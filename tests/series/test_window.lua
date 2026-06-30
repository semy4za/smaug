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

-- item 8a: min_periods aplicado a sum/min/max (REGRESSÃO do bug histórico —
-- o caminho C ignorava min_periods; agora respeita). rs = {1,2,3,4,5}
local bsum = rs:rolling(3):min_periods(1):sum()
check(approx(bsum:get(1), 1.0),  "8a sum mp1[1]=1 (parcial; ANTES era NA)")
check(approx(bsum:get(2), 3.0),  "8a sum mp1[2]=3 (parcial)")
check(approx(bsum:get(3), 6.0),  "8a sum mp1[3]=6 (janela cheia)")
local bsum2 = rs:rolling(3):min_periods(2):sum()
check(bsum2:is_null(1),          "8a sum mp2[1]=NA (1 val < mp=2)")
check(approx(bsum2:get(2), 3.0), "8a sum mp2[2]=3")
-- min/max com min_periods → rescan type-preserving
local bmin = rs:rolling(3):min_periods(1):min()
check(approx(bmin:get(1), 1.0),  "8a min mp1[1]=1 (rescan parcial)")
check(approx(bmin:get(5), 3.0),  "8a min mp1[5]=3 ({3,4,5})")
local bmax = rs:rolling(3):min_periods(1):max()
check(approx(bmax:get(1), 1.0),  "8a max mp1[1]=1")
check(approx(bmax:get(2), 2.0),  "8a max mp1[2]=2 (parcial {1,2})")
-- mean com min_periods (caminho motor)
local bmean = rs:rolling(3):min_periods(1):mean()
check(approx(bmean:get(1), 1.0), "8a mean mp1[1]=1")
check(approx(bmean:get(2), 1.5), "8a mean mp1[2]=1.5")
-- i64 min_periods preserva tipo no rescan
local bi = S.from_table({10,20,30,40}, "int64"):rolling(2):min_periods(1):max()
check(bi:get(1) == 10,           "8a i64 max mp1[1]=10")
check(bi:get(4) == 40,           "8a i64 max mp1[4]=40")
-- default (min_periods=0) inalterado: janela-cheia
local bdef = rs:rolling(3):sum()
check(bdef:is_null(1) and bdef:is_null(2), "8a sum default[1,2]=NA (janela-cheia preservada)")
check(approx(bdef:get(3), 6.0),  "8a sum default[3]=6")

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

-- item 8b: expanding delega a rolling(n, min_periods>=1). Tipos coerentes
-- com rolling: sum→dtype, mean/std/var→float64, count→int64 (correção: o
-- expanding antigo retornava col._dtype p/ tudo, truncando mean de i64).
local exp_i = S.from_table({10,20,30}, "int64")
check(exp_i:expanding():sum():dtype()   == "int64",   "8b expanding sum i64→int64")
check(exp_i:expanding():mean():dtype()  == "float64", "8b expanding mean i64→float64 (corrigido)")
check(exp_i:expanding():count():dtype() == "int64",   "8b expanding count→int64")
check(exp_i:expanding():std():dtype()   == "float64", "8b expanding std→float64")
check(approx(exp_i:expanding():mean():get(2), 15.0),  "8b expanding mean i64 não trunca (10,20→15)")
-- expanding com min_periods explícito
local emp = exp_s:expanding(2):sum()
check(emp:is_null(1),          "8b expanding(mp=2) sum[1]=NA")
check(approx(emp:get(2), 3.0), "8b expanding(mp=2) sum[2]=3")
-- expanding count acumula não-nulos
local ecn = S.from_table({1.0, NA, 3.0}, "float64"):expanding():count()
check(ecn:get(1) == 1 and ecn:get(2) == 1 and ecn:get(3) == 2, "8b expanding count acumula não-nulos")

-- ===================================================================
-- ffill/bfill agnósticos a tipo (item 7.1): bool, string, datetime
-- delegam ao C; antes só numéricos tinham C, o resto era fallback Lua.
-- ===================================================================

-- bool
local sb  = S.from_table({true, NA, NA, false, NA}, "bool")
local sbf = sb:ffill()
check(sbf:get(1) == true  and sbf:get(3) == true,  "bool ffill: carry true")
check(sbf:get(4) == false and sbf:get(5) == false, "bool ffill: carry false")
local sbb = sb:bfill()
check(sbb:get(2) == false and sbb:get(1) == true,  "bool bfill: carry")
check(sbb:is_null(5),                              "bool bfill: borda final NA")

-- string (com vazia válida e multibyte)
local ss  = S.from_table({"a", NA, "", NA, "héllo"}, "string")
local ssf = ss:ffill()
check(ssf:get(2) == "a",      "str ffill: [2]=a (carry)")
check(ssf:get(3) == "",       "str ffill: [3]= (vazia válida)")
check(ssf:get(4) == "",       "str ffill: [4]= (carry vazia)")
check(ssf:get(5) == "héllo",  "str ffill: [5]=héllo (multibyte)")
local ssb = ss:bfill()
check(ssb:get(1) == "a",      "str bfill: [1]=a")
check(ssb:get(2) == "",       "str bfill: [2]= (carry vazia seguinte)")
check(ssb:get(4) == "héllo",  "str bfill: [4]=héllo")
-- bordas sem fonte permanecem NA
local ss2 = S.from_table({NA, "x", NA}, "string")
check(ss2:ffill():is_null(1), "str ffill: borda inicial NA")
check(ss2:bfill():is_null(3), "str bfill: borda final NA")

-- datetime
local sd  = S.from_table({"2020-01-01", NA, NA, "2020-06-15"}, "datetime")
local sdf = sd:ffill()
check(sdf:count_nonnull() == 4,        "dt ffill: preenche 4")
check(sdf:get(2) == sdf:get(1),        "dt ffill: [2] carrega [1]")
local sdb = sd:bfill()
check(sdb:get(3) == sdb:get(4),        "dt bfill: [3] carrega [4]")

-- série toda nula permanece toda nula
local sn = S.from_table({NA, NA, NA}, "string")
check(sn:ffill():count_nonnull() == 0, "str ffill all-null: 0 válidos")
check(sn:bfill():count_nonnull() == 0, "str bfill all-null: 0 válidos")

-- ===================================================================
-- shift com sinal (item 7.1b): negativo agora vem do C (antes era Lua,
-- e sem cobertura em lugar nenhum). Testa os dois sentidos em todos os dtypes.
-- ===================================================================

-- f64 positivo e negativo
local nf = S.from_table({1.0, 2.0, 3.0, 4.0}, "float64")
local nfp = nf:shift(1)   -- [NA,1,2,3]
check(nfp:is_null(1) and nfp:get(2) == 1 and nfp:get(4) == 3, "f64 shift(1)")
local nfn = nf:shift(-1)  -- [2,3,4,NA]
check(nfn:get(1) == 2 and nfn:get(3) == 4 and nfn:is_null(4), "f64 shift(-1)")
check(nf:shift(0):get(1) == 1 and nf:shift(0):get(4) == 4,    "f64 shift(0)=clone")
check(nf:shift(10):count_nonnull() == 0,                      "f64 shift(>=size)=all-NA")
check(nf:shift(-10):count_nonnull() == 0,                     "f64 shift(<=-size)=all-NA")

-- f64 com NA preservado no deslocamento
local nfna = S.from_table({1.0, NA, 3.0}, "float64")
check(nfna:shift(-1):is_null(1) and nfna:shift(-1):get(2) == 3, "f64 shift(-1) preserva NA")

-- i64 negativo
local ni = S.from_table({10, 20, 30}, "int64")
check(ni:shift(-1):get(1) == 20 and ni:shift(-1):is_null(3), "i64 shift(-1)")

-- string negativo (offset-based)
local nss = S.from_table({"a", "b", "c", "d"}, "string")
local nssn = nss:shift(-2)  -- [c,d,NA,NA]
check(nssn:get(1) == "c" and nssn:get(2) == "d", "str shift(-2): valores")
check(nssn:is_null(3) and nssn:is_null(4),       "str shift(-2): bordas NA")
local nssp = nss:shift(2)   -- [NA,NA,a,b]
check(nssp:is_null(1) and nssp:get(3) == "a" and nssp:get(4) == "b", "str shift(2)")

-- bool negativo
local nb = S.from_table({true, false, true}, "bool")
local nbn = nb:shift(-1)  -- [false,true,NA]
check(nbn:get(1) == false and nbn:get(2) == true and nbn:is_null(3), "bool shift(-1)")

-- datetime negativo
local nd = S.from_table({"2020-01-01", "2020-02-01", "2020-03-01"}, "datetime")
local ndn = nd:shift(-1)
check(ndn:count_nonnull() == 2 and ndn:get(1) == nd:get(2), "dt shift(-1)")

-- validação de entrada mantida
check(not pcall(function() return nf:shift(1.5) end), "shift(1.5) erra (não-inteiro)")

print(string.format("OK — %d checks passaram (Series: rolling, expanding, cumsum, cummin, cummax, diff, shift, ffill, bfill, argmin, argmax)", n_ok))
