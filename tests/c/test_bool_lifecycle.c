/* tests/test_bool_lifecycle.c
 *
 * Teste do dtype `bool` de primeira classe no Anel 0 (smaug_series_bool_t).
 * Cobre lifecycle, acesso, COW, seleção, agregação, lógica Kleene struct-based
 * e ordenação — incluindo os ramos defensivos (NULL, OOB, mismatch, recusa de
 * NULL no sort). Espelha o rigor de test_string.c.
 *
 * Rode da raiz:  gcc -I./include tests/test_bool_lifecycle.c <SRCS> -lm && ./a.out
 */

#include "../include/smaug.h"
#include <assert.h>
#include <stdio.h>

static int passed_checks = 0;
#define OK(condition, message) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU: %s\n", message); return 1; } passed_checks++; } while (0)

/* helper: cria série de "01N" (0=false, 1=true, N=null) */
static smaug_series_bool_t *make_boolean_series(const char *text_value) {
    size_t element_count = 0; while (text_value[element_count]) element_count++;
    smaug_series_bool_t *right_series = smaug_bool_create(element_count);
    for (size_t row_index = 0; row_index < element_count; row_index++) {
        if (text_value[row_index] == 'N') smaug_bool_set_null(right_series, row_index);
        else smaug_bool_set(right_series, row_index, (uint8_t)(text_value[row_index] == '1'));
    }
    return right_series;
}
static char read_boolean(smaug_series_bool_t *right_series, size_t row_index) {
    if (smaug_bool_is_null(right_series, row_index)) return 'N';
    return smaug_bool_get(right_series, row_index, NULL) ? '1' : '0';
}

/* ---- lifecycle: create, set/get, normalização, null ---- */
static int test_lifecycle(void) {
    smaug_series_bool_t *boolean_series = smaug_bool_create(3);
    OK(boolean_series != NULL, "create nao-nulo");
    OK(boolean_series->size == 3 && boolean_series->capacity == 3, "create size/capacity");
    OK(smaug_bool_is_null(boolean_series, 0), "create: tudo NULL");

    smaug_status_t status;
    OK(smaug_bool_set(boolean_series, 0, 1) == SMG_OK, "set true");
    OK(smaug_bool_set(boolean_series, 1, 0) == SMG_OK, "set false");
    OK(smaug_bool_set(boolean_series, 2, 42) == SMG_OK, "set nao-zero");
    OK(smaug_bool_get(boolean_series, 0, &status) == 1 && status == SMG_OK, "get true");
    OK(smaug_bool_get(boolean_series, 1, &status) == 0 && status == SMG_OK, "get false");
    OK(smaug_bool_get(boolean_series, 2, &status) == 1, "get: 42 normaliza p/ 1");

    OK(smaug_bool_set_null(boolean_series, 0) == SMG_OK, "set_null");
    OK(smaug_bool_is_null(boolean_series, 0), "is_null apos set_null");
    smaug_bool_get(boolean_series, 0, &status); OK(status == SMG_NULL_VALUE, "get null -> SMG_NULL_VALUE");

    smaug_bool_free(boolean_series);
    return 0;
}

/* ---- ramos defensivos: NULL, OOB ---- */
static int test_guards(void) {
    smaug_status_t status;
    OK(smaug_bool_get(NULL, 0, &status) == 0 && status == SMG_ERR_ARGUMENT, "get(NULL) -> ARGUMENT");
    OK(smaug_bool_set(NULL, 0, 1) == SMG_ERR_ARGUMENT, "set(NULL) -> ARGUMENT");
    OK(smaug_bool_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "set_null(NULL) -> ARGUMENT");
    OK(smaug_bool_is_null(NULL, 0) == true, "is_null(NULL) -> true");
    OK(smaug_bool_append(NULL, 1) == -1, "append(NULL) -> -1");
    OK(smaug_bool_append_null(NULL) == -1, "append_null(NULL) -> -1");
    OK(smaug_bool_clone(NULL) == NULL, "clone(NULL) -> NULL");

    /* status == NULL combinado com erro: cobre o ramo `if (status)` em cada
       caminho de saída do get (serie NULL, OOB, e null-value). */
    OK(smaug_bool_get(NULL, 0, NULL) == 0, "get(NULL, status=NULL) -> 0");

    smaug_series_bool_t *boolean_series = smaug_bool_create(2);
    OK(smaug_bool_set(boolean_series, 99, 1) == SMG_ERR_OOB, "set OOB");
    smaug_bool_get(boolean_series, 99, &status); OK(status == SMG_ERR_OOB, "get OOB -> OOB");
    OK(smaug_bool_get(boolean_series, 99, NULL) == 0, "get OOB (status=NULL) -> 0");  /* ramo status em OOB */
    smaug_bool_set_null(boolean_series, 0);
    smaug_bool_get(boolean_series, 0, &status); OK(status == SMG_NULL_VALUE, "get null -> NULL_VALUE");
    OK(smaug_bool_get(boolean_series, 0, NULL) == 0, "get null (status=NULL) -> 0");  /* ramo status em null */
    OK(smaug_bool_get(boolean_series, 1, NULL) == 0, "get valido (status=NULL) -> valor");  /* ramo status em SMG_OK */
    OK(smaug_bool_is_null(boolean_series, 99) == true, "is_null OOB -> true");
    OK(smaug_bool_view(boolean_series, 1, 5) == NULL, "view OOB -> NULL");
    OK(smaug_bool_set(NULL, 0, 1) == SMG_ERR_ARGUMENT, "set(NULL) idx valido");
    OK(smaug_bool_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "set_null(NULL) idx valido");
    smaug_bool_free(boolean_series);

    smaug_bool_free(NULL);   /* NULL-safe */
    OK(1, "free(NULL) seguro");

    /* with_capacity: size > capacity -> NULL (ramo :467) */
    OK(smaug_bool_create_with_capacity(5, 2) == NULL, "with_capacity size>cap -> NULL");

    /* clone de serie vazia: ramo `s->size > 0` falso (:526) */
    smaug_series_bool_t *empty = smaug_bool_create(0);
    smaug_series_bool_t *cloned_series = smaug_bool_clone(empty);
    OK(cloned_series != NULL && cloned_series->size == 0, "clone de vazio -> vazio");
    smaug_bool_free(cloned_series);

    /* view guards isolados (:538): start>size e len>size-start */
    smaug_series_bool_t *boolean_series_2 = smaug_bool_create(3);
    OK(smaug_bool_view(boolean_series_2, 4, 0) == NULL, "view start>size -> NULL");
    OK(smaug_bool_view(boolean_series_2, 1, 5) == NULL, "view len>size-start -> NULL");
    OK(smaug_bool_view(NULL, 0, 1) == NULL, "view(NULL) -> NULL");

    /* COW detach de view vazia: ramo `s->size == 0` (:556).
       view de len 0; mutar forca detach com size 0. */
    smaug_series_bool_t *series_view = smaug_bool_view(boolean_series_2, 1, 0);
    OK(series_view != NULL && series_view->size == 0, "view vazia criada");
    OK(smaug_bool_append(series_view, 1) == 0, "append em view vazia (detach size==0)");
    OK(series_view->size == 1 && !series_view->meta.is_view, "view vazia detachada e cresceu");
    smaug_bool_free(series_view);

    /* set_null OOB (:598) */
    OK(smaug_bool_set_null(boolean_series_2, 99) == SMG_ERR_OOB, "set_null OOB -> OOB");
    smaug_bool_free(boolean_series_2);
    smaug_bool_free(empty);
    return 0;
}

/* ---- clone independente + COW em view ---- */
static int test_clone_cow(void) {
    smaug_series_bool_t *source_series = make_boolean_series("101");
    smaug_series_bool_t *cloned_series = smaug_bool_clone(source_series);
    smaug_bool_set(cloned_series, 1, 1);
    OK(smaug_bool_get(source_series, 1, NULL) == 0, "clone independente: original intacto");

    smaug_series_bool_t *series_view = smaug_bool_view(source_series, 1, 2);
    OK(series_view && series_view->size == 2, "view criada");
    OK(series_view->meta.is_view && series_view->meta.external_alloc, "view flags");
    smaug_bool_set(series_view, 0, 1);   /* materializa (COW detach) */
    OK(smaug_bool_get(source_series, 1, NULL) == 0, "COW: pai intacta apos set na view");
    OK(smaug_bool_get(series_view, 0, NULL) == 1, "COW: view tem valor novo");
    OK(!series_view->meta.is_view, "COW: view detached vira dona");

    /* COW via append em view */
    smaug_series_bool_t *series_view_2 = smaug_bool_view(source_series, 0, 2);
    smaug_bool_append(series_view_2, 1);
    OK(series_view_2->size == 3, "append em view incrementa");
    OK(source_series->size == 3, "pai mantem tamanho original");

    smaug_bool_free(source_series); smaug_bool_free(cloned_series); smaug_bool_free(series_view); smaug_bool_free(series_view_2);
    return 0;
}

/* ---- append dinâmico (grow) ---- */
static int test_append(void) {
    smaug_series_bool_t *left_series = smaug_bool_create(0);
    for (int row_index = 0; row_index < 20; row_index++) OK(smaug_bool_append(left_series, row_index % 2) == 0, "append");
    OK(smaug_bool_append_null(left_series) == 0, "append_null");
    OK(left_series->size == 21, "append size apos grow");
    OK(smaug_bool_get(left_series, 0, NULL) == 0 && smaug_bool_get(left_series, 1, NULL) == 1, "append valores");
    OK(smaug_bool_is_null(left_series, 20), "append_null preserva NA");
    smaug_bool_free(left_series);

    uint8_t source_values[] = {0, 5, 0, 99};
    smaug_series_bool_t *boolean_series = smaug_bool_create_from_array(source_values, 4);
    OK(boolean_series && smaug_bool_get(boolean_series, 1, NULL) == 1 && smaug_bool_get(boolean_series, 3, NULL) == 1,
       "from_array normaliza nao-zero");
    OK(smaug_bool_get(boolean_series, 0, NULL) == 0, "from_array zero");
    OK(smaug_bool_create_from_array(NULL, 3) == NULL, "from_array(NULL) -> NULL");
    smaug_bool_free(boolean_series);
    return 0;
}

/* ---- tabela-verdade Kleene completa (struct-based) ---- */
static int test_kleene(void) {
    smaug_series_bool_t *left_series = make_boolean_series("111000NNN");
    smaug_series_bool_t *right_series = make_boolean_series("10N10N10N");

    smaug_series_bool_t *source_series;
    const char *expected_and = "10N000N0N";
    const char *expected_or  = "11110N1NN";
    const char *expected_xor = "01N10NNNN";

    source_series = smaug_bool_series_and(left_series, right_series);
    for (int row_index = 0; row_index < 9; row_index++) OK(read_boolean(source_series, row_index) == expected_and[row_index], "Kleene AND");
    smaug_bool_free(source_series);
    source_series = smaug_bool_series_or(left_series, right_series);
    for (int row_index = 0; row_index < 9; row_index++) OK(read_boolean(source_series, row_index) == expected_or[row_index], "Kleene OR");
    smaug_bool_free(source_series);
    source_series = smaug_bool_series_xor(left_series, right_series);
    for (int row_index = 0; row_index < 9; row_index++) OK(read_boolean(source_series, row_index) == expected_xor[row_index], "Kleene XOR");
    smaug_bool_free(source_series);
    source_series = smaug_bool_series_not(left_series);
    const char *expected_not = "000111NNN";
    for (int row_index = 0; row_index < 9; row_index++) OK(read_boolean(source_series, row_index) == expected_not[row_index], "Kleene NOT");
    smaug_bool_free(source_series);

    /* mismatch e NULL — cobre cada operando do guard `!a || !b || size` (MC/DC) */
    smaug_series_bool_t *small = make_boolean_series("1");
    OK(smaug_bool_series_and(left_series, small) == NULL, "and mismatch -> NULL");
    OK(smaug_bool_series_or(left_series, small)  == NULL, "or mismatch -> NULL");
    OK(smaug_bool_series_xor(left_series, small) == NULL, "xor mismatch -> NULL");
    OK(smaug_bool_series_and(NULL, right_series)  == NULL, "and(NULL, b) -> NULL");   /* !a */
    OK(smaug_bool_series_and(left_series, NULL)  == NULL, "and(a, NULL) -> NULL");   /* !b */
    OK(smaug_bool_series_or(NULL, right_series)   == NULL, "or(NULL, b) -> NULL");    /* !a */
    OK(smaug_bool_series_or(left_series, NULL)   == NULL, "or(a, NULL) -> NULL");    /* !b */
    OK(smaug_bool_series_xor(NULL, right_series)  == NULL, "xor(NULL, b) -> NULL");   /* !a */
    OK(smaug_bool_series_xor(left_series, NULL)  == NULL, "xor(a, NULL) -> NULL");   /* !b */
    OK(smaug_bool_series_not(NULL)     == NULL, "not(NULL) -> NULL");

    smaug_bool_free(left_series); smaug_bool_free(right_series); smaug_bool_free(small);
    return 0;
}

/* ---- agregações ---- */
static int test_agg(void) {
    smaug_series_bool_t *left_series = make_boolean_series("111000NNN");
    OK(smaug_bool_series_count_true(left_series) == 3, "count_true ignora NA");
    OK(smaug_bool_count_nonnull(left_series) == 6, "count_nonnull");
    OK(smaug_bool_series_any(left_series) == true, "any com trues");

    smaug_series_bool_t *source_series = make_boolean_series("000");
    OK(smaug_bool_series_all(source_series) == false, "all com false");
    OK(smaug_bool_series_any(source_series) == false, "any sem trues");

    smaug_series_bool_t *source_series_2 = make_boolean_series("111");
    OK(smaug_bool_series_all(source_series_2) == true, "all com trues");

    smaug_series_bool_t *empty = smaug_bool_create(0);
    OK(smaug_bool_series_all(empty) == true, "all de vazio = true");
    OK(smaug_bool_series_any(empty) == false, "any de vazio = false");
    OK(smaug_bool_series_count_true(empty) == 0, "count_true de vazio = 0");

    OK(smaug_bool_series_count_true(NULL) == 0, "count_true(NULL) = 0");
    OK(smaug_bool_series_any(NULL) == false, "any(NULL) = false");
    OK(smaug_bool_series_all(NULL) == true, "all(NULL) = true");
    OK(smaug_bool_count_nonnull(NULL) == 0, "count_nonnull(NULL) = 0");

    smaug_bool_free(left_series); smaug_bool_free(source_series); smaug_bool_free(source_series_2); smaug_bool_free(empty);
    return 0;
}

/* ---- seleção: take, filter ---- */
static int test_selection(void) {
    smaug_series_bool_t *left_series = make_boolean_series("101N0");
    size_t indices[] = {4, 0, 3};
    smaug_series_bool_t *selected_result = smaug_bool_take(left_series, indices, 3);
    OK(selected_result && read_boolean(selected_result, 0) == '0' && read_boolean(selected_result, 1) == '1' && read_boolean(selected_result, 2) == 'N', "take valores e ordem");

    size_t source_values[] = {99};
    OK(smaug_bool_take(left_series, source_values, 1) == NULL, "take OOB -> NULL");
    OK(smaug_bool_take(NULL, indices, 3) == NULL, "take(NULL) -> NULL");
    OK(smaug_bool_take(left_series, NULL, 3) == NULL, "take(idx NULL) -> NULL");

    uint8_t source_values_2[] = {1, 0, 1, 1, 0};
    smaug_series_bool_t *filtered_result = smaug_bool_filter(left_series, source_values_2);
    OK(filtered_result && filtered_result->size == 3, "filter conta corretos");
    OK(read_boolean(filtered_result, 0) == '1' && read_boolean(filtered_result, 1) == '1' && read_boolean(filtered_result, 2) == 'N', "filter preserva valores/NA");
    OK(smaug_bool_filter(NULL, source_values_2) == NULL, "filter(NULL) -> NULL");
    OK(smaug_bool_filter(left_series, NULL) == NULL, "filter(mask NULL) -> NULL");

    smaug_bool_free(left_series); smaug_bool_free(selected_result); smaug_bool_free(filtered_result);
    return 0;
}

/* ---- ordenação: false<true, estável, recusa NULL ---- */
static int test_sort(void) {
    smaug_series_bool_t *left_series = make_boolean_series("10110");
    smaug_series_bool_t *ascending_series = smaug_bool_sort(left_series, true);
    OK(ascending_series && read_boolean(ascending_series, 0) == '0' && read_boolean(ascending_series, 1) == '0', "sort asc: falses primeiro");
    OK(read_boolean(ascending_series, 2) == '1' && read_boolean(ascending_series, 4) == '1', "sort asc: trues depois");

    smaug_series_bool_t *description = smaug_bool_sort(left_series, false);
    OK(description && read_boolean(description, 0) == '1', "sort desc: trues primeiro");
    OK(read_boolean(description, 4) == '0', "sort desc: falses depois");

    /* estabilidade: argsort preserva ordem relativa de iguais */
    size_t *sort_indices = smaug_bool_argsort(left_series, true);  /* a = 1 0 1 1 0 -> falses idx 1,4 ; trues 0,2,3 */
    OK(sort_indices && sort_indices[0] == 1 && sort_indices[1] == 4, "argsort estavel: falses na ordem original");
    OK(sort_indices[2] == 0 && sort_indices[3] == 2 && sort_indices[4] == 3, "argsort estavel: trues na ordem original");
    smaug_free(sort_indices);

    /* recusa NULL */
    smaug_series_bool_t *withna = make_boolean_series("1N0");
    OK(smaug_bool_sort(withna, true) == NULL, "sort recusa NULL");
    OK(smaug_bool_argsort(withna, true) == NULL, "argsort recusa NULL");
    OK(smaug_bool_sort(NULL, true) == NULL, "sort(NULL) -> NULL");
    OK(smaug_bool_argsort(NULL, true) == NULL, "argsort(NULL) -> NULL");

    /* série vazia: argsort/sort válidos, size 0 (cobre o ramo size==0 do malloc) */
    smaug_series_bool_t *empty = smaug_bool_create(0);
    size_t *sort_indices_2 = smaug_bool_argsort(empty, true);
    OK(sort_indices_2 != NULL, "argsort de vazio -> nao-nulo");
    smaug_free(sort_indices_2);
    smaug_series_bool_t *sorted_series = smaug_bool_sort(empty, true);
    OK(sorted_series != NULL && sorted_series->size == 0, "sort de vazio -> vazio");
    smaug_bool_free(sorted_series);
    smaug_bool_free(empty);

    smaug_bool_free(left_series); smaug_bool_free(ascending_series); smaug_bool_free(description); smaug_bool_free(withna);
    return 0;
}

/* 7.4 — comparação de igualdade (único dtype que faltava) */
static int test_equal_not_equal(void) {
    smaug_series_bool_t *right_series = make_boolean_series("10N");   /* true, false, NA */
    smaug_mask_t *result_null_mask = NULL;

    uint8_t *equality_mask = smaug_bool_eq(right_series, 1, &result_null_mask);          /* == true */
    OK(equality_mask != NULL && result_null_mask != NULL, "eq retorna resultado e mascara");
    OK(equality_mask[0] == 1 && SMAUG_VALID(result_null_mask, 0), "eq: true==true -> 1 valido");
    OK(equality_mask[1] == 0 && SMAUG_VALID(result_null_mask, 1), "eq: false==true -> 0 valido");
    OK(SMAUG_NULL(result_null_mask, 2), "eq: NA -> NA na out_mask");
    smaug_free(equality_mask); smaug_free(result_null_mask); result_null_mask = NULL;

    equality_mask = smaug_bool_ne(right_series, 1, &result_null_mask);                   /* != true */
    OK(equality_mask[0] == 0 && equality_mask[1] == 1, "ne: inverso de eq nos validos");
    OK(SMAUG_NULL(result_null_mask, 2), "ne: NA -> NA");
    smaug_free(equality_mask); smaug_free(result_null_mask); result_null_mask = NULL;

    equality_mask = smaug_bool_eq(right_series, 0, &result_null_mask);                   /* == false */
    OK(equality_mask[0] == 0 && equality_mask[1] == 1, "eq false: false==false -> 1");
    OK(SMAUG_NULL(result_null_mask, 2), "eq false: NA -> NA");
    smaug_free(equality_mask); smaug_free(result_null_mask); result_null_mask = NULL;

    /* threshold nao-normalizado (qualquer != 0 = true) */
    equality_mask = smaug_bool_eq(right_series, 42, &result_null_mask);
    OK(equality_mask[0] == 1, "eq: threshold 42 normaliza para true");
    smaug_free(equality_mask); smaug_free(result_null_mask); result_null_mask = NULL;

    OK(smaug_bool_eq(NULL, 1, &result_null_mask) == NULL, "eq(NULL) -> NULL");
    OK(smaug_bool_ne(NULL, 1, &result_null_mask) == NULL, "ne(NULL) -> NULL");

    smaug_bool_free(right_series);
    return 0;
}

/* ---- coalesce_scalar: preenche nulos com value (0/1), mantém não-nulos ---- */
static int test_coalesce(void) {
    /* fill com false: NA -> 0, validos inalterados */
    smaug_series_bool_t *right_series = make_boolean_series("01N1");
    smaug_series_bool_t *coalesce_scalar_series = smaug_bool_coalesce_scalar(right_series, 0);
    OK(coalesce_scalar_series != NULL, "coalesce retorna clone");
    OK(coalesce_scalar_series != right_series, "coalesce nao muta a origem");
    OK(read_boolean(coalesce_scalar_series, 0) == '0' && read_boolean(coalesce_scalar_series, 1) == '1' && read_boolean(coalesce_scalar_series, 3) == '1', "coalesce: validos inalterados");
    OK(read_boolean(coalesce_scalar_series, 2) == '0', "coalesce false: NA -> false");
    OK(smaug_bool_count_nonnull(coalesce_scalar_series) == 4, "coalesce: sem nulos restantes");
    OK(read_boolean(right_series, 2) == 'N', "origem preservada (NA intacto)");
    smaug_bool_free(coalesce_scalar_series);

    /* fill com true */
    coalesce_scalar_series = smaug_bool_coalesce_scalar(right_series, 1);
    OK(read_boolean(coalesce_scalar_series, 2) == '1', "coalesce true: NA -> true");
    OK(read_boolean(coalesce_scalar_series, 0) == '0' && read_boolean(coalesce_scalar_series, 1) == '1', "coalesce true: validos inalterados");
    smaug_bool_free(coalesce_scalar_series);

    /* value nao-normalizado: qualquer != 0 vira 1 */
    coalesce_scalar_series = smaug_bool_coalesce_scalar(right_series, 42);
    OK(read_boolean(coalesce_scalar_series, 2) == '1', "coalesce: value 42 normaliza para true");
    smaug_bool_free(coalesce_scalar_series);
    smaug_bool_free(right_series);

    /* série sem NA: no-op semântico */
    right_series = make_boolean_series("010");
    coalesce_scalar_series = smaug_bool_coalesce_scalar(right_series, 1);
    OK(read_boolean(coalesce_scalar_series, 0) == '0' && read_boolean(coalesce_scalar_series, 1) == '1' && read_boolean(coalesce_scalar_series, 2) == '0', "coalesce sem NA: inalterada");
    smaug_bool_free(coalesce_scalar_series); smaug_bool_free(right_series);

    /* série vazia */
    right_series = smaug_bool_create(0);
    coalesce_scalar_series = smaug_bool_coalesce_scalar(right_series, 1);
    OK(coalesce_scalar_series != NULL && coalesce_scalar_series->size == 0, "coalesce de vazia -> vazia");
    smaug_bool_free(coalesce_scalar_series); smaug_bool_free(right_series);

    /* guarda NULL */
    OK(smaug_bool_coalesce_scalar(NULL, 1) == NULL, "coalesce(NULL) -> NULL");
    return 0;
}

int main(void) {
    if (test_lifecycle())  return 1;
    if (test_guards())     return 1;
    if (test_clone_cow())  return 1;
    if (test_append())     return 1;
    if (test_kleene())     return 1;
    if (test_agg())        return 1;
    if (test_selection())  return 1;
    if (test_sort())       return 1;
    if (test_equal_not_equal())      return 1;
    if (test_coalesce())   return 1;
    printf("PASS: bool lifecycle (%d checks)\n", passed_checks);
    return 0;
}
