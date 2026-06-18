#!/usr/bin/env bash
# scripts/parity/parity.sh
# Roda todos os scripts de paridade e gera docs/PARITY_REPORT.md.
# Princípio: cada script é independente. Falha em um não impede os outros.

set -u
cd "$(dirname "$0")/../.." || exit 1

OUT=docs/PARITY_REPORT.md
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Header do relatório
cat > "$OUT" <<EOF
# Smaug — Relatório de Paridade

> Arquivo gerado por \`bash scripts/parity/parity.sh\`. **Não editar à mão.**
> Decisões conscientes de não-paridade ficam em \`scripts/parity/exceptions.txt\`.

Convenção de status:

- 🟩 paridade presente
- ⬜ não aplicável (exceção registrada em \`exceptions.txt\`)
- 🟨 ausência sem registro — suspeita, requer revisão humana
- 🟥 inconsistência clara — gap real

Gerado em: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF

# Rodar cada eixo
EIXOS=(
    01_dtypes
    02_series_dataset
    03_c_lua_mirror
    04_anel2
    05_io_dtypes
    06_return_types
    07_null_handling
    08_naming
    09_sentinels
    10_lifecycle
    11_test_coverage
    12_docs_sync
)

FAILED=()
for eixo in "${EIXOS[@]}"; do
    SCRIPT="scripts/parity/${eixo}.lua"
    if [ ! -f "$SCRIPT" ]; then
        echo "  AVISO  $eixo: script não encontrado"
        FAILED+=("$eixo")
        continue
    fi
    if luajit "$SCRIPT" >> "$OUT" 2>"$TMPDIR/$eixo.err"; then
        echo "  OK     $eixo"
    else
        echo "  FALHOU $eixo"
        cat "$TMPDIR/$eixo.err" | sed 's/^/         /'
        FAILED+=("$eixo")
    fi
done

# Footer
cat >> "$OUT" <<EOF

---

## Resumo executivo

EOF

# Contagens globais
WARN_COUNT=$(grep -c "🟨" "$OUT")
ERR_COUNT=$(grep -c "🟥" "$OUT")
OK_COUNT=$(grep -o "🟩" "$OUT" | wc -l)
EXC_COUNT=$(grep -o "⬜" "$OUT" | wc -l)

cat >> "$OUT" <<EOF

**Contagem global de status no relatório:**

- 🟩 paridade: $OK_COUNT
- ⬜ exceção registrada: $EXC_COUNT
- 🟨 suspeita (revisar): $WARN_COUNT
- 🟥 inconsistência clara: $ERR_COUNT

EOF

cat >> "$OUT" <<EOF

## Como usar este relatório

1. Procure por 🟨 — cada um é um candidato a gap real ou exceção a registrar.
2. Se for decisão consciente, adicione em \`scripts/parity/exceptions.txt\`.
3. Se for gap real, registre em \`Roadmap.md\` ou corrija e rode novamente.
4. Procure por 🟥 — sempre gap real, exige ação.
EOF

echo
echo "Relatório: $OUT"
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "Eixos que falharam: ${FAILED[*]}"
fi
# Indicador, não veredito: NUNCA quebra build, mesmo se algum eixo falhar.
exit 0
