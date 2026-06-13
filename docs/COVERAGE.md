# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `23ffb8c`  |  Data: 2026-06-13 01:30:32 -0300
- **Branch-alvo** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica), exclui guards defensivos/inalcancaveis marcados `COV-EXCL-BR` -- e a que perseguimos rumo a 100%.
- **Branch-bruto** (todos os ramos): `1384/1407 = 98.37%` -- 23 ramo(s) excluido(s) com justificativa (ver fim do arquivo).
- Agrega TODOS os testes: C diretos (incl. `test_cow` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

| Arquivo | Linhas | Branch-alvo (taken) |
| :--- | :--- | :--- |
| `smaug_core.c` | `402/402 = 100.00%` `[██████████]` | `290/290 = 100.00%` `[██████████]` |
| `smaug_ops_f64.c` | `285/285 = 100.00%` `[██████████]` | `303/303 = 100.00%` `[██████████]` |
| `smaug_ops_i64.c` | `289/289 = 100.00%` `[██████████]` | `305/305 = 100.00%` `[██████████]` |
| `smaug_ops_bool.c` | `165/165 = 100.00%` `[██████████]` | `239/239 = 100.00%` `[██████████]` |
| `smaug_str.c` | `162/164 = 98.78%` `[█████████░]` | `132/132 = 100.00%` `[██████████]` |
| `smaug_ops_str.c` | `115/116 = 99.14%` `[█████████░]` | `115/115 = 100.00%` `[██████████]` |
| **TOTAL** | `1418/1421 = 99.79%` `[██████████]` | `1384/1384 = 100.00%` `[██████████]` |

## Ramos descobertos (mapa real, derivado do .gcov)

Nenhum ramo descoberto. 🎯
## Ramos excluidos (`COV-EXCL-BR` -- defensivos/inalcancaveis, documentados)

Fora da meta por justificativa tecnica (assert reservado a invariantes internas; estes sao guards defensivos sobre condicoes inalcancaveis na pratica):

- `smaug_core.c:22` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:39` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_core.c:50` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:62` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_core.c:447` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:457` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_ops_f64.c:247` — count==0 inalcancavel: mean nao-NaN implica count>0
- `smaug_ops_i64.c:247` — count==0 inalcancavel: mean nao-NaN implica count>0
- `smaug_ops_bool.c:48` — at&&bt sempre true aqui (linhas 45/47 ja garantiram ambos validos-nao-false)
- `smaug_ops_bool.c:48` — at&&bt sempre true aqui (linhas 45/47 ja garantiram ambos validos-nao-false)
- `smaug_ops_bool.c:158` — m sempre fornecido pelas Kleene raw (out_mask != NULL); ramo :0xFF defensivo, uso interno controlado
- `smaug_str.c:95` — external_alloc=true inalcancavel via API publica; usado apenas internamente
- `smaug_str.c:124` — total ~ SIZE_MAX; inalcancavel
- `smaug_str.c:185` — overflow na soma buffer_len+extra; so com buffer_len ~ SIZE_MAX
- `smaug_str.c:187` — buffer_capacity==0 inalcancavel via API publica (create garante bufcap>=INIT)
- `smaug_str.c:205` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_str.c:216` — bloco de recuperacao de OOM de null_mask; inalcancavel na pratica (slots crescem atomicamente)
- `smaug_str.c:218` — realloc de shrink falhando; defensivo
- `smaug_str.c:218` — realloc de shrink falhando; defensivo
- `smaug_str.c:250` — len==0 inalcancavel aqui (bloco len>old_len implica len>0)
- `smaug_str.c:290` — rc sempre SMG_OK neste ponto (validacao acima ja garante)
- `smaug_ops_str.c:80` — mode e enum interno (LT/GT/LE/GE aqui); case default inalcancavel
- `smaug_ops_str.c:221` — ia==ib inalcancavel (indices sempre unicos no argsort)
