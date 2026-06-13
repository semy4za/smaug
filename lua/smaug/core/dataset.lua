-- lua/smaug/core/dataset.lua
--
-- DataSet: tabela 2D = coleção de Series alinhadas (mesmo número de linhas).
-- Cada coluna é uma Series independente; as colunas só compartilham o
-- comprimento, nunca os dados.
--
-- Atributos de instância:
--   _columns   : dict  nome -> Series
--   _col_names : array com a ordem das colunas
--   _length    : número de linhas (nil enquanto não há colunas)
--   _name      : rótulo opcional
--
-- Invariantes (garantidos por add_column):
--   * todas as colunas têm o mesmo _length;
--   * _col_names e _columns sempre sincronizados (mesma cardinalidade/chaves).
--
-- Posse por contrato (Modelo 3 — transferência de ownership lógica):
-- `add_column` assume a posse lógica da Series passada; ela não é clonada
-- (zero-copy, consistente com a filosofia COW da engine). O caller deve tratar
-- esta chamada como transferência de ownership — continuar usando `series`
-- para mutações após add_column é uma violação de contrato e produz aliasing.
-- Lua não impede tecnicamente essa violação; o contrato é semântico, não mecânico.
-- Operações de derivação (filter/take/sort_by/…) produzem colunas novas e
-- independentes, portanto DataSets derivados são sempre seguros.

local Series     = require("smaug.core.series")
local BoolSeries = require("smaug.core.boolseries")

local DataSet = {}
local methods = {}

local function is_series(x)     return getmetatable(x) == Series end
-- Aceita BoolSeries (legada) ou Series<bool> (novo dtype de primeira classe).
local function is_boolseries(x)
    return getmetatable(x) == BoolSeries
        or (type(x) == "table" and x._dtype == "bool")
end

-- =====================================================================
-- Construção
-- =====================================================================
function DataSet.new(name)
    return setmetatable({
        _columns   = {},
        _col_names = {},
        _length    = nil,
        _name      = name or "DataSet",
    }, DataSet)
end

-- Constrói de uma lista ORDENADA de pares { {nome, series_ou_tabela}, ... }.
-- Se o 2º elemento for uma tabela Lua, vira Series via from_table (dtype opcional
-- no 3º elemento do par, default float64).
function DataSet.from_columns(pairs_list, name)
    local df = DataSet.new(name)
    for _, pair in ipairs(pairs_list) do
        local cname, data, dtype = pair[1], pair[2], pair[3]
        local col = is_series(data) and data
                    or Series.from_table(data, dtype or "float64", cname)
        df:add_column(cname, col)
    end
    return df
end

-- =====================================================================
-- CRUD de colunas (mutam o DataSet; chainable)
-- =====================================================================
function methods.add_column(self, name, series)
    if type(name) ~= "string" then error("smaug: nome de coluna deve ser string", 2) end
    if not (is_series(series) or is_boolseries(series)) then
        error("smaug: add_column espera uma Series ou BoolSeries", 2)
    end
    if self._columns[name] ~= nil then
        error("smaug: coluna '"..name.."' já existe; use df[\""..name.."\"] = s para atualizar", 2)
    end
    local n = series:len()
    if self._length == nil then
        self._length = n
    elseif n ~= self._length then
        error("smaug: coluna '"..name.."' tem "..n.." linhas; esperado "..
              self._length, 2)
    end
    self._columns[name] = series
    self._col_names[#self._col_names + 1] = name
    return self
end

-- update_column: substitui uma coluna existente, preservando a posição.
-- Valida o número de linhas. Não pode ser usada para criar colunas novas.
function methods.update_column(self, name, series)
    if type(name) ~= "string" then error("smaug: nome de coluna deve ser string", 2) end
    if not (is_series(series) or is_boolseries(series)) then
        error("smaug: update_column espera uma Series ou BoolSeries", 2)
    end
    if self._columns[name] == nil then
        error("smaug: coluna '"..name.."' não existe; use df[\""..name.."\"] = s para criar", 2)
    end
    local n = series:len()
    if n ~= self._length then
        error("smaug: coluna '"..name.."' tem "..n.." linhas; esperado "..
              self._length, 2)
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
-- col(): acesso mutável explícito à coluna interna. Devolve a mesma referência
-- Lua armazenada no DataSet; mutações via esta referência afetam o DataSet
-- diretamente (aliasing intencional, coerente com o Modelo 3 de ownership).
-- COW funciona corretamente: se a coluna for uma view e receber um set/append,
-- o detach ocorre no struct em si — o DataSet passa a apontar para o buffer
-- privado sem que o pai seja afetado. Se quiser uma cópia independente, use
-- :col(name):clone().
function methods.column(self, name)
    local c = self._columns[name]
    if c == nil then error("smaug: coluna '"..name.."' não existe", 2) end
    return c
end
methods.col = methods.column

function methods.has_column(self, name) return self._columns[name] ~= nil end
function methods.columns(self)
    local t = {}
    for i, n in ipairs(self._col_names) do t[i] = n end   -- cópia defensiva
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

-- Linha i (1-based) como tabela Lua { coluna = valor }. Nulos viram na_value.
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
-- Seleção de colunas / linhas -> novo DataSet
-- =====================================================================
-- Constrói um novo DataSet aplicando uma transformação a cada coluna.
local function map_columns(self, fn, new_name)
    local df = DataSet.new(new_name or self._name)
    for _, n in ipairs(self._col_names) do
        df:add_column(n, fn(self._columns[n]))
    end
    return df
end

-- select: novo DataSet com as colunas nomeadas, na ordem dada.
-- Cada coluna é CLONADA para garantir independência: mutations no DataSet
-- derivado não afetam o original e vice-versa. Esta é a semântica correta
-- para uma operação de derivação (projeção), não um alias.
function methods.select(self, names)
    if type(names) ~= "table" then error("smaug: select espera uma tabela de nomes", 2) end
    local df = DataSet.new(self._name)
    for _, n in ipairs(names) do
        df:add_column(n, self:column(n):clone())   -- clone garante independência
    end
    return df
end

-- fillna: novo DataSet com NULLs preenchidos.
--   fillna(valor)          -> aplica `valor` a TODAS as colunas
--   fillna({col = valor})  -> por coluna; colunas omitidas mantêm seus nulos
-- Cada coluna usa Series:fillna (mesmo contrato: sem coerção de tipo).
function methods.fillna(self, value)
    if value == nil then
        error("smaug: fillna requer um valor ou tabela {coluna=valor}", 2)
    end
    -- caso 1: valor escalar → todas as colunas
    if type(value) ~= "table" then
        return map_columns(self, function(c) return c:fillna(value) end)
    end
    -- caso 2: mapa {col = valor} → só as colunas citadas; resto inalterado
    local df = DataSet.new(self._name)
    for _, n in ipairs(self._col_names) do
        local col = self._columns[n]
        if value[n] ~= nil then
            df:add_column(n, col:fillna(value[n]))
        else
            df:add_column(n, col)   -- mantém a coluna como está (com nulos)
        end
    end
    return df
end

-- take: novo DataSet com as linhas nos índices idx (tabela 1-based).
function methods.take(self, idx)
    return map_columns(self, function(c) return c:take(idx) end)
end

function methods.head(self, n)
    return map_columns(self, function(c) return c:head(n) end)
end

function methods.tail(self, n)
    return map_columns(self, function(c) return c:tail(n) end)
end

-- iloc(start, stop): faixa de linhas 1-based inclusiva -> novo DataSet.
function methods.iloc(self, start, stop)
    local total = self:nrows()
    start = start or 1
    stop  = stop or total
    if start < 1 or stop > total or start > stop + 1 then
        error("smaug: iloc("..start..", "..stop..") fora dos limites [1, "..total.."]", 2)
    end
    local idx = {}
    for i = start, stop do idx[#idx + 1] = i end
    return self:take(idx)
end

-- sample(n): n linhas aleatórias (sem reposição) -> novo DataSet.
function methods.sample(self, n, seed)
    local total = self:nrows()
    n = math.min(n or 1, total)
    if seed ~= nil then math.randomseed(seed) end
    -- Fisher-Yates parcial sobre uma permutação de 1..total
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

-- filter(mask): novo DataSet só com as linhas onde a máscara é true.
-- Aceita Series<bool> (novo) ou BoolSeries (legado).
function methods.filter(self, mask)
    if not is_boolseries(mask) then
        error("smaug: filter espera uma Series<bool> ou BoolSeries (use coluna:gt/:lt/:eq)", 2)
    end
    if mask:len() ~= self:nrows() then
        error("smaug: filter com máscara de tamanho diferente ("..
              mask:len().." vs "..self:nrows()..")", 2)
    end
    return map_columns(self, function(c) return c:filter(mask) end)
end

-- sort_by(col, ascending): novo DataSet ordenado pela permutação da coluna-chave.
function methods.sort_by(self, col, ascending)
    local key = self:column(col)
    local idx = key:argsort(ascending)
    if idx == nil then
        error("smaug: sort_by não suporta nulos na coluna '"..col..
              "' (use dropna primeiro)", 2)
    end
    return self:take(idx)
end

-- dropna: novo DataSet sem as linhas que têm pelo menos um NULL.
--   dropna()         → verifica TODAS as colunas
--   dropna({"a","b"})→ verifica apenas as colunas listadas (subset)
-- Produz DataSet independente via take() (colunas novas via Series:take).
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
            if self._columns[n]:is_null(i) then
                row_ok = false
                break
            end
        end
        if row_ok then keep[#keep + 1] = i end
    end
    return self:take(keep)
end

-- =====================================================================
-- Inspeção
-- =====================================================================
-- describe: tabela { coluna = (describe da Series) } para colunas numéricas.
function methods.describe(self)
    local t = {}
    for _, n in ipairs(self._col_names) do
        t[n] = self._columns[n]:describe()
    end
    return t
end

-- to_table: dict { coluna = {valores} } (nulos viram na_value).
function methods.to_table(self, na_value)
    local t = {}
    for _, n in ipairs(self._col_names) do
        t[n] = self._columns[n]:to_table(na_value)
    end
    return t
end

-- =====================================================================
-- Pretty-print tabular
-- =====================================================================
local function cell_str(v)
    if v == nil then return "NA" end
    if type(v) == "number" then
        if v % 1 == 0 then return string.format("%d", v) end
        return string.format("%.4g", v)
    end
    return tostring(v)
end

DataSet.__tostring = function(self)
    local names = self._col_names
    local nrows = self:nrows()
    if #names == 0 then return "DataSet '"..self._name.."' (vazio)" end

    local limit = math.min(nrows, 10)
    -- larguras: max entre nome e células exibidas (+ a coluna de índice)
    local widths = {}
    for _, n in ipairs(names) do widths[n] = #n end
    local idxw = #tostring(nrows)
    local rows = {}
    for i = 1, limit do
        local row = {}
        for _, n in ipairs(names) do
            local s = cell_str(self._columns[n]:get(i))
            row[n] = s
            if #s > widths[n] then widths[n] = #s end
        end
        rows[i] = row
    end

    local function pad(s, w) return s .. string.rep(" ", w - #s) end
    local out = {}
    -- cabeçalho
    local header = { string.rep(" ", idxw) }
    for _, n in ipairs(names) do header[#header + 1] = pad(n, widths[n]) end
    out[#out + 1] = table.concat(header, "  ")
    -- linhas
    for i = 1, limit do
        local line = { pad(tostring(i), idxw) }
        for _, n in ipairs(names) do line[#line + 1] = pad(rows[i][n], widths[n]) end
        out[#out + 1] = table.concat(line, "  ")
    end
    if nrows > limit then out[#out + 1] = "... ("..(nrows - limit).." linhas a mais)" end

    return string.format("DataSet '%s' [%d linhas x %d colunas]\n%s",
        self._name, nrows, #names, table.concat(out, "\n"))
end

-- __index: df["coluna"] OU df:metodo() OU df[bool_series].
-- Prioridades: método > BoolSeries (filtragem) > string (coluna).
-- Para coluna cujo nome colide com um método, use df:column(nome).
-- df[mask] é açúcar para df:filter(mask); semântica idêntica.
DataSet.__index = function(self, k)
    local m = methods[k]
    if m ~= nil then return m end
    if is_boolseries(k) then return self:filter(k) end
    if type(k) == "string" then return rawget(self, "_columns")[k] end
    return nil
end

-- __newindex: df["coluna"] = serie_ou_escalar
-- Semântica: muta o DataSet in-place (consistente com add_column/update_column).
--   - Series ou BoolSeries: passada diretamente.
--   - Escalar (string, number, boolean): broadcast para Series.full(nrows, val).
-- Invariante preservada: todas as colunas mantêm o mesmo número de linhas.
-- Coluna existente → update_column (substitui, preserva posição).
-- Coluna nova      → add_column (acrescenta ao fim).
DataSet.__newindex = function(self, k, v)
    -- atributos internos (_columns, _col_names, etc.) passam direto
    if type(k) ~= "string" or k:sub(1,1) == "_" then
        rawset(self, k, v)
        return
    end
    -- converte escalar em Series via broadcast
    if not (is_series(v) or is_boolseries(v)) then
        local nrows = rawget(self, "_length")
        if nrows == nil then
            error("smaug: df[\""..k.."\"] = escalar requer DataSet não-vazio", 2)
        end
        v = Series.full(nrows, v, nil, k)
    end
    -- add ou update dependendo se a coluna já existe
    local cols = rawget(self, "_columns")
    if cols[k] ~= nil then
        self:update_column(k, v)
    else
        self:add_column(k, v)
    end
end

DataSet.__len = function(self) return self:nrows() end

-- __call: smaug.DataSet({{"col", dados}, ...}, name?)
-- Permite usar a classe como construtor público: DataSet({...})
-- Preserva acesso a DataSet.from_columns, DataSet.new etc. via a classe.
-- Lógica de inferência de dtype: string→"string", inteiro→"int64",
-- fracionário→"float64". Series/BoolSeries passadas diretamente.
local function infer_dtype(arr)
    for _, v in ipairs(arr) do
        if type(v) == "string" then return "string" end
    end
    for _, v in ipairs(arr) do
        if type(v) == "number" and v % 1 ~= 0 then return "float64" end
    end
    return "int64"
end

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
            elseif is_series(data) or is_boolseries(data) then
                col = data
            elseif type(data) == "table" then
                dtype = dtype or infer_dtype(data)
                col = Series.from_table(data, dtype, cname)
            else
                error("smaug: coluna '"..cname.."': dados devem ser tabela ou Series", 2)
            end
            df:add_column(cname, col)
        end
        return df
    end
})

return DataSet
