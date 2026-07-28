#ifndef SMAUG_DATETIME_H
#define SMAUG_DATETIME_H

/* ===================================================================
   smaug_datetime.h — Dtype datetime (Anel 0, Tier 2)
   -------------------------------------------------------------------
   Armazenamento: epoch em milissegundos UTC (int64). Valores negativos
   representam datas antes de 1970-01-01. Resolução: 1 ms.

   Calendário: Gregoriano proléptico. Nenhuma dependência de timezone —
   UTC no armazenamento, apresentação local é responsabilidade do caller.

   Contrato de fronteira: mesmo princípio dos outros dtypes.
     - O engine não confia no caller: valida ponteiro/índice antes de
       tocar memória.
     - get: retorna valor + smaug_status_t* anulável.
     - set/set_null: retorna smaug_status_t; em erro nenhuma escrita.
     - Null por bitmask uniforme (0xFF = válido, 0x00 = NULL).

   Funções de calendário trabalham com o valor epoch_ms de um único
   elemento — não alocam série nova. Frontend Lua usa :map() para
   aplicar em toda a série.

   Implementado em src/smaug_datetime.c.
   =================================================================== */

#include "smaug_types.h"
#include <stdbool.h>

/* ===================== Lifecycle ===================== */

smaug_series_dt_t* smaug_dt_create(size_t size);
smaug_series_dt_t* smaug_dt_create_with_capacity(size_t size, size_t capacity);

/* Cria a partir de um array de epoch_ms (todos marcados como válidos). */
smaug_series_dt_t* smaug_dt_create_from_array(const int64_t *array, size_t len);

void               smaug_dt_free(smaug_series_dt_t *s);
smaug_series_dt_t* smaug_dt_clone(const smaug_series_dt_t *s);

/* coalesce_scalar (null-mask): onde self[i] é nulo, entra value (epoch_ms);
   senão self[i]. Serve fillna. */
smaug_series_dt_t* smaug_dt_coalesce_scalar(const smaug_series_dt_t *self, int64_t value);

/* coalesce (null-mask, série+série): onde self[i] é nulo entra other[i]
   (epoch_ms, se válido); senão self[i]. Ambos nulos → nulo. Serve combine_first. */
smaug_series_dt_t* smaug_dt_coalesce(const smaug_series_dt_t *self, const smaug_series_dt_t *other);

/* select (cond-bool): cond[i] true → a[i], senão (false/NA) → b[i]. Preserva a
   nulidade do operando escolhido. Unifica where/mask/ifelse. */
smaug_series_dt_t* smaug_dt_select(const smaug_series_bool_t *cond,
                                   const smaug_series_dt_t *a,
                                   const smaug_series_dt_t *b);
smaug_series_dt_t* smaug_dt_view(smaug_series_dt_t *s, size_t start, size_t len);

/* ===================== Acesso ===================== */

/* Retorna epoch_ms + status. Sentinela em erro/null: INT64_MIN. */
int64_t        smaug_dt_get(const smaug_series_dt_t *s, size_t idx,
                             smaug_status_t *status);
smaug_status_t smaug_dt_set(smaug_series_dt_t *s, size_t idx, int64_t epoch_ms);
smaug_status_t smaug_dt_set_null(smaug_series_dt_t *s, size_t idx);
bool           smaug_dt_is_null(const smaug_series_dt_t *s, size_t idx);

/* Append dinâmico (0 = ok, -1 = erro). */
int smaug_dt_append(smaug_series_dt_t *s, int64_t epoch_ms);
int smaug_dt_append_null(smaug_series_dt_t *s);

/* ===================== Parsing ===================== */

/* Converte string ISO 8601 para epoch_ms.
   Formatos suportados:
     "YYYY-MM-DD"                  → meia-noite UTC
     "YYYY-MM-DDTHH:MM:SS"         → sem offset → UTC
     "YYYY-MM-DDTHH:MM:SS.mmm"     → com milissegundos
     "YYYY-MM-DDTHH:MM:SS±HH:MM"   → com offset de timezone
     "YYYY-MM-DDTHH:MM:SSZ"        → UTC explícito
   Retorna 0 em sucesso, -1 em formato inválido.
   epoch_ms é escrito apenas em sucesso. */
/* Parseia data/datetime. dayfirst: para formatos com ano no fim
   (DD/MM/YYYY vs MM/DD/YYYY), 1 = dia primeiro, 0 = mês primeiro. Formatos
   year-first (YYYY-MM-DD) ignoram dayfirst (ordem não-ambígua). */
int smaug_dt_parse(const char *str, size_t len, int64_t *epoch_ms, int dayfirst);

/* Formata epoch_ms como string ISO 8601 UTC no buffer.
   Formato: "YYYY-MM-DDTHH:MM:SS.mmmZ" (25 chars + \0 = 26 bytes).
   buf deve ter pelo menos 26 bytes. Retorna 0 em sucesso, -1 em erro. */
int smaug_dt_format(int64_t epoch_ms, char *buf, size_t buf_size);

/* ===================== Extração de componentes =====================
   Todas as funções recebem epoch_ms direto (não série).
   Calendário Gregoriano proléptico, UTC.
   Retornam -1 em caso de overflow ou valor inválido. */

int smaug_dt_year   (int64_t epoch_ms);   /* ex.: 2026                  */
int smaug_dt_month  (int64_t epoch_ms);   /* 1–12                       */
int smaug_dt_day    (int64_t epoch_ms);   /* 1–31                       */
int smaug_dt_hour   (int64_t epoch_ms);   /* 0–23                       */
int smaug_dt_minute (int64_t epoch_ms);   /* 0–59                       */
int smaug_dt_second (int64_t epoch_ms);   /* 0–59                       */
int smaug_dt_ms     (int64_t epoch_ms);   /* 0–999 milissegundos        */
int smaug_dt_weekday(int64_t epoch_ms);   /* 0=seg, 1=ter, …, 6=dom     */
int smaug_dt_yearday(int64_t epoch_ms);   /* 1–366                      */
int smaug_dt_quarter(int64_t epoch_ms);   /* 1–4                        */
int smaug_dt_week   (int64_t epoch_ms);   /* 1–53 (ISO 8601, segunda-fair) */

/* ===================== Construção de epoch_ms ===================== */

/* Constrói epoch_ms a partir de componentes UTC.
   ms é opcional (0 se não houver precisão sub-segundo).
   Retorna INT64_MIN em caso de data inválida. */
int64_t smaug_dt_from_parts(int year, int month, int day,
                              int hour, int minute, int second, int ms);

/* ===================== Aritmética ===================== */

/* Diferença entre dois epoch_ms em milissegundos (a - b). */
int64_t smaug_dt_diff_ms(int64_t a, int64_t b);

/* Adiciona delta_ms a epoch_ms (saturação em overflow: retorna INT64_MIN). */
int64_t smaug_dt_add_ms(int64_t epoch_ms, int64_t delta_ms);

/* Trunca epoch_ms para o início do período especificado (UTC).
   unit: 's' = segundo, 'm' = minuto, 'h' = hora, 'D' = dia,
         'W' = semana (segunda-feira), 'M' = mês, 'Q' = trimestre, 'Y' = ano.
   Retorna INT64_MIN em caso de unit inválida. */
int64_t smaug_dt_truncate(int64_t epoch_ms, char unit);

/* ===================== Comparações (série) ===================== */

/* Compara cada elemento contra um threshold (epoch_ms escalar).
   Retornam array uint8_t* (1/0) + out_mask (via ponteiro).
   NULL em erro. Caller libera com smaug_free. */
uint8_t* smaug_dt_gt(const smaug_series_dt_t *s, int64_t threshold,
                      smaug_mask_t **out_mask);
uint8_t* smaug_dt_lt(const smaug_series_dt_t *s, int64_t threshold,
                      smaug_mask_t **out_mask);
uint8_t* smaug_dt_eq(const smaug_series_dt_t *s, int64_t threshold,
                      smaug_mask_t **out_mask);
uint8_t* smaug_dt_ge(const smaug_series_dt_t *s, int64_t threshold,
                      smaug_mask_t **out_mask);
uint8_t* smaug_dt_le(const smaug_series_dt_t *s, int64_t threshold,
                      smaug_mask_t **out_mask);
uint8_t* smaug_dt_ne(const smaug_series_dt_t *s, int64_t threshold,
                      smaug_mask_t **out_mask);
/* between: lo..hi numa passada; inc_lo/inc_hi dao os 4 modos de inclusividade.
   epoch_ms e int64_t -> comparacao exata em toda a faixa. */
uint8_t* smaug_dt_between(const smaug_series_dt_t *s, int64_t lo, int64_t hi,
                          bool inc_lo, bool inc_hi, smaug_mask_t **out_mask);

/* ===================== Ordenação ===================== */

/* Recusam série com qualquer NULL (retornam NULL).
   Ordem cronológica (ascending=true). Caller libera com smaug_free. */
size_t*             smaug_dt_argsort(const smaug_series_dt_t *s, bool ascending);
smaug_series_dt_t*  smaug_dt_sort   (const smaug_series_dt_t *s, bool ascending);

/* ===================== Seleção ===================== */

size_t             smaug_dt_count_nonnull(const smaug_series_dt_t *s);
smaug_series_dt_t* smaug_dt_take  (const smaug_series_dt_t *s,
                                    const size_t *idx, size_t len);
smaug_series_dt_t* smaug_dt_filter(const smaug_series_dt_t *s,
                                    const uint8_t *mask);

/* Movimentação de dados agnóstica a tipo (item 7.1): preenche NA com o
   último (ffill) / próximo (bfill) valor válido. Série nova; NA nas bordas
   sem fonte permanecem NA. */
smaug_series_dt_t* smaug_dt_ffill (const smaug_series_dt_t *s);
smaug_series_dt_t* smaug_dt_bfill (const smaug_series_dt_t *s);

/* shift(periods): desloca por `periods` posições, com sinal (item 7.1b). */
smaug_series_dt_t* smaug_dt_shift (const smaug_series_dt_t *s, int64_t periods);

/* argmin/argmax(): índice 0-based do menor/maior datetime não-NA; SIZE_MAX se
   vazia/toda-NA. Ordem cronológica (item 7.2a). */
size_t smaug_dt_argmin (const smaug_series_dt_t *s);
size_t smaug_dt_argmax (const smaug_series_dt_t *s);

/* min/max (item 7.2b): menor/maior epoch_ms (cronológico). INT64_MIN
   sinaliza vazia/toda-NA/(ignore_na=false) presença de NA (= sentinela dt). */
int64_t smaug_dt_min (const smaug_series_dt_t *s, bool ignore_na);
int64_t smaug_dt_max (const smaug_series_dt_t *s, bool ignore_na);

/* rank (item 7.3): ranking cronológico, double* (NAN=NA). method 0=avg 1=min 2=max 3=first. */
double* smaug_dt_rank (const smaug_series_dt_t *s, int method);

#endif /* SMAUG_DATETIME_H */
