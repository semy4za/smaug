-- tests/props/test_integration.lua
-- Fluxos completos integrando Series + DataSet com dados reais e cenários
-- de ponta a ponta. Absorve: reduções avançadas de test_enrich.lua (prod,
-- median, quantile, mode, rank, skew, kurtosis, mad, sem, nlargest, funções matemáticas).
-- Rode da raiz: luajit tests/props/test_integration.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local S     = smaug.Series
local NA    = smaug.Series.NA

local function approx(a, b, tol) tol = tol or 1e-9; return math.abs(a - b) < tol end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- ================================================================
-- Series — reduções novas
-- ================================================================

local s = S.from_table({3,1,4,1,5,9,2,6}, "float64")
local si = S.from_table({3,1,4,1,5,9,2,6}, "int64")

-- prod
check(s:prod() == 6480,      "prod: 3*1*4*1*5*9*2*6=6480")
check(si:prod() == 6480,     "prod i64: 6480")
local sna = S.from_table({2, NA, 3}, "float64")
check(sna:prod() == 6,       "prod ignore_na: 2*3=6")
check(sna:prod(false) == nil,"prod !ignore_na com NA: nil")

-- median
check(s:median() == 3.5,     "median: (3+4)/2=3.5")
check(S.from_table({5}, "float64"):median() == 5, "median 1 elem: 5")
check(sna:median() == 2.5,   "median ignore_na: (2+3)/2=2.5")

-- quantile
check(approx(s:quantile(0.0), 1),   "q0=min=1")
check(approx(s:quantile(1.0), 9),   "q1=max=9")
check(approx(s:quantile(0.5), 3.5), "q0.5=median=3.5")
check(approx(s:quantile(0.25), 1.75),"q0.25=1.75")

-- mode
check(S.from_table({1,2,1,3}, "int64"):mode() == 1, "mode: 1")
check(S.from_table({5,5,5},   "float64"):mode() == 5,"mode único: 5")

-- ffill
local sf = S.from_table({1.0, NA, NA, 4.0, NA}, "float64")
local ff = sf:ffill()
check(ff:get(1) == 1.0,   "ffill[1]=1.0")
check(ff:get(2) == 1.0,   "ffill[2]=1.0 (propagado)")
check(ff:get(3) == 1.0,   "ffill[3]=1.0")
check(ff:get(4) == 4.0,   "ffill[4]=4.0")
check(ff:get(5) == 4.0,   "ffill[5]=4.0")
-- NA no início: permanece NA
local sf2 = S.from_table({NA, NA, 3.0}, "float64")
local ff2 = sf2:ffill()
check(ff2:is_null(1),     "ffill NA início[1]=NA")
check(ff2:is_null(2),     "ffill NA início[2]=NA")
check(ff2:get(3) == 3.0,  "ffill[3]=3.0")

-- bfill
local bf = sf:bfill()
check(bf:get(1) == 1.0,   "bfill[1]=1.0")
check(bf:get(2) == 4.0,   "bfill[2]=4.0 (propagado para trás)")
check(bf:get(5) == nil,   "bfill[5]=NA (sem próximo)")

-- cummin
local cm = s:cummin()
check(cm:get(1) == 3,     "cummin[1]=3")
check(cm:get(2) == 1,     "cummin[2]=1")
check(cm:get(8) == 1,     "cummin[8]=1")
-- NA propaga
local scm = S.from_table({5.0, NA, 2.0}, "float64")
check(scm:cummin():is_null(2),   "cummin NA propaga[2]")
check(scm:cummin():get(3) == 2.0,"cummin após NA[3]=2.0")

-- cummax
local cx = s:cummax()
check(cx:get(1) == 3,     "cummax[1]=3")
check(cx:get(3) == 4,     "cummax[3]=4")
check(cx:get(6) == 9,     "cummax[6]=9")
check(cx:get(8) == 9,     "cummax[8]=9")

-- argmin / argmax
check(s:argmin() == 2,    "argmin: idx=2 (val=1)")
check(s:argmax() == 6,    "argmax: idx=6 (val=9)")
check(S.from_table({NA,NA}, "float64"):argmin() == nil, "argmin all NA: nil")

-- rank
local r = S.from_table({3,1,4,1,5}, "float64"):rank()
check(approx(r:get(1), 3.0), "rank[1]=3")
check(approx(r:get(2), 1.5), "rank[2]=1.5 (empate avg)")
check(approx(r:get(4), 1.5), "rank[4]=1.5")
check(approx(r:get(5), 5.0), "rank[5]=5")
-- rank com NA → NA
local rna = S.from_table({3.0, NA, 1.0}, "float64"):rank()
check(rna:is_null(2),         "rank NA → NA")
check(approx(rna:get(1), 2), "rank[1]=2")

-- pct_rank
local pr = S.from_table({1.0,2.0,3.0,4.0}, "float64"):pct_rank()
check(approx(pr:get(1), 0.25), "pct_rank[1]=0.25")
check(approx(pr:get(4), 1.0),  "pct_rank[4]=1.0")

-- skew / kurtosis / mad / sem
local sg = S.from_table({2,4,4,4,5,5,7,9}, "float64")
check(approx(sg:mad(), 0.5, 1e-9), "mad: 0.5")
check(sg:sem() ~= nil,              "sem: não nil")
check(sg:skew() ~= nil,             "skew: não nil")
check(sg:kurtosis() ~= nil,         "kurtosis: não nil")
-- série pequena demais
check(S.from_table({1.0,2.0}, "float64"):skew() == nil, "skew n<3: nil")
check(S.from_table({1.0,2.0,3.0}, "float64"):kurtosis() == nil, "kurtosis n<4: nil")

-- nlargest / nsmallest
local nl = s:nlargest(3)
check(nl:len() == 3,   "nlargest len=3")
check(nl:get(1) == 9,  "nlargest[1]=9")
check(nl:get(2) == 6,  "nlargest[2]=6")
check(nl:get(3) == 5,  "nlargest[3]=5")
local ns = s:nsmallest(3)
check(ns:get(1) == 1,  "nsmallest[1]=1")
check(ns:get(3) == 2,  "nsmallest[3]=2")

-- sin / cos / exp / log / sqrt
local sm = S.from_table({0.0, math.pi/2}, "float64")
check(approx(sm:sin():get(1), 0.0),   "sin(0)=0")
check(approx(sm:sin():get(2), 1.0),   "sin(π/2)=1")
check(approx(sm:cos():get(1), 1.0),   "cos(0)=1")
local se = S.from_table({0.0, 1.0}, "float64")
check(approx(se:exp():get(1), 1.0),   "exp(0)=1")
check(approx(se:exp():get(2), math.exp(1)), "exp(1)=e")
check(approx(se:log():get(2), 0.0),   "log(1)=0")
local sq = S.from_table({4.0, 9.0}, "float64")
check(sq:sqrt():get(1) == 2.0,        "sqrt(4)=2")
check(sq:sqrt():get(2) == 3.0,        "sqrt(9)=3")
-- nulos propagam
local smath = S.from_table({4.0, NA}, "float64")
check(smath:sqrt():get(1) == 2.0,     "sqrt propaga não-nulo")
check(smath:sqrt():is_null(2),         "sqrt propaga NA")

print(string.format("OK — %d checks passaram (integração: reduções avançadas, rank, skew, kurtosis, mad, sem, funções matemáticas)", n_ok))
