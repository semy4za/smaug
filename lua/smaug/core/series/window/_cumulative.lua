-- lua/smaug/core/series/window/_cumulative.lua
--
-- Operações de janela posicional: cumsum, cumprod, diff, shift, ffill, bfill,
-- cummin, cummax, argmin, argmax.
-- Grupo A e parcialmente Grupo B do Ring 0 (Fase 3) — delegam para C via DTYPES.
-- Recebe I com: I.methods, I.Series, I.C, I.NA, I.wrap
-- Contribui: methods.cumsum, cumprod, diff, shift, ffill, bfill,
--            cummin, cummax, argmin, argmax

return function(I)
    local methods = I.methods
    local Series  = I.Series
    local C       = I.C
    local NA      = I.NA
    local wrap    = I.wrap

    -- cumsum(): soma cumulativa. Null na posição i → null em [i, n-1].
    function methods.cumsum(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: cumsum() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        local r = self._d.cumsum(self._c)
        if r == nil then error("smaug: cumsum falhou (OOM)", 2) end
        return wrap(r, self._dtype, self._name)
    end

    -- cumprod(): produto cumulativo.
    function methods.cumprod(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: cumprod() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        local r = self._d.cumprod(self._c)
        if r == nil then error("smaug: cumprod falhou (OOM)", 2) end
        return wrap(r, self._dtype, self._name)
    end

    -- diff(periods): diferença entre elemento i e elemento i-periods.
    -- Numérico (f64/i64): C. Datetime: Lua via smaug_dt_diff_ms.
    function methods.diff(self, periods)
        if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
            error("smaug: diff() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
        end
        periods = periods or 1
        if periods < 1 then error("smaug: diff() requer periods >= 1", 2) end
        -- datetime: diferença de epochs via smaug_dt_diff_ms → int64 (ms)
        if self._dtype == "datetime" then
            local n    = self:len()
            local vals = {}
            for i = 1, n do
                if i <= periods then
                    vals[i] = NA
                else
                    local a = self:get(i)
                    local b = self:get(i - periods)
                    vals[i] = (a ~= nil and b ~= nil) and tonumber(C.smaug_dt_diff_ms(a, b)) or NA
                end
            end
            return Series.from_table(vals, "int64", self._name)
        end
        local r = self._d.diff(self._c, periods)
        if r == nil then error("smaug: diff falhou (OOM)", 2) end
        return wrap(r, self._dtype, self._name)
    end

    -- shift(periods): desloca os valores `periods` posições.
    -- periods > 0: C (caso comum). periods <= 0: Lua.
    function methods.shift(self, periods)
        periods = periods or 1
        if type(periods) ~= "number" or periods % 1 ~= 0 then
            error("smaug: shift() requer periods inteiro", 2)
        end
        if periods > 0 and self._d.shift then
            local r = self._d.shift(self._c, periods)
            if r == nil then error("smaug: shift falhou (OOM)", 2) end
            return wrap(r, self._dtype, self._name)
        end
        -- Lua: periods <= 0 ou dtype sem C (datetime/string/bool)
        local n    = self:len()
        local vals = {}
        for i = 1, n do
            local src = i - periods
            if src < 1 or src > n then
                vals[i] = NA
            else
                local v = self:get(src)
                vals[i] = (v == nil) and NA or v
            end
        end
        return Series.from_table(vals, self._dtype, self._name)
    end

    -- ffill(): preenche nulos com o último valor válido anterior.
    -- Numérico: C. Outros dtypes: Lua.
    function methods.ffill(self)
        if self._d.ffill then
            local r = self._d.ffill(self._c)
            if r == nil then error("smaug: ffill falhou (OOM)", 2) end
            return wrap(r, self._dtype, self._name)
        end
        local n    = self:len()
        local vals = {}
        local last = NA
        for i = 1, n do
            local v = self:get(i)
            if v ~= nil then last = v end
            vals[i] = last
        end
        return Series.from_table(vals, self._dtype, self._name)
    end

    -- bfill(): preenche nulos com o próximo valor válido seguinte.
    function methods.bfill(self)
        if self._d.bfill then
            local r = self._d.bfill(self._c)
            if r == nil then error("smaug: bfill falhou (OOM)", 2) end
            return wrap(r, self._dtype, self._name)
        end
        local n        = self:len()
        local vals     = {}
        local next_val = NA
        for i = n, 1, -1 do
            local v = self:get(i)
            if v ~= nil then next_val = v end
            vals[i] = next_val
        end
        return Series.from_table(vals, self._dtype, self._name)
    end

    -- cummin(): mínimo cumulativo. Numérico → C. Datetime → Lua.
    function methods.cummin(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
            error("smaug: cummin() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
        end
        if self._d.cummin then
            local r = self._d.cummin(self._c)
            if r == nil then error("smaug: cummin falhou (OOM)", 2) end
            return wrap(r, self._dtype, self._name)
        end
        -- Lua: datetime (e qualquer dtype sem C)
        local n, vals = self:len(), {}
        local cur = nil
        for i = 1, n do
            local v = self:get(i)
            if v == nil then
                vals[i] = NA
            else
                cur = (cur == nil or v < cur) and v or cur
                vals[i] = cur
            end
        end
        return Series.from_table(vals, self._dtype, self._name)
    end

    -- cummax(): máximo cumulativo. Mesmo contrato de cummin.
    function methods.cummax(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
            error("smaug: cummax() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
        end
        if self._d.cummax then
            local r = self._d.cummax(self._c)
            if r == nil then error("smaug: cummax falhou (OOM)", 2) end
            return wrap(r, self._dtype, self._name)
        end
        local n, vals = self:len(), {}
        local cur = nil
        for i = 1, n do
            local v = self:get(i)
            if v == nil then
                vals[i] = NA
            else
                cur = (cur == nil or v > cur) and v or cur
                vals[i] = cur
            end
        end
        return Series.from_table(vals, self._dtype, self._name)
    end

    -- argmin(): índice 1-based do mínimo (ignora nulos). nil se vazia ou toda nula.
    -- f64/i64: C. datetime: Lua.
    function methods.argmin(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
            error("smaug: argmin() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
        end
        if self._d.argmin then
            local idx = self._d.argmin(self._c)
            local n   = tonumber(idx)
            if n == nil or n >= tonumber(self._c.size) then return nil end
            return n + 1   -- 0-based → 1-based
        end
        local best_v, best_i = nil, nil
        for i = 1, self:len() do
            local v = self:get(i)
            if v ~= nil and (best_v == nil or v < best_v) then
                best_v, best_i = v, i
            end
        end
        return best_i
    end

    -- argmax(): índice 1-based do máximo (ignora nulos).
    function methods.argmax(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
            error("smaug: argmax() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
        end
        if self._d.argmax then
            local idx = self._d.argmax(self._c)
            local n   = tonumber(idx)
            if n == nil or n >= tonumber(self._c.size) then return nil end
            return n + 1
        end
        local best_v, best_i = nil, nil
        for i = 1, self:len() do
            local v = self:get(i)
            if v ~= nil and (best_v == nil or v > best_v) then
                best_v, best_i = v, i
            end
        end
        return best_i
    end
end
