-- tests/series/test_stat.lua
-- Estatísticas (corr/cov/autocorr/dot/pct_change/rank/describe) e transformações
-- (unique, nunique, value_counts, abs, round, clip, cumsum, cumprod, diff, shift).
-- Consolida: test_stats.lua + test_series_ops.lua
-- Rode da raiz: luajit tests/series/test_stat.lua

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

-- Roda da raiz: luajit tests/test_stats.lua

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
    tol = tol or 1e-9
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tol
end
local function is_nan(v) return v ~= v end

-- ================================================================
-- 1. Series:cov — covariância amostral (÷ n-1)
-- ================================================================

-- x={1,2,3,4}, y={1,3,2,5}: cov amostral = 5.5/3 = 1.833...
local x = S.from_table({1, 2, 3, 4}, "float64")
local y = S.from_table({1, 3, 2, 5}, "float64")

check(approx(x:cov(y), 5.5/3),        "cov(x,y) = 1.8333...")
check(approx(x:cov(x), 5.0/3),        "cov(x,x) = var amostral de x = 1.6667")

-- covariância simétrica
check(approx(x:cov(y), y:cov(x)),     "cov simétrica")

-- correlação perfeita positiva
local a = S.from_table({1, 2, 3, 4, 5}, "float64")
local b = S.from_table({2, 4, 6, 8, 10}, "float64")
check(x:cov(x) > 0,                   "cov(x,x) positiva")
check(a:cov(b) > 0,                   "cov positiva em correlação direta")

-- menos de 2 pares válidos → NaN
local one = S.from_table({5}, "float64")
check(is_nan(one:cov(one)),           "cov com 1 elemento = NaN")
local empty = S.from_table({}, "float64")
check(is_nan(empty:cov(empty)),       "cov vazia = NaN")

-- ================================================================
-- 2. Series:corr — Pearson ∈ [-1, 1]
-- ================================================================

-- x={1,2,3,4}, y={1,3,2,5}: corr = 5.5/sqrt(43.75) = 0.8315218406
check(approx(x:corr(y), 0.8315218406, 1e-9), "corr(x,y) = 0.83152")

-- correlação perfeita = 1
check(approx(a:corr(b), 1.0),         "corr perfeita positiva = 1")

-- anti-correlação = -1
local c = S.from_table({5, 4, 3, 2, 1}, "float64")
check(approx(a:corr(c), -1.0),        "corr anti = -1")

-- simétrica
check(approx(x:corr(y), y:corr(x)),   "corr simétrica")

-- diagonal: corr(x,x) = 1
check(approx(a:corr(a), 1.0),         "corr(a,a) = 1")

-- variância zero → NaN (série constante)
local const = S.from_table({7, 7, 7, 7, 7}, "float64")
check(is_nan(const:corr(a)),          "corr com série constante = NaN (var zero)")

-- menos de 2 pares → NaN
check(is_nan(one:corr(one)),          "corr com 1 elemento = NaN")

-- ================================================================
-- 3. corr/cov com nulos — pares incompletos pulados
-- ================================================================

-- x'={1,2,NA,4}, y'={1,3,2,5}: usa pares (1,1),(2,3),(4,5)
local xn = S.from_table({1, 2, NA, 4}, "float64")
local yn = S.from_table({1, 3, 2, 5}, "float64")
-- pares válidos: (1,1),(2,3),(4,5)
-- mx=7/3=2.333 my=3 ; manualmente corr destes 3 pontos
local xv = S.from_table({1, 2, 4}, "float64")
local yv = S.from_table({1, 3, 5}, "float64")
check(approx(xn:corr(yn), xv:corr(yv)), "corr ignora par com null (= corr dos válidos)")
check(approx(xn:cov(yn),  xv:cov(yv)),  "cov ignora par com null")

-- ================================================================
-- 4. Series:autocorr
-- ================================================================

-- série linear perfeita: autocorr(lag=1) entre {2,3,4,5} e {1,2,3,4} = 1
local lin = S.from_table({1, 2, 3, 4, 5}, "float64")
check(approx(lin:autocorr(), 1.0),    "autocorr lag1 série linear = 1")
check(approx(lin:autocorr(1), 1.0),   "autocorr(1) explícito = 1")

-- autocorr = corr(self, shift)
check(approx(lin:autocorr(2), lin:corr(lin:shift(2))), "autocorr(2) = corr(self, shift(2))")

-- ================================================================
-- 5. Series:dot — produto interno; null propaga
-- ================================================================

-- x={1,2,3,4}, y={1,3,2,5}: dot = 1+6+6+20 = 33
check(approx(x:dot(y), 33.0),         "dot(x,y) = 33")
check(approx(x:dot(y), y:dot(x)),     "dot comutativo")

-- null propaga → nil (diferente de cov/corr que pulam)
local xd = S.from_table({1, 2, NA, 4}, "float64")
local yd = S.from_table({1, 3, 2, 5}, "float64")
check(xd:dot(yd) == nil,              "dot com null = nil (propaga)")

-- ================================================================
-- 6. Series:pct_change
-- ================================================================

-- {100,110,99}: [nil, 0.1, -0.1]
local p = S.from_table({100, 110, 99}, "float64")
local pc = p:pct_change()
check(pc._dtype == "float64",         "pct_change dtype = float64")
check(pc:get(1) == nil,               "pct_change[1] = nil (sem predecessor)")
check(approx(pc:get(2), 0.1),         "pct_change[2] = 0.1")
check(approx(pc:get(3), -0.1, 1e-9),  "pct_change[3] = -0.1")

-- periods=2
local p2 = S.from_table({100, 200, 150, 300}, "float64")
local pc2 = p2:pct_change(2)
check(pc2:get(1) == nil,              "pct_change(2)[1] = nil")
check(pc2:get(2) == nil,              "pct_change(2)[2] = nil")
check(approx(pc2:get(3), 0.5),        "pct_change(2)[3] = (150-100)/100 = 0.5")
check(approx(pc2:get(4), 0.5),        "pct_change(2)[4] = (300-200)/200 = 0.5")

-- divisor zero → NA (não Inf)
local pz = S.from_table({50, 0, 25}, "float64")
local pcz = pz:pct_change()
check(pcz:get(2) ~= nil,              "pct_change com prev=50 ok")
check(pcz:get(3) == nil,              "pct_change com prev=0 = nil (não Inf)")

-- null propaga
local pn = S.from_table({10, NA, 30}, "float64")
local pcn = pn:pct_change()
check(pcn:get(2) == nil,              "pct_change[2] com cur null = nil")
check(pcn:get(3) == nil,              "pct_change[3] com prev null = nil")

-- ================================================================
-- 7. int64 — F.1 funciona em séries inteiras
-- ================================================================

local xi = S.from_table({1, 2, 3, 4}, "int64")
local yi = S.from_table({1, 3, 2, 5}, "int64")
check(approx(xi:corr(yi), 0.8315218406, 1e-9), "corr funciona em int64")
check(approx(xi:dot(yi), 33.0),       "dot funciona em int64")

-- ================================================================
-- 8. Guards de dtype — rejeição em tipos não-numéricos
-- ================================================================

local str = S.from_table({"a", "b"}, "string")
local ok_corr = pcall(function() str:corr(str) end)
check(not ok_corr,                    "corr rejeita string")
local ok_dot = pcall(function() str:dot(str) end)
check(not ok_dot,                     "dot rejeita string")
local ok_pct = pcall(function() str:pct_change() end)
check(not ok_pct,                     "pct_change rejeita string")

-- tamanhos diferentes
local ok_size = pcall(function()
    S.from_table({1,2}, "float64"):corr(S.from_table({1,2,3}, "float64"))
end)
check(not ok_size,                    "corr rejeita tamanhos diferentes")

-- argumento não-Series
local ok_arg = pcall(function() x:corr(42) end)
check(not ok_arg,                     "corr rejeita argumento não-Series")

-- ================================================================
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
-- Transformações (de test_series_ops.lua)
-- =====================================================================


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


print(string.format("OK — %d checks passaram (Series: stat, transformações, cumsum/diff/shift)", n_ok))
