/* Reescrita do parser CSV com abordagem single-pass mais clara */
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

#include "../include/smaug_io.h"
#include "../include/smaug_core.h"
#include "../include/smaug_string.h"
#include "smaug_io_internal.h"
#include "../include/smaug_convert.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <math.h>

/* ===================================================================
   smaug_table_t — ciclo de vida
   =================================================================== */

void smaug_table_free(smaug_table_t *t) {
    if (!t) return;
    for (size_t i = 0; i < t->ncols; i++) {
        free((char *)t->columns[i].name);
        if (t->columns[i].f64)     smaug_f64_free(t->columns[i].f64);
        if (t->columns[i].i64)     smaug_i64_free(t->columns[i].i64);
        if (t->columns[i].boolcol) smaug_bool_free(t->columns[i].boolcol);
        if (t->columns[i].str)     smaug_str_free(t->columns[i].str);
    }
    free(t->columns);
    free(t->error);
    free(t);
}

static char *read_file(const char *path, size_t *out_len) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; } /* COV-EXCL-BR: falha de syscall não simulável sem mock */
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return NULL; } /* COV-EXCL-BR: ftell negativo só em fd inválido */
    rewind(f);
    char *buf = malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return NULL; } /* COV-EXCL-BR: OOM de malloc no read_file */
    size_t got = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    buf[got] = '\0';
    *out_len = got;
    return buf;
}

smaug_csv_opts_t smaug_csv_default_opts(void) {
    smaug_csv_opts_t o;
    o.sep       = ',';
    o.header    = 1;
    o.na_values = NULL;  /* usa o padrão interno */
    o.na_lengths = NULL;
    o.na_count  = 0;
    o.quote     = '"';
    o.decimal   = '.';
    return o;
}

smaug_csv_write_opts_t smaug_csv_write_default_opts(void) {
    smaug_csv_write_opts_t o;
    o.sep    = ',';
    o.header = 1;
    o.quote  = '"';
    o.decimal = '.';
    return o;
}

/* Valores NA padrão — vocabulário de AUSÊNCIA.
   "nan"/"NaN" NÃO estão aqui de propósito: NaN é um VALOR (IEEE 754), não
   ausência. O Smaug separa os dois — ausência vive no null_mask. Tratá-los
   como sentinela desfazia, na leitura, a distinção que o core inteiro sustenta,
   e criava colisão com o smaug_fmt_f64, que escreve "nan" como valor (o writer
   e o reader discordavam do significado do mesmo token). Também gerava um buraco
   por caixa: "nan"/"NaN" viravam ausência, mas "NAN" escapava para o strtod e
   virava valor. Agora todas as grafias de não-finito (nan/NaN/NAN/inf/Infinity/
   INF, case-insensitive via strtod) são valores, uniformemente.
   Quem lê CSV de terceiros onde "nan" significa ausência passa
   na_values={"nan"} explicitamente. */
static const char *BUILTIN_NA[] = {"", "NA", "null", "N/A", "NULL"};
#define BUILTIN_NA_COUNT 5

static int is_na(const char *s, size_t length, const char **na_values, const size_t *na_lengths,
                 size_t na_count) {
    const char **nav = na_values ? na_values : BUILTIN_NA;
    size_t nc = na_values ? na_count : BUILTIN_NA_COUNT;
    for (size_t index = 0; index < nc; index++) {
        size_t marker_length = na_values ? na_lengths[index] : strlen(nav[index]);
        if (io_bytes_equal(s, length, nav[index], marker_length)) {
            return 1;
        }
    }
    return 0;
}

/* O leitor adapta o separador; o core mantém gramática e diagnósticos. */
static smaug_status_t parse_csv_f64(const char *text, size_t length, double *output, char decimal) {
    if (!text || !output) {
        return SMG_ERR_ARGUMENT;
    }
    if (decimal == '.') {
        return smaug_parse_f64_status(text, length, output);
    }
    if (memchr(text, '.', length)) {
        return SMG_ERR_SYNTAX;
    }
    if (length == SIZE_MAX) {
        return SMG_ERR_NOMEM;
    }
    char local_buffer[256];
    char *buffer = local_buffer;
    if (length >= sizeof(local_buffer)) {
        buffer = malloc(length + 1);
        if (!buffer) {
            return SMG_ERR_NOMEM;
        }
    }
    for (size_t position = 0; position < length; position++) {
        buffer[position] = text[position] == decimal ? '.' : text[position];
    }
    buffer[length] = '\0';
    smaug_status_t status = smaug_parse_f64_status(buffer, length, output);
    if (buffer != local_buffer) {
        free(buffer);
    }
    return status;
}

static int try_bool(const char *s, size_t length, uint8_t *out) {
    if (length == 4 && (!memcmp(s,"true",4)||!memcmp(s,"True",4)||!memcmp(s,"TRUE",4)))   { *out=1; return 1; }
    if (length == 5 && (!memcmp(s,"false",5)||!memcmp(s,"False",5)||!memcmp(s,"FALSE",5))) { *out=0; return 1; }
    return 0;
}

typedef enum {
    CSV_FIELD_OK = 0,
    CSV_FIELD_UNCLOSED_QUOTE,
    CSV_FIELD_TRAILING_TEXT,
    CSV_FIELD_QUOTE_UNQUOTED,
    CSV_FIELD_BARE_CR
} csv_field_error_t;

/* ===================================================================
   Tokenizador: extrai campo CSV respeitando aspas RFC 4180.
   Avança *pos. Retorna campo alocado (chamar free). eol=1 se fim de linha.
   =================================================================== */
static char *next_field(const char *buf, size_t len, size_t *pos,
                         char sep, char quote, int *eol, size_t *out_length,
                         csv_field_error_t *error_kind, size_t *error_position) {
    *eol = 0;
    *out_length = 0;
    *error_kind = CSV_FIELD_OK;
    *error_position = *pos;
    size_t i = *pos;
    if (i >= len) { *eol = 1; return strdup(""); } /* COV-EXCL-BR: loop externo garante pos < len antes de chamar */

    char *out = NULL;
    size_t n = 0, cap = 0;

    #define PUSH(c) do { \
        if (n + 1 >= cap) { \
            if (cap > SIZE_MAX / 2) { free(out); return NULL; } \
            cap = cap ? cap * 2 : 32; \
            char *_t = realloc(out, cap); \
            if (!_t) { free(out); return NULL; } \
            out = _t; \
        } \
        out[n++] = (c); \
    } while(0)

    #define FIELD_ERROR(kind) do { \
        *error_kind = (kind); \
        *error_position = i; \
        free(out); \
        return NULL; \
    } while(0)

    if (buf[i] == quote) {
        i++;
        int closed = 0;
        while (i < len) {
            if (buf[i] == quote) {
                if (i+1 < len && buf[i+1] == quote) { PUSH(quote); i += 2; }
                else { i++; closed = 1; break; }
            } else if (buf[i] == '\r') {
                if (i + 1 >= len || buf[i + 1] != '\n') {
                    FIELD_ERROR(CSV_FIELD_BARE_CR);
                }
                PUSH('\r'); PUSH('\n'); i += 2;
            } else {
                PUSH(buf[i]); i++;
            }
        }
        if (!closed) {
            FIELD_ERROR(CSV_FIELD_UNCLOSED_QUOTE);
        }
        if (i < len && buf[i] != sep && buf[i] != '\n' && buf[i] != '\r') {
            FIELD_ERROR(CSV_FIELD_TRAILING_TEXT);
        }
    } else {
        while (i < len && buf[i] != sep && buf[i] != '\n' && buf[i] != '\r') {
            if (buf[i] == quote) {
                FIELD_ERROR(CSV_FIELD_QUOTE_UNQUOTED);
            }
            PUSH(buf[i]); i++;
        }
    }

    /* consumir delimitador */
    if (i < len && buf[i] == sep)       { i++; }
    else if (i < len && buf[i] == '\r') {
        if (i + 1 >= len || buf[i + 1] != '\n') {
            FIELD_ERROR(CSV_FIELD_BARE_CR);
        }
        i += 2; *eol=1;
    }
    else if (i < len && buf[i] == '\n') { i++; *eol=1; }
    else                                { *eol=1; }

    *pos = i;
    if (!out) { out = malloc(1); if (out) out[0]='\0'; } /* COV-EXCL-BR: só falha se PUSH falhou por OOM */
    else out[n] = '\0';
    *out_length = n;
    #undef FIELD_ERROR
    return out;
    #undef PUSH
}

/* ===================================================================
   Parser principal: coleta todos os tokens e depois constrói séries
   =================================================================== */
static void free_csv_fields(smaug_io_text_t *fields, size_t field_count) {
    for (size_t field_index = 0; field_index < field_count; field_index++) {
        free(fields[field_index].data);
    }
    free(fields);
}

static void free_csv_rows(smaug_io_text_t **rows, size_t *row_sizes, size_t row_count) {
    for (size_t row_index = 0; row_index < row_count; row_index++) {
        free_csv_fields(rows[row_index], row_sizes[row_index]);
    }
    free(rows);
    free(row_sizes);
}

static smaug_status_t csv_schema_set_value(smaug_column_t *column, size_t row,
    smaug_dtype_t dtype, const smaug_io_text_t *text, char decimal) {
    smaug_status_t status;
    switch (dtype) {
        case SMAUG_DTYPE_INT64: {
            int64_t value;
            status = smaug_parse_i64_status(text->data, text->length, &value);
            return status == SMG_OK ? smaug_i64_set(column->i64, row, value) : status;
        }
        case SMAUG_DTYPE_FLOAT64: {
            double value;
            status = parse_csv_f64(text->data, text->length, &value, decimal);
            return status == SMG_OK ? smaug_f64_set(column->f64, row, value) : status;
        }
        case SMAUG_DTYPE_BOOL: {
            uint8_t value;
            if (!try_bool(text->data, text->length, &value)) {
                return SMG_ERR_SYNTAX;
            }
            return smaug_bool_set(column->boolcol, row, value);
        }
        case SMAUG_DTYPE_STRING:
            return smaug_str_set(column->str, row, text->data, text->length);
        default: return SMG_ERR_ARGUMENT;
    }
}

static smaug_table_t *csv_schema_rows(smaug_io_text_t **rows, size_t row_count,
    size_t column_count, const smaug_csv_opts_t *options, const smaug_schema_t *schema) {
    if (column_count != schema->count) {
        return smaug_io_schema_error("CSV", schema, SIZE_MAX, SIZE_MAX, SIZE_MAX,
                                     "header/record width differs from schema");
    }
    if (column_count > SIZE_MAX / sizeof(size_t)) {
        return make_error("schema mapping size overflow");
    }
    size_t *source_columns = malloc(column_count * sizeof(*source_columns));
    if (!source_columns) {
        return NULL;
    }
    for (size_t field = 0; field < column_count; field++) {
        source_columns[field] = SIZE_MAX;
    }
    smaug_table_t *result = NULL;
    for (size_t source = 0; source < column_count; source++) {
        size_t field = options->header
            ? smaug_io_schema_find(schema, rows[0][source].data, rows[0][source].length)
            : source;
        if (field == SIZE_MAX || source_columns[field] != SIZE_MAX) {
            result = smaug_io_schema_error("CSV", schema, SIZE_MAX, field, SIZE_MAX,
                                           "unknown or duplicate header field");
            goto done;
        }
        source_columns[field] = source;
    }
    size_t header_rows = options->header ? 1 : 0;
    result = smaug_io_schema_table(schema, row_count - header_rows);
    if (!result) {
        goto done;
    }
    for (size_t record = 0; record < result->nrows; record++) {
        for (size_t field = 0; field < column_count; field++) {
            const smaug_schema_field_t *descriptor = &schema->fields[field];
            const smaug_io_text_t *text = &rows[record + header_rows][source_columns[field]];
            const char *reason = NULL;
            smaug_status_t status;
            if (is_na(text->data, text->length, options->na_values, options->na_lengths,
                       options->na_values ? options->na_count : 0)) {
                if (!descriptor->nullable) {
                    status = SMG_ERR_ARGUMENT;
                    reason = "missing value in non-nullable field";
                } else {
                    status = smaug_io_schema_set_null(&result->columns[field], record);
                }
            } else {
                status = csv_schema_set_value(&result->columns[field], record,
                    descriptor->dtype, text, options->decimal ? options->decimal : '.');
            }
            if (status != SMG_OK) {
                smaug_table_free(result);
                result = smaug_io_schema_error("CSV", schema, record, field, SIZE_MAX,
                    reason ? reason : smaug_io_status_reason(status));
                goto done;
            }
        }
    }
done:
    free(source_columns);
    return result;
}

static smaug_table_t *read_csv_memory(const char *buffer, size_t length,
    const smaug_csv_opts_t *options, const smaug_schema_t *schema) {
    if (!buffer && length > 0) {
        return NULL;
    }
    smaug_csv_opts_t default_options = smaug_csv_default_opts();
    if (!options) {
        options = &default_options;
    }
    /* Campos zerados preservam os defaults da API. */
    char separator = options->sep ? options->sep : ',';
    char quote = options->quote ? options->quote : '"';
    char decimal = options->decimal ? options->decimal : '.';
    const char **na_values = options->na_values;
    size_t na_count = na_values ? options->na_count : 0;
    if (na_count && !options->na_lengths) {
        return make_error("na_lengths obrigatório para marcadores CSV");
    }
    for (size_t marker = 0; marker < na_count; marker++) {
        if (!na_values[marker]) {
            return make_error("marcador CSV nulo");
        }
    }


    /* H.5.c: separador de campo e decimal iguais tornam o parsing ambíguo
       ("3,14" com sep=',' decimal=',' seria dois campos). Erro que orienta. */
    if (separator == decimal) {
        return make_error("separador de campo e decimal não podem "
                          "ser o mesmo caractere (ex.: sep=';' com decimal=',')");
    }

    if (length == 0) {
        return make_error("entrada vazia");
    }

    /* --- Passo 1: tokenizar tudo em um vetor plano de strings --- */
    /* Cada linha possui seus campos; o header, se houver, também está em rows. */
    size_t row_capacity = 64;
    smaug_io_text_t **rows = malloc(row_capacity * sizeof(smaug_io_text_t *));
    size_t *row_sizes = malloc(row_capacity * sizeof(size_t));
    if (!rows || !row_sizes) {
        free(rows);
        free(row_sizes);
        return make_error("OOM");
    }
    size_t row_count = 0;

    size_t position = 0;
    if (length >= 3 && (unsigned char)buffer[0] == 0xef &&
        (unsigned char)buffer[1] == 0xbb && (unsigned char)buffer[2] == 0xbf) {
        /* BOM é metadata de entrada, não parte do nome da primeira coluna. */
        position = 3;
    }
    while (position < length) {
        /* Pula linhas completamente vazias. */
        if (buffer[position] == '\n' || (buffer[position] == '\r' &&
            (position + 1 >= length || buffer[position + 1] == '\n'))) {
            if (buffer[position] == '\r') {
                position++;
            }
            position++;
            continue;
        }
        size_t field_capacity = 16;
        smaug_io_text_t *fields = malloc(field_capacity * sizeof(smaug_io_text_t));
        if (!fields) {
            goto oom_cleanup;
        }
        size_t field_count = 0;
        int end_of_line = 0;
        while (!end_of_line) {
            size_t field_length = 0;
            csv_field_error_t field_error = CSV_FIELD_OK;
            size_t error_position = position;
            char *field = next_field(buffer, length, &position, separator, quote,
                                     &end_of_line, &field_length,
                                     &field_error, &error_position);
            if (!field) {
                free_csv_fields(fields, field_count);
                if (field_error != CSV_FIELD_OK) {
                    const char *reason = "estrutura CSV inválida";
                    switch (field_error) {
                    case CSV_FIELD_UNCLOSED_QUOTE: reason = "aspas não fechadas"; break;
                    case CSV_FIELD_TRAILING_TEXT: reason = "texto após aspas fechadas"; break;
                    case CSV_FIELD_QUOTE_UNQUOTED: reason = "aspas em campo não citado"; break;
                    case CSV_FIELD_BARE_CR: reason = "CR isolado; use CRLF ou LF"; break;
                    default: break;
                    }
                    char message[192];
                    int written = snprintf(message, sizeof(message),
                                            "CSV byte %zu: %s", error_position, reason);
                    free_csv_rows(rows, row_sizes, row_count);
                    if (written < 0 || (size_t)written >= sizeof(message)) {
                        return make_error("CSV: falha ao construir diagnóstico");
                    }
                    return make_error(message);
                }
                goto oom_cleanup;
            }
            if (field_count >= field_capacity) {
                if (field_capacity > SIZE_MAX / sizeof(smaug_io_text_t) / 2) {
                    free(field);
                    free_csv_fields(fields, field_count);
                    goto oom_cleanup;
                }
                field_capacity *= 2;
                smaug_io_text_t *resized_fields = realloc(fields, field_capacity * sizeof(smaug_io_text_t));
                if (!resized_fields) {
                    free(field);
                    free_csv_fields(fields, field_count);
                    goto oom_cleanup;
                }
                fields = resized_fields;
            }
            fields[field_count++] = (smaug_io_text_t){field, field_length};
        }
        if (row_count >= row_capacity) {
            if (row_capacity > SIZE_MAX / sizeof(smaug_io_text_t *) / 2 ||
                row_capacity > SIZE_MAX / sizeof(size_t) / 2) {
                free_csv_fields(fields, field_count);
                goto oom_cleanup;
            }
            row_capacity *= 2;
            smaug_io_text_t **resized_rows = realloc(rows, row_capacity * sizeof(smaug_io_text_t *));
            if (!resized_rows) {
                free_csv_fields(fields, field_count);
                goto oom_cleanup;
            }
            /* O primeiro realloc pode mover o buffer mesmo se o segundo falhar. */
            rows = resized_rows;
            size_t *resized_sizes = realloc(row_sizes, row_capacity * sizeof(size_t));
            if (!resized_sizes) {
                free_csv_fields(fields, field_count);
                goto oom_cleanup;
            }
            row_sizes = resized_sizes;
        }
        rows[row_count] = fields;
        row_sizes[row_count] = field_count;
        row_count++;
    }

    if (row_count == 0) {
        free(rows);
        free(row_sizes);
        return make_error("sem linhas de dados");
    }

    size_t header_row = options->header ? 1 : 0;
    size_t column_count = row_sizes[0];
    if (column_count == 0) {
        free_csv_rows(rows, row_sizes, row_count);
        return make_error("sem colunas");
    }
    for (size_t row_index = header_row; row_index < row_count; row_index++) {
        if (row_sizes[row_index] != column_count) {
            char message[192];
            int written = snprintf(message, sizeof(message),
                                    "CSV linha %zu: largura %zu; esperado %zu",
                                    row_index, row_sizes[row_index], column_count);
            free_csv_rows(rows, row_sizes, row_count);
            if (written < 0 || (size_t)written >= sizeof(message)) {
                return make_error("CSV: falha ao construir diagnóstico");
            }
            return make_error(message);
        }
    }
    if (schema) {
        smaug_table_t *result = csv_schema_rows(rows, row_count, column_count, options, schema);
        free_csv_rows(rows, row_sizes, row_count);
        return result;
    }
    size_t data_rows = row_count - header_row;

    smaug_io_text_t *column_names = calloc(column_count, sizeof(smaug_io_text_t));
    if (!column_names) {
        goto oom_cleanup;
    }
    for (size_t column_index = 0; column_index < column_count; column_index++) {
        if (options->header) {
            column_names[column_index].length = rows[0][column_index].length;
            column_names[column_index].data = io_copy_bytes(rows[0][column_index].data,
                                                            rows[0][column_index].length);
        } else {
            char generated_name[32];
            int name_length = snprintf(generated_name, sizeof(generated_name),
                                       "col%zu", column_index);
            if (name_length < 0 || (size_t)name_length >= sizeof(generated_name)) {
                free_csv_fields(column_names, column_count);
                free_csv_rows(rows, row_sizes, row_count);
                return make_error("column name formatting failed");
            }
            column_names[column_index].data = strdup(generated_name);
            column_names[column_index].length = (size_t)name_length;
        }
        if (!column_names[column_index].data) {
            free_csv_fields(column_names, column_count);
            goto oom_cleanup;
        }
    }

    /* --- Passo 2: inferência de dtype --- */
    int *dtypes = calloc(column_count, sizeof(int));
    if (!dtypes) {
        free_csv_fields(column_names, column_count);
        goto oom_cleanup;
    }
    smaug_table_t *table = NULL;
    for (size_t row_index = 0; row_index < data_rows; row_index++) {
        smaug_io_text_t *row = rows[row_index + header_row];
        size_t row_size = row_sizes[row_index + header_row];
        for (size_t column_index = 0; column_index < column_count; column_index++) {
            const char *text = (column_index < row_size) ? row[column_index].data : "";
            size_t text_length = column_index < row_size ? row[column_index].length : 0;
            if (is_na(text, text_length, na_values, options->na_lengths, na_count)) {
                continue;
            }
            int64_t integer_value;
            double real_value;
            uint8_t bool_value;
            int candidate;
            if (try_bool(text, text_length, &bool_value)) {
                candidate = DT_BOOL;
            } else if (smaug_parse_i64_status(text, text_length, &integer_value) == SMG_OK) {
                candidate = DT_I64;
            } else {
                smaug_status_t status = parse_csv_f64(text, text_length, &real_value, decimal);
                if (status == SMG_ERR_NOMEM || status == SMG_ERR_ARGUMENT) {
                    table = make_error(status == SMG_ERR_NOMEM
                        ? "OOM" : "invalid numeric argument");
                    goto done;
                }
                candidate = status == SMG_OK ? DT_F64 : DT_STR;
            }
            dtypes[column_index] = dtype_upgrade(dtypes[column_index], candidate);
        }
    }
    for (size_t column_index = 0; column_index < column_count; column_index++) {
        if (dtypes[column_index] == DT_UNKNOWN) {
            dtypes[column_index] = DT_STR;
        }
    }

    /* --- Passo 3: alocar e preencher séries --- */
    table = calloc(1, sizeof(smaug_table_t));
    if (!table) {
        free_csv_fields(column_names, column_count);
        free(dtypes);
        goto oom_cleanup;
    }
    table->columns = calloc(column_count, sizeof(smaug_column_t));
    if (!table->columns) {
        free(table);
        free_csv_fields(column_names, column_count);
        free(dtypes);
        goto oom_cleanup;
    }
    table->ncols = column_count;
    table->nrows = data_rows;

    for (size_t column_index = 0; column_index < column_count; column_index++) {
        table->columns[column_index].name = column_names[column_index].data;
        table->columns[column_index].name_len = column_names[column_index].length;
        column_names[column_index].data = NULL;
        table->columns[column_index].dtype = dtype_name(dtypes[column_index]);

        switch (dtypes[column_index]) {
        case DT_I64: {
            smaug_series_i64_t *series = smaug_i64_create(data_rows);
            if (!series) {
                smaug_table_free(table);
                table = NULL;
                goto done;
            }
            table->columns[column_index].i64 = series;
            for (size_t row_index = 0; row_index < data_rows; row_index++) {
                smaug_io_text_t *row = rows[row_index + header_row];
                size_t row_size = row_sizes[row_index + header_row];
                const char *text = (column_index < row_size) ? row[column_index].data : "";
                size_t text_length = column_index < row_size ? row[column_index].length : 0;
                if (is_na(text, text_length, na_values, options->na_lengths, na_count)) {
                    smaug_i64_set_null(series, row_index);
                    continue;
                }
                int64_t value;
                smaug_status_t status = smaug_parse_i64_status(text, text_length, &value);
                if (status != SMG_OK) {
                    smaug_table_free(table);
                    table = make_error("numeric conversion failed");
                    goto done;
                }
                smaug_i64_set(series, row_index, value);
            }
            break;
        }
        case DT_F64: {
            smaug_series_f64_t *series = smaug_f64_create(data_rows);
            if (!series) {
                smaug_table_free(table);
                table = NULL;
                goto done;
            }
            /* Transfere ownership antes de converter: qualquer falha limpa a tabela inteira. */
            table->columns[column_index].f64 = series;
            for (size_t row_index = 0; row_index < data_rows; row_index++) {
                smaug_io_text_t *row = rows[row_index + header_row];
                size_t row_size = row_sizes[row_index + header_row];
                const char *text = (column_index < row_size) ? row[column_index].data : "";
                size_t text_length = column_index < row_size ? row[column_index].length : 0;
                if (is_na(text, text_length, na_values, options->na_lengths, na_count)) {
                    smaug_f64_set_null(series, row_index);
                    continue;
                }
                double value;
                smaug_status_t status = parse_csv_f64(text, text_length, &value, decimal);
                if (status != SMG_OK) {
                    smaug_table_free(table);
                    table = make_error(status == SMG_ERR_NOMEM
                        ? "OOM" : "numeric conversion failed");
                    goto done;
                }
                smaug_f64_set(series, row_index, value);
            }
            break;
        }
        case DT_BOOL: {
            smaug_series_bool_t *series = smaug_bool_create(data_rows);
            if (!series) {
                smaug_table_free(table);
                table = NULL;
                goto done;
            }
            for (size_t row_index = 0; row_index < data_rows; row_index++) {
                smaug_io_text_t *row = rows[row_index + header_row];
                size_t row_size = row_sizes[row_index + header_row];
                const char *text = (column_index < row_size) ? row[column_index].data : "";
                size_t text_length = column_index < row_size ? row[column_index].length : 0;
                uint8_t bool_value;
                if (is_na(text, text_length, na_values, options->na_lengths, na_count)) {
                    smaug_bool_set_null(series, row_index);
                } else if (try_bool(text, text_length, &bool_value)) {
                    smaug_bool_set(series, row_index, bool_value);
                } else {
                    smaug_bool_set_null(series, row_index);
                }
            }
            table->columns[column_index].boolcol = series;
            break;
        }
        default: {
            smaug_series_str_t *series = smaug_str_create(data_rows);
            if (!series) {
                smaug_table_free(table);
                table = NULL;
                goto done;
            }
            for (size_t row_index = 0; row_index < data_rows; row_index++) {
                smaug_io_text_t *row = rows[row_index + header_row];
                size_t row_size = row_sizes[row_index + header_row];
                const char *text = (column_index < row_size) ? row[column_index].data : "";
                size_t text_length = column_index < row_size ? row[column_index].length : 0;
                smaug_status_t status;
                if (is_na(text, text_length, na_values, options->na_lengths, na_count)) {
                    status = smaug_str_set_null(series, row_index);
                } else {
                    status = smaug_str_set(series, row_index, text, text_length);
                }
                if (status != 0) {
                    smaug_str_free(series);
                    smaug_table_free(table);
                    table = make_error("OOM");
                    goto done;
                }
            }
            table->columns[column_index].str = series;
            break;
        }
        }
    }

done:
    /* Nomes transferidos para a tabela foram zerados no vetor temporário. */
    free_csv_fields(column_names, column_count);
    free(dtypes);
    free_csv_rows(rows, row_sizes, row_count);
    return table;

oom_cleanup:
    free_csv_rows(rows, row_sizes, row_count);
    return make_error("OOM");
}

smaug_table_t *smaug_read_csv_mem(const char *buffer, size_t length,
    const smaug_csv_opts_t *options) {
    return read_csv_memory(buffer, length, options, NULL);
}

smaug_table_t *smaug_read_csv_mem_schema(const char *buffer, size_t length,
    const smaug_csv_opts_t *options, const smaug_schema_t *schema) {
    size_t error_field;
    smaug_status_t status = smaug_schema_validate(schema, &error_field);
    if (status != SMG_OK) {
        return smaug_io_schema_error("CSV", schema, SIZE_MAX, error_field, SIZE_MAX,
                                     "invalid schema descriptor");
    }
    if (!buffer && length) {
        return make_error("CSV: NULL buffer with nonzero length");
    }
    return read_csv_memory(buffer, length, options, schema);
}

smaug_table_t *smaug_read_csv_schema(const char *path, const smaug_csv_opts_t *options,
    const smaug_schema_t *schema) {
    size_t error_field;
    if (smaug_schema_validate(schema, &error_field) != SMG_OK) {
        return smaug_io_schema_error("CSV", schema, SIZE_MAX, error_field, SIZE_MAX,
                                     "invalid schema descriptor");
    }
    char *buffer;
    size_t length;
    const char *reason;
    if (smaug_io_read_bytes(path, &buffer, &length, &reason) != SMG_OK) {
        return make_error(reason);
    }
    smaug_table_t *table = smaug_read_csv_mem_schema(buffer, length, options, schema);
    free(buffer);
    return table;
}

smaug_table_t *smaug_read_csv(const char *path, const smaug_csv_opts_t *opts) {
    size_t len; char *buf = read_file(path, &len);
    if (!buf) {
        char msg[256]; snprintf(msg,sizeof(msg),"não foi possível abrir '%s'",path);
        return make_error(msg);
    }
    smaug_table_t *t = smaug_read_csv_mem(buf, len, opts);
    free(buf); return t;
}

/* ===================================================================
   Writer CSV
   =================================================================== */

typedef struct { char *data; size_t len; size_t cap; } wbuf_t;

static int wbuf_push(wbuf_t *b, const char *s, size_t n) {
    if (b->len + n >= b->cap) {
        size_t ncap = b->cap ? b->cap * 2 : 4096;
        while (ncap <= b->len + n) ncap *= 2;
        char *tmp = realloc(b->data, ncap);
        if (!tmp) return -1;
        b->data = tmp; b->cap = ncap;
    }
    memcpy(b->data + b->len, s, n); b->len += n; return 0;
}
static int wbuf_pushc(wbuf_t *b, char c) { return wbuf_push(b, &c, 1); }

static int write_field(wbuf_t *b, const char *s, size_t n, char sep, char quote) {
    int needs_quote = 0;
    for (size_t i = 0; i < n; i++)
        if (s[i]==sep||s[i]=='\n'||s[i]=='\r'||s[i]==quote) { needs_quote=1; break; }
    if (!needs_quote) return wbuf_push(b, s, n);
    if (wbuf_pushc(b, quote)) return -1;
    for (size_t i = 0; i < n; i++) {
        if (s[i] == quote && wbuf_pushc(b, quote)) return -1;
        if (wbuf_pushc(b, s[i])) return -1;
    }
    return wbuf_pushc(b, quote);
}

char *smaug_write_csv_mem(const smaug_table_t *t,
                           const smaug_csv_write_opts_t *opts, size_t *out_len,
                           char **err_out) {
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
    }

    smaug_csv_write_opts_t def = smaug_csv_write_default_opts();
    if (!opts) opts = &def;
    char sep = opts->sep ? opts->sep : ',';   /* fallback defensivo (ver test_csv_write_opts_zero_sep_quote) */
    char quote = opts->quote ? opts->quote : '"'; /* fallback defensivo (ver test_csv_write_opts_zero_sep_quote) */
    char decimal = opts->decimal ? opts->decimal : '.'; /* fallback defensivo: campo zerado → '.' */
    /* H.5.c: sep == decimal produziria CSV ilegível (campo e decimal colidem). */
    if (sep == decimal) {
        set_io_error(err_out, "separador de campo e decimal não podem ser iguais");
        return NULL;
    }
    wbuf_t b = {0};

    if (opts->header) {
        for (size_t c = 0; c < t->ncols; c++) {
            if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
            const char *n = t->columns[c].name; /* COV-EXCL-BR: name sempre não-NULL após construção */
            if (write_field(&b, n, t->columns[c].name_len, sep, quote)) goto oom;
        }
        if (wbuf_pushc(&b, '\n')) goto oom;
    }

    for (size_t r = 0; r < t->nrows; r++) {
        for (size_t c = 0; c < t->ncols; c++) {
            if (c > 0 && wbuf_pushc(&b, sep)) goto oom;
            smaug_column_t *col = &t->columns[c];
            char tmp[64]; const char *s = tmp; size_t n;
            if (col->i64) {
                smaug_status_t st; int64_t v = smaug_i64_get(col->i64, r, &st);
                /* st==SMG_NULL_VALUE é subcaso de st!=SMG_OK (únicos dois
                 * status possíveis aqui: col->i64 não-NULL e r<nrows sempre,
                 * então ERR_ARGUMENT/ERR_OOB são inalcançáveis) — simplificado. */
                if (st != SMG_OK) { s=""; n=0; }
                else {
                    n = smaug_fmt_i64(tmp, sizeof(tmp), v);
                    if (n == 0) {
                        goto format_error;
                    }
                    s = tmp;
                }
            } else if (col->f64) {
                smaug_status_t st; double v = smaug_f64_get(col->f64, r, &st);
                if (st != SMG_OK) { s=""; n=0; } /* idem i64: subcaso redundante removido */
                else {
                    n = smaug_fmt_f64(tmp, sizeof(tmp), v);
                    if (n == 0) {
                        goto format_error;
                    }
                    /* decimal customizado: troca o '.' do fmt pelo separador
                       configurado. "%.17g" produz no máximo um '.' (nan/inf não têm). */
                    if (decimal != '.') {
                        for (size_t k = 0; k < n; k++)
                            if (tmp[k] == '.') { tmp[k] = decimal; break; }
                    }
                    s=tmp;
                }
            } else if (col->boolcol) {
                smaug_status_t st; uint8_t v = smaug_bool_get(col->boolcol, r, &st);
                if (st != SMG_OK) { s=""; n=0; } /* idem i64: subcaso redundante removido */
                else { s=v?"true":"false"; n=strlen(s); }
            } else if (col->str) {
                size_t slen; const char *sv = smaug_str_get(col->str, r, &slen);
                if (!sv) { s=""; n=0; } else { s=sv; n=slen; }
            } else { s=""; n=0; }
            if (write_field(&b, s, n, sep, quote)) goto oom;
        }
        if (wbuf_pushc(&b, '\n')) goto oom;
    }
    /* adiciona \0 de terminação para uso como string C (não conta em out_len) */
    if (wbuf_pushc(&b, '\0')) goto oom;
    *out_len = b.len - 1;  /* out_len não inclui o \0 */
    return b.data;
format_error:
    set_io_error(err_out, "falha ao formatar número no CSV");
    free(b.data);
    return NULL;
oom: set_io_error(err_out, "OOM ao serializar CSV"); free(b.data); return NULL;
}

int smaug_write_csv(const char *path, const smaug_table_t *table,
                     const smaug_csv_write_opts_t *opts) {
    /* A detailed error channel remains a separate API change. */
    if (!path) {
        return -1;
    }
    size_t length;
    char *buffer = smaug_write_csv_mem(table, opts, &length, NULL);
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
