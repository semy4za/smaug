-- lua/smaug/core/keys.lua
--
-- Fonte ÚNICA de chave de igualdade/agrupamento a partir de valores de Series.
--
-- Problema que resolve: join, groupby, unique, nunique, value_counts, mode,
-- isin e duplicated precisam responder "estes dois valores são o mesmo?".
-- Cada um resolvia isso por conta própria com `type(v)..":"..tostring(v)` sobre
-- `series:get(i)`. Furos desse padrão espalhado:
--   1. `get(i)` para int64 passa por `tonumber()` -> double (mesma perda da
--      Sub-A do 9.1, na saida). Dois int64 distintos acima de 2^53 (ex.:
--      9007199254740992 e ...993 - IDs de banco, contadores) colapsavam na
--      MESMA chave: join casava linhas erradas, groupby fundia grupos,
--      unique/nunique/value_counts subcontavam - em silencio, sem erro.
--   2. `mode` e `isin` usavam `tostring(v)` SEM prefixo de tipo, divergindo dos
--      demais (colisao latente entre 1 e "1").
--
-- Desenho: o prefixo da chave e o **dtype da coluna** (fixo e conhecido), nao o
-- `type()` do valor Lua. Isso importa porque o mesmo valor int64 chega como
-- `number` via get() e como `cdata` via get_raw() - usar type() do valor faria
-- as duas formas divergirem (quebrava isin, que compara a serie contra uma lista
-- crua do usuario). O dtype e a fonte estavel: `int64:100` bate venha o 100 como
-- number (lista) ou cdata (serie). E chave composta (join concatena colunas de
-- dtypes diferentes) segue desambiguada - cada coluna traz seu proprio dtype.
--
-- Contrato: chave-de-igualdade != apresentacao (`display.lua`) != descricao-em-
-- erro (`errors.lua`) != serializacao (`smaug_fmt_*`). Aqui o objetivo e uma
-- representacao canonica ESTAVEL para comparar/agrupar. Duas responsabilidades:
--   . encode(series, row) -> string : chave de igualdade de uma posicao da serie.
--   . value(series, row)  -> valor  : o valor EXATO preservado, para quem
--       reconstroi uma coluna a partir da chave (groupby/value_counts/join
--       guardam a chave como valor no resultado; `get` ali degradaria o int64).
-- E, para valores fora de uma serie (a lista do isin):
--   . encode_value(v, dtype) -> string : mesma canonica, para um valor cru cujo
--       dtype de referencia e conhecido. encode() delega a ela.
--
-- Preservacao: int64 via get_raw (cdata; `tostring` preserva os 64 bits) e, na
-- lista crua, via `%.0f` (melhor esforco - number > 2^53 ja chegou degradado
-- pela Sub-A da entrada; para exato o usuario passa cdata `NNN LL`). float64/
-- string/bool sao exatos por get. datetime e exato na pratica (epoch_ms << 2^53;
-- 2^53 ms = ano 287586) - nao tem get_raw; latente inalcancavel, registrado.
--
-- Ponto de plugue futuro: a primitiva C de chave (E7/hash_series, item 10.5)
-- substitui o corpo destas funcoes sem tocar os call-sites.

local M = {}

-- Sentinela de NULL. Bytes de controle (\0) nao aparecem em conteudo textual
-- normal, entao nao colidem com uma string legitima. Mesmo valor que os
-- call-sites ja usavam, agora numa fonte so.
local NULL_KEY = "\0NULL\0"
M.NULL_KEY = NULL_KEY

-- encode_value: valor cru + dtype de referencia -> string canonica de igualdade.
-- Usada diretamente pelo isin (lista do usuario) e como nucleo de encode.
function M.encode_value(v, dtype)
    if v == nil then return NULL_KEY end
    if dtype == "int64" then
        -- Normaliza para representacao decimal sem sufixo, venha number ou cdata.
        if type(v) == "cdata" then
            return "int64:" .. (tostring(v):gsub("LL$", ""))
        end
        -- number: %.0f evita notacao cientifica; > 2^53 ja veio degradado (Sub-A).
        return "int64:" .. string.format("%.0f", v)
    end
    return dtype .. ":" .. tostring(v)
end

-- encode: chave de igualdade da posicao `row` (1-based) da serie.
-- int64 le via get_raw (cdata exato); demais via get. Delega a encode_value
-- para uma canonica so.
function M.encode(series, row)
    if series._dtype == "int64" then
        return M.encode_value(series:get_raw(row), "int64")
    end
    return M.encode_value(series:get(row), series._dtype)
end

-- value: valor EXATO da posicao `row`, para reconstruir coluna a partir da
-- chave. int64 -> cdata (get_raw); demais -> get. NULL -> nil (o caller decide
-- o sentinela do resultado, tipicamente NA).
function M.value(series, row)
    if series._dtype == "int64" then
        return series:get_raw(row)
    end
    return series:get(row)
end

return M
