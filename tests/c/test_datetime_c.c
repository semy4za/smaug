/* tests/test_datetime_c.c
 *
 * Testes C do dtype datetime (smaug_datetime.c).
 * Cobre: lifecycle, parse ISO 8601, componentes calendário,
 * aritmética, comparações, sort, seleção, datas negativas (pré-1970),
 * anos bissextos, COW e fronteiras defensivas.
 */

#define _POSIX_C_SOURCE 200809L
#include "../include/smaug_datetime.h"
#include "../include/smaug_core.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

static int passed_checks = 0, failed_checks = 0;

#define CHECK(condition, message) do { \
    if (condition) { passed_checks++; } \
    else { fprintf(stderr, "FALHOU [%d]: %s\n", __LINE__, message); failed_checks++; } \
} while(0)

/* epoch_ms de datas conhecidas para ancoragem */
/* 2026-06-13T14:30:00.000Z = ? ms */
/* verificado: 1970 + 56*365.25*86400*1000 ≈ não vamos calcular, usamos parse */

static int64_t parse(const char *text_value) {
    int64_t epoch_milliseconds = 0;
    int parse_result = smaug_dt_parse(text_value, strlen(text_value), &epoch_milliseconds, 0);
    if (parse_result != 0) {
        fprintf(stderr, "parse inesperado falhou para: %s\n", text_value);
        abort();
    }
    return epoch_milliseconds;
}

/* ===================================================================
   Lifecycle
   =================================================================== */

static void test_lifecycle(void) {
    /* create / free NULL-safe */
    smaug_dt_free(NULL);
    passed_checks++;

    /* create com size=0 */
    smaug_series_dt_t *source_series = smaug_dt_create(0);
    CHECK(source_series != NULL,    "create(0): não NULL");
    CHECK(source_series->size == 0, "create(0): size=0");
    smaug_dt_free(source_series);

    /* create normal */
    smaug_series_dt_t *source_series_2 = smaug_dt_create(4);
    CHECK(source_series_2 != NULL,           "create(4): não NULL");
    CHECK(source_series_2->size == 4,        "create(4): size=4");
    CHECK(source_series_2->capacity >= 4,    "create(4): capacity>=4");
    CHECK(!strcmp(source_series_2->meta.dtype, "datetime"), "dtype='datetime'");

    /* todos nulos por padrão */
    for (size_t row_index = 0; row_index < 4; row_index++)
        CHECK(smaug_dt_is_null(source_series_2, row_index), "criado nulo");

    /* set / get */
    int64_t epoch_milliseconds = parse("2026-06-13T00:00:00Z");
    CHECK(smaug_dt_set(source_series_2, 0, epoch_milliseconds) == SMG_OK, "set OK");
    smaug_status_t status;
    int64_t element_value = smaug_dt_get(source_series_2, 0, &status);
    CHECK(status == SMG_OK && element_value == epoch_milliseconds, "get após set");

    /* set_null */
    CHECK(smaug_dt_set_null(source_series_2, 0) == SMG_OK, "set_null OK");
    smaug_dt_get(source_series_2, 0, &status);
    CHECK(status == SMG_NULL_VALUE, "get após set_null = NULL_VALUE");

    /* OOB */
    CHECK(smaug_dt_set(source_series_2, 10, epoch_milliseconds)  == SMG_ERR_OOB, "set OOB");
    CHECK(smaug_dt_set_null(source_series_2, 10) == SMG_ERR_OOB, "set_null OOB");
    smaug_dt_get(source_series_2, 10, &status);
    CHECK(status == SMG_ERR_OOB, "get OOB → SMG_ERR_OOB");

    /* NULL pointer — 12.18: guards de fronteira publica sao TESTADOS, nao
       excluidos da metrica. O smaug_core.c (f64) fecha 100% de branch-alvo
       exatamente por cobrir estes casos; o dt tinha os mesmos guards sem teste,
       e o registro original pedia COV-EXCL-BR — o que esconderia um ramo
       alcancavel em vez de exercita-lo. */
    CHECK(smaug_dt_set(NULL, 0, epoch_milliseconds) == SMG_ERR_ARGUMENT, "set NULL ptr");
    CHECK(smaug_dt_is_null(NULL, 0) == true, "is_null NULL ptr = true");
    CHECK(smaug_dt_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "set_null NULL ptr");
    CHECK(smaug_dt_append_null(NULL) == -1, "append_null NULL ptr -> -1");
    /* get(NULL) com status NAO-nulo: exercita o `if (status)` DENTRO do
       `if (!s)`. O caso status=NULL ja existe (test_get_null_status); sem este,
       o ramo verdadeiro do if interno nunca era tomado. */
    smaug_status_t null_status = SMG_OK;
    smaug_dt_get(NULL, 0, &null_status);
    CHECK(null_status == SMG_ERR_ARGUMENT, "get NULL ptr com status -> SMG_ERR_ARGUMENT");

    smaug_dt_free(source_series_2);
}

static void test_clone(void) {
    smaug_series_dt_t *source_series = smaug_dt_create(2);
    int64_t epoch_milliseconds = parse("2026-01-01T00:00:00Z");
    smaug_dt_set(source_series, 0, epoch_milliseconds);
    /* s[1] permanece NULL */

    smaug_series_dt_t *source_series_2 = smaug_dt_clone(source_series);
    CHECK(source_series_2 != NULL,                    "clone não NULL");
    CHECK(source_series_2->size == 2,                 "clone size=2");
    smaug_status_t status;
    CHECK(smaug_dt_get(source_series_2, 0, &status) == epoch_milliseconds && status == SMG_OK, "clone val[0]");
    CHECK(smaug_dt_is_null(source_series_2, 1),       "clone null[1]");

    /* independência: mudar clone não afeta original */
    smaug_dt_set(source_series_2, 0, epoch_milliseconds + 1000);
    CHECK(smaug_dt_get(source_series, 0, &status) == epoch_milliseconds, "clone independente");

    smaug_dt_free(source_series);
    smaug_dt_free(source_series_2);

    /* clone NULL */
    CHECK(smaug_dt_clone(NULL) == NULL, "clone NULL → NULL");
}

static void test_view_cow(void) {
    smaug_series_dt_t *source_series = smaug_dt_create(4);
    int64_t epoch_milliseconds = parse("2026-06-13T00:00:00Z");
    for (size_t row_index = 0; row_index < 4; row_index++) smaug_dt_set(source_series, row_index, epoch_milliseconds + (int64_t)row_index * 86400000LL);

    /* view */
    smaug_series_dt_t *source_series_2 = smaug_dt_view(source_series, 1, 2);
    CHECK(source_series_2 != NULL,            "view não NULL");
    CHECK(source_series_2->size == 2,         "view size=2");
    CHECK(source_series_2->meta.is_view,      "view is_view=true");
    smaug_status_t status;
    int64_t element_value = smaug_dt_get(source_series_2, 0, &status);
    CHECK(status == SMG_OK && element_value == epoch_milliseconds + 86400000LL, "view val[0]");

    /* COW: mutação na view não afeta a pai */
    smaug_dt_set(source_series_2, 0, epoch_milliseconds + 999000LL);
    CHECK(smaug_dt_get(source_series, 1, &status) == epoch_milliseconds + 86400000LL, "COW: pai intacta");
    CHECK(!source_series_2->meta.is_view, "COW: view deixou de ser view");

    /* view fora dos limites */
    CHECK(smaug_dt_view(source_series, 10, 1) == NULL, "view OOB → NULL");
    CHECK(smaug_dt_view(NULL, 0, 1) == NULL, "view NULL → NULL");

    smaug_dt_free(source_series);
    smaug_dt_free(source_series_2);
}

static void test_append(void) {
    smaug_series_dt_t *source_series = smaug_dt_create(0);
    int64_t epoch_milliseconds = parse("2026-01-01T00:00:00Z");

    /* append 5 elementos — força dt_grow (capacity inicial 0) */
    for (int row_index = 0; row_index < 5; row_index++) {
        CHECK(smaug_dt_append(source_series, epoch_milliseconds + (int64_t)row_index * 86400000LL) == 0, "append OK");
    }
    CHECK(source_series->size == 5, "append size=5");
    CHECK(smaug_dt_append_null(source_series) == 0, "append_null OK");
    CHECK(source_series->size == 6, "append_null size=6");
    CHECK(smaug_dt_is_null(source_series, 5), "append_null[5] é null");

    CHECK(smaug_dt_append(NULL, 0) == -1, "append NULL → -1");

    smaug_dt_free(source_series);
}

static void test_create_from_array(void) {
    int64_t source_values[] = {0LL, 86400000LL, 172800000LL};
    smaug_series_dt_t *source_series = smaug_dt_create_from_array(source_values, 3);
    CHECK(source_series != NULL,         "from_array não NULL");
    CHECK(source_series->size == 3,      "from_array size=3");
    smaug_status_t status;
    CHECK(smaug_dt_get(source_series, 1, &status) == 86400000LL, "from_array val[1]");
    CHECK(!smaug_dt_is_null(source_series, 0), "from_array todos válidos");
    smaug_dt_free(source_series);

    CHECK(smaug_dt_create_from_array(NULL, 3) == NULL, "from_array NULL → NULL");
}

/* ===================================================================
   Parse ISO 8601
   =================================================================== */

static void test_parse(void) {
    int64_t epoch_milliseconds = 0;

    /* epoch: 1970-01-01 */
    CHECK(smaug_dt_parse("1970-01-01T00:00:00Z", 20, &epoch_milliseconds, 0) == 0, "parse epoch");
    CHECK(epoch_milliseconds == 0, "epoch = 0");

    /* só data (meia-noite UTC) */
    CHECK(smaug_dt_parse("1970-01-02", 10, &epoch_milliseconds, 0) == 0, "parse só data");
    CHECK(epoch_milliseconds == 86400000LL, "só data = 1 dia em ms");

    /* com milissegundos */
    CHECK(smaug_dt_parse("1970-01-01T00:00:00.500Z", 24, &epoch_milliseconds, 0) == 0, "parse com ms");
    CHECK(epoch_milliseconds == 500, "500 ms");

    /* com offset +03:00 */
    CHECK(smaug_dt_parse("1970-01-01T03:00:00+03:00", 25, &epoch_milliseconds, 0) == 0, "parse +03:00");
    CHECK(epoch_milliseconds == 0, "UTC=0 com offset +03:00");

    /* com offset -05:30 */
    CHECK(smaug_dt_parse("1970-01-01T00:00:00-05:30", 25, &epoch_milliseconds, 0) == 0, "parse -05:30");
    CHECK(epoch_milliseconds == (5*60+30)*60*1000LL, "-05:30 → UTC+19800000ms");

    /* data negativa: 1969-12-31 = -1 dia */
    CHECK(smaug_dt_parse("1969-12-31T00:00:00Z", 20, &epoch_milliseconds, 0) == 0, "parse pré-1970");
    CHECK(epoch_milliseconds == -86400000LL, "1969-12-31 = -1 dia");

    /* formato inválido */
    CHECK(smaug_dt_parse("abc", 3, &epoch_milliseconds, 0) == -1, "parse inválido");
    CHECK(smaug_dt_parse("2026-13-01", 10, &epoch_milliseconds, 0) == -1, "mês 13 inválido");
    CHECK(smaug_dt_parse("2026-02-30", 10, &epoch_milliseconds, 0) == -1, "fev 30 inválido");
    CHECK(smaug_dt_parse("2026-06-13T25:00:00Z", 20, &epoch_milliseconds, 0) == -1, "hora 25 inválida");
    CHECK(smaug_dt_parse(NULL, 0, &epoch_milliseconds, 0) == -1, "parse NULL");
    CHECK(smaug_dt_parse("2026-06-13T00:00:00Z", 20, NULL, 0) == -1, "out NULL");

    /* com lixo no final */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00ZLIXO", 24, &epoch_milliseconds, 0) == -1, "lixo no final");

    /* separador '/' (H.6.4): mesma ordem YYYY/MM/DD, não-ambíguo */
    int64_t epoch_slash = 0, epoch_dash = 0;
    CHECK(smaug_dt_parse("2026/06/13", 10, &epoch_slash, 0) == 0, "parse com / (só data)");
    CHECK(smaug_dt_parse("2026-06-13", 10, &epoch_dash, 0) == 0,  "parse com - (referência)");
    CHECK(epoch_slash == epoch_dash, "/ e - produzem o mesmo epoch (equivalência)");

    /* '/' com hora: separador de data muda, hora continua ':' */
    CHECK(smaug_dt_parse("2026/06/13T14:30:00Z", 20, &epoch_milliseconds, 0) == 0, "parse / com hora");
    int64_t epoch_reference = parse("2026-06-13T14:30:00Z");
    CHECK(epoch_milliseconds == epoch_reference, "/ com hora = - com hora");

    /* consistência: separador misturado é rejeitado (sem meia-boca) */
    CHECK(smaug_dt_parse("2026-06/13", 10, &epoch_milliseconds, 0) == -1, "separador misturado -/ rejeitado");
    CHECK(smaug_dt_parse("2026/06-13", 10, &epoch_milliseconds, 0) == -1, "separador misturado /- rejeitado");

    /* '/' não afrouxa validação: mês/dia inválidos continuam barrados */
    CHECK(smaug_dt_parse("2026/13/01", 10, &epoch_milliseconds, 0) == -1, "/ mês 13 ainda inválido");
    CHECK(smaug_dt_parse("2026/02/30", 10, &epoch_milliseconds, 0) == -1, "/ fev 30 ainda inválido");

    /* H.5.a — dayfirst (year-last DD/MM/YYYY vs MM/DD/YYYY) */
    int64_t epoch_dataset = 0;

    /* year-first ignora dayfirst (ordem não-ambígua) */
    int64_t first_year = 0, second_year = 0;
    CHECK(smaug_dt_parse("2026-06-13", 10, &first_year, 0) == 0, "year-first df=0 ok");
    CHECK(smaug_dt_parse("2026-06-13", 10, &second_year, 1) == 0, "year-first df=1 ok");
    CHECK(first_year == second_year, "year-first: dayfirst não altera resultado");

    /* dayfirst=0 (MM/DD): 06/13 ok, 13/06 rejeitado (falha visível) */
    CHECK(smaug_dt_parse("06/13/2026", 10, &epoch_dataset, 0) == 0,  "MM/DD 06/13 (df=0) ok");
    CHECK(smaug_dt_parse("13/06/2026", 10, &epoch_dataset, 0) == -1, "MM/DD 13/06 (df=0) → mês 13 rejeitado");

    /* dayfirst=1 (DD/MM): 13/06 ok, 06/13 rejeitado */
    CHECK(smaug_dt_parse("13/06/2026", 10, &epoch_dataset, 1) == 0,  "DD/MM 13/06 (df=1) ok");
    CHECK(smaug_dt_parse("06/13/2026", 10, &epoch_dataset, 1) == -1, "DD/MM 06/13 (df=1) → mês 13 rejeitado");

    /* equivalência: 13/06/2026 df=1 == 2026-06-13 */
    smaug_dt_parse("13/06/2026", 10, &epoch_dataset, 1);
    CHECK(epoch_dataset == parse("2026-06-13"), "DD/MM 13/06/2026 (df=1) == ISO 2026-06-13");

    /* 1-2 dígitos: 5/6/2026 (teu caso real) */
    smaug_dt_parse("5/6/2026", 8, &epoch_dataset, 1);
    CHECK(epoch_dataset == parse("2026-06-05"), "5/6/2026 (df=1) = 5 de junho");
    smaug_dt_parse("5/6/2026", 8, &epoch_dataset, 0);
    CHECK(epoch_dataset == parse("2026-05-06"), "5/6/2026 (df=0) = 6 de maio");

    /* year-last com hora e com separador '-' */
    CHECK(smaug_dt_parse("13/06/2026 14:30:00", 19, &epoch_dataset, 1) == 0, "year-last DD/MM com hora ok");
    CHECK(epoch_dataset == parse("2026-06-13T14:30:00"), "13/06/2026 14:30 (df=1) = ISO equivalente");
    CHECK(smaug_dt_parse("13-06-2026", 10, &epoch_dataset, 1) == 0, "year-last com '-' (df=1) ok");

    /* ano-no-fim exige 4 dígitos; 2 dígitos rejeitado */
    CHECK(smaug_dt_parse("13/06/26", 8, &epoch_dataset, 1) == -1, "year-last ano 2 dígitos rejeitado");

    /* cobertura dos caminhos de erro do parser de data (year-last/year-first) */
    CHECK(smaug_dt_parse("", 0, &epoch_dataset, 1) == -1,           "string vazia rejeitada");
    CHECK(smaug_dt_parse("/06/2026", 8, &epoch_dataset, 1) == -1,   "year-last sem 1º campo (não-dígito) rejeitado");
    CHECK(smaug_dt_parse("13//2026", 8, &epoch_dataset, 1) == -1,   "year-last sem 2º campo rejeitado");
    CHECK(smaug_dt_parse("13/06/", 6, &epoch_dataset, 1) == -1,     "year-last sem ano rejeitado");
    CHECK(smaug_dt_parse("13:06:2026", 10, &epoch_dataset, 1) == -1,"year-last separador ':' inválido rejeitado");
    CHECK(smaug_dt_parse("1/2/2026", 8, &epoch_dataset, 1) == 0,    "year-last 1 dígito em ambos (1/2) ok");
    CHECK(smaug_dt_parse("202X-06-13", 10, &epoch_milliseconds, 0) == -1,   "year-first ano com não-dígito rejeitado");
    CHECK(smaug_dt_parse("2026-6-13", 9, &epoch_milliseconds, 0) == -1,     "year-first mês 1 dígito ainda rejeitado (escopo)");
}

static void test_format(void) {
    char buffer[26];
    CHECK(smaug_dt_format(0, buffer, 26) == 0, "format epoch OK");
    CHECK(strcmp(buffer, "1970-01-01T00:00:00.000Z") == 0, "format epoch string");

    CHECK(smaug_dt_format(500, buffer, 26) == 0, "format 500ms OK");
    CHECK(strcmp(buffer, "1970-01-01T00:00:00.500Z") == 0, "format 500ms string");

    /* buffer pequeno */
    char small[10];
    CHECK(smaug_dt_format(0, small, 10) == -1, "format buf pequeno");
    CHECK(smaug_dt_format(0, NULL, 26) == -1, "format NULL buf");

    /* roundtrip: parse → format */
    int64_t epoch_milliseconds = parse("2026-06-13T14:30:00.123Z");
    CHECK(smaug_dt_format(epoch_milliseconds, buffer, 26) == 0, "roundtrip format OK");
    CHECK(strcmp(buffer, "2026-06-13T14:30:00.123Z") == 0, "roundtrip string");
}

/* ===================================================================
   Componentes calendário
   =================================================================== */

static void test_components(void) {
    int64_t epoch_milliseconds = parse("2026-06-13T14:30:45.123Z");

    CHECK(smaug_dt_year(epoch_milliseconds)    == 2026, "year=2026");
    CHECK(smaug_dt_month(epoch_milliseconds)   == 6,    "month=6");
    CHECK(smaug_dt_day(epoch_milliseconds)     == 13,   "day=13");
    CHECK(smaug_dt_hour(epoch_milliseconds)    == 14,   "hour=14");
    CHECK(smaug_dt_minute(epoch_milliseconds)  == 30,   "minute=30");
    CHECK(smaug_dt_second(epoch_milliseconds)  == 45,   "second=45");
    CHECK(smaug_dt_ms(epoch_milliseconds)      == 123,  "ms=123");
    CHECK(smaug_dt_quarter(epoch_milliseconds) == 2,    "quarter=2 (junho)");

    /* 2026-06-13 é sábado = weekday 5 (0=seg) */
    CHECK(smaug_dt_weekday(epoch_milliseconds) == 5, "weekday=5 (sáb)");

    /* Datas antes de 1970 */
    int64_t epoch_negative = parse("1969-12-31T12:00:00Z");
    CHECK(smaug_dt_year(epoch_negative)   == 1969, "1969 year");
    CHECK(smaug_dt_month(epoch_negative)  == 12,   "1969 month=12");
    CHECK(smaug_dt_day(epoch_negative)    == 31,   "1969 day=31");
    CHECK(smaug_dt_hour(epoch_negative)   == 12,   "1969 hour=12");

    /* Ano bissexto: 2024-02-29 existe */
    int64_t leap_day_epoch = parse("2024-02-29T00:00:00Z");
    CHECK(smaug_dt_year(leap_day_epoch)  == 2024, "bissexto year=2024");
    CHECK(smaug_dt_month(leap_day_epoch) == 2,    "bissexto month=2");
    CHECK(smaug_dt_day(leap_day_epoch)   == 29,   "bissexto day=29");

    /* 2024 não é bissexto em 100 anos mas divide 4: bissexto normal */
    /* 1900 não é bissexto (divisível por 100, não por 400) */
    CHECK(smaug_dt_parse("1900-02-29", 10, &epoch_negative, 0) == -1, "1900 não bissexto");
    /* 2000 é bissexto (divisível por 400) */
    int64_t year_2000_epoch = parse("2000-02-29T00:00:00Z");
    CHECK(smaug_dt_day(year_2000_epoch) == 29, "2000 é bissexto");

    /* yearday */
    int64_t january_first_epoch = parse("2026-01-01T00:00:00Z");
    CHECK(smaug_dt_yearday(january_first_epoch) == 1, "1 jan = yearday 1");
    int64_t dec31 = parse("2026-12-31T00:00:00Z");
    CHECK(smaug_dt_yearday(dec31) == 365, "31 dez = yearday 365");

    /* quarter */
    CHECK(smaug_dt_quarter(parse("2026-01-01T00:00:00Z")) == 1, "Q1 jan");
    CHECK(smaug_dt_quarter(parse("2026-04-01T00:00:00Z")) == 2, "Q2 abr");
    CHECK(smaug_dt_quarter(parse("2026-07-01T00:00:00Z")) == 3, "Q3 jul");
    CHECK(smaug_dt_quarter(parse("2026-10-01T00:00:00Z")) == 4, "Q4 out");
}

/* ===================================================================
   from_parts
   =================================================================== */

static void test_from_parts(void) {
    /* deve ser igual ao parse */
    int64_t epoch_parse = parse("2026-06-13T14:30:45.123Z");
    int64_t epoch_parts = smaug_dt_from_parts(2026, 6, 13, 14, 30, 45, 123);
    CHECK(epoch_parse == epoch_parts, "from_parts == parse");

    /* data inválida */
    CHECK(smaug_dt_from_parts(2026, 13,  1, 0, 0, 0, 0) == INT64_MIN, "mês 13 inválido");
    CHECK(smaug_dt_from_parts(2026,  2, 30, 0, 0, 0, 0) == INT64_MIN, "fev 30 inválido");
    CHECK(smaug_dt_from_parts(2026,  6, 13, 25, 0, 0, 0) == INT64_MIN, "hora 25 inválida");
    CHECK(smaug_dt_from_parts(2026,  6, 13, 14, 60, 0, 0) == INT64_MIN, "minuto 60 inválido");

    /* data pré-1970 */
    int64_t epoch_negative = smaug_dt_from_parts(1969, 12, 31, 0, 0, 0, 0);
    CHECK(epoch_negative == -86400000LL, "1969-12-31 from_parts");
}

/* ===================================================================
   Aritmética
   =================================================================== */

static void test_arithmetic(void) {
    int64_t epoch_milliseconds = parse("2026-06-13T00:00:00Z");

    /* diff_ms */
    int64_t second_epoch = parse("2026-06-14T00:00:00Z");
    CHECK(smaug_dt_diff_ms(second_epoch, epoch_milliseconds) == 86400000LL, "diff = 1 dia");
    CHECK(smaug_dt_diff_ms(epoch_milliseconds, second_epoch) == -86400000LL, "diff negativo");

    /* add_ms */
    int64_t add_milliseconds_result = smaug_dt_add_ms(epoch_milliseconds, 86400000LL);
    CHECK(add_milliseconds_result == second_epoch, "add_ms 1 dia");
    int64_t add_milliseconds_result_2 = smaug_dt_add_ms(epoch_milliseconds, -86400000LL);
    CHECK(smaug_dt_day(add_milliseconds_result_2) == 12, "add_ms negativo = 12");

    /* truncate */
    int64_t with_time = parse("2026-06-13T14:30:45.123Z");

    /* segundo */
    int64_t second_timestamp = smaug_dt_truncate(with_time, 's');
    CHECK(smaug_dt_ms(second_timestamp) == 0 && smaug_dt_second(second_timestamp) == 45, "truncate segundo");

    /* minuto */
    int64_t minimum_timestamp = smaug_dt_truncate(with_time, 'm');
    CHECK(smaug_dt_second(minimum_timestamp) == 0 && smaug_dt_minute(minimum_timestamp) == 30, "truncate minuto");

    /* hora */
    int64_t truncate_result = smaug_dt_truncate(with_time, 'h');
    CHECK(smaug_dt_minute(truncate_result) == 0 && smaug_dt_hour(truncate_result) == 14, "truncate hora");

    /* dia */
    int64_t truncate_result_2 = smaug_dt_truncate(with_time, 'D');
    CHECK(smaug_dt_hour(truncate_result_2) == 0 && smaug_dt_day(truncate_result_2) == 13, "truncate dia");

    /* semana (segunda-feira anterior) */
    int64_t truncate_result_3 = smaug_dt_truncate(with_time, 'W');
    CHECK(smaug_dt_weekday(truncate_result_3) == 0, "truncate semana = segunda");
    CHECK(smaug_dt_day(truncate_result_3) == 8, "truncate semana = 8 jun (segunda anterior a 13 jun sáb)");

    /* mês */
    int64_t truncate_result_4 = smaug_dt_truncate(with_time, 'M');
    CHECK(smaug_dt_day(truncate_result_4) == 1 && smaug_dt_month(truncate_result_4) == 6, "truncate mês");

    /* trimestre */
    int64_t truncate_result_5 = smaug_dt_truncate(with_time, 'Q');
    CHECK(smaug_dt_month(truncate_result_5) == 4 && smaug_dt_day(truncate_result_5) == 1, "truncate trimestre Q2→abr");

    /* ano */
    int64_t truncate_result_6 = smaug_dt_truncate(with_time, 'Y');
    CHECK(smaug_dt_month(truncate_result_6) == 1 && smaug_dt_day(truncate_result_6) == 1, "truncate ano");

    /* unidade inválida */
    CHECK(smaug_dt_truncate(with_time, 'X') == INT64_MIN, "truncate X inválido");

    /* truncate de data negativa (pré-1970) */
    int64_t negative = parse("1969-12-31T14:30:00Z");
    int64_t negative_day_timestamp = smaug_dt_truncate(negative, 'D');
    CHECK(smaug_dt_day(negative_day_timestamp) == 31 && smaug_dt_hour(negative_day_timestamp) == 0, "truncate dia negativo");
}

/* ===================================================================
   Comparações
   =================================================================== */

static void test_comparisons(void) {
    int64_t dates[] = {
        parse("2026-01-01T00:00:00Z"),
        parse("2026-06-13T00:00:00Z"),
        parse("2026-12-31T00:00:00Z"),
    };
    smaug_series_dt_t *source_series = smaug_dt_create_from_array(dates, 3);

    int64_t reference = parse("2026-06-13T00:00:00Z");
    smaug_mask_t *mask = NULL;

    uint8_t *greater_than_mask = smaug_dt_gt(source_series, reference, &mask);
    CHECK(greater_than_mask != NULL,        "gt retorna array");
    CHECK(greater_than_mask[0] == 0,        "gt[0]=false (jan < jun)");
    CHECK(greater_than_mask[1] == 0,        "gt[1]=false (jun == jun)");
    CHECK(greater_than_mask[2] == 1,        "gt[2]=true (dez > jun)");
    CHECK(mask[0] == 0xFF,   "gt mask válida");
    smaug_free(greater_than_mask); smaug_free(mask);

    uint8_t *less_than_mask = smaug_dt_lt(source_series, reference, &mask);
    CHECK(less_than_mask[0] == 1, "lt[0]=true"); CHECK(less_than_mask[2] == 0, "lt[2]=false");
    smaug_free(less_than_mask); smaug_free(mask);

    uint8_t *equality_mask = smaug_dt_eq(source_series, reference, &mask);
    CHECK(equality_mask[0] == 0, "eq[0]=false"); CHECK(equality_mask[1] == 1, "eq[1]=true");
    smaug_free(equality_mask); smaug_free(mask);

    uint8_t *greater_or_equal_mask = smaug_dt_ge(source_series, reference, &mask);
    CHECK(greater_or_equal_mask[1] == 1, "ge[1]=true"); CHECK(greater_or_equal_mask[0] == 0, "ge[0]=false");
    smaug_free(greater_or_equal_mask); smaug_free(mask);

    uint8_t *less_or_equal_mask = smaug_dt_le(source_series, reference, &mask);
    CHECK(less_or_equal_mask[2] == 0, "le[2]=false"); CHECK(less_or_equal_mask[1] == 1, "le[1]=true");
    smaug_free(less_or_equal_mask); smaug_free(mask);

    uint8_t *inequality_mask = smaug_dt_ne(source_series, reference, &mask);
    CHECK(inequality_mask[1] == 0, "ne[1]=false"); CHECK(inequality_mask[0] == 1, "ne[0]=true");
    smaug_free(inequality_mask); smaug_free(mask);

    /* NULL propaga nas comparações */
    smaug_dt_set_null(source_series, 1);
    uint8_t *greater_than_mask_2 = smaug_dt_gt(source_series, reference, &mask);
    CHECK(mask[1] == 0x00, "gt null: mask=0x00");
    CHECK(greater_than_mask_2[1] == 0,     "gt null: valor=0");
    smaug_free(greater_than_mask_2); smaug_free(mask);

    /* NULL série */
    CHECK(smaug_dt_gt(NULL, reference, &mask) == NULL, "gt NULL série → NULL");

    /* between (10.2 fatia 2): mesma matriz de ramos dos comparadores.
       A série `s` deste bloco tem nulo — ver a montagem acima. */
    CHECK(smaug_dt_between(NULL, 0, 10, true, true, NULL) == NULL,
          "between NULL série → NULL");

    uint8_t *between_result = smaug_dt_between(source_series, INT64_MIN, INT64_MAX, true, true, NULL);
    CHECK(between_result != NULL, "between sem out_mask");            /* ramo out_mask==NULL */
    smaug_free(between_result);

    mask = NULL;
    between_result = smaug_dt_between(source_series, INT64_MIN, INT64_MAX, true, true, &mask);
    CHECK(between_result != NULL && mask != NULL, "between com out_mask");
    smaug_free(between_result); smaug_free(mask);

    /* os quatro modos, com os limites nas pontas: só o inc muda o resultado */
    int64_t element_value = smaug_dt_get(source_series, 0, NULL);
    uint8_t *comparison_values;
    comparison_values = smaug_dt_between(source_series, element_value, element_value, true,  true,  NULL);
    CHECK(comparison_values && comparison_values[0] == 1, "between both inclui a ponta");   smaug_free(comparison_values);
    comparison_values = smaug_dt_between(source_series, element_value, element_value, false, false, NULL);
    CHECK(comparison_values && comparison_values[0] == 0, "between neither exclui a ponta"); smaug_free(comparison_values);
    comparison_values = smaug_dt_between(source_series, element_value, INT64_MAX, true,  true, NULL);
    CHECK(comparison_values && comparison_values[0] == 1, "between left inclui a inferior");  smaug_free(comparison_values);
    comparison_values = smaug_dt_between(source_series, element_value, INT64_MAX, false, true, NULL);
    CHECK(comparison_values && comparison_values[0] == 0, "between left exclusivo exclui");   smaug_free(comparison_values);

    /* inc_hi no ramo FALSO precisa que a condicao de lo passe primeiro: em
       `A && B`, se A e falso o B nem e avaliado (curto-circuito). Com lo bem
       abaixo e hi exatamente no valor, inc_hi=false decide sozinho. */
    comparison_values = smaug_dt_between(source_series, INT64_MIN, element_value, true, false, NULL);
    CHECK(comparison_values && comparison_values[0] == 0, "between hi exclusivo avalia o ramo falso");
    smaug_free(comparison_values);

    /* curto-circuito do &&: com lo acima de tudo, a condicao da esquerda e
       falsa e a da direita NAO e avaliada. Sem este caso o ramo fica
       descoberto, porque todo teste anterior passa pela esquerda. */
    comparison_values = smaug_dt_between(source_series, INT64_MAX, INT64_MAX, true, true, NULL);
    CHECK(comparison_values && comparison_values[0] == 0, "between curto-circuita quando lo nao passa");
    smaug_free(comparison_values);

    /* --- 10.4 fatia A: componentes em versao de SERIE -------------------
       Sao 11 funcoes geradas por macro, mas cada instanciacao tem corpo
       proprio: cobrir uma NAO cobre as outras dez. Tabela em vez de 11
       blocos iguais -- mesmo motivo de a implementacao ser macro. */
    {
        typedef smaug_series_i64_t *(*compfn)(const smaug_series_dt_t *);
        struct { const char *nome; compfn fn; } comps[] = {
            {"year", smaug_dt_year_series},   {"month", smaug_dt_month_series},
            {"day", smaug_dt_day_series},     {"hour", smaug_dt_hour_series},
            {"minute", smaug_dt_minute_series},{"second", smaug_dt_second_series},
            {"ms", smaug_dt_ms_series},       {"weekday", smaug_dt_weekday_series},
            {"yearday", smaug_dt_yearday_series},{"quarter", smaug_dt_quarter_series},
            {"week", smaug_dt_week_series},
        };
        /* serie com um nulo no meio: exercita os dois ramos de SMAUG_VALID */
        smaug_series_dt_t *source_series_2 = smaug_dt_create(3);
        smaug_dt_set(source_series_2, 0, 0);            /* 1970-01-01 */
        smaug_dt_set_null(source_series_2, 1);
        smaug_dt_set(source_series_2, 2, 1735689600000LL); /* 2025-01-01 */

        for (size_t element_index = 0; element_index < sizeof(comps)/sizeof(comps[0]); element_index++) {
            CHECK(comps[element_index].fn(NULL) == NULL, "componente NULL série → NULL");

            smaug_series_i64_t *source_series_3 = comps[element_index].fn(source_series_2);
            CHECK(source_series_3 != NULL, "componente devolve série");
            CHECK(SMAUG_VALID(source_series_3->null_mask, 0), "componente preserva válido");
            CHECK(SMAUG_NULL(source_series_3->null_mask, 1),  "componente propaga nulo");
            smaug_i64_free(source_series_3);

            /* serie vazia nao estoura */
            smaug_series_dt_t *source_series_4 = smaug_dt_create(0);
            smaug_series_i64_t *source_series_5 = comps[element_index].fn(source_series_4);
            CHECK(source_series_5 != NULL, "componente em série vazia");
            smaug_i64_free(source_series_5); smaug_dt_free(source_series_4);
        }
        /* valores conferidos contra a escalar, que ja e testada acima */
        smaug_series_i64_t *source_series_3 = smaug_dt_year_series(source_series_2);
        CHECK(source_series_3->data[0] == 1970 && source_series_3->data[2] == 2025, "year_series confere");
        smaug_i64_free(source_series_3);
        smaug_series_i64_t *source_series_4 = smaug_dt_quarter_series(source_series_2);
        CHECK(source_series_4->data[2] == 1, "quarter_series confere");
        smaug_i64_free(source_series_4);
        smaug_dt_free(source_series_2);
    }

    /* série vazia */
    smaug_series_dt_t *vazia = smaug_dt_create(0);
    CHECK(vazia != NULL, "dt create(0) para between");
    uint8_t *between_result_2 = smaug_dt_between(vazia, 0, 10, true, true, NULL);
    CHECK(between_result_2 != NULL, "between em série vazia não estoura");
    smaug_free(between_result_2);
    smaug_dt_free(vazia);

    smaug_dt_free(source_series);
}

/* ===================================================================
   Ordenação e seleção
   =================================================================== */

static void test_sort_take_filter(void) {
    int64_t dates[] = {
        parse("2026-12-31T00:00:00Z"),
        parse("2026-01-01T00:00:00Z"),
        parse("2026-06-13T00:00:00Z"),
    };
    smaug_series_dt_t *source_series = smaug_dt_create_from_array(dates, 3);

    /* argsort asc */
    size_t *indices = smaug_dt_argsort(source_series, true);
    CHECK(indices != NULL, "argsort não NULL");
    CHECK(indices[0] == 1, "argsort asc [0]=jan");
    CHECK(indices[1] == 2, "argsort asc [1]=jun");
    CHECK(indices[2] == 0, "argsort asc [2]=dez");
    smaug_free(indices);

    /* argsort desc */
    indices = smaug_dt_argsort(source_series, false);
    CHECK(indices[0] == 0, "argsort desc [0]=dez");
    smaug_free(indices);

    /* sort */
    smaug_series_dt_t *sorted = smaug_dt_sort(source_series, true);
    CHECK(sorted != NULL, "sort não NULL");
    smaug_status_t status;
    CHECK(smaug_dt_get(sorted, 0, &status) == dates[1], "sort[0]=jan");
    CHECK(smaug_dt_get(sorted, 2, &status) == dates[0], "sort[2]=dez");
    smaug_dt_free(sorted);

    /* argsort com NULL → NULL */
    smaug_dt_set_null(source_series, 0);
    CHECK(smaug_dt_argsort(source_series, true) == NULL, "argsort com NULL → NULL");

    /* take */
    smaug_series_dt_t *source_series_2 = smaug_dt_create_from_array(dates, 3);
    size_t take_index[] = {2, 0};
    smaug_series_dt_t *taken = smaug_dt_take(source_series_2, take_index, 2);
    CHECK(taken != NULL, "take não NULL");
    CHECK(taken->size == 2, "take size=2");
    CHECK(smaug_dt_get(taken, 0, &status) == dates[2], "take[0]=jun");
    CHECK(smaug_dt_get(taken, 1, &status) == dates[0], "take[1]=dez");
    smaug_dt_free(taken);

    /* take índice OOB → null */
    size_t oob_index[] = {10};
    smaug_series_dt_t *source_series_3 = smaug_dt_take(source_series_2, oob_index, 1);
    CHECK(smaug_dt_is_null(source_series_3, 0), "take OOB → null");
    smaug_dt_free(source_series_3);

    /* filter */
    uint8_t fmask[] = {1, 0, 1};
    smaug_series_dt_t *filtered = smaug_dt_filter(source_series_2, fmask);
    CHECK(filtered->size == 2, "filter size=2");
    CHECK(smaug_dt_get(filtered, 0, &status) == dates[0], "filter[0]");
    smaug_dt_free(filtered);

    /* count_nonnull */
    smaug_dt_set_null(source_series_2, 0);
    CHECK(smaug_dt_count_nonnull(source_series_2) == 2, "count_nonnull=2");

    smaug_dt_free(source_series);
    smaug_dt_free(source_series_2);

    /* NULL cases */
    CHECK(smaug_dt_argsort(NULL, true)    == NULL, "argsort NULL");
    CHECK(smaug_dt_sort(NULL, true)       == NULL, "sort NULL");
    CHECK(smaug_dt_take(NULL, take_index, 1) == NULL, "take NULL");
    CHECK(smaug_dt_filter(NULL, fmask)    == NULL, "filter NULL");
    CHECK(smaug_dt_count_nonnull(NULL)    == 0,    "count_nonnull NULL=0");
}

/* ===================================================================
   Datas de fronteira
   =================================================================== */

static void test_edge_dates(void) {
    /* 1 jan de cada século para exercitar o algoritmo de Hinnant */
    CHECK(smaug_dt_year(parse("1900-01-01T00:00:00Z")) == 1900, "1900");
    CHECK(smaug_dt_year(parse("2000-01-01T00:00:00Z")) == 2000, "2000");
    CHECK(smaug_dt_year(parse("2100-01-01T00:00:00Z")) == 2100, "2100");

    /* Último dia de cada mês */
    CHECK(smaug_dt_day(parse("2026-01-31T00:00:00Z")) == 31, "jan 31");
    CHECK(smaug_dt_day(parse("2026-02-28T00:00:00Z")) == 28, "fev 28 (não bissexto)");
    CHECK(smaug_dt_day(parse("2024-02-29T00:00:00Z")) == 29, "fev 29 (bissexto)");
    CHECK(smaug_dt_day(parse("2026-04-30T00:00:00Z")) == 30, "abr 30");

    /* Meia-noite exata */
    int64_t midnight = parse("2026-06-13T00:00:00.000Z");
    CHECK(smaug_dt_hour(midnight)   == 0, "meia-noite hour=0");
    CHECK(smaug_dt_minute(midnight) == 0, "meia-noite minute=0");
    CHECK(smaug_dt_ms(midnight)     == 0, "meia-noite ms=0");

    /* Fim do dia */
    int64_t end_of_day_epoch = parse("2026-06-13T23:59:59.999Z");
    CHECK(smaug_dt_hour(end_of_day_epoch)   == 23,  "23h");
    CHECK(smaug_dt_minute(end_of_day_epoch) == 59,  "59m");
    CHECK(smaug_dt_second(end_of_day_epoch) == 59,  "59s");
    CHECK(smaug_dt_ms(end_of_day_epoch)     == 999, "999ms");

    /* weekday: 2026-06-08=seg(0) ... 2026-06-14=dom(6) */
    const char *weekdays[] = {
        "2026-06-08T00:00:00Z",  /* seg = 0 */
        "2026-06-09T00:00:00Z",  /* ter = 1 */
        "2026-06-10T00:00:00Z",  /* qua = 2 */
        "2026-06-11T00:00:00Z",  /* qui = 3 */
        "2026-06-12T00:00:00Z",  /* sex = 4 */
        "2026-06-13T00:00:00Z",  /* sáb = 5 */
        "2026-06-14T00:00:00Z",  /* dom = 6 */
    };
    for (int source_dataset = 0; source_dataset < 7; source_dataset++) {
        int weekday_result = smaug_dt_weekday(parse(weekdays[source_dataset]));
        CHECK(weekday_result == source_dataset, "weekday sequencial");
    }

    /* Meses Janeiro e Março para exercitar ramos de mp >= 10 / < 10 no algoritmo */
    CHECK(smaug_dt_month(parse("2026-01-15T00:00:00Z")) == 1, "jan (mp >= 10)");
    CHECK(smaug_dt_month(parse("2026-03-15T00:00:00Z")) == 3, "mar (mp < 10)");
    CHECK(smaug_dt_month(parse("2026-11-15T00:00:00Z")) == 11, "nov");
    CHECK(smaug_dt_month(parse("2026-12-15T00:00:00Z")) == 12, "dez");
}

/* ===================================================================
   Roundtrip parse → format
   =================================================================== */

static void test_roundtrip(void) {
    const char *cases[] = {
        "1970-01-01T00:00:00.000Z",
        "2026-06-13T14:30:45.123Z",
        "1969-12-31T23:59:59.999Z",
        "2000-02-29T12:00:00.000Z",
        "2100-12-31T23:59:59.999Z",
        NULL
    };
    char buffer[26];
    for (int row_index = 0; cases[row_index]; row_index++) {
        int64_t epoch_milliseconds = 0;
        int parse_result = smaug_dt_parse(cases[row_index], strlen(cases[row_index]), &epoch_milliseconds, 0);
        CHECK(parse_result == 0, "roundtrip parse OK");
        parse_result = smaug_dt_format(epoch_milliseconds, buffer, 26);
        CHECK(parse_result == 0, "roundtrip format OK");
        CHECK(strcmp(buffer, cases[row_index]) == 0, "roundtrip idêntico");
    }
}

static void test_get_null_status(void) {
    /* smaug_dt_get com status=NULL — os ramos if(status) dentro de get()
     * (linhas 234-237) nunca foram chamados com status=NULL. */
    smaug_series_dt_t *source_series = smaug_dt_create(2);
    int64_t epoch_milliseconds = parse("2026-06-13T00:00:00Z");
    smaug_dt_set(source_series, 0, epoch_milliseconds);
    /* status=NULL com valor válido */
    int64_t element_value = smaug_dt_get(source_series, 0, NULL);
    CHECK(element_value == epoch_milliseconds, "get NULL status: valor correto");
    /* status=NULL com null value */
    int64_t element_value_2 = smaug_dt_get(source_series, 1, NULL);
    CHECK(element_value_2 == INT64_MIN, "get NULL status: null → DT_SENTINEL");
    /* status=NULL com OOB */
    int64_t element_value_3 = smaug_dt_get(source_series, 99, NULL);
    CHECK(element_value_3 == INT64_MIN, "get NULL status: OOB → DT_SENTINEL");
    /* status=NULL com s=NULL */
    int64_t element_value_4 = smaug_dt_get(NULL, 0, NULL);
    CHECK(element_value_4 == INT64_MIN, "get NULL status: s=NULL → DT_SENTINEL");
    smaug_dt_free(source_series);
}

static void test_is_null_oob(void) {
    /* smaug_dt_is_null com idx OOB — linha 260 (idx >= s->size → true) */
    smaug_series_dt_t *source_series = smaug_dt_create(2);
    CHECK(smaug_dt_is_null(source_series, 999) == true, "is_null OOB → true");
    smaug_dt_free(source_series);
}

static void test_append_grow(void) {
    /* append além da capacidade inicial (linha 279: s->size >= s->capacity) */
    smaug_series_dt_t *source_series = smaug_dt_create(1); /* capacity mínima */
    int64_t epoch_milliseconds = parse("2026-06-13T00:00:00Z");
    /* preenche a capacidade inicial */
    smaug_dt_set(source_series, 0, epoch_milliseconds);
    /* append forçando crescimento */
    for (int row_index = 0; row_index < 8; row_index++) {
        int status_code = smaug_dt_append(source_series, epoch_milliseconds + (int64_t)row_index * 86400000LL);
        CHECK(status_code == 0, "append grow: OK");
    }
    CHECK(source_series->size == 9, "append grow: size=9");
    /* append_null também deve crescer */
    int status_code = smaug_dt_append_null(source_series);
    CHECK(status_code == 0, "append_null grow: OK");
    CHECK(smaug_dt_is_null(source_series, 9), "append_null grow: null");
    smaug_dt_free(source_series);
}

static void test_parse_errors_extended(void) {
    int64_t epoch_milliseconds;
    /* formato YYYY sem primeiro '-' */
    CHECK(smaug_dt_parse("20261301", 8, &epoch_milliseconds, 0) == -1, "parse: sem '-' após ano");
    /* dígito inválido no mês (parse_digits, linha 306) */
    CHECK(smaug_dt_parse("2026-0A-01", 10, &epoch_milliseconds, 0) == -1, "parse: dígito inválido no mês");
    /* sem '-' após mês */
    CHECK(smaug_dt_parse("2026-01X01", 10, &epoch_milliseconds, 0) == -1, "parse: sem '-' após mês");
    /* sem ':' após hora (linha 333) */
    CHECK(smaug_dt_parse("2026-06-13T14X30:00Z", 20, &epoch_milliseconds, 0) == -1, "parse: sem ':' após hora");
    /* sem ':' após minuto (linha 335) */
    CHECK(smaug_dt_parse("2026-06-13T14:30X00Z", 20, &epoch_milliseconds, 0) == -1, "parse: sem ':' após minuto");
    /* minuto 60 inválido (linha 337) */
    CHECK(smaug_dt_parse("2026-06-13T14:60:00Z", 20, &epoch_milliseconds, 0) == -1, "parse: minuto 60 inválido");
    /* segundo 60 inválido */
    CHECK(smaug_dt_parse("2026-06-13T14:30:60Z", 20, &epoch_milliseconds, 0) == -1, "parse: segundo 60 inválido");
    /* timezone tz_h > 23 (linha 364) */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00+25:00", 25, &epoch_milliseconds, 0) == -1, "parse: tz_h>23");
    /* timezone tz_m > 59 */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00+05:60", 25, &epoch_milliseconds, 0) == -1, "parse: tz_m>59");
    /* separator ' ' (espaço) entre data e hora (linha 330) */
    CHECK(smaug_dt_parse("2026-06-13 14:30:00Z", 20, &epoch_milliseconds, 0) == 0, "parse: sep=' ' válido");
    /* timezone sem ':' entre h e m (linha 362: colon opcional) */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00+0530", 24, &epoch_milliseconds, 0) == 0, "parse: tz sem ':' válido");
    /* ms com 1 dígito → pad para 100ms (linha 350) */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00.5Z", 22, &epoch_milliseconds, 0) == 0, "parse: ms 1 dígito");
    CHECK(epoch_milliseconds % 1000 == 500, "parse: ms 1 dígito → 500ms");
    /* Contrato aprovado: fracao excedente precisa ser exata em ms. */
    int64_t original_epoch = epoch_milliseconds;
    CHECK(smaug_dt_parse("2026-06-13T00:00:00.1234Z", 25, &epoch_milliseconds, 0) == -1,
          "parse: ms inexatos rejeitados");
    CHECK(epoch_milliseconds == original_epoch, "parse: falha preserva saida");
    CHECK(smaug_dt_parse("2026-06-13T00:00:00.1230Z", 25, &epoch_milliseconds, 0) == 0,
          "parse: ms 4 digitos exatos");
    CHECK(epoch_milliseconds % 1000 == 123, "parse: .1230 representa 123ms");
}

static void test_format_small_buffer(void) {
    /* smaug_dt_format com buffer pequeno → escrita truncada → retorna -1
     * (linha 408: written >= buf_size). */
    int64_t epoch_milliseconds = parse("2026-06-13T00:00:00Z");
    char buffer[5];
    int status_code = smaug_dt_format(epoch_milliseconds, buffer, 5);
    CHECK(status_code == -1, "format buf pequeno: retorna -1");
}

static void test_week_boundary(void) {
    /* ISO week < 1: Jan 1 de 2023 é domingo — doy=1, wd=6 (dom=6),
     * week = (1 - 7 + 10)/7 = 4/7 = 0 → branch week < 1 (linha 484). */
    int64_t epoch_milliseconds;
    smaug_dt_parse("2023-01-01T00:00:00Z", 20, &epoch_milliseconds, 0);
    int week_result = smaug_dt_week(epoch_milliseconds);
    CHECK(week_result == 52 || week_result == 53, "week boundary Jan 1 2023 (domingo): semana do ano anterior");

    /* ISO week > 52 e semana 53 existe: 28-Dez de 2015 é segunda (wd=0 ≤ 3),
     * então semana 53 existe → Dec 31 2015 → week=53 (linha 496). */
    smaug_dt_parse("2015-12-31T00:00:00Z", 20, &epoch_milliseconds, 0);
    week_result = smaug_dt_week(epoch_milliseconds);
    CHECK(week_result == 53, "week Dec 31 2015: semana 53 existe");

    /* ISO week > 52 mas semana 53 NÃO existe: Dec 31 2018 → wd_dec28 > 3
     * → week = 1 (pertence a semana 1 de 2019) (linha 502). */
    smaug_dt_parse("2018-12-31T00:00:00Z", 20, &epoch_milliseconds, 0);
    week_result = smaug_dt_week(epoch_milliseconds);
    CHECK(week_result == 1, "week Dec 31 2018: pertence à semana 1 de 2019");

    /* wd_dec28 < 0: apenas com epoch_ms muito negativo (pré-~7M a.C.) —
     * inalcançável em uso prático; o branch wd < 0 em weekday (linha 453)
     * é exercitado por qualquer data pré-1970 com wd calculado negativo. */
    smaug_dt_parse("1969-01-01T00:00:00Z", 20, &epoch_milliseconds, 0);
    week_result = smaug_dt_week(epoch_milliseconds);
    CHECK(week_result >= 1 && week_result <= 53, "week pré-1970: dentro do intervalo");
}

static void test_from_parts_bounds(void) {
    /* ms < 0 e ms > 999 (linha 514-515) — não coberto pelos testes existentes */
    CHECK(smaug_dt_from_parts(2026,6,13,0,0,0,-1)  == INT64_MIN, "from_parts ms=-1");
    CHECK(smaug_dt_from_parts(2026,6,13,0,0,0,1000)== INT64_MIN, "from_parts ms=1000");
    CHECK(smaug_dt_from_parts(2026,6,13,0,0,-1,0)  == INT64_MIN, "from_parts sec=-1");
}

static void test_add_milliseconds_overflow(void) {
    /* overflow positivo e negativo (linhas 537-538) */
    CHECK(smaug_dt_add_ms(INT64_MAX,  1) == INT64_MIN, "add_ms overflow+");
    CHECK(smaug_dt_add_ms(INT64_MIN, -1) == INT64_MIN, "add_ms overflow-");
}

static void test_truncate_negative(void) {
    /* truncate com epoch_ms negativo não múltiplo (linhas 546/549/552) */
    /* -1500ms = 1500ms antes de epoch; segundo: floor = -2000ms */
    int64_t truncate_result = smaug_dt_truncate(-1500LL, 's');
    CHECK(truncate_result == -2000LL, "truncate 's' negativo não múltiplo");
    /* -90001ms (não múltiplo de 60000): floor minuto = -120000ms */
    int64_t truncate_result_2 = smaug_dt_truncate(-90001LL, 'm');
    CHECK(truncate_result_2 == -120000LL, "truncate 'm' negativo não múltiplo");
    /* -3601000ms (não múltiplo de 3600000): floor hora = -7200000ms */
    int64_t truncate_result_3 = smaug_dt_truncate(-3601000LL, 'h');
    CHECK(truncate_result_3 == -7200000LL, "truncate 'h' negativo não múltiplo");
}

static void test_take_filter_null_args(void) {
    /* smaug_dt_take/filter com NULL (linhas 681/698) */
    smaug_series_dt_t *source_series = smaug_dt_create(2);
    size_t indices[1] = {0};
    CHECK(smaug_dt_take(NULL, indices, 1) == NULL, "take NULL série");
    CHECK(smaug_dt_take(source_series, NULL, 1)   == NULL, "take NULL idx");
    uint8_t source_values[2] = {1, 0};
    CHECK(smaug_dt_filter(NULL, source_values) == NULL, "filter NULL série");
    CHECK(smaug_dt_filter(source_series, NULL)    == NULL, "filter NULL mask");
    smaug_dt_free(source_series);
}

static void test_argsort_empate(void) {
    /* cmp_dt_asc retorna 1 (linha 624: ea->val > eb->val) exige dois
     * valores onde a > b na ordenação. O teste existente tem 4 valores
     * distintos — adicionar aqui um com duplicatas para garantir o ramo. */
    int64_t values[3] = {
        parse("2026-06-13T00:00:00Z"),
        parse("2026-06-13T00:00:00Z"), /* duplicata */
        parse("2026-01-01T00:00:00Z"),
    };
    smaug_series_dt_t *source_series = smaug_dt_create_from_array(values, 3);
    size_t *indices = smaug_dt_argsort(source_series, true);
    CHECK(indices != NULL,     "argsort com empate: retorna índices");
    CHECK(indices[0] == 2,     "argsort empate: menor primeiro");
    free(indices);
    /* descendente: verifica que ramo > também é exercitado */
    size_t *sort_indices = smaug_dt_argsort(source_series, false);
    CHECK(sort_indices != NULL,    "argsort desc com empate: OK");
    CHECK(sort_indices[2] == 2,    "argsort desc: menor no final");
    free(sort_indices);
    smaug_dt_free(source_series);
}

static void test_comparisons_outmask_null(void) {
    /* Os 6 comparadores têm o ramo `if (out_mask) *out_mask = mask; else
     * free(mask);` — o test_comparisons sempre passa out_mask não-NULL,
     * deixando o else (out_mask==NULL → free(mask)) descoberto nos 6.
     * Aqui chamamos cada um com out_mask=NULL (uso legítimo: só quero o
     * resultado, não a máscara de validade). */
    int64_t dates[] = {
        parse("2026-01-01T00:00:00Z"),
        parse("2026-06-13T00:00:00Z"),
        parse("2026-12-31T00:00:00Z"),
    };
    smaug_series_dt_t *source_series = smaug_dt_create_from_array(dates, 3);
    int64_t reference = parse("2026-06-13T00:00:00Z");

    uint8_t *greater_than_mask = smaug_dt_gt(source_series, reference, NULL);
    CHECK(greater_than_mask && greater_than_mask[2] == 1, "gt out_mask=NULL: resultado correto");
    smaug_free(greater_than_mask);
    uint8_t *less_than_mask = smaug_dt_lt(source_series, reference, NULL);
    CHECK(less_than_mask && less_than_mask[0] == 1, "lt out_mask=NULL: resultado correto");
    smaug_free(less_than_mask);
    uint8_t *equality_mask = smaug_dt_eq(source_series, reference, NULL);
    CHECK(equality_mask && equality_mask[1] == 1, "eq out_mask=NULL: resultado correto");
    smaug_free(equality_mask);
    uint8_t *greater_or_equal_mask = smaug_dt_ge(source_series, reference, NULL);
    CHECK(greater_or_equal_mask && greater_or_equal_mask[1] == 1, "ge out_mask=NULL: resultado correto");
    smaug_free(greater_or_equal_mask);
    uint8_t *less_or_equal_mask = smaug_dt_le(source_series, reference, NULL);
    CHECK(less_or_equal_mask && less_or_equal_mask[1] == 1, "le out_mask=NULL: resultado correto");
    smaug_free(less_or_equal_mask);
    uint8_t *inequality_mask = smaug_dt_ne(source_series, reference, NULL);
    CHECK(inequality_mask && inequality_mask[0] == 1, "ne out_mask=NULL: resultado correto");
    smaug_free(inequality_mask);

    /* também: comparador com null no meio + out_mask=NULL (INVALID_DT branch
     * sem capturar máscara) — garante que os 6 tratam null sem out_mask */
    smaug_dt_set_null(source_series, 1);
    uint8_t *greater_than_mask_2 = smaug_dt_gt(source_series, reference, NULL);
    CHECK(greater_than_mask_2 && greater_than_mask_2[1] == 0, "gt out_mask=NULL com null: posição null = 0");
    smaug_free(greater_than_mask_2);

    smaug_dt_free(source_series);
}

static void test_parse_digit_below_zero(void) {
    /* parse_digits L306 branch 0: caractere ABAIXO de '0' (ex '/' = 0x2F).
     * Os testes existentes só usavam letras (acima de '9'). */
    int64_t epoch_milliseconds;
    CHECK(smaug_dt_parse("2026-/1-01", 10, &epoch_milliseconds, 0) == -1, "parse: '/' no mês (abaixo de '0')");
    CHECK(smaug_dt_parse("202/-01-01", 10, &epoch_milliseconds, 0) == -1, "parse: '/' no ano");
}

static void test_parse_tz_minus(void) {
    /* L358 branch do '-' no timezone (o '+' já era testado; o '-' com offset
     * que efetivamente subtrai precisa de caso próprio com minutos). */
    int64_t epoch_plus, epoch_minus;
    CHECK(smaug_dt_parse("2026-06-13T12:00:00+02:30", 25, &epoch_plus, 0)  == 0, "parse tz +02:30");
    CHECK(smaug_dt_parse("2026-06-13T12:00:00-02:30", 25, &epoch_minus, 0) == 0, "parse tz -02:30");
    /* +02:30 recua 2h30 em UTC; -02:30 avança 2h30 — diferença de 5h */
    CHECK(epoch_minus - epoch_plus == 5LL*3600*1000, "parse tz: +/- diferem por 5h");
}

static void test_from_parts_each_bound(void) {
    /* L514-515: cada componente fora do intervalo, individualmente, para
     * exercitar cada sub-branch da condição composta. */
    CHECK(smaug_dt_from_parts(2026,6,13,-1,0,0,0)  == INT64_MIN, "from_parts hour=-1");
    CHECK(smaug_dt_from_parts(2026,6,13,24,0,0,0)  == INT64_MIN, "from_parts hour=24");
    CHECK(smaug_dt_from_parts(2026,6,13,0,-1,0,0)  == INT64_MIN, "from_parts minute=-1");
    CHECK(smaug_dt_from_parts(2026,6,13,0,0,60,0)  == INT64_MIN, "from_parts second=60");
    CHECK(smaug_dt_from_parts(2026,6,13,0,0,0,-1)  == INT64_MIN, "from_parts ms=-1");
    CHECK(smaug_dt_from_parts(2026,6,13,0,0,0,1000)== INT64_MIN, "from_parts ms=1000");
    /* válido extremo: 23:59:59.999 */
    CHECK(smaug_dt_from_parts(2026,6,13,23,59,59,999) != INT64_MIN, "from_parts limite válido");
}

static void test_truncate_negative_minimum_hour(void) {
    /* L549/552: truncate minuto/hora com epoch negativo NÃO múltiplo
     * (o teste anterior já cobria 's'; faltavam os ramos % != 0 de 'm' e 'h'
     * que dependem do segundo operando da condição ternária). */
    /* -1ms truncado a minuto: deve ir para -60000 */
    CHECK(smaug_dt_truncate(-1LL, 'm') == -60000LL,   "truncate 'm' de -1ms = -60000");
    /* -1ms truncado a hora: -3600000 */
    CHECK(smaug_dt_truncate(-1LL, 'h') == -3600000LL, "truncate 'h' de -1ms = -3600000");
    /* múltiplo exato negativo: -60000ms a minuto = -60000 (sem ajuste) */
    CHECK(smaug_dt_truncate(-60000LL, 'm') == -60000LL, "truncate 'm' de múltiplo exato");
}

static void test_week_pre1970(void) {
    /* L489/500: wd_dec28 < 0 — alcançável com anos pré-1970, onde dec28
     * (dias desde epoch do 28-dez do ano anterior) é negativo e (dec28+3)%7
     * fica negativo em C. Varre anos que disparam os ramos week<1 e week>52. */
    int saw_valid = 0;
    for (int other_value = 1900; other_value < 1970; other_value++) {
        int64_t epoch_milliseconds = smaug_dt_from_parts(other_value, 1, 1, 0, 0, 0, 0);
        if (epoch_milliseconds == INT64_MIN) continue;
        int week_result = smaug_dt_week(epoch_milliseconds);
        CHECK(week_result >= 1 && week_result <= 53, "week pré-1970 jan1: intervalo válido");
        int64_t second_epoch = smaug_dt_from_parts(other_value, 12, 31, 0, 0, 0, 0);
        int week_result_2 = smaug_dt_week(second_epoch);
        CHECK(week_result_2 >= 1 && week_result_2 <= 53, "week pré-1970 dez31: intervalo válido");
        saw_valid = 1;
    }
    CHECK(saw_valid, "week pré-1970: varreu anos válidos");
}



/* 12.23: guards ESSENCIAIS de fronteira publica (ver CONTRATO 10).
   Auditado: sem o guard, estes SEGFAULTAM — dt_clone(NULL) desreferencia s->size
   direto, e dt_coalesce toca other->null_mask no laco. Nao sao redundantes. */
static void test_guards_publicos(void) {
    CHECK(smaug_dt_clone(NULL) == NULL, "dt_clone(NULL) -> NULL");

    smaug_series_dt_t *left_series = smaug_dt_create(3);
    smaug_dt_set(left_series, 0, 1000); smaug_dt_set_null(left_series, 1); smaug_dt_set(left_series, 2, 3000);
    smaug_series_dt_t *right_series = smaug_dt_create(2);
    smaug_dt_set(right_series, 0, 9); smaug_dt_set(right_series, 1, 9);

    CHECK(smaug_dt_coalesce(NULL, left_series) == NULL, "dt_coalesce(NULL, other) -> NULL");
    CHECK(smaug_dt_coalesce(left_series, NULL) == NULL, "dt_coalesce(self, NULL) -> NULL");
    CHECK(smaug_dt_coalesce(left_series, right_series)    == NULL, "dt_coalesce size divergente -> NULL");
    smaug_series_dt_t *source_series = smaug_dt_coalesce(left_series, left_series);
    CHECK(source_series != NULL,                          "dt_coalesce valido -> serie (controle)");
    smaug_dt_free(source_series); smaug_dt_free(right_series); smaug_dt_free(left_series);

    smaug_series_dt_t *source_series_2 = smaug_dt_create(2);
    smaug_dt_set(source_series_2, 0, 5000);
    smaug_series_dt_t *source_series_3 = smaug_dt_clone(source_series_2);
    CHECK(source_series_3 != NULL && source_series_3->size == 2, "dt_clone valido -> copia (controle)");
    smaug_dt_free(source_series_3); smaug_dt_free(source_series_2);

    /* 12.24: dt_select — guard ESSENCIAL (a auditoria do 12.18 errou: o script
       removia so a linha do `if`, deixando o `return NULL;` orfao executar
       sempre; a funcao virava `return NULL` incondicional e nao crashava).
       O corpo toca cond->null_mask e `b` no laco. 5 ramos do `||`. */
    smaug_series_dt_t *left_series_2  = smaug_dt_create(3);
    smaug_dt_set(left_series_2, 0, 1); smaug_dt_set(left_series_2, 1, 2); smaug_dt_set(left_series_2, 2, 3);
    smaug_series_dt_t *right_series_2  = smaug_dt_create(3);
    smaug_dt_set(right_series_2, 0, 7); smaug_dt_set(right_series_2, 1, 8); smaug_dt_set(right_series_2, 2, 9);
    smaug_series_dt_t *source_series_4 = smaug_dt_create(2);
    smaug_series_bool_t *boolean_series = smaug_bool_create(3);
    smaug_bool_set(boolean_series, 0, 1); smaug_bool_set(boolean_series, 1, 0); smaug_bool_set(boolean_series, 2, 1);
    smaug_series_bool_t *boolean_series_2 = smaug_bool_create(2);

    CHECK(smaug_dt_select(NULL, left_series_2, right_series_2) == NULL, "dt_select(cond NULL) -> NULL");
    CHECK(smaug_dt_select(boolean_series, NULL, right_series_2) == NULL, "dt_select(a NULL) -> NULL");
    CHECK(smaug_dt_select(boolean_series, left_series_2, NULL) == NULL, "dt_select(b NULL) -> NULL");
    CHECK(smaug_dt_select(boolean_series_2, left_series_2, right_series_2) == NULL,   "dt_select(cond->size != a->size) -> NULL");
    CHECK(smaug_dt_select(boolean_series, left_series_2, source_series_4) == NULL,   "dt_select(a->size != b->size) -> NULL");
    smaug_series_dt_t *source_series_5 = smaug_dt_select(boolean_series, left_series_2, right_series_2);
    CHECK(source_series_5 != NULL && source_series_5->size == 3,          "dt_select valido -> serie (controle)");
    smaug_dt_free(source_series_5);
    smaug_bool_free(boolean_series_2); smaug_bool_free(boolean_series);
    smaug_dt_free(source_series_4); smaug_dt_free(right_series_2); smaug_dt_free(left_series_2);
}

int main(void) {
    test_lifecycle();
    test_guards_publicos();
    test_get_null_status();
    test_is_null_oob();
    test_append_grow();
    test_clone();
    test_view_cow();
    test_append();
    test_create_from_array();
    test_parse();
    test_parse_errors_extended();
    test_format();
    test_format_small_buffer();
    test_components();
    test_week_boundary();
    test_from_parts();
    test_from_parts_bounds();
    test_arithmetic();
    test_add_milliseconds_overflow();
    test_truncate_negative();
    test_comparisons();
    test_sort_take_filter();
    test_take_filter_null_args();
    test_argsort_empate();
    test_comparisons_outmask_null();
    test_parse_digit_below_zero();
    test_parse_tz_minus();
    test_from_parts_each_bound();
    test_truncate_negative_minimum_hour();
    test_week_pre1970();
    test_edge_dates();
    test_roundtrip();

    if (failed_checks == 0)
        printf("PASS: test_datetime_c (%d checks)\n", passed_checks);
    else
        printf("FAIL: %d/%d checks falharam\n", failed_checks, passed_checks + failed_checks);

    return failed_checks > 0 ? 1 : 0;
}
