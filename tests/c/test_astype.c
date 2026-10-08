#ifndef _WIN32
#define _GNU_SOURCE
#endif
#include "../include/smaug.h"
#include <errno.h>
#include <float.h>
#include <fenv.h>
#include <locale.h>
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
    {
        size_t length = 0;
        const char *string_value = smaug_str_get(to_string_series_2, 3, &length);
        char numeric_text[40];
        OK(string_value != NULL && length < sizeof(numeric_text),
           "f64->str fornece texto que cabe no buffer do teste");
        memcpy(numeric_text, string_value, length);
        numeric_text[length] = '\0';
        char *parse_end = NULL;
        double parsed_value = strtod(numeric_text, &parse_end);
        OK(parsed_value == 3.14 && parse_end == numeric_text + length,
           "f64->str 3.14 round-trip exato e consumo completo");
    }
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
    /* str -> i64: gramática decimal/hexadecimal explícita. */
    const char *text_values[] = {"42","  42","42 ","0x1A","3.7","9007199254740993","abc",NULL};
    smaug_series_str_t *source_series = make_string(text_values, 8);
    smaug_series_i64_t *row_index = smaug_str_to_i64(source_series);
    OK(row_index != NULL, "str->i64 retorna serie");
    OK(smaug_i64_get(row_index, 0, NULL) == 42, "str->i64 '42' -> 42");
    OK(smaug_i64_is_null(row_index, 1), "str->i64 leading ws -> null");
    OK(smaug_i64_is_null(row_index, 2), "str->i64 '42 ' trailing ws -> null");
    OK(smaug_i64_get(row_index, 3, NULL) == 26, "str->i64 '0x1A' hex -> 26");
    OK(smaug_i64_is_null(row_index, 4), "str->i64 '3.7' float -> null");
    OK(smaug_i64_get(row_index, 5, NULL) == TWO53_PLUS_1,
       "str->i64 2^53+1 EXATO (conserta o tonumber->double)");
    OK(smaug_i64_is_null(row_index, 6), "str->i64 'abc' -> null");
    OK(smaug_i64_is_null(row_index, 7), "str->i64 origem nula -> null");

    /* str -> f64: gramática explícita (hex/inf; rejeita overflow/trailing). */
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
   (string vazia), token longo sem truncamento e overflow. */
static void test_convert_direto(void) {
    int64_t integer_value; double double_value;
    /* i64 — sucesso e cada ramo de rejeicao */
    OK(smaug_parse_i64("42", 2, &integer_value) == 1 && integer_value == 42, "parse_i64 '42' ok");
    OK(smaug_parse_i64(NULL, 2, &integer_value) == 0, "parse_i64 ptr NULL -> 0");
    OK(smaug_parse_i64("", 0, &integer_value) == 0,   "parse_i64 len 0 -> 0");
    { char source_values[80]; memset(source_values, '0', 79); source_values[78] = '1'; source_values[79] = '\0';
      OK(smaug_parse_i64(source_values, 79, &integer_value) == 1 && integer_value == 1,
         "parse_i64 token longo sem truncar"); }
    OK(smaug_parse_i64("99999999999999999999", 20, &integer_value) == 0,
       "parse_i64 overflow (errno) -> 0");
    OK(smaug_parse_i64("42 ", 3, &integer_value) == 0, "parse_i64 trailing -> 0");

    /* f64 — sucesso e cada ramo de rejeicao */
    OK(smaug_parse_f64("3.14", 4, &double_value) == 1 && double_value == 3.14, "parse_f64 '3.14' ok");
    OK(smaug_parse_f64(NULL, 4, &double_value) == 0, "parse_f64 ptr NULL -> 0");
    OK(smaug_parse_f64("", 0, &double_value) == 0,   "parse_f64 len 0 -> 0");
    { char source_values[80]; memset(source_values, '0', 79); source_values[78] = '1'; source_values[79] = '\0';
      OK(smaug_parse_f64(source_values, 79, &double_value) == 1 && double_value == 1.0,
         "parse_f64 token longo sem truncar"); }
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

/* Diagnósticos do core: o valor anterior nunca é sobrescrito em falha. */
static void test_convert_diagnosticos(void) {
    int64_t integer_output = 77;
    double real_output = 77.0;
    OK(smaug_parse_i64_status("0x1A", 4, &integer_output) == SMG_OK && integer_output == 26,
       "status i64 hexadecimal inteiro");
    integer_output = 77;
    OK(smaug_parse_i64_status("9223372036854775808", 19, &integer_output) == SMG_ERR_OVERFLOW
       && integer_output == 77, "status i64 overflow preserva saída");
    integer_output = 77;
    OK(smaug_parse_i64_status("1.0", 3, &integer_output) == SMG_ERR_SYNTAX
       && integer_output == 77, "status i64 fração é sintaxe");
    OK(smaug_parse_i64_status(NULL, 1, &integer_output) == SMG_ERR_ARGUMENT,
       "status i64 texto NULL é argumento");

    real_output = 77.0;
    OK(smaug_parse_f64_status("0x1p-1074", 9, &real_output) == SMG_OK
       && real_output > 0.0 && real_output < DBL_MIN, "status f64 subnormal representável");
    real_output = 77.0;
    OK(smaug_parse_f64_status("1e-400", 6, &real_output) == SMG_ERR_UNDERFLOW
       && real_output == 77.0, "status f64 underflow preserva saída");
    real_output = 77.0;
    OK(smaug_parse_f64_status("0x1p-1075", 9, &real_output) == SMG_ERR_UNDERFLOW
       && real_output == 77.0, "status f64 underflow hexadecimal");
    real_output = 77.0;
    OK(smaug_parse_f64_status("0e-400", 6, &real_output) == SMG_OK
       && real_output == 0.0, "status f64 zero textual não é underflow");
    real_output = 77.0;
    OK(smaug_parse_f64_status("1e400", 5, &real_output) == SMG_ERR_OVERFLOW
       && real_output == 77.0, "status f64 overflow preserva saída");
    real_output = 77.0;
    OK(smaug_parse_f64_status("nan(payload)", 12, &real_output) == SMG_ERR_SYNTAX
       && real_output == 77.0, "status f64 payload NaN é sintaxe");
}

/* Casos exatos não dependem da precisão intermediária de double. */
static void test_integer_syntax_and_hex_boundaries(void) {
    const struct {
        const char *text;
        smaug_status_t status;
        int64_t expected;
    } cases[] = {
        {"0x7fffffffffffffff", SMG_OK, INT64_MAX},
        {"-0x8000000000000000", SMG_OK, INT64_MIN},
        {"+0X0007FFFFFFFFFFFFFFF", SMG_OK, INT64_MAX},
        {"0x8000000000000000", SMG_ERR_OVERFLOW, 77},
        {"-0x8000000000000001", SMG_ERR_OVERFLOW, 77},
        {"0xffffffffffffffffffffffff", SMG_ERR_OVERFLOW, 77},
        {"9223372036854775808x", SMG_ERR_SYNTAX, 77},
        {"-9223372036854775809 ", SMG_ERR_SYNTAX, 77},
        {"0xffffffffffffffffffffffffg", SMG_ERR_SYNTAX, 77},
        {"0x8000000000000000p0", SMG_ERR_SYNTAX, 77},
        {"0x", SMG_ERR_SYNTAX, 77},
        {"-0x", SMG_ERR_SYNTAX, 77},
        {"+", SMG_ERR_SYNTAX, 77}
    };
    for (size_t case_index = 0; case_index < sizeof(cases) / sizeof(cases[0]); case_index++) {
        int64_t output = 77;
        OK(smaug_parse_i64_cstr_status(cases[case_index].text, &output)
           == cases[case_index].status && output == cases[case_index].expected,
           "i64 cstr: sintaxe integral e fronteiras hex exatas");
        output = 77;
        OK(smaug_parse_i64_status(cases[case_index].text,
           strlen(cases[case_index].text), &output) == cases[case_index].status
           && output == cases[case_index].expected,
           "i64 slice: sintaxe integral e fronteiras hex exatas");
    }
}

static void test_float_grammar(void) {
    const struct { const char *text; double expected; } valid[] = {
        {".5", 0.5}, {"1.", 1.0}, {"1.e2", 100.0}, {"0x10", 16.0},
        {"-0X1A", -26.0}, {"0x.8", 0.5}, {"0x1.p2", 4.0}, {"0x1e2", 482.0}
    };
    const char *invalid[] = {
        ".", "0x", "0x.p1", "1e", "1e+", "0x1p+", "0xp1", "0x1p1.5",
        "nan(x)", "infinite", "inf0", "1e400x", "0x1p99999x", "1_000", "0b1", "1,5"
    };
    for (size_t case_index = 0; case_index < sizeof(valid) / sizeof(valid[0]); case_index++) {
        double output = 77.0;
        OK(smaug_parse_f64_cstr_status(valid[case_index].text, &output) == SMG_OK
           && output == valid[case_index].expected, "gramática f64 válida: cstr e valor exato");
        output = 77.0;
        OK(smaug_parse_f64_status(valid[case_index].text,
           strlen(valid[case_index].text), &output) == SMG_OK
           && output == valid[case_index].expected, "gramática f64 válida: slice e valor exato");
    }
    for (size_t case_index = 0; case_index < sizeof(invalid) / sizeof(invalid[0]); case_index++) {
        double output = 77.0;
        OK(smaug_parse_f64_cstr_status(invalid[case_index], &output) == SMG_ERR_SYNTAX
           && output == 77.0, "gramática f64 inválida: cstr preserva saída");
        OK(smaug_parse_f64_status(invalid[case_index], strlen(invalid[case_index]), &output)
           == SMG_ERR_SYNTAX && output == 77.0, "gramática f64 inválida: slice preserva saída");
    }
}

static void test_float_rounding_modes(void) {
    int original_rounding = fegetround();
    OK(original_rounding != -1, "modo de arredondamento disponível");
    const int modes[] = {FE_TONEAREST, FE_TOWARDZERO, FE_UPWARD, FE_DOWNWARD};
    const char *overflow_tokens[] = {"1e400", "-1e400", "0x1p1024", "-0x1p1024"};
    for (size_t mode_index = 0; mode_index < sizeof(modes) / sizeof(modes[0]); mode_index++) {
        OK(fesetround(modes[mode_index]) == 0, "seleciona modo de arredondamento");
        for (size_t token_index = 0;
             token_index < sizeof(overflow_tokens) / sizeof(overflow_tokens[0]); token_index++) {
            double output = 77.0;
            OK(smaug_parse_f64_cstr_status(overflow_tokens[token_index], &output)
               == SMG_ERR_OVERFLOW && output == 77.0,
               "overflow dirigido não pode passar como DBL_MAX");
        }
        double output = 77.0;
        OK(smaug_parse_f64_cstr_status("0x1.fffffffffffffp1023", &output) == SMG_OK
           && output == DBL_MAX, "DBL_MAX exato é válido em todos os modos");
        OK(smaug_parse_f64_cstr_status("0x1p-1074", &output) == SMG_OK
           && output == DBL_TRUE_MIN, "menor subnormal exato preservado");
        const char *boundary_token = "0x1.fffffffffffffp-1023";
        /* Ponto medio exato: nearest/upward -> DBL_MIN; zero/downward -> anterior. */
        double expected_boundary =
            (modes[mode_index] == FE_TONEAREST || modes[mode_index] == FE_UPWARD)
            ? DBL_MIN : 0x0.fffffffffffffp-1022;
        output = 77.0;
        smaug_status_t boundary_status =
            smaug_parse_f64_cstr_status(boundary_token, &output);
        if (boundary_status != SMG_OK || output != expected_boundary) {
            fprintf(stderr,
                    "diagnostico subnormal: modo=%d status=%d saida=%a esperado=%a\n",
                    modes[mode_index], (int)boundary_status, output, expected_boundary);
#ifdef _WIN32
            /* Probe temporario apos a falha: nao altera o ambiente da chamada sob teste. */
            _locale_t numeric_locale = _create_locale(LC_NUMERIC, "C");
            if (numeric_locale != NULL) {
                char *parse_end = NULL;
                errno = 0;
                double raw_value = _strtod_l(boundary_token, &parse_end, numeric_locale);
                int saved_errno = errno;
                fprintf(stderr,
                        "probe CRT: modo=%d valor=%a errno=%d consumidos=%td\n",
                        fegetround(), raw_value, saved_errno,
                        parse_end != NULL ? parse_end - boundary_token : (ptrdiff_t)-1);
                _free_locale(numeric_locale);
            } else {
                fprintf(stderr, "probe CRT: falha ao criar locale C\n");
            }
#endif
        }
        OK(boundary_status == SMG_OK && output == expected_boundary,
           "fronteira subnormal respeita resultado exato por modo de arredondamento");
        output = 77.0;
        smaug_status_t status = smaug_parse_f64_cstr_status("1e-400", &output);
        if (modes[mode_index] == FE_UPWARD) {
            OK(status == SMG_OK && output == DBL_TRUE_MIN,
               "arredondamento para subnormal preserva magnitude");
        } else {
            OK(status == SMG_ERR_UNDERFLOW && output == 77.0,
               "arredondamento para zero tem diagnóstico e preserva saída");
        }
        OK(smaug_parse_f64_cstr_status("-0e-9999", &output) == SMG_OK
           && output == 0.0 && signbit(output), "zero textual negativo preservado");
        OK(fegetround() == modes[mode_index], "parser preserva modo do caller");
    }
    OK(fesetround(original_rounding) == 0, "restaura modo de arredondamento");
}

/* Oraculos hex exatos; zero/inf na tabela indicam underflow/overflow esperado. */
static void check_hex_rounding(const char *token, double expected_value) {
    smaug_status_t expected_status = expected_value == 0.0 ? SMG_ERR_UNDERFLOW :
        (isinf(expected_value) ? SMG_ERR_OVERFLOW : SMG_OK);
    double output = 77.0;
    OK(smaug_parse_f64_cstr_status(token, &output) == expected_status &&
       output == (expected_status == SMG_OK ? expected_value : 77.0),
       "hex cstr: arredondamento exato e saida preservada");
    output = 77.0;
    OK(smaug_parse_f64_status(token, strlen(token), &output) == expected_status &&
       output == (expected_status == SMG_OK ? expected_value : 77.0),
       "hex slice: arredondamento exato e saida preservada");
}

static void test_hex_rounding_regressions(void) {
    const int modes[] = {FE_TONEAREST, FE_TOWARDZERO, FE_UPWARD, FE_DOWNWARD};
    const struct { const char *token; double expected[4]; } cases[] = {
        {"0x1.00000000000008p0", {1.0, 1.0, 0x1.0000000000001p0, 1.0}},
        {"0x1.00000000000008001p0",
         {0x1.0000000000001p0, 1.0, 0x1.0000000000001p0, 1.0}},
        {"0x1.00000000000018p0",
         {0x1.0000000000002p0, 0x1.0000000000001p0,
          0x1.0000000000002p0, 0x1.0000000000001p0}},
        {"0x0.8p-1074", {0.0, 0.0, DBL_TRUE_MIN, 0.0}},
        {"0x0.80000000000000001p-1074", {DBL_TRUE_MIN, 0.0, DBL_TRUE_MIN, 0.0}},
        {"0x0.7ffffffffffffffffp-1074", {0.0, 0.0, DBL_TRUE_MIN, 0.0}},
        {"0x1.8p-1074", {0x1p-1073, DBL_TRUE_MIN, 0x1p-1073, DBL_TRUE_MIN}},
        {"0x1.fffffffffffffp-1023",
         {DBL_MIN, 0x0.fffffffffffffp-1022, DBL_MIN, 0x0.fffffffffffffp-1022}},
        {"0x1p-999999999999999999999999", {0.0, 0.0, DBL_TRUE_MIN, 0.0}},
        {"0x1p999999999999999999999999", {INFINITY, INFINITY, INFINITY, INFINITY}},
        {"0x1.fffffffffffff8p1023", {INFINITY, DBL_MAX, INFINITY, DBL_MAX}},
        {"0x000.004p+3", {0x1p-7, 0x1p-7, 0x1p-7, 0x1p-7}},
    };
    int original_rounding = fegetround();
    OK(original_rounding != -1, "hex: salva arredondamento");
    for (size_t mode_index = 0; mode_index < 4; mode_index++) {
        OK(fesetround(modes[mode_index]) == 0, "hex: seleciona arredondamento");
        for (size_t case_index = 0; case_index < sizeof(cases) / sizeof(cases[0]);
             case_index++) {
            check_hex_rounding(cases[case_index].token, cases[case_index].expected[mode_index]);
            char negative_token[128];
            int length = snprintf(negative_token, sizeof(negative_token), "-%s",
                                  cases[case_index].token);
            OK(length > 0 && (size_t)length < sizeof(negative_token), "hex: fixture negativa");
            size_t opposite_mode = mode_index == 2 ? 3 : (mode_index == 3 ? 2 : mode_index);
            check_hex_rounding(negative_token, -cases[case_index].expected[opposite_mode]);
        }
        char long_token[1100];
        memcpy(long_token, "0x1", 3);
        memset(long_token + 3, '0', 1000);
        memcpy(long_token + 1003, "p-4000", 7);
        check_hex_rounding(long_token, 1.0);
        memcpy(long_token, "0x0.", 4);
        memset(long_token + 4, '0', 1000);
        memcpy(long_token + 1004, "1p4004", 7);
        check_hex_rounding(long_token, 1.0);
        const char *halfway_prefix = "0x1.00000000000008";
        size_t prefix_length = strlen(halfway_prefix);
        memcpy(long_token, halfway_prefix, prefix_length);
        memset(long_token + prefix_length, '0', 1000);
        memcpy(long_token + prefix_length + 1000, "1p0", 4);
        check_hex_rounding(long_token, (mode_index == 0 || mode_index == 2)
                           ? 0x1.0000000000001p0 : 1.0);
        double output = 77.0;
        OK(smaug_parse_f64_cstr_status("-0x0p999999999999999999999999", &output) == SMG_OK
           && output == 0.0 && signbit(output), "hex: zero negativo com expoente enorme");
        output = 77.0;
        OK(smaug_parse_f64_cstr_status("0x1p999999999999999999999999x", &output)
           == SMG_ERR_SYNTAX && output == 77.0, "hex: sintaxe prevalece sobre expoente enorme");
        OK(fegetround() == modes[mode_index], "hex: preserva arredondamento");
    }
    OK(fesetround(original_rounding) == 0, "hex: restaura arredondamento");
}

/* O comprimento inclui conteudo, nunca um terminador implicito. */
static void test_numeric_slice_contract(void) {
    const struct { const char *text; size_t length; } invalid_slices[] = {
        {"\0" "123", 4}, {"123\0abc", 7}, {"123\0", 4},
        {NULL, 3}, {"", 0}, {"42 ", 3}, {"+", 1}, {" ", 1},
        {"1e", 2}, {"1e400", 5}
    };
    for (size_t case_index = 0; case_index < sizeof(invalid_slices) / sizeof(invalid_slices[0]); case_index++) {
        int64_t integer_output = 77;
        double real_output = 77;
        OK(!smaug_parse_i64(invalid_slices[case_index].text, invalid_slices[case_index].length, &integer_output)
           && integer_output == 77, "slice i64 invalido preserva saida");
        OK(!smaug_parse_f64(invalid_slices[case_index].text, invalid_slices[case_index].length, &real_output)
           && real_output == 77, "slice f64 invalido preserva saida");
    }
    char unterminated[] = {'1', '2', '3'};
    int64_t integer_output = 77;
    double real_output = 77;
    OK(smaug_parse_i64(unterminated, sizeof(unterminated), &integer_output) && integer_output == 123,
       "slice i64 sem terminador");
    OK(smaug_parse_f64(unterminated, sizeof(unterminated), &real_output) && real_output == 123,
       "slice f64 sem terminador");
    OK(smaug_parse_i64("123\0abc", 3, &integer_output) && integer_output == 123,
       "NUL externo nao pertence ao slice i64");
    OK(smaug_parse_f64("123\0abc", 3, &real_output) && real_output == 123,
       "NUL externo nao pertence ao slice f64");
    for (size_t length = 63; length <= 65; length++) {
        char leading_zeroes[66];
        memset(leading_zeroes, '0', length);
        leading_zeroes[length - 1] = '1';
        leading_zeroes[length] = '\0';
        integer_output = 77; real_output = 77;
        OK(smaug_parse_i64(leading_zeroes, length, &integer_output) && integer_output == 1,
           "slice i64 aceita token longo sem truncar");
        OK(smaug_parse_f64(leading_zeroes, length, &real_output) && real_output == 1,
           "slice f64 aceita token longo sem truncar");
        OK(smaug_parse_i64_cstr(leading_zeroes, &integer_output) && integer_output == 1,
           "cstr i64 preserva tokens longos");
        OK(smaug_parse_f64_cstr(leading_zeroes, &real_output) && real_output == 1,
           "cstr f64 preserva tokens longos");
    }
    const struct { const char *text; int valid; int64_t expected; } boundaries[] = {
        {"9223372036854775807", 1, INT64_MAX}, {"-9223372036854775808", 1, INT64_MIN},
        {"9223372036854775808", 0, 77}, {"-9223372036854775809", 0, 77}
    };
    for (size_t case_index = 0; case_index < sizeof(boundaries) / sizeof(boundaries[0]); case_index++) {
        integer_output = 77;
        OK(smaug_parse_i64(boundaries[case_index].text, strlen(boundaries[case_index].text), &integer_output)
           == boundaries[case_index].valid && integer_output == boundaries[case_index].expected,
           "fronteira i64 exata com saida preservada em falha");
    }
    OK(!smaug_parse_i64("1", 1, NULL), "slice i64 rejeita saida NULL");
    OK(!smaug_parse_f64("1", 1, NULL), "slice f64 rejeita saida NULL");
    OK(!smaug_parse_i64_cstr("1", NULL), "cstr i64 rejeita saida NULL");
    OK(!smaug_parse_f64_cstr("1", NULL), "cstr f64 rejeita saida NULL");
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

static void check_format_roundtrip(void) {
    const double values[] = {0.0, -0.0, 1.5, 0.1, DBL_MAX, -DBL_MAX, DBL_MIN,
                             DBL_TRUE_MIN, -DBL_TRUE_MIN, 0x1.fffffffffffffp-1};
    char buffer[32];
    OK(smaug_fmt_f64(buffer, sizeof(buffer), 1.5) == 3 && strcmp(buffer, "1.5") == 0,
       "formatter usa ponto independentemente do locale");
    for (size_t value_index = 0; value_index < sizeof(values) / sizeof(values[0]); value_index++) {
        size_t length = smaug_fmt_f64(buffer, sizeof(buffer), values[value_index]);
        OK(length > 0 && length == strlen(buffer), "formatter publica comprimento real");
        double parsed = 77.0;
        OK(smaug_parse_f64_status(buffer, length, &parsed) == SMG_OK
           && parsed == values[value_index]
           && !!signbit(parsed) == !!signbit(values[value_index]),
           "formatter roundtrip exato incluindo subnormal e zero negativo");
    }
    OK(smaug_fmt_i64(buffer, sizeof(buffer), INT64_MIN) == 20
       && strcmp(buffer, "-9223372036854775808") == 0, "formatter INT64_MIN exato");
    OK(smaug_fmt_i64(buffer, sizeof(buffer), INT64_MAX) == 19
       && strcmp(buffer, "9223372036854775807") == 0, "formatter INT64_MAX exato");
}

static void test_format_capacity_and_locale(void) {
    const double values[] = {1.5, -0.0, DBL_MAX, NAN, INFINITY, -INFINITY};
    char expected[32];
    char output[32];
    char sentinel[32];
    memset(sentinel, '#', sizeof(sentinel));
    for (size_t value_index = 0; value_index < sizeof(values) / sizeof(values[0]); value_index++) {
        size_t length = smaug_fmt_f64(expected, sizeof(expected), values[value_index]);
        OK(length > 0, "formatter baseline");
        for (size_t capacity = 0; capacity <= length; capacity++) {
            memcpy(output, sentinel, sizeof(output));
            OK(smaug_fmt_f64(output, capacity, values[value_index]) == 0
               && memcmp(output, sentinel, sizeof(output)) == 0,
               "formatter buffer curto preserva todos os bytes");
        }
        memcpy(output, sentinel, sizeof(output));
        OK(smaug_fmt_f64(output, length + 1, values[value_index]) == length
           && memcmp(output, expected, length + 1) == 0 && output[length + 1] == '#',
           "formatter capacidade exata inclui NUL sem ultrapassar");
    }
    for (size_t capacity = 0; capacity <= 20; capacity++) {
        memcpy(output, sentinel, sizeof(output));
        OK(smaug_fmt_i64(output, capacity, INT64_MIN) == 0
           && memcmp(output, sentinel, sizeof(output)) == 0,
           "formatter i64 curto não anuncia sucesso truncado");
    }
    OK(smaug_fmt_i64(NULL, 32, 1) == 0 && smaug_fmt_f64(NULL, 32, 1.5) == 0,
       "formatter rejeita destino NULL");
    int original_rounding = fegetround();
    OK(original_rounding != -1 && fesetround(FE_TONEAREST) == 0, "roundtrip em nearest");
    const char *current_locale = setlocale(LC_NUMERIC, NULL);
    char saved_locale[256];
    OK(current_locale != NULL && strlen(current_locale) < sizeof(saved_locale),
       "salva locale numérico original");
    strcpy(saved_locale, current_locale);
    OK(setlocale(LC_NUMERIC, "C") != NULL, "seleciona locale C");
    check_format_roundtrip();
    const char *comma_locale = setlocale(LC_NUMERIC, "pt_BR.utf8");
#ifdef _WIN32
    if (!comma_locale) {
        comma_locale = setlocale(LC_NUMERIC, "Portuguese_Brazil.1252");
    }
#endif
    if (comma_locale) {
        check_format_roundtrip();
        OK(strcmp(localeconv()->decimal_point, ",") == 0,
           "formatter restaura locale global do caller");
#ifndef _WIN32
        locale_t thread_locale = newlocale(LC_NUMERIC_MASK, "pt_BR.utf8", (locale_t)0);
        OK(thread_locale != (locale_t)0, "cria locale de thread");
        OK(setlocale(LC_NUMERIC, "C") != NULL, "global C distinto da thread");
        locale_t previous_locale = uselocale(thread_locale);
        OK(previous_locale != (locale_t)0, "instala locale de thread");
        check_format_roundtrip();
        OK(uselocale((locale_t)0) == thread_locale,
           "formatter restaura objeto locale da thread");
        OK(uselocale(previous_locale) != (locale_t)0, "restaura thread do teste");
        freelocale(thread_locale);
#endif
    } else {
        fprintf(stderr, "SKIP: locale decimal com vírgula indisponível\n");
    }
    OK(setlocale(LC_NUMERIC, saved_locale) != NULL, "restaura locale original");
    OK(fesetround(original_rounding) == 0, "restaura arredondamento original");
}

int main(void) {
    test_numeric_datetime();
    test_strict_datetime();
    test_numeric_slice_contract();
    test_convert_direto();
    test_convert_diagnosticos();
    test_integer_syntax_and_hex_boundaries();
    test_float_rounding_modes();
    test_hex_rounding_regressions();
    test_float_grammar();
    test_fmt_direto();
    test_format_capacity_and_locale();
    test_basic_conversions();
    test_exatidao_2e53();
    test_float64_int64_edge();
    test_outbound_conversions();
    test_inbound_conversions();
    test_guard_null();
    printf("PASS: astype Grupos A+B-out+B-in (%d checks)\n", passed_checks);
    return 0;
}
