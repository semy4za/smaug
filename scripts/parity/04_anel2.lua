-- scripts/parity/04_anel2.lua
-- Eixo 4: Anel 2 (groupby, join, concat, pivot) — paridade por dtype.
--
-- Examina o código de dataset.lua para identificar quais dtypes são aceitos
-- em cada operação. Heurística: procura por bloqueios explícitos
-- ("dtype ~= 'X'") no corpo das funções.

local C = dofile("scripts/parity/common.lua")

local ds = C.read_dataset_lua()

-- Extração de funções GroupBy
local gb_methods = C.extract_lua_methods(ds, "function GroupBy:([%w_]+)")

-- DataSet methods de interesse
local ds_ops_of_interest = {
    "groupby", "join", "concat", "pivot", "pivot_table", "melt",
    "stack", "unstack", "explode", "rolling", "sort_by", "filter",
}

local dtypes = {"float64", "int64", "bool", "string", "datetime", "categorical"}

-- ----------------------------------------------------------------
-- Função auxiliar: extrai corpo de uma função em dataset.lua
-- ----------------------------------------------------------------
local function method_body(content, fname)
    local s_start, s_end = content:find("function methods%."..fname.."%b()")
    if not s_start then
        s_start, s_end = content:find("function methods%."..fname.."%s*%(")
        if not s_start then return "" end
        local p = content:find("%)", s_end)
        if p then s_end = p end
    end
    local rest = content:sub(s_end + 1)
    local nxt = rest:find("\nfunction ")
    if nxt then return rest:sub(1, nxt - 1) end
    return rest
end

local function gb_method_body(content, fname)
    local s_start, s_end = content:find("function GroupBy:"..fname.."%b()")
    if not s_start then return "" end
    local rest = content:sub(s_end + 1)
    local nxt = rest:find("\nfunction ")
    if nxt then return rest:sub(1, nxt - 1) end
    return rest
end

-- ----------------------------------------------------------------
-- Heurística: analisar corpo para descobrir quais dtypes são aceitos
-- ----------------------------------------------------------------
local function dtype_accepted(body, dtype)
    if body == "" then return true end
    -- "if dt == 'float64' or dt == 'int64' then ... result[#] = c" → aceita
    -- "elseif dt == 'X' then error()" → bloqueia
    -- Estratégia conservadora: se aparece 'X' como string no corpo, marca como ✅
    -- Se não aparece, ⚠️ (suspeita).
    if body:find('"'..dtype..'"', 1, true) then
        return true, "menciona explicitamente"
    end
    -- Verifica também resolve_agg_cols-like guards
    return nil, "sem menção"
end

-- ----------------------------------------------------------------
-- GroupBy: agregações por dtype
-- ----------------------------------------------------------------
local rows_gb = {}
for _, m in ipairs(gb_methods) do
    if m:sub(1,1) ~= "_" then  -- pula internos
        local body = gb_method_body(ds, m)
        local row = { "`groupby."..m.."`" }
        for _, dt in ipairs(dtypes) do
            local ok = dtype_accepted(body, dt)
            row[#row+1] = ok == true and "✅" or "⚠️"
        end
        rows_gb[#rows_gb+1] = row
    end
end

-- ----------------------------------------------------------------
-- DataSet ops como groupby/join/concat/sort_by/filter por dtype
-- Aqui a análise é "qual dtype de coluna pode ser usado como
-- chave/argumento dessa operação"
-- ----------------------------------------------------------------
local rows_ds = {}
for _, op in ipairs(ds_ops_of_interest) do
    local body = method_body(ds, op)
    local row = { "`"..op.."`" }
    for _, dt in ipairs(dtypes) do
        local ok = dtype_accepted(body, dt)
        row[#row+1] = ok == true and "✅" or "⚠️"
    end
    rows_ds[#rows_ds+1] = row
end

-- ----------------------------------------------------------------
-- Saída
-- ----------------------------------------------------------------
local header = { "operação", "f64", "i64", "bool", "string", "datetime", "categorical" }

local out = {
    C.section(4, "Paridade Anel 2 (operações relacionais) por dtype",
        "Heurística conservadora: verifica menção explícita do dtype no corpo da "
        .. "função. ✅ = dtype mencionado explicitamente (provável suporte). "
        .. "⚠️ = dtype não mencionado (pode ser sem suporte, pode ser polimorfismo "
        .. "via dispatcher genérico — requer revisão manual)."),
    "",
    "### DataSet — operações estruturais",
    "",
    C.render_table(header, rows_ds),
    "",
    "### GroupBy — agregações",
    "",
    C.render_table(header, rows_gb),
    "",
}

io.write(table.concat(out, "\n"))
