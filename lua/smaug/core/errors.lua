-- lua/smaug/core/errors.lua
--
-- Fonte ÚNICA de descrição de valores em MENSAGENS DE ERRO (item 12.9).
--
-- Problema que resolve: `error("... " .. tostring(v))` com um `v` fornecido pelo
-- usuário dispara o `__tostring` do objeto. Se `v` for uma Series ou um DataSet,
-- a mensagem passa a conter os DADOS (medido: DataSet 20x1000 como índice gerava
-- 2459 chars de erro com o conteúdo das colunas). Erro deve dizer o que houve —
-- não despejar o dado em log/stderr/ticket.
--
-- Contrato: descrição-em-erro ≠ apresentação. `core/display.lua` responde "como
-- o usuário vê este valor numa tabela" (e PODE mostrar o dado, é o objetivo);
-- aqui respondemos "como referenciar este valor sem vazar conteúdo". São
-- responsabilidades distintas e deliberadamente separadas.
--
-- Uso: em toda mensagem de erro cujo argumento possa ser um objeto arbitrário
-- (índices, operandos, dtypes vindos do caller). Para valores já type-checados e
-- curtos (um cdata int64 validado, um `_dtype` interno) o `tostring` direto
-- continua correto — o helper existe para a fronteira não-confiável.

local M = {}

-- Teto de segurança para strings vindas do usuário: uma string de 100k não deve
-- virar uma mensagem de 100k.
local MAX_STR = 60

-- describe(v): descrição curta e segura de um valor, para uso em erro.
--   number            → o número ("3", "1.5")
--   nil / boolean     → "nil" / "true"
--   string            → aspas + truncada em MAX_STR ('"abc"', '"aaa…" (120 chars)')
--   cdata             → tostring (int64 etc. são curtos e informativos)
--   Series            → <Series 'nome' (dtype, len=N)>   — SEM os valores
--   CategoricalSeries → <CategoricalSeries 'nome' (len=N)>
--   DataSet           → <DataSet 'nome' [N linhas x M colunas]>  — SEM as células
--   outra table       → "table" (sem despejar o conteúdo)
--   function/userdata → o tipo
function M.describe(v)
    local tv = type(v)

    if tv == "number" or tv == "nil" or tv == "boolean" then
        return tostring(v)
    end

    if tv == "string" then
        if #v > MAX_STR then
            return string.format('"%s…" (%d chars)', v:sub(1, MAX_STR), #v)
        end
        return string.format('"%s"', v)
    end

    if tv == "cdata" then
        return tostring(v)
    end

    if tv == "table" then
        -- Objetos do Smaug: identifica pela estrutura, sem chamar __tostring
        -- (é exatamente o __tostring que despejaria os dados).
        if v._c ~= nil and v._dtype ~= nil then
            return string.format("<Series '%s' (%s, len=%d)>",
                tostring(v._name or "unnamed"), tostring(v._dtype),
                tonumber(v._c.size) or -1)
        end
        if v._codes ~= nil and v._levels ~= nil then
            return string.format("<CategoricalSeries '%s' (len=%d)>",
                tostring(v._name or "unnamed"), tonumber(v._size) or -1)
        end
        if v._columns ~= nil and v._col_names ~= nil then
            return string.format("<DataSet '%s' [%d linhas x %d colunas]>",
                tostring(v._name or "DataSet"), tonumber(v._length or 0),
                #v._col_names)
        end
        return "table"
    end

    return tv   -- function, userdata, thread
end

-- =====================================================================
-- suggest: "você quis dizer X?" (item 12.12)
-- =====================================================================

-- Distância de Levenshtein com early-exit: se passar de `max`, devolve max+1.
-- Só precisamos saber se está PERTO, não a distância exata.
local function levenshtein(a, b, max)
    local la, lb = #a, #b
    if math.abs(la - lb) > max then return max + 1 end
    local prev, cur = {}, {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        cur[0] = i
        local best = cur[0]
        local ai = a:byte(i)
        for j = 1, lb do
            local cost = (ai == b:byte(j)) and 0 or 1
            local d = prev[j] + 1
            local e = cur[j-1] + 1
            local f = prev[j-1] + cost
            if e < d then d = e end
            if f < d then d = f end
            cur[j] = d
            if d < best then best = d end
        end
        if best > max then return max + 1 end
        prev, cur = cur, prev
    end
    return prev[lb]
end

-- suggest(name, candidates): nome mais próximo de `name` entre as CHAVES de
-- `candidates`, ou nil se nada estiver perto o bastante.
--
-- Tolerância proporcional ao tamanho (2 para nomes >= 5 chars, 1 para curtos):
-- evita sugerir "sum" para "abs". Normaliza `_` e caixa antes de comparar, para
-- pegar o caso mais comum de confusão de convenção — `group_by`/`groupBy` vs
-- `groupby` — que sai com distância 0 na forma normalizada.
function M.suggest(name, candidates)
    if type(name) ~= "string" or #name == 0 then return nil end
    local function norm(s) return (s:gsub("_", ""):lower()) end
    local target = norm(name)
    local max    = (#name >= 5) and 2 or 1

    local best, best_d = nil, math.huge
    for cand in pairs(candidates) do
        if type(cand) == "string" and cand:sub(1, 1) ~= "_" then
            local d = levenshtein(target, norm(cand), max)
            if d < best_d then best, best_d = cand, d end
        end
    end
    if best_d <= max then return best end
    return nil
end

-- unknown_key(kind, name, candidates, extra): mensagem canônica de chave
-- desconhecida, com sugestão quando houver. `extra` é um complemento opcional
-- (ex.: mencionar que em DataSet a chave também poderia ser uma coluna).
-- check_plain_array(v, op, esperado, level): recusa objeto do Smaug onde se
-- espera uma tabela Lua simples.
--
-- Problema que resolve (12.38): guards escritos como `type(v) ~= "table"` não
-- distinguem um array de uma Series/DataSet — os dois são `table`. Como esses
-- objetos não têm parte array, `#v` dá 0 e `ipairs(v)` não itera nada, então a
-- chamada devolve resultado VAZIO ou ERRADO em silêncio, em vez de falhar.
-- Medido em 2026-07-28: `s:take(serie)` devolvia 0 elementos, `s:isin(serie)`
-- devolvia tudo false, `ds:select(serie)` devolvia 0 colunas.
--
-- Discriminador: objeto do Smaug tem metatable; tabela Lua simples não. A
-- mensagem nomeia a saída (`:to_table()`), porque o erro comum é justamente
-- passar a Series achando que ela serve de lista.
function M.check_plain_array(v, op, esperado, level)
    if type(v) ~= "table" then
        error("smaug: " .. op .. " espera " .. esperado
              .. "; recebido " .. M.describe(v), (level or 2) + 1)
    end
    if getmetatable(v) ~= nil then
        error("smaug: " .. op .. " espera " .. esperado
              .. " (tabela Lua), não um objeto do Smaug — "
              .. "use :to_table() para converter", (level or 2) + 1)
    end
end

function M.unknown_key(kind, name, candidates, extra)
    local msg = "smaug: " .. kind .. " '" .. tostring(name) .. "' não existe"
    local s = M.suggest(name, candidates)
    if s then msg = msg .. " — você quis dizer '" .. s .. "'?" end
    if extra then msg = msg .. " " .. extra end
    return msg
end

return M
