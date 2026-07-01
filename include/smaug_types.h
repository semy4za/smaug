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
    SMG_ERR_ARGUMENT,  /* ponteiro nulo / argumento inconsistente */
    SMG_ERR_NOMEM      /* falha de alocação no COW detach         */
} smaug_status_t;

/* Tipo opaque para hash table (uso futuro: GroupBy/joins) */
typedef struct smaug_hash_table smaug_hash_table_t;

/* Máscara de nulos: array paralelo (1 byte por valor). */
typedef uint8_t smaug_mask_t;

/* Valores do byte de máscara — o ÚNICO lugar onde os bytes crus aparecem.
   Toda escrita de máscara usa estes símbolos; nenhum literal 0xFF/0x00
   de máscara deve existir em outro arquivo. */
#define SMAUG_MASK_VALID 0xFF
#define SMAUG_MASK_NULL  0x00

/* ===================================================================
   Convenção de nulidade — fonte única dos TESTES de máscara
   -------------------------------------------------------------------
   Byte de máscara: SMAUG_MASK_VALID = válido, SMAUG_MASK_NULL = NA.

   Existem DOIS contratos distintos, por design, não por descuido.
   NÃO os unifique num macro permissivo: esconder uma máscara ausente
   em código de Series mascararia bug de programação
   (falha visível > acerto adivinhado).

     SMAUG_VALID / SMAUG_NULL
         Exigem máscara válida (presente). Passar NULL é erro de
         programação e deve falhar, nunca ser silenciado.

     SMAUG_OPTIONAL_VALID
         Só para APIs cujo contrato aceita explicitamente máscara NULL
         significando "todos os valores são válidos" (funções livres
         do bool: smaug_bool_*).

   SMAUG_NULL é, por construção, a negação de SMAUG_VALID — não podem
   divergir.
   =================================================================== */
#define SMAUG_VALID(mask, i)          ((mask)[(i)] == SMAUG_MASK_VALID)
#define SMAUG_NULL(mask, i)           (!SMAUG_VALID((mask), (i)))
#define SMAUG_OPTIONAL_VALID(mask, i) ((mask) == NULL || SMAUG_VALID((mask), (i)))

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

/* Series Bool — armazenamento de coluna booleana (Anel 0).
   Um byte por elemento (0 = false, 1 = true). Nulos via bitmask paralelo,
   uniforme com os demais tipos. O dtype booleano de primeira classe vive aqui,
   no mesmo padrão de f64/i64 — não como classe paralela no frontend. */
typedef struct {
    uint8_t      *data;        /* 0 = false, 1 = true     */
    smaug_mask_t *null_mask;   /* paralelo a data         */
    size_t        size;        /* elementos preenchidos   */
    size_t        capacity;    /* elementos alocados      */
    smaug_metadata_t meta;
} smaug_series_bool_t;

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
    /* Posse do array `offsets`, independente de meta.external_alloc.
       Necessário porque a view de string (offset-based) é um estado MISTO de
       posse: ela compartilha `buffer` e `null_mask` com o pai (external_alloc
       = true → free não os toca), mas possui um `offsets` PRÓPRIO rebaseado
       (offsets_owned = true → free o libera). Um único external_alloc não
       consegue representar isso. Séries normais têm offsets_owned = true e
       external_alloc = false (donas de tudo); a view tem offsets_owned = true
       e external_alloc = true (dona só do offsets). Ver smaug_str_view/free. */
    bool          offsets_owned;
    smaug_metadata_t meta;
} smaug_series_str_t;

/* Series DateTime — epoch em milissegundos UTC (int64 internamente).
   Layout idêntico a smaug_series_i64_t; semântica distinta (calendário).
   Valores negativos representam datas antes de 1970-01-01.
   Fuso horário: sempre UTC no armazenamento; apresentação local é responsabilidade
   do frontend. Null por bitmask, uniforme com os demais dtypes. */
typedef struct {
    int64_t      *data;        /* epoch ms                    */
    smaug_mask_t *null_mask;   /* 0xFF = válido, 0x00 = NULL  */
    size_t        size;
    size_t        capacity;
    smaug_metadata_t meta;
} smaug_series_dt_t;

/* ===================================================================
   smaug_table_t — Struct intermediária do Anel 3 (I/O)
   -------------------------------------------------------------------
   Contrato de fronteira entre leitores (CSV, JSON, …) e o frontend Lua.
   Todo leitor produz uma smaug_table_t; o frontend Lua a consome e
   monta um DataSet. Colocada aqui no final porque referencia as quatro
   structs de série acima.
   =================================================================== */

typedef struct {
    const char          *name;     /* nome da coluna (cópia alocada pelo leitor) */
    const char          *dtype;    /* "float64" | "int64" | "bool" | "string"    */
    smaug_series_f64_t  *f64;      /* não-NULL se dtype == "float64"             */
    smaug_series_i64_t  *i64;      /* não-NULL se dtype == "int64"               */
    smaug_series_bool_t *boolcol;  /* não-NULL se dtype == "bool"                */
    smaug_series_str_t  *str;      /* não-NULL se dtype == "string"              */
} smaug_column_t;

typedef struct {
    smaug_column_t *columns;   /* array de colunas                               */
    size_t          ncols;     /* número de colunas                              */
    size_t          nrows;     /* número de linhas (todas as colunas têm nrows)  */
    char           *error;     /* NULL se ok; mensagem de erro se falhou         */
} smaug_table_t;

#endif /* SMAUG_TYPES_H */
