-- lua/smaug/core/series/window/_rolling.lua
--
-- SeriesRolling e SeriesExpanding: janela deslizante e janela crescente.
-- Grupo C Ring 0 (item 8a): sum/mean/min/max/std/var/count delegam ao C com
-- min_periods. median/quantile ficam em Lua (janela ordenada, via _agg).
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
    SeriesRolling.__tostring = function(self)
        return string.format("<Series.rolling(window=%s, min_periods=%s) de '%s'>",
            tostring(self._window), tostring(self._min_periods or self._window),
            self._s._name or "unnamed")
    end
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

    -- Item 8a: sum/mean/min/max/std/var/count delegam ao C com min_periods.
    -- Convenção: _min_periods nil → 0 (modo janela-cheia, default do C);
    -- setado → valor (modo parcial). Sem fallback Lua — fonte única no C.
    -- O bug histórico (caminho C ignorava min_periods) morre aqui.
    local function mp(self) return self._min_periods or 0 end

    function SeriesRolling:sum()
        local r = self._s._d.rolling_sum(self._s._c, self._window, mp(self))
        if r == nil then error("smaug: rolling:sum falhou (OOM)", 2) end
        return wrap(r, self._s._dtype, self._s._name)
    end

    function SeriesRolling:mean()
        local r = self._s._d.rolling_mean(self._s._c, self._window, mp(self))
        if r == nil then error("smaug: rolling:mean falhou (OOM)", 2) end
        return wrap(r, "float64", self._s._name)
    end

    function SeriesRolling:min()
        local r = self._s._d.rolling_min(self._s._c, self._window, mp(self))
        if r == nil then error("smaug: rolling:min falhou (OOM)", 2) end
        return wrap(r, self._s._dtype, self._s._name)
    end

    function SeriesRolling:max()
        local r = self._s._d.rolling_max(self._s._c, self._window, mp(self))
        if r == nil then error("smaug: rolling:max falhou (OOM)", 2) end
        return wrap(r, self._s._dtype, self._s._name)
    end

    function SeriesRolling:std()
        local r = self._s._d.rolling_std(self._s._c, self._window, mp(self))
        if r == nil then error("smaug: rolling:std falhou (OOM)", 2) end
        return wrap(r, "float64", self._s._name)
    end

    function SeriesRolling:var()
        local r = self._s._d.rolling_var(self._s._c, self._window, mp(self))
        if r == nil then error("smaug: rolling:var falhou (OOM)", 2) end
        return wrap(r, "float64", self._s._name)
    end

    function SeriesRolling:count()
        local r = self._s._d.rolling_count(self._s._c, self._window, mp(self))
        if r == nil then error("smaug: rolling:count falhou (OOM)", 2) end
        return wrap(r, "int64", self._s._name)
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
    SeriesExpanding.__tostring = function(self)
        return string.format("<Series.expanding(min_periods=%s) de '%s'>",
            tostring(self._min_periods or 1), self._s._name or "unnamed")
    end
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

    -- Item 8b: expanding É rolling com janela = comprimento total e
    -- min_periods >= 1 (janela [1,i] cresce a cada posição). Delega ao
    -- rolling (que delega ao C) — fonte única, sem reimplementação.
    -- median/quantile ficam Lua (via _agg, como no rolling).
    local function exp_roll(self)
        local n = self._s:len()
        local w = (n > 0) and n or 1
        return self._s:rolling(w):min_periods(self._min_periods or 1)
    end

    function SeriesExpanding:sum()   return exp_roll(self):sum()   end
    function SeriesExpanding:mean()  return exp_roll(self):mean()  end
    function SeriesExpanding:min()   return exp_roll(self):min()   end
    function SeriesExpanding:max()   return exp_roll(self):max()   end
    function SeriesExpanding:std()   return exp_roll(self):std()   end
    function SeriesExpanding:var()   return exp_roll(self):var()   end
    function SeriesExpanding:count() return exp_roll(self):count() end

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
