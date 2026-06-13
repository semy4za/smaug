# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `ce2b73c`  |  Data: 2026-06-12 16:51:22 -0300
- **Branch-alvo** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica), exclui guards defensivos/inalcancaveis marcados `COV-EXCL-BR` -- e a que perseguimos rumo a 100%.
- **Branch-bruto** (todos os ramos): `1285/1407 = 91.33%` -- 21 ramo(s) excluido(s) com justificativa (ver fim do arquivo).
- Agrega TODOS os testes: C diretos (incl. `test_cow` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

| Arquivo | Linhas | Branch-alvo (taken) |
| :--- | :--- | :--- |
| `smaug_core.c` | `376/391 = 96.16%` `[█████████░]` | `255/290 = 87.93%` `[████████░░]` |
| `smaug_ops_f64.c` | `276/276 = 100.00%` `[██████████]` | `284/303 = 93.73%` `[█████████░]` |
| `smaug_ops_i64.c` | `280/280 = 100.00%` `[██████████]` | `287/305 = 94.10%` `[█████████░]` |
| `smaug_ops_bool.c` | `144/153 = 94.12%` `[█████████░]` | `212/240 = 88.33%` `[████████░░]` |
| `smaug_str.c` | `162/164 = 98.78%` `[█████████░]` | `132/132 = 100.00%` `[██████████]` |
| `smaug_ops_str.c` | `115/116 = 99.14%` `[█████████░]` | `115/116 = 99.14%` `[█████████░]` |
| **TOTAL** | `1353/1380 = 98.04%` `[█████████░]` | `1285/1386 = 92.71%` `[█████████░]` |

## Ramos descobertos (mapa real, derivado do .gcov)

Alvos concretos de endurecimento rumo a **branch-alvo 100%** (MC/DC):

**`smaug_core.c`** — 20 linha(s) com ramo descoberto:
- `smaug_core.c:467` — if (size > capacity) return NULL;
- `smaug_core.c:500` — if (!array) return NULL;
- `smaug_core.c:512` — if (!s) return;
- `smaug_core.c:521` — if (!s) return NULL;
- `smaug_core.c:526` — if (s->size > 0) {
- `smaug_core.c:538` — if (!s || start > s->size || len > s->size - start) return NULL;
- `smaug_core.c:556` — if (s->size == 0) {
- `smaug_core.c:580` — if (!s)             { if (status) *status = SMG_ERR_ARGUMENT; return 0; }
- `smaug_core.c:581` — if (idx >= s->size) { if (status) *status = SMG_ERR_OOB;      return 0; }
- `smaug_core.c:582` — if (s->null_mask[idx] != 0xFF) { if (status) *status = SMG_NULL_VALUE; return 0; }
- `smaug_core.c:583` — if (status) *status = SMG_OK;
- `smaug_core.c:588` — if (!s)             return SMG_ERR_ARGUMENT;
- `smaug_core.c:589` — if (idx >= s->size) return SMG_ERR_OOB;
- `smaug_core.c:597` — if (!s)             return SMG_ERR_ARGUMENT;
- `smaug_core.c:598` — if (idx >= s->size) return SMG_ERR_OOB;
- `smaug_core.c:606` — if (!s || idx >= s->size) return true;
- `smaug_core.c:613` — if (!s) return -1;
- `smaug_core.c:616` — if (s->size >= s->capacity) {
- `smaug_core.c:627` — if (!s) return -1;
- `smaug_core.c:630` — if (s->size >= s->capacity) {

**`smaug_ops_f64.c`** — 19 linha(s) com ramo descoberto:
- `smaug_ops_f64.c:151` — if (VALID(a, i)) {
- `smaug_ops_f64.c:342` — if (!s) return NULL;
- `smaug_ops_f64.c:345` — if (!result) return NULL;
- `smaug_ops_f64.c:346` — if (out_mask) {
- `smaug_ops_f64.c:348` — if (!mask) { free(result); return NULL; }
- `smaug_ops_f64.c:354` — if (mask) mask[i] = 0xFF;
- `smaug_ops_f64.c:357` — if (mask) mask[i] = 0x00;
- `smaug_ops_f64.c:365` — if (!s) return NULL;
- `smaug_ops_f64.c:368` — if (!result) return NULL;
- `smaug_ops_f64.c:369` — if (out_mask) {
- `smaug_ops_f64.c:371` — if (!mask) { free(result); return NULL; }
- `smaug_ops_f64.c:377` — if (mask) mask[i] = 0xFF;
- `smaug_ops_f64.c:380` — if (mask) mask[i] = 0x00;
- `smaug_ops_f64.c:388` — if (!s) return NULL;
- `smaug_ops_f64.c:391` — if (!result) return NULL;
- `smaug_ops_f64.c:392` — if (out_mask) {
- `smaug_ops_f64.c:394` — if (!mask) { free(result); return NULL; }
- `smaug_ops_f64.c:400` — if (mask) mask[i] = 0xFF;
- `smaug_ops_f64.c:403` — if (mask) mask[i] = 0x00;

**`smaug_ops_i64.c`** — 18 linha(s) com ramo descoberto:
- `smaug_ops_i64.c:338` — if (!s) return NULL;
- `smaug_ops_i64.c:341` — if (!result) return NULL;
- `smaug_ops_i64.c:342` — if (out_mask) {
- `smaug_ops_i64.c:344` — if (!mask) { free(result); return NULL; }
- `smaug_ops_i64.c:350` — if (mask) mask[i] = 0xFF;
- `smaug_ops_i64.c:353` — if (mask) mask[i] = 0x00;
- `smaug_ops_i64.c:361` — if (!s) return NULL;
- `smaug_ops_i64.c:364` — if (!result) return NULL;
- `smaug_ops_i64.c:365` — if (out_mask) {
- `smaug_ops_i64.c:367` — if (!mask) { free(result); return NULL; }
- `smaug_ops_i64.c:373` — if (mask) mask[i] = 0xFF;
- `smaug_ops_i64.c:376` — if (mask) mask[i] = 0x00;
- `smaug_ops_i64.c:384` — if (!s) return NULL;
- `smaug_ops_i64.c:387` — if (!result) return NULL;
- `smaug_ops_i64.c:388` — if (out_mask) {
- `smaug_ops_i64.c:390` — if (!mask) { free(result); return NULL; }
- `smaug_ops_i64.c:396` — if (mask) mask[i] = 0xFF;
- `smaug_ops_i64.c:399` — if (mask) mask[i] = 0x00;

**`smaug_ops_bool.c`** — 17 linha(s) com ramo descoberto:
- `smaug_ops_bool.c:158` — r->null_mask[i] = m ? m[i] : 0xFF;
- `smaug_ops_bool.c:167` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_bool.c:175` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_bool.c:183` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_bool.c:190` — if (!a) return NULL;
- `smaug_ops_bool.c:198` — if (!s) return 0;
- `smaug_ops_bool.c:202` — if (!s) return false;
- `smaug_ops_bool.c:206` — if (!s) return true;
- `smaug_ops_bool.c:212` — if (!s) return 0;
- `smaug_ops_bool.c:215` — if (s->null_mask[i] == 0xFF) c++;
- `smaug_ops_bool.c:221` — if (!s || !idx) return NULL;
- `smaug_ops_bool.c:225` — if (idx[i] >= s->size) { smaug_bool_free(r); return NULL; }
- `smaug_ops_bool.c:234` — if (!s || !mask) return NULL;
- `smaug_ops_bool.c:255` — if (!s) return NULL;
- `smaug_ops_bool.c:257` — if (s->null_mask[i] != 0xFF) return NULL;   /* qualquer NULL -> recusa */
- `smaug_ops_bool.c:259` — size_t *indices = malloc((s->size ? s->size : 1) * sizeof(size_t));
- `smaug_ops_bool.c:275` — if (!s) return NULL;

**`smaug_ops_str.c`** — 1 linha(s) com ramo descoberto:
- `smaug_ops_str.c:80` — switch (mode) {

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
- `smaug_ops_str.c:221` — ia==ib inalcancavel (indices sempre unicos no argsort)
