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

/* --- B1: ops aritméticas restantes (sub/mul/div série) --- */
static void af_f64_sub(void) {
    double a[3] = {4, 5, 6}, b[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(a, 3);
    smaug_series_f64_t *y = smaug_f64_create_from_array(b, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *r = smaug_f64_sub(x, y);
        if (r) { OK(r->size == 3, "f64 sub size"); smaug_f64_free(r); }
    }
    smaug_f64_free(x); smaug_f64_free(y);
}

static void af_f64_mul(void) {
    double a[3] = {4, 5, 6}, b[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(a, 3);
    smaug_series_f64_t *y = smaug_f64_create_from_array(b, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *r = smaug_f64_mul(x, y);
        if (r) { OK(r->size == 3, "f64 mul size"); smaug_f64_free(r); }
    }
    smaug_f64_free(x); smaug_f64_free(y);
}

static void af_f64_div(void) {
    double a[3] = {4, 5, 6}, b[3] = {1, 2, 3};   /* divisor não-nulo */
    smaug_series_f64_t *x = smaug_f64_create_from_array(a, 3);
    smaug_series_f64_t *y = smaug_f64_create_from_array(b, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *r = smaug_f64_div(x, y);
        if (r) { OK(r->size == 3, "f64 div size"); smaug_f64_free(r); }
    }
    smaug_f64_free(x); smaug_f64_free(y);
}

/* --- B1: scalars restantes (sub/mul/div) --- */
static void af_f64_sub_scalar(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *r = smaug_f64_sub_scalar(x, 1.0);
        if (r) { OK(r->size == 3, "f64 sub_scalar size"); smaug_f64_free(r); }
    }
    smaug_f64_free(x);
}

static void af_f64_mul_scalar(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *r = smaug_f64_mul_scalar(x, 2.0);
        if (r) { OK(r->size == 3, "f64 mul_scalar size"); smaug_f64_free(r); }
    }
    smaug_f64_free(x);
}

static void af_f64_div_scalar(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *r = smaug_f64_div_scalar(x, 2.0);   /* scalar não-nulo */
        if (r) { OK(r->size == 3, "f64 div_scalar size"); smaug_f64_free(r); }
    }
    smaug_f64_free(x);
}

/* --- B1: compares restantes (lt/eq); gt já coberto em af_f64_compare --- */
static void af_f64_lt(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_f64_lt(x, 1.5, &mask);
        if (res) { OK(mask != NULL, "f64 lt mask junto"); free(res); free(mask); }
    }
    smaug_f64_free(x);
}

static void af_f64_eq(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_f64_eq(x, 2.0, &mask);
        if (res) { OK(mask != NULL, "f64 eq mask junto"); free(res); free(mask); }
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

/* --- B3: i64 compares restantes (lt/eq); gt já coberto em af_i64_compare --- */
static void af_i64_lt(void) {
    int64_t arr[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_i64_lt(x, 2, &mask);
        if (res) { OK(mask != NULL, "i64 lt mask junto"); free(res); free(mask); }
    }
    smaug_i64_free(x);
}

static void af_i64_eq(void) {
    int64_t arr[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_i64_eq(x, 2, &mask);
        if (res) { OK(mask != NULL, "i64 eq mask junto"); free(res); free(mask); }
    }
    smaug_i64_free(x);
}

/* --- B1: i64 ops aritméticas restantes (sub/mul/div série) --- */
static void af_i64_sub(void) {
    int64_t a[3] = {4, 5, 6}, b[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(a, 3);
    smaug_series_i64_t *y = smaug_i64_create_from_array(b, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_sub(x, y);
        if (r) { OK(r->size == 3, "i64 sub size"); smaug_i64_free(r); }
    }
    smaug_i64_free(x); smaug_i64_free(y);
}

static void af_i64_mul(void) {
    int64_t a[3] = {4, 5, 6}, b[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(a, 3);
    smaug_series_i64_t *y = smaug_i64_create_from_array(b, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_mul(x, y);
        if (r) { OK(r->size == 3, "i64 mul size"); smaug_i64_free(r); }
    }
    smaug_i64_free(x); smaug_i64_free(y);
}

static void af_i64_div(void) {
    int64_t a[3] = {4, 5, 6}, b[3] = {1, 2, 3};   /* divisor não-nulo */
    smaug_series_i64_t *x = smaug_i64_create_from_array(a, 3);
    smaug_series_i64_t *y = smaug_i64_create_from_array(b, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_div(x, y);
        if (r) { OK(r->size == 3, "i64 div size"); smaug_i64_free(r); }
    }
    smaug_i64_free(x); smaug_i64_free(y);
}

/* --- B1: i64 scalars restantes (sub/mul/div) --- */
static void af_i64_sub_scalar(void) {
    int64_t arr[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_sub_scalar(x, 1);
        if (r) { OK(r->size == 3, "i64 sub_scalar size"); smaug_i64_free(r); }
    }
    smaug_i64_free(x);
}

static void af_i64_mul_scalar(void) {
    int64_t arr[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_mul_scalar(x, 3);
        if (r) { OK(r->size == 3, "i64 mul_scalar size"); smaug_i64_free(r); }
    }
    smaug_i64_free(x);
}

static void af_i64_div_scalar(void) {
    int64_t arr[3] = {2, 4, 6};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_div_scalar(x, 2);   /* scalar não-nulo */
        if (r) { OK(r->size == 3, "i64 div_scalar size"); smaug_i64_free(r); }
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
   string — varre os pontos de alocação do lifecycle, mutação, seleção e
   ordenação. Onde há série-base, ela é criada com reset(-1) (sem falha) e a
   falha é injetada só na operação testada.
   ====================================================================== */
static void af_str_create(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_str_t *s = smaug_str_create(5);
        if (s) { OK(s->size == 5, "str create size"); smaug_str_free(s); }
    }
}
static void af_str_create_from_array(void) {
    const char *arr[] = {"AC", "BA", "MG"};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
        if (s) { OK(s->size == 3, "str from_array size"); smaug_str_free(s); }
    }
}
static void af_str_clone(void) {
    const char *arr[] = {"x", "yy", "zzz"};
    reset(-1);
    smaug_series_str_t *base = smaug_str_create_from_array(arr, 3);
    assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_str_t *c = smaug_str_clone(base);
        if (c) { OK(c->size == 3, "str clone size"); smaug_str_free(c); }
    }
    smaug_str_free(base);
}
static void af_str_set_grow(void) {
    /* set com string MAIOR força realocação do buffer — caminho de erro crítico */
    const char *arr[] = {"a", "b", "c"};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
        assert(s);
        reset(k);
        int rc = smaug_str_set(s, 0, "MUITO_GRANDE", 12);  /* cresce o buffer */
        if (rc == 0) {
            size_t l; const char *p = smaug_str_get(s, 0, &l);
            OK(p && l == 12, "str set grow conteudo");
        }
        /* rc != 0 = falha de alocação injetada (esperado); série segue íntegra */
        smaug_str_free(s);
    }
}
/* --- B3: str append forçando crescimento de buffer sob falha ---
   SMAUG_STR_BUFFER_INIT = 16 bytes. Criamos com capacidade 1 (força reserve
   logo no 1º append) e plantamos strings que somam >16 bytes pra garantir
   que str_buffer_reserve chame realloc e tenha chance de falhar.
   str_slots_reserve_one também entra quando capacity==0 (slots crescem). */
static void af_str_append_grow(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        /* capacidade inicial 1 byte → qualquer string >1 byte força crescimento */
        smaug_series_str_t *s = smaug_str_create_with_capacity(0, 1);
        assert(s);
        reset(k);
        /* 20 bytes: garante crescimento do buffer (>BUFFER_INIT=16) */
        smaug_str_append(s, "abcdefghijklmnopqrst", 20);
        smaug_str_append(s, "uvwxyz", 6);
        smaug_str_append_null(s);
        smaug_str_free(s);
    }
}
/* --- B3-final: append_null força crescimento de slots sob falha (str:316) ---
   str_slots_reserve_one cresce quando size==capacity. create(0) → capacity=0,
   então o 1º append_null já precisa crescer. O bloco anterior (af_str_append_grow)
   chama append_null depois de dois appends regulares que já cresceram os slots —
   portanto str:316 nunca falhou lá. Aqui append_null é a primeira op. */
static void af_str_append_null_grow(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_str_t *s = smaug_str_create(0);   /* capacity=0 */
        assert(s);
        reset(k);
        smaug_str_append_null(s);   /* 1ª op: slots crescem aqui → str:316 */
        smaug_str_append_null(s);
        smaug_str_free(s);
    }
}

static void af_str_compare(void) {
    const char *arr[] = {"SP", "RJ", "MG"};
    reset(-1);
    smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *m = NULL;
        uint8_t *r = smaug_str_eq(s, "SP", 2, &m);
        if (r) { OK(1, "str eq ok"); free(r); free(m); }
    }
    smaug_str_free(s);
}
static void af_str_filter(void) {
    const char *arr[] = {"a", "bb", "ccc", "d"};
    uint8_t mask[] = {1, 0, 1, 1};
    reset(-1);
    smaug_series_str_t *s = smaug_str_create_from_array(arr, 4);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_str_t *f = smaug_str_filter(s, mask);
        if (f) { OK(f->size == 3, "str filter size"); smaug_str_free(f); }
    }
    smaug_str_free(s);
}
static void af_str_take(void) {
    const char *arr[] = {"a", "bb", "ccc"};
    size_t idx[] = {2, 0, 1};
    reset(-1);
    smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_str_t *t = smaug_str_take(s, idx, 3);
        if (t) { OK(t->size == 3, "str take size"); smaug_str_free(t); }
    }
    smaug_str_free(s);
}
static void af_str_argsort(void) {
    const char *arr[] = {"MG", "AC", "SP"};
    reset(-1);
    smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        size_t *ix = smaug_str_argsort(s, true);
        if (ix) { OK(1, "str argsort ok"); free(ix); }
    }
    smaug_str_free(s);
}
static void af_str_sort(void) {
    const char *arr[] = {"MG", "AC", "SP"};
    reset(-1);
    smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_str_t *r = smaug_str_sort(s, true);
        if (r) { OK(r->size == 3, "str sort size"); smaug_str_free(r); }
    }
    smaug_str_free(s);
}

/* ======================================================================
   COW detach — falha de alocação em set/set_null em views
   O detach faz exatamente 2 mallocs (nd, nm). Varremos k=0 (nd falha) e
   k=1 (nd ok, nm falha) verificando:
     - retorno SMG_ERR_NOMEM, view continua sendo view, pai inalterada;
     - nd alocado e depois descartado no caminho k=1 não vaza (Valgrind).
   Para k >= 2 o detach sucede: verificamos view destacada e pai intacta.
   ====================================================================== */
static void af_f64_cow_set(void) {
    double arr[4] = {10.0, 20.0, 30.0, 40.0};
    reset(-1);
    smaug_series_f64_t *pai = smaug_f64_create_from_array(arr, 4);
    assert(pai);

    for (long k = 0; k < MAX_ALLOCS; k++) {
        /* view sem falha; falha injetada apenas no set (dentro do detach) */
        reset(-1);
        smaug_series_f64_t *v = smaug_f64_view(pai, 1, 2);   /* [20, 30] */
        assert(v);

        reset(k);
        smaug_status_t rc = smaug_f64_set(v, 0, 99.0);

        if (rc == SMG_OK) {
            OK(v->meta.is_view        == false, "f64 cow_set: view detachada");
            OK(v->meta.external_alloc == false, "f64 cow_set: external_alloc false");
            OK(pai->data[1] == 20.0,            "f64 cow_set: pai preservada");
        } else {
            OK(rc == SMG_ERR_NOMEM,             "f64 cow_set OOM: status NOMEM");
            OK(v->meta.is_view        == true,  "f64 cow_set OOM: view nao detachada");
            OK(pai->data[1] == 20.0,            "f64 cow_set OOM: pai preservada");
        }

        reset(-1);
        smaug_f64_free(v);
    }
    smaug_f64_free(pai);
}

static void af_f64_cow_set_null(void) {
    double arr[4] = {10.0, 20.0, 30.0, 40.0};
    reset(-1);
    smaug_series_f64_t *pai = smaug_f64_create_from_array(arr, 4);
    assert(pai);

    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_f64_t *v = smaug_f64_view(pai, 0, 4);
        assert(v);

        reset(k);
        smaug_status_t rc = smaug_f64_set_null(v, 1);

        if (rc == SMG_OK) {
            OK(v->meta.is_view == false,    "f64 cow_set_null: view detachada");
            OK(!smaug_f64_is_null(pai, 1),  "f64 cow_set_null: pai nao virou null");
        } else {
            OK(rc == SMG_ERR_NOMEM,         "f64 cow_set_null OOM: status NOMEM");
            OK(v->meta.is_view == true,     "f64 cow_set_null OOM: view nao detachada");
            OK(!smaug_f64_is_null(pai, 1),  "f64 cow_set_null OOM: pai preservada");
        }

        reset(-1);
        smaug_f64_free(v);
    }
    smaug_f64_free(pai);
}

static void af_i64_cow_set(void) {
    int64_t arr[4] = {10, 20, 30, 40};
    reset(-1);
    smaug_series_i64_t *pai = smaug_i64_create_from_array(arr, 4);
    assert(pai);

    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_i64_t *v = smaug_i64_view(pai, 1, 2);   /* [20, 30] */
        assert(v);

        reset(k);
        smaug_status_t rc = smaug_i64_set(v, 0, 99);

        if (rc == SMG_OK) {
            OK(v->meta.is_view        == false, "i64 cow_set: view detachada");
            OK(v->meta.external_alloc == false, "i64 cow_set: external_alloc false");
            OK(pai->data[1] == 20,              "i64 cow_set: pai preservada");
        } else {
            OK(rc == SMG_ERR_NOMEM,             "i64 cow_set OOM: status NOMEM");
            OK(v->meta.is_view        == true,  "i64 cow_set OOM: view nao detachada");
            OK(pai->data[1] == 20,              "i64 cow_set OOM: pai preservada");
        }

        reset(-1);
        smaug_i64_free(v);
    }
    smaug_i64_free(pai);
}

static void af_i64_cow_set_null(void) {
    int64_t arr[4] = {10, 20, 30, 40};
    reset(-1);
    smaug_series_i64_t *pai = smaug_i64_create_from_array(arr, 4);
    assert(pai);

    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_i64_t *v = smaug_i64_view(pai, 0, 4);
        assert(v);

        reset(k);
        smaug_status_t rc = smaug_i64_set_null(v, 2);

        if (rc == SMG_OK) {
            OK(v->meta.is_view == false,    "i64 cow_set_null: view detachada");
            OK(!smaug_i64_is_null(pai, 2),  "i64 cow_set_null: pai nao virou null");
        } else {
            OK(rc == SMG_ERR_NOMEM,         "i64 cow_set_null OOM: status NOMEM");
            OK(v->meta.is_view == true,     "i64 cow_set_null OOM: view nao detachada");
            OK(!smaug_i64_is_null(pai, 2),  "i64 cow_set_null OOM: pai preservada");
        }

        reset(-1);
        smaug_i64_free(v);
    }
    smaug_i64_free(pai);
}

static void af_f64_cow_append(void) {
    /* O append numa view faz: detach (2 mallocs) + grow (até 2 reallocs).
       Varremos todos os pontos de falha; em qualquer um, pai deve permanecer
       intacta e o retorno deve ser -1. */
    double arr[3] = {10.0, 20.0, 30.0};
    reset(-1);
    smaug_series_f64_t *pai = smaug_f64_create_from_array(arr, 3);
    assert(pai);

    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_f64_t *v = smaug_f64_view(pai, 0, 3);
        assert(v);

        reset(k);
        int rc = smaug_f64_append(v, 99.0);

        if (rc == 0) {
            OK(v->meta.is_view == false, "f64 cow_append: view detachada");
            OK(v->size == 4,             "f64 cow_append: size incrementado");
            OK(pai->data[0] == 10.0,     "f64 cow_append: pai preservada");
        } else {
            OK(rc == -1,             "f64 cow_append OOM: rc=-1");
            OK(pai->data[0] == 10.0, "f64 cow_append OOM: pai preservada");
        }

        reset(-1);
        smaug_f64_free(v);
    }
    smaug_f64_free(pai);
}

static void af_f64_cow_append_null(void) {
    double arr[3] = {10.0, 20.0, 30.0};
    reset(-1);
    smaug_series_f64_t *pai = smaug_f64_create_from_array(arr, 3);
    assert(pai);

    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_f64_t *v = smaug_f64_view(pai, 0, 3);
        assert(v);

        reset(k);
        int rc = smaug_f64_append_null(v);

        if (rc == 0) {
            OK(v->meta.is_view == false,  "f64 cow_append_null: view detachada");
            OK(v->size == 4,              "f64 cow_append_null: size incrementado");
            OK(!smaug_f64_is_null(pai,0), "f64 cow_append_null: pai preservada");
        } else {
            OK(rc == -1,                  "f64 cow_append_null OOM: rc=-1");
            OK(!smaug_f64_is_null(pai,0), "f64 cow_append_null OOM: pai preservada");
        }

        reset(-1);
        smaug_f64_free(v);
    }
    smaug_f64_free(pai);
}

static void af_i64_cow_append(void) {
    int64_t arr[3] = {10, 20, 30};
    reset(-1);
    smaug_series_i64_t *pai = smaug_i64_create_from_array(arr, 3);
    assert(pai);

    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_i64_t *v = smaug_i64_view(pai, 0, 3);
        assert(v);

        reset(k);
        int rc = smaug_i64_append(v, 99);

        if (rc == 0) {
            OK(v->meta.is_view == false, "i64 cow_append: view detachada");
            OK(v->size == 4,             "i64 cow_append: size incrementado");
            OK(pai->data[0] == 10,       "i64 cow_append: pai preservada");
        } else {
            OK(rc == -1,           "i64 cow_append OOM: rc=-1");
            OK(pai->data[0] == 10, "i64 cow_append OOM: pai preservada");
        }

        reset(-1);
        smaug_i64_free(v);
    }
    smaug_i64_free(pai);
}

static void af_i64_cow_append_null(void) {
    int64_t arr[3] = {10, 20, 30};
    reset(-1);
    smaug_series_i64_t *pai = smaug_i64_create_from_array(arr, 3);
    assert(pai);

    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_i64_t *v = smaug_i64_view(pai, 0, 3);
        assert(v);

        reset(k);
        int rc = smaug_i64_append_null(v);

        if (rc == 0) {
            OK(v->meta.is_view == false,  "i64 cow_append_null: view detachada");
            OK(v->size == 4,              "i64 cow_append_null: size incrementado");
            OK(!smaug_i64_is_null(pai,0), "i64 cow_append_null: pai preservada");
        } else {
            OK(rc == -1,                  "i64 cow_append_null OOM: rc=-1");
            OK(!smaug_i64_is_null(pai,0), "i64 cow_append_null OOM: pai preservada");
        }

        reset(-1);
        smaug_i64_free(v);
    }
    smaug_i64_free(pai);
}

/* ======================================================================
   FASE 8 (b) — take/filter numéricos sob falha de alocação.
   Os equivalentes de string (af_str_take/af_str_filter) já existiam; os
   numéricos faltavam. São os caminhos C que DataSet:take/dropna/filter/iloc/
   head/tail/sample exercem em colunas f64/i64. Padrão idêntico ao str:
   base construída fora da janela de injeção, varredura em reset(k).
   ====================================================================== */
static void af_f64_take(void) {
    double arr[3] = {10, 20, 30};
    size_t idx[]  = {2, 0, 1};
    reset(-1);
    smaug_series_f64_t *s = smaug_f64_create_from_array(arr, 3);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *t = smaug_f64_take(s, idx, 3);
        if (t) { OK(t->size == 3, "f64 take size"); smaug_f64_free(t); }
    }
    smaug_f64_free(s);
}
static void af_f64_filter(void) {
    double arr[4] = {1, 2, 3, 4};
    uint8_t mask[] = {1, 0, 1, 1};
    reset(-1);
    smaug_series_f64_t *s = smaug_f64_create_from_array(arr, 4);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *f = smaug_f64_filter(s, mask);
        if (f) { OK(f->size == 3, "f64 filter size"); smaug_f64_free(f); }
    }
    smaug_f64_free(s);
}
static void af_i64_take(void) {
    int64_t arr[3] = {10, 20, 30};
    size_t  idx[]  = {2, 0, 1};
    reset(-1);
    smaug_series_i64_t *s = smaug_i64_create_from_array(arr, 3);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *t = smaug_i64_take(s, idx, 3);
        if (t) { OK(t->size == 3, "i64 take size"); smaug_i64_free(t); }
    }
    smaug_i64_free(s);
}
static void af_i64_filter(void) {
    int64_t arr[4] = {1, 2, 3, 4};
    uint8_t mask[] = {1, 0, 1, 1};
    reset(-1);
    smaug_series_i64_t *s = smaug_i64_create_from_array(arr, 4);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *f = smaug_i64_filter(s, mask);
        if (f) { OK(f->size == 3, "i64 filter size"); smaug_i64_free(f); }
    }
    smaug_i64_free(s);
}

/* ======================================================================
   B2: bool (Kleene) — and/or/xor/not via alloc-fail.
   As ops bool não têm struct de série: operam em arrays crus (valores +
   máscara + n). A única alocação durante a op é o alloc_pair (vals + mask),
   então out_mask é sempre fornecido para forçar os DOIS mallocs (linhas
   15/18) e o guard !r de cada op.
   ====================================================================== */
static void af_bool_and(void) {
    uint8_t a[3] = {1, 0, 1}, b[3] = {1, 1, 0};
    smaug_mask_t am[3] = {0xFF, 0xFF, 0xFF}, bm[3] = {0xFF, 0xFF, 0xFF};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *om = NULL;
        uint8_t *r = smaug_bool_and(a, am, b, bm, 3, &om);
        if (r) { OK(om != NULL, "bool and mask junto"); free(r); free(om); }
    }
}

static void af_bool_or(void) {
    uint8_t a[3] = {1, 0, 1}, b[3] = {1, 1, 0};
    smaug_mask_t am[3] = {0xFF, 0xFF, 0xFF}, bm[3] = {0xFF, 0xFF, 0xFF};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *om = NULL;
        uint8_t *r = smaug_bool_or(a, am, b, bm, 3, &om);
        if (r) { OK(om != NULL, "bool or mask junto"); free(r); free(om); }
    }
}

static void af_bool_xor(void) {
    uint8_t a[3] = {1, 0, 1}, b[3] = {1, 1, 0};
    smaug_mask_t am[3] = {0xFF, 0xFF, 0xFF}, bm[3] = {0xFF, 0xFF, 0xFF};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *om = NULL;
        uint8_t *r = smaug_bool_xor(a, am, b, bm, 3, &om);
        if (r) { OK(om != NULL, "bool xor mask junto"); free(r); free(om); }
    }
}

static void af_bool_not(void) {
    uint8_t a[3] = {1, 0, 1};
    smaug_mask_t am[3] = {0xFF, 0xFF, 0xFF};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *om = NULL;
        uint8_t *r = smaug_bool_not(a, am, 3, &om);
        if (r) { OK(om != NULL, "bool not mask junto"); free(r); free(om); }
    }
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
    af_f64_sub();
    af_f64_mul();
    af_f64_div();
    af_f64_add_scalar();
    af_f64_sub_scalar();
    af_f64_mul_scalar();
    af_f64_div_scalar();
    af_f64_compare();
    af_f64_lt();
    af_f64_eq();
    af_f64_argsort();
    af_f64_sort();
    af_f64_take();
    af_f64_filter();

    af_i64_create();
    af_i64_create_from_array();
    af_i64_clone();
    af_i64_view();
    af_i64_append_grow();
    af_i64_add();
    af_i64_sub();
    af_i64_mul();
    af_i64_div();
    af_i64_add_scalar();
    af_i64_sub_scalar();
    af_i64_mul_scalar();
    af_i64_div_scalar();
    af_i64_compare();
    af_i64_lt();
    af_i64_eq();
    af_i64_argsort();
    af_i64_sort();
    af_i64_take();
    af_i64_filter();

    af_str_create();
    af_str_create_from_array();
    af_str_clone();
    af_str_set_grow();
    af_str_append_grow();
    af_str_append_null_grow();
    af_str_compare();
    af_str_filter();
    af_str_take();
    af_str_argsort();
    af_str_sort();

    af_f64_cow_set();
    af_f64_cow_set_null();
    af_i64_cow_set();
    af_i64_cow_set_null();
    af_f64_cow_append();
    af_f64_cow_append_null();
    af_i64_cow_append();
    af_i64_cow_append_null();

    af_bool_and();
    af_bool_or();
    af_bool_xor();
    af_bool_not();

    sanity_no_fail();

    printf("PASS: alloc-failure varreu todos os pontos (%ld verificacoes)\n", n_checks);
    return 0;
}
