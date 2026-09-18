/* tests/test_cow.c
 *
 * Testes de Copy-on-Write (COW) para views de f64 e i64.
 * Garante que a primeira escrita numa view destaca um buffer privado,
 * preservando integralmente o pai.
 *
 * Contrato que cada teste verifica:
 *   1. set/set_null numa view não modifica o pai.
 *   2. A view torna-se independente após o primeiro set (is_view=false,
 *      external_alloc=false, capacity==size).
 *   3. Elementos não modificados da view batem com os do pai (cópia correta).
 *   4. A segunda escrita NÃO realoca (detach já aconteceu).
 *   5. O pai pode ser liberado sem afetar a view destacada.
 *   6. SMG_ERR_NOMEM é retornado quando o detach falha por OOM
 *      (testado via -Wl,--wrap -- ver test_allocfail.c para esse caminho).
 *
 * Compilar e rodar:
 *   gcc -std=c11 -g -O0 -I./include \
 *       tests/test_cow.c src/smaug_core.c src/smaug_ops_f64.c \
 *       src/smaug_ops_i64.c src/smaug_ops_bool.c src/smaug_str.c \
 *       src/smaug_ops_str.c -lm -o build/test_cow
 *   valgrind --leak-check=full --error-exitcode=1 ./build/test_cow
 */

#include "../include/smaug.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Verificação que NÃO some sob -DNDEBUG. Os testes deste arquivo foram
   escritos com assert() como verificação principal; redefinir assert como
   uma checagem ativa (com contador) torna o teste robusto a builds release
   que definam NDEBUG — sem reescrever cada chamada. A própria expressão
   serve de mensagem. */
#include <assert.h>   /* garante que <assert.h> não redefina depois */
#undef assert
static int passed_checks = 0;
#define assert(condition) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU [%s:%d]: %s\n", __FILE__, __LINE__, #condition); \
    exit(1); } passed_checks++; } while (0)

/* ===================================================================
   Utilitário: preenche f64 com [0.0, 1.0, ..., n-1.0] */
static smaug_series_f64_t *make_float64(size_t element_count) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(element_count);
    assert(floating_point_series);
    for (size_t row_index = 0; row_index < element_count; row_index++)
        assert(smaug_f64_set(floating_point_series, row_index, (double)row_index) == SMG_OK);
    return floating_point_series;
}

/* Utilitário: preenche i64 com [0, 1, ..., n-1] */
static smaug_series_i64_t *make_int64(size_t element_count) {
    smaug_series_i64_t *integer_series = smaug_i64_create(element_count);
    assert(integer_series);
    for (size_t row_index = 0; row_index < element_count; row_index++)
        assert(smaug_i64_set(integer_series, row_index, (int64_t)row_index) == SMG_OK);
    return integer_series;
}

/* ===================================================================
   F64 — set: escrita destaca view, pai intacto
   ================================================================= */
static void test_float64_set_detaches_view(void) {
    /* pai: [0.0, 1.0, 2.0, 3.0, 4.0] */
    smaug_series_f64_t *parent_series = make_float64(5);

    /* view sobre [1, 2, 3] (índices 1..3, len=3) */
    smaug_series_f64_t *series_view = smaug_f64_view(parent_series, 1, 3);
    assert(series_view);
    assert(series_view->meta.is_view        == true);
    assert(series_view->meta.external_alloc == true);

    /* escrita na posição 0 da view (= posição 1 do pai) */
    smaug_status_t status = smaug_f64_set(series_view, 0, 99.0);
    assert(status == SMG_OK);

    /* COW: view tornou-se privada */
    assert(series_view->meta.is_view        == false);
    assert(series_view->meta.external_alloc == false);
    assert(series_view->capacity            == 3);     /* janela exata */

    /* valor escrito na view está correto */
    assert(smaug_f64_get(series_view, 0, NULL) == 99.0);

    /* PAI NÃO foi modificado: posição 1 ainda é 1.0 */
    smaug_status_t status_2;
    assert(smaug_f64_get(parent_series, 1, &status_2) == 1.0 && status_2 == SMG_OK);

    /* elementos não tocados da view batem com o pai original */
    assert(smaug_f64_get(series_view, 1, NULL) == 2.0);
    assert(smaug_f64_get(series_view, 2, NULL) == 3.0);

    smaug_f64_free(series_view);
    smaug_f64_free(parent_series);
}

/* ===================================================================
   F64 — set_null: também destaca
   ================================================================= */
static void test_float64_set_null_detaches_view(void) {
    smaug_series_f64_t *parent_series = make_float64(4);
    smaug_series_f64_t *series_view   = smaug_f64_view(parent_series, 0, 2);
    assert(series_view);

    smaug_status_t status = smaug_f64_set_null(series_view, 1);
    assert(status == SMG_OK);
    assert(series_view->meta.is_view == false);

    /* view tem null na posição 1 */
    assert(smaug_f64_is_null(series_view, 1));

    /* pai inalterado: posição 1 ainda é 1.0 e não é null */
    assert(!smaug_f64_is_null(parent_series, 1));
    assert(smaug_f64_get(parent_series, 1, NULL) == 1.0);

    smaug_f64_free(series_view);
    smaug_f64_free(parent_series);
}

/* ===================================================================
   F64 — segunda escrita não realoca (detach já aconteceu)
   ================================================================= */
static void test_float64_second_write_no_realloc(void) {
    smaug_series_f64_t *parent_series = make_float64(6);
    smaug_series_f64_t *series_view   = smaug_f64_view(parent_series, 2, 3);
    assert(series_view);

    /* primeiro set: destaca */
    assert(smaug_f64_set(series_view, 0, 10.0) == SMG_OK);
    assert(series_view->meta.is_view == false);

    double *data_after_first = series_view->data;

    /* segundo set: não deve realocar (data aponta pro mesmo lugar) */
    assert(smaug_f64_set(series_view, 1, 20.0) == SMG_OK);
    assert(series_view->data == data_after_first);     /* mesmo ponteiro */

    assert(smaug_f64_get(series_view, 0, NULL) == 10.0);
    assert(smaug_f64_get(series_view, 1, NULL) == 20.0);

    /* pai inalterado */
    assert(smaug_f64_get(parent_series, 2, NULL) == 2.0);
    assert(smaug_f64_get(parent_series, 3, NULL) == 3.0);

    smaug_f64_free(series_view);
    smaug_f64_free(parent_series);
}

/* ===================================================================
   F64 — view destacada sobrevive à liberação do pai
   ================================================================= */
static void test_float64_view_outlives_parent(void) {
    smaug_series_f64_t *parent_series = make_float64(5);
    smaug_series_f64_t *series_view   = smaug_f64_view(parent_series, 0, 5);
    assert(series_view);

    /* destaca via set */
    assert(smaug_f64_set(series_view, 2, 77.0) == SMG_OK);
    assert(series_view->meta.is_view == false);

    /* libera o pai — view deve continuar válida */
    smaug_f64_free(parent_series);

    /* operações na view após liberação do pai */
    assert(smaug_f64_get(series_view, 0, NULL) == 0.0);
    assert(smaug_f64_get(series_view, 2, NULL) == 77.0);
    assert(smaug_f64_get(series_view, 4, NULL) == 4.0);

    smaug_f64_free(series_view);
}

/* ===================================================================
   F64 — view de view (encadeada): escrita destaca só a view imediata
   ================================================================= */
static void test_float64_nested_view(void) {
    smaug_series_f64_t *parent_series = make_float64(10);   /* [0..9] */
    smaug_series_f64_t *series_view  = smaug_f64_view(parent_series, 2, 6);  /* [2..7] */
    smaug_series_f64_t *series_view_2  = smaug_f64_view(series_view,  1, 3);  /* [3..5] do pai */
    assert(series_view && series_view_2);

    /* escrita em v2 destaca v2; v1 e pai ficam intactos */
    assert(smaug_f64_set(series_view_2, 0, 55.0) == SMG_OK);
    assert(series_view_2->meta.is_view == false);
    assert(series_view->meta.is_view == true);   /* v1 ainda é view */

    assert(smaug_f64_get(series_view_2, 0, NULL) == 55.0);
    assert(smaug_f64_get(series_view, 1, NULL) == 3.0);   /* v1 inalterada */
    assert(smaug_f64_get(parent_series, 3, NULL) == 3.0);  /* pai inalterado */

    smaug_f64_free(series_view_2);
    smaug_f64_free(series_view);
    smaug_f64_free(parent_series);
}

/* ===================================================================
   I64 — set: escrita destaca view, pai intacto
   ================================================================= */
static void test_int64_set_detaches_view(void) {
    smaug_series_i64_t *parent_series = make_int64(5);
    smaug_series_i64_t *series_view   = smaug_i64_view(parent_series, 1, 3);
    assert(series_view);
    assert(series_view->meta.is_view == true);

    smaug_status_t status = smaug_i64_set(series_view, 0, 99);
    assert(status == SMG_OK);

    assert(series_view->meta.is_view        == false);
    assert(series_view->meta.external_alloc == false);
    assert(series_view->capacity            == 3);

    assert(smaug_i64_get(series_view, 0, NULL) == 99);

    /* pai inalterado */
    smaug_status_t status_2;
    assert(smaug_i64_get(parent_series, 1, &status_2) == 1 && status_2 == SMG_OK);

    /* elementos não tocados */
    assert(smaug_i64_get(series_view, 1, NULL) == 2);
    assert(smaug_i64_get(series_view, 2, NULL) == 3);

    smaug_i64_free(series_view);
    smaug_i64_free(parent_series);
}

/* ===================================================================
   I64 — set_null: também destaca
   ================================================================= */
static void test_int64_set_null_detaches_view(void) {
    smaug_series_i64_t *parent_series = make_int64(4);
    smaug_series_i64_t *series_view   = smaug_i64_view(parent_series, 0, 4);
    assert(series_view);

    assert(smaug_i64_set_null(series_view, 2) == SMG_OK);
    assert(series_view->meta.is_view == false);
    assert(smaug_i64_is_null(series_view, 2));

    assert(!smaug_i64_is_null(parent_series, 2));
    assert(smaug_i64_get(parent_series, 2, NULL) == 2);

    smaug_i64_free(series_view);
    smaug_i64_free(parent_series);
}

/* ===================================================================
   I64 — view destacada sobrevive à liberação do pai
   ================================================================= */
static void test_int64_view_outlives_parent(void) {
    smaug_series_i64_t *parent_series = make_int64(4);
    smaug_series_i64_t *series_view   = smaug_i64_view(parent_series, 0, 4);
    assert(series_view);

    assert(smaug_i64_set(series_view, 0, -1) == SMG_OK);
    assert(series_view->meta.is_view == false);

    smaug_i64_free(parent_series);

    assert(smaug_i64_get(series_view, 0, NULL) == -1);
    assert(smaug_i64_get(series_view, 1, NULL) == 1);
    assert(smaug_i64_get(series_view, 3, NULL) == 3);

    smaug_i64_free(series_view);
}

/* ===================================================================
   Status: OOB numa view NÃO destaca (falha segura)
   ================================================================= */
static void test_cow_oob_does_not_detach(void) {
    smaug_series_f64_t *parent_series = make_float64(5);
    smaug_series_f64_t *series_view   = smaug_f64_view(parent_series, 1, 3);  /* len=3 */
    assert(series_view);

    /* índice 3 está fora da view (size=3, índice válido: 0..2) */
    smaug_status_t status = smaug_f64_set(series_view, 3, 99.0);
    assert(status == SMG_ERR_OOB);

    /* view continua sendo view (OOB não destaca) */
    assert(series_view->meta.is_view == true);

    /* pai inalterado */
    assert(smaug_f64_get(parent_series, 4, NULL) == 4.0);

    smaug_f64_free(series_view);
    smaug_f64_free(parent_series);
}

/* ===================================================================
   F64 — append: COW destaca, grow acontece, pai intacta
   ================================================================= */
static void test_float64_append_detaches_view(void) {
    smaug_series_f64_t *parent_series = make_float64(4);   /* [0, 1, 2, 3] */
    smaug_series_f64_t *series_view   = smaug_f64_view(parent_series, 1, 3);  /* [1, 2, 3] */
    assert(series_view);

    assert(smaug_f64_append(series_view, 99.0) == 0);
    assert(series_view->meta.is_view        == false);
    assert(series_view->meta.external_alloc == false);
    assert(series_view->size     == 4);
    assert(series_view->capacity >= 4);
    assert(smaug_f64_get(series_view, 3, NULL) == 99.0);

    /* elementos copiados do pai antes do grow */
    assert(smaug_f64_get(series_view, 0, NULL) == 1.0);
    assert(smaug_f64_get(series_view, 1, NULL) == 2.0);
    assert(smaug_f64_get(series_view, 2, NULL) == 3.0);

    /* pai inalterada */
    assert(smaug_f64_get(parent_series, 1, NULL) == 1.0);
    assert(smaug_f64_get(parent_series, 3, NULL) == 3.0);

    smaug_f64_free(series_view);
    smaug_f64_free(parent_series);
}

/* ===================================================================
   F64 — append_null: também destaca
   ================================================================= */
static void test_float64_append_null_detaches_view(void) {
    smaug_series_f64_t *parent_series = make_float64(3);
    smaug_series_f64_t *series_view   = smaug_f64_view(parent_series, 0, 3);
    assert(series_view);

    assert(smaug_f64_append_null(series_view) == 0);
    assert(series_view->meta.is_view == false);
    assert(series_view->size == 4);
    assert(smaug_f64_is_null(series_view, 3));       /* elemento appended é null */
    assert(!smaug_f64_is_null(parent_series, 0));    /* pai inalterada */

    smaug_f64_free(series_view);
    smaug_f64_free(parent_series);
}

/* ===================================================================
   F64 — view de tamanho zero: append destaca (sem malloc) e adiciona
   ================================================================= */
static void test_float64_append_zero_size_view(void) {
    smaug_series_f64_t *parent_series = make_float64(3);
    smaug_series_f64_t *series_view   = smaug_f64_view(parent_series, 1, 0);  /* view vazia */
    assert(series_view);
    assert(series_view->size == 0);

    assert(smaug_f64_append(series_view, 42.0) == 0);
    assert(series_view->meta.is_view == false);
    assert(series_view->size == 1);
    assert(smaug_f64_get(series_view, 0, NULL) == 42.0);

    /* pai intacta */
    assert(smaug_f64_get(parent_series, 0, NULL) == 0.0);

    smaug_f64_free(series_view);
    smaug_f64_free(parent_series);
}

/* ===================================================================
   F64 — após append-detach, mais appends crescem normalmente
   ================================================================= */
static void test_float64_append_then_grow(void) {
    smaug_series_f64_t *parent_series = make_float64(2);
    smaug_series_f64_t *series_view   = smaug_f64_view(parent_series, 0, 2);
    assert(series_view);

    /* primeiro append: detach + grow */
    assert(smaug_f64_append(series_view, 10.0) == 0);
    assert(series_view->meta.is_view == false);
    double *pointer_after_first = series_view->data;

    /* segundo append: sem detach (já private), grow se necessário */
    assert(smaug_f64_append(series_view, 20.0) == 0);
    assert(series_view->size == 4);
    assert(smaug_f64_get(series_view, 2, NULL) == 10.0);
    assert(smaug_f64_get(series_view, 3, NULL) == 20.0);
    (void)pointer_after_first;  /* ponteiro pode mudar após grow — apenas confirma não crash */

    smaug_f64_free(series_view);
    smaug_f64_free(parent_series);
}

/* ===================================================================
   I64 — append: COW destaca, pai intacta
   ================================================================= */
static void test_int64_append_detaches_view(void) {
    smaug_series_i64_t *parent_series = make_int64(4);
    smaug_series_i64_t *series_view   = smaug_i64_view(parent_series, 0, 4);
    assert(series_view);

    assert(smaug_i64_append(series_view, 99) == 0);
    assert(series_view->meta.is_view == false);
    assert(series_view->size == 5);
    assert(smaug_i64_get(series_view, 4, NULL) == 99);

    /* pai inalterada */
    assert(smaug_i64_get(parent_series, 0, NULL) == 0);
    assert(smaug_i64_get(parent_series, 3, NULL) == 3);
    assert(parent_series->size == 4);

    smaug_i64_free(series_view);
    smaug_i64_free(parent_series);
}

/* ===================================================================
   I64 — append_null: também destaca
   ================================================================= */
static void test_int64_append_null_detaches_view(void) {
    smaug_series_i64_t *parent_series = make_int64(3);
    smaug_series_i64_t *series_view   = smaug_i64_view(parent_series, 1, 2);
    assert(series_view);

    assert(smaug_i64_append_null(series_view) == 0);
    assert(series_view->meta.is_view == false);
    assert(series_view->size == 3);
    assert(smaug_i64_is_null(series_view, 2));
    assert(!smaug_i64_is_null(parent_series, 1));

    smaug_i64_free(series_view);
    smaug_i64_free(parent_series);
}

/* ===================================================================
   main
   ================================================================= */
/* ===================================================================
   STRING — view + COW (offset-based, modelo A1: buffer/null_mask
   compartilhados, offsets próprio absoluto)
   ================================================================= */

/* Utilitário: cria string ["SP","RJ","MG","BA","CE"] */
static smaug_series_str_t *make_str5(void) {
    const char *const source_values[] = {"SP", "RJ", "MG", "BA", "CE"};
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 5);
    assert(source_series);
    return source_series;
}

static const char *string_value_at(const smaug_series_str_t *source_series, size_t row_index, size_t *length) {
    return smaug_str_get(source_series, row_index, length);
}
static int string_equals(const smaug_series_str_t *source_series, size_t row_index, const char *expected_values) {
    size_t length; const char *text_value = string_value_at(source_series, row_index, &length);
    if (!text_value) return expected_values == NULL;
    if (expected_values == NULL) return 0;
    return length == strlen(expected_values) && memcmp(text_value, expected_values, length) == 0;
}

/* view lê o pai antes de qualquer escrita */
static void test_string_view_reads_parent(void) {
    smaug_series_str_t *parent_series = make_str5();
    smaug_series_str_t *source_series = smaug_str_view(parent_series, 1, 3);   /* [RJ,MG,BA] */
    assert(source_series);
    assert(source_series->meta.is_view == true);
    assert(source_series->meta.external_alloc == true);
    assert(source_series->offsets_owned == true);
    assert(source_series->size == 3);
    assert(string_equals(source_series, 0, "RJ"));
    assert(string_equals(source_series, 1, "MG"));
    assert(string_equals(source_series, 2, "BA"));
    smaug_str_free(source_series);
    smaug_str_free(parent_series);
}

/* set numa view destaca; pai intacto. Caso mais sensível: nova string de
   tamanho DIFERENTE, forçando remontagem do buffer privado. */
static void test_string_set_detaches_view(void) {
    smaug_series_str_t *parent_series = make_str5();
    smaug_series_str_t *source_series = smaug_str_view(parent_series, 1, 3);   /* [RJ,MG,BA] */

    /* troca "MG" (pos 1 da view = pos 2 do pai) por "MINAS" (maior) */
    assert(smaug_str_set(source_series, 1, "MINAS", 5) == SMG_OK);
    assert(source_series->meta.is_view == false);           /* destacou */
    assert(source_series->meta.external_alloc == false);
    assert(source_series->offsets_owned == true);

    /* view reflete a mudança */
    assert(string_equals(source_series, 0, "RJ"));
    assert(string_equals(source_series, 1, "MINAS"));
    assert(string_equals(source_series, 2, "BA"));

    /* pai INTACTO — não viu a mudança */
    assert(string_equals(parent_series, 0, "SP"));
    assert(string_equals(parent_series, 1, "RJ"));
    assert(string_equals(parent_series, 2, "MG"));    /* continua MG, não MINAS */
    assert(string_equals(parent_series, 3, "BA"));
    assert(string_equals(parent_series, 4, "CE"));

    smaug_str_free(source_series);
    smaug_str_free(parent_series);
}

/* set_null numa view destaca (via set interno) e não toca o pai */
static void test_string_set_null_detaches_view(void) {
    smaug_series_str_t *parent_series = make_str5();
    smaug_series_str_t *source_series = smaug_str_view(parent_series, 0, 3);   /* [SP,RJ,MG] */

    assert(smaug_str_set_null(source_series, 0) == SMG_OK);
    assert(source_series->meta.is_view == false);
    assert(smaug_str_is_null(source_series, 0) == true);
    assert(string_equals(source_series, 1, "RJ"));

    /* pai intacto */
    assert(smaug_str_is_null(parent_series, 0) == false);
    assert(string_equals(parent_series, 0, "SP"));
    smaug_str_free(source_series);
    smaug_str_free(parent_series);
}

/* append numa view destaca e cresce a cópia privada; pai intacto no tamanho */
static void test_string_append_detaches_view(void) {
    smaug_series_str_t *parent_series = make_str5();
    size_t pai_size_antes = parent_series->size;
    smaug_series_str_t *source_series = smaug_str_view(parent_series, 1, 2);   /* [RJ,MG] */

    assert(smaug_str_append(source_series, "NOVO", 4) == 0);
    assert(source_series->meta.is_view == false);
    assert(source_series->size == 3);
    assert(string_equals(source_series, 0, "RJ"));
    assert(string_equals(source_series, 1, "MG"));
    assert(string_equals(source_series, 2, "NOVO"));

    /* pai não cresceu */
    assert(parent_series->size == pai_size_antes);
    smaug_str_free(source_series);
    smaug_str_free(parent_series);
}

/* append_null numa view destaca */
static void test_string_append_null_detaches_view(void) {
    smaug_series_str_t *parent_series = make_str5();
    smaug_series_str_t *source_series = smaug_str_view(parent_series, 2, 2);   /* [MG,BA] */

    assert(smaug_str_append_null(source_series) == 0);
    assert(source_series->meta.is_view == false);
    assert(source_series->size == 3);
    assert(string_equals(source_series, 0, "MG"));
    assert(string_equals(source_series, 1, "BA"));
    assert(smaug_str_is_null(source_series, 2) == true);
    smaug_str_free(source_series);
    smaug_str_free(parent_series);
}

/* view de view: detach da neta não afeta a filha nem o avô */
static void test_string_nested_view(void) {
    smaug_series_str_t *grandparent_series = make_str5();           /* [SP,RJ,MG,BA,CE] */
    smaug_series_str_t *filha = smaug_str_view(grandparent_series, 1, 3);   /* [RJ,MG,BA] */
    smaug_series_str_t *grandchild_series  = smaug_str_view(filha, 1, 2); /* [MG,BA] */

    assert(string_equals(grandchild_series, 0, "MG"));
    assert(string_equals(grandchild_series, 1, "BA"));

    assert(smaug_str_set(grandchild_series, 0, "X", 1) == SMG_OK);   /* detach só da neta */
    assert(string_equals(grandchild_series, 0, "X"));
    assert(string_equals(filha, 1, "MG"));    /* filha intacta */
    assert(string_equals(grandparent_series, 2, "MG"));      /* avô intacto */

    smaug_str_free(grandchild_series);
    smaug_str_free(filha);
    smaug_str_free(grandparent_series);
}

/* view destacada sobrevive ao pai liberado */
static void test_string_view_outlives_parent(void) {
    smaug_series_str_t *parent_series = make_str5();
    smaug_series_str_t *source_series = smaug_str_view(parent_series, 1, 3);   /* [RJ,MG,BA] */
    assert(smaug_str_set(source_series, 0, "ZZ", 2) == SMG_OK);      /* destaca */
    smaug_str_free(parent_series);                                 /* pai vai embora */
    /* view ainda íntegra (buffer/offsets/null_mask são privados agora) */
    assert(string_equals(source_series, 0, "ZZ"));
    assert(string_equals(source_series, 1, "MG"));
    assert(string_equals(source_series, 2, "BA"));
    smaug_str_free(source_series);
}

/* view vazia (len=0): detach materializa struct coerente sem UB */
static void test_string_empty_view(void) {
    smaug_series_str_t *parent_series = make_str5();
    smaug_series_str_t *source_series = smaug_str_view(parent_series, 2, 0);   /* janela vazia */
    assert(source_series);
    assert(source_series->size == 0);
    /* append destaca a view vazia e adiciona */
    assert(smaug_str_append(source_series, "UNICO", 5) == 0);
    assert(source_series->meta.is_view == false);
    assert(source_series->size == 1);
    assert(string_equals(source_series, 0, "UNICO"));
    smaug_str_free(source_series);
    smaug_str_free(parent_series);
}

/* segunda escrita não re-detacha (já é privada) */
static void test_string_second_write_no_redetach(void) {
    smaug_series_str_t *parent_series = make_str5();
    smaug_series_str_t *source_series = smaug_str_view(parent_series, 0, 3);
    assert(smaug_str_set(source_series, 0, "AA", 2) == SMG_OK);
    assert(source_series->meta.is_view == false);
    assert(smaug_str_set(source_series, 1, "BB", 2) == SMG_OK);   /* já privada */
    assert(string_equals(source_series, 0, "AA"));
    assert(string_equals(source_series, 1, "BB"));
    assert(string_equals(source_series, 2, "MG"));
    smaug_str_free(source_series);
    smaug_str_free(parent_series);
}

/* guard da view: entradas inválidas retornam NULL; pai intacto.
   Cobre as 3 sub-condições (linha a linha do guard) + a borda VÁLIDA
   start==size com len==0 (janela vazia no fim — offsets[size] existe). */
static void test_string_view_invalid_inputs(void) {
    smaug_series_str_t *parent_series = make_str5();
    assert(smaug_str_view(NULL, 0, 0) == NULL);   /* !s                    */
    assert(smaug_str_view(parent_series, 6, 0) == NULL);    /* start > size          */
    assert(smaug_str_view(parent_series, 2, 4) == NULL);    /* len > size - start    */
    assert(smaug_str_view(parent_series, 5, 1) == NULL);    /* borda: start==size, len>0 */
    smaug_series_str_t *source_series = smaug_str_view(parent_series, 5, 0);  /* borda válida */
    assert(source_series && source_series->size == 0);
    smaug_str_free(source_series);
    /* pai intacto após as recusas */
    assert(parent_series->size == 5 && string_equals(parent_series, 0, "SP") && string_equals(parent_series, 4, "CE"));
    smaug_str_free(parent_series);
}

/* detach com byte_count==0 e size>0: janela onde TODAS as strings são "".
   bufcap cai no fallback SMAUG_STR_BUFFER_INIT e o memcpy do buffer é
   pulado. A série destacada deve ser coerente, mutável, e preservar
   "" ≠ NULL. Pai intacto. */
static void test_string_detach_all_empty_window(void) {
    const char *const source_values[] = {"", "", "", "X"};
    smaug_series_str_t *parent_series = smaug_str_create_from_array(source_values, 4);
    assert(parent_series);
    smaug_series_str_t *source_series = smaug_str_view(parent_series, 0, 3);  /* ["","",""], 0 bytes */
    assert(source_series && source_series->size == 3);
    assert(string_equals(source_series, 0, "") && string_equals(source_series, 1, "") && string_equals(source_series, 2, ""));  /* "" ≠ NULL na view */

    assert(smaug_str_set(source_series, 1, "NOVO", 4) == SMG_OK);   /* dispara o detach */
    assert(source_series->meta.is_view == false);
    assert(source_series->meta.external_alloc == false);
    assert(source_series->offsets_owned == true);
    assert(string_equals(source_series, 0, "") && string_equals(source_series, 1, "NOVO") && string_equals(source_series, 2, ""));

    /* pai integralmente intacto */
    assert(string_equals(parent_series, 0, "") && string_equals(parent_series, 1, "") && string_equals(parent_series, 2, "") && string_equals(parent_series, 3, "X"));
    smaug_str_free(source_series);
    smaug_str_free(parent_series);
}

int main(void) {
    test_float64_set_detaches_view();
    test_float64_set_null_detaches_view();
    test_float64_second_write_no_realloc();
    test_float64_view_outlives_parent();
    test_float64_nested_view();
    test_int64_set_detaches_view();
    test_int64_set_null_detaches_view();
    test_int64_view_outlives_parent();
    test_cow_oob_does_not_detach();
    test_float64_append_detaches_view();
    test_float64_append_null_detaches_view();
    test_float64_append_zero_size_view();
    test_float64_append_then_grow();
    test_int64_append_detaches_view();
    test_int64_append_null_detaches_view();

    test_string_view_reads_parent();
    test_string_set_detaches_view();
    test_string_set_null_detaches_view();
    test_string_append_detaches_view();
    test_string_append_null_detaches_view();
    test_string_nested_view();
    test_string_view_outlives_parent();
    test_string_empty_view();
    test_string_second_write_no_redetach();
    test_string_view_invalid_inputs();
    test_string_detach_all_empty_window();

    printf("PASS: COW (%d checks)\n", passed_checks);
    return 0;
}
