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

static long failure_allocation_index = -1;   /* índice da alocação que deve falhar (-1 = nenhuma) */
static long allocation_count   = 0;    /* alocações já vistas nesta rodada */

void *__wrap_malloc(size_t element_count) {
    if (allocation_count++ == failure_allocation_index) return NULL;
    return __real_malloc(element_count);
}
void *__wrap_realloc(void *pointer, size_t element_count) {
    if (allocation_count++ == failure_allocation_index) return NULL;
    return __real_realloc(pointer, element_count);
}
void *__wrap_calloc(size_t element_count, size_t size) {
    if (allocation_count++ == failure_allocation_index) return NULL;
    return __real_calloc(element_count, size);
}
char *__wrap_strdup(const char *text_value) {
    if (allocation_count++ == failure_allocation_index) return NULL;
    return __real_strdup(text_value);
}

static void reset(long fail_at) { failure_allocation_index = fail_at; allocation_count = 0; }

/* contador de checagens (cada iteração do loop é uma verificação) */
static long passed_checks = 0;
#define OK(condition, message) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU [fail_at=%ld]: %s\n", failure_allocation_index, message); exit(1); } \
    passed_checks++; } while (0)

/* MAX_ALLOCS: teto de varredura por operação (folga sobre o medido) */
#define MAX_ALLOCS 12

/* ======================================================================
   f64
   ====================================================================== */
static void allocation_failure_float64_create(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *floating_point_series = smaug_f64_create(5);
        /* se falhou em alguma alocação, deve ser NULL; senão, válido */
        if (floating_point_series) { OK(floating_point_series->size == 5, "f64 create size"); smaug_f64_free(floating_point_series); }
        /* se s==NULL aqui, foi por falha injetada — comportamento esperado */
    }
}

static void allocation_failure_float64_create_from_array(void) {
    double source_values[4] = {1, 2, 3, 4};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *floating_point_series = smaug_f64_create_from_array(source_values, 4);
        if (floating_point_series) { OK(smaug_f64_count_nonnull(floating_point_series) == 4, "f64 from_array conteudo"); smaug_f64_free(floating_point_series); }
    }
}

static void allocation_failure_float64_clone(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(5);
    assert(floating_point_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *cloned_series = smaug_f64_clone(floating_point_series);
        if (cloned_series) { OK(cloned_series->size == 5, "f64 clone size"); smaug_f64_free(cloned_series); }
    }
    smaug_f64_free(floating_point_series);
}

static void allocation_failure_float64_view(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(5);
    assert(floating_point_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *series_view = smaug_f64_view(floating_point_series, 0, 2);
        if (series_view) { OK(series_view->size == 2, "f64 view size"); smaug_f64_free(series_view); }
    }
    smaug_f64_free(floating_point_series);
}

static void allocation_failure_float64_append_grow(void) {
    /* cada iteração começa com série nova; append força grow (realloc) */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        smaug_series_f64_t *floating_point_series = smaug_f64_create_with_capacity(0, 0);
        assert(floating_point_series);
        reset(allocation_index);
        int status_code = smaug_f64_append(floating_point_series, 1.0);
        /* rc==0 sucesso, rc==-1 falha graciosa; em ambos a série segue consistente */
        OK(status_code == 0 || status_code == -1, "f64 append rc valido");
        if (status_code == 0) OK(floating_point_series->size == 1, "f64 append cresceu");
        else         OK(floating_point_series->size == 0, "f64 append falhou sem corromper");
        reset(-1);
        smaug_f64_free(floating_point_series);
    }
}

static void allocation_failure_float64_add(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    smaug_series_f64_t *right_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *sum_series = smaug_f64_add(left_series, right_series);
        if (sum_series) { OK(sum_series->size == 3, "f64 add size"); smaug_f64_free(sum_series); }
    }
    smaug_f64_free(left_series); smaug_f64_free(right_series);
}

static void allocation_failure_float64_add_scalar(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *add_scalar_series = smaug_f64_add_scalar(left_series, 10.0);
        if (add_scalar_series) { OK(add_scalar_series->size == 3, "f64 add_scalar size"); smaug_f64_free(add_scalar_series); }
    }
    smaug_f64_free(left_series);
}

static void allocation_failure_float64_compare(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_f64_gt(left_series, 1.5, &mask);
        /* gt aloca result E mask; se um falhar, ambos devem ser liberados internamente
           e o retorno NULL. Liberamos o que voltou não-NULL. */
        if (result) { OK(mask != NULL, "f64 gt mask junto"); free(result); free(mask); }
    }
    smaug_f64_free(left_series);
}

/* --- B1: ops aritméticas restantes (sub/mul/div série) --- */
static void allocation_failure_float64_subtract(void) {
    double left_values[3] = {4, 5, 6}, right_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(left_values, 3);
    smaug_series_f64_t *right_series = smaug_f64_create_from_array(right_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *difference_series = smaug_f64_sub(left_series, right_series);
        if (difference_series) { OK(difference_series->size == 3, "f64 sub size"); smaug_f64_free(difference_series); }
    }
    smaug_f64_free(left_series); smaug_f64_free(right_series);
}

static void allocation_failure_float64_multiply(void) {
    double left_values[3] = {4, 5, 6}, right_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(left_values, 3);
    smaug_series_f64_t *right_series = smaug_f64_create_from_array(right_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *product_series = smaug_f64_mul(left_series, right_series);
        if (product_series) { OK(product_series->size == 3, "f64 mul size"); smaug_f64_free(product_series); }
    }
    smaug_f64_free(left_series); smaug_f64_free(right_series);
}

static void allocation_failure_float64_divide(void) {
    double left_values[3] = {4, 5, 6}, right_values[3] = {1, 2, 3};   /* divisor não-nulo */
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(left_values, 3);
    smaug_series_f64_t *right_series = smaug_f64_create_from_array(right_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *quotient_series = smaug_f64_div(left_series, right_series);
        if (quotient_series) { OK(quotient_series->size == 3, "f64 div size"); smaug_f64_free(quotient_series); }
    }
    smaug_f64_free(left_series); smaug_f64_free(right_series);
}

/* --- B1: scalars restantes (sub/mul/div) --- */
static void allocation_failure_float64_subtract_scalar(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *subtract_scalar_series = smaug_f64_sub_scalar(left_series, 1.0);
        if (subtract_scalar_series) { OK(subtract_scalar_series->size == 3, "f64 sub_scalar size"); smaug_f64_free(subtract_scalar_series); }
    }
    smaug_f64_free(left_series);
}

static void allocation_failure_float64_multiply_scalar(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *multiply_scalar_series = smaug_f64_mul_scalar(left_series, 2.0);
        if (multiply_scalar_series) { OK(multiply_scalar_series->size == 3, "f64 mul_scalar size"); smaug_f64_free(multiply_scalar_series); }
    }
    smaug_f64_free(left_series);
}

static void allocation_failure_float64_divide_scalar(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *divide_scalar_series = smaug_f64_div_scalar(left_series, 2.0);   /* scalar não-nulo */
        if (divide_scalar_series) { OK(divide_scalar_series->size == 3, "f64 div_scalar size"); smaug_f64_free(divide_scalar_series); }
    }
    smaug_f64_free(left_series);
}

/* --- B1: compares restantes (lt/eq); gt já coberto em af_f64_compare --- */
static void allocation_failure_float64_less_than(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_f64_lt(left_series, 1.5, &mask);
        if (result) { OK(mask != NULL, "f64 lt mask junto"); free(result); free(mask); }
    }
    smaug_f64_free(left_series);
}

static void allocation_failure_float64_equal(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_f64_eq(left_series, 2.0, &mask);
        if (result) { OK(mask != NULL, "f64 eq mask junto"); free(result); free(mask); }
    }
    smaug_f64_free(left_series);
}

static void allocation_failure_float64_greater_or_equal(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_f64_ge(left_series, 2.0, &mask);
        if (result) { OK(mask != NULL, "f64 ge mask junto"); free(result); free(mask); }
    }
    smaug_f64_free(left_series);
}
static void allocation_failure_float64_less_or_equal(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_f64_le(left_series, 2.0, &mask);
        if (result) { OK(mask != NULL, "f64 le mask junto"); free(result); free(mask); }
    }
    smaug_f64_free(left_series);
}
/* 10.3 fatia A: as seis matematicas. Uma varredura por funcao -- sao corpos
   distintos apos a expansao da macro, entao cada uma tem seus proprios pontos
   de alocacao. Tabela em vez de seis funcoes iguais. */
/* 10.3 fatia B: abs/round/clip. As i64 podem liberar o resultado a meio caminho
   (INT64_MIN em abs, overflow em round) -- caminho que so aparece sob OOM se o
   alloc passar e a validacao falhar depois. */
static void allocation_failure_math_dtype_preserving(void) {
    double  source_values[3] = {-1.5, 2.5, 3.0};
    int64_t source_values_2[3] = {-15, 25, 30};
    reset(-1);
    smaug_series_f64_t *floating_point_series = smaug_f64_create_from_array(source_values, 3);
    smaug_series_i64_t *integer_series = smaug_i64_create_from_array(source_values_2, 3);
    assert(floating_point_series && integer_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_status_t status;
        smaug_series_f64_t *abs_series = smaug_f64_abs(floating_point_series);
        if (abs_series) { OK(abs_series->size == 3, "f64 abs ok"); smaug_f64_free(abs_series); }
        smaug_series_f64_t *round_series = smaug_f64_round(floating_point_series, 1);
        if (round_series) { OK(round_series->size == 3, "f64 round ok"); smaug_f64_free(round_series); }
        smaug_series_f64_t *clip_series = smaug_f64_clip(floating_point_series, -1, true, 1, true, &status);
        if (clip_series) { OK(clip_series->size == 3, "f64 clip ok"); smaug_f64_free(clip_series); }
        smaug_series_i64_t *abs_series_2 = smaug_i64_abs(integer_series, &status);
        if (abs_series_2) { OK(abs_series_2->size == 3, "i64 abs ok"); smaug_i64_free(abs_series_2); }
        smaug_series_i64_t *round_series_2 = smaug_i64_round(integer_series, -1, &status);
        if (round_series_2) { OK(round_series_2->size == 3, "i64 round ok"); smaug_i64_free(round_series_2); }
        smaug_series_i64_t *clip_series_2 = smaug_i64_clip(integer_series, -10, true, 10, true, &status);
        if (clip_series_2) { OK(clip_series_2->size == 3, "i64 clip ok"); smaug_i64_free(clip_series_2); }
    }
    smaug_f64_free(floating_point_series); smaug_i64_free(integer_series);
}
static void allocation_failure_float64_math(void) {
    typedef smaug_series_f64_t *(*mathfn)(const smaug_series_f64_t *);
    mathfn source_values[] = { smaug_f64_sin, smaug_f64_cos, smaug_f64_tan,
                     smaug_f64_exp, smaug_f64_log, smaug_f64_sqrt };
    double source_values_2[3] = {1, 2, 3};
    reset(-1);
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values_2, 3);
    assert(left_series);
    for (size_t filtered_series = 0; filtered_series < sizeof(source_values)/sizeof(source_values[0]); filtered_series++) {
        for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
            reset(allocation_index);
            smaug_series_f64_t *source_series = source_values[filtered_series](left_series);
            if (source_series) { OK(source_series->size == 3, "f64 math size ok"); smaug_f64_free(source_series); }
        }
    }
    smaug_f64_free(left_series);
}
static void allocation_failure_float64_between(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_f64_between(left_series, 1.0, 3.0, true, true, &mask);
        /* between aloca result E mask; se um falhar, ambos devem ser liberados
           internamente e o retorno e' NULL (nunca result sem mask). */
        if (result) { OK(mask != NULL, "f64 between mask junto"); free(result); free(mask); }
    }
    smaug_f64_free(left_series);
}
static void allocation_failure_float64_not_equal(void) {
    double source_values[3] = {1, 2, 3};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_f64_ne(left_series, 2.0, &mask);
        if (result) { OK(mask != NULL, "f64 ne mask junto"); free(result); free(mask); }
    }
    smaug_f64_free(left_series);
}

static void allocation_failure_float64_argsort(void) {
    double source_values[3] = {3, 1, 2};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t *indices = smaug_f64_argsort(left_series, true);
        if (indices) { OK(indices[0] == 1, "f64 argsort menor"); free(indices); }
    }
    smaug_f64_free(left_series);
}

static void allocation_failure_float64_sort(void) {
    double source_values[3] = {3, 1, 2};
    smaug_series_f64_t *left_series = smaug_f64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *sorted_series = smaug_f64_sort(left_series, true);
        if (sorted_series) { OK(sorted_series->size == 3, "f64 sort size"); smaug_f64_free(sorted_series); }
    }
    smaug_f64_free(left_series);
}

/* ======================================================================
   i64 (paridade)
   ====================================================================== */
static void allocation_failure_int64_create(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *integer_series = smaug_i64_create(5);
        if (integer_series) { OK(integer_series->size == 5, "i64 create size"); smaug_i64_free(integer_series); }
    }
}

static void allocation_failure_int64_create_from_array(void) {
    int64_t source_values[4] = {1, 2, 3, 4};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *integer_series = smaug_i64_create_from_array(source_values, 4);
        if (integer_series) { OK(smaug_i64_count_nonnull(integer_series) == 4, "i64 from_array"); smaug_i64_free(integer_series); }
    }
}

static void allocation_failure_int64_clone(void) {
    smaug_series_i64_t *integer_series = smaug_i64_create(5);
    assert(integer_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *cloned_series = smaug_i64_clone(integer_series);
        if (cloned_series) { OK(cloned_series->size == 5, "i64 clone size"); smaug_i64_free(cloned_series); }
    }
    smaug_i64_free(integer_series);
}

static void allocation_failure_int64_view(void) {
    smaug_series_i64_t *integer_series = smaug_i64_create(5);
    assert(integer_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *series_view = smaug_i64_view(integer_series, 0, 2);
        if (series_view) { OK(series_view->size == 2, "i64 view size"); smaug_i64_free(series_view); }
    }
    smaug_i64_free(integer_series);
}

static void allocation_failure_int64_append_grow(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        smaug_series_i64_t *integer_series = smaug_i64_create_with_capacity(0, 0);
        assert(integer_series);
        reset(allocation_index);
        int status_code = smaug_i64_append(integer_series, 7);
        OK(status_code == 0 || status_code == -1, "i64 append rc valido");
        if (status_code == 0) OK(integer_series->size == 1, "i64 append cresceu");
        else         OK(integer_series->size == 0, "i64 append falhou sem corromper");
        reset(-1);
        smaug_i64_free(integer_series);
    }
}

static void allocation_failure_int64_add(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    smaug_series_i64_t *right_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *sum_series = smaug_i64_add(left_series, right_series);
        if (sum_series) { OK(sum_series->size == 3, "i64 add size"); smaug_i64_free(sum_series); }
    }
    smaug_i64_free(left_series); smaug_i64_free(right_series);
}

static void allocation_failure_int64_add_scalar(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *add_scalar_series = smaug_i64_add_scalar(left_series, 10);
        if (add_scalar_series) { OK(add_scalar_series->size == 3, "i64 add_scalar size"); smaug_i64_free(add_scalar_series); }
    }
    smaug_i64_free(left_series);
}

static void allocation_failure_int64_compare(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_i64_gt(left_series, 1, &mask);
        if (result) { OK(mask != NULL, "i64 gt mask junto"); free(result); free(mask); }
    }
    smaug_i64_free(left_series);
}

/* --- B3: i64 compares restantes (lt/eq); gt já coberto em af_i64_compare --- */
static void allocation_failure_int64_less_than(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_i64_lt(left_series, 2, &mask);
        if (result) { OK(mask != NULL, "i64 lt mask junto"); free(result); free(mask); }
    }
    smaug_i64_free(left_series);
}

static void allocation_failure_int64_equal(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_i64_eq(left_series, 2, &mask);
        if (result) { OK(mask != NULL, "i64 eq mask junto"); free(result); free(mask); }
    }
    smaug_i64_free(left_series);
}

static void allocation_failure_int64_greater_or_equal(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_i64_ge(left_series, 2, &mask);
        if (result) { OK(mask != NULL, "i64 ge mask junto"); free(result); free(mask); }
    }
    smaug_i64_free(left_series);
}
static void allocation_failure_int64_less_or_equal(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_i64_le(left_series, 2, &mask);
        if (result) { OK(mask != NULL, "i64 le mask junto"); free(result); free(mask); }
    }
    smaug_i64_free(left_series);
}
static void allocation_failure_int64_between(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_i64_between(left_series, 1, 3, true, true, &mask);
        if (result) { OK(mask != NULL, "i64 between mask junto"); free(result); free(mask); }
    }
    smaug_i64_free(left_series);
}
static void allocation_failure_int64_not_equal(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *mask = NULL;
        uint8_t *result = smaug_i64_ne(left_series, 2, &mask);
        if (result) { OK(mask != NULL, "i64 ne mask junto"); free(result); free(mask); }
    }
    smaug_i64_free(left_series);
}

/* --- B1: i64 ops aritméticas restantes (sub/mul/div série) --- */
static void allocation_failure_int64_subtract(void) {
    int64_t left_values[3] = {4, 5, 6}, right_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(left_values, 3);
    smaug_series_i64_t *right_series = smaug_i64_create_from_array(right_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *difference_series = smaug_i64_sub(left_series, right_series);
        if (difference_series) { OK(difference_series->size == 3, "i64 sub size"); smaug_i64_free(difference_series); }
    }
    smaug_i64_free(left_series); smaug_i64_free(right_series);
}

static void allocation_failure_int64_multiply(void) {
    int64_t left_values[3] = {4, 5, 6}, right_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(left_values, 3);
    smaug_series_i64_t *right_series = smaug_i64_create_from_array(right_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *product_series = smaug_i64_mul(left_series, right_series);
        if (product_series) { OK(product_series->size == 3, "i64 mul size"); smaug_i64_free(product_series); }
    }
    smaug_i64_free(left_series); smaug_i64_free(right_series);
}

static void allocation_failure_int64_divide(void) {
    int64_t left_values[3] = {4, 5, 6}, right_values[3] = {1, 2, 3};   /* divisor não-nulo */
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(left_values, 3);
    smaug_series_i64_t *right_series = smaug_i64_create_from_array(right_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *quotient_series = smaug_i64_div(left_series, right_series);
        if (quotient_series) { OK(quotient_series->size == 3, "i64 div size"); smaug_i64_free(quotient_series); }
    }
    smaug_i64_free(left_series); smaug_i64_free(right_series);
}

/* --- B1: i64 scalars restantes (sub/mul/div) --- */
static void allocation_failure_int64_subtract_scalar(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *subtract_scalar_series = smaug_i64_sub_scalar(left_series, 1);
        if (subtract_scalar_series) { OK(subtract_scalar_series->size == 3, "i64 sub_scalar size"); smaug_i64_free(subtract_scalar_series); }
    }
    smaug_i64_free(left_series);
}

static void allocation_failure_int64_multiply_scalar(void) {
    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *multiply_scalar_series = smaug_i64_mul_scalar(left_series, 3);
        if (multiply_scalar_series) { OK(multiply_scalar_series->size == 3, "i64 mul_scalar size"); smaug_i64_free(multiply_scalar_series); }
    }
    smaug_i64_free(left_series);
}

static void allocation_failure_int64_divide_scalar(void) {
    int64_t source_values[3] = {2, 4, 6};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *divide_scalar_series = smaug_i64_div_scalar(left_series, 2);   /* scalar não-nulo */
        if (divide_scalar_series) { OK(divide_scalar_series->size == 3, "i64 div_scalar size"); smaug_i64_free(divide_scalar_series); }
    }
    smaug_i64_free(left_series);
}

static void allocation_failure_int64_argsort(void) {
    int64_t source_values[3] = {3, 1, 2};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t *indices = smaug_i64_argsort(left_series, true);
        if (indices) { OK(indices[0] == 1, "i64 argsort menor"); free(indices); }
    }
    smaug_i64_free(left_series);
}

static void allocation_failure_int64_sort(void) {
    int64_t source_values[3] = {3, 1, 2};
    smaug_series_i64_t *left_series = smaug_i64_create_from_array(source_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *sorted_series = smaug_i64_sort(left_series, true);
        if (sorted_series) { OK(sorted_series->size == 3, "i64 sort size"); smaug_i64_free(sorted_series); }
    }
    smaug_i64_free(left_series);
}

/* ======================================================================
   string — varre os pontos de alocação do lifecycle, mutação, seleção e
   ordenação. Onde há série-base, ela é criada com reset(-1) (sem falha) e a
   falha é injetada só na operação testada.
   ====================================================================== */
static void allocation_failure_string_create(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_str_t *source_series = smaug_str_create(5);
        if (source_series) { OK(source_series->size == 5, "str create size"); smaug_str_free(source_series); }
    }
}
static void allocation_failure_string_create_from_array(void) {
    const char *source_values[] = {"AC", "BA", "MG"};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
        if (source_series) { OK(source_series->size == 3, "str from_array size"); smaug_str_free(source_series); }
    }
}
static void allocation_failure_string_clone(void) {
    const char *source_values[] = {"x", "yy", "zzz"};
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_str_t *source_series_2 = smaug_str_clone(source_series);
        if (source_series_2) { OK(source_series_2->size == 3, "str clone size"); smaug_str_free(source_series_2); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_set_grow(void) {
    /* set com string MAIOR força realocação do buffer — caminho de erro crítico */
    const char *source_values[] = {"a", "b", "c"};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
        assert(source_series);
        reset(allocation_index);
        int status_code = smaug_str_set(source_series, 0, "MUITO_GRANDE", 12);  /* cresce o buffer */
        if (status_code == 0) {
            size_t left_value; const char *string_get_result = smaug_str_get(source_series, 0, &left_value);
            OK(string_get_result && left_value == 12, "str set grow conteudo");
        }
        /* rc != 0 = falha de alocação injetada (esperado); série segue íntegra */
        smaug_str_free(source_series);
    }
}
/* --- B3: str append forçando crescimento de buffer sob falha ---
   SMAUG_STR_BUFFER_INIT = 16 bytes. Criamos com capacidade 1 (força reserve
   logo no 1º append) e plantamos strings que somam >16 bytes pra garantir
   que str_buffer_reserve chame realloc e tenha chance de falhar.
   str_slots_reserve_one também entra quando capacity==0 (slots crescem). */
static void allocation_failure_string_append_grow(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        /* capacidade inicial 1 byte → qualquer string >1 byte força crescimento */
        smaug_series_str_t *source_series = smaug_str_create_with_capacity(0, 1);
        assert(source_series);
        reset(allocation_index);
        /* 20 bytes: garante crescimento do buffer (>BUFFER_INIT=16) */
        smaug_str_append(source_series, "abcdefghijklmnopqrst", 20);
        smaug_str_append(source_series, "uvwxyz", 6);
        smaug_str_append_null(source_series);
        smaug_str_free(source_series);
    }
}
/* --- B3-final: append_null força crescimento de slots sob falha (str:316) ---
   str_slots_reserve_one cresce quando size==capacity. create(0) → capacity=0,
   então o 1º append_null já precisa crescer. O bloco anterior (af_str_append_grow)
   chama append_null depois de dois appends regulares que já cresceram os slots —
   portanto str:316 nunca falhou lá. Aqui append_null é a primeira op. */
static void allocation_failure_string_append_null_grow(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_str_t *source_series = smaug_str_create(0);   /* capacity=0 */
        assert(source_series);
        reset(allocation_index);
        smaug_str_append_null(source_series);   /* 1ª op: slots crescem aqui → str:316 */
        smaug_str_append_null(source_series);
        smaug_str_free(source_series);
    }
}

/* --- str view + COW detach sob OOM (item 9.2) ---
   smaug_str_view aloca struct + offsets próprio (2 mallocs). Escrever numa view
   dispara str_cow_detach, que aloca buffer + offsets + null_mask privados (3
   mallocs) — todos revertidos de forma segura se algum falhar (série intacta,
   pai intacto). Espelha af_dt_setters, mas com as alocações extras da string. */
static void allocation_failure_string_view_cow(void) {
    const char *source_values[] = {"SP", "RJ", "MG", "BA", "CE"};

    /* smaug_str_view em si sob OOM (malloc do struct + offsets) */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 5);
        assert(source_series);
        reset(allocation_index);
        smaug_series_str_t *source_series_2 = smaug_str_view(source_series, 1, 3);
        if (source_series_2) { OK(source_series_2->size == 3, "str view size"); smaug_str_free(source_series_2); }
        reset(-1);
        smaug_str_free(source_series);
    }
    /* set numa view → str_cow_detach (buffer+offsets+null_mask) */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 5);
        assert(source_series);
        smaug_series_str_t *source_series_2 = smaug_str_view(source_series, 1, 3);
        if (!source_series_2) { smaug_str_free(source_series); reset(-1); continue; }
        reset(allocation_index);
        smaug_status_t status = smaug_str_set(source_series_2, 1, "MINAS", 5); /* detach + set_grow */
        OK(status == SMG_OK || status == SMG_ERR_NOMEM, "str_set view: status válido");
        reset(-1);
        smaug_str_free(source_series_2); smaug_str_free(source_series);
    }
    /* set_null numa view → detach via set interno */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 5);
        assert(source_series);
        smaug_series_str_t *source_series_2 = smaug_str_view(source_series, 0, 3);
        if (!source_series_2) { smaug_str_free(source_series); reset(-1); continue; }
        reset(allocation_index);
        smaug_status_t status = smaug_str_set_null(source_series_2, 0); /* detach */
        OK(status == SMG_OK || status == SMG_ERR_NOMEM, "str_set_null view: status válido");
        reset(-1);
        smaug_str_free(source_series_2); smaug_str_free(source_series);
    }
    /* append numa view → detach + slots/buffer reserve */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 5);
        assert(source_series);
        smaug_series_str_t *source_series_2 = smaug_str_view(source_series, 1, 2);
        if (!source_series_2) { smaug_str_free(source_series); reset(-1); continue; }
        reset(allocation_index);
        int status_code = smaug_str_append(source_series_2, "NOVO", 4); /* detach + grow */
        OK(status_code == 0 || status_code == -1, "str_append view: rc válido");
        reset(-1);
        smaug_str_free(source_series_2); smaug_str_free(source_series);
    }
    /* append_null numa view → detach + slots reserve */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 5);
        assert(source_series);
        smaug_series_str_t *source_series_2 = smaug_str_view(source_series, 2, 2);
        if (!source_series_2) { smaug_str_free(source_series); reset(-1); continue; }
        reset(allocation_index);
        int status_code = smaug_str_append_null(source_series_2); /* detach + slots */
        OK(status_code == 0 || status_code == -1, "str_append_null view: rc válido");
        reset(-1);
        smaug_str_free(source_series_2); smaug_str_free(source_series);
    }
    /* view vazia: detach materializa buffer inicial (1 malloc no ramo size==0) */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 5);
        assert(source_series);
        smaug_series_str_t *source_series_2 = smaug_str_view(source_series, 2, 0);
        if (!source_series_2) { smaug_str_free(source_series); reset(-1); continue; }
        reset(allocation_index);
        int status_code = smaug_str_append(source_series_2, "X", 1); /* detach ramo vazio + grow */
        OK(status_code == 0 || status_code == -1, "str_append empty view: rc válido");
        reset(-1);
        smaug_str_free(source_series_2); smaug_str_free(source_series);
    }
}

static void allocation_failure_string_compare(void) {
    const char *source_values[] = {"SP", "RJ", "MG"};
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *null_mask = NULL;
        uint8_t *string_equal_result = smaug_str_eq(source_series, "SP", 2, &null_mask);
        if (string_equal_result) { OK(1, "str eq ok"); free(string_equal_result); free(null_mask); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_greater_or_equal(void) {
    const char *source_values[] = {"SP", "RJ", "MG"};
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *null_mask = NULL;
        uint8_t *string_greater_or_equal_result = smaug_str_ge(source_series, "RJ", 2, &null_mask);
        if (string_greater_or_equal_result) { OK(1, "str ge ok"); free(string_greater_or_equal_result); free(null_mask); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_between(void) {
    const char *source_values[] = {"SP", "RJ", "MG"};
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *null_mask = NULL;
        uint8_t *string_between_result = smaug_str_between(source_series, "MG", 2, "SP", 2, true, true, &null_mask);
        /* aloca result E mask; se um falhar, ambos liberados e retorno NULL */
        if (string_between_result) { OK(null_mask != NULL, "str between mask junto"); free(string_between_result); free(null_mask); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_less_or_equal(void) {
    const char *source_values[] = {"SP", "RJ", "MG"};
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *null_mask = NULL;
        uint8_t *string_less_or_equal_result = smaug_str_le(source_series, "RJ", 2, &null_mask);
        if (string_less_or_equal_result) { OK(1, "str le ok"); free(string_less_or_equal_result); free(null_mask); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_not_equal(void) {
    const char *source_values[] = {"SP", "RJ", "MG"};
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *null_mask = NULL;
        uint8_t *string_not_equal_result = smaug_str_ne(source_series, "SP", 2, &null_mask);
        if (string_not_equal_result) { OK(1, "str ne ok"); free(string_not_equal_result); free(null_mask); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_filter(void) {
    const char *source_values[] = {"a", "bb", "ccc", "d"};
    uint8_t source_values_2[] = {1, 0, 1, 1};
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 4);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_str_t *source_series_2 = smaug_str_filter(source_series, source_values_2);
        if (source_series_2) { OK(source_series_2->size == 3, "str filter size"); smaug_str_free(source_series_2); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_take(void) {
    const char *source_values[] = {"a", "bb", "ccc"};
    size_t indices[] = {2, 0, 1};
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_str_t *source_series_2 = smaug_str_take(source_series, indices, 3);
        if (source_series_2) { OK(source_series_2->size == 3, "str take size"); smaug_str_free(source_series_2); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_forward_fill(void) {
    /* série com NA no meio e nas bordas, exercita append/append_null
       e (no bfill) o malloc(src). */
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create(5);
    assert(source_series);
    smaug_str_set(source_series, 0, "a", 1);
    smaug_str_set(source_series, 2, "ccc", 3);
    /* idx 1, 3, 4 ficam null */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_str_t *source_series_2 = smaug_str_ffill(source_series);
        if (source_series_2) { OK(source_series_2->size == 5, "str ffill size"); smaug_str_free(source_series_2); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_backward_fill(void) {
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create(5);
    assert(source_series);
    smaug_str_set(source_series, 1, "bb", 2);
    smaug_str_set(source_series, 3, "dddd", 4);
    /* idx 0, 2, 4 null → exercita o malloc(src) e append/append_null */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_str_t *source_series_2 = smaug_str_bfill(source_series);
        if (source_series_2) { OK(source_series_2->size == 5, "str bfill size"); smaug_str_free(source_series_2); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_shift(void) {
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create(5);
    assert(source_series);
    smaug_str_set(source_series, 0, "a", 1);
    smaug_str_set(source_series, 2, "ccc", 3);
    smaug_str_set(source_series, 4, "ee", 2);
    /* idx 1,3 null; shift(2) move e cria nulls nas bordas, exercitando
       create_with_capacity + append/append_null. */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_str_t *source_series_2 = smaug_str_shift(source_series, 2);
        if (source_series_2) { OK(source_series_2->size == 5, "str shift size"); smaug_str_free(source_series_2); }
    }
    /* negativo também */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_str_t *source_series_2 = smaug_str_shift(source_series, -2);
        if (source_series_2) { OK(source_series_2->size == 5, "str shift(-) size"); smaug_str_free(source_series_2); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_rank(void) {
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create(5);
    assert(source_series);
    smaug_str_set(source_series, 0, "banana", 6);
    smaug_str_set(source_series, 1, "abacaxi", 7);
    smaug_str_set(source_series, 3, "abacaxi", 7);  /* empate; idx 2,4 null */
    /* exercita malloc(result) + malloc(idx) + qsort */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        double *string_rank_result = smaug_str_rank(source_series, 0);
        if (string_rank_result) { OK(1, "str rank ok"); free(string_rank_result); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_argsort(void) {
    const char *source_values[] = {"MG", "AC", "SP"};
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t *string_argsort_result = smaug_str_argsort(source_series, true);
        if (string_argsort_result) { OK(1, "str argsort ok"); free(string_argsort_result); }
    }
    smaug_str_free(source_series);
}
static void allocation_failure_string_sort(void) {
    const char *source_values[] = {"MG", "AC", "SP"};
    reset(-1);
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_str_t *source_series_2 = smaug_str_sort(source_series, true);
        if (source_series_2) { OK(source_series_2->size == 3, "str sort size"); smaug_str_free(source_series_2); }
    }
    smaug_str_free(source_series);
}

/* ======================================================================
   COW detach — falha de alocação em set/set_null em views
   O detach faz exatamente 2 mallocs (nd, nm). Varremos k=0 (nd falha) e
   k=1 (nd ok, nm falha) verificando:
     - retorno SMG_ERR_NOMEM, view continua sendo view, pai inalterada;
     - nd alocado e depois descartado no caminho k=1 não vaza (Valgrind).
   Para k >= 2 o detach sucede: verificamos view destacada e pai intacta.
   ====================================================================== */
static void allocation_failure_float64_cow_set(void) {
    double source_values[4] = {10.0, 20.0, 30.0, 40.0};
    reset(-1);
    smaug_series_f64_t *parent_series = smaug_f64_create_from_array(source_values, 4);
    assert(parent_series);

    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        /* view sem falha; falha injetada apenas no set (dentro do detach) */
        reset(-1);
        smaug_series_f64_t *series_view = smaug_f64_view(parent_series, 1, 2);   /* [20, 30] */
        assert(series_view);

        reset(allocation_index);
        smaug_status_t status = smaug_f64_set(series_view, 0, 99.0);

        if (status == SMG_OK) {
            OK(series_view->meta.is_view        == false, "f64 cow_set: view detachada");
            OK(series_view->meta.external_alloc == false, "f64 cow_set: external_alloc false");
            OK(parent_series->data[1] == 20.0,            "f64 cow_set: pai preservada");
        } else {
            OK(status == SMG_ERR_NOMEM,             "f64 cow_set OOM: status NOMEM");
            OK(series_view->meta.is_view        == true,  "f64 cow_set OOM: view nao detachada");
            OK(parent_series->data[1] == 20.0,            "f64 cow_set OOM: pai preservada");
        }

        reset(-1);
        smaug_f64_free(series_view);
    }
    smaug_f64_free(parent_series);
}

static void allocation_failure_float64_cow_set_null(void) {
    double source_values[4] = {10.0, 20.0, 30.0, 40.0};
    reset(-1);
    smaug_series_f64_t *parent_series = smaug_f64_create_from_array(source_values, 4);
    assert(parent_series);

    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_f64_t *series_view = smaug_f64_view(parent_series, 0, 4);
        assert(series_view);

        reset(allocation_index);
        smaug_status_t status = smaug_f64_set_null(series_view, 1);

        if (status == SMG_OK) {
            OK(series_view->meta.is_view == false,    "f64 cow_set_null: view detachada");
            OK(!smaug_f64_is_null(parent_series, 1),  "f64 cow_set_null: pai nao virou null");
        } else {
            OK(status == SMG_ERR_NOMEM,         "f64 cow_set_null OOM: status NOMEM");
            OK(series_view->meta.is_view == true,     "f64 cow_set_null OOM: view nao detachada");
            OK(!smaug_f64_is_null(parent_series, 1),  "f64 cow_set_null OOM: pai preservada");
        }

        reset(-1);
        smaug_f64_free(series_view);
    }
    smaug_f64_free(parent_series);
}

static void allocation_failure_int64_cow_set(void) {
    int64_t source_values[4] = {10, 20, 30, 40};
    reset(-1);
    smaug_series_i64_t *parent_series = smaug_i64_create_from_array(source_values, 4);
    assert(parent_series);

    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_i64_t *series_view = smaug_i64_view(parent_series, 1, 2);   /* [20, 30] */
        assert(series_view);

        reset(allocation_index);
        smaug_status_t status = smaug_i64_set(series_view, 0, 99);

        if (status == SMG_OK) {
            OK(series_view->meta.is_view        == false, "i64 cow_set: view detachada");
            OK(series_view->meta.external_alloc == false, "i64 cow_set: external_alloc false");
            OK(parent_series->data[1] == 20,              "i64 cow_set: pai preservada");
        } else {
            OK(status == SMG_ERR_NOMEM,             "i64 cow_set OOM: status NOMEM");
            OK(series_view->meta.is_view        == true,  "i64 cow_set OOM: view nao detachada");
            OK(parent_series->data[1] == 20,              "i64 cow_set OOM: pai preservada");
        }

        reset(-1);
        smaug_i64_free(series_view);
    }
    smaug_i64_free(parent_series);
}

static void allocation_failure_int64_cow_set_null(void) {
    int64_t source_values[4] = {10, 20, 30, 40};
    reset(-1);
    smaug_series_i64_t *parent_series = smaug_i64_create_from_array(source_values, 4);
    assert(parent_series);

    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_i64_t *series_view = smaug_i64_view(parent_series, 0, 4);
        assert(series_view);

        reset(allocation_index);
        smaug_status_t status = smaug_i64_set_null(series_view, 2);

        if (status == SMG_OK) {
            OK(series_view->meta.is_view == false,    "i64 cow_set_null: view detachada");
            OK(!smaug_i64_is_null(parent_series, 2),  "i64 cow_set_null: pai nao virou null");
        } else {
            OK(status == SMG_ERR_NOMEM,         "i64 cow_set_null OOM: status NOMEM");
            OK(series_view->meta.is_view == true,     "i64 cow_set_null OOM: view nao detachada");
            OK(!smaug_i64_is_null(parent_series, 2),  "i64 cow_set_null OOM: pai preservada");
        }

        reset(-1);
        smaug_i64_free(series_view);
    }
    smaug_i64_free(parent_series);
}

static void allocation_failure_float64_cow_append(void) {
    /* O append numa view faz: detach (2 mallocs) + grow (até 2 reallocs).
       Varremos todos os pontos de falha; em qualquer um, pai deve permanecer
       intacta e o retorno deve ser -1. */
    double source_values[3] = {10.0, 20.0, 30.0};
    reset(-1);
    smaug_series_f64_t *parent_series = smaug_f64_create_from_array(source_values, 3);
    assert(parent_series);

    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_f64_t *series_view = smaug_f64_view(parent_series, 0, 3);
        assert(series_view);

        reset(allocation_index);
        int status_code = smaug_f64_append(series_view, 99.0);

        if (status_code == 0) {
            OK(series_view->meta.is_view == false, "f64 cow_append: view detachada");
            OK(series_view->size == 4,             "f64 cow_append: size incrementado");
            OK(parent_series->data[0] == 10.0,     "f64 cow_append: pai preservada");
        } else {
            OK(status_code == -1,             "f64 cow_append OOM: rc=-1");
            OK(parent_series->data[0] == 10.0, "f64 cow_append OOM: pai preservada");
        }

        reset(-1);
        smaug_f64_free(series_view);
    }
    smaug_f64_free(parent_series);
}

static void allocation_failure_float64_cow_append_null(void) {
    double source_values[3] = {10.0, 20.0, 30.0};
    reset(-1);
    smaug_series_f64_t *parent_series = smaug_f64_create_from_array(source_values, 3);
    assert(parent_series);

    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_f64_t *series_view = smaug_f64_view(parent_series, 0, 3);
        assert(series_view);

        reset(allocation_index);
        int status_code = smaug_f64_append_null(series_view);

        if (status_code == 0) {
            OK(series_view->meta.is_view == false,  "f64 cow_append_null: view detachada");
            OK(series_view->size == 4,              "f64 cow_append_null: size incrementado");
            OK(!smaug_f64_is_null(parent_series,0), "f64 cow_append_null: pai preservada");
        } else {
            OK(status_code == -1,                  "f64 cow_append_null OOM: rc=-1");
            OK(!smaug_f64_is_null(parent_series,0), "f64 cow_append_null OOM: pai preservada");
        }

        reset(-1);
        smaug_f64_free(series_view);
    }
    smaug_f64_free(parent_series);
}

static void allocation_failure_int64_cow_append(void) {
    int64_t source_values[3] = {10, 20, 30};
    reset(-1);
    smaug_series_i64_t *parent_series = smaug_i64_create_from_array(source_values, 3);
    assert(parent_series);

    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_i64_t *series_view = smaug_i64_view(parent_series, 0, 3);
        assert(series_view);

        reset(allocation_index);
        int status_code = smaug_i64_append(series_view, 99);

        if (status_code == 0) {
            OK(series_view->meta.is_view == false, "i64 cow_append: view detachada");
            OK(series_view->size == 4,             "i64 cow_append: size incrementado");
            OK(parent_series->data[0] == 10,       "i64 cow_append: pai preservada");
        } else {
            OK(status_code == -1,           "i64 cow_append OOM: rc=-1");
            OK(parent_series->data[0] == 10, "i64 cow_append OOM: pai preservada");
        }

        reset(-1);
        smaug_i64_free(series_view);
    }
    smaug_i64_free(parent_series);
}

static void allocation_failure_int64_cow_append_null(void) {
    int64_t source_values[3] = {10, 20, 30};
    reset(-1);
    smaug_series_i64_t *parent_series = smaug_i64_create_from_array(source_values, 3);
    assert(parent_series);

    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_i64_t *series_view = smaug_i64_view(parent_series, 0, 3);
        assert(series_view);

        reset(allocation_index);
        int status_code = smaug_i64_append_null(series_view);

        if (status_code == 0) {
            OK(series_view->meta.is_view == false,  "i64 cow_append_null: view detachada");
            OK(series_view->size == 4,              "i64 cow_append_null: size incrementado");
            OK(!smaug_i64_is_null(parent_series,0), "i64 cow_append_null: pai preservada");
        } else {
            OK(status_code == -1,                  "i64 cow_append_null OOM: rc=-1");
            OK(!smaug_i64_is_null(parent_series,0), "i64 cow_append_null OOM: pai preservada");
        }

        reset(-1);
        smaug_i64_free(series_view);
    }
    smaug_i64_free(parent_series);
}

/* ======================================================================
   FASE 8 (b) — take/filter numéricos sob falha de alocação.
   Os equivalentes de string (af_str_take/af_str_filter) já existiam; os
   numéricos faltavam. São os caminhos C que DataSet:take/dropna/filter/iloc/
   head/tail/sample exercem em colunas f64/i64. Padrão idêntico ao str:
   base construída fora da janela de injeção, varredura em reset(k).
   ====================================================================== */
static void allocation_failure_float64_take(void) {
    double source_values[3] = {10, 20, 30};
    size_t indices[]  = {2, 0, 1};
    reset(-1);
    smaug_series_f64_t *floating_point_series = smaug_f64_create_from_array(source_values, 3);
    assert(floating_point_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *selected_result = smaug_f64_take(floating_point_series, indices, 3);
        if (selected_result) { OK(selected_result->size == 3, "f64 take size"); smaug_f64_free(selected_result); }
    }
    smaug_f64_free(floating_point_series);
}
static void allocation_failure_float64_filter(void) {
    double source_values[4] = {1, 2, 3, 4};
    uint8_t source_values_2[] = {1, 0, 1, 1};
    reset(-1);
    smaug_series_f64_t *floating_point_series = smaug_f64_create_from_array(source_values, 4);
    assert(floating_point_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *filtered_result = smaug_f64_filter(floating_point_series, source_values_2);
        if (filtered_result) { OK(filtered_result->size == 3, "f64 filter size"); smaug_f64_free(filtered_result); }
    }
    smaug_f64_free(floating_point_series);
}
static void allocation_failure_int64_take(void) {
    int64_t source_values[3] = {10, 20, 30};
    size_t  indices[]  = {2, 0, 1};
    reset(-1);
    smaug_series_i64_t *integer_series = smaug_i64_create_from_array(source_values, 3);
    assert(integer_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *selected_result = smaug_i64_take(integer_series, indices, 3);
        if (selected_result) { OK(selected_result->size == 3, "i64 take size"); smaug_i64_free(selected_result); }
    }
    smaug_i64_free(integer_series);
}
static void allocation_failure_int64_filter(void) {
    int64_t source_values[4] = {1, 2, 3, 4};
    uint8_t source_values_2[] = {1, 0, 1, 1};
    reset(-1);
    smaug_series_i64_t *integer_series = smaug_i64_create_from_array(source_values, 4);
    assert(integer_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *filtered_result = smaug_i64_filter(integer_series, source_values_2);
        if (filtered_result) { OK(filtered_result->size == 3, "i64 filter size"); smaug_i64_free(filtered_result); }
    }
    smaug_i64_free(integer_series);
}

/* ======================================================================
   B2: bool (Kleene) — and/or/xor/not via alloc-fail.
   As ops bool não têm struct de série: operam em arrays crus (valores +
   máscara + n). A única alocação durante a op é o alloc_pair (vals + mask),
   então out_mask é sempre fornecido para forçar os DOIS mallocs (linhas
   15/18) e o guard !r de cada op.
   ====================================================================== */
static void allocation_failure_bool_and(void) {
    uint8_t left_values[3] = {1, 0, 1}, right_values[3] = {1, 1, 0};
    smaug_mask_t left_null_mask[3] = {0xFF, 0xFF, 0xFF}, right_null_mask[3] = {0xFF, 0xFF, 0xFF};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *result_null_mask = NULL;
        uint8_t *and_result = smaug_bool_and(left_values, left_null_mask, right_values, right_null_mask, 3, &result_null_mask);
        if (and_result) { OK(result_null_mask != NULL, "bool and mask junto"); free(and_result); free(result_null_mask); }
    }
}

static void allocation_failure_bool_or(void) {
    uint8_t left_values[3] = {1, 0, 1}, right_values[3] = {1, 1, 0};
    smaug_mask_t left_null_mask[3] = {0xFF, 0xFF, 0xFF}, right_null_mask[3] = {0xFF, 0xFF, 0xFF};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *result_null_mask = NULL;
        uint8_t *or_result = smaug_bool_or(left_values, left_null_mask, right_values, right_null_mask, 3, &result_null_mask);
        if (or_result) { OK(result_null_mask != NULL, "bool or mask junto"); free(or_result); free(result_null_mask); }
    }
}

static void allocation_failure_bool_xor(void) {
    uint8_t left_values[3] = {1, 0, 1}, right_values[3] = {1, 1, 0};
    smaug_mask_t left_null_mask[3] = {0xFF, 0xFF, 0xFF}, right_null_mask[3] = {0xFF, 0xFF, 0xFF};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *result_null_mask = NULL;
        uint8_t *xor_result = smaug_bool_xor(left_values, left_null_mask, right_values, right_null_mask, 3, &result_null_mask);
        if (xor_result) { OK(result_null_mask != NULL, "bool xor mask junto"); free(xor_result); free(result_null_mask); }
    }
}

static void allocation_failure_bool_not(void) {
    uint8_t left_values[3] = {1, 0, 1};
    smaug_mask_t left_null_mask[3] = {0xFF, 0xFF, 0xFF};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *result_null_mask = NULL;
        uint8_t *not_result = smaug_bool_not(left_values, left_null_mask, 3, &result_null_mask);
        if (not_result) { OK(result_null_mask != NULL, "bool not mask junto"); free(not_result); free(result_null_mask); }
    }
}

/* ======================================================================
   B3: bool struct-based (smaug_series_bool_t) — dtype de primeira classe.
   Espelha a varredura de i64: lifecycle, seleção, COW, e Kleene struct→struct.
   Distinto do bloco B2 (raw arrays), que cobre as funções legadas.
   ====================================================================== */
static void allocation_failure_bool_create(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *boolean_series = smaug_bool_create(5);
        if (boolean_series) { OK(boolean_series->size == 5, "bool create size"); smaug_bool_free(boolean_series); }
    }
}
static void allocation_failure_bool_create_from_array(void) {
    uint8_t source_values[4] = {1, 0, 1, 1};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *boolean_series = smaug_bool_create_from_array(source_values, 4);
        if (boolean_series) { OK(smaug_bool_count_nonnull(boolean_series) == 4, "bool from_array"); smaug_bool_free(boolean_series); }
    }
}
static void allocation_failure_bool_clone(void) {
    smaug_series_bool_t *boolean_series = smaug_bool_create(5);
    assert(boolean_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *cloned_series = smaug_bool_clone(boolean_series);
        if (cloned_series) { OK(cloned_series->size == 5, "bool clone size"); smaug_bool_free(cloned_series); }
    }
    smaug_bool_free(boolean_series);
}
static void allocation_failure_bool_view(void) {
    smaug_series_bool_t *boolean_series = smaug_bool_create(5);
    assert(boolean_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *series_view = smaug_bool_view(boolean_series, 0, 2);
        if (series_view) { OK(series_view->size == 2, "bool view size"); smaug_bool_free(series_view); }
    }
    smaug_bool_free(boolean_series);
}
static void allocation_failure_bool_append_grow(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        smaug_series_bool_t *boolean_series = smaug_bool_create_with_capacity(0, 0);
        assert(boolean_series);
        reset(allocation_index);
        int status_code = smaug_bool_append(boolean_series, 1);
        OK(status_code == 0 || status_code == -1, "bool append rc valido");
        if (status_code == 0) OK(boolean_series->size == 1, "bool append cresceu");
        else         OK(boolean_series->size == 0, "bool append falhou sem corromper");
        reset(-1);
        smaug_bool_free(boolean_series);
    }
}
static void allocation_failure_bool_take(void) {
    uint8_t source_values[3] = {1, 0, 1};
    size_t  indices[]  = {2, 0, 1};
    reset(-1);
    smaug_series_bool_t *boolean_series = smaug_bool_create_from_array(source_values, 3);
    assert(boolean_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *selected_result = smaug_bool_take(boolean_series, indices, 3);
        if (selected_result) { OK(selected_result->size == 3, "bool take size"); smaug_bool_free(selected_result); }
    }
    smaug_bool_free(boolean_series);
}
static void allocation_failure_bool_filter(void) {
    uint8_t source_values[4] = {1, 0, 1, 1};
    uint8_t source_values_2[] = {1, 0, 1, 1};
    reset(-1);
    smaug_series_bool_t *boolean_series = smaug_bool_create_from_array(source_values, 4);
    assert(boolean_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *filtered_result = smaug_bool_filter(boolean_series, source_values_2);
        if (filtered_result) { OK(filtered_result->size == 3, "bool filter size"); smaug_bool_free(filtered_result); }
    }
    smaug_bool_free(boolean_series);
}
static void allocation_failure_bool_shift(void) {
    reset(-1);
    smaug_series_bool_t *boolean_series = smaug_bool_create(4);
    assert(boolean_series);
    smaug_bool_set(boolean_series, 0, 1); smaug_bool_set(boolean_series, 1, 0); smaug_bool_set(boolean_series, 2, 1);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *shift_series = smaug_bool_shift(boolean_series, -1);
        if (shift_series) { OK(shift_series->size == 4, "bool shift size"); smaug_bool_free(shift_series); }
    }
    smaug_bool_free(boolean_series);
}
static void allocation_failure_bool_rank(void) {
    reset(-1);
    smaug_series_bool_t *boolean_series = smaug_bool_create(4);
    assert(boolean_series);
    smaug_bool_set(boolean_series, 0, 1); smaug_bool_set(boolean_series, 1, 0); smaug_bool_set(boolean_series, 2, 1);
    /* idx 3 null; bool rank só aloca result (sem qsort) */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        double *ranked_series = smaug_bool_rank(boolean_series, 0);
        if (ranked_series) { OK(1, "bool rank ok"); free(ranked_series); }
    }
    smaug_bool_free(boolean_series);
}
static void allocation_failure_bool_forward_fill(void) {
    reset(-1);
    smaug_series_bool_t *boolean_series = smaug_bool_create(5);
    assert(boolean_series);
    smaug_bool_set(boolean_series, 0, 1);
    smaug_bool_set(boolean_series, 3, 0);
    /* idx 1,2,4 null */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *forward_fill_series = smaug_bool_ffill(boolean_series);
        if (forward_fill_series) { OK(forward_fill_series->size == 5, "bool ffill size"); smaug_bool_free(forward_fill_series); }
    }
    smaug_bool_free(boolean_series);
}
static void allocation_failure_bool_backward_fill(void) {
    reset(-1);
    smaug_series_bool_t *boolean_series = smaug_bool_create(5);
    assert(boolean_series);
    smaug_bool_set(boolean_series, 1, 1);
    smaug_bool_set(boolean_series, 4, 0);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *backward_fill_series = smaug_bool_bfill(boolean_series);
        if (backward_fill_series) { OK(backward_fill_series->size == 5, "bool bfill size"); smaug_bool_free(backward_fill_series); }
    }
    smaug_bool_free(boolean_series);
}
static void allocation_failure_bool_argsort(void) {
    uint8_t source_values[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *boolean_series = smaug_bool_create_from_array(source_values, 4);
    assert(boolean_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t *sort_indices = smaug_bool_argsort(boolean_series, true);
        if (sort_indices) { OK(sort_indices[0] == 1, "bool argsort"); smaug_free(sort_indices); }
    }
    smaug_bool_free(boolean_series);
}
static void allocation_failure_bool_sort(void) {
    uint8_t source_values[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *boolean_series = smaug_bool_create_from_array(source_values, 4);
    assert(boolean_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *sorted_series = smaug_bool_sort(boolean_series, true);
        if (sorted_series) { OK(sorted_series->size == 4, "bool sort size"); smaug_bool_free(sorted_series); }
    }
    smaug_bool_free(boolean_series);
}
/* Kleene struct→struct: a única alocação extra é a série resultado (via
   bool_series_from_pair, que chama smaug_bool_create + os pares internos). */
static void allocation_failure_bool_series_and(void) {
    uint8_t left_values[3] = {1, 0, 1}, right_values[3] = {1, 1, 0};
    reset(-1);
    smaug_series_bool_t *left_series = smaug_bool_create_from_array(left_values, 3);
    smaug_series_bool_t *right_series = smaug_bool_create_from_array(right_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *series_and_series = smaug_bool_series_and(left_series, right_series);
        if (series_and_series) { OK(series_and_series->size == 3, "bool series_and size"); smaug_bool_free(series_and_series); }
    }
    smaug_bool_free(left_series); smaug_bool_free(right_series);
}
static void allocation_failure_bool_series_or(void) {
    uint8_t left_values[3] = {1, 0, 1}, right_values[3] = {1, 1, 0};
    reset(-1);
    smaug_series_bool_t *left_series = smaug_bool_create_from_array(left_values, 3);
    smaug_series_bool_t *right_series = smaug_bool_create_from_array(right_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *series_or_series = smaug_bool_series_or(left_series, right_series);
        if (series_or_series) { OK(series_or_series->size == 3, "bool series_or size"); smaug_bool_free(series_or_series); }
    }
    smaug_bool_free(left_series); smaug_bool_free(right_series);
}
static void allocation_failure_bool_series_xor(void) {
    uint8_t left_values[3] = {1, 0, 1}, right_values[3] = {1, 1, 0};
    reset(-1);
    smaug_series_bool_t *left_series = smaug_bool_create_from_array(left_values, 3);
    smaug_series_bool_t *right_series = smaug_bool_create_from_array(right_values, 3);
    assert(left_series && right_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *series_xor_series = smaug_bool_series_xor(left_series, right_series);
        if (series_xor_series) { OK(series_xor_series->size == 3, "bool series_xor size"); smaug_bool_free(series_xor_series); }
    }
    smaug_bool_free(left_series); smaug_bool_free(right_series);
}
static void allocation_failure_bool_series_not(void) {
    uint8_t left_values[3] = {1, 0, 1};
    reset(-1);
    smaug_series_bool_t *left_series = smaug_bool_create_from_array(left_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_bool_t *series_not_series = smaug_bool_series_not(left_series);
        if (series_not_series) { OK(series_not_series->size == 3, "bool series_not size"); smaug_bool_free(series_not_series); }
    }
    smaug_bool_free(left_series);
}
/* 7.4 — varre os mallocs de bool_eq/bool_ne (result + out_mask) */
static void allocation_failure_bool_equal_not_equal(void) {
    uint8_t left_values[3] = {1, 0, 1};
    reset(-1);
    smaug_series_bool_t *left_series = smaug_bool_create_from_array(left_values, 3);
    assert(left_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *null_mask = NULL;
        uint8_t *equality_mask = smaug_bool_eq(left_series, 1, &null_mask);
        if (equality_mask) { OK(null_mask != NULL, "bool eq mask junto"); free(equality_mask); free(null_mask); }
    }
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *null_mask = NULL;
        uint8_t *inequality_mask = smaug_bool_ne(left_series, 1, &null_mask);
        if (inequality_mask) { OK(null_mask != NULL, "bool ne mask junto"); free(inequality_mask); free(null_mask); }
    }
    smaug_bool_free(left_series);
}
/* COW em view de bool: set, set_null, append, append_null */
static void allocation_failure_bool_cow_set(void) {
    uint8_t source_values[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *parent_series = smaug_bool_create_from_array(source_values, 4);
    assert(parent_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_bool_t *series_view = smaug_bool_view(parent_series, 1, 2);
        assert(series_view);
        reset(allocation_index);
        smaug_status_t status = smaug_bool_set(series_view, 0, 1);
        if (status == SMG_OK) {
            OK(series_view->meta.is_view == false, "bool cow_set: view detachada");
            OK(parent_series->data[1] == 0,        "bool cow_set: pai preservada");
        } else {
            OK(status == SMG_ERR_NOMEM,      "bool cow_set OOM: status NOMEM");
            OK(series_view->meta.is_view == true,  "bool cow_set OOM: view nao detachada");
            OK(parent_series->data[1] == 0,        "bool cow_set OOM: pai preservada");
        }
        reset(-1);
        smaug_bool_free(series_view);
    }
    smaug_bool_free(parent_series);
}
static void allocation_failure_bool_cow_set_null(void) {
    uint8_t source_values[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *parent_series = smaug_bool_create_from_array(source_values, 4);
    assert(parent_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_bool_t *series_view = smaug_bool_view(parent_series, 0, 4);
        assert(series_view);
        reset(allocation_index);
        smaug_status_t status = smaug_bool_set_null(series_view, 0);
        if (status == SMG_OK) {
            OK(series_view->meta.is_view == false,      "bool cow_set_null: detachada");
            OK(parent_series->null_mask[0] == 0xFF,     "bool cow_set_null: pai preservada");
        } else {
            OK(status == SMG_ERR_NOMEM,           "bool cow_set_null OOM: NOMEM");
            OK(parent_series->null_mask[0] == 0xFF,     "bool cow_set_null OOM: pai preservada");
        }
        reset(-1);
        smaug_bool_free(series_view);
    }
    smaug_bool_free(parent_series);
}
static void allocation_failure_bool_cow_append(void) {
    uint8_t source_values[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *parent_series = smaug_bool_create_from_array(source_values, 4);
    assert(parent_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_bool_t *series_view = smaug_bool_view(parent_series, 0, 2);
        assert(series_view);
        reset(allocation_index);
        int status_code = smaug_bool_append(series_view, 1);
        OK(status_code == 0 || status_code == -1, "bool cow_append rc valido");
        if (status_code == 0) OK(series_view->meta.is_view == false, "bool cow_append: detachada");
        OK(parent_series->size == 4, "bool cow_append: pai intacta");
        reset(-1);
        smaug_bool_free(series_view);
    }
    smaug_bool_free(parent_series);
}
static void allocation_failure_bool_cow_append_null(void) {
    uint8_t source_values[4] = {1, 0, 1, 0};
    reset(-1);
    smaug_series_bool_t *parent_series = smaug_bool_create_from_array(source_values, 4);
    assert(parent_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(-1);
        smaug_series_bool_t *series_view = smaug_bool_view(parent_series, 0, 2);
        assert(series_view);
        reset(allocation_index);
        int status_code = smaug_bool_append_null(series_view);
        OK(status_code == 0 || status_code == -1, "bool cow_append_null rc valido");
        if (status_code == 0) OK(series_view->meta.is_view == false, "bool cow_append_null: detachada");
        OK(parent_series->size == 4, "bool cow_append_null: pai intacta");
        reset(-1);
        smaug_bool_free(series_view);
    }
    smaug_bool_free(parent_series);
}

/* ======================================================================
   sanidade: sem falha injetada, tudo funciona (garante que o teste não
   está sabotando além da conta)
   ====================================================================== */
static void sanity_no_fail(void) {
    reset(-1);
    smaug_series_f64_t *floating_point_series = smaug_f64_create(3);
    OK(floating_point_series != NULL, "sanidade: create sem falha funciona");
    smaug_f64_free(floating_point_series);
}

/* ======================================================================
   Anel 3 — CSV/JSON: varredura de pontos de alocação nos parsers.
   Cada falha deve retornar NULL/erro gracioso, sem crash, sem leak.
   MAX_IO_ALLOCS: teto generoso para cobrir todos os malloc/realloc/strdup
   dos parsers (CSV tem ~14, JSON tem ~16, mais margens de crescimento).
   ====================================================================== */
#define MAX_IO_ALLOCS 64

/* CSV — leitura: todos os pontos de malloc no tokenizador e no parser */
static void allocation_failure_csv_read_memory(void) {
    /* CSV simples com todos os dtypes para exercitar todas as alocações */
    const char *text_value = "i,f,b,s\n1,1.5,true,hello\n2,2.5,false,world\n";
    size_t csv_length  = strlen(text_value);
    reset(-1);
    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, csv_length, NULL);
        if (read_csv_memory_result) {
            /* pode ter succedido ou retornado tabela com erro */
            OK(!read_csv_memory_result || read_csv_memory_result->error || 1, "csv_read_mem: sem crash");
            smaug_table_free(read_csv_memory_result);
        }
    }
    /* sem falha: deve suceder */
    reset(-1);
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, csv_length, NULL);
    OK(read_csv_memory_result && !read_csv_memory_result->error && read_csv_memory_result->nrows == 2, "csv_read_mem: sucesso sem falha");
    smaug_table_free(read_csv_memory_result);
}

/* CSV — leitura com aspas RFC 4180 (exercita realloc dentro do tokenizador) */
static void allocation_failure_csv_read_quoted(void) {
    const char *text_value = "v\n\"campo com, virgula\"\n\"outro\"\n";
    size_t csv_length  = strlen(text_value);
    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, csv_length, NULL);
        if (read_csv_memory_result) { smaug_table_free(read_csv_memory_result); }
    }
    reset(-1);
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, csv_length, NULL);
    OK(read_csv_memory_result && !read_csv_memory_result->error && read_csv_memory_result->nrows == 2, "csv_read_quoted: sucesso");
    smaug_table_free(read_csv_memory_result);
}

/* CSV — leitura com muitas linhas (exercita realloc do vetor de rows) */
static void allocation_failure_csv_read_many_rows(void) {
    /* 100 linhas — força o realloc de rows[] (começa com cap=64) */
    char *text_value = malloc(8192);
    assert(text_value);
    int write_position = sprintf(text_value, "v\n");
    for (int row_index = 0; row_index < 100; row_index++) write_position += sprintf(text_value + write_position, "%d\n", row_index);
    size_t csv_length = (size_t)write_position;

    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, csv_length, NULL);
        if (read_csv_memory_result) { smaug_table_free(read_csv_memory_result); }
    }
    reset(-1);
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, csv_length, NULL);
    OK(read_csv_memory_result && !read_csv_memory_result->error && read_csv_memory_result->nrows == 100, "csv_read_many_rows: sucesso");
    smaug_table_free(read_csv_memory_result);
    free(text_value);  /* liberar sem wrap */
}

/* CSV — leitura sem header: nomes sintéticos "colN" via strdup de buffer local
 * (caminho nunca exercitado pelo allocfail antes — strdup(tmp) é um ponto de
 * alocação distinto do strdup(src) com header). */
static void allocation_failure_csv_read_no_header(void) {
    const char *text_value = "1,2.5,true\n3,4.5,false\n";
    size_t csv_length  = strlen(text_value);
    smaug_csv_opts_t default_options_result = smaug_csv_default_opts();
    default_options_result.header = 0;
    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, csv_length, &default_options_result);
        if (read_csv_memory_result) { smaug_table_free(read_csv_memory_result); }
    }
    reset(-1);
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, csv_length, &default_options_result);
    OK(read_csv_memory_result && !read_csv_memory_result->error && read_csv_memory_result->ncols == 3, "csv_read_no_header: sucesso, 3 colunas");
    smaug_table_free(read_csv_memory_result);
}

/* CSV — writer: pontos de realloc do wbuf + todos os ramos por dtype
 * (multi-coluna com NULL em cada família — a tabela antiga, de 1 coluna
 * int64 sem null, nunca exercitava os ramos st==SMG_NULL_VALUE nem a
 * coluna string nem o separador c>0 entre colunas). */
static void allocation_failure_csv_write(void) {
    smaug_series_i64_t  *integer_series = smaug_i64_create(2);
    smaug_series_f64_t  *floating_point_series = smaug_f64_create(2);
    smaug_series_bool_t *boolean_series = smaug_bool_create(2);
    smaug_series_str_t  *source_series = smaug_str_create(2);
    assert(integer_series && floating_point_series && boolean_series && source_series);
    smaug_i64_set(integer_series, 0, 1);        smaug_i64_set_null(integer_series, 1);
    smaug_f64_set_null(floating_point_series, 0);      smaug_f64_set(floating_point_series, 1, 2.5);
    smaug_bool_set(boolean_series, 0, 1);       smaug_bool_set_null(boolean_series, 1);
    smaug_str_set(source_series, 0, "a,b", 3); smaug_str_set_null(source_series, 1);

    smaug_column_t column_names[4] = {0};
    column_names[0].name = "i"; column_names[0].dtype = "int64";   column_names[0].i64     = integer_series;
    column_names[1].name = "f"; column_names[1].dtype = "float64"; column_names[1].f64     = floating_point_series;
    column_names[2].name = "b"; column_names[2].dtype = "bool";    column_names[2].boolcol = boolean_series;
    column_names[3].name = "s"; column_names[3].dtype = "string";  column_names[3].str     = source_series;

    smaug_table_t values = {0};
    values.columns = column_names; values.ncols = 4; values.nrows = 2;

    smaug_csv_write_opts_t write_default_options_result = smaug_csv_write_default_opts();
    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t length;
        char *write_csv_memory_result = smaug_write_csv_mem(&values, &write_default_options_result, &length, NULL);
        if (write_csv_memory_result) { free(write_csv_memory_result); }
    }
    reset(-1);
    size_t length;
    char *write_csv_memory_result = smaug_write_csv_mem(&values, &write_default_options_result, &length, NULL);
    OK(write_csv_memory_result != NULL && length > 0,         "csv_write: sucesso");
    OK(strstr(write_csv_memory_result, "\"a,b\"") != NULL, "csv_write: campo com vírgula escapado");
    free(write_csv_memory_result);

    /* 12.30: com err_out != NULL, o set_io_error faz strdup da causa — que pode
       falhar sob OOM. sep==decimal força o caminho de erro sem depender dos
       mallocs internos do serializador; varremos o strdup do set_io_error. */
    smaug_csv_write_opts_t write_default_options_result_2 = smaug_csv_write_default_opts();
    write_default_options_result_2.sep = ';'; write_default_options_result_2.decimal = ';';
    for (long allocation_index = 0; allocation_index < 4; allocation_index++) {
        reset(allocation_index);
        char *text_value = NULL; size_t second_length;
        char *write_csv_memory_result_2 = smaug_write_csv_mem(&values, &write_default_options_result_2, &second_length, &text_value);
        OK(write_csv_memory_result_2 == NULL, "csv_write err_out: retorna NULL em sep==decimal sob OOM");
        /* werr pode ser NULL (strdup falhou — fallback documentado) ou não;
           qualquer um é válido, o essencial é não crashar nem vazar. */
        if (text_value) smaug_free(text_value);
    }
    reset(-1);
    smaug_i64_free(integer_series); smaug_f64_free(floating_point_series); smaug_bool_free(boolean_series); smaug_str_free(source_series);
}

/* JSON — leitura: todos os pontos de malloc do tokenizador e do parser */
static void allocation_failure_json_read_memory(void) {
    const char *column_index =
        "[{\"i\":1,\"f\":1.5,\"b\":true,\"s\":\"hello\"},"
         "{\"i\":2,\"f\":2.5,\"b\":false,\"s\":\"world\"}]";
    size_t json_length = strlen(column_index);

    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, json_length);
        if (read_json_memory_result) { smaug_table_free(read_json_memory_result); }
    }
    reset(-1);
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, json_length);
    OK(read_json_memory_result && !read_json_memory_result->error && read_json_memory_result->nrows == 2 && read_json_memory_result->ncols == 4,
       "json_read_mem: sucesso");
    smaug_table_free(read_json_memory_result);
}

/* JSON — leitura com muitos records (exercita realloc do vetor de recs[]) */
static void allocation_failure_json_read_many_records(void) {
    /* 80 records — força realloc de recs[] (começa com cap=64) */
    char *column_index = malloc(8192);
    assert(column_index);
    int write_position = sprintf(column_index, "[");
    for (int row_index = 0; row_index < 80; row_index++) {
        write_position += sprintf(column_index + write_position, "{\"v\":%d}%s", row_index, row_index < 79 ? "," : "");
    }
    write_position += sprintf(column_index + write_position, "]");
    size_t json_length = (size_t)write_position;

    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, json_length);
        if (read_json_memory_result) { smaug_table_free(read_json_memory_result); }
    }
    reset(-1);
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, json_length);
    OK(read_json_memory_result && !read_json_memory_result->error && read_json_memory_result->nrows == 80, "json_read_many_records: sucesso");
    smaug_table_free(read_json_memory_result);
    free(column_index);
}

/* JSON — leitura com strings longas (exercita realloc dentro do tokenizador) */
static void allocation_failure_json_read_long_string(void) {
    /* string > 64 bytes força realloc no read_json_string */
    const char *column_index =
        "[{\"v\":\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789XY\"}]";
    size_t json_length = strlen(column_index);

    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, json_length);
        if (read_json_memory_result) { smaug_table_free(read_json_memory_result); }
    }
    reset(-1);
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, json_length);
    OK(read_json_memory_result && !read_json_memory_result->error && read_json_memory_result->nrows == 1, "json_read_long_string: sucesso");
    smaug_table_free(read_json_memory_result);
}

/* JSON — writer: pontos de realloc do wbuf */
static void allocation_failure_json_write(void) {
    smaug_series_i64_t  *integer_series = smaug_i64_create(2);
    smaug_series_f64_t  *floating_point_series = smaug_f64_create(2);
    smaug_series_bool_t *boolean_series = smaug_bool_create(2);
    smaug_series_str_t  *source_series = smaug_str_create(2);
    assert(integer_series && floating_point_series && boolean_series && source_series);
    smaug_i64_set(integer_series, 0, 1);            smaug_i64_set_null(integer_series, 1);
    smaug_f64_set(floating_point_series, 0, (double)(0.0/0.0)); smaug_f64_set_null(floating_point_series, 1); /* NaN + null */
    smaug_bool_set_null(boolean_series, 0);         smaug_bool_set(boolean_series, 1, 1);
    smaug_str_set(source_series, 0, "SP", 2);      smaug_str_set_null(source_series, 1);

    smaug_column_t column_names[4] = {0};
    column_names[0].name = "i"; column_names[0].dtype = "int64";   column_names[0].i64     = integer_series;
    column_names[1].name = "f"; column_names[1].dtype = "float64"; column_names[1].f64     = floating_point_series;
    column_names[2].name = "b"; column_names[2].dtype = "bool";    column_names[2].boolcol = boolean_series;
    column_names[3].name = "s"; column_names[3].dtype = "string";  column_names[3].str     = source_series;

    smaug_table_t values = {0};
    values.columns = column_names; values.ncols = 4; values.nrows = 2;

    smaug_json_write_opts_t values_2 = {0};
    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t length;
        char *write_json_memory_result = smaug_write_json_mem(&values, &values_2, &length, NULL);
        if (write_json_memory_result) { free(write_json_memory_result); }
    }
    reset(-1);
    size_t length;
    char *write_json_memory_result = smaug_write_json_mem(&values, &values_2, &length, NULL);
    OK(write_json_memory_result != NULL && length > 0, "json_write: sucesso");
    free(write_json_memory_result);
    smaug_i64_free(integer_series); smaug_f64_free(floating_point_series); smaug_bool_free(boolean_series); smaug_str_free(source_series);
}

/* JSON — writer com pretty=1: os branches de nl/ind/ind2 (linhas 557–570,
 * 598–610) só são exercitados quando pretty=1 — precisam de sweep próprio. */
static void allocation_failure_json_write_pretty(void) {
    smaug_series_i64_t *integer_series = smaug_i64_create(3);
    smaug_series_str_t *source_series = smaug_str_create(3);
    assert(integer_series && source_series);
    smaug_i64_set(integer_series, 0, 1); smaug_i64_set_null(integer_series, 1); smaug_i64_set(integer_series, 2, 3);
    smaug_str_set(source_series, 0, "a", 1); smaug_str_set(source_series, 1, "b", 1); smaug_str_set_null(source_series, 2);
    smaug_column_t column_names[2] = {0};
    column_names[0].name = "i"; column_names[0].dtype = "int64";  column_names[0].i64 = integer_series;
    column_names[1].name = "s"; column_names[1].dtype = "string"; column_names[1].str = source_series;
    smaug_table_t values = {0};
    values.columns = column_names; values.ncols = 2; values.nrows = 3;

    smaug_json_write_opts_t values_2 = {.pretty = 1};
    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t length;
        char *write_json_memory_result = smaug_write_json_mem(&values, &values_2, &length, NULL);
        if (write_json_memory_result) { free(write_json_memory_result); }
    }
    reset(-1);
    size_t length;
    char *write_json_memory_result = smaug_write_json_mem(&values, &values_2, &length, NULL);
    OK(write_json_memory_result != NULL && strstr(write_json_memory_result,"\n") != NULL, "json_write_pretty: sucesso");
    free(write_json_memory_result);
    smaug_i64_free(integer_series); smaug_str_free(source_series);
}

/* JSON — leitura de muitos registros: força o realloc do array de records
 * (recs[]) que começa com cap=8 e dobra (linhas 332/333). */
static void allocation_failure_json_read_many_recs(void) {
    char *column_index = malloc(8192); assert(column_index);
    int write_position = sprintf(column_index, "[");
    for (int row_index = 0; row_index < 20; row_index++) {
        write_position += sprintf(column_index+write_position, "%s{\"v\":%d}", row_index?",":"", row_index);
    }
    write_position += sprintf(column_index+write_position, "]");
    size_t json_length = (size_t)write_position;

    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, json_length);
        if (read_json_memory_result) smaug_table_free(read_json_memory_result);
    }
    reset(-1);
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, json_length);
    OK(read_json_memory_result && !read_json_memory_result->error && read_json_memory_result->nrows == 20, "json_read_many_recs: sucesso 20 linhas");
    smaug_table_free(read_json_memory_result);
    free(column_index);
}

/* JSON — registro único com muitos campos: força o realloc de keys/vals
 * DENTRO de parse_record (cap começa em 8 e dobra; L288-289). Sob allocfail,
 * o ramo !nk || !nv (L290) dispara — não alcançável por registros estreitos. */
static void allocation_failure_json_read_wide_record(void) {
    char *column_index = malloc(8192); assert(column_index);
    int write_position = sprintf(column_index, "[{");
    for (int row_index = 0; row_index < 12; row_index++) { /* 12 campos > cap inicial 8 → força realloc */
        write_position += sprintf(column_index+write_position, "%s\"k%d\":%d", row_index?",":"", row_index, row_index);
    }
    write_position += sprintf(column_index+write_position, "}]");
    size_t json_length = (size_t)write_position;

    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, json_length);
        if (read_json_memory_result) smaug_table_free(read_json_memory_result);
    }
    reset(-1);
    smaug_table_t *read_json_memory_result = smaug_read_json_mem(column_index, json_length);
    OK(read_json_memory_result && !read_json_memory_result->error && read_json_memory_result->ncols == 12, "json_read_wide_record: 12 colunas");
    smaug_table_free(read_json_memory_result);
    free(column_index);
}


static void allocation_failure_table_free_partial(void) {
    /* simula OOM a meio da construção de colunas */
    const char *text_value = "a,b,c\n1,2,3\n4,5,6\n";
    size_t csv_length  = strlen(text_value);
    /* ao falhar no meio, smaug_table_free deve lidar com colunas parciais */
    for (long allocation_index = 0; allocation_index < MAX_IO_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, csv_length, NULL);
        if (read_csv_memory_result) { smaug_table_free(read_csv_memory_result); }  /* não deve crash mesmo parcial */
    }
    reset(-1);
    smaug_table_t *read_csv_memory_result = smaug_read_csv_mem(text_value, csv_length, NULL);
    OK(read_csv_memory_result && !read_csv_memory_result->error, "table_free_partial: sucesso final");
    smaug_table_free(read_csv_memory_result);
}


/* ======================================================================
   FRENTE B — Grupo A/B (Fase 3 Ring 0): cumulativas, diff/shift, fill,
   sorted_nonnull, rank — e janela deslizante (rolling). Varre os caminhos
   de OOM dessas primitivas, antes descobertos no COVERAGE.
   ====================================================================== */

/* helper: série f64 com nulos no meio, para exercitar VALID/INVALID + fill */
static smaug_series_f64_t *make_float64_nullable(void) {
    double source_values[6] = {1, 2, 3, 4, 5, 6};
    smaug_series_f64_t *floating_point_series = smaug_f64_create_from_array(source_values, 6);
    if (floating_point_series) { smaug_f64_set_null(floating_point_series, 1); smaug_f64_set_null(floating_point_series, 3); }
    return floating_point_series;
}
static smaug_series_i64_t *make_int64_nullable(void) {
    int64_t source_values[6] = {1, 2, 3, 4, 5, 6};
    smaug_series_i64_t *integer_series = smaug_i64_create_from_array(source_values, 6);
    if (integer_series) { smaug_i64_set_null(integer_series, 1); smaug_i64_set_null(integer_series, 3); }
    return integer_series;
}

/* --- f64 Grupo A: cumulativas + diff/shift + fill --- */
#define AF_F64_UNARY(function_name, expression) \
static void function_name(void) { \
    smaug_series_f64_t *base = make_float64_nullable(); assert(base); \
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) { \
        reset(allocation_index); \
        smaug_series_f64_t *result_series = expression; \
        if (result_series) { OK(result_series->size == base->size, #function_name " size"); smaug_f64_free(result_series); } \
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
static void allocation_failure_float64_sorted_non_null(void) {
    smaug_series_f64_t *source_series = make_float64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t element_count = 0;
        double *sorted_non_null_result = smaug_f64_sorted_nonnull(source_series, &element_count);
        if (sorted_non_null_result) { OK(element_count == 4, "f64 sorted_nonnull conta"); free(sorted_non_null_result); }
    }
    smaug_f64_free(source_series);
}
static void allocation_failure_float64_rank(void) {
    smaug_series_f64_t *source_series = make_float64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        double *ranked_series = smaug_f64_rank(source_series, 0);
        if (ranked_series) { OK(1, "f64 rank ok"); free(ranked_series); }
    }
    smaug_f64_free(source_series);
}

/* --- i64 Grupo A --- */
#define AF_I64_UNARY(function_name, expression) \
static void function_name(void) { \
    smaug_series_i64_t *base = make_int64_nullable(); assert(base); \
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) { \
        reset(allocation_index); \
        smaug_series_i64_t *result_series = expression; \
        if (result_series) { OK(result_series->size == base->size, #function_name " size"); smaug_i64_free(result_series); } \
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

static void allocation_failure_int64_sorted_non_null(void) {
    smaug_series_i64_t *source_series = make_int64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t element_count = 0;
        int64_t *sorted_non_null_result = smaug_i64_sorted_nonnull(source_series, &element_count);
        if (sorted_non_null_result) { OK(element_count == 4, "i64 sorted_nonnull conta"); free(sorted_non_null_result); }
    }
    smaug_i64_free(source_series);
}
static void allocation_failure_int64_rank(void) {
    smaug_series_i64_t *source_series = make_int64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        double *ranked_series = smaug_i64_rank(source_series, 0);
        if (ranked_series) { OK(1, "i64 rank ok"); free(ranked_series); }
    }
    smaug_i64_free(source_series);
}

/* --- rolling f64 (sum/mean/min/max) — min/max usam deque interno --- */
#define AF_F64_ROLL(function_name, expression) \
static void function_name(void) { \
    smaug_series_f64_t *base = make_float64_nullable(); assert(base); \
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) { \
        reset(allocation_index); \
        smaug_series_f64_t *result_series = expression; \
        if (result_series) { OK(result_series->size == base->size, #function_name " size"); smaug_f64_free(result_series); } \
    } \
    smaug_f64_free(base); \
}
AF_F64_ROLL(af_f64_rolling_sum,  smaug_f64_rolling_sum(base, 3, 0))
AF_F64_ROLL(af_f64_rolling_mean, smaug_f64_rolling_mean(base, 3, 0))
AF_F64_ROLL(af_f64_rolling_min,  smaug_f64_rolling_min(base, 3, 0))
AF_F64_ROLL(af_f64_rolling_max,  smaug_f64_rolling_max(base, 3, 0))
/* item 8a: motor genérico (rolling_apply + pack_f64) e modo min_periods */
AF_F64_ROLL(af_f64_rolling_std,  smaug_f64_rolling_std(base, 3, 0))
AF_F64_ROLL(af_f64_rolling_var,  smaug_f64_rolling_var(base, 3, 0))
AF_F64_ROLL(af_f64_rolling_mean_mp, smaug_f64_rolling_mean(base, 3, 1))
AF_F64_ROLL(af_f64_rolling_min_mp,  smaug_f64_rolling_min(base, 3, 1))  /* rescan */
/* count f64 → i64 */
static void allocation_failure_float64_rolling_count(void) {
    smaug_series_f64_t *source_series = make_float64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *rolling_count_series = smaug_f64_rolling_count(source_series, 3, 0);
        if (rolling_count_series) { OK(rolling_count_series->size == source_series->size, "f64 rolling_count size"); smaug_i64_free(rolling_count_series); }
    }
    smaug_f64_free(source_series);
}

/* --- rolling i64 (sum/min/max → i64; mean → f64) --- */
static void allocation_failure_int64_rolling_sum(void) {
    smaug_series_i64_t *source_series = make_int64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *rolling_sum_series = smaug_i64_rolling_sum(source_series, 3, 0);
        if (rolling_sum_series) { OK(rolling_sum_series->size == source_series->size, "i64 rolling_sum size"); smaug_i64_free(rolling_sum_series); }
    }
    smaug_i64_free(source_series);
}
static void allocation_failure_int64_rolling_mean(void) {
    smaug_series_i64_t *source_series = make_int64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *rolling_mean_series = smaug_i64_rolling_mean(source_series, 3, 0);
        if (rolling_mean_series) { OK(rolling_mean_series->size == source_series->size, "i64 rolling_mean size"); smaug_f64_free(rolling_mean_series); }
    }
    smaug_i64_free(source_series);
}
static void allocation_failure_int64_rolling_minimum(void) {
    smaug_series_i64_t *source_series = make_int64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *rolling_minimum_series = smaug_i64_rolling_min(source_series, 3, 0);
        if (rolling_minimum_series) { OK(rolling_minimum_series->size == source_series->size, "i64 rolling_min size"); smaug_i64_free(rolling_minimum_series); }
    }
    smaug_i64_free(source_series);
}
static void allocation_failure_int64_rolling_maximum(void) {
    smaug_series_i64_t *source_series = make_int64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *rolling_maximum_series = smaug_i64_rolling_max(source_series, 3, 0);
        if (rolling_maximum_series) { OK(rolling_maximum_series->size == source_series->size, "i64 rolling_max size"); smaug_i64_free(rolling_maximum_series); }
    }
    smaug_i64_free(source_series);
}
/* item 8a: i64 std/var (→f64, via i64_rolling_via_motor) e count (→i64) */
static void allocation_failure_int64_rolling_standard_deviation(void) {
    smaug_series_i64_t *source_series = make_int64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *rolling_standard_deviation_series = smaug_i64_rolling_std(source_series, 3, 0);
        if (rolling_standard_deviation_series) { OK(rolling_standard_deviation_series->size == source_series->size, "i64 rolling_std size"); smaug_f64_free(rolling_standard_deviation_series); }
    }
    smaug_i64_free(source_series);
}
static void allocation_failure_int64_rolling_variance(void) {
    smaug_series_i64_t *source_series = make_int64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_f64_t *rolling_variance_series = smaug_i64_rolling_var(source_series, 3, 0);
        if (rolling_variance_series) { OK(rolling_variance_series->size == source_series->size, "i64 rolling_var size"); smaug_f64_free(rolling_variance_series); }
    }
    smaug_i64_free(source_series);
}
static void allocation_failure_int64_rolling_count(void) {
    smaug_series_i64_t *source_series = make_int64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *rolling_count_series = smaug_i64_rolling_count(source_series, 3, 0);
        if (rolling_count_series) { OK(rolling_count_series->size == source_series->size, "i64 rolling_count size"); smaug_i64_free(rolling_count_series); }
    }
    smaug_i64_free(source_series);
}
static void allocation_failure_int64_rolling_minimum_mp(void) {  /* rescan type-preserving */
    smaug_series_i64_t *source_series = make_int64_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_i64_t *rolling_minimum_series = smaug_i64_rolling_min(source_series, 3, 1);
        if (rolling_minimum_series) { OK(rolling_minimum_series->size == source_series->size, "i64 rolling_min mp size"); smaug_i64_free(rolling_minimum_series); }
    }
    smaug_i64_free(source_series);
}

/* ======================================================================
   FRENTE B fase 2 — Anel 3: datetime (lifecycle + ops que alocam).
   datetime estava SEM cobertura allocfail; a auditoria das exclusoes
   revelou varias "coberto por test_allocfail" que de fato NAO eram
   cobertas (conveniencia disfarcada). Esta frente as torna verdadeiras
   ou expoe o ramo para teste.
   ====================================================================== */
static smaug_series_dt_t *make_datetime_nullable(void) {
    int64_t source_values[6] = {1000, 2000, 3000, 4000, 5000, 6000};
    smaug_series_dt_t *source_series = smaug_dt_create_from_array(source_values, 6);
    if (source_series) { smaug_dt_set_null(source_series, 1); smaug_dt_set_null(source_series, 3); }
    return source_series;
}

static void allocation_failure_datetime_create(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_dt_t *source_series = smaug_dt_create(5);
        if (source_series) { OK(source_series->size == 5, "dt create size"); smaug_dt_free(source_series); }
    }
}
static void allocation_failure_datetime_create_from_array(void) {
    int64_t source_values[4] = {1, 2, 3, 4};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_dt_t *source_series = smaug_dt_create_from_array(source_values, 4);
        if (source_series) { OK(source_series->size == 4, "dt from_array size"); smaug_dt_free(source_series); }
    }
}
static void allocation_failure_datetime_clone(void) {
    smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_dt_t *source_series_2 = smaug_dt_clone(source_series);
        if (source_series_2) { OK(source_series_2->size == source_series->size, "dt clone size"); smaug_dt_free(source_series_2); }
    }
    smaug_dt_free(source_series);
}
static void allocation_failure_datetime_view(void) {
    smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_dt_t *source_series_2 = smaug_dt_view(source_series, 0, 3);
        if (source_series_2) { OK(source_series_2->size == 3, "dt view size"); smaug_dt_free(source_series_2); }
    }
    smaug_dt_free(source_series);
}
static void allocation_failure_datetime_append_grow(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        smaug_series_dt_t *source_series = smaug_dt_create_with_capacity(0, 0);
        assert(source_series);
        reset(allocation_index);
        int status_code = smaug_dt_append(source_series, 1234);
        OK(status_code == 0 || status_code == -1, "dt append rc valido");
        if (status_code == 0) OK(source_series->size == 1, "dt append cresceu");
        else         OK(source_series->size == 0, "dt append falhou sem corromper");
        reset(-1);
        smaug_dt_free(source_series);
    }
}
/* 10.4 fatia A: os 11 componentes em versao de serie. Uma varredura por
   funcao -- sao corpos distintos apos a macro. */
static void allocation_failure_datetime_components(void) {
    typedef smaug_series_i64_t *(*compfn)(const smaug_series_dt_t *);
    compfn source_values[] = { smaug_dt_year_series, smaug_dt_month_series,
                     smaug_dt_day_series, smaug_dt_hour_series,
                     smaug_dt_minute_series, smaug_dt_second_series,
                     smaug_dt_ms_series, smaug_dt_weekday_series,
                     smaug_dt_yearday_series, smaug_dt_quarter_series,
                     smaug_dt_week_series };
    int64_t source_values_2[3] = {0, 86400000, 1735689600000LL};
    reset(-1);
    smaug_series_dt_t *left_series = smaug_dt_create_from_array(source_values_2, 3);
    assert(left_series);
    for (size_t filtered_series = 0; filtered_series < sizeof(source_values)/sizeof(source_values[0]); filtered_series++) {
        for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
            reset(allocation_index);
            smaug_series_i64_t *source_series = source_values[filtered_series](left_series);
            if (source_series) { OK(source_series->size == 3, "dt componente size ok"); smaug_i64_free(source_series); }
        }
    }
    smaug_dt_free(left_series);
}
static void allocation_failure_datetime_between(void) {
    int64_t source_values[3] = {0, 1000, 2000};
    reset(-1);
    smaug_series_dt_t *source_series = smaug_dt_create_from_array(source_values, 3);
    assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_mask_t *null_mask = NULL;
        uint8_t *between_result = smaug_dt_between(source_series, 0, 2000, true, true, &null_mask);
        if (between_result) { OK(null_mask != NULL, "dt between mask junto"); free(between_result); free(null_mask); }
    }
    smaug_dt_free(source_series);
}
static void allocation_failure_datetime_argsort(void) {
    smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t *indices = smaug_dt_argsort(source_series, true);
        if (indices) { OK(1, "dt argsort ok"); free(indices); }
    }
    smaug_dt_free(source_series);
}
static void allocation_failure_datetime_sort(void) {
    smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_dt_t *source_series_2 = smaug_dt_sort(source_series, true);
        if (source_series_2) { OK(source_series_2->size == source_series->size, "dt sort size"); smaug_dt_free(source_series_2); }
    }
    smaug_dt_free(source_series);
}
static void allocation_failure_datetime_take(void) {
    smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
    size_t indices[3] = {0, 2, 4};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_dt_t *source_series_2 = smaug_dt_take(source_series, indices, 3);
        if (source_series_2) { OK(source_series_2->size == 3, "dt take size"); smaug_dt_free(source_series_2); }
    }
    smaug_dt_free(source_series);
}
static void allocation_failure_datetime_filter(void) {
    smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
    uint8_t source_values[6] = {1, 0, 1, 0, 1, 0};
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_dt_t *source_series_2 = smaug_dt_filter(source_series, source_values);
        if (source_series_2) { OK(1, "dt filter ok"); smaug_dt_free(source_series_2); }
    }
    smaug_dt_free(source_series);
}
static void allocation_failure_datetime_forward_fill(void) {
    smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);  /* NAs em 1 e 3 */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_dt_t *source_series_2 = smaug_dt_ffill(source_series);
        if (source_series_2) { OK(source_series_2->size == 6, "dt ffill size"); smaug_dt_free(source_series_2); }
    }
    smaug_dt_free(source_series);
}
static void allocation_failure_datetime_backward_fill(void) {
    smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_dt_t *source_series_2 = smaug_dt_bfill(source_series);
        if (source_series_2) { OK(source_series_2->size == 6, "dt bfill size"); smaug_dt_free(source_series_2); }
    }
    smaug_dt_free(source_series);
}
static void allocation_failure_datetime_shift(void) {
    smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        smaug_series_dt_t *source_series_2 = smaug_dt_shift(source_series, -2);
        if (source_series_2) { OK(source_series_2->size == 6, "dt shift size"); smaug_dt_free(source_series_2); }
    }
    smaug_dt_free(source_series);
}
static void allocation_failure_datetime_rank(void) {
    smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);  /* NAs + empates */
    /* exercita malloc(result) + malloc(pairs) + qsort */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        double *ranked_series = smaug_dt_rank(source_series, 0);
        if (ranked_series) { OK(1, "dt rank ok"); free(ranked_series); }
    }
    smaug_dt_free(source_series);
}

/* dt setters sob OOM: dt_set/set_null/append fazem dt_cow_detach (e append
 * faz dt_grow) — esses caminhos de NOMEM (L244/253/266/278/280) só são
 * alcançados quando a série é uma VIEW (is_view=true); escrever numa view
 * dispara o detach copy-on-write, que aloca. clone() NÃO cria view — só
 * dt_view() marca is_view, então é ela que exercita o caminho COW. */
/* dt comparadores sob OOM: os 6 macros DT_CMP_IMPL fazem 2 malloc cada
 * (result + mask) — nunca exercitados sob allocfail antes. Cobre o ramo
 * !result e !mask (free(result)) de cada operador. */
static void allocation_failure_datetime_compare(void) {
    int64_t source_values[4] = {10, 20, 30, 40};
    typedef uint8_t* (*cmp_fn)(const smaug_series_dt_t*, int64_t, smaug_mask_t**);
    cmp_fn source_values_2[6] = {
        smaug_dt_gt, smaug_dt_lt, smaug_dt_eq,
        smaug_dt_ge, smaug_dt_le, smaug_dt_ne
    };
    for (int operation_index = 0; operation_index < 6; operation_index++) {
        smaug_series_dt_t *source_series = smaug_dt_create_from_array(source_values, 4); assert(source_series);
        for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
            reset(allocation_index);
            smaug_mask_t *mask = NULL;
            uint8_t *source_values_3 = source_values_2[operation_index](source_series, 25, &mask);
            if (source_values_3) { OK(1, "dt compare ok"); free(source_values_3); free(mask); }
        }
        reset(-1);
        smaug_dt_free(source_series);
    }
}

static void allocation_failure_datetime_setters(void) {
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
        smaug_series_dt_t *source_series_2 = smaug_dt_view(source_series, 0, 4); /* is_view=true */
        if (!source_series_2) { smaug_dt_free(source_series); reset(-1); continue; }
        reset(allocation_index);
        smaug_status_t status = smaug_dt_set(source_series_2, 0, 999); /* dispara dt_cow_detach */
        OK(status == SMG_OK || status == SMG_ERR_NOMEM, "dt_set view: status válido");
        reset(-1);
        smaug_dt_free(source_series_2); smaug_dt_free(source_series);
    }
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
        smaug_series_dt_t *source_series_2 = smaug_dt_view(source_series, 0, 4);
        if (!source_series_2) { smaug_dt_free(source_series); reset(-1); continue; }
        reset(allocation_index);
        smaug_status_t status = smaug_dt_set_null(source_series_2, 0); /* dispara dt_cow_detach */
        OK(status == SMG_OK || status == SMG_ERR_NOMEM, "dt_set_null view: status válido");
        reset(-1);
        smaug_dt_free(source_series_2); smaug_dt_free(source_series);
    }
    /* append numa view: dt_cow_detach + dt_grow */
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        smaug_series_dt_t *source_series = make_datetime_nullable(); assert(source_series);
        smaug_series_dt_t *source_series_2 = smaug_dt_view(source_series, 0, 4);
        if (!source_series_2) { smaug_dt_free(source_series); reset(-1); continue; }
        reset(allocation_index);
        int status_code = smaug_dt_append(source_series_2, 1234); /* detach + grow */
        OK(status_code == 0 || status_code == -1, "dt_append view: rc válido");
        reset(-1);
        smaug_dt_free(source_series_2); smaug_dt_free(source_series);
    }
}

/* multi_argsort: OOM nos dois malloc (idx linha 110, tmp linha 113) */
static void allocation_failure_multi_argsort(void) {
    smaug_series_f64_t *source_series = make_float64_nullable(); assert(source_series);
    /* preenche os nulos para ter série densa (multi_argsort não aceita nulls) */
    smaug_f64_set(source_series, 1, 2.5); smaug_f64_set(source_series, 3, 4.5);
    smaug_sort_col_t column = { .kind = SMAUG_COL_F64, .f64 = source_series };
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t *indices = smaug_multi_argsort(&column, 1, 6);
        if (indices) { OK(1, "multi_argsort ok"); free(indices); }
    }
    smaug_f64_free(source_series);
}

/* multi_argsort_ffi: OOM no malloc de cols (linha 136) + propaga aos internos */
static void allocation_failure_multi_argsort_ffi(void) {
    smaug_series_f64_t *source_series = make_float64_nullable(); assert(source_series);
    smaug_f64_set(source_series, 1, 2.5); smaug_f64_set(source_series, 3, 4.5);
    smaug_sort_col_ffi_t column = { .kind = SMAUG_COL_F64, .ptr = source_series };
    for (long allocation_index = 0; allocation_index < MAX_ALLOCS; allocation_index++) {
        reset(allocation_index);
        size_t *indices = smaug_multi_argsort_ffi(&column, 1, 6);
        if (indices) { OK(1, "multi_argsort_ffi ok"); free(indices); }
    }
    smaug_f64_free(source_series);
}

static void allocation_failure_strict_datetime(void) {
    reset(-1);
    smaug_series_str_t *source = smaug_str_create(2);
    assert(source);
    assert(smaug_str_set(source, 1, "1970-01-01", 10) == 0);
    smaug_series_dt_t *output = NULL;
    size_t error_index = 77;
    reset(-1);
    OK(smaug_str_to_dt_checked(source, 0, &output, &error_index) == SMG_OK,
       "str->dt baseline sem falha");
    long total_allocations = allocation_count;
    smaug_dt_free(output);
    OK(total_allocations > 0, "str->dt injecao cobre alocacoes reais");
    for (long allocation_index = 0; allocation_index < total_allocations; allocation_index++) {
        output = NULL;
        reset(allocation_index);
        OK(smaug_str_to_dt_checked(source, 0, &output, &error_index) == SMG_ERR_NOMEM,
           "str->dt OOM nao vira NA ou erro de elemento");
        OK(output == NULL && error_index == 77, "OOM preserva out e indice");
        size_t text_length = 0;
        const char *text = smaug_str_get(source, 1, &text_length);
        OK(smaug_str_is_null(source, 0) && text_length == 10 && memcmp(text, "1970-01-01", 10) == 0,
           "OOM preserva entrada");
    }
    reset(-1);
    smaug_str_free(source);
}

static void allocation_failure_numeric_datetime(void) {
    reset(-1);
    smaug_series_i64_t *integer_source = smaug_i64_create(2);
    smaug_series_f64_t *real_source = smaug_f64_create(2);
    smaug_series_dt_t *original_output = smaug_dt_create(1);
    assert(integer_source && real_source && original_output);
    smaug_i64_set(integer_source, 1, 123);
    smaug_f64_set(real_source, 1, 123);
    for (int source_kind = 0; source_kind < 2; source_kind++) {
        size_t error_index = 77;
        smaug_series_dt_t *output = NULL;
        reset(-1);
        smaug_status_t status = source_kind == 0
            ? smaug_i64_to_dt_checked(integer_source, &output, &error_index)
            : smaug_f64_to_dt_checked(real_source, &output, &error_index);
        long total_allocations = allocation_count;
        OK(status == SMG_OK && total_allocations > 0, "numeric->dt baseline aloca e converte");
        smaug_dt_free(output);
        for (long allocation_index = 0; allocation_index < total_allocations; allocation_index++) {
            output = original_output;
            reset(allocation_index);
            status = source_kind == 0
                ? smaug_i64_to_dt_checked(integer_source, &output, &error_index)
                : smaug_f64_to_dt_checked(real_source, &output, &error_index);
            OK(status == SMG_ERR_NOMEM, "numeric->dt OOM tem status proprio");
            OK(output == original_output && error_index == 77, "numeric->dt OOM preserva saidas");
            OK(smaug_i64_get(integer_source, 1, NULL) == 123 && smaug_i64_is_null(integer_source, 0)
               && smaug_f64_get(real_source, 1, NULL) == 123 && smaug_f64_is_null(real_source, 0),
               "numeric->dt OOM preserva entradas");
        }
    }
    reset(-1);
    smaug_dt_free(original_output);
    smaug_i64_free(integer_source);
    smaug_f64_free(real_source);
}

int main(void) {
    allocation_failure_numeric_datetime();
    allocation_failure_strict_datetime();
    allocation_failure_float64_create();
    allocation_failure_float64_create_from_array();
    allocation_failure_float64_clone();
    allocation_failure_float64_view();
    allocation_failure_float64_append_grow();
    allocation_failure_float64_add();
    allocation_failure_float64_subtract();
    allocation_failure_float64_multiply();
    allocation_failure_float64_divide();
    allocation_failure_float64_add_scalar();
    allocation_failure_float64_subtract_scalar();
    allocation_failure_float64_multiply_scalar();
    allocation_failure_float64_divide_scalar();
    allocation_failure_float64_compare();
    allocation_failure_float64_less_than();
    allocation_failure_float64_equal();
    allocation_failure_float64_greater_or_equal();
    allocation_failure_float64_less_or_equal();
    allocation_failure_float64_not_equal();
    allocation_failure_float64_between();
    allocation_failure_float64_math();
    allocation_failure_math_dtype_preserving();
    allocation_failure_float64_argsort();
    allocation_failure_float64_sort();
    allocation_failure_float64_take();
    allocation_failure_float64_filter();

    allocation_failure_int64_create();
    allocation_failure_int64_create_from_array();
    allocation_failure_int64_clone();
    allocation_failure_int64_view();
    allocation_failure_int64_append_grow();
    allocation_failure_int64_add();
    allocation_failure_int64_subtract();
    allocation_failure_int64_multiply();
    allocation_failure_int64_divide();
    allocation_failure_int64_add_scalar();
    allocation_failure_int64_subtract_scalar();
    allocation_failure_int64_multiply_scalar();
    allocation_failure_int64_divide_scalar();
    allocation_failure_int64_compare();
    allocation_failure_int64_less_than();
    allocation_failure_int64_equal();
    allocation_failure_int64_greater_or_equal();
    allocation_failure_int64_less_or_equal();
    allocation_failure_int64_not_equal();
    allocation_failure_int64_between();
    allocation_failure_int64_argsort();
    allocation_failure_int64_sort();
    allocation_failure_int64_take();
    allocation_failure_int64_filter();

    allocation_failure_string_create();
    allocation_failure_string_create_from_array();
    allocation_failure_string_clone();
    allocation_failure_string_set_grow();
    allocation_failure_string_append_grow();
    allocation_failure_string_append_null_grow();
    allocation_failure_string_view_cow();
    allocation_failure_string_compare();
    allocation_failure_string_greater_or_equal();
    allocation_failure_string_less_or_equal();
    allocation_failure_string_between();
    allocation_failure_string_not_equal();
    allocation_failure_string_filter();
    allocation_failure_string_take();
    allocation_failure_string_forward_fill();
    allocation_failure_string_backward_fill();
    allocation_failure_string_shift();
    allocation_failure_string_rank();
    allocation_failure_string_argsort();
    allocation_failure_string_sort();

    allocation_failure_float64_cow_set();
    allocation_failure_float64_cow_set_null();
    allocation_failure_int64_cow_set();
    allocation_failure_int64_cow_set_null();
    allocation_failure_float64_cow_append();
    allocation_failure_float64_cow_append_null();
    allocation_failure_int64_cow_append();
    allocation_failure_int64_cow_append_null();

    allocation_failure_bool_and();
    allocation_failure_bool_or();
    allocation_failure_bool_xor();
    allocation_failure_bool_not();

    /* bool struct-based (dtype de primeira classe) */
    allocation_failure_bool_create();
    allocation_failure_bool_create_from_array();
    allocation_failure_bool_clone();
    allocation_failure_bool_view();
    allocation_failure_bool_append_grow();
    allocation_failure_bool_take();
    allocation_failure_bool_filter();
    allocation_failure_bool_forward_fill();
    allocation_failure_bool_backward_fill();
    allocation_failure_bool_shift();
    allocation_failure_bool_rank();
    allocation_failure_bool_argsort();
    allocation_failure_bool_sort();
    allocation_failure_bool_series_and();
    allocation_failure_bool_series_or();
    allocation_failure_bool_series_xor();
    allocation_failure_bool_series_not();
    allocation_failure_bool_equal_not_equal();
    allocation_failure_bool_cow_set();
    allocation_failure_bool_cow_set_null();
    allocation_failure_bool_cow_append();
    allocation_failure_bool_cow_append_null();

    /* Anel 3 — parsers CSV e JSON */
    allocation_failure_csv_read_memory();
    allocation_failure_csv_read_quoted();
    allocation_failure_csv_read_many_rows();
    allocation_failure_csv_read_no_header();
    allocation_failure_csv_write();
    allocation_failure_json_read_memory();
    allocation_failure_json_read_many_records();
    allocation_failure_json_read_long_string();
    allocation_failure_json_write();
    allocation_failure_json_write_pretty();
    allocation_failure_json_read_many_recs();
    allocation_failure_json_read_wide_record();
    allocation_failure_table_free_partial();

    /* Frente B — Grupo A/B (Fase 3) e rolling */
    af_f64_cumsum(); af_f64_cumprod(); af_f64_cummin(); af_f64_cummax();
    af_f64_diff(); af_f64_shift(); af_f64_ffill(); af_f64_bfill();
    allocation_failure_float64_sorted_non_null(); allocation_failure_float64_rank();
    af_i64_cumsum(); af_i64_cumprod(); af_i64_cummin(); af_i64_cummax();
    af_i64_diff(); af_i64_shift(); af_i64_ffill(); af_i64_bfill();
    allocation_failure_int64_sorted_non_null(); allocation_failure_int64_rank();
    af_f64_rolling_sum(); af_f64_rolling_mean(); af_f64_rolling_min(); af_f64_rolling_max();
    af_f64_rolling_std(); af_f64_rolling_var(); allocation_failure_float64_rolling_count();
    af_f64_rolling_mean_mp(); af_f64_rolling_min_mp();
    allocation_failure_int64_rolling_standard_deviation(); allocation_failure_int64_rolling_variance(); allocation_failure_int64_rolling_count(); allocation_failure_int64_rolling_minimum_mp();
    allocation_failure_int64_rolling_sum(); allocation_failure_int64_rolling_mean(); allocation_failure_int64_rolling_minimum(); allocation_failure_int64_rolling_maximum();

    /* Frente B fase 2 — datetime (lifecycle + argsort/sort/take/filter) */
    allocation_failure_datetime_create(); allocation_failure_datetime_create_from_array(); allocation_failure_datetime_clone(); allocation_failure_datetime_view();
    allocation_failure_datetime_append_grow(); allocation_failure_datetime_between(); allocation_failure_datetime_components(); allocation_failure_datetime_argsort(); allocation_failure_datetime_sort(); allocation_failure_datetime_take(); allocation_failure_datetime_filter();
    allocation_failure_datetime_forward_fill(); allocation_failure_datetime_backward_fill(); allocation_failure_datetime_shift(); allocation_failure_datetime_rank();
    allocation_failure_datetime_setters();
    allocation_failure_datetime_compare();

    /* Grupo C — multi_argsort (idx/tmp/cols OOM) */
    allocation_failure_multi_argsort(); allocation_failure_multi_argsort_ffi();

    sanity_no_fail();

    printf("PASS: alloc-failure varreu todos os pontos (%ld verificacoes)\n", passed_checks);
    return 0;
}
