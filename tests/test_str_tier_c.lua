-- tests/test_str_tier_c.lua
-- Bloco F.4 — accessor .str Tier C (ASCII, sem regex, sem Unicode).
--   count, isalnum/isalpha/isdigit/isspace/islower/isupper,
--   removeprefix/removesuffix, capitalize/title/swapcase, join
--
-- Roda da raiz: luajit tests/test_str_tier_c.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")
local S  = smaug.Series
local NA = smaug.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- ================================================================
-- 1. count — ocorrências literais não-sobrepostas
-- ================================================================

local c = S.from_table({"banana", "aaaa", "xyz", "", NA}, "string")
local cnt = c.str:count("a")
check(cnt._dtype == "int64",        "count → int64")
check(cnt:get(1) == 3,              "count 'a' em banana = 3")
check(cnt:get(2) == 4,              "count 'a' em aaaa = 4")
check(cnt:get(3) == 0,              "count 'a' em xyz = 0")
check(cnt:get(4) == 0,              "count 'a' em vazia = 0")
check(cnt:get(5) == nil,            "count NA → nil")

-- não-sobreposto: "aa" em "aaaa" = 2 (não 3)
local cnt2 = c.str:count("aa")
check(cnt2:get(2) == 2,             "count 'aa' em aaaa = 2 (não-sobreposto)")
check(cnt2:get(1) == 0,             "count 'aa' em banana = 0 (a's não-adjacentes)")

-- substring multichar
local cm = S.from_table({"abcabcabc"}, "string")
check(cm.str:count("abc"):get(1) == 3, "count 'abc' = 3")

-- sub vazio → erro
local ok_empty = pcall(function() c.str:count("") end)
check(not ok_empty,                 "count substring vazia = erro")
-- não-string → erro
local ok_type = pcall(function() c.str:count(5) end)
check(not ok_type,                  "count não-string = erro")

-- ================================================================
-- 2. Predicados ASCII — string vazia sempre false; null → nil
-- ================================================================

local p = S.from_table({
    "abc123",  -- 1: alnum
    "abc",     -- 2: alpha, lower
    "123",     -- 3: digit
    "   ",     -- 4: space
    "ABC",     -- 5: alpha, upper
    "abC",     -- 6: alpha, misto
    "",        -- 7: vazia
    NA,        -- 8: null
}, "string")

local alnum = p.str:isalnum()
check(alnum._dtype == "bool",       "isalnum → bool")
check(alnum:get(1) == true,         "isalnum abc123 → true")
check(alnum:get(4) == false,        "isalnum espaços → false")
check(alnum:get(7) == false,        "isalnum vazia → false")
check(alnum:get(8) == nil,          "isalnum NA → nil")

local alpha = p.str:isalpha()
check(alpha:get(1) == false,        "isalpha abc123 → false (tem dígitos)")
check(alpha:get(2) == true,         "isalpha abc → true")
check(alpha:get(7) == false,        "isalpha vazia → false")

local digit = p.str:isdigit()
check(digit:get(3) == true,         "isdigit 123 → true")
check(digit:get(1) == false,        "isdigit abc123 → false")
check(digit:get(7) == false,        "isdigit vazia → false")

local space = p.str:isspace()
check(space:get(4) == true,         "isspace '   ' → true")
check(space:get(2) == false,        "isspace abc → false")
check(space:get(7) == false,        "isspace vazia → false")

local lower = p.str:islower()
check(lower:get(2) == true,         "islower abc → true")
check(lower:get(5) == false,        "islower ABC → false")
check(lower:get(6) == false,        "islower abC → false (tem maiúscula)")
check(lower:get(3) == false,        "islower 123 → false (sem letras)")
check(lower:get(7) == false,        "islower vazia → false")

local upper = p.str:isupper()
check(upper:get(5) == true,         "isupper ABC → true")
check(upper:get(2) == false,        "isupper abc → false")
check(upper:get(6) == false,        "isupper abC → false (tem minúscula)")
check(upper:get(3) == false,        "isupper 123 → false (sem letras)")

-- isspace com tab/newline
local ws = S.from_table({"\t\n", " \t ", "a b"}, "string")
check(ws.str:isspace():get(1) == true,  "isspace tab+newline → true")
check(ws.str:isspace():get(3) == false, "isspace 'a b' → false")

-- ================================================================
-- 3. removeprefix / removesuffix — idempotente
-- ================================================================

local r = S.from_table({"unhappy", "happy", "test.lua", "test", NA}, "string")

local rp = r.str:removeprefix("un")
check(rp._dtype == "string",        "removeprefix → string")
check(rp:get(1) == "happy",         "removeprefix un de unhappy → happy")
check(rp:get(2) == "happy",         "removeprefix un de happy → happy (idempotente)")
check(rp:get(5) == nil,             "removeprefix NA → nil")

local rs = r.str:removesuffix(".lua")
check(rs:get(3) == "test",          "removesuffix .lua de test.lua → test")
check(rs:get(4) == "test",          "removesuffix .lua de test → test (idempotente)")

-- prefixo/sufixo vazio → cópia inalterada
check(r.str:removeprefix(""):get(1) == "unhappy", "removeprefix vazio → inalterado")
check(r.str:removesuffix(""):get(1) == "unhappy", "removesuffix vazio → inalterado")

-- prefixo maior que a string
local short = S.from_table({"ab"}, "string")
check(short.str:removeprefix("abcdef"):get(1) == "ab", "removeprefix maior → inalterado")

-- não-string → erro
local ok_rp = pcall(function() r.str:removeprefix(5) end)
check(not ok_rp,                    "removeprefix não-string = erro")

-- ================================================================
-- 4. capitalize / title / swapcase
-- ================================================================

local k = S.from_table({"hello WORLD", "foo bar baz", "aBcD", "", NA}, "string")

local cap = k.str:capitalize()
check(cap:get(1) == "Hello world",  "capitalize hello WORLD → Hello world")
check(cap:get(3) == "Abcd",         "capitalize aBcD → Abcd")
check(cap:get(4) == "",             "capitalize vazia → vazia")
check(cap:get(5) == nil,            "capitalize NA → nil")

local tit = k.str:title()
check(tit:get(1) == "Hello World",  "title hello WORLD → Hello World")
check(tit:get(2) == "Foo Bar Baz",  "title foo bar baz → Foo Bar Baz")
check(tit:get(3) == "Abcd",         "title aBcD → Abcd")

-- title com separadores não-letra
local tsep = S.from_table({"a-b c.d", "joão123silva"}, "string")
check(tsep.str:title():get(1) == "A-B C.D", "title com hífen/ponto/espaço")
-- 'joão' tem byte não-ASCII (ã); título trata cada letra ASCII; verifica que ç/ã não quebram
check(type(tsep.str:title():get(2)) == "string", "title com não-ASCII não quebra")

local swap = k.str:swapcase()
check(swap:get(1) == "HELLO world",  "swapcase hello WORLD → HELLO world")
check(swap:get(3) == "AbCd",         "swapcase aBcD → AbCd")

-- ================================================================
-- 5. join (atalho de cat)
-- ================================================================

local j = S.from_table({"a", "b", NA, "c"}, "string")
check(j.str:join("-") == "a-b-c",   "join '-' ignora nulos")
check(j.str:join("") == "abc",      "join '' concatena")
check(j.str:join("-") == j.str:cat("-"), "join idêntico a cat")

-- série vazia
local je = S.from_table({}, "string")
check(je.str:join(",") == "",       "join série vazia → vazia")

-- ================================================================
-- Resultado
-- ================================================================

print(string.format(
    "OK — %d checks passaram (str Tier C: count, is{alnum,alpha,digit,space," ..
    "lower,upper}, remove{prefix,suffix}, capitalize/title/swapcase, join)",
    n_ok))
