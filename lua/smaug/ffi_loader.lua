-- lua/smaug/ffi_loader.lua
--
-- Ponte FFI do Smaug. Responsabilidade ÚNICA: tradução.
--   1. Declara os tipos e assinaturas de include/smaug.h (umbrella) via ffi.cdef.
--   2. Carrega a biblioteca compilada (libsmaug.so / .dylib / .dll).
--   3. Devolve o namespace C.
--
-- Sem lógica de negócio aqui. Conversão 1-based/0-based, nil<->NAN, ffi.gc,
-- validação etc. ficam nas camadas de cima (series.lua, dataset.lua).
--
-- Mantenha este cdef em sincronia com include/smaug.h.

local ffi = require("ffi")

ffi.cdef([[
    /* ===== Tipos base ===== */

    typedef struct smaug_hash_table smaug_hash_table_t;  /* opaque (GroupBy futuro) */

    typedef uint8_t smaug_mask_t;   /* 0xFF = valido, 0x00 = NA */

    typedef struct {
        const char *name;
        const char *dtype;
        bool        is_view;
        bool        external_alloc;
    } smaug_metadata_t;

    /* ===== Contrato defensivo: códigos de status (SMG_OK == 0) ===== */
    typedef enum {
        SMG_OK = 0,
        SMG_NULL_VALUE,
        SMG_ERR_OOB,
        SMG_ERR_ARGUMENT,
        SMG_ERR_NOMEM
    } smaug_status_t;

    /* ===================================================================
       Series Float64
       =================================================================== */

    typedef struct {
        double           *data;
        smaug_mask_t     *null_mask;
        size_t            size;
        size_t            capacity;
        smaug_metadata_t  meta;
    } smaug_series_f64_t;

    /* --- Lifecycle --- */
    smaug_series_f64_t* smaug_f64_create(size_t size);
    smaug_series_f64_t* smaug_f64_create_with_capacity(size_t size, size_t capacity);
    smaug_series_f64_t* smaug_f64_create_from_array(const double *array, size_t len);
    void                smaug_f64_free(smaug_series_f64_t *s);
    smaug_series_f64_t* smaug_f64_clone(const smaug_series_f64_t *s);
    smaug_series_f64_t* smaug_f64_view(smaug_series_f64_t *s, size_t start, size_t len);

    /* --- Getters / Setters --- */
    double smaug_f64_get(const smaug_series_f64_t *s, size_t idx, smaug_status_t *status);
    smaug_status_t smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val);
    smaug_status_t smaug_f64_set_null(smaug_series_f64_t *s, size_t idx);
    bool   smaug_f64_is_null(smaug_series_f64_t *s, size_t idx);

    /* --- Append dinamico --- */
    int smaug_f64_append(smaug_series_f64_t *s, double val);
    int smaug_f64_append_null(smaug_series_f64_t *s);

    /* --- Aritmeticas serie x serie --- */
    smaug_series_f64_t* smaug_f64_add(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
    smaug_series_f64_t* smaug_f64_sub(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
    smaug_series_f64_t* smaug_f64_mul(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
    smaug_series_f64_t* smaug_f64_div(const smaug_series_f64_t *a, const smaug_series_f64_t *b);

    /* --- Aritmeticas serie x escalar --- */
    smaug_series_f64_t* smaug_f64_add_scalar(const smaug_series_f64_t *a, double scalar);
    smaug_series_f64_t* smaug_f64_sub_scalar(const smaug_series_f64_t *a, double scalar);
    smaug_series_f64_t* smaug_f64_mul_scalar(const smaug_series_f64_t *a, double scalar);
    smaug_series_f64_t* smaug_f64_div_scalar(const smaug_series_f64_t *a, double scalar);

    /* --- Reducoes --- */
    double smaug_f64_sum (const smaug_series_f64_t *s, bool ignore_na);
    double smaug_f64_mean(const smaug_series_f64_t *s, bool ignore_na);
    double smaug_f64_min (const smaug_series_f64_t *s, bool ignore_na);
    double smaug_f64_max (const smaug_series_f64_t *s, bool ignore_na);
    double smaug_f64_var (const smaug_series_f64_t *s, bool ignore_na);
    double smaug_f64_std (const smaug_series_f64_t *s, bool ignore_na);

    /* --- Comparacoes -> uint8_t* (caller libera) --- */
    uint8_t* smaug_f64_gt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_f64_lt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_f64_eq(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_f64_ge(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_f64_le(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_f64_ne(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);

    /* --- Ordenacao --- */
    size_t*             smaug_f64_argsort(const smaug_series_f64_t *s, bool ascending);
    smaug_series_f64_t* smaug_f64_sort   (const smaug_series_f64_t *s, bool ascending);

    /* --- Utilitarios --- */
    size_t              smaug_f64_count_nonnull(const smaug_series_f64_t *s);
    smaug_series_f64_t* smaug_f64_take  (const smaug_series_f64_t *s, const size_t *idx, size_t len);
    smaug_series_f64_t* smaug_f64_filter(const smaug_series_f64_t *s, const uint8_t *mask);

    /* ===================================================================
       Series Int64
       =================================================================== */

    typedef struct {
        int64_t          *data;
        smaug_mask_t     *null_mask;
        size_t            size;
        size_t            capacity;
        smaug_metadata_t  meta;
    } smaug_series_i64_t;

    /* --- Lifecycle --- */
    smaug_series_i64_t* smaug_i64_create(size_t size);
    smaug_series_i64_t* smaug_i64_create_with_capacity(size_t size, size_t capacity);
    smaug_series_i64_t* smaug_i64_create_from_array(const int64_t *array, size_t len);
    void                smaug_i64_free(smaug_series_i64_t *s);
    smaug_series_i64_t* smaug_i64_clone(const smaug_series_i64_t *s);
    smaug_series_i64_t* smaug_i64_view(smaug_series_i64_t *s, size_t start, size_t len);

    /* --- Getters / Setters --- */
    int64_t smaug_i64_get(const smaug_series_i64_t *s, size_t idx, smaug_status_t *status);
    smaug_status_t smaug_i64_set(smaug_series_i64_t *s, size_t idx, int64_t val);
    smaug_status_t smaug_i64_set_null(smaug_series_i64_t *s, size_t idx);
    bool    smaug_i64_is_null(smaug_series_i64_t *s, size_t idx);

    /* --- Append dinamico --- */
    int smaug_i64_append(smaug_series_i64_t *s, int64_t val);
    int smaug_i64_append_null(smaug_series_i64_t *s);

    /* --- Aritmeticas serie x serie --- */
    smaug_series_i64_t* smaug_i64_add(const smaug_series_i64_t *a, const smaug_series_i64_t *b);
    smaug_series_i64_t* smaug_i64_sub(const smaug_series_i64_t *a, const smaug_series_i64_t *b);
    smaug_series_i64_t* smaug_i64_mul(const smaug_series_i64_t *a, const smaug_series_i64_t *b);
    smaug_series_i64_t* smaug_i64_div(const smaug_series_i64_t *a, const smaug_series_i64_t *b);

    /* --- Aritmeticas serie x escalar --- */
    smaug_series_i64_t* smaug_i64_add_scalar(const smaug_series_i64_t *a, int64_t scalar);
    smaug_series_i64_t* smaug_i64_sub_scalar(const smaug_series_i64_t *a, int64_t scalar);
    smaug_series_i64_t* smaug_i64_mul_scalar(const smaug_series_i64_t *a, int64_t scalar);
    smaug_series_i64_t* smaug_i64_div_scalar(const smaug_series_i64_t *a, int64_t scalar);

    /* --- Reducoes --- */
    int64_t smaug_i64_sum (const smaug_series_i64_t *s, bool ignore_na);
    int64_t smaug_i64_min (const smaug_series_i64_t *s, bool ignore_na);
    int64_t smaug_i64_max (const smaug_series_i64_t *s, bool ignore_na);
    double  smaug_i64_mean(const smaug_series_i64_t *s, bool ignore_na);
    double  smaug_i64_var (const smaug_series_i64_t *s, bool ignore_na);
    double  smaug_i64_std (const smaug_series_i64_t *s, bool ignore_na);

    /* --- Comparacoes -> uint8_t* (caller libera) --- */
    uint8_t* smaug_i64_gt(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_i64_lt(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_i64_eq(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_i64_ge(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_i64_le(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_i64_ne(const smaug_series_i64_t *s, int64_t threshold, smaug_mask_t **out_mask);

    /* --- Ordenacao --- */
    size_t*             smaug_i64_argsort(const smaug_series_i64_t *s, bool ascending);
    smaug_series_i64_t* smaug_i64_sort   (const smaug_series_i64_t *s, bool ascending);

    /* --- Utilitarios --- */
    size_t              smaug_i64_count_nonnull(const smaug_series_i64_t *s);
    smaug_series_i64_t* smaug_i64_take  (const smaug_series_i64_t *s, const size_t *idx, size_t len);
    smaug_series_i64_t* smaug_i64_filter(const smaug_series_i64_t *s, const uint8_t *mask);

    /* --- liberação dos arrays brutos devolvidos por compare/argsort/bool ops.
       Exportada pela própria lib Smaug (não a free() da libc), para liberar no
       mesmo runtime/heap que alocou — essencial no Windows. --- */
    void smaug_free(void *ptr);

    /* ===================================================================
       Series Bool — dtype de primeira classe (Fase 2: Anel 1)
       Struct-based, espelha f64/i64. As funções raw abaixo (smaug_bool_and
       etc.) permanecem para a BoolSeries legada até a Fase 4.
       =================================================================== */

    typedef struct {
        uint8_t          *data;
        smaug_mask_t     *null_mask;
        size_t            size;
        size_t            capacity;
        smaug_metadata_t  meta;
    } smaug_series_bool_t;

    /* --- Lifecycle --- */
    smaug_series_bool_t* smaug_bool_create(size_t size);
    smaug_series_bool_t* smaug_bool_create_with_capacity(size_t size, size_t capacity);
    smaug_series_bool_t* smaug_bool_create_from_array(const uint8_t *array, size_t len);
    void                 smaug_bool_free(smaug_series_bool_t *s);
    smaug_series_bool_t* smaug_bool_clone(const smaug_series_bool_t *s);
    smaug_series_bool_t* smaug_bool_view(smaug_series_bool_t *s, size_t start, size_t len);

    /* --- Getters / Setters --- */
    uint8_t        smaug_bool_get(const smaug_series_bool_t *s, size_t idx, smaug_status_t *status);
    smaug_status_t smaug_bool_set(smaug_series_bool_t *s, size_t idx, uint8_t val);
    smaug_status_t smaug_bool_set_null(smaug_series_bool_t *s, size_t idx);
    bool           smaug_bool_is_null(smaug_series_bool_t *s, size_t idx);

    /* --- Append dinamico --- */
    int smaug_bool_append(smaug_series_bool_t *s, uint8_t val);
    int smaug_bool_append_null(smaug_series_bool_t *s);

    /* --- Selecao --- */
    size_t               smaug_bool_count_nonnull(const smaug_series_bool_t *s);
    smaug_series_bool_t* smaug_bool_take  (const smaug_series_bool_t *s, const size_t *idx, size_t len);
    smaug_series_bool_t* smaug_bool_filter(const smaug_series_bool_t *s, const uint8_t *mask);

    /* --- Agregacoes struct-based --- */
    size_t smaug_bool_series_count_true(const smaug_series_bool_t *s);
    bool   smaug_bool_series_any(const smaug_series_bool_t *s);
    bool   smaug_bool_series_all(const smaug_series_bool_t *s);

    /* --- Logica Kleene struct->struct --- */
    smaug_series_bool_t* smaug_bool_series_and(const smaug_series_bool_t *a, const smaug_series_bool_t *b);
    smaug_series_bool_t* smaug_bool_series_or (const smaug_series_bool_t *a, const smaug_series_bool_t *b);
    smaug_series_bool_t* smaug_bool_series_xor(const smaug_series_bool_t *a, const smaug_series_bool_t *b);
    smaug_series_bool_t* smaug_bool_series_not(const smaug_series_bool_t *a);

    /* --- Ordenacao: false < true; recusa NULL --- */
    size_t*              smaug_bool_argsort(const smaug_series_bool_t *s, bool ascending);
    smaug_series_bool_t* smaug_bool_sort   (const smaug_series_bool_t *s, bool ascending);

    /* ===================================================================
       Operações Boolean (BoolSeries) — lógica de três valores (Kleene)
       =================================================================== */
    uint8_t* smaug_bool_and(const uint8_t *a, const smaug_mask_t *am,
                            const uint8_t *b, const smaug_mask_t *bm,
                            size_t n, smaug_mask_t **out_mask);
    uint8_t* smaug_bool_or (const uint8_t *a, const smaug_mask_t *am,
                            const uint8_t *b, const smaug_mask_t *bm,
                            size_t n, smaug_mask_t **out_mask);
    uint8_t* smaug_bool_xor(const uint8_t *a, const smaug_mask_t *am,
                            const uint8_t *b, const smaug_mask_t *bm,
                            size_t n, smaug_mask_t **out_mask);
    uint8_t* smaug_bool_not(const uint8_t *a, const smaug_mask_t *am,
                            size_t n, smaug_mask_t **out_mask);
    size_t smaug_bool_count_true(const uint8_t *a, const smaug_mask_t *am, size_t n);
    bool   smaug_bool_any(const uint8_t *a, const smaug_mask_t *am, size_t n);
    bool   smaug_bool_all(const uint8_t *a, const smaug_mask_t *am, size_t n);

    /* ===================================================================
       Series String (offset-based)
       =================================================================== */

    typedef struct {
        char             *buffer;
        size_t           *offsets;
        smaug_mask_t     *null_mask;
        size_t            size;
        size_t            capacity;
        size_t            buffer_len;
        size_t            buffer_capacity;
        smaug_metadata_t  meta;
    } smaug_series_str_t;

    /* --- Lifecycle --- */
    smaug_series_str_t* smaug_str_create(size_t size);
    smaug_series_str_t* smaug_str_create_with_capacity(size_t size, size_t buffer_capacity);
    smaug_series_str_t* smaug_str_create_from_array(const char *const *array, size_t len);
    void                smaug_str_free(smaug_series_str_t *s);
    smaug_series_str_t* smaug_str_clone(const smaug_series_str_t *s);

    /* --- Acesso --- */
    const char* smaug_str_get(const smaug_series_str_t *s, size_t idx, size_t *out_len);
    smaug_status_t smaug_str_set(smaug_series_str_t *s, size_t idx, const char *str, size_t len);
    smaug_status_t smaug_str_set_null(smaug_series_str_t *s, size_t idx);
    bool smaug_str_is_null(const smaug_series_str_t *s, size_t idx);
    int  smaug_str_append(smaug_series_str_t *s, const char *str, size_t len);
    int  smaug_str_append_null(smaug_series_str_t *s);

    /* --- Utilidades --- */
    size_t smaug_str_count_nonnull(const smaug_series_str_t *s);

    /* --- Comparações (contra string-alvo; retornam uint8_t* + out_mask) --- */
    uint8_t* smaug_str_eq(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);
    uint8_t* smaug_str_lt(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);
    uint8_t* smaug_str_gt(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);
    uint8_t* smaug_str_ge(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);
    uint8_t* smaug_str_le(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);
    uint8_t* smaug_str_ne(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);

    /* --- Seleção --- */
    smaug_series_str_t* smaug_str_filter(const smaug_series_str_t *s, const uint8_t *mask);
    smaug_series_str_t* smaug_str_take(const smaug_series_str_t *s, const size_t *idx, size_t len);

    /* --- Ordenação --- */
    size_t*             smaug_str_argsort(const smaug_series_str_t *s, bool ascending);
    smaug_series_str_t* smaug_str_sort(const smaug_series_str_t *s, bool ascending);
]])

-- Nome do arquivo da lib conforme o SO.
local function lib_filename()
    if ffi.os == "Windows" then return "smaug.dll" end
    if ffi.os == "OSX"     then return "libsmaug.dylib" end
    return "libsmaug.so"
end

-- Tenta carregar a lib a partir de uma lista de paths candidatos.
local function load_library()
    local name = lib_filename()
    local candidates = {
        "./build/" .. name,        -- rodando da raiz do projeto
        "../build/" .. name,       -- rodando de dentro de lua/
        "../../build/" .. name,    -- rodando de dentro de lua/smaug/
        "/usr/local/lib/" .. name, -- instalada no sistema
        name,                      -- deixa o loader do SO resolver (LD_LIBRARY_PATH etc)
    }

    local errors = {}
    for _, path in ipairs(candidates) do
        local ok, lib = pcall(ffi.load, path)
        if ok then return lib end
        errors[#errors + 1] = "  " .. path .. " -> " .. tostring(lib)
    end

    error(string.format(
        "Smaug: falha ao carregar '%s'. Compile com 'make' primeiro.\n" ..
        "Paths tentados:\n%s",
        name, table.concat(errors, "\n")
    ), 2)
end

return load_library()
