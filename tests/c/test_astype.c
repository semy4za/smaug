#include "../include/smaug.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

/* OK nao depende de assert(): permanece ativo sob -DNDEBUG. */
static int n_checks = 0;
#define OK(cond, msg) do { if (!(cond)) { \
    fprintf(stderr, "FALHOU: %s\n", msg); exit(1); } n_checks++; } while (0)

/* 2^53 + 1: primeiro inteiro que double NAO representa. E o coracao do
   bug do 10.7 — o round-trip por get()/double do oraculo o corrompe para
   9007199254740992. As copias diretas em C devem preserva-lo exato. */
#define TWO53_PLUS_1  9007199254740993LL

/* ---------- Grupo A: valores normais + propagacao de null ---------- */
static void test_grupo_a_basico(void) {
    /* i64 -> f64 */
    smaug_series_i64_t *i = smaug_i64_create(3);
    smaug_i64_set(i, 0, -7); smaug_i64_set(i, 1, 42); smaug_i64_set_null(i, 2);
    smaug_series_f64_t *f = smaug_i64_to_f64(i);
    OK(f != NULL, "i64->f64 retorna serie");
    OK(smaug_f64_get(f, 0, NULL) == -7.0, "i64->f64 [0]=-7");
    OK(smaug_f64_get(f, 1, NULL) == 42.0, "i64->f64 [1]=42");
    OK(smaug_f64_is_null(f, 2),           "i64->f64 preserva null [2]");

    /* i64 -> dt (reinterpreta epoch_ms) */
    smaug_series_dt_t *d = smaug_i64_to_dt(i);
    OK(d != NULL, "i64->dt retorna serie");
    OK(smaug_dt_get(d, 1, NULL) == 42,  "i64->dt [1]=42 epoch");
    OK(smaug_dt_is_null(d, 2),          "i64->dt preserva null [2]");

    /* dt -> f64 */
    smaug_series_f64_t *df = smaug_dt_to_f64(d);
    OK(df != NULL, "dt->f64 retorna serie");
    OK(smaug_f64_get(df, 0, NULL) == -7.0, "dt->f64 [0]=-7");
    OK(smaug_f64_is_null(df, 2),           "dt->f64 preserva null [2]");

    smaug_i64_free(i); smaug_f64_free(f); smaug_dt_free(d); smaug_f64_free(df);
}

/* ---------- Dirigido: exatidao acima de 2^53 (o conserto) ---------- */
static void test_exatidao_2e53(void) {
    /* dt -> i64: epoch_ms grande deve sair EXATO (get nativo int64);
       elemento nulo deve propagar (cobre o ramo null do SMAUG_VALID). */
    smaug_series_dt_t *d = smaug_dt_create(2);
    smaug_dt_set(d, 0, TWO53_PLUS_1);
    smaug_dt_set_null(d, 1);
    smaug_series_i64_t *i = smaug_dt_to_i64(d);
    OK(i != NULL, "dt->i64 retorna serie");
    OK(smaug_i64_get(i, 0, NULL) == TWO53_PLUS_1,
       "dt->i64 preserva 2^53+1 EXATO (nao 9007199254740992)");
    OK(smaug_i64_is_null(i, 1), "dt->i64 propaga null");

    /* i64 -> dt: ida e volta pelo mesmo valor grande, exato. */
    smaug_series_i64_t *big = smaug_i64_create(1);
    smaug_i64_set(big, 0, TWO53_PLUS_1);
    smaug_series_dt_t *dt2 = smaug_i64_to_dt(big);
    OK(smaug_dt_get(dt2, 0, NULL) == TWO53_PLUS_1,
       "i64->dt preserva 2^53+1 EXATO");

    smaug_dt_free(d); smaug_i64_free(i); smaug_i64_free(big); smaug_dt_free(dt2);
}

/* ---------- Dirigido: f64 -> i64 trunc + inconversiveis -> null ---------- */
static void test_f64_i64_edge(void) {
    smaug_series_f64_t *f = smaug_f64_create(8);
    smaug_f64_set(f, 0,  3.7);        /* -> 3  (trunc direcao zero)  */
    smaug_f64_set(f, 1, -3.7);        /* -> -3 (trunc direcao zero)  */
    smaug_f64_set(f, 2,  NAN);        /* -> null                     */
    smaug_f64_set(f, 3,  INFINITY);   /* -> null                     */
    smaug_f64_set(f, 4, -INFINITY);   /* -> null                     */
    smaug_f64_set(f, 5,  1e300);      /* -> null (fora do range i64) */
    smaug_f64_set(f, 6, -1e300);      /* -> null (fora do range i64) */
    smaug_f64_set_null(f, 7);         /* -> null (origem nula)       */

    smaug_series_i64_t *i = smaug_f64_to_i64(f);
    OK(i != NULL, "f64->i64 retorna serie");
    OK(smaug_i64_get(i, 0, NULL) ==  3, "f64->i64 3.7 -> 3");
    OK(smaug_i64_get(i, 1, NULL) == -3, "f64->i64 -3.7 -> -3");
    OK(smaug_i64_is_null(i, 2), "f64->i64 NaN -> null");
    OK(smaug_i64_is_null(i, 3), "f64->i64 +inf -> null");
    OK(smaug_i64_is_null(i, 4), "f64->i64 -inf -> null");
    OK(smaug_i64_is_null(i, 5), "f64->i64 1e300 -> null (fora do range)");
    OK(smaug_i64_is_null(i, 6), "f64->i64 -1e300 -> null (fora do range)");
    OK(smaug_i64_is_null(i, 7), "f64->i64 origem nula -> null");

    /* mesma politica no destino datetime */
    smaug_series_dt_t *d = smaug_f64_to_dt(f);
    OK(smaug_dt_get(d, 0, NULL) == 3, "f64->dt 3.7 -> 3 epoch");
    OK(smaug_dt_is_null(d, 2), "f64->dt NaN -> null");
    OK(smaug_dt_is_null(d, 5), "f64->dt 1e300 -> null (fora do range)");

    smaug_f64_free(f); smaug_i64_free(i); smaug_dt_free(d);
}

/* ---------- Contrato: self==NULL -> NULL ---------- */
static void test_guard_null(void) {
    OK(smaug_i64_to_f64(NULL) == NULL, "i64->f64 guard self==NULL");
    OK(smaug_f64_to_i64(NULL) == NULL, "f64->i64 guard self==NULL");
    OK(smaug_i64_to_dt (NULL) == NULL, "i64->dt guard self==NULL");
    OK(smaug_dt_to_i64 (NULL) == NULL, "dt->i64 guard self==NULL");
    OK(smaug_f64_to_dt (NULL) == NULL, "f64->dt guard self==NULL");
    OK(smaug_dt_to_f64 (NULL) == NULL, "dt->f64 guard self==NULL");
}

int main(void) {
    test_grupo_a_basico();
    test_exatidao_2e53();
    test_f64_i64_edge();
    test_guard_null();
    printf("PASS: astype Grupo A (%d checks)\n", n_checks);
    return 0;
}
