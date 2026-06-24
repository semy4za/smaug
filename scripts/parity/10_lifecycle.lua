-- scripts/parity/10_lifecycle.lua
-- Eixo 10: paridade de lifecycle entre dtypes.
-- Cada dtype com backend C deve ter o mesmo conjunto de funções de lifecycle.
--
-- Reforço (Bloco I.4): para funções de "dois lados" — existem no header C E
-- precisam ser expostas no descritor DTYPES de _types.lua — o eixo cruza as
-- duas pontas. Pega o caso em que a função C existe mas o descritor não a
-- expõe (ex.: smaug_dt_view existia no C sem campo `view` no descritor).

local C = dofile("scripts/parity/common.lua")

local lifecycle = {
    "create", "create_with_capacity", "create_from_array",
    "free", "clone", "view", "append", "append_null",
    "set", "set_null", "get", "is_null",
}

-- funções de dois-lados: além do header C, devem ter campo homônimo no
-- descritor DTYPES (_types.lua). São as que a camada Lua despacha via self._d.
local two_sided = { view = true, take = true, filter = true }

local headers_by_dtype = {
    f64 = (C.read_file("include/smaug_numeric.h") or "")
       .. (C.read_file("include/smaug_core.h") or ""),
    i64 = (C.read_file("include/smaug_numeric.h") or "")
       .. (C.read_file("include/smaug_core.h") or ""),
    bool = (C.read_file("include/smaug_bool.h") or "")
        .. (C.read_file("include/smaug_core.h") or ""),
    str = (C.read_file("include/smaug_string.h") or "")
       .. (C.read_file("include/smaug.h") or ""),
    dt = (C.read_file("include/smaug_datetime.h") or ""),
}

local dtypes = {"f64", "i64", "bool", "str", "dt"}

-- mapa dtype-curto → nome no descritor (campo `name = "..."`)
local dtype_name = { f64="float64", i64="int64", bool="bool", str="string", dt="datetime" }

-- Lê _types.lua e fatia em segmentos por dtype (delimitados por `name = "..."`).
-- Retorna, por dtype, o trecho-fonte do seu descritor.
local function descriptor_segments()
    local src = C.read_file("lua/smaug/core/series/_types.lua") or ""
    local segs, order = {}, {}
    for name, pos in src:gmatch("name%s*=%s*\"([%w_]+)\"()") do
        order[#order+1] = { name = name, pos = pos }
    end
    for i, e in ipairs(order) do
        local stop = order[i+1] and order[i+1].pos or #src
        segs[e.name] = src:sub(e.pos, stop)
    end
    return segs
end

-- descritor expõe o campo `fn`? (procura `fn =` no segmento do dtype)
local function descriptor_has(segs, dshort, fn)
    local seg = segs[dtype_name[dshort]]
    if not seg then return false end
    return seg:find("%f[%w]" .. fn .. "%s*=") ~= nil
end

local segs = descriptor_segments()

local excs = C.load_exceptions()
local excs10 = excs["10"] or {}

local rows = {}
local cross_rows = {}   -- linhas do cruzamento header↔descritor (só two_sided)
for _, fn in ipairs(lifecycle) do
    local row = { "`"..fn.."`" }
    for _, d in ipairs(dtypes) do
        local content = headers_by_dtype[d] or ""
        local needle = "smaug_" .. d .. "_" .. fn
        local found = content:find(needle, 1, true) ~= nil
        local exc_key = fn .. "/" .. d
        if found then
            row[#row+1] = "🟩"
        elseif excs10[exc_key] then
            row[#row+1] = "⬜"
        else
            row[#row+1] = "🟨"
        end
    end
    rows[#rows+1] = row

    -- cruzamento das duas pontas para funções de dois-lados
    if two_sided[fn] then
        local crow = { "`"..fn.."`" }
        for _, d in ipairs(dtypes) do
            local in_c   = (headers_by_dtype[d] or ""):find("smaug_"..d.."_"..fn, 1, true) ~= nil
            local in_lua = descriptor_has(segs, d, fn)
            local exc_key = fn .. "/" .. d
            if in_c and in_lua then
                crow[#crow+1] = "🟩"              -- coerente: existe nos dois
            elseif (not in_c) and (not in_lua) then
                crow[#crow+1] = excs10[exc_key] and "⬜" or "🟨"
            elseif in_c and not in_lua then
                -- C tem, descritor NÃO expõe → divergência, salvo exceção
                crow[#crow+1] = excs10[exc_key] and "⬜" or "🟥"
            else
                crow[#crow+1] = "🟥"              -- descritor expõe sem C: impossível, alerta
            end
        end
        cross_rows[#cross_rows+1] = crow
    end
end

local header = { "função", "f64", "i64", "bool", "str", "dt" }

local out = {
    C.section(10, "Paridade de lifecycle",
        "Cada dtype com backend C deve oferecer o mesmo conjunto de operações "
        .. "de lifecycle. `categorical` é Lua puro e não entra nesta tabela "
        .. "(exceção em `exceptions.txt`)."),
    "",
    C.render_table(header, rows),
    "",
    "**Cruzamento header C ↔ descritor DTYPES** (funções de dois-lados): a "
    .. "função existe no C *e* é exposta no descritor de `_types.lua`? 🟥 = C "
    .. "tem mas o descritor não expõe (ou vice-versa) sem exceção registrada.",
    "",
    C.render_table(header, cross_rows),
    "",
}

io.write(table.concat(out, "\n"))
