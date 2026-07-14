-- lua/smaug/core/dataset/_relational.lua
--
-- Operações relacionais: concat, join, GroupBy, pivot, melt,
-- pivot_table, stack, unstack, explode.
-- Recebe I com: I.Series, I.DataSet, I.methods, I.ffi, I.C,
--               I.is_series, I.is_boolseries, I.is_categorical,
--               I.map_columns
-- Contribui: DataSet.concat, methods.concat, methods.join,
--            methods.groupby, methods.pivot, methods.melt,
--            methods.pivot_table, methods.stack, methods.unstack,
--            methods.explode

return function(I)
    local Series        = I.Series
    local DataSet       = I.DataSet
    local methods       = I.methods
    local ffi           = I.ffi
    local C             = I.C
    local is_series     = I.is_series
    local is_boolseries = I.is_boolseries
    local is_categorical = I.is_categorical
    local map_columns   = I.map_columns

    local NA = Series.NA

    -- =====================================================================
    -- Concat
    -- =====================================================================
    local function concat_datasets(list, name)
        if type(list) ~= "table" or #list == 0 then
            error("smaug: concat espera uma lista não-vazia de DataSets", 2)
        end
        local ref = list[1]
        if getmetatable(ref) ~= DataSet then
            error("smaug: concat — elemento 1 não é um DataSet", 2)
        end
        local col_names = ref._col_names
        for k = 2, #list do
            local ds = list[k]
            if getmetatable(ds) ~= DataSet then
                error("smaug: concat — elemento "..k.." não é um DataSet", 2)
            end
            if #ds._col_names ~= #col_names then
                error("smaug: concat — elemento "..k.." tem número de colunas diferente"
                      .." ("..#ds._col_names.." vs "..#col_names..")", 2)
            end
            for _, cname in ipairs(col_names) do
                if not ds:has_column(cname) then
                    error("smaug: concat — elemento "..k.." não tem coluna '"..cname.."'", 2)
                end
                local dt1 = ref:_raw_column(cname)._dtype
                local dt2 = ds:_raw_column(cname)._dtype
                if dt1 ~= dt2 then
                    error("smaug: concat — coluna '"..cname.."': dtype incompatível"
                          .." ('"..dt1.."' vs '"..dt2.."')", 2)
                end
            end
        end
        local result = DataSet.new(name or ref._name)
        for _, cname in ipairs(col_names) do
            local dtype = ref:_raw_column(cname)._dtype
            local vals  = {}
            for _, ds in ipairs(list) do
                local col = ds:_raw_column(cname)
                for i = 1, col:len() do
                    local v = col:get(i)
                    vals[#vals + 1] = (v == nil) and NA or v
                end
            end
            result:add_column(cname, Series.from_table(vals, dtype, cname))
        end
        return result
    end

    DataSet.concat = concat_datasets
    function methods.concat(self, other, name)
        if getmetatable(other) == DataSet then
            return concat_datasets({self, other}, name)
        elseif type(other) == "table" then
            return concat_datasets({self, unpack(other)}, name)
        end
        error("smaug: concat espera um DataSet ou lista de DataSets", 2)
    end

    -- =====================================================================
    -- Join helpers
    -- =====================================================================
    local function key_to_str(v)
        if v == nil then return "\0NULL\0" end
        return type(v) .. ":" .. tostring(v)
    end

    local function join_key(col_list, row)
        if #col_list == 1 then return key_to_str(col_list[1]:get(row)) end
        local parts = {}
        for _, c in ipairs(col_list) do parts[#parts+1] = key_to_str(c:get(row)) end
        return table.concat(parts, "\1")
    end

    -- Política de NA em chave relacional (Contrato 8): NA = ausência que não
    -- participa. join/groupby/pivot/pivot_table erram em vez de casar NA com NA,
    -- agrupar por NA ou descartar a linha em silêncio. "Falha visível > acerto
    -- adivinhado": o usuário trata com fillna/dropna na pipeline.
    -- named_cols: lista de { name = <string>, col = <Series> }. Valida SÓ colunas
    -- de chave — nunca a coluna de valores (valores podem ser NA, são dado).
    local function validate_keys_no_na(named_cols, op_name)
        for _, nc in ipairs(named_cols) do
            local col, n = nc.col, nc.col:len()
            for i = 1, n do
                if col:is_null(i) then
                    error("smaug: "..op_name.." — coluna '"..nc.name..
                          "' contém NA; trate com fillna ou dropna antes", 3)
                end
            end
        end
    end

    local function resolve_names(left_names, right_names, join_keys_set, suffixes)
        local sl, sr = suffixes[1] or "_left", suffixes[2] or "_right"
        local right_non_key = {}
        for _, n in ipairs(right_names) do
            if not join_keys_set[n] then right_non_key[#right_non_key+1] = n end
        end
        local left_set = {}
        for _, n in ipairs(left_names) do left_set[n] = true end
        local result_left, result_right = {}, {}
        for _, n in ipairs(left_names) do
            if join_keys_set[n] then
                result_left[#result_left+1] = {n, n}
            else
                local has_conflict = false
                for _, rn in ipairs(right_non_key) do
                    if rn == n then has_conflict = true; break end
                end
                result_left[#result_left+1] = {n, has_conflict and (n..sl) or n}
            end
        end
        for _, n in ipairs(right_non_key) do
            local final = left_set[n] and (n..sr) or n
            result_right[#result_right+1] = {n, final}
        end
        return result_left, result_right
    end

    local function build_col(series, pairs_idx, side, NA_val)
        local vals = {}
        for _, p in ipairs(pairs_idx) do
            local idx = (side == "left") and p[1] or p[2]
            if idx == 0 then
                vals[#vals+1] = NA_val
            else
                local v = series:get(idx)
                vals[#vals+1] = (v == nil) and NA_val or v
            end
        end
        return Series.from_table(vals, series._dtype)
    end

    -- =====================================================================
    -- Join
    -- =====================================================================
    function methods.join(self, other, on, how, suffixes)
        if getmetatable(other) ~= DataSet then
            error("smaug: join — 'other' deve ser um DataSet", 2)
        end
        how      = how      or "inner"
        suffixes = suffixes or {"_left", "_right"}
        if how ~= "inner" and how ~= "left" and how ~= "right" and how ~= "outer" then
            error("smaug: join — 'how' deve ser 'inner', 'left', 'right' ou 'outer'", 2)
        end
        if how == "right" then
            return other:join(self, on, "left", {suffixes[2], suffixes[1]})
        end
        local left_key_names, right_key_names
        if type(on) == "string" then
            left_key_names  = {on}
            right_key_names = {on}
        elseif type(on) == "table" and type(on[1]) == "string" and type(on[2]) == "string" then
            left_key_names  = {on[1]}
            right_key_names = {on[2]}
        elseif type(on) == "table" then
            left_key_names  = on
            right_key_names = on
        else
            error("smaug: join — 'on' deve ser string ou {left_key, right_key}", 2)
        end
        for _, k in ipairs(left_key_names) do
            if not self:has_column(k) then
                error("smaug: join — coluna esquerda '"..k.."' não existe", 2)
            end
        end
        for _, k in ipairs(right_key_names) do
            if not other:has_column(k) then
                error("smaug: join — coluna direita '"..k.."' não existe", 2)
            end
        end
        local left_key_cols, right_key_cols = {}, {}
        for _, k in ipairs(left_key_names)  do left_key_cols[#left_key_cols+1]   = self:_raw_column(k)  end
        for _, k in ipairs(right_key_names) do right_key_cols[#right_key_cols+1] = other:_raw_column(k) end

        -- Contrato 8: NA em chave de join não casa — erro orientado.
        do
            local named = {}
            for i, k in ipairs(left_key_names)  do named[#named+1] = { name = k, col = left_key_cols[i]  } end
            for i, k in ipairs(right_key_names) do named[#named+1] = { name = k, col = right_key_cols[i] } end
            validate_keys_no_na(named, "join")
        end

        local join_keys_set = {}
        for _, k in ipairs(left_key_names)  do join_keys_set[k] = true end
        for _, k in ipairs(right_key_names) do join_keys_set[k] = true end

        local nl, nr = self:nrows(), other:nrows()
        local hash = {}
        for i = 1, nr do
            local k = join_key(right_key_cols, i)
            if hash[k] then hash[k][#hash[k]+1] = i else hash[k] = {i} end
        end

        local pairs_idx     = {}
        local right_matched = {}
        for i = 1, nl do
            local k = join_key(left_key_cols, i)
            local matches = hash[k]
            if matches then
                for _, j in ipairs(matches) do
                    pairs_idx[#pairs_idx+1] = {i, j}
                    right_matched[j] = true
                end
            elseif how == "left" or how == "outer" then
                pairs_idx[#pairs_idx+1] = {i, 0}
            end
        end
        if how == "outer" then
            for j = 1, nr do
                if not right_matched[j] then
                    pairs_idx[#pairs_idx+1] = {0, j}
                end
            end
        end

        local res_left, res_right = resolve_names(
            self._col_names, other._col_names, join_keys_set, suffixes)

        local result = DataSet.new(self._name .. "_join_" .. other._name)
        for _, pair in ipairs(res_left) do
            local orig, final = pair[1], pair[2]
            local src = self:_raw_column(orig)
            if join_keys_set[orig] then
                local right_key_idx = 1
                for ri, rk in ipairs(right_key_names) do
                    if rk == orig or left_key_names[ri] == orig then
                        right_key_idx = ri; break
                    end
                end
                local right_key_src = other:_raw_column(right_key_names[right_key_idx] or right_key_names[1])
                local vals = {}
                for _, p in ipairs(pairs_idx) do
                    if p[1] ~= 0 then
                        local v = src:get(p[1])
                        vals[#vals+1] = (v == nil) and NA or v
                    else
                        local v = right_key_src:get(p[2])
                        vals[#vals+1] = (v == nil) and NA or v
                    end
                end
                result:add_column(final, Series.from_table(vals, src._dtype, final))
            else
                result:add_column(final, build_col(src, pairs_idx, "left", NA))
            end
        end
        for _, pair in ipairs(res_right) do
            local orig, final = pair[1], pair[2]
            result:add_column(final, build_col(other:_raw_column(orig), pairs_idx, "right", NA))
        end
        return result
    end

    -- =====================================================================
    -- GroupBy
    -- =====================================================================
    local GroupBy = {}
    GroupBy.__index = GroupBy
    GroupBy.__tostring = function(self)
        return string.format("<DataSet.groupby([%s]) de '%s'>",
            table.concat(self._key_names or {}, ", "), self._ds._name or "DataSet")
    end

    local function key_eq(a, b)
        if type(a) ~= type(b) then return false end
        return a == b
    end

    local function get_key(key_cols, row)
        if #key_cols == 1 then return key_cols[1]:get(row) end
        local k = {}
        for _, c in ipairs(key_cols) do k[#k+1] = c:get(row) end
        return k
    end

    local function keys_eq(a, b)
        if type(a) ~= "table" then return key_eq(a, b) end
        if #a ~= #b then return false end
        for i = 1, #a do
            if not key_eq(a[i], b[i]) then return false end
        end
        return true
    end

    local SORT_COL_KIND = {
        float64  = 0,
        int64    = 1,
        string   = 2,
        datetime = 3,
        bool     = 4,
    }

    local function multi_argsort(ds, key_names)
        local n = ds:nrows()
        if n == 0 then return {} end
        local cols_lua = {}
        for _, name in ipairs(key_names) do
            local col = ds:_raw_column(name)
            -- NA na chave já foi rejeitado por validate_keys_no_na em methods.groupby
            -- (Contrato 8). multi_argsort só é alcançado por build_groups/groupby.
            cols_lua[#cols_lua+1] = col
        end
        local all_c = true
        for _, col in ipairs(cols_lua) do
            if not SORT_COL_KIND[col._dtype] then all_c = false; break end
        end
        if all_c and #key_names > 0 then
            local ffi_cols = ffi.new("smaug_sort_col_ffi_t[?]", #cols_lua)
            for k, col in ipairs(cols_lua) do
                ffi_cols[k-1].kind = SORT_COL_KIND[col._dtype]
                ffi_cols[k-1].ptr  = ffi.cast("void*", col._c)
            end
            local perm_ptr = C.smaug_multi_argsort_ffi(ffi_cols, #cols_lua, n)
            if perm_ptr == nil then error("smaug: multi_argsort — OOM", 4) end
            local idx = {}
            for i = 0, n - 1 do idx[i+1] = tonumber(perm_ptr[i]) + 1 end
            C.smaug_free(perm_ptr)
            return idx
        end
        -- Fallback Lua
        local idx = {}
        for i = 1, n do idx[i] = i end
        table.sort(idx, function(a, b)
            for _, col in ipairs(cols_lua) do
                local va, vb = col:get(a), col:get(b)
                if type(va) == "boolean" then va = va and 1 or 0 end
                if type(vb) == "boolean" then vb = vb and 1 or 0 end
                if va ~= vb then return va < vb end
            end
            return false
        end)
        return idx
    end

    local function build_groups(ds, key_names)
        local perm = multi_argsort(ds, key_names)
        local key_cols = {}
        for _, name in ipairs(key_names) do key_cols[#key_cols+1] = ds:_raw_column(name) end
        local groups = {}
        local n = ds:nrows()
        if n == 0 then return groups end
        local cur_key = get_key(key_cols, perm[1])
        local cur_idx = { perm[1] }
        for i = 2, n do
            local k = get_key(key_cols, perm[i])
            if keys_eq(k, cur_key) then
                cur_idx[#cur_idx+1] = perm[i]
            else
                groups[#groups+1] = { key = cur_key, idx = cur_idx }
                cur_key = k
                cur_idx = { perm[i] }
            end
        end
        groups[#groups+1] = { key = cur_key, idx = cur_idx }
        return groups
    end

    local function resolve_agg_cols(ds, key_set, col_names)
        if col_names and #col_names > 0 then
            for _, c in ipairs(col_names) do
                if not ds:has_column(c) then
                    error("smaug: groupby agg — coluna '"..c.."' não existe", 4)
                end
            end
            return col_names
        end
        local result = {}
        for _, c in ipairs(ds._col_names) do
            if not key_set[c] then
                local dt = ds:_raw_column(c)._dtype
                if dt == "float64" or dt == "int64" then result[#result+1] = c end
            end
        end
        return result
    end

    -- Funções de agregação
    -- 5.4: agregações delegam às reduções da Series (fonte única). Materializam a
    -- sub-coluna do grupo via take(idx) e chamam a redução — mesma semântica
    -- (skip NA, ddof=1 amostral em std/var após 5.0). build_result controla o dtype.
    local function agg_sum(col, idx)    return col:take(idx):sum()    end
    local function agg_mean(col, idx)   return col:take(idx):mean()   end
    local function agg_min(col, idx)    return col:take(idx):min()    end
    local function agg_max(col, idx)    return col:take(idx):max()    end
    local function agg_std(col, idx)    return col:take(idx):std()    end
    local function agg_var(col, idx)    return col:take(idx):var()    end
    local function agg_median(col, idx) return col:take(idx):median() end
    local function agg_prod(col, idx)   return col:take(idx):prod()   end
    local function agg_nunique(col, idx) return col:take(idx):nunique() end
    -- first/last são posicionais por grupo, não reduções da Series → seguem inline.
    local function agg_first(col, idx)
        for _, i in ipairs(idx) do local v = col:get(i); if v ~= nil then return v end end
        return nil
    end
    local function agg_last(col, idx)
        local last = nil
        for _, i in ipairs(idx) do local v = col:get(i); if v ~= nil then last = v end end
        return last
    end

    local function build_result(gb, agg_fn, col_names, out_dtype_override)
        local ds        = gb._ds
        local key_names = gb._key_names
        local groups    = gb._groups
        local key_set   = gb._key_set
        local result    = DataSet.new(ds._name .. "_groupby")
        if #key_names == 1 then
            local key_dtype = ds:_raw_column(key_names[1])._dtype
            local vals = {}
            for _, g in ipairs(groups) do vals[#vals+1] = g.key end
            result:add_column(key_names[1], Series.from_table(vals, key_dtype, key_names[1]))
        else
            for ki, kname in ipairs(key_names) do
                local key_dtype = ds:_raw_column(kname)._dtype
                local vals = {}
                for _, g in ipairs(groups) do vals[#vals+1] = g.key[ki] end
                result:add_column(kname, Series.from_table(vals, key_dtype, kname))
            end
        end
        local agg_cols = resolve_agg_cols(ds, key_set, col_names)
        for _, cname in ipairs(agg_cols) do
            local src  = ds:_raw_column(cname)
            local vals = {}
            for gi, g in ipairs(groups) do
                local v = agg_fn(src, g.idx)
                vals[gi] = (v ~= nil) and v or NA
            end
            local out_dtype
            if out_dtype_override then
                out_dtype = out_dtype_override
            elseif agg_fn == agg_mean or agg_fn == agg_std or agg_fn == agg_var
               or agg_fn == agg_median then
                out_dtype = "float64"
            elseif agg_fn == agg_nunique then
                out_dtype = "int64"
            else
                out_dtype = src._dtype == "int64" and "int64" or "float64"
            end
            result:add_column(cname, Series.from_table(vals, out_dtype, cname))
        end
        return result
    end

    -- GroupBy métodos de agregação
    function GroupBy:sum(...)
        local cols = select('#', ...) > 0 and {...} or nil
        return build_result(self, agg_sum, cols)
    end
    function GroupBy:mean(...)
        local cols = select('#', ...) > 0 and {...} or nil
        return build_result(self, agg_mean, cols)
    end
    function GroupBy:min(...)
        local cols = select('#', ...) > 0 and {...} or nil
        return build_result(self, agg_min, cols)
    end
    function GroupBy:max(...)
        local cols = select('#', ...) > 0 and {...} or nil
        return build_result(self, agg_max, cols)
    end
    function GroupBy:std(...)
        local cols = select('#', ...) > 0 and {...} or nil
        return build_result(self, agg_std, cols)
    end
    function GroupBy:var(...)
        local cols = select('#', ...) > 0 and {...} or nil
        return build_result(self, agg_var, cols)
    end
    function GroupBy:median(...)
        local cols = select('#', ...) > 0 and {...} or nil
        return build_result(self, agg_median, cols)
    end
    function GroupBy:first(...)
        local cols = select('#', ...) > 0 and {...} or nil
        return build_result(self, agg_first, cols)
    end
    function GroupBy:last(...)
        local cols = select('#', ...) > 0 and {...} or nil
        return build_result(self, agg_last, cols)
    end
    function GroupBy:prod(...)
        local cols = select('#', ...) > 0 and {...} or nil
        return build_result(self, agg_prod, cols)
    end

    function GroupBy:nunique(...)
        local cols = select('#', ...) > 0 and {...} or nil
        local ds, key_names, key_set, groups = self._ds, self._key_names, self._key_set, self._groups
        local result = DataSet.new(ds._name .. "_groupby")
        if #key_names == 1 then
            local key_dtype = ds:_raw_column(key_names[1])._dtype
            local vals = {}
            for _, g in ipairs(groups) do vals[#vals+1] = g.key end
            result:add_column(key_names[1], Series.from_table(vals, key_dtype, key_names[1]))
        else
            for ki, kname in ipairs(key_names) do
                local key_dtype = ds:_raw_column(kname)._dtype
                local vals = {}
                for _, g in ipairs(groups) do vals[#vals+1] = g.key[ki] end
                result:add_column(kname, Series.from_table(vals, key_dtype, kname))
            end
        end
        local agg_cols = resolve_agg_cols(ds, key_set, cols)
        for _, cname in ipairs(agg_cols) do
            local src  = ds:_raw_column(cname)
            local vals = {}
            for _, g in ipairs(groups) do vals[#vals+1] = agg_nunique(src, g.idx) end
            result:add_column(cname, Series.from_table(vals, "int64", cname))
        end
        return result
    end

    function GroupBy:quantile(q, ...)
        if type(q) ~= "number" or q < 0 or q > 1 then
            error("smaug: groupby:quantile() espera 0 ≤ q ≤ 1", 2)
        end
        local cols = select('#', ...) > 0 and {...} or nil
        local fn = function(col, idx)
            local vals = {}
            for _, i in ipairs(idx) do local v = col:get(i); if v ~= nil then vals[#vals+1] = v end end
            local n = #vals
            if n == 0 then return nil end
            table.sort(vals)
            if n == 1 then return vals[1] end
            local pos  = q * (n - 1)
            local lo   = math.floor(pos)
            local frac = pos - lo
            local hi   = lo + 1
            if hi >= n then return vals[n] end
            return vals[lo+1] + frac * (vals[hi+1] - vals[lo+1])
        end
        return build_result(self, fn, cols, "float64")
    end

    function GroupBy:agg(spec)
        if type(spec) ~= "table" then
            error("smaug: groupby:agg() espera uma tabela {coluna = fn | {fn,...}}", 2)
        end
        local ds, key_names, key_set, groups = self._ds, self._key_names, self._key_set, self._groups
        local builtin = {
            sum=agg_sum, mean=agg_mean, min=agg_min, max=agg_max,
            std=agg_std, var=agg_var, median=agg_median,
            first=agg_first, last=agg_last, prod=agg_prod, nunique=agg_nunique,
            count=function(_, idx) return #idx end,
        }
        local result = DataSet.new(ds._name .. "_groupby")
        if #key_names == 1 then
            local key_dtype = ds:_raw_column(key_names[1])._dtype
            local vals = {}
            for _, g in ipairs(groups) do vals[#vals+1] = g.key end
            result:add_column(key_names[1], Series.from_table(vals, key_dtype, key_names[1]))
        else
            for ki, kname in ipairs(key_names) do
                local key_dtype = ds:_raw_column(kname)._dtype
                local vals = {}
                for _, g in ipairs(groups) do vals[#vals+1] = g.key[ki] end
                result:add_column(kname, Series.from_table(vals, key_dtype, kname))
            end
        end
        for cname, fns in pairs(spec) do
            if not ds:has_column(cname) then
                error("smaug: groupby:agg() — coluna '"..cname.."' não existe", 2)
            end
            if type(fns) ~= "table" then fns = {fns} end
            local src = ds:_raw_column(cname)
            for _, fn in ipairs(fns) do
                local fn_real = type(fn) == "string" and builtin[fn] or fn
                if not fn_real then
                    error("smaug: groupby:agg() — função desconhecida '"..tostring(fn).."'", 2)
                end
                local out_name = type(fn) == "string" and (cname.."_"..fn) or cname
                local vals = {}
                for gi, g in ipairs(groups) do
                    local v = fn_real(src, g.idx)
                    vals[gi] = (v ~= nil) and v or NA
                end
                result:add_column(out_name, Series.from_table(vals, "float64", out_name))
            end
        end
        return result
    end

    function GroupBy:transform(fn_name, col_name)
        local ds, groups = self._ds, self._groups
        if not ds:has_column(col_name) then
            error("smaug: groupby:transform() — coluna '"..col_name.."' não existe", 2)
        end
        local builtin = {
            sum=agg_sum, mean=agg_mean, min=agg_min, max=agg_max,
            std=agg_std, var=agg_var, median=agg_median,
            first=agg_first, last=agg_last, prod=agg_prod,
        }
        local fn = type(fn_name) == "string" and builtin[fn_name] or fn_name
        if not fn then
            error("smaug: groupby:transform() — função desconhecida '"..tostring(fn_name).."'", 2)
        end
        local src  = ds:_raw_column(col_name)
        local n    = ds:nrows()
        local vals = {}
        for i = 1, n do vals[i] = NA end
        for _, g in ipairs(groups) do
            local agg_val = fn(src, g.idx)
            for _, i in ipairs(g.idx) do vals[i] = agg_val end
        end
        return Series.from_table(vals, "float64", col_name)
    end

    function GroupBy:count()
        local ds        = self._ds
        local key_names = self._key_names
        local groups    = self._groups
        local result    = DataSet.new(ds._name .. "_groupby")
        if #key_names == 1 then
            local key_dtype = ds:_raw_column(key_names[1])._dtype
            local kv, cv = {}, {}
            for _, g in ipairs(groups) do kv[#kv+1] = g.key; cv[#cv+1] = #g.idx end
            result:add_column(key_names[1], Series.from_table(kv, key_dtype, key_names[1]))
            result:add_column("count",      Series.from_table(cv, "int64",   "count"))
        else
            for ki, kname in ipairs(key_names) do
                local key_dtype = ds:_raw_column(kname)._dtype
                local vals = {}
                for _, g in ipairs(groups) do vals[#vals+1] = g.key[ki] end
                result:add_column(kname, Series.from_table(vals, key_dtype, kname))
            end
            local cv = {}
            for _, g in ipairs(groups) do cv[#cv+1] = #g.idx end
            result:add_column("count", Series.from_table(cv, "int64", "count"))
        end
        return result
    end

    function methods.groupby(self, key)
        local key_names
        if type(key) == "string" then
            key_names = { key }
        elseif type(key) == "table" then
            if #key == 0 then error("smaug: groupby espera pelo menos uma coluna-chave", 2) end
            key_names = key
        else
            error("smaug: groupby espera string ou lista de strings", 2)
        end
        for _, k in ipairs(key_names) do
            if not self:has_column(k) then
                error("smaug: groupby — coluna '"..k.."' não existe", 2)
            end
        end
        -- Contrato 8: NA em chave de groupby não agrupa — erro orientado.
        do
            local named = {}
            for _, k in ipairs(key_names) do named[#named+1] = { name = k, col = self:_raw_column(k) } end
            validate_keys_no_na(named, "groupby")
        end
        local key_set = {}
        for _, k in ipairs(key_names) do key_set[k] = true end
        local groups = build_groups(self, key_names)
        return setmetatable({
            _ds        = self,
            _key_names = key_names,
            _key_set   = key_set,
            _groups    = groups,
        }, GroupBy)
    end

    -- =====================================================================
    -- Pivot / Melt
    -- =====================================================================
    function methods.pivot(self, index, columns, values)
        for _, arg in ipairs({index, columns, values}) do
            if type(arg) ~= "string" then
                error("smaug: pivot — argumentos devem ser strings (index, columns, values)", 2)
            end
        end
        for _, col in ipairs({index, columns, values}) do
            if not self:has_column(col) then
                error("smaug: pivot — coluna '"..col.."' não existe", 2)
            end
        end
        local n       = self:nrows()
        local idx_col = self:_raw_column(index)
        local col_col = self:_raw_column(columns)
        local val_col = self:_raw_column(values)
        -- Contrato 8: NA em index/columns do pivot não é descartado em silêncio — erro.
        validate_keys_no_na({ { name = index, col = idx_col }, { name = columns, col = col_col } }, "pivot")
        local idx_vals, idx_seen = {}, {}
        local col_vals, col_seen = {}, {}
        for i = 1, n do
            local iv = idx_col:get(i)
            if iv ~= nil then
                local k = tostring(iv)
                if not idx_seen[k] then idx_seen[k]=true; idx_vals[#idx_vals+1]=iv end
            end
            local cv = col_col:get(i)
            if cv ~= nil then
                local k = tostring(cv)
                if not col_seen[k] then col_seen[k]=true; col_vals[#col_vals+1]=cv end
            end
        end
        table.sort(idx_vals, function(a,b) return tostring(a) < tostring(b) end)
        table.sort(col_vals, function(a,b) return tostring(a) < tostring(b) end)
        local lookup = {}
        for i = 1, n do
            local iv = idx_col:get(i)
            local cv = col_col:get(i)
            local vv = val_col:get(i)
            if iv ~= nil and cv ~= nil then
                lookup[tostring(iv).."\1"..tostring(cv)] = vv
            end
        end
        local result   = DataSet.new(self._name.."_pivot")
        local idx_dtype = idx_col._dtype
        result:add_column(index, Series.from_table(idx_vals, idx_dtype, index))
        local val_dtype = val_col._dtype
        for _, cv in ipairs(col_vals) do
            local cname = tostring(cv)
            local vals  = {}
            for _, iv in ipairs(idx_vals) do
                local k = tostring(iv).."\1"..tostring(cv)
                vals[#vals+1] = lookup[k] ~= nil and lookup[k] or NA
            end
            result:add_column(cname, Series.from_table(vals, val_dtype, cname))
        end
        return result
    end

    function methods.melt(self, id_vars, value_vars, var_name, value_name)
        id_vars    = id_vars    or {}
        var_name   = var_name   or "variable"
        value_name = value_name or "value"
        if type(id_vars) == "string" then id_vars = {id_vars} end
        local id_set = {}
        for _, n in ipairs(id_vars) do
            if not self:has_column(n) then error("smaug: melt — id_var '"..n.."' não existe", 2) end
            id_set[n] = true
        end
        if value_vars == nil then
            value_vars = {}
            for _, n in ipairs(self._col_names) do
                if not id_set[n] then value_vars[#value_vars+1] = n end
            end
        elseif type(value_vars) == "string" then
            value_vars = {value_vars}
        end
        for _, n in ipairs(value_vars) do
            if not self:has_column(n) then error("smaug: melt — value_var '"..n.."' não existe", 2) end
        end
        local nrows    = self:nrows()
        local val_dtype = nil
        for _, vv in ipairs(value_vars) do
            local dt = self:_raw_column(vv)._dtype
            if val_dtype == nil then val_dtype = dt
            elseif val_dtype ~= dt then val_dtype = "string"; break end
        end
        val_dtype = val_dtype or "string"
        local id_data   = {}
        for _, n in ipairs(id_vars) do id_data[n] = {} end
        local var_data, value_data = {}, {}
        for _, vv in ipairs(value_vars) do
            local src = self:_raw_column(vv)
            for i = 1, nrows do
                for _, n in ipairs(id_vars) do
                    local v = self:_raw_column(n):get(i)
                    id_data[n][#id_data[n]+1] = (v == nil) and NA or v
                end
                var_data[#var_data+1] = vv
                local v = src:get(i)
                if v == nil then
                    value_data[#value_data+1] = NA
                elseif val_dtype == "string" then
                    value_data[#value_data+1] = tostring(v)
                else
                    value_data[#value_data+1] = v
                end
            end
        end
        local result = DataSet.new(self._name.."_melt")
        for _, n in ipairs(id_vars) do
            result:add_column(n, Series.from_table(id_data[n], self:_raw_column(n)._dtype, n))
        end
        result:add_column(var_name,   Series.from_table(var_data,   "string",   var_name))
        result:add_column(value_name, Series.from_table(value_data, val_dtype, value_name))
        return result
    end

    function methods.pivot_table(self, index, columns, values, aggfunc)
        if not self:has_column(index)   then error("smaug: pivot_table — coluna '"..index.."' não existe",   2) end
        if not self:has_column(columns) then error("smaug: pivot_table — coluna '"..columns.."' não existe", 2) end
        if not self:has_column(values)  then error("smaug: pivot_table — coluna '"..values.."' não existe",  2) end
        aggfunc = aggfunc or "sum"
        local fns = {
            sum=agg_sum, mean=agg_mean, min=agg_min, max=agg_max,
            count=function(_, idx) return #idx end,
            first=agg_first, last=agg_last,
        }
        local fn = fns[aggfunc]
        if not fn then error("smaug: pivot_table — aggfunc desconhecida '"..aggfunc.."'", 2) end
        local idx_col = self:_raw_column(index)
        local col_col = self:_raw_column(columns)
        local val_col = self:_raw_column(values)
        local n       = self:nrows()
        -- Contrato 8: NA em index/columns do pivot_table não é descartado em silêncio — erro.
        validate_keys_no_na({ { name = index, col = idx_col }, { name = columns, col = col_col } }, "pivot_table")
        local idx_vals, idx_seen = {}, {}
        local col_vals, col_seen = {}, {}
        for i = 1, n do
            local iv = idx_col:get(i)
            local cv = col_col:get(i)
            if iv ~= nil and not idx_seen[tostring(iv)] then
                idx_seen[tostring(iv)] = true; idx_vals[#idx_vals+1] = iv
            end
            if cv ~= nil and not col_seen[tostring(cv)] then
                col_seen[tostring(cv)] = true; col_vals[#col_vals+1] = cv
            end
        end
        table.sort(idx_vals, function(a, b) return tostring(a) < tostring(b) end)
        table.sort(col_vals, function(a, b) return tostring(a) < tostring(b) end)
        local buckets = {}
        for i = 1, n do
            local ik = tostring(idx_col:get(i) or "")
            local ck = tostring(col_col:get(i) or "")
            if not buckets[ik] then buckets[ik] = {} end
            if not buckets[ik][ck] then buckets[ik][ck] = {} end
            buckets[ik][ck][#buckets[ik][ck]+1] = i
        end
        local result   = DataSet.new(self._name.."_pivot")
        local idx_dtype = idx_col._dtype
        local idx_data  = {}
        for _, iv in ipairs(idx_vals) do idx_data[#idx_data+1] = iv end
        result:add_column(index, Series.from_table(idx_data, idx_dtype, index))
        local val_dtype = val_col._dtype
        for _, cv in ipairs(col_vals) do
            local ck    = tostring(cv)
            local cdata = {}
            for _, iv in ipairs(idx_vals) do
                local ik  = tostring(iv)
                local ids = buckets[ik] and buckets[ik][ck] or {}
                cdata[#cdata+1] = (#ids > 0) and fn(val_col, ids) or NA
            end
            result:add_column(tostring(cv), Series.from_table(cdata, val_dtype, tostring(cv)))
        end
        return result
    end

    function methods.stack(self, col_names)
        if type(col_names) ~= "table" or #col_names == 0 then
            error("smaug: stack() espera lista de colunas a empilhar", 2)
        end
        local id_vars = {}
        for _, cname in ipairs(self._col_names) do
            local is_val = false
            for _, v in ipairs(col_names) do if v == cname then is_val = true; break end end
            if not is_val then id_vars[#id_vars+1] = cname end
        end
        return self:melt(id_vars, col_names, "variable", "value")
    end

    function methods.unstack(self, index, col, values)
        return self:pivot_table(index, col, values, "first")
    end

    function methods.explode(self, col_name)
        if not self:has_column(col_name) then
            error("smaug: explode() — coluna '"..col_name.."' não existe", 2)
        end
        local src = self:_raw_column(col_name)
        local n   = self:nrows()
        local total = 0
        for i = 1, n do
            local v = src:get(i)
            if v == nil then total = total + 1
            elseif type(v) == "table" then total = total + math.max(#v, 1)
            else total = total + 1 end
        end
        local other_cols = {}
        for _, cname in ipairs(self._col_names) do
            if cname ~= col_name then
                other_cols[cname] = { col=self:_raw_column(cname), vals={} }
            end
        end
        local exploded_vals = {}
        for i = 1, n do
            local v = src:get(i)
            local items
            if v == nil then items = {NA}
            elseif type(v) == "table" then items = #v > 0 and v or {NA}
            else items = {v} end
            for _, item in ipairs(items) do
                exploded_vals[#exploded_vals+1] = item
                for _, info in pairs(other_cols) do
                    info.vals[#info.vals+1] = info.col:get(i)
                end
            end
        end
        local result = DataSet.new(self._name)
        for _, cname in ipairs(self._col_names) do
            if cname == col_name then
                local dtype = "string"
                for _, v in ipairs(exploded_vals) do
                    if v ~= nil and v ~= NA then
                        if type(v) == "number" then
                            dtype = (v % 1 == 0) and "int64" or "float64"
                        elseif type(v) == "boolean" then
                            dtype = "bool"
                        end
                        break
                    end
                end
                result:add_column(col_name, Series.from_table(exploded_vals, dtype, col_name))
            else
                local info = other_cols[cname]
                result:add_column(cname, Series.from_table(info.vals, info.col._dtype, cname))
            end
        end
        return result
    end
end
