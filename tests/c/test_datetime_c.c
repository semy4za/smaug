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

static int g_ok = 0, g_fail = 0;

#define CHECK(cond, msg) do { \
    if (cond) { g_ok++; } \
    else { fprintf(stderr, "FALHOU [%d]: %s\n", __LINE__, msg); g_fail++; } \
} while(0)

/* epoch_ms de datas conhecidas para ancoragem */
/* 2026-06-13T14:30:00.000Z = ? ms */
/* verificado: 1970 + 56*365.25*86400*1000 ≈ não vamos calcular, usamos parse */

static int64_t parse(const char *s) {
    int64_t ep = 0;
    int r = smaug_dt_parse(s, strlen(s), &ep, 0);
    if (r != 0) {
        fprintf(stderr, "parse inesperado falhou para: %s\n", s);
        abort();
    }
    return ep;
}

/* ===================================================================
   Lifecycle
   =================================================================== */

static void test_lifecycle(void) {
    /* create / free NULL-safe */
    smaug_dt_free(NULL);
    g_ok++;

    /* create com size=0 */
    smaug_series_dt_t *s0 = smaug_dt_create(0);
    CHECK(s0 != NULL,    "create(0): não NULL");
    CHECK(s0->size == 0, "create(0): size=0");
    smaug_dt_free(s0);

    /* create normal */
    smaug_series_dt_t *s = smaug_dt_create(4);
    CHECK(s != NULL,           "create(4): não NULL");
    CHECK(s->size == 4,        "create(4): size=4");
    CHECK(s->capacity >= 4,    "create(4): capacity>=4");
    CHECK(!strcmp(s->meta.dtype, "datetime"), "dtype='datetime'");

    /* todos nulos por padrão */
    for (size_t i = 0; i < 4; i++)
        CHECK(smaug_dt_is_null(s, i), "criado nulo");

    /* set / get */
    int64_t ep = parse("2026-06-13T00:00:00Z");
    CHECK(smaug_dt_set(s, 0, ep) == SMG_OK, "set OK");
    smaug_status_t st;
    int64_t v = smaug_dt_get(s, 0, &st);
    CHECK(st == SMG_OK && v == ep, "get após set");

    /* set_null */
    CHECK(smaug_dt_set_null(s, 0) == SMG_OK, "set_null OK");
    smaug_dt_get(s, 0, &st);
    CHECK(st == SMG_NULL_VALUE, "get após set_null = NULL_VALUE");

    /* OOB */
    CHECK(smaug_dt_set(s, 10, ep)  == SMG_ERR_OOB, "set OOB");
    CHECK(smaug_dt_set_null(s, 10) == SMG_ERR_OOB, "set_null OOB");
    smaug_dt_get(s, 10, &st);
    CHECK(st == SMG_ERR_OOB, "get OOB → SMG_ERR_OOB");

    /* NULL pointer */
    CHECK(smaug_dt_set(NULL, 0, ep) == SMG_ERR_ARGUMENT, "set NULL ptr");
    CHECK(smaug_dt_is_null(NULL, 0) == true, "is_null NULL ptr = true");

    smaug_dt_free(s);
}

static void test_clone(void) {
    smaug_series_dt_t *s = smaug_dt_create(2);
    int64_t ep = parse("2026-01-01T00:00:00Z");
    smaug_dt_set(s, 0, ep);
    /* s[1] permanece NULL */

    smaug_series_dt_t *c = smaug_dt_clone(s);
    CHECK(c != NULL,                    "clone não NULL");
    CHECK(c->size == 2,                 "clone size=2");
    smaug_status_t st;
    CHECK(smaug_dt_get(c, 0, &st) == ep && st == SMG_OK, "clone val[0]");
    CHECK(smaug_dt_is_null(c, 1),       "clone null[1]");

    /* independência: mudar clone não afeta original */
    smaug_dt_set(c, 0, ep + 1000);
    CHECK(smaug_dt_get(s, 0, &st) == ep, "clone independente");

    smaug_dt_free(s);
    smaug_dt_free(c);

    /* clone NULL */
    CHECK(smaug_dt_clone(NULL) == NULL, "clone NULL → NULL");
}

static void test_view_cow(void) {
    smaug_series_dt_t *s = smaug_dt_create(4);
    int64_t ep = parse("2026-06-13T00:00:00Z");
    for (size_t i = 0; i < 4; i++) smaug_dt_set(s, i, ep + (int64_t)i * 86400000LL);

    /* view */
    smaug_series_dt_t *v = smaug_dt_view(s, 1, 2);
    CHECK(v != NULL,            "view não NULL");
    CHECK(v->size == 2,         "view size=2");
    CHECK(v->meta.is_view,      "view is_view=true");
    smaug_status_t st;
    int64_t vv = smaug_dt_get(v, 0, &st);
    CHECK(st == SMG_OK && vv == ep + 86400000LL, "view val[0]");

    /* COW: mutação na view não afeta a pai */
    smaug_dt_set(v, 0, ep + 999000LL);
    CHECK(smaug_dt_get(s, 1, &st) == ep + 86400000LL, "COW: pai intacta");
    CHECK(!v->meta.is_view, "COW: view deixou de ser view");

    /* view fora dos limites */
    CHECK(smaug_dt_view(s, 10, 1) == NULL, "view OOB → NULL");
    CHECK(smaug_dt_view(NULL, 0, 1) == NULL, "view NULL → NULL");

    smaug_dt_free(s);
    smaug_dt_free(v);
}

static void test_append(void) {
    smaug_series_dt_t *s = smaug_dt_create(0);
    int64_t ep = parse("2026-01-01T00:00:00Z");

    /* append 5 elementos — força dt_grow (capacity inicial 0) */
    for (int i = 0; i < 5; i++) {
        CHECK(smaug_dt_append(s, ep + (int64_t)i * 86400000LL) == 0, "append OK");
    }
    CHECK(s->size == 5, "append size=5");
    CHECK(smaug_dt_append_null(s) == 0, "append_null OK");
    CHECK(s->size == 6, "append_null size=6");
    CHECK(smaug_dt_is_null(s, 5), "append_null[5] é null");

    CHECK(smaug_dt_append(NULL, 0) == -1, "append NULL → -1");

    smaug_dt_free(s);
}

static void test_create_from_array(void) {
    int64_t arr[] = {0LL, 86400000LL, 172800000LL};
    smaug_series_dt_t *s = smaug_dt_create_from_array(arr, 3);
    CHECK(s != NULL,         "from_array não NULL");
    CHECK(s->size == 3,      "from_array size=3");
    smaug_status_t st;
    CHECK(smaug_dt_get(s, 1, &st) == 86400000LL, "from_array val[1]");
    CHECK(!smaug_dt_is_null(s, 0), "from_array todos válidos");
    smaug_dt_free(s);

    CHECK(smaug_dt_create_from_array(NULL, 3) == NULL, "from_array NULL → NULL");
}

/* ===================================================================
   Parse ISO 8601
   =================================================================== */

static void test_parse(void) {
    int64_t ep = 0;

    /* epoch: 1970-01-01 */
    CHECK(smaug_dt_parse("1970-01-01T00:00:00Z", 20, &ep, 0) == 0, "parse epoch");
    CHECK(ep == 0, "epoch = 0");

    /* só data (meia-noite UTC) */
    CHECK(smaug_dt_parse("1970-01-02", 10, &ep, 0) == 0, "parse só data");
    CHECK(ep == 86400000LL, "só data = 1 dia em ms");

    /* com milissegundos */
    CHECK(smaug_dt_parse("1970-01-01T00:00:00.500Z", 24, &ep, 0) == 0, "parse com ms");
    CHECK(ep == 500, "500 ms");

    /* com offset +03:00 */
    CHECK(smaug_dt_parse("1970-01-01T03:00:00+03:00", 25, &ep, 0) == 0, "parse +03:00");
    CHECK(ep == 0, "UTC=0 com offset +03:00");

    /* com offset -05:30 */
    CHECK(smaug_dt_parse("1970-01-01T00:00:00-05:30", 25, &ep, 0) == 0, "parse -05:30");
    CHECK(ep == (5*60+30)*60*1000LL, "-05:30 → UTC+19800000ms");

    /* data negativa: 1969-12-31 = -1 dia */
    CHECK(smaug_dt_parse("1969-12-31T00:00:00Z", 20, &ep, 0) == 0, "parse pré-1970");
    CHECK(ep == -86400000LL, "1969-12-31 = -1 dia");

    /* formato inválido */
    CHECK(smaug_dt_parse("abc", 3, &ep, 0) == -1, "parse inválido");
    CHECK(smaug_dt_parse("2026-13-01", 10, &ep, 0) == -1, "mês 13 inválido");
    CHECK(smaug_dt_parse("2026-02-30", 10, &ep, 0) == -1, "fev 30 inválido");
    CHECK(smaug_dt_parse("2026-06-13T25:00:00Z", 20, &ep, 0) == -1, "hora 25 inválida");
    CHECK(smaug_dt_parse(NULL, 0, &ep, 0) == -1, "parse NULL");
    CHECK(smaug_dt_parse("2026-06-13T00:00:00Z", 20, NULL, 0) == -1, "out NULL");

    /* com lixo no final */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00ZLIXO", 24, &ep, 0) == -1, "lixo no final");

    /* separador '/' (H.6.4): mesma ordem YYYY/MM/DD, não-ambíguo */
    int64_t ep_slash = 0, ep_dash = 0;
    CHECK(smaug_dt_parse("2026/06/13", 10, &ep_slash, 0) == 0, "parse com / (só data)");
    CHECK(smaug_dt_parse("2026-06-13", 10, &ep_dash, 0) == 0,  "parse com - (referência)");
    CHECK(ep_slash == ep_dash, "/ e - produzem o mesmo epoch (equivalência)");

    /* '/' com hora: separador de data muda, hora continua ':' */
    CHECK(smaug_dt_parse("2026/06/13T14:30:00Z", 20, &ep, 0) == 0, "parse / com hora");
    int64_t ep_ref = parse("2026-06-13T14:30:00Z");
    CHECK(ep == ep_ref, "/ com hora = - com hora");

    /* consistência: separador misturado é rejeitado (sem meia-boca) */
    CHECK(smaug_dt_parse("2026-06/13", 10, &ep, 0) == -1, "separador misturado -/ rejeitado");
    CHECK(smaug_dt_parse("2026/06-13", 10, &ep, 0) == -1, "separador misturado /- rejeitado");

    /* '/' não afrouxa validação: mês/dia inválidos continuam barrados */
    CHECK(smaug_dt_parse("2026/13/01", 10, &ep, 0) == -1, "/ mês 13 ainda inválido");
    CHECK(smaug_dt_parse("2026/02/30", 10, &ep, 0) == -1, "/ fev 30 ainda inválido");

    /* H.5.a — dayfirst (year-last DD/MM/YYYY vs MM/DD/YYYY) */
    int64_t ep_df = 0;

    /* year-first ignora dayfirst (ordem não-ambígua) */
    int64_t yf0 = 0, yf1 = 0;
    CHECK(smaug_dt_parse("2026-06-13", 10, &yf0, 0) == 0, "year-first df=0 ok");
    CHECK(smaug_dt_parse("2026-06-13", 10, &yf1, 1) == 0, "year-first df=1 ok");
    CHECK(yf0 == yf1, "year-first: dayfirst não altera resultado");

    /* dayfirst=0 (MM/DD): 06/13 ok, 13/06 rejeitado (falha visível) */
    CHECK(smaug_dt_parse("06/13/2026", 10, &ep_df, 0) == 0,  "MM/DD 06/13 (df=0) ok");
    CHECK(smaug_dt_parse("13/06/2026", 10, &ep_df, 0) == -1, "MM/DD 13/06 (df=0) → mês 13 rejeitado");

    /* dayfirst=1 (DD/MM): 13/06 ok, 06/13 rejeitado */
    CHECK(smaug_dt_parse("13/06/2026", 10, &ep_df, 1) == 0,  "DD/MM 13/06 (df=1) ok");
    CHECK(smaug_dt_parse("06/13/2026", 10, &ep_df, 1) == -1, "DD/MM 06/13 (df=1) → mês 13 rejeitado");

    /* equivalência: 13/06/2026 df=1 == 2026-06-13 */
    smaug_dt_parse("13/06/2026", 10, &ep_df, 1);
    CHECK(ep_df == parse("2026-06-13"), "DD/MM 13/06/2026 (df=1) == ISO 2026-06-13");

    /* 1-2 dígitos: 5/6/2026 (teu caso real) */
    smaug_dt_parse("5/6/2026", 8, &ep_df, 1);
    CHECK(ep_df == parse("2026-06-05"), "5/6/2026 (df=1) = 5 de junho");
    smaug_dt_parse("5/6/2026", 8, &ep_df, 0);
    CHECK(ep_df == parse("2026-05-06"), "5/6/2026 (df=0) = 6 de maio");

    /* year-last com hora e com separador '-' */
    CHECK(smaug_dt_parse("13/06/2026 14:30:00", 19, &ep_df, 1) == 0, "year-last DD/MM com hora ok");
    CHECK(ep_df == parse("2026-06-13T14:30:00"), "13/06/2026 14:30 (df=1) = ISO equivalente");
    CHECK(smaug_dt_parse("13-06-2026", 10, &ep_df, 1) == 0, "year-last com '-' (df=1) ok");

    /* ano-no-fim exige 4 dígitos; 2 dígitos rejeitado */
    CHECK(smaug_dt_parse("13/06/26", 8, &ep_df, 1) == -1, "year-last ano 2 dígitos rejeitado");

    /* cobertura dos caminhos de erro do parser de data (year-last/year-first) */
    CHECK(smaug_dt_parse("", 0, &ep_df, 1) == -1,           "string vazia rejeitada");
    CHECK(smaug_dt_parse("/06/2026", 8, &ep_df, 1) == -1,   "year-last sem 1º campo (não-dígito) rejeitado");
    CHECK(smaug_dt_parse("13//2026", 8, &ep_df, 1) == -1,   "year-last sem 2º campo rejeitado");
    CHECK(smaug_dt_parse("13/06/", 6, &ep_df, 1) == -1,     "year-last sem ano rejeitado");
    CHECK(smaug_dt_parse("13:06:2026", 10, &ep_df, 1) == -1,"year-last separador ':' inválido rejeitado");
    CHECK(smaug_dt_parse("1/2/2026", 8, &ep_df, 1) == 0,    "year-last 1 dígito em ambos (1/2) ok");
    CHECK(smaug_dt_parse("202X-06-13", 10, &ep, 0) == -1,   "year-first ano com não-dígito rejeitado");
    CHECK(smaug_dt_parse("2026-6-13", 9, &ep, 0) == -1,     "year-first mês 1 dígito ainda rejeitado (escopo)");
}

static void test_format(void) {
    char buf[26];
    CHECK(smaug_dt_format(0, buf, 26) == 0, "format epoch OK");
    CHECK(strcmp(buf, "1970-01-01T00:00:00.000Z") == 0, "format epoch string");

    CHECK(smaug_dt_format(500, buf, 26) == 0, "format 500ms OK");
    CHECK(strcmp(buf, "1970-01-01T00:00:00.500Z") == 0, "format 500ms string");

    /* buffer pequeno */
    char small[10];
    CHECK(smaug_dt_format(0, small, 10) == -1, "format buf pequeno");
    CHECK(smaug_dt_format(0, NULL, 26) == -1, "format NULL buf");

    /* roundtrip: parse → format */
    int64_t ep = parse("2026-06-13T14:30:00.123Z");
    CHECK(smaug_dt_format(ep, buf, 26) == 0, "roundtrip format OK");
    CHECK(strcmp(buf, "2026-06-13T14:30:00.123Z") == 0, "roundtrip string");
}

/* ===================================================================
   Componentes calendário
   =================================================================== */

static void test_components(void) {
    int64_t ep = parse("2026-06-13T14:30:45.123Z");

    CHECK(smaug_dt_year(ep)    == 2026, "year=2026");
    CHECK(smaug_dt_month(ep)   == 6,    "month=6");
    CHECK(smaug_dt_day(ep)     == 13,   "day=13");
    CHECK(smaug_dt_hour(ep)    == 14,   "hour=14");
    CHECK(smaug_dt_minute(ep)  == 30,   "minute=30");
    CHECK(smaug_dt_second(ep)  == 45,   "second=45");
    CHECK(smaug_dt_ms(ep)      == 123,  "ms=123");
    CHECK(smaug_dt_quarter(ep) == 2,    "quarter=2 (junho)");

    /* 2026-06-13 é sábado = weekday 5 (0=seg) */
    CHECK(smaug_dt_weekday(ep) == 5, "weekday=5 (sáb)");

    /* Datas antes de 1970 */
    int64_t ep_neg = parse("1969-12-31T12:00:00Z");
    CHECK(smaug_dt_year(ep_neg)   == 1969, "1969 year");
    CHECK(smaug_dt_month(ep_neg)  == 12,   "1969 month=12");
    CHECK(smaug_dt_day(ep_neg)    == 31,   "1969 day=31");
    CHECK(smaug_dt_hour(ep_neg)   == 12,   "1969 hour=12");

    /* Ano bissexto: 2024-02-29 existe */
    int64_t leap = parse("2024-02-29T00:00:00Z");
    CHECK(smaug_dt_year(leap)  == 2024, "bissexto year=2024");
    CHECK(smaug_dt_month(leap) == 2,    "bissexto month=2");
    CHECK(smaug_dt_day(leap)   == 29,   "bissexto day=29");

    /* 2024 não é bissexto em 100 anos mas divide 4: bissexto normal */
    /* 1900 não é bissexto (divisível por 100, não por 400) */
    CHECK(smaug_dt_parse("1900-02-29", 10, &ep_neg, 0) == -1, "1900 não bissexto");
    /* 2000 é bissexto (divisível por 400) */
    int64_t y2k = parse("2000-02-29T00:00:00Z");
    CHECK(smaug_dt_day(y2k) == 29, "2000 é bissexto");

    /* yearday */
    int64_t jan1 = parse("2026-01-01T00:00:00Z");
    CHECK(smaug_dt_yearday(jan1) == 1, "1 jan = yearday 1");
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
    int64_t ep_parse = parse("2026-06-13T14:30:45.123Z");
    int64_t ep_parts = smaug_dt_from_parts(2026, 6, 13, 14, 30, 45, 123);
    CHECK(ep_parse == ep_parts, "from_parts == parse");

    /* data inválida */
    CHECK(smaug_dt_from_parts(2026, 13,  1, 0, 0, 0, 0) == INT64_MIN, "mês 13 inválido");
    CHECK(smaug_dt_from_parts(2026,  2, 30, 0, 0, 0, 0) == INT64_MIN, "fev 30 inválido");
    CHECK(smaug_dt_from_parts(2026,  6, 13, 25, 0, 0, 0) == INT64_MIN, "hora 25 inválida");
    CHECK(smaug_dt_from_parts(2026,  6, 13, 14, 60, 0, 0) == INT64_MIN, "minuto 60 inválido");

    /* data pré-1970 */
    int64_t ep_neg = smaug_dt_from_parts(1969, 12, 31, 0, 0, 0, 0);
    CHECK(ep_neg == -86400000LL, "1969-12-31 from_parts");
}

/* ===================================================================
   Aritmética
   =================================================================== */

static void test_arithmetic(void) {
    int64_t ep = parse("2026-06-13T00:00:00Z");

    /* diff_ms */
    int64_t ep2 = parse("2026-06-14T00:00:00Z");
    CHECK(smaug_dt_diff_ms(ep2, ep) == 86400000LL, "diff = 1 dia");
    CHECK(smaug_dt_diff_ms(ep, ep2) == -86400000LL, "diff negativo");

    /* add_ms */
    int64_t next = smaug_dt_add_ms(ep, 86400000LL);
    CHECK(next == ep2, "add_ms 1 dia");
    int64_t prev = smaug_dt_add_ms(ep, -86400000LL);
    CHECK(smaug_dt_day(prev) == 12, "add_ms negativo = 12");

    /* truncate */
    int64_t with_time = parse("2026-06-13T14:30:45.123Z");

    /* segundo */
    int64_t t_sec = smaug_dt_truncate(with_time, 's');
    CHECK(smaug_dt_ms(t_sec) == 0 && smaug_dt_second(t_sec) == 45, "truncate segundo");

    /* minuto */
    int64_t t_min = smaug_dt_truncate(with_time, 'm');
    CHECK(smaug_dt_second(t_min) == 0 && smaug_dt_minute(t_min) == 30, "truncate minuto");

    /* hora */
    int64_t t_h = smaug_dt_truncate(with_time, 'h');
    CHECK(smaug_dt_minute(t_h) == 0 && smaug_dt_hour(t_h) == 14, "truncate hora");

    /* dia */
    int64_t t_d = smaug_dt_truncate(with_time, 'D');
    CHECK(smaug_dt_hour(t_d) == 0 && smaug_dt_day(t_d) == 13, "truncate dia");

    /* semana (segunda-feira anterior) */
    int64_t t_w = smaug_dt_truncate(with_time, 'W');
    CHECK(smaug_dt_weekday(t_w) == 0, "truncate semana = segunda");
    CHECK(smaug_dt_day(t_w) == 8, "truncate semana = 8 jun (segunda anterior a 13 jun sáb)");

    /* mês */
    int64_t t_m = smaug_dt_truncate(with_time, 'M');
    CHECK(smaug_dt_day(t_m) == 1 && smaug_dt_month(t_m) == 6, "truncate mês");

    /* trimestre */
    int64_t t_q = smaug_dt_truncate(with_time, 'Q');
    CHECK(smaug_dt_month(t_q) == 4 && smaug_dt_day(t_q) == 1, "truncate trimestre Q2→abr");

    /* ano */
    int64_t t_y = smaug_dt_truncate(with_time, 'Y');
    CHECK(smaug_dt_month(t_y) == 1 && smaug_dt_day(t_y) == 1, "truncate ano");

    /* unidade inválida */
    CHECK(smaug_dt_truncate(with_time, 'X') == INT64_MIN, "truncate X inválido");

    /* truncate de data negativa (pré-1970) */
    int64_t neg = parse("1969-12-31T14:30:00Z");
    int64_t t_neg_d = smaug_dt_truncate(neg, 'D');
    CHECK(smaug_dt_day(t_neg_d) == 31 && smaug_dt_hour(t_neg_d) == 0, "truncate dia negativo");
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
    smaug_series_dt_t *s = smaug_dt_create_from_array(dates, 3);

    int64_t ref = parse("2026-06-13T00:00:00Z");
    smaug_mask_t *mask = NULL;

    uint8_t *gt = smaug_dt_gt(s, ref, &mask);
    CHECK(gt != NULL,        "gt retorna array");
    CHECK(gt[0] == 0,        "gt[0]=false (jan < jun)");
    CHECK(gt[1] == 0,        "gt[1]=false (jun == jun)");
    CHECK(gt[2] == 1,        "gt[2]=true (dez > jun)");
    CHECK(mask[0] == 0xFF,   "gt mask válida");
    smaug_free(gt); smaug_free(mask);

    uint8_t *lt = smaug_dt_lt(s, ref, &mask);
    CHECK(lt[0] == 1, "lt[0]=true"); CHECK(lt[2] == 0, "lt[2]=false");
    smaug_free(lt); smaug_free(mask);

    uint8_t *eq = smaug_dt_eq(s, ref, &mask);
    CHECK(eq[0] == 0, "eq[0]=false"); CHECK(eq[1] == 1, "eq[1]=true");
    smaug_free(eq); smaug_free(mask);

    uint8_t *ge = smaug_dt_ge(s, ref, &mask);
    CHECK(ge[1] == 1, "ge[1]=true"); CHECK(ge[0] == 0, "ge[0]=false");
    smaug_free(ge); smaug_free(mask);

    uint8_t *le = smaug_dt_le(s, ref, &mask);
    CHECK(le[2] == 0, "le[2]=false"); CHECK(le[1] == 1, "le[1]=true");
    smaug_free(le); smaug_free(mask);

    uint8_t *ne = smaug_dt_ne(s, ref, &mask);
    CHECK(ne[1] == 0, "ne[1]=false"); CHECK(ne[0] == 1, "ne[0]=true");
    smaug_free(ne); smaug_free(mask);

    /* NULL propaga nas comparações */
    smaug_dt_set_null(s, 1);
    uint8_t *gt2 = smaug_dt_gt(s, ref, &mask);
    CHECK(mask[1] == 0x00, "gt null: mask=0x00");
    CHECK(gt2[1] == 0,     "gt null: valor=0");
    smaug_free(gt2); smaug_free(mask);

    /* NULL série */
    CHECK(smaug_dt_gt(NULL, ref, &mask) == NULL, "gt NULL série → NULL");

    smaug_dt_free(s);
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
    smaug_series_dt_t *s = smaug_dt_create_from_array(dates, 3);

    /* argsort asc */
    size_t *idx = smaug_dt_argsort(s, true);
    CHECK(idx != NULL, "argsort não NULL");
    CHECK(idx[0] == 1, "argsort asc [0]=jan");
    CHECK(idx[1] == 2, "argsort asc [1]=jun");
    CHECK(idx[2] == 0, "argsort asc [2]=dez");
    smaug_free(idx);

    /* argsort desc */
    idx = smaug_dt_argsort(s, false);
    CHECK(idx[0] == 0, "argsort desc [0]=dez");
    smaug_free(idx);

    /* sort */
    smaug_series_dt_t *sorted = smaug_dt_sort(s, true);
    CHECK(sorted != NULL, "sort não NULL");
    smaug_status_t st;
    CHECK(smaug_dt_get(sorted, 0, &st) == dates[1], "sort[0]=jan");
    CHECK(smaug_dt_get(sorted, 2, &st) == dates[0], "sort[2]=dez");
    smaug_dt_free(sorted);

    /* argsort com NULL → NULL */
    smaug_dt_set_null(s, 0);
    CHECK(smaug_dt_argsort(s, true) == NULL, "argsort com NULL → NULL");

    /* take */
    smaug_series_dt_t *s2 = smaug_dt_create_from_array(dates, 3);
    size_t take_idx[] = {2, 0};
    smaug_series_dt_t *taken = smaug_dt_take(s2, take_idx, 2);
    CHECK(taken != NULL, "take não NULL");
    CHECK(taken->size == 2, "take size=2");
    CHECK(smaug_dt_get(taken, 0, &st) == dates[2], "take[0]=jun");
    CHECK(smaug_dt_get(taken, 1, &st) == dates[0], "take[1]=dez");
    smaug_dt_free(taken);

    /* take índice OOB → null */
    size_t oob_idx[] = {10};
    smaug_series_dt_t *t2 = smaug_dt_take(s2, oob_idx, 1);
    CHECK(smaug_dt_is_null(t2, 0), "take OOB → null");
    smaug_dt_free(t2);

    /* filter */
    uint8_t fmask[] = {1, 0, 1};
    smaug_series_dt_t *filtered = smaug_dt_filter(s2, fmask);
    CHECK(filtered->size == 2, "filter size=2");
    CHECK(smaug_dt_get(filtered, 0, &st) == dates[0], "filter[0]");
    smaug_dt_free(filtered);

    /* count_nonnull */
    smaug_dt_set_null(s2, 0);
    CHECK(smaug_dt_count_nonnull(s2) == 2, "count_nonnull=2");

    smaug_dt_free(s);
    smaug_dt_free(s2);

    /* NULL cases */
    CHECK(smaug_dt_argsort(NULL, true)    == NULL, "argsort NULL");
    CHECK(smaug_dt_sort(NULL, true)       == NULL, "sort NULL");
    CHECK(smaug_dt_take(NULL, take_idx, 1) == NULL, "take NULL");
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
    int64_t eod = parse("2026-06-13T23:59:59.999Z");
    CHECK(smaug_dt_hour(eod)   == 23,  "23h");
    CHECK(smaug_dt_minute(eod) == 59,  "59m");
    CHECK(smaug_dt_second(eod) == 59,  "59s");
    CHECK(smaug_dt_ms(eod)     == 999, "999ms");

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
    for (int d = 0; d < 7; d++) {
        int wd = smaug_dt_weekday(parse(weekdays[d]));
        CHECK(wd == d, "weekday sequencial");
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
    char buf[26];
    for (int i = 0; cases[i]; i++) {
        int64_t ep = 0;
        int r = smaug_dt_parse(cases[i], strlen(cases[i]), &ep, 0);
        CHECK(r == 0, "roundtrip parse OK");
        r = smaug_dt_format(ep, buf, 26);
        CHECK(r == 0, "roundtrip format OK");
        CHECK(strcmp(buf, cases[i]) == 0, "roundtrip idêntico");
    }
}

static void test_get_null_status(void) {
    /* smaug_dt_get com status=NULL — os ramos if(status) dentro de get()
     * (linhas 234-237) nunca foram chamados com status=NULL. */
    smaug_series_dt_t *s = smaug_dt_create(2);
    int64_t ep = parse("2026-06-13T00:00:00Z");
    smaug_dt_set(s, 0, ep);
    /* status=NULL com valor válido */
    int64_t v = smaug_dt_get(s, 0, NULL);
    CHECK(v == ep, "get NULL status: valor correto");
    /* status=NULL com null value */
    int64_t v2 = smaug_dt_get(s, 1, NULL);
    CHECK(v2 == INT64_MIN, "get NULL status: null → DT_SENTINEL");
    /* status=NULL com OOB */
    int64_t v3 = smaug_dt_get(s, 99, NULL);
    CHECK(v3 == INT64_MIN, "get NULL status: OOB → DT_SENTINEL");
    /* status=NULL com s=NULL */
    int64_t v4 = smaug_dt_get(NULL, 0, NULL);
    CHECK(v4 == INT64_MIN, "get NULL status: s=NULL → DT_SENTINEL");
    smaug_dt_free(s);
}

static void test_is_null_oob(void) {
    /* smaug_dt_is_null com idx OOB — linha 260 (idx >= s->size → true) */
    smaug_series_dt_t *s = smaug_dt_create(2);
    CHECK(smaug_dt_is_null(s, 999) == true, "is_null OOB → true");
    smaug_dt_free(s);
}

static void test_append_grow(void) {
    /* append além da capacidade inicial (linha 279: s->size >= s->capacity) */
    smaug_series_dt_t *s = smaug_dt_create(1); /* capacity mínima */
    int64_t ep = parse("2026-06-13T00:00:00Z");
    /* preenche a capacidade inicial */
    smaug_dt_set(s, 0, ep);
    /* append forçando crescimento */
    for (int i = 0; i < 8; i++) {
        int rc = smaug_dt_append(s, ep + (int64_t)i * 86400000LL);
        CHECK(rc == 0, "append grow: OK");
    }
    CHECK(s->size == 9, "append grow: size=9");
    /* append_null também deve crescer */
    int rc = smaug_dt_append_null(s);
    CHECK(rc == 0, "append_null grow: OK");
    CHECK(smaug_dt_is_null(s, 9), "append_null grow: null");
    smaug_dt_free(s);
}

static void test_parse_errors_extended(void) {
    int64_t ep;
    /* formato YYYY sem primeiro '-' */
    CHECK(smaug_dt_parse("20261301", 8, &ep, 0) == -1, "parse: sem '-' após ano");
    /* dígito inválido no mês (parse_digits, linha 306) */
    CHECK(smaug_dt_parse("2026-0A-01", 10, &ep, 0) == -1, "parse: dígito inválido no mês");
    /* sem '-' após mês */
    CHECK(smaug_dt_parse("2026-01X01", 10, &ep, 0) == -1, "parse: sem '-' após mês");
    /* sem ':' após hora (linha 333) */
    CHECK(smaug_dt_parse("2026-06-13T14X30:00Z", 20, &ep, 0) == -1, "parse: sem ':' após hora");
    /* sem ':' após minuto (linha 335) */
    CHECK(smaug_dt_parse("2026-06-13T14:30X00Z", 20, &ep, 0) == -1, "parse: sem ':' após minuto");
    /* minuto 60 inválido (linha 337) */
    CHECK(smaug_dt_parse("2026-06-13T14:60:00Z", 20, &ep, 0) == -1, "parse: minuto 60 inválido");
    /* segundo 60 inválido */
    CHECK(smaug_dt_parse("2026-06-13T14:30:60Z", 20, &ep, 0) == -1, "parse: segundo 60 inválido");
    /* timezone tz_h > 23 (linha 364) */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00+25:00", 25, &ep, 0) == -1, "parse: tz_h>23");
    /* timezone tz_m > 59 */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00+05:60", 25, &ep, 0) == -1, "parse: tz_m>59");
    /* separator ' ' (espaço) entre data e hora (linha 330) */
    CHECK(smaug_dt_parse("2026-06-13 14:30:00Z", 20, &ep, 0) == 0, "parse: sep=' ' válido");
    /* timezone sem ':' entre h e m (linha 362: colon opcional) */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00+0530", 24, &ep, 0) == 0, "parse: tz sem ':' válido");
    /* ms com 1 dígito → pad para 100ms (linha 350) */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00.5Z", 22, &ep, 0) == 0, "parse: ms 1 dígito");
    CHECK(ep % 1000 == 500, "parse: ms 1 dígito → 500ms");
    /* ms com 4 dígitos → só os 3 primeiros contam (linha 346) */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00.1234Z", 25, &ep, 0) == 0, "parse: ms 4 dígitos");
    CHECK(ep % 1000 == 123, "parse: ms 4 dígitos → 123ms");
}

static void test_format_small_buf(void) {
    /* smaug_dt_format com buffer pequeno → escrita truncada → retorna -1
     * (linha 408: written >= buf_size). */
    int64_t ep = parse("2026-06-13T00:00:00Z");
    char buf[5];
    int rc = smaug_dt_format(ep, buf, 5);
    CHECK(rc == -1, "format buf pequeno: retorna -1");
}

static void test_week_boundary(void) {
    /* ISO week < 1: Jan 1 de 2023 é domingo — doy=1, wd=6 (dom=6),
     * week = (1 - 7 + 10)/7 = 4/7 = 0 → branch week < 1 (linha 484). */
    int64_t ep;
    smaug_dt_parse("2023-01-01T00:00:00Z", 20, &ep, 0);
    int w = smaug_dt_week(ep);
    CHECK(w == 52 || w == 53, "week boundary Jan 1 2023 (domingo): semana do ano anterior");

    /* ISO week > 52 e semana 53 existe: 28-Dez de 2015 é segunda (wd=0 ≤ 3),
     * então semana 53 existe → Dec 31 2015 → week=53 (linha 496). */
    smaug_dt_parse("2015-12-31T00:00:00Z", 20, &ep, 0);
    w = smaug_dt_week(ep);
    CHECK(w == 53, "week Dec 31 2015: semana 53 existe");

    /* ISO week > 52 mas semana 53 NÃO existe: Dec 31 2018 → wd_dec28 > 3
     * → week = 1 (pertence a semana 1 de 2019) (linha 502). */
    smaug_dt_parse("2018-12-31T00:00:00Z", 20, &ep, 0);
    w = smaug_dt_week(ep);
    CHECK(w == 1, "week Dec 31 2018: pertence à semana 1 de 2019");

    /* wd_dec28 < 0: apenas com epoch_ms muito negativo (pré-~7M a.C.) —
     * inalcançável em uso prático; o branch wd < 0 em weekday (linha 453)
     * é exercitado por qualquer data pré-1970 com wd calculado negativo. */
    smaug_dt_parse("1969-01-01T00:00:00Z", 20, &ep, 0);
    w = smaug_dt_week(ep);
    CHECK(w >= 1 && w <= 53, "week pré-1970: dentro do intervalo");
}

static void test_from_parts_bounds(void) {
    /* ms < 0 e ms > 999 (linha 514-515) — não coberto pelos testes existentes */
    CHECK(smaug_dt_from_parts(2026,6,13,0,0,0,-1)  == INT64_MIN, "from_parts ms=-1");
    CHECK(smaug_dt_from_parts(2026,6,13,0,0,0,1000)== INT64_MIN, "from_parts ms=1000");
    CHECK(smaug_dt_from_parts(2026,6,13,0,0,-1,0)  == INT64_MIN, "from_parts sec=-1");
}

static void test_add_ms_overflow(void) {
    /* overflow positivo e negativo (linhas 537-538) */
    CHECK(smaug_dt_add_ms(INT64_MAX,  1) == INT64_MIN, "add_ms overflow+");
    CHECK(smaug_dt_add_ms(INT64_MIN, -1) == INT64_MIN, "add_ms overflow-");
}

static void test_truncate_negative(void) {
    /* truncate com epoch_ms negativo não múltiplo (linhas 546/549/552) */
    /* -1500ms = 1500ms antes de epoch; segundo: floor = -2000ms */
    int64_t t_s = smaug_dt_truncate(-1500LL, 's');
    CHECK(t_s == -2000LL, "truncate 's' negativo não múltiplo");
    /* -90001ms (não múltiplo de 60000): floor minuto = -120000ms */
    int64_t t_m = smaug_dt_truncate(-90001LL, 'm');
    CHECK(t_m == -120000LL, "truncate 'm' negativo não múltiplo");
    /* -3601000ms (não múltiplo de 3600000): floor hora = -7200000ms */
    int64_t t_h = smaug_dt_truncate(-3601000LL, 'h');
    CHECK(t_h == -7200000LL, "truncate 'h' negativo não múltiplo");
}

static void test_take_filter_null_args(void) {
    /* smaug_dt_take/filter com NULL (linhas 681/698) */
    smaug_series_dt_t *s = smaug_dt_create(2);
    size_t idx[1] = {0};
    CHECK(smaug_dt_take(NULL, idx, 1) == NULL, "take NULL série");
    CHECK(smaug_dt_take(s, NULL, 1)   == NULL, "take NULL idx");
    uint8_t mask[2] = {1, 0};
    CHECK(smaug_dt_filter(NULL, mask) == NULL, "filter NULL série");
    CHECK(smaug_dt_filter(s, NULL)    == NULL, "filter NULL mask");
    smaug_dt_free(s);
}

static void test_argsort_empate(void) {
    /* cmp_dt_asc retorna 1 (linha 624: ea->val > eb->val) exige dois
     * valores onde a > b na ordenação. O teste existente tem 4 valores
     * distintos — adicionar aqui um com duplicatas para garantir o ramo. */
    int64_t vals[3] = {
        parse("2026-06-13T00:00:00Z"),
        parse("2026-06-13T00:00:00Z"), /* duplicata */
        parse("2026-01-01T00:00:00Z"),
    };
    smaug_series_dt_t *s = smaug_dt_create_from_array(vals, 3);
    size_t *idx = smaug_dt_argsort(s, true);
    CHECK(idx != NULL,     "argsort com empate: retorna índices");
    CHECK(idx[0] == 2,     "argsort empate: menor primeiro");
    free(idx);
    /* descendente: verifica que ramo > também é exercitado */
    size_t *idx2 = smaug_dt_argsort(s, false);
    CHECK(idx2 != NULL,    "argsort desc com empate: OK");
    CHECK(idx2[2] == 2,    "argsort desc: menor no final");
    free(idx2);
    smaug_dt_free(s);
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
    smaug_series_dt_t *s = smaug_dt_create_from_array(dates, 3);
    int64_t ref = parse("2026-06-13T00:00:00Z");

    uint8_t *gt = smaug_dt_gt(s, ref, NULL);
    CHECK(gt && gt[2] == 1, "gt out_mask=NULL: resultado correto");
    smaug_free(gt);
    uint8_t *lt = smaug_dt_lt(s, ref, NULL);
    CHECK(lt && lt[0] == 1, "lt out_mask=NULL: resultado correto");
    smaug_free(lt);
    uint8_t *eq = smaug_dt_eq(s, ref, NULL);
    CHECK(eq && eq[1] == 1, "eq out_mask=NULL: resultado correto");
    smaug_free(eq);
    uint8_t *ge = smaug_dt_ge(s, ref, NULL);
    CHECK(ge && ge[1] == 1, "ge out_mask=NULL: resultado correto");
    smaug_free(ge);
    uint8_t *le = smaug_dt_le(s, ref, NULL);
    CHECK(le && le[1] == 1, "le out_mask=NULL: resultado correto");
    smaug_free(le);
    uint8_t *ne = smaug_dt_ne(s, ref, NULL);
    CHECK(ne && ne[0] == 1, "ne out_mask=NULL: resultado correto");
    smaug_free(ne);

    /* também: comparador com null no meio + out_mask=NULL (INVALID_DT branch
     * sem capturar máscara) — garante que os 6 tratam null sem out_mask */
    smaug_dt_set_null(s, 1);
    uint8_t *gt2 = smaug_dt_gt(s, ref, NULL);
    CHECK(gt2 && gt2[1] == 0, "gt out_mask=NULL com null: posição null = 0");
    smaug_free(gt2);

    smaug_dt_free(s);
}

static void test_parse_digit_below_zero(void) {
    /* parse_digits L306 branch 0: caractere ABAIXO de '0' (ex '/' = 0x2F).
     * Os testes existentes só usavam letras (acima de '9'). */
    int64_t ep;
    CHECK(smaug_dt_parse("2026-/1-01", 10, &ep, 0) == -1, "parse: '/' no mês (abaixo de '0')");
    CHECK(smaug_dt_parse("202/-01-01", 10, &ep, 0) == -1, "parse: '/' no ano");
}

static void test_parse_tz_minus(void) {
    /* L358 branch do '-' no timezone (o '+' já era testado; o '-' com offset
     * que efetivamente subtrai precisa de caso próprio com minutos). */
    int64_t ep_plus, ep_minus;
    CHECK(smaug_dt_parse("2026-06-13T12:00:00+02:30", 25, &ep_plus, 0)  == 0, "parse tz +02:30");
    CHECK(smaug_dt_parse("2026-06-13T12:00:00-02:30", 25, &ep_minus, 0) == 0, "parse tz -02:30");
    /* +02:30 recua 2h30 em UTC; -02:30 avança 2h30 — diferença de 5h */
    CHECK(ep_minus - ep_plus == 5LL*3600*1000, "parse tz: +/- diferem por 5h");
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

static void test_truncate_negative_min_hour(void) {
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
    for (int y = 1900; y < 1970; y++) {
        int64_t ep = smaug_dt_from_parts(y, 1, 1, 0, 0, 0, 0);
        if (ep == INT64_MIN) continue;
        int w = smaug_dt_week(ep);
        CHECK(w >= 1 && w <= 53, "week pré-1970 jan1: intervalo válido");
        int64_t ep2 = smaug_dt_from_parts(y, 12, 31, 0, 0, 0, 0);
        int w2 = smaug_dt_week(ep2);
        CHECK(w2 >= 1 && w2 <= 53, "week pré-1970 dez31: intervalo válido");
        saw_valid = 1;
    }
    CHECK(saw_valid, "week pré-1970: varreu anos válidos");
}



int main(void) {
    test_lifecycle();
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
    test_format_small_buf();
    test_components();
    test_week_boundary();
    test_from_parts();
    test_from_parts_bounds();
    test_arithmetic();
    test_add_ms_overflow();
    test_truncate_negative();
    test_comparisons();
    test_sort_take_filter();
    test_take_filter_null_args();
    test_argsort_empate();
    test_comparisons_outmask_null();
    test_parse_digit_below_zero();
    test_parse_tz_minus();
    test_from_parts_each_bound();
    test_truncate_negative_min_hour();
    test_week_pre1970();
    test_edge_dates();
    test_roundtrip();

    if (g_fail == 0)
        printf("PASS: test_datetime_c (%d checks)\n", g_ok);
    else
        printf("FAIL: %d/%d checks falharam\n", g_fail, g_ok + g_fail);

    return g_fail > 0 ? 1 : 0;
}
