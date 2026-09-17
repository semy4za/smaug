-- tests/core/test_collation.lua
-- Invariante de colação Lua <-> C (item 12.34).
--
-- Por que este teste existe:
-- a colação de string do Smaug vive no Anel 0 (smaug_cmp_bytes: lexicográfica
-- por bytes, prefixo igual desempata pela mais curta). Mas o CategoricalSeries
-- é dtype Tier 2 -- Lua puro, sem backend C -- e compara com o operador `<` do
-- próprio Lua. Isso está CERTO: fazê-lo chamar o C por elemento seria o
-- antipadrão de loop sobre FFI que o item 10 combate.
--
-- O problema é que as duas só concordam por uma razão que ninguém escreveu: o
-- LuaJIT compara string por memcmp. No Lua padrão (5.1/5.3) o operador `<` usa
-- strcoll, que é DEPENDENTE DE LOCALE -- e sob um locale não-C o categorical
-- passaria a ordenar diferente do resto da biblioteca, em silêncio, sem que
-- nenhum teste existente notasse.
--
-- Este arquivo converte a suposição em verificação. Se um dia o interpretador
-- mudar, ou alguém rodar sob outro runtime, isto falha alto.
--
-- Rode da raiz: luajit tests/core/test_collation.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")

local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

-- Pares escolhidos onde memcmp e colação de locale DIVERGEM de fato.
-- Sob locale pt_BR/en_US, strcoll costuma ordenar case-insensitive e tratar
-- acento como equivalente à letra base -- exatamente o oposto de memcmp.
local comparison_pairs = {
    { "a",     "B"     },  -- minúscula x MAIÚSCULA: byte 'a'(97) > 'B'(66)
    { "Z",     "a"     },  -- 'Z'(90) < 'a'(97); locale poria "a" antes de "Z"
    { "abc",   "abd"   },  -- diferença no último byte
    { "ab",    "abc"   },  -- prefixo: a mais curta vem antes
    { "",      "a"     },  -- vazia é a menor de todas
    { "",      ""      },  -- ambas vazias: iguais
    { "café",  "cafe"  },  -- acento multibyte (UTF-8): 'é' > 'e' por byte
    { "a",     "á"     },
    { "A",     "a"     },
    { "10",    "9"     },  -- ordem lexicográfica, não numérica
    { "ab\0z", "ab\0a" },  -- NUL embutido: compara os bytes DEPOIS do NUL
}

for pair_index, comparison_pair in ipairs(comparison_pairs) do
    local left_value, right_value = comparison_pair[1], comparison_pair[2]
    local comparison_description = string.format("%q x %q", left_value, right_value):gsub("\\0", "\\0")

    -- Lado C: série com left_value, comparada com right_value pelo Anel 0.
    local source_series = smaug.Series({ left_value }, "string")
    local backend_less_than = source_series:lt(right_value):get(1)
    local backend_greater_than = source_series:gt(right_value):get(1)
    local backend_equal = source_series:eq(right_value):get(1)

    -- lado Lua: o operador nativo, que é o que o CategoricalSeries usa
    check((left_value < right_value) == backend_less_than, "Lua '<' concorda com o C em " .. comparison_description)
    check((left_value > right_value) == backend_greater_than, "Lua '>' concorda com o C em " .. comparison_description)
    check((left_value == right_value) == backend_equal, "Lua '==' concorda com o C em " .. comparison_description)
end

-- E a consequência prática: CategoricalSeries (compara em Lua) tem de dar o
-- mesmo resultado que Series<string> (compara no C) sobre os mesmos dados.
do
    local source_values = { "a", "B", "Z", "ab", "á" }
    local string_series = smaug.Series(source_values, "string")
    local categorical_series = smaug.Series(source_values, "string"):astype("categorical")
    for target_index, comparison_target in ipairs({ "B", "a", "M", "ab", "" }) do
        local string_comparison, categorical_comparison = string_series:lt(comparison_target), categorical_series:lt(comparison_target)
        for row_index = 1, #source_values do
            check(string_comparison:get(row_index) == categorical_comparison:get(row_index),
                  "categorical concorda com string em lt('" .. comparison_target .. "') idx " .. row_index)
        end
    end
end

-- sort usa a mesma colação (o desempate por índice é preocupação de sort, não
-- de colação): a ordem resultante tem de ser a de memcmp, não a de locale.
do
    local sorted_series = smaug.Series({ "b", "A", "a", "B" }, "string"):sort()
    check(sorted_series:get(1) == "A" and sorted_series:get(2) == "B" and sorted_series:get(3) == "a" and sorted_series:get(4) == "b",
          "sort ordena por byte (maiúsculas antes), não por locale")
end

print(string.format("OK — %d checks passaram (colação: invariante Lua <-> C)", passed_checks))
