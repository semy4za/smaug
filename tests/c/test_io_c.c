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

/* Diretório temporário portátil: respeita TMPDIR/TMP/TEMP (Windows usa TEMP),
 * com fallback "/tmp". Monta "<dir>/<name>" em buf. Usa '/' como separador,
 * aceito tanto pela CRT do Windows quanto pelo POSIX. */
static const char *tmp_path(char *buf, size_t size, const char *name) {
    const char *dir = getenv("TMPDIR");
    if (!dir || !*dir) dir = getenv("TMP");
    if (!dir || !*dir) dir = getenv("TEMP");
    if (!dir || !*dir) dir = "/tmp";
    snprintf(buf, size, "%s/%s", dir, name);
    return buf;
}

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
    CHECK(get_i64(t, 0, 0) == 1,"CR only: a[0]=1");
    CHECK(get_i64(t, 1, 0) == 2,"CR only: b[0]=2");
    CHECK(get_i64(t, 0, 1) == 3,"CR only: a[1]=3");
    CHECK(get_i64(t, 1, 1) == 4,"CR only: b[1]=4");
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

/* H.5.b — decimal customizado (CSV brasileiro: sep=';' decimal=',') */
static void test_csv_decimal_comma(void) {
    const char *csv = "nome;valor\nproduto;34,12\noutro;5,5\n";
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.sep = ';'; o.decimal = ',';
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), &o);
    CHECK(t && !t->error,                 "decimal ,: sem erro");
    CHECK(t->ncols == 2,                  "decimal ,: 2 colunas");
    CHECK(t->columns[1].f64 != NULL,      "decimal ,: valor inferido float64");
    CHECK(get_f64(t, 1, 0) > 34.11 && get_f64(t, 1, 0) < 34.13, "decimal ,: 34,12 → 34.12");
    CHECK(get_f64(t, 1, 1) > 5.49  && get_f64(t, 1, 1) < 5.51,  "decimal ,: 5,5 → 5.5");
    smaug_table_free(t);
}

/* H.5.b — '.' literal com decimal ',' não é float válido (rigor preservado) */
static void test_csv_decimal_comma_rejects_dot(void) {
    const char *csv = "nome;valor\nproduto;34.12\n";
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.sep = ';'; o.decimal = ',';
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), &o);
    CHECK(t && !t->error,                 "decimal ,: '.' literal sem erro de parse");
    CHECK(t->columns[1].str != NULL,      "decimal ,: '34.12' vira string (não float)");
    smaug_table_free(t);

    /* :112 — após trocar ',' por '.', a string ainda é lixo → rejeitada como float */
    const char *csv2 = "nome;valor\nx;12,3,4\noutro;5,6x\n";
    smaug_table_t *t2 = smaug_read_csv_mem(csv2, strlen(csv2), &o);
    CHECK(t2 && !t2->error,               "decimal ,: lixo após troca sem erro de parse");
    CHECK(t2->columns[1].str != NULL,     "decimal ,: '12,3,4' e '5,6x' viram string");
    smaug_table_free(t2);

    /* :104 — campo numérico absurdamente longo (>=64 chars) → não-float, vira string */
    char longnum[80];
    longnum[0] = '\0';
    /* monta "1111...,11" com >64 chars, separador decimal ',' */
    char field[80];
    for (int i = 0; i < 70; i++) field[i] = '1';
    field[70] = ','; field[71] = '5'; field[72] = '\0';
    char csv3[160];
    snprintf(csv3, sizeof(csv3), "v\n%s\n", field);
    smaug_table_t *t3 = smaug_read_csv_mem(csv3, strlen(csv3), &o);
    CHECK(t3 && !t3->error,               "decimal ,: campo >64 chars sem erro de parse");
    CHECK(t3->columns[0].str != NULL,     "decimal ,: número longo demais vira string (:104)");
    smaug_table_free(t3);
    (void)longnum;
}

/* H.5.b — roundtrip: escrever com decimal ',' e reler */
static void test_csv_decimal_roundtrip(void) {
    const char *csv = "v\n3,25\n";
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.sep = ';'; o.decimal = ',';
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), &o);
    CHECK(t && !t->error,                 "roundtrip: read ok");
    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    wo.sep = ';'; wo.decimal = ',';
    size_t len; char *out = smaug_write_csv_mem(t, &wo, &len, NULL);
    CHECK(out != NULL,                    "roundtrip: write ok");
    CHECK(strstr(out, "3,25") != NULL,    "roundtrip: emite 3,25 com vírgula");
    CHECK(strstr(out, "3.25") == NULL,    "roundtrip: não emite ponto");
    free(out);
    smaug_table_free(t);
}

/* H.5.c — sep == decimal → erro orientado (read) e NULL (write) */
static void test_csv_sep_equals_decimal(void) {
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.sep = ','; o.decimal = ',';
    smaug_table_t *t = smaug_read_csv_mem("a,b\n1,2\n", 8, &o);
    CHECK(t && t->error != NULL,          "sep==decimal: erro no read");
    CHECK(strstr(t->error, "decimal") != NULL, "sep==decimal: mensagem orienta");
    smaug_table_free(t);

    /* write: sep==decimal → NULL, e agora a causa é comunicada (12.30). Antes o
       write só devolvia NULL — assimétrico com o read acima, que já orientava
       via t->error. Agora err_out espelha esse papel. */
    const char *csv = "v\n1.5\n";
    smaug_table_t *t2 = smaug_read_csv_mem(csv, strlen(csv), NULL);
    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    wo.sep = ';'; wo.decimal = ';';
    size_t len; char *werr = NULL;
    char *out = smaug_write_csv_mem(t2, &wo, &len, &werr);
    CHECK(out == NULL,                    "sep==decimal: write retorna NULL");
    CHECK(werr != NULL,                   "sep==decimal: write comunica a causa (12.30)");
    CHECK(werr && strstr(werr, "decimal") != NULL, "sep==decimal: mensagem orienta (12.30)");
    smaug_free(werr);
    /* err_out == NULL é aceitável (caller sem interesse na causa) */
    char *out2 = smaug_write_csv_mem(t2, &wo, &len, NULL);
    CHECK(out2 == NULL,                   "sep==decimal: err_out NULL não crasha (12.30)");
    smaug_table_free(t2);
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
       "N/A", "NULL". Linhas completamente vazias são PULADAS pelo parser
       (comportamento documentado). Para testar célula vazia, usamos dois
       campos separados por vírgula.

       "nan"/"NaN" NÃO são NA (mudança deliberada, item 12.21): NaN é valor
       IEEE 754, ausência vive no null_mask. Ver test_csv_nonfinite_values. */
    const char *csv = "v,x\n,1\nNA,2\nnull,3\nN/A,4\nNULL,5\n1,6\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,      "NA padrão: sem erro");
    CHECK(t->nrows == 6,       "NA padrão: 6 linhas");
    /* coluna v: todos NA exceto última */
    for (size_t r = 0; r < 5; r++)
        CHECK(col_is_null(t, 0, r), "NA padrão: linha NA");
    CHECK(!col_is_null(t, 0, 5),    "NA padrão: linha 6 não é NA");
    /* coluna x: nenhum NA */
    for (size_t r = 0; r < 6; r++)
        CHECK(!col_is_null(t, 1, r), "NA padrão: col x sem NA");
    smaug_table_free(t);
}

static void test_csv_nonfinite_values(void) {
    /* 12.21: não-finitos são VALORES, não ausência. Todas as grafias que o
       strtod aceita (case-insensitive) caem no mesmo destino — antes "nan"/
       "NaN" viravam NA por estarem no BUILTIN_NA enquanto "NAN" escapava para
       o strtod e virava valor: o destino do dado dependia da caixa. */
    const char *csv = "v,x\nnan,1\nNaN,2\nNAN,3\ninf,4\nInfinity,5\n-inf,6\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,               "não-finito: sem erro");
    CHECK(t->nrows == 6,                "não-finito: 6 linhas");
    CHECK(t->columns[0].f64 != NULL,    "não-finito: coluna inferida float64");
    for (size_t r = 0; r < 6; r++)
        CHECK(!col_is_null(t, 0, r),    "não-finito: é valor, não NA");
    smaug_status_t st;
    CHECK(isnan(smaug_f64_get(t->columns[0].f64, 0, &st)), "não-finito: 'nan' -> NaN");
    CHECK(isnan(smaug_f64_get(t->columns[0].f64, 1, &st)), "não-finito: 'NaN' -> NaN");
    CHECK(isnan(smaug_f64_get(t->columns[0].f64, 2, &st)), "não-finito: 'NAN' -> NaN (caixa não decide)");
    CHECK(isinf(smaug_f64_get(t->columns[0].f64, 3, &st)), "não-finito: 'inf' -> inf");
    CHECK(isinf(smaug_f64_get(t->columns[0].f64, 4, &st)), "não-finito: 'Infinity' -> inf");
    CHECK(smaug_f64_get(t->columns[0].f64, 5, &st) < 0,    "não-finito: '-inf' -> -inf");
    smaug_table_free(t);

    /* na_values explícito ainda permite tratar "nan" como ausência (compat com
       CSV de terceiros onde "nan" significa missing). */
    const char *na_vals[] = {"nan"};
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.na_values = na_vals;
    o.na_count  = 1;
    const char *csv2 = "v,x\nnan,1\n2.5,2\n";
    smaug_table_t *t2 = smaug_read_csv_mem(csv2, strlen(csv2), &o);
    CHECK(t2 && !t2->error,          "na_values: sem erro");
    CHECK(col_is_null(t2, 0, 0),     "na_values={'nan'}: 'nan' vira NA (opt-in)");
    CHECK(!col_is_null(t2, 0, 1),    "na_values={'nan'}: 2.5 segue valor");
    smaug_table_free(t2);
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
    /* valores: o '1' e o '3' (que pareciam int) viraram float corretamente */
    CHECK(fabs(get_f64(t, 0, 0) - 1.0) < 1e-9, "misto: linha int 1 → 1.0");
    CHECK(fabs(get_f64(t, 0, 1) - 2.5) < 1e-9, "misto: linha float 2.5");
    CHECK(fabs(get_f64(t, 0, 2) - 3.0) < 1e-9, "misto: linha int 3 → 3.0");
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
    /* todos os valores devem ser NA de fato */
    for (size_t r = 0; r < t->nrows; r++)
        CHECK(col_is_null(t, 0, r), "col toda NA: cada célula é NA");
    smaug_table_free(t);
}

static void test_csv_infer_bool_mixed_with_string(void) {
    /* bool + string não-bool → string */
    const char *csv = "v\ntrue\nhello\nfalse\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error, "bool+str: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"string") == 0, "bool+str: dtype string");
    /* o "true"/"false" devem virar texto literal, não bool */
    size_t n; const char *s0 = get_str(t, 0, 0, &n);
    CHECK(s0 && n == 4 && strncmp(s0, "true", 4) == 0,  "bool+str: 'true' preservado como texto");
    const char *s1 = get_str(t, 0, 1, &n);
    CHECK(s1 && n == 5 && strncmp(s1, "hello", 5) == 0, "bool+str: 'hello' preservado");
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
    CHECK(get_i64(t, 0, 0) == 1,  "CRLF EOF: v[0]=1 (\\r não entrou no valor)");
    smaug_table_free(t);
    /* \r sem \n no último byte */
    const char *csv2 = "v\n1\r";
    smaug_table_t *t2 = smaug_read_csv_mem(csv2, strlen(csv2), NULL);
    CHECK(t2 && !t2->error,       "CR EOF: sem erro");
    CHECK(t2->nrows == 1,         "CR EOF: 1 linha");
    CHECK(get_i64(t2, 0, 0) == 1, "CR EOF: v[0]=1 (\\r final tratado)");
    smaug_table_free(t2);
}

/* csv.c:137 — PUSH em campo sem aspas > 32 bytes (força realloc no macro) */
static void test_csv_long_unquoted_field(void) {
    const char *csv = "v\nabcdefghijklmnopqrstuvwxyzABCDEFGH\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,         "long field: sem erro");
    CHECK(t->nrows == 1,          "long field: 1 linha");
    size_t n; get_str(t, 0, 0, &n);
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

static void test_csv_opts_zero_sep_quote(void) {
    /* opts.sep/opts.quote == 0: a struct opts não é opaca — qualquer caller
     * em C pode pegar os defaults e zerar um campo (ou montar a struct na
     * mão sem inicializar). O guard "sep ? sep : ','" existe exatamente pra
     * isso; não é inalcançável, só não tinha caller adversarial testando. */
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.sep = 0;
    const char *csv = "a,b\n1,2\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), &o);
    CHECK(t && !t->error,        "sep=0: cai pro default ',' — sem erro");
    CHECK(t->ncols == 2,         "sep=0: 2 colunas (separou por vírgula)");
    CHECK(get_i64(t, 1, 0) == 2, "sep=0: b[0]=2");
    smaug_table_free(t);

    smaug_csv_opts_t o2 = smaug_csv_default_opts();
    o2.quote = 0;
    const char *csv2 = "a\n\"x\"\n";
    smaug_table_t *t2 = smaug_read_csv_mem(csv2, strlen(csv2), &o2);
    CHECK(t2 && !t2->error,      "quote=0: cai pro default '\"' — sem erro");
    size_t n; const char *s = get_str(t2, 0, 0, &n);
    CHECK(s && n == 1 && s[0] == 'x', "quote=0: aspas reconhecidas, campo='x'");
    smaug_table_free(t2);
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
    char *out = smaug_write_csv_mem(&t, &wo, &len, NULL);
    CHECK(out != NULL,                         "write NaN: retorna buffer");
    CHECK(strstr(out, "nan") != NULL,          "write NaN: contém 'nan'");
    free(out);
    smaug_f64_free(s);
}

static void test_csv_write_opts_zero_sep_quote(void) {
    /* mesmo guard do lado da escrita (linhas 427/428): opts.sep/opts.quote
     * podem chegar zerados de um caller em C que monta a struct na mão. */
    smaug_series_i64_t *s = smaug_i64_create(1);
    smaug_i64_set(s, 0, 1);
    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name = "a"; col.dtype = "int64"; col.i64 = s;
    t.columns = &col; t.ncols = 1; t.nrows = 1;

    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    wo.sep = 0; wo.quote = 0;
    size_t len;
    char *out = smaug_write_csv_mem(&t, &wo, &len, NULL);
    CHECK(out != NULL,             "write sep/quote=0: retorna buffer");
    CHECK(strstr(out, "a\n1\n") != NULL, "write sep/quote=0: cai pro default ','/'\"'");
    free(out);
    smaug_i64_free(s);
}

static void test_csv_write_large_field(void) {
    /* campo único > 8192 bytes força o wbuf a dobrar a capacidade mais de
     * uma vez numa só chamada de wbuf_push (cap começa em 4096; precisa
     * passar por 8192 até cobrir o campo) — cobre o loop `while` de
     * csv.c:400, que um único dobramento nunca exercita. */
    size_t big_len = 10000;
    char *big = malloc(big_len + 1);
    assert(big);
    memset(big, 'x', big_len);
    big[big_len] = '\0';

    smaug_series_str_t *s = smaug_str_create(1);
    smaug_str_set(s, 0, big, big_len);

    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name = "v"; col.dtype = "string"; col.str = s;
    t.columns = &col; t.ncols = 1; t.nrows = 1;

    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    size_t len;
    char *out = smaug_write_csv_mem(&t, &wo, &len, NULL);
    CHECK(out != NULL,        "write campo grande: retorna buffer");
    CHECK(len > big_len,      "write campo grande: buffer cresceu além do campo (header+\\n)");
    /* integridade: o campo de 10000 'x' precisa sair COMPLETO e sem corrupção
     * no meio (o ponto do teste é o crescimento do wbuf — se ele corromper
     * durante um realloc, o tamanho ainda baterá mas o conteúdo não). */
    char *body = strchr(out, '\n');           /* pula o header "v\n" */
    CHECK(body != NULL,       "write campo grande: tem corpo após header");
    body++;                                    /* primeiro byte do campo */
    size_t run = strspn(body, "x");            /* conta 'x' consecutivos */
    CHECK(run == big_len,     "write campo grande: 10000 'x' contíguos e íntegros");
    free(out);
    free(big);
    smaug_str_free(s);
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
    char *out = smaug_write_csv_mem(&t, &wo, &len, NULL);
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
    char *out = smaug_write_csv_mem(&t, &wo, &len, NULL);
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
    char *out = smaug_write_csv_mem(&t, &wo, &len, NULL);
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
    char path[1024];
    tmp_path(path, sizeof(path), "smaug_test_c.csv");
    int rc = smaug_write_csv(path, &t, &wo);
    CHECK(rc == 0, "write file: sucesso");

    /* ler de volta e verificar */
    smaug_table_t *t2 = smaug_read_csv(path, NULL);
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
    /* o 1 (que era int) precisa ter virado 1.0 no float64 */
    CHECK(fabs(get_f64(t, 0, 0) - 1.0) < 1e-9, "JSON int+float: int 1 → 1.0");
    CHECK(fabs(get_f64(t, 0, 1) - 2.5) < 1e-9, "JSON int+float: float 2.5");
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

static void test_json_short_record(void) {
    /* registro heterogêneo: 2o objeto é totalmente vazio ({}), ausente em
     * TODAS as 4 colunas — registro com só "i" não bastava: a própria
     * coluna "i" (int64) nunca ficava ausente, deixando o ramo !v
     * (json.c:426) descoberto especificamente pra DT_I64. JSON heterogêneo
     * é caso NORMAL (campo opcional ausente em alguns registros), não uma
     * exceção rara — campos faltando viram NA em todas as 4 famílias. */
    const char *j = "[{\"i\":1,\"f\":1.5,\"b\":true,\"s\":\"hello\"},{}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error,        "JSON registro curto: sem erro");
    CHECK(t->ncols == 4,         "JSON registro curto: 4 colunas (do 1o registro)");
    CHECK(t->nrows == 2,         "JSON registro curto: 2 linhas");
    CHECK(col_is_null(t, 0, 1),  "JSON registro curto: i[1]=NA (ausente, {} vazio)");
    CHECK(col_is_null(t, 1, 1),  "JSON registro curto: f[1]=NA (ausente)");
    CHECK(col_is_null(t, 2, 1),  "JSON registro curto: b[1]=NA (ausente)");
    CHECK(col_is_null(t, 3, 1),  "JSON registro curto: s[1]=NA (ausente)");
    /* linha 0 — todos presentes, confirma que não regrediu */
    CHECK(!col_is_null(t, 0, 0), "JSON registro curto: i[0] presente");
    CHECK(!col_is_null(t, 1, 0), "JSON registro curto: f[0] presente");
    CHECK(!col_is_null(t, 2, 0), "JSON registro curto: b[0] presente");
    CHECK(!col_is_null(t, 3, 0), "JSON registro curto: s[0] presente");
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
    char *out = smaug_write_json_mem(&t, &wo, &len, NULL);
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
    char *out = smaug_write_json_mem(&t, &wo, &len, NULL);
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
    char *out = smaug_write_json_mem(t, &wo, &len, NULL);
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
    char path[1024];
    tmp_path(path, sizeof(path), "smaug_test_c.json");
    int rc = smaug_write_json(path, t, &wo);
    CHECK(rc == 0, "JSON write file: sucesso");

    smaug_table_t *t2 = smaug_read_json(path);
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
    char *out = smaug_write_csv_mem(t, &wo, &len, NULL);
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
    char *out = smaug_write_json_mem(t, &wo, &len, NULL);
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

static void test_csv_na_custom_empty_field(void) {
    /* na_values customizado SEM "" — campo vazio deixa de ser NA por
     * definição e chega em try_i64/try_f64 como string vazia de verdade
     * (cobre o ramo !*s, nunca alcançado pelo default que trata "" como NA
     * antes mesmo de chamar try_i64/try_f64). */
    const char *nav[] = {"N/D"};
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.na_values = nav;
    o.na_count  = 1;
    const char *csv = "v,w\nN/D,5\n,7\n1,8\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), &o);
    CHECK(t && !t->error,            "na custom sem vazio: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"string") == 0,
                                      "na custom sem vazio: v vira string (\"\" não parseia)");
    CHECK(col_is_null(t, 0, 0),      "na custom sem vazio: N/D → null");
    CHECK(!col_is_null(t, 0, 1),     "na custom sem vazio: \"\" não é NA (não está na lista)");
    size_t n; const char *s = get_str(t, 0, 1, &n);
    CHECK(s && n == 0,               "na custom sem vazio: campo vazio vira string vazia, não null");
    smaug_table_free(t);
}

static void test_csv_numeric_overflow(void) {
    /* valor que excede int64 (errno=ERANGE em strtoll) mas cabe em double —
     * cobre o ramo errno de try_i64 (linha 84), que difere do ramo "sobra
     * lixo" (*end != '\0') já coberto por colunas de string comum. */
    const char *csv = "v\n99999999999999999999\n1.5\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,         "overflow i64: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"float64") == 0,
                                   "overflow i64: vira float64 (i64 falha por overflow, f64 aceita)");
    smaug_table_free(t);
}

static void test_csv_float_overflow(void) {
    /* valor que excede DBL_MAX (~1.8e308) — strtod retorna HUGE_VAL e seta
     * errno=ERANGE. Único jeito de exercitar o ramo errno de try_f64;
     * o ramo "sobra lixo" já é coberto por qualquer string comum. */
    const char *csv = "v\n1e400\n1.5\n";
    smaug_table_t *t = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(t && !t->error,         "overflow f64: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"string") == 0,
                                   "overflow f64: 1e400 falha em f64 (overflow) → coluna vira string");
    smaug_table_free(t);
}

/* Contraparte de LEITURA do teste de fronteira abaixo. Achado 2026-07-28: a
   escrita validava e era testada; a leitura nao fazia nem uma coisa nem outra,
   e read_csv_mem(NULL, 10) / read_json_mem(NULL, 10) SEGFALTAVAM. Assimetria
   dentro do mesmo modulo. */
static void test_read_mem_null_args(void) {
    /* buf NULL com len > 0 e chamada invalida -> NULL, nao crash */
    CHECK(smaug_read_csv_mem(NULL, 10, NULL) == NULL,
          "read_csv_mem: buf=NULL com len>0 retorna NULL");
    CHECK(smaug_read_json_mem(NULL, 10) == NULL,
          "read_json_mem: buf=NULL com len>0 retorna NULL");

    /* buf NULL com len == 0 e entrada VAZIA legitima, nao erro -- a guarda nao
       pode ser `if (!buf)`, senao quebraria este caso */
    smaug_table_t *t = smaug_read_json_mem(NULL, 0);
    CHECK(t != NULL, "read_json_mem: buf=NULL com len=0 e entrada vazia valida");
    if (t) smaug_table_free(t);

    /* caminho normal segue funcionando */
    const char *csv = "a,b\n1,2\n";
    smaug_table_t *tc = smaug_read_csv_mem(csv, strlen(csv), NULL);
    CHECK(tc != NULL && tc->ncols == 2, "read_csv_mem: caminho normal intacto");
    if (tc) smaug_table_free(tc);
}

static void test_csv_write_null_args(void) {
    /* smaug_write_csv_mem(NULL,...) e (t, NULL, ...) — guards de fronteira
     * pública (linhas 424/426), nunca testados com argumento NULL real. */
    size_t len;
    char *out1 = smaug_write_csv_mem(NULL, NULL, &len, NULL);
    CHECK(out1 == NULL, "write_csv_mem: t=NULL retorna NULL");

    smaug_series_i64_t *s = smaug_i64_create(1);
    smaug_i64_set(s, 0, 1);
    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name = "v"; col.dtype = "int64"; col.i64 = s;
    t.columns = &col; t.ncols = 1; t.nrows = 1;

    char *out2 = smaug_write_csv_mem(&t, NULL, &len, NULL);
    CHECK(out2 != NULL, "write_csv_mem: opts=NULL usa default, sem erro");
    free(out2);

    char *out3 = smaug_write_csv_mem(&t, NULL, NULL, NULL);
    CHECK(out3 == NULL, "write_csv_mem: out_len=NULL retorna NULL");

    smaug_i64_free(s);
}

static void test_json_str_mixed_types(void) {
    /* coluna que mistura int/float/bool/string força dtype=string (catch-all
     * heterogêneo) — diferente das colunas i64/f64/bool, aqui o formatador
     * de fallback (tmp/snprintf) É alcançável de verdade: cada valor não-
     * string precisa ser formatado como texto na hora de preencher. */
    const char *j = "[{\"v\":1},{\"v\":2.5},{\"v\":true},{\"v\":\"texto\"},{\"v\":false}]";
    smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
    CHECK(t && !t->error,         "JSON str misto: sem erro");
    CHECK(strcmp(t->columns[0].dtype,"string") == 0, "JSON str misto: dtype string");
    size_t n; const char *s;
    s = get_str(t, 0, 0, &n); CHECK(s && n==1 && s[0]=='1',        "JSON str misto: int → \"1\"");
    s = get_str(t, 0, 1, &n); CHECK(s && strncmp(s,"2.5",3)==0,    "JSON str misto: float → \"2.5\"");
    s = get_str(t, 0, 2, &n); CHECK(s && n==4 && strncmp(s,"true",4)==0,  "JSON str misto: bool true → \"true\"");
    s = get_str(t, 0, 3, &n); CHECK(s && n==5 && strncmp(s,"texto",5)==0, "JSON str misto: string passa direto");
    s = get_str(t, 0, 4, &n); CHECK(s && n==5 && strncmp(s,"false",5)==0, "JSON str misto: bool false → \"false\"");
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
    /* --- BMP: ASCII (U+0041 = 'A') --- */
    {
        const char *j = "[{\"v\":\"\\u0041\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && !t->error, "JSON unicode ASCII: sem erro");
        size_t n; const char *s = get_str(t, 0, 0, &n);
        CHECK(s && n == 1,    "JSON unicode ASCII: 1 byte");
        CHECK(s[0] == 'A',    "JSON unicode ASCII: U+0041 = 'A'");
        smaug_table_free(t);
    }
    /* --- BMP: 2-byte UTF-8 (U+00E9 = 'e' com acento agudo) --- */
    {
        const char *j = "[{\"v\":\"caf\\u00e9\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && !t->error, "JSON unicode 2-byte: sem erro");
        size_t n; const char *s = get_str(t, 0, 0, &n);
        /* UTF-8 de e-agudo = 0xC3 0xA9; "caf" + 2 bytes = 5 bytes total */
        CHECK(s && n == 5,    "JSON unicode 2-byte: 5 bytes");
        CHECK((unsigned char)s[3] == 0xC3 && (unsigned char)s[4] == 0xA9,
              "JSON unicode 2-byte: UTF-8 correto para U+00E9");
        smaug_table_free(t);
    }
    /* --- BMP: 3-byte UTF-8 (U+4E2D = caractere CJK) --- */
    {
        const char *j = "[{\"v\":\"\\u4e2d\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && !t->error, "JSON unicode 3-byte: sem erro");
        size_t n; const char *s = get_str(t, 0, 0, &n);
        /* UTF-8 de U+4E2D = 0xE4 0xB8 0xAD */
        CHECK(s && n == 3,                         "JSON unicode 3-byte: 3 bytes");
        CHECK((unsigned char)s[0] == 0xE4 &&
              (unsigned char)s[1] == 0xB8 &&
              (unsigned char)s[2] == 0xAD,         "JSON unicode 3-byte: UTF-8 correto para U+4E2D");
        smaug_table_free(t);
    }
    /* --- Surrogate pair (U+1F600) → 4-byte UTF-8 --- */
    {
        /* \uD83D\uDE00 = U+1F600 → UTF-8: 0xF0 0x9F 0x98 0x80 */
        const char *j = "[{\"v\":\"\\uD83D\\uDE00\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && !t->error, "JSON unicode surrogate pair: sem erro");
        size_t n; const char *s = get_str(t, 0, 0, &n);
        CHECK(s && n == 4,                         "JSON unicode surrogate pair: 4 bytes");
        CHECK((unsigned char)s[0] == 0xF0 &&
              (unsigned char)s[1] == 0x9F &&
              (unsigned char)s[2] == 0x98 &&
              (unsigned char)s[3] == 0x80,         "JSON unicode surrogate pair: UTF-8 correto para U+1F600");
        smaug_table_free(t);
    }
    /* --- Surrogate isolado (high) → erro --- */
    {
        const char *j = "[{\"v\":\"\\uD83D\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && t->error,  "JSON unicode high surrogate isolado: erro");
        smaug_table_free(t);
    }
    /* --- Surrogate isolado (low) → erro --- */
    {
        const char *j = "[{\"v\":\"\\uDE00\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && t->error,  "JSON unicode low surrogate isolado: erro");
        smaug_table_free(t);
    }
    /* --- Hex inválido em \uXXXX → erro --- */
    {
        const char *j = "[{\"v\":\"\\uXXXX\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && t->error,  "JSON unicode hex invalido: erro");
        smaug_table_free(t);
    }
    /* --- \uXXXX dentro de string mista --- */
    {
        /* "ol\u00e1 mundo" = "ol" + a-agudo (2 bytes) + " mundo" = 10 bytes */
        const char *j = "[{\"v\":\"ol\\u00e1 mundo\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && !t->error, "JSON unicode misto: sem erro");
        size_t n; const char *s = get_str(t, 0, 0, &n);
        CHECK(s && n == 10,   "JSON unicode misto: 10 bytes");
        CHECK(s[0]=='o' && s[1]=='l', "JSON unicode misto: prefixo correto");
        CHECK((unsigned char)s[2]==0xC3 && (unsigned char)s[3]==0xA1,
              "JSON unicode misto: a-agudo U+00E1 correto");
        smaug_table_free(t);
    }
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
    char *out = smaug_write_json_mem(&t, &wo, &len, NULL);
    CHECK(out != NULL, "JSON \\b\\f: retorna buffer");
    /* \b e \f não têm escape explícito no writer — viram \u0008 e \u000c */
    CHECK(strstr(out, "\\u0008") != NULL || strstr(out, "\\b") != NULL,
          "JSON \\b: escapado");
    free(out);
    smaug_str_free(s);
}

static void test_json_lexer_edges(void) {
    /* --- \r e \r\n como whitespace (linha 45: \r branch nunca exercitado) --- */
    {
        const char *j = "[\r{\"v\":1}\r\n]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && !t->error,         "JSON \\r whitespace: sem erro");
        CHECK(get_i64(t, 0, 0) == 1, "JSON \\r whitespace: v=1");
        smaug_table_free(t);
    }
    /* --- expoente com sinal + e letra E maiúscula (linha 212 branches) --- */
    {
        const char *j = "[{\"v\":1.5E+3}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && !t->error,                        "JSON E+: sem erro");
        CHECK(fabs(get_f64(t, 0, 0) - 1500.0) < 1.0,"JSON E+: 1.5E+3=1500");
        smaug_table_free(t);
    }
    /* --- palavras-chave com prefixo parcial → TOK_ERROR (linhas 194/198/202) --- */
    {
        const char *cases[] = {
            "[{\"v\":tru}]", "[{\"v\":fals}]", "[{\"v\":nul}]", NULL
        };
        for (int i = 0; cases[i]; i++) {
            smaug_table_t *t = smaug_read_json_mem(cases[i], strlen(cases[i]));
            CHECK(t && t->error, "JSON keyword parcial: erro esperado");
            smaug_table_free(t);
        }
    }
    /* --- escapes do reader: \/ \r \b \f (switch linha 156) --- */
    {
        const char *j = "[{\"v\":\"\\/\\r\\b\\f\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && !t->error,  "JSON escapes \\/\\r\\b\\f: sem erro");
        size_t n; const char *s = get_str(t, 0, 0, &n);
        CHECK(s && n == 4,     "JSON escapes: 4 bytes no campo");
        CHECK(s[0] == '/',     "JSON escapes: \\/ → '/'");
        CHECK(s[1] == '\r',    "JSON escapes: \\r → carriage return");
        CHECK(s[2] == '\b',    "JSON escapes: \\b → backspace");
        CHECK(s[3] == '\f',    "JSON escapes: \\f → form feed");
        smaug_table_free(t);
    }
    /* --- elemento não-objeto no array (linhas 324-325) --- */
    {
        const char *j = "[1, 2, 3]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && t->error,   "JSON array não-objeto: erro esperado");
        smaug_table_free(t);
    }
    /* --- coluna toda-nula (dtypes[c] == DT_UNKNOWN, linha 396) --- */
    {
        const char *j = "[{\"v\":null},{\"v\":null}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && !t->error,  "JSON coluna toda-nula: sem erro");
        CHECK(strcmp(t->columns[0].dtype,"string") == 0,
                               "JSON coluna toda-nula: DT_UNKNOWN → string");
        CHECK(col_is_null(t, 0, 0), "JSON coluna toda-nula: v[0]=NA");
        CHECK(col_is_null(t, 0, 1), "JSON coluna toda-nula: v[1]=NA");
        smaug_table_free(t);
    }
}

static void test_json_surrogate_errors_extended(void) {
    /* --- high surrogate seguido de \u com hex inválido (linha 130: cp2 < 0) --- */
    {
        const char *j = "[{\"v\":\"\\uD83D\\uXXXX\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && t->error, "JSON surrogate+hex_invalido: erro esperado");
        smaug_table_free(t);
    }
    /* --- dois high surrogates seguidos (linha 132: ucp2 < 0xDC00) --- */
    {
        const char *j = "[{\"v\":\"\\uD83D\\uD800\"}]";
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && t->error, "JSON high+high surrogate: erro esperado");
        smaug_table_free(t);
    }
    /* --- \uXXXX truncado no final do buffer (linha 53: pos+4 > len) --- */
    {
        const char *j = "[{\"v\":\"\\u00\"}]"; /* só 2 dígitos hex */
        smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
        CHECK(t && t->error, "JSON \\uXXXX truncado: erro esperado");
        smaug_table_free(t);
    }
}

static void test_json_unicode_realloc(void) {
    /* 25 codepoints BMP 3-byte (U+4E2D = 中) = 75 bytes > cap inicial (64)
     * força o realloc do buffer de string (linha 145/146) numa única string.
     * Usa JSON com 25 \u4e2d consecutivos. */
    char j[512];
    int pos = sprintf(j, "[{\"v\":\"");
    for (int i = 0; i < 25; i++) pos += sprintf(j+pos, "\\u4e2d");
    pos += sprintf(j+pos, "\"}]");

    smaug_table_t *t = smaug_read_json_mem(j, (size_t)pos);
    CHECK(t && !t->error,        "JSON unicode realloc: sem erro");
    size_t n; const char *s = get_str(t, 0, 0, &n);
    CHECK(s && n == 75,          "JSON unicode realloc: 25×3 bytes = 75");
    /* primeiro e último codepoint: 0xE4 0xB8 0xAD */
    CHECK((unsigned char)s[0] == 0xE4 &&
          (unsigned char)s[1] == 0xB8 &&
          (unsigned char)s[2] == 0xAD,  "JSON unicode realloc: primeiro codepoint correto");
    smaug_table_free(t);
}

static void test_json_write_opts_null(void) {
    /* smaug_write_json_mem(NULL, ...) e (t, ..., NULL) — guards de fronteira
     * (linha 549: !t || !out_len). */
    size_t len;
    char *out1 = smaug_write_json_mem(NULL, NULL, &len, NULL);
    CHECK(out1 == NULL, "JSON write: t=NULL retorna NULL");

    smaug_series_i64_t *s = smaug_i64_create(1);
    smaug_i64_set(s, 0, 1);
    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name = "v"; col.dtype = "int64"; col.i64 = s;
    t.columns = &col; t.ncols = 1; t.nrows = 1;

    smaug_json_write_opts_t wo = {0};
    char *out2 = smaug_write_json_mem(&t, &wo, NULL, NULL);
    CHECK(out2 == NULL, "JSON write: out_len=NULL retorna NULL");
    smaug_i64_free(s);
}

static void test_json_write_pretty_rich(void) {
    /* pretty=1 com multi-coluna e nulls — exercita os branches de nl/ind/ind2
     * e os separadores de colunas/linhas (linhas 557–605) que a versão simples
     * não alcança porque tem só 1 coluna sem null. */
    smaug_series_i64_t *si = smaug_i64_create(2);
    smaug_series_str_t *ss = smaug_str_create(2);
    smaug_i64_set(si, 0, 1);  smaug_i64_set_null(si, 1);
    smaug_str_set(ss, 0, "a", 1); smaug_str_set_null(ss, 1);
    smaug_column_t cols[2] = {0};
    cols[0].name = "i"; cols[0].dtype = "int64";  cols[0].i64 = si;
    cols[1].name = "s"; cols[1].dtype = "string"; cols[1].str = ss;
    smaug_table_t t = {0};
    t.columns = cols; t.ncols = 2; t.nrows = 2;

    smaug_json_write_opts_t wo = {.pretty = 1};
    size_t len;
    char *out = smaug_write_json_mem(&t, &wo, &len, NULL);
    CHECK(out != NULL,               "JSON write pretty rich: retorna buffer");
    CHECK(strstr(out, "\n") != NULL, "JSON write pretty rich: tem newline");
    CHECK(strstr(out, "null") != NULL, "JSON write pretty rich: null aparece");
    free(out);
    smaug_i64_free(si); smaug_str_free(ss);
}

static void test_json_parse_errors(void) {
    /* chave sem ':' depois (linha 281) */
    { const char *j = "[{\"v\" 1}]";
      smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
      CHECK(t && t->error, "JSON sem ':': erro esperado");
      smaug_table_free(t); }

    /* dois campos sem ',' entre eles (linha 299) */
    { const char *j = "[{\"v\":1 \"w\":2}]";
      smaug_table_t *t = smaug_read_json_mem(j, strlen(j));
      CHECK(t && t->error, "JSON sem ',': erro esperado");
      smaug_table_free(t); }
}

static void test_json_write_large_string(void) {
    /* string de 10k chars → força o wbuf do writer a dobrar a capacidade
     * mais de uma vez (linha 521: while ncap <= b->len+n cap*=2). */
    size_t big_len = 10000;
    char *big = malloc(big_len + 1);
    assert(big);
    memset(big, 'x', big_len);
    big[big_len] = '\0';

    smaug_series_str_t *s = smaug_str_create(1);
    smaug_str_set(s, 0, big, big_len);
    smaug_table_t t = {0};
    smaug_column_t col = {0};
    col.name = "v"; col.dtype = "string"; col.str = s;
    t.columns = &col; t.ncols = 1; t.nrows = 1;

    smaug_json_write_opts_t wo = {0};
    size_t len;
    char *out = smaug_write_json_mem(&t, &wo, &len, NULL);
    CHECK(out != NULL,    "JSON write large: retorna buffer");
    CHECK(len > big_len,  "JSON write large: buffer maior que o campo (overhead JSON)");
    /* integridade: relê o JSON e confirma que a string de 10000 'x' voltou
     * COMPLETA (um realloc corrompido daria tamanho certo mas conteúdo errado). */
    smaug_table_t *t2 = smaug_read_json_mem(out, len);
    CHECK(t2 && !t2->error,           "JSON write large: relê sem erro");
    size_t n; const char *s2 = get_str(t2, 0, 0, &n);
    CHECK(s2 && n == big_len,         "JSON write large: 10000 bytes relidos");
    /* a string tem comprimento explícito n (não é null-terminada) — verificar
     * dentro do limite, sem strspn que leria além do buffer. */
    int all_x = (s2 != NULL);
    for (size_t i = 0; all_x && i < n; i++) if (s2[i] != 'x') all_x = 0;
    CHECK(all_x,                      "JSON write large: 10000 'x' íntegros");
    smaug_table_free(t2);
    free(out);
    free(big);
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
    test_csv_decimal_comma();
    test_csv_decimal_comma_rejects_dot();
    test_csv_decimal_roundtrip();
    test_csv_sep_equals_decimal();
    test_csv_quotes_rfc4180();
    test_csv_quotes_escaped();
    test_csv_quotes_unclosed();
    test_csv_newline_in_quoted_field();
    test_csv_na_values();
    test_csv_nonfinite_values();

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
    test_csv_opts_zero_sep_quote();
    test_csv_numeric_overflow();
    test_csv_float_overflow();

    /* CSV — writer */
    test_csv_write_nan();
    test_csv_write_opts_zero_sep_quote();
    test_csv_write_large_field();
    test_read_mem_null_args();
    test_csv_write_null_args();
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
    test_json_short_record();
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
    test_csv_na_custom_empty_field();

    /* JSON — variantes numéricas e escapes */
    test_json_negative_number();
    test_json_str_mixed_types();
    test_json_exponent_number();
    test_json_negative_exponent();
    test_json_unicode_escape();
    test_json_whitespace_variants();
    test_json_bf_escape();
    test_json_lexer_edges();
    test_json_surrogate_errors_extended();
    test_json_unicode_realloc();
    test_json_write_opts_null();
    test_json_write_pretty_rich();
    test_json_parse_errors();
    test_json_write_large_string();

    /* Roundtrips */
    test_csv_roundtrip_all_dtypes();
    test_json_roundtrip_all_dtypes();

    if (g_fail == 0)
        printf("PASS: test_io_c (%d checks)\n", g_ok);
    else
        printf("FAIL: %d/%d checks falharam\n", g_fail, g_ok + g_fail);

    return g_fail > 0 ? 1 : 0;
}
