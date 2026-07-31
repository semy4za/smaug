# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `72dd10b`  |  Data: 2026-07-30 17:53:40 -0300
- **Branch-alvo** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica), exclui guards defensivos/inalcancaveis marcados `COV-EXCL-BR` -- e a que perseguimos rumo a 100%.
- **Branch-bruto** (todos os ramos): `4417/4785 = 92.31%` -- 139 ramo(s) excluido(s) com justificativa (ver fim do arquivo).
- Agrega TODOS os testes: C diretos (incl. `test_cow test_io_c` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

| Arquivo | Linhas | Branch-alvo (taken) |
| :--- | :--- | :--- |
| `smaug_astype.c` | `118/118 = 100.00%` `[██████████]` | `109/109 = 100.00%` `[██████████]` |
| `smaug_convert.c` | `37/37 = 100.00%` `[██████████]` | `37/37 = 100.00%` `[██████████]` |
| `smaug_core.c` | `402/402 = 100.00%` `[██████████]` | `290/290 = 100.00%` `[██████████]` |
| `smaug_csv.c` | `298/306 = 97.39%` `[█████████░]` | `333/370 = 90.00%` `[█████████░]` |
| `smaug_datetime.c` | `570/576 = 98.96%` `[█████████░]` | `702/747 = 93.98%` `[█████████░]` |
| `smaug_json.c` | `352/364 = 96.70%` `[█████████░]` | `417/463 = 90.06%` `[█████████░]` |
| `smaug_ops_bool.c` | `314/320 = 98.12%` `[█████████░]` | `380/407 = 93.37%` `[█████████░]` |
| `smaug_ops_f64.c` | `549/549 = 100.00%` `[██████████]` | `632/634 = 99.68%` `[██████████]` |
| `smaug_ops_i64.c` | `557/560 = 99.46%` `[█████████░]` | `603/616 = 97.89%` `[█████████░]` |
| `smaug_ops_str.c` | `278/285 = 97.54%` `[█████████░]` | `318/342 = 92.98%` `[█████████░]` |
| `smaug_ops_window.c` | `326/331 = 98.49%` `[█████████░]` | `342/377 = 90.72%` `[█████████░]` |
| `smaug_str.c` | `297/297 = 100.00%` `[██████████]` | `254/254 = 100.00%` `[██████████]` |
| **TOTAL** | `4098/4145 = 98.87%` `[█████████░]` | `4417/4646 = 95.07%` `[█████████░]` |

## Ramos descobertos (mapa real, derivado do .gcov)

Alvos concretos de endurecimento rumo a **branch-alvo 100%** (MC/DC):

**`smaug_csv.c`** — 27 linha(s) com ramo descoberto:
- `smaug_csv.c:154` — if (i+1 < len && buf[i+1] == quote) { PUSH(quote); i += 2; }
- `smaug_csv.c:157` — PUSH(buf[i]); i++;
- `smaug_csv.c:168` — else if (i < len && buf[i] == '\n') { i++; *eol=1; }
- `smaug_csv.c:187` — char decimal = opts->decimal ? opts->decimal : '.';  /* fallback defensivo: campo zerado → '.' */
- `smaug_csv.c:210` — if (buf[pos] == '\n' || (buf[pos] == '\r' && (pos+1>=len || buf[pos+1]=='\n'))) {
- `smaug_csv.c:211` — if (buf[pos] == '\r') pos++;
- `smaug_csv.c:345` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:359` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:361` — if (is_na(v,nav,nc)) smaug_bool_set_null(s,r);
- `smaug_csv.c:372` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:383` — if (col_names) {
- `smaug_csv.c:407` — if (rows[r]) { for(size_t c=0;c<row_sizes[r];c++) free(rows[r][c]); free(rows[r]); }
- `smaug_csv.c:444` — if (s[i]==sep||s[i]=='\n'||s[i]=='\r'||s[i]==quote) { needs_quote=1; break; }
- `smaug_csv.c:446` — if (wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:448` — if (s[i] == quote && wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:449` — if (wbuf_pushc(b, s[i])) return -1;
- `smaug_csv.c:466` — char decimal = opts->decimal ? opts->decimal : '.'; /* fallback defensivo: campo zerado → '.' */
- `smaug_csv.c:476` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:480` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:485` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:503` — for (size_t k = 0; k < n; k++)
- `smaug_csv.c:512` — } else if (col->str) {
- `smaug_csv.c:516` — if (write_field(&b, s, n, sep, quote)) goto oom;
- `smaug_csv.c:518` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:521` — if (wbuf_pushc(&b, '\0')) goto oom;
- `smaug_csv.c:533` — if (!buf) return -1;
- `smaug_csv.c:537` — return (w==len) ? 0 : -1;

**`smaug_datetime.c`** — 38 linha(s) com ramo descoberto:
- `smaug_datetime.c:340` — if (dt_cow_detach(s) != 0) return -1;
- `smaug_datetime.c:342` — if (dt_grow(s) != 0) return -1;
- `smaug_datetime.c:381` — if (p < end && p[0] >= '0' && p[0] <= '9') {
- `smaug_datetime.c:397` — if (p + 4 <= end && p[0] >= '0' && p[0] <= '9' && p[1] >= '0' && p[1] <= '9'
- `smaug_datetime.c:401` — if (!(p = parse_digits(p, end, 4, y)))   return -1;
- `smaug_datetime.c:404` — if (p >= end || *p++ != sep)             return -1;
- `smaug_datetime.c:405` — if (!(p = parse_digits(p, end, 2, d)))   return -1;
- `smaug_datetime.c:414` — if (p >= end || (*p != '-' && *p != '/'))    return -1;
- `smaug_datetime.c:417` — if (p >= end || *p++ != sep)                 return -1;
- `smaug_datetime.c:437` — if (p < end && (*p == 'T' || *p == ' ')) {
- `smaug_datetime.c:439` — if (!(p = parse_digits(p, end, 2, &h)))   return -1;
- `smaug_datetime.c:440` — if (p >= end || *p++ != ':')               return -1;
- `smaug_datetime.c:441` — if (!(p = parse_digits(p, end, 2, &mi)))  return -1;
- `smaug_datetime.c:442` — if (p >= end || *p++ != ':')               return -1;
- `smaug_datetime.c:443` — if (!(p = parse_digits(p, end, 2, &sec))) return -1;
- `smaug_datetime.c:452` — while (p < end && *p >= '0' && *p <= '9') {
- `smaug_datetime.c:465` — } else if (*p == '+' || *p == '-') {
- `smaug_datetime.c:468` — if (!(p = parse_digits(p, end, 2, &tz_h))) return -1;
- `smaug_datetime.c:469` — if (p < end && *p == ':') p++;
- `smaug_datetime.c:470` — if (!(p = parse_digits(p, end, 2, &tz_m))) return -1;
- `smaug_datetime.c:515` — return (written > 0 && (size_t)written < buf_size) ? 0 : -1;
- `smaug_datetime.c:708` — - (epoch_ms < 0 && epoch_ms % MS_PER_SECOND != 0 ? MS_PER_SECOND : 0);
- `smaug_datetime.c:714` — - (epoch_ms < 0 && epoch_ms % MS_PER_HOUR != 0 ? MS_PER_HOUR : 0);
- `smaug_datetime.c:770` — DT_CMP_IMPL(lt, < )
- `smaug_datetime.c:771` — DT_CMP_IMPL(eq, ==)
- `smaug_datetime.c:772` — DT_CMP_IMPL(ge, >=)
- `smaug_datetime.c:773` — DT_CMP_IMPL(le, <=)
- `smaug_datetime.c:774` — DT_CMP_IMPL(ne, !=)
- `smaug_datetime.c:842` — if (!entries) return NULL;
- `smaug_datetime.c:853` — if (!indices) { free(entries); return NULL; }
- `smaug_datetime.c:973` — if (periods <= -(int64_t)s->size || periods >= (int64_t)s->size) return r;
- `smaug_datetime.c:1002` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_datetime.c:1023` — if (!s || s->size == 0) return DT_SENTINEL;
- `smaug_datetime.c:1040` — if (!s || s->size == 0) return DT_SENTINEL;
- `smaug_datetime.c:1049` — } else if (!ignore_na) {
- `smaug_datetime.c:1053` — return found ? result : DT_SENTINEL;
- `smaug_datetime.c:1077` — if (m == 0) return result;
- `smaug_datetime.c:1099` — switch (method) {

**`smaug_json.c`** — 37 linha(s) com ramo descoberto:
- `smaug_json.c:44` — while (l->pos < l->len) {
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
- `smaug_json.c:181` — if (l->pos >= l->len) return TOK_EOF;
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
- `smaug_json.c:328` — while (t != TOK_RBRACKET && t != TOK_EOF && t != TOK_ERROR) {
- `smaug_json.c:330` — for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
- `smaug_json.c:337` — if (!tmp) {
- `smaug_json.c:338` — for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
- `smaug_json.c:359` — return empty ? empty : make_error("OOM");
- `smaug_json.c:432` — else if (v->type == 1)  smaug_i64_set(s, r, v->i);
- `smaug_json.c:471` — else if (v->type==3) { strcpy(tmp,v->b?"true":"false"); n=strlen(tmp); }
- `smaug_json.c:499` — if (sz < 0) { fclose(f); return NULL; }
- `smaug_json.c:501` — if (!buf) { fclose(f); return NULL; }
- `smaug_json.c:526` — while (ncap <= b->len + n) ncap *= 2;
- `smaug_json.c:537` — if (wbj_pushc(b, '"')) return -1;
- `smaug_json.c:639` — if (!buf) return -1;
- `smaug_json.c:643` — return (w == len) ? 0 : -1;

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

**`smaug_ops_f64.c`** — 2 linha(s) com ramo descoberto:
- `smaug_ops_f64.c:597` — && (inc_hi ? (v <= hi) : (v < hi));
- `smaug_ops_f64.c:934` — if (!s || !out_n) return NULL;

**`smaug_ops_i64.c`** — 10 linha(s) com ramo descoberto:
- `smaug_ops_i64.c:205` — if (!r) return NULL;
- `smaug_ops_i64.c:241` — if (!r) return NULL;
- `smaug_ops_i64.c:273` — if (status) *status = SMG_ERR_ARGUMENT;
- `smaug_ops_i64.c:810` — if (periods <= -(int64_t)s->size || periods >= (int64_t)s->size) return r;
- `smaug_ops_i64.c:848` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_ops_i64.c:862` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_ops_i64.c:910` — if (!s || !out_n) return NULL;
- `smaug_ops_i64.c:916` — if (n == 0) return NULL;
- `smaug_ops_i64.c:953` — if (m == 0) return result;
- `smaug_ops_i64.c:979` — switch (method) {

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

**`smaug_ops_window.c`** — 27 linha(s) com ramo descoberto:
- `smaug_ops_window.c:33` — switch (col->kind) {
- `smaug_ops_window.c:135` — if (!ffi_cols || ncols == 0 || nrows == 0) return NULL;
- `smaug_ops_window.c:216` — double *out = malloc((n ? n : 1) * sizeof(double));
- `smaug_ops_window.c:241` — switch (kind) {
- `smaug_ops_window.c:256` — if (num < 0.0) num = 0.0;   /* guarda contra erro numérico */
- `smaug_ops_window.c:328` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:335` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:343` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:377` — if (cnt == 0 || s->data[j] < best) best = s->data[j];
- `smaug_ops_window.c:381` — if (cnt >= min_periods) {
- `smaug_ops_window.c:394` — if (i + 1 >= window && !deque_empty(&dq) &&
- `smaug_ops_window.c:437` — if (SMAUG_VALID(s->null_mask, j)) {
- `smaug_ops_window.c:438` — if (cnt == 0 || s->data[j] > best) best = s->data[j];
- `smaug_ops_window.c:442` — if (cnt >= min_periods) {
- `smaug_ops_window.c:454` — if (i + 1 >= window && !deque_empty(&dq) &&
- `smaug_ops_window.c:460` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
- `smaug_ops_window.c:513` — double *tmp = malloc((s->size ? s->size : 1) * sizeof(double));
- `smaug_ops_window.c:530` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:536` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:542` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:559` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:573` — if (cnt >= min_periods) {
- `smaug_ops_window.c:606` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:615` — if (SMAUG_VALID(s->null_mask, j)) {
- `smaug_ops_window.c:616` — if (cnt == 0 || s->data[j] > best) best = s->data[j];
- `smaug_ops_window.c:620` — if (cnt >= min_periods) {
- `smaug_ops_window.c:632` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)

## Ramos excluidos (`COV-EXCL-BR` -- defensivos/inalcancaveis, documentados)

Fora da meta por justificativa tecnica (assert reservado a invariantes internas; estes sao guards defensivos sobre condicoes inalcancaveis na pratica):

- `smaug_astype.c:63` — OOM sem injecao de falha
- `smaug_astype.c:77` — OOM
- `smaug_astype.c:97` — OOM
- `smaug_astype.c:112` — OOM
- `smaug_astype.c:126` — OOM
- `smaug_astype.c:145` — OOM
- `smaug_astype.c:171` — OOM sem injecao
- `smaug_astype.c:181` — OOM no append
- `smaug_astype.c:191` — OOM sem injecao
- `smaug_astype.c:201` — OOM no append
- `smaug_astype.c:213` — OOM sem injecao
- `smaug_astype.c:225` — OOM no append
- `smaug_astype.c:244` — OOM sem injecao
- `smaug_astype.c:264` — OOM sem injecao
- `smaug_astype.c:285` — OOM sem injecao
- `smaug_convert.c:75` — bufsize < 5 nunca ocorre (callers usam >= 32)
- `smaug_convert.c:75` — bufsize < 5 nunca ocorre (callers usam >= 32)
- `smaug_convert.c:75` — bufsize < 5 nunca ocorre (callers usam >= 32)
- `smaug_core.c:22` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:39` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_core.c:50` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:62` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_core.c:447` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:457` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_csv.c:38` — falha de syscall não simulável sem mock
- `smaug_csv.c:40` — ftell negativo só em fd inválido
- `smaug_csv.c:43` — OOM de malloc no read_file
- `smaug_csv.c:106` — s nunca é NULL — origem é row[c] ou "" literal
- `smaug_csv.c:135` — loop externo garante pos < len antes de chamar
- `smaug_csv.c:172` — só falha se PUSH falhou por OOM
- `smaug_csv.c:227` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:227` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:227` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:236` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:236` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:236` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:236` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:250` — rows[0] nunca NULL — n_rows>0 garante alocação
- `smaug_csv.c:251` — next_field sempre produz >=1 campo por linha
- `smaug_csv.c:261` — c<n_cols<=row_sizes[0] por construção
- `smaug_csv.c:335` — dtype=int64 implica que todo valor não-NA já passou em try_i64 durante a inferência (mesma string, mesma is_na, função pura e determinística) — confirmado por auditoria adversarial (overflow/inf/nan/zeros à esquerda) e 400k+ checks da suíte, nunca quebrou
- `smaug_csv.c:348` — dtype=float64 implica try_f64=1 pelo mesmo argumento de pureza da inferência (ver linha 303)
- `smaug_csv.c:349` — duplamente inalcançável — além da pureza da inferência, try_i64(v) bem-sucedido implica try_f64(v) também bem-sucedido (strtod aceita toda a gramática de strtoll), então o try_f64 da linha acima já teria capturado este valor
- `smaug_csv.c:349` — duplamente inalcançável — além da pureza da inferência, try_i64(v) bem-sucedido implica try_f64(v) também bem-sucedido (strtod aceita toda a gramática de strtoll), então o try_f64 da linha acima já teria capturado este valor
- `smaug_csv.c:362` — dtype=bool implica try_bool=1 pelo mesmo argumento de pureza da inferência (ver linha 303)
- `smaug_csv.c:477` — name sempre não-NULL após construção
- `smaug_datetime.c:64` — ramo z<0 no algoritmo de Hinnant — datas antes de ~292Mi a.C.
- `smaug_datetime.c:82` — ramo Y<0 no algoritmo de Hinnant — datas antes de ~292Mi a.C.
- `smaug_datetime.c:119` — realloc de shrink
- `smaug_datetime.c:130` — view size==0 — caso degenerado de view vazia
- `smaug_datetime.c:151` — size > capacity — invariante; create() nunca viola
- `smaug_datetime.c:204` — size==0 — clone de série vazia tem size=0, memcpy não executado
- `smaug_datetime.c:219` — redundante — o clone(NULL) logo abaixo devolve NULL e o `if (!r)` barra; auditado 2026-07-14 (remover este guard NAO crasha). Defesa em profundidade, nao a unica protecao.
- `smaug_datetime.c:222` — falha de alloc do clone; OOM sem injecao
- `smaug_datetime.c:242` — falha de alloc do clone; OOM sem injecao
- `smaug_datetime.c:263` — OOM sem injecao
- `smaug_datetime.c:277` — args inválidos — start > size ou len > size-start
- `smaug_datetime.c:657` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:658` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:659` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:660` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:661` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:662` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:663` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:664` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:665` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:666` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_datetime.c:667` — o ramo falso do `v >= 0` e inalcancavel -- as escalares nunca devolvem -1 hoje, apesar de o header prometer (ver item registrado); guard mantido como defesa em profundidade
- `smaug_json.c:114` — string não fechada — break inalcançável em JSON bem-formado
- `smaug_json.c:149` — OOM de realloc em string JSON
- `smaug_json.c:433` — dtype=int64 implica que toda linha não-null tinha jt==1 durante a inferência (dtype_upgrade força float64 se qualquer linha fosse jt==2) — mesmo argumento de pureza do csv.c
- `smaug_json.c:433` — dtype=int64 implica que toda linha não-null tinha jt==1 durante a inferência (dtype_upgrade força float64 se qualquer linha fosse jt==2) — mesmo argumento de pureza do csv.c
- `smaug_json.c:445` — ramo falso inalcançável — se chegou aqui, type já não é 0 nem 2; pureza garante que só resta 1
- `smaug_json.c:456` — ramo falso inalcançável — pureza garante type==3 sempre que não-null numa coluna bool
- `smaug_json.c:540` — OOM de wbuf sem injeção
- `smaug_json.c:541` — OOM de wbuf sem injeção
- `smaug_json.c:542` — OOM de wbuf sem injeção
- `smaug_json.c:543` — OOM de wbuf sem injeção
- `smaug_json.c:543` — OOM de wbuf sem injeção
- `smaug_json.c:543` — OOM de wbuf sem injeção
- `smaug_json.c:544` — OOM de wbuf sem injeção
- `smaug_json.c:545` — OOM de wbuf sem injeção
- `smaug_json.c:546` — OOM de wbuf sem injeção
- `smaug_json.c:559` — NULL opts usa default 0; opts não-NULL cobre ambos
- `smaug_json.c:566` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:569` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:570` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:571` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:574` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:576` — name sempre não-NULL após construção
- `smaug_json.c:577` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:578` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:579` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:587` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:588` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:592` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:599` — OOM de wbuf + nao-finito→null: ramo oom inalcançável sem injeção
- `smaug_json.c:600` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:604` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:605` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:606` — dtype inferido garante exatamente um ponteiro não-NULL
- `smaug_json.c:609` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:610` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:611` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:611` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:613` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:614` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:617` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:618` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:619` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:620` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:623` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:624` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:625` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_ops_bool.c:48` — at&&bt sempre true aqui (linhas 45/47 ja garantiram ambos validos-nao-false)
- `smaug_ops_bool.c:48` — at&&bt sempre true aqui (linhas 45/47 ja garantiram ambos validos-nao-false)
- `smaug_ops_bool.c:158` — m sempre fornecido pelas Kleene raw (out_mask != NULL); ramo :SMAUG_MASK_VALID defensivo, uso interno controlado
- `smaug_ops_bool.c:267` — falha de alloc do clone; OOM sem injecao
- `smaug_ops_f64.c:266` — redundante — o clone(NULL) logo abaixo devolve NULL e o `if (!r)` barra; auditado 2026-07-14 (remover este guard NAO crasha). Defesa em profundidade, nao a unica protecao.
- `smaug_ops_f64.c:269` — falha de alloc do clone; OOM sem injecao
- `smaug_ops_f64.c:290` — falha de alloc do clone; OOM sem injecao
- `smaug_ops_f64.c:311` — OOM sem injecao
- `smaug_ops_i64.c:284` — redundante — o clone(NULL) logo abaixo devolve NULL e o `if (!r)` barra; auditado 2026-07-14 (remover este guard NAO crasha). Defesa em profundidade, nao a unica protecao.
- `smaug_ops_i64.c:287` — falha de alloc do clone; OOM sem injecao
- `smaug_ops_i64.c:308` — falha de alloc do clone; OOM sem injecao
- `smaug_ops_i64.c:330` — OOM sem injecao
- `smaug_ops_str.c:85` — mode e enum interno (LT/GT/LE/GE aqui); case default inalcancavel
- `smaug_ops_window.c:412` — loop-body inalcançável — a if em 258-260 já trata o único item stale possível; by invariante de 266, no máximo um item envelhece por passo de null
- `smaug_ops_window.c:469` — loop-body inalcançável — mesma invariante que linha 276 (rolling_min)
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
