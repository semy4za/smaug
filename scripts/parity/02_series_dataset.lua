-- scripts/parity/02_series_dataset.lua
-- Eixo 2: paridade entre Series e DataSet.
-- Métodos que aparecem em ambos devem ter semântica e assinatura comparáveis.

local C = dofile("scripts/parity/common.lua")

local series  = C.read_series_lua()
local dataset = C.read_file("lua/smaug/core/dataset.lua")

local series_set  = C.set(C.extract_lua_methods(series,  "function methods%.([%w_]+)"))
local dataset_set = C.set(C.extract_lua_methods(dataset, "function methods%.([%w_]+)"))

-- Universo: métodos esperados em ambos (lista intencional)
-- Estes são os métodos que conceitualmente fazem sentido nos dois lados.
local expected_pairs = {
    -- introspecção
    "len", "ncols", "nrows", "describe", "to_table", "head", "tail",
    "iloc", "take", "sample", "clone",
    -- manipulação
    "filter", "sort", "dropna", "fillna", "select",
    -- info
    "has_column", "columns", "dtypes",
}

-- Renome conhecidos (Series → DataSet)
-- ex: Series:len() ↔ DataSet:nrows() (ambos são "tamanho")
-- Não trato como mismatch — anoto.

local in_both, only_series, only_dataset = {}, {}, {}

local all = {}
for k in pairs(series_set) do all[k] = true end
for k in pairs(dataset_set) do all[k] = true end
local sorted = {}
for k in pairs(all) do sorted[#sorted+1] = k end
table.sort(sorted)

local rows = {}
for _, m in ipairs(sorted) do
    local s = series_set[m]  and "✅" or "—"
    local d = dataset_set[m] and "✅" or "—"
    local note = ""
    if series_set[m] and not dataset_set[m] then
        note = "só em Series"
    elseif dataset_set[m] and not series_set[m] then
        note = "só em DataSet"
    end
    rows[#rows+1] = { "`"..m.."`", s, d, note }
end

local header = { "método", "Series", "DataSet", "nota" }
local section = C.section(2, "Paridade Series ↔ DataSet",
    "Métodos que existem em cada lado. Algumas assimetrias são intencionais "
    .. "(ex: `Series:len` vs `DataSet:nrows/ncols`). Outras podem ser gaps reais.")

local out = { section, C.render_table(header, rows), "" }

-- Sumário e listagem de assimetrias
local s_only, d_only, both = {}, {}, {}
for _, m in ipairs(sorted) do
    if series_set[m] and dataset_set[m] then both[#both+1] = m
    elseif series_set[m] then s_only[#s_only+1] = m
    else d_only[#d_only+1] = m end
end

out[#out+1] = string.format("**Sumário Eixo 2:** %d métodos em ambos · %d só em Series · %d só em DataSet",
    #both, #s_only, #d_only)
out[#out+1] = ""

io.write(table.concat(out, "\n"))
