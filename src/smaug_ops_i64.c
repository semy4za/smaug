#include "../include/smaug_math.h"
#include <math.h>      /* NAN, isnan(), sqrt() — para mean/var/std */
#include <stdint.h>    /* INT64_MIN, INT64_MAX */
#include <stdlib.h>    /* malloc, free, qsort */
#include <stddef.h>

#define VALID(s, i)  ((s)->null_mask[(i)] == 0xFF)
#define INVALID(s,i) ((s)->null_mask[(i)] != 0xFF)

static smaug_series_i64_t *alloc_result(size_t size) {
    extern smaug_series_i64_t *smaug_i64_create(size_t);
    return smaug_i64_create(size);
}

/* ===================================================================
   ARITMÉTICAS — série × série
   NULL propagation: se qualquer operando é NULL, resultado é NULL.
   i64_div: divisão inteira (truncação). Divisor 0 → NULL (evita UB).
   =================================================================== */

smaug_series_i64_t *smaug_i64_add(const smaug_series_i64_t *a,
                                   const smaug_series_i64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_i64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i) && VALID(b, i)) {
            r->data[i]      = a->data[i] + b->data[i];
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_sub(const smaug_series_i64_t *a,
                                   const smaug_series_i64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_i64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i) && VALID(b, i)) {
            r->data[i]      = a->data[i] - b->data[i];
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_mul(const smaug_series_i64_t *a,
                                   const smaug_series_i64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_i64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i) && VALID(b, i)) {
            r->data[i]      = a->data[i] * b->data[i];
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

/* Divisão inteira. Divisor 0 → NULL (evita undefined behavior). */
smaug_series_i64_t *smaug_i64_div(const smaug_series_i64_t *a,
                                   const smaug_series_i64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_i64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i) && VALID(b, i) && b->data[i] != 0) {
            r->data[i]      = a->data[i] / b->data[i];
            r->null_mask[i] = 0xFF;
        }
        /* divisão por zero fica como NULL (null_mask[i] == 0x00) */
    }
    return r;
}

/* ===================================================================
   ARITMÉTICAS — série × escalar
   =================================================================== */

smaug_series_i64_t *smaug_i64_add_scalar(const smaug_series_i64_t *a, int64_t scalar) {
    if (!a) return NULL;

    smaug_series_i64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i)) {
            r->data[i]      = a->data[i] + scalar;
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_sub_scalar(const smaug_series_i64_t *a, int64_t scalar) {
    if (!a) return NULL;

    smaug_series_i64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i)) {
            r->data[i]      = a->data[i] - scalar;
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_mul_scalar(const smaug_series_i64_t *a, int64_t scalar) {
    if (!a) return NULL;

    smaug_series_i64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i)) {
            r->data[i]      = a->data[i] * scalar;
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

/* Escalar 0 → NULL (evita UB de divisão inteira por zero). */
smaug_series_i64_t *smaug_i64_div_scalar(const smaug_series_i64_t *a, int64_t scalar) {
    if (!a) return NULL;
    if (scalar == 0) return alloc_result(a->size);  /* tudo NULL */

    smaug_series_i64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i)) {
            r->data[i]      = a->data[i] / scalar;
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

/* ===================================================================
   REDUÇÕES
   Funções que retornam int64_t NÃO TÊM como representar NAN.
   Com ignore_na=false e qualquer NULL: retorna INT64_MIN como sentinel.
   O Lua layer deve verificar count_nonnull() se precisar tratar isso.
   Funções que retornam double usam NAN normalmente.
   =================================================================== */

int64_t smaug_i64_sum(const smaug_series_i64_t *s, bool ignore_na) {
    if (!s) return 0;

    int64_t sum = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            sum += s->data[i];
        } else if (!ignore_na) {
            return INT64_MIN;   /* sentinel: série contém NULL */
        }
    }
    return sum;
}

int64_t smaug_i64_min(const smaug_series_i64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return INT64_MIN;

    int64_t result     = INT64_MAX;  /* "nenhum valor ainda" */
    bool    found      = false;

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            if (!found || s->data[i] < result) {
                result = s->data[i];
                found  = true;
            }
        } else if (!ignore_na) {
            return INT64_MIN;   /* sentinel */
        }
    }
    return found ? result : INT64_MIN;
}

int64_t smaug_i64_max(const smaug_series_i64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return INT64_MIN;

    int64_t result = INT64_MIN;
    bool    found  = false;

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            if (!found || s->data[i] > result) {
                result = s->data[i];
                found  = true;
            }
        } else if (!ignore_na) {
            return INT64_MIN;   /* sentinel */
        }
    }
    return found ? result : INT64_MIN;
}

/* mean retorna double porque a média de inteiros pode ser fracionária. */
double smaug_i64_mean(const smaug_series_i64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double sum   = 0.0;
    size_t count = 0;

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            sum += (double)s->data[i];
            count++;
        } else if (!ignore_na) {
            return NAN;
        }
    }
    return count ? sum / (double)count : NAN;
}

double smaug_i64_var(const smaug_series_i64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double mean = smaug_i64_mean(s, ignore_na);
    if (isnan(mean)) return NAN;

    double sum_sq = 0.0;
    size_t count  = 0;

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            double d = (double)s->data[i] - mean;
            sum_sq += d * d;
            count++;
        }
    }
    return count ? sum_sq / (double)count : NAN;
}

double smaug_i64_std(const smaug_series_i64_t *s, bool ignore_na) {
    return sqrt(smaug_i64_var(s, ignore_na));
}

/* ===================================================================
   COMPARAÇÕES → uint8_t* (bool array)
   =================================================================== */

uint8_t *smaug_i64_gt(const smaug_series_i64_t *s, int64_t threshold,
                       smaug_mask_t **out_mask) {
    if (!s) return NULL;

    uint8_t      *result = malloc(s->size * sizeof(uint8_t));
    smaug_mask_t *mask   = NULL;
    if (!result) return NULL;

    if (out_mask) {
        mask = malloc(s->size * sizeof(smaug_mask_t));
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            result[i] = s->data[i] > threshold ? 1 : 0;
            if (mask) mask[i] = 0xFF;
        } else {
            result[i] = 0;
            if (mask) mask[i] = 0x00;
        }
    }
    return result;
}

uint8_t *smaug_i64_lt(const smaug_series_i64_t *s, int64_t threshold,
                       smaug_mask_t **out_mask) {
    if (!s) return NULL;

    uint8_t      *result = malloc(s->size * sizeof(uint8_t));
    smaug_mask_t *mask   = NULL;
    if (!result) return NULL;

    if (out_mask) {
        mask = malloc(s->size * sizeof(smaug_mask_t));
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            result[i] = s->data[i] < threshold ? 1 : 0;
            if (mask) mask[i] = 0xFF;
        } else {
            result[i] = 0;
            if (mask) mask[i] = 0x00;
        }
    }
    return result;
}

uint8_t *smaug_i64_eq(const smaug_series_i64_t *s, int64_t threshold,
                       smaug_mask_t **out_mask) {
    if (!s) return NULL;

    uint8_t      *result = malloc(s->size * sizeof(uint8_t));
    smaug_mask_t *mask   = NULL;
    if (!result) return NULL;

    if (out_mask) {
        mask = malloc(s->size * sizeof(smaug_mask_t));
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            result[i] = s->data[i] == threshold ? 1 : 0;
            if (mask) mask[i] = 0xFF;
        } else {
            result[i] = 0;
            if (mask) mask[i] = 0x00;
        }
    }
    return result;
}

/* ===================================================================
   ORDENAÇÃO
   Retorna NULL se houver NULLs na série (posição de NA é indefinida).
   =================================================================== */

typedef struct { size_t idx; int64_t val; } i64_entry_t;

static int cmp_i64_asc(const void *a, const void *b) {
    const i64_entry_t *ea = (const i64_entry_t *)a;
    const i64_entry_t *eb = (const i64_entry_t *)b;
    if (ea->val < eb->val) return -1;
    if (ea->val > eb->val) return  1;
    return 0;
}

static int cmp_i64_desc(const void *a, const void *b) {
    return cmp_i64_asc(b, a);
}

size_t *smaug_i64_argsort(const smaug_series_i64_t *s, bool ascending) {
    if (!s) return NULL;

    for (size_t i = 0; i < s->size; i++) {
        if (INVALID(s, i)) return NULL;
    }

    i64_entry_t *entries = malloc(s->size * sizeof(i64_entry_t));
    if (!entries) return NULL;

    for (size_t i = 0; i < s->size; i++) {
        entries[i].idx = i;
        entries[i].val = s->data[i];
    }

    qsort(entries, s->size, sizeof(i64_entry_t),
          ascending ? cmp_i64_asc : cmp_i64_desc);

    size_t *indices = malloc(s->size * sizeof(size_t));
    if (!indices) { free(entries); return NULL; }

    for (size_t i = 0; i < s->size; i++) indices[i] = entries[i].idx;

    free(entries);
    return indices;
}

smaug_series_i64_t *smaug_i64_sort(const smaug_series_i64_t *s, bool ascending) {
    if (!s) return NULL;

    size_t *indices = smaug_i64_argsort(s, ascending);
    if (!indices) return NULL;

    smaug_series_i64_t *result = smaug_i64_take(s, indices, s->size);
    free(indices);
    return result;
}

/* ===================================================================
   UTILITÁRIOS
   =================================================================== */

size_t smaug_i64_count_nonnull(const smaug_series_i64_t *s) {
    if (!s) return 0;
    size_t count = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) count++;
    }
    return count;
}

smaug_series_i64_t *smaug_i64_take(const smaug_series_i64_t *s,
                                    const size_t *idx, size_t len) {
    if (!s || !idx) return NULL;

    smaug_series_i64_t *r = smaug_i64_create(len);
    if (!r) return NULL;

    for (size_t i = 0; i < len; i++) {
        if (idx[i] >= s->size) {
            smaug_i64_free(r);
            return NULL;
        }
        r->data[i]      = s->data[idx[i]];
        r->null_mask[i] = s->null_mask[idx[i]];
    }
    return r;
}

smaug_series_i64_t *smaug_i64_filter(const smaug_series_i64_t *s,
                                      const uint8_t *mask) {
    if (!s || !mask) return NULL;

    size_t count = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (mask[i]) count++;
    }

    smaug_series_i64_t *r = smaug_i64_create(count);
    if (!r) return NULL;

    size_t j = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (mask[i]) {
            r->data[j]      = s->data[i];
            r->null_mask[j] = s->null_mask[i];
            j++;
        }
    }
    return r;
}
