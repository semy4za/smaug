-- Rode da raiz: luajit tests/dataset/test_relational.lua
-- Contratos: docs/CONTRACT.md (NA em chaves; NA != NaN), docs/API_INDEX.md.
-- Revisão: docs/TEST_SUITE_REWRITE_REVIEW.md, R01/R09 e camada Relacional.
-- docs/COVERAGE.md mede o backend C no commit 51184cb, não este módulo Lua.
-- Vazios, máscaras, tipos e ordenação abaixo exercitam a fronteira Lua/C;
-- não demonstram cobertura de OOM nem substituem uma medição instrumentada.
--
-- Migração: os antigos blocos groupby/estendido, concat, join, C8, L2 e
-- 12.39 foram substituídos pelos casos nomeados abaixo. Resultados completos
-- substituem checks isolados de tamanho, presença ou ausência de crash.
-- Pendências de contrato: API_INDEX descreve count como não-nulos e o padrão
-- de pivot_table como mean; o código conta linhas e usa sum. Aqui count usa
-- dados completos e pivot_table recebe aggfunc explícito. A sintaxe pública
-- de join composto também precisa distinguir lista de chaves de {esq, dir}.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local cases = {}

local function check(condition, message)
    if not condition then error(message, 2) end
end

local function test(name, callback)
    cases[#cases + 1] = {name = name, run = callback}
end

local function expect_error(callback, fragments)
    local succeeded, message = pcall(callback)
    check(not succeeded, "era esperado um erro")
    message = tostring(message)
    for unused_index, fragment in ipairs(fragments) do
        check(message:find(fragment, 1, true), "erro sem '" .. fragment .. "': " .. message)
    end
end

-- Comparação independente: não usa keys.encode, sort, join ou agregações
-- do Smaug para construir o esperado. int64 nunca passa por tonumber.
-- Tolerância é opt-in, somente para resultados estatísticos destas fixtures.
local function cell_matches(series, row_index, expected, tolerance)
    if expected == smaug.NA then return series:is_null(row_index) end
    if series:is_null(row_index) then return false end
    local actual
    if series._dtype == "int64" then actual = series:get_raw(row_index)
    else actual = series:get(row_index) end
    if type(expected) == "number" and expected ~= expected then
        return type(actual) == "number" and actual ~= actual
    end
    if actual == expected then return true end
    if tolerance and type(actual) == "number" and type(expected) == "number"
        and math.abs(actual) < math.huge and math.abs(expected) < math.huge then
        return math.abs(actual - expected) <= tolerance * math.max(1, math.abs(expected))
    end
    return false
end

local function expect_series(series, dtype, values, tolerance)
    check(series._dtype == dtype, "dtype esperado: " .. dtype .. "; recebido: " .. series._dtype)
    check(series:len() == #values, "comprimento esperado: " .. #values .. "; recebido: " .. series:len())
    for row_index, expected in ipairs(values) do
        check(cell_matches(series, row_index, expected, tolerance),
            "valor/máscara incorreto na posição " .. row_index .. "; esperado: " .. tostring(expected))
    end
end

-- schema = {{nome, dtype, tolerância opcional}, ...}; rows inclui NA explícito.
-- A comparação sem ordem consome cada linha uma vez: duplicatas não somem
-- num mapa. Ordem de colunas pode ser omitida em agg (spec é um mapa) e join.
local function expect_dataset(dataset, schema, rows, unordered_rows, unordered_columns)
    check(dataset:nrows() == #rows, "linhas esperadas: " .. #rows .. "; recebidas: " .. dataset:nrows())
    check(dataset:ncols() == #schema, "colunas esperadas: " .. #schema .. "; recebidas: " .. dataset:ncols())
    local columns = dataset:columns()
    for column_index, definition in ipairs(schema) do
        local name, dtype = definition[1], definition[2]
        check(dataset:has_column(name), "coluna ausente: " .. name)
        check(dataset:col(name)._dtype == dtype, "dtype incorreto: " .. name)
        if not unordered_columns then check(columns[column_index] == name, "ordem de colunas: " .. name) end
    end
    local consumed = {}
    for expected_index, expected_row in ipairs(rows) do
        check(#expected_row == #schema, "fixture com número de células incorreto")
        local matched = false
        local first_index = unordered_rows and 1 or expected_index
        local last_index = unordered_rows and dataset:nrows() or expected_index
        for actual_index = first_index, last_index do
            if not consumed[actual_index] then
                local equal = true
                for column_index, definition in ipairs(schema) do
                    if not cell_matches(dataset:col(definition[1]), actual_index,
                        expected_row[column_index], definition[3]) then
                        equal = false
                        break
                    end
                end
                if equal then
                    consumed[actual_index], matched = true, true
                    break
                end
            end
        end
        check(matched, "linha esperada " .. expected_index .. " ausente/incorreta (incluindo multiplicidade)")
    end
end

-- GroupBy: seleção de colunas, reduções, broadcast, chaves e precisão.

test("groupby: count, seleção explícita e todas as colunas numéricas", function()
    local sales = smaug.DataSet({
        {"state", {"SP", "RJ", "SP", "MG", "SP", "RJ"}, "string"},
        {"sales", {10, 20, 30, 40, 50, 60}, "int64"},
        {"cost", {1.5, 2.5, 3.5, 4.5, 5.5, 6.5}, "float64"},
        {"label", {"a", "b", "c", "d", "e", "f"}, "string"},
    })
    local grouped = sales:groupby("state")
    expect_dataset(grouped:count(), {{"state", "string"}, {"count", "int64"}},
        {{"MG", 1}, {"RJ", 2}, {"SP", 3}})
    local sum_schema = {{"state", "string"}, {"sales", "int64"}, {"cost", "float64"}}
    local sum_rows = {{"MG", 40, 4.5}, {"RJ", 80, 9}, {"SP", 90, 10.5}}
    expect_dataset(grouped:sum(), sum_schema, sum_rows)
    expect_dataset(grouped:sum("sales", "cost"), sum_schema, sum_rows)
    expect_dataset(grouped:sum("sales"), {{"state", "string"}, {"sales", "int64"}},
        {{"MG", 40}, {"RJ", 80}, {"SP", 90}})
end)

test("groupby: reduções completas, singleton e valores repetidos", function()
    -- A={2,8,2}, B={3,7}, C={11}; ordem de entrada difere da ordem dos grupos.
    local source = smaug.DataSet({
        {"key", {"B", "A", "C", "A", "B", "A"}, "string"},
        {"value", {3, 2, 11, 8, 7, 2}, "int64"},
    })
    local grouped = source:groupby("key")
    local reductions = {
        {"sum", "int64", {12, 10, 11}},
        {"mean", "float64", {4, 5, 11}},
        {"min", "int64", {2, 3, 11}},
        {"max", "int64", {8, 7, 11}},
        {"var", "float64", {12, 8, smaug.NA}}, -- amostral: divide por n-1
        {"std", "float64", {math.sqrt(12), math.sqrt(8), smaug.NA}},
        {"median", "float64", {2, 5, 11}},
        {"first", "int64", {2, 3, 11}},
        {"last", "int64", {2, 7, 11}},
        {"prod", "int64", {32, 21, 11}},
        {"nunique", "int64", {2, 2, 1}},
    }
    for unused_index, reduction in ipairs(reductions) do
        local name, dtype, expected = unpack(reduction)
        expect_dataset(grouped[name](grouped, "value"), {{"key", "string"}, {"value", dtype, 1e-12}},
            {{"A", expected[1]}, {"B", expected[2]}, {"C", expected[3]}})
    end
end)

test("groupby: NA ignorado, first/last e grupo totalmente nulo", function()
    local source = smaug.DataSet({
        {"key", {"A", "B", "A", "C", "A", "B", "A"}, "string"},
        {"value", {smaug.NA, smaug.NA, 4, 9, 10, smaug.NA, smaug.NA}, "float64"},
    })
    local grouped = source:groupby("key")
    local reductions = {
        {"sum", {14, 0, 9}}, {"mean", {7, smaug.NA, 9}},
        {"min", {4, smaug.NA, 9}}, {"max", {10, smaug.NA, 9}},
        {"first", {4, smaug.NA, 9}}, {"last", {10, smaug.NA, 9}},
        {"var", {18, smaug.NA, smaug.NA}},
        {"std", {math.sqrt(18), smaug.NA, smaug.NA}},
        {"median", {7, smaug.NA, 9}},
    }
    for unused_index, reduction in ipairs(reductions) do
        local name, expected = reduction[1], reduction[2]
        expect_dataset(grouped[name](grouped, "value"), {{"key", "string"}, {"value", "float64", 1e-12}},
            {{"A", expected[1]}, {"B", expected[2]}, {"C", expected[3]}})
    end
    expect_dataset(grouped:nunique("value"), {{"key", "string"}, {"value", "int64"}},
        {{"A", 2}, {"B", 0}, {"C", 1}})
end)

test("groupby: quantile interpola e trata extremos, singleton e NA", function()
    local source = smaug.DataSet({
        {"key", {"A", "A", "A", "B", "C"}, "string"},
        {"value", {10, smaug.NA, 30, 7, smaug.NA}, "float64"},
    })
    local grouped = source:groupby("key")
    for unused_index, fixture in ipairs({{0, 10}, {0.25, 15}, {0.5, 20}, {1, 30}}) do
        expect_dataset(grouped:quantile(fixture[1], "value"), {{"key", "string"}, {"value", "float64"}},
            {{"A", fixture[2]}, {"B", 7}, {"C", smaug.NA}})
    end
    for unused_index, invalid in ipairs({-0.1, 1.1, "0.5"}) do
        expect_error(function() grouped:quantile(invalid, "value") end, {"quantile", "0", "1"})
    end
end)

test("groupby: agg verifica todas as células e transform alinha à entrada", function()
    local source = smaug.DataSet({
        {"state", {"SP", "RJ", "SP", "MG", "RJ", "SP"}, "string"},
        {"value", {10, 20, 30, 40, 50, 20}, "float64"},
    })
    local grouped = source:groupby("state")
    expect_dataset(grouped:agg({value = {"sum", "mean", "std"}}),
        {{"state", "string"}, {"value_sum", "float64"}, {"value_mean", "float64"}, {"value_std", "float64", 1e-12}},
        {{"MG", 40, 40, smaug.NA}, {"RJ", 70, 35, math.sqrt(450)}, {"SP", 60, 20, 10}}, false, true)
    expect_dataset(grouped:agg({value = "sum"}), {{"state", "string"}, {"value_sum", "float64"}},
        {{"MG", 40}, {"RJ", 70}, {"SP", 60}})
    expect_series(grouped:transform("mean", "value"), "float64", {20, 35, 20, 40, 35, 20})
    expect_series(grouped:transform("sum", "value"), "float64", {60, 70, 60, 40, 70, 60})
    expect_series(source:col("value"), "float64", {10, 20, 30, 40, 50, 20})
    expect_error(function() grouped:agg(123) end, {"agg", "tabela"})
    expect_error(function() grouped:agg({missing = "sum"}) end, {"agg", "missing"})
    expect_error(function() grouped:transform("mean", "missing") end, {"transform", "missing"})
end)

test("groupby: agg rejeita nome de função desconhecido com erro orientado", function()
    local source = smaug.DataSet({{"key", {"A"}, "string"}, {"value", {1}, "int64"}})
    expect_error(function() source:groupby("key"):agg({value = "unknown"}) end, {"agg", "desconhecida"})
end)

test("groupby: transform rejeita nome de função desconhecido com erro orientado", function()
    local source = smaug.DataSet({{"key", {"A"}, "string"}, {"value", {1}, "int64"}})
    expect_error(function() source:groupby("key"):transform("unknown", "value") end, {"transform", "desconhecida"})
end)

test("groupby: funções inválidas são rejeitadas também sem grupos", function()
    for unused_index, values in ipairs({{}, {1}}) do
        local source = smaug.DataSet({
            {"key", #values == 0 and {} or {"A"}, "string"}, {"value", values, "int64"},
        })
        local grouped = source:groupby("key")
        for unused_invalid_index, invalid in ipairs({"unknown", 42, false}) do
            expect_error(function() grouped:agg({value = invalid}) end, {"agg", "desconhecida"})
            expect_error(function() grouped:transform(invalid, "value") end, {"transform", "desconhecida"})
        end
    end
end)

test("groupby: agg e transform aceitam callbacks com índices do grupo", function()
    local source = smaug.DataSet({
        {"key", {"B", "A", "B"}, "string"}, {"value", {10, 20, 30}, "float64"},
    })
    local function weighted_sum(series, row_indices)
        local total = 0
        for unused_index, row_index in ipairs(row_indices) do
            total = total + series:get(row_index) * row_index
        end
        return total
    end
    local grouped = source:groupby("key")
    expect_dataset(grouped:agg({value = weighted_sum}), {{"key", "string"}, {"value", "float64"}},
        {{"A", 40}, {"B", 100}})
    expect_series(grouped:transform(weighted_sum, "value"), "float64", {100, 40, 100})
end)

test("groupby: chaves int64, bool e composta preservam schema e valores", function()
    local years = smaug.DataSet({{"year", {2024, 2023, 2024}, "int64"}, {"value", {2, 5, 8}, "int64"}})
    expect_dataset(years:groupby("year"):sum(), {{"year", "int64"}, {"value", "int64"}}, {{2023, 5}, {2024, 10}})
    local flags = smaug.DataSet({{"active", {true, false, true}, "bool"}, {"value", {2, 5, 8}, "int64"}})
    expect_dataset(flags:groupby("active"):sum(), {{"active", "bool"}, {"value", "int64"}}, {{false, 5}, {true, 10}})
    local source = smaug.DataSet({
        {"state", {"SP", "SP", "RJ", "RJ", "SP"}, "string"},
        {"year", {2023, 2024, 2023, 2023, 2023}, "int64"},
        {"value", {10, 20, 30, 40, 50}, "int64"},
    })
    expect_dataset(source:groupby({"state", "year"}):sum(),
        {{"state", "string"}, {"year", "int64"}, {"value", "int64"}},
        {{"RJ", 2023, 70}, {"SP", 2023, 60}, {"SP", 2024, 20}})
    expect_dataset(source:groupby({"state", "year"}):count(),
        {{"state", "string"}, {"year", "int64"}, {"count", "int64"}},
        {{"RJ", 2023, 2}, {"SP", 2023, 2}, {"SP", 2024, 1}})
end)

test("groupby: chaves compostas não colidem com separadores no texto", function()
    local source = smaug.DataSet({
        {"first", {"a\1string:b", "a", "a\1string:b"}, "string"},
        {"second", {"c", "b\1string:c", "c"}, "string"},
        {"value", {1, 10, 100}, "int64"},
    })
    expect_dataset(source:groupby({"first", "second"}):sum("value"),
        {{"first", "string"}, {"second", "string"}, {"value", "int64"}},
        {{"a", "b\1string:c", 10}, {"a\1string:b", "c", 101}})
end)

test("groupby: vazio preserva schema e argumentos inválidos falham", function()
    local empty = smaug.DataSet({{"key", {}, "string"}, {"value", {}, "int64"}})
    local grouped = empty:groupby("key")
    expect_dataset(grouped:sum(), {{"key", "string"}, {"value", "int64"}}, {})
    expect_dataset(grouped:mean(), {{"key", "string"}, {"value", "float64"}}, {})
    expect_dataset(grouped:count(), {{"key", "string"}, {"count", "int64"}}, {})
    expect_series(grouped:transform("mean", "value"), "float64", {})
    expect_error(function() empty:groupby("missing") end, {"groupby", "missing"})
    expect_error(function() empty:groupby(123) end, {"groupby", "string"})
    expect_error(function() empty:groupby({}) end, {"groupby", "pelo menos"})
    expect_error(function() grouped:sum("missing") end, {"agg", "missing"})
end)

-- Concat: todas as formas públicas usam o mesmo esperado literal.

test("concat: ordem, dtypes e máscaras em todas as formas de chamada", function()
    local first = smaug.DataSet({
        {"text", {"SP", ""}, "string"}, {"integer", {10, smaug.NA}, "int64"},
        {"real", {1.5, smaug.NA}, "float64"}, {"flag", {true, false}, "bool"},
    })
    -- Ordem diferente de colunas: alinhamento deve ser por nome.
    local second = smaug.DataSet({
        {"flag", {smaug.NA}, "bool"}, {"real", {3.5}, "float64"},
        {"integer", {30}, "int64"}, {"text", {smaug.NA}, "string"},
    })
    local third = smaug.DataSet({
        {"text", {"RS"}, "string"}, {"integer", {40}, "int64"},
        {"real", {4.5}, "float64"}, {"flag", {true}, "bool"},
    })
    local schema = {{"text", "string"}, {"integer", "int64"}, {"real", "float64"}, {"flag", "bool"}}
    local two_rows = {{"SP", 10, 1.5, true}, {"", smaug.NA, smaug.NA, false}, {smaug.NA, 30, 3.5, smaug.NA}}
    local three_rows = {two_rows[1], two_rows[2], two_rows[3], {"RS", 40, 4.5, true}}
    expect_dataset(smaug.concat({first, second}), schema, two_rows)
    expect_dataset(first:concat(second), schema, two_rows)
    expect_dataset(smaug.concat({first, second, third}), schema, three_rows)
    expect_dataset(first:concat({second, third}), schema, three_rows)
    expect_dataset(first, schema, {two_rows[1], two_rows[2]})
end)

test("concat: vazios e cópia de um único dataset", function()
    local empty = smaug.DataSet({{"key", {}, "string"}, {"value", {}, "int64"}})
    local source = smaug.DataSet({{"key", {"a", "b"}, "string"}, {"value", {1, 2}, "int64"}})
    local schema, rows = {{"key", "string"}, {"value", "int64"}}, {{"a", 1}, {"b", 2}}
    expect_dataset(smaug.concat({empty, source}), schema, rows)
    expect_dataset(smaug.concat({source, empty}), schema, rows)
    expect_dataset(smaug.concat({empty, empty}), schema, {})
    expect_dataset(smaug.concat({source}), schema, rows)
    local copy = smaug.concat({source})
    -- col() devolve uma view protegida por COW. Atualizar o frame exige
    -- recolocar a coluna alterada pela API pública update_column().
    local copied_values, copied_keys = copy:col("value"), copy:col("key")
    copied_values:set(1, 99)
    copied_keys:set(2, "changed")
    copy:update_column("value", copied_values)
    copy:update_column("key", copied_keys)
    copy:add_column("extra", smaug.Series({5, 6}, "int64"))
    expect_dataset(source, schema, rows)
    local source_values = source:col("value")
    source_values:set(2, 88)
    source:update_column("value", source_values)
    expect_series(source:col("value"), "int64", {1, 88})
    expect_series(copy:col("value"), "int64", {99, 2})
    expect_series(copy:col("key"), "string", {"a", "changed"})
end)

test("concat: rejeita lista inválida e cada incompatibilidade de schema", function()
    local source = smaug.DataSet({{"key", {"a"}, "string"}, {"value", {1}, "int64"}})
    expect_error(function() smaug.concat({}) end, {"concat", "lista"})
    expect_error(function() smaug.concat("invalid") end, {"concat", "lista"})
    expect_error(function() smaug.concat({"invalid"}) end, {"concat", "elemento 1", "DataSet"})
    expect_error(function() smaug.concat({source, "invalid"}) end, {"concat", "elemento 2", "DataSet"})
    expect_error(function() source:concat(123) end, {"concat", "DataSet"})
    local missing = smaug.DataSet({{"key", {"b"}, "string"}, {"other", {2}, "int64"}})
    expect_error(function() smaug.concat({source, missing}) end, {"concat", "coluna 'value'"})
    local fewer = smaug.DataSet({{"key", {"b"}, "string"}})
    expect_error(function() smaug.concat({source, fewer}) end, {"concat", "número de colunas"})
    local incompatible = smaug.DataSet({{"key", {"b"}, "string"}, {"value", {2.5}, "float64"}})
    expect_error(function() smaug.concat({source, incompatible}) end, {"concat", "value", "dtype"})
    expect_dataset(source, {{"key", "string"}, {"value", "int64"}}, {{"a", 1}})
end)

-- Join: referência por produto cartesiano de listas, sem hashing/keys.encode.
-- Fixtures são {chave, payload}; o modelo preserva todas as multiplicidades.
local function reference_join(left_rows, right_rows, how)
    local result = {}
    for unused_index, left_row in ipairs(left_rows) do
        local matched = false
        for unused_index, right_row in ipairs(right_rows) do
            if left_row[1] == right_row[1] then
                result[#result + 1] = {left_row[1], left_row[2], right_row[2]}
                matched = true
            end
        end
        if not matched and (how == "left" or how == "outer") then
            result[#result + 1] = {left_row[1], left_row[2], smaug.NA}
        end
    end
    if how == "right" or how == "outer" then
        for unused_index, right_row in ipairs(right_rows) do
            local matched = false
            for unused_index, left_row in ipairs(left_rows) do
                if left_row[1] == right_row[1] then matched = true; break end
            end
            if not matched then result[#result + 1] = {right_row[1], smaug.NA, right_row[2]} end
        end
    end
    return result
end

local function join_input(rows, payload_name)
    local keys, payloads = {}, {}
    for row_index, row in ipairs(rows) do keys[row_index], payloads[row_index] = row[1], row[2] end
    return smaug.DataSet({{"key", keys, "string"}, {payload_name, payloads, "int64"}})
end

for unused_index, fixture in ipairs({
    {name = "1:1", left = {{"B", 20}, {"A", 10}}, right = {{"A", 100}, {"B", 200}}},
    {name = "1:N", left = {{"A", 10}}, right = {{"A", 100}, {"A", 200}}},
    {name = "N:1", left = {{"A", 10}, {"A", 20}}, right = {{"A", 100}}},
    {name = "N:N e linhas idênticas", left = {{"A", 10}, {"A", 10}, {"B", 30}},
        right = {{"A", 100}, {"A", 200}, {"B", 300}}},
    {name = "matches e órfãos", left = {{"A", 10}, {"C", 30}, {"A", 20}}, right = {{"A", 100}, {"D", 400}}},
    {name = "sem match", left = {{"A", 10}}, right = {{"B", 20}}},
    {name = "esquerda vazia", left = {}, right = {{"A", 10}, {"B", 20}}},
    {name = "direita vazia", left = {{"A", 10}, {"B", 20}}, right = {}},
    {name = "ambos vazios", left = {}, right = {}},
    {name = "NA nos valores", left = {{"A", smaug.NA}, {"B", 2}}, right = {{"A", 9}, {"B", smaug.NA}}},
}) do
    for unused_index, how in ipairs({"inner", "left", "right", "outer"}) do
        test("join: " .. fixture.name .. " / " .. how, function()
            local left = join_input(fixture.left, "left_value")
            local right = join_input(fixture.right, "right_value")
            local expected = reference_join(fixture.left, fixture.right, how)
            expect_dataset(left:join(right, "key", how),
                {{"key", "string"}, {"left_value", "int64"}, {"right_value", "int64"}}, expected, true, true)
            expect_dataset(left, {{"key", "string"}, {"left_value", "int64"}}, fixture.left)
            expect_dataset(right, {{"key", "string"}, {"right_value", "int64"}}, fixture.right)
        end)
    end
end

test("join: inner por padrão preserva a sequência dos matches", function()
    local left = join_input({{"B", 20}, {"A", 10}, {"B", 30}}, "left_value")
    local right = join_input({{"A", 100}, {"B", 200}}, "right_value")
    expect_dataset(left:join(right, "key"),
        {{"key", "string"}, {"left_value", "int64"}, {"right_value", "int64"}},
        {{"B", 20, 200}, {"A", 10, 100}, {"B", 30, 200}})
end)

test("join: nomes distintos de chave em inner, left e outer", function()
    local left = smaug.DataSet({{"order_id", {1, 2, 3}, "int64"}, {"value", {10, 20, 30}, "int64"}})
    local right = smaug.DataSet({{"customer_id", {2, 3, 4}, "int64"}, {"label", {"b", "c", "d"}, "string"}})
    local schema = {{"order_id", "int64"}, {"value", "int64"}, {"label", "string"}}
    expect_dataset(left:join(right, {"order_id", "customer_id"}, "inner"), schema, {{2, 20, "b"}, {3, 30, "c"}})
    expect_dataset(left:join(right, {"order_id", "customer_id"}, "left"), schema,
        {{1, 10, smaug.NA}, {2, 20, "b"}, {3, 30, "c"}})
    expect_dataset(left:join(right, {"order_id", "customer_id"}, "outer"), schema,
        {{1, 10, smaug.NA}, {2, 20, "b"}, {3, 30, "c"}, {4, smaug.NA, "d"}})
end)

test("join: sufixos resolvem conflitos sem trocar os valores de lado", function()
    local left = smaug.DataSet({{"key", {1, 2}, "int64"}, {"name", {"a", "b"}, "string"}, {"quantity", {10, 20}, "int64"}})
    local right = smaug.DataSet({{"key", {1, 2}, "int64"}, {"name", {"x", "y"}, "string"}, {"price", {1.5, 2.5}, "float64"}})
    for unused_index, suffixes in ipairs({{"_left", "_right"}, {"_esq", "_dir"}}) do
        expect_dataset(left:join(right, "key", "inner", suffixes),
            {{"key", "int64"}, {"name" .. suffixes[1], "string"}, {"quantity", "int64"},
             {"name" .. suffixes[2], "string"}, {"price", "float64"}},
            {{1, "a", 10, "x", 1.5}, {2, "b", 20, "y", 2.5}})
    end
    expect_dataset(left:join(right, "key"),
        {{"key", "int64"}, {"name_left", "string"}, {"quantity", "int64"}, {"name_right", "string"}, {"price", "float64"}},
        {{1, "a", 10, "x", 1.5}, {2, "b", 20, "y", 2.5}})
end)

test("join: argumentos inválidos geram erros orientados", function()
    local left = join_input({{"A", 1}}, "left_value")
    local right = join_input({{"A", 2}}, "right_value")
    expect_error(function() left:join("invalid", "key") end, {"join", "other", "DataSet"})
    expect_error(function() left:join(right, "missing") end, {"join", "esquerda", "missing"})
    expect_error(function() left:join(right, {"key", "missing"}) end, {"join", "direita", "missing"})
    expect_error(function() left:join(right, "key", "invalid") end, {"join", "how"})
    expect_error(function() left:join(right, 123) end, {"join", "on"})
end)

-- Regressões L2 e 12.39: esperado literal exato e máscara separada de NaN.

test("int64: groupby e join distinguem vizinhos de 2^53 e preservam chaves", function()
    local source = smaug.DataSet({
        {"key", {9007199254740993LL, 9007199254740992LL, 9007199254740993LL}, "int64"},
        {"value", {1, 10, 100}, "int64"},
    })
    expect_dataset(source:groupby("key"):sum("value"), {{"key", "int64"}, {"value", "int64"}},
        {{9007199254740992LL, 10}, {9007199254740993LL, 101}})
    local right = smaug.DataSet({{"key", {9007199254740993LL}, "int64"}, {"other", {7}, "int64"}})
    expect_dataset(source:join(right, "key"), {{"key", "int64"}, {"value", "int64"}, {"other", "int64"}},
        {{9007199254740993LL, 1, 7}, {9007199254740993LL, 100, 7}})
    local different = smaug.DataSet({{"key", {9007199254740992LL}, "int64"}})
    expect_dataset(different:join(right, "key"), {{"key", "int64"}, {"other", "int64"}}, {})
end)

test("NaN: groupby mantém os grupos finitos e ordena NaN por último", function()
    local nan_value = 0 / 0
    local source = smaug.DataSet({
        {"key", {1, nan_value, 1, nan_value, 2, 3}, "float64"},
        {"value", {10, 20, 30, 40, 50, 60}, "int64"},
    })
    expect_dataset(source:groupby("key"):sum("value"), {{"key", "float64"}, {"value", "int64"}},
        {{1, 40}, {2, 50}, {3, 60}, {nan_value, 60}})
    local finite = smaug.DataSet({{"key", {1, 1, 2, 3}, "float64"}, {"value", {10, 30, 50, 60}, "int64"}})
    expect_dataset(finite:groupby("key"):sum("value"), {{"key", "float64"}, {"value", "int64"}},
        {{1, 40}, {2, 50}, {3, 60}})
end)

test("NaN: join casa NaN com NaN sem perder ou inventar pares", function()
    local nan_value = 0 / 0
    local left = smaug.DataSet({{"key", {1, nan_value, 2, nan_value}, "float64"}, {"left_value", {1, 2, 3, 4}, "int64"}})
    local right = smaug.DataSet({{"key", {1, nan_value}, "float64"}, {"right_value", {10, 20}, "int64"}})
    expect_dataset(left:join(right, "key"), {{"key", "float64"}, {"left_value", "int64"}, {"right_value", "int64"}},
        {{1, 1, 10}, {nan_value, 2, 20}, {nan_value, 4, 20}})
end)

-- Pivot: esperado wide literal, incluindo combinações ausentes e valores NA.

test("pivot: conteúdo, schema, ordenação e células ausentes", function()
    local source = smaug.DataSet({
        {"item", {"b", "a", "a"}, "string"},
        {"period", {"feb", "jan", "feb"}, "string"},
        {"value", {4, 1, smaug.NA}, "int64"},
    })
    expect_dataset(source:pivot("item", "period", "value"),
        {{"item", "string"}, {"feb", "int64"}, {"jan", "int64"}},
        {{"a", smaug.NA, 1}, {"b", 4, smaug.NA}})
    expect_dataset(source, {{"item", "string"}, {"period", "string"}, {"value", "int64"}},
        {{"b", "feb", 4}, {"a", "jan", 1}, {"a", "feb", smaug.NA}})
end)

test("pivot_table: agrega duplicatas com função explícita", function()
    local source = smaug.DataSet({
        {"item", {"b", "a", "a", "a"}, "string"},
        {"period", {"feb", "jan", "jan", "feb"}, "string"},
        {"value", {8, 2, 5, 4}, "float64"},
    })
    local schema = {{"item", "string"}, {"feb", "float64"}, {"jan", "float64"}}
    for unused_index, fixture in ipairs({{"sum", 7}, {"mean", 3.5}, {"min", 2}, {"max", 5}, {"first", 2}, {"last", 5}}) do
        expect_dataset(source:pivot_table("item", "period", "value", fixture[1]), schema,
            {{"a", 4, fixture[2]}, {"b", 8, smaug.NA}})
    end
    expect_dataset(source:pivot_table("item", "period", "value", "count"), schema,
        {{"a", 1, 2}, {"b", 1, smaug.NA}})
end)

test("pivot e pivot_table: vazios e argumentos inválidos", function()
    local empty = smaug.DataSet({{"item", {}, "string"}, {"period", {}, "string"}, {"value", {}, "float64"}})
    expect_dataset(empty:pivot("item", "period", "value"), {{"item", "string"}}, {})
    expect_dataset(empty:pivot_table("item", "period", "value", "sum"), {{"item", "string"}}, {})
    expect_error(function() empty:pivot(123, "period", "value") end, {"pivot", "strings"})
    for unused_index, names in ipairs({{"missing", "period", "value"}, {"item", "missing", "value"}, {"item", "period", "missing"}}) do
        expect_error(function() empty:pivot(unpack(names)) end, {"pivot", "missing"})
        expect_error(function() empty:pivot_table(names[1], names[2], names[3], "sum") end, {"pivot_table", "missing"})
    end
    expect_error(function() empty:pivot_table("item", "period", "value", "unknown") end, {"pivot_table", "aggfunc"})
end)

-- Contrato 8: validar os dois lados e todas as posições de chave; nunca
-- confundir NA nos valores com NA nas chaves. Mensagens usam busca literal.
test("NA em chave: groupby simples e ambas as posições da chave composta", function()
    for unused_index, null_column in ipairs({"first", "second"}) do
        local first = null_column == "first" and {"a", smaug.NA} or {"a", "b"}
        local second = null_column == "second" and {"x", smaug.NA} or {"x", "y"}
        local source = smaug.DataSet({{"first", first, "string"}, {"second", second, "string"}, {"value", {1, 2}, "int64"}})
        expect_error(function() source:groupby(null_column):count() end,
            {"groupby", "'" .. null_column .. "'", "contém NA", "fillna", "dropna"})
        expect_error(function() source:groupby({"first", "second"}):sum() end,
            {"groupby", "'" .. null_column .. "'", "contém NA", "fillna", "dropna"})
    end
end)

test("NA em chave: join valida os dois lados em todos os modos", function()
    local valid = join_input({{"a", 1}}, "value")
    local nullable = join_input({{"a", 1}, {smaug.NA, 2}}, "other")
    for unused_index, how in ipairs({"inner", "left", "right", "outer"}) do
        expect_error(function() nullable:join(valid, "key", how) end, {"join", "'key'", "contém NA", "fillna", "dropna"})
        expect_error(function() valid:join(nullable, "key", how) end, {"join", "'key'", "contém NA", "fillna", "dropna"})
    end
    local right = smaug.DataSet({{"other_key", {"a", smaug.NA}, "string"}})
    expect_error(function() valid:join(right, {"key", "other_key"}) end,
        {"join", "'other_key'", "contém NA", "fillna", "dropna"})
end)

test("NA em chave: pivot e pivot_table validam index e columns", function()
    for unused_index, null_column in ipairs({"item", "period"}) do
        local items = null_column == "item" and {"a", smaug.NA} or {"a", "b"}
        local periods = null_column == "period" and {"jan", smaug.NA} or {"jan", "feb"}
        local source = smaug.DataSet({{"item", items, "string"}, {"period", periods, "string"}, {"value", {1, 2}, "int64"}})
        expect_error(function() source:pivot("item", "period", "value") end,
            {"pivot", "'" .. null_column .. "'", "contém NA", "fillna", "dropna"})
        expect_error(function() source:pivot_table("item", "period", "value", "sum") end,
            {"pivot_table", "'" .. null_column .. "'", "contém NA", "fillna", "dropna"})
    end
end)

-- Executar todos os casos revela falhas independentes; qualquer falha deixa
-- o processo com status não-zero. O resumo conta cenários, não células.
local failed_cases = 0
for unused_index, case in ipairs(cases) do
    local succeeded, message = pcall(case.run)
    if not succeeded then
        failed_cases = failed_cases + 1
        io.stderr:write("FALHOU [" .. case.name .. "]: " .. tostring(message) .. "\n")
    end
end
if failed_cases > 0 then
    error(string.format("DataSet relacional: %d de %d casos falharam", failed_cases, #cases), 0)
end
print(string.format("OK — %d casos passaram (DataSet: groupby, concat, join, pivot)", #cases))
