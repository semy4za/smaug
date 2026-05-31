/* tests/test_bool.c
 *
 * Testa o backend booleano (smaug_ops_bool.c): lógica de três valores (Kleene)
 * em and/or/xor/not e as agregações count_true/any/all.
 *
 *   make test   (compila junto)   ou:
 *   gcc -std=c11 -g -O0 -I./include tests/test_bool.c src/*.c -lm -o build/test_bool
 *   valgrind --leak-check=full ./build/test_bool
 */

#include "../include/smaug_math.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#define V 0xFF
#define N 0x00

int main(void) {
    /* a = [T, F, NA, T] ; b = [F, T, T, NA] */
    uint8_t      av[4] = { 1, 0, 0, 1 };
    smaug_mask_t am[4] = { V, V, N, V };
    uint8_t      bv[4] = { 0, 1, 1, 0 };
    smaug_mask_t bm[4] = { V, V, V, N };

    smaug_mask_t *om = NULL;
    uint8_t      *r;

    /* AND (Kleene):
       T&F=F ; F&T=F ; NA&T=NA ; T&NA=NA */
    r = smaug_bool_and(av, am, bv, bm, 4, &om);
    assert(r[0] == 0 && om[0] == V);   /* F  */
    assert(r[1] == 0 && om[1] == V);   /* F  */
    assert(om[2] == N);                /* NA */
    assert(om[3] == N);                /* NA */
    free(r); free(om); om = NULL;

    /* OR (Kleene):
       T|F=T ; F|T=T ; NA|T=T ; T|NA=T */
    r = smaug_bool_or(av, am, bv, bm, 4, &om);
    assert(r[0] == 1 && om[0] == V);   /* T  */
    assert(r[1] == 1 && om[1] == V);   /* T  */
    assert(r[2] == 1 && om[2] == V);   /* NA|T = T */
    assert(r[3] == 1 && om[3] == V);   /* T|NA = T */
    free(r); free(om); om = NULL;

    /* XOR: qualquer NA -> NA */
    r = smaug_bool_xor(av, am, bv, bm, 4, &om);
    assert(r[0] == 1 && om[0] == V);   /* T^F = T */
    assert(r[1] == 1 && om[1] == V);   /* F^T = T */
    assert(om[2] == N && om[3] == N);  /* NA    */
    free(r); free(om); om = NULL;

    /* NOT: NOT NA = NA */
    r = smaug_bool_not(av, am, 4, &om);
    assert(r[0] == 0 && om[0] == V);   /* !T = F */
    assert(r[1] == 1 && om[1] == V);   /* !F = T */
    assert(om[2] == N);                /* NA     */
    assert(r[3] == 0 && om[3] == V);   /* !T = F */
    free(r); free(om); om = NULL;

    /* Agregações (NA ignorado). a = [T,F,NA,T] -> 2 trues */
    assert(smaug_bool_count_true(av, am, 4) == 2);
    assert(smaug_bool_any(av, am, 4) == true);
    assert(smaug_bool_all(av, am, 4) == false);   /* há um F */

    /* all() ignorando NA: [T, NA, T] -> true */
    uint8_t      cv[3] = { 1, 0, 1 };
    smaug_mask_t cm[3] = { V, N, V };
    assert(smaug_bool_all(cv, cm, 3) == true);
    assert(smaug_bool_count_true(cv, cm, 3) == 2);

    /* NULL mask = todos válidos */
    uint8_t dv[3] = { 1, 1, 0 };
    assert(smaug_bool_count_true(dv, NULL, 3) == 2);
    assert(smaug_bool_all(dv, NULL, 3) == false);

    printf("PASS\n");
    return 0;
}
