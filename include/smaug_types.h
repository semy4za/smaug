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

/* Códigos de status do contrato defensivo das funções de fronteira.
   Princípio: o engine valida e COMUNICA — nunca confia que o caller validou.
   SMG_OK == 0 por convenção (testável como `if (!status)`). */
typedef enum {
    SMG_OK = 0,        /* operação concluída com sucesso          */
    SMG_NULL_VALUE,    /* leitura: elemento é NULL (não é erro)   */
    SMG_ERR_OOB,       /* índice fora dos limites                 */
    SMG_ERR_ARGUMENT   /* ponteiro nulo / argumento inconsistente */
} smaug_status_t;

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

/* Series String (offset-based, estilo Apache Arrow).
   -------------------------------------------------------------------
   Em vez de um ponteiro por string (char**, muitas alocações), todas as
   strings ficam concatenadas num único `buffer` de bytes, e `offsets` marca
   onde cada uma começa. `offsets` tem (size + 1) elementos: a string i ocupa
   os bytes [offsets[i], offsets[i+1]); seu comprimento é offsets[i+1]-offsets[i].
   O elemento extra (offsets[size]) marca o fim da última string.

     Ex.: ["SP", "RJ", "MG"]
       buffer  = "SPRJMG"            (sem terminador \0; o comprimento vem dos offsets)
       offsets = [0, 2, 4, 6]        (size+1 = 4 elementos)
       string 1 ("RJ") = bytes [offsets[1], offsets[2]) = [2, 4)

   Vantagens: poucas alocações (dois buffers, não um malloc por string),
   cache-friendly, e o comprimento é O(1). Custo: a série é efetivamente
   IMUTÁVEL em tamanho de elemento — trocar uma string por outra de tamanho
   diferente exige remontar o buffer. Isso combina com a imutabilidade por
   padrão do Smaug: a construção típica é em lote (from_table), não set a set.

   Nulos: bitmask paralelo, uniforme com os demais tipos. Um elemento nulo tem
   offsets[i] == offsets[i+1] (comprimento zero) por convenção, e null_mask[i]
   == 0x00 — o null_mask é a fonte de verdade (string vazia "" é distinta de NULL). */
typedef struct {
    char         *buffer;          /* bytes de todas as strings concatenados   */
    size_t       *offsets;         /* (size+1) marcadores de início/fim         */
    smaug_mask_t *null_mask;       /* 0xFF = válido, 0x00 = NULL                 */
    size_t        size;            /* número de strings                         */
    size_t        capacity;        /* strings que cabem em offsets/null_mask    */
    size_t        buffer_len;      /* bytes usados no buffer                     */
    size_t        buffer_capacity; /* bytes alocados no buffer                   */
    smaug_metadata_t meta;
} smaug_series_str_t;

#endif /* SMAUG_TYPES_H */
