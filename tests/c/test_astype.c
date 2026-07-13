#include "../include/smaug.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* OK nao depende de assert(): permanece ativo sob -DNDEBUG. */
static int n_checks = 0;
#define OK(cond, msg) do { if (!(cond)) { \
    fprintf(stderr, "FALHOU: %s\n", msg); exit(1); } n_checks++; } while (0)

/* 2^53 + 1: primeiro inteiro que double NAO representa. E o coracao do
   bug do 10.7 — o round-trip por get()/double do oraculo o corrompe para
   9007199254740992. As copias diretas em C devem preserva-lo exato. */
#define TWO53_PLUS_1  9007199254740993LL

/* ---------- Grupo A: valores normais + propagacao de null ---------- */
static void test_grupo_a_basico(void) {
    /* i64 -> f64 */
    smaug_series_i64_t *i = smaug_i64_create(3);
    smaug_i64_set(i, 0, -7); smaug_i64_set(i, 1, 42); smaug_i64_set_null(i, 2);
    smaug_series_f64_t *f = smaug_i64_to_f64(i);
    OK(f != NULL, "i64->f64 retorna serie");
    OK(smaug_f64_get(f, 0, NULL) == -7.0, "i64->f64 [0]=-7");
    OK(smaug_f64_get(f, 1, NULL) == 42.0, "i64->f64 [1]=42");
    OK(smaug_f64_is_null(f, 2),           "i64->f64 preserva null [2]");

    /* i64 -> dt (reinterpreta epoch_ms) */
    smaug_series_dt_t *d = smaug_i64_to_dt(i);
    OK(d != NULL, "i64->dt retorna serie");
    OK(smaug_dt_get(d, 1, NULL) == 42,  "i64->dt [1]=42 epoch");
    OK(smaug_dt_is_null(d, 2),          "i64->dt preserva null [2]");

    /* dt -> f64 */
    smaug_series_f64_t *df = smaug_dt_to_f64(d);
    OK(df != NULL, "dt->f64 retorna serie");
    OK(smaug_f64_get(df, 0, NULL) == -7.0, "dt->f64 [0]=-7");
    OK(smaug_f64_is_null(df, 2),           "dt->f64 preserva null [2]");

    smaug_i64_free(i); smaug_f64_free(f); smaug_dt_free(d); smaug_f64_free(df);
}

/* ---------- Dirigido: exatidao acima de 2^53 (o conserto) ---------- */
static void test_exatidao_2e53(void) {
    /* dt -> i64: epoch_ms grande deve sair EXATO (get nativo int64);
       elemento nulo deve propagar (cobre o ramo null do SMAUG_VALID). */
    smaug_series_dt_t *d = smaug_dt_create(2);
    smaug_dt_set(d, 0, TWO53_PLUS_1);
    smaug_dt_set_null(d, 1);
    smaug_series_i64_t *i = smaug_dt_to_i64(d);
    OK(i != NULL, "dt->i64 retorna serie");
    OK(smaug_i64_get(i, 0, NULL) == TWO53_PLUS_1,
       "dt->i64 preserva 2^53+1 EXATO (nao 9007199254740992)");
    OK(smaug_i64_is_null(i, 1), "dt->i64 propaga null");

    /* i64 -> dt: ida e volta pelo mesmo valor grande, exato. */
    smaug_series_i64_t *big = smaug_i64_create(1);
    smaug_i64_set(big, 0, TWO53_PLUS_1);
    smaug_series_dt_t *dt2 = smaug_i64_to_dt(big);
    OK(smaug_dt_get(dt2, 0, NULL) == TWO53_PLUS_1,
       "i64->dt preserva 2^53+1 EXATO");

    smaug_dt_free(d); smaug_i64_free(i); smaug_i64_free(big); smaug_dt_free(dt2);
}

/* ---------- Dirigido: f64 -> i64 trunc + inconversiveis -> null ---------- */
static void test_f64_i64_edge(void) {
    smaug_series_f64_t *f = smaug_f64_create(8);
    smaug_f64_set(f, 0,  3.7);        /* -> 3  (trunc direcao zero)  */
    smaug_f64_set(f, 1, -3.7);        /* -> -3 (trunc direcao zero)  */
    smaug_f64_set(f, 2,  NAN);        /* -> null                     */
    smaug_f64_set(f, 3,  INFINITY);   /* -> null                     */
    smaug_f64_set(f, 4, -INFINITY);   /* -> null                     */
    smaug_f64_set(f, 5,  1e300);      /* -> null (fora do range i64) */
    smaug_f64_set(f, 6, -1e300);      /* -> null (fora do range i64) */
    smaug_f64_set_null(f, 7);         /* -> null (origem nula)       */

    smaug_series_i64_t *i = smaug_f64_to_i64(f);
    OK(i != NULL, "f64->i64 retorna serie");
    OK(smaug_i64_get(i, 0, NULL) ==  3, "f64->i64 3.7 -> 3");
    OK(smaug_i64_get(i, 1, NULL) == -3, "f64->i64 -3.7 -> -3");
    OK(smaug_i64_is_null(i, 2), "f64->i64 NaN -> null");
    OK(smaug_i64_is_null(i, 3), "f64->i64 +inf -> null");
    OK(smaug_i64_is_null(i, 4), "f64->i64 -inf -> null");
    OK(smaug_i64_is_null(i, 5), "f64->i64 1e300 -> null (fora do range)");
    OK(smaug_i64_is_null(i, 6), "f64->i64 -1e300 -> null (fora do range)");
    OK(smaug_i64_is_null(i, 7), "f64->i64 origem nula -> null");

    /* mesma politica no destino datetime */
    smaug_series_dt_t *d = smaug_f64_to_dt(f);
    OK(smaug_dt_get(d, 0, NULL) == 3, "f64->dt 3.7 -> 3 epoch");
    OK(smaug_dt_is_null(d, 2), "f64->dt NaN -> null");
    OK(smaug_dt_is_null(d, 5), "f64->dt 1e300 -> null (fora do range)");

    smaug_f64_free(f); smaug_i64_free(i); smaug_dt_free(d);
}

/* ---------- Contrato: self==NULL -> NULL ---------- */
static void test_guard_null(void) {
    OK(smaug_i64_to_f64(NULL) == NULL, "i64->f64 guard self==NULL");
    OK(smaug_f64_to_i64(NULL) == NULL, "f64->i64 guard self==NULL");
    OK(smaug_i64_to_dt (NULL) == NULL, "i64->dt guard self==NULL");
    OK(smaug_dt_to_i64 (NULL) == NULL, "dt->i64 guard self==NULL");
    OK(smaug_f64_to_dt (NULL) == NULL, "f64->dt guard self==NULL");
    OK(smaug_dt_to_f64 (NULL) == NULL, "dt->f64 guard self==NULL");
    OK(smaug_i64_to_str(NULL) == NULL, "i64->str guard self==NULL");
    OK(smaug_f64_to_str(NULL) == NULL, "f64->str guard self==NULL");
    OK(smaug_dt_to_str (NULL) == NULL, "dt->str guard self==NULL");
    OK(smaug_str_to_i64(NULL) == NULL,    "str->i64 guard self==NULL");
    OK(smaug_str_to_f64(NULL) == NULL,    "str->f64 guard self==NULL");
    OK(smaug_str_to_dt (NULL, 0) == NULL, "str->dt guard self==NULL");
}

/* Compara o elemento i (nao-nulo) da serie string com uma C-string exata.
   str_get devolve ponteiro nao terminado em \0 + comprimento via out_len. */
static int str_eq(const smaug_series_str_t *s, size_t i, const char *exp) {
    size_t len; const char *p = smaug_str_get(s, i, &len);
    if (!p) return 0;
    size_t el = strlen(exp);
    return len == el && memcmp(p, exp, el) == 0;
}

/* ---------- Grupo B-out: num/dt -> string ---------- */
static void test_grupo_b_out(void) {
    /* i64 -> str: %lld exato, incl. 2^53+1 (conserto) e null. */
    smaug_series_i64_t *i = smaug_i64_create(4);
    smaug_i64_set(i, 0, 42); smaug_i64_set(i, 1, -7);
    smaug_i64_set(i, 2, TWO53_PLUS_1); smaug_i64_set_null(i, 3);
    smaug_series_str_t *is = smaug_i64_to_str(i);
    OK(is != NULL, "i64->str retorna serie");
    OK(str_eq(is, 0, "42"),  "i64->str 42");
    OK(str_eq(is, 1, "-7"),  "i64->str -7");
    OK(str_eq(is, 2, "9007199254740993"),
       "i64->str 2^53+1 EXATO (nao cientifica)");
    OK(smaug_str_is_null(is, 3), "i64->str propaga null");

    /* f64 -> str: %.17g. Exatos tem forma previsivel; inexato via round-trip. */
    smaug_series_f64_t *f = smaug_f64_create(5);
    smaug_f64_set(f, 0, 0.5); smaug_f64_set(f, 1, -7.0);
    smaug_f64_set(f, 2, 100.25); smaug_f64_set(f, 3, 3.14);
    smaug_f64_set_null(f, 4);
    smaug_series_str_t *fs = smaug_f64_to_str(f);
    OK(fs != NULL, "f64->str retorna serie");
    OK(str_eq(fs, 0, "0.5"),    "f64->str 0.5");
    OK(str_eq(fs, 1, "-7"),     "f64->str -7.0 -> -7");
    OK(str_eq(fs, 2, "100.25"), "f64->str 100.25");
    /* round-trip: a string de 3.14 volta ao mesmo double */
    { size_t len; const char *p = smaug_str_get(fs, 3, &len);
      char tmp[40]; memcpy(tmp, p, len); tmp[len] = '\0';
      OK(strtod(tmp, NULL) == 3.14, "f64->str 3.14 round-trip exato"); }
    OK(smaug_str_is_null(fs, 4), "f64->str propaga null");

    /* dt -> str: ISO 8601 via dt_format (paridade por construcao). */
    smaug_series_dt_t *d = smaug_dt_create(2);
    smaug_dt_set(d, 0, 0);          /* epoch 0 = 1970-01-01T00:00:00.000Z */
    smaug_dt_set_null(d, 1);
    smaug_series_str_t *ds = smaug_dt_to_str(d);
    OK(ds != NULL, "dt->str retorna serie");
    OK(str_eq(ds, 0, "1970-01-01T00:00:00.000Z"), "dt->str epoch 0 = ISO");
    OK(smaug_str_is_null(ds, 1), "dt->str propaga null");

    /* series vazias: exercita o ramo size==0 do dimensionamento do buffer */
    smaug_series_i64_t *ei = smaug_i64_create(0);
    smaug_series_f64_t *ef = smaug_f64_create(0);
    smaug_series_dt_t  *ed = smaug_dt_create(0);
    smaug_series_str_t *eis = smaug_i64_to_str(ei);
    smaug_series_str_t *efs = smaug_f64_to_str(ef);
    smaug_series_str_t *eds = smaug_dt_to_str(ed);
    OK(eis && eis->size == 0, "i64->str serie vazia");
    OK(efs && efs->size == 0, "f64->str serie vazia");
    OK(eds && eds->size == 0, "dt->str serie vazia");
    smaug_i64_free(ei); smaug_f64_free(ef); smaug_dt_free(ed);
    smaug_str_free(eis); smaug_str_free(efs); smaug_str_free(eds);

    smaug_i64_free(i); smaug_str_free(is);
    smaug_f64_free(f); smaug_str_free(fs);
    smaug_dt_free(d);  smaug_str_free(ds);
}

/* cria uma serie string a partir de C-strings; NULL no array -> null. */
static smaug_series_str_t *mk_str(const char *const *vals, size_t n) {
    smaug_series_str_t *s = smaug_str_create(n);
    for (size_t i = 0; i < n; i++)
        if (vals[i]) smaug_str_set(s, i, vals[i], strlen(vals[i]));
    return s;
}

/* ---------- Grupo B-in: string -> num/dt (parsing rigido) ---------- */
static void test_grupo_b_in(void) {
    /* str -> i64: rigido (strtoll base 10). */
    const char *ci[] = {"42","  42","42 ","0x1A","3.7","9007199254740993","abc",NULL};
    smaug_series_str_t *si = mk_str(ci, 8);
    smaug_series_i64_t *i = smaug_str_to_i64(si);
    OK(i != NULL, "str->i64 retorna serie");
    OK(smaug_i64_get(i, 0, NULL) == 42, "str->i64 '42' -> 42");
    OK(smaug_i64_get(i, 1, NULL) == 42, "str->i64 '  42' leading ws ok");
    OK(smaug_i64_is_null(i, 2), "str->i64 '42 ' trailing ws -> null");
    OK(smaug_i64_is_null(i, 3), "str->i64 '0x1A' hex -> null");
    OK(smaug_i64_is_null(i, 4), "str->i64 '3.7' float -> null");
    OK(smaug_i64_get(i, 5, NULL) == TWO53_PLUS_1,
       "str->i64 2^53+1 EXATO (conserta o tonumber->double)");
    OK(smaug_i64_is_null(i, 6), "str->i64 'abc' -> null");
    OK(smaug_i64_is_null(i, 7), "str->i64 origem nula -> null");

    /* str -> f64: strtod (aceita hex/inf; rejeita overflow/trailing). */
    const char *cf[] = {"3.14","0x1A","1e3","inf","1e400","3.14 ","abc",NULL};
    smaug_series_str_t *sf = mk_str(cf, 8);
    smaug_series_f64_t *f = smaug_str_to_f64(sf);
    OK(f != NULL, "str->f64 retorna serie");
    OK(smaug_f64_get(f, 0, NULL) == 3.14,   "str->f64 '3.14'");
    OK(smaug_f64_get(f, 1, NULL) == 26.0,   "str->f64 '0x1A' hex -> 26 (strtod)");
    OK(smaug_f64_get(f, 2, NULL) == 1000.0, "str->f64 '1e3' -> 1000");
    OK(isinf(smaug_f64_get(f, 3, NULL)),    "str->f64 'inf' -> inf");
    OK(smaug_f64_is_null(f, 4), "str->f64 '1e400' overflow -> null");
    OK(smaug_f64_is_null(f, 5), "str->f64 '3.14 ' trailing ws -> null");
    OK(smaug_f64_is_null(f, 6), "str->f64 'abc' -> null");
    OK(smaug_f64_is_null(f, 7), "str->f64 origem nula -> null");

    /* str -> dt: ISO + falha->null + null propaga. */
    const char *cd[] = {"1970-01-01","abc",NULL};
    smaug_series_str_t *sd = mk_str(cd, 3);
    smaug_series_dt_t *d = smaug_str_to_dt(sd, 0);
    OK(d != NULL, "str->dt retorna serie");
    OK(smaug_dt_get(d, 0, NULL) == 0, "str->dt '1970-01-01' -> epoch 0");
    OK(smaug_dt_is_null(d, 1), "str->dt 'abc' -> null");
    OK(smaug_dt_is_null(d, 2), "str->dt origem nula -> null");

    /* dayfirst propagado: '01/02/2003' muda conforme o flag. */
    const char *ca[] = {"01/02/2003"};
    smaug_series_str_t *sa = mk_str(ca, 1);
    smaug_series_dt_t *d0 = smaug_str_to_dt(sa, 0);
    smaug_series_dt_t *d1 = smaug_str_to_dt(sa, 1);
    OK(smaug_dt_get(d0, 0, NULL) != smaug_dt_get(d1, 0, NULL),
       "str->dt dayfirst propagado (0 e 1 diferem)");

    smaug_str_free(si); smaug_i64_free(i);
    smaug_str_free(sf); smaug_f64_free(f);
    smaug_str_free(sd); smaug_dt_free(d);
    smaug_str_free(sa); smaug_dt_free(d0); smaug_dt_free(d1);
}

/* ---------- fonte unica de parsing (smaug_convert) — teste direto ----------
   Cobre os ramos que o astype nunca alcanca: ptr NULL (defensivo), len==0
   (string vazia), len>=64 (nao-numero), e overflow (errno). */
static void test_convert_direto(void) {
    int64_t iv; double dv;
    /* i64 — sucesso e cada ramo de rejeicao */
    OK(smaug_parse_i64("42", 2, &iv) == 1 && iv == 42, "parse_i64 '42' ok");
    OK(smaug_parse_i64(NULL, 2, &iv) == 0, "parse_i64 ptr NULL -> 0");
    OK(smaug_parse_i64("", 0, &iv) == 0,   "parse_i64 len 0 -> 0");
    { char big[80]; memset(big, '9', 79); big[79] = '\0';
      OK(smaug_parse_i64(big, 79, &iv) == 0, "parse_i64 len>=64 -> 0"); }
    OK(smaug_parse_i64("99999999999999999999", 20, &iv) == 0,
       "parse_i64 overflow (errno) -> 0");
    OK(smaug_parse_i64("42 ", 3, &iv) == 0, "parse_i64 trailing -> 0");

    /* f64 — sucesso e cada ramo de rejeicao */
    OK(smaug_parse_f64("3.14", 4, &dv) == 1 && dv == 3.14, "parse_f64 '3.14' ok");
    OK(smaug_parse_f64(NULL, 4, &dv) == 0, "parse_f64 ptr NULL -> 0");
    OK(smaug_parse_f64("", 0, &dv) == 0,   "parse_f64 len 0 -> 0");
    { char big[80]; memset(big, '9', 79); big[79] = '\0';
      OK(smaug_parse_f64(big, 79, &dv) == 0, "parse_f64 len>=64 -> 0"); }
    OK(smaug_parse_f64("1e400", 5, &dv) == 0, "parse_f64 overflow (errno) -> 0");
    OK(smaug_parse_f64("3.14 ", 5, &dv) == 0, "parse_f64 trailing -> 0");

    /* núcleos _cstr (hot-path do CSV): NULL, vazio, sucesso, trailing */
    OK(smaug_parse_i64_cstr("42", &iv) == 1 && iv == 42, "parse_i64_cstr '42'");
    OK(smaug_parse_i64_cstr(NULL, &iv) == 0, "parse_i64_cstr NULL -> 0");
    OK(smaug_parse_i64_cstr("", &iv) == 0,   "parse_i64_cstr vazio -> 0");
    OK(smaug_parse_i64_cstr("1x", &iv) == 0, "parse_i64_cstr trailing -> 0");
    OK(smaug_parse_f64_cstr("3.14", &dv) == 1 && dv == 3.14, "parse_f64_cstr '3.14'");
    OK(smaug_parse_f64_cstr(NULL, &dv) == 0, "parse_f64_cstr NULL -> 0");
    OK(smaug_parse_f64_cstr("", &dv) == 0,   "parse_f64_cstr vazio -> 0");
    OK(smaug_parse_f64_cstr("1x", &dv) == 0, "parse_f64_cstr trailing -> 0");
}

/* ---------- fonte única de formatação (smaug_fmt) — teste direto ----------
   Cobre i64, f64 finito (%.17g) e a normalização de não-finitos. */
static void test_fmt_direto(void) {
    char b[32];
    OK(smaug_fmt_i64(b, sizeof(b), 42) == 2 && strcmp(b, "42") == 0, "fmt_i64 42");
    OK(smaug_fmt_i64(b, sizeof(b), -7) == 2 && strcmp(b, "-7") == 0, "fmt_i64 -7");
    OK(smaug_fmt_i64(b, sizeof(b), TWO53_PLUS_1) == 16
       && strcmp(b, "9007199254740993") == 0, "fmt_i64 2^53+1 exato");
    OK(smaug_fmt_f64(b, sizeof(b), 1.5) == 3 && strcmp(b, "1.5") == 0, "fmt_f64 1.5");
    OK(smaug_fmt_f64(b, sizeof(b), 3.14) > 0
       && strcmp(b, "3.1400000000000001") == 0, "fmt_f64 3.14 -> %.17g");
    OK(smaug_fmt_f64(b, sizeof(b), NAN) == 3 && strcmp(b, "nan") == 0, "fmt_f64 NaN -> nan");
    OK(smaug_fmt_f64(b, sizeof(b), INFINITY) == 3 && strcmp(b, "inf") == 0, "fmt_f64 +inf -> inf");
    OK(smaug_fmt_f64(b, sizeof(b), -INFINITY) == 4 && strcmp(b, "-inf") == 0, "fmt_f64 -inf -> -inf");
}

int main(void) {
    test_convert_direto();
    test_fmt_direto();
    test_grupo_a_basico();
    test_exatidao_2e53();
    test_f64_i64_edge();
    test_grupo_b_out();
    test_grupo_b_in();
    test_guard_null();
    printf("PASS: astype Grupos A+B-out+B-in (%d checks)\n", n_checks);
    return 0;
}
