/* tests/test_string.c
 *
 * Testes do tipo string (offset-based). Construído peça a peça junto com
 * src/smaug_str.c. Rode sob Valgrind — o tipo string faz gerência manual
 * de buffer de tamanho variável, então ausência de leak/erro é essencial.
 *
 * Peça 1: lifecycle (create / create_with_capacity / free).
 */

#include "../include/smaug_string.h"
#include <assert.h>
#include <stdio.h>
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
        OK(smaug_str_set(s, 0, "RJ", 2) == 0, "set igual ok");
        OK(STR_EQ(s, 0, "RJ"), "set igual valor");
        OK(STR_EQ(s, 1, "RJ") && STR_EQ(s, 2, "MG"), "set igual nao afeta vizinhos");

        /* MAIOR: idx0 RJ->Bahia (2->5), desloca o rabo */
        OK(smaug_str_set(s, 0, "Bahia", 5) == 0, "set maior ok");
        OK(STR_EQ(s, 0, "Bahia"), "set maior valor");
        OK(STR_EQ(s, 1, "RJ") && STR_EQ(s, 2, "MG"), "set maior preserva rabo");

        /* MENOR: idx0 Bahia->AC (5->2), fecha o buraco */
        OK(smaug_str_set(s, 0, "AC", 2) == 0, "set menor ok");
        OK(STR_EQ(s, 0, "AC"), "set menor valor");
        OK(STR_EQ(s, 1, "RJ") && STR_EQ(s, 2, "MG"), "set menor preserva rabo");

        /* MAIOR no meio: idx1 RJ->Parana (2->6) */
        OK(smaug_str_set(s, 1, "Parana", 6) == 0, "set meio maior ok");
        OK(STR_EQ(s, 0, "AC") && STR_EQ(s, 1, "Parana") && STR_EQ(s, 2, "MG"),
           "set meio preserva ambas as pontas");

        /* set_null no meio: zera idx1, preserva vizinhos */
        smaug_str_set_null(s, 1);
        OK(smaug_str_is_null(s, 1), "set_null marca NULL");
        OK(STR_EQ(s, 0, "AC") && STR_EQ(s, 2, "MG"), "set_null preserva vizinhos");

        /* set sobre NULL: torna válido */
        OK(smaug_str_set(s, 1, "novo", 4) == 0, "set sobre NULL ok");
        OK(!smaug_str_is_null(s, 1) && STR_EQ(s, 1, "novo"), "set sobre NULL torna valido");

        /* set para "" (vazia, válida) */
        OK(smaug_str_set(s, 0, "", 0) == 0, "set vazia ok");
        { size_t l; const char *p = smaug_str_get(s, 0, &l);
          OK(p != NULL && l == 0 && !smaug_str_is_null(s, 0), "set '' = vazia valida"); }

        /* set fora dos limites: erro */
        OK(smaug_str_set(s, 99, "x", 1) == -1, "set fora-limites = erro");

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

    printf("PASS: string lifecycle (%d checks)\n", n_checks);
    return 0;
}
