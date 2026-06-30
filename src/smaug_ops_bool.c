#include "../include/smaug_bool.h"
#include <stdlib.h>
#include <stddef.h>
#include <math.h>

/* ===================================================================
   Operações booleanas com lógica de três valores (Kleene).
   Valores: 1 = true, 0 = false.  Máscara: SMAUG_MASK_VALID = válido, SMAUG_MASK_NULL = NA.
   =================================================================== */


/* Aloca o par (valores, máscara). Em falha, libera o que tiver alocado e
   devolve NULL (deixando *out_mask intacto/NULL). */
static uint8_t *alloc_pair(size_t n, smaug_mask_t **out_mask) {
    uint8_t *vals = malloc(n ? n : 1);
    if (!vals) return NULL;
    if (out_mask) {
        smaug_mask_t *m = malloc(n ? n : 1);
        if (!m) { free(vals); return NULL; }
        *out_mask = m;
    }
    return vals;
}

/* set helper: grava valor e máscara (se houver) numa posição. */
static inline void put(uint8_t *vals, smaug_mask_t *m, size_t i,
                       int value, int valid) {
    vals[i] = valid ? (value ? 1 : 0) : 0;
    if (m) m[i] = valid ? SMAUG_MASK_VALID : SMAUG_MASK_NULL;
}

uint8_t *smaug_bool_and(const uint8_t *a, const smaug_mask_t *am,
                        const uint8_t *b, const smaug_mask_t *bm,
                        size_t n, smaug_mask_t **out_mask) {
    if (!a || !b) return NULL;
    smaug_mask_t *m = NULL;
    uint8_t *r = alloc_pair(n, out_mask);
    if (!r) return NULL;
    if (out_mask) m = *out_mask;

    for (size_t i = 0; i < n; i++) {
        int av = SMAUG_OPTIONAL_VALID(am, i), bv = SMAUG_OPTIONAL_VALID(bm, i);
        int at = av && a[i], bt = bv && b[i];
        /* Kleene AND: false domina; NA só sobrevive se o outro não é false */
        if ((av && !a[i]) || (bv && !b[i])) {
            put(r, m, i, 0, 1);                 /* algum false -> false */
        } else if (av && bv) {
            put(r, m, i, at && bt, 1);          /* ambos válidos; COV-EXCL-BR: at&&bt sempre true aqui (linhas 45/47 ja garantiram ambos validos-nao-false) */
        } else {
            put(r, m, i, 0, 0);                 /* NA */
        }
    }
    return r;
}

uint8_t *smaug_bool_or(const uint8_t *a, const smaug_mask_t *am,
                       const uint8_t *b, const smaug_mask_t *bm,
                       size_t n, smaug_mask_t **out_mask) {
    if (!a || !b) return NULL;
    smaug_mask_t *m = NULL;
    uint8_t *r = alloc_pair(n, out_mask);
    if (!r) return NULL;
    if (out_mask) m = *out_mask;

    for (size_t i = 0; i < n; i++) {
        int av = SMAUG_OPTIONAL_VALID(am, i), bv = SMAUG_OPTIONAL_VALID(bm, i);
        /* Kleene OR: true domina; NA só sobrevive se o outro não é true */
        if ((av && a[i]) || (bv && b[i])) {
            put(r, m, i, 1, 1);                 /* algum true -> true */
        } else if (av && bv) {
            put(r, m, i, 0, 1);                 /* ambos válidos e false */
        } else {
            put(r, m, i, 0, 0);                 /* NA */
        }
    }
    return r;
}

uint8_t *smaug_bool_xor(const uint8_t *a, const smaug_mask_t *am,
                        const uint8_t *b, const smaug_mask_t *bm,
                        size_t n, smaug_mask_t **out_mask) {
    if (!a || !b) return NULL;
    smaug_mask_t *m = NULL;
    uint8_t *r = alloc_pair(n, out_mask);
    if (!r) return NULL;
    if (out_mask) m = *out_mask;

    for (size_t i = 0; i < n; i++) {
        int av = SMAUG_OPTIONAL_VALID(am, i), bv = SMAUG_OPTIONAL_VALID(bm, i);
        if (av && bv) put(r, m, i, (a[i] != 0) ^ (b[i] != 0), 1);
        else          put(r, m, i, 0, 0);       /* qualquer NA -> NA */
    }
    return r;
}

uint8_t *smaug_bool_not(const uint8_t *a, const smaug_mask_t *am,
                        size_t n, smaug_mask_t **out_mask) {
    if (!a) return NULL;
    smaug_mask_t *m = NULL;
    uint8_t *r = alloc_pair(n, out_mask);
    if (!r) return NULL;
    if (out_mask) m = *out_mask;

    for (size_t i = 0; i < n; i++) {
        int av = SMAUG_OPTIONAL_VALID(am, i);
        if (av) put(r, m, i, !a[i], 1);
        else    put(r, m, i, 0, 0);             /* NOT NA -> NA */
    }
    return r;
}

/* --- Agregações: NA ignorado --- */

size_t smaug_bool_count_true(const uint8_t *a, const smaug_mask_t *am, size_t n) {
    if (!a) return 0;
    size_t c = 0;
    for (size_t i = 0; i < n; i++)
        if (SMAUG_OPTIONAL_VALID(am, i) && a[i]) c++;
    return c;
}

bool smaug_bool_any(const uint8_t *a, const smaug_mask_t *am, size_t n) {
    if (!a) return false;
    for (size_t i = 0; i < n; i++)
        if (SMAUG_OPTIONAL_VALID(am, i) && a[i]) return true;
    return false;
}

bool smaug_bool_all(const uint8_t *a, const smaug_mask_t *am, size_t n) {
    if (!a) return true;            /* all() de vazio = true (vacuamente) */
    for (size_t i = 0; i < n; i++)
        if (SMAUG_OPTIONAL_VALID(am, i) && !a[i]) return false;
    return true;
}

/* ===================================================================
   BOOL — operações struct-based (dtype `bool` de primeira classe)
   -------------------------------------------------------------------
   Estas recebem/retornam smaug_series_bool_t, seguindo o padrão dos demais
   dtypes. A lógica Kleene reusa as funções raw acima (não reimplementa a
   tabela-verdade): extrai (data, null_mask) da struct, chama a raw, e embrulha
   o resultado numa nova struct. As raw permanecem como API até a BoolSeries
   ser aposentada (ver Roadmap, dívida de contrato do bool).
   =================================================================== */

#include "../include/smaug_core.h"     /* smaug_bool_create/free */
#include "../include/smaug_numeric.h"  /* protótipos struct-based */

/* Constrói uma série bool a partir de um par (valores, máscara) recém-alocado,
   assumindo posse: copia para a struct e libera os buffers crus. Em OOM
   devolve NULL e libera tudo. */
static smaug_series_bool_t *bool_series_from_pair(uint8_t *vals, smaug_mask_t *m, size_t n) {
    if (!vals) { smaug_free(m); return NULL; }
    smaug_series_bool_t *r = smaug_bool_create(n);
    if (!r) { smaug_free(vals); smaug_free(m); return NULL; }
    for (size_t i = 0; i < n; i++) {
        r->data[i]      = vals[i] ? 1 : 0;
        r->null_mask[i] = m ? m[i] : SMAUG_MASK_VALID;  /* COV-EXCL-BR: m sempre fornecido pelas Kleene raw (out_mask != NULL); ramo :SMAUG_MASK_VALID defensivo, uso interno controlado */
    }
    smaug_free(vals);
    smaug_free(m);
    return r;
}

smaug_series_bool_t *smaug_bool_series_and(const smaug_series_bool_t *a,
                                           const smaug_series_bool_t *b) {
    if (!a || !b || a->size != b->size) return NULL;
    smaug_mask_t *om = NULL;
    uint8_t *r = smaug_bool_and(a->data, a->null_mask, b->data, b->null_mask, a->size, &om);
    return bool_series_from_pair(r, om, a->size);
}

smaug_series_bool_t *smaug_bool_series_or(const smaug_series_bool_t *a,
                                          const smaug_series_bool_t *b) {
    if (!a || !b || a->size != b->size) return NULL;
    smaug_mask_t *om = NULL;
    uint8_t *r = smaug_bool_or(a->data, a->null_mask, b->data, b->null_mask, a->size, &om);
    return bool_series_from_pair(r, om, a->size);
}

smaug_series_bool_t *smaug_bool_series_xor(const smaug_series_bool_t *a,
                                           const smaug_series_bool_t *b) {
    if (!a || !b || a->size != b->size) return NULL;
    smaug_mask_t *om = NULL;
    uint8_t *r = smaug_bool_xor(a->data, a->null_mask, b->data, b->null_mask, a->size, &om);
    return bool_series_from_pair(r, om, a->size);
}

smaug_series_bool_t *smaug_bool_series_not(const smaug_series_bool_t *a) {
    if (!a) return NULL;
    smaug_mask_t *om = NULL;
    uint8_t *r = smaug_bool_not(a->data, a->null_mask, a->size, &om);
    return bool_series_from_pair(r, om, a->size);
}

/* --- Comparação com escalar → máscara uint8_t (espelha f64_eq).
   NA → resultado 0, out_mask NULL. threshold normalizado a 0/1. --- */
uint8_t *smaug_bool_eq(const smaug_series_bool_t *s, uint8_t threshold,
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
    uint8_t t = threshold ? 1 : 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = ((s->data[i] ? 1 : 0) == t) ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

uint8_t *smaug_bool_ne(const smaug_series_bool_t *s, uint8_t threshold,
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
    uint8_t t = threshold ? 1 : 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            result[i] = ((s->data[i] ? 1 : 0) != t) ? 1 : 0;
            if (mask) mask[i] = SMAUG_MASK_VALID;
        } else {
            result[i] = 0;
            if (mask) mask[i] = SMAUG_MASK_NULL;
        }
    }
    return result;
}

/* --- Agregações struct-based (reusam as raw) --- */
size_t smaug_bool_series_count_true(const smaug_series_bool_t *s) {
    if (!s) return 0;
    return smaug_bool_count_true(s->data, s->null_mask, s->size);
}
bool smaug_bool_series_any(const smaug_series_bool_t *s) {
    if (!s) return false;
    return smaug_bool_any(s->data, s->null_mask, s->size);
}
bool smaug_bool_series_all(const smaug_series_bool_t *s) {
    if (!s) return true;
    return smaug_bool_all(s->data, s->null_mask, s->size);
}

/* --- count_nonnull / seleção (espelham i64) --- */
size_t smaug_bool_count_nonnull(const smaug_series_bool_t *s) {
    if (!s) return 0;
    size_t c = 0;
    for (size_t i = 0; i < s->size; i++)
        if (SMAUG_VALID(s->null_mask, i)) c++;
    return c;
}

smaug_series_bool_t *smaug_bool_take(const smaug_series_bool_t *s,
                                     const size_t *idx, size_t len) {
    if (!s || !idx) return NULL;
    smaug_series_bool_t *r = smaug_bool_create(len);
    if (!r) return NULL;
    for (size_t i = 0; i < len; i++) {
        if (idx[i] >= s->size) { smaug_bool_free(r); return NULL; }
        r->data[i]      = s->data[idx[i]];
        r->null_mask[i] = s->null_mask[idx[i]];
    }
    return r;
}

smaug_series_bool_t *smaug_bool_filter(const smaug_series_bool_t *s,
                                       const uint8_t *mask) {
    if (!s || !mask) return NULL;
    size_t count = 0;
    for (size_t i = 0; i < s->size; i++)
        if (mask[i]) count++;
    smaug_series_bool_t *r = smaug_bool_create(count);
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

/* --- Ordenação: false < true; recusa NULL (como os demais dtypes) ---
   Estável: counting sort de dois baldes preserva a ordem relativa de iguais
   (argsort percorre os índices em ordem crescente). */
size_t *smaug_bool_argsort(const smaug_series_bool_t *s, bool ascending) {
    if (!s) return NULL;
    for (size_t i = 0; i < s->size; i++)
        if (SMAUG_NULL(s->null_mask, i)) return NULL;   /* qualquer NULL -> recusa */

    size_t *indices = malloc((s->size ? s->size : 1) * sizeof(size_t));
    if (!indices) return NULL;

    /* dois passes estáveis: na ordem ascendente, falses primeiro depois trues;
       descendente inverte. Percorrer em ordem de índice mantém estabilidade. */
    size_t j = 0;
    uint8_t first = ascending ? 0 : 1;   /* valor que vem primeiro */
    for (size_t i = 0; i < s->size; i++)
        if (s->data[i] == first) indices[j++] = i;
    for (size_t i = 0; i < s->size; i++)
        if (s->data[i] != first) indices[j++] = i;

    return indices;
}

smaug_series_bool_t *smaug_bool_sort(const smaug_series_bool_t *s, bool ascending) {
    if (!s) return NULL;
    size_t *indices = smaug_bool_argsort(s, ascending);
    if (!indices) return NULL;
    smaug_series_bool_t *r = smaug_bool_take(s, indices, s->size);
    smaug_free(indices);
    return r;
}

/* ===================================================================
   Movimentação de dados agnóstica a tipo (item 7.1): ffill / bfill.
   Padrão idêntico a f64/i64 — copia valor + máscara por posição.
   smaug_bool_create já inicializa a máscara como NULL, então posições
   não preenchidas permanecem NA sem ação extra.
   =================================================================== */

/* ffill: preenche NA com o último valor válido anterior.
   NAs antes do primeiro válido permanecem NA. */
smaug_series_bool_t *smaug_bool_ffill(const smaug_series_bool_t *s) {
    if (!s) return NULL;
    smaug_series_bool_t *r = smaug_bool_create(s->size);
    if (!r) return NULL;
    int     has_last = 0;
    uint8_t last     = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            last = s->data[i];
            has_last = 1;
        }
        if (has_last) {
            r->data[i]      = last;
            r->null_mask[i] = SMAUG_MASK_VALID;
        }
    }
    return r;
}

/* bfill: preenche NA com o próximo valor válido seguinte.
   NAs após o último válido permanecem NA. */
smaug_series_bool_t *smaug_bool_bfill(const smaug_series_bool_t *s) {
    if (!s) return NULL;
    smaug_series_bool_t *r = smaug_bool_create(s->size);
    if (!r) return NULL;
    int     has_next = 0;
    uint8_t next     = 0;
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

/* shift(periods): desloca por `periods` posições, com sinal.
   Mesma semântica de smaug_f64_shift (item 7.1b). Para cada posição i a
   fonte é (i - periods); fora de [0, size) → NA. */
smaug_series_bool_t *smaug_bool_shift(const smaug_series_bool_t *s, int64_t periods) {
    if (!s) return NULL;
    smaug_series_bool_t *r = smaug_bool_create(s->size);
    if (!r) return NULL;
    if (periods <= -(int64_t)s->size || periods >= (int64_t)s->size) return r;
    for (size_t i = 0; i < s->size; i++) {
        int64_t src = (int64_t)i - periods;
        if (src >= 0 && (size_t)src < s->size) {
            r->data[i]      = s->data[src];
            r->null_mask[i] = s->null_mask[src];
        }
    }
    return r;
}

/* argmin/argmax(): índice 0-based do menor/maior bool não-NA (false < true).
   SIZE_MAX se vazia ou toda-NA. (Item 7.2a.) */
size_t smaug_bool_argmin(const smaug_series_bool_t *s) {
    if (!s || s->size == 0) return SIZE_MAX;
    size_t  best_i = SIZE_MAX;
    uint8_t best_v = 0;
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
size_t smaug_bool_argmax(const smaug_series_bool_t *s) {
    if (!s || s->size == 0) return SIZE_MAX;
    size_t  best_i = SIZE_MAX;
    uint8_t best_v = 0;
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
   min / max (item 7.2b): bool é ordenável (false < true). Shape 1
   (valor + status), como smaug_bool_get — não há valor fora do domínio
   {0,1} para servir de sentinela, então o status sinaliza ausência:
   SMG_NULL_VALUE = vazia / toda-NA / (ignore_na=false) presença de NA;
   SMG_OK = há valor. status pode ser NULL (caller ignora).
   =================================================================== */
uint8_t smaug_bool_min(const smaug_series_bool_t *s, bool ignore_na,
                       smaug_status_t *status) {
    if (!s || s->size == 0) {
        if (status) *status = SMG_NULL_VALUE;
        return 0;
    }
    uint8_t result = 1;   /* maior possível: qualquer false reduz */
    bool    found  = false;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            uint8_t v = s->data[i] ? 1 : 0;
            if (!found || v < result) { result = v; found = true; }
        } else if (!ignore_na) {
            if (status) *status = SMG_NULL_VALUE;
            return 0;
        }
    }
    if (status) *status = found ? SMG_OK : SMG_NULL_VALUE;
    return found ? result : 0;
}

uint8_t smaug_bool_max(const smaug_series_bool_t *s, bool ignore_na,
                       smaug_status_t *status) {
    if (!s || s->size == 0) {
        if (status) *status = SMG_NULL_VALUE;
        return 0;
    }
    uint8_t result = 0;   /* menor possível: qualquer true aumenta */
    bool    found  = false;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            uint8_t v = s->data[i] ? 1 : 0;
            if (!found || v > result) { result = v; found = true; }
        } else if (!ignore_na) {
            if (status) *status = SMG_NULL_VALUE;
            return 0;
        }
    }
    if (status) *status = found ? SMG_OK : SMG_NULL_VALUE;
    return found ? result : 0;
}

/* ===================================================================
   rank (item 7.3): posição no ranking (false < true), 1-based. Só dois
   grupos, então não precisa de qsort — os `nf` false válidos ocupam as
   posições 1..nf, os `nt` true ocupam nf+1..nf+nt. method:
   0=average 1=min 2=max 3=first. NAN para NA. Caller libera.
   =================================================================== */
double *smaug_bool_rank(const smaug_series_bool_t *s, int method) {
    if (!s) return NULL;
    size_t n = s->size;
    double *result = malloc(n * sizeof(double));
    if (!result) return NULL;
    for (size_t i = 0; i < n; i++) result[i] = NAN;

    /* conta false e true válidos */
    size_t nf = 0, nt = 0;
    for (size_t i = 0; i < n; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            if (s->data[i]) nt++; else nf++;
        }
    }
    if (nf + nt == 0) return result;

    /* ranks de cada grupo conforme o método */
    double r_false = 0.0, r_true = 0.0;  /* usados em avg/min/max */
    /* false: posições 1..nf ; true: nf+1..nf+nt */
    double f_min = 1.0,            f_max = (double)nf;
    double t_min = (double)(nf+1), t_max = (double)(nf+nt);
    switch (method) {
        case 1:  r_false = f_min; r_true = t_min; break;  /* min */
        case 2:  r_false = f_max; r_true = t_max; break;  /* max */
        default: r_false = (f_min + f_max) / 2.0;         /* average */
                 r_true  = (t_min + t_max) / 2.0; break;
    }

    /* atribui na ordem original; para 'first' (method 3) o rank é
       sequencial dentro de cada grupo, na ordem de aparição. */
    size_t seen_f = 0, seen_t = 0;
    for (size_t i = 0; i < n; i++) {
        if (!SMAUG_VALID(s->null_mask, i)) continue;
        if (s->data[i]) {
            result[i] = (method == 3) ? (double)(nf + (++seen_t)) : r_true;
        } else {
            result[i] = (method == 3) ? (double)(++seen_f) : r_false;
        }
    }
    return result;
}
