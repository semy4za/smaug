# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `9015d45`  |  Data: 2026-06-08 15:32:17 -0300
- **Branch** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica) -- e a que perseguimos rumo a 100%.
- Agrega TODOS os testes: C diretos (incl. `test_cow` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

| Arquivo | Linhas | Branch (taken) |
| :--- | :--- | :--- |
| `smaug_core.c` | `254/260 = 97.69%` `[█████████░]` | `169/196 = 86.22%` `[████████░░]` |
| `smaug_ops_f64.c` | `198/221 = 89.59%` `[█████████░]` | `189/252 = 75.00%` `[███████░░░]` |
| `smaug_ops_i64.c` | `208/213 = 97.65%` `[█████████░]` | `194/258 = 75.19%` `[███████░░░]` |
| `smaug_ops_bool.c` | `63/63 = 100.00%` `[██████████]` | `121/156 = 77.56%` `[███████░░░]` |
| `smaug_str.c` | `154/156 = 98.72%` `[█████████░]` | `117/142 = 82.39%` `[████████░░]` |
| `smaug_ops_str.c` | `93/93 = 100.00%` `[██████████]` | `92/110 = 83.64%` `[████████░░]` |
| **TOTAL** | `970/1006 = 96.42%` `[█████████░]` | `882/1114 = 79.17%` `[███████░░░]` |

## Ramos descobertos (mapa real, derivado do .gcov)

Alvos concretos de endurecimento rumo a **branch 100%** (MC/DC):

**`smaug_core.c`** — 23 linha(s) com ramo descoberto:
- `smaug_core.c:22` — if (new_cap <= s->capacity) new_cap = s->capacity + 1; /* overflow guard */
- `smaug_core.c:39` — if (back) s->data = back;
- `smaug_core.c:50` — if (new_cap <= s->capacity) new_cap = s->capacity + 1;
- `smaug_core.c:62` — if (back) s->data = back;
- `smaug_core.c:150` — if (!s || start > s->size || len > s->size - start) return NULL;
- `smaug_core.c:197` — if (!s)             { if (status) *status = SMG_ERR_ARGUMENT; return NAN; }
- `smaug_core.c:198` — if (idx >= s->size) { if (status) *status = SMG_ERR_OOB;      return NAN; }
- `smaug_core.c:199` — if (s->null_mask[idx] != 0xFF) { if (status) *status = SMG_NULL_VALUE; return NAN; }
- `smaug_core.c:223` — if (!s || idx >= s->size) return true;
- `smaug_core.c:230` — if (!s) return -1;
- `smaug_core.c:244` — if (!s) return -1;
- `smaug_core.c:263` — if (size > capacity) return NULL;
- `smaug_core.c:296` — if (!array) return NULL;
- `smaug_core.c:316` — if (!s) return NULL;
- `smaug_core.c:321` — if (s->size > 0) {
- `smaug_core.c:333` — if (!s || start > s->size || len > s->size - start) return NULL;
- `smaug_core.c:353` — if (s->size == 0) {
- `smaug_core.c:378` — if (!s)             { if (status) *status = SMG_ERR_ARGUMENT; return 0; }
- `smaug_core.c:379` — if (idx >= s->size) { if (status) *status = SMG_ERR_OOB;      return 0; }
- `smaug_core.c:380` — if (s->null_mask[idx] != 0xFF) { if (status) *status = SMG_NULL_VALUE; return 0; }
- `smaug_core.c:404` — if (!s || idx >= s->size) return true;
- `smaug_core.c:411` — if (!s) return -1;
- `smaug_core.c:425` — if (!s) return -1;

**`smaug_ops_f64.c`** — 43 linha(s) com ramo descoberto:
- `smaug_ops_f64.c:36` — if (VALID(a, i) && VALID(b, i)) {
- `smaug_ops_f64.c:46` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_f64.c:49` — if (!r) return NULL;
- `smaug_ops_f64.c:51` — for (size_t i = 0; i < a->size; i++) {
- `smaug_ops_f64.c:52` — if (VALID(a, i) && VALID(b, i)) {
- `smaug_ops_f64.c:62` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_f64.c:65` — if (!r) return NULL;
- `smaug_ops_f64.c:67` — for (size_t i = 0; i < a->size; i++) {
- `smaug_ops_f64.c:68` — if (VALID(a, i) && VALID(b, i)) {
- `smaug_ops_f64.c:78` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_f64.c:81` — if (!r) return NULL;
- `smaug_ops_f64.c:84` — if (VALID(a, i) && VALID(b, i)) {
- `smaug_ops_f64.c:113` — if (!a) return NULL;
- `smaug_ops_f64.c:116` — if (!r) return NULL;
- `smaug_ops_f64.c:118` — for (size_t i = 0; i < a->size; i++) {
- `smaug_ops_f64.c:119` — if (VALID(a, i)) {
- `smaug_ops_f64.c:128` — if (!a) return NULL;
- `smaug_ops_f64.c:131` — if (!r) return NULL;
- `smaug_ops_f64.c:134` — if (VALID(a, i)) {
- `smaug_ops_f64.c:146` — if (!r) return NULL;
- `smaug_ops_f64.c:164` — if (!s) return NAN;
- `smaug_ops_f64.c:178` — if (!s || s->size == 0) return NAN;
- `smaug_ops_f64.c:196` — if (!s || s->size == 0) return NAN;
- `smaug_ops_f64.c:212` — if (!s || s->size == 0) return NAN;
- `smaug_ops_f64.c:229` — if (!s || s->size == 0) return NAN;
- `smaug_ops_f64.c:245` — return count ? sum_sq / (double)count : NAN;
- `smaug_ops_f64.c:288` — if (!s) return NULL;
- `smaug_ops_f64.c:292` — if (!result) return NULL;
- `smaug_ops_f64.c:294` — if (out_mask) {
- `smaug_ops_f64.c:296` — if (!mask) { free(result); return NULL; }
- `smaug_ops_f64.c:303` — if (mask) mask[i] = 0xFF;
- `smaug_ops_f64.c:306` — if (mask) mask[i] = 0x00;
- `smaug_ops_f64.c:314` — if (!s) return NULL;
- `smaug_ops_f64.c:318` — if (!result) return NULL;
- `smaug_ops_f64.c:320` — if (out_mask) {
- `smaug_ops_f64.c:322` — if (!mask) { free(result); return NULL; }
- `smaug_ops_f64.c:329` — if (mask) mask[i] = 0xFF;
- `smaug_ops_f64.c:332` — if (mask) mask[i] = 0x00;
- `smaug_ops_f64.c:359` — if (!s) return NULL;
- `smaug_ops_f64.c:390` — if (!s) return NULL;
- `smaug_ops_f64.c:405` — if (!s) return 0;
- `smaug_ops_f64.c:417` — if (!s || !idx) return NULL;
- `smaug_ops_f64.c:437` — if (!s || !mask) return NULL;

**`smaug_ops_i64.c`** — 48 linha(s) com ramo descoberto:
- `smaug_ops_i64.c:23` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_i64.c:29` — if (VALID(a, i) && VALID(b, i)) {
- `smaug_ops_i64.c:39` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_i64.c:42` — if (!r) return NULL;
- `smaug_ops_i64.c:45` — if (VALID(a, i) && VALID(b, i)) {
- `smaug_ops_i64.c:55` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_i64.c:58` — if (!r) return NULL;
- `smaug_ops_i64.c:61` — if (VALID(a, i) && VALID(b, i)) {
- `smaug_ops_i64.c:72` — if (!a || !b || a->size != b->size) return NULL;
- `smaug_ops_i64.c:75` — if (!r) return NULL;
- `smaug_ops_i64.c:78` — if (VALID(a, i) && VALID(b, i) && b->data[i] != 0) {
- `smaug_ops_i64.c:107` — if (!a) return NULL;
- `smaug_ops_i64.c:110` — if (!r) return NULL;
- `smaug_ops_i64.c:113` — if (VALID(a, i)) {
- `smaug_ops_i64.c:122` — if (!a) return NULL;
- `smaug_ops_i64.c:125` — if (!r) return NULL;
- `smaug_ops_i64.c:128` — if (VALID(a, i)) {
- `smaug_ops_i64.c:138` — if (!a) return NULL;
- `smaug_ops_i64.c:142` — if (!r) return NULL;
- `smaug_ops_i64.c:145` — if (VALID(a, i)) {
- `smaug_ops_i64.c:162` — if (!s) return 0;
- `smaug_ops_i64.c:176` — if (!s || s->size == 0) return INT64_MIN;
- `smaug_ops_i64.c:195` — if (!s || s->size == 0) return INT64_MIN;
- `smaug_ops_i64.c:215` — if (!s || s->size == 0) return NAN;
- `smaug_ops_i64.c:224` — } else if (!ignore_na) {
- `smaug_ops_i64.c:232` — if (!s || s->size == 0) return NAN;
- `smaug_ops_i64.c:235` — if (isnan(mean)) return NAN;
- `smaug_ops_i64.c:241` — if (VALID(s, i)) {
- `smaug_ops_i64.c:247` — return count ? sum_sq / (double)count : NAN;
- `smaug_ops_i64.c:286` — if (!s) return NULL;
- `smaug_ops_i64.c:290` — if (!result) return NULL;
- `smaug_ops_i64.c:292` — if (out_mask) {
- `smaug_ops_i64.c:294` — if (!mask) { free(result); return NULL; }
- `smaug_ops_i64.c:299` — if (VALID(s, i)) {
- `smaug_ops_i64.c:301` — if (mask) mask[i] = 0xFF;
- `smaug_ops_i64.c:304` — if (mask) mask[i] = 0x00;
- `smaug_ops_i64.c:312` — if (!s) return NULL;
- `smaug_ops_i64.c:316` — if (!result) return NULL;
- `smaug_ops_i64.c:318` — if (out_mask) {
- `smaug_ops_i64.c:320` — if (!mask) { free(result); return NULL; }
- `smaug_ops_i64.c:325` — if (VALID(s, i)) {
- `smaug_ops_i64.c:327` — if (mask) mask[i] = 0xFF;
- `smaug_ops_i64.c:330` — if (mask) mask[i] = 0x00;
- `smaug_ops_i64.c:356` — if (!s) return NULL;
- `smaug_ops_i64.c:383` — if (!s) return NULL;
- `smaug_ops_i64.c:398` — if (!s) return 0;
- `smaug_ops_i64.c:408` — if (!s || !idx) return NULL;
- `smaug_ops_i64.c:426` — if (!s || !mask) return NULL;

**`smaug_ops_bool.c`** — 27 linha(s) com ramo descoberto:
- `smaug_ops_bool.c:15` — uint8_t *vals = malloc(n ? n : 1);
- `smaug_ops_bool.c:16` — if (!vals) return NULL;
- `smaug_ops_bool.c:17` — if (out_mask) {
- `smaug_ops_bool.c:18` — smaug_mask_t *m = malloc(n ? n : 1);
- `smaug_ops_bool.c:19` — if (!m) { free(vals); return NULL; }
- `smaug_ops_bool.c:29` — if (m) m[i] = valid ? 0xFF : 0x00;
- `smaug_ops_bool.c:35` — if (!a || !b) return NULL;
- `smaug_ops_bool.c:38` — if (!r) return NULL;
- `smaug_ops_bool.c:39` — if (out_mask) m = *out_mask;
- `smaug_ops_bool.c:42` — int av = VALID(am, i), bv = VALID(bm, i);
- `smaug_ops_bool.c:48` — put(r, m, i, at && bt, 1);          /* ambos válidos */
- `smaug_ops_bool.c:59` — if (!a || !b) return NULL;
- `smaug_ops_bool.c:62` — if (!r) return NULL;
- `smaug_ops_bool.c:63` — if (out_mask) m = *out_mask;
- `smaug_ops_bool.c:66` — int av = VALID(am, i), bv = VALID(bm, i);
- `smaug_ops_bool.c:82` — if (!a || !b) return NULL;
- `smaug_ops_bool.c:85` — if (!r) return NULL;
- `smaug_ops_bool.c:86` — if (out_mask) m = *out_mask;
- `smaug_ops_bool.c:89` — int av = VALID(am, i), bv = VALID(bm, i);
- `smaug_ops_bool.c:98` — if (!a) return NULL;
- `smaug_ops_bool.c:101` — if (!r) return NULL;
- `smaug_ops_bool.c:102` — if (out_mask) m = *out_mask;
- `smaug_ops_bool.c:105` — int av = VALID(am, i);
- `smaug_ops_bool.c:115` — if (!a) return 0;
- `smaug_ops_bool.c:123` — if (!a) return false;
- `smaug_ops_bool.c:125` — if (VALID(am, i) && a[i]) return true;
- `smaug_ops_bool.c:130` — if (!a) return true;            /* all() de vazio = true (vacuamente) */

**`smaug_str.c`** — 22 linha(s) com ramo descoberto:
- `smaug_str.c:74` — if (!s) return NULL;
- `smaug_str.c:83` — if (s->size > 0)
- `smaug_str.c:95` — if (!s->meta.external_alloc) {
- `smaug_str.c:124` — if (l > (size_t)-1 - total) return NULL;
- `smaug_str.c:156` — if (out_len) *out_len = 0;
- `smaug_str.c:157` — if (!s || idx >= s->size) return NULL;
- `smaug_str.c:162` — if (out_len) *out_len = end - start;
- `smaug_str.c:169` — if (!s || idx >= s->size) return true;        /* fora dos limites = "nulo" */
- `smaug_str.c:185` — if (need < s->buffer_len) return -1;
- `smaug_str.c:187` — size_t new_cap = s->buffer_capacity ? s->buffer_capacity : SMAUG_STR_BUFFER_INIT;
- `smaug_str.c:190` — if (grown <= new_cap) { new_cap = need; break; }  /* overflow → usa need */
- `smaug_str.c:205` — if (new_cap <= s->capacity) new_cap = s->capacity + 1;
- `smaug_str.c:216` — if (s->capacity > 0) {
- `smaug_str.c:218` — if (back) s->offsets = back;
- `smaug_str.c:250` — if (len > 0) memcpy(s->buffer + start, str, len);
- `smaug_str.c:290` — if (rc != SMG_OK) return rc;   /* propaga (na prática impossível após validação acima) */
- `smaug_str.c:296` — if (!s) return -1;
- `smaug_str.c:297` — if (!str && len > 0) return -1;
- `smaug_str.c:301` — if (str_buffer_reserve(s, len) != 0) return -1;
- `smaug_str.c:315` — if (!s) return -1;
- `smaug_str.c:316` — if (str_slots_reserve_one(s) != 0) return -1;
- `smaug_str.c:331` — if (!s) return 0;

**`smaug_ops_str.c`** — 12 linha(s) com ramo descoberto:
- `smaug_ops_str.c:32` — if (len > target_len) return  1;
- `smaug_ops_str.c:40` — if (!s) return NULL;
- `smaug_ops_str.c:41` — if (!target && target_len > 0) return NULL;
- `smaug_ops_str.c:43` — uint8_t *result = malloc(s->size ? s->size : 1);
- `smaug_ops_str.c:48` — mask = malloc(s->size ? s->size : 1);
- `smaug_ops_str.c:105` — if (!s || !mask) return NULL;
- `smaug_ops_str.c:136` — if (!s || (!idx && len > 0)) return NULL;
- `smaug_ops_str.c:145` — smaug_series_str_t *r = smaug_str_create_with_capacity(0, bytes ? bytes : 1);
- `smaug_ops_str.c:191` — if (c == 0) c = (ia < ib) ? -1 : (ia > ib) ? 1 : 0;
- `smaug_ops_str.c:196` — if (!s) return NULL;
- `smaug_ops_str.c:202` — size_t *idx = malloc((s->size ? s->size : 1) * sizeof(size_t));
- `smaug_ops_str.c:215` — if (!s) return NULL;

