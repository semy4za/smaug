#include "../include/smaug_astype.h"

/* Construtores e utilitarios dos dtypes de destino/origem. As primitivas
   da matriz constroem series de outro dtype, entao precisam dos headers
   de todos os tipos envolvidos, alem de dt_format/dt_parse. */
#include "../include/smaug_numeric.h"   /* smaug_i64_*, smaug_f64_* */
#include "../include/smaug_string.h"    /* smaug_str_* (offset-based) */
#include "../include/smaug_datetime.h"  /* smaug_dt_*, dt_format/dt_parse */
#include <math.h>       /* isnan */
#include <stdbool.h>    /* bool */
#include <stdint.h>     /* int64_t */

/* ===================================================================
   smaug_astype.c — matriz de conversao de tipo src×dst (Anel 0).
   Ver smaug_astype.h para a matriz e o contrato.

   Nota de disciplina: as primitivas por-par tem cascas de iteracao
   simetricas (so mudam os tipos) — isso e o preco da type-safety
   (uma funcao por par, retorno tipado no FFI), o mesmo precedente dos
   smaug_*_coalesce / smaug_*_add. A logica de calculo nao-trivial fica
   fatorada em helpers (f64_to_i64_trunc), fonte unica — a redundancia
   real (o calculo) nao se duplica.

   Fase 1 (Grupo A): conversoes entre arrays diretos (sem string).
   Fases 2-3 (string): entram depois.
   =================================================================== */

/* ===================================================================
   Helpers internos
   =================================================================== */

/* double -> int64 com truncagem em direcao a zero (igual ao cast C e ao
   trunc_to_int do oraculo Lua). Inconversivel — NaN, +/-inf, ou fora do
   range representavel de int64 (|v| >= 2^63) — sinaliza *ok=false; pelo
   Contrato 2 esses viram null (a serie nunca e descartada). Guardar o
   range evita o UB de (int64_t)v para v fora de [-2^63, 2^63);
   2^63 (9223372036854775808.0) e exato em double. */
static int64_t f64_to_i64_trunc(double v, bool *ok) {
    if (isnan(v) || v >= 9223372036854775808.0 || v < -9223372036854775808.0) {
        *ok = false;
        return 0;
    }
    *ok = true;
    return (int64_t)v;   /* C11: truncagem em direcao a zero */
}

/* ===================================================================
   GRUPO A — conversoes entre arrays diretos (i64/f64/datetime)
   Cada primitiva: o destino nasce todo-nulo (create memset NULL), seta
   apenas as celulas validas convertidas; origem-nula e inconversivel
   ficam nulas. Sem round-trip por double na fronteira Lua — dt<->i64
   copia int64->int64, exato acima de 2^53.
   =================================================================== */

/* int64 -> float64: exato ate 2^53; acima, o proprio double e o destino
   pedido (a perda e da largura do tipo-alvo, nao de round-trip). */
smaug_series_f64_t *smaug_i64_to_f64(const smaug_series_i64_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_f64_t *r = smaug_f64_create(self->size);
    if (!r) return NULL;     /* COV-EXCL-BR: OOM sem injecao de falha */
    for (size_t i = 0; i < self->size; i++) {
        if (SMAUG_VALID(self->null_mask, i)) {
            r->data[i]      = (double)self->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* float64 -> int64: trunc direcao zero; NaN/+-inf/fora-do-range -> null. */
smaug_series_i64_t *smaug_f64_to_i64(const smaug_series_f64_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_i64_t *r = smaug_i64_create(self->size);
    if (!r) return NULL;     /* COV-EXCL-BR: OOM */
    for (size_t i = 0; i < self->size; i++) {
        if (SMAUG_VALID(self->null_mask, i)) {
            bool ok;
            int64_t iv = f64_to_i64_trunc(self->data[i], &ok);
            if (ok) {
                r->data[i]      = iv;
                r->null_mask[i] = SMAUG_MASK_VALID;
            }
            /* !ok -> inconversivel -> permanece null */
        }
    }
    return r;
}

/* int64 -> datetime: reinterpreta o int64 como epoch_ms. Copia direta
   int64->int64 — exato, sem passar por double. */
smaug_series_dt_t *smaug_i64_to_dt(const smaug_series_i64_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_dt_t *r = smaug_dt_create(self->size);
    if (!r) return NULL;     /* COV-EXCL-BR: OOM */
    for (size_t i = 0; i < self->size; i++) {
        if (SMAUG_VALID(self->null_mask, i)) {
            r->data[i]      = self->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* datetime -> int64: extrai o epoch_ms como int64. Copia direta — EXATO
   acima de 2^53 (conserta o round-trip por get()/double do oraculo). */
smaug_series_i64_t *smaug_dt_to_i64(const smaug_series_dt_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_i64_t *r = smaug_i64_create(self->size);
    if (!r) return NULL;     /* COV-EXCL-BR: OOM */
    for (size_t i = 0; i < self->size; i++) {
        if (SMAUG_VALID(self->null_mask, i)) {
            r->data[i]      = self->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* float64 -> datetime: trunc para epoch_ms; NaN/+-inf/fora-do-range -> null. */
smaug_series_dt_t *smaug_f64_to_dt(const smaug_series_f64_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_dt_t *r = smaug_dt_create(self->size);
    if (!r) return NULL;     /* COV-EXCL-BR: OOM */
    for (size_t i = 0; i < self->size; i++) {
        if (SMAUG_VALID(self->null_mask, i)) {
            bool ok;
            int64_t iv = f64_to_i64_trunc(self->data[i], &ok);
            if (ok) {
                r->data[i]      = iv;
                r->null_mask[i] = SMAUG_MASK_VALID;
            }
        }
    }
    return r;
}

/* datetime -> float64: epoch_ms -> double (perda acima de 2^53; double e
   o destino pedido). */
smaug_series_f64_t *smaug_dt_to_f64(const smaug_series_dt_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_f64_t *r = smaug_f64_create(self->size);
    if (!r) return NULL;     /* COV-EXCL-BR: OOM */
    for (size_t i = 0; i < self->size; i++) {
        if (SMAUG_VALID(self->null_mask, i)) {
            r->data[i]      = (double)self->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}
