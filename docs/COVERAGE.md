# Cobertura — Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh`
> (`make coverage`). Não editar à mão — é regenerado a cada medição.

- Commit medido: `558eb33`
- Data do commit: 2026-06-02 21:48:36 -0300
- Linha: métrica básica.  **Branch** ("taken at least once"): métrica
  rigorosa, padrão SQLite/aviônica — é a que perseguimos rumo a 100%.

| Arquivo | Linhas | Branch (taken) |
|---------|--------|----------------|
| `smaug_core.c` | 89.15% | 55.48% |
| `smaug_ops_f64.c` | 81.01% | 58.33% |
| `smaug_ops_i64.c` | 56.61% | 39.92% |
| `smaug_ops_bool.c` | 100.00% | 77.56% |
| **TOTAL (ponderado)** | **77.14%** | **55.30%** |

## Gate da Fase 1.6

- Critério atual (opção A): **linha ≥ 90%**.
- Status: NÃO atingido ❌ (faltam 12.86 pontos)

## Norte de longo prazo (cover real, padrão SQLite)

Meta futura: **branch 100%** (cobertura MC/DC, como o SQLite). Os ramos
não cobertos hoje são majoritariamente **caminhos de erro** (falha de
alocação, entrada inválida) — atacados pelo `test_allocfail.c` e por
testes de entrada inválida. Evolução incremental, medida a cada commit.
