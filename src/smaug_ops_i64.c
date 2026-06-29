#include "../include/smaug_numeric.h"
#include <math.h>      /* NAN, isnan(), sqrt() — para mean/var/std */
#include <stdint.h>    /* INT64_MIN, INT64_MAX */
#include <stdlib.h>    /* malloc, free, qsort */
#include <stddef.h>


/* smaug_i64_create vem de smaug_core.h (incluído via smaug_numeric.h). */
static smaug_series_i64_t *alloc_result(size_t size) {
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
        if (SMAUG_VALID(a->null_mask, i) && SMAUG_VALID(b->null_mask, i)) {
            r->data[i]      = a->data[i] + b->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
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
        if (SMAUG_VALID(a->null_mask, i) && SMAUG_VALID(b->null_mask, i)) {
            r->data[i]      = a->data[i] - b->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
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
        if (SMAUG_VALID(a->null_mask, i) && SMAUG_VALID(b->null_mask, i)) {
            r->data[i]      = a->data[i] * b->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
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
        if (SMAUG_VALID(a->null_mask, i) && SMAUG_VALID(b->null_mask, i) && b->data[i] != 0) {
            r->data[i]      = a->data[i] / b->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
        /* divisão por zero fica como NULL (null_mask[i] == SMAUG_MASK_NULL) */
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
        if (SMAUG_VALID(a->null_mask, i)) {
            r->data[i]      = a->data[i] + scalar;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_sub_scalar(const smaug_series_i64_t *a, int64_t scalar) {
    if (!a) return NULL;

    smaug_series_i64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i)) {
            r->data[i]      = a->data[i] - scalar;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_mul_scalar(const smaug_series_i64_t *a, int64_t scalar) {
    if (!a) return NULL;

    smaug_series_i64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i)) {
            r->data[i]      = a->data[i] * scalar;
            r->null_mask[i] = SMAUG_MASK_VALID;
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
        if (SMAUG_VALID(a->null_mask, i)) {
            r->data[i]      = a->data[i] / scalar;
            r->null_mask[i] = SMAUG_MASK_VALID;
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
        if (SMAUG_VALID(s->null_mask, i)) {
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
        if (SMAUG_VALID(s->null_mask, i)) {
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
        if (SMAUG_VALID(s->null_mask, i)) {
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
        if (SMAUG_VALID(s->null_mask, i)) {
            sum += (double)s->data[i];
            count++;
        } else if (!ignore_na) {
            return NAN;
        }
    }
    return count ? sum / (double)count : NAN;
}

/* Variância amostral (ddof=1): Σ(xi - mean)² / (n-1); NaN para n<2.
   Alinha com cov/skew/groupby e pandas. */
double smaug_i64_var(const smaug_series_i64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double mean = smaug_i64_mean(s, ignore_na);
    if (isnan(mean)) return NAN;

    double sum_sq = 0.0;
    size_t count  = 0;

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            double d = (double)s->data[i] - mean;
            sum_sq += d * d;
            count++;
        }
    }
    return count >= 2 ? sum_sq / (double)(count - 1) : NAN;  /* amostral: n<2 indefinido */
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
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] > threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
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
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] < threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
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
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] == threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

uint8_t *smaug_i64_ge(const smaug_series_i64_t *s, int64_t threshold,
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
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] >= threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

uint8_t *smaug_i64_le(const smaug_series_i64_t *s, int64_t threshold,
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
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] <= threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

uint8_t *smaug_i64_ne(const smaug_series_i64_t *s, int64_t threshold,
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
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] != threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
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
        if (SMAUG_NULL(s->null_mask, i)) return NULL;
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
        if (SMAUG_VALID(s->null_mask, i)) count++;
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

/* ===================================================================
   Grupo A — Operações de janela e redução posicional (Fase 3 Ring 0)
   Contrato idêntico ao f64, adaptado para int64_t.
   i64 overflow faz wrap (complemento de 2) — contrato documentado.
   =================================================================== */

smaug_series_i64_t *smaug_i64_cumsum(const smaug_series_i64_t *s) {
    if (!s) return NULL;
    smaug_series_i64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    int64_t acc = 0;
    int null_seen = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (null_seen || SMAUG_NULL(s->null_mask, i)) {
            null_seen = 1;
        } else {
            acc += s->data[i];   /* wrap-around intencional (contrato i64) */
            r->data[i]      = acc;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_cumprod(const smaug_series_i64_t *s) {
    if (!s) return NULL;
    smaug_series_i64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    int64_t acc = 1;
    int null_seen = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (null_seen || SMAUG_NULL(s->null_mask, i)) {
            null_seen = 1;
        } else {
            acc *= s->data[i];   /* wrap-around intencional */
            r->data[i]      = acc;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_cummin(const smaug_series_i64_t *s) {
    if (!s) return NULL;
    smaug_series_i64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    int has_val = 0;
    int64_t cur = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_NULL(s->null_mask, i)) continue;
        int64_t v = s->data[i];
        if (!has_val || v < cur) { cur = v; has_val = 1; }
        r->data[i]      = cur;
        r->null_mask[i] = SMAUG_MASK_VALID;
    }
    return r;
}

smaug_series_i64_t *smaug_i64_cummax(const smaug_series_i64_t *s) {
    if (!s) return NULL;
    smaug_series_i64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    int has_val = 0;
    int64_t cur = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_NULL(s->null_mask, i)) continue;
        int64_t v = s->data[i];
        if (!has_val || v > cur) { cur = v; has_val = 1; }
        r->data[i]      = cur;
        r->null_mask[i] = SMAUG_MASK_VALID;
    }
    return r;
}

smaug_series_i64_t *smaug_i64_diff(const smaug_series_i64_t *s, size_t periods) {
    if (!s) return NULL;
    smaug_series_i64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    for (size_t i = periods; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i) && SMAUG_VALID(s->null_mask, i - periods)) {
            r->data[i]      = s->data[i] - s->data[i - periods];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_shift(const smaug_series_i64_t *s, int64_t periods) {
    if (!s) return NULL;
    smaug_series_i64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    /* create já zera null_mask; |periods| >= size → série toda NA (evita
       overflow e atalha o caso comum). Ver smaug_f64_shift p/ semântica. */
    if (periods <= -(int64_t)s->size || periods >= (int64_t)s->size) return r;
    for (size_t i = 0; i < s->size; i++) {
        int64_t src = (int64_t)i - periods;
        if (src >= 0 && (size_t)src < s->size) {
            r->data[i]      = s->data[src];
            r->null_mask[i] = s->null_mask[src];
        }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_ffill(const smaug_series_i64_t *s) {
    if (!s) return NULL;
    smaug_series_i64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    int has_last = 0;
    int64_t last = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) { last = s->data[i]; has_last = 1; }
        if (has_last) { r->data[i] = last; r->null_mask[i] = SMAUG_MASK_VALID; }
    }
    return r;
}

smaug_series_i64_t *smaug_i64_bfill(const smaug_series_i64_t *s) {
    if (!s) return NULL;
    smaug_series_i64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    int has_next = 0;
    int64_t next = 0;
    for (size_t i = s->size; i-- > 0; ) {
        if (SMAUG_VALID(s->null_mask, i)) { next = s->data[i]; has_next = 1; }
        if (has_next) { r->data[i] = next; r->null_mask[i] = SMAUG_MASK_VALID; }
    }
    return r;
}

size_t smaug_i64_argmin(const smaug_series_i64_t *s) {
    if (!s || s->size == 0) return SIZE_MAX;
    size_t best_i = SIZE_MAX;
    int64_t best_v = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            if (best_i == SIZE_MAX || s->data[i] < best_v) {
                best_v = s->data[i]; best_i = i;
            }
        }
    }
    return best_i;
}

size_t smaug_i64_argmax(const smaug_series_i64_t *s) {
    if (!s || s->size == 0) return SIZE_MAX;
    size_t best_i = SIZE_MAX;
    int64_t best_v = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            if (best_i == SIZE_MAX || s->data[i] > best_v) {
                best_v = s->data[i]; best_i = i;
            }
        }
    }
    return best_i;
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

/* ===================================================================
   Grupo B — sorted_nonnull e rank (Fase 3 Ring 0)
   =================================================================== */

static int cmp_i64(const void *a, const void *b) {
    int64_t da = *(const int64_t *)a, db = *(const int64_t *)b;
    return (da > db) - (da < db);
}

/* smaug_i64_sorted_nonnull: coleta não-nulos em array int64_t ordenado.
   Contrato idêntico ao f64. Caller libera com smaug_free. */
int64_t *smaug_i64_sorted_nonnull(const smaug_series_i64_t *s, size_t *out_n) {
    if (!s || !out_n) return NULL;
    size_t n = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) n++;
    }
    *out_n = n;
    if (n == 0) return NULL;

    int64_t *arr = malloc(n * sizeof(int64_t));
    if (!arr) return NULL;

    size_t j = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) arr[j++] = s->data[i];
    }
    qsort(arr, n, sizeof(int64_t), cmp_i64);
    return arr;
}

static int cmp_i64_rank_pair(const void *a, const void *b) {
    const i64_entry_t *pa = (const i64_entry_t *)a, *pb = (const i64_entry_t *)b;
    /* compara o valor como int64 (sem conversão para double — preserva
       precisão total acima de 2^53) e desempata pelo índice original
       (size_t), mantendo a ordenação estável. */
    if (pa->val != pb->val) return (pa->val > pb->val) - (pa->val < pb->val);
    return (pa->idx > pb->idx) - (pa->idx < pb->idx);
}

/* rank i64: ordena por valor int64 direto (mesma lógica de comparação do
   argsort i64). Contrato e método idênticos ao f64. */
double *smaug_i64_rank(const smaug_series_i64_t *s, int method) {
    if (!s) return NULL;
    size_t n = s->size;

    double *result = malloc(n * sizeof(double));
    if (!result) return NULL;

    for (size_t i = 0; i < n; i++) result[i] = NAN;

    size_t m = 0;
    for (size_t i = 0; i < n; i++) {
        if (SMAUG_VALID(s->null_mask, i)) m++;
    }
    if (m == 0) return result;

    i64_entry_t *pairs = malloc(m * sizeof(*pairs));
    if (!pairs) { free(result); return NULL; }

    size_t j = 0;
    for (size_t i = 0; i < n; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            pairs[j].val = s->data[i];
            pairs[j].idx = i;
            j++;
        }
    }
    qsort(pairs, m, sizeof(*pairs), cmp_i64_rank_pair);

    size_t p = 0;
    while (p < m) {
        size_t q = p;
        while (q + 1 < m && pairs[q+1].val == pairs[p].val) q++;

        double r_min = (double)(p + 1);
        double r_max = (double)(q + 1);

        for (size_t k = p; k <= q; k++) {
            size_t orig_i = pairs[k].idx;
            double rank_val;
            switch (method) {
                case 1:  rank_val = r_min;                   break;
                case 2:  rank_val = r_max;                   break;
                case 3:  rank_val = (double)(k + 1);         break;
                default: rank_val = (r_min + r_max) / 2.0;  break;
            }
            result[orig_i] = rank_val;
        }
        p = q + 1;
    }

    free(pairs);
    return result;
}

