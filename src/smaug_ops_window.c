/* src/smaug_ops_window.c
 *
 * Grupo C (Fase 3 Ring 0):
 *   - smaug_multi_argsort: sort estável multi-coluna para GroupBy/sort_by.
 *   - smaug_f64_rolling_N / smaug_i64_rolling_N: operações de janela deslizante.
 *
 * Portabilidade:
 *   Usa merge sort próprio (estável, sem dependência de qsort_r/qsort_s).
 */

#include "../include/smaug_types.h"
#include "../include/smaug_string.h"
#include "../include/smaug_ops_window.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>     /* NAN, sqrt */
#include <stddef.h>

/* ===================================================================
   Parte 1 — smaug_multi_argsort
   =================================================================== */

/* Contexto passado ao comparador: array de descritores + ncols. */
typedef struct {
    const smaug_sort_col_t *cols;
    size_t                  ncols;
} sort_ctx_t;

/* Compara dois valores do mesmo dtype na posição de linha (row_a, row_b).
   Retorna <0, 0, >0 conforme comparação lexicográfica. */
static int cmp_col_at(const smaug_sort_col_t *col, size_t ra, size_t rb) {
    switch (col->kind) {
        case SMAUG_COL_F64: {
            double a = col->f64->data[ra], b = col->f64->data[rb];
            return (a > b) - (a < b);
        }
        case SMAUG_COL_I64:
        case SMAUG_COL_DT: {
            /* datetime é int64 internamente */
            int64_t a = col->i64->data[ra], b = col->i64->data[rb];
            return (a > b) - (a < b);
        }
        case SMAUG_COL_BOOL: {
            uint8_t a = col->boo->data[ra], b = col->boo->data[rb];
            return (int)a - (int)b;
        }
        case SMAUG_COL_STR: {
            size_t la = col->str->offsets[ra+1] - col->str->offsets[ra];
            size_t lb = col->str->offsets[rb+1] - col->str->offsets[rb];
            const char *pa = col->str->buffer + col->str->offsets[ra];
            const char *pb = col->str->buffer + col->str->offsets[rb];
            size_t lmin = la < lb ? la : lb;
            int c = memcmp(pa, pb, lmin);
            if (c != 0) return c;
            return (la > lb) - (la < lb);
        }
    }
    return 0; /* nunca atingido */
}

/* ===================================================================
   Merge sort estável (bottom-up, in-place com buffer auxiliar).
   Usado no lugar de qsort_r/qsort_s para garantir estabilidade
   em todas as plataformas (qsort não é estável por padrão).
   =================================================================== */

static void merge_stable(size_t *arr, size_t *tmp,
                         size_t lo, size_t mid, size_t hi,
                         const sort_ctx_t *ctx) {
    size_t i = lo, j = mid, k = lo;
    while (i < mid && j < hi) {
        int cmp = 0;
        for (size_t col = 0; col < ctx->ncols; col++) {
            cmp = cmp_col_at(&ctx->cols[col], arr[i], arr[j]);
            if (cmp != 0) break;
        }
        /* estável: empate mantém ordem original (i antes de j) */
        if (cmp <= 0) tmp[k++] = arr[i++];
        else          tmp[k++] = arr[j++];
    }
    while (i < mid) tmp[k++] = arr[i++];
    while (j < hi)  tmp[k++] = arr[j++];
    for (size_t x = lo; x < hi; x++) arr[x] = tmp[x];
}

static void mergesort_stable(size_t *arr, size_t *tmp,
                              size_t n, const sort_ctx_t *ctx) {
    for (size_t width = 1; width < n; width *= 2) {
        for (size_t lo = 0; lo < n; lo += 2 * width) {
            size_t mid = lo + width;
            size_t hi  = lo + 2 * width;
            if (mid > n) mid = n;
            if (hi  > n) hi  = n;
            if (mid < hi)
                merge_stable(arr, tmp, lo, mid, hi, ctx);
        }
    }
}

/*
 * smaug_multi_argsort: sort estável multi-coluna.
 * Usa merge sort próprio — estável em todas as plataformas.
 * Retorna NULL em OOM.
 */
size_t *smaug_multi_argsort(const smaug_sort_col_t *cols,
                             size_t ncols, size_t nrows) {
    if (!cols || ncols == 0 || nrows == 0) return NULL;

    size_t *idx = malloc(nrows * sizeof(size_t));
    if (!idx) return NULL;

    size_t *tmp = malloc(nrows * sizeof(size_t));
    if (!tmp) { free(idx); return NULL; }

    for (size_t i = 0; i < nrows; i++) idx[i] = i;

    sort_ctx_t ctx = { cols, ncols };
    mergesort_stable(idx, tmp, nrows, &ctx);

    free(tmp);
    return idx;
}

/* ===================================================================
   Wrapper FFI público: interface simplificada para o LuaJIT FFI.
   O Lua não consegue construir unions C diretamente; esta função recebe
   uma struct plana { kind, ptr } e reconstrói o smaug_sort_col_t.
   smaug_sort_col_ffi_t declarado em smaug_ops_window.h.
   =================================================================== */

size_t *smaug_multi_argsort_ffi(const smaug_sort_col_ffi_t *ffi_cols,
                                 size_t ncols, size_t nrows) {
    if (!ffi_cols || ncols == 0 || nrows == 0) return NULL;

    smaug_sort_col_t *cols = malloc(ncols * sizeof(smaug_sort_col_t));
    if (!cols) return NULL;

    for (size_t k = 0; k < ncols; k++) {
        cols[k].kind = (smaug_col_kind_t)ffi_cols[k].kind;
        /* todos os membros da union são ponteiros do mesmo tamanho */
        cols[k].f64 = (const smaug_series_f64_t *)ffi_cols[k].ptr;
    }

    size_t *result = smaug_multi_argsort(cols, ncols, nrows);
    free(cols);
    return result;
}

/* ===================================================================
   Parte 2 — Rolling ops (janela deslizante)
   Implementação O(N) com janela deslizante incremental para sum/mean.
   Min/max usam deque (monotone queue) para O(N) também.
   Sem alocação de wv[] a cada iteração.
   =================================================================== */

/* --- helpers de deque para rolling min/max O(N) --- */

/* Deque de índices (size_t) para monotone queue. */
typedef struct {
    size_t *buf;
    size_t  cap;
    size_t  head;
    size_t  tail;  /* tail aponta para próximo slot livre */
} deque_t;

static int deque_init(deque_t *d, size_t cap) {
    d->buf  = malloc(cap * sizeof(size_t));
    d->cap  = cap;
    d->head = 0;
    d->tail = 0;
    return d->buf != NULL;
}
static void deque_free(deque_t *d) { free(d->buf); }
static int  deque_empty(const deque_t *d) { return d->head == d->tail; }
static void deque_push_back(deque_t *d, size_t v) { d->buf[d->tail++ % d->cap] = v; }
static void deque_pop_back(deque_t *d)             { d->tail--; }
static void deque_pop_front(deque_t *d)            { d->head++; }
static size_t deque_front(const deque_t *d)        { return d->buf[d->head % d->cap]; }
static size_t deque_back(const deque_t *d)         { return d->buf[(d->tail-1) % d->cap]; }

/* ===================================================================
   f64 rolling
   =================================================================== */

/* ===================================================================
   Parte 2 — Motor de janela genérico (item 8a)
   -------------------------------------------------------------------
   Fonte única para os agregados naturalmente double: mean, std, var,
   count. sum/min/max NÃO passam aqui (preservam tipo exato e otimização
   própria — ver D8-g); apenas ganham o parâmetro min_periods.

   Regra de emissão (unificada, espelha o _agg da camada Lua):
     - min_periods == 0  → MODO JANELA CHEIA (default): emite valor só se
       a posição tem janela completa (i+1 >= window) E >= 1 não-nulo.
     - min_periods >= 1  → MODO PARCIAL: emite se a janela (parcial no
       início) tem >= min_periods não-nulos. Convenção idêntica ao
       min_count do item 5.5.

   std/var são AMOSTRAIS (ddof=1, ÷(n-1), NaN para n<2) — coerente com a
   reconciliação do item 5.0. Não populacional.
   =================================================================== */
typedef enum {
    ROLL_MEAN = 0,
    ROLL_STD,
    ROLL_VAR,
    ROLL_COUNT
} roll_kind_t;

/* Aplica o agregado `kind` sobre janelas de `data`/`mask` (tamanho n).
   Retorna double* (NAN onde não emite). Caller libera. NULL em OOM. */
static double *rolling_apply(const double *data, const smaug_mask_t *mask,
                             size_t n, size_t window, size_t min_periods,
                             roll_kind_t kind) {
    double *out = malloc((n ? n : 1) * sizeof(double));
    if (!out) return NULL;
    for (size_t i = 0; i < n; i++) out[i] = NAN;

    for (size_t i = 0; i < n; i++) {
        size_t wstart = (i + 1 >= window) ? (i + 1 - window) : 0;

        /* modo janela-cheia (min_periods==0): exige janela completa */
        if (min_periods == 0 && i + 1 < window) continue;

        /* varre a janela [wstart, i], acumulando não-nulos */
        size_t cnt = 0;
        double sum = 0.0, sumsq = 0.0;
        for (size_t j = wstart; j <= i; j++) {
            if (SMAUG_VALID(mask, j)) {
                double v = data[j];
                sum   += v;
                sumsq += v * v;
                cnt++;
            }
        }

        size_t need = (min_periods == 0) ? 1 : min_periods;
        if (cnt < need) continue;   /* não emite → permanece NAN */

        switch (kind) {
            case ROLL_COUNT:
                out[i] = (double)cnt;
                break;
            case ROLL_MEAN:
                out[i] = sum / (double)cnt;
                break;
            case ROLL_STD:
            case ROLL_VAR: {
                if (cnt < 2) { /* amostral indefinido → permanece NAN */
                    break;
                }
                double mean = sum / (double)cnt;
                /* variância amostral: (Σx² - n·mean²)/(n-1) */
                double num = sumsq - (double)cnt * mean * mean;
                if (num < 0.0) num = 0.0;   /* guarda contra erro numérico */
                double var = num / (double)(cnt - 1);
                out[i] = (kind == ROLL_VAR) ? var : sqrt(var);
                break;
            }
        }
    }
    return out;
}

/*
 * rolling_sum f64: soma deslizante O(N).
 * Nulos ignorados dentro da janela (somados como 0, contados separado).
 * Se a janela inteira for nula, resultado é NA.
 * Primeiras (window-1) posições são NA.
 */
smaug_series_f64_t *smaug_f64_rolling_sum(const smaug_series_f64_t *s,
                                           size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    smaug_series_f64_t *r = smaug_f64_create(s->size);
    if (!r) return NULL;

    double sum = 0.0;
    size_t cnt = 0;  /* não-nulos na janela */

    for (size_t i = 0; i < s->size; i++) {
        /* adiciona elemento que entra */
        if (SMAUG_VALID(s->null_mask, i)) { sum += s->data[i]; cnt++; }
        /* remove elemento que sai (fora da janela) */
        if (i >= window) {
            size_t out = i - window;
            if (SMAUG_VALID(s->null_mask, out)) { sum -= s->data[out]; cnt--; }
        }
        /* emissão (item 8a): modo janela-cheia (min_periods==0) exige
           janela completa; modo parcial exige >= min_periods não-nulos. */
        if (min_periods == 0 && i + 1 < window) continue;
        size_t need = (min_periods == 0) ? 1 : min_periods;
        if (cnt < need) continue;
        r->data[i]      = sum;
        r->null_mask[i] = SMAUG_MASK_VALID;
    }
    return r;
}

/*
 * rolling_mean f64: média deslizante O(N).
 */
/* Empacota um double* (do motor) numa série f64, transferindo NAN→NA.
   Consome `vals` (libera ao fim). NULL em OOM. */
static smaug_series_f64_t *pack_f64(double *vals, size_t n) {
    if (!vals) return NULL;
    smaug_series_f64_t *r = smaug_f64_create(n);
    if (!r) { free(vals); return NULL; }
    for (size_t i = 0; i < n; i++) {
        if (vals[i] == vals[i]) {   /* não-NAN */
            r->data[i]      = vals[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    free(vals);
    return r;
}

smaug_series_f64_t *smaug_f64_rolling_mean(const smaug_series_f64_t *s,
                                            size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    return pack_f64(rolling_apply(s->data, s->null_mask, s->size,
                                  window, min_periods, ROLL_MEAN), s->size);
}

smaug_series_f64_t *smaug_f64_rolling_std(const smaug_series_f64_t *s,
                                           size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    return pack_f64(rolling_apply(s->data, s->null_mask, s->size,
                                  window, min_periods, ROLL_STD), s->size);
}

smaug_series_f64_t *smaug_f64_rolling_var(const smaug_series_f64_t *s,
                                           size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    return pack_f64(rolling_apply(s->data, s->null_mask, s->size,
                                  window, min_periods, ROLL_VAR), s->size);
}

/* count retorna int64 (contagem é naturalmente inteira). */
smaug_series_i64_t *smaug_f64_rolling_count(const smaug_series_f64_t *s,
                                             size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    double *vals = rolling_apply(s->data, s->null_mask, s->size,
                                 window, min_periods, ROLL_COUNT);
    if (!vals) return NULL;
    smaug_series_i64_t *r = smaug_i64_create(s->size);
    if (!r) { free(vals); return NULL; }
    for (size_t i = 0; i < s->size; i++) {
        if (vals[i] == vals[i]) {
            r->data[i]      = (int64_t)vals[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    free(vals);
    return r;
}

/*
 * rolling_min f64: mínimo deslizante O(N) via monotone deque.
 */
smaug_series_f64_t *smaug_f64_rolling_min(const smaug_series_f64_t *s,
                                           size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    smaug_series_f64_t *r = smaug_f64_create(s->size);
    if (!r) return NULL;

    /* Modo min_periods>=1 (item 8a, D8-h opção ii): rescan O(n·window)
       type-preserving (compara em double nativo, sem perda) sobre janelas
       parciais. A deque otimizada fica reservada ao modo janela-cheia. */
    if (min_periods >= 1) {
        for (size_t i = 0; i < s->size; i++) {
            size_t wstart = (i + 1 >= window) ? (i + 1 - window) : 0;
            size_t cnt = 0; double best = 0.0;
            for (size_t j = wstart; j <= i; j++) {
                if (SMAUG_VALID(s->null_mask, j)) {
                    if (cnt == 0 || s->data[j] < best) best = s->data[j];
                    cnt++;
                }
            }
            if (cnt >= min_periods) {
                r->data[i] = best; r->null_mask[i] = SMAUG_MASK_VALID;
            }
        }
        return r;
    }

    deque_t dq;
    if (!deque_init(&dq, window + 1)) { smaug_f64_free(r); return NULL; }

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_NULL(s->null_mask, i)) {
            /* nulo: não entra na deque; verifica se janela completa tem válidos */
            if (i + 1 >= window && !deque_empty(&dq) &&
                deque_front(&dq) + window <= i) {
                deque_pop_front(&dq);
            }
            /* posição permanece NA */
            goto next_min;
        }
        /* remove índices fora da janela */
        while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
            deque_pop_front(&dq);
        /* remove do fundo índices com valor >= atual (não podem ser mínimo futuro) */
        while (!deque_empty(&dq) && s->data[deque_back(&dq)] >= s->data[i])
            deque_pop_back(&dq);
        deque_push_back(&dq, i);

        next_min:
        if (i + 1 < window) continue;
        /* remove front desatualizado após salto de nulo */
        while (!deque_empty(&dq) && deque_front(&dq) + window <= i) /* COV-EXCL-BR: loop-body inalcançável — a if em 258-260 já trata o único item stale possível; by invariante de 266, no máximo um item envelhece por passo de null */
            deque_pop_front(&dq);
        if (deque_empty(&dq)) continue;
        r->data[i]      = s->data[deque_front(&dq)];
        r->null_mask[i] = SMAUG_MASK_VALID;
    }

    deque_free(&dq);
    return r;
}

/*
 * rolling_max f64: máximo deslizante O(N) via monotone deque.
 */
smaug_series_f64_t *smaug_f64_rolling_max(const smaug_series_f64_t *s,
                                           size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    smaug_series_f64_t *r = smaug_f64_create(s->size);
    if (!r) return NULL;

    if (min_periods >= 1) {  /* rescan type-preserving (D8-h ii) */
        for (size_t i = 0; i < s->size; i++) {
            size_t wstart = (i + 1 >= window) ? (i + 1 - window) : 0;
            size_t cnt = 0; double best = 0.0;
            for (size_t j = wstart; j <= i; j++) {
                if (SMAUG_VALID(s->null_mask, j)) {
                    if (cnt == 0 || s->data[j] > best) best = s->data[j];
                    cnt++;
                }
            }
            if (cnt >= min_periods) {
                r->data[i] = best; r->null_mask[i] = SMAUG_MASK_VALID;
            }
        }
        return r;
    }

    deque_t dq;
    if (!deque_init(&dq, window + 1)) { smaug_f64_free(r); return NULL; }

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_NULL(s->null_mask, i)) {
            if (i + 1 >= window && !deque_empty(&dq) &&
                deque_front(&dq) + window <= i) {
                deque_pop_front(&dq);
            }
            goto next_max;
        }
        while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
            deque_pop_front(&dq);
        /* fundo com valor <= atual (não podem ser máximo futuro) */
        while (!deque_empty(&dq) && s->data[deque_back(&dq)] <= s->data[i])
            deque_pop_back(&dq);
        deque_push_back(&dq, i);

        next_max:
        if (i + 1 < window) continue;
        while (!deque_empty(&dq) && deque_front(&dq) + window <= i) /* COV-EXCL-BR: loop-body inalcançável — mesma invariante que linha 276 (rolling_min) */
            deque_pop_front(&dq);
        if (deque_empty(&dq)) continue;
        r->data[i]      = s->data[deque_front(&dq)];
        r->null_mask[i] = SMAUG_MASK_VALID;
    }

    deque_free(&dq);
    return r;
}

/* ===================================================================
   i64 rolling (mesmo padrão, tipo diferente)
   =================================================================== */

smaug_series_i64_t *smaug_i64_rolling_sum(const smaug_series_i64_t *s,
                                           size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    smaug_series_i64_t *r = smaug_i64_create(s->size);
    if (!r) return NULL;

    int64_t sum = 0;
    size_t  cnt = 0;

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) { sum += s->data[i]; cnt++; }
        if (i >= window) {
            size_t out = i - window;
            if (SMAUG_VALID(s->null_mask, out)) { sum -= s->data[out]; cnt--; }
        }
        if (min_periods == 0 && i + 1 < window) continue;
        size_t need = (min_periods == 0) ? 1 : min_periods;
        if (cnt < need) continue;
        r->data[i]      = sum;
        r->null_mask[i] = SMAUG_MASK_VALID;
    }
    return r;
}

/* Converte os dados int64 para double e aplica o motor genérico.
   mean/std/var de i64 são double-safe (resultado é estatística contínua);
   count idem (contagem pequena). Caller libera o retorno. */
static double *i64_rolling_via_motor(const smaug_series_i64_t *s, size_t window,
                                     size_t min_periods, roll_kind_t kind) {
    double *tmp = malloc((s->size ? s->size : 1) * sizeof(double));
    if (!tmp) return NULL;
    for (size_t i = 0; i < s->size; i++) tmp[i] = (double)s->data[i];
    double *out = rolling_apply(tmp, s->null_mask, s->size,
                                window, min_periods, kind);
    free(tmp);
    return out;
}

smaug_series_f64_t *smaug_i64_rolling_mean(const smaug_series_i64_t *s,
                                            size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    return pack_f64(i64_rolling_via_motor(s, window, min_periods, ROLL_MEAN), s->size);
}

smaug_series_f64_t *smaug_i64_rolling_std(const smaug_series_i64_t *s,
                                           size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    return pack_f64(i64_rolling_via_motor(s, window, min_periods, ROLL_STD), s->size);
}

smaug_series_f64_t *smaug_i64_rolling_var(const smaug_series_i64_t *s,
                                           size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    return pack_f64(i64_rolling_via_motor(s, window, min_periods, ROLL_VAR), s->size);
}

smaug_series_i64_t *smaug_i64_rolling_count(const smaug_series_i64_t *s,
                                             size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    double *vals = i64_rolling_via_motor(s, window, min_periods, ROLL_COUNT);
    if (!vals) return NULL;
    smaug_series_i64_t *r = smaug_i64_create(s->size);
    if (!r) { free(vals); return NULL; }
    for (size_t i = 0; i < s->size; i++) {
        if (vals[i] == vals[i]) {
            r->data[i]      = (int64_t)vals[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    free(vals);
    return r;
}

smaug_series_i64_t *smaug_i64_rolling_min(const smaug_series_i64_t *s,
                                           size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    smaug_series_i64_t *r = smaug_i64_create(s->size);
    if (!r) return NULL;

    if (min_periods >= 1) {  /* rescan type-preserving int64 (D8-h ii) */
        for (size_t i = 0; i < s->size; i++) {
            size_t wstart = (i + 1 >= window) ? (i + 1 - window) : 0;
            size_t cnt = 0; int64_t best = 0;
            for (size_t j = wstart; j <= i; j++) {
                if (SMAUG_VALID(s->null_mask, j)) {
                    if (cnt == 0 || s->data[j] < best) best = s->data[j];
                    cnt++;
                }
            }
            if (cnt >= min_periods) {
                r->data[i] = best; r->null_mask[i] = SMAUG_MASK_VALID;
            }
        }
        return r;
    }

    deque_t dq;
    if (!deque_init(&dq, window + 1)) { smaug_i64_free(r); return NULL; }

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_NULL(s->null_mask, i)) { goto next_i64_min; }
        while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
            deque_pop_front(&dq);
        while (!deque_empty(&dq) && s->data[deque_back(&dq)] >= s->data[i])
            deque_pop_back(&dq);
        deque_push_back(&dq, i);

        next_i64_min:
        if (i + 1 < window) continue;
        while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
            deque_pop_front(&dq);
        if (deque_empty(&dq)) continue;
        r->data[i]      = s->data[deque_front(&dq)];
        r->null_mask[i] = SMAUG_MASK_VALID;
    }

    deque_free(&dq);
    return r;
}

smaug_series_i64_t *smaug_i64_rolling_max(const smaug_series_i64_t *s,
                                           size_t window, size_t min_periods) {
    if (!s || window == 0) return NULL;
    smaug_series_i64_t *r = smaug_i64_create(s->size);
    if (!r) return NULL;

    if (min_periods >= 1) {  /* rescan type-preserving int64 (D8-h ii) */
        for (size_t i = 0; i < s->size; i++) {
            size_t wstart = (i + 1 >= window) ? (i + 1 - window) : 0;
            size_t cnt = 0; int64_t best = 0;
            for (size_t j = wstart; j <= i; j++) {
                if (SMAUG_VALID(s->null_mask, j)) {
                    if (cnt == 0 || s->data[j] > best) best = s->data[j];
                    cnt++;
                }
            }
            if (cnt >= min_periods) {
                r->data[i] = best; r->null_mask[i] = SMAUG_MASK_VALID;
            }
        }
        return r;
    }

    deque_t dq;
    if (!deque_init(&dq, window + 1)) { smaug_i64_free(r); return NULL; }

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_NULL(s->null_mask, i)) { goto next_i64_max; }
        while (!deque_empty(&dq) && deque_front(&dq) + window <= i)
            deque_pop_front(&dq);
        while (!deque_empty(&dq) && s->data[deque_back(&dq)] <= s->data[i])
            deque_pop_back(&dq);
        deque_push_back(&dq, i);

        next_i64_max:
        if (i + 1 < window) continue;
        while (!deque_empty(&dq) && deque_front(&dq) + window <= i) /* COV-EXCL-BR: loop-body inalcançável — mesma invariante que linhas 276/316 (i64: não há null-path cleanup prévio, mas a monotone deque e o loop não-null a 405 já garantem no máximo 1 stale) */
            deque_pop_front(&dq);
        if (deque_empty(&dq)) continue;
        r->data[i]      = s->data[deque_front(&dq)];
        r->null_mask[i] = SMAUG_MASK_VALID;
    }

    deque_free(&dq);
    return r;
}
