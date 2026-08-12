-- tests/series/test_categorical.lua
-- CategoricalSeries: factories, acesso, .cat accessor, comparações,
-- seleção, fillna, únicos, describe, astype, integração DataSet.
-- Baseado estritamente no API_INDEX v1.0.
-- Rode da raiz: luajit tests/series/test_categorical.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug  = require("smaug")
local Series = smaug.Series
local NA     = Series.NA
local DataSet = smaug.DataSet

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

local function check_err(fn, msg)
    local ok = pcall(fn)
    check(not ok, msg .. " (deveria lançar erro)")
end

-- =====================================================================
-- 1. Factories e Estrutura
-- =====================================================================
do
    -- from_table básico
    local c = Series.from_table({"SP", "RJ", "SP", NA, "MG"}, "categorical")
    check(c._dtype == "categorical", "dtype = categorical")
    check(c:len() == 5, "len = 5")
    check(c:get(1) == "SP", "get(1) = SP")
    check(c:get(4) == nil, "get(4) = nil (NA)")
    
    -- Levels: ordem de primeira aparição
    local lev = c.cat:levels()
    check(#lev == 3, "3 levels")
    check(lev[1] == "SP", "level[1] = SP")
    check(lev[2] == "RJ", "level[2] = RJ")
    check(lev[3] == "MG", "level[3] = MG")
    
    -- from_codes
    local fc = Series.Categorical.from_codes({1, 2, 1, NA, 3}, {"SP", "RJ", "MG"})
    check(fc:get(1) == "SP", "from_codes: 1→SP")
    check(fc:is_null(4), "from_codes: NA→null")
    
    -- Erro: code fora do range
    check_err(function()
        Series.Categorical.from_codes({1, 5}, {"A", "B", "C"})
    end, "from_codes: code fora do range")
    
    -- Guard de unicidade de níveis
    check_err(function() 
        Series.Categorical.from_codes({1, 2}, {"a", "a"}) 
    end, "from_codes: nível duplicado literal")
    
    -- Série vazia
    local c0 = Series.from_table({}, "categorical")
    check(c0:len() == 0, "vazio: len=0")
    check(#c0.cat:levels() == 0, "vazio: 0 levels")
    
    -- Série toda nula
    local c_null = Series.from_table({NA, NA, NA}, "categorical")
    check(c_null:get(1) == nil, "tudo NA: get=nil")
    check(c_null:count_nonnull() == 0, "tudo NA: count_nonnull=0")
end

-- =====================================================================
-- 2. Acesso e Mutação
-- =====================================================================
do
    local cm = Series.from_table({"A", "B", "C"}, "categorical")
    
    -- is_null / set_null
    check(not cm:is_null(1), "is_null(1) = false")
    cm:set_null(2)
    check(cm:is_null(2), "set_null(2): is_null=true")
    check(cm:get(2) == nil, "get após set_null = nil")
    
    -- set: valor existente
    cm:set(2, "A")
    check(cm:get(2) == "A", "set existing level: A")
    
    -- set: valor novo (cria level)
    cm:set(3, "Z")
    check(cm:get(3) == "Z", "set novo level: Z")
    check(#cm.cat:levels() == 4, "novo level criado (4 total)")
    
    -- append
    local ca = Series.from_table({"X"}, "categorical")
    ca:append("Y")
    ca:append(NA)
    ca:append("X") -- reutiliza level
    check(ca:len() == 4, "append: len=4")
    check(ca:get(2) == "Y", "append Y")
    check(ca:is_null(3), "append NA")
    
    -- count_nonnull
    local c = Series.from_table({"SP", "RJ", "SP", NA, "MG"}, "categorical")
    check(c:count_nonnull() == 4, "count_nonnull = 4")
end

-- =====================================================================
-- 3. .cat Accessor
-- =====================================================================
do
    local ccat = Series.from_table({"B", "A", NA, "C", "A"}, "categorical")
    
    -- codes()
    local codes = ccat.cat:codes()
    check(codes._dtype == "int64", "codes: dtype=int64")
    check(codes:is_null(3), "codes: NA → null")
    check(codes:get(1) == 1, "codes[1] = 1 (B)")
    check(codes:get(2) == 2, "codes[2] = 2 (A)")
    
    -- rename_categories
    local renamed = ccat.cat:rename_categories({A = "Alpha", B = "Beta"})
    check(renamed:get(1) == "Beta", "rename: B→Beta")
    check(ccat:get(1) == "B", "rename: original intacto")
    
    -- set_categories
    local sc = ccat.cat:set_categories({"C", "A"}) -- remove B
    check(sc:get(1) == nil, "set_categories: B removido → null")
    check(sc:get(4) == "C", "set_categories: C preservado")
    
    -- add_categories
    local ac = ccat.cat:add_categories({"D", "E"})
    check(#ac.cat:levels() == 5, "add_categories: 5 levels")
    
    -- remove_categories
    local rc = ccat.cat:remove_categories({"A"})
    check(rc:get(2) == nil, "remove_categories: A→null")
end

-- =====================================================================
-- 4. Comparações e Ordenação
-- =====================================================================
do
    local ccmp = Series.from_table({"SP", "RJ", "SP", NA, "MG"}, "categorical")
    
    -- eq / ne
    local eq = ccmp:eq("SP")
    check(eq._dtype == "bool", "eq: dtype=bool")
    check(eq:get(1) == true, "eq: SP==SP")
    check(eq:is_null(4), "eq: NA → NA")
    
    -- lt / gt / le / ge
    local cord = Series.from_table({"B", "A", "C"}, "categorical")
    check(cord:lt("B"):get(2) == true, "lt: A < B")
    check(cord:gt("B"):get(3) == true, "gt: C > B")
    check(cord:le("B"):get(1) == true, "le: B <= B")
    
    -- sort
    local csort = Series.from_table({"C", "A", "B", "A"}, "categorical")
    local sorted = csort:sort(true)
    check(sorted:get(1) == "A", "sort asc: 1º = A")
    check(sorted:get(4) == "C", "sort asc: 4º = C")
    
    -- sort com nulo → erro
    local cnull = Series.from_table({"A", NA, "B"}, "categorical")
    check_err(function() cnull:sort(true) end, "sort com null")
    
    -- argsort
    local idx = csort:argsort(true)
    check(type(idx) == "table", "argsort: retorna tabela")
    
    -- filter
    local mfl = ccmp:eq("SP")
    local filtered = ccmp:filter(mfl)
    check(filtered:len() == 2, "filter: len=2")
    
    -- dropna
    local cdn = Series.from_table({"A", NA, "B", NA, "C"}, "categorical")
    local dropped = cdn:dropna()
    check(dropped:len() == 3, "dropna: len=3")
end

-- =====================================================================
-- 5. Transformações e Preenchimento
-- =====================================================================
do
    -- fillna
    local cfn = Series.from_table({"A", NA, NA, "C"}, "categorical")
    local filled = cfn:fillna("B")
    check(filled:get(2) == "B", "fillna: NA preenchido")
    check(cfn:is_null(2), "fillna: original não mutado")
    
    -- ffill
    local c3 = Series.from_table({NA, "SP", NA, "RJ", NA}, "categorical")
    local ff = c3:ffill()
    check(ff:get(1) == nil, "ffill[1] = nil")
    check(ff:get(3) == "SP", "ffill[3] = SP")
    
    -- bfill
    local bf = c3:bfill()
    check(bf:get(1) == "SP", "bfill[1] = SP")
    check(bf:get(5) == nil, "bfill[5] = nil")
    
    -- shift
    local c5 = Series.from_table({"A", "B", "C"}, "categorical")
    local sh = c5:shift(1)
    check(sh:get(1) == nil, "shift(1)[1] = null")
    check(sh:get(2) == "A", "shift(1)[2] = A")
    
    -- map
    local c6 = Series.from_table({"sp", "rj", NA}, "categorical")
    local up = c6:map(function(v) return v and string.upper(v) or nil end, "string")
    check(up._dtype == "string", "map → string")
    check(up:get(3) == nil, "map: null propaga")
    
    -- where / mask
    local c7 = Series.from_table({"SP", "RJ", "MG"}, "categorical")
    local mask = Series.from_table({true, false, true}, "bool")
    local w1 = c7:where(mask, "OUTRO")
    check(w1:get(2) == "OUTRO", "where: substitui onde false")
    check(w1:get(1) == "SP", "where: mantém onde true")
    
    local m1 = c7:mask(mask, "OUTRO")
    check(m1:get(1) == "OUTRO", "mask: substitui onde true")
end

-- =====================================================================
-- 6. Estatísticas e Metadados
-- =====================================================================
do
    local cu = Series.from_table({"C", "A", "B", "A", NA, "C"}, "categorical")
    
    -- unique / nunique
    local uniq = cu:unique()
    check(uniq._dtype == "categorical", "unique: dtype=categorical")
    check(cu:nunique() == 3, "nunique = 3")
    
    -- value_counts
    local vc = cu:value_counts()
    check(type(vc) == "table", "value_counts: retorna tabela")
    
    -- describe
    local cd = Series.from_table({"SP", "RJ", "SP", NA, "MG", "SP"}, "categorical")
    local desc = cd:describe()
    check(desc.dtype == "categorical", "describe: dtype")
    check(desc.count == 5, "describe: count=5")
    check(desc.top == "SP", "describe: top=SP")
    check(desc.freq == 3, "describe: freq=3")
    
    -- min / max
    local c2 = Series.from_table({"SP", "RJ", NA, "AM", "MG"}, "categorical")
    check(c2:min() == "AM", "min() = AM")
    check(c2:max() == "SP", "max() = SP")
end

-- =====================================================================
-- 7. Conversão de Tipo (astype)
-- =====================================================================
do
    local cas = Series.from_table({"SP", NA, "RJ"}, "categorical")
    
    -- categorical → string
    local as_str = cas:astype("string")
    check(as_str._dtype == "string", "astype cat→str")
    check(as_str:is_null(2), "astype: NA → null")
    
    -- categorical → float64
    local cnum = Series.from_table({"1.5", "2.0", NA, "invalido"}, "categorical")
    local as_f64 = cnum:astype("float64")
    check(as_f64._dtype == "float64", "astype cat→f64")
    check(as_f64:is_null(4), "astype: invalido → null")
    
    -- string → categorical
    local ss = Series.from_table({"SP", "RJ", NA}, "string")
    local as_cat = ss:astype("categorical")
    check(as_cat._dtype == "categorical", "astype str→cat")
    
    -- dtype inválido
    check_err(function() cas:astype("datetime") end, "astype cat→datetime")
end

-- =====================================================================
-- 8. Serialização (to_table)
-- =====================================================================
do
    local ctt = Series.from_table({"A", NA, "B"}, "categorical")
    
    -- to_table padrão
    local t = ctt:to_table()
    check(t[1] == "A", "to_table: [1]=A")
    check(t[2] == nil, "to_table: [2]=nil (NA)")
    
    -- to_table com na_value
    local t2 = ctt:to_table("N/A")
    check(t2[2] == "N/A", "to_table na_value: [2]=N/A")
end

-- =====================================================================
-- 9. Integração DataSet
-- =====================================================================
do
    local ds = DataSet({
        {"cidade", {"SP", "RJ", "SP", "MG", "RJ"}, "categorical"},
        {"valor", {10.0, 20.0, 30.0, 40.0, 50.0}, "float64"},
    })
    
    check(ds:has_column("cidade"), "DataSet: coluna existe")
    check(ds:col("cidade")._dtype == "categorical", "DataSet: dtype=categorical")
    
    -- filter
    local m = ds:col("cidade"):eq("SP")
    local dsf = ds:filter(m)
    check(dsf:nrows() == 2, "DataSet filter: 2 linhas SP")
    
    -- sort_by
    local dss = ds:sort_by("cidade", true)
    check(dss:col("cidade"):get(1) == "MG", "sort_by asc: 1º = MG")
    
    -- groupby
    local gb = ds:groupby("cidade"):sum("valor")
    check(gb:nrows() == 3, "groupby sum: 3 grupos")
    
    -- assign
    local ds2 = ds:assign("regiao", Series.from_table({"SE", "SE", "SE", "SE", "SE"}, "categorical"))
    check(ds2:has_column("regiao"), "assign: coluna criada")
    
    -- concat
    local ds3 = DataSet({{"cidade", {"MG", "RS"}, "categorical"}, {"valor", {100.0, 200.0}, "float64"}})
    local cat_ds = smaug.concat({ds:select({"cidade", "valor"}), ds3})
    check(cat_ds:nrows() == 7, "concat categorical: 7 linhas")
end

-- =====================================================================
-- 10. Erros e Limites (Edge Cases)
-- =====================================================================
do
    local c = Series.from_table({"A", "B", "C"}, "categorical")
    
    -- .cat em dtype errado
    check_err(function()
        Series.from_table({1.0, 2.0}, "float64").cat:levels()
    end, "erro: .cat em float64")
    
    -- Índices fora dos limites
    check_err(function() c:get(0) end, "erro: get(0)")
    check_err(function() c:get(100) end, "erro: get(100)")
    check_err(function() c:set(0, "X") end, "erro: set(0)")
    check_err(function() c:is_null(0) end, "erro: is_null(0)")
    
    -- Índice fracionário (deve errar, não retornar nil)
    check_err(function() return c:get(1.5) end, "erro: get(1.5) fracionário")
    check_err(function() return c:set(1.5, "x") end, "erro: set(1.5) fracionário")
    
    -- take com índice inválido
    check_err(function() c:take({1, 999}) end, "erro: take índice inválido")
    
    -- filter tamanho diferente
    check_err(function()
        local m2 = Series.from_table({true, false}, "bool")
        c:filter(m2)
    end, "erro: filter tamanho diferente")
    
    -- fillna sem argumento
    check_err(function()
        Series.from_table({"A", NA}, "categorical"):fillna(nil)
    end, "erro: fillna nil")
end

-- =====================================================================
-- 11. Display e Metatables
-- =====================================================================
do
    local c = Series({"a", "b", "a", "c"}, "categorical")
    c._name = "cor"
    
    -- __tostring não vaza "table: 0x..."
    local tc = tostring(c)
    check(tc:find("^table:") == nil, "__tostring não vaza table:")
    
    -- .cat proxy legível
    local tp = tostring(c.cat)
    check(tp:find("^table:") == nil and tp:find(".cat", 1, true) ~= nil, ".cat proxy legível")
end

print(string.format("OK — %d checks passaram (Series: categorical)", n_ok))