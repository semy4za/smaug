#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
/* src/smaug_json.c
 *
 * Parser e writer JSON do Smaug — Anel 3.
 * Formato suportado: array de records [ {...}, {...}, ... ]
 * Zero dependências externas.
 */

#include "../include/smaug_io.h"
#include "smaug_io_internal.h"
#include "../include/smaug_core.h"
#include "../include/smaug_string.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <math.h>

/* ===================================================================
   Tokenizador JSON minimalista
   =================================================================== */

typedef enum {
    TOK_LBRACE, TOK_RBRACE, TOK_LBRACKET, TOK_RBRACKET,
    TOK_COLON, TOK_COMMA,
    TOK_STRING, TOK_NUMBER, TOK_TRUE, TOK_FALSE, TOK_NULL,
    TOK_EOF, TOK_ERROR
} json_tok_t;

typedef struct {
    const char *buf;
    size_t      len;
    size_t      pos;
    char       *str_val;   /* para TOK_STRING */
    double      num_val;   /* para TOK_NUMBER */
    int         is_int;    /* 1 se numero sem ponto/exp */
    int64_t     int_val;
} json_lex_t;

static void skip_ws(json_lex_t *l) {
    while (l->pos < l->len) {
        char c = l->buf[l->pos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') l->pos++;
        else break;
    }
}

/* Lê 4 dígitos hex de l->buf[l->pos..] e devolve o codepoint (0–0xFFFF).
   Avança l->pos em 4. Retorna -1 se os 4 caracteres não forem hex válidos. */
static int read_hex4(json_lex_t *l) {
    if (l->pos + 4 > l->len) return -1;
    unsigned int cp = 0;
    for (int i = 0; i < 4; i++) {
        unsigned char h = (unsigned char)l->buf[l->pos + i];
        unsigned int digit;
        if      (h >= '0' && h <= '9') digit = h - '0';
        else if (h >= 'a' && h <= 'f') digit = h - 'a' + 10;
        else if (h >= 'A' && h <= 'F') digit = h - 'A' + 10;
        else return -1;
        cp = (cp << 4) | digit;
    }
    l->pos += 4;
    return (int)cp;
}

/* Codifica codepoint Unicode (U+0000–U+10FFFF, exceto surrogates) em UTF-8.
   Escreve 1–4 bytes em dst. Retorna o número de bytes escritos, ou 0 em erro. */
static int encode_utf8(unsigned int cp, char *dst) {
    if (cp <= 0x7F) {
        dst[0] = (char)cp;
        return 1;
    } else if (cp <= 0x7FF) {
        dst[0] = (char)(0xC0 | (cp >> 6));
        dst[1] = (char)(0x80 | (cp & 0x3F));
        return 2;
    } else if (cp <= 0xFFFF) {
        dst[0] = (char)(0xE0 | (cp >> 12));
        dst[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        dst[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    } else if (cp <= 0x10FFFF) { /* COV-EXCL-BR: ramo falso inalcançável — surrogates produzem max 0x10FFFF, BMP já foi tratado em cp<=0xFFFF acima */
        dst[0] = (char)(0xF0 | (cp >> 18));
        dst[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
        dst[2] = (char)(0x80 | ((cp >> 6)  & 0x3F));
        dst[3] = (char)(0x80 | (cp & 0x3F));
        return 4;
    }
    return 0; /* codepoint inválido */
}

/* Lê string JSON (com escape). Retorna malloc'd string ou NULL em erro.
 *
 * Escapes suportados: \" \\ \/ \n \r \t \b \f
 * Escapes Unicode: \uXXXX decodificado para UTF-8.
 *   - BMP (U+0000–U+FFFF, exceto surrogates): decodificado diretamente.
 *   - Pares surrogate (\uD800–\uDBFF seguido de \uDC00–\uDFFF): decodificados
 *     para o codepoint suplementar correspondente (U+10000–U+10FFFF).
 *   - Surrogate isolado ou par inválido: erro (retorna NULL → TOK_ERROR).
 * Hex inválido em \uXXXX: erro (retorna NULL → TOK_ERROR).
 */
static char *read_json_string(json_lex_t *l) {
    if (l->pos >= l->len || l->buf[l->pos] != '"') return NULL;
    l->pos++;
    size_t cap = 64; char *out = malloc(cap); size_t n = 0;
    if (!out) return NULL;

    while (l->pos < l->len) {
        char c = l->buf[l->pos++];
        if (c == '"') { out[n] = '\0'; return out; }
        if (c == '\\') {
            if (l->pos >= l->len) break; /* COV-EXCL-BR: string não fechada — break inalcançável em JSON bem-formado */
            char esc = l->buf[l->pos++];
            if (esc == 'u') {
                /* Decodifica \uXXXX para UTF-8. */
                int cp = read_hex4(l);
                if (cp < 0) { free(out); return NULL; }   /* hex inválido */

                unsigned int ucp = (unsigned int)cp;

                if (ucp >= 0xD800 && ucp <= 0xDBFF) {
                    /* High surrogate: esperado \uDC00–\uDFFF a seguir. */
                    if (l->pos + 6 > l->len ||
                        l->buf[l->pos] != '\\' || l->buf[l->pos+1] != 'u') {
                        free(out); return NULL;   /* surrogate isolado */
                    }
                    l->pos += 2;   /* consume \u */
                    int cp2 = read_hex4(l);
                    if (cp2 < 0) { free(out); return NULL; }
                    unsigned int ucp2 = (unsigned int)cp2;
                    if (ucp2 < 0xDC00 || ucp2 > 0xDFFF) {
                        free(out); return NULL;   /* par inválido */
                    }
                    ucp = 0x10000 + ((ucp - 0xD800) << 10) + (ucp2 - 0xDC00);
                } else if (ucp >= 0xDC00 && ucp <= 0xDFFF) {
                    free(out); return NULL;   /* low surrogate isolado */
                }

                char utf8[4];
                int bytes = encode_utf8(ucp, utf8);
                if (bytes == 0) { free(out); return NULL; } /* COV-EXCL-BR: encode_utf8 só retorna 0 para cp > 0x10FFFF, mas o parser garante cp ≤ 0x10FFFF (BMP direto ≤ 0xFFFF; par surrogate → max 0x10FFFF pela fórmula) */

                /* garantir espaço para até 4 bytes + terminador */
                if (n + bytes >= cap) {
                    while (n + bytes >= cap) cap *= 2;
                    char *tmp = realloc(out, cap);
                    if (!tmp) { free(out); return NULL; } /* COV-EXCL-BR: OOM de realloc em string JSON */
                    out = tmp;
                }
                for (int i = 0; i < bytes; i++) out[n++] = utf8[i];
                continue;
            }
            /* escapes de 1 caractere */
            char mapped;
            switch (esc) {
                case '"': case '\\': case '/': mapped = esc; break;
                case 'n': mapped = '\n'; break;
                case 'r': mapped = '\r'; break;
                case 't': mapped = '\t'; break;
                case 'b': mapped = '\b'; break;
                case 'f': mapped = '\f'; break;
                default:  mapped = esc; break;
            }
            c = mapped;
        }
        if (n + 1 >= cap) {
            cap *= 2; char *tmp = realloc(out, cap);
            if (!tmp) { free(out); return NULL; } /* COV-EXCL-BR: OOM de realloc em string JSON */
            out = tmp;
        }
        out[n++] = c;
    }
    free(out); return NULL;  /* string não fechada */
}

static json_tok_t next_token(json_lex_t *l) {
    free(l->str_val); l->str_val = NULL;
    skip_ws(l);
    if (l->pos >= l->len) return TOK_EOF;

    char c = l->buf[l->pos];
    switch (c) {
        case '{': l->pos++; return TOK_LBRACE;
        case '}': l->pos++; return TOK_RBRACE;
        case '[': l->pos++; return TOK_LBRACKET;
        case ']': l->pos++; return TOK_RBRACKET;
        case ':': l->pos++; return TOK_COLON;
        case ',': l->pos++; return TOK_COMMA;
        case '"':
            l->str_val = read_json_string(l);
            return l->str_val ? TOK_STRING : TOK_ERROR;
        case 't':
            if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"true",4)==0)
                { l->pos+=4; return TOK_TRUE; }
            return TOK_ERROR;
        case 'f':
            if (l->pos + 5 <= l->len && strncmp(l->buf+l->pos,"false",5)==0)
                { l->pos+=5; return TOK_FALSE; }
            return TOK_ERROR;
        case 'n':
            if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"null",4)==0)
                { l->pos+=4; return TOK_NULL; }
            return TOK_ERROR;
        default:
            if (c == '-' || (c >= '0' && c <= '9')) {
                size_t start = l->pos;
                l->is_int = 1;
                if (c == '-') l->pos++;
                while (l->pos < l->len && l->buf[l->pos] >= '0' && l->buf[l->pos] <= '9') l->pos++;
                if (l->pos < l->len && l->buf[l->pos] == '.') { l->is_int = 0; l->pos++; while (l->pos<l->len && l->buf[l->pos]>='0' && l->buf[l->pos]<='9') l->pos++; }
                if (l->pos < l->len && (l->buf[l->pos]=='e' || l->buf[l->pos]=='E')) { l->is_int=0; l->pos++; if (l->pos<l->len && (l->buf[l->pos]=='+'||l->buf[l->pos]=='-')) l->pos++; while(l->pos<l->len && l->buf[l->pos]>='0' && l->buf[l->pos]<='9') l->pos++; }
                char tmp[64]; size_t numlen = l->pos - start;
                if (numlen >= sizeof(tmp)) numlen = sizeof(tmp)-1;
                memcpy(tmp, l->buf+start, numlen); tmp[numlen]='\0';
                if (l->is_int) { char *e; errno=0; l->int_val=strtoll(tmp,&e,10); if (*e) l->is_int=0; }
                if (!l->is_int) { char *e; errno=0; l->num_val=strtod(tmp,&e); if (*e||errno) return TOK_ERROR; }
                return TOK_NUMBER;
            }
            return TOK_ERROR;
    }
}

/* ===================================================================
   Parser de array de records
   =================================================================== */

/* Valor de uma célula na leitura */
typedef struct {
    int     type;   /* 0=null, 1=int64, 2=float64, 3=bool, 4=string */
    int64_t i;
    double  d;
    uint8_t b;
    char   *s;
} json_val_t;

/* Um record (linha) */
typedef struct {
    char       **keys;
    json_val_t  *vals;
    size_t       count;
} json_record_t;

static void free_record(json_record_t *r) {
    for (size_t i = 0; i < r->count; i++) {
        free(r->keys[i]);
        if (r->vals[i].type == 4) free(r->vals[i].s);
    }
    free(r->keys); free(r->vals);
}

static int parse_value(json_lex_t *l, json_val_t *v, json_tok_t tok) {
    switch (tok) {
        case TOK_NULL:   v->type = 0; return 1;
        case TOK_TRUE:   v->type = 3; v->b = 1; return 1;
        case TOK_FALSE:  v->type = 3; v->b = 0; return 1;
        case TOK_NUMBER:
            if (l->is_int) { v->type = 1; v->i = l->int_val; }
            else            { v->type = 2; v->d = l->num_val; }
            return 1;
        case TOK_STRING:
            v->type = 4; v->s = l->str_val; l->str_val = NULL; return 1;
        default: return 0;
    }
}

static int parse_record(json_lex_t *l, json_record_t *rec) {
    /* espera '{' já consumido */
    size_t cap = 8;
    rec->keys  = malloc(cap * sizeof(char*));
    rec->vals  = malloc(cap * sizeof(json_val_t));
    rec->count = 0;
    if (!rec->keys || !rec->vals) return 0;

    json_tok_t t = next_token(l);
    if (t == TOK_RBRACE) return 1;  /* objeto vazio */

    while (1) {
        if (t != TOK_STRING) return 0;
        char *key = l->str_val; l->str_val = NULL;
        if (next_token(l) != TOK_COLON) { free(key); return 0; }
        json_tok_t vt = next_token(l);
        json_val_t val = {0};
        if (!parse_value(l, &val, vt)) { free(key); return 0; }

        if (rec->count >= cap) {
            cap *= 2;
            char **nk = realloc(rec->keys, cap*sizeof(char*));
            json_val_t *nv = realloc(rec->vals, cap*sizeof(json_val_t));
            if (!nk || !nv) { free(key); if (val.type==4) free(val.s); return 0; }
            rec->keys = nk; rec->vals = nv;
        }
        rec->keys[rec->count]  = key;
        rec->vals[rec->count]  = val;
        rec->count++;

        t = next_token(l);
        if (t == TOK_RBRACE) return 1;
        if (t != TOK_COMMA)  return 0;
        t = next_token(l);
    }
}

smaug_table_t *smaug_read_json_mem(const char *buf, size_t len) {
    json_lex_t l = {buf, len, 0, NULL, 0, 0, 0};
    json_tok_t t;
    /* alocações visíveis em oom_recs (NULL = não-alocado ou já liberado) */
    char **col_names = NULL;
    int   *dtypes    = NULL;
    size_t n_cols_io = 0;

    t = next_token(&l);
    if (t != TOK_LBRACKET)
        return make_error("smaug_read_json: esperado array '[' no topo");

    /* ler todos os records */
    size_t rec_cap = 64;
    json_record_t *recs = malloc(rec_cap * sizeof(json_record_t));
    if (!recs) return make_error("smaug_read_json: OOM");
    size_t n_recs = 0;

    t = next_token(&l);
    while (t != TOK_RBRACKET && t != TOK_EOF && t != TOK_ERROR) {
        if (t != TOK_LBRACE) {
            for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
            free(recs); free(l.str_val);
            return make_error("smaug_read_json: esperado '{' em cada elemento");
        }
        if (n_recs >= rec_cap) {
            rec_cap *= 2;
            json_record_t *tmp = realloc(recs, rec_cap * sizeof(json_record_t));
            if (!tmp) {
                for (size_t i = 0; i < n_recs; i++) free_record(&recs[i]);
                free(recs); free(l.str_val);
                return make_error("smaug_read_json: OOM");
            }
            recs = tmp;
        }
        recs[n_recs] = (json_record_t){0};
        if (!parse_record(&l, &recs[n_recs])) {
            for (size_t i = 0; i <= n_recs; i++) free_record(&recs[i]);
            free(recs); free(l.str_val);
            return make_error("smaug_read_json: erro ao parsear objeto");
        }
        n_recs++;
        t = next_token(&l);
        if (t == TOK_COMMA) t = next_token(&l);
    }
    free(l.str_val);

    if (n_recs == 0) {
        free(recs);
        smaug_table_t *empty = calloc(1, sizeof(smaug_table_t));
        return empty ? empty : make_error("smaug_read_json: OOM");
    }

    /* descobrir colunas (ordem do primeiro record) */
    size_t n_cols = recs[0].count;
    n_cols_io     = n_cols;
    col_names     = malloc(n_cols * sizeof(char*));
    if (!col_names) goto oom_recs;
    /* zera antes de strdup para permitir cleanup parcial seguro */
    for (size_t c = 0; c < n_cols; c++) col_names[c] = NULL;
    for (size_t c = 0; c < n_cols; c++) {
        col_names[c] = strdup(recs[0].keys[c]);
        if (!col_names[c]) {
            for (size_t k = 0; k < c; k++) free(col_names[k]);
            free(col_names); col_names = NULL;
            goto oom_recs;
        }
    }

    /* inferir dtypes */
    dtypes = calloc(n_cols, sizeof(int));
    if (!dtypes) {
        for (size_t c = 0; c < n_cols; c++) free(col_names[c]);
        free(col_names); col_names = NULL;
        goto oom_recs;
    }

    for (size_t r = 0; r < n_recs; r++) {
        for (size_t c = 0; c < n_cols && c < recs[r].count; c++) {
            int jt = recs[r].vals[c].type;
            int cand;
            switch (jt) {
                case 0: continue;          /* null: não vota */
                case 1: cand = DT_I64;  break;
                case 2: cand = DT_F64;  break;
                case 3: cand = DT_BOOL; break;
                default: cand = DT_STR; break;
            }
            dtypes[c] = dtype_upgrade(dtypes[c], cand);
        }
    }
    for (size_t c = 0; c < n_cols; c++)
        if (dtypes[c] == DT_UNKNOWN) dtypes[c] = DT_STR;

    /* construir tabela */
    smaug_table_t *tbl = calloc(1, sizeof(smaug_table_t));
    if (!tbl) {
        for (size_t c = 0; c < n_cols; c++) free(col_names[c]);
        free(dtypes); free(col_names); dtypes = NULL; col_names = NULL;
        goto oom_recs;
    }
    tbl->columns = calloc(n_cols, sizeof(smaug_column_t));
    if (!tbl->columns) {
        free(tbl);
        for (size_t c = 0; c < n_cols; c++) free(col_names[c]);
        free(dtypes); free(col_names); dtypes = NULL; col_names = NULL;
        goto oom_recs;
    }
    tbl->ncols = n_cols;
    tbl->nrows = n_recs;

    for (size_t c = 0; c < n_cols; c++) {
        tbl->columns[c].name  = col_names[c];
        col_names[c]          = NULL;   /* ownership transferida ao tbl */
        tbl->columns[c].dtype = dtype_name(dtypes[c]);

        switch (dtypes[c]) {
        case DT_I64: {
            smaug_series_i64_t *s = smaug_i64_create(n_recs);
            if (!s) { smaug_table_free(tbl); tbl=NULL; goto oom_recs; }
            for (size_t r = 0; r < n_recs; r++) {
                json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
                if (!v || v->type == 0) smaug_i64_set_null(s, r); /* registro heterogêneo (campo ausente) — caso normal, ver test_json_short_record */
                else if (v->type == 1)  smaug_i64_set(s, r, v->i); /* COV-EXCL-BR: ramo falso inalcançável — pureza de inferência garante que todo não-null numa coluna i64 tem type==1; type==2/3/4 teriam forçado DT_F64/DT_STR via dtype_upgrade */
                else if (v->type == 2)  smaug_i64_set(s, r, (int64_t)v->d); /* COV-EXCL-BR: dtype=int64 implica que toda linha não-null tinha jt==1 durante a inferência (dtype_upgrade força float64 se qualquer linha fosse jt==2) — mesmo argumento de pureza do csv.c */
                else                    smaug_i64_set_null(s, r); /* COV-EXCL-BR: idem — jt só pode ser 0(null)/1(int) numa coluna int64 */
            }
            tbl->columns[c].i64 = s; break;
        }
        case DT_F64: {
            smaug_series_f64_t *s = smaug_f64_create(n_recs);
            if (!s) { smaug_table_free(tbl); tbl=NULL; goto oom_recs; }
            for (size_t r = 0; r < n_recs; r++) {
                json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
                if (!v || v->type == 0) smaug_f64_set_null(s, r); /* registro heterogêneo — ver test_json_short_record */
                else if (v->type == 2)  smaug_f64_set(s, r, v->d);
                else if (v->type == 1)  smaug_f64_set(s, r, (double)v->i); /* COV-EXCL-BR: ramo falso inalcançável — se chegou aqui, type já não é 0 nem 2; pureza garante que só resta 1 */
                else                    smaug_f64_set_null(s, r); /* COV-EXCL-BR: dtype=float64 implica jt∈{1,2} pra toda linha não-null (mesmo argumento de pureza) */
            }
            tbl->columns[c].f64 = s; break;
        }
        case DT_BOOL: {
            smaug_series_bool_t *s = smaug_bool_create(n_recs);
            if (!s) { smaug_table_free(tbl); tbl=NULL; goto oom_recs; }
            for (size_t r = 0; r < n_recs; r++) {
                json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
                if (!v || v->type == 0) smaug_bool_set_null(s, r); /* registro heterogêneo — ver test_json_short_record */
                else if (v->type == 3)  smaug_bool_set(s, r, v->b); /* COV-EXCL-BR: ramo falso inalcançável — pureza garante type==3 sempre que não-null numa coluna bool */
                else                    smaug_bool_set_null(s, r); /* COV-EXCL-BR: idem — else nunca alcançado pelo mesmo motivo */
            }
            tbl->columns[c].boolcol = s; break;
        }
        default: {
            smaug_series_str_t *s = smaug_str_create(n_recs);
            if (!s) { smaug_table_free(tbl); tbl=NULL; goto oom_recs; }
            for (size_t r = 0; r < n_recs; r++) {
                json_val_t *v = (c < recs[r].count) ? &recs[r].vals[c] : NULL;
                if (!v || v->type == 0) { smaug_str_set_null(s, r); } /* registro heterogêneo — ver test_json_short_record */
                else if (v->type == 4) smaug_str_set(s, r, v->s, strlen(v->s)); /* v->s nunca é NULL aqui — TOK_STRING só é emitido com l->str_val não-nulo (linha 192) */
                else { char tmp[64]; size_t n;
                       if (v->type==1) n=snprintf(tmp,sizeof(tmp),"%lld",(long long)v->i);
                       else if (v->type==2) n=snprintf(tmp,sizeof(tmp),"%.17g",v->d);
                       else if (v->type==3) { strcpy(tmp,v->b?"true":"false"); n=strlen(tmp); } /* COV-EXCL-BR: ramo falso inalcançável — numa coluna DT_STR (catch-all), todo não-null com !v->s tem type∈{1,2,3}; o else (tmp[0]='\0') só seria alcançado se type fosse 0 ou >4, impossível de JSON válido */
                       else { tmp[0]='\0'; n=0; }
                       smaug_str_set(s, r, tmp, n); }
            }
            tbl->columns[c].str = s; break;
        }
        }
    }

    for (size_t r = 0; r < n_recs; r++) free_record(&recs[r]);
    free(recs); free(dtypes); free(col_names);
    return tbl;

oom_recs:
    if (col_names) {
        for (size_t c = 0; c < n_cols_io; c++) free(col_names[c]);
        free(col_names);
    }
    free(dtypes);
    for (size_t r = 0; r < n_recs; r++) free_record(&recs[r]);
    free(recs);
    return make_error("smaug_read_json: OOM");
}

static char *read_file_json(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long sz = ftell(f); rewind(f);
    if (sz < 0) { fclose(f); return NULL; }
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t got = fread(buf, 1, (size_t)sz, f); fclose(f);
    buf[got] = '\0'; *out_len = got;
    return buf;
}

smaug_table_t *smaug_read_json(const char *path) {
    size_t len; char *buf = read_file_json(path, &len);
    if (!buf) {
        char msg[256]; snprintf(msg,sizeof(msg),"smaug_read_json: não foi possível abrir '%s'",path);
        return make_error(msg);
    }
    smaug_table_t *t = smaug_read_json_mem(buf, len);
    free(buf); return t;
}

/* ===================================================================
   Writer JSON
   =================================================================== */

/* reutiliza wbuf_t do csv */
typedef struct { char *data; size_t len; size_t cap; } wbuf_j_t;
static int wbj_push(wbuf_j_t *b, const char *s, size_t n) {
    if (b->len + n >= b->cap) {
        size_t ncap = b->cap ? b->cap * 2 : 4096;
        while (ncap <= b->len + n) ncap *= 2;
        char *tmp = realloc(b->data, ncap);
        if (!tmp) return -1;
        b->data = tmp; b->cap = ncap;
    }
    memcpy(b->data + b->len, s, n); b->len += n; return 0;
}
static int wbj_pushc(wbuf_j_t *b, char c) { return wbj_push(b, &c, 1); }
static int wbj_pushz(wbuf_j_t *b, const char *s) { return wbj_push(b, s, strlen(s)); }

static int write_json_string(wbuf_j_t *b, const char *s, size_t n) {
    if (wbj_pushc(b, '"')) return -1;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if      (c == '"')  { if (wbj_pushz(b, "\\\"")) return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else if (c == '\\') { if (wbj_pushz(b, "\\\\")) return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else if (c == '\n') { if (wbj_pushz(b, "\\n"))  return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else if (c == '\r') { if (wbj_pushz(b, "\\r"))  return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else if (c == '\t') { if (wbj_pushz(b, "\\t"))  return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else if (c < 0x20)  { char u[8]; snprintf(u,sizeof(u),"\\u%04x",c); if (wbj_pushz(b,u)) return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else                { if (wbj_pushc(b,(char)c)) return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
    }
    return wbj_pushc(b, '"');
}

char *smaug_write_json_mem(const smaug_table_t *t,
                            const smaug_json_write_opts_t *opts,
                            size_t *out_len) {
    if (!t || !out_len) return NULL;
    int pretty = opts ? opts->pretty : 0; /* COV-EXCL-BR: NULL opts usa default 0; opts não-NULL cobre ambos */
    const char *nl   = pretty ? "\n" : "";
    const char *ind  = pretty ? "  " : "";
    const char *ind2 = pretty ? "    " : "";

    wbuf_j_t b = {0};
    if (wbj_pushc(&b, '[')) goto oom;
    if (wbj_pushz(&b, nl)) goto oom;

    for (size_t r = 0; r < t->nrows; r++) {
        if (wbj_pushz(&b, ind)) goto oom;
        if (wbj_pushc(&b, '{')) goto oom;
        if (wbj_pushz(&b, nl)) goto oom;

        for (size_t c = 0; c < t->ncols; c++) {
            if (wbj_pushz(&b, ind2)) goto oom;
            /* chave */
            const char *n = t->columns[c].name ? t->columns[c].name : ""; /* COV-EXCL-BR: name sempre não-NULL após construção */
            if (write_json_string(&b, n, strlen(n))) goto oom;
            if (wbj_pushc(&b, ':')) goto oom;
            if (pretty && wbj_pushc(&b, ' ')) goto oom;

            /* valor */
            smaug_column_t *col = &t->columns[c];
            char tmp[64];
            if (col->i64) {
                smaug_status_t st;
                int64_t v = smaug_i64_get(col->i64, r, &st);
                if (st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; } /* st==SMG_NULL_VALUE é subcaso de st!=SMG_OK — simplificado (ver csv.c) */
                else { snprintf(tmp,sizeof(tmp),"%lld",(long long)v); if (wbj_pushz(&b,tmp)) goto oom; }
            } else if (col->f64) {
                smaug_status_t st;
                double v = smaug_f64_get(col->f64, r, &st);
                if (st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; } /* idem i64 */
                else if (v != v) { if (wbj_pushz(&b,"null")) goto oom; }  /* COV-EXCL-BR: OOM de wbuf + NaN→null: ramo oom inalcançável sem injeção */
                else { snprintf(tmp,sizeof(tmp),"%.17g",v); if (wbj_pushz(&b,tmp)) goto oom; }
            } else if (col->boolcol) {
                smaug_status_t st;
                uint8_t v = smaug_bool_get(col->boolcol, r, &st);
                if (st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; } /* idem i64 */
                else { if (wbj_pushz(&b, v ? "true" : "false")) goto oom; }
            } else if (col->str) { /* COV-EXCL-BR: dtype inferido garante exatamente um ponteiro não-NULL */
                size_t slen;
                const char *sv = smaug_str_get(col->str, r, &slen);
                if (!sv) { if (wbj_pushz(&b,"null")) goto oom; }
                else { if (write_json_string(&b, sv, slen)) goto oom; }
            } else { if (wbj_pushz(&b,"null")) goto oom; } /* COV-EXCL-BR: só alcançado se tbl->columns[c] não tiver nenhum ponteiro de dado (col completamente inválida) — inalcançável com tabela bem-construída */

            if (c + 1 < t->ncols) { if (wbj_pushc(&b,',')) goto oom; }
            if (wbj_pushz(&b, nl)) goto oom;
        }

        if (wbj_pushz(&b, ind)) goto oom;
        if (wbj_pushc(&b, '}')) goto oom;
        if (r + 1 < t->nrows) { if (wbj_pushc(&b,',')) goto oom; }
        if (wbj_pushz(&b, nl)) goto oom;
    }

    if (wbj_pushc(&b, ']')) goto oom;
    if (wbj_pushc(&b, '\n')) goto oom;
    if (wbj_pushc(&b, '\0')) goto oom;
    *out_len = b.len - 1;
    return b.data;

oom:
    free(b.data); return NULL;
}

int smaug_write_json(const char *path, const smaug_table_t *t,
                     const smaug_json_write_opts_t *opts) {
    size_t len; char *buf = smaug_write_json_mem(t, opts, &len);
    if (!buf) return -1;
    FILE *f = fopen(path, "wb");
    if (!f) { free(buf); return -1; }
    size_t w = fwrite(buf, 1, len, f); fclose(f); free(buf);
    return (w == len) ? 0 : -1; /* COV-EXCL-BR: w != len só com fwrite parcial (disco cheio/falha de I/O) — inalcançável sem mock de fwrite */
}
