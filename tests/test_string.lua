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
    check(rejects(function() return s:sort() end), "sort recusa string (ainda)")
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

print(string.format("OK — %d checks passaram (string frontend)", n_ok))
