#include "../include/smaug_math.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Float64

smaug_series_f64_t* smaug_f64_create(size_t size) {
    return smaug_f64_create_with_capacity(size, size);
}

smaug_series_f64_t* smaug_f64_create_with_capacity(size_t size, size_t capacity) {
    if (size > capacity) return  NULL;

    smaug_series_f64_t *s = malloc(sizeof(smaug_series_f64_t));
    if (!s) return NULL;

    s->data = malloc(capacity * sizeof(double));
    if (!s->data) {
        free(s);
        return NULL;
    }

    s->null_mask = malloc(capacity * sizeof(smaug_mask_t));
    if (!s->null_mask) {
        free(s->data);
        free(s);
        return NULL;
    }

    s->size = size;
    s->capacity = capacity;

    // Inicializador nulos
    memset(s->null_mask, 0x00, capacity);
    memset(s->data, 0.0, size * sizeof(double));

    // Metadados padrão
    s->meta.name = "unnamed";
    s->meta.dtype = "float64";
    s->meta.is_view = false;
    s->meta.external_alloc = false;

    return s;
}