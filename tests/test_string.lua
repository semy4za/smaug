-- tests/test_string.lua
-- Suíte do tipo string no frontend Lua (núcleo: lifecycle, acesso, mutação,
-- recusa de operações numéricas, integração com DataSet).
-- O backend C tem seu próprio teste exaustivo (tests/test_string.c, Valgrind).
-- Aqui o foco é a camada Lua: conversão FFI (ponteiro+len <-> string Lua),
-- despacho por dtype, e mensagens de erro.
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
-- Comparações (eq/lt/gt) -> BoolSeries
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

print(string.format("OK — %d checks passaram (string frontend)", n_ok))
