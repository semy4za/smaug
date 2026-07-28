/* tests/test_string.c
 *
 * Testes do tipo string (offset-based). Construído peça a peça junto com
 * src/smaug_str.c. Rode sob Valgrind — o tipo string faz gerência manual
 * de buffer de tamanho variável, então ausência de leak/erro é essencial.
 *
 * Peça 1: lifecycle (create / create_with_capacity / free).
 */

#include "../include/smaug_string.h"
#include "../include/smaug_core.h"   /* 12.24: str_select recebe smaug_series_bool_t */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int n_checks = 0;
#define OK(cond, msg) do { if (!(cond)) { \
    fprintf(stderr, "FALHOU: %s\n", msg); return 1; } n_checks++; } while (0)

int main(void) {
    /* create(0): série vazia, sem null_mask, buffer mínimo */
    {
        smaug_series_str_t *s = smaug_str_create(0);
        OK(s != NULL, "create(0) nao-nulo");
        OK(s->size == 0, "create(0) size=0");
        OK(s->offsets != NULL, "create(0) offsets alocado (size+1=1)");
        OK(s->offsets[0] == 0, "create(0) offsets[0]=0");
        OK(s->buffer_len == 0, "create(0) buffer_len=0");
        OK(strcmp(s->meta.dtype, "string") == 0, "create(0) dtype=string");
        smaug_str_free(s);
    }

    /* create(3): tres strings, todas NULL inicialmente */
    {
        smaug_series_str_t *s = smaug_str_create(3);
        OK(s != NULL, "create(3) nao-nulo");
        OK(s->size == 3, "create(3) size=3");
        OK(s->null_mask != NULL, "create(3) null_mask alocado");
        /* todos os 3 elementos comecam NULL */
        OK(s->null_mask[0] == 0x00 && s->null_mask[1] == 0x00 && s->null_mask[2] == 0x00,
           "create(3) todos NULL");
        /* offsets: size+1 = 4 marcadores, todos 0 */
        OK(s->offsets[0] == 0 && s->offsets[3] == 0, "create(3) offsets zerados");
        smaug_str_free(s);
    }

    /* create_with_capacity: reserva buffer maior */
    {
        smaug_series_str_t *s = smaug_str_create_with_capacity(2, 256);
        OK(s != NULL, "create_with_capacity nao-nulo");
        OK(s->size == 2, "create_with_capacity size=2");
        OK(s->buffer_capacity == 256, "create_with_capacity buffer reservado");
        smaug_str_free(s);
    }

    /* free(NULL) nao deve crashar */
    smaug_str_free(NULL);
    n_checks++;

    /* ---- Peça 2: from_array, get, is_null ---- */

    /* construção em lote com os 4 casos: válida, vazia, NULL, válida longa */
    {
        const char *arr[] = {"SP", "", NULL, "Minas"};
        smaug_series_str_t *s = smaug_str_create_from_array(arr, 4);
        OK(s != NULL, "from_array nao-nulo");
        OK(s->size == 4, "from_array size=4");
        OK(s->buffer_len == 7, "from_array buffer_len=7 (SP+Minas)");

        size_t len;
        const char *p;

        /* [0] "SP": válida, len 2 */
        p = smaug_str_get(s, 0, &len);
        OK(p != NULL && len == 2 && memcmp(p, "SP", 2) == 0, "get [0]=SP");
        OK(!smaug_str_is_null(s, 0), "is_null [0]=false");

        /* [1] "": VÁLIDA e vazia (distinta de NULL) */
        p = smaug_str_get(s, 1, &len);
        OK(p != NULL && len == 0, "get [1]='' (ponteiro valido, len 0)");
        OK(!smaug_str_is_null(s, 1), "is_null ['']=false (vazia != NULL)");

        /* [2] NULL */
        p = smaug_str_get(s, 2, &len);
        OK(p == NULL && len == 0, "get [2]=NULL (ponteiro nulo, len 0)");
        OK(smaug_str_is_null(s, 2), "is_null [NULL]=true");

        /* [3] "Minas": válida, len 5 */
        p = smaug_str_get(s, 3, &len);
        OK(p != NULL && len == 5 && memcmp(p, "Minas", 5) == 0, "get [3]=Minas");

        /* offsets coerentes: [0,2,2,2,7] */
        OK(s->offsets[0] == 0 && s->offsets[1] == 2 && s->offsets[2] == 2
           && s->offsets[3] == 2 && s->offsets[4] == 7, "offsets coerentes");

        /* acesso fora dos limites: get NULL, is_null true */
        p = smaug_str_get(s, 99, &len);
        OK(p == NULL && len == 0, "get fora-limites = NULL");
        OK(smaug_str_is_null(s, 99), "is_null fora-limites = true");

        smaug_str_free(s);
    }

    /* from_array(NULL) -> NULL */
    OK(smaug_str_create_from_array(NULL, 3) == NULL, "from_array(NULL)=NULL");

    /* array vazio (len 0) -> série válida vazia */
    {
        const char *empty[] = { NULL };
        smaug_series_str_t *s = smaug_str_create_from_array(empty, 0);
        OK(s != NULL && s->size == 0, "from_array len 0 = serie vazia");
        smaug_str_free(s);
    }

    /* ---- Peça 3: set (3 casos), set_null, append ---- */

    /* helper inline de leitura para asserts */
    #define STR_EQ(s, i, txt) ({ size_t _l; const char *_p = smaug_str_get((s),(i),&_l); \
        _p != NULL && _l == strlen(txt) && memcmp(_p, txt, _l) == 0; })

    {
        const char *arr[] = {"SP", "RJ", "MG"};
        smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);

        /* IGUAL: SP->RJ (mesmo tamanho, in-place) */
        OK(smaug_str_set(s, 0, "RJ", 2) == SMG_OK, "set igual ok");
        OK(STR_EQ(s, 0, "RJ"), "set igual valor");
        OK(STR_EQ(s, 1, "RJ") && STR_EQ(s, 2, "MG"), "set igual nao afeta vizinhos");

        /* MAIOR: idx0 RJ->Bahia (2->5), desloca o rabo */
        OK(smaug_str_set(s, 0, "Bahia", 5) == SMG_OK, "set maior ok");
        OK(STR_EQ(s, 0, "Bahia"), "set maior valor");
        OK(STR_EQ(s, 1, "RJ") && STR_EQ(s, 2, "MG"), "set maior preserva rabo");

        /* MENOR: idx0 Bahia->AC (5->2), fecha o buraco */
        OK(smaug_str_set(s, 0, "AC", 2) == SMG_OK, "set menor ok");
        OK(STR_EQ(s, 0, "AC"), "set menor valor");
        OK(STR_EQ(s, 1, "RJ") && STR_EQ(s, 2, "MG"), "set menor preserva rabo");

        /* MAIOR no meio: idx1 RJ->Parana (2->6) */
        OK(smaug_str_set(s, 1, "Parana", 6) == SMG_OK, "set meio maior ok");
        OK(STR_EQ(s, 0, "AC") && STR_EQ(s, 1, "Parana") && STR_EQ(s, 2, "MG"),
           "set meio preserva ambas as pontas");

        /* set_null no meio: zera idx1, preserva vizinhos */
        smaug_str_set_null(s, 1);
        OK(smaug_str_is_null(s, 1), "set_null marca NULL");
        OK(STR_EQ(s, 0, "AC") && STR_EQ(s, 2, "MG"), "set_null preserva vizinhos");

        /* set sobre NULL: torna válido */
        OK(smaug_str_set(s, 1, "novo", 4) == SMG_OK, "set sobre NULL ok");
        OK(!smaug_str_is_null(s, 1) && STR_EQ(s, 1, "novo"), "set sobre NULL torna valido");

        /* set para "" (vazia, válida) */
        OK(smaug_str_set(s, 0, "", 0) == SMG_OK, "set vazia ok");
        { size_t l; const char *p = smaug_str_get(s, 0, &l);
          OK(p != NULL && l == 0 && !smaug_str_is_null(s, 0), "set '' = vazia valida"); }

        /* set fora dos limites: erro */
        OK(smaug_str_set(s, 99, "x", 1) == SMG_ERR_OOB, "set fora-limites = erro");

        /* contrato do enum (str_set): ARGUMENT em ponteiro nulo da serie e em
           str==NULL com len>0; mas str==NULL com len==0 e valido (string vazia). */
        OK(smaug_str_set(NULL, 0, "x", 1) == SMG_ERR_ARGUMENT, "set serie NULL = ARGUMENT");
        OK(smaug_str_set(s, 0, NULL, 5)   == SMG_ERR_ARGUMENT, "set str NULL com len>0 = ARGUMENT");
        OK(smaug_str_set(s, 0, NULL, 0)   == SMG_OK,           "set str NULL com len==0 = ok (vazia)");
        OK(STR_EQ(s, 0, ""), "set str NULL/len0 deixa vazia");

        /* contrato do enum (str_set_null): OK em idx valido, OOB, ARGUMENT */
        OK(smaug_str_set_null(s, 2)    == SMG_OK,           "set_null idx valido = ok");
        OK(smaug_str_is_null(s, 2),                          "set_null idx valido marca NULL");
        OK(smaug_str_set_null(s, 99)   == SMG_ERR_OOB,      "set_null fora-limites = OOB");
        OK(smaug_str_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "set_null serie NULL = ARGUMENT");

        smaug_str_free(s);
    }

    /* append sequencial numa série vazia (incl. NULL no meio) */
    {
        smaug_series_str_t *a = smaug_str_create(0);
        OK(smaug_str_append(a, "um", 2) == 0, "append 1 ok");
        OK(smaug_str_append(a, "dois", 4) == 0, "append 2 ok");
        OK(smaug_str_append_null(a) == 0, "append_null ok");
        OK(smaug_str_append(a, "quatro", 6) == 0, "append 3 ok");
        OK(a->size == 4, "append size=4");
        OK(STR_EQ(a, 0, "um") && STR_EQ(a, 1, "dois") && STR_EQ(a, 3, "quatro"),
           "append valores");
        OK(smaug_str_is_null(a, 2), "append_null no meio = NULL");
        OK(smaug_str_count_nonnull(a) == 3, "count_nonnull apos append");
        smaug_str_free(a);
    }

    /* ---- clone: cópia profunda independente ---- */
    {
        const char *arr[] = {"alpha", NULL, "gamma"};
        smaug_series_str_t *orig = smaug_str_create_from_array(arr, 3);
        smaug_series_str_t *c = smaug_str_clone(orig);
        OK(c != NULL, "clone nao-nulo");
        OK(c->size == 3, "clone size");
        OK(STR_EQ(c, 0, "alpha") && smaug_str_is_null(c, 1) && STR_EQ(c, 2, "gamma"),
           "clone copia conteudo (incl. NULL)");

        /* INDEPENDÊNCIA: mutar o clone NÃO afeta o original */
        smaug_str_set(c, 0, "MUDADO", 6);
        OK(STR_EQ(c, 0, "MUDADO"), "clone mutavel");
        OK(STR_EQ(orig, 0, "alpha"), "clone independente (original intacto)");

        /* e o inverso: mutar o original não afeta o clone */
        smaug_str_set(orig, 2, "XX", 2);
        OK(STR_EQ(c, 2, "gamma"), "original independente (clone intacto)");

        smaug_str_free(orig);
        smaug_str_free(c);
    }

    /* ---- Comparações (eq/lt/gt) contra string-alvo ---- */
    {
        const char *arr[] = {"SP", "RJ", NULL, "MG", "SP", ""};
        smaug_series_str_t *s = smaug_str_create_from_array(arr, 6);
        smaug_mask_t *m = NULL;
        uint8_t *r;

        /* eq "SP": 1 0 N 0 1 0 */
        r = smaug_str_eq(s, "SP", 2, &m);
        OK(r && m, "eq retorna result+mask");
        OK(r[0]==1 && r[1]==0 && r[3]==0 && r[4]==1 && r[5]==0, "eq valores");
        OK(m[2]==0x00 && m[0]==0xFF, "eq NULL->mascara 0x00, valido->0xFF");
        free(r); free(m); m=NULL;

        /* eq "" : só a vazia (idx5) */
        r = smaug_str_eq(s, "", 0, &m);
        OK(r[5]==1 && r[0]==0 && r[1]==0, "eq '' casa so a vazia");
        OK(m[5]==0xFF, "vazia e valida (compara normal)");
        free(r); free(m); m=NULL;

        /* lt "RJ": MG e '' antes; SP depois -> 0 0 N 1 0 1 */
        r = smaug_str_lt(s, "RJ", 2, &m);
        OK(r[3]==1 && r[5]==1 && r[0]==0 && r[1]==0 && r[4]==0, "lt lexicografico");
        OK(m[2]==0x00, "lt NULL->mascara 0");
        free(r); free(m); m=NULL;

        /* gt "RJ": SP depois -> 1 0 N 0 1 0 */
        r = smaug_str_gt(s, "RJ", 2, &m);
        OK(r[0]==1 && r[4]==1 && r[1]==0 && r[3]==0, "gt lexicografico");
        free(r); free(m); m=NULL;

        /* desempate por comprimento: "MG" < "MGA" (prefixo igual, mais curta antes) */
        r = smaug_str_lt(s, "MGA", 3, &m);
        OK(r[3]==1, "lt desempata por comprimento (MG < MGA)");
        free(r); free(m); m=NULL;

        /* le/ge: cobrem os cases STR_CMP_LE/GE do switch. s = [SP,RJ,N,MG,SP,""] */
        r = smaug_str_le(s, "RJ", 2, &m);   /* <= RJ: RJ(1), MG(3), ""(5); SP nao */
        OK(r[1]==1 && r[3]==1 && r[5]==1 && r[0]==0 && r[4]==0, "le lexicografico");
        OK(m && m[2]==0x00, "le NULL -> mascara 0");
        free(r); free(m); m=NULL;

        r = smaug_str_ge(s, "RJ", 2, &m);   /* >= RJ: SP(0), RJ(1), SP(4); MG e "" nao */
        OK(r[0]==1 && r[1]==1 && r[4]==1 && r[3]==0 && r[5]==0, "ge lexicografico");
        free(r); free(m); m=NULL;

        r = smaug_str_le(s, "RJ", 2, NULL);  /* sem out_mask */
        OK(r && r[1]==1, "le sem out_mask funciona");
        free(r);

        /* eq sem out_mask (NULL) nao deve crashar */
        r = smaug_str_eq(s, "SP", 2, NULL);
        OK(r && r[0]==1, "eq sem out_mask funciona");
        free(r);

        smaug_str_free(s);
    }

    /* ---- Seleção: filter e take ---- */
    {
        const char *arr[] = {"SP", "RJ", NULL, "MG", "SP"};
        smaug_series_str_t *s = smaug_str_create_from_array(arr, 5);

        /* filter por máscara {1,0,0,0,1} -> SP SP */
        uint8_t m1[] = {1,0,0,0,1};
        smaug_series_str_t *f = smaug_str_filter(s, m1);
        OK(f && f->size == 2, "filter conta certo");
        OK(STR_EQ(f, 0, "SP") && STR_EQ(f, 1, "SP"), "filter valores");
        smaug_str_free(f);

        /* filter incluindo NULL {0,0,1,1,0} -> [NULL] MG */
        uint8_t m2[] = {0,0,1,1,0};
        f = smaug_str_filter(s, m2);
        OK(f->size == 2 && smaug_str_is_null(f, 0) && STR_EQ(f, 1, "MG"),
           "filter preserva NULL");
        smaug_str_free(f);

        /* filter vazio */
        uint8_t mz[] = {0,0,0,0,0};
        f = smaug_str_filter(s, mz);
        OK(f && f->size == 0, "filter vazio = serie vazia");
        smaug_str_free(f);

        /* take reordenado {3,0,2} -> MG SP NULL */
        size_t idx[] = {3,0,2};
        smaug_series_str_t *t = smaug_str_take(s, idx, 3);
        OK(t && t->size == 3, "take conta certo");
        OK(STR_EQ(t, 0, "MG") && STR_EQ(t, 1, "SP") && smaug_str_is_null(t, 2),
           "take reordena e preserva NULL");
        smaug_str_free(t);

        /* take fora dos limites -> NULL */
        size_t bad[] = {99};
        OK(smaug_str_take(s, bad, 1) == NULL, "take fora-limites = NULL");

        smaug_str_free(s);
    }

    /* ---- Ordenação: sort e argsort ---- */
    {
        const char *arr[] = {"MG", "AC", "SP", "BA", "AC"};
        smaug_series_str_t *s = smaug_str_create_from_array(arr, 5);

        /* sort ascendente */
        smaug_series_str_t *asc = smaug_str_sort(s, true);
        OK(asc && asc->size == 5, "sort asc conta");
        OK(STR_EQ(asc,0,"AC") && STR_EQ(asc,1,"AC") && STR_EQ(asc,2,"BA")
           && STR_EQ(asc,3,"MG") && STR_EQ(asc,4,"SP"), "sort asc ordem");
        smaug_str_free(asc);

        /* sort descendente */
        smaug_series_str_t *desc = smaug_str_sort(s, false);
        OK(STR_EQ(desc,0,"SP") && STR_EQ(desc,4,"AC"), "sort desc ordem");
        smaug_str_free(desc);

        /* argsort: permutação estável (os dois AC em ordem original: 1 antes de 4) */
        size_t *ix = smaug_str_argsort(s, true);
        OK(ix && ix[0]==1 && ix[1]==4 && ix[2]==3 && ix[3]==0 && ix[4]==2,
           "argsort permutacao estavel");
        free(ix);

        smaug_str_free(s);
    }

    /* sort com vazia (vem primeiro) */
    {
        const char *arr[] = {"b", "", "a"};
        smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
        smaug_series_str_t *r = smaug_str_sort(s, true);
        { size_t l; smaug_str_get(r,0,&l); OK(l==0, "sort: vazia vem primeiro"); }
        OK(STR_EQ(r,1,"a") && STR_EQ(r,2,"b"), "sort com vazia");
        smaug_str_free(s); smaug_str_free(r);
    }

    /* sort/argsort RECUSAM NULL */
    {
        const char *arr[] = {"x", NULL, "a"};
        smaug_series_str_t *s = smaug_str_create_from_array(arr, 3);
        OK(smaug_str_sort(s, true) == NULL, "sort recusa NULL");
        OK(smaug_str_argsort(s, true) == NULL, "argsort recusa NULL");
        smaug_str_free(s);
    }

    /* ==================================================================
       FASE 8 / frente A1 (string) — varredura de input inválido.
       Guards de ponteiro NULL e sub-args (str/target NULL com len>0, idx/mask
       NULL) ainda não exercitados. set/set_null e from_array(NULL) já cobertos;
       argsort/sort aqui é o PONTEIRO NULL (distinto da série-com-null já testada).
       ================================================================== */
    {
        smaug_series_str_t *gs = smaug_str_create(2);
        smaug_str_set(gs, 0, "AB", 2);
        smaug_str_set(gs, 1, "CD", 2);
        size_t  glen = 0;
        uint8_t gmask[1] = { 1 };
        size_t  gidx[1]  = { 0 };

        OK(smaug_str_clone(NULL) == NULL,            "str clone(NULL) -> NULL");
        OK(smaug_str_get(NULL, 0, &glen) == NULL,    "str get(serie NULL) -> NULL");
        OK(smaug_str_get(gs, 9, &glen) == NULL,      "str get(OOB) -> NULL");
        OK(smaug_str_is_null(NULL, 0) == true,       "str is_null(serie NULL) -> true");
        OK(smaug_str_is_null(gs, 9) == true,         "str is_null(OOB) -> true");
        OK(smaug_str_append(NULL, "x", 1) == -1,     "str append(serie NULL) -> -1");
        OK(smaug_str_append(gs, NULL, 5) == -1,      "str append(str NULL, len>0) -> -1");
        OK(smaug_str_append_null(NULL) == -1,        "str append_null(NULL) -> -1");
        OK(smaug_str_count_nonnull(NULL) == 0,       "str count_nonnull(NULL) -> 0");

        OK(smaug_str_eq(NULL, "x", 1, NULL) == NULL, "str eq(serie NULL) -> NULL");
        OK(smaug_str_eq(gs, NULL, 5, NULL) == NULL,  "str eq(target NULL, len>0) -> NULL");
        OK(smaug_str_lt(NULL, "x", 1, NULL) == NULL, "str lt(serie NULL) -> NULL");
        OK(smaug_str_gt(NULL, "x", 1, NULL) == NULL, "str gt(serie NULL) -> NULL");

        /* between (10.2 fatia 2): guarda nos DOIS alvos, nao so num */
        OK(smaug_str_between(NULL, "a", 1, "z", 1, true, true, NULL) == NULL,
           "str between(serie NULL) -> NULL");
        OK(smaug_str_between(gs, NULL, 5, "z", 1, true, true, NULL) == NULL,
           "str between(lo NULL, len>0) -> NULL");
        OK(smaug_str_between(gs, "a", 1, NULL, 5, true, true, NULL) == NULL,
           "str between(hi NULL, len>0) -> NULL");

        /* out_mask == NULL: o ramo que o frontend nunca exercita (ele sempre
           pede a mascara), e que por isso escapa da cobertura se nao for
           testado aqui. Mesma licao da fatia 1. */
        uint8_t *bnm = smaug_str_between(gs, "A", 1, "z", 1, true, true, NULL);
        OK(bnm != NULL, "str between sem out_mask");
        free(bnm);

        /* alvo NULL com len 0 e string VAZIA, nao chamada invalida: a guarda e
           `!lo && lo_len > 0`, entao este caso passa e compara normalmente.
           Sem ele, a segunda condicao da guarda nunca e avaliada (MC/DC). */
        uint8_t *bz = smaug_str_between(gs, NULL, 0, "zzz", 3, true, true, NULL);
        OK(bz != NULL, "str between(lo NULL, len 0) trata como vazia");
        free(bz);
        bz = smaug_str_between(gs, "", 0, NULL, 0, true, true, NULL);
        OK(bz != NULL, "str between(hi NULL, len 0) trata como vazia");
        free(bz);

        /* serie vazia: exercita o ramo `size ? size : 1` do malloc -- e precisa
           pedir a mascara, senao o malloc dela nao roda */
        smaug_series_str_t *vazia = smaug_str_create(0);
        OK(vazia != NULL, "str create(0) para between");
        smaug_mask_t *mv = NULL;
        uint8_t *bv = smaug_str_between(vazia, "a", 1, "z", 1, true, true, &mv);
        OK(bv != NULL, "str between em serie vazia nao estoura");
        free(bv); free(mv);
        smaug_str_free(vazia);

        /* elemento NULL com out_mask == NULL: exercita o `if (mask)` falso
           dentro do ramo de nulo, que o frontend nunca alcanca */
        smaug_series_str_t *cn = smaug_str_create(2);
        OK(cn != NULL, "str create(2) para between com nulo");
        smaug_str_set(cn, 0, "abc", 3);
        smaug_str_set_null(cn, 1);
        uint8_t *bn = smaug_str_between(cn, "a", 1, "z", 1, true, true, NULL);
        OK(bn != NULL && bn[1] == 0, "str between nulo sem out_mask");
        free(bn);
        smaug_str_free(cn);

        OK(smaug_str_filter(NULL, gmask) == NULL,    "str filter(serie NULL) -> NULL");
        OK(smaug_str_filter(gs, NULL) == NULL,       "str filter(mask NULL) -> NULL");
        OK(smaug_str_take(NULL, gidx, 1) == NULL,    "str take(serie NULL) -> NULL");
        OK(smaug_str_take(gs, NULL, 1) == NULL,      "str take(idx NULL, len>0) -> NULL");

        OK(smaug_str_argsort(NULL, true) == NULL,    "str argsort(serie NULL) -> NULL");
        OK(smaug_str_sort(NULL, true) == NULL,       "str sort(serie NULL) -> NULL");

        smaug_str_free(gs);
    }

    /* ==================================================================
       12.23: guards ESSENCIAIS de fronteira publica (CONTRATO 10).
       Auditado empiricamente: sem estes guards, ambos SEGFAULTAM — o
       coalesce_scalar mede o buffer tocando self->size direto (nao clona
       antes, ao contrario dos irmaos f64/i64/dt, onde o clone(NULL) barra),
       e o coalesce toca other->offsets no laco. Estavam COV-EXCL-BR com
       "o frontend valida antes": sao simbolos publicos exportados.
       ================================================================== */
    {
        const char *arr[] = {"a", NULL, "c"};
        smaug_series_str_t *s  = smaug_str_create_from_array(arr, 3);
        const char *arr2[] = {"x", "y"};
        smaug_series_str_t *s2 = smaug_str_create_from_array(arr2, 2);

        /* coalesce_scalar: os dois ramos do guard */
        OK(smaug_str_coalesce_scalar(NULL, "x", 1) == NULL,
           "str_coalesce_scalar(serie NULL) -> NULL");
        OK(smaug_str_coalesce_scalar(s, NULL, 5) == NULL,
           "str_coalesce_scalar(value NULL, len>0) -> NULL");
        smaug_series_str_t *r1 = smaug_str_coalesce_scalar(s, "Z", 1);
        OK(r1 != NULL && STR_EQ(r1, 1, "Z"),
           "str_coalesce_scalar valido preenche o NULL (controle)");
        smaug_str_free(r1);
        /* value NULL com len==0 e valido (string vazia), como no str_set */
        smaug_series_str_t *r2 = smaug_str_coalesce_scalar(s, NULL, 0);
        OK(r2 != NULL, "str_coalesce_scalar(value NULL, len==0) -> ok (vazia)");
        smaug_str_free(r2);

        /* coalesce: os tres ramos do || */
        OK(smaug_str_coalesce(NULL, s) == NULL, "str_coalesce(NULL, other) -> NULL");
        OK(smaug_str_coalesce(s, NULL) == NULL, "str_coalesce(self, NULL) -> NULL");
        OK(smaug_str_coalesce(s, s2)   == NULL, "str_coalesce size divergente -> NULL");
        smaug_series_str_t *r3 = smaug_str_coalesce(s, s);
        OK(r3 != NULL, "str_coalesce valido -> serie (controle)");
        smaug_str_free(r3);

        smaug_str_free(s2); smaug_str_free(s);
    }

    /* 12.24: str_select — guard ESSENCIAL. A auditoria do 12.18 o marcou como
       redundante por erro do harness (removia so a linha do `if`, o
       `return NULL;` orfao executava sempre). O corpo toca cond->null_mask e
       `b` no laco. 5 ramos do `||`. */
    {
        const char *av[] = {"a", "b", "c"};
        const char *bv[] = {"x", "y", "z"};
        smaug_series_str_t *sa = smaug_str_create_from_array(av, 3);
        smaug_series_str_t *sb = smaug_str_create_from_array(bv, 3);
        const char *dv[] = {"p", "q"};
        smaug_series_str_t *sd = smaug_str_create_from_array(dv, 2);
        smaug_series_bool_t *cb = smaug_bool_create(3);
        smaug_bool_set(cb, 0, 1); smaug_bool_set(cb, 1, 0); smaug_bool_set(cb, 2, 1);
        smaug_series_bool_t *cbd = smaug_bool_create(2);

        OK(smaug_str_select(NULL, sa, sb) == NULL, "str_select(cond NULL) -> NULL");
        OK(smaug_str_select(cb, NULL, sb) == NULL, "str_select(a NULL) -> NULL");
        OK(smaug_str_select(cb, sa, NULL) == NULL, "str_select(b NULL) -> NULL");
        OK(smaug_str_select(cbd, sa, sb) == NULL,  "str_select(cond->size != a->size) -> NULL");
        OK(smaug_str_select(cb, sa, sd) == NULL,   "str_select(a->size != b->size) -> NULL");
        smaug_series_str_t *sr = smaug_str_select(cb, sa, sb);
        OK(sr != NULL && STR_EQ(sr, 0, "a") && STR_EQ(sr, 1, "y") && STR_EQ(sr, 2, "c"),
           "str_select valido: cond escolhe a/b por posicao (controle)");
        smaug_str_free(sr);
        smaug_bool_free(cbd); smaug_bool_free(cb);
        smaug_str_free(sd); smaug_str_free(sb); smaug_str_free(sa);
    }

    printf("PASS: string lifecycle (%d checks)\n", n_checks);

    return 0;
}
