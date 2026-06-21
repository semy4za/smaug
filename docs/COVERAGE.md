# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `9849416`  |  Data: 2026-06-21 12:57:14 -0300
- **Branch-alvo** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica), exclui guards defensivos/inalcancaveis marcados `COV-EXCL-BR` -- e a que perseguimos rumo a 100%.
- **Branch-bruto** (todos os ramos): `2874/3280 = 87.62%` -- 80 ramo(s) excluido(s) com justificativa (ver fim do arquivo).
- Agrega TODOS os testes: C diretos (incl. `test_cow test_io_c` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

| Arquivo | Linhas | Branch-alvo (taken) |
| :--- | :--- | :--- |
| `smaug_core.c` | `402/402 = 100.00%` `[██████████]` | `290/290 = 100.00%` `[██████████]` |
| `smaug_ops_f64.c` | `460/460 = 100.00%` `[██████████]` | `456/457 = 99.78%` `[██████████]` |
| `smaug_ops_i64.c` | `448/451 = 99.33%` `[█████████░]` | `450/459 = 98.04%` `[█████████░]` |
| `smaug_ops_bool.c` | `165/165 = 100.00%` `[██████████]` | `239/239 = 100.00%` `[██████████]` |
| `smaug_str.c` | `162/164 = 98.78%` `[█████████░]` | `132/132 = 100.00%` `[██████████]` |
| `smaug_ops_str.c` | `115/116 = 99.14%` `[█████████░]` | `115/115 = 100.00%` `[██████████]` |
| `smaug_csv.c` | `271/282 = 96.10%` `[█████████░]` | `312/363 = 85.95%` `[████████░░]` |
| `smaug_json.c` | `320/350 = 91.43%` `[█████████░]` | `367/491 = 74.75%` `[███████░░░]` |
| `smaug_datetime.c` | `329/356 = 92.42%` `[█████████░]` | `299/403 = 74.19%` `[███████░░░]` |
| `smaug_ops_window.c` | `213/220 = 96.82%` `[█████████░]` | `214/251 = 85.26%` `[████████░░]` |
| **TOTAL** | `2885/2966 = 97.27%` `[█████████░]` | `2874/3200 = 89.81%` `[█████████░]` |

## Ramos descobertos (mapa real, derivado do .gcov)

Alvos concretos de endurecimento rumo a **branch-alvo 100%** (MC/DC):

**`smaug_ops_f64.c`** — 1 linha(s) com ramo descoberto:
- `smaug_ops_f64.c:715` — if (!s || !out_n) return NULL;

**`smaug_ops_i64.c`** — 7 linha(s) com ramo descoberto:
- `smaug_ops_i64.c:584` — if (periods >= s->size) return r;
- `smaug_ops_i64.c:619` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_ops_i64.c:633` — if (!s || s->size == 0) return SIZE_MAX;
- `smaug_ops_i64.c:681` — if (!s || !out_n) return NULL;
- `smaug_ops_i64.c:687` — if (n == 0) return NULL;
- `smaug_ops_i64.c:722` — if (m == 0) return result;
- `smaug_ops_i64.c:748` — switch (method) {

**`smaug_csv.c`** — 36 linha(s) com ramo descoberto:
- `smaug_csv.c:81` — if (!s || !*s) return 0;
- `smaug_csv.c:84` — if (errno || *end != '\0') return 0;
- `smaug_csv.c:89` — if (!s || !*s) return 0;
- `smaug_csv.c:92` — if (errno || *end != '\0') return 0;
- `smaug_csv.c:129` — if (i+1 < len && buf[i+1] == quote) { PUSH(quote); i += 2; }
- `smaug_csv.c:132` — PUSH(buf[i]); i++;
- `smaug_csv.c:143` — else if (i < len && buf[i] == '\n') { i++; *eol=1; }
- `smaug_csv.c:178` — if (buf[pos] == '\n' || (buf[pos] == '\r' && (pos+1>=len || buf[pos+1]=='\n'))) {
- `smaug_csv.c:179` — if (buf[pos] == '\r') pos++;
- `smaug_csv.c:241` — if (!col_names[c]) {
- `smaug_csv.c:242` — for (size_t k = 0; k < c; k++) free(col_names[k]);
- `smaug_csv.c:313` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:327` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:329` — if (is_na(v,nav,nc)) smaug_bool_set_null(s,r);
- `smaug_csv.c:340` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:351` — if (col_names) {
- `smaug_csv.c:375` — if (rows[r]) { for(size_t c=0;c<row_sizes[r];c++) free(rows[r][c]); free(rows[r]); }
- `smaug_csv.c:400` — while (ncap <= b->len + n) ncap *= 2;
- `smaug_csv.c:412` — if (s[i]==sep||s[i]=='\n'||s[i]=='\r'||s[i]==quote) { needs_quote=1; break; }
- `smaug_csv.c:414` — if (wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:416` — if (s[i] == quote && wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:417` — if (wbuf_pushc(b, s[i])) return -1;
- `smaug_csv.c:424` — if (!t || !out_len) return NULL;
- `smaug_csv.c:426` — if (!opts) opts = &def;
- `smaug_csv.c:433` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:437` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:442` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:447` — if (st==SMG_NULL_VALUE||st!=SMG_OK) { s=""; n=0; }
- `smaug_csv.c:451` — if (st==SMG_NULL_VALUE||st!=SMG_OK) { s=""; n=0; }
- `smaug_csv.c:456` — if (st==SMG_NULL_VALUE||st!=SMG_OK) { s=""; n=0; }
- `smaug_csv.c:458` — } else if (col->str) {
- `smaug_csv.c:462` — if (write_field(&b, s, n, sep, quote)) goto oom;
- `smaug_csv.c:464` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:467` — if (wbuf_pushc(&b, '\0')) goto oom;
- `smaug_csv.c:476` — if (!buf) return -1;
- `smaug_csv.c:480` — return (w==len) ? 0 : -1;

**`smaug_json.c`** — 85 linha(s) com ramo descoberto:
- `smaug_json.c:43` — while (l->pos < l->len) {
- `smaug_json.c:45` — if (c == ' ' || c == '\t' || c == '\n' || c == '\r') l->pos++;
- `smaug_json.c:53` — if (l->pos + 4 > l->len) return -1;
- `smaug_json.c:58` — if      (h >= '0' && h <= '9') digit = h - '0';
- `smaug_json.c:59` — else if (h >= 'a' && h <= 'f') digit = h - 'a' + 10;
- `smaug_json.c:60` — else if (h >= 'A' && h <= 'F') digit = h - 'A' + 10;
- `smaug_json.c:83` — } else if (cp <= 0x10FFFF) {
- `smaug_json.c:104` — if (l->pos >= l->len || l->buf[l->pos] != '"') return NULL;
- `smaug_json.c:109` — while (l->pos < l->len) {
- `smaug_json.c:125` — l->buf[l->pos] != '\\' || l->buf[l->pos+1] != 'u') {
- `smaug_json.c:130` — if (cp2 < 0) { free(out); return NULL; }
- `smaug_json.c:132` — if (ucp2 < 0xDC00 || ucp2 > 0xDFFF) {
- `smaug_json.c:136` — } else if (ucp >= 0xDC00 && ucp <= 0xDFFF) {
- `smaug_json.c:142` — if (bytes == 0) { free(out); return NULL; }
- `smaug_json.c:145` — if (n + bytes >= cap) {
- `smaug_json.c:146` — while (n + bytes >= cap) cap *= 2;
- `smaug_json.c:156` — switch (esc) {
- `smaug_json.c:180` — if (l->pos >= l->len) return TOK_EOF;
- `smaug_json.c:194` — if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"true",4)==0)
- `smaug_json.c:198` — if (l->pos + 5 <= l->len && strncmp(l->buf+l->pos,"false",5)==0)
- `smaug_json.c:202` — if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"null",4)==0)
- `smaug_json.c:206` — if (c == '-' || (c >= '0' && c <= '9')) {
- `smaug_json.c:210` — while (l->pos < l->len && l->buf[l->pos] >= '0' && l->buf[l->pos] <= '9') l->pos++;
- `smaug_json.c:211` — if (l->pos < l->len && l->buf[l->pos] == '.') { l->is_int = 0; l->pos++; while (l->pos<l->len && l->buf[l->pos]>='0' && l->buf[l->pos]<='9') l->pos++; }
- `smaug_json.c:212` — if (l->pos < l->len && (l->buf[l->pos]=='e' || l->buf[l->pos]=='E')) { l->is_int=0; l->pos++; if (l->pos<l->len && (l->buf[l->pos]=='+'||l->buf[l->pos]=='-')) l->pos++; while(l->pos<l->len && l->buf[l->pos]>='0' && l->buf[l->pos]<='9') l->pos++; }
- `smaug_json.c:214` — if (numlen >= sizeof(tmp)) numlen = sizeof(tmp)-1;
- `smaug_json.c:216` — if (l->is_int) { char *e; errno=0; l->int_val=strtoll(tmp,&e,10); if (*e) l->is_int=0; }
- `smaug_json.c:217` — if (!l->is_int) { char *e; errno=0; l->num_val=strtod(tmp,&e); if (*e||errno) return TOK_ERROR; }
- `smaug_json.c:276` — if (t == TOK_RBRACE) return 1;  /* objeto vazio */
- `smaug_json.c:281` — if (next_token(l) != TOK_COLON) { free(key); return 0; }
- `smaug_json.c:290` — if (!nk || !nv) { free(key); if (val.type==4) free(val.s); return 0; }
- `smaug_json.c:299` — if (t != TOK_COMMA)  return 0;
- `smaug_json.c:323` — while (t != TOK_RBRACKET && t != TOK_EOF && t != TOK_ERROR) {
- `smaug_json.c:324` — if (t != TOK_LBRACE) {
- `smaug_json.c:325` — for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
- `smaug_json.c:332` — if (!tmp) {
- `smaug_json.c:333` — for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
- `smaug_json.c:354` — return empty ? empty : make_error("smaug_read_json: OOM");
- `smaug_json.c:382` — for (size_t c = 0; c < n_cols && c < recs[r].count; c++) {
- `smaug_json.c:396` — if (dtypes[c] == DT_UNKNOWN) dtypes[c] = DT_STR;
- `smaug_json.c:425` — json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
- `smaug_json.c:427` — else if (v->type == 1)  smaug_i64_set(s, r, v->i);
- `smaug_json.c:428` — else if (v->type == 2)  smaug_i64_set(s, r, (int64_t)v->d);
- `smaug_json.c:437` — json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
- `smaug_json.c:440` — else if (v->type == 1)  smaug_f64_set(s, r, (double)v->i);
- `smaug_json.c:449` — json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
- `smaug_json.c:451` — else if (v->type == 3)  smaug_bool_set(s, r, v->b);
- `smaug_json.c:460` — json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
- `smaug_json.c:462` — else if (v->type == 4 && v->s) smaug_str_set(s, r, v->s, strlen(v->s));
- `smaug_json.c:464` — if (v->type==1) n=snprintf(tmp,sizeof(tmp),"%lld",(long long)v->i);
- `smaug_json.c:465` — else if (v->type==2) n=snprintf(tmp,sizeof(tmp),"%.17g",v->d);
- `smaug_json.c:466` — else if (v->type==3) { strcpy(tmp,v->b?"true":"false"); n=strlen(tmp); }
- `smaug_json.c:494` — if (sz < 0) { fclose(f); return NULL; }
- `smaug_json.c:496` — if (!buf) { fclose(f); return NULL; }
- `smaug_json.c:521` — while (ncap <= b->len + n) ncap *= 2;
- `smaug_json.c:532` — if (wbj_pushc(b, '"')) return -1;
- `smaug_json.c:549` — if (!t || !out_len) return NULL;
- `smaug_json.c:557` — if (wbj_pushz(&b, nl)) goto oom;
- `smaug_json.c:560` — if (wbj_pushz(&b, ind)) goto oom;
- `smaug_json.c:561` — if (wbj_pushc(&b, '{')) goto oom;
- `smaug_json.c:562` — if (wbj_pushz(&b, nl)) goto oom;
- `smaug_json.c:565` — if (wbj_pushz(&b, ind2)) goto oom;
- `smaug_json.c:568` — if (write_json_string(&b, n, strlen(n))) goto oom;
- `smaug_json.c:569` — if (wbj_pushc(&b, ':')) goto oom;
- `smaug_json.c:570` — if (pretty && wbj_pushc(&b, ' ')) goto oom;
- `smaug_json.c:578` — if (st == SMG_NULL_VALUE || st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; }
- `smaug_json.c:579` — else { snprintf(tmp,sizeof(tmp),"%lld",(long long)v); if (wbj_pushz(&b,tmp)) goto oom; }
- `smaug_json.c:583` — if (st == SMG_NULL_VALUE || st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; }
- `smaug_json.c:585` — else { snprintf(tmp,sizeof(tmp),"%.17g",v); if (wbj_pushz(&b,tmp)) goto oom; }
- `smaug_json.c:589` — if (st == SMG_NULL_VALUE || st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; }
- `smaug_json.c:590` — else { if (wbj_pushz(&b, v ? "true" : "false")) goto oom; }
- `smaug_json.c:594` — if (!sv) { if (wbj_pushz(&b,"null")) goto oom; }
- `smaug_json.c:595` — else { if (write_json_string(&b, sv, slen)) goto oom; }
- `smaug_json.c:596` — } else { if (wbj_pushz(&b,"null")) goto oom; }
- `smaug_json.c:598` — if (c + 1 < t->ncols) { if (wbj_pushc(&b,',')) goto oom; }
- `smaug_json.c:599` — if (wbj_pushz(&b, nl)) goto oom;
- `smaug_json.c:602` — if (wbj_pushz(&b, ind)) goto oom;
- `smaug_json.c:603` — if (wbj_pushc(&b, '}')) goto oom;
- `smaug_json.c:604` — if (r + 1 < t->nrows) { if (wbj_pushc(&b,',')) goto oom; }
- `smaug_json.c:605` — if (wbj_pushz(&b, nl)) goto oom;
- `smaug_json.c:608` — if (wbj_pushc(&b, ']')) goto oom;
- `smaug_json.c:609` — if (wbj_pushc(&b, '\n')) goto oom;
- `smaug_json.c:610` — if (wbj_pushc(&b, '\0')) goto oom;
- `smaug_json.c:621` — if (!buf) return -1;
- `smaug_json.c:625` — return (w == len) ? 0 : -1;

**`smaug_datetime.c`** — 58 linha(s) com ramo descoberto:
- `smaug_datetime.c:234` — if (!s)             { if (status) *status = SMG_ERR_ARGUMENT; return DT_SENTINEL; }
- `smaug_datetime.c:235` — if (idx >= s->size) { if (status) *status = SMG_ERR_OOB;      return DT_SENTINEL; }
- `smaug_datetime.c:236` — if (INVALID_DT(s, idx)) { if (status) *status = SMG_NULL_VALUE; return DT_SENTINEL; }
- `smaug_datetime.c:237` — if (status) *status = SMG_OK;
- `smaug_datetime.c:244` — if (dt_cow_detach(s) != 0) return SMG_ERR_NOMEM;
- `smaug_datetime.c:251` — if (!s)             return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:253` — if (dt_cow_detach(s) != 0) return SMG_ERR_NOMEM;
- `smaug_datetime.c:260` — if (!s || idx >= s->size) return true;
- `smaug_datetime.c:266` — if (dt_cow_detach(s) != 0) return -1;
- `smaug_datetime.c:277` — if (!s) return -1;
- `smaug_datetime.c:278` — if (dt_cow_detach(s) != 0) return -1;
- `smaug_datetime.c:279` — if (s->size >= s->capacity) {
- `smaug_datetime.c:280` — if (dt_grow(s) != 0) return -1;
- `smaug_datetime.c:306` — if (p[i] < '0' || p[i] > '9') return NULL;
- `smaug_datetime.c:321` — if (p >= end || *p++ != '-')                   return -1;
- `smaug_datetime.c:322` — if (!(p = parse_digits(p, end, 2, &mo)))      return -1;
- `smaug_datetime.c:323` — if (p >= end || *p++ != '-')                   return -1;
- `smaug_datetime.c:324` — if (!(p = parse_digits(p, end, 2, &d)))       return -1;
- `smaug_datetime.c:330` — if (p < end && (*p == 'T' || *p == ' ')) {
- `smaug_datetime.c:332` — if (!(p = parse_digits(p, end, 2, &h)))   return -1;
- `smaug_datetime.c:333` — if (p >= end || *p++ != ':')               return -1;
- `smaug_datetime.c:334` — if (!(p = parse_digits(p, end, 2, &mi)))  return -1;
- `smaug_datetime.c:335` — if (p >= end || *p++ != ':')               return -1;
- `smaug_datetime.c:336` — if (!(p = parse_digits(p, end, 2, &sec))) return -1;
- `smaug_datetime.c:337` — if (h > 23 || mi > 59 || sec > 59)        return -1;
- `smaug_datetime.c:345` — while (p < end && *p >= '0' && *p <= '9') {
- `smaug_datetime.c:346` — if (cnt < 3) ms_val = ms_val * 10 + (*p - '0');
- `smaug_datetime.c:350` — while (cnt < 3) { ms_val *= 10; cnt++; }
- `smaug_datetime.c:358` — } else if (*p == '+' || *p == '-') {
- `smaug_datetime.c:361` — if (!(p = parse_digits(p, end, 2, &tz_h))) return -1;
- `smaug_datetime.c:362` — if (p < end && *p == ':') p++;
- `smaug_datetime.c:363` — if (!(p = parse_digits(p, end, 2, &tz_m))) return -1;
- `smaug_datetime.c:364` — if (tz_h > 23 || tz_m > 59) return -1;
- `smaug_datetime.c:408` — return (written > 0 && (size_t)written < buf_size) ? 0 : -1;
- `smaug_datetime.c:453` — if (wd < 0) wd += 7;
- `smaug_datetime.c:484` — if (week < 1) {
- `smaug_datetime.c:489` — if (wd_dec28 < 0) wd_dec28 += 7;
- `smaug_datetime.c:496` — } else if (week > 52) {
- `smaug_datetime.c:500` — if (wd_dec28 < 0) wd_dec28 += 7;
- `smaug_datetime.c:502` — if (wd_dec28 > 3) week = 1; /* pertence à semana 1 do próximo ano */
- `smaug_datetime.c:514` — if (hour < 0 || hour > 23 || minute < 0 || minute > 59 ||
- `smaug_datetime.c:515` — second < 0 || second > 59 || ms < 0 || ms > 999) return DT_SENTINEL;
- `smaug_datetime.c:537` — if ((delta_ms > 0 && result < epoch_ms) ||
- `smaug_datetime.c:538` — (delta_ms < 0 && result > epoch_ms)) return DT_SENTINEL;
- `smaug_datetime.c:546` — - (epoch_ms < 0 && epoch_ms % MS_PER_SECOND != 0 ? MS_PER_SECOND : 0);
- `smaug_datetime.c:549` — - (epoch_ms < 0 && epoch_ms % MS_PER_MINUTE != 0 ? MS_PER_MINUTE : 0);
- `smaug_datetime.c:552` — - (epoch_ms < 0 && epoch_ms % MS_PER_HOUR != 0 ? MS_PER_HOUR : 0);
- `smaug_datetime.c:607` — DT_CMP_IMPL(gt, > )
- `smaug_datetime.c:608` — DT_CMP_IMPL(lt, < )
- `smaug_datetime.c:609` — DT_CMP_IMPL(eq, ==)
- `smaug_datetime.c:610` — DT_CMP_IMPL(ge, >=)
- `smaug_datetime.c:611` — DT_CMP_IMPL(le, <=)
- `smaug_datetime.c:612` — DT_CMP_IMPL(ne, !=)
- `smaug_datetime.c:624` — if (ea->val > eb->val) return  1;
- `smaug_datetime.c:639` — if (!entries) return NULL;
- `smaug_datetime.c:650` — if (!indices) { free(entries); return NULL; }
- `smaug_datetime.c:681` — if (!s || !idx) return NULL;
- `smaug_datetime.c:698` — if (!s || !mask) return NULL;

**`smaug_ops_window.c`** — 30 linha(s) com ramo descoberto:
- `smaug_ops_window.c:32` — switch (col->kind) {
- `smaug_ops_window.c:110` — if (!idx) return NULL;
- `smaug_ops_window.c:113` — if (!tmp) { free(idx); return NULL; }
- `smaug_ops_window.c:133` — if (!ffi_cols || ncols == 0 || nrows == 0) return NULL;
- `smaug_ops_window.c:136` — if (!cols) return NULL;
- `smaug_ops_window.c:193` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:210` — if (cnt == 0) continue;  /* janela toda nula → NA */
- `smaug_ops_window.c:222` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:236` — if (cnt == 0) continue;
- `smaug_ops_window.c:248` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:258` — if (i + 1 >= window && !deque_empty(&dq) &&
- `smaug_ops_window.c:259` — deque_front(&dq) + window <= i) {
- `smaug_ops_window.c:276` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
- `smaug_ops_window.c:278` — if (deque_empty(&dq)) continue;
- `smaug_ops_window.c:292` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:301` — if (i + 1 >= window && !deque_empty(&dq) &&
- `smaug_ops_window.c:302` — deque_front(&dq) + window <= i) {
- `smaug_ops_window.c:307` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
- `smaug_ops_window.c:316` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
- `smaug_ops_window.c:318` — if (deque_empty(&dq)) continue;
- `smaug_ops_window.c:333` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:346` — if (i + 1 < window || cnt == 0) continue;
- `smaug_ops_window.c:355` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:377` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:394` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
- `smaug_ops_window.c:396` — if (deque_empty(&dq)) continue;
- `smaug_ops_window.c:407` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:416` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
- `smaug_ops_window.c:424` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
- `smaug_ops_window.c:426` — if (deque_empty(&dq)) continue;

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
- `smaug_csv.c:37` — falha de syscall não simulável sem mock
- `smaug_csv.c:39` — ftell negativo só em fd inválido
- `smaug_csv.c:42` — OOM de malloc no read_file
- `smaug_csv.c:110` — loop externo garante pos < len antes de chamar
- `smaug_csv.c:147` — só falha se PUSH falhou por OOM
- `smaug_csv.c:160` — default_opts garante sep!=0
- `smaug_csv.c:161` — default_opts garante quote!=0
- `smaug_csv.c:195` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:195` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:195` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:204` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:204` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:204` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:204` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:218` — rows[0] nunca NULL — n_rows>0 garante alocação
- `smaug_csv.c:219` — next_field sempre produz >=1 campo por linha
- `smaug_csv.c:229` — c<n_cols<=row_sizes[0] por construção
- `smaug_csv.c:303` — dtype inferido garante try_i64=1
- `smaug_csv.c:316` — dtype inferido garante try_f64=1
- `smaug_csv.c:317` — idem para inteiros em coluna float
- `smaug_csv.c:317` — idem para inteiros em coluna float
- `smaug_csv.c:330` — dtype inferido garante try_bool=1
- `smaug_csv.c:427` — write_default_opts garante sep!=0
- `smaug_csv.c:428` — write_default_opts garante quote!=0
- `smaug_csv.c:434` — name sempre não-NULL após construção
- `smaug_json.c:113` — string não fechada — break inalcançável em JSON bem-formado
- `smaug_json.c:148` — OOM de realloc em string JSON
- `smaug_json.c:148` — OOM de realloc em string JSON
- `smaug_json.c:426` — !v só quando record tem menos campos que esperado
- `smaug_json.c:438` — !v só quando record tem menos campos
- `smaug_json.c:450` — !v só quando record tem menos campos
- `smaug_json.c:461` — !v só quando record tem menos campos
- `smaug_json.c:535` — OOM de wbuf sem injeção
- `smaug_json.c:536` — OOM de wbuf sem injeção
- `smaug_json.c:537` — OOM de wbuf sem injeção
- `smaug_json.c:538` — OOM de wbuf sem injeção
- `smaug_json.c:538` — OOM de wbuf sem injeção
- `smaug_json.c:538` — OOM de wbuf sem injeção
- `smaug_json.c:539` — OOM de wbuf sem injeção
- `smaug_json.c:540` — OOM de wbuf sem injeção
- `smaug_json.c:541` — OOM de wbuf sem injeção
- `smaug_json.c:550` — NULL opts usa default 0; opts não-NULL cobre ambos
- `smaug_json.c:567` — name sempre não-NULL após construção
- `smaug_json.c:584` — OOM de wbuf + NaN→null: ramo oom inalcançável sem injeção
- `smaug_json.c:591` — dtype inferido garante exatamente um ponteiro não-NULL
- `smaug_datetime.c:63` — ramo z<0 no algoritmo de Hinnant — datas antes de ~292Mi a.C.
- `smaug_datetime.c:81` — ramo Y<0 no algoritmo de Hinnant — datas antes de ~292Mi a.C.
- `smaug_datetime.c:110` — overflow de capacity
- `smaug_datetime.c:118` — realloc de shrink após falha — padrão defensivo documentado
- `smaug_datetime.c:120` — realloc de shrink
- `smaug_datetime.c:120` — realloc de shrink
- `smaug_datetime.c:131` — view size==0 — caso degenerado de view vazia
- `smaug_datetime.c:138` — OOM em malloc de buffers COW — coberto por test_allocfail
- `smaug_datetime.c:138` — OOM em malloc de buffers COW — coberto por test_allocfail
- `smaug_datetime.c:152` — size > capacity — invariante; create() nunca viola
- `smaug_datetime.c:205` — size==0 — clone de série vazia tem size=0, memcpy não executado
- `smaug_datetime.c:215` — args inválidos — start > size ou len > size-start
