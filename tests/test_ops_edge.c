/* tests/test_ops_edge.c
 *
 * Cobre ramos defensivos e de valores especiais das operações numéricas que os
 * testes via frontend não exercitam (o frontend usa quase sempre o caminho
 * "feliz"): reduções com ignore_na=false sobre NULL, reduções em série vazia,
 * e operações binárias com argumento NULL ou tamanhos incompatíveis.
 *
 * Objetivo: subir o branch coverage de smaug_ops_f64.c / smaug_ops_i64.c —
 * estes caminhos são corretos e devem ter teste, não só serem alcançados de
 * passagem. Sem alocação dinâmica complexa; rode sob Valgrind mesmo assim.
 */

#include "../include/smaug.h"
#include <assert.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static long n_checks = 0;
#define OK(cond, msg) do { if (!(cond)) { \
    fprintf(stderr, "FALHOU: %s\n", msg); exit(1); } n_checks++; } while (0)

/* ======================================================================
   f64 — reduções com ignore_na=false sobre NULL (caminho que retorna NAN)
   ====================================================================== */
static void f64_reduce_na_false(void) {
    smaug_series_f64_t *s = smaug_f64_create(3);
    smaug_f64_set(s, 0, 10);
    smaug_f64_set_null(s, 1);          /* NULL no meio */
    smaug_f64_set(s, 2, 20);

    /* ignore_na=true: ignora o NULL */
    OK(smaug_f64_sum(s, true)  == 30.0, "f64 sum ignore_na=true");
    OK(smaug_f64_mean(s, true) == 15.0, "f64 mean ignore_na=true");
    OK(smaug_f64_min(s, true)  == 10.0, "f64 min ignore_na=true");
    OK(smaug_f64_max(s, true)  == 20.0, "f64 max ignore_na=true");

    /* ignore_na=false: encontra NULL -> NAN (ramo else if (!ignore_na)) */
    OK(isnan(smaug_f64_sum(s, false)),  "f64 sum ignore_na=false -> NaN");
    OK(isnan(smaug_f64_mean(s, false)), "f64 mean ignore_na=false -> NaN");
    OK(isnan(smaug_f64_min(s, false)),  "f64 min ignore_na=false -> NaN");
    OK(isnan(smaug_f64_max(s, false)),  "f64 max ignore_na=false -> NaN");
    OK(isnan(smaug_f64_var(s, false)),  "f64 var ignore_na=false -> NaN");
    OK(isnan(smaug_f64_std(s, false)),  "f64 std ignore_na=false -> NaN");

    smaug_f64_free(s);
}

/* f64 — reduções em série vazia (size == 0) */
static void f64_reduce_empty(void) {
    smaug_series_f64_t *e = smaug_f64_create(0);
    OK(smaug_f64_sum(e, true) == 0.0, "f64 sum vazio = 0");
    OK(isnan(smaug_f64_mean(e, true)), "f64 mean vazio = NaN");
    OK(isnan(smaug_f64_min(e, true)),  "f64 min vazio = NaN");
    OK(isnan(smaug_f64_max(e, true)),  "f64 max vazio = NaN");
    OK(isnan(smaug_f64_var(e, true)),  "f64 var vazio = NaN");
    OK(isnan(smaug_f64_std(e, true)),  "f64 std vazio = NaN");
    smaug_f64_free(e);
}

/* f64 — série toda-NULL (reduções com ignore_na=true não acham nada) */
static void f64_reduce_all_null(void) {
    smaug_series_f64_t *s = smaug_f64_create(2);
    smaug_f64_set_null(s, 0);
    smaug_f64_set_null(s, 1);
    OK(smaug_f64_sum(s, true) == 0.0, "f64 sum todo-NULL = 0");
    OK(isnan(smaug_f64_mean(s, true)), "f64 mean todo-NULL = NaN");
    OK(isnan(smaug_f64_min(s, true)),  "f64 min todo-NULL = NaN");
    smaug_f64_free(s);
}

/* f64 — operações binárias: NULL e tamanhos incompatíveis -> NULL */
static void f64_binop_guards(void) {
    smaug_series_f64_t *a = smaug_f64_create(3);
    smaug_series_f64_t *b = smaug_f64_create(2);   /* tamanho diferente */
    for (size_t i = 0; i < 3; i++) smaug_f64_set(a, i, (double)i);
    for (size_t i = 0; i < 2; i++) smaug_f64_set(b, i, (double)i);

    /* tamanhos diferentes */
    OK(smaug_f64_add(a, b) == NULL, "f64 add tam-dif -> NULL");
    OK(smaug_f64_sub(a, b) == NULL, "f64 sub tam-dif -> NULL");
    OK(smaug_f64_mul(a, b) == NULL, "f64 mul tam-dif -> NULL");
    OK(smaug_f64_div(a, b) == NULL, "f64 div tam-dif -> NULL");

    /* argumento NULL */
    OK(smaug_f64_add(NULL, a) == NULL, "f64 add NULL a -> NULL");
    OK(smaug_f64_add(a, NULL) == NULL, "f64 add NULL b -> NULL");

    smaug_f64_free(a);
    smaug_f64_free(b);
}

/* f64 — div por zero e operações com NULL preservam semântica */
static void f64_div_zero_and_null(void) {
    smaug_series_f64_t *a = smaug_f64_create(3);
    smaug_series_f64_t *b = smaug_f64_create(3);
    smaug_f64_set(a, 0, 10); smaug_f64_set(a, 1, 20); smaug_f64_set_null(a, 2);
    smaug_f64_set(b, 0, 0);  smaug_f64_set(b, 1, 4);  smaug_f64_set(b, 2, 2);

    smaug_series_f64_t *r = smaug_f64_div(a, b);
    OK(r != NULL, "f64 div ok");
    /* 10/0 = Inf (IEEE), 20/4 = 5, NULL/2 = NULL */
    OK(isinf(smaug_f64_get(r, 0, NULL)), "f64 div por zero = Inf");
    OK(smaug_f64_get(r, 1, NULL) == 5.0, "f64 div normal");
    OK(smaug_f64_is_null(r, 2), "f64 div com NULL preserva NULL");

    smaug_f64_free(a); smaug_f64_free(b); smaug_f64_free(r);
}

/* ======================================================================
   i64 — mesmos padrões (ignore_na=false, vazio, guardas, div/0 -> NULL)
   ====================================================================== */
static void i64_reduce_na_false(void) {
    smaug_series_i64_t *s = smaug_i64_create(3);
    smaug_i64_set(s, 0, 10);
    smaug_i64_set_null(s, 1);
    smaug_i64_set(s, 2, 20);

    OK(smaug_i64_sum(s, true) == 30, "i64 sum ignore_na=true");

    /* ignore_na=false com NULL: i64 usa sentinela INT64_MIN (nil no frontend) */
    OK(smaug_i64_sum(s, false) == INT64_MIN, "i64 sum ignore_na=false -> sentinela");
    OK(smaug_i64_min(s, false) == INT64_MIN, "i64 min ignore_na=false -> sentinela");
    OK(smaug_i64_max(s, false) == INT64_MIN, "i64 max ignore_na=false -> sentinela");

    smaug_i64_free(s);
}

static void i64_reduce_empty(void) {
    smaug_series_i64_t *e = smaug_i64_create(0);
    OK(smaug_i64_sum(e, true) == 0, "i64 sum vazio = 0");
    /* mean de i64 retorna double */
    OK(isnan(smaug_i64_mean(e, true)), "i64 mean vazio = NaN");
    smaug_i64_free(e);
}

static void i64_binop_guards(void) {
    smaug_series_i64_t *a = smaug_i64_create(3);
    smaug_series_i64_t *b = smaug_i64_create(2);
    for (size_t i = 0; i < 3; i++) smaug_i64_set(a, i, (int64_t)i);
    for (size_t i = 0; i < 2; i++) smaug_i64_set(b, i, (int64_t)i);

    OK(smaug_i64_add(a, b) == NULL, "i64 add tam-dif -> NULL");
    OK(smaug_i64_add(NULL, a) == NULL, "i64 add NULL -> NULL");

    smaug_i64_free(a);
    smaug_i64_free(b);
}

/* i64 — divisão por zero vira NULL (não Inf; inteiro não tem Inf) */
static void i64_div_zero(void) {
    smaug_series_i64_t *a = smaug_i64_create(2);
    smaug_series_i64_t *b = smaug_i64_create(2);
    smaug_i64_set(a, 0, 10); smaug_i64_set(a, 1, 20);
    smaug_i64_set(b, 0, 0);  smaug_i64_set(b, 1, 5);

    smaug_series_i64_t *r = smaug_i64_div(a, b);
    OK(r != NULL, "i64 div ok");
    OK(smaug_i64_is_null(r, 0), "i64 div por zero -> NULL");
    OK(smaug_i64_get(r, 1, NULL) == 4, "i64 div normal (20/5=4)");

    smaug_i64_free(a); smaug_i64_free(b); smaug_i64_free(r);
}

/* f64 — scalar ops: guarda NULL e div_scalar por zero */
static void f64_scalar_edge(void) {
    smaug_series_f64_t *a = smaug_f64_create(2);
    smaug_f64_set(a, 0, 10); smaug_f64_set_null(a, 1);

    /* guarda NULL */
    OK(smaug_f64_add_scalar(NULL, 1) == NULL, "f64 add_scalar NULL -> NULL");
    OK(smaug_f64_div_scalar(NULL, 1) == NULL, "f64 div_scalar NULL -> NULL");

    /* preserva NULL do elemento */
    smaug_series_f64_t *r = smaug_f64_add_scalar(a, 5);
    OK(r && r->size == 2, "f64 add_scalar ok");
    OK(smaug_f64_get(r, 0, NULL) == 15.0, "f64 add_scalar valor");
    OK(smaug_f64_is_null(r, 1), "f64 add_scalar preserva NULL");
    smaug_f64_free(r);

    /* div_scalar por zero: 10/0 = Inf (IEEE) */
    smaug_series_f64_t *dz = smaug_f64_div_scalar(a, 0);
    OK(dz && isinf(smaug_f64_get(dz, 0, NULL)), "f64 div_scalar por zero = Inf");
    smaug_f64_free(dz);

    smaug_f64_free(a);
}

/* f64 — comparações: guarda NULL, out_mask NULL, e NULL no elemento */
static void f64_compare_edge(void) {
    smaug_series_f64_t *s = smaug_f64_create(3);
    smaug_f64_set(s, 0, 1); smaug_f64_set_null(s, 1); smaug_f64_set(s, 2, 3);

    OK(smaug_f64_gt(NULL, 0, NULL) == NULL, "f64 gt NULL serie -> NULL");

    /* out_mask = NULL (caller não quer a máscara) */
    uint8_t *r = smaug_f64_gt(s, 2, NULL);
    OK(r != NULL, "f64 gt sem out_mask ok");
    OK(r[2] == 1 && r[0] == 0, "f64 gt valores");
    free(r);

    /* com out_mask: NULL no elemento -> máscara 0 */
    smaug_mask_t *m = NULL;
    r = smaug_f64_lt(s, 5, &m);
    OK(m && m[1] == 0x00, "f64 lt NULL -> mascara 0");
    free(r); free(m);

    smaug_f64_free(s);
}

/* f64 — sort/argsort recusam NULL e NaN */
static void f64_sort_edge(void) {
    smaug_series_f64_t *sn = smaug_f64_create(3);
    smaug_f64_set(sn, 0, 3); smaug_f64_set_null(sn, 1); smaug_f64_set(sn, 2, 1);
    OK(smaug_f64_argsort(sn, true) == NULL, "f64 argsort recusa NULL");
    OK(smaug_f64_sort(sn, true) == NULL, "f64 sort recusa NULL");
    smaug_f64_free(sn);

    /* NaN também é recusado (valor presente, mas sem ordem total) */
    smaug_series_f64_t *snan = smaug_f64_create(2);
    smaug_f64_set(snan, 0, NAN); smaug_f64_set(snan, 1, 1);
    OK(smaug_f64_argsort(snan, true) == NULL, "f64 argsort recusa NaN");
    smaug_f64_free(snan);
}

/* f64 — take fora dos limites e filter */
static void f64_take_filter_edge(void) {
    smaug_series_f64_t *s = smaug_f64_create(3);
    for (size_t i = 0; i < 3; i++) smaug_f64_set(s, i, (double)i);

    size_t bad[] = {99};
    OK(smaug_f64_take(s, bad, 1) == NULL, "f64 take fora-limites -> NULL");

    uint8_t mask[] = {1, 0, 1};
    smaug_series_f64_t *f = smaug_f64_filter(s, mask);
    OK(f && f->size == 2, "f64 filter ok");
    smaug_f64_free(f);

    OK(smaug_f64_filter(NULL, mask) == NULL, "f64 filter NULL -> NULL");

    smaug_f64_free(s);
}

/* i64 — scalar, comparação e sort edge (espelha o f64) */
static void i64_scalar_compare_sort_edge(void) {
    smaug_series_i64_t *a = smaug_i64_create(2);
    smaug_i64_set(a, 0, 10); smaug_i64_set_null(a, 1);

    /* scalar guarda NULL + preserva NULL do elemento */
    OK(smaug_i64_add_scalar(NULL, 1) == NULL, "i64 add_scalar NULL -> NULL");
    smaug_series_i64_t *r = smaug_i64_add_scalar(a, 5);
    OK(r && smaug_i64_get(r, 0, NULL) == 15, "i64 add_scalar valor");
    OK(smaug_i64_is_null(r, 1), "i64 add_scalar preserva NULL");
    smaug_i64_free(r);

    /* div_scalar por zero -> NULL (inteiro) */
    smaug_series_i64_t *dz = smaug_i64_div_scalar(a, 0);
    OK(dz && smaug_i64_is_null(dz, 0), "i64 div_scalar por zero -> NULL");
    smaug_i64_free(dz);

    /* comparação: guarda NULL, out_mask NULL */
    OK(smaug_i64_gt(NULL, 0, NULL) == NULL, "i64 gt NULL -> NULL");
    uint8_t *c = smaug_i64_gt(a, 5, NULL);
    OK(c && c[0] == 1, "i64 gt sem out_mask");
    free(c);

    /* sort/argsort recusam NULL */
    OK(smaug_i64_argsort(a, true) == NULL, "i64 argsort recusa NULL");
    OK(smaug_i64_sort(a, true) == NULL, "i64 sort recusa NULL");

    /* take fora dos limites */
    smaug_series_i64_t *full = smaug_i64_create(2);
    smaug_i64_set(full, 0, 1); smaug_i64_set(full, 1, 2);
    size_t bad[] = {5};
    OK(smaug_i64_take(full, bad, 1) == NULL, "i64 take fora-limites -> NULL");
    smaug_i64_free(full);

    smaug_i64_free(a);
}

/* ======================================================================
   Contrato defensivo: set/set_null comunicam sucesso/falha via smaug_status_t
   (SMG_OK / SMG_ERR_OOB / SMG_ERR_ARGUMENT). Prova que a falha deixou de ser
   silenciosa — o caller distingue escrita aplicada de escrita rejeitada — e que
   em erro NENHUMA escrita ocorre.
   ====================================================================== */
static void mutation_status_contract(void) {
    /* --- f64 --- */
    smaug_series_f64_t *f = smaug_f64_create(2);
    OK(smaug_f64_set(f, 0, 1.5)    == SMG_OK,           "f64_set idx valido -> OK");
    OK(smaug_f64_set_null(f, 1)    == SMG_OK,           "f64_set_null idx valido -> OK");
    OK(smaug_f64_set(f, 9, 1.0)    == SMG_ERR_OOB,      "f64_set OOB");
    OK(smaug_f64_set_null(f, 9)    == SMG_ERR_OOB,      "f64_set_null OOB");
    OK(smaug_f64_set(NULL, 0, 1.0) == SMG_ERR_ARGUMENT, "f64_set serie NULL -> ARGUMENT");
    OK(smaug_f64_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "f64_set_null serie NULL -> ARGUMENT");
    OK(smaug_f64_get(f, 0, NULL) == 1.5, "f64 erro nao corrompeu idx 0");
    OK(smaug_f64_is_null(f, 1),    "f64 idx 1 segue NULL");
    smaug_f64_free(f);

    /* --- i64 --- */
    smaug_series_i64_t *n = smaug_i64_create(2);
    OK(smaug_i64_set(n, 0, 42)     == SMG_OK,           "i64_set idx valido -> OK");
    OK(smaug_i64_set_null(n, 1)    == SMG_OK,           "i64_set_null idx valido -> OK");
    OK(smaug_i64_set(n, 9, 1)      == SMG_ERR_OOB,      "i64_set OOB");
    OK(smaug_i64_set_null(n, 9)    == SMG_ERR_OOB,      "i64_set_null OOB");
    OK(smaug_i64_set(NULL, 0, 1)   == SMG_ERR_ARGUMENT, "i64_set serie NULL -> ARGUMENT");
    OK(smaug_i64_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "i64_set_null serie NULL -> ARGUMENT");
    OK(smaug_i64_get(n, 0, NULL) == 42,  "i64 erro nao corrompeu idx 0");
    smaug_i64_free(n);

    /* --- str_set_null (entrou no contrato; antes era void) --- */
    smaug_series_str_t *s = smaug_str_create(2);
    OK(smaug_str_set(s, 0, "ab", 2) == 0,                "str_set idx valido (legado 0=ok)");
    OK(smaug_str_set_null(s, 1)     == SMG_OK,           "str_set_null idx valido -> OK");
    OK(smaug_str_set_null(s, 9)     == SMG_ERR_OOB,      "str_set_null OOB");
    OK(smaug_str_set_null(NULL, 0)  == SMG_ERR_ARGUMENT, "str_set_null serie NULL -> ARGUMENT");
    OK(smaug_str_is_null(s, 1),     "str_set_null marcou NULL idx 1");
    smaug_str_free(s);
}

/* ======================================================================
   Contrato defensivo: get (Shape 1) — valor + smaug_status_t* anulável.
   Prova que a COLISÃO acabou: um NaN legítimo (f64) e um zero legítimo (i64)
   retornam SMG_OK, distinguíveis de NULL (SMG_NULL_VALUE) e de índice inválido
   (SMG_ERR_OOB) — que antes eram indistinguíveis do valor.
   ====================================================================== */
static void get_status_contract(void) {
    smaug_status_t st;

    /* --- f64: o caso que prova o fim da colisão NaN --- */
    smaug_series_f64_t *f = smaug_f64_create(3);
    smaug_f64_set(f, 0, 3.14);
    smaug_f64_set(f, 1, NAN);      /* NaN LEGÍTIMO como valor */
    smaug_f64_set_null(f, 2);      /* NULL */

    st = SMG_ERR_OOB;
    OK(smaug_f64_get(f, 0, &st) == 3.14 && st == SMG_OK, "f64 get valor -> OK");
    double vnan = smaug_f64_get(f, 1, &st);              /* valor NaN, status OK */
    OK(isnan(vnan) && st == SMG_OK, "f64 get NaN legitimo -> NaN + OK (colisao resolvida)");
    smaug_f64_get(f, 2, &st); OK(st == SMG_NULL_VALUE,   "f64 get NULL -> SMG_NULL_VALUE");
    smaug_f64_get(f, 9, &st); OK(st == SMG_ERR_OOB,      "f64 get OOB -> SMG_ERR_OOB");
    smaug_f64_get(NULL, 0, &st); OK(st == SMG_ERR_ARGUMENT, "f64 get serie NULL -> ARGUMENT");
    OK(smaug_f64_get(f, 0, NULL) == 3.14, "f64 get status=NULL ainda devolve valor");
    smaug_f64_free(f);

    /* --- i64: aqui a colisão era TOTAL (0 é um valor comum) --- */
    smaug_series_i64_t *n = smaug_i64_create(2);
    smaug_i64_set(n, 0, 0);        /* ZERO legítimo */
    smaug_i64_set_null(n, 1);      /* NULL (também devolve 0) */
    st = SMG_ERR_OOB;
    OK(smaug_i64_get(n, 0, &st) == 0 && st == SMG_OK, "i64 get zero legitimo -> 0 + OK");
    OK(smaug_i64_get(n, 1, &st) == 0 && st == SMG_NULL_VALUE,
       "i64 get NULL -> 0 + NULL_VALUE (distingue do zero)");
    smaug_i64_get(n, 9, &st); OK(st == SMG_ERR_OOB,      "i64 get OOB -> SMG_ERR_OOB");
    smaug_i64_get(NULL, 0, &st); OK(st == SMG_ERR_ARGUMENT, "i64 get serie NULL -> ARGUMENT");
    OK(smaug_i64_get(n, 0, NULL) == 0, "i64 get status=NULL ainda devolve valor");
    smaug_i64_free(n);
}

/* ======================================================================
   Semântica Fechada — A2: view com start+len que overflow size_t deve ser
   rejeitada corretamente. A checagem antiga `start + len > size` pode fazer
   wrap-around em size_t, permitindo que valores absurdos passem; a forma
   segura é `start > size || len > size - start`.
   ====================================================================== */
static void view_overflow_boundary(void) {
    smaug_series_f64_t *s = smaug_f64_create(4);

    /* limites normais: deve funcionar */
    smaug_series_f64_t *v = smaug_f64_view(s, 0, 4);
    OK(v != NULL,                    "view start=0 len=size valida");
    smaug_f64_free(v);
    v = smaug_f64_view(s, 2, 2);
    OK(v != NULL,                    "view start+len == size valida");
    smaug_f64_free(v);

    /* além dos limites normais: deve ser rejeitada */
    OK(smaug_f64_view(s, 0, 5) == NULL,  "view len > size -> NULL");
    OK(smaug_f64_view(s, 3, 2) == NULL,  "view start+len > size -> NULL");

    /* overflow de size_t: len=SIZE_MAX; com a checagem antiga,
       start(1)+SIZE_MAX wrappa para 0 < size(4) e passaria — bug real.
       Com a checagem segura SIZE_MAX > size-start = 3 → rejeitada. */
    OK(smaug_f64_view(s, 1, SIZE_MAX) == NULL,
       "view len=SIZE_MAX overflow-safe -> NULL");

    /* i64 — mesma garantia */
    smaug_series_i64_t *si = smaug_i64_create(4);
    OK(smaug_i64_view(si, 1, SIZE_MAX) == NULL,
       "i64 view len=SIZE_MAX overflow-safe -> NULL");
    smaug_i64_free(si);

    smaug_f64_free(s);
}

/* ======================================================================
   Semântica Fechada — A3: NaN em comparações (nível C).
   NaN > threshold = false (IEEE 754); a máscara é VÁLIDA (0xFF), não NA.
   Isso é distinto de NULL: um NULL em gt produz máscara 0x00 (NA).
   ====================================================================== */
static void nan_in_compare(void) {
    smaug_series_f64_t *s = smaug_f64_create(3);
    smaug_f64_set(s, 0, 5.0);
    smaug_f64_set(s, 1, NAN);   /* NaN como valor presente */
    smaug_f64_set_null(s, 2);   /* NULL genuíno */

    smaug_mask_t *m = NULL;
    uint8_t *r = smaug_f64_gt(s, 0.0, &m);
    OK(r != NULL,      "gt com NaN: retorna resultado");
    OK(r[0] == 1,      "gt: 5.0 > 0 = true");
    OK(r[1] == 0,      "gt: NaN > 0 = false (IEEE)");
    OK(m[1] == 0xFF,   "gt: máscara de NaN = válida (não NA)");
    OK(r[2] == 0,      "gt: NULL > 0 = false");
    OK(m[2] == 0x00,   "gt: máscara de NULL = NA (0x00)");
    free(r); free(m);

    /* lt também */
    r = smaug_f64_lt(s, 3.0, &m);
    OK(r != NULL,      "lt com NaN: retorna resultado");
    OK(r[1] == 0,      "lt: NaN < 3 = false (IEEE)");
    OK(m[1] == 0xFF,   "lt: máscara de NaN = válida");
    free(r); free(m);

    /* eq */
    r = smaug_f64_eq(s, NAN, &m);
    OK(r != NULL,      "eq NaN==NaN: retorna resultado");
    OK(r[1] == 0,      "eq: NaN == NaN = false (IEEE)");
    OK(m[1] == 0xFF,   "eq: máscara NaN = válida");
    free(r); free(m);

    smaug_f64_free(s);
}

/* ======================================================================
   Semântica Fechada — A4: overflow de int64_t em operações aritméticas.
   C não define o comportamento de overflow de inteiros sinalizados, mas em
   todas as plataformas suportadas (x86/x64, GCC/Clang -O2) o resultado é
   wrap-around em complemento de 2 — o mesmo comportamento de pandas/numpy.
   O contrato do Smaug é: overflow produz um valor presente (não NULL),
   sendo o valor resultante dependente da plataforma (wrap em C).
   ====================================================================== */
static void i64_overflow_behavior(void) {
    /* Testa que overflow não causa crash, não vira NULL, não corrompe. */
    smaug_series_i64_t *a = smaug_i64_create(1);
    smaug_series_i64_t *b = smaug_i64_create(1);

    smaug_i64_set(a, 0, INT64_MAX);
    smaug_i64_set(b, 0, 1);
    smaug_series_i64_t *r = smaug_i64_add(a, b);  /* INT64_MAX + 1 */
    OK(r != NULL,                   "i64 overflow: add retorna serie");
    OK(!smaug_i64_is_null(r, 0),    "i64 overflow: resultado e valor presente (nao NULL)");
    /* o valor real é INT64_MIN em complemento de 2 — documentado, não é bug */
    smaug_i64_free(r);

    /* mul overflow: INT64_MAX * 2 */
    smaug_i64_set(b, 0, 2);
    r = smaug_i64_mul(a, b);
    OK(r != NULL,                   "i64 overflow mul: retorna serie");
    OK(!smaug_i64_is_null(r, 0),    "i64 overflow mul: resultado presente");
    smaug_i64_free(r);

    /* scalar: INT64_MAX + 1 via add_scalar */
    r = smaug_i64_add_scalar(a, 1);
    OK(r != NULL,                   "i64 overflow add_scalar: retorna serie");
    OK(!smaug_i64_is_null(r, 0),    "i64 overflow add_scalar: resultado presente");
    smaug_i64_free(r);

    smaug_i64_free(a);
    smaug_i64_free(b);
}

/* ======================================================================
   FASE 8 / categoria C — propagação de NULL nas aritméticas binárias.
   O ramo descoberto é a 2a condição do `VALID(a,i) && VALID(b,i)`: "b NULL
   com a VÁLIDO" (os testes de div só faziam "a NULL", que curto-circuita em
   VALID(a) e nunca avalia VALID(b)). Padrão [ambos válidos | a-val/b-null |
   a-null/b-val] exercita as 4 branches do &&.
   ====================================================================== */
static void f64_arith_null_prop(void) {
    smaug_series_f64_t *a = smaug_f64_create(3);
    smaug_series_f64_t *b = smaug_f64_create(3);
    smaug_f64_set(a, 0, 1);  smaug_f64_set(a, 1, 2);  smaug_f64_set_null(a, 2);
    smaug_f64_set(b, 0, 10); smaug_f64_set_null(b, 1); smaug_f64_set(b, 2, 30);

    smaug_series_f64_t *r;
    #define CHECK_PROP(op, name) \
        r = smaug_f64_##op(a, b); \
        OK(!smaug_f64_is_null(r, 0), name " pos0 (ambos validos) -> valido"); \
        OK(smaug_f64_is_null(r, 1),  name " pos1 (b NULL, a valido) -> NULL"); \
        OK(smaug_f64_is_null(r, 2),  name " pos2 (a NULL) -> NULL"); \
        smaug_f64_free(r)
    CHECK_PROP(add, "f64 add");
    CHECK_PROP(sub, "f64 sub");
    CHECK_PROP(mul, "f64 mul");
    CHECK_PROP(div, "f64 div");
    #undef CHECK_PROP

    smaug_f64_free(a); smaug_f64_free(b);
}

static void i64_arith_null_prop(void) {
    smaug_series_i64_t *a = smaug_i64_create(3);
    smaug_series_i64_t *b = smaug_i64_create(3);
    smaug_i64_set(a, 0, 6);  smaug_i64_set(a, 1, 8);  smaug_i64_set_null(a, 2);
    smaug_i64_set(b, 0, 2);  smaug_i64_set_null(b, 1); smaug_i64_set(b, 2, 4);

    smaug_series_i64_t *r;
    #define CHECK_PROP(op, name) \
        r = smaug_i64_##op(a, b); \
        OK(!smaug_i64_is_null(r, 0), name " pos0 (ambos validos) -> valido"); \
        OK(smaug_i64_is_null(r, 1),  name " pos1 (b NULL, a valido) -> NULL"); \
        OK(smaug_i64_is_null(r, 2),  name " pos2 (a NULL) -> NULL"); \
        smaug_i64_free(r)
    CHECK_PROP(add, "i64 add");
    CHECK_PROP(sub, "i64 sub");
    CHECK_PROP(mul, "i64 mul");
    CHECK_PROP(div, "i64 div");
    #undef CHECK_PROP

    smaug_i64_free(a); smaug_i64_free(b);
}

/* ======================================================================
   FASE 8 / frente A1 — varredura de input inválido nas ops numéricas.
   Verifica o contrato "o engine não confia no caller": toda fronteira pública
   recusa ponteiro NULL / tamanho incompatível com falha limpa. Cobre só o que
   o f64_binop_guards/scalar_edge ainda NÃO pegam (sub/mul/div NULL, i64 tam-dif,
   sub/mul_scalar, lt/eq, take/filter NULL, reduções com ponteiro NULL, e os
   getters com status=NULL no caminho de erro -> exercita o `if(status)` falso).
   Retornos-em-NULL conferidos contra o código (diferem por função).
   ====================================================================== */
static void numeric_guard_sweep(void) {
    smaug_series_f64_t *fa = smaug_f64_create(3);
    smaug_f64_set(fa, 0, 1); smaug_f64_set(fa, 1, 2); smaug_f64_set(fa, 2, 3);
    smaug_series_i64_t *ia = smaug_i64_create(3);
    smaug_i64_set(ia, 0, 1); smaug_i64_set(ia, 1, 2); smaug_i64_set(ia, 2, 3);
    smaug_series_i64_t *ib2 = smaug_i64_create(2);   /* tamanho diferente */

    /* binops: NULL em qualquer operando -> NULL (cobre as 2 sub-condições do ||) */
    OK(smaug_f64_sub(NULL, fa) == NULL && smaug_f64_sub(fa, NULL) == NULL, "f64 sub NULL -> NULL");
    OK(smaug_f64_mul(NULL, fa) == NULL && smaug_f64_mul(fa, NULL) == NULL, "f64 mul NULL -> NULL");
    OK(smaug_f64_div(NULL, fa) == NULL && smaug_f64_div(fa, NULL) == NULL, "f64 div NULL -> NULL");
    OK(smaug_i64_sub(NULL, ia) == NULL && smaug_i64_sub(ia, NULL) == NULL, "i64 sub NULL -> NULL");
    OK(smaug_i64_mul(NULL, ia) == NULL && smaug_i64_mul(ia, NULL) == NULL, "i64 mul NULL -> NULL");
    OK(smaug_i64_div(NULL, ia) == NULL && smaug_i64_div(ia, NULL) == NULL, "i64 div NULL -> NULL");

    /* binops i64: tamanho incompatível (add já coberto pelo i64_binop) */
    OK(smaug_i64_sub(ia, ib2) == NULL, "i64 sub tam-dif -> NULL");
    OK(smaug_i64_mul(ia, ib2) == NULL, "i64 mul tam-dif -> NULL");
    OK(smaug_i64_div(ia, ib2) == NULL, "i64 div tam-dif -> NULL");

    /* escalares: série NULL -> NULL (add/div já cobertos) */
    OK(smaug_f64_sub_scalar(NULL, 1) == NULL, "f64 sub_scalar NULL -> NULL");
    OK(smaug_f64_mul_scalar(NULL, 1) == NULL, "f64 mul_scalar NULL -> NULL");
    OK(smaug_i64_sub_scalar(NULL, 1) == NULL, "i64 sub_scalar NULL -> NULL");
    OK(smaug_i64_mul_scalar(NULL, 1) == NULL, "i64 mul_scalar NULL -> NULL");
    OK(smaug_i64_div_scalar(NULL, 1) == NULL, "i64 div_scalar NULL -> NULL");

    /* comparações: série NULL -> NULL (gt já coberto) */
    OK(smaug_f64_lt(NULL, 0, NULL) == NULL, "f64 lt NULL -> NULL");
    OK(smaug_f64_eq(NULL, 0, NULL) == NULL, "f64 eq NULL -> NULL");
    OK(smaug_i64_lt(NULL, 0, NULL) == NULL, "i64 lt NULL -> NULL");
    OK(smaug_i64_eq(NULL, 0, NULL) == NULL, "i64 eq NULL -> NULL");

    /* take/filter: cobre as sub-condições !s e !idx/!mask */
    {
        size_t  idx[1]  = { 0 };
        uint8_t mask[1] = { 1 };
        OK(smaug_f64_take(NULL, idx, 1) == NULL, "f64 take serie NULL -> NULL");
        OK(smaug_f64_take(fa, NULL, 1)  == NULL, "f64 take idx NULL -> NULL");
        OK(smaug_f64_filter(NULL, mask) == NULL, "f64 filter serie NULL -> NULL");
        OK(smaug_f64_filter(fa, NULL)   == NULL, "f64 filter mask NULL -> NULL");
        OK(smaug_i64_take(NULL, idx, 1) == NULL, "i64 take serie NULL -> NULL");
        OK(smaug_i64_take(ia, NULL, 1)  == NULL, "i64 take idx NULL -> NULL");
        OK(smaug_i64_filter(NULL, mask) == NULL, "i64 filter serie NULL -> NULL");
        OK(smaug_i64_filter(ia, NULL)   == NULL, "i64 filter mask NULL -> NULL");
    }

    /* reduções: PONTEIRO NULL (distinto de série toda-nula) */
    OK(isnan(smaug_f64_sum(NULL, true)),       "f64 sum NULL -> NaN");
    OK(isnan(smaug_f64_mean(NULL, true)),      "f64 mean NULL -> NaN");
    OK(isnan(smaug_f64_min(NULL, true)),       "f64 min NULL -> NaN");
    OK(isnan(smaug_f64_max(NULL, true)),       "f64 max NULL -> NaN");
    OK(isnan(smaug_f64_var(NULL, true)),       "f64 var NULL -> NaN");
    OK(isnan(smaug_f64_std(NULL, true)),       "f64 std NULL -> NaN");
    OK(smaug_f64_count_nonnull(NULL) == 0,     "f64 count_nonnull NULL -> 0");
    OK(smaug_i64_sum(NULL, true) == 0,         "i64 sum NULL -> 0");
    OK(smaug_i64_min(NULL, true) == INT64_MIN, "i64 min NULL -> INT64_MIN");
    OK(smaug_i64_max(NULL, true) == INT64_MIN, "i64 max NULL -> INT64_MIN");
    OK(isnan(smaug_i64_mean(NULL, true)),      "i64 mean NULL -> NaN");
    OK(isnan(smaug_i64_var(NULL, true)),       "i64 var NULL -> NaN");
    OK(isnan(smaug_i64_std(NULL, true)),       "i64 std NULL -> NaN");
    OK(smaug_i64_count_nonnull(NULL) == 0,     "i64 count_nonnull NULL -> 0");

    /* getters: status=NULL no caminho de ERRO -> if(status) falso, sem crash */
    smaug_series_f64_t *fn = smaug_f64_create(2);
    smaug_f64_set(fn, 0, 1); smaug_f64_set_null(fn, 1);
    OK(isnan(smaug_f64_get(NULL, 0, NULL)), "f64 get(serie NULL, status=NULL) -> NaN");
    OK(isnan(smaug_f64_get(fn, 9, NULL)),   "f64 get(OOB, status=NULL) -> NaN");
    OK(isnan(smaug_f64_get(fn, 1, NULL)),   "f64 get(pos NULL, status=NULL) -> NaN");
    smaug_series_i64_t *in = smaug_i64_create(2);
    smaug_i64_set(in, 0, 7); smaug_i64_set_null(in, 1);
    OK(smaug_i64_get(NULL, 0, NULL) == 0,   "i64 get(serie NULL, status=NULL) -> 0");
    OK(smaug_i64_get(in, 9, NULL)   == 0,   "i64 get(OOB, status=NULL) -> 0");
    OK(smaug_i64_get(in, 1, NULL)   == 0,   "i64 get(pos NULL, status=NULL) -> 0");

    smaug_f64_free(fa); smaug_f64_free(fn);
    smaug_i64_free(ia); smaug_i64_free(ib2); smaug_i64_free(in);
}

int main(void) {
    f64_arith_null_prop();
    i64_arith_null_prop();
    numeric_guard_sweep();
    f64_reduce_na_false();
    f64_reduce_empty();
    f64_reduce_all_null();
    f64_binop_guards();
    f64_div_zero_and_null();
    f64_scalar_edge();
    f64_compare_edge();
    f64_sort_edge();
    f64_take_filter_edge();

    i64_reduce_na_false();
    i64_reduce_empty();
    i64_binop_guards();
    i64_div_zero();
    i64_scalar_compare_sort_edge();

    mutation_status_contract();
    get_status_contract();

    view_overflow_boundary();
    nan_in_compare();
    i64_overflow_behavior();

    printf("PASS: ops edge (%ld checks)\n", n_checks);
    return 0;
}
