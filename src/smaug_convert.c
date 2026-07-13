#include "../include/smaug_convert.h"
#include <stdlib.h>   /* strtoll, strtod */
#include <string.h>   /* memcpy, strlen */
#include <errno.h>
#include <math.h>     /* isinf, isnan */
#include <stdio.h>    /* snprintf */

/* ===================================================================
   smaug_convert.c — conversao texto <-> numero. Ver o header para a
   semantica, a copia obrigatoria e a normalizacao de nao-finitos.
   =================================================================== */

/* Buffer local: numeros cabem com folga (i64 <= 20 chars, f64 <= 24).
   len >= SMG_PARSE_BUF => nao-numero (mesmo limite do try_f64 do CSV). */
#define SMG_PARSE_BUF 64

/* --- PARSING (texto -> numero) --- */

/* Nucleos sem copia — recebem C-string ja terminada (hot-path do CSV, onde
   o campo vem null-terminado). Sem guard de tamanho: aceitam qualquer
   comprimento, como o try_i64/try_f64 originais. */
int smaug_parse_i64_cstr(const char *s, int64_t *out) {
    if (!s || !*s) return 0;
    char *end; errno = 0;
    long long v = strtoll(s, &end, 10);
    if (errno || *end != '\0') return 0;   /* overflow, trailing ou nao-numerico */
    *out = (int64_t)v;
    return 1;
}

int smaug_parse_f64_cstr(const char *s, double *out) {
    if (!s || !*s) return 0;
    char *end; errno = 0;
    double v = strtod(s, &end);
    if (errno || *end != '\0') return 0;   /* overflow, trailing ou nao-numerico */
    *out = v;
    return 1;
}

/* Versoes com (ptr, len): a origem e um slice de buffer concatenado (nao
   null-terminado). Copiam para buffer local e delegam ao nucleo _cstr — a
   copia e OBRIGATORIA por correcao. O guard len>=SMG_PARSE_BUF limita a copia. */
int smaug_parse_i64(const char *s, size_t len, int64_t *out) {
    if (!s || len == 0 || len >= SMG_PARSE_BUF) return 0;
    char buf[SMG_PARSE_BUF];
    memcpy(buf, s, len);
    buf[len] = '\0';
    return smaug_parse_i64_cstr(buf, out);
}

int smaug_parse_f64(const char *s, size_t len, double *out) {
    if (!s || len == 0 || len >= SMG_PARSE_BUF) return 0;
    char buf[SMG_PARSE_BUF];
    memcpy(buf, s, len);
    buf[len] = '\0';
    return smaug_parse_f64_cstr(buf, out);
}

/* --- FORMATTING (numero -> texto) --- */

size_t smaug_fmt_i64(char *buf, size_t bufsize, int64_t v) {
    int n = snprintf(buf, bufsize, "%lld", (long long)v);
    return (n > 0) ? (size_t)n : 0;
}

size_t smaug_fmt_f64(char *buf, size_t bufsize, double v) {
    /* Nao-finitos normalizados: o snprintf de %g diverge entre libc
       (glibc "nan"/"inf"; UCRT pode dar "nan(ind)"/"-nan"), o que
       tornava a serializacao dependente de plataforma. */
    const char *lit = NULL;
    if (isnan(v))       lit = "nan";
    else if (isinf(v))  lit = (v < 0) ? "-inf" : "inf";
    if (lit) {
        size_t len = strlen(lit);
        if (bufsize <= len) { if (bufsize) buf[0] = '\0'; return 0; }  /* COV-EXCL-BR: bufsize < 5 nunca ocorre (callers usam >= 32) */
        memcpy(buf, lit, len + 1);
        return len;
    }
    int n = snprintf(buf, bufsize, "%.17g", v);
    return (n > 0) ? (size_t)n : 0;
}
