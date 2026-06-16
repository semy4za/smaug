#ifndef SMAUG_OPS_WINDOW_H
#define SMAUG_OPS_WINDOW_H

/* ===================================================================
   smaug_ops_window.h — Grupo C (Fase 3 Ring 0)
   Multi-argsort e rolling ops implementados em C.
   =================================================================== */

#include "smaug_core.h"
#include "smaug_string.h"

/* =====================================================================
   smaug_multi_argsort — sort estável multi-coluna
   ===================================================================== */

/* Código de dtype de coluna para o sort. */
typedef enum {
    SMAUG_COL_F64  = 0,
    SMAUG_COL_I64  = 1,
    SMAUG_COL_STR  = 2,
    SMAUG_COL_DT   = 3,   /* datetime: int64 internamente */
    SMAUG_COL_BOOL = 4
} smaug_col_kind_t;

/* Descritor de uma coluna de chave para o sort. */
typedef struct {
    smaug_col_kind_t kind;
    union {
        const smaug_series_f64_t  *f64;
        const smaug_series_i64_t  *i64;  /* também usado por DT */
        const smaug_series_str_t  *str;
        const smaug_series_dt_t   *dt;
        const smaug_series_bool_t *boo;
    };
} smaug_sort_col_t;

/*
 * smaug_multi_argsort: retorna size_t[nrows] com índices 0-based na ordem
 * lexicográfica das colunas. Sort estável (preserva ordem original em empates).
 * Caller libera com smaug_free.
 * Contrato: todas as posições nas colunas de chave são válidas (sem nulos).
 * Retorna NULL em OOM ou se cols==NULL / ncols==0 / nrows==0.
 */
size_t *smaug_multi_argsort(const smaug_sort_col_t *cols,
                             size_t ncols, size_t nrows);

/* Wrapper FFI: struct plana para uso do LuaJIT (sem union). */
typedef struct {
    int   kind;
    void *ptr;
} smaug_sort_col_ffi_t;

size_t *smaug_multi_argsort_ffi(const smaug_sort_col_ffi_t *cols,
                                 size_t ncols, size_t nrows);

/* =====================================================================
   Rolling ops — janela deslizante O(N)
   Primeiras (window-1) posições são NA. Nulos ignorados na janela.
   Se a janela inteira for nula, posição é NA.
   ===================================================================== */

/* f64 */
smaug_series_f64_t *smaug_f64_rolling_sum (const smaug_series_f64_t *s, size_t window);
smaug_series_f64_t *smaug_f64_rolling_mean(const smaug_series_f64_t *s, size_t window);
smaug_series_f64_t *smaug_f64_rolling_min (const smaug_series_f64_t *s, size_t window);
smaug_series_f64_t *smaug_f64_rolling_max (const smaug_series_f64_t *s, size_t window);

/* i64: sum/min/max retornam i64; mean retorna f64 */
smaug_series_i64_t *smaug_i64_rolling_sum (const smaug_series_i64_t *s, size_t window);
smaug_series_f64_t *smaug_i64_rolling_mean(const smaug_series_i64_t *s, size_t window);
smaug_series_i64_t *smaug_i64_rolling_min (const smaug_series_i64_t *s, size_t window);
smaug_series_i64_t *smaug_i64_rolling_max (const smaug_series_i64_t *s, size_t window);

#endif /* SMAUG_OPS_WINDOW_H */
