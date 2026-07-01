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
    -- 5.1 — reduções por coluna → DataSet de 1 linha (D1)
    --   Aplica a redução da Series a cada coluna numérica; cada coluna do
    --   resultado mantém SEU dtype de resultado (sum de i64→i64, mean→f64
    --   convivem — por isso DataSet 1-linha, não Series posicional).
    --   Fonte única: delega às reduções da Series (as mesmas do GroupBy, 5.4).
    -- =====================================================================
    local NA = Series.NA

    -- dtype do resultado por redução (espelha build_result do GroupBy)
    local function out_dtype_for(rule, src_dtype)
        if rule == "preserve" then
            return src_dtype == "int64" and "int64" or "float64"
        end
        return rule  -- "float64" ou "int64"
    end

    local function reduce_frame(self, method, dtype_rule, ...)
        local names = numeric_col_names(self)
        if #names == 0 then
            error("smaug: "..method.."() requer ao menos uma coluna numérica", 3)
        end
        local result = DataSet.new(self._name .. "_" .. method)
        local extra  = { ... }
        for _, name in ipairs(names) do
            local col    = self._columns[name]
            local v      = col[method](col, unpack(extra))
            local out_dt = out_dtype_for(dtype_rule, col._dtype)
            result:add_column(name, Series.from_table({ v == nil and NA or v }, out_dt, name))
        end
        return result
    end

    function methods.sum(self, min_count)  return reduce_frame(self, "sum",  "preserve", true, min_count) end
    function methods.prod(self, min_count)  return reduce_frame(self, "prod", "preserve", true, min_count) end
    function methods.min(self)           return reduce_frame(self, "min",           "preserve") end
    function methods.max(self)           return reduce_frame(self, "max",           "preserve") end
    function methods.mean(self)          return reduce_frame(self, "mean",          "float64")  end
    function methods.std(self)           return reduce_frame(self, "std",           "float64")  end
    function methods.var(self)           return reduce_frame(self, "var",           "float64")  end
    function methods.median(self)        return reduce_frame(self, "median",        "float64")  end
    function methods.skew(self)          return reduce_frame(self, "skew",          "float64")  end
    function methods.kurtosis(self)      return reduce_frame(self, "kurtosis",      "float64")  end
    function methods.mad(self)           return reduce_frame(self, "mad",           "float64")  end
    function methods.sem(self)           return reduce_frame(self, "sem",           "float64")  end
    function methods.count_nonnull(self) return reduce_frame(self, "count_nonnull", "int64")    end
    function methods.quantile(self, q)   return reduce_frame(self, "quantile",      "float64", q) end

    -- =====================================================================
    -- 5.2 / 5.3 — element-wise e transforms → DataSet de MESMA forma
    --   map_frame aplica o método da Series a cada coluna (fonte única).
    --   numeric_strict (D4-i): operações numéricas erram se houver coluna
    --   não-numérica — element-wise preserva a forma, então não dá pra
    --   descartar nem passar coluna não-aplicável em silêncio ("falha visível").
    --   (Contraste com 5.1: reduções mudam a forma → pulam não-numéricas.)
    -- =====================================================================
    local function map_frame(self, method, numeric_strict, ...)
        local result = DataSet.new(self._name .. "_" .. method)
        local extra  = { ... }
        for _, name in ipairs(self._col_names) do
            local col, dt = self._columns[name], self._columns[name]._dtype
            if numeric_strict and dt ~= "float64" and dt ~= "int64" then
                error("smaug: "..method.."() requer colunas numéricas; coluna '"..name..
                      "' é '"..dt.."' (selecione as numéricas antes)", 3)
            end
            result:add_column(name, col[method](col, unpack(extra)))
        end
        return result
    end

    -- 5.2 element-wise (numéricos estritos)
    function methods.abs(self)          return map_frame(self, "abs",     true)         end
    function methods.cumsum(self)       return map_frame(self, "cumsum",  true)         end
    function methods.cummin(self)       return map_frame(self, "cummin",  true)         end
    function methods.cummax(self)       return map_frame(self, "cummax",  true)         end
    function methods.cumprod(self)      return map_frame(self, "cumprod", true)         end
    function methods.round(self, nd)    return map_frame(self, "round",   true, nd)     end
    function methods.clip(self, lo, hi) return map_frame(self, "clip",    true, lo, hi) end

    -- 5.3 transforms
    function methods.diff(self)         return map_frame(self, "diff",  true)     end  -- numérico
    function methods.ffill(self)        return map_frame(self, "ffill", false)    end  -- qualquer dtype
    function methods.bfill(self)        return map_frame(self, "bfill", false)    end
    function methods.shift(self, p)     return map_frame(self, "shift", false, p) end

    -- 5.3 isna/notna — mask de nulidade por coluna (qualquer dtype) → DataSet bool.
    -- Não usa Series:isna (que é escalar por índice); constrói via is_null.
    local function frame_null_mask(self, negate)
        local result = DataSet.new(self._name .. (negate and "_notna" or "_isna"))
        for _, name in ipairs(self._col_names) do
            local col, n = self._columns[name], self._columns[name]:len()
            local vals = {}
            for j = 1, n do
                local nul = col:is_null(j)
                vals[j] = negate and (not nul) or nul
            end
            result:add_column(name, Series.from_table(vals, "bool", name))
        end
        return result
    end
    function methods.isna(self)  return frame_null_mask(self, false) end
    function methods.notna(self) return frame_null_mask(self, true)  end

    -- 5.3 astype — mapa { coluna = dtype } (D4-A). Colunas fora do mapa seguem
    -- inalteradas (compartilhadas; Series são COW).
    function methods.astype(self, dtype_map)
        if type(dtype_map) ~= "table" then
            error("smaug: astype() espera um mapa { coluna = dtype }", 2)
        end
        for cname in pairs(dtype_map) do
            if not self:has_column(cname) then
                error("smaug: astype() — coluna '"..cname.."' não existe", 2)
            end
        end
        local result = DataSet.new(self._name .. "_astype")
        for _, name in ipairs(self._col_names) do
            local col    = self._columns[name]
            local target = dtype_map[name]
            result:add_column(name, target and col:astype(target, name) or col)
        end
        return result
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
    -- Rolling DataSet (item 8c): delega à Series, que delega ao C. Remove a
    -- reimplementação _agg própria — fonte única. min_periods opcional;
    -- ganha std/var/count de graça (a Series já os tem via C).
    local Rolling = {}
    Rolling.__index = Rolling

    local function ds_roll(self, col_name)
        local r = self._ds:_raw_column(col_name):rolling(self._window)
        if self._min_periods then r = r:min_periods(self._min_periods) end
        return r
    end

    function Rolling:sum(col_name)   return ds_roll(self, col_name):sum()   end
    function Rolling:mean(col_name)  return ds_roll(self, col_name):mean()  end
    function Rolling:min(col_name)   return ds_roll(self, col_name):min()   end
    function Rolling:max(col_name)   return ds_roll(self, col_name):max()   end
    function Rolling:std(col_name)   return ds_roll(self, col_name):std()   end
    function Rolling:var(col_name)   return ds_roll(self, col_name):var()   end
    function Rolling:count(col_name) return ds_roll(self, col_name):count() end

    function Rolling:min_periods(p)
        if type(p) ~= "number" or p < 1 then
            error("smaug: rolling:min_periods() espera p >= 1", 2)
        end
        return setmetatable({ _ds=self._ds, _window=self._window, _min_periods=p }, Rolling)
    end

    function methods.rolling(self, window)
        if type(window) ~= "number" or window < 1 or window ~= math.floor(window) then
            error("smaug: rolling — window deve ser inteiro >= 1", 2)
        end
        return setmetatable({ _ds = self, _window = window }, Rolling)
    end
end
