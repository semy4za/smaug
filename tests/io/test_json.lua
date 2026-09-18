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

print(string.format("OK — %d checks passaram (I/O JSON + unicode)", passed_checks))
