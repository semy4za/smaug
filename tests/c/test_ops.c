#include "../include/smaug.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define EQ(a,b) (fabs((a)-(b)) < 1e-9)

/* OK não depende de assert(): permanece ativo mesmo sob -DNDEBUG (um build
   release com NDEBUG apagaria os asserts e tornaria o teste um no-op silencioso). */
static int n_checks = 0;
#define OK(cond, msg) do { if (!(cond)) { \
    fprintf(stderr, "FALHOU: %s\n", msg); exit(1); } n_checks++; } while (0)

/* FASE 8 / resíduo — caminho de cálculo dos scalar ops, que estava SEM teste
   (o sweep A1 só batia no guard NULL). Verifica valor + propagação de null, e o
   contrato divergente do div_scalar: i64 por 0 -> tudo NULL; f64 segue IEEE. */
static void test_scalar_compute(void) {
    smaug_series_f64_t *f = smaug_f64_create(4);
    smaug_f64_set(f, 0, 1.0); smaug_f64_set(f, 1, 2.0);
    smaug_f64_set_null(f, 2); smaug_f64_set(f, 3, 4.0);

    smaug_series_f64_t *fs = smaug_f64_sub_scalar(f, 0.5);   /* [0.5,1.5,null,3.5] */
    OK(fs != NULL, "f64 sub_scalar retorna serie");
    OK(EQ(smaug_f64_get(fs, 0, NULL), 0.5), "f64 sub_scalar [0]=0.5");
    OK(EQ(smaug_f64_get(fs, 1, NULL), 1.5), "f64 sub_scalar [1]=1.5");
    OK(smaug_f64_is_null(fs, 2),            "f64 sub_scalar preserva null [2]");
    OK(EQ(smaug_f64_get(fs, 3, NULL), 3.5), "f64 sub_scalar [3]=3.5");
    smaug_series_f64_t *fm = smaug_f64_mul_scalar(f, 2.0);   /* [2,4,null,8] */
    OK(fm != NULL, "f64 mul_scalar retorna serie");
    OK(EQ(smaug_f64_get(fm, 0, NULL), 2.0), "f64 mul_scalar [0]=2.0");
    OK(EQ(smaug_f64_get(fm, 1, NULL), 4.0), "f64 mul_scalar [1]=4.0");
    OK(smaug_f64_is_null(fm, 2),            "f64 mul_scalar preserva null [2]");
    OK(EQ(smaug_f64_get(fm, 3, NULL), 8.0), "f64 mul_scalar [3]=8.0");
    smaug_f64_free(f); smaug_f64_free(fs); smaug_f64_free(fm);

    smaug_series_i64_t *n = smaug_i64_create(4);
    smaug_i64_set(n, 0, 10); smaug_i64_set(n, 1, 20);
    smaug_i64_set_null(n, 2); smaug_i64_set(n, 3, 40);

    smaug_series_i64_t *ns = smaug_i64_sub_scalar(n, 5);     /* [5,15,null,35] */
    OK(ns != NULL, "i64 sub_scalar retorna serie");
    OK(smaug_i64_get(ns, 0, NULL) == 5,  "i64 sub_scalar [0]=5");
    OK(smaug_i64_get(ns, 1, NULL) == 15, "i64 sub_scalar [1]=15");
    OK(smaug_i64_is_null(ns, 2),         "i64 sub_scalar preserva null [2]");
    OK(smaug_i64_get(ns, 3, NULL) == 35, "i64 sub_scalar [3]=35");
    smaug_series_i64_t *nm = smaug_i64_mul_scalar(n, 3);     /* [30,60,null,120] */
    OK(nm != NULL, "i64 mul_scalar retorna serie");
    OK(smaug_i64_get(nm, 0, NULL) == 30,  "i64 mul_scalar [0]=30");
    OK(smaug_i64_get(nm, 1, NULL) == 60,  "i64 mul_scalar [1]=60");
    OK(smaug_i64_is_null(nm, 2),          "i64 mul_scalar preserva null [2]");
    OK(smaug_i64_get(nm, 3, NULL) == 120, "i64 mul_scalar [3]=120");
    smaug_series_i64_t *nd = smaug_i64_div_scalar(n, 2);     /* [5,10,null,20] */
    OK(nd != NULL, "i64 div_scalar retorna serie");
    OK(smaug_i64_get(nd, 0, NULL) == 5,  "i64 div_scalar [0]=5");
    OK(smaug_i64_get(nd, 1, NULL) == 10, "i64 div_scalar [1]=10");
    OK(smaug_i64_is_null(nd, 2),         "i64 div_scalar preserva null [2]");
    OK(smaug_i64_get(nd, 3, NULL) == 20, "i64 div_scalar [3]=20");
    smaug_series_i64_t *nz = smaug_i64_div_scalar(n, 0);     /* contrato: scalar 0 -> tudo NULL */
    OK(nz != NULL, "i64 div_scalar por 0 retorna serie");
    OK(smaug_i64_is_null(nz, 0) && smaug_i64_is_null(nz, 1)
       && smaug_i64_is_null(nz, 2) && smaug_i64_is_null(nz, 3),
       "i64 div_scalar por 0: contrato tudo NULL");
    smaug_i64_free(n); smaug_i64_free(ns); smaug_i64_free(nm); smaug_i64_free(nd); smaug_i64_free(nz);
}

static void test_prod(void) {
    // Teste f64
    smaug_series_f64_t *s_f64 = smaug_f64_create(3);
    smaug_f64_set(s_f64, 0, 2.0);
    smaug_f64_set(s_f64, 1, 3.0);
    smaug_f64_set(s_f64, 2, 4.0);
    OK(EQ(smaug_f64_prod(s_f64, true), 24.0), "f64 prod=24");
    smaug_f64_set_null(s_f64, 1);
    OK(isnan(smaug_f64_prod(s_f64, false)), "f64 prod with NA and ignore_na=false -> NAN");
    OK(EQ(smaug_f64_prod(s_f64, true), 8.0), "f64 prod with NA and ignore_na=true -> 8");
    smaug_f64_free(s_f64);

    // Teste i64 normal
    smaug_series_i64_t *s_i64 = smaug_i64_create(3);
    smaug_i64_set(s_i64, 0, 2);
    smaug_i64_set(s_i64, 1, 3);
    smaug_i64_set(s_i64, 2, 4);
    int64_t out;
    smaug_status_t status = smaug_i64_prod(s_i64, true, &out);
    OK(status == SMG_OK && out == 24, "i64 prod=24");
    smaug_i64_set_null(s_i64, 1);
    status = smaug_i64_prod(s_i64, false, &out);
    OK(status == SMG_ERR_ARGUMENT, "i64 prod with NA and ignore_na=false -> SMG_ERR_ARGUMENT");
    status = smaug_i64_prod(s_i64, true, &out);
    OK(status == SMG_OK && out == 8, "i64 prod with NA and ignore_na=true -> 8");

    // Teste i64 overflow
    smaug_i64_set(s_i64, 0, INT64_MAX);
    smaug_i64_set(s_i64, 1, 2);
    smaug_i64_set_null(s_i64, 2); // para não falhar no ignore_na=false
    status = smaug_i64_prod(s_i64, true, &out);
    OK(status == SMG_ERR_OOB, "i64 prod overflow -> SMG_ERR_OOB");

    // Teste i64 vazio
    smaug_series_i64_t *s_empty = smaug_i64_create(0);
    status = smaug_i64_prod(s_empty, true, &out);
    OK(status == SMG_OK && out == 0, "i64 prod empty -> 0");
    smaug_i64_free(s_empty);

    smaug_i64_free(s_i64);
}

int main(void) {
    smaug_series_f64_t *s = smaug_f64_create(5);
    for (size_t i = 0; i < 5; i++) smaug_f64_set(s, i, (double)(i+1)*10);
    OK(EQ(smaug_f64_sum(s, true), 150.0),  "f64 sum=150");
    OK(EQ(smaug_f64_mean(s, true), 30.0),  "f64 mean=30");
    OK(EQ(smaug_f64_min(s, true), 10.0),   "f64 min=10");
    OK(EQ(smaug_f64_max(s, true), 50.0),   "f64 max=50");

    smaug_f64_set_null(s, 2);
    OK(smaug_f64_is_null(s, 2),            "set_null marca null");
    OK(smaug_f64_count_nonnull(s) == 4,    "count_nonnull=4");

    test_scalar_compute();
    test_prod(); 
    smaug_f64_free(s);
    printf("PASS: ops (%d checks)\n", n_checks);
    return 0;
}