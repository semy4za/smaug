-- tests/dataset/test_stat.lua
-- DataSet: corr/cov (matriz N×N), equals, compare, duplicated, drop_duplicates.
-- Consolida: seções DataSet de test_stats.lua + test_predicates.lua + test_duplicates.lua
-- Rode da raiz: luajit tests/dataset/test_stat.lua

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

-- 9. DataSet:corr — matriz N×N
-- ================================================================

local ds = smaug.DataSet({
    {"a",    {1, 2, 3, 4, 5},   "float64"},
    {"b",    {2, 4, 6, 8, 10},  "float64"},   -- corr(a,b) = 1
    {"c",    {5, 4, 3, 2, 1},   "float64"},   -- corr(a,c) = -1
    {"nome", {"x","y","z","w","v"}, "string"}, -- ignorada
})

local cm = ds:corr()
-- estrutura: __index__ + a,b,c = 4 colunas; 3 linhas (variáveis numéricas)
check(cm:ncols() == 4,                "corr matriz: 4 colunas (__index__ + 3 num)")
check(cm:nrows() == 3,                "corr matriz: 3 linhas")
check(cm:has_column("__index__"),     "corr matriz: tem coluna __index__")
check(not cm:has_column("nome"),      "corr matriz: coluna string ignorada")

-- identificador de linhas
check(cm:column("__index__"):get(1) == "a", "corr __index__[1] = a")
check(cm:column("__index__"):get(2) == "b", "corr __index__[2] = b")
check(cm:column("__index__"):get(3) == "c", "corr __index__[3] = c")

-- diagonal = 1
check(approx(cm:column("a"):get(1), 1.0), "corr[a,a] = 1")
check(approx(cm:column("b"):get(2), 1.0), "corr[b,b] = 1")
check(approx(cm:column("c"):get(3), 1.0), "corr[c,c] = 1")

-- correlações conhecidas
check(approx(cm:column("b"):get(1), 1.0),  "corr[a,b] = 1")
check(approx(cm:column("c"):get(1), -1.0), "corr[a,c] = -1")

-- simetria da matriz
check(approx(cm:column("b"):get(1), cm:column("a"):get(2)), "corr matriz simétrica [a,b]=[b,a]")

-- ================================================================
-- 10. DataSet:cov — matriz N×N
-- ================================================================

local cov = ds:cov()
check(cov:ncols() == 4,               "cov matriz: 4 colunas")
check(cov:nrows() == 3,               "cov matriz: 3 linhas")

-- diagonal = variância amostral de cada coluna
-- var amostral de {1,2,3,4,5} = 10/4 = 2.5
check(approx(cov:column("a"):get(1), 2.5), "cov[a,a] = var amostral a = 2.5")
-- var de {2,4,6,8,10} = 40/4 = 10
check(approx(cov:column("b"):get(2), 10.0), "cov[b,b] = var amostral b = 10")

-- simetria
check(approx(cov:column("b"):get(1), cov:column("a"):get(2)), "cov matriz simétrica")

-- ================================================================
-- 11. DataSet corr/cov — sem coluna numérica → erro
-- ================================================================

local ds_str = smaug.DataSet({
    {"nome", {"x", "y"}, "string"},
})
local ok_nonum = pcall(function() ds_str:corr() end)
check(not ok_nonum,                   "corr sem coluna numérica = erro")

-- ================================================================
-- Resultado
-- ================================================================


-- =====================================================================
-- DataSet equals/compare (de test_predicates.lua)
-- =====================================================================

-- 9. DataSet:equals
-- ================================================================

local d1 = smaug.DataSet({{"a", {1,2,3}, "int64"}, {"b", {"x","y","z"}, "string"}})
local d2 = smaug.DataSet({{"a", {1,2,3}, "int64"}, {"b", {"x","y","z"}, "string"}})
local d3 = smaug.DataSet({{"a", {1,2,9}, "int64"}, {"b", {"x","y","z"}, "string"}})

check(d1:equals(d2) == true,          "DataSet equals idênticos")
check(d1:equals(d3) == false,         "DataSet equals difere")

-- colunas em ordem diferente → false
local d4 = smaug.DataSet({{"b", {"x","y","z"}, "string"}, {"a", {1,2,3}, "int64"}})
check(d1:equals(d4) == false,         "DataSet equals ordem diferente = false")

-- ncols diferente
local d5 = smaug.DataSet({{"a", {1,2,3}, "int64"}})
check(d1:equals(d5) == false,         "DataSet equals ncols diferente")

-- não-DataSet
check(d1:equals(42) == false,         "DataSet equals não-DataSet = false")

-- ================================================================
-- 10. DataSet:compare
-- ================================================================

local dcmp = d1:compare(d3)
check(dcmp:nrows() == 1,              "DataSet compare: 1 diferença")
check(dcmp:column("linha"):get(1) == 3,   "DataSet compare linha = 3")
check(dcmp:column("coluna"):get(1) == "a", "DataSet compare coluna = a")
check(dcmp:column("self"):get(1) == "3",   "DataSet compare self = 3")
check(dcmp:column("other"):get(1) == "9",  "DataSet compare other = 9")

-- idênticos → vazio
check(d1:compare(d2):nrows() == 0,    "DataSet compare idênticos = vazio")

-- formas diferentes → erro
local ok_dcmp = pcall(function() d1:compare(d5) end)
check(not ok_dcmp,                    "DataSet compare formas diferentes = erro")

-- ================================================================
-- Resultado
-- ================================================================


-- =====================================================================
-- DataSet duplicated/drop_duplicates (de test_duplicates.lua)
-- =====================================================================

-- 6. DataSet:duplicated
-- ================================================================

local ds = smaug.DataSet({
    {"a", {1, 1, 2, 2, 3},          "int64"},
    {"b", {"x", "x", "y", "z", "w"}, "string"},
})

-- por todas as colunas: linha 2 (1,x) == linha 1
local dsd = ds:duplicated()
check(dsd:get(1) == false,          "DataSet dup all [1] → false")
check(dsd:get(2) == true,           "DataSet dup all [2] = (1,x) repetida → true")
check(dsd:get(4) == false,          "DataSet dup all [4] = (2,z) único → false")

-- por subset "a"
local dsa = ds:duplicated("a")
check(dsa:get(2) == true,           "DataSet dup subset a [2]=1 → true")
check(dsa:get(4) == true,           "DataSet dup subset a [4]=2 → true")
check(dsa:get(5) == false,          "DataSet dup subset a [5]=3 → false")

-- subset como lista
local dsl = ds:duplicated({"a", "b"})
check(dsl:get(2) == true,           "DataSet dup [a,b] [2] → true")
check(dsl:get(3) == false,          "DataSet dup [a,b] [3] → false")

-- keep none por "a"
local dsn = ds:duplicated("a", "none")
check(dsn:get(1) == true,           "DataSet dup a none [1] → true (tem cópia)")
check(dsn:get(5) == false,          "DataSet dup a none [5]=3 único → false")

-- coluna inexistente → erro
check(not pcall(function() ds:duplicated("zzz") end), "DataSet dup coluna inexistente = erro")

-- ================================================================
-- 7. DataSet:drop_duplicates
-- ================================================================

-- por todas: remove linha 2
local ddall = ds:drop_duplicates()
check(ddall:nrows() == 4,           "DataSet drop all: 4 linhas")

-- por subset a: mantém a=1,2,3 (primeiras)
local dda = ds:drop_duplicates("a")
check(dda:nrows() == 3,             "DataSet drop subset a: 3 linhas")
check(dda:at(1, "a") == 1,          "DataSet drop a: primeira a=1")
check(dda:at(2, "a") == 2,          "DataSet drop a: primeira a=2")
check(dda:at(3, "a") == 3,          "DataSet drop a: a=3")

-- keep last por a
local ddl = ds:drop_duplicates("a", "last")
check(ddl:nrows() == 3,             "DataSet drop a last: 3 linhas")
check(ddl:at(1, "b") == "x",        "DataSet drop a last: última a=1 tem b=x")

-- ================================================================
-- Resultado
-- ================================================================


print(string.format("OK — %d checks passaram (DataSet: corr/cov, equals, compare, duplicated, drop_duplicates)", n_ok))
