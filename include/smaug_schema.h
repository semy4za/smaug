#ifndef SMAUG_SCHEMA_H
#define SMAUG_SCHEMA_H

#include "smaug_types.h"

/* Reusable data description. No format options or owned buffers.
 * These identifiers describe types, not the private inference lattice. */
typedef enum {
    SMAUG_DTYPE_BOOL = 1,
    SMAUG_DTYPE_INT64 = 2,
    SMAUG_DTYPE_FLOAT64 = 3,
    SMAUG_DTYPE_STRING = 4
} smaug_dtype_t;

typedef struct {
    const char *name;       /* Non-NULL, name_len accessible bytes; NUL is allowed. */
    size_t name_len;
    smaug_dtype_t dtype;
    int nullable;          /* Exactly 0 or 1. */
} smaug_schema_field_t;

typedef struct {
    const smaug_schema_field_t *fields;
    size_t count;          /* Nonempty ordered sequence, unique byte names. */
} smaug_schema_t;

/* Allocation-free. Returns ARGUMENT for invalid descriptors, OVERFLOW for
 * unrepresentable lengths. Optional error_field receives a zero-based field
 * index, or SIZE_MAX for a schema-level error/success. Borrowed memory must
 * remain accessible and unchanged during validation/reader calls. */
smaug_status_t smaug_schema_validate(const smaug_schema_t *schema, size_t *error_field);

#endif
