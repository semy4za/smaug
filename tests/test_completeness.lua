-- tests/test_completeness.lua
-- Testes de completude: métodos adicionados em datetime e categorical
-- para fechar os 17 ⚠️ do Eixo 1 do PARITY_REPORT.
--
-- datetime (7): argmin, argmax, cummin, cummax, diff, median, quantile
-- categorical (10): isna, notna, min, max, ffill, bfill, shift, map, where, mask
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

print(string.format(
    "OK — %d checks passaram (completude: datetime argmin/argmax/cummin/cummax/" ..
    "diff/median/quantile + categorical isna/notna/min/max/ffill/bfill/shift/map/where/mask)",
    n_ok))
