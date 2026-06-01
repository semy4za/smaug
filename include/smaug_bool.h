#ifndef SMAUG_BOOL_H
#define SMAUG_BOOL_H

/* ===================================================================
   smaug_bool.h — Operações booleanas (BoolSeries)
   -------------------------------------------------------------------
   Um "bool array" é o par (valores uint8_t*, máscara smaug_mask_t*) de mesmo
   comprimento, como o devolvido por smaug_{f64,i64}_gt/lt/eq.
   Valores: 1 = true, 0 = false.  Máscara: 0xFF = válido, 0x00 = NA.

   Lógica de três valores (Kleene), igual a SQL/pandas:
     NA AND false = false   NA AND true = NA    NA AND NA = NA
     NA OR  true  = true    NA OR  false = NA   NA OR  NA = NA
     NOT NA = NA            x XOR NA = NA

   Cada operação aloca um novo array de valores (caller libera com smaug_free)
   e, via out_mask (se não-NULL), a máscara do resultado (caller libera).
   Inclui smaug_types.h. Implementado em src/smaug_ops_bool.c.
   =================================================================== */

#include "smaug_types.h"

uint8_t* smaug_bool_and(const uint8_t *a, const smaug_mask_t *am,
                        const uint8_t *b, const smaug_mask_t *bm,
                        size_t n, smaug_mask_t **out_mask);
uint8_t* smaug_bool_or (const uint8_t *a, const smaug_mask_t *am,
                        const uint8_t *b, const smaug_mask_t *bm,
                        size_t n, smaug_mask_t **out_mask);
uint8_t* smaug_bool_xor(const uint8_t *a, const smaug_mask_t *am,
                        const uint8_t *b, const smaug_mask_t *bm,
                        size_t n, smaug_mask_t **out_mask);
uint8_t* smaug_bool_not(const uint8_t *a, const smaug_mask_t *am,
                        size_t n, smaug_mask_t **out_mask);

/* Agregações: NA é ignorado (semântica pandas). */
size_t smaug_bool_count_true(const uint8_t *a, const smaug_mask_t *am, size_t n);
bool   smaug_bool_any(const uint8_t *a, const smaug_mask_t *am, size_t n);
bool   smaug_bool_all(const uint8_t *a, const smaug_mask_t *am, size_t n);

#endif /* SMAUG_BOOL_H */
