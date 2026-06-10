#include "../include/smaug_core.h"
#include <math.h>      /* NAN */
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

/* Libera buffers crus devolvidos pelo backend, usando o mesmo heap/runtime que
   os alocou. Ver smaug_core.h. */
void smaug_free(void *ptr) {
    free(ptr);
}

/* ===================================================================
   Helpers internos (não expostos pelo header)
   =================================================================== */

/* Tenta crescer um array de doubles.
   Retorna 0 se ok, -1 se malloc falhou (série fica válida com old capacity). */
static int f64_grow(smaug_series_f64_t *s) {
    size_t new_cap = s->capacity ? (s->capacity + (s->capacity >> 1)) : 4;
    if (new_cap <= s->capacity) new_cap = s->capacity + 1; /* overflow guard; COV-EXCL-BR: overflow ao dobrar capacity; so com capacity ~ SIZE_MAX */

    double *nd = realloc(s->data, new_cap * sizeof(double));
    if (!nd) return -1;            /* data intacto; nada mudou, série consistente */
    s->data = nd;                  /* commit: data agora tem new_cap elementos */

    smaug_mask_t *nm = realloc(s->null_mask, new_cap * sizeof(smaug_mask_t));
    if (!nm) {
        /* null_mask falhou. data já cresceu — tenta encolher de volta para
           preservar o invariante (data e null_mask sempre com 'capacity'
           elementos). Encolher só faz sentido se capacity > 0: realloc(p, 0) é
           tratado como free(p) e devolve NULL, o que deixaria s->data pendente
           (dangling) e causaria double-free depois. Quando capacity == 0, o
           buffer maior simplesmente permanece — seguro (só usa um pouco mais de
           memória até o próximo grow). capacity fica inalterado em ambos os casos. */
        if (s->capacity > 0) {
            double *back = realloc(s->data, s->capacity * sizeof(double));
            if (back) s->data = back;  /* COV-EXCL-BR: realloc de shrink falhando; defensivo, mantem buffer maior (seguro) */
        }
        return -1;
    }
    s->null_mask = nm;
    s->capacity  = new_cap;
    return 0;
}

static int i64_grow(smaug_series_i64_t *s) {
    size_t new_cap = s->capacity ? (s->capacity + (s->capacity >> 1)) : 4;
    if (new_cap <= s->capacity) new_cap = s->capacity + 1;  /* COV-EXCL-BR: overflow ao dobrar capacity; so com capacity ~ SIZE_MAX */

    int64_t *nd = realloc(s->data, new_cap * sizeof(int64_t));
    if (!nd) return -1;            /* data intacto; série consistente */
    s->data = nd;

    smaug_mask_t *nm = realloc(s->null_mask, new_cap * sizeof(smaug_mask_t));
    if (!nm) {
        /* Ver f64_grow: encolhe data de volta só se capacity > 0 (realloc(p,0)
           liberaria o buffer e deixaria s->data pendente → double-free). */
        if (s->capacity > 0) {
            int64_t *back = realloc(s->data, s->capacity * sizeof(int64_t));
            if (back) s->data = back;  /* COV-EXCL-BR: realloc de shrink falhando; defensivo, mantem buffer maior (seguro) */
        }
        return -1;
    }
    s->null_mask = nm;
    s->capacity  = new_cap;
    return 0;
}

/* ===================================================================
   FLOAT64 — Lifecycle
   =================================================================== */

smaug_series_f64_t *smaug_f64_create_with_capacity(size_t size, size_t capacity) {
    if (size > capacity) return NULL;

    smaug_series_f64_t *s = malloc(sizeof(smaug_series_f64_t));
    if (!s) return NULL;

    if (capacity == 0) {
        s->data      = NULL;
        s->null_mask = NULL;
    } else {
        s->data = malloc(capacity * sizeof(double));
        if (!s->data) { free(s); return NULL; }

        s->null_mask = malloc(capacity * sizeof(smaug_mask_t));
        if (!s->null_mask) { free(s->data); free(s); return NULL; }

        memset(s->null_mask, 0x00, capacity);          /* tudo NULL por padrão */
        memset(s->data,      0,    size * sizeof(double));
    }

    s->size               = size;
    s->capacity           = capacity;
    s->meta.name          = "unnamed";
    s->meta.dtype         = "float64";
    s->meta.is_view       = false;
    s->meta.external_alloc = false;
    return s;
}

smaug_series_f64_t *smaug_f64_create(size_t size) {
    return smaug_f64_create_with_capacity(size, size);
}

smaug_series_f64_t *smaug_f64_create_from_array(const double *array, size_t len) {
    if (!array) return NULL;

    smaug_series_f64_t *s = smaug_f64_create_with_capacity(len, len);
    if (!s) return NULL;

    memcpy(s->data, array, len * sizeof(double));
    memset(s->null_mask, 0xFF, len);   /* todos os elementos são válidos */
    return s;
}

void smaug_f64_free(smaug_series_f64_t *s) {
    if (!s) return;
    if (!s->meta.external_alloc) {
        free(s->data);
        free(s->null_mask);
    }
    free(s);  /* o struct em si sempre é heap-allocated */
}

smaug_series_f64_t *smaug_f64_clone(const smaug_series_f64_t *s) {
    if (!s) return NULL;

    smaug_series_f64_t *c = smaug_f64_create_with_capacity(s->size, s->capacity);
    if (!c) return NULL;

    if (s->size > 0) {
        memcpy(c->data,      s->data,      s->size * sizeof(double));
        memcpy(c->null_mask, s->null_mask, s->size);
    }

    c->meta                = s->meta;
    c->meta.is_view        = false;
    c->meta.external_alloc = false;
    return c;
}

/* View: fatia sem cópia. O caller é responsável por garantir que a série-pai
   sobrevive a view. Mutações na view disparam COW detach (ver smaug_core.h).
   Checagem de limites overflow-safe: `start + len` pode fazer wrap em size_t
   se os valores forem muito grandes; a forma segura é `len > size - start`. */
smaug_series_f64_t *smaug_f64_view(smaug_series_f64_t *s, size_t start, size_t len) {
    if (!s || start > s->size || len > s->size - start) return NULL;

    smaug_series_f64_t *v = malloc(sizeof(smaug_series_f64_t));
    if (!v) return NULL;

    v->data                = s->data      + start;
    v->null_mask           = s->null_mask + start;
    v->size                = len;
    v->capacity            = len;
    v->meta                = s->meta;
    v->meta.is_view        = true;
    v->meta.external_alloc = true;   /* NÃO libera data/null_mask no free */
    return v;
}

/* --- Copy-on-Write detach ---
   Chamado antes de qualquer mutação numa view (set, set_null, append,
   append_null).  Aloca data e null_mask privados de tamanho `s->size` (a janela
   da view), copia os elementos e atualiza as flags, preservando o pai.
   Guarda size==0: view vazia não precisa de malloc; desvincula as flags.
   Retorna 0 se ok, -1 se OOM (série permanece intacta — falha segura). */
static int f64_cow_detach(smaug_series_f64_t *s) {
    if (!s->meta.is_view) return 0;            /* já é privada, nada a fazer */
    if (s->size == 0) {                        /* view vazia: sem dados a copiar */
        s->data                = NULL;
        s->null_mask           = NULL;
        s->capacity            = 0;
        s->meta.is_view        = false;
        s->meta.external_alloc = false;
        return 0;
    }
    double       *nd = malloc(s->size * sizeof *nd);
    smaug_mask_t *nm = malloc(s->size * sizeof *nm);
    if (!nd || !nm) { free(nd); free(nm); return -1; }
    memcpy(nd, s->data,      s->size * sizeof *nd);
    memcpy(nm, s->null_mask, s->size * sizeof *nm);
    s->data                = nd;
    s->null_mask           = nm;
    s->capacity            = s->size;          /* buffer privado = janela exata */
    s->meta.is_view        = false;
    s->meta.external_alloc = false;
    return 0;
}

/* --- Getters / Setters --- */

double smaug_f64_get(const smaug_series_f64_t *s, size_t idx, smaug_status_t *status) {
    if (!s)             { if (status) *status = SMG_ERR_ARGUMENT; return NAN; }
    if (idx >= s->size) { if (status) *status = SMG_ERR_OOB;      return NAN; }
    if (s->null_mask[idx] != 0xFF) { if (status) *status = SMG_NULL_VALUE; return NAN; }
    if (status) *status = SMG_OK;
    return s->data[idx];
}

smaug_status_t smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val) {
    if (!s)             return SMG_ERR_ARGUMENT;
    if (idx >= s->size) return SMG_ERR_OOB;
    if (f64_cow_detach(s) != 0) return SMG_ERR_NOMEM;
    s->data[idx]      = val;
    s->null_mask[idx] = 0xFF;
    return SMG_OK;
}

smaug_status_t smaug_f64_set_null(smaug_series_f64_t *s, size_t idx) {
    if (!s)             return SMG_ERR_ARGUMENT;
    if (idx >= s->size) return SMG_ERR_OOB;
    if (f64_cow_detach(s) != 0) return SMG_ERR_NOMEM;
    s->null_mask[idx] = 0x00;
    s->data[idx]      = 0.0;   /* limpa o dado (opcional, mas consistente) */
    return SMG_OK;
}

bool smaug_f64_is_null(smaug_series_f64_t *s, size_t idx) {
    if (!s || idx >= s->size) return true;
    return s->null_mask[idx] != 0xFF;
}

/* --- Append dinâmico --- */

int smaug_f64_append(smaug_series_f64_t *s, double val) {
    if (!s) return -1;
    if (f64_cow_detach(s) != 0) return -1;   /* COW: destaca se for view; -1 se OOM */

    if (s->size >= s->capacity) {
        if (f64_grow(s) != 0) return -1;
    }

    s->data[s->size]      = val;
    s->null_mask[s->size] = 0xFF;
    s->size++;
    return 0;
}

int smaug_f64_append_null(smaug_series_f64_t *s) {
    if (!s) return -1;
    if (f64_cow_detach(s) != 0) return -1;

    if (s->size >= s->capacity) {
        if (f64_grow(s) != 0) return -1;
    }

    s->data[s->size]      = 0.0;
    s->null_mask[s->size] = 0x00;
    s->size++;
    return 0;
}

/* ===================================================================
   INT64 — Lifecycle
   (análogo ao Float64; diferenças comentadas)
   =================================================================== */

smaug_series_i64_t *smaug_i64_create_with_capacity(size_t size, size_t capacity) {
    if (size > capacity) return NULL;

    smaug_series_i64_t *s = malloc(sizeof(smaug_series_i64_t));
    if (!s) return NULL;

    if (capacity == 0) {
        s->data      = NULL;
        s->null_mask = NULL;
    } else {
        s->data = malloc(capacity * sizeof(int64_t));
        if (!s->data) { free(s); return NULL; }

        s->null_mask = malloc(capacity * sizeof(smaug_mask_t));
        if (!s->null_mask) { free(s->data); free(s); return NULL; }

        memset(s->null_mask, 0x00, capacity);
        memset(s->data,      0,    size * sizeof(int64_t));
    }

    s->size               = size;
    s->capacity           = capacity;
    s->meta.name          = "unnamed";
    s->meta.dtype         = "int64";
    s->meta.is_view       = false;
    s->meta.external_alloc = false;
    return s;
}

smaug_series_i64_t *smaug_i64_create(size_t size) {
    return smaug_i64_create_with_capacity(size, size);
}

smaug_series_i64_t *smaug_i64_create_from_array(const int64_t *array, size_t len) {
    if (!array) return NULL;

    smaug_series_i64_t *s = smaug_i64_create_with_capacity(len, len);
    if (!s) return NULL;

    memcpy(s->data, array, len * sizeof(int64_t));
    memset(s->null_mask, 0xFF, len);
    return s;
}

void smaug_i64_free(smaug_series_i64_t *s) {
    if (!s) return;
    if (!s->meta.external_alloc) {
        free(s->data);
        free(s->null_mask);
    }
    free(s);
}

smaug_series_i64_t *smaug_i64_clone(const smaug_series_i64_t *s) {
    if (!s) return NULL;

    smaug_series_i64_t *c = smaug_i64_create_with_capacity(s->size, s->capacity);
    if (!c) return NULL;

    if (s->size > 0) {
        memcpy(c->data,      s->data,      s->size * sizeof(int64_t));
        memcpy(c->null_mask, s->null_mask, s->size);
    }

    c->meta                = s->meta;
    c->meta.is_view        = false;
    c->meta.external_alloc = false;
    return c;
}

smaug_series_i64_t *smaug_i64_view(smaug_series_i64_t *s, size_t start, size_t len) {
    if (!s || start > s->size || len > s->size - start) return NULL;

    smaug_series_i64_t *v = malloc(sizeof(smaug_series_i64_t));
    if (!v) return NULL;

    v->data                = s->data      + start;
    v->null_mask           = s->null_mask + start;
    v->size                = len;
    v->capacity            = len;
    v->meta                = s->meta;
    v->meta.is_view        = true;
    v->meta.external_alloc = true;
    return v;
}

/* --- Copy-on-Write detach (i64) ---
   Análogo ao f64_cow_detach.  Cobre set, set_null, append e append_null.
   Guarda size==0: view vazia desvincula sem malloc. */
static int i64_cow_detach(smaug_series_i64_t *s) {
    if (!s->meta.is_view) return 0;
    if (s->size == 0) {
        s->data                = NULL;
        s->null_mask           = NULL;
        s->capacity            = 0;
        s->meta.is_view        = false;
        s->meta.external_alloc = false;
        return 0;
    }
    int64_t      *nd = malloc(s->size * sizeof *nd);
    smaug_mask_t *nm = malloc(s->size * sizeof *nm);
    if (!nd || !nm) { free(nd); free(nm); return -1; }
    memcpy(nd, s->data,      s->size * sizeof *nd);
    memcpy(nm, s->null_mask, s->size * sizeof *nm);
    s->data                = nd;
    s->null_mask           = nm;
    s->capacity            = s->size;
    s->meta.is_view        = false;
    s->meta.external_alloc = false;
    return 0;
}

/* --- Getters / Setters --- */

/* Nota: int64_t não tem NAN. O caller DEVE verificar is_null() antes de get(). */
int64_t smaug_i64_get(const smaug_series_i64_t *s, size_t idx, smaug_status_t *status) {
    if (!s)             { if (status) *status = SMG_ERR_ARGUMENT; return 0; }
    if (idx >= s->size) { if (status) *status = SMG_ERR_OOB;      return 0; }
    if (s->null_mask[idx] != 0xFF) { if (status) *status = SMG_NULL_VALUE; return 0; }
    if (status) *status = SMG_OK;
    return s->data[idx];
}

smaug_status_t smaug_i64_set(smaug_series_i64_t *s, size_t idx, int64_t val) {
    if (!s)             return SMG_ERR_ARGUMENT;
    if (idx >= s->size) return SMG_ERR_OOB;
    if (i64_cow_detach(s) != 0) return SMG_ERR_NOMEM;
    s->data[idx]      = val;
    s->null_mask[idx] = 0xFF;
    return SMG_OK;
}

smaug_status_t smaug_i64_set_null(smaug_series_i64_t *s, size_t idx) {
    if (!s)             return SMG_ERR_ARGUMENT;
    if (idx >= s->size) return SMG_ERR_OOB;
    if (i64_cow_detach(s) != 0) return SMG_ERR_NOMEM;
    s->null_mask[idx] = 0x00;
    s->data[idx]      = 0;
    return SMG_OK;
}

bool smaug_i64_is_null(smaug_series_i64_t *s, size_t idx) {
    if (!s || idx >= s->size) return true;
    return s->null_mask[idx] != 0xFF;
}

/* --- Append dinâmico --- */

int smaug_i64_append(smaug_series_i64_t *s, int64_t val) {
    if (!s) return -1;
    if (i64_cow_detach(s) != 0) return -1;   /* COW: destaca se for view; -1 se OOM */

    if (s->size >= s->capacity) {
        if (i64_grow(s) != 0) return -1;
    }

    s->data[s->size]      = val;
    s->null_mask[s->size] = 0xFF;
    s->size++;
    return 0;
}

int smaug_i64_append_null(smaug_series_i64_t *s) {
    if (!s) return -1;
    if (i64_cow_detach(s) != 0) return -1;

    if (s->size >= s->capacity) {
        if (i64_grow(s) != 0) return -1;
    }

    s->data[s->size]      = 0;
    s->null_mask[s->size] = 0x00;
    s->size++;
    return 0;
}
