-- scripts/parity/13_tostring.lua
-- Eixo 13: ergonomia REPL — todo objeto que o usuário segura deve ter
-- __tostring (nunca vazar "table: 0x…"). Invariante do item 11.3.
--
-- Auditoria estática: para cada objeto exposto, confirma que o arquivo que o
-- define contém a atribuição/label de __tostring. Marcador de conteúdo (não só
-- a existência do token) onde o metatable é literal (SeriesAt).

local C = dofile("scripts/parity/common.lua")

-- {rótulo do objeto, arquivo, marcador que prova o __tostring}
local objs = {
    { "Series",            "lua/smaug/core/series/_bool_ops.lua",              "Series.__tostring" },
    { "DataSet",           "lua/smaug/core/dataset/_core.lua",                 "DataSet.__tostring" },
    { "CategoricalSeries", "lua/smaug/core/series/categorical/_categorical.lua","CategoricalSeries.__tostring" },
    { "StrProxy (.str)",   "lua/smaug/core/series/text/_str.lua",              "StrProxy.__tostring" },
    { "SeriesDT (.dt)",    "lua/smaug/core/series/temporal/_dt.lua",           "SeriesDT.__tostring" },
    { "SeriesAt (.at)",    "lua/smaug/core/series/temporal/_dt.lua",           "accessor .at" },
    { "CatProxy (.cat)",   "lua/smaug/core/series/categorical/_categorical.lua","CatProxy.__tostring" },
    { "SeriesRolling",     "lua/smaug/core/series/window/_rolling.lua",        "SeriesRolling.__tostring" },
    { "SeriesExpanding",   "lua/smaug/core/series/window/_rolling.lua",        "SeriesExpanding.__tostring" },
    { "GroupBy",           "lua/smaug/core/dataset/_relational.lua",           "GroupBy.__tostring" },
    { "Rolling (DataSet)", "lua/smaug/core/dataset/_stat.lua",                 "Rolling.__tostring" },
}

local cache = {}
local function content(path)
    if cache[path] == nil then cache[path] = C.read_file(path) or "" end
    return cache[path]
end

local rows = {}
for _, o in ipairs(objs) do
    local label, path, marker = o[1], o[2], o[3]
    local has = content(path):find(marker, 1, true) ~= nil
    rows[#rows+1] = { "`"..label.."`", has and "🟩" or "🟥" }
end

local header = { "objeto exposto", "__tostring" }

local out = {
    C.section(13, "Ergonomia REPL — __tostring de objetos expostos",
        "🟩 = objeto tem __tostring (não vaza 'table: 0x…'). 🟥 = ausente. "
        .. "Invariante do item 11.3: todo objeto que o usuário segura se "
        .. "auto-mostra legível. A formatação de células segue a fonte única "
        .. "`core/display.lua` (itens 11.4/11.5)."),
    "",
    C.render_table(header, rows),
    "",
}

io.write(table.concat(out, "\n"))
