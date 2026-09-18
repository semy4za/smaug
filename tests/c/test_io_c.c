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

static int passed_checks = 0;
static int failed_checks = 0;

#define CHECK(condition, message) do { \
    if (condition) { passed_checks++; } \
    else { fprintf(stderr, "FALHOU [%s:%d]: %s\n", __FILE__, __LINE__, message); failed_checks++; } \
} while(0)

#define CHECK_STR(actual_text, expected_text, message) \
    CHECK((actual_text) && strncmp((actual_text), (expected_text), strlen(expected_text)) == 0, message)

/* Diretório temporário portátil: respeita TMPDIR/TMP/TEMP (Windows usa TEMP),
 * com fallback "/tmp". Monta "<dir>/<name>" em buf. Usa '/' como separador,
 * aceito tanto pela CRT do Windows quanto pelo POSIX. */
static const char *temporary_file_path(char *buffer, size_t size, const char *name) {
    const char *text_value = getenv("TMPDIR");
    if (!text_value || !*text_value) text_value = getenv("TMP");
    if (!text_value || !*text_value) text_value = getenv("TEMP");
    if (!text_value || !*text_value) text_value = "/tmp";
    snprintf(buffer, size, "%s/%s", text_value, name);
    return buffer;
}

/* ===================================================================
   Helpers
   =================================================================== */

static int column_is_null(smaug_table_t *values, size_t column, size_t row) {
    smaug_status_t status;
    smaug_column_t *source_values = &values->columns[column];
    if (source_values->i64)     { smaug_i64_get(source_values->i64, row, &status);     return status == SMG_NULL_VALUE; }
    if (source_values->f64)     { smaug_f64_get(source_values->f64, row, &status);     return status == SMG_NULL_VALUE; }
    if (source_values->boolcol) { smaug_bool_get(source_values->boolcol, row, &status); return status == SMG_NULL_VALUE; }
    if (source_values->str)     { size_t element_count; const char *string_get_result = smaug_str_get(source_values->str, row, &element_count); return string_get_result == NULL; }
    return 1;
}

static int64_t get_int64(smaug_table_t *values, size_t column, size_t row) {
    smaug_status_t status;
    int64_t source_values = smaug_i64_get(values->columns[column].i64, row, &status);
    assert(status == SMG_OK);
    return source_values;
}

static double get_float64(smaug_table_t *values, size_t column, size_t row) {
    smaug_status_t status;
    double source_values = smaug_f64_get(values->columns[column].f64, row, &status);
    assert(status == SMG_OK);
    return source_values;
}

static uint8_t get_bool(smaug_table_t *values, size_t column, size_t row) {
    smaug_status_t status;
    uint8_t source_values = smaug_bool_get(values->columns[column].boolcol, row, &status);
    assert(status == SMG_OK);
    return source_values;
}

static const char *get_string(smaug_table_t *values, size_t column, size_t row, size_t *length) {
    return smaug_str_get(values->columns[column].str, row, length);
}

/* ===================================================================
   CSV — erros de entrada
   =================================================================== */

static void test_csv_empty(void) {
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem("", 0, NULL);
    CHECK(read_csv_memory_result != NULL,       "empty: retorna tabela");
    CHECK(read_csv_memory_result->error != NULL,"empty: tem mensagem de erro");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_only_blank_lines(void) {
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem("\n\n\n", 3, NULL);
    CHECK(read_csv_memory_result != NULL,       "blank lines: retorna tabela");
    CHECK(read_csv_memory_result->error != NULL,"blank lines: tem erro");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_only_header(void) {
    /* header sem dados → nrows=0, sem erro */
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem("a,b,c\n", 6, NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,  "só header: sem erro");
    CHECK(read_csv_memory_result->ncols == 3,   "só header: 3 colunas");
    CHECK(read_csv_memory_result->nrows == 0,   "só header: 0 linhas");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_file_not_found(void) {
    smaug_table_t *read_csv_result = smaug_read_csv("/caminho/inexistente/arquivo.csv", NULL);
    CHECK(read_csv_result != NULL,       "arquivo inexistente: retorna tabela");
    CHECK(read_csv_result->error != NULL,"arquivo inexistente: tem erro");
    smaug_table_free(read_csv_result);
}

static void test_csv_table_free_null(void) {
    smaug_table_free(NULL);  /* não deve crashar */
    passed_checks++;
}

/* ===================================================================
   CSV — variantes de formato
   =================================================================== */

static void test_csv_crlf(void) {
    /* CRLF como terminador de linha (Windows) */
    const char *text_value = "a,b\r\n1,2\r\n3,4\r\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,        "CRLF: sem erro");
    CHECK(read_csv_memory_result->nrows == 2,         "CRLF: 2 linhas");
    CHECK(get_int64(read_csv_memory_result, 0, 0) == 1,"CRLF: a[0]=1");
    CHECK(get_int64(read_csv_memory_result, 1, 1) == 4,"CRLF: b[1]=4");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_cr_only(void) {
    /* CR sem LF — menos comum mas válido */
    const char *text_value = "a,b\r1,2\r3,4\r";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,        "CR only: sem erro");
    CHECK(read_csv_memory_result->nrows == 2,         "CR only: 2 linhas");
    CHECK(get_int64(read_csv_memory_result, 0, 0) == 1,"CR only: a[0]=1");
    CHECK(get_int64(read_csv_memory_result, 1, 0) == 2,"CR only: b[0]=2");
    CHECK(get_int64(read_csv_memory_result, 0, 1) == 3,"CR only: a[1]=3");
    CHECK(get_int64(read_csv_memory_result, 1, 1) == 4,"CR only: b[1]=4");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_no_trailing_newline(void) {
    /* última linha sem \n */
    const char *text_value = "a,b\n1,2\n3,4";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,        "sem newline final: sem erro");
    CHECK(read_csv_memory_result->nrows == 2,         "sem newline final: 2 linhas");
    CHECK(get_int64(read_csv_memory_result, 1, 1) == 4,"sem newline final: b[1]=4");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_tab_sep(void) {
    const char *text_value = "a\tb\tc\n10\t20\t30\n";
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.sep = '\t';
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), &default_options_result);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,         "TSV: sem erro");
    CHECK(read_csv_memory_result->ncols == 3,          "TSV: 3 colunas");
    CHECK(get_int64(read_csv_memory_result, 2, 0) == 30,"TSV: c[0]=30");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_no_header(void) {
    const char *text_value = "1,2\n3,4\n";
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.header = 0;
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), &default_options_result);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,         "sem header: sem erro");
    CHECK(read_csv_memory_result->ncols == 2,          "sem header: 2 colunas");
    CHECK(read_csv_memory_result->nrows == 2,          "sem header: 2 linhas");
    CHECK(strcmp(read_csv_memory_result->columns[0].name, "col0") == 0, "sem header: nome col0");
    CHECK(get_int64(read_csv_memory_result, 0, 0) == 1, "sem header: col0[0]=1");
    smaug_table_free(read_csv_memory_result);
}

/* H.5.b — decimal customizado (CSV brasileiro: sep=';' decimal=',') */
static void test_csv_decimal_comma(void) {
    const char *text_value = "nome;valor\nproduto;34,12\noutro;5,5\n";
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.sep = ';'; default_options_result.decimal = ',';
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), &default_options_result);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,                 "decimal ,: sem erro");
    CHECK(read_csv_memory_result->ncols == 2,                  "decimal ,: 2 colunas");
    CHECK(read_csv_memory_result->columns[1].f64 != NULL,      "decimal ,: valor inferido float64");
    CHECK(get_float64(read_csv_memory_result, 1, 0) > 34.11 && get_float64(read_csv_memory_result, 1, 0) < 34.13, "decimal ,: 34,12 → 34.12");
    CHECK(get_float64(read_csv_memory_result, 1, 1) > 5.49  && get_float64(read_csv_memory_result, 1, 1) < 5.51,  "decimal ,: 5,5 → 5.5");
    smaug_table_free(read_csv_memory_result);
}

/* H.5.b — '.' literal com decimal ',' não é float válido (rigor preservado) */
static void test_csv_decimal_comma_rejects_dot(void) {
    const char *text_value = "nome;valor\nproduto;34.12\n";
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.sep = ';'; default_options_result.decimal = ',';
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), &default_options_result);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,                 "decimal ,: '.' literal sem erro de parse");
    CHECK(read_csv_memory_result->columns[1].str != NULL,      "decimal ,: '34.12' vira string (não float)");
    smaug_table_free(read_csv_memory_result);

    /* :112 — após trocar ',' por '.', a string ainda é lixo → rejeitada como float */
    const char *text_value_2 = "nome;valor\nx;12,3,4\noutro;5,6x\n";
    smaug_table_t *read_csv_memory_result_2 = smaug_read_csv_mem(text_value_2, strlen(text_value_2), &default_options_result);
    CHECK(read_csv_memory_result_2 && !read_csv_memory_result_2->error,               "decimal ,: lixo após troca sem erro de parse");
    CHECK(read_csv_memory_result_2->columns[1].str != NULL,     "decimal ,: '12,3,4' e '5,6x' viram string");
    smaug_table_free(read_csv_memory_result_2);

    /* :104 — campo numérico absurdamente longo (>=64 chars) → não-float, vira string */
    char longnum[80];
    longnum[0] = '\0';
    /* monta "1111...,11" com >64 chars, separador decimal ',' */
    char field[80];
    for (int row_index = 0; row_index < 70; row_index++) field[row_index] = '1';
    field[70] = ','; field[71] = '5'; field[72] = '\0';
    char source_values[160];
    snprintf(source_values, sizeof(source_values), "v\n%s\n", field);
    smaug_table_t *read_csv_memory_result_3 = smaug_read_csv_mem(source_values, strlen(source_values), &default_options_result);
    CHECK(read_csv_memory_result_3 && !read_csv_memory_result_3->error,               "decimal ,: campo >64 chars sem erro de parse");
    CHECK(read_csv_memory_result_3->columns[0].str != NULL,     "decimal ,: número longo demais vira string (:104)");
    smaug_table_free(read_csv_memory_result_3);
    (void)longnum;
}

/* H.5.b — roundtrip: escrever com decimal ',' e reler */
static void test_csv_decimal_roundtrip(void) {
    const char *text_value = "v\n3,25\n";
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.sep = ';'; default_options_result.decimal = ',';
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), &default_options_result);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,                 "roundtrip: read ok");
    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    write_default_options_result.sep = ';'; write_default_options_result.decimal = ',';
    size_t length; char *write_csv_memory_result = smaug_write_csv_mem(read_csv_memory_result, &write_default_options_result, &length, NULL);
    CHECK(write_csv_memory_result != NULL,                    "roundtrip: write ok");
    CHECK(strstr(write_csv_memory_result, "3,25") != NULL,    "roundtrip: emite 3,25 com vírgula");
    CHECK(strstr(write_csv_memory_result, "3.25") == NULL,    "roundtrip: não emite ponto");
    free(write_csv_memory_result);
    smaug_table_free(read_csv_memory_result);
}

/* H.5.c — sep == decimal → erro orientado (read) e NULL (write) */
static void test_csv_sep_equals_decimal(void) {
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.sep = ','; default_options_result.decimal = ',';
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem("a,b\n1,2\n", 8, &default_options_result);
    CHECK(read_csv_memory_result && read_csv_memory_result->error != NULL,          "sep==decimal: erro no read");
    CHECK(strstr(read_csv_memory_result->error, "decimal") != NULL, "sep==decimal: mensagem orienta");
    smaug_table_free(read_csv_memory_result);

    /* write: sep==decimal → NULL, e agora a causa é comunicada (12.30). Antes o
       write só devolvia NULL — assimétrico com o read acima, que já orientava
       via t->error. Agora err_out espelha esse papel. */
    const char *text_value = "v\n1.5\n";
    smaug_table_t *read_csv_memory_result_2 = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    write_default_options_result.sep = ';'; write_default_options_result.decimal = ';';
    size_t length; char *text_value_2 = NULL;
    char *write_csv_memory_result = smaug_write_csv_mem(read_csv_memory_result_2, &write_default_options_result, &length, &text_value_2);
    CHECK(write_csv_memory_result == NULL,                    "sep==decimal: write retorna NULL");
    CHECK(text_value_2 != NULL,                   "sep==decimal: write comunica a causa (12.30)");
    CHECK(text_value_2 && strstr(text_value_2, "decimal") != NULL, "sep==decimal: mensagem orienta (12.30)");
    smaug_free(text_value_2);
    /* err_out == NULL é aceitável (caller sem interesse na causa) */
    char *write_csv_memory_result_2 = smaug_write_csv_mem(read_csv_memory_result_2, &write_default_options_result, &length, NULL);
    CHECK(write_csv_memory_result_2 == NULL,                   "sep==decimal: err_out NULL não crasha (12.30)");
    smaug_table_free(read_csv_memory_result_2);
}

static void test_csv_quotes_rfc4180(void) {
    /* campo com sep dentro de aspas */
    const char *text_value = "nome,cidade\n\"Fulano, Jr.\",\"São Paulo\"\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error, "aspas RFC4180: sem erro");
    size_t element_count; const char *text_value_2 = get_string(read_csv_memory_result, 0, 0, &element_count);
    CHECK(text_value_2 && strncmp(text_value_2, "Fulano, Jr.", 11) == 0, "aspas: nome com vírgula");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_quotes_escaped(void) {
    /* aspas escapadas dentro de campo: "" → " */
    const char *text_value = "v\n\"val \"\"com\"\" aspas\"\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error, "aspas escapadas: sem erro");
    size_t element_count; const char *text_value_2 = get_string(read_csv_memory_result, 0, 0, &element_count);
    CHECK(text_value_2 && strncmp(text_value_2, "val \"com\" aspas", 15) == 0, "aspas escapadas: valor correto");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_quotes_unclosed(void) {
    /* aspas não fechadas — parser deve tolerar (trata como fim de buffer) */
    const char *text_value = "v\n\"abc\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result != NULL, "aspas não fechadas: retorna algo (sem crash)");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_newline_in_quoted_field(void) {
    /* newline dentro de campo entre aspas (RFC 4180 permite) */
    const char *text_value = "v\n\"linha1\nlinha2\"\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error, "newline em campo: sem erro");
    CHECK(read_csv_memory_result->nrows == 1,  "newline em campo: 1 linha");
    size_t element_count; const char *text_value_2 = get_string(read_csv_memory_result, 0, 0, &element_count);
    CHECK(text_value_2 && element_count == 13,   "newline em campo: comprimento correto (linha1\nlinha2 = 13 bytes)");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_null_values(void) {
    /* NA padrão: célula vazia (campo real, não linha vazia), "NA", "null",
       "N/A", "NULL". Linhas completamente vazias são PULADAS pelo parser
       (comportamento documentado). Para testar célula vazia, usamos dois
       campos separados por vírgula.

       "nan"/"NaN" NÃO são NA (mudança deliberada, item 12.21): NaN é valor
       IEEE 754, ausência vive no null_mask. Ver test_csv_nonfinite_values. */
    const char *text_value = "v,x\n,1\nNA,2\nnull,3\nN/A,4\nNULL,5\n1,6\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,      "NA padrão: sem erro");
    CHECK(read_csv_memory_result->nrows == 6,       "NA padrão: 6 linhas");
    /* coluna v: todos NA exceto última */
    for (size_t result = 0; result < 5; result++)
        CHECK(column_is_null(read_csv_memory_result, 0, result), "NA padrão: linha NA");
    CHECK(!column_is_null(read_csv_memory_result, 0, 5),    "NA padrão: linha 6 não é NA");
    /* coluna x: nenhum NA */
    for (size_t result = 0; result < 6; result++)
        CHECK(!column_is_null(read_csv_memory_result, 1, result), "NA padrão: col x sem NA");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_nonfinite_values(void) {
    /* 12.21: não-finitos são VALORES, não ausência. Todas as grafias que o
       strtod aceita (case-insensitive) caem no mesmo destino — antes "nan"/
       "NaN" viravam NA por estarem no BUILTIN_NA enquanto "NAN" escapava para
       o strtod e virava valor: o destino do dado dependia da caixa. */
    const char *text_value = "v,x\nnan,1\nNaN,2\nNAN,3\ninf,4\nInfinity,5\n-inf,6\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,               "não-finito: sem erro");
    CHECK(read_csv_memory_result->nrows == 6,                "não-finito: 6 linhas");
    CHECK(read_csv_memory_result->columns[0].f64 != NULL,    "não-finito: coluna inferida float64");
    for (size_t result = 0; result < 6; result++)
        CHECK(!column_is_null(read_csv_memory_result, 0, result),    "não-finito: é valor, não NA");
    smaug_status_t status;
    CHECK(isnan(smaug_f64_get(read_csv_memory_result->columns[0].f64, 0, &status)), "não-finito: 'nan' -> NaN");
    CHECK(isnan(smaug_f64_get(read_csv_memory_result->columns[0].f64, 1, &status)), "não-finito: 'NaN' -> NaN");
    CHECK(isnan(smaug_f64_get(read_csv_memory_result->columns[0].f64, 2, &status)), "não-finito: 'NAN' -> NaN (caixa não decide)");
    CHECK(isinf(smaug_f64_get(read_csv_memory_result->columns[0].f64, 3, &status)), "não-finito: 'inf' -> inf");
    CHECK(isinf(smaug_f64_get(read_csv_memory_result->columns[0].f64, 4, &status)), "não-finito: 'Infinity' -> inf");
    CHECK(smaug_f64_get(read_csv_memory_result->columns[0].f64, 5, &status) < 0,    "não-finito: '-inf' -> -inf");
    smaug_table_free(read_csv_memory_result);

    /* na_values explícito ainda permite tratar "nan" como ausência (compat com
       CSV de terceiros onde "nan" significa missing). */
    const char *null_vals[] = {"nan"};
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.na_values = null_vals;
    default_options_result.na_count  = 1;
    const char *text_value_2 = "v,x\nnan,1\n2.5,2\n";
    smaug_table_t *read_csv_memory_result_2 = smaug_read_csv_mem(text_value_2, strlen(text_value_2), &default_options_result);
    CHECK(read_csv_memory_result_2 && !read_csv_memory_result_2->error,          "na_values: sem erro");
    CHECK(column_is_null(read_csv_memory_result_2, 0, 0),     "na_values={'nan'}: 'nan' vira NA (opt-in)");
    CHECK(!column_is_null(read_csv_memory_result_2, 0, 1),    "na_values={'nan'}: 2.5 segue valor");
    smaug_table_free(read_csv_memory_result_2);
}

/* ===================================================================
   CSV — inferência de tipo: todos os caminhos
   =================================================================== */

static void test_csv_infer_bool_variants(void) {
    /* True/TRUE e False/FALSE além de true/false */
    const char *text_value = "v\ntrue\nTrue\nTRUE\nfalse\nFalse\nFALSE\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,               "bool variantes: sem erro");
    CHECK(strcmp(read_csv_memory_result->columns[0].dtype,"bool") == 0, "bool variantes: dtype bool");
    CHECK(get_bool(read_csv_memory_result, 0, 0) == 1,      "true → 1");
    CHECK(get_bool(read_csv_memory_result, 0, 1) == 1,      "True → 1");
    CHECK(get_bool(read_csv_memory_result, 0, 2) == 1,      "TRUE → 1");
    CHECK(get_bool(read_csv_memory_result, 0, 3) == 0,      "false → 0");
    CHECK(get_bool(read_csv_memory_result, 0, 4) == 0,      "False → 0");
    CHECK(get_bool(read_csv_memory_result, 0, 5) == 0,      "FALSE → 0");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_infer_mixed_int_float(void) {
    /* int e float na mesma coluna → float64 */
    const char *text_value = "v\n1\n2.5\n3\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error, "misto int/float: sem erro");
    CHECK(strcmp(read_csv_memory_result->columns[0].dtype,"float64") == 0, "misto: dtype float64");
    /* valores: o '1' e o '3' (que pareciam int) viraram float corretamente */
    CHECK(fabs(get_float64(read_csv_memory_result, 0, 0) - 1.0) < 1e-9, "misto: linha int 1 → 1.0");
    CHECK(fabs(get_float64(read_csv_memory_result, 0, 1) - 2.5) < 1e-9, "misto: linha float 2.5");
    CHECK(fabs(get_float64(read_csv_memory_result, 0, 2) - 3.0) < 1e-9, "misto: linha int 3 → 3.0");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_infer_float_with_int_row(void) {
    /* coluna inferida como f64: linhas que parecem i64 devem ser convertidas */
    const char *text_value = "v\n1.5\n2\n3.5\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error, "f64 com linha int: sem erro");
    double element_value = get_float64(read_csv_memory_result, 0, 1);
    CHECK(fabs(element_value - 2.0) < 1e-9, "f64 com linha int: valor 2.0");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_infer_all_null_column(void) {
    /* coluna toda NA → string (fallback seguro) */
    const char *text_value = "v\n\n\n\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error, "col toda NA: sem erro");
    CHECK(strcmp(read_csv_memory_result->columns[0].dtype,"string") == 0, "col toda NA: dtype string");
    /* todos os valores devem ser NA de fato */
    for (size_t result = 0; result < read_csv_memory_result->nrows; result++)
        CHECK(column_is_null(read_csv_memory_result, 0, result), "col toda NA: cada célula é NA");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_infer_bool_mixed_with_string(void) {
    /* bool + string não-bool → string */
    const char *text_value = "v\ntrue\nhello\nfalse\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error, "bool+str: sem erro");
    CHECK(strcmp(read_csv_memory_result->columns[0].dtype,"string") == 0, "bool+str: dtype string");
    /* o "true"/"false" devem virar texto literal, não bool */
    size_t element_count; const char *text_value_2 = get_string(read_csv_memory_result, 0, 0, &element_count);
    CHECK(text_value_2 && element_count == 4 && strncmp(text_value_2, "true", 4) == 0,  "bool+str: 'true' preservado como texto");
    const char *text_value_3 = get_string(read_csv_memory_result, 0, 1, &element_count);
    CHECK(text_value_3 && element_count == 5 && strncmp(text_value_3, "hello", 5) == 0, "bool+str: 'hello' preservado");
    smaug_table_free(read_csv_memory_result);
}


/* csv.c:143 — ramo \n no else-if do tokenizador (campo terminado por \n puro) */
static void test_csv_lf_only_field_end(void) {
    const char *text_value = "a,b\n1,2\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,         "LF field end: sem erro");
    CHECK(read_csv_memory_result->nrows == 1,          "LF field end: 1 linha");
    CHECK(get_int64(read_csv_memory_result, 1, 0) == 2, "LF field end: b[0]=2");
    smaug_table_free(read_csv_memory_result);
}

/* csv.c:178/179 — linha vazia com \r\n e \r no último byte (pos+1>=len) */
static void test_csv_crlf_at_eof(void) {
    /* \r\n final */
    const char *text_value = "v\n1\r\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,         "CRLF EOF: sem erro");
    CHECK(read_csv_memory_result->nrows == 1,          "CRLF EOF: 1 linha");
    CHECK(get_int64(read_csv_memory_result, 0, 0) == 1,  "CRLF EOF: v[0]=1 (\\r não entrou no valor)");
    smaug_table_free(read_csv_memory_result);
    /* \r sem \n no último byte */
    const char *text_value_2 = "v\n1\r";
    smaug_table_t *read_csv_memory_result_2 = smaug_read_csv_mem(text_value_2, strlen(text_value_2), NULL);
    CHECK(read_csv_memory_result_2 && !read_csv_memory_result_2->error,       "CR EOF: sem erro");
    CHECK(read_csv_memory_result_2->nrows == 1,         "CR EOF: 1 linha");
    CHECK(get_int64(read_csv_memory_result_2, 0, 0) == 1, "CR EOF: v[0]=1 (\\r final tratado)");
    smaug_table_free(read_csv_memory_result_2);
}

/* csv.c:137 — PUSH em campo sem aspas > 32 bytes (força realloc no macro) */
static void test_csv_long_unquoted_field(void) {
    const char *text_value = "v\nabcdefghijklmnopqrstuvwxyzABCDEFGH\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,         "long field: sem erro");
    CHECK(read_csv_memory_result->nrows == 1,          "long field: 1 linha");
    size_t element_count; get_string(read_csv_memory_result, 0, 0, &element_count);
    CHECK(element_count == 34,                "long field: comprimento 34");
    smaug_table_free(read_csv_memory_result);
}

/* csv.c:192 — realloc de fields[] quando linha tem > 16 campos */
static void test_csv_many_columns(void) {
    char source_values[512];
    int write_position = 0;
    for (int row_index = 0; row_index < 20; row_index++)
        write_position += sprintf(source_values + write_position, "%sc%d", row_index ? "," : "", row_index);
    write_position += sprintf(source_values + write_position, "\n");
    for (int row_index = 0; row_index < 20; row_index++)
        write_position += sprintf(source_values + write_position, "%s%d", row_index ? "," : "", row_index * 10);
    write_position += sprintf(source_values + write_position, "\n");
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(source_values, (size_t)write_position, NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,            "many cols: sem erro");
    CHECK(read_csv_memory_result->ncols == 20,            "many cols: 20 colunas");
    CHECK(read_csv_memory_result->nrows == 1,             "many cols: 1 linha");
    CHECK(get_int64(read_csv_memory_result, 19, 0) == 190, "many cols: col19[0]=190");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_short_row(void) {
    /* linha com menos campos que o header → campos faltando viram NA */
    const char *text_value = "a,b,c\n1,2\n3,4,5\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,       "linha curta: sem erro");
    CHECK(read_csv_memory_result->nrows == 2,        "linha curta: 2 linhas");
    CHECK(column_is_null(read_csv_memory_result, 2, 0), "linha curta: c[0] = NA");
    CHECK(!column_is_null(read_csv_memory_result,2, 1), "linha curta: c[1] = 5 (não NA)");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_options_zero_sep_quote(void) {
    /* opts.sep/opts.quote == 0: a struct opts não é opaca — qualquer caller
     * em C pode pegar os defaults e zerar um campo (ou montar a struct na
     * mão sem inicializar). O guard "sep ? sep : ','" existe exatamente pra
     * isso; não é inalcançável, só não tinha caller adversarial testando. */
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.sep = 0;
    const char *text_value = "a,b\n1,2\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), &default_options_result);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,        "sep=0: cai pro default ',' — sem erro");
    CHECK(read_csv_memory_result->ncols == 2,         "sep=0: 2 colunas (separou por vírgula)");
    CHECK(get_int64(read_csv_memory_result, 1, 0) == 2, "sep=0: b[0]=2");
    smaug_table_free(read_csv_memory_result);

    smaug_csv_opts_t default_options_result_2 = smaug_csv_default_opts();
    default_options_result_2.quote = 0;
    const char *text_value_2 = "a\n\"x\"\n";
    smaug_table_t *read_csv_memory_result_2 = smaug_read_csv_mem(text_value_2, strlen(text_value_2), &default_options_result_2);
    CHECK(read_csv_memory_result_2 && !read_csv_memory_result_2->error,      "quote=0: cai pro default '\"' — sem erro");
    size_t element_count; const char *text_value_3 = get_string(read_csv_memory_result_2, 0, 0, &element_count);
    CHECK(text_value_3 && element_count == 1 && text_value_3[0] == 'x', "quote=0: aspas reconhecidas, campo='x'");
    smaug_table_free(read_csv_memory_result_2);
}

/* ===================================================================
   CSV writer — caminhos adicionais
   =================================================================== */

static void test_csv_write_nan(void) {
    /* NaN em coluna float64 → "nan" no CSV */
    smaug_series_f64_t *floating_point_series = smaug_f64_create(2);
    smaug_f64_set(floating_point_series, 0, 1.0);
    smaug_f64_set(floating_point_series, 1, (double)(0.0/0.0)); /* NaN */

    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name  = "v";
    column.dtype = "float64";
    column.f64   = floating_point_series;
    values.columns = &column;
    values.ncols   = 1;
    values.nrows   = 2;

    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    size_t length;
    char *write_csv_memory_result = smaug_write_csv_mem(&values, &write_default_options_result, &length, NULL);
    CHECK(write_csv_memory_result != NULL,                         "write NaN: retorna buffer");
    CHECK(strstr(write_csv_memory_result, "nan") != NULL,          "write NaN: contém 'nan'");
    free(write_csv_memory_result);
    smaug_f64_free(floating_point_series);
}

static void test_csv_write_options_zero_sep_quote(void) {
    /* mesmo guard do lado da escrita (linhas 427/428): opts.sep/opts.quote
     * podem chegar zerados de um caller em C que monta a struct na mão. */
    smaug_series_i64_t *integer_series = smaug_i64_create(1);
    smaug_i64_set(integer_series, 0, 1);
    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name = "a"; column.dtype = "int64"; column.i64 = integer_series;
    values.columns = &column; values.ncols = 1; values.nrows = 1;

    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    write_default_options_result.sep = 0; write_default_options_result.quote = 0;
    size_t length;
    char *write_csv_memory_result = smaug_write_csv_mem(&values, &write_default_options_result, &length, NULL);
    CHECK(write_csv_memory_result != NULL,             "write sep/quote=0: retorna buffer");
    CHECK(strstr(write_csv_memory_result, "a\n1\n") != NULL, "write sep/quote=0: cai pro default ','/'\"'");
    free(write_csv_memory_result);
    smaug_i64_free(integer_series);
}

static void test_csv_write_large_field(void) {
    /* campo único > 8192 bytes força o wbuf a dobrar a capacidade mais de
     * uma vez numa só chamada de wbuf_push (cap começa em 4096; precisa
     * passar por 8192 até cobrir o campo) — cobre o loop `while` de
     * csv.c:400, que um único dobramento nunca exercita. */
    size_t big_length = 10000;
    char *text_value = malloc(big_length + 1);
    assert(text_value);
    memset(text_value, 'x', big_length);
    text_value[big_length] = '\0';

    smaug_series_str_t *source_series = smaug_str_create(1);
    smaug_str_set(source_series, 0, text_value, big_length);

    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name = "v"; column.dtype = "string"; column.str = source_series;
    values.columns = &column; values.ncols = 1; values.nrows = 1;

    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    size_t length;
    char *write_csv_memory_result = smaug_write_csv_mem(&values, &write_default_options_result, &length, NULL);
    CHECK(write_csv_memory_result != NULL,        "write campo grande: retorna buffer");
    CHECK(length > big_length,      "write campo grande: buffer cresceu além do campo (header+\\n)");
    /* integridade: o campo de 10000 'x' precisa sair COMPLETO e sem corrupção
     * no meio (o ponto do teste é o crescimento do wbuf — se ele corromper
     * durante um realloc, o tamanho ainda baterá mas o conteúdo não). */
    char *text_value_2 = strchr(write_csv_memory_result, '\n');           /* pula o header "v\n" */
    CHECK(text_value_2 != NULL,       "write campo grande: tem corpo após header");
    text_value_2++;                                    /* primeiro byte do campo */
    size_t run = strspn(text_value_2, "x");            /* conta 'x' consecutivos */
    CHECK(run == big_length,     "write campo grande: 10000 'x' contíguos e íntegros");
    free(write_csv_memory_result);
    free(text_value);
    smaug_str_free(source_series);
}


static void test_csv_write_field_with_sep(void) {
    /* campo com vírgula → deve ser escapado com aspas */
    smaug_series_str_t *source_series = smaug_str_create(1);
    smaug_str_set(source_series, 0, "a,b", 3);

    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name  = "v";
    column.dtype = "string";
    column.str   = source_series;
    values.columns = &column;
    values.ncols   = 1;
    values.nrows   = 1;

    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    size_t length;
    char *write_csv_memory_result = smaug_write_csv_mem(&values, &write_default_options_result, &length, NULL);
    CHECK(write_csv_memory_result != NULL,              "write sep em campo: retorna buffer");
    CHECK(strstr(write_csv_memory_result, "\"a,b\"") != NULL, "write sep: campo entre aspas");
    free(write_csv_memory_result);
    smaug_str_free(source_series);
}

static void test_csv_write_field_with_quote(void) {
    /* campo com aspas → "" dentro de aspas */
    smaug_series_str_t *source_series = smaug_str_create(1);
    smaug_str_set(source_series, 0, "a\"b", 3);

    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name  = "v";
    column.dtype = "string";
    column.str   = source_series;
    values.columns = &column;
    values.ncols   = 1;
    values.nrows   = 1;

    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    size_t length;
    char *write_csv_memory_result = smaug_write_csv_mem(&values, &write_default_options_result, &length, NULL);
    CHECK(write_csv_memory_result != NULL,                    "write aspas em campo: retorna buffer");
    CHECK(strstr(write_csv_memory_result, "\"a\"\"b\"") != NULL, "write aspas: escape correto");
    free(write_csv_memory_result);
    smaug_str_free(source_series);
}

static void test_csv_write_no_header(void) {
    smaug_series_i64_t *integer_series = smaug_i64_create(1);
    smaug_i64_set(integer_series, 0, 42);

    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name  = "v";
    column.dtype = "int64";
    column.i64   = integer_series;
    values.columns = &column;
    values.ncols   = 1;
    values.nrows   = 1;

    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    write_default_options_result.header = 0;
    size_t length;
    char *write_csv_memory_result = smaug_write_csv_mem(&values, &write_default_options_result, &length, NULL);
    CHECK(write_csv_memory_result != NULL,                "write sem header: retorna buffer");
    CHECK(strstr(write_csv_memory_result, "v") == NULL,   "write sem header: sem nome de coluna");
    CHECK(strstr(write_csv_memory_result, "42") != NULL,  "write sem header: contém valor");
    free(write_csv_memory_result);
    smaug_i64_free(integer_series);
}

static void test_csv_write_file(void) {
    smaug_series_i64_t *integer_series = smaug_i64_create(2);
    smaug_i64_set(integer_series, 0, 1);
    smaug_i64_set(integer_series, 1, 2);

    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name  = "v";
    column.dtype = "int64";
    column.i64   = integer_series;
    values.columns = &column;
    values.ncols   = 1;
    values.nrows   = 2;

    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    char source_values[1024];
    temporary_file_path(source_values, sizeof(source_values), "smaug_test_c.csv");
    int status_code = smaug_write_csv(source_values, &values, &write_default_options_result);
    CHECK(status_code == 0, "write file: sucesso");

    /* ler de volta e verificar */
    smaug_table_t *read_csv_result = smaug_read_csv(source_values, NULL);
    CHECK(read_csv_result && !read_csv_result->error,       "write file roundtrip: sem erro");
    CHECK(read_csv_result->nrows == 2,         "write file roundtrip: 2 linhas");
    CHECK(get_int64(read_csv_result, 0, 1) == 2,"write file roundtrip: v[1]=2");
    smaug_table_free(read_csv_result);
    smaug_i64_free(integer_series);
}

static void test_csv_write_invalid_path(void) {
    smaug_series_i64_t *integer_series = smaug_i64_create(1);
    smaug_i64_set(integer_series, 0, 1);

    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name  = "v"; column.dtype = "int64"; column.i64 = integer_series;
    values.columns = &column; values.ncols = 1; values.nrows = 1;

    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    int status_code = smaug_write_csv("/caminho/inexistente/arquivo.csv", &values, &write_default_options_result);
    CHECK(status_code == -1, "write path inválido: retorna -1");
    smaug_i64_free(integer_series);
}

/* ===================================================================
   JSON — erros e variantes
   =================================================================== */

static void test_json_empty_array(void) {
    const char *column_index = "[]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error, "JSON []: sem erro");
    CHECK(read_json_memory_result->nrows == 0,  "JSON []: 0 linhas");
    smaug_table_free(read_json_memory_result);
}

static void test_json_not_array(void) {
    /* JSON que não começa com '[' → erro */
    const char *column_index = "{\"a\":1}";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && read_json_memory_result->error != NULL, "JSON não-array: tem erro");
    smaug_table_free(read_json_memory_result);
}

static void test_json_null_values(void) {
    const char *column_index = "[{\"v\":null},{\"v\":1}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error,         "JSON null: sem erro");
    CHECK(column_is_null(read_json_memory_result, 0, 0),  "JSON null: v[0]=null");
    CHECK(!column_is_null(read_json_memory_result, 0, 1), "JSON null: v[1] não null");
    smaug_table_free(read_json_memory_result);
}

static void test_json_bool_values(void) {
    const char *column_index = "[{\"ok\":true},{\"ok\":false},{\"ok\":null}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error,               "JSON bool: sem erro");
    CHECK(strcmp(read_json_memory_result->columns[0].dtype,"bool") == 0, "JSON bool: dtype bool");
    CHECK(get_bool(read_json_memory_result, 0, 0) == 1,      "JSON bool: true → 1");
    CHECK(get_bool(read_json_memory_result, 0, 1) == 0,      "JSON bool: false → 0");
    CHECK(column_is_null(read_json_memory_result, 0, 2),        "JSON bool: null → NA");
    smaug_table_free(read_json_memory_result);
}

static void test_json_int_and_float(void) {
    /* int + float na mesma coluna → float64 */
    const char *column_index = "[{\"v\":1},{\"v\":2.5}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error, "JSON int+float: sem erro");
    CHECK(strcmp(read_json_memory_result->columns[0].dtype,"float64") == 0, "JSON int+float: float64");
    /* o 1 (que era int) precisa ter virado 1.0 no float64 */
    CHECK(fabs(get_float64(read_json_memory_result, 0, 0) - 1.0) < 1e-9, "JSON int+float: int 1 → 1.0");
    CHECK(fabs(get_float64(read_json_memory_result, 0, 1) - 2.5) < 1e-9, "JSON int+float: float 2.5");
    smaug_table_free(read_json_memory_result);
}

static void test_json_float_in_int_column(void) {
    /* float que cabe em int64: 1.0 → int64 */
    const char *column_index = "[{\"v\":1},{\"v\":2},{\"v\":3}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error, "JSON int col: sem erro");
    CHECK(strcmp(read_json_memory_result->columns[0].dtype,"int64") == 0, "JSON int col: int64");
    CHECK(get_int64(read_json_memory_result, 0, 2) == 3, "JSON int col: v[2]=3");
    smaug_table_free(read_json_memory_result);
}

static void test_json_short_record(void) {
    /* registro heterogêneo: 2o objeto é totalmente vazio ({}), ausente em
     * TODAS as 4 colunas — registro com só "i" não bastava: a própria
     * coluna "i" (int64) nunca ficava ausente, deixando o ramo !v
     * (json.c:426) descoberto especificamente pra DT_I64. JSON heterogêneo
     * é caso NORMAL (campo opcional ausente em alguns registros), não uma
     * exceção rara — campos faltando viram NA em todas as 4 famílias. */
    const char *column_index = "[{\"i\":1,\"f\":1.5,\"b\":true,\"s\":\"hello\"},{}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error,        "JSON registro curto: sem erro");
    CHECK(read_json_memory_result->ncols == 4,         "JSON registro curto: 4 colunas (do 1o registro)");
    CHECK(read_json_memory_result->nrows == 2,         "JSON registro curto: 2 linhas");
    CHECK(column_is_null(read_json_memory_result, 0, 1),  "JSON registro curto: i[1]=NA (ausente, {} vazio)");
    CHECK(column_is_null(read_json_memory_result, 1, 1),  "JSON registro curto: f[1]=NA (ausente)");
    CHECK(column_is_null(read_json_memory_result, 2, 1),  "JSON registro curto: b[1]=NA (ausente)");
    CHECK(column_is_null(read_json_memory_result, 3, 1),  "JSON registro curto: s[1]=NA (ausente)");
    /* linha 0 — todos presentes, confirma que não regrediu */
    CHECK(!column_is_null(read_json_memory_result, 0, 0), "JSON registro curto: i[0] presente");
    CHECK(!column_is_null(read_json_memory_result, 1, 0), "JSON registro curto: f[0] presente");
    CHECK(!column_is_null(read_json_memory_result, 2, 0), "JSON registro curto: b[0] presente");
    CHECK(!column_is_null(read_json_memory_result, 3, 0), "JSON registro curto: s[0] presente");
    smaug_table_free(read_json_memory_result);
}

static void test_json_string_escape(void) {
    /* escapes JSON: \n \t \\ \" */
    const char *column_index = "[{\"v\":\"a\\nb\\tc\\\\d\\\"\"}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error, "JSON escape: sem erro");
    size_t element_count; const char *text_value = get_string(read_json_memory_result, 0, 0, &element_count);
    CHECK(text_value && element_count == 8,    "JSON escape: comprimento 8");
    CHECK(text_value[1] == '\n',   "JSON escape: \\n");
    CHECK(text_value[3] == '\t',   "JSON escape: \\t");
    CHECK(text_value[5] == '\\',   "JSON escape: \\\\");
    CHECK(text_value[7] == '"',    "JSON escape: \\\"");
    smaug_table_free(read_json_memory_result);
}

static void test_json_file_not_found(void) {
    smaug_table_t *read_json_result = smaug_read_json("/caminho/inexistente/arquivo.json");
    CHECK(read_json_result && read_json_result->error != NULL, "JSON arquivo inexistente: tem erro");
    smaug_table_free(read_json_result);
}

static void test_json_write_nan(void) {
    /* NaN em float64 → null no JSON */
    smaug_series_f64_t *floating_point_series = smaug_f64_create(2);
    smaug_f64_set(floating_point_series, 0, 1.5);
    smaug_f64_set(floating_point_series, 1, (double)(0.0/0.0));

    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name = "v"; column.dtype = "float64"; column.f64 = floating_point_series;
    values.columns = &column; values.ncols = 1; values.nrows = 2;

    smaug_json_write_opts_t values_2 = {0};
    size_t length;
    char *write_json_memory_result = smaug_write_json_mem(&values, &values_2, &length, NULL);
    CHECK(write_json_memory_result != NULL,               "JSON write NaN: retorna buffer");
    CHECK(strstr(write_json_memory_result, "null") != NULL,"JSON write NaN: NaN → null");
    free(write_json_memory_result);
    smaug_f64_free(floating_point_series);
}

static void test_json_write_escape(void) {
    /* JSON writer: escapa \n \t \\ " e caracteres de controle */
    smaug_series_str_t *source_series = smaug_str_create(1);
    const char *text_value = "a\nb\tc\\\"\x01";  /* \n \t \\ " e ctrl */
    smaug_str_set(source_series, 0, text_value, strlen(text_value));

    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name = "v"; column.dtype = "string"; column.str = source_series;
    values.columns = &column; values.ncols = 1; values.nrows = 1;

    smaug_json_write_opts_t values_2 = {0};
    size_t length;
    char *write_json_memory_result = smaug_write_json_mem(&values, &values_2, &length, NULL);
    CHECK(write_json_memory_result != NULL,                    "JSON write escape: retorna buffer");
    CHECK(strstr(write_json_memory_result, "\\n")  != NULL,    "JSON write escape: \\n");
    CHECK(strstr(write_json_memory_result, "\\t")  != NULL,    "JSON write escape: \\t");
    CHECK(strstr(write_json_memory_result, "\\\\") != NULL,    "JSON write escape: \\\\");
    CHECK(strstr(write_json_memory_result, "\\\"") != NULL,    "JSON write escape: \\\"");
    CHECK(strstr(write_json_memory_result, "\\u0001") != NULL, "JSON write escape: ctrl→\\uXXXX");
    free(write_json_memory_result);
    smaug_str_free(source_series);
}

static void test_json_write_pretty(void) {
    const char *column_index = "[{\"x\":1}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    smaug_json_write_opts_t values = {.pretty = 1};
    size_t length;
    char *write_json_memory_result = smaug_write_json_mem(read_json_memory_result, &values, &length, NULL);
    CHECK(write_json_memory_result != NULL,            "JSON pretty: retorna buffer");
    CHECK(strstr(write_json_memory_result,"\n") != NULL,"JSON pretty: tem newlines");
    CHECK(strstr(write_json_memory_result,"  ") != NULL,"JSON pretty: tem indentação");
    free(write_json_memory_result);
    smaug_table_free(read_json_memory_result);
}

static void test_json_write_file(void) {
    const char *column_index = "[{\"a\":1,\"b\":\"x\"}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    smaug_json_write_opts_t values = {0};
    char source_values[1024];
    temporary_file_path(source_values, sizeof(source_values), "smaug_test_c.json");
    int status_code = smaug_write_json(source_values, read_json_memory_result, &values);
    CHECK(status_code == 0, "JSON write file: sucesso");

    smaug_table_t *read_json_result = smaug_read_json(source_values);
    CHECK(read_json_result && !read_json_result->error,       "JSON file roundtrip: sem erro");
    CHECK(read_json_result->nrows == 1,         "JSON file roundtrip: 1 linha");
    CHECK(get_int64(read_json_result, 0, 0) == 1,"JSON file roundtrip: a[0]=1");
    smaug_table_free(read_json_memory_result);
    smaug_table_free(read_json_result);
}

static void test_json_write_invalid_path(void) {
    const char *column_index = "[{\"v\":1}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    smaug_json_write_opts_t values = {0};
    int status_code = smaug_write_json("/caminho/inexistente/arquivo.json", read_json_memory_result, &values);
    CHECK(status_code == -1, "JSON write path inválido: retorna -1");
    smaug_table_free(read_json_memory_result);
}

/* ===================================================================
   Roundtrips (CSV e JSON)
   =================================================================== */

static void test_csv_roundtrip_all_dtypes(void) {
    /* i64, f64, bool, string com NAs em cada dtype */
    const char *text_value =
        "i,f,b,s\n"
        "1,1.5,true,hello\n"
        ",2.5,false,\n"
        "3,,true,world\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,  "roundtrip all: leitura ok");
    CHECK(read_csv_memory_result->nrows == 3,   "roundtrip all: 3 linhas");

    /* escreve e lê de volta */
    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    size_t length;
    char *write_csv_memory_result = smaug_write_csv_mem(read_csv_memory_result, &write_default_options_result, &length, NULL);
    CHECK(write_csv_memory_result != NULL, "roundtrip all: escrita ok");

    smaug_table_t *read_csv_memory_result_2 = smaug_read_csv_mem(write_csv_memory_result, length, NULL);
    CHECK(read_csv_memory_result_2 && !read_csv_memory_result_2->error,          "roundtrip all: releitura ok");
    CHECK(read_csv_memory_result_2->nrows == 3,            "roundtrip all: 3 linhas relidas");
    CHECK(column_is_null(read_csv_memory_result_2, 0, 1),    "roundtrip all: i[1] NA");
    CHECK(column_is_null(read_csv_memory_result_2, 1, 2),    "roundtrip all: f[2] NA");
    CHECK(get_bool(read_csv_memory_result_2, 2, 0) == 1, "roundtrip all: b[0]=true");
    CHECK(get_bool(read_csv_memory_result_2, 2, 1) == 0, "roundtrip all: b[1]=false");
    CHECK(column_is_null(read_csv_memory_result_2, 3, 1),   "roundtrip all: s[1] NA");

    free(write_csv_memory_result);
    smaug_table_free(read_csv_memory_result);
    smaug_table_free(read_csv_memory_result_2);
}

static void test_json_roundtrip_all_dtypes(void) {
    const char *column_index =
        "[{\"i\":1,\"f\":1.5,\"b\":true,\"s\":\"hello\"},"
         "{\"i\":null,\"f\":2.5,\"b\":false,\"s\":null},"
         "{\"i\":3,\"f\":null,\"b\":true,\"s\":\"world\"}]";

    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error, "JSON roundtrip all: leitura ok");

    smaug_json_write_opts_t values = {0};
    size_t length;
    char *write_json_memory_result = smaug_write_json_mem(read_json_memory_result, &values, &length, NULL);
    CHECK(write_json_memory_result != NULL, "JSON roundtrip all: escrita ok");

    smaug_table_t *read_json_memory_result_2 = smaug_read_json_mem(write_json_memory_result, length);
    CHECK(read_json_memory_result_2 && !read_json_memory_result_2->error,          "JSON roundtrip all: releitura ok");
    CHECK(read_json_memory_result_2->nrows == 3,            "JSON roundtrip all: 3 linhas");
    CHECK(column_is_null(read_json_memory_result_2, 0, 1),    "JSON roundtrip: i[1] null");
    CHECK(column_is_null(read_json_memory_result_2, 1, 2),    "JSON roundtrip: f[2] null");
    CHECK(get_bool(read_json_memory_result_2, 2, 2) == 1, "JSON roundtrip: b[2]=true");

    free(write_json_memory_result);
    smaug_table_free(read_json_memory_result);
    smaug_table_free(read_json_memory_result_2);
}


static void test_csv_null_custom(void) {
    /* na_values customizados passados pelo caller */
    const char *text_values[] = {"N/D", "ausente"};
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.na_values = text_values;
    default_options_result.na_count  = 2;
    const char *text_value = "v\nN/D\nausente\n1\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), &default_options_result);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,         "na custom: sem erro");
    CHECK(column_is_null(read_csv_memory_result, 0, 0),  "na custom: N/D → null");
    CHECK(column_is_null(read_csv_memory_result, 0, 1),  "na custom: ausente → null");
    CHECK(!column_is_null(read_csv_memory_result, 0, 2), "na custom: 1 não é null");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_null_custom_empty_field(void) {
    /* na_values customizado SEM "" — campo vazio deixa de ser NA por
     * definição e chega em try_i64/try_f64 como string vazia de verdade
     * (cobre o ramo !*s, nunca alcançado pelo default que trata "" como NA
     * antes mesmo de chamar try_i64/try_f64). */
    const char *text_values[] = {"N/D"};
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.na_values = text_values;
    default_options_result.na_count  = 1;
    const char *text_value = "v,w\nN/D,5\n,7\n1,8\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), &default_options_result);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,            "na custom sem vazio: sem erro");
    CHECK(strcmp(read_csv_memory_result->columns[0].dtype,"string") == 0,
                                      "na custom sem vazio: v vira string (\"\" não parseia)");
    CHECK(column_is_null(read_csv_memory_result, 0, 0),      "na custom sem vazio: N/D → null");
    CHECK(!column_is_null(read_csv_memory_result, 0, 1),     "na custom sem vazio: \"\" não é NA (não está na lista)");
    size_t element_count; const char *text_value_2 = get_string(read_csv_memory_result, 0, 1, &element_count);
    CHECK(text_value_2 && element_count == 0,               "na custom sem vazio: campo vazio vira string vazia, não null");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_numeric_overflow(void) {
    /* valor que excede int64 (errno=ERANGE em strtoll) mas cabe em double —
     * cobre o ramo errno de try_i64 (linha 84), que difere do ramo "sobra
     * lixo" (*end != '\0') já coberto por colunas de string comum. */
    const char *text_value = "v\n99999999999999999999\n1.5\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,         "overflow i64: sem erro");
    CHECK(strcmp(read_csv_memory_result->columns[0].dtype,"float64") == 0,
                                   "overflow i64: vira float64 (i64 falha por overflow, f64 aceita)");
    smaug_table_free(read_csv_memory_result);
}

static void test_csv_float_overflow(void) {
    /* valor que excede DBL_MAX (~1.8e308) — strtod retorna HUGE_VAL e seta
     * errno=ERANGE. Único jeito de exercitar o ramo errno de try_f64;
     * o ramo "sobra lixo" já é coberto por qualquer string comum. */
    const char *text_value = "v\n1e400\n1.5\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result && !read_csv_memory_result->error,         "overflow f64: sem erro");
    CHECK(strcmp(read_csv_memory_result->columns[0].dtype,"string") == 0,
                                   "overflow f64: 1e400 falha em f64 (overflow) → coluna vira string");
    smaug_table_free(read_csv_memory_result);
}

/* Contraparte de LEITURA do teste de fronteira abaixo. Achado 2026-07-28: a
   escrita validava e era testada; a leitura nao fazia nem uma coisa nem outra,
   e read_csv_mem(NULL, 10) / read_json_mem(NULL, 10) SEGFALTAVAM. Assimetria
   dentro do mesmo modulo. */
static void test_read_memory_null_args(void) {
    /* buf NULL com len > 0 e chamada invalida -> NULL, nao crash */
    CHECK(smaug_read_csv_mem(NULL, 10, NULL) == NULL,
          "read_csv_mem: buf=NULL com len>0 retorna NULL");
    CHECK(smaug_read_json_mem(NULL, 10) == NULL,
          "read_json_mem: buf=NULL com len>0 retorna NULL");

    /* buf NULL com len == 0 e entrada VAZIA legitima, nao erro -- a guarda nao
       pode ser `if (!buf)`, senao quebraria este caso */
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(NULL, 0);
    CHECK(read_json_memory_result != NULL, "read_json_mem: buf=NULL com len=0 e entrada vazia valida");
    if (read_json_memory_result) smaug_table_free(read_json_memory_result);

    /* caminho normal segue funcionando */
    const char *text_value = "a,b\n1,2\n";
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, strlen(text_value), NULL);
    CHECK(read_csv_memory_result != NULL && read_csv_memory_result->ncols == 2, "read_csv_mem: caminho normal intacto");
    if (read_csv_memory_result) smaug_table_free(read_csv_memory_result);
}

static void test_csv_write_null_args(void) {
    /* smaug_write_csv_mem(NULL,...) e (t, NULL, ...) — guards de fronteira
     * pública (linhas 424/426), nunca testados com argumento NULL real. */
    size_t length;
    char *write_csv_memory_result = smaug_write_csv_mem(NULL, NULL, &length, NULL);
    CHECK(write_csv_memory_result == NULL, "write_csv_mem: t=NULL retorna NULL");

    smaug_series_i64_t *integer_series = smaug_i64_create(1);
    smaug_i64_set(integer_series, 0, 1);
    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name = "v"; column.dtype = "int64"; column.i64 = integer_series;
    values.columns = &column; values.ncols = 1; values.nrows = 1;

    char *write_csv_memory_result_2 = smaug_write_csv_mem(&values, NULL, &length, NULL);
    CHECK(write_csv_memory_result_2 != NULL, "write_csv_mem: opts=NULL usa default, sem erro");
    free(write_csv_memory_result_2);

    char *write_csv_memory_result_3 = smaug_write_csv_mem(&values, NULL, NULL, NULL);
    CHECK(write_csv_memory_result_3 == NULL, "write_csv_mem: out_len=NULL retorna NULL");

    smaug_i64_free(integer_series);
}

static void test_json_string_mixed_types(void) {
    /* coluna que mistura int/float/bool/string força dtype=string (catch-all
     * heterogêneo) — diferente das colunas i64/f64/bool, aqui o formatador
     * de fallback (tmp/snprintf) É alcançável de verdade: cada valor não-
     * string precisa ser formatado como texto na hora de preencher. */
    const char *column_index = "[{\"v\":1},{\"v\":2.5},{\"v\":true},{\"v\":\"texto\"},{\"v\":false}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error,         "JSON str misto: sem erro");
    CHECK(strcmp(read_json_memory_result->columns[0].dtype,"string") == 0, "JSON str misto: dtype string");
    size_t element_count; const char *text_value;
    text_value = get_string(read_json_memory_result, 0, 0, &element_count); CHECK(text_value && element_count==1 && text_value[0]=='1',        "JSON str misto: int → \"1\"");
    text_value = get_string(read_json_memory_result, 0, 1, &element_count); CHECK(text_value && strncmp(text_value,"2.5",3)==0,    "JSON str misto: float → \"2.5\"");
    text_value = get_string(read_json_memory_result, 0, 2, &element_count); CHECK(text_value && element_count==4 && strncmp(text_value,"true",4)==0,  "JSON str misto: bool true → \"true\"");
    text_value = get_string(read_json_memory_result, 0, 3, &element_count); CHECK(text_value && element_count==5 && strncmp(text_value,"texto",5)==0, "JSON str misto: string passa direto");
    text_value = get_string(read_json_memory_result, 0, 4, &element_count); CHECK(text_value && element_count==5 && strncmp(text_value,"false",5)==0, "JSON str misto: bool false → \"false\"");
    smaug_table_free(read_json_memory_result);
}


static void test_json_negative_number(void) {
    const char *column_index = "[{\"v\":-42}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error,         "JSON negativo: sem erro");
    CHECK(get_int64(read_json_memory_result, 0, 0) == -42,"JSON negativo: v=-42");
    smaug_table_free(read_json_memory_result);
}

static void test_json_exponent_number(void) {
    const char *column_index = "[{\"v\":1e3}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error,          "JSON expoente: sem erro");
    CHECK(fabs(get_float64(read_json_memory_result, 0, 0) - 1000.0) < 1.0, "JSON expoente: 1e3=1000");
    smaug_table_free(read_json_memory_result);
}

static void test_json_negative_exponent(void) {
    const char *column_index = "[{\"v\":1.5e-2}]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error,          "JSON exp negativo: sem erro");
    CHECK(fabs(get_float64(read_json_memory_result, 0, 0) - 0.015) < 1e-9, "JSON exp negativo: 1.5e-2");
    smaug_table_free(read_json_memory_result);
}

static void test_json_unicode_escape(void) {
    /* --- BMP: ASCII (U+0041 = 'A') --- */
    {
        const char *column_index = "[{\"v\":\"\\u0041\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && !read_json_memory_result->error, "JSON unicode ASCII: sem erro");
        size_t element_count; const char *text_value = get_string(read_json_memory_result, 0, 0, &element_count);
        CHECK(text_value && element_count == 1,    "JSON unicode ASCII: 1 byte");
        CHECK(text_value[0] == 'A',    "JSON unicode ASCII: U+0041 = 'A'");
        smaug_table_free(read_json_memory_result);
    }
    /* --- BMP: 2-byte UTF-8 (U+00E9 = 'e' com acento agudo) --- */
    {
        const char *column_index = "[{\"v\":\"caf\\u00e9\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && !read_json_memory_result->error, "JSON unicode 2-byte: sem erro");
        size_t element_count; const char *text_value = get_string(read_json_memory_result, 0, 0, &element_count);
        /* UTF-8 de e-agudo = 0xC3 0xA9; "caf" + 2 bytes = 5 bytes total */
        CHECK(text_value && element_count == 5,    "JSON unicode 2-byte: 5 bytes");
        CHECK((unsigned char)text_value[3] == 0xC3 && (unsigned char)text_value[4] == 0xA9,
              "JSON unicode 2-byte: UTF-8 correto para U+00E9");
        smaug_table_free(read_json_memory_result);
    }
    /* --- BMP: 3-byte UTF-8 (U+4E2D = caractere CJK) --- */
    {
        const char *column_index = "[{\"v\":\"\\u4e2d\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && !read_json_memory_result->error, "JSON unicode 3-byte: sem erro");
        size_t element_count; const char *text_value = get_string(read_json_memory_result, 0, 0, &element_count);
        /* UTF-8 de U+4E2D = 0xE4 0xB8 0xAD */
        CHECK(text_value && element_count == 3,                         "JSON unicode 3-byte: 3 bytes");
        CHECK((unsigned char)text_value[0] == 0xE4 &&
              (unsigned char)text_value[1] == 0xB8 &&
              (unsigned char)text_value[2] == 0xAD,         "JSON unicode 3-byte: UTF-8 correto para U+4E2D");
        smaug_table_free(read_json_memory_result);
    }
    /* --- Surrogate pair (U+1F600) → 4-byte UTF-8 --- */
    {
        /* \uD83D\uDE00 = U+1F600 → UTF-8: 0xF0 0x9F 0x98 0x80 */
        const char *column_index = "[{\"v\":\"\\uD83D\\uDE00\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && !read_json_memory_result->error, "JSON unicode surrogate pair: sem erro");
        size_t element_count; const char *text_value = get_string(read_json_memory_result, 0, 0, &element_count);
        CHECK(text_value && element_count == 4,                         "JSON unicode surrogate pair: 4 bytes");
        CHECK((unsigned char)text_value[0] == 0xF0 &&
              (unsigned char)text_value[1] == 0x9F &&
              (unsigned char)text_value[2] == 0x98 &&
              (unsigned char)text_value[3] == 0x80,         "JSON unicode surrogate pair: UTF-8 correto para U+1F600");
        smaug_table_free(read_json_memory_result);
    }
    /* --- Surrogate isolado (high) → erro --- */
    {
        const char *column_index = "[{\"v\":\"\\uD83D\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && read_json_memory_result->error,  "JSON unicode high surrogate isolado: erro");
        smaug_table_free(read_json_memory_result);
    }
    /* --- Surrogate isolado (low) → erro --- */
    {
        const char *column_index = "[{\"v\":\"\\uDE00\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && read_json_memory_result->error,  "JSON unicode low surrogate isolado: erro");
        smaug_table_free(read_json_memory_result);
    }
    /* --- Hex inválido em \uXXXX → erro --- */
    {
        const char *column_index = "[{\"v\":\"\\uXXXX\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && read_json_memory_result->error,  "JSON unicode hex invalido: erro");
        smaug_table_free(read_json_memory_result);
    }
    /* --- \uXXXX dentro de string mista --- */
    {
        /* "ol\u00e1 mundo" = "ol" + a-agudo (2 bytes) + " mundo" = 10 bytes */
        const char *column_index = "[{\"v\":\"ol\\u00e1 mundo\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && !read_json_memory_result->error, "JSON unicode misto: sem erro");
        size_t element_count; const char *text_value = get_string(read_json_memory_result, 0, 0, &element_count);
        CHECK(text_value && element_count == 10,   "JSON unicode misto: 10 bytes");
        CHECK(text_value[0]=='o' && text_value[1]=='l', "JSON unicode misto: prefixo correto");
        CHECK((unsigned char)text_value[2]==0xC3 && (unsigned char)text_value[3]==0xA1,
              "JSON unicode misto: a-agudo U+00E1 correto");
        smaug_table_free(read_json_memory_result);
    }
}

static void test_json_whitespace_variants(void) {
    /* espaços, tabs e newlines entre tokens */
    const char *column_index = "[\n  {\n    \"x\" : 1\n  }\n]";
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
    CHECK(read_json_memory_result && !read_json_memory_result->error,         "JSON whitespace: sem erro");
    CHECK(get_int64(read_json_memory_result, 0, 0) == 1, "JSON whitespace: x=1");
    smaug_table_free(read_json_memory_result);
}

static void test_json_bf_escape(void) {
    /* \b e \f no writer JSON — escapes de controle menos comuns */
    smaug_series_str_t *source_series = smaug_str_create(1);
    const char *text_value = "a\bf\fc";  /* backspace e form-feed */
    smaug_str_set(source_series, 0, text_value, strlen(text_value));
    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name = "v"; column.dtype = "string"; column.str = source_series;
    values.columns = &column; values.ncols = 1; values.nrows = 1;
    smaug_json_write_opts_t values_2 = {0};
    size_t length;
    char *write_json_memory_result = smaug_write_json_mem(&values, &values_2, &length, NULL);
    CHECK(write_json_memory_result != NULL, "JSON \\b\\f: retorna buffer");
    /* \b e \f não têm escape explícito no writer — viram \u0008 e \u000c */
    CHECK(strstr(write_json_memory_result, "\\u0008") != NULL || strstr(write_json_memory_result, "\\b") != NULL,
          "JSON \\b: escapado");
    free(write_json_memory_result);
    smaug_str_free(source_series);
}

static void test_json_lexer_edges(void) {
    /* --- \r e \r\n como whitespace (linha 45: \r branch nunca exercitado) --- */
    {
        const char *column_index = "[\r{\"v\":1}\r\n]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && !read_json_memory_result->error,         "JSON \\r whitespace: sem erro");
        CHECK(get_int64(read_json_memory_result, 0, 0) == 1, "JSON \\r whitespace: v=1");
        smaug_table_free(read_json_memory_result);
    }
    /* --- expoente com sinal + e letra E maiúscula (linha 212 branches) --- */
    {
        const char *column_index = "[{\"v\":1.5E+3}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && !read_json_memory_result->error,                        "JSON E+: sem erro");
        CHECK(fabs(get_float64(read_json_memory_result, 0, 0) - 1500.0) < 1.0,"JSON E+: 1.5E+3=1500");
        smaug_table_free(read_json_memory_result);
    }
    /* --- palavras-chave com prefixo parcial → TOK_ERROR (linhas 194/198/202) --- */
    {
        const char *cases[] = {
            "[{\"v\":tru}]", "[{\"v\":fals}]", "[{\"v\":nul}]", NULL
        };
        for (int row_index = 0; cases[row_index]; row_index++) {
            smaug_table_t *read_json_memory_result = smaug_read_json_mem(cases[row_index], strlen(cases[row_index]));
            CHECK(read_json_memory_result && read_json_memory_result->error, "JSON keyword parcial: erro esperado");
            smaug_table_free(read_json_memory_result);
        }
    }
    /* --- escapes do reader: \/ \r \b \f (switch linha 156) --- */
    {
        const char *column_index = "[{\"v\":\"\\/\\r\\b\\f\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && !read_json_memory_result->error,  "JSON escapes \\/\\r\\b\\f: sem erro");
        size_t element_count; const char *text_value = get_string(read_json_memory_result, 0, 0, &element_count);
        CHECK(text_value && element_count == 4,     "JSON escapes: 4 bytes no campo");
        CHECK(text_value[0] == '/',     "JSON escapes: \\/ → '/'");
        CHECK(text_value[1] == '\r',    "JSON escapes: \\r → carriage return");
        CHECK(text_value[2] == '\b',    "JSON escapes: \\b → backspace");
        CHECK(text_value[3] == '\f',    "JSON escapes: \\f → form feed");
        smaug_table_free(read_json_memory_result);
    }
    /* --- elemento não-objeto no array (linhas 324-325) --- */
    {
        const char *column_index = "[1, 2, 3]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && read_json_memory_result->error,   "JSON array não-objeto: erro esperado");
        smaug_table_free(read_json_memory_result);
    }
    /* --- coluna toda-nula (dtypes[c] == DT_UNKNOWN, linha 396) --- */
    {
        const char *column_index = "[{\"v\":null},{\"v\":null}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && !read_json_memory_result->error,  "JSON coluna toda-nula: sem erro");
        CHECK(strcmp(read_json_memory_result->columns[0].dtype,"string") == 0,
                               "JSON coluna toda-nula: DT_UNKNOWN → string");
        CHECK(column_is_null(read_json_memory_result, 0, 0), "JSON coluna toda-nula: v[0]=NA");
        CHECK(column_is_null(read_json_memory_result, 0, 1), "JSON coluna toda-nula: v[1]=NA");
        smaug_table_free(read_json_memory_result);
    }
}

static void test_json_surrogate_errors_extended(void) {
    /* --- high surrogate seguido de \u com hex inválido (linha 130: cp2 < 0) --- */
    {
        const char *column_index = "[{\"v\":\"\\uD83D\\uXXXX\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && read_json_memory_result->error, "JSON surrogate+hex_invalido: erro esperado");
        smaug_table_free(read_json_memory_result);
    }
    /* --- dois high surrogates seguidos (linha 132: ucp2 < 0xDC00) --- */
    {
        const char *column_index = "[{\"v\":\"\\uD83D\\uD800\"}]";
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && read_json_memory_result->error, "JSON high+high surrogate: erro esperado");
        smaug_table_free(read_json_memory_result);
    }
    /* --- \uXXXX truncado no final do buffer (linha 53: pos+4 > len) --- */
    {
        const char *column_index = "[{\"v\":\"\\u00\"}]"; /* só 2 dígitos hex */
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
        CHECK(read_json_memory_result && read_json_memory_result->error, "JSON \\uXXXX truncado: erro esperado");
        smaug_table_free(read_json_memory_result);
    }
}

static void test_json_unicode_realloc(void) {
    /* 25 codepoints BMP 3-byte (U+4E2D = 中) = 75 bytes > cap inicial (64)
     * força o realloc do buffer de string (linha 145/146) numa única string.
     * Usa JSON com 25 \u4e2d consecutivos. */
    char column_index[512];
    int write_position = sprintf(column_index, "[{\"v\":\"");
    for (int row_index = 0; row_index < 25; row_index++) write_position += sprintf(column_index+write_position, "\\u4e2d");
    write_position += sprintf(column_index+write_position, "\"}]");

    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, (size_t)write_position);
    CHECK(read_json_memory_result && !read_json_memory_result->error,        "JSON unicode realloc: sem erro");
    size_t element_count; const char *text_value = get_string(read_json_memory_result, 0, 0, &element_count);
    CHECK(text_value && element_count == 75,          "JSON unicode realloc: 25×3 bytes = 75");
    /* primeiro e último codepoint: 0xE4 0xB8 0xAD */
    CHECK((unsigned char)text_value[0] == 0xE4 &&
          (unsigned char)text_value[1] == 0xB8 &&
          (unsigned char)text_value[2] == 0xAD,  "JSON unicode realloc: primeiro codepoint correto");
    smaug_table_free(read_json_memory_result);
}

static void test_json_write_options_null(void) {
    /* smaug_write_json_mem(NULL, ...) e (t, ..., NULL) — guards de fronteira
     * (linha 549: !t || !out_len). */
    size_t length;
    char *write_json_memory_result = smaug_write_json_mem(NULL, NULL, &length, NULL);
    CHECK(write_json_memory_result == NULL, "JSON write: t=NULL retorna NULL");

    smaug_series_i64_t *integer_series = smaug_i64_create(1);
    smaug_i64_set(integer_series, 0, 1);
    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name = "v"; column.dtype = "int64"; column.i64 = integer_series;
    values.columns = &column; values.ncols = 1; values.nrows = 1;

    smaug_json_write_opts_t values_2 = {0};
    char *write_json_memory_result_2 = smaug_write_json_mem(&values, &values_2, NULL, NULL);
    CHECK(write_json_memory_result_2 == NULL, "JSON write: out_len=NULL retorna NULL");
    smaug_i64_free(integer_series);
}

static void test_json_write_pretty_rich(void) {
    /* pretty=1 com multi-coluna e nulls — exercita os branches de nl/ind/ind2
     * e os separadores de colunas/linhas (linhas 557–605) que a versão simples
     * não alcança porque tem só 1 coluna sem null. */
    smaug_series_i64_t *integer_series = smaug_i64_create(2);
    smaug_series_str_t *source_series = smaug_str_create(2);
    smaug_i64_set(integer_series, 0, 1);  smaug_i64_set_null(integer_series, 1);
    smaug_str_set(source_series, 0, "a", 1); smaug_str_set_null(source_series, 1);
    smaug_column_t column_names[2] = {0};
    column_names[0].name = "i"; column_names[0].dtype = "int64";  column_names[0].i64 = integer_series;
    column_names[1].name = "s"; column_names[1].dtype = "string"; column_names[1].str = source_series;
    smaug_table_t values = {0};
    values.columns = column_names; values.ncols = 2; values.nrows = 2;

    smaug_json_write_opts_t values_2 = {.pretty = 1};
    size_t length;
    char *write_json_memory_result = smaug_write_json_mem(&values, &values_2, &length, NULL);
    CHECK(write_json_memory_result != NULL,               "JSON write pretty rich: retorna buffer");
    CHECK(strstr(write_json_memory_result, "\n") != NULL, "JSON write pretty rich: tem newline");
    CHECK(strstr(write_json_memory_result, "null") != NULL, "JSON write pretty rich: null aparece");
    free(write_json_memory_result);
    smaug_i64_free(integer_series); smaug_str_free(source_series);
}

static void test_json_parse_errors(void) {
    /* chave sem ':' depois (linha 281) */
    { const char *column_index = "[{\"v\" 1}]";
      smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
      CHECK(read_json_memory_result && read_json_memory_result->error, "JSON sem ':': erro esperado");
      smaug_table_free(read_json_memory_result); }

    /* dois campos sem ',' entre eles (linha 299) */
    { const char *column_index = "[{\"v\":1 \"w\":2}]";
      smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, strlen(column_index));
      CHECK(read_json_memory_result && read_json_memory_result->error, "JSON sem ',': erro esperado");
      smaug_table_free(read_json_memory_result); }
}

static void test_json_write_large_string(void) {
    /* string de 10k chars → força o wbuf do writer a dobrar a capacidade
     * mais de uma vez (linha 521: while ncap <= b->len+n cap*=2). */
    size_t big_length = 10000;
    char *text_value = malloc(big_length + 1);
    assert(text_value);
    memset(text_value, 'x', big_length);
    text_value[big_length] = '\0';

    smaug_series_str_t *source_series = smaug_str_create(1);
    smaug_str_set(source_series, 0, text_value, big_length);
    smaug_table_t values = {0};
    smaug_column_t column = {0};
    column.name = "v"; column.dtype = "string"; column.str = source_series;
    values.columns = &column; values.ncols = 1; values.nrows = 1;

    smaug_json_write_opts_t values_2 = {0};
    size_t length;
    char *write_json_memory_result = smaug_write_json_mem(&values, &values_2, &length, NULL);
    CHECK(write_json_memory_result != NULL,    "JSON write large: retorna buffer");
    CHECK(length > big_length,  "JSON write large: buffer maior que o campo (overhead JSON)");
    /* integridade: relê o JSON e confirma que a string de 10000 'x' voltou
     * COMPLETA (um realloc corrompido daria tamanho certo mas conteúdo errado). */
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(write_json_memory_result, length);
    CHECK(read_json_memory_result && !read_json_memory_result->error,           "JSON write large: relê sem erro");
    size_t element_count; const char *text_value_2 = get_string(read_json_memory_result, 0, 0, &element_count);
    CHECK(text_value_2 && element_count == big_length,         "JSON write large: 10000 bytes relidos");
    /* a string tem comprimento explícito n (não é null-terminada) — verificar
     * dentro do limite, sem strspn que leria além do buffer. */
    int repeated_character_buffer = (text_value_2 != NULL);
    for (size_t row_index = 0; repeated_character_buffer && row_index < element_count; row_index++) if (text_value_2[row_index] != 'x') repeated_character_buffer = 0;
    CHECK(repeated_character_buffer,                      "JSON write large: 10000 'x' íntegros");
    smaug_table_free(read_json_memory_result);
    free(write_json_memory_result);
    free(text_value);
    smaug_str_free(source_series);
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
    test_csv_null_values();
    test_csv_nonfinite_values();

    /* CSV — inferência */
    test_csv_infer_bool_variants();
    test_csv_infer_mixed_int_float();
    test_csv_infer_float_with_int_row();
    test_csv_infer_all_null_column();
    test_csv_infer_bool_mixed_with_string();
    test_csv_lf_only_field_end();
    test_csv_crlf_at_eof();
    test_csv_long_unquoted_field();
    test_csv_many_columns();
    test_csv_short_row();
    test_csv_options_zero_sep_quote();
    test_csv_numeric_overflow();
    test_csv_float_overflow();

    /* CSV — writer */
    test_csv_write_nan();
    test_csv_write_options_zero_sep_quote();
    test_csv_write_large_field();
    test_read_memory_null_args();
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
    test_json_float_in_int_column();
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
    test_csv_null_custom();
    test_csv_null_custom_empty_field();

    /* JSON — variantes numéricas e escapes */
    test_json_negative_number();
    test_json_string_mixed_types();
    test_json_exponent_number();
    test_json_negative_exponent();
    test_json_unicode_escape();
    test_json_whitespace_variants();
    test_json_bf_escape();
    test_json_lexer_edges();
    test_json_surrogate_errors_extended();
    test_json_unicode_realloc();
    test_json_write_options_null();
    test_json_write_pretty_rich();
    test_json_parse_errors();
    test_json_write_large_string();

    /* Roundtrips */
    test_csv_roundtrip_all_dtypes();
    test_json_roundtrip_all_dtypes();

    if (failed_checks == 0)
        printf("PASS: test_io_c (%d checks)\n", passed_checks);
    else
        printf("FAIL: %d/%d checks falharam\n", failed_checks, passed_checks + failed_checks);

    return failed_checks > 0 ? 1 : 0;
}
