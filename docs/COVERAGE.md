# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `f93d4a5`  |  Data: 2026-10-08 01:03:56 -0300
- **Branch-alvo** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica), exclui guards defensivos/inalcancaveis marcados `COV-EXCL-BR` -- e a que perseguimos rumo a 100%.
- **Branch-bruto** (todos os ramos): `5332/5896 = 90.43%` -- 104 ramo(s) excluido(s) com justificativa (ver fim do arquivo).
- Agrega TODOS os testes: C diretos (incl. `test_cow test_io_c` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

<a id="coverage-total"></a>

| Arquivo | Linhas | Branch-alvo (taken) |
| :--- | :--- | :--- |
| `smaug_astype.c` | `178/192 = 92.71%` `[█████████░]` | `152/166 = 91.57%` `[█████████░]` |
| `smaug_convert.c` | `316/325 = 97.23%` `[█████████░]` | `306/332 = 92.17%` `[█████████░]` |
| `smaug_core.c` | `428/428 = 100.00%` `[██████████]` | `343/350 = 98.00%` `[█████████░]` |
| `smaug_csv.c` | `512/549 = 93.26%` `[█████████░]` | `433/535 = 80.93%` `[████████░░]` |
| `smaug_datetime.c` | `585/594 = 98.48%` `[█████████░]` | `753/820 = 91.83%` `[█████████░]` |
| `smaug_io_schema.c` | `122/133 = 91.73%` `[█████████░]` | `74/89 = 83.15%` `[████████░░]` |
| `smaug_json.c` | `798/841 = 94.89%` `[█████████░]` | `658/748 = 87.97%` `[████████░░]` |
| `smaug_ops_bool.c` | `314/320 = 98.12%` `[█████████░]` | `380/407 = 93.37%` `[█████████░]` |
| `smaug_ops_f64.c` | `558/558 = 100.00%` `[██████████]` | `640/644 = 99.38%` `[█████████░]` |
| `smaug_ops_i64.c` | `573/582 = 98.45%` `[█████████░]` | `633/674 = 93.92%` `[█████████░]` |
| `smaug_ops_str.c` | `278/285 = 97.54%` `[█████████░]` | `318/342 = 92.98%` `[█████████░]` |
| `smaug_ops_window.c` | `335/342 = 97.95%` `[█████████░]` | `355/397 = 89.42%` `[████████░░]` |
| `smaug_schema.c` | `26/26 = 100.00%` `[██████████]` | `33/34 = 97.06%` `[█████████░]` |
| `smaug_str.c` | `297/297 = 100.00%` `[██████████]` | `254/254 = 100.00%` `[██████████]` |
| **TOTAL** | `5320/5472 = 97.22%` `[█████████░]` | `5332/5792 = 92.06%` `[█████████░]` |

## Ramos descobertos (mapa real, derivado do .gcov)

Alvos concretos de endurecimento rumo a **branch-alvo 100%** (MC/DC):

**`smaug_astype.c`** — 11 linha(s) com ramo descoberto:
- `smaug_astype.c:189` — if (self->size > SIZE_MAX / 20) {
- `smaug_astype.c:194` — if (!result_series) {
- `smaug_astype.c:203` — if (formatted_length == 0) {
- `smaug_astype.c:211` — if (append_status != 0) {
- `smaug_astype.c:224` — if (self->size > SIZE_MAX / 24) {
- `smaug_astype.c:229` — if (!result_series) {
- `smaug_astype.c:246` — if (append_status != 0) {
- `smaug_astype.c:295` — if (!result_series) {
- `smaug_astype.c:307` — } else if (parse_status != SMG_ERR_SYNTAX &&
- `smaug_astype.c:308` — parse_status != SMG_ERR_OVERFLOW &&
- `smaug_astype.c:338` — parse_status != SMG_ERR_OVERFLOW &&

**`smaug_convert.c`** — 20 linha(s) com ramo descoberto:
- `smaug_convert.c:137` — if (!text || !output) {
- `smaug_convert.c:225` — if (offset > SIZE_MAX - exponent_quads) {
- `smaug_convert.c:226` — return offset_negative ? -2048 : 2048;
- `smaug_convert.c:235` — if (magnitude > 512) {
- `smaug_convert.c:236` — return total_negative ? -2048 : 2048;
- `smaug_convert.c:250` — if (*text == '+' || *text == '-') {
- `smaug_convert.c:262` — for (; *text && *text != 'p' && *text != 'P'; text++) {
- `smaug_convert.c:288` — *output = negative ? -0.0 : 0.0;
- `smaug_convert.c:300` — rounding != FE_UPWARD && rounding != FE_DOWNWARD) {
- `smaug_convert.c:317` — sticky = sticky || (prefix & ((UINT64_C(1) << (shift - 1)) - 1)) != 0;
- `smaug_convert.c:318` — if ((round_away && (guard || sticky)) ||
- `smaug_convert.c:378` — if (!parse_end || (size_t)(parse_end - text) != length) {
- `smaug_convert.c:394` — if ((rounding == FE_UPWARD && !negative) ||
- `smaug_convert.c:395` — (rounding == FE_DOWNWARD && negative)) {
- `smaug_convert.c:396` — parsed_value = negative ? -DBL_TRUE_MIN : DBL_TRUE_MIN;
- `smaug_convert.c:435` — if (length == SIZE_MAX) {
- `smaug_convert.c:476` — if (!buffer || length <= 0 || (size_t)length >= capacity) {
- `smaug_convert.c:486` — if (length < 0 || (size_t)length >= sizeof(temporary)) {
- `smaug_convert.c:514` — if (!uselocale(previous_locale)) {
- `smaug_convert.c:536` — if (length < 0 || (size_t)length >= sizeof(temporary)) {

**`smaug_core.c`** — 7 linha(s) com ramo descoberto:
- `smaug_core.c:41` — if (a == 0 || b == 0) {
- `smaug_core.c:42` — if (out) *out = 0;
- `smaug_core.c:46` — (a > 0 && b < 0 && b < INT64_MIN / a) ||
- `smaug_core.c:47` — (a < 0 && b > 0 && a < INT64_MIN / b) ||
- `smaug_core.c:48` — (a < 0 && b < 0 && a < INT64_MAX / b)) return false;
- `smaug_core.c:54` — if (b == 0 || (a == INT64_MIN && b == -1)) return false;
- `smaug_core.c:473` — if (s->size >= s->capacity) {

**`smaug_csv.c`** — 64 linha(s) com ramo descoberto:
- `smaug_csv.c:101` — if (!text || !output) {
- `smaug_csv.c:110` — if (length == SIZE_MAX) {
- `smaug_csv.c:186` — if (i+1 < len && buf[i+1] == quote) { PUSH(quote); i += 2; }
- `smaug_csv.c:188` — } else if (buf[i] == '\r') {
- `smaug_csv.c:189` — if (i + 1 >= len || buf[i + 1] != '\n') {
- `smaug_csv.c:192` — PUSH('\r'); PUSH('\n'); i += 2;
- `smaug_csv.c:194` — PUSH(buf[i]); i++;
- `smaug_csv.c:200` — if (i < len && buf[i] != sep && buf[i] != '\n' && buf[i] != '\r') {
- `smaug_csv.c:208` — PUSH(buf[i]); i++;
- `smaug_csv.c:220` — else if (i < len && buf[i] == '\n') { i++; *eol=1; }
- `smaug_csv.c:253` — switch (dtype) {
- `smaug_csv.c:283` — if (column_count > SIZE_MAX / sizeof(size_t)) {
- `smaug_csv.c:326` — descriptor->dtype, text, options->decimal ? options->decimal : '.');
- `smaug_csv.c:343` — if (!buffer && length > 0) {
- `smaug_csv.c:353` — char decimal = options->decimal ? options->decimal : '.';
- `smaug_csv.c:390` — if (length >= 3 && (unsigned char)buffer[0] == 0xef &&
- `smaug_csv.c:391` — (unsigned char)buffer[1] == 0xbb && (unsigned char)buffer[2] == 0xbf) {
- `smaug_csv.c:397` — if (buffer[position] == '\n' || (buffer[position] == '\r' &&
- `smaug_csv.c:398` — (position + 1 >= length || buffer[position + 1] == '\n'))) {
- `smaug_csv.c:399` — if (buffer[position] == '\r') {
- `smaug_csv.c:423` — switch (field_error) {
- `smaug_csv.c:434` — if (written < 0 || (size_t)written >= sizeof(message)) {
- `smaug_csv.c:442` — if (field_capacity > SIZE_MAX / sizeof(smaug_io_text_t) / 2) {
- `smaug_csv.c:449` — if (!resized_fields) {
- `smaug_csv.c:459` — if (row_capacity > SIZE_MAX / sizeof(smaug_io_text_t *) / 2 ||
- `smaug_csv.c:492` — if (column_count == 0) {
- `smaug_csv.c:503` — if (written < 0 || (size_t)written >= sizeof(message)) {
- `smaug_csv.c:529` — if (name_length < 0 || (size_t)name_length >= sizeof(generated_name)) {
- `smaug_csv.c:554` — const char *text = (column_index < row_size) ? row[column_index].data : "";
- `smaug_csv.c:555` — size_t text_length = column_index < row_size ? row[column_index].length : 0;
- `smaug_csv.c:569` — if (status == SMG_ERR_NOMEM || status == SMG_ERR_ARGUMENT) {
- `smaug_csv.c:570` — table = make_error(status == SMG_ERR_NOMEM
- `smaug_csv.c:620` — const char *text = (column_index < row_size) ? row[column_index].data : "";
- `smaug_csv.c:621` — size_t text_length = column_index < row_size ? row[column_index].length : 0;
- `smaug_csv.c:628` — if (status != SMG_OK) {
- `smaug_csv.c:649` — const char *text = (column_index < row_size) ? row[column_index].data : "";
- `smaug_csv.c:650` — size_t text_length = column_index < row_size ? row[column_index].length : 0;
- `smaug_csv.c:659` — table = make_error(status == SMG_ERR_NOMEM
- `smaug_csv.c:677` — const char *text = (column_index < row_size) ? row[column_index].data : "";
- `smaug_csv.c:678` — size_t text_length = column_index < row_size ? row[column_index].length : 0;
- `smaug_csv.c:680` — if (is_na(text, text_length, na_values, options->na_lengths, na_count)) {
- `smaug_csv.c:682` — } else if (try_bool(text, text_length, &bool_value)) {
- `smaug_csv.c:701` — const char *text = (column_index < row_size) ? row[column_index].data : "";
- `smaug_csv.c:702` — size_t text_length = column_index < row_size ? row[column_index].length : 0;
- `smaug_csv.c:747` — if (!buffer && length) {
- `smaug_csv.c:756` — if (smaug_schema_validate(schema, &error_field) != SMG_OK) {
- `smaug_csv.c:802` — if (s[i]==sep||s[i]=='\n'||s[i]=='\r'||s[i]==quote) { needs_quote=1; break; }
- `smaug_csv.c:804` — if (wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:806` — if (s[i] == quote && wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:807` — if (wbuf_pushc(b, s[i])) return -1;
- `smaug_csv.c:820` — if (t->ncols && !t->columns) {
- `smaug_csv.c:835` — char decimal = opts->decimal ? opts->decimal : '.'; /* fallback defensivo: campo zerado → '.' */
- `smaug_csv.c:845` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:849` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:854` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:865` — if (n == 0) {
- `smaug_csv.c:881` — for (size_t k = 0; k < n; k++)
- `smaug_csv.c:890` — } else if (col->str) {
- `smaug_csv.c:894` — if (write_field(&b, s, n, sep, quote)) goto oom;
- `smaug_csv.c:896` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:899` — if (wbuf_pushc(&b, '\0')) goto oom;
- `smaug_csv.c:912` — if (!path) {
- `smaug_csv.c:917` — if (!buffer) {
- `smaug_csv.c:929` — return written == length && close_status == 0 ? 0 : -1;

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

**`smaug_io_schema.c`** — 10 linha(s) com ramo descoberto:
- `smaug_io_schema.c:8` — switch (dtype) {
- `smaug_io_schema.c:30` — const char *dtype = field != SIZE_MAX && schema && field < schema->count
- `smaug_io_schema.c:35` — if (count < 0 || (size_t)count >= sizeof(byte_context)) {
- `smaug_io_schema.c:45` — if (written < 0 || (size_t)written >= sizeof(message)) {
- `smaug_io_schema.c:62` — if (schema->count > SIZE_MAX / sizeof(smaug_column_t) ||
- `smaug_io_schema.c:63` — rows > SIZE_MAX / sizeof(double) || rows > SIZE_MAX / sizeof(int64_t) ||
- `smaug_io_schema.c:89` — switch (descriptor->dtype) {
- `smaug_io_schema.c:159` — if (used < capacity) {
- `smaug_io_schema.c:164` — if (capacity > SIZE_MAX / 2) {
- `smaug_io_schema.c:178` — if (fclose(file) != 0 && status == SMG_OK) {

**`smaug_json.c`** — 73 linha(s) com ramo descoberto:
- `smaug_json.c:50` — if (length == 0) {
- `smaug_json.c:84` — if (bytes[offset] < 0x80 || bytes[offset] > 0xbf) {
- `smaug_json.c:105` — if (used == SIZE_MAX || added > SIZE_MAX - used - 1) {
- `smaug_json.c:114` — if (grown > SIZE_MAX / 2) {
- `smaug_json.c:140` — if (l->len - l->pos < 4) return -1;
- `smaug_json.c:146` — else if (h >= 'a' && h <= 'f') digit = h - 'a' + 10;
- `smaug_json.c:170` — } else if (cp <= 0x10FFFF) {
- `smaug_json.c:191` — if (l->pos >= l->len || l->buf[l->pos] != '"') return NULL;
- `smaug_json.c:199` — while (l->pos < l->len) {
- `smaug_json.c:239` — l->buf[l->pos] != '\\' || l->buf[l->pos+1] != 'u') {
- `smaug_json.c:246` — if (ucp2 < 0xDC00 || ucp2 > 0xDFFF) {
- `smaug_json.c:250` — } else if (ucp >= 0xDC00 && ucp <= 0xDFFF) {
- `smaug_json.c:256` — if (bytes == 0) { free(out); return NULL; }
- `smaug_json.c:258` — if (!json_string_reserve(&out, &cap, n, (size_t)bytes)) {
- `smaug_json.c:269` — switch (esc) {
- `smaug_json.c:300` — if (lexer->pos == lexer->len || !json_digit(lexer->buf[lexer->pos])) {
- `smaug_json.c:306` — while (lexer->pos < lexer->len && json_digit(lexer->buf[lexer->pos])) {
- `smaug_json.c:310` — if (lexer->pos < lexer->len && lexer->buf[lexer->pos] == '.') {
- `smaug_json.c:314` — while (lexer->pos < lexer->len && json_digit(lexer->buf[lexer->pos])) {
- `smaug_json.c:321` — if (lexer->pos < lexer->len &&
- `smaug_json.c:325` — if (lexer->pos < lexer->len &&
- `smaug_json.c:330` — while (lexer->pos < lexer->len && json_digit(lexer->buf[lexer->pos])) {
- `smaug_json.c:337` — if (lexer->pos < lexer->len) {
- `smaug_json.c:340` — boundary != ' ' && boundary != '\t' && boundary != '\n' && boundary != '\r') {
- `smaug_json.c:348` — switch (status) {
- `smaug_json.c:381` — if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"true",4)==0)
- `smaug_json.c:385` — if (l->pos + 5 <= l->len && strncmp(l->buf+l->pos,"false",5)==0)
- `smaug_json.c:389` — if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"null",4)==0)
- `smaug_json.c:420` — if (magnitude == 0) {
- `smaug_json.c:506` — if (!lexer->error_reason) {
- `smaug_json.c:521` — if (capacity > SIZE_MAX / sizeof(char *) / 2 ||
- `smaug_json.c:545` — if (!lexer->error_reason) {
- `smaug_json.c:554` — if (value.type == 4) {
- `smaug_json.c:565` — const char *reason = lexer->error_reason ? lexer->error_reason : fallback;
- `smaug_json.c:568` — if (length < 0 || (size_t)length >= sizeof(message)) {
- `smaug_json.c:587` — if (!lexer->error_reason) {
- `smaug_json.c:596` — if (!lexer->error_reason) {
- `smaug_json.c:602` — if (capacity > SIZE_MAX / sizeof(json_record_t) / 2) {
- `smaug_json.c:618` — if (!lexer->error_reason) {
- `smaug_json.c:629` — if (!lexer->error_reason) {
- `smaug_json.c:638` — if (!lexer->error_reason) {
- `smaug_json.c:677` — if (length > SIZE_MAX - extra) {
- `smaug_json.c:685` — for (size_t suffix = 1; suffix != 0; suffix++) {
- `smaug_json.c:687` — if (written < 0 || (size_t)written >= extra) {
- `smaug_json.c:704` — if (records[row].count > SIZE_MAX - capacity) {
- `smaug_json.c:714` — if (capacity > SIZE_MAX / sizeof(smaug_io_text_t) ||
- `smaug_json.c:782` — switch (dtype) {
- `smaug_json.c:801` — if (value->type == 2) {
- `smaug_json.c:867` — reason ? reason : smaug_io_status_reason(status));
- `smaug_json.c:903` — if (!buffer && length) {
- `smaug_json.c:907` — if (length >= 3 && (unsigned char)buffer[0] == 0xef &&
- `smaug_json.c:908` — (unsigned char)buffer[1] == 0xbb && (unsigned char)buffer[2] == 0xbf) {
- `smaug_json.c:928` — if (validation_error) {
- `smaug_json.c:949` — (unsigned char)buf[1] == 0xbb && (unsigned char)buf[2] == 0xbf) {
- `smaug_json.c:966` — return empty ? empty : make_error("OOM");
- `smaug_json.c:979` — if (empty) {
- `smaug_json.c:983` — return empty ? empty : make_error("OOM");
- `smaug_json.c:1062` — else if (v->type == 1)  smaug_i64_set(s, r, v->i);
- `smaug_json.c:1108` — else if (v->type==3) { strcpy(tmp,v->b?"true":"false"); n=strlen(tmp); }
- `smaug_json.c:1110` — if (n == 0 || smaug_str_set(s, r, tmp, n) != SMG_OK) {
- `smaug_json.c:1142` — if (sz < 0) { fclose(f); return NULL; }
- `smaug_json.c:1144` — if (!buf) { fclose(f); return NULL; }
- `smaug_json.c:1169` — while (ncap <= b->len + n) ncap *= 2;
- `smaug_json.c:1180` — if (wbj_pushc(b, '"')) return -1;
- `smaug_json.c:1202` — if (t->ncols && !t->columns) {
- `smaug_json.c:1218` — set_io_error(err_out, written < 0 || (size_t)written >= sizeof(message)
- `smaug_json.c:1230` — set_io_error(err_out, written < 0 || (size_t)written >= sizeof(message)
- `smaug_json.c:1268` — if (smaug_fmt_i64(tmp, sizeof(tmp), v) == 0) {
- `smaug_json.c:1271` — if (wbj_pushz(&b, tmp)) {
- `smaug_json.c:1290` — if (wbj_pushz(&b, tmp)) {
- `smaug_json.c:1334` — if (!path) {
- `smaug_json.c:1339` — if (!buffer) {
- `smaug_json.c:1351` — return written == length && close_status == 0 ? 0 : -1;

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

**`smaug_schema.c`** — 1 linha(s) com ramo descoberto:
- `smaug_schema.c:20` — field->dtype < SMAUG_DTYPE_BOOL || field->dtype > SMAUG_DTYPE_STRING) {

## Ramos excluidos (`COV-EXCL-BR` -- defensivos/inalcancaveis, documentados)

Fora da meta por justificativa tecnica (assert reservado a invariantes internas; estes sao guards defensivos sobre condicoes inalcancaveis na pratica):

- `smaug_astype.c:53` — OOM sem injecao de falha
- `smaug_astype.c:67` — OOM
- `smaug_astype.c:114` — OOM
- `smaug_astype.c:163` — OOM
- `smaug_astype.c:261` — OOM sem injecao
- `smaug_astype.c:273` — OOM no append
- `smaug_core.c:67` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:84` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_core.c:95` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:107` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_core.c:492` — overflow ao dobrar capacity; so com capacity ~ SIZE_MAX
- `smaug_core.c:502` — realloc de shrink falhando; defensivo, mantem buffer maior (seguro)
- `smaug_csv.c:38` — falha de syscall não simulável sem mock
- `smaug_csv.c:40` — ftell negativo só em fd inválido
- `smaug_csv.c:43` — OOM de malloc no read_file
- `smaug_csv.c:158` — loop externo garante pos < len antes de chamar
- `smaug_csv.c:224` — só falha se PUSH falhou por OOM
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
- `smaug_json.c:227` — string não fechada — break inalcançável em JSON bem-formado
- `smaug_json.c:1063` — dtype=int64 implica que toda linha não-null tinha jt==1 durante a inferência (dtype_upgrade força float64 se qualquer linha fosse jt==2) — mesmo argumento de pureza do csv.c
- `smaug_json.c:1063` — dtype=int64 implica que toda linha não-null tinha jt==1 durante a inferência (dtype_upgrade força float64 se qualquer linha fosse jt==2) — mesmo argumento de pureza do csv.c
- `smaug_json.c:1075` — ramo falso inalcançável — se chegou aqui, type já não é 0 nem 2; pureza garante que só resta 1
- `smaug_json.c:1086` — ramo falso inalcançável — pureza garante type==3 sempre que não-null numa coluna bool
- `smaug_json.c:1183` — OOM de wbuf sem injeção
- `smaug_json.c:1184` — OOM de wbuf sem injeção
- `smaug_json.c:1185` — OOM de wbuf sem injeção
- `smaug_json.c:1186` — OOM de wbuf sem injeção
- `smaug_json.c:1186` — OOM de wbuf sem injeção
- `smaug_json.c:1186` — OOM de wbuf sem injeção
- `smaug_json.c:1187` — OOM de wbuf sem injeção
- `smaug_json.c:1188` — OOM de wbuf sem injeção
- `smaug_json.c:1189` — OOM de wbuf sem injeção
- `smaug_json.c:1245` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1248` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1249` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1250` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1253` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1256` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1257` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1258` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1266` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1278` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1285` — OOM de wbuf + nao-finito→null: ramo oom inalcançável sem injeção
- `smaug_json.c:1297` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1298` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1299` — dtype inferido garante exatamente um ponteiro não-NULL
- `smaug_json.c:1302` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1303` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1304` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1304` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1306` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1307` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1310` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1311` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1312` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1313` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1316` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1317` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:1318` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
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
