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
#define assert(condition) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU [%s:%d]: %s\n", __FILE__, __LINE__, #condition); \
    exit(1); } passed_checks++; } while (0)

#define N_LINEAR  1000000
#define N_SORT      50000
#define N_CHAIN     10000
#define N_STRING     1000
#define N_CYCLE     10000

static long passed_checks = 0;
#define OK(condition, message) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU: %s\n", message); exit(1); } passed_checks++; } while (0)

/* ======================================================================
   f64 — operações lineares com N=1M
   Prova: criação, set em massa, reduções e count sem leak ou crash.
   Corretude: [0..N-1]; sum = N*(N-1)/2; min=0; max=N-1; count=N.
   ====================================================================== */
static void float64_large_linear(void) {
    const size_t element_count = N_LINEAR;
    smaug_series_f64_t *floating_point_series = smaug_f64_create(element_count);
    OK(floating_point_series != NULL, "f64 large: create ok");
    OK(floating_point_series->size == element_count, "f64 large: size correto");

    for (size_t row_index = 0; row_index < element_count; row_index++)
        smaug_f64_set(floating_point_series, row_index, (double)row_index);

    double expected_sum = (double)element_count * ((double)element_count - 1.0) / 2.0;
    OK(smaug_f64_sum(floating_point_series, true) == expected_sum, "f64 large: sum correto");
    OK(smaug_f64_min(floating_point_series, true) == 0.0,          "f64 large: min = 0");
    OK(smaug_f64_max(floating_point_series, true) == (double)(element_count-1),"f64 large: max = N-1");
    OK(smaug_f64_count_nonnull(floating_point_series) == element_count,         "f64 large: count = N");

    /* NULL intercalado: marca 10% de NULLs e refaz count */
    size_t null_count = element_count / 10;
    for (size_t row_index = 0; row_index < null_count; row_index++)
        smaug_f64_set_null(floating_point_series, row_index * 10);
    OK(smaug_f64_count_nonnull(floating_point_series) == element_count - null_count, "f64 large: count com NULLs");

    smaug_f64_free(floating_point_series);
}

/* ======================================================================
   f64 — sort e argsort com N=50k
   Prova: ordem correta após sort, argsort inverte corretamente.
   ====================================================================== */
static void float64_sort_medium(void) {
    const size_t element_count = N_SORT;

    /* cria série em ordem REVERSA: [N-1, N-2, ..., 1, 0] */
    smaug_series_f64_t *floating_point_series = smaug_f64_create(element_count);
    OK(floating_point_series != NULL, "f64 sort medium: create ok");
    for (size_t row_index = 0; row_index < element_count; row_index++)
        smaug_f64_set(floating_point_series, row_index, (double)(element_count - 1 - row_index));

    /* sort crescente */
    smaug_series_f64_t *sorted = smaug_f64_sort(floating_point_series, true);
    OK(sorted != NULL,                     "f64 sort medium: sort ok");
    OK(sorted->size == element_count,                  "f64 sort medium: size preservado");
    OK(smaug_f64_get(sorted, 0,    NULL) == 0.0,          "f64 sort medium: [0] = 0");
    OK(smaug_f64_get(sorted, element_count-1,  NULL) == (double)(element_count-1),"f64 sort medium: [N-1] = N-1");
    OK(smaug_f64_get(sorted, element_count/2,  NULL) == (double)(element_count/2),"f64 sort medium: [N/2] correto");
    smaug_f64_free(sorted);

    /* argsort: índice 0 do resultado deve ser N-1 (maior elemento = primeiro após sort desc) */
    size_t *indices = smaug_f64_argsort(floating_point_series, false);   /* decrescente */
    OK(indices != NULL,    "f64 sort medium: argsort ok");
    OK(indices[0] == 0,    "f64 argsort desc: [0] = índice do maior (pos 0 = N-1)");
    OK(indices[element_count-1] == element_count-1,"f64 argsort desc: [N-1] = índice do menor");
    free(indices);

    smaug_f64_free(floating_point_series);
}

/* ======================================================================
   f64 — append intenso a partir de série vazia (stress de grow)
   Prova: N appends forçam múltiplos reallocs; invariantes preservados.
   ====================================================================== */
static void float64_append_stress(void) {
    const size_t element_count = N_SORT;   /* 50k appends */
    smaug_series_f64_t *floating_point_series = smaug_f64_create_with_capacity(0, 0);
    OK(floating_point_series != NULL, "f64 append stress: create ok");

    for (size_t row_index = 0; row_index < element_count; row_index++) {
        int status_code = (row_index % 10 == 0)
            ? smaug_f64_append_null(floating_point_series)
            : smaug_f64_append(floating_point_series, (double)row_index);
        OK(status_code == 0, "f64 append stress: append ok");
    }
    OK(floating_point_series->size == element_count,          "f64 append stress: size = N");
    OK(floating_point_series->capacity >= element_count,      "f64 append stress: capacity >= N");
    /* elementos com i%10==0 são null: índice 0, 10, 20, ... */
    OK(smaug_f64_is_null(floating_point_series, 0),      "f64 append stress: [0] null (i=0, multiplo de 10)");
    OK(smaug_f64_is_null(floating_point_series, 10),     "f64 append stress: [10] null");
    OK(!smaug_f64_is_null(floating_point_series, element_count-1),   "f64 append stress: último não é null (49999%10=9)");
    /* o elemento 1 (não-null, valor=1.0) */
    OK(smaug_f64_get(floating_point_series, 1, NULL) == 1.0, "f64 append stress: [1] = 1.0");

    smaug_f64_free(floating_point_series);
}

/* ======================================================================
   f64 — encadeamento de operações: create → filter → sort → take
   Prova: resultado final coerente, sem acumulação de memória.
   ====================================================================== */
static void float64_chained_ops(void) {
    const size_t element_count = N_CHAIN;

    /* série [0, 1, ..., N-1] */
    smaug_series_f64_t *floating_point_series = smaug_f64_create(element_count);
    OK(floating_point_series != NULL, "f64 chain: create ok");
    for (size_t row_index = 0; row_index < element_count; row_index++)
        smaug_f64_set(floating_point_series, row_index, (double)row_index);

    /* filter: mantém apenas os pares (máscara 1/0 alternada) */
    uint8_t *mask = malloc(element_count);
    OK(mask != NULL, "f64 chain: alloc mask");
    for (size_t row_index = 0; row_index < element_count; row_index++) mask[row_index] = (row_index % 2 == 0) ? 1 : 0;

    smaug_series_f64_t *filtered = smaug_f64_filter(floating_point_series, mask);
    free(mask);
    OK(filtered != NULL,           "f64 chain: filter ok");
    OK(filtered->size == element_count / 2,    "f64 chain: filter size = N/2");

    /* sort crescente sobre o filtrado (já está ordenado, mas exercita o código) */
    smaug_series_f64_t *sorted = smaug_f64_sort(filtered, true);
    OK(sorted != NULL, "f64 chain: sort ok");
    smaug_f64_free(filtered);

    /* take: pega os 3 primeiros */
    size_t take_index[3] = {0, 1, 2};
    smaug_series_f64_t *taken = smaug_f64_take(sorted, take_index, 3);
    OK(taken != NULL,                    "f64 chain: take ok");
    OK(taken->size == 3,                 "f64 chain: take size=3");
    OK(smaug_f64_get(taken, 0, NULL) == 0.0, "f64 chain: take[0] = 0");
    OK(smaug_f64_get(taken, 1, NULL) == 2.0, "f64 chain: take[1] = 2 (pares)");
    OK(smaug_f64_get(taken, 2, NULL) == 4.0, "f64 chain: take[2] = 4 (pares)");

    smaug_f64_free(sorted);
    smaug_f64_free(taken);
    smaug_f64_free(floating_point_series);
}

/* ======================================================================
   i64 — operações lineares com N=1M
   ====================================================================== */
static void int64_large_linear(void) {
    const size_t element_count = N_LINEAR;
    smaug_series_i64_t *integer_series = smaug_i64_create(element_count);
    OK(integer_series != NULL, "i64 large: create ok");

    for (size_t row_index = 0; row_index < element_count; row_index++)
        smaug_i64_set(integer_series, row_index, (int64_t)row_index);

    /* sum = N*(N-1)/2; para N=1M cabe em int64_t (max ~4.6×10^17) */
    int64_t expected = (int64_t)element_count * ((int64_t)element_count - 1) / 2;
    OK(smaug_i64_sum(integer_series, true) == expected, "i64 large: sum correto");
    OK(smaug_i64_min(integer_series, true) == 0,        "i64 large: min = 0");
    OK(smaug_i64_max(integer_series, true) == (int64_t)(element_count-1), "i64 large: max = N-1");
    OK(smaug_i64_count_nonnull(integer_series) == element_count,    "i64 large: count = N");

    /* clone: verificar independência em escala */
    smaug_series_i64_t *cloned_series = smaug_i64_clone(integer_series);
    OK(cloned_series != NULL,                "i64 large: clone ok");
    OK(cloned_series->data != integer_series->data,       "i64 large: clone independente");
    OK(cloned_series->size == element_count,             "i64 large: clone size = N");
    smaug_i64_set(cloned_series, 0, -1);
    OK(smaug_i64_get(integer_series, 0, NULL) == 0, "i64 large: original intacto após clone-set");
    smaug_i64_free(cloned_series);

    smaug_i64_free(integer_series);
}

/* ======================================================================
   COW stress: N views, cada uma recebe um set (detach independente)
   Prova: pai inalterado após N detachs, sem leak.
   ====================================================================== */
static void view_cow_stress(void) {
    const size_t parent_length  = 1000;
    const size_t view_count = 200;   /* janelas de 5 elementos cada */
    const size_t window_size    = 5;

    smaug_series_f64_t *parent_series = smaug_f64_create(parent_length);
    OK(parent_series != NULL, "cow stress: pai ok");
    for (size_t row_index = 0; row_index < parent_length; row_index++)
        smaug_f64_set(parent_series, row_index, (double)row_index);

    smaug_series_f64_t **views = malloc(view_count * sizeof(*views));
    OK(views != NULL, "cow stress: alloc views ok");

    /* cria todas as views antes de qualquer escrita */
    for (size_t row_index = 0; row_index < view_count; row_index++) {
        size_t start = (row_index * window_size) % (parent_length - window_size);
        views[row_index] = smaug_f64_view(parent_series, start, window_size);
        OK(views[row_index] != NULL, "cow stress: view criada");
    }

    /* escreve em todas as views (cada uma faz COW detach) */
    for (size_t row_index = 0; row_index < view_count; row_index++) {
        smaug_status_t status = smaug_f64_set(views[row_index], 0, -1.0);
        OK(status == SMG_OK,                          "cow stress: set ok");
        OK(views[row_index]->meta.is_view == false,       "cow stress: view detachada");
        OK(smaug_f64_get(views[row_index], 0, NULL) == -1.0, "cow stress: valor escrito");
    }

    /* pai inalterado: nenhum elemento é -1.0 */
    bool pai_succeeded = true;
    for (size_t row_index = 0; row_index < parent_length; row_index++)
        if (smaug_f64_get(parent_series, row_index, NULL) != (double)row_index) { pai_succeeded = false; break; }
    OK(pai_succeeded, "cow stress: pai completamente preservada");

    for (size_t row_index = 0; row_index < view_count; row_index++)
        smaug_f64_free(views[row_index]);
    free(views);
    smaug_f64_free(parent_series);
}

/* ======================================================================
   String — lifecycle e sort em escala
   ====================================================================== */
static void string_medium(void) {
    const size_t element_count = N_STRING;
    const char *words[4] = {"zebra", "apple", "mango", "banana"};

    smaug_series_str_t *source_series = smaug_str_create(element_count);
    OK(source_series != NULL, "str medium: create ok");

    for (size_t row_index = 0; row_index < element_count; row_index++) {
        const char *text_values = words[row_index % 4];
        int status_code = smaug_str_set(source_series, row_index, text_values, strlen(text_values));
        OK(status_code == 0, "str medium: set ok");
    }
    OK(smaug_str_count_nonnull(source_series) == element_count, "str medium: count = N");

    /* sort: após sort, [0] == "apple" (menor lexicograficamente) */
    smaug_series_str_t *sorted = smaug_str_sort(source_series, true);
    OK(sorted != NULL, "str medium: sort ok");
    size_t left_value = 0;
    const char *first = smaug_str_get(sorted, 0, &left_value);
    OK(first != NULL && left_value == 5 && memcmp(first, "apple", 5) == 0,
       "str medium: sort[0] = apple");

    /* clone: independente */
    smaug_series_str_t *source_series_2 = smaug_str_clone(source_series);
    OK(source_series_2 != NULL && source_series_2->size == element_count, "str medium: clone ok");
    smaug_str_free(source_series_2);

    smaug_str_free(sorted);
    smaug_str_free(source_series);
}

/* ======================================================================
   Ciclos de create/clone/free — verifica ausência de acumulação
   ====================================================================== */
static void allocation_free_cycles(void) {
    const size_t element_count = 100;   /* tamanho da série por ciclo */
    const size_t cycle_count = N_CYCLE; /* número de ciclos */

    for (size_t cloned_series = 0; cloned_series < cycle_count; cloned_series++) {
        smaug_series_f64_t *floating_point_series = smaug_f64_create(element_count);
        assert(floating_point_series);
        for (size_t row_index = 0; row_index < element_count; row_index++) smaug_f64_set(floating_point_series, row_index, (double)row_index);

        smaug_series_f64_t *cloned_series_2 = smaug_f64_clone(floating_point_series);
        assert(cloned_series_2);

        smaug_series_f64_t *series_view = smaug_f64_view(floating_point_series, 0, element_count / 2);
        assert(series_view);

        /* COW detach na view */
        smaug_f64_set(series_view, 0, -1.0);

        smaug_f64_free(series_view);
        smaug_f64_free(cloned_series_2);
        smaug_f64_free(floating_point_series);
    }
    OK(1, "alloc_free_cycles: completou sem crash");
}

/* ======================================================================
   main
   ====================================================================== */
int main(void) {
    printf("stress: f64 large linear (N=%d)...\n", N_LINEAR);
    float64_large_linear();

    printf("stress: f64 sort medium (N=%d)...\n", N_SORT);
    float64_sort_medium();

    printf("stress: f64 append (N=%d)...\n", N_SORT);
    float64_append_stress();

    printf("stress: f64 chained ops (N=%d)...\n", N_CHAIN);
    float64_chained_ops();

    printf("stress: i64 large linear (N=%d)...\n", N_LINEAR);
    int64_large_linear();

    printf("stress: COW views (N_views=%d)...\n", 200);
    view_cow_stress();

    printf("stress: string medium (N=%d)...\n", N_STRING);
    string_medium();

    printf("stress: alloc/free cycles (N=%d)...\n", N_CYCLE);
    allocation_free_cycles();

    printf("PASS: stress (%ld checks)\n", passed_checks);
    return 0;
}
