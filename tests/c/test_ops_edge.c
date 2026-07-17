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
    /* 10/0 = NULL (div/0 previsível), 20/4 = 5, NULL/2 = NULL */
    OK(smaug_f64_is_null(r, 0), "f64 div por zero = NULL");
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

    /* div_scalar por zero: tudo NULL (igual ao i64; div/0 não passa) */
    smaug_series_f64_t *dz = smaug_f64_div_scalar(a, 0);
    OK(dz && smaug_f64_is_null(dz, 0), "f64 div_scalar por zero = NULL");
    smaug_f64_free(dz);

    /* div_scalar normal sobre serie com null: ramo VALID verdadeiro (idx 0) e
       falso (idx 1, null preservado) */
    smaug_series_f64_t *dn = smaug_f64_div_scalar(a, 2);
    OK(dn && smaug_f64_get(dn, 0, NULL) == 5.0, "f64 div_scalar valor");
    OK(smaug_f64_is_null(dn, 1), "f64 div_scalar preserva NULL");
    smaug_f64_free(dn);

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

    /* ge/le/ne: mesma matriz de ramos (NULL serie, out_mask NULL, mask 0xFF/0x00) */
    OK(smaug_f64_ge(NULL, 0, NULL) == NULL, "f64 ge NULL serie -> NULL");
    OK(smaug_f64_le(NULL, 0, NULL) == NULL, "f64 le NULL serie -> NULL");
    OK(smaug_f64_ne(NULL, 0, NULL) == NULL, "f64 ne NULL serie -> NULL");

    r = smaug_f64_ge(s, 1, NULL);   /* out_mask NULL */
    OK(r != NULL && r[0] == 1 && r[2] == 1, "f64 ge sem out_mask");
    free(r);
    r = smaug_f64_le(s, 1, NULL);
    OK(r != NULL && r[0] == 1 && r[2] == 0, "f64 le sem out_mask");
    free(r);
    r = smaug_f64_ne(s, 1, NULL);
    OK(r != NULL && r[0] == 0 && r[2] == 1, "f64 ne sem out_mask");
    free(r);

    m = NULL; r = smaug_f64_ge(s, 1, &m);   /* com mask: 0xFF nos validos, 0x00 no NULL */
    OK(m && m[0] == 0xFF && m[1] == 0x00, "f64 ge mask valido/NULL");
    free(r); free(m);
    m = NULL; r = smaug_f64_le(s, 1, &m);
    OK(m && m[1] == 0x00, "f64 le mask NULL -> 0");
    free(r); free(m);
    m = NULL; r = smaug_f64_ne(s, 1, &m);
    OK(m && m[1] == 0x00, "f64 ne mask NULL -> 0");
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

    /* ge/le/ne: NULL serie, out_mask NULL, mask 0xFF/0x00 (a = [10, null]) */
    OK(smaug_i64_ge(NULL, 0, NULL) == NULL, "i64 ge NULL -> NULL");
    OK(smaug_i64_le(NULL, 0, NULL) == NULL, "i64 le NULL -> NULL");
    OK(smaug_i64_ne(NULL, 0, NULL) == NULL, "i64 ne NULL -> NULL");
    c = smaug_i64_ge(a, 10, NULL); OK(c && c[0] == 1, "i64 ge sem out_mask"); free(c);
    c = smaug_i64_le(a, 10, NULL); OK(c && c[0] == 1, "i64 le sem out_mask"); free(c);
    c = smaug_i64_ne(a, 10, NULL); OK(c && c[0] == 0, "i64 ne sem out_mask"); free(c);
    smaug_mask_t *mi = NULL;
    c = smaug_i64_ge(a, 10, &mi); OK(mi && mi[0] == 0xFF && mi[1] == 0x00, "i64 ge mask valido/NULL"); free(c); free(mi);
    mi = NULL; c = smaug_i64_le(a, 10, &mi); OK(mi && mi[1] == 0x00, "i64 le mask NULL -> 0"); free(c); free(mi);
    mi = NULL; c = smaug_i64_ne(a, 10, &mi); OK(mi && mi[1] == 0x00, "i64 ne mask NULL -> 0"); free(c); free(mi);

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
    /* o contrato documenta wrap determinístico em complemento de 2:
     * INT64_MAX + 1 == INT64_MIN. Verificar o valor prova que o wrap é
     * determinístico, não só "presente". */
    OK(smaug_i64_get(r, 0, NULL) == INT64_MIN, "i64 overflow: INT64_MAX+1 == INT64_MIN (wrap c2)");
    smaug_i64_free(r);

    /* mul overflow: INT64_MAX * 2 == -2 em complemento de 2 */
    smaug_i64_set(b, 0, 2);
    r = smaug_i64_mul(a, b);
    OK(r != NULL,                   "i64 overflow mul: retorna serie");
    OK(!smaug_i64_is_null(r, 0),    "i64 overflow mul: resultado presente");
    OK(smaug_i64_get(r, 0, NULL) == -2, "i64 overflow mul: INT64_MAX*2 == -2 (wrap c2)");
    smaug_i64_free(r);

    /* scalar: INT64_MAX + 1 via add_scalar == INT64_MIN */
    r = smaug_i64_add_scalar(a, 1);
    OK(r != NULL,                   "i64 overflow add_scalar: retorna serie");
    OK(!smaug_i64_is_null(r, 0),    "i64 overflow add_scalar: resultado presente");
    OK(smaug_i64_get(r, 0, NULL) == INT64_MIN, "i64 overflow add_scalar: == INT64_MIN (wrap c2)");
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

/* Guards de input: f64 argsort/sort com s=NULL (f64:359/390) */
static void f64_null_guard_sort(void) {
    OK(smaug_f64_argsort(NULL, true) == NULL, "f64 argsort(NULL) -> NULL");
    OK(smaug_f64_sort(NULL, true)    == NULL, "f64 sort(NULL) -> NULL");
}

/* Guards de input: i64 ops binárias com NULL/tamanho incompatível (i64:23) */
static void i64_null_guard_binop(void) {
    smaug_series_i64_t *a = smaug_i64_create(2);
    smaug_i64_set(a, 0, 1); smaug_i64_set(a, 1, 2);
    OK(smaug_i64_add(NULL, a) == NULL, "i64 add(NULL,a) -> NULL");
    OK(smaug_i64_add(a, NULL) == NULL, "i64 add(a,NULL) -> NULL");
    OK(smaug_i64_sub(NULL, a) == NULL, "i64 sub(NULL,a) -> NULL");
    OK(smaug_i64_mul(NULL, a) == NULL, "i64 mul(NULL,a) -> NULL");
    OK(smaug_i64_div(NULL, a) == NULL, "i64 div(NULL,a) -> NULL");
    smaug_i64_free(a);
}

/* Guards de input: i64 argsort/sort com s=NULL (i64:356/383) */
static void i64_null_guard_sort(void) {
    OK(smaug_i64_argsort(NULL, true) == NULL, "i64 argsort(NULL) -> NULL");
    OK(smaug_i64_sort(NULL, true)    == NULL, "i64 sort(NULL) -> NULL");
}

/* Guards de input + reachable: i64 reduções com s=NULL e size==0 (i64:176/195/232) */
static void i64_reduce_null_and_empty(void) {
    /* NULL */
    OK(smaug_i64_min(NULL, true)  == INT64_MIN, "i64 min(NULL) -> INT64_MIN");
    OK(smaug_i64_max(NULL, true)  == INT64_MIN, "i64 max(NULL) -> INT64_MIN");
    OK(isnan(smaug_i64_mean(NULL, true)),        "i64 mean(NULL) -> NaN");
    OK(isnan(smaug_i64_std(NULL, true)),         "i64 std(NULL) -> NaN");
    /* size==0: fecha o lado reachable do mesmo if */
    smaug_series_i64_t *e = smaug_i64_create(0);
    OK(smaug_i64_min(e, true)  == INT64_MIN, "i64 min(vazia) -> INT64_MIN");
    OK(smaug_i64_max(e, true)  == INT64_MIN, "i64 max(vazia) -> INT64_MIN");
    OK(isnan(smaug_i64_mean(e, true)),        "i64 mean(vazia) -> NaN");
    OK(isnan(smaug_i64_std(e, true)),         "i64 std(vazia) -> NaN");
    smaug_i64_free(e);
}

/* Guards de input: str set com str=NULL, len>0 (str:297) */
static void str_null_guard_set(void) {
    smaug_series_str_t *s = smaug_str_create(3);
    assert(s);
    smaug_status_t rc = smaug_str_set(s, 0, NULL, 5);
    OK(rc == SMG_ERR_ARGUMENT, "str set(NULL,len>0) -> ARGUMENT");
    smaug_str_free(s);
}

/* Guards de input: ops_str NULL target/s (ops_str:41/136) */
static void ops_str_null_guards(void) {
    const char *arr[] = {"a", "b", "c"};
    smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
    assert(s);
    /* compare com target=NULL e target_len>0 (ops_str:41) */
    OK(smaug_str_eq(s, NULL, 3, NULL) == NULL, "str_eq(target=NULL,len>0) -> NULL");
    OK(smaug_str_lt(s, NULL, 3, NULL) == NULL, "str_lt(target=NULL,len>0) -> NULL");
    OK(smaug_str_gt(s, NULL, 3, NULL) == NULL, "str_gt(target=NULL,len>0) -> NULL");
    smaug_str_free(s);

    /* ops_str:32 — ramo len > target_len em str_cmp_at:
       série com "abc" comparada contra target "ab" (2 bytes) — prefixo igual
       mas elemento é mais longo → return 1 (maior). */
    const char *long_arr[] = {"ab", "abc", "z"};
    smaug_series_str_t *sl = smaug_str_create_from_array(long_arr, 3);
    assert(sl);
    uint8_t *r = smaug_str_eq(sl, "ab", 2, NULL);
    OK(r && r[0]==1 && r[1]==0, "str_eq: elem mais longo que target nao eh igual");
    free(r);
    r = smaug_str_gt(sl, "ab", 2, NULL);
    OK(r && r[0]==0 && r[1]==1, "str_gt: 'abc' > 'ab' (len tiebreak)");
    free(r);
    /* ops_str:41 branch residual: target=NULL e target_len=0 (não é erro, compara contra "") */
    r = smaug_str_eq(sl, NULL, 0, NULL);
    OK(r != NULL, "str_eq(target=NULL,len=0) -> válido (compara contra string vazia)");
    free(r);
    smaug_str_free(sl);

    /* ops_str:136 — segundo ramo: s!=NULL mas idx==NULL e len>0 */
    OK(smaug_str_take(NULL, NULL, 1) == NULL, "str_take(NULL,NULL,1) -> NULL");
    /* take com s válido, idx=NULL, len>0 */
    const char *ta[] = {"x", "y"};
    smaug_series_str_t *st = smaug_str_create_from_array(ta, 2);
    OK(smaug_str_take(st, NULL, 1) == NULL, "str_take(s,NULL,len>0) -> NULL");
    /* branch 5: idx=NULL e len=0 — válido, retorna série vazia */
    smaug_series_str_t *tz = smaug_str_take(st, NULL, 0);
    OK(tz && tz->size == 0, "str_take(s,NULL,0) -> serie vazia");
    smaug_str_free(tz);
    smaug_str_free(st);
}

/* Reachable: out_mask=NULL nas compares f64 (f64:294/303/306/320/329/332) */
static void f64_compare_no_mask(void) {
    double arr[] = {1.0, 2.0, 3.0};
    smaug_series_f64_t *s = smaug_f64_create_from_array(arr, 3);
    assert(s);
    uint8_t *r;
    /* lt sem máscara: exercita out_mask=NULL e mask=NULL branches */
    r = smaug_f64_lt(s, 2.5, NULL);
    OK(r && r[0]==1 && r[1]==1 && r[2]==0, "f64 lt sem out_mask");
    free(r);
    /* eq sem máscara */
    r = smaug_f64_eq(s, 2.0, NULL);
    OK(r && r[0]==0 && r[1]==1 && r[2]==0, "f64 eq sem out_mask");
    free(r);
    smaug_f64_free(s);

    /* f64:306/332 — ramo !VALID + mask==NULL: série com null, sem out_mask */
    smaug_series_f64_t *n = smaug_f64_create(3);
    smaug_f64_set(n, 0, 1.0); smaug_f64_set_null(n, 1); smaug_f64_set(n, 2, 3.0);
    r = smaug_f64_lt(n, 2.0, NULL);
    OK(r && r[0]==1 && r[1]==0 && r[2]==0, "f64 lt null+no_mask: ramo mask==NULL no else");
    free(r);
    r = smaug_f64_eq(n, 1.0, NULL);
    OK(r && r[0]==1 && r[1]==0 && r[2]==0, "f64 eq null+no_mask: ramo mask==NULL no else");
    free(r);
    smaug_f64_free(n);
}

/* Reachable: out_mask=NULL nas compares i64 (i64:292/299/301/304/318/325/327/330) */
static void i64_compare_no_mask(void) {
    int64_t arr[] = {1, 2, 3};
    smaug_series_i64_t *s = smaug_i64_create_from_array(arr, 3);
    assert(s);
    uint8_t *r;
    r = smaug_i64_lt(s, 3, NULL);
    OK(r && r[0]==1 && r[1]==1 && r[2]==0, "i64 lt sem out_mask");
    free(r);
    r = smaug_i64_eq(s, 2, NULL);
    OK(r && r[0]==0 && r[1]==1 && r[2]==0, "i64 eq sem out_mask");
    free(r);
    /* série com null + sem máscara: exercita VALID() false + mask==NULL (i64:299/325) */
    smaug_series_i64_t *n = smaug_i64_create(3);
    smaug_i64_set(n, 0, 1); smaug_i64_set_null(n, 1); smaug_i64_set(n, 2, 3);
    r = smaug_i64_lt(n, 2, NULL);
    OK(r && r[0]==1 && r[1]==0 && r[2]==0, "i64 lt com null sem out_mask");
    free(r);
    r = smaug_i64_eq(n, 1, NULL);
    OK(r && r[0]==1 && r[1]==0 && r[2]==0, "i64 eq com null sem out_mask");
    free(r);
    /* i64:304/330 — ramo !VALID + mask!=NULL (mask[i]=0x00 escrito):
       série com null, COM out_mask → escreve 0x00 na posição nula */
    smaug_mask_t *om = NULL;
    r = smaug_i64_lt(n, 2, &om);
    OK(r && om && om[1]==0x00, "i64 lt null+mask: mask[null]=0x00");
    free(r); free(om); om = NULL;
    r = smaug_i64_eq(n, 1, &om);
    OK(r && om && om[1]==0x00, "i64 eq null+mask: mask[null]=0x00");
    free(r); free(om);
    smaug_i64_free(s); smaug_i64_free(n);
}

/* Reachable: i64 reduções all-null e std/mean all-null (i64:224/235/241/247) */
static void i64_reduce_all_null(void) {
    smaug_series_i64_t *s = smaug_i64_create(3);  /* tudo NULL */
    /* mean all-null com ignore_na=false: } else if (!ignore_na) {  (i64:224) */
    OK(isnan(smaug_i64_mean(s, false)), "i64 mean all-null,ignore_na=false -> NaN");
    /* std all-null: isnan(mean) -> return NaN (i64:235) */
    OK(isnan(smaug_i64_std(s, true)),  "i64 std all-null -> NaN");
    OK(isnan(smaug_i64_std(s, false)), "i64 std all-null,ignore_na=false -> NaN");
    smaug_i64_free(s);

    /* i64:241 (VALID true no loop de var) + i64:247 (count>0 → divisão real):
       série mista (válidos E nulls) com ignore_na=true → mean!=NaN → entra no
       loop → VALID=true para os válidos, count>0 → toma o ramo da divisão */
    smaug_series_i64_t *m = smaug_i64_create(3);
    smaug_i64_set(m, 0, 4); smaug_i64_set_null(m, 1); smaug_i64_set(m, 2, 6);
    OK(!isnan(smaug_i64_var(m, true)),  "i64 var misto ignore_na=true: VALID+count>0");
    OK(!isnan(smaug_i64_std(m, true)),  "i64 std misto ignore_na=true");
    smaug_i64_free(m);
}

/* Reachable: f64 std all-null → count==0 (f64:245) */
static void f64_reduce_all_null_std(void) {
    smaug_series_f64_t *s = smaug_f64_create(3);  /* tudo NULL */
    OK(isnan(smaug_f64_std(s, true)),  "f64 std all-null -> NaN");
    OK(isnan(smaug_f64_var(s, true)),  "f64 var all-null -> NaN");
    smaug_f64_free(s);
}

/* Reachable: série vazia em core/str/bool (core:353, str:83, bool:15/18) */
static void empty_series_edges(void) {
    /* core:353 — i64_cow_detach com size==0: view vazia desvincula sem malloc.
       Disparado por mutação (set/append) em view de tamanho zero. */
    smaug_series_i64_t *base = smaug_i64_create(2);
    smaug_i64_set(base, 0, 1); smaug_i64_set(base, 1, 2);
    smaug_series_i64_t *vz = smaug_i64_view(base, 0, 0);  /* view vazia */
    assert(vz && vz->size == 0 && vz->meta.is_view);
    smaug_i64_append(vz, 99);   /* dispara detach com size==0 */
    OK(!vz->meta.is_view, "i64 view vazia: detach sem malloc");
    smaug_i64_free(base); smaug_i64_free(vz);

    /* str:83 — clone de série vazia (free do buffer quando size==0) */
    smaug_series_str_t *es = smaug_str_create(0);
    smaug_series_str_t *ec = smaug_str_clone(es);
    OK(ec && ec->size == 0, "str clone(vazia) -> vazia");
    smaug_str_free(es); smaug_str_free(ec);

    /* bool:15/18 — alloc_pair com n==0 (série bool vazia) */
    uint8_t  av[1]={0}; smaug_mask_t am[1]={0xFF};
    uint8_t  bv[1]={0}; smaug_mask_t bm[1]={0xFF};
    smaug_mask_t *om = NULL;
    uint8_t *r = smaug_bool_and(av, am, bv, bm, 0, &om);
    OK(r != NULL, "bool and(n=0) retorna buffer válido");
    free(r); free(om);
}

/* Reachable: str edges — out_len=NULL, len==0, first-grow, external_alloc
   (str:156/162/187/216/250/95) */
static void str_reachable_edges(void) {
    const char *arr[] = {"hello", "world", NULL};
    smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
    assert(s);

    /* str:156 — get com out_len=NULL: pos NULL → *out_len omitido */
    const char *p = smaug_str_get(s, 2, NULL);
    OK(p == NULL, "str get(null-pos, out_len=NULL) -> NULL sem crash");

    /* str:162 — get com out_len=NULL: pos válida → comprimento omitido */
    p = smaug_str_get(s, 0, NULL);
    OK(p != NULL, "str get(válida, out_len=NULL) -> ptr não-NULL");

    /* str:250 — if(len>0) memcpy: ramo len==0 em set (string vazia sobrescreve pos) */
    smaug_series_str_t *sv = smaug_str_create(2);
    smaug_str_set(sv, 0, "hello", 5);
    smaug_str_set(sv, 0, "", 0);   /* set com len==0: sem memcpy */
    size_t ol = 99;
    const char *pv = smaug_str_get(sv, 0, &ol);
    OK(pv != NULL && ol == 0, "str set len==0: string vazia");
    smaug_str_free(sv);

    /* str:297 — branch 2: append(NULL, 0) não é erro (str==NULL mas len==0) */
    smaug_series_str_t *an = smaug_str_create(0);
    int rc_an = smaug_str_append(an, NULL, 0);
    OK(rc_an == 0 && an->size == 1, "str append(NULL,0) ok: string vazia nao-nula");
    smaug_str_free(an);

    smaug_str_free(s);

    /* str:187 — buffer_capacity==0 no first-grow: usa SMAUG_STR_BUFFER_INIT
       create_with_capacity(0,0) → bufcap=SMAUG_STR_BUFFER_INIT (não zero),
       então forçamos via série que começa sem buffer. Usamos o path normal
       de create(1) + set que expande. */
    smaug_series_str_t *g = smaug_str_create(1);  /* 1 elem, NULL */
    smaug_str_set(g, 0, "abcdefghijklmnopqrstuvwxyz", 26); /* força grow */
    OK(smaug_str_get(g, 0, NULL) != NULL, "str set força grow de buffer");
    smaug_str_free(g);

    /* str:216 — str_slots_reserve_one com capacity==0 já é exercitado pelo
       af_str_append_null_grow no allocfail; aqui verificamos o path de sucesso:
       clone de série com size>0 → realloc de slots. */
    smaug_series_str_t *c = smaug_str_create(1);
    smaug_str_set(c, 0, "x", 1);
    smaug_series_str_t *cl = smaug_str_clone(c);
    OK(cl && cl->size == 1, "str clone com capacity>0");
    smaug_str_free(c); smaug_str_free(cl);
}

/* Reachable: ops_str edges — série vazia, tiebreaks (ops_str:32/43/48/145/191/202) */
static void ops_str_reachable_edges(void) {
    /* série vazia: ternários size==0 em malloc (ops_str:43/48/202) */
    smaug_series_str_t *empty = smaug_str_create(0);
    smaug_mask_t *om = NULL;
    uint8_t *r = smaug_str_eq(empty, "x", 1, &om);
    OK(r != NULL, "str_eq(vazia) -> buffer válido");
    free(r); free(om);
    size_t *ai = smaug_str_argsort(empty, true);
    OK(ai != NULL, "str_argsort(vazia) -> buffer válido");
    free(ai);
    smaug_str_free(empty);

    /* ops_str:145 — take com bytes==0 (série de NULLs):
       create_with_capacity(0, bytes?bytes:1) exercita o ternário */
    smaug_series_str_t *nulls = smaug_str_create(3); /* tudo NULL */
    size_t tidx[] = {0, 1};
    smaug_series_str_t *t = smaug_str_take(nulls, tidx, 2);
    OK(t && t->size == 2, "str_take com bytes==0");
    smaug_str_free(nulls); smaug_str_free(t);

    /* ops_str:32 — tiebreak de comprimento em cmp_str (len > target_len → return 1):
       série com "ab" e "abc" — prefixo idêntico, mas "abc" é mais longa.
       No argsort, "ab" < "abc" (menor comprimento vem antes): aciona len<target e len>target */
    const char *lendiff[] = {"abc", "ab", "z"};
    smaug_series_str_t *sld = smaug_str_create_from_array(lendiff, 3);
    size_t *ldi = smaug_str_argsort(sld, true);
    OK(ldi != NULL && ldi[0]==1 && ldi[1]==0, "str_argsort: 'ab'<'abc' (len tiebreak)");
    free(ldi);
    smaug_series_str_t *ldsorted = smaug_str_sort(sld, true);
    OK(ldsorted != NULL, "str_sort com len-diff tiebreak");
    smaug_str_free(ldsorted);
    smaug_str_free(sld);

    /* ops_str:191 — tiebreak de índice quando bytes e comprimento iguais (c==0):
       strings idênticas: "a","a","b" → as duas "a" têm c==0 → ia<ib decide ordem */
    const char *dup[] = {"a", "a", "b"};
    smaug_series_str_t *sd = smaug_str_create_from_array(dup, 3);
    size_t *di = smaug_str_argsort(sd, true);
    OK(di != NULL && di[0]==0 && di[1]==1, "str_argsort tiebreak por índice (estável)");
    free(di);
    smaug_str_free(sd);
}

/* 12.23: guards ESSENCIAIS de fronteira publica.
   Auditados empiricamente (removendo o guard e chamando com NULL): estes
   SEGFAULTAM sem a protecao — nao sao defesa redundante como o
   coalesce_scalar (onde o clone(NULL) barra antes). Estavam COV-EXCL-BR com
   "o frontend valida antes", o que contradiz o CONTRATO 10: sao simbolos
   publicos exportados, alcancaveis por qualquer caller C. Cobrir os dois
   ramos do `||`: ponteiro NULL e size divergente. */
static void coalesce_guards_publicos(void) {
    double a[3] = {1, 2, 3};
    smaug_series_f64_t *f = smaug_f64_create_from_array(a, 3);
    smaug_f64_set_null(f, 1);
    double b[2] = {9, 9};
    smaug_series_f64_t *f2 = smaug_f64_create_from_array(b, 2);

    OK(smaug_f64_coalesce(NULL, f) == NULL,  "f64_coalesce(NULL, other) -> NULL");
    OK(smaug_f64_coalesce(f, NULL) == NULL,  "f64_coalesce(self, NULL) -> NULL");
    OK(smaug_f64_coalesce(f, f2)   == NULL,  "f64_coalesce size divergente -> NULL");
    smaug_series_f64_t *fr = smaug_f64_coalesce(f, f);
    OK(fr != NULL,                           "f64_coalesce valido -> serie (controle)");
    smaug_f64_free(fr); smaug_f64_free(f2); smaug_f64_free(f);

    int64_t ia[3] = {1, 2, 3};
    smaug_series_i64_t *i = smaug_i64_create_from_array(ia, 3);
    smaug_i64_set_null(i, 1);
    int64_t ib[2] = {9, 9};
    smaug_series_i64_t *i2 = smaug_i64_create_from_array(ib, 2);

    OK(smaug_i64_coalesce(NULL, i) == NULL,  "i64_coalesce(NULL, other) -> NULL");
    OK(smaug_i64_coalesce(i, NULL) == NULL,  "i64_coalesce(self, NULL) -> NULL");
    OK(smaug_i64_coalesce(i, i2)   == NULL,  "i64_coalesce size divergente -> NULL");
    smaug_series_i64_t *ir = smaug_i64_coalesce(i, i);
    OK(ir != NULL,                           "i64_coalesce valido -> serie (controle)");
    smaug_i64_free(ir); smaug_i64_free(i2); smaug_i64_free(i);
}

/* 12.24: os guards de `select` sao ESSENCIAIS, nao redundantes.
   A auditoria do 12.18 os classificou errado — o script removia so a primeira
   linha do guard (`if (...)`), deixando o `return NULL;` orfao, que passava a
   executar SEMPRE: a funcao virava `return NULL` incondicional e nunca crashava.
   Artefato do harness, nao do codigo. Removendo o guard INTEIRO: SIGSEGV nos 4.
   O corpo toca os tres ponteiros direto — create(a->size), cond->null_mask no
   laco, e `b` quando cond[i] e' false. Cobrimos os 5 ramos do `||`. */
static void select_guards_publicos(void) {
    double a[3] = {1, 2, 3};
    smaug_series_f64_t *f  = smaug_f64_create_from_array(a, 3);
    smaug_series_f64_t *f2 = smaug_f64_create_from_array(a, 3);
    double s2[2] = {9, 9};
    smaug_series_f64_t *fd = smaug_f64_create_from_array(s2, 2);   /* size divergente */
    /* cond com um FALSE no meio: o laco PRECISA tocar `b` */
    smaug_series_bool_t *cb = smaug_bool_create(3);
    smaug_bool_set(cb, 0, 1); smaug_bool_set(cb, 1, 0); smaug_bool_set(cb, 2, 1);
    smaug_series_bool_t *cbd = smaug_bool_create(2);               /* size divergente */

    OK(smaug_f64_select(NULL, f, f2) == NULL, "f64_select(cond NULL) -> NULL");
    OK(smaug_f64_select(cb, NULL, f2) == NULL, "f64_select(a NULL) -> NULL");
    OK(smaug_f64_select(cb, f, NULL) == NULL, "f64_select(b NULL) -> NULL");
    OK(smaug_f64_select(cbd, f, f2) == NULL,  "f64_select(cond->size != a->size) -> NULL");
    OK(smaug_f64_select(cb, f, fd) == NULL,   "f64_select(a->size != b->size) -> NULL");
    smaug_series_f64_t *fr = smaug_f64_select(cb, f, f2);
    OK(fr != NULL && fr->size == 3,           "f64_select valido -> serie (controle)");
    smaug_f64_free(fr);
    smaug_f64_free(fd); smaug_f64_free(f2); smaug_f64_free(f);

    int64_t ia[3] = {1, 2, 3};
    smaug_series_i64_t *i  = smaug_i64_create_from_array(ia, 3);
    smaug_series_i64_t *i2 = smaug_i64_create_from_array(ia, 3);
    int64_t id[2] = {9, 9};
    smaug_series_i64_t *idv = smaug_i64_create_from_array(id, 2);

    OK(smaug_i64_select(NULL, i, i2) == NULL, "i64_select(cond NULL) -> NULL");
    OK(smaug_i64_select(cb, NULL, i2) == NULL, "i64_select(a NULL) -> NULL");
    OK(smaug_i64_select(cb, i, NULL) == NULL, "i64_select(b NULL) -> NULL");
    OK(smaug_i64_select(cbd, i, i2) == NULL,  "i64_select(cond->size != a->size) -> NULL");
    OK(smaug_i64_select(cb, i, idv) == NULL,  "i64_select(a->size != b->size) -> NULL");
    smaug_series_i64_t *ir2 = smaug_i64_select(cb, i, i2);
    OK(ir2 != NULL && ir2->size == 3,         "i64_select valido -> serie (controle)");
    smaug_i64_free(ir2);
    smaug_i64_free(idv); smaug_i64_free(i2); smaug_i64_free(i);
    smaug_bool_free(cbd); smaug_bool_free(cb);
}

int main(void) {
    f64_arith_null_prop();
    i64_arith_null_prop();
    numeric_guard_sweep();
    f64_reduce_na_false();
    f64_reduce_empty();
    f64_reduce_all_null();
    f64_reduce_all_null_std();
    f64_binop_guards();
    f64_div_zero_and_null();
    f64_scalar_edge();
    f64_compare_edge();
    f64_compare_no_mask();
    f64_sort_edge();
    f64_null_guard_sort();
    f64_take_filter_edge();

    i64_reduce_na_false();
    i64_reduce_empty();
    i64_reduce_all_null();
    i64_reduce_null_and_empty();
    i64_binop_guards();
    i64_null_guard_binop();
    i64_div_zero();
    i64_scalar_compare_sort_edge();
    i64_null_guard_sort();
    i64_compare_no_mask();

    str_null_guard_set();
    ops_str_null_guards();
    empty_series_edges();
    str_reachable_edges();
    ops_str_reachable_edges();

    mutation_status_contract();
    get_status_contract();

    coalesce_guards_publicos();
    select_guards_publicos();

    view_overflow_boundary();
    nan_in_compare();
    i64_overflow_behavior();

    printf("PASS: ops edge (%ld checks)\n", n_checks);
    return 0;
}
