local ffi = require("ffi")
ffi.cdef([[
    typedef uint8_t smaug_mask_t;
    typedef struct { const char *name, *dtype; bool is_view, external_alloc; } smaug_metadata_t;
    typedef struct {
        double *data; smaug_mask_t *null_mask;
        size_t size, capacity; smaug_metadata_t meta;
    } smaug_series_f64_t;
    smaug_series_f64_t* smaug_f64_create(size_t size);
    void   smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val);
    double smaug_f64_sum(const smaug_series_f64_t *s, bool ignore_na);
    void   smaug_f64_free(smaug_series_f64_t *s);
]])

local C = ffi.load("./build/libsmaug.so")
local s = C.smaug_f64_create(3)
assert(s ~= nil)
C.smaug_f64_set(s, 0, 1.0)
C.smaug_f64_set(s, 1, 2.0)
C.smaug_f64_set(s, 2, 3.0)
assert(math.abs(C.smaug_f64_sum(s, true) - 6.0) < 1e-9)
C.smaug_f64_free(s)
print("OK — soma = 6, série liberada")