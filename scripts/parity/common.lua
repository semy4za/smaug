-- scripts/parity/common.lua
-- Helpers compartilhados por todos os scripts de paridade.
-- Princípio: zero dependências externas. Parsing por regex.

local M = {}

-- ===================================================================
-- Leitura de arquivo como string
-- ===================================================================
function M.read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

-- ===================================================================
-- Submódulos do split (Fase 4), na ordem de carregamento do init.lua.
-- Fonte da verdade explícita: sem shell (`find` não existe igual no
-- Windows), portanto determinístico e idêntico entre Linux e Windows.
-- A leitura é tolerante: arquivo ausente é ignorado, nunca quebra.
-- Manutenção: ao adicionar/remover um submódulo, atualizar esta lista.
-- ===================================================================
M.SERIES_SUBMODULES = {
    "lua/smaug/core/series/_types.lua",
    "lua/smaug/core/series/_core.lua",
    "lua/smaug/core/series/_factories.lua",
    "lua/smaug/core/series/_bool_ops.lua",
    "lua/smaug/core/series/access/_access.lua",
    "lua/smaug/core/series/access/_transform.lua",
    "lua/smaug/core/series/stats/_reduce.lua",
    "lua/smaug/core/series/stats/_stat.lua",
    "lua/smaug/core/series/stats/_stat_adv.lua",
    "lua/smaug/core/series/window/_cumulative.lua",
    "lua/smaug/core/series/window/_rolling.lua",
    "lua/smaug/core/series/selection/_predicates.lua",
    "lua/smaug/core/series/selection/_selection.lua",
    "lua/smaug/core/series/text/_str.lua",
    "lua/smaug/core/series/temporal/_dt.lua",
    "lua/smaug/core/series/categorical/_categorical.lua",
    "lua/smaug/core/series/init.lua",
}

M.DATASET_SUBMODULES = {
    "lua/smaug/core/dataset/_core.lua",
    "lua/smaug/core/dataset/_relational.lua",
    "lua/smaug/core/dataset/_stat.lua",
    "lua/smaug/core/dataset/_io_support.lua",
    "lua/smaug/core/dataset/init.lua",
}

-- Concatena uma lista de submódulos numa única string de fonte.
local function concat_submodules(files)
    local parts = {}
    for _, path in ipairs(files) do
        local c = M.read_file(path)
        if c then
            parts[#parts+1] = "-- === " .. path .. " ===\n" .. c
        end
    end
    return table.concat(parts, "\n")
end

-- ===================================================================
-- Lê lua/smaug/core/series.lua (monolítico) ou, se não existir,
-- concatena os submódulos da pasta series/ na ordem canônica.
-- Usado pelos scripts de paridade que fazem análise estática do fonte.
-- ===================================================================
function M.read_series_lua()
    local mono = M.read_file("lua/smaug/core/series.lua")
    if mono then return mono end
    return concat_submodules(M.SERIES_SUBMODULES)
end

-- ===================================================================
-- Lê lua/smaug/core/dataset.lua (monolítico) ou, se não existir,
-- concatena os submódulos da pasta dataset/ na ordem canônica.
-- ===================================================================
function M.read_dataset_lua()
    local mono = M.read_file("lua/smaug/core/dataset.lua")
    if mono then return mono end
    return concat_submodules(M.DATASET_SUBMODULES)
end

-- ===================================================================
-- Carrega exceções de scripts/parity/exceptions.txt.
-- Retorna tabela: {[eixo]={[chave]=razão, ...}, ...}
-- Formato: linhas "EIXO:CHAVE razão de existência"
-- # no início = comentário. Linhas vazias ignoradas.
-- ===================================================================
function M.load_exceptions(path)
    path = path or "scripts/parity/exceptions.txt"
    local out = {}
    local f = io.open(path, "r")
    if not f then return out end
    for line in f:lines() do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1,1) ~= "#" then
            local eixo, chave, razao = line:match("^([^:]+):(%S+)%s+(.+)$")
            if eixo and chave then
                out[eixo] = out[eixo] or {}
                out[eixo][chave] = razao
            end
        end
    end
    f:close()
    return out
end

-- ===================================================================
-- Parsing de funções Lua por padrão "function PREFIX.NOME" / "PREFIX:NOME".
-- Retorna lista ordenada de nomes únicos.
-- ===================================================================
function M.extract_lua_methods(content, pattern)
    local seen, list = {}, {}
    for name in content:gmatch(pattern) do
        if not seen[name] then
            seen[name] = true
            list[#list+1] = name
        end
    end
    table.sort(list)
    return list
end

-- ===================================================================
-- Parsing de declarações C por prefixo.
-- Lê headers e source: smaug_PREFIX_NOME(...)
-- Retorna lista ordenada de nomes (sem o prefixo "smaug_PREFIX_").
-- ===================================================================
function M.extract_c_functions(content, prefix)
    -- Captura: tipo_retorno smaug_PREFIX_NOME(
    -- Aceita: "smaug_f64_create(", "smaug_dt_set(" etc.
    local seen, list = {}, {}
    local needle = "smaug_" .. prefix .. "_([%w_]+)%s*%("
    for name in content:gmatch(needle) do
        if not seen[name] then
            seen[name] = true
            list[#list+1] = name
        end
    end
    table.sort(list)
    return list
end

-- ===================================================================
-- Conjunto: tabela {chave=true,...}
-- ===================================================================
function M.set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

-- ===================================================================
-- Renderiza tabela markdown.
-- header = {"col1","col2",...}
-- rows = lista de listas
-- ===================================================================
function M.render_table(header, rows)
    local out = {}
    out[#out+1] = "| " .. table.concat(header, " | ") .. " |"
    local sep = {}
    for i = 1, #header do sep[i] = i == 1 and ":---" or ":-:" end
    out[#out+1] = "| " .. table.concat(sep, " | ") .. " |"
    for _, row in ipairs(rows) do
        out[#out+1] = "| " .. table.concat(row, " | ") .. " |"
    end
    return table.concat(out, "\n")
end

-- ===================================================================
-- Conta status (🟩 ⬜ 🟨 🟥) numa lista de linhas-resultado.
-- ===================================================================
function M.count_status(rows, col_idx)
    local c = {ok=0, exc=0, warn=0, err=0}
    for _, row in ipairs(rows) do
        local cell = row[col_idx] or ""
        if     cell:find("🟩") then c.ok   = c.ok   + 1
        elseif cell:find("⬜") then c.exc  = c.exc  + 1
        elseif cell:find("🟨") then c.warn = c.warn + 1
        elseif cell:find("🟥") then c.err  = c.err  + 1
        end
    end
    return c
end

-- ===================================================================
-- Cabeçalho de seção
-- ===================================================================
function M.section(num, title, summary)
    local out = {}
    out[#out+1] = ""
    out[#out+1] = "## Eixo " .. num .. " — " .. title
    out[#out+1] = ""
    if summary then
        out[#out+1] = summary
        out[#out+1] = ""
    end
    return table.concat(out, "\n")
end

return M
