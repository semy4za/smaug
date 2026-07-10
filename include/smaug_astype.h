#ifndef SMAUG_ASTYPE_H
#define SMAUG_ASTYPE_H

/* ===================================================================
   smaug_astype.h — Conversão de tipo (matriz src×dst) no Anel 0
   -------------------------------------------------------------------
   Responsabilidade única: converter uma série de um dtype para outro,
   buffer -> buffer, sem round-trip pela fronteira Lua (que passa por
   double em get() e corrompe int64 > 2^53). Isolado dos ops_* de cada
   dtype de proposito — cast e uma responsabilidade propria, nao deve
   se espalhar pelos arquivos de operacao.

   Cobre os 4 dtypes de struct de serie: int64, float64, string,
   datetime. Fora do raio: bool (Anel 1 ate 10.8), categorical (tipo
   Lua puro). A diagonal (mesmo dtype) reusa os smaug_*_clone
   existentes — nao ha primitiva astype para i->i.

   Matriz de conversao (12 primitivas, preenchida nas Fases 1-3):

       de \ para | int64        float64      string       datetime
       ----------+-----------------------------------------------------
       int64     | (clone)      ->f64        ->str         ->dt
       float64   | ->i64        (clone)      ->str         ->dt
       string    | ->i64 (2t)   ->f64        (clone)       ->dt
       datetime  | ->i64        ->f64        ->str         (clone)

   Contrato (herdado do astype Lua, o oraculo): inconversivel -> null,
   a serie inteira nunca e descartada por um dado ruim. Implementado em
   src/smaug_astype.c.
   =================================================================== */

#include "smaug_core.h"

/* ---------- Grupo A: conversoes entre arrays diretos (i64/f64/dt) ----------
   Retorno NULL apenas em self==NULL (contrato) ou OOM. Inconversivel por
   elemento (NaN/inf/fora-do-range em ->i64/->dt) vira null, nunca erro. */
smaug_series_f64_t *smaug_i64_to_f64(const smaug_series_i64_t *self);
smaug_series_i64_t *smaug_f64_to_i64(const smaug_series_f64_t *self);
smaug_series_dt_t  *smaug_i64_to_dt (const smaug_series_i64_t *self);
smaug_series_i64_t *smaug_dt_to_i64 (const smaug_series_dt_t  *self);
smaug_series_dt_t  *smaug_f64_to_dt (const smaug_series_f64_t *self);
smaug_series_f64_t *smaug_dt_to_f64 (const smaug_series_dt_t  *self);

/* Grupos B-out (-> string) e B-in (string ->) entram nas Fases 2-3. */

#endif /* SMAUG_ASTYPE_H */
