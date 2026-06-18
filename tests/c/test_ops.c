#include "../include/smaug.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

#define EQ(a,b) (fabs((a)-(b)) < 1e-9)

/* FASE 8 / resíduo — caminho de cálculo dos scalar ops, que estava SEM teste
   (o sweep A1 só batia no guard NULL). Verifica valor + propagação de null, e o
   contrato divergente do div_scalar: i64 por 0 -> tudo NULL; f64 segue IEEE. */
static void test_scalar_compute(void) {
    smaug_series_f64_t *f = smaug_f64_create(4);
    smaug_f64_set(f, 0, 1.0); smaug_f64_set(f, 1, 2.0);
    smaug_f64_set_null(f, 2); smaug_f64_set(f, 3, 4.0);

    smaug_series_f64_t *fs = smaug_f64_sub_scalar(f, 0.5);   /* [0.5,1.5,null,3.5] */
    assert(fs && EQ(smaug_f64_get(fs, 0, NULL), 0.5) && EQ(smaug_f64_get(fs, 1, NULL), 1.5)
              && smaug_f64_is_null(fs, 2) && EQ(smaug_f64_get(fs, 3, NULL), 3.5));
    smaug_series_f64_t *fm = smaug_f64_mul_scalar(f, 2.0);   /* [2,4,null,8] */
    assert(fm && EQ(smaug_f64_get(fm, 0, NULL), 2.0) && EQ(smaug_f64_get(fm, 1, NULL), 4.0)
              && smaug_f64_is_null(fm, 2) && EQ(smaug_f64_get(fm, 3, NULL), 8.0));
    smaug_f64_free(f); smaug_f64_free(fs); smaug_f64_free(fm);

    smaug_series_i64_t *n = smaug_i64_create(4);
    smaug_i64_set(n, 0, 10); smaug_i64_set(n, 1, 20);
    smaug_i64_set_null(n, 2); smaug_i64_set(n, 3, 40);

    smaug_series_i64_t *ns = smaug_i64_sub_scalar(n, 5);     /* [5,15,null,35] */
    assert(ns && smaug_i64_get(ns, 0, NULL) == 5 && smaug_i64_get(ns, 1, NULL) == 15
              && smaug_i64_is_null(ns, 2) && smaug_i64_get(ns, 3, NULL) == 35);
    smaug_series_i64_t *nm = smaug_i64_mul_scalar(n, 3);     /* [30,60,null,120] */
    assert(nm && smaug_i64_get(nm, 0, NULL) == 30 && smaug_i64_get(nm, 1, NULL) == 60
              && smaug_i64_is_null(nm, 2) && smaug_i64_get(nm, 3, NULL) == 120);
    smaug_series_i64_t *nd = smaug_i64_div_scalar(n, 2);     /* [5,10,null,20] */
    assert(nd && smaug_i64_get(nd, 0, NULL) == 5 && smaug_i64_get(nd, 1, NULL) == 10
              && smaug_i64_is_null(nd, 2) && smaug_i64_get(nd, 3, NULL) == 20);
    smaug_series_i64_t *nz = smaug_i64_div_scalar(n, 0);     /* contrato: scalar 0 -> tudo NULL */
    assert(nz && smaug_i64_is_null(nz, 0) && smaug_i64_is_null(nz, 1)
              && smaug_i64_is_null(nz, 2) && smaug_i64_is_null(nz, 3));
    smaug_i64_free(n); smaug_i64_free(ns); smaug_i64_free(nm); smaug_i64_free(nd); smaug_i64_free(nz);
}

int main(void) {
    smaug_series_f64_t *s = smaug_f64_create(5);
    for (size_t i = 0; i < 5; i++) smaug_f64_set(s, i, (double)(i+1)*10);
    assert(EQ(smaug_f64_sum(s, true), 150.0));
    assert(EQ(smaug_f64_mean(s, true), 30.0));
    assert(EQ(smaug_f64_min(s, true), 10.0));
    assert(EQ(smaug_f64_max(s, true), 50.0));

    smaug_f64_set_null(s, 2);
    assert(smaug_f64_is_null(s, 2));
    assert(smaug_f64_count_nonnull(s) == 4);

    test_scalar_compute();
    smaug_f64_free(s);
    printf("PASS\n");
    return 0;
}