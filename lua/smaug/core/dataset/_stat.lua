-- lua/smaug/core/dataset/_stat.lua
--
-- Estatísticas, predicados, duplicatas e Rolling DataSet.
-- Recebe I com: I.Series, I.DataSet, I.methods
-- Contribui: methods.corr, cov, equals, compare,
--            methods.duplicated, drop_duplicates, methods.rolling

return function(I)
    local Series  = I.Series
    local DataSet = I.DataSet
    local methods = I.methods

    -- =====================================================================
    -- F.1 — corr / cov
    -- =====================================================================

    local function numeric_col_names(self)
        local names = {}
        for _, n in ipairs(self._col_names) do
            local dt = self._columns[n]._dtype
            if dt == "float64" or dt == "int64" then names[#names + 1] = n end
        end
        return names
    end

    local function _stat_matrix(self, pair_fn, suffix)
        local names = numeric_col_names(self)
        if #names == 0 then
            error("smaug: "..suffix.."() requer ao menos uma coluna numérica", 3)
        end
        local result = DataSet.new(self._name .. "_" .. suffix)
        result:add_column("__index__", Series.from_table(names, "string", "__index__"))
        for _, cj in ipairs(names) do
            local col_j = self._columns[cj]
            local vals  = {}
            for i, ci in ipairs(names) do
                vals[i] = pair_fn(self._columns[ci], col_j)
            end
            result:add_column(cj, Series.from_table(vals, "float64", cj))
        end
        return result
    end

    function methods.corr(self)
        return _stat_matrix(self, function(a, b) return a:corr(b) end, "corr")
    end

    function methods.cov(self)
        return _stat_matrix(self, function(a, b) return a:cov(b) end, "cov")
    end

    -- =====================================================================
    -- F.2 — equals / compare
    -- =====================================================================

    -- Helper: igualdade estrutural de duas colunas (Series, bool ou categorical).
    local function column_equals(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        if a._dtype ~= b._dtype then return false end
        -- Series typed: usa :equals nativo (NaN estrutural)
        if getmetatable(a) == Series and getmetatable(b) == Series then
            return a:equals(b)
        end
        if a:len() ~= b:len() then return false end
        for i = 1, a:len() do
            local va, vb = a:get(i), b:get(i)
            if (va == nil) ~= (vb == nil) then return false end
            if va ~= nil and va ~= vb then return false end
        end
        return true
    end

    function methods.equals(self, other)
        if getmetatable(other) ~= DataSet then return false end
        if self:ncols() ~= other:ncols() then return false end
        if self:nrows() ~= other:nrows() then return false end
        local sn, on = self._col_names, other._col_names
        for i = 1, #sn do
            if sn[i] ~= on[i] then return false end
        end
        for _, n in ipairs(sn) do
            if not column_equals(self._columns[n], other._columns[n]) then return false end
        end
        return true
    end

    function methods.compare(self, other)
        if getmetatable(other) ~= DataSet then
            error("smaug: compare() espera outro DataSet", 2)
        end
        if self:ncols() ~= other:ncols() or self:nrows() ~= other:nrows() then
            error("smaug: compare() — DataSets de formas diferentes", 2)
        end
        local sn, on = self._col_names, other._col_names
        for i = 1, #sn do
            if sn[i] ~= on[i] then
                error("smaug: compare() — colunas diferentes ('"..sn[i].."' vs '"..on[i].."')", 2)
            end
        end
        local NA = Series.NA
        local rows, cols, self_vals, other_vals = {}, {}, {}, {}
        for _, name in ipairs(sn) do
            local a, b = self._columns[name], other._columns[name]
            for i = 1, self:nrows() do
                local va, vb = a:get(i), b:get(i)
                local differ
                if (va == nil) ~= (vb == nil) then
                    differ = true
                elseif va == nil then
                    differ = false
                else
                    differ = (va ~= vb) and not (va ~= va and vb ~= vb)
                end
                if differ then
                    local m = #rows + 1
                    rows[m]       = i
                    cols[m]       = name
                    self_vals[m]  = (va == nil) and NA or tostring(va)
                    other_vals[m] = (vb == nil) and NA or tostring(vb)
                end
            end
        end
        return DataSet.from_columns({
            {"linha",  rows,       "int64"},
            {"coluna", cols,       "string"},
            {"self",   self_vals,  "string"},
            {"other",  other_vals, "string"},
        }, self._name .. "_compare")
    end

    -- =====================================================================
    -- F.6 — Duplicatas
    -- =====================================================================

    local function row_dup_key(self, i, subset)
        local parts = {}
        for j, name in ipairs(subset) do
            local v = self._columns[name]:get(i)
            parts[j] = (v == nil) and "\0NULL\0" or (type(v)..":"..tostring(v))
        end
        return table.concat(parts, "\1")
    end

    function methods.duplicated(self, subset, keep)
        keep = keep or "first"
        if keep ~= "first" and keep ~= "last" and keep ~= "none" then
            error("smaug: duplicated() keep ∈ {first, last, none}", 2)
        end
        if subset == nil then
            subset = self._col_names
        elseif type(subset) == "string" then
            subset = { subset }
        elseif type(subset) ~= "table" then
            error("smaug: duplicated() subset deve ser nome, lista de nomes ou nil", 2)
        end
        for _, name in ipairs(subset) do
            if self._columns[name] == nil then
                error("smaug: duplicated() coluna '"..tostring(name).."' não existe", 2)
            end
        end
        local n    = self:nrows()
        local vals = {}
        if keep == "first" then
            local seen = {}
            for i = 1, n do
                local k = row_dup_key(self, i, subset)
                if seen[k] then vals[i] = true else seen[k] = true; vals[i] = false end
            end
        elseif keep == "last" then
            local seen = {}
            for i = n, 1, -1 do
                local k = row_dup_key(self, i, subset)
                if seen[k] then vals[i] = true else seen[k] = true; vals[i] = false end
            end
        else  -- none
            local count = {}
            for i = 1, n do
                local k = row_dup_key(self, i, subset)
                count[k] = (count[k] or 0) + 1
            end
            for i = 1, n do
                vals[i] = count[row_dup_key(self, i, subset)] > 1
            end
        end
        return Series.from_table(vals, "bool", "duplicated")
    end

    function methods.drop_duplicates(self, subset, keep)
        local mask = self:duplicated(subset, keep)
        local keep_idx = {}
        for i = 1, self:nrows() do
            if mask:get(i) == false then keep_idx[#keep_idx + 1] = i end
        end
        return self:take(keep_idx)
    end

    -- =====================================================================
    -- Rolling DataSet
    -- =====================================================================
    local Rolling = {}
    Rolling.__index = Rolling

    function Rolling:_agg(col_name, fn)
        local col  = self._ds:column(col_name)
        local n    = col:len()
        local w    = self._window
        local NA   = Series.NA
        local vals = {}
        for i = 1, n do
            if i < w then
                vals[i] = NA
            else
                local window_vals = {}
                for j = i - w + 1, i do
                    local v = col:get(j)
                    if v ~= nil then window_vals[#window_vals+1] = v end
                end
                vals[i] = fn(window_vals)
            end
        end
        return Series.from_table(vals, col._dtype, col_name)
    end

    function Rolling:sum(col_name)
        return self:_agg(col_name, function(vs)
            local s = 0; for _, v in ipairs(vs) do s = s + v end; return s
        end)
    end
    function Rolling:mean(col_name)
        return self:_agg(col_name, function(vs)
            if #vs == 0 then return nil end
            local s = 0; for _, v in ipairs(vs) do s = s + v end
            return s / #vs
        end)
    end
    function Rolling:min(col_name)
        return self:_agg(col_name, function(vs)
            if #vs == 0 then return nil end
            local m = vs[1]; for _, v in ipairs(vs) do if v < m then m = v end end
            return m
        end)
    end
    function Rolling:max(col_name)
        return self:_agg(col_name, function(vs)
            if #vs == 0 then return nil end
            local m = vs[1]; for _, v in ipairs(vs) do if v > m then m = v end end
            return m
        end)
    end

    function methods.rolling(self, window)
        if type(window) ~= "number" or window < 1 or window ~= math.floor(window) then
            error("smaug: rolling — window deve ser inteiro >= 1", 2)
        end
        return setmetatable({ _ds = self, _window = window }, Rolling)
    end
end
