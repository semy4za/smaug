#ifndef SMAUG_IO_H
#define SMAUG_IO_H

/* ===================================================================
   smaug_io.h — Anel 3: leitores e escritores de arquivo
   -------------------------------------------------------------------
   Toda função que lê produz uma smaug_table_t* (checar ->error antes
   de usar). Toda função que escreve retorna 0 em sucesso, -1 em erro
   (checar smaug_io_last_error()).

   Zero dependências externas — parsers escritos do zero.
   =================================================================== */

#include "smaug_types.h"

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
   - Inferência de tipo: int64 → float64 → bool → string
   - Encoding: UTF-8 / bytes crus (sem conversão)
   =================================================================== */

typedef struct {
    char        sep;          /* separador de campo (default ',')              */
    int         header;       /* 1 = primeira linha é cabeçalho (default 1)   */
    const char **na_values;   /* array de strings que representam NA (NULL = default) */
    size_t      na_count;     /* tamanho de na_values                         */
    char        quote;        /* caractere de aspas (default '"')             */
    char        decimal;      /* separador decimal de floats (default '.')    */
} smaug_csv_opts_t;

/* Opções padrão: sep=',', header=1, quote='"', decimal='.',
   na={"","NA","null","N/A"} */
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

/* Escreve uma smaug_table_t num arquivo CSV.
   Retorna 0 em sucesso, -1 em erro. */
int smaug_write_csv(const char *path, const smaug_table_t *t,
                    const smaug_csv_write_opts_t *opts);

/* Escreve para um buffer alocado pelo callee (liberar com smaug_free).
   *out_len recebe o número de bytes escritos. NULL em erro. */
char* smaug_write_csv_mem(const smaug_table_t *t,
                           const smaug_csv_write_opts_t *opts,
                           size_t *out_len);

/* ===================================================================
   JSON
   -------------------------------------------------------------------
   Formato suportado: array de records (linha por objeto):
     [{"col1": val, "col2": val}, ...]

   Inferência de tipo: número inteiro → int64, número float → float64,
   true/false → bool, string → string, null → NA.
   Todas as colunas inferidas a partir do primeiro objeto não-nulo.
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

char* smaug_write_json_mem(const smaug_table_t *t,
                            const smaug_json_write_opts_t *opts,
                            size_t *out_len);

#endif /* SMAUG_IO_H */
