#include "../include/smaug_numeric.h"
#include <math.h>      /* NAN, isnan(), sqrt() */
#include <stdlib.h>    /* malloc, free, qsort */
#include <stddef.h>

/* ===================================================================
   Macros de null-check para manter os loops legíveis
   =================================================================== */
#define VALID(s, i)  ((s)->null_mask[(i)] == 0xFF)
#define INVALID(s,i) ((s)->null_mask[(i)] != 0xFF)

/* ===================================================================
   Helpers de alocação de resultado
   =================================================================== */

/* Aloca uma nova série f64 com todos os elementos marcados como NULL.
   Operações preenchem apenas as posições válidas.
   smaug_f64_create vem de smaug_core.h (incluído via smaug_numeric.h). */
static smaug_series_f64_t *alloc_result(size_t size) {
    return smaug_f64_create(size);
}

/* ===================================================================
   ARITMÉTICAS — série × série
   Propagação de NULL: se qualquer operando é NULL, resultado é NULL.
   =================================================================== */

smaug_series_f64_t *smaug_f64_add(const smaug_series_f64_t *a,
                                   const smaug_series_f64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i) && VALID(b, i)) {
            r->data[i]      = a->data[i] + b->data[i];
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_sub(const smaug_series_f64_t *a,
                                   const smaug_series_f64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i) && VALID(b, i)) {
            r->data[i]      = a->data[i] - b->data[i];
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_mul(const smaug_series_f64_t *a,
                                   const smaug_series_f64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i) && VALID(b, i)) {
            r->data[i]      = a->data[i] * b->data[i];
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_div(const smaug_series_f64_t *a,
                                   const smaug_series_f64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i) && VALID(b, i) && b->data[i] != 0.0) {
            r->data[i]      = a->data[i] / b->data[i];
            r->null_mask[i] = 0xFF;
        }
        /* div/0 → NULL (previsível; evita ±Inf/NaN silenciosos) */
    }
    return r;
}

/* ===================================================================
   ARITMÉTICAS — série × escalar
   NULL se elemento é NULL; escalar não propaga NULL.
   =================================================================== */

smaug_series_f64_t *smaug_f64_add_scalar(const smaug_series_f64_t *a, double scalar) {
    if (!a) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i)) {
            r->data[i]      = a->data[i] + scalar;
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_sub_scalar(const smaug_series_f64_t *a, double scalar) {
    if (!a) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i)) {
            r->data[i]      = a->data[i] - scalar;
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_mul_scalar(const smaug_series_f64_t *a, double scalar) {
    if (!a) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (VALID(a, i)) {
            r->data[i]      = a->data[i] * scalar;
            r->null_mask[i] = 0xFF;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_div_scalar(const smaug_series_f64_t *a, double scalar) {
    if (!a) return NULL;
    if (scalar == 0.0) return alloc_result(a->size);  /* tudo NULL — igual ao i64 */

    smaug_series_f64_t *r = alloc_result(a->size);
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
   ignore_na=false: retorna NAN ao encontrar o primeiro NULL.
   ignore_na=true:  pula NULLs.
   =================================================================== */

double smaug_f64_sum(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s) return NAN;

    double sum = 0.0;
    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            sum += s->data[i];
        } else if (!ignore_na) {
            return NAN;
        }
    }
    return sum;
}

double smaug_f64_mean(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double sum   = 0.0;
    size_t count = 0;

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            sum += s->data[i];
            count++;
        } else if (!ignore_na) {
            return NAN;
        }
    }

    return count ? sum / (double)count : NAN;
}

double smaug_f64_min(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double result = NAN;

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            if (isnan(result) || s->data[i] < result)
                result = s->data[i];
        } else if (!ignore_na) {
            return NAN;
        }
    }
    return result;  /* NAN se nenhum elemento válido */
}

double smaug_f64_max(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double result = NAN;

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            if (isnan(result) || s->data[i] > result)
                result = s->data[i];
        } else if (!ignore_na) {
            return NAN;
        }
    }
    return result;
}

/* Variância populacional: Σ(xi - mean)² / n  (dois passos, numericamente estável) */
double smaug_f64_var(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double mean = smaug_f64_mean(s, ignore_na);
    if (isnan(mean)) return NAN;

    double sum_sq = 0.0;
    size_t count  = 0;

    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) {
            double d = s->data[i] - mean;
            sum_sq += d * d;
            count++;
        }
    }

    return count ? sum_sq / (double)count : NAN;  /* COV-EXCL-BR: count==0 inalcancavel: mean nao-NaN implica count>0 */
}

double smaug_f64_std(const smaug_series_f64_t *s, bool ignore_na) {
    return sqrt(smaug_f64_var(s, ignore_na));
}

/* ===================================================================
   COMPARAÇÕES → uint8_t* (bool array)
   out_mask: ponteiro de saída para a null_mask do resultado (pode ser NULL).
   Caller é responsável por free() do array retornado e do *out_mask.
   NULL de entrada → resultado NULL naquela posição.
   =================================================================== */


uint8_t *smaug_f64_gt(const smaug_series_f64_t *s, double threshold,
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

uint8_t *smaug_f64_lt(const smaug_series_f64_t *s, double threshold,
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

uint8_t *smaug_f64_eq(const smaug_series_f64_t *s, double threshold,
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

uint8_t *smaug_f64_ge(const smaug_series_f64_t *s, double threshold,
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
            result[i] = s->data[i] >= threshold ? 1 : 0;
            if (mask) mask[i] = 0xFF;
        } else {
            result[i] = 0;
            if (mask) mask[i] = 0x00;
        }
    }
    return result;
}

uint8_t *smaug_f64_le(const smaug_series_f64_t *s, double threshold,
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
            result[i] = s->data[i] <= threshold ? 1 : 0;
            if (mask) mask[i] = 0xFF;
        } else {
            result[i] = 0;
            if (mask) mask[i] = 0x00;
        }
    }
    return result;
}

uint8_t *smaug_f64_ne(const smaug_series_f64_t *s, double threshold,
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
            result[i] = s->data[i] != threshold ? 1 : 0;
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
   argsort/sort retornam NULL se a série contém NULLs (posição de NA
   é indefinida). Use dropna() antes, ou filtre com count_nonnull().
   =================================================================== */

typedef struct { size_t idx; double val; } f64_entry_t;

static int cmp_f64_asc(const void *a, const void *b) {
    const f64_entry_t *ea = (const f64_entry_t *)a;
    const f64_entry_t *eb = (const f64_entry_t *)b;
    if (ea->val < eb->val) return -1;
    if (ea->val > eb->val) return  1;
    return 0;
}

static int cmp_f64_desc(const void *a, const void *b) {
    return cmp_f64_asc(b, a);
}

size_t *smaug_f64_argsort(const smaug_series_f64_t *s, bool ascending) {
    if (!s) return NULL;

    /* Falha se houver qualquer NULL ou NaN. NaN é um valor presente, mas sem
       ordem bem-definida (toda comparação com NaN é false), então ordenar uma
       série com NaN produziria resultado indefinido. Contrato: sort/argsort
       recusam NaN além de null (ver Roadmap, "Contrato de valores especiais"). */
    for (size_t i = 0; i < s->size; i++) {
        if (INVALID(s, i) || isnan(s->data[i])) return NULL;
    }

    f64_entry_t *entries = malloc(s->size * sizeof(f64_entry_t));
    if (!entries) return NULL;

    for (size_t i = 0; i < s->size; i++) {
        entries[i].idx = i;
        entries[i].val = s->data[i];
    }

    qsort(entries, s->size, sizeof(f64_entry_t),
          ascending ? cmp_f64_asc : cmp_f64_desc);

    size_t *indices = malloc(s->size * sizeof(size_t));
    if (!indices) { free(entries); return NULL; }

    for (size_t i = 0; i < s->size; i++) indices[i] = entries[i].idx;

    free(entries);
    return indices;
}

smaug_series_f64_t *smaug_f64_sort(const smaug_series_f64_t *s, bool ascending) {
    if (!s) return NULL;

    size_t *indices = smaug_f64_argsort(s, ascending);
    if (!indices) return NULL;  /* série com NULL/NaN, ou falha de alocação */

    smaug_series_f64_t *result = smaug_f64_take(s, indices, s->size);
    free(indices);
    return result;
}

/* ===================================================================
   UTILITÁRIOS
   =================================================================== */

size_t smaug_f64_count_nonnull(const smaug_series_f64_t *s) {
    if (!s) return 0;
    size_t count = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (VALID(s, i)) count++;
    }
    return count;
}

/* take: copia elementos nas posições idx[0..len-1] (0-based).
   Retorna NULL se qualquer índice está fora dos limites. */
smaug_series_f64_t *smaug_f64_take(const smaug_series_f64_t *s,
                                    const size_t *idx, size_t len) {
    if (!s || !idx) return NULL;

    smaug_series_f64_t *r = smaug_f64_create(len);
    if (!r) return NULL;

    for (size_t i = 0; i < len; i++) {
        if (idx[i] >= s->size) {
            smaug_f64_free(r);
            return NULL;
        }
        r->data[i]      = s->data[idx[i]];
        r->null_mask[i] = s->null_mask[idx[i]];
    }
    return r;
}

/* filter: retorna nova série com elementos onde mask[i] != 0.
   mask deve ter o mesmo tamanho que s. */
smaug_series_f64_t *smaug_f64_filter(const smaug_series_f64_t *s,
                                      const uint8_t *mask) {
    if (!s || !mask) return NULL;

    /* Primeiro passo: contar quantos elementos passar */
    size_t count = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (mask[i]) count++;
    }

    smaug_series_f64_t *r = smaug_f64_create(count);
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
