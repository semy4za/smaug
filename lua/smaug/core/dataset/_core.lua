-- lua/smaug/core/dataset/_core.lua
--
-- Núcleo do DataSet: metatype, factories, CRUD de colunas, acesso,
-- seleção básica, assign, nunique, rename, describe, to_table,
-- metamétodos (__tostring, __index, __newindex, __len, __call).
--
-- Recebe I com: I.Series, I.DataSet, I.methods,
--               I.is_series, I.is_boolseries, I.is_categorical
-- Contribui: DataSet.new, from_columns, from_dict (factory),
--            todos os methods.* acima, metamétodos DataSet.*

local Display = require("smaug.core.display")

return function(I)
    local Series        = I.Series
    local DataSet       = I.DataSet
    local methods       = I.methods
    local is_series     = I.is_series
    local is_boolseries = I.is_boolseries
    local is_categorical = I.is_categorical

    -- =====================================================================
    -- Factories
    -- =====================================================================
    function DataSet.new(name)
        return setmetatable({
            _columns   = {},
            _col_names = {},
            _length    = nil,
            _name      = name or "DataSet",
        }, DataSet)
    end

    -- from_columns: constrói de lista ordenada { {nome, series_ou_tabela, dtype?}, ... }
    -- dtype omitido em qualquer par → Series.from_table infere (Series.infer_dtype,
    -- Bloco H H.2). Antes: default float64 silencioso, igual ao que o __call tinha.
    function DataSet.from_columns(pairs_list, name)
        local df = DataSet.new(name)
        for _, pair in ipairs(pairs_list) do
            local cname, data, dtype = pair[1], pair[2], pair[3]
            local col = is_series(data) and data
                        or Series.from_table(data, dtype, cname)
            df:add_column(cname, col)
        end
        return df
    end

    -- =====================================================================
    -- CRUD de colunas
    -- =====================================================================
    function methods.add_column(self, name, series)
        if type(name) ~= "string" then error("smaug: nome de coluna deve ser string", 2) end
        if not (is_series(series) or is_boolseries(series) or is_categorical(series)) then
            error("smaug: add_column espera uma Series ou Series<bool>", 2)
        end
        if self._columns[name] ~= nil then
            error("smaug: coluna '"..name.."' já existe; use df[\""..name.."\"] = s para atualizar", 2)
        end
        local n = series:len()
        if self._length == nil then
            self._length = n
        elseif n ~= self._length then
            error("smaug: coluna '"..name.."' tem "..n.." linhas; esperado "..self._length, 2)
        end
        self._columns[name] = series
        self._col_names[#self._col_names + 1] = name
        return self
    end

    function methods.update_column(self, name, series)
        if type(name) ~= "string" then error("smaug: nome de coluna deve ser string", 2) end
        if not (is_series(series) or is_boolseries(series) or is_categorical(series)) then
            error("smaug: update_column espera uma Series ou Series<bool>", 2)
        end
        if self._columns[name] == nil then
            error("smaug: coluna '"..name.."' não existe; use df[\""..name.."\"] = s para criar", 2)
        end
        local n = series:len()
        if n ~= self._length then
            error("smaug: coluna '"..name.."' tem "..n.." linhas; esperado "..self._length, 2)
        end
        self._columns[name] = series
        return self
    end

    function methods.drop_column(self, name)
        if self._columns[name] == nil then
            error("smaug: coluna '"..name.."' não existe", 2)
        end
        self._columns[name] = nil
        for i, n in ipairs(self._col_names) do
            if n == name then table.remove(self._col_names, i); break end
        end
        if #self._col_names == 0 then self._length = nil end
        return self
    end

    function methods.rename_column(self, old, new)
        if self._columns[old] == nil then error("smaug: coluna '"..old.."' não existe", 2) end
        if self._columns[new] ~= nil then error("smaug: coluna '"..new.."' já existe", 2) end
        self._columns[new] = self._columns[old]
        self._columns[old] = nil
        for i, n in ipairs(self._col_names) do
            if n == old then self._col_names[i] = new; break end
        end
        return self
    end

    -- =====================================================================
    -- Acesso / metadados
    -- =====================================================================
    -- _raw_column: acesso INTERNO à referência real da coluna (mesma Series
    -- guardada no frame). Usado pelo código interno (relacional, csv, stat) que
    -- só lê metadados/valores ou precisa de identidade de objeto — sem o custo
    -- de criar view a cada chamada. NÃO exposto ao usuário: mutar o retorno aqui
    -- altera o frame (é a referência viva). Público usa column() (protegido).
    function methods._raw_column(self, name)
        local c = self._columns[name]
        if c == nil then error("smaug: coluna '"..name.."' não existe", 2) end
        return c
    end

    -- column: acesso PÚBLICO protegido (9.2, mata o E2). Retorna uma view COW da
    -- coluna inteira, não a referência interna: leitura é zero-copy; a primeira
    -- mutação (set/set_null/append) destaca um buffer privado, deixando o frame
    -- intacto. `col = df:column("x"); col:set(...)` já não corrompe o frame.
    -- Categorical não tem view (é Lua puro: codes + dicionário), então recebe um
    -- clone (cópia profunda protegida) — mesmo contrato de "o frame não muda".
    function methods.column(self, name)
        local c = self._columns[name]
        if c == nil then error("smaug: coluna '"..name.."' não existe", 2) end
        if is_categorical(c) then
            return c:clone()
        end
        return c:view(1, c:len())
    end
    methods.col = methods.column

    function methods.has_column(self, name) return self._columns[name] ~= nil end

    function methods.columns(self)
        local t = {}
        for i, n in ipairs(self._col_names) do t[i] = n end
        return t
    end

    function methods.ncols(self) return #self._col_names end
    function methods.nrows(self) return self._length or 0 end
    methods.len = methods.nrows

    function methods.dtypes(self)
        local t = {}
        for _, n in ipairs(self._col_names) do t[n] = self._columns[n]._dtype end
        return t
    end

    -- 6.5: clone profundo (par de Series:clone). Cada coluna é clonada;
    -- preserva nome e ordem. DataSet vazio → novo DataSet vazio de mesmo nome.
    function methods.clone(self)
        local copy = DataSet.new(self._name)
        for _, name in ipairs(self._col_names) do
            copy:add_column(name, self._columns[name]:clone())
        end
        return copy
    end

    function methods.row(self, i, na_value)
        if type(i) ~= "number" or i < 1 or i > self:nrows() then
            error("smaug: linha "..tostring(i).." fora dos limites [1, "..self:nrows().."]", 2)
        end
        local r = {}
        for _, n in ipairs(self._col_names) do
            local v = self._columns[n]:get(i)
            if v == nil then v = na_value end
            r[n] = v
        end
        return r
    end

    -- =====================================================================
    -- Seleção de colunas / linhas → novo DataSet
    -- =====================================================================

    -- map_columns: helper local — aplica fn a cada coluna, retorna novo DataSet.
    local function map_columns(self, fn, new_name)
        local df = DataSet.new(new_name or self._name)
        for _, n in ipairs(self._col_names) do
            df:add_column(n, fn(self._columns[n]))
        end
        return df
    end
    I.map_columns = map_columns   -- exporta para _relational e _stat usarem

    function methods.select(self, names)
        if type(names) ~= "table" then error("smaug: select espera uma tabela de nomes", 2) end
        local df = DataSet.new(self._name)
        for _, n in ipairs(names) do
            df:add_column(n, self:_raw_column(n):clone())
        end
        return df
    end

    function methods.fillna(self, value)
        if value == nil then
            error("smaug: fillna requer um valor ou tabela {coluna=valor}", 2)
        end
        if type(value) ~= "table" then
            return map_columns(self, function(c) return c:fillna(value) end)
        end
        local df = DataSet.new(self._name)
        for _, n in ipairs(self._col_names) do
            local col = self._columns[n]
            if value[n] ~= nil then
                df:add_column(n, col:fillna(value[n]))
            else
                df:add_column(n, col)
            end
        end
        return df
    end

    function methods.take(self, idx)
        return map_columns(self, function(c) return c:take(idx) end)
    end

    function methods.head(self, n)
        return map_columns(self, function(c) return c:head(n) end)
    end

    function methods.tail(self, n)
        return map_columns(self, function(c) return c:tail(n) end)
    end

    function methods.iloc(self, start, stop)
        local total = self:nrows()
        start = start or 1
        stop  = stop  or total
        if start < 1 or stop > total or start > stop + 1 then
            error("smaug: iloc("..start..", "..stop..") fora dos limites [1, "..total.."]", 2)
        end
        local idx = {}
        for i = start, stop do idx[#idx + 1] = i end
        return self:take(idx)
    end

    function methods.sample(self, n, seed)
        local total = self:nrows()
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

    function methods.filter(self, mask)
        if not is_boolseries(mask) then
            error("smaug: filter espera uma Series<bool> (use coluna:gt/:lt/:eq)", 2)
        end
        if mask:len() ~= self:nrows() then
            error("smaug: filter com máscara de tamanho diferente ("..
                  mask:len().." vs "..self:nrows()..")", 2)
        end
        return map_columns(self, function(c) return c:filter(mask) end)
    end

    function methods.sort_by(self, col, ascending)
        local key = self:_raw_column(col)
        local idx = key:argsort(ascending)
        if idx == nil then
            error("smaug: sort_by não suporta nulos na coluna '"..col..
                  "' (use dropna primeiro)", 2)
        end
        return self:take(idx)
    end

    function methods.dropna(self, subset)
        local cols_to_check = subset or self._col_names
        if type(cols_to_check) ~= "table" then
            error("smaug: dropna espera nil ou uma lista de nomes de colunas", 2)
        end
        for _, n in ipairs(cols_to_check) do
            if self._columns[n] == nil then
                error("smaug: dropna: coluna '"..n.."' não existe", 2)
            end
        end
        local keep = {}
        for i = 1, self:nrows() do
            local row_ok = true
            for _, n in ipairs(cols_to_check) do
                if self._columns[n]:is_null(i) then row_ok = false; break end
            end
            if row_ok then keep[#keep + 1] = i end
        end
        return self:take(keep)
    end

    -- =====================================================================
    -- assign, nunique, rename
    -- =====================================================================
    function methods.assign(self, name, fn_or_series)
        if type(name) ~= "string" then
            error("smaug: assign — nome deve ser string", 2)
        end
        local col
        if is_series(fn_or_series) or is_boolseries(fn_or_series) or is_categorical(fn_or_series) then
            col = fn_or_series
        elseif type(fn_or_series) == "function" then
            col = fn_or_series(self)
            if not (is_series(col) or is_boolseries(col) or is_categorical(col)) then
                error("smaug: assign — função deve retornar uma Series", 2)
            end
        else
            error("smaug: assign — segundo argumento deve ser Series ou função", 2)
        end
        if col:len() ~= self:nrows() then
            error("smaug: assign — Series tem tamanho diferente do DataSet ("
                  ..col:len().." vs "..self:nrows()..")", 2)
        end
        if self:has_column(name) then
            local result = DataSet.new(self._name)
            for _, cname in ipairs(self._col_names) do
                if cname == name then
                    result:add_column(name, col)
                else
                    result:add_column(cname, self:_raw_column(cname):clone())
                end
            end
            return result
        end
        local result = DataSet.new(self._name)
        for _, cname in ipairs(self._col_names) do
            result:add_column(cname, self:_raw_column(cname):clone())
        end
        result:add_column(name, col)
        return result
    end

    function methods.nunique(self)
        local t = {}
        for _, name in ipairs(self._col_names) do
            t[name] = self:_raw_column(name):nunique()
        end
        return t
    end

    function methods.rename(self, mapping)
        if type(mapping) ~= "table" then
            error("smaug: rename() espera tabela {old=new, ...}", 2)
        end
        for old, new in pairs(mapping) do
            if not self:has_column(old) then
                error("smaug: rename() — coluna '"..old.."' não existe", 2)
            end
            if type(new) ~= "string" or new == "" then
                error("smaug: rename() — nome inválido para '"..old.."': "..tostring(new), 2)
            end
        end
        local result = DataSet.new(self._name)
        for _, cname in ipairs(self._col_names) do
            local new_name = mapping[cname] or cname
            result:add_column(new_name, self:_raw_column(cname):clone())
        end
        return result
    end

    -- =====================================================================
    -- describe e to_table
    -- =====================================================================
    function methods.describe(self)
        local t = {}
        for _, n in ipairs(self._col_names) do
            t[n] = self._columns[n]:describe()
        end
        return t
    end

    function methods.to_table(self, na_value)
        local t = {}
        for _, n in ipairs(self._col_names) do
            t[n] = self._columns[n]:to_table(na_value)
        end
        return t
    end

    -- =====================================================================
    -- Pretty-print (__tostring) — formatação via módulo display (fonte única)
    -- =====================================================================
    DataSet.__tostring = function(self)
        local names = self._col_names
        local nrows = self:nrows()
        if #names == 0 then return "DataSet '"..self._name.."' (vazio)" end
        local widths = {}
        local aligns = {}
        for _, n in ipairs(names) do
            widths[n] = Display.dwidth(n)
            aligns[n] = Display.align_for(self._columns[n]._dtype)
        end
        local idx, brk = Display.plan_rows(nrows, 10)
        local idxw = #tostring(nrows)
        local rows = {}
        for _, i in ipairs(idx) do
            rows[i] = {}
            for _, n in ipairs(names) do
                local s = Display.cell_str(Display.cell_of(self._columns[n], i))
                rows[i][n] = s
                local dw = Display.dwidth(s)
                if dw > widths[n] then widths[n] = dw end
            end
        end
        local out = {}
        local header = { string.rep(" ", idxw) }
        for _, n in ipairs(names) do header[#header + 1] = Display.pad(n, widths[n], aligns[n]) end
        out[#out + 1] = table.concat(header, "  ")
        for pos, i in ipairs(idx) do
            local line = { Display.pad(tostring(i), idxw) }
            for _, n in ipairs(names) do line[#line + 1] = Display.pad(rows[i][n], widths[n], aligns[n]) end
            out[#out + 1] = table.concat(line, "  ")
            if brk and pos == brk then
                local mk = { Display.pad("...", idxw) }
                for _, n in ipairs(names) do mk[#mk + 1] = Display.pad("...", widths[n], aligns[n]) end
                out[#out + 1] = table.concat(mk, "  ")
            end
        end
        return string.format("DataSet '%s' [%d linhas x %d colunas]\n%s",
            self._name, nrows, #names, table.concat(out, "\n"))
    end

    -- =====================================================================
    -- Metamétodos de acesso
    -- =====================================================================
    DataSet.__index = function(self, k)
        local m = methods[k]
        if m ~= nil then return m end
        if is_boolseries(k) then return self:filter(k) end
        if type(k) == "string" then return rawget(self, "_columns")[k] end
        return nil
    end

    DataSet.__newindex = function(self, k, v)
        if type(k) ~= "string" or k:sub(1,1) == "_" then
            rawset(self, k, v)
            return
        end
        if not (is_series(v) or is_boolseries(v) or is_categorical(v)) then
            local nrows = rawget(self, "_length")
            if nrows == nil then
                error("smaug: df[\""..k.."\"] = escalar requer DataSet não-vazio", 2)
            end
            v = Series.full(nrows, v, nil, k)
        end
        local cols = rawget(self, "_columns")
        if cols[k] ~= nil then
            self:update_column(k, v)
        else
            self:add_column(k, v)
        end
    end

    DataSet.__len = function(self) return self:nrows() end

    -- __call: DataSet({{"col", dados}, ...}, name?)
    -- dtype omitido → Series.from_table infere via Series.infer_dtype (Bloco H,
    -- H.2/H.6.1). Antes havia uma infer_dtype local aqui que não reconhecia
    -- boolean nativo (caía em int64 e quebrava no set); removida — fonte única
    -- agora é Series.infer_dtype (_factories.lua).
    setmetatable(DataSet, {
        __call = function(_, pairs_list, name)
            if type(pairs_list) ~= "table" then
                error("smaug: DataSet espera uma lista de pares {{\"col\", dados}, ...}", 2)
            end
            local df = DataSet.new(name)
            for _, pair in ipairs(pairs_list) do
                local cname, data, dtype = pair[1], pair[2], pair[3]
                if type(cname) ~= "string" then
                    error("smaug: nome de coluna deve ser string", 2)
                end
                local col
                if getmetatable(data) == DataSet then
                    error("smaug: coluna '"..cname.."': esperado Series, não DataSet", 2)
                elseif is_series(data) or is_boolseries(data) or is_categorical(data) then
                    col = data
                elseif type(data) == "table" then
                    col = Series.from_table(data, dtype, cname)
                else
                    error("smaug: coluna '"..cname.."': dados devem ser tabela ou Series", 2)
                end
                df:add_column(cname, col)
            end
            return df
        end
    })
end
