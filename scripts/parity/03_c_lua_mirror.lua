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
-- 12.20 (frente 1): rolling (smaug_{f64,i64}_rolling_*) e multi_argsort vivem
-- aqui; o header nunca tinha entrado na composição do eixo — as 16 funções
-- de rolling ficavam fora do radar C↔Lua sem que nada acusasse a lacuna.
local hdr_window = C.read_file("include/smaug_ops_window.h") or ""
-- 12.20 (frente 3): astype (conversão cross-dtype) não cabe no padrão
-- "smaug_{dtype}_{sufixo}" — o nome carrega origem E destino
-- (smaug_i64_to_f64, smaug_str_to_dt...). Seção própria abaixo (matriz).
local hdr_astype = C.read_file("include/smaug_astype.h") or ""

-- Lua frontend
local series  = C.read_series_lua()

-- Para cada dtype, extrai funções C públicas
-- 12.20 (frente 2): as funções que o Lua REALMENTE usa para bool em massa
-- (smaug_bool_series_and/or/xor/count_true/any/all) vivem em smaug_numeric.h,
-- não em smaug_bool.h. Sem numeric.h aqui, o eixo nem tentava buscá-las — não
-- apareciam nem como 🟩 nem 🟨, sumiam do relatório. As de smaug_bool.h (sem
-- "_series_") são primitivas cruas de uso interno entre .c files — corretamente
-- sem caminho Lua direto (ficarão 🟨, e é o esperado).
local headers = {
    f64  = hdr_numeric .. hdr_core .. hdr_window,
    i64  = hdr_numeric .. hdr_core .. hdr_window,
    bool = hdr_bool .. hdr_core .. hdr_numeric,
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
        local status = found_in_lua and "🟩" or "🟨"
        rows[#rows+1] = { "`"..fname.."`", status, "" }
    end

    local section = "\n### " .. d .. " — " .. #funcs .. " funções C\n\n"
    local header = { "função C", "exposta em Lua?", "nota" }
    sections[#sections+1] = section .. C.render_table(header, rows) .. "\n"
end

-- ===================================================================
-- 12.20 (frente 3): astype — matriz origem×destino.
-- smaug_{origem}_to_{destino}(...) não é "um dtype com sufixo": carrega dois
-- dtypes no nome. Reaproveitar a tabela por-dtype esconderia essa natureza
-- (apareceria como "função to_f64 do dtype i64", confuso). Seção própria:
-- uma linha por par origem→destino, na ordem em que o header declara.
-- ===================================================================
do
    local rows = {}
    local n = 0
    for origem, destino in hdr_astype:gmatch("smaug_([%w]+)_to_([%w]+)%s*%(") do
        n = n + 1
        local fname = "smaug_" .. origem .. "_to_" .. destino
        local found_in_lua = series:find(fname, 1, true) ~= nil
        local status = found_in_lua and "🟩" or "🟨"
        rows[#rows+1] = { origem, destino, "`"..fname.."`", status }
    end
    local section = "\n### astype — conversão cross-dtype (" .. n .. " funções C)\n\n"
        .. "Matriz origem→destino (`smaug_astype.h`); não cabe na tabela por-dtype "
        .. "acima porque o nome carrega dois dtypes, não um.\n\n"
    local header = { "origem", "destino", "função C", "exposta em Lua?" }
    sections[#sections+1] = section .. C.render_table(header, rows) .. "\n"
end

local out = {
    C.section(3, "Espelhamento C ↔ Lua",
        "Cada função pública do backend C deveria ter caminho no frontend Lua "
        .. "(direto via FFI ou exposto via método Series). 🟨 = função C que não "
        .. "aparece em `lua/smaug/core/series.lua` (pode ser órfã ou exposta "
        .. "indiretamente via outro nome).\n\n"
        .. "**Fora de escopo por natureza (12.20 frente 4):** `smaug_convert.h` "
        .. "(`smaug_parse_i64/f64`, `smaug_fmt_i64/f64` e variantes _cstr — 6 "
        .. "funções) não entra nas tabelas acima. São infraestrutura interna de "
        .. "parsing/formatação usada entre arquivos C (astype.c, csv.c, json.c) "
        .. "— nunca expostas ao Lua via FFI (confirmado: zero ocorrências no "
        .. "cdef). Colocá-las aqui as marcaria 🟨 permanentemente — ruído, não "
        .. "achado, já que por design não devem ter caminho Lua direto."),
}
for _, s in ipairs(sections) do out[#out+1] = s end

io.write(table.concat(out, "\n"))
