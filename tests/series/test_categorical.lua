-- tests/series/test_categorical.lua
-- CategoricalSeries: factories, acesso, .cat accessor, comparações, sort,
-- seleção, fillna, unique, describe, astype, integração DataSet.
-- Completude: datetime + categorical métodos adicionais.
-- Consolida: test_categorical.lua + test_completeness.lua
-- Rode da raiz: luajit tests/series/test_categorical.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local Series = smaug.Series
local NA     = Series.NA

local function approx(a, b) return math.abs(a - b) < 1e-9 end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

local smaug = require("smaug")
local S  = smaug.Series
local NA = smaug.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- ================================================================
-- 1. Factories
-- ================================================================

-- from_table básico
local c = S.from_table({"SP", "RJ", "SP", NA, "MG"}, "categorical")
check(c._dtype == "categorical",    "dtype = categorical")
check(c:len() == 5,                 "len = 5")
check(c:get(1) == "SP",             "get(1) = SP")
check(c:get(2) == "RJ",             "get(2) = RJ")
check(c:get(3) == "SP",             "get(3) = SP (repetido)")
check(c:get(4) == nil,              "get(4) = nil (NA)")
check(c:get(5) == "MG",             "get(5) = MG")

-- Levels: ordem de primeira aparição
local lev = c.cat:levels()
check(#lev == 3,                    "3 levels")
check(lev[1] == "SP",               "level[1] = SP")
check(lev[2] == "RJ",               "level[2] = RJ")
check(lev[3] == "MG",               "level[3] = MG")

-- Valores numéricos convertidos via tostring
local cn = S.from_table({1, 2, 1, NA, 3}, "categorical")
check(cn:get(1) == "1",             "numérico → tostring")
check(cn:get(4) == nil,             "NA preservado")
check(cn:get(3) == "1",             "código compartilhado")

-- from_codes
-- NA como marcador de null; n explícito para arrays com nil no meio
local fc = S.Categorical.from_codes({1, 2, 1, NA, 3}, {"SP", "RJ", "MG"})
check(fc:get(1) == "SP",            "from_codes: 1→SP")
check(fc:get(2) == "RJ",            "from_codes: 2→RJ")
check(fc:is_null(4),                "from_codes: NA→null")
check(fc:get(5) == "MG",            "from_codes: 3→MG")

-- from_codes erro: code fora do range
local ok, err = pcall(function()
    S.Categorical.from_codes({1, 5}, {"A", "B", "C"})
end)
check(not ok, "from_codes: code fora do range → erro")

-- 12.4: guard de unicidade de níveis (falha-visível em vez de corromper)
local okd = pcall(function() S.Categorical.from_codes({1, 2}, {"a", "a"}) end)
check(not okd, "from_codes: nível duplicado literal → erro")
local okm = pcall(function() S.Categorical.from_codes({1, 2}, {1, "1"}) end)
check(not okm, "from_codes: colisão de tipo misto (1 vs \"1\") → erro")
-- controle positivo: níveis numéricos distintos normalizam sem colidir
local fcn = S.Categorical.from_codes({1, 2}, {1, 2})
check(fcn:get(1) == "1" and fcn:get(2) == "2",
      "from_codes: níveis numéricos distintos normalizam para \"1\"/\"2\"")

-- Series vazia
local c0 = S.from_table({}, "categorical")
check(c0:len() == 0,                "vazio: len=0")
check(#c0.cat:levels() == 0,        "vazio: 0 levels")

-- Série com todos nulos
local call_null = S.from_table({NA, NA, NA}, "categorical")
check(call_null:get(1) == nil,      "tudo NA: get=nil")
check(call_null:count_nonnull() == 0, "tudo NA: count_nonnull=0")

-- ================================================================
-- 2. Acesso e mutação
-- ================================================================

local cm = S.from_table({"A", "B", "C"}, "categorical")

-- is_null / set_null
check(not cm:is_null(1),            "is_null(1) = false")
cm:set_null(2)
check(cm:is_null(2),                "set_null(2): is_null=true")
check(cm:get(2) == nil,             "get após set_null = nil")

-- set: valor existente
cm:set(2, "A")
check(cm:get(2) == "A",             "set existing level: A")
check(cm:is_null(2) == false,       "após set: não nulo")

-- set: valor novo (cria level)
cm:set(3, "Z")
check(cm:get(3) == "Z",             "set novo level: Z")
local lev2 = cm.cat:levels()
check(#lev2 == 4,                   "novo level criado (4 total)")

-- set via NA
cm:set(1, NA)
check(cm:is_null(1),                "set NA → null")

-- append
local ca = S.from_table({"X"}, "categorical")
ca:append("Y")
ca:append(NA)
ca:append("X")   -- reutiliza level existente
check(ca:len() == 4,                "append: len=4")
check(ca:get(2) == "Y",             "append Y")
check(ca:is_null(3),                "append NA → null")
check(ca:get(4) == "X",             "append X (level existente)")
-- levels não duplicam
local lev_a = ca.cat:levels()
local x_count = 0
for _, v in ipairs(lev_a) do if v == "X" then x_count = x_count + 1 end end
check(x_count == 1,                 "append: level X não duplicado")

-- count_nonnull
check(c:count_nonnull() == 4,       "count_nonnull = 4")

-- ================================================================
-- 3. .cat accessor
-- ================================================================

local ccat = S.from_table({"B", "A", NA, "C", "A"}, "categorical")

-- codes(): Series<int64> com índices 1-based
local codes = ccat.cat:codes()
check(codes._dtype == "int64",      "codes: dtype=int64")
check(codes:len() == 5,             "codes: len=5")
check(codes:is_null(3),             "codes: NA → null")
-- B=1, A=2, C=3 (ordem de primeira aparição)
check(codes:get(1) == 1,            "codes[1] = 1 (B)")
check(codes:get(2) == 2,            "codes[2] = 2 (A)")
check(codes:get(4) == 3,            "codes[4] = 3 (C)")
check(codes:get(5) == 2,            "codes[5] = 2 (A reutilizado)")

-- levels()
local lev_cat = ccat.cat:levels()
check(type(lev_cat) == "table",     "levels: tabela")
check(#lev_cat == 3,                "levels: 3 elementos")
check(lev_cat[1] == "B",            "levels[1] = B")
check(lev_cat[2] == "A",            "levels[2] = A")
check(lev_cat[3] == "C",            "levels[3] = C")

-- rename_categories
local renamed = ccat.cat:rename_categories({A = "Alpha", B = "Beta"})
check(renamed:get(1) == "Beta",     "rename: B→Beta")
check(renamed:get(2) == "Alpha",    "rename: A→Alpha")
check(renamed:is_null(3),           "rename: NA preservado")
check(renamed:get(4) == "C",        "rename: C não alterado")
-- original intacto
check(ccat:get(1) == "B",           "rename: original intacto")

-- set_categories: reordena e restringe
local sc = ccat.cat:set_categories({"C", "A"})  -- remove B
check(sc:get(1) == nil,             "set_categories: B removido → null")
check(sc:get(2) == "A",             "set_categories: A preservado")
check(sc:get(4) == "C",             "set_categories: C preservado")
local lev_sc = sc.cat:levels()
check(#lev_sc == 2,                 "set_categories: 2 levels")
check(lev_sc[1] == "C",             "set_categories: order respeitada")

-- add_categories
local ac = ccat.cat:add_categories({"D", "E"})
check(#ac.cat:levels() == 5,        "add_categories: 5 levels")
check(ac:get(1) == "B",             "add_categories: dados intactos")

-- remove_categories
local rc = ccat.cat:remove_categories({"A"})
check(rc:get(2) == nil,             "remove_categories: A→null")
check(rc:get(5) == nil,             "remove_categories: A[5]→null")
check(rc:get(1) == "B",             "remove_categories: B intacto")
check(#rc.cat:levels() == 2,        "remove_categories: 2 levels")

-- ================================================================
-- 4. Comparações → Series<bool>
-- ================================================================

local ccmp = S.from_table({"SP", "RJ", "SP", NA, "MG"}, "categorical")

-- eq
local eq = ccmp:eq("SP")
check(eq._dtype == "bool",          "eq: dtype=bool")
check(eq:get(1) == true,            "eq: SP==SP = true")
check(eq:get(2) == false,           "eq: RJ==SP = false")
check(eq:get(3) == true,            "eq: SP==SP = true")
check(eq:is_null(4),                "eq: NA → NA")
check(eq:get(5) == false,           "eq: MG==SP = false")

-- ne
local ne = ccmp:ne("SP")
check(ne:get(1) == false,           "ne: SP!=SP = false")
check(ne:get(2) == true,            "ne: RJ!=SP = true")
check(ne:is_null(4),                "ne: NA → NA")

-- lt / le / gt / ge (ordem lexicográfica)
local cord = S.from_table({"B", "A", "C"}, "categorical")
local lt = cord:lt("B")
check(lt:get(1) == false,           "lt: B<B = false")
check(lt:get(2) == true,            "lt: A<B = true")
check(lt:get(3) == false,           "lt: C<B = false")

local gt = cord:gt("B")
check(gt:get(1) == false,           "gt: B>B = false")
check(gt:get(3) == true,            "gt: C>B = true")

local le = cord:le("B")
check(le:get(1) == true,            "le: B<=B = true")
check(le:get(2) == true,            "le: A<=B = true")

local ge = cord:ge("B")
check(ge:get(1) == true,            "ge: B>=B = true")
check(ge:get(3) == true,            "ge: C>=B = true")

-- Erro: comparação com não-string
local ok2, err2 = pcall(function() cord:eq(42) end)
check(not ok2,                      "eq: não-string → erro")

-- ================================================================
-- 5. Ordenação e seleção
-- ================================================================

local csort = S.from_table({"C", "A", "B", "A"}, "categorical")

-- sort asc (lexicográfico)
local sorted = csort:sort(true)
check(sorted:get(1) == "A",         "sort asc: 1º = A")
check(sorted:get(2) == "A",         "sort asc: 2º = A")
check(sorted:get(3) == "B",         "sort asc: 3º = B")
check(sorted:get(4) == "C",         "sort asc: 4º = C")

-- sort desc
local sortd = csort:sort(false)
check(sortd:get(1) == "C",          "sort desc: 1º = C")
check(sortd:get(4) == "A",          "sort desc: 4º = A")

-- sort com nulo → erro
local cnull = S.from_table({"A", NA, "B"}, "categorical")
local ok3, _ = pcall(function() cnull:sort(true) end)
check(not ok3,                      "sort com null → erro")

-- argsort
local idx = csort:argsort(true)
check(type(idx) == "table",         "argsort: retorna tabela")
check(idx[1] == 2 or idx[1] == 4,  "argsort asc: 1º é A (idx 2 ou 4)")
check(idx[4] == 1,                  "argsort asc: 4º = C (idx 1)")

-- argsort com nulo → nil
check(cnull:argsort(true) == nil,   "argsort com null → nil")

-- take
local tk = csort:take({3, 1})
check(tk:len() == 2,                "take: len=2")
check(tk:get(1) == "B",             "take: 1º = B (era idx 3)")
check(tk:get(2) == "C",             "take: 2º = C (era idx 1)")

-- head / tail
local hd = csort:head(2)
check(hd:len() == 2,                "head(2): len=2")
check(hd:get(1) == "C",             "head(2): 1º = C")

local tl = csort:tail(1)
check(tl:len() == 1,                "tail(1): len=1")
check(tl:get(1) == "A",             "tail(1): 1º = A")

-- filter via Series<bool>
local cfl = S.from_table({"SP","RJ","SP","MG"}, "categorical")
local mfl = cfl:eq("SP")
local filtered = cfl:filter(mfl)
check(filtered:len() == 2,          "filter: len=2")
check(filtered:get(1) == "SP",      "filter: 1º = SP")
check(filtered:get(2) == "SP",      "filter: 2º = SP")

-- dropna
local cdn = S.from_table({"A", NA, "B", NA, "C"}, "categorical")
local dropped = cdn:dropna()
check(dropped:len() == 3,           "dropna: len=3")
check(dropped:get(1) == "A",        "dropna: 1º = A")
check(dropped:get(3) == "C",        "dropna: 3º = C")

-- clone: independência
local cl = cfl:clone()
cl:set(1, "XX")
check(cfl:get(1) == "SP",           "clone: original intacto")
check(cl:get(1) == "XX",            "clone: modificado")

-- ================================================================
-- 6. fillna
-- ================================================================

local cfn = S.from_table({"A", NA, NA, "C"}, "categorical")
local filled = cfn:fillna("B")
check(filled:get(1) == "A",         "fillna: não-nulo intacto")
check(filled:get(2) == "B",         "fillna: NA preenchido")
check(filled:get(3) == "B",         "fillna: NA preenchido [3]")
check(filled:get(4) == "C",         "fillna: não-nulo intacto [4]")
-- original intacto
check(cfn:is_null(2),               "fillna: original não mutado")
-- fillna cria level se necessário
local lev_fn = filled.cat:levels()
local has_b = false
for _, v in ipairs(lev_fn) do if v == "B" then has_b = true end end
check(has_b,                        "fillna: B adicionado aos levels")

-- ================================================================
-- 7. unique / nunique / value_counts
-- ================================================================

local cu = S.from_table({"C", "A", "B", "A", NA, "C"}, "categorical")

-- unique
local uniq = cu:unique()
check(uniq._dtype == "categorical", "unique: dtype=categorical")
check(uniq:len() == 3,              "unique: 3 valores (sem NA)")
-- os valores distintos estão presentes
local uvals = {}
for i = 1, uniq:len() do uvals[uniq:get(i)] = true end
check(uvals["A"] and uvals["B"] and uvals["C"], "unique: A, B, C presentes")

-- nunique
check(cu:nunique() == 3,            "nunique = 3")

-- value_counts: retorna {value=..., count=...}
local vc = cu:value_counts()
check(type(vc) == "table",          "value_counts: retorna tabela")
check(vc.value ~= nil,              "value_counts: campo value")
check(vc.count ~= nil,              "value_counts: campo count")
-- C aparece 2x, A aparece 2x, B aparece 1x
local count_map = {}
for i, v in ipairs(vc.value) do count_map[v] = vc.count[i] end
check(count_map["A"] == 2,          "value_counts: A=2")
check(count_map["C"] == 2,          "value_counts: C=2")
check(count_map["B"] == 1,          "value_counts: B=1")

-- ================================================================
-- 8. describe
-- ================================================================

local cd = S.from_table({"SP","RJ","SP",NA,"MG","SP"}, "categorical")
local desc = cd:describe()
check(type(desc) == "table",        "describe: retorna tabela")
check(desc.dtype == "categorical",  "describe: dtype=categorical")
check(desc.count == 5,              "describe: count=5 (sem NA)")
check(desc.nulls == 1,              "describe: nulls=1")
check(desc.unique == 3,             "describe: unique=3")
check(desc.levels == 3,             "describe: levels=3")
check(desc.top == "SP",             "describe: top=SP (mais frequente)")
check(desc.freq == 3,               "describe: freq=3")

-- ================================================================
-- 9. astype
-- ================================================================

local cas = S.from_table({"SP", NA, "RJ"}, "categorical")

-- categorical → string
local as_str = cas:astype("string")
check(as_str._dtype == "string",    "astype cat→str: dtype")
check(as_str:get(1) == "SP",        "astype cat→str: SP")
check(as_str:is_null(2),            "astype cat→str: NA → null")
check(as_str:get(3) == "RJ",        "astype cat→str: RJ")

-- categorical → categorical (clone)
local as_cat = cas:astype("categorical")
check(as_cat._dtype == "categorical", "astype cat→cat: dtype")
check(as_cat:get(1) == "SP",          "astype cat→cat: SP")

-- categorical com números → float64
local cnum = S.from_table({"1.5", "2.0", NA, "invalido"}, "categorical")
local as_f64 = cnum:astype("float64")
check(as_f64._dtype == "float64",    "astype cat→f64: dtype")
check(as_f64:get(1) == 1.5,          "astype cat→f64: 1.5")
check(as_f64:get(2) == 2.0,          "astype cat→f64: 2.0")
check(as_f64:is_null(3),             "astype cat→f64: NA → null")
check(as_f64:is_null(4),             "astype cat→f64: invalido → null")

-- categorical → int64
local cint = S.from_table({"10", "20", NA}, "categorical")
local as_i64 = cint:astype("int64")
check(as_i64._dtype == "int64",      "astype cat→i64: dtype")
check(as_i64:get(1) == 10,           "astype cat→i64: 10")
check(as_i64:is_null(3),             "astype cat→i64: NA → null")

-- string → categorical via Series:astype
local ss = S.from_table({"SP", "RJ", NA, "SP"}, "string")
local as_cat2 = ss:astype("categorical")
check(as_cat2._dtype == "categorical", "astype str→cat: dtype")
check(as_cat2:get(1) == "SP",          "astype str→cat: SP")
check(as_cat2:is_null(3),             "astype str→cat: NA → null")
check(as_cat2:get(4) == "SP",          "astype str→cat: SP reutilizado")
local lev_c2 = as_cat2.cat:levels()
check(#lev_c2 == 2,                    "astype str→cat: 2 levels (SP e RJ)")

-- dtype inválido → erro
local ok4, _ = pcall(function() cas:astype("datetime") end)
check(not ok4,                         "astype cat→datetime: erro")

-- ================================================================
-- 10. to_table
-- ================================================================

local ctt = S.from_table({"A", NA, "B"}, "categorical")
local t = ctt:to_table()
check(t[1] == "A",                   "to_table: [1]=A")
check(t[2] == nil,                   "to_table: [2]=nil (NA)")
check(t[3] == "B",                   "to_table: [3]=B")

-- to_table com na_value
local t2 = ctt:to_table("N/A")
check(t2[2] == "N/A",                "to_table na_value: [2]=N/A")

-- ================================================================
-- 11. Integração com DataSet
-- ================================================================

local ds = smaug.DataSet({
    {"cidade",  {"SP", "RJ", "SP", "MG", "RJ"}, "categorical"},
    {"produto", {"X",  "Y",  "X",  "Z",  "Y"},  "categorical"},
    {"valor",   {10.0, 20.0, 30.0, 40.0, 50.0}, "float64"},
})

check(ds:has_column("cidade"),        "DataSet: coluna cidade existe")
check(ds:col("cidade")._dtype == "categorical", "DataSet: dtype=categorical")
check(ds:ncols() == 3,                "DataSet: 3 colunas")
check(ds:nrows() == 5,                "DataSet: 5 linhas")

-- filter
local m = ds:col("cidade"):eq("SP")
local dsf = ds:filter(m)
check(dsf:nrows() == 2,               "DataSet filter: 2 linhas SP")
check(dsf:col("valor"):sum() == 40.0, "DataSet filter: soma SP = 40")

-- sort_by categorical
local dss = ds:sort_by("cidade", true)
check(dss:col("cidade"):get(1) == "MG", "sort_by asc: 1º = MG")
check(dss:col("cidade"):get(5) == "SP", "sort_by asc: 5º = SP")

-- head / tail
local dsh = ds:head(2)
check(dsh:nrows() == 2,               "DataSet head(2): 2 linhas")
check(dsh:col("cidade")._dtype == "categorical", "head: dtype preservado")

local dst = ds:tail(1)
check(dst:nrows() == 1,               "DataSet tail(1): 1 linha")

-- iloc
local dsi = ds:iloc(2, 4)
check(dsi:nrows() == 3,               "DataSet iloc(2,4): 3 linhas")

-- select
local sel = ds:select({"cidade", "valor"})
check(sel:ncols() == 2,               "select: 2 colunas")
check(sel:col("cidade")._dtype == "categorical", "select: dtype preservado")

-- dropna: sem nulos — todas as linhas preservadas
local drp = ds:dropna()
check(drp:nrows() == 5,               "DataSet dropna sem NA: 5 linhas")

-- dropna com nulos
local ds_na = smaug.DataSet({
    {"cat", {"A", NA, "B", NA, "C"}, "categorical"},
    {"v",   {1,   2,  3,  4,  5},   "float64"},
})
local drp2 = ds_na:dropna()
check(drp2:nrows() == 3,              "DataSet dropna: 3 linhas")

-- groupby por coluna categorical
local gb = ds:groupby("cidade"):sum("valor")
check(gb:nrows() == 3,                "groupby sum: 3 grupos")
check(gb:has_column("cidade"),        "groupby: coluna chave presente")
check(gb:has_column("valor"),         "groupby: coluna valor presente")

-- groupby chave composta (categorical + string/i64)
local gb2 = ds:groupby({"cidade", "produto"}):sum("valor")
check(gb2:nrows() == 3,               "groupby composto: 3 grupos únicos")

-- groupby count
local gbc = ds:groupby("cidade"):count()
check(gbc:nrows() == 3,               "groupby count: 3 grupos")

-- assign: adicionar coluna categorical
local ds2 = ds:assign("regiao", S.from_table({"SE","SE","SE","SE","SE"}, "categorical"))
check(ds2:has_column("regiao"),        "assign: coluna regiao criada")
check(ds2:col("regiao")._dtype == "categorical", "assign: dtype=categorical")

-- __newindex
ds["zona"] = S.from_table({"N","S","N","S","N"}, "categorical")
check(ds:has_column("zona"),           "df[col] = cat: coluna criada")
check(ds:col("zona"):get(1) == "N",    "df[col] = cat: valor correto")

-- update_column
ds:update_column("zona", S.from_table({"L","O","L","O","L"}, "categorical"))
check(ds:col("zona"):get(1) == "L",    "update_column categorical: atualizado")

-- describe DataSet com categorical
local ddesc = ds:describe()
check(type(ddesc) == "table",          "DataSet describe: retorna tabela")
check(ddesc["cidade"] ~= nil,          "DataSet describe: cidade presente")
check(ddesc["cidade"].dtype == "categorical", "DataSet describe: dtype correto")
check(ddesc["cidade"].unique == 3,     "DataSet describe: unique=3")

-- concat com categorical
local ds3 = smaug.DataSet({
    {"cidade", {"MG", "RS"}, "categorical"},
    {"valor",  {100.0, 200.0}, "float64"},
})
local cat_ds = smaug.concat({ds:select({"cidade","valor"}), ds3})
check(cat_ds:nrows() == 7,             "concat categorical: 7 linhas")

-- join: categorical como chave
local dsa = smaug.DataSet({
    {"cidade", {"SP","RJ","MG"}, "categorical"},
    {"pop",    {12.0, 6.0, 2.0}, "float64"},
})
local joined = ds:select({"cidade","valor"}):join(dsa, "cidade", "left")
check(joined:nrows() == 5,             "join categorical: 5 linhas (left)")
check(joined:has_column("pop"),        "join: coluna pop presente")

-- ================================================================
-- 12. Erros esperados
-- ================================================================

-- .cat em dtype errado
local ok5, e5 = pcall(function()
    S.from_table({1.0, 2.0}, "float64").cat:levels()
end)
check(not ok5,                         "erro: .cat em float64")

-- índice fora dos limites
local ok6, _ = pcall(function() c:get(0) end)
check(not ok6,                         "erro: get(0) fora dos limites")
local ok7, _ = pcall(function() c:get(100) end)
check(not ok7,                         "erro: get(100) fora dos limites")

-- set fora dos limites
local ok8, _ = pcall(function() c:set(0, "X") end)
check(not ok8,                         "erro: set(0) fora dos limites")

-- is_null fora dos limites
local ok9, _ = pcall(function() c:is_null(0) end)
check(not ok9,                         "erro: is_null(0) fora dos limites")

-- take com índice inválido
local ok10, _ = pcall(function() c:take({1, 999}) end)
check(not ok10,                        "erro: take com índice inválido")

-- filter tamanho diferente
local ok11, _ = pcall(function()
    local m2 = S.from_table({true, false}, "bool")
    c:filter(m2)
end)
check(not ok11,                        "erro: filter tamanho diferente")

-- fillna sem argumento
local ok12, _ = pcall(function()
    S.from_table({"A",NA}, "categorical"):fillna(nil)
end)
check(not ok12,                        "erro: fillna nil")


-- =====================================================================
-- Completude (de test_completeness.lua)
-- =====================================================================

--
-- Roda da raiz: luajit tests/test_completeness.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")
local S  = smaug.Series
local NA = smaug.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
local function approx(a, b, tol)
    tol = tol or 1.0   -- 1 ms de tolerância para epoch_ms
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tol
end

-- Épocas de referência
local ep_jan  = S.dt_parse("2024-01-01T00:00:00Z")   -- menor
local ep_mar  = S.dt_parse("2024-03-15T00:00:00Z")   -- meio
local ep_dec  = S.dt_parse("2024-12-31T00:00:00Z")   -- maior

-- ================================================================
-- 1. datetime — argmin / argmax
-- ================================================================

local dt = S.from_table({ep_mar, ep_jan, NA, ep_dec}, "datetime")

check(dt:argmin() == 2, "dt:argmin() = posição do menor epoch (idx 2)")
check(dt:argmax() == 4, "dt:argmax() = posição do maior epoch (idx 4)")

-- série toda nula
local dt_all_null = S.from_table({NA, NA}, "datetime")
check(dt_all_null:argmin() == nil, "dt:argmin() toda nula = nil")
check(dt_all_null:argmax() == nil, "dt:argmax() toda nula = nil")

-- série de 1 elemento
local dt_single = S.from_table({ep_jan}, "datetime")
check(dt_single:argmin() == 1, "dt:argmin() único = 1")
check(dt_single:argmax() == 1, "dt:argmax() único = 1")

-- ================================================================
-- 2. datetime — cummin / cummax
-- ================================================================

local dt2 = S.from_table({ep_dec, ep_jan, ep_mar, NA}, "datetime")
local cmn = dt2:cummin()
local cmx = dt2:cummax()

check(cmn._dtype == "datetime",         "cummin dtype = datetime")
check(cmx._dtype == "datetime",         "cummax dtype = datetime")
check(cmn:get(1) == ep_dec,             "cummin[1] = ep_dec (ainda só ele)")
check(cmn:get(2) == ep_jan,             "cummin[2] = ep_jan (menor até aqui)")
check(cmn:get(3) == ep_jan,             "cummin[3] = ep_jan (mantém)")
check(cmn:get(4) == nil,                "cummin[4] = null (propaga nulo)")
check(cmx:get(1) == ep_dec,             "cummax[1] = ep_dec")
check(cmx:get(2) == ep_dec,             "cummax[2] = ep_dec (mantém maior)")
check(cmx:get(3) == ep_dec,             "cummax[3] = ep_dec")
check(cmx:get(4) == nil,                "cummax[4] = null")

-- ================================================================
-- 3. datetime — diff → Series<int64> (duração em ms)
-- ================================================================

-- ep_mar - ep_jan em ms
local delta_jan_mar = ep_mar - ep_jan    -- diferença em ms

local dt3 = S.from_table({ep_jan, ep_mar, NA, ep_dec}, "datetime")
local diffs = dt3:diff()

check(diffs._dtype == "int64",           "diff dtype = int64 (duração)")
check(diffs:get(1) == nil,               "diff[1] = null (sem predecessor)")
check(approx(diffs:get(2), delta_jan_mar), "diff[2] = ep_mar - ep_jan")
check(diffs:get(3) == nil,               "diff[3] = null (operando nulo)")
check(diffs:get(4) == nil,               "diff[4] = null (prev nulo)")

-- periods = 2
local diffs2 = dt3:diff(2)
check(diffs2:get(1) == nil,              "diff(2)[1] = null")
check(diffs2:get(2) == nil,              "diff(2)[2] = null")
check(diffs2:get(3) == nil,              "diff(2)[3] = null (cur nulo)")

-- ================================================================
-- 4. datetime — median (epoch_ms do meio)
-- ================================================================

local dt4 = S.from_table({ep_jan, ep_dec, ep_mar}, "datetime")
local med = dt4:median()
-- mediana de 3 = valor do meio (ep_mar)
check(approx(med, ep_mar, 1.0),          "dt:median() = epoch_ms do meio")

-- com nulo (ignore_na=true por padrão)
local dt4n = S.from_table({ep_jan, NA, ep_mar, ep_dec}, "datetime")
local med_na = dt4n:median()
-- não-nulos: ep_jan, ep_mar, ep_dec → mediana = ep_mar
check(approx(med_na, ep_mar, 1.0),       "dt:median() ignora nulos por padrão")

-- ignore_na=false com nulo → nil
local med_strict = dt4n:median(false)
check(med_strict == nil,                 "dt:median(false) com nulo = nil")

-- série vazia
local dt4e = S.from_table({}, "datetime")
check(dt4e:median() == nil,              "dt:median() vazia = nil")

-- ================================================================
-- 5. datetime — quantile
-- ================================================================

local dt5 = S.from_table({ep_jan, ep_mar, ep_dec}, "datetime")
local q0  = dt5:quantile(0)
local q1  = dt5:quantile(1)
local q05 = dt5:quantile(0.5)

check(approx(q0,  ep_jan, 1.0),          "dt:quantile(0) = epoch menor")
check(approx(q1,  ep_dec, 1.0),          "dt:quantile(1) = epoch maior")
check(approx(q05, ep_mar, 1.0),          "dt:quantile(0.5) = mediana")

-- ignore_na=false com nulo → nil
local dt5n = S.from_table({ep_jan, NA, ep_dec}, "datetime")
check(dt5n:quantile(0.5, false) == nil,  "dt:quantile(false) com nulo = nil")

-- ================================================================
-- 6. categorical — isna / notna
-- ================================================================

local c = S.from_table({"SP", NA, "RJ", NA, "MG"}, "categorical")

check(c:isna(1)  == false,   "isna(1) = false (SP)")
check(c:isna(2)  == true,    "isna(2) = true (NA)")
check(c:notna(1) == true,    "notna(1) = true")
check(c:notna(2) == false,   "notna(2) = false")

-- erro de bounds via is_null subjacente
local ok_err, _ = pcall(function() c:isna(0) end)
check(not ok_err,            "isna(0) = erro (fora dos limites)")

-- ================================================================
-- 7. categorical — min / max (lexicográfico)
-- ================================================================

local c2 = S.from_table({"SP", "RJ", NA, "AM", "MG"}, "categorical")

check(c2:min() == "AM",      "min() = AM (lex menor)")
check(c2:max() == "SP",      "max() = SP (lex maior)")

-- toda nula
local c2n = S.from_table({NA, NA}, "categorical")
check(c2n:min() == nil,      "min() toda nula = nil")
check(c2n:max() == nil,      "max() toda nula = nil")

-- único elemento não-nulo
local c2s = S.from_table({NA, "BA", NA}, "categorical")
check(c2s:min() == "BA",     "min() único não-nulo = BA")
check(c2s:max() == "BA",     "max() único não-nulo = BA")

-- ================================================================
-- 8. categorical — ffill
-- ================================================================

local c3 = S.from_table({NA, "SP", NA, "RJ", NA}, "categorical")
local ff  = c3:ffill()

check(ff._dtype == "categorical",  "ffill dtype = categorical")
check(ff:get(1) == nil,            "ffill[1] = nil (nenhum anterior)")
check(ff:get(2) == "SP",           "ffill[2] = SP")
check(ff:get(3) == "SP",           "ffill[3] = SP (preenchido)")
check(ff:get(4) == "RJ",           "ffill[4] = RJ")
check(ff:get(5) == "RJ",           "ffill[5] = RJ (preenchido)")

-- sem nulos — retorna equivalente
local c3nn = S.from_table({"A", "B", "C"}, "categorical")
local ff2   = c3nn:ffill()
check(ff2:get(1) == "A" and ff2:get(3) == "C", "ffill sem nulos = inalterado")

-- ================================================================
-- 9. categorical — bfill
-- ================================================================

local c4  = S.from_table({NA, "SP", NA, "RJ", NA}, "categorical")
local bf  = c4:bfill()

check(bf:get(1) == "SP",           "bfill[1] = SP (próximo à direita)")
check(bf:get(2) == "SP",           "bfill[2] = SP")
check(bf:get(3) == "RJ",           "bfill[3] = RJ (próximo à direita)")
check(bf:get(4) == "RJ",           "bfill[4] = RJ")
check(bf:get(5) == nil,            "bfill[5] = nil (nenhum à direita)")

-- ================================================================
-- 10. categorical — shift
-- ================================================================

local c5 = S.from_table({"A", "B", "C", "D"}, "categorical")
local sh1 = c5:shift()     -- default periods=1
local sh2 = c5:shift(2)

check(sh1._dtype == "categorical",  "shift dtype = categorical")
check(sh1:get(1) == nil,            "shift(1)[1] = null (sem predecessor)")
check(sh1:get(2) == "A",            "shift(1)[2] = A")
check(sh1:get(3) == "B",            "shift(1)[3] = B")
check(sh1:get(4) == "C",            "shift(1)[4] = C")

check(sh2:get(1) == nil,            "shift(2)[1] = null")
check(sh2:get(2) == nil,            "shift(2)[2] = null")
check(sh2:get(3) == "A",            "shift(2)[3] = A")
check(sh2:get(4) == "B",            "shift(2)[4] = B")

-- shift com nulos no meio
local c5n = S.from_table({"A", NA, "C"}, "categorical")
local sh_n = c5n:shift()
check(sh_n:get(1) == nil,           "shift(1) com NA[1] = null")
check(sh_n:get(2) == "A",           "shift(1) com NA[2] = A")
check(sh_n:get(3) == nil,           "shift(1) com NA[3] = null (NA deslocado)")

-- ================================================================
-- 11. categorical — map
-- ================================================================

local c6 = S.from_table({"sp", "rj", NA, "mg"}, "categorical")

-- map → string (upper)
local up = c6:map(function(v) return v and string.upper(v) or nil end, "string")
check(up._dtype == "string",        "map → string dtype")
check(up:get(1) == "SP",            "map upper[1] = SP")
check(up:get(3) == nil,             "map upper[3] = nil (null propaga)")

-- map → bool (predicado)
local has_s = c6:map(function(v)
    if v == nil then return nil end
    return string.find(v, "s") ~= nil
end, "bool")
check(has_s._dtype == "bool",       "map → bool dtype")
check(has_s:get(1) == true,         "map bool[1] = true (sp tem s)")
check(has_s:get(2) == false,        "map bool[2] = false (rj não tem s)")

-- map → int64 (comprimento)
local lens = c6:map(function(v)
    if v == nil then return nil end
    return #v
end, "int64")
check(lens._dtype == "int64",       "map → int64 dtype")
check(lens:get(1) == 2,             "map len[1] = 2 (sp)")
check(lens:get(3) == nil,           "map len[3] = nil")

-- inferência de dtype (sem dtype explícito)
local inferred = c6:map(function(v) return v and #v or nil end)
check(inferred._dtype == "int64",   "map dtype inferido = int64 (números inteiros)")

-- ================================================================
-- 12. categorical — where
-- ================================================================

local c7   = S.from_table({"SP", "RJ", "MG", "BA"}, "categorical")
local mask_bool = S.from_table({true, false, true, false}, "bool")

-- substituição por string escalar
local w1 = c7:where(mask_bool, "OUTRO")
check(w1._dtype == "categorical",   "where dtype = categorical")
check(w1:get(1) == "SP",            "where[1] = SP (cond true)")
check(w1:get(2) == "OUTRO",         "where[2] = OUTRO (cond false)")
check(w1:get(3) == "MG",            "where[3] = MG (cond true)")
check(w1:get(4) == "OUTRO",         "where[4] = OUTRO (cond false)")

-- substituição por nil → null
local w2 = c7:where(mask_bool, nil)
check(w2:get(2) == nil,             "where com nil = null onde false")

-- substituição por outro CategoricalSeries
local c7b = S.from_table({"A", "B", "C", "D"}, "categorical")
local w3  = c7:where(mask_bool, c7b)
check(w3:get(1) == "SP",            "where outro cat[1] = SP")
check(w3:get(2) == "B",             "where outro cat[2] = B (de c7b)")

-- erro: tamanhos diferentes
local ok_w, _ = pcall(function()
    c7:where(S.from_table({true, false}, "bool"), "X")
end)
check(not ok_w,                     "where tamanhos diferentes = erro")

-- ================================================================
-- 13. categorical — mask
-- ================================================================

local c8 = S.from_table({"SP", "RJ", "MG", "BA"}, "categorical")
local mb  = S.from_table({true, false, true, false}, "bool")

-- mask = inverso de where
local m1 = c8:mask(mb, "OUTRO")
check(m1:get(1) == "OUTRO",         "mask[1] = OUTRO (cond true → substituído)")
check(m1:get(2) == "RJ",            "mask[2] = RJ (cond false → mantido)")
check(m1:get(3) == "OUTRO",         "mask[3] = OUTRO")
check(m1:get(4) == "BA",            "mask[4] = BA")

-- mask com nil → null
local m2 = c8:mask(mb, nil)
check(m2:get(1) == nil,             "mask com nil = null onde true")
check(m2:get(2) == "RJ",            "mask com nil[2] = RJ (mantido)")

-- erro: tamanhos diferentes
local ok_m, _ = pcall(function()
    c8:mask(S.from_table({true}, "bool"), "X")
end)
check(not ok_m,                     "mask tamanhos diferentes = erro")

-- ================================================================
-- Resultado
-- ================================================================

do
    -- 11.1/11.2: CategoricalSeries e .cat proxy se auto-mostram legíveis
    local c = Series({"a", "b", "a", "c"}, "categorical"); c._name = "cor"
    local tc = tostring(c)
    check(tc:find("^table:") == nil, "11.1 CategoricalSeries __tostring não vaza table:")
    check(tc:find("Categorias", 1, true) ~= nil, "11.1 __tostring tem rodapé de categorias")
    check(tc:find("(3)", 1, true) ~= nil, "11.1 __tostring conta 3 categorias")
    local tp = tostring(c.cat)
    check(tp:find("^table:") == nil and tp:find(".cat", 1, true) ~= nil,
          "11.2 .cat proxy __tostring legível")
end


print(string.format("OK — %d checks passaram (Series: categorical + completude datetime/categorical)", n_ok))
