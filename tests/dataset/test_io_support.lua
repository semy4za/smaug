-- tests/dataset/test_io_support.lua
-- DataSet: at/iat (acesso escalar), insert, to_dict, from_dict,
-- to_markdown, to_string.
-- Consolida: seção DataSet de test_access.lua (F.5)
-- Rode da raiz: luajit tests/dataset/test_io_support.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

-- 2. DataSet:at / iat — célula única
-- ================================================================

local source_dataset = smaug.DataSet({
    {"a", {1, 2, 3},          "int64"},
    {"b", {"x", "y", "z"},    "string"},
    {"c", {1.5, smaug.NA, 3.5},     "float64"},
})

-- at(i, col) por nome
check(source_dataset:at(1, "a") == 1,           "at(1,a) = 1")
check(source_dataset:at(2, "b") == "y",         "at(2,b) = y")
check(source_dataset:at(2, "c") == nil,         "at(2,c) = nil (null)")

-- iat(i, ci) por posição de coluna
check(source_dataset:iat(3, 1) == 3,            "iat(3,1) = 3 (coluna a)")
check(source_dataset:iat(1, 2) == "x",          "iat(1,2) = x (coluna b)")

-- erros
check(not pcall(function() return source_dataset:at(1, "zzz") end), "at coluna inexistente = erro")
check(not pcall(function() return source_dataset:iat(1, 99) end),   "iat ci fora dos limites = erro")
check(not pcall(function() return source_dataset:at(1, 5) end),     "at col não-string = erro")

-- ================================================================
-- 3. DataSet:insert — posição específica
-- ================================================================

local source_dataset_2 = smaug.DataSet({
    {"a", {1, 2, 3}, "int64"},
    {"c", {7, 8, 9}, "int64"},
})

-- inserir no meio
source_dataset_2:insert(2, "b", smaug.Series({4, 5, 6}, "int64"))
check(table.concat(source_dataset_2:columns(), ",") == "a,b,c", "insert no meio: ordem a,b,c")
check(source_dataset_2:at(1, "b") == 4,           "insert: valor correto")

-- inserir no início
source_dataset_2:insert(1, "z", smaug.Series({0, 0, 0}, "int64"))
check(source_dataset_2:columns()[1] == "z",       "insert no início")

-- inserir no fim (loc = ncols+1)
source_dataset_2:insert(source_dataset_2:ncols() + 1, "w", smaug.Series({9, 9, 9}, "int64"))
check(source_dataset_2:columns()[source_dataset_2:ncols()] == "w", "insert no fim")

-- erros
check(not pcall(function() source_dataset_2:insert(99, "x", smaug.Series({1,2,3}, "int64")) end),
      "insert loc fora dos limites = erro")
check(not pcall(function() source_dataset_2:insert(1, "a", smaug.Series({1,2,3}, "int64")) end),
      "insert nome duplicado = erro")
check(not pcall(function() source_dataset_2:insert(1, "novo", smaug.Series({1,2}, "int64")) end),
      "insert nrows incompatível = erro")

-- ================================================================
-- 4. DataSet:to_dict
-- ================================================================

local source_dataset_3 = smaug.DataSet({
    {"x", {1, 2}, "int64"},
    {"y", {"a", "b"}, "string"},
})

-- columns (default)
local column_dictionary = source_dataset_3:to_dict()
check(column_dictionary.x[1] == 1 and column_dictionary.x[2] == 2, "to_dict columns: x")
check(column_dictionary.y[1] == "a",             "to_dict columns: y")

-- records
local record_dictionary = source_dataset_3:to_dict("records")
check(#record_dictionary == 2,                   "to_dict records: 2 linhas")
check(record_dictionary[1].x == 1 and record_dictionary[1].y == "a", "to_dict records[1]")
check(record_dictionary[2].x == 2 and record_dictionary[2].y == "b", "to_dict records[2]")

-- orient inválido → erro
check(not pcall(function() source_dataset_3:to_dict("bad") end), "to_dict orient inválido = erro")

-- ================================================================
-- 5. DataSet.from_dict
-- ================================================================

-- columns com _order
local dictionary_dataset = smaug.DataSet.from_dict({a = {1, 2, 3}, b = {"p", "q", "r"}, _order = {"a", "b"}})
check(table.concat(dictionary_dataset:columns(), ",") == "a,b", "from_dict columns: ordem via _order")
check(dictionary_dataset:nrows() == 3,              "from_dict columns: 3 linhas")
check(dictionary_dataset:column("a")._dtype == "int64",  "from_dict infere int64")
check(dictionary_dataset:column("b")._dtype == "string", "from_dict infere string")
check(dictionary_dataset:at(2, "a") == 2,           "from_dict columns: valor")

-- inferência float
local dictionary_dataset_2 = smaug.DataSet.from_dict({v = {1.5, 2.5}, _order = {"v"}})
check(dictionary_dataset_2:column("v")._dtype == "float64", "from_dict infere float64")

-- inferência bool
local dictionary_dataset_3 = smaug.DataSet.from_dict({flag = {true, false}, _order = {"flag"}})
check(dictionary_dataset_3:column("flag")._dtype == "bool", "from_dict infere bool")

-- records
local dictionary_dataset_4 = smaug.DataSet.from_dict({{x = 1, y = "a"}, {x = 2, y = "b"}, {x = 3}}, "records")
check(dictionary_dataset_4:nrows() == 3,              "from_dict records: 3 linhas")
check(dictionary_dataset_4:has_column("x") and dictionary_dataset_4:has_column("y"), "from_dict records: ambas colunas")
check(dictionary_dataset_4:at(1, "x") == 1,           "from_dict records: x[1]")
check(dictionary_dataset_4:at(3, "y") == nil,         "from_dict records: y[3] ausente → nil")

-- roundtrip to_dict → from_dict (columns)
local dictionary_dataset_5 = smaug.DataSet.from_dict(source_dataset_3:to_dict("columns"), "columns")
check(dictionary_dataset_5:nrows() == 2,              "roundtrip to_dict→from_dict: nrows")

-- orient inválido → erro
check(not pcall(function() smaug.DataSet.from_dict({}, "bad") end), "from_dict orient inválido = erro")

-- ================================================================
-- 6. DataSet:to_markdown
-- ================================================================

local source_dataset_4 = smaug.DataSet({
    {"nome", {"Ana", "Bruno"}, "string"},
    {"idade", {30, smaug.NA}, "int64"},
})
local markdown_text = source_dataset_4:to_markdown()
check(type(markdown_text) == "string",         "to_markdown → string")
-- estrutura: 4 linhas (header, separador, 2 dados)
local lines = {}
for line in markdown_text:gmatch("[^\n]+") do lines[#lines + 1] = line end
check(#lines == 4,                  "to_markdown: 4 linhas (header+sep+2)")
check(lines[1]:sub(1, 1) == "|",    "to_markdown: header começa com |")
check(lines[2]:find("%-%-") ~= nil, "to_markdown: separador tem traços")
check(lines[4]:find("NA") ~= nil,   "to_markdown: null vira NA")

-- DataSet vazio
local dempty = smaug.DataSet({})
check(dempty:to_markdown() == "",   "to_markdown vazio → string vazia")

-- ================================================================
-- 7. DataSet:to_string
-- ================================================================

local source_dataset_5 = smaug.DataSet({
    {"a", {1, 2, 3, 4, 5}, "int64"},
})
local formatted_text = source_dataset_5:to_string()
check(type(formatted_text) == "string",        "to_string → string")
check(formatted_text:find("a") ~= nil,         "to_string contém nome da coluna")

-- max_rows limita com truncamento cabeça+cauda (marcador "..." no meio)
local formatted_text_2 = source_dataset_5:to_string({max_rows = 2})
check(formatted_text_2:find("%.%.%.") ~= nil, "to_string max_rows: marcador de corte '...'")
local truncated_lines = {}; for line in formatted_text_2:gmatch("[^\n]+") do truncated_lines[#truncated_lines+1] = line end
check(#truncated_lines == 4, "to_string cabeça+cauda: header + 1 topo + ... + 1 base")
check(truncated_lines[2]:find("^1%s"), "to_string cabeça+cauda: primeira linha de dados é o índice 1")
check(truncated_lines[4]:find("^5%s"), "to_string cabeça+cauda: última linha de dados é o índice 5")

-- 11.5/11.4 invariantes de display do DataSet (fonte única compartilhada)
local large_integer = require("ffi").new("int64_t", 9007199254740993LL)
local source_dataset_6 = smaug.DataSet({ {"n", {large_integer}, "int64"} })
check(source_dataset_6:to_string():find("9007199254740993", 1, true) ~= nil,
      "11.4 DataSet:to_string int64 > 2^53 EXATO")
check(tostring(source_dataset_6):find("9007199254740993", 1, true) ~= nil,
      "11.4 DataSet __tostring int64 > 2^53 EXATO")
check(source_dataset_6:to_string():find("e+", 1, true) == nil,
      "11.4 DataSet: sem notação científica no int64 grande")
local source_dataset_7 = smaug.DataSet({ {"x", {3.14159265358979}, "float64"} })
local floating_point_series = smaug.Series({3.14159265358979}, "float64")
local function cellnum(source_series) return source_series:match("3%.%d+") end
check(cellnum(source_dataset_7:to_string()) == cellnum(floating_point_series:to_string()),
      "11.5 float: DataSet e Series rendem o MESMO texto (%.6g canônico)")
local source_dataset_8 = smaug.DataSet({ {"g", {"x","y","x"}, "string"}, {"v", {1,2,3}, "int64"} })
local groupby_text = tostring(source_dataset_8:groupby("g"))
check(groupby_text:find("^table:") == nil and groupby_text:find("groupby", 1, true) ~= nil,
      "11.2 DataSet.groupby proxy __tostring legível")
local rolling_text = tostring(source_dataset_8:rolling(2))
check(rolling_text:find("^table:") == nil and rolling_text:find("rolling", 1, true) ~= nil,
      "11.2 DataSet.rolling proxy __tostring legível")

-- ================================================================
-- Resultado
-- ================================================================

print(string.format("OK — %d checks passaram (DataSet: at/iat, insert, to_dict, from_dict, to_markdown, to_string)", passed_checks))
