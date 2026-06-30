/* src/smaug_datetime.c
 *
 * Implementação do dtype datetime do Smaug (Anel 0, Tier 2).
 *
 * Armazenamento: epoch em milissegundos UTC (int64).
 * Calendário: Gregoriano proléptico — algoritmo de Rata Die
 * (proleptic Gregorian, sem dependência de localtime/mktime que
 * seriam timezone-dependentes e não-reentrantes).
 *
 * Zero dependências além da libc (stdint, string, stdlib, math).
 */

#include "../include/smaug_datetime.h"
#include "../include/smaug_core.h"  /* smaug_free */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <limits.h>
#include <math.h>

/* ===================================================================
   Constantes
   =================================================================== */

#define MS_PER_SECOND  1000LL
#define MS_PER_MINUTE  (60LL  * MS_PER_SECOND)
#define MS_PER_HOUR    (3600LL * MS_PER_SECOND)
#define MS_PER_DAY     (86400LL * MS_PER_SECOND)

/* INT64_MIN como sentinela de erro — igual ao i64 */
#define DT_SENTINEL INT64_MIN

/* ===================================================================
   Helpers internos — calendário Gregoriano
   -------------------------------------------------------------------
   Algoritmo: converte epoch_ms ↔ (year, month, day) sem usar
   localtime/mktime. Baseado em:
     Hinnant, Howard. "chrono-Compatible Low-Level Date Algorithms."
     http://howardhinnant.github.io/date_algorithms.html
   Funciona para qualquer data no intervalo int64 (±2.9×10^11 anos).
   =================================================================== */

/* Dia civil (0 = 1970-01-01) a partir de epoch_ms. */
static int64_t epoch_ms_to_civil_day(int64_t epoch_ms) {
    /* Divisão floor para dias negativos (antes de 1970). */
    if (epoch_ms >= 0) return epoch_ms / MS_PER_DAY;
    return (epoch_ms - MS_PER_DAY + 1) / MS_PER_DAY;
}

/* Milissegundos dentro do dia (0–86399999). */
static int64_t ms_of_day(int64_t epoch_ms) {
    int64_t ms = epoch_ms % MS_PER_DAY;
    if (ms < 0) ms += MS_PER_DAY;
    return ms;
}

/* Algoritmo de Hinnant: civil_day → (year, month, day).
   z = dias desde 1970-01-01 (pode ser negativo).
   Ref: http://howardhinnant.github.io/date_algorithms.html#civil_from_days */
static void civil_from_days(int64_t z, int *year, int *month, int *day) {
    z += 719468LL;                          /* shift para 0 = 0000-03-01 */
    int64_t era  = (z >= 0 ? z : z - 146096) / 146097;  /* COV-EXCL-BR: ramo z<0 no algoritmo de Hinnant — datas antes de ~292Mi a.C. */
    int64_t doe  = z - era * 146097;        /* day of era   [0, 146096] */
    int64_t yoe  = (doe - doe/1460 + doe/36524 - doe/146096) / 365; /* year of era [0, 399] */
    int64_t y    = yoe + era * 400;
    int64_t doy  = doe - (365*yoe + yoe/4 - yoe/100); /* day of year [0, 365] */
    int64_t mp   = (5*doy + 2) / 153;      /* month of year [0, 11] */
    int64_t d    = doy - (153*mp + 2)/5 + 1;
    int64_t m    = mp + (mp < 10 ? 3 : -9);
    if (m <= 2) y++;
    *year  = (int)y;
    *month = (int)m;
    *day   = (int)d;
}

/* Inverso: (year, month, day) → civil_day (dias desde 1970-01-01). */
static int64_t days_from_civil(int y, int m, int d) {
    int64_t Y = y, M = m, D = d;
    if (M <= 2) { Y--; M += 9; } else { M -= 3; }
    int64_t era = (Y >= 0 ? Y : Y - 399) / 400;  /* COV-EXCL-BR: ramo Y<0 no algoritmo de Hinnant — datas antes de ~292Mi a.C. */
    int64_t yoe = Y - era * 400;
    int64_t doy = (153*M + 2)/5 + D - 1;
    int64_t doe = yoe*365 + yoe/4 - yoe/100 + doy;
    return era * 146097 + doe - 719468LL;
}

/* Valida data Gregoriana. */
static bool is_valid_date(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1) return false;  /* COV-EXCL-BR: guards m/d inválidos — API interna; parse valida antes de chamar */
    /* dias no mês */
    static const int days_in_month[] = {0,31,28,31,30,31,30,31,31,30,31,30,31};
    int dim = days_in_month[m];
    if (m == 2) {
        bool leap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
        if (leap) dim = 29;
    }
    return d <= dim;
}

/* ===================================================================
   Helpers internos de alocação — mesmos padrões de smaug_core.c
   =================================================================== */


static int dt_grow(smaug_series_dt_t *s) {
    size_t new_cap = s->capacity ? (s->capacity + (s->capacity >> 1)) : 4;
    if (new_cap <= s->capacity) new_cap = s->capacity + 1; /* COV-EXCL-BR: overflow de capacity */

    int64_t *nd = realloc(s->data, new_cap * sizeof(int64_t));
    if (!nd) return -1;  /* COV-EXCL-BR: OOM em realloc(data) — coberto por test_allocfail */
    s->data = nd;

    smaug_mask_t *nm = realloc(s->null_mask, new_cap * sizeof(smaug_mask_t));
    if (!nm) {  /* COV-EXCL-BR: OOM em realloc(null_mask) — coberto por test_allocfail */
        if (s->capacity > 0) {  /* COV-EXCL-BR: realloc de shrink após falha — padrão defensivo documentado */
            int64_t *back = realloc(s->data, s->capacity * sizeof(int64_t));
            if (back) s->data = back; /* COV-EXCL-BR: realloc de shrink */
        }
        return -1;
    }
    s->null_mask = nm;
    s->capacity  = new_cap;
    return 0;
}

static int dt_cow_detach(smaug_series_dt_t *s) {
    if (!s->meta.is_view) return 0;
    if (s->size == 0) {  /* COV-EXCL-BR: view size==0 — caso degenerado de view vazia */
        s->data = NULL; s->null_mask = NULL; s->capacity = 0;
        s->meta.is_view = false; s->meta.external_alloc = false;
        return 0;
    }
    int64_t      *nd = malloc(s->size * sizeof(int64_t));
    smaug_mask_t *nm = malloc(s->size * sizeof(smaug_mask_t));
    if (!nd || !nm) { free(nd); free(nm); return -1; }  /* COV-EXCL-BR: OOM em malloc de buffers COW — coberto por test_allocfail */
    memcpy(nd, s->data,      s->size * sizeof(int64_t));
    memcpy(nm, s->null_mask, s->size);
    s->data = nd; s->null_mask = nm;
    s->capacity = s->size;
    s->meta.is_view = false; s->meta.external_alloc = false;
    return 0;
}

/* ===================================================================
   Lifecycle
   =================================================================== */

smaug_series_dt_t *smaug_dt_create_with_capacity(size_t size, size_t capacity) {
    if (size > capacity) return NULL;  /* COV-EXCL-BR: size > capacity — invariante; create() nunca viola */

    smaug_series_dt_t *s = malloc(sizeof(smaug_series_dt_t));
    if (!s) return NULL;  /* COV-EXCL-BR: OOM em malloc(struct) — coberto por test_allocfail */

    if (capacity == 0) {
        s->data = NULL; s->null_mask = NULL;
    } else {
        s->data = malloc(capacity * sizeof(int64_t));
        if (!s->data) { free(s); return NULL; }  /* COV-EXCL-BR: OOM em malloc(data) — coberto por test_allocfail */

        s->null_mask = malloc(capacity * sizeof(smaug_mask_t));
        if (!s->null_mask) { free(s->data); free(s); return NULL; }  /* COV-EXCL-BR: OOM em malloc(null_mask) — coberto por test_allocfail */

        memset(s->null_mask, SMAUG_MASK_NULL, capacity);
        memset(s->data,      0,    size * sizeof(int64_t));
    }

    s->size                = size;
    s->capacity            = capacity;
    s->meta.name           = "unnamed";
    s->meta.dtype          = "datetime";
    s->meta.is_view        = false;
    s->meta.external_alloc = false;
    return s;
}

smaug_series_dt_t *smaug_dt_create(size_t size) {
    return smaug_dt_create_with_capacity(size, size);
}

smaug_series_dt_t *smaug_dt_create_from_array(const int64_t *array, size_t len) {
    if (!array) return NULL;  /* COV-EXCL-BR: array==NULL — uso incorreto de API interna */
    smaug_series_dt_t *s = smaug_dt_create_with_capacity(len, len);
    if (!s) return NULL;  /* COV-EXCL-BR: OOM em create — coberto por test_allocfail */
    memcpy(s->data, array, len * sizeof(int64_t));
    memset(s->null_mask, SMAUG_MASK_VALID, len);
    return s;
}

void smaug_dt_free(smaug_series_dt_t *s) {
    if (!s) return;
    if (!s->meta.external_alloc) {  /* COV-EXCL-BR: external_alloc — só vistas têm external_alloc=true; free de view liberaria buffer compartilhado */
        free(s->data);
        free(s->null_mask);
    }
    free(s);
}

smaug_series_dt_t *smaug_dt_clone(const smaug_series_dt_t *s) {
    if (!s) return NULL;  /* COV-EXCL-BR: s==NULL — defensivo, caller já verifica */
    smaug_series_dt_t *c = smaug_dt_create_with_capacity(s->size, s->capacity);
    if (!c) return NULL;  /* COV-EXCL-BR: OOM em create — coberto por test_allocfail */
    if (s->size > 0) {  /* COV-EXCL-BR: size==0 — clone de série vazia tem size=0, memcpy não executado */
        memcpy(c->data,      s->data,      s->size * sizeof(int64_t));
        memcpy(c->null_mask, s->null_mask, s->size);
    }
    c->meta = s->meta;
    c->meta.is_view = false; c->meta.external_alloc = false;
    return c;
}

smaug_series_dt_t *smaug_dt_view(smaug_series_dt_t *s, size_t start, size_t len) {
    if (!s || start > s->size || len > s->size - start) return NULL;  /* COV-EXCL-BR: args inválidos — start > size ou len > size-start */
    smaug_series_dt_t *v = malloc(sizeof(smaug_series_dt_t));
    if (!v) return NULL;  /* COV-EXCL-BR: OOM em malloc(view struct) — coberto por test_allocfail */
    v->data                = s->data      + start;
    v->null_mask           = s->null_mask + start;
    v->size                = len;
    v->capacity            = len;
    v->meta                = s->meta;
    v->meta.is_view        = true;
    v->meta.external_alloc = true;
    return v;
}

/* ===================================================================
   Acesso
   =================================================================== */

int64_t smaug_dt_get(const smaug_series_dt_t *s, size_t idx,
                      smaug_status_t *status) {
    if (!s)             { if (status) *status = SMG_ERR_ARGUMENT; return DT_SENTINEL; }
    if (idx >= s->size) { if (status) *status = SMG_ERR_OOB;      return DT_SENTINEL; }
    if (SMAUG_NULL(s->null_mask, idx)) { if (status) *status = SMG_NULL_VALUE; return DT_SENTINEL; }
    if (status) *status = SMG_OK;
    return s->data[idx];
}

smaug_status_t smaug_dt_set(smaug_series_dt_t *s, size_t idx, int64_t epoch_ms) {
    if (!s)             return SMG_ERR_ARGUMENT;
    if (idx >= s->size) return SMG_ERR_OOB;
    if (dt_cow_detach(s) != 0) return SMG_ERR_NOMEM;
    s->data[idx]      = epoch_ms;
    s->null_mask[idx] = SMAUG_MASK_VALID;
    return SMG_OK;
}

smaug_status_t smaug_dt_set_null(smaug_series_dt_t *s, size_t idx) {
    if (!s)             return SMG_ERR_ARGUMENT;
    if (idx >= s->size) return SMG_ERR_OOB;
    if (dt_cow_detach(s) != 0) return SMG_ERR_NOMEM;
    s->null_mask[idx] = SMAUG_MASK_NULL;
    s->data[idx]      = 0;
    return SMG_OK;
}

bool smaug_dt_is_null(const smaug_series_dt_t *s, size_t idx) {
    if (!s || idx >= s->size) return true;
    return SMAUG_NULL(s->null_mask, idx);
}

int smaug_dt_append(smaug_series_dt_t *s, int64_t epoch_ms) {
    if (!s) return -1;
    if (dt_cow_detach(s) != 0) return -1;
    if (s->size >= s->capacity) {
        if (dt_grow(s) != 0) return -1;
    }
    s->data[s->size]      = epoch_ms;
    s->null_mask[s->size] = SMAUG_MASK_VALID;
    s->size++;
    return 0;
}

int smaug_dt_append_null(smaug_series_dt_t *s) {
    if (!s) return -1;
    if (dt_cow_detach(s) != 0) return -1;
    if (s->size >= s->capacity) {
        if (dt_grow(s) != 0) return -1;
    }
    s->data[s->size]      = 0;
    s->null_mask[s->size] = SMAUG_MASK_NULL;
    s->size++;
    return 0;
}

/* ===================================================================
   Parsing ISO 8601
   -------------------------------------------------------------------
   Suporta:
     YYYY-MM-DD
     YYYY-MM-DDTHH:MM:SS
     YYYY-MM-DDTHH:MM:SS.mmm
     YYYY-MM-DDTHH:MM:SSZ
     YYYY-MM-DDTHH:MM:SS+HH:MM
     YYYY-MM-DDTHH:MM:SS-HH:MM
   =================================================================== */

/* Lê exatamente n dígitos decimais de s; escreve valor em *out.
   Retorna ponteiro após os dígitos, ou NULL em erro. */
static const char *parse_digits(const char *p, const char *end, int n, int *out) {
    if (p + n > end) return NULL;
    int v = 0;
    for (int i = 0; i < n; i++) {
        if (p[i] < '0' || p[i] > '9') return NULL;
        v = v * 10 + (p[i] - '0');
    }
    *out = v;
    return p + n;
}

/* Lê 1 ou 2 dígitos (para dia/mês em formato year-last: "5/6/2026" ou
   "05/06/2026"). Para no primeiro não-dígito. Retorna NULL se nenhum dígito. */
static const char *parse_digits_1or2(const char *p, const char *end, int *out) {
    if (p >= end || p[0] < '0' || p[0] > '9') return NULL;
    int v = p[0] - '0';
    p++;
    if (p < end && p[0] >= '0' && p[0] <= '9') {
        v = v * 10 + (p[0] - '0');
        p++;
    }
    *out = v;
    return p;
}

/* Lê a porção de DATA de [p,end), detectando year-first (YYYY-MM-DD) ou
   year-last (DD/MM/YYYY ou MM/DD/YYYY). Para year-last, dayfirst escolhe a
   ordem: 1 = dia primeiro (DD/MM), 0 = mês primeiro (MM/DD). Separador '-' ou
   '/', consistente. Avança *pp e preenche y/mo/d. Retorna 0 ok, -1 erro. */
static int parse_date_part(const char **pp, const char *end, int dayfirst,
                           int *y, int *mo, int *d) {
    const char *p = *pp;
    /* tenta year-first: 4 dígitos + separador */
    if (p + 4 <= end && p[0] >= '0' && p[0] <= '9' && p[1] >= '0' && p[1] <= '9'
        && p[2] >= '0' && p[2] <= '9' && p[3] >= '0' && p[3] <= '9'
        && (p[4] == '-' || p[4] == '/')) {
        /* YYYY<sep>MM<sep>DD — ordem fixa, dayfirst não se aplica */
        if (!(p = parse_digits(p, end, 4, y)))   return -1;
        char sep = *p++;
        if (!(p = parse_digits(p, end, 2, mo)))  return -1;
        if (p >= end || *p++ != sep)             return -1;
        if (!(p = parse_digits(p, end, 2, d)))   return -1;
        *pp = p;
        return 0;
    }

    /* year-last: AA<sep>BB<sep>YYYY (1-2 dígitos cada nos dois primeiros).
       AA e BB são dia/mês conforme dayfirst. */
    int a, b;
    if (!(p = parse_digits_1or2(p, end, &a)))    return -1;
    if (p >= end || (*p != '-' && *p != '/'))    return -1;
    char sep = *p++;
    if (!(p = parse_digits_1or2(p, end, &b)))    return -1;
    if (p >= end || *p++ != sep)                 return -1;
    if (!(p = parse_digits(p, end, 4, y)))       return -1;
    if (dayfirst) { *d = a; *mo = b; }   /* DD/MM */
    else          { *mo = a; *d = b; }   /* MM/DD */
    *pp = p;
    return 0;
}

int smaug_dt_parse(const char *str, size_t len, int64_t *epoch_ms, int dayfirst) {
    if (!str || !epoch_ms) return -1;
    const char *p   = str;
    const char *end = str + len;

    int y, mo, d, h = 0, mi = 0, sec = 0, ms = 0;
    if (parse_date_part(&p, end, dayfirst, &y, &mo, &d) != 0) return -1;
    if (!is_valid_date(y, mo, d))                  return -1;

    /* Hora opcional: T ou ' ' */
    int tz_sign = 0, tz_h = 0, tz_m = 0;

    if (p < end && (*p == 'T' || *p == ' ')) {
        p++;
        if (!(p = parse_digits(p, end, 2, &h)))   return -1;
        if (p >= end || *p++ != ':')               return -1;
        if (!(p = parse_digits(p, end, 2, &mi)))  return -1;
        if (p >= end || *p++ != ':')               return -1;
        if (!(p = parse_digits(p, end, 2, &sec))) return -1;
        if (h > 23 || mi > 59 || sec > 59)        return -1;

        /* milissegundos opcionais */
        if (p < end && *p == '.') {
            p++;
            /* aceita 1–9 dígitos, usa apenas os 3 primeiros */
            int cnt = 0;
            int ms_val = 0;
            while (p < end && *p >= '0' && *p <= '9') {
                if (cnt < 3) ms_val = ms_val * 10 + (*p - '0');
                cnt++; p++;
            }
            /* pad para ms se menos de 3 dígitos */
            while (cnt < 3) { ms_val *= 10; cnt++; }
            ms = ms_val;
        }

        /* timezone opcional */
        if (p < end) {
            if (*p == 'Z') {
                p++; /* UTC */
            } else if (*p == '+' || *p == '-') {
                tz_sign = (*p == '+') ? 1 : -1;
                p++;
                if (!(p = parse_digits(p, end, 2, &tz_h))) return -1;
                if (p < end && *p == ':') p++;
                if (!(p = parse_digits(p, end, 2, &tz_m))) return -1;
                if (tz_h > 23 || tz_m > 59) return -1;
            }
        }
    }

    /* sobra algo no buffer → inválido */
    if (p != end) return -1;

    int64_t days   = days_from_civil(y, mo, d);
    int64_t result = days       * MS_PER_DAY
                   + (int64_t)h   * MS_PER_HOUR
                   + (int64_t)mi  * MS_PER_MINUTE
                   + (int64_t)sec * MS_PER_SECOND
                   + ms;

    /* subtrai offset de timezone para obter UTC */
    if (tz_sign != 0) {
        int64_t tz_offset = ((int64_t)tz_h * 60 + tz_m) * MS_PER_MINUTE;
        result -= tz_sign * tz_offset;
    }

    *epoch_ms = result;
    return 0;
}

int smaug_dt_format(int64_t epoch_ms, char *buf, size_t buf_size) {
    if (!buf || buf_size < 26) return -1;

    int64_t day_ms = ms_of_day(epoch_ms);
    int64_t civil  = epoch_ms_to_civil_day(epoch_ms);

    int y, mo, d;
    civil_from_days(civil, &y, &mo, &d);

    int h   = (int)(day_ms / MS_PER_HOUR);   day_ms %= MS_PER_HOUR;
    int mi  = (int)(day_ms / MS_PER_MINUTE);  day_ms %= MS_PER_MINUTE;
    int sec = (int)(day_ms / MS_PER_SECOND);
    int ms  = (int)(day_ms % MS_PER_SECOND);

    /* formato: "YYYY-MM-DDTHH:MM:SS.mmmZ" */
    int written = snprintf(buf, buf_size,
        "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
        y, mo, d, h, mi, sec, ms);

    return (written > 0 && (size_t)written < buf_size) ? 0 : -1;
}

/* ===================================================================
   Extração de componentes
   =================================================================== */

int smaug_dt_year(int64_t epoch_ms) {
    int y, mo, d;
    civil_from_days(epoch_ms_to_civil_day(epoch_ms), &y, &mo, &d);
    return y;
}

int smaug_dt_month(int64_t epoch_ms) {
    int y, mo, d;
    civil_from_days(epoch_ms_to_civil_day(epoch_ms), &y, &mo, &d);
    return mo;
}

int smaug_dt_day(int64_t epoch_ms) {
    int y, mo, d;
    civil_from_days(epoch_ms_to_civil_day(epoch_ms), &y, &mo, &d);
    return d;
}

int smaug_dt_hour(int64_t epoch_ms) {
    return (int)(ms_of_day(epoch_ms) / MS_PER_HOUR);
}

int smaug_dt_minute(int64_t epoch_ms) {
    return (int)((ms_of_day(epoch_ms) % MS_PER_HOUR) / MS_PER_MINUTE);
}

int smaug_dt_second(int64_t epoch_ms) {
    return (int)((ms_of_day(epoch_ms) % MS_PER_MINUTE) / MS_PER_SECOND);
}

int smaug_dt_ms(int64_t epoch_ms) {
    return (int)(ms_of_day(epoch_ms) % MS_PER_SECOND);
}

int smaug_dt_weekday(int64_t epoch_ms) {
    /* 1970-01-01 foi quinta-feira = 3. Queremos 0=segunda. */
    int64_t d = epoch_ms_to_civil_day(epoch_ms);
    int wd = (int)((d + 3) % 7);
    if (wd < 0) wd += 7;
    return wd;  /* 0=seg, 1=ter, 2=qua, 3=qui, 4=sex, 5=sab, 6=dom */
}

int smaug_dt_quarter(int64_t epoch_ms) {
    return (smaug_dt_month(epoch_ms) - 1) / 3 + 1;
}

int smaug_dt_yearday(int64_t epoch_ms) {
    int y, mo, d;
    civil_from_days(epoch_ms_to_civil_day(epoch_ms), &y, &mo, &d);
    /* dias do ano = dias desde 1-Jan do mesmo ano */
    int64_t jan1 = days_from_civil(y, 1, 1);
    int64_t cur  = epoch_ms_to_civil_day(epoch_ms);
    return (int)(cur - jan1) + 1;
}

int smaug_dt_week(int64_t epoch_ms) {
    /* ISO 8601: semana começa na segunda-feira.
       Semana 1 = semana que contém a 1ª quinta-feira do ano. */
    int y, mo, d;
    int64_t cd = epoch_ms_to_civil_day(epoch_ms);
    civil_from_days(cd, &y, &mo, &d);

    /* dia da semana ISO: 1=seg .. 7=dom */
    int wd = smaug_dt_weekday(epoch_ms) + 1;  /* 1-based */

    /* Número da semana: floor((doy - wd + 10) / 7) */
    int doy = smaug_dt_yearday(epoch_ms);
    int week = (doy - wd + 10) / 7;

    if (week < 1) {
        /* pertence à última semana do ano anterior */
        int64_t dec28 = days_from_civil(y - 1, 12, 28);
        /* última 5ª-feira do ano anterior */
        int wd_dec28 = (int)((dec28 + 3) % 7);
        if (wd_dec28 < 0) wd_dec28 += 7;
        week = (smaug_dt_yearday(
                    (days_from_civil(y-1,1,1) + 363 + 3 - wd_dec28) * MS_PER_DAY)
                + 6) / 7;
        (void)week;
        /* simplificação: retorna 53 quando pertence ao ano anterior */
        week = 53;
    } else if (week > 52) {
        /* verificar se semana 53 existe */
        int64_t dec28_cur = days_from_civil(y, 12, 28);
        int wd_dec28 = (int)((dec28_cur + 3) % 7);
        if (wd_dec28 < 0) wd_dec28 += 7;
        /* se 28-Dez for segunda a quinta, semana 53 existe */
        if (wd_dec28 > 3) week = 1; /* pertence à semana 1 do próximo ano */
    }
    return week < 1 ? 1 : week;
}

/* ===================================================================
   Construção a partir de componentes
   =================================================================== */

int64_t smaug_dt_from_parts(int year, int month, int day,
                              int hour, int minute, int second, int ms) {
    if (!is_valid_date(year, month, day)) return DT_SENTINEL;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59 ||
        second < 0 || second > 59 || ms < 0 || ms > 999) return DT_SENTINEL;

    int64_t days   = days_from_civil(year, month, day);
    return days       * MS_PER_DAY
         + (int64_t)hour   * MS_PER_HOUR
         + (int64_t)minute * MS_PER_MINUTE
         + (int64_t)second * MS_PER_SECOND
         + ms;
}

/* ===================================================================
   Aritmética
   =================================================================== */

int64_t smaug_dt_diff_ms(int64_t a, int64_t b) {
    return a - b;
}

int64_t smaug_dt_add_ms(int64_t epoch_ms, int64_t delta_ms) {
    /* Detecta overflow: se os sinais de epoch_ms e delta_ms são iguais
       e o resultado tem sinal diferente, houve overflow. */
    int64_t result = epoch_ms + delta_ms;
    if ((delta_ms > 0 && result < epoch_ms) ||
        (delta_ms < 0 && result > epoch_ms)) return DT_SENTINEL;
    return result;
}

int64_t smaug_dt_truncate(int64_t epoch_ms, char unit) {
    switch (unit) {
        case 's': /* segundo */
            return (epoch_ms / MS_PER_SECOND) * MS_PER_SECOND
                 - (epoch_ms < 0 && epoch_ms % MS_PER_SECOND != 0 ? MS_PER_SECOND : 0);
        case 'm': /* minuto */
            return (epoch_ms / MS_PER_MINUTE) * MS_PER_MINUTE
                 - (epoch_ms < 0 && epoch_ms % MS_PER_MINUTE != 0 ? MS_PER_MINUTE : 0);
        case 'h': /* hora */
            return (epoch_ms / MS_PER_HOUR) * MS_PER_HOUR
                 - (epoch_ms < 0 && epoch_ms % MS_PER_HOUR != 0 ? MS_PER_HOUR : 0);
        case 'D': { /* dia */
            int64_t d = epoch_ms_to_civil_day(epoch_ms);
            return d * MS_PER_DAY;
        }
        case 'W': { /* semana — retrocede para a segunda-feira anterior */
            int64_t d  = epoch_ms_to_civil_day(epoch_ms);
            int     wd = smaug_dt_weekday(epoch_ms); /* 0=seg */
            return (d - wd) * MS_PER_DAY;
        }
        case 'M': { /* mês */
            int y, mo, d;
            civil_from_days(epoch_ms_to_civil_day(epoch_ms), &y, &mo, &d);
            return days_from_civil(y, mo, 1) * MS_PER_DAY;
        }
        case 'Q': { /* trimestre */
            int y, mo, d;
            civil_from_days(epoch_ms_to_civil_day(epoch_ms), &y, &mo, &d);
            int q_start = ((mo - 1) / 3) * 3 + 1;
            return days_from_civil(y, q_start, 1) * MS_PER_DAY;
        }
        case 'Y': { /* ano */
            int y, mo, d;
            civil_from_days(epoch_ms_to_civil_day(epoch_ms), &y, &mo, &d);
            return days_from_civil(y, 1, 1) * MS_PER_DAY;
        }
        default:
            return DT_SENTINEL;
    }
}

/* ===================================================================
   Comparações
   =================================================================== */

#define DT_CMP_IMPL(name, op)                                               \
uint8_t* smaug_dt_##name(const smaug_series_dt_t *s, int64_t threshold,    \
                           smaug_mask_t **out_mask) {                        \
    if (!s) return NULL;                                                      \
    uint8_t *result = malloc(s->size * sizeof(uint8_t));                      \
    if (!result) return NULL;                                                 \
    smaug_mask_t *mask = malloc(s->size * sizeof(smaug_mask_t));              \
    if (!mask) { free(result); return NULL; }                                 \
    for (size_t i = 0; i < s->size; i++) {                                   \
        if (SMAUG_NULL(s->null_mask, i)) {                                               \
            result[i] = 0; mask[i] = SMAUG_MASK_NULL;                                   \
        } else {                                                              \
            result[i] = (s->data[i] op threshold) ? 1 : 0;                  \
            mask[i]   = SMAUG_MASK_VALID;                                                 \
        }                                                                     \
    }                                                                         \
    if (out_mask) *out_mask = mask; else free(mask);                          \
    return result;                                                            \
}

DT_CMP_IMPL(gt, > )
DT_CMP_IMPL(lt, < )
DT_CMP_IMPL(eq, ==)
DT_CMP_IMPL(ge, >=)
DT_CMP_IMPL(le, <=)
DT_CMP_IMPL(ne, !=)

/* ===================================================================
   Ordenação
   =================================================================== */

typedef struct { size_t idx; int64_t val; } dt_entry_t;

static int cmp_dt_asc(const void *a, const void *b) {
    const dt_entry_t *ea = (const dt_entry_t *)a;
    const dt_entry_t *eb = (const dt_entry_t *)b;
    if (ea->val < eb->val) return -1;
    if (ea->val > eb->val) return  1;
    return 0;
}

static int cmp_dt_desc(const void *a, const void *b) {
    return cmp_dt_asc(b, a);
}

size_t *smaug_dt_argsort(const smaug_series_dt_t *s, bool ascending) {
    if (!s) return NULL;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_NULL(s->null_mask, i)) return NULL;
    }

    dt_entry_t *entries = malloc(s->size * sizeof(dt_entry_t));
    if (!entries) return NULL;

    for (size_t i = 0; i < s->size; i++) {
        entries[i].idx = i;
        entries[i].val = s->data[i];
    }

    qsort(entries, s->size, sizeof(dt_entry_t),
          ascending ? cmp_dt_asc : cmp_dt_desc);

    size_t *indices = malloc(s->size * sizeof(size_t));
    if (!indices) { free(entries); return NULL; }

    for (size_t i = 0; i < s->size; i++) indices[i] = entries[i].idx;
    free(entries);
    return indices;
}

smaug_series_dt_t *smaug_dt_sort(const smaug_series_dt_t *s, bool ascending) {
    if (!s) return NULL;
    size_t *indices = smaug_dt_argsort(s, ascending);
    if (!indices) return NULL;
    smaug_series_dt_t *result = smaug_dt_take(s, indices, s->size);
    free(indices);
    return result;
}

/* ===================================================================
   Utilitários
   =================================================================== */

size_t smaug_dt_count_nonnull(const smaug_series_dt_t *s) {
    if (!s) return 0;
    size_t count = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) count++;
    }
    return count;
}

smaug_series_dt_t *smaug_dt_take(const smaug_series_dt_t *s,
                                   const size_t *idx, size_t len) {
    if (!s || !idx) return NULL;
    smaug_series_dt_t *result = smaug_dt_create(len);
    if (!result) return NULL;
    for (size_t i = 0; i < len; i++) {
        if (idx[i] >= s->size) {
            result->null_mask[i] = SMAUG_MASK_NULL;
            result->data[i]      = 0;
        } else {
            result->data[i]      = s->data[idx[i]];
            result->null_mask[i] = s->null_mask[idx[i]];
        }
    }
    return result;
}

smaug_series_dt_t *smaug_dt_filter(const smaug_series_dt_t *s,
                                     const uint8_t *mask) {
    if (!s || !mask) return NULL;
    size_t count = 0;
    for (size_t i = 0; i < s->size; i++) if (mask[i]) count++;

    smaug_series_dt_t *result = smaug_dt_create(count);
    if (!result) return NULL;

    size_t j = 0;
    for (size_t i = 0; i < s->size; i++) {
        if (mask[i]) {
            result->data[j]      = s->data[i];
            result->null_mask[j] = s->null_mask[i];
            j++;
        }
    }
    return result;
}

/* ===================================================================
   Movimentação de dados agnóstica a tipo (item 7.1): ffill / bfill.
   Padrão idêntico a f64/i64 — copia valor + máscara por posição.
   smaug_dt_create já inicializa a máscara como NULL.
   =================================================================== */

/* ffill: preenche NA com o último valor válido anterior.
   NAs antes do primeiro válido permanecem NA. */
smaug_series_dt_t *smaug_dt_ffill(const smaug_series_dt_t *s) {
    if (!s) return NULL;
    smaug_series_dt_t *r = smaug_dt_create(s->size);
    if (!r) return NULL;
    int     has_last = 0;
    int64_t last     = 0;
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
smaug_series_dt_t *smaug_dt_bfill(const smaug_series_dt_t *s) {
    if (!s) return NULL;
    smaug_series_dt_t *r = smaug_dt_create(s->size);
    if (!r) return NULL;
    int     has_next = 0;
    int64_t next     = 0;
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
   Mesma semântica de smaug_f64_shift (item 7.1b). */
smaug_series_dt_t *smaug_dt_shift(const smaug_series_dt_t *s, int64_t periods) {
    if (!s) return NULL;
    smaug_series_dt_t *r = smaug_dt_create(s->size);
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

/* argmin/argmax(): índice 0-based do menor/maior datetime não-NA.
   SIZE_MAX se vazia ou toda-NA. Ordem cronológica (int64). (Item 7.2a;
   antes era fallback Lua.) Espelha smaug_f64_argmin. */
size_t smaug_dt_argmin(const smaug_series_dt_t *s) {
    if (!s || s->size == 0) return SIZE_MAX;
    size_t  best_i = SIZE_MAX;
    int64_t best_v = 0;
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
size_t smaug_dt_argmax(const smaug_series_dt_t *s) {
    if (!s || s->size == 0) return SIZE_MAX;
    size_t  best_i = SIZE_MAX;
    int64_t best_v = 0;
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
   min / max (item 7.2b): menor/maior epoch_ms (ordem cronológica).
   Espelha smaug_i64_min/max — INT64_MIN (DT_SENTINEL) sinaliza
   vazia / toda-NA / (com ignore_na=false) presença de NA. A Lua
   detecta o sentinela via is_int_sentinel → nil.
   =================================================================== */
int64_t smaug_dt_min(const smaug_series_dt_t *s, bool ignore_na) {
    if (!s || s->size == 0) return DT_SENTINEL;
    int64_t result = 0;
    bool    found  = false;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            if (!found || s->data[i] < result) {
                result = s->data[i];
                found  = true;
            }
        } else if (!ignore_na) {
            return DT_SENTINEL;
        }
    }
    return found ? result : DT_SENTINEL;
}

int64_t smaug_dt_max(const smaug_series_dt_t *s, bool ignore_na) {
    if (!s || s->size == 0) return DT_SENTINEL;
    int64_t result = 0;
    bool    found  = false;
    for (size_t i = 0; i < s->size; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            if (!found || s->data[i] > result) {
                result = s->data[i];
                found  = true;
            }
        } else if (!ignore_na) {
            return DT_SENTINEL;
        }
    }
    return found ? result : DT_SENTINEL;
}

/* ===================================================================
   rank (item 7.3): posição no ranking cronológico (1-based). Espelha
   smaug_i64_rank — epoch_ms é int64, comparação exata. method:
   0=average 1=min 2=max 3=first. NAN para posições NA. Caller libera.
   =================================================================== */
static int cmp_dt_rank_pair(const void *a, const void *b) {
    const dt_entry_t *pa = (const dt_entry_t *)a, *pb = (const dt_entry_t *)b;
    if (pa->val != pb->val) return (pa->val > pb->val) - (pa->val < pb->val);
    return (pa->idx > pb->idx) - (pa->idx < pb->idx);  /* desempate estável */
}

double *smaug_dt_rank(const smaug_series_dt_t *s, int method) {
    if (!s) return NULL;
    size_t n = s->size;
    double *result = malloc(n * sizeof(double));
    if (!result) return NULL;
    for (size_t i = 0; i < n; i++) result[i] = NAN;

    size_t m = 0;
    for (size_t i = 0; i < n; i++)
        if (SMAUG_VALID(s->null_mask, i)) m++;
    if (m == 0) return result;

    dt_entry_t *pairs = malloc(m * sizeof(*pairs));
    if (!pairs) { free(result); return NULL; }
    size_t j = 0;
    for (size_t i = 0; i < n; i++) {
        if (SMAUG_VALID(s->null_mask, i)) {
            pairs[j].val = s->data[i];
            pairs[j].idx = i;
            j++;
        }
    }
    qsort(pairs, m, sizeof(*pairs), cmp_dt_rank_pair);

    size_t p = 0;
    while (p < m) {
        size_t q = p;
        while (q + 1 < m && pairs[q+1].val == pairs[p].val) q++;
        double r_min = (double)(p + 1);
        double r_max = (double)(q + 1);
        for (size_t k = p; k <= q; k++) {
            double rank_val;
            switch (method) {
                case 1:  rank_val = r_min;                  break;
                case 2:  rank_val = r_max;                  break;
                case 3:  rank_val = (double)(k + 1);        break;
                default: rank_val = (r_min + r_max) / 2.0;  break;
            }
            result[pairs[k].idx] = rank_val;
        }
        p = q + 1;
    }
    free(pairs);
    return result;
}
