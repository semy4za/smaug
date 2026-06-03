-- tests/test_i64.lua
-- Suíte dedicada ao int64 (Fase 1.6 — endurecimento de cobertura).
--
-- Motivo: a cobertura media de `smaug_ops_i64.c` estava ~56% porque os demais
-- testes exercitam majoritariamente float64. Este arquivo espelha, para int64,
-- o que já se testa em f64 — aritmética, escalares, reduções, comparações,
-- ordenação, seleção e lifecycle — assertando os valores corretos (não apenas
-- executando o código: cada caso verifica o resultado).
--
-- Contrato i64 relevante (ver Roadmap): divisão é inteira e /0 → NULL;
-- sum/min/max usam INT64_MIN como sentinela (Lua recebe nil); var/std são
-- populacionais.
--
-- Rode da raiz:  luajit tests/test_i64.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local S     = smaug.Series

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
local function approx(a, b) return math.abs(a - b) < 1e-9 end

-- ===================================================================
-- Aritmética elemento-a-elemento
-- ===================================================================
do
    local a = S.from_table({10, 20, 30}, "int64")
    local b = S.from_table({3, 4, 5}, "int64")
    check((a + b):get(1) == 13, "i64 add")
    check((a - b):get(1) == 7,  "i64 sub")
    check((a * b):get(1) == 30, "i64 mul")
    -- divisão inteira: 10/3 = 3 (trunca)
    check((a / b):get(1) == 3, "i64 div inteira trunca")
    check((a + b):len() == 3, "i64 add preserva tamanho")
end

-- ===================================================================
-- Divisão por zero → NULL; propagação de NA na aritmética
-- ===================================================================
do
    local num = S.from_table({10, 20, 30}, "int64")
    local den = S.from_table({2, 0, 3}, "int64")
    local q = num / den
    check(q:get(1) == 5, "i64 div ok")
    check(q:is_null(2), "i64 div por zero → null")
    check(q:get(3) == 10, "i64 div terceiro ok")

    -- NA em um operando propaga para o resultado
    local x = S.from_table({1, smaug.NA, 3}, "int64")
    local y = S.from_table({1, 2, 3}, "int64")
    local r = x + y
    check(r:get(1) == 2, "i64 add [1] ok")
    check(r:is_null(2), "i64 add propaga NA")
    check(r:get(3) == 6, "i64 add [3] ok")
end

-- ===================================================================
-- Operações com escalar
-- ===================================================================
do
    local a = S.from_table({10, 20, 30}, "int64")
    check((a + 100):get(1) == 110, "i64 add_scalar")
    check((a - 5):get(2) == 15, "i64 sub_scalar")
    check((a * 2):get(3) == 60, "i64 mul_scalar")
    check((a / 10):get(2) == 2, "i64 div_scalar inteira")
    -- divisão escalar por zero → null em todas as posições
    local z = a / 0
    check(z:is_null(1) and z:is_null(2) and z:is_null(3), "i64 div_scalar por zero → null")
end

-- ===================================================================
-- Reduções (min, max, mean, var, std populacionais)
-- ===================================================================
do
    local a = S.from_table({10, 20, 30}, "int64")
    check(a:sum() == 60, "i64 sum")
    check(a:min() == 10, "i64 min")
    check(a:max() == 30, "i64 max")
    check(approx(a:mean(), 20.0), "i64 mean")
    -- var populacional: ((10-20)²+(20-20)²+(30-20)²)/3 = 200/3 ≈ 66.6667
    check(approx(a:var(), 200.0/3.0), "i64 var populacional")
    check(approx(a:std(), math.sqrt(200.0/3.0)), "i64 std populacional")

    -- reduções ignoram NA por padrão
    local k = S.from_table({10, smaug.NA, 30}, "int64")
    check(k:sum() == 40, "i64 sum ignora NA")
    check(k:min() == 10, "i64 min ignora NA")
    check(k:max() == 30, "i64 max ignora NA")
    -- com ignore_na=false e havendo NA → sentinela → nil
    check(k:sum(false) == nil, "i64 sum(false) com NA → nil")
end

-- ===================================================================
-- Reduções em casos degenerados
-- ===================================================================
do
    local one = S.from_table({42}, "int64")
    check(one:sum() == 42 and one:min() == 42 and one:max() == 42, "i64 reduções 1-elemento")
    check(approx(one:var(), 0.0), "i64 var de 1 elemento = 0")

    local allnull = S.from_table({smaug.NA, smaug.NA}, "int64")
    check(allnull:sum() == 0, "i64 sum toda-nula = 0")
    check(allnull:min() == nil, "i64 min toda-nula = nil")
    check(allnull:max() == nil, "i64 max toda-nula = nil")
    check(allnull:mean() == nil, "i64 mean toda-nula = nil")
end

-- ===================================================================
-- Comparações (gt, lt, eq) → BoolSeries
-- ===================================================================
do
    local a = S.from_table({10, 20, 30}, "int64")
    check(a:gt(15):count_true() == 2, "i64 gt")
    check(a:lt(25):count_true() == 2, "i64 lt")
    check(a:eq(20):count_true() == 1, "i64 eq")
    -- comparação com NA → NA (não conta como true)
    local k = S.from_table({10, smaug.NA, 30}, "int64")
    local m = k:gt(15)
    check(m:get(1) == false, "i64 gt: 10>15 false")
    check(m:is_null(2), "i64 gt: NA propaga")
    check(m:get(3) == true, "i64 gt: 30>15 true")
    check(m:count_true() == 1, "i64 gt count_true ignora NA")
end

-- ===================================================================
-- Ordenação (sort asc/desc, argsort) e recusa de NULL
-- ===================================================================
do
    local a = S.from_table({30, 10, 20}, "int64")
    local asc = a:sort()
    check(asc:get(1) == 10 and asc:get(2) == 20 and asc:get(3) == 30, "i64 sort asc")
    local desc = a:sort(false)
    check(desc:get(1) == 30 and desc:get(3) == 10, "i64 sort desc")
    -- argsort devolve permutação 1-based
    local idx = a:argsort()
    check(idx[1] == 2 and idx[2] == 3 and idx[3] == 1, "i64 argsort (índices do menor→maior)")

    -- sort recusa série com NULL
    local k = S.from_table({3, smaug.NA, 1}, "int64")
    check(pcall(function() return k:sort() end) == false, "i64 sort recusa NULL")
    check(k:argsort() == nil, "i64 argsort com NULL → nil")
end

-- ===================================================================
-- Seleção (take, filter)
-- ===================================================================
do
    local a = S.from_table({10, 20, 30, 40}, "int64")
    local t = a:take({4, 1, 3})
    check(t:len() == 3, "i64 take comprimento")
    check(t:get(1) == 40 and t:get(2) == 10 and t:get(3) == 30, "i64 take reordena")

    local f = a:filter(a:gt(15))
    check(f:len() == 3, "i64 filter len = count_true")
    check(f:get(1) == 20, "i64 filter primeiro elemento")
end

-- ===================================================================
-- Lifecycle: clone (independente), view (compartilha), append (grow)
-- ===================================================================
do
    local a = S.from_table({1, 2, 3}, "int64")
    -- clone independente
    local c = a:clone()
    c:set(1, 999)
    check(a:get(1) == 1, "i64 clone independente (original intacto)")
    check(c:get(1) == 999, "i64 clone mutável")

    -- view compartilha
    local v = a:view(2, 2)   -- [2,3]
    check(v:len() == 2 and v:get(1) == 2 and v:get(2) == 3, "i64 view janela")

    -- append faz crescer
    local g = S.int64(0)
    for i = 1, 50 do g:append(i) end
    check(g:len() == 50, "i64 append grow comprimento")
    check(g:get(1) == 1 and g:get(50) == 50, "i64 append valores")
    g:append(nil)   -- append null
    check(g:is_null(51), "i64 append_null")
    check(g:count_nonnull() == 50, "i64 count_nonnull após append_null")
end

-- ===================================================================
-- astype i64 ↔ f64 (paridade de conversão)
-- ===================================================================
do
    local i = S.from_table({5, 6, 7}, "int64")
    local f = i:astype("float64")
    check(f:get(1) == 5.0, "i64→f64 astype")
    local back = f:astype("int64")
    check(back:get(1) == 5, "f64→i64 astype ida-volta")
    check(back._dtype == "int64", "i64 astype preserva dtype final")
end

print(string.format("OK — %d checks passaram (int64 dedicado)", n_ok))
