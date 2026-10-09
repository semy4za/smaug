-- tests/io/test_json.lua
-- I/O JSON: read_json_mem, to_json, unicode (\uXXXX), nulos, tipos mistos.
-- Consolida: seção JSON de test_io.lua
-- Rode da raiz: luajit tests/io/test_json.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local function approximately_equal(left_value, right_value) return math.abs(left_value - right_value) < 1e-9 end
local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local function temporary_file_path(name)
    local function non_empty_value(value) return (value ~= nil and value ~= "") and value or nil end
    local temporary_directory = non_empty_value(os.getenv("TMPDIR")) or non_empty_value(os.getenv("TMP"))
             or non_empty_value(os.getenv("TEMP")) or "/tmp"
    return temporary_directory .. "/" .. name
end

-- JSON — read_json_mem
-- ================================================================
local json_buffer = '[{"uf":"SP","pop":12,"pib":1.5,"cap":true},{"uf":"RJ","pop":6,"pib":0.8,"cap":false},{"uf":"MG","pop":null,"pib":0.5,"cap":true}]'
local read_json_memory_result = smaug.read_json_mem(json_buffer)
check(read_json_memory_result:nrows() == 3,                     "json: 3 linhas")
check(read_json_memory_result:ncols() == 4,                     "json: 4 colunas")
check(read_json_memory_result:col("uf")._dtype   == "string",   "json: uf=string")
check(read_json_memory_result:col("pop")._dtype  == "int64",    "json: pop=int64")
check(read_json_memory_result:col("pib")._dtype  == "float64",  "json: pib=float64")
check(read_json_memory_result:col("cap")._dtype  == "bool",     "json: cap=bool")
check(read_json_memory_result:col("uf"):get(1)  == "SP",        "json: uf[1]=SP")
check(read_json_memory_result:col("pop"):get(2) == 6,           "json: pop[2]=6")
check(approximately_equal(read_json_memory_result:col("pib"):get(1), 1.5),   "json: pib[1]=1.5")
check(read_json_memory_result:col("cap"):get(1) == true,        "json: cap[1]=true")
check(read_json_memory_result:col("cap"):get(2) == false,       "json: cap[2]=false")
check(read_json_memory_result:col("pop"):is_null(3),            "json: pop[3]=null")

-- null em string
local null_json = '[{"s":"hello"},{"s":null},{"s":"world"}]'
local read_json_memory_result_2 = smaug.read_json_mem(null_json)
check(read_json_memory_result_2:col("s"):get(1) == "hello",       "json null str: s[1]=hello")
check(read_json_memory_result_2:col("s"):is_null(2),              "json null str: s[2]=null")

-- array vazio
local empty_json = '[]'
local read_json_memory_result_3 = smaug.read_json_mem(empty_json)
check(read_json_memory_result_3:nrows() == 0,                     "json vazio: 0 linhas")

-- ================================================================
-- JSON — to_json_mem (roundtrip)
-- ================================================================
local serialized_json = read_json_memory_result:to_json_mem()
check(type(serialized_json) == "string",               "to_json_mem: retorna string")
check(#serialized_json > 0,                            "to_json_mem: não vazia")

local read_json_memory_result_4 = smaug.read_json_mem(serialized_json)
check(read_json_memory_result_4:nrows() == 3,                    "json roundtrip: 3 linhas")
check(read_json_memory_result_4:col("uf"):get(1) == "SP",        "json roundtrip: uf[1]=SP")
check(read_json_memory_result_4:col("cap"):get(1) == true,       "json roundtrip: cap[1]=true")
check(read_json_memory_result_4:col("cap"):get(2) == false,      "json roundtrip: cap[2]=false")
check(read_json_memory_result_4:col("pop"):is_null(3),           "json roundtrip: pop[3]=null")

-- pretty print
local jpretty = read_json_memory_result:to_json_mem({pretty=true})
check(jpretty:find("\n") ~= nil,            "json pretty: tem newlines")

-- ================================================================
-- JSON — to_json / read_json (arquivo)
-- ================================================================
local json_path = temporary_file_path("smaug_test_io.json")
read_json_memory_result:to_json(json_path)
local read_json_result = smaug.read_json(json_path)
check(read_json_result:nrows() == 3,                    "json arquivo: 3 linhas")
check(read_json_result:col("uf"):get(3) == "MG",        "json arquivo: uf[3]=MG")

-- ================================================================
-- Integração: read_csv → groupby → to_json
-- ================================================================
local read_csv_memory_result = smaug.read_csv_mem("cat,val\nA,10\nB,20\nA,30\n")
local sum_result = read_csv_memory_result:groupby("cat"):sum("val")
check(sum_result:nrows() == 2,                      "integração csv→groupby: 2 grupos")
local gb_json = sum_result:to_json_mem()
local gb_back = smaug.read_json_mem(gb_json)
check(gb_back:nrows() == 2,                 "integração csv→groupby→json: roundtrip")

-- ================================================================
-- 12.21: não-finitos no JSON — null + aviso (RFC 8259 não os comporta)
-- ================================================================
do
    local function capture(callback)
        local buffer = {}
        local original_stderr = io.stderr
        io.stderr = { write = function(unused_value, source_series) buffer[#buffer+1] = source_series end }
        local succeeded, error_message = pcall(callback)
        io.stderr = original_stderr
        if not succeeded then error(error_message, 0) end
        return table.concat(buffer)
    end

    local source_dataset = smaug.DataSet({ {"id", {1,2,3,4,5}, "int64"},
                               {"v", {smaug.NA, 0/0, 1/0, -1/0, 1.5}, "float64"} })
    local json_text
    local captured_warning = capture(function() json_text = source_dataset:to_json_mem() end)

    -- writer: todos os não-finitos viram null (JSON válido)
    check(json_text:find("inf", 1, true) == nil,  "12.21 to_json: sem literal 'inf'")
    check(json_text:find("nan", 1, true) == nil,  "12.21 to_json: sem literal 'nan'")
    check(json_text:find("null", 1, true) ~= nil, "12.21 to_json: não-finitos viraram null")

    -- round-trip: o Smaug lê o que o Smaug escreve (antes falhava!)
    local read_json_memory_result_5 = smaug.read_json_mem(json_text)
    check(read_json_memory_result_5:nrows() == 5,                  "12.21 read_json do próprio output: 5 linhas")
    check(read_json_memory_result_5:col("v"):is_null(2),           "12.21 round-trip: NaN virou null")
    check(read_json_memory_result_5:col("v"):is_null(3),           "12.21 round-trip: inf virou null")
    check(read_json_memory_result_5:col("v"):get(5) == 1.5,        "12.21 round-trip: finito preservado")

    -- aviso: a perda é real, então é visível (não silenciosa)
    check(captured_warning:find("não%-finito"), "12.21 to_json avisa sobre não-finitos")
    check(captured_warning:find("3 valor", 1, true) ~= nil, "12.21 aviso conta os 3 (NaN, inf, -inf; NA não conta)")
    check(captured_warning:find("null", 1, true) ~= nil,    "12.21 aviso diz que viraram null")

    -- sem não-finitos: silêncio
    local source_dataset_2 = smaug.DataSet({ {"v", {1.5, 2.5}, "float64"} })
    local captured_warning_2 = capture(function() source_dataset_2:to_json_mem() end)
    check(captured_warning_2 == "", "12.21 to_json sem não-finitos não avisa")

    -- NA sozinho não dispara aviso (ausência não é não-finito)
    local source_dataset_3 = smaug.DataSet({ {"v", {smaug.NA, 1.5}, "float64"} })
    local captured_warning_3 = capture(function() source_dataset_3:to_json_mem() end)
    check(captured_warning_3 == "", "12.21 NA puro não dispara aviso")
end

-- ================================================================
-- 12.1: mensagens de erro seguem "smaug: <op> — <razão>"
-- ================================================================
do
    local function error_message_of(callback) local succeeded, error_message = pcall(callback); return tostring(error_message) end

    local error_message = error_message_of(function() smaug.read_json("/tmp/_nao_existe_smaug_12_1.json") end)
    check(error_message:find("smaug: smaug_", 1, true) == nil, "12.1 read_json: sem 'smaug' duplicado")
    check(error_message:find("smaug: read_json —", 1, true) ~= nil, "12.1 read_json: padrão 'smaug: <op> —'")

    local error_message_2 = error_message_of(function() smaug.read_json_mem("xyz") end)
    check(error_message_2:find("smaug: read_json_mem —", 1, true) ~= nil,
          "12.1 read_json_mem: nomeia a própria função")

    local error_message_3 = error_message_of(function() smaug.DataSet({{"a",{1},"int64"}}):to_json("/nao/existe/x.json") end)
    check(error_message_3:find("smaug: to_json —", 1, true) ~= nil, "12.1 to_json: mesmo padrão do reader")
end

-- ================================================================
-- 12.3: datetime no to_json — string ISO (JSON não tem tipo "date")
-- ================================================================
do
    local source_dataset = smaug.DataSet({ {"id", {1, 2}, "int64"},
                               {"t", {1710460800000, 1710547200000}, "datetime"} })
    local json_text
    local succeeded = pcall(function() json_text = source_dataset:to_json_mem() end)
    check(succeeded, "12.3 to_json com datetime não crasha")
    check(json_text:find('"2024%-03%-15T00:00:00%.000Z"') ~= nil,
          "12.3 to_json escreve datetime como string ISO 8601")

    -- o Smaug lê o próprio output (era o critério do 12.21)
    local read_json_memory_result_5 = smaug.read_json_mem(json_text)
    check(read_json_memory_result_5:nrows() == 2, "12.3 read_json do próprio output")
    local converted_series = read_json_memory_result_5:col("t"):astype("datetime")
    check(converted_series:get(1) == source_dataset:col("t"):get(1), "12.3 round-trip de valor via astype")
end

-- Associação por nome, união tardia e colisão entre nome literal e gerado.
do
    local document = '[{}, {"a":1,"a":2}, {"a.1":30,"a":3,"a":4,"text":"NA"}]'
    local dataset = smaug.read_json_mem(document)
    check(dataset:nrows() == 3 and dataset:ncols() == 4, "json união após objeto vazio")
    check(dataset:col("a"):is_null(1), "json campo futuro preenche NA")
    check(dataset:col("a"):get(3) == 3, "json associação por nome reordenado")
    check(dataset:col("a.1"):get(2) == 2, "json segunda ocorrência preservada")
    check(dataset:col("a.1"):get(3) == 4, "json ocorrência estável entre objetos")
    check(dataset:col("a.1.1"):get(3) == 30, "json sufixo literal distinto do gerado")
    check(dataset:col("text"):get(3) == "NA", "json marcador permanece texto")
    local roundtrip = smaug.read_json_mem(dataset:to_json_mem())
    check(roundtrip:col("a.1.1"):get(3) == 30, "json nomes únicos no roundtrip")
    check(roundtrip:col("a.1"):is_null(1), "json NA preservado no roundtrip")
end

do
    local document = [=[[{"a":"NA\u0000x","a\u0000b":"123\u0000x","":"true\u0000x"}]]=]
    local dataset = smaug.read_json_mem(document)
    check(dataset:ncols() == 3, "json NUL nome distinto do prefixo")
    check(dataset:col("a"):get(1) == "NA\0x", "json NUL após marcador")
    check(dataset:col("a\0b"):get(1) == "123\0x", "json NUL em nome e valor")
    check(dataset:col(""):get(1) == "true\0x", "json nome vazio legítimo")
    local again = smaug.read_json_mem(dataset:to_json_mem())
    check(again:col("a\0b"):get(1) == "123\0x", "json NUL roundtrip C Lua C")
    local csv = dataset:to_csv_mem()
    local from_csv = smaug.read_csv_mem(csv)
    check(from_csv:col("a\0b"):get(1) == "123\0x", "csv NUL roundtrip C Lua C")
end

do
    local csv = "v,x\nNA\0x,1\nNA,2\nNA\0y,3\n\"\",4\n"
    local dataset = smaug.read_csv_mem(csv, {na_values = {"NA\0x"}})
    check(dataset:col("v"):is_null(1), "csv marcador NUL completo vira NA")
    check(dataset:col("v"):get(2) == "NA", "csv prefixo do marcador permanece texto")
    check(dataset:col("v"):get(3) == "NA\0y", "csv marcador com sufixo diferente")
    check(dataset:col("v"):get(4) == "", "csv vazio fora da lista permanece texto")
    local no_markers = smaug.read_csv_mem(csv, {na_values = {}})
    check(no_markers:col("v"):get(1) == "NA\0x", "csv lista vazia desativa padrões")
end

-- Expectativas textuais e cdata independentes: nunca criar limites via number.
do
    local expected = {9007199254740993LL, -9007199254740993LL,
                      9223372036854775807LL, -9223372036854775807LL - 1LL, 0LL}
    local literals = {"9007199254740993", "-9007199254740993", "9223372036854775807",
                      "-9223372036854775808", "0"}
    local records = {}
    for row, literal in ipairs(literals) do records[row] = '{"id":' .. literal .. '}' end
    records[6] = '{"id":null}'
    local json = "[" .. table.concat(records, ",") .. "]\n"
    -- NA explícito evita que uma linha CSV inteiramente vazia seja ignorada.
    local csv = "id\n" .. table.concat(literals, "\n") .. "\nNA\n"
    local function check_exact(dataset, label)
        check(dataset:nrows() == 6 and dataset:col("id")._dtype == "int64", label .. " shape/dtype")
        for row, value in ipairs(expected) do
            local actual = dataset:col("id"):get_raw(row)
            check(type(actual) == "cdata" and actual == value, label .. " int64 exato")
        end
        check(dataset:col("id"):is_null(6) and dataset:col("id"):get_raw(6) == nil,
              label .. " NA preservado")
    end
    local from_json = smaug.read_json_mem(json)
    local from_csv = smaug.read_csv_mem(csv)
    check_exact(from_json, "JSON leitura")
    check_exact(from_csv, "CSV leitura")
    local values = {expected[1], expected[2], expected[3], expected[4], expected[5], smaug.NA}
    local source = smaug.DataSet({{"id", values, "int64"}})
    check(source:to_json_mem() == json, "JSON escrita int64 exata sem reader")
    -- Coluna auxiliar mantém a linha NA no roundtrip CSV padrão.
    source:add_column("keep", smaug.Series({1, 1, 1, 1, 1, 1}, "int64"))
    local csv_rows = {"id,keep"}
    for row, literal in ipairs(literals) do csv_rows[row + 1] = literal .. ",1" end
    csv_rows[7] = ",1"
    local written_csv = source:to_csv_mem()
    check(written_csv == table.concat(csv_rows, "\n") .. "\n", "CSV escrita int64 exata sem reader")
    check_exact(smaug.read_csv_mem(written_csv), "CSV roundtrip")
    check_exact(smaug.read_json_mem(from_json:to_json_mem()), "JSON roundtrip")
end

do
    local bom = string.char(0xef, 0xbb, 0xbf) .. "[{\"v\":1}]"
    local dataset = smaug.read_json_mem(bom)
    check(dataset:nrows() == 1 and dataset:col("v"):get(1) == 1,
          "JSON BOM: leitura aceita marcador inicial")

    local invalid = string.char(0xed, 0xa0, 0x80)
    local succeeded, message = pcall(smaug.read_json_mem, '[{"n":"' .. invalid .. '"}]')
    check(not succeeded and tostring(message):find("UTF-8", 1, true),
          "JSON Lua rejeita UTF8 inválido na leitura")
    local source = smaug.DataSet({{"n", {invalid}, "string"}})
    succeeded, message = pcall(function() return source:to_json_mem() end)
    check(not succeeded and tostring(message):find("UTF-8", 1, true),
          "JSON Lua rejeita UTF8 inválido na escrita")
    local csv = source:to_csv_mem()
    check(smaug.read_csv_mem(csv):col("n"):get(1) == invalid,
          "CSV continua preservando bytes sem exigir UTF8")
    local named = smaug.DataSet({{invalid, {"text"}, "string"}})
    succeeded, message = pcall(function() return named:to_json_mem() end)
    check(not succeeded and tostring(message):find("nome byte 0", 1, true),
          "JSON Lua diagnostica UTF8 inválido no nome")
    local valid = string.char(0xf4, 0x8f, 0xbf, 0xbf)
    local roundtrip = smaug.read_json_mem(smaug.DataSet({{valid, {valid}, "string"}}):to_json_mem())
    check(roundtrip:col(valid):get(1) == valid, "JSON Lua preserva U+10FFFF")
end

do
    local schema = smaug.Schema({{name = "v", dtype = "float64", nullable = true}})
    for unused_index, case in ipairs({
        {"5e-324", 0x1p-1074}, {"-5e-324", -0x1p-1074}, {"-0e-9999", -0.0},
    }) do
        local document = '[{"v":' .. case[1] .. '},{"v":null}]'
        for unused_reader, dataset in ipairs({
            smaug.read_json_mem(document), smaug.read_json_mem(document, {schema = schema}),
        }) do
            local column = dataset:col("v")
            check(dataset:nrows() == 2 and column._dtype == "float64", "JSON rounding shape/dtype")
            check(column:get(1) == case[2] and not column:is_null(1), "JSON rounding exact value")
            check(column:is_null(2), "JSON rounding NA preserved")
            if case[2] == 0 then
                check(1 / column:get(1) == -math.huge, "JSON rounding negative zero")
            end
        end
    end
    for unused_index, case in ipairs({
        {"1e-400", "UNDERFLOW"}, {"-1e-400", "UNDERFLOW"},
        {"0x1p-1074", "SYNTAX"},
    }) do
        for unused_reader, options in ipairs({{}, {schema = schema}}) do
            local document = '[{"v":' .. case[1] .. '}]'
            local succeeded, message = pcall(smaug.read_json_mem, document, options)
            check(not succeeded and tostring(message):find(case[2], 1, true),
                  "JSON rounding preserves error and format grammar")
        end
    end
end

print(string.format("OK — %d checks passaram (I/O JSON + unicode)", passed_checks))
