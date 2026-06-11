# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `68757bf`  |  Data: 2026-06-10 14:43:47 -0300
- **Branch-alvo** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica), exclui guards defensivos/inalcancaveis marcados `COV-EXCL-BR` -- e a que perseguimos rumo a 100%.
- **Branch-bruto** (todos os ramos): `1047/1114 = 93.99%` -- 13 ramo(s) excluido(s) com justificativa (ver fim do arquivo).
- Agrega TODOS os testes: C diretos (incl. `test_cow` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

| Arquivo | Linhas | Branch-alvo (taken) |
| :--- | :--- | :--- |
| `smaug_core.c` | `263/269 = 97.77%` `[█████████░]` | `191/192 = 99.48%` `[█████████░]` |
| `smaug_ops_f64.c` | `234/234 = 100.00%` `[██████████]` | `243/252 = 96.43%` `[█████████░]` |
| `smaug_ops_i64.c` | `229/234 = 97.86%` `[█████████░]` | `234/258 = 90.70%` `[█████████░]` |
| `smaug_ops_bool.c` | `76/76 = 100.00%` `[██████████]` | `152/154 = 98.70%` `[█████████░]` |
| `smaug_str.c` | `159/161 = 98.76%` `[█████████░]` | `125/135 = 92.59%` `[█████████░]` |
| `smaug_ops_str.c` | `99/99 = 100.00%` `[██████████]` | `102/110 = 92.73%` `[█████████░]` |
| **TOTAL** | `1060/1073 = 98.79%` `[█████████░]` | `1047/1101 = 95.10%` `[█████████░]` |

## Ramos descobertos (mapa real, derivado do .gcov)

Alvos concretos de endurecimento rumo a **branch-alvo 100%** (MC/DC):

**`smaug_core.c`** — 1 linha(s) com ramo descoberto:
- `smaug_core.c:353` — if (s->size == 0) {

**`smaug_ops_f64.c`** — 9 linha(s) com ramo descoberto:
- `smaug_ops_f64.c:245` — return count ? sum_sq / (double)count : NAN;
- `smaug_ops_f64.c:294` — if (out_mask) {
- `smaug_ops_f64.c:303` — if (mask) mask[i] = 0xFF;
- `smaug_ops_f64.c:306` — if (mask) mask[i] = 0x00;
- `smaug_ops_f64.c:320` — if (out_mask) {
- `smaug_ops_f64.c:329` — if (mask) mask[i] = 0xFF;
- `smaug_ops_f64.c:332` — if (mask) mask[i] = 0x00;
- `smaug_ops_f64.c:359` — if (!s) return NULL;
- `smaug_ops_f64.c:390` — if (!s) return NULL;

**`smaug_ops_i64.c`** — 22 linha(s) com ramo descoberto:
- `smaug_ops_i64.c:23` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_i64.c:176` — if (!s || s->size == 0) return INT64_MIN;
- `smaug_ops_i64.c:195` — if (!s || s->size == 0) return INT64_MIN;
- `smaug_ops_i64.c:224` — } else if (!ignore_na) {
- `smaug_ops_i64.c:232` — if (!s || s->size == 0) return NAN;
- `smaug_ops_i64.c:235` — if (isnan(mean)) return NAN;
- `smaug_ops_i64.c:241` — if (VALID(s, i)) {
- `smaug_ops_i64.c:247` — return count ? sum_sq / (double)count : NAN;
- `smaug_ops_i64.c:290` — if (!result) return NULL;
- `smaug_ops_i64.c:292` — if (out_mask) {
- `smaug_ops_i64.c:294` — if (!mask) { free(result); return NULL; }
- `smaug_ops_i64.c:299` — if (VALID(s, i)) {
- `smaug_ops_i64.c:301` — if (mask) mask[i] = 0xFF;
- `smaug_ops_i64.c:304` — if (mask) mask[i] = 0x00;
- `smaug_ops_i64.c:316` — if (!result) return NULL;
- `smaug_ops_i64.c:318` — if (out_mask) {
- `smaug_ops_i64.c:320` — if (!mask) { free(result); return NULL; }
- `smaug_ops_i64.c:325` — if (VALID(s, i)) {
- `smaug_ops_i64.c:327` — if (mask) mask[i] = 0xFF;
- `smaug_ops_i64.c:330` — if (mask) mask[i] = 0x00;
- `smaug_ops_i64.c:356` — if (!s) return NULL;
- `smaug_ops_i64.c:383` — if (!s) return NULL;

**`smaug_ops_bool.c`** — 2 linha(s) com ramo descoberto:
- `smaug_ops_bool.c:15` — uint8_t *vals = malloc(n ? n : 1);
- `smaug_ops_bool.c:18` — smaug_mask_t *m = malloc(n ? n : 1);

**`smaug_str.c`** — 10 linha(s) com ramo descoberto:
- `smaug_str.c:83` — if (s->size > 0)
- `smaug_str.c:95` — if (!s->meta.external_alloc) {
- `smaug_str.c:156` — if (out_len) *out_len = 0;
- `smaug_str.c:162` — if (out_len) *out_len = end - start;
- `smaug_str.c:187` — size_t new_cap = s->buffer_capacity ? s->buffer_capacity : SMAUG_STR_BUFFER_INIT;
- `smaug_str.c:216` — if (s->capacity > 0) {
- `smaug_str.c:250` — if (len > 0) memcpy(s->buffer + start, str, len);
- `smaug_str.c:297` — if (!str && len > 0) return -1;
- `smaug_str.c:301` — if (str_buffer_reserve(s, len) != 0) return -1;
- `smaug_str.c:316` — if (str_slots_reserve_one(s) != 0) return -1;

**`smaug_ops_str.c`** — 8 linha(s) com ramo descoberto:
- `smaug_ops_str.c:32` — if (len > target_len) return  1;
- `smaug_ops_str.c:41` — if (!target && target_len > 0) return NULL;
- `smaug_ops_str.c:43` — uint8_t *result = malloc(s->size ? s->size : 1);
- `smaug_ops_str.c:48` — mask = malloc(s->size ? s->size : 1);
- `smaug_ops_str.c:136` — if (!s || (!idx && len > 0)) return NULL;
- `smaug_ops_str.c:145` — smaug_series_str_t *r = smaug_str_create_with_capacity(0, bytes ? bytes : 1);
- `smaug_ops_str.c:191` — if (c == 0) c = (ia < ib) ? -1 : (ia > ib) ? 1 : 0;
- `smaug_ops_str.c:202` — size_t *idx = malloc((s->size ? s->size : 1) * sizeof(size_t));

## Ramos excluidos (`COV-EXCL-BR` -- defensivos/inalcancaveis, documentados)

Fora da meta por justificativa tecnica (assert reservado a invariantes internas; estes sao guards defensivos sobre condicoes inalcancaveis na pratica):

- `smaug_core.c:22` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:39` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_core.c:50` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:62` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_ops_bool.c:48` — at&&bt sempre true aqui (linhas 45/47 ja garantiram ambos validos-nao-false)
- `smaug_str.c:124` — total ~ SIZE_MAX; inalcancavel
- `smaug_str.c:185` — overflow na soma buffer_len+extra; so com buffer_len ~ SIZE_MAX
- `smaug_str.c:190` — overflow no crescimento *1.5; so com new_cap ~ SIZE_MAX
- `smaug_str.c:205` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_str.c:218` — realloc de shrink falhando; defensivo
- `smaug_str.c:290` — rc sempre SMG_OK neste ponto (validacao acima ja garante)
