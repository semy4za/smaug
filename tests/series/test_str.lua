-- tests/series/test_str.lua
-- Accessor .str completo: Tier A + Tier B + Tier C.
-- Consolida: test_string.lua + test_str_tier_b.lua + test_str_tier_c.lua
-- Rode da raiz: luajit tests/series/test_str.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local Series = smaug.Series
local NA     = Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

--
-- Rode da raiz:  luajit tests/test_string.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local S     = smaug.Series

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
local function rejects(fn) return pcall(fn) == false end

-- ===================================================================
-- Construção e acesso
-- ===================================================================
do
    local s = S.from_table({"SP", "RJ", smaug.NA, "Minas"}, "string")
    check(s:len() == 4, "len")
    check(s:get(1) == "SP", "get string")
    check(s:get(4) == "Minas", "get string longa")
    check(s:get(3) == nil, "get NA -> nil")
    check(s:is_null(3), "is_null no NA")
    check(not s:is_null(1), "is_null false em valido")
    check(s:count_nonnull() == 3, "count_nonnull")
end

-- ===================================================================
-- String vazia é distinta de NULL
-- ===================================================================
do
    local s = S.from_table({"", smaug.NA, "x"}, "string")
    check(s:get(1) == "", "vazia -> '' (nao nil)")
    check(not s:is_null(1), "vazia nao e null")
    check(s:get(2) == nil, "NA -> nil")
    check(s:is_null(2), "NA e null")
    check(s:count_nonnull() == 2, "vazia conta como valida")
end

-- ===================================================================
-- Mutação: set (3 casos via backend), set_null, append
-- ===================================================================
do
    local s = S.from_table({"SP", "RJ", "MG"}, "string")
    -- mesmo tamanho
    s:set(1, "AC")
    check(s:get(1) == "AC", "set mesmo tamanho")
    -- maior (desloca buffer)
    s:set(1, "Bahia")
    check(s:get(1) == "Bahia" and s:get(2) == "RJ" and s:get(3) == "MG",
          "set maior preserva vizinhos")
    -- menor
    s:set(1, "PB")
    check(s:get(1) == "PB" and s:get(3) == "MG", "set menor preserva vizinhos")
    -- set vazia
    s:set(2, "")
    check(s:get(2) == "" and not s:is_null(2), "set '' = vazia valida")
    -- set_null
    s:set_null(3)
    check(s:is_null(3), "set_null")
    check(s:get(1) == "PB", "set_null preserva vizinho")

    -- append (encadeável) e append de NA
    local a = S.string(0)
    a:append("um"):append("dois")
    a:append(smaug.NA)
    a:append("quatro")
    check(a:len() == 4, "append len")
    check(a:get(1) == "um" and a:get(4) == "quatro", "append valores")
    check(a:is_null(3), "append NA -> null")
    check(a:count_nonnull() == 3, "count apos append com NA")
end

-- ===================================================================
-- clone independente
-- ===================================================================
do
    local s = S.from_table({"alpha", smaug.NA, "gamma"}, "string")
    local c = s:clone()
    check(c:get(1) == "alpha" and c:is_null(2) and c:get(3) == "gamma",
          "clone copia conteudo")
    c:set(1, "MUDADO")
    check(c:get(1) == "MUDADO" and s:get(1) == "alpha", "clone independente")
end

-- ===================================================================
-- Sem coerção: set recusa não-string; ops numéricas recusam com erro claro
-- ===================================================================
do
    local s = S.from_table({"a", "b"}, "string")
    check(rejects(function() s:set(1, 42) end), "set recusa numero")
    check(rejects(function() s:set(1, true) end), "set recusa boolean")
    -- operações numéricas não se aplicam
    check(rejects(function() return s:sum() end), "sum recusa string")
    check(rejects(function() return s:mean() end), "mean recusa string")
    check(rejects(function() return s:add(s) end), "add recusa string")
end

-- ===================================================================
-- Integração com DataSet (coluna de string)
-- ===================================================================
do
    local df = smaug.DataSet.from_columns({
        {"uf",  {"SP", "RJ", "MG"}, "string"},
        {"pop", {44, 17, 21},       "int64"},
    })
    check(df:nrows() == 3 and df:ncols() == 2, "dataset com coluna string")
    check(df:col("uf"):get(2) == "RJ", "acesso a coluna string")
    check(df:col("pop"):sum() == 82, "coluna numerica ao lado funciona")
end

-- ===================================================================
-- Comparações (eq/lt/gt) -> Series<bool>
-- ===================================================================
do
    local s = S.from_table({"SP", "RJ", smaug.NA, "MG", "SP"}, "string")

    local eq = s:eq("SP")
    check(eq:get(1) == true and eq:get(5) == true, "eq casa SP")
    check(eq:get(2) == false, "eq nao casa RJ")
    check(eq:get(3) == nil, "eq NULL -> nil")
    check(eq:count_true() == 2, "eq count_true")

    local lt = s:lt("RJ")
    check(lt:get(4) == true, "lt: MG < RJ")
    check(lt:get(1) == false, "lt: SP nao < RJ")
    check(lt:get(3) == nil, "lt NULL -> nil")

    local gt = s:gt("RJ")
    check(gt:get(1) == true, "gt: SP > RJ")
    check(gt:get(4) == false, "gt: MG nao > RJ")

    -- string vazia compara normalmente
    local s2 = S.from_table({"", "a"}, "string")
    check(s2:eq(""):get(1) == true, "eq '' casa vazia")
    check(s2:lt("a"):get(1) == true, "lt: '' < 'a'")

    -- recusa de tipo (sem coerção), nos dois sentidos
    check(rejects(function() return s:eq(42) end), "string:eq(numero) recusa")
    local n = S.from_table({1, 2}, "int64")
    check(rejects(function() return n:eq("x") end), "int64:eq(string) recusa")
end

-- ===================================================================
-- Seleção: filter (por máscara de comparação) e take (por índices)
-- ===================================================================
do
    local s = S.from_table({"SP", "RJ", smaug.NA, "MG", "SP"}, "string")

    -- o caso de uso principal: filter(eq)
    local f = s:filter(s:eq("SP"))
    check(f:len() == 2, "filter(eq SP) conta")
    check(f:get(1) == "SP" and f:get(2) == "SP", "filter(eq SP) valores")

    -- filter por lt (NULL nao passa)
    local f2 = s:filter(s:lt("RJ"))
    check(f2:len() == 1 and f2:get(1) == "MG", "filter(lt RJ) = MG")

    -- take reordenado, preserva NULL
    local t = s:take({4, 1, 3})
    check(t:len() == 3, "take conta")
    check(t:get(1) == "MG" and t:get(2) == "SP" and t:get(3) == nil,
          "take reordena e preserva NULL")

    -- take fora dos limites recusa
    check(rejects(function() return s:take({99}) end), "take fora-limites recusa")

    -- DataSet: filtrar linhas por coluna de texto, aplicar noutra coluna
    local df = smaug.DataSet.from_columns({
        {"uf",  {"SP", "RJ", "SP"}, "string"},
        {"pop", {44, 17, 11},       "int64"},
    })
    local pop_sp = df:col("pop"):filter(df:col("uf"):eq("SP"))
    check(pop_sp:len() == 2 and pop_sp:get(1) == 44 and pop_sp:get(2) == 11,
          "filtrar dataset por coluna de texto")
end

-- ===================================================================
-- Ordenação: sort e argsort (lexicográfico; recusa NULL)
-- ===================================================================
do
    local s = S.from_table({"MG", "AC", "SP", "BA", "AC"}, "string")

    local asc = s:sort()
    check(asc:get(1) == "AC" and asc:get(2) == "AC" and asc:get(3) == "BA"
          and asc:get(4) == "MG" and asc:get(5) == "SP", "sort ascendente")

    local desc = s:sort(false)
    check(desc:get(1) == "SP" and desc:get(5) == "AC", "sort descendente")

    -- argsort 1-based, permutação estável
    local ix = s:argsort()
    check(ix[1] == 2 and ix[2] == 5 and ix[5] == 3, "argsort 1-based estavel")

    -- vazia ordena primeiro
    local v = S.from_table({"b", "", "a"}, "string"):sort()
    check(v:get(1) == "" and v:get(2) == "a" and v:get(3) == "b",
          "sort: vazia vem primeiro")

    -- NULL recusa (sort levanta erro; argsort retorna nil)
    local sn = S.from_table({"x", smaug.NA, "a"}, "string")
    check(rejects(function() return sn:sort() end), "sort recusa NULL")
    check(sn:argsort() == nil, "argsort com NULL -> nil")

    -- sort + take coerentes: ordenar e reordenar dá o mesmo
    local sorted = s:sort()
    check(sorted:len() == 5, "sort preserva tamanho")
end

-- =====================================================================
-- fillna / describe / astype para string
-- =====================================================================
local function test_string_ux()
    -- fillna: preenche NULL com string; mantém não-nulos intactos
    local s = S.from_table({"SP", smaug.NA, "RJ", smaug.NA}, "string", "uf")
    local f = s:fillna("?")
    check(f:get(1) == "SP", "fillna string: não-nulo preservado")
    check(f:get(2) == "?",  "fillna string: null preenchido")
    check(f:get(3) == "RJ", "fillna string: não-nulo preservado 2")
    check(f:get(4) == "?",  "fillna string: null preenchido 2")
    check(s:is_null(2),     "fillna string: original imutável")

    -- fillna com tipo errado dá erro descritivo
    check(rejects(function() s:fillna(0)   end), "fillna str+num -> erro")
    check(rejects(function() s:fillna(nil) end), "fillna nil -> erro")

    -- describe: retorna count/nulls/unique/top/freq
    local d = s:describe()
    check(d.count  == 2,    "describe str: count não-nulos")
    check(d.nulls  == 2,    "describe str: nulls")
    check(d.unique == 2,    "describe str: unique")
    check(d.top ~= nil,     "describe str: top existe")
    check(d.freq   >= 1,    "describe str: freq >= 1")

    -- describe: série com valor mais frequente
    local s2 = S.from_table({"a","b","a","a","b"}, "string")
    local d2 = s2:describe()
    check(d2.top == "a" and d2.freq == 3, "describe str: top/freq corretos")
    check(d2.unique == 2,                 "describe str: unique 2 valores")

    -- describe: série toda NULL
    local sn = S.from_table({smaug.NA, smaug.NA}, "string")
    local dn = sn:describe()
    check(dn.count == 0 and dn.nulls == 2, "describe str: toda-null")
    check(dn.top == nil and dn.freq == nil, "describe str: top nil em toda-null")

    -- astype string → float64: parse numérico
    local nums = S.from_table({"1.5", "2.0", "abc", smaug.NA}, "string")
    local f64  = nums:astype("float64")
    check(f64._dtype == "float64",       "astype str->f64: dtype")
    check(f64:get(1) == 1.5,             "astype str->f64: valor")
    check(f64:get(2) == 2.0,             "astype str->f64: valor 2")
    check(f64:is_null(3),                "astype str->f64: parse inválido -> null")
    check(f64:is_null(4),                "astype str->f64: null preservado")

    -- astype string → int64
    local ints = S.from_table({"3", "7", "x"}, "string"):astype("int64")
    check(ints:get(1) == 3,  "astype str->i64: valor")
    check(ints:get(2) == 7,  "astype str->i64: valor 2")
    check(ints:is_null(3),   "astype str->i64: parse inválido -> null")

    -- astype float64 → string
    local strs = S.from_table({1.5, 0.0/0.0, smaug.NA}, "float64"):astype("string")
    check(strs._dtype == "string",       "astype f64->str: dtype")
    check(strs:get(1) == "1.5",          "astype f64->str: valor")
    check(strs:get(2) ~= nil,            "astype f64->str: NaN vira string (nao null)")
    check(strs:is_null(3),               "astype f64->str: null preservado")

    -- astype int64 → string
    local si = S.from_table({10, 20, smaug.NA}, "int64"):astype("string")
    check(si:get(1) == "10" and si:get(2) == "20", "astype i64->str: valores")
    check(si:is_null(3),                            "astype i64->str: null preservado")
end

test_string_ux()

-- =====================================================================
-- .str Tier A: len, lower, upper, strip, contains, startswith, endswith
-- =====================================================================
local function test_str_accessor()
    local s = S.from_table({"  Sao Paulo  ", "rio", smaug.NA, "MINAS"}, "string")

    -- len: comprimento em bytes; null -> null
    local l = s.str:len()
    check(l._dtype == "int64",  "str:len dtype int64")
    check(l:get(1) == 13,       "str:len espaços inclusos")
    check(l:get(2) == 3,        "str:len valor simples")
    check(l:is_null(3),         "str:len null -> null")
    check(l:get(4) == 5,        "str:len uppercase")

    -- lower: ASCII; null -> null
    local lo = s.str:lower()
    check(lo._dtype == "string",          "str:lower dtype string")
    check(lo:get(2) == "rio",             "str:lower já minúsculo")
    check(lo:get(4) == "minas",           "str:lower uppercase -> lower")
    check(lo:is_null(3),                  "str:lower null -> null")

    -- upper: ASCII; null -> null
    local up = s.str:upper()
    check(up:get(2) == "RIO",             "str:upper lower -> upper")
    check(up:get(4) == "MINAS",           "str:upper já maiúsculo")
    check(up:is_null(3),                  "str:upper null -> null")

    -- strip: remove espaços nas bordas; null -> null
    local st = s.str:strip()
    check(st:get(1) == "Sao Paulo",       "str:strip remove bordas")
    check(st:get(2) == "rio",             "str:strip sem espaço: inalterado")
    check(st:is_null(3),                  "str:strip null -> null")

    -- strip: string de só espaços vira ""
    local sp = S.from_table({"   "}, "string")
    check(sp.str:strip():get(1) == "",    "str:strip só espaços -> ''")

    -- contains: busca de substring; null -> NA
    local c = s.str:contains("ao")
    check(c:get(1) == true,               "str:contains match")
    check(c:get(2) == false,              "str:contains no-match")
    check(c:is_null(3),                   "str:contains null -> NA")

    -- contains: string vazia sempre true
    check(s.str:contains(""):get(2) == true, "str:contains '' sempre true")

    -- startswith; null -> NA
    local sw = s.str:startswith("  S")
    check(sw:get(1) == true,              "str:startswith match")
    check(sw:get(2) == false,             "str:startswith no-match")
    check(sw:is_null(3),                  "str:startswith null -> NA")

    -- startswith: prefixo vazio sempre true
    check(s.str:startswith(""):get(2) == true, "str:startswith '' sempre true")

    -- endswith; null -> NA
    local ew = s.str:endswith("AS")
    check(ew:get(4) == true,              "str:endswith match")
    check(ew:get(2) == false,             "str:endswith no-match")
    check(ew:is_null(3),                  "str:endswith null -> NA")

    -- endswith: sufixo vazio sempre true
    check(s.str:endswith(""):get(2) == true, "str:endswith '' sempre true")

    -- dtype errado dá erro descritivo
    local n = S.from_table({1.0, 2.0}, "float64")
    check(rejects(function() return n.str:lower() end), "str em float64 -> erro")
    local i = S.from_table({1, 2}, "int64")
    check(rejects(function() return i.str:len() end),   "str em int64 -> erro")

    -- argumento de tipo errado
    check(rejects(function() s.str:contains(42)     end), "contains(num) -> erro")
    check(rejects(function() s.str:startswith(false) end), "startswith(bool) -> erro")
    check(rejects(function() s.str:endswith(nil)     end), "endswith(nil) -> erro")

    -- integração: filter com .str:contains
    -- "tos" só ocorre em "Santos"; NA na máscara conta como false (descartado)
    local cidades = S.from_table({"São Paulo", "Rio de Janeiro", "Santos", smaug.NA}, "string")
    local mask = cidades.str:contains("tos")
    check(mask:get(1) == false,           "str:contains integração: SP false")
    check(mask:get(3) == true,            "str:contains integração: Santos true")
    check(mask:is_null(4),                "str:contains integração: null -> NA")
    local filtrado = cidades:filter(mask)
    check(filtrado:len() == 1,            "filter com str:contains: 1 resultado")
    check(filtrado:get(1) == "Santos",    "filter com str:contains: valor correto")
end

test_str_accessor()

-- =====================================================================
-- .str:replace — substituição literal de substring
-- =====================================================================
local function test_str_replace()
    local s = S.from_table({"foo bar foo", "hello", smaug.NA, "foo"}, "string")

    -- substituição básica
    local r = s.str:replace("foo", "baz")
    check(r:get(1) == "baz bar baz",  "str:replace: todas as ocorrências")
    check(r:get(2) == "hello",        "str:replace: sem match: inalterado")
    check(r:is_null(3),               "str:replace: null -> null")
    check(r:get(4) == "baz",          "str:replace: ocorrência única")

    -- substituição por string vazia (remoção)
    local r2 = s.str:replace("foo", "")
    check(r2:get(1) == " bar ",       "str:replace: remove todas ocorrências")
    check(r2:get(4) == "",            "str:replace: string vira vazia")

    -- old vazio: no-op (semântica indefinida -> cópia sem alterar)
    check(s.str:replace("", "x"):get(1) == "foo bar foo", "str:replace: old vazio -> no-op")

    -- metacaracteres Lua no old e new são tratados literalmente
    local s2 = S.from_table({"a.b.c", "x+y", "2^3"}, "string")
    check(s2.str:replace(".", "-"):get(1)    == "a-b-c",  "str:replace: '.' literal")
    check(s2.str:replace("+", "plus"):get(2) == "xplusy", "str:replace: '+' literal")
    check(s2.str:replace("^", ""):get(3)     == "23",     "str:replace: '^' literal")

    -- argumentos de tipo errado
    check(rejects(function() s.str:replace(1, "x")   end), "str:replace: old não-string -> erro")
    check(rejects(function() s.str:replace("x", nil) end), "str:replace: new nil -> erro")
end

test_str_replace()


-- =====================================================================
-- .str Tier B (de test_str_tier_b.lua)
-- =====================================================================

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


-- =====================================================================
-- .str Tier C (de test_str_tier_c.lua)
-- =====================================================================


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

-- view não suportado em string → erro orientado (I.3; antes era nil-call cru)
local sv = S.from_table({"SP", "RJ", "MG"}, "string")
local ok_v, err_v = pcall(function() return sv:view(1, 2) end)
check(not ok_v,                            "string view: erro (não nil-call)")
check(type(err_v) == "string" and err_v:find("não é suportado", 1, true) ~= nil,
                                           "string view: mensagem orienta (não suportado)")
check(sv:take({1, 2}):len() == 2,          "string take: alternativa a view funciona")

-- ================================================================
-- Resultado
-- ================================================================


print(string.format("OK — %d checks passaram (Series: .str Tier A+B+C completo)", n_ok))
