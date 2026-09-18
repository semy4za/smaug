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

static int passed_checks = 0;
#define OK(condition, message) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU: %s\n", message); return 1; } passed_checks++; } while (0)

int main(void) {
    /* create(0): série vazia, sem null_mask, buffer mínimo */
    {
        smaug_series_str_t *source_series = smaug_str_create(0);
        OK(source_series != NULL, "create(0) nao-nulo");
        OK(source_series->size == 0, "create(0) size=0");
        OK(source_series->offsets != NULL, "create(0) offsets alocado (size+1=1)");
        OK(source_series->offsets[0] == 0, "create(0) offsets[0]=0");
        OK(source_series->buffer_len == 0, "create(0) buffer_len=0");
        OK(strcmp(source_series->meta.dtype, "string") == 0, "create(0) dtype=string");
        smaug_str_free(source_series);
    }

    /* create(3): tres strings, todas NULL inicialmente */
    {
        smaug_series_str_t *source_series = smaug_str_create(3);
        OK(source_series != NULL, "create(3) nao-nulo");
        OK(source_series->size == 3, "create(3) size=3");
        OK(source_series->null_mask != NULL, "create(3) null_mask alocado");
        /* todos os 3 elementos comecam NULL */
        OK(source_series->null_mask[0] == 0x00 && source_series->null_mask[1] == 0x00 && source_series->null_mask[2] == 0x00,
           "create(3) todos NULL");
        /* offsets: size+1 = 4 marcadores, todos 0 */
        OK(source_series->offsets[0] == 0 && source_series->offsets[3] == 0, "create(3) offsets zerados");
        smaug_str_free(source_series);
    }

    /* create_with_capacity: reserva buffer maior */
    {
        smaug_series_str_t *source_series = smaug_str_create_with_capacity(2, 256);
        OK(source_series != NULL, "create_with_capacity nao-nulo");
        OK(source_series->size == 2, "create_with_capacity size=2");
        OK(source_series->buffer_capacity == 256, "create_with_capacity buffer reservado");
        smaug_str_free(source_series);
    }

    /* free(NULL) nao deve crashar */
    smaug_str_free(NULL);
    passed_checks++;

    /* ---- Peça 2: from_array, get, is_null ---- */

    /* construção em lote com os 4 casos: válida, vazia, NULL, válida longa */
    {
        const char *source_values[] = {"SP", "", NULL, "Minas"};
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 4);
        OK(source_series != NULL, "from_array nao-nulo");
        OK(source_series->size == 4, "from_array size=4");
        OK(source_series->buffer_len == 7, "from_array buffer_len=7 (SP+Minas)");

        size_t length;
        const char *text_value;

        /* [0] "SP": válida, len 2 */
        text_value = smaug_str_get(source_series, 0, &length);
        OK(text_value != NULL && length == 2 && memcmp(text_value, "SP", 2) == 0, "get [0]=SP");
        OK(!smaug_str_is_null(source_series, 0), "is_null [0]=false");

        /* [1] "": VÁLIDA e vazia (distinta de NULL) */
        text_value = smaug_str_get(source_series, 1, &length);
        OK(text_value != NULL && length == 0, "get [1]='' (ponteiro valido, len 0)");
        OK(!smaug_str_is_null(source_series, 1), "is_null ['']=false (vazia != NULL)");

        /* [2] NULL */
        text_value = smaug_str_get(source_series, 2, &length);
        OK(text_value == NULL && length == 0, "get [2]=NULL (ponteiro nulo, len 0)");
        OK(smaug_str_is_null(source_series, 2), "is_null [NULL]=true");

        /* [3] "Minas": válida, len 5 */
        text_value = smaug_str_get(source_series, 3, &length);
        OK(text_value != NULL && length == 5 && memcmp(text_value, "Minas", 5) == 0, "get [3]=Minas");

        /* offsets coerentes: [0,2,2,2,7] */
        OK(source_series->offsets[0] == 0 && source_series->offsets[1] == 2 && source_series->offsets[2] == 2
           && source_series->offsets[3] == 2 && source_series->offsets[4] == 7, "offsets coerentes");

        /* acesso fora dos limites: get NULL, is_null true */
        text_value = smaug_str_get(source_series, 99, &length);
        OK(text_value == NULL && length == 0, "get fora-limites = NULL");
        OK(smaug_str_is_null(source_series, 99), "is_null fora-limites = true");

        smaug_str_free(source_series);
    }

    /* from_array(NULL) -> NULL */
    OK(smaug_str_create_from_array(NULL, 3) == NULL, "from_array(NULL)=NULL");

    /* array vazio (len 0) -> série válida vazia */
    {
        const char *empty[] = { NULL };
        smaug_series_str_t *source_series = smaug_str_create_from_array(empty, 0);
        OK(source_series != NULL && source_series->size == 0, "from_array len 0 = serie vazia");
        smaug_str_free(source_series);
    }

    /* ---- Peça 3: set (3 casos), set_null, append ---- */

    /* helper inline de leitura para asserts */
    #define STR_EQ(source_series, row_index, expected_text) ({ size_t actual_length; const char *actual_text = smaug_str_get((source_series),(row_index),&actual_length); \
        actual_text != NULL && actual_length == strlen(expected_text) && memcmp(actual_text, expected_text, actual_length) == 0; })

    {
        const char *source_values[] = {"SP", "RJ", "MG"};
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);

        /* IGUAL: SP->RJ (mesmo tamanho, in-place) */
        OK(smaug_str_set(source_series, 0, "RJ", 2) == SMG_OK, "set igual ok");
        OK(STR_EQ(source_series, 0, "RJ"), "set igual valor");
        OK(STR_EQ(source_series, 1, "RJ") && STR_EQ(source_series, 2, "MG"), "set igual nao afeta vizinhos");

        /* MAIOR: idx0 RJ->Bahia (2->5), desloca o rabo */
        OK(smaug_str_set(source_series, 0, "Bahia", 5) == SMG_OK, "set maior ok");
        OK(STR_EQ(source_series, 0, "Bahia"), "set maior valor");
        OK(STR_EQ(source_series, 1, "RJ") && STR_EQ(source_series, 2, "MG"), "set maior preserva rabo");

        /* MENOR: idx0 Bahia->AC (5->2), fecha o buraco */
        OK(smaug_str_set(source_series, 0, "AC", 2) == SMG_OK, "set menor ok");
        OK(STR_EQ(source_series, 0, "AC"), "set menor valor");
        OK(STR_EQ(source_series, 1, "RJ") && STR_EQ(source_series, 2, "MG"), "set menor preserva rabo");

        /* MAIOR no meio: idx1 RJ->Parana (2->6) */
        OK(smaug_str_set(source_series, 1, "Parana", 6) == SMG_OK, "set meio maior ok");
        OK(STR_EQ(source_series, 0, "AC") && STR_EQ(source_series, 1, "Parana") && STR_EQ(source_series, 2, "MG"),
           "set meio preserva ambas as pontas");

        /* set_null no meio: zera idx1, preserva vizinhos */
        smaug_str_set_null(source_series, 1);
        OK(smaug_str_is_null(source_series, 1), "set_null marca NULL");
        OK(STR_EQ(source_series, 0, "AC") && STR_EQ(source_series, 2, "MG"), "set_null preserva vizinhos");

        /* set sobre NULL: torna válido */
        OK(smaug_str_set(source_series, 1, "novo", 4) == SMG_OK, "set sobre NULL ok");
        OK(!smaug_str_is_null(source_series, 1) && STR_EQ(source_series, 1, "novo"), "set sobre NULL torna valido");

        /* set para "" (vazia, válida) */
        OK(smaug_str_set(source_series, 0, "", 0) == SMG_OK, "set vazia ok");
        { size_t left_value; const char *string_get_result = smaug_str_get(source_series, 0, &left_value);
          OK(string_get_result != NULL && left_value == 0 && !smaug_str_is_null(source_series, 0), "set '' = vazia valida"); }

        /* set fora dos limites: erro */
        OK(smaug_str_set(source_series, 99, "x", 1) == SMG_ERR_OOB, "set fora-limites = erro");

        /* contrato do enum (str_set): ARGUMENT em ponteiro nulo da serie e em
           str==NULL com len>0; mas str==NULL com len==0 e valido (string vazia). */
        OK(smaug_str_set(NULL, 0, "x", 1) == SMG_ERR_ARGUMENT, "set serie NULL = ARGUMENT");
        OK(smaug_str_set(source_series, 0, NULL, 5)   == SMG_ERR_ARGUMENT, "set str NULL com len>0 = ARGUMENT");
        OK(smaug_str_set(source_series, 0, NULL, 0)   == SMG_OK,           "set str NULL com len==0 = ok (vazia)");
        OK(STR_EQ(source_series, 0, ""), "set str NULL/len0 deixa vazia");

        /* contrato do enum (str_set_null): OK em idx valido, OOB, ARGUMENT */
        OK(smaug_str_set_null(source_series, 2)    == SMG_OK,           "set_null idx valido = ok");
        OK(smaug_str_is_null(source_series, 2),                          "set_null idx valido marca NULL");
        OK(smaug_str_set_null(source_series, 99)   == SMG_ERR_OOB,      "set_null fora-limites = OOB");
        OK(smaug_str_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "set_null serie NULL = ARGUMENT");

        smaug_str_free(source_series);
    }

    /* append sequencial numa série vazia (incl. NULL no meio) */
    {
        smaug_series_str_t *left_series = smaug_str_create(0);
        OK(smaug_str_append(left_series, "um", 2) == 0, "append 1 ok");
        OK(smaug_str_append(left_series, "dois", 4) == 0, "append 2 ok");
        OK(smaug_str_append_null(left_series) == 0, "append_null ok");
        OK(smaug_str_append(left_series, "quatro", 6) == 0, "append 3 ok");
        OK(left_series->size == 4, "append size=4");
        OK(STR_EQ(left_series, 0, "um") && STR_EQ(left_series, 1, "dois") && STR_EQ(left_series, 3, "quatro"),
           "append valores");
        OK(smaug_str_is_null(left_series, 2), "append_null no meio = NULL");
        OK(smaug_str_count_nonnull(left_series) == 3, "count_nonnull apos append");
        smaug_str_free(left_series);
    }

    /* ---- clone: cópia profunda independente ---- */
    {
        const char *source_values[] = {"alpha", NULL, "gamma"};
        smaug_series_str_t *original_series = smaug_str_create_from_array(source_values, 3);
        smaug_series_str_t *source_series = smaug_str_clone(original_series);
        OK(source_series != NULL, "clone nao-nulo");
        OK(source_series->size == 3, "clone size");
        OK(STR_EQ(source_series, 0, "alpha") && smaug_str_is_null(source_series, 1) && STR_EQ(source_series, 2, "gamma"),
           "clone copia conteudo (incl. NULL)");

        /* INDEPENDÊNCIA: mutar o clone NÃO afeta o original */
        smaug_str_set(source_series, 0, "MUDADO", 6);
        OK(STR_EQ(source_series, 0, "MUDADO"), "clone mutavel");
        OK(STR_EQ(original_series, 0, "alpha"), "clone independente (original intacto)");

        /* e o inverso: mutar o original não afeta o clone */
        smaug_str_set(original_series, 2, "XX", 2);
        OK(STR_EQ(source_series, 2, "gamma"), "original independente (clone intacto)");

        smaug_str_free(original_series);
        smaug_str_free(source_series);
    }

    /* ---- Comparações (eq/lt/gt) contra string-alvo ---- */
    {
        const char *source_values[] = {"SP", "RJ", NULL, "MG", "SP", ""};
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 6);
        smaug_mask_t *null_mask = NULL;
        uint8_t *result;

        /* eq "SP": 1 0 N 0 1 0 */
        result = smaug_str_eq(source_series, "SP", 2, &null_mask);
        OK(result && null_mask, "eq retorna result+mask");
        OK(result[0]==1 && result[1]==0 && result[3]==0 && result[4]==1 && result[5]==0, "eq valores");
        OK(null_mask[2]==0x00 && null_mask[0]==0xFF, "eq NULL->mascara 0x00, valido->0xFF");
        free(result); free(null_mask); null_mask=NULL;

        /* eq "" : só a vazia (idx5) */
        result = smaug_str_eq(source_series, "", 0, &null_mask);
        OK(result[5]==1 && result[0]==0 && result[1]==0, "eq '' casa so a vazia");
        OK(null_mask[5]==0xFF, "vazia e valida (compara normal)");
        free(result); free(null_mask); null_mask=NULL;

        /* lt "RJ": MG e '' antes; SP depois -> 0 0 N 1 0 1 */
        result = smaug_str_lt(source_series, "RJ", 2, &null_mask);
        OK(result[3]==1 && result[5]==1 && result[0]==0 && result[1]==0 && result[4]==0, "lt lexicografico");
        OK(null_mask[2]==0x00, "lt NULL->mascara 0");
        free(result); free(null_mask); null_mask=NULL;

        /* gt "RJ": SP depois -> 1 0 N 0 1 0 */
        result = smaug_str_gt(source_series, "RJ", 2, &null_mask);
        OK(result[0]==1 && result[4]==1 && result[1]==0 && result[3]==0, "gt lexicografico");
        free(result); free(null_mask); null_mask=NULL;

        /* desempate por comprimento: "MG" < "MGA" (prefixo igual, mais curta antes) */
        result = smaug_str_lt(source_series, "MGA", 3, &null_mask);
        OK(result[3]==1, "lt desempata por comprimento (MG < MGA)");
        free(result); free(null_mask); null_mask=NULL;

        /* le/ge: cobrem os cases STR_CMP_LE/GE do switch. s = [SP,RJ,N,MG,SP,""] */
        result = smaug_str_le(source_series, "RJ", 2, &null_mask);   /* <= RJ: RJ(1), MG(3), ""(5); SP nao */
        OK(result[1]==1 && result[3]==1 && result[5]==1 && result[0]==0 && result[4]==0, "le lexicografico");
        OK(null_mask && null_mask[2]==0x00, "le NULL -> mascara 0");
        free(result); free(null_mask); null_mask=NULL;

        result = smaug_str_ge(source_series, "RJ", 2, &null_mask);   /* >= RJ: SP(0), RJ(1), SP(4); MG e "" nao */
        OK(result[0]==1 && result[1]==1 && result[4]==1 && result[3]==0 && result[5]==0, "ge lexicografico");
        free(result); free(null_mask); null_mask=NULL;

        result = smaug_str_le(source_series, "RJ", 2, NULL);  /* sem out_mask */
        OK(result && result[1]==1, "le sem out_mask funciona");
        free(result);

        /* eq sem out_mask (NULL) nao deve crashar */
        result = smaug_str_eq(source_series, "SP", 2, NULL);
        OK(result && result[0]==1, "eq sem out_mask funciona");
        free(result);

        smaug_str_free(source_series);
    }

    /* ---- Seleção: filter e take ---- */
    {
        const char *source_values[] = {"SP", "RJ", NULL, "MG", "SP"};
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 5);

        /* filter por máscara {1,0,0,0,1} -> SP SP */
        uint8_t source_values_2[] = {1,0,0,0,1};
        smaug_series_str_t *source_series_2 = smaug_str_filter(source_series, source_values_2);
        OK(source_series_2 && source_series_2->size == 2, "filter conta certo");
        OK(STR_EQ(source_series_2, 0, "SP") && STR_EQ(source_series_2, 1, "SP"), "filter valores");
        smaug_str_free(source_series_2);

        /* filter incluindo NULL {0,0,1,1,0} -> [NULL] MG */
        uint8_t source_values_3[] = {0,0,1,1,0};
        source_series_2 = smaug_str_filter(source_series, source_values_3);
        OK(source_series_2->size == 2 && smaug_str_is_null(source_series_2, 0) && STR_EQ(source_series_2, 1, "MG"),
           "filter preserva NULL");
        smaug_str_free(source_series_2);

        /* filter vazio */
        uint8_t source_values_4[] = {0,0,0,0,0};
        source_series_2 = smaug_str_filter(source_series, source_values_4);
        OK(source_series_2 && source_series_2->size == 0, "filter vazio = serie vazia");
        smaug_str_free(source_series_2);

        /* take reordenado {3,0,2} -> MG SP NULL */
        size_t indices[] = {3,0,2};
        smaug_series_str_t *source_series_3 = smaug_str_take(source_series, indices, 3);
        OK(source_series_3 && source_series_3->size == 3, "take conta certo");
        OK(STR_EQ(source_series_3, 0, "MG") && STR_EQ(source_series_3, 1, "SP") && smaug_str_is_null(source_series_3, 2),
           "take reordena e preserva NULL");
        smaug_str_free(source_series_3);

        /* take fora dos limites -> NULL */
        size_t source_values_5[] = {99};
        OK(smaug_str_take(source_series, source_values_5, 1) == NULL, "take fora-limites = NULL");

        smaug_str_free(source_series);
    }

    /* ---- Ordenação: sort e argsort ---- */
    {
        const char *source_values[] = {"MG", "AC", "SP", "BA", "AC"};
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 5);

        /* sort ascendente */
        smaug_series_str_t *ascending_series = smaug_str_sort(source_series, true);
        OK(ascending_series && ascending_series->size == 5, "sort asc conta");
        OK(STR_EQ(ascending_series,0,"AC") && STR_EQ(ascending_series,1,"AC") && STR_EQ(ascending_series,2,"BA")
           && STR_EQ(ascending_series,3,"MG") && STR_EQ(ascending_series,4,"SP"), "sort asc ordem");
        smaug_str_free(ascending_series);

        /* sort descendente */
        smaug_series_str_t *description = smaug_str_sort(source_series, false);
        OK(STR_EQ(description,0,"SP") && STR_EQ(description,4,"AC"), "sort desc ordem");
        smaug_str_free(description);

        /* argsort: permutação estável (os dois AC em ordem original: 1 antes de 4) */
        size_t *string_argsort_result = smaug_str_argsort(source_series, true);
        OK(string_argsort_result && string_argsort_result[0]==1 && string_argsort_result[1]==4 && string_argsort_result[2]==3 && string_argsort_result[3]==0 && string_argsort_result[4]==2,
           "argsort permutacao estavel");
        free(string_argsort_result);

        smaug_str_free(source_series);
    }

    /* sort com vazia (vem primeiro) */
    {
        const char *source_values[] = {"b", "", "a"};
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
        smaug_series_str_t *source_series_2 = smaug_str_sort(source_series, true);
        { size_t left_value; smaug_str_get(source_series_2,0,&left_value); OK(left_value==0, "sort: vazia vem primeiro"); }
        OK(STR_EQ(source_series_2,1,"a") && STR_EQ(source_series_2,2,"b"), "sort com vazia");
        smaug_str_free(source_series); smaug_str_free(source_series_2);
    }

    /* sort/argsort RECUSAM NULL */
    {
        const char *source_values[] = {"x", NULL, "a"};
        smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
        OK(smaug_str_sort(source_series, true) == NULL, "sort recusa NULL");
        OK(smaug_str_argsort(source_series, true) == NULL, "argsort recusa NULL");
        smaug_str_free(source_series);
    }

    /* ==================================================================
       FASE 8 / frente A1 (string) — varredura de input inválido.
       Guards de ponteiro NULL e sub-args (str/target NULL com len>0, idx/mask
       NULL) ainda não exercitados. set/set_null e from_array(NULL) já cobertos;
       argsort/sort aqui é o PONTEIRO NULL (distinto da série-com-null já testada).
       ================================================================== */
    {
        smaug_series_str_t *source_series = smaug_str_create(2);
        smaug_str_set(source_series, 0, "AB", 2);
        smaug_str_set(source_series, 1, "CD", 2);
        size_t  group_length = 0;
        uint8_t gmask[1] = { 1 };
        size_t  source_values[1]  = { 0 };

        OK(smaug_str_clone(NULL) == NULL,            "str clone(NULL) -> NULL");
        OK(smaug_str_get(NULL, 0, &group_length) == NULL,    "str get(serie NULL) -> NULL");
        OK(smaug_str_get(source_series, 9, &group_length) == NULL,      "str get(OOB) -> NULL");
        OK(smaug_str_is_null(NULL, 0) == true,       "str is_null(serie NULL) -> true");
        OK(smaug_str_is_null(source_series, 9) == true,         "str is_null(OOB) -> true");
        OK(smaug_str_append(NULL, "x", 1) == -1,     "str append(serie NULL) -> -1");
        OK(smaug_str_append(source_series, NULL, 5) == -1,      "str append(str NULL, len>0) -> -1");
        OK(smaug_str_append_null(NULL) == -1,        "str append_null(NULL) -> -1");
        OK(smaug_str_count_nonnull(NULL) == 0,       "str count_nonnull(NULL) -> 0");

        OK(smaug_str_eq(NULL, "x", 1, NULL) == NULL, "str eq(serie NULL) -> NULL");
        OK(smaug_str_eq(source_series, NULL, 5, NULL) == NULL,  "str eq(target NULL, len>0) -> NULL");
        OK(smaug_str_lt(NULL, "x", 1, NULL) == NULL, "str lt(serie NULL) -> NULL");
        OK(smaug_str_gt(NULL, "x", 1, NULL) == NULL, "str gt(serie NULL) -> NULL");

        /* between (10.2 fatia 2): guarda nos DOIS alvos, nao so num */
        OK(smaug_str_between(NULL, "a", 1, "z", 1, true, true, NULL) == NULL,
           "str between(serie NULL) -> NULL");
        OK(smaug_str_between(source_series, NULL, 5, "z", 1, true, true, NULL) == NULL,
           "str between(lo NULL, len>0) -> NULL");
        OK(smaug_str_between(source_series, "a", 1, NULL, 5, true, true, NULL) == NULL,
           "str between(hi NULL, len>0) -> NULL");

        /* out_mask == NULL: o ramo que o frontend nunca exercita (ele sempre
           pede a mascara), e que por isso escapa da cobertura se nao for
           testado aqui. Mesma licao da fatia 1. */
        uint8_t *string_between_result = smaug_str_between(source_series, "A", 1, "z", 1, true, true, NULL);
        OK(string_between_result != NULL, "str between sem out_mask");
        free(string_between_result);

        /* alvo NULL com len 0 e string VAZIA, nao chamada invalida: a guarda e
           `!lo && lo_len > 0`, entao este caso passa e compara normalmente.
           Sem ele, a segunda condicao da guarda nunca e avaliada (MC/DC). */
        uint8_t *string_between_result_2 = smaug_str_between(source_series, NULL, 0, "zzz", 3, true, true, NULL);
        OK(string_between_result_2 != NULL, "str between(lo NULL, len 0) trata como vazia");
        free(string_between_result_2);
        string_between_result_2 = smaug_str_between(source_series, "", 0, NULL, 0, true, true, NULL);
        OK(string_between_result_2 != NULL, "str between(hi NULL, len 0) trata como vazia");
        free(string_between_result_2);

        /* serie vazia: exercita o ramo `size ? size : 1` do malloc -- e precisa
           pedir a mascara, senao o malloc dela nao roda */
        smaug_series_str_t *vazia = smaug_str_create(0);
        OK(vazia != NULL, "str create(0) para between");
        smaug_mask_t *view_null_mask = NULL;
        uint8_t *string_between_result_3 = smaug_str_between(vazia, "a", 1, "z", 1, true, true, &view_null_mask);
        OK(string_between_result_3 != NULL, "str between em serie vazia nao estoura");
        free(string_between_result_3); free(view_null_mask);
        smaug_str_free(vazia);

        /* elemento NULL com out_mask == NULL: exercita o `if (mask)` falso
           dentro do ramo de nulo, que o frontend nunca alcanca */
        smaug_series_str_t *source_series_2 = smaug_str_create(2);
        OK(source_series_2 != NULL, "str create(2) para between com nulo");
        smaug_str_set(source_series_2, 0, "abc", 3);
        smaug_str_set_null(source_series_2, 1);
        uint8_t *string_between_result_4 = smaug_str_between(source_series_2, "a", 1, "z", 1, true, true, NULL);
        OK(string_between_result_4 != NULL && string_between_result_4[1] == 0, "str between nulo sem out_mask");
        free(string_between_result_4);
        smaug_str_free(source_series_2);

        OK(smaug_str_filter(NULL, gmask) == NULL,    "str filter(serie NULL) -> NULL");
        OK(smaug_str_filter(source_series, NULL) == NULL,       "str filter(mask NULL) -> NULL");
        OK(smaug_str_take(NULL, source_values, 1) == NULL,    "str take(serie NULL) -> NULL");
        OK(smaug_str_take(source_series, NULL, 1) == NULL,      "str take(idx NULL, len>0) -> NULL");

        OK(smaug_str_argsort(NULL, true) == NULL,    "str argsort(serie NULL) -> NULL");
        OK(smaug_str_sort(NULL, true) == NULL,       "str sort(serie NULL) -> NULL");

        smaug_str_free(source_series);
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
        const char *source_values[] = {"a", NULL, "c"};
        smaug_series_str_t *source_series  = smaug_str_create_from_array(source_values, 3);
        const char *text_values[] = {"x", "y"};
        smaug_series_str_t *source_series_2 = smaug_str_create_from_array(text_values, 2);

        /* coalesce_scalar: os dois ramos do guard */
        OK(smaug_str_coalesce_scalar(NULL, "x", 1) == NULL,
           "str_coalesce_scalar(serie NULL) -> NULL");
        OK(smaug_str_coalesce_scalar(source_series, NULL, 5) == NULL,
           "str_coalesce_scalar(value NULL, len>0) -> NULL");
        smaug_series_str_t *source_series_3 = smaug_str_coalesce_scalar(source_series, "Z", 1);
        OK(source_series_3 != NULL && STR_EQ(source_series_3, 1, "Z"),
           "str_coalesce_scalar valido preenche o NULL (controle)");
        smaug_str_free(source_series_3);
        /* value NULL com len==0 e valido (string vazia), como no str_set */
        smaug_series_str_t *source_series_4 = smaug_str_coalesce_scalar(source_series, NULL, 0);
        OK(source_series_4 != NULL, "str_coalesce_scalar(value NULL, len==0) -> ok (vazia)");
        smaug_str_free(source_series_4);

        /* coalesce: os tres ramos do || */
        OK(smaug_str_coalesce(NULL, source_series) == NULL, "str_coalesce(NULL, other) -> NULL");
        OK(smaug_str_coalesce(source_series, NULL) == NULL, "str_coalesce(self, NULL) -> NULL");
        OK(smaug_str_coalesce(source_series, source_series_2)   == NULL, "str_coalesce size divergente -> NULL");
        smaug_series_str_t *source_series_5 = smaug_str_coalesce(source_series, source_series);
        OK(source_series_5 != NULL, "str_coalesce valido -> serie (controle)");
        smaug_str_free(source_series_5);

        smaug_str_free(source_series_2); smaug_str_free(source_series);
    }

    /* 12.24: str_select — guard ESSENCIAL. A auditoria do 12.18 o marcou como
       redundante por erro do harness (removia so a linha do `if`, o
       `return NULL;` orfao executava sempre). O corpo toca cond->null_mask e
       `b` no laco. 5 ramos do `||`. */
    {
        const char *left_values[] = {"a", "b", "c"};
        const char *right_values[] = {"x", "y", "z"};
        smaug_series_str_t *source_series = smaug_str_create_from_array(left_values, 3);
        smaug_series_str_t *source_series_2 = smaug_str_create_from_array(right_values, 3);
        const char *double_value[] = {"p", "q"};
        smaug_series_str_t *source_series_3 = smaug_str_create_from_array(double_value, 2);
        smaug_series_bool_t *boolean_series = smaug_bool_create(3);
        smaug_bool_set(boolean_series, 0, 1); smaug_bool_set(boolean_series, 1, 0); smaug_bool_set(boolean_series, 2, 1);
        smaug_series_bool_t *boolean_series_2 = smaug_bool_create(2);

        OK(smaug_str_select(NULL, source_series, source_series_2) == NULL, "str_select(cond NULL) -> NULL");
        OK(smaug_str_select(boolean_series, NULL, source_series_2) == NULL, "str_select(a NULL) -> NULL");
        OK(smaug_str_select(boolean_series, source_series, NULL) == NULL, "str_select(b NULL) -> NULL");
        OK(smaug_str_select(boolean_series_2, source_series, source_series_2) == NULL,  "str_select(cond->size != a->size) -> NULL");
        OK(smaug_str_select(boolean_series, source_series, source_series_3) == NULL,   "str_select(a->size != b->size) -> NULL");
        smaug_series_str_t *source_series_4 = smaug_str_select(boolean_series, source_series, source_series_2);
        OK(source_series_4 != NULL && STR_EQ(source_series_4, 0, "a") && STR_EQ(source_series_4, 1, "y") && STR_EQ(source_series_4, 2, "c"),
           "str_select valido: cond escolhe a/b por posicao (controle)");
        smaug_str_free(source_series_4);
        smaug_bool_free(boolean_series_2); smaug_bool_free(boolean_series);
        smaug_str_free(source_series_3); smaug_str_free(source_series_2); smaug_str_free(source_series);
    }

    printf("PASS: string lifecycle (%d checks)\n", passed_checks);

    return 0;
}
