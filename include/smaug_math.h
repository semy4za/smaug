#ifndef SMAUG_MATH_H
#define SMAUG_MATH_H

#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stddef.h>
#include <math.h>

/* ===== Tipos Base ===== */

typedef uint8_t smaug_mask_t;

// Metadados da série
typedef struct {
    const char *name;       /* Nome da coluna */
    const char *dtype;      /* 'float64', 'int64', etc */
    bool is_view;           /* True se é uma view*/
    bool external_alloc;    /* True se alocado externamente */
} smaug_metadata_t;

// Series Float64

typedef struct {
    double *data;
    smaug_mask_t *null_mask;
    size_t size;
    size_t capacity;
    smaug_metadata_t meta;
} smaug_series_f64_t;

// Construtores e Desconstrutores
smaug_series_f64_t* smaug_f64_create(size_t size);
smaug_series_f64_t* smaug_f64_create_with_capacity(size_t size, size_t capacity);
void smaug_f64_free(smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_clone(const smaug_series_f64_t *s);

// Getters/Setters
double smaug_f64_get(smaug_series_f64_t *s, size_t idx);
void smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val);
void smaug_f64_set_null(smaug_series_f64_t *s, size_t idx);
bool smaug_f64_is_null(smaug_series_f64_t *s, size_t idx);

// Append dinâmico
int smaug_f64_append(smaug_series_f64_t *s, double val);
int smaug_f64_append_null(smaug_series_f64_t *s);

// Operações aritméticas
smaug_series_f64_t* smaug_f64_add(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_mul_scalar(const smaug_series_f64_t *a, double scalar);

// Reduções
double smaug_f64_sum(const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_mean(const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_min(const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_max(const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_std(const smaug_series_f64_t *s, bool ignore_na);

// Comparações
uint8_t* smaug_f64_gt(const smaug_series_f64_t *s, double threshold);

//Contar valores não-nulos
size_t smaug_f64_count_nonnull(const smaug_series_f64_t *s);

// Series Int64

typedef struct {
    int64_t *data;
    smaug_mask_t *null_mask;
    size_t size;
    size_t capacity;
    smaug_metadata_t meta;
} smaug_series_i64_t;

smaug_series_i64_t* smaug_i64_create(size_t size);
void smaug_i64_free(smaug_series_i64_t *s);
int64_t smaug_i64_get(smaug_series_i64_t *s, size_t idx);
void smaug_i64_set(smaug_series_i64_t *s, size_t idx, int64_t val);
int64_t smaug_i64_sum(const smaug_series_i64_t *s, bool ignore_na);

#endif /* SMAUG_MATH_H */