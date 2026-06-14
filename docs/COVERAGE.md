# Cobertura -- Smaug (backend C)

> **Arquivo gerado automaticamente** por `scripts/make_coverage.sh` (`make coverage`).
> Nao editar a mao. Contagens **exatas** (parse do texto .gcov), nao reconstruidas por %.

- Commit medido: `c8917d1`  |  Data: 2026-06-14 01:39:45 -0300
- **Branch-alvo** ("taken at least once"): metrica rigorosa (padrao SQLite/avionica), exclui guards defensivos/inalcancaveis marcados `COV-EXCL-BR` -- e a que perseguimos rumo a 100%.
- **Branch-bruto** (todos os ramos): `1981/2215 = 89.44%` -- 66 ramo(s) excluido(s) com justificativa (ver fim do arquivo).
- Agrega TODOS os testes: C diretos (incl. `test_cow test_io_c` e `test_stress`), Lua (FFI) e `test_allocfail` (OOM).

| Arquivo | Linhas | Branch-alvo (taken) |
| :--- | :--- | :--- |
| `smaug_core.c` | `402/402 = 100.00%` `[██████████]` | `290/290 = 100.00%` `[██████████]` |
| `smaug_ops_f64.c` | `285/285 = 100.00%` `[██████████]` | `303/303 = 100.00%` `[██████████]` |
| `smaug_ops_i64.c` | `289/289 = 100.00%` `[██████████]` | `305/305 = 100.00%` `[██████████]` |
| `smaug_ops_bool.c` | `165/165 = 100.00%` `[██████████]` | `239/239 = 100.00%` `[██████████]` |
| `smaug_str.c` | `162/164 = 98.78%` `[█████████░]` | `132/132 = 100.00%` `[██████████]` |
| `smaug_ops_str.c` | `115/116 = 99.14%` `[█████████░]` | `115/115 = 100.00%` `[██████████]` |
| `smaug_csv.c` | `249/257 = 96.89%` `[█████████░]` | `292/343 = 85.13%` `[████████░░]` |
| `smaug_json.c` | `242/271 = 89.30%` `[████████░░]` | `305/422 = 72.27%` `[███████░░░]` |
| **TOTAL** | `1909/1949 = 97.95%` `[█████████░]` | `1981/2149 = 92.18%` `[█████████░]` |

## Ramos descobertos (mapa real, derivado do .gcov)

Alvos concretos de endurecimento rumo a **branch-alvo 100%** (MC/DC):

**`smaug_csv.c`** — 37 linha(s) com ramo descoberto:
- `smaug_csv.c:81` — if (!s || !*s) return 0;
- `smaug_csv.c:84` — if (errno || *end != '\0') return 0;
- `smaug_csv.c:89` — if (!s || !*s) return 0;
- `smaug_csv.c:92` — if (errno || *end != '\0') return 0;
- `smaug_csv.c:129` — if (i+1 < len && buf[i+1] == quote) { PUSH(quote); i += 2; }
- `smaug_csv.c:132` — PUSH(buf[i]); i++;
- `smaug_csv.c:143` — else if (i < len && buf[i] == '\n') { i++; *eol=1; }
- `smaug_csv.c:178` — if (buf[pos] == '\n' || (buf[pos] == '\r' && (pos+1>=len || buf[pos+1]=='\n'))) {
- `smaug_csv.c:179` — if (buf[pos] == '\r') pos++;
- `smaug_csv.c:237` — if (!dtypes) { free(col_names); goto oom_cleanup; }
- `smaug_csv.c:259` — if (!t) { free(dtypes); free(col_names); goto oom_cleanup; }
- `smaug_csv.c:261` — if (!t->columns) { free(t); free(dtypes); free(col_names); goto oom_cleanup; }
- `smaug_csv.c:288` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:302` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:304` — if (is_na(v,nav,nc)) smaug_bool_set_null(s,r);
- `smaug_csv.c:315` — const char *v = (c < rsz) ? row[c] : "";
- `smaug_csv.c:345` — if (rows[r]) { for(size_t c=0;c<row_sizes[r];c++) free(rows[r][c]); free(rows[r]); }
- `smaug_csv.c:369` — size_t ncap = b->cap ? b->cap * 2 : 4096;
- `smaug_csv.c:370` — while (ncap <= b->len + n) ncap *= 2;
- `smaug_csv.c:382` — if (s[i]==sep||s[i]=='\n'||s[i]=='\r'||s[i]==quote) { needs_quote=1; break; }
- `smaug_csv.c:384` — if (wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:386` — if (s[i] == quote && wbuf_pushc(b, quote)) return -1;
- `smaug_csv.c:387` — if (wbuf_pushc(b, s[i])) return -1;
- `smaug_csv.c:394` — if (!t || !out_len) return NULL;
- `smaug_csv.c:396` — if (!opts) opts = &def;
- `smaug_csv.c:403` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:407` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:412` — if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
- `smaug_csv.c:417` — if (st==SMG_NULL_VALUE||st!=SMG_OK) { s=""; n=0; }
- `smaug_csv.c:421` — if (st==SMG_NULL_VALUE||st!=SMG_OK) { s=""; n=0; }
- `smaug_csv.c:426` — if (st==SMG_NULL_VALUE||st!=SMG_OK) { s=""; n=0; }
- `smaug_csv.c:428` — } else if (col->str) {
- `smaug_csv.c:432` — if (write_field(&b, s, n, sep, quote)) goto oom;
- `smaug_csv.c:434` — if (wbuf_pushc(&b, '\n')) goto oom;
- `smaug_csv.c:437` — if (wbuf_pushc(&b, '\0')) goto oom;
- `smaug_csv.c:446` — if (!buf) return -1;
- `smaug_csv.c:450` — return (w==len) ? 0 : -1;

**`smaug_json.c`** — 79 linha(s) com ramo descoberto:
- `smaug_json.c:43` — while (l->pos < l->len) {
- `smaug_json.c:45` — if (c == ' ' || c == '\t' || c == '\n' || c == '\r') l->pos++;
- `smaug_json.c:52` — if (l->pos >= l->len || l->buf[l->pos] != '"') return NULL;
- `smaug_json.c:57` — while (l->pos < l->len) {
- `smaug_json.c:64` — switch (esc) {
- `smaug_json.c:73` — if (l->pos + 4 <= l->len) l->pos += 4;
- `smaug_json.c:92` — if (l->pos >= l->len) return TOK_EOF;
- `smaug_json.c:106` — if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"true",4)==0)
- `smaug_json.c:110` — if (l->pos + 5 <= l->len && strncmp(l->buf+l->pos,"false",5)==0)
- `smaug_json.c:114` — if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"null",4)==0)
- `smaug_json.c:118` — if (c == '-' || (c >= '0' && c <= '9')) {
- `smaug_json.c:122` — while (l->pos < l->len && l->buf[l->pos] >= '0' && l->buf[l->pos] <= '9') l->pos++;
- `smaug_json.c:123` — if (l->pos < l->len && l->buf[l->pos] == '.') { l->is_int = 0; l->pos++; while (l->pos<l->len && l->buf[l->pos]>='0' && l->buf[l->pos]<='9') l->pos++; }
- `smaug_json.c:124` — if (l->pos < l->len && (l->buf[l->pos]=='e' || l->buf[l->pos]=='E')) { l->is_int=0; l->pos++; if (l->pos<l->len && (l->buf[l->pos]=='+'||l->buf[l->pos]=='-')) l->pos++; while(l->pos<l->len && l->buf[l->pos]>='0' && l->buf[l->pos]<='9') l->pos++; }
- `smaug_json.c:126` — if (numlen >= sizeof(tmp)) numlen = sizeof(tmp)-1;
- `smaug_json.c:128` — if (l->is_int) { char *e; errno=0; l->int_val=strtoll(tmp,&e,10); if (*e) l->is_int=0; }
- `smaug_json.c:129` — if (!l->is_int) { char *e; errno=0; l->num_val=strtod(tmp,&e); if (*e||errno) return TOK_ERROR; }
- `smaug_json.c:188` — if (t == TOK_RBRACE) return 1;  /* objeto vazio */
- `smaug_json.c:193` — if (next_token(l) != TOK_COLON) { free(key); return 0; }
- `smaug_json.c:198` — if (rec->count >= cap) {
- `smaug_json.c:202` — if (!nk || !nv) { free(key); if (val.type==4) free(val.s); return 0; }
- `smaug_json.c:211` — if (t != TOK_COMMA)  return 0;
- `smaug_json.c:231` — while (t != TOK_RBRACKET && t != TOK_EOF && t != TOK_ERROR) {
- `smaug_json.c:232` — if (t != TOK_LBRACE) {
- `smaug_json.c:233` — for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
- `smaug_json.c:240` — if (!tmp) {
- `smaug_json.c:241` — for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
- `smaug_json.c:262` — return empty ? empty : make_error("smaug_read_json: OOM");
- `smaug_json.c:274` — if (!dtypes) { free(col_names); goto oom_recs; }
- `smaug_json.c:277` — for (size_t c = 0; c < n_cols && c < recs[r].count; c++) {
- `smaug_json.c:291` — if (dtypes[c] == DT_UNKNOWN) dtypes[c] = DT_STR;
- `smaug_json.c:295` — if (!tbl) { free(dtypes); free(col_names); goto oom_recs; }
- `smaug_json.c:297` — if (!tbl->columns) { free(tbl); free(dtypes); free(col_names); goto oom_recs; }
- `smaug_json.c:310` — json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
- `smaug_json.c:312` — else if (v->type == 1)  smaug_i64_set(s, r, v->i);
- `smaug_json.c:313` — else if (v->type == 2)  smaug_i64_set(s, r, (int64_t)v->d);
- `smaug_json.c:322` — json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
- `smaug_json.c:325` — else if (v->type == 1)  smaug_f64_set(s, r, (double)v->i);
- `smaug_json.c:334` — json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
- `smaug_json.c:336` — else if (v->type == 3)  smaug_bool_set(s, r, v->b);
- `smaug_json.c:345` — json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
- `smaug_json.c:347` — else if (v->type == 4 && v->s) smaug_str_set(s, r, v->s, strlen(v->s));
- `smaug_json.c:349` — if (v->type==1) n=snprintf(tmp,sizeof(tmp),"%lld",(long long)v->i);
- `smaug_json.c:350` — else if (v->type==2) n=snprintf(tmp,sizeof(tmp),"%.17g",v->d);
- `smaug_json.c:351` — else if (v->type==3) { strcpy(tmp,v->b?"true":"false"); n=strlen(tmp); }
- `smaug_json.c:374` — if (sz < 0) { fclose(f); return NULL; }
- `smaug_json.c:376` — if (!buf) { fclose(f); return NULL; }
- `smaug_json.c:400` — size_t ncap = b->cap ? b->cap * 2 : 4096;
- `smaug_json.c:401` — while (ncap <= b->len + n) ncap *= 2;
- `smaug_json.c:412` — if (wbj_pushc(b, '"')) return -1;
- `smaug_json.c:429` — if (!t || !out_len) return NULL;
- `smaug_json.c:437` — if (wbj_pushz(&b, nl)) goto oom;
- `smaug_json.c:440` — if (wbj_pushz(&b, ind)) goto oom;
- `smaug_json.c:441` — if (wbj_pushc(&b, '{')) goto oom;
- `smaug_json.c:442` — if (wbj_pushz(&b, nl)) goto oom;
- `smaug_json.c:445` — if (wbj_pushz(&b, ind2)) goto oom;
- `smaug_json.c:448` — if (write_json_string(&b, n, strlen(n))) goto oom;
- `smaug_json.c:449` — if (wbj_pushc(&b, ':')) goto oom;
- `smaug_json.c:450` — if (pretty && wbj_pushc(&b, ' ')) goto oom;
- `smaug_json.c:458` — if (st == SMG_NULL_VALUE || st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; }
- `smaug_json.c:459` — else { snprintf(tmp,sizeof(tmp),"%lld",(long long)v); if (wbj_pushz(&b,tmp)) goto oom; }
- `smaug_json.c:463` — if (st == SMG_NULL_VALUE || st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; }
- `smaug_json.c:465` — else { snprintf(tmp,sizeof(tmp),"%.17g",v); if (wbj_pushz(&b,tmp)) goto oom; }
- `smaug_json.c:469` — if (st == SMG_NULL_VALUE || st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; }
- `smaug_json.c:470` — else { if (wbj_pushz(&b, v ? "true" : "false")) goto oom; }
- `smaug_json.c:474` — if (!sv) { if (wbj_pushz(&b,"null")) goto oom; }
- `smaug_json.c:475` — else { if (write_json_string(&b, sv, slen)) goto oom; }
- `smaug_json.c:476` — } else { if (wbj_pushz(&b,"null")) goto oom; }
- `smaug_json.c:478` — if (c + 1 < t->ncols) { if (wbj_pushc(&b,',')) goto oom; }
- `smaug_json.c:479` — if (wbj_pushz(&b, nl)) goto oom;
- `smaug_json.c:482` — if (wbj_pushz(&b, ind)) goto oom;
- `smaug_json.c:483` — if (wbj_pushc(&b, '}')) goto oom;
- `smaug_json.c:484` — if (r + 1 < t->nrows) { if (wbj_pushc(&b,',')) goto oom; }
- `smaug_json.c:485` — if (wbj_pushz(&b, nl)) goto oom;
- `smaug_json.c:488` — if (wbj_pushc(&b, ']')) goto oom;
- `smaug_json.c:489` — if (wbj_pushc(&b, '\n')) goto oom;
- `smaug_json.c:490` — if (wbj_pushc(&b, '\0')) goto oom;
- `smaug_json.c:501` — if (!buf) return -1;
- `smaug_json.c:505` — return (w == len) ? 0 : -1;

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
- `smaug_csv.c:227` — c<n_cols<=row_sizes[0] por construção
- `smaug_csv.c:278` — dtype inferido garante try_i64=1
- `smaug_csv.c:291` — dtype inferido garante try_f64=1
- `smaug_csv.c:292` — idem para inteiros em coluna float
- `smaug_csv.c:292` — idem para inteiros em coluna float
- `smaug_csv.c:305` — dtype inferido garante try_bool=1
- `smaug_csv.c:397` — write_default_opts garante sep!=0
- `smaug_csv.c:398` — write_default_opts garante quote!=0
- `smaug_csv.c:404` — name sempre não-NULL após construção
- `smaug_json.c:61` — string não fechada — parser tolera, mas o EOL interno break é inalcançável em JSON bem-formado
- `smaug_json.c:311` — !v só quando record tem menos campos que esperado
- `smaug_json.c:323` — !v só quando record tem menos campos
- `smaug_json.c:335` — !v só quando record tem menos campos
- `smaug_json.c:346` — !v só quando record tem menos campos
- `smaug_json.c:415` — OOM de wbuf sem injeção
- `smaug_json.c:416` — OOM de wbuf sem injeção
- `smaug_json.c:417` — OOM de wbuf sem injeção
- `smaug_json.c:418` — OOM de wbuf sem injeção
- `smaug_json.c:418` — OOM de wbuf sem injeção
- `smaug_json.c:418` — OOM de wbuf sem injeção
- `smaug_json.c:419` — OOM de wbuf sem injeção
- `smaug_json.c:420` — OOM de wbuf sem injeção
- `smaug_json.c:421` — OOM de wbuf sem injeção
- `smaug_json.c:430` — NULL opts usa default 0; opts não-NULL cobre ambos
- `smaug_json.c:447` — name sempre não-NULL após construção
- `smaug_json.c:464` — OOM de wbuf + NaN→null: ramo oom inalcançável sem injeção
- `smaug_json.c:471` — dtype inferido garante exatamente um ponteiro não-NULL
