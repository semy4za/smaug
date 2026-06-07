# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh`
> (`make coverage`). Nao editar a mao -- e regenerado a cada medicao.

- Commit medido: `9a694cf`
- Data do commit: 2026-06-06 09:41:23 -0300
- Linha: metrica basica.  **Branch** ("taken at least once"): metrica
  rigorosa, padrao SQLite/avionica -- e a que perseguimos rumo a 100%.
- **Mede TODOS os testes do projeto**: testes C diretos, testes Lua (via
  FFI) e `test_allocfail` (falha de alocacao). Todos linkam contra os
  mesmos .o instrumentados, entao os caminhos de erro (OOM) contam.

| Arquivo | Linhas | Branch (taken) |
|---------|--------|----------------|
| `smaug_core.c` | **97.67%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#50fa7b; width:97.67%; height:14px; border-radius:4px;"></div></div> | **80.32%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#bd93f9; width:80.32%; height:14px; border-radius:4px;"></div></div> |
| `smaug_ops_f64.c` | **89.45%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#50fa7b; width:89.45%; height:14px; border-radius:4px;"></div></div> | **73.81%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#bd93f9; width:73.81%; height:14px; border-radius:4px;"></div></div> |
| `smaug_ops_i64.c` | **97.93%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#50fa7b; width:97.93%; height:14px; border-radius:4px;"></div></div> | **74.81%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#bd93f9; width:74.81%; height:14px; border-radius:4px;"></div></div> |
| `smaug_ops_bool.c` | **100.00%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#50fa7b; width:100.00%; height:14px; border-radius:4px;"></div></div> | **77.56%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#bd93f9; width:77.56%; height:14px; border-radius:4px;"></div></div> |
| `smaug_str.c` | **98.80%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#50fa7b; width:98.80%; height:14px; border-radius:4px;"></div></div> | **78.17%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#bd93f9; width:78.17%; height:14px; border-radius:4px;"></div></div> |
| `smaug_ops_str.c` | **100.00%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#50fa7b; width:100.00%; height:14px; border-radius:4px;"></div></div> | **83.64%** &nbsp; <div style="background:#44475a; border-radius:4px; width:100px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#bd93f9; width:83.64%; height:14px; border-radius:4px;"></div></div> |
| **TOTAL** | **96.23%** &nbsp; <div style="background:#44475a; border-radius:4px; width:150px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#8be9fd; width:96.23%; height:16px; border-radius:4px;"></div></div> | **77.12%** &nbsp; <div style="background:#44475a; border-radius:4px; width:150px; display:inline-block; vertical-align:middle; overflow:hidden"><div style="background:#ff79c6; width:77.12%; height:16px; border-radius:4px;"></div></div> |


## Norte de longo prazo (cover real, padrao SQLite)

Meta futura: **branch 100%** (cobertura MC/DC, como o SQLite). Com a
agregacao de todos os testes, os ramos descobertos restantes sao
majoritariamente: (a) caminhos de erro de string ainda nao exercitados
pelo allocfail (que cobre f64/i64/core, nao string -- ver divida); (b)
ramos de valores especiais (NaN/Inf/sentinela) menos testados. Evolucao
incremental, medida a cada commit.

