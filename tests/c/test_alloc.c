/* tests/test_alloc.c
 *
 * Testes de lifecycle e gerenciamento de memória do backend C.
 * Cobre: create/create_with_capacity/create_from_array, free (idempotente e
 * external_alloc), clone (independência), view (aliasing + read-only),
 * append/append_null (incluindo o caminho de grow), e os invariantes de
 * size/capacity.
 *
 * Compilar e rodar sob Valgrind:
 *   gcc -std=c11 -g -O0 -I./include \
 *       tests/test_alloc.c src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c \
 *       -lm -o build/test_alloc
 *   valgrind --leak-check=full --error-exitcode=1 ./build/test_alloc
 */

#include "../include/smaug.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

/* Verificação que NÃO some sob -DNDEBUG (ver nota em test_cow.c): redefine
   assert como checagem ativa com contador, sem reescrever cada chamada. */
#undef assert
static int passed_checks = 0;
#define assert(condition) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU [%s:%d]: %s\n", __FILE__, __LINE__, #condition); \
    exit(1); } passed_checks++; } while (0)

/* ===================================================================
   create / invariantes
   =================================================================== */
static void test_create_defaults(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(10);
    assert(floating_point_series != NULL);
    assert(floating_point_series->size == 10);
    assert(floating_point_series->capacity == 10);          /* create: size == capacity */
    assert(floating_point_series->meta.is_view == false);
    assert(floating_point_series->meta.external_alloc == false);

    /* create() nasce com todos os elementos NULL */
    for (size_t row_index = 0; row_index < 10; row_index++) {
        assert(smaug_f64_is_null(floating_point_series, row_index));
    }
    assert(smaug_f64_count_nonnull(floating_point_series) == 0);

    smaug_f64_free(floating_point_series);
}

static void test_create_with_capacity(void) {
    /* capacity > size: pré-aloca para append sem realloc imediato */
    smaug_series_f64_t *floating_point_series = smaug_f64_create_with_capacity(2, 8);
    assert(floating_point_series != NULL);
    assert(floating_point_series->size == 2);
    assert(floating_point_series->capacity == 8);

    /* size > capacity é inválido */
    assert(smaug_f64_create_with_capacity(9, 4) == NULL);

    /* capacity 0 é válido (série vazia, data/null_mask NULL) */
    smaug_series_f64_t *empty = smaug_f64_create_with_capacity(0, 0);
    assert(empty != NULL);
    assert(empty->size == 0);

    smaug_f64_free(floating_point_series);
    smaug_f64_free(empty);
}

static void test_create_from_array(void) {
    double source_values[4] = {1.5, 2.5, 3.5, 4.5};
    smaug_series_f64_t *floating_point_series = smaug_f64_create_from_array(source_values, 4);
    assert(floating_point_series != NULL);
    assert(floating_point_series->size == 4);
    /* from_array marca tudo como VÁLIDO (ao contrário de create) */
    assert(smaug_f64_count_nonnull(floating_point_series) == 4);
    assert(smaug_f64_get(floating_point_series, 0, NULL) == 1.5);
    assert(smaug_f64_get(floating_point_series, 3, NULL) == 4.5);

    assert(smaug_f64_create_from_array(NULL, 4) == NULL);  /* NULL safe */

    /* 12.21: count_nonfinite — quantos valores nao-nulos sao NaN/±inf.
       Serve ao Anel 3 para avisar quando o formato nao os comporta (JSON). */
    assert(smaug_f64_count_nonfinite(floating_point_series) == 0);          /* todos finitos */
    smaug_f64_set(floating_point_series, 0, 0.0/0.0);                       /* NaN */
    smaug_f64_set(floating_point_series, 1, 1.0/0.0);                       /* +inf */
    smaug_f64_set(floating_point_series, 2, -1.0/0.0);                      /* -inf */
    assert(smaug_f64_count_nonfinite(floating_point_series) == 3);
    smaug_f64_set_null(floating_point_series, 0);                           /* NaN vira ausencia */
    assert(smaug_f64_count_nonfinite(floating_point_series) == 2);          /* nulo nao conta */
    assert(smaug_f64_count_nonfinite(NULL) == 0);       /* NULL safe */

    smaug_f64_free(floating_point_series);
}

/* ===================================================================
   free: idempotência e NULL-safety
   =================================================================== */
static void test_free_null_safe(void) {
    smaug_f64_free(NULL);   /* não deve crashar */
    smaug_i64_free(NULL);
}

/* ===================================================================
   clone: deep copy independente
   =================================================================== */
static void test_clone_independence(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(3);
    smaug_f64_set(floating_point_series, 0, 10.0);
    smaug_f64_set(floating_point_series, 1, 20.0);
    smaug_f64_set_null(floating_point_series, 2);

    smaug_series_f64_t *cloned_series = smaug_f64_clone(floating_point_series);
    assert(cloned_series != NULL);
    assert(cloned_series->size == floating_point_series->size);
    assert(cloned_series->meta.is_view == false);
    assert(cloned_series->meta.external_alloc == false);
    assert(cloned_series->data != floating_point_series->data);            /* buffers independentes */

    /* mutar o clone não afeta o original */
    smaug_f64_set(cloned_series, 0, 999.0);
    assert(smaug_f64_get(floating_point_series, 0, NULL) == 10.0);
    assert(smaug_f64_get(cloned_series, 0, NULL) == 999.0);

    /* o estado de null foi copiado */
    assert(smaug_f64_is_null(cloned_series, 2));

    assert(smaug_f64_clone(NULL) == NULL);

    smaug_f64_free(floating_point_series);
    smaug_f64_free(cloned_series);
}

/* ===================================================================
   view: zero-copy, aliasing, COW-writable, external_alloc
   =================================================================== */
static void test_view_aliasing(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(5);
    for (size_t row_index = 0; row_index < 5; row_index++) smaug_f64_set(floating_point_series, row_index, (double)row_index);

    smaug_series_f64_t *series_view = smaug_f64_view(floating_point_series, 1, 3);  /* [1,2,3] */
    assert(series_view != NULL);
    assert(series_view->size == 3);
    assert(series_view->meta.is_view == true);
    assert(series_view->meta.external_alloc == true);
    assert(series_view->data == floating_point_series->data + 1);        /* aponta para dentro da pai */

    /* mutar a pai reflete na view (mesma memória, ainda não desatada) */
    smaug_f64_set(floating_point_series, 1, 100.0);
    assert(smaug_f64_get(series_view, 0, NULL) == 100.0);

    /* COW: append destaca a view e adiciona o elemento; pai preservada */
    assert(smaug_f64_append(series_view, 7.0) == 0);
    assert(series_view->meta.is_view        == false);
    assert(series_view->meta.external_alloc == false);
    assert(series_view->size == 4);
    assert(smaug_f64_get(series_view, 3, NULL) == 7.0);
    assert(smaug_f64_get(floating_point_series, 1, NULL) == 100.0);   /* pai inalterada */

    /* out of bounds → NULL */
    assert(smaug_f64_view(floating_point_series, 3, 5) == NULL);

    /* liberar a view NÃO libera os dados da pai (agora private, não external) */
    smaug_f64_free(series_view);
    assert(smaug_f64_get(floating_point_series, 1, NULL) == 100.0);  /* pai ainda válida */

    smaug_f64_free(floating_point_series);
}

/* ===================================================================
   append / grow: exercita o caminho de realloc
   =================================================================== */
static void test_append_grow(void) {
    /* começa vazia (capacity 0) e força várias expansões */
    smaug_series_f64_t *floating_point_series = smaug_f64_create_with_capacity(0, 0);
    assert(floating_point_series != NULL);

    const size_t element_count = 100;
    for (size_t row_index = 0; row_index < element_count; row_index++) {
        assert(smaug_f64_append(floating_point_series, (double)row_index) == 0);
    }
    assert(floating_point_series->size == element_count);
    assert(floating_point_series->capacity >= element_count);              /* invariante: capacity >= size */
    assert(smaug_f64_count_nonnull(floating_point_series) == element_count);
    assert(smaug_f64_get(floating_point_series, 0, NULL) == 0.0);
    assert(smaug_f64_get(floating_point_series, element_count - 1, NULL) == (double)(element_count - 1));

    /* append_null intercalado */
    assert(smaug_f64_append_null(floating_point_series) == 0);
    assert(floating_point_series->size == element_count + 1);
    assert(smaug_f64_is_null(floating_point_series, element_count));
    assert(smaug_f64_count_nonnull(floating_point_series) == element_count);

    smaug_f64_free(floating_point_series);
}

/* ===================================================================
   i64: cobertura mínima de paridade (lifecycle + grow)
   =================================================================== */
static void test_int64_lifecycle(void) {
    smaug_series_i64_t *integer_series = smaug_i64_create_with_capacity(0, 0);
    assert(integer_series != NULL);
    for (int64_t row_index = 0; row_index < 50; row_index++) {
        assert(smaug_i64_append(integer_series, row_index) == 0);
    }
    assert(integer_series->size == 50);
    assert(integer_series->capacity >= 50);

    smaug_series_i64_t *cloned_series = smaug_i64_clone(integer_series);
    assert(cloned_series != NULL && cloned_series->data != integer_series->data);
    smaug_i64_set(cloned_series, 0, -1);
    assert(smaug_i64_get(integer_series, 0, NULL) == 0);      /* original intacto */

    smaug_series_i64_t *series_view = smaug_i64_view(integer_series, 10, 5);
    assert(series_view != NULL && series_view->meta.external_alloc == true);
    assert(smaug_i64_append(series_view, 1) == 0);       /* COW: destaca e adiciona */
    assert(series_view->meta.is_view == false);
    assert(series_view->size == 6);
    assert(smaug_i64_get(series_view, 5, NULL) == 1);
    assert(smaug_i64_get(integer_series, 10, NULL) == 10);  /* pai preservada */

    smaug_i64_free(series_view);
    smaug_i64_free(cloned_series);
    smaug_i64_free(integer_series);
}

/* ======================================================================
   FASE 8 / frente A1 (core) — varredura de input inválido no lifecycle.
   Cobre o que os testes de create, clone, view e append ainda nao pegavam: as 3
   sub-condições do guard de view (!s, start>size, len>size-start), append/
   append_null com serie NULL, clone/from_array NULL do i64, is_null(NULL/OOB)
   f64+i64, e clone de serie VAZIA (ramo size>0 falso). create_from_array(NULL)
   e clone(NULL) do f64, e create_with_capacity(size>cap), ja cobertos.
   ====================================================================== */
static void test_core_input_guards(void) {
    smaug_series_f64_t *floating_point_series  = smaug_f64_create(5);
    smaug_series_i64_t *integer_series = smaug_i64_create(5);

    /* view: as 3 sub-condicoes do guard (short-circuit evita underflow em start>size) */
    assert(smaug_f64_view(NULL, 0, 0) == NULL);
    assert(smaug_f64_view(floating_point_series, 99, 0)   == NULL);   /* start > size */
    assert(smaug_f64_view(floating_point_series, 0, 99)   == NULL);   /* len > size-start */
    assert(smaug_i64_view(NULL, 0, 0) == NULL);
    assert(smaug_i64_view(integer_series, 99, 0)  == NULL);
    assert(smaug_i64_view(integer_series, 0, 99)  == NULL);

    /* append / append_null: serie NULL -> -1 */
    assert(smaug_f64_append(NULL, 1.0) == -1);
    assert(smaug_f64_append_null(NULL) == -1);
    assert(smaug_i64_append(NULL, 1)   == -1);
    assert(smaug_i64_append_null(NULL) == -1);

    /* clone / from_array NULL (i64; f64 ja coberto) */
    assert(smaug_i64_clone(NULL) == NULL);
    assert(smaug_i64_create_from_array(NULL, 4) == NULL);

    /* is_null: serie NULL e OOB -> true */
    assert(smaug_f64_is_null(NULL, 0) == true);
    assert(smaug_f64_is_null(floating_point_series, 99)   == true);
    assert(smaug_i64_is_null(NULL, 0) == true);
    assert(smaug_i64_is_null(integer_series, 99)  == true);

    /* clone de serie VAZIA -> exercita o ramo (size>0) falso */
    smaug_series_f64_t *empty = smaug_f64_create_with_capacity(0, 0);
    smaug_series_f64_t *cloned_series    = smaug_f64_clone(empty);
    assert(cloned_series != NULL && cloned_series->size == 0);
    smaug_f64_free(empty); smaug_f64_free(cloned_series);

    /* simetria i64: create_with_capacity(size>cap), clone de vazia, append_null com crescimento */
    assert(smaug_i64_create_with_capacity(9, 4) == NULL);   /* size > capacity */
    smaug_series_i64_t *empty_integer_series = smaug_i64_create_with_capacity(0, 0);
    smaug_series_i64_t *cloned_series_2    = smaug_i64_clone(empty_integer_series);   /* clone vazia: ramo size>0 falso */
    assert(cloned_series_2 != NULL && cloned_series_2->size == 0);
    smaug_i64_free(empty_integer_series); smaug_i64_free(cloned_series_2);

    smaug_series_i64_t *integer_series_2 = smaug_i64_create(2);           /* size == capacity == 2 */
    assert(smaug_i64_append_null(integer_series_2) == 0);                 /* size>=capacity -> cresce */
    assert(integer_series_2->size == 3 && smaug_i64_is_null(integer_series_2, 2));
    smaug_i64_free(integer_series_2);

    smaug_f64_free(floating_point_series); smaug_i64_free(integer_series);
}

int main(void) {
    test_create_defaults();
    test_create_with_capacity();
    test_create_from_array();
    test_free_null_safe();
    test_clone_independence();
    test_view_aliasing();
    test_append_grow();
    test_int64_lifecycle();
    test_core_input_guards();

    printf("PASS: alloc (%d checks)\n", passed_checks);
    return 0;
}
