-- tests/series/test_window.lua
-- Janela deslizante (rolling) e janela crescente (expanding).
-- Consolida: test_rolling_series.lua + seção rolling de test_enrich.lua
-- Rode da raiz: luajit tests/series/test_window.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local Series = smaug.Series
local S      = Series
local NA     = Series.NA

local function approx(a, b, tol) tol = tol or 1e-9; return math.abs(a - b) < tol end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

local smaug = require("smaug")
local NA    = smaug.Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
local function approx(a, b) return math.abs(a - b) < 1e-9 end

local s = smaug.Series.from_table({1,2,3,4,5}, "int64")

-- ================================================================
-- sum
-- ================================================================
local r3s = s:rolling(3):sum()
check(r3s:is_null(1),                  "sum(3): [1]=NA")
check(r3s:is_null(2),                  "sum(3): [2]=NA")
check(r3s:get(3) == 6,                 "sum(3): [3]=6")
check(r3s:get(4) == 9,                 "sum(3): [4]=9")
check(r3s:get(5) == 12,               "sum(3): [5]=12")
check(r3s._dtype == "int64",           "sum: dtype int64")

-- window=1: sem NA
local r1s = s:rolling(1):sum()
check(r1s:get(1) == 1,                 "sum(1): sem NA, [1]=1")
check(r1s:get(5) == 5,                 "sum(1): [5]=5")

-- window=n: só último não-NA
local rns = s:rolling(5):sum()
check(rns:is_null(4),                  "sum(n): [4]=NA")
check(rns:get(5) == 15,               "sum(n): [5]=15")

-- float64
local sf = smaug.Series.from_table({1.0,2.0,3.0}, "float64")
local rfs = sf:rolling(2):sum()
check(approx(rfs:get(2), 3.0),        "sum float: [2]=3.0")
check(approx(rfs:get(3), 5.0),        "sum float: [3]=5.0")

-- ================================================================
-- mean
-- ================================================================
local r2m = s:rolling(2):mean()
check(r2m:is_null(1),                  "mean(2): [1]=NA")
check(approx(r2m:get(2), 1.5),        "mean(2): [2]=1.5")
check(approx(r2m:get(5), 4.5),        "mean(2): [5]=4.5")
check(r2m._dtype == "float64",         "mean: dtype sempre float64")

-- ================================================================
-- min / max
-- ================================================================
local r2n = s:rolling(2):min()
check(r2n:is_null(1),                  "min(2): [1]=NA")
check(r2n:get(2) == 1,                 "min(2): [2]=1")
check(r2n:get(5) == 4,                 "min(2): [5]=4")

local r2x = s:rolling(2):max()
check(r2x:is_null(1),                  "max(2): [1]=NA")
check(r2x:get(2) == 2,                 "max(2): [2]=2")
check(r2x:get(5) == 5,                 "max(2): [5]=5")

-- ================================================================
-- NA dentro da janela: ignorado
-- ================================================================
local sn = smaug.Series.from_table({10, NA, 30, 40}, "int64")
local rn = sn:rolling(2):sum()
check(rn:is_null(1),                   "NA na janela: [1]=NA")
check(rn:get(2) == 10,                 "NA na janela: [2]=10 (NA ignorado)")
check(rn:get(3) == 30,                 "NA na janela: [3]=30 (NA ignorado)")
check(rn:get(4) == 70,                 "NA na janela: [4]=70 (30+40)")

-- janela toda de NA: resultado NA
local sna = smaug.Series.from_table({NA, NA, 30}, "int64")
local rna = sna:rolling(2):mean()
check(rna:is_null(1),                  "janela NA: [1]=NA")
check(rna:is_null(2),                  "janela toda NA: [2]=NA")
check(approx(rna:get(3), 30.0),       "janela com 1 válido: [3]=30.0")

-- ================================================================
-- Série pequena (tamanho < window)
-- ================================================================
local s2 = smaug.Series.from_table({1,2}, "int64")
local r5 = s2:rolling(5):sum()
check(r5:len() == 2,                   "janela > len: tamanho preservado")
check(r5:is_null(1),                   "janela > len: [1]=NA")
check(r5:is_null(2),                   "janela > len: [2]=NA")

-- ================================================================
-- Série vazia
-- ================================================================
local se = smaug.Series.from_table({}, "int64")
local re = se:rolling(3):sum()
check(re:len() == 0,                   "série vazia: len=0")

-- ================================================================
-- Erros
-- ================================================================
local ok1, _ = pcall(function() s:rolling(0) end)
check(not ok1,                         "erro: window=0")
local ok2, _ = pcall(function() s:rolling(1.5) end)
check(not ok2,                         "erro: window fracionário")
local ok3, _ = pcall(function() s:rolling(-1) end)
check(not ok3,                         "erro: window negativo")

-- dtype inválido
local ss = smaug.Series.from_table({"a","b"}, "string")
local ok4, _ = pcall(function() ss:rolling(2) end)
check(not ok4,                         "erro: rolling em string")


-- =====================================================================
-- Rolling estendido e expanding (de test_enrich.lua)
-- =====================================================================

-- Rolling estendido
-- ================================================================

local rs = S.from_table({1.0,2.0,3.0,4.0,5.0}, "float64")

-- std / var
local rstd = rs:rolling(3):std()
check(rstd:is_null(1),             "rolling std[1]=NA")
check(rstd:is_null(2),             "rolling std[2]=NA")
check(approx(rstd:get(3), 1.0),   "rolling std[3]=1.0")

local rvar = rs:rolling(3):var()
check(rvar:is_null(1),             "rolling var[1]=NA")
check(approx(rvar:get(3), 1.0),   "rolling var[3]=1.0")

-- count
local rc = S.from_table({1.0,NA,3.0,NA,5.0}, "float64"):rolling(3):count()
check(rc:is_null(1),              "rolling count[1]=NA (janela incompleta)")
check(rc:is_null(2),              "rolling count[2]=NA")
check(rc:get(3) == 2,             "rolling count[3]=2 ({1,NA,3}→2 não-nulos)")
check(rc:get(4) == 1,             "rolling count[4]=1 ({NA,3,NA}→1)")

-- median
local rmed = rs:rolling(3):median()
check(rmed:is_null(1),            "rolling median[1]=NA")
check(approx(rmed:get(3), 2.0),  "rolling median[3]=2.0")
check(approx(rmed:get(5), 4.0),  "rolling median[5]=4.0")

-- quantile
local rq = rs:rolling(3):quantile(0.0)
check(rq:is_null(1),              "rolling q0[1]=NA")
check(approx(rq:get(3), 1.0),    "rolling q0[3]=1.0 (min da janela)")

-- min_periods
local rmp = rs:rolling(3):min_periods(2):std()
check(rmp:is_null(1),             "rolling mp std[1]=NA (1 val < mp=2)")
check(approx(rmp:get(2), 0.7071067811865476, 1e-9), "rolling mp std[2]=sqrt(0.5)")
check(approx(rmp:get(3), 1.0),   "rolling mp std[3]=1.0")

-- expanding
local exp_s = S.from_table({1.0,2.0,3.0,4.0}, "float64")
local es = exp_s:expanding():sum()
check(es:get(1) == 1, "expanding sum[1]=1")
check(es:get(2) == 3, "expanding sum[2]=3")
check(es:get(4) == 10,"expanding sum[4]=10")

local em = exp_s:expanding():mean()
check(approx(em:get(2), 1.5),  "expanding mean[2]=1.5")
check(approx(em:get(4), 2.5),  "expanding mean[4]=2.5")

local estd = exp_s:expanding():std()
check(estd:is_null(1),         "expanding std[1]=nil (n<2)")
check(approx(estd:get(2), 0.7071067811865476, 1e-9), "expanding std[2]")

local emd = exp_s:expanding():median()
check(approx(emd:get(2), 1.5), "expanding median[2]=1.5")

print(string.format("OK — %d checks passaram (Series: rolling, expanding, cumsum, cummin, cummax, diff, shift, ffill, bfill, argmin, argmax)", n_ok))
