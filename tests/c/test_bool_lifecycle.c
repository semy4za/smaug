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

static int n_checks = 0;
#define OK(cond, msg) do { if (!(cond)) { \
    fprintf(stderr, "FALHOU: %s\n", msg); return 1; } n_checks++; } while (0)

/* helper: cria série de "01N" (0=false, 1=true, N=null) */
static smaug_series_bool_t *mk(const char *s) {
    size_t n = 0; while (s[n]) n++;
    smaug_series_bool_t *b = smaug_bool_create(n);
    for (size_t i = 0; i < n; i++) {
        if (s[i] == 'N') smaug_bool_set_null(b, i);
        else smaug_bool_set(b, i, (uint8_t)(s[i] == '1'));
    }
    return b;
}
static char rd(smaug_series_bool_t *b, size_t i) {
    if (smaug_bool_is_null(b, i)) return 'N';
    return smaug_bool_get(b, i, NULL) ? '1' : '0';
}

/* ---- lifecycle: create, set/get, normalização, null ---- */
static int test_lifecycle(void) {
    smaug_series_bool_t *s = smaug_bool_create(3);
    OK(s != NULL, "create nao-nulo");
    OK(s->size == 3 && s->capacity == 3, "create size/capacity");
    OK(smaug_bool_is_null(s, 0), "create: tudo NULL");

    smaug_status_t st;
    OK(smaug_bool_set(s, 0, 1) == SMG_OK, "set true");
    OK(smaug_bool_set(s, 1, 0) == SMG_OK, "set false");
    OK(smaug_bool_set(s, 2, 42) == SMG_OK, "set nao-zero");
    OK(smaug_bool_get(s, 0, &st) == 1 && st == SMG_OK, "get true");
    OK(smaug_bool_get(s, 1, &st) == 0 && st == SMG_OK, "get false");
    OK(smaug_bool_get(s, 2, &st) == 1, "get: 42 normaliza p/ 1");

    OK(smaug_bool_set_null(s, 0) == SMG_OK, "set_null");
    OK(smaug_bool_is_null(s, 0), "is_null apos set_null");
    smaug_bool_get(s, 0, &st); OK(st == SMG_NULL_VALUE, "get null -> SMG_NULL_VALUE");

    smaug_bool_free(s);
    return 0;
}

/* ---- ramos defensivos: NULL, OOB ---- */
static int test_guards(void) {
    smaug_status_t st;
    OK(smaug_bool_get(NULL, 0, &st) == 0 && st == SMG_ERR_ARGUMENT, "get(NULL) -> ARGUMENT");
    OK(smaug_bool_set(NULL, 0, 1) == SMG_ERR_ARGUMENT, "set(NULL) -> ARGUMENT");
    OK(smaug_bool_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "set_null(NULL) -> ARGUMENT");
    OK(smaug_bool_is_null(NULL, 0) == true, "is_null(NULL) -> true");
    OK(smaug_bool_append(NULL, 1) == -1, "append(NULL) -> -1");
    OK(smaug_bool_append_null(NULL) == -1, "append_null(NULL) -> -1");
    OK(smaug_bool_clone(NULL) == NULL, "clone(NULL) -> NULL");

    /* status == NULL combinado com erro: cobre o ramo `if (status)` em cada
       caminho de saída do get (serie NULL, OOB, e null-value). */
    OK(smaug_bool_get(NULL, 0, NULL) == 0, "get(NULL, status=NULL) -> 0");

    smaug_series_bool_t *s = smaug_bool_create(2);
    OK(smaug_bool_set(s, 99, 1) == SMG_ERR_OOB, "set OOB");
    smaug_bool_get(s, 99, &st); OK(st == SMG_ERR_OOB, "get OOB -> OOB");
    OK(smaug_bool_get(s, 99, NULL) == 0, "get OOB (status=NULL) -> 0");  /* ramo status em OOB */
    smaug_bool_set_null(s, 0);
    smaug_bool_get(s, 0, &st); OK(st == SMG_NULL_VALUE, "get null -> NULL_VALUE");
    OK(smaug_bool_get(s, 0, NULL) == 0, "get null (status=NULL) -> 0");  /* ramo status em null */
    OK(smaug_bool_get(s, 1, NULL) == 0, "get valido (status=NULL) -> valor");  /* ramo status em SMG_OK */
    OK(smaug_bool_is_null(s, 99) == true, "is_null OOB -> true");
    OK(smaug_bool_view(s, 1, 5) == NULL, "view OOB -> NULL");
    OK(smaug_bool_set(NULL, 0, 1) == SMG_ERR_ARGUMENT, "set(NULL) idx valido");
    OK(smaug_bool_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "set_null(NULL) idx valido");
    smaug_bool_free(s);

    smaug_bool_free(NULL);   /* NULL-safe */
    OK(1, "free(NULL) seguro");

    /* with_capacity: size > capacity -> NULL (ramo :467) */
    OK(smaug_bool_create_with_capacity(5, 2) == NULL, "with_capacity size>cap -> NULL");

    /* clone de serie vazia: ramo `s->size > 0` falso (:526) */
    smaug_series_bool_t *empty = smaug_bool_create(0);
    smaug_series_bool_t *ce = smaug_bool_clone(empty);
    OK(ce != NULL && ce->size == 0, "clone de vazio -> vazio");
    smaug_bool_free(ce);

    /* view guards isolados (:538): start>size e len>size-start */
    smaug_series_bool_t *base = smaug_bool_create(3);
    OK(smaug_bool_view(base, 4, 0) == NULL, "view start>size -> NULL");
    OK(smaug_bool_view(base, 1, 5) == NULL, "view len>size-start -> NULL");
    OK(smaug_bool_view(NULL, 0, 1) == NULL, "view(NULL) -> NULL");

    /* COW detach de view vazia: ramo `s->size == 0` (:556).
       view de len 0; mutar forca detach com size 0. */
    smaug_series_bool_t *v0 = smaug_bool_view(base, 1, 0);
    OK(v0 != NULL && v0->size == 0, "view vazia criada");
    OK(smaug_bool_append(v0, 1) == 0, "append em view vazia (detach size==0)");
    OK(v0->size == 1 && !v0->meta.is_view, "view vazia detachada e cresceu");
    smaug_bool_free(v0);

    /* set_null OOB (:598) */
    OK(smaug_bool_set_null(base, 99) == SMG_ERR_OOB, "set_null OOB -> OOB");
    smaug_bool_free(base);
    smaug_bool_free(empty);
    return 0;
}

/* ---- clone independente + COW em view ---- */
static int test_clone_cow(void) {
    smaug_series_bool_t *s = mk("101");
    smaug_series_bool_t *c = smaug_bool_clone(s);
    smaug_bool_set(c, 1, 1);
    OK(smaug_bool_get(s, 1, NULL) == 0, "clone independente: original intacto");

    smaug_series_bool_t *v = smaug_bool_view(s, 1, 2);
    OK(v && v->size == 2, "view criada");
    OK(v->meta.is_view && v->meta.external_alloc, "view flags");
    smaug_bool_set(v, 0, 1);   /* materializa (COW detach) */
    OK(smaug_bool_get(s, 1, NULL) == 0, "COW: pai intacta apos set na view");
    OK(smaug_bool_get(v, 0, NULL) == 1, "COW: view tem valor novo");
    OK(!v->meta.is_view, "COW: view detached vira dona");

    /* COW via append em view */
    smaug_series_bool_t *v2 = smaug_bool_view(s, 0, 2);
    smaug_bool_append(v2, 1);
    OK(v2->size == 3, "append em view incrementa");
    OK(s->size == 3, "pai mantem tamanho original");

    smaug_bool_free(s); smaug_bool_free(c); smaug_bool_free(v); smaug_bool_free(v2);
    return 0;
}

/* ---- append dinâmico (grow) ---- */
static int test_append(void) {
    smaug_series_bool_t *a = smaug_bool_create(0);
    for (int i = 0; i < 20; i++) OK(smaug_bool_append(a, i % 2) == 0, "append");
    OK(smaug_bool_append_null(a) == 0, "append_null");
    OK(a->size == 21, "append size apos grow");
    OK(smaug_bool_get(a, 0, NULL) == 0 && smaug_bool_get(a, 1, NULL) == 1, "append valores");
    OK(smaug_bool_is_null(a, 20), "append_null preserva NA");
    smaug_bool_free(a);

    uint8_t raw[] = {0, 5, 0, 99};
    smaug_series_bool_t *fa = smaug_bool_create_from_array(raw, 4);
    OK(fa && smaug_bool_get(fa, 1, NULL) == 1 && smaug_bool_get(fa, 3, NULL) == 1,
       "from_array normaliza nao-zero");
    OK(smaug_bool_get(fa, 0, NULL) == 0, "from_array zero");
    OK(smaug_bool_create_from_array(NULL, 3) == NULL, "from_array(NULL) -> NULL");
    smaug_bool_free(fa);
    return 0;
}

/* ---- tabela-verdade Kleene completa (struct-based) ---- */
static int test_kleene(void) {
    smaug_series_bool_t *a = mk("111000NNN");
    smaug_series_bool_t *b = mk("10N10N10N");

    smaug_series_bool_t *r;
    const char *exp_and = "10N000N0N";
    const char *exp_or  = "11110N1NN";
    const char *exp_xor = "01N10NNNN";

    r = smaug_bool_series_and(a, b);
    for (int i = 0; i < 9; i++) OK(rd(r, i) == exp_and[i], "Kleene AND");
    smaug_bool_free(r);
    r = smaug_bool_series_or(a, b);
    for (int i = 0; i < 9; i++) OK(rd(r, i) == exp_or[i], "Kleene OR");
    smaug_bool_free(r);
    r = smaug_bool_series_xor(a, b);
    for (int i = 0; i < 9; i++) OK(rd(r, i) == exp_xor[i], "Kleene XOR");
    smaug_bool_free(r);
    r = smaug_bool_series_not(a);
    const char *exp_not = "000111NNN";
    for (int i = 0; i < 9; i++) OK(rd(r, i) == exp_not[i], "Kleene NOT");
    smaug_bool_free(r);

    /* mismatch e NULL — cobre cada operando do guard `!a || !b || size` (MC/DC) */
    smaug_series_bool_t *small = mk("1");
    OK(smaug_bool_series_and(a, small) == NULL, "and mismatch -> NULL");
    OK(smaug_bool_series_or(a, small)  == NULL, "or mismatch -> NULL");
    OK(smaug_bool_series_xor(a, small) == NULL, "xor mismatch -> NULL");
    OK(smaug_bool_series_and(NULL, b)  == NULL, "and(NULL, b) -> NULL");   /* !a */
    OK(smaug_bool_series_and(a, NULL)  == NULL, "and(a, NULL) -> NULL");   /* !b */
    OK(smaug_bool_series_or(NULL, b)   == NULL, "or(NULL, b) -> NULL");    /* !a */
    OK(smaug_bool_series_or(a, NULL)   == NULL, "or(a, NULL) -> NULL");    /* !b */
    OK(smaug_bool_series_xor(NULL, b)  == NULL, "xor(NULL, b) -> NULL");   /* !a */
    OK(smaug_bool_series_xor(a, NULL)  == NULL, "xor(a, NULL) -> NULL");   /* !b */
    OK(smaug_bool_series_not(NULL)     == NULL, "not(NULL) -> NULL");

    smaug_bool_free(a); smaug_bool_free(b); smaug_bool_free(small);
    return 0;
}

/* ---- agregações ---- */
static int test_agg(void) {
    smaug_series_bool_t *a = mk("111000NNN");
    OK(smaug_bool_series_count_true(a) == 3, "count_true ignora NA");
    OK(smaug_bool_count_nonnull(a) == 6, "count_nonnull");
    OK(smaug_bool_series_any(a) == true, "any com trues");

    smaug_series_bool_t *allf = mk("000");
    OK(smaug_bool_series_all(allf) == false, "all com false");
    OK(smaug_bool_series_any(allf) == false, "any sem trues");

    smaug_series_bool_t *allt = mk("111");
    OK(smaug_bool_series_all(allt) == true, "all com trues");

    smaug_series_bool_t *empty = smaug_bool_create(0);
    OK(smaug_bool_series_all(empty) == true, "all de vazio = true");
    OK(smaug_bool_series_any(empty) == false, "any de vazio = false");
    OK(smaug_bool_series_count_true(empty) == 0, "count_true de vazio = 0");

    OK(smaug_bool_series_count_true(NULL) == 0, "count_true(NULL) = 0");
    OK(smaug_bool_series_any(NULL) == false, "any(NULL) = false");
    OK(smaug_bool_series_all(NULL) == true, "all(NULL) = true");
    OK(smaug_bool_count_nonnull(NULL) == 0, "count_nonnull(NULL) = 0");

    smaug_bool_free(a); smaug_bool_free(allf); smaug_bool_free(allt); smaug_bool_free(empty);
    return 0;
}

/* ---- seleção: take, filter ---- */
static int test_selection(void) {
    smaug_series_bool_t *a = mk("101N0");
    size_t idx[] = {4, 0, 3};
    smaug_series_bool_t *t = smaug_bool_take(a, idx, 3);
    OK(t && rd(t, 0) == '0' && rd(t, 1) == '1' && rd(t, 2) == 'N', "take valores e ordem");

    size_t bad[] = {99};
    OK(smaug_bool_take(a, bad, 1) == NULL, "take OOB -> NULL");
    OK(smaug_bool_take(NULL, idx, 3) == NULL, "take(NULL) -> NULL");
    OK(smaug_bool_take(a, NULL, 3) == NULL, "take(idx NULL) -> NULL");

    uint8_t mask[] = {1, 0, 1, 1, 0};
    smaug_series_bool_t *f = smaug_bool_filter(a, mask);
    OK(f && f->size == 3, "filter conta corretos");
    OK(rd(f, 0) == '1' && rd(f, 1) == '1' && rd(f, 2) == 'N', "filter preserva valores/NA");
    OK(smaug_bool_filter(NULL, mask) == NULL, "filter(NULL) -> NULL");
    OK(smaug_bool_filter(a, NULL) == NULL, "filter(mask NULL) -> NULL");

    smaug_bool_free(a); smaug_bool_free(t); smaug_bool_free(f);
    return 0;
}

/* ---- ordenação: false<true, estável, recusa NULL ---- */
static int test_sort(void) {
    smaug_series_bool_t *a = mk("10110");
    smaug_series_bool_t *asc = smaug_bool_sort(a, true);
    OK(asc && rd(asc, 0) == '0' && rd(asc, 1) == '0', "sort asc: falses primeiro");
    OK(rd(asc, 2) == '1' && rd(asc, 4) == '1', "sort asc: trues depois");

    smaug_series_bool_t *desc = smaug_bool_sort(a, false);
    OK(desc && rd(desc, 0) == '1', "sort desc: trues primeiro");
    OK(rd(desc, 4) == '0', "sort desc: falses depois");

    /* estabilidade: argsort preserva ordem relativa de iguais */
    size_t *p = smaug_bool_argsort(a, true);  /* a = 1 0 1 1 0 -> falses idx 1,4 ; trues 0,2,3 */
    OK(p && p[0] == 1 && p[1] == 4, "argsort estavel: falses na ordem original");
    OK(p[2] == 0 && p[3] == 2 && p[4] == 3, "argsort estavel: trues na ordem original");
    smaug_free(p);

    /* recusa NULL */
    smaug_series_bool_t *withna = mk("1N0");
    OK(smaug_bool_sort(withna, true) == NULL, "sort recusa NULL");
    OK(smaug_bool_argsort(withna, true) == NULL, "argsort recusa NULL");
    OK(smaug_bool_sort(NULL, true) == NULL, "sort(NULL) -> NULL");
    OK(smaug_bool_argsort(NULL, true) == NULL, "argsort(NULL) -> NULL");

    /* série vazia: argsort/sort válidos, size 0 (cobre o ramo size==0 do malloc) */
    smaug_series_bool_t *empty = smaug_bool_create(0);
    size_t *pe = smaug_bool_argsort(empty, true);
    OK(pe != NULL, "argsort de vazio -> nao-nulo");
    smaug_free(pe);
    smaug_series_bool_t *se = smaug_bool_sort(empty, true);
    OK(se != NULL && se->size == 0, "sort de vazio -> vazio");
    smaug_bool_free(se);
    smaug_bool_free(empty);

    smaug_bool_free(a); smaug_bool_free(asc); smaug_bool_free(desc); smaug_bool_free(withna);
    return 0;
}

/* 7.4 — comparação de igualdade (único dtype que faltava) */
static int test_eq_ne(void) {
    smaug_series_bool_t *b = mk("10N");   /* true, false, NA */
    smaug_mask_t *om = NULL;

    uint8_t *r = smaug_bool_eq(b, 1, &om);          /* == true */
    OK(r != NULL && om != NULL, "eq retorna resultado e mascara");
    OK(r[0] == 1 && SMAUG_VALID(om, 0), "eq: true==true -> 1 valido");
    OK(r[1] == 0 && SMAUG_VALID(om, 1), "eq: false==true -> 0 valido");
    OK(SMAUG_NULL(om, 2), "eq: NA -> NA na out_mask");
    smaug_free(r); smaug_free(om); om = NULL;

    r = smaug_bool_ne(b, 1, &om);                   /* != true */
    OK(r[0] == 0 && r[1] == 1, "ne: inverso de eq nos validos");
    OK(SMAUG_NULL(om, 2), "ne: NA -> NA");
    smaug_free(r); smaug_free(om); om = NULL;

    r = smaug_bool_eq(b, 0, &om);                   /* == false */
    OK(r[0] == 0 && r[1] == 1, "eq false: false==false -> 1");
    OK(SMAUG_NULL(om, 2), "eq false: NA -> NA");
    smaug_free(r); smaug_free(om); om = NULL;

    /* threshold nao-normalizado (qualquer != 0 = true) */
    r = smaug_bool_eq(b, 42, &om);
    OK(r[0] == 1, "eq: threshold 42 normaliza para true");
    smaug_free(r); smaug_free(om); om = NULL;

    OK(smaug_bool_eq(NULL, 1, &om) == NULL, "eq(NULL) -> NULL");
    OK(smaug_bool_ne(NULL, 1, &om) == NULL, "ne(NULL) -> NULL");

    smaug_bool_free(b);
    return 0;
}

/* ---- coalesce_scalar: preenche nulos com value (0/1), mantém não-nulos ---- */
static int test_coalesce(void) {
    /* fill com false: NA -> 0, validos inalterados */
    smaug_series_bool_t *b = mk("01N1");
    smaug_series_bool_t *r = smaug_bool_coalesce_scalar(b, 0);
    OK(r != NULL, "coalesce retorna clone");
    OK(r != b, "coalesce nao muta a origem");
    OK(rd(r, 0) == '0' && rd(r, 1) == '1' && rd(r, 3) == '1', "coalesce: validos inalterados");
    OK(rd(r, 2) == '0', "coalesce false: NA -> false");
    OK(smaug_bool_count_nonnull(r) == 4, "coalesce: sem nulos restantes");
    OK(rd(b, 2) == 'N', "origem preservada (NA intacto)");
    smaug_bool_free(r);

    /* fill com true */
    r = smaug_bool_coalesce_scalar(b, 1);
    OK(rd(r, 2) == '1', "coalesce true: NA -> true");
    OK(rd(r, 0) == '0' && rd(r, 1) == '1', "coalesce true: validos inalterados");
    smaug_bool_free(r);

    /* value nao-normalizado: qualquer != 0 vira 1 */
    r = smaug_bool_coalesce_scalar(b, 42);
    OK(rd(r, 2) == '1', "coalesce: value 42 normaliza para true");
    smaug_bool_free(r);
    smaug_bool_free(b);

    /* série sem NA: no-op semântico */
    b = mk("010");
    r = smaug_bool_coalesce_scalar(b, 1);
    OK(rd(r, 0) == '0' && rd(r, 1) == '1' && rd(r, 2) == '0', "coalesce sem NA: inalterada");
    smaug_bool_free(r); smaug_bool_free(b);

    /* série vazia */
    b = smaug_bool_create(0);
    r = smaug_bool_coalesce_scalar(b, 1);
    OK(r != NULL && r->size == 0, "coalesce de vazia -> vazia");
    smaug_bool_free(r); smaug_bool_free(b);

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
    if (test_eq_ne())      return 1;
    if (test_coalesce())   return 1;
    printf("PASS: bool lifecycle (%d checks)\n", n_checks);
    return 0;
}
