-- tests/test_dataset_ops.lua
-- Teste das novas operações de DataSet (Anel 2):
-- assign, nunique, rolling (sum/mean/min/max), pivot, melt.
-- Rode da raiz:  luajit tests/test_dataset_ops.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
local function approx(a, b) return math.abs(a - b) < 1e-9 end

local ds = smaug.DataSet({
    {"uf",     {"SP","RJ","MG","SP","RJ"}, "string"},
    {"vendas", {10,  20,  30,  40,  50},   "int64"},
    {"custo",  {1.0, 2.0, 3.0, 4.0, 5.0}, "float64"},
})

-- ================================================================
-- assign
-- ================================================================

-- adicionar coluna nova via função
local ds2 = ds:assign("margem", function(d)
    return d:col("vendas"):map(function(v) return v * 2 end, "int64")
end)
check(ds2:has_column("margem"),            "assign: coluna margem adicionada")
check(ds2:col("margem"):get(1) == 20,     "assign: margem[1]=20")
check(ds2:col("margem"):get(5) == 100,    "assign: margem[5]=100")
check(ds2:nrows() == 5,                   "assign: nrows inalterado")
-- original não mutado
check(not ds:has_column("margem"),        "assign: original imutável")

-- adicionar coluna via Series direta
local nova = smaug.Series.from_table({1,2,3,4,5}, "int64")
local ds3 = ds:assign("idx", nova)
check(ds3:has_column("idx"),              "assign Series: coluna adicionada")
check(ds3:col("idx"):get(3) == 3,        "assign Series: valor correto")

-- substituir coluna existente
local ds4 = ds:assign("vendas", function(d)
    return d:col("vendas"):map(function(v) return v + 1000 end, "int64")
end)
check(ds4:col("vendas"):get(1) == 1010,  "assign substituir: valor novo")
check(ds4:ncols() == ds:ncols(),         "assign substituir: ncols inalterado")
-- posição da coluna preservada
check(ds4._col_names[2] == "vendas",     "assign substituir: posição preservada")

-- erro: tamanho errado
local ok1, _ = pcall(function()
    ds:assign("x", smaug.Series.from_table({1,2}, "int64"))
end)
check(not ok1,                            "assign: erro tamanho errado")

-- erro: não é Series nem função
local ok2, _ = pcall(function() ds:assign("x", 42) end)
check(not ok2,                            "assign: erro tipo inválido")

-- ================================================================
-- nunique
-- ================================================================
local nu = ds:nunique()
check(nu.uf == 3,                         "nunique uf: 3")
check(nu.vendas == 5,                     "nunique vendas: 5")

local ds_na = smaug.DataSet({
    {"k", {1,1,NA,2}, "int64"},
    {"v", {"a","b","a","a"}, "string"},
})
local nu2 = ds_na:nunique()
check(nu2.k == 2,                         "nunique com NA: 2 distintos (NA excluído)")
check(nu2.v == 2,                         "nunique string: 2")

-- ================================================================
-- rolling
-- ================================================================
-- window=3
local r3 = ds:rolling(3):sum("vendas")
check(r3:is_null(1),                      "rolling(3) sum: [1]=NA")
check(r3:is_null(2),                      "rolling(3) sum: [2]=NA")
check(r3:get(3) == 60,                    "rolling(3) sum: [3]=60 (10+20+30)")
check(r3:get(4) == 90,                    "rolling(3) sum: [4]=90 (20+30+40)")
check(r3:get(5) == 120,                   "rolling(3) sum: [5]=120 (30+40+50)")

-- mean
local rm = ds:rolling(2):mean("vendas")
check(rm:is_null(1),                      "rolling(2) mean: [1]=NA")
check(approx(rm:get(2), 15.0),            "rolling(2) mean: [2]=15")
check(approx(rm:get(5), 45.0),            "rolling(2) mean: [5]=45")

-- min/max
local rmin = ds:rolling(2):min("vendas")
check(rmin:get(2) == 10,                  "rolling min: [2]=10")
check(rmin:get(5) == 40,                  "rolling min: [5]=40")

local rmax = ds:rolling(2):max("vendas")
check(rmax:get(2) == 20,                  "rolling max: [2]=20")
check(rmax:get(5) == 50,                  "rolling max: [5]=50")

-- window=1: sem NA
local r1 = ds:rolling(1):sum("vendas")
check(r1:get(1) == 10,                    "rolling(1): sem NA")
check(r1:get(5) == 50,                    "rolling(1): [5]=50")

-- NA dentro da janela: ignorado
local ds_na2 = smaug.DataSet({{"v",{10,NA,30},"int64"}})
local rna = ds_na2:rolling(2):sum("v")
check(rna:is_null(1),                     "rolling com NA: [1]=NA (janela incompleta)")
check(rna:get(2) == 10,                   "rolling com NA: [2]=10 (NA ignorado)")
check(rna:get(3) == 30,                   "rolling com NA: [3]=30 (NA ignorado)")

-- erro: window inválido
local ok3, _ = pcall(function() ds:rolling(0) end)
check(not ok3,                            "rolling: window=0 recusado")
local ok4, _ = pcall(function() ds:rolling(1.5) end)
check(not ok4,                            "rolling: window fracionário recusado")

-- ================================================================
-- pivot
-- ================================================================
local long = smaug.DataSet({
    {"uf",    {"SP","SP","RJ","RJ","MG"}, "string"},
    {"prod",  {"A", "B", "A", "B", "A"}, "string"},
    {"val",   {10,  20,  30,  40,  50},   "int64"},
})
local wide = long:pivot("uf","prod","val")
check(wide:nrows() == 3,                  "pivot: 3 linhas (3 UFs)")
check(wide:has_column("uf"),              "pivot: coluna uf")
check(wide:has_column("A"),               "pivot: coluna A")
check(wide:has_column("B"),               "pivot: coluna B")
-- valores
local uf_vals = {}
for i=1,3 do uf_vals[wide:col("uf"):get(i)] = i end
check(wide:col("A"):get(uf_vals["SP"]) == 10, "pivot SP-A=10")
check(wide:col("B"):get(uf_vals["SP"]) == 20, "pivot SP-B=20")
check(wide:col("A"):get(uf_vals["RJ"]) == 30, "pivot RJ-A=30")
check(wide:col("A"):get(uf_vals["MG"]) == 50, "pivot MG-A=50")
check(wide:col("B"):is_null(uf_vals["MG"]),   "pivot MG-B=NA")

-- erros
local ok5, _ = pcall(function() long:pivot("xxx","prod","val") end)
check(not ok5,                            "pivot: coluna inexistente")
local ok6, _ = pcall(function() long:pivot("uf","prod",42) end)
check(not ok6,                            "pivot: argumento não-string")

-- ================================================================
-- melt
-- ================================================================
local wide2 = smaug.DataSet({
    {"uf",   {"SP","RJ"},    "string"},
    {"2022", {100, 200},     "int64"},
    {"2023", {150, 250},     "int64"},
})

-- melt básico
local long2 = wide2:melt("uf")
check(long2:nrows() == 4,                 "melt: 4 linhas (2 UFs × 2 anos)")
check(long2:has_column("uf"),             "melt: id_var uf presente")
check(long2:has_column("variable"),       "melt: coluna variable")
check(long2:has_column("value"),          "melt: coluna value")
-- valores: SP/2022=100, RJ/2022=200, SP/2023=150, RJ/2023=250
local rows = {}
for i=1,4 do
    rows[i] = {
        uf=long2:col("uf"):get(i),
        var=long2:col("variable"):get(i),
        val=long2:col("value"):get(i)
    }
end
check(rows[1].uf=="SP" and rows[1].var=="2022" and rows[1].val==100, "melt [1]: SP/2022/100")
check(rows[4].uf=="RJ" and rows[4].var=="2023" and rows[4].val==250, "melt [4]: RJ/2023/250")

-- var_name / value_name customizados
local long3 = wide2:melt("uf", nil, "ano", "vendas")
check(long3:has_column("ano"),            "melt var_name: coluna ano")
check(long3:has_column("vendas"),         "melt value_name: coluna vendas")
check(not long3:has_column("variable"),   "melt: variable renomeado")

-- value_vars específicos
local long4 = wide2:melt("uf", {"2022"})
check(long4:nrows() == 2,                 "melt value_vars: só 2022 → 2 linhas")
check(long4:col("variable"):get(1) == "2022", "melt value_vars: variável = 2022")

-- melt sem id_vars
local long5 = wide2:melt({})
check(long5:nrows() == 6,              "melt sem id: 6 linhas (3 colunas x 2 linhas)")
check(long5:col("variable"):get(1) == "uf", "melt sem id: uf virou variable")

-- erros
local ok7, _ = pcall(function() wide2:melt("xxx") end)
check(not ok7,                            "melt: id_var inexistente")
local ok8, _ = pcall(function() wide2:melt("uf", {"xxx"}) end)
check(not ok8,                            "melt: value_var inexistente")

print(string.format("OK — %d checks passaram (dataset_ops)", n_ok))
