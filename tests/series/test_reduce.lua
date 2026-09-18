-- tests/series/test_reduce.lua
-- Reduções core (sum/mean/min/max/var/std) e valores especiais f64 (NaN/Inf).
-- Consolida: test_special.lua + partes de test_series_ops.lua
-- Rode da raiz: luajit tests/series/test_reduce.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local positive_infinity, negative_infinity, not_a_number = math.huge, -math.huge, 0/0

local function approximately_equal(left_value, right_value) return math.abs(left_value - right_value) < 1e-9 end
local function is_nan(value) return value ~= value end

local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local function check_error(operation, message)
    local succeeded = pcall(operation)
    check(not succeeded, message .. " (deveria lançar erro)")
end

-- =====================================================================
-- 1. +Inf / -Inf — ordenáveis, válidos em reduções
-- =====================================================================
do
    local infinity_series = smaug.Series({3.0, positive_infinity, 1.0, negative_infinity, 2.0}, "float64")
    check(infinity_series:min() == negative_infinity, "Inf: min == -Inf")
    check(infinity_series:max() == positive_infinity,  "Inf: max == +Inf")
    -- +Inf + -Inf = NaN → soma indefinida vira nil
    check(infinity_series:sum() == nil, "Inf: sum(+Inf,-Inf) indefinido → nil")
    -- sort ordena Inf normalmente (-Inf no começo, +Inf no fim)
    local sorted_series = infinity_series:sort()
    check(sorted_series:get(1) == negative_infinity, "Inf: sort põe -Inf no início")
    check(sorted_series:get(5) == positive_infinity,  "Inf: sort põe +Inf no fim")

    local positive_infinity_series = smaug.Series({1.0, positive_infinity, 2.0}, "float64")
    check(positive_infinity_series:sum() == positive_infinity, "Inf: 1+Inf+2 = Inf")
    check(positive_infinity_series:mean() == positive_infinity, "Inf: mean = Inf")
    check(positive_infinity_series:max() == positive_infinity, "Inf: max")
    check(positive_infinity_series:gt(0):count_true() == 3, "Inf: Inf>0 = true")
    -- sort com Inf (sem NaN) é permitido
    check(positive_infinity_series:sort():len() == 3, "Inf: sort permitido (sem NaN)")
end

-- =====================================================================
-- 2. NaN é distinto de null — set(i, NaN) grava NaN, NÃO null
-- =====================================================================
do
    local nan_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64")
    nan_series:set(1, 1.0)
    nan_series:set(2, not_a_number)        -- NaN explícito do usuário
    nan_series:set(3, 3.0)
    -- a posição NÃO é null (NaN é um valor presente)
    check(nan_series:is_null(2) == false, "NaN: set(NaN) não vira null")
    -- get devolve um NaN de verdade (não nil)
    check(is_nan(nan_series:get(2)), "NaN: get devolve NaN real")
    -- conta como não-nulo (há um valor ali)
    check(nan_series:count_nonnull() == 3, "NaN: count_nonnull conta o NaN")
end

-- =====================================================================
-- 3. nil continua sendo null (distinto de NaN)
-- =====================================================================
do
    local nullable_series = smaug.Series({smaug.NA, smaug.NA}, "float64")
    nullable_series:set(1, nil)        -- nil → null
    nullable_series:set(2, 5.0)
    check(nullable_series:is_null(1) == true, "nil: set(nil) vira null")
    check(nullable_series:get(1) == nil, "nil: get de null devolve nil")

    -- numa mesma série dá pra ter null E NaN distintos
    local mixed_values_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64")
    mixed_values_series:set(1, nil)      -- null
    mixed_values_series:set(2, not_a_number)      -- NaN
    mixed_values_series:set(3, 7.0)      -- valor normal
    check(mixed_values_series:is_null(1) == true,  "mix: [1] é null")
    check(mixed_values_series:is_null(2) == false, "mix: [2] é NaN (não null)")
    check(is_nan(mixed_values_series:get(2)),      "mix: [2] get NaN")
    check(mixed_values_series:count_nonnull() == 2, "mix: count_nonnull = 2 (null não conta, NaN+valor sim)")
end

-- =====================================================================
-- 4. NaN é contagioso; ignore_na NÃO pula NaN (só pula null)
-- =====================================================================
do
    local nan_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64")
    nan_series:set(1, 1.0); nan_series:set(2, not_a_number); nan_series:set(3, 3.0)
    -- soma com NaN real → NaN → nil (contágio), mesmo com ignore_na default
    check(nan_series:sum() == nil, "NaN: sum com NaN real → nil (contágio; ignore_na pula null, não NaN)")
    check(nan_series:mean() == nil, "NaN: mean com NaN real → nil")
end

-- =====================================================================
-- 5. div/0 → null (decisão explícita: div/0 não passa, é previsível)
-- =====================================================================
do
    local numerator_series = smaug.Series({0.0, 1.0, -1.0}, "float64")
    local denominator_series = smaug.Series({0.0, 0.0,  0.0}, "float64")
    local quotient_series = numerator_series / denominator_series
    check(quotient_series:is_null(1), "op: 0/0  → null")
    check(quotient_series:is_null(2), "op: 1/0  → null")
    check(quotient_series:is_null(3), "op: -1/0 → null")
    -- escalar 0
    local scalar_quotient_series = numerator_series / 0
    check(scalar_quotient_series:is_null(1), "op: f64 / escalar 0 → null")
    check(scalar_quotient_series:is_null(2), "op: f64 / escalar 0 → null (2)")
end

-- =====================================================================
-- 6. sort/argsort RECUSAM séries com NaN (além de null)
-- =====================================================================
do
    local nan_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64")
    nan_series:set(1, 3.0); nan_series:set(2, not_a_number); nan_series:set(3, 1.0)
    check_error(function() return nan_series:sort() end, "NaN: sort recusa NaN")
    check(nan_series:argsort() == nil, "NaN: argsort retorna nil com NaN")
    -- null vindo de div/0 também é recusado pelo sort
    local numerator_series = smaug.Series({0.0, 1.0}, "float64")
    local denominator_series = smaug.Series({0.0, 2.0}, "float64")
    local quotient_series = numerator_series / denominator_series            -- [1] = null (0/0 → null), [2] = 0.5
    check_error(function() return quotient_series:sort() end, "div/0: sort recusa null resultante")
end

-- =====================================================================
-- 7. Comparações com NaN → false (IEEE), com máscara VÁLIDA (não NA)
-- =====================================================================
do
    local nan_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64")
    nan_series:set(1, 5.0); nan_series:set(2, not_a_number); nan_series:set(3, 10.0)
    local positive_value_mask = nan_series:gt(0)
    check(positive_value_mask:get(1) == true,  "cmp-NaN: 5>0 true")
    -- NaN > 0 é false pelo IEEE; e como NaN é valor (não null), a máscara é válida
    check(positive_value_mask:get(2) == false, "cmp-NaN: NaN>0 → false (não NA)")
    check(positive_value_mask:is_null(2) == false, "cmp-NaN: resultado de NaN é válido (não NA)")
    check(positive_value_mask:get(3) == true,  "cmp-NaN: 10>0 true")
    check(positive_value_mask:count_true() == 2, "cmp-NaN: count_true 2")
end

-- =====================================================================
-- 8. -0.0 — igual a 0.0 nas comparações, neutro na soma
-- =====================================================================
do
    local signed_zero_series = smaug.Series({-0.0, 0.0}, "float64")
    check(signed_zero_series:eq(0.0):count_true() == 2, "-0.0: -0 e +0 ambos == 0")
    check(signed_zero_series:sum() == 0, "-0.0: soma neutra")
    check(signed_zero_series:min() == signed_zero_series:max(), "-0.0: min == max (mesmo valor)")
end

-- =====================================================================
-- 9. min_count opt-in em sum/prod (Series)
-- =====================================================================
do
    local nullable_integer_series = smaug.Series({10, smaug.NA, smaug.NA}, "int64")
    check(nullable_integer_series:sum() == 10, "5.5 Series sum default ignora NA = 10")
    check(nullable_integer_series:sum(nil, 2) == nil, "5.5 Series sum(min_count=2): 1 não-nulo → NA")
    check(nullable_integer_series:sum(nil, 1) == 10, "5.5 Series sum(min_count=1): 1 não-nulo → 10")
    local all_null_series = smaug.Series({smaug.NA, smaug.NA}, "int64")
    check(all_null_series:sum() == 0, "5.5 Series sum all-null default = 0 (preservado)")
    check(all_null_series:sum(nil, 1) == nil, "5.5 Series sum all-null min_count=1 → NA")
    check(nullable_integer_series:prod(nil, 2) == nil, "5.5 Series prod(min_count=2) → NA")
end

-- =====================================================================
-- 10. min/max em dtypes ordenáveis não-numéricos (7.2b)
-- =====================================================================
do
    local datetime_series = smaug.Series({"2020-03-01", "2020-01-01", "2020-06-15"}, "datetime")
    check(datetime_series:min() == datetime_series:get(datetime_series:argmin()), "7.2b dt:min == get(argmin)")
    check(datetime_series:max() == datetime_series:get(datetime_series:argmax()), "7.2b dt:max == get(argmax)")
    check(type(datetime_series:min()) == "number",     "7.2b dt:min retorna número (epoch)")

    local fruit_names_series = smaug.Series({"banana", "abacaxi", "caju"}, "string")
    check(fruit_names_series:min() == "abacaxi", "7.2b str:min = abacaxi")
    check(fruit_names_series:max() == "caju",    "7.2b str:max = caju")
    local empty_string_series = smaug.Series({"z", "", "m"}, "string")
    check(empty_string_series:min() == "",       "7.2b str:min com vazia = '' (válida)")

    local boolean_series = smaug.Series({true, false, true}, "bool")
    check(boolean_series:min() == false, "7.2b bool:min = false")
    check(boolean_series:max() == true,  "7.2b bool:max = true")

    check(smaug.Series({smaug.NA, smaug.NA}, "string"):min()   == nil, "7.2b str all-NA min = nil")
    check(smaug.Series({smaug.NA, smaug.NA}, "bool"):min()     == nil, "7.2b bool all-NA min = nil")
    check(smaug.Series({smaug.NA, smaug.NA}, "datetime"):min() == nil, "7.2b dt all-NA min = nil")

    local nullable_string_series = smaug.Series({"a", smaug.NA, "c"}, "string")
    check(nullable_string_series:min()      == "a",  "7.2b str:min default ignora NA")
    check(nullable_string_series:min(false) == nil,  "7.2b str:min(false) com NA = nil")
    local nullable_boolean_series = smaug.Series({true, smaug.NA}, "bool")
    check(nullable_boolean_series:min(false) == nil,  "7.2b bool:min(false) com NA = nil")
end

print(string.format("OK — %d checks passaram (Series: reduções, valores especiais f64)", passed_checks))
