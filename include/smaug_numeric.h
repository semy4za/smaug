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

/* Ordenação (argsort retorna NULL se há nulos; caller libera com smaug_free) */
size_t*             smaug_f64_argsort(const smaug_series_f64_t *s, bool ascending);
smaug_series_f64_t* smaug_f64_sort   (const smaug_series_f64_t *s, bool ascending);

/* Utilitários */
size_t              smaug_f64_count_nonnull(const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_take  (const smaug_series_f64_t *s, const size_t *idx, size_t len);
smaug_series_f64_t* smaug_f64_filter(const smaug_series_f64_t *s, const uint8_t *mask);

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

/* Ordenação */
size_t*             smaug_i64_argsort(const smaug_series_i64_t *s, bool ascending);
smaug_series_i64_t* smaug_i64_sort   (const smaug_series_i64_t *s, bool ascending);

/* Utilitários */
size_t              smaug_i64_count_nonnull(const smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_take  (const smaug_series_i64_t *s, const size_t *idx, size_t len);
smaug_series_i64_t* smaug_i64_filter(const smaug_series_i64_t *s, const uint8_t *mask);

#endif /* SMAUG_NUMERIC_H */
