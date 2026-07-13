#ifndef SMAUG_CONVERT_H
#define SMAUG_CONVERT_H

/* ===================================================================
   smaug_convert.h — conversao texto <-> numero (fonte unica, Anel 0)
   PARSING: strtoll base 10 / strtod (rigido). _cstr = C-string sem copia
   (hot-path); (ptr,len) copia e delega ao _cstr. FORMATTING: i64 "%lld",
   f64 "%.17g"; nao-finitos normalizados NaN->"nan", +-inf->"inf"/"-inf"
   (independente de plataforma). fmt escreve em (buf,bufsize>=32), retorna len.
   =================================================================== */

#include <stddef.h>
#include <stdint.h>

int smaug_parse_i64(const char *s, size_t len, int64_t *out);
int smaug_parse_f64(const char *s, size_t len, double *out);
int smaug_parse_i64_cstr(const char *s, int64_t *out);
int smaug_parse_f64_cstr(const char *s, double *out);
size_t smaug_fmt_i64(char *buf, size_t bufsize, int64_t v);
size_t smaug_fmt_f64(char *buf, size_t bufsize, double v);

#endif /* SMAUG_CONVERT_H */
