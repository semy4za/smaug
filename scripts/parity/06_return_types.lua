-- scripts/parity/06_return_types.lua
-- Eixo 6: tipos de retorno consistentes.
-- Para métodos críticos, examina o que cada um retorna.
-- Padrões procurados:
--   - retorno via "return Series.from_table(..., 'bool', ...)" → Series<bool>
--   - retorno via "return DataSet.new(...)" → DataSet
--   - retorno via "return {...}" → tabela Lua

local C = dofile("scripts/parity/common.lua")
local series = C.read_series_lua() or ""

-- Métodos que conceitualmente retornam algo categorizado
local interesting = {
    -- predicados
    {"eq",   "Series<bool>"},
    {"ne",   "Series<bool>"},
    {"lt",   "Series<bool>"},
    {"le",   "Series<bool>"},
    {"gt",   "Series<bool>"},
    {"ge",   "Series<bool>"},
    {"is_null", "valor escalar (bool)"},
    {"isna", "valor escalar (bool)"},
    {"notna","valor escalar (bool)"},
    -- factoreis de coleção
    {"unique", "Series"},
    {"value_counts", "DataSet"},
    {"describe", "tabela Lua"},
    -- estruturais
    {"head",   "Series"},
    {"tail",   "Series"},
    {"take",   "Series"},
    {"filter", "Series"},
    {"clone",  "Series"},
    {"sort",   "Series"},
    {"argsort","tabela de índices"},
    {"to_table", "tabela Lua"},
    -- aritméticas vetorizadas
    {"cumsum", "Series"},
    {"cumprod","Series"},
    {"cummax", "Series"},
    {"cummin", "Series"},
    {"diff",   "Series"},
    {"shift",  "Series"},
    {"map",    "Series"},
}

-- Heurística: caça "return XXX" nas últimas N linhas do corpo
local function extract_returns(body)
    local returns = {}
    for r in body:gmatch("return%s+([^%s][^\n]-)\n") do
        returns[#returns+1] = r:sub(1, 80)
    end
    return returns
end

local function classify_return(rets)
    if #rets == 0 then return "—" end
    local s = table.concat(rets, " | ")
    if     s:find("Series%.from_table.-bool")       then return "Series<bool>"
    elseif s:find("Series%.from_table")             then return "Series"
    elseif s:find("Series%.new")                    then return "Series"
    elseif s:find("DataSet%.new")                   then return "DataSet"
    elseif s:find('value_counts.*DataSet')          then return "DataSet"
    elseif s:find("smaug%.DataSet")                 then return "DataSet"
    elseif s:find("^%s*{")                          then return "tabela Lua"
    elseif s:find(":clone")                         then return "Series"
    elseif s:find(":take")                          then return "Series"
    elseif s:find(":filter")                        then return "Series"
    elseif s:find("self:")                          then return "Series (self)"
    elseif s:find("tonumber%(.*%)")                 then return "escalar"
    elseif s:find("true") or s:find("false")        then return "bool"
    elseif s:find("nil")                            then return "nil/valor"
    end
    return "outro (" .. (rets[1]:sub(1,40)) .. ")"
end

-- Extrai o corpo de uma função methods.NOME até a PRÓXIMA declaração
-- de função (heurística mais robusta que casar "end\n" perfeitamente).
local function method_body(content, fname)
    local start_pat = "function methods%." .. fname .. "%b()"
    local s_start, s_end = content:find(start_pat)
    if not s_start then
        -- tentar sem %b() (assinatura sem parêntese balanceado por algum motivo)
        s_start, s_end = content:find("function methods%."..fname.."%s*%(")
        if not s_start then return "" end
        -- avança até fechar parênteses
        local p = content:find("%)", s_end)
        if p then s_end = p end
    end
    local rest = content:sub(s_end + 1)
    -- Pega até a próxima "function " (qualquer escopo)
    local next_fn = rest:find("\nfunction ")
    if next_fn then
        return rest:sub(1, next_fn - 1)
    end
    return rest
end

local rows = {}
for _, item in ipairs(interesting) do
    local m, expected = item[1], item[2]
    local body = method_body(series, m)
    local rets = extract_returns(body)
    local actual = classify_return(rets)
    local status
    if actual == "—" then status = "❌ não encontrado"
    elseif actual:lower():find(expected:lower(), 1, true) then status = "✅"
    elseif expected:find(actual, 1, true) then status = "✅"
    else status = "⚠️"
    end
    rows[#rows+1] = { "`"..m.."`", expected, actual, status }
end

-- Caso especial: CategoricalSeries:value_counts (sabidamente retorna tabela, não DataSet)
local cs_body_pat = "function CategoricalSeries[:.]value_counts%b()(.-)\nend\n"
local cs_body = series:match(cs_body_pat) or ""
local cs_rets = extract_returns(cs_body)
local cs_class = classify_return(cs_rets)
rows[#rows+1] = { "`CategoricalSeries:value_counts`", "DataSet (paridade com Series)", cs_class,
                   cs_class == "DataSet" and "✅" or "❌ inconsistente com Series" }

local header = { "método", "esperado", "detectado", "status" }

local out = {
    C.section(6, "Tipos de retorno consistentes",
        "Métodos críticos: o tipo de retorno está conforme o esperado e simétrico "
        .. "entre dtypes? ⚠️ = divergência possível. ❌ = inconsistência clara."),
    "",
    C.render_table(header, rows),
    "",
}

io.write(table.concat(out, "\n"))
