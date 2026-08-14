-- tests/series/test_reduce.lua
-- Reduções core (sum/mean/min/max/var/std) e valores especiais f64 (NaN/Inf).
-- Consolida: test_special.lua + partes de test_series_ops.lua
-- Rode da raiz: luajit tests/series/test_reduce.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local Series = smaug.Series
local NA     = Series.NA

local function approx(a, b) return math.abs(a - b) < 1e-9 end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

--   * +Inf/-Inf são ordenáveis (não recusados)
-- Rode da raiz:  luajit tests/test_special.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local S     = smaug.Series

local inf, ninf, nan = math.huge, -math.huge, 0/0
local function is_nan(x) return x ~= x end

local function check_err(fn, msg)
    local ok = pcall(fn)
    check(not ok, msg .. " (deveria lançar erro)")
end

-- ===================================================================
-- +Inf / -Inf — ordenáveis, válidos em reduções
-- ===================================================================
do
    local s = S.from_array({3.0, inf, 1.0, ninf, 2.0}, "float64")
    check(s:min() == ninf, "Inf: min == -Inf")
    check(s:max() == inf,  "Inf: max == +Inf")
    -- +Inf + -Inf = NaN → soma indefinida vira nil
    check(s:sum() == nil, "Inf: sum(+Inf,-Inf) indefinido → nil")
    -- sort ordena Inf normalmente (-Inf no começo, +Inf no fim)
    local sorted = s:sort()
    check(sorted:get(1) == ninf, "Inf: sort põe -Inf no início")
    check(sorted:get(5) == inf,  "Inf: sort põe +Inf no fim")

    local p = S.from_array({1.0, inf, 2.0}, "float64")
    check(p:sum() == inf, "Inf: 1+Inf+2 = Inf")
    check(p:mean() == inf, "Inf: mean = Inf")
    check(p:max() == inf, "Inf: max")
    check(p:gt(0):count_true() == 3, "Inf: Inf>0 = true")
    -- sort com Inf (sem NaN) é permitido
    check(p:sort():len() == 3, "Inf: sort permitido (sem NaN)")
end

-- ===================================================================
-- NaN é distinto de null — set(i, NaN) grava NaN, NÃO null
-- ===================================================================
do
    local q = S.float64(3)
    q:set(1, 1.0)
    q:set(2, nan)        -- NaN explícito do usuário
    q:set(3, 3.0)
    -- a posição NÃO é null (NaN é um valor presente)
    check(q:is_null(2) == false, "NaN: set(NaN) não vira null")
    -- get devolve um NaN de verdade (não nil)
    check(is_nan(q:get(2)), "NaN: get devolve NaN real")
    -- conta como não-nulo (há um valor ali)
    check(q:count_nonnull() == 3, "NaN: count_nonnull conta o NaN")
end

-- ===================================================================
-- nil continua sendo null (distinto de NaN)
-- ===================================================================
do
    local r = S.float64(2)
    r:set(1, nil)        -- nil → null
    r:set(2, 5.0)
    check(r:is_null(1) == true, "nil: set(nil) vira null")
    check(r:get(1) == nil, "nil: get de null devolve nil")
    -- numa mesma série dá pra ter null E NaN distintos
    local mix = S.float64(3)
    mix:set(1, nil)      -- null
    mix:set(2, nan)      -- NaN
    mix:set(3, 7.0)      -- valor normal
    check(mix:is_null(1) == true,  "mix: [1] é null")
    check(mix:is_null(2) == false, "mix: [2] é NaN (não null)")
    check(is_nan(mix:get(2)),      "mix: [2] get NaN")
    check(mix:count_nonnull() == 2, "mix: count_nonnull = 2 (null não conta, NaN+valor sim)")
end

-- ===================================================================
-- NaN é contagioso; ignore_na NÃO pula NaN (só pula null)
-- ===================================================================
do
    local s = S.float64(3)
    s:set(1, 1.0); s:set(2, nan); s:set(3, 3.0)
    -- soma com NaN real → NaN → nil (contágio), mesmo com ignore_na default
    check(s:sum() == nil, "NaN: sum com NaN real → nil (contágio; ignore_na pula null, não NaN)")
    check(s:mean() == nil, "NaN: mean com NaN real → nil")
end

-- ===================================================================
-- div/0 → null (decisão explícita: div/0 não passa, é previsível)
-- 0/0, n/0 e -n/0 todos produzem null; NaN via op foi removido.
-- NaN ainda existe como valor literal (S.from_array({0/0})).
-- ===================================================================
do
    local a = S.from_array({0.0, 1.0, -1.0}, "float64")
    local b = S.from_array({0.0, 0.0,  0.0}, "float64")
    local c = a / b
    check(c:is_null(1), "op: 0/0  → null")
    check(c:is_null(2), "op: 1/0  → null")
    check(c:is_null(3), "op: -1/0 → null")
    -- escalar 0
    local d = a / 0
    check(d:is_null(1), "op: f64 / escalar 0 → null")
    check(d:is_null(2), "op: f64 / escalar 0 → null (2)")
end

-- ===================================================================
-- sort/argsort RECUSAM séries com NaN (além de null)
-- ===================================================================
do
    local s = S.float64(3)
    s:set(1, 3.0); s:set(2, nan); s:set(3, 1.0)
    check_err(function() return s:sort() end, "NaN: sort recusa NaN")
    check(s:argsort() == nil, "NaN: argsort retorna nil com NaN")
    -- null vindo de div/0 também é recusado pelo sort
    local a = S.from_array({0.0, 1.0}, "float64")
    local b = S.from_array({0.0, 2.0}, "float64")
    local c = a / b            -- [1] = null (0/0 → null), [2] = 0.5
    check_err(function() return c:sort() end, "div/0: sort recusa null resultante")
end

-- ===================================================================
-- comparações com NaN → false (IEEE), com máscara VÁLIDA (não NA)
-- distinção importante: NaN comparado dá false-válido; null dá NA.
-- ===================================================================
do
    local s = S.float64(3)
    s:set(1, 5.0); s:set(2, nan); s:set(3, 10.0)
    local b = s:gt(0)
    check(b:get(1) == true,  "cmp-NaN: 5>0 true")
    -- NaN > 0 é false pelo IEEE; e como NaN é valor (não null), a máscara é válida
    check(b:get(2) == false, "cmp-NaN: NaN>0 → false (não NA)")
    check(b:is_null(2) == false, "cmp-NaN: resultado de NaN é válido (não NA)")
    check(b:get(3) == true,  "cmp-NaN: 10>0 true")
    check(b:count_true() == 2, "cmp-NaN: count_true 2")
end

-- ===================================================================
-- -0.0 — igual a 0.0 nas comparações, neutro na soma
-- ===================================================================
do
    local z = S.from_array({-0.0, 0.0}, "float64")
    check(z:eq(0.0):count_true() == 2, "-0.0: -0 e +0 ambos == 0")
    check(z:sum() == 0, "-0.0: soma neutra")
    check(z:min() == z:max(), "-0.0: min == max (mesmo valor)")
end


-- 5.5 — min_count opt-in em sum/prod (Series)
do
    local c = Series.from_array({10, NA, NA}, "int64")
    check(c:sum() == 10, "5.5 Series sum default ignora NA = 10")
    check(c:sum(nil, 2) == nil, "5.5 Series sum(min_count=2): 1 não-nulo → NA")
    check(c:sum(nil, 1) == 10, "5.5 Series sum(min_count=1): 1 não-nulo → 10")
    local an = Series.from_array({NA, NA}, "int64")
    check(an:sum() == 0, "5.5 Series sum all-null default = 0 (preservado)")
    check(an:sum(nil, 1) == nil, "5.5 Series sum all-null min_count=1 → NA")
    check(c:prod(nil, 2) == nil, "5.5 Series prod(min_count=2) → NA")

    -- ===============================================================
    -- min/max em dtypes ordenáveis não-numéricos (item 7.2b): retornam
    -- VALOR (D7.2-a ii). Fecha a incoerência argmin✓/min✗ que havia em dt.
    -- ===============================================================
    local d = Series.from_array({"2020-03-01", "2020-01-01", "2020-06-15"}, "datetime")
    check(d:min() == d:get(d:argmin()), "7.2b dt:min == get(argmin)")
    check(d:max() == d:get(d:argmax()), "7.2b dt:max == get(argmax)")
    check(type(d:min()) == "number",     "7.2b dt:min retorna número (epoch)")

    local sm = Series.from_array({"banana", "abacaxi", "caju"}, "string")
    check(sm:min() == "abacaxi", "7.2b str:min = abacaxi")
    check(sm:max() == "caju",    "7.2b str:max = caju")
    local sv = Series.from_array({"z", "", "m"}, "string")
    check(sv:min() == "",       "7.2b str:min com vazia = '' (válida)")

    local bm = Series.from_array({true, false, true}, "bool")
    check(bm:min() == false, "7.2b bool:min = false")
    check(bm:max() == true,  "7.2b bool:max = true")

    check(Series.from_array({NA, NA}, "string"):min()   == nil, "7.2b str all-NA min = nil")
    check(Series.from_array({NA, NA}, "bool"):min()     == nil, "7.2b bool all-NA min = nil")
    check(Series.from_array({NA, NA}, "datetime"):min() == nil, "7.2b dt all-NA min = nil")

    local smn = Series.from_array({"a", NA, "c"}, "string")
    check(smn:min()      == "a",  "7.2b str:min default ignora NA")
    check(smn:min(false) == nil,  "7.2b str:min(false) com NA = nil")
    local bmn = Series.from_array({true, NA}, "bool")
    check(bmn:min(false) == nil,  "7.2b bool:min(false) com NA = nil")
end


print(string.format("OK — %d checks passaram (Series: reduções, valores especiais f64)", n_ok))
