-- tests/test_groupby.lua
-- Teste do DataSet:groupby (Anel 2 — Operações Relacionais).
-- Sort-based, chave simples e composta, todas as agregações.
-- Rode da raiz:  luajit tests/test_groupby.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
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

print(string.format("OK — %d checks passaram (groupby)", n_ok))
