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

#include "../include/smaug_math.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

/* ===================================================================
   create / invariantes
   =================================================================== */
static void test_create_defaults(void) {
    smaug_series_f64_t *s = smaug_f64_create(10);
    assert(s != NULL);
    assert(s->size == 10);
    assert(s->capacity == 10);          /* create: size == capacity */
    assert(s->meta.is_view == false);
    assert(s->meta.external_alloc == false);

    /* create() nasce com todos os elementos NULL */
    for (size_t i = 0; i < 10; i++) {
        assert(smaug_f64_is_null(s, i));
    }
    assert(smaug_f64_count_nonnull(s) == 0);

    smaug_f64_free(s);
}

static void test_create_with_capacity(void) {
    /* capacity > size: pré-aloca para append sem realloc imediato */
    smaug_series_f64_t *s = smaug_f64_create_with_capacity(2, 8);
    assert(s != NULL);
    assert(s->size == 2);
    assert(s->capacity == 8);

    /* size > capacity é inválido */
    assert(smaug_f64_create_with_capacity(9, 4) == NULL);

    /* capacity 0 é válido (série vazia, data/null_mask NULL) */
    smaug_series_f64_t *empty = smaug_f64_create_with_capacity(0, 0);
    assert(empty != NULL);
    assert(empty->size == 0);

    smaug_f64_free(s);
    smaug_f64_free(empty);
}

static void test_create_from_array(void) {
    double arr[4] = {1.5, 2.5, 3.5, 4.5};
    smaug_series_f64_t *s = smaug_f64_create_from_array(arr, 4);
    assert(s != NULL);
    assert(s->size == 4);
    /* from_array marca tudo como VÁLIDO (ao contrário de create) */
    assert(smaug_f64_count_nonnull(s) == 4);
    assert(smaug_f64_get(s, 0) == 1.5);
    assert(smaug_f64_get(s, 3) == 4.5);

    assert(smaug_f64_create_from_array(NULL, 4) == NULL);  /* NULL safe */

    smaug_f64_free(s);
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
    smaug_series_f64_t *s = smaug_f64_create(3);
    smaug_f64_set(s, 0, 10.0);
    smaug_f64_set(s, 1, 20.0);
    smaug_f64_set_null(s, 2);

    smaug_series_f64_t *c = smaug_f64_clone(s);
    assert(c != NULL);
    assert(c->size == s->size);
    assert(c->meta.is_view == false);
    assert(c->meta.external_alloc == false);
    assert(c->data != s->data);            /* buffers independentes */

    /* mutar o clone não afeta o original */
    smaug_f64_set(c, 0, 999.0);
    assert(smaug_f64_get(s, 0) == 10.0);
    assert(smaug_f64_get(c, 0) == 999.0);

    /* o estado de null foi copiado */
    assert(smaug_f64_is_null(c, 2));

    assert(smaug_f64_clone(NULL) == NULL);

    smaug_f64_free(s);
    smaug_f64_free(c);
}

/* ===================================================================
   view: zero-copy, aliasing, read-only, external_alloc
   =================================================================== */
static void test_view_aliasing(void) {
    smaug_series_f64_t *s = smaug_f64_create(5);
    for (size_t i = 0; i < 5; i++) smaug_f64_set(s, i, (double)i);

    smaug_series_f64_t *v = smaug_f64_view(s, 1, 3);  /* [1,2,3] */
    assert(v != NULL);
    assert(v->size == 3);
    assert(v->meta.is_view == true);
    assert(v->meta.external_alloc == true);
    assert(v->data == s->data + 1);        /* aponta para dentro da pai */

    /* mutar a pai reflete na view (mesma memória) */
    smaug_f64_set(s, 1, 100.0);
    assert(smaug_f64_get(v, 0) == 100.0);

    /* view é read-only: append falha */
    assert(smaug_f64_append(v, 7.0) == -1);

    /* out of bounds → NULL */
    assert(smaug_f64_view(s, 3, 5) == NULL);

    /* liberar a view NÃO libera os dados da pai (external_alloc) */
    smaug_f64_free(v);
    assert(smaug_f64_get(s, 1) == 100.0);  /* pai ainda válida */

    smaug_f64_free(s);
}

/* ===================================================================
   append / grow: exercita o caminho de realloc
   =================================================================== */
static void test_append_grow(void) {
    /* começa vazia (capacity 0) e força várias expansões */
    smaug_series_f64_t *s = smaug_f64_create_with_capacity(0, 0);
    assert(s != NULL);

    const size_t N = 100;
    for (size_t i = 0; i < N; i++) {
        assert(smaug_f64_append(s, (double)i) == 0);
    }
    assert(s->size == N);
    assert(s->capacity >= N);              /* invariante: capacity >= size */
    assert(smaug_f64_count_nonnull(s) == N);
    assert(smaug_f64_get(s, 0) == 0.0);
    assert(smaug_f64_get(s, N - 1) == (double)(N - 1));

    /* append_null intercalado */
    assert(smaug_f64_append_null(s) == 0);
    assert(s->size == N + 1);
    assert(smaug_f64_is_null(s, N));
    assert(smaug_f64_count_nonnull(s) == N);

    smaug_f64_free(s);
}

/* ===================================================================
   i64: cobertura mínima de paridade (lifecycle + grow)
   =================================================================== */
static void test_i64_lifecycle(void) {
    smaug_series_i64_t *s = smaug_i64_create_with_capacity(0, 0);
    assert(s != NULL);
    for (int64_t i = 0; i < 50; i++) {
        assert(smaug_i64_append(s, i) == 0);
    }
    assert(s->size == 50);
    assert(s->capacity >= 50);

    smaug_series_i64_t *c = smaug_i64_clone(s);
    assert(c != NULL && c->data != s->data);
    smaug_i64_set(c, 0, -1);
    assert(smaug_i64_get(s, 0) == 0);      /* original intacto */

    smaug_series_i64_t *v = smaug_i64_view(s, 10, 5);
    assert(v != NULL && v->meta.external_alloc == true);
    assert(smaug_i64_append(v, 1) == -1);  /* view read-only */

    smaug_i64_free(v);
    smaug_i64_free(c);
    smaug_i64_free(s);
}

int main(void) {
    test_create_defaults();
    test_create_with_capacity();
    test_create_from_array();
    test_free_null_safe();
    test_clone_independence();
    test_view_aliasing();
    test_append_grow();
    test_i64_lifecycle();

    printf("PASS\n");
    return 0;
}
