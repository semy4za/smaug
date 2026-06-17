-- scripts/parity/03_c_lua_mirror.lua
-- Eixo 3: backend C ↔ frontend Lua.
-- Para cada dtype com backend C, lista funções C públicas e indica
-- se há método Lua correspondente.

local C = dofile("scripts/parity/common.lua")

-- Headers
local hdr_str   = (C.read_file("include/smaug.h") or "") ..
                  (C.read_file("include/smaug_string.h") or "")
local hdr_dt    = C.read_file("include/smaug_datetime.h") or ""
local hdr_io    = C.read_file("include/smaug_io.h") or ""
local hdr_numeric = C.read_file("include/smaug_numeric.h") or ""
local hdr_bool  = C.read_file("include/smaug_bool.h") or ""
local hdr_core  = C.read_file("include/smaug_core.h") or ""

-- Lua frontend
local series  = C.read_series_lua()

-- Para cada dtype, extrai funções C públicas
local headers = {
    f64  = hdr_numeric .. hdr_core,
    i64  = hdr_numeric .. hdr_core,
    bool = hdr_bool .. hdr_core,
    str  = hdr_str  .. hdr_core,
    dt   = hdr_dt  .. hdr_core,
}

local dtypes = {"f64", "i64", "bool", "str", "dt"}

local sections = {}

for _, d in ipairs(dtypes) do
    local funcs = C.extract_c_functions(headers[d], d)
    local rows = {}

    -- nomenclatura de exposição esperada no frontend Lua:
    -- C.smaug_{d}_NAME → frequentemente exposto via FFI; método Lua
    -- com o mesmo NAME ou um equivalente.
    for _, fname in ipairs(funcs) do
        -- procura referência à função C no frontend
        local needle = "smaug_" .. d .. "_" .. fname
        local found_in_lua = series:find(needle, 1, true) ~= nil
        local status = found_in_lua and "✅" or "⚠️"
        rows[#rows+1] = { "`"..fname.."`", status, "" }
    end

    local section = "\n### " .. d .. " — " .. #funcs .. " funções C\n\n"
    local header = { "função C", "exposta em Lua?", "nota" }
    sections[#sections+1] = section .. C.render_table(header, rows) .. "\n"
end

local out = {
    C.section(3, "Espelhamento C ↔ Lua",
        "Cada função pública do backend C deveria ter caminho no frontend Lua "
        .. "(direto via FFI ou exposto via método Series). ⚠️ = função C que não "
        .. "aparece em `lua/smaug/core/series.lua` (pode ser órfã ou exposta "
        .. "indiretamente via outro nome)."),
}
for _, s in ipairs(sections) do out[#out+1] = s end

io.write(table.concat(out, "\n"))
