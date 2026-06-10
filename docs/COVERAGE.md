# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `c696b87`  |  Data: 2026-06-09 17:03:50 -0300
- **Branch** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica) -- e a que perseguimos rumo a 100%.
- Agrega TODOS os testes: C diretos (incl. `test_cow` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

| Arquivo | Linhas | Branch (taken) |
| :--- | :--- | :--- |
| `smaug_core.c` | `263/269 = 97.77%` `[█████████░]` | `191/196 = 97.45%` `[█████████░]` |
| `smaug_ops_f64.c` | `218/225 = 96.89%` `[█████████░]` | `226/252 = 89.68%` `[█████████░]` |
| `smaug_ops_i64.c` | `223/228 = 97.81%` `[█████████░]` | `225/258 = 87.21%` `[████████░░]` |
| `smaug_ops_bool.c` | `70/70 = 100.00%` `[██████████]` | `146/156 = 93.59%` `[█████████░]` |
| `smaug_str.c` | `159/161 = 98.76%` `[█████████░]` | `125/142 = 88.03%` `[████████░░]` |
| `smaug_ops_str.c` | `99/99 = 100.00%` `[██████████]` | `102/110 = 92.73%` `[█████████░]` |
| **TOTAL** | `1032/1052 = 98.10%` `[█████████░]` | `1015/1114 = 91.11%` `[█████████░]` |

## Ramos descobertos (mapa real, derivado do .gcov)

Alvos concretos de endurecimento rumo a **branch 100%** (MC/DC):

**`smaug_core.c`** — 5 linha(s) com ramo descoberto:
- `smaug_core.c:22` — if (new_cap <= s->capacity) new_cap = s->capacity + 1; /* overflow guard */
- `smaug_core.c:39` — if (back) s->data = back;
- `smaug_core.c:50` — if (new_cap <= s->capacity) new_cap = s->capacity + 1;
- `smaug_core.c:62` — if (back) s->data = back;
- `smaug_core.c:353` — if (s->size == 0) {

**`smaug_ops_f64.c`** — 23 linha(s) com ramo descoberto:
- `smaug_ops_f64.c:49` — if (!r) return NULL;
- `smaug_ops_f64.c:65` — if (!r) return NULL;
- `smaug_ops_f64.c:81` — if (!r) return NULL;
- `smaug_ops_f64.c:113` — if (!a) return NULL;
- `smaug_ops_f64.c:116` — if (!r) return NULL;
- `smaug_ops_f64.c:118` — for (size_t i = 0; i < a->size; i++) {
- `smaug_ops_f64.c:119` — if (VALID(a, i)) {
- `smaug_ops_f64.c:131` — if (!r) return NULL;
- `smaug_ops_f64.c:134` — if (VALID(a, i)) {
- `smaug_ops_f64.c:146` — if (!r) return NULL;
- `smaug_ops_f64.c:245` — return count ? sum_sq / (double)count : NAN;
- `smaug_ops_f64.c:292` — if (!result) return NULL;
- `smaug_ops_f64.c:294` — if (out_mask) {
- `smaug_ops_f64.c:296` — if (!mask) { free(result); return NULL; }
- `smaug_ops_f64.c:303` — if (mask) mask[i] = 0xFF;
- `smaug_ops_f64.c:306` — if (mask) mask[i] = 0x00;
- `smaug_ops_f64.c:318` — if (!result) return NULL;
- `smaug_ops_f64.c:320` — if (out_mask) {
- `smaug_ops_f64.c:322` — if (!mask) { free(result); return NULL; }
- `smaug_ops_f64.c:329` — if (mask) mask[i] = 0xFF;
- `smaug_ops_f64.c:332` — if (mask) mask[i] = 0x00;
- `smaug_ops_f64.c:359` — if (!s) return NULL;
- `smaug_ops_f64.c:390` — if (!s) return NULL;

**`smaug_ops_i64.c`** — 31 linha(s) com ramo descoberto:
- `smaug_ops_i64.c:23` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_i64.c:42` — if (!r) return NULL;
- `smaug_ops_i64.c:58` — if (!r) return NULL;
- `smaug_ops_i64.c:75` — if (!r) return NULL;
- `smaug_ops_i64.c:110` — if (!r) return NULL;
- `smaug_ops_i64.c:113` — if (VALID(a, i)) {
- `smaug_ops_i64.c:125` — if (!r) return NULL;
- `smaug_ops_i64.c:128` — if (VALID(a, i)) {
- `smaug_ops_i64.c:142` — if (!r) return NULL;
- `smaug_ops_i64.c:145` — if (VALID(a, i)) {
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

**`smaug_ops_bool.c`** — 9 linha(s) com ramo descoberto:
- `smaug_ops_bool.c:15` — uint8_t *vals = malloc(n ? n : 1);
- `smaug_ops_bool.c:16` — if (!vals) return NULL;
- `smaug_ops_bool.c:18` — smaug_mask_t *m = malloc(n ? n : 1);
- `smaug_ops_bool.c:19` — if (!m) { free(vals); return NULL; }
- `smaug_ops_bool.c:38` — if (!r) return NULL;
- `smaug_ops_bool.c:48` — put(r, m, i, at && bt, 1);          /* ambos válidos */
- `smaug_ops_bool.c:62` — if (!r) return NULL;
- `smaug_ops_bool.c:85` — if (!r) return NULL;
- `smaug_ops_bool.c:101` — if (!r) return NULL;

**`smaug_str.c`** — 16 linha(s) com ramo descoberto:
- `smaug_str.c:83` — if (s->size > 0)
- `smaug_str.c:95` — if (!s->meta.external_alloc) {
- `smaug_str.c:124` — if (l > (size_t)-1 - total) return NULL;
- `smaug_str.c:156` — if (out_len) *out_len = 0;
- `smaug_str.c:162` — if (out_len) *out_len = end - start;
- `smaug_str.c:185` — if (need < s->buffer_len) return -1;
- `smaug_str.c:187` — size_t new_cap = s->buffer_capacity ? s->buffer_capacity : SMAUG_STR_BUFFER_INIT;
- `smaug_str.c:190` — if (grown <= new_cap) { new_cap = need; break; }  /* overflow → usa need */
- `smaug_str.c:205` — if (new_cap <= s->capacity) new_cap = s->capacity + 1;
- `smaug_str.c:216` — if (s->capacity > 0) {
- `smaug_str.c:218` — if (back) s->offsets = back;
- `smaug_str.c:250` — if (len > 0) memcpy(s->buffer + start, str, len);
- `smaug_str.c:290` — if (rc != SMG_OK) return rc;   /* propaga (na prática impossível após validação acima) */
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

