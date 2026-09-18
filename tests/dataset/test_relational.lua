-- tests/dataset/test_relational.lua
-- GroupBy, concat, join (inner/left/right/outer), groupby estendido
-- (std/var/median/first/last/prod/nunique/quantile/agg/transform/count).
-- Consolida: test_groupby.lua + test_concat.lua + test_join.lua + seção groupby de test_enrich.lua
-- Rode da raiz: luajit tests/dataset/test_relational.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local function approximately_equal(left_value, right_value, tolerance) tolerance = tolerance or 1e-9; return math.abs(left_value - right_value) < tolerance end
local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local function approximately_equal_2(left_value, right_value) return math.abs(left_value - right_value) < 1e-9 end

-- helper: lê coluna como map key->valor
local function column_map(dataset, key_column, val_column)
    local values = {}
    for row_index = 1, dataset:nrows() do
        values[tostring(dataset:col(key_column):get(row_index))] = dataset:col(val_column):get(row_index)
    end
    return values
end

-- Dataset base
local source_dataset = smaug.DataSet({
    {"uf",     {"SP","RJ","SP","MG","SP","RJ"}, "string"},
    {"vendas", {10,  20,  30,  40,  50,  60},   "int64"},
    {"custo",  {1.0, 2.0, 3.0, 4.0, 5.0, 6.0}, "float64"},
})

-- ---- count ----
local count_result = source_dataset:groupby("uf"):count()
check(count_result:nrows() == 3,                    "count: 3 grupos")
check(count_result:col("count")._dtype == "int64", "count: dtype int64")
local count_by_state = column_map(count_result, "uf", "count")
check(count_by_state["SP"] == 3,                     "count SP=3")
check(count_by_state["RJ"] == 2,                     "count RJ=2")
check(count_by_state["MG"] == 1,                     "count MG=1")

-- ---- sum (todas as numéricas) ----
local sum_result = source_dataset:groupby("uf"):sum()
check(sum_result:nrows() == 3,                    "sum: 3 grupos")
check(sum_result:has_column("vendas"),            "sum: tem vendas")
check(sum_result:has_column("custo"),             "sum: tem custo")
local sales_by_state = column_map(sum_result, "uf", "vendas")
check(sales_by_state["SP"] == 90,                    "sum SP vendas=90")
check(sales_by_state["RJ"] == 80,                    "sum RJ vendas=80")
check(sales_by_state["MG"] == 40,                    "sum MG vendas=40")

-- ---- sum (coluna específica) ----
local sum_result_2 = source_dataset:groupby("uf"):sum("vendas")
check(sum_result_2:ncols() == 2,                   "sum(col): só uf+vendas")
check(not sum_result_2:has_column("custo"),        "sum(col): custo excluído")

-- ---- mean ----
local mean_result = source_dataset:groupby("uf"):mean("vendas")
local mean_by_state = column_map(mean_result, "uf", "vendas")
check(approximately_equal_2(mean_by_state["SP"], 30.0),            "mean SP=30")
check(approximately_equal_2(mean_by_state["RJ"], 40.0),            "mean RJ=40")
check(approximately_equal_2(mean_by_state["MG"], 40.0),            "mean MG=40")
-- mean sempre float64
check(mean_result:col("vendas")._dtype == "float64", "mean dtype=float64")

-- ---- min / max ----
local minimum_result = source_dataset:groupby("uf"):min("vendas")
local maximum_result = source_dataset:groupby("uf"):max("vendas")
local minimum_by_state = column_map(minimum_result, "uf", "vendas")
local maximum_by_state = column_map(maximum_result, "uf", "vendas")
check(minimum_by_state["SP"] == 10,                   "min SP=10")
check(minimum_by_state["RJ"] == 20,                   "min RJ=20")
check(maximum_by_state["SP"] == 50,                   "max SP=50")
check(maximum_by_state["RJ"] == 60,                   "max RJ=60")

-- ---- múltiplas colunas específicas ----
local sum_result_3 = source_dataset:groupby("uf"):sum("vendas","custo")
check(sum_result_3:ncols() == 3,                   "sum(v,c): uf+vendas+custo")

-- ---- nulos ignorados nas agregações ----
local source_dataset_2 = smaug.DataSet({
    {"cat", {"A","A","B","B"},    "string"},
    {"val", {10, smaug.NA, 20, 30},     "int64"},
})
local sum_result_4 = source_dataset_2:groupby("cat"):sum("val")
local nullable_sum_by_category = column_map(sum_result_4, "cat", "val")
check(nullable_sum_by_category["A"] == 10,                    "sum: nulo ignorado A=10")
check(nullable_sum_by_category["B"] == 50,                    "sum: B=50 (20+30)")

local mean_result_2 = source_dataset_2:groupby("cat"):mean("val")
local nullable_minimum_by_category = column_map(mean_result_2, "cat", "val")
check(approximately_equal_2(nullable_minimum_by_category["A"], 10.0),           "mean: nulo ignorado A=10")
check(approximately_equal_2(nullable_minimum_by_category["B"], 25.0),           "mean: B=25")

-- all-null group -> nil (NA na saída)
local source_dataset_3 = smaug.DataSet({
    {"cat", {"A","A"},     "string"},
    {"val", {smaug.NA, smaug.NA},      "int64"},
})
local sum_result_5 = source_dataset_3:groupby("cat"):sum("val")
check(sum_result_5:nrows() == 1,                  "all-null: 1 grupo")
check(sum_result_5:col("val"):get(1) == 0,        "sum all-null: 0 (soma vazia)")

-- ---- chave int64 ----
local source_dataset_4 = smaug.DataSet({
    {"ano", {2023,2024,2023,2024}, "int64"},
    {"val", {10,  20,  30,  40},   "int64"},
})
local sum_result_6 = source_dataset_4:groupby("ano"):sum()
local sum_by_year = column_map(sum_result_6, "ano", "val")
check(sum_by_year["2023"] == 40,                 "chave int64: 2023=40")
check(sum_by_year["2024"] == 60,                 "chave int64: 2024=60")

-- ---- chave bool ----
local source_dataset_5 = smaug.DataSet({
    {"ativo", {true,false,true,false,true}, "bool"},
    {"val",   {10,  20,  30,  40,  50},    "int64"},
})
local sum_result_7 = source_dataset_5:groupby("ativo"):sum()
check(sum_result_7:nrows() == 2,                   "chave bool: 2 grupos")
local sum_by_boolean = column_map(sum_result_7, "ativo", "val")
check(sum_by_boolean["true"]  == 90,               "chave bool: true=90")
check(sum_by_boolean["false"] == 60,               "chave bool: false=60")

-- ---- chave composta ----
local source_dataset_6 = smaug.DataSet({
    {"uf",  {"SP","SP","RJ","RJ","SP"}, "string"},
    {"ano", {2023,2024,2023,2023,2023}, "int64"},
    {"val", {10,  20,  30,  40,  50},   "int64"},
})
local sum_result_8 = source_dataset_6:groupby({"uf","ano"}):sum()
check(sum_result_8:nrows() == 3,                   "chave composta: 3 grupos")
-- SP2023=60, SP2024=20, RJ2023=70
local values = {}
for row_index = 1, sum_result_8:nrows() do
    local key_series = sum_result_8:col("uf"):get(row_index)..tostring(sum_result_8:col("ano"):get(row_index))
    values[key_series] = sum_result_8:col("val"):get(row_index)
end
check(values["SP2023"] == 60,              "composta SP2023=60")
check(values["SP2024"] == 20,              "composta SP2024=20")
check(values["RJ2023"] == 70,              "composta RJ2023=70")

local count_result_2 = source_dataset_6:groupby({"uf","ano"}):count()
check(count_result_2:nrows() == 3,                   "composta count: 3 grupos")
check(count_result_2:has_column("count"),            "composta count: coluna count")

-- ---- DataSet vazio ----
local source_dataset_7 = smaug.DataSet({
    {"uf",  {}, "string"},
    {"val", {}, "int64"},
})
local sum_result_9 = source_dataset_7:groupby("uf"):sum()
check(sum_result_9:nrows() == 0,                   "vazio: 0 grupos")

-- ---- grupo de 1 linha ----
local source_dataset_8 = smaug.DataSet({
    {"uf",  {"SP","RJ","MG"}, "string"},
    {"val", {1,2,3},           "int64"},
})
local sum_result_10 = source_dataset_8:groupby("uf"):sum()
check(sum_result_10:nrows() == 3,                   "grupo 1 linha: 3 grupos")

-- ---- erros esperados ----
local succeeded, unused_error = pcall(function() source_dataset:groupby("xxx") end)
check(not succeeded,                            "erro: coluna inexistente")
local succeeded_2, unused_error_2 = pcall(function() source_dataset:groupby(123) end)
check(not succeeded_2,                           "erro: chave não-string")
local succeeded_3, unused_error_3 = pcall(function() source_dataset:groupby({}) end)
check(not succeeded_3,                           "erro: lista vazia")

-- chave com nulo -> erro
local source_dataset_9 = smaug.DataSet({
    {"uf",  {"SP", smaug.NA, "RJ"}, "string"},
    {"val", {1,2,3},           "int64"},
})
local succeeded_4, unused_error_4 = pcall(function() source_dataset_9:groupby("uf"):count() end)
check(not succeeded_4,                           "erro: chave com nulo")

-- coluna pedida não existe
local succeeded_5, unused_error_5 = pcall(function() source_dataset:groupby("uf"):sum("inexistente") end)
check(not succeeded_5,                           "erro: coluna agg inexistente")

-- =====================================================================
-- GroupBy estendido (de test_enrich.lua)
-- =====================================================================

-- ================================================================
-- GroupBy estendido
-- ================================================================

local source_dataset_10 = smaug.DataSet({
    {"uf",    {"SP","RJ","SP","MG","RJ","SP"}, "string"},
    {"v",     {10.0,20.0,30.0,40.0,50.0,20.0},"float64"},
})
local grouped_dataset = source_dataset_10:groupby("uf")

-- grupos: MG={40}, RJ={20,50}, SP={10,30,20}

local function column(row_values, column_2) return row_values:col(column_2):to_table() end

-- std / var
local standard_deviation_result = grouped_dataset:std("v")
check(standard_deviation_result:col("v")._dtype == "float64",   "groupby std: float64")
check(standard_deviation_result:col("v"):is_null(1),            "groupby std MG: NA (n<2)")
check(approximately_equal_2(standard_deviation_result:col("v"):get(2), 21.213203435596, 1e-9), "groupby std RJ")

local variance_result = grouped_dataset:var("v")
check(variance_result:col("v"):is_null(1),            "groupby var MG: NA")

-- median
local median_result = grouped_dataset:median("v")
check(median_result:col("v")._dtype == "float64",   "groupby median: float64")
check(median_result:col("v"):get(1) == 40.0,        "groupby median MG=40")
check(median_result:col("v"):get(2) == 35.0,        "groupby median RJ=35")
check(median_result:col("v"):get(3) == 20.0,        "groupby median SP=20")

-- first / last
local gfirst = grouped_dataset:first("v")
check(gfirst:col("v"):get(1) == 40.0, "groupby first MG=40")
check(gfirst:col("v"):get(3) == 10.0, "groupby first SP=10")
local glast = grouped_dataset:last("v")
check(glast:col("v"):get(3) == 20.0,  "groupby last SP=20")

-- nunique
local unique_count = grouped_dataset:nunique("v")
check(unique_count:col("v"):get(1) == 1, "groupby nunique MG=1")
check(unique_count:col("v"):get(2) == 2, "groupby nunique RJ=2")
check(unique_count:col("v"):get(3) == 3, "groupby nunique SP=3")

-- prod
local gprod = grouped_dataset:prod("v")
check(gprod:col("v"):get(1) == 40.0, "groupby prod MG=40")
check(approximately_equal_2(gprod:col("v"):get(2), 1000.0), "groupby prod RJ=1000")
check(approximately_equal_2(gprod:col("v"):get(3), 6000.0), "groupby prod SP=6000")

-- quantile
local quantile_result = grouped_dataset:quantile(0.5, "v")
check(quantile_result:col("v")._dtype == "float64",  "groupby quantile: float64")
check(approximately_equal_2(quantile_result:col("v"):get(3), 20.0),"groupby q50 SP=20")

-- agg
local agged = grouped_dataset:agg({v={"sum","mean","std"}})
check(agged:has_column("v_sum"),   "agg: coluna v_sum")
check(agged:has_column("v_mean"),  "agg: coluna v_mean")
check(agged:has_column("v_std"),   "agg: coluna v_std")
check(agged:nrows() == 3,          "agg: 3 grupos")
-- MG sum=40
local mg_index = nil
for row_index=1,agged:nrows() do
    if agged:col("uf"):get(row_index) == "MG" then mg_index = row_index; break end
end
check(mg_index ~= nil,               "agg: grupo MG existe")
check(agged:col("v_sum"):get(mg_index) == 40, "agg v_sum MG=40")

-- transform
local transform_result = grouped_dataset:transform("mean","v")
check(transform_result:len() == source_dataset_10:nrows(),      "transform: mesmo tamanho do DS")
-- MG na posição 4 do DS original → média do grupo MG = 40
local mg_pos = nil
for row_index=1,source_dataset_10:nrows() do
    if source_dataset_10:col("uf"):get(row_index) == "MG" then mg_pos = row_index; break end
end
check(approximately_equal_2(transform_result:get(mg_pos), 40.0), "transform MG=40 (média do grupo)")

-- =====================================================================
-- Concat (de test_concat.lua)
-- =====================================================================

local source_dataset_11 = smaug.DataSet({
    {"uf",  {"SP","RJ"},  "string"},
    {"val", {10, 20},     "int64"},
})
local source_dataset_12 = smaug.DataSet({
    {"uf",  {"MG","SP"},  "string"},
    {"val", {30, 40},     "int64"},
})
local source_dataset_13 = smaug.DataSet({
    {"uf",  {"RS"},       "string"},
    {"val", {50},         "int64"},
})

-- ---- 2 DataSets via smaug.concat ----
local concatenated_result = smaug.concat({source_dataset_11, source_dataset_12})
check(concatenated_result:nrows() == 4,                         "concat 2: 4 linhas")
check(concatenated_result:ncols() == 2,                         "concat 2: 2 colunas")
check(concatenated_result:col("uf"):get(1) == "SP",             "concat 2: linha 1 uf=SP")
check(concatenated_result:col("uf"):get(3) == "MG",             "concat 2: linha 3 uf=MG")
check(concatenated_result:col("val"):get(1) == 10,              "concat 2: linha 1 val=10")
check(concatenated_result:col("val"):get(4) == 40,              "concat 2: linha 4 val=40")
check(concatenated_result:col("uf")._dtype == "string",         "concat 2: dtype string preservado")
check(concatenated_result:col("val")._dtype == "int64",         "concat 2: dtype int64 preservado")

-- ---- 3 DataSets ----
local concatenated_result_2 = smaug.concat({source_dataset_11, source_dataset_12, source_dataset_13})
check(concatenated_result_2:nrows() == 5,                         "concat 3: 5 linhas")
check(concatenated_result_2:col("uf"):get(5) == "RS",             "concat 3: linha 5 uf=RS")
check(concatenated_result_2:col("val"):get(5) == 50,              "concat 3: linha 5 val=50")

-- ---- método ds:concat(other) ----
local concatenated_result_3 = source_dataset_11:concat(source_dataset_12)
check(concatenated_result_3:nrows() == 4,                         "método concat: 4 linhas")
check(concatenated_result_3:col("val"):get(2) == 20,              "método concat: val linha 2=20")

-- ---- ds:concat({b, c}) ----
local concatenated_result_4 = source_dataset_11:concat({source_dataset_12, source_dataset_13})
check(concatenated_result_4:nrows() == 5,                        "método concat lista: 5 linhas")

-- ---- independência: mutar resultado não afeta originais ----
local concatenated_result_5 = smaug.concat({source_dataset_11, source_dataset_12})
concatenated_result_5:add_column("extra", smaug.Series({1,2,3,4}, "int64"))
check(not source_dataset_11:has_column("extra"),               "independência: original não alterado")

-- ---- com NA ----
local source_dataset_14 = smaug.DataSet({
    {"uf",  {"BA"},  "string"},
    {"val", {smaug.NA},    "int64"},
})
local concatenated_result_6 = smaug.concat({source_dataset_11, source_dataset_14})
check(concatenated_result_6:nrows() == 3,                        "concat com NA: 3 linhas")
check(concatenated_result_6:col("val"):is_null(3),               "concat com NA: null preservado")
check(not concatenated_result_6:col("val"):is_null(1),           "concat com NA: não-null intacto")

-- ---- float64 ----
local source_dataset_15 = smaug.DataSet({{"v",{1.5,2.5},"float64"}})
local source_dataset_16 = smaug.DataSet({{"v",{3.5},     "float64"}})
local concatenated_result_7 = smaug.concat({source_dataset_15, source_dataset_16})
check(concatenated_result_7:nrows() == 3,                         "concat float64: 3 linhas")
check(concatenated_result_7:col("v"):get(3) == 3.5,              "concat float64: valor correto")
check(concatenated_result_7:col("v")._dtype == "float64",         "concat float64: dtype preservado")

-- ---- bool ----
local source_dataset_17 = smaug.DataSet({{"ok",{true,false},"bool"}})
local source_dataset_18 = smaug.DataSet({{"ok",{true},      "bool"}})
local concatenated_result_8 = smaug.concat({source_dataset_17, source_dataset_18})
check(concatenated_result_8:nrows() == 3,                         "concat bool: 3 linhas")
check(concatenated_result_8:col("ok"):get(1) == true,             "concat bool: true preservado")
check(concatenated_result_8:col("ok"):get(2) == false,            "concat bool: false preservado")
check(concatenated_result_8:col("ok")._dtype == "bool",           "concat bool: dtype preservado")

-- ---- DataSet vazio como primeiro ----
local empty = smaug.DataSet({{"uf",{},"string"},{"val",{},"int64"}})
local concatenated_result_9 = smaug.concat({empty, source_dataset_11})
check(concatenated_result_9:nrows() == 2,                         "concat vazio+a: 2 linhas")

-- ---- DataSet vazio como segundo ----
local concatenated_result_10 = smaug.concat({source_dataset_11, empty})
check(concatenated_result_10:nrows() == 2,                        "concat a+vazio: 2 linhas")

-- ---- dois vazios ----
local concatenated_result_11 = smaug.concat({empty, empty})
check(concatenated_result_11:nrows() == 0,                        "concat vazio+vazio: 0 linhas")

-- ---- um único DataSet (cópia) ----
local concatenated_result_12 = smaug.concat({source_dataset_11})
check(concatenated_result_12:nrows() == 2,                         "concat 1 elem: 2 linhas (cópia)")
check(concatenated_result_12:col("uf"):get(1) == "SP",             "concat 1 elem: valor correto")

-- ---- erros esperados ----
local succeeded_6, unused_error_6 = pcall(function() smaug.concat({}) end)
check(not succeeded_6,                                 "erro: lista vazia")

local succeeded_7, unused_error_7 = pcall(function() smaug.concat({source_dataset_11, "nao_dataset"}) end)
check(not succeeded_7,                                 "erro: elemento não-DataSet")

-- coluna faltando
local bad_column = smaug.DataSet({{"outro",{1},"int64"}})
local succeeded_8, unused_error_8 = pcall(function() smaug.concat({source_dataset_11, bad_column}) end)
check(not succeeded_8,                                 "erro: coluna faltando")

-- dtype incompatível
local bad_datetime = smaug.DataSet({{"uf",{"X"},"string"},{"val",{1.5},"float64"}})
local succeeded_9, unused_error_9 = pcall(function() smaug.concat({source_dataset_11, bad_datetime}) end)
check(not succeeded_9,                                 "erro: dtype incompatível")

-- número de colunas diferente
local bad_nc = smaug.DataSet({{"uf",{"X"},"string"}})
local succeeded_10, unused_error_10 = pcall(function() smaug.concat({source_dataset_11, bad_nc}) end)
check(not succeeded_10,                                 "erro: ncols diferente")

-- =====================================================================
-- Join (de test_join.lua)
-- =====================================================================

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

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
local joined_dataset = pedidos:join(clientes, "cliente")   -- default = inner
check(joined_dataset:nrows() == 3,                         "inner: 3 linhas (C e D sem match)")
check(joined_dataset:ncols() == 4,                         "inner: 4 colunas")
check(joined_dataset:has_column("id"),                     "inner: tem id")
check(joined_dataset:has_column("cliente"),                "inner: tem cliente")
check(joined_dataset:has_column("valor"),                  "inner: tem valor")
check(joined_dataset:has_column("cidade"),                 "inner: tem cidade")
-- A aparece 2x (pedidos 1 e 3)
local city_names = {}
for row_index = 1, joined_dataset:nrows() do city_names[row_index] = joined_dataset:col("cidade"):get(row_index) end
check(city_names[1] == "SP" and city_names[2] == "RJ" and city_names[3] == "SP",
      "inner: cidades corretas (SP,RJ,SP)")
check(joined_dataset:col("id"):get(1) == 1,                "inner: id linha 1 = 1")
check(joined_dataset:col("id"):get(3) == 3,                "inner: id linha 3 = 3 (segundo A)")
-- C (pedido 4) não aparece
local values_2 = {}; for row_index=1,joined_dataset:nrows() do values_2[joined_dataset:col("id"):get(row_index)] = true end
check(not values_2[4],                              "inner: pedido 4 (C) excluído")

-- how explícito
local joined_dataset_2 = pedidos:join(clientes, "cliente", "inner")
check(joined_dataset_2:nrows() == 3,                        "inner explícito: 3 linhas")

-- ================================================================
-- LEFT JOIN
-- ================================================================
local joined_dataset_3 = pedidos:join(clientes, "cliente", "left")
check(joined_dataset_3:nrows() == 4,                         "left: 4 linhas (todos os pedidos)")
check(joined_dataset_3:col("cidade"):is_null(4),             "left: cidade NULL para C")
check(joined_dataset_3:col("cliente"):get(4) == "C",         "left: cliente C na linha 4")
check(not joined_dataset_3:col("cidade"):is_null(1),         "left: cidade não-null para A")
check(joined_dataset_3:col("cidade"):get(1) == "SP",         "left: cidade SP para A")

-- ================================================================
-- RIGHT JOIN
-- ================================================================
local joined_dataset_4 = pedidos:join(clientes, "cliente", "right")
check(joined_dataset_4:nrows() == 4,                         "right: 4 linhas (A×2, B, D)")
-- D aparece com NAs no lado esquerdo
local date_row = nil
for row_index = 1, joined_dataset_4:nrows() do
    if joined_dataset_4:col("cliente"):get(row_index) == "D" then date_row = row_index; break end
end
check(date_row ~= nil,                            "right: D presente")
check(joined_dataset_4:col("id"):is_null(date_row),             "right: id NULL para D")
check(joined_dataset_4:col("valor"):is_null(date_row),          "right: valor NULL para D")

-- ================================================================
-- OUTER JOIN
-- ================================================================
local joined_dataset_5 = pedidos:join(clientes, "cliente", "outer")
check(joined_dataset_5:nrows() == 5,                         "outer: 5 linhas (A×2, B, C, D)")
-- C: cidade NULL; D: id e valor NULL
local count_row, object_date_row = nil, nil
for row_index = 1, joined_dataset_5:nrows() do
    local element_value = joined_dataset_5:col("cliente"):get(row_index)
    if element_value == "C" then count_row = row_index end
    if element_value == "D" then object_date_row = row_index end
end
check(count_row ~= nil,                            "outer: C presente")
check(object_date_row ~= nil,                          "outer: D presente")
check(joined_dataset_5:col("cidade"):is_null(count_row),         "outer: cidade NULL para C")
check(joined_dataset_5:col("id"):is_null(object_date_row),           "outer: id NULL para D")

-- ================================================================
-- CHAVES DIFERENTES
-- ================================================================
local source_dataset_19 = smaug.DataSet({
    {"id_pedido", {1,2,3},   "int64"},
    {"val",       {10,20,30}, "int64"},
})
local source_dataset_20 = smaug.DataSet({
    {"id_cliente", {2,3,4},    "int64"},
    {"desc",       {"b","c","d"}, "string"},
})
local joined_dataset_6 = source_dataset_19:join(source_dataset_20, {"id_pedido","id_cliente"}, "inner")
check(joined_dataset_6:nrows() == 2,                         "chaves diff inner: 2 linhas (2,3)")
check(joined_dataset_6:has_column("id_pedido"),              "chaves diff: coluna esq presente")
check(joined_dataset_6:col("val"):get(1) == 20,              "chaves diff: val linha 1 = 20")
check(joined_dataset_6:col("desc"):get(1) == "b",            "chaves diff: desc linha 1 = b")

local joined_dataset_7 = source_dataset_19:join(source_dataset_20, {"id_pedido","id_cliente"}, "left")
check(joined_dataset_7:nrows() == 3,                        "chaves diff left: 3 linhas")
check(joined_dataset_7:col("desc"):is_null(1),              "chaves diff left: desc NULL para id=1")

-- ================================================================
-- SUFIXOS
-- ================================================================
local source_dataset_21 = smaug.DataSet({{"k",{1,2},"int64"},{"nome",{"a","b"},"string"},{"x",{10,20},"int64"}})
local source_dataset_22 = smaug.DataSet({{"k",{1,2},"int64"},{"nome",{"x","y"},"string"},{"y",{100,200},"int64"}})
local joined_dataset_8 = source_dataset_21:join(source_dataset_22, "k", "inner")
check(joined_dataset_8:has_column("nome_left"),              "sufixos: nome_left presente")
check(joined_dataset_8:has_column("nome_right"),             "sufixos: nome_right presente")
check(not joined_dataset_8:has_column("nome"),               "sufixos: nome sem sufixo ausente")
check(joined_dataset_8:has_column("x"),                      "sufixos: x sem sufixo (só em esq)")
check(joined_dataset_8:has_column("y"),                      "sufixos: y sem sufixo (só em dir)")
check(joined_dataset_8:col("nome_left"):get(1) == "a",       "sufixos: nome_left valor correto")
check(joined_dataset_8:col("nome_right"):get(1) == "x",      "sufixos: nome_right valor correto")

-- sufixos customizados
local joined_dataset_9 = source_dataset_21:join(source_dataset_22, "k", "inner", {"_esq","_dir"})
check(joined_dataset_9:has_column("nome_esq"),              "sufixos custom: nome_esq")
check(joined_dataset_9:has_column("nome_dir"),              "sufixos custom: nome_dir")

-- ================================================================
-- MÚLTIPLOS MATCHES (N para N)
-- ================================================================
local source_dataset_23 = smaug.DataSet({{"k",{1,1,2},"int64"},{"va",{10,20,30},"int64"}})
local source_dataset_24 = smaug.DataSet({{"k",{1,1,2},"int64"},{"vb",{100,200,300},"int64"}})
local joined_dataset_10 = source_dataset_23:join(source_dataset_24, "k", "inner")
-- 1×1 cruzado = 4 linhas para k=1, mais 1 para k=2
check(joined_dataset_10:nrows() == 5,                         "N×N: 5 linhas (2×2 + 1×1)")

-- ================================================================
-- DATASETS VAZIOS
-- ================================================================
local empty_2 = smaug.DataSet({{"k",{},"int64"},{"v",{},"int64"}})
local normal = smaug.DataSet({{"k",{1,2},"int64"},{"v",{10,20},"int64"}})

local joined_dataset_11 = empty_2:join(normal, "k", "inner")
check(joined_dataset_11:nrows() == 0,                        "vazio inner: 0 linhas")
local joined_dataset_12 = normal:join(empty_2, "k", "inner")
check(joined_dataset_12:nrows() == 0,                        "inner vazio: 0 linhas")
local joined_dataset_13 = normal:join(empty_2, "k", "left")
check(joined_dataset_13:nrows() == 2,                        "left com right vazio: 2 linhas")
check(joined_dataset_13:col("v_right"):is_null(1),           "left vazio: v_right NULL")
local joined_dataset_14 = empty_2:join(normal, "k", "outer")
check(joined_dataset_14:nrows() == 2,                        "outer esq-vazio: 2 linhas (do dir)")

-- ================================================================
-- CHAVE INT64
-- ================================================================
local source_dataset_25 = smaug.DataSet({{"id",{10,20,30},"int64"},{"a",{1,2,3},"int64"}})
local source_dataset_26 = smaug.DataSet({{"id",{20,30,40},"int64"},{"b",{20,30,40},"int64"}})
local joined_dataset_15 = source_dataset_25:join(source_dataset_26, "id", "inner")
check(joined_dataset_15:nrows() == 2,                        "chave int64 inner: 2 linhas")
check(joined_dataset_15:col("id"):get(1) == 20,              "chave int64: id=20")

-- ================================================================
-- ERROS ESPERADOS
-- ================================================================
local succeeded_11, unused_error_11 = pcall(function() pedidos:join("nao_dataset", "cliente") end)
check(not succeeded_11,                                 "erro: other não-DataSet")

local succeeded_12, unused_error_12 = pcall(function() pedidos:join(clientes, "inexistente") end)
check(not succeeded_12,                                 "erro: chave esq inexistente")

local succeeded_13, unused_error_13 = pcall(function() pedidos:join(clientes, {"cliente","inexistente"}) end)
check(not succeeded_13,                                 "erro: chave dir inexistente")

local succeeded_14, unused_error_14 = pcall(function() pedidos:join(clientes, "cliente", "bad") end)
check(not succeeded_14,                                 "erro: how inválido")

-- =====================================================================
-- Contrato 8 — NA em chave relacional é erro (join/groupby/pivot/pivot_table)
-- =====================================================================
local function error_message_of(callback)
    local succeeded_15, error_message = pcall(callback)
    return (not succeeded_15) and tostring(error_message) or nil
end

-- join: NA na chave simples → erro orientado (não casa NA com NA)
local left_nullable_key_dataset = smaug.DataSet({{"k", {"x", smaug.NA, "y"}, "string"}, {"v", {1,2,3}, "int64"}})
local right_key_dataset = smaug.DataSet({{"k", {"x", "y"}, "string"},     {"w", {9,8},    "int64"}})
local error_message = error_message_of(function() return left_nullable_key_dataset:join(right_key_dataset, "k") end)
check(error_message ~= nil and error_message:match("join") and error_message:match("'k'") and error_message:match("contém NA")
      and error_message:match("fillna") and error_message:match("dropna"), "C8 join: erro com mensagem padrão")

-- groupby: NA na chave → erro (mensagem padrão, agora menciona fillna)
local error_message_2 = error_message_of(function() return left_nullable_key_dataset:groupby("k"):count() end)
check(error_message_2 ~= nil and error_message_2:match("groupby") and error_message_2:match("'k'") and error_message_2:match("contém NA")
      and error_message_2:match("fillna"), "C8 groupby: erro com mensagem padrão (fillna)")

-- pivot e pivot_table: NA no index → erro (não descarta linha em silêncio)
local source_dataset_27 = smaug.DataSet({
    {"i", {"a", smaug.NA},   "string"},
    {"c", {"m", "n"},  "string"},
    {"v", {1, 2},      "int64"},
})
local error_message_3 = error_message_of(function() return source_dataset_27:pivot("i", "c", "v") end)
check(error_message_3 ~= nil and error_message_3:match("pivot") and error_message_3:match("'i'") and error_message_3:match("contém NA"),
      "C8 pivot: erro com mensagem padrão")
local error_message_4 = error_message_of(function() return source_dataset_27:pivot_table("i", "c", "v", "sum") end)
check(error_message_4 ~= nil and error_message_4:match("pivot_table") and error_message_4:match("'i'") and error_message_4:match("contém NA"),
      "C8 pivot_table: erro com mensagem padrão")

-- NA na COLUNA (não no index) do pivot também dispara
local source_dataset_28 = smaug.DataSet({
    {"i", {"a", "b"},  "string"},
    {"c", {"m", smaug.NA},   "string"},
    {"v", {1, 2},      "int64"},
})
local error_message_5 = error_message_of(function() return source_dataset_28:pivot("i", "c", "v") end)
check(error_message_5 ~= nil and error_message_5:match("'c'"), "C8 pivot: NA na coluna 'columns' dispara")

-- chave COMPOSTA: NA em qualquer coluna da chave dispara, nomeando-a
local source_dataset_29 = smaug.DataSet({
    {"k1", {"x", "y"}, "string"},
    {"k2", {"a", smaug.NA},  "string"},
    {"v",  {1, 2},     "int64"},
})
local error_message_6 = error_message_of(function() return source_dataset_29:groupby({"k1", "k2"}):count() end)
check(error_message_6 ~= nil and error_message_6:match("'k2'"), "C8 composta: nomeia a coluna culpada (k2)")
-- join valida AMBOS os lados: NA na chave do lado direito (forma {chave_esq, chave_dir})
local left_valid_key_dataset = smaug.DataSet({{"kl", {"x", "y"}, "string"}, {"v", {1, 2}, "int64"}})
local right_nullable_key_dataset = smaug.DataSet({{"kr", {"x", smaug.NA},  "string"}, {"w", {9, 8}, "int64"}})
local error_message_7 = error_message_of(function() return left_valid_key_dataset:join(right_nullable_key_dataset, {"kl", "kr"}) end)
check(error_message_7 ~= nil and error_message_7:match("'kr'"), "C8 join: valida chave do lado direito (kr)")

-- a coluna de VALORES pode conter NA (não é chave) — join com valor NA funciona
local left_nullable_value_dataset = smaug.DataSet({{"k", {"x", "y"}, "string"}, {"v", {1, smaug.NA}, "int64"}})
local right_value_dataset = smaug.DataSet({{"k", {"x", "y"}, "string"}, {"w", {9, 8}, "int64"}})
local succeeded_15 = pcall(function() return left_nullable_value_dataset:join(right_value_dataset, "k") end)
check(succeeded_15, "C8: NA em coluna de valores (não-chave) não dispara")

-- ===================================================================
-- L2: int64 > 2^53 em chave de join/groupby (correção via core/keys).
-- A chave passava por get()→double: dois int64 distintos acima de 2^53
-- colapsavam (join casava errado, groupby fundia grupos) e o valor da
-- chave saía degradado no resultado. keys.encode/value corrigem ambos.
-- ===================================================================
do
    local ffi = require("ffi")
    local exact_double_limit = ffi.new("int64_t", 9007199254740992LL)  -- 2^53
    local above_double_limit = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1

    -- groupby: a,b,a → 2 grupos (não funde)
    local sum_result_11 = smaug.DataSet({{"id", {exact_double_limit, above_double_limit, exact_double_limit}, "int64"}, {"v", {1, 10, 100}, "int64"}})
                   :groupby("id"):sum("v")
    check(sum_result_11:nrows() == 2, "L2 groupby int64>2^53 não funde grupos")
    local seen_exact_double_limit, seen_above_double_limit = false, false
    for row_index = 1, sum_result_11:nrows() do
        local key_series = sum_result_11:column("id"):get_raw(row_index)
        if key_series == exact_double_limit then seen_exact_double_limit = true elseif key_series == above_double_limit then seen_above_double_limit = true end
    end
    check(seen_exact_double_limit and seen_above_double_limit, "L2 groupby preserva valor exato da chave no resultado")

    -- join: ids distintos não casam; iguais casam e preservam valor
    local left_dataset = smaug.DataSet({{"id", {exact_double_limit}, "int64"}, {"lval", {100}, "int64"}})
    local different_key_dataset = smaug.DataSet({{"id", {above_double_limit}, "int64"}, {"rval", {200}, "int64"}})
    check(left_dataset:join(different_key_dataset, "id", "inner"):nrows() == 0, "L2 join ids distintos → 0 linhas")
    local same_key_dataset = smaug.DataSet({{"id", {exact_double_limit}, "int64"}, {"rval", {200}, "int64"}})
    local joined_dataset_16 = left_dataset:join(same_key_dataset, "id", "inner")
    check(joined_dataset_16:nrows() == 1, "L2 join ids iguais → 1 linha")
    check(joined_dataset_16:column("id"):get_raw(1) == exact_double_limit, "L2 join preserva valor exato da chave")
end

-- ===================================================================
-- 12.39: NaN em chave de agrupamento quebrava a ordem fraca estrita
-- `(a > b) - (a < b)` devolve 0 quando qualquer operando é NaN, então NaN
-- comparava IGUAL A TUDO. Isso torna o comparador inconsistente e o
-- comportamento do qsort INDEFINIDO — não era ordem esquisita, era UB. Um
-- único NaN corrompia o agrupamento das OUTRAS chaves também.
-- Corrigido com ordem TOTAL: NaN ao fim, e NaN igual a NaN (todas as linhas
-- com NaN formam um grupo). NaN é VALOR neste projeto (Contrato 9), então
-- agrupar por ele é legítimo — recusar trocaria erro por erro, a ordem total
-- troca por resultado certo.
-- ===================================================================
do
    local nan_value = 0/0

    -- 12.39.1 — o caso medido: 5 grupos para 3 valores, com 1.0 duplicado
    local source_dataset_30 = smaug.DataSet({ {"k", {1.0, nan_value, 1.0, nan_value, 2.0}, "float64"},
                               {"v", {10, 20, 30, 40, 50}, "int64"} })
    local sum_result_11 = source_dataset_30:groupby("k"):sum("v")
    check(sum_result_11:nrows() == 3, "12.39.1 três valores distintos → três grupos")

    -- as somas provam que o agrupamento é o certo, não só a contagem
    local key_series, value_series = sum_result_11:column("k"), sum_result_11:column("v")
    local group_sums = {}
    for row_index = 1, sum_result_11:nrows() do
        local element_value = key_series:get(row_index)
        group_sums[element_value ~= element_value and "nan" or tostring(element_value)] = value_series:get(row_index)
    end
    check(group_sums["1"] == 40,   "12.39.1 grupo 1.0 soma 10+30 (não ficou partido)")
    check(group_sums["2"] == 50,   "12.39.1 grupo 2.0 intacto")
    check(group_sums["nan"] == 60, "12.39.1 linhas com NaN formam UM grupo (20+40)")

    -- 12.39.2 — NaN não contamina as outras chaves: sem NaN o resultado é o
    -- mesmo para elas, o que prova que o bug era do comparador e não do dado
    local clean_dataset = smaug.DataSet({ {"k", {1.0, 1.0, 2.0}, "float64"},
                                  {"v", {10, 30, 50}, "int64"} })
    local sum_result_12 = clean_dataset:groupby("k"):sum("v")
    check(sum_result_12:nrows() == 2 and sum_result_12:column("v"):get(1) == 40,
          "12.39.2 mesmo resultado para 1.0 com e sem NaN na coluna")

    -- 12.39.3 — ordem total: NaN vai para o fim, de forma determinística
    local source_dataset_31 = smaug.DataSet({ {"k", {3.0, nan_value, 1.0, nan_value, 2.0}, "float64"},
                              {"v", {1, 1, 1, 1, 1}, "int64"} })
    local sum_result_13 = source_dataset_31:groupby("k"):sum("v")
    local column_result = sum_result_13:column("k")
    check(sum_result_13:nrows() == 4, "12.39.3 quatro grupos (1, 2, 3, NaN)")
    check(column_result:get(4) ~= column_result:get(4), "12.39.3 NaN ordena por último")
    check(sum_result_13:column("v"):get(4) == 2, "12.39.3 os dois NaN no mesmo grupo")

    -- 12.39.4 — join também usa o comparador e passou a casar NaN com NaN
    local source_dataset_32 = smaug.DataSet({ {"k", {1.0, nan_value, 2.0}, "float64"}, {"x", {1,2,3}, "int64"} })
    local source_dataset_33 = smaug.DataSet({ {"k", {1.0, nan_value}, "float64"},      {"y", {10,20}, "int64"} })
    check(source_dataset_32:join(source_dataset_33, "k"):nrows() == 2, "12.39.4 join casa 1.0 e NaN")

    -- 12.39.5 — int64 não tem NaN; o caminho não-float segue idêntico
    local source_dataset_34 = smaug.DataSet({ {"k", {1, 1, 2}, "int64"}, {"v", {10, 30, 50}, "int64"} })
    check(source_dataset_34:groupby("k"):sum("v"):nrows() == 2, "12.39.5 int64 intacto")
end

print(string.format("OK — %d checks passaram (DataSet: groupby, concat, join)", passed_checks))
