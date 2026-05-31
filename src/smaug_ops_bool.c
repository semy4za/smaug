#include "../include/smaug_math.h"
#include <stdlib.h>
#include <stddef.h>

/* ===================================================================
   Operações booleanas com lógica de três valores (Kleene).
   Valores: 1 = true, 0 = false.  Máscara: 0xFF = válido, 0x00 = NA.
   =================================================================== */

#define VALID(m, i) ((m) == NULL || (m)[(i)] == 0xFF)

/* Aloca o par (valores, máscara). Em falha, libera o que tiver alocado e
   devolve NULL (deixando *out_mask intacto/NULL). */
static uint8_t *alloc_pair(size_t n, smaug_mask_t **out_mask) {
    uint8_t *vals = malloc(n ? n : 1);
    if (!vals) return NULL;
    if (out_mask) {
        smaug_mask_t *m = malloc(n ? n : 1);
        if (!m) { free(vals); return NULL; }
        *out_mask = m;
    }
    return vals;
}

/* set helper: grava valor e máscara (se houver) numa posição. */
static inline void put(uint8_t *vals, smaug_mask_t *m, size_t i,
                       int value, int valid) {
    vals[i] = valid ? (value ? 1 : 0) : 0;
    if (m) m[i] = valid ? 0xFF : 0x00;
}

uint8_t *smaug_bool_and(const uint8_t *a, const smaug_mask_t *am,
                        const uint8_t *b, const smaug_mask_t *bm,
                        size_t n, smaug_mask_t **out_mask) {
    if (!a || !b) return NULL;
    smaug_mask_t *m = NULL;
    uint8_t *r = alloc_pair(n, out_mask);
    if (!r) return NULL;
    if (out_mask) m = *out_mask;

    for (size_t i = 0; i < n; i++) {
        int av = VALID(am, i), bv = VALID(bm, i);
        int at = av && a[i], bt = bv && b[i];
        /* Kleene AND: false domina; NA só sobrevive se o outro não é false */
        if ((av && !a[i]) || (bv && !b[i])) {
            put(r, m, i, 0, 1);                 /* algum false -> false */
        } else if (av && bv) {
            put(r, m, i, at && bt, 1);          /* ambos válidos */
        } else {
            put(r, m, i, 0, 0);                 /* NA */
        }
    }
    return r;
}

uint8_t *smaug_bool_or(const uint8_t *a, const smaug_mask_t *am,
                       const uint8_t *b, const smaug_mask_t *bm,
                       size_t n, smaug_mask_t **out_mask) {
    if (!a || !b) return NULL;
    smaug_mask_t *m = NULL;
    uint8_t *r = alloc_pair(n, out_mask);
    if (!r) return NULL;
    if (out_mask) m = *out_mask;

    for (size_t i = 0; i < n; i++) {
        int av = VALID(am, i), bv = VALID(bm, i);
        /* Kleene OR: true domina; NA só sobrevive se o outro não é true */
        if ((av && a[i]) || (bv && b[i])) {
            put(r, m, i, 1, 1);                 /* algum true -> true */
        } else if (av && bv) {
            put(r, m, i, 0, 1);                 /* ambos válidos e false */
        } else {
            put(r, m, i, 0, 0);                 /* NA */
        }
    }
    return r;
}

uint8_t *smaug_bool_xor(const uint8_t *a, const smaug_mask_t *am,
                        const uint8_t *b, const smaug_mask_t *bm,
                        size_t n, smaug_mask_t **out_mask) {
    if (!a || !b) return NULL;
    smaug_mask_t *m = NULL;
    uint8_t *r = alloc_pair(n, out_mask);
    if (!r) return NULL;
    if (out_mask) m = *out_mask;

    for (size_t i = 0; i < n; i++) {
        int av = VALID(am, i), bv = VALID(bm, i);
        if (av && bv) put(r, m, i, (a[i] != 0) ^ (b[i] != 0), 1);
        else          put(r, m, i, 0, 0);       /* qualquer NA -> NA */
    }
    return r;
}

uint8_t *smaug_bool_not(const uint8_t *a, const smaug_mask_t *am,
                        size_t n, smaug_mask_t **out_mask) {
    if (!a) return NULL;
    smaug_mask_t *m = NULL;
    uint8_t *r = alloc_pair(n, out_mask);
    if (!r) return NULL;
    if (out_mask) m = *out_mask;

    for (size_t i = 0; i < n; i++) {
        int av = VALID(am, i);
        if (av) put(r, m, i, !a[i], 1);
        else    put(r, m, i, 0, 0);             /* NOT NA -> NA */
    }
    return r;
}

/* --- Agregações: NA ignorado --- */

size_t smaug_bool_count_true(const uint8_t *a, const smaug_mask_t *am, size_t n) {
    if (!a) return 0;
    size_t c = 0;
    for (size_t i = 0; i < n; i++)
        if (VALID(am, i) && a[i]) c++;
    return c;
}

bool smaug_bool_any(const uint8_t *a, const smaug_mask_t *am, size_t n) {
    if (!a) return false;
    for (size_t i = 0; i < n; i++)
        if (VALID(am, i) && a[i]) return true;
    return false;
}

bool smaug_bool_all(const uint8_t *a, const smaug_mask_t *am, size_t n) {
    if (!a) return true;            /* all() de vazio = true (vacuamente) */
    for (size_t i = 0; i < n; i++)
        if (VALID(am, i) && !a[i]) return false;
    return true;
}
