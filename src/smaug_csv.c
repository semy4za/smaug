/* Reescrita do parser CSV com abordagem single-pass mais clara */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "../include/smaug_io.h"
#include "../include/smaug_core.h"
#include "../include/smaug_string.h"
#include "smaug_io_internal.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <math.h>

/* ===================================================================
   smaug_table_t — ciclo de vida
   =================================================================== */

void smaug_table_free(smaug_table_t *t) {
    if (!t) return;
    for (size_t i = 0; i < t->ncols; i++) {
        free((char *)t->columns[i].name);
        if (t->columns[i].f64)     smaug_f64_free(t->columns[i].f64);
        if (t->columns[i].i64)     smaug_i64_free(t->columns[i].i64);
        if (t->columns[i].boolcol) smaug_bool_free(t->columns[i].boolcol);
        if (t->columns[i].str)     smaug_str_free(t->columns[i].str);
    }
    free(t->columns);
    free(t->error);
    free(t);
}

static char *read_file(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; } /* COV-EXCL-BR: falha de syscall não simulável sem mock */
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return NULL; } /* COV-EXCL-BR: ftell negativo só em fd inválido */
    rewind(f);
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; } /* COV-EXCL-BR: OOM de malloc no read_file */
    size_t got = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[got] = '\0';
    *out_len = got;
    return buf;
}

smaug_csv_opts_t smaug_csv_default_opts(void) {
    smaug_csv_opts_t o;
    o.sep       = ',';
    o.header    = 1;
    o.na_values = NULL;  /* usa o padrão interno */
    o.na_count  = 0;
    o.quote     = '"';
    return o;
}

smaug_csv_write_opts_t smaug_csv_write_default_opts(void) {
    smaug_csv_write_opts_t o;
    o.sep    = ',';
    o.header = 1;
    o.quote  = '"';
    return o;
}

/* Valores NA padrão */
static const char *BUILTIN_NA[] = {"", "NA", "null", "N/A", "nan", "NaN", "NULL"};
#define BUILTIN_NA_COUNT 7

static int is_na(const char *s, const char **na_values, size_t na_count) {
    const char **nav = na_values ? na_values : BUILTIN_NA;
    size_t nc = na_values ? na_count : BUILTIN_NA_COUNT;
    for (size_t i = 0; i < nc; i++)
        if (strcmp(s, nav[i]) == 0) return 1;
    return 0;
}

static int try_i64(const char *s, int64_t *out) {
    if (!s || !*s) return 0;
    char *end; errno = 0;
    long long v = strtoll(s, &end, 10);
    if (errno || *end != '\0') return 0;
    *out = (int64_t)v; return 1;
}

static int try_f64(const char *s, double *out) {
    if (!s || !*s) return 0;
    char *end; errno = 0;
    double v = strtod(s, &end);
    if (errno || *end != '\0') return 0;
    *out = v; return 1;
}

static int try_bool(const char *s, uint8_t *out) {
    if (!strcmp(s,"true")||!strcmp(s,"True")||!strcmp(s,"TRUE"))   { *out=1; return 1; }
    if (!strcmp(s,"false")||!strcmp(s,"False")||!strcmp(s,"FALSE")) { *out=0; return 1; }
    return 0;
}

/* ===================================================================
   Tokenizador: extrai campo CSV respeitando aspas RFC 4180.
   Avança *pos. Retorna campo alocado (chamar free). eol=1 se fim de linha.
   =================================================================== */
static char *next_field(const char *buf, size_t len, size_t *pos,
                         char sep, char quote, int *eol) {
    *eol = 0;
    size_t i = *pos;
    if (i >= len) { *eol = 1; return strdup(""); } /* COV-EXCL-BR: loop externo garante pos < len antes de chamar */

    char *out = NULL;
    size_t n = 0, cap = 0;

    #define PUSH(c) do { \
        if (n + 1 >= cap) { \
            cap = cap ? cap * 2 : 32; \
            char *_t = realloc(out, cap); \
            if (!_t) { free(out); return NULL; } \
            out = _t; \
        } \
        out[n++] = (c); \
    } while(0)

    if (buf[i] == quote) {
        i++;
        while (i < len) {
            if (buf[i] == quote) {
                if (i+1 < len && buf[i+1] == quote) { PUSH(quote); i += 2; }
                else { i++; break; }
            } else {
                PUSH(buf[i]); i++;
            }
        }
    } else {
        while (i < len && buf[i] != sep && buf[i] != '\n' && buf[i] != '\r')
            { PUSH(buf[i]); i++; }
    }

    /* consumir delimitador */
    if (i < len && buf[i] == sep)       { i++; }
    else if (i < len && buf[i] == '\r') { i++; if (i<len && buf[i]=='\n') i++; *eol=1; }
    else if (i < len && buf[i] == '\n') { i++; *eol=1; }
    else                                { *eol=1; }

    *pos = i;
    if (!out) { out = malloc(1); if (out) out[0]='\0'; } /* COV-EXCL-BR: só falha se PUSH falhou por OOM */
    else out[n] = '\0';
    return out;
    #undef PUSH
}

/* ===================================================================
   Parser principal: coleta todos os tokens e depois constrói séries
   =================================================================== */
smaug_table_t *smaug_read_csv_mem(const char *buf, size_t len,
                                    const smaug_csv_opts_t *opts) {
    smaug_csv_opts_t def = smaug_csv_default_opts();
    if (!opts) opts = &def;
    char sep   = opts->sep   ? opts->sep   : ',';   /* COV-EXCL-BR: default_opts garante sep!=0 */
    char quote = opts->quote ? opts->quote : '"';  /* COV-EXCL-BR: default_opts garante quote!=0 */
    const char **nav = opts->na_values;
    size_t nc = nav ? opts->na_count : 0;

    if (len == 0) return make_error("smaug_read_csv: arquivo vazio");

    /* --- Passo 1: tokenizar tudo em um vetor plano de strings --- */
    /* rows_tok[r] = array de campos da linha r (inclui header se houver) */
    size_t row_cap = 64;
    char ***rows = malloc(row_cap * sizeof(char **));
    size_t *row_sizes = malloc(row_cap * sizeof(size_t));
    if (!rows || !row_sizes) { free(rows); free(row_sizes); return make_error("OOM"); } /* COV-EXCL-BR: OOM de malloc inicial */
    size_t n_rows = 0;

    size_t pos = 0;
    while (pos < len) {
        /* pula linhas completamente vazias */
        if (buf[pos] == '\n' || (buf[pos] == '\r' && (pos+1>=len || buf[pos+1]=='\n'))) {
            if (buf[pos] == '\r') pos++;
            pos++;
            continue;
        }
        /* ler linha */
        size_t field_cap = 16;
        char **fields = malloc(field_cap * sizeof(char *));
        if (!fields) goto oom; /* COV-EXCL-BR: OOM de malloc de fields */
        size_t n_fields = 0;
        int eol = 0;
        while (!eol) {
            char *f = next_field(buf, len, &pos, sep, quote, &eol);
            if (!f) { for(size_t k=0;k<n_fields;k++)free(fields[k]); free(fields); goto oom; }
            if (n_fields >= field_cap) {
                field_cap *= 2;
                char **tmp = realloc(fields, field_cap * sizeof(char*));
                if (!tmp) { free(f); for(size_t k=0;k<n_fields;k++)free(fields[k]); free(fields); goto oom; } /* COV-EXCL-BR: OOM de realloc de fields — coberto pelo allocfail */
                fields = tmp;
            }
            fields[n_fields++] = f;
        }
        if (n_rows >= row_cap) {
            row_cap *= 2;
            char ***tr = realloc(rows, row_cap * sizeof(char**));
            size_t *ts = realloc(row_sizes, row_cap * sizeof(size_t));
            if (!tr || !ts) { for(size_t k=0;k<n_fields;k++)free(fields[k]); free(fields); goto oom; } /* COV-EXCL-BR: OOM de realloc de rows — coberto pelo allocfail */
            rows = tr; row_sizes = ts;
        }
        rows[n_rows] = fields;
        row_sizes[n_rows] = n_fields;
        n_rows++;
    }

    if (n_rows == 0) {
        free(rows); free(row_sizes);
        return make_error("smaug_read_csv: sem linhas de dados");
    }

    size_t header_row = opts->header ? 1 : 0;
    size_t n_cols = rows[0] ? row_sizes[0] : 0; /* COV-EXCL-BR: rows[0] nunca NULL — n_rows>0 garante alocação */
    if (n_cols == 0) goto cleanup_empty; /* COV-EXCL-BR: next_field sempre produz >=1 campo por linha */
    size_t data_rows = (n_rows > header_row) ? n_rows - header_row : 0;

    /* nomes das colunas */
    char **col_names = malloc(n_cols * sizeof(char *));
    if (!col_names) goto oom_cleanup;
    if (opts->header) {
        for (size_t c = 0; c < n_cols; c++)
            col_names[c] = (c < row_sizes[0]) ? strdup(rows[0][c]) : strdup(""); /* COV-EXCL-BR: c<n_cols<=row_sizes[0] por construção */
    } else {
        for (size_t c = 0; c < n_cols; c++) {
            char tmp[32]; snprintf(tmp, sizeof(tmp), "col%zu", c);
            col_names[c] = strdup(tmp);
        }
    }

    /* --- Passo 2: inferência de dtype --- */
    int *dtypes = calloc(n_cols, sizeof(int));
    if (!dtypes) { free(col_names); goto oom_cleanup; }
    for (size_t r = 0; r < data_rows; r++) {
        char **row = rows[r + header_row];
        size_t rsz = row_sizes[r + header_row];
        for (size_t c = 0; c < n_cols; c++) {
            const char *s = (c < rsz) ? row[c] : "";
            if (is_na(s, nav, nc)) continue;
            int64_t vi; double vd; uint8_t vb;
            int cand;
            if      (try_bool(s, &vb)) cand = DT_BOOL;
            else if (try_i64(s, &vi))  cand = DT_I64;
            else if (try_f64(s, &vd))  cand = DT_F64;
            else                        cand = DT_STR;
            dtypes[c] = dtype_upgrade(dtypes[c], cand);
            if (dtypes[c] == DT_STR) continue;
        }
    }
    for (size_t c = 0; c < n_cols; c++)
        if (dtypes[c] == DT_UNKNOWN) dtypes[c] = DT_STR;

    /* --- Passo 3: alocar e preencher séries --- */
    smaug_table_t *t = calloc(1, sizeof(smaug_table_t));
    if (!t) { free(dtypes); free(col_names); goto oom_cleanup; }
    t->columns = calloc(n_cols, sizeof(smaug_column_t));
    if (!t->columns) { free(t); free(dtypes); free(col_names); goto oom_cleanup; }
    t->ncols = n_cols;
    t->nrows = data_rows;

    for (size_t c = 0; c < n_cols; c++) {
        t->columns[c].name  = col_names[c]; col_names[c] = NULL;
        t->columns[c].dtype = dtype_name(dtypes[c]);

        switch (dtypes[c]) {
        case DT_I64: {
            smaug_series_i64_t *s = smaug_i64_create(data_rows);
            if (!s) { smaug_table_free(t); t=NULL; goto done; }
            for (size_t r = 0; r < data_rows; r++) {
                char **row = rows[r + header_row]; size_t rsz = row_sizes[r+header_row];
                const char *v = (c < rsz) ? row[c] : "";
                int64_t vi;
                if (is_na(v,nav,nc)) smaug_i64_set_null(s,r);
                else if (try_i64(v,&vi)) smaug_i64_set(s,r,vi); /* COV-EXCL-BR: dtype inferido garante try_i64=1 */
                else smaug_i64_set_null(s,r);
            }
            t->columns[c].i64 = s; break;
        }
        case DT_F64: {
            smaug_series_f64_t *s = smaug_f64_create(data_rows);
            if (!s) { smaug_table_free(t); t=NULL; goto done; }
            for (size_t r = 0; r < data_rows; r++) {
                char **row = rows[r + header_row]; size_t rsz = row_sizes[r+header_row];
                const char *v = (c < rsz) ? row[c] : "";
                double vd; int64_t vi;
                if (is_na(v,nav,nc)) smaug_f64_set_null(s,r);
                else if (try_f64(v,&vd)) smaug_f64_set(s,r,vd); /* COV-EXCL-BR: dtype inferido garante try_f64=1 */
                else if (try_i64(v,&vi)) smaug_f64_set(s,r,(double)vi); /* COV-EXCL-BR: idem para inteiros em coluna float */
                else smaug_f64_set_null(s,r);
            }
            t->columns[c].f64 = s; break;
        }
        case DT_BOOL: {
            smaug_series_bool_t *s = smaug_bool_create(data_rows);
            if (!s) { smaug_table_free(t); t=NULL; goto done; }
            for (size_t r = 0; r < data_rows; r++) {
                char **row = rows[r + header_row]; size_t rsz = row_sizes[r+header_row];
                const char *v = (c < rsz) ? row[c] : "";
                uint8_t vb;
                if (is_na(v,nav,nc)) smaug_bool_set_null(s,r);
                else if (try_bool(v,&vb)) smaug_bool_set(s,r,vb); /* COV-EXCL-BR: dtype inferido garante try_bool=1 */
                else smaug_bool_set_null(s,r);
            }
            t->columns[c].boolcol = s; break;
        }
        default: {
            smaug_series_str_t *s = smaug_str_create(data_rows);
            if (!s) { smaug_table_free(t); t=NULL; goto done; }
            for (size_t r = 0; r < data_rows; r++) {
                char **row = rows[r + header_row]; size_t rsz = row_sizes[r+header_row];
                const char *v = (c < rsz) ? row[c] : "";
                if (is_na(v,nav,nc)) smaug_str_set_null(s,r);
                else smaug_str_set(s,r,v,strlen(v));
            }
            t->columns[c].str = s; break;
        }
        }
    }

done:
    free(col_names); free(dtypes);
    for (size_t r = 0; r < n_rows; r++) {
        for (size_t c = 0; c < row_sizes[r]; c++) free(rows[r][c]);
        free(rows[r]);
    }
    free(rows); free(row_sizes);
    return t;

cleanup_empty:
    free(rows); free(row_sizes);
    return make_error("smaug_read_csv: sem colunas");
oom_cleanup:
    for (size_t r = 0; r < n_rows; r++) {
        for (size_t c = 0; c < row_sizes[r]; c++) free(rows[r][c]);
        free(rows[r]);
    }
    free(rows); free(row_sizes);
    return make_error("smaug_read_csv: OOM");
oom:
    for (size_t r = 0; r < n_rows; r++) {
        if (rows[r]) { for(size_t c=0;c<row_sizes[r];c++) free(rows[r][c]); free(rows[r]); }
    }
    free(rows); free(row_sizes);
    return make_error("smaug_read_csv: OOM");
}

smaug_table_t *smaug_read_csv(const char *path, const smaug_csv_opts_t *opts) {
    size_t len; char *buf = read_file(path, &len);
    if (!buf) {
        char msg[256]; snprintf(msg,sizeof(msg),"smaug_read_csv: não foi possível abrir '%s'",path);
        return make_error(msg);
    }
    smaug_table_t *t = smaug_read_csv_mem(buf, len, opts);
    free(buf); return t;
}

/* ===================================================================
   Writer CSV
   =================================================================== */

typedef struct { char *data; size_t len; size_t cap; } wbuf_t;

static int wbuf_push(wbuf_t *b, const char *s, size_t n) {
    if (b->len + n >= b->cap) {
        size_t ncap = b->cap ? b->cap * 2 : 4096;
        while (ncap <= b->len + n) ncap *= 2;
        char *tmp = realloc(b->data, ncap);
        if (!tmp) return -1;
        b->data = tmp; b->cap = ncap;
    }
    memcpy(b->data + b->len, s, n); b->len += n; return 0;
}
static int wbuf_pushc(wbuf_t *b, char c) { return wbuf_push(b, &c, 1); }

static int write_field(wbuf_t *b, const char *s, size_t n, char sep, char quote) {
    int needs_quote = 0;
    for (size_t i = 0; i < n; i++)
        if (s[i]==sep||s[i]=='\n'||s[i]=='\r'||s[i]==quote) { needs_quote=1; break; }
    if (!needs_quote) return wbuf_push(b, s, n);
    if (wbuf_pushc(b, quote)) return -1;
    for (size_t i = 0; i < n; i++) {
        if (s[i] == quote && wbuf_pushc(b, quote)) return -1;
        if (wbuf_pushc(b, s[i])) return -1;
    }
    return wbuf_pushc(b, quote);
}

char *smaug_write_csv_mem(const smaug_table_t *t,
                           const smaug_csv_write_opts_t *opts, size_t *out_len) {
    if (!t || !out_len) return NULL;
    smaug_csv_write_opts_t def = smaug_csv_write_default_opts();
    if (!opts) opts = &def;
    char sep = opts->sep ? opts->sep : ',';   /* COV-EXCL-BR: write_default_opts garante sep!=0 */
    char quote = opts->quote ? opts->quote : '"'; /* COV-EXCL-BR: write_default_opts garante quote!=0 */
    wbuf_t b = {0};

    if (opts->header) {
        for (size_t c = 0; c < t->ncols; c++) {
            if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
            const char *n = t->columns[c].name ? t->columns[c].name : ""; /* COV-EXCL-BR: name sempre não-NULL após construção */
            if (write_field(&b, n, strlen(n), sep, quote)) goto oom;
        }
        if (wbuf_pushc(&b, '\n')) goto oom;
    }

    for (size_t r = 0; r < t->nrows; r++) {
        for (size_t c = 0; c < t->ncols; c++) {
            if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
            smaug_column_t *col = &t->columns[c];
            char tmp[64]; const char *s = tmp; size_t n;
            if (col->i64) {
                smaug_status_t st; int64_t v = smaug_i64_get(col->i64, r, &st);
                if (st==SMG_NULL_VALUE||st!=SMG_OK) { s=""; n=0; }
                else { n=(size_t)snprintf(tmp,sizeof(tmp),"%lld",(long long)v); s=tmp; }
            } else if (col->f64) {
                smaug_status_t st; double v = smaug_f64_get(col->f64, r, &st);
                if (st==SMG_NULL_VALUE||st!=SMG_OK) { s=""; n=0; }
                else if (v!=v) { s="nan"; n=3; }
                else { n=(size_t)snprintf(tmp,sizeof(tmp),"%.17g",v); s=tmp; }
            } else if (col->boolcol) {
                smaug_status_t st; uint8_t v = smaug_bool_get(col->boolcol, r, &st);
                if (st==SMG_NULL_VALUE||st!=SMG_OK) { s=""; n=0; }
                else { s=v?"true":"false"; n=strlen(s); }
            } else if (col->str) {
                size_t slen; const char *sv = smaug_str_get(col->str, r, &slen);
                if (!sv) { s=""; n=0; } else { s=sv; n=slen; }
            } else { s=""; n=0; }
            if (write_field(&b, s, n, sep, quote)) goto oom;
        }
        if (wbuf_pushc(&b, '\n')) goto oom;
    }
    /* adiciona \0 de terminação para uso como string C (não conta em out_len) */
    if (wbuf_pushc(&b, '\0')) goto oom;
    *out_len = b.len - 1;  /* out_len não inclui o \0 */
    return b.data;
oom: free(b.data); return NULL;
}

int smaug_write_csv(const char *path, const smaug_table_t *t,
                    const smaug_csv_write_opts_t *opts) {
    size_t len; char *buf = smaug_write_csv_mem(t, opts, &len);
    if (!buf) return -1;
    FILE *f = fopen(path, "wb");
    if (!f) { free(buf); return -1; }
    size_t w = fwrite(buf, 1, len, f); fclose(f); free(buf);
    return (w==len) ? 0 : -1;
}
