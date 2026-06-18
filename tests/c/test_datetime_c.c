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
    int r = smaug_dt_parse(s, strlen(s), &ep);
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
    CHECK(smaug_dt_parse("1970-01-01T00:00:00Z", 20, &ep) == 0, "parse epoch");
    CHECK(ep == 0, "epoch = 0");

    /* só data (meia-noite UTC) */
    CHECK(smaug_dt_parse("1970-01-02", 10, &ep) == 0, "parse só data");
    CHECK(ep == 86400000LL, "só data = 1 dia em ms");

    /* com milissegundos */
    CHECK(smaug_dt_parse("1970-01-01T00:00:00.500Z", 24, &ep) == 0, "parse com ms");
    CHECK(ep == 500, "500 ms");

    /* com offset +03:00 */
    CHECK(smaug_dt_parse("1970-01-01T03:00:00+03:00", 25, &ep) == 0, "parse +03:00");
    CHECK(ep == 0, "UTC=0 com offset +03:00");

    /* com offset -05:30 */
    CHECK(smaug_dt_parse("1970-01-01T00:00:00-05:30", 25, &ep) == 0, "parse -05:30");
    CHECK(ep == (5*60+30)*60*1000LL, "-05:30 → UTC+19800000ms");

    /* data negativa: 1969-12-31 = -1 dia */
    CHECK(smaug_dt_parse("1969-12-31T00:00:00Z", 20, &ep) == 0, "parse pré-1970");
    CHECK(ep == -86400000LL, "1969-12-31 = -1 dia");

    /* formato inválido */
    CHECK(smaug_dt_parse("abc", 3, &ep) == -1, "parse inválido");
    CHECK(smaug_dt_parse("2026-13-01", 10, &ep) == -1, "mês 13 inválido");
    CHECK(smaug_dt_parse("2026-02-30", 10, &ep) == -1, "fev 30 inválido");
    CHECK(smaug_dt_parse("2026-06-13T25:00:00Z", 20, &ep) == -1, "hora 25 inválida");
    CHECK(smaug_dt_parse(NULL, 0, &ep) == -1, "parse NULL");
    CHECK(smaug_dt_parse("2026-06-13T00:00:00Z", 20, NULL) == -1, "out NULL");

    /* com lixo no final */
    CHECK(smaug_dt_parse("2026-06-13T00:00:00ZLIXO", 24, &ep) == -1, "lixo no final");
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
    CHECK(smaug_dt_parse("1900-02-29", 10, &ep_neg) == -1, "1900 não bissexto");
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
        int r = smaug_dt_parse(cases[i], strlen(cases[i]), &ep);
        CHECK(r == 0, "roundtrip parse OK");
        r = smaug_dt_format(ep, buf, 26);
        CHECK(r == 0, "roundtrip format OK");
        CHECK(strcmp(buf, cases[i]) == 0, "roundtrip idêntico");
    }
}

/* ===================================================================
   main
   =================================================================== */

int main(void) {
    test_lifecycle();
    test_clone();
    test_view_cow();
    test_append();
    test_create_from_array();
    test_parse();
    test_format();
    test_components();
    test_from_parts();
    test_arithmetic();
    test_comparisons();
    test_sort_take_filter();
    test_edge_dates();
    test_roundtrip();

    if (g_fail == 0)
        printf("PASS: test_datetime_c (%d checks)\n", g_ok);
    else
        printf("FAIL: %d/%d checks falharam\n", g_fail, g_ok + g_fail);

    return g_fail > 0 ? 1 : 0;
}
