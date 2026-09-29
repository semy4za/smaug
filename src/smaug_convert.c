#if !defined(_WIN32)
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "../include/smaug_convert.h"
#include <stdlib.h>   /* malloc, free, strtod_l */
#include <string.h>   /* memcpy, memchr, strlen */
#include <errno.h>
#include <float.h>
#include <limits.h>
#include <stdbool.h>
#include <math.h>     /* isinf, isnan */
#include <stdio.h>    /* snprintf */
#include <locale.h>   /* C-locale conversion */

/* ===================================================================
   smaug_convert.c — conversao texto <-> numero. Ver o header para a
   semantica, a copia obrigatoria e a normalizacao de nao-finitos.
   =================================================================== */

/* --- PARSING (texto -> numero) --- */

static int ascii_lower(int character) {
    return (character >= 'A' && character <= 'Z') ? character + ('a' - 'A') : character;
}

static int is_dec_digit(unsigned char character) {
    return character >= (unsigned char)'0' && character <= (unsigned char)'9';
}

static int hex_digit(unsigned char character) {
    if (is_dec_digit(character)) {
        return (int)(character - (unsigned char)'0');
    }
    character = (unsigned char)ascii_lower(character);
    if (character >= (unsigned char)'a' && character <= (unsigned char)'f') {
        return (int)(character - (unsigned char)'a') + 10;
    }
    return -1;
}

static int token_equals(const char *text, size_t length, const char *literal) {
    size_t literal_length = strlen(literal);
    if (length != literal_length) {
        return 0;
    }
    for (size_t position = 0; position < length; position++) {
        if (ascii_lower((unsigned char)text[position]) !=
            ascii_lower((unsigned char)literal[position])) {
            return 0;
        }
    }
    return 1;
}

/* Avança somente por dígitos da mantissa e identifica magnitude textual não zero. */
static void scan_mantissa_digits(const char *text, size_t length, int hexadecimal,
                                size_t *position, int *nonzero) {
    while (*position < length) {
        int digit = hexadecimal ? hex_digit((unsigned char)text[*position])
            : (is_dec_digit((unsigned char)text[*position]) ? text[*position] - '0' : -1);
        if (digit < 0) {
            break;
        }
        if (digit != 0) {
            *nonzero = 1;
        }
        (*position)++;
    }
}

/* Verifica a gramática sem depender da libc. lexical_nonzero distingue zero
   textual de um valor não zero que a conversão pode reduzir a zero. */
static smaug_status_t validate_f64_lexeme(const char *text, size_t length,
                                        int *lexical_nonzero, int *special) {
    if (length == 0) {
        return SMG_ERR_SYNTAX;
    }
    size_t position = 0;
    if (text[position] == '+' || text[position] == '-') {
        position++;
    }
    if (position == length) {
        return SMG_ERR_SYNTAX;
    }
    size_t remaining = length - position;
    if (token_equals(text + position, remaining, "nan") ||
        token_equals(text + position, remaining, "inf") ||
        token_equals(text + position, remaining, "infinity")) {
        *lexical_nonzero = 0;
        *special = 1;
        return SMG_OK;
    }
    *special = 0;
    int hexadecimal = remaining >= 2 && text[position] == '0' &&
        (text[position + 1] == 'x' || text[position + 1] == 'X');
    if (hexadecimal) {
        position += 2;
    }
    int nonzero = 0;
    size_t mantissa_start = position;
    scan_mantissa_digits(text, length, hexadecimal, &position, &nonzero);
    size_t mantissa_digits = position - mantissa_start;
    if (position < length && text[position] == '.') {
        position++;
        size_t fraction_start = position;
        scan_mantissa_digits(text, length, hexadecimal, &position, &nonzero);
        mantissa_digits += position - fraction_start;
    }
    if (mantissa_digits == 0) {
        return SMG_ERR_SYNTAX;
    }
    int exponent_marker = hexadecimal ? 'p' : 'e';
    if (position < length && ascii_lower((unsigned char)text[position]) == exponent_marker) {
        position++;
        if (position < length && (text[position] == '+' || text[position] == '-')) {
            position++;
        }
        size_t exponent_start = position;
        while (position < length && is_dec_digit((unsigned char)text[position])) {
            position++;
        }
        if (position == exponent_start) {
            return SMG_ERR_SYNTAX;
        }
    }
    if (position != length) {
        return SMG_ERR_SYNTAX;
    }
    *lexical_nonzero = nonzero;
    return SMG_OK;
}

static smaug_status_t parse_i64_text(const char *text, size_t length, int64_t *output) {
    if (!text || !output) {
        return SMG_ERR_ARGUMENT;
    }
    if (length == 0) {
        return SMG_ERR_SYNTAX;
    }
    size_t position = 0;
    bool negative = false;
    if (text[position] == '+' || text[position] == '-') {
        negative = text[position] == '-';
        position++;
    }
    unsigned int base = 10;
    if (length - position >= 2 && text[position] == '0' &&
        (text[position + 1] == 'x' || text[position + 1] == 'X')) {
        base = 16;
        position += 2;
    }
    if (position == length) {
        return SMG_ERR_SYNTAX;
    }
    uint64_t magnitude = 0;
    uint64_t limit = negative ? (uint64_t)INT64_MAX + 1u : (uint64_t)INT64_MAX;
    bool overflow = false;
    while (position < length) {
        int digit = (base == 16) ? hex_digit((unsigned char)text[position])
            : (is_dec_digit((unsigned char)text[position]) ? text[position] - '0' : -1);
        if (digit < 0) {
            return SMG_ERR_SYNTAX;
        }
        /* Continue validando o sufixo após exceder a faixa, sem acumular mais.
           Sintaxe inválida tem precedência sobre overflow de um prefixo. */
        if (!overflow) {
            if (magnitude > (limit - (uint64_t)digit) / base) {
                overflow = true;
            } else {
                magnitude = magnitude * base + (uint64_t)digit;
            }
        }
        position++;
    }
    if (overflow) {
        return SMG_ERR_OVERFLOW;
    }
    if (negative) {
        if (magnitude == (uint64_t)INT64_MAX + 1u) {
            *output = INT64_MIN;
        } else {
            *output = -(int64_t)magnitude;
        }
    } else {
        *output = (int64_t)magnitude;
    }
    return SMG_OK;
}

/* strtod_l mantém o ponto decimal do core independente do locale global. */
static smaug_status_t convert_f64_c_locale(const char *text, double *value,
                                           char **end, int *saved_errno) {
#ifdef _WIN32
    _locale_t locale = _create_locale(LC_NUMERIC, "C");
    if (!locale) {
        return SMG_ERR_NOMEM;
    }
    errno = 0;
    *value = _strtod_l(text, end, locale);
    *saved_errno = errno;
    _free_locale(locale);
#else
    locale_t locale = newlocale(LC_NUMERIC_MASK, "C", (locale_t)0);
    if (!locale) {
        return SMG_ERR_NOMEM;
    }
    errno = 0;
    *value = strtod_l(text, end, locale);
    *saved_errno = errno;
    freelocale(locale);
#endif
    return SMG_OK;
}

static smaug_status_t parse_f64_terminated(const char *text, size_t length, double *output) {
    int lexical_nonzero = 0;
    int special = 0;
    smaug_status_t status = validate_f64_lexeme(text, length, &lexical_nonzero, &special);
    if (status != SMG_OK) {
        return status;
    }
    char *parse_end = NULL;
    double parsed_value = 0.0;
    int parse_errno = 0;
    status = convert_f64_c_locale(text, &parsed_value, &parse_end, &parse_errno);
    if (status != SMG_OK) {
        return status;
    }
    if (!parse_end || (size_t)(parse_end - text) != length) {
        return SMG_ERR_SYNTAX;
    }
    /* Arredondamento dirigido pode saturar overflow em +/-DBL_MAX.
       ERANGE perto de DBL_MIN também pode arredondar para normal: é sucesso. */
    if (!special && (isinf(parsed_value) ||
        (parse_errno == ERANGE && fabs(parsed_value) == DBL_MAX))) {
        return SMG_ERR_OVERFLOW;
    }
    if (!special && parsed_value == 0.0 && lexical_nonzero) {
        return SMG_ERR_UNDERFLOW;
    }
    *output = parsed_value;
    return SMG_OK;
}

smaug_status_t smaug_parse_i64_status(const char *text, size_t length, int64_t *output) {
    if (!text || !output) {
        return SMG_ERR_ARGUMENT;
    }
    if (memchr(text, '\0', length)) {
        return SMG_ERR_SYNTAX;
    }
    return parse_i64_text(text, length, output);
}

smaug_status_t smaug_parse_i64_cstr_status(const char *text, int64_t *output) {
    if (!text || !output) {
        return SMG_ERR_ARGUMENT;
    }
    return parse_i64_text(text, strlen(text), output);
}

smaug_status_t smaug_parse_f64_status(const char *text, size_t length, double *output) {
    if (!text || !output) {
        return SMG_ERR_ARGUMENT;
    }
    if (memchr(text, '\0', length)) {
        return SMG_ERR_SYNTAX;
    }
    if (length < 256) {
        char buffer[256];
        memcpy(buffer, text, length);
        buffer[length] = '\0';
        return parse_f64_terminated(buffer, length, output);
    }
    if (length == SIZE_MAX) {
        return SMG_ERR_NOMEM;
    }
    char *buffer = (char *)malloc(length + 1);
    if (!buffer) {
        return SMG_ERR_NOMEM;
    }
    memcpy(buffer, text, length);
    buffer[length] = '\0';
    smaug_status_t status = parse_f64_terminated(buffer, length, output);
    free(buffer);
    return status;
}

smaug_status_t smaug_parse_f64_cstr_status(const char *text, double *output) {
    if (!text || !output) {
        return SMG_ERR_ARGUMENT;
    }
    return parse_f64_terminated(text, strlen(text), output);
}

int smaug_parse_i64(const char *text, size_t length, int64_t *output) {
    return smaug_parse_i64_status(text, length, output) == SMG_OK;
}

int smaug_parse_f64(const char *text, size_t length, double *output) {
    return smaug_parse_f64_status(text, length, output) == SMG_OK;
}

int smaug_parse_i64_cstr(const char *text, int64_t *output) {
    return smaug_parse_i64_cstr_status(text, output) == SMG_OK;
}

int smaug_parse_f64_cstr(const char *text, double *output) {
    return smaug_parse_f64_cstr_status(text, output) == SMG_OK;
}

/* --- FORMATTING (numero -> texto) --- */

/* Publica apenas texto completo, incluindo terminador; falha preserva o destino. */
static size_t publish_formatted(char *buffer, size_t capacity, const char *text, int length) {
    if (!buffer || length <= 0 || (size_t)length >= capacity) {
        return 0;
    }
    memcpy(buffer, text, (size_t)length + 1);
    return (size_t)length;
}

size_t smaug_fmt_i64(char *buffer, size_t capacity, int64_t value) {
    char temporary[32];
    int length = snprintf(temporary, sizeof(temporary), "%lld", (long long)value);
    if (length < 0 || (size_t)length >= sizeof(temporary)) {
        return 0;
    }
    return publish_formatted(buffer, capacity, temporary, length);
}

/* Extensões de plataforma isoladas: nunca chama setlocale no core. */
static int format_f64_c_locale(char *buffer, size_t capacity, double value) {
#ifdef _WIN32
    _locale_t numeric_locale = _create_locale(LC_NUMERIC, "C");
    if (!numeric_locale) {
        return -1;
    }
    int length = _snprintf_l(buffer, capacity, "%.17g", numeric_locale, value);
    _free_locale(numeric_locale);
#else
    locale_t numeric_locale = newlocale(LC_NUMERIC_MASK, "C", (locale_t)0);
    if (!numeric_locale) {
        return -1;
    }
    locale_t previous_locale = uselocale(numeric_locale);
    if (!previous_locale) {
        freelocale(numeric_locale);
        return -1;
    }
    int length = snprintf(buffer, capacity, "%.17g", value);
    /* previous_locale veio de uselocale e continua válido: restaurá-lo não
       pode falhar sob o contrato POSIX. Não liberar o locale ainda instalado. */
    if (!uselocale(previous_locale)) {
        return -1;
    }
    freelocale(numeric_locale);
#endif
    return length;
}

size_t smaug_fmt_f64(char *buffer, size_t capacity, double value) {
    if (!buffer || capacity == 0) {
        return 0;
    }
    /* Normalização explícita evita payload/sinal NaN dependentes da libc. */
    if (isnan(value)) {
        return publish_formatted(buffer, capacity, "nan", 3);
    }
    if (isinf(value)) {
        return value < 0 ? publish_formatted(buffer, capacity, "-inf", 4)
                         : publish_formatted(buffer, capacity, "inf", 3);
    }
    char temporary[32];
    int length = format_f64_c_locale(temporary, sizeof(temporary), value);
    if (length < 0 || (size_t)length >= sizeof(temporary)) {
        return 0;
    }
    return publish_formatted(buffer, capacity, temporary, length);
}
