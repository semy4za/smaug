-- tests/test_duplicates.lua
-- Bloco F.6 — duplicatas e operações binárias.
--   Series: duplicated, drop_duplicates, combine_first, searchsorted, rep_each
--   DataSet: duplicated, drop_duplicates (multi-coluna)
--
-- Roda da raiz: luajit tests/test_duplicates.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")
local S  = smaug.Series
local NA = smaug.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- ================================================================
-- 1. Series:duplicated — keep first/last/none, nulos como valor
-- ================================================================

local d = S.from_table({1, 2, 2, 3, 1, NA, NA}, "int64")

local df = d:duplicated("first")
check(df._dtype == "bool",          "duplicated → bool")
check(df:get(1) == false,           "dup first [1]=1 1ª → false")
check(df:get(3) == true,            "dup first [3]=2 2ª → true")
check(df:get(5) == true,            "dup first [5]=1 repetido → true")
check(df:get(6) == false,           "dup first [6]=NA 1ª → false")
check(df:get(7) == true,            "dup first [7]=NA 2ª → true (null é valor)")

local dl = d:duplicated("last")
check(dl:get(1) == true,            "dup last [1]=1 não-última → true")
check(dl:get(5) == false,           "dup last [5]=1 última → false")
check(dl:get(6) == true,            "dup last [6]=NA não-última → true")
check(dl:get(7) == false,           "dup last [7]=NA última → false")

local dn = d:duplicated("none")
check(dn:get(1) == true,            "dup none [1]=1 tem cópia → true")
check(dn:get(4) == false,           "dup none [4]=3 único → false")
check(dn:get(6) == true,            "dup none [6]=NA tem cópia → true")

-- default = first
check(d:duplicated():get(3) == true, "duplicated() default = first")

-- keep inválido → erro
check(not pcall(function() d:duplicated("bad") end), "duplicated keep inválido = erro")

-- ================================================================
-- 2. Series:drop_duplicates
-- ================================================================

local dd_first = d:drop_duplicates("first")
-- mantém: 1, 2, 3, NA (primeira de cada)
check(dd_first:len() == 4,          "drop_duplicates first: 4 elementos")
check(dd_first:get(1) == 1,         "drop first: 1")
check(dd_first:get(2) == 2,         "drop first: 2")
check(dd_first:get(3) == 3,         "drop first: 3")
check(dd_first:get(4) == nil,       "drop first: NA")

-- none: só o que não tem cópia → 3
local dd_none = d:drop_duplicates("none")
check(dd_none:len() == 1,           "drop_duplicates none: 1 elemento")
check(dd_none:get(1) == 3,          "drop none: só o 3")

-- série sem duplicatas → inalterada
local uniq = S.from_table({1, 2, 3}, "int64")
check(uniq:drop_duplicates():len() == 3, "drop sem duplicatas: inalterada")

-- ================================================================
-- 3. Series:combine_first
-- ================================================================

local a = S.from_table({1, NA, 3, NA}, "int64")
local b = S.from_table({9, 8, 7, NA}, "int64")
local comb = a:combine_first(b)
check(comb:get(1) == 1,             "combine_first: self não-null preservado")
check(comb:get(2) == 8,             "combine_first: null preenchido por other")
check(comb:get(3) == 3,             "combine_first: self preservado")
check(comb:get(4) == nil,           "combine_first: ambos null → null")

-- string
local sa = S.from_table({"x", NA}, "string")
local sb = S.from_table({"y", "z"}, "string")
check(sa:combine_first(sb):get(2) == "z", "combine_first string")

-- erros
check(not pcall(function() a:combine_first(42) end), "combine_first não-Series = erro")
check(not pcall(function()
    a:combine_first(S.from_table({1.0}, "float64"))
end), "combine_first dtype diferente = erro")
check(not pcall(function()
    a:combine_first(S.from_table({1,2}, "int64"))
end), "combine_first tamanho diferente = erro")

-- ================================================================
-- 4. Series:searchsorted — binary search
-- ================================================================

local srt = S.from_table({10, 20, 20, 30, 40}, "int64")

check(srt:searchsorted(20) == 2,            "searchsorted 20 left = 2 (antes dos iguais)")
check(srt:searchsorted(20, "right") == 4,   "searchsorted 20 right = 4 (após os iguais)")
check(srt:searchsorted(25) == 4,            "searchsorted 25 = 4 (entre 20 e 30)")
check(srt:searchsorted(5) == 1,             "searchsorted 5 = 1 (antes de tudo)")
check(srt:searchsorted(99) == 6,            "searchsorted 99 = 6 (após tudo)")
check(srt:searchsorted(10) == 1,            "searchsorted 10 left = 1")
check(srt:searchsorted(40, "right") == 6,   "searchsorted 40 right = 6")

-- série não-ordenada → erro
check(not pcall(function() d:searchsorted(2) end), "searchsorted não-ordenada = erro")
-- side inválido → erro
check(not pcall(function() srt:searchsorted(20, "bad") end), "searchsorted side inválido = erro")

-- float
local fsrt = S.from_table({1.5, 2.5, 3.5}, "float64")
check(fsrt:searchsorted(2.0) == 2,          "searchsorted float")

-- string (ordenada lexicograficamente)
local ssrt = S.from_table({"apple", "mango", "zebra"}, "string")
check(ssrt:searchsorted("banana") == 2,     "searchsorted string")

-- ================================================================
-- 5. Series:rep_each
-- ================================================================

-- escalar
local re2 = S.from_table({1, 2, 3}, "int64"):rep_each(2)
check(re2:len() == 6,               "rep_each(2): 6 elementos")
check(re2:get(1) == 1 and re2:get(2) == 1, "rep_each(2): 1,1")
check(re2:get(5) == 3 and re2:get(6) == 3, "rep_each(2): 3,3")

-- n=1 → cópia
local re1 = S.from_table({1, 2}, "int64"):rep_each(1)
check(re1:len() == 2,               "rep_each(1): inalterado em tamanho")

-- n=0 → vazia
local re0 = S.from_table({1, 2, 3}, "int64"):rep_each(0)
check(re0:len() == 0,               "rep_each(0): série vazia")

-- por Series<int64>
local base  = S.from_table({10, 20, 30}, "int64")
local times = S.from_table({1, 0, 2}, "int64")
local rev = base:rep_each(times)
check(rev:len() == 3,               "rep_each Series: 1+0+2 = 3 elementos")
check(rev:get(1) == 10,             "rep_each Series: 10 (1x)")
check(rev:get(2) == 30,             "rep_each Series: 30 (2x, 1º)")
check(rev:get(3) == 30,             "rep_each Series: 30 (2x, 2º)")

-- nulos repetidos como nulos
local rn = S.from_table({NA, 5}, "int64"):rep_each(2)
check(rn:get(1) == nil and rn:get(2) == nil, "rep_each: nulos repetidos")
check(rn:get(3) == 5,               "rep_each: valor após nulos")

-- erros
check(not pcall(function() base:rep_each(-1) end), "rep_each n negativo = erro")
check(not pcall(function() base:rep_each(1.5) end), "rep_each n não-inteiro = erro")
check(not pcall(function()
    base:rep_each(S.from_table({1.0,2.0,3.0}, "float64"))
end), "rep_each Series não-int64 = erro")

-- ================================================================
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

print(string.format(
    "OK — %d checks passaram (F.6 duplicatas: Series duplicated/drop_duplicates/" ..
    "combine_first/searchsorted/rep_each + DataSet duplicated/drop_duplicates)",
    n_ok))
