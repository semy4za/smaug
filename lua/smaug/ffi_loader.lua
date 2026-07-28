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
       Series Bool — declarado cedo: referenciado por *_select (cond-bool).
       =================================================================== */

    typedef struct {
        uint8_t          *data;
        smaug_mask_t     *null_mask;
        size_t            size;
        size_t            capacity;
        smaug_metadata_t  meta;
    } smaug_series_bool_t;

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
    smaug_series_f64_t* smaug_f64_coalesce_scalar(const smaug_series_f64_t *self, double value);
    smaug_series_f64_t* smaug_f64_coalesce(const smaug_series_f64_t *self, const smaug_series_f64_t *other);
    smaug_series_f64_t* smaug_f64_select(const smaug_series_bool_t *cond, const smaug_series_f64_t *a, const smaug_series_f64_t *b);
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
    uint8_t* smaug_f64_between(const smaug_series_f64_t *s, double lo, double hi,
                               bool inc_lo, bool inc_hi, smaug_mask_t **out_mask);

    /* --- Ordenacao --- */
    size_t*             smaug_f64_argsort(const smaug_series_f64_t *s, bool ascending);
    smaug_series_f64_t* smaug_f64_sort   (const smaug_series_f64_t *s, bool ascending);

    /* --- Utilitarios --- */
    size_t              smaug_f64_count_nonnull(const smaug_series_f64_t *s);
    size_t              smaug_f64_count_nonfinite(const smaug_series_f64_t *s);
    smaug_series_f64_t* smaug_f64_take  (const smaug_series_f64_t *s, const size_t *idx, size_t len);
    smaug_series_f64_t* smaug_f64_filter(const smaug_series_f64_t *s, const uint8_t *mask);

    /* --- Grupo A: janela e reducao posicional (Fase 3 Ring 0) --- */
    smaug_series_f64_t* smaug_f64_cumsum (const smaug_series_f64_t *s);
    smaug_series_f64_t* smaug_f64_cumprod(const smaug_series_f64_t *s);
    smaug_series_f64_t* smaug_f64_cummin (const smaug_series_f64_t *s);
    smaug_series_f64_t* smaug_f64_cummax (const smaug_series_f64_t *s);
    smaug_series_f64_t* smaug_f64_diff   (const smaug_series_f64_t *s, size_t periods);
    smaug_series_f64_t* smaug_f64_shift  (const smaug_series_f64_t *s, int64_t periods);
    smaug_series_f64_t* smaug_f64_ffill  (const smaug_series_f64_t *s);
    smaug_series_f64_t* smaug_f64_bfill  (const smaug_series_f64_t *s);
    size_t              smaug_f64_argmin  (const smaug_series_f64_t *s);
    size_t              smaug_f64_argmax  (const smaug_series_f64_t *s);

    /* --- Grupo B: sorted_nonnull e rank (Fase 3 Ring 0) --- */
    /* Retornam ponteiros brutos; caller libera com smaug_free. */
    double* smaug_f64_sorted_nonnull(const smaug_series_f64_t *s, size_t *out_n);
    double* smaug_f64_rank          (const smaug_series_f64_t *s, int method);

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
    smaug_series_i64_t* smaug_i64_coalesce_scalar(const smaug_series_i64_t *self, int64_t value);
    smaug_series_i64_t* smaug_i64_coalesce(const smaug_series_i64_t *self, const smaug_series_i64_t *other);
    smaug_series_i64_t* smaug_i64_select(const smaug_series_bool_t *cond, const smaug_series_i64_t *a, const smaug_series_i64_t *b);
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
    uint8_t* smaug_i64_between(const smaug_series_i64_t *s, int64_t lo, int64_t hi,
                               bool inc_lo, bool inc_hi, smaug_mask_t **out_mask);

    /* --- Ordenacao --- */
    size_t*             smaug_i64_argsort(const smaug_series_i64_t *s, bool ascending);
    smaug_series_i64_t* smaug_i64_sort   (const smaug_series_i64_t *s, bool ascending);

    /* --- Utilitarios --- */
    size_t              smaug_i64_count_nonnull(const smaug_series_i64_t *s);
    smaug_series_i64_t* smaug_i64_take  (const smaug_series_i64_t *s, const size_t *idx, size_t len);
    smaug_series_i64_t* smaug_i64_filter(const smaug_series_i64_t *s, const uint8_t *mask);

    /* --- Grupo A: janela e reducao posicional (Fase 3 Ring 0) --- */
    smaug_series_i64_t* smaug_i64_cumsum (const smaug_series_i64_t *s);
    smaug_series_i64_t* smaug_i64_cumprod(const smaug_series_i64_t *s);
    smaug_series_i64_t* smaug_i64_cummin (const smaug_series_i64_t *s);
    smaug_series_i64_t* smaug_i64_cummax (const smaug_series_i64_t *s);
    smaug_series_i64_t* smaug_i64_diff   (const smaug_series_i64_t *s, size_t periods);
    smaug_series_i64_t* smaug_i64_shift  (const smaug_series_i64_t *s, int64_t periods);
    smaug_series_i64_t* smaug_i64_ffill  (const smaug_series_i64_t *s);
    smaug_series_i64_t* smaug_i64_bfill  (const smaug_series_i64_t *s);
    size_t              smaug_i64_argmin  (const smaug_series_i64_t *s);
    size_t              smaug_i64_argmax  (const smaug_series_i64_t *s);

    /* --- Grupo B: sorted_nonnull e rank (Fase 3 Ring 0) --- */
    int64_t* smaug_i64_sorted_nonnull(const smaug_series_i64_t *s, size_t *out_n);
    double*  smaug_i64_rank          (const smaug_series_i64_t *s, int method);

    /* --- liberação dos arrays brutos devolvidos por compare/argsort/bool ops.
       Exportada pela própria lib Smaug (não a free() da libc), para liberar no
       mesmo runtime/heap que alocou — essencial no Windows. --- */
    void smaug_free(void *ptr);

    /* ===================================================================
       Series Bool — dtype de primeira classe (Fase 2: Anel 1)
       Struct-based, espelha f64/i64. As funções raw abaixo (smaug_bool_and
       etc.) permanecem para a BoolSeries legada até a Fase 4.
       =================================================================== */

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
    smaug_series_bool_t* smaug_bool_coalesce_scalar(const smaug_series_bool_t *self, uint8_t value);

    /* --- Agregacoes struct-based --- */
    size_t smaug_bool_series_count_true(const smaug_series_bool_t *s);
    bool   smaug_bool_series_any(const smaug_series_bool_t *s);
    bool   smaug_bool_series_all(const smaug_series_bool_t *s);

    /* --- Logica Kleene struct->struct --- */
    smaug_series_bool_t* smaug_bool_series_and(const smaug_series_bool_t *a, const smaug_series_bool_t *b);
    smaug_series_bool_t* smaug_bool_series_or (const smaug_series_bool_t *a, const smaug_series_bool_t *b);
    smaug_series_bool_t* smaug_bool_series_xor(const smaug_series_bool_t *a, const smaug_series_bool_t *b);
    smaug_series_bool_t* smaug_bool_series_not(const smaug_series_bool_t *a);
    uint8_t* smaug_bool_eq(const smaug_series_bool_t *s, uint8_t threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_bool_ne(const smaug_series_bool_t *s, uint8_t threshold, smaug_mask_t **out_mask);

    /* --- Ordenacao: false < true; recusa NULL --- */
    size_t*              smaug_bool_argsort(const smaug_series_bool_t *s, bool ascending);
    smaug_series_bool_t* smaug_bool_sort   (const smaug_series_bool_t *s, bool ascending);

    /* --- Movimentação de dados (item 7.1): ffill/bfill --- */
    smaug_series_bool_t* smaug_bool_ffill  (const smaug_series_bool_t *s);
    smaug_series_bool_t* smaug_bool_bfill  (const smaug_series_bool_t *s);
    smaug_series_bool_t* smaug_bool_shift  (const smaug_series_bool_t *s, int64_t periods);
    size_t smaug_bool_argmin (const smaug_series_bool_t *s);
    size_t smaug_bool_argmax (const smaug_series_bool_t *s);
    uint8_t smaug_bool_min (const smaug_series_bool_t *s, bool ignore_na, smaug_status_t *status);
    uint8_t smaug_bool_max (const smaug_series_bool_t *s, bool ignore_na, smaug_status_t *status);
    double* smaug_bool_rank (const smaug_series_bool_t *s, int method);

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
        bool              offsets_owned;
        smaug_metadata_t  meta;
    } smaug_series_str_t;

    /* --- Lifecycle --- */
    smaug_series_str_t* smaug_str_create(size_t size);
    smaug_series_str_t* smaug_str_create_with_capacity(size_t size, size_t buffer_capacity);
    smaug_series_str_t* smaug_str_create_from_array(const char *const *array, size_t len);
    void                smaug_str_free(smaug_series_str_t *s);
    smaug_series_str_t* smaug_str_clone(const smaug_series_str_t *s);
    smaug_series_str_t* smaug_str_coalesce_scalar(const smaug_series_str_t *self, const char *value, size_t value_len);
    smaug_series_str_t* smaug_str_coalesce(const smaug_series_str_t *self, const smaug_series_str_t *other);
    smaug_series_str_t* smaug_str_select(const smaug_series_bool_t *cond, const smaug_series_str_t *a, const smaug_series_str_t *b);
    smaug_series_str_t* smaug_str_view(smaug_series_str_t *s, size_t start, size_t len);

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
    uint8_t* smaug_str_between(const smaug_series_str_t *s,
                               const char *lo, size_t lo_len,
                               const char *hi, size_t hi_len,
                               bool inc_lo, bool inc_hi, smaug_mask_t **out_mask);

    /* --- Seleção --- */
    smaug_series_str_t* smaug_str_filter(const smaug_series_str_t *s, const uint8_t *mask);
    smaug_series_str_t* smaug_str_take(const smaug_series_str_t *s, const size_t *idx, size_t len);

    /* --- Ordenação --- */
    size_t*             smaug_str_argsort(const smaug_series_str_t *s, bool ascending);
    smaug_series_str_t* smaug_str_sort(const smaug_series_str_t *s, bool ascending);

    /* --- Movimentação de dados (item 7.1): ffill/bfill (offset-based, cópia) --- */
    smaug_series_str_t* smaug_str_ffill  (const smaug_series_str_t *s);
    smaug_series_str_t* smaug_str_bfill  (const smaug_series_str_t *s);
    smaug_series_str_t* smaug_str_shift  (const smaug_series_str_t *s, int64_t periods);
    size_t smaug_str_argmin (const smaug_series_str_t *s);
    size_t smaug_str_argmax (const smaug_series_str_t *s);
    const char* smaug_str_min (const smaug_series_str_t *s, bool ignore_na, size_t *out_len);
    const char* smaug_str_max (const smaug_series_str_t *s, bool ignore_na, size_t *out_len);
    double* smaug_str_rank (const smaug_series_str_t *s, int method);

    /* ===================================================================
       Anel 3 — I/O (CSV + JSON)
       smaug_table_t: struct intermediária entre leitores e DataSet.
       =================================================================== */

    typedef struct {
        const char          *name;
        const char          *dtype;
        smaug_series_f64_t  *f64;
        smaug_series_i64_t  *i64;
        smaug_series_bool_t *boolcol;
        smaug_series_str_t  *str;
    } smaug_column_t;

    typedef struct {
        smaug_column_t *columns;
        size_t          ncols;
        size_t          nrows;
        char           *error;
    } smaug_table_t;

    /* stdlib básico necessário para o frontend I/O */
    void* malloc(size_t size);
    void  free(void *ptr);

    void           smaug_table_free(smaug_table_t *t);

    typedef struct {
        char        sep;
        int         header;
        const char **na_values;
        size_t      na_count;
        char        quote;
        char        decimal;
    } smaug_csv_opts_t;

    typedef struct {
        char sep;
        int  header;
        char quote;
        char decimal;
    } smaug_csv_write_opts_t;

    smaug_csv_opts_t        smaug_csv_default_opts(void);
    smaug_csv_write_opts_t  smaug_csv_write_default_opts(void);
    smaug_table_t*          smaug_read_csv(const char *path, const smaug_csv_opts_t *opts);
    smaug_table_t*          smaug_read_csv_mem(const char *buf, size_t len, const smaug_csv_opts_t *opts);
    int                     smaug_write_csv(const char *path, const smaug_table_t *t, const smaug_csv_write_opts_t *opts);
    char*                   smaug_write_csv_mem(const smaug_table_t *t, const smaug_csv_write_opts_t *opts, size_t *out_len, char **err_out);

    typedef struct { int pretty; } smaug_json_write_opts_t;

    smaug_table_t*  smaug_read_json(const char *path);
    smaug_table_t*  smaug_read_json_mem(const char *buf, size_t len);
    int             smaug_write_json(const char *path, const smaug_table_t *t, const smaug_json_write_opts_t *opts);
    char*           smaug_write_json_mem(const smaug_table_t *t, const smaug_json_write_opts_t *opts, size_t *out_len, char **err_out);

    /* ===================================================================
       Datetime — dtype Tier 2 (epoch ms UTC)
       =================================================================== */

    typedef struct {
        int64_t      *data;
        uint8_t      *null_mask;
        size_t        size;
        size_t        capacity;
        smaug_metadata_t meta;
    } smaug_series_dt_t;

    /* Lifecycle */
    smaug_series_dt_t* smaug_dt_create(size_t size);
    smaug_series_dt_t* smaug_dt_create_with_capacity(size_t size, size_t capacity);
    smaug_series_dt_t* smaug_dt_create_from_array(const int64_t *array, size_t len);
    void               smaug_dt_free(smaug_series_dt_t *s);
    smaug_series_dt_t* smaug_dt_clone(const smaug_series_dt_t *s);
    smaug_series_dt_t* smaug_dt_coalesce_scalar(const smaug_series_dt_t *self, int64_t value);
    smaug_series_dt_t* smaug_dt_coalesce(const smaug_series_dt_t *self, const smaug_series_dt_t *other);
    smaug_series_dt_t* smaug_dt_select(const smaug_series_bool_t *cond, const smaug_series_dt_t *a, const smaug_series_dt_t *b);
    smaug_series_dt_t* smaug_dt_view(smaug_series_dt_t *s, size_t start, size_t len);

    /* Acesso */
    int64_t        smaug_dt_get(const smaug_series_dt_t *s, size_t idx, smaug_status_t *status);
    smaug_status_t smaug_dt_set(smaug_series_dt_t *s, size_t idx, int64_t epoch_ms);
    smaug_status_t smaug_dt_set_null(smaug_series_dt_t *s, size_t idx);
    bool           smaug_dt_is_null(const smaug_series_dt_t *s, size_t idx);
    int            smaug_dt_append(smaug_series_dt_t *s, int64_t epoch_ms);
    int            smaug_dt_append_null(smaug_series_dt_t *s);

    /* Parsing / formatação */
    int smaug_dt_parse(const char *str, size_t len, int64_t *epoch_ms, int dayfirst);
    int smaug_dt_format(int64_t epoch_ms, char *buf, size_t buf_size);

    /* Componentes calendário */
    int smaug_dt_year   (int64_t epoch_ms);
    int smaug_dt_month  (int64_t epoch_ms);
    int smaug_dt_day    (int64_t epoch_ms);
    int smaug_dt_hour   (int64_t epoch_ms);
    int smaug_dt_minute (int64_t epoch_ms);
    int smaug_dt_second (int64_t epoch_ms);
    int smaug_dt_ms     (int64_t epoch_ms);
    int smaug_dt_weekday(int64_t epoch_ms);
    int smaug_dt_yearday(int64_t epoch_ms);
    int smaug_dt_quarter(int64_t epoch_ms);
    int smaug_dt_week   (int64_t epoch_ms);

    /* Construção e aritmética */
    int64_t smaug_dt_from_parts(int year, int month, int day,
                                 int hour, int minute, int second, int ms);
    int64_t smaug_dt_diff_ms  (int64_t a, int64_t b);
    int64_t smaug_dt_add_ms   (int64_t epoch_ms, int64_t delta_ms);
    int64_t smaug_dt_truncate (int64_t epoch_ms, char unit);

    /* Comparações */
    uint8_t* smaug_dt_gt(const smaug_series_dt_t *s, int64_t threshold, uint8_t **out_mask);
    uint8_t* smaug_dt_lt(const smaug_series_dt_t *s, int64_t threshold, uint8_t **out_mask);
    uint8_t* smaug_dt_eq(const smaug_series_dt_t *s, int64_t threshold, uint8_t **out_mask);
    uint8_t* smaug_dt_ge(const smaug_series_dt_t *s, int64_t threshold, uint8_t **out_mask);
    uint8_t* smaug_dt_le(const smaug_series_dt_t *s, int64_t threshold, uint8_t **out_mask);
    uint8_t* smaug_dt_ne(const smaug_series_dt_t *s, int64_t threshold, uint8_t **out_mask);
    uint8_t* smaug_dt_between(const smaug_series_dt_t *s, int64_t lo, int64_t hi,
                              bool inc_lo, bool inc_hi, uint8_t **out_mask);

    /* Seleção e ordenação */
    size_t             smaug_dt_count_nonnull(const smaug_series_dt_t *s);
    size_t*            smaug_dt_argsort(const smaug_series_dt_t *s, bool ascending);
    smaug_series_dt_t* smaug_dt_sort   (const smaug_series_dt_t *s, bool ascending);
    smaug_series_dt_t* smaug_dt_take   (const smaug_series_dt_t *s, const size_t *idx, size_t len);
    smaug_series_dt_t* smaug_dt_filter (const smaug_series_dt_t *s, const uint8_t *mask);

    /* --- Movimentação de dados (item 7.1): ffill/bfill --- */
    smaug_series_dt_t* smaug_dt_ffill  (const smaug_series_dt_t *s);
    smaug_series_dt_t* smaug_dt_bfill  (const smaug_series_dt_t *s);
    smaug_series_dt_t* smaug_dt_shift  (const smaug_series_dt_t *s, int64_t periods);
    size_t smaug_dt_argmin (const smaug_series_dt_t *s);
    size_t smaug_dt_argmax (const smaug_series_dt_t *s);
    int64_t smaug_dt_min (const smaug_series_dt_t *s, bool ignore_na);
    int64_t smaug_dt_max (const smaug_series_dt_t *s, bool ignore_na);
    double* smaug_dt_rank (const smaug_series_dt_t *s, int method);

    /* ===================================================================
       Grupo C (Fase 3 Ring 0): multi_argsort e rolling ops
       =================================================================== */

    /* --- smaug_multi_argsort ---
       Tipos de coluna para o sort (espelho de smaug_col_kind_t em C). */
    typedef enum {
        SMAUG_COL_F64  = 0,
        SMAUG_COL_I64  = 1,
        SMAUG_COL_STR  = 2,
        SMAUG_COL_DT   = 3,
        SMAUG_COL_BOOL = 4
    } smaug_col_kind_t;

    /* Descritor de coluna de chave (union em C → maior membro define tamanho).
       No FFI do LuaJIT declaramos como void* para evitar union; o wrapper Lua
       popula o campo correto. */
    typedef struct {
        int      kind;   /* smaug_col_kind_t como int */
        void    *ptr;    /* ponteiro para a struct da série */
    } smaug_sort_col_ffi_t;

    /* Wrapper FFI: recebe array de smaug_sort_col_ffi_t montados pelo Lua.
       Definido em smaug_ops_window.c como função pública de fronteira. */
    size_t* smaug_multi_argsort_ffi(const smaug_sort_col_ffi_t *cols,
                                    size_t ncols, size_t nrows);

    /* --- Rolling ops f64 (window, min_periods) --- */
    smaug_series_f64_t* smaug_f64_rolling_sum  (const smaug_series_f64_t *s, size_t window, size_t min_periods);
    smaug_series_f64_t* smaug_f64_rolling_mean (const smaug_series_f64_t *s, size_t window, size_t min_periods);
    smaug_series_f64_t* smaug_f64_rolling_min  (const smaug_series_f64_t *s, size_t window, size_t min_periods);
    smaug_series_f64_t* smaug_f64_rolling_max  (const smaug_series_f64_t *s, size_t window, size_t min_periods);
    smaug_series_f64_t* smaug_f64_rolling_std  (const smaug_series_f64_t *s, size_t window, size_t min_periods);
    smaug_series_f64_t* smaug_f64_rolling_var  (const smaug_series_f64_t *s, size_t window, size_t min_periods);
    smaug_series_i64_t* smaug_f64_rolling_count(const smaug_series_f64_t *s, size_t window, size_t min_periods);

    /* --- Rolling ops i64 (mean/std/var retornam f64; count retorna i64) --- */
    smaug_series_i64_t* smaug_i64_rolling_sum  (const smaug_series_i64_t *s, size_t window, size_t min_periods);
    smaug_series_f64_t* smaug_i64_rolling_mean (const smaug_series_i64_t *s, size_t window, size_t min_periods);
    smaug_series_i64_t* smaug_i64_rolling_min  (const smaug_series_i64_t *s, size_t window, size_t min_periods);
    smaug_series_i64_t* smaug_i64_rolling_max  (const smaug_series_i64_t *s, size_t window, size_t min_periods);
    smaug_series_f64_t* smaug_i64_rolling_std  (const smaug_series_i64_t *s, size_t window, size_t min_periods);
    smaug_series_f64_t* smaug_i64_rolling_var  (const smaug_series_i64_t *s, size_t window, size_t min_periods);
    smaug_series_i64_t* smaug_i64_rolling_count(const smaug_series_i64_t *s, size_t window, size_t min_periods);

    /* ===== astype — matriz de conversão src×dst (Anel 0) =====
       Espelha include/smaug_astype.h. Diagonal usa os *_clone acima.
       str->dt recebe dayfirst (0/1). =================================== */
    smaug_series_f64_t* smaug_i64_to_f64(const smaug_series_i64_t *self);
    smaug_series_i64_t* smaug_f64_to_i64(const smaug_series_f64_t *self);
    smaug_series_dt_t*  smaug_i64_to_dt (const smaug_series_i64_t *self);
    smaug_series_i64_t* smaug_dt_to_i64 (const smaug_series_dt_t  *self);
    smaug_series_dt_t*  smaug_f64_to_dt (const smaug_series_f64_t *self);
    smaug_series_f64_t* smaug_dt_to_f64 (const smaug_series_dt_t  *self);
    smaug_series_str_t* smaug_i64_to_str(const smaug_series_i64_t *self);
    smaug_series_str_t* smaug_f64_to_str(const smaug_series_f64_t *self);
    smaug_series_str_t* smaug_dt_to_str (const smaug_series_dt_t  *self);
    smaug_series_i64_t* smaug_str_to_i64(const smaug_series_str_t *self);
    smaug_series_f64_t* smaug_str_to_f64(const smaug_series_str_t *self);
    smaug_series_dt_t*  smaug_str_to_dt (const smaug_series_str_t *self, int dayfirst);
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
