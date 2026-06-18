-- scripts/parity/09_sentinels.lua
-- Eixo 9: sentinelas e contratos defensivos.
-- Verifica:
--   1. Em C, cada *_get retorna sentinela consistente em erro/null
--   2. Em Lua, mensagens de erro têm prefixo padronizado "smaug:"

local C = dofile("scripts/parity/common.lua")

-- ----------------------------------------------------------------
-- C: sentinelas
-- ----------------------------------------------------------------
local files = {
    {file="src/smaug_ops_f64.c", dtype="f64", expected="NaN"},
    {file="src/smaug_ops_i64.c", dtype="i64", expected="INT64_MIN"},
    {file="src/smaug_ops_bool.c", dtype="bool", expected="false / mask"},
    {file="src/smaug_str.c", dtype="str", expected="NULL ptr"},
    {file="src/smaug_datetime.c", dtype="dt", expected="INT64_MIN / DT_SENTINEL"},
}

local rows_c = {}
for _, item in ipairs(files) do
    local content = C.read_file(item.file) or ""
    local has_sentinel
    if item.dtype == "f64" then
        has_sentinel = content:find("0.0/0.0") or content:find("NAN")
    elseif item.dtype == "i64" or item.dtype == "dt" then
        has_sentinel = content:find("INT64_MIN") or content:find("SENTINEL")
    elseif item.dtype == "bool" then
        has_sentinel = content:find("false") and content:find("mask")
    elseif item.dtype == "str" then
        has_sentinel = content:find("return NULL")
    end
    rows_c[#rows_c+1] = {
        "`"..item.dtype.."`",
        item.expected,
        has_sentinel and "🟩 usa" or "🟨 não detectado",
    }
end

-- ----------------------------------------------------------------
-- Lua: mensagens de erro padronizadas
-- ----------------------------------------------------------------
local series  = C.read_series_lua() or ""
local dataset = C.read_dataset_lua() or ""

local function count_errors(content, prefix_pattern)
    local total, padronizadas = 0, 0
    for err_msg in content:gmatch('error%(%s*"([^"]+)"') do
        total = total + 1
        if err_msg:find(prefix_pattern) then
            padronizadas = padronizadas + 1
        end
    end
    -- Também pega erros com concatenação: error("smaug: ..."..x.."...")
    for err_msg in content:gmatch('error%(%s*"([^"]+)%.%.') do
        total = total + 1
        if err_msg:find(prefix_pattern) then
            padronizadas = padronizadas + 1
        end
    end
    return padronizadas, total
end

local s_ok, s_total = count_errors(series,  "^smaug:")
local d_ok, d_total = count_errors(dataset, "^smaug:")

-- ----------------------------------------------------------------
-- Saída
-- ----------------------------------------------------------------
local out = {
    C.section(9, "Sentinelas e contratos defensivos",
        "Backend C deve usar sentinela documentada em retorno de `get`. Frontend "
        .. "Lua deve usar prefixo `smaug:` em todas as mensagens de erro."),
    "",
    "### Sentinelas C",
    "",
    C.render_table({"dtype", "sentinela esperada", "presente?"}, rows_c),
    "",
    "### Mensagens de erro Lua",
    "",
    string.format("- `series.lua`: %d/%d erros com prefixo `smaug:` (%.1f%%)",
                  s_ok, s_total, s_total > 0 and 100*s_ok/s_total or 0),
    string.format("- `dataset.lua`: %d/%d erros com prefixo `smaug:` (%.1f%%)",
                  d_ok, d_total, d_total > 0 and 100*d_ok/d_total or 0),
    "",
}

io.write(table.concat(out, "\n"))
