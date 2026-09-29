#ifndef SMAUG_CONVERT_H
#define SMAUG_CONVERT_H

/* ===================================================================
   smaug_convert.h — conversao texto <-> numero (fonte unica, Anel 0)
   PARSING: gramática Smaug explícita, com decimal e hexadecimal. _cstr =
   C-string sem cópia (hot-path); (ptr,len) valida o slice integral. FORMATTING: i64 "%lld",
   f64 "%.17g"; nao-finitos normalizados NaN->"nan", +-inf->"inf"/"-inf"
   (independente de plataforma). fmt publica texto completo ou retorna zero.
   =================================================================== */

#include <stddef.h>
#include <stdint.h>
#include "smaug_types.h"

/* API de diagnóstico: retorna SMG_OK em sucesso; falhas distinguem argumento,
   sintaxe, overflow, underflow e falta de memória. A saída só é publicada em
   SMG_OK; toda falha preserva seu valor anterior. O core usa ponto decimal,
   rejeita whitespace e consome toda a entrada. i64 aceita decimal e hex inteiro;
   f64 aceita decimal, hex com expoente binário opcional e nan/inf/infinity.
   Slices não têm limite artificial de 63 bytes, não aceitam NUL interno e não
   precisam de terminador externo. Variantes _cstr exigem terminador. Sintaxe
   inválida prevalece sobre overflow de prefixo. Subnormais não zero têm sucesso;
   ERANGE com saturação em DBL_MAX é overflow. O parser não altera o modo de
   arredondamento do caller. */
smaug_status_t smaug_parse_i64_status(const char *text, size_t length, int64_t *output);
smaug_status_t smaug_parse_f64_status(const char *text, size_t length, double *output);
smaug_status_t smaug_parse_i64_cstr_status(const char *text, int64_t *output);
smaug_status_t smaug_parse_f64_cstr_status(const char *text, double *output);

/* Wrappers legados: preservam a convenção 1 = sucesso, 0 = falha. Use as
   variantes _status quando a causa da falha for necessária. */
int smaug_parse_i64(const char *text, size_t length, int64_t *output);
int smaug_parse_f64(const char *text, size_t length, double *output);
int smaug_parse_i64_cstr(const char *text, int64_t *output);
int smaug_parse_f64_cstr(const char *text, double *output);
/* Formatação: buffer obrigatório, capacity em bytes incluindo o NUL. Retorna
   comprimento escrito sem NUL; zero indica argumento/capacidade inválidos ou
   falha operacional. Não é API de consulta de tamanho: falha preserva todos
   os bytes do buffer. 32 bytes bastam para i64 e float64 (%.17g).
   Ponto decimal fixo; f64 preserva zero negativo e normaliza não finitos.
   Não altera locale global nem o modo de arredondamento; no POSIX troca o
   locale da thread apenas durante snprintf e restaura o objeto anterior.
   O caller deve manter válido seu locale durante a chamada. Roundtrip f64
   é verificado com FE_TONEAREST; outros modos seguem a libc da plataforma.
   Variantes legadas não distinguem causas; consumidores devem conferir zero. */
size_t smaug_fmt_i64(char *buffer, size_t capacity, int64_t value);
size_t smaug_fmt_f64(char *buffer, size_t capacity, double value);

#endif /* SMAUG_CONVERT_H */
