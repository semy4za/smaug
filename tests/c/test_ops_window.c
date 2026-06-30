/* tests/test_ops_window.c
 *
 * Testes C para as primitivas do Grupo A, B e C (Fase 3 Ring 0):
 * cumsum, cumprod, cummin, cummax, diff, shift, ffill, bfill, argmin, argmax,
 * sorted_nonnull, rank (Grupos A+B) e multi_argsort, rolling_* (Grupo C).
 */

#include "../include/smaug_numeric.h"
#include "../include/smaug_ops_window.h"
#include "../include/smaug_string.h"
#include "../include/smaug_datetime.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

static int g_checks = 0;
static int g_fails  = 0;

#define CHECK(cond, msg) do { \
    g_checks++; \
    if (!(cond)) { g_fails++; fprintf(stderr, "FAIL [%s:%d]: %s\n", __FILE__, __LINE__, msg); } \
} while (0)

#define APPROX(a, b) (fabs((a) - (b)) < 1e-9)

/* =====================================================================
   Helpers de construção
   ===================================================================== */

/* Cria série f64 a partir de array; -9999.0 indica null. */
static smaug_series_f64_t *f64_from(const double *arr, size_t n) {
    smaug_series_f64_t *s = smaug_f64_create(n);
    if (!s) return NULL;
    for (size_t i = 0; i < n; i++) {
        if (arr[i] == -9999.0) smaug_f64_set_null(s, i);
        else                   smaug_f64_set(s, i, arr[i]);
    }
    return s;
}

/* Cria série i64; INT64_MIN indica null. */
static smaug_series_i64_t *i64_from(const int64_t *arr, size_t n) {
    smaug_series_i64_t *s = smaug_i64_create(n);
    if (!s) return NULL;
    for (size_t i = 0; i < n; i++) {
        if (arr[i] == INT64_MIN) smaug_i64_set_null(s, i);
        else                     smaug_i64_set(s, i, arr[i]);
    }
    return s;
}

static double f64_get(const smaug_series_f64_t *s, size_t i) {
    smaug_status_t st;
    return smaug_f64_get(s, i, &st);
}
static int f64_null(const smaug_series_f64_t *s, size_t i) {
    smaug_status_t st;
    smaug_f64_get(s, i, &st);
    return st == SMG_NULL_VALUE;
}
static int64_t i64_get(const smaug_series_i64_t *s, size_t i) {
    smaug_status_t st;
    return smaug_i64_get(s, i, &st);
}
static int i64_null(const smaug_series_i64_t *s, size_t i) {
    smaug_status_t st;
    smaug_i64_get(s, i, &st);
    return st == SMG_NULL_VALUE;
}

/* Cria série bool a partir de string-padrão: '1'=true, '0'=false, 'N'=null. */
static smaug_series_bool_t *bool_from(const char *pat) {
    size_t n = strlen(pat);
    smaug_series_bool_t *s = smaug_bool_create(n);
    if (!s) return NULL;
    for (size_t i = 0; i < n; i++) {
        if (pat[i] == 'N') smaug_bool_set_null(s, i);
        else               smaug_bool_set(s, i, pat[i] == '1' ? 1 : 0);
    }
    return s;
}
static int bool_get(const smaug_series_bool_t *s, size_t i) {
    smaug_status_t st;
    return smaug_bool_get(s, i, &st);
}
static int bool_null(const smaug_series_bool_t *s, size_t i) {
    smaug_status_t st;
    smaug_bool_get(s, i, &st);
    return st == SMG_NULL_VALUE;
}

/* Cria série dt; INT64_MIN indica null (epoch ms cru). */
static smaug_series_dt_t *dt_from(const int64_t *arr, size_t n) {
    smaug_series_dt_t *s = smaug_dt_create(n);
    if (!s) return NULL;
    for (size_t i = 0; i < n; i++) {
        if (arr[i] == INT64_MIN) smaug_dt_set_null(s, i);
        else                     smaug_dt_set(s, i, arr[i]);
    }
    return s;
}
static int64_t dt_get(const smaug_series_dt_t *s, size_t i) {
    smaug_status_t st;
    return smaug_dt_get(s, i, &st);
}
static int dt_null(const smaug_series_dt_t *s, size_t i) {
    smaug_status_t st;
    smaug_dt_get(s, i, &st);
    return st != SMG_OK;
}

/* Lê string na posição i; preenche *is_null. Retorna ponteiro (não-terminado),
   use com *len. */
static const char *str_get(const smaug_series_str_t *s, size_t i, size_t *len, int *is_null) {
    const char *p = smaug_str_get(s, i, len);
    *is_null = (p == NULL);
    return p;
}
/* Compara string na posição i com literal c (NUL-terminado). */
static int str_eq_at(const smaug_series_str_t *s, size_t i, const char *c) {
    size_t len; int isn;
    const char *p = str_get(s, i, &len, &isn);
    if (isn) return 0;
    size_t cl = strlen(c);
    return len == cl && (cl == 0 || memcmp(p, c, cl) == 0);
}

/* =====================================================================
   cumsum
   ===================================================================== */

static void test_f64_cumsum(void) {
    /* [1, 2, 3] → [1, 3, 6] */
    double arr[] = {1.0, 2.0, 3.0};
    smaug_series_f64_t *s = f64_from(arr, 3);
    smaug_series_f64_t *r = smaug_f64_cumsum(s);
    CHECK(r && !f64_null(r, 0) && APPROX(f64_get(r, 0), 1.0), "f64 cumsum [0]=1");
    CHECK(r && !f64_null(r, 1) && APPROX(f64_get(r, 1), 3.0), "f64 cumsum [1]=3");
    CHECK(r && !f64_null(r, 2) && APPROX(f64_get(r, 2), 6.0), "f64 cumsum [2]=6");
    smaug_f64_free(r); smaug_f64_free(s);

    /* [1, null, 3] → [1, null, null] (null propaga) */
    double arr2[] = {1.0, -9999.0, 3.0};
    smaug_series_f64_t *s2 = f64_from(arr2, 3);
    smaug_series_f64_t *r2 = smaug_f64_cumsum(s2);
    CHECK(r2 && !f64_null(r2, 0) && APPROX(f64_get(r2, 0), 1.0), "f64 cumsum null prop [0]=1");
    CHECK(r2 && f64_null(r2, 1),  "f64 cumsum null prop [1]=null");
    CHECK(r2 && f64_null(r2, 2),  "f64 cumsum null prop [2]=null");
    smaug_f64_free(r2); smaug_f64_free(s2);

    /* série vazia */
    smaug_series_f64_t *se = smaug_f64_create(0);
    smaug_series_f64_t *re = smaug_f64_cumsum(se);
    CHECK(re && re->size == 0, "f64 cumsum vazia");
    smaug_f64_free(re); smaug_f64_free(se);

    /* NULL input */
    CHECK(smaug_f64_cumsum(NULL) == NULL, "f64 cumsum NULL input");
}

static void test_i64_cumsum(void) {
    int64_t arr[] = {1, 2, 3};
    smaug_series_i64_t *s = i64_from(arr, 3);
    smaug_series_i64_t *r = smaug_i64_cumsum(s);
    CHECK(r && !i64_null(r, 0) && i64_get(r, 0) == 1, "i64 cumsum [0]=1");
    CHECK(r && !i64_null(r, 1) && i64_get(r, 1) == 3, "i64 cumsum [1]=3");
    CHECK(r && !i64_null(r, 2) && i64_get(r, 2) == 6, "i64 cumsum [2]=6");
    smaug_i64_free(r); smaug_i64_free(s);

    int64_t arr2[] = {1, INT64_MIN, 3};
    smaug_series_i64_t *s2 = i64_from(arr2, 3);
    smaug_series_i64_t *r2 = smaug_i64_cumsum(s2);
    CHECK(r2 && !i64_null(r2, 0) && i64_get(r2, 0) == 1, "i64 cumsum null [0]=1");
    CHECK(r2 && i64_null(r2, 1), "i64 cumsum null [1]=null");
    CHECK(r2 && i64_null(r2, 2), "i64 cumsum null [2]=null");
    smaug_i64_free(r2); smaug_i64_free(s2);

    CHECK(smaug_i64_cumsum(NULL) == NULL, "i64 cumsum NULL input");
}

/* =====================================================================
   cumprod
   ===================================================================== */

static void test_f64_cumprod(void) {
    double arr[] = {2.0, 3.0, 4.0};
    smaug_series_f64_t *s = f64_from(arr, 3);
    smaug_series_f64_t *r = smaug_f64_cumprod(s);
    CHECK(r && APPROX(f64_get(r, 0), 2.0),  "f64 cumprod [0]=2");
    CHECK(r && APPROX(f64_get(r, 1), 6.0),  "f64 cumprod [1]=6");
    CHECK(r && APPROX(f64_get(r, 2), 24.0), "f64 cumprod [2]=24");
    smaug_f64_free(r); smaug_f64_free(s);

    double arr2[] = {2.0, -9999.0, 3.0};
    smaug_series_f64_t *s2 = f64_from(arr2, 3);
    smaug_series_f64_t *r2 = smaug_f64_cumprod(s2);
    CHECK(r2 && APPROX(f64_get(r2, 0), 2.0), "f64 cumprod null [0]=2");
    CHECK(r2 && f64_null(r2, 1), "f64 cumprod null [1]=null");
    CHECK(r2 && f64_null(r2, 2), "f64 cumprod null [2]=null");
    smaug_f64_free(r2); smaug_f64_free(s2);

    CHECK(smaug_f64_cumprod(NULL) == NULL, "f64 cumprod NULL input");
}

static void test_i64_cumprod(void) {
    int64_t arr[] = {2, 3, 4};
    smaug_series_i64_t *s = i64_from(arr, 3);
    smaug_series_i64_t *r = smaug_i64_cumprod(s);
    CHECK(r && i64_get(r, 0) == 2,  "i64 cumprod [0]=2");
    CHECK(r && i64_get(r, 1) == 6,  "i64 cumprod [1]=6");
    CHECK(r && i64_get(r, 2) == 24, "i64 cumprod [2]=24");
    smaug_i64_free(r); smaug_i64_free(s);

    CHECK(smaug_i64_cumprod(NULL) == NULL, "i64 cumprod NULL input");
}

/* =====================================================================
   cummin / cummax
   ===================================================================== */

static void test_f64_cummin(void) {
    /* [3, 1, 4, 1, 5] → [3, 1, 1, 1, 1] */
    double arr[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *s = f64_from(arr, 5);
    smaug_series_f64_t *r = smaug_f64_cummin(s);
    CHECK(r && APPROX(f64_get(r, 0), 3.0), "f64 cummin [0]=3");
    CHECK(r && APPROX(f64_get(r, 1), 1.0), "f64 cummin [1]=1");
    CHECK(r && APPROX(f64_get(r, 2), 1.0), "f64 cummin [2]=1");
    CHECK(r && APPROX(f64_get(r, 4), 1.0), "f64 cummin [4]=1");
    smaug_f64_free(r); smaug_f64_free(s);

    /* [3, null, 1] → [3, null, 1] (null não propaga para frente) */
    double arr2[] = {3.0, -9999.0, 1.0};
    smaug_series_f64_t *s2 = f64_from(arr2, 3);
    smaug_series_f64_t *r2 = smaug_f64_cummin(s2);
    CHECK(r2 && APPROX(f64_get(r2, 0), 3.0), "f64 cummin null [0]=3");
    CHECK(r2 && f64_null(r2, 1),              "f64 cummin null [1]=null");
    CHECK(r2 && APPROX(f64_get(r2, 2), 1.0), "f64 cummin null [2]=1 (nao propaga)");
    smaug_f64_free(r2); smaug_f64_free(s2);

    CHECK(smaug_f64_cummin(NULL) == NULL, "f64 cummin NULL input");
}

static void test_f64_cummax(void) {
    double arr[] = {1.0, 3.0, 2.0, 5.0, 4.0};
    smaug_series_f64_t *s = f64_from(arr, 5);
    smaug_series_f64_t *r = smaug_f64_cummax(s);
    CHECK(r && APPROX(f64_get(r, 0), 1.0), "f64 cummax [0]=1");
    CHECK(r && APPROX(f64_get(r, 1), 3.0), "f64 cummax [1]=3");
    CHECK(r && APPROX(f64_get(r, 2), 3.0), "f64 cummax [2]=3");
    CHECK(r && APPROX(f64_get(r, 3), 5.0), "f64 cummax [3]=5");
    CHECK(r && APPROX(f64_get(r, 4), 5.0), "f64 cummax [4]=5");
    smaug_f64_free(r); smaug_f64_free(s);

    CHECK(smaug_f64_cummax(NULL) == NULL, "f64 cummax NULL input");
}

static void test_i64_cummin(void) {
    int64_t arr[] = {5, 2, 8, 1};
    smaug_series_i64_t *s = i64_from(arr, 4);
    smaug_series_i64_t *r = smaug_i64_cummin(s);
    CHECK(r && i64_get(r, 0) == 5, "i64 cummin [0]=5");
    CHECK(r && i64_get(r, 1) == 2, "i64 cummin [1]=2");
    CHECK(r && i64_get(r, 2) == 2, "i64 cummin [2]=2");
    CHECK(r && i64_get(r, 3) == 1, "i64 cummin [3]=1");
    smaug_i64_free(r); smaug_i64_free(s);

    /* null não propaga */
    int64_t arr2[] = {5, INT64_MIN, 1};
    smaug_series_i64_t *s2 = i64_from(arr2, 3);
    smaug_series_i64_t *r2 = smaug_i64_cummin(s2);
    CHECK(r2 && i64_get(r2, 0) == 5, "i64 cummin null [0]=5");
    CHECK(r2 && i64_null(r2, 1),     "i64 cummin null [1]=null");
    CHECK(r2 && i64_get(r2, 2) == 1, "i64 cummin null [2]=1");
    smaug_i64_free(r2); smaug_i64_free(s2);

    CHECK(smaug_i64_cummin(NULL) == NULL, "i64 cummin NULL input");
}

static void test_i64_cummax(void) {
    int64_t arr[] = {1, 3, 2};
    smaug_series_i64_t *s = i64_from(arr, 3);
    smaug_series_i64_t *r = smaug_i64_cummax(s);
    CHECK(r && i64_get(r, 0) == 1, "i64 cummax [0]=1");
    CHECK(r && i64_get(r, 1) == 3, "i64 cummax [1]=3");
    CHECK(r && i64_get(r, 2) == 3, "i64 cummax [2]=3");
    smaug_i64_free(r); smaug_i64_free(s);
    CHECK(smaug_i64_cummax(NULL) == NULL, "i64 cummax NULL input");
}

/* =====================================================================
   diff
   ===================================================================== */

static void test_f64_diff(void) {
    /* periods=1: [10, 13, 11] → [null, 3, -2] */
    double arr[] = {10.0, 13.0, 11.0};
    smaug_series_f64_t *s = f64_from(arr, 3);
    smaug_series_f64_t *r = smaug_f64_diff(s, 1);
    CHECK(r && f64_null(r, 0),                "f64 diff [0]=null");
    CHECK(r && APPROX(f64_get(r, 1),  3.0),   "f64 diff [1]=3");
    CHECK(r && APPROX(f64_get(r, 2), -2.0),   "f64 diff [2]=-2");
    smaug_f64_free(r); smaug_f64_free(s);

    /* periods=2: [1, 2, 4, 8] → [null, null, 3, 6] */
    double arr2[] = {1.0, 2.0, 4.0, 8.0};
    smaug_series_f64_t *s2 = f64_from(arr2, 4);
    smaug_series_f64_t *r2 = smaug_f64_diff(s2, 2);
    CHECK(r2 && f64_null(r2, 0), "f64 diff p2 [0]=null");
    CHECK(r2 && f64_null(r2, 1), "f64 diff p2 [1]=null");
    CHECK(r2 && APPROX(f64_get(r2, 2), 3.0), "f64 diff p2 [2]=3");
    CHECK(r2 && APPROX(f64_get(r2, 3), 6.0), "f64 diff p2 [3]=6");
    smaug_f64_free(r2); smaug_f64_free(s2);

    /* null em operando */
    double arr3[] = {1.0, -9999.0, 3.0};
    smaug_series_f64_t *s3 = f64_from(arr3, 3);
    smaug_series_f64_t *r3 = smaug_f64_diff(s3, 1);
    CHECK(r3 && f64_null(r3, 0), "f64 diff null op [0]=null");
    CHECK(r3 && f64_null(r3, 1), "f64 diff null op [1]=null (null-curr)");
    CHECK(r3 && f64_null(r3, 2), "f64 diff null op [2]=null (null-prev)");
    smaug_f64_free(r3); smaug_f64_free(s3);

    CHECK(smaug_f64_diff(NULL, 1) == NULL, "f64 diff NULL input");
}

static void test_i64_diff(void) {
    int64_t arr[] = {10, 13, 11};
    smaug_series_i64_t *s = i64_from(arr, 3);
    smaug_series_i64_t *r = smaug_i64_diff(s, 1);
    CHECK(r && i64_null(r, 0),         "i64 diff [0]=null");
    CHECK(r && i64_get(r, 1) == 3,     "i64 diff [1]=3");
    CHECK(r && i64_get(r, 2) == -2,    "i64 diff [2]=-2");
    smaug_i64_free(r); smaug_i64_free(s);
    CHECK(smaug_i64_diff(NULL, 1) == NULL, "i64 diff NULL input");
}

/* =====================================================================
   shift
   ===================================================================== */

static void test_f64_shift(void) {
    /* periods=1: [1, 2, 3] → [null, 1, 2] */
    double arr[] = {1.0, 2.0, 3.0};
    smaug_series_f64_t *s = f64_from(arr, 3);
    smaug_series_f64_t *r = smaug_f64_shift(s, 1);
    CHECK(r && f64_null(r, 0),               "f64 shift [0]=null");
    CHECK(r && APPROX(f64_get(r, 1), 1.0),   "f64 shift [1]=1");
    CHECK(r && APPROX(f64_get(r, 2), 2.0),   "f64 shift [2]=2");
    smaug_f64_free(r); smaug_f64_free(s);

    /* periods=0: clone */
    smaug_series_f64_t *s2 = f64_from(arr, 3);
    smaug_series_f64_t *r2 = smaug_f64_shift(s2, 0);
    CHECK(r2 && APPROX(f64_get(r2, 0), 1.0), "f64 shift p0 [0]=1");
    CHECK(r2 && APPROX(f64_get(r2, 2), 3.0), "f64 shift p0 [2]=3");
    smaug_f64_free(r2); smaug_f64_free(s2);

    /* periods >= size: toda null */
    smaug_series_f64_t *s3 = f64_from(arr, 3);
    smaug_series_f64_t *r3 = smaug_f64_shift(s3, 5);
    CHECK(r3 && f64_null(r3, 0) && f64_null(r3, 1) && f64_null(r3, 2),
          "f64 shift >= size: toda null");
    smaug_f64_free(r3); smaug_f64_free(s3);

    /* null preservado */
    double arr4[] = {1.0, -9999.0, 3.0};
    smaug_series_f64_t *s4 = f64_from(arr4, 3);
    smaug_series_f64_t *r4 = smaug_f64_shift(s4, 1);
    CHECK(r4 && f64_null(r4, 0),               "f64 shift null [0]=null");
    CHECK(r4 && APPROX(f64_get(r4, 1), 1.0),   "f64 shift null [1]=1");
    CHECK(r4 && f64_null(r4, 2),               "f64 shift null [2]=null (null deslocado)");
    smaug_f64_free(r4); smaug_f64_free(s4);

    /* periods NEGATIVO (item 7.1b): [1,2,3] shift(-1) → [2,3,null] */
    smaug_series_f64_t *s5 = f64_from(arr, 3);
    smaug_series_f64_t *r5 = smaug_f64_shift(s5, -1);
    CHECK(r5 && APPROX(f64_get(r5, 0), 2.0), "f64 shift(-1) [0]=2");
    CHECK(r5 && APPROX(f64_get(r5, 1), 3.0), "f64 shift(-1) [1]=3");
    CHECK(r5 && f64_null(r5, 2),             "f64 shift(-1) [2]=null (borda final)");
    smaug_f64_free(r5); smaug_f64_free(s5);

    /* periods <= -size: toda null */
    smaug_series_f64_t *s6 = f64_from(arr, 3);
    smaug_series_f64_t *r6 = smaug_f64_shift(s6, -5);
    CHECK(r6 && f64_null(r6, 0) && f64_null(r6, 2), "f64 shift(-5): toda null");
    smaug_f64_free(r6); smaug_f64_free(s6);

    /* shift negativo com null preservado: [1,NA,3] shift(-1) → [NA,3,NA] */
    smaug_series_f64_t *s7 = f64_from(arr4, 3);
    smaug_series_f64_t *r7 = smaug_f64_shift(s7, -1);
    CHECK(r7 && f64_null(r7, 0),             "f64 shift(-1) null [0]=null (NA deslocado)");
    CHECK(r7 && APPROX(f64_get(r7, 1), 3.0), "f64 shift(-1) null [1]=3");
    CHECK(r7 && f64_null(r7, 2),             "f64 shift(-1) null [2]=null (borda)");
    smaug_f64_free(r7); smaug_f64_free(s7);

    CHECK(smaug_f64_shift(NULL, 1) == NULL, "f64 shift NULL input");
}

static void test_i64_shift(void) {
    int64_t arr[] = {10, 20, 30};
    smaug_series_i64_t *s = i64_from(arr, 3);
    smaug_series_i64_t *r = smaug_i64_shift(s, 1);
    CHECK(r && i64_null(r, 0),       "i64 shift [0]=null");
    CHECK(r && i64_get(r, 1) == 10,  "i64 shift [1]=10");
    CHECK(r && i64_get(r, 2) == 20,  "i64 shift [2]=20");
    smaug_i64_free(r);
    /* negativo (item 7.1b): [10,20,30] shift(-1) → [20,30,null] */
    smaug_series_i64_t *rn = smaug_i64_shift(s, -1);
    CHECK(rn && i64_get(rn, 0) == 20, "i64 shift(-1) [0]=20");
    CHECK(rn && i64_get(rn, 1) == 30, "i64 shift(-1) [1]=30");
    CHECK(rn && i64_null(rn, 2),      "i64 shift(-1) [2]=null");
    smaug_i64_free(rn);
    /* shift(0) = clone */
    smaug_series_i64_t *r0 = smaug_i64_shift(s, 0);
    CHECK(r0 && i64_get(r0, 0) == 10 && i64_get(r0, 2) == 30, "i64 shift(0)=clone");
    smaug_i64_free(r0);
    smaug_i64_free(s);
    CHECK(smaug_i64_shift(NULL, 1) == NULL, "i64 shift NULL input");
}

/* shift em bool/str/dt (item 7.1b: motor agnóstico, com sinal) */
static void test_typed_shift(void) {
    /* bool: "101" shift(1) → [NA,1,0] ; shift(-1) → [0,1,NA] */
    smaug_series_bool_t *b = bool_from("101");
    smaug_series_bool_t *bp = smaug_bool_shift(b, 1);
    CHECK(bp && bool_null(bp, 0) && bool_get(bp, 1) == 1 && bool_get(bp, 2) == 0,
          "bool shift(1)");
    smaug_bool_free(bp);
    smaug_series_bool_t *bn = smaug_bool_shift(b, -1);
    CHECK(bn && bool_get(bn, 0) == 0 && bool_get(bn, 1) == 1 && bool_null(bn, 2),
          "bool shift(-1)");
    smaug_bool_free(bn);
    smaug_bool_free(b);
    CHECK(smaug_bool_shift(NULL, 1) == NULL, "bool shift NULL");

    /* dt: [100,200,300] shift(1) → [NA,100,200] ; shift(-1) → [200,300,NA] */
    int64_t da[] = {100, 200, 300};
    smaug_series_dt_t *d = dt_from(da, 3);
    smaug_series_dt_t *dp = smaug_dt_shift(d, 1);
    CHECK(dp && dt_null(dp, 0) && dt_get(dp, 1) == 100 && dt_get(dp, 2) == 200,
          "dt shift(1)");
    smaug_dt_free(dp);
    smaug_series_dt_t *dn = smaug_dt_shift(d, -1);
    CHECK(dn && dt_get(dn, 0) == 200 && dt_get(dn, 2 - 1) == 300 && dt_null(dn, 2),
          "dt shift(-1)");
    smaug_dt_free(dn);
    smaug_dt_free(d);
    CHECK(smaug_dt_shift(NULL, 1) == NULL, "dt shift NULL");

    /* str: ["a","b","c"] shift(1) → [NA,a,b] ; shift(-2) → [c,NA,NA] */
    smaug_series_str_t *s = smaug_str_create(3);
    smaug_str_set(s, 0, "a", 1);
    smaug_str_set(s, 1, "b", 1);
    smaug_str_set(s, 2, "c", 1);
    smaug_series_str_t *sp = smaug_str_shift(s, 1);
    size_t len; int isn;
    str_get(sp, 0, &len, &isn);
    CHECK(isn,                     "str shift(1) [0]=null");
    CHECK(str_eq_at(sp, 1, "a"),   "str shift(1) [1]=a");
    CHECK(str_eq_at(sp, 2, "b"),   "str shift(1) [2]=b");
    smaug_str_free(sp);
    smaug_series_str_t *sn = smaug_str_shift(s, -2);
    CHECK(str_eq_at(sn, 0, "c"),   "str shift(-2) [0]=c");
    str_get(sn, 1, &len, &isn); CHECK(isn, "str shift(-2) [1]=null");
    str_get(sn, 2, &len, &isn); CHECK(isn, "str shift(-2) [2]=null");
    smaug_str_free(sn);
    /* |shift| >= size → toda null */
    smaug_series_str_t *sbig = smaug_str_shift(s, 9);
    str_get(sbig, 0, &len, &isn); CHECK(isn, "str shift(9) all-null [0]");
    str_get(sbig, 2, &len, &isn); CHECK(isn, "str shift(9) all-null [2]");
    smaug_str_free(sbig);
    /* str shift com NA na fonte: [a,NA,c] shift(1) → [NA,a,NA] */
    smaug_series_str_t *s2 = smaug_str_create(3);
    smaug_str_set(s2, 0, "a", 1);
    smaug_str_set(s2, 2, "c", 1);
    smaug_series_str_t *s2p = smaug_str_shift(s2, 1);
    str_get(s2p, 0, &len, &isn); CHECK(isn, "str shift(1) NA [0]=null");
    CHECK(str_eq_at(s2p, 1, "a"),               "str shift(1) NA [1]=a");
    str_get(s2p, 2, &len, &isn); CHECK(isn, "str shift(1) NA [2]=null (NA deslocado)");
    smaug_str_free(s2p); smaug_str_free(s2);
    smaug_str_free(s);
    CHECK(smaug_str_shift(NULL, 1) == NULL, "str shift NULL");
}

/* =====================================================================
   ffill / bfill
   ===================================================================== */

static void test_f64_ffill(void) {
    /* [null, 1, null, 3, null] → [null, 1, 1, 3, 3] */
    double arr[] = {-9999.0, 1.0, -9999.0, 3.0, -9999.0};
    smaug_series_f64_t *s = f64_from(arr, 5);
    smaug_series_f64_t *r = smaug_f64_ffill(s);
    CHECK(r && f64_null(r, 0),               "f64 ffill [0]=null (sem valor anterior)");
    CHECK(r && APPROX(f64_get(r, 1), 1.0),   "f64 ffill [1]=1");
    CHECK(r && APPROX(f64_get(r, 2), 1.0),   "f64 ffill [2]=1 (preenchido)");
    CHECK(r && APPROX(f64_get(r, 3), 3.0),   "f64 ffill [3]=3");
    CHECK(r && APPROX(f64_get(r, 4), 3.0),   "f64 ffill [4]=3 (preenchido)");
    smaug_f64_free(r); smaug_f64_free(s);

    CHECK(smaug_f64_ffill(NULL) == NULL, "f64 ffill NULL input");
}

static void test_f64_bfill(void) {
    /* [null, 1, null, 3, null] → [1, 1, 3, 3, null] */
    double arr[] = {-9999.0, 1.0, -9999.0, 3.0, -9999.0};
    smaug_series_f64_t *s = f64_from(arr, 5);
    smaug_series_f64_t *r = smaug_f64_bfill(s);
    CHECK(r && APPROX(f64_get(r, 0), 1.0),   "f64 bfill [0]=1 (preenchido)");
    CHECK(r && APPROX(f64_get(r, 1), 1.0),   "f64 bfill [1]=1");
    CHECK(r && APPROX(f64_get(r, 2), 3.0),   "f64 bfill [2]=3 (preenchido)");
    CHECK(r && APPROX(f64_get(r, 3), 3.0),   "f64 bfill [3]=3");
    CHECK(r && f64_null(r, 4),               "f64 bfill [4]=null (sem valor seguinte)");
    smaug_f64_free(r); smaug_f64_free(s);

    CHECK(smaug_f64_bfill(NULL) == NULL, "f64 bfill NULL input");
}

static void test_i64_ffill(void) {
    int64_t arr[] = {INT64_MIN, 5, INT64_MIN, 7};
    smaug_series_i64_t *s = i64_from(arr, 4);
    smaug_series_i64_t *r = smaug_i64_ffill(s);
    CHECK(r && i64_null(r, 0),       "i64 ffill [0]=null");
    CHECK(r && i64_get(r, 1) == 5,   "i64 ffill [1]=5");
    CHECK(r && i64_get(r, 2) == 5,   "i64 ffill [2]=5 (preenchido)");
    CHECK(r && i64_get(r, 3) == 7,   "i64 ffill [3]=7");
    smaug_i64_free(r); smaug_i64_free(s);
    CHECK(smaug_i64_ffill(NULL) == NULL, "i64 ffill NULL input");
}

static void test_i64_bfill(void) {
    int64_t arr[] = {INT64_MIN, 5, INT64_MIN};
    smaug_series_i64_t *s = i64_from(arr, 3);
    smaug_series_i64_t *r = smaug_i64_bfill(s);
    CHECK(r && i64_get(r, 0) == 5,   "i64 bfill [0]=5 (preenchido)");
    CHECK(r && i64_get(r, 1) == 5,   "i64 bfill [1]=5");
    CHECK(r && i64_null(r, 2),       "i64 bfill [2]=null");
    smaug_i64_free(r); smaug_i64_free(s);
    CHECK(smaug_i64_bfill(NULL) == NULL, "i64 bfill NULL input");
}

/* ----- ffill/bfill em bool/str/dt (item 7.1: motor agnóstico a tipo) ----- */

static void test_bool_ffill_bfill(void) {
    /* "1NN0N" → ffill: 1,1,1,0,0 ; bfill: 1,0,0,0,NA */
    smaug_series_bool_t *s = bool_from("1NN0N");
    smaug_series_bool_t *rf = smaug_bool_ffill(s);
    CHECK(rf && bool_get(rf, 0) == 1, "bool ffill [0]=true");
    CHECK(rf && bool_get(rf, 1) == 1, "bool ffill [1]=true (preenchido)");
    CHECK(rf && bool_get(rf, 2) == 1, "bool ffill [2]=true (preenchido)");
    CHECK(rf && bool_get(rf, 3) == 0, "bool ffill [3]=false");
    CHECK(rf && bool_get(rf, 4) == 0, "bool ffill [4]=false (preenchido)");
    smaug_bool_free(rf);

    smaug_series_bool_t *rb = smaug_bool_bfill(s);
    CHECK(rb && bool_get(rb, 0) == 1, "bool bfill [0]=true");
    CHECK(rb && bool_get(rb, 1) == 0, "bool bfill [1]=false (preenchido)");
    CHECK(rb && bool_get(rb, 3) == 0, "bool bfill [3]=false");
    CHECK(rb && bool_null(rb, 4),     "bool bfill [4]=null (sem seguinte)");
    smaug_bool_free(rb);

    /* ffill com NA na borda inicial: "N1" → NA,true */
    smaug_series_bool_t *s2 = bool_from("N1");
    smaug_series_bool_t *r2 = smaug_bool_ffill(s2);
    CHECK(r2 && bool_null(r2, 0),     "bool ffill borda [0]=null (sem anterior)");
    CHECK(r2 && bool_get(r2, 1) == 1, "bool ffill borda [1]=true");
    smaug_bool_free(r2); smaug_bool_free(s2);

    /* toda nula */
    smaug_series_bool_t *s3 = bool_from("NNN");
    smaug_series_bool_t *r3 = smaug_bool_ffill(s3);
    CHECK(r3 && bool_null(r3, 0) && bool_null(r3, 2), "bool ffill all-null: tudo null");
    smaug_bool_free(r3); smaug_bool_free(s3);

    smaug_bool_free(s);
    CHECK(smaug_bool_ffill(NULL) == NULL, "bool ffill NULL input");
    CHECK(smaug_bool_bfill(NULL) == NULL, "bool bfill NULL input");
}

static void test_dt_ffill_bfill(void) {
    /* [NA, 100, NA, 300, NA] (epoch ms) */
    int64_t arr[] = {INT64_MIN, 100, INT64_MIN, 300, INT64_MIN};
    smaug_series_dt_t *s = dt_from(arr, 5);

    smaug_series_dt_t *rf = smaug_dt_ffill(s);
    CHECK(rf && dt_null(rf, 0),          "dt ffill [0]=null (sem anterior)");
    CHECK(rf && dt_get(rf, 1) == 100,    "dt ffill [1]=100");
    CHECK(rf && dt_get(rf, 2) == 100,    "dt ffill [2]=100 (preenchido)");
    CHECK(rf && dt_get(rf, 3) == 300,    "dt ffill [3]=300");
    CHECK(rf && dt_get(rf, 4) == 300,    "dt ffill [4]=300 (preenchido)");
    smaug_dt_free(rf);

    smaug_series_dt_t *rb = smaug_dt_bfill(s);
    CHECK(rb && dt_get(rb, 0) == 100,    "dt bfill [0]=100 (preenchido)");
    CHECK(rb && dt_get(rb, 2) == 300,    "dt bfill [2]=300 (preenchido)");
    CHECK(rb && dt_null(rb, 4),          "dt bfill [4]=null (sem seguinte)");
    smaug_dt_free(rb);

    smaug_dt_free(s);
    CHECK(smaug_dt_ffill(NULL) == NULL, "dt ffill NULL input");
    CHECK(smaug_dt_bfill(NULL) == NULL, "dt bfill NULL input");
}

static void test_str_ffill_bfill(void) {
    /* ["a", NA, "", NA, "héllo"] — "" é valor válido distinto de NA;
       "héllo" exercita multibyte. */
    smaug_series_str_t *s = smaug_str_create(5);
    smaug_str_set(s, 0, "a", 1);
    /* idx 1 fica null (create já zera) */
    smaug_str_set(s, 2, "", 0);
    /* idx 3 null */
    smaug_str_set(s, 4, "h\xc3\xa9llo", 6);

    smaug_series_str_t *rf = smaug_str_ffill(s);
    CHECK(rf && str_eq_at(rf, 0, "a"),       "str ffill [0]=a");
    CHECK(rf && str_eq_at(rf, 1, "a"),       "str ffill [1]=a (preenchido)");
    CHECK(rf && str_eq_at(rf, 2, ""),        "str ffill [2]= (vazia, válida)");
    CHECK(rf && str_eq_at(rf, 3, ""),        "str ffill [3]= (preenchido c/ vazia)");
    CHECK(rf && str_eq_at(rf, 4, "h\xc3\xa9llo"), "str ffill [4]=héllo");
    smaug_str_free(rf);

    smaug_series_str_t *rb = smaug_str_bfill(s);
    CHECK(rb && str_eq_at(rb, 0, "a"),       "str bfill [0]=a");
    CHECK(rb && str_eq_at(rb, 1, ""),        "str bfill [1]= (preenchido c/ vazia seguinte)");
    CHECK(rb && str_eq_at(rb, 3, "h\xc3\xa9llo"), "str bfill [3]=héllo (preenchido)");
    CHECK(rb && str_eq_at(rb, 4, "h\xc3\xa9llo"), "str bfill [4]=héllo");
    smaug_str_free(rb);

    /* borda: [NA, "x", NA] */
    smaug_series_str_t *s2 = smaug_str_create(3);
    smaug_str_set(s2, 1, "x", 1);
    smaug_series_str_t *r2f = smaug_str_ffill(s2);
    size_t len; int isn;
    str_get(r2f, 0, &len, &isn);
    CHECK(isn,                       "str ffill borda [0]=null (sem anterior)");
    CHECK(str_eq_at(r2f, 2, "x"),    "str ffill borda [2]=x (preenchido)");
    smaug_str_free(r2f);
    smaug_series_str_t *r2b = smaug_str_bfill(s2);
    str_get(r2b, 2, &len, &isn);
    CHECK(isn,                       "str bfill borda [2]=null (sem seguinte)");
    CHECK(str_eq_at(r2b, 0, "x"),    "str bfill borda [0]=x (preenchido)");
    smaug_str_free(r2b); smaug_str_free(s2);

    /* toda nula */
    smaug_series_str_t *s3 = smaug_str_create(3);
    smaug_series_str_t *r3 = smaug_str_ffill(s3);
    str_get(r3, 0, &len, &isn); CHECK(isn, "str ffill all-null [0]=null");
    str_get(r3, 2, &len, &isn); CHECK(isn, "str ffill all-null [2]=null");
    smaug_str_free(r3); smaug_str_free(s3);

    smaug_str_free(s);
    CHECK(smaug_str_ffill(NULL) == NULL, "str ffill NULL input");
    CHECK(smaug_str_bfill(NULL) == NULL, "str bfill NULL input");
}

/* =====================================================================
   argmin / argmax
   ===================================================================== */

static void test_f64_argmin_argmax(void) {
    double arr[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *s = f64_from(arr, 5);
    CHECK(smaug_f64_argmin(s) == 1, "f64 argmin = 1 (0-based)");
    CHECK(smaug_f64_argmax(s) == 4, "f64 argmax = 4 (0-based)");
    smaug_f64_free(s);

    /* com null: ignora null */
    double arr2[] = {-9999.0, 1.0, -9999.0, 5.0};
    smaug_series_f64_t *s2 = f64_from(arr2, 4);
    CHECK(smaug_f64_argmin(s2) == 1, "f64 argmin null = 1");
    CHECK(smaug_f64_argmax(s2) == 3, "f64 argmax null = 3");
    smaug_f64_free(s2);

    /* toda null → SIZE_MAX */
    double arr3[] = {-9999.0, -9999.0};
    smaug_series_f64_t *s3 = f64_from(arr3, 2);
    CHECK(smaug_f64_argmin(s3) == (size_t)-1, "f64 argmin toda-null = SIZE_MAX");
    CHECK(smaug_f64_argmax(s3) == (size_t)-1, "f64 argmax toda-null = SIZE_MAX");
    smaug_f64_free(s3);

    /* vazia */
    smaug_series_f64_t *se = smaug_f64_create(0);
    CHECK(smaug_f64_argmin(se) == (size_t)-1, "f64 argmin vazia = SIZE_MAX");
    CHECK(smaug_f64_argmax(se) == (size_t)-1, "f64 argmax vazia = SIZE_MAX");
    smaug_f64_free(se);

    CHECK(smaug_f64_argmin(NULL) == (size_t)-1, "f64 argmin NULL = SIZE_MAX");
    CHECK(smaug_f64_argmax(NULL) == (size_t)-1, "f64 argmax NULL = SIZE_MAX");
}

static void test_i64_argmin_argmax(void) {
    int64_t arr[] = {3, 1, 4, 1, 5};
    smaug_series_i64_t *s = i64_from(arr, 5);
    CHECK(smaug_i64_argmin(s) == 1, "i64 argmin = 1");
    CHECK(smaug_i64_argmax(s) == 4, "i64 argmax = 4");
    smaug_i64_free(s);

    int64_t arr2[] = {INT64_MIN, 10, INT64_MIN, 2};
    smaug_series_i64_t *s2 = i64_from(arr2, 4);
    CHECK(smaug_i64_argmin(s2) == 3, "i64 argmin null = 3");
    CHECK(smaug_i64_argmax(s2) == 1, "i64 argmax null = 1");
    smaug_i64_free(s2);

    CHECK(smaug_i64_argmin(NULL) == (size_t)-1, "i64 argmin NULL = SIZE_MAX");
    CHECK(smaug_i64_argmax(NULL) == (size_t)-1, "i64 argmax NULL = SIZE_MAX");
}

/* argmin/argmax em dt/str/bool (item 7.2a: ordenáveis no Anel 0) */
static void test_typed_argminmax(void) {
    /* dt: cronológico. [300,100,600,100] → argmin=1, argmax=2 */
    int64_t da[] = {300, 100, 600, 100};
    smaug_series_dt_t *d = dt_from(da, 4);
    CHECK(smaug_dt_argmin(d) == 1, "dt argmin = 1");
    CHECK(smaug_dt_argmax(d) == 2, "dt argmax = 2");
    smaug_dt_free(d);
    /* dt com NA: ignora */
    int64_t da2[] = {INT64_MIN, 50, INT64_MIN, 10};
    smaug_series_dt_t *d2 = dt_from(da2, 4);
    CHECK(smaug_dt_argmin(d2) == 3, "dt argmin null = 3");
    CHECK(smaug_dt_argmax(d2) == 1, "dt argmax null = 1");
    smaug_dt_free(d2);
    /* dt toda-NA / vazia / NULL */
    int64_t da3[] = {INT64_MIN, INT64_MIN};
    smaug_series_dt_t *d3 = dt_from(da3, 2);
    CHECK(smaug_dt_argmin(d3) == (size_t)-1, "dt argmin toda-NA = SIZE_MAX");
    smaug_dt_free(d3);
    smaug_series_dt_t *de = smaug_dt_create(0);
    CHECK(smaug_dt_argmin(de) == (size_t)-1, "dt argmin vazia = SIZE_MAX");
    smaug_dt_free(de);
    CHECK(smaug_dt_argmin(NULL) == (size_t)-1, "dt argmin NULL = SIZE_MAX");
    CHECK(smaug_dt_argmax(NULL) == (size_t)-1, "dt argmax NULL = SIZE_MAX");

    /* str: lexicográfico por bytes. ["banana","abacaxi","caju"] →
       argmin=1 (abacaxi), argmax=2 (caju) */
    smaug_series_str_t *s = smaug_str_create(3);
    smaug_str_set(s, 0, "banana", 6);
    smaug_str_set(s, 1, "abacaxi", 7);
    smaug_str_set(s, 2, "caju", 4);
    CHECK(smaug_str_argmin(s) == 1, "str argmin = 1 (abacaxi)");
    CHECK(smaug_str_argmax(s) == 2, "str argmax = 2 (caju)");
    smaug_str_free(s);
    /* str com vazia (menor de todas) e NA */
    smaug_series_str_t *s2 = smaug_str_create(4);
    smaug_str_set(s2, 0, "z", 1);
    /* idx 1 = NA */
    smaug_str_set(s2, 2, "", 0);
    smaug_str_set(s2, 3, "m", 1);
    CHECK(smaug_str_argmin(s2) == 2, "str argmin = 2 (vazia é a menor)");
    CHECK(smaug_str_argmax(s2) == 0, "str argmax = 0 (z)");
    smaug_str_free(s2);
    /* str prefixo: "ab" < "abc" (mais curta antes) */
    smaug_series_str_t *s3 = smaug_str_create(2);
    smaug_str_set(s3, 0, "abc", 3);
    smaug_str_set(s3, 1, "ab", 2);
    CHECK(smaug_str_argmin(s3) == 1, "str argmin prefixo = 1 (ab)");
    smaug_str_free(s3);
    /* str toda-NA / vazia / NULL */
    smaug_series_str_t *s4 = smaug_str_create(2);
    CHECK(smaug_str_argmin(s4) == (size_t)-1, "str argmin toda-NA = SIZE_MAX");
    smaug_str_free(s4);
    smaug_series_str_t *se2 = smaug_str_create(0);
    CHECK(smaug_str_argmin(se2) == (size_t)-1, "str argmin vazia = SIZE_MAX");
    smaug_str_free(se2);
    CHECK(smaug_str_argmin(NULL) == (size_t)-1, "str argmin NULL = SIZE_MAX");
    CHECK(smaug_str_argmax(NULL) == (size_t)-1, "str argmax NULL = SIZE_MAX");

    /* bool: false<true. "101" → argmin=1 (false), argmax=0 (true) */
    smaug_series_bool_t *b = bool_from("101");
    CHECK(smaug_bool_argmin(b) == 1, "bool argmin = 1 (false)");
    CHECK(smaug_bool_argmax(b) == 0, "bool argmax = 0 (true)");
    smaug_bool_free(b);
    /* bool com NA: "N0N1" → argmin=1 (false), argmax=3 (true) */
    smaug_series_bool_t *b2 = bool_from("N0N1");
    CHECK(smaug_bool_argmin(b2) == 1, "bool argmin null = 1");
    CHECK(smaug_bool_argmax(b2) == 3, "bool argmax null = 3");
    smaug_bool_free(b2);
    /* bool toda-NA / NULL */
    smaug_series_bool_t *b3 = bool_from("NN");
    CHECK(smaug_bool_argmin(b3) == (size_t)-1, "bool argmin toda-NA = SIZE_MAX");
    smaug_bool_free(b3);
    CHECK(smaug_bool_argmin(NULL) == (size_t)-1, "bool argmin NULL = SIZE_MAX");
    CHECK(smaug_bool_argmax(NULL) == (size_t)-1, "bool argmax NULL = SIZE_MAX");
}

/* min/max em dt/str/bool (item 7.2b: valor do menor/maior, ordenáveis) */
static void test_typed_minmax(void) {
    /* dt: cronológico. [300,100,600] → min=100, max=600 */
    int64_t da[] = {300, 100, 600};
    smaug_series_dt_t *d = dt_from(da, 3);
    CHECK(smaug_dt_min(d, true) == 100, "dt min = 100");
    CHECK(smaug_dt_max(d, true) == 600, "dt max = 600");
    smaug_dt_free(d);
    /* dt com NA: ignore_na pula; senão sentinela */
    int64_t da2[] = {300, INT64_MIN, 100};
    smaug_series_dt_t *d2 = dt_from(da2, 3);
    CHECK(smaug_dt_min(d2, true)  == 100,        "dt min ignore_na");
    CHECK(smaug_dt_max(d2, true)  == 300,        "dt max ignore_na");
    CHECK(smaug_dt_min(d2, false) == INT64_MIN,  "dt min(false) com NA = sentinela");
    smaug_dt_free(d2);
    /* dt vazia / toda-NA / NULL */
    int64_t da3[] = {INT64_MIN, INT64_MIN};
    smaug_series_dt_t *d3 = dt_from(da3, 2);
    CHECK(smaug_dt_min(d3, true) == INT64_MIN, "dt min toda-NA = sentinela");
    smaug_dt_free(d3);
    CHECK(smaug_dt_min(NULL, true) == INT64_MIN, "dt min NULL = sentinela");

    /* str: lexicográfico. ["banana","abacaxi","caju"] → min=abacaxi, max=caju */
    smaug_series_str_t *s = smaug_str_create(3);
    smaug_str_set(s, 0, "banana", 6);
    smaug_str_set(s, 1, "abacaxi", 7);
    smaug_str_set(s, 2, "caju", 4);
    size_t len; const char *p;
    p = smaug_str_min(s, true, &len);
    CHECK(p && len == 7 && memcmp(p, "abacaxi", 7) == 0, "str min = abacaxi");
    p = smaug_str_max(s, true, &len);
    CHECK(p && len == 4 && memcmp(p, "caju", 4) == 0,    "str max = caju");
    smaug_str_free(s);
    /* str com "" válida: ["z","","m"] → min="" (len 0, ptr não-NULL) */
    smaug_series_str_t *sv = smaug_str_create(3);
    smaug_str_set(sv, 0, "z", 1);
    smaug_str_set(sv, 1, "", 0);
    smaug_str_set(sv, 2, "m", 1);
    p = smaug_str_min(sv, true, &len);
    CHECK(p != NULL && len == 0, "str min = '' (vazia válida, ptr não-NULL)");
    smaug_str_free(sv);
    /* str com NA: ignore_na pula; senão NULL */
    smaug_series_str_t *sn = smaug_str_create(3);
    smaug_str_set(sn, 0, "a", 1);
    smaug_str_set(sn, 2, "c", 1);  /* idx 1 = NA */
    p = smaug_str_min(sn, true, &len);
    CHECK(p && len == 1 && p[0] == 'a',           "str min ignore_na = a");
    p = smaug_str_min(sn, false, &len);
    CHECK(p == NULL,                              "str min(false) com NA = NULL");
    smaug_str_free(sn);
    /* str toda-NA / vazia / NULL */
    smaug_series_str_t *se = smaug_str_create(2);  /* tudo NA */
    CHECK(smaug_str_min(se, true, &len) == NULL,  "str min toda-NA = NULL");
    smaug_str_free(se);
    CHECK(smaug_str_min(NULL, true, &len) == NULL, "str min NULL = NULL");

    /* bool: false<true. "101" → min=false(0), max=true(1) */
    smaug_status_t st;
    smaug_series_bool_t *b = bool_from("101");
    CHECK(smaug_bool_min(b, true, &st) == 0 && st == SMG_OK, "bool min = false");
    CHECK(smaug_bool_max(b, true, &st) == 1 && st == SMG_OK, "bool max = true");
    smaug_bool_free(b);
    /* bool todos-true: "11" → min=true */
    smaug_series_bool_t *bt = bool_from("11");
    CHECK(smaug_bool_min(bt, true, &st) == 1 && st == SMG_OK, "bool min todos-true = true");
    smaug_bool_free(bt);
    /* bool com NA: ignore pula; senão NULL */
    smaug_series_bool_t *bn = bool_from("1N0");
    CHECK(smaug_bool_min(bn, true, &st) == 0 && st == SMG_OK,    "bool min ignore_na");
    smaug_bool_min(bn, false, &st);
    CHECK(st == SMG_NULL_VALUE,                                  "bool min(false) com NA = status NULL");
    smaug_bool_free(bn);
    /* bool toda-NA / NULL */
    smaug_series_bool_t *be = bool_from("NN");
    smaug_bool_min(be, true, &st);
    CHECK(st == SMG_NULL_VALUE, "bool min toda-NA = status NULL");
    smaug_bool_free(be);
    smaug_bool_min(NULL, true, &st);
    CHECK(st == SMG_NULL_VALUE, "bool min NULL = status NULL");
    /* status NULL-safe (caller passa NULL) */
    smaug_series_bool_t *bok = bool_from("10");
    CHECK(smaug_bool_min(bok, true, NULL) == 0, "bool min status=NULL safe");
    smaug_bool_free(bok);
}

/* =====================================================================
   sorted_nonnull
   ===================================================================== */

static void test_f64_sorted_nonnull(void) {
    /* [3, 1, 4, 1, 5] → [1, 1, 3, 4, 5] */
    double arr[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *s = f64_from(arr, 5);
    size_t n;
    double *out = smaug_f64_sorted_nonnull(s, &n);
    CHECK(n == 5,              "f64 sorted_nonnull: n=5");
    CHECK(out && APPROX(out[0], 1.0), "f64 sorted_nonnull: [0]=1");
    CHECK(out && APPROX(out[4], 5.0), "f64 sorted_nonnull: [4]=5");
    free(out); smaug_f64_free(s);

    /* com null: [3, null, 1] → [1, 3], n=2 */
    double arr2[] = {3.0, -9999.0, 1.0};
    smaug_series_f64_t *s2 = f64_from(arr2, 3);
    size_t n2;
    double *out2 = smaug_f64_sorted_nonnull(s2, &n2);
    CHECK(n2 == 2,                   "f64 sorted_nonnull null: n=2");
    CHECK(out2 && APPROX(out2[0], 1.0), "f64 sorted_nonnull null: [0]=1");
    CHECK(out2 && APPROX(out2[1], 3.0), "f64 sorted_nonnull null: [1]=3");
    free(out2); smaug_f64_free(s2);

    /* toda null: n=0, retorna NULL */
    double arr3[] = {-9999.0, -9999.0};
    smaug_series_f64_t *s3 = f64_from(arr3, 2);
    size_t n3;
    double *out3 = smaug_f64_sorted_nonnull(s3, &n3);
    CHECK(n3 == 0 && out3 == NULL, "f64 sorted_nonnull toda-null: n=0");
    smaug_f64_free(s3);

    /* NULL input */
    size_t nz; CHECK(smaug_f64_sorted_nonnull(NULL, &nz) == NULL, "f64 sorted_nonnull NULL");
}

static void test_i64_sorted_nonnull(void) {
    int64_t arr[] = {5, 1, 3};
    smaug_series_i64_t *s = i64_from(arr, 3);
    size_t n;
    int64_t *out = smaug_i64_sorted_nonnull(s, &n);
    CHECK(n == 3,            "i64 sorted_nonnull: n=3");
    CHECK(out && out[0] == 1, "i64 sorted_nonnull: [0]=1");
    CHECK(out && out[2] == 5, "i64 sorted_nonnull: [2]=5");
    free(out); smaug_i64_free(s);

    size_t nz; CHECK(smaug_i64_sorted_nonnull(NULL, &nz) == NULL, "i64 sorted_nonnull NULL");
}

/* =====================================================================
   rank
   ===================================================================== */

static void test_f64_rank(void) {
    /* [3, 1, 4, 1, 5] → average: [3, 1.5, 4, 1.5, 5] */
    double arr[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *s = f64_from(arr, 5);

    double *r_avg = smaug_f64_rank(s, 0);
    CHECK(r_avg && APPROX(r_avg[0], 3.0),   "f64 rank avg [0]=3");
    CHECK(r_avg && APPROX(r_avg[1], 1.5),   "f64 rank avg [1]=1.5");
    CHECK(r_avg && APPROX(r_avg[2], 4.0),   "f64 rank avg [2]=4");
    CHECK(r_avg && APPROX(r_avg[3], 1.5),   "f64 rank avg [3]=1.5");
    CHECK(r_avg && APPROX(r_avg[4], 5.0),   "f64 rank avg [4]=5");
    free(r_avg);

    /* method=min: empates recebem menor rank */
    double *r_min = smaug_f64_rank(s, 1);
    CHECK(r_min && APPROX(r_min[1], 1.0),   "f64 rank min [1]=1");
    CHECK(r_min && APPROX(r_min[3], 1.0),   "f64 rank min [3]=1");
    free(r_min);

    /* method=max */
    double *r_max = smaug_f64_rank(s, 2);
    CHECK(r_max && APPROX(r_max[1], 2.0),   "f64 rank max [1]=2");
    CHECK(r_max && APPROX(r_max[3], 2.0),   "f64 rank max [3]=2");
    free(r_max);

    /* method=first: posição de aparição */
    double *r_first = smaug_f64_rank(s, 3);
    CHECK(r_first && APPROX(r_first[1], 1.0), "f64 rank first [1]=1 (aparece antes)");
    CHECK(r_first && APPROX(r_first[3], 2.0), "f64 rank first [3]=2 (aparece depois)");
    free(r_first);

    smaug_f64_free(s);

    /* com null: [3, null, 1] → [2, NAN, 1] */
    double arr2[] = {3.0, -9999.0, 1.0};
    smaug_series_f64_t *s2 = f64_from(arr2, 3);
    double *r2 = smaug_f64_rank(s2, 0);
    CHECK(r2 && APPROX(r2[0], 2.0),   "f64 rank null [0]=2");
    CHECK(r2 && r2[1] != r2[1],       "f64 rank null [1]=NAN");
    CHECK(r2 && APPROX(r2[2], 1.0),   "f64 rank null [2]=1");
    free(r2); smaug_f64_free(s2);

    /* série vazia: retorna array vazio (não NULL) */
    smaug_series_f64_t *se = smaug_f64_create(0);
    double *re = smaug_f64_rank(se, 0);
    CHECK(re != NULL, "f64 rank vazia: nao NULL");
    free(re); smaug_f64_free(se);

    CHECK(smaug_f64_rank(NULL, 0) == NULL, "f64 rank NULL input");
}

static void test_i64_rank(void) {
    int64_t arr[] = {3, 1, 4, 1, 5};
    smaug_series_i64_t *s = i64_from(arr, 5);
    double *r = smaug_i64_rank(s, 0);  /* average */
    CHECK(r && APPROX(r[0], 3.0),  "i64 rank [0]=3");
    CHECK(r && APPROX(r[1], 1.5),  "i64 rank [1]=1.5");
    CHECK(r && APPROX(r[4], 5.0),  "i64 rank [4]=5");
    free(r); smaug_i64_free(s);

    CHECK(smaug_i64_rank(NULL, 0) == NULL, "i64 rank NULL input");

    /* precisão acima de 2^53: três int64 distintos e consecutivos que
       colapsariam para o mesmo double. Com ordenação int64 direta, devem
       ranquear como distintos (1,2,3), não como empate. */
    int64_t big[] = { 9007199254740994LL,   /* 2^53 + 2 */
                      9007199254740992LL,   /* 2^53     */
                      9007199254740993LL };  /* 2^53 + 1 */
    smaug_series_i64_t *sb = i64_from(big, 3);
    double *rb = smaug_i64_rank(sb, 0);  /* average; sem empates → ranks inteiros */
    CHECK(rb && APPROX(rb[0], 3.0), "i64 rank >2^53: maior valor → rank 3");
    CHECK(rb && APPROX(rb[1], 1.0), "i64 rank >2^53: menor valor → rank 1");
    CHECK(rb && APPROX(rb[2], 2.0), "i64 rank >2^53: valor médio → rank 2");
    free(rb); smaug_i64_free(sb);
}

/* =====================================================================
   multi_argsort
   ===================================================================== */

/* Helper: cria smaug_series_str_t com strings simples */
static smaug_series_str_t *str_from(const char **strs, size_t n) {
    smaug_series_str_t *s = smaug_str_create(n);
    if (!s) return NULL;
    for (size_t i = 0; i < n; i++) {
        if (strs[i] == NULL) smaug_str_set_null(s, i);
        else smaug_str_set(s, i, strs[i], strlen(strs[i]));
    }
    return s;
}

static void test_multi_argsort_single_f64(void) {
    /* Coluna única f64: [3, 1, 2] → perm [1, 2, 0] */
    double arr[] = {3.0, 1.0, 2.0};
    smaug_series_f64_t *col = f64_from(arr, 3);
    smaug_sort_col_t cols[1] = {{ SMAUG_COL_F64, .f64 = col }};
    size_t *perm = smaug_multi_argsort(cols, 1, 3);
    CHECK(perm && perm[0] == 1, "multi_argsort f64 single: perm[0]=1");
    CHECK(perm && perm[1] == 2, "multi_argsort f64 single: perm[1]=2");
    CHECK(perm && perm[2] == 0, "multi_argsort f64 single: perm[2]=0");
    free(perm); smaug_f64_free(col);
}

static void test_multi_argsort_single_i64(void) {
    int64_t arr[] = {10, 30, 20};
    smaug_series_i64_t *col = i64_from(arr, 3);
    smaug_sort_col_t cols[1] = {{ SMAUG_COL_I64, .i64 = col }};
    size_t *perm = smaug_multi_argsort(cols, 1, 3);
    CHECK(perm && perm[0] == 0, "multi_argsort i64 single: perm[0]=0");
    CHECK(perm && perm[1] == 2, "multi_argsort i64 single: perm[1]=2");
    CHECK(perm && perm[2] == 1, "multi_argsort i64 single: perm[2]=1");
    free(perm); smaug_i64_free(col);
}

static void test_multi_argsort_str(void) {
    /* ["banana", "abacate", "caju"] → perm [1, 0, 2] */
    const char *strs[] = {"banana", "abacate", "caju"};
    smaug_series_str_t *col = str_from(strs, 3);
    smaug_sort_col_t cols[1] = {{ SMAUG_COL_STR, .str = col }};
    size_t *perm = smaug_multi_argsort(cols, 1, 3);
    CHECK(perm && perm[0] == 1, "multi_argsort str: perm[0]=1 (abacate)");
    CHECK(perm && perm[1] == 0, "multi_argsort str: perm[1]=0 (banana)");
    CHECK(perm && perm[2] == 2, "multi_argsort str: perm[2]=2 (caju)");
    free(perm); smaug_str_free(col);
}

static void test_multi_argsort_bool(void) {
    /* [true, false, true] → perm [1, 0, 2] (false < true) */
    uint8_t arr[] = {1, 0, 1};
    smaug_series_bool_t *col = smaug_bool_create(3);
    for (int i = 0; i < 3; i++) { smaug_bool_set(col, i, arr[i]); }
    smaug_sort_col_t cols[1] = {{ SMAUG_COL_BOOL, .boo = col }};
    size_t *perm = smaug_multi_argsort(cols, 1, 3);
    CHECK(perm && perm[0] == 1, "multi_argsort bool: perm[0]=1 (false primeiro)");
    free(perm); smaug_bool_free(col);
}

static void test_multi_argsort_composite(void) {
    /* chave composta: col1=[SP, SP, RJ], col2=[2, 1, 3]
       ordem: RJ/3=idx2, SP/1=idx1, SP/2=idx0
       perm = [2, 1, 0] */
    const char *cities[] = {"SP", "SP", "RJ"};
    int64_t years[] = {2, 1, 3};
    smaug_series_str_t *col_city = str_from(cities, 3);
    smaug_series_i64_t *col_year = i64_from(years, 3);

    smaug_sort_col_t cols[2] = {
        { SMAUG_COL_STR, .str = col_city },
        { SMAUG_COL_I64, .i64 = col_year }
    };
    size_t *perm = smaug_multi_argsort(cols, 2, 3);
    CHECK(perm && perm[0] == 2, "multi_argsort composite: perm[0]=2 (RJ/3)");
    CHECK(perm && perm[1] == 1, "multi_argsort composite: perm[1]=1 (SP/1)");
    CHECK(perm && perm[2] == 0, "multi_argsort composite: perm[2]=0 (SP/2)");
    free(perm);
    smaug_str_free(col_city); smaug_i64_free(col_year);
}

static void test_multi_argsort_stable(void) {
    /* Estabilidade: empates preservam ordem original.
       col1=[1,1,1] col2=[2,2,2]: perm deve ser [0,1,2] */
    double arr[] = {1.0, 1.0, 1.0};
    smaug_series_f64_t *col = f64_from(arr, 3);
    smaug_sort_col_t cols[1] = {{ SMAUG_COL_F64, .f64 = col }};
    size_t *perm = smaug_multi_argsort(cols, 1, 3);
    CHECK(perm && perm[0] == 0, "multi_argsort stable: empates preservados [0]");
    CHECK(perm && perm[1] == 1, "multi_argsort stable: empates preservados [1]");
    CHECK(perm && perm[2] == 2, "multi_argsort stable: empates preservados [2]");
    free(perm); smaug_f64_free(col);
}

static void test_multi_argsort_edge(void) {
    /* NULL/zero */
    CHECK(smaug_multi_argsort(NULL, 1, 3) == NULL, "multi_argsort NULL cols");
    double arr[] = {1.0};
    smaug_series_f64_t *col = f64_from(arr, 1);
    smaug_sort_col_t cols[1] = {{ SMAUG_COL_F64, .f64 = col }};
    CHECK(smaug_multi_argsort(cols, 0, 1) == NULL, "multi_argsort ncols=0");
    CHECK(smaug_multi_argsort(cols, 1, 0) == NULL, "multi_argsort nrows=0");
    smaug_f64_free(col);
}

/* =====================================================================
   rolling ops f64
   ===================================================================== */

static void test_f64_rolling_sum(void) {
    /* [1,2,3,4,5] window=3 → [NA,NA,6,9,12] */
    double arr[] = {1.0, 2.0, 3.0, 4.0, 5.0};
    smaug_series_f64_t *s = f64_from(arr, 5);
    smaug_series_f64_t *r = smaug_f64_rolling_sum(s, 3);
    CHECK(r && f64_null(r, 0), "f64 rolling_sum [0]=NA");
    CHECK(r && f64_null(r, 1), "f64 rolling_sum [1]=NA");
    CHECK(r && APPROX(f64_get(r, 2), 6.0),  "f64 rolling_sum [2]=6");
    CHECK(r && APPROX(f64_get(r, 3), 9.0),  "f64 rolling_sum [3]=9");
    CHECK(r && APPROX(f64_get(r, 4), 12.0), "f64 rolling_sum [4]=12");
    smaug_f64_free(r); smaug_f64_free(s);

    /* com null: [1, null, 3, 4] window=2 → [NA, 1, 3, 7] */
    double arr2[] = {1.0, -9999.0, 3.0, 4.0};
    smaug_series_f64_t *s2 = f64_from(arr2, 4);
    smaug_series_f64_t *r2 = smaug_f64_rolling_sum(s2, 2);
    CHECK(r2 && f64_null(r2, 0),              "f64 rolling_sum null [0]=NA");
    CHECK(r2 && APPROX(f64_get(r2, 1), 1.0), "f64 rolling_sum null [1]=1 (null ignorado, soma de [1,null]=1)");
    CHECK(r2 && APPROX(f64_get(r2, 2), 3.0), "f64 rolling_sum null [2]=3 (null+3=3)");
    CHECK(r2 && APPROX(f64_get(r2, 3), 7.0), "f64 rolling_sum null [3]=7");
    smaug_f64_free(r2); smaug_f64_free(s2);

    CHECK(smaug_f64_rolling_sum(NULL, 3) == NULL, "f64 rolling_sum NULL");
}

static void test_f64_rolling_mean(void) {
    double arr[] = {1.0, 2.0, 3.0, 4.0, 5.0};
    smaug_series_f64_t *s = f64_from(arr, 5);
    smaug_series_f64_t *r = smaug_f64_rolling_mean(s, 3);
    CHECK(r && f64_null(r, 0), "f64 rolling_mean [0]=NA");
    CHECK(r && APPROX(f64_get(r, 2), 2.0), "f64 rolling_mean [2]=2");
    CHECK(r && APPROX(f64_get(r, 4), 4.0), "f64 rolling_mean [4]=4");
    smaug_f64_free(r); smaug_f64_free(s);
    CHECK(smaug_f64_rolling_mean(NULL, 3) == NULL, "f64 rolling_mean NULL");
}

static void test_f64_rolling_min(void) {
    /* [3,1,4,1,5] window=3 → [NA,NA,1,1,1] */
    double arr[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *s = f64_from(arr, 5);
    smaug_series_f64_t *r = smaug_f64_rolling_min(s, 3);
    CHECK(r && f64_null(r, 0), "f64 rolling_min [0]=NA");
    CHECK(r && APPROX(f64_get(r, 2), 1.0), "f64 rolling_min [2]=1");
    CHECK(r && APPROX(f64_get(r, 3), 1.0), "f64 rolling_min [3]=1");
    CHECK(r && APPROX(f64_get(r, 4), 1.0), "f64 rolling_min [4]=1");
    smaug_f64_free(r); smaug_f64_free(s);
    CHECK(smaug_f64_rolling_min(NULL, 3) == NULL, "f64 rolling_min NULL");
}

static void test_f64_rolling_max(void) {
    double arr[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *s = f64_from(arr, 5);
    smaug_series_f64_t *r = smaug_f64_rolling_max(s, 3);
    CHECK(r && f64_null(r, 0), "f64 rolling_max [0]=NA");
    CHECK(r && APPROX(f64_get(r, 2), 4.0), "f64 rolling_max [2]=4");
    CHECK(r && APPROX(f64_get(r, 3), 4.0), "f64 rolling_max [3]=4");
    CHECK(r && APPROX(f64_get(r, 4), 5.0), "f64 rolling_max [4]=5");
    smaug_f64_free(r); smaug_f64_free(s);
    CHECK(smaug_f64_rolling_max(NULL, 3) == NULL, "f64 rolling_max NULL");
}

/* =====================================================================
   rolling ops i64
   ===================================================================== */

static void test_i64_rolling_sum(void) {
    int64_t arr[] = {1, 2, 3, 4, 5};
    smaug_series_i64_t *s = i64_from(arr, 5);
    smaug_series_i64_t *r = smaug_i64_rolling_sum(s, 3);
    CHECK(r && i64_null(r, 0), "i64 rolling_sum [0]=NA");
    CHECK(r && i64_get(r, 2) == 6,  "i64 rolling_sum [2]=6");
    CHECK(r && i64_get(r, 4) == 12, "i64 rolling_sum [4]=12");
    smaug_i64_free(r); smaug_i64_free(s);
    CHECK(smaug_i64_rolling_sum(NULL, 3) == NULL, "i64 rolling_sum NULL");
}

static void test_i64_rolling_mean(void) {
    int64_t arr[] = {1, 2, 3, 4, 5};
    smaug_series_i64_t *s = i64_from(arr, 5);
    smaug_series_f64_t *r = smaug_i64_rolling_mean(s, 3);
    CHECK(r && f64_null(r, 0), "i64 rolling_mean [0]=NA");
    CHECK(r && APPROX(f64_get(r, 2), 2.0), "i64 rolling_mean [2]=2.0");
    CHECK(r && APPROX(f64_get(r, 4), 4.0), "i64 rolling_mean [4]=4.0");
    smaug_f64_free(r); smaug_i64_free(s);
    CHECK(smaug_i64_rolling_mean(NULL, 3) == NULL, "i64 rolling_mean NULL");
}

static void test_i64_rolling_min_max(void) {
    int64_t arr[] = {3, 1, 4, 1, 5};
    smaug_series_i64_t *s = i64_from(arr, 5);
    smaug_series_i64_t *rmin = smaug_i64_rolling_min(s, 3);
    CHECK(rmin && i64_null(rmin, 0),       "i64 rolling_min [0]=NA");
    CHECK(rmin && i64_get(rmin, 2) == 1,   "i64 rolling_min [2]=1");
    CHECK(rmin && i64_get(rmin, 4) == 1,   "i64 rolling_min [4]=1");
    smaug_i64_free(rmin);

    smaug_series_i64_t *rmax = smaug_i64_rolling_max(s, 3);
    CHECK(rmax && i64_null(rmax, 0),       "i64 rolling_max [0]=NA");
    CHECK(rmax && i64_get(rmax, 2) == 4,   "i64 rolling_max [2]=4");
    CHECK(rmax && i64_get(rmax, 4) == 5,   "i64 rolling_max [4]=5");
    smaug_i64_free(rmax);

    smaug_i64_free(s);
}

/* =====================================================================
   Testes de cobertura — lacunas identificadas em 2026-06-21
   ===================================================================== */

static void test_multi_argsort_dt(void) {
    /* SMAUG_COL_DT nunca exercitado em cmp_col_at (linha 32 branch 4) */
    smaug_series_dt_t *s = smaug_dt_create_from_array(
        (int64_t[]){3000000LL, 1000000LL, 2000000LL}, 3);
    smaug_sort_col_t col = { .kind = SMAUG_COL_DT, .dt = s };
    size_t *idx = smaug_multi_argsort(&col, 1, 3);
    CHECK(idx != NULL, "multi_argsort DT: retorna índices");
    CHECK(idx[0] == 1, "multi_argsort DT: menor primeiro");
    CHECK(idx[1] == 2, "multi_argsort DT: médio no meio");
    CHECK(idx[2] == 0, "multi_argsort DT: maior no final");
    free(idx);
    smaug_dt_free(s);
}

static void test_multi_argsort_edge_null_args(void) {
    /* ncols=0 e nrows=0 (linha 133) */
    smaug_sort_col_t col = {0};
    CHECK(smaug_multi_argsort(NULL, 1, 5) == NULL, "multi_argsort NULL cols");
    CHECK(smaug_multi_argsort(&col, 0, 5) == NULL, "multi_argsort ncols=0");
    CHECK(smaug_multi_argsort(&col, 1, 0) == NULL, "multi_argsort nrows=0");
}

static void test_rolling_window_zero(void) {
    /* window=0 para todas as 8 funções rolling (guards, ramos 2 de cada) */
    double fd[] = {1.0, 2.0, 3.0};
    smaug_series_f64_t *sf = f64_from(fd, 3);
    CHECK(smaug_f64_rolling_sum(sf,  0) == NULL, "f64 rolling_sum window=0");
    CHECK(smaug_f64_rolling_mean(sf, 0) == NULL, "f64 rolling_mean window=0");
    CHECK(smaug_f64_rolling_min(sf,  0) == NULL, "f64 rolling_min window=0");
    CHECK(smaug_f64_rolling_max(sf,  0) == NULL, "f64 rolling_max window=0");
    smaug_f64_free(sf);

    int64_t id[] = {1, 2, 3};
    smaug_series_i64_t *si = i64_from(id, 3);
    CHECK(smaug_i64_rolling_sum(si,  0) == NULL, "i64 rolling_sum window=0");
    CHECK(smaug_i64_rolling_mean(si, 0) == NULL, "i64 rolling_mean window=0");
    CHECK(smaug_i64_rolling_min(si,  0) == NULL, "i64 rolling_min window=0");
    CHECK(smaug_i64_rolling_max(si,  0) == NULL, "i64 rolling_max window=0");
    smaug_i64_free(si);
}

static void test_rolling_all_null_window(void) {
    /* cnt==0 path: janela completa formada só de nulls → NA (linhas 210, 236, 346)
     * [null, null, 1.0] window=2: posição 1 tem janela [null,null] → NA */
    double arr[] = {-1.0, -1.0, 1.0};
    smaug_series_f64_t *sf = f64_from(arr, 3);
    smaug_f64_set_null(sf, 0);
    smaug_f64_set_null(sf, 1);

    /* rolling_sum */
    smaug_series_f64_t *rs = smaug_f64_rolling_sum(sf, 2);
    CHECK(rs && f64_null(rs, 1), "f64 rolling_sum all-null window: pos 1 = NA (cnt=0)");
    smaug_f64_free(rs);
    /* rolling_mean */
    smaug_series_f64_t *rm = smaug_f64_rolling_mean(sf, 2);
    CHECK(rm && f64_null(rm, 1), "f64 rolling_mean all-null window: pos 1 = NA");
    smaug_f64_free(rm);
    smaug_f64_free(sf);

    /* i64: [null, null, 1] window=2 */
    int64_t arri[] = {0, 0, 1};
    smaug_series_i64_t *si = i64_from(arri, 3);
    smaug_i64_set_null(si, 0);
    smaug_i64_set_null(si, 1);
    smaug_series_i64_t *ris = smaug_i64_rolling_sum(si, 2);
    CHECK(ris && i64_null(ris, 1), "i64 rolling_sum all-null: pos 1 = NA (cnt=0)");
    smaug_i64_free(ris);
    smaug_i64_free(si);
}

static void test_rolling_null_in_deque_window(void) {
    /* Null no meio de uma janela rolling_min/max — força o path de
     * cleanup do deque (linhas 258-259/301-302 em f64, 394/416 em i64)
     * e a deque vazia → NA (linhas 278/318/396/426).
     *
     * Série: [1.0, NA, NA, 2.0] window=2
     *   i=0: push 0. skip.
     *   i=1: output data[0]=1.0.
     *   i=2: null — if(258): front(0)+2<=2? Yes. Pop. deque=[]. → 278/318: empty → NA.
     *   i=3: output 2.0.
     */
    double arrf[] = {1.0, -9999.0, -9999.0, 2.0};
    smaug_series_f64_t *sf = f64_from(arrf, 4);
    smaug_f64_set_null(sf, 1);
    smaug_f64_set_null(sf, 2);

    /* rolling_min */
    smaug_series_f64_t *rmin = smaug_f64_rolling_min(sf, 2);
    CHECK(rmin && f64_null(rmin, 0),              "f64 rolling_min null-deque: [0]=NA");
    CHECK(rmin && APPROX(f64_get(rmin, 1), 1.0),  "f64 rolling_min null-deque: [1]=1.0");
    CHECK(rmin && f64_null(rmin, 2),              "f64 rolling_min null-deque: [2]=NA (258+278)");
    CHECK(rmin && APPROX(f64_get(rmin, 3), 2.0),  "f64 rolling_min null-deque: [3]=2.0");
    smaug_f64_free(rmin);

    /* rolling_max */
    smaug_series_f64_t *rmax = smaug_f64_rolling_max(sf, 2);
    CHECK(rmax && f64_null(rmax, 0),              "f64 rolling_max null-deque: [0]=NA");
    CHECK(rmax && APPROX(f64_get(rmax, 1), 1.0),  "f64 rolling_max null-deque: [1]=1.0");
    CHECK(rmax && f64_null(rmax, 2),              "f64 rolling_max null-deque: [2]=NA (301+318)");
    CHECK(rmax && APPROX(f64_get(rmax, 3), 2.0),  "f64 rolling_max null-deque: [3]=2.0");
    smaug_f64_free(rmax);
    smaug_f64_free(sf);

    /* i64: [1, NA, NA, 2] window=2 — exercita while(394)/396 e while(416)/426 */
    int64_t arri[] = {1, 0, 0, 2};
    smaug_series_i64_t *si = i64_from(arri, 4);
    smaug_i64_set_null(si, 1);
    smaug_i64_set_null(si, 2);

    smaug_series_i64_t *rimin = smaug_i64_rolling_min(si, 2);
    CHECK(rimin && i64_null(rimin, 0),         "i64 rolling_min null-deque: [0]=NA");
    CHECK(rimin && i64_get(rimin, 1) == 1,     "i64 rolling_min null-deque: [1]=1");
    CHECK(rimin && i64_null(rimin, 2),         "i64 rolling_min null-deque: [2]=NA (394+396)");
    CHECK(rimin && i64_get(rimin, 3) == 2,     "i64 rolling_min null-deque: [3]=2");
    smaug_i64_free(rimin);

    smaug_series_i64_t *rimax = smaug_i64_rolling_max(si, 2);
    CHECK(rimax && i64_null(rimax, 0),         "i64 rolling_max null-deque: [0]=NA");
    CHECK(rimax && i64_get(rimax, 1) == 1,     "i64 rolling_max null-deque: [1]=1");
    CHECK(rimax && i64_null(rimax, 2),         "i64 rolling_max null-deque: [2]=NA (416+426)");
    CHECK(rimax && i64_get(rimax, 3) == 2,     "i64 rolling_max null-deque: [3]=2");
    smaug_i64_free(rimax);
    smaug_i64_free(si);
}

/* =====================================================================
   main
   ===================================================================== */

int main(void) {
    test_f64_cumsum();
    test_i64_cumsum();
    test_f64_cumprod();
    test_i64_cumprod();
    test_f64_cummin();
    test_f64_cummax();
    test_i64_cummin();
    test_i64_cummax();
    test_f64_diff();
    test_i64_diff();
    test_f64_shift();
    test_i64_shift();
    test_typed_shift();
    test_f64_ffill();
    test_f64_bfill();
    test_i64_ffill();
    test_i64_bfill();
    test_bool_ffill_bfill();
    test_dt_ffill_bfill();
    test_str_ffill_bfill();
    test_f64_argmin_argmax();
    test_i64_argmin_argmax();
    test_typed_argminmax();
    test_typed_minmax();
    test_f64_sorted_nonnull();
    test_i64_sorted_nonnull();
    test_f64_rank();
    test_i64_rank();
    /* Grupo C */
    test_multi_argsort_single_f64();
    test_multi_argsort_single_i64();
    test_multi_argsort_str();
    test_multi_argsort_bool();
    test_multi_argsort_composite();
    test_multi_argsort_stable();
    test_multi_argsort_edge();
    test_multi_argsort_dt();
    test_multi_argsort_edge_null_args();
    test_f64_rolling_sum();
    test_f64_rolling_mean();
    test_f64_rolling_min();
    test_f64_rolling_max();
    test_i64_rolling_sum();
    test_i64_rolling_mean();
    test_i64_rolling_min_max();
    test_rolling_window_zero();
    test_rolling_all_null_window();
    test_rolling_null_in_deque_window();

    if (g_fails == 0) {
        printf("PASS: test_ops_window (%d checks)\n", g_checks);
        return 0;
    }
    fprintf(stderr, "FAIL: %d/%d checks falharam\n", g_fails, g_checks);
    return 1;
}
