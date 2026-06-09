#!/usr/bin/env bash
# Mede a cobertura do backend C (src/*.c) e gera docs/COVERAGE.md.
#
# Como funciona: compila cada src/*.c como um .o instrumentado (--coverage) UMA
# vez; TODOS os executores de teste linkam contra esses MESMOS .o (mesmos .gcno),
# entao os .gcda agregam de tres fontes:
#   1. testes C diretos (incl. test_cow e test_stress) -- linkados contra a .so;
#   2. testes Lua (carregam a mesma .so via FFI);
#   3. test_allocfail (--wrap malloc/realloc) -- linka contra os MESMOS .o.
#
# Contagem EXATA: as porcentagens sao derivadas das contagens reais parseadas do
# texto .gcov (linhas executadas; ramos "taken at least once"), NAO reconstruidas
# a partir de porcentagem arredondada. O mesmo parse emite o mapa real de ramos
# descobertos (arquivo:linha), que vira a secao de alvos de endurecimento.
#
# Uso (da raiz do projeto):  bash scripts/make_coverage.sh
# Requer: gcc, luajit, gcov. (Linux -- gcov nao e confiavel no Windows.)
set -euo pipefail

command -v luajit >/dev/null 2>&1 || { echo "ERRO: luajit nao encontrado (necessario para agregar os testes Lua)."; exit 1; }

SRCS="smaug_core smaug_ops_f64 smaug_ops_i64 smaug_ops_bool smaug_str smaug_ops_str"
# Tudo que exercita o backend. Se test_stress deixar a medicao lenta demais,
# pode remove-lo daqui -- ele cobre majoritariamente ramos que ops ja pega.
C_TESTS="test_alloc test_ops test_ops_edge test_bool test_string test_cow test_stress"
LUA_TESTS="test_series test_dataset test_edge test_special test_fillna test_props test_i64 test_string"
COVDIR=cov
OUT=docs/COVERAGE.md

# build/ NAO e destruido (ao contrario da versao antiga, que fazia rm -rf build):
# so gerenciamos build/libsmaug.so. A lib instrumentada precisa ser o 1o candidato
# do loader Lua, senao uma .so antiga (de 'make') faria sombra e a medicao Lua
# contaria ZERO. Ao final, removemos so a nossa lib (artefato descartavel: refaca
# com 'make'); o resto de build/ fica intacto.
mkdir -p "$COVDIR" build

cleanup() {
    rm -rf "$COVDIR"
    rm -f ./*.gcov
    rm -f build/libsmaug.so
}
trap cleanup EXIT

# 1. cada src como .o instrumentado (gera um .gcno por src em $COVDIR)
objs=""
for s in $SRCS; do
    gcc -std=c11 -fPIC --coverage -O0 -I./include -c "src/$s.c" -o "$COVDIR/$s.o"
    objs="$objs $COVDIR/$s.o"
done

# 2. .so a partir dos MESMOS .o + copia pra build/ (1o candidato do loader = instrumentado)
gcc --coverage -shared -o "$COVDIR/libsmaug.so" $objs
cp "$COVDIR/libsmaug.so" build/libsmaug.so

# 3. testes C diretos (incl. cow e stress), linkados contra a .so
for t in $C_TESTS; do
    gcc -std=c11 -O0 -I./include "tests/$t.c" -L"./$COVDIR" -lsmaug -lm -o "$COVDIR/$t"
    LD_LIBRARY_PATH="./$COVDIR" "./$COVDIR/$t" >/dev/null 2>&1
done

# 4. testes Lua contra a MESMA .so (loader acha build/libsmaug.so instrumentada)
for t in $LUA_TESTS; do
    luajit "tests/$t.lua" >/dev/null 2>&1
done

# 5. test_allocfail: precisa de --wrap (age no link do executavel), entao linka
#    contra os MESMOS .o instrumentados + --coverage. Seus .gcda agregam.
gcc -std=c11 -O0 --coverage -I./include \
    -Wl,--wrap=malloc -Wl,--wrap=realloc \
    tests/test_allocfail.c $objs -lm -o "$COVDIR/test_allocfail"
"./$COVDIR/test_allocfail" >/dev/null 2>&1

# 6. agrega com contagem EXATA (parse do texto .gcov)
commit=$(git rev-parse --short HEAD 2>/dev/null || echo "sem-git")
cdate=$(git log -1 --format=%ci 2>/dev/null || date "+%Y-%m-%d %H:%M:%S")

bar() {  # $1 = porcentagem inteira -> barra de 10 blocos
    local v=$1 f e i s=""
    f=$(( v / 10 ))
    if [ "$f" -gt 10 ]; then f=10; fi
    if [ "$f" -lt 0 ]; then f=0; fi
    e=$(( 10 - f ))
    for ((i=0; i<f; i++)); do s="${s}█"; done
    for ((i=0; i<e; i++)); do s="${s}░"; done
    printf "%s" "$s"
}

tot_l=0; cov_l=0; tot_b=0; cov_b=0
rows=""; map=""
for s in $SRCS; do
    gcov -b -o "$COVDIR" "$COVDIR/$s.gcda" >/dev/null 2>&1 || true
    g="$s.c.gcov"
    [ -f "$g" ] || continue

    # Linhas: contagem numerica = executada; ##### = instrumentada nao-executada.
    lc=$(grep -cE '^ *[0-9]+: *[0-9]+:' "$g" || true)
    lm=$(grep -cE '^ *#####: *[0-9]+:' "$g" || true)
    lt=$(( lc + lm ))

    # Branches: total = linhas '^branch'; coberto = 'taken' com pct >0
    # (exclui 'taken 0%' e 'never executed' -- a metrica "taken at least once").
    bt=$(grep -c '^branch' "$g" || true)
    bc=$(grep -cE '^branch +[0-9]+ taken [1-9]' "$g" || true)

    lp=$(awk "BEGIN{printf \"%.2f\", ($lt? 100*$lc/$lt : 0)}")
    bp=$(awk "BEGIN{printf \"%.2f\", ($bt? 100*$bc/$bt : 0)}")
    lpi=$(awk "BEGIN{printf \"%.0f\", $lp}")
    bpi=$(awk "BEGIN{printf \"%.0f\", $bp}")

    rows="${rows}| \`$s.c\` | \`$lc/$lt = ${lp}%\` \`[$(bar "$lpi")]\` | \`$bc/$bt = ${bp}%\` \`[$(bar "$bpi")]\` |"$'\n'

    tot_l=$(( tot_l + lt )); cov_l=$(( cov_l + lc ))
    tot_b=$(( tot_b + bt )); cov_b=$(( cov_b + bc ))

    # Mapa real de ramos descobertos: rastreia a linha-fonte corrente e, ao ver
    # um branch 'taken 0%' / 'never executed', registra arquivo:linha (uma vez).
    uncov=$(awk -v f="$s.c" '
        /^ *[^:]+: *[0-9]+:/ {
            i = index($0, ":"); r = substr($0, i+1)
            j = index(r, ":"); ln = substr(r, 1, j-1); gsub(/ /, "", ln)
            cur = ln; csrc = substr(r, j+1); done = 0; next
        }
        /^branch/ {
            if (($0 ~ /taken 0%/ || $0 ~ /never executed/) && !done) {
                t = csrc; sub(/^[ \t]+/, "", t)
                printf "- `%s:%s` — %s\n", f, cur, t
                done = 1
            }
        }
    ' "$g" || true)
    if [ -n "$uncov" ]; then
        cnt=$(printf "%s\n" "$uncov" | grep -c . || true)
        map="${map}**\`$s.c\`** — ${cnt} linha(s) com ramo descoberto:"$'\n'"${uncov}"$'\n\n'
    fi

    rm -f "$g"
done

line_pct=$(awk "BEGIN{printf \"%.2f\", ($tot_l? 100*$cov_l/$tot_l : 0)}")
br_pct=$(awk "BEGIN{printf \"%.2f\", ($tot_b? 100*$cov_b/$tot_b : 0)}")
lpi=$(awk "BEGIN{printf \"%.0f\", $line_pct}")
bpi=$(awk "BEGIN{printf \"%.0f\", $br_pct}")

{
    echo "# Cobertura -- Smaug (backend C)"
    echo ""
    echo "> **Arquivo gerado automaticamente** por \`scripts/make_coverage.sh\` (\`make coverage\`)."
    echo "> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %."
    echo ""
    echo "- Commit medido: \`$commit\`  |  Data: $cdate"
    echo "- **Branch** (\"taken at least once\"): metrica rigorosa (padrao SQLite/avionica) -- e a que perseguimos rumo a 100%."
    echo "- Agrega TODOS os testes: C diretos (incl. \`test_cow\` e \`test_stress\`), Lua (FFI) e \`test_allocfail\` (OOM)."
    echo ""
    echo "| Arquivo | Linhas | Branch (taken) |"
    echo "| :--- | :--- | :--- |"
    printf "%s" "$rows"
    echo "| **TOTAL** | \`$cov_l/$tot_l = ${line_pct}%\` \`[$(bar "$lpi")]\` | \`$cov_b/$tot_b = ${br_pct}%\` \`[$(bar "$bpi")]\` |"
    echo ""
    echo "## Ramos descobertos (mapa real, derivado do .gcov)"
    echo ""
    if [ -n "$map" ]; then
        echo "Alvos concretos de endurecimento rumo a **branch 100%** (MC/DC):"
        echo ""
        printf "%s" "$map"
    else
        echo "Nenhum ramo descoberto. 🎯"
    fi
} > "$OUT"

echo "COVERAGE gerado: $OUT"
echo "  Linha:  $cov_l/$tot_l = ${line_pct}%"
echo "  Branch: $cov_b/$tot_b = ${br_pct}%"
