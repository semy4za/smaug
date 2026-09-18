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

/* Verificação que NÃO some sob -DNDEBUG (ver nota em test_cow.c): redefine
   assert como checagem ativa com contador, sem reescrever cada chamada. */
#undef assert
static int passed_checks = 0;
#define assert(condition) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU [%s:%d]: %s\n", __FILE__, __LINE__, #condition); \
    exit(1); } passed_checks++; } while (0)

#define TEST_VALID_MASK 0xFF
#define TEST_NULL_MASK 0x00

/* ======================================================================
   FASE 8 / categoria C — tabela-verdade Kleene COMPLETA.
   O vetor de 4 do main cobre T·F/F·T/NA·T/T·NA, mas deixa de fora os ramos
   av/bv onde NA é assimétrico: no AND, false domina (F·NA=F, NA·F=F); no OR,
   true domina (T·NA=T, NA·T=T); além de T·T, F·F e NA·NA. Aqui varremos as 9
   combinações {T,F,NA}^2 e fixamos a semântica inteira.
   ====================================================================== */
static void kleene_full_table(void) {
    /* idx:    0(TT) 1(TF) 2(T·NA) 3(FT) 4(FF) 5(F·NA) 6(NA·T) 7(NA·F) 8(NA·NA) */
    uint8_t      left_values[9] = { 1, 1, 1,  0, 0, 0,  1,  0,  1 };
    smaug_mask_t left_null_mask[9] = { TEST_VALID_MASK, TEST_VALID_MASK, TEST_VALID_MASK,  TEST_VALID_MASK, TEST_VALID_MASK, TEST_VALID_MASK,  TEST_NULL_MASK,  TEST_NULL_MASK,  TEST_NULL_MASK };
    uint8_t      right_values[9] = { 1, 0, 1,  1, 0, 1,  1,  0,  1 };
    smaug_mask_t right_null_mask[9] = { TEST_VALID_MASK, TEST_VALID_MASK, TEST_NULL_MASK,  TEST_VALID_MASK, TEST_VALID_MASK, TEST_NULL_MASK,  TEST_VALID_MASK,  TEST_VALID_MASK,  TEST_NULL_MASK };
    smaug_mask_t *result_null_mask = NULL;
    uint8_t *result;

    /* AND: false domina (até sobre NA) */
    result = smaug_bool_and(left_values, left_null_mask, right_values, right_null_mask, 9, &result_null_mask);
    assert(result[0] == 1 && result_null_mask[0] == TEST_VALID_MASK);   /* T·T   = T  */
    assert(result[1] == 0 && result_null_mask[1] == TEST_VALID_MASK);   /* T·F   = F  */
    assert(result_null_mask[2] == TEST_NULL_MASK);                /* T·NA  = NA */
    assert(result[3] == 0 && result_null_mask[3] == TEST_VALID_MASK);   /* F·T   = F  */
    assert(result[4] == 0 && result_null_mask[4] == TEST_VALID_MASK);   /* F·F   = F  */
    assert(result[5] == 0 && result_null_mask[5] == TEST_VALID_MASK);   /* F·NA  = F   (false domina NA) */
    assert(result_null_mask[6] == TEST_NULL_MASK);                /* NA·T  = NA */
    assert(result[7] == 0 && result_null_mask[7] == TEST_VALID_MASK);   /* NA·F  = F   (false domina NA) */
    assert(result_null_mask[8] == TEST_NULL_MASK);                /* NA·NA = NA */
    free(result); free(result_null_mask); result_null_mask = NULL;

    /* OR: true domina (até sobre NA) */
    result = smaug_bool_or(left_values, left_null_mask, right_values, right_null_mask, 9, &result_null_mask);
    assert(result[0] == 1 && result_null_mask[0] == TEST_VALID_MASK);   /* T·T   = T  */
    assert(result[1] == 1 && result_null_mask[1] == TEST_VALID_MASK);   /* T·F   = T  */
    assert(result[2] == 1 && result_null_mask[2] == TEST_VALID_MASK);   /* T·NA  = T   (true domina NA) */
    assert(result[3] == 1 && result_null_mask[3] == TEST_VALID_MASK);   /* F·T   = T  */
    assert(result[4] == 0 && result_null_mask[4] == TEST_VALID_MASK);   /* F·F   = F  */
    assert(result_null_mask[5] == TEST_NULL_MASK);                /* F·NA  = NA */
    assert(result[6] == 1 && result_null_mask[6] == TEST_VALID_MASK);   /* NA·T  = T   (true domina NA) */
    assert(result_null_mask[7] == TEST_NULL_MASK);                /* NA·F  = NA */
    assert(result_null_mask[8] == TEST_NULL_MASK);                /* NA·NA = NA */
    free(result); free(result_null_mask); result_null_mask = NULL;

    /* XOR: ambos válidos -> a^b ; qualquer NA -> NA */
    result = smaug_bool_xor(left_values, left_null_mask, right_values, right_null_mask, 9, &result_null_mask);
    assert(result[0] == 0 && result_null_mask[0] == TEST_VALID_MASK);   /* T^T = F */
    assert(result[1] == 1 && result_null_mask[1] == TEST_VALID_MASK);   /* T^F = T */
    assert(result_null_mask[2] == TEST_NULL_MASK);                /* T·NA = NA */
    assert(result[3] == 1 && result_null_mask[3] == TEST_VALID_MASK);   /* F^T = T */
    assert(result[4] == 0 && result_null_mask[4] == TEST_VALID_MASK);   /* F^F = F */
    assert(result_null_mask[5] == TEST_NULL_MASK && result_null_mask[6] == TEST_NULL_MASK && result_null_mask[7] == TEST_NULL_MASK && result_null_mask[8] == TEST_NULL_MASK); /* qualquer NA = NA */
    free(result); free(result_null_mask); result_null_mask = NULL;

    /* NOT: !válido ; NA -> NA.  a = [T, F, NA] */
    {
        uint8_t      negated_values[3] = { 1, 0, 1 };
        smaug_mask_t negated_null_mask[3] = { TEST_VALID_MASK, TEST_VALID_MASK, TEST_NULL_MASK };
        result = smaug_bool_not(negated_values, negated_null_mask, 3, &result_null_mask);
        assert(result[0] == 0 && result_null_mask[0] == TEST_VALID_MASK);   /* !T  = F  */
        assert(result[1] == 1 && result_null_mask[1] == TEST_VALID_MASK);   /* !F  = T  */
        assert(result_null_mask[2] == TEST_NULL_MASK);                /* !NA = NA */
        free(result); free(result_null_mask); result_null_mask = NULL;
    }
}

/* ======================================================================
   FASE 8 / frente A1 (bool) — varredura de input inválido no booleano.
   Guards que C2/vetor-de-4 não tocam: !a||!b em and/or/xor (as 2 sub-condições
   do ||), !a em not/count_true/any/all, e os caminhos vacuamente-seguros das
   agregações (any sem true -> false; all(n=0) -> true).
   ====================================================================== */
static void bool_guard_sweep(void) {
    uint8_t      source_values[2] = { 1, 0 };
    smaug_mask_t source_null_mask[2] = { TEST_VALID_MASK, TEST_VALID_MASK };
    smaug_mask_t *result_null_mask = NULL;

    /* and/or/xor: NULL em qualquer operando -> NULL (cobre !a e !b) */
    assert(smaug_bool_and(NULL, source_null_mask, source_values, source_null_mask, 2, &result_null_mask) == NULL);
    assert(smaug_bool_and(source_values, source_null_mask, NULL, source_null_mask, 2, &result_null_mask) == NULL);
    assert(smaug_bool_or (NULL, source_null_mask, source_values, source_null_mask, 2, &result_null_mask) == NULL);
    assert(smaug_bool_or (source_values, source_null_mask, NULL, source_null_mask, 2, &result_null_mask) == NULL);
    assert(smaug_bool_xor(NULL, source_null_mask, source_values, source_null_mask, 2, &result_null_mask) == NULL);
    assert(smaug_bool_xor(source_values, source_null_mask, NULL, source_null_mask, 2, &result_null_mask) == NULL);
    assert(smaug_bool_not(NULL, source_null_mask, 2, &result_null_mask) == NULL);

    /* agregações com série NULL -> resultado vacuamente seguro */
    assert(smaug_bool_count_true(NULL, source_null_mask, 2) == 0);
    assert(smaug_bool_any(NULL, source_null_mask, 2) == false);
    assert(smaug_bool_all(NULL, source_null_mask, 2) == true);

    /* any sem nenhum true (false/NA) -> false; all(n=0) -> true; NA não conta */
    uint8_t      source_values_2[3] = { 0, 0, 0 };
    smaug_mask_t source_values_3[3] = { TEST_VALID_MASK, TEST_NULL_MASK, TEST_VALID_MASK };
    assert(smaug_bool_any(source_values_2, source_values_3, 3) == false);
    assert(smaug_bool_all(source_values_2, source_values_3, 0) == true);
    assert(smaug_bool_count_true(source_values_2, source_values_3, 3) == 0);

    /* out_mask = NULL: caller não quer a máscara de volta (cobre if(out_mask)/if(m) falso) */
    uint8_t      source_values_4[2] = { 1, 1 }, source_values_5[2] = { 1, 0 };
    smaug_mask_t source_values_6[2] = { TEST_VALID_MASK, TEST_VALID_MASK };
    uint8_t *result;
    result = smaug_bool_and(source_values_4, source_values_6, source_values_5, source_values_6, 2, NULL); assert(result && result[0] == 1 && result[1] == 0); free(result);
    result = smaug_bool_or (source_values_4, source_values_6, source_values_5, source_values_6, 2, NULL); assert(result && result[0] == 1 && result[1] == 1); free(result);
    result = smaug_bool_xor(source_values_4, source_values_6, source_values_5, source_values_6, 2, NULL); assert(result && result[0] == 0 && result[1] == 1); free(result);
    result = smaug_bool_not(source_values_4, source_values_6, 2, NULL);         assert(result && result[0] == 0 && result[1] == 0); free(result);
}

/* ======================================================================
   FASE 8 / frente A1 (bool) — ramos que o sweep de NULL existente não pega.
   Os guards `!a`/`!b` já estão cobertos (and/or/xor/not/count/any/all com NULL).
   Faltavam: (1) máscara NULL = "tudo válido", que exercita o ramo (m==NULL) do
   VALID em and/or/xor/not; (2) any() que varre tudo sem achar true -> false.
   (O ramo at&&bt-falso na linha do put do AND é inalcançável: vai pra exclusão.)
   ====================================================================== */
static void bool_extra_branches(void) {
    uint8_t left_values[2] = { 1, 0 };   /* T, F */
    uint8_t right_values[2] = { 1, 1 };   /* T, T */
    smaug_mask_t *result_null_mask = NULL;
    uint8_t *result;

    /* máscara NULL (todos válidos) -> exercita VALID(NULL,i) em cada op binária/not */
    result = smaug_bool_and(left_values, NULL, right_values, NULL, 2, &result_null_mask); assert(result && result[0] == 1 && result[1] == 0); free(result); free(result_null_mask); result_null_mask = NULL;
    result = smaug_bool_or (left_values, NULL, right_values, NULL, 2, &result_null_mask); assert(result && result[0] == 1 && result[1] == 1); free(result); free(result_null_mask); result_null_mask = NULL;
    result = smaug_bool_xor(left_values, NULL, right_values, NULL, 2, &result_null_mask); assert(result && result[0] == 0 && result[1] == 1); free(result); free(result_null_mask); result_null_mask = NULL;
    result = smaug_bool_not(left_values, NULL, 2, &result_null_mask);          assert(result && result[0] == 0 && result[1] == 1); free(result); free(result_null_mask); result_null_mask = NULL;

    /* any() percorrendo tudo sem achar true -> false (complemento da linha de early-return) */
    {
        uint8_t      source_values[2] = { 0, 0 };           /* F, F */
        smaug_mask_t source_values_2[2] = { TEST_NULL_MASK, TEST_NULL_MASK };           /* NA, NA */
        assert(smaug_bool_any(source_values, NULL, 2) == false);   /* todos false */
        assert(smaug_bool_any(source_values, source_values_2, 2)   == false);   /* todos NA (ignorados) */
    }
}

int main(void) {
    kleene_full_table();
    bool_extra_branches();
    bool_guard_sweep();
    /* a = [T, F, NA, T] ; b = [F, T, T, NA] */
    uint8_t      left_values[4] = { 1, 0, 0, 1 };
    smaug_mask_t left_null_mask[4] = { TEST_VALID_MASK, TEST_VALID_MASK, TEST_NULL_MASK, TEST_VALID_MASK };
    uint8_t      right_values[4] = { 0, 1, 1, 0 };
    smaug_mask_t right_null_mask[4] = { TEST_VALID_MASK, TEST_VALID_MASK, TEST_VALID_MASK, TEST_NULL_MASK };

    smaug_mask_t *result_null_mask = NULL;
    uint8_t      *result;

    /* AND (Kleene):
       T&F=F ; F&T=F ; NA&T=NA ; T&NA=NA */
    result = smaug_bool_and(left_values, left_null_mask, right_values, right_null_mask, 4, &result_null_mask);
    assert(result[0] == 0 && result_null_mask[0] == TEST_VALID_MASK);   /* F  */
    assert(result[1] == 0 && result_null_mask[1] == TEST_VALID_MASK);   /* F  */
    assert(result_null_mask[2] == TEST_NULL_MASK);                /* NA */
    assert(result_null_mask[3] == TEST_NULL_MASK);                /* NA */
    free(result); free(result_null_mask); result_null_mask = NULL;

    /* OR (Kleene):
       T|F=T ; F|T=T ; NA|T=T ; T|NA=T */
    result = smaug_bool_or(left_values, left_null_mask, right_values, right_null_mask, 4, &result_null_mask);
    assert(result[0] == 1 && result_null_mask[0] == TEST_VALID_MASK);   /* T  */
    assert(result[1] == 1 && result_null_mask[1] == TEST_VALID_MASK);   /* T  */
    assert(result[2] == 1 && result_null_mask[2] == TEST_VALID_MASK);   /* NA|T = T */
    assert(result[3] == 1 && result_null_mask[3] == TEST_VALID_MASK);   /* T|NA = T */
    free(result); free(result_null_mask); result_null_mask = NULL;

    /* XOR: qualquer NA -> NA */
    result = smaug_bool_xor(left_values, left_null_mask, right_values, right_null_mask, 4, &result_null_mask);
    assert(result[0] == 1 && result_null_mask[0] == TEST_VALID_MASK);   /* T^F = T */
    assert(result[1] == 1 && result_null_mask[1] == TEST_VALID_MASK);   /* F^T = T */
    assert(result_null_mask[2] == TEST_NULL_MASK && result_null_mask[3] == TEST_NULL_MASK);  /* NA    */
    free(result); free(result_null_mask); result_null_mask = NULL;

    /* NOT: NOT NA = NA */
    result = smaug_bool_not(left_values, left_null_mask, 4, &result_null_mask);
    assert(result[0] == 0 && result_null_mask[0] == TEST_VALID_MASK);   /* !T = F */
    assert(result[1] == 1 && result_null_mask[1] == TEST_VALID_MASK);   /* !F = T */
    assert(result_null_mask[2] == TEST_NULL_MASK);                /* NA     */
    assert(result[3] == 0 && result_null_mask[3] == TEST_VALID_MASK);   /* !T = F */
    free(result); free(result_null_mask); result_null_mask = NULL;

    /* Agregações (NA ignorado). a = [T,F,NA,T] -> 2 trues */
    assert(smaug_bool_count_true(left_values, left_null_mask, 4) == 2);
    assert(smaug_bool_any(left_values, left_null_mask, 4) == true);
    assert(smaug_bool_all(left_values, left_null_mask, 4) == false);   /* há um F */

    /* all() ignorando NA: [T, NA, T] -> true */
    uint8_t      source_values[3] = { 1, 0, 1 };
    smaug_mask_t comparison_null_mask[3] = { TEST_VALID_MASK, TEST_NULL_MASK, TEST_VALID_MASK };
    assert(smaug_bool_all(source_values, comparison_null_mask, 3) == true);
    assert(smaug_bool_count_true(source_values, comparison_null_mask, 3) == 2);

    /* NULL mask = todos válidos */
    uint8_t double_value[3] = { 1, 1, 0 };
    assert(smaug_bool_count_true(double_value, NULL, 3) == 2);
    assert(smaug_bool_all(double_value, NULL, 3) == false);

    printf("PASS: bool (%d checks)\n", passed_checks);
    return 0;
}
