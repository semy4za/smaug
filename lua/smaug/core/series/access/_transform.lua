-- lua/smaug/core/series/access/_transform.lua
--
-- Transformações elementares: sort, view, take, astype, fillna, map, abs, round, clip.
-- Recebe I com: I.methods, I.Series, I.wrap, I.DTYPES, I.ffi, I.C,
--               I.NA, I.is_na, I.is_nan, I.infer_dtype_from_value
-- Contribui: methods.sort, argsort, view, take, dropna, head, tail,
--            to_table, astype, fillna, map, abs, round, clip

return function(I)
    local methods = I.methods
    local Series  = I.Series
    local wrap    = I.wrap
    local DTYPES  = I.DTYPES
    local ffi     = I.ffi
    local C       = I.C
    local NA      = I.NA
    local is_na   = I.is_na
    local is_nan  = I.is_nan

    -- =====================================================================
    -- Ordenação
    -- =====================================================================
    function methods.sort(self, ascending)
        if ascending == nil then ascending = true end
        local r = self._d.sort(self._c, ascending)
        if r == nil then
            error("smaug: sort não suporta séries com nulos (use dropna primeiro)", 2)
        end
        return wrap(r, self._dtype, self._name)
    end

    -- argsort: tabela Lua 1-based de índices que ordenam a série.
    -- Devolve nil se a série contém nulos. Usado por DataSet:sort_by.
    function methods.argsort(self, ascending)
        if ascending == nil then ascending = true end
        local p = self._d.argsort(self._c, ascending)
        if p == nil then return nil end
        local n   = self:len()
        local idx = {}
        for i = 1, n do idx[i] = tonumber(p[i - 1]) + 1 end   -- 0-based → 1-based
        C.smaug_free(p)
        return idx
    end

    -- =====================================================================
    -- View e Take
    -- =====================================================================

    -- view: fatia zero-copy [start, start+len-1] (1-based).
    function methods.view(self, start, len)
        if self._d.view == nil then
            if self._dtype == "string" then
                error("smaug: view() ainda não é suportado para dtype 'string' "..
                      "(planejado); use :take(idx) ou :head(n)/:tail(n) para uma cópia", 2)
            end
            error("smaug: view() não é suportado para dtype '"..self._dtype..
                  "'; use :take(idx) ou :head(n)/:tail(n) para uma cópia", 2)
        end
        start = start or 1
        len   = len or (self:len() - start + 1)
        local n = self:len()
        if type(start) ~= "number" or type(len) ~= "number"
           or start < 1 or len < 0 or start + len - 1 > n then
            error("smaug: view("..tostring(start)..", "..tostring(len)..
                  ") fora dos limites [1, "..n.."]", 2)
        end
        local r = self._d.view(self._c, start - 1, len)
        return wrap(r, self._dtype, self._name, self._parent or self)
    end

    -- take: nova série (cópia independente) com os elementos nas posições idx.
    function methods.take(self, idx)
        if type(idx) ~= "table" then error("smaug: take espera uma tabela de índices", 2) end
        local n   = self:len()
        local len = #idx
        local cidx = ffi.new("size_t[?]", len)
        for i = 1, len do
            local k = idx[i]
            if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
                error("smaug: take índice "..tostring(k).." fora dos limites [1, "..n.."]", 2)
            end
            cidx[i - 1] = k - 1
        end
        local r = self._d.take(self._c, cidx, len)
        if r == nil then error("smaug: take falhou", 2) end
        return wrap(r, self._dtype, self._name)
    end

    -- dropna: nova série sem elementos NULL.
    function methods.dropna(self)
        local n   = self:len()
        local idx = {}
        local j   = 0
        for i = 1, n do
            if not self:is_null(i) then j = j + 1; idx[j] = i end
        end
        return self:take(idx)
    end

    -- head/tail: cópia das primeiras/últimas n linhas.
    function methods.head(self, n)
        n = math.min(n or 5, self:len())
        local idx = {}
        for i = 1, n do idx[i] = i end
        return self:take(idx)
    end

    function methods.tail(self, n)
        local total = self:len()
        n = math.min(n or 5, total)
        local idx = {}
        for i = 1, n do idx[i] = total - n + i end
        return self:take(idx)
    end

    -- to_table: converte para tabela Lua. Nulos → na_value (default nil).
    function methods.to_table(self, na_value)
        local t = {}
        for i = 1, self:len() do
            local v = self:get(i)
            if v == nil then v = na_value end
            t[i] = v
        end
        return t
    end

    -- =====================================================================
    -- 6.3 — pares do DataSet: sample / to_string / to_markdown
    -- =====================================================================

    -- sample(n, [seed]): amostra n elementos sem reposição (Fisher-Yates parcial).
    -- Espelha DataSet:sample (take de índices), com len no lugar de nrows.
    function methods.sample(self, n, seed)
        local total = self:len()
        n = math.min(n or 1, total)
        if seed ~= nil then math.randomseed(seed) end
        local perm = {}
        for i = 1, total do perm[i] = i end
        for i = 1, n do
            local j = math.random(i, total)
            perm[i], perm[j] = perm[j], perm[i]
        end
        local idx = {}
        for i = 1, n do idx[i] = perm[i] end
        return self:take(idx)
    end

    local function cell_str(v) return v == nil and "NA" or tostring(v) end

    -- to_string([opts]): texto plano, índice + valor. opts.max_rows limita.
    -- Espelha DataSet:to_string (que mostra índice de linha), em 1 coluna.
    function methods.to_string(self, opts)
        opts = opts or {}
        local n     = self:len()
        local name  = self._name or "value"
        local limit = opts.max_rows and math.min(n, opts.max_rows) or n
        local w     = #name
        local cells = {}
        for i = 1, limit do
            local s = cell_str(self:get(i)); cells[i] = s
            if #s > w then w = #s end
        end
        local idxw = math.max(#tostring(limit > 0 and limit or 1), 1)
        local function pad(s, ww) return s .. string.rep(" ", ww - #s) end
        local out = { pad("", idxw) .. "  " .. name }
        for i = 1, limit do
            out[#out + 1] = pad(tostring(i), idxw) .. "  " .. pad(cells[i], w)
        end
        if n > limit then out[#out + 1] = "... ("..(n - limit).." linhas a mais)" end
        return table.concat(out, "\n")
    end

    -- to_markdown(): tabela Markdown de 1 coluna (sem índice, como DataSet:to_markdown).
    function methods.to_markdown(self)
        local n    = self:len()
        local name = self._name or "value"
        local w    = #name
        local cells = {}
        for i = 1, n do
            local s = cell_str(self:get(i)); cells[i] = s
            if #s > w then w = #s end
        end
        local function pad(s, ww) return s .. string.rep(" ", ww - #s) end
        local out = {}
        out[#out + 1] = "| " .. pad(name, w) .. " |"
        out[#out + 1] = "| " .. string.rep("-", w) .. " |"
        for i = 1, n do out[#out + 1] = "| " .. pad(cells[i], w) .. " |" end
        return table.concat(out, "\n")
    end

    -- =====================================================================
    -- astype
    -- =====================================================================

    -- trunca em direção a zero (igual ao cast (int64_t) do C)
    local function trunc_to_int(x)
        return x >= 0 and math.floor(x) or math.ceil(x)
    end

    -- astype(dtype): converte a série para outro dtype. Tolerante por elemento:
    -- inconversíveis → null. Nunca descarta a série inteira.
    function methods.astype(self, dtype, name)
        -- 3º argumento: string = name (retrocompat) | tabela = {name=, dayfirst=}
        local dayfirst = 0
        if type(name) == "table" then
            local opts = name
            name = opts.name
            if opts.dayfirst == true then dayfirst = 1
            elseif opts.dayfirst == false then dayfirst = 0 end
        end
        -- categorical é Lua puro — não está em DTYPES, mas é suportado
        if dtype == "categorical" then
            local Cat = Series.Categorical
            if not Cat then
                error("smaug: astype 'categorical' — CategoricalSeries não disponível", 2)
            end
            local vals = {}
            local n    = self:len()
            for i = 1, n do
                local v = self:get(i)
                vals[i] = v ~= nil and tostring(v) or NA
            end
            return Cat.from_table(vals, name or self._name)
        end
        if not DTYPES[dtype] then
            error("smaug: dtype desconhecido '" .. tostring(dtype) .. "'", 2)
        end
        local src = self._dtype
        local n   = self:len()
        local out = Series.new(dtype, n, name or self._name)

        for i = 1, n do
            local v = self:get(i)
            if v == nil then
                out:set_null(i)
            elseif src == "datetime" and dtype ~= "datetime" then
                if dtype == "string" then
                    local buf = ffi.new("char[26]")
                    C.smaug_dt_format(v, buf, 26)
                    out:set(i, ffi.string(buf))
                elseif dtype == "int64" then
                    out:set(i, trunc_to_int(v))
                else -- float64
                    out:set(i, tonumber(v))
                end
            elseif dtype == "datetime" and src ~= "datetime" then
                if src == "string" then
                    local ep = ffi.new("int64_t[1]")
                    if C.smaug_dt_parse(v, #v, ep, dayfirst) == 0 then
                        out:set(i, tonumber(ep[0]))
                    else
                        out:set_null(i)
                    end
                else
                    if is_nan(v) or v == math.huge or v == -math.huge then
                        out:set_null(i)
                    else
                        out:set(i, trunc_to_int(v))
                    end
                end
            elseif src == "bool" and dtype ~= "bool" then
                if dtype == "string" then
                    out:set(i, tostring(v))
                elseif dtype == "int64" then
                    out:set(i, v and 1 or 0)
                else -- float64
                    out:set(i, v and 1.0 or 0.0)
                end
            elseif dtype == "bool" and src ~= "bool" then
                if src == "string" then
                    if v == "true" then out:set(i, true)
                    elseif v == "false" then out:set(i, false)
                    else out:set_null(i) end
                else  -- int64/float64 → bool: rígido, só 0/1 (H.6.5.a)
                    if v == 0 or v == 1 then
                        out:set(i, v == 1)
                    else
                        error("smaug: astype('bool'): valor " .. tostring(v) .. " no índice "
                              .. i .. " não é 0/1; use :map(fn) para definir a regra", 2)
                    end
                end
            elseif src == "string" and dtype ~= "string" then
                local num = tonumber(v)
                if num == nil then
                    out:set_null(i)
                elseif dtype == "int64" then
                    if is_nan(num) or num == math.huge or num == -math.huge then
                        out:set_null(i)
                    else
                        out:set(i, trunc_to_int(num))
                    end
                else
                    out:set(i, num)
                end
            elseif dtype == "string" and src ~= "string" then
                out:set(i, tostring(v))
            elseif dtype == "int64" and src ~= "int64" then
                if is_nan(v) or v == math.huge or v == -math.huge then
                    out:set_null(i)
                else
                    out:set(i, trunc_to_int(v))
                end
            else
                out:set(i, v)
            end
        end
        return out
    end

    -- =====================================================================
    -- fillna
    -- =====================================================================

    -- fillna: nova Series com cada NULL substituído por value.
    -- Sem coerção de tipo. NaN é valor presente — fica intacto.
    function methods.fillna(self, value)
        if value == nil or value == NA then
            error("smaug: fillna requer um valor de preenchimento", 2)
        end
        local dt = self._dtype
        if dt == "string" then
            if type(value) ~= "string" then
                error("smaug: fillna em série string espera uma string Lua; "
                      .. "recebido " .. type(value), 2)
            end
        elseif dt == "bool" then
            if type(value) ~= "boolean" then
                error("smaug: fillna em série bool espera boolean (true/false); "
                      .. "recebido " .. type(value), 2)
            end
        else
            if type(value) ~= "number" then
                error("smaug: fillna em série " .. dt .. " espera um número; "
                      .. "recebido " .. type(value), 2)
            end
            if dt == "int64" and value % 1 ~= 0 then
                error("smaug: fillna em int64 requer valor inteiro (sem coerção); "
                      .. "recebido " .. tostring(value), 2)
            end
        end
        local n   = self:len()
        local out = Series.new(dt, n, self._name)
        for i = 1, n do
            if self:is_null(i) then
                out:set(i, value)
            else
                out:set(i, self:get(i))
            end
        end
        return out
    end

    -- =====================================================================
    -- map
    -- =====================================================================

    -- infer_from_value: reusa a fonte única definida em _factories.lua (Bloco H,
    -- H.2/H.6) em vez de uma cópia local incompleta. H.6.6.1: antes não
    -- reconhecia boolean — map(fn) com retorno true/false falhava mesmo com
    -- dtype="bool" explícito, porque o valor era rejeitado aqui antes de
    -- chegar no check_map_value que respeitaria o dtype declarado.
    local infer_from_value = I.infer_dtype_from_value

    local function check_map_value(v, dtype, i)
        if dtype == "int64" then
            if type(v) ~= "number" or v % 1 ~= 0 then
                error("smaug: map: tipo inconsistente no índice " .. i
                      .. " (esperado int64, recebido " .. type(v) .. ")", 4)
            end
        elseif dtype == "string" then
            if type(v) ~= "string" then
                error("smaug: map: tipo inconsistente no índice " .. i
                      .. " (esperado string, recebido " .. type(v) .. ")", 4)
            end
        elseif dtype == "bool" then
            if type(v) ~= "boolean" then
                error("smaug: map: tipo inconsistente no índice " .. i
                      .. " (esperado bool, recebido " .. type(v) .. ")", 4)
            end
        else  -- float64
            if type(v) ~= "number" then
                error("smaug: map: tipo inconsistente no índice " .. i
                      .. " (esperado float64, recebido " .. type(v) .. ")", 4)
            end
        end
    end

    -- map(fn, dtype?): aplica fn a cada elemento, devolvendo nova Series.
    -- nil retornado → null. dtype omitido → inferido do 1º retorno não-null.
    function methods.map(self, fn, dtype, name)
        if type(fn) ~= "function" then
            error("smaug: map espera uma função como 1º argumento", 2)
        end
        if dtype ~= nil and not DTYPES[dtype] then
            error("smaug: map: dtype desconhecido '" .. tostring(dtype) .. "'", 2)
        end

        local n       = self:len()
        local results = {}
        local inferred = dtype

        for i = 1, n do
            local v = self:get(i)
            local r = fn(v, i)
            if r == nil or r == NA then
                results[i] = nil
            else
                local rt = infer_from_value(r)
                if rt == nil then
                    error("smaug: map: retorno de tipo não suportado no índice "
                          .. i .. " (" .. type(r) .. ")", 2)
                end
                if inferred == nil then
                    inferred = rt
                else
                    check_map_value(r, inferred, i)
                end
                results[i] = r
            end
        end

        if inferred == nil then
            error("smaug: map: todos os retornos são nil — informe dtype explicitamente", 2)
        end

        local out = Series.new(inferred, n, name or self._name)
        for i = 1, n do
            if results[i] == nil then
                out:set_null(i)
            else
                out:set(i, results[i])
            end
        end
        return out
    end

    -- =====================================================================
    -- abs, round, clip
    -- =====================================================================

    function methods.abs(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: abs() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        return self:map(function(v) return v ~= nil and math.abs(v) or nil end, self._dtype, self._name)
    end

    function methods.round(self, ndigits)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: round() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        ndigits = ndigits or 0
        local factor = 10 ^ ndigits
        return self:map(function(v)
            if v == nil then return nil end
            if v >= 0 then
                return math.floor(v * factor + 0.5) / factor
            else
                return math.ceil(v * factor - 0.5) / factor
            end
        end, "float64", self._name)
    end

    function methods.clip(self, lo, hi)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: clip() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        if lo == nil and hi == nil then return self:clone() end
        return self:map(function(v)
            if v == nil then return nil end
            if lo ~= nil and v < lo then return lo end
            if hi ~= nil and v > hi then return hi end
            return v
        end, self._dtype, self._name)
    end
end
