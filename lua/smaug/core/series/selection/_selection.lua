-- lua/smaug/core/series/selection/_selection.lua
--
-- Seleção condicional, lógica Kleene, comparações e funções matemáticas.
-- Recebe I com: I.methods, I.Series, I.C, I.ffi, I.wrap, I.NA,
--               I.bool_mask_parts, I.bool_series_from_raw, I.kleene_binop
-- Contribui: methods.where, mask, Series.ifelse, nlargest, nsmallest,
--            gt, lt, eq, ge, le, ne, filter, land, lor, lxor, lnot,
--            count_true, any, all, isna, notna, sin, cos, tan, exp, log, sqrt,
--            c_sorted_nonnull usada por nlargest/nsmallest

return function(I)
    local methods          = I.methods
    local Series           = I.Series
    local C                = I.C
    local ffi              = I.ffi
    local wrap             = I.wrap
    local NA               = I.NA
    local DTYPES           = I.DTYPES
    local bool_mask_parts  = I.bool_mask_parts
    local bool_series_from_raw = I.bool_series_from_raw
    local kleene_binop     = I.kleene_binop
    local c_sorted_nonnull = I.c_sorted_nonnull

    -- =====================================================================
    -- Comparações → Series<bool>
    -- =====================================================================
    local function compare(self, cmp_name, target)
        local wrapper = self._d[cmp_name]
        if wrapper == nil then
            error("smaug: comparação '" .. cmp_name .. "' não se aplica ao tipo "
                  .. self._dtype, 3)
        end
        local om   = ffi.new("smaug_mask_t*[1]")
        local vals = wrapper(self._c, target, om)
        if vals == nil then error("smaug: comparação falhou", 3) end
        return bool_series_from_raw(vals, om[0], self:len(), self._name)
    end

    function methods.gt(self, target) return compare(self, "cmp_gt", target) end
    function methods.lt(self, target) return compare(self, "cmp_lt", target) end
    function methods.eq(self, target) return compare(self, "cmp_eq", target) end
    function methods.ge(self, target) return compare(self, "cmp_ge", target) end
    function methods.le(self, target) return compare(self, "cmp_le", target) end
    function methods.ne(self, target) return compare(self, "cmp_ne", target) end

    -- filter(mask): nova Series com as linhas onde a máscara é true.
    function methods.filter(self, mask)
        local vals, _, mlen = bool_mask_parts(mask)
        if vals == nil then
            error("smaug: filter espera uma Series<bool> ou BoolSeries (use :gt/:lt/:eq)", 2)
        end
        if mlen ~= self:len() then
            error("smaug: filter com máscara de tamanho diferente ("..
                  mlen.." vs "..self:len()..")", 2)
        end
        local r = self._d.filter(self._c, vals)
        if r == nil then error("smaug: filter falhou", 2) end
        return wrap(r, self._dtype, self._name)
    end

    -- =====================================================================
    -- Lógica Kleene para Series<bool>
    -- =====================================================================
    function methods.land(self, other)
        return kleene_binop(self, other, C.smaug_bool_series_and, "land")
    end
    function methods.lor(self, other)
        return kleene_binop(self, other, C.smaug_bool_series_or, "lor")
    end
    function methods.lxor(self, other)
        return kleene_binop(self, other, C.smaug_bool_series_xor, "lxor")
    end
    function methods.lnot(self)
        if self._dtype ~= "bool" then
            error("smaug: lnot requer Series<bool>", 2)
        end
        local r = C.smaug_bool_series_not(self._c)
        if r == nil then error("smaug: lnot falhou (OOM)", 2) end
        return wrap(ffi.gc(r, C.smaug_bool_free), "bool", self._name)
    end

    -- Agregações booleanas
    function methods.count_true(self)
        if self._dtype ~= "bool" then
            error("smaug: count_true requer Series<bool>", 2)
        end
        return tonumber(C.smaug_bool_series_count_true(self._c))
    end
    function methods.any(self)
        if self._dtype ~= "bool" then
            error("smaug: any requer Series<bool>", 2)
        end
        return C.smaug_bool_series_any(self._c)
    end
    function methods.all(self)
        if self._dtype ~= "bool" then
            error("smaug: all requer Series<bool>", 2)
        end
        return C.smaug_bool_series_all(self._c)
    end

    -- =====================================================================
    -- Seleção condicional
    -- =====================================================================

    -- where(cond, other): mantém valor onde cond=true, substitui onde false/NA.
    -- resolve_operand: materializa um operando (série, escalar ou nil→NA) num
    -- cdata de tamanho n e dtype dado. Série já pronta é usada direto (valida
    -- dtype/tamanho); escalar vira série constante via create+coalesce_scalar
    -- (ambos selados); nil→NA é a própria série toda-nula. Broadcast em Lua,
    -- sem primitivo C novo. ffi.gc no cdata cru garante liberação.
    local function resolve_operand(desc, dtype, x, n, ctx)
        if type(x) == "table" and x._c ~= nil then
            if x._dtype ~= dtype then
                error("smaug: "..ctx.."() — dtype do operando ('"..tostring(x._dtype)
                      .."') difere de '"..dtype.."'", 3)
            end
            if x:len() ~= n then
                error("smaug: "..ctx.."() — tamanho do operando ("..x:len()
                      ..") difere de "..n, 3)
            end
            return x._c
        end
        local tmp = ffi.gc(desc.create(n), desc.free)   -- toda-nula
        if x == nil then return tmp end                  -- nil → NA
        if dtype == "string" then
            if type(x) ~= "string" then
                error("smaug: "..ctx.."() — operando escalar de string espera string", 3)
            end
            return ffi.gc(desc.coalesce_scalar(tmp, x, #x), desc.free)
        end
        return ffi.gc(desc.coalesce_scalar(tmp, x), desc.free)
    end

    function methods.where(self, cond, other)
        if type(cond) ~= "table" or cond._dtype ~= "bool" then
            error("smaug: where() espera Series<bool> como primeiro argumento", 2)
        end
        if cond:len() ~= self:len() then
            error("smaug: where() — tamanhos diferentes ("..cond:len().." vs "..self:len()..")", 2)
        end
        local n = self:len()
        -- bool como dtype de VALOR fica no Anel 1 até 10.8 (sem risco int64).
        if self._dtype == "bool" then
            local vals = {}
            local is_series_other = type(other) == "table" and other._dtype ~= nil
            for i = 1, n do
                if cond:get(i) == true then
                    vals[i] = self:get(i)
                else
                    vals[i] = is_series_other and other:get(i) or (other == nil and NA or other)
                end
            end
            return Series.from_table(vals, self._dtype, self._name)
        end
        -- Anel 0: where = select(cond, self, other). Degrau sai.
        local b = resolve_operand(self._d, self._dtype, other, n, "where")
        return wrap(self._d.select(cond._c, self._c, b), self._dtype, self._name)
    end

    -- mask(cond, other): inverso de where — substitui onde cond=true.
    function methods.mask(self, cond, other)
        if type(cond) ~= "table" or cond._dtype ~= "bool" then
            error("smaug: mask() espera Series<bool> como primeiro argumento", 2)
        end
        if cond:len() ~= self:len() then
            error("smaug: mask() — tamanhos diferentes ("..cond:len().." vs "..self:len()..")", 2)
        end
        local n = self:len()
        if self._dtype == "bool" then
            local vals = {}
            local is_series_other = type(other) == "table" and other._dtype ~= nil
            for i = 1, n do
                if cond:get(i) == true then
                    vals[i] = is_series_other and other:get(i) or (other == nil and NA or other)
                else
                    vals[i] = self:get(i)
                end
            end
            return Series.from_table(vals, self._dtype, self._name)
        end
        -- Anel 0: mask = select(cond, other, self) (lados trocados).
        local a = resolve_operand(self._d, self._dtype, other, n, "mask")
        return wrap(self._d.select(cond._c, a, self._c), self._dtype, self._name)
    end

    -- Series.ifelse(cond, a, b): vetorizado — a onde cond=true, b onde false/NA.
    function Series.ifelse(cond, a, b)
        if type(cond) ~= "table" or cond._dtype ~= "bool" then
            error("smaug: ifelse() espera Series<bool> como primeiro argumento", 2)
        end
        local n    = cond:len()
        local is_a = type(a) == "table" and a._dtype ~= nil
        local is_b = type(b) == "table" and b._dtype ~= nil
        local dtype = "float64"
        if is_a     then dtype = a._dtype
        elseif is_b then dtype = b._dtype
        elseif type(a) == "string" or type(b) == "string" then dtype = "string"
        elseif type(a) == "boolean" or type(b) == "boolean" then dtype = "bool"
        elseif type(a) == "number" and a % 1 == 0 and
               (b == nil or (type(b) == "number" and b % 1 == 0)) then dtype = "int64"
        end
        -- bool como dtype de VALOR fica no Anel 1 até 10.8.
        if dtype == "bool" then
            local vals = {}
            for i = 1, n do
                if cond:get(i) == true then
                    vals[i] = is_a and a:get(i) or (a == nil and NA or a)
                else
                    vals[i] = is_b and b:get(i) or (b == nil and NA or b)
                end
            end
            return Series.from_table(vals, dtype)
        end
        -- Anel 0: ifelse = select(cond, a, b).
        local desc = DTYPES[dtype]
        local ra   = resolve_operand(desc, dtype, a, n, "ifelse")
        local rb   = resolve_operand(desc, dtype, b, n, "ifelse")
        return wrap(desc.select(cond._c, ra, rb), dtype)
    end

    -- isna(i) / notna(i): aliases de is_null / not is_null.
    function methods.isna(self, i)  return self:is_null(i) end
    function methods.notna(self, i) return not self:is_null(i) end

    -- =====================================================================
    -- nlargest / nsmallest
    -- =====================================================================

    function methods.nlargest(self, n)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: nlargest() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        if type(n) ~= "number" or n < 1 then
            error("smaug: nlargest() espera n >= 1", 2)
        end
        local arr, m = c_sorted_nonnull(self)
        local result = {}
        local take   = math.min(n, m)
        for i = 0, take - 1 do
            local v = tonumber(arr[m - 1 - i])
            result[i + 1] = (self._dtype == "int64") and math.floor(v) or v
        end
        return Series.from_table(result, self._dtype, self._name)
    end

    function methods.nsmallest(self, n)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: nsmallest() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        if type(n) ~= "number" or n < 1 then
            error("smaug: nsmallest() espera n >= 1", 2)
        end
        local arr, m = c_sorted_nonnull(self)
        local result = {}
        local take   = math.min(n, m)
        for i = 0, take - 1 do
            local v = tonumber(arr[i])
            result[i + 1] = (self._dtype == "int64") and math.floor(v) or v
        end
        return Series.from_table(result, self._dtype, self._name)
    end

    -- =====================================================================
    -- Funções matemáticas vetorizadas
    -- =====================================================================
    local _math_fns = {
        sin  = math.sin,  cos = math.cos, tan = math.tan,
        exp  = math.exp,  log = math.log, sqrt = math.sqrt,
    }
    for fname, fn in pairs(_math_fns) do
        methods[fname] = function(self)
            if self._dtype ~= "float64" and self._dtype ~= "int64" then
                error("smaug: "..fname.."() requer dtype numérico, não '"..self._dtype.."'", 2)
            end
            return self:map(function(v) return v ~= nil and fn(v) or nil end, "float64", self._name)
        end
    end
end
