-- lua/smaug/core/series/window/_rolling.lua
--
-- SeriesRolling e SeriesExpanding: janela deslizante e janela crescente.
-- Grupo C Ring 0 (sum/mean/min/max com C); std/var/count/median/quantile em Lua.
-- Recebe I com: I.methods, I.Series, I.wrap, I.NA, I.median_sorted
-- Produz em I: I.SeriesRolling, I.SeriesExpanding
-- Contribui: methods.rolling, methods.expanding

return function(I)
    local methods       = I.methods
    local Series        = I.Series
    local wrap          = I.wrap
    local NA            = I.NA
    local median_sorted = I.median_sorted

    -- =====================================================================
    -- SeriesRolling
    -- =====================================================================
    local SeriesRolling = {}
    SeriesRolling.__index = SeriesRolling
    I.SeriesRolling = SeriesRolling

    -- _agg: agregação genérica com suporte a min_periods.
    -- min_periods: mínimo de não-nulos necessários dentro da janela.
    function SeriesRolling:_agg(fn, out_dtype)
        local col   = self._s
        local n     = col:len()
        local w     = self._window
        local min_p = self._min_periods or 1
        local vals  = {}
        for i = 1, n do
            local wstart = math.max(1, i - w + 1)
            if i < w and not self._min_periods then
                vals[i] = NA
            else
                local wv = {}
                for j = wstart, i do
                    local v = col:get(j)
                    if v ~= nil then wv[#wv+1] = v end
                end
                local res = (#wv >= min_p) and fn(wv) or nil
                vals[i] = (res ~= nil) and res or NA
            end
        end
        return Series.from_table(vals, out_dtype or col._dtype, col._name)
    end

    function SeriesRolling:sum()
        if self._s._d.rolling_sum then
            local r = self._s._d.rolling_sum(self._s._c, self._window)
            if r == nil then error("smaug: rolling:sum falhou (OOM)", 2) end
            return wrap(r, self._s._dtype, self._s._name)
        end
        return self:_agg(function(vs)
            local s = 0; for _, v in ipairs(vs) do s = s + v end; return s
        end)
    end

    function SeriesRolling:mean()
        if self._s._d.rolling_mean then
            local r = self._s._d.rolling_mean(self._s._c, self._window)
            if r == nil then error("smaug: rolling:mean falhou (OOM)", 2) end
            return wrap(r, "float64", self._s._name)
        end
        local col = self._s
        local n   = col:len()
        local w   = self._window
        local vals = {}
        for i = 1, n do
            if i < w then
                vals[i] = NA
            else
                local wv = {}
                for j = i - w + 1, i do
                    local v = col:get(j)
                    if v ~= nil then wv[#wv+1] = v end
                end
                if #wv == 0 then vals[i] = NA
                else
                    local s = 0; for _, v in ipairs(wv) do s = s + v end
                    vals[i] = s / #wv
                end
            end
        end
        return Series.from_table(vals, "float64", col._name)
    end

    function SeriesRolling:min()
        if self._s._d.rolling_min then
            local r = self._s._d.rolling_min(self._s._c, self._window)
            if r == nil then error("smaug: rolling:min falhou (OOM)", 2) end
            return wrap(r, self._s._dtype, self._s._name)
        end
        return self:_agg(function(vs)
            if #vs == 0 then return nil end
            local m = vs[1]; for _, v in ipairs(vs) do if v < m then m = v end end
            return m
        end)
    end

    function SeriesRolling:max()
        if self._s._d.rolling_max then
            local r = self._s._d.rolling_max(self._s._c, self._window)
            if r == nil then error("smaug: rolling:max falhou (OOM)", 2) end
            return wrap(r, self._s._dtype, self._s._name)
        end
        return self:_agg(function(vs)
            if #vs == 0 then return nil end
            local m = vs[1]; for _, v in ipairs(vs) do if v > m then m = v end end
            return m
        end)
    end

    function SeriesRolling:std()
        return self:_agg(function(vs)
            local n = #vs
            if n < 2 then return nil end
            local mean = 0; for _, v in ipairs(vs) do mean = mean + v end; mean = mean / n
            local s = 0; for _, v in ipairs(vs) do local d = v - mean; s = s + d*d end
            return math.sqrt(s / (n - 1))
        end, "float64")
    end

    function SeriesRolling:var()
        return self:_agg(function(vs)
            local n = #vs
            if n < 2 then return nil end
            local mean = 0; for _, v in ipairs(vs) do mean = mean + v end; mean = mean / n
            local s = 0; for _, v in ipairs(vs) do local d = v - mean; s = s + d*d end
            return s / (n - 1)
        end, "float64")
    end

    function SeriesRolling:count()
        local col, w = self._s, self._window
        local n      = col:len()
        local vals   = {}
        for i = 1, n do
            if i < w then vals[i] = NA
            else
                local cnt = 0
                for j = i - w + 1, i do
                    if col:get(j) ~= nil then cnt = cnt + 1 end
                end
                vals[i] = cnt
            end
        end
        return Series.from_table(vals, "int64", col._name)
    end

    function SeriesRolling:median()
        return self:_agg(function(vs)
            if #vs == 0 then return nil end
            local sv = {}; for _, v in ipairs(vs) do sv[#sv+1] = v end
            table.sort(sv)
            return median_sorted(sv)
        end, "float64")
    end

    function SeriesRolling:quantile(q)
        if type(q) ~= "number" or q < 0 or q > 1 then
            error("smaug: rolling:quantile() espera 0 ≤ q ≤ 1", 2)
        end
        return self:_agg(function(vs)
            local n = #vs
            if n == 0 then return nil end
            local sv = {}; for _, v in ipairs(vs) do sv[#sv+1] = v end
            table.sort(sv)
            if n == 1 then return sv[1] end
            local pos  = q * (n - 1)
            local lo   = math.floor(pos)
            local frac = pos - lo
            local hi   = lo + 1
            if hi >= n then return sv[n] end
            return sv[lo+1] + frac * (sv[hi+1] - sv[lo+1])
        end)
    end

    -- min_periods(p): retorna novo objeto rolling com min_periods configurado.
    function SeriesRolling:min_periods(p)
        if type(p) ~= "number" or p < 1 then
            error("smaug: rolling:min_periods() espera p >= 1", 2)
        end
        return setmetatable({ _s=self._s, _window=self._window, _min_periods=p }, SeriesRolling)
    end

    function methods.rolling(self, window)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: rolling() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        if type(window) ~= "number" or window < 1 or window ~= math.floor(window) then
            error("smaug: rolling — window deve ser inteiro >= 1", 2)
        end
        return setmetatable({ _s = self, _window = window }, SeriesRolling)
    end

    -- =====================================================================
    -- SeriesExpanding
    -- =====================================================================
    local SeriesExpanding = {}
    SeriesExpanding.__index = SeriesExpanding
    I.SeriesExpanding = SeriesExpanding

    function SeriesExpanding:_agg(fn)
        local col   = self._s
        local n     = col:len()
        local min_p = self._min_periods or 1
        local vals  = {}
        for i = 1, n do
            local wv = {}
            for j = 1, i do
                local v = col:get(j)
                if v ~= nil then wv[#wv+1] = v end
            end
            vals[i] = (#wv >= min_p) and fn(wv) or NA
        end
        return Series.from_table(vals, col._dtype, col._name)
    end

    function SeriesExpanding:sum()
        return self:_agg(function(vs) local s=0; for _,v in ipairs(vs) do s=s+v end; return s end)
    end
    function SeriesExpanding:mean()
        return self:_agg(function(vs)
            if #vs == 0 then return nil end
            local s=0; for _,v in ipairs(vs) do s=s+v end; return s/#vs
        end)
    end
    function SeriesExpanding:min()
        return self:_agg(function(vs)
            if #vs == 0 then return nil end
            local m=vs[1]; for _,v in ipairs(vs) do if v<m then m=v end end; return m
        end)
    end
    function SeriesExpanding:max()
        return self:_agg(function(vs)
            if #vs == 0 then return nil end
            local m=vs[1]; for _,v in ipairs(vs) do if v>m then m=v end end; return m
        end)
    end
    function SeriesExpanding:std()
        return self:_agg(function(vs)
            local n = #vs
            if n < 2 then return nil end
            local mean = 0; for _,v in ipairs(vs) do mean=mean+v end; mean=mean/n
            local s = 0; for _,v in ipairs(vs) do local d=v-mean; s=s+d*d end
            return math.sqrt(s / (n-1))
        end)
    end
    function SeriesExpanding:var()
        return self:_agg(function(vs)
            local n = #vs
            if n < 2 then return nil end
            local mean = 0; for _,v in ipairs(vs) do mean=mean+v end; mean=mean/n
            local s = 0; for _,v in ipairs(vs) do local d=v-mean; s=s+d*d end
            return s / (n-1)
        end)
    end
    function SeriesExpanding:count()
        return self:_agg(function(vs) return #vs end)
    end
    function SeriesExpanding:median()
        return self:_agg(function(vs)
            local sv = {}; for _,v in ipairs(vs) do sv[#sv+1]=v end
            table.sort(sv)
            return median_sorted(sv)
        end)
    end

    function methods.expanding(self, min_periods)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: expanding() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        return setmetatable({ _s=self, _min_periods=min_periods or 1 }, SeriesExpanding)
    end
end
