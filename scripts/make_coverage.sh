#!/usr/bin/env bash
# Mede a cobertura do backend C (src/*.c) e gera docs/COVERAGE.md.
#
# Como funciona: compila cada src/*.c como um .o instrumentado (--coverage) UMA
# vez, e TODOS os executores de teste linkam contra esses MESMOS .o (mesmos
# .gcno). Assim a cobertura agrega de tres fontes que compartilham os objetos:
#   1. testes C diretos (test_alloc/ops/bool/string)  -- linkados contra a .so;
#   2. testes Lua (carregam a mesma .so via FFI);
#   3. test_allocfail (--wrap malloc/realloc, exige link proprio dos .o) --
#      antes ficava FORA da medicao (divida tecnica); agora entra, pois linka
#      contra os mesmos .o instrumentados e seus .gcda agregam no gcov.
# Resultado: os caminhos de erro (OOM) e o lifecycle/ops de string passam a
# contar -- o numero reflete TODOS os testes do projeto, nao so os via .so/Lua.
#
# Uso (da raiz do projeto):  bash scripts/make_coverage.sh
# Requer: gcc, luajit, gcov. (Linux -- gcov nao e confiavel no Windows.)
set -euo pipefail

SRCS="smaug_core smaug_ops_f64 smaug_ops_i64 smaug_ops_bool smaug_str smaug_ops_str"
COVDIR=cov
OUT=docs/COVERAGE.md

rm -rf "$COVDIR" build
mkdir -p "$COVDIR" build

# 1. cada src como .o instrumentado (gera um .gcno por src em $COVDIR)
objs=""
for s in $SRCS; do
    gcc -std=c11 -fPIC --coverage -O0 -I./include -c "src/$s.c" -o "$COVDIR/$s.o"
    objs="$objs $COVDIR/$s.o"
done

# 2. .so a partir dos MESMOS .o (compartilha .gcno com os executores de teste)
gcc --coverage -shared -o "$COVDIR/libsmaug.so" $objs

# 3. testes C diretos, linkados contra a .so (sem --wrap)
for t in test_alloc test_ops test_ops_edge test_bool test_string; do
    gcc -std=c11 -O0 -I./include "tests/$t.c" -L"./$COVDIR" -lsmaug -lm -o "$COVDIR/$t"
    LD_LIBRARY_PATH="./$COVDIR" "./$COVDIR/$t" >/dev/null 2>&1
done

# 4. testes Lua contra a MESMA .so (o loader procura em build/)
cp "$COVDIR/libsmaug.so" build/libsmaug.so
for t in test_series test_dataset test_edge test_special test_fillna test_props test_i64 test_string; do
    luajit "tests/$t.lua" >/dev/null 2>&1
done

# 5. test_allocfail: precisa de --wrap (age no link do executavel, nao na .so),
#    entao linka contra os MESMOS .o instrumentados + --coverage (puxa libgcov).
#    Seus .gcda caem nos mesmos arquivos e agregam com os passos anteriores.
gcc -std=c11 -O0 --coverage -I./include \
    -Wl,--wrap=malloc -Wl,--wrap=realloc \
    tests/test_allocfail.c $objs -lm -o "$COVDIR/test_allocfail"
"./$COVDIR/test_allocfail" >/dev/null 2>&1

# 6. agrega com gcov e monta a tabela
commit=$(git rev-parse --short HEAD 2>/dev/null || echo "sem-git")
cdate=$(git log -1 --format=%ci 2>/dev/null || date "+%Y-%m-%d %H:%M:%S")

tot_lines=0; cov_lines=0; tot_br=0; cov_br=0
rows=""
for obj in $SRCS; do
    out=$(gcov -b -o "$COVDIR" "$COVDIR/$obj.gcda" 2>/dev/null || true)
    lp=$(echo "$out" | grep -m1 "Lines executed" | grep -oE "[0-9.]+%" | head -1 | tr -d '%')
    ln=$(echo "$out" | grep -m1 "Lines executed" | grep -oE "of [0-9]+" | grep -oE "[0-9]+")
    bp=$(echo "$out" | grep -m1 "Taken at least once" | grep -oE "[0-9.]+%" | head -1 | tr -d '%')
    bn=$(echo "$out" | grep -m1 "Taken at least once" | grep -oE "of [0-9]+" | grep -oE "[0-9]+")
    lp=${lp:-0}; ln=${ln:-0}; bp=${bp:-0}; bn=${bn:-0}
    rows="${rows}| \`$obj.c\` | ${lp}% | ${bp}% |"$'\n'
    cl=$(awk "BEGIN{printf \"%d\", $ln*$lp/100}")
    cb=$(awk "BEGIN{printf \"%d\", $bn*$bp/100}")
    tot_lines=$((tot_lines+ln)); cov_lines=$((cov_lines+cl))
    tot_br=$((tot_br+bn)); cov_br=$((cov_br+cb))
done
line_pct=$(awk "BEGIN{printf \"%.2f\", ($tot_lines? $cov_lines*100/$tot_lines : 0)}")
br_pct=$(awk "BEGIN{printf \"%.2f\", ($tot_br? $cov_br*100/$tot_br : 0)}")

{
  echo "# Cobertura -- Smaug (backend C)"
  echo ""
  echo "> **Arquivo gerado automaticamente** por \`scripts/make_coverage.sh\`"
  echo "> (\`make coverage\`). Nao editar a mao -- e regenerado a cada medicao."
  echo ""
  echo "- Commit medido: \`$commit\`"
  echo "- Data do commit: $cdate"
  echo "- Linha: metrica basica.  **Branch** (\"taken at least once\"): metrica"
  echo "  rigorosa, padrao SQLite/avionica -- e a que perseguimos rumo a 100%."
  echo "- **Mede TODOS os testes do projeto**: testes C diretos, testes Lua (via"
  echo "  FFI) e \`test_allocfail\` (falha de alocacao). Todos linkam contra os"
  echo "  mesmos .o instrumentados, entao os caminhos de erro (OOM) contam."
  echo ""
  echo "| Arquivo | Linhas | Branch (taken) |"
  echo "|---------|--------|----------------|"
  printf "%s" "$rows"
  echo "| **TOTAL (ponderado)** | **${line_pct}%** | **${br_pct}%** |"
  echo ""g
  echo ""
  echo "## Norte de longo prazo (cover real, padrao SQLite)"
  echo ""
  echo "Meta futura: **branch 100%** (cobertura MC/DC, como o SQLite). Com a"
  echo "agregacao de todos os testes, os ramos descobertos restantes sao"
  echo "majoritariamente: (a) caminhos de erro de string ainda nao exercitados"
  echo "pelo allocfail (que cobre f64/i64/core, nao string -- ver divida); (b)"
  echo "ramos de valores especiais (NaN/Inf/sentinela) menos testados. Evolucao"
  echo "incremental, medida a cada commit."
} > "$OUT"

echo "COVERAGE gerado: $OUT"
echo "  Linha total:  ${line_pct}%"
echo "  Branch total: ${br_pct}%"

# limpa artefatos de cobertura (nao poluir a arvore)
rm -rf "$COVDIR" build
