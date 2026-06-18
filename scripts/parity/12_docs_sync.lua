-- scripts/parity/12_docs_sync.lua
-- Eixo 12: documentação espelhada com código.
-- Para cada método do código, verifica se aparece em API_INDEX.md
-- (mesmo nome, em backtick).

local C = dofile("scripts/parity/common.lua")

local series  = C.read_series_lua() or ""
local dataset = C.read_dataset_lua() or ""
local api_idx = C.read_file("docs/API_INDEX.md") or ""

local s_methods  = C.extract_lua_methods(series,  "function methods%.([%w_]+)")
local d_methods  = C.extract_lua_methods(dataset, "function methods%.([%w_]+)")
local gb_methods = C.extract_lua_methods(dataset, "function GroupBy:([%w_]+)")
local cat_methods = C.extract_lua_methods(series, "function CategoricalSeries[:.]([%w_]+)")
local cat_proxy   = C.extract_lua_methods(series, "function CatProxy:([%w_]+)")
local str_proxy   = C.extract_lua_methods(series, "function StrProxy:([%w_]+)")
local dt_proxy    = C.extract_lua_methods(series, "function SeriesDT:([%w_]+)")

local function check_in_docs(name)
    -- Procura `nome` em backticks (mais tolerante: também aceita `:nome`)
    return api_idx:find("`"..name.."`", 1, true) ~= nil
        or api_idx:find(":"..name.."`", 1, true) ~= nil
        or api_idx:find(":"..name.."(", 1, true) ~= nil
end

local function table_status(list, label)
    local missing = {}
    local present = 0
    for _, m in ipairs(list) do
        if m:sub(1,1) ~= "_" then  -- skip privados
            if check_in_docs(m) then
                present = present + 1
            else
                missing[#missing+1] = m
            end
        end
    end
    return present, missing
end

local groups = {
    {name="`Series.methods`",       list=s_methods},
    {name="`DataSet.methods`",      list=d_methods},
    {name="`GroupBy:*`",            list=gb_methods},
    {name="`CategoricalSeries:*`",  list=cat_methods},
    {name="`CatProxy:*` (.cat)",    list=cat_proxy},
    {name="`StrProxy:*` (.str)",    list=str_proxy},
    {name="`SeriesDT:*` (.dt)",     list=dt_proxy},
}

local rows = {}
for _, g in ipairs(groups) do
    local present, missing = table_status(g.list, g.name)
    local total = #g.list
    local pct = total > 0 and (100*present/total) or 0
    rows[#rows+1] = { g.name, total, present, total-present,
                      string.format("%.0f%%", pct),
                      (#missing > 0 and ("⚠️ faltam: " .. table.concat(missing, ", "):sub(1,80))
                                     or "✅ completo") }
end

local header = { "categoria", "total", "documentados", "faltam", "%", "detalhe" }

local out = {
    C.section(12, "Sincronização docs ↔ código",
        "Cada método público do código deveria aparecer em `API_INDEX.md`. "
        .. "Faltantes podem ser gaps de documentação ou métodos intencionalmente "
        .. "privados."),
    "",
    C.render_table(header, rows),
    "",
}

io.write(table.concat(out, "\n"))
