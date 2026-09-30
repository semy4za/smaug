#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif
/* src/smaug_json.c
 *
 * Parser e writer JSON do Smaug — Anel 3.
 * Formato suportado: array de records [ {...}, {...}, ... ]
 * Zero dependências externas.
 */

#include "../include/smaug_io.h"
#include "smaug_io_internal.h"
#include "../include/smaug_convert.h"
#include "../include/smaug_core.h"
#include "../include/smaug_string.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <float.h>
#include <limits.h>
#include <math.h>

/* ===================================================================
   Tokenizador JSON minimalista
   =================================================================== */

typedef enum {
    TOK_LBRACE, TOK_RBRACE, TOK_LBRACKET, TOK_RBRACKET,
    TOK_COLON, TOK_COMMA,
    TOK_STRING, TOK_NUMBER, TOK_TRUE, TOK_FALSE, TOK_NULL,
    TOK_EOF, TOK_ERROR
} json_tok_t;

typedef struct {
    const char *buf;
    size_t      len;
    size_t      pos;
    char       *str_val;   /* para TOK_STRING */
    size_t      str_length;
    double      num_val;   /* para TOK_NUMBER */
    int         is_int;    /* 1 se numero sem ponto/exp */
    int64_t     int_val;
    size_t      token_start;
    const char *error_reason;
} json_lex_t;

/* RFC 3629: forma mínima, sem surrogates e até U+10FFFF.
 * Retorna bytes da sequência, ou zero; nunca lê além de length. */
static size_t json_utf8_sequence_length(const char *text, size_t length) {
    if (length == 0) {
        return 0;
    }
    const unsigned char *bytes = (const unsigned char *)text;
    unsigned char first = bytes[0];
    if (first < 0x80) {
        return 1;
    }
    size_t width;
    unsigned char second_min = 0x80;
    unsigned char second_max = 0xbf;
    if (first >= 0xc2 && first <= 0xdf) {
        width = 2;
    } else if (first >= 0xe0 && first <= 0xef) {
        width = 3;
        if (first == 0xe0) {
            second_min = 0xa0;
        } else if (first == 0xed) {
            second_max = 0x9f;
        }
    } else if (first >= 0xf0 && first <= 0xf4) {
        width = 4;
        if (first == 0xf0) {
            second_min = 0x90;
        } else if (first == 0xf4) {
            second_max = 0x8f;
        }
    } else {
        return 0;
    }
    if (length < width || bytes[1] < second_min || bytes[1] > second_max) {
        return 0;
    }
    for (size_t offset = 2; offset < width; offset++) {
        if (bytes[offset] < 0x80 || bytes[offset] > 0xbf) {
            return 0;
        }
    }
    return width;
}

static int json_valid_utf8(const char *text, size_t length, size_t *error_position) {
    size_t position = 0;
    while (position < length) {
        size_t width = json_utf8_sequence_length(text + position, length - position);
        if (width == 0) {
            *error_position = position;
            return 0;
        }
        position += width;
    }
    return 1;
}

static int json_string_reserve(char **buffer, size_t *capacity, size_t used, size_t added) {
    if (used == SIZE_MAX || added > SIZE_MAX - used - 1) {
        return 0;
    }
    size_t required = used + added + 1;
    if (required <= *capacity) {
        return 1;
    }
    size_t grown = *capacity;
    while (grown < required) {
        if (grown > SIZE_MAX / 2) {
            grown = required;
            break;
        }
        grown *= 2;
    }
    char *resized = realloc(*buffer, grown);
    if (!resized) {
        return 0;
    }
    *buffer = resized;
    *capacity = grown;
    return 1;
}

static void skip_ws(json_lex_t *l) {
    while (l->pos < l->len) {
        char c = l->buf[l->pos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') l->pos++;
        else break;
    }
}

/* Lê 4 dígitos hex de l->buf[l->pos..] e devolve o codepoint (0–0xFFFF).
   Avança l->pos em 4. Retorna -1 se os 4 caracteres não forem hex válidos. */
static int read_hex4(json_lex_t *l) {
    if (l->len - l->pos < 4) return -1;
    unsigned int cp = 0;
    for (int i = 0; i < 4; i++) {
        unsigned char h = (unsigned char)l->buf[l->pos + i];
        unsigned int digit;
        if      (h >= '0' && h <= '9') digit = h - '0';
        else if (h >= 'a' && h <= 'f') digit = h - 'a' + 10;
        else if (h >= 'A' && h <= 'F') digit = h - 'A' + 10;
        else return -1;
        cp = (cp << 4) | digit;
    }
    l->pos += 4;
    return (int)cp;
}

/* Codifica codepoint Unicode (U+0000–U+10FFFF, exceto surrogates) em UTF-8.
   Escreve 1–4 bytes em dst. Retorna o número de bytes escritos, ou 0 em erro. */
static int encode_utf8(unsigned int cp, char *dst) {
    if (cp <= 0x7F) {
        dst[0] = (char)cp;
        return 1;
    } else if (cp <= 0x7FF) {
        dst[0] = (char)(0xC0 | (cp >> 6));
        dst[1] = (char)(0x80 | (cp & 0x3F));
        return 2;
    } else if (cp <= 0xFFFF) {
        dst[0] = (char)(0xE0 | (cp >> 12));
        dst[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        dst[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    } else if (cp <= 0x10FFFF) {
        dst[0] = (char)(0xF0 | (cp >> 18));
        dst[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
        dst[2] = (char)(0x80 | ((cp >> 6)  & 0x3F));
        dst[3] = (char)(0x80 | (cp & 0x3F));
        return 4;
    }
    return 0; /* codepoint inválido */
}

/* Lê string JSON (com escape). Retorna malloc'd string ou NULL em erro.
 *
 * Escapes suportados: \" \\ \/ \n \r \t \b \f
 * Escapes Unicode: \uXXXX decodificado para UTF-8.
 *   - BMP (U+0000–U+FFFF, exceto surrogates): decodificado diretamente.
 *   - Pares surrogate (\uD800–\uDBFF seguido de \uDC00–\uDFFF): decodificados
 *     para o codepoint suplementar correspondente (U+10000–U+10FFFF).
 *   - Surrogate isolado ou par inválido: erro (retorna NULL → TOK_ERROR).
 * Hex inválido em \uXXXX: erro (retorna NULL → TOK_ERROR).
 */
static char *read_json_string(json_lex_t *l) {
    if (l->pos >= l->len || l->buf[l->pos] != '"') return NULL;
    l->pos++;
    size_t cap = 64; char *out = malloc(cap); size_t n = 0;
    if (!out) {
        l->error_reason = "NOMEM ao criar string JSON";
        return NULL;
    }

    while (l->pos < l->len) {
        char c = l->buf[l->pos++];
        if (c == '"') { out[n] = '\0'; l->str_length = n; return out; }
        if ((unsigned char)c < 0x20) {
            l->error_reason = "controle literal em string JSON";
            free(out);
            return NULL;
        }
        if ((unsigned char)c >= 0x80) {
            size_t start = l->pos - 1;
            size_t width = json_utf8_sequence_length(l->buf + start, l->len - start);
            if (width == 0) {
                l->token_start = start;
                l->error_reason = "UTF-8 inválido em string JSON";
                free(out);
                return NULL;
            }
            if (!json_string_reserve(&out, &cap, n, width)) {
                l->error_reason = "NOMEM ao ampliar string JSON";
                free(out);
                return NULL;
            }
            memcpy(out + n, l->buf + start, width);
            n += width;
            l->pos = start + width;
            continue;
        }
        if (c == '\\') {
            if (l->pos >= l->len) break; /* COV-EXCL-BR: string não fechada — break inalcançável em JSON bem-formado */
            char esc = l->buf[l->pos++];
            if (esc == 'u') {
                /* Decodifica \uXXXX para UTF-8. */
                int cp = read_hex4(l);
                if (cp < 0) { free(out); return NULL; }   /* hex inválido */

                unsigned int ucp = (unsigned int)cp;

                if (ucp >= 0xD800 && ucp <= 0xDBFF) {
                    /* High surrogate: esperado \uDC00–\uDFFF a seguir. */
                    if (l->len - l->pos < 6 ||
                        l->buf[l->pos] != '\\' || l->buf[l->pos+1] != 'u') {
                        free(out); return NULL;   /* surrogate isolado */
                    }
                    l->pos += 2;   /* consume \u */
                    int cp2 = read_hex4(l);
                    if (cp2 < 0) { free(out); return NULL; }
                    unsigned int ucp2 = (unsigned int)cp2;
                    if (ucp2 < 0xDC00 || ucp2 > 0xDFFF) {
                        free(out); return NULL;   /* par inválido */
                    }
                    ucp = 0x10000 + ((ucp - 0xD800) << 10) + (ucp2 - 0xDC00);
                } else if (ucp >= 0xDC00 && ucp <= 0xDFFF) {
                    free(out); return NULL;   /* low surrogate isolado */
                }

                char utf8[4];
                int bytes = encode_utf8(ucp, utf8);
                if (bytes == 0) { free(out); return NULL; }

                if (!json_string_reserve(&out, &cap, n, (size_t)bytes)) {
                    l->error_reason = "NOMEM ao ampliar string JSON";
                    free(out);
                    return NULL;
                }
                memcpy(out + n, utf8, (size_t)bytes);
                n += (size_t)bytes;
                continue;
            }
            /* escapes de 1 caractere */
            char mapped;
            switch (esc) {
                case '"': case '\\': case '/': mapped = esc; break;
                case 'n': mapped = '\n'; break;
                case 'r': mapped = '\r'; break;
                case 't': mapped = '\t'; break;
                case 'b': mapped = '\b'; break;
                case 'f': mapped = '\f'; break;
                default: free(out); return NULL;
            }
            c = mapped;
        }
        if (!json_string_reserve(&out, &cap, n, 1)) {
            l->error_reason = "NOMEM ao ampliar string JSON";
            free(out);
            return NULL;
        }
        out[n++] = c;
    }
    free(out); return NULL;  /* string não fechada */
}

static int json_digit(char character) {
    return character >= '0' && character <= '9';
}

static json_tok_t read_json_number(json_lex_t *lexer) {
    size_t start = lexer->pos;
    lexer->is_int = 1;
    if (lexer->buf[lexer->pos] == '-') {
        lexer->pos++;
    }
    if (lexer->pos == lexer->len || !json_digit(lexer->buf[lexer->pos])) {
        goto syntax_error;
    }
    if (lexer->buf[lexer->pos] == '0') {
        lexer->pos++;
    } else {
        while (lexer->pos < lexer->len && json_digit(lexer->buf[lexer->pos])) {
            lexer->pos++;
        }
    }
    if (lexer->pos < lexer->len && lexer->buf[lexer->pos] == '.') {
        lexer->is_int = 0;
        lexer->pos++;
        size_t digits_start = lexer->pos;
        while (lexer->pos < lexer->len && json_digit(lexer->buf[lexer->pos])) {
            lexer->pos++;
        }
        if (lexer->pos == digits_start) {
            goto syntax_error;
        }
    }
    if (lexer->pos < lexer->len &&
        (lexer->buf[lexer->pos] == 'e' || lexer->buf[lexer->pos] == 'E')) {
        lexer->is_int = 0;
        lexer->pos++;
        if (lexer->pos < lexer->len &&
            (lexer->buf[lexer->pos] == '+' || lexer->buf[lexer->pos] == '-')) {
            lexer->pos++;
        }
        size_t digits_start = lexer->pos;
        while (lexer->pos < lexer->len && json_digit(lexer->buf[lexer->pos])) {
            lexer->pos++;
        }
        if (lexer->pos == digits_start) {
            goto syntax_error;
        }
    }
    if (lexer->pos < lexer->len) {
        char boundary = lexer->buf[lexer->pos];
        if (boundary != ',' && boundary != '}' && boundary != ']' &&
            boundary != ' ' && boundary != '\t' && boundary != '\n' && boundary != '\r') {
            goto syntax_error;
        }
    }
    size_t length = lexer->pos - start;
    smaug_status_t status = lexer->is_int
        ? smaug_parse_i64_status(lexer->buf + start, length, &lexer->int_val)
        : smaug_parse_f64_status(lexer->buf + start, length, &lexer->num_val);
    switch (status) {
        case SMG_OK: return TOK_NUMBER;
        case SMG_ERR_OVERFLOW: lexer->error_reason = "OVERFLOW numérico"; break;
        case SMG_ERR_UNDERFLOW: lexer->error_reason = "UNDERFLOW numérico para zero"; break;
        case SMG_ERR_NOMEM: lexer->error_reason = "NOMEM na conversão numérica"; break;
        case SMG_ERR_ARGUMENT: lexer->error_reason = "ARGUMENT na conversão numérica"; break;
        default: lexer->error_reason = "SYNTAX numérica"; break;
    }
    return TOK_ERROR;

syntax_error:
    lexer->error_reason = "SYNTAX numérica JSON";
    return TOK_ERROR;
}

static json_tok_t next_token(json_lex_t *l) {
    free(l->str_val); l->str_val = NULL;
    skip_ws(l);
    l->token_start = l->pos;
    if (l->pos >= l->len) return TOK_EOF;

    char c = l->buf[l->pos];
    switch (c) {
        case '{': l->pos++; return TOK_LBRACE;
        case '}': l->pos++; return TOK_RBRACE;
        case '[': l->pos++; return TOK_LBRACKET;
        case ']': l->pos++; return TOK_RBRACKET;
        case ':': l->pos++; return TOK_COLON;
        case ',': l->pos++; return TOK_COMMA;
        case '"':
            l->str_val = read_json_string(l);
            return l->str_val ? TOK_STRING : TOK_ERROR;
        case 't':
            if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"true",4)==0)
                { l->pos+=4; return TOK_TRUE; }
            return TOK_ERROR;
        case 'f':
            if (l->pos + 5 <= l->len && strncmp(l->buf+l->pos,"false",5)==0)
                { l->pos+=5; return TOK_FALSE; }
            return TOK_ERROR;
        case 'n':
            if (l->pos + 4 <= l->len && strncmp(l->buf+l->pos,"null",4)==0)
                { l->pos+=4; return TOK_NULL; }
            return TOK_ERROR;
        default:
            if (c == '-' || (c >= '0' && c <= '9')) {
                return read_json_number(l);
            }
            return TOK_ERROR;
    }
}

/* ===================================================================
   Parser de array de records
   =================================================================== */

/* Valor de uma célula na leitura */
typedef struct {
    int     type;   /* 0=null, 1=int64, 2=float64, 3=bool, 4=string */
    int64_t i;
    double  d;
    uint8_t b;
    char   *s;
    size_t string_length;
    size_t key_length;
    size_t source_position;
    size_t column_index;
} json_val_t;

/* Remove fatores da base antes de contar os dígitos significativos. */
static int json_integer_exact_in_double(int64_t value) {
    uint64_t magnitude = value < 0 ? UINT64_C(0) - (uint64_t)value : (uint64_t)value;
    if (magnitude == 0) {
        return 1;
    }
    while (magnitude % FLT_RADIX == 0) {
        magnitude /= FLT_RADIX;
    }
    int digits = 0;
    while (magnitude != 0) {
        magnitude /= FLT_RADIX;
        digits++;
    }
    return digits <= DBL_MANT_DIG;
}

/* Um record (linha) */
typedef struct {
    char       **keys;
    json_val_t  *vals;
    size_t       count;
} json_record_t;

static void free_record(json_record_t *r) {
    for (size_t i = 0; i < r->count; i++) {
        free(r->keys[i]);
        if (r->vals[i].type == 4) free(r->vals[i].s);
    }
    free(r->keys); free(r->vals);
}

static int parse_value(json_lex_t *lexer, json_val_t *value, json_tok_t token) {
    value->source_position = lexer->token_start;
    switch (token) {
        case TOK_NULL:
            value->type = 0;
            return 1;
        case TOK_TRUE:
        case TOK_FALSE:
            value->type = 3;
            value->b = token == TOK_TRUE;
            return 1;
        case TOK_NUMBER:
            if (lexer->is_int) {
                value->type = 1;
                value->i = lexer->int_val;
            } else {
                value->type = 2;
                value->d = lexer->num_val;
            }
            return 1;
        case TOK_STRING:
            value->type = 4;
            value->s = lexer->str_val;
            value->string_length = lexer->str_length;
            lexer->str_val = NULL;
            return 1;
        default:
            return 0;
    }
}

static int parse_record(json_lex_t *lexer, json_record_t *record) {
    /* A abertura já foi consumida; o caller limpa o registro parcial em falha. */
    size_t capacity = 8;
    record->keys = malloc(capacity * sizeof(char *));
    record->vals = malloc(capacity * sizeof(json_val_t));
    record->count = 0;
    if (!record->keys || !record->vals) {
        lexer->error_reason = "OOM ao alocar objeto";
        return 0;
    }
    json_tok_t token = next_token(lexer);
    if (token == TOK_RBRACE) {
        return 1;
    }
    while (1) {
        if (token != TOK_STRING) {
            if (!lexer->error_reason) {
                lexer->error_reason = "esperada chave string no objeto";
            }
            return 0;
        }
        char *key = lexer->str_val;
        size_t key_length = lexer->str_length;
        lexer->str_val = NULL;
        if (next_token(lexer) != TOK_COLON) {
            free(key);
            if (!lexer->error_reason) {
                lexer->error_reason = "esperado ':' após chave";
            }
            return 0;
        }
        json_tok_t value_token = next_token(lexer);
        json_val_t value = {.key_length = key_length};
        if (!parse_value(lexer, &value, value_token)) {
            free(key);
            if (!lexer->error_reason) {
                lexer->error_reason = "esperado valor escalar";
            }
            return 0;
        }
        if (record->count == capacity) {
            if (capacity > SIZE_MAX / sizeof(char *) / 2 ||
                capacity > SIZE_MAX / sizeof(json_val_t) / 2) {
                goto allocation_failure;
            }
            capacity *= 2;
            char **resized_keys = realloc(record->keys, capacity * sizeof(char *));
            if (!resized_keys) {
                goto allocation_failure;
            }
            record->keys = resized_keys;
            json_val_t *resized_values = realloc(record->vals, capacity * sizeof(json_val_t));
            if (!resized_values) {
                goto allocation_failure;
            }
            record->vals = resized_values;
        }
        record->keys[record->count] = key;
        record->vals[record->count] = value;
        record->count++;
        token = next_token(lexer);
        if (token == TOK_RBRACE) {
            return 1;
        }
        if (token != TOK_COMMA) {
            if (!lexer->error_reason) {
                lexer->error_reason = "esperado ',' ou '}' após valor";
            }
            return 0;
        }
        token = next_token(lexer);
        continue;
allocation_failure:
        free(key);
        if (value.type == 4) {
            free(value.s);
        }
        lexer->error_reason = "OOM ao ampliar objeto";
        return 0;
    }
}

/* Diagnóstico local ao lexer; byte base 0, sem estado global mutável. */
static smaug_table_t *json_parse_error(const json_lex_t *lexer, const char *fallback) {
    char message[192];
    const char *reason = lexer->error_reason ? lexer->error_reason : fallback;
    int length = snprintf(message, sizeof(message), "JSON byte %zu: %s",
                          lexer->token_start, reason);
    if (length < 0 || (size_t)length >= sizeof(message)) {
        return make_error("JSON: falha ao construir diagnóstico");
    }
    return make_error(message);
}

static void free_json_records(json_record_t *records, size_t count) {
    for (size_t record_index = 0; record_index < count; record_index++) {
        free_record(&records[record_index]);
    }
    free(records);
}

/* Documento completo: delimitadores obrigatórios, sem vírgula final ou sufixo. */
static int read_json_records(json_lex_t *lexer, json_record_t **output, size_t *output_count) {
    json_record_t *records = NULL;
    size_t count = 0;
    size_t capacity = 0;
    if (next_token(lexer) != TOK_LBRACKET) {
        if (!lexer->error_reason) {
            lexer->error_reason = "esperado array '[' no topo";
        }
        goto failure;
    }
    json_tok_t token = next_token(lexer);
    if (token != TOK_RBRACKET) {
        while (1) {
            if (token != TOK_LBRACE) {
                if (!lexer->error_reason) {
                    lexer->error_reason = "esperado objeto '{' no array";
                }
                goto failure;
            }
            if (count == capacity) {
                if (capacity > SIZE_MAX / sizeof(json_record_t) / 2) {
                    lexer->error_reason = "OOM ao ampliar registros";
                    goto failure;
                }
                size_t new_capacity = capacity ? capacity * 2 : 64;
                json_record_t *resized = realloc(records, new_capacity * sizeof(json_record_t));
                if (!resized) {
                    lexer->error_reason = "OOM ao alocar registros";
                    goto failure;
                }
                records = resized;
                capacity = new_capacity;
            }
            records[count] = (json_record_t){0};
            if (!parse_record(lexer, &records[count])) {
                free_record(&records[count]);
                if (!lexer->error_reason) {
                    lexer->error_reason = "objeto inválido: esperado chave, ':' ou separador";
                }
                goto failure;
            }
            count++;
            token = next_token(lexer);
            if (token == TOK_RBRACKET) {
                break;
            }
            if (token != TOK_COMMA) {
                if (!lexer->error_reason) {
                    lexer->error_reason = "esperado ',' ou ']' após objeto";
                }
                goto failure;
            }
            token = next_token(lexer);
        }
    }
    if (next_token(lexer) != TOK_EOF) {
        if (!lexer->error_reason) {
            lexer->error_reason = "conteúdo após fechamento do array";
        }
        goto failure;
    }
    *output = records;
    *output_count = count;
    return 1;
failure:
    free_json_records(records, count);
    return 0;
}

/* Identidade: nome original + ordinal da ocorrência dentro do objeto.
 * O nome publicado é único, mas nunca participa da associação de entrada. */
typedef struct {
    const char *key;
    size_t key_length;
    size_t occurrence;
} json_column_identity_t;

static int json_column_name_used(smaug_io_text_t *names, size_t count,
                                 const char *candidate, size_t length) {
    for (size_t column = 0; column < count; column++) {
        if (io_bytes_equal(names[column].data, names[column].length, candidate, length)) {
            return 1;
        }
    }
    return 0;
}

static char *json_unique_column_name(const char *key, size_t length,
                                     smaug_io_text_t *names, size_t count,
                                     size_t *output_length) {
    if (!json_column_name_used(names, count, key, length)) {
        *output_length = length;
        return io_copy_bytes(key, length);
    }
    size_t extra = sizeof(size_t) * CHAR_BIT + 2;
    if (length > SIZE_MAX - extra) {
        return NULL;
    }
    char *candidate = malloc(length + extra);
    if (!candidate) {
        return NULL;
    }
    memcpy(candidate, key, length);
    for (size_t suffix = 1; suffix != 0; suffix++) {
        int written = snprintf(candidate + length, extra, ".%zu", suffix);
        if (written < 0 || (size_t)written >= extra) {
            break;
        }
        size_t candidate_length = length + (size_t)written;
        if (!json_column_name_used(names, count, candidate, candidate_length)) {
            *output_length = candidate_length;
            return candidate;
        }
    }
    free(candidate);
    return NULL;
}

static int json_resolve_columns(json_record_t *records, size_t row_count,
                                smaug_io_text_t **output_names, size_t *output_count) {
    size_t capacity = 0;
    for (size_t row = 0; row < row_count; row++) {
        if (records[row].count > SIZE_MAX - capacity) {
            return 0;
        }
        capacity += records[row].count;
    }
    if (capacity == 0) {
        *output_names = NULL;
        *output_count = 0;
        return 1;
    }
    if (capacity > SIZE_MAX / sizeof(smaug_io_text_t) ||
        capacity > SIZE_MAX / sizeof(json_column_identity_t)) {
        return 0;
    }
    smaug_io_text_t *names = calloc(capacity, sizeof(*names));
    json_column_identity_t *identities = malloc(capacity * sizeof(*identities));
    if (!names || !identities) {
        free(names);
        free(identities);
        return 0;
    }
    size_t count = 0;
    for (size_t row = 0; row < row_count; row++) {
        json_record_t *record = &records[row];
        for (size_t field = 0; field < record->count; field++) {
            size_t occurrence = 0;
            for (size_t previous = 0; previous < field; previous++) {
                if (io_bytes_equal(record->keys[previous], record->vals[previous].key_length,
                                   record->keys[field], record->vals[field].key_length)) {
                    occurrence++;
                }
            }
            size_t column = 0;
            while (column < count) {
                if (identities[column].occurrence == occurrence &&
                    io_bytes_equal(identities[column].key, identities[column].key_length,
                                   record->keys[field], record->vals[field].key_length)) {
                    break;
                }
                column++;
            }
            if (column == count) {
                names[count].data = json_unique_column_name(record->keys[field],
                    record->vals[field].key_length, names, count, &names[count].length);
                if (!names[count].data) {
                    for (size_t owned = 0; owned < count; owned++) {
                        free(names[owned].data);
                    }
                    free(names);
                    free(identities);
                    return 0;
                }
                identities[count].key = record->keys[field];
                identities[count].key_length = record->vals[field].key_length;
                identities[count].occurrence = occurrence;
                count++;
            }
            record->vals[field].column_index = column;
        }
    }
    free(identities);
    *output_names = names;
    *output_count = count;
    return 1;
}

static json_val_t *json_record_column(json_record_t *record, size_t column) {
    for (size_t field = 0; field < record->count; field++) {
        if (record->vals[field].column_index == column) {
            return &record->vals[field];
        }
    }
    return NULL;
}

static smaug_status_t json_schema_set_value(smaug_column_t *column, size_t row,
    smaug_dtype_t dtype, const json_val_t *value, const char **reason) {
    *reason = "value family differs from schema";
    switch (dtype) {
        case SMAUG_DTYPE_BOOL:
            if (value->type == 3) {
                return smaug_bool_set(column->boolcol, row, value->b);
            }
            break;
        case SMAUG_DTYPE_INT64:
            if (value->type == 1) {
                return smaug_i64_set(column->i64, row, value->i);
            }
            break;
        case SMAUG_DTYPE_FLOAT64:
            if (value->type == 1) {
                if (!json_integer_exact_in_double(value->i)) {
                    *reason = "PRECISION: integer is not exactly representable as float64";
                    return SMG_ERR_OVERFLOW;
                }
                return smaug_f64_set(column->f64, row, (double)value->i);
            }
            if (value->type == 2) {
                return smaug_f64_set(column->f64, row, value->d);
            }
            break;
        case SMAUG_DTYPE_STRING:
            if (value->type == 4) {
                smaug_status_t status = smaug_str_set(column->str, row,
                                                     value->s, value->string_length);
                *reason = smaug_io_status_reason(status);
                return status;
            }
            break;
        default: break;
    }
    return SMG_ERR_SYNTAX;
}

static smaug_table_t *json_schema_records(json_record_t *records, size_t row_count,
    const smaug_schema_t *schema) {
    smaug_table_t *table = smaug_io_schema_table(schema, row_count);
    if (!table) {
        return NULL;
    }
    for (size_t row = 0; row < row_count; row++) {
        json_record_t *record = &records[row];
        for (size_t source = 0; source < record->count; source++) {
            json_val_t *value = &record->vals[source];
            size_t field = smaug_io_schema_find(schema, record->keys[source], value->key_length);
            const char *reason = NULL;
            if (field == SIZE_MAX) {
                reason = "unknown field";
            } else {
                for (size_t previous = 0; previous < source; previous++) {
                    if (record->vals[previous].column_index == field) {
                        reason = "duplicate field";
                        break;
                    }
                }
            }
            if (reason) {
                smaug_table_free(table);
                return smaug_io_schema_error("JSON", schema, row, field,
                                             value->source_position, reason);
            }
            value->column_index = field;
        }
        for (size_t field = 0; field < schema->count; field++) {
            const smaug_schema_field_t *descriptor = &schema->fields[field];
            json_val_t *value = json_record_column(record, field);
            const char *reason = NULL;
            smaug_status_t status;
            if (!value || value->type == 0) {
                if (!descriptor->nullable) {
                    status = SMG_ERR_ARGUMENT;
                    reason = "missing/null value in non-nullable field";
                } else {
                    status = smaug_io_schema_set_null(&table->columns[field], row);
                }
            } else {
                status = json_schema_set_value(&table->columns[field], row,
                                                descriptor->dtype, value, &reason);
            }
            if (status != SMG_OK) {
                smaug_table_free(table);
                return smaug_io_schema_error("JSON", schema, row, field,
                    value ? value->source_position : SIZE_MAX,
                    reason ? reason : smaug_io_status_reason(status));
            }
        }
    }
    return table;
}

static const char *json_schema_validate(const smaug_schema_t *schema,
    size_t *field_index, size_t *byte_index) {
    size_t error_field;
    if (smaug_schema_validate(schema, &error_field) != SMG_OK) {
        *field_index = error_field;
        *byte_index = SIZE_MAX;
        return "invalid schema descriptor";
    }
    for (size_t field = 0; field < schema->count; field++) {
        size_t error_byte;
        if (!json_valid_utf8(schema->fields[field].name, schema->fields[field].name_len,
                             &error_byte)) {
            *field_index = field;
            *byte_index = error_byte;
            return "invalid UTF-8 in schema name";
        }
    }
    return NULL;
}

smaug_table_t *smaug_read_json_mem_schema(const char *buffer, size_t length,
    const smaug_schema_t *schema) {
    size_t field_index;
    size_t byte_index;
    const char *validation_error = json_schema_validate(schema, &field_index, &byte_index);
    if (validation_error) {
        return smaug_io_schema_error("JSON", schema, SIZE_MAX, field_index, byte_index,
                                     validation_error);
    }
    if (!buffer && length) {
        return make_error("JSON: NULL buffer with nonzero length");
    }
    size_t position = 0;
    if (length >= 3 && (unsigned char)buffer[0] == 0xef &&
        (unsigned char)buffer[1] == 0xbb && (unsigned char)buffer[2] == 0xbf) {
        position = 3;
    }
    json_lex_t lexer = {.buf = buffer, .len = length, .pos = position};
    json_record_t *records = NULL;
    size_t row_count = 0;
    int success = read_json_records(&lexer, &records, &row_count);
    free(lexer.str_val);
    if (!success) {
        return json_parse_error(&lexer, "invalid document");
    }
    smaug_table_t *table = json_schema_records(records, row_count, schema);
    free_json_records(records, row_count);
    return table;
}

smaug_table_t *smaug_read_json_schema(const char *path, const smaug_schema_t *schema) {
    size_t field_index;
    size_t byte_index;
    const char *validation_error = json_schema_validate(schema, &field_index, &byte_index);
    if (validation_error) {
        return smaug_io_schema_error("JSON", schema, SIZE_MAX, field_index, byte_index,
                                     validation_error);
    }
    char *buffer;
    size_t length;
    const char *reason;
    if (smaug_io_read_bytes(path, &buffer, &length, &reason) != SMG_OK) {
        return make_error(reason);
    }
    smaug_table_t *table = smaug_read_json_mem_schema(buffer, length, schema);
    free(buffer);
    return table;
}

smaug_table_t *smaug_read_json_mem(const char *buf, size_t len) {
    if (!buf && len > 0) {
        return NULL;
    }
    size_t initial_position = 0;
    if (len >= 3 && (unsigned char)buf[0] == 0xef &&
        (unsigned char)buf[1] == 0xbb && (unsigned char)buf[2] == 0xbf) {
        /* RFC 8259: aceitar um BOM inicial para interoperabilidade, mas nunca
           tratá-lo como conteúdo JSON. U+FEFF dentro de uma string permanece
           um valor normal e não passa por este caminho. */
        initial_position = 3;
    }
    json_lex_t lexer = {.buf = buf, .len = len, .pos = initial_position};
    json_record_t *recs = NULL;
    size_t n_recs = 0;
    int success = read_json_records(&lexer, &recs, &n_recs);
    free(lexer.str_val);
    if (!success) {
        return json_parse_error(&lexer, "documento inválido");
    }
    if (n_recs == 0) {
        free(recs);
        smaug_table_t *empty = calloc(1, sizeof(smaug_table_t));
        return empty ? empty : make_error("OOM");
    }
    smaug_io_text_t *col_names = NULL;
    int *dtypes = NULL;
    size_t n_cols_io = 0;

    size_t n_cols = 0;
    if (!json_resolve_columns(recs, n_recs, &col_names, &n_cols)) {
        goto oom_recs;
    }
    n_cols_io = n_cols;
    if (n_cols == 0) {
        smaug_table_t *empty = calloc(1, sizeof(*empty));
        if (empty) {
            empty->nrows = n_recs;
        }
        free_json_records(recs, n_recs);
        return empty ? empty : make_error("OOM");
    }

    /* inferir dtypes */
    dtypes = calloc(n_cols, sizeof(int));
    if (!dtypes) {
        for (size_t c = 0; c < n_cols; c++) free(col_names[c].data);
        free(col_names); col_names = NULL;
        goto oom_recs;
    }

    for (size_t r = 0; r < n_recs; r++) {
        for (size_t field = 0; field < recs[r].count; field++) {
            size_t c = recs[r].vals[field].column_index;
            int jt = recs[r].vals[field].type;
            int cand;
            switch (jt) {
                case 0: continue;          /* null: não vota */
                case 1: cand = DT_I64;  break;
                case 2: cand = DT_F64;  break;
                case 3: cand = DT_BOOL; break;
                default: cand = DT_STR; break;
            }
            dtypes[c] = dtype_upgrade(dtypes[c], cand);
        }
    }
    for (size_t c = 0; c < n_cols; c++)
        if (dtypes[c] == DT_UNKNOWN) dtypes[c] = DT_STR;

    /* A inferência completa pode terminar em string; só validar promoção numérica. */
    for (size_t row = 0; row < n_recs; row++) {
        for (size_t field = 0; field < recs[row].count; field++) {
            const json_val_t *value = &recs[row].vals[field];
            size_t column = value->column_index;
            if (dtypes[column] == DT_F64 && value->type == 1 &&
                !json_integer_exact_in_double(value->i)) {
                lexer.token_start = value->source_position;
                lexer.error_reason = "PRECISION: inteiro inexato em coluna float64";
                for (size_t name = 0; name < n_cols; name++) {
                    free(col_names[name].data);
                }
                free(col_names);
                free(dtypes);
                free_json_records(recs, n_recs);
                return json_parse_error(&lexer, "promoção inexata");
            }
        }
    }

    /* construir tabela */
    smaug_table_t *tbl = calloc(1, sizeof(smaug_table_t));
    if (!tbl) {
        for (size_t c = 0; c < n_cols; c++) free(col_names[c].data);
        free(dtypes); free(col_names); dtypes = NULL; col_names = NULL;
        goto oom_recs;
    }
    tbl->columns = calloc(n_cols, sizeof(smaug_column_t));
    if (!tbl->columns) {
        free(tbl);
        for (size_t c = 0; c < n_cols; c++) free(col_names[c].data);
        free(dtypes); free(col_names); dtypes = NULL; col_names = NULL;
        goto oom_recs;
    }
    tbl->ncols = n_cols;
    tbl->nrows = n_recs;

    for (size_t c = 0; c < n_cols; c++) {
        tbl->columns[c].name  = col_names[c].data;
        tbl->columns[c].name_len = col_names[c].length;
        col_names[c].data     = NULL;   /* ownership transferida ao tbl */
        tbl->columns[c].dtype = dtype_name(dtypes[c]);

        switch (dtypes[c]) {
        case DT_I64: {
            smaug_series_i64_t *s = smaug_i64_create(n_recs);
            if (!s) { smaug_table_free(tbl); tbl=NULL; goto oom_recs; }
            for (size_t r = 0; r < n_recs; r++) {
                json_val_t *v = json_record_column(&recs[r], c);
                if (!v || v->type == 0) smaug_i64_set_null(s, r); /* registro heterogêneo (campo ausente) — caso normal, ver test_json_short_record */
                else if (v->type == 1)  smaug_i64_set(s, r, v->i);
                else if (v->type == 2)  smaug_i64_set(s, r, (int64_t)v->d); /* COV-EXCL-BR: dtype=int64 implica que toda linha não-null tinha jt==1 durante a inferência (dtype_upgrade força float64 se qualquer linha fosse jt==2) — mesmo argumento de pureza do csv.c */
                else                    smaug_i64_set_null(s, r); /* COV-EXCL-BR: idem — jt só pode ser 0(null)/1(int) numa coluna int64 */
            }
            tbl->columns[c].i64 = s; break;
        }
        case DT_F64: {
            smaug_series_f64_t *s = smaug_f64_create(n_recs);
            if (!s) { smaug_table_free(tbl); tbl=NULL; goto oom_recs; }
            for (size_t r = 0; r < n_recs; r++) {
                json_val_t *v = json_record_column(&recs[r], c);
                if (!v || v->type == 0) smaug_f64_set_null(s, r); /* registro heterogêneo — ver test_json_short_record */
                else if (v->type == 2)  smaug_f64_set(s, r, v->d);
                else if (v->type == 1)  smaug_f64_set(s, r, (double)v->i); /* COV-EXCL-BR: ramo falso inalcançável — se chegou aqui, type já não é 0 nem 2; pureza garante que só resta 1 */
                else                    smaug_f64_set_null(s, r); /* COV-EXCL-BR: dtype=float64 implica jt∈{1,2} pra toda linha não-null (mesmo argumento de pureza) */
            }
            tbl->columns[c].f64 = s; break;
        }
        case DT_BOOL: {
            smaug_series_bool_t *s = smaug_bool_create(n_recs);
            if (!s) { smaug_table_free(tbl); tbl=NULL; goto oom_recs; }
            for (size_t r = 0; r < n_recs; r++) {
                json_val_t *v = json_record_column(&recs[r], c);
                if (!v || v->type == 0) smaug_bool_set_null(s, r); /* registro heterogêneo — ver test_json_short_record */
                else if (v->type == 3)  smaug_bool_set(s, r, v->b); /* COV-EXCL-BR: ramo falso inalcançável — pureza garante type==3 sempre que não-null numa coluna bool */
                else                    smaug_bool_set_null(s, r); /* COV-EXCL-BR: idem — else nunca alcançado pelo mesmo motivo */
            }
            tbl->columns[c].boolcol = s; break;
        }
        default: {
            smaug_series_str_t *s = smaug_str_create(n_recs);
            if (!s) { smaug_table_free(tbl); tbl=NULL; goto oom_recs; }
            for (size_t r = 0; r < n_recs; r++) {
                json_val_t *v = json_record_column(&recs[r], c);
                if (!v || v->type == 0) { smaug_str_set_null(s, r); } /* registro heterogêneo — ver test_json_short_record */
                else if (v->type == 4) {
                    if (smaug_str_set(s, r, v->s, v->string_length) != SMG_OK) {
                        smaug_str_free(s);
                        smaug_table_free(tbl);
                        tbl = NULL;
                        goto oom_recs;
                    }
                }
                else { char tmp[64]; size_t n;
                       if (v->type==1) n=smaug_fmt_i64(tmp,sizeof(tmp),v->i);
                       else if (v->type==2) n=smaug_fmt_f64(tmp,sizeof(tmp),v->d);
                       else if (v->type==3) { strcpy(tmp,v->b?"true":"false"); n=strlen(tmp); }
                       else { tmp[0]='\0'; n=0; }
                       if (n == 0 || smaug_str_set(s, r, tmp, n) != SMG_OK) {
                           smaug_str_free(s);
                           smaug_table_free(tbl);
                           tbl = NULL;
                           goto oom_recs;
                       }
                }
            }
            tbl->columns[c].str = s; break;
        }
        }
    }

    for (size_t r = 0; r < n_recs; r++) free_record(&recs[r]);
    free(recs); free(dtypes); free(col_names);
    return tbl;

oom_recs:
    if (col_names) {
        for (size_t c = 0; c < n_cols_io; c++) free(col_names[c].data);
        free(col_names);
    }
    free(dtypes);
    for (size_t r = 0; r < n_recs; r++) free_record(&recs[r]);
    free(recs);
    return make_error("OOM");
}

static char *read_file_json(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long sz = ftell(f); rewind(f);
    if (sz < 0) { fclose(f); return NULL; }
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; }
    size_t got = fread(buf, 1, (size_t)sz, f); fclose(f);
    buf[got] = '\0'; *out_len = got;
    return buf;
}

smaug_table_t *smaug_read_json(const char *path) {
    size_t len; char *buf = read_file_json(path, &len);
    if (!buf) {
        char msg[256]; snprintf(msg,sizeof(msg),"não foi possível abrir '%s'",path);
        return make_error(msg);
    }
    smaug_table_t *t = smaug_read_json_mem(buf, len);
    free(buf); return t;
}

/* ===================================================================
   Writer JSON
   =================================================================== */

/* reutiliza wbuf_t do csv */
typedef struct { char *data; size_t len; size_t cap; } wbuf_j_t;
static int wbj_push(wbuf_j_t *b, const char *s, size_t n) {
    if (b->len + n >= b->cap) {
        size_t ncap = b->cap ? b->cap * 2 : 4096;
        while (ncap <= b->len + n) ncap *= 2;
        char *tmp = realloc(b->data, ncap);
        if (!tmp) return -1;
        b->data = tmp; b->cap = ncap;
    }
    memcpy(b->data + b->len, s, n); b->len += n; return 0;
}
static int wbj_pushc(wbuf_j_t *b, char c) { return wbj_push(b, &c, 1); }
static int wbj_pushz(wbuf_j_t *b, const char *s) { return wbj_push(b, s, strlen(s)); }

static int write_json_string(wbuf_j_t *b, const char *s, size_t n) {
    if (wbj_pushc(b, '"')) return -1;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        if      (c == '"')  { if (wbj_pushz(b, "\\\"")) return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else if (c == '\\') { if (wbj_pushz(b, "\\\\")) return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else if (c == '\n') { if (wbj_pushz(b, "\\n"))  return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else if (c == '\r') { if (wbj_pushz(b, "\\r"))  return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else if (c == '\t') { if (wbj_pushz(b, "\\t"))  return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else if (c < 0x20)  { char u[8]; snprintf(u,sizeof(u),"\\u%04x",c); if (wbj_pushz(b,u)) return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
        else                { if (wbj_pushc(b,(char)c)) return -1; }  /* COV-EXCL-BR: OOM de wbuf sem injeção */
    }
    return wbj_pushc(b, '"');
}

char *smaug_write_json_mem(const smaug_table_t *t,
                            const smaug_json_write_opts_t *opts,
                            size_t *out_len, char **err_out) {
    if (err_out) *err_out = NULL;   /* 12.30: limpa o slot; só preenche em erro */
    if (!t || !out_len) {
        set_io_error(err_out, "argumento nulo (tabela ou out_len)");
        return NULL;
    }
    if (t->ncols && !t->columns) {
        set_io_error(err_out, "colunas nulas");
        return NULL;
    }
    for (size_t column = 0; column < t->ncols; column++) {
        if (!t->columns[column].name) {
            set_io_error(err_out, "nome de coluna nulo; nome vazio exige ponteiro válido");
            return NULL;
        }
        const smaug_column_t *source = &t->columns[column];
        size_t invalid_byte;
        char message[160];
        if (!json_valid_utf8(source->name, source->name_len, &invalid_byte)) {
            int written = snprintf(message, sizeof(message),
                                   "JSON coluna %zu nome byte %zu: UTF-8 inválido",
                                   column, invalid_byte);
            set_io_error(err_out, written < 0 || (size_t)written >= sizeof(message)
                         ? "UTF-8 inválido em nome JSON" : message);
            return NULL;
        }
        if (source->str) {
            for (size_t row = 0; row < t->nrows; row++) {
                size_t length;
                const char *value = smaug_str_get(source->str, row, &length);
                if (value && !json_valid_utf8(value, length, &invalid_byte)) {
                    int written = snprintf(message, sizeof(message),
                        "JSON linha %zu coluna %zu valor byte %zu: UTF-8 inválido",
                        row, column, invalid_byte);
                    set_io_error(err_out, written < 0 || (size_t)written >= sizeof(message)
                                 ? "UTF-8 inválido em valor JSON" : message);
                    return NULL;
                }
            }
        }
    }

    int pretty = opts ? opts->pretty : 0; /* COV-EXCL-BR: NULL opts usa default 0; opts não-NULL cobre ambos */
    const char *nl   = pretty ? "\n" : "";
    const char *ind  = pretty ? "  " : "";
    const char *ind2 = pretty ? "    " : "";

    wbuf_j_t b = {0};
    if (wbj_pushc(&b, '[')) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
    if (wbj_pushz(&b, nl)) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */

    for (size_t r = 0; r < t->nrows; r++) {
        if (wbj_pushz(&b, ind)) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
        if (wbj_pushc(&b, '{')) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
        if (wbj_pushz(&b, nl)) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */

        for (size_t c = 0; c < t->ncols; c++) {
            if (wbj_pushz(&b, ind2)) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
            /* chave */
            const char *n = t->columns[c].name; /* COV-EXCL-BR: name sempre não-NULL após construção */
            if (write_json_string(&b, n, t->columns[c].name_len)) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
            if (wbj_pushc(&b, ':')) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
            if (pretty && wbj_pushc(&b, ' ')) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */

            /* valor */
            smaug_column_t *col = &t->columns[c];
            char tmp[64];
            if (col->i64) {
                smaug_status_t st;
                int64_t v = smaug_i64_get(col->i64, r, &st);
                if (st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; } /* st==SMG_NULL_VALUE é subcaso de st!=SMG_OK — simplificado (ver csv.c) */ /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
                else {
                    if (smaug_fmt_i64(tmp, sizeof(tmp), v) == 0) {
                        goto format_error;
                    }
                    if (wbj_pushz(&b, tmp)) {
                        goto oom;
                    }
                }
            } else if (col->f64) {
                smaug_status_t st;
                double v = smaug_f64_get(col->f64, r, &st);
                if (st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; } /* idem i64 */ /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
                /* 12.21: JSON (RFC 8259) nao comporta nao-finitos. NaN e
                   +-inf viram null. Antes so o NaN era interceptado e o inf caia
                   no fmt, gerando "inf" — literal que nem o nosso proprio parser
                   le (round-trip quebrado). O Anel 3 avisa o usuario da perda
                   via smaug_f64_count_nonfinite; aqui a escrita e' silenciosa
                   por contrato (o C nao tem canal de aviso). */
                else if (!isfinite(v)) { if (wbj_pushz(&b,"null")) goto oom; }  /* COV-EXCL-BR: OOM de wbuf + nao-finito→null: ramo oom inalcançável sem injeção */
                else {
                    if (smaug_fmt_f64(tmp, sizeof(tmp), v) == 0) {
                        goto format_error;
                    }
                    if (wbj_pushz(&b, tmp)) {
                        goto oom;
                    }
                }
            } else if (col->boolcol) {
                smaug_status_t st;
                uint8_t v = smaug_bool_get(col->boolcol, r, &st);
                if (st != SMG_OK) { if (wbj_pushz(&b,"null")) goto oom; } /* idem i64 */ /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
                else { if (wbj_pushz(&b, v ? "true" : "false")) goto oom; } /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
            } else if (col->str) { /* COV-EXCL-BR: dtype inferido garante exatamente um ponteiro não-NULL */
                size_t slen;
                const char *sv = smaug_str_get(col->str, r, &slen);
                if (!sv) { if (wbj_pushz(&b,"null")) goto oom; } /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
                else { if (write_json_string(&b, sv, slen)) goto oom; } /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
            } else { if (wbj_pushz(&b,"null")) goto oom; } /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */

            if (c + 1 < t->ncols) { if (wbj_pushc(&b,',')) goto oom; } /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
            if (wbj_pushz(&b, nl)) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
        }

        if (wbj_pushz(&b, ind)) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
        if (wbj_pushc(&b, '}')) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
        if (r + 1 < t->nrows) { if (wbj_pushc(&b,',')) goto oom; } /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
        if (wbj_pushz(&b, nl)) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
    }

    if (wbj_pushc(&b, ']')) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
    if (wbj_pushc(&b, '\n')) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
    if (wbj_pushc(&b, '\0')) goto oom; /* COV-EXCL-BR: ramo oom (realloc de wbuf) só dispara no instante de uma realocação — confirmado empiricamente que numa tabela de N linhas só 1 ponto falha; mesma natureza dos goto oom já excluídos em write_json_string (535-541) */
    *out_len = b.len - 1;
    return b.data;

format_error:
    set_io_error(err_out, "falha ao formatar número no JSON");
    free(b.data);
    return NULL;
oom:
    set_io_error(err_out, "OOM ao serializar JSON");
    free(b.data); return NULL;
}

int smaug_write_json(const char *path, const smaug_table_t *table,
                     const smaug_json_write_opts_t *opts) {
    /* A detailed error channel remains a separate API change. */
    if (!path) {
        return -1;
    }
    size_t length;
    char *buffer = smaug_write_json_mem(table, opts, &length, NULL);
    if (!buffer) {
        return -1;
    }
    FILE *file = fopen(path, "wb");
    if (!file) {
        free(buffer);
        return -1;
    }
    size_t written = fwrite(buffer, 1, length, file);
    /* fclose can report delayed write errors even after a complete fwrite. */
    int close_status = fclose(file);
    free(buffer);
    return written == length && close_status == 0 ? 0 : -1;
}
