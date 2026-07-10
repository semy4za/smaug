#include "../include/smaug_astype.h"

/* Construtores e utilitarios dos dtypes de destino/origem. As primitivas
   da matriz (Fases 1-3) constroem series de outro dtype, entao precisam
   dos headers de todos os tipos envolvidos, alem de dt_format/dt_parse. */
#include "../include/smaug_numeric.h"   /* smaug_i64_*, smaug_f64_* */
#include "../include/smaug_string.h"    /* smaug_str_* (offset-based) */
#include "../include/smaug_datetime.h"  /* smaug_dt_*, dt_format/dt_parse */

/* ===================================================================
   smaug_astype.c — matriz de conversao de tipo src×dst (Anel 0).
   Ver smaug_astype.h para a matriz e o contrato.

   Fase 0 (infra): arquivo integrado ao build, sem primitivas ainda.
   As 12 conversoes entram nas Fases 1 (arrays diretos), 2 (-> string,
   two-pass builder) e 3 (string ->, parse com two-tier em str->i64).
   =================================================================== */
