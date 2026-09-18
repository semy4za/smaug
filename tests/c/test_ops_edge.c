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

static long passed_checks = 0;
#define OK(condition, message) do { if (!(condition)) { \
    fprintf(stderr, "FALHOU: %s\n", message); exit(1); } passed_checks++; } while (0)

/* ======================================================================
   f64 — reduções com ignore_na=false sobre NULL (caminho que retorna NAN)
   ====================================================================== */
static void float64_reduce_null_false(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(3);
    smaug_f64_set(floating_point_series, 0, 10);
    smaug_f64_set_null(floating_point_series, 1);          /* NULL no meio */
    smaug_f64_set(floating_point_series, 2, 20);

    /* ignore_na=true: ignora o NULL */
    OK(smaug_f64_sum(floating_point_series, true)  == 30.0, "f64 sum ignore_na=true");
    OK(smaug_f64_mean(floating_point_series, true) == 15.0, "f64 mean ignore_na=true");
    OK(smaug_f64_min(floating_point_series, true)  == 10.0, "f64 min ignore_na=true");
    OK(smaug_f64_max(floating_point_series, true)  == 20.0, "f64 max ignore_na=true");

    /* ignore_na=false: encontra NULL -> NAN (ramo else if (!ignore_na)) */
    OK(isnan(smaug_f64_sum(floating_point_series, false)),  "f64 sum ignore_na=false -> NaN");
    OK(isnan(smaug_f64_mean(floating_point_series, false)), "f64 mean ignore_na=false -> NaN");
    OK(isnan(smaug_f64_min(floating_point_series, false)),  "f64 min ignore_na=false -> NaN");
    OK(isnan(smaug_f64_max(floating_point_series, false)),  "f64 max ignore_na=false -> NaN");
    OK(isnan(smaug_f64_var(floating_point_series, false)),  "f64 var ignore_na=false -> NaN");
    OK(isnan(smaug_f64_std(floating_point_series, false)),  "f64 std ignore_na=false -> NaN");

    smaug_f64_free(floating_point_series);
}

/* f64 — reduções em série vazia (size == 0) */
static void float64_reduce_empty(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(0);
    OK(smaug_f64_sum(floating_point_series, true) == 0.0, "f64 sum vazio = 0");
    OK(isnan(smaug_f64_mean(floating_point_series, true)), "f64 mean vazio = NaN");
    OK(isnan(smaug_f64_min(floating_point_series, true)),  "f64 min vazio = NaN");
    OK(isnan(smaug_f64_max(floating_point_series, true)),  "f64 max vazio = NaN");
    OK(isnan(smaug_f64_var(floating_point_series, true)),  "f64 var vazio = NaN");
    OK(isnan(smaug_f64_std(floating_point_series, true)),  "f64 std vazio = NaN");
    smaug_f64_free(floating_point_series);
}

/* f64 — série toda-NULL (reduções com ignore_na=true não acham nada) */
static void float64_reduce_all_null(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(2);
    smaug_f64_set_null(floating_point_series, 0);
    smaug_f64_set_null(floating_point_series, 1);
    OK(smaug_f64_sum(floating_point_series, true) == 0.0, "f64 sum todo-NULL = 0");
    OK(isnan(smaug_f64_mean(floating_point_series, true)), "f64 mean todo-NULL = NaN");
    OK(isnan(smaug_f64_min(floating_point_series, true)),  "f64 min todo-NULL = NaN");
    smaug_f64_free(floating_point_series);
}

/* f64 — operações binárias: NULL e tamanhos incompatíveis -> NULL */
static void float64_binop_guards(void) {
    smaug_series_f64_t *left_series = smaug_f64_create(3);
    smaug_series_f64_t *right_series = smaug_f64_create(2);   /* tamanho diferente */
    for (size_t row_index = 0; row_index < 3; row_index++) smaug_f64_set(left_series, row_index, (double)row_index);
    for (size_t row_index = 0; row_index < 2; row_index++) smaug_f64_set(right_series, row_index, (double)row_index);

    /* tamanhos diferentes */
    OK(smaug_f64_add(left_series, right_series) == NULL, "f64 add tam-dif -> NULL");
    OK(smaug_f64_sub(left_series, right_series) == NULL, "f64 sub tam-dif -> NULL");
    OK(smaug_f64_mul(left_series, right_series) == NULL, "f64 mul tam-dif -> NULL");
    OK(smaug_f64_div(left_series, right_series) == NULL, "f64 div tam-dif -> NULL");

    /* argumento NULL */
    OK(smaug_f64_add(NULL, left_series) == NULL, "f64 add NULL a -> NULL");
    OK(smaug_f64_add(left_series, NULL) == NULL, "f64 add NULL b -> NULL");

    smaug_f64_free(left_series);
    smaug_f64_free(right_series);
}

/* f64 — div por zero e operações com NULL preservam semântica */
static void float64_divide_zero_and_null(void) {
    smaug_series_f64_t *left_series = smaug_f64_create(3);
    smaug_series_f64_t *right_series = smaug_f64_create(3);
    smaug_f64_set(left_series, 0, 10); smaug_f64_set(left_series, 1, 20); smaug_f64_set_null(left_series, 2);
    smaug_f64_set(right_series, 0, 0);  smaug_f64_set(right_series, 1, 4);  smaug_f64_set(right_series, 2, 2);

    smaug_series_f64_t *quotient_series = smaug_f64_div(left_series, right_series);
    OK(quotient_series != NULL, "f64 div ok");
    /* 10/0 = NULL (div/0 previsível), 20/4 = 5, NULL/2 = NULL */
    OK(smaug_f64_is_null(quotient_series, 0), "f64 div por zero = NULL");
    OK(smaug_f64_get(quotient_series, 1, NULL) == 5.0, "f64 div normal");
    OK(smaug_f64_is_null(quotient_series, 2), "f64 div com NULL preserva NULL");

    smaug_f64_free(left_series); smaug_f64_free(right_series); smaug_f64_free(quotient_series);
}

/* ======================================================================
   i64 — mesmos padrões (ignore_na=false, vazio, guardas, div/0 -> NULL)
   ====================================================================== */
static void int64_reduce_null_false(void) {
    smaug_series_i64_t *integer_series = smaug_i64_create(3);
    smaug_i64_set(integer_series, 0, 10);
    smaug_i64_set_null(integer_series, 1);
    smaug_i64_set(integer_series, 2, 20);

    OK(smaug_i64_sum(integer_series, true) == 30, "i64 sum ignore_na=true");

    /* ignore_na=false com NULL: i64 usa sentinela INT64_MIN (nil no frontend) */
    OK(smaug_i64_sum(integer_series, false) == INT64_MIN, "i64 sum ignore_na=false -> sentinela");
    OK(smaug_i64_min(integer_series, false) == INT64_MIN, "i64 min ignore_na=false -> sentinela");
    OK(smaug_i64_max(integer_series, false) == INT64_MIN, "i64 max ignore_na=false -> sentinela");

    smaug_i64_free(integer_series);
}

static void int64_reduce_empty(void) {
    smaug_series_i64_t *integer_series = smaug_i64_create(0);
    OK(smaug_i64_sum(integer_series, true) == 0, "i64 sum vazio = 0");
    /* mean de i64 retorna double */
    OK(isnan(smaug_i64_mean(integer_series, true)), "i64 mean vazio = NaN");
    smaug_i64_free(integer_series);
}

static void int64_binop_guards(void) {
    smaug_series_i64_t *left_series = smaug_i64_create(3);
    smaug_series_i64_t *right_series = smaug_i64_create(2);
    for (size_t row_index = 0; row_index < 3; row_index++) smaug_i64_set(left_series, row_index, (int64_t)row_index);
    for (size_t row_index = 0; row_index < 2; row_index++) smaug_i64_set(right_series, row_index, (int64_t)row_index);

    OK(smaug_i64_add(left_series, right_series) == NULL, "i64 add tam-dif -> NULL");
    OK(smaug_i64_add(NULL, left_series) == NULL, "i64 add NULL -> NULL");

    smaug_i64_free(left_series);
    smaug_i64_free(right_series);
}

/* i64 — divisão por zero vira NULL (não Inf; inteiro não tem Inf) */
static void int64_divide_zero(void) {
    smaug_series_i64_t *left_series = smaug_i64_create(2);
    smaug_series_i64_t *right_series = smaug_i64_create(2);
    smaug_i64_set(left_series, 0, 10); smaug_i64_set(left_series, 1, 20);
    smaug_i64_set(right_series, 0, 0);  smaug_i64_set(right_series, 1, 5);

    smaug_series_i64_t *quotient_series = smaug_i64_div(left_series, right_series);
    OK(quotient_series != NULL, "i64 div ok");
    OK(smaug_i64_is_null(quotient_series, 0), "i64 div por zero -> NULL");
    OK(smaug_i64_get(quotient_series, 1, NULL) == 4, "i64 div normal (20/5=4)");

    smaug_i64_free(left_series); smaug_i64_free(right_series); smaug_i64_free(quotient_series);
}

/* f64 — scalar ops: guarda NULL e div_scalar por zero */
static void float64_scalar_edge(void) {
    smaug_series_f64_t *left_series = smaug_f64_create(2);
    smaug_f64_set(left_series, 0, 10); smaug_f64_set_null(left_series, 1);

    /* guarda NULL */
    OK(smaug_f64_add_scalar(NULL, 1) == NULL, "f64 add_scalar NULL -> NULL");
    OK(smaug_f64_div_scalar(NULL, 1) == NULL, "f64 div_scalar NULL -> NULL");

    /* preserva NULL do elemento */
    smaug_series_f64_t *add_scalar_series = smaug_f64_add_scalar(left_series, 5);
    OK(add_scalar_series && add_scalar_series->size == 2, "f64 add_scalar ok");
    OK(smaug_f64_get(add_scalar_series, 0, NULL) == 15.0, "f64 add_scalar valor");
    OK(smaug_f64_is_null(add_scalar_series, 1), "f64 add_scalar preserva NULL");
    smaug_f64_free(add_scalar_series);

    /* div_scalar por zero: tudo NULL (igual ao i64; div/0 não passa) */
    smaug_series_f64_t *divide_scalar_series = smaug_f64_div_scalar(left_series, 0);
    OK(divide_scalar_series && smaug_f64_is_null(divide_scalar_series, 0), "f64 div_scalar por zero = NULL");
    smaug_f64_free(divide_scalar_series);

    /* div_scalar normal sobre serie com null: ramo VALID verdadeiro (idx 0) e
       falso (idx 1, null preservado) */
    smaug_series_f64_t *divide_scalar_series_2 = smaug_f64_div_scalar(left_series, 2);
    OK(divide_scalar_series_2 && smaug_f64_get(divide_scalar_series_2, 0, NULL) == 5.0, "f64 div_scalar valor");
    OK(smaug_f64_is_null(divide_scalar_series_2, 1), "f64 div_scalar preserva NULL");
    smaug_f64_free(divide_scalar_series_2);

    smaug_f64_free(left_series);
}

/* f64 — comparações: guarda NULL, out_mask NULL, e NULL no elemento */
static void float64_compare_edge(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(3);
    smaug_f64_set(floating_point_series, 0, 1); smaug_f64_set_null(floating_point_series, 1); smaug_f64_set(floating_point_series, 2, 3);

    OK(smaug_f64_gt(NULL, 0, NULL) == NULL, "f64 gt NULL serie -> NULL");

    /* out_mask = NULL (caller não quer a máscara) */
    uint8_t *greater_than_mask = smaug_f64_gt(floating_point_series, 2, NULL);
    OK(greater_than_mask != NULL, "f64 gt sem out_mask ok");
    OK(greater_than_mask[2] == 1 && greater_than_mask[0] == 0, "f64 gt valores");
    free(greater_than_mask);

    /* com out_mask: NULL no elemento -> máscara 0 */
    smaug_mask_t *null_mask = NULL;
    greater_than_mask = smaug_f64_lt(floating_point_series, 5, &null_mask);
    OK(null_mask && null_mask[1] == 0x00, "f64 lt NULL -> mascara 0");
    free(greater_than_mask); free(null_mask);

    /* ge/le/ne: mesma matriz de ramos (NULL serie, out_mask NULL, mask 0xFF/0x00) */
    OK(smaug_f64_ge(NULL, 0, NULL) == NULL, "f64 ge NULL serie -> NULL");
    OK(smaug_f64_le(NULL, 0, NULL) == NULL, "f64 le NULL serie -> NULL");
    OK(smaug_f64_ne(NULL, 0, NULL) == NULL, "f64 ne NULL serie -> NULL");

    greater_than_mask = smaug_f64_ge(floating_point_series, 1, NULL);   /* out_mask NULL */
    OK(greater_than_mask != NULL && greater_than_mask[0] == 1 && greater_than_mask[2] == 1, "f64 ge sem out_mask");
    free(greater_than_mask);
    greater_than_mask = smaug_f64_le(floating_point_series, 1, NULL);
    OK(greater_than_mask != NULL && greater_than_mask[0] == 1 && greater_than_mask[2] == 0, "f64 le sem out_mask");
    free(greater_than_mask);
    greater_than_mask = smaug_f64_ne(floating_point_series, 1, NULL);
    OK(greater_than_mask != NULL && greater_than_mask[0] == 0 && greater_than_mask[2] == 1, "f64 ne sem out_mask");
    free(greater_than_mask);

    null_mask = NULL; greater_than_mask = smaug_f64_ge(floating_point_series, 1, &null_mask);   /* com mask: 0xFF nos validos, 0x00 no NULL */
    OK(null_mask && null_mask[0] == 0xFF && null_mask[1] == 0x00, "f64 ge mask valido/NULL");
    free(greater_than_mask); free(null_mask);
    null_mask = NULL; greater_than_mask = smaug_f64_le(floating_point_series, 1, &null_mask);
    OK(null_mask && null_mask[1] == 0x00, "f64 le mask NULL -> 0");
    free(greater_than_mask); free(null_mask);
    null_mask = NULL; greater_than_mask = smaug_f64_ne(floating_point_series, 1, &null_mask);
    OK(null_mask && null_mask[1] == 0x00, "f64 ne mask NULL -> 0");
    free(greater_than_mask); free(null_mask);

    /* --- 10.3 fatia A: as seis matematicas ---------------------------------
       Sao geradas por macro (F64_MATH_IMPL), mas cada instanciacao tem os
       proprios ramos: cobrir uma NAO cobre as outras cinco. Tabela em vez de
       seis blocos iguais -- mesmo motivo de a implementacao ser macro. */
    {
        typedef smaug_series_f64_t *(*mathfn)(const smaug_series_f64_t *);
        struct { const char *nome; mathfn fn; } text_values[] = {
            {"sin", smaug_f64_sin}, {"cos", smaug_f64_cos}, {"tan", smaug_f64_tan},
            {"exp", smaug_f64_exp}, {"log", smaug_f64_log}, {"sqrt", smaug_f64_sqrt},
        };
        for (size_t element_index = 0; element_index < sizeof(text_values)/sizeof(text_values[0]); element_index++) {
            OK(text_values[element_index].fn(NULL) == NULL, "f64 math NULL serie -> NULL");

            /* s = {1, NULL, 3}: exercita os dois ramos de SMAUG_VALID */
            smaug_series_f64_t *source_series = text_values[element_index].fn(floating_point_series);
            OK(source_series != NULL, "f64 math devolve serie");
            OK(SMAUG_NULL(source_series->null_mask, 1), "f64 math propaga nulo");
            OK(SMAUG_VALID(source_series->null_mask, 0), "f64 math preserva valido");
            smaug_f64_free(source_series);

            /* serie vazia nao estoura */
            smaug_series_f64_t *vazia = smaug_f64_create(0);
            OK(vazia != NULL, "f64 create(0) para math");
            smaug_series_f64_t *source_series_2 = text_values[element_index].fn(vazia);
            OK(source_series_2 != NULL, "f64 math em serie vazia");
            smaug_f64_free(source_series_2); smaug_f64_free(vazia);
        }
        /* dominio invalido: NaN como VALOR (mascara valida), nao nulo nem erro */
        smaug_series_f64_t *floating_point_series_2 = smaug_f64_create(1);
        smaug_f64_set(floating_point_series_2, 0, -4.0);
        smaug_series_f64_t *sqrt_series = smaug_f64_sqrt(floating_point_series_2);
        OK(sqrt_series && isnan(sqrt_series->data[0]), "sqrt(-4) -> NaN");
        OK(sqrt_series && SMAUG_VALID(sqrt_series->null_mask, 0), "sqrt(-4) mascara VALIDA (Contrato 9)");
        smaug_f64_free(sqrt_series);
        sqrt_series = smaug_f64_log(floating_point_series_2);
        OK(sqrt_series && isnan(sqrt_series->data[0]), "log(-4) -> NaN");
        smaug_f64_free(sqrt_series); smaug_f64_free(floating_point_series_2);
    }

    /* --- 10.3 fatia B: abs/round/clip -------------------------------------
       O frontend SEMPRE passa ponteiro de status e nunca passa serie NULL,
       entao esses ramos so existem se testados aqui. Mesma licao das fatias
       anteriores: o que o Lua nao alcanca, o teste em C tem de alcancar. */
    {
        /* f64: serie s = {1, NULL, 3} ja montada acima */
        OK(smaug_f64_abs(NULL) == NULL,                    "f64 abs NULL -> NULL");
        OK(smaug_f64_round(NULL, 2) == NULL,               "f64 round NULL -> NULL");
        OK(smaug_f64_clip(NULL, 0, true, 1, true, NULL) == NULL, "f64 clip NULL -> NULL");

        smaug_series_f64_t *abs_series = smaug_f64_abs(floating_point_series);
        OK(abs_series && SMAUG_NULL(abs_series->null_mask, 1), "f64 abs propaga nulo");
        smaug_f64_free(abs_series);

        smaug_series_f64_t *round_series = smaug_f64_round(floating_point_series, 0);
        OK(round_series && SMAUG_NULL(round_series->null_mask, 1), "f64 round propaga nulo");
        smaug_f64_free(round_series);

        /* status NULL: ramo que o frontend nunca exercita */
        smaug_series_f64_t *status_code = smaug_f64_clip(floating_point_series, 0, true, 2, true, NULL);
        OK(status_code && SMAUG_NULL(status_code->null_mask, 1), "f64 clip sem status propaga nulo");
        OK(status_code && status_code->data[0] == 1.0, "f64 clip dentro da faixa mantem");
        smaug_f64_free(status_code);
        OK(smaug_f64_clip(floating_point_series, 5, true, 1, true, NULL) == NULL, "f64 clip lo>hi sem status");

        /* status preenchido nos dois desfechos */
        smaug_status_t status = SMG_ERR_OOB;
        smaug_series_f64_t *clip_series = smaug_f64_clip(floating_point_series, 0, true, 9, true, &status);
        OK(clip_series && status == SMG_OK, "f64 clip sucesso zera status");
        smaug_f64_free(clip_series);
        OK(smaug_f64_clip(floating_point_series, 9, true, 0, true, &status) == NULL && status == SMG_ERR_ARGUMENT,
           "f64 clip lo>hi marca SMG_ERR_ARGUMENT");

        /* limites ausentes: has_lo/has_hi falsos */
        smaug_series_f64_t *clip_series_2 = smaug_f64_clip(floating_point_series, 0, false, 2, true, NULL);
        OK(clip_series_2 && clip_series_2->data[2] == 2.0, "f64 clip so com limite superior");
        smaug_f64_free(clip_series_2);
        smaug_series_f64_t *clip_series_3 = smaug_f64_clip(floating_point_series, 2, true, 0, false, NULL);
        OK(clip_series_3 && clip_series_3->data[0] == 2.0, "f64 clip so com limite inferior");
        smaug_f64_free(clip_series_3);

        /* i64 */
        int64_t source_values[3] = {-15, 25, 30};
        smaug_series_i64_t *integer_series = smaug_i64_create_from_array(source_values, 3);
        smaug_i64_set_null(integer_series, 1);

        OK(smaug_i64_abs(NULL, NULL) == NULL,               "i64 abs NULL -> NULL");
        OK(smaug_i64_round(NULL, -1, NULL) == NULL,         "i64 round NULL -> NULL");
        OK(smaug_i64_clip(NULL, 0, true, 1, true, NULL) == NULL, "i64 clip NULL -> NULL");

        /* serie NULL COM status: `if (!a) { if (status) ... }` e condicao
           composta -- serie NULL sem status cobre so metade dela */
        smaug_status_t status_2 = SMG_OK;
        OK(smaug_i64_abs(NULL, &status_2) == NULL && status_2 == SMG_ERR_ARGUMENT,
           "i64 abs NULL marca status");
        status_2 = SMG_OK;
        OK(smaug_i64_round(NULL, -1, &status_2) == NULL && status_2 == SMG_ERR_ARGUMENT,
           "i64 round NULL marca status");
        status_2 = SMG_OK;
        OK(smaug_i64_clip(NULL, 0, true, 1, true, &status_2) == NULL && status_2 == SMG_ERR_ARGUMENT,
           "i64 clip NULL marca status");
        status_2 = SMG_OK;
        OK(smaug_f64_clip(NULL, 0, true, 1, true, &status_2) == NULL && status_2 == SMG_ERR_ARGUMENT,
           "f64 clip NULL marca status");

        smaug_series_i64_t *abs_series_2 = smaug_i64_abs(integer_series, NULL);   /* status NULL */
        OK(abs_series_2 && abs_series_2->data[0] == 15, "i64 abs sem status");
        OK(abs_series_2 && SMAUG_NULL(abs_series_2->null_mask, 1), "i64 abs propaga nulo");
        smaug_i64_free(abs_series_2);

        smaug_series_i64_t *round_series_2 = smaug_i64_round(integer_series, 0, NULL);
        OK(round_series_2 && round_series_2->data[0] == -15, "i64 round(0) identidade");
        OK(round_series_2 && SMAUG_NULL(round_series_2->null_mask, 1), "i64 round propaga nulo");
        smaug_i64_free(round_series_2);

        smaug_series_i64_t *round_series_3 = smaug_i64_round(integer_series, -1, NULL);
        OK(round_series_3 && round_series_3->data[0] == -20, "i64 round(-1) de -15 = -20 (afasta do zero)");
        smaug_i64_free(round_series_3);

        smaug_series_i64_t *clip_series_4 = smaug_i64_clip(integer_series, 0, true, 28, true, NULL);
        OK(clip_series_4 && clip_series_4->data[0] == 0 && clip_series_4->data[2] == 28, "i64 clip sem status");
        smaug_i64_free(clip_series_4);
        OK(smaug_i64_clip(integer_series, 9, true, 0, true, NULL) == NULL, "i64 clip lo>hi sem status");

        /* INT64_MIN em abs: erro, com e sem status */
        smaug_series_i64_t *integer_series_2 = smaug_i64_create(1);
        smaug_i64_set(integer_series_2, 0, INT64_MIN);
        smaug_status_t status_3 = SMG_OK;
        OK(smaug_i64_abs(integer_series_2, &status_3) == NULL && status_3 == SMG_ERR_ARGUMENT,
           "i64 abs(INT64_MIN) marca SMG_ERR_ARGUMENT");
        OK(smaug_i64_abs(integer_series_2, NULL) == NULL, "i64 abs(INT64_MIN) sem status");
        smaug_i64_free(integer_series_2);

        /* round: fator grande demais, e overflow do resultado perto do teto */
        OK(smaug_i64_round(integer_series, -19, NULL) == NULL, "i64 round(-19) fator nao cabe");
        smaug_status_t status_4 = SMG_OK;
        OK(smaug_i64_round(integer_series, -25, &status_4) == NULL && status_4 == SMG_ERR_ARGUMENT,
           "i64 round(-25) marca status");
        smaug_series_i64_t *integer_series_3 = smaug_i64_create(1);
        smaug_i64_set(integer_series_3, 0, INT64_MAX);
        smaug_status_t status_5 = SMG_OK;
        OK(smaug_i64_round(integer_series_3, -3, &status_5) == NULL && status_5 == SMG_ERR_ARGUMENT,
           "i64 round de INT64_MAX estoura ao arredondar para cima");
        smaug_i64_free(integer_series_3);

        /* overflow NEGATIVO: o outro lado da guarda (q < INT64_MIN / factor).
           INT64_MIN arredondado para baixo sai da faixa pelo piso. */
        smaug_series_i64_t *integer_series_4 = smaug_i64_create(1);
        smaug_i64_set(integer_series_4, 0, INT64_MIN);
        smaug_status_t status_6 = SMG_OK;
        OK(smaug_i64_round(integer_series_4, -3, &status_6) == NULL && status_6 == SMG_ERR_ARGUMENT,
           "i64 round de INT64_MIN estoura pelo piso");
        smaug_i64_free(integer_series_4);

        /* series vazias nos dois dtypes */
        smaug_series_i64_t *integer_series_5 = smaug_i64_create(0);
        smaug_series_i64_t *abs_series_3 = smaug_i64_abs(integer_series_5, NULL);
        OK(abs_series_3 != NULL, "i64 abs em serie vazia");
        smaug_i64_free(abs_series_3);
        abs_series_3 = smaug_i64_round(integer_series_5, -2, NULL);
        OK(abs_series_3 != NULL, "i64 round em serie vazia");
        smaug_i64_free(abs_series_3); smaug_i64_free(integer_series_5);

        smaug_series_f64_t *floating_point_series_2 = smaug_f64_create(0);
        smaug_series_f64_t *abs_series_4 = smaug_f64_abs(floating_point_series_2);
        OK(abs_series_4 != NULL, "f64 abs em serie vazia");
        smaug_f64_free(abs_series_4); smaug_f64_free(floating_point_series_2);

        smaug_i64_free(integer_series);
    }

    /* between: mesma matriz de ramos. Serie tem {1, NULL, 3}. */
    OK(smaug_f64_between(NULL, 0, 5, true, true, NULL) == NULL,
       "f64 between NULL serie -> NULL");

    greater_than_mask = smaug_f64_between(floating_point_series, 1, 3, true, true, NULL);   /* out_mask NULL */
    OK(greater_than_mask != NULL && greater_than_mask[0] == 1 && greater_than_mask[2] == 1, "f64 between sem out_mask");
    free(greater_than_mask);

    null_mask = NULL; greater_than_mask = smaug_f64_between(floating_point_series, 1, 3, true, true, &null_mask);
    OK(null_mask && null_mask[0] == 0xFF && null_mask[1] == 0x00, "f64 between mask valido/NULL");
    OK(greater_than_mask[1] == 0, "f64 between NULL no elemento -> 0");
    free(greater_than_mask); free(null_mask);

    /* os quatro modos de inclusividade, com os limites nas pontas (1 e 3) */
    greater_than_mask = smaug_f64_between(floating_point_series, 1, 3, false, false, NULL);
    OK(greater_than_mask && greater_than_mask[0] == 0 && greater_than_mask[2] == 0, "f64 between neither exclui as pontas");
    free(greater_than_mask);
    greater_than_mask = smaug_f64_between(floating_point_series, 1, 3, true, false, NULL);
    OK(greater_than_mask && greater_than_mask[0] == 1 && greater_than_mask[2] == 0, "f64 between left");
    free(greater_than_mask);
    greater_than_mask = smaug_f64_between(floating_point_series, 1, 3, false, true, NULL);
    OK(greater_than_mask && greater_than_mask[0] == 0 && greater_than_mask[2] == 1, "f64 between right");
    free(greater_than_mask);

    smaug_f64_free(floating_point_series);
}

/* f64 — sort/argsort recusam NULL e NaN */
static void float64_sort_edge(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(3);
    smaug_f64_set(floating_point_series, 0, 3); smaug_f64_set_null(floating_point_series, 1); smaug_f64_set(floating_point_series, 2, 1);
    OK(smaug_f64_argsort(floating_point_series, true) == NULL, "f64 argsort recusa NULL");
    OK(smaug_f64_sort(floating_point_series, true) == NULL, "f64 sort recusa NULL");
    smaug_f64_free(floating_point_series);

    /* NaN também é recusado (valor presente, mas sem ordem total) */
    smaug_series_f64_t *floating_point_series_2 = smaug_f64_create(2);
    smaug_f64_set(floating_point_series_2, 0, NAN); smaug_f64_set(floating_point_series_2, 1, 1);
    OK(smaug_f64_argsort(floating_point_series_2, true) == NULL, "f64 argsort recusa NaN");
    smaug_f64_free(floating_point_series_2);
}

/* f64 — take fora dos limites e filter */
static void float64_take_filter_edge(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(3);
    for (size_t row_index = 0; row_index < 3; row_index++) smaug_f64_set(floating_point_series, row_index, (double)row_index);

    size_t source_values[] = {99};
    OK(smaug_f64_take(floating_point_series, source_values, 1) == NULL, "f64 take fora-limites -> NULL");

    uint8_t source_values_2[] = {1, 0, 1};
    smaug_series_f64_t *filtered_result = smaug_f64_filter(floating_point_series, source_values_2);
    OK(filtered_result && filtered_result->size == 2, "f64 filter ok");
    smaug_f64_free(filtered_result);

    OK(smaug_f64_filter(NULL, source_values_2) == NULL, "f64 filter NULL -> NULL");

    smaug_f64_free(floating_point_series);
}

/* i64 — scalar, comparação e sort edge (espelha o f64) */
static void int64_scalar_compare_sort_edge(void) {
    smaug_series_i64_t *left_series = smaug_i64_create(2);
    smaug_i64_set(left_series, 0, 10); smaug_i64_set_null(left_series, 1);

    /* scalar guarda NULL + preserva NULL do elemento */
    OK(smaug_i64_add_scalar(NULL, 1) == NULL, "i64 add_scalar NULL -> NULL");
    smaug_series_i64_t *add_scalar_series = smaug_i64_add_scalar(left_series, 5);
    OK(add_scalar_series && smaug_i64_get(add_scalar_series, 0, NULL) == 15, "i64 add_scalar valor");
    OK(smaug_i64_is_null(add_scalar_series, 1), "i64 add_scalar preserva NULL");
    smaug_i64_free(add_scalar_series);

    /* div_scalar por zero -> NULL (inteiro) */
    smaug_series_i64_t *divide_scalar_series = smaug_i64_div_scalar(left_series, 0);
    OK(divide_scalar_series && smaug_i64_is_null(divide_scalar_series, 0), "i64 div_scalar por zero -> NULL");
    smaug_i64_free(divide_scalar_series);

    /* comparação: guarda NULL, out_mask NULL */
    OK(smaug_i64_gt(NULL, 0, NULL) == NULL, "i64 gt NULL -> NULL");
    uint8_t *greater_than_mask = smaug_i64_gt(left_series, 5, NULL);
    OK(greater_than_mask && greater_than_mask[0] == 1, "i64 gt sem out_mask");
    free(greater_than_mask);

    /* ge/le/ne: NULL serie, out_mask NULL, mask 0xFF/0x00 (a = [10, null]) */
    OK(smaug_i64_ge(NULL, 0, NULL) == NULL, "i64 ge NULL -> NULL");
    OK(smaug_i64_le(NULL, 0, NULL) == NULL, "i64 le NULL -> NULL");
    OK(smaug_i64_ne(NULL, 0, NULL) == NULL, "i64 ne NULL -> NULL");
    greater_than_mask = smaug_i64_ge(left_series, 10, NULL); OK(greater_than_mask && greater_than_mask[0] == 1, "i64 ge sem out_mask"); free(greater_than_mask);
    greater_than_mask = smaug_i64_le(left_series, 10, NULL); OK(greater_than_mask && greater_than_mask[0] == 1, "i64 le sem out_mask"); free(greater_than_mask);
    greater_than_mask = smaug_i64_ne(left_series, 10, NULL); OK(greater_than_mask && greater_than_mask[0] == 0, "i64 ne sem out_mask"); free(greater_than_mask);
    smaug_mask_t *integer_null_mask = NULL;
    greater_than_mask = smaug_i64_ge(left_series, 10, &integer_null_mask); OK(integer_null_mask && integer_null_mask[0] == 0xFF && integer_null_mask[1] == 0x00, "i64 ge mask valido/NULL"); free(greater_than_mask); free(integer_null_mask);
    integer_null_mask = NULL; greater_than_mask = smaug_i64_le(left_series, 10, &integer_null_mask); OK(integer_null_mask && integer_null_mask[1] == 0x00, "i64 le mask NULL -> 0"); free(greater_than_mask); free(integer_null_mask);
    integer_null_mask = NULL; greater_than_mask = smaug_i64_ne(left_series, 10, &integer_null_mask); OK(integer_null_mask && integer_null_mask[1] == 0x00, "i64 ne mask NULL -> 0"); free(greater_than_mask); free(integer_null_mask);

    /* between: mesma matriz de ramos (a = [10, null]) */
    OK(smaug_i64_between(NULL, 0, 5, true, true, NULL) == NULL, "i64 between NULL -> NULL");
    greater_than_mask = smaug_i64_between(left_series, 10, 10, true, true, NULL);   /* out_mask NULL */
    OK(greater_than_mask && greater_than_mask[0] == 1, "i64 between sem out_mask");
    free(greater_than_mask);
    integer_null_mask = NULL; greater_than_mask = smaug_i64_between(left_series, 0, 20, true, true, &integer_null_mask);
    OK(integer_null_mask && integer_null_mask[0] == 0xFF && integer_null_mask[1] == 0x00, "i64 between mask valido/NULL");
    OK(greater_than_mask[1] == 0, "i64 between NULL no elemento -> 0");
    free(greater_than_mask); free(integer_null_mask);
    /* os quatro modos, limites nas pontas (serie tem 10) */
    greater_than_mask = smaug_i64_between(left_series, 10, 10, false, false, NULL);
    OK(greater_than_mask && greater_than_mask[0] == 0, "i64 between neither exclui as pontas"); free(greater_than_mask);
    greater_than_mask = smaug_i64_between(left_series, 10, 20, true, false, NULL);
    OK(greater_than_mask && greater_than_mask[0] == 1, "i64 between left inclui a inferior"); free(greater_than_mask);
    greater_than_mask = smaug_i64_between(left_series, 0, 10, false, true, NULL);
    OK(greater_than_mask && greater_than_mask[0] == 1, "i64 between right inclui a superior"); free(greater_than_mask);

    /* exatidao acima de 2^53 no nivel C: 2^53+1 e 2^53+3 sao vizinhos que o
       double confundiria (ambos cairiam em multiplos de 2). Aqui a comparacao
       e int64_t pura, entao between(2^53+1, 2^53+1) tem de isolar o primeiro. */
    smaug_series_i64_t *integer_series = smaug_i64_create(2);
    smaug_i64_set(integer_series, 0, 9007199254740993LL);   /* 2^53 + 1 */
    smaug_i64_set(integer_series, 1, 9007199254740995LL);   /* 2^53 + 3 */
    greater_than_mask = smaug_i64_between(integer_series, 9007199254740993LL, 9007199254740993LL, true, true, NULL);
    OK(greater_than_mask && greater_than_mask[0] == 1 && greater_than_mask[1] == 0, "i64 between exato acima de 2^53");
    free(greater_than_mask);
    smaug_i64_free(integer_series);

    /* sort/argsort recusam NULL */
    OK(smaug_i64_argsort(left_series, true) == NULL, "i64 argsort recusa NULL");
    OK(smaug_i64_sort(left_series, true) == NULL, "i64 sort recusa NULL");

    /* take fora dos limites */
    smaug_series_i64_t *integer_series_2 = smaug_i64_create(2);
    smaug_i64_set(integer_series_2, 0, 1); smaug_i64_set(integer_series_2, 1, 2);
    size_t source_values[] = {5};
    OK(smaug_i64_take(integer_series_2, source_values, 1) == NULL, "i64 take fora-limites -> NULL");
    smaug_i64_free(integer_series_2);

    smaug_i64_free(left_series);
}

/* ======================================================================
   Contrato defensivo: set/set_null comunicam sucesso/falha via smaug_status_t
   (SMG_OK / SMG_ERR_OOB / SMG_ERR_ARGUMENT). Prova que a falha deixou de ser
   silenciosa — o caller distingue escrita aplicada de escrita rejeitada — e que
   em erro NENHUMA escrita ocorre.
   ====================================================================== */
static void mutation_status_contract(void) {
    /* --- f64 --- */
    smaug_series_f64_t *floating_point_series = smaug_f64_create(2);
    OK(smaug_f64_set(floating_point_series, 0, 1.5)    == SMG_OK,           "f64_set idx valido -> OK");
    OK(smaug_f64_set_null(floating_point_series, 1)    == SMG_OK,           "f64_set_null idx valido -> OK");
    OK(smaug_f64_set(floating_point_series, 9, 1.0)    == SMG_ERR_OOB,      "f64_set OOB");
    OK(smaug_f64_set_null(floating_point_series, 9)    == SMG_ERR_OOB,      "f64_set_null OOB");
    OK(smaug_f64_set(NULL, 0, 1.0) == SMG_ERR_ARGUMENT, "f64_set serie NULL -> ARGUMENT");
    OK(smaug_f64_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "f64_set_null serie NULL -> ARGUMENT");
    OK(smaug_f64_get(floating_point_series, 0, NULL) == 1.5, "f64 erro nao corrompeu idx 0");
    OK(smaug_f64_is_null(floating_point_series, 1),    "f64 idx 1 segue NULL");
    smaug_f64_free(floating_point_series);

    /* --- i64 --- */
    smaug_series_i64_t *integer_series = smaug_i64_create(2);
    OK(smaug_i64_set(integer_series, 0, 42)     == SMG_OK,           "i64_set idx valido -> OK");
    OK(smaug_i64_set_null(integer_series, 1)    == SMG_OK,           "i64_set_null idx valido -> OK");
    OK(smaug_i64_set(integer_series, 9, 1)      == SMG_ERR_OOB,      "i64_set OOB");
    OK(smaug_i64_set_null(integer_series, 9)    == SMG_ERR_OOB,      "i64_set_null OOB");
    OK(smaug_i64_set(NULL, 0, 1)   == SMG_ERR_ARGUMENT, "i64_set serie NULL -> ARGUMENT");
    OK(smaug_i64_set_null(NULL, 0) == SMG_ERR_ARGUMENT, "i64_set_null serie NULL -> ARGUMENT");
    OK(smaug_i64_get(integer_series, 0, NULL) == 42,  "i64 erro nao corrompeu idx 0");
    smaug_i64_free(integer_series);

    /* --- str_set_null (entrou no contrato; antes era void) --- */
    smaug_series_str_t *source_series = smaug_str_create(2);
    OK(smaug_str_set(source_series, 0, "ab", 2) == 0,                "str_set idx valido (legado 0=ok)");
    OK(smaug_str_set_null(source_series, 1)     == SMG_OK,           "str_set_null idx valido -> OK");
    OK(smaug_str_set_null(source_series, 9)     == SMG_ERR_OOB,      "str_set_null OOB");
    OK(smaug_str_set_null(NULL, 0)  == SMG_ERR_ARGUMENT, "str_set_null serie NULL -> ARGUMENT");
    OK(smaug_str_is_null(source_series, 1),     "str_set_null marcou NULL idx 1");
    smaug_str_free(source_series);
}

/* ======================================================================
   Contrato defensivo: get (Shape 1) — valor + smaug_status_t* anulável.
   Prova que a COLISÃO acabou: um NaN legítimo (f64) e um zero legítimo (i64)
   retornam SMG_OK, distinguíveis de NULL (SMG_NULL_VALUE) e de índice inválido
   (SMG_ERR_OOB) — que antes eram indistinguíveis do valor.
   ====================================================================== */
static void get_status_contract(void) {
    smaug_status_t status;

    /* --- f64: o caso que prova o fim da colisão NaN --- */
    smaug_series_f64_t *floating_point_series = smaug_f64_create(3);
    smaug_f64_set(floating_point_series, 0, 3.14);
    smaug_f64_set(floating_point_series, 1, NAN);      /* NaN LEGÍTIMO como valor */
    smaug_f64_set_null(floating_point_series, 2);      /* NULL */

    status = SMG_ERR_OOB;
    OK(smaug_f64_get(floating_point_series, 0, &status) == 3.14 && status == SMG_OK, "f64 get valor -> OK");
    double element_value = smaug_f64_get(floating_point_series, 1, &status);              /* valor NaN, status OK */
    OK(isnan(element_value) && status == SMG_OK, "f64 get NaN legitimo -> NaN + OK (colisao resolvida)");
    smaug_f64_get(floating_point_series, 2, &status); OK(status == SMG_NULL_VALUE,   "f64 get NULL -> SMG_NULL_VALUE");
    smaug_f64_get(floating_point_series, 9, &status); OK(status == SMG_ERR_OOB,      "f64 get OOB -> SMG_ERR_OOB");
    smaug_f64_get(NULL, 0, &status); OK(status == SMG_ERR_ARGUMENT, "f64 get serie NULL -> ARGUMENT");
    OK(smaug_f64_get(floating_point_series, 0, NULL) == 3.14, "f64 get status=NULL ainda devolve valor");
    smaug_f64_free(floating_point_series);

    /* --- i64: aqui a colisão era TOTAL (0 é um valor comum) --- */
    smaug_series_i64_t *integer_series = smaug_i64_create(2);
    smaug_i64_set(integer_series, 0, 0);        /* ZERO legítimo */
    smaug_i64_set_null(integer_series, 1);      /* NULL (também devolve 0) */
    status = SMG_ERR_OOB;
    OK(smaug_i64_get(integer_series, 0, &status) == 0 && status == SMG_OK, "i64 get zero legitimo -> 0 + OK");
    OK(smaug_i64_get(integer_series, 1, &status) == 0 && status == SMG_NULL_VALUE,
       "i64 get NULL -> 0 + NULL_VALUE (distingue do zero)");
    smaug_i64_get(integer_series, 9, &status); OK(status == SMG_ERR_OOB,      "i64 get OOB -> SMG_ERR_OOB");
    smaug_i64_get(NULL, 0, &status); OK(status == SMG_ERR_ARGUMENT, "i64 get serie NULL -> ARGUMENT");
    OK(smaug_i64_get(integer_series, 0, NULL) == 0, "i64 get status=NULL ainda devolve valor");
    smaug_i64_free(integer_series);
}

/* ======================================================================
   Semântica Fechada — A2: view com start+len que overflow size_t deve ser
   rejeitada corretamente. A checagem antiga `start + len > size` pode fazer
   wrap-around em size_t, permitindo que valores absurdos passem; a forma
   segura é `start > size || len > size - start`.
   ====================================================================== */
static void view_overflow_boundary(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(4);

    /* limites normais: deve funcionar */
    smaug_series_f64_t *series_view = smaug_f64_view(floating_point_series, 0, 4);
    OK(series_view != NULL,                    "view start=0 len=size valida");
    smaug_f64_free(series_view);
    series_view = smaug_f64_view(floating_point_series, 2, 2);
    OK(series_view != NULL,                    "view start+len == size valida");
    smaug_f64_free(series_view);

    /* além dos limites normais: deve ser rejeitada */
    OK(smaug_f64_view(floating_point_series, 0, 5) == NULL,  "view len > size -> NULL");
    OK(smaug_f64_view(floating_point_series, 3, 2) == NULL,  "view start+len > size -> NULL");

    /* overflow de size_t: len=SIZE_MAX; com a checagem antiga,
       start(1)+SIZE_MAX wrappa para 0 < size(4) e passaria — bug real.
       Com a checagem segura SIZE_MAX > size-start = 3 → rejeitada. */
    OK(smaug_f64_view(floating_point_series, 1, SIZE_MAX) == NULL,
       "view len=SIZE_MAX overflow-safe -> NULL");

    /* i64 — mesma garantia */
    smaug_series_i64_t *integer_series = smaug_i64_create(4);
    OK(smaug_i64_view(integer_series, 1, SIZE_MAX) == NULL,
       "i64 view len=SIZE_MAX overflow-safe -> NULL");
    smaug_i64_free(integer_series);

    smaug_f64_free(floating_point_series);
}

/* ======================================================================
   Semântica Fechada — A3: NaN em comparações (nível C).
   NaN > threshold = false (IEEE 754); a máscara é VÁLIDA (0xFF), não NA.
   Isso é distinto de NULL: um NULL em gt produz máscara 0x00 (NA).
   ====================================================================== */
static void nan_in_compare(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(3);
    smaug_f64_set(floating_point_series, 0, 5.0);
    smaug_f64_set(floating_point_series, 1, NAN);   /* NaN como valor presente */
    smaug_f64_set_null(floating_point_series, 2);   /* NULL genuíno */

    smaug_mask_t *null_mask = NULL;
    uint8_t *greater_than_mask = smaug_f64_gt(floating_point_series, 0.0, &null_mask);
    OK(greater_than_mask != NULL,      "gt com NaN: retorna resultado");
    OK(greater_than_mask[0] == 1,      "gt: 5.0 > 0 = true");
    OK(greater_than_mask[1] == 0,      "gt: NaN > 0 = false (IEEE)");
    OK(null_mask[1] == 0xFF,   "gt: máscara de NaN = válida (não NA)");
    OK(greater_than_mask[2] == 0,      "gt: NULL > 0 = false");
    OK(null_mask[2] == 0x00,   "gt: máscara de NULL = NA (0x00)");
    free(greater_than_mask); free(null_mask);

    /* lt também */
    greater_than_mask = smaug_f64_lt(floating_point_series, 3.0, &null_mask);
    OK(greater_than_mask != NULL,      "lt com NaN: retorna resultado");
    OK(greater_than_mask[1] == 0,      "lt: NaN < 3 = false (IEEE)");
    OK(null_mask[1] == 0xFF,   "lt: máscara de NaN = válida");
    free(greater_than_mask); free(null_mask);

    /* eq */
    greater_than_mask = smaug_f64_eq(floating_point_series, NAN, &null_mask);
    OK(greater_than_mask != NULL,      "eq NaN==NaN: retorna resultado");
    OK(greater_than_mask[1] == 0,      "eq: NaN == NaN = false (IEEE)");
    OK(null_mask[1] == 0xFF,   "eq: máscara NaN = válida");
    free(greater_than_mask); free(null_mask);

    smaug_f64_free(floating_point_series);
}

/* ======================================================================
   Overflow int64: a operação precisa falhar de forma definida, antes de
   executar a expressão assinada. A API com status preserva a causa para o
   FFI; a API legada também fica segura e devolve NULL.
   ====================================================================== */
static void int64_overflow_behavior(void) {
    smaug_series_i64_t *left_series = smaug_i64_create(1);
    smaug_series_i64_t *right_series = smaug_i64_create(1);
    smaug_status_t status = SMG_OK;

    smaug_i64_set(left_series, 0, INT64_MAX);
    smaug_i64_set(right_series, 0, 1);
    OK(smaug_i64_add_checked_series(left_series, right_series, &status) == NULL && status == SMG_ERR_OVERFLOW,
       "i64 add: overflow comunicado");
    OK(smaug_i64_add(left_series, right_series) == NULL, "i64 add legado: overflow seguro");

    smaug_i64_set(left_series, 0, INT64_MIN);
    OK(smaug_i64_sub_checked_series(left_series, right_series, &status) == NULL && status == SMG_ERR_OVERFLOW,
       "i64 sub: overflow comunicado");
    smaug_series_i64_t *divide_checked_series_series = smaug_i64_div_checked_series(left_series, right_series, &status);
    OK(divide_checked_series_series != NULL && status == SMG_OK, "i64 div por 1 permanece valida");
    smaug_i64_free(divide_checked_series_series);

    smaug_i64_set(left_series, 0, INT64_MAX);
    smaug_i64_set(right_series, 0, 2);
    OK(smaug_i64_mul_checked_series(left_series, right_series, &status) == NULL && status == SMG_ERR_OVERFLOW,
       "i64 mul: overflow comunicado");
    OK(smaug_i64_add_scalar_checked(left_series, 1, &status) == NULL && status == SMG_ERR_OVERFLOW,
       "i64 add escalar: overflow comunicado");

    smaug_i64_set(left_series, 0, INT64_MIN);
    smaug_i64_set(right_series, 0, -1);
    OK(smaug_i64_div_checked_series(left_series, right_series, &status) == NULL && status == SMG_ERR_OVERFLOW,
       "i64 div INT64_MIN/-1: overflow comunicado");

    smaug_series_i64_t *integer_series = smaug_i64_create(2);
    smaug_i64_set(integer_series, 0, INT64_MAX); smaug_i64_set(integer_series, 1, 1);
    (void)smaug_i64_sum_checked(integer_series, true, &status);
    OK(status == SMG_ERR_OVERFLOW, "i64 sum: overflow comunicado");
    OK(smaug_i64_cumsum_checked(integer_series, &status) == NULL && status == SMG_ERR_OVERFLOW,
       "i64 cumsum: overflow comunicado");
    smaug_series_i64_t *diff_checked_series = smaug_i64_diff_checked(integer_series, 1, &status);
    OK(diff_checked_series != NULL && status == SMG_OK, "i64 diff sem overflow permanece valida");
    smaug_i64_free(diff_checked_series);
    smaug_i64_set(integer_series, 0, INT64_MIN); smaug_i64_set(integer_series, 1, INT64_MAX);
    OK(smaug_i64_diff_checked(integer_series, 1, &status) == NULL && status == SMG_ERR_OVERFLOW,
       "i64 diff: overflow comunicado");
    smaug_i64_free(integer_series);

    smaug_i64_free(left_series);
    smaug_i64_free(right_series);
}

/* ======================================================================
   FASE 8 / categoria C — propagação de NULL nas aritméticas binárias.
   O ramo descoberto é a 2a condição do `VALID(a,i) && VALID(b,i)`: "b NULL
   com a VÁLIDO" (os testes de div só faziam "a NULL", que curto-circuita em
   VALID(a) e nunca avalia VALID(b)). Padrão [ambos válidos | a-val/b-null |
   a-null/b-val] exercita as 4 branches do &&.
   ====================================================================== */
static void float64_arith_null_prop(void) {
    smaug_series_f64_t *left_series = smaug_f64_create(3);
    smaug_series_f64_t *right_series = smaug_f64_create(3);
    smaug_f64_set(left_series, 0, 1);  smaug_f64_set(left_series, 1, 2);  smaug_f64_set_null(left_series, 2);
    smaug_f64_set(right_series, 0, 10); smaug_f64_set_null(right_series, 1); smaug_f64_set(right_series, 2, 30);

    smaug_series_f64_t *source_series;
    #define CHECK_PROP(operation, name) \
        source_series = smaug_f64_##operation(left_series, right_series); \
        OK(!smaug_f64_is_null(source_series, 0), name " pos0 (ambos validos) -> valido"); \
        OK(smaug_f64_is_null(source_series, 1),  name " pos1 (b NULL, a valido) -> NULL"); \
        OK(smaug_f64_is_null(source_series, 2),  name " pos2 (a NULL) -> NULL"); \
        smaug_f64_free(source_series)
    CHECK_PROP(add, "f64 add");
    CHECK_PROP(sub, "f64 sub");
    CHECK_PROP(mul, "f64 mul");
    CHECK_PROP(div, "f64 div");
    #undef CHECK_PROP

    smaug_f64_free(left_series); smaug_f64_free(right_series);
}

static void int64_arith_null_prop(void) {
    smaug_series_i64_t *left_series = smaug_i64_create(3);
    smaug_series_i64_t *right_series = smaug_i64_create(3);
    smaug_i64_set(left_series, 0, 6);  smaug_i64_set(left_series, 1, 8);  smaug_i64_set_null(left_series, 2);
    smaug_i64_set(right_series, 0, 2);  smaug_i64_set_null(right_series, 1); smaug_i64_set(right_series, 2, 4);

    smaug_series_i64_t *source_series;
    #define CHECK_PROP(operation, name) \
        source_series = smaug_i64_##operation(left_series, right_series); \
        OK(!smaug_i64_is_null(source_series, 0), name " pos0 (ambos validos) -> valido"); \
        OK(smaug_i64_is_null(source_series, 1),  name " pos1 (b NULL, a valido) -> NULL"); \
        OK(smaug_i64_is_null(source_series, 2),  name " pos2 (a NULL) -> NULL"); \
        smaug_i64_free(source_series)
    CHECK_PROP(add, "i64 add");
    CHECK_PROP(sub, "i64 sub");
    CHECK_PROP(mul, "i64 mul");
    CHECK_PROP(div, "i64 div");
    #undef CHECK_PROP

    smaug_i64_free(left_series); smaug_i64_free(right_series);
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
    smaug_series_f64_t *floating_point_series = smaug_f64_create(3);
    smaug_f64_set(floating_point_series, 0, 1); smaug_f64_set(floating_point_series, 1, 2); smaug_f64_set(floating_point_series, 2, 3);
    smaug_series_i64_t *integer_series = smaug_i64_create(3);
    smaug_i64_set(integer_series, 0, 1); smaug_i64_set(integer_series, 1, 2); smaug_i64_set(integer_series, 2, 3);
    smaug_series_i64_t *integer_series_2 = smaug_i64_create(2);   /* tamanho diferente */

    /* binops: NULL em qualquer operando -> NULL (cobre as 2 sub-condições do ||) */
    OK(smaug_f64_sub(NULL, floating_point_series) == NULL && smaug_f64_sub(floating_point_series, NULL) == NULL, "f64 sub NULL -> NULL");
    OK(smaug_f64_mul(NULL, floating_point_series) == NULL && smaug_f64_mul(floating_point_series, NULL) == NULL, "f64 mul NULL -> NULL");
    OK(smaug_f64_div(NULL, floating_point_series) == NULL && smaug_f64_div(floating_point_series, NULL) == NULL, "f64 div NULL -> NULL");
    OK(smaug_i64_sub(NULL, integer_series) == NULL && smaug_i64_sub(integer_series, NULL) == NULL, "i64 sub NULL -> NULL");
    OK(smaug_i64_mul(NULL, integer_series) == NULL && smaug_i64_mul(integer_series, NULL) == NULL, "i64 mul NULL -> NULL");
    OK(smaug_i64_div(NULL, integer_series) == NULL && smaug_i64_div(integer_series, NULL) == NULL, "i64 div NULL -> NULL");

    /* binops i64: tamanho incompatível (add já coberto pelo i64_binop) */
    OK(smaug_i64_sub(integer_series, integer_series_2) == NULL, "i64 sub tam-dif -> NULL");
    OK(smaug_i64_mul(integer_series, integer_series_2) == NULL, "i64 mul tam-dif -> NULL");
    OK(smaug_i64_div(integer_series, integer_series_2) == NULL, "i64 div tam-dif -> NULL");

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
        size_t  indices[1]  = { 0 };
        uint8_t source_values[1] = { 1 };
        OK(smaug_f64_take(NULL, indices, 1) == NULL, "f64 take serie NULL -> NULL");
        OK(smaug_f64_take(floating_point_series, NULL, 1)  == NULL, "f64 take idx NULL -> NULL");
        OK(smaug_f64_filter(NULL, source_values) == NULL, "f64 filter serie NULL -> NULL");
        OK(smaug_f64_filter(floating_point_series, NULL)   == NULL, "f64 filter mask NULL -> NULL");
        OK(smaug_i64_take(NULL, indices, 1) == NULL, "i64 take serie NULL -> NULL");
        OK(smaug_i64_take(integer_series, NULL, 1)  == NULL, "i64 take idx NULL -> NULL");
        OK(smaug_i64_filter(NULL, source_values) == NULL, "i64 filter serie NULL -> NULL");
        OK(smaug_i64_filter(integer_series, NULL)   == NULL, "i64 filter mask NULL -> NULL");
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
    smaug_series_f64_t *callback = smaug_f64_create(2);
    smaug_f64_set(callback, 0, 1); smaug_f64_set_null(callback, 1);
    OK(isnan(smaug_f64_get(NULL, 0, NULL)), "f64 get(serie NULL, status=NULL) -> NaN");
    OK(isnan(smaug_f64_get(callback, 9, NULL)),   "f64 get(OOB, status=NULL) -> NaN");
    OK(isnan(smaug_f64_get(callback, 1, NULL)),   "f64 get(pos NULL, status=NULL) -> NaN");
    smaug_series_i64_t *integer_series_3 = smaug_i64_create(2);
    smaug_i64_set(integer_series_3, 0, 7); smaug_i64_set_null(integer_series_3, 1);
    OK(smaug_i64_get(NULL, 0, NULL) == 0,   "i64 get(serie NULL, status=NULL) -> 0");
    OK(smaug_i64_get(integer_series_3, 9, NULL)   == 0,   "i64 get(OOB, status=NULL) -> 0");
    OK(smaug_i64_get(integer_series_3, 1, NULL)   == 0,   "i64 get(pos NULL, status=NULL) -> 0");

    smaug_f64_free(floating_point_series); smaug_f64_free(callback);
    smaug_i64_free(integer_series); smaug_i64_free(integer_series_2); smaug_i64_free(integer_series_3);
}

/* Guards de input: f64 argsort/sort com s=NULL (f64:359/390) */
static void float64_null_guard_sort(void) {
    OK(smaug_f64_argsort(NULL, true) == NULL, "f64 argsort(NULL) -> NULL");
    OK(smaug_f64_sort(NULL, true)    == NULL, "f64 sort(NULL) -> NULL");
}

/* Guards de input: i64 ops binárias com NULL/tamanho incompatível (i64:23) */
static void int64_null_guard_binop(void) {
    smaug_series_i64_t *left_series = smaug_i64_create(2);
    smaug_i64_set(left_series, 0, 1); smaug_i64_set(left_series, 1, 2);
    OK(smaug_i64_add(NULL, left_series) == NULL, "i64 add(NULL,a) -> NULL");
    OK(smaug_i64_add(left_series, NULL) == NULL, "i64 add(a,NULL) -> NULL");
    OK(smaug_i64_sub(NULL, left_series) == NULL, "i64 sub(NULL,a) -> NULL");
    OK(smaug_i64_mul(NULL, left_series) == NULL, "i64 mul(NULL,a) -> NULL");
    OK(smaug_i64_div(NULL, left_series) == NULL, "i64 div(NULL,a) -> NULL");
    smaug_i64_free(left_series);
}

/* Guards de input: i64 argsort/sort com s=NULL (i64:356/383) */
static void int64_null_guard_sort(void) {
    OK(smaug_i64_argsort(NULL, true) == NULL, "i64 argsort(NULL) -> NULL");
    OK(smaug_i64_sort(NULL, true)    == NULL, "i64 sort(NULL) -> NULL");
}

/* Guards de input + reachable: i64 reduções com s=NULL e size==0 (i64:176/195/232) */
static void int64_reduce_null_and_empty(void) {
    /* NULL */
    OK(smaug_i64_min(NULL, true)  == INT64_MIN, "i64 min(NULL) -> INT64_MIN");
    OK(smaug_i64_max(NULL, true)  == INT64_MIN, "i64 max(NULL) -> INT64_MIN");
    OK(isnan(smaug_i64_mean(NULL, true)),        "i64 mean(NULL) -> NaN");
    OK(isnan(smaug_i64_std(NULL, true)),         "i64 std(NULL) -> NaN");
    /* size==0: fecha o lado reachable do mesmo if */
    smaug_series_i64_t *integer_series = smaug_i64_create(0);
    OK(smaug_i64_min(integer_series, true)  == INT64_MIN, "i64 min(vazia) -> INT64_MIN");
    OK(smaug_i64_max(integer_series, true)  == INT64_MIN, "i64 max(vazia) -> INT64_MIN");
    OK(isnan(smaug_i64_mean(integer_series, true)),        "i64 mean(vazia) -> NaN");
    OK(isnan(smaug_i64_std(integer_series, true)),         "i64 std(vazia) -> NaN");
    smaug_i64_free(integer_series);
}

/* Guards de input: str set com str=NULL, len>0 (str:297) */
static void string_null_guard_set(void) {
    smaug_series_str_t *source_series = smaug_str_create(3);
    assert(source_series);
    smaug_status_t status = smaug_str_set(source_series, 0, NULL, 5);
    OK(status == SMG_ERR_ARGUMENT, "str set(NULL,len>0) -> ARGUMENT");
    smaug_str_free(source_series);
}

/* Guards de input: ops_str NULL target/s (ops_str:41/136) */
static void ops_string_null_guards(void) {
    const char *source_values[] = {"a", "b", "c"};
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);
    /* compare com target=NULL e target_len>0 (ops_str:41) */
    OK(smaug_str_eq(source_series, NULL, 3, NULL) == NULL, "str_eq(target=NULL,len>0) -> NULL");
    OK(smaug_str_lt(source_series, NULL, 3, NULL) == NULL, "str_lt(target=NULL,len>0) -> NULL");
    OK(smaug_str_gt(source_series, NULL, 3, NULL) == NULL, "str_gt(target=NULL,len>0) -> NULL");
    smaug_str_free(source_series);

    /* ops_str:32 — ramo len > target_len em str_cmp_at:
       série com "abc" comparada contra target "ab" (2 bytes) — prefixo igual
       mas elemento é mais longo → return 1 (maior). */
    const char *long_array[] = {"ab", "abc", "z"};
    smaug_series_str_t *source_series_2 = smaug_str_create_from_array(long_array, 3);
    assert(source_series_2);
    uint8_t *string_equal_result = smaug_str_eq(source_series_2, "ab", 2, NULL);
    OK(string_equal_result && string_equal_result[0]==1 && string_equal_result[1]==0, "str_eq: elem mais longo que target nao eh igual");
    free(string_equal_result);
    string_equal_result = smaug_str_gt(source_series_2, "ab", 2, NULL);
    OK(string_equal_result && string_equal_result[0]==0 && string_equal_result[1]==1, "str_gt: 'abc' > 'ab' (len tiebreak)");
    free(string_equal_result);
    /* ops_str:41 branch residual: target=NULL e target_len=0 (não é erro, compara contra "") */
    string_equal_result = smaug_str_eq(source_series_2, NULL, 0, NULL);
    OK(string_equal_result != NULL, "str_eq(target=NULL,len=0) -> válido (compara contra string vazia)");
    free(string_equal_result);
    smaug_str_free(source_series_2);

    /* ops_str:136 — segundo ramo: s!=NULL mas idx==NULL e len>0 */
    OK(smaug_str_take(NULL, NULL, 1) == NULL, "str_take(NULL,NULL,1) -> NULL");
    /* take com s válido, idx=NULL, len>0 */
    const char *text_values[] = {"x", "y"};
    smaug_series_str_t *source_series_3 = smaug_str_create_from_array(text_values, 2);
    OK(smaug_str_take(source_series_3, NULL, 1) == NULL, "str_take(s,NULL,len>0) -> NULL");
    /* branch 5: idx=NULL e len=0 — válido, retorna série vazia */
    smaug_series_str_t *source_series_4 = smaug_str_take(source_series_3, NULL, 0);
    OK(source_series_4 && source_series_4->size == 0, "str_take(s,NULL,0) -> serie vazia");
    smaug_str_free(source_series_4);
    smaug_str_free(source_series_3);
}

/* Reachable: out_mask=NULL nas compares f64 (f64:294/303/306/320/329/332) */
static void float64_compare_no_mask(void) {
    double source_values[] = {1.0, 2.0, 3.0};
    smaug_series_f64_t *floating_point_series = smaug_f64_create_from_array(source_values, 3);
    assert(floating_point_series);
    uint8_t *result;
    /* lt sem máscara: exercita out_mask=NULL e mask=NULL branches */
    result = smaug_f64_lt(floating_point_series, 2.5, NULL);
    OK(result && result[0]==1 && result[1]==1 && result[2]==0, "f64 lt sem out_mask");
    free(result);
    /* eq sem máscara */
    result = smaug_f64_eq(floating_point_series, 2.0, NULL);
    OK(result && result[0]==0 && result[1]==1 && result[2]==0, "f64 eq sem out_mask");
    free(result);
    smaug_f64_free(floating_point_series);

    /* f64:306/332 — ramo !VALID + mask==NULL: série com null, sem out_mask */
    smaug_series_f64_t *floating_point_series_2 = smaug_f64_create(3);
    smaug_f64_set(floating_point_series_2, 0, 1.0); smaug_f64_set_null(floating_point_series_2, 1); smaug_f64_set(floating_point_series_2, 2, 3.0);
    result = smaug_f64_lt(floating_point_series_2, 2.0, NULL);
    OK(result && result[0]==1 && result[1]==0 && result[2]==0, "f64 lt null+no_mask: ramo mask==NULL no else");
    free(result);
    result = smaug_f64_eq(floating_point_series_2, 1.0, NULL);
    OK(result && result[0]==1 && result[1]==0 && result[2]==0, "f64 eq null+no_mask: ramo mask==NULL no else");
    free(result);
    smaug_f64_free(floating_point_series_2);
}

/* Reachable: out_mask=NULL nas compares i64 (i64:292/299/301/304/318/325/327/330) */
static void int64_compare_no_mask(void) {
    int64_t source_values[] = {1, 2, 3};
    smaug_series_i64_t *integer_series = smaug_i64_create_from_array(source_values, 3);
    assert(integer_series);
    uint8_t *result;
    result = smaug_i64_lt(integer_series, 3, NULL);
    OK(result && result[0]==1 && result[1]==1 && result[2]==0, "i64 lt sem out_mask");
    free(result);
    result = smaug_i64_eq(integer_series, 2, NULL);
    OK(result && result[0]==0 && result[1]==1 && result[2]==0, "i64 eq sem out_mask");
    free(result);
    /* série com null + sem máscara: exercita VALID() false + mask==NULL (i64:299/325) */
    smaug_series_i64_t *integer_series_2 = smaug_i64_create(3);
    smaug_i64_set(integer_series_2, 0, 1); smaug_i64_set_null(integer_series_2, 1); smaug_i64_set(integer_series_2, 2, 3);
    result = smaug_i64_lt(integer_series_2, 2, NULL);
    OK(result && result[0]==1 && result[1]==0 && result[2]==0, "i64 lt com null sem out_mask");
    free(result);
    result = smaug_i64_eq(integer_series_2, 1, NULL);
    OK(result && result[0]==1 && result[1]==0 && result[2]==0, "i64 eq com null sem out_mask");
    free(result);
    /* i64:304/330 — ramo !VALID + mask!=NULL (mask[i]=0x00 escrito):
       série com null, COM out_mask → escreve 0x00 na posição nula */
    smaug_mask_t *result_null_mask = NULL;
    result = smaug_i64_lt(integer_series_2, 2, &result_null_mask);
    OK(result && result_null_mask && result_null_mask[1]==0x00, "i64 lt null+mask: mask[null]=0x00");
    free(result); free(result_null_mask); result_null_mask = NULL;
    result = smaug_i64_eq(integer_series_2, 1, &result_null_mask);
    OK(result && result_null_mask && result_null_mask[1]==0x00, "i64 eq null+mask: mask[null]=0x00");
    free(result); free(result_null_mask);
    smaug_i64_free(integer_series); smaug_i64_free(integer_series_2);
}

/* Reachable: i64 reduções all-null e std/mean all-null (i64:224/235/241/247) */
static void int64_reduce_all_null(void) {
    smaug_series_i64_t *integer_series = smaug_i64_create(3);  /* tudo NULL */
    /* mean all-null com ignore_na=false: } else if (!ignore_na) {  (i64:224) */
    OK(isnan(smaug_i64_mean(integer_series, false)), "i64 mean all-null,ignore_na=false -> NaN");
    /* std all-null: isnan(mean) -> return NaN (i64:235) */
    OK(isnan(smaug_i64_std(integer_series, true)),  "i64 std all-null -> NaN");
    OK(isnan(smaug_i64_std(integer_series, false)), "i64 std all-null,ignore_na=false -> NaN");
    smaug_i64_free(integer_series);

    /* i64:241 (VALID true no loop de var) + i64:247 (count>0 → divisão real):
       série mista (válidos E nulls) com ignore_na=true → mean!=NaN → entra no
       loop → VALID=true para os válidos, count>0 → toma o ramo da divisão */
    smaug_series_i64_t *integer_series_2 = smaug_i64_create(3);
    smaug_i64_set(integer_series_2, 0, 4); smaug_i64_set_null(integer_series_2, 1); smaug_i64_set(integer_series_2, 2, 6);
    OK(!isnan(smaug_i64_var(integer_series_2, true)),  "i64 var misto ignore_na=true: VALID+count>0");
    OK(!isnan(smaug_i64_std(integer_series_2, true)),  "i64 std misto ignore_na=true");
    smaug_i64_free(integer_series_2);
}

/* Reachable: f64 std all-null → count==0 (f64:245) */
static void float64_reduce_all_null_standard_deviation(void) {
    smaug_series_f64_t *floating_point_series = smaug_f64_create(3);  /* tudo NULL */
    OK(isnan(smaug_f64_std(floating_point_series, true)),  "f64 std all-null -> NaN");
    OK(isnan(smaug_f64_var(floating_point_series, true)),  "f64 var all-null -> NaN");
    smaug_f64_free(floating_point_series);
}

/* Reachable: série vazia em core/str/bool (core:353, str:83, bool:15/18) */
static void empty_series_edges(void) {
    /* core:353 — i64_cow_detach com size==0: view vazia desvincula sem malloc.
       Disparado por mutação (set/append) em view de tamanho zero. */
    smaug_series_i64_t *integer_series = smaug_i64_create(2);
    smaug_i64_set(integer_series, 0, 1); smaug_i64_set(integer_series, 1, 2);
    smaug_series_i64_t *series_view = smaug_i64_view(integer_series, 0, 0);  /* view vazia */
    assert(series_view && series_view->size == 0 && series_view->meta.is_view);
    smaug_i64_append(series_view, 99);   /* dispara detach com size==0 */
    OK(!series_view->meta.is_view, "i64 view vazia: detach sem malloc");
    smaug_i64_free(integer_series); smaug_i64_free(series_view);

    /* str:83 — clone de série vazia (free do buffer quando size==0) */
    smaug_series_str_t *source_series = smaug_str_create(0);
    smaug_series_str_t *source_series_2 = smaug_str_clone(source_series);
    OK(source_series_2 && source_series_2->size == 0, "str clone(vazia) -> vazia");
    smaug_str_free(source_series); smaug_str_free(source_series_2);

    /* bool:15/18 — alloc_pair com n==0 (série bool vazia) */
    uint8_t  left_values[1]={0}; smaug_mask_t left_null_mask[1]={0xFF};
    uint8_t  right_values[1]={0}; smaug_mask_t right_null_mask[1]={0xFF};
    smaug_mask_t *result_null_mask = NULL;
    uint8_t *and_result = smaug_bool_and(left_values, left_null_mask, right_values, right_null_mask, 0, &result_null_mask);
    OK(and_result != NULL, "bool and(n=0) retorna buffer válido");
    free(and_result); free(result_null_mask);
}

/* Reachable: str edges — out_len=NULL, len==0, first-grow, external_alloc
   (str:156/162/187/216/250/95) */
static void string_reachable_edges(void) {
    const char *source_values[] = {"hello", "world", NULL};
    smaug_series_str_t *source_series = smaug_str_create_from_array(source_values, 3);
    assert(source_series);

    /* str:156 — get com out_len=NULL: pos NULL → *out_len omitido */
    const char *string_get_result = smaug_str_get(source_series, 2, NULL);
    OK(string_get_result == NULL, "str get(null-pos, out_len=NULL) -> NULL sem crash");

    /* str:162 — get com out_len=NULL: pos válida → comprimento omitido */
    string_get_result = smaug_str_get(source_series, 0, NULL);
    OK(string_get_result != NULL, "str get(válida, out_len=NULL) -> ptr não-NULL");

    /* str:250 — if(len>0) memcpy: ramo len==0 em set (string vazia sobrescreve pos) */
    smaug_series_str_t *source_series_2 = smaug_str_create(2);
    smaug_str_set(source_series_2, 0, "hello", 5);
    smaug_str_set(source_series_2, 0, "", 0);   /* set com len==0: sem memcpy */
    size_t output_length = 99;
    const char *string_get_result_2 = smaug_str_get(source_series_2, 0, &output_length);
    OK(string_get_result_2 != NULL && output_length == 0, "str set len==0: string vazia");
    smaug_str_free(source_series_2);

    /* str:297 — branch 2: append(NULL, 0) não é erro (str==NULL mas len==0) */
    smaug_series_str_t *source_series_3 = smaug_str_create(0);
    int all_null_status = smaug_str_append(source_series_3, NULL, 0);
    OK(all_null_status == 0 && source_series_3->size == 1, "str append(NULL,0) ok: string vazia nao-nula");
    smaug_str_free(source_series_3);

    smaug_str_free(source_series);

    /* str:187 — buffer_capacity==0 no first-grow: usa SMAUG_STR_BUFFER_INIT
       create_with_capacity(0,0) → bufcap=SMAUG_STR_BUFFER_INIT (não zero),
       então forçamos via série que começa sem buffer. Usamos o path normal
       de create(1) + set que expande. */
    smaug_series_str_t *source_series_4 = smaug_str_create(1);  /* 1 elem, NULL */
    smaug_str_set(source_series_4, 0, "abcdefghijklmnopqrstuvwxyz", 26); /* força grow */
    OK(smaug_str_get(source_series_4, 0, NULL) != NULL, "str set força grow de buffer");
    smaug_str_free(source_series_4);

    /* str:216 — str_slots_reserve_one com capacity==0 já é exercitado pelo
       af_str_append_null_grow no allocfail; aqui verificamos o path de sucesso:
       clone de série com size>0 → realloc de slots. */
    smaug_series_str_t *source_series_5 = smaug_str_create(1);
    smaug_str_set(source_series_5, 0, "x", 1);
    smaug_series_str_t *source_series_6 = smaug_str_clone(source_series_5);
    OK(source_series_6 && source_series_6->size == 1, "str clone com capacity>0");
    smaug_str_free(source_series_5); smaug_str_free(source_series_6);
}

/* Reachable: ops_str edges — série vazia, tiebreaks (ops_str:32/43/48/145/191/202) */
static void ops_string_reachable_edges(void) {
    /* série vazia: ternários size==0 em malloc (ops_str:43/48/202) */
    smaug_series_str_t *empty = smaug_str_create(0);
    smaug_mask_t *result_null_mask = NULL;
    uint8_t *string_equal_result = smaug_str_eq(empty, "x", 1, &result_null_mask);
    OK(string_equal_result != NULL, "str_eq(vazia) -> buffer válido");
    free(string_equal_result); free(result_null_mask);
    size_t *string_argsort_result = smaug_str_argsort(empty, true);
    OK(string_argsort_result != NULL, "str_argsort(vazia) -> buffer válido");
    free(string_argsort_result);
    smaug_str_free(empty);

    /* ops_str:145 — take com bytes==0 (série de NULLs):
       create_with_capacity(0, bytes?bytes:1) exercita o ternário */
    smaug_series_str_t *nulls = smaug_str_create(3); /* tudo NULL */
    size_t source_values[] = {0, 1};
    smaug_series_str_t *source_series = smaug_str_take(nulls, source_values, 2);
    OK(source_series && source_series->size == 2, "str_take com bytes==0");
    smaug_str_free(nulls); smaug_str_free(source_series);

    /* ops_str:32 — tiebreak de comprimento em cmp_str (len > target_len → return 1):
       série com "ab" e "abc" — prefixo idêntico, mas "abc" é mais longa.
       No argsort, "ab" < "abc" (menor comprimento vem antes): aciona len<target e len>target */
    const char *lendiff[] = {"abc", "ab", "z"};
    smaug_series_str_t *source_series_2 = smaug_str_create_from_array(lendiff, 3);
    size_t *string_argsort_result_2 = smaug_str_argsort(source_series_2, true);
    OK(string_argsort_result_2 != NULL && string_argsort_result_2[0]==1 && string_argsort_result_2[1]==0, "str_argsort: 'ab'<'abc' (len tiebreak)");
    free(string_argsort_result_2);
    smaug_series_str_t *ldsorted = smaug_str_sort(source_series_2, true);
    OK(ldsorted != NULL, "str_sort com len-diff tiebreak");
    smaug_str_free(ldsorted);
    smaug_str_free(source_series_2);

    /* ops_str:191 — tiebreak de índice quando bytes e comprimento iguais (c==0):
       strings idênticas: "a","a","b" → as duas "a" têm c==0 → ia<ib decide ordem */
    const char *text_values[] = {"a", "a", "b"};
    smaug_series_str_t *source_series_3 = smaug_str_create_from_array(text_values, 3);
    size_t *string_argsort_result_3 = smaug_str_argsort(source_series_3, true);
    OK(string_argsort_result_3 != NULL && string_argsort_result_3[0]==0 && string_argsort_result_3[1]==1, "str_argsort tiebreak por índice (estável)");
    free(string_argsort_result_3);
    smaug_str_free(source_series_3);
}

/* 12.23: guards ESSENCIAIS de fronteira publica.
   Auditados empiricamente (removendo o guard e chamando com NULL): estes
   SEGFAULTAM sem a protecao — nao sao defesa redundante como o
   coalesce_scalar (onde o clone(NULL) barra antes). Estavam COV-EXCL-BR com
   "o frontend valida antes", o que contradiz o CONTRATO 10: sao simbolos
   publicos exportados, alcancaveis por qualquer caller C. Cobrir os dois
   ramos do `||`: ponteiro NULL e size divergente. */
static void coalesce_guards_publicos(void) {
    double left_values[3] = {1, 2, 3};
    smaug_series_f64_t *floating_point_series = smaug_f64_create_from_array(left_values, 3);
    smaug_f64_set_null(floating_point_series, 1);
    double right_values[2] = {9, 9};
    smaug_series_f64_t *floating_point_series_2 = smaug_f64_create_from_array(right_values, 2);

    OK(smaug_f64_coalesce(NULL, floating_point_series) == NULL,  "f64_coalesce(NULL, other) -> NULL");
    OK(smaug_f64_coalesce(floating_point_series, NULL) == NULL,  "f64_coalesce(self, NULL) -> NULL");
    OK(smaug_f64_coalesce(floating_point_series, floating_point_series_2)   == NULL,  "f64_coalesce size divergente -> NULL");
    smaug_series_f64_t *coalesce_series = smaug_f64_coalesce(floating_point_series, floating_point_series);
    OK(coalesce_series != NULL,                           "f64_coalesce valido -> serie (controle)");
    smaug_f64_free(coalesce_series); smaug_f64_free(floating_point_series_2); smaug_f64_free(floating_point_series);

    int64_t source_values[3] = {1, 2, 3};
    smaug_series_i64_t *row_index = smaug_i64_create_from_array(source_values, 3);
    smaug_i64_set_null(row_index, 1);
    int64_t source_values_2[2] = {9, 9};
    smaug_series_i64_t *integer_series = smaug_i64_create_from_array(source_values_2, 2);

    OK(smaug_i64_coalesce(NULL, row_index) == NULL,  "i64_coalesce(NULL, other) -> NULL");
    OK(smaug_i64_coalesce(row_index, NULL) == NULL,  "i64_coalesce(self, NULL) -> NULL");
    OK(smaug_i64_coalesce(row_index, integer_series)   == NULL,  "i64_coalesce size divergente -> NULL");
    smaug_series_i64_t *coalesce_series_2 = smaug_i64_coalesce(row_index, row_index);
    OK(coalesce_series_2 != NULL,                           "i64_coalesce valido -> serie (controle)");
    smaug_i64_free(coalesce_series_2); smaug_i64_free(integer_series); smaug_i64_free(row_index);
}

/* 12.24: os guards de `select` sao ESSENCIAIS, nao redundantes.
   A auditoria do 12.18 os classificou errado — o script removia so a primeira
   linha do guard (`if (...)`), deixando o `return NULL;` orfao, que passava a
   executar SEMPRE: a funcao virava `return NULL` incondicional e nunca crashava.
   Artefato do harness, nao do codigo. Removendo o guard INTEIRO: SIGSEGV nos 4.
   O corpo toca os tres ponteiros direto — create(a->size), cond->null_mask no
   laco, e `b` quando cond[i] e' false. Cobrimos os 5 ramos do `||`. */
static void select_guards_publicos(void) {
    double left_values[3] = {1, 2, 3};
    smaug_series_f64_t *floating_point_series  = smaug_f64_create_from_array(left_values, 3);
    smaug_series_f64_t *floating_point_series_2 = smaug_f64_create_from_array(left_values, 3);
    double source_values[2] = {9, 9};
    smaug_series_f64_t *floating_point_series_3 = smaug_f64_create_from_array(source_values, 2);   /* size divergente */
    /* cond com um FALSE no meio: o laco PRECISA tocar `b` */
    smaug_series_bool_t *boolean_series = smaug_bool_create(3);
    smaug_bool_set(boolean_series, 0, 1); smaug_bool_set(boolean_series, 1, 0); smaug_bool_set(boolean_series, 2, 1);
    smaug_series_bool_t *boolean_series_2 = smaug_bool_create(2);               /* size divergente */

    OK(smaug_f64_select(NULL, floating_point_series, floating_point_series_2) == NULL, "f64_select(cond NULL) -> NULL");
    OK(smaug_f64_select(boolean_series, NULL, floating_point_series_2) == NULL, "f64_select(a NULL) -> NULL");
    OK(smaug_f64_select(boolean_series, floating_point_series, NULL) == NULL, "f64_select(b NULL) -> NULL");
    OK(smaug_f64_select(boolean_series_2, floating_point_series, floating_point_series_2) == NULL,  "f64_select(cond->size != a->size) -> NULL");
    OK(smaug_f64_select(boolean_series, floating_point_series, floating_point_series_3) == NULL,   "f64_select(a->size != b->size) -> NULL");
    smaug_series_f64_t *selected_dataset = smaug_f64_select(boolean_series, floating_point_series, floating_point_series_2);
    OK(selected_dataset != NULL && selected_dataset->size == 3,           "f64_select valido -> serie (controle)");
    smaug_f64_free(selected_dataset);
    smaug_f64_free(floating_point_series_3); smaug_f64_free(floating_point_series_2); smaug_f64_free(floating_point_series);

    int64_t source_values_2[3] = {1, 2, 3};
    smaug_series_i64_t *row_index  = smaug_i64_create_from_array(source_values_2, 3);
    smaug_series_i64_t *integer_series = smaug_i64_create_from_array(source_values_2, 3);
    int64_t source_values_3[2] = {9, 9};
    smaug_series_i64_t *integer_series_2 = smaug_i64_create_from_array(source_values_3, 2);

    OK(smaug_i64_select(NULL, row_index, integer_series) == NULL, "i64_select(cond NULL) -> NULL");
    OK(smaug_i64_select(boolean_series, NULL, integer_series) == NULL, "i64_select(a NULL) -> NULL");
    OK(smaug_i64_select(boolean_series, row_index, NULL) == NULL, "i64_select(b NULL) -> NULL");
    OK(smaug_i64_select(boolean_series_2, row_index, integer_series) == NULL,  "i64_select(cond->size != a->size) -> NULL");
    OK(smaug_i64_select(boolean_series, row_index, integer_series_2) == NULL,  "i64_select(a->size != b->size) -> NULL");
    smaug_series_i64_t *selected_dataset_2 = smaug_i64_select(boolean_series, row_index, integer_series);
    OK(selected_dataset_2 != NULL && selected_dataset_2->size == 3,         "i64_select valido -> serie (controle)");
    smaug_i64_free(selected_dataset_2);
    smaug_i64_free(integer_series_2); smaug_i64_free(integer_series); smaug_i64_free(row_index);
    smaug_bool_free(boolean_series_2); smaug_bool_free(boolean_series);
}

int main(void) {
    float64_arith_null_prop();
    int64_arith_null_prop();
    numeric_guard_sweep();
    float64_reduce_null_false();
    float64_reduce_empty();
    float64_reduce_all_null();
    float64_reduce_all_null_standard_deviation();
    float64_binop_guards();
    float64_divide_zero_and_null();
    float64_scalar_edge();
    float64_compare_edge();
    float64_compare_no_mask();
    float64_sort_edge();
    float64_null_guard_sort();
    float64_take_filter_edge();

    int64_reduce_null_false();
    int64_reduce_empty();
    int64_reduce_all_null();
    int64_reduce_null_and_empty();
    int64_binop_guards();
    int64_null_guard_binop();
    int64_divide_zero();
    int64_scalar_compare_sort_edge();
    int64_null_guard_sort();
    int64_compare_no_mask();

    string_null_guard_set();
    ops_string_null_guards();
    empty_series_edges();
    string_reachable_edges();
    ops_string_reachable_edges();

    mutation_status_contract();
    get_status_contract();

    coalesce_guards_publicos();
    select_guards_publicos();

    view_overflow_boundary();
    nan_in_compare();
    int64_overflow_behavior();

    printf("PASS: ops edge (%ld checks)\n", passed_checks);
    return 0;
}
