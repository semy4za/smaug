#ifndef SMAUG_CONVERT_H
#define SMAUG_CONVERT_H

/* ===================================================================
   smaug_convert.h — parsing rigido texto -> numero (fonte unica, Anel 0)
   -------------------------------------------------------------------
   Autoridade: strtoll base 10 / strtod. Rejeita trailing (inclusive
   espaco), string vazia e overflow; aceita leading whitespace. O i64
   rejeita hex (base 10); o f64 aceita hex/inf/nan/cientifica (heranca
   do strtod). Semantica IDENTICA ao try_i64/try_f64 do smaug_csv.c —
   que serao refatorados como thin wrappers desta fonte no item 10.9
   (adiado para acompanhar analise de perf da copia por campo).

   Recebem (ptr, len), nao C-string: a origem tipica e um slice de um
   buffer concatenado (series string sao offset-based, sem terminador
   entre elementos). Copiam para buffer local null-terminado — copia
   OBRIGATORIA por correcao: sem ela strtoll/strtod leriam alem do
   slice, ate o proximo caractere invalido no buffer vizinho.

   Retornam 1 em sucesso (*out preenchido), 0 em falha (inconversivel).
   =================================================================== */

#include <stddef.h>
#include <stdint.h>

int smaug_parse_i64(const char *s, size_t len, int64_t *out);
int smaug_parse_f64(const char *s, size_t len, double *out);

#endif /* SMAUG_CONVERT_H */
