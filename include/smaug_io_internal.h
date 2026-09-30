/* src/smaug_io_internal.h — interno ao Anel 3, não exportado */
#ifndef SMAUG_IO_INTERNAL_H
#define SMAUG_IO_INTERNAL_H

/* strdup é POSIX — necessário declarar antes de qualquer include em C11 */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "../include/smaug_types.h"
#include <stdlib.h>
#include <string.h>

/* Buffer interno com comprimento real, inclusive para nomes vazios/NUL. */
typedef struct {
    char *data;
    size_t length;
} smaug_io_text_t;

static inline char *io_copy_bytes(const char *data, size_t length) {
    if (length == SIZE_MAX) {
        return NULL;
    }
    char *copy = malloc(length + 1);
    if (copy) {
        memcpy(copy, data, length);
        copy[length] = '\0';
    }
    return copy;
}

static inline int io_bytes_equal(const char *left, size_t left_length,
                                 const char *right, size_t right_length) {
    return left_length == right_length && memcmp(left, right, left_length) == 0;
}

/* Códigos de dtype para inferência (uso interno) */
#define DT_UNKNOWN 0
#define DT_I64     1
#define DT_F64     2
#define DT_BOOL    3
#define DT_STR     4

/* Eleva dtype para o tipo mais abrangente que acomoda ambos.
   Regra: desconhecido < bool < int64 < float64 < string.
   Bool não coerce com numérico — vai direto para string. */
static inline int dtype_upgrade(int current, int candidate) {
    if (current == DT_UNKNOWN) return candidate;
    if (current == candidate)  return current;
    if (current == DT_STR || candidate == DT_STR) return DT_STR;
    if ((current == DT_I64 && candidate == DT_F64) ||
        (current == DT_F64 && candidate == DT_I64))  return DT_F64;
    /* qualquer mix envolvendo bool → string */
    return DT_STR;
}

static inline const char *dtype_name(int dt) {
    switch (dt) {
        case DT_I64:  return "int64";
        case DT_F64:  return "float64";
        case DT_BOOL: return "bool";
        default:      return "string";
    }
}

/* Erro de escrita — preenche *err_out com strdup(msg) da causa (12.30).
   Espelha o papel do t->error da leitura, mas para funções que não retornam
   smaug_table_t. Convenção:
   - err_out == NULL: caller não quer a causa (ignora silenciosamente).
   - err_out != NULL: recebe strdup da mensagem (heap da DLL → o caller Lua
     libera com smaug_free, respeitando o heap separado no Windows).
   - strdup falha (OOM ao copiar): *err_out fica NULL; o caller cai no
     fallback "erro desconhecido" — a falha continua sinalizada (retorno
     NULL/-1), só sem a string. Nunca deixa lixo em *err_out.
   NÃO é um smaug_io_last_error() global: estado global mutável violaria a
   thread-safety do Anel 0 (ver eixo de paridade 14). */
static inline void set_io_error(char **err_out, const char *msg) {
    if (err_out) *err_out = strdup(msg);
}

/* Tabela de erro — aloca smaug_table_t com ->error preenchido. */
static inline smaug_table_t *make_error(const char *msg) {
    smaug_table_t *t = calloc(1, sizeof(smaug_table_t));
    if (!t) return NULL;
    t->error = strdup(msg);
    if (!t->error) {        /* OOM ao copiar a mensagem: não deixar t->error NULL
                               (o caller leria como sucesso). Retorna NULL → o
                               consumidor trata como OOM, sinalização correta. */
        free(t);
        return NULL;
    }
    return t;
}

#include "smaug_schema.h"

/* Internal schema adapters. SIZE_MAX denotes no field/record/byte context. */
smaug_table_t *smaug_io_schema_error(const char *format, const smaug_schema_t *schema,
    size_t record, size_t field, size_t byte, const char *reason);
smaug_table_t *smaug_io_schema_table(const smaug_schema_t *schema, size_t rows);
size_t smaug_io_schema_find(const smaug_schema_t *schema, const char *name, size_t length);
smaug_status_t smaug_io_schema_set_null(smaug_column_t *column, size_t row);
const char *smaug_io_status_reason(smaug_status_t status);
/* Allocates *buffer only on success; caller frees it. No partial read success. */
smaug_status_t smaug_io_read_bytes(const char *path, char **buffer, size_t *length,
    const char **reason);

#endif /* SMAUG_IO_INTERNAL_H */
