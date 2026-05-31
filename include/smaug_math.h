#ifndef SMAUG_MATH_H
#define SMAUG_MATH_H

#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stddef.h>

/* Tipo opaque para hash table (uso futuro: GroupBy) */
typedef struct smaug_hash_table smaug_hash_table_t;

/* ===== Tipos Base ===== */

/* Máscara de nulos: array paralelo (1 byte por valor)
   Convenção: 0xFF = válido, 0x00 = NA/NULL */
typedef uint8_t smaug_mask_t;

/* Metadados da série */
typedef struct {
    const char *name;        /* Nome da coluna             */
    const char *dtype;       /* "float64", "int64", etc    */
    bool is_view;            /* True se é uma view         */
    bool external_alloc;     /* True se alocado externamente */
} smaug_metadata_t;

/* ===================================================================
   Series Float64
   =================================================================== */

typedef struct {
    double       *data;
    smaug_mask_t *null_mask;
    size_t        size;
    size_t        capacity;
    smaug_metadata_t meta;
} smaug_series_f64_t;

/* --- Lifecycle --- */
smaug_series_f64_t* smaug_f64_create(size_t size);
smaug_series_f64_t* smaug_f64_create_with_capacity(size_t size, size_t capacity);
smaug_series_f64_t* smaug_f64_create_from_array(const double *array, size_t len);
void                smaug_f64_free(smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_clone(const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_view(smaug_series_f64_t *s, size_t start, size_t len);

/* --- Getters / Setters --- */
double smaug_f64_get(smaug_series_f64_t *s, size_t idx);        /* NAN se nulo */
void   smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val);
void   smaug_f64_set_null(smaug_series_f64_t *s, size_t idx);
bool   smaug_f64_is_null(smaug_series_f64_t *s, size_t idx);

/* --- Append dinâmico --- */
int smaug_f64_append(smaug_series_f64_t *s, double val);   /* 0 = ok, -1 = erro */
int smaug_f64_append_null(smaug_series_f64_t *s);

/* --- Aritméticas série × série --- */
smaug_series_f64_t* smaug_f64_add(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_sub(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_mul(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_div(const smaug_series_f64_t *a, const smaug_series_f64_t *b);

/* --- Aritméticas série × escalar --- */
smaug_series_f64_t* smaug_f64_add_scalar(const smaug_series_f64_t *a, double scalar);
smaug_series_f64_t* smaug_f64_sub_scalar(const smaug_series_f64_t *a, double scalar);
smaug_series_f64_t* smaug_f64_mul_scalar(const smaug_series_f64_t *a, double scalar);
smaug_series_f64_t* smaug_f64_div_scalar(const smaug_series_f64_t *a, double scalar);

/* --- Reduções --- */
double smaug_f64_sum (const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_mean(const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_min (const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_max (const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_var (const smaug_series_f64_t *s, bool ignore_na); /* variância populacional */
double smaug_f64_std (const smaug_series_f64_t *s, bool ignore_na); /* desvio padrão populacional */

/* --- Comparações → uint8_t* (bool array, caller libera) --- */
uint8_t* smaug_f64_gt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_lt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_eq(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);

/* --- Ordenação --- */
size_t*             smaug_f64_argsort(const smaug_series_f64_t *s, bool ascending); /* NULL se há nulos */
smaug_series_f64_t* smaug_f64_sort   (const smaug_series_f64_t *s, bool ascending);

/* --- Utilitários --- */
size_t              smaug_f64_count_nonnull(const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_take  (const smaug_series_f64_t *s, const size_t *idx, size_t len);
smaug_series_f64_t* smaug_f64_filter(const smaug_series_f64_t *s, const uint8_t *mask);

/* ===================================================================
   Series Int64
   =================================================================== */

typedef struct {
    int64_t      *data;
    smaug_mask_t *null_mask;
    size_t        size;
    size_t        capacity;
    smaug_metadata_t meta;
} smaug_series_i64_t;

/* --- Lifecycle --- */
smaug_series_i64_t* smaug_i64_create(size_t size);
smaug_series_i64_t* smaug_i64_create_with_capacity(size_t size, size_t capacity);
smaug_series_i64_t* smaug_i64_create_from_array(const int64_t *array, size_t len);
void                smaug_i64_free(smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_clone(const smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_view(smaug_series_i64_t *s, size_t start, size_t len);

/* --- Getters / Setters --- */
int64_t smaug_i64_get(smaug_series_i64_t *s, size_t idx);      /* caller verifica is_null() */
void    smaug_i64_set(smaug_series_i64_t *s, size_t idx, int64_t val);
void    smaug_i64_set_null(smaug_series_i64_t *s, size_t idx);
bool    smaug_i64_is_null(smaug_series_i64_t *s, size_t idx);

/* --- Append dinâmico --- */
int smaug_i64_append(smaug_series_i64_t *s, int64_t val);
int smaug_i64_append_null(smaug_series_i64_t *s);

/* --- Aritméticas série × série --- */
smaug_series_i64_t* smaug_i64_add(const smaug_series_i64_t *a, const smaug_series_i64_t *b);
smaug_series_i64_t* smaug_i64_sub(const smaug_series_i64_t *a, const smaug_series_i64_t *b);
smaug_series_i64_t* smaug_i64_mul(const smaug_series_i64_t *a, const smaug_series_i64_t *b);
smaug_series_i64_t* smaug_i64_div(const smaug_series_i64_t *a, const smaug_series_i64_t *b); /* divisão inteira */

/* --- Aritméticas série × escalar --- */
smaug_series_i64_t* smaug_i64_add_scalar(const smaug_series_i64_t *a, int64_t scalar);
smaug_series_i64_t* smaug_i64_sub_scalar(const smaug_series_i64_t *a, int64_t scalar);
smaug_series_i64_t* smaug_i64_mul_scalar(const smaug_series_i64_t *a, int64_t scalar);
smaug_series_i64_t* smaug_i64_div_scalar(const smaug_series_i64_t *a, int64_t scalar);

/* --- Reduções --- */
int64_t smaug_i64_sum(const smaug_series_i64_t *s, bool ignore_na); /* INT64_MIN se nulo + !ignore_na */
int64_t smaug_i64_min(const smaug_series_i64_t *s, bool ignore_na);
int64_t smaug_i64_max(const smaug_series_i64_t *s, bool ignore_na);
double  smaug_i64_mean(const smaug_series_i64_t *s, bool ignore_na); /* double: média pode ser fracionária */
double  smaug_i64_var (const smaug_series_i64_t *s, bool ignore_na);
double  smaug_i64_std (const smaug_series_i64_t *s, bool ignore_na);

/* --- Comparações → uint8_t* (bool array, caller libera) --- */
uint8_t* smaug_i64_gt(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
uint8_t* smaug_i64_lt(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
uint8_t* smaug_i64_eq(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);

/* --- Ordenação --- */
size_t*             smaug_i64_argsort(const smaug_series_i64_t *s, bool ascending);
smaug_series_i64_t* smaug_i64_sort   (const smaug_series_i64_t *s, bool ascending);

/* --- Utilitários --- */
size_t              smaug_i64_count_nonnull(const smaug_series_i64_t *s);
smaug_series_i64_t* smaug_i64_take  (const smaug_series_i64_t *s, const size_t *idx, size_t len);
smaug_series_i64_t* smaug_i64_filter(const smaug_series_i64_t *s, const uint8_t *mask);

#endif /* SMAUG_MATH_H */
