#ifndef SMAUG_TYPES_H
#define SMAUG_TYPES_H

/* ===================================================================
   smaug_types.h — Tipos base do Smaug (a fundação)
   -------------------------------------------------------------------
   Contém APENAS tipos: máscara de nulos, metadados e as structs de série.
   Zero funções. Todo header de operação (core, numeric, bool, e o futuro
   string) inclui este. Inspirado no ndarraytypes.h do NumPy, que isola os
   tipos/structs das funções para que novos tipos possam ser adicionados sem
   arrastar o lifecycle/operações de outros tipos.
   =================================================================== */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

/* Tipo opaque para hash table (uso futuro: GroupBy/joins) */
typedef struct smaug_hash_table smaug_hash_table_t;

/* Máscara de nulos: array paralelo (1 byte por valor).
   Convenção: 0xFF = válido, 0x00 = NA/NULL */
typedef uint8_t smaug_mask_t;

/* Metadados comuns a toda série (qualquer dtype). */
typedef struct {
    const char *name;        /* Nome da coluna               */
    const char *dtype;       /* "float64", "int64", "bool"…  */
    bool is_view;            /* True se é uma view           */
    bool external_alloc;     /* True se data/null_mask são de terceiros */
} smaug_metadata_t;

/* Series Float64 */
typedef struct {
    double       *data;
    smaug_mask_t *null_mask;
    size_t        size;
    size_t        capacity;
    smaug_metadata_t meta;
} smaug_series_f64_t;

/* Series Int64 */
typedef struct {
    int64_t      *data;
    smaug_mask_t *null_mask;
    size_t        size;
    size_t        capacity;
    smaug_metadata_t meta;
} smaug_series_i64_t;

#endif /* SMAUG_TYPES_H */
