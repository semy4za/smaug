-- tests/series/test_categorical.lua
-- CategoricalSeries: factories, acesso, .cat accessor, comparações,
-- seleção, fillna, únicos, describe, astype, integração DataSet.
-- Baseado estritamente no API_INDEX v1.0.
-- Rode da raiz: luajit tests/series/test_categorical.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")

local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local function check_error(callback, message)
    local succeeded = pcall(callback)
    check(not succeeded, message .. " (deveria lançar erro)")
end

-- =====================================================================
-- 1. Factories e Estrutura
-- =====================================================================
do
    -- Construção pública de uma série categórica
    local nullable_categorical_series = smaug.Series({"SP", "RJ", "SP", smaug.NA, "MG"}, "categorical")
    check(nullable_categorical_series._dtype == "categorical", "dtype = categorical")
    check(nullable_categorical_series:len() == 5, "len = 5")
    check(nullable_categorical_series:get(1) == "SP", "get(1) = SP")
    check(nullable_categorical_series:get(4) == nil, "get(4) = nil (NA)")

    -- Levels: ordem de primeira aparição
    local category_levels = nullable_categorical_series.cat:levels()
    check(#category_levels == 3, "3 levels")
    check(category_levels[1] == "SP", "level[1] = SP")
    check(category_levels[2] == "RJ", "level[2] = RJ")
    check(category_levels[3] == "MG", "level[3] = MG")

    -- from_codes
    local from_codes_result = smaug.Series.Categorical.from_codes({1, 2, 1, smaug.NA, 3}, {"SP", "RJ", "MG"})
    check(from_codes_result:get(1) == "SP", "from_codes: 1→SP")
    check(from_codes_result:is_null(4), "from_codes: NA→null")

    -- Erro: code fora do range
    check_error(function()
        smaug.Series.Categorical.from_codes({1, 5}, {"A", "B", "C"})
    end, "from_codes: code fora do range")

    -- Guard de unicidade de níveis
    check_error(function()
        smaug.Series.Categorical.from_codes({1, 2}, {"a", "a"})
    end, "from_codes: nível duplicado literal")

    -- Série vazia
    local empty_categorical_series = smaug.Series({}, "categorical")
    check(empty_categorical_series:len() == 0, "vazio: len=0")
    check(#empty_categorical_series.cat:levels() == 0, "vazio: 0 levels")

    -- Série toda nula
    local all_null_categorical_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "categorical")
    check(all_null_categorical_series:get(1) == nil, "tudo NA: get=nil")
    check(all_null_categorical_series:count_nonnull() == 0, "tudo NA: count_nonnull=0")
end

-- =====================================================================
-- 2. Acesso e Mutação
-- =====================================================================
do
    local categorical_series = smaug.Series({"A", "B", "C"}, "categorical")

    -- is_null / set_null
    check(not categorical_series:is_null(1), "is_null(1) = false")
    categorical_series:set_null(2)
    check(categorical_series:is_null(2), "set_null(2): is_null=true")
    check(categorical_series:get(2) == nil, "get após set_null = nil")

    -- set: valor existente
    categorical_series:set(2, "A")
    check(categorical_series:get(2) == "A", "set existing level: A")

    -- set: valor novo (cria level)
    categorical_series:set(3, "Z")
    check(categorical_series:get(3) == "Z", "set novo level: Z")
    check(#categorical_series.cat:levels() == 4, "novo level criado (4 total)")

    -- append
    local categorical_series_2 = smaug.Series({"X"}, "categorical")
    categorical_series_2:append("Y")
    categorical_series_2:append(smaug.NA)
    categorical_series_2:append("X") -- reutiliza level
    check(categorical_series_2:len() == 4, "append: len=4")
    check(categorical_series_2:get(2) == "Y", "append Y")
    check(categorical_series_2:is_null(3), "append NA")

    -- count_nonnull
    local nullable_categorical_series = smaug.Series({"SP", "RJ", "SP", smaug.NA, "MG"}, "categorical")
    check(nullable_categorical_series:count_nonnull() == 4, "count_nonnull = 4")
end

-- =====================================================================
-- 3. .cat Accessor
-- =====================================================================
do
    local nullable_categorical_series = smaug.Series({"B", "A", smaug.NA, "C", "A"}, "categorical")

    -- codes()
    local codes = nullable_categorical_series.cat:codes()
    check(codes._dtype == "int64", "codes: dtype=int64")
    check(codes:is_null(3), "codes: NA → null")
    check(codes:get(1) == 1, "codes[1] = 1 (B)")
    check(codes:get(2) == 2, "codes[2] = 2 (A)")

    -- rename_categories
    local renamed = nullable_categorical_series.cat:rename_categories({A = "Alpha", B = "Beta"})
    check(renamed:get(1) == "Beta", "rename: B→Beta")
    check(nullable_categorical_series:get(1) == "B", "rename: original intacto")

    -- set_categories
    local set_categories_result = nullable_categorical_series.cat:set_categories({"C", "A"}) -- remove B
    check(set_categories_result:get(1) == nil, "set_categories: B removido → null")
    check(set_categories_result:get(4) == "C", "set_categories: C preservado")

    -- add_categories
    local add_categories_result = nullable_categorical_series.cat:add_categories({"D", "E"})
    check(#add_categories_result.cat:levels() == 5, "add_categories: 5 levels")

    -- remove_categories
    local removed_categories_series = nullable_categorical_series.cat:remove_categories({"A"})
    check(removed_categories_series:get(2) == nil, "remove_categories: A→null")
end

-- =====================================================================
-- 4. Comparações e Ordenação
-- =====================================================================
do
    local nullable_categorical_series = smaug.Series({"SP", "RJ", "SP", smaug.NA, "MG"}, "categorical")

    -- eq / ne
    local equality_mask = nullable_categorical_series:eq("SP")
    check(equality_mask._dtype == "bool", "eq: dtype=bool")
    check(equality_mask:get(1) == true, "eq: SP==SP")
    check(equality_mask:is_null(4), "eq: NA → NA")

    -- lt / gt / le / ge
    local categorical_series = smaug.Series({"B", "A", "C"}, "categorical")
    check(categorical_series:lt("B"):get(2) == true, "lt: A < B")
    check(categorical_series:gt("B"):get(3) == true, "gt: C > B")
    check(categorical_series:le("B"):get(1) == true, "le: B <= B")

    -- sort
    local csort = smaug.Series({"C", "A", "B", "A"}, "categorical")
    local sorted = csort:sort(true)
    check(sorted:get(1) == "A", "sort asc: 1º = A")
    check(sorted:get(4) == "C", "sort asc: 4º = C")

    -- sort com nulo → erro
    local cnull = smaug.Series({"A", smaug.NA, "B"}, "categorical")
    check_error(function() cnull:sort(true) end, "sort com null")

    -- argsort
    local indices = csort:argsort(true)
    check(type(indices) == "table", "argsort: retorna tabela")

    -- filter
    local equality_mask_2 = nullable_categorical_series:eq("SP")
    local filtered = nullable_categorical_series:filter(equality_mask_2)
    check(filtered:len() == 2, "filter: len=2")

    -- dropna
    local nullable_categorical_series_2 = smaug.Series({"A", smaug.NA, "B", smaug.NA, "C"}, "categorical")
    local dropped = nullable_categorical_series_2:dropna()
    check(dropped:len() == 3, "dropna: len=3")
end

-- =====================================================================
-- 5. Transformações e Preenchimento
-- =====================================================================
do
    -- fillna
    local nullable_categorical_series = smaug.Series({"A", smaug.NA, smaug.NA, "C"}, "categorical")
    local filled = nullable_categorical_series:fillna("B")
    check(filled:get(2) == "B", "fillna: NA preenchido")
    check(nullable_categorical_series:is_null(2), "fillna: original não mutado")

    -- ffill
    local nullable_categorical_series_2 = smaug.Series({smaug.NA, "SP", smaug.NA, "RJ", smaug.NA}, "categorical")
    local forward_fill_result = nullable_categorical_series_2:ffill()
    check(forward_fill_result:get(1) == nil, "ffill[1] = nil")
    check(forward_fill_result:get(3) == "SP", "ffill[3] = SP")

    -- bfill
    local backward_fill_result = nullable_categorical_series_2:bfill()
    check(backward_fill_result:get(1) == "SP", "bfill[1] = SP")
    check(backward_fill_result:get(5) == nil, "bfill[5] = nil")

    -- shift
    local categorical_series = smaug.Series({"A", "B", "C"}, "categorical")
    local shift_result = categorical_series:shift(1)
    check(shift_result:get(1) == nil, "shift(1)[1] = null")
    check(shift_result:get(2) == "A", "shift(1)[2] = A")

    -- map
    local nullable_categorical_series_3 = smaug.Series({"sp", "rj", smaug.NA}, "categorical")
    local uppercase_series = nullable_categorical_series_3:map(function(value) return value and string.upper(value) or nil end, "string")
    check(uppercase_series._dtype == "string", "map → string")
    check(uppercase_series:get(3) == nil, "map: null propaga")

    -- where / mask
    local categorical_series_2 = smaug.Series({"SP", "RJ", "MG"}, "categorical")
    local boolean_series = smaug.Series({true, false, true}, "bool")
    local conditional_series = categorical_series_2:where(boolean_series, "OUTRO")
    check(conditional_series:get(2) == "OUTRO", "where: substitui onde false")
    check(conditional_series:get(1) == "SP", "where: mantém onde true")

    local masked_series = categorical_series_2:mask(boolean_series, "OUTRO")
    check(masked_series:get(1) == "OUTRO", "mask: substitui onde true")
end

-- =====================================================================
-- 6. Estatísticas e Metadados
-- =====================================================================
do
    local nullable_categorical_series = smaug.Series({"C", "A", "B", "A", smaug.NA, "C"}, "categorical")

    -- unique / nunique
    local unique_values = nullable_categorical_series:unique()
    check(unique_values._dtype == "categorical", "unique: dtype=categorical")
    check(nullable_categorical_series:nunique() == 3, "nunique = 3")

    -- value_counts
    local value_counts = nullable_categorical_series:value_counts()
    check(type(value_counts) == "table", "value_counts: retorna tabela")

    -- describe
    local nullable_categorical_series_2 = smaug.Series({"SP", "RJ", "SP", smaug.NA, "MG", "SP"}, "categorical")
    local description = nullable_categorical_series_2:describe()
    check(description.dtype == "categorical", "describe: dtype")
    check(description.count == 5, "describe: count=5")
    check(description.top == "SP", "describe: top=SP")
    check(description.freq == 3, "describe: freq=3")

    -- min / max
    local nullable_categorical_series_3 = smaug.Series({"SP", "RJ", smaug.NA, "AM", "MG"}, "categorical")
    check(nullable_categorical_series_3:min() == "AM", "min() = AM")
    check(nullable_categorical_series_3:max() == "SP", "max() = SP")
end

-- =====================================================================
-- 7. Conversão de Tipo (astype)
-- =====================================================================
do
    local nullable_categorical_series = smaug.Series({"SP", smaug.NA, "RJ"}, "categorical")

    -- categorical → string
    local as_string = nullable_categorical_series:astype("string")
    check(as_string._dtype == "string", "astype cat→str")
    check(as_string:is_null(2), "astype: NA → null")

    -- categorical → float64
    local nullable_categorical_series_2 = smaug.Series({"1.5", "2.0", smaug.NA, "invalido"}, "categorical")
    local as_float64 = nullable_categorical_series_2:astype("float64")
    check(as_float64._dtype == "float64", "astype cat→f64")
    check(as_float64:is_null(4), "astype: invalido → null")

    -- string → categorical
    local nullable_string_series = smaug.Series({"SP", "RJ", smaug.NA}, "string")
    local as_categorical = nullable_string_series:astype("categorical")
    check(as_categorical._dtype == "categorical", "astype str→cat")

    -- dtype inválido
    check_error(function() nullable_categorical_series:astype("datetime") end, "astype cat→datetime")
end

-- =====================================================================
-- 8. Serialização (to_table)
-- =====================================================================
do
    local nullable_categorical_series = smaug.Series({"A", smaug.NA, "B"}, "categorical")

    -- to_table padrão
    local table_values = nullable_categorical_series:to_table()
    check(table_values[1] == "A", "to_table: [1]=A")
    check(table_values[2] == nil, "to_table: [2]=nil (NA)")

    -- to_table com na_value
    local table_values_2 = nullable_categorical_series:to_table("N/A")
    check(table_values_2[2] == "N/A", "to_table na_value: [2]=N/A")
end

-- =====================================================================
-- 9. Integração DataSet
-- =====================================================================
do
    local source_dataset = smaug.DataSet({
        {"cidade", {"SP", "RJ", "SP", "MG", "RJ"}, "categorical"},
        {"valor", {10.0, 20.0, 30.0, 40.0, 50.0}, "float64"},
    })

    check(source_dataset:has_column("cidade"), "DataSet: coluna existe")
    check(source_dataset:col("cidade")._dtype == "categorical", "DataSet: dtype=categorical")

    -- filter
    local equality_mask = source_dataset:col("cidade"):eq("SP")
    local filtered_result = source_dataset:filter(equality_mask)
    check(filtered_result:nrows() == 2, "DataSet filter: 2 linhas SP")

    -- sort_by
    local sorted_dataset = source_dataset:sort_by("cidade", true)
    check(sorted_dataset:col("cidade"):get(1) == "MG", "sort_by asc: 1º = MG")

    -- groupby
    local sum_result = source_dataset:groupby("cidade"):sum("valor")
    check(sum_result:nrows() == 3, "groupby sum: 3 grupos")

    -- assign
    local assign_result = source_dataset:assign("regiao", smaug.Series({"SE", "SE", "SE", "SE", "SE"}, "categorical"))
    check(assign_result:has_column("regiao"), "assign: coluna criada")

    -- concat
    local source_dataset_2 = smaug.DataSet({{"cidade", {"MG", "RS"}, "categorical"}, {"valor", {100.0, 200.0}, "float64"}})
    local categorical_dataset = smaug.concat({source_dataset:select({"cidade", "valor"}), source_dataset_2})
    check(categorical_dataset:nrows() == 7, "concat categorical: 7 linhas")
end

-- =====================================================================
-- 10. Erros e Limites (Edge Cases)
-- =====================================================================
do
    local categorical_series = smaug.Series({"A", "B", "C"}, "categorical")

    -- .cat em dtype errado
    check_error(function()
        smaug.Series({1.0, 2.0}, "float64").cat:levels()
    end, "erro: .cat em float64")

    -- Índices fora dos limites
    check_error(function() categorical_series:get(0) end, "erro: get(0)")
    check_error(function() categorical_series:get(100) end, "erro: get(100)")
    check_error(function() categorical_series:set(0, "X") end, "erro: set(0)")
    check_error(function() categorical_series:is_null(0) end, "erro: is_null(0)")

    -- Índice fracionário (deve errar, não retornar nil)
    check_error(function() return categorical_series:get(1.5) end, "erro: get(1.5) fracionário")
    check_error(function() return categorical_series:set(1.5, "x") end, "erro: set(1.5) fracionário")

    -- take com índice inválido
    check_error(function() categorical_series:take({1, 999}) end, "erro: take índice inválido")

    -- filter tamanho diferente
    check_error(function()
        local boolean_series = smaug.Series({true, false}, "bool")
        categorical_series:filter(boolean_series)
    end, "erro: filter tamanho diferente")

    -- fillna sem argumento
    check_error(function()
        smaug.Series({"A", smaug.NA}, "categorical"):fillna(nil)
    end, "erro: fillna nil")
end

-- =====================================================================
-- 11. Display e Metatables
-- =====================================================================
do
    local categorical_series = smaug.Series({"a", "b", "a", "c"}, "categorical")
    categorical_series._name = "cor"

    -- __tostring não vaza "table: 0x..."
    local series_text = tostring(categorical_series)
    check(series_text:find("^table:") == nil, "__tostring não vaza table:")

    -- .cat proxy legível
    local accessor_text = tostring(categorical_series.cat)
    check(accessor_text:find("^table:") == nil and accessor_text:find(".cat", 1, true) ~= nil, ".cat proxy legível")
end

print(string.format("OK — %d checks passaram (Series: categorical)", passed_checks))
