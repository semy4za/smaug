-- lua/smaug/core/series/_types.lua
--
-- Descritores de dtype: o coração da abstração de tipos da Series.
-- Recebe I com: I.C, I.ffi, I.I64_MIN
-- Retorna: tabela DTYPES
--
-- Adicionar um novo dtype = novo bloco aqui + backend C.
-- Zero toque na lógica da Series.

return function(I)
    local C       = I.C
    local ffi     = I.ffi
    local I64_MIN = I.I64_MIN

    local DTYPES = {
        float64 = {
            name        = "float64",
            free        = C.smaug_f64_free,
            create      = C.smaug_f64_create,
            clone       = C.smaug_f64_clone,
            coalesce_scalar = C.smaug_f64_coalesce_scalar,
            get         = C.smaug_f64_get,
            get_value   = function(c, i) return tonumber(C.smaug_f64_get(c, i, nil)) end,
            set         = C.smaug_f64_set,
            set_null    = C.smaug_f64_set_null,
            is_null     = C.smaug_f64_is_null,
            append      = C.smaug_f64_append,
            append_null = C.smaug_f64_append_null,
            add = C.smaug_f64_add, sub = C.smaug_f64_sub,
            mul = C.smaug_f64_mul, div = C.smaug_f64_div,
            add_scalar = C.smaug_f64_add_scalar, sub_scalar = C.smaug_f64_sub_scalar,
            mul_scalar = C.smaug_f64_mul_scalar, div_scalar = C.smaug_f64_div_scalar,
            sum = C.smaug_f64_sum, mean = C.smaug_f64_mean,
            min = C.smaug_f64_min, max = C.smaug_f64_max,
            var = C.smaug_f64_var, std = C.smaug_f64_std,
            count_nonnull = C.smaug_f64_count_nonnull,
            sort = C.smaug_f64_sort,
            view = C.smaug_f64_view, take = C.smaug_f64_take,
            filter = C.smaug_f64_filter,
            gt = C.smaug_f64_gt, lt = C.smaug_f64_lt, eq = C.smaug_f64_eq,
            ge = C.smaug_f64_ge, le = C.smaug_f64_le, ne = C.smaug_f64_ne,
            cmp_gt = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_gt(c,t,om) end,
            cmp_lt = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_lt(c,t,om) end,
            cmp_eq = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_eq(c,t,om) end,
            cmp_ge = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_ge(c,t,om) end,
            cmp_le = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_le(c,t,om) end,
            cmp_ne = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_ne(c,t,om) end,
            argsort = C.smaug_f64_argsort,
            is_int_sentinel = function(_) return false end,
            -- Grupo A (Fase 3 Ring 0): janela e redução posicional
            cumsum  = C.smaug_f64_cumsum,
            cumprod = C.smaug_f64_cumprod,
            cummin  = C.smaug_f64_cummin,
            cummax  = C.smaug_f64_cummax,
            diff    = C.smaug_f64_diff,
            shift   = C.smaug_f64_shift,
            ffill   = C.smaug_f64_ffill,
            bfill   = C.smaug_f64_bfill,
            argmin  = C.smaug_f64_argmin,
            argmax  = C.smaug_f64_argmax,
            rank    = C.smaug_f64_rank,
            -- Grupo C (Fase 3 Ring 0): rolling ops
            rolling_sum  = C.smaug_f64_rolling_sum,
            rolling_mean = C.smaug_f64_rolling_mean,
            rolling_min  = C.smaug_f64_rolling_min,
            rolling_max  = C.smaug_f64_rolling_max,
            rolling_std   = C.smaug_f64_rolling_std,
            rolling_var   = C.smaug_f64_rolling_var,
            rolling_count = C.smaug_f64_rolling_count,
        },
        int64 = {
            name        = "int64",
            free        = C.smaug_i64_free,
            create      = C.smaug_i64_create,
            clone       = C.smaug_i64_clone,
            coalesce_scalar = C.smaug_i64_coalesce_scalar,
            get         = C.smaug_i64_get,
            get_value   = function(c, i) return tonumber(C.smaug_i64_get(c, i, nil)) end,
            set         = C.smaug_i64_set,
            set_null    = C.smaug_i64_set_null,
            is_null     = C.smaug_i64_is_null,
            append      = C.smaug_i64_append,
            append_null = C.smaug_i64_append_null,
            add = C.smaug_i64_add, sub = C.smaug_i64_sub,
            mul = C.smaug_i64_mul, div = C.smaug_i64_div,
            add_scalar = C.smaug_i64_add_scalar, sub_scalar = C.smaug_i64_sub_scalar,
            mul_scalar = C.smaug_i64_mul_scalar, div_scalar = C.smaug_i64_div_scalar,
            sum = C.smaug_i64_sum, mean = C.smaug_i64_mean,
            min = C.smaug_i64_min, max = C.smaug_i64_max,
            var = C.smaug_i64_var, std = C.smaug_i64_std,
            count_nonnull = C.smaug_i64_count_nonnull,
            sort = C.smaug_i64_sort,
            view = C.smaug_i64_view, take = C.smaug_i64_take,
            filter = C.smaug_i64_filter,
            gt = C.smaug_i64_gt, lt = C.smaug_i64_lt, eq = C.smaug_i64_eq,
            ge = C.smaug_i64_ge, le = C.smaug_i64_le, ne = C.smaug_i64_ne,
            cmp_gt = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_gt(c,t,om) end,
            cmp_lt = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_lt(c,t,om) end,
            cmp_eq = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_eq(c,t,om) end,
            cmp_ge = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_ge(c,t,om) end,
            cmp_le = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_le(c,t,om) end,
            cmp_ne = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_ne(c,t,om) end,
            argsort = C.smaug_i64_argsort,
            is_int_sentinel = function(v) return v == I64_MIN end,
            -- Grupo A (Fase 3 Ring 0): janela e redução posicional
            cumsum  = C.smaug_i64_cumsum,
            cumprod = C.smaug_i64_cumprod,
            cummin  = C.smaug_i64_cummin,
            cummax  = C.smaug_i64_cummax,
            diff    = C.smaug_i64_diff,
            shift   = C.smaug_i64_shift,
            ffill   = C.smaug_i64_ffill,
            bfill   = C.smaug_i64_bfill,
            argmin  = C.smaug_i64_argmin,
            argmax  = C.smaug_i64_argmax,
            rank    = C.smaug_i64_rank,
            -- Grupo C (Fase 3 Ring 0): rolling ops
            rolling_sum  = C.smaug_i64_rolling_sum,
            rolling_mean = C.smaug_i64_rolling_mean,
            rolling_min  = C.smaug_i64_rolling_min,
            rolling_max  = C.smaug_i64_rolling_max,
            rolling_std   = C.smaug_i64_rolling_std,
            rolling_var   = C.smaug_i64_rolling_var,
            rolling_count = C.smaug_i64_rolling_count,
        },
        string = {
            name        = "string",
            free        = C.smaug_str_free,
            create      = C.smaug_str_create,
            clone       = C.smaug_str_clone,
            coalesce_scalar = C.smaug_str_coalesce_scalar,
            get_value   = function(c, i)
                local len = ffi.new("size_t[1]")
                local p   = C.smaug_str_get(c, i, len)
                if p == nil then return nil end
                return ffi.string(p, len[0])
            end,
            set         = function(c, i, v) return C.smaug_str_set(c, i, v, #v) end,
            set_null    = C.smaug_str_set_null,
            is_null     = C.smaug_str_is_null,
            append      = function(c, v) return C.smaug_str_append(c, v, #v) end,
            append_null = C.smaug_str_append_null,
            count_nonnull = C.smaug_str_count_nonnull,
            cmp_eq = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_eq(c,t,#t,om) end,
            cmp_lt = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_lt(c,t,#t,om) end,
            cmp_gt = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_gt(c,t,#t,om) end,
            cmp_ge = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_ge(c,t,#t,om) end,
            cmp_le = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_le(c,t,#t,om) end,
            cmp_ne = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_ne(c,t,#t,om) end,
            filter = C.smaug_str_filter,
            take   = C.smaug_str_take,
            view    = C.smaug_str_view,   -- 9.2: view + COW (offset-based, modelo A1)
            sort    = C.smaug_str_sort,
            argsort = C.smaug_str_argsort,
            ffill   = C.smaug_str_ffill,
            bfill   = C.smaug_str_bfill,
            shift   = C.smaug_str_shift,
            argmin  = C.smaug_str_argmin,
            argmax  = C.smaug_str_argmax,
            rank    = C.smaug_str_rank,
            -- 7.2b: min/max retornam o valor (string) ou nil (vazia/toda-NA).
            -- Wrapper materializa o ponteiro+len do C via ffi.string.
            min = function(c, ignore_na)
                local len = ffi.new("size_t[1]")
                local p   = C.smaug_str_min(c, ignore_na, len)
                if p == nil then return nil end
                return ffi.string(p, len[0])
            end,
            max = function(c, ignore_na)
                local len = ffi.new("size_t[1]")
                local p   = C.smaug_str_max(c, ignore_na, len)
                if p == nil then return nil end
                return ffi.string(p, len[0])
            end,
            is_int_sentinel = function(_) return false end,
        },
        datetime = {
            name        = "datetime",
            free        = C.smaug_dt_free,
            create      = C.smaug_dt_create,
            clone       = C.smaug_dt_clone,
            coalesce_scalar = C.smaug_dt_coalesce_scalar,
            get_value   = function(c, i)
                local st = ffi.new("smaug_status_t[1]")
                local v  = C.smaug_dt_get(c, i, st)
                if st[0] ~= 0 then return nil end
                return tonumber(v)
            end,
            set = function(c, i, v)
                if type(v) == "string" then
                    local ep = ffi.new("int64_t[1]")
                    if C.smaug_dt_parse(v, #v, ep, 0) ~= 0 then
                        error("smaug: datetime parse falhou: " .. v, 3)
                    end
                    return C.smaug_dt_set(c, i, ep[0])
                end
                return C.smaug_dt_set(c, i, v)
            end,
            set_null    = C.smaug_dt_set_null,
            is_null     = C.smaug_dt_is_null,
            append = function(c, v)
                if type(v) == "string" then
                    local ep = ffi.new("int64_t[1]")
                    if C.smaug_dt_parse(v, #v, ep, 0) ~= 0 then
                        error("smaug: datetime parse falhou: " .. v, 3)
                    end
                    return C.smaug_dt_append(c, ep[0])
                end
                return C.smaug_dt_append(c, v)
            end,
            append_null = C.smaug_dt_append_null,
            count_nonnull = C.smaug_dt_count_nonnull,
            filter  = C.smaug_dt_filter,
            take    = C.smaug_dt_take,
            view    = C.smaug_dt_view,
            sort    = C.smaug_dt_sort,
            argsort = C.smaug_dt_argsort,
            ffill   = C.smaug_dt_ffill,
            bfill   = C.smaug_dt_bfill,
            shift   = C.smaug_dt_shift,
            argmin  = C.smaug_dt_argmin,
            argmax  = C.smaug_dt_argmax,
            rank    = C.smaug_dt_rank,
            min     = C.smaug_dt_min,
            max     = C.smaug_dt_max,
            cmp_gt = function(c, t, om) if type(t)~="number" then error("smaug: comparação de datetime espera epoch_ms (número)",4) end return C.smaug_dt_gt(c, t, om) end,
            cmp_lt = function(c, t, om) if type(t)~="number" then error("smaug: comparação de datetime espera epoch_ms (número)",4) end return C.smaug_dt_lt(c, t, om) end,
            cmp_eq = function(c, t, om) if type(t)~="number" then error("smaug: comparação de datetime espera epoch_ms (número)",4) end return C.smaug_dt_eq(c, t, om) end,
            cmp_ge = function(c, t, om) if type(t)~="number" then error("smaug: comparação de datetime espera epoch_ms (número)",4) end return C.smaug_dt_ge(c, t, om) end,
            cmp_le = function(c, t, om) if type(t)~="number" then error("smaug: comparação de datetime espera epoch_ms (número)",4) end return C.smaug_dt_le(c, t, om) end,
            cmp_ne = function(c, t, om) if type(t)~="number" then error("smaug: comparação de datetime espera epoch_ms (número)",4) end return C.smaug_dt_ne(c, t, om) end,
            is_int_sentinel = function(v) return v == I64_MIN end,
        },
        bool = {
            name        = "bool",
            free        = C.smaug_bool_free,
            create      = C.smaug_bool_create,
            clone       = C.smaug_bool_clone,
            get_value   = function(c, i)
                local st = ffi.new("smaug_status_t[1]")
                local v  = C.smaug_bool_get(c, i, st)
                if st[0] == C.SMG_NULL_VALUE or st[0] == C.SMG_ERR_OOB then return nil end
                return v ~= 0
            end,
            set = function(c, i, v)
                if v == nil then return C.smaug_bool_set_null(c, i) end
                return C.smaug_bool_set(c, i, v and 1 or 0)
            end,
            set_null    = C.smaug_bool_set_null,
            is_null     = C.smaug_bool_is_null,
            append = function(c, v)
                if v == nil then return C.smaug_bool_append_null(c) end
                return C.smaug_bool_append(c, v and 1 or 0)
            end,
            append_null = C.smaug_bool_append_null,
            count_nonnull = C.smaug_bool_count_nonnull,
            filter  = C.smaug_bool_filter,
            take    = C.smaug_bool_take,
            view    = C.smaug_bool_view,   -- bool é mutável (tem set); view + COW idênticos a f64/i64/dt
            sort    = C.smaug_bool_sort,
            argsort = C.smaug_bool_argsort,
            ffill   = C.smaug_bool_ffill,
            bfill   = C.smaug_bool_bfill,
            shift   = C.smaug_bool_shift,
            argmin  = C.smaug_bool_argmin,
            argmax  = C.smaug_bool_argmax,
            rank    = C.smaug_bool_rank,
            -- 7.2b: min/max retornam o valor (bool) ou nil (vazia/toda-NA).
            -- Wrapper lê o status (Shape 1) para distinguir false de ausência.
            min = function(c, ignore_na)
                local st = ffi.new("smaug_status_t[1]")
                local v  = C.smaug_bool_min(c, ignore_na, st)
                if st[0] ~= C.SMG_OK then return nil end
                return v ~= 0
            end,
            max = function(c, ignore_na)
                local st = ffi.new("smaug_status_t[1]")
                local v  = C.smaug_bool_max(c, ignore_na, st)
                if st[0] ~= C.SMG_OK then return nil end
                return v ~= 0
            end,
            cmp_eq = function(c, t, om) if type(t)~="boolean" then error("smaug: comparação bool espera true/false",4) end return C.smaug_bool_eq(c, t and 1 or 0, om) end,
            cmp_ne = function(c, t, om) if type(t)~="boolean" then error("smaug: comparação bool espera true/false",4) end return C.smaug_bool_ne(c, t and 1 or 0, om) end,
            is_int_sentinel = function(_) return false end,
        },
    }

    return DTYPES
end
