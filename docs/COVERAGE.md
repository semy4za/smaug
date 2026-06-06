# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh`
> (`make coverage`). Nao editar a mao -- e regenerado a cada medicao.

- Commit medido: `sem-git`
- Data do commit: 2026-06-05 23:49:40
- Linha: metrica basica.  **Branch** ("taken at least once"): metrica
  rigorosa, padrao SQLite/avionica -- e a que perseguimos rumo a 100%.
- **Mede TODOS os testes do projeto**: testes C diretos, testes Lua (via
  FFI) e `test_allocfail` (falha de alocacao). Todos linkam contra os
  mesmos .o instrumentados, entao os caminhos de erro (OOM) contam.

| Arquivo | Linhas | Branch (taken) |
|---------|--------|----------------|
| `smaug_core.c` | 97.30% | 76.00% |
| `smaug_ops_f64.c` | 89.45% | 73.81% |
| `smaug_ops_i64.c` | 97.93% | 74.81% |
| `smaug_ops_bool.c` | 100.00% | 77.56% |
| `smaug_str.c` | 98.80% | 78.17% |
| `smaug_ops_str.c` | 100.00% | 83.64% |
| **TOTAL (ponderado)** | **96.10%** | **76.40%** |

## Gate da Fase 1.6

- Criterio do gate (Fase 1.6): **linha >= 90%**.
- Status: ATINGIDO

## Norte de longo prazo (cover real, padrao SQLite)

Meta futura: **branch 100%** (cobertura MC/DC, como o SQLite). Com a
agregacao de todos os testes, os ramos descobertos restantes sao
majoritariamente: (a) caminhos de erro de string ainda nao exercitados
pelo allocfail (que cobre f64/i64/core, nao string -- ver divida); (b)
ramos de valores especiais (NaN/Inf/sentinela) menos testados. Evolucao
incremental, medida a cada commit.
