#ifndef SMAUG_STRING_H
#define SMAUG_STRING_H

/* ===================================================================
   smaug_string.h — Tipo string (offset-based, estilo Arrow)
   -------------------------------------------------------------------
   6º header do Smaug, irmão de smaug_core.h. Lifecycle e acesso do tipo
   string, cuja representação (buffer concatenado + offsets) está em
   smaug_types.h (smaug_series_str_t). Inclui apenas smaug_types.h — o
   string tem lifecycle próprio (tamanho variável exige gerência do buffer
   de bytes, diferente dos numéricos de tamanho fixo), então não depende de
   smaug_core.h.

   Implementado em src/smaug_ops_str.c.

   Convenções (iguais às do restante do backend):
     - Índices 0-based no C (o frontend Lua converte de 1-based).
     - Nulos por bitmask paralelo (0xFF válido, 0x00 NULL); o null_mask é a
       fonte de verdade. String vazia "" é DISTINTA de NULL.
     - Strings NÃO são terminadas em \0 no buffer; o comprimento vem dos
       offsets. As funções de acesso devolvem ponteiro + comprimento.
     - As funções validam ponteiro/índice e falham de forma previsível (ver
       "Contrato de entrada" em smaug_core.h) — não corrompem memória.
   =================================================================== */

#include "smaug_types.h"

/* ===================== Lifecycle ===================== */

/* Cria uma série de `size` strings, todas NULL inicialmente. O buffer começa
   com uma capacidade inicial pequena e cresce conforme as strings entram. */
smaug_series_str_t* smaug_str_create(size_t size);

/* Cria já reservando `buffer_capacity` bytes no buffer (evita realocações
   quando o tamanho total do texto é conhecido). `size` strings, NULL no início. */
smaug_series_str_t* smaug_str_create_with_capacity(size_t size, size_t buffer_capacity);

/* Cria a partir de um array de C-strings (terminadas em \0). `array[i]` NULL
   (ponteiro nulo) vira elemento NULL. Retorna NULL em falha de alocação. */
smaug_series_str_t* smaug_str_create_from_array(const char *const *array, size_t len);

void                smaug_str_free(smaug_series_str_t *s);
smaug_series_str_t* smaug_str_clone(const smaug_series_str_t *s);

/* ===================== Acesso ===================== */

/* Lê a string no índice idx. NÃO copia: devolve ponteiro para dentro do buffer
   e escreve o comprimento em *out_len. Retorna NULL se idx for inválido ou o
   elemento for NULL (nesse caso *out_len = 0). O ponteiro é válido enquanto a
   série não for modificada/liberada. */
const char* smaug_str_get(const smaug_series_str_t *s, size_t idx, size_t *out_len);

/* Define a string no índice idx (copia `len` bytes de `str` para o buffer).
   Como a representação é offset-based, isto pode exigir remontar o buffer —
   operação O(n) no pior caso; a construção típica é em lote. Retorna 0 em
   sucesso, -1 em erro (idx inválido, OOM). */
int  smaug_str_set(smaug_series_str_t *s, size_t idx, const char *str, size_t len);

smaug_status_t smaug_str_set_null(smaug_series_str_t *s, size_t idx);
bool smaug_str_is_null(const smaug_series_str_t *s, size_t idx);

/* Acrescenta uma string ao final (cresce a série). 0 = ok, -1 = erro. */
int  smaug_str_append(smaug_series_str_t *s, const char *str, size_t len);
int  smaug_str_append_null(smaug_series_str_t *s);

/* ===================== Utilidades ===================== */

size_t smaug_str_count_nonnull(const smaug_series_str_t *s);

/* ===================== Comparações ===================== */
/* Comparam cada elemento contra uma string-alvo (target + target_len). Retornam
   um array uint8_t* (1/0) de tamanho s->size e, via out_mask, a máscara de
   validade (elemento NULL -> resultado 0, máscara 0x00 — comparar com ausência
   é indefinido). String vazia "" é valor válido e compara normalmente.
   Ordem lexicográfica por BYTES (não Unicode-aware; ver Roadmap sobre UTF-8).
   Retornam NULL em falha de alocação. O caller libera result e *out_mask. */
uint8_t* smaug_str_eq(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);
uint8_t* smaug_str_lt(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);
uint8_t* smaug_str_gt(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);

/* ===================== Seleção ===================== */
/* filter: nova série com os elementos onde mask[i] != 0 (mask tem s->size
   entradas; tipicamente vinda de uma comparação). NULL é preservado.
   take: nova série com os elementos nos índices idx[0..len) (na ordem dada);
   índice fora dos limites -> NULL. Ambos retornam NULL em falha de alocação.
   O caller é dono da série retornada (smaug_str_free). */
smaug_series_str_t* smaug_str_filter(const smaug_series_str_t *s, const uint8_t *mask);
smaug_series_str_t* smaug_str_take  (const smaug_series_str_t *s, const size_t *idx, size_t len);

/* ===================== Ordenação ===================== */
/* argsort: permutação de índices que ordena a série (lexicográfico por bytes);
   o caller é dono do array (free). sort: nova série ordenada (= argsort+take).
   Política: RECUSAM séries com qualquer NULL (retornam NULL) — ordenar com
   ausência é indefinido; use dropna antes. String vazia "" ordena normalmente.
   ascending=true ordem crescente; false decrescente. NULL em falha de alocação. */
size_t*             smaug_str_argsort(const smaug_series_str_t *s, bool ascending);
smaug_series_str_t* smaug_str_sort   (const smaug_series_str_t *s, bool ascending);

/* NOTA: comparações (eq/lt/gt) — ESTA peça. sort/argsort, take/filter e a
   evolução para dictionary encoding (via tipo `categorical`, Tier 2) são fases
   posteriores — ver Roadmap. */

#endif /* SMAUG_STRING_H */
