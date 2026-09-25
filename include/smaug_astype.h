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

   Conversoes para datetime sao estritas: preservam NA e falham sem resultado
   parcial. Os demais pares mantem seus contratos. Implementado em
   src/smaug_astype.c.
   =================================================================== */

#include "smaug_core.h"

/* ---------- Grupo A: conversoes entre arrays diretos (i64/f64/dt) ----------
   float64->int64 trunca e converte inconversiveis em NA.
   ->datetime valida dominio/precisao e retorna NULL em qualquer falha. */
smaug_series_f64_t *smaug_i64_to_f64(const smaug_series_i64_t *self);
smaug_series_i64_t *smaug_f64_to_i64(const smaug_series_f64_t *self);
smaug_series_dt_t  *smaug_i64_to_dt (const smaug_series_i64_t *self);
smaug_series_i64_t *smaug_dt_to_i64 (const smaug_series_dt_t  *self);
smaug_series_dt_t  *smaug_f64_to_dt (const smaug_series_f64_t *self);
smaug_series_f64_t *smaug_dt_to_f64 (const smaug_series_dt_t  *self);

/* Grupo B-out (-> string): num->str usa o formato canonico dos writers C
   (%.17g / %lld), nao o tostring %.14g do Lua — coerencia de aneis e
   round-trip exato. dt->str via smaug_dt_format (paridade por construcao). */
smaug_series_str_t *smaug_i64_to_str(const smaug_series_i64_t *self);
smaug_series_str_t *smaug_f64_to_str(const smaug_series_f64_t *self);
smaug_series_str_t *smaug_dt_to_str (const smaug_series_dt_t  *self);

/* Grupo B-in (string -> {int64, float64, datetime}): parsing rigido via
   smaug_convert (rejeita trailing/vazio/overflow; i64 sem hex, f64 com
   hex/inf/nan). Inconversivel -> null somente nas conversoes numericas. */
smaug_series_i64_t *smaug_str_to_i64(const smaug_series_str_t *self);
smaug_series_f64_t *smaug_str_to_f64(const smaug_series_str_t *self);
smaug_series_dt_t  *smaug_str_to_dt (const smaug_series_str_t *self, int dayfirst);
/* Conversoes estritas para datetime. self/out obrigatorios; dayfirst 0 ou 1
   na variante textual. int64 deve estar no dominio; float64 deve tambem ser
   finito e integral. NaN/inf/fracao -> ARGUMENT; finito fora da faixa -> OVERFLOW.
   A faixa datetime inteira e representavel exatamente em double (< 2^53).
   SMG_OK publica *out (caller libera com smaug_dt_free); falhas preservam *out.
   SMG_ERR_NOMEM e argumento de chamada invalido preservam error_index.
   Com argumentos de chamada validos, ARGUMENT/OVERFLOW indicam falha de
   elemento e escrevem seu primeiro indice (base 0) em error_index, se != NULL.
   Sucesso preserva error_index. NA propaga; entrada nunca e alterada.
   Os wrappers legados delegam aqui e retornam NULL em qualquer falha. */
smaug_status_t smaug_i64_to_dt_checked(const smaug_series_i64_t *self,
                                     smaug_series_dt_t **out, size_t *error_index);
smaug_status_t smaug_f64_to_dt_checked(const smaug_series_f64_t *self,
                                     smaug_series_dt_t **out, size_t *error_index);
smaug_status_t smaug_str_to_dt_checked(const smaug_series_str_t *self,
                                     int dayfirst, smaug_series_dt_t **out,
                                     size_t *error_index);

#endif /* SMAUG_ASTYPE_H */
