#include "smaug_schema.h"
#include <string.h>

smaug_status_t smaug_schema_validate(const smaug_schema_t *schema, size_t *error_field) {
    if (error_field) {
        *error_field = SIZE_MAX;
    }
    if (!schema || !schema->fields || schema->count == 0) {
        return SMG_ERR_ARGUMENT;
    }
    if (schema->count > SIZE_MAX / sizeof(smaug_schema_field_t)) {
        return SMG_ERR_OVERFLOW;
    }
    for (size_t field_index = 0; field_index < schema->count; field_index++) {
        const smaug_schema_field_t *field = &schema->fields[field_index];
        smaug_status_t status = SMG_OK;
        if (field->name_len == SIZE_MAX) {
            status = SMG_ERR_OVERFLOW;
        } else if (!field->name || (field->nullable != 0 && field->nullable != 1) ||
                   field->dtype < SMAUG_DTYPE_BOOL || field->dtype > SMAUG_DTYPE_STRING) {
            status = SMG_ERR_ARGUMENT;
        } else {
            for (size_t previous = 0; previous < field_index; previous++) {
                const smaug_schema_field_t *other = &schema->fields[previous];
                if (field->name_len == other->name_len &&
                    memcmp(field->name, other->name, field->name_len) == 0) {
                    status = SMG_ERR_ARGUMENT;
                    break;
                }
            }
        }
        if (status != SMG_OK) {
            if (error_field) {
                *error_field = field_index;
            }
            return status;
        }
    }
    return SMG_OK;
}
