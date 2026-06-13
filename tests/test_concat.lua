-- tests/test_concat.lua
-- Teste do concat (Anel 2 — Operações Relacionais).
-- Rode da raiz:  luajit tests/test_concat.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

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

print(string.format("OK — %d checks passaram (concat)", n_ok))
