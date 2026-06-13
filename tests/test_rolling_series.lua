-- tests/test_rolling_series.lua
-- Teste do Series:rolling (janela deslizante).
-- Rode da raiz:  luajit tests/test_rolling_series.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

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

print(string.format("OK — %d checks passaram (rolling Series)", n_ok))
