-- lua/smaug/core/series/selection/_predicates.lua
--
-- Predicados e operações sobre duplicatas: between, isin, is_unique,
-- is_monotonic_*, equals, compare, idxmin/max, first/last_valid_index,
-- duplicated, drop_duplicates, combine_first, searchsorted, rep_each.
-- Recebe I com: I.methods, I.Series, I.NA
-- Produz em I: I.is_monotonic, I.dup_key
-- Contribui: todos os methods acima

return function(I)
    local methods = I.methods
    local Series  = I.Series
    local NA      = I.NA
    local wrap    = I.wrap

    -- =====================================================================
    -- F.2 — Predicados
    -- =====================================================================

    -- between(lo, hi, [inclusive]): máscara booleana lo ≤ x ≤ hi.
    function methods.between(self, lo, hi, inclusive)
        if self._dtype ~= "float64" and self._dtype ~= "int64"
           and self._dtype ~= "datetime" and self._dtype ~= "string" then
            error("smaug: between() requer dtype ordenável (numérico, datetime ou string), não '"
                  ..self._dtype.."'", 2)
        end
        inclusive = inclusive or "both"
        if inclusive ~= "both" and inclusive ~= "left"
           and inclusive ~= "right" and inclusive ~= "neither" then
            error("smaug: between() inclusive ∈ {both, left, right, neither}", 2)
        end
        local inc_lo = (inclusive == "both" or inclusive == "left")
        local inc_hi = (inclusive == "both" or inclusive == "right")
        local n    = self:len()
        local vals = {}
        for i = 1, n do
            local v = self:get(i)
            if v == nil then
                vals[i] = NA
            else
                local ge_lo = inc_lo and (v >= lo) or (v > lo)
                local le_hi = inc_hi and (v <= hi) or (v < hi)
                vals[i] = (ge_lo and le_hi)
            end
        end
        return Series.from_table(vals, "bool", self._name)
    end

    -- isin(values): máscara booleana — true onde o valor está em values.
    function methods.isin(self, values)
        if type(values) ~= "table" then
            error("smaug: isin() espera uma tabela de valores", 2)
        end
        local set = {}
        for _, val in ipairs(values) do set[tostring(val)] = true end
        local n    = self:len()
        local vals = {}
        for i = 1, n do
            local v = self:get(i)
            if v == nil then
                vals[i] = NA
            else
                vals[i] = set[tostring(v)] == true
            end
        end
        return Series.from_table(vals, "bool", self._name)
    end

    -- is_unique(): true se todos os valores não-nulos são distintos.
    function methods.is_unique(self)
        local seen = {}
        for i = 1, self:len() do
            local v = self:get(i)
            if v ~= nil then
                local k = tostring(v)
                if seen[k] then return false end
                seen[k] = true
            end
        end
        return true
    end

    -- Helper de monotonicidade. dir = "inc" ou "dec"; strict = true/false.
    local function is_monotonic(self, dir, strict)
        if self._dtype ~= "float64" and self._dtype ~= "int64"
           and self._dtype ~= "datetime" and self._dtype ~= "string" then
            error("smaug: is_monotonic requer dtype ordenável, não '"..self._dtype.."'", 3)
        end
        local n    = self:len()
        local prev = nil
        for i = 1, n do
            local v = self:get(i)
            if v == nil then return false end
            if prev ~= nil then
                if dir == "inc" then
                    if strict then if not (v > prev) then return false end
                    else if not (v >= prev) then return false end end
                else
                    if strict then if not (v < prev) then return false end
                    else if not (v <= prev) then return false end end
                end
            end
            prev = v
        end
        return true
    end
    I.is_monotonic = is_monotonic

    function methods.is_monotonic_increasing(self, strict)
        return is_monotonic(self, "inc", strict == true)
    end
    function methods.is_monotonic_decreasing(self, strict)
        return is_monotonic(self, "dec", strict == true)
    end

    -- equals(other): igualdade estrutural. NaN == NaN (estrutural, não IEEE 754).
    function methods.equals(self, other)
        if getmetatable(other) ~= Series then return false end
        if self._dtype ~= other._dtype then return false end
        if self:len() ~= other:len() then return false end
        for i = 1, self:len() do
            local a, b = self:get(i), other:get(i)
            if (a == nil) ~= (b == nil) then return false end
            if a ~= nil then
                if a ~= b and not (a ~= a and b ~= b) then return false end
            end
        end
        return true
    end

    -- compare(other): diferenças posicionais → DataSet {i, self, other}.
    function methods.compare(self, other)
        if getmetatable(other) ~= Series then
            error("smaug: compare() espera outra Series", 2)
        end
        if self._dtype ~= other._dtype then
            error("smaug: compare() — dtypes diferentes ('"..self._dtype.."' vs '"
                  ..other._dtype.."')", 2)
        end
        if self:len() ~= other:len() then
            error("smaug: compare() — tamanhos diferentes ("..self:len().." vs "
                  ..other:len()..")", 2)
        end
        local idx, self_vals, other_vals = {}, {}, {}
        for i = 1, self:len() do
            local a, b = self:get(i), other:get(i)
            local differ
            if (a == nil) ~= (b == nil) then
                differ = true
            elseif a == nil then
                differ = false
            else
                differ = (a ~= b) and not (a ~= a and b ~= b)
            end
            if differ then
                local m = #idx + 1
                idx[m]        = i
                self_vals[m]  = (a == nil) and NA or a
                other_vals[m] = (b == nil) and NA or b
            end
        end
        local DataSet = require("smaug.core.dataset")
        return DataSet.from_columns({
            {"i",     idx,        "int64"},
            {"self",  self_vals,  self._dtype},
            {"other", other_vals, self._dtype},
        }, (self._name or "series") .. "_compare")
    end

    -- idxmin/idxmax: aliases de argmin/argmax.
    function methods.idxmin(self) return self:argmin() end
    function methods.idxmax(self) return self:argmax() end

    -- first_valid_index(): índice 1-based do 1º valor não-nulo.
    function methods.first_valid_index(self)
        for i = 1, self:len() do
            if self:get(i) ~= nil then return i end
        end
        return nil
    end

    -- last_valid_index(): índice 1-based do último valor não-nulo.
    function methods.last_valid_index(self)
        for i = self:len(), 1, -1 do
            if self:get(i) ~= nil then return i end
        end
        return nil
    end

    -- =====================================================================
    -- F.6 — Duplicatas e operações binárias
    -- =====================================================================

    -- Chave de igualdade consistente com unique/nunique. Null tem chave própria.
    local function dup_key(v)
        if v == nil then return "\0NULL\0" end
        return type(v) .. ":" .. tostring(v)
    end
    I.dup_key = dup_key

    -- duplicated([keep]): Series<bool> marcando posições duplicadas.
    -- keep="first" (default), "last", "none".
    function methods.duplicated(self, keep)
        keep = keep or "first"
        if keep ~= "first" and keep ~= "last" and keep ~= "none" then
            error("smaug: duplicated() keep ∈ {first, last, none}", 2)
        end
        local n    = self:len()
        local vals = {}

        if keep == "first" then
            local seen = {}
            for i = 1, n do
                local k = dup_key(self:get(i))
                if seen[k] then vals[i] = true else seen[k] = true; vals[i] = false end
            end
        elseif keep == "last" then
            local seen = {}
            for i = n, 1, -1 do
                local k = dup_key(self:get(i))
                if seen[k] then vals[i] = true else seen[k] = true; vals[i] = false end
            end
        else  -- none
            local count = {}
            for i = 1, n do
                local k = dup_key(self:get(i))
                count[k] = (count[k] or 0) + 1
            end
            for i = 1, n do
                vals[i] = count[dup_key(self:get(i))] > 1
            end
        end
        return Series.from_table(vals, "bool", self._name)
    end

    -- drop_duplicates([keep]): nova Series sem as posições duplicadas.
    function methods.drop_duplicates(self, keep)
        local mask = self:duplicated(keep)
        local vals = {}
        for i = 1, self:len() do
            if mask:get(i) == false then
                local v = self:get(i)
                vals[#vals + 1] = (v == nil) and NA or v
            end
        end
        return Series.from_table(vals, self._dtype, self._name)
    end

    -- combine_first(other): onde self é null, usa o valor de other.
    function methods.combine_first(self, other)
        if getmetatable(other) ~= Series then
            error("smaug: combine_first() espera outra Series", 2)
        end
        if self._dtype ~= other._dtype then
            error("smaug: combine_first() — dtypes diferentes ('"..self._dtype
                  .."' vs '"..other._dtype.."')", 2)
        end
        if self:len() ~= other:len() then
            error("smaug: combine_first() — tamanhos diferentes ("..self:len()
                  .." vs "..other:len()..")", 2)
        end

        -- bool continua no Anel 1 até o 10.8 (tipo paralelo, arrays crus). Sem
        -- risco int64 → sem degrau; loop get/set direto.
        if self._dtype == "bool" then
            local vals = {}
            for i = 1, self:len() do
                local v = self:get(i)
                if v == nil then
                    local o = other:get(i)
                    vals[i] = (o == nil) and NA or o
                else
                    vals[i] = v
                end
            end
            return Series.from_table(vals, self._dtype, self._name)
        end

        -- Anel 0: delega a coalesce série+série (null-mask posicional). O degrau
        -- sai — int64 > 2^53 preservado exato, sem round-trip por get().
        local r = self._d.coalesce(self._c, other._c)
        return wrap(r, self._dtype, self._name)
    end

    -- searchsorted(value, [side]): posição de inserção (1-based).
    -- Exige série ordenada crescente. side="left" (default) ou "right".
    function methods.searchsorted(self, value, side)
        if self._dtype ~= "float64" and self._dtype ~= "int64"
           and self._dtype ~= "datetime" and self._dtype ~= "string" then
            error("smaug: searchsorted() requer dtype ordenável, não '"..self._dtype.."'", 2)
        end
        side = side or "left"
        if side ~= "left" and side ~= "right" then
            error("smaug: searchsorted() side ∈ {left, right}", 2)
        end
        if not self:is_monotonic_increasing() then
            error("smaug: searchsorted() requer série ordenada crescente (sem nulos)", 2)
        end
        local lo, hi = 1, self:len() + 1
        while lo < hi do
            local mid      = math.floor((lo + hi) / 2)
            local v        = self:get(mid)
            local go_right
            if side == "left" then
                go_right = (v < value)
            else
                go_right = (v <= value)
            end
            if go_right then lo = mid + 1 else hi = mid end
        end
        return lo
    end

    -- rep_each(n): repete cada elemento n vezes.
    -- n: inteiro escalar >= 0, OU Series<int64> com contagem por elemento.
    function methods.rep_each(self, n)
        local len  = self:len()
        local vals = {}
        local counts

        if type(n) == "number" then
            if n < 0 or n ~= math.floor(n) then
                error("smaug: rep_each(n) — n deve ser inteiro >= 0", 2)
            end
            counts = nil
        elseif getmetatable(n) == Series then
            if n._dtype ~= "int64" then
                error("smaug: rep_each(Series) requer Series<int64>", 2)
            end
            if n:len() ~= len then
                error("smaug: rep_each(Series) — tamanho diferente ("..n:len()
                      .." vs "..len..")", 2)
            end
            counts = n
        else
            error("smaug: rep_each(n) — n deve ser inteiro ou Series<int64>", 2)
        end

        for i = 1, len do
            local times
            if counts == nil then
                times = n
            else
                times = counts:get(i)
                if times == nil or times < 0 then
                    error("smaug: rep_each — contagem inválida na posição "..i, 2)
                end
            end
            local v = self:get(i)
            for _ = 1, times do
                vals[#vals + 1] = (v == nil) and NA or v
            end
        end
        return Series.from_table(vals, self._dtype, self._name)
    end
end
