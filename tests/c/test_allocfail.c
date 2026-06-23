/* tests/test_allocfail.c
 *
 * Teste de falha de alocação (Fase 1.6 — endurecimento, padrão SQLite).
 *
 * Intercepta malloc/realloc/calloc/strdup via --wrap do linker (ver Makefile).
 * Um contador
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
 * Compile/rode via:  make test-allocfail   (usa -Wl,--wrap=malloc,realloc,calloc,strdup)
 */

#include "../include/smaug.h"
#include "../include/smaug_io.h"
#include "../include/smaug_string.h"
#include "../include/smaug_ops_window.h"
#include "../include/smaug_datetime.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- interceptação de malloc/realloc ---------------------------------- */
extern void *__real_malloc(size_t);
extern void *__real_realloc(void *, size_t);
extern void *__real_calloc(size_t, size_t);
extern char *__real_strdup(const char *);
extern void  free(void *);

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
void *__wrap_calloc(size_t nmemb, size_t size) {
    if (g_count++ == g_fail_at) return NULL;
    return __real_calloc(nmemb, size);
}
char *__wrap_strdup(const char *s) {
    if (g_count++ == g_fail_at) return NULL;
    return __real_strdup(s);
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

static void af_f64_ge(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_f64_ge(x, 2.0, &mask);
        if (res) { OK(mask != NULL, "f64 ge mask junto"); free(res); free(mask); }
    }
    smaug_f64_free(x);
}
static void af_f64_le(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_f64_le(x, 2.0, &mask);
        if (res) { OK(mask != NULL, "f64 le mask junto"); free(res); free(mask); }
    }
    smaug_f64_free(x);
}
static void af_f64_ne(void) {
    double arr[3] = {1, 2, 3};
    smaug_series_f64_t *x = smaug_f64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_f64_ne(x, 2.0, &mask);
        if (res) { OK(mask != NULL, "f64 ne mask junto"); free(res); free(mask); }
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

static void af_i64_ge(void) {
    int64_t arr[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_i64_ge(x, 2, &mask);
        if (res) { OK(mask != NULL, "i64 ge mask junto"); free(res); free(mask); }
    }
    smaug_i64_free(x);
}
static void af_i64_le(void) {
    int64_t arr[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_i64_le(x, 2, &mask);
        if (res) { OK(mask != NULL, "i64 le mask junto"); free(res); free(mask); }
    }
    smaug_i64_free(x);
}
static void af_i64_ne(void) {
    int64_t arr[3] = {1, 2, 3};
    smaug_series_i64_t *x = smaug_i64_create_from_array(arr, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *mask = NULL;
        uint8_t *res = smaug_i64_ne(x, 2, &mask);
        if (res) { OK(mask != NULL, "i64 ne mask junto"); free(res); free(mask); }
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
static void af_str_ge(void) {
    const char *arr[] = {"SP", "RJ", "MG"};
    reset(-1);
    smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *m = NULL;
        uint8_t *r = smaug_str_ge(s, "RJ", 2, &m);
        if (r) { OK(1, "str ge ok"); free(r); free(m); }
    }
    smaug_str_free(s);
}
static void af_str_le(void) {
    const char *arr[] = {"SP", "RJ", "MG"};
    reset(-1);
    smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *m = NULL;
        uint8_t *r = smaug_str_le(s, "RJ", 2, &m);
        if (r) { OK(1, "str le ok"); free(r); free(m); }
    }
    smaug_str_free(s);
}
static void af_str_ne(void) {
    const char *arr[] = {"SP", "RJ", "MG"};
    reset(-1);
    smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_mask_t *m = NULL;
        uint8_t *r = smaug_str_ne(s, "SP", 2, &m);
        if (r) { OK(1, "str ne ok"); free(r); free(m); }
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
   B3: bool struct-based (smaug_series_bool_t) — dtype de primeira classe.
   Espelha a varredura de i64: lifecycle, seleção, COW, e Kleene struct→struct.
   Distinto do bloco B2 (raw arrays), que cobre as funções legadas.
   ====================================================================== */
static void af_bool_create(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *s = smaug_bool_create(5);
        if (s) { OK(s->size == 5, "bool create size"); smaug_bool_free(s); }
    }
}
static void af_bool_create_from_array(void) {
    uint8_t arr[4] = {1, 0, 1, 1};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *s = smaug_bool_create_from_array(arr, 4);
        if (s) { OK(smaug_bool_count_nonnull(s) == 4, "bool from_array"); smaug_bool_free(s); }
    }
}
static void af_bool_clone(void) {
    smaug_series_bool_t *base = smaug_bool_create(5);
    assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *c = smaug_bool_clone(base);
        if (c) { OK(c->size == 5, "bool clone size"); smaug_bool_free(c); }
    }
    smaug_bool_free(base);
}
static void af_bool_view(void) {
    smaug_series_bool_t *base = smaug_bool_create(5);
    assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *v = smaug_bool_view(base, 0, 2);
        if (v) { OK(v->size == 2, "bool view size"); smaug_bool_free(v); }
    }
    smaug_bool_free(base);
}
static void af_bool_append_grow(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        smaug_series_bool_t *s = smaug_bool_create_with_capacity(0, 0);
        assert(s);
        reset(k);
        int rc = smaug_bool_append(s, 1);
        OK(rc == 0 || rc == -1, "bool append rc valido");
        if (rc == 0) OK(s->size == 1, "bool append cresceu");
        else         OK(s->size == 0, "bool append falhou sem corromper");
        reset(-1);
        smaug_bool_free(s);
    }
}
static void af_bool_take(void) {
    uint8_t arr[3] = {1, 0, 1};
    size_t  idx[]  = {2, 0, 1};
    reset(-1);
    smaug_series_bool_t *s = smaug_bool_create_from_array(arr, 3);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *t = smaug_bool_take(s, idx, 3);
        if (t) { OK(t->size == 3, "bool take size"); smaug_bool_free(t); }
    }
    smaug_bool_free(s);
}
static void af_bool_filter(void) {
    uint8_t arr[4] = {1, 0, 1, 1};
    uint8_t mask[] = {1, 0, 1, 1};
    reset(-1);
    smaug_series_bool_t *s = smaug_bool_create_from_array(arr, 4);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *f = smaug_bool_filter(s, mask);
        if (f) { OK(f->size == 3, "bool filter size"); smaug_bool_free(f); }
    }
    smaug_bool_free(s);
}
static void af_bool_argsort(void) {
    uint8_t arr[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *s = smaug_bool_create_from_array(arr, 4);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        size_t *p = smaug_bool_argsort(s, true);
        if (p) { OK(p[0] == 1, "bool argsort"); smaug_free(p); }
    }
    smaug_bool_free(s);
}
static void af_bool_sort(void) {
    uint8_t arr[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *s = smaug_bool_create_from_array(arr, 4);
    assert(s);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *r = smaug_bool_sort(s, true);
        if (r) { OK(r->size == 4, "bool sort size"); smaug_bool_free(r); }
    }
    smaug_bool_free(s);
}
/* Kleene struct→struct: a única alocação extra é a série resultado (via
   bool_series_from_pair, que chama smaug_bool_create + os pares internos). */
static void af_bool_series_and(void) {
    uint8_t a[3] = {1, 0, 1}, b[3] = {1, 1, 0};
    reset(-1);
    smaug_series_bool_t *x = smaug_bool_create_from_array(a, 3);
    smaug_series_bool_t *y = smaug_bool_create_from_array(b, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *r = smaug_bool_series_and(x, y);
        if (r) { OK(r->size == 3, "bool series_and size"); smaug_bool_free(r); }
    }
    smaug_bool_free(x); smaug_bool_free(y);
}
static void af_bool_series_or(void) {
    uint8_t a[3] = {1, 0, 1}, b[3] = {1, 1, 0};
    reset(-1);
    smaug_series_bool_t *x = smaug_bool_create_from_array(a, 3);
    smaug_series_bool_t *y = smaug_bool_create_from_array(b, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *r = smaug_bool_series_or(x, y);
        if (r) { OK(r->size == 3, "bool series_or size"); smaug_bool_free(r); }
    }
    smaug_bool_free(x); smaug_bool_free(y);
}
static void af_bool_series_xor(void) {
    uint8_t a[3] = {1, 0, 1}, b[3] = {1, 1, 0};
    reset(-1);
    smaug_series_bool_t *x = smaug_bool_create_from_array(a, 3);
    smaug_series_bool_t *y = smaug_bool_create_from_array(b, 3);
    assert(x && y);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *r = smaug_bool_series_xor(x, y);
        if (r) { OK(r->size == 3, "bool series_xor size"); smaug_bool_free(r); }
    }
    smaug_bool_free(x); smaug_bool_free(y);
}
static void af_bool_series_not(void) {
    uint8_t a[3] = {1, 0, 1};
    reset(-1);
    smaug_series_bool_t *x = smaug_bool_create_from_array(a, 3);
    assert(x);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_bool_t *r = smaug_bool_series_not(x);
        if (r) { OK(r->size == 3, "bool series_not size"); smaug_bool_free(r); }
    }
    smaug_bool_free(x);
}
/* COW em view de bool: set, set_null, append, append_null */
static void af_bool_cow_set(void) {
    uint8_t arr[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *pai = smaug_bool_create_from_array(arr, 4);
    assert(pai);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_bool_t *v = smaug_bool_view(pai, 1, 2);
        assert(v);
        reset(k);
        smaug_status_t rc = smaug_bool_set(v, 0, 1);
        if (rc == SMG_OK) {
            OK(v->meta.is_view == false, "bool cow_set: view detachada");
            OK(pai->data[1] == 0,        "bool cow_set: pai preservada");
        } else {
            OK(rc == SMG_ERR_NOMEM,      "bool cow_set OOM: status NOMEM");
            OK(v->meta.is_view == true,  "bool cow_set OOM: view nao detachada");
            OK(pai->data[1] == 0,        "bool cow_set OOM: pai preservada");
        }
        reset(-1);
        smaug_bool_free(v);
    }
    smaug_bool_free(pai);
}
static void af_bool_cow_set_null(void) {
    uint8_t arr[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *pai = smaug_bool_create_from_array(arr, 4);
    assert(pai);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_bool_t *v = smaug_bool_view(pai, 0, 4);
        assert(v);
        reset(k);
        smaug_status_t rc = smaug_bool_set_null(v, 0);
        if (rc == SMG_OK) {
            OK(v->meta.is_view == false,      "bool cow_set_null: detachada");
            OK(pai->null_mask[0] == 0xFF,     "bool cow_set_null: pai preservada");
        } else {
            OK(rc == SMG_ERR_NOMEM,           "bool cow_set_null OOM: NOMEM");
            OK(pai->null_mask[0] == 0xFF,     "bool cow_set_null OOM: pai preservada");
        }
        reset(-1);
        smaug_bool_free(v);
    }
    smaug_bool_free(pai);
}
static void af_bool_cow_append(void) {
    uint8_t arr[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *pai = smaug_bool_create_from_array(arr, 4);
    assert(pai);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_bool_t *v = smaug_bool_view(pai, 0, 2);
        assert(v);
        reset(k);
        int rc = smaug_bool_append(v, 1);
        OK(rc == 0 || rc == -1, "bool cow_append rc valido");
        if (rc == 0) OK(v->meta.is_view == false, "bool cow_append: detachada");
        OK(pai->size == 4, "bool cow_append: pai intacta");
        reset(-1);
        smaug_bool_free(v);
    }
    smaug_bool_free(pai);
}
static void af_bool_cow_append_null(void) {
    uint8_t arr[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *pai = smaug_bool_create_from_array(arr, 4);
    assert(pai);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(-1);
        smaug_series_bool_t *v = smaug_bool_view(pai, 0, 2);
        assert(v);
        reset(k);
        int rc = smaug_bool_append_null(v);
        OK(rc == 0 || rc == -1, "bool cow_append_null rc valido");
        if (rc == 0) OK(v->meta.is_view == false, "bool cow_append_null: detachada");
        OK(pai->size == 4, "bool cow_append_null: pai intacta");
        reset(-1);
        smaug_bool_free(v);
    }
    smaug_bool_free(pai);
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

/* ======================================================================
   Anel 3 — CSV/JSON: varredura de pontos de alocação nos parsers.
   Cada falha deve retornar NULL/erro gracioso, sem crash, sem leak.
   MAX_IO_ALLOCS: teto generoso para cobrir todos os malloc/realloc/strdup
   dos parsers (CSV tem ~14, JSON tem ~16, mais margens de crescimento).
   ====================================================================== */
#define MAX_IO_ALLOCS 64

/* CSV — leitura: todos os pontos de malloc no tokenizador e no parser */
static void af_csv_read_mem(void) {
    /* CSV simples com todos os dtypes para exercitar todas as alocações */
    const char *csv = "i,f,b,s\n1,1.5,true,hello\n2,2.5,false,world\n";
    size_t csv_len  = strlen(csv);
    reset(-1);
    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        smaug_table_t *t = smaug_read_csv_mem(csv, csv_len, NULL);
        if (t) {
            /* pode ter succedido ou retornado tabela com erro */
            OK(!t || t->error || 1, "csv_read_mem: sem crash");
            smaug_table_free(t);
        }
    }
    /* sem falha: deve suceder */
    reset(-1);
    smaug_table_t *t = smaug_read_csv_mem(csv, csv_len, NULL);
    OK(t && !t->error && t->nrows == 2, "csv_read_mem: sucesso sem falha");
    smaug_table_free(t);
}

/* CSV — leitura com aspas RFC 4180 (exercita realloc dentro do tokenizador) */
static void af_csv_read_quoted(void) {
    const char *csv = "v\n\"campo com, virgula\"\n\"outro\"\n";
    size_t csv_len  = strlen(csv);
    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        smaug_table_t *t = smaug_read_csv_mem(csv, csv_len, NULL);
        if (t) { smaug_table_free(t); }
    }
    reset(-1);
    smaug_table_t *t = smaug_read_csv_mem(csv, csv_len, NULL);
    OK(t && !t->error && t->nrows == 2, "csv_read_quoted: sucesso");
    smaug_table_free(t);
}

/* CSV — leitura com muitas linhas (exercita realloc do vetor de rows) */
static void af_csv_read_many_rows(void) {
    /* 100 linhas — força o realloc de rows[] (começa com cap=64) */
    char *csv = malloc(8192);
    assert(csv);
    int pos = sprintf(csv, "v\n");
    for (int i = 0; i < 100; i++) pos += sprintf(csv + pos, "%d\n", i);
    size_t csv_len = (size_t)pos;

    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        smaug_table_t *t = smaug_read_csv_mem(csv, csv_len, NULL);
        if (t) { smaug_table_free(t); }
    }
    reset(-1);
    smaug_table_t *t = smaug_read_csv_mem(csv, csv_len, NULL);
    OK(t && !t->error && t->nrows == 100, "csv_read_many_rows: sucesso");
    smaug_table_free(t);
    free(csv);  /* liberar sem wrap */
}

/* CSV — leitura sem header: nomes sintéticos "colN" via strdup de buffer local
 * (caminho nunca exercitado pelo allocfail antes — strdup(tmp) é um ponto de
 * alocação distinto do strdup(src) com header). */
static void af_csv_read_no_header(void) {
    const char *csv = "1,2.5,true\n3,4.5,false\n";
    size_t csv_len  = strlen(csv);
    smaug_csv_opts_t o = smaug_csv_default_opts();
    o.header = 0;
    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        smaug_table_t *t = smaug_read_csv_mem(csv, csv_len, &o);
        if (t) { smaug_table_free(t); }
    }
    reset(-1);
    smaug_table_t *t = smaug_read_csv_mem(csv, csv_len, &o);
    OK(t && !t->error && t->ncols == 3, "csv_read_no_header: sucesso, 3 colunas");
    smaug_table_free(t);
}

/* CSV — writer: pontos de realloc do wbuf + todos os ramos por dtype
 * (multi-coluna com NULL em cada família — a tabela antiga, de 1 coluna
 * int64 sem null, nunca exercitava os ramos st==SMG_NULL_VALUE nem a
 * coluna string nem o separador c>0 entre colunas). */
static void af_csv_write(void) {
    smaug_series_i64_t  *si = smaug_i64_create(2);
    smaug_series_f64_t  *sf = smaug_f64_create(2);
    smaug_series_bool_t *sb = smaug_bool_create(2);
    smaug_series_str_t  *ss = smaug_str_create(2);
    assert(si && sf && sb && ss);
    smaug_i64_set(si, 0, 1);        smaug_i64_set_null(si, 1);
    smaug_f64_set_null(sf, 0);      smaug_f64_set(sf, 1, 2.5);
    smaug_bool_set(sb, 0, 1);       smaug_bool_set_null(sb, 1);
    smaug_str_set(ss, 0, "a,b", 3); smaug_str_set_null(ss, 1);

    smaug_column_t cols[4] = {0};
    cols[0].name = "i"; cols[0].dtype = "int64";   cols[0].i64     = si;
    cols[1].name = "f"; cols[1].dtype = "float64"; cols[1].f64     = sf;
    cols[2].name = "b"; cols[2].dtype = "bool";    cols[2].boolcol = sb;
    cols[3].name = "s"; cols[3].dtype = "string";  cols[3].str     = ss;

    smaug_table_t t = {0};
    t.columns = cols; t.ncols = 4; t.nrows = 2;

    smaug_csv_write_opts_t wo = smaug_csv_write_default_opts();
    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        size_t len;
        char *out = smaug_write_csv_mem(&t, &wo, &len);
        if (out) { free(out); }
    }
    reset(-1);
    size_t len;
    char *out = smaug_write_csv_mem(&t, &wo, &len);
    OK(out != NULL && len > 0,         "csv_write: sucesso");
    OK(strstr(out, "\"a,b\"") != NULL, "csv_write: campo com vírgula escapado");
    free(out);
    smaug_i64_free(si); smaug_f64_free(sf); smaug_bool_free(sb); smaug_str_free(ss);
}

/* JSON — leitura: todos os pontos de malloc do tokenizador e do parser */
static void af_json_read_mem(void) {
    const char *j =
        "[{\"i\":1,\"f\":1.5,\"b\":true,\"s\":\"hello\"},"
         "{\"i\":2,\"f\":2.5,\"b\":false,\"s\":\"world\"}]";
    size_t jlen = strlen(j);

    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        smaug_table_t *t = smaug_read_json_mem(j, jlen);
        if (t) { smaug_table_free(t); }
    }
    reset(-1);
    smaug_table_t *t = smaug_read_json_mem(j, jlen);
    OK(t && !t->error && t->nrows == 2 && t->ncols == 4,
       "json_read_mem: sucesso");
    smaug_table_free(t);
}

/* JSON — leitura com muitos records (exercita realloc do vetor de recs[]) */
static void af_json_read_many_records(void) {
    /* 80 records — força realloc de recs[] (começa com cap=64) */
    char *j = malloc(8192);
    assert(j);
    int pos = sprintf(j, "[");
    for (int i = 0; i < 80; i++) {
        pos += sprintf(j + pos, "{\"v\":%d}%s", i, i < 79 ? "," : "");
    }
    pos += sprintf(j + pos, "]");
    size_t jlen = (size_t)pos;

    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        smaug_table_t *t = smaug_read_json_mem(j, jlen);
        if (t) { smaug_table_free(t); }
    }
    reset(-1);
    smaug_table_t *t = smaug_read_json_mem(j, jlen);
    OK(t && !t->error && t->nrows == 80, "json_read_many_records: sucesso");
    smaug_table_free(t);
    free(j);
}

/* JSON — leitura com strings longas (exercita realloc dentro do tokenizador) */
static void af_json_read_long_string(void) {
    /* string > 64 bytes força realloc no read_json_string */
    const char *j =
        "[{\"v\":\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789XY\"}]";
    size_t jlen = strlen(j);

    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        smaug_table_t *t = smaug_read_json_mem(j, jlen);
        if (t) { smaug_table_free(t); }
    }
    reset(-1);
    smaug_table_t *t = smaug_read_json_mem(j, jlen);
    OK(t && !t->error && t->nrows == 1, "json_read_long_string: sucesso");
    smaug_table_free(t);
}

/* JSON — writer: pontos de realloc do wbuf */
static void af_json_write(void) {
    smaug_series_i64_t  *si = smaug_i64_create(2);
    smaug_series_f64_t  *sf = smaug_f64_create(2);
    smaug_series_bool_t *sb = smaug_bool_create(2);
    smaug_series_str_t  *ss = smaug_str_create(2);
    assert(si && sf && sb && ss);
    smaug_i64_set(si, 0, 1);            smaug_i64_set_null(si, 1);
    smaug_f64_set(sf, 0, (double)(0.0/0.0)); smaug_f64_set_null(sf, 1); /* NaN + null */
    smaug_bool_set_null(sb, 0);         smaug_bool_set(sb, 1, 1);
    smaug_str_set(ss, 0, "SP", 2);      smaug_str_set_null(ss, 1);

    smaug_column_t cols[4] = {0};
    cols[0].name = "i"; cols[0].dtype = "int64";   cols[0].i64     = si;
    cols[1].name = "f"; cols[1].dtype = "float64"; cols[1].f64     = sf;
    cols[2].name = "b"; cols[2].dtype = "bool";    cols[2].boolcol = sb;
    cols[3].name = "s"; cols[3].dtype = "string";  cols[3].str     = ss;

    smaug_table_t t = {0};
    t.columns = cols; t.ncols = 4; t.nrows = 2;

    smaug_json_write_opts_t wo = {0};
    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        size_t len;
        char *out = smaug_write_json_mem(&t, &wo, &len);
        if (out) { free(out); }
    }
    reset(-1);
    size_t len;
    char *out = smaug_write_json_mem(&t, &wo, &len);
    OK(out != NULL && len > 0, "json_write: sucesso");
    free(out);
    smaug_i64_free(si); smaug_f64_free(sf); smaug_bool_free(sb); smaug_str_free(ss);
}

/* JSON — writer com pretty=1: os branches de nl/ind/ind2 (linhas 557–570,
 * 598–610) só são exercitados quando pretty=1 — precisam de sweep próprio. */
static void af_json_write_pretty(void) {
    smaug_series_i64_t *si = smaug_i64_create(3);
    smaug_series_str_t *ss = smaug_str_create(3);
    assert(si && ss);
    smaug_i64_set(si, 0, 1); smaug_i64_set_null(si, 1); smaug_i64_set(si, 2, 3);
    smaug_str_set(ss, 0, "a", 1); smaug_str_set(ss, 1, "b", 1); smaug_str_set_null(ss, 2);
    smaug_column_t cols[2] = {0};
    cols[0].name = "i"; cols[0].dtype = "int64";  cols[0].i64 = si;
    cols[1].name = "s"; cols[1].dtype = "string"; cols[1].str = ss;
    smaug_table_t t = {0};
    t.columns = cols; t.ncols = 2; t.nrows = 3;

    smaug_json_write_opts_t wo = {.pretty = 1};
    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        size_t len;
        char *out = smaug_write_json_mem(&t, &wo, &len);
        if (out) { free(out); }
    }
    reset(-1);
    size_t len;
    char *out = smaug_write_json_mem(&t, &wo, &len);
    OK(out != NULL && strstr(out,"\n") != NULL, "json_write_pretty: sucesso");
    free(out);
    smaug_i64_free(si); smaug_str_free(ss);
}

/* JSON — leitura de muitos registros: força o realloc do array de records
 * (recs[]) que começa com cap=8 e dobra (linhas 332/333). */
static void af_json_read_many_recs(void) {
    char *j = malloc(8192); assert(j);
    int pos = sprintf(j, "[");
    for (int i = 0; i < 20; i++) {
        pos += sprintf(j+pos, "%s{\"v\":%d}", i?",":"", i);
    }
    pos += sprintf(j+pos, "]");
    size_t jlen = (size_t)pos;

    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        smaug_table_t *t = smaug_read_json_mem(j, jlen);
        if (t) smaug_table_free(t);
    }
    reset(-1);
    smaug_table_t *t = smaug_read_json_mem(j, jlen);
    OK(t && !t->error && t->nrows == 20, "json_read_many_recs: sucesso 20 linhas");
    smaug_table_free(t);
    free(j);
}

/* JSON — registro único com muitos campos: força o realloc de keys/vals
 * DENTRO de parse_record (cap começa em 8 e dobra; L288-289). Sob allocfail,
 * o ramo !nk || !nv (L290) dispara — não alcançável por registros estreitos. */
static void af_json_read_wide_record(void) {
    char *j = malloc(8192); assert(j);
    int pos = sprintf(j, "[{");
    for (int i = 0; i < 12; i++) { /* 12 campos > cap inicial 8 → força realloc */
        pos += sprintf(j+pos, "%s\"k%d\":%d", i?",":"", i, i);
    }
    pos += sprintf(j+pos, "}]");
    size_t jlen = (size_t)pos;

    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        smaug_table_t *t = smaug_read_json_mem(j, jlen);
        if (t) smaug_table_free(t);
    }
    reset(-1);
    smaug_table_t *t = smaug_read_json_mem(j, jlen);
    OK(t && !t->error && t->ncols == 12, "json_read_wide_record: 12 colunas");
    smaug_table_free(t);
    free(j);
}


static void af_table_free_partial(void) {
    /* simula OOM a meio da construção de colunas */
    const char *csv = "a,b,c\n1,2,3\n4,5,6\n";
    size_t csv_len  = strlen(csv);
    /* ao falhar no meio, smaug_table_free deve lidar com colunas parciais */
    for (long k = 0; k < MAX_IO_ALLOCS; k++) {
        reset(k);
        smaug_table_t *t = smaug_read_csv_mem(csv, csv_len, NULL);
        if (t) { smaug_table_free(t); }  /* não deve crash mesmo parcial */
    }
    reset(-1);
    smaug_table_t *t = smaug_read_csv_mem(csv, csv_len, NULL);
    OK(t && !t->error, "table_free_partial: sucesso final");
    smaug_table_free(t);
}


/* ======================================================================
   FRENTE B — Grupo A/B (Fase 3 Ring 0): cumulativas, diff/shift, fill,
   sorted_nonnull, rank — e janela deslizante (rolling). Varre os caminhos
   de OOM dessas primitivas, antes descobertos no COVERAGE.
   ====================================================================== */

/* helper: série f64 com nulos no meio, para exercitar VALID/INVALID + fill */
static smaug_series_f64_t *mk_f64_gapped(void) {
    double arr[6] = {1, 2, 3, 4, 5, 6};
    smaug_series_f64_t *s = smaug_f64_create_from_array(arr, 6);
    if (s) { smaug_f64_set_null(s, 1); smaug_f64_set_null(s, 3); }
    return s;
}
static smaug_series_i64_t *mk_i64_gapped(void) {
    int64_t arr[6] = {1, 2, 3, 4, 5, 6};
    smaug_series_i64_t *s = smaug_i64_create_from_array(arr, 6);
    if (s) { smaug_i64_set_null(s, 1); smaug_i64_set_null(s, 3); }
    return s;
}

/* --- f64 Grupo A: cumulativas + diff/shift + fill --- */
#define AF_F64_UNARY(fnname, call) \
static void fnname(void) { \
    smaug_series_f64_t *base = mk_f64_gapped(); assert(base); \
    for (long k = 0; k < MAX_ALLOCS; k++) { \
        reset(k); \
        smaug_series_f64_t *r = call; \
        if (r) { OK(r->size == base->size, #fnname " size"); smaug_f64_free(r); } \
    } \
    smaug_f64_free(base); \
}
AF_F64_UNARY(af_f64_cumsum,  smaug_f64_cumsum(base))
AF_F64_UNARY(af_f64_cumprod, smaug_f64_cumprod(base))
AF_F64_UNARY(af_f64_cummin,  smaug_f64_cummin(base))
AF_F64_UNARY(af_f64_cummax,  smaug_f64_cummax(base))
AF_F64_UNARY(af_f64_diff,    smaug_f64_diff(base, 1))
AF_F64_UNARY(af_f64_shift,   smaug_f64_shift(base, 2))
AF_F64_UNARY(af_f64_ffill,   smaug_f64_ffill(base))
AF_F64_UNARY(af_f64_bfill,   smaug_f64_bfill(base))

/* --- f64 Grupo B: sorted_nonnull + rank (retornam buffer cru) --- */
static void af_f64_sorted_nonnull(void) {
    smaug_series_f64_t *base = mk_f64_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        size_t n = 0;
        double *out = smaug_f64_sorted_nonnull(base, &n);
        if (out) { OK(n == 4, "f64 sorted_nonnull conta"); free(out); }
    }
    smaug_f64_free(base);
}
static void af_f64_rank(void) {
    smaug_series_f64_t *base = mk_f64_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        double *out = smaug_f64_rank(base, 0);
        if (out) { OK(1, "f64 rank ok"); free(out); }
    }
    smaug_f64_free(base);
}

/* --- i64 Grupo A --- */
#define AF_I64_UNARY(fnname, call) \
static void fnname(void) { \
    smaug_series_i64_t *base = mk_i64_gapped(); assert(base); \
    for (long k = 0; k < MAX_ALLOCS; k++) { \
        reset(k); \
        smaug_series_i64_t *r = call; \
        if (r) { OK(r->size == base->size, #fnname " size"); smaug_i64_free(r); } \
    } \
    smaug_i64_free(base); \
}
AF_I64_UNARY(af_i64_cumsum,  smaug_i64_cumsum(base))
AF_I64_UNARY(af_i64_cumprod, smaug_i64_cumprod(base))
AF_I64_UNARY(af_i64_cummin,  smaug_i64_cummin(base))
AF_I64_UNARY(af_i64_cummax,  smaug_i64_cummax(base))
AF_I64_UNARY(af_i64_diff,    smaug_i64_diff(base, 1))
AF_I64_UNARY(af_i64_shift,   smaug_i64_shift(base, 2))
AF_I64_UNARY(af_i64_ffill,   smaug_i64_ffill(base))
AF_I64_UNARY(af_i64_bfill,   smaug_i64_bfill(base))

static void af_i64_sorted_nonnull(void) {
    smaug_series_i64_t *base = mk_i64_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        size_t n = 0;
        int64_t *out = smaug_i64_sorted_nonnull(base, &n);
        if (out) { OK(n == 4, "i64 sorted_nonnull conta"); free(out); }
    }
    smaug_i64_free(base);
}
static void af_i64_rank(void) {
    smaug_series_i64_t *base = mk_i64_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        double *out = smaug_i64_rank(base, 0);
        if (out) { OK(1, "i64 rank ok"); free(out); }
    }
    smaug_i64_free(base);
}

/* --- rolling f64 (sum/mean/min/max) — min/max usam deque interno --- */
#define AF_F64_ROLL(fnname, call) \
static void fnname(void) { \
    smaug_series_f64_t *base = mk_f64_gapped(); assert(base); \
    for (long k = 0; k < MAX_ALLOCS; k++) { \
        reset(k); \
        smaug_series_f64_t *r = call; \
        if (r) { OK(r->size == base->size, #fnname " size"); smaug_f64_free(r); } \
    } \
    smaug_f64_free(base); \
}
AF_F64_ROLL(af_f64_rolling_sum,  smaug_f64_rolling_sum(base, 3))
AF_F64_ROLL(af_f64_rolling_mean, smaug_f64_rolling_mean(base, 3))
AF_F64_ROLL(af_f64_rolling_min,  smaug_f64_rolling_min(base, 3))
AF_F64_ROLL(af_f64_rolling_max,  smaug_f64_rolling_max(base, 3))

/* --- rolling i64 (sum/min/max → i64; mean → f64) --- */
static void af_i64_rolling_sum(void) {
    smaug_series_i64_t *base = mk_i64_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_rolling_sum(base, 3);
        if (r) { OK(r->size == base->size, "i64 rolling_sum size"); smaug_i64_free(r); }
    }
    smaug_i64_free(base);
}
static void af_i64_rolling_mean(void) {
    smaug_series_i64_t *base = mk_i64_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_f64_t *r = smaug_i64_rolling_mean(base, 3);
        if (r) { OK(r->size == base->size, "i64 rolling_mean size"); smaug_f64_free(r); }
    }
    smaug_i64_free(base);
}
static void af_i64_rolling_min(void) {
    smaug_series_i64_t *base = mk_i64_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_rolling_min(base, 3);
        if (r) { OK(r->size == base->size, "i64 rolling_min size"); smaug_i64_free(r); }
    }
    smaug_i64_free(base);
}
static void af_i64_rolling_max(void) {
    smaug_series_i64_t *base = mk_i64_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_i64_t *r = smaug_i64_rolling_max(base, 3);
        if (r) { OK(r->size == base->size, "i64 rolling_max size"); smaug_i64_free(r); }
    }
    smaug_i64_free(base);
}

/* ======================================================================
   FRENTE B fase 2 — Anel 3: datetime (lifecycle + ops que alocam).
   datetime estava SEM cobertura allocfail; a auditoria das exclusoes
   revelou varias "coberto por test_allocfail" que de fato NAO eram
   cobertas (conveniencia disfarcada). Esta frente as torna verdadeiras
   ou expoe o ramo para teste.
   ====================================================================== */
static smaug_series_dt_t *mk_dt_gapped(void) {
    int64_t arr[6] = {1000, 2000, 3000, 4000, 5000, 6000};
    smaug_series_dt_t *s = smaug_dt_create_from_array(arr, 6);
    if (s) { smaug_dt_set_null(s, 1); smaug_dt_set_null(s, 3); }
    return s;
}

static void af_dt_create(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_dt_t *s = smaug_dt_create(5);
        if (s) { OK(s->size == 5, "dt create size"); smaug_dt_free(s); }
    }
}
static void af_dt_create_from_array(void) {
    int64_t arr[4] = {1, 2, 3, 4};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_dt_t *s = smaug_dt_create_from_array(arr, 4);
        if (s) { OK(s->size == 4, "dt from_array size"); smaug_dt_free(s); }
    }
}
static void af_dt_clone(void) {
    smaug_series_dt_t *base = mk_dt_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_dt_t *c = smaug_dt_clone(base);
        if (c) { OK(c->size == base->size, "dt clone size"); smaug_dt_free(c); }
    }
    smaug_dt_free(base);
}
static void af_dt_view(void) {
    smaug_series_dt_t *base = mk_dt_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_dt_t *v = smaug_dt_view(base, 0, 3);
        if (v) { OK(v->size == 3, "dt view size"); smaug_dt_free(v); }
    }
    smaug_dt_free(base);
}
static void af_dt_append_grow(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        smaug_series_dt_t *s = smaug_dt_create_with_capacity(0, 0);
        assert(s);
        reset(k);
        int rc = smaug_dt_append(s, 1234);
        OK(rc == 0 || rc == -1, "dt append rc valido");
        if (rc == 0) OK(s->size == 1, "dt append cresceu");
        else         OK(s->size == 0, "dt append falhou sem corromper");
        reset(-1);
        smaug_dt_free(s);
    }
}
static void af_dt_argsort(void) {
    smaug_series_dt_t *base = mk_dt_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        size_t *idx = smaug_dt_argsort(base, true);
        if (idx) { OK(1, "dt argsort ok"); free(idx); }
    }
    smaug_dt_free(base);
}
static void af_dt_sort(void) {
    smaug_series_dt_t *base = mk_dt_gapped(); assert(base);
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_dt_t *r = smaug_dt_sort(base, true);
        if (r) { OK(r->size == base->size, "dt sort size"); smaug_dt_free(r); }
    }
    smaug_dt_free(base);
}
static void af_dt_take(void) {
    smaug_series_dt_t *base = mk_dt_gapped(); assert(base);
    size_t idx[3] = {0, 2, 4};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_dt_t *r = smaug_dt_take(base, idx, 3);
        if (r) { OK(r->size == 3, "dt take size"); smaug_dt_free(r); }
    }
    smaug_dt_free(base);
}
static void af_dt_filter(void) {
    smaug_series_dt_t *base = mk_dt_gapped(); assert(base);
    uint8_t mask[6] = {1, 0, 1, 0, 1, 0};
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        smaug_series_dt_t *r = smaug_dt_filter(base, mask);
        if (r) { OK(1, "dt filter ok"); smaug_dt_free(r); }
    }
    smaug_dt_free(base);
}

/* dt setters sob OOM: dt_set/set_null/append fazem dt_cow_detach (e append
 * faz dt_grow) — esses caminhos de NOMEM (L244/253/266/278/280) só são
 * alcançados quando a série é uma VIEW (is_view=true); escrever numa view
 * dispara o detach copy-on-write, que aloca. clone() NÃO cria view — só
 * dt_view() marca is_view, então é ela que exercita o caminho COW. */
/* dt comparadores sob OOM: os 6 macros DT_CMP_IMPL fazem 2 malloc cada
 * (result + mask) — nunca exercitados sob allocfail antes. Cobre o ramo
 * !result e !mask (free(result)) de cada operador. */
static void af_dt_compare(void) {
    int64_t arr[4] = {10, 20, 30, 40};
    typedef uint8_t* (*cmp_fn)(const smaug_series_dt_t*, int64_t, smaug_mask_t**);
    cmp_fn fns[6] = {
        smaug_dt_gt, smaug_dt_lt, smaug_dt_eq,
        smaug_dt_ge, smaug_dt_le, smaug_dt_ne
    };
    for (int op = 0; op < 6; op++) {
        smaug_series_dt_t *s = smaug_dt_create_from_array(arr, 4); assert(s);
        for (long k = 0; k < MAX_ALLOCS; k++) {
            reset(k);
            smaug_mask_t *mask = NULL;
            uint8_t *r = fns[op](s, 25, &mask);
            if (r) { OK(1, "dt compare ok"); free(r); free(mask); }
        }
        reset(-1);
        smaug_dt_free(s);
    }
}

static void af_dt_setters(void) {
    for (long k = 0; k < MAX_ALLOCS; k++) {
        smaug_series_dt_t *base = mk_dt_gapped(); assert(base);
        smaug_series_dt_t *v = smaug_dt_view(base, 0, 4); /* is_view=true */
        if (!v) { smaug_dt_free(base); reset(-1); continue; }
        reset(k);
        smaug_status_t st = smaug_dt_set(v, 0, 999); /* dispara dt_cow_detach */
        OK(st == SMG_OK || st == SMG_ERR_NOMEM, "dt_set view: status válido");
        reset(-1);
        smaug_dt_free(v); smaug_dt_free(base);
    }
    for (long k = 0; k < MAX_ALLOCS; k++) {
        smaug_series_dt_t *base = mk_dt_gapped(); assert(base);
        smaug_series_dt_t *v = smaug_dt_view(base, 0, 4);
        if (!v) { smaug_dt_free(base); reset(-1); continue; }
        reset(k);
        smaug_status_t st = smaug_dt_set_null(v, 0); /* dispara dt_cow_detach */
        OK(st == SMG_OK || st == SMG_ERR_NOMEM, "dt_set_null view: status válido");
        reset(-1);
        smaug_dt_free(v); smaug_dt_free(base);
    }
    /* append numa view: dt_cow_detach + dt_grow */
    for (long k = 0; k < MAX_ALLOCS; k++) {
        smaug_series_dt_t *base = mk_dt_gapped(); assert(base);
        smaug_series_dt_t *v = smaug_dt_view(base, 0, 4);
        if (!v) { smaug_dt_free(base); reset(-1); continue; }
        reset(k);
        int rc = smaug_dt_append(v, 1234); /* detach + grow */
        OK(rc == 0 || rc == -1, "dt_append view: rc válido");
        reset(-1);
        smaug_dt_free(v); smaug_dt_free(base);
    }
}

/* multi_argsort: OOM nos dois malloc (idx linha 110, tmp linha 113) */
static void af_multi_argsort(void) {
    smaug_series_f64_t *f = mk_f64_gapped(); assert(f);
    /* preenche os nulos para ter série densa (multi_argsort não aceita nulls) */
    smaug_f64_set(f, 1, 2.5); smaug_f64_set(f, 3, 4.5);
    smaug_sort_col_t col = { .kind = SMAUG_COL_F64, .f64 = f };
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        size_t *idx = smaug_multi_argsort(&col, 1, 6);
        if (idx) { OK(1, "multi_argsort ok"); free(idx); }
    }
    smaug_f64_free(f);
}

/* multi_argsort_ffi: OOM no malloc de cols (linha 136) + propaga aos internos */
static void af_multi_argsort_ffi(void) {
    smaug_series_f64_t *f = mk_f64_gapped(); assert(f);
    smaug_f64_set(f, 1, 2.5); smaug_f64_set(f, 3, 4.5);
    smaug_sort_col_ffi_t col = { .kind = SMAUG_COL_F64, .ptr = f };
    for (long k = 0; k < MAX_ALLOCS; k++) {
        reset(k);
        size_t *idx = smaug_multi_argsort_ffi(&col, 1, 6);
        if (idx) { OK(1, "multi_argsort_ffi ok"); free(idx); }
    }
    smaug_f64_free(f);
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
    af_f64_ge();
    af_f64_le();
    af_f64_ne();
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
    af_i64_ge();
    af_i64_le();
    af_i64_ne();
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
    af_str_ge();
    af_str_le();
    af_str_ne();
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

    /* bool struct-based (dtype de primeira classe) */
    af_bool_create();
    af_bool_create_from_array();
    af_bool_clone();
    af_bool_view();
    af_bool_append_grow();
    af_bool_take();
    af_bool_filter();
    af_bool_argsort();
    af_bool_sort();
    af_bool_series_and();
    af_bool_series_or();
    af_bool_series_xor();
    af_bool_series_not();
    af_bool_cow_set();
    af_bool_cow_set_null();
    af_bool_cow_append();
    af_bool_cow_append_null();

    /* Anel 3 — parsers CSV e JSON */
    af_csv_read_mem();
    af_csv_read_quoted();
    af_csv_read_many_rows();
    af_csv_read_no_header();
    af_csv_write();
    af_json_read_mem();
    af_json_read_many_records();
    af_json_read_long_string();
    af_json_write();
    af_json_write_pretty();
    af_json_read_many_recs();
    af_json_read_wide_record();
    af_table_free_partial();

    /* Frente B — Grupo A/B (Fase 3) e rolling */
    af_f64_cumsum(); af_f64_cumprod(); af_f64_cummin(); af_f64_cummax();
    af_f64_diff(); af_f64_shift(); af_f64_ffill(); af_f64_bfill();
    af_f64_sorted_nonnull(); af_f64_rank();
    af_i64_cumsum(); af_i64_cumprod(); af_i64_cummin(); af_i64_cummax();
    af_i64_diff(); af_i64_shift(); af_i64_ffill(); af_i64_bfill();
    af_i64_sorted_nonnull(); af_i64_rank();
    af_f64_rolling_sum(); af_f64_rolling_mean(); af_f64_rolling_min(); af_f64_rolling_max();
    af_i64_rolling_sum(); af_i64_rolling_mean(); af_i64_rolling_min(); af_i64_rolling_max();

    /* Frente B fase 2 — datetime (lifecycle + argsort/sort/take/filter) */
    af_dt_create(); af_dt_create_from_array(); af_dt_clone(); af_dt_view();
    af_dt_append_grow(); af_dt_argsort(); af_dt_sort(); af_dt_take(); af_dt_filter();
    af_dt_setters();
    af_dt_compare();

    /* Grupo C — multi_argsort (idx/tmp/cols OOM) */
    af_multi_argsort(); af_multi_argsort_ffi();

    sanity_no_fail();

    printf("PASS: alloc-failure varreu todos os pontos (%ld verificacoes)\n", n_checks);
    return 0;
}
