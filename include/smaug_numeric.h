#ifndef SMAUG_NUMERIC_H
#define SMAUG_NUMERIC_H

/* ===================================================================
   smaug_numeric.h — Operações numéricas (f64 + i64)
   -------------------------------------------------------------------
   Aritmética (série×série e série×escalar), reduções, comparações,
   ordenação e utilitários (count/take/filter). Inclui smaug_core.h.
   Implementado em src/smaug_ops_f64.c e src/smaug_ops_i64.c.
   =================================================================== */

#include "smaug_core.h"

/* ===================== FLOAT64 ===================== */

/* Aritméticas série × série (propagam NA) */
smaug_series_f64_t* smaug_f64_add(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_sub(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_mul(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_div(const smaug_series_f64_t *a, const smaug_series_f64_t *b);

/* Aritméticas série × escalar (escalar não propaga NA) */
smaug_series_f64_t* smaug_f64_add_scalar(const smaug_series_f64_t *a, double scalar);
smaug_series_f64_t* smaug_f64_sub_scalar(const smaug_series_f64_t *a, double scalar);
smaug_series_f64_t* smaug_f64_mul_scalar(const smaug_series_f64_t *a, double scalar);
smaug_series_f64_t* smaug_f64_div_scalar(const smaug_series_f64_t *a, double scalar);

/* coalesce_scalar (null-mask): onde self[i] é nulo, entra value; senão self[i].
   NaN existente preservado (opera sobre máscara). Serve fillna. */
smaug_series_f64_t* smaug_f64_coalesce_scalar(const smaug_series_f64_t *self, double value);

/* coalesce (null-mask, série+série): onde self[i] é nulo entra other[i] (se
   válido); senão self[i]. Ambos nulos → nulo. Serve combine_first. */
smaug_series_f64_t* smaug_f64_coalesce(const smaug_series_f64_t *self, const smaug_series_f64_t *other);

/* select (cond-bool): cond[i] true → a[i], senão (false/NA) → b[i]. Preserva a
   nulidade do operando escolhido. Unifica where/mask/ifelse. */
smaug_series_f64_t* smaug_f64_select(const smaug_series_bool_t *cond,
                                     const smaug_series_f64_t *a,
                                     const smaug_series_f64_t *b);

/* Reduções (var/std são populacionais) */
double smaug_f64_sum (const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_mean(const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_min (const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_max (const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_var (const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_std (const smaug_series_f64_t *s, bool ignore_na);

/* Comparações → uint8_t* (bool array; caller libera com smaug_free) */
uint8_t* smaug_f64_gt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_lt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_eq(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_ge(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_le(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_ne(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);

/* Ordenação (argsort retorna NULL se há nulos; caller libera com smaug_free) */
size_t*             smaug_f64_argsort(const smaug_series_f64_t *s, bool ascending);
smaug_series_f64_t* smaug_f64_sort   (const smaug_series_f64_t *s, bool ascending);

/* Utilitários */
size_t              smaug_f64_count_nonnull(const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_take  (const smaug_series_f64_t *s, const size_t *idx, size_t len);
smaug_series_f64_t* smaug_f64_filter(const smaug_series_f64_t *s, const uint8_t *mask);

/* Janela e redução posicional (Grupo A — Fase 3 Ring 0) */
smaug_series_f64_t* smaug_f64_cumsum (const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_cumprod(const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_cummin (const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_cummax (const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_diff   (const smaug_series_f64_t *s, size_t periods);
smaug_series_f64_t* smaug_f64_shift  (const smaug_series_f64_t *s, int64_t periods);
smaug_series_f64_t* smaug_f64_ffill  (const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_bfill  (const smaug_series_f64_t *s);
size_t              smaug_f64_argmin  (const smaug_series_f64_t *s);  /* 0-based; SIZE_MAX se vazia/toda-null */
size_t              smaug_f64_argmax  (const smaug_series_f64_t *s);

/* Ordenação e rank (Grupo B — Fase 3 Ring 0) */
double* smaug_f64_sorted_nonnull(const smaug_series_f64_t *s, size_t *out_n);  /* caller libera com smaug_free */
double* smaug_f64_rank          (const smaug_series_f64_t *s, int method);     /* 0=avg 1=min 2=max 3=first; NAN=null; caller libera */

/* ===================== INT64 ===================== */

/* Aritméticas série × série */
smaug_series_i64_t* smaug_i64_add(const smaug_series_i64_t *a, const smaug_series_i64_t *b);
smaug_series_i64_t* smaug_i64_sub(const smaug_series_i64_t *a, const smaug_series_i64_t *b);
smaug_series_i64_t* smaug_i64_mul(const smaug_series_i64_t *a, const smaug_series_i64_t *b);
smaug_series_i64_t* smaug_i64_div(const smaug_series_i64_t *a, const smaug_series_i64_t *b); /* divisão inteira; /0 → NULL */

/* Aritméticas série × escalar */
smaug_series_i64_t* smaug_i64_add_scalar(const smaug_series_i64_t *a, int64_t scalar);
smaug_series_i64_t* smaug_i64_sub_scalar(const smaug_series_i64_t *a, int64_t scalar);
smaug_series_i64_t* smaug_i64_mul_scalar(const smaug_series_i64_t *a, int64_t scalar);
smaug_series_i64_t* smaug_i64_div_scalar(const smaug_series_i64_t *a, int64_t scalar);

/* coalesce_scalar (null-mask): onde self[i] é nulo, entra value; senão self[i].
   Resultado sem nulos. Serve fillna. */
smaug_series_i64_t* smaug_i64_coalesce_scalar(const smaug_series_i64_t *self, int64_t value);

/* coalesce (null-mask, série+série): onde self[i] é nulo entra other[i] (se
   válido); senão self[i]. Ambos nulos → nulo. Serve combine_first. */
smaug_series_i64_t* smaug_i64_coalesce(const smaug_series_i64_t *self, const smaug_series_i64_t *other);

/* select (cond-bool): cond[i] true → a[i], senão (false/NA) → b[i]. Preserva a
   nulidade do operando escolhido. Unifica where/mask/ifelse. */
smaug_series_i64_t* smaug_i64_select(const smaug_series_bool_t *cond,
                                     const smaug_series_i64_t *a,
                                     const smaug_series_i64_t *b);

/* Reduções (sum/min/max retornam INT64_MIN como sentinela; mean/var/std → double) */
int64_t smaug_i64_sum(const smaug_series_i64_t *s, bool ignore_na);
int64_t smaug_i64_min(const smaug_series_i64_t *s, bool ignore_na);
int64_t smaug_i64_max(const smaug_series_i64_t *s, bool ignore_na);
double  smaug_i64_mean(const smaug_series_i64_t *s, bool ignore_na);
double  smaug_i64_var (const smaug_series_i64_t *s, bool ignore_na);
double  smaug_i64_std (const smaug_series_i64_t *s, bool ignore_na);

/* Comparações → uint8_t* (caller libera com smaug_free) */
uint8_t* smaug_i64_gt(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
uint8_t* smaug_i64_lt(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
uint8_t* smaug_i64_eq(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
uint8_t* smaug_i64_ge(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
uint8_t* smaug_i64_le(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
uint8_t* smaug_i64_ne(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);

/* Ordenação */
size_t*             smaug_i64_argsort(const smaug_series_i64_t *s, bool ascending);
smaug_series_i64_t* smaug_i64_sort   (const smaug_series_i64_t *s, bool ascending);

/* Utilitários */
size_t              smaug_i64_count_nonnull(const smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_take  (const smaug_series_i64_t *s, const size_t *idx, size_t len);
smaug_series_i64_t* smaug_i64_filter(const smaug_series_i64_t *s, const uint8_t *mask);

/* Janela e redução posicional (Grupo A — Fase 3 Ring 0) */
smaug_series_i64_t* smaug_i64_cumsum (const smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_cumprod(const smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_cummin (const smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_cummax (const smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_diff   (const smaug_series_i64_t *s, size_t periods);
smaug_series_i64_t* smaug_i64_shift  (const smaug_series_i64_t *s, int64_t periods);
smaug_series_i64_t* smaug_i64_ffill  (const smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_bfill  (const smaug_series_i64_t *s);
size_t              smaug_i64_argmin  (const smaug_series_i64_t *s);  /* 0-based; SIZE_MAX se vazia/toda-null */
size_t              smaug_i64_argmax  (const smaug_series_i64_t *s);

/* Ordenação e rank (Grupo B — Fase 3 Ring 0) */
int64_t* smaug_i64_sorted_nonnull(const smaug_series_i64_t *s, size_t *out_n);  /* caller libera com smaug_free */
double*  smaug_i64_rank          (const smaug_series_i64_t *s, int method);     /* mesmo contrato do f64 */

/* ===================== BOOL — seleção, agregação, lógica Kleene =====================
   Operações struct-based sobre smaug_series_bool_t (dtype `bool` de primeira
   classe). Distintas das funções raw de smaug_bool.h, que operam sobre arrays
   (uint8_t*, máscara) e são o legado da BoolSeries — a ser aposentado. Estas
   seguem o padrão dos demais dtypes: recebem/retornam a struct. */
size_t               smaug_bool_count_nonnull(const smaug_series_bool_t *s);
smaug_series_bool_t* smaug_bool_take  (const smaug_series_bool_t *s, const size_t *idx, size_t len);
smaug_series_bool_t* smaug_bool_filter(const smaug_series_bool_t *s, const uint8_t *mask);

/* Agregações (NA ignorado; all de série vazia = true). */
size_t smaug_bool_series_count_true(const smaug_series_bool_t *s);
bool   smaug_bool_series_any(const smaug_series_bool_t *s);
bool   smaug_bool_series_all(const smaug_series_bool_t *s);

/* Lógica Kleene struct→struct. Exigem mesmo tamanho; retornam NULL em
   mismatch/OOM. NULL propaga conforme a tabela-verdade de três valores. */
smaug_series_bool_t* smaug_bool_series_and(const smaug_series_bool_t *a, const smaug_series_bool_t *b);
smaug_series_bool_t* smaug_bool_series_or (const smaug_series_bool_t *a, const smaug_series_bool_t *b);
smaug_series_bool_t* smaug_bool_series_xor(const smaug_series_bool_t *a, const smaug_series_bool_t *b);
smaug_series_bool_t* smaug_bool_series_not(const smaug_series_bool_t *a);

/* Comparação com escalar bool (0/1) → máscara uint8_t + out_mask de nulidade.
   NA → 0 com out_mask NULL. Completa eq/ne para bool (único dtype sem igualdade
   até o item 7). Caller libera result e *out_mask com smaug_free. */
uint8_t* smaug_bool_eq(const smaug_series_bool_t *s, uint8_t threshold, smaug_mask_t **out_mask);
uint8_t* smaug_bool_ne(const smaug_series_bool_t *s, uint8_t threshold, smaug_mask_t **out_mask);

/* Ordenação: false < true. Recusam série com qualquer NULL (retornam NULL),
   como os demais dtypes — posição de NA é indefinida. ascending controla a
   direção. Estável (preserva ordem relativa de iguais). */
size_t*              smaug_bool_argsort(const smaug_series_bool_t *s, bool ascending);
smaug_series_bool_t* smaug_bool_sort   (const smaug_series_bool_t *s, bool ascending);

/* Movimentação de dados agnóstica a tipo (item 7.1): preenche NA com o
   último (ffill) / próximo (bfill) valor válido. Série nova; NA nas bordas
   sem fonte permanecem NA. */
smaug_series_bool_t* smaug_bool_ffill  (const smaug_series_bool_t *s);
smaug_series_bool_t* smaug_bool_bfill  (const smaug_series_bool_t *s);

/* shift(periods): desloca por `periods` posições, com sinal (item 7.1b).
   periods>0 p/ baixo, <0 p/ cima; fonte fora de [0,size) → NA. */
smaug_series_bool_t* smaug_bool_shift  (const smaug_series_bool_t *s, int64_t periods);

/* argmin/argmax(): índice 0-based do menor/maior bool não-NA (false<true);
   SIZE_MAX se vazia/toda-NA (item 7.2a). */
size_t smaug_bool_argmin (const smaug_series_bool_t *s);
size_t smaug_bool_argmax (const smaug_series_bool_t *s);

/* min/max (item 7.2b): bool é ordenável (false<true). Shape 1 (valor+status),
   como smaug_bool_get; SMG_NULL_VALUE = vazia/toda-NA/(ignore_na=false) NA. */
uint8_t smaug_bool_min (const smaug_series_bool_t *s, bool ignore_na, smaug_status_t *status);
uint8_t smaug_bool_max (const smaug_series_bool_t *s, bool ignore_na, smaug_status_t *status);

/* rank (item 7.3): ranking false<true, double* (NAN=NA). method 0=avg 1=min 2=max 3=first. */
double* smaug_bool_rank (const smaug_series_bool_t *s, int method);

#endif /* SMAUG_NUMERIC_H */
