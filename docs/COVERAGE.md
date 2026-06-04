# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh`
> (`make coverage`). Nao editar a mao -- e regenerado a cada medicao.

- Commit medido: `2c4752c`
- Data do commit: 2026-06-04 19:44:49 -0300
- Linha: metrica basica.  **Branch** ("taken at least once"): metrica
  rigorosa, padrao SQLite/avionica -- e a que perseguimos rumo a 100%.
- **Mede TODOS os testes do projeto**: testes C diretos, testes Lua (via
  FFI) e `test_allocfail` (falha de alocacao). Todos linkam contra os
  mesmos .o instrumentados, entao os caminhos de erro (OOM) contam.

| Arquivo | Linhas | Branch (taken) |
|---------|--------|----------------|
| `smaug_core.c` | 97.20% | 70.67% |
| `smaug_ops_f64.c` | 81.01% | 61.11% |
| `smaug_ops_i64.c` | 96.28% | 70.54% |
| `smaug_ops_bool.c` | 100.00% | 77.56% |
| `smaug_str.c` | 97.58% | 67.14% |
| **TOTAL (ponderado)** | **92.96%** | **68.31%** |

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
