-- tests/dataset/test_io_support.lua
-- DataSet: at/iat (acesso escalar), insert, to_dict, from_dict,
-- to_markdown, to_string.
-- Consolida: seção DataSet de test_access.lua (F.5)
-- Rode da raiz: luajit tests/dataset/test_io_support.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local Series = smaug.Series
local S      = Series
local NA     = Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- 2. DataSet:at / iat — célula única
-- ================================================================

local df = smaug.DataSet({
    {"a", {1, 2, 3},          "int64"},
    {"b", {"x", "y", "z"},    "string"},
    {"c", {1.5, NA, 3.5},     "float64"},
})

-- at(i, col) por nome
check(df:at(1, "a") == 1,           "at(1,a) = 1")
check(df:at(2, "b") == "y",         "at(2,b) = y")
check(df:at(2, "c") == nil,         "at(2,c) = nil (null)")

-- iat(i, ci) por posição de coluna
check(df:iat(3, 1) == 3,            "iat(3,1) = 3 (coluna a)")
check(df:iat(1, 2) == "x",          "iat(1,2) = x (coluna b)")

-- erros
check(not pcall(function() return df:at(1, "zzz") end), "at coluna inexistente = erro")
check(not pcall(function() return df:iat(1, 99) end),   "iat ci fora dos limites = erro")
check(not pcall(function() return df:at(1, 5) end),     "at col não-string = erro")

-- ================================================================
-- 3. DataSet:insert — posição específica
-- ================================================================

local di = smaug.DataSet({
    {"a", {1, 2, 3}, "int64"},
    {"c", {7, 8, 9}, "int64"},
})

-- inserir no meio
di:insert(2, "b", S.from_table({4, 5, 6}, "int64"))
check(table.concat(di:columns(), ",") == "a,b,c", "insert no meio: ordem a,b,c")
check(di:at(1, "b") == 4,           "insert: valor correto")

-- inserir no início
di:insert(1, "z", S.from_table({0, 0, 0}, "int64"))
check(di:columns()[1] == "z",       "insert no início")

-- inserir no fim (loc = ncols+1)
di:insert(di:ncols() + 1, "w", S.from_table({9, 9, 9}, "int64"))
check(di:columns()[di:ncols()] == "w", "insert no fim")

-- erros
check(not pcall(function() di:insert(99, "x", S.from_table({1,2,3}, "int64")) end),
      "insert loc fora dos limites = erro")
check(not pcall(function() di:insert(1, "a", S.from_table({1,2,3}, "int64")) end),
      "insert nome duplicado = erro")
check(not pcall(function() di:insert(1, "novo", S.from_table({1,2}, "int64")) end),
      "insert nrows incompatível = erro")

-- ================================================================
-- 4. DataSet:to_dict
-- ================================================================

local dd = smaug.DataSet({
    {"x", {1, 2}, "int64"},
    {"y", {"a", "b"}, "string"},
})

-- columns (default)
local dcol = dd:to_dict()
check(dcol.x[1] == 1 and dcol.x[2] == 2, "to_dict columns: x")
check(dcol.y[1] == "a",             "to_dict columns: y")

-- records
local drec = dd:to_dict("records")
check(#drec == 2,                   "to_dict records: 2 linhas")
check(drec[1].x == 1 and drec[1].y == "a", "to_dict records[1]")
check(drec[2].x == 2 and drec[2].y == "b", "to_dict records[2]")

-- orient inválido → erro
check(not pcall(function() dd:to_dict("bad") end), "to_dict orient inválido = erro")

-- ================================================================
-- 5. DataSet.from_dict
-- ================================================================

-- columns com _order
local fc = smaug.DataSet.from_dict({a = {1, 2, 3}, b = {"p", "q", "r"}, _order = {"a", "b"}})
check(table.concat(fc:columns(), ",") == "a,b", "from_dict columns: ordem via _order")
check(fc:nrows() == 3,              "from_dict columns: 3 linhas")
check(fc:column("a")._dtype == "int64",  "from_dict infere int64")
check(fc:column("b")._dtype == "string", "from_dict infere string")
check(fc:at(2, "a") == 2,           "from_dict columns: valor")

-- inferência float
local ff = smaug.DataSet.from_dict({v = {1.5, 2.5}, _order = {"v"}})
check(ff:column("v")._dtype == "float64", "from_dict infere float64")

-- inferência bool
local fb = smaug.DataSet.from_dict({flag = {true, false}, _order = {"flag"}})
check(fb:column("flag")._dtype == "bool", "from_dict infere bool")

-- records
local fr = smaug.DataSet.from_dict({{x = 1, y = "a"}, {x = 2, y = "b"}, {x = 3}}, "records")
check(fr:nrows() == 3,              "from_dict records: 3 linhas")
check(fr:has_column("x") and fr:has_column("y"), "from_dict records: ambas colunas")
check(fr:at(1, "x") == 1,           "from_dict records: x[1]")
check(fr:at(3, "y") == nil,         "from_dict records: y[3] ausente → nil")

-- roundtrip to_dict → from_dict (columns)
local rt = smaug.DataSet.from_dict(dd:to_dict("columns"), "columns")
check(rt:nrows() == 2,              "roundtrip to_dict→from_dict: nrows")

-- orient inválido → erro
check(not pcall(function() smaug.DataSet.from_dict({}, "bad") end), "from_dict orient inválido = erro")

-- ================================================================
-- 6. DataSet:to_markdown
-- ================================================================

local dm = smaug.DataSet({
    {"nome", {"Ana", "Bruno"}, "string"},
    {"idade", {30, NA}, "int64"},
})
local md = dm:to_markdown()
check(type(md) == "string",         "to_markdown → string")
-- estrutura: 4 linhas (header, separador, 2 dados)
local lines = {}
for line in md:gmatch("[^\n]+") do lines[#lines + 1] = line end
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

local dts = smaug.DataSet({
    {"a", {1, 2, 3, 4, 5}, "int64"},
})
local str = dts:to_string()
check(type(str) == "string",        "to_string → string")
check(str:find("a") ~= nil,         "to_string contém nome da coluna")

-- max_rows limita
local str2 = dts:to_string({max_rows = 2})
check(str2:find("linhas a mais") ~= nil, "to_string max_rows trunca com aviso")

-- ================================================================
-- Resultado
-- ================================================================


print(string.format("OK — %d checks passaram (DataSet: at/iat, insert, to_dict, from_dict, to_markdown, to_string)", n_ok))