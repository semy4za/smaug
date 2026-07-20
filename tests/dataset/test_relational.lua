-- tests/dataset/test_relational.lua
-- GroupBy, concat, join (inner/left/right/outer), groupby estendido
-- (std/var/median/first/last/prod/nunique/quantile/agg/transform/count).
-- Consolida: test_groupby.lua + test_concat.lua + test_join.lua + seção groupby de test_enrich.lua
-- Rode da raiz: luajit tests/dataset/test_relational.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local Series = smaug.Series
local NA     = Series.NA

local function approx(a, b, tol) tol = tol or 1e-9; return math.abs(a - b) < tol end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA

local function approx(a, b) return math.abs(a - b) < 1e-9 end

-- helper: lê coluna como map key->valor
local function col_map(ds, key_col, val_col)
    local m = {}
    for i = 1, ds:nrows() do
        m[tostring(ds:col(key_col):get(i))] = ds:col(val_col):get(i)
    end
    return m
end

-- Dataset base
local ds = smaug.DataSet({
    {"uf",     {"SP","RJ","SP","MG","SP","RJ"}, "string"},
    {"vendas", {10,  20,  30,  40,  50,  60},   "int64"},
    {"custo",  {1.0, 2.0, 3.0, 4.0, 5.0, 6.0}, "float64"},
})

-- ---- count ----
local c = ds:groupby("uf"):count()
check(c:nrows() == 3,                    "count: 3 grupos")
check(c:col("count")._dtype == "int64", "count: dtype int64")
local cm = col_map(c, "uf", "count")
check(cm["SP"] == 3,                     "count SP=3")
check(cm["RJ"] == 2,                     "count RJ=2")
check(cm["MG"] == 1,                     "count MG=1")

-- ---- sum (todas as numéricas) ----
local s = ds:groupby("uf"):sum()
check(s:nrows() == 3,                    "sum: 3 grupos")
check(s:has_column("vendas"),            "sum: tem vendas")
check(s:has_column("custo"),             "sum: tem custo")
local sv = col_map(s, "uf", "vendas")
check(sv["SP"] == 90,                    "sum SP vendas=90")
check(sv["RJ"] == 80,                    "sum RJ vendas=80")
check(sv["MG"] == 40,                    "sum MG vendas=40")

-- ---- sum (coluna específica) ----
local s2 = ds:groupby("uf"):sum("vendas")
check(s2:ncols() == 2,                   "sum(col): só uf+vendas")
check(not s2:has_column("custo"),        "sum(col): custo excluído")

-- ---- mean ----
local m = ds:groupby("uf"):mean("vendas")
local mv = col_map(m, "uf", "vendas")
check(approx(mv["SP"], 30.0),            "mean SP=30")
check(approx(mv["RJ"], 40.0),            "mean RJ=40")
check(approx(mv["MG"], 40.0),            "mean MG=40")
-- mean sempre float64
check(m:col("vendas")._dtype == "float64", "mean dtype=float64")

-- ---- min / max ----
local mn = ds:groupby("uf"):min("vendas")
local mx = ds:groupby("uf"):max("vendas")
local mnv = col_map(mn, "uf", "vendas")
local mxv = col_map(mx, "uf", "vendas")
check(mnv["SP"] == 10,                   "min SP=10")
check(mnv["RJ"] == 20,                   "min RJ=20")
check(mxv["SP"] == 50,                   "max SP=50")
check(mxv["RJ"] == 60,                   "max RJ=60")

-- ---- múltiplas colunas específicas ----
local s3 = ds:groupby("uf"):sum("vendas","custo")
check(s3:ncols() == 3,                   "sum(v,c): uf+vendas+custo")

-- ---- nulos ignorados nas agregações ----
local dsn = smaug.DataSet({
    {"cat", {"A","A","B","B"},    "string"},
    {"val", {10, NA, 20, 30},     "int64"},
})
local sn = dsn:groupby("cat"):sum("val")
local snv = col_map(sn, "cat", "val")
check(snv["A"] == 10,                    "sum: nulo ignorado A=10")
check(snv["B"] == 50,                    "sum: B=50 (20+30)")

local mn2 = dsn:groupby("cat"):mean("val")
local mnv2 = col_map(mn2, "cat", "val")
check(approx(mnv2["A"], 10.0),           "mean: nulo ignorado A=10")
check(approx(mnv2["B"], 25.0),           "mean: B=25")

-- all-null group -> nil (NA na saída)
local dsnn = smaug.DataSet({
    {"cat", {"A","A"},     "string"},
    {"val", {NA, NA},      "int64"},
})
local snn = dsnn:groupby("cat"):sum("val")
check(snn:nrows() == 1,                  "all-null: 1 grupo")
check(snn:col("val"):get(1) == 0,        "sum all-null: 0 (soma vazia)")

-- ---- chave int64 ----
local dsi = smaug.DataSet({
    {"ano", {2023,2024,2023,2024}, "int64"},
    {"val", {10,  20,  30,  40},   "int64"},
})
local si = dsi:groupby("ano"):sum()
local siv = col_map(si, "ano", "val")
check(siv["2023"] == 40,                 "chave int64: 2023=40")
check(siv["2024"] == 60,                 "chave int64: 2024=60")

-- ---- chave bool ----
local dsb = smaug.DataSet({
    {"ativo", {true,false,true,false,true}, "bool"},
    {"val",   {10,  20,  30,  40,  50},    "int64"},
})
local sb = dsb:groupby("ativo"):sum()
check(sb:nrows() == 2,                   "chave bool: 2 grupos")
local sbv = col_map(sb, "ativo", "val")
check(sbv["true"]  == 90,               "chave bool: true=90")
check(sbv["false"] == 60,               "chave bool: false=60")

-- ---- chave composta ----
local dsc = smaug.DataSet({
    {"uf",  {"SP","SP","RJ","RJ","SP"}, "string"},
    {"ano", {2023,2024,2023,2023,2023}, "int64"},
    {"val", {10,  20,  30,  40,  50},   "int64"},
})
local sc = dsc:groupby({"uf","ano"}):sum()
check(sc:nrows() == 3,                   "chave composta: 3 grupos")
-- SP2023=60, SP2024=20, RJ2023=70
local scv = {}
for i = 1, sc:nrows() do
    local k = sc:col("uf"):get(i)..tostring(sc:col("ano"):get(i))
    scv[k] = sc:col("val"):get(i)
end
check(scv["SP2023"] == 60,              "composta SP2023=60")
check(scv["SP2024"] == 20,              "composta SP2024=20")
check(scv["RJ2023"] == 70,              "composta RJ2023=70")

local cc = dsc:groupby({"uf","ano"}):count()
check(cc:nrows() == 3,                   "composta count: 3 grupos")
check(cc:has_column("count"),            "composta count: coluna count")

-- ---- DataSet vazio ----
local dse = smaug.DataSet({
    {"uf",  {}, "string"},
    {"val", {}, "int64"},
})
local se = dse:groupby("uf"):sum()
check(se:nrows() == 0,                   "vazio: 0 grupos")

-- ---- grupo de 1 linha ----
local ds1 = smaug.DataSet({
    {"uf",  {"SP","RJ","MG"}, "string"},
    {"val", {1,2,3},           "int64"},
})
local s1 = ds1:groupby("uf"):sum()
check(s1:nrows() == 3,                   "grupo 1 linha: 3 grupos")

-- ---- erros esperados ----
local ok, _ = pcall(function() ds:groupby("xxx") end)
check(not ok,                            "erro: coluna inexistente")
local ok2, _ = pcall(function() ds:groupby(123) end)
check(not ok2,                           "erro: chave não-string")
local ok3, _ = pcall(function() ds:groupby({}) end)
check(not ok3,                           "erro: lista vazia")

-- chave com nulo -> erro
local dsna = smaug.DataSet({
    {"uf",  {"SP", NA, "RJ"}, "string"},
    {"val", {1,2,3},           "int64"},
})
local ok4, _ = pcall(function() dsna:groupby("uf"):count() end)
check(not ok4,                           "erro: chave com nulo")

-- coluna pedida não existe
local ok5, _ = pcall(function() ds:groupby("uf"):sum("inexistente") end)
check(not ok5,                           "erro: coluna agg inexistente")


-- =====================================================================
-- GroupBy estendido (de test_enrich.lua)
-- =====================================================================

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

-- =====================================================================
-- Concat (de test_concat.lua)
-- =====================================================================


local smaug = require("smaug")
local NA    = smaug.Series.NA


local a = smaug.DataSet({
    {"uf",  {"SP","RJ"},  "string"},
    {"val", {10, 20},     "int64"},
})
local b = smaug.DataSet({
    {"uf",  {"MG","SP"},  "string"},
    {"val", {30, 40},     "int64"},
})
local c = smaug.DataSet({
    {"uf",  {"RS"},       "string"},
    {"val", {50},         "int64"},
})

-- ---- 2 DataSets via smaug.concat ----
local r2 = smaug.concat({a, b})
check(r2:nrows() == 4,                         "concat 2: 4 linhas")
check(r2:ncols() == 2,                         "concat 2: 2 colunas")
check(r2:col("uf"):get(1) == "SP",             "concat 2: linha 1 uf=SP")
check(r2:col("uf"):get(3) == "MG",             "concat 2: linha 3 uf=MG")
check(r2:col("val"):get(1) == 10,              "concat 2: linha 1 val=10")
check(r2:col("val"):get(4) == 40,              "concat 2: linha 4 val=40")
check(r2:col("uf")._dtype == "string",         "concat 2: dtype string preservado")
check(r2:col("val")._dtype == "int64",         "concat 2: dtype int64 preservado")

-- ---- 3 DataSets ----
local r3 = smaug.concat({a, b, c})
check(r3:nrows() == 5,                         "concat 3: 5 linhas")
check(r3:col("uf"):get(5) == "RS",             "concat 3: linha 5 uf=RS")
check(r3:col("val"):get(5) == 50,              "concat 3: linha 5 val=50")

-- ---- método ds:concat(other) ----
local rm = a:concat(b)
check(rm:nrows() == 4,                         "método concat: 4 linhas")
check(rm:col("val"):get(2) == 20,              "método concat: val linha 2=20")

-- ---- ds:concat({b, c}) ----
local rm2 = a:concat({b, c})
check(rm2:nrows() == 5,                        "método concat lista: 5 linhas")

-- ---- independência: mutar resultado não afeta originais ----
local ri = smaug.concat({a, b})
ri:add_column("extra", smaug.Series.from_table({1,2,3,4}, "int64"))
check(not a:has_column("extra"),               "independência: original não alterado")

-- ---- com NA ----
local d = smaug.DataSet({
    {"uf",  {"BA"},  "string"},
    {"val", {NA},    "int64"},
})
local rna = smaug.concat({a, d})
check(rna:nrows() == 3,                        "concat com NA: 3 linhas")
check(rna:col("val"):is_null(3),               "concat com NA: null preservado")
check(not rna:col("val"):is_null(1),           "concat com NA: não-null intacto")

-- ---- float64 ----
local fa = smaug.DataSet({{"v",{1.5,2.5},"float64"}})
local fb = smaug.DataSet({{"v",{3.5},     "float64"}})
local rf = smaug.concat({fa, fb})
check(rf:nrows() == 3,                         "concat float64: 3 linhas")
check(rf:col("v"):get(3) == 3.5,              "concat float64: valor correto")
check(rf:col("v")._dtype == "float64",         "concat float64: dtype preservado")

-- ---- bool ----
local ba = smaug.DataSet({{"ok",{true,false},"bool"}})
local bb = smaug.DataSet({{"ok",{true},      "bool"}})
local rb = smaug.concat({ba, bb})
check(rb:nrows() == 3,                         "concat bool: 3 linhas")
check(rb:col("ok"):get(1) == true,             "concat bool: true preservado")
check(rb:col("ok"):get(2) == false,            "concat bool: false preservado")
check(rb:col("ok")._dtype == "bool",           "concat bool: dtype preservado")

-- ---- DataSet vazio como primeiro ----
local empty = smaug.DataSet({{"uf",{},"string"},{"val",{},"int64"}})
local re = smaug.concat({empty, a})
check(re:nrows() == 2,                         "concat vazio+a: 2 linhas")

-- ---- DataSet vazio como segundo ----
local re2 = smaug.concat({a, empty})
check(re2:nrows() == 2,                        "concat a+vazio: 2 linhas")

-- ---- dois vazios ----
local re3 = smaug.concat({empty, empty})
check(re3:nrows() == 0,                        "concat vazio+vazio: 0 linhas")

-- ---- um único DataSet (cópia) ----
local r1 = smaug.concat({a})
check(r1:nrows() == 2,                         "concat 1 elem: 2 linhas (cópia)")
check(r1:col("uf"):get(1) == "SP",             "concat 1 elem: valor correto")

-- ---- erros esperados ----
local ok1, _ = pcall(function() smaug.concat({}) end)
check(not ok1,                                 "erro: lista vazia")

local ok2, _ = pcall(function() smaug.concat({a, "nao_dataset"}) end)
check(not ok2,                                 "erro: elemento não-DataSet")

-- coluna faltando
local bad_col = smaug.DataSet({{"outro",{1},"int64"}})
local ok3, _ = pcall(function() smaug.concat({a, bad_col}) end)
check(not ok3,                                 "erro: coluna faltando")

-- dtype incompatível
local bad_dt = smaug.DataSet({{"uf",{"X"},"string"},{"val",{1.5},"float64"}})
local ok4, _ = pcall(function() smaug.concat({a, bad_dt}) end)
check(not ok4,                                 "erro: dtype incompatível")

-- número de colunas diferente
local bad_nc = smaug.DataSet({{"uf",{"X"},"string"}})
local ok5, _ = pcall(function() smaug.concat({a, bad_nc}) end)
check(not ok5,                                 "erro: ncols diferente")


-- =====================================================================
-- Join (de test_join.lua)
-- =====================================================================


package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA


-- Datasets base
local pedidos = smaug.DataSet({
    {"id",      {1, 2, 3, 4},           "int64"},
    {"cliente", {"A","B","A","C"},       "string"},
    {"valor",   {100, 200, 150, 300},    "int64"},
})
local clientes = smaug.DataSet({
    {"cliente", {"A","B","D"},           "string"},
    {"cidade",  {"SP","RJ","MG"},        "string"},
})

-- ================================================================
-- INNER JOIN
-- ================================================================
local ri = pedidos:join(clientes, "cliente")   -- default = inner
check(ri:nrows() == 3,                         "inner: 3 linhas (C e D sem match)")
check(ri:ncols() == 4,                         "inner: 4 colunas")
check(ri:has_column("id"),                     "inner: tem id")
check(ri:has_column("cliente"),                "inner: tem cliente")
check(ri:has_column("valor"),                  "inner: tem valor")
check(ri:has_column("cidade"),                 "inner: tem cidade")
-- A aparece 2x (pedidos 1 e 3)
local cidades = {}
for i = 1, ri:nrows() do cidades[i] = ri:col("cidade"):get(i) end
check(cidades[1] == "SP" and cidades[2] == "RJ" and cidades[3] == "SP",
      "inner: cidades corretas (SP,RJ,SP)")
check(ri:col("id"):get(1) == 1,                "inner: id linha 1 = 1")
check(ri:col("id"):get(3) == 3,                "inner: id linha 3 = 3 (segundo A)")
-- C (pedido 4) não aparece
local ids = {}; for i=1,ri:nrows() do ids[ri:col("id"):get(i)] = true end
check(not ids[4],                              "inner: pedido 4 (C) excluído")

-- how explícito
local ri2 = pedidos:join(clientes, "cliente", "inner")
check(ri2:nrows() == 3,                        "inner explícito: 3 linhas")

-- ================================================================
-- LEFT JOIN
-- ================================================================
local rl = pedidos:join(clientes, "cliente", "left")
check(rl:nrows() == 4,                         "left: 4 linhas (todos os pedidos)")
check(rl:col("cidade"):is_null(4),             "left: cidade NULL para C")
check(rl:col("cliente"):get(4) == "C",         "left: cliente C na linha 4")
check(not rl:col("cidade"):is_null(1),         "left: cidade não-null para A")
check(rl:col("cidade"):get(1) == "SP",         "left: cidade SP para A")

-- ================================================================
-- RIGHT JOIN
-- ================================================================
local rr = pedidos:join(clientes, "cliente", "right")
check(rr:nrows() == 4,                         "right: 4 linhas (A×2, B, D)")
-- D aparece com NAs no lado esquerdo
local d_row = nil
for i = 1, rr:nrows() do
    if rr:col("cliente"):get(i) == "D" then d_row = i; break end
end
check(d_row ~= nil,                            "right: D presente")
check(rr:col("id"):is_null(d_row),             "right: id NULL para D")
check(rr:col("valor"):is_null(d_row),          "right: valor NULL para D")

-- ================================================================
-- OUTER JOIN
-- ================================================================
local ro = pedidos:join(clientes, "cliente", "outer")
check(ro:nrows() == 5,                         "outer: 5 linhas (A×2, B, C, D)")
-- C: cidade NULL; D: id e valor NULL
local c_row, d_row_o = nil, nil
for i = 1, ro:nrows() do
    local cl = ro:col("cliente"):get(i)
    if cl == "C" then c_row = i end
    if cl == "D" then d_row_o = i end
end
check(c_row ~= nil,                            "outer: C presente")
check(d_row_o ~= nil,                          "outer: D presente")
check(ro:col("cidade"):is_null(c_row),         "outer: cidade NULL para C")
check(ro:col("id"):is_null(d_row_o),           "outer: id NULL para D")

-- ================================================================
-- CHAVES DIFERENTES
-- ================================================================
local fa = smaug.DataSet({
    {"id_pedido", {1,2,3},   "int64"},
    {"val",       {10,20,30}, "int64"},
})
local fb = smaug.DataSet({
    {"id_cliente", {2,3,4},    "int64"},
    {"desc",       {"b","c","d"}, "string"},
})
local rc = fa:join(fb, {"id_pedido","id_cliente"}, "inner")
check(rc:nrows() == 2,                         "chaves diff inner: 2 linhas (2,3)")
check(rc:has_column("id_pedido"),              "chaves diff: coluna esq presente")
check(rc:col("val"):get(1) == 20,              "chaves diff: val linha 1 = 20")
check(rc:col("desc"):get(1) == "b",            "chaves diff: desc linha 1 = b")

local rl2 = fa:join(fb, {"id_pedido","id_cliente"}, "left")
check(rl2:nrows() == 3,                        "chaves diff left: 3 linhas")
check(rl2:col("desc"):is_null(1),              "chaves diff left: desc NULL para id=1")

-- ================================================================
-- SUFIXOS
-- ================================================================
local sx = smaug.DataSet({{"k",{1,2},"int64"},{"nome",{"a","b"},"string"},{"x",{10,20},"int64"}})
local sy = smaug.DataSet({{"k",{1,2},"int64"},{"nome",{"x","y"},"string"},{"y",{100,200},"int64"}})
local rs = sx:join(sy, "k", "inner")
check(rs:has_column("nome_left"),              "sufixos: nome_left presente")
check(rs:has_column("nome_right"),             "sufixos: nome_right presente")
check(not rs:has_column("nome"),               "sufixos: nome sem sufixo ausente")
check(rs:has_column("x"),                      "sufixos: x sem sufixo (só em esq)")
check(rs:has_column("y"),                      "sufixos: y sem sufixo (só em dir)")
check(rs:col("nome_left"):get(1) == "a",       "sufixos: nome_left valor correto")
check(rs:col("nome_right"):get(1) == "x",      "sufixos: nome_right valor correto")

-- sufixos customizados
local rsc = sx:join(sy, "k", "inner", {"_esq","_dir"})
check(rsc:has_column("nome_esq"),              "sufixos custom: nome_esq")
check(rsc:has_column("nome_dir"),              "sufixos custom: nome_dir")

-- ================================================================
-- MÚLTIPLOS MATCHES (N para N)
-- ================================================================
local ma = smaug.DataSet({{"k",{1,1,2},"int64"},{"va",{10,20,30},"int64"}})
local mb = smaug.DataSet({{"k",{1,1,2},"int64"},{"vb",{100,200,300},"int64"}})
local rm = ma:join(mb, "k", "inner")
-- 1×1 cruzado = 4 linhas para k=1, mais 1 para k=2
check(rm:nrows() == 5,                         "N×N: 5 linhas (2×2 + 1×1)")

-- ================================================================
-- DATASETS VAZIOS
-- ================================================================
local empty = smaug.DataSet({{"k",{},"int64"},{"v",{},"int64"}})
local normal = smaug.DataSet({{"k",{1,2},"int64"},{"v",{10,20},"int64"}})

local re1 = empty:join(normal, "k", "inner")
check(re1:nrows() == 0,                        "vazio inner: 0 linhas")
local re2 = normal:join(empty, "k", "inner")
check(re2:nrows() == 0,                        "inner vazio: 0 linhas")
local re3 = normal:join(empty, "k", "left")
check(re3:nrows() == 2,                        "left com right vazio: 2 linhas")
check(re3:col("v_right"):is_null(1),           "left vazio: v_right NULL")
local re4 = empty:join(normal, "k", "outer")
check(re4:nrows() == 2,                        "outer esq-vazio: 2 linhas (do dir)")

-- ================================================================
-- CHAVE INT64
-- ================================================================
local ia = smaug.DataSet({{"id",{10,20,30},"int64"},{"a",{1,2,3},"int64"}})
local ib = smaug.DataSet({{"id",{20,30,40},"int64"},{"b",{20,30,40},"int64"}})
local rii = ia:join(ib, "id", "inner")
check(rii:nrows() == 2,                        "chave int64 inner: 2 linhas")
check(rii:col("id"):get(1) == 20,              "chave int64: id=20")

-- ================================================================
-- ERROS ESPERADOS
-- ================================================================
local ok1, _ = pcall(function() pedidos:join("nao_dataset", "cliente") end)
check(not ok1,                                 "erro: other não-DataSet")

local ok2, _ = pcall(function() pedidos:join(clientes, "inexistente") end)
check(not ok2,                                 "erro: chave esq inexistente")

local ok3, _ = pcall(function() pedidos:join(clientes, {"cliente","inexistente"}) end)
check(not ok3,                                 "erro: chave dir inexistente")

local ok4, _ = pcall(function() pedidos:join(clientes, "cliente", "bad") end)
check(not ok4,                                 "erro: how inválido")


-- =====================================================================
-- Contrato 8 — NA em chave relacional é erro (join/groupby/pivot/pivot_table)
-- =====================================================================
local function msg_of(fn)
    local ok, e = pcall(fn)
    return (not ok) and tostring(e) or nil
end

-- join: NA na chave simples → erro orientado (não casa NA com NA)
local jL = smaug.DataSet({{"k", {"x", NA, "y"}, "string"}, {"v", {1,2,3}, "int64"}})
local jR = smaug.DataSet({{"k", {"x", "y"}, "string"},     {"w", {9,8},    "int64"}})
local mj = msg_of(function() return jL:join(jR, "k") end)
check(mj ~= nil and mj:match("join") and mj:match("'k'") and mj:match("contém NA")
      and mj:match("fillna") and mj:match("dropna"), "C8 join: erro com mensagem padrão")

-- groupby: NA na chave → erro (mensagem padrão, agora menciona fillna)
local mg = msg_of(function() return jL:groupby("k"):count() end)
check(mg ~= nil and mg:match("groupby") and mg:match("'k'") and mg:match("contém NA")
      and mg:match("fillna"), "C8 groupby: erro com mensagem padrão (fillna)")

-- pivot e pivot_table: NA no index → erro (não descarta linha em silêncio)
local pv = smaug.DataSet({
    {"i", {"a", NA},   "string"},
    {"c", {"m", "n"},  "string"},
    {"v", {1, 2},      "int64"},
})
local mp = msg_of(function() return pv:pivot("i", "c", "v") end)
check(mp ~= nil and mp:match("pivot") and mp:match("'i'") and mp:match("contém NA"),
      "C8 pivot: erro com mensagem padrão")
local mpt = msg_of(function() return pv:pivot_table("i", "c", "v", "sum") end)
check(mpt ~= nil and mpt:match("pivot_table") and mpt:match("'i'") and mpt:match("contém NA"),
      "C8 pivot_table: erro com mensagem padrão")

-- NA na COLUNA (não no index) do pivot também dispara
local pv2 = smaug.DataSet({
    {"i", {"a", "b"},  "string"},
    {"c", {"m", NA},   "string"},
    {"v", {1, 2},      "int64"},
})
local mp2 = msg_of(function() return pv2:pivot("i", "c", "v") end)
check(mp2 ~= nil and mp2:match("'c'"), "C8 pivot: NA na coluna 'columns' dispara")

-- chave COMPOSTA: NA em qualquer coluna da chave dispara, nomeando-a
local cmp = smaug.DataSet({
    {"k1", {"x", "y"}, "string"},
    {"k2", {"a", NA},  "string"},
    {"v",  {1, 2},     "int64"},
})
local mc = msg_of(function() return cmp:groupby({"k1", "k2"}):count() end)
check(mc ~= nil and mc:match("'k2'"), "C8 composta: nomeia a coluna culpada (k2)")
-- join valida AMBOS os lados: NA na chave do lado direito (forma {chave_esq, chave_dir})
local jLok = smaug.DataSet({{"kl", {"x", "y"}, "string"}, {"v", {1, 2}, "int64"}})
local jRna = smaug.DataSet({{"kr", {"x", NA},  "string"}, {"w", {9, 8}, "int64"}})
local mcj = msg_of(function() return jLok:join(jRna, {"kl", "kr"}) end)
check(mcj ~= nil and mcj:match("'kr'"), "C8 join: valida chave do lado direito (kr)")

-- a coluna de VALORES pode conter NA (não é chave) — join com valor NA funciona
local vL = smaug.DataSet({{"k", {"x", "y"}, "string"}, {"v", {1, NA}, "int64"}})
local vR = smaug.DataSet({{"k", {"x", "y"}, "string"}, {"w", {9, 8}, "int64"}})
local okv = pcall(function() return vL:join(vR, "k") end)
check(okv, "C8: NA em coluna de valores (não-chave) não dispara")

-- ===================================================================
-- L2: int64 > 2^53 em chave de join/groupby (correção via core/keys).
-- A chave passava por get()→double: dois int64 distintos acima de 2^53
-- colapsavam (join casava errado, groupby fundia grupos) e o valor da
-- chave saía degradado no resultado. keys.encode/value corrigem ambos.
-- ===================================================================
do
    local ffi = require("ffi")
    local A = ffi.new("int64_t", 9007199254740992LL)  -- 2^53
    local B = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1

    -- groupby: a,b,a → 2 grupos (não funde)
    local g = smaug.DataSet({{"id", {A, B, A}, "int64"}, {"v", {1, 10, 100}, "int64"}})
                   :groupby("id"):sum("v")
    check(g:nrows() == 2, "L2 groupby int64>2^53 não funde grupos")
    local seen_a, seen_b = false, false
    for i = 1, g:nrows() do
        local k = g:column("id"):get_raw(i)
        if k == A then seen_a = true elseif k == B then seen_b = true end
    end
    check(seen_a and seen_b, "L2 groupby preserva valor exato da chave no resultado")

    -- join: ids distintos não casam; iguais casam e preservam valor
    local L = smaug.DataSet({{"id", {A}, "int64"}, {"lval", {100}, "int64"}})
    local Rdiff = smaug.DataSet({{"id", {B}, "int64"}, {"rval", {200}, "int64"}})
    check(L:join(Rdiff, "id", "inner"):nrows() == 0, "L2 join ids distintos → 0 linhas")
    local Rsame = smaug.DataSet({{"id", {A}, "int64"}, {"rval", {200}, "int64"}})
    local j = L:join(Rsame, "id", "inner")
    check(j:nrows() == 1, "L2 join ids iguais → 1 linha")
    check(j:column("id"):get_raw(1) == A, "L2 join preserva valor exato da chave")
end


print(string.format("OK — %d checks passaram (DataSet: groupby, concat, join)", n_ok))
