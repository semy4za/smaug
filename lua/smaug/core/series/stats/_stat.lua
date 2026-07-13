-- lua/smaug/core/series/stats/_stat.lua
--
-- Estatísticas descritivas e helpers de ordenação.
-- Recebe I com: I.methods, I.Series, I.C, I.ffi, I.NA, I.is_nan
-- Produz em I: I.c_sorted_nonnull, I.median_of_sorted, I.quantile_of_sorted,
--              I.collect_sorted, I.median_sorted, I.quantile_sorted
-- Contribui: methods.unique, nunique, value_counts, prod, median, quantile,
--            mode, describe

return function(I)
    local methods = I.methods
    local Series  = I.Series
    local C       = I.C
    local ffi     = I.ffi
    local NA      = I.NA
    local is_nan  = I.is_nan

    -- =====================================================================
    -- Helpers de ordenação/sorted (Grupo B Ring 0)
    -- =====================================================================

    -- c_sorted_nonnull: chama sorted_nonnull C conforme o dtype.
    -- Devolve (double_array, n). Uniforme para f64 e i64.
    local function c_sorted_nonnull(self)
        local out_n = ffi.new("size_t[1]")
        if self._dtype == "float64" then
            local ptr = C.smaug_f64_sorted_nonnull(self._c, out_n)
            local n = tonumber(out_n[0])
            if ptr == nil or n == 0 then return nil, 0 end
            local arr = ffi.new("double[?]", n)
            ffi.copy(arr, ptr, n * ffi.sizeof("double"))
            C.smaug_free(ptr)
            return arr, n
        else  -- int64
            local iptr = C.smaug_i64_sorted_nonnull(self._c, out_n)
            local n = tonumber(out_n[0])
            if iptr == nil or n == 0 then
                if iptr ~= nil then C.smaug_free(iptr) end
                return nil, 0
            end
            local arr = ffi.new("double[?]", n)
            for i = 0, n - 1 do arr[i] = tonumber(iptr[i]) end
            C.smaug_free(iptr)
            return arr, n
        end
    end
    I.c_sorted_nonnull = c_sorted_nonnull

    -- median_of_sorted: mediana de double* ordenado (interpolação linear).
    local function median_of_sorted(ptr, n)
        if n == 0 then return nil end
        local m = math.floor(n / 2)
        if n % 2 == 1 then return tonumber(ptr[m]) end
        return (tonumber(ptr[m - 1]) + tonumber(ptr[m])) / 2
    end
    I.median_of_sorted = median_of_sorted

    -- quantile_of_sorted: quantil de double* ordenado (0 ≤ q ≤ 1, interpolação linear).
    local function quantile_of_sorted(ptr, n, q)
        if n == 0 then return nil end
        if n == 1 then return tonumber(ptr[0]) end
        local pos  = q * (n - 1)
        local lo   = math.floor(pos)
        local frac = pos - lo
        local hi   = lo + 1
        if hi >= n then return tonumber(ptr[n - 1]) end
        return tonumber(ptr[lo]) + frac * (tonumber(ptr[hi]) - tonumber(ptr[lo]))
    end
    I.quantile_of_sorted = quantile_of_sorted

    -- collect_sorted: fallback Lua para dtypes sem C (datetime, string).
    local function collect_sorted(self)
        local n, vals = self:len(), {}
        for i = 1, n do
            local v = self:get(i)
            if v ~= nil then vals[#vals+1] = v end
        end
        table.sort(vals)
        return vals
    end
    I.collect_sorted = collect_sorted

    -- median_sorted: mediana de tabela Lua ordenada (usada por mad()).
    local function median_sorted(vals)
        local n = #vals
        if n == 0 then return nil end
        local m = math.floor(n / 2)
        return (n % 2 == 1) and vals[m+1] or (vals[m] + vals[m+1]) / 2
    end
    I.median_sorted = median_sorted

    -- quantile_sorted: quantil de tabela Lua ordenada.
    local function quantile_sorted(vals, q)
        local n = #vals
        if n == 0 then return nil end
        if n == 1 then return vals[1] end
        local pos  = q * (n - 1)
        local lo   = math.floor(pos)
        local frac = pos - lo
        local hi   = lo + 1
        if hi >= n then return vals[n] end
        return vals[lo+1] + frac * (vals[hi+1] - vals[lo+1])
    end
    I.quantile_sorted = quantile_sorted

    -- =====================================================================
    -- Análise de distintos
    -- =====================================================================

    -- unique(): nova Series com os valores distintos na ordem de primeira aparição.
    function methods.unique(self)
        local n    = self:len()
        local seen = {}
        local vals = {}
        for i = 1, n do
            local v   = self:get(i)
            local key = (v == nil) and "\0NULL\0" or (type(v)..":"..tostring(v))
            if not seen[key] then
                seen[key]     = true
                vals[#vals+1] = (v == nil) and NA or v
            end
        end
        return Series.from_table(vals, self._dtype, self._name)
    end

    -- nunique(): contagem de valores distintos não-nulos.
    function methods.nunique(self)
        local seen = {}
        local n    = self:len()
        local c    = 0
        for i = 1, n do
            local v = self:get(i)
            if v ~= nil then
                local key = type(v)..":"..tostring(v)
                if not seen[key] then seen[key] = true; c = c + 1 end
            end
        end
        return c
    end

    -- value_counts(): DataSet com colunas "value" e "count", ordenado por count desc.
    -- Nulos são excluídos. require circular resolvido via chamada tardia.
    function methods.value_counts(self)
        local n     = self:len()
        local cnt   = {}
        local order = {}
        for i = 1, n do
            local v = self:get(i)
            if v ~= nil then
                local key = type(v)..":"..tostring(v)
                if not cnt[key] then
                    cnt[key]         = 0
                    order[#order+1] = {key=key, val=v}
                end
                cnt[key] = cnt[key] + 1
            end
        end
        table.sort(order, function(a, b) return cnt[a.key] > cnt[b.key] end)
        local vals, counts = {}, {}
        for _, item in ipairs(order) do
            vals[#vals+1]   = item.val
            counts[#counts+1] = cnt[item.key]
        end
        local DataSet = require("smaug.core.dataset")
        local ds = DataSet.new("value_counts")
        ds:add_column("value", Series.from_table(vals,   self._dtype, "value"))
        ds:add_column("count", Series.from_table(counts, "int64",     "count"))
        return ds
    end

    -- =====================================================================
    -- Estatísticas
    -- =====================================================================

    -- prod([ignore_na]): produto de todos os valores.
    function methods.prod(self, ignore_na, min_count)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: prod() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        -- 5.5: min_count opt-in. Default (0) preserva o comportamento atual.
        if min_count and min_count > 0 and self:count_nonnull() < min_count then return nil end
        ignore_na = (ignore_na == nil) and true or ignore_na
        local p, n = 1, 0
        for i = 1, self:len() do
            local v = self:get(i)
            if v == nil then
                if not ignore_na then return nil end
            else
                p = p * v; n = n + 1
            end
        end
        return n > 0 and p or nil
    end

    -- median([ignore_na]): mediana (ignora nulos por padrão). float64.
    function methods.median(self, ignore_na)
        if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
            error("smaug: median() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
        end
        ignore_na = (ignore_na == nil) and true or ignore_na
        if not ignore_na then
            for i = 1, self:len() do
                if self:get(i) == nil then return nil end
            end
        end
        if self._dtype == "datetime" then
            return median_sorted(collect_sorted(self))
        end
        local arr, n = c_sorted_nonnull(self)
        return median_of_sorted(arr, n)
    end

    -- quantile(q, [ignore_na]): percentil 0 ≤ q ≤ 1. Interpolação linear.
    function methods.quantile(self, q, ignore_na)
        if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
            error("smaug: quantile() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
        end
        if type(q) ~= "number" or q < 0 or q > 1 then
            error("smaug: quantile() espera 0 ≤ q ≤ 1", 2)
        end
        ignore_na = (ignore_na == nil) and true or ignore_na
        if not ignore_na then
            for i = 1, self:len() do
                if self:get(i) == nil then return nil end
            end
        end
        if self._dtype == "datetime" then
            return quantile_sorted(collect_sorted(self), q)
        end
        local arr, n = c_sorted_nonnull(self)
        return quantile_of_sorted(arr, n, q)
    end

    -- mode(): valor mais frequente (ignora nulos). Empate: primeiro em ordem de aparição.
    function methods.mode(self)
        if self._dtype == "bool" then
            error("smaug: mode() não suportado para bool", 2)
        end
        local freq  = {}
        local order = {}
        for i = 1, self:len() do
            local v = self:get(i)
            if v ~= nil then
                local k = tostring(v)
                if not freq[k] then freq[k] = 0; order[#order+1] = v end
                freq[k] = freq[k] + 1
            end
        end
        if #order == 0 then return nil end
        local best, best_f = order[1], 0
        for _, v in ipairs(order) do
            local f = freq[tostring(v)]
            if f > best_f then best = v; best_f = f end
        end
        return best
    end

    -- =====================================================================
    -- describe
    -- =====================================================================
    function methods.describe(self)
        local n     = self:len()
        local nulls = n - self:count_nonnull()

        if self._dtype == "bool" then
            -- count_true desce ao Anel 0 (smaug_bool_series_count_true, ignora NA);
            -- nulos já vêm de count_nonnull. Sem loop Lua/travessia FFI por elemento.
            local count_true = self:count_true()
            return {
                count       = n - nulls,
                nulls       = nulls,
                count_true  = count_true,
                count_false = (n - nulls) - count_true,
            }
        end

        if self._dtype == "datetime" then
            local min_ep, max_ep = nil, nil
            for i = 1, n do
                local v = self:get(i)
                if v ~= nil then
                    if min_ep == nil or v < min_ep then min_ep = v end
                    if max_ep == nil or v > max_ep then max_ep = v end
                end
            end
            local buf = ffi.new("char[26]")
            local function fmt(ep)
                if ep == nil then return nil end
                C.smaug_dt_format(ep, buf, 26)
                return ffi.string(buf)
            end
            return {
                dtype = "datetime",
                count = n - nulls,
                nulls = nulls,
                min   = fmt(min_ep),
                max   = fmt(max_ep),
            }
        end

        if self._dtype == "string" then
            local freq = {}
            local top, top_freq = nil, 0
            for i = 1, n do
                local v = self:get(i)
                if v ~= nil then
                    freq[v] = (freq[v] or 0) + 1
                    if freq[v] > top_freq then top, top_freq = v, freq[v] end
                end
            end
            return {
                count  = n - nulls,
                nulls  = nulls,
                unique = (function()
                    local u = 0
                    for _ in pairs(freq) do u = u + 1 end
                    return u
                end)(),
                top    = top,
                freq   = top_freq > 0 and top_freq or nil,
            }
        end

        -- numérico
        local vals = {}
        for i = 1, n do
            local v = self:get(i)
            if v ~= nil then vals[#vals + 1] = v end
        end
        table.sort(vals)
        local m = #vals
        local function pct(p)
            if m == 0 then return nil end
            if m == 1 then return vals[1] end
            local rank = p * (m - 1) + 1
            local lo   = math.floor(rank)
            local frac = rank - lo
            if lo >= m then return vals[m] end
            return vals[lo] + frac * (vals[lo + 1] - vals[lo])
        end
        return {
            count   = m,
            nulls   = nulls,
            mean    = self:mean(),
            std     = self:std(),
            min     = self:min(),
            ["25%"] = pct(0.25),
            ["50%"] = pct(0.50),
            ["75%"] = pct(0.75),
            max     = self:max(),
        }
    end
end
