#include "smaug_io_internal.h"
#include "smaug_io.h"
#include "smaug_core.h"
#include "smaug_string.h"
#include <stdio.h>

static const char *schema_type_name(smaug_dtype_t dtype) {
    switch (dtype) {
        case SMAUG_DTYPE_BOOL: return "bool";
        case SMAUG_DTYPE_INT64: return "int64";
        case SMAUG_DTYPE_FLOAT64: return "float64";
        case SMAUG_DTYPE_STRING: return "string";
        default: return "invalid";
    }
}

const char *smaug_io_status_reason(smaug_status_t status) {
    switch (status) {
        case SMG_ERR_NOMEM: return "OOM";
        case SMG_ERR_OVERFLOW: return "OVERFLOW";
        case SMG_ERR_UNDERFLOW: return "UNDERFLOW";
        case SMG_ERR_SYNTAX: return "SYNTAX";
        default: return "invalid argument or operation";
    }
}

smaug_table_t *smaug_io_schema_error(const char *format, const smaug_schema_t *schema,
    size_t record, size_t field, size_t byte, const char *reason) {
    char message[320];
    const char *dtype = field != SIZE_MAX && schema && field < schema->count
        ? schema_type_name(schema->fields[field].dtype) : "unspecified";
    char byte_context[48] = "unavailable";
    if (byte != SIZE_MAX) {
        int count = snprintf(byte_context, sizeof(byte_context), "%zu", byte);
        if (count < 0 || (size_t)count >= sizeof(byte_context)) {
            return make_error("schema: byte diagnostic formatting failed");
        }
    }
    /* Zero context means descriptor/header rather than a data record/field.
     * Never interpolate arbitrary name bytes into a C-string diagnostic. */
    int written = snprintf(message, sizeof(message),
        "%s schema record %zu column %zu expected %s byte %s: %s",
        format, record == SIZE_MAX ? 0 : record + 1,
        field == SIZE_MAX ? 0 : field + 1, dtype, byte_context, reason);
    if (written < 0 || (size_t)written >= sizeof(message)) {
        return make_error("schema: diagnostic formatting failed");
    }
    return make_error(message);
}

size_t smaug_io_schema_find(const smaug_schema_t *schema, const char *name, size_t length) {
    for (size_t field = 0; field < schema->count; field++) {
        if (io_bytes_equal(name, length, schema->fields[field].name,
                           schema->fields[field].name_len)) {
            return field;
        }
    }
    return SIZE_MAX;
}

smaug_table_t *smaug_io_schema_table(const smaug_schema_t *schema, size_t rows) {
    if (schema->count > SIZE_MAX / sizeof(smaug_column_t) ||
        rows > SIZE_MAX / sizeof(double) || rows > SIZE_MAX / sizeof(int64_t) ||
        rows >= SIZE_MAX / sizeof(size_t)) {
        return NULL;
    }
    smaug_table_t *table = calloc(1, sizeof(*table));
    if (!table) {
        return NULL;
    }
    table->columns = calloc(schema->count, sizeof(*table->columns));
    if (!table->columns) {
        free(table);
        return NULL;
    }
    table->ncols = schema->count;
    table->nrows = rows;
    for (size_t field = 0; field < schema->count; field++) {
        const smaug_schema_field_t *descriptor = &schema->fields[field];
        smaug_column_t *column = &table->columns[field];
        column->name = io_copy_bytes(descriptor->name, descriptor->name_len);
        column->name_len = descriptor->name_len;
        column->dtype = schema_type_name(descriptor->dtype);
        if (!column->name) {
            smaug_table_free(table);
            return NULL;
        }
        int allocated = 0;
        switch (descriptor->dtype) {
            case SMAUG_DTYPE_BOOL:
                column->boolcol = smaug_bool_create(rows);
                allocated = column->boolcol != NULL;
                break;
            case SMAUG_DTYPE_INT64:
                column->i64 = smaug_i64_create(rows);
                allocated = column->i64 != NULL;
                break;
            case SMAUG_DTYPE_FLOAT64:
                column->f64 = smaug_f64_create(rows);
                allocated = column->f64 != NULL;
                break;
            case SMAUG_DTYPE_STRING:
                column->str = smaug_str_create(rows);
                allocated = column->str != NULL;
                break;
            default: break;
        }
        if (!allocated) {
            smaug_table_free(table);
            return NULL;
        }
    }
    return table;
}

smaug_status_t smaug_io_schema_set_null(smaug_column_t *column, size_t row) {
    if (column->i64) {
        return smaug_i64_set_null(column->i64, row);
    }
    if (column->f64) {
        return smaug_f64_set_null(column->f64, row);
    }
    if (column->boolcol) {
        return smaug_bool_set_null(column->boolcol, row);
    }
    return smaug_str_set_null(column->str, row);
}

smaug_status_t smaug_io_read_bytes(const char *path, char **buffer, size_t *length,
    const char **reason) {
    *reason = "invalid path";
    if (!path) {
        return SMG_ERR_ARGUMENT;
    }
    FILE *file = fopen(path, "rb");
    if (!file) {
        *reason = "file open failed";
        return SMG_ERR_ARGUMENT;
    }
    size_t capacity = 4096;
    size_t used = 0;
    char *data = malloc(capacity);
    smaug_status_t status = SMG_OK;
    if (!data) {
        status = SMG_ERR_NOMEM;
        *reason = "OOM reading file";
    }
    while (status == SMG_OK) {
        size_t received = fread(data + used, 1, capacity - used, file);
        used += received;
        if (ferror(file)) {
            *reason = "file read failed";
            status = SMG_ERR_ARGUMENT;
            break;
        }
        if (feof(file)) {
            break;
        }
        if (used < capacity) {
            *reason = "file read made no progress";
            status = SMG_ERR_ARGUMENT;
            break;
        }
        if (capacity > SIZE_MAX / 2) {
            *reason = "file size overflow";
            status = SMG_ERR_OVERFLOW;
            break;
        }
        char *resized = realloc(data, capacity * 2);
        if (!resized) {
            *reason = "OOM reading file";
            status = SMG_ERR_NOMEM;
            break;
        }
        data = resized;
        capacity *= 2;
    }
    if (fclose(file) != 0 && status == SMG_OK) {
        *reason = "file close failed";
        status = SMG_ERR_ARGUMENT;
    }
    if (status != SMG_OK) {
        free(data);
        return status;
    }
    *buffer = data;
    *length = used;
    return SMG_OK;
}
