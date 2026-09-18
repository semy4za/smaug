#include "../include/smaug.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define EQ(left_value,right_value) (fabs((left_value)-(right_value)) < 1e-9)

/* OK não depende de assert(): permanece ativo mesmo sob -DNDEBUG (um build
   release com NDEBUG apagaria os asserts e tornaria o teste um no-op silencioso). */
static int passed_checks = 0;
#define OK(condition, message) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU: %s\n", message); exit(1); } passed_checks++; } while (0)

/* FASE 8 / resíduo — caminho de cálculo dos scalar ops, que estava SEM teste
   (o sweep A1 só batia no guard NULL). Verifica valor + propagação de null, e o
   contrato divergente do div_scalar: i64 por 0 -> tudo NULL; f64 segue IEEE. */
static void test_scalar_compute(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(4);
    smaug_f64_set(floating_point_series, 0, 1.0); smaug_f64_set(floating_point_series, 1, 2.0);
    smaug_f64_set_null(floating_point_series, 2); smaug_f64_set(floating_point_series, 3, 4.0);

    smaug_series_f64_t *subtract_scalar_series = smaug_f64_sub_scalar(floating_point_series, 0.5);   /* [0.5,1.5,null,3.5] */
    OK(subtract_scalar_series != NULL, "f64 sub_scalar retorna serie");
    OK(EQ(smaug_f64_get(subtract_scalar_series, 0, NULL), 0.5), "f64 sub_scalar [0]=0.5");
    OK(EQ(smaug_f64_get(subtract_scalar_series, 1, NULL), 1.5), "f64 sub_scalar [1]=1.5");
    OK(smaug_f64_is_null(subtract_scalar_series, 2),            "f64 sub_scalar preserva null [2]");
    OK(EQ(smaug_f64_get(subtract_scalar_series, 3, NULL), 3.5), "f64 sub_scalar [3]=3.5");
    smaug_series_f64_t *multiply_scalar_series = smaug_f64_mul_scalar(floating_point_series, 2.0);   /* [2,4,null,8] */
    OK(multiply_scalar_series != NULL, "f64 mul_scalar retorna serie");
    OK(EQ(smaug_f64_get(multiply_scalar_series, 0, NULL), 2.0), "f64 mul_scalar [0]=2.0");
    OK(EQ(smaug_f64_get(multiply_scalar_series, 1, NULL), 4.0), "f64 mul_scalar [1]=4.0");
    OK(smaug_f64_is_null(multiply_scalar_series, 2),            "f64 mul_scalar preserva null [2]");
    OK(EQ(smaug_f64_get(multiply_scalar_series, 3, NULL), 8.0), "f64 mul_scalar [3]=8.0");
    smaug_f64_free(floating_point_series); smaug_f64_free(subtract_scalar_series); smaug_f64_free(multiply_scalar_series);

    smaug_series_i64_t *integer_series = smaug_i64_create(4);
    smaug_i64_set(integer_series, 0, 10); smaug_i64_set(integer_series, 1, 20);
    smaug_i64_set_null(integer_series, 2); smaug_i64_set(integer_series, 3, 40);

    smaug_series_i64_t *subtract_scalar_series_2 = smaug_i64_sub_scalar(integer_series, 5);     /* [5,15,null,35] */
    OK(subtract_scalar_series_2 != NULL, "i64 sub_scalar retorna serie");
    OK(smaug_i64_get(subtract_scalar_series_2, 0, NULL) == 5,  "i64 sub_scalar [0]=5");
    OK(smaug_i64_get(subtract_scalar_series_2, 1, NULL) == 15, "i64 sub_scalar [1]=15");
    OK(smaug_i64_is_null(subtract_scalar_series_2, 2),         "i64 sub_scalar preserva null [2]");
    OK(smaug_i64_get(subtract_scalar_series_2, 3, NULL) == 35, "i64 sub_scalar [3]=35");
    smaug_series_i64_t *multiply_scalar_series_2 = smaug_i64_mul_scalar(integer_series, 3);     /* [30,60,null,120] */
    OK(multiply_scalar_series_2 != NULL, "i64 mul_scalar retorna serie");
    OK(smaug_i64_get(multiply_scalar_series_2, 0, NULL) == 30,  "i64 mul_scalar [0]=30");
    OK(smaug_i64_get(multiply_scalar_series_2, 1, NULL) == 60,  "i64 mul_scalar [1]=60");
    OK(smaug_i64_is_null(multiply_scalar_series_2, 2),          "i64 mul_scalar preserva null [2]");
    OK(smaug_i64_get(multiply_scalar_series_2, 3, NULL) == 120, "i64 mul_scalar [3]=120");
    smaug_series_i64_t *divide_scalar_series = smaug_i64_div_scalar(integer_series, 2);     /* [5,10,null,20] */
    OK(divide_scalar_series != NULL, "i64 div_scalar retorna serie");
    OK(smaug_i64_get(divide_scalar_series, 0, NULL) == 5,  "i64 div_scalar [0]=5");
    OK(smaug_i64_get(divide_scalar_series, 1, NULL) == 10, "i64 div_scalar [1]=10");
    OK(smaug_i64_is_null(divide_scalar_series, 2),         "i64 div_scalar preserva null [2]");
    OK(smaug_i64_get(divide_scalar_series, 3, NULL) == 20, "i64 div_scalar [3]=20");
    smaug_series_i64_t *divide_scalar_series_2 = smaug_i64_div_scalar(integer_series, 0);     /* contrato: scalar 0 -> tudo NULL */
    OK(divide_scalar_series_2 != NULL, "i64 div_scalar por 0 retorna serie");
    OK(smaug_i64_is_null(divide_scalar_series_2, 0) && smaug_i64_is_null(divide_scalar_series_2, 1)
       && smaug_i64_is_null(divide_scalar_series_2, 2) && smaug_i64_is_null(divide_scalar_series_2, 3),
       "i64 div_scalar por 0: contrato tudo NULL");
    smaug_i64_free(integer_series); smaug_i64_free(subtract_scalar_series_2); smaug_i64_free(multiply_scalar_series_2); smaug_i64_free(divide_scalar_series); smaug_i64_free(divide_scalar_series_2);
}

static void test_product(void) {
    // Teste f64
    smaug_series_f64_t *series_float64 = smaug_f64_create(3);
    smaug_f64_set(series_float64, 0, 2.0);
    smaug_f64_set(series_float64, 1, 3.0);
    smaug_f64_set(series_float64, 2, 4.0);
    OK(EQ(smaug_f64_prod(series_float64, true), 24.0), "f64 prod=24");
    smaug_f64_set_null(series_float64, 1);
    OK(isnan(smaug_f64_prod(series_float64, false)), "f64 prod with NA and ignore_na=false -> NAN");
    OK(EQ(smaug_f64_prod(series_float64, true), 8.0), "f64 prod with NA and ignore_na=true -> 8");
    smaug_f64_free(series_float64);

    // Teste i64 normal
    // Contrato real (smaug_numeric.h): o produto é o RETORNO (int64_t);
    // status é out-param por ponteiro. Estava invertido (retorno em
    // smaug_status_t, &out onde se esperava smaug_status_t*) — corrigido.
    smaug_series_i64_t *series_int64 = smaug_i64_create(3);
    smaug_i64_set(series_int64, 0, 2);
    smaug_i64_set(series_int64, 1, 3);
    smaug_i64_set(series_int64, 2, 4);
    smaug_status_t status;
    int64_t product_result = smaug_i64_prod(series_int64, true, &status);
    OK(status == SMG_OK && product_result == 24, "i64 prod=24");
    smaug_i64_set_null(series_int64, 1);
    product_result = smaug_i64_prod(series_int64, false, &status);
    OK(status == SMG_ERR_ARGUMENT, "i64 prod with NA and ignore_na=false -> SMG_ERR_ARGUMENT");
    product_result = smaug_i64_prod(series_int64, true, &status);
    OK(status == SMG_OK && product_result == 8, "i64 prod with NA and ignore_na=true -> 8");

    // Teste i64 overflow
    smaug_i64_set(series_int64, 0, INT64_MAX);
    smaug_i64_set(series_int64, 1, 2);
    smaug_i64_set_null(series_int64, 2); // para não falhar no ignore_na=false
    product_result = smaug_i64_prod(series_int64, true, &status);
    OK(status == SMG_ERR_OVERFLOW, "i64 prod overflow -> SMG_ERR_OVERFLOW");

    // Teste i64 vazio
    smaug_series_i64_t *series_empty = smaug_i64_create(0);
    product_result = smaug_i64_prod(series_empty, true, &status);
    OK(status == SMG_OK && product_result == 0, "i64 prod empty -> 0");
    smaug_i64_free(series_empty);

    smaug_i64_free(series_int64);
}

int main(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(5);
    for (size_t row_index = 0; row_index < 5; row_index++) smaug_f64_set(floating_point_series, row_index, (double)(row_index+1)*10);
    OK(EQ(smaug_f64_sum(floating_point_series, true), 150.0),  "f64 sum=150");
    OK(EQ(smaug_f64_mean(floating_point_series, true), 30.0),  "f64 mean=30");
    OK(EQ(smaug_f64_min(floating_point_series, true), 10.0),   "f64 min=10");
    OK(EQ(smaug_f64_max(floating_point_series, true), 50.0),   "f64 max=50");

    smaug_f64_set_null(floating_point_series, 2);
    OK(smaug_f64_is_null(floating_point_series, 2),            "set_null marca null");
    OK(smaug_f64_count_nonnull(floating_point_series) == 4,    "count_nonnull=4");

    test_scalar_compute();
    test_product();
    smaug_f64_free(floating_point_series);
    printf("PASS: ops (%d checks)\n", passed_checks);
    return 0;
}
