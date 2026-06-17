/* tests/test_ops_window.c
 *
 * Testes C para as primitivas do Grupo A, B e C (Fase 3 Ring 0):
 * cumsum, cumprod, cummin, cummax, diff, shift, ffill, bfill, argmin, argmax,
 * sorted_nonnull, rank (Grupos A+B) e multi_argsort, rolling_* (Grupo C).
 */

#include "../include/smaug_numeric.h"
#include "../include/smaug_ops_window.h"
#include "../include/smaug_string.h"
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

    CHECK(smaug_f64_shift(NULL, 1) == NULL, "f64 shift NULL input");
}

static void test_i64_shift(void) {
    int64_t arr[] = {10, 20, 30};
    smaug_series_i64_t *s = i64_from(arr, 3);
    smaug_series_i64_t *r = smaug_i64_shift(s, 1);
    CHECK(r && i64_null(r, 0),       "i64 shift [0]=null");
    CHECK(r && i64_get(r, 1) == 10,  "i64 shift [1]=10");
    CHECK(r && i64_get(r, 2) == 20,  "i64 shift [2]=20");
    smaug_i64_free(r); smaug_i64_free(s);
    CHECK(smaug_i64_shift(NULL, 1) == NULL, "i64 shift NULL input");
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
    test_f64_ffill();
    test_f64_bfill();
    test_i64_ffill();
    test_i64_bfill();
    test_f64_argmin_argmax();
    test_i64_argmin_argmax();
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
    test_f64_rolling_sum();
    test_f64_rolling_mean();
    test_f64_rolling_min();
    test_f64_rolling_max();
    test_i64_rolling_sum();
    test_i64_rolling_mean();
    test_i64_rolling_min_max();

    if (g_fails == 0) {
        printf("PASS: test_ops_window (%d checks)\n", g_checks);
        return 0;
    }
    fprintf(stderr, "FAIL: %d/%d checks falharam\n", g_fails, g_checks);
    return 1;
}
