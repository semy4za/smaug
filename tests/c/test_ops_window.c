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

static int check_count = 0;
static int failed_checks  = 0;

#define CHECK(condition, message) do { \
    check_count++; \
    if (!(condition)) { failed_checks++; fprintf(stderr, "FAIL [%s:%d]: %s\n", __FILE__, __LINE__, message); } \
} while (0)

#define APPROX(left_value, right_value) (fabs((left_value) - (right_value)) < 1e-9)

/* =====================================================================
   Helpers de construção
   ===================================================================== */

/* Cria série f64 a partir de array; -9999.0 indica null. */
static smaug_series_f64_t *float64_from(const double *source_values, size_t element_count) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(element_count);
    if (!floating_point_series) return NULL;
    for (size_t row_index = 0; row_index < element_count; row_index++) {
        if (source_values[row_index] == -9999.0) smaug_f64_set_null(floating_point_series, row_index);
        else                   smaug_f64_set(floating_point_series, row_index, source_values[row_index]);
    }
    return floating_point_series;
}

/* Cria série i64; INT64_MIN indica null. */
static smaug_series_i64_t *int64_from(const int64_t *source_values, size_t element_count) {
    smaug_series_i64_t *integer_series = smaug_i64_create(element_count);
    if (!integer_series) return NULL;
    for (size_t row_index = 0; row_index < element_count; row_index++) {
        if (source_values[row_index] == INT64_MIN) smaug_i64_set_null(integer_series, row_index);
        else                     smaug_i64_set(integer_series, row_index, source_values[row_index]);
    }
    return integer_series;
}

static double float64_get(const smaug_series_f64_t *source_series, size_t row_index) {
    smaug_status_t status;
    return smaug_f64_get(source_series, row_index, &status);
}
static int float64_null(const smaug_series_f64_t *source_series, size_t row_index) {
    smaug_status_t status;
    smaug_f64_get(source_series, row_index, &status);
    return status == SMG_NULL_VALUE;
}
static int64_t int64_get(const smaug_series_i64_t *source_series, size_t row_index) {
    smaug_status_t status;
    return smaug_i64_get(source_series, row_index, &status);
}
static int int64_null(const smaug_series_i64_t *source_series, size_t row_index) {
    smaug_status_t status;
    smaug_i64_get(source_series, row_index, &status);
    return status == SMG_NULL_VALUE;
}

/* Cria série bool a partir de string-padrão: '1'=true, '0'=false, 'N'=null. */
static smaug_series_bool_t *bool_from(const char *pattern) {
    size_t element_count = strlen(pattern);
    smaug_series_bool_t *boolean_series = smaug_bool_create(element_count);
    if (!boolean_series) return NULL;
    for (size_t row_index = 0; row_index < element_count; row_index++) {
        if (pattern[row_index] == 'N') smaug_bool_set_null(boolean_series, row_index);
        else               smaug_bool_set(boolean_series, row_index, pattern[row_index] == '1' ? 1 : 0);
    }
    return boolean_series;
}
static int bool_get(const smaug_series_bool_t *source_series, size_t row_index) {
    smaug_status_t status;
    return smaug_bool_get(source_series, row_index, &status);
}
static int bool_null(const smaug_series_bool_t *source_series, size_t row_index) {
    smaug_status_t status;
    smaug_bool_get(source_series, row_index, &status);
    return status == SMG_NULL_VALUE;
}

/* Cria série dt; INT64_MIN indica null (epoch ms cru). */
static smaug_series_dt_t *datetime_from(const int64_t *source_values, size_t element_count) {
    smaug_series_dt_t *source_series = smaug_dt_create(element_count);
    if (!source_series) return NULL;
    for (size_t row_index = 0; row_index < element_count; row_index++) {
        if (source_values[row_index] == INT64_MIN) smaug_dt_set_null(source_series, row_index);
        else                     smaug_dt_set(source_series, row_index, source_values[row_index]);
    }
    return source_series;
}
static int64_t datetime_get(const smaug_series_dt_t *source_series, size_t row_index) {
    smaug_status_t status;
    return smaug_dt_get(source_series, row_index, &status);
}
static int datetime_null(const smaug_series_dt_t *source_series, size_t row_index) {
    smaug_status_t status;
    smaug_dt_get(source_series, row_index, &status);
    return status != SMG_OK;
}

/* Lê string na posição i; preenche *is_null. Retorna ponteiro (não-terminado),
   use com *len. */
static const char *string_get(const smaug_series_str_t *source_series, size_t row_index, size_t *length, int *is_null) {
    const char *string_get_result = smaug_str_get(source_series, row_index, length);
    *is_null = (string_get_result == NULL);
    return string_get_result;
}
/* Compara string na posição i com literal c (NUL-terminado). */
static int string_equal_at(const smaug_series_str_t *source_series, size_t row_index, const char *column) {
    size_t length; int is_null;
    const char *text_value = string_get(source_series, row_index, &length, &is_null);
    if (is_null) return 0;
    size_t cloned_series = strlen(column);
    return length == cloned_series && (cloned_series == 0 || memcmp(text_value, column, cloned_series) == 0);
}

/* =====================================================================
   cumsum
   ===================================================================== */

static void test_float64_cumulative_sum(void) {
    /* [1, 2, 3] → [1, 3, 6] */
    double source_values[] = {1.0, 2.0, 3.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 3);
    smaug_series_f64_t *cumulative_sum_series = smaug_f64_cumsum(source_series);
    CHECK(cumulative_sum_series && !float64_null(cumulative_sum_series, 0) && APPROX(float64_get(cumulative_sum_series, 0), 1.0), "f64 cumsum [0]=1");
    CHECK(cumulative_sum_series && !float64_null(cumulative_sum_series, 1) && APPROX(float64_get(cumulative_sum_series, 1), 3.0), "f64 cumsum [1]=3");
    CHECK(cumulative_sum_series && !float64_null(cumulative_sum_series, 2) && APPROX(float64_get(cumulative_sum_series, 2), 6.0), "f64 cumsum [2]=6");
    smaug_f64_free(cumulative_sum_series); smaug_f64_free(source_series);

    /* [1, null, 3] → [1, null, null] (null propaga) */
    double source_values_2[] = {1.0, -9999.0, 3.0};
    smaug_series_f64_t *source_series_2 = float64_from(source_values_2, 3);
    smaug_series_f64_t *cumulative_sum_series_2 = smaug_f64_cumsum(source_series_2);
    CHECK(cumulative_sum_series_2 && !float64_null(cumulative_sum_series_2, 0) && APPROX(float64_get(cumulative_sum_series_2, 0), 1.0), "f64 cumsum null prop [0]=1");
    CHECK(cumulative_sum_series_2 && float64_null(cumulative_sum_series_2, 1),  "f64 cumsum null prop [1]=null");
    CHECK(cumulative_sum_series_2 && float64_null(cumulative_sum_series_2, 2),  "f64 cumsum null prop [2]=null");
    smaug_f64_free(cumulative_sum_series_2); smaug_f64_free(source_series_2);

    /* série vazia */
    smaug_series_f64_t *floating_point_series = smaug_f64_create(0);
    smaug_series_f64_t *cumulative_sum_series_3 = smaug_f64_cumsum(floating_point_series);
    CHECK(cumulative_sum_series_3 && cumulative_sum_series_3->size == 0, "f64 cumsum vazia");
    smaug_f64_free(cumulative_sum_series_3); smaug_f64_free(floating_point_series);

    /* NULL input */
    CHECK(smaug_f64_cumsum(NULL) == NULL, "f64 cumsum NULL input");
}

static void test_int64_cumulative_sum(void) {
    int64_t source_values[] = {1, 2, 3};
    smaug_series_i64_t *source_series = int64_from(source_values, 3);
    smaug_series_i64_t *cumulative_sum_series = smaug_i64_cumsum(source_series);
    CHECK(cumulative_sum_series && !int64_null(cumulative_sum_series, 0) && int64_get(cumulative_sum_series, 0) == 1, "i64 cumsum [0]=1");
    CHECK(cumulative_sum_series && !int64_null(cumulative_sum_series, 1) && int64_get(cumulative_sum_series, 1) == 3, "i64 cumsum [1]=3");
    CHECK(cumulative_sum_series && !int64_null(cumulative_sum_series, 2) && int64_get(cumulative_sum_series, 2) == 6, "i64 cumsum [2]=6");
    smaug_i64_free(cumulative_sum_series); smaug_i64_free(source_series);

    int64_t source_values_2[] = {1, INT64_MIN, 3};
    smaug_series_i64_t *source_series_2 = int64_from(source_values_2, 3);
    smaug_series_i64_t *cumulative_sum_series_2 = smaug_i64_cumsum(source_series_2);
    CHECK(cumulative_sum_series_2 && !int64_null(cumulative_sum_series_2, 0) && int64_get(cumulative_sum_series_2, 0) == 1, "i64 cumsum null [0]=1");
    CHECK(cumulative_sum_series_2 && int64_null(cumulative_sum_series_2, 1), "i64 cumsum null [1]=null");
    CHECK(cumulative_sum_series_2 && int64_null(cumulative_sum_series_2, 2), "i64 cumsum null [2]=null");
    smaug_i64_free(cumulative_sum_series_2); smaug_i64_free(source_series_2);

    CHECK(smaug_i64_cumsum(NULL) == NULL, "i64 cumsum NULL input");
}

/* =====================================================================
   cumprod
   ===================================================================== */

static void test_float64_cumulative_product(void) {
    double source_values[] = {2.0, 3.0, 4.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 3);
    smaug_series_f64_t *cumulative_product_series = smaug_f64_cumprod(source_series);
    CHECK(cumulative_product_series && APPROX(float64_get(cumulative_product_series, 0), 2.0),  "f64 cumprod [0]=2");
    CHECK(cumulative_product_series && APPROX(float64_get(cumulative_product_series, 1), 6.0),  "f64 cumprod [1]=6");
    CHECK(cumulative_product_series && APPROX(float64_get(cumulative_product_series, 2), 24.0), "f64 cumprod [2]=24");
    smaug_f64_free(cumulative_product_series); smaug_f64_free(source_series);

    double source_values_2[] = {2.0, -9999.0, 3.0};
    smaug_series_f64_t *source_series_2 = float64_from(source_values_2, 3);
    smaug_series_f64_t *cumulative_product_series_2 = smaug_f64_cumprod(source_series_2);
    CHECK(cumulative_product_series_2 && APPROX(float64_get(cumulative_product_series_2, 0), 2.0), "f64 cumprod null [0]=2");
    CHECK(cumulative_product_series_2 && float64_null(cumulative_product_series_2, 1), "f64 cumprod null [1]=null");
    CHECK(cumulative_product_series_2 && float64_null(cumulative_product_series_2, 2), "f64 cumprod null [2]=null");
    smaug_f64_free(cumulative_product_series_2); smaug_f64_free(source_series_2);

    CHECK(smaug_f64_cumprod(NULL) == NULL, "f64 cumprod NULL input");
}

static void test_int64_cumulative_product(void) {
    int64_t source_values[] = {2, 3, 4};
    smaug_series_i64_t *source_series = int64_from(source_values, 3);
    smaug_series_i64_t *cumulative_product_series = smaug_i64_cumprod(source_series);
    CHECK(cumulative_product_series && int64_get(cumulative_product_series, 0) == 2,  "i64 cumprod [0]=2");
    CHECK(cumulative_product_series && int64_get(cumulative_product_series, 1) == 6,  "i64 cumprod [1]=6");
    CHECK(cumulative_product_series && int64_get(cumulative_product_series, 2) == 24, "i64 cumprod [2]=24");
    smaug_i64_free(cumulative_product_series); smaug_i64_free(source_series);

    CHECK(smaug_i64_cumprod(NULL) == NULL, "i64 cumprod NULL input");
}

/* =====================================================================
   cummin / cummax
   ===================================================================== */

static void test_float64_cumulative_minimum(void) {
    /* [3, 1, 4, 1, 5] → [3, 1, 1, 1, 1] */
    double source_values[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);
    smaug_series_f64_t *cumulative_minimum_series = smaug_f64_cummin(source_series);
    CHECK(cumulative_minimum_series && APPROX(float64_get(cumulative_minimum_series, 0), 3.0), "f64 cummin [0]=3");
    CHECK(cumulative_minimum_series && APPROX(float64_get(cumulative_minimum_series, 1), 1.0), "f64 cummin [1]=1");
    CHECK(cumulative_minimum_series && APPROX(float64_get(cumulative_minimum_series, 2), 1.0), "f64 cummin [2]=1");
    CHECK(cumulative_minimum_series && APPROX(float64_get(cumulative_minimum_series, 4), 1.0), "f64 cummin [4]=1");
    smaug_f64_free(cumulative_minimum_series); smaug_f64_free(source_series);

    /* [3, null, 1] → [3, null, 1] (null não propaga para frente) */
    double source_values_2[] = {3.0, -9999.0, 1.0};
    smaug_series_f64_t *source_series_2 = float64_from(source_values_2, 3);
    smaug_series_f64_t *cumulative_minimum_series_2 = smaug_f64_cummin(source_series_2);
    CHECK(cumulative_minimum_series_2 && APPROX(float64_get(cumulative_minimum_series_2, 0), 3.0), "f64 cummin null [0]=3");
    CHECK(cumulative_minimum_series_2 && float64_null(cumulative_minimum_series_2, 1),              "f64 cummin null [1]=null");
    CHECK(cumulative_minimum_series_2 && APPROX(float64_get(cumulative_minimum_series_2, 2), 1.0), "f64 cummin null [2]=1 (nao propaga)");
    smaug_f64_free(cumulative_minimum_series_2); smaug_f64_free(source_series_2);

    CHECK(smaug_f64_cummin(NULL) == NULL, "f64 cummin NULL input");
}

static void test_float64_cumulative_maximum(void) {
    double source_values[] = {1.0, 3.0, 2.0, 5.0, 4.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);
    smaug_series_f64_t *cumulative_maximum_series = smaug_f64_cummax(source_series);
    CHECK(cumulative_maximum_series && APPROX(float64_get(cumulative_maximum_series, 0), 1.0), "f64 cummax [0]=1");
    CHECK(cumulative_maximum_series && APPROX(float64_get(cumulative_maximum_series, 1), 3.0), "f64 cummax [1]=3");
    CHECK(cumulative_maximum_series && APPROX(float64_get(cumulative_maximum_series, 2), 3.0), "f64 cummax [2]=3");
    CHECK(cumulative_maximum_series && APPROX(float64_get(cumulative_maximum_series, 3), 5.0), "f64 cummax [3]=5");
    CHECK(cumulative_maximum_series && APPROX(float64_get(cumulative_maximum_series, 4), 5.0), "f64 cummax [4]=5");
    smaug_f64_free(cumulative_maximum_series); smaug_f64_free(source_series);

    CHECK(smaug_f64_cummax(NULL) == NULL, "f64 cummax NULL input");
}

static void test_int64_cumulative_minimum(void) {
    int64_t source_values[] = {5, 2, 8, 1};
    smaug_series_i64_t *source_series = int64_from(source_values, 4);
    smaug_series_i64_t *cumulative_minimum_series = smaug_i64_cummin(source_series);
    CHECK(cumulative_minimum_series && int64_get(cumulative_minimum_series, 0) == 5, "i64 cummin [0]=5");
    CHECK(cumulative_minimum_series && int64_get(cumulative_minimum_series, 1) == 2, "i64 cummin [1]=2");
    CHECK(cumulative_minimum_series && int64_get(cumulative_minimum_series, 2) == 2, "i64 cummin [2]=2");
    CHECK(cumulative_minimum_series && int64_get(cumulative_minimum_series, 3) == 1, "i64 cummin [3]=1");
    smaug_i64_free(cumulative_minimum_series); smaug_i64_free(source_series);

    /* null não propaga */
    int64_t source_values_2[] = {5, INT64_MIN, 1};
    smaug_series_i64_t *source_series_2 = int64_from(source_values_2, 3);
    smaug_series_i64_t *cumulative_minimum_series_2 = smaug_i64_cummin(source_series_2);
    CHECK(cumulative_minimum_series_2 && int64_get(cumulative_minimum_series_2, 0) == 5, "i64 cummin null [0]=5");
    CHECK(cumulative_minimum_series_2 && int64_null(cumulative_minimum_series_2, 1),     "i64 cummin null [1]=null");
    CHECK(cumulative_minimum_series_2 && int64_get(cumulative_minimum_series_2, 2) == 1, "i64 cummin null [2]=1");
    smaug_i64_free(cumulative_minimum_series_2); smaug_i64_free(source_series_2);

    CHECK(smaug_i64_cummin(NULL) == NULL, "i64 cummin NULL input");
}

static void test_int64_cumulative_maximum(void) {
    int64_t source_values[] = {1, 3, 2};
    smaug_series_i64_t *source_series = int64_from(source_values, 3);
    smaug_series_i64_t *cumulative_maximum_series = smaug_i64_cummax(source_series);
    CHECK(cumulative_maximum_series && int64_get(cumulative_maximum_series, 0) == 1, "i64 cummax [0]=1");
    CHECK(cumulative_maximum_series && int64_get(cumulative_maximum_series, 1) == 3, "i64 cummax [1]=3");
    CHECK(cumulative_maximum_series && int64_get(cumulative_maximum_series, 2) == 3, "i64 cummax [2]=3");
    smaug_i64_free(cumulative_maximum_series); smaug_i64_free(source_series);
    CHECK(smaug_i64_cummax(NULL) == NULL, "i64 cummax NULL input");
}

/* =====================================================================
   diff
   ===================================================================== */

static void test_float64_diff(void) {
    /* periods=1: [10, 13, 11] → [null, 3, -2] */
    double source_values[] = {10.0, 13.0, 11.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 3);
    smaug_series_f64_t *diff_series = smaug_f64_diff(source_series, 1);
    CHECK(diff_series && float64_null(diff_series, 0),                "f64 diff [0]=null");
    CHECK(diff_series && APPROX(float64_get(diff_series, 1),  3.0),   "f64 diff [1]=3");
    CHECK(diff_series && APPROX(float64_get(diff_series, 2), -2.0),   "f64 diff [2]=-2");
    smaug_f64_free(diff_series); smaug_f64_free(source_series);

    /* periods=2: [1, 2, 4, 8] → [null, null, 3, 6] */
    double source_values_2[] = {1.0, 2.0, 4.0, 8.0};
    smaug_series_f64_t *source_series_2 = float64_from(source_values_2, 4);
    smaug_series_f64_t *diff_series_2 = smaug_f64_diff(source_series_2, 2);
    CHECK(diff_series_2 && float64_null(diff_series_2, 0), "f64 diff p2 [0]=null");
    CHECK(diff_series_2 && float64_null(diff_series_2, 1), "f64 diff p2 [1]=null");
    CHECK(diff_series_2 && APPROX(float64_get(diff_series_2, 2), 3.0), "f64 diff p2 [2]=3");
    CHECK(diff_series_2 && APPROX(float64_get(diff_series_2, 3), 6.0), "f64 diff p2 [3]=6");
    smaug_f64_free(diff_series_2); smaug_f64_free(source_series_2);

    /* null em operando */
    double source_values_3[] = {1.0, -9999.0, 3.0};
    smaug_series_f64_t *source_series_3 = float64_from(source_values_3, 3);
    smaug_series_f64_t *diff_series_3 = smaug_f64_diff(source_series_3, 1);
    CHECK(diff_series_3 && float64_null(diff_series_3, 0), "f64 diff null op [0]=null");
    CHECK(diff_series_3 && float64_null(diff_series_3, 1), "f64 diff null op [1]=null (null-curr)");
    CHECK(diff_series_3 && float64_null(diff_series_3, 2), "f64 diff null op [2]=null (null-prev)");
    smaug_f64_free(diff_series_3); smaug_f64_free(source_series_3);

    CHECK(smaug_f64_diff(NULL, 1) == NULL, "f64 diff NULL input");
}

static void test_int64_diff(void) {
    int64_t source_values[] = {10, 13, 11};
    smaug_series_i64_t *source_series = int64_from(source_values, 3);
    smaug_series_i64_t *diff_series = smaug_i64_diff(source_series, 1);
    CHECK(diff_series && int64_null(diff_series, 0),         "i64 diff [0]=null");
    CHECK(diff_series && int64_get(diff_series, 1) == 3,     "i64 diff [1]=3");
    CHECK(diff_series && int64_get(diff_series, 2) == -2,    "i64 diff [2]=-2");
    smaug_i64_free(diff_series); smaug_i64_free(source_series);
    CHECK(smaug_i64_diff(NULL, 1) == NULL, "i64 diff NULL input");
}

/* =====================================================================
   shift
   ===================================================================== */

static void test_float64_shift(void) {
    /* periods=1: [1, 2, 3] → [null, 1, 2] */
    double source_values[] = {1.0, 2.0, 3.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 3);
    smaug_series_f64_t *shift_series = smaug_f64_shift(source_series, 1);
    CHECK(shift_series && float64_null(shift_series, 0),               "f64 shift [0]=null");
    CHECK(shift_series && APPROX(float64_get(shift_series, 1), 1.0),   "f64 shift [1]=1");
    CHECK(shift_series && APPROX(float64_get(shift_series, 2), 2.0),   "f64 shift [2]=2");
    smaug_f64_free(shift_series); smaug_f64_free(source_series);

    /* periods=0: clone */
    smaug_series_f64_t *source_series_2 = float64_from(source_values, 3);
    smaug_series_f64_t *shift_series_2 = smaug_f64_shift(source_series_2, 0);
    CHECK(shift_series_2 && APPROX(float64_get(shift_series_2, 0), 1.0), "f64 shift p0 [0]=1");
    CHECK(shift_series_2 && APPROX(float64_get(shift_series_2, 2), 3.0), "f64 shift p0 [2]=3");
    smaug_f64_free(shift_series_2); smaug_f64_free(source_series_2);

    /* periods >= size: toda null */
    smaug_series_f64_t *source_series_3 = float64_from(source_values, 3);
    smaug_series_f64_t *shift_series_3 = smaug_f64_shift(source_series_3, 5);
    CHECK(shift_series_3 && float64_null(shift_series_3, 0) && float64_null(shift_series_3, 1) && float64_null(shift_series_3, 2),
          "f64 shift >= size: toda null");
    smaug_f64_free(shift_series_3); smaug_f64_free(source_series_3);

    /* null preservado */
    double source_values_2[] = {1.0, -9999.0, 3.0};
    smaug_series_f64_t *source_series_4 = float64_from(source_values_2, 3);
    smaug_series_f64_t *shift_series_4 = smaug_f64_shift(source_series_4, 1);
    CHECK(shift_series_4 && float64_null(shift_series_4, 0),               "f64 shift null [0]=null");
    CHECK(shift_series_4 && APPROX(float64_get(shift_series_4, 1), 1.0),   "f64 shift null [1]=1");
    CHECK(shift_series_4 && float64_null(shift_series_4, 2),               "f64 shift null [2]=null (null deslocado)");
    smaug_f64_free(shift_series_4); smaug_f64_free(source_series_4);

    /* periods NEGATIVO (item 7.1b): [1,2,3] shift(-1) → [2,3,null] */
    smaug_series_f64_t *source_series_5 = float64_from(source_values, 3);
    smaug_series_f64_t *shift_series_5 = smaug_f64_shift(source_series_5, -1);
    CHECK(shift_series_5 && APPROX(float64_get(shift_series_5, 0), 2.0), "f64 shift(-1) [0]=2");
    CHECK(shift_series_5 && APPROX(float64_get(shift_series_5, 1), 3.0), "f64 shift(-1) [1]=3");
    CHECK(shift_series_5 && float64_null(shift_series_5, 2),             "f64 shift(-1) [2]=null (borda final)");
    smaug_f64_free(shift_series_5); smaug_f64_free(source_series_5);

    /* periods <= -size: toda null */
    smaug_series_f64_t *source_series_6 = float64_from(source_values, 3);
    smaug_series_f64_t *shift_series_6 = smaug_f64_shift(source_series_6, -5);
    CHECK(shift_series_6 && float64_null(shift_series_6, 0) && float64_null(shift_series_6, 2), "f64 shift(-5): toda null");
    smaug_f64_free(shift_series_6); smaug_f64_free(source_series_6);

    /* shift negativo com null preservado: [1,NA,3] shift(-1) → [NA,3,NA] */
    smaug_series_f64_t *source_series_7 = float64_from(source_values_2, 3);
    smaug_series_f64_t *shift_series_7 = smaug_f64_shift(source_series_7, -1);
    CHECK(shift_series_7 && float64_null(shift_series_7, 0),             "f64 shift(-1) null [0]=null (NA deslocado)");
    CHECK(shift_series_7 && APPROX(float64_get(shift_series_7, 1), 3.0), "f64 shift(-1) null [1]=3");
    CHECK(shift_series_7 && float64_null(shift_series_7, 2),             "f64 shift(-1) null [2]=null (borda)");
    smaug_f64_free(shift_series_7); smaug_f64_free(source_series_7);

    CHECK(smaug_f64_shift(NULL, 1) == NULL, "f64 shift NULL input");
}

static void test_int64_shift(void) {
    int64_t source_values[] = {10, 20, 30};
    smaug_series_i64_t *source_series = int64_from(source_values, 3);
    smaug_series_i64_t *shift_series = smaug_i64_shift(source_series, 1);
    CHECK(shift_series && int64_null(shift_series, 0),       "i64 shift [0]=null");
    CHECK(shift_series && int64_get(shift_series, 1) == 10,  "i64 shift [1]=10");
    CHECK(shift_series && int64_get(shift_series, 2) == 20,  "i64 shift [2]=20");
    smaug_i64_free(shift_series);
    /* negativo (item 7.1b): [10,20,30] shift(-1) → [20,30,null] */
    smaug_series_i64_t *shift_series_2 = smaug_i64_shift(source_series, -1);
    CHECK(shift_series_2 && int64_get(shift_series_2, 0) == 20, "i64 shift(-1) [0]=20");
    CHECK(shift_series_2 && int64_get(shift_series_2, 1) == 30, "i64 shift(-1) [1]=30");
    CHECK(shift_series_2 && int64_null(shift_series_2, 2),      "i64 shift(-1) [2]=null");
    smaug_i64_free(shift_series_2);
    /* shift(0) = clone */
    smaug_series_i64_t *shift_series_3 = smaug_i64_shift(source_series, 0);
    CHECK(shift_series_3 && int64_get(shift_series_3, 0) == 10 && int64_get(shift_series_3, 2) == 30, "i64 shift(0)=clone");
    smaug_i64_free(shift_series_3);
    smaug_i64_free(source_series);
    CHECK(smaug_i64_shift(NULL, 1) == NULL, "i64 shift NULL input");
}

/* shift em bool/str/dt (item 7.1b: motor agnóstico, com sinal) */
static void test_typed_shift(void) {
    /* bool: "101" shift(1) → [NA,1,0] ; shift(-1) → [0,1,NA] */
    smaug_series_bool_t *right_series = bool_from("101");
    smaug_series_bool_t *shift_series = smaug_bool_shift(right_series, 1);
    CHECK(shift_series && bool_null(shift_series, 0) && bool_get(shift_series, 1) == 1 && bool_get(shift_series, 2) == 0,
          "bool shift(1)");
    smaug_bool_free(shift_series);
    smaug_series_bool_t *shift_series_2 = smaug_bool_shift(right_series, -1);
    CHECK(shift_series_2 && bool_get(shift_series_2, 0) == 0 && bool_get(shift_series_2, 1) == 1 && bool_null(shift_series_2, 2),
          "bool shift(-1)");
    smaug_bool_free(shift_series_2);
    smaug_bool_free(right_series);
    CHECK(smaug_bool_shift(NULL, 1) == NULL, "bool shift NULL");

    /* dt: [100,200,300] shift(1) → [NA,100,200] ; shift(-1) → [200,300,NA] */
    int64_t source_values[] = {100, 200, 300};
    smaug_series_dt_t *source_series = datetime_from(source_values, 3);
    smaug_series_dt_t *source_series_2 = smaug_dt_shift(source_series, 1);
    CHECK(source_series_2 && datetime_null(source_series_2, 0) && datetime_get(source_series_2, 1) == 100 && datetime_get(source_series_2, 2) == 200,
          "dt shift(1)");
    smaug_dt_free(source_series_2);
    smaug_series_dt_t *source_series_3 = smaug_dt_shift(source_series, -1);
    CHECK(source_series_3 && datetime_get(source_series_3, 0) == 200 && datetime_get(source_series_3, 2 - 1) == 300 && datetime_null(source_series_3, 2),
          "dt shift(-1)");
    smaug_dt_free(source_series_3);
    smaug_dt_free(source_series);
    CHECK(smaug_dt_shift(NULL, 1) == NULL, "dt shift NULL");

    /* str: ["a","b","c"] shift(1) → [NA,a,b] ; shift(-2) → [c,NA,NA] */
    smaug_series_str_t *source_series_4 = smaug_str_create(3);
    smaug_str_set(source_series_4, 0, "a", 1);
    smaug_str_set(source_series_4, 1, "b", 1);
    smaug_str_set(source_series_4, 2, "c", 1);
    smaug_series_str_t *source_series_5 = smaug_str_shift(source_series_4, 1);
    size_t length; int is_null;
    string_get(source_series_5, 0, &length, &is_null);
    CHECK(is_null,                     "str shift(1) [0]=null");
    CHECK(string_equal_at(source_series_5, 1, "a"),   "str shift(1) [1]=a");
    CHECK(string_equal_at(source_series_5, 2, "b"),   "str shift(1) [2]=b");
    smaug_str_free(source_series_5);
    smaug_series_str_t *source_series_6 = smaug_str_shift(source_series_4, -2);
    CHECK(string_equal_at(source_series_6, 0, "c"),   "str shift(-2) [0]=c");
    string_get(source_series_6, 1, &length, &is_null); CHECK(is_null, "str shift(-2) [1]=null");
    string_get(source_series_6, 2, &length, &is_null); CHECK(is_null, "str shift(-2) [2]=null");
    smaug_str_free(source_series_6);
    /* |shift| >= size → toda null */
    smaug_series_str_t *source_series_7 = smaug_str_shift(source_series_4, 9);
    string_get(source_series_7, 0, &length, &is_null); CHECK(is_null, "str shift(9) all-null [0]");
    string_get(source_series_7, 2, &length, &is_null); CHECK(is_null, "str shift(9) all-null [2]");
    smaug_str_free(source_series_7);
    /* str shift com NA na fonte: [a,NA,c] shift(1) → [NA,a,NA] */
    smaug_series_str_t *source_series_8 = smaug_str_create(3);
    smaug_str_set(source_series_8, 0, "a", 1);
    smaug_str_set(source_series_8, 2, "c", 1);
    smaug_series_str_t *source_series_9 = smaug_str_shift(source_series_8, 1);
    string_get(source_series_9, 0, &length, &is_null); CHECK(is_null, "str shift(1) NA [0]=null");
    CHECK(string_equal_at(source_series_9, 1, "a"),               "str shift(1) NA [1]=a");
    string_get(source_series_9, 2, &length, &is_null); CHECK(is_null, "str shift(1) NA [2]=null (NA deslocado)");
    smaug_str_free(source_series_9); smaug_str_free(source_series_8);
    smaug_str_free(source_series_4);
    CHECK(smaug_str_shift(NULL, 1) == NULL, "str shift NULL");
}

/* =====================================================================
   ffill / bfill
   ===================================================================== */

static void test_float64_forward_fill(void) {
    /* [null, 1, null, 3, null] → [null, 1, 1, 3, 3] */
    double source_values[] = {-9999.0, 1.0, -9999.0, 3.0, -9999.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);
    smaug_series_f64_t *forward_fill_series = smaug_f64_ffill(source_series);
    CHECK(forward_fill_series && float64_null(forward_fill_series, 0),               "f64 ffill [0]=null (sem valor anterior)");
    CHECK(forward_fill_series && APPROX(float64_get(forward_fill_series, 1), 1.0),   "f64 ffill [1]=1");
    CHECK(forward_fill_series && APPROX(float64_get(forward_fill_series, 2), 1.0),   "f64 ffill [2]=1 (preenchido)");
    CHECK(forward_fill_series && APPROX(float64_get(forward_fill_series, 3), 3.0),   "f64 ffill [3]=3");
    CHECK(forward_fill_series && APPROX(float64_get(forward_fill_series, 4), 3.0),   "f64 ffill [4]=3 (preenchido)");
    smaug_f64_free(forward_fill_series); smaug_f64_free(source_series);

    CHECK(smaug_f64_ffill(NULL) == NULL, "f64 ffill NULL input");
}

static void test_float64_backward_fill(void) {
    /* [null, 1, null, 3, null] → [1, 1, 3, 3, null] */
    double source_values[] = {-9999.0, 1.0, -9999.0, 3.0, -9999.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);
    smaug_series_f64_t *backward_fill_series = smaug_f64_bfill(source_series);
    CHECK(backward_fill_series && APPROX(float64_get(backward_fill_series, 0), 1.0),   "f64 bfill [0]=1 (preenchido)");
    CHECK(backward_fill_series && APPROX(float64_get(backward_fill_series, 1), 1.0),   "f64 bfill [1]=1");
    CHECK(backward_fill_series && APPROX(float64_get(backward_fill_series, 2), 3.0),   "f64 bfill [2]=3 (preenchido)");
    CHECK(backward_fill_series && APPROX(float64_get(backward_fill_series, 3), 3.0),   "f64 bfill [3]=3");
    CHECK(backward_fill_series && float64_null(backward_fill_series, 4),               "f64 bfill [4]=null (sem valor seguinte)");
    smaug_f64_free(backward_fill_series); smaug_f64_free(source_series);

    CHECK(smaug_f64_bfill(NULL) == NULL, "f64 bfill NULL input");
}

static void test_int64_forward_fill(void) {
    int64_t source_values[] = {INT64_MIN, 5, INT64_MIN, 7};
    smaug_series_i64_t *source_series = int64_from(source_values, 4);
    smaug_series_i64_t *forward_fill_series = smaug_i64_ffill(source_series);
    CHECK(forward_fill_series && int64_null(forward_fill_series, 0),       "i64 ffill [0]=null");
    CHECK(forward_fill_series && int64_get(forward_fill_series, 1) == 5,   "i64 ffill [1]=5");
    CHECK(forward_fill_series && int64_get(forward_fill_series, 2) == 5,   "i64 ffill [2]=5 (preenchido)");
    CHECK(forward_fill_series && int64_get(forward_fill_series, 3) == 7,   "i64 ffill [3]=7");
    smaug_i64_free(forward_fill_series); smaug_i64_free(source_series);
    CHECK(smaug_i64_ffill(NULL) == NULL, "i64 ffill NULL input");
}

static void test_int64_backward_fill(void) {
    int64_t source_values[] = {INT64_MIN, 5, INT64_MIN};
    smaug_series_i64_t *source_series = int64_from(source_values, 3);
    smaug_series_i64_t *backward_fill_series = smaug_i64_bfill(source_series);
    CHECK(backward_fill_series && int64_get(backward_fill_series, 0) == 5,   "i64 bfill [0]=5 (preenchido)");
    CHECK(backward_fill_series && int64_get(backward_fill_series, 1) == 5,   "i64 bfill [1]=5");
    CHECK(backward_fill_series && int64_null(backward_fill_series, 2),       "i64 bfill [2]=null");
    smaug_i64_free(backward_fill_series); smaug_i64_free(source_series);
    CHECK(smaug_i64_bfill(NULL) == NULL, "i64 bfill NULL input");
}

/* ----- ffill/bfill em bool/str/dt (item 7.1: motor agnóstico a tipo) ----- */

static void test_bool_forward_fill_backward_fill(void) {
    /* "1NN0N" → ffill: 1,1,1,0,0 ; bfill: 1,0,0,0,NA */
    smaug_series_bool_t *source_series = bool_from("1NN0N");
    smaug_series_bool_t *forward_fill_series = smaug_bool_ffill(source_series);
    CHECK(forward_fill_series && bool_get(forward_fill_series, 0) == 1, "bool ffill [0]=true");
    CHECK(forward_fill_series && bool_get(forward_fill_series, 1) == 1, "bool ffill [1]=true (preenchido)");
    CHECK(forward_fill_series && bool_get(forward_fill_series, 2) == 1, "bool ffill [2]=true (preenchido)");
    CHECK(forward_fill_series && bool_get(forward_fill_series, 3) == 0, "bool ffill [3]=false");
    CHECK(forward_fill_series && bool_get(forward_fill_series, 4) == 0, "bool ffill [4]=false (preenchido)");
    smaug_bool_free(forward_fill_series);

    smaug_series_bool_t *backward_fill_series = smaug_bool_bfill(source_series);
    CHECK(backward_fill_series && bool_get(backward_fill_series, 0) == 1, "bool bfill [0]=true");
    CHECK(backward_fill_series && bool_get(backward_fill_series, 1) == 0, "bool bfill [1]=false (preenchido)");
    CHECK(backward_fill_series && bool_get(backward_fill_series, 3) == 0, "bool bfill [3]=false");
    CHECK(backward_fill_series && bool_null(backward_fill_series, 4),     "bool bfill [4]=null (sem seguinte)");
    smaug_bool_free(backward_fill_series);

    /* ffill com NA na borda inicial: "N1" → NA,true */
    smaug_series_bool_t *source_series_2 = bool_from("N1");
    smaug_series_bool_t *forward_fill_series_2 = smaug_bool_ffill(source_series_2);
    CHECK(forward_fill_series_2 && bool_null(forward_fill_series_2, 0),     "bool ffill borda [0]=null (sem anterior)");
    CHECK(forward_fill_series_2 && bool_get(forward_fill_series_2, 1) == 1, "bool ffill borda [1]=true");
    smaug_bool_free(forward_fill_series_2); smaug_bool_free(source_series_2);

    /* toda nula */
    smaug_series_bool_t *source_series_3 = bool_from("NNN");
    smaug_series_bool_t *forward_fill_series_3 = smaug_bool_ffill(source_series_3);
    CHECK(forward_fill_series_3 && bool_null(forward_fill_series_3, 0) && bool_null(forward_fill_series_3, 2), "bool ffill all-null: tudo null");
    smaug_bool_free(forward_fill_series_3); smaug_bool_free(source_series_3);

    smaug_bool_free(source_series);
    CHECK(smaug_bool_ffill(NULL) == NULL, "bool ffill NULL input");
    CHECK(smaug_bool_bfill(NULL) == NULL, "bool bfill NULL input");
}

static void test_datetime_forward_fill_backward_fill(void) {
    /* [NA, 100, NA, 300, NA] (epoch ms) */
    int64_t source_values[] = {INT64_MIN, 100, INT64_MIN, 300, INT64_MIN};
    smaug_series_dt_t *source_series = datetime_from(source_values, 5);

    smaug_series_dt_t *source_series_2 = smaug_dt_ffill(source_series);
    CHECK(source_series_2 && datetime_null(source_series_2, 0),          "dt ffill [0]=null (sem anterior)");
    CHECK(source_series_2 && datetime_get(source_series_2, 1) == 100,    "dt ffill [1]=100");
    CHECK(source_series_2 && datetime_get(source_series_2, 2) == 100,    "dt ffill [2]=100 (preenchido)");
    CHECK(source_series_2 && datetime_get(source_series_2, 3) == 300,    "dt ffill [3]=300");
    CHECK(source_series_2 && datetime_get(source_series_2, 4) == 300,    "dt ffill [4]=300 (preenchido)");
    smaug_dt_free(source_series_2);

    smaug_series_dt_t *source_series_3 = smaug_dt_bfill(source_series);
    CHECK(source_series_3 && datetime_get(source_series_3, 0) == 100,    "dt bfill [0]=100 (preenchido)");
    CHECK(source_series_3 && datetime_get(source_series_3, 2) == 300,    "dt bfill [2]=300 (preenchido)");
    CHECK(source_series_3 && datetime_null(source_series_3, 4),          "dt bfill [4]=null (sem seguinte)");
    smaug_dt_free(source_series_3);

    smaug_dt_free(source_series);
    CHECK(smaug_dt_ffill(NULL) == NULL, "dt ffill NULL input");
    CHECK(smaug_dt_bfill(NULL) == NULL, "dt bfill NULL input");
}

static void test_string_forward_fill_backward_fill(void) {
    /* ["a", NA, "", NA, "héllo"] — "" é valor válido distinto de NA;
       "héllo" exercita multibyte. */
    smaug_series_str_t *source_series = smaug_str_create(5);
    smaug_str_set(source_series, 0, "a", 1);
    /* idx 1 fica null (create já zera) */
    smaug_str_set(source_series, 2, "", 0);
    /* idx 3 null */
    smaug_str_set(source_series, 4, "h\xc3\xa9llo", 6);

    smaug_series_str_t *source_series_2 = smaug_str_ffill(source_series);
    CHECK(source_series_2 && string_equal_at(source_series_2, 0, "a"),       "str ffill [0]=a");
    CHECK(source_series_2 && string_equal_at(source_series_2, 1, "a"),       "str ffill [1]=a (preenchido)");
    CHECK(source_series_2 && string_equal_at(source_series_2, 2, ""),        "str ffill [2]= (vazia, válida)");
    CHECK(source_series_2 && string_equal_at(source_series_2, 3, ""),        "str ffill [3]= (preenchido c/ vazia)");
    CHECK(source_series_2 && string_equal_at(source_series_2, 4, "h\xc3\xa9llo"), "str ffill [4]=héllo");
    smaug_str_free(source_series_2);

    smaug_series_str_t *source_series_3 = smaug_str_bfill(source_series);
    CHECK(source_series_3 && string_equal_at(source_series_3, 0, "a"),       "str bfill [0]=a");
    CHECK(source_series_3 && string_equal_at(source_series_3, 1, ""),        "str bfill [1]= (preenchido c/ vazia seguinte)");
    CHECK(source_series_3 && string_equal_at(source_series_3, 3, "h\xc3\xa9llo"), "str bfill [3]=héllo (preenchido)");
    CHECK(source_series_3 && string_equal_at(source_series_3, 4, "h\xc3\xa9llo"), "str bfill [4]=héllo");
    smaug_str_free(source_series_3);

    /* borda: [NA, "x", NA] */
    smaug_series_str_t *source_series_4 = smaug_str_create(3);
    smaug_str_set(source_series_4, 1, "x", 1);
    smaug_series_str_t *source_series_5 = smaug_str_ffill(source_series_4);
    size_t length; int is_null;
    string_get(source_series_5, 0, &length, &is_null);
    CHECK(is_null,                       "str ffill borda [0]=null (sem anterior)");
    CHECK(string_equal_at(source_series_5, 2, "x"),    "str ffill borda [2]=x (preenchido)");
    smaug_str_free(source_series_5);
    smaug_series_str_t *source_series_6 = smaug_str_bfill(source_series_4);
    string_get(source_series_6, 2, &length, &is_null);
    CHECK(is_null,                       "str bfill borda [2]=null (sem seguinte)");
    CHECK(string_equal_at(source_series_6, 0, "x"),    "str bfill borda [0]=x (preenchido)");
    smaug_str_free(source_series_6); smaug_str_free(source_series_4);

    /* toda nula */
    smaug_series_str_t *source_series_7 = smaug_str_create(3);
    smaug_series_str_t *source_series_8 = smaug_str_ffill(source_series_7);
    string_get(source_series_8, 0, &length, &is_null); CHECK(is_null, "str ffill all-null [0]=null");
    string_get(source_series_8, 2, &length, &is_null); CHECK(is_null, "str ffill all-null [2]=null");
    smaug_str_free(source_series_8); smaug_str_free(source_series_7);

    smaug_str_free(source_series);
    CHECK(smaug_str_ffill(NULL) == NULL, "str ffill NULL input");
    CHECK(smaug_str_bfill(NULL) == NULL, "str bfill NULL input");
}

/* =====================================================================
   argmin / argmax
   ===================================================================== */

static void test_float64_argmin_argmax(void) {
    double source_values[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);
    CHECK(smaug_f64_argmin(source_series) == 1, "f64 argmin = 1 (0-based)");
    CHECK(smaug_f64_argmax(source_series) == 4, "f64 argmax = 4 (0-based)");
    smaug_f64_free(source_series);

    /* com null: ignora null */
    double source_values_2[] = {-9999.0, 1.0, -9999.0, 5.0};
    smaug_series_f64_t *source_series_2 = float64_from(source_values_2, 4);
    CHECK(smaug_f64_argmin(source_series_2) == 1, "f64 argmin null = 1");
    CHECK(smaug_f64_argmax(source_series_2) == 3, "f64 argmax null = 3");
    smaug_f64_free(source_series_2);

    /* toda null → SIZE_MAX */
    double source_values_3[] = {-9999.0, -9999.0};
    smaug_series_f64_t *source_series_3 = float64_from(source_values_3, 2);
    CHECK(smaug_f64_argmin(source_series_3) == (size_t)-1, "f64 argmin toda-null = SIZE_MAX");
    CHECK(smaug_f64_argmax(source_series_3) == (size_t)-1, "f64 argmax toda-null = SIZE_MAX");
    smaug_f64_free(source_series_3);

    /* vazia */
    smaug_series_f64_t *floating_point_series = smaug_f64_create(0);
    CHECK(smaug_f64_argmin(floating_point_series) == (size_t)-1, "f64 argmin vazia = SIZE_MAX");
    CHECK(smaug_f64_argmax(floating_point_series) == (size_t)-1, "f64 argmax vazia = SIZE_MAX");
    smaug_f64_free(floating_point_series);

    CHECK(smaug_f64_argmin(NULL) == (size_t)-1, "f64 argmin NULL = SIZE_MAX");
    CHECK(smaug_f64_argmax(NULL) == (size_t)-1, "f64 argmax NULL = SIZE_MAX");
}

static void test_int64_argmin_argmax(void) {
    int64_t source_values[] = {3, 1, 4, 1, 5};
    smaug_series_i64_t *source_series = int64_from(source_values, 5);
    CHECK(smaug_i64_argmin(source_series) == 1, "i64 argmin = 1");
    CHECK(smaug_i64_argmax(source_series) == 4, "i64 argmax = 4");
    smaug_i64_free(source_series);

    int64_t source_values_2[] = {INT64_MIN, 10, INT64_MIN, 2};
    smaug_series_i64_t *source_series_2 = int64_from(source_values_2, 4);
    CHECK(smaug_i64_argmin(source_series_2) == 3, "i64 argmin null = 3");
    CHECK(smaug_i64_argmax(source_series_2) == 1, "i64 argmax null = 1");
    smaug_i64_free(source_series_2);

    CHECK(smaug_i64_argmin(NULL) == (size_t)-1, "i64 argmin NULL = SIZE_MAX");
    CHECK(smaug_i64_argmax(NULL) == (size_t)-1, "i64 argmax NULL = SIZE_MAX");
}

/* argmin/argmax em dt/str/bool (item 7.2a: ordenáveis no Anel 0) */
static void test_typed_argminmax(void) {
    /* dt: cronológico. [300,100,600,100] → argmin=1, argmax=2 */
    int64_t source_values[] = {300, 100, 600, 100};
    smaug_series_dt_t *source_series = datetime_from(source_values, 4);
    CHECK(smaug_dt_argmin(source_series) == 1, "dt argmin = 1");
    CHECK(smaug_dt_argmax(source_series) == 2, "dt argmax = 2");
    smaug_dt_free(source_series);
    /* dt com NA: ignora */
    int64_t source_values_2[] = {INT64_MIN, 50, INT64_MIN, 10};
    smaug_series_dt_t *source_series_2 = datetime_from(source_values_2, 4);
    CHECK(smaug_dt_argmin(source_series_2) == 3, "dt argmin null = 3");
    CHECK(smaug_dt_argmax(source_series_2) == 1, "dt argmax null = 1");
    smaug_dt_free(source_series_2);
    /* dt toda-NA / vazia / NULL */
    int64_t source_values_3[] = {INT64_MIN, INT64_MIN};
    smaug_series_dt_t *source_series_3 = datetime_from(source_values_3, 2);
    CHECK(smaug_dt_argmin(source_series_3) == (size_t)-1, "dt argmin toda-NA = SIZE_MAX");
    smaug_dt_free(source_series_3);
    smaug_series_dt_t *source_series_4 = smaug_dt_create(0);
    CHECK(smaug_dt_argmin(source_series_4) == (size_t)-1, "dt argmin vazia = SIZE_MAX");
    smaug_dt_free(source_series_4);
    CHECK(smaug_dt_argmin(NULL) == (size_t)-1, "dt argmin NULL = SIZE_MAX");
    CHECK(smaug_dt_argmax(NULL) == (size_t)-1, "dt argmax NULL = SIZE_MAX");

    /* str: lexicográfico por bytes. ["banana","abacaxi","caju"] →
       argmin=1 (abacaxi), argmax=2 (caju) */
    smaug_series_str_t *source_series_5 = smaug_str_create(3);
    smaug_str_set(source_series_5, 0, "banana", 6);
    smaug_str_set(source_series_5, 1, "abacaxi", 7);
    smaug_str_set(source_series_5, 2, "caju", 4);
    CHECK(smaug_str_argmin(source_series_5) == 1, "str argmin = 1 (abacaxi)");
    CHECK(smaug_str_argmax(source_series_5) == 2, "str argmax = 2 (caju)");
    smaug_str_free(source_series_5);
    /* str com vazia (menor de todas) e NA */
    smaug_series_str_t *source_series_6 = smaug_str_create(4);
    smaug_str_set(source_series_6, 0, "z", 1);
    /* idx 1 = NA */
    smaug_str_set(source_series_6, 2, "", 0);
    smaug_str_set(source_series_6, 3, "m", 1);
    CHECK(smaug_str_argmin(source_series_6) == 2, "str argmin = 2 (vazia é a menor)");
    CHECK(smaug_str_argmax(source_series_6) == 0, "str argmax = 0 (z)");
    smaug_str_free(source_series_6);
    /* str prefixo: "ab" < "abc" (mais curta antes) */
    smaug_series_str_t *source_series_7 = smaug_str_create(2);
    smaug_str_set(source_series_7, 0, "abc", 3);
    smaug_str_set(source_series_7, 1, "ab", 2);
    CHECK(smaug_str_argmin(source_series_7) == 1, "str argmin prefixo = 1 (ab)");
    smaug_str_free(source_series_7);
    /* str toda-NA / vazia / NULL */
    smaug_series_str_t *source_series_8 = smaug_str_create(2);
    CHECK(smaug_str_argmin(source_series_8) == (size_t)-1, "str argmin toda-NA = SIZE_MAX");
    smaug_str_free(source_series_8);
    smaug_series_str_t *source_series_9 = smaug_str_create(0);
    CHECK(smaug_str_argmin(source_series_9) == (size_t)-1, "str argmin vazia = SIZE_MAX");
    smaug_str_free(source_series_9);
    CHECK(smaug_str_argmin(NULL) == (size_t)-1, "str argmin NULL = SIZE_MAX");
    CHECK(smaug_str_argmax(NULL) == (size_t)-1, "str argmax NULL = SIZE_MAX");

    /* bool: false<true. "101" → argmin=1 (false), argmax=0 (true) */
    smaug_series_bool_t *right_series = bool_from("101");
    CHECK(smaug_bool_argmin(right_series) == 1, "bool argmin = 1 (false)");
    CHECK(smaug_bool_argmax(right_series) == 0, "bool argmax = 0 (true)");
    smaug_bool_free(right_series);
    /* bool com NA: "N0N1" → argmin=1 (false), argmax=3 (true) */
    smaug_series_bool_t *source_series_10 = bool_from("N0N1");
    CHECK(smaug_bool_argmin(source_series_10) == 1, "bool argmin null = 1");
    CHECK(smaug_bool_argmax(source_series_10) == 3, "bool argmax null = 3");
    smaug_bool_free(source_series_10);
    /* bool toda-NA / NULL */
    smaug_series_bool_t *source_series_11 = bool_from("NN");
    CHECK(smaug_bool_argmin(source_series_11) == (size_t)-1, "bool argmin toda-NA = SIZE_MAX");
    smaug_bool_free(source_series_11);
    CHECK(smaug_bool_argmin(NULL) == (size_t)-1, "bool argmin NULL = SIZE_MAX");
    CHECK(smaug_bool_argmax(NULL) == (size_t)-1, "bool argmax NULL = SIZE_MAX");
}

/* min/max em dt/str/bool (item 7.2b: valor do menor/maior, ordenáveis) */
static void test_typed_minmax(void) {
    /* dt: cronológico. [300,100,600] → min=100, max=600 */
    int64_t source_values[] = {300, 100, 600};
    smaug_series_dt_t *source_series = datetime_from(source_values, 3);
    CHECK(smaug_dt_min(source_series, true) == 100, "dt min = 100");
    CHECK(smaug_dt_max(source_series, true) == 600, "dt max = 600");
    smaug_dt_free(source_series);
    /* dt com NA: ignore_na pula; senão sentinela */
    int64_t source_values_2[] = {300, INT64_MIN, 100};
    smaug_series_dt_t *source_series_2 = datetime_from(source_values_2, 3);
    CHECK(smaug_dt_min(source_series_2, true)  == 100,        "dt min ignore_na");
    CHECK(smaug_dt_max(source_series_2, true)  == 300,        "dt max ignore_na");
    CHECK(smaug_dt_min(source_series_2, false) == INT64_MIN,  "dt min(false) com NA = sentinela");
    smaug_dt_free(source_series_2);
    /* dt vazia / toda-NA / NULL */
    int64_t source_values_3[] = {INT64_MIN, INT64_MIN};
    smaug_series_dt_t *source_series_3 = datetime_from(source_values_3, 2);
    CHECK(smaug_dt_min(source_series_3, true) == INT64_MIN, "dt min toda-NA = sentinela");
    smaug_dt_free(source_series_3);
    CHECK(smaug_dt_min(NULL, true) == INT64_MIN, "dt min NULL = sentinela");

    /* str: lexicográfico. ["banana","abacaxi","caju"] → min=abacaxi, max=caju */
    smaug_series_str_t *source_series_4 = smaug_str_create(3);
    smaug_str_set(source_series_4, 0, "banana", 6);
    smaug_str_set(source_series_4, 1, "abacaxi", 7);
    smaug_str_set(source_series_4, 2, "caju", 4);
    size_t length; const char *text_value;
    text_value = smaug_str_min(source_series_4, true, &length);
    CHECK(text_value && length == 7 && memcmp(text_value, "abacaxi", 7) == 0, "str min = abacaxi");
    text_value = smaug_str_max(source_series_4, true, &length);
    CHECK(text_value && length == 4 && memcmp(text_value, "caju", 4) == 0,    "str max = caju");
    smaug_str_free(source_series_4);
    /* str com "" válida: ["z","","m"] → min="" (len 0, ptr não-NULL) */
    smaug_series_str_t *source_series_5 = smaug_str_create(3);
    smaug_str_set(source_series_5, 0, "z", 1);
    smaug_str_set(source_series_5, 1, "", 0);
    smaug_str_set(source_series_5, 2, "m", 1);
    text_value = smaug_str_min(source_series_5, true, &length);
    CHECK(text_value != NULL && length == 0, "str min = '' (vazia válida, ptr não-NULL)");
    smaug_str_free(source_series_5);
    /* str com NA: ignore_na pula; senão NULL */
    smaug_series_str_t *source_series_6 = smaug_str_create(3);
    smaug_str_set(source_series_6, 0, "a", 1);
    smaug_str_set(source_series_6, 2, "c", 1);  /* idx 1 = NA */
    text_value = smaug_str_min(source_series_6, true, &length);
    CHECK(text_value && length == 1 && text_value[0] == 'a',           "str min ignore_na = a");
    text_value = smaug_str_min(source_series_6, false, &length);
    CHECK(text_value == NULL,                              "str min(false) com NA = NULL");
    smaug_str_free(source_series_6);
    /* str toda-NA / vazia / NULL */
    smaug_series_str_t *source_series_7 = smaug_str_create(2);  /* tudo NA */
    CHECK(smaug_str_min(source_series_7, true, &length) == NULL,  "str min toda-NA = NULL");
    smaug_str_free(source_series_7);
    CHECK(smaug_str_min(NULL, true, &length) == NULL, "str min NULL = NULL");

    /* bool: false<true. "101" → min=false(0), max=true(1) */
    smaug_status_t status;
    smaug_series_bool_t *right_series = bool_from("101");
    CHECK(smaug_bool_min(right_series, true, &status) == 0 && status == SMG_OK, "bool min = false");
    CHECK(smaug_bool_max(right_series, true, &status) == 1 && status == SMG_OK, "bool max = true");
    smaug_bool_free(right_series);
    /* bool todos-true: "11" → min=true */
    smaug_series_bool_t *source_series_8 = bool_from("11");
    CHECK(smaug_bool_min(source_series_8, true, &status) == 1 && status == SMG_OK, "bool min todos-true = true");
    smaug_bool_free(source_series_8);
    /* bool com NA: ignore pula; senão NULL */
    smaug_series_bool_t *source_series_9 = bool_from("1N0");
    CHECK(smaug_bool_min(source_series_9, true, &status) == 0 && status == SMG_OK,    "bool min ignore_na");
    smaug_bool_min(source_series_9, false, &status);
    CHECK(status == SMG_NULL_VALUE,                                  "bool min(false) com NA = status NULL");
    smaug_bool_free(source_series_9);
    /* bool toda-NA / NULL */
    smaug_series_bool_t *source_series_10 = bool_from("NN");
    smaug_bool_min(source_series_10, true, &status);
    CHECK(status == SMG_NULL_VALUE, "bool min toda-NA = status NULL");
    smaug_bool_free(source_series_10);
    smaug_bool_min(NULL, true, &status);
    CHECK(status == SMG_NULL_VALUE, "bool min NULL = status NULL");
    /* status NULL-safe (caller passa NULL) */
    smaug_series_bool_t *source_series_11 = bool_from("10");
    CHECK(smaug_bool_min(source_series_11, true, NULL) == 0, "bool min status=NULL safe");
    smaug_bool_free(source_series_11);
}

/* =====================================================================
   sorted_nonnull
   ===================================================================== */

static void test_float64_sorted_non_null(void) {
    /* [3, 1, 4, 1, 5] → [1, 1, 3, 4, 5] */
    double source_values[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);
    size_t element_count;
    double *sorted_non_null_result = smaug_f64_sorted_nonnull(source_series, &element_count);
    CHECK(element_count == 5,              "f64 sorted_nonnull: n=5");
    CHECK(sorted_non_null_result && APPROX(sorted_non_null_result[0], 1.0), "f64 sorted_nonnull: [0]=1");
    CHECK(sorted_non_null_result && APPROX(sorted_non_null_result[4], 5.0), "f64 sorted_nonnull: [4]=5");
    free(sorted_non_null_result); smaug_f64_free(source_series);

    /* com null: [3, null, 1] → [1, 3], n=2 */
    double source_values_2[] = {3.0, -9999.0, 1.0};
    smaug_series_f64_t *source_series_2 = float64_from(source_values_2, 3);
    size_t second_length;
    double *sorted_non_null_result_2 = smaug_f64_sorted_nonnull(source_series_2, &second_length);
    CHECK(second_length == 2,                   "f64 sorted_nonnull null: n=2");
    CHECK(sorted_non_null_result_2 && APPROX(sorted_non_null_result_2[0], 1.0), "f64 sorted_nonnull null: [0]=1");
    CHECK(sorted_non_null_result_2 && APPROX(sorted_non_null_result_2[1], 3.0), "f64 sorted_nonnull null: [1]=3");
    free(sorted_non_null_result_2); smaug_f64_free(source_series_2);

    /* toda null: n=0, retorna NULL */
    double source_values_3[] = {-9999.0, -9999.0};
    smaug_series_f64_t *source_series_3 = float64_from(source_values_3, 2);
    size_t third_length;
    double *sorted_non_null_result_3 = smaug_f64_sorted_nonnull(source_series_3, &third_length);
    CHECK(third_length == 0 && sorted_non_null_result_3 == NULL, "f64 sorted_nonnull toda-null: n=0");
    smaug_f64_free(source_series_3);

    /* NULL input */
    size_t non_null_value; CHECK(smaug_f64_sorted_nonnull(NULL, &non_null_value) == NULL, "f64 sorted_nonnull NULL");
}

static void test_int64_sorted_non_null(void) {
    int64_t source_values[] = {5, 1, 3};
    smaug_series_i64_t *source_series = int64_from(source_values, 3);
    size_t element_count;
    int64_t *sorted_non_null_result = smaug_i64_sorted_nonnull(source_series, &element_count);
    CHECK(element_count == 3,            "i64 sorted_nonnull: n=3");
    CHECK(sorted_non_null_result && sorted_non_null_result[0] == 1, "i64 sorted_nonnull: [0]=1");
    CHECK(sorted_non_null_result && sorted_non_null_result[2] == 5, "i64 sorted_nonnull: [2]=5");
    free(sorted_non_null_result); smaug_i64_free(source_series);

    size_t non_null_value; CHECK(smaug_i64_sorted_nonnull(NULL, &non_null_value) == NULL, "i64 sorted_nonnull NULL");
}

/* =====================================================================
   rank
   ===================================================================== */

static void test_float64_rank(void) {
    /* [3, 1, 4, 1, 5] → average: [3, 1.5, 4, 1.5, 5] */
    double source_values[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);

    double *average_rank_series = smaug_f64_rank(source_series, 0);
    CHECK(average_rank_series && APPROX(average_rank_series[0], 3.0),   "f64 rank avg [0]=3");
    CHECK(average_rank_series && APPROX(average_rank_series[1], 1.5),   "f64 rank avg [1]=1.5");
    CHECK(average_rank_series && APPROX(average_rank_series[2], 4.0),   "f64 rank avg [2]=4");
    CHECK(average_rank_series && APPROX(average_rank_series[3], 1.5),   "f64 rank avg [3]=1.5");
    CHECK(average_rank_series && APPROX(average_rank_series[4], 5.0),   "f64 rank avg [4]=5");
    free(average_rank_series);

    /* method=min: empates recebem menor rank */
    double *minimum_rank_series = smaug_f64_rank(source_series, 1);
    CHECK(minimum_rank_series && APPROX(minimum_rank_series[1], 1.0),   "f64 rank min [1]=1");
    CHECK(minimum_rank_series && APPROX(minimum_rank_series[3], 1.0),   "f64 rank min [3]=1");
    free(minimum_rank_series);

    /* method=max */
    double *maximum_rank_series = smaug_f64_rank(source_series, 2);
    CHECK(maximum_rank_series && APPROX(maximum_rank_series[1], 2.0),   "f64 rank max [1]=2");
    CHECK(maximum_rank_series && APPROX(maximum_rank_series[3], 2.0),   "f64 rank max [3]=2");
    free(maximum_rank_series);

    /* method=first: posição de aparição */
    double *first_rank_series = smaug_f64_rank(source_series, 3);
    CHECK(first_rank_series && APPROX(first_rank_series[1], 1.0), "f64 rank first [1]=1 (aparece antes)");
    CHECK(first_rank_series && APPROX(first_rank_series[3], 2.0), "f64 rank first [3]=2 (aparece depois)");
    free(first_rank_series);

    smaug_f64_free(source_series);

    /* com null: [3, null, 1] → [2, NAN, 1] */
    double source_values_2[] = {3.0, -9999.0, 1.0};
    smaug_series_f64_t *source_series_2 = float64_from(source_values_2, 3);
    double *ranked_series = smaug_f64_rank(source_series_2, 0);
    CHECK(ranked_series && APPROX(ranked_series[0], 2.0),   "f64 rank null [0]=2");
    CHECK(ranked_series && ranked_series[1] != ranked_series[1],       "f64 rank null [1]=NAN");
    CHECK(ranked_series && APPROX(ranked_series[2], 1.0),   "f64 rank null [2]=1");
    free(ranked_series); smaug_f64_free(source_series_2);

    /* série vazia: retorna array vazio (não NULL) */
    smaug_series_f64_t *floating_point_series = smaug_f64_create(0);
    double *ranked_series_2 = smaug_f64_rank(floating_point_series, 0);
    CHECK(ranked_series_2 != NULL, "f64 rank vazia: nao NULL");
    free(ranked_series_2); smaug_f64_free(floating_point_series);

    CHECK(smaug_f64_rank(NULL, 0) == NULL, "f64 rank NULL input");
}

static void test_int64_rank(void) {
    int64_t source_values[] = {3, 1, 4, 1, 5};
    smaug_series_i64_t *source_series = int64_from(source_values, 5);
    double *ranked_series = smaug_i64_rank(source_series, 0);  /* average */
    CHECK(ranked_series && APPROX(ranked_series[0], 3.0),  "i64 rank [0]=3");
    CHECK(ranked_series && APPROX(ranked_series[1], 1.5),  "i64 rank [1]=1.5");
    CHECK(ranked_series && APPROX(ranked_series[4], 5.0),  "i64 rank [4]=5");
    free(ranked_series); smaug_i64_free(source_series);

    CHECK(smaug_i64_rank(NULL, 0) == NULL, "i64 rank NULL input");

    /* precisão acima de 2^53: três int64 distintos e consecutivos que
       colapsariam para o mesmo double. Com ordenação int64 direta, devem
       ranquear como distintos (1,2,3), não como empate. */
    int64_t source_values_2[] = { 9007199254740994LL,   /* 2^53 + 2 */
                      9007199254740992LL,   /* 2^53     */
                      9007199254740993LL };  /* 2^53 + 1 */
    smaug_series_i64_t *source_series_2 = int64_from(source_values_2, 3);
    double *ranked_series_2 = smaug_i64_rank(source_series_2, 0);  /* average; sem empates → ranks inteiros */
    CHECK(ranked_series_2 && APPROX(ranked_series_2[0], 3.0), "i64 rank >2^53: maior valor → rank 3");
    CHECK(ranked_series_2 && APPROX(ranked_series_2[1], 1.0), "i64 rank >2^53: menor valor → rank 1");
    CHECK(ranked_series_2 && APPROX(ranked_series_2[2], 2.0), "i64 rank >2^53: valor médio → rank 2");
    free(ranked_series_2); smaug_i64_free(source_series_2);
}

/* rank em dt/str/bool (item 7.3: ordenáveis, ranking double*) */
static void test_typed_rank(void) {
    /* dt cronológico: [300,100,600,100] → avg: jan(100)=1.5,1.5; 300=3; 600=4 */
    int64_t source_values[] = {300, 100, 600, 100};
    smaug_series_dt_t *source_series = datetime_from(source_values, 4);
    double *ranked_series = smaug_dt_rank(source_series, 0);
    CHECK(ranked_series && APPROX(ranked_series[0], 3.0), "dt rank avg [0]=3 (300)");
    CHECK(ranked_series && APPROX(ranked_series[1], 1.5), "dt rank avg [1]=1.5 (100 empate)");
    CHECK(ranked_series && APPROX(ranked_series[2], 4.0), "dt rank avg [2]=4 (600)");
    CHECK(ranked_series && APPROX(ranked_series[3], 1.5), "dt rank avg [3]=1.5 (100 empate)");
    free(ranked_series);
    double *ranked_series_2 = smaug_dt_rank(source_series, 1);  /* min */
    CHECK(ranked_series_2 && APPROX(ranked_series_2[1], 1.0) && APPROX(ranked_series_2[3], 1.0), "dt rank min empate=1");
    free(ranked_series_2);
    /* dt com NA */
    int64_t source_values_2[] = {300, INT64_MIN, 100};
    smaug_series_dt_t *source_series_2 = datetime_from(source_values_2, 3);
    double *ranked_series_3 = smaug_dt_rank(source_series_2, 0);
    CHECK(ranked_series_3 && APPROX(ranked_series_3[0], 2.0),    "dt rank NA [0]=2");
    CHECK(ranked_series_3 && ranked_series_3[1] != ranked_series_3[1],       "dt rank NA [1]=NAN");
    CHECK(ranked_series_3 && APPROX(ranked_series_3[2], 1.0),    "dt rank NA [2]=1");
    free(ranked_series_3); smaug_dt_free(source_series_2);
    CHECK(smaug_dt_rank(NULL, 0) == NULL, "dt rank NULL");
    smaug_dt_free(source_series);

    /* str lexicográfico: ["banana","abacaxi","caju","abacaxi"]
       → abacaxi(1,2 empate)=1.5; banana=3; caju=4 */
    smaug_series_str_t *source_series_3 = smaug_str_create(4);
    smaug_str_set(source_series_3, 0, "banana", 6);
    smaug_str_set(source_series_3, 1, "abacaxi", 7);
    smaug_str_set(source_series_3, 2, "caju", 4);
    smaug_str_set(source_series_3, 3, "abacaxi", 7);
    double *string_rank_result = smaug_str_rank(source_series_3, 0);
    CHECK(string_rank_result && APPROX(string_rank_result[0], 3.0), "str rank avg [0]=3 (banana)");
    CHECK(string_rank_result && APPROX(string_rank_result[1], 1.5), "str rank avg [1]=1.5 (abacaxi empate)");
    CHECK(string_rank_result && APPROX(string_rank_result[2], 4.0), "str rank avg [2]=4 (caju)");
    CHECK(string_rank_result && APPROX(string_rank_result[3], 1.5), "str rank avg [3]=1.5 (abacaxi empate)");
    free(string_rank_result);
    double *string_rank_result_2 = smaug_str_rank(source_series_3, 3);  /* first: ordem de aparição */
    CHECK(string_rank_result_2 && APPROX(string_rank_result_2[1], 1.0), "str rank first [1]=1 (abacaxi 1º)");
    CHECK(string_rank_result_2 && APPROX(string_rank_result_2[3], 2.0), "str rank first [3]=2 (abacaxi 2º)");
    free(string_rank_result_2);
    /* str com "" e NA: ["", NA, "a"] → ""=1, NA=NAN, a=2 */
    smaug_series_str_t *source_series_4 = smaug_str_create(3);
    smaug_str_set(source_series_4, 0, "", 0);
    smaug_str_set(source_series_4, 2, "a", 1);
    double *string_rank_result_3 = smaug_str_rank(source_series_4, 0);
    CHECK(string_rank_result_3 && APPROX(string_rank_result_3[0], 1.0), "str rank [0]=1 (vazia é menor)");
    CHECK(string_rank_result_3 && string_rank_result_3[1] != string_rank_result_3[1],    "str rank [1]=NAN");
    CHECK(string_rank_result_3 && APPROX(string_rank_result_3[2], 2.0), "str rank [2]=2");
    free(string_rank_result_3); smaug_str_free(source_series_4);
    /* str toda-NA / NULL */
    smaug_series_str_t *source_series_5 = smaug_str_create(2);
    double *string_rank_result_4 = smaug_str_rank(source_series_5, 0);
    CHECK(string_rank_result_4 && string_rank_result_4[0] != string_rank_result_4[0] && string_rank_result_4[1] != string_rank_result_4[1], "str rank toda-NA: tudo NAN");
    free(string_rank_result_4); smaug_str_free(source_series_5);
    CHECK(smaug_str_rank(NULL, 0) == NULL, "str rank NULL");
    smaug_str_free(source_series_3);

    /* bool: [true,false,true,false] → false=1,2; true=3,4
       avg: false=1.5, true=3.5 */
    smaug_series_bool_t *right_series = bool_from("1010");
    double *ranked_series_4 = smaug_bool_rank(right_series, 0);
    CHECK(ranked_series_4 && APPROX(ranked_series_4[0], 3.5), "bool rank avg [0]=3.5 (true)");
    CHECK(ranked_series_4 && APPROX(ranked_series_4[1], 1.5), "bool rank avg [1]=1.5 (false)");
    CHECK(ranked_series_4 && APPROX(ranked_series_4[2], 3.5), "bool rank avg [2]=3.5 (true)");
    CHECK(ranked_series_4 && APPROX(ranked_series_4[3], 1.5), "bool rank avg [3]=1.5 (false)");
    free(ranked_series_4);
    double *ranked_series_5 = smaug_bool_rank(right_series, 1);  /* min: false=1, true=3 */
    CHECK(ranked_series_5 && APPROX(ranked_series_5[1], 1.0) && APPROX(ranked_series_5[0], 3.0), "bool rank min");
    free(ranked_series_5);
    double *ranked_series_6 = smaug_bool_rank(right_series, 3);  /* first: false 1,2; true 3,4 */
    CHECK(ranked_series_6 && APPROX(ranked_series_6[1], 1.0) && APPROX(ranked_series_6[3], 2.0), "bool rank first false");
    CHECK(ranked_series_6 && APPROX(ranked_series_6[0], 3.0) && APPROX(ranked_series_6[2], 4.0), "bool rank first true");
    free(ranked_series_6);
    smaug_bool_free(right_series);
    /* bool com NA: "1N0" → true=2, NA=NAN, false=1 */
    smaug_series_bool_t *source_series_6 = bool_from("1N0");
    double *ranked_series_7 = smaug_bool_rank(source_series_6, 0);
    CHECK(ranked_series_7 && APPROX(ranked_series_7[0], 2.0), "bool rank NA [0]=2 (true)");
    CHECK(ranked_series_7 && ranked_series_7[1] != ranked_series_7[1],    "bool rank NA [1]=NAN");
    CHECK(ranked_series_7 && APPROX(ranked_series_7[2], 1.0), "bool rank NA [2]=1 (false)");
    free(ranked_series_7); smaug_bool_free(source_series_6);
    CHECK(smaug_bool_rank(NULL, 0) == NULL, "bool rank NULL");
}

/* =====================================================================
   multi_argsort
   ===================================================================== */

/* Helper: cria smaug_series_str_t com strings simples */
static smaug_series_str_t *string_from(const char **strings, size_t element_count) {
    smaug_series_str_t *source_series = smaug_str_create(element_count);
    if (!source_series) return NULL;
    for (size_t row_index = 0; row_index < element_count; row_index++) {
        if (strings[row_index] == NULL) smaug_str_set_null(source_series, row_index);
        else smaug_str_set(source_series, row_index, strings[row_index], strlen(strings[row_index]));
    }
    return source_series;
}

static void test_multi_argsort_single_float64(void) {
    /* Coluna única f64: [3, 1, 2] → perm [1, 2, 0] */
    double source_values[] = {3.0, 1.0, 2.0};
    smaug_series_f64_t *column = float64_from(source_values, 3);
    smaug_sort_col_t column_names[1] = {{ SMAUG_COL_F64, .f64 = column }};
    size_t *permutation = smaug_multi_argsort(column_names, 1, 3);
    CHECK(permutation && permutation[0] == 1, "multi_argsort f64 single: perm[0]=1");
    CHECK(permutation && permutation[1] == 2, "multi_argsort f64 single: perm[1]=2");
    CHECK(permutation && permutation[2] == 0, "multi_argsort f64 single: perm[2]=0");
    free(permutation); smaug_f64_free(column);
}

static void test_multi_argsort_single_int64(void) {
    int64_t source_values[] = {10, 30, 20};
    smaug_series_i64_t *column = int64_from(source_values, 3);
    smaug_sort_col_t column_names[1] = {{ SMAUG_COL_I64, .i64 = column }};
    size_t *permutation = smaug_multi_argsort(column_names, 1, 3);
    CHECK(permutation && permutation[0] == 0, "multi_argsort i64 single: perm[0]=0");
    CHECK(permutation && permutation[1] == 2, "multi_argsort i64 single: perm[1]=2");
    CHECK(permutation && permutation[2] == 1, "multi_argsort i64 single: perm[2]=1");
    free(permutation); smaug_i64_free(column);
}

static void test_multi_argsort_string(void) {
    /* ["banana", "abacate", "caju"] → perm [1, 0, 2] */
    const char *strings[] = {"banana", "abacate", "caju"};
    smaug_series_str_t *column = string_from(strings, 3);
    smaug_sort_col_t column_names[1] = {{ SMAUG_COL_STR, .str = column }};
    size_t *permutation = smaug_multi_argsort(column_names, 1, 3);
    CHECK(permutation && permutation[0] == 1, "multi_argsort str: perm[0]=1 (abacate)");
    CHECK(permutation && permutation[1] == 0, "multi_argsort str: perm[1]=0 (banana)");
    CHECK(permutation && permutation[2] == 2, "multi_argsort str: perm[2]=2 (caju)");
    free(permutation); smaug_str_free(column);
}

static void test_multi_argsort_bool(void) {
    /* [true, false, true] → perm [1, 0, 2] (false < true) */
    uint8_t source_values[] = {1, 0, 1};
    smaug_series_bool_t *column = smaug_bool_create(3);
    for (int row_index = 0; row_index < 3; row_index++) { smaug_bool_set(column, row_index, source_values[row_index]); }
    smaug_sort_col_t column_names[1] = {{ SMAUG_COL_BOOL, .boo = column }};
    size_t *permutation = smaug_multi_argsort(column_names, 1, 3);
    CHECK(permutation && permutation[0] == 1, "multi_argsort bool: perm[0]=1 (false primeiro)");
    free(permutation); smaug_bool_free(column);
}

static void test_multi_argsort_composite(void) {
    /* chave composta: col1=[SP, SP, RJ], col2=[2, 1, 3]
       ordem: RJ/3=idx2, SP/1=idx1, SP/2=idx0
       perm = [2, 1, 0] */
    const char *cities[] = {"SP", "SP", "RJ"};
    int64_t years[] = {2, 1, 3};
    smaug_series_str_t *column_city = string_from(cities, 3);
    smaug_series_i64_t *column_year = int64_from(years, 3);

    smaug_sort_col_t column_names[2] = {
        { SMAUG_COL_STR, .str = column_city },
        { SMAUG_COL_I64, .i64 = column_year }
    };
    size_t *permutation = smaug_multi_argsort(column_names, 2, 3);
    CHECK(permutation && permutation[0] == 2, "multi_argsort composite: perm[0]=2 (RJ/3)");
    CHECK(permutation && permutation[1] == 1, "multi_argsort composite: perm[1]=1 (SP/1)");
    CHECK(permutation && permutation[2] == 0, "multi_argsort composite: perm[2]=0 (SP/2)");
    free(permutation);
    smaug_str_free(column_city); smaug_i64_free(column_year);
}

static void test_multi_argsort_stable(void) {
    /* Estabilidade: empates preservam ordem original.
       col1=[1,1,1] col2=[2,2,2]: perm deve ser [0,1,2] */
    double source_values[] = {1.0, 1.0, 1.0};
    smaug_series_f64_t *column = float64_from(source_values, 3);
    smaug_sort_col_t column_names[1] = {{ SMAUG_COL_F64, .f64 = column }};
    size_t *permutation = smaug_multi_argsort(column_names, 1, 3);
    CHECK(permutation && permutation[0] == 0, "multi_argsort stable: empates preservados [0]");
    CHECK(permutation && permutation[1] == 1, "multi_argsort stable: empates preservados [1]");
    CHECK(permutation && permutation[2] == 2, "multi_argsort stable: empates preservados [2]");
    free(permutation); smaug_f64_free(column);
}

static void test_multi_argsort_edge(void) {
    /* NULL/zero */
    CHECK(smaug_multi_argsort(NULL, 1, 3) == NULL, "multi_argsort NULL cols");
    double source_values[] = {1.0};
    smaug_series_f64_t *column = float64_from(source_values, 1);
    smaug_sort_col_t column_names[1] = {{ SMAUG_COL_F64, .f64 = column }};
    CHECK(smaug_multi_argsort(column_names, 0, 1) == NULL, "multi_argsort ncols=0");
    CHECK(smaug_multi_argsort(column_names, 1, 0) == NULL, "multi_argsort nrows=0");
    smaug_f64_free(column);
}

/* =====================================================================
   rolling ops f64
   ===================================================================== */

static void test_float64_rolling_sum(void) {
    /* [1,2,3,4,5] window=3 → [NA,NA,6,9,12] */
    double source_values[] = {1.0, 2.0, 3.0, 4.0, 5.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);
    smaug_series_f64_t *rolling_sum_series = smaug_f64_rolling_sum(source_series, 3, 0);
    CHECK(rolling_sum_series && float64_null(rolling_sum_series, 0), "f64 rolling_sum [0]=NA");
    CHECK(rolling_sum_series && float64_null(rolling_sum_series, 1), "f64 rolling_sum [1]=NA");
    CHECK(rolling_sum_series && APPROX(float64_get(rolling_sum_series, 2), 6.0),  "f64 rolling_sum [2]=6");
    CHECK(rolling_sum_series && APPROX(float64_get(rolling_sum_series, 3), 9.0),  "f64 rolling_sum [3]=9");
    CHECK(rolling_sum_series && APPROX(float64_get(rolling_sum_series, 4), 12.0), "f64 rolling_sum [4]=12");
    smaug_f64_free(rolling_sum_series); smaug_f64_free(source_series);

    /* com null: [1, null, 3, 4] window=2 → [NA, 1, 3, 7] */
    double source_values_2[] = {1.0, -9999.0, 3.0, 4.0};
    smaug_series_f64_t *source_series_2 = float64_from(source_values_2, 4);
    smaug_series_f64_t *rolling_sum_series_2 = smaug_f64_rolling_sum(source_series_2, 2, 0);
    CHECK(rolling_sum_series_2 && float64_null(rolling_sum_series_2, 0),              "f64 rolling_sum null [0]=NA");
    CHECK(rolling_sum_series_2 && APPROX(float64_get(rolling_sum_series_2, 1), 1.0), "f64 rolling_sum null [1]=1 (null ignorado, soma de [1,null]=1)");
    CHECK(rolling_sum_series_2 && APPROX(float64_get(rolling_sum_series_2, 2), 3.0), "f64 rolling_sum null [2]=3 (null+3=3)");
    CHECK(rolling_sum_series_2 && APPROX(float64_get(rolling_sum_series_2, 3), 7.0), "f64 rolling_sum null [3]=7");
    smaug_f64_free(rolling_sum_series_2); smaug_f64_free(source_series_2);

    CHECK(smaug_f64_rolling_sum(NULL, 3, 0) == NULL, "f64 rolling_sum NULL");
}

static void test_float64_rolling_mean(void) {
    double source_values[] = {1.0, 2.0, 3.0, 4.0, 5.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);
    smaug_series_f64_t *rolling_mean_series = smaug_f64_rolling_mean(source_series, 3, 0);
    CHECK(rolling_mean_series && float64_null(rolling_mean_series, 0), "f64 rolling_mean [0]=NA");
    CHECK(rolling_mean_series && APPROX(float64_get(rolling_mean_series, 2), 2.0), "f64 rolling_mean [2]=2");
    CHECK(rolling_mean_series && APPROX(float64_get(rolling_mean_series, 4), 4.0), "f64 rolling_mean [4]=4");
    smaug_f64_free(rolling_mean_series); smaug_f64_free(source_series);
    CHECK(smaug_f64_rolling_mean(NULL, 3, 0) == NULL, "f64 rolling_mean NULL");
}

static void test_float64_rolling_minimum(void) {
    /* [3,1,4,1,5] window=3 → [NA,NA,1,1,1] */
    double source_values[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);
    smaug_series_f64_t *rolling_minimum_series = smaug_f64_rolling_min(source_series, 3, 0);
    CHECK(rolling_minimum_series && float64_null(rolling_minimum_series, 0), "f64 rolling_min [0]=NA");
    CHECK(rolling_minimum_series && APPROX(float64_get(rolling_minimum_series, 2), 1.0), "f64 rolling_min [2]=1");
    CHECK(rolling_minimum_series && APPROX(float64_get(rolling_minimum_series, 3), 1.0), "f64 rolling_min [3]=1");
    CHECK(rolling_minimum_series && APPROX(float64_get(rolling_minimum_series, 4), 1.0), "f64 rolling_min [4]=1");
    smaug_f64_free(rolling_minimum_series); smaug_f64_free(source_series);
    CHECK(smaug_f64_rolling_min(NULL, 3, 0) == NULL, "f64 rolling_min NULL");
}

static void test_float64_rolling_maximum(void) {
    double source_values[] = {3.0, 1.0, 4.0, 1.0, 5.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 5);
    smaug_series_f64_t *rolling_maximum_series = smaug_f64_rolling_max(source_series, 3, 0);
    CHECK(rolling_maximum_series && float64_null(rolling_maximum_series, 0), "f64 rolling_max [0]=NA");
    CHECK(rolling_maximum_series && APPROX(float64_get(rolling_maximum_series, 2), 4.0), "f64 rolling_max [2]=4");
    CHECK(rolling_maximum_series && APPROX(float64_get(rolling_maximum_series, 3), 4.0), "f64 rolling_max [3]=4");
    CHECK(rolling_maximum_series && APPROX(float64_get(rolling_maximum_series, 4), 5.0), "f64 rolling_max [4]=5");
    smaug_f64_free(rolling_maximum_series); smaug_f64_free(source_series);
    CHECK(smaug_f64_rolling_max(NULL, 3, 0) == NULL, "f64 rolling_max NULL");
}

/* =====================================================================
   rolling ops i64
   ===================================================================== */

static void test_int64_rolling_sum(void) {
    int64_t source_values[] = {1, 2, 3, 4, 5};
    smaug_series_i64_t *source_series = int64_from(source_values, 5);
    smaug_series_i64_t *rolling_sum_series = smaug_i64_rolling_sum(source_series, 3, 0);
    CHECK(rolling_sum_series && int64_null(rolling_sum_series, 0), "i64 rolling_sum [0]=NA");
    CHECK(rolling_sum_series && int64_get(rolling_sum_series, 2) == 6,  "i64 rolling_sum [2]=6");
    CHECK(rolling_sum_series && int64_get(rolling_sum_series, 4) == 12, "i64 rolling_sum [4]=12");
    smaug_i64_free(rolling_sum_series); smaug_i64_free(source_series);
    CHECK(smaug_i64_rolling_sum(NULL, 3, 0) == NULL, "i64 rolling_sum NULL");
}

static void test_int64_rolling_mean(void) {
    int64_t source_values[] = {1, 2, 3, 4, 5};
    smaug_series_i64_t *source_series = int64_from(source_values, 5);
    smaug_series_f64_t *rolling_mean_series = smaug_i64_rolling_mean(source_series, 3, 0);
    CHECK(rolling_mean_series && float64_null(rolling_mean_series, 0), "i64 rolling_mean [0]=NA");
    CHECK(rolling_mean_series && APPROX(float64_get(rolling_mean_series, 2), 2.0), "i64 rolling_mean [2]=2.0");
    CHECK(rolling_mean_series && APPROX(float64_get(rolling_mean_series, 4), 4.0), "i64 rolling_mean [4]=4.0");
    smaug_f64_free(rolling_mean_series); smaug_i64_free(source_series);
    CHECK(smaug_i64_rolling_mean(NULL, 3, 0) == NULL, "i64 rolling_mean NULL");
}

static void test_int64_rolling_minimum_maximum(void) {
    int64_t source_values[] = {3, 1, 4, 1, 5};
    smaug_series_i64_t *source_series = int64_from(source_values, 5);
    smaug_series_i64_t *rolling_minimum_series = smaug_i64_rolling_min(source_series, 3, 0);
    CHECK(rolling_minimum_series && int64_null(rolling_minimum_series, 0),       "i64 rolling_min [0]=NA");
    CHECK(rolling_minimum_series && int64_get(rolling_minimum_series, 2) == 1,   "i64 rolling_min [2]=1");
    CHECK(rolling_minimum_series && int64_get(rolling_minimum_series, 4) == 1,   "i64 rolling_min [4]=1");
    smaug_i64_free(rolling_minimum_series);

    smaug_series_i64_t *rolling_maximum_series = smaug_i64_rolling_max(source_series, 3, 0);
    CHECK(rolling_maximum_series && int64_null(rolling_maximum_series, 0),       "i64 rolling_max [0]=NA");
    CHECK(rolling_maximum_series && int64_get(rolling_maximum_series, 2) == 4,   "i64 rolling_max [2]=4");
    CHECK(rolling_maximum_series && int64_get(rolling_maximum_series, 4) == 5,   "i64 rolling_max [4]=5");
    smaug_i64_free(rolling_maximum_series);

    smaug_i64_free(source_series);
}

/* item 8a: rolling std/var/count + min_periods + rescan min/max */
static void test_rolling_8a(void) {
    /* std/var amostral (ddof=1). [1,2,3,4] w=3:
       janela {1,2,3}: mean=2, var=((1+0+1)/2)=1, std=1; {2,3,4}: idem */
    double source_values[] = {1.0, 2.0, 3.0, 4.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 4);

    smaug_series_f64_t *rolling_standard_deviation_series = smaug_f64_rolling_std(source_series, 3, 0);
    CHECK(rolling_standard_deviation_series && float64_null(rolling_standard_deviation_series, 0) && float64_null(rolling_standard_deviation_series, 1), "rolling_std [0,1]=NA");
    CHECK(rolling_standard_deviation_series && APPROX(float64_get(rolling_standard_deviation_series, 2), 1.0), "rolling_std [2]=1");
    CHECK(rolling_standard_deviation_series && APPROX(float64_get(rolling_standard_deviation_series, 3), 1.0), "rolling_std [3]=1");
    smaug_f64_free(rolling_standard_deviation_series);

    smaug_series_f64_t *rolling_variance_series = smaug_f64_rolling_var(source_series, 3, 0);
    CHECK(rolling_variance_series && APPROX(float64_get(rolling_variance_series, 2), 1.0), "rolling_var [2]=1");
    smaug_f64_free(rolling_variance_series);

    /* count → i64 */
    smaug_series_i64_t *status_code = smaug_f64_rolling_count(source_series, 3, 0);
    CHECK(status_code && int64_null(status_code, 1), "rolling_count [1]=NA (janela-cheia)");
    CHECK(status_code && int64_get(status_code, 2) == 3, "rolling_count [2]=3");
    smaug_i64_free(status_code);

    /* min_periods=1: janelas parciais. std precisa de n>=2 → [1] sozinho = NA */
    smaug_series_f64_t *rolling_standard_deviation_series_2 = smaug_f64_rolling_std(source_series, 3, 1);
    CHECK(rolling_standard_deviation_series_2 && float64_null(rolling_standard_deviation_series_2, 0),            "rolling_std mp1 [0]=NA (n<2)");
    CHECK(rolling_standard_deviation_series_2 && APPROX(float64_get(rolling_standard_deviation_series_2, 1), sqrt(0.5)), "rolling_std mp1 [1]={1,2}");
    smaug_f64_free(rolling_standard_deviation_series_2);

    /* sum com min_periods=1: janelas parciais emitem (o BUG corrigido) */
    smaug_series_f64_t *rolling_sum_series = smaug_f64_rolling_sum(source_series, 3, 1);
    CHECK(rolling_sum_series && APPROX(float64_get(rolling_sum_series, 0), 1.0), "rolling_sum mp1 [0]=1 (parcial)");
    CHECK(rolling_sum_series && APPROX(float64_get(rolling_sum_series, 1), 3.0), "rolling_sum mp1 [1]=3");
    CHECK(rolling_sum_series && APPROX(float64_get(rolling_sum_series, 2), 6.0), "rolling_sum mp1 [2]=6");
    smaug_f64_free(rolling_sum_series);

    /* count com min_periods=2 e NA: [1,NA,3,4] janelas parciais */
    double source_values_2[] = {1.0, -9999.0, 3.0, 4.0};
    smaug_series_f64_t *source_series_2 = float64_from(source_values_2, 4);
    smaug_series_i64_t *rolling_count_series = smaug_f64_rolling_count(source_series_2, 3, 2);
    CHECK(rolling_count_series && int64_null(rolling_count_series, 0), "rolling_count mp2 [0]=NA (1 nonnull)");
    CHECK(rolling_count_series && int64_null(rolling_count_series, 1), "rolling_count mp2 [1]=NA (1 nonnull)");
    CHECK(rolling_count_series && int64_get(rolling_count_series, 2) == 2, "rolling_count mp2 [2]=2");
    smaug_i64_free(rolling_count_series);

    /* min/max com min_periods → rescan type-preserving */
    smaug_series_f64_t *rolling_minimum_series = smaug_f64_rolling_min(source_series, 3, 1);
    CHECK(rolling_minimum_series && APPROX(float64_get(rolling_minimum_series, 0), 1.0), "rolling_min mp1 [0]=1 (rescan)");
    CHECK(rolling_minimum_series && APPROX(float64_get(rolling_minimum_series, 3), 2.0), "rolling_min mp1 [3]=2");
    smaug_f64_free(rolling_minimum_series);
    smaug_series_f64_t *rolling_maximum_series = smaug_f64_rolling_max(source_series, 3, 1);
    CHECK(rolling_maximum_series && APPROX(float64_get(rolling_maximum_series, 0), 1.0), "rolling_max mp1 [0]=1");
    CHECK(rolling_maximum_series && APPROX(float64_get(rolling_maximum_series, 3), 4.0), "rolling_max mp1 [3]=4");
    smaug_f64_free(rolling_maximum_series);
    smaug_f64_free(source_series_2);
    smaug_f64_free(source_series);

    /* i64 min com min_periods: rescan preserva tipo (sem perda >2^53) */
    int64_t source_values_3[] = {9007199254740993LL, 9007199254740992LL, 9007199254740994LL};
    smaug_series_i64_t *source_series_3 = int64_from(source_values_3, 3);
    smaug_series_i64_t *rbmin = smaug_i64_rolling_min(source_series_3, 2, 1);
    CHECK(rbmin && int64_get(rbmin, 1) == 9007199254740992LL, "i64 rolling_min mp >2^53 exato");
    smaug_i64_free(rbmin);
    /* std de i64 (via motor, double-safe) */
    int64_t integer_value[] = {10, 20, 30};
    smaug_series_i64_t *source_series_4 = int64_from(integer_value, 3);
    smaug_series_f64_t *ristd = smaug_i64_rolling_std(source_series_4, 2, 0);
    CHECK(ristd && APPROX(float64_get(ristd, 1), sqrt(50.0)), "i64 rolling_std [1]={10,20}");
    smaug_f64_free(ristd); smaug_i64_free(source_series_4);
    smaug_i64_free(source_series_3);
}

/* =====================================================================
   Testes de cobertura — lacunas identificadas em 2026-06-21
   ===================================================================== */

static void test_multi_argsort_datetime(void) {
    /* SMAUG_COL_DT nunca exercitado em cmp_col_at (linha 32 branch 4) */
    smaug_series_dt_t *source_series = smaug_dt_create_from_array(
        (int64_t[]){3000000LL, 1000000LL, 2000000LL}, 3);
    smaug_sort_col_t column = { .kind = SMAUG_COL_DT, .dt = source_series };
    size_t *indices = smaug_multi_argsort(&column, 1, 3);
    CHECK(indices != NULL, "multi_argsort DT: retorna índices");
    CHECK(indices[0] == 1, "multi_argsort DT: menor primeiro");
    CHECK(indices[1] == 2, "multi_argsort DT: médio no meio");
    CHECK(indices[2] == 0, "multi_argsort DT: maior no final");
    free(indices);
    smaug_dt_free(source_series);
}

static void test_multi_argsort_edge_null_args(void) {
    /* ncols=0 e nrows=0 (linha 133) */
    smaug_sort_col_t column = {0};
    CHECK(smaug_multi_argsort(NULL, 1, 5) == NULL, "multi_argsort NULL cols");
    CHECK(smaug_multi_argsort(&column, 0, 5) == NULL, "multi_argsort ncols=0");
    CHECK(smaug_multi_argsort(&column, 1, 0) == NULL, "multi_argsort nrows=0");
}

static void test_rolling_window_zero(void) {
    /* window=0 para todas as 8 funções rolling (guards, ramos 2 de cada) */
    double source_values[] = {1.0, 2.0, 3.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 3);
    CHECK(smaug_f64_rolling_sum(source_series,  0, 0) == NULL, "f64 rolling_sum window=0");
    CHECK(smaug_f64_rolling_mean(source_series, 0, 0) == NULL, "f64 rolling_mean window=0");
    CHECK(smaug_f64_rolling_min(source_series,  0, 0) == NULL, "f64 rolling_min window=0");
    CHECK(smaug_f64_rolling_max(source_series,  0, 0) == NULL, "f64 rolling_max window=0");
    smaug_f64_free(source_series);

    int64_t source_values_2[] = {1, 2, 3};
    smaug_series_i64_t *source_series_2 = int64_from(source_values_2, 3);
    CHECK(smaug_i64_rolling_sum(source_series_2,  0, 0) == NULL, "i64 rolling_sum window=0");
    CHECK(smaug_i64_rolling_mean(source_series_2, 0, 0) == NULL, "i64 rolling_mean window=0");
    CHECK(smaug_i64_rolling_min(source_series_2,  0, 0) == NULL, "i64 rolling_min window=0");
    CHECK(smaug_i64_rolling_max(source_series_2,  0, 0) == NULL, "i64 rolling_max window=0");
    smaug_i64_free(source_series_2);
}

static void test_rolling_all_null_window(void) {
    /* cnt==0 path: janela completa formada só de nulls → NA (linhas 210, 236, 346)
     * [null, null, 1.0] window=2: posição 1 tem janela [null,null] → NA */
    double source_values[] = {-1.0, -1.0, 1.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 3);
    smaug_f64_set_null(source_series, 0);
    smaug_f64_set_null(source_series, 1);

    /* rolling_sum */
    smaug_series_f64_t *rolling_sum_series = smaug_f64_rolling_sum(source_series, 2, 0);
    CHECK(rolling_sum_series && float64_null(rolling_sum_series, 1), "f64 rolling_sum all-null window: pos 1 = NA (cnt=0)");
    smaug_f64_free(rolling_sum_series);
    /* rolling_mean */
    smaug_series_f64_t *rolling_mean_series = smaug_f64_rolling_mean(source_series, 2, 0);
    CHECK(rolling_mean_series && float64_null(rolling_mean_series, 1), "f64 rolling_mean all-null window: pos 1 = NA");
    smaug_f64_free(rolling_mean_series);
    smaug_f64_free(source_series);

    /* i64: [null, null, 1] window=2 */
    int64_t source_values_2[] = {0, 0, 1};
    smaug_series_i64_t *source_series_2 = int64_from(source_values_2, 3);
    smaug_i64_set_null(source_series_2, 0);
    smaug_i64_set_null(source_series_2, 1);
    smaug_series_i64_t *rolling_sum_series_2 = smaug_i64_rolling_sum(source_series_2, 2, 0);
    CHECK(rolling_sum_series_2 && int64_null(rolling_sum_series_2, 1), "i64 rolling_sum all-null: pos 1 = NA (cnt=0)");
    smaug_i64_free(rolling_sum_series_2);
    smaug_i64_free(source_series_2);
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
    double source_values[] = {1.0, -9999.0, -9999.0, 2.0};
    smaug_series_f64_t *source_series = float64_from(source_values, 4);
    smaug_f64_set_null(source_series, 1);
    smaug_f64_set_null(source_series, 2);

    /* rolling_min */
    smaug_series_f64_t *rolling_minimum_series = smaug_f64_rolling_min(source_series, 2, 0);
    CHECK(rolling_minimum_series && float64_null(rolling_minimum_series, 0),              "f64 rolling_min null-deque: [0]=NA");
    CHECK(rolling_minimum_series && APPROX(float64_get(rolling_minimum_series, 1), 1.0),  "f64 rolling_min null-deque: [1]=1.0");
    CHECK(rolling_minimum_series && float64_null(rolling_minimum_series, 2),              "f64 rolling_min null-deque: [2]=NA (258+278)");
    CHECK(rolling_minimum_series && APPROX(float64_get(rolling_minimum_series, 3), 2.0),  "f64 rolling_min null-deque: [3]=2.0");
    smaug_f64_free(rolling_minimum_series);

    /* rolling_max */
    smaug_series_f64_t *rolling_maximum_series = smaug_f64_rolling_max(source_series, 2, 0);
    CHECK(rolling_maximum_series && float64_null(rolling_maximum_series, 0),              "f64 rolling_max null-deque: [0]=NA");
    CHECK(rolling_maximum_series && APPROX(float64_get(rolling_maximum_series, 1), 1.0),  "f64 rolling_max null-deque: [1]=1.0");
    CHECK(rolling_maximum_series && float64_null(rolling_maximum_series, 2),              "f64 rolling_max null-deque: [2]=NA (301+318)");
    CHECK(rolling_maximum_series && APPROX(float64_get(rolling_maximum_series, 3), 2.0),  "f64 rolling_max null-deque: [3]=2.0");
    smaug_f64_free(rolling_maximum_series);
    smaug_f64_free(source_series);

    /* i64: [1, NA, NA, 2] window=2 — exercita while(394)/396 e while(416)/426 */
    int64_t source_values_2[] = {1, 0, 0, 2};
    smaug_series_i64_t *source_series_2 = int64_from(source_values_2, 4);
    smaug_i64_set_null(source_series_2, 1);
    smaug_i64_set_null(source_series_2, 2);

    smaug_series_i64_t *rimin = smaug_i64_rolling_min(source_series_2, 2, 0);
    CHECK(rimin && int64_null(rimin, 0),         "i64 rolling_min null-deque: [0]=NA");
    CHECK(rimin && int64_get(rimin, 1) == 1,     "i64 rolling_min null-deque: [1]=1");
    CHECK(rimin && int64_null(rimin, 2),         "i64 rolling_min null-deque: [2]=NA (394+396)");
    CHECK(rimin && int64_get(rimin, 3) == 2,     "i64 rolling_min null-deque: [3]=2");
    smaug_i64_free(rimin);

    smaug_series_i64_t *rimax = smaug_i64_rolling_max(source_series_2, 2, 0);
    CHECK(rimax && int64_null(rimax, 0),         "i64 rolling_max null-deque: [0]=NA");
    CHECK(rimax && int64_get(rimax, 1) == 1,     "i64 rolling_max null-deque: [1]=1");
    CHECK(rimax && int64_null(rimax, 2),         "i64 rolling_max null-deque: [2]=NA (416+426)");
    CHECK(rimax && int64_get(rimax, 3) == 2,     "i64 rolling_max null-deque: [3]=2");
    smaug_i64_free(rimax);
    smaug_i64_free(source_series_2);
}

/* =====================================================================
   main
   ===================================================================== */

int main(void) {
    test_float64_cumulative_sum();
    test_int64_cumulative_sum();
    test_float64_cumulative_product();
    test_int64_cumulative_product();
    test_float64_cumulative_minimum();
    test_float64_cumulative_maximum();
    test_int64_cumulative_minimum();
    test_int64_cumulative_maximum();
    test_float64_diff();
    test_int64_diff();
    test_float64_shift();
    test_int64_shift();
    test_typed_shift();
    test_float64_forward_fill();
    test_float64_backward_fill();
    test_int64_forward_fill();
    test_int64_backward_fill();
    test_bool_forward_fill_backward_fill();
    test_datetime_forward_fill_backward_fill();
    test_string_forward_fill_backward_fill();
    test_float64_argmin_argmax();
    test_int64_argmin_argmax();
    test_typed_argminmax();
    test_typed_minmax();
    test_float64_sorted_non_null();
    test_int64_sorted_non_null();
    test_float64_rank();
    test_int64_rank();
    test_typed_rank();
    /* Grupo C */
    test_multi_argsort_single_float64();
    test_multi_argsort_single_int64();
    test_multi_argsort_string();
    test_multi_argsort_bool();
    test_multi_argsort_composite();
    test_multi_argsort_stable();
    test_multi_argsort_edge();
    test_multi_argsort_datetime();
    test_multi_argsort_edge_null_args();
    test_float64_rolling_sum();
    test_float64_rolling_mean();
    test_float64_rolling_minimum();
    test_float64_rolling_maximum();
    test_int64_rolling_sum();
    test_int64_rolling_mean();
    test_int64_rolling_minimum_maximum();
    test_rolling_8a();
    test_rolling_window_zero();
    test_rolling_all_null_window();
    test_rolling_null_in_deque_window();

    if (failed_checks == 0) {
        printf("PASS: test_ops_window (%d checks)\n", check_count);
        return 0;
    }
    fprintf(stderr, "FAIL: %d/%d checks falharam\n", failed_checks, check_count);
    return 1;
}
