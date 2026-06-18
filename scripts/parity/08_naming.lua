-- scripts/parity/08_naming.lua
-- Eixo 8: nomenclatura consistente.
-- Verifica grupos de nomes que devem ou não ser aliases, e onde a convenção
-- está sendo seguida.

local C = dofile("scripts/parity/common.lua")
local series  = C.read_series_lua() or ""
local dataset = C.read_dataset_lua() or ""

local series_set  = C.set(C.extract_lua_methods(series,  "function methods%.([%w_]+)"))
local dataset_set = C.set(C.extract_lua_methods(dataset, "function methods%.([%w_]+)"))

-- Aliases: nomes que devem ser equivalentes a outros
-- Detecta padrão "methods.X = methods.Y"
local function find_aliases(content)
    local aliases = {}
    for k, v in content:gmatch("methods%.([%w_]+)%s*=%s*methods%.([%w_]+)") do
        aliases[k] = v
    end
    return aliases
end

local s_aliases = find_aliases(series)
local d_aliases = find_aliases(dataset)

-- Grupos de nomes a auditar
local groups = {
    {
        name = "Tamanho",
        items = {"len", "size"},
        rules = "Series tem ambos (size = alias de len). DataSet tem nrows + ncols.",
    },
    {
        name = "Nulidade — predicados",
        items = {"is_null", "isna", "notna"},
        rules = "Convenção: is_null é original; isna/notna são aliases ergonômicos.",
    },
    {
        name = "Contagem",
        items = {"count_nonnull", "count_true"},
        rules = "count_nonnull é universal; count_true é só de Series<bool>.",
    },
    {
        name = "Lógica Kleene",
        items = {"land", "lor", "lxor", "lnot"},
        rules = "Exclusivos de Series<bool>. Nome com prefixo 'l' para não chocar com palavras-chave Lua.",
    },
    {
        name = "Seleção posicional",
        items = {"head", "tail", "take", "view", "iloc"},
        rules = "Series tem head/tail/take/view. DataSet tem head/tail/take/iloc. iloc é range-based.",
    },
}

local rows = {}
for _, g in ipairs(groups) do
    for _, item in ipairs(g.items) do
        local in_s = series_set[item] and "🟩" or "—"
        local in_d = dataset_set[item] and "🟩" or "—"
        local alias_s = s_aliases[item]
        local alias_d = d_aliases[item]
        local note = ""
        if alias_s then note = "Series: alias de `"..alias_s.."`" end
        if alias_d then
            note = note .. (note ~= "" and "; " or "") .. "DataSet: alias de `"..alias_d.."`"
        end
        rows[#rows+1] = { "**"..g.name.."**", "`"..item.."`", in_s, in_d, note }
    end
end

local header = { "grupo", "método", "Series", "DataSet", "nota" }

local out = {
    C.section(8, "Nomenclatura consistente",
        "Grupos de nomes que devem seguir convenções claras. Aliases declarados "
        .. "via `methods.X = methods.Y` são identificados automaticamente."),
    "",
    C.render_table(header, rows),
    "",
    "### Convenções",
    "",
}
for _, g in ipairs(groups) do
    out[#out+1] = "- **" .. g.name .. ":** " .. g.rules
end
out[#out+1] = ""

io.write(table.concat(out, "\n"))
