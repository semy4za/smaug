#include "../include/smaug_astype.h"

/* Construtores e utilitarios dos dtypes de destino/origem. As primitivas
   da matriz constroem series de outro dtype, entao precisam dos headers
   de todos os tipos envolvidos, alem de dt_format/dt_parse. */
#include "../include/smaug_numeric.h"   /* smaug_i64_*, smaug_f64_* */
#include "../include/smaug_string.h"    /* smaug_str_* (offset-based) */
#include "../include/smaug_datetime.h"  /* smaug_dt_*, dt_format/dt_parse */
#include "../include/smaug_convert.h"   /* smaug_parse_i64/f64 (parse rigido) */
#include <math.h>       /* isnan, isfinite, trunc */
#include <stdbool.h>    /* bool */
#include <stdint.h>     /* int64_t */
#include <string.h>     /* strlen — comprimento do ISO formatado */

/* ===================================================================
   smaug_astype.c — matriz de conversao de tipo src×dst (Anel 0).
   Ver smaug_astype.h para a matriz e o contrato.

   Cada par mantem tipos C explicitos na entrada e na saida. Conversoes
   para datetime validam todos os valores presentes antes de publicar a
   serie; os wrappers de ponteiro delegam as variantes com status.
   Parsing e formatacao pertencem aos respectivos modulos de valores.
   =================================================================== */

/* ===================================================================
   Helpers internos
   =================================================================== */

/* Conversao tolerante float64->int64: validar [-2^63, 2^63) antes do cast
   evita UB. Frações truncam em direcao a zero; NaN/inf/fora da faixa viram
   NA no caller. Esta politica nao se aplica ao destino datetime. */
static int64_t truncate_float64_to_int64(double value, bool *is_convertible) {
    if (isnan(value) || value >= 9223372036854775808.0 || value < -9223372036854775808.0) {
        *is_convertible = false;
        return 0;
    }
    *is_convertible = true;
    return (int64_t)value;   /* C11: truncagem em direcao a zero */
}

/* ===================================================================
   GRUPO A — conversoes entre arrays diretos (i64/f64/datetime)
   O destino nasce todo-nulo; NA de origem propaga sem converter seu payload.
   Conversoes estritas ->datetime validam dominio e precisao, liberando o
   destino temporario em erro. Copias i64/datetime nao passam por double.
   =================================================================== */

/* int64 -> float64: exato ate 2^53; acima, o proprio double e o destino
   pedido (a perda e da largura do tipo-alvo, nao de round-trip). */
smaug_series_f64_t *smaug_i64_to_f64(const smaug_series_i64_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_f64_t *result_series = smaug_f64_create(self->size);
    if (!result_series) return NULL;     /* COV-EXCL-BR: OOM sem injecao de falha */
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        if (SMAUG_VALID(self->null_mask, row_index)) {
            result_series->data[row_index]      = (double)self->data[row_index];
            result_series->null_mask[row_index] = SMAUG_MASK_VALID;
        }
    }
    return result_series;
}

/* float64 -> int64: trunc direcao zero; NaN/+-inf/fora-do-range -> null. */
smaug_series_i64_t *smaug_f64_to_i64(const smaug_series_f64_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_i64_t *result_series = smaug_i64_create(self->size);
    if (!result_series) return NULL;     /* COV-EXCL-BR: OOM */
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        if (SMAUG_VALID(self->null_mask, row_index)) {
            bool is_convertible;
            int64_t integer_value = truncate_float64_to_int64(self->data[row_index], &is_convertible);
            if (is_convertible) {
                result_series->data[row_index]      = integer_value;
                result_series->null_mask[row_index] = SMAUG_MASK_VALID;
            }
            /* !ok -> inconversivel -> permanece null */
        }
    }
    return result_series;
}

/* Wrappers preservam a ABI de ponteiro/NULL; a validacao fica nas checked. */
smaug_series_dt_t *smaug_i64_to_dt(const smaug_series_i64_t *self) {
    smaug_series_dt_t *result_series = NULL;
    smaug_i64_to_dt_checked(self, &result_series, NULL);
    return result_series;
}

smaug_status_t smaug_i64_to_dt_checked(const smaug_series_i64_t *self,
                                     smaug_series_dt_t **out, size_t *error_index) {
    if (!self || !out) return SMG_ERR_ARGUMENT;
    smaug_series_dt_t *result_series = smaug_dt_create(self->size);
    if (!result_series) return SMG_ERR_NOMEM;
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        if (!SMAUG_VALID(self->null_mask, row_index)) continue;
        int64_t epoch_ms = self->data[row_index];
        if (epoch_ms < SMAUG_DT_MIN_EPOCH_MS || epoch_ms > SMAUG_DT_MAX_EPOCH_MS) {
            smaug_dt_free(result_series);
            if (error_index) *error_index = row_index;
            return SMG_ERR_OVERFLOW;
        }
        result_series->data[row_index] = epoch_ms;
        result_series->null_mask[row_index] = SMAUG_MASK_VALID;
    }
    *out = result_series;
    return SMG_OK;
}

/* datetime -> int64: extrai o epoch_ms como int64. Copia direta — EXATO
   acima de 2^53 (conserta o round-trip por get()/double do oraculo). */
smaug_series_i64_t *smaug_dt_to_i64(const smaug_series_dt_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_i64_t *result_series = smaug_i64_create(self->size);
    if (!result_series) return NULL;     /* COV-EXCL-BR: OOM */
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        if (SMAUG_VALID(self->null_mask, row_index)) {
            result_series->data[row_index]      = self->data[row_index];
            result_series->null_mask[row_index] = SMAUG_MASK_VALID;
        }
    }
    return result_series;
}

/* float64 -> datetime: exige milissegundos inteiros, finitos e no dominio. */
smaug_series_dt_t *smaug_f64_to_dt(const smaug_series_f64_t *self) {
    smaug_series_dt_t *result_series = NULL;
    smaug_f64_to_dt_checked(self, &result_series, NULL);
    return result_series;
}

smaug_status_t smaug_f64_to_dt_checked(const smaug_series_f64_t *self,
                                     smaug_series_dt_t **out, size_t *error_index) {
    if (!self || !out) return SMG_ERR_ARGUMENT;
    smaug_series_dt_t *result_series = smaug_dt_create(self->size);
    if (!result_series) return SMG_ERR_NOMEM;
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        if (!SMAUG_VALID(self->null_mask, row_index)) continue;
        double value = self->data[row_index];
        smaug_status_t status = SMG_OK;
        if (!isfinite(value)) status = SMG_ERR_ARGUMENT;
        else if (value < SMAUG_DT_MIN_EPOCH_MS || value > SMAUG_DT_MAX_EPOCH_MS)
            status = SMG_ERR_OVERFLOW;
        else if (trunc(value) != value) status = SMG_ERR_ARGUMENT;
        if (status != SMG_OK) {
            smaug_dt_free(result_series);
            if (error_index) *error_index = row_index;
            return status;
        }
        /* O dominio datetime cabe em int64 e todos os seus inteiros em double.
           Validar antes do cast evita UB e impede truncamento silencioso. */
        result_series->data[row_index] = (int64_t)value;
        result_series->null_mask[row_index] = SMAUG_MASK_VALID;
    }
    *out = result_series;
    return SMG_OK;
}

/* datetime -> float64: epoch_ms -> double (perda acima de 2^53; double e
   o destino pedido). */
smaug_series_f64_t *smaug_dt_to_f64(const smaug_series_dt_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_f64_t *result_series = smaug_f64_create(self->size);
    if (!result_series) return NULL;     /* COV-EXCL-BR: OOM */
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        if (SMAUG_VALID(self->null_mask, row_index)) {
            result_series->data[row_index]      = (double)self->data[row_index];
            result_series->null_mask[row_index] = SMAUG_MASK_VALID;
        }
    }
    return result_series;
}

/* ===================================================================
   GRUPO B-out — conversoes para string (builder offset-based)
   num->str usa o formato canonico dos writers C do projeto (%.17g / %lld),
   NAO o tostring %.14g do Lua: coerencia de aneis (astype = csv = json) e
   round-trip exato. i64->str formata o int64 direto (%lld) — conserta a
   corrupcao > 2^53 do round-trip por get()/double do oraculo. dt->str usa
   smaug_dt_format (a mesma primitiva do oraculo), paridade por construcao.
   Construcao single-pass: create_with_capacity(0, est) + append; o append
   cresce buffer/offsets/mask sozinho. Origem nula -> append_null.
   =================================================================== */

/* int64 -> string: %lld exato (conserta o > 2^53 do oraculo). */
smaug_series_str_t *smaug_i64_to_str(const smaug_series_i64_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_str_t *result_series =
        smaug_str_create_with_capacity(0, self->size ? self->size * 20 : 1);
    if (!result_series) return NULL;     /* COV-EXCL-BR: OOM sem injecao */
    char format_buffer[32];
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        int append_status;
        if (SMAUG_VALID(self->null_mask, row_index)) {
            size_t formatted_length = smaug_fmt_i64(format_buffer, sizeof(format_buffer), self->data[row_index]);
            append_status = smaug_str_append(result_series, format_buffer, formatted_length);
        } else {
            append_status = smaug_str_append_null(result_series);
        }
        if (append_status != 0) { smaug_str_free(result_series); return NULL; }  /* COV-EXCL-BR: OOM no append */
    }
    return result_series;
}

/* float64 -> string: %.17g (round-trip exato, formato canonico do projeto). */
smaug_series_str_t *smaug_f64_to_str(const smaug_series_f64_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_str_t *result_series =
        smaug_str_create_with_capacity(0, self->size ? self->size * 24 : 1);
    if (!result_series) return NULL;     /* COV-EXCL-BR: OOM sem injecao */
    char format_buffer[32];
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        int append_status;
        if (SMAUG_VALID(self->null_mask, row_index)) {
            size_t formatted_length = smaug_fmt_f64(format_buffer, sizeof(format_buffer), self->data[row_index]);
            append_status = smaug_str_append(result_series, format_buffer, formatted_length);
        } else {
            append_status = smaug_str_append_null(result_series);
        }
        if (append_status != 0) { smaug_str_free(result_series); return NULL; }  /* COV-EXCL-BR: OOM no append */
    }
    return result_series;
}

/* datetime -> string: ISO 8601 via smaug_dt_format (mesma primitiva do
   oraculo). buf[40] >= 26 (requisito) e cobre qualquer ano de int64 epoch_ms
   (<= ~292M, 9 digitos): o ramo de falha do format e defensivo/inalcancavel. */
smaug_series_str_t *smaug_dt_to_str(const smaug_series_dt_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_str_t *result_series =
        smaug_str_create_with_capacity(0, self->size ? self->size * 26 : 1);
    if (!result_series) return NULL;     /* COV-EXCL-BR: OOM sem injecao */
    char format_buffer[40];  /* >= 26 (requisito de dt_format) e cobre qualquer ano de
                      int64 epoch_ms (ISO <= ~30 chars): format sempre sucede,
                      como o oraculo assume — sem ramo de falha alcancavel. */
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        int append_status;
        if (SMAUG_VALID(self->null_mask, row_index)) {
            (void)smaug_dt_format(self->data[row_index], format_buffer, sizeof(format_buffer));
            append_status = smaug_str_append(result_series, format_buffer, strlen(format_buffer));
        } else {
            append_status = smaug_str_append_null(result_series);
        }
        if (append_status != 0) { smaug_str_free(result_series); return NULL; }  /* COV-EXCL-BR: OOM no append */
    }
    return result_series;
}

/* ===================================================================
   GRUPO B-in — string -> {int64, float64, datetime}
   Parsing rigido via fonte unica (smaug_convert): rejeita trailing,
   vazio, overflow; i64 rejeita hex/float, f64 aceita hex/inf/nan.
   Numerico inconversivel -> null (Contrato 2); datetime falha com status.
   Diverge de proposito do oraculo
   `tonumber` (permissivo) — falha visivel > acerto adivinhado, e
   coerencia com o str->num do CSV. Destino sao arrays diretos
   (create + escrita direta), como o Grupo A.
   =================================================================== */

/* string -> int64: strtoll base 10 (via smaug_parse_i64). */
smaug_series_i64_t *smaug_str_to_i64(const smaug_series_str_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_i64_t *result_series = smaug_i64_create(self->size);
    if (!result_series) return NULL;     /* COV-EXCL-BR: OOM sem injecao */
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        if (SMAUG_VALID(self->null_mask, row_index)) {
            const char *text = self->buffer + self->offsets[row_index];
            size_t len    = self->offsets[row_index + 1] - self->offsets[row_index];
            int64_t value;
            if (smaug_parse_i64(text, len, &value)) {
                result_series->data[row_index]      = value;
                result_series->null_mask[row_index] = SMAUG_MASK_VALID;
            }
            /* inconversivel -> permanece null */
        }
    }
    return result_series;
}

/* string -> float64: strtod (via smaug_parse_f64). */
smaug_series_f64_t *smaug_str_to_f64(const smaug_series_str_t *self) {
    if (!self) return NULL;  /* contrato: engine nao confia no caller (testado com NULL em test_astype) */
    smaug_series_f64_t *result_series = smaug_f64_create(self->size);
    if (!result_series) return NULL;     /* COV-EXCL-BR: OOM sem injecao */
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        if (SMAUG_VALID(self->null_mask, row_index)) {
            const char *text = self->buffer + self->offsets[row_index];
            size_t len    = self->offsets[row_index + 1] - self->offsets[row_index];
            double value;
            if (smaug_parse_f64(text, len, &value)) {
                result_series->data[row_index]      = value;
                result_series->null_mask[row_index] = SMAUG_MASK_VALID;
            }
        }
    }
    return result_series;
}

/* Preserva a ABI legada, mas nao entrega resultado parcial em falha. */
smaug_series_dt_t *smaug_str_to_dt(const smaug_series_str_t *self, int dayfirst) {
    smaug_series_dt_t *result_series = NULL;
    smaug_str_to_dt_checked(self, dayfirst, &result_series, NULL);
    return result_series;
}

smaug_status_t smaug_str_to_dt_checked(const smaug_series_str_t *self,
                                     int dayfirst, smaug_series_dt_t **out,
                                     size_t *error_index) {
    if (!self || !out || (dayfirst != 0 && dayfirst != 1)) return SMG_ERR_ARGUMENT;
    smaug_series_dt_t *result_series = smaug_dt_create(self->size);
    if (!result_series) return SMG_ERR_NOMEM;
    for (size_t row_index = 0; row_index < self->size; row_index++) {
        if (!SMAUG_VALID(self->null_mask, row_index)) continue;
        const char *text = self->buffer + self->offsets[row_index];
        size_t length = self->offsets[row_index + 1] - self->offsets[row_index];
        int64_t epoch_ms;
        smaug_status_t status = smaug_dt_parse_checked(text, length, &epoch_ms, dayfirst);
        if (status != SMG_OK) {
            smaug_dt_free(result_series);
            if (error_index) *error_index = row_index;
            return status;
        }
        result_series->data[row_index] = epoch_ms;
        result_series->null_mask[row_index] = SMAUG_MASK_VALID;
    }
    *out = result_series;
    return SMG_OK;
}
