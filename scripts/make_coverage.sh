#!/usr/bin/env bash
# Mede a cobertura do backend C (src/*.c) e gera docs/COVERAGE.md.
#
# Como funciona: compila UMA .so instrumentada (--coverage), linka os testes C
# contra ela, roda os testes C E os testes Lua (que carregam a mesma .so via
# FFI) — assim a cobertura acumula os dois caminhos de execução. Depois agrega
# com gcov e escreve um relatório em Markdown.
#
# Uso (da raiz do projeto):  bash scripts/make_coverage.sh
# Requer: gcc, luajit, gcov. (Linux — gcov não é confiável no Windows.)
set -euo pipefail

SRCS="smaug_core smaug_ops_f64 smaug_ops_i64 smaug_ops_bool"
COVDIR=cov
OUT=docs/COVERAGE.md

rm -rf "$COVDIR" build
mkdir -p "$COVDIR" build

# 1. .so instrumentada
gcc -std=c11 -fPIC --coverage -O0 -I./include -shared \
    -o "$COVDIR/libsmaug.so" \
    src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c src/smaug_ops_bool.c

# 2. testes C linkados contra a .so instrumentada
for t in test_alloc test_ops test_bool; do
    gcc -std=c11 -O0 -I./include "tests/$t.c" -L"./$COVDIR" -lsmaug -lm -o "$COVDIR/$t"
done

# 3. roda os testes C (LD_LIBRARY_PATH aponta pra .so instrumentada)
for t in test_alloc test_ops test_bool; do
    LD_LIBRARY_PATH="./$COVDIR" "./$COVDIR/$t" >/dev/null 2>&1
done

# 4. roda os testes Lua contra a MESMA .so (o loader procura em build/)
cp "$COVDIR/libsmaug.so" build/libsmaug.so
for t in test_series test_dataset test_edge test_special test_fillna test_props; do
    luajit "tests/$t.lua" >/dev/null 2>&1
done

# 5. agrega com gcov e monta a tabela
commit=$(git rev-parse --short HEAD 2>/dev/null || echo "sem-git")
cdate=$(git log -1 --format=%ci 2>/dev/null || date "+%Y-%m-%d %H:%M:%S")

tot_lines=0; cov_lines=0; tot_br=0; cov_br=0
rows=""
for obj in $SRCS; do
    out=$(gcov -b -o "$COVDIR" "$COVDIR/libsmaug.so-$obj.gcda" 2>/dev/null || true)
    lp=$(echo "$out" | grep -m1 "Lines executed" | grep -oE "[0-9.]+%" | head -1 | tr -d '%')
    ln=$(echo "$out" | grep -m1 "Lines executed" | grep -oE "of [0-9]+" | grep -oE "[0-9]+")
    bp=$(echo "$out" | grep -m1 "Taken at least once" | grep -oE "[0-9.]+%" | head -1 | tr -d '%')
    bn=$(echo "$out" | grep -m1 "Taken at least once" | grep -oE "of [0-9]+" | grep -oE "[0-9]+")
    lp=${lp:-0}; ln=${ln:-0}; bp=${bp:-0}; bn=${bn:-0}
    rows="${rows}| \`$obj.c\` | ${lp}% | ${bp}% |"$'\n'
    # acumula para a média ponderada
    cl=$(awk "BEGIN{printf \"%d\", $ln*$lp/100}")
    cb=$(awk "BEGIN{printf \"%d\", $bn*$bp/100}")
    tot_lines=$((tot_lines+ln)); cov_lines=$((cov_lines+cl))
    tot_br=$((tot_br+bn)); cov_br=$((cov_br+cb))
done
line_pct=$(awk "BEGIN{printf \"%.2f\", ($tot_lines? $cov_lines*100/$tot_lines : 0)}")
br_pct=$(awk "BEGIN{printf \"%.2f\", ($tot_br? $cov_br*100/$tot_br : 0)}")

{
  echo "# Cobertura — Smaug (backend C)"
  echo ""
  echo "> **Arquivo gerado automaticamente** por \`scripts/make_coverage.sh\`"
  echo "> (\`make coverage\`). Não editar à mão — é regenerado a cada medição."
  echo ""
  echo "- Commit medido: \`$commit\`"
  echo "- Data do commit: $cdate"
  echo "- Linha: métrica básica.  **Branch** (\"taken at least once\"): métrica"
  echo "  rigorosa, padrão SQLite/aviônica — é a que perseguimos rumo a 100%."
  echo ""
  echo "| Arquivo | Linhas | Branch (taken) |"
  echo "|---------|--------|----------------|"
  printf "%s" "$rows"
  echo "| **TOTAL (ponderado)** | **${line_pct}%** | **${br_pct}%** |"
  echo ""
  echo "## Gate da Fase 1.6"
  echo ""
  echo "- Critério atual (opção A): **linha ≥ 90%**."
  echo "- Status: $(awk "BEGIN{print ($line_pct>=90)?\"ATINGIDO ✅\":\"NÃO atingido ❌ (faltam \"  90-$line_pct  \" pontos)\"}")"
  echo ""
  echo "## Norte de longo prazo (cover real, padrão SQLite)"
  echo ""
  echo "Meta futura: **branch 100%** (cobertura MC/DC, como o SQLite). Os ramos"
  echo "não cobertos hoje são majoritariamente **caminhos de erro** (falha de"
  echo "alocação, entrada inválida) — atacados pelo \`test_allocfail.c\` e por"
  echo "testes de entrada inválida. Evolução incremental, medida a cada commit."
} > "$OUT"

echo "COVERAGE gerado: $OUT"
echo "  Linha total:  ${line_pct}%"
echo "  Branch total: ${br_pct}%"

# limpa artefatos de cobertura (não poluir a árvore)
rm -rf "$COVDIR" build
