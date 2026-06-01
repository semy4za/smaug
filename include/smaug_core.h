#ifndef SMAUG_CORE_H
#define SMAUG_CORE_H

/* ===================================================================
   smaug_core.h — Lifecycle e acesso
   -------------------------------------------------------------------
   create/free/clone/view, getters/setters, append dinâmico (f64 + i64),
   e smaug_free (liberação de buffers crus). Inclui smaug_types.h.
   Implementado em src/smaug_core.c.
   =================================================================== */

#include "smaug_types.h"

/* -------------------------------------------------------------------
   Liberação de buffers crus (uint8_t* de comparações/bool ops, size_t* de
   argsort) devolvidos pelo backend. Use SEMPRE em vez da free() da libc:
   garante liberação no mesmo runtime/heap que alocou (essencial no Windows,
   onde a DLL tem seu próprio runtime C).
   ------------------------------------------------------------------- */
void smaug_free(void *ptr);

/* ===================== FLOAT64 — Lifecycle ===================== */
smaug_series_f64_t* smaug_f64_create(size_t size);
smaug_series_f64_t* smaug_f64_create_with_capacity(size_t size, size_t capacity);
smaug_series_f64_t* smaug_f64_create_from_array(const double *array, size_t len);
void                smaug_f64_free(smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_clone(const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_view(smaug_series_f64_t *s, size_t start, size_t len);

/* Getters / Setters */
double smaug_f64_get(smaug_series_f64_t *s, size_t idx);        /* NAN se nulo */
void   smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val);
void   smaug_f64_set_null(smaug_series_f64_t *s, size_t idx);
bool   smaug_f64_is_null(smaug_series_f64_t *s, size_t idx);

/* Append dinâmico (0 = ok, -1 = erro) */
int smaug_f64_append(smaug_series_f64_t *s, double val);
int smaug_f64_append_null(smaug_series_f64_t *s);

/* ===================== INT64 — Lifecycle ===================== */
smaug_series_i64_t* smaug_i64_create(size_t size);
smaug_series_i64_t* smaug_i64_create_with_capacity(size_t size, size_t capacity);
smaug_series_i64_t* smaug_i64_create_from_array(const int64_t *array, size_t len);
void                smaug_i64_free(smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_clone(const smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_view(smaug_series_i64_t *s, size_t start, size_t len);

/* Getters / Setters */
int64_t smaug_i64_get(smaug_series_i64_t *s, size_t idx);      /* caller verifica is_null() */
void    smaug_i64_set(smaug_series_i64_t *s, size_t idx, int64_t val);
void    smaug_i64_set_null(smaug_series_i64_t *s, size_t idx);
bool    smaug_i64_is_null(smaug_series_i64_t *s, size_t idx);

/* Append dinâmico */
int smaug_i64_append(smaug_series_i64_t *s, int64_t val);
int smaug_i64_append_null(smaug_series_i64_t *s);

#endif /* SMAUG_CORE_H */
