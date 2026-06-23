/* tests/test_stress.c
 *
 * Testes de stress do Smaug — régua v1.0.
 *
 * Objetivo: aumentar a confiança com datasets grandes, operações encadeadas,
 * crescimento de memória e cenários extremos. Complementa os testes unitários
 * (que usam N pequeno) e o allocfail (que prova falha graciosa) com pressão
 * real sobre a engine.
 *
 * N usados:
 *   N_LINEAR  1 000 000  — ops O(N): sum, min, max, count (rápido mesmo no Valgrind)
 *   N_SORT       50 000  — sort/argsort O(N log N) (aceitável no Valgrind)
 *   N_CHAIN      10 000  — encadeamento multi-passo
 *   N_STRING      1 000  — strings (alocação por elemento é cara)
 *   N_CYCLE      10 000  — ciclos de create/free
 *
 * Compilar e rodar:
 *   gcc -std=c11 -g -O0 -I./include \
 *       tests/test_stress.c src/smaug_core.c src/smaug_ops_f64.c \
 *       src/smaug_ops_i64.c src/smaug_ops_bool.c src/smaug_str.c \
 *       src/smaug_ops_str.c -lm -o build/test_stress
 *   valgrind --leak-check=full --error-exitcode=1 ./build/test_stress
 */

#include "../include/smaug.h"
#include <assert.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Verificação que NÃO some sob -DNDEBUG (ver nota em test_cow.c). */
#undef assert
#define assert(cond) do { if (!(cond)) { \
    fprintf(stderr, "FALHOU [%s:%d]: %s\n", __FILE__, __LINE__, #cond); \
    exit(1); } n_checks++; } while (0)

#define N_LINEAR  1000000
#define N_SORT      50000
#define N_CHAIN     10000
#define N_STRING     1000
#define N_CYCLE     10000

static long n_checks = 0;
#define OK(cond, msg) do { if (!(cond)) { \
    fprintf(stderr, "FALHOU: %s\n", msg); exit(1); } n_checks++; } while (0)

/* ======================================================================
   f64 — operações lineares com N=1M
   Prova: criação, set em massa, reduções e count sem leak ou crash.
   Corretude: [0..N-1]; sum = N*(N-1)/2; min=0; max=N-1; count=N.
   ====================================================================== */
static void f64_large_linear(void) {
    const size_t N = N_LINEAR;
    smaug_series_f64_t *s = smaug_f64_create(N);
    OK(s != NULL, "f64 large: create ok");
    OK(s->size == N, "f64 large: size correto");

    for (size_t i = 0; i < N; i++)
        smaug_f64_set(s, i, (double)i);

    double expected_sum = (double)N * ((double)N - 1.0) / 2.0;
    OK(smaug_f64_sum(s, true) == expected_sum, "f64 large: sum correto");
    OK(smaug_f64_min(s, true) == 0.0,          "f64 large: min = 0");
    OK(smaug_f64_max(s, true) == (double)(N-1),"f64 large: max = N-1");
    OK(smaug_f64_count_nonnull(s) == N,         "f64 large: count = N");

    /* NULL intercalado: marca 10% de NULLs e refaz count */
    size_t n_null = N / 10;
    for (size_t i = 0; i < n_null; i++)
        smaug_f64_set_null(s, i * 10);
    OK(smaug_f64_count_nonnull(s) == N - n_null, "f64 large: count com NULLs");

    smaug_f64_free(s);
}

/* ======================================================================
   f64 — sort e argsort com N=50k
   Prova: ordem correta após sort, argsort inverte corretamente.
   ====================================================================== */
static void f64_sort_medium(void) {
    const size_t N = N_SORT;

    /* cria série em ordem REVERSA: [N-1, N-2, ..., 1, 0] */
    smaug_series_f64_t *s = smaug_f64_create(N);
    OK(s != NULL, "f64 sort medium: create ok");
    for (size_t i = 0; i < N; i++)
        smaug_f64_set(s, i, (double)(N - 1 - i));

    /* sort crescente */
    smaug_series_f64_t *sorted = smaug_f64_sort(s, true);
    OK(sorted != NULL,                     "f64 sort medium: sort ok");
    OK(sorted->size == N,                  "f64 sort medium: size preservado");
    OK(smaug_f64_get(sorted, 0,    NULL) == 0.0,          "f64 sort medium: [0] = 0");
    OK(smaug_f64_get(sorted, N-1,  NULL) == (double)(N-1),"f64 sort medium: [N-1] = N-1");
    OK(smaug_f64_get(sorted, N/2,  NULL) == (double)(N/2),"f64 sort medium: [N/2] correto");
    smaug_f64_free(sorted);

    /* argsort: índice 0 do resultado deve ser N-1 (maior elemento = primeiro após sort desc) */
    size_t *idx = smaug_f64_argsort(s, false);   /* decrescente */
    OK(idx != NULL,    "f64 sort medium: argsort ok");
    OK(idx[0] == 0,    "f64 argsort desc: [0] = índice do maior (pos 0 = N-1)");
    OK(idx[N-1] == N-1,"f64 argsort desc: [N-1] = índice do menor");
    free(idx);

    smaug_f64_free(s);
}

/* ======================================================================
   f64 — append intenso a partir de série vazia (stress de grow)
   Prova: N appends forçam múltiplos reallocs; invariantes preservados.
   ====================================================================== */
static void f64_append_stress(void) {
    const size_t N = N_SORT;   /* 50k appends */
    smaug_series_f64_t *s = smaug_f64_create_with_capacity(0, 0);
    OK(s != NULL, "f64 append stress: create ok");

    for (size_t i = 0; i < N; i++) {
        int rc = (i % 10 == 0)
            ? smaug_f64_append_null(s)
            : smaug_f64_append(s, (double)i);
        OK(rc == 0, "f64 append stress: append ok");
    }
    OK(s->size == N,          "f64 append stress: size = N");
    OK(s->capacity >= N,      "f64 append stress: capacity >= N");
    /* elementos com i%10==0 são null: índice 0, 10, 20, ... */
    OK(smaug_f64_is_null(s, 0),      "f64 append stress: [0] null (i=0, multiplo de 10)");
    OK(smaug_f64_is_null(s, 10),     "f64 append stress: [10] null");
    OK(!smaug_f64_is_null(s, N-1),   "f64 append stress: último não é null (49999%10=9)");
    /* o elemento 1 (não-null, valor=1.0) */
    OK(smaug_f64_get(s, 1, NULL) == 1.0, "f64 append stress: [1] = 1.0");

    smaug_f64_free(s);
}

/* ======================================================================
   f64 — encadeamento de operações: create → filter → sort → take
   Prova: resultado final coerente, sem acumulação de memória.
   ====================================================================== */
static void f64_chained_ops(void) {
    const size_t N = N_CHAIN;

    /* série [0, 1, ..., N-1] */
    smaug_series_f64_t *base = smaug_f64_create(N);
    OK(base != NULL, "f64 chain: create ok");
    for (size_t i = 0; i < N; i++)
        smaug_f64_set(base, i, (double)i);

    /* filter: mantém apenas os pares (máscara 1/0 alternada) */
    uint8_t *mask = malloc(N);
    OK(mask != NULL, "f64 chain: alloc mask");
    for (size_t i = 0; i < N; i++) mask[i] = (i % 2 == 0) ? 1 : 0;

    smaug_series_f64_t *filtered = smaug_f64_filter(base, mask);
    free(mask);
    OK(filtered != NULL,           "f64 chain: filter ok");
    OK(filtered->size == N / 2,    "f64 chain: filter size = N/2");

    /* sort crescente sobre o filtrado (já está ordenado, mas exercita o código) */
    smaug_series_f64_t *sorted = smaug_f64_sort(filtered, true);
    OK(sorted != NULL, "f64 chain: sort ok");
    smaug_f64_free(filtered);

    /* take: pega os 3 primeiros */
    size_t take_idx[3] = {0, 1, 2};
    smaug_series_f64_t *taken = smaug_f64_take(sorted, take_idx, 3);
    OK(taken != NULL,                    "f64 chain: take ok");
    OK(taken->size == 3,                 "f64 chain: take size=3");
    OK(smaug_f64_get(taken, 0, NULL) == 0.0, "f64 chain: take[0] = 0");
    OK(smaug_f64_get(taken, 1, NULL) == 2.0, "f64 chain: take[1] = 2 (pares)");
    OK(smaug_f64_get(taken, 2, NULL) == 4.0, "f64 chain: take[2] = 4 (pares)");

    smaug_f64_free(sorted);
    smaug_f64_free(taken);
    smaug_f64_free(base);
}

/* ======================================================================
   i64 — operações lineares com N=1M
   ====================================================================== */
static void i64_large_linear(void) {
    const size_t N = N_LINEAR;
    smaug_series_i64_t *s = smaug_i64_create(N);
    OK(s != NULL, "i64 large: create ok");

    for (size_t i = 0; i < N; i++)
        smaug_i64_set(s, i, (int64_t)i);

    /* sum = N*(N-1)/2; para N=1M cabe em int64_t (max ~4.6×10^17) */
    int64_t expected = (int64_t)N * ((int64_t)N - 1) / 2;
    OK(smaug_i64_sum(s, true) == expected, "i64 large: sum correto");
    OK(smaug_i64_min(s, true) == 0,        "i64 large: min = 0");
    OK(smaug_i64_max(s, true) == (int64_t)(N-1), "i64 large: max = N-1");
    OK(smaug_i64_count_nonnull(s) == N,    "i64 large: count = N");

    /* clone: verificar independência em escala */
    smaug_series_i64_t *c = smaug_i64_clone(s);
    OK(c != NULL,                "i64 large: clone ok");
    OK(c->data != s->data,       "i64 large: clone independente");
    OK(c->size == N,             "i64 large: clone size = N");
    smaug_i64_set(c, 0, -1);
    OK(smaug_i64_get(s, 0, NULL) == 0, "i64 large: original intacto após clone-set");
    smaug_i64_free(c);

    smaug_i64_free(s);
}

/* ======================================================================
   COW stress: N views, cada uma recebe um set (detach independente)
   Prova: pai inalterado após N detachs, sem leak.
   ====================================================================== */
static void view_cow_stress(void) {
    const size_t N_PAI  = 1000;
    const size_t N_VIEWS = 200;   /* janelas de 5 elementos cada */
    const size_t WIN    = 5;

    smaug_series_f64_t *pai = smaug_f64_create(N_PAI);
    OK(pai != NULL, "cow stress: pai ok");
    for (size_t i = 0; i < N_PAI; i++)
        smaug_f64_set(pai, i, (double)i);

    smaug_series_f64_t **views = malloc(N_VIEWS * sizeof(*views));
    OK(views != NULL, "cow stress: alloc views ok");

    /* cria todas as views antes de qualquer escrita */
    for (size_t i = 0; i < N_VIEWS; i++) {
        size_t start = (i * WIN) % (N_PAI - WIN);
        views[i] = smaug_f64_view(pai, start, WIN);
        OK(views[i] != NULL, "cow stress: view criada");
    }

    /* escreve em todas as views (cada uma faz COW detach) */
    for (size_t i = 0; i < N_VIEWS; i++) {
        smaug_status_t rc = smaug_f64_set(views[i], 0, -1.0);
        OK(rc == SMG_OK,                          "cow stress: set ok");
        OK(views[i]->meta.is_view == false,       "cow stress: view detachada");
        OK(smaug_f64_get(views[i], 0, NULL) == -1.0, "cow stress: valor escrito");
    }

    /* pai inalterado: nenhum elemento é -1.0 */
    bool pai_ok = true;
    for (size_t i = 0; i < N_PAI; i++)
        if (smaug_f64_get(pai, i, NULL) != (double)i) { pai_ok = false; break; }
    OK(pai_ok, "cow stress: pai completamente preservada");

    for (size_t i = 0; i < N_VIEWS; i++)
        smaug_f64_free(views[i]);
    free(views);
    smaug_f64_free(pai);
}

/* ======================================================================
   String — lifecycle e sort em escala
   ====================================================================== */
static void str_medium(void) {
    const size_t N = N_STRING;
    const char *words[4] = {"zebra", "apple", "mango", "banana"};

    smaug_series_str_t *s = smaug_str_create(N);
    OK(s != NULL, "str medium: create ok");

    for (size_t i = 0; i < N; i++) {
        const char *w = words[i % 4];
        int rc = smaug_str_set(s, i, w, strlen(w));
        OK(rc == 0, "str medium: set ok");
    }
    OK(smaug_str_count_nonnull(s) == N, "str medium: count = N");

    /* sort: após sort, [0] == "apple" (menor lexicograficamente) */
    smaug_series_str_t *sorted = smaug_str_sort(s, true);
    OK(sorted != NULL, "str medium: sort ok");
    size_t l = 0;
    const char *first = smaug_str_get(sorted, 0, &l);
    OK(first != NULL && l == 5 && memcmp(first, "apple", 5) == 0,
       "str medium: sort[0] = apple");

    /* clone: independente */
    smaug_series_str_t *c = smaug_str_clone(s);
    OK(c != NULL && c->size == N, "str medium: clone ok");
    smaug_str_free(c);

    smaug_str_free(sorted);
    smaug_str_free(s);
}

/* ======================================================================
   Ciclos de create/clone/free — verifica ausência de acumulação
   ====================================================================== */
static void alloc_free_cycles(void) {
    const size_t N = 100;   /* tamanho da série por ciclo */
    const size_t C = N_CYCLE; /* número de ciclos */

    for (size_t c = 0; c < C; c++) {
        smaug_series_f64_t *s = smaug_f64_create(N);
        assert(s);
        for (size_t i = 0; i < N; i++) smaug_f64_set(s, i, (double)i);

        smaug_series_f64_t *cl = smaug_f64_clone(s);
        assert(cl);

        smaug_series_f64_t *v = smaug_f64_view(s, 0, N / 2);
        assert(v);

        /* COW detach na view */
        smaug_f64_set(v, 0, -1.0);

        smaug_f64_free(v);
        smaug_f64_free(cl);
        smaug_f64_free(s);
    }
    OK(1, "alloc_free_cycles: completou sem crash");
}

/* ======================================================================
   main
   ====================================================================== */
int main(void) {
    printf("stress: f64 large linear (N=%d)...\n", N_LINEAR);
    f64_large_linear();

    printf("stress: f64 sort medium (N=%d)...\n", N_SORT);
    f64_sort_medium();

    printf("stress: f64 append (N=%d)...\n", N_SORT);
    f64_append_stress();

    printf("stress: f64 chained ops (N=%d)...\n", N_CHAIN);
    f64_chained_ops();

    printf("stress: i64 large linear (N=%d)...\n", N_LINEAR);
    i64_large_linear();

    printf("stress: COW views (N_views=%d)...\n", 200);
    view_cow_stress();

    printf("stress: string medium (N=%d)...\n", N_STRING);
    str_medium();

    printf("stress: alloc/free cycles (N=%d)...\n", N_CYCLE);
    alloc_free_cycles();

    printf("PASS: stress (%ld checks)\n", n_checks);
    return 0;
}
