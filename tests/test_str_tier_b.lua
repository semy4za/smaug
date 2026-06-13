-- tests/test_str_tier_b.lua
-- Teste do .str Tier B: find, slice, pad, zfill, rep, cat, split.
-- Rode da raiz:  luajit tests/test_str_tier_b.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

local s = smaug.Series.from_table({"hello world","foo bar","baz",NA}, "string")

-- ================================================================
-- find
-- ================================================================
local f = s.str:find("o")
check(f:get(1) == 5,           "find 'o' em 'hello world' = 5")
check(f:get(2) == 2,           "find 'o' em 'foo bar' = 2")
check(f:get(3) == 0,           "find 'o' em 'baz' = 0 (ausente)")
check(f:is_null(4),            "find: NA propaga")
check(f._dtype == "int64",     "find: dtype int64")

-- find string vazia -> sempre 1 (string vazia encontrada no início)
local fe = s.str:find("")
check(fe:get(1) == 1,          "find '': sempre 1")
check(fe:get(3) == 1,          "find '' em 'baz' = 1")

-- find inexistente
local fx = s.str:find("xyz")
check(fx:get(1) == 0,          "find 'xyz' = 0")
check(fx:get(3) == 0,          "find 'xyz' = 0")

-- erro: não-string
local ok1, _ = pcall(function() s.str:find(42) end)
check(not ok1,                  "find: erro não-string")

-- ================================================================
-- slice
-- ================================================================
local sl = s.str:slice(1, 3)
check(sl:get(1) == "hel",      "slice(1,3): 'hello world' -> 'hel'")
check(sl:get(2) == "foo",      "slice(1,3): 'foo bar' -> 'foo'")
check(sl:get(3) == "baz",      "slice(1,3): 'baz' -> 'baz'")
check(sl:is_null(4),           "slice: NA propaga")

-- índice negativo
local sln = s.str:slice(-3)
check(sln:get(1) == "rld",     "slice(-3): 'hello world' -> 'rld'")
check(sln:get(3) == "baz",     "slice(-3): 'baz' -> 'baz'")

-- slice além do tamanho (Lua retorna o que tiver)
local slb = s.str:slice(1, 100)
check(slb:get(1) == "hello world", "slice(1,100): retorna toda a string")

-- sem stop: vai até o fim
local sle = s.str:slice(7)
check(sle:get(1) == "world",   "slice(7): 'hello world' -> 'world'")

-- série vazia
local se = smaug.Series.from_table({}, "string")
check(se.str:slice(1,3):len() == 0, "slice: série vazia -> vazia")

-- ================================================================
-- pad
-- ================================================================
local p = s.str:pad(12, "left")
check(p:get(1) == " hello world",  "pad(12,left): 1 espaço antes")
check(p:get(2) == "     foo bar",  "pad(12,left): 5 espaços antes")
check(p:get(3) == "         baz",  "pad(12,left): 9 espaços antes")
check(p:is_null(4),                "pad: NA propaga")
check(p._dtype == "string",        "pad: dtype string")

local pr = s.str:pad(10, "right", "*")
check(pr:get(3) == "baz*******",   "pad(10,right,*): baz*******")

local pb = s.str:pad(12, "both")
check(#pb:get(2) == 12,            "pad(12,both): comprimento total=12")

-- string maior que width: retorna intacta
local pl = s.str:pad(3, "left")
check(pl:get(1) == "hello world",  "pad: string maior não trunca")

-- erros
local ok2, _ = pcall(function() s.str:pad(-1) end)
check(not ok2,                     "pad: width negativo recusado")
local ok3, _ = pcall(function() s.str:pad(5, "left", "ab") end)
check(not ok3,                     "pad: fillchar >1 char recusado")
local ok4, _ = pcall(function() s.str:pad(5, "centro") end)
check(not ok4,                     "pad: side inválido recusado")

-- ================================================================
-- zfill
-- ================================================================
local nums = smaug.Series.from_table({"42","7","100","1000",NA}, "string")
local z = nums.str:zfill(5)
check(z:get(1) == "00042",     "zfill(5): '42' -> '00042'")
check(z:get(2) == "00007",     "zfill(5): '7' -> '00007'")
check(z:get(3) == "00100",     "zfill(5): '100' -> '00100'")
check(z:get(4) == "01000",      "zfill(5): .1000. -> .01000. (5 chars total)")
check(z:is_null(5),            "zfill: NA propaga")

-- ================================================================
-- rep
-- ================================================================
local r = smaug.Series.from_table({"ab","x",NA}, "string")
local r2 = r.str:rep(2)
check(r2:get(1) == "abab",     "rep(2): 'ab' -> 'abab'")
check(r2:get(2) == "xx",       "rep(2): 'x' -> 'xx'")
check(r2:is_null(3),           "rep: NA propaga")

local r2s = r.str:rep(2, "-")
check(r2s:get(1) == "ab-ab",   "rep(2,'-'): 'ab' -> 'ab-ab'")
check(r2s:get(2) == "x-x",     "rep(2,'-'): 'x' -> 'x-x'")

local r0 = r.str:rep(0)
check(r0:get(1) == "",         "rep(0): string vazia")

-- erro: n < 0
local ok5, _ = pcall(function() r.str:rep(-1) end)
check(not ok5,                  "rep: n<0 recusado")

-- ================================================================
-- cat
-- ================================================================
local c = s.str:cat(", ")
check(c == "hello world, foo bar, baz", "cat: NA ignorado, sep correto")

local c2 = s.str:cat()
check(c2 == "hello worldfoo barbaz", "cat sem sep")

-- todos NA
local na_s = smaug.Series.from_table({NA, NA}, "string")
check(na_s.str:cat() == "",     "cat: todos NA -> string vazia")

-- série vazia
check(se.str:cat() == "",       "cat: série vazia -> string vazia")

-- ================================================================
-- split
-- ================================================================
local csv = smaug.Series.from_table({"a:b:c","x:y","z",NA}, "string")
local cols = csv.str:split(":")

check(#cols == 3,               "split: 3 colunas (max partes)")
check(cols[1]:get(1) == "a",   "split col1[1] = a")
check(cols[2]:get(1) == "b",   "split col2[1] = b")
check(cols[3]:get(1) == "c",   "split col3[1] = c")
check(cols[1]:get(2) == "x",   "split col1[2] = x")
check(cols[2]:get(2) == "y",   "split col2[2] = y")
check(cols[3]:is_null(2),      "split: col3[2] = NA (sem terceira parte)")
check(cols[1]:get(3) == "z",   "split col1[3] = z (sem sep)")
check(cols[2]:is_null(3),      "split: col2[3] = NA (sem segunda parte)")
check(cols[1]:is_null(4),      "split: col1[4] = NA (entrada NA)")

-- separador multi-char
local ms = smaug.Series.from_table({"a::b::c","x::y"}, "string")
local msp = ms.str:split("::")
check(msp[1]:get(1) == "a",    "split '::' col1 = a")
check(msp[2]:get(1) == "b",    "split '::' col2 = b")
check(msp[3]:get(1) == "c",    "split '::' col3 = c")

-- max_splits
local lim = smaug.Series.from_table({"a:b:c:d"}, "string")
local lsp = lim.str:split(":", 2)
check(#lsp == 3,                "split max=2: 3 partes")
check(lsp[1]:get(1) == "a",    "split max=2 [1]=a")
check(lsp[2]:get(1) == "b",    "split max=2 [2]=b")
check(lsp[3]:get(1) == "c:d",  "split max=2 [3]=c:d (resto)")

-- nenhum match: 1 coluna com a string original
local nm = smaug.Series.from_table({"abc","def"}, "string")
local nmp = nm.str:split(",")
check(#nmp == 1,                "split sem match: 1 coluna")
check(nmp[1]:get(1) == "abc",  "split sem match: valor original")

-- série vazia
local esp = se.str:split(":")
check(#esp == 0,                "split série vazia: 0 colunas")

-- erro: sep vazio
local ok6, _ = pcall(function() s.str:split("") end)
check(not ok6,                  "split: sep vazio recusado")

print(string.format("OK — %d checks passaram (str Tier B)", n_ok))
