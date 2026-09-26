# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `31c4cfd`  |  Data: 2026-09-26 13:31:23 -0300
- **Branch-alvo** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica), exclui guards defensivos/inalcancaveis marcados `COV-EXCL-BR` -- e a que perseguimos rumo a 100%.
- **Branch-bruto** (todos os ramos): `4612/5041 = 91.49%` -- 135 ramo(s) excluido(s) com justificativa (ver fim do arquivo).
- Agrega TODOS os testes: C diretos (incl. `test_cow test_io_c` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

<a id="coverage-total"></a>

| Arquivo | Linhas | Branch-alvo (taken) |
| :--- | :--- | :--- |
| `smaug_astype.c` | `153/153 = 100.00%` `[██████████]` | `140/140 = 100.00%` `[██████████]` |
| `smaug_convert.c` | `37/37 = 100.00%` `[██████████]` | `37/37 = 100.00%` `[██████████]` |
| `smaug_core.c` | `426/426 = 100.00%` `[██████████]` | `343/350 = 98.00%` `[█████████░]` |
| `smaug_csv.c` | `299/307 = 97.39%` `[█████████░]` | `336/374 = 89.84%` `[█████████░]` |
| `smaug_datetime.c` | `585/594 = 98.48%` `[█████████░]` | `753/820 = 91.83%` `[█████████░]` |
| `smaug_json.c` | `354/366 = 96.72%` `[█████████░]` | `423/467 = 90.58%` `[█████████░]` |
| `smaug_ops_bool.c` | `314/320 = 98.12%` `[█████████░]` | `380/407 = 93.37%` `[█████████░]` |
| `smaug_ops_f64.c` | `558/558 = 100.00%` `[██████████]` | `640/644 = 99.38%` `[█████████░]` |
| `smaug_ops_i64.c` | `573/582 = 98.45%` `[█████████░]` | `633/674 = 93.92%` `[█████████░]` |
| `smaug_ops_str.c` | `278/285 = 97.54%` `[█████████░]` | `318/342 = 92.98%` `[█████████░]` |
| `smaug_ops_window.c` | `335/342 = 97.95%` `[█████████░]` | `355/397 = 89.42%` `[████████░░]` |
| `smaug_str.c` | `297/297 = 100.00%` `[██████████]` | `254/254 = 100.00%` `[██████████]` |
| **TOTAL** | `4209/4267 = 98.64%` `[█████████░]` | `4612/4906 = 94.01%` `[█████████░]` |

## Ramos descobertos (mapa real, derivado do .gcov)

Alvos concretos de endurecimento rumo a **branch-alvo 100%** (MC/DC):

**`smaug_core.c`** — 7 linha(s) com ramo descoberto:
- `smaug_core.c:37` — if (a == 0 || b == 0) {
- `smaug_core.c:38` — if (out) *out = 0;
- `smaug_core.c:42` — (a > 0 && b < 0 && b < INT64_MIN / a) ||
- `smaug_core.c:43` — (a < 0 && b > 0 && a < INT64_MIN / b) ||
- `smaug_core.c:44` — (a < 0 && b < 0 && a < INT64_MAX / b)) return false;
- `smaug_core.c:50` — if (b == 0 || (a == INT64_MIN && b == -1)) return false;
- `smaug_core.c:469` — if (s->size >= s->capacity) {

**`smaug_csv.c`** — 28 linha(s) com ramo descoberto:
- `smaug_csv.c:154` — if (i+1 < len && buf[i+1] == quote) { PUSH(quote); i += 2; }
- `smaug_csv.c:157` — PUSH(buf[i]); i++;
- `smaug_csv.c:168` — else if (i < len && buf[i] == '\n') { i++; *eol=1; }
- `smaug_csv.c:188` — if (!buf && len > 0) return NULL;
- `smaug_csv.c:194` — char decimal = opts->decimal ? opts->decimal : '.';  /* fallback defensivo: campo zerado → '.' */
- `smaug_csv.c:217` — if (buf[pos] == '\n' || (buf[pos] == '\r' && (pos+1>=len || buf[pos+1]=='\n'))) {
- `smaug_csv.c:218` — if (buf[pos] == '\r') pos++;
- `smaug_csv.c:352` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:366` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:368` — if (is_na(v,nav,nc)) smaug_bool_set_null(s,r);
- `smaug_csv.c:379` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:390` — if (col_names) {
- `smaug_csv.c:414` — if (rows[r]) { for(size_t c=0;c<row_sizes[r];c++) free(rows[r][c]); free(rows[r]); }
- `smaug_csv.c:451` — if (s[i]==sep||s[i]=='\n'||s[i]=='\r'||s[i]==quote) { needs_quote=1; break; }
- `smaug_csv.c:453` — if (wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:455` — if (s[i] == quote && wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:456` — if (wbuf_pushc(b, s[i])) return -1;
- `smaug_csv.c:473` — char decimal = opts->decimal ? opts->decimal : '.'; /* fallback defensivo: campo zerado → '.' */
- `smaug_csv.c:483` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:487` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:492` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:510` — for (size_t k = 0; k < n; k++)
- `smaug_csv.c:519` — } else if (col->str) {
- `smaug_csv.c:523` — if (write_field(&b, s, n, sep, quote)) goto oom;
- `smaug_csv.c:525` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:528` — if (wbuf_pushc(&b, '\0')) goto oom;
- `smaug_csv.c:540` — if (!buf) return -1;
- `smaug_csv.c:544` — return (w==len) ? 0 : -1;

**`smaug_datetime.c`** — 60 linha(s) com ramo descoberto:
- `smaug_datetime.c:341` — if (dt_cow_detach(s) != 0) return -1;
- `smaug_datetime.c:343` — if (dt_grow(s) != 0) return -1;
- `smaug_datetime.c:382` — if (cursor < end && cursor[0] >= '0' && cursor[0] <= '9') {
- `smaug_datetime.c:402` — if (cursor >= end || *cursor++ != '-') return -1;
- `smaug_datetime.c:403` — if (!(cursor = parse_digits(cursor, end, 2, month))) return -1;
- `smaug_datetime.c:404` — if (cursor >= end || *cursor++ != '-') return -1;
- `smaug_datetime.c:405` — if (!(cursor = parse_digits(cursor, end, 2, day))) return -1;
- `smaug_datetime.c:410` — if (end - cursor >= 5 && cursor[0] >= '0' && cursor[0] <= '9' && cursor[1] >= '0' && cursor[1] <= '9'
- `smaug_datetime.c:414` — if (!(cursor = parse_digits(cursor, end, 4, year)))   return -1;
- `smaug_datetime.c:418` — if (!(cursor = parse_digits(cursor, end, 2, day)))   return -1;
- `smaug_datetime.c:427` — if (cursor >= end || (*cursor != '-' && *cursor != '/'))    return -1;
- `smaug_datetime.c:430` — if (cursor >= end || *cursor++ != separator)                 return -1;
- `smaug_datetime.c:440` — if (!str || !epoch_ms || (dayfirst != 0 && dayfirst != 1)) return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:453` — if (!(cursor = parse_digits(cursor, end, 2, &hour)))   return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:454` — if (cursor >= end || *cursor++ != ':')             return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:455` — if (!(cursor = parse_digits(cursor, end, 2, &minute))) return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:457` — if (!(cursor = parse_digits(cursor, end, 2, &second))) return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:482` — } else if (*cursor == '+' || *cursor == '-') {
- `smaug_datetime.c:485` — if (!(cursor = parse_digits(cursor, end, 2, &offset_hour))) return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:486` — if (cursor < end && *cursor == ':') cursor++;
- `smaug_datetime.c:487` — if (!(cursor = parse_digits(cursor, end, 2, &offset_minute))) return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:497` — if (smaug_dt_from_parts_checked(year, month, day, hour, minute, second, millisecond, &result) != SMG_OK)
- `smaug_datetime.c:503` — if (smaug_dt_add_ms_checked(result, offset_sign > 0 ? -offset_ms : offset_ms,
- `smaug_datetime.c:537` — return (written > 0 && (size_t)written < buf_size) ? 0 : -1;
- `smaug_datetime.c:696` — if (!out || !is_valid_date(year, month, day)) return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:702` — if (!smaug_i64_mul_checked(days, MS_PER_DAY, &result) ||
- `smaug_datetime.c:703` — !smaug_i64_mul_checked((int64_t)hour, MS_PER_HOUR, &part) ||
- `smaug_datetime.c:704` — !smaug_i64_add_checked(result, part, &result) ||
- `smaug_datetime.c:705` — !smaug_i64_mul_checked((int64_t)minute, MS_PER_MINUTE, &part) ||
- `smaug_datetime.c:706` — !smaug_i64_add_checked(result, part, &result) ||
- `smaug_datetime.c:707` — !smaug_i64_mul_checked((int64_t)second, MS_PER_SECOND, &part) ||
- `smaug_datetime.c:708` — !smaug_i64_add_checked(result, part, &result) ||
- `smaug_datetime.c:709` — !smaug_i64_add_checked(result, (int64_t)ms, &result))
- `smaug_datetime.c:727` — if (!out) return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:728` — return smaug_i64_sub_checked(a, b, out) ? SMG_OK : SMG_ERR_OVERFLOW;
- `smaug_datetime.c:732` — return smaug_dt_diff_ms_checked(a, b, &out) == SMG_OK ? out : DT_SENTINEL;
- `smaug_datetime.c:737` — if (!out) return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:750` — return smaug_i64_mul_checked(q, unit, out) ? SMG_OK : SMG_ERR_OVERFLOW;
- `smaug_datetime.c:754` — if (!out) return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:762` — return smaug_i64_mul_checked(d, MS_PER_DAY, out) ? SMG_OK : SMG_ERR_OVERFLOW;
- `smaug_datetime.c:767` — if (!smaug_i64_sub_checked(d, (int64_t)wd, &start) ||
- `smaug_datetime.c:768` — !smaug_i64_mul_checked(start, MS_PER_DAY, out)) return SMG_ERR_OVERFLOW;
- `smaug_datetime.c:775` — ? SMG_OK : SMG_ERR_OVERFLOW;
- `smaug_datetime.c:782` — ? SMG_OK : SMG_ERR_OVERFLOW;
- `smaug_datetime.c:788` — ? SMG_OK : SMG_ERR_OVERFLOW;
- `smaug_datetime.c:825` — DT_CMP_IMPL(lt, < )
- `smaug_datetime.c:826` — DT_CMP_IMPL(eq, ==)
- `smaug_datetime.c:827` — DT_CMP_IMPL(ge, >=)
- `smaug_datetime.c:828` — DT_CMP_IMPL(le, <=)
- `smaug_datetime.c:829` — DT_CMP_IMPL(ne, !=)
- `smaug_datetime.c:897` — if (!entries) return NULL;
- `smaug_datetime.c:908` — if (!indices) { free(entries); return NULL; }
- `smaug_datetime.c:1028` — if (periods <= -(int64_t)s->size || periods >= (int64_t)s->size) return r;
- `smaug_datetime.c:1057` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_datetime.c:1078` — if (!s || s->size == 0) return DT_SENTINEL;
- `smaug_datetime.c:1095` — if (!s || s->size == 0) return DT_SENTINEL;
- `smaug_datetime.c:1104` — } else if (!ignore_na) {
- `smaug_datetime.c:1108` — return found ? result : DT_SENTINEL;
- `smaug_datetime.c:1132` — if (m == 0) return result;
- `smaug_datetime.c:1154` — switch (method) {

**`smaug_json.c`** — 35 linha(s) com ramo descoberto:
- `smaug_json.c:46` — if (c == ' ' || c == '\t' || c == '\n' || c == '\r') l->pos++;
- `smaug_json.c:54` — if (l->pos + 4 > l->len) return -1;
- `smaug_json.c:60` — else if (h >= 'a' && h <= 'f') digit = h - 'a' + 10;
- `smaug_json.c:84` — } else if (cp <= 0x10FFFF) {
- `smaug_json.c:105` — if (l->pos >= l->len || l->buf[l->pos] != '"') return NULL;
- `smaug_json.c:110` — while (l->pos < l->len) {
- `smaug_json.c:126` — l->buf[l->pos] != '\\' || l->buf[l->pos+1] != 'u') {
- `smaug_json.c:133` — if (ucp2 < 0xDC00 || ucp2 > 0xDFFF) {
- `smaug_json.c:137` — } else if (ucp >= 0xDC00 && ucp <= 0xDFFF) {
- `smaug_json.c:143` — if (bytes == 0) { free(out); return NULL; }
- `smaug_json.c:157` — switch (esc) {
- `smaug_json.c:195` — if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"true",4)==0)
- `smaug_json.c:199` — if (l->pos + 5 <= l->len && strncmp(l->buf+l->pos,"false",5)==0)
- `smaug_json.c:203` — if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"null",4)==0)
- `smaug_json.c:207` — if (c == '-' || (c >= '0' && c <= '9')) {
- `smaug_json.c:211` — while (l->pos < l->len && l->buf[l->pos] >= '0' && l->buf[l->pos] <= '9') l->pos++;
- `smaug_json.c:212` — if (l->pos < l->len && l->buf[l->pos] == '.') { l->is_int = 0; l->pos++; while (l->pos<l->len && l->buf[l->pos]>='0' && l->buf[l->pos]<='9') l->pos++; }
- `smaug_json.c:213` — if (l->pos < l->len && (l->buf[l->pos]=='e' || l->buf[l->pos]=='E')) { l->is_int=0; l->pos++; if (l->pos<l->len && (l->buf[l->pos]=='+'||l->buf[l->pos]=='-')) l->pos++; while(l->pos<l->len && l->buf[l->pos]>='0' && l->buf[l->pos]<='9') l->pos++; }
- `smaug_json.c:215` — if (numlen >= sizeof(tmp)) numlen = sizeof(tmp)-1;
- `smaug_json.c:217` — if (l->is_int) { char *e; errno=0; l->int_val=strtoll(tmp,&e,10); if (*e) l->is_int=0; }
- `smaug_json.c:218` — if (!l->is_int) { char *e; errno=0; l->num_val=strtod(tmp,&e); if (*e||errno) return TOK_ERROR; }
- `smaug_json.c:296` — if (!nk || !nv) { free(key); if (val.type==4) free(val.s); return 0; }
- `smaug_json.c:332` — while (t != TOK_RBRACKET && t != TOK_EOF && t != TOK_ERROR) {
- `smaug_json.c:334` — for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
- `smaug_json.c:341` — if (!tmp) {
- `smaug_json.c:342` — for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
- `smaug_json.c:363` — return empty ? empty : make_error("OOM");
- `smaug_json.c:436` — else if (v->type == 1)  smaug_i64_set(s, r, v->i);
- `smaug_json.c:475` — else if (v->type==3) { strcpy(tmp,v->b?"true":"false"); n=strlen(tmp); }
- `smaug_json.c:503` — if (sz < 0) { fclose(f); return NULL; }
- `smaug_json.c:505` — if (!buf) { fclose(f); return NULL; }
- `smaug_json.c:530` — while (ncap <= b->len + n) ncap *= 2;
- `smaug_json.c:541` — if (wbj_pushc(b, '"')) return -1;
- `smaug_json.c:643` — if (!buf) return -1;
- `smaug_json.c:647` — return (w == len) ? 0 : -1;

**`smaug_ops_bool.c`** — 22 linha(s) com ramo descoberto:
- `smaug_ops_bool.c:204` — if (out_mask) {
- `smaug_ops_bool.c:213` — if (mask) mask[i] = SMAUG_MASK_VALID;
- `smaug_ops_bool.c:216` — if (mask) mask[i] = SMAUG_MASK_NULL;
- `smaug_ops_bool.c:228` — if (out_mask) {
- `smaug_ops_bool.c:237` — if (mask) mask[i] = SMAUG_MASK_VALID;
- `smaug_ops_bool.c:240` — if (mask) mask[i] = SMAUG_MASK_NULL;
- `smaug_ops_bool.c:408` — if (periods <= -(int64_t)s->size || periods >= (int64_t)s->size) return r;
- `smaug_ops_bool.c:422` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_ops_bool.c:436` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_ops_bool.c:459` — if (!s || s->size == 0) {
- `smaug_ops_bool.c:460` — if (status) *status = SMG_NULL_VALUE;
- `smaug_ops_bool.c:470` — if (status) *status = SMG_NULL_VALUE;
- `smaug_ops_bool.c:480` — if (!s || s->size == 0) {
- `smaug_ops_bool.c:481` — if (status) *status = SMG_NULL_VALUE;
- `smaug_ops_bool.c:487` — if (SMAUG_VALID(s->null_mask, i)) {
- `smaug_ops_bool.c:489` — if (!found || v > result) { result = v; found = true; }
- `smaug_ops_bool.c:490` — } else if (!ignore_na) {
- `smaug_ops_bool.c:491` — if (status) *status = SMG_NULL_VALUE;
- `smaug_ops_bool.c:495` — if (status) *status = found ? SMG_OK : SMG_NULL_VALUE;
- `smaug_ops_bool.c:496` — return found ? result : 0;
- `smaug_ops_bool.c:519` — if (nf + nt == 0) return result;
- `smaug_ops_bool.c:526` — switch (method) {

**`smaug_ops_f64.c`** — 4 linha(s) com ramo descoberto:
- `smaug_ops_f64.c:421` — if (!s) return NAN;
- `smaug_ops_f64.c:432` — return found_valid ? prod : NAN;
- `smaug_ops_f64.c:612` — && (inc_hi ? (v <= hi) : (v < hi));
- `smaug_ops_f64.c:949` — if (!s || !out_n) return NULL;

**`smaug_ops_i64.c`** — 36 linha(s) com ramo descoberto:
- `smaug_ops_i64.c:27` — if (status) *status = SMG_ERR_ARGUMENT;
- `smaug_ops_i64.c:41` — if (!r) { if (status) *status = SMG_ERR_NOMEM; return NULL; }
- `smaug_ops_i64.c:57` — if (!a) { if (status) *status = SMG_ERR_ARGUMENT; return NULL; }
- `smaug_ops_i64.c:61` — if (status) *status = SMG_ERR_OVERFLOW;
- `smaug_ops_i64.c:67` — if (!r) { if (status) *status = SMG_ERR_NOMEM; return NULL; }
- `smaug_ops_i64.c:156` — if (!r) return NULL;
- `smaug_ops_i64.c:192` — if (!r) return NULL;
- `smaug_ops_i64.c:224` — if (status) *status = SMG_ERR_ARGUMENT;
- `smaug_ops_i64.c:305` — if (!s) { if (status) *status = SMG_ERR_ARGUMENT; return 0; }
- `smaug_ops_i64.c:311` — if (status) *status = SMG_ERR_OVERFLOW;
- `smaug_ops_i64.c:338` — } else if (!ignore_na) {
- `smaug_ops_i64.c:342` — return found ? result : INT64_MIN;
- `smaug_ops_i64.c:408` — if (status) *status = SMG_OK;
- `smaug_ops_i64.c:409` — if (!s) {
- `smaug_ops_i64.c:410` — if (status) *status = SMG_ERR_ARGUMENT;
- `smaug_ops_i64.c:415` — for (size_t i = 0; i < s->size; i++) {
- `smaug_ops_i64.c:417` — if (status) *status = SMG_ERR_ARGUMENT;
- `smaug_ops_i64.c:428` — if (status) *status = SMG_ERR_OVERFLOW;
- `smaug_ops_i64.c:663` — qsort(entries, s->size, sizeof(i64_entry_t),
- `smaug_ops_i64.c:726` — if (!s) { if (status) *status = SMG_ERR_ARGUMENT; return NULL; }
- `smaug_ops_i64.c:733` — if (status) *status = SMG_ERR_OVERFLOW;
- `smaug_ops_i64.c:738` — if (!r) { if (status) *status = SMG_ERR_NOMEM; return NULL; }
- `smaug_ops_i64.c:759` — if (!s) { if (status) *status = SMG_ERR_ARGUMENT; return NULL; }
- `smaug_ops_i64.c:765` — } else if (!smaug_i64_mul_checked(acc, s->data[i], &acc)) {
- `smaug_ops_i64.c:766` — if (status) *status = SMG_ERR_OVERFLOW;
- `smaug_ops_i64.c:771` — if (!r) { if (status) *status = SMG_ERR_NOMEM; return NULL; }
- `smaug_ops_i64.c:824` — if (!s) { if (status) *status = SMG_ERR_ARGUMENT; return NULL; }
- `smaug_ops_i64.c:828` — if (status) *status = SMG_ERR_OVERFLOW;
- `smaug_ops_i64.c:833` — if (!r) { if (status) *status = SMG_ERR_NOMEM; return NULL; }
- `smaug_ops_i64.c:852` — if (periods <= -(int64_t)s->size || periods >= (int64_t)s->size) return r;
- `smaug_ops_i64.c:890` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_ops_i64.c:904` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_ops_i64.c:952` — if (!s || !out_n) return NULL;
- `smaug_ops_i64.c:958` — if (n == 0) return NULL;
- `smaug_ops_i64.c:995` — if (m == 0) return result;
- `smaug_ops_i64.c:1021` — switch (method) {

**`smaug_ops_str.c`** — 19 linha(s) com ramo descoberto:
- `smaug_ops_str.c:309` — while (lo < hi) {
- `smaug_ops_str.c:322` — if (i <= j) { sort_swap(a, i, j); i++; if (j > 0) j--; }
- `smaug_ops_str.c:325` — if (j > lo && (j - lo) < (hi - i)) { sort_idx(a, lo, j, s); lo = i; }
- `smaug_ops_str.c:326` — else if (i < hi)                   { sort_idx(a, i, hi, s); hi = j; }
- `smaug_ops_str.c:327` — else if (j > lo)                   { hi = j; }
- `smaug_ops_str.c:426` — size_t *src = malloc((s->size ? s->size : 1) * sizeof(size_t));
- `smaug_ops_str.c:457` — int all_null = (periods <= -(int64_t)n || periods >= (int64_t)n);
- `smaug_ops_str.c:505` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_ops_str.c:526` — if (out_len) *out_len = 0;
- `smaug_ops_str.c:527` — if (!s || s->size == 0) return NULL;
- `smaug_ops_str.c:529` — for (size_t i = 0; i < s->size; i++)
- `smaug_ops_str.c:539` — if (out_len) *out_len = 0;
- `smaug_ops_str.c:540` — if (!s || s->size == 0) return NULL;
- `smaug_ops_str.c:541` — if (!ignore_na) {
- `smaug_ops_str.c:542` — for (size_t i = 0; i < s->size; i++)
- `smaug_ops_str.c:543` — if (SMAUG_NULL(s->null_mask, i)) return NULL;
- `smaug_ops_str.c:546` — if (idx == SIZE_MAX) return NULL;
- `smaug_ops_str.c:577` — if (m > 1) sort_idx(idx, 0, m - 1, s);
- `smaug_ops_str.c:588` — switch (method) {

**`smaug_ops_window.c`** — 33 linha(s) com ramo descoberto:
- `smaug_ops_window.c:33` — switch (col->kind) {
- `smaug_ops_window.c:155` — if (!ffi_cols || ncols == 0 || nrows == 0) return NULL;
- `smaug_ops_window.c:236` — double *out = malloc((n ? n : 1) * sizeof(double));
- `smaug_ops_window.c:261` — switch (kind) {
- `smaug_ops_window.c:276` — if (num < 0.0) num = 0.0;   /* guarda contra erro numérico */
- `smaug_ops_window.c:348` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:355` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:363` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:397` — if (cnt == 0 || s->data[j] < best) best = s->data[j];
- `smaug_ops_window.c:401` — if (cnt >= min_periods) {
- `smaug_ops_window.c:414` — if (i + 1 >= window && !deque_empty(&dq) &&
- `smaug_ops_window.c:457` — if (SMAUG_VALID(s->null_mask, j)) {
- `smaug_ops_window.c:458` — if (cnt == 0 || s->data[j] > best) best = s->data[j];
- `smaug_ops_window.c:462` — if (cnt >= min_periods) {
- `smaug_ops_window.c:474` — if (i + 1 >= window && !deque_empty(&dq) &&
- `smaug_ops_window.c:480` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
- `smaug_ops_window.c:514` — if (!smaug_i64_sub_checked(sum, s->data[out], &sum)) return false;
- `smaug_ops_window.c:519` — if (!smaug_i64_add_checked(sum, s->data[i], &sum)) return false;
- `smaug_ops_window.c:537` — if (!s || window == 0) { if (status) *status = SMG_ERR_ARGUMENT; return NULL; }
- `smaug_ops_window.c:538` — if (!i64_rolling_sum_apply(s, window, min_periods, NULL)) {
- `smaug_ops_window.c:539` — if (status) *status = SMG_ERR_OVERFLOW;
- `smaug_ops_window.c:543` — if (!r) { if (status) *status = SMG_ERR_NOMEM; return NULL; }
- `smaug_ops_window.c:558` — double *tmp = malloc((s->size ? s->size : 1) * sizeof(double));
- `smaug_ops_window.c:575` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:581` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:587` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:604` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:618` — if (cnt >= min_periods) {
- `smaug_ops_window.c:651` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:660` — if (SMAUG_VALID(s->null_mask, j)) {
- `smaug_ops_window.c:661` — if (cnt == 0 || s->data[j] > best) best = s->data[j];
- `smaug_ops_window.c:665` — if (cnt >= min_periods) {
- `smaug_ops_window.c:677` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)

## Ramos excluidos (`COV-EXCL-BR` -- defensivos/inalcancaveis, documentados)

Fora da meta por justificativa tecnica (assert reservado a invariantes internas; estes sao guards defensivos sobre condicoes inalcancaveis na pratica):

- `smaug_astype.c:53` — OOM sem injecao de falha
- `smaug_astype.c:67` — OOM
- `smaug_astype.c:114` — OOM
- `smaug_astype.c:163` — OOM
- `smaug_astype.c:189` — OOM sem injecao
- `smaug_astype.c:199` — OOM no append
- `smaug_astype.c:209` — OOM sem injecao
- `smaug_astype.c:219` — OOM no append
- `smaug_astype.c:231` — OOM sem injecao
- `smaug_astype.c:243` — OOM no append
- `smaug_astype.c:263` — OOM sem injecao
- `smaug_astype.c:283` — OOM sem injecao
- `smaug_convert.c:75` — bufsize < 5 nunca ocorre (callers usam >= 32)
- `smaug_convert.c:75` — bufsize < 5 nunca ocorre (callers usam >= 32)
- `smaug_convert.c:75` — bufsize < 5 nunca ocorre (callers usam >= 32)
- `smaug_core.c:63` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:80` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_core.c:91` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:103` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_core.c:488` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:498` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_csv.c:38` — falha de syscall não simulável sem mock
- `smaug_csv.c:40` — ftell negativo só em fd inválido
- `smaug_csv.c:43` — OOM de malloc no read_file
- `smaug_csv.c:106` — s nunca é NULL — origem é row[c] ou "" literal
- `smaug_csv.c:135` — loop externo garante pos < len antes de chamar
- `smaug_csv.c:172` — só falha se PUSH falhou por OOM
- `smaug_csv.c:234` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:234` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:234` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:243` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:243` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:243` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:243` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:257` — rows[0] nunca NULL — n_rows>0 garante alocação
- `smaug_csv.c:258` — next_field sempre produz >=1 campo por linha
- `smaug_csv.c:268` — c<n_cols<=row_sizes[0] por construção
- `smaug_csv.c:342` — dtype=int64 implica que todo valor não-NA já passou em try_i64 durante a inferência (mesma string, mesma is_na, função pura e determinística) — confirmado por auditoria adversarial (overflow/inf/nan/zeros à esquerda) e 400k+ checks da suíte, nunca quebrou
- `smaug_csv.c:355` — dtype=float64 implica try_f64=1 pelo mesmo argumento de pureza da inferência (ver linha 303)
- `smaug_csv.c:356` — duplamente inalcançável — além da pureza da inferência, try_i64(v) bem-sucedido implica try_f64(v) também bem-sucedido (strtod aceita toda a gramática de strtoll), então o try_f64 da linha acima já teria capturado este valor
- `smaug_csv.c:356` — duplamente inalcançável — além da pureza da inferência, try_i64(v) bem-sucedido implica try_f64(v) também bem-sucedido (strtod aceita toda a gramática de strtoll), então o try_f64 da linha acima já teria capturado este valor
- `smaug_csv.c:369` — dtype=bool implica try_bool=1 pelo mesmo argumento de pureza da inferência (ver linha 303)
- `smaug_csv.c:484` — name sempre não-NULL após construção
- `smaug_datetime.c:65` — ramo z<0 no algoritmo de Hinnant — datas antes de ~292Mi a.C.
- `smaug_datetime.c:120` — realloc de shrink
- `smaug_datetime.c:131` — view size==0 — caso degenerado de view vazia
- `smaug_datetime.c:152` — size > capacity — invariante; create() nunca viola
- `smaug_datetime.c:205` — size==0 — clone de série vazia tem size=0, memcpy não executado
- `smaug_datetime.c:220` — redundante — o clone(NULL) logo abaixo devolve NULL e o `if (!r)` barra; auditado 2026-07-14 (remover este guard NAO crasha). Defesa em profundidade, nao a unica protecao.
- `smaug_datetime.c:223` — falha de alloc do clone; OOM sem injecao
- `smaug_datetime.c:243` — falha de alloc do clone; OOM sem injecao
- `smaug_datetime.c:264` — OOM sem injecao
- `smaug_datetime.c:278` — args inválidos — start > size ou len > size-start
- `smaug_datetime.c:677` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:678` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:679` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:680` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:681` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:682` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:683` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:684` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:685` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:686` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:687` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_json.c:114` — string não fechada — break inalcançável em JSON bem-formado
- `smaug_json.c:149` — OOM de realloc em string JSON
- `smaug_json.c:437` — dtype=int64 implica que toda linha não-null tinha jt==1 durante a inferência (dtype_upgrade força float64 se qualquer linha fosse jt==2) — mesmo argumento de pureza do csv.c
- `smaug_json.c:437` — dtype=int64 implica que toda linha não-null tinha jt==1 durante a inferência (dtype_upgrade força float64 se qualquer linha fosse jt==2) — mesmo argumento de pureza do csv.c
- `smaug_json.c:449` — ramo falso inalcançável — se chegou aqui, type já não é 0 nem 2; pureza garante que só resta 1
- `smaug_json.c:460` — ramo falso inalcançável — pureza garante type==3 sempre que não-null numa coluna bool
- `smaug_json.c:544` — OOM de wbuf sem injeção
- `smaug_json.c:545` — OOM de wbuf sem injeção
- `smaug_json.c:546` — OOM de wbuf sem injeção
- `smaug_json.c:547` — OOM de wbuf sem injeção
- `smaug_json.c:547` — OOM de wbuf sem injeção
- `smaug_json.c:547` — OOM de wbuf sem injeção
- `smaug_json.c:548` — OOM de wbuf sem injeção
- `smaug_json.c:549` — OOM de wbuf sem injeção
- `smaug_json.c:550` — OOM de wbuf sem injeção
- `smaug_json.c:563` — NULL opts usa default 0; opts não-NULL cobre ambos
- `smaug_json.c:570` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:573` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:574` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:575` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:578` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:580` — name sempre não-NULL após construção
- `smaug_json.c:581` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:582` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:583` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:591` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:592` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:596` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:603` — OOM de wbuf + nao-finito→null: ramo oom inalcançável sem injeção
- `smaug_json.c:604` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:608` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:609` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:610` — dtype inferido garante exatamente um ponteiro não-NULL
- `smaug_json.c:613` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:614` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:615` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:615` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:617` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:618` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:621` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:622` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:623` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:624` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:627` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:628` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:629` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_ops_bool.c:48` — at&&bt sempre true aqui (linhas 45/47 ja garantiram ambos validos-nao-false)
- `smaug_ops_bool.c:48` — at&&bt sempre true aqui (linhas 45/47 ja garantiram ambos validos-nao-false)
- `smaug_ops_bool.c:158` — m sempre fornecido pelas Kleene raw (out_mask != NULL); ramo :SMAUG_MASK_VALID defensivo, uso interno controlado
- `smaug_ops_bool.c:267` — falha de alloc do clone; OOM sem injecao
- `smaug_ops_f64.c:266` — redundante — o clone(NULL) logo abaixo devolve NULL e o `if (!r)` barra; auditado 2026-07-14 (remover este guard NAO crasha). Defesa em profundidade, nao a unica protecao.
- `smaug_ops_f64.c:269` — falha de alloc do clone; OOM sem injecao
- `smaug_ops_f64.c:290` — falha de alloc do clone; OOM sem injecao
- `smaug_ops_f64.c:311` — OOM sem injecao
- `smaug_ops_i64.c:235` — redundante — o clone(NULL) logo abaixo devolve NULL e o `if (!r)` barra; auditado 2026-07-14 (remover este guard NAO crasha). Defesa em profundidade, nao a unica protecao.
- `smaug_ops_i64.c:238` — falha de alloc do clone; OOM sem injecao
- `smaug_ops_i64.c:259` — falha de alloc do clone; OOM sem injecao
- `smaug_ops_i64.c:281` — OOM sem injecao
- `smaug_ops_str.c:85` — mode e enum interno (LT/GT/LE/GE aqui); case default inalcancavel
- `smaug_ops_window.c:432` — loop-body inalcançável — a if em 258-260 já trata o único item stale possível; by invariante de 266, no máximo um item envelhece por passo de null
- `smaug_ops_window.c:489` — loop-body inalcançável — mesma invariante que linha 276 (rolling_min)
- `smaug_str.c:104` — offsets_owned=false nao existe na API atual; o campo separa a posse do offsets da do buffer (modelo A1, smaug_types.h) — sem ele o free inferiria posse por acoplamento external_alloc+is_view
- `smaug_str.c:164` — total ~ SIZE_MAX; inalcancavel
- `smaug_str.c:214` — falha de alloc; OOM sem injecao
- `smaug_str.c:256` — falha de alloc; OOM sem injecao
- `smaug_str.c:303` — OOM sem injecao
- `smaug_str.c:358` — overflow na soma buffer_len+extra; so com buffer_len ~ SIZE_MAX
- `smaug_str.c:360` — buffer_capacity==0 inalcancavel via API publica (create garante bufcap>=INIT)
- `smaug_str.c:378` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_str.c:391` — realloc de shrink falhando; defensivo
- `smaug_str.c:486` — len==0 inalcancavel aqui (bloco len>old_len implica len>0)
