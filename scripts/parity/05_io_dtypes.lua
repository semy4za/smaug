-- scripts/parity/05_io_dtypes.lua
-- Eixo 5: I/O por dtype.
-- Examina smaug_csv.c e smaug_json.c para verificar quais dtypes
-- são lidos e escritos.

local C = dofile("scripts/parity/common.lua")

local csv_c = C.read_file("src/smaug_csv.c") or ""
local json_c = C.read_file("src/smaug_json.c") or ""
local csv_lua = C.read_file("lua/smaug/io/csv.lua") or ""
local json_lua = C.read_file("lua/smaug/io/json.lua") or ""

-- Dtypes
local dtypes = { "f64", "i64", "bool", "str", "dt", "cat" }
-- nomes Lua
local dt_lua = { f64="float64", i64="int64", bool="bool", str="string",
                 dt="datetime", cat="categorical" }

-- Heurística: para cada dtype, verifica se aparece referência ao
-- create/set/append correspondente no arquivo.
local function dtype_in(content, d)
    return content:find("smaug_"..d.."_create", 1, true) ~= nil or
           content:find("smaug_"..d.."_set",    1, true) ~= nil or
           content:find("smaug_"..d.."_append", 1, true) ~= nil or
           content:find('"'..dt_lua[d]..'"',    1, true) ~= nil
end

local rows = {}
for _, d in ipairs(dtypes) do
    local row = { "`"..dt_lua[d].."`" }
    row[#row+1] = dtype_in(csv_c, d)  and "🟩" or "🟨"
    row[#row+1] = dtype_in(csv_lua, d) and "🟩" or "🟨"
    row[#row+1] = dtype_in(json_c, d) and "🟩" or "🟨"
    row[#row+1] = dtype_in(json_lua, d) and "🟩" or "🟨"
    rows[#rows+1] = row
end

local header = { "dtype", "CSV C", "CSV Lua", "JSON C", "JSON Lua" }

local out = {
    C.section(5, "Paridade I/O por dtype",
        "🟩 = dtype mencionado/usado nos arquivos do parser/writer. "
        .. "🟨 = sem menção (dtype provavelmente não suportado no formato). "
        .. "Limitações conhecidas: `categorical` não tem representação nativa "
        .. "em CSV/JSON (lida como string e convertida via `astype`)."),
    "",
    C.render_table(header, rows),
    "",
}

io.write(table.concat(out, "\n"))
