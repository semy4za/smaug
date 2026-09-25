#include "../include/smaug.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* OK nao depende de assert(): permanece ativo sob -DNDEBUG. */
static int passed_checks = 0;
#define OK(condition, message) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU: %s\n", message); exit(1); } passed_checks++; } while (0)

/* 2^53 + 1: primeiro inteiro que double NAO representa. E o coracao do
   bug do 10.7 — o round-trip por get()/double do oraculo o corrompe para
   9007199254740992. As copias diretas em C devem preserva-lo exato. */
#define TWO53_PLUS_1  9007199254740993LL

/* ---------- Grupo A: valores normais + propagacao de null ---------- */
static void test_basic_conversions(void) {
    /* i64 -> f64 */
    smaug_series_i64_t *row_index = smaug_i64_create(3);
    smaug_i64_set(row_index, 0, -7); smaug_i64_set(row_index, 1, 42); smaug_i64_set_null(row_index, 2);
    smaug_series_f64_t *to_float64_series = smaug_i64_to_f64(row_index);
    OK(to_float64_series != NULL, "i64->f64 retorna serie");
    OK(smaug_f64_get(to_float64_series, 0, NULL) == -7.0, "i64->f64 [0]=-7");
    OK(smaug_f64_get(to_float64_series, 1, NULL) == 42.0, "i64->f64 [1]=42");
    OK(smaug_f64_is_null(to_float64_series, 2),           "i64->f64 preserva null [2]");

    /* i64 -> dt (reinterpreta epoch_ms) */
    smaug_series_dt_t *to_datetime_series = smaug_i64_to_dt(row_index);
    OK(to_datetime_series != NULL, "i64->dt retorna serie");
    OK(smaug_dt_get(to_datetime_series, 1, NULL) == 42,  "i64->dt [1]=42 epoch");
    OK(smaug_dt_is_null(to_datetime_series, 2),          "i64->dt preserva null [2]");

    /* dt -> f64 */
    smaug_series_f64_t *source_series = smaug_dt_to_f64(to_datetime_series);
    OK(source_series != NULL, "dt->f64 retorna serie");
    OK(smaug_f64_get(source_series, 0, NULL) == -7.0, "dt->f64 [0]=-7");
    OK(smaug_f64_is_null(source_series, 2),           "dt->f64 preserva null [2]");

    smaug_i64_free(row_index); smaug_f64_free(to_float64_series); smaug_dt_free(to_datetime_series); smaug_f64_free(source_series);
}

/* ---------- Dirigido: exatidao acima de 2^53 (o conserto) ---------- */
static void test_exatidao_2e53(void) {
    /* dt -> i64: epoch_ms grande deve sair EXATO (get nativo int64);
       elemento nulo deve propagar (cobre o ramo null do SMAUG_VALID). */
    smaug_series_dt_t *source_series = smaug_dt_create(2);
    smaug_dt_set(source_series, 0, TWO53_PLUS_1);
    smaug_dt_set_null(source_series, 1);
    smaug_series_i64_t *row_index = smaug_dt_to_i64(source_series);
    OK(row_index != NULL, "dt->i64 retorna serie");
    OK(smaug_i64_get(row_index, 0, NULL) == TWO53_PLUS_1,
       "dt->i64 preserva 2^53+1 EXATO (nao 9007199254740992)");
    OK(smaug_i64_is_null(row_index, 1), "dt->i64 propaga null");

    /* i64 -> dt: o dominio aprovado exclui 2^53+1; nao arredondar para aceitar. */
    smaug_series_i64_t *integer_series = smaug_i64_create(1);
    smaug_i64_set(integer_series, 0, TWO53_PLUS_1);
    smaug_series_dt_t *to_datetime_series = smaug_i64_to_dt(integer_series);
    OK(to_datetime_series == NULL, "i64->dt rejeita 2^53+1 fora do dominio");

    smaug_dt_free(source_series); smaug_i64_free(row_index); smaug_i64_free(integer_series); smaug_dt_free(to_datetime_series);
}

/* ---------- Dirigido: f64 -> i64 trunc + inconversiveis -> null ---------- */
static void test_float64_int64_edge(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(8);
    smaug_f64_set(floating_point_series, 0,  3.7);        /* -> 3  (trunc direcao zero)  */
    smaug_f64_set(floating_point_series, 1, -3.7);        /* -> -3 (trunc direcao zero)  */
    smaug_f64_set(floating_point_series, 2,  NAN);        /* -> null                     */
    smaug_f64_set(floating_point_series, 3,  INFINITY);   /* -> null                     */
    smaug_f64_set(floating_point_series, 4, -INFINITY);   /* -> null                     */
    smaug_f64_set(floating_point_series, 5,  1e300);      /* -> null (fora do range i64) */
    smaug_f64_set(floating_point_series, 6, -1e300);      /* -> null (fora do range i64) */
    smaug_f64_set_null(floating_point_series, 7);         /* -> null (origem nula)       */

    smaug_series_i64_t *row_index = smaug_f64_to_i64(floating_point_series);
    OK(row_index != NULL, "f64->i64 retorna serie");
    OK(smaug_i64_get(row_index, 0, NULL) ==  3, "f64->i64 3.7 -> 3");
    OK(smaug_i64_get(row_index, 1, NULL) == -3, "f64->i64 -3.7 -> -3");
    OK(smaug_i64_is_null(row_index, 2), "f64->i64 NaN -> null");
    OK(smaug_i64_is_null(row_index, 3), "f64->i64 +inf -> null");
    OK(smaug_i64_is_null(row_index, 4), "f64->i64 -inf -> null");
    OK(smaug_i64_is_null(row_index, 5), "f64->i64 1e300 -> null (fora do range)");
    OK(smaug_i64_is_null(row_index, 6), "f64->i64 -1e300 -> null (fora do range)");
    OK(smaug_i64_is_null(row_index, 7), "f64->i64 origem nula -> null");

    /* Destino datetime tem contrato estrito: fracao nao e truncada. */
    smaug_series_dt_t *to_datetime_series = smaug_f64_to_dt(floating_point_series);
    OK(to_datetime_series == NULL, "f64->dt rejeita fracao sem resultado parcial");

    smaug_f64_free(floating_point_series); smaug_i64_free(row_index); smaug_dt_free(to_datetime_series);
}

/* ---------- Contrato: self==NULL -> NULL ---------- */
static void test_guard_null(void) {
    OK(smaug_i64_to_f64(NULL) == NULL, "i64->f64 guard self==NULL");
    OK(smaug_f64_to_i64(NULL) == NULL, "f64->i64 guard self==NULL");
    OK(smaug_i64_to_dt (NULL) == NULL, "i64->dt guard self==NULL");
    OK(smaug_dt_to_i64 (NULL) == NULL, "dt->i64 guard self==NULL");
    OK(smaug_f64_to_dt (NULL) == NULL, "f64->dt guard self==NULL");
    OK(smaug_dt_to_f64 (NULL) == NULL, "dt->f64 guard self==NULL");
    OK(smaug_i64_to_str(NULL) == NULL, "i64->str guard self==NULL");
    OK(smaug_f64_to_str(NULL) == NULL, "f64->str guard self==NULL");
    OK(smaug_dt_to_str (NULL) == NULL, "dt->str guard self==NULL");
    OK(smaug_str_to_i64(NULL) == NULL,    "str->i64 guard self==NULL");
    OK(smaug_str_to_f64(NULL) == NULL,    "str->f64 guard self==NULL");
    OK(smaug_str_to_dt (NULL, 0) == NULL, "str->dt guard self==NULL");
}

/* Compara o elemento i (nao-nulo) da serie string com uma C-string exata.
   str_get devolve ponteiro nao terminado em \0 + comprimento via out_len. */
static int string_equal(const smaug_series_str_t *source_series, size_t row_index, const char *expected_values) {
    size_t length; const char *string_get_result = smaug_str_get(source_series, row_index, &length);
    if (!string_get_result) return 0;
    size_t expected_length = strlen(expected_values);
    return length == expected_length && memcmp(string_get_result, expected_values, expected_length) == 0;
}

/* ---------- Grupo B-out: num/dt -> string ---------- */
static void test_outbound_conversions(void) {
    /* i64 -> str: %lld exato, incl. 2^53+1 (conserto) e null. */
    smaug_series_i64_t *row_index = smaug_i64_create(4);
    smaug_i64_set(row_index, 0, 42); smaug_i64_set(row_index, 1, -7);
    smaug_i64_set(row_index, 2, TWO53_PLUS_1); smaug_i64_set_null(row_index, 3);
    smaug_series_str_t *to_string_series = smaug_i64_to_str(row_index);
    OK(to_string_series != NULL, "i64->str retorna serie");
    OK(string_equal(to_string_series, 0, "42"),  "i64->str 42");
    OK(string_equal(to_string_series, 1, "-7"),  "i64->str -7");
    OK(string_equal(to_string_series, 2, "9007199254740993"),
       "i64->str 2^53+1 EXATO (nao cientifica)");
    OK(smaug_str_is_null(to_string_series, 3), "i64->str propaga null");

    /* f64 -> str: %.17g. Exatos tem forma previsivel; inexato via round-trip. */
    smaug_series_f64_t *floating_point_series = smaug_f64_create(5);
    smaug_f64_set(floating_point_series, 0, 0.5); smaug_f64_set(floating_point_series, 1, -7.0);
    smaug_f64_set(floating_point_series, 2, 100.25); smaug_f64_set(floating_point_series, 3, 3.14);
    smaug_f64_set_null(floating_point_series, 4);
    smaug_series_str_t *to_string_series_2 = smaug_f64_to_str(floating_point_series);
    OK(to_string_series_2 != NULL, "f64->str retorna serie");
    OK(string_equal(to_string_series_2, 0, "0.5"),    "f64->str 0.5");
    OK(string_equal(to_string_series_2, 1, "-7"),     "f64->str -7.0 -> -7");
    OK(string_equal(to_string_series_2, 2, "100.25"), "f64->str 100.25");
    /* round-trip: a string de 3.14 volta ao mesmo double */
    { size_t length; const char *string_get_result = smaug_str_get(to_string_series_2, 3, &length);
      char temporary_path[40]; memcpy(temporary_path, string_get_result, length); temporary_path[length] = '\0';
      OK(strtod(temporary_path, NULL) == 3.14, "f64->str 3.14 round-trip exato"); }
    OK(smaug_str_is_null(to_string_series_2, 4), "f64->str propaga null");

    /* dt -> str: ISO 8601 via dt_format (paridade por construcao). */
    smaug_series_dt_t *source_series = smaug_dt_create(2);
    smaug_dt_set(source_series, 0, 0);          /* epoch 0 = 1970-01-01T00:00:00.000Z */
    smaug_dt_set_null(source_series, 1);
    smaug_series_str_t *source_series_2 = smaug_dt_to_str(source_series);
    OK(source_series_2 != NULL, "dt->str retorna serie");
    OK(string_equal(source_series_2, 0, "1970-01-01T00:00:00.000Z"), "dt->str epoch 0 = ISO");
    OK(smaug_str_is_null(source_series_2, 1), "dt->str propaga null");

    /* series vazias: exercita o ramo size==0 do dimensionamento do buffer */
    smaug_series_i64_t *integer_series = smaug_i64_create(0);
    smaug_series_f64_t *floating_point_series_2 = smaug_f64_create(0);
    smaug_series_dt_t  *source_series_3 = smaug_dt_create(0);
    smaug_series_str_t *to_string_series_3 = smaug_i64_to_str(integer_series);
    smaug_series_str_t *to_string_series_4 = smaug_f64_to_str(floating_point_series_2);
    smaug_series_str_t *source_series_4 = smaug_dt_to_str(source_series_3);
    OK(to_string_series_3 && to_string_series_3->size == 0, "i64->str serie vazia");
    OK(to_string_series_4 && to_string_series_4->size == 0, "f64->str serie vazia");
    OK(source_series_4 && source_series_4->size == 0, "dt->str serie vazia");
    smaug_i64_free(integer_series); smaug_f64_free(floating_point_series_2); smaug_dt_free(source_series_3);
    smaug_str_free(to_string_series_3); smaug_str_free(to_string_series_4); smaug_str_free(source_series_4);

    smaug_i64_free(row_index); smaug_str_free(to_string_series);
    smaug_f64_free(floating_point_series); smaug_str_free(to_string_series_2);
    smaug_dt_free(source_series);  smaug_str_free(source_series_2);
}

/* cria uma serie string a partir de C-strings; NULL no array -> null. */
static smaug_series_str_t *make_string(const char *const *values, size_t element_count) {
    smaug_series_str_t *source_series = smaug_str_create(element_count);
    for (size_t row_index = 0; row_index < element_count; row_index++)
        if (values[row_index]) smaug_str_set(source_series, row_index, values[row_index], strlen(values[row_index]));
    return source_series;
}

/* ---------- Grupo B-in: string -> num/dt (parsing rigido) ---------- */
static void test_inbound_conversions(void) {
    /* str -> i64: rigido (strtoll base 10). */
    const char *text_values[] = {"42","  42","42 ","0x1A","3.7","9007199254740993","abc",NULL};
    smaug_series_str_t *source_series = make_string(text_values, 8);
    smaug_series_i64_t *row_index = smaug_str_to_i64(source_series);
    OK(row_index != NULL, "str->i64 retorna serie");
    OK(smaug_i64_get(row_index, 0, NULL) == 42, "str->i64 '42' -> 42");
    OK(smaug_i64_get(row_index, 1, NULL) == 42, "str->i64 '  42' leading ws ok");
    OK(smaug_i64_is_null(row_index, 2), "str->i64 '42 ' trailing ws -> null");
    OK(smaug_i64_is_null(row_index, 3), "str->i64 '0x1A' hex -> null");
    OK(smaug_i64_is_null(row_index, 4), "str->i64 '3.7' float -> null");
    OK(smaug_i64_get(row_index, 5, NULL) == TWO53_PLUS_1,
       "str->i64 2^53+1 EXATO (conserta o tonumber->double)");
    OK(smaug_i64_is_null(row_index, 6), "str->i64 'abc' -> null");
    OK(smaug_i64_is_null(row_index, 7), "str->i64 origem nula -> null");

    /* str -> f64: strtod (aceita hex/inf; rejeita overflow/trailing). */
    const char *text_values_2[] = {"3.14","0x1A","1e3","inf","1e400","3.14 ","abc",NULL};
    smaug_series_str_t *source_series_2 = make_string(text_values_2, 8);
    smaug_series_f64_t *source_series_3 = smaug_str_to_f64(source_series_2);
    OK(source_series_3 != NULL, "str->f64 retorna serie");
    OK(smaug_f64_get(source_series_3, 0, NULL) == 3.14,   "str->f64 '3.14'");
    OK(smaug_f64_get(source_series_3, 1, NULL) == 26.0,   "str->f64 '0x1A' hex -> 26 (strtod)");
    OK(smaug_f64_get(source_series_3, 2, NULL) == 1000.0, "str->f64 '1e3' -> 1000");
    OK(isinf(smaug_f64_get(source_series_3, 3, NULL)),    "str->f64 'inf' -> inf");
    OK(smaug_f64_is_null(source_series_3, 4), "str->f64 '1e400' overflow -> null");
    OK(smaug_f64_is_null(source_series_3, 5), "str->f64 '3.14 ' trailing ws -> null");
    OK(smaug_f64_is_null(source_series_3, 6), "str->f64 'abc' -> null");
    OK(smaug_f64_is_null(source_series_3, 7), "str->f64 origem nula -> null");

    /* str -> dt: ISO + null propaga; invalidos sao testados como erro abaixo. */
    const char *text_values_3[] = {"1970-01-01","1970-01-02",NULL};
    smaug_series_str_t *source_series_4 = make_string(text_values_3, 3);
    smaug_series_dt_t *source_series_5 = smaug_str_to_dt(source_series_4, 0);
    OK(source_series_5 != NULL, "str->dt retorna serie");
    OK(smaug_dt_get(source_series_5, 0, NULL) == 0, "str->dt '1970-01-01' -> epoch 0");
    OK(smaug_dt_get(source_series_5, 1, NULL) == 86400000, "str->dt dia seguinte");
    OK(smaug_dt_is_null(source_series_5, 2), "str->dt origem nula -> null");

    /* dayfirst propagado: '01/02/2003' muda conforme o flag. */
    const char *text_values_4[] = {"01/02/2003"};
    smaug_series_str_t *source_series_6 = make_string(text_values_4, 1);
    smaug_series_dt_t *source_series_7 = smaug_str_to_dt(source_series_6, 0);
    smaug_series_dt_t *source_series_8 = smaug_str_to_dt(source_series_6, 1);
    OK(smaug_dt_get(source_series_7, 0, NULL) != smaug_dt_get(source_series_8, 0, NULL),
       "str->dt dayfirst propagado (0 e 1 diferem)");

    smaug_str_free(source_series); smaug_i64_free(row_index);
    smaug_str_free(source_series_2); smaug_f64_free(source_series_3);
    smaug_str_free(source_series_4); smaug_dt_free(source_series_5);
    smaug_str_free(source_series_6); smaug_dt_free(source_series_7); smaug_dt_free(source_series_8);
}

/* ---------- fonte unica de parsing (smaug_convert) — teste direto ----------
   Cobre os ramos que o astype nunca alcanca: ptr NULL (defensivo), len==0
   (string vazia), len>=64 (nao-numero), e overflow (errno). */
static void test_convert_direto(void) {
    int64_t integer_value; double double_value;
    /* i64 — sucesso e cada ramo de rejeicao */
    OK(smaug_parse_i64("42", 2, &integer_value) == 1 && integer_value == 42, "parse_i64 '42' ok");
    OK(smaug_parse_i64(NULL, 2, &integer_value) == 0, "parse_i64 ptr NULL -> 0");
    OK(smaug_parse_i64("", 0, &integer_value) == 0,   "parse_i64 len 0 -> 0");
    { char source_values[80]; memset(source_values, '9', 79); source_values[79] = '\0';
      OK(smaug_parse_i64(source_values, 79, &integer_value) == 0, "parse_i64 len>=64 -> 0"); }
    OK(smaug_parse_i64("99999999999999999999", 20, &integer_value) == 0,
       "parse_i64 overflow (errno) -> 0");
    OK(smaug_parse_i64("42 ", 3, &integer_value) == 0, "parse_i64 trailing -> 0");

    /* f64 — sucesso e cada ramo de rejeicao */
    OK(smaug_parse_f64("3.14", 4, &double_value) == 1 && double_value == 3.14, "parse_f64 '3.14' ok");
    OK(smaug_parse_f64(NULL, 4, &double_value) == 0, "parse_f64 ptr NULL -> 0");
    OK(smaug_parse_f64("", 0, &double_value) == 0,   "parse_f64 len 0 -> 0");
    { char source_values[80]; memset(source_values, '9', 79); source_values[79] = '\0';
      OK(smaug_parse_f64(source_values, 79, &double_value) == 0, "parse_f64 len>=64 -> 0"); }
    OK(smaug_parse_f64("1e400", 5, &double_value) == 0, "parse_f64 overflow (errno) -> 0");
    OK(smaug_parse_f64("3.14 ", 5, &double_value) == 0, "parse_f64 trailing -> 0");

    /* núcleos _cstr (hot-path do CSV): NULL, vazio, sucesso, trailing */
    OK(smaug_parse_i64_cstr("42", &integer_value) == 1 && integer_value == 42, "parse_i64_cstr '42'");
    OK(smaug_parse_i64_cstr(NULL, &integer_value) == 0, "parse_i64_cstr NULL -> 0");
    OK(smaug_parse_i64_cstr("", &integer_value) == 0,   "parse_i64_cstr vazio -> 0");
    OK(smaug_parse_i64_cstr("1x", &integer_value) == 0, "parse_i64_cstr trailing -> 0");
    OK(smaug_parse_f64_cstr("3.14", &double_value) == 1 && double_value == 3.14, "parse_f64_cstr '3.14'");
    OK(smaug_parse_f64_cstr(NULL, &double_value) == 0, "parse_f64_cstr NULL -> 0");
    OK(smaug_parse_f64_cstr("", &double_value) == 0,   "parse_f64_cstr vazio -> 0");
    OK(smaug_parse_f64_cstr("1x", &double_value) == 0, "parse_f64_cstr trailing -> 0");
}

/* ---------- fonte única de formatação (smaug_fmt) — teste direto ----------
   Cobre i64, f64 finito (%.17g) e a normalização de não-finitos. */
static void test_fmt_direto(void) {
    char right_values[32];
    OK(smaug_fmt_i64(right_values, sizeof(right_values), 42) == 2 && strcmp(right_values, "42") == 0, "fmt_i64 42");
    OK(smaug_fmt_i64(right_values, sizeof(right_values), -7) == 2 && strcmp(right_values, "-7") == 0, "fmt_i64 -7");
    OK(smaug_fmt_i64(right_values, sizeof(right_values), TWO53_PLUS_1) == 16
       && strcmp(right_values, "9007199254740993") == 0, "fmt_i64 2^53+1 exato");
    OK(smaug_fmt_f64(right_values, sizeof(right_values), 1.5) == 3 && strcmp(right_values, "1.5") == 0, "fmt_f64 1.5");
    OK(smaug_fmt_f64(right_values, sizeof(right_values), 3.14) > 0
       && strcmp(right_values, "3.1400000000000001") == 0, "fmt_f64 3.14 -> %.17g");
    OK(smaug_fmt_f64(right_values, sizeof(right_values), NAN) == 3 && strcmp(right_values, "nan") == 0, "fmt_f64 NaN -> nan");
    OK(smaug_fmt_f64(right_values, sizeof(right_values), INFINITY) == 3 && strcmp(right_values, "inf") == 0, "fmt_f64 +inf -> inf");
    OK(smaug_fmt_f64(right_values, sizeof(right_values), -INFINITY) == 4 && strcmp(right_values, "-inf") == 0, "fmt_f64 -inf -> -inf");
}

static void test_strict_datetime(void) {
    const char *values[] = {"1970-01-01", NULL, "invalid", "also invalid"};
    smaug_series_str_t *source = make_string(values, 4);
    smaug_series_dt_t *original_output = smaug_dt_create(1);
    smaug_series_dt_t *output = original_output;
    size_t error_index = 77;
    OK(smaug_str_to_dt_checked(source, 0, &output, &error_index) == SMG_ERR_ARGUMENT,
       "str->dt invalido retorna status");
    OK(output == original_output && error_index == 2, "falha preserva out e aponta primeiro erro apos NA");
    OK(smaug_str_to_dt(source, 0) == NULL, "ABI legada tambem rejeita resultado parcial");
    OK(smaug_str_to_dt_checked(source, 0, &output, NULL) == SMG_ERR_ARGUMENT,
       "indice opcional");
    size_t text_length = 0;
    const char *original_text = smaug_str_get(source, 2, &text_length);
    OK(text_length == 7 && memcmp(original_text, "invalid", 7) == 0
       && smaug_str_is_null(source, 1), "entrada e mascara preservadas");
    error_index = 77;
    OK(smaug_str_to_dt_checked(NULL, 0, &output, &error_index) == SMG_ERR_ARGUMENT,
       "self obrigatorio");
    OK(smaug_str_to_dt_checked(source, 0, NULL, &error_index) == SMG_ERR_ARGUMENT,
       "out obrigatorio");
    OK(smaug_str_to_dt_checked(source, 2, &output, &error_index) == SMG_ERR_ARGUMENT,
       "dayfirst somente 0 ou 1");
    OK(output == original_output && error_index == 77, "argumentos invalidos preservam saidas");
    smaug_dt_free(original_output);
    smaug_str_free(source);

    const char *valid_values[] = {NULL, "1970-01-01", "1970-01-01T00:00:00.123000Z"};
    source = make_string(valid_values, 3);
    output = NULL;
    OK(smaug_str_to_dt_checked(source, 0, &output, &error_index) == SMG_OK, "conversao integral valida");
    OK(error_index == 77 && output->size == 3 && smaug_dt_is_null(output, 0)
       && smaug_dt_get(output, 1, NULL) == 0 && smaug_dt_get(output, 2, NULL) == 123,
       "sucesso preserva indice, NA e milissegundos exatos");
    smaug_dt_free(output);
    smaug_str_free(source);
    source = smaug_str_create(0);
    OK(smaug_str_to_dt_checked(source, 0, &output, &error_index) == SMG_OK
       && output->size == 0 && error_index == 77, "vazio e sucesso sem posicao de erro");
    smaug_dt_free(output);
    smaug_str_free(source);

    const struct { const char *text; int64_t expected; } valid[] = {
        {"0000-01-01", -62167219200000LL}, {"-000001-01-01", -62198755200000LL},
        {"-009999-01-01T00:00:00.000Z", -377705116800000LL},
        {"9999-12-31T23:59:59.999Z", 253402300799999LL},
        {"-009999-01-01T01:00:00+0100", -377705116800000LL},
        {"9999-12-31T22:59:59.999-01:00", 253402300799999LL},
        {"1970/01/01 03:00:00+03:00", 0}, {"01-02-1970", 86400000},
        {"1970-01-01T00:00:00.1", 100}, {"1970-01-01T00:00:00.12Z", 120},
        {"1970-01-01T00:00:00.1230000000Z", 123},
    };
    for (size_t case_index = 0; case_index < sizeof(valid) / sizeof(valid[0]); case_index++) {
        int64_t epoch_ms = 17;
        OK(smaug_dt_parse_checked(valid[case_index].text, strlen(valid[case_index].text), &epoch_ms, 0) == SMG_OK
           && epoch_ms == valid[case_index].expected, valid[case_index].text);
    }
    const char *invalid[] = {"", "1970", "1970-01", "1970-02-30", "1900-02-29",
        "-000000-01-01", "-1-01-01", "-000001/01/01", "1970-01/01",
        "1970-01-01T00:00:60Z", "1970-01-01T00:00:00.Z",
        "1970-01-01T00:00:00.123456Z", "1970-01-01T00:00:00.000001Z",
        "1970-01-01T00:00", "1970-01-01junk"};
    for (size_t case_index = 0; case_index < sizeof(invalid) / sizeof(invalid[0]); case_index++) {
        int64_t epoch_ms = 17;
        OK(smaug_dt_parse_checked(invalid[case_index], strlen(invalid[case_index]), &epoch_ms, 0) == SMG_ERR_ARGUMENT
           && epoch_ms == 17, invalid[case_index]);
    }
    const char *outside[] = {"-009999-01-01T00:00:59.999+00:01",
        "9999-12-31T23:59:00.000-00:01", "-010000-01-01"};
    for (size_t case_index = 0; case_index < sizeof(outside) / sizeof(outside[0]); case_index++) {
        const char *overflow_values[] = {NULL, "1970-01-01", outside[case_index]};
        source = make_string(overflow_values, 3);
        output = NULL;
        error_index = 77;
        OK(smaug_str_to_dt_checked(source, 0, &output, &error_index) == SMG_ERR_OVERFLOW
           && output == NULL && error_index == 2, "dominio UTC comunica status e posicao");
        smaug_str_free(source);
    }
    /* Buffer exato sem terminador: o parser deve respeitar len. */
    const char short_text[4] = {'1', '9', '7', '0'};
    int64_t epoch_ms = 17;
    OK(smaug_dt_parse_checked(short_text, sizeof(short_text), &epoch_ms, 0) == SMG_ERR_ARGUMENT
       && epoch_ms == 17, "buffer curto nao exige terminador");
}

static void test_numeric_datetime(void) {
    const int64_t valid_values[] = {-377705116800000LL, 253402300799999LL, -1, 0, 1};
    smaug_series_i64_t *integers = smaug_i64_create(6);
    smaug_series_f64_t *reals = smaug_f64_create(6);
    for (size_t row_index = 0; row_index < 5; row_index++) {
        smaug_i64_set(integers, row_index, valid_values[row_index]);
        smaug_f64_set(reals, row_index, (double)valid_values[row_index]);
    }
    smaug_series_dt_t *integer_output = NULL;
    smaug_series_dt_t *real_output = NULL;
    size_t error_index = 77;
    OK(smaug_i64_to_dt_checked(integers, &integer_output, &error_index) == SMG_OK,
       "i64->dt aceita limites inclusivos e epoch negativo");
    OK(smaug_f64_to_dt_checked(reals, &real_output, &error_index) == SMG_OK,
       "f64->dt aceita inteiros exatos inclusive limites");
    OK(integer_output->size == 6 && real_output->size == 6 && error_index == 77,
       "sucesso preserva indice e tamanho");
    for (size_t row_index = 0; row_index < 5; row_index++) {
        OK(smaug_dt_get(integer_output, row_index, NULL) == valid_values[row_index]
           && smaug_dt_get(real_output, row_index, NULL) == valid_values[row_index], "epoch exato");
    }
    OK(smaug_dt_is_null(integer_output, 5) && smaug_dt_is_null(real_output, 5), "NA preservado");
    smaug_dt_free(integer_output);
    smaug_dt_free(real_output);
    smaug_i64_free(integers);
    smaug_f64_free(reals);

    integers = smaug_i64_create(4);
    reals = smaug_f64_create(4);
    smaug_i64_set(integers, 0, 0);
    smaug_f64_set(reals, 0, 0);
    smaug_i64_set(integers, 3, INT64_MAX);
    smaug_f64_set(reals, 3, INFINITY);
    smaug_series_dt_t *original_output = smaug_dt_create(1);
    const int64_t invalid_integers[] = {-377705116800001LL, 253402300800000LL, INT64_MIN, INT64_MAX, TWO53_PLUS_1};
    for (size_t case_index = 0; case_index < sizeof(invalid_integers) / sizeof(invalid_integers[0]); case_index++) {
        smaug_i64_set(integers, 2, invalid_integers[case_index]);
        integer_output = original_output;
        error_index = 77;
        OK(smaug_i64_to_dt_checked(integers, &integer_output, &error_index) == SMG_ERR_OVERFLOW
           && error_index == 2 && integer_output == original_output, "i64 erro preserva out e aponta primeiro invalido");
        OK(smaug_i64_get(integers, 2, NULL) == invalid_integers[case_index]
           && smaug_i64_is_null(integers, 1), "i64 falha preserva entrada");
    }
    const struct { double value; smaug_status_t status; } invalid_reals[] = {
        {0.5, SMG_ERR_ARGUMENT}, {-0.5, SMG_ERR_ARGUMENT}, {0x1p-1074, SMG_ERR_ARGUMENT},
        {NAN, SMG_ERR_ARGUMENT}, {INFINITY, SMG_ERR_ARGUMENT}, {-INFINITY, SMG_ERR_ARGUMENT},
        {-377705116800001.0, SMG_ERR_OVERFLOW}, {253402300800000.0, SMG_ERR_OVERFLOW},
        {1e300, SMG_ERR_OVERFLOW}, {-1e300, SMG_ERR_OVERFLOW},
    };
    for (size_t case_index = 0; case_index < sizeof(invalid_reals) / sizeof(invalid_reals[0]); case_index++) {
        smaug_f64_set(reals, 2, invalid_reals[case_index].value);
        real_output = original_output;
        error_index = 77;
        OK(smaug_f64_to_dt_checked(reals, &real_output, &error_index) == invalid_reals[case_index].status
           && error_index == 2 && real_output == original_output, "f64 distingue precisao e dominio sem publicar out");
        double unchanged = smaug_f64_get(reals, 2, NULL);
        OK((unchanged == invalid_reals[case_index].value || (isnan(unchanged) && isnan(invalid_reals[case_index].value)))
           && smaug_f64_is_null(reals, 1), "f64 falha preserva valor e mascara");
    }
    error_index = 77;
    OK(smaug_i64_to_dt_checked(NULL, &integer_output, &error_index) == SMG_ERR_ARGUMENT
       && smaug_i64_to_dt_checked(integers, NULL, &error_index) == SMG_ERR_ARGUMENT,
       "i64 argumentos obrigatorios");
    OK(smaug_f64_to_dt_checked(NULL, &real_output, &error_index) == SMG_ERR_ARGUMENT
       && smaug_f64_to_dt_checked(reals, NULL, &error_index) == SMG_ERR_ARGUMENT,
       "f64 argumentos obrigatorios");
    OK(error_index == 77 && real_output == original_output && integer_output == original_output,
       "falha de chamada nao escreve saidas");
    OK(smaug_i64_to_dt_checked(integers, &integer_output, NULL) == SMG_ERR_OVERFLOW
       && smaug_f64_to_dt_checked(reals, &real_output, NULL) == SMG_ERR_OVERFLOW,
       "indice opcional em falha numerica");
    smaug_dt_free(original_output);
    smaug_i64_free(integers);
    smaug_f64_free(reals);
    for (size_t element_count = 0; element_count <= 2; element_count += 2) {
        integers = smaug_i64_create(element_count);
        reals = smaug_f64_create(element_count);
        OK(smaug_i64_to_dt_checked(integers, &integer_output, NULL) == SMG_OK
           && smaug_f64_to_dt_checked(reals, &real_output, NULL) == SMG_OK,
           "vazio e todo NA sao validos sem indice");
        OK(integer_output->size == element_count && real_output->size == element_count
           && smaug_dt_count_nonnull(integer_output) == 0 && smaug_dt_count_nonnull(real_output) == 0,
           "vazio e todo NA preservam conteudo");
        smaug_dt_free(integer_output);
        smaug_dt_free(real_output);
        smaug_i64_free(integers);
        smaug_f64_free(reals);
    }
}

int main(void) {
    test_numeric_datetime();
    test_strict_datetime();
    test_convert_direto();
    test_fmt_direto();
    test_basic_conversions();
    test_exatidao_2e53();
    test_float64_int64_edge();
    test_outbound_conversions();
    test_inbound_conversions();
    test_guard_null();
    printf("PASS: astype Grupos A+B-out+B-in (%d checks)\n", passed_checks);
    return 0;
}
