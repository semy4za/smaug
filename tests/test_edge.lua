-- tests/test_edge.lua
-- Casos degenerados (Fase 1.6 — endurecimento).
-- Trava o comportamento em entradas-limite: série vazia, 1 elemento, toda-nula,
-- toda-igual. Cobre reduções, sort, view, take, filter, comparações.
-- Rode da raiz:  luajit tests/test_edge.lua
--
-- NOTA: marcações "PENDENTE (1.6)" indicam asserções a adicionar quando a
-- funcionalidade correspondente for implementada nesta fase. Não remover sem
-- implementar.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local S      = smaug.Series

local function approx(a, b) return math.abs(a - b) < 1e-9 end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
-- Verifica que uma chamada lança erro (para casos que devem ser recusados).
local function check_err(fn, msg)
    local ok = pcall(fn)
    check(not ok, msg .. " (deveria lançar erro)")
end

-- ===================================================================
-- SÉRIE VAZIA (size 0)
-- ===================================================================
do
    local e = S.float64(0)
    check(e:len() == 0, "vazia: len 0")
    check(e:count_nonnull() == 0, "vazia: count_nonnull 0")
    -- sum de vazia = 0 (default min_count=0; alinhado com pandas)
    check(e:sum() == 0, "vazia: sum 0")
    -- PENDENTE (1.6): quando min_count existir, e:sum(nil, {min_count=1}) == nil
    -- mean/min/max/std de vazia = nil (sem valor neutro)
    check(e:mean() == nil, "vazia: mean nil")
    check(e:min() == nil, "vazia: min nil")
    check(e:max() == nil, "vazia: max nil")
    check(e:std() == nil, "vazia: std nil")
    check(e:var() == nil, "vazia: var nil")
    -- transformações em vazia devolvem vazia, sem quebrar
    check(e:clone():len() == 0, "vazia: clone vazia")
    check(e:sort():len() == 0, "vazia: sort vazia")
    check(e:head(3):len() == 0, "vazia: head vazia")
    check(e:tail(3):len() == 0, "vazia: tail vazia")
    check(e:take({}):len() == 0, "vazia: take vazio")
    -- comparação de vazia → BoolSeries vazia
    check(e:gt(0):len() == 0, "vazia: gt len 0")
    check(e:gt(0):count_true() == 0, "vazia: gt count_true 0")
    check(e:gt(0):any() == false, "vazia: any false")
    check(e:gt(0):all() == true, "vazia: all true (vacuamente)")
    -- to_table de vazia → tabela vazia
    check(#e:to_table() == 0, "vazia: to_table vazio")
end

-- ===================================================================
-- SÉRIE DE 1 ELEMENTO
-- ===================================================================
do
    local one = S.from_table({42}, "float64")
    check(one:len() == 1, "1-elem: len 1")
    check(one:sum() == 42, "1-elem: sum 42")
    check(one:mean() == 42, "1-elem: mean 42")
    check(one:min() == 42 and one:max() == 42, "1-elem: min==max==42")
    -- variância/desvio populacional de 1 elemento = 0
    check(one:std() == 0, "1-elem: std 0 (populacional)")
    check(one:var() == 0, "1-elem: var 0")
    check(one:sort():get(1) == 42, "1-elem: sort")
    check(one:clone():get(1) == 42, "1-elem: clone")
    check(one:head(5):len() == 1, "1-elem: head(5) limita a 1")
    -- view de 1 elemento
    local v = one:view(1, 1)
    check(v:len() == 1 and v:get(1) == 42, "1-elem: view")
end

-- ===================================================================
-- SÉRIE TODA-NULA
-- ===================================================================
do
    local n = S.from_table({smaug.NA, smaug.NA, smaug.NA}, "float64")
    check(n:len() == 3, "toda-nula: len 3")
    check(n:count_nonnull() == 0, "toda-nula: count_nonnull 0")
    -- sum toda-nula = 0 (default). PENDENTE (1.6): sum(min_count=1) == nil
    check(n:sum() == 0, "toda-nula: sum 0 (default)")
    check(n:mean() == nil, "toda-nula: mean nil")
    check(n:min() == nil, "toda-nula: min nil")
    check(n:max() == nil, "toda-nula: max nil")
    -- sort recusa série com nulos
    check_err(function() return n:sort() end, "toda-nula: sort recusa nulos")
    -- comparação: nulo não é > 0 → 0 trues, mas a máscara mantém os NA
    check(n:gt(0):count_true() == 0, "toda-nula: gt count_true 0")
    check(n:gt(0):is_null(1) == true, "toda-nula: gt preserva NA na máscara")
    -- todas as posições são null
    check(n:is_null(1) and n:is_null(3), "toda-nula: is_null em todas")
end

-- ===================================================================
-- SÉRIE TODA-IGUAL
-- ===================================================================
do
    local eq = S.from_table({5, 5, 5, 5}, "float64")
    check(eq:sum() == 20, "toda-igual: sum 20")
    check(eq:mean() == 5, "toda-igual: mean 5")
    check(eq:min() == 5 and eq:max() == 5, "toda-igual: min==max==5")
    -- variância/desvio de valores idênticos = 0
    check(eq:std() == 0, "toda-igual: std 0")
    check(eq:var() == 0, "toda-igual: var 0")
    -- sort de toda-igual = ela mesma
    local s = eq:sort()
    check(s:get(1) == 5 and s:get(4) == 5, "toda-igual: sort estável")
    -- gt(5) → nenhum; gt(4) → todos
    check(eq:gt(5):count_true() == 0, "toda-igual: gt(5) nenhum")
    check(eq:gt(4):count_true() == 4, "toda-igual: gt(4) todos")
    check(eq:eq(5):all() == true, "toda-igual: eq(5) all true")
end

-- ===================================================================
-- i64: paridade nos casos degenerados + sentinela
-- ===================================================================
do
    local e = S.int64(0)
    check(e:sum() == 0, "i64 vazia: sum 0")
    check(e:mean() == nil, "i64 vazia: mean nil")

    local n = S.from_table({smaug.NA, smaug.NA}, "int64")
    check(n:sum() == 0, "i64 toda-nula: sum 0 (ignore_na)")
    -- sentinela INT64_MIN deve virar nil quando ignore_na=false
    check(n:sum(false) == nil, "i64 toda-nula: sum(false) nil (sentinela→nil)")
    check(n:max() == nil, "i64 toda-nula: max nil")

    local one = S.from_table({7}, "int64")
    check(one:sum() == 7 and one:std() == 0, "i64 1-elem: sum/std")
end

-- ===================================================================
-- PENDENTE (1.6) — adicionar quando implementado:
--   * sum(min_count=1) em série vazia/toda-nula → nil (contrato decidido)
--   * NaN do usuário: sort/argsort devem RECUSAR (hoje só recusam null);
--     comparação com NaN → false. Ver test_special.lua (a criar).
--   * fillna: preencher nulos em vazia/toda-nula.
-- ===================================================================

-- ===================================================================
-- PROPAGAÇÃO DE NULL EM COMPARAÇÃO (série mista)
-- Comparar um nulo produz NA na máscara — nunca false.
-- ===================================================================
do
    local s = S.from_table({10, smaug.NA, 30}, "float64")
    local b = s:gt(15)              -- F, NA, T
    check(b:get(1) == false, "cmp-misto: 10>15 false")
    check(b:get(2) == nil,   "cmp-misto: NA>15 → NA (não false)")
    check(b:is_null(2) == true, "cmp-misto: posição NA marcada na máscara")
    check(b:get(3) == true,  "cmp-misto: 30>15 true")
    check(b:count_true() == 1, "cmp-misto: count_true 1 (NA não conta)")
    -- filter descarta a linha NA da máscara
    check(s:filter(b):len() == 1, "cmp-misto: filter descarta NA e false")
end

print(string.format("OK — %d checks passaram (casos degenerados)", n_ok))
