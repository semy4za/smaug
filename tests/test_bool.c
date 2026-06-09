/* tests/test_bool.c
 *
 * Testa o backend booleano (smaug_ops_bool.c): lógica de três valores (Kleene)
 * em and/or/xor/not e as agregações count_true/any/all.
 *
 *   make test   (compila junto)   ou:
 *   gcc -std=c11 -g -O0 -I./include tests/test_bool.c src(...).c -lm -o build/test_bool
 *   valgrind --leak-check=full ./build/test_bool
 */

#include "../include/smaug.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

#define V 0xFF
#define N 0x00

/* ======================================================================
   FASE 8 / categoria C — tabela-verdade Kleene COMPLETA.
   O vetor de 4 do main cobre T·F/F·T/NA·T/T·NA, mas deixa de fora os ramos
   av/bv onde NA é assimétrico: no AND, false domina (F·NA=F, NA·F=F); no OR,
   true domina (T·NA=T, NA·T=T); além de T·T, F·F e NA·NA. Aqui varremos as 9
   combinações {T,F,NA}^2 e fixamos a semântica inteira.
   ====================================================================== */
static void kleene_full_table(void) {
    /* idx:    0(TT) 1(TF) 2(T·NA) 3(FT) 4(FF) 5(F·NA) 6(NA·T) 7(NA·F) 8(NA·NA) */
    uint8_t      av[9] = { 1, 1, 1,  0, 0, 0,  1,  0,  1 };
    smaug_mask_t am[9] = { V, V, V,  V, V, V,  N,  N,  N };
    uint8_t      bv[9] = { 1, 0, 1,  1, 0, 1,  1,  0,  1 };
    smaug_mask_t bm[9] = { V, V, N,  V, V, N,  V,  V,  N };
    smaug_mask_t *om = NULL;
    uint8_t *r;

    /* AND: false domina (até sobre NA) */
    r = smaug_bool_and(av, am, bv, bm, 9, &om);
    assert(r[0] == 1 && om[0] == V);   /* T·T   = T  */
    assert(r[1] == 0 && om[1] == V);   /* T·F   = F  */
    assert(om[2] == N);                /* T·NA  = NA */
    assert(r[3] == 0 && om[3] == V);   /* F·T   = F  */
    assert(r[4] == 0 && om[4] == V);   /* F·F   = F  */
    assert(r[5] == 0 && om[5] == V);   /* F·NA  = F   (false domina NA) */
    assert(om[6] == N);                /* NA·T  = NA */
    assert(r[7] == 0 && om[7] == V);   /* NA·F  = F   (false domina NA) */
    assert(om[8] == N);                /* NA·NA = NA */
    free(r); free(om); om = NULL;

    /* OR: true domina (até sobre NA) */
    r = smaug_bool_or(av, am, bv, bm, 9, &om);
    assert(r[0] == 1 && om[0] == V);   /* T·T   = T  */
    assert(r[1] == 1 && om[1] == V);   /* T·F   = T  */
    assert(r[2] == 1 && om[2] == V);   /* T·NA  = T   (true domina NA) */
    assert(r[3] == 1 && om[3] == V);   /* F·T   = T  */
    assert(r[4] == 0 && om[4] == V);   /* F·F   = F  */
    assert(om[5] == N);                /* F·NA  = NA */
    assert(r[6] == 1 && om[6] == V);   /* NA·T  = T   (true domina NA) */
    assert(om[7] == N);                /* NA·F  = NA */
    assert(om[8] == N);                /* NA·NA = NA */
    free(r); free(om); om = NULL;

    /* XOR: ambos válidos -> a^b ; qualquer NA -> NA */
    r = smaug_bool_xor(av, am, bv, bm, 9, &om);
    assert(r[0] == 0 && om[0] == V);   /* T^T = F */
    assert(r[1] == 1 && om[1] == V);   /* T^F = T */
    assert(om[2] == N);                /* T·NA = NA */
    assert(r[3] == 1 && om[3] == V);   /* F^T = T */
    assert(r[4] == 0 && om[4] == V);   /* F^F = F */
    assert(om[5] == N && om[6] == N && om[7] == N && om[8] == N); /* qualquer NA = NA */
    free(r); free(om); om = NULL;

    /* NOT: !válido ; NA -> NA.  a = [T, F, NA] */
    {
        uint8_t      nv[3] = { 1, 0, 1 };
        smaug_mask_t nm[3] = { V, V, N };
        r = smaug_bool_not(nv, nm, 3, &om);
        assert(r[0] == 0 && om[0] == V);   /* !T  = F  */
        assert(r[1] == 1 && om[1] == V);   /* !F  = T  */
        assert(om[2] == N);                /* !NA = NA */
        free(r); free(om); om = NULL;
    }
}

/* ======================================================================
   FASE 8 / frente A1 (bool) — varredura de input inválido no booleano.
   Guards que C2/vetor-de-4 não tocam: !a||!b em and/or/xor (as 2 sub-condições
   do ||), !a em not/count_true/any/all, e os caminhos vacuamente-seguros das
   agregações (any sem true -> false; all(n=0) -> true).
   ====================================================================== */
static void bool_guard_sweep(void) {
    uint8_t      v[2] = { 1, 0 };
    smaug_mask_t m[2] = { V, V };
    smaug_mask_t *om = NULL;

    /* and/or/xor: NULL em qualquer operando -> NULL (cobre !a e !b) */
    assert(smaug_bool_and(NULL, m, v, m, 2, &om) == NULL);
    assert(smaug_bool_and(v, m, NULL, m, 2, &om) == NULL);
    assert(smaug_bool_or (NULL, m, v, m, 2, &om) == NULL);
    assert(smaug_bool_or (v, m, NULL, m, 2, &om) == NULL);
    assert(smaug_bool_xor(NULL, m, v, m, 2, &om) == NULL);
    assert(smaug_bool_xor(v, m, NULL, m, 2, &om) == NULL);
    assert(smaug_bool_not(NULL, m, 2, &om) == NULL);

    /* agregações com série NULL -> resultado vacuamente seguro */
    assert(smaug_bool_count_true(NULL, m, 2) == 0);
    assert(smaug_bool_any(NULL, m, 2) == false);
    assert(smaug_bool_all(NULL, m, 2) == true);

    /* any sem nenhum true (false/NA) -> false; all(n=0) -> true; NA não conta */
    uint8_t      f3[3] = { 0, 0, 0 };
    smaug_mask_t fm[3] = { V, N, V };
    assert(smaug_bool_any(f3, fm, 3) == false);
    assert(smaug_bool_all(f3, fm, 0) == true);
    assert(smaug_bool_count_true(f3, fm, 3) == 0);

    /* out_mask = NULL: caller não quer a máscara de volta (cobre if(out_mask)/if(m) falso) */
    uint8_t      a2[2] = { 1, 1 }, b2[2] = { 1, 0 };
    smaug_mask_t mm[2] = { V, V };
    uint8_t *r;
    r = smaug_bool_and(a2, mm, b2, mm, 2, NULL); assert(r && r[0] == 1 && r[1] == 0); free(r);
    r = smaug_bool_or (a2, mm, b2, mm, 2, NULL); assert(r && r[0] == 1 && r[1] == 1); free(r);
    r = smaug_bool_xor(a2, mm, b2, mm, 2, NULL); assert(r && r[0] == 0 && r[1] == 1); free(r);
    r = smaug_bool_not(a2, mm, 2, NULL);         assert(r && r[0] == 0 && r[1] == 0); free(r);
}

/* ======================================================================
   FASE 8 / frente A1 (bool) — ramos que o sweep de NULL existente não pega.
   Os guards `!a`/`!b` já estão cobertos (and/or/xor/not/count/any/all com NULL).
   Faltavam: (1) máscara NULL = "tudo válido", que exercita o ramo (m==NULL) do
   VALID em and/or/xor/not; (2) any() que varre tudo sem achar true -> false.
   (O ramo at&&bt-falso na linha do put do AND é inalcançável: vai pra exclusão.)
   ====================================================================== */
static void bool_extra_branches(void) {
    uint8_t a[2] = { 1, 0 };   /* T, F */
    uint8_t b[2] = { 1, 1 };   /* T, T */
    smaug_mask_t *om = NULL;
    uint8_t *r;

    /* máscara NULL (todos válidos) -> exercita VALID(NULL,i) em cada op binária/not */
    r = smaug_bool_and(a, NULL, b, NULL, 2, &om); assert(r && r[0] == 1 && r[1] == 0); free(r); free(om); om = NULL;
    r = smaug_bool_or (a, NULL, b, NULL, 2, &om); assert(r && r[0] == 1 && r[1] == 1); free(r); free(om); om = NULL;
    r = smaug_bool_xor(a, NULL, b, NULL, 2, &om); assert(r && r[0] == 0 && r[1] == 1); free(r); free(om); om = NULL;
    r = smaug_bool_not(a, NULL, 2, &om);          assert(r && r[0] == 0 && r[1] == 1); free(r); free(om); om = NULL;

    /* any() percorrendo tudo sem achar true -> false (complemento da linha de early-return) */
    {
        uint8_t      ff[2] = { 0, 0 };           /* F, F */
        smaug_mask_t na[2] = { N, N };           /* NA, NA */
        assert(smaug_bool_any(ff, NULL, 2) == false);   /* todos false */
        assert(smaug_bool_any(ff, na, 2)   == false);   /* todos NA (ignorados) */
    }
}

int main(void) {
    kleene_full_table();
    bool_extra_branches();
    bool_guard_sweep();
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
