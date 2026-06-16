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
local ffi        = require("ffi")
local C          = require("smaug.ffi_loader")

local DataSet = {}
local methods = {}

local function is_series(x)     return getmetatable(x) == Series end
-- Detecta uma Series<bool> — o dtype booleano de primeira classe do Smaug.
local function is_boolseries(x)
    return type(x) == "table" and x._dtype == "bool"
end

local function is_categorical(x)
    return type(x) == "table" and x._dtype == "categorical"
end

-- Igualdade estrutural de duas colunas (Series, Series<bool> ou Categorical).
-- Para Series usa o :equals nativo (NaN estrutural). Para os demais, compara
-- dtype, tamanho e valores posição a posição (nulls incluídos).
local function column_equals(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if a._dtype ~= b._dtype then return false end
    if is_series(a) and is_series(b) then return a:equals(b) end
    -- bool / categorical: comparação elemento a elemento
    if a:len() ~= b:len() then return false end
    for i = 1, a:len() do
        local va, vb = a:get(i), b:get(i)
        if (va == nil) ~= (vb == nil) then return false end
        if va ~= nil and va ~= vb then return false end
    end
    return true
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
    if not (is_series(series) or is_boolseries(series) or is_categorical(series)) then
        error("smaug: update_column espera uma Series ou Series<bool>", 2)
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
        error("smaug: filter espera uma Series<bool> (use coluna:gt/:lt/:eq)", 2)
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
-- =====================================================================
-- Concat (Anel 2 — Operações Relacionais)
--
-- concat(outros, [nome]): empilha DataSets verticalmente.
-- Todos devem ter as mesmas colunas com os mesmos dtypes.
-- Retorna um novo DataSet independente.
--
-- Uso:
--   smaug.concat({ds1, ds2, ds3})
--   smaug.concat({ds1, ds2}, "resultado")
--   DataSet.concat({ds1, ds2})          -- alias de classe
-- =====================================================================

local function concat_datasets(list, name)
    if type(list) ~= "table" or #list == 0 then
        error("smaug: concat espera uma lista não-vazia de DataSets", 2)
    end

    -- primeiro DataSet como referência de esquema
    local ref = list[1]
    if getmetatable(ref) ~= DataSet then
        error("smaug: concat — elemento 1 não é um DataSet", 2)
    end
    local col_names = ref._col_names

    -- validar esquema de todos os outros
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
            local dt1 = ref:column(cname)._dtype
            local dt2 = ds:column(cname)._dtype
            if dt1 ~= dt2 then
                error("smaug: concat — coluna '"..cname.."': dtype incompatível"
                      .." ('"..dt1.."' vs '"..dt2.."')", 2)
            end
        end
    end

    -- construir: por coluna, coleta todos os valores e cria Series nova
    local result = DataSet.new(name or ref._name)
    local NA = Series.NA

    for _, cname in ipairs(col_names) do
        local dtype = ref:column(cname)._dtype
        local vals  = {}
        for _, ds in ipairs(list) do
            local col = ds:column(cname)
            for i = 1, col:len() do
                local v = col:get(i)
                vals[#vals + 1] = (v == nil) and NA or v
            end
        end
        result:add_column(cname, Series.from_table(vals, dtype, cname))
    end
    return result
end

-- Expõe como método de classe e como função do módulo (via smaug.concat)
DataSet.concat = concat_datasets
function methods.concat(self, other, name)
    -- ds1:concat(ds2) ou ds1:concat({ds2, ds3})
    if getmetatable(other) == DataSet then
        return concat_datasets({self, other}, name)
    elseif type(other) == "table" then
        return concat_datasets({self, unpack(other)}, name)
    end
    error("smaug: concat espera um DataSet ou lista de DataSets", 2)
end

-- =====================================================================
-- Join / Merge (Anel 2 — Operações Relacionais)
--
-- ds:join(other, on, [how], [suffixes])
--
-- Parâmetros:
--   on       : string ou {left_key, right_key} — coluna(s) de junção
--   how      : "inner" (default), "left", "right", "outer"
--   suffixes : tabela {esq, dir} para colunas com mesmo nome (default {"_left","_right"})
--
-- Implementação: hash join — O(n+m) no tamanho das tabelas.
--   1. Constrói hash table do lado direito: key → lista de índices de linha
--   2. Varre o lado esquerdo e acumula pares (i_left, i_right)
--   3. Para outer/right, acumula os índices direitos sem match
--   4. Monta o DataSet resultado coluna a coluna
--
-- Restrições:
--   * coluna(s) de junção não podem ter nulos nos dois lados
--   * right join é implementado como left join com os operandos invertidos
-- =====================================================================

-- Converte valor de chave para string para uso como chave de tabela Lua.
local function key_to_str(v)
    if v == nil then return "\0NULL\0" end
    return type(v) .. ":" .. tostring(v)
end

-- Extrai valor de chave de uma linha (chave simples ou composta).
local function join_key(col_list, row)
    if #col_list == 1 then return key_to_str(col_list[1]:get(row)) end
    local parts = {}
    for _, c in ipairs(col_list) do parts[#parts+1] = key_to_str(c:get(row)) end
    return table.concat(parts, "\1")
end

-- Resolve os nomes das colunas no resultado, aplicando sufixos onde há conflito.
local function resolve_names(left_names, right_names, join_keys_set, suffixes)
    local sl, sr = suffixes[1] or "_left", suffixes[2] or "_right"
    -- colunas da direita que não são chave de junção
    local right_non_key = {}
    for _, n in ipairs(right_names) do
        if not join_keys_set[n] then right_non_key[#right_non_key+1] = n end
    end
    -- detectar conflitos entre esquerda e direita (excluindo chaves)
    local left_set = {}
    for _, n in ipairs(left_names) do left_set[n] = true end

    local result_left  = {}   -- {original, final}
    local result_right = {}

    for _, n in ipairs(left_names) do
        -- se a coluna esquerda é chave de junção, não recebe sufixo
        if join_keys_set[n] then
            result_left[#result_left+1] = {n, n}
        else
            -- recebe sufixo só se há coluna direita (não-chave) com mesmo nome
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

-- Constrói uma coluna do resultado a partir de pares de índices.
-- i_left=0 ou i_right=0 significa NULL naquele lado.
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

function methods.join(self, other, on, how, suffixes)
    -- validação de parâmetros
    if getmetatable(other) ~= DataSet then
        error("smaug: join — 'other' deve ser um DataSet", 2)
    end
    how      = how      or "inner"
    suffixes = suffixes or {"_left", "_right"}

    if how ~= "inner" and how ~= "left" and how ~= "right" and how ~= "outer" then
        error("smaug: join — 'how' deve ser 'inner', 'left', 'right' ou 'outer'", 2)
    end

    -- right join = left join com operandos invertidos
    if how == "right" then
        return other:join(self, on, "left", {suffixes[2], suffixes[1]})
    end

    -- resolver chaves
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

    local left_key_cols  = {}
    for _, k in ipairs(left_key_names)  do left_key_cols[#left_key_cols+1]   = self:column(k)  end
    local right_key_cols = {}
    for _, k in ipairs(right_key_names) do right_key_cols[#right_key_cols+1] = other:column(k) end

    -- set de chaves de junção (para resolver nomes)
    local join_keys_set = {}
    for _, k in ipairs(left_key_names)  do join_keys_set[k] = true end
    for _, k in ipairs(right_key_names) do join_keys_set[k] = true end

    local nl = self:nrows()
    local nr = other:nrows()
    local NA = Series.NA

    -- 1. Construir hash table do lado direito: key_str → {idx, ...}
    local hash = {}
    for i = 1, nr do
        local k = join_key(right_key_cols, i)
        if hash[k] then
            hash[k][#hash[k]+1] = i
        else
            hash[k] = {i}
        end
    end

    -- 2. Varrer lado esquerdo, acumular pares (i_left, i_right)
    local pairs_idx      = {}   -- {i_left, i_right}; 0 = NULL
    local right_matched  = {}   -- para outer: registrar índices direitos com match

    for i = 1, nl do
        local k = join_key(left_key_cols, i)
        local matches = hash[k]
        if matches then
            for _, j in ipairs(matches) do
                pairs_idx[#pairs_idx+1] = {i, j}
                right_matched[j] = true
            end
        elseif how == "left" or how == "outer" then
            pairs_idx[#pairs_idx+1] = {i, 0}   -- 0 = NULL no lado direito
        end
    end

    -- 3. Para outer: adicionar linhas direitas sem match
    if how == "outer" then
        for j = 1, nr do
            if not right_matched[j] then
                pairs_idx[#pairs_idx+1] = {0, j}
            end
        end
    end

    -- 4. Resolver nomes das colunas
    local res_left, res_right = resolve_names(
        self._col_names, other._col_names, join_keys_set, suffixes)

    -- 5. Montar DataSet resultado
    local result = DataSet.new(self._name .. "_join_" .. other._name)

    -- colunas do lado esquerdo (inclui chave com valor esquerdo;
    -- em outer, quando i_left=0 a chave vem do lado direito)
    for ci, pair in ipairs(res_left) do
        local orig, final = pair[1], pair[2]
        local src = self:column(orig)
        if join_keys_set[orig] then
            -- chave: em outer com i_left=0 usa valor da chave direita
            local right_key_idx = 1
            for ri, rk in ipairs(right_key_names) do
                if rk == orig or left_key_names[ri] == orig then
                    right_key_idx = ri; break
                end
            end
            local right_key_src = other:column(right_key_names[right_key_idx] or right_key_names[1])
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

    -- colunas do lado direito (exceto chave)
    for _, pair in ipairs(res_right) do
        local orig, final = pair[1], pair[2]
        local src = other:column(orig)
        result:add_column(final, build_col(src, pairs_idx, "right", NA))
    end

    return result
end

-- =====================================================================
-- GroupBy (Anel 2 — Operações Relacionais)
--
-- Implementação: sort-based. Ordena pela(s) chave(s) via argsort,
-- percorre runs contíguos e aplica a agregação em cada grupo.
-- Zero infraestrutura de hash — reutiliza o argsort existente.
--
-- API:
--   ds:groupby("uf"):sum()              → todas as colunas numéricas
--   ds:groupby("uf"):sum("v1","v2")     → colunas específicas
--   ds:groupby("uf"):mean("pop")
--   ds:groupby("uf"):min("pop")
--   ds:groupby("uf"):max("pop")
--   ds:groupby("uf"):count()            → coluna "count" (int64)
--   ds:groupby({"uf","ano"}):sum()      → chave composta
--
-- Restrições:
--   * coluna(s)-chave não podem ter nulos (use dropna primeiro)
--   * colunas bool e string são ignoradas nas agregações numéricas
--   * count conta todas as linhas do grupo (incluindo nulos nas outras cols)
-- =====================================================================

local GroupBy   = {}
GroupBy.__index = GroupBy

-- Compara dois valores de chave. Suporta string, número e bool.
local function key_eq(a, b)
    if type(a) ~= type(b) then return false end
    return a == b
end

-- Extrai o valor de chave de uma linha, suportando chave simples ou composta.
-- Para chave composta retorna uma tabela {v1, v2, ...}.
local function get_key(key_cols, row)
    if #key_cols == 1 then
        return key_cols[1]:get(row)
    end
    local k = {}
    for _, c in ipairs(key_cols) do k[#k+1] = c:get(row) end
    return k
end

-- Compara chaves compostas.
local function keys_eq(a, b)
    if type(a) ~= "table" then return key_eq(a, b) end
    if #a ~= #b then return false end
    for i = 1, #a do
        if not key_eq(a[i], b[i]) then return false end
    end
    return true
end

-- Mapeia dtype Smaug → código de kind para smaug_multi_argsort_ffi.
local SORT_COL_KIND = {
    float64  = 0,   -- SMAUG_COL_F64
    int64    = 1,   -- SMAUG_COL_I64
    string   = 2,   -- SMAUG_COL_STR
    datetime = 3,   -- SMAUG_COL_DT
    bool     = 4,   -- SMAUG_COL_BOOL
}

-- multi_argsort: sort estável multi-coluna via C (Grupo C Fase 3).
-- Retorna tabela Lua 1-based de índices ordenados.
-- Fallback Lua para dtypes não cobertos (categorical).
local function multi_argsort(ds, key_names)
    local n = ds:nrows()

    -- DataSet vazio: sem linhas para ordenar
    if n == 0 then return {} end

    -- Validar nulos e coletar colunas
    local cols_lua = {}
    for _, name in ipairs(key_names) do
        local col = ds:column(name)
        for i = 1, n do
            if col:is_null(i) then
                error("smaug: groupby — coluna '"..name.."' tem nulos"
                      .." (use dropna primeiro)", 4)
            end
        end
        cols_lua[#cols_lua+1] = col
    end

    -- Verificar se todos os dtypes têm suporte C
    local all_c = true
    for _, col in ipairs(cols_lua) do
        if not SORT_COL_KIND[col._dtype] then
            all_c = false; break
        end
    end

    if all_c and #key_names > 0 then
        -- Caminho C: monta array de smaug_sort_col_ffi_t
        local ffi_cols = ffi.new("smaug_sort_col_ffi_t[?]", #cols_lua)
        for k, col in ipairs(cols_lua) do
            ffi_cols[k-1].kind = SORT_COL_KIND[col._dtype]
            ffi_cols[k-1].ptr  = ffi.cast("void*", col._c)
        end
        local perm_ptr = C.smaug_multi_argsort_ffi(ffi_cols, #cols_lua, n)
        -- NULL aqui é OOM real (n>0 já verificado acima)
        if perm_ptr == nil then
            error("smaug: multi_argsort — OOM", 4)
        end
        -- Converter 0-based C → 1-based Lua
        local idx = {}
        for i = 0, n - 1 do idx[i+1] = tonumber(perm_ptr[i]) + 1 end
        C.smaug_free(perm_ptr)
        return idx
    end

    -- Fallback Lua: dtypes sem suporte C (categorical, etc.)
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

-- Constrói a lista de grupos: { key=valor_ou_tabela, idx={linha,...} }
local function build_groups(ds, key_names)
    local perm = multi_argsort(ds, key_names)
    local key_cols = {}
    for _, name in ipairs(key_names) do key_cols[#key_cols+1] = ds:column(name) end

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

-- Determina quais colunas agregar: as pedidas, ou todas as numéricas exceto chaves.
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
            local dt = ds:column(c)._dtype
            if dt == "float64" or dt == "int64" then
                result[#result+1] = c
            end
        end
    end
    return result
end

-- Funções de agregação elementares.
local function agg_sum(col, idx)
    local s = 0
    for _, i in ipairs(idx) do
        local v = col:get(i); if v ~= nil then s = s + v end
    end
    return s
end
local function agg_mean(col, idx)
    local s, n = 0, 0
    for _, i in ipairs(idx) do
        local v = col:get(i); if v ~= nil then s = s + v; n = n + 1 end
    end
    return n > 0 and (s / n) or nil
end
local function agg_min(col, idx)
    local m = nil
    for _, i in ipairs(idx) do
        local v = col:get(i)
        if v ~= nil and (m == nil or v < m) then m = v end
    end
    return m
end
local function agg_max(col, idx)
    local m = nil
    for _, i in ipairs(idx) do
        local v = col:get(i)
        if v ~= nil and (m == nil or v > m) then m = v end
    end
    return m
end
local function agg_std(col, idx)
    local vals = {}
    for _, i in ipairs(idx) do
        local v = col:get(i); if v ~= nil then vals[#vals+1] = v end
    end
    local n = #vals
    if n < 2 then return nil end
    local mean = 0; for _, v in ipairs(vals) do mean = mean + v end; mean = mean / n
    local s = 0; for _, v in ipairs(vals) do local d = v - mean; s = s + d*d end
    return math.sqrt(s / (n - 1))
end
local function agg_var(col, idx)
    local vals = {}
    for _, i in ipairs(idx) do
        local v = col:get(i); if v ~= nil then vals[#vals+1] = v end
    end
    local n = #vals
    if n < 2 then return nil end
    local mean = 0; for _, v in ipairs(vals) do mean = mean + v end; mean = mean / n
    local s = 0; for _, v in ipairs(vals) do local d = v - mean; s = s + d*d end
    return s / (n - 1)
end
local function agg_median(col, idx)
    local vals = {}
    for _, i in ipairs(idx) do
        local v = col:get(i); if v ~= nil then vals[#vals+1] = v end
    end
    local n = #vals
    if n == 0 then return nil end
    table.sort(vals)
    local m = math.floor(n / 2)
    return (n % 2 == 1) and vals[m+1] or (vals[m] + vals[m+1]) / 2
end
local function agg_first(col, idx)
    for _, i in ipairs(idx) do
        local v = col:get(i); if v ~= nil then return v end
    end
    return nil
end
local function agg_last(col, idx)
    local last = nil
    for _, i in ipairs(idx) do
        local v = col:get(i); if v ~= nil then last = v end
    end
    return last
end
local function agg_nunique(col, idx)
    local seen = {}; local cnt = 0
    for _, i in ipairs(idx) do
        local v = col:get(i)
        if v ~= nil then
            local k = tostring(v)
            if not seen[k] then seen[k] = true; cnt = cnt + 1 end
        end
    end
    return cnt
end
local function agg_prod(col, idx)
    local p, n = 1, 0
    for _, i in ipairs(idx) do
        local v = col:get(i); if v ~= nil then p = p * v; n = n + 1 end
    end
    return n > 0 and p or nil
end

-- Monta o DataSet de resultado: colunas-chave + colunas agregadas.
local function build_result(gb, agg_fn, col_names, out_dtype_override)
    local ds       = gb._ds
    local key_names = gb._key_names
    local groups   = gb._groups
    local key_set  = gb._key_set

    local result = DataSet.new(ds._name .. "_groupby")

    -- colunas-chave
    if #key_names == 1 then
        local key_dtype = ds:column(key_names[1])._dtype
        local vals = {}
        for _, g in ipairs(groups) do vals[#vals+1] = g.key end
        result:add_column(key_names[1],
            Series.from_table(vals, key_dtype, key_names[1]))
    else
        -- chave composta: uma coluna por campo
        for ki, kname in ipairs(key_names) do
            local key_dtype = ds:column(kname)._dtype
            local vals = {}
            for _, g in ipairs(groups) do vals[#vals+1] = g.key[ki] end
            result:add_column(kname,
                Series.from_table(vals, key_dtype, kname))
        end
    end

    -- colunas agregadas
    local agg_cols = resolve_agg_cols(ds, key_set, col_names)
    for _, cname in ipairs(agg_cols) do
        local src    = ds:column(cname)
        local vals   = {}
        local out_name = cname
        for gi, g in ipairs(groups) do
            local v = agg_fn(src, g.idx)
            vals[gi] = (v ~= nil) and v or Series.NA
        end
        -- dtype do resultado
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
        result:add_column(cname,
            Series.from_table(vals, out_dtype, out_name))
    end
    return result
end

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

-- groupby:nunique(): número de valores distintos não-nulos por grupo.
-- Retorna DataSet com chave + uma coluna "nunique" por coluna agregada.
function GroupBy:nunique(...)
    local cols = select('#', ...) > 0 and {...} or nil
    local ds, key_names, key_set, groups = self._ds, self._key_names, self._key_set, self._groups
    local result = DataSet.new(ds._name .. "_groupby")
    -- colunas-chave
    if #key_names == 1 then
        local key_dtype = ds:column(key_names[1])._dtype
        local vals = {}
        for _, g in ipairs(groups) do vals[#vals+1] = g.key end
        result:add_column(key_names[1], Series.from_table(vals, key_dtype, key_names[1]))
    else
        for ki, kname in ipairs(key_names) do
            local key_dtype = ds:column(kname)._dtype
            local vals = {}
            for _, g in ipairs(groups) do vals[#vals+1] = g.key[ki] end
            result:add_column(kname, Series.from_table(vals, key_dtype, kname))
        end
    end
    local agg_cols = resolve_agg_cols(ds, key_set, cols)
    for _, cname in ipairs(agg_cols) do
        local src = ds:column(cname)
        local vals = {}
        for _, g in ipairs(groups) do vals[#vals+1] = agg_nunique(src, g.idx) end
        result:add_column(cname, Series.from_table(vals, "int64", cname))
    end
    return result
end

-- groupby:quantile(q): percentil por grupo.
function GroupBy:quantile(q, ...)
    if type(q) ~= "number" or q < 0 or q > 1 then
        error("smaug: groupby:quantile() espera 0 ≤ q ≤ 1", 2)
    end
    local cols = select('#', ...) > 0 and {...} or nil
    local fn = function(col, idx)
        local vals = {}
        for _, i in ipairs(idx) do
            local v = col:get(i); if v ~= nil then vals[#vals+1] = v end
        end
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

-- groupby:agg({col = fn | {fn1, fn2, ...}}): múltiplas agregações de uma vez.
-- Exemplo: ds:groupby("uf"):agg({vendas = {"sum","mean"}, custo = "max"})
-- Nomes de coluna resultado: "vendas_sum", "vendas_mean", "custo_max".
-- fn pode ser string ("sum","mean","min","max","std","var","median","first","last","prod","count")
-- ou função Lua (col, idx) -> valor.
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
    -- colunas-chave
    if #key_names == 1 then
        local key_dtype = ds:column(key_names[1])._dtype
        local vals = {}
        for _, g in ipairs(groups) do vals[#vals+1] = g.key end
        result:add_column(key_names[1], Series.from_table(vals, key_dtype, key_names[1]))
    else
        for ki, kname in ipairs(key_names) do
            local key_dtype = ds:column(kname)._dtype
            local vals = {}
            for _, g in ipairs(groups) do vals[#vals+1] = g.key[ki] end
            result:add_column(kname, Series.from_table(vals, key_dtype, kname))
        end
    end
    -- colunas agregadas
    for cname, fns in pairs(spec) do
        if not ds:has_column(cname) then
            error("smaug: groupby:agg() — coluna '"..cname.."' não existe", 2)
        end
        if type(fns) ~= "table" then fns = {fns} end
        local src = ds:column(cname)
        for _, fn in ipairs(fns) do
            local fn_real = type(fn) == "string" and builtin[fn] or fn
            if not fn_real then
                error("smaug: groupby:agg() — função desconhecida '"..tostring(fn).."'", 2)
            end
            local out_name = type(fn) == "string" and (cname.."_"..fn) or cname
            local vals = {}
            for gi, g in ipairs(groups) do
                local v = fn_real(src, g.idx)
                vals[gi] = (v ~= nil) and v or Series.NA
            end
            result:add_column(out_name, Series.from_table(vals, "float64", out_name))
        end
    end
    return result
end

-- groupby:transform(fn_name): aplica agregação e faz broadcast de volta ao tamanho original.
-- Exemplo: ds:groupby("uf"):transform("mean", "vendas") → Series do tamanho de ds com
-- cada linha substituída pela média do seu grupo.
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
    local src  = ds:column(col_name)
    local n    = ds:nrows()
    local vals = {}
    for i = 1, n do vals[i] = Series.NA end
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
        local key_dtype = ds:column(key_names[1])._dtype
        local kv, cv = {}, {}
        for _, g in ipairs(groups) do
            kv[#kv+1] = g.key; cv[#cv+1] = #g.idx
        end
        result:add_column(key_names[1],
            Series.from_table(kv, key_dtype, key_names[1]))
        result:add_column("count",
            Series.from_table(cv, "int64", "count"))
    else
        for ki, kname in ipairs(key_names) do
            local key_dtype = ds:column(kname)._dtype
            local vals = {}
            for _, g in ipairs(groups) do vals[#vals+1] = g.key[ki] end
            result:add_column(kname,
                Series.from_table(vals, key_dtype, kname))
        end
        local cv = {}
        for _, g in ipairs(groups) do cv[#cv+1] = #g.idx end
        result:add_column("count", Series.from_table(cv, "int64", "count"))
    end
    return result
end

function methods.groupby(self, key)
    -- aceita string (chave simples) ou tabela de strings (chave composta)
    local key_names
    if type(key) == "string" then
        key_names = { key }
    elseif type(key) == "table" then
        if #key == 0 then
            error("smaug: groupby espera pelo menos uma coluna-chave", 2)
        end
        key_names = key
    else
        error("smaug: groupby espera string ou lista de strings", 2)
    end

    for _, k in ipairs(key_names) do
        if not self:has_column(k) then
            error("smaug: groupby — coluna '"..k.."' não existe", 2)
        end
    end

    -- key_set: lookup O(1) para saber se uma coluna é chave
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
-- Transformações de colunas (Anel 2)
-- =====================================================================

-- assign(nome, fn_ou_series): adiciona ou substitui uma coluna calculada.
-- Se o segundo argumento for uma função, ela recebe o DataSet e deve retornar
-- uma Series. Se for uma Series, é usada diretamente.
-- Retorna um NOVO DataSet (imutável).
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
    -- clonar o DataSet e adicionar/substituir a coluna
    local result = DataSet.new(self._name)
    for _, cname in ipairs(self._col_names) do
        if cname ~= name then
            result:add_column(cname, self:column(cname):clone())
        end
    end
    -- se a coluna já existe, mantém a posição; senão vai para o fim
    if self:has_column(name) then
        -- recriar na ordem original com a coluna substituída
        local result2 = DataSet.new(self._name)
        for _, cname in ipairs(self._col_names) do
            if cname == name then
                result2:add_column(name, col)
            else
                result2:add_column(cname, self:column(cname):clone())
            end
        end
        return result2
    end
    result:add_column(name, col)
    return result
end

-- nunique(): tabela { coluna = contagem_de_distintos_nao_nulos }.
function methods.nunique(self)
    local t = {}
    for _, name in ipairs(self._col_names) do
        t[name] = self:column(name):nunique()
    end
    return t
end

-- =====================================================================
-- F.1 — Pacote estatístico (DataSet): corr / cov
-- Matriz N×N entre as colunas numéricas, retornada como DataSet.
-- Coluna identificadora "__index__" (string) + uma coluna float64 por
-- variável numérica. Célula [i][j] = corr/cov(col_i, col_j).
-- Colunas não-numéricas são ignoradas. Diagonal de corr = 1 (exceto
-- variância zero → NaN, herdado de Series:corr).
-- =====================================================================

-- Helper: nomes das colunas numéricas (float64/int64), na ordem original.
local function numeric_col_names(self)
    local names = {}
    for _, n in ipairs(self._col_names) do
        local dt = self._columns[n]._dtype
        if dt == "float64" or dt == "int64" then
            names[#names + 1] = n
        end
    end
    return names
end

-- Helper comum a corr/cov: monta a matriz aplicando `pair_fn` (Series, Series)→número.
local function _stat_matrix(self, pair_fn, suffix)
    local names = numeric_col_names(self)
    if #names == 0 then
        error("smaug: "..suffix.."() requer ao menos uma coluna numérica", 3)
    end
    local result = DataSet.new(self._name .. "_" .. suffix)
    -- coluna identificadora: nome de cada variável (linhas da matriz)
    result:add_column("__index__", Series.from_table(names, "string", "__index__"))
    -- uma coluna por variável: valores da estatística contra cada linha
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

-- corr(): matriz de correlação de Pearson entre colunas numéricas.
function methods.corr(self)
    return _stat_matrix(self, function(a, b) return a:corr(b) end, "corr")
end

-- cov(): matriz de covariância amostral entre colunas numéricas.
function methods.cov(self)
    return _stat_matrix(self, function(a, b) return a:cov(b) end, "cov")
end

-- =====================================================================
-- F.2 — Predicados (DataSet): equals / compare
-- =====================================================================

-- equals(other): igualdade estrutural entre DataSets — mesmas colunas (nomes e
-- ordem), mesmos dtypes, mesmo número de linhas, e todas as colunas equals.
function methods.equals(self, other)
    if getmetatable(other) ~= DataSet then return false end
    if self:ncols() ~= other:ncols() then return false end
    if self:nrows() ~= other:nrows() then return false end
    local sn, on = self._col_names, other._col_names
    for i = 1, #sn do
        if sn[i] ~= on[i] then return false end   -- nomes e ordem
    end
    for _, n in ipairs(sn) do
        local a, b = self._columns[n], other._columns[n]
        -- delega ao equals da coluna; categorical tem seu próprio equals abaixo
        if not column_equals(a, b) then return false end
    end
    return true
end

-- compare(other): diferenças célula a célula → DataSet {linha, coluna, self, other}.
-- Só inclui células que diferem. DataSet vazio se idênticos.
-- Exige mesma estrutura de colunas (nomes, ordem) e nrows.
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
                differ = (va ~= vb) and not (va ~= va and vb ~= vb)  -- NaN estrutural
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
-- F.6 — Duplicatas (DataSet)
-- =====================================================================

-- Chave de linha consistente: concatena as chaves por coluna do subset.
-- subset: lista de nomes de coluna (default: todas, na ordem original).
local function row_dup_key(self, i, subset)
    local parts = {}
    for j, name in ipairs(subset) do
        local v = self._columns[name]:get(i)
        parts[j] = (v == nil) and "\0NULL\0" or (type(v)..":"..tostring(v))
    end
    return table.concat(parts, "\1")   -- separador improvável nos dados
end

-- duplicated([subset], [keep]): Series<bool> marcando linhas duplicadas.
-- subset: nome de coluna, lista de nomes, ou nil (todas). keep como na Series.
function methods.duplicated(self, subset, keep)
    keep = keep or "first"
    if keep ~= "first" and keep ~= "last" and keep ~= "none" then
        error("smaug: duplicated() keep ∈ {first, last, none}", 2)
    end
    -- normaliza subset
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

-- drop_duplicates([subset], [keep]): novo DataSet sem as linhas marcadas.
function methods.drop_duplicates(self, subset, keep)
    local mask = self:duplicated(subset, keep)   -- valida subset/keep
    -- índices a manter (onde mask == false)
    local keep_idx = {}
    for i = 1, self:nrows() do
        if mask:get(i) == false then keep_idx[#keep_idx + 1] = i end
    end
    return self:take(keep_idx)
end

-- =====================================================================
-- Window / Rolling (Anel 2)
--
-- ds:rolling(window):sum/mean/min/max(col)
-- Retorna uma nova Series com a agregação sobre a janela deslizante.
-- Primeiras (window-1) posições são NA. Nulos dentro da janela são ignorados.
-- =====================================================================
local Rolling = {}
Rolling.__index = Rolling

function Rolling:_agg(col_name, fn)
    local col = self._ds:column(col_name)
    local n   = col:len()
    local w   = self._window
    local NA  = Series.NA
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

-- =====================================================================
-- Pivot / Melt (Anel 2)
-- =====================================================================

-- pivot(index, columns, values): transforma de long para wide.
--   index   : coluna que vira índice das linhas (valores únicos)
--   columns : coluna cujos valores únicos viram novas colunas
--   values  : coluna cujos valores preenchem as células (NA onde sem match)
--
-- Exemplo:
--   ds = {uf, produto, vendas}
--   ds:pivot("uf","produto","vendas")
--   → DataSet com coluna "uf" + uma coluna por produto
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

    local n          = self:nrows()
    local idx_col    = self:column(index)
    local col_col    = self:column(columns)
    local val_col    = self:column(values)
    local NA         = Series.NA

    -- coletar valores únicos de cada dimensão (na ordem de aparição)
    local idx_vals, idx_seen   = {}, {}
    local col_vals, col_seen   = {}, {}
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

    -- construir lookup: (idx_key, col_key) -> valor
    local lookup = {}
    for i = 1, n do
        local iv = idx_col:get(i)
        local cv = col_col:get(i)
        local vv = val_col:get(i)
        if iv ~= nil and cv ~= nil then
            local k = tostring(iv).."\1"..tostring(cv)
            lookup[k] = vv
        end
    end

    -- montar resultado
    local result = DataSet.new(self._name.."_pivot")
    -- coluna de índice
    local idx_dtype = idx_col._dtype
    result:add_column(index, Series.from_table(idx_vals, idx_dtype, index))
    -- uma coluna por valor de "columns"
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

-- melt(id_vars, value_vars, [var_name], [value_name]):
-- transforma de wide para long (inverso de pivot).
--   id_vars    : colunas que permanecem como identificadores
--   value_vars : colunas que viram linhas (nil = todas as não-id)
--   var_name   : nome da nova coluna de variável (default "variable")
--   value_name : nome da nova coluna de valor    (default "value")
function methods.melt(self, id_vars, value_vars, var_name, value_name)
    id_vars    = id_vars    or {}
    var_name   = var_name   or "variable"
    value_name = value_name or "value"

    if type(id_vars) == "string" then id_vars = {id_vars} end
    local id_set = {}
    for _, n in ipairs(id_vars) do
        if not self:has_column(n) then
            error("smaug: melt — id_var '"..n.."' não existe", 2)
        end
        id_set[n] = true
    end

    -- determinar value_vars
    if value_vars == nil then
        value_vars = {}
        for _, n in ipairs(self._col_names) do
            if not id_set[n] then value_vars[#value_vars+1] = n end
        end
    elseif type(value_vars) == "string" then
        value_vars = {value_vars}
    end
    for _, n in ipairs(value_vars) do
        if not self:has_column(n) then
            error("smaug: melt — value_var '"..n.."' não existe", 2)
        end
    end

    local nrows   = self:nrows()
    local NA      = Series.NA

    -- inferir dtype do value: se todas as value_vars têm mesmo dtype, usa esse;
    -- senão converte tudo para string (dtypes misturados)
    local val_dtype = nil
    for _, vv in ipairs(value_vars) do
        local dt = self:column(vv)._dtype
        if val_dtype == nil then
            val_dtype = dt
        elseif val_dtype ~= dt then
            val_dtype = "string"  -- dtypes misturados → string
            break
        end
    end
    val_dtype = val_dtype or "string"

    -- montar linhas: para cada linha × cada value_var
    local id_data   = {}   -- { col_name -> {valores} }
    for _, n in ipairs(id_vars) do id_data[n] = {} end
    local var_data   = {}
    local value_data = {}

    for _, vv in ipairs(value_vars) do
        local src = self:column(vv)
        for i = 1, nrows do
            -- replicar id columns
            for _, n in ipairs(id_vars) do
                local v = self:column(n):get(i)
                id_data[n][#id_data[n]+1] = (v == nil) and NA or v
            end
            var_data[#var_data+1]   = vv
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
        local dtype = self:column(n)._dtype
        result:add_column(n, Series.from_table(id_data[n], dtype, n))
    end
    result:add_column(var_name,   Series.from_table(var_data,   "string", var_name))
    result:add_column(value_name, Series.from_table(value_data, val_dtype, value_name))
    return result
end

-- Inspeção
-- =====================================================================
-- describe: tabela { coluna = (describe da Series) } para colunas numéricas.
-- rename({old=new, ...}): renomeia múltiplas colunas de uma vez → novo DataSet.
function methods.rename(self, mapping)
    if type(mapping) ~= "table" then
        error("smaug: rename() espera tabela {old=new, ...}", 2)
    end
    -- validar: todas as colunas-fonte existem e os novos nomes não colidem
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
        result:add_column(new_name, self:column(cname):clone())
    end
    return result
end

-- pivot_table(index, columns, values, aggfunc): pivot com agregação.
-- aggfunc: "sum" (default), "mean", "min", "max", "count", "first", "last".
-- Linhas = valores únicos de `index`, colunas = valores únicos de `columns`.
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

    local idx_col  = self:column(index)
    local col_col  = self:column(columns)
    local val_col  = self:column(values)
    local n        = self:nrows()

    -- coletar valores únicos (em ordem de aparição)
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

    -- agrupar linhas por (index, column)
    local buckets = {}  -- buckets[idx_key][col_key] = {indices}
    for i = 1, n do
        local ik = tostring(idx_col:get(i) or "")
        local ck = tostring(col_col:get(i) or "")
        if not buckets[ik] then buckets[ik] = {} end
        if not buckets[ik][ck] then buckets[ik][ck] = {} end
        buckets[ik][ck][#buckets[ik][ck]+1] = i
    end

    -- construir resultado
    local result = DataSet.new(self._name.."_pivot")
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
            cdata[#cdata+1] = (#ids > 0) and fn(val_col, ids) or Series.NA
        end
        result:add_column(tostring(cv), Series.from_table(cdata, val_dtype, tostring(cv)))
    end
    return result
end

-- stack(col_names): empilha colunas selecionadas em duas colunas (variable, value).
-- Mantém id_vars como as colunas restantes. Equivale a melt com nomes padrão.
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

-- unstack(col, index): operação inversa do stack.
-- Equivale a pivot com aggfunc="first".
function methods.unstack(self, index, col, values)
    return self:pivot_table(index, col, values, "first")
end

-- explode(col_name): expande uma coluna cujos valores são tabelas Lua em múltiplas linhas.
-- As demais colunas têm seus valores repetidos. Nulos na coluna → linha com NA.
function methods.explode(self, col_name)
    if not self:has_column(col_name) then
        error("smaug: explode() — coluna '"..col_name.."' não existe", 2)
    end
    local src   = self:column(col_name)
    local n     = self:nrows()
    -- contagem de linhas no resultado
    local total = 0
    for i = 1, n do
        local v = src:get(i)
        if v == nil then total = total + 1
        elseif type(v) == "table" then total = total + math.max(#v, 1)
        else total = total + 1 end
    end
    -- construir colunas resultado
    local other_cols = {}
    for _, cname in ipairs(self._col_names) do
        if cname ~= col_name then
            other_cols[cname] = { col=self:column(cname), vals={} }
        end
    end
    local exploded_vals = {}
    for i = 1, n do
        local v = src:get(i)
        local items
        if v == nil then
            items = {Series.NA}
        elseif type(v) == "table" then
            items = #v > 0 and v or {Series.NA}
        else
            items = {v}
        end
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
            -- inferir dtype da coluna explodida
            local dtype = "string"
            for _, v in ipairs(exploded_vals) do
                if v ~= nil and v ~= Series.NA then
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
            local info   = other_cols[cname]
            result:add_column(cname, Series.from_table(info.vals, info.col._dtype, cname))
        end
    end
    return result
end

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
-- F.5 — Acesso e ergonomia
-- =====================================================================

-- at(i, col): célula única por nome de coluna. col deve existir; i 1-based.
function methods.at(self, i, col)
    if type(col) ~= "string" then
        error("smaug: df:at(i, col) — col deve ser nome de coluna (string)", 2)
    end
    local c = self._columns[col]
    if c == nil then error("smaug: coluna '"..tostring(col).."' não existe", 2) end
    return c:get(i)
end

-- iat(i, ci): célula única por índice posicional de coluna (1-based).
function methods.iat(self, i, ci)
    if type(ci) ~= "number" or ci < 1 or ci > #self._col_names then
        error("smaug: df:iat(i, ci) — ci fora dos limites [1, "..#self._col_names.."]", 2)
    end
    return self._columns[self._col_names[ci]]:get(i)
end

-- insert(loc, name, series): insere uma coluna na posição `loc` (1-based).
-- loc ∈ [1, ncols+1]. Desloca as colunas seguintes. Valida nrows e nome único.
function methods.insert(self, loc, name, series)
    if type(loc) ~= "number" or loc < 1 or loc > #self._col_names + 1 then
        error("smaug: df:insert — loc fora dos limites [1, "..(#self._col_names+1).."]", 2)
    end
    if type(name) ~= "string" then
        error("smaug: df:insert — name deve ser string", 2)
    end
    if self._columns[name] ~= nil then
        error("smaug: coluna '"..name.."' já existe", 2)
    end
    if not (is_series(series) or is_boolseries(series) or is_categorical(series)) then
        error("smaug: df:insert espera uma Series", 2)
    end
    local n = series:len()
    if self._length == nil then
        self._length = n
    elseif n ~= self._length then
        error("smaug: coluna '"..name.."' tem "..n.." linhas; esperado "..self._length, 2)
    end
    self._columns[name] = series
    table.insert(self._col_names, loc, name)
    return self
end

-- to_dict([orient]): converte para tabela Lua.
--   "columns" (default): { coluna = {v1, v2, ...}, ... }
--   "records": { {col=v, ...}, {col=v, ...}, ... } (lista de linhas)
-- Nulos viram nil nas tabelas (chaves ausentes em records).
function methods.to_dict(self, orient)
    orient = orient or "columns"
    if orient == "columns" then
        return self:to_table()
    elseif orient == "records" then
        local out = {}
        for i = 1, self:nrows() do
            out[i] = self:row(i)   -- {coluna = valor}; nil para nulos
        end
        return out
    end
    error("smaug: to_dict orient ∈ {columns, records}", 2)
end

-- from_dict(t, [orient]): constrói DataSet a partir de tabela Lua.
--   "columns" (default): { coluna = {v1,...}, ... } — ordem indefinida em Lua,
--      então aceita ordem explícita via t._order (lista de nomes), opcional.
--   "records": { {col=v,...}, ... } — infere colunas da união das chaves.
-- dtype é inferido por coluna (int64 se todos inteiros, float64 se números,
-- bool, senão string). Nil/ausente → NA.
function DataSet.from_dict(t, orient)
    orient = orient or "columns"
    if type(t) ~= "table" then error("smaug: from_dict espera tabela", 2) end

    local function infer_and_build(name, values, n)
        -- infere dtype varrendo os não-nulos
        local seen_num, seen_float, seen_bool, seen_str = false, false, false, false
        for i = 1, n do
            local v = values[i]
            if v ~= nil and v ~= Series.NA then
                local tv = type(v)
                if tv == "boolean" then seen_bool = true
                elseif tv == "number" then
                    seen_num = true
                    if v % 1 ~= 0 then seen_float = true end
                elseif tv == "string" then seen_str = true end
            end
        end
        local dtype
        if seen_str then dtype = "string"
        elseif seen_bool and not seen_num then dtype = "bool"
        elseif seen_float then dtype = "float64"
        elseif seen_num then dtype = "int64"
        else dtype = "string" end   -- coluna toda nula → string por convenção
        -- normaliza nil → NA
        local vals = {}
        for i = 1, n do
            local v = values[i]
            vals[i] = (v == nil) and Series.NA or v
        end
        return Series.from_table(vals, dtype, name)
    end

    local df = DataSet.new("from_dict")
    if orient == "columns" then
        local order = t._order   -- lista opcional de nomes para ordem determinística
        if order == nil then
            order = {}
            for k in pairs(t) do
                if k ~= "_order" then order[#order + 1] = k end
            end
            table.sort(order)   -- ordem estável (alfabética) na ausência de _order
        end
        for _, name in ipairs(order) do
            local values = t[name]
            df:add_column(name, infer_and_build(name, values, #values))
        end
        return df
    elseif orient == "records" then
        -- coleta nomes de coluna na ordem de 1ª aparição
        local order, seen = {}, {}
        for _, rec in ipairs(t) do
            for k in pairs(rec) do
                if not seen[k] then seen[k] = true; order[#order + 1] = k end
            end
        end
        local nrows = #t
        for _, name in ipairs(order) do
            local values = {}
            for i = 1, nrows do values[i] = t[i][name] end
            df:add_column(name, infer_and_build(name, values, nrows))
        end
        return df
    end
    error("smaug: from_dict orient ∈ {columns, records}", 2)
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

-- to_markdown(): tabela em formato Markdown (GitHub-flavored).
-- Inclui todas as linhas (sem limite de 10 do __tostring). Útil para
-- READMEs, issues e PRs. Nulos → "NA".
function methods.to_markdown(self)
    local names = self._col_names
    if #names == 0 then return "" end
    local nrows = self:nrows()
    -- larguras: max entre nome e qualquer célula
    local widths = {}
    for _, n in ipairs(names) do widths[n] = #n end
    local cells = {}
    for i = 1, nrows do
        cells[i] = {}
        for _, n in ipairs(names) do
            local s = cell_str(self._columns[n]:get(i))
            cells[i][n] = s
            if #s > widths[n] then widths[n] = #s end
        end
    end
    local function pad(s, w) return s .. string.rep(" ", w - #s) end
    local out = {}
    -- cabeçalho
    local header = {}
    for _, n in ipairs(names) do header[#header + 1] = pad(n, widths[n]) end
    out[#out + 1] = "| " .. table.concat(header, " | ") .. " |"
    -- separador
    local sep = {}
    for _, n in ipairs(names) do sep[#sep + 1] = string.rep("-", widths[n]) end
    out[#out + 1] = "| " .. table.concat(sep, " | ") .. " |"
    -- linhas
    for i = 1, nrows do
        local line = {}
        for _, n in ipairs(names) do line[#line + 1] = pad(cells[i][n], widths[n]) end
        out[#out + 1] = "| " .. table.concat(line, " | ") .. " |"
    end
    return table.concat(out, "\n")
end

-- to_string([opts]): render tabular em texto plano. opts.max_rows limita
-- linhas (default: todas). Formaliza o que __tostring faz, sem truncar em 10.
function methods.to_string(self, opts)
    opts = opts or {}
    local names = self._col_names
    local nrows = self:nrows()
    if #names == 0 then return "DataSet '"..self._name.."' (vazio)" end
    local limit = opts.max_rows and math.min(nrows, opts.max_rows) or nrows

    local widths = {}
    for _, n in ipairs(names) do widths[n] = #n end
    local idxw = math.max(#tostring(limit), 1)
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
    local header = { string.rep(" ", idxw) }
    for _, n in ipairs(names) do header[#header + 1] = pad(n, widths[n]) end
    out[#out + 1] = table.concat(header, "  ")
    for i = 1, limit do
        local line = { pad(tostring(i), idxw) }
        for _, n in ipairs(names) do line[#line + 1] = pad(rows[i][n], widths[n]) end
        out[#out + 1] = table.concat(line, "  ")
    end
    if nrows > limit then out[#out + 1] = "... ("..(nrows - limit).." linhas a mais)" end
    return table.concat(out, "\n")
end

-- __index: df["coluna"] OU df:metodo() OU df[bool_series].
-- Prioridades: método > Series<bool> (filtragem) > string (coluna).
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
--   - Series ou Series<bool>: passada diretamente.
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
    if not (is_series(v) or is_boolseries(v) or is_categorical(v)) then
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
-- fracionário→"float64". Series/Series<bool> passadas diretamente.
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
            elseif is_series(data) or is_boolseries(data) or is_categorical(data) then
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

-- Expõe a tabela methods para extensão por módulos externos (ex: I/O).
DataSet.methods = methods

return DataSet
