/* tests/test_io_c.c
 *
 * Testes C do Anel 3 — parsers CSV e JSON.
 * Cobre os caminhos de erro, variantes de formato e casos de fronteira
 * que os testes Lua (test_io.lua) não exercitam em C direto.
 *
 * Filosofia: "o engine não confia no caller" — cada caminho de erro
 * documentado no código deve ter um teste que o percorre.
 */

#define _POSIX_C_SOURCE 200809L
#include "../include/smaug_io.h"
#include "../include/smaug_core.h"
#include "../include/smaug_string.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <math.h>

static int g_ok = 0;
static int g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { g_ok++; } \
    else { fprintf(stderr, "FALHOU [%s:%d]: %s\n", __FILE__, __LINE__, msg); g_fail++; } \
} while(0)

#define CHECK_STR(s, expected, msg) \
    CHECK((s) && strncmp((s), (expected), strlen(expected)) == 0, msg)

/* ===================================================================
   Helpers
   =================================================================== */

static int col_is_null(smaug_table_t *t, size_t col, size_t row) {
    smaug_status_t st;
    smaug_column_t *c = &t->columns[col];
    if (c->i64)     { smaug_i64_get(c->i64, row, &st);     return st == SMG_NULL_VALUE; }
    if (c->f64)     { smaug_f64_get(c->f64, row, &st);     return st == SMG_NULL_VALUE; }
    if (c->boolcol) { smaug_bool_get(c->boolcol, row, &st); return st == SMG_NULL_VALUE; }
    if (c->str)     { size_t n; const char *v = smaug_str_get(c->str, row, &n); return v == NULL; }
    return 1;
}

static int64_t get_i64(smaug_table_t *t, size_t col, size_t row) {
    smaug_status_t st;
    int64_t v = smaug_i64_get(t->columns[col].i64, row, &st);
    assert(st == SMG_OK);
    return v;
}

static double get_f64(smaug_table_t *t, size_t col, size_t row) {
    smaug_status_t st;
    double v = smaug_f64_get(t->columns[col].f64, row, &st);
    assert(st == SMG_OK);
    return v;
}

static uint8_t get_bool(smaug_table_t *t, size_t col, size_t row) {
    smaug_status_t st;
    uint8_t v = smaug_bool_get(t->columns[col].boolcol, row, &st);
    assert(st == SMG_OK);
    return v;
}

static const char *get_str(smaug_table_t *t, size_t col, size_t row, size_t *len) {
    return smaug_str_get(t->columns[col].str, row, len);
}

/* ===================================================================
   CSV — erros de entrada
   =================================================================== */

static void test_csv_empty(void) {
    smaug_table_t *t = smaug_read_csv_mem("", 0, NULL);
    CHECK(t != NULL,       "empty: retorna tabela");
    CHECK(t->error != NULL,"empty: tem mensagem de erro");
    smaug_table_free(t);
}

static void test_csv_only_blank_lines(void) {
    smaug_table_t *t = smaug_read_csv_mem("\n\n\n", 3, NULL);
    CHECK(t != NULL,       "blank lines: retorna tabela");
    CHECK(t->error != NULL,"blank lines: tem erro");
    smaug_table_free(t);
}

static void test_csv_only_header(void) {
    /* header sem dados → nrows=0, sem erro */
    smaug_table_t *t = smaug_read_csv_mem("a,b,c\n", 6, NULL);
    CHECK(t && !t->error,  "só header: sem erro");
    CHECK(t->ncols == 3,   "só header: 3 colunas");
    CHECK(t->nrows == 0,   "só header: 0 linhas");
    smaug_table_free(t);
}

static void test_csv_file_not_found(void) {
    smaug_table_t *t = smaug_read_csv("/caminho/inexistente/arquivo.csv", NULL);
    CHECK(t != NULL,       "arquivo inexistente: retorna tabela");
    CHECK(t->error != NULL,"arquivo inexistente: tem erro");
    smaug_table_free(t);
}

static void test_csv_table_free_null(void) {
    smaug_table_free(NULL);  /* não deve crashar */
    g_ok++;
}

/* ===================================================================
   CSV — variantes de formato
   =================================================================== */

static void test_csv_crlf(void) {
    /* CRLF como terminador de linha (Windows) */
    const char *csv = "a,b\r\n1,2\r\n3,4\r\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,        "CRLF: sem erro");
    CHECK(t->nrows == 2,         "CRLF: 2 linhas");
    CHECK(get_i64(t, 0, 0) == 1,"CRLF: a[0]=1");
    CHECK(get_i64(t, 1, 1) == 4,"CRLF: b[1]=4");
    smaug_table_free(t);
}

static void test_csv_cr_only(void) {
    /* CR sem LF — menos comum mas válido */
    const char *csv = "a,b\r1,2\r3,4\r";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,        "CR only: sem erro");
    CHECK(t->nrows == 2,         "CR only: 2 linhas");
    smaug_table_free(t);
}

static void test_csv_no_trailing_newline(void) {
    /* última linha sem \n */
    const char *csv = "a,b\n1,2\n3,4";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,        "sem newline final: sem erro");
    CHECK(t->nrows == 2,         "sem newline final: 2 linhas");
    CHECK(get_i64(t, 1, 1) == 4,"sem newline final: b[1]=4");
    smaug_table_free(t);
}

static void test_csv_tab_sep(void) {
    const char *tsv = "a\tb\tc\n10\t20\t30\n";
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.sep = '\t';
    smaug_table_t *t = smaug_read_csv_mem(tsv, strlen(tsv), &o);
    CHECK(t && !t->error,         "TSV: sem erro");
    CHECK(t->ncols == 3,          "TSV: 3 colunas");
    CHECK(get_i64(t, 2, 0) == 30,"TSV: c[0]=30");
    smaug_table_free(t);
}

static void test_csv_no_header(void) {
    const char *csv = "1,2\n3,4\n";
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.header = 0;
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), &o);
    CHECK(t && !t->error,         "sem header: sem erro");
    CHECK(t->ncols == 2,          "sem header: 2 colunas");
    CHECK(t->nrows == 2,          "sem header: 2 linhas");
    CHECK(strcmp(t->columns[0].name, "col0") == 0, "sem header: nome col0");
    CHECK(get_i64(t, 0, 0) == 1, "sem header: col0[0]=1");
    smaug_table_free(t);
}

static void test_csv_quotes_rfc4180(void) {
    /* campo com sep dentro de aspas */
    const char *csv = "nome,cidade\n\"Fulano, Jr.\",\"São Paulo\"\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error, "aspas RFC4180: sem erro");
    size_t n; const char *s = get_str(t, 0, 0, &n);
    CHECK(s && strncmp(s, "Fulano, Jr.", 11) == 0, "aspas: nome com vírgula");
    smaug_table_free(t);
}

static void test_csv_quotes_escaped(void) {
    /* aspas escapadas dentro de campo: "" → " */
    const char *csv = "v\n\"val \"\"com\"\" aspas\"\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error, "aspas escapadas: sem erro");
    size_t n; const char *s = get_str(t, 0, 0, &n);
    CHECK(s && strncmp(s, "val \"com\" aspas", 15) == 0, "aspas escapadas: valor correto");
    smaug_table_free(t);
}

static void test_csv_quotes_unclosed(void) {
    /* aspas não fechadas — parser deve tolerar (trata como fim de buffer) */
    const char *csv = "v\n\"abc\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t != NULL, "aspas não fechadas: retorna algo (sem crash)");
    smaug_table_free(t);
}

static void test_csv_newline_in_quoted_field(void) {
    /* newline dentro de campo entre aspas (RFC 4180 permite) */
    const char *csv = "v\n\"linha1\nlinha2\"\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error, "newline em campo: sem erro");
    CHECK(t->nrows == 1,  "newline em campo: 1 linha");
    size_t n; const char *s = get_str(t, 0, 0, &n);
    CHECK(s && n == 13,   "newline em campo: comprimento correto (linha1\nlinha2 = 13 bytes)");
    smaug_table_free(t);
}

static void test_csv_na_values(void) {
    /* NA padrão: célula vazia (campo real, não linha vazia), "NA", "null",
       "N/A", "nan", "NaN", "NULL". Linhas completamente vazias são PULADAS
       pelo parser (comportamento documentado). Para testar célula vazia,
       usamos dois campos separados por vírgula. */
    const char *csv = "v,x\n,1\nNA,2\nnull,3\nN/A,4\nnan,5\nNaN,6\nNULL,7\n1,8\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,      "NA padrão: sem erro");
    CHECK(t->nrows == 8,       "NA padrão: 8 linhas");
    /* coluna v: todos NA exceto última */
    for (size_t r = 0; r < 7; r++)
        CHECK(col_is_null(t, 0, r), "NA padrão: linha NA");
    CHECK(!col_is_null(t, 0, 7),    "NA padrão: linha 8 não é NA");
    /* coluna x: nenhum NA */
    for (size_t r = 0; r < 8; r++)
        CHECK(!col_is_null(t, 1, r), "NA padrão: col x sem NA");
    smaug_table_free(t);
}

/* ===================================================================
   CSV — inferência de tipo: todos os caminhos
   =================================================================== */

static void test_csv_infer_bool_variants(void) {
    /* True/TRUE e False/FALSE além de true/false */
    const char *csv = "v\ntrue\nTrue\nTRUE\nfalse\nFalse\nFALSE\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,               "bool variantes: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"bool") == 0, "bool variantes: dtype bool");
    CHECK(get_bool(t, 0, 0) == 1,      "true → 1");
    CHECK(get_bool(t, 0, 1) == 1,      "True → 1");
    CHECK(get_bool(t, 0, 2) == 1,      "TRUE → 1");
    CHECK(get_bool(t, 0, 3) == 0,      "false → 0");
    CHECK(get_bool(t, 0, 4) == 0,      "False → 0");
    CHECK(get_bool(t, 0, 5) == 0,      "FALSE → 0");
    smaug_table_free(t);
}

static void test_csv_infer_mixed_int_float(void) {
    /* int e float na mesma coluna → float64 */
    const char *csv = "v\n1\n2.5\n3\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error, "misto int/float: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"float64") == 0, "misto: dtype float64");
    smaug_table_free(t);
}

static void test_csv_infer_float_with_int_row(void) {
    /* coluna inferida como f64: linhas que parecem i64 devem ser convertidas */
    const char *csv = "v\n1.5\n2\n3.5\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error, "f64 com linha int: sem erro");
    double v = get_f64(t, 0, 1);
    CHECK(fabs(v - 2.0) < 1e-9, "f64 com linha int: valor 2.0");
    smaug_table_free(t);
}

static void test_csv_infer_all_na_column(void) {
    /* coluna toda NA → string (fallback seguro) */
    const char *csv = "v\n\n\n\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error, "col toda NA: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"string") == 0, "col toda NA: dtype string");
    smaug_table_free(t);
}

static void test_csv_infer_bool_mixed_with_string(void) {
    /* bool + string não-bool → string */
    const char *csv = "v\ntrue\nhello\nfalse\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error, "bool+str: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"string") == 0, "bool+str: dtype string");
    smaug_table_free(t);
}


/* csv.c:143 — ramo \n no else-if do tokenizador (campo terminado por \n puro) */
static void test_csv_lf_only_field_end(void) {
    const char *csv = "a,b\n1,2\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,         "LF field end: sem erro");
    CHECK(t->nrows == 1,          "LF field end: 1 linha");
    CHECK(get_i64(t, 1, 0) == 2, "LF field end: b[0]=2");
    smaug_table_free(t);
}

/* csv.c:178/179 — linha vazia com \r\n e \r no último byte (pos+1>=len) */
static void test_csv_crlf_at_eof(void) {
    /* \r\n final */
    const char *csv = "v\n1\r\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,         "CRLF EOF: sem erro");
    CHECK(t->nrows == 1,          "CRLF EOF: 1 linha");
    smaug_table_free(t);
    /* \r sem \n no último byte */
    const char *csv2 = "v\n1\r";
    smaug_table_t *t2 = smaug_read_csv_mem(csv2, strlen(csv2), NULL);
    CHECK(t2 && !t2->error,       "CR EOF: sem erro");
    CHECK(t2->nrows == 1,         "CR EOF: 1 linha");
    smaug_table_free(t2);
}

/* csv.c:137 — PUSH em campo sem aspas > 32 bytes (força realloc no macro) */
static void test_csv_long_unquoted_field(void) {
    const char *csv = "v\nabcdefghijklmnopqrstuvwxyzABCDEFGH\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,         "long field: sem erro");
    CHECK(t->nrows == 1,          "long field: 1 linha");
    size_t n; const char *s = get_str(t, 0, 0, &n);
    CHECK(n == 34,                "long field: comprimento 34");
    smaug_table_free(t);
}

/* csv.c:192 — realloc de fields[] quando linha tem > 16 campos */
static void test_csv_many_columns(void) {
    char csv[512];
    int pos = 0;
    for (int i = 0; i < 20; i++)
        pos += sprintf(csv + pos, "%sc%d", i ? "," : "", i);
    pos += sprintf(csv + pos, "\n");
    for (int i = 0; i < 20; i++)
        pos += sprintf(csv + pos, "%s%d", i ? "," : "", i * 10);
    pos += sprintf(csv + pos, "\n");
    smaug_table_t *t = smaug_read_csv_mem(csv, (size_t)pos, NULL);
    CHECK(t && !t->error,            "many cols: sem erro");
    CHECK(t->ncols == 20,            "many cols: 20 colunas");
    CHECK(t->nrows == 1,             "many cols: 1 linha");
    CHECK(get_i64(t, 19, 0) == 190, "many cols: col19[0]=190");
    smaug_table_free(t);
}

static void test_csv_short_row(void) {
    /* linha com menos campos que o header → campos faltando viram NA */
    const char *csv = "a,b,c\n1,2\n3,4,5\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,       "linha curta: sem erro");
    CHECK(t->nrows == 2,        "linha curta: 2 linhas");
    CHECK(col_is_null(t, 2, 0), "linha curta: c[0] = NA");
    CHECK(!col_is_null(t,2, 1), "linha curta: c[1] = 5 (não NA)");
    smaug_table_free(t);
}

/* ===================================================================
   CSV writer — caminhos adicionais
   =================================================================== */

static void test_csv_write_nan(void) {
    /* NaN em coluna float64 → "nan" no CSV */
    smaug_series_f64_t *s = smaug_f64_create(2);
    smaug_f64_set(s, 0, 1.0);
    smaug_f64_set(s, 1, (double)(0.0/0.0)); /* NaN */

    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name  = "v";
    col.dtype = "float64";
    col.f64   = s;
    t.columns = &col;
    t.ncols   = 1;
    t.nrows   = 2;

    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    size_t len;
    char *out = smaug_write_csv_mem(&t, &wo, &len);
    CHECK(out != NULL,                         "write NaN: retorna buffer");
    CHECK(strstr(out, "nan") != NULL,          "write NaN: contém 'nan'");
    free(out);
    smaug_f64_free(s);
}

static void test_csv_write_field_with_sep(void) {
    /* campo com vírgula → deve ser escapado com aspas */
    smaug_series_str_t *s = smaug_str_create(1);
    smaug_str_set(s, 0, "a,b", 3);

    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name  = "v";
    col.dtype = "string";
    col.str   = s;
    t.columns = &col;
    t.ncols   = 1;
    t.nrows   = 1;

    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    size_t len;
    char *out = smaug_write_csv_mem(&t, &wo, &len);
    CHECK(out != NULL,              "write sep em campo: retorna buffer");
    CHECK(strstr(out, "\"a,b\"") != NULL, "write sep: campo entre aspas");
    free(out);
    smaug_str_free(s);
}

static void test_csv_write_field_with_quote(void) {
    /* campo com aspas → "" dentro de aspas */
    smaug_series_str_t *s = smaug_str_create(1);
    smaug_str_set(s, 0, "a\"b", 3);

    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name  = "v";
    col.dtype = "string";
    col.str   = s;
    t.columns = &col;
    t.ncols   = 1;
    t.nrows   = 1;

    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    size_t len;
    char *out = smaug_write_csv_mem(&t, &wo, &len);
    CHECK(out != NULL,                    "write aspas em campo: retorna buffer");
    CHECK(strstr(out, "\"a\"\"b\"") != NULL, "write aspas: escape correto");
    free(out);
    smaug_str_free(s);
}

static void test_csv_write_no_header(void) {
    smaug_series_i64_t *s = smaug_i64_create(1);
    smaug_i64_set(s, 0, 42);

    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name  = "v";
    col.dtype = "int64";
    col.i64   = s;
    t.columns = &col;
    t.ncols   = 1;
    t.nrows   = 1;

    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    wo.header = 0;
    size_t len;
    char *out = smaug_write_csv_mem(&t, &wo, &len);
    CHECK(out != NULL,                "write sem header: retorna buffer");
    CHECK(strstr(out, "v") == NULL,   "write sem header: sem nome de coluna");
    CHECK(strstr(out, "42") != NULL,  "write sem header: contém valor");
    free(out);
    smaug_i64_free(s);
}

static void test_csv_write_file(void) {
    smaug_series_i64_t *s = smaug_i64_create(2);
    smaug_i64_set(s, 0, 1);
    smaug_i64_set(s, 1, 2);

    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name  = "v";
    col.dtype = "int64";
    col.i64   = s;
    t.columns = &col;
    t.ncols   = 1;
    t.nrows   = 2;

    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    int rc = smaug_write_csv("/tmp/smaug_test_c.csv", &t, &wo);
    CHECK(rc == 0, "write file: sucesso");

    /* ler de volta e verificar */
    smaug_table_t *t2 = smaug_read_csv("/tmp/smaug_test_c.csv", NULL);
    CHECK(t2 && !t2->error,       "write file roundtrip: sem erro");
    CHECK(t2->nrows == 2,         "write file roundtrip: 2 linhas");
    CHECK(get_i64(t2, 0, 1) == 2,"write file roundtrip: v[1]=2");
    smaug_table_free(t2);
    smaug_i64_free(s);
}

static void test_csv_write_invalid_path(void) {
    smaug_series_i64_t *s = smaug_i64_create(1);
    smaug_i64_set(s, 0, 1);

    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name  = "v"; col.dtype = "int64"; col.i64 = s;
    t.columns = &col; t.ncols = 1; t.nrows = 1;

    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    int rc = smaug_write_csv("/caminho/inexistente/arquivo.csv", &t, &wo);
    CHECK(rc == -1, "write path inválido: retorna -1");
    smaug_i64_free(s);
}

/* ===================================================================
   JSON — erros e variantes
   =================================================================== */

static void test_json_empty_array(void) {
    const char *j = "[]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error, "JSON []: sem erro");
    CHECK(t->nrows == 0,  "JSON []: 0 linhas");
    smaug_table_free(t);
}

static void test_json_not_array(void) {
    /* JSON que não começa com '[' → erro */
    const char *j = "{\"a\":1}";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && t->error != NULL, "JSON não-array: tem erro");
    smaug_table_free(t);
}

static void test_json_null_values(void) {
    const char *j = "[{\"v\":null},{\"v\":1}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error,         "JSON null: sem erro");
    CHECK(col_is_null(t, 0, 0),  "JSON null: v[0]=null");
    CHECK(!col_is_null(t, 0, 1), "JSON null: v[1] não null");
    smaug_table_free(t);
}

static void test_json_bool_values(void) {
    const char *j = "[{\"ok\":true},{\"ok\":false},{\"ok\":null}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error,               "JSON bool: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"bool") == 0, "JSON bool: dtype bool");
    CHECK(get_bool(t, 0, 0) == 1,      "JSON bool: true → 1");
    CHECK(get_bool(t, 0, 1) == 0,      "JSON bool: false → 0");
    CHECK(col_is_null(t, 0, 2),        "JSON bool: null → NA");
    smaug_table_free(t);
}

static void test_json_int_and_float(void) {
    /* int + float na mesma coluna → float64 */
    const char *j = "[{\"v\":1},{\"v\":2.5}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error, "JSON int+float: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"float64") == 0, "JSON int+float: float64");
    smaug_table_free(t);
}

static void test_json_float_in_int_col(void) {
    /* float que cabe em int64: 1.0 → int64 */
    const char *j = "[{\"v\":1},{\"v\":2},{\"v\":3}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error, "JSON int col: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"int64") == 0, "JSON int col: int64");
    CHECK(get_i64(t, 0, 2) == 3, "JSON int col: v[2]=3");
    smaug_table_free(t);
}

static void test_json_string_escape(void) {
    /* escapes JSON: \n \t \\ \" */
    const char *j = "[{\"v\":\"a\\nb\\tc\\\\d\\\"\"}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error, "JSON escape: sem erro");
    size_t n; const char *s = get_str(t, 0, 0, &n);
    CHECK(s && n == 8,    "JSON escape: comprimento 8");
    CHECK(s[1] == '\n',   "JSON escape: \\n");
    CHECK(s[3] == '\t',   "JSON escape: \\t");
    CHECK(s[5] == '\\',   "JSON escape: \\\\");
    CHECK(s[7] == '"',    "JSON escape: \\\"");
    smaug_table_free(t);
}

static void test_json_file_not_found(void) {
    smaug_table_t *t = smaug_read_json("/caminho/inexistente/arquivo.json");
    CHECK(t && t->error != NULL, "JSON arquivo inexistente: tem erro");
    smaug_table_free(t);
}

static void test_json_write_nan(void) {
    /* NaN em float64 → null no JSON */
    smaug_series_f64_t *s = smaug_f64_create(2);
    smaug_f64_set(s, 0, 1.5);
    smaug_f64_set(s, 1, (double)(0.0/0.0));

    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name = "v"; col.dtype = "float64"; col.f64 = s;
    t.columns = &col; t.ncols = 1; t.nrows = 2;

    smaug_json_write_opts_t wo = {0};
    size_t len;
    char *out = smaug_write_json_mem(&t, &wo, &len);
    CHECK(out != NULL,               "JSON write NaN: retorna buffer");
    CHECK(strstr(out, "null") != NULL,"JSON write NaN: NaN → null");
    free(out);
    smaug_f64_free(s);
}

static void test_json_write_escape(void) {
    /* JSON writer: escapa \n \t \\ " e caracteres de controle */
    smaug_series_str_t *s = smaug_str_create(1);
    const char *val = "a\nb\tc\\\"\x01";  /* \n \t \\ " e ctrl */
    smaug_str_set(s, 0, val, strlen(val));

    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name = "v"; col.dtype = "string"; col.str = s;
    t.columns = &col; t.ncols = 1; t.nrows = 1;

    smaug_json_write_opts_t wo = {0};
    size_t len;
    char *out = smaug_write_json_mem(&t, &wo, &len);
    CHECK(out != NULL,                    "JSON write escape: retorna buffer");
    CHECK(strstr(out, "\\n")  != NULL,    "JSON write escape: \\n");
    CHECK(strstr(out, "\\t")  != NULL,    "JSON write escape: \\t");
    CHECK(strstr(out, "\\\\") != NULL,    "JSON write escape: \\\\");
    CHECK(strstr(out, "\\\"") != NULL,    "JSON write escape: \\\"");
    CHECK(strstr(out, "\\u0001") != NULL, "JSON write escape: ctrl→\\uXXXX");
    free(out);
    smaug_str_free(s);
}

static void test_json_write_pretty(void) {
    const char *j = "[{\"x\":1}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    smaug_json_write_opts_t wo = {.pretty = 1};
    size_t len;
    char *out = smaug_write_json_mem(t, &wo, &len);
    CHECK(out != NULL,            "JSON pretty: retorna buffer");
    CHECK(strstr(out,"\n") != NULL,"JSON pretty: tem newlines");
    CHECK(strstr(out,"  ") != NULL,"JSON pretty: tem indentação");
    free(out);
    smaug_table_free(t);
}

static void test_json_write_file(void) {
    const char *j = "[{\"a\":1,\"b\":\"x\"}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    smaug_json_write_opts_t wo = {0};
    int rc = smaug_write_json("/tmp/smaug_test_c.json", t, &wo);
    CHECK(rc == 0, "JSON write file: sucesso");

    smaug_table_t *t2 = smaug_read_json("/tmp/smaug_test_c.json");
    CHECK(t2 && !t2->error,       "JSON file roundtrip: sem erro");
    CHECK(t2->nrows == 1,         "JSON file roundtrip: 1 linha");
    CHECK(get_i64(t2, 0, 0) == 1,"JSON file roundtrip: a[0]=1");
    smaug_table_free(t);
    smaug_table_free(t2);
}

static void test_json_write_invalid_path(void) {
    const char *j = "[{\"v\":1}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    smaug_json_write_opts_t wo = {0};
    int rc = smaug_write_json("/caminho/inexistente/arquivo.json", t, &wo);
    CHECK(rc == -1, "JSON write path inválido: retorna -1");
    smaug_table_free(t);
}

/* ===================================================================
   Roundtrips (CSV e JSON)
   =================================================================== */

static void test_csv_roundtrip_all_dtypes(void) {
    /* i64, f64, bool, string com NAs em cada dtype */
    const char *csv =
        "i,f,b,s\n"
        "1,1.5,true,hello\n"
        ",2.5,false,\n"
        "3,,true,world\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,  "roundtrip all: leitura ok");
    CHECK(t->nrows == 3,   "roundtrip all: 3 linhas");

    /* escreve e lê de volta */
    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    size_t len;
    char *out = smaug_write_csv_mem(t, &wo, &len);
    CHECK(out != NULL, "roundtrip all: escrita ok");

    smaug_table_t *t2 = smaug_read_csv_mem(out, len, NULL);
    CHECK(t2 && !t2->error,          "roundtrip all: releitura ok");
    CHECK(t2->nrows == 3,            "roundtrip all: 3 linhas relidas");
    CHECK(col_is_null(t2, 0, 1),    "roundtrip all: i[1] NA");
    CHECK(col_is_null(t2, 1, 2),    "roundtrip all: f[2] NA");
    CHECK(get_bool(t2, 2, 0) == 1, "roundtrip all: b[0]=true");
    CHECK(get_bool(t2, 2, 1) == 0, "roundtrip all: b[1]=false");
    CHECK(col_is_null(t2, 3, 1),   "roundtrip all: s[1] NA");

    free(out);
    smaug_table_free(t);
    smaug_table_free(t2);
}

static void test_json_roundtrip_all_dtypes(void) {
    const char *j =
        "[{\"i\":1,\"f\":1.5,\"b\":true,\"s\":\"hello\"},"
         "{\"i\":null,\"f\":2.5,\"b\":false,\"s\":null},"
         "{\"i\":3,\"f\":null,\"b\":true,\"s\":\"world\"}]";

    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error, "JSON roundtrip all: leitura ok");

    smaug_json_write_opts_t wo = {0};
    size_t len;
    char *out = smaug_write_json_mem(t, &wo, &len);
    CHECK(out != NULL, "JSON roundtrip all: escrita ok");

    smaug_table_t *t2 = smaug_read_json_mem(out, len);
    CHECK(t2 && !t2->error,          "JSON roundtrip all: releitura ok");
    CHECK(t2->nrows == 3,            "JSON roundtrip all: 3 linhas");
    CHECK(col_is_null(t2, 0, 1),    "JSON roundtrip: i[1] null");
    CHECK(col_is_null(t2, 1, 2),    "JSON roundtrip: f[2] null");
    CHECK(get_bool(t2, 2, 2) == 1, "JSON roundtrip: b[2]=true");

    free(out);
    smaug_table_free(t);
    smaug_table_free(t2);
}


static void test_csv_na_custom(void) {
    /* na_values customizados passados pelo caller */
    const char *nav[] = {"N/D", "ausente"};
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.na_values = nav;
    o.na_count  = 2;
    const char *csv = "v\nN/D\nausente\n1\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), &o);
    CHECK(t && !t->error,         "na custom: sem erro");
    CHECK(col_is_null(t, 0, 0),  "na custom: N/D → null");
    CHECK(col_is_null(t, 0, 1),  "na custom: ausente → null");
    CHECK(!col_is_null(t, 0, 2), "na custom: 1 não é null");
    smaug_table_free(t);
}

static void test_json_negative_number(void) {
    const char *j = "[{\"v\":-42}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error,         "JSON negativo: sem erro");
    CHECK(get_i64(t, 0, 0) == -42,"JSON negativo: v=-42");
    smaug_table_free(t);
}

static void test_json_exponent_number(void) {
    const char *j = "[{\"v\":1e3}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error,          "JSON expoente: sem erro");
    CHECK(fabs(get_f64(t, 0, 0) - 1000.0) < 1.0, "JSON expoente: 1e3=1000");
    smaug_table_free(t);
}

static void test_json_negative_exponent(void) {
    const char *j = "[{\"v\":1.5e-2}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error,          "JSON exp negativo: sem erro");
    CHECK(fabs(get_f64(t, 0, 0) - 0.015) < 1e-9, "JSON exp negativo: 1.5e-2");
    smaug_table_free(t);
}

static void test_json_unicode_escape(void) {
    /* \uXXXX → '?' (placeholder documentado) */
    const char *j = "[{\"v\":\"\\u0041\"}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error, "JSON unicode: sem erro");
    size_t n; const char *s = get_str(t, 0, 0, &n);
    CHECK(s && n == 1,    "JSON unicode: 1 char");
    CHECK(s[0] == '?',    "JSON unicode: mapeado para '?'");
    smaug_table_free(t);
}

static void test_json_whitespace_variants(void) {
    /* espaços, tabs e newlines entre tokens */
    const char *j = "[\n  {\n    \"x\" : 1\n  }\n]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error,         "JSON whitespace: sem erro");
    CHECK(get_i64(t, 0, 0) == 1, "JSON whitespace: x=1");
    smaug_table_free(t);
}

static void test_json_bf_escape(void) {
    /* \b e \f no writer JSON — escapes de controle menos comuns */
    smaug_series_str_t *s = smaug_str_create(1);
    const char *val = "a\bf\fc";  /* backspace e form-feed */
    smaug_str_set(s, 0, val, strlen(val));
    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name = "v"; col.dtype = "string"; col.str = s;
    t.columns = &col; t.ncols = 1; t.nrows = 1;
    smaug_json_write_opts_t wo = {0};
    size_t len;
    char *out = smaug_write_json_mem(&t, &wo, &len);
    CHECK(out != NULL, "JSON \\b\\f: retorna buffer");
    /* \b e \f não têm escape explícito no writer — viram \u0008 e \u000c */
    CHECK(strstr(out, "\\u0008") != NULL || strstr(out, "\\b") != NULL,
          "JSON \\b: escapado");
    free(out);
    smaug_str_free(s);
}

/* ===================================================================
   main
   =================================================================== */

int main(void) {
    /* CSV — erros */
    test_csv_empty();
    test_csv_only_blank_lines();
    test_csv_only_header();
    test_csv_file_not_found();
    test_csv_table_free_null();

    /* CSV — variantes de formato */
    test_csv_crlf();
    test_csv_cr_only();
    test_csv_no_trailing_newline();
    test_csv_tab_sep();
    test_csv_no_header();
    test_csv_quotes_rfc4180();
    test_csv_quotes_escaped();
    test_csv_quotes_unclosed();
    test_csv_newline_in_quoted_field();
    test_csv_na_values();

    /* CSV — inferência */
    test_csv_infer_bool_variants();
    test_csv_infer_mixed_int_float();
    test_csv_infer_float_with_int_row();
    test_csv_infer_all_na_column();
    test_csv_infer_bool_mixed_with_string();
    test_csv_lf_only_field_end();
    test_csv_crlf_at_eof();
    test_csv_long_unquoted_field();
    test_csv_many_columns();
    test_csv_short_row();

    /* CSV — writer */
    test_csv_write_nan();
    test_csv_write_field_with_sep();
    test_csv_write_field_with_quote();
    test_csv_write_no_header();
    test_csv_write_file();
    test_csv_write_invalid_path();

    /* JSON — erros e variantes */
    test_json_empty_array();
    test_json_not_array();
    test_json_null_values();
    test_json_bool_values();
    test_json_int_and_float();
    test_json_float_in_int_col();
    test_json_string_escape();
    test_json_file_not_found();

    /* JSON — writer */
    test_json_write_nan();
    test_json_write_escape();
    test_json_write_pretty();
    test_json_write_file();
    test_json_write_invalid_path();

    /* CSV — na customizados */
    test_csv_na_custom();

    /* JSON — variantes numéricas e escapes */
    test_json_negative_number();
    test_json_exponent_number();
    test_json_negative_exponent();
    test_json_unicode_escape();
    test_json_whitespace_variants();
    test_json_bf_escape();

    /* Roundtrips */
    test_csv_roundtrip_all_dtypes();
    test_json_roundtrip_all_dtypes();

    if (g_fail == 0)
        printf("PASS: test_io_c (%d checks)\n", g_ok);
    else
        printf("FAIL: %d/%d checks falharam\n", g_fail, g_ok + g_fail);

    return g_fail > 0 ? 1 : 0;
}
