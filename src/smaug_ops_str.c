/* src/smaug_ops_str.c
 *
 * Operações sobre o tipo string (offset-based). Separado do lifecycle/acesso
 * (smaug_str.c) como nos numéricos (core vs ops). Esta peça: comparações
 * (eq/lt/gt) contra uma string-alvo, retornando máscara booleana.
 *
 * Ordem lexicográfica por BYTES (não Unicode-aware — ver Roadmap sobre UTF-8).
 * Otimização honesta (a mesma dos modelos de referência para string simples):
 *   - eq: compara COMPRIMENTO primeiro (O(1) via offsets); só faz memcmp se
 *     os comprimentos baterem (pula o memcmp na maioria dos "diferentes").
 *   - lt/gt: memcmp até o menor comprimento, desempata pelo comprimento.
 * (A otimização real para string repetida é o dictionary encoding / categorical,
 * Tier 2 — ver Roadmap. As comparações daqui seguem válidas; o categorical será
 * um tipo separado que implementa a mesma interface de forma acelerada.)
 */

#include "smaug_string.h"
#include <stdlib.h>
#include <string.h>

/* Compara a string no índice idx com (target,target_len), lexicográfico por
   bytes. Retorna <0, 0 ou >0 (como memcmp/strcmp). */
static int str_cmp_at(const smaug_series_str_t *s, size_t idx,
                      const char *target, size_t target_len) {
    size_t start = s->offsets[idx];
    size_t len   = s->offsets[idx + 1] - start;
    size_t min   = len < target_len ? len : target_len;
    int c = (min > 0) ? memcmp(s->buffer + start, target, min) : 0;
    if (c != 0) return c;
    /* prefixo igual: a mais curta vem antes (lexicográfico padrão) */
    if (len < target_len) return -1;
    if (len > target_len) return  1;
    return 0;
}

/* Núcleo comum das três comparações: aplica `keep(cmp)` a cada elemento válido.
   mode: 0 = eq, -1 = lt (cmp<0), +1 = gt (cmp>0). */
static uint8_t *str_compare(const smaug_series_str_t *s, const char *target,
                            size_t target_len, smaug_mask_t **out_mask, int mode) {
    if (!s) return NULL;
    if (!target && target_len > 0) return NULL;

    uint8_t *result = malloc(s->size ? s->size : 1);
    if (!result) return NULL;

    smaug_mask_t *mask = NULL;
    if (out_mask) {
        mask = malloc(s->size ? s->size : 1);
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }

    for (size_t i = 0; i < s->size; i++) {
        if (s->null_mask[i] == 0x00) {        /* NULL -> indefinido */
            result[i] = 0;
            if (mask) mask[i] = 0x00;
            continue;
        }
        int r;
        if (mode == 0) {
            /* eq: comprimento primeiro (O(1)); memcmp só se baterem */
            size_t len = s->offsets[i + 1] - s->offsets[i];
            if (len != target_len) {
                r = 0;                         /* comprimentos diferentes -> != */
            } else {
                r = (len == 0) ? 1
                  : (memcmp(s->buffer + s->offsets[i], target, len) == 0);
            }
            result[i] = (uint8_t)r;
        } else {
            int c = str_cmp_at(s, i, target, target_len);
            result[i] = (uint8_t)((mode < 0) ? (c < 0) : (c > 0));
        }
        if (mask) mask[i] = 0xFF;
    }
    return result;
}

uint8_t *smaug_str_eq(const smaug_series_str_t *s, const char *target,
                      size_t target_len, smaug_mask_t **out_mask) {
    return str_compare(s, target, target_len, out_mask, 0);
}

uint8_t *smaug_str_lt(const smaug_series_str_t *s, const char *target,
                      size_t target_len, smaug_mask_t **out_mask) {
    return str_compare(s, target, target_len, out_mask, -1);
}

uint8_t *smaug_str_gt(const smaug_series_str_t *s, const char *target,
                      size_t target_len, smaug_mask_t **out_mask) {
    return str_compare(s, target, target_len, out_mask, 1);
}

/* ===================================================================
   Seleção: filter (por máscara booleana) e take (por índices)
   Ambos retornam uma NOVA série (cópia). Reusam append/append_null, que já
   gerenciam buffer/offsets de tamanho variável (Valgrind-clean) — evita mexer
   em offsets na mão aqui. NULL é preservado (append_null). NULL no resultado
   mantém a semântica: o elemento seguia NULL na origem.
   =================================================================== */

/* filter: mantém os elementos onde mask[i] != 0. mask tem s->size entradas. */
smaug_series_str_t *smaug_str_filter(const smaug_series_str_t *s,
                                     const uint8_t *mask) {
    if (!s || !mask) return NULL;

    /* passo 1: conta quantos passam e soma os bytes (dimensiona o buffer) */
    size_t count = 0, bytes = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (mask[i]) {
            count++;
            bytes += s->offsets[i + 1] - s->offsets[i];
        }
    }

    smaug_series_str_t *r = smaug_str_create_with_capacity(0, bytes ? bytes : 1);
    if (!r) return NULL;

    /* passo 2: copia cada elemento que passa, preservando NULL */
    for (size_t i = 0; i < s->size; i++) {
        if (!mask[i]) continue;
        int rc;
        if (s->null_mask[i] == 0x00) {
            rc = smaug_str_append_null(r);
        } else {
            size_t start = s->offsets[i];
            size_t len   = s->offsets[i + 1] - start;
            rc = smaug_str_append(r, s->buffer + start, len);
        }
        if (rc != 0) { smaug_str_free(r); return NULL; }   /* OOM */
    }
    return r;
}

/* take: nova série com os elementos nos índices idx[0..len). Índice fora dos
   limites -> retorna NULL (erro). */
smaug_series_str_t *smaug_str_take(const smaug_series_str_t *s,
                                   const size_t *idx, size_t len) {
    if (!s || (!idx && len > 0)) return NULL;

    /* passo 1: valida índices e soma bytes */
    size_t bytes = 0;
    for (size_t k = 0; k < len; k++) {
        if (idx[k] >= s->size) return NULL;                /* fora dos limites */
        bytes += s->offsets[idx[k] + 1] - s->offsets[idx[k]];
    }

    smaug_series_str_t *r = smaug_str_create_with_capacity(0, bytes ? bytes : 1);
    if (!r) return NULL;

    /* passo 2: copia na ordem dos índices, preservando NULL */
    for (size_t k = 0; k < len; k++) {
        size_t i = idx[k];
        int rc;
        if (s->null_mask[i] == 0x00) {
            rc = smaug_str_append_null(r);
        } else {
            size_t start = s->offsets[i];
            size_t l     = s->offsets[i + 1] - start;
            rc = smaug_str_append(r, s->buffer + start, l);
        }
        if (rc != 0) { smaug_str_free(r); return NULL; }
    }
    return r;
}
