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

/* Modos de comparação para str_compare. */
#define STR_CMP_EQ  0   /* ==  */
#define STR_CMP_LT (-1) /* <   */
#define STR_CMP_GT  1   /* >   */
#define STR_CMP_GE  2   /* >=  */
#define STR_CMP_LE (-2) /* <=  */
#define STR_CMP_NE  3   /* !=  */

/* Núcleo comum das seis comparações. */
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
        if (SMAUG_NULL(s->null_mask, i)) {        /* NULL -> indefinido */
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
            continue;
        }
        int r;
        if (mode == STR_CMP_EQ || mode == STR_CMP_NE) {
            /* eq/ne: comprimento primeiro (O(1)); memcmp só se baterem */
            size_t len = s->offsets[i + 1] - s->offsets[i];
            int eq;
            if (len != target_len) {
                eq = 0;
            } else {
                eq = (len == 0) ? 1
                   : (memcmp(s->buffer + s->offsets[i], target, len) == 0);
            }
            r = (mode == STR_CMP_EQ) ? eq : !eq;
        } else {
            int c = str_cmp_at(s, i, target, target_len);
            switch (mode) {   /* COV-EXCL-BR: mode e enum interno (LT/GT/LE/GE aqui); case default inalcancavel */
                case STR_CMP_LT: r = (c <  0); break;
                case STR_CMP_GT: r = (c >  0); break;
                case STR_CMP_LE: r = (c <= 0); break;
                case STR_CMP_GE: r = (c >= 0); break;
                default:         r = 0;        break;
            }
        }
        result[i] = (uint8_t)r;
        if (mask) mask[i] = SMAUG_MASK_VALID;
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

uint8_t *smaug_str_ge(const smaug_series_str_t *s, const char *target,
                      size_t target_len, smaug_mask_t **out_mask) {
    return str_compare(s, target, target_len, out_mask, STR_CMP_GE);
}

uint8_t *smaug_str_le(const smaug_series_str_t *s, const char *target,
                      size_t target_len, smaug_mask_t **out_mask) {
    return str_compare(s, target, target_len, out_mask, STR_CMP_LE);
}

uint8_t *smaug_str_ne(const smaug_series_str_t *s, const char *target,
                      size_t target_len, smaug_mask_t **out_mask) {
    return str_compare(s, target, target_len, out_mask, STR_CMP_NE);
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

    /* passo 1: soma os bytes dos que passam (dimensiona o buffer) */
    size_t bytes = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (mask[i]) bytes += s->offsets[i + 1] - s->offsets[i];
    }

    smaug_series_str_t *r = smaug_str_create_with_capacity(0, bytes ? bytes : 1);
    if (!r) return NULL;

    /* passo 2: copia cada elemento que passa, preservando NULL */
    for (size_t i = 0; i < s->size; i++) {
        if (!mask[i]) continue;
        int rc;
        if (SMAUG_NULL(s->null_mask, i)) {
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
        if (SMAUG_NULL(s->null_mask, i)) {
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

/* ===================================================================
   Ordenação: argsort (permutação de índices) e sort (nova série ordenada)
   Política (coerente com os numéricos): RECUSA séries com qualquer NULL —
   ordenar com ausência é indefinido (use dropna antes). Retorna NULL nesse
   caso. String vazia "" é valor válido e ordena normalmente (vem primeiro).
   Ordem lexicográfica por bytes (reusa str_cmp_at). sort = argsort + take.
   =================================================================== */

/* Contexto para a comparação do qsort (que não recebe argumento de usuário).
   Single-thread: o projeto não usa threads. Documentado como limitação. */
static const smaug_series_str_t *g_sort_series = NULL;
static bool g_sort_ascending = true;

static int sort_cmp(const void *pa, const void *pb) {
    size_t ia = *(const size_t *)pa;
    size_t ib = *(const size_t *)pb;
    const smaug_series_str_t *s = g_sort_series;

    size_t sa = s->offsets[ia], la = s->offsets[ia + 1] - sa;
    size_t sb = s->offsets[ib], lb = s->offsets[ib + 1] - sb;
    size_t min = la < lb ? la : lb;
    int c = (min > 0) ? memcmp(s->buffer + sa, s->buffer + sb, min) : 0;
    if (c == 0) {                       /* prefixo igual: mais curta antes */
        c = (la < lb) ? -1 : (la > lb) ? 1 : 0;
    }
    /* desempate estável por índice (qsort não é estável; isto torna
       determinístico para elementos iguais) */
    if (c == 0) c = (ia < ib) ? -1 : (ia > ib) ? 1 : 0;  /* COV-EXCL-BR: ia==ib inalcancavel (indices sempre unicos no argsort) */
    return g_sort_ascending ? c : -c;
}

size_t *smaug_str_argsort(const smaug_series_str_t *s, bool ascending) {
    if (!s) return NULL;

    /* recusa se houver qualquer NULL (coerente com os numéricos) */
    for (size_t i = 0; i < s->size; i++)
        if (SMAUG_NULL(s->null_mask, i)) return NULL;

    size_t *idx = malloc((s->size ? s->size : 1) * sizeof(size_t));
    if (!idx) return NULL;
    for (size_t i = 0; i < s->size; i++) idx[i] = i;

    g_sort_series    = s;
    g_sort_ascending = ascending;
    qsort(idx, s->size, sizeof(size_t), sort_cmp);
    g_sort_series    = NULL;            /* limpa o contexto global */

    return idx;
}

smaug_series_str_t *smaug_str_sort(const smaug_series_str_t *s, bool ascending) {
    if (!s) return NULL;
    size_t *idx = smaug_str_argsort(s, ascending);
    if (!idx) return NULL;              /* NULL presente, ou OOM */
    smaug_series_str_t *r = smaug_str_take(s, idx, s->size);
    free(idx);
    return r;
}

/* ===================================================================
   Movimentação de dados agnóstica a tipo (item 7.1): ffill / bfill
   para string. Diferente de f64/i64/bool/dt (buffer plano), a string é
   offset-based: a série nova é reconstruída por append, reusando o mesmo
   padrão de smaug_str_take (gather posicional). NÃO é view — produz cópia
   completa, então a limitação de view-em-string (ver COW.md) não se aplica.
   =================================================================== */

/* ffill: cada posição recebe a string da última posição válida anterior
   (incluindo ela mesma, se válida). Posições antes do primeiro válido → NA. */
smaug_series_str_t *smaug_str_ffill(const smaug_series_str_t *s) {
    if (!s) return NULL;

    /* passo 1: para cada posição, o índice-fonte (última válida até aqui),
       e soma de bytes do resultado. SIZE_MAX = sem fonte (permanece NA). */
    size_t bytes = 0, last = SIZE_MAX;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) last = i;
        if (last != SIZE_MAX)
            bytes += s->offsets[last + 1] - s->offsets[last];
    }

    smaug_series_str_t *r = smaug_str_create_with_capacity(0, bytes ? bytes : 1);
    if (!r) return NULL;

    /* passo 2: append na ordem, repetindo a última válida */
    last = SIZE_MAX;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) last = i;
        int rc;
        if (last == SIZE_MAX) {
            rc = smaug_str_append_null(r);
        } else {
            size_t start = s->offsets[last];
            size_t l     = s->offsets[last + 1] - start;
            rc = smaug_str_append(r, s->buffer + start, l);
        }
        if (rc != 0) { smaug_str_free(r); return NULL; }
    }
    return r;
}

/* bfill: cada posição recebe a string da próxima posição válida seguinte
   (incluindo ela mesma, se válida). Posições após o último válido → NA. */
smaug_series_str_t *smaug_str_bfill(const smaug_series_str_t *s) {
    if (!s) return NULL;

    /* passo 1: soma de bytes percorrendo de trás para frente */
    size_t bytes = 0, next = SIZE_MAX;
    for (size_t i = s->size; i-- > 0; ) {
        if (SMAUG_VALID(s->null_mask, i)) next = i;
        if (next != SIZE_MAX)
            bytes += s->offsets[next + 1] - s->offsets[next];
    }

    smaug_series_str_t *r = smaug_str_create_with_capacity(0, bytes ? bytes : 1);
    if (!r) return NULL;

    /* passo 2: precisa preencher na ordem natural (append é sequencial),
       então recalcula a próxima-válida para cada i da esquerda p/ direita.
       Pré-computa o índice-fonte de cada posição num passo reverso. */
    size_t *src = malloc((s->size ? s->size : 1) * sizeof(size_t));
    if (!src) { smaug_str_free(r); return NULL; }
    next = SIZE_MAX;
    for (size_t i = s->size; i-- > 0; ) {
        if (SMAUG_VALID(s->null_mask, i)) next = i;
        src[i] = next;
    }

    for (size_t i = 0; i < s->size; i++) {
        int rc;
        if (src[i] == SIZE_MAX) {
            rc = smaug_str_append_null(r);
        } else {
            size_t start = s->offsets[src[i]];
            size_t l     = s->offsets[src[i] + 1] - start;
            rc = smaug_str_append(r, s->buffer + start, l);
        }
        if (rc != 0) { free(src); smaug_str_free(r); return NULL; }
    }
    free(src);
    return r;
}

/* shift(periods): desloca por `periods` posições, com sinal. Offset-based,
   reconstruído por append (mesmo padrão de ffill/bfill). Para cada posição i a
   fonte é (i - periods); fora de [0, size) → NA. (Item 7.1b.) */
smaug_series_str_t *smaug_str_shift(const smaug_series_str_t *s, int64_t periods) {
    if (!s) return NULL;

    size_t n = s->size;
    /* |periods| >= size → toda NA: série de n nulls. */
    int all_null = (periods <= -(int64_t)n || periods >= (int64_t)n);

    /* passo 1: soma de bytes do resultado (só posições com fonte válida e não-NA) */
    size_t bytes = 0;
    if (!all_null) {
        for (size_t i = 0; i < n; i++) {
            int64_t src = (int64_t)i - periods;
            if (src >= 0 && (size_t)src < n && SMAUG_VALID(s->null_mask, src))
                bytes += s->offsets[src + 1] - s->offsets[src];
        }
    }

    smaug_series_str_t *r = smaug_str_create_with_capacity(0, bytes ? bytes : 1);
    if (!r) return NULL;

    /* passo 2: append na ordem das posições de saída */
    for (size_t i = 0; i < n; i++) {
        int rc;
        int64_t src = all_null ? -1 : (int64_t)i - periods;
        if (src < 0 || (size_t)src >= n || SMAUG_NULL(s->null_mask, src)) {
            rc = smaug_str_append_null(r);
        } else {
            size_t start = s->offsets[src];
            size_t l     = s->offsets[src + 1] - start;
            rc = smaug_str_append(r, s->buffer + start, l);
        }
        if (rc != 0) { smaug_str_free(r); return NULL; }
    }
    return r;
}
