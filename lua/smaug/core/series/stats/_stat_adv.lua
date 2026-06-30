-- lua/smaug/core/series/stats/_stat_adv.lua
--
-- Estatísticas avançadas: cov, corr, autocorr, dot, pct_change, rank, pct_rank,
-- skew, kurtosis, mad, sem.
-- Recebe I com: I.methods, I.Series, I.C, I.ffi, I.NA, I.NAN, I.is_nan,
--               I.c_sorted_nonnull, I.median_of_sorted, I.median_sorted
-- Contribui: methods.cov, corr, autocorr, dot, pct_change, rank, pct_rank,
--            skew, kurtosis, mad, sem

return function(I)
    local methods          = I.methods
    local Series           = I.Series
    local C                = I.C
    local ffi              = I.ffi
    local NA               = I.NA
    local NAN              = I.NAN      -- produção central de NaN (não 0/0 cru)
    local is_nan           = I.is_nan   -- teste central de NaN (não v ~= v cru)
    local c_sorted_nonnull = I.c_sorted_nonnull
    local median_of_sorted = I.median_of_sorted
    local median_sorted    = I.median_sorted

    -- =====================================================================
    -- Helper: pares não-nulos (para cov/corr)
    -- =====================================================================
    local function paired_nonnull(a, b)
        if getmetatable(b) ~= Series then
            error("smaug: esperado outra Series como argumento", 3)
        end
        if a:len() ~= b:len() then
            error("smaug: séries de tamanhos diferentes ("..a:len().." vs "..b:len()..")", 3)
        end
        local xs, ys, m = {}, {}, 0
        for i = 1, a:len() do
            local x, y = a:get(i), b:get(i)
            if x ~= nil and y ~= nil then
                m = m + 1
                xs[m] = x; ys[m] = y
            end
        end
        return xs, ys, m
    end

    -- =====================================================================
    -- F.1 — Pacote estatístico
    -- =====================================================================

    -- cov(other): covariância amostral de Pearson (divide por n-1).
    function methods.cov(self, other)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: cov() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        local xs, ys, m = paired_nonnull(self, other)
        if m < 2 then return NAN end
        local mx, my = 0, 0
        for i = 1, m do mx = mx + xs[i]; my = my + ys[i] end
        mx = mx / m; my = my / m
        local acc = 0
        for i = 1, m do acc = acc + (xs[i] - mx) * (ys[i] - my) end
        return acc / (m - 1)
    end

    -- corr(other): correlação de Pearson ∈ [-1, 1].
    function methods.corr(self, other)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: corr() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        local xs, ys, m = paired_nonnull(self, other)
        if m < 2 then return NAN end
        local mx, my = 0, 0
        for i = 1, m do mx = mx + xs[i]; my = my + ys[i] end
        mx = mx / m; my = my / m
        local sxy, sxx, syy = 0, 0, 0
        for i = 1, m do
            local dx, dy = xs[i] - mx, ys[i] - my
            sxy = sxy + dx * dy
            sxx = sxx + dx * dx
            syy = syy + dy * dy
        end
        local denom = math.sqrt(sxx * syy)
        if denom == 0 then return NAN end
        return sxy / denom
    end

    -- autocorr([lag]): correlação da série com ela mesma deslocada lag (default 1).
    function methods.autocorr(self, lag)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: autocorr() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        lag = lag or 1
        return self:corr(self:shift(lag))
    end

    -- dot(other): produto interno Σ xᵢ·yᵢ. Qualquer par com null → nil.
    function methods.dot(self, other)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: dot() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        if getmetatable(other) ~= Series then
            error("smaug: dot() espera outra Series como argumento", 2)
        end
        if self:len() ~= other:len() then
            error("smaug: dot() — tamanhos diferentes ("..self:len().." vs "..other:len()..")", 2)
        end
        local acc = 0
        for i = 1, self:len() do
            local x, y = self:get(i), other:get(i)
            if x == nil or y == nil then return nil end
            acc = acc + x * y
        end
        return acc
    end

    -- pct_change([periods]): variação percentual = (xᵢ - xᵢ₋ₚ) / xᵢ₋ₚ.
    -- Divisor zero → NA. Resultado sempre float64.
    function methods.pct_change(self, periods)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: pct_change() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        periods = periods or 1
        if periods < 1 then error("smaug: pct_change() requer periods >= 1", 2) end
        local n    = self:len()
        local vals = {}
        for i = 1, n do
            if i <= periods then
                vals[i] = NA
            else
                local cur  = self:get(i)
                local prev = self:get(i - periods)
                if cur == nil or prev == nil or prev == 0 then
                    vals[i] = NA
                else
                    vals[i] = (cur - prev) / prev
                end
            end
        end
        return Series.from_table(vals, "float64", self._name)
    end

    -- =====================================================================
    -- rank e pct_rank (Grupo B Ring 0)
    -- =====================================================================

    -- rank([method]): posição de cada valor no ranking (1-based, ignora nulos → NA).
    -- method: "average" (default), "min", "max", "first". Delega ao C.
    -- Item 7.3: todos os dtypes ordenáveis (f64/i64/dt/str/bool) têm rank no C;
    -- a Lua delega via self._d.rank, sem branch por dtype. Erro por capacidade.
    function methods.rank(self, method)
        if not self._d.rank then
            error("smaug: rank() não se aplica a dtype '"..self._dtype.."'", 2)
        end
        method = method or "average"
        local method_int
        if     method == "average" then method_int = 0
        elseif method == "min"     then method_int = 1
        elseif method == "max"     then method_int = 2
        elseif method == "first"   then method_int = 3
        else error("smaug: rank() method ∈ {average, min, max, first}", 2) end

        local raw = self._d.rank(self._c, method_int)
        if raw == nil then error("smaug: rank falhou (OOM)", 2) end

        local n   = self:len()
        local out = Series.new("float64", n, self._name)
        for i = 0, n - 1 do
            local v = tonumber(raw[i])
            if is_nan(v) then  -- NAN → null
                out:set_null(i + 1)
            else
                out:set(i + 1, v)
            end
        end
        C.smaug_free(raw)
        return out
    end

    -- pct_rank(): rank normalizado para [0, 1].
    function methods.pct_rank(self)
        local r = self:rank("average")
        local n = tonumber(self._d.count_nonnull and self._d.count_nonnull(self._c) or self:count_nonnull())
        if n == 0 then return r end
        return r:map(function(v) return v ~= nil and (v / n) or nil end, "float64", self._name)
    end

    -- =====================================================================
    -- skew, kurtosis, mad, sem
    -- =====================================================================

    -- skew(): assimetria amostral (denominador n-1). nil se < 3 valores.
    function methods.skew(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: skew() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        local arr, n = c_sorted_nonnull(self)
        if n < 3 then return nil end
        local mean = 0
        for i = 0, n - 1 do mean = mean + tonumber(arr[i]) end
        mean = mean / n
        local m2, m3 = 0, 0
        for i = 0, n - 1 do
            local d = tonumber(arr[i]) - mean
            m2 = m2 + d*d
            m3 = m3 + d*d*d
        end
        m2 = m2 / n; m3 = m3 / n
        if m2 == 0 then return 0 end
        local g1 = (m3 / (m2 ^ 1.5)) * (math.sqrt(n*(n-1)) / (n-2))
        return g1
    end

    -- kurtosis(): curtose amostral (excess kurtosis, base normal = 0).
    function methods.kurtosis(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: kurtosis() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        local arr, n = c_sorted_nonnull(self)
        if n < 4 then return nil end
        local mean = 0
        for i = 0, n - 1 do mean = mean + tonumber(arr[i]) end
        mean = mean / n
        local m2, m4 = 0, 0
        for i = 0, n - 1 do
            local d  = tonumber(arr[i]) - mean
            local d2 = d * d
            m2 = m2 + d2
            m4 = m4 + d2 * d2
        end
        m2 = m2 / n; m4 = m4 / n
        if m2 == 0 then return 0 end
        local kurt = (n*(n+1) / ((n-1)*(n-2)*(n-3))) * (m4/(m2*m2)) - 3*(n-1)^2/((n-2)*(n-3))
        return kurt
    end

    -- mad(): desvio absoluto mediano (robusto a outliers).
    function methods.mad(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: mad() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        local arr, n = c_sorted_nonnull(self)
        if n == 0 then return nil end
        local med  = median_of_sorted(arr, n)
        local devs = {}
        for i = 0, n - 1 do devs[i + 1] = math.abs(tonumber(arr[i]) - med) end
        table.sort(devs)
        return median_sorted(devs)
    end

    -- sem(): erro padrão da média = std / sqrt(n).
    function methods.sem(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: sem() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        local arr, n = c_sorted_nonnull(self)
        if n < 2 then return nil end
        local mean = 0
        for i = 0, n - 1 do mean = mean + tonumber(arr[i]) end
        mean = mean / n
        local s2 = 0
        for i = 0, n - 1 do local d = tonumber(arr[i]) - mean; s2 = s2 + d*d end
        local std = math.sqrt(s2 / (n - 1))
        return std / math.sqrt(n)
    end
end
