-- tests/test_enrich.lua
-- Testes formais do enriquecimento: novas reduções, transformações,
-- groupby estendido, rolling estendido, DataSet novos.
-- Rode da raiz: luajit tests/test_enrich.lua

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
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < tol
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

-- isna / notna
local isn = S.from_table({1.0, NA, 3.0}, "float64")
check(isn:isna(2) == true,   "isna(2)=true")
check(isn:isna(1) == false,  "isna(1)=false")
check(isn:notna(1) == true,  "notna(1)=true")
check(isn:notna(2) == false, "notna(2)=false")

-- where / mask / ifelse
local sw  = S.from_table({1.0,2.0,3.0,4.0}, "float64")
local cnd = sw:gt(2)
local w   = sw:where(cnd, 0.0)
check(w:get(1) == 0.0, "where[1]=0 (falso)")
check(w:get(3) == 3.0, "where[3]=3 (verdadeiro)")
local mk  = sw:mask(cnd, 0.0)
check(mk:get(1) == 1.0, "mask[1]=1 (falso, mantém)")
check(mk:get(3) == 0.0, "mask[3]=0 (verdadeiro, substitui)")
local ife = S.ifelse(cnd, sw, S.full(4, 0.0, "float64"))
check(ife:get(1) == 0.0, "ifelse[1]=0 (falso)")
check(ife:get(4) == 4.0, "ifelse[4]=4 (verdadeiro)")

-- ================================================================
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
check(emd:get(4) ~= nil,       "expanding median[4] não nil")

-- ================================================================
-- GroupBy estendido
-- ================================================================

local ds = smaug.DataSet({
    {"uf",    {"SP","RJ","SP","MG","RJ","SP"}, "string"},
    {"v",     {10.0,20.0,30.0,40.0,50.0,20.0},"float64"},
})
local gb = ds:groupby("uf")

-- grupos: MG={40}, RJ={20,50}, SP={10,30,20}

local function col(r, c) return r:col(c):to_table() end

-- std / var
local gstd = gb:std("v")
check(gstd:col("v")._dtype == "float64",   "groupby std: float64")
check(gstd:col("v"):is_null(1),            "groupby std MG: NA (n<2)")
check(approx(gstd:col("v"):get(2), 21.213203435596, 1e-9), "groupby std RJ")

local gvar = gb:var("v")
check(gvar:col("v"):is_null(1),            "groupby var MG: NA")

-- median
local gmed = gb:median("v")
check(gmed:col("v")._dtype == "float64",   "groupby median: float64")
check(gmed:col("v"):get(1) == 40.0,        "groupby median MG=40")
check(gmed:col("v"):get(2) == 35.0,        "groupby median RJ=35")
check(gmed:col("v"):get(3) == 20.0,        "groupby median SP=20")

-- first / last
local gfirst = gb:first("v")
check(gfirst:col("v"):get(1) == 40.0, "groupby first MG=40")
check(gfirst:col("v"):get(3) == 10.0, "groupby first SP=10")
local glast = gb:last("v")
check(glast:col("v"):get(3) == 20.0,  "groupby last SP=20")

-- nunique
local gnu = gb:nunique("v")
check(gnu:col("v"):get(1) == 1, "groupby nunique MG=1")
check(gnu:col("v"):get(2) == 2, "groupby nunique RJ=2")
check(gnu:col("v"):get(3) == 3, "groupby nunique SP=3")

-- prod
local gprod = gb:prod("v")
check(gprod:col("v"):get(1) == 40.0, "groupby prod MG=40")
check(approx(gprod:col("v"):get(2), 1000.0), "groupby prod RJ=1000")
check(approx(gprod:col("v"):get(3), 6000.0), "groupby prod SP=6000")

-- quantile
local gq = gb:quantile(0.5, "v")
check(gq:col("v")._dtype == "float64",  "groupby quantile: float64")
check(approx(gq:col("v"):get(3), 20.0),"groupby q50 SP=20")

-- agg
local agged = gb:agg({v={"sum","mean","std"}})
check(agged:has_column("v_sum"),   "agg: coluna v_sum")
check(agged:has_column("v_mean"),  "agg: coluna v_mean")
check(agged:has_column("v_std"),   "agg: coluna v_std")
check(agged:nrows() == 3,          "agg: 3 grupos")
-- MG sum=40
local mg_idx = nil
for i=1,agged:nrows() do
    if agged:col("uf"):get(i) == "MG" then mg_idx = i; break end
end
check(mg_idx ~= nil,               "agg: grupo MG existe")
check(agged:col("v_sum"):get(mg_idx) == 40, "agg v_sum MG=40")

-- transform
local tr = gb:transform("mean","v")
check(tr:len() == ds:nrows(),      "transform: mesmo tamanho do DS")
-- MG na posição 4 do DS original → média do grupo MG = 40
local mg_pos = nil
for i=1,ds:nrows() do
    if ds:col("uf"):get(i) == "MG" then mg_pos = i; break end
end
check(approx(tr:get(mg_pos), 40.0), "transform MG=40 (média do grupo)")

-- ================================================================
-- DataSet novos
-- ================================================================

-- rename
local ds2 = ds:rename({uf="estado", v="valor"})
check(ds2:has_column("estado"),    "rename: estado existe")
check(ds2:has_column("valor"),     "rename: valor existe")
check(not ds2:has_column("uf"),    "rename: uf não existe mais")
check(ds2:nrows() == ds:nrows(),   "rename: nrows preservado")

-- rename em lote preserva ordem
local cols_new = ds2:columns()
check(cols_new[1] == "estado",     "rename: ordem [1]=estado")
check(cols_new[2] == "valor",      "rename: ordem [2]=valor")

-- pivot_table
local ds3 = smaug.DataSet({
    {"ano",  {2023,2023,2024,2024},    "int64"},
    {"mes",  {"jan","fev","jan","fev"},"string"},
    {"val",  {10.0,20.0,30.0,40.0},   "float64"},
})
local pt = ds3:pivot_table("ano","mes","val","sum")
check(pt:nrows() == 2,             "pivot_table: 2 anos")
check(pt:has_column("jan"),        "pivot_table: coluna jan")
check(pt:has_column("fev"),        "pivot_table: coluna fev")
check(pt:has_column("ano"),        "pivot_table: coluna index")
-- 2023 jan=10, 2023 fev=20
local ano2023 = nil
for i=1,pt:nrows() do
    if pt:col("ano"):get(i) == 2023 then ano2023=i; break end
end
check(pt:col("jan"):get(ano2023) == 10.0, "pivot jan 2023=10")
check(pt:col("fev"):get(ano2023) == 20.0, "pivot fev 2023=20")

-- pivot_table aggfunc "mean"
local ptm = ds3:pivot_table("ano","mes","val","mean")
check(ptm:col("jan"):get(ano2023) == 10.0, "pivot mean jan 2023=10")

-- stack
local wide = smaug.DataSet({
    {"id", {1,2},       "int64"},
    {"a",  {10.0,20.0}, "float64"},
    {"b",  {30.0,40.0}, "float64"},
})
local stk = wide:stack({"a","b"})
check(stk:nrows() == 4,            "stack nrows=4")
check(stk:has_column("variable"),  "stack: coluna variable")
check(stk:has_column("value"),     "stack: coluna value")
check(stk:has_column("id"),        "stack: coluna id preservada")
-- ordem: (1,a,10), (1,b,30), (2,a,20), (2,b,40)
local var_col = stk:col("variable"):to_table()
check(var_col[1] == "a" or var_col[1] == "b", "stack: variable[1] é a ou b")

-- unstack (pivot com first)
local us = ds3:unstack("ano","mes","val")
check(us:nrows() == 2,             "unstack nrows=2")
check(us:has_column("jan"),        "unstack: coluna jan")

-- explode com tabelas Lua (uso via assign)
local edst = smaug.DataSet({{"id", {1,2}, "int64"}})
-- simula coluna com listas usando melt/map não é direto,
-- mas explode pode ser testado via coluna string que representa lista
-- Para este teste, validamos que explode funciona com valores escalares
-- (caso degenerado: cada valor já é escalar → linha 1-para-1)
local eds2 = smaug.DataSet({
    {"id",  {10,20,30}, "int64"},
    {"val", {1.0,2.0,3.0}, "float64"},
})
local expl = eds2:explode("val")
check(expl:nrows() == 3,           "explode escalar: nrows=3")
check(expl:col("val"):get(1) == 1.0, "explode escalar: val[1]=1.0")

print(string.format(
    "OK — %d checks passaram (enriquecimento: Series + Rolling + GroupBy + DataSet)",
    n_ok))
