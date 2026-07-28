/* include/smaug_str_internal.h — interno ao Anel 0, não exportado.
 *
 * Fonte ÚNICA da colação de string do Smaug.
 *
 * Antes deste arquivo (item 12.34) a mesma regra estava escrita em quatro
 * lugares do C: str_cmp_at (elemento x alvo externo), sort_cmp_idx (quicksort,
 * com desempate por indice), str_cmp_idx (argmin/argmax/rank) -- as tres no
 * mesmo smaug_ops_str.c, duas delas a 200 linhas de distancia -- e um memcmp
 * inline em smaug_ops_window.c. Diferiam so em DE ONDE vinham os ponteiros,
 * nunca na regra. Quatro copias de uma regra sao quatro lugares onde ela pode
 * divergir; e uma ja divergia (ver a nota sobre lmin == 0 abaixo).
 *
 * A regra: lexicografica por bytes, e prefixo igual desempata pela mais curta.
 * Sem locale -- deliberadamente. O `<` do LuaJIT concorda com isto porque o
 * LuaJIT compara string por memcmp; no Lua padrao seria strcoll (dependente de
 * locale) e o CategoricalSeries, que compara em Lua, divergiria do resto da
 * biblioteca em silencio. Essa invariante Lua<->C tem teste proprio.
 */
#ifndef SMAUG_STR_INTERNAL_H
#define SMAUG_STR_INTERNAL_H

#include <stddef.h>
#include <string.h>

/* Compara (pa,la) com (pb,lb). Retorna <0, 0 ou >0, como memcmp/strcmp.
 *
 * A guarda `min > 0` NAO e defensiva a toa: memcmp exige ponteiros validos
 * mesmo com n == 0, e em serie vazia `buffer + offset` pode ser NULL + 0.
 * Tres das quatro implementacoes antigas tinham a guarda; a do ops_window nao
 * tinha -- chamava memcmp(NULL, NULL, 0), que e UB pelo padrao C ainda que
 * inofensivo na pratica. Unificar aqui elimina esse caso.
 */
static inline int smaug_cmp_bytes(const char *pa, size_t la,
                                  const char *pb, size_t lb) {
    size_t min = la < lb ? la : lb;
    int c = (min > 0) ? memcmp(pa, pb, min) : 0;
    if (c != 0) return c;
    /* prefixo igual: a mais curta vem antes (lexicografico padrao) */
    if (la < lb) return -1;
    if (la > lb) return  1;
    return 0;
}

#endif /* SMAUG_STR_INTERNAL_H */
