#!/usr/bin/env bash
# scripts/build.sh
#
# Build + testes completos do Smaug no Linux/macOS.
# Equivalente ao build_win.ps1, com Valgrind e coverage adicionais.
#
# O que faz (por padrao, tudo):
#   1. Compila o backend C em build/libsmaug.so
#   2. Compila e roda os testes C (plain + allocfail --wrap)
#   3. Roda os testes de stress
#   4. Roda os testes Lua com luajit
#   5. (se --valgrind)  roda cada binario de teste sob Valgrind
#   6. (se --coverage)  gera docs/COVERAGE.md via gcov
#   7. Roda scripts/parity/parity.sh — gera docs/PARITY_REPORT.md
#      (indicador, nunca quebra o build)
#   8. Regenera docs/MANIFEST.txt
#
# Uso:
#   bash scripts/build.sh                  # tudo (sem Valgrind/coverage)
#   bash scripts/build.sh --valgrind       # + Valgrind em todos os testes C
#   bash scripts/build.sh --coverage       # + coverage (gcov)
#   bash scripts/build.sh --all            # + Valgrind + coverage
#   bash scripts/build.sh --skip-lua       # pula os testes Lua
#   bash scripts/build.sh --skip-stress    # pula os testes de stress
#   bash scripts/build.sh --skip-manifest  # pula o manifest
#
# Combinacoes validas:
#   bash scripts/build.sh --all --skip-stress

set -euo pipefail

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------
DO_VALGRIND=0
DO_COVERAGE=0
SKIP_LUA=0
SKIP_STRESS=0
SKIP_MANIFEST=0

for arg in "$@"; do
    case "$arg" in
        --valgrind)      DO_VALGRIND=1 ;;
        --coverage)      DO_COVERAGE=1 ;;
        --all)           DO_VALGRIND=1; DO_COVERAGE=1 ;;
        --skip-lua)      SKIP_LUA=1 ;;
        --skip-stress)   SKIP_STRESS=1 ;;
        --skip-manifest) SKIP_MANIFEST=1 ;;
        *) echo "Opcao desconhecida: $arg" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Cores e helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'
YELLOW='\033[0;33m'; RESET='\033[0m'

info()    { echo -e "${CYAN}$*${RESET}"; }
ok()      { echo -e "${GREEN}$*${RESET}"; }
warn()    { echo -e "${YELLOW}$*${RESET}"; }
fail()    { echo -e "${RED}$*${RESET}"; }

PASS_COUNT=0
FAIL_COUNT=0

check_tool() {
    if ! command -v "$1" &>/dev/null; then
        warn "  $1 nao encontrado — ${2:-}"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Ferramentas
# ---------------------------------------------------------------------------
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

info "Projeto: $ROOT"

GCC=$(command -v gcc 2>/dev/null || true)
if [[ -z "$GCC" ]]; then
    fail "ERRO: gcc nao encontrado. Instale o gcc e tente novamente."
    exit 1
fi
echo "gcc:    $GCC"

LUAJIT=$(command -v luajit 2>/dev/null || true)
if [[ -z "$LUAJIT" ]]; then
    warn "luajit: nao encontrado — testes Lua serao pulados"
    SKIP_LUA=1
else
    echo "luajit: $LUAJIT"
fi

HAS_VALGRIND=0
if [[ $DO_VALGRIND -eq 1 ]]; then
    if check_tool valgrind "Valgrind sera pulado"; then
        HAS_VALGRIND=1
        echo "valgrind: $(command -v valgrind)"
    else
        DO_VALGRIND=0
    fi
fi

HAS_GCOV=0
if [[ $DO_COVERAGE -eq 1 ]]; then
    if check_tool gcov "coverage sera pulado"; then
        HAS_GCOV=1
    else
        DO_COVERAGE=0
    fi
fi

# ---------------------------------------------------------------------------
# Listas de teste (fonte unica — espelha o Makefile)
# ---------------------------------------------------------------------------
# Fontes do backend C: descobre TODOS os src/*.c automaticamente, para nunca
# dessincronizar quando um novo .c entra (espelha build_win.ps1 / A3, item 12.29).
# O glob do bash expande ordenado alfabeticamente → build reproduzível.
SRCS=(src/*.c)
if [[ ${#SRCS[@]} -eq 0 || ! -e "${SRCS[0]}" ]]; then
    echo "ERRO: nenhum fonte encontrado em src/*.c" >&2
    exit 1
fi

C_TESTS_PLAIN=(test_alloc test_ops test_ops_edge test_bool \
               test_bool_lifecycle test_string test_cow test_io_c test_datetime_c \
               test_ops_window test_astype)
C_TESTS_WRAP=(test_allocfail)
C_TESTS_STRESS=(test_stress)
LUA_TESTS=(core/test_keys \
           series/test_constructors series/test_access series/test_reduce \
           series/test_stat series/test_window series/test_predicates \
           series/test_selection series/test_str series/test_dt series/test_categorical \
           dataset/test_core dataset/test_relational dataset/test_stat dataset/test_io_support \
           io/test_csv io/test_json \
           props/test_props props/test_integration)

CFLAGS=(-std=c11 -fPIC -Wall -Wextra -O2 -I./include)
TEST_CFLAGS=(-std=c11 -g -O0 -Wall -Wextra -I./include)
WRAP_FLAGS=(-Wl,--wrap=malloc -Wl,--wrap=realloc -Wl,--wrap=calloc -Wl,--wrap=strdup)

ALL_PASS=1
run_result() {
    local name="$1" out="$2" rc="$3"
    if [[ $rc -eq 0 ]]; then
        echo -e "  ${name}${RESET}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        fail "  FALHOU: $name"
        [[ -n "$out" ]] && echo "$out"
        ALL_PASS=0
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# ---------------------------------------------------------------------------
# 1. Build
# ---------------------------------------------------------------------------
echo ""
info "== Compilando build/libsmaug.so =="
mkdir -p build
# Exporta a lista de fontes descoberta (uma por linha) para o eixo 14 auditar
# exatamente o que foi compilado — sem lista hardcoded, sem defasagem (12.29/A3).
printf '%s\n' "${SRCS[@]}" > build/SOURCES
gcc "${CFLAGS[@]}" -shared -o build/libsmaug.so "${SRCS[@]}"
ok "OK -> build/libsmaug.so"

# ---------------------------------------------------------------------------
# 2. Testes C (plain)
# ---------------------------------------------------------------------------
echo ""
info "== Testes em C =="

for t in "${C_TESTS_PLAIN[@]}"; do
    printf "  CC    %-20s" "$t"
    gcc "${TEST_CFLAGS[@]}" "tests/c/$t.c" "${SRCS[@]}" -lm -o "build/$t" 2>/tmp/cc_err
    if [[ $? -ne 0 ]]; then
        fail "FALHOU (compilacao)"; cat /tmp/cc_err; ALL_PASS=0; continue
    fi
    out=$(./build/$t 2>&1)
    rc=$?
    echo "-> $out"
    [[ $rc -ne 0 ]] && { ALL_PASS=0; FAIL_COUNT=$((FAIL_COUNT+1)); } || PASS_COUNT=$((PASS_COUNT+1))
done

for t in "${C_TESTS_WRAP[@]}"; do
    printf "  CC    %-20s" "$t (--wrap)"
    gcc "${TEST_CFLAGS[@]}" "${WRAP_FLAGS[@]}" "tests/c/$t.c" "${SRCS[@]}" -lm -o "build/$t" 2>/tmp/cc_err
    if [[ $? -ne 0 ]]; then
        fail "FALHOU (compilacao)"; cat /tmp/cc_err; ALL_PASS=0; continue
    fi
    out=$(./build/$t 2>&1)
    rc=$?
    echo "-> $out"
    [[ $rc -ne 0 ]] && { ALL_PASS=0; FAIL_COUNT=$((FAIL_COUNT+1)); } || PASS_COUNT=$((PASS_COUNT+1))
done

# ---------------------------------------------------------------------------
# 3. Testes de stress
# ---------------------------------------------------------------------------
if [[ $SKIP_STRESS -eq 0 ]]; then
    echo ""
    info "== Testes de Stress =="
    for t in "${C_TESTS_STRESS[@]}"; do
        printf "  CC    %-20s" "$t"
        gcc "${TEST_CFLAGS[@]}" "tests/c/$t.c" "${SRCS[@]}" -lm -o "build/$t" 2>/tmp/cc_err
        if [[ $? -ne 0 ]]; then
            fail "FALHOU (compilacao)"; cat /tmp/cc_err; ALL_PASS=0; continue
        fi
        out=$(./build/$t 2>&1)
        rc=$?
        last=$(echo "$out" | tail -1)
        echo "-> $last"
        [[ $rc -ne 0 ]] && { ALL_PASS=0; FAIL_COUNT=$((FAIL_COUNT+1)); } || PASS_COUNT=$((PASS_COUNT+1))
    done
fi

# ---------------------------------------------------------------------------
# 4. Testes Lua
# ---------------------------------------------------------------------------
if [[ $SKIP_LUA -eq 0 ]]; then
    echo ""
    info "== Testes em Lua =="
    for t in "${LUA_TESTS[@]}"; do
        out=$(luajit "tests/$t.lua" 2>&1)
        rc=$?
        if [[ $rc -eq 0 ]]; then
            echo "  $out"
            PASS_COUNT=$((PASS_COUNT+1))
        else
            fail "  FALHOU: $t"
            echo "$out"
            ALL_PASS=0
            FAIL_COUNT=$((FAIL_COUNT+1))
        fi
    done
fi

# ---------------------------------------------------------------------------
# 5. Valgrind
# ---------------------------------------------------------------------------
if [[ $DO_VALGRIND -eq 1 && $HAS_VALGRIND -eq 1 ]]; then
    echo ""
    info "== Valgrind =="
    ALL_C_TESTS=("${C_TESTS_PLAIN[@]}" "${C_TESTS_WRAP[@]}")
    [[ $SKIP_STRESS -eq 0 ]] && ALL_C_TESTS+=("${C_TESTS_STRESS[@]}")
    for t in "${ALL_C_TESTS[@]}"; do
        printf "  VALGRIND %-20s" "$t"
        vg_out=$(valgrind --leak-check=full --error-exitcode=1 "./build/$t" 2>&1)
        rc=$?
        summary=$(echo "$vg_out" | grep "ERROR SUMMARY" | head -1)
        if [[ $rc -eq 0 ]]; then
            echo "-> OK ($summary)"
            PASS_COUNT=$((PASS_COUNT+1))
        else
            fail "-> FALHOU"
            echo "$vg_out" | tail -15
            ALL_PASS=0
            FAIL_COUNT=$((FAIL_COUNT+1))
        fi
    done
fi

# ---------------------------------------------------------------------------
# 6. Coverage
# ---------------------------------------------------------------------------
if [[ $DO_COVERAGE -eq 1 && $HAS_GCOV -eq 1 ]]; then
    echo ""
    info "== Coverage (gcov) =="
    bash scripts/make_coverage.sh
fi

# ---------------------------------------------------------------------------
# 7. Paridade da API (indicador permanente, nunca quebra build)
# ---------------------------------------------------------------------------
if [[ -f scripts/parity/parity.sh && $SKIP_LUA -eq 0 ]]; then
    echo ""
    info "== Paridade da API =="
    bash scripts/parity/parity.sh || warn "  (parity reportou problemas — ver docs/PARITY_REPORT.md)"
fi

# ---------------------------------------------------------------------------
# 8. Manifest
# ---------------------------------------------------------------------------
if [[ $SKIP_MANIFEST -eq 0 ]]; then
    echo ""
    info "== Manifest =="
    if [[ -f scripts/make_manifest.sh ]]; then
        bash scripts/make_manifest.sh
    else
        warn "  make_manifest.sh nao encontrado — pulando"
    fi
fi

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
echo ""
if [[ $ALL_PASS -eq 1 ]]; then
    ok "TUDO PASSOU."
    exit 0
else
    fail "FALHOU: $FAIL_COUNT suite(s)."
    exit 1
fi
