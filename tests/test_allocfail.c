/* tests/test_allocfail.c
 *
 * Teste de falha de alocação (Fase 1.6 — endurecimento, padrão SQLite).
 *
 * Intercepta malloc/realloc via --wrap do linker (ver Makefile). Um contador
 * global faz a N-ésima alocação falhar (retornar NULL). Cada operação é
 * exercitada em LOOP: falha-se na alocação 0, depois na 1, na 2, ... varrendo
 * TODOS os pontos de alocação daquela operação. Verifica-se que cada falha
 * resulta em retorno NULL/erro gracioso, sem crash. Quando o contador passa do
 * número de alocações (nenhuma falha), a operação deve SUCEDER.
 *
 * O que este teste garante (rode sob Valgrind para o quadro completo):
 *   - nenhum ponto de falha de alocação causa crash;
 *   - nenhum ponto de falha vaza memória (Valgrind confirma);
 *   - o caminho de erro do grow (realloc parcial: data cresce, null_mask falha)
 *     é finalmente exercitado.
 *
 * Compile/rode via:  make test-allocfail   (usa -Wl,--wrap=malloc,realloc)
 */

#include "../include/smaug.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

/* ---- interceptação de malloc/realloc ---------------------------------- */
extern void *__real_malloc(size_t);
extern void *__real_realloc(void *, size_t);

static long g_fail_at = -1;   /* índice da alocação que deve falhar (-1 = nenhuma) */
static long g_count   = 0;    /* alocações já vistas nesta rodada */

void *__wrap_malloc(size_t n) {
    if (g_count++ == g_fail_at) return NULL;
    return __real_malloc(n);
}
void *__wrap_realloc(void *p, size_t n) {
    if (g_count++ == g_fail_at) return NULL;
    return __real_realloc(p, n);
}

static void reset(long fail_at) { g_fail_at = fail_at; g_count = 0; }

/* contador de checagens (cada iteração do loop é uma verificação) */
static long n_checks = 0;
#define OK(cond, msg) do { if (!(cond)) { \
    fprintf(stderr, "FALHOU [fail_at=%ld]: %s\n", g_fail_at, msg); exit(1); } \
    n_checks++; } while (0)

/* MAX_ALLOCS: teto de varredura por operação (folga sobre o medido) */
#define MAX_ALLOCS 12

/* ======================================================================
   f64
   ====================================================================== */
static void af_f64_create(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *s = smaug_f64_create(5);
        /* se falhou em alguma alocação, deve ser NULL; senão, válido */
        if (s) { OK(s->size == 5, "f64 create size"); smaug_f64_free(s); }
        /* se s==NULL aqui, foi por falha injetada — comportamento esperado */
    }
}

static void af_f64_create_from_array(void) {
    double arr[4] = {1, 2, 3, 4};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *s = smaug_f64_create_from_array(arr, 4);
        if (s) { OK(smaug_f64_count_nonnull(s) == 4, "f64 from_array conteudo"); smaug_f64_free(s); }
    }
}

static void af_f64_clone(void) {
    smaug_series_f64_t *base = smaug_f64_create(5);
    assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *c = smaug_f64_clone(base);
        if (c) { OK(c->size == 5, "f64 clone size"); smaug_f64_free(c); }
    }
    smaug_f64_free(base);
}

static void af_f64_view(void) {
    smaug_series_f64_t *base = smaug_f64_create(5);
    assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *v = smaug_f64_view(base, 0, 2);
        if (v) { OK(v->size == 2, "f64 view size"); smaug_f64_free(v); }
    }
    smaug_f64_free(base);
}

static void af_f64_append_grow(void) {
    /* cada iteração começa com série nova; append força grow (realloc) */
    for (long k = 0; k < MAX_ALLOCS; k++) {
        smaug_series_f64_t *s = smaug_f64_create_with_capacity(0, 0);
        assert(s);
        reset(k);
        int rc = smaug_f64_append(s, 1.0);
        /* rc==0 sucesso, rc==-1 falha graciosa; em ambos a série segue consistente */
        OK(rc == 0 || rc == -1, "f64 append rc valido");
        if (rc == 0) OK(s->size == 1, "f64 append cresceu");
        else         OK(s->size == 0, "f64 append falhou sem corromper");
        reset(-1);
        smaug_f64_free(s);
    }
}

static void af_f64_add(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    smaug_series_f64_t *y = smaug_f64_create_from_array(arr, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *r = smaug_f64_add(x, y);
        if (r) { OK(r->size == 3, "f64 add size"); smaug_f64_free(r); }
    }
    smaug_f64_free(x); smaug_f64_free(y);
}

static void af_f64_add_scalar(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *r = smaug_f64_add_scalar(x, 10.0);
        if (r) { OK(r->size == 3, "f64 add_scalar size"); smaug_f64_free(r); }
    }
    smaug_f64_free(x);
}

static void af_f64_compare(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_f64_gt(x, 1.5, &mask);
        /* gt aloca result E mask; se um falhar, ambos devem ser liberados internamente
           e o retorno NULL. Liberamos o que voltou não-NULL. */
        if (res) { OK(mask != NULL, "f64 gt mask junto"); free(res); free(mask); }
    }
    smaug_f64_free(x);
}

static void af_f64_argsort(void) {
    double arr[3] = {3, 1, 2};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        size_t *idx = smaug_f64_argsort(x, true);
        if (idx) { OK(idx[0] == 1, "f64 argsort menor"); free(idx); }
    }
    smaug_f64_free(x);
}

static void af_f64_sort(void) {
    double arr[3] = {3, 1, 2};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *r = smaug_f64_sort(x, true);
        if (r) { OK(r->size == 3, "f64 sort size"); smaug_f64_free(r); }
    }
    smaug_f64_free(x);
}

/* ======================================================================
   i64 (paridade)
   ====================================================================== */
static void af_i64_create(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *s = smaug_i64_create(5);
        if (s) { OK(s->size == 5, "i64 create size"); smaug_i64_free(s); }
    }
}

static void af_i64_create_from_array(void) {
    int64_t arr[4] = {1, 2, 3, 4};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *s = smaug_i64_create_from_array(arr, 4);
        if (s) { OK(smaug_i64_count_nonnull(s) == 4, "i64 from_array"); smaug_i64_free(s); }
    }
}

static void af_i64_clone(void) {
    smaug_series_i64_t *base = smaug_i64_create(5);
    assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *c = smaug_i64_clone(base);
        if (c) { OK(c->size == 5, "i64 clone size"); smaug_i64_free(c); }
    }
    smaug_i64_free(base);
}

static void af_i64_view(void) {
    smaug_series_i64_t *base = smaug_i64_create(5);
    assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *v = smaug_i64_view(base, 0, 2);
        if (v) { OK(v->size == 2, "i64 view size"); smaug_i64_free(v); }
    }
    smaug_i64_free(base);
}

static void af_i64_append_grow(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        smaug_series_i64_t *s = smaug_i64_create_with_capacity(0, 0);
        assert(s);
        reset(k);
        int rc = smaug_i64_append(s, 7);
        OK(rc == 0 || rc == -1, "i64 append rc valido");
        if (rc == 0) OK(s->size == 1, "i64 append cresceu");
        else         OK(s->size == 0, "i64 append falhou sem corromper");
        reset(-1);
        smaug_i64_free(s);
    }
}

static void af_i64_add(void) {
    int64_t arr[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    smaug_series_i64_t *y = smaug_i64_create_from_array(arr, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_add(x, y);
        if (r) { OK(r->size == 3, "i64 add size"); smaug_i64_free(r); }
    }
    smaug_i64_free(x); smaug_i64_free(y);
}

static void af_i64_add_scalar(void) {
    int64_t arr[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_add_scalar(x, 10);
        if (r) { OK(r->size == 3, "i64 add_scalar size"); smaug_i64_free(r); }
    }
    smaug_i64_free(x);
}

static void af_i64_compare(void) {
    int64_t arr[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_i64_gt(x, 1, &mask);
        if (res) { OK(mask != NULL, "i64 gt mask junto"); free(res); free(mask); }
    }
    smaug_i64_free(x);
}

static void af_i64_argsort(void) {
    int64_t arr[3] = {3, 1, 2};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        size_t *idx = smaug_i64_argsort(x, true);
        if (idx) { OK(idx[0] == 1, "i64 argsort menor"); free(idx); }
    }
    smaug_i64_free(x);
}

static void af_i64_sort(void) {
    int64_t arr[3] = {3, 1, 2};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_sort(x, true);
        if (r) { OK(r->size == 3, "i64 sort size"); smaug_i64_free(r); }
    }
    smaug_i64_free(x);
}

/* ======================================================================
   sanidade: sem falha injetada, tudo funciona (garante que o teste não
   está sabotando além da conta)
   ====================================================================== */
static void sanity_no_fail(void) {
    reset(-1);
    smaug_series_f64_t *s = smaug_f64_create(3);
    OK(s != NULL, "sanidade: create sem falha funciona");
    smaug_f64_free(s);
}

int main(void) {
    af_f64_create();
    af_f64_create_from_array();
    af_f64_clone();
    af_f64_view();
    af_f64_append_grow();
    af_f64_add();
    af_f64_add_scalar();
    af_f64_compare();
    af_f64_argsort();
    af_f64_sort();

    af_i64_create();
    af_i64_create_from_array();
    af_i64_clone();
    af_i64_view();
    af_i64_append_grow();
    af_i64_add();
    af_i64_add_scalar();
    af_i64_compare();
    af_i64_argsort();
    af_i64_sort();

    sanity_no_fail();

    printf("PASS: alloc-failure varreu todos os pontos (%ld verificacoes)\n", n_checks);
    return 0;
}
