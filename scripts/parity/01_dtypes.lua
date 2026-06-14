-- scripts/parity/01_dtypes.lua
-- Eixo 1: paridade de métodos entre dtypes.
-- Para cada método de Series e cada dtype (f64, i64, bool, string, datetime,
-- categorical), determina se está disponível.
--
-- Saída: tabela markdown anexada a docs/PARITY_REPORT.md (ou stdout).

local C = dofile("scripts/parity/common.lua")

-- ----------------------------------------------------------------
-- Universo de métodos rastreáveis no frontend Lua (de Series.methods e CategoricalSeries)
-- ----------------------------------------------------------------
local series_content = C.read_file("lua/smaug/core/series.lua")
        or error("não foi possível ler lua/smaug/core/series.lua")

-- Series.methods (compartilhado por f64, i64, bool, string, datetime via DTYPES dispatch)
local series_methods = C.extract_lua_methods(
    series_content, "function methods%.([%w_]+)")

-- Aliases via "methods.X = methods.Y"
local aliases = {}
for k, v in series_content:gmatch("methods%.([%w_]+)%s*=%s*methods%.([%w_]+)") do
    aliases[k] = v
end

-- CategoricalSeries.* (classe separada)
local cat_methods = C.extract_lua_methods(
    series_content, "function CategoricalSeries[%.:]([%w_]+)")
-- Filtra factories (from_*)
local cat_methods_inst = {}
for _, m in ipairs(cat_methods) do
    if not m:match("^from_") then
        cat_methods_inst[#cat_methods_inst+1] = m
    end
end
cat_methods = cat_methods_inst

-- ----------------------------------------------------------------
-- Determinar qual dtype tem qual método.
-- Como Series.methods é compartilhado por dispatch, todos os dtypes do
-- núcleo (f64, i64, bool, string, datetime) HERDAM os mesmos métodos —
-- mas alguns só funcionam para certos dtypes (assertion no corpo).
--
-- A forma robusta é varrer o corpo de cada método e detectar guards
-- do tipo "self._dtype ~= 'string'" ou "if self._dtype == 'float64'".
-- ----------------------------------------------------------------

local DTYPES = {"f64", "i64", "bool", "string", "datetime", "categorical"}
local DTYPE_NAMES = {
    f64="float64", i64="int64", bool="bool",
    string="string", datetime="datetime", categorical="categorical",
}

-- Extrai o corpo de cada método de Series.methods.
-- Heurística: do "function methods.NOME(...)" até a próxima "function ".
local function extract_method_body(content, fname)
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
    if next_fn then
        return rest:sub(1, next_fn - 1)
    end
    return rest
end

-- Determina se o método aceita um dtype específico, lendo o corpo.
-- Heurísticas (caçam padrões REAIS no código):
--
--   Padrão A — "guard de erro com lista positiva":
--     if self._dtype ~= "X" and self._dtype ~= "Y" then error(...) end
--     → permite só {X, Y}
--
--   Padrão B — "guard de exclusão":
--     if self._dtype == "X" then error(...) end
--     → bloqueia X
--
--   Default: sem guard → aceita todos os dtypes do núcleo.
--
local function method_accepts(body, dtype_lua)
    if body == "" then return true end

    -- Padrão A: "self._dtype ~= "X"" e em sequência "error("
    -- Capturamos os dtypes permitidos do bloco de guard inicial.
    -- Estratégia: encontrar UM bloco "if self._dtype ~= ... then error"
    -- e listar todos os dtypes que aparecem em "self._dtype ~= "TIPO"" dentro dele.
    local guard_block = body:match("if%s+(self%._dtype%s*~=.-)then%s*[\r\n]+%s*error")
    if guard_block then
        local allowed = {}
        for tipo in guard_block:gmatch('self%._dtype%s*~=%s*"(%w+)"') do
            allowed[tipo] = true
        end
        if next(allowed) then
            return allowed[dtype_lua] == true
        end
    end

    -- Padrão B: "if self._dtype == "X" then error"
    -- Lista dtypes bloqueados.
    for tipo in body:gmatch('if%s+self%._dtype%s*==%s*"(%w+)"%s*then%s*[\r\n]+%s*error') do
        if tipo == dtype_lua then return false end
    end

    return true
end

-- ----------------------------------------------------------------
-- Métodos de CategoricalSeries são gravados separadamente.
-- ----------------------------------------------------------------
local cat_set = C.set(cat_methods)

-- Universo final = união de métodos Series, aliases e CategoricalSeries
local universe_set = {}
for _, m in ipairs(series_methods) do universe_set[m] = true end
for k       in pairs(aliases)       do universe_set[k] = true end
for _, m in ipairs(cat_methods)     do universe_set[m] = true end
-- Filtra Series.from_table, Series.new etc. (não são métodos)
universe_set["from_table"] = nil
universe_set["from_codes"] = nil

local universe = {}
for m in pairs(universe_set) do universe[#universe+1] = m end
table.sort(universe)

-- ----------------------------------------------------------------
-- Para cada método × dtype, decide o status
-- ----------------------------------------------------------------
local excs = C.load_exceptions()
local excs1 = excs["1"] or {}

local rows = {}
local stats_methods = 0
local stats_cells = 0

for _, method in ipairs(universe) do
    local row = { "`" .. method .. "`" }
    local body_series = extract_method_body(series_content, method)
    local in_series_methods = body_series ~= ""

    for _, d in ipairs(DTYPES) do
        local cell
        local key = method .. "/" .. d
        local exc = excs1[key]

        if d == "categorical" then
            if cat_set[method] then
                cell = "✅"
            elseif exc then
                cell = "⚪"
            else
                cell = "⚠️"
            end
        else
            -- núcleo (f64/i64/bool/string/datetime) usa Series.methods
            local lua_name = DTYPE_NAMES[d]
            -- Se for alias, resolve para o método original antes de extrair corpo
            local lookup = aliases[method] or method
            local body_for_lookup = (lookup == method) and body_series
                                    or extract_method_body(series_content, lookup)
            local has_definition = body_for_lookup ~= "" or aliases[method]
            if has_definition then
                local ok = method_accepts(body_for_lookup, lua_name)
                if ok then
                    cell = "✅"
                elseif exc then
                    cell = "⚪"
                else
                    cell = "⚠️"
                end
            else
                -- método não está em Series.methods — verifica se é CategoricalSeries-only
                if cat_set[method] then
                    -- método existe só em CategoricalSeries
                    if exc then cell = "⚪" else cell = "⚠️" end
                else
                    cell = "⚠️"
                end
            end
        end
        stats_cells = stats_cells + 1
        row[#row+1] = cell
    end
    rows[#rows+1] = row
    stats_methods = stats_methods + 1
end

-- ----------------------------------------------------------------
-- Renderiza saída
-- ----------------------------------------------------------------
local header = { "método", "f64", "i64", "bool", "string", "datetime", "categorical" }
local section = C.section(1, "Paridade de métodos entre dtypes",
    "Cada linha = um método rastreado em `Series.methods` ou `CategoricalSeries`. "
    .. "Coluna = um dos 6 dtypes. ✅ disponível · ⚪ não aplicável (exceção registrada) · "
    .. "⚠️ ausência sem registro (suspeita) · ❌ inconsistência clara.")

local out = { section, C.render_table(header, rows), "" }

-- Sumário
local total_cells = stats_methods * #DTYPES
local cnt = { ok=0, exc=0, warn=0 }
for _, row in ipairs(rows) do
    for i = 2, #row do
        local c = row[i]
        if     c:find("✅") then cnt.ok   = cnt.ok   + 1
        elseif c:find("⚪") then cnt.exc  = cnt.exc  + 1
        elseif c:find("⚠️") then cnt.warn = cnt.warn + 1
        end
    end
end
out[#out+1] = string.format("**Sumário Eixo 1:** %d métodos × %d dtypes = %d células · "
    .. "✅ %d (%.1f%%) · ⚪ %d (%.1f%%) · ⚠️ %d (%.1f%%)",
    stats_methods, #DTYPES, total_cells,
    cnt.ok,   100*cnt.ok/total_cells,
    cnt.exc,  100*cnt.exc/total_cells,
    cnt.warn, 100*cnt.warn/total_cells)
out[#out+1] = ""

io.write(table.concat(out, "\n"))
