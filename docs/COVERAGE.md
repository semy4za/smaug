# Cobertura — Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh`
> (`make coverage`). Não editar à mão — é regenerado a cada medição.

- Commit medido: `00da973`
- Data do commit: 2026-06-03 17:11:24 -0300
- Linha: métrica básica.  **Branch** ("taken at least once"): métrica
  rigorosa, padrão SQLite/aviônica — é a que perseguimos rumo a 100%.

| Arquivo | Linhas | Branch (taken) |
|---------|--------|----------------|
| `smaug_core.c` | 92.06% | 56.00% |
| `smaug_ops_f64.c` | 81.01% | 58.33% |
| `smaug_ops_i64.c` | 96.28% | 67.83% |
| `smaug_ops_bool.c` | 100.00% | 77.56% |
| **TOTAL (ponderado)** | **90.54%** | **64.34%** |

## Gate da Fase 1.6

- Critério do gate (Fase 1.6): **linha ≥ 90%**.
- Status: ATINGIDO ✅

## Norte de longo prazo (cover real, padrão SQLite)

Meta futura: **branch 100%** (cobertura MC/DC, como o SQLite). Os ramos
não cobertos hoje são majoritariamente **caminhos de erro** (falha de
alocação, entrada inválida) — atacados pelo `test_allocfail.c` e por
testes de entrada inválida. Evolução incremental, medida a cada commit.

> **Nota:** `test_allocfail.c` (falha de alocação via `--wrap`) exercita
> caminhos de erro adicionais **não refletidos neste número**, pois usa
> instrumentação incompatível com a `.so` medida aqui. Agregá-lo à medição
> é dívida técnica registrada. Ele roda em `make test`/`make valgrind`.
