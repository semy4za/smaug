#ifndef SMAUG_H
#define SMAUG_H

/* ===================================================================
   smaug.h — Header guarda-chuva (umbrella)
   -------------------------------------------------------------------
   Inclui tudo de uma vez. Use este quando quiser a API completa; ou inclua
   apenas o header específico (smaug_core.h, smaug_numeric.h, smaug_bool.h)
   se quiser limitar a superfície.

   Substitui o antigo smaug_math.h (removido — o nome "math" não refletia mais
   o conteúdo, que inclui lifecycle, null handling, comparações e bool).

   Mapa de headers (qual incluir para cada coisa):
     smaug_types.h    — tipos base (mask, metadata, structs). Zero funções.
     smaug_core.h     — lifecycle, get/set, append, smaug_free. (inclui types)
     smaug_numeric.h  — aritmética/reduções/comparações/sort/utils f64+i64. (inclui core)
     smaug_bool.h     — lógica booleana Kleene. (inclui types)
     smaug_string.h   — tipo string (offset-based), lifecycle e acesso. (inclui types)
     smaug.h          — este; inclui os de operação.
   =================================================================== */

#include "smaug_types.h"
#include "smaug_core.h"
#include "smaug_numeric.h"
#include "smaug_bool.h"
#include "smaug_string.h"

#endif /* SMAUG_H */
