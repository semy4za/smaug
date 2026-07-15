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

return M
