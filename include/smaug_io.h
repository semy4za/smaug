#ifndef SMAUG_IO_H
#define SMAUG_IO_H

/* ===================================================================
   smaug_io.h — Anel 3: leitores e escritores de arquivo
   -------------------------------------------------------------------
   Toda função que lê produz uma smaug_table_t* (checar ->error antes
   de usar). Writers em arquivo retornam 0 em sucesso, -1 em erro (inclusive fechamento);
   writers em memória retornam NULL e podem preencher err_out.

   Writers exigem name não nulo e name_len real em cada coluna, inclusive
   para nomes vazios. Nomes e valores podem conter NUL dentro do comprimento.
   ABI 1: recompile biblioteca e consumidores juntos.

   Zero dependências externas — parsers escritos do zero.
   =================================================================== */

#include "smaug_types.h"
#include "smaug_schema.h"

/* --- Ciclo de vida da smaug_table_t -------------------------------- */

/* Libera todos os recursos de uma tabela (colunas, nomes, buffers).
   NULL-safe. */
void smaug_table_free(smaug_table_t *t);

/* ===================================================================
   CSV
   -------------------------------------------------------------------
   Suporte a:
   - Separador configurável (default ',')
   - Aspas duplas (RFC 4180): "campo com, virgula", ""aspas duplas""
   - Linha de cabeçalho opcional (default true)
   - Valores nulos: células vazias ou strings em na_values
   - Inferência de tipo: bool → int64 → float64 → string
   - Encoding: UTF-8 / bytes crus (sem conversão)
   - Entrada: um BOM inicial é consumido; LF/CRLF aceitos; largura uniforme
     e aspas RFC 4180 são exigidas; CR isolado é erro
   =================================================================== */

typedef struct {
    char        sep;          /* separador de campo (default ',')              */
    int         header;       /* 1 = primeira linha é cabeçalho (default 1)   */
    const char **na_values;   /* array de strings que representam NA (NULL = default) */
    const size_t *na_lengths; /* comprimentos; obrigatório se na_values e na_count > 0 */
    size_t      na_count;     /* tamanho de na_values                         */
    char        quote;        /* caractere de aspas (default '"')             */
    char        decimal;      /* separador decimal de floats (default '.')    */
} smaug_csv_opts_t;

/* Opções padrão: sep=',', header=1, quote='"', decimal='.',
   na={"","NA","null","N/A","NULL"}; nan/NaN permanecem valores float */
smaug_csv_opts_t smaug_csv_default_opts(void);

/* Lê um arquivo CSV e retorna uma smaug_table_t*.
   Em erro: retorna tabela com ->error != NULL (liberar com smaug_table_free).
   Em sucesso: ->error == NULL. */
smaug_table_t* smaug_read_csv(const char *path, const smaug_csv_opts_t *opts);

/* Lê CSV de um buffer de bytes em memória (não precisa de arquivo). */
smaug_table_t* smaug_read_csv_mem(const char *buf, size_t len,
                                   const smaug_csv_opts_t *opts);

typedef struct {
    char sep;     /* separador (default ',')                    */
    int  header;  /* 1 = escrever cabeçalho (default 1)        */
    char quote;   /* aspas para campos com sep/newline/aspas   */
    char decimal; /* separador decimal de floats (default '.') */
} smaug_csv_write_opts_t;

smaug_csv_write_opts_t smaug_csv_write_default_opts(void);

/* Writers exigem nomes não nulos com name_len real (zero é nome vazio).
   Escreve uma smaug_table_t num arquivo CSV.
   Retorna 0 em sucesso, -1 em erro. */
int smaug_write_csv(const char *path, const smaug_table_t *t,
                    const smaug_csv_write_opts_t *opts);

/* Escreve para um buffer alocado pelo callee (liberar com smaug_free).
   *out_len recebe o número de bytes escritos. NULL em erro.
   err_out (12.30): se != NULL, em erro recebe strdup da causa (ex.: sep igual a
   decimal, OOM) — liberar com smaug_free. Pode ser NULL se a causa não interessa. */
char* smaug_write_csv_mem(const smaug_table_t *t,
                           const smaug_csv_write_opts_t *opts,
                           size_t *out_len, char **err_out);

/* ===================================================================
   JSON
   -------------------------------------------------------------------
   Formato suportado: array de records (linha por objeto):
     [{"col1": val, "col2": val}, ...]

   Inferência de tipo: número inteiro → int64, número float → float64,
   true/false → bool, string → string, null → NA.
   União de campos por nome/ocorrência, na ordem da primeira aparição.
   Nomes e strings preservam NUL escapado; nome usa name_len. Um BOM inicial
   é aceito na leitura e nunca emitido; nomes/valores exigem UTF-8 válido.
   =================================================================== */

/* Lê um arquivo JSON (array de records). */
smaug_table_t* smaug_read_json(const char *path);

/* Lê JSON de um buffer em memória. */
smaug_table_t* smaug_read_json_mem(const char *buf, size_t len);

typedef struct {
    int pretty;    /* 1 = indentado com 2 espaços (default 0 = compacto) */
} smaug_json_write_opts_t;

/* Escreve uma smaug_table_t como JSON (array de records). */
int smaug_write_json(const char *path, const smaug_table_t *t,
                     const smaug_json_write_opts_t *opts);

/* err_out (12.30): se != NULL, em erro recebe strdup da causa — liberar com
   smaug_free. Pode ser NULL. */
char* smaug_write_json_mem(const smaug_table_t *t,
                            const smaug_json_write_opts_t *opts,
                            size_t *out_len, char **err_out);

/* Complete strict schema readers. schema is required and borrowed for the call.
 * CSV header/JSON keys match unique names by bytes; output follows schema order.
 * Headerless CSV matches position. Unknown/duplicate fields and failed value
 * conversions are errors; JSON missing/null and CSV NA require nullable=1.
 * Existing readers retain inference. NULL means allocation failure; other
 * failures return an error table. Always release with smaug_table_free.
 * File paths must be non-NULL NUL-terminated strings. */
smaug_table_t *smaug_read_csv_mem_schema(const char *buffer, size_t length,
    const smaug_csv_opts_t *opts, const smaug_schema_t *schema);
smaug_table_t *smaug_read_csv_schema(const char *path,
    const smaug_csv_opts_t *opts, const smaug_schema_t *schema);
smaug_table_t *smaug_read_json_mem_schema(const char *buffer, size_t length,
    const smaug_schema_t *schema);
smaug_table_t *smaug_read_json_schema(const char *path, const smaug_schema_t *schema);

#endif /* SMAUG_IO_H */
