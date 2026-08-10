#include "../include/smaug_numeric.h"
#include <math.h>      /* NAN, isnan(), sqrt() */
#include <stdlib.h>    /* malloc, free, qsort */
#include <stddef.h>

/* ===================================================================
   Macros de null-check para manter os loops legíveis
   =================================================================== */

/* ===================================================================
   Helpers de alocação de resultado
   =================================================================== */

/* Aloca uma nova série f64 com todos os elementos marcados como NULL.
   Operações preenchem apenas as posições válidas.
   smaug_f64_create vem de smaug_core.h (incluído via smaug_numeric.h). */
static smaug_series_f64_t *alloc_result(size_t size) {
    return smaug_f64_create(size);
}

/* ===================================================================
   ARITMÉTICAS — série × série
   Propagação de NULL: se qualquer operando é NULL, resultado é NULL.
   =================================================================== */

smaug_series_f64_t *smaug_f64_add(const smaug_series_f64_t *a,
                                   const smaug_series_f64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i) && SMAUG_VALID(b->null_mask, i)) {
            r->data[i]      = a->data[i] + b->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_sub(const smaug_series_f64_t *a,
                                   const smaug_series_f64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i) && SMAUG_VALID(b->null_mask, i)) {
            r->data[i]      = a->data[i] - b->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_mul(const smaug_series_f64_t *a,
                                   const smaug_series_f64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i) && SMAUG_VALID(b->null_mask, i)) {
            r->data[i]      = a->data[i] * b->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_div(const smaug_series_f64_t *a,
                                   const smaug_series_f64_t *b) {
    if (!a || !b || a->size != b->size) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i) && SMAUG_VALID(b->null_mask, i) && b->data[i] != 0.0) {
            r->data[i]      = a->data[i] / b->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
        /* div/0 → NULL (previsível; evita ±Inf/NaN silenciosos) */
    }
    return r;
}

/* ===================================================================
   ARITMÉTICAS — série × escalar
   NULL se elemento é NULL; escalar não propaga NULL.
   =================================================================== */

smaug_series_f64_t *smaug_f64_add_scalar(const smaug_series_f64_t *a, double scalar) {
    if (!a) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i)) {
            r->data[i]      = a->data[i] + scalar;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_sub_scalar(const smaug_series_f64_t *a, double scalar) {
    if (!a) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i)) {
            r->data[i]      = a->data[i] - scalar;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_mul_scalar(const smaug_series_f64_t *a, double scalar) {
    if (!a) return NULL;

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i)) {
            r->data[i]      = a->data[i] * scalar;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

smaug_series_f64_t *smaug_f64_div_scalar(const smaug_series_f64_t *a, double scalar) {
    if (!a) return NULL;
    if (scalar == 0.0) return alloc_result(a->size);  /* tudo NULL — igual ao i64 */

    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;

    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i)) {
            r->data[i]      = a->data[i] / scalar;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* ===================================================================
   MATEMÁTICAS ELEMENT-WISE — unárias, f64 -> f64
   ===================================================================
   As seis (sin/cos/tan/exp/log/sqrt) diferem APENAS pela função de libm que
   aplicam: mesma alocação, mesmo laço, mesma propagação de nulo. Escritas à
   mão seriam seis corpos idênticos -- seis lugares onde uma correção precisa
   ser repetida, e cinco onde ela pode ser esquecida. A macro é o padrão que a
   casa já usa para famílias assim (DT_CMP_IMPL, em smaug_datetime.c).

   Nulo propaga: alloc_result devolve tudo marcado como nulo, e o laço só
   marca VÁLIDO onde havia valor.

   Domínio: sqrt(-4) e log(-4) devolvem NaN, não erro nem nulo -- é o que a
   libm faz, e é coerente com o Contrato 9 (não-finito é VALOR presente;
   ausência é null_mask). Quem quiser tratar chama isna()/isnan() depois.

   Entrada int64 não tem versão própria de propósito (10.3, Opção 1): a saída
   é f64 de todo jeito, então o Anel 1 encadeia astype("float64") -- já
   vetorizado -- e chama estas. Converter antes não perde nada que a operação
   não fosse perder, e evita seis funções gêmeas só para trocar o tipo de
   entrada. */
#define F64_MATH_IMPL(name, fn)                                              \
smaug_series_f64_t *smaug_f64_##name(const smaug_series_f64_t *a) {           \
    if (!a) return NULL;                                                      \
    smaug_series_f64_t *r = alloc_result(a->size);                            \
    if (!r) return NULL;                                                      \
    for (size_t i = 0; i < a->size; i++) {                                    \
        if (SMAUG_VALID(a->null_mask, i)) {                                   \
            r->data[i]      = fn(a->data[i]);                                 \
            r->null_mask[i] = SMAUG_MASK_VALID;                               \
        }                                                                     \
    }                                                                         \
    return r;                                                                 \
}

F64_MATH_IMPL(sin,  sin)
F64_MATH_IMPL(cos,  cos)
F64_MATH_IMPL(tan,  tan)
F64_MATH_IMPL(exp,  exp)
F64_MATH_IMPL(log,  log)
F64_MATH_IMPL(sqrt, sqrt)
/* abs entra aqui e não como corpo próprio: tem exatamente a mesma forma das
   seis acima -- unária, f64 -> f64, só troca a função de libm por fabs. A
   diferença em relação às outras é semântica (preserva dtype, então existe
   versão int64), não estrutural. */
F64_MATH_IMPL(abs, fabs)

/* round: half-away-from-zero, a MESMA regra que o frontend aplicava em Lua
   (floor(v*f + 0.5) para v >= 0; ceil(v*f - 0.5) para v < 0). ndigits negativo
   arredonda casas ANTES da vírgula: round(1234.0, -2) = 1200.
   Sem status: em f64 não há caso sem resposta -- ndigits extremo faz o fator
   virar infinito e o resultado NaN, que é VALOR presente pelo Contrato 9, o
   mesmo que a versão Lua já produzia. */
smaug_series_f64_t *smaug_f64_round(const smaug_series_f64_t *a, int ndigits) {
    if (!a) return NULL;
    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;
    double factor = pow(10.0, (double)ndigits);
    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i)) {
            double v = a->data[i];
            r->data[i] = (v >= 0.0) ? floor(v * factor + 0.5) / factor
                                    : ceil (v * factor - 0.5) / factor;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* clip: limita ao intervalo [lo, hi]. has_lo/has_hi expressam limite ausente
   (o frontend aceita nil em qualquer um dos dois) -- mesmo padrão de
   inc_lo/inc_hi do between, em vez de sentinela mágica.

   lo > hi é ERRO (10.3), não resultado. Antes disto o frontend devolvia algo
   incoerente: o `return lo` curto-circuitava antes de checar `hi`, então
   {1,5,9}:clip(8,2) dava {8,8,2} -- um resultado que não está dentro de faixa
   nenhuma. Faixa contraditória não tem semântica válida; adivinhar qual limite
   "vence" seria escolher pelo usuário. */
smaug_series_f64_t *smaug_f64_clip(const smaug_series_f64_t *a,
                                   double lo, bool has_lo,
                                   double hi, bool has_hi,
                                   smaug_status_t *status) {
    if (status) *status = SMG_OK;
    if (!a) { if (status) *status = SMG_ERR_ARGUMENT; return NULL; }
    if (has_lo && has_hi && lo > hi) {
        if (status) *status = SMG_ERR_ARGUMENT;
        return NULL;
    }
    smaug_series_f64_t *r = alloc_result(a->size);
    if (!r) return NULL;
    for (size_t i = 0; i < a->size; i++) {
        if (SMAUG_VALID(a->null_mask, i)) {
            double v = a->data[i];
            if (has_lo && v < lo) v = lo;
            if (has_hi && v > hi) v = hi;
            r->data[i]      = v;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* coalesce_scalar (natureza null-mask): onde self[i] é nulo, entra `value`;
   senão, mantém self[i]. Serve fillna. Opera sobre a MÁSCARA, não sobre o
   valor: NaN existente (máscara válida) é preservado como está — coerente com
   a política do Smaug de NaN ser valor presente, distinto de null. Reusa
   smaug_f64_clone (cópia via memcpy); o loop só preenche os buracos. */
smaug_series_f64_t *smaug_f64_coalesce_scalar(const smaug_series_f64_t *self,
                                              double value) {
    if (!self) return NULL;  /* COV-EXCL-BR: redundante — o clone(NULL) logo abaixo devolve NULL e o `if (!r)` barra; auditado 2026-07-14 (remover este guard NAO crasha). Defesa em profundidade, nao a unica protecao. */

    smaug_series_f64_t *r = smaug_f64_clone(self);
    if (!r) return NULL;  /* COV-EXCL-BR: falha de alloc do clone; OOM sem injecao */

    for (size_t i = 0; i < self->size; i++) {
        if (SMAUG_NULL(r->null_mask, i)) {
            r->data[i]      = value;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* coalesce (natureza null-mask, série+série): onde self[i] é nulo entra
   other[i] (se other[i] válido); senão mantém self[i]. Ambos nulos → nulo.
   Serve combine_first. Opera sobre a MÁSCARA: NaN válido (de self ou de other)
   é valor presente, preservado como está. Reusa smaug_f64_clone; o loop só
   preenche os buracos de self a partir de other. */
smaug_series_f64_t *smaug_f64_coalesce(const smaug_series_f64_t *self,
                                       const smaug_series_f64_t *other) {
    if (!self || !other || self->size != other->size) return NULL;  /* guard essencial: sem ele, other->null_mask crasha. Coberto por coalesce_guards_publicos (12.23) */

    smaug_series_f64_t *r = smaug_f64_clone(self);
    if (!r) return NULL;  /* COV-EXCL-BR: falha de alloc do clone; OOM sem injecao */

    for (size_t i = 0; i < self->size; i++) {
        if (SMAUG_NULL(r->null_mask, i) && SMAUG_VALID(other->null_mask, i)) {
            r->data[i]      = other->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* select (cond-bool, ternário posicional): cond[i] true → a[i], senão (false OU
   NA — decisão 1a) → b[i], preservando a nulidade do operando escolhido. NaN
   válido é valor presente. Unifica where/mask/ifelse. */
smaug_series_f64_t *smaug_f64_select(const smaug_series_bool_t *cond,
                                     const smaug_series_f64_t *a,
                                     const smaug_series_f64_t *b) {
    if (!cond || !a || !b || cond->size != a->size || a->size != b->size)  /* guard essencial: o corpo toca create(a->size), cond->null_mask e `b` direto. Coberto por select_guards_publicos (12.24) */
        return NULL;

    smaug_series_f64_t *r = smaug_f64_create(a->size);
    if (!r) return NULL;  /* COV-EXCL-BR: OOM sem injecao */

    for (size_t i = 0; i < a->size; i++) {
        bool take_a = SMAUG_VALID(cond->null_mask, i) && cond->data[i];
        const smaug_series_f64_t *src = take_a ? a : b;
        if (SMAUG_VALID(src->null_mask, i)) {
            r->data[i]      = src->data[i];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* ===================================================================
   REDUÇÕES
   ignore_na=false: retorna NAN ao encontrar o primeiro NULL.
   ignore_na=true:  pula NULLs.
   =================================================================== */

double smaug_f64_sum(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s) return NAN;

    double sum = 0.0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            sum += s->data[i];
        } else if (!ignore_na) {
            return NAN;
        }
    }
    return sum;
}

double smaug_f64_mean(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double sum   = 0.0;
    size_t count = 0;

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            sum += s->data[i];
            count++;
        } else if (!ignore_na) {
            return NAN;
        }
    }

    return count ? sum / (double)count : NAN;
}

double smaug_f64_min(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double result = NAN;

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            if (isnan(result) || s->data[i] < result)
                result = s->data[i];
        } else if (!ignore_na) {
            return NAN;
        }
    }
    return result;  /* NAN se nenhum elemento válido */
}

double smaug_f64_max(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double result = NAN;

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            if (isnan(result) || s->data[i] > result)
                result = s->data[i];
        } else if (!ignore_na) {
            return NAN;
        }
    }
    return result;
}

/* Variância amostral (ddof=1): Σ(xi - mean)² / (n-1); NaN para n<2.
   Dois passos, numericamente estável. Alinha com cov/skew/groupby e pandas. */
double smaug_f64_var(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s || s->size == 0) return NAN;

    double mean = smaug_f64_mean(s, ignore_na);
    if (isnan(mean)) return NAN;

    double sum_sq = 0.0;
    size_t count  = 0;

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            double d = s->data[i] - mean;
            sum_sq += d * d;
            count++;
        }
    }

    return count >= 2 ? sum_sq / (double)(count - 1) : NAN;  /* amostral: n<2 indefinido */
}

double smaug_f64_std(const smaug_series_f64_t *s, bool ignore_na) {
    return sqrt(smaug_f64_var(s, ignore_na));
}

double smaug_f64_prod(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s) return NAN;
    double prod = 1.0;
    bool found_valid = false;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            prod *= s->data[i];
            found_valid = true;
        } else if (!ignore_na) {
            return NAN;
        }
    }
    return found_valid ? prod : NAN;
}

/* ===================================================================
   COMPARAÇÕES → uint8_t* (bool array)
   out_mask: ponteiro de saída para a null_mask do resultado (pode ser NULL).
   Caller é responsável por free() do array retornado e do *out_mask.
   NULL de entrada → resultado NULL naquela posição.
   =================================================================== */


uint8_t *smaug_f64_gt(const smaug_series_f64_t *s, double threshold,
                       smaug_mask_t **out_mask) {
    if (!s) return NULL;

    uint8_t      *result = malloc(s->size * sizeof(uint8_t));
    smaug_mask_t *mask   = NULL;
    if (!result) return NULL;

    if (out_mask) {
        mask = malloc(s->size * sizeof(smaug_mask_t));
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] > threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

uint8_t *smaug_f64_lt(const smaug_series_f64_t *s, double threshold,
                       smaug_mask_t **out_mask) {
    if (!s) return NULL;

    uint8_t      *result = malloc(s->size * sizeof(uint8_t));
    smaug_mask_t *mask   = NULL;
    if (!result) return NULL;

    if (out_mask) {
        mask = malloc(s->size * sizeof(smaug_mask_t));
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] < threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

uint8_t *smaug_f64_eq(const smaug_series_f64_t *s, double threshold,
                       smaug_mask_t **out_mask) {
    if (!s) return NULL;

    uint8_t      *result = malloc(s->size * sizeof(uint8_t));
    smaug_mask_t *mask   = NULL;
    if (!result) return NULL;

    if (out_mask) {
        mask = malloc(s->size * sizeof(smaug_mask_t));
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }

    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] == threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

uint8_t *smaug_f64_ge(const smaug_series_f64_t *s, double threshold,
                       smaug_mask_t **out_mask) {
    if (!s) return NULL;
    uint8_t      *result = malloc(s->size * sizeof(uint8_t));
    smaug_mask_t *mask   = NULL;
    if (!result) return NULL;
    if (out_mask) {
        mask = malloc(s->size * sizeof(smaug_mask_t));
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] >= threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

uint8_t *smaug_f64_le(const smaug_series_f64_t *s, double threshold,
                       smaug_mask_t **out_mask) {
    if (!s) return NULL;
    uint8_t      *result = malloc(s->size * sizeof(uint8_t));
    smaug_mask_t *mask   = NULL;
    if (!result) return NULL;
    if (out_mask) {
        mask = malloc(s->size * sizeof(smaug_mask_t));
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] <= threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

uint8_t *smaug_f64_ne(const smaug_series_f64_t *s, double threshold,
                       smaug_mask_t **out_mask) {
    if (!s) return NULL;
    uint8_t      *result = malloc(s->size * sizeof(uint8_t));
    smaug_mask_t *mask   = NULL;
    if (!result) return NULL;
    if (out_mask) {
        mask = malloc(s->size * sizeof(smaug_mask_t));
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = s->data[i] != threshold ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

/* between: lo <= v <= hi (inclusividade independente por lado) em UMA passada.
   Não compõe ge+le internamente de propósito: compor exigiria três alocações de
   par (result+mask) e três varreduras, para o que uma varredura e um par fazem.
   inc_lo/inc_hi escolhem >= vs > e <= vs < — cobre os quatro modos do
   `inclusive` do frontend (both/left/right/neither).
   NaN: qualquer comparação com NaN é falsa, então NaN → 0 com máscara VÁLIDA
   (não é null). Coerente com os comparadores e com o CODE_REVIEW A3. */
uint8_t *smaug_f64_between(const smaug_series_f64_t *s, double lo, double hi,
                           bool inc_lo, bool inc_hi, smaug_mask_t **out_mask) {
    if (!s) return NULL;
    uint8_t      *result = malloc(s->size * sizeof(uint8_t));
    smaug_mask_t *mask   = NULL;
    if (!result) return NULL;
    if (out_mask) {
        mask = malloc(s->size * sizeof(smaug_mask_t));
        if (!mask) { free(result); return NULL; }
        *out_mask = mask;
    }
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            double v  = s->data[i];
            bool   ok = (inc_lo ? (v >= lo) : (v > lo))
                     && (inc_hi ? (v <= hi) : (v < hi));
            result[i] = ok ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

/* ===================================================================
   ORDENAÇÃO
   argsort/sort retornam NULL se a série contém NULLs (posição de NA
   é indefinida). Use dropna() antes, ou filtre com count_nonnull().
   =================================================================== */

typedef struct { size_t idx; double val; } f64_entry_t;

static int cmp_f64_asc(const void *a, const void *b) {
    const f64_entry_t *ea = (const f64_entry_t *)a;
    const f64_entry_t *eb = (const f64_entry_t *)b;
    if (ea->val < eb->val) return -1;
    if (ea->val > eb->val) return  1;
    return 0;
}

static int cmp_f64_desc(const void *a, const void *b) {
    return cmp_f64_asc(b, a);
}

size_t *smaug_f64_argsort(const smaug_series_f64_t *s, bool ascending) {
    if (!s) return NULL;

    /* Falha se houver qualquer NULL ou NaN. NaN é um valor presente, mas sem
       ordem bem-definida (toda comparação com NaN é false), então ordenar uma
       série com NaN produziria resultado indefinido. Contrato: sort/argsort
       recusam NaN além de null (ver Roadmap, "Contrato de valores especiais"). */
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_NULL(s->null_mask, i) || isnan(s->data[i])) return NULL;
    }

    f64_entry_t *entries = malloc(s->size * sizeof(f64_entry_t));
    if (!entries) return NULL;

    for (size_t i = 0; i < s->size; i++) {
        entries[i].idx = i;
        entries[i].val = s->data[i];
    }

    qsort(entries, s->size, sizeof(f64_entry_t),
          ascending ? cmp_f64_asc : cmp_f64_desc);

    size_t *indices = malloc(s->size * sizeof(size_t));
    if (!indices) { free(entries); return NULL; }

    for (size_t i = 0; i < s->size; i++) indices[i] = entries[i].idx;

    free(entries);
    return indices;
}

smaug_series_f64_t *smaug_f64_sort(const smaug_series_f64_t *s, bool ascending) {
    if (!s) return NULL;

    size_t *indices = smaug_f64_argsort(s, ascending);
    if (!indices) return NULL;  /* série com NULL/NaN, ou falha de alocação */

    smaug_series_f64_t *result = smaug_f64_take(s, indices, s->size);
    free(indices);
    return result;
}

/* ===================================================================
   UTILITÁRIOS
   =================================================================== */

size_t smaug_f64_count_nonnull(const smaug_series_f64_t *s) {
    if (!s) return 0;
    size_t count = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) count++;
    }
    return count;
}

size_t smaug_f64_count_nonfinite(const smaug_series_f64_t *s) {
    if (!s) return 0;
    size_t count = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i) && !isfinite(s->data[i])) count++;
    }
    return count;
}

/* take: copia elementos nas posições idx[0..len-1] (0-based).
   Retorna NULL se qualquer índice está fora dos limites. */
smaug_series_f64_t *smaug_f64_take(const smaug_series_f64_t *s,
                                    const size_t *idx, size_t len) {
    if (!s || !idx) return NULL;

    smaug_series_f64_t *r = smaug_f64_create(len);
    if (!r) return NULL;

    for (size_t i = 0; i < len; i++) {
        if (idx[i] >= s->size) {
            smaug_f64_free(r);
            return NULL;
        }
        r->data[i]      = s->data[idx[i]];
        r->null_mask[i] = s->null_mask[idx[i]];
    }
    return r;
}

/* ===================================================================
   Grupo A — Operações de janela e redução posicional (Fase 3 Ring 0)
   Todas retornam nova série do mesmo tamanho que a entrada.
   NULL propaga: posição nula na entrada → posição nula na saída.
   =================================================================== */

/* cumsum: soma cumulativa. Null na posição i → null em [i, n-1].
   Série vazia ou toda-null → série toda-null. */
smaug_series_f64_t *smaug_f64_cumsum(const smaug_series_f64_t *s) {
    if (!s) return NULL;
    smaug_series_f64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    double acc = 0.0;
    int null_seen = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (null_seen || SMAUG_NULL(s->null_mask, i)) {
            null_seen = 1;
            /* null_mask já inicializado como SMAUG_MASK_NULL por alloc_result */
        } else {
            acc += s->data[i];
            r->data[i]      = acc;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* cumprod: produto cumulativo. Null propaga igual ao cumsum. */
smaug_series_f64_t *smaug_f64_cumprod(const smaug_series_f64_t *s) {
    if (!s) return NULL;
    smaug_series_f64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    double acc = 1.0;
    int null_seen = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (null_seen || SMAUG_NULL(s->null_mask, i)) {
            null_seen = 1;
        } else {
            acc *= s->data[i];
            r->data[i]      = acc;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* cummin: mínimo cumulativo. Nulos não propagam para frente — são pulados;
   a posição nula fica nula mas não contamina as seguintes.
   Contrato distinto de cumsum/cumprod (sem null-contagion). */
smaug_series_f64_t *smaug_f64_cummin(const smaug_series_f64_t *s) {
    if (!s) return NULL;
    smaug_series_f64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    int has_val = 0;
    double cur = 0.0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_NULL(s->null_mask, i)) continue;  /* null → null na saída (já SMAUG_MASK_NULL) */
        double v = s->data[i];
        if (!has_val || v < cur) { cur = v; has_val = 1; }
        r->data[i]      = cur;
        r->null_mask[i] = SMAUG_MASK_VALID;
    }
    return r;
}

/* cummax: máximo cumulativo. Mesmo contrato de cummin. */
smaug_series_f64_t *smaug_f64_cummax(const smaug_series_f64_t *s) {
    if (!s) return NULL;
    smaug_series_f64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    int has_val = 0;
    double cur = 0.0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_NULL(s->null_mask, i)) continue;
        double v = s->data[i];
        if (!has_val || v > cur) { cur = v; has_val = 1; }
        r->data[i]      = cur;
        r->null_mask[i] = SMAUG_MASK_VALID;
    }
    return r;
}

/* diff(periods): diferença s[i] - s[i-periods].
   Primeiros `periods` elementos → null. Null em qualquer operando → null. */
smaug_series_f64_t *smaug_f64_diff(const smaug_series_f64_t *s, size_t periods) {
    if (!s) return NULL;
    smaug_series_f64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    for (size_t i = periods; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i) && SMAUG_VALID(s->null_mask, i - periods)) {
            r->data[i]      = s->data[i] - s->data[i - periods];
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
        /* senão permanece null (SMAUG_MASK_NULL) */
    }
    return r;
}

/* shift(periods): desloca a série por `periods` posições, com sinal.
   periods > 0 → desloca para baixo (as primeiras `periods` posições viram NA);
   periods < 0 → desloca para cima (as últimas |periods| posições viram NA);
   periods == 0 → cópia. Para cada posição i, a fonte é (i - periods); fora do
   intervalo [0, size) o resultado é NA. |periods| >= size → série toda NA.
   (Item 7.1b: unifica os dois sentidos no Anel 0; antes o negativo era Lua.) */
smaug_series_f64_t *smaug_f64_shift(const smaug_series_f64_t *s, int64_t periods) {
    if (!s) return NULL;
    smaug_series_f64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    /* |periods| >= size → toda fonte cai fora do intervalo: série toda NA.
       Tratado à parte para evitar overflow em (int64_t)i - periods com
       `periods` próximo de INT64_MIN, e como atalho do caso comum. */
    if (periods <= -(int64_t)s->size || periods >= (int64_t)s->size) return r;
    /* create já inicializa null_mask como NULL; só preenchemos as posições
       cuja fonte cai no intervalo válido. */
    for (size_t i = 0; i < s->size; i++) {
        int64_t src = (int64_t)i - periods;
        if (src >= 0 && (size_t)src < s->size) {
            r->data[i]      = s->data[src];
            r->null_mask[i] = s->null_mask[src];
        }
    }
    return r;
}

/* ffill: preenche null com o último valor válido anterior.
   Nulls antes do primeiro valor válido permanecem null. */
smaug_series_f64_t *smaug_f64_ffill(const smaug_series_f64_t *s) {
    if (!s) return NULL;
    smaug_series_f64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    int has_last = 0;
    double last = 0.0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            last = s->data[i];
            has_last = 1;
        }
        if (has_last) {
            r->data[i]      = last;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
        /* senão permanece null (SMAUG_MASK_NULL) */
    }
    return r;
}

/* bfill: preenche null com o próximo valor válido seguinte.
   Nulls após o último valor válido permanecem null. */
smaug_series_f64_t *smaug_f64_bfill(const smaug_series_f64_t *s) {
    if (!s) return NULL;
    smaug_series_f64_t *r = alloc_result(s->size);
    if (!r) return NULL;
    int has_next = 0;
    double next = 0.0;
    /* percorre de trás para frente */
    for (size_t i = s->size; i-- > 0; ) {
        if (SMAUG_VALID(s->null_mask, i)) {
            next = s->data[i];
            has_next = 1;
        }
        if (has_next) {
            r->data[i]      = next;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* argmin: índice 0-based do menor valor não-null. SIZE_MAX se não há válidos. */
size_t smaug_f64_argmin(const smaug_series_f64_t *s) {
    if (!s || s->size == 0) return SIZE_MAX;
    size_t best_i = SIZE_MAX;
    double best_v = 0.0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            if (best_i == SIZE_MAX || s->data[i] < best_v) {
                best_v = s->data[i];
                best_i = i;
            }
        }
    }
    return best_i;
}

/* argmax: índice 0-based do maior valor não-null. SIZE_MAX se não há válidos. */
size_t smaug_f64_argmax(const smaug_series_f64_t *s) {
    if (!s || s->size == 0) return SIZE_MAX;
    size_t best_i = SIZE_MAX;
    double best_v = 0.0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            if (best_i == SIZE_MAX || s->data[i] > best_v) {
                best_v = s->data[i];
                best_i = i;
            }
        }
    }
    return best_i;
}

/* ===================================================================
   Grupo B — sorted_nonnull e rank (Fase 3 Ring 0)
   =================================================================== */

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a, db = *(const double *)b;
    return (da > db) - (da < db);
}

/* Comparador de pares [valor, índice_original] para rank */
static int cmp_rank_pair(const void *a, const void *b) {
    const double *pa = (const double *)a, *pb = (const double *)b;
    if (pa[0] != pb[0]) return (pa[0] > pb[0]) - (pa[0] < pb[0]);
    return (pa[1] > pb[1]) - (pa[1] < pb[1]);
}

/* smaug_f64_sorted_nonnull: coleta os valores não-nulos de s em array
   alocado (malloc), ordenado crescente. Devolve o ponteiro e escreve
   o n efetivo em *out_n. Retorna NULL em OOM ou se s == NULL.
   O array retornado tem *out_n doubles; caller libera com smaug_free.
   Série vazia ou toda-null: retorna NULL com *out_n = 0 (não é erro). */
double *smaug_f64_sorted_nonnull(const smaug_series_f64_t *s, size_t *out_n) {
    if (!s || !out_n) return NULL;
    size_t n = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) n++;
    }
    *out_n = n;
    if (n == 0) return NULL;

    double *arr = malloc(n * sizeof(double));
    if (!arr) return NULL;

    size_t j = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) arr[j++] = s->data[i];
    }
    qsort(arr, n, sizeof(double), cmp_double);
    return arr;
}

/* ===================================================================
   rank: atribui posição ordenada a cada elemento (1-based).
   method:
     0 = average  (default; empates recebem a média das posições)
     1 = min       (empates recebem a menor posição)
     2 = max       (empates recebem a maior posição)
     3 = first     (empates recebem posições por ordem de aparição)
   Nulos → NAN no resultado (caller converte para NA).
   Retorna double* de tamanho s->size; caller libera com smaug_free.
   =================================================================== */
double *smaug_f64_rank(const smaug_series_f64_t *s, int method) {
    if (!s) return NULL;
    size_t n = s->size;

    double *result = malloc(n * sizeof(double));
    if (!result) return NULL;

    for (size_t i = 0; i < n; i++) result[i] = NAN;

    size_t m = 0;
    for (size_t i = 0; i < n; i++) {
        if (SMAUG_VALID(s->null_mask, i)) m++;
    }
    if (m == 0) return result;

    /* pares [valor, índice_original] */
    double (*pairs)[2] = malloc(m * sizeof(*pairs));
    if (!pairs) { free(result); return NULL; }

    size_t j = 0;
    for (size_t i = 0; i < n; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            pairs[j][0] = s->data[i];
            pairs[j][1] = (double)i;
            j++;
        }
    }
    qsort(pairs, m, sizeof(*pairs), cmp_rank_pair);

    size_t p = 0;
    while (p < m) {
        size_t q = p;
        while (q + 1 < m && pairs[q+1][0] == pairs[p][0]) q++;

        double r_min = (double)(p + 1);
        double r_max = (double)(q + 1);

        for (size_t k = p; k <= q; k++) {
            size_t orig_i = (size_t)pairs[k][1];
            double rank_val;
            switch (method) {
                case 1:  rank_val = r_min;                   break;  /* min */
                case 2:  rank_val = r_max;                   break;  /* max */
                case 3:  rank_val = (double)(k + 1);         break;  /* first */
                default: rank_val = (r_min + r_max) / 2.0;  break;  /* average */
            }
            result[orig_i] = rank_val;
        }
        p = q + 1;
    }

    free(pairs);
    return result;
}

/* filter: retorna nova série com elementos onde mask[i] != 0.
   mask deve ter o mesmo tamanho que s. */
smaug_series_f64_t *smaug_f64_filter(const smaug_series_f64_t *s,
                                      const uint8_t *mask) {
    if (!s || !mask) return NULL;

    /* Primeiro passo: contar quantos elementos passar */
    size_t count = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (mask[i]) count++;
    }

    smaug_series_f64_t *r = smaug_f64_create(count);
    if (!r) return NULL;

    size_t j = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (mask[i]) {
            r->data[j]      = s->data[i];
            r->null_mask[j] = s->null_mask[i];
            j++;
        }
    }
    return r;
}
