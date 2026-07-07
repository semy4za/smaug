-- tests/series/test_predicates.lua
-- Predicados (between/isin/is_unique/is_monotonic/equals/compare/idxmin/idxmax/
-- first_last_valid_index) e duplicatas (duplicated/drop_duplicates/combine_first/
-- searchsorted/rep_each).
-- Consolida: test_predicates.lua + test_duplicates.lua
-- Rode da raiz: luajit tests/series/test_predicates.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local Series = smaug.Series
local S      = Series
local NA     = smaug.NA

local function approx(a, b) return math.abs(a - b) < 1e-9 end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- Roda da raiz: luajit tests/test_predicates.lua

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
-- 1. between — inclusividade
-- ================================================================

local s = S.from_table({1, 5, 10, 15, 20}, "int64")

-- both (default): 5 ≤ x ≤ 15
local b_both = s:between(5, 15)
check(b_both._dtype == "bool",        "between → Series<bool>")
check(b_both:get(1) == false,         "between both[1]=1 → false")
check(b_both:get(2) == true,          "between both[2]=5 → true (incl left)")
check(b_both:get(3) == true,          "between both[3]=10 → true")
check(b_both:get(4) == true,          "between both[4]=15 → true (incl right)")
check(b_both:get(5) == false,         "between both[5]=20 → false")

-- neither: 5 < x < 15
local b_neither = s:between(5, 15, "neither")
check(b_neither:get(2) == false,      "between neither[2]=5 → false")
check(b_neither:get(3) == true,       "between neither[3]=10 → true")
check(b_neither:get(4) == false,      "between neither[4]=15 → false")

-- left: 5 ≤ x < 15
local b_left = s:between(5, 15, "left")
check(b_left:get(2) == true,          "between left[2]=5 → true")
check(b_left:get(4) == false,         "between left[4]=15 → false")

-- right: 5 < x ≤ 15
local b_right = s:between(5, 15, "right")
check(b_right:get(2) == false,        "between right[2]=5 → false")
check(b_right:get(4) == true,         "between right[4]=15 → true")

-- null propaga
local sn = S.from_table({1, NA, 10}, "int64")
local bn = sn:between(0, 20)
check(bn:get(2) == nil,               "between null → null")

-- inclusive inválido → erro
local ok_inc = pcall(function() s:between(1, 2, "bad") end)
check(not ok_inc,                     "between inclusive inválido = erro")

-- between em string
local ss = S.from_table({"apple", "mango", "zebra"}, "string")
local bs = ss:between("b", "n")
check(bs:get(1) == false,             "between string apple → false")
check(bs:get(2) == true,              "between string mango → true")
check(bs:get(3) == false,             "between string zebra → false")

-- ================================================================
-- 2. isin
-- ================================================================

local m = s:isin({5, 20})
check(m._dtype == "bool",             "isin → Series<bool>")
check(m:get(1) == false,              "isin[1]=1 não está")
check(m:get(2) == true,               "isin[2]=5 está")
check(m:get(5) == true,               "isin[5]=20 está")

-- null → null
local mn = sn:isin({1, 10})
check(mn:get(2) == nil,               "isin null → null")

-- isin com strings
local mi = ss:isin({"apple", "zebra"})
check(mi:get(1) == true,              "isin string apple → true")
check(mi:get(2) == false,             "isin string mango → false")
check(mi:get(3) == true,              "isin string zebra → true")

-- isin vazio → tudo false
local me = s:isin({})
check(me:get(1) == false and me:get(3) == false, "isin vazio → tudo false")

-- não-tabela → erro
local ok_isin = pcall(function() s:isin(5) end)
check(not ok_isin,                    "isin não-tabela = erro")

-- ================================================================
-- 3. is_unique
-- ================================================================

check(S.from_table({1, 2, 3}, "int64"):is_unique() == true,   "is_unique distinto")
check(S.from_table({1, 2, 2}, "int64"):is_unique() == false,  "is_unique com duplicata")
check(S.from_table({}, "int64"):is_unique() == true,          "is_unique vazia = true")
-- nulos ignorados
check(S.from_table({1, NA, 2, NA}, "int64"):is_unique() == true, "is_unique ignora nulls")
check(S.from_table({1, NA, 1}, "int64"):is_unique() == false,    "is_unique dup com null = false")
-- string
check(S.from_table({"a", "b", "a"}, "string"):is_unique() == false, "is_unique string dup")

-- ================================================================
-- 4. is_monotonic_increasing / decreasing
-- ================================================================

-- não-decrescente (default)
check(S.from_table({1, 2, 2, 3}, "int64"):is_monotonic_increasing() == true,
      "mono inc não-estrito (com igual)")
-- estritamente crescente
check(S.from_table({1, 2, 2, 3}, "int64"):is_monotonic_increasing(true) == false,
      "mono inc estrito rejeita igual")
check(S.from_table({1, 2, 3, 4}, "int64"):is_monotonic_increasing(true) == true,
      "mono inc estrito ok")

-- decrescente
check(S.from_table({3, 2, 1}, "int64"):is_monotonic_decreasing() == true,
      "mono dec")
check(S.from_table({3, 2, 2, 1}, "int64"):is_monotonic_decreasing(true) == false,
      "mono dec estrito rejeita igual")

-- não-monotônica
check(S.from_table({1, 3, 2}, "int64"):is_monotonic_increasing() == false,
      "mono inc rejeita não-ordenada")

-- null quebra
check(S.from_table({1, NA, 3}, "int64"):is_monotonic_increasing() == false,
      "mono com null = false")

-- vazia / 1 elemento = true (vacuamente)
check(S.from_table({}, "int64"):is_monotonic_increasing() == true,  "mono vazia = true")
check(S.from_table({5}, "int64"):is_monotonic_increasing() == true, "mono single = true")

-- string lexicográfica
check(S.from_table({"a", "b", "c"}, "string"):is_monotonic_increasing() == true,
      "mono inc string")

-- ================================================================
-- 5. equals (Series)
-- ================================================================

local a1 = S.from_table({1, 2, NA}, "int64")
local a2 = S.from_table({1, 2, NA}, "int64")
local a3 = S.from_table({1, 2, 3}, "int64")

check(a1:equals(a2) == true,          "equals idênticas (com null)")
check(a1:equals(a3) == false,         "equals difere (null vs 3)")

-- dtype diferente
local af = S.from_table({1, 2, 3}, "float64")
check(a3:equals(af) == false,         "equals dtype diferente = false")

-- tamanho diferente
check(a3:equals(S.from_table({1, 2}, "int64")) == false, "equals tamanho diferente")

-- não-Series
check(a1:equals(42) == false,         "equals não-Series = false")

-- NaN estrutural: NaN == NaN aqui
local nan1 = S.from_table({0/0, 1}, "float64")
local nan2 = S.from_table({0/0, 1}, "float64")
check(nan1:equals(nan2) == true,      "equals NaN estrutural (NaN==NaN)")

-- ================================================================
-- 6. compare (Series)
-- ================================================================

local cmp = a1:compare(a3)
check(cmp:nrows() == 1,               "compare: 1 diferença")
check(cmp:column("i"):get(1) == 3,    "compare i = 3")
check(cmp:column("self"):get(1) == nil,  "compare self = null")
check(cmp:column("other"):get(1) == 3,   "compare other = 3")

-- idênticas → vazio
check(a1:compare(a2):nrows() == 0,    "compare idênticas = vazio")

-- dtype incompatível → erro
local ok_cmp = pcall(function() a3:compare(af) end)
check(not ok_cmp,                     "compare dtype diferente = erro")

-- ================================================================
-- 7. idxmin / idxmax (aliases de argmin/argmax)
-- ================================================================

local v = S.from_table({3, 1, 4, 1, 5}, "int64")
check(v:idxmin() == 2,                "idxmin = 2 (primeiro mínimo)")
check(v:idxmax() == 5,                "idxmax = 5")
check(v:idxmin() == v:argmin(),       "idxmin == argmin")
check(v:idxmax() == v:argmax(),       "idxmax == argmax")

-- ================================================================
-- 8. first_valid_index / last_valid_index
-- ================================================================

local fv = S.from_table({NA, NA, 7, NA, 9, NA}, "int64")
check(fv:first_valid_index() == 3,    "first_valid = 3")
check(fv:last_valid_index() == 5,     "last_valid = 5")

-- toda nula → nil
local allnull = S.from_table({NA, NA}, "int64")
check(allnull:first_valid_index() == nil, "first_valid toda nula = nil")
check(allnull:last_valid_index() == nil,  "last_valid toda nula = nil")

-- sem nulos
local nonull = S.from_table({1, 2, 3}, "int64")
check(nonull:first_valid_index() == 1, "first_valid sem null = 1")
check(nonull:last_valid_index() == 3,  "last_valid sem null = 3")

-- ================================================================
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
-- Duplicatas (de test_duplicates.lua)
-- =====================================================================


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

-- ===================================================================
-- Degrau família (10.6): combine_first recusa int64 > 2^53.
-- ===================================================================
do
    local ffi = require("ffi")
    local BIG = ffi.new("int64_t", 9007199254740993LL)
    local a = S.new("int64", 1, "a"); a:set_null(1)
    local b = S.new("int64", 1, "b"); b:set(1, BIG)
    check(not pcall(function() return a:combine_first(b) end), "degrau: combine_first i64>2^53 recusa")
    local a2 = S.new("int64", 1, "a"); a2:set_null(1)
    local b2 = S.from_table({42}, "int64")
    check(a2:combine_first(b2):get(1) == 42, "degrau: combine_first i64<=2^53 intacto")
end


print(string.format("OK — %d checks passaram (Series: predicados, duplicatas, searchsorted, rep_each)", n_ok))
