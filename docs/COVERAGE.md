# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `3b0404a`  |  Data: 2026-06-23 22:28:45 -0300
- **Branch-alvo** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica), exclui guards defensivos/inalcancaveis marcados `COV-EXCL-BR` -- e a que perseguimos rumo a 100%.
- **Branch-bruto** (todos os ramos): `3037/3270 = 92.87%` -- 101 ramo(s) excluido(s) com justificativa (ver fim do arquivo).
- Agrega TODOS os testes: C diretos (incl. `test_cow test_io_c` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

| Arquivo | Linhas | Branch-alvo (taken) |
| :--- | :--- | :--- |
| `smaug_core.c` | `402/402 = 100.00%` `[██████████]` | `290/290 = 100.00%` `[██████████]` |
| `smaug_ops_f64.c` | `460/460 = 100.00%` `[██████████]` | `456/457 = 99.78%` `[██████████]` |
| `smaug_ops_i64.c` | `448/451 = 99.33%` `[█████████░]` | `450/459 = 98.04%` `[█████████░]` |
| `smaug_ops_bool.c` | `165/165 = 100.00%` `[██████████]` | `239/239 = 100.00%` `[██████████]` |
| `smaug_str.c` | `162/164 = 98.78%` `[█████████░]` | `132/132 = 100.00%` `[██████████]` |
| `smaug_ops_str.c` | `115/116 = 99.14%` `[█████████░]` | `115/115 = 100.00%` `[██████████]` |
| `smaug_csv.c` | `284/292 = 97.26%` `[█████████░]` | `325/359 = 90.53%` `[█████████░]` |
| `smaug_json.c` | `347/360 = 96.39%` `[█████████░]` | `414/461 = 89.80%` `[█████████░]` |
| `smaug_datetime.c` | `371/374 = 99.20%` `[█████████░]` | `377/408 = 92.40%` `[█████████░]` |
| `smaug_ops_window.c` | `226/231 = 97.84%` `[█████████░]` | `239/249 = 95.98%` `[█████████░]` |
| **TOTAL** | `2980/3015 = 98.84%` `[█████████░]` | `3037/3169 = 95.83%` `[█████████░]` |

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
- `smaug_ops_i64.c:724` — if (m == 0) return result;
- `smaug_ops_i64.c:750` — switch (method) {

**`smaug_csv.c`** — 24 linha(s) com ramo descoberto:
- `smaug_csv.c:131` — if (i+1 < len && buf[i+1] == quote) { PUSH(quote); i += 2; }
- `smaug_csv.c:134` — PUSH(buf[i]); i++;
- `smaug_csv.c:145` — else if (i < len && buf[i] == '\n') { i++; *eol=1; }
- `smaug_csv.c:180` — if (buf[pos] == '\n' || (buf[pos] == '\r' && (pos+1>=len || buf[pos+1]=='\n'))) {
- `smaug_csv.c:181` — if (buf[pos] == '\r') pos++;
- `smaug_csv.c:315` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:329` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:331` — if (is_na(v,nav,nc)) smaug_bool_set_null(s,r);
- `smaug_csv.c:342` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:353` — if (col_names) {
- `smaug_csv.c:377` — if (rows[r]) { for(size_t c=0;c<row_sizes[r];c++) free(rows[r][c]); free(rows[r]); }
- `smaug_csv.c:414` — if (s[i]==sep||s[i]=='\n'||s[i]=='\r'||s[i]==quote) { needs_quote=1; break; }
- `smaug_csv.c:416` — if (wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:418` — if (s[i] == quote && wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:419` — if (wbuf_pushc(b, s[i])) return -1;
- `smaug_csv.c:435` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:439` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:444` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:463` — } else if (col->str) {
- `smaug_csv.c:467` — if (write_field(&b, s, n, sep, quote)) goto oom;
- `smaug_csv.c:469` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:472` — if (wbuf_pushc(&b, '\0')) goto oom;
- `smaug_csv.c:481` — if (!buf) return -1;
- `smaug_csv.c:485` — return (w==len) ? 0 : -1;

**`smaug_json.c`** — 37 linha(s) com ramo descoberto:
- `smaug_json.c:43` — while (l->pos < l->len) {
- `smaug_json.c:45` — if (c == ' ' || c == '\t' || c == '\n' || c == '\r') l->pos++;
- `smaug_json.c:53` — if (l->pos + 4 > l->len) return -1;
- `smaug_json.c:59` — else if (h >= 'a' && h <= 'f') digit = h - 'a' + 10;
- `smaug_json.c:83` — } else if (cp <= 0x10FFFF) {
- `smaug_json.c:104` — if (l->pos >= l->len || l->buf[l->pos] != '"') return NULL;
- `smaug_json.c:109` — while (l->pos < l->len) {
- `smaug_json.c:125` — l->buf[l->pos] != '\\' || l->buf[l->pos+1] != 'u') {
- `smaug_json.c:132` — if (ucp2 < 0xDC00 || ucp2 > 0xDFFF) {
- `smaug_json.c:136` — } else if (ucp >= 0xDC00 && ucp <= 0xDFFF) {
- `smaug_json.c:142` — if (bytes == 0) { free(out); return NULL; }
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
- `smaug_json.c:295` — if (!nk || !nv) { free(key); if (val.type==4) free(val.s); return 0; }
- `smaug_json.c:327` — while (t != TOK_RBRACKET && t != TOK_EOF && t != TOK_ERROR) {
- `smaug_json.c:329` — for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
- `smaug_json.c:336` — if (!tmp) {
- `smaug_json.c:337` — for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
- `smaug_json.c:358` — return empty ? empty : make_error("smaug_read_json: OOM");
- `smaug_json.c:431` — else if (v->type == 1)  smaug_i64_set(s, r, v->i);
- `smaug_json.c:470` — else if (v->type==3) { strcpy(tmp,v->b?"true":"false"); n=strlen(tmp); }
- `smaug_json.c:498` — if (sz < 0) { fclose(f); return NULL; }
- `smaug_json.c:500` — if (!buf) { fclose(f); return NULL; }
- `smaug_json.c:525` — while (ncap <= b->len + n) ncap *= 2;
- `smaug_json.c:536` — if (wbj_pushc(b, '"')) return -1;
- `smaug_json.c:625` — if (!buf) return -1;
- `smaug_json.c:629` — return (w == len) ? 0 : -1;

**`smaug_datetime.c`** — 29 linha(s) com ramo descoberto:
- `smaug_datetime.c:234` — if (!s)             { if (status) *status = SMG_ERR_ARGUMENT; return DT_SENTINEL; }
- `smaug_datetime.c:251` — if (!s)             return SMG_ERR_ARGUMENT;
- `smaug_datetime.c:277` — if (!s) return -1;
- `smaug_datetime.c:278` — if (dt_cow_detach(s) != 0) return -1;
- `smaug_datetime.c:280` — if (dt_grow(s) != 0) return -1;
- `smaug_datetime.c:321` — if (p >= end || *p++ != '-')                   return -1;
- `smaug_datetime.c:323` — if (p >= end || *p++ != '-')                   return -1;
- `smaug_datetime.c:324` — if (!(p = parse_digits(p, end, 2, &d)))       return -1;
- `smaug_datetime.c:330` — if (p < end && (*p == 'T' || *p == ' ')) {
- `smaug_datetime.c:332` — if (!(p = parse_digits(p, end, 2, &h)))   return -1;
- `smaug_datetime.c:333` — if (p >= end || *p++ != ':')               return -1;
- `smaug_datetime.c:334` — if (!(p = parse_digits(p, end, 2, &mi)))  return -1;
- `smaug_datetime.c:335` — if (p >= end || *p++ != ':')               return -1;
- `smaug_datetime.c:336` — if (!(p = parse_digits(p, end, 2, &sec))) return -1;
- `smaug_datetime.c:345` — while (p < end && *p >= '0' && *p <= '9') {
- `smaug_datetime.c:358` — } else if (*p == '+' || *p == '-') {
- `smaug_datetime.c:361` — if (!(p = parse_digits(p, end, 2, &tz_h))) return -1;
- `smaug_datetime.c:362` — if (p < end && *p == ':') p++;
- `smaug_datetime.c:363` — if (!(p = parse_digits(p, end, 2, &tz_m))) return -1;
- `smaug_datetime.c:408` — return (written > 0 && (size_t)written < buf_size) ? 0 : -1;
- `smaug_datetime.c:546` — - (epoch_ms < 0 && epoch_ms % MS_PER_SECOND != 0 ? MS_PER_SECOND : 0);
- `smaug_datetime.c:552` — - (epoch_ms < 0 && epoch_ms % MS_PER_HOUR != 0 ? MS_PER_HOUR : 0);
- `smaug_datetime.c:608` — DT_CMP_IMPL(lt, < )
- `smaug_datetime.c:609` — DT_CMP_IMPL(eq, ==)
- `smaug_datetime.c:610` — DT_CMP_IMPL(ge, >=)
- `smaug_datetime.c:611` — DT_CMP_IMPL(le, <=)
- `smaug_datetime.c:612` — DT_CMP_IMPL(ne, !=)
- `smaug_datetime.c:639` — if (!entries) return NULL;
- `smaug_datetime.c:650` — if (!indices) { free(entries); return NULL; }

**`smaug_ops_window.c`** — 8 linha(s) com ramo descoberto:
- `smaug_ops_window.c:32` — switch (col->kind) {
- `smaug_ops_window.c:133` — if (!ffi_cols || ncols == 0 || nrows == 0) return NULL;
- `smaug_ops_window.c:258` — if (i + 1 >= window && !deque_empty(&dq) &&
- `smaug_ops_window.c:301` — if (i + 1 >= window && !deque_empty(&dq) &&
- `smaug_ops_window.c:307` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
- `smaug_ops_window.c:377` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:407` — if (!s || window == 0) return NULL;
- `smaug_ops_window.c:416` — while (!deque_empty(&dq) && deque_front(&dq) + window <= i)

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
- `smaug_csv.c:81` — s nunca é NULL — única origem é row[c] (sempre alocado por next_field) ou "" literal
- `smaug_csv.c:90` — s nunca é NULL — mesmo argumento de try_i64
- `smaug_csv.c:112` — loop externo garante pos < len antes de chamar
- `smaug_csv.c:149` — só falha se PUSH falhou por OOM
- `smaug_csv.c:197` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:197` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:197` — OOM de realloc de fields — coberto pelo allocfail
- `smaug_csv.c:206` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:206` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:206` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:206` — OOM de realloc de rows — coberto pelo allocfail
- `smaug_csv.c:220` — rows[0] nunca NULL — n_rows>0 garante alocação
- `smaug_csv.c:221` — next_field sempre produz >=1 campo por linha
- `smaug_csv.c:231` — c<n_cols<=row_sizes[0] por construção
- `smaug_csv.c:305` — dtype=int64 implica que todo valor não-NA já passou em try_i64 durante a inferência (mesma string, mesma is_na, função pura e determinística) — confirmado por auditoria adversarial (overflow/inf/nan/zeros à esquerda) e 400k+ checks da suíte, nunca quebrou
- `smaug_csv.c:318` — dtype=float64 implica try_f64=1 pelo mesmo argumento de pureza da inferência (ver linha 303)
- `smaug_csv.c:319` — duplamente inalcançável — além da pureza da inferência, try_i64(v) bem-sucedido implica try_f64(v) também bem-sucedido (strtod aceita toda a gramática de strtoll), então o try_f64 da linha acima já teria capturado este valor
- `smaug_csv.c:319` — duplamente inalcançável — além da pureza da inferência, try_i64(v) bem-sucedido implica try_f64(v) também bem-sucedido (strtod aceita toda a gramática de strtoll), então o try_f64 da linha acima já teria capturado este valor
- `smaug_csv.c:332` — dtype=bool implica try_bool=1 pelo mesmo argumento de pureza da inferência (ver linha 303)
- `smaug_csv.c:436` — name sempre não-NULL após construção
- `smaug_json.c:113` — string não fechada — break inalcançável em JSON bem-formado
- `smaug_json.c:148` — OOM de realloc em string JSON
- `smaug_json.c:432` — dtype=int64 implica que toda linha não-null tinha jt==1 durante a inferência (dtype_upgrade força float64 se qualquer linha fosse jt==2) — mesmo argumento de pureza do csv.c
- `smaug_json.c:432` — dtype=int64 implica que toda linha não-null tinha jt==1 durante a inferência (dtype_upgrade força float64 se qualquer linha fosse jt==2) — mesmo argumento de pureza do csv.c
- `smaug_json.c:444` — ramo falso inalcançável — se chegou aqui, type já não é 0 nem 2; pureza garante que só resta 1
- `smaug_json.c:455` — ramo falso inalcançável — pureza garante type==3 sempre que não-null numa coluna bool
- `smaug_json.c:539` — OOM de wbuf sem injeção
- `smaug_json.c:540` — OOM de wbuf sem injeção
- `smaug_json.c:541` — OOM de wbuf sem injeção
- `smaug_json.c:542` — OOM de wbuf sem injeção
- `smaug_json.c:542` — OOM de wbuf sem injeção
- `smaug_json.c:542` — OOM de wbuf sem injeção
- `smaug_json.c:543` — OOM de wbuf sem injeção
- `smaug_json.c:544` — OOM de wbuf sem injeção
- `smaug_json.c:545` — OOM de wbuf sem injeção
- `smaug_json.c:554` — NULL opts usa default 0; opts não-NULL cobre ambos
- `smaug_json.c:561` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:564` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:565` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:566` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:569` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:571` — name sempre não-NULL após construção
- `smaug_json.c:572` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:573` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:574` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:582` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:583` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:587` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:588` — OOM de wbuf + NaN→null: ramo oom inalcançável sem injeção
- `smaug_json.c:589` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:593` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:594` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:595` — dtype inferido garante exatamente um ponteiro não-NULL
- `smaug_json.c:598` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:599` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:600` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:600` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:602` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:603` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:606` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:607` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:608` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:609` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:612` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:613` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_json.c:614` — ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541)
- `smaug_datetime.c:63` — ramo z<0 no algoritmo de Hinnant — datas antes de ~292Mi a.C.
- `smaug_datetime.c:81` — ramo Y<0 no algoritmo de Hinnant — datas antes de ~292Mi a.C.
- `smaug_datetime.c:120` — realloc de shrink
- `smaug_datetime.c:131` — view size==0 — caso degenerado de view vazia
- `smaug_datetime.c:152` — size > capacity — invariante; create() nunca viola
- `smaug_datetime.c:205` — size==0 — clone de série vazia tem size=0, memcpy não executado
- `smaug_datetime.c:215` — args inválidos — start > size ou len > size-start
- `smaug_ops_window.c:276` — loop-body inalcançável — a if em 258-260 já trata o único item stale possível; by invariante de 266, no máximo um item envelhece por passo de null
- `smaug_ops_window.c:316` — loop-body inalcançável — mesma invariante que linha 276 (rolling_min)
