-- lua/smaug/core/series/_bool_ops.lua
--
-- Helpers de operações booleanas e metamétodos aritméticos da Series.
-- Recebe I com: I.Series, I.C, I.ffi, I.wrap
-- Produz em I: I.bool_mask_parts, I.bool_series_from_raw, I.binop, I.kleene_binop
-- Contribui: Series.__add, __mul, __sub, __div, __len, __tostring, __newindex

return function(I)
    local Series  = I.Series
    local C       = I.C
    local ffi     = I.ffi
    local wrap    = I.wrap
    local methods = I.methods

    -- =====================================================================
    -- bool_mask_parts: extrai (uint8_t* vals, smaug_mask_t* nulls, size_t n)
    -- de uma Series<bool>. Retorna nil se o argumento não for válido.
    -- =====================================================================
    local function bool_mask_parts(mask)
        if type(mask) == "table" and mask._dtype == "bool" then
            return mask._c.data, mask._c.null_mask, tonumber(mask._c.size)
        end
        return nil
    end
    I.bool_mask_parts = bool_mask_parts

    -- bool_series_from_raw: constrói Series<bool> a partir de arrays crus.
    -- Copia os dados e libera os originais (gerenciamento de memória do C).
    local function bool_series_from_raw(vals, nulls, n, name)
        local s = C.smaug_bool_create(n)
        if s == nil then
            C.smaug_free(vals)
            if nulls ~= nil then C.smaug_free(nulls) end
            error("smaug: OOM ao criar Series<bool>", 3)
        end
        for i = 0, n - 1 do
            s.data[i]      = vals[i]
            s.null_mask[i] = nulls ~= nil and nulls[i] or 0xFF
        end
        C.smaug_free(vals)
        if nulls ~= nil then C.smaug_free(nulls) end
        return wrap(ffi.gc(s, C.smaug_bool_free), "bool", name)
    end
    I.bool_series_from_raw = bool_series_from_raw

    -- =====================================================================
    -- kleene_binop: lógica Kleene para Series<bool> (land/lor/lxor)
    -- =====================================================================
    local function kleene_binop(a, b, fn, opname)
        if a._dtype ~= "bool" then
            error("smaug: " .. opname .. " requer Series<bool>", 3)
        end
        local bv
        if type(b) == "table" and b._dtype == "bool" then
            bv = b._c
        else
            error("smaug: " .. opname .. " requer Series<bool>", 3)
        end
        local r = fn(a._c, bv)
        if r == nil then error("smaug: " .. opname .. " falhou (tamanhos diferentes ou OOM)", 3) end
        return wrap(ffi.gc(r, C.smaug_bool_free), "bool", a._name)
    end
    I.kleene_binop = kleene_binop

    -- =====================================================================
    -- binop: aritmética Series±Series e Series±escalar
    -- =====================================================================
    local function both_series(a, b)
        return getmetatable(a) == Series and getmetatable(b) == Series
    end

    local function binop(a, b, series_fn, scalar_fn, scalar_left_ok, opname)
        if both_series(a, b) then
            if a._dtype ~= b._dtype then
                error("smaug: '"..opname.."' entre dtypes diferentes ("..
                      a._dtype.." e "..b._dtype..") não é permitido", 2)
            end
            if a._c.size ~= b._c.size then
                error("smaug: '"..opname.."' entre séries de tamanhos diferentes", 2)
            end
            -- Series<bool>: operadores aritméticos mapeiam para Kleene
            if a._dtype == "bool" then
                local kleene_fn = (series_fn == "add") and C.smaug_bool_series_or
                               or (series_fn == "sub") and C.smaug_bool_series_xor
                               or (series_fn == "mul") and C.smaug_bool_series_and
                               or nil
                if kleene_fn == nil then
                    error("smaug: operação '"..opname.."' não se aplica a Series<bool>", 2)
                end
                local r = kleene_fn(a._c, b._c)
                if r == nil then error("smaug: '"..opname.."' falhou", 2) end
                return wrap(ffi.gc(r, C.smaug_bool_free), "bool", a._name)
            end
            local r = a._d[series_fn](a._c, b._c)
            if r == nil then error("smaug: '"..opname.."' falhou", 2) end
            return wrap(r, a._dtype, a._name)
        end
        if getmetatable(a) == Series and type(b) == "number" then
            local r = a._d[scalar_fn](a._c, b)
            return wrap(r, a._dtype, a._name)
        end
        if type(a) == "number" and getmetatable(b) == Series then
            if scalar_left_ok == "commute" then
                local r = b._d[scalar_fn](b._c, a)
                return wrap(r, b._dtype, b._name)
            end
            error("smaug: 'escalar "..opname.." Series' não é suportado; "..
                  "inverta a ordem ou use métodos explícitos", 2)
        end
        error("smaug: operandos inválidos para '"..opname.."'", 2)
    end
    I.binop = binop

    -- =====================================================================
    -- Metamétodos
    -- =====================================================================
    Series.__add = function(a, b) return binop(a, b, "add", "add_scalar", "commute", "+") end
    Series.__mul = function(a, b) return binop(a, b, "mul", "mul_scalar", "commute", "*") end
    Series.__sub = function(a, b) return binop(a, b, "sub", "sub_scalar", false,      "-") end
    Series.__div = function(a, b) return binop(a, b, "div", "div_scalar", false,      "/") end

    Series.__len = function(self) return tonumber(self._c.size) end

    Series.__tostring = function(self)
        local n = tonumber(self._c.size)
        local parts = {}
        local limit = math.min(n, 10)
        for i = 1, limit do
            local v = self:get(i)
            parts[#parts + 1] = string.format("  [%d] %s", i,
                v == nil and "NA" or tostring(v))
        end
        if n > limit then parts[#parts + 1] = "  ... ("..(n - limit).." mais)" end
        return string.format("Series '%s' (%s, len=%d)\n%s",
            self._name, self._dtype, n, table.concat(parts, "\n"))
    end

    -- __newindex: serie[i] = v → set(); outras chaves gravam no objeto.
    Series.__newindex = function(self, k, v)
        if type(k) == "number" then methods.set(self, k, v)
        else rawset(self, k, v) end
    end
end
