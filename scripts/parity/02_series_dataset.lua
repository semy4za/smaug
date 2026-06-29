-- scripts/parity/02_series_dataset.lua
-- Eixo 2: paridade Series ↔ DataSet, CLASSIFICADA.
-- Cada método: (1) em ambos, (2) par de nome conhecido, (3) assimetria
-- intencional registrada em exceptions.txt, ou (4) GAP REAL não-registrado → falha.
-- Series é 1-D, DataSet é 2-D: a maioria das assimetrias é estrutural e intencional.

local C = dofile("scripts/parity/common.lua")

local series  = C.read_series_lua()
local dataset = C.read_dataset_lua()

local series_set  = C.set(C.extract_lua_methods(series,  "function methods%.([%w_]+)"))
local dataset_set = C.set(C.extract_lua_methods(dataset, "function methods%.([%w_]+)"))

-- Pares de nome: mesmo conceito, nome diferente pela dimensionalidade.
-- Paridade sob outro nome — não é não-paridade.
local pairs_map = {
    len = "nrows", nrows = "len",
    dtype = "dtypes", dtypes = "dtype",
    sort = "sort_by", sort_by = "sort",
}

local exc = C.load_exceptions()["2"] or {}

local all = {}
for k in pairs(series_set)  do all[k] = true end
for k in pairs(dataset_set) do all[k] = true end
local sorted = {}
for k in pairs(all) do sorted[#sorted+1] = k end
table.sort(sorted)

local rows = {}
local gaps = {}
local n_both, n_pair, n_exc = 0, 0, 0

for _, m in ipairs(sorted) do
    local in_s, in_d = series_set[m], dataset_set[m]
    local s_mark = in_s and "🟩" or "—"
    local d_mark = in_d and "🟩" or "—"
    local cls, note
    if in_s and in_d then
        cls, note = "🟩", ""
        n_both = n_both + 1
    else
        local partner = pairs_map[m]
        local paired = partner and ((in_s and dataset_set[partner]) or (in_d and series_set[partner]))
        if paired then
            cls, note = "🟦", "par de `"..partner.."`"
            n_pair = n_pair + 1
        elseif exc[m] then
            cls, note = "⬜", exc[m]
            n_exc = n_exc + 1
        else
            cls, note = "🟥", "GAP REAL não-registrado"
            gaps[#gaps+1] = m .. (in_s and " (só Series)" or " (só DataSet)")
        end
    end
    rows[#rows+1] = { "`"..m.."`", s_mark, d_mark, cls.." "..note }
end

local header = { "método", "Series", "DataSet", "classificação" }
local section = C.section(2, "Paridade Series ↔ DataSet (classificada)",
    "Cada assimetria é classificada: 🟩 ambos · 🟦 par de nome · ⬜ intencional "
    .. "(exceptions.txt) · 🟥 gap real. Series é 1-D, DataSet é 2-D.")

local out = { section, C.render_table(header, rows), "" }
out[#out+1] = string.format(
    "**Sumário Eixo 2:** %d em ambos · %d pares de nome · %d intencionais · %d gaps reais",
    n_both, n_pair, n_exc, #gaps)
out[#out+1] = ""

io.write(table.concat(out, "\n"))

if #gaps > 0 then
    io.stderr:write("Eixo 2 — GAPS REAIS nao-registrados:\n")
    for _, g in ipairs(gaps) do io.stderr:write("  - "..g.."\n") end
    io.stderr:write("Registre em exceptions.txt (intencional) ou Roadmap (gap real).\n")
    os.exit(1)
end
