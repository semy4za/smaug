-- tests/test_series_ops.lua
-- Teste das novas operações de Series (Anel 2 — completude analítica):
-- unique, nunique, value_counts, abs, round, clip, cumsum, cumprod, diff, shift.
-- Rode da raiz:  luajit tests/test_series_ops.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
local function approx(a, b) return math.abs(a - b) < 1e-9 end

-- ================================================================
-- unique
-- ================================================================
local s = smaug.Series.from_table({3,1,2,1,3,2,NA}, "int64")
local u = s:unique()
check(u:len() == 4,                      "unique: 4 distintos (incl NA)")
check(u:get(1) == 3,                     "unique: 1ª aparição = 3")
check(u:get(2) == 1,                     "unique: 2ª = 1")
check(u:is_null(4),                      "unique: NA incluído")
check(u._dtype == "int64",               "unique: dtype preservado")

-- string
local ss = smaug.Series.from_table({"b","a","b","c"}, "string")
local us = ss:unique()
check(us:len() == 3,                     "unique string: 3 distintos")
check(us:get(1) == "b",                  "unique string: 1ª = b")

-- todos iguais
local sa = smaug.Series.from_table({5,5,5}, "int64")
check(sa:unique():len() == 1,            "unique todos iguais: 1")

-- vazia
local se = smaug.Series.from_table({}, "int64")
check(se:unique():len() == 0,            "unique vazia: 0")

-- ================================================================
-- nunique
-- ================================================================
check(s:nunique() == 3,                  "nunique: 3 (NA excluído)")
check(ss:nunique() == 3,                 "nunique string: 3")
check(se:nunique() == 0,                 "nunique vazia: 0")

local sn = smaug.Series.from_table({NA,NA}, "int64")
check(sn:nunique() == 0,                 "nunique só NA: 0")

-- ================================================================
-- value_counts
-- ================================================================
local sc = smaug.Series.from_table({1,2,1,3,1,2}, "int64")
local vc = sc:value_counts()
check(vc:nrows() == 3,                   "value_counts: 3 linhas")
check(vc:col("value"):get(1) == 1,       "value_counts: 1 mais frequente")
check(vc:col("count"):get(1) == 3,       "value_counts: count(1) = 3")
check(vc:col("count"):get(2) == 2,       "value_counts: count(2) = 2")
check(vc:col("count"):get(3) == 1,       "value_counts: count(3) = 1")
check(vc:col("count")._dtype == "int64", "value_counts: count dtype int64")
-- NA excluído
local sc2 = smaug.Series.from_table({1,NA,1}, "int64")
local vc2 = sc2:value_counts()
check(vc2:nrows() == 1,                  "value_counts: NA excluído")

-- ================================================================
-- abs
-- ================================================================
local fa = smaug.Series.from_table({-3.0, 1.5, -2.7, NA}, "float64")
local ab = fa:abs()
check(approx(ab:get(1), 3.0),            "abs: -3 -> 3")
check(approx(ab:get(2), 1.5),            "abs: 1.5 -> 1.5")
check(approx(ab:get(3), 2.7),            "abs: -2.7 -> 2.7")
check(ab:is_null(4),                     "abs: NA propaga")

local ia = smaug.Series.from_table({-5, 3, -1}, "int64")
local iab = ia:abs()
check(iab:get(1) == 5,                   "abs int64: -5 -> 5")
check(iab:get(3) == 1,                   "abs int64: -1 -> 1")

-- erro dtype
local ok1, _ = pcall(function() smaug.Series.from_table({"a"},"string"):abs() end)
check(not ok1,                           "abs: erro em string")

-- ================================================================
-- round
-- ================================================================
local fr = smaug.Series.from_table({1.456, -2.345, NA}, "float64")
local r0 = fr:round()
check(approx(r0:get(1), 1.0),            "round(0): 1.456 -> 1")
check(approx(r0:get(2), -2.0),           "round(0): -2.345 -> -2")
check(r0:is_null(3),                     "round: NA propaga")

local r2 = fr:round(2)
check(approx(r2:get(1), 1.46),           "round(2): 1.456 -> 1.46")
check(approx(r2:get(2), -2.35),          "round(2): -2.345 -> -2.35 (half-away-from-zero)")
check(r2._dtype == "float64",            "round: dtype float64")

-- ================================================================
-- clip
-- ================================================================
local fc = smaug.Series.from_table({-5.0, 1.0, 3.0, 8.0, NA}, "float64")
local cl = fc:clip(0, 5)
check(approx(cl:get(1), 0.0),            "clip: -5 -> 0 (lo)")
check(approx(cl:get(2), 1.0),            "clip: 1 -> 1 (dentro)")
check(approx(cl:get(4), 5.0),            "clip: 8 -> 5 (hi)")
check(cl:is_null(5),                     "clip: NA propaga")

local cl_lo = fc:clip(0, nil)
check(approx(cl_lo:get(1), 0.0),         "clip só lo: -5 -> 0")
check(approx(cl_lo:get(4), 8.0),         "clip só lo: 8 intacto")

local cl_hi = fc:clip(nil, 5)
check(approx(cl_hi:get(1), -5.0),        "clip só hi: -5 intacto")
check(approx(cl_hi:get(4), 5.0),         "clip só hi: 8 -> 5")

-- ================================================================
-- cumsum
-- ================================================================
local ft = smaug.Series.from_table({1,2,3,4,5}, "int64")
local cs = ft:cumsum()
check(cs:get(1) == 1,                    "cumsum: [1]=1")
check(cs:get(3) == 6,                    "cumsum: [3]=6")
check(cs:get(5) == 15,                   "cumsum: [5]=15")

-- NA propaga
local fn = smaug.Series.from_table({1,NA,3,4}, "int64")
local csn = fn:cumsum()
check(csn:get(1) == 1,                   "cumsum NA: [1]=1")
check(csn:is_null(2),                    "cumsum NA: [2]=NA")
check(csn:is_null(3),                    "cumsum NA: [3]=NA (propagado)")
check(csn:is_null(4),                    "cumsum NA: [4]=NA (propagado)")

-- float64
local ff = smaug.Series.from_table({0.5, 1.5, 2.0}, "float64")
local csf = ff:cumsum()
check(approx(csf:get(2), 2.0),           "cumsum float: [2]=2.0")
check(approx(csf:get(3), 4.0),           "cumsum float: [3]=4.0")

-- ================================================================
-- cumprod
-- ================================================================
local cp = ft:cumprod()
check(cp:get(1) == 1,                    "cumprod: [1]=1")
check(cp:get(3) == 6,                    "cumprod: [3]=6")
check(cp:get(5) == 120,                  "cumprod: [5]=120")
check(fn:cumprod():is_null(2),           "cumprod NA: propaga")

-- ================================================================
-- diff
-- ================================================================
local fd = smaug.Series.from_table({1,3,6,10,15}, "int64")
local d1 = fd:diff()
check(d1:is_null(1),                     "diff(1): [1]=NA")
check(d1:get(2) == 2,                    "diff(1): [2]=2")
check(d1:get(5) == 5,                    "diff(1): [5]=5")

local d2 = fd:diff(2)
check(d2:is_null(1),                     "diff(2): [1]=NA")
check(d2:is_null(2),                     "diff(2): [2]=NA")
check(d2:get(3) == 5,                    "diff(2): [3]=5")
check(d2:get(5) == 9,                    "diff(2): [5]=9")

-- NA
check(fn:diff():is_null(1),              "diff com NA: [1]=NA")
check(fn:diff():is_null(2),              "diff com NA: [2]=NA")

-- erro periods < 1
local ok2, _ = pcall(function() ft:diff(0) end)
check(not ok2,                           "diff: periods=0 recusado")

-- ================================================================
-- shift
-- ================================================================
local fs = smaug.Series.from_table({1,2,3,4,5}, "int64")
local sh2 = fs:shift(2)
check(sh2:is_null(1),                    "shift(2): [1]=NA")
check(sh2:is_null(2),                    "shift(2): [2]=NA")
check(sh2:get(3) == 1,                   "shift(2): [3]=1")
check(sh2:get(5) == 3,                   "shift(2): [5]=3")

local shm1 = fs:shift(-1)
check(shm1:get(1) == 2,                  "shift(-1): [1]=2")
check(shm1:get(4) == 5,                  "shift(-1): [4]=5")
check(shm1:is_null(5),                   "shift(-1): [5]=NA")

-- shift(0) = clone
local sh0 = fs:shift(0)
check(sh0:get(1) == 1,                   "shift(0): [1]=1 (clone)")
check(sh0:get(5) == 5,                   "shift(0): [5]=5")

print(string.format("OK — %d checks passaram (series_ops)", n_ok))
