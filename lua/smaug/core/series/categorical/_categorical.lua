-- lua/smaug/core/series/categorical/_categorical.lua
--
-- CategoricalSeries: dtype Tier 2, Lua puro, sem backend C.
-- Armazenamento: dictionary encoding (_codes, _levels, _level_map).
-- CatProxy: accessor .cat
-- Recebe I com: I.Series, I.NA
-- Produz em I: I.CategoricalSeries

local Display = require("smaug.core.display")

return function(I)
    local Series = I.Series
    local NA     = I.NA

    -- =====================================================================
    -- CategoricalSeries
    -- =====================================================================
    local CategoricalSeries = {}
    CategoricalSeries.__index = CategoricalSeries
    CategoricalSeries._dtype  = "categorical"
    I.CategoricalSeries = CategoricalSeries

    -- Construtor interno
    local function cat_new(codes, levels, level_map, n, name)
        return setmetatable({
            _codes     = codes,
            _levels    = levels,
            _level_map = level_map,
            _name      = name,
            _size      = n,
            _dtype     = "categorical",
        }, CategoricalSeries)
    end

    -- ----------------------------------------------------------------
    -- Factories
    -- ----------------------------------------------------------------

    function CategoricalSeries.from_table(arr, name)
        local n         = #arr
        local codes     = {}
        local levels    = {}
        local level_map = {}
        for i = 1, n do
            local v = arr[i]
            if v == nil or v == NA then
                codes[i] = nil
            else
                local s   = tostring(v)
                local idx = level_map[s]
                if idx == nil then
                    levels[#levels + 1] = s
                    idx                 = #levels
                    level_map[s]        = idx
                end
                codes[i] = idx
            end
        end
        return cat_new(codes, levels, level_map, n, name)
    end

    -- from_codes: aceita NA como marcador de null.
    -- Para arrays com nil no meio, passe n explicitamente.
    function CategoricalSeries.from_codes(codes_arr, levels_arr, name, n)
        if type(levels_arr) ~= "table" then
            error("smaug: CategoricalSeries.from_codes — levels deve ser tabela", 2)
        end
        n = n or #codes_arr
        local lev  = {}
        local lmap = {}
        for i, v in ipairs(levels_arr) do
            lev[i]       = tostring(v)
            lmap[tostring(v)] = i
        end
        local codes = {}
        for i = 1, n do
            local c = codes_arr[i]
            if c == nil or c == NA then
                codes[i] = nil
            elseif type(c) ~= "number" or c < 1 or c > #lev then
                error("smaug: from_codes — code "..tostring(c).." fora do intervalo [1,"..#lev.."]", 2)
            else
                codes[i] = c
            end
        end
        return cat_new(codes, lev, lmap, n, name)
    end

    -- ----------------------------------------------------------------
    -- Acesso básico
    -- ----------------------------------------------------------------

    function CategoricalSeries:len()  return self._size end
    function CategoricalSeries:size() return self._size end

    -- __tostring (11.1): objeto de 1ª classe se auto-mostra. Valores via display
    -- canônico (cabeça+cauda) + rodapé de categorias, estilo pandas.
    CategoricalSeries.__tostring = function(self)
        local n = self._size
        local parts = {}
        local idx, brk = Display.plan_rows(n, 10)
        for pos, i in ipairs(idx) do
            parts[#parts + 1] = string.format("  [%d] %s", i, Display.cell_str(self:get(i)))
            if brk and pos == brk then parts[#parts + 1] = "  ..." end
        end
        local k = #self._levels
        local shown = {}
        for j = 1, math.min(k, 10) do shown[j] = self._levels[j] end
        local cats = table.concat(shown, ", ")
        if k > 10 then cats = cats .. ", ..." end
        return string.format("CategoricalSeries '%s' (len=%d)\n%s\nCategorias (%d): %s",
            self._name or "unnamed", n, table.concat(parts, "\n"), k, cats)
    end

    function CategoricalSeries:get(i)
        if type(i) ~= "number" or i < 1 or i > self._size then
            error("smaug: índice "..tostring(i).." fora dos limites [1, "..self._size.."]", 2)
        end
        local c = self._codes[i]
        if c == nil then return nil end
        return self._levels[c]
    end

    function CategoricalSeries:is_null(i)
        if type(i) ~= "number" or i < 1 or i > self._size then
            error("smaug: índice "..tostring(i).." fora dos limites [1, "..self._size.."]", 2)
        end
        return self._codes[i] == nil
    end

    function CategoricalSeries:set(i, v)
        if type(i) ~= "number" or i < 1 or i > self._size then
            error("smaug: índice "..tostring(i).." fora dos limites [1, "..self._size.."]", 2)
        end
        if v == nil or v == NA then self._codes[i] = nil; return end
        local s   = tostring(v)
        local idx = self._level_map[s]
        if idx == nil then
            self._levels[#self._levels + 1] = s
            idx                             = #self._levels
            self._level_map[s]              = idx
        end
        self._codes[i] = idx
    end

    function CategoricalSeries:set_null(i)
        if type(i) ~= "number" or i < 1 or i > self._size then
            error("smaug: índice "..tostring(i).." fora dos limites [1, "..self._size.."]", 2)
        end
        self._codes[i] = nil
    end

    function CategoricalSeries:append(v)
        self._size = self._size + 1
        local i    = self._size
        if v == nil or v == NA then
            self._codes[i] = nil
        else
            local s   = tostring(v)
            local idx = self._level_map[s]
            if idx == nil then
                self._levels[#self._levels + 1] = s
                idx                             = #self._levels
                self._level_map[s]              = idx
            end
            self._codes[i] = idx
        end
        return self
    end

    function CategoricalSeries:count_nonnull()
        local n = 0
        for i = 1, self._size do
            if self._codes[i] ~= nil then n = n + 1 end
        end
        return n
    end

    -- ----------------------------------------------------------------
    -- Transformações (sempre retornam novo objeto)
    -- ----------------------------------------------------------------

    function CategoricalSeries:clone()
        local codes = {}
        for i = 1, self._size do codes[i] = self._codes[i] end
        local levels, lmap = {}, {}
        for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
        return cat_new(codes, levels, lmap, self._size, self._name)
    end

    function CategoricalSeries:head(n)
        n = math.min(n or 5, self._size)
        local codes = {}
        for i = 1, n do codes[i] = self._codes[i] end
        local levels, lmap = {}, {}
        for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
        return cat_new(codes, levels, lmap, n, self._name)
    end

    function CategoricalSeries:tail(n)
        n = math.min(n or 5, self._size)
        local start = self._size - n + 1
        local codes = {}
        for i = 1, n do codes[i] = self._codes[start + i - 1] end
        local levels, lmap = {}, {}
        for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
        return cat_new(codes, levels, lmap, n, self._name)
    end

    function CategoricalSeries:take(idx)
        if type(idx) ~= "table" then
            error("smaug: take espera uma tabela de índices", 2)
        end
        local codes = {}
        for j, i in ipairs(idx) do
            if type(i) ~= "number" or i < 1 or i > self._size then
                error("smaug: take — índice "..tostring(i).." fora dos limites", 2)
            end
            codes[j] = self._codes[i]
        end
        local levels, lmap = {}, {}
        for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
        return cat_new(codes, levels, lmap, #idx, self._name)
    end

    -- view() não se aplica a categorical: é Lua puro (codes + dicionário), sem
    -- buffer C compartilhável. Stub explícito para dar a razão correta em vez do
    -- erro cru "attempt to call method 'view' (a nil value)".
    function CategoricalSeries:view()
        error("smaug: view() não se aplica a dtype 'categorical' "..
              "(sem buffer compartilhável); use :take(idx) ou :head(n)/:tail(n) "..
              "para uma cópia", 2)
    end

    function CategoricalSeries:filter(mask)
        if type(mask) ~= "table" or mask._dtype ~= "bool" then
            error("smaug: filter espera Series<bool>", 2)
        end
        if mask:len() ~= self._size then
            error("smaug: filter — tamanhos diferentes", 2)
        end
        local codes, n = {}, 0
        for i = 1, self._size do
            if mask:get(i) == true then
                n = n + 1; codes[n] = self._codes[i]
            end
        end
        local levels, lmap = {}, {}
        for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
        return cat_new(codes, levels, lmap, n, self._name)
    end

    function CategoricalSeries:dropna()
        local codes, n = {}, 0
        for i = 1, self._size do
            if self._codes[i] ~= nil then n = n + 1; codes[n] = self._codes[i] end
        end
        local levels, lmap = {}, {}
        for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
        return cat_new(codes, levels, lmap, n, self._name)
    end

    function CategoricalSeries:fillna(value)
        if value == nil or value == NA then
            error("smaug: fillna requer um valor de preenchimento", 2)
        end
        local s         = tostring(value)
        local fill_idx  = self._level_map[s]
        local new_levels, new_lmap = {}, {}
        for i, v in ipairs(self._levels) do new_levels[i] = v; new_lmap[v] = i end
        if fill_idx == nil then
            new_levels[#new_levels + 1] = s
            fill_idx                    = #new_levels
            new_lmap[s]                 = fill_idx
        end
        local codes = {}
        for i = 1, self._size do
            codes[i] = self._codes[i] ~= nil and self._codes[i] or fill_idx
        end
        return cat_new(codes, new_levels, new_lmap, self._size, self._name)
    end

    function CategoricalSeries:sort(ascending)
        if ascending == nil then ascending = true end
        for i = 1, self._size do
            if self._codes[i] == nil then
                error("smaug: sort não suporta séries com nulos (use dropna primeiro)", 2)
            end
        end
        local idx    = {}
        for i = 1, self._size do idx[i] = i end
        local levels = self._levels
        local codes  = self._codes
        if ascending then
            table.sort(idx, function(a, b) return levels[codes[a]] < levels[codes[b]] end)
        else
            table.sort(idx, function(a, b) return levels[codes[a]] > levels[codes[b]] end)
        end
        local new_codes = {}
        for j, i in ipairs(idx) do new_codes[j] = codes[i] end
        local new_levels, new_lmap = {}, {}
        for i, v in ipairs(levels) do new_levels[i] = v; new_lmap[v] = i end
        return cat_new(new_codes, new_levels, new_lmap, self._size, self._name)
    end

    function CategoricalSeries:argsort(ascending)
        if ascending == nil then ascending = true end
        for i = 1, self._size do
            if self._codes[i] == nil then return nil end
        end
        local idx    = {}
        local levels = self._levels
        local codes  = self._codes
        for i = 1, self._size do idx[i] = i end
        if ascending then
            table.sort(idx, function(a, b) return levels[codes[a]] < levels[codes[b]] end)
        else
            table.sort(idx, function(a, b) return levels[codes[a]] > levels[codes[b]] end)
        end
        return idx
    end

    -- Comparações → Series<bool>
    local function cat_compare(self, target, fn)
        if type(target) ~= "string" then
            error("smaug: comparação categorical espera string", 2)
        end
        local vals = {}
        for i = 1, self._size do
            local v = self:get(i)
            if v == nil then vals[i] = NA
            else vals[i] = fn(v, target) end
        end
        return Series.from_table(vals, "bool", self._name)
    end

    function CategoricalSeries:eq(t) return cat_compare(self, t, function(a,b) return a == b end) end
    function CategoricalSeries:ne(t) return cat_compare(self, t, function(a,b) return a ~= b end) end
    function CategoricalSeries:lt(t) return cat_compare(self, t, function(a,b) return a <  b end) end
    function CategoricalSeries:le(t) return cat_compare(self, t, function(a,b) return a <= b end) end
    function CategoricalSeries:gt(t) return cat_compare(self, t, function(a,b) return a >  b end) end
    function CategoricalSeries:ge(t) return cat_compare(self, t, function(a,b) return a >= b end) end

    -- unique / nunique / value_counts
    function CategoricalSeries:unique()
        local seen, vals = {}, {}
        for i = 1, self._size do
            local v = self:get(i)
            if v ~= nil and not seen[v] then
                seen[v] = true; vals[#vals+1] = v
            end
        end
        return CategoricalSeries.from_table(vals, self._name)
    end

    function CategoricalSeries:nunique()
        local seen, n = {}, 0
        for i = 1, self._size do
            local v = self:get(i)
            if v ~= nil and not seen[v] then seen[v] = true; n = n + 1 end
        end
        return n
    end

    -- Retorna tabela (não DataSet) para evitar dependência circular
    function CategoricalSeries:value_counts()
        local freq, order = {}, {}
        for i = 1, self._size do
            local v = self:get(i)
            if v ~= nil then
                if not freq[v] then order[#order+1] = v end
                freq[v] = (freq[v] or 0) + 1
            end
        end
        table.sort(order, function(a, b)
            if freq[a] ~= freq[b] then return freq[a] > freq[b] end
            return a < b
        end)
        local vals, counts = {}, {}
        for i, v in ipairs(order) do vals[i] = v; counts[i] = freq[v] end
        return { value = vals, count = counts }
    end

    -- Predicados de nulidade
    function CategoricalSeries:isna(i)  return self:is_null(i) end
    function CategoricalSeries:notna(i) return not self:is_null(i) end

    -- min/max lexicográfico
    function CategoricalSeries:min()
        local best = nil
        for i = 1, self._size do
            local v = self:get(i)
            if v ~= nil and (best == nil or v < best) then best = v end
        end
        return best
    end
    function CategoricalSeries:max()
        local best = nil
        for i = 1, self._size do
            local v = self:get(i)
            if v ~= nil and (best == nil or v > best) then best = v end
        end
        return best
    end

    -- ffill/bfill: opera ao nível de codes para eficiência
    function CategoricalSeries:ffill()
        local codes, last = {}, nil
        for i = 1, self._size do
            if self._codes[i] ~= nil then last = self._codes[i] end
            codes[i] = last
        end
        local levels, lmap = {}, {}
        for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
        return cat_new(codes, levels, lmap, self._size, self._name)
    end

    function CategoricalSeries:bfill()
        local codes, next_code = {}, nil
        for i = self._size, 1, -1 do
            if self._codes[i] ~= nil then next_code = self._codes[i] end
            codes[i] = next_code
        end
        local levels, lmap = {}, {}
        for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
        return cat_new(codes, levels, lmap, self._size, self._name)
    end

    function CategoricalSeries:shift(periods)
        periods = periods or 1
        local codes = {}
        for i = 1, self._size do
            local src = i - periods
            codes[i] = (src >= 1 and src <= self._size) and self._codes[src] or nil
        end
        local levels, lmap = {}, {}
        for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
        return cat_new(codes, levels, lmap, self._size, self._name)
    end

    -- map(fn, [dtype], [name]): aplica fn a cada label. Retorna Series (não Cat).
    function CategoricalSeries:map(fn, dtype, name)
        if type(fn) ~= "function" then
            error("smaug: map() espera uma função", 2)
        end
        local vals, inferred = {}, dtype
        for i = 1, self._size do
            local v   = self:get(i)
            local out = fn(v)
            if out == nil or out == NA then
                vals[i] = NA
            else
                if inferred == nil then
                    if     type(out) == "boolean" then inferred = "bool"
                    elseif type(out) == "string"  then inferred = "string"
                    elseif type(out) == "number" and out % 1 == 0 then inferred = "int64"
                    else   inferred = "float64"
                    end
                end
                vals[i] = out
            end
        end
        return Series.from_table(vals, inferred or "string", name or self._name)
    end

    -- where(cond, other)
    function CategoricalSeries:where(cond, other)
        if type(cond) ~= "table" or cond._dtype ~= "bool" then
            error("smaug: where() espera Series<bool> como primeiro argumento", 2)
        end
        if cond:len() ~= self._size then
            error("smaug: where() — tamanhos diferentes ("..cond:len().." vs "..self._size..")", 2)
        end
        local has_other = type(other) == "table" and other._dtype ~= nil
        local vals = {}
        for i = 1, self._size do
            local c = cond:get(i)
            if c == true then
                vals[i] = self:get(i)
            else
                vals[i] = has_other and other:get(i) or (other == nil and NA or other)
            end
        end
        return CategoricalSeries.from_table(vals, self._name)
    end

    -- mask(cond, other)
    function CategoricalSeries:mask(cond, other)
        if type(cond) ~= "table" or cond._dtype ~= "bool" then
            error("smaug: mask() espera Series<bool> como primeiro argumento", 2)
        end
        if cond:len() ~= self._size then
            error("smaug: mask() — tamanhos diferentes ("..cond:len().." vs "..self._size..")", 2)
        end
        local has_other = type(other) == "table" and other._dtype ~= nil
        local vals = {}
        for i = 1, self._size do
            local c = cond:get(i)
            if c == true then
                vals[i] = has_other and other:get(i) or (other == nil and NA or other)
            else
                vals[i] = self:get(i)
            end
        end
        return CategoricalSeries.from_table(vals, self._name)
    end

    -- describe
    function CategoricalSeries:describe()
        local freq, top, top_freq = {}, nil, 0
        for i = 1, self._size do
            local v = self:get(i)
            if v ~= nil then
                freq[v] = (freq[v] or 0) + 1
                if freq[v] > top_freq then top, top_freq = v, freq[v] end
            end
        end
        local nulls = self._size - self:count_nonnull()
        local u = 0
        for _ in pairs(freq) do u = u + 1 end
        return {
            dtype   = "categorical",
            count   = self._size - nulls,
            nulls   = nulls,
            unique  = u,
            levels  = #self._levels,
            top     = top,
            freq    = top_freq > 0 and top_freq or nil,
        }
    end

    function CategoricalSeries:to_table(na_value)
        local t = {}
        for i = 1, self._size do
            local v = self:get(i)
            t[i] = v ~= nil and v or na_value
        end
        return t
    end

    function CategoricalSeries:astype(dtype, name)
        name = name or self._name
        if dtype == "categorical" then return self:clone() end
        if dtype == "string" then
            local vals = {}
            for i = 1, self._size do
                vals[i] = self._codes[i] ~= nil and self._levels[self._codes[i]] or NA
            end
            return Series.from_table(vals, "string", name)
        end
        if dtype == "float64" or dtype == "int64" or dtype == "int32" then
            local vals = {}
            for i = 1, self._size do
                if self._codes[i] == nil then
                    vals[i] = NA
                else
                    local num = tonumber(self._levels[self._codes[i]])
                    vals[i] = num ~= nil and num or NA
                end
            end
            return Series.from_table(vals, dtype == "int32" and "int64" or dtype, name)
        end
        error("smaug: astype categorical → '"..tostring(dtype).."' não suportado", 2)
    end

    -- ----------------------------------------------------------------
    -- CatProxy (.cat accessor)
    -- ----------------------------------------------------------------
    local CatProxy = {}
    CatProxy.__index = CatProxy
    CatProxy.__tostring = function(self)
        return string.format("<accessor .cat de CategoricalSeries '%s'>", self._s._name or "unnamed")
    end

    function CatProxy:codes()
        local vals = {}
        local s    = self._s
        for i = 1, s._size do
            vals[i] = s._codes[i] ~= nil and s._codes[i] or NA
        end
        return Series.from_table(vals, "int64", s._name)
    end

    function CatProxy:levels()
        local t = {}
        for i, v in ipairs(self._s._levels) do t[i] = v end
        return t
    end

    function CatProxy:rename_categories(mapping)
        if type(mapping) ~= "table" then
            error("smaug: rename_categories espera tabela {old = new, ...}", 2)
        end
        local s          = self._s
        local new_levels = {}
        local new_lmap   = {}
        for i, v in ipairs(s._levels) do
            local nv      = mapping[v] ~= nil and tostring(mapping[v]) or v
            new_levels[i] = nv
            new_lmap[nv]  = i
        end
        local codes = {}
        for i = 1, s._size do codes[i] = s._codes[i] end
        return cat_new(codes, new_levels, new_lmap, s._size, s._name)
    end

    function CatProxy:set_categories(new_levels_arr)
        if type(new_levels_arr) ~= "table" then
            error("smaug: set_categories espera tabela de strings", 2)
        end
        local s       = self._s
        local new_lev = {}
        local new_map = {}
        for i, v in ipairs(new_levels_arr) do
            new_lev[i]           = tostring(v)
            new_map[tostring(v)] = i
        end
        local remap = {}
        for i, v in ipairs(s._levels) do remap[i] = new_map[v] end
        local codes = {}
        for i = 1, s._size do
            local old_c = s._codes[i]
            codes[i]    = old_c ~= nil and remap[old_c] or nil
        end
        return cat_new(codes, new_lev, new_map, s._size, s._name)
    end

    function CatProxy:add_categories(vals)
        local s       = self._s
        local new_lev = {}
        local new_map = {}
        for i, v in ipairs(s._levels) do new_lev[i] = v; new_map[v] = i end
        for _, v in ipairs(vals) do
            local sv = tostring(v)
            if not new_map[sv] then
                new_lev[#new_lev + 1] = sv
                new_map[sv]           = #new_lev
            end
        end
        local codes = {}
        for i = 1, s._size do codes[i] = s._codes[i] end
        return cat_new(codes, new_lev, new_map, s._size, s._name)
    end

    function CatProxy:remove_categories(vals)
        local s      = self._s
        local remove = {}
        for _, v in ipairs(vals) do remove[tostring(v)] = true end
        local new_lev = {}
        local new_map = {}
        local remap   = {}
        for i, v in ipairs(s._levels) do
            if not remove[v] then
                new_lev[#new_lev + 1] = v
                new_map[v]            = #new_lev
                remap[i]              = #new_lev
            end
        end
        local codes = {}
        for i = 1, s._size do
            local c  = s._codes[i]
            codes[i] = c ~= nil and remap[c] or nil
        end
        return cat_new(codes, new_lev, new_map, s._size, s._name)
    end

    -- __index do CategoricalSeries
    CategoricalSeries.__index = function(self, k)
        if k == "cat" then
            return setmetatable({ _s = self }, CatProxy)
        end
        if type(k) == "number" then return CategoricalSeries.get(self, k) end
        return CategoricalSeries[k]
    end
end
