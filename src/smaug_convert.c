#include "../include/smaug_convert.h"
#include <stdlib.h>   /* strtoll, strtod */
#include <string.h>   /* memcpy */
#include <errno.h>

/* ===================================================================
   smaug_convert.c — implementacao dos parsers rigidos. Ver o header
   para a semantica e a decisao de copia obrigatoria.
   =================================================================== */

/* Buffer local: numeros cabem com folga (i64 <= 20 chars, f64 <= 24).
   len >= SMG_PARSE_BUF => nao-numero (mesmo limite do try_f64 do CSV). */
#define SMG_PARSE_BUF 64

int smaug_parse_i64(const char *s, size_t len, int64_t *out) {
    if (!s || len == 0 || len >= SMG_PARSE_BUF) return 0;

    char buf[SMG_PARSE_BUF];
    memcpy(buf, s, len);
    buf[len] = '\0';

    char *end; errno = 0;
    long long v = strtoll(buf, &end, 10);
    if (errno || *end != '\0') return 0;   /* overflow, trailing ou nao-numerico */

    *out = (int64_t)v;
    return 1;
}

int smaug_parse_f64(const char *s, size_t len, double *out) {
    if (!s || len == 0 || len >= SMG_PARSE_BUF) return 0;

    char buf[SMG_PARSE_BUF];
    memcpy(buf, s, len);
    buf[len] = '\0';

    char *end; errno = 0;
    double v = strtod(buf, &end);
    if (errno || *end != '\0') return 0;   /* overflow, trailing ou nao-numerico */

    *out = v;
    return 1;
}
