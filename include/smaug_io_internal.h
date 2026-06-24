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

#endif /* SMAUG_IO_INTERNAL_H */
