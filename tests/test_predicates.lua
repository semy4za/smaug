-- tests/test_predicates.lua
-- Bloco F.2 — pacote de predicados.
--   Series: between, isin, is_unique, is_monotonic_increasing/decreasing,
--           equals, compare, idxmin/idxmax, first_valid_index/last_valid_index
--   DataSet: equals, compare
--
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

print(string.format(
    "OK — %d checks passaram (F.2 predicados: between/isin/is_unique/" ..
    "is_monotonic_*/equals/compare/idxmin/idxmax/first_last_valid_index " ..
    "+ DataSet equals/compare)",
    n_ok))
