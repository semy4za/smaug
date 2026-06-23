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

/* Verificação que NÃO some sob -DNDEBUG. Os testes deste arquivo foram
   escritos com assert() como verificação principal; redefinir assert como
   uma checagem ativa (com contador) torna o teste robusto a builds release
   que definam NDEBUG — sem reescrever cada chamada. A própria expressão
   serve de mensagem. */
#include <assert.h>   /* garante que <assert.h> não redefina depois */
#undef assert
static int n_checks = 0;
#define assert(cond) do { if (!(cond)) { \
    fprintf(stderr, "FALHOU [%s:%d]: %s\n", __FILE__, __LINE__, #cond); \
    exit(1); } n_checks++; } while (0)

/* ===================================================================
   Utilitário: preenche f64 com [0.0, 1.0, ..., n-1.0] */
static smaug_series_f64_t *make_f64(size_t n) {
    smaug_series_f64_t *s = smaug_f64_create(n);
    assert(s);
    for (size_t i = 0; i < n; i++)
        assert(smaug_f64_set(s, i, (double)i) == SMG_OK);
    return s;
}

/* Utilitário: preenche i64 com [0, 1, ..., n-1] */
static smaug_series_i64_t *make_i64(size_t n) {
    smaug_series_i64_t *s = smaug_i64_create(n);
    assert(s);
    for (size_t i = 0; i < n; i++)
        assert(smaug_i64_set(s, i, (int64_t)i) == SMG_OK);
    return s;
}

/* ===================================================================
   F64 — set: escrita destaca view, pai intacto
   ================================================================= */
static void test_f64_set_detaches_view(void) {
    /* pai: [0.0, 1.0, 2.0, 3.0, 4.0] */
    smaug_series_f64_t *pai = make_f64(5);

    /* view sobre [1, 2, 3] (índices 1..3, len=3) */
    smaug_series_f64_t *v = smaug_f64_view(pai, 1, 3);
    assert(v);
    assert(v->meta.is_view        == true);
    assert(v->meta.external_alloc == true);

    /* escrita na posição 0 da view (= posição 1 do pai) */
    smaug_status_t rc = smaug_f64_set(v, 0, 99.0);
    assert(rc == SMG_OK);

    /* COW: view tornou-se privada */
    assert(v->meta.is_view        == false);
    assert(v->meta.external_alloc == false);
    assert(v->capacity            == 3);     /* janela exata */

    /* valor escrito na view está correto */
    assert(smaug_f64_get(v, 0, NULL) == 99.0);

    /* PAI NÃO foi modificado: posição 1 ainda é 1.0 */
    smaug_status_t st;
    assert(smaug_f64_get(pai, 1, &st) == 1.0 && st == SMG_OK);

    /* elementos não tocados da view batem com o pai original */
    assert(smaug_f64_get(v, 1, NULL) == 2.0);
    assert(smaug_f64_get(v, 2, NULL) == 3.0);

    smaug_f64_free(v);
    smaug_f64_free(pai);
}

/* ===================================================================
   F64 — set_null: também destaca
   ================================================================= */
static void test_f64_set_null_detaches_view(void) {
    smaug_series_f64_t *pai = make_f64(4);
    smaug_series_f64_t *v   = smaug_f64_view(pai, 0, 2);
    assert(v);

    smaug_status_t rc = smaug_f64_set_null(v, 1);
    assert(rc == SMG_OK);
    assert(v->meta.is_view == false);

    /* view tem null na posição 1 */
    assert(smaug_f64_is_null(v, 1));

    /* pai inalterado: posição 1 ainda é 1.0 e não é null */
    assert(!smaug_f64_is_null(pai, 1));
    assert(smaug_f64_get(pai, 1, NULL) == 1.0);

    smaug_f64_free(v);
    smaug_f64_free(pai);
}

/* ===================================================================
   F64 — segunda escrita não realoca (detach já aconteceu)
   ================================================================= */
static void test_f64_second_write_no_realloc(void) {
    smaug_series_f64_t *pai = make_f64(6);
    smaug_series_f64_t *v   = smaug_f64_view(pai, 2, 3);
    assert(v);

    /* primeiro set: destaca */
    assert(smaug_f64_set(v, 0, 10.0) == SMG_OK);
    assert(v->meta.is_view == false);

    double *data_after_first = v->data;

    /* segundo set: não deve realocar (data aponta pro mesmo lugar) */
    assert(smaug_f64_set(v, 1, 20.0) == SMG_OK);
    assert(v->data == data_after_first);     /* mesmo ponteiro */

    assert(smaug_f64_get(v, 0, NULL) == 10.0);
    assert(smaug_f64_get(v, 1, NULL) == 20.0);

    /* pai inalterado */
    assert(smaug_f64_get(pai, 2, NULL) == 2.0);
    assert(smaug_f64_get(pai, 3, NULL) == 3.0);

    smaug_f64_free(v);
    smaug_f64_free(pai);
}

/* ===================================================================
   F64 — view destacada sobrevive à liberação do pai
   ================================================================= */
static void test_f64_view_outlives_parent(void) {
    smaug_series_f64_t *pai = make_f64(5);
    smaug_series_f64_t *v   = smaug_f64_view(pai, 0, 5);
    assert(v);

    /* destaca via set */
    assert(smaug_f64_set(v, 2, 77.0) == SMG_OK);
    assert(v->meta.is_view == false);

    /* libera o pai — view deve continuar válida */
    smaug_f64_free(pai);

    /* operações na view após liberação do pai */
    assert(smaug_f64_get(v, 0, NULL) == 0.0);
    assert(smaug_f64_get(v, 2, NULL) == 77.0);
    assert(smaug_f64_get(v, 4, NULL) == 4.0);

    smaug_f64_free(v);
}

/* ===================================================================
   F64 — view de view (encadeada): escrita destaca só a view imediata
   ================================================================= */
static void test_f64_nested_view(void) {
    smaug_series_f64_t *pai = make_f64(10);   /* [0..9] */
    smaug_series_f64_t *v1  = smaug_f64_view(pai, 2, 6);  /* [2..7] */
    smaug_series_f64_t *v2  = smaug_f64_view(v1,  1, 3);  /* [3..5] do pai */
    assert(v1 && v2);

    /* escrita em v2 destaca v2; v1 e pai ficam intactos */
    assert(smaug_f64_set(v2, 0, 55.0) == SMG_OK);
    assert(v2->meta.is_view == false);
    assert(v1->meta.is_view == true);   /* v1 ainda é view */

    assert(smaug_f64_get(v2, 0, NULL) == 55.0);
    assert(smaug_f64_get(v1, 1, NULL) == 3.0);   /* v1 inalterada */
    assert(smaug_f64_get(pai, 3, NULL) == 3.0);  /* pai inalterado */

    smaug_f64_free(v2);
    smaug_f64_free(v1);
    smaug_f64_free(pai);
}

/* ===================================================================
   I64 — set: escrita destaca view, pai intacto
   ================================================================= */
static void test_i64_set_detaches_view(void) {
    smaug_series_i64_t *pai = make_i64(5);
    smaug_series_i64_t *v   = smaug_i64_view(pai, 1, 3);
    assert(v);
    assert(v->meta.is_view == true);

    smaug_status_t rc = smaug_i64_set(v, 0, 99);
    assert(rc == SMG_OK);

    assert(v->meta.is_view        == false);
    assert(v->meta.external_alloc == false);
    assert(v->capacity            == 3);

    assert(smaug_i64_get(v, 0, NULL) == 99);

    /* pai inalterado */
    smaug_status_t st;
    assert(smaug_i64_get(pai, 1, &st) == 1 && st == SMG_OK);

    /* elementos não tocados */
    assert(smaug_i64_get(v, 1, NULL) == 2);
    assert(smaug_i64_get(v, 2, NULL) == 3);

    smaug_i64_free(v);
    smaug_i64_free(pai);
}

/* ===================================================================
   I64 — set_null: também destaca
   ================================================================= */
static void test_i64_set_null_detaches_view(void) {
    smaug_series_i64_t *pai = make_i64(4);
    smaug_series_i64_t *v   = smaug_i64_view(pai, 0, 4);
    assert(v);

    assert(smaug_i64_set_null(v, 2) == SMG_OK);
    assert(v->meta.is_view == false);
    assert(smaug_i64_is_null(v, 2));

    assert(!smaug_i64_is_null(pai, 2));
    assert(smaug_i64_get(pai, 2, NULL) == 2);

    smaug_i64_free(v);
    smaug_i64_free(pai);
}

/* ===================================================================
   I64 — view destacada sobrevive à liberação do pai
   ================================================================= */
static void test_i64_view_outlives_parent(void) {
    smaug_series_i64_t *pai = make_i64(4);
    smaug_series_i64_t *v   = smaug_i64_view(pai, 0, 4);
    assert(v);

    assert(smaug_i64_set(v, 0, -1) == SMG_OK);
    assert(v->meta.is_view == false);

    smaug_i64_free(pai);

    assert(smaug_i64_get(v, 0, NULL) == -1);
    assert(smaug_i64_get(v, 1, NULL) == 1);
    assert(smaug_i64_get(v, 3, NULL) == 3);

    smaug_i64_free(v);
}

/* ===================================================================
   Status: OOB numa view NÃO destaca (falha segura)
   ================================================================= */
static void test_cow_oob_does_not_detach(void) {
    smaug_series_f64_t *pai = make_f64(5);
    smaug_series_f64_t *v   = smaug_f64_view(pai, 1, 3);  /* len=3 */
    assert(v);

    /* índice 3 está fora da view (size=3, índice válido: 0..2) */
    smaug_status_t rc = smaug_f64_set(v, 3, 99.0);
    assert(rc == SMG_ERR_OOB);

    /* view continua sendo view (OOB não destaca) */
    assert(v->meta.is_view == true);

    /* pai inalterado */
    assert(smaug_f64_get(pai, 4, NULL) == 4.0);

    smaug_f64_free(v);
    smaug_f64_free(pai);
}

/* ===================================================================
   F64 — append: COW destaca, grow acontece, pai intacta
   ================================================================= */
static void test_f64_append_detaches_view(void) {
    smaug_series_f64_t *pai = make_f64(4);   /* [0, 1, 2, 3] */
    smaug_series_f64_t *v   = smaug_f64_view(pai, 1, 3);  /* [1, 2, 3] */
    assert(v);

    assert(smaug_f64_append(v, 99.0) == 0);
    assert(v->meta.is_view        == false);
    assert(v->meta.external_alloc == false);
    assert(v->size     == 4);
    assert(v->capacity >= 4);
    assert(smaug_f64_get(v, 3, NULL) == 99.0);

    /* elementos copiados do pai antes do grow */
    assert(smaug_f64_get(v, 0, NULL) == 1.0);
    assert(smaug_f64_get(v, 1, NULL) == 2.0);
    assert(smaug_f64_get(v, 2, NULL) == 3.0);

    /* pai inalterada */
    assert(smaug_f64_get(pai, 1, NULL) == 1.0);
    assert(smaug_f64_get(pai, 3, NULL) == 3.0);

    smaug_f64_free(v);
    smaug_f64_free(pai);
}

/* ===================================================================
   F64 — append_null: também destaca
   ================================================================= */
static void test_f64_append_null_detaches_view(void) {
    smaug_series_f64_t *pai = make_f64(3);
    smaug_series_f64_t *v   = smaug_f64_view(pai, 0, 3);
    assert(v);

    assert(smaug_f64_append_null(v) == 0);
    assert(v->meta.is_view == false);
    assert(v->size == 4);
    assert(smaug_f64_is_null(v, 3));       /* elemento appended é null */
    assert(!smaug_f64_is_null(pai, 0));    /* pai inalterada */

    smaug_f64_free(v);
    smaug_f64_free(pai);
}

/* ===================================================================
   F64 — view de tamanho zero: append destaca (sem malloc) e adiciona
   ================================================================= */
static void test_f64_append_zero_size_view(void) {
    smaug_series_f64_t *pai = make_f64(3);
    smaug_series_f64_t *v   = smaug_f64_view(pai, 1, 0);  /* view vazia */
    assert(v);
    assert(v->size == 0);

    assert(smaug_f64_append(v, 42.0) == 0);
    assert(v->meta.is_view == false);
    assert(v->size == 1);
    assert(smaug_f64_get(v, 0, NULL) == 42.0);

    /* pai intacta */
    assert(smaug_f64_get(pai, 0, NULL) == 0.0);

    smaug_f64_free(v);
    smaug_f64_free(pai);
}

/* ===================================================================
   F64 — após append-detach, mais appends crescem normalmente
   ================================================================= */
static void test_f64_append_then_grow(void) {
    smaug_series_f64_t *pai = make_f64(2);
    smaug_series_f64_t *v   = smaug_f64_view(pai, 0, 2);
    assert(v);

    /* primeiro append: detach + grow */
    assert(smaug_f64_append(v, 10.0) == 0);
    assert(v->meta.is_view == false);
    double *ptr_after_first = v->data;

    /* segundo append: sem detach (já private), grow se necessário */
    assert(smaug_f64_append(v, 20.0) == 0);
    assert(v->size == 4);
    assert(smaug_f64_get(v, 2, NULL) == 10.0);
    assert(smaug_f64_get(v, 3, NULL) == 20.0);
    (void)ptr_after_first;  /* ponteiro pode mudar após grow — apenas confirma não crash */

    smaug_f64_free(v);
    smaug_f64_free(pai);
}

/* ===================================================================
   I64 — append: COW destaca, pai intacta
   ================================================================= */
static void test_i64_append_detaches_view(void) {
    smaug_series_i64_t *pai = make_i64(4);
    smaug_series_i64_t *v   = smaug_i64_view(pai, 0, 4);
    assert(v);

    assert(smaug_i64_append(v, 99) == 0);
    assert(v->meta.is_view == false);
    assert(v->size == 5);
    assert(smaug_i64_get(v, 4, NULL) == 99);

    /* pai inalterada */
    assert(smaug_i64_get(pai, 0, NULL) == 0);
    assert(smaug_i64_get(pai, 3, NULL) == 3);
    assert(pai->size == 4);

    smaug_i64_free(v);
    smaug_i64_free(pai);
}

/* ===================================================================
   I64 — append_null: também destaca
   ================================================================= */
static void test_i64_append_null_detaches_view(void) {
    smaug_series_i64_t *pai = make_i64(3);
    smaug_series_i64_t *v   = smaug_i64_view(pai, 1, 2);
    assert(v);

    assert(smaug_i64_append_null(v) == 0);
    assert(v->meta.is_view == false);
    assert(v->size == 3);
    assert(smaug_i64_is_null(v, 2));
    assert(!smaug_i64_is_null(pai, 1));

    smaug_i64_free(v);
    smaug_i64_free(pai);
}

/* ===================================================================
   main
   ================================================================= */
int main(void) {
    test_f64_set_detaches_view();
    test_f64_set_null_detaches_view();
    test_f64_second_write_no_realloc();
    test_f64_view_outlives_parent();
    test_f64_nested_view();
    test_i64_set_detaches_view();
    test_i64_set_null_detaches_view();
    test_i64_view_outlives_parent();
    test_cow_oob_does_not_detach();
    test_f64_append_detaches_view();
    test_f64_append_null_detaches_view();
    test_f64_append_zero_size_view();
    test_f64_append_then_grow();
    test_i64_append_detaches_view();
    test_i64_append_null_detaches_view();

    printf("PASS: COW (%d checks)\n", n_checks);
    return 0;
}
