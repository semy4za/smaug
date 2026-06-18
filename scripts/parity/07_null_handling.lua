-- scripts/parity/07_null_handling.lua
-- Eixo 7: política de null consistente.
-- Para cada método relevante, examina como null é tratado:
--   - propaga (null no input → null no output)
--   - é ignorado (com flag ignore_na)
--   - erra (sort/argsort recusam)
--   - conta diferente

local C = dofile("scripts/parity/common.lua")
local series = C.read_series_lua() or ""

local function method_body(content, fname)
    local start_pat = "function methods%." .. fname .. "%b()"
    local s_start, s_end = content:find(start_pat)
    if not s_start then
        s_start, s_end = content:find("function methods%."..fname.."%s*%(")
        if not s_start then return "" end
        local p = content:find("%)", s_end)
        if p then s_end = p end
    end
    local rest = content:sub(s_end + 1)
    local next_fn = rest:find("\nfunction ")
    if next_fn then return rest:sub(1, next_fn - 1) end
    return rest
end

-- Métodos com flag ignore_na
local with_ignore_na_pattern = {
    "sum", "mean", "min", "max", "median", "quantile", "var", "std",
    "prod", "skew", "kurtosis", "mad", "sem", "mode",
}

-- Métodos que devem ERRAR com null
local err_on_null = { "sort", "argsort" }

-- Métodos que devem PROPAGAR null
local propagate = {
    "abs", "round", "clip", "cumsum", "cumprod", "cummin", "cummax",
    "diff", "shift", "sin", "cos", "tan", "exp", "log", "sqrt",
}

local rows = {}

local function check(method, expectation, body)
    if body == "" then
        return { "`"..method.."`", expectation, "—", "🟥 não encontrado" }
    end
    if expectation == "ignore_na flag" then
        local has_flag = body:find("ignore_na") ~= nil
        return { "`"..method.."`", expectation,
                 has_flag and "tem ignore_na" or "sem ignore_na",
                 has_flag and "🟩" or "🟨" }
    elseif expectation == "erra com null" then
        local has_check = body:find("nulos") ~= nil or
                          body:find("count_nonnull") ~= nil or
                          body:find("smaug:.+sort.+null") ~= nil
        return { "`"..method.."`", expectation,
                 has_check and "verifica nulls" or "sem verificação",
                 has_check and "🟩" or "🟨" }
    elseif expectation == "propaga null" then
        local has_propagation = body:find("is_null") ~= nil or
                                body:find("set_null") ~= nil or
                                body:find("== nil") ~= nil
        return { "`"..method.."`", expectation,
                 has_propagation and "propaga" or "sem propagação visível",
                 has_propagation and "🟩" or "🟨" }
    end
    return { "`"..method.."`", expectation, "?", "?" }
end

for _, m in ipairs(with_ignore_na_pattern) do
    local body = method_body(series, m)
    rows[#rows+1] = check(m, "ignore_na flag", body)
end
for _, m in ipairs(err_on_null) do
    local body = method_body(series, m)
    rows[#rows+1] = check(m, "erra com null", body)
end
for _, m in ipairs(propagate) do
    local body = method_body(series, m)
    rows[#rows+1] = check(m, "propaga null", body)
end

local header = { "método", "política esperada", "detectado", "status" }

local out = {
    C.section(7, "Tratamento de null consistente",
        "Cada método tem uma política de null esperada (ignore_na, erra, propaga). "
        .. "Verificação heurística sobre o corpo da função. 🟨 = padrão esperado "
        .. "não foi detectado; pode ser implementação alternativa ou bug."),
    "",
    C.render_table(header, rows),
    "",
}

io.write(table.concat(out, "\n"))
