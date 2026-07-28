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
local Series = smaug.Series

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- Pares escolhidos onde memcmp e colação de locale DIVERGEM de fato.
-- Sob locale pt_BR/en_US, strcoll costuma ordenar case-insensitive e tratar
-- acento como equivalente à letra base -- exatamente o oposto de memcmp.
local pares = {
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

for _, p in ipairs(pares) do
    local a, b = p[1], p[2]
    local rot = string.format("%q x %q", a, b):gsub("\\0", "\\0")

    -- lado C: série com [a], comparada com o alvo b pelos comparadores do Anel 0
    local s = Series.from_table({ a }, "string")
    local c_lt = s:lt(b):get(1)
    local c_gt = s:gt(b):get(1)
    local c_eq = s:eq(b):get(1)

    -- lado Lua: o operador nativo, que é o que o CategoricalSeries usa
    check((a < b) == c_lt, "Lua '<' concorda com o C em " .. rot)
    check((a > b) == c_gt, "Lua '>' concorda com o C em " .. rot)
    check((a == b) == c_eq, "Lua '==' concorda com o C em " .. rot)
end

-- E a consequência prática: CategoricalSeries (compara em Lua) tem de dar o
-- mesmo resultado que Series<string> (compara no C) sobre os mesmos dados.
do
    local vals = { "a", "B", "Z", "ab", "á" }
    local ss = Series.from_table(vals, "string")
    local cs = Series.from_table(vals, "string"):astype("categorical")
    for _, alvo in ipairs({ "B", "a", "M", "ab", "" }) do
        local ms, mc = ss:lt(alvo), cs:lt(alvo)
        for i = 1, #vals do
            check(ms:get(i) == mc:get(i),
                  "categorical concorda com string em lt('" .. alvo .. "') idx " .. i)
        end
    end
end

-- sort usa a mesma colação (o desempate por índice é preocupação de sort, não
-- de colação): a ordem resultante tem de ser a de memcmp, não a de locale.
do
    local s = Series.from_table({ "b", "A", "a", "B" }, "string"):sort()
    check(s:get(1) == "A" and s:get(2) == "B" and s:get(3) == "a" and s:get(4) == "b",
          "sort ordena por byte (maiúsculas antes), não por locale")
end

print(string.format("OK — %d checks passaram (colação: invariante Lua <-> C)", n_ok))
