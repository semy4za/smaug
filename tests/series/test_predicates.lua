-- tests/series/test_predicates.lua
-- Predicados (between/isin/is_unique/is_monotonic/equals/compare/idxmin/idxmax/
-- first_last_valid_index) e duplicatas (duplicated/drop_duplicates/combine_first/
-- searchsorted/rep_each).
-- Consolida: test_predicates.lua + test_duplicates.lua
-- Rode da raiz: luajit tests/series/test_predicates.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local function approximately_equal(left_value, right_value) return math.abs(left_value - right_value) < 1e-9 end

local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

-- =====================================================================
-- 1. between — inclusividade
-- =====================================================================
do
    local integer_series = smaug.Series({1, 5, 10, 15, 20}, "int64")

    -- both (default): 5 ≤ x ≤ 15
    local both_bounds_mask = integer_series:between(5, 15)
    check(both_bounds_mask._dtype == "bool",        "between → Series<bool>")
    check(both_bounds_mask:get(1) == false,         "between both[1]=1 → false")
    check(both_bounds_mask:get(2) == true,          "between both[2]=5 → true (incl left)")
    check(both_bounds_mask:get(3) == true,          "between both[3]=10 → true")
    check(both_bounds_mask:get(4) == true,          "between both[4]=15 → true (incl right)")
    check(both_bounds_mask:get(5) == false,         "between both[5]=20 → false")

    -- neither: 5 < x < 15
    local neither_bound_mask = integer_series:between(5, 15, "neither")
    check(neither_bound_mask:get(2) == false,      "between neither[2]=5 → false")
    check(neither_bound_mask:get(3) == true,       "between neither[3]=10 → true")
    check(neither_bound_mask:get(4) == false,      "between neither[4]=15 → false")

    -- left: 5 ≤ x < 15
    local left_bound_mask = integer_series:between(5, 15, "left")
    check(left_bound_mask:get(2) == true,          "between left[2]=5 → true")
    check(left_bound_mask:get(4) == false,         "between left[4]=15 → false")

    -- right: 5 < x ≤ 15
    local right_bound_mask = integer_series:between(5, 15, "right")
    check(right_bound_mask:get(2) == false,        "between right[2]=5 → false")
    check(right_bound_mask:get(4) == true,         "between right[4]=15 → true")

    -- null propaga
    local nullable_integer_series = smaug.Series({1, smaug.NA, 10}, "int64")
    local between_result = nullable_integer_series:between(0, 20)
    check(between_result:get(2) == nil,               "between null → null")

    -- inclusive inválido → erro
    local succeeded = pcall(function() integer_series:between(1, 2, "bad") end)
    check(not succeeded,                     "between inclusive inválido = erro")

    -- between em string
    local string_series = smaug.Series({"apple", "mango", "zebra"}, "string")
    local between_result_2 = string_series:between("b", "n")
    check(between_result_2:get(1) == false,             "between string apple → false")
    check(between_result_2:get(2) == true,              "between string mango → true")
    check(between_result_2:get(3) == false,             "between string zebra → false")
end

-- =====================================================================
-- 2. isin
-- =====================================================================
do
    local integer_series = smaug.Series({1, 5, 10, 15, 20}, "int64")
    local nullable_integer_series = smaug.Series({1, smaug.NA, 10}, "int64")
    local string_series = smaug.Series({"apple", "mango", "zebra"}, "string")

    local isin_result = integer_series:isin({5, 20})
    check(isin_result._dtype == "bool",             "isin → Series<bool>")
    check(isin_result:get(1) == false,              "isin[1]=1 não está")
    check(isin_result:get(2) == true,               "isin[2]=5 está")
    check(isin_result:get(5) == true,               "isin[5]=20 está")

    -- null → null
    local isin_result_2 = nullable_integer_series:isin({1, 10})
    check(isin_result_2:get(2) == nil,               "isin null → null")

    -- isin com strings
    local isin_result_3 = string_series:isin({"apple", "zebra"})
    check(isin_result_3:get(1) == true,              "isin string apple → true")
    check(isin_result_3:get(2) == false,             "isin string mango → false")
    check(isin_result_3:get(3) == true,              "isin string zebra → true")

    -- isin vazio → tudo false
    local isin_result_4 = integer_series:isin({})
    check(isin_result_4:get(1) == false and isin_result_4:get(3) == false, "isin vazio → tudo false")

    -- não-tabela → erro
    local succeeded = pcall(function() integer_series:isin(5) end)
    check(not succeeded,                    "isin não-tabela = erro")
end

-- =====================================================================
-- 3. is_unique
-- =====================================================================
do
    check(smaug.Series({1, 2, 3}, "int64"):is_unique() == true,   "is_unique distinto")
    check(smaug.Series({1, 2, 2}, "int64"):is_unique() == false,  "is_unique com duplicata")
    check(smaug.Series({}, "int64"):is_unique() == true,          "is_unique vazia = true")

    -- nulos ignorados
    check(smaug.Series({1, smaug.NA, 2, smaug.NA}, "int64"):is_unique() == true, "is_unique ignora nulls")
    check(smaug.Series({1, smaug.NA, 1}, "int64"):is_unique() == false,    "is_unique dup com null = false")

    -- string
    check(smaug.Series({"a", "b", "a"}, "string"):is_unique() == false, "is_unique string dup")
end

-- =====================================================================
-- 4. is_monotonic_increasing / decreasing
-- =====================================================================
do
    -- não-decrescente (default)
    check(smaug.Series({1, 2, 2, 3}, "int64"):is_monotonic_increasing() == true,
          "mono inc não-estrito (com igual)")

    -- estritamente crescente
    check(smaug.Series({1, 2, 2, 3}, "int64"):is_monotonic_increasing(true) == false,
          "mono inc estrito rejeita igual")
    check(smaug.Series({1, 2, 3, 4}, "int64"):is_monotonic_increasing(true) == true,
          "mono inc estrito ok")

    -- decrescente
    check(smaug.Series({3, 2, 1}, "int64"):is_monotonic_decreasing() == true,
          "mono dec")
    check(smaug.Series({3, 2, 2, 1}, "int64"):is_monotonic_decreasing(true) == false,
          "mono dec estrito rejeita igual")

    -- não-monotônica
    check(smaug.Series({1, 3, 2}, "int64"):is_monotonic_increasing() == false,
          "mono inc rejeita não-ordenada")

    -- null quebra
    check(smaug.Series({1, smaug.NA, 3}, "int64"):is_monotonic_increasing() == false,
          "mono com null = false")

    -- vazia / 1 elemento = true (vacuamente)
    check(smaug.Series({}, "int64"):is_monotonic_increasing() == true,  "mono vazia = true")
    check(smaug.Series({5}, "int64"):is_monotonic_increasing() == true, "mono single = true")

    -- string lexicográfica
    check(smaug.Series({"a", "b", "c"}, "string"):is_monotonic_increasing() == true,
          "mono inc string")
end

-- =====================================================================
-- 5. equals (Series)
-- =====================================================================
do
    local nullable_integer_series = smaug.Series({1, 2, smaug.NA}, "int64")
    local nullable_integer_series_2 = smaug.Series({1, 2, smaug.NA}, "int64")
    local integer_series = smaug.Series({1, 2, 3}, "int64")

    check(nullable_integer_series:equals(nullable_integer_series_2) == true,          "equals idênticas (com null)")
    check(nullable_integer_series:equals(integer_series) == false,         "equals difere (null vs 3)")

    -- dtype diferente
    local floating_point_series = smaug.Series({1, 2, 3}, "float64")
    check(integer_series:equals(floating_point_series) == false,         "equals dtype diferente = false")

    -- tamanho diferente
    check(integer_series:equals(smaug.Series({1, 2}, "int64")) == false, "equals tamanho diferente")

    -- não-Series
    check(nullable_integer_series:equals(42) == false,         "equals não-Series = false")

    -- NaN estrutural: NaN == NaN aqui
    local floating_point_series_2 = smaug.Series({0/0, 1}, "float64")
    local floating_point_series_3 = smaug.Series({0/0, 1}, "float64")
    check(floating_point_series_2:equals(floating_point_series_3) == true,      "equals NaN estrutural (NaN==NaN)")
end

-- =====================================================================
-- 6. compare (Series)
-- =====================================================================
do
    local nullable_integer_series = smaug.Series({1, 2, smaug.NA}, "int64")
    local nullable_integer_series_2 = smaug.Series({1, 2, smaug.NA}, "int64")
    local integer_series = smaug.Series({1, 2, 3}, "int64")
    local floating_point_series = smaug.Series({1, 2, 3}, "float64")

    local comparison_dataset = nullable_integer_series:compare(integer_series)
    check(comparison_dataset:nrows() == 1,               "compare: 1 diferença")
    check(comparison_dataset:column("i"):get(1) == 3,    "compare i = 3")
    check(comparison_dataset:column("self"):get(1) == nil,  "compare self = null")
    check(comparison_dataset:column("other"):get(1) == 3,   "compare other = 3")

    -- idênticas → vazio
    check(nullable_integer_series:compare(nullable_integer_series_2):nrows() == 0,    "compare idênticas = vazio")

    -- dtype incompatível → erro
    local succeeded = pcall(function() integer_series:compare(floating_point_series) end)
    check(not succeeded,                     "compare dtype diferente = erro")
end

-- =====================================================================
-- 7. idxmin / idxmax (aliases de argmin/argmax)
-- =====================================================================
do
    local integer_series = smaug.Series({3, 1, 4, 1, 5}, "int64")
    check(integer_series:idxmin() == 2,                "idxmin = 2 (primeiro mínimo)")
    check(integer_series:idxmax() == 5,                "idxmax = 5")
    check(integer_series:idxmin() == integer_series:argmin(),       "idxmin == argmin")
    check(integer_series:idxmax() == integer_series:argmax(),       "idxmax == argmax")
end

-- =====================================================================
-- 8. first_valid_index / last_valid_index
-- =====================================================================
do
    local nullable_integer_series = smaug.Series({smaug.NA, smaug.NA, 7, smaug.NA, 9, smaug.NA}, "int64")
    check(nullable_integer_series:first_valid_index() == 3,    "first_valid = 3")
    check(nullable_integer_series:last_valid_index() == 5,     "last_valid = 5")

    -- toda nula → nil
    local allnull = smaug.Series({smaug.NA, smaug.NA}, "int64")
    check(allnull:first_valid_index() == nil, "first_valid toda nula = nil")
    check(allnull:last_valid_index() == nil,  "last_valid toda nula = nil")

    -- sem nulos
    local nonull = smaug.Series({1, 2, 3}, "int64")
    check(nonull:first_valid_index() == 1, "first_valid sem null = 1")
    check(nonull:last_valid_index() == 3,  "last_valid sem null = 3")
end

-- =====================================================================
-- 9. DataSet:equals
-- =====================================================================
do
    local source_dataset = smaug.DataSet({{"a", {1,2,3}, "int64"}, {"b", {"x","y","z"}, "string"}})
    local source_dataset_2 = smaug.DataSet({{"a", {1,2,3}, "int64"}, {"b", {"x","y","z"}, "string"}})
    local source_dataset_3 = smaug.DataSet({{"a", {1,2,9}, "int64"}, {"b", {"x","y","z"}, "string"}})

    check(source_dataset:equals(source_dataset_2) == true,          "DataSet equals idênticos")
    check(source_dataset:equals(source_dataset_3) == false,         "DataSet equals difere")

    -- colunas em ordem diferente → false
    local source_dataset_4 = smaug.DataSet({{"b", {"x","y","z"}, "string"}, {"a", {1,2,3}, "int64"}})
    check(source_dataset:equals(source_dataset_4) == false,         "DataSet equals ordem diferente = false")

    -- ncols diferente
    local source_dataset_5 = smaug.DataSet({{"a", {1,2,3}, "int64"}})
    check(source_dataset:equals(source_dataset_5) == false,         "DataSet equals ncols diferente")

    -- não-DataSet
    check(source_dataset:equals(42) == false,         "DataSet equals não-DataSet = false")
end

-- =====================================================================
-- 10. DataSet:compare
-- =====================================================================
do
    local source_dataset = smaug.DataSet({{"a", {1,2,3}, "int64"}, {"b", {"x","y","z"}, "string"}})
    local source_dataset_2 = smaug.DataSet({{"a", {1,2,3}, "int64"}, {"b", {"x","y","z"}, "string"}})
    local source_dataset_3 = smaug.DataSet({{"a", {1,2,9}, "int64"}, {"b", {"x","y","z"}, "string"}})
    local source_dataset_4 = smaug.DataSet({{"a", {1,2,3}, "int64"}})

    local comparison_dataset = source_dataset:compare(source_dataset_3)
    check(comparison_dataset:nrows() == 1,              "DataSet compare: 1 diferença")
    check(comparison_dataset:column("linha"):get(1) == 3,   "DataSet compare linha = 3")
    check(comparison_dataset:column("coluna"):get(1) == "a", "DataSet compare coluna = a")
    check(comparison_dataset:column("self"):get(1) == "3",   "DataSet compare self = 3")
    check(comparison_dataset:column("other"):get(1) == "9",  "DataSet compare other = 9")

    -- idênticos → vazio
    check(source_dataset:compare(source_dataset_2):nrows() == 0,    "DataSet compare idênticos = vazio")

    -- formas diferentes → erro
    local succeeded = pcall(function() source_dataset:compare(source_dataset_4) end)
    check(not succeeded,                    "DataSet compare formas diferentes = erro")
end

-- =====================================================================
-- 11. Series:duplicated — keep first/last/none, nulos como valor
-- =====================================================================
do
    local nullable_integer_series = smaug.Series({1, 2, 2, 3, 1, smaug.NA, smaug.NA}, "int64")

    local duplicate_mask = nullable_integer_series:duplicated("first")
    check(duplicate_mask._dtype == "bool",          "duplicated → bool")
    check(duplicate_mask:get(1) == false,           "dup first [1]=1 1ª → false")
    check(duplicate_mask:get(3) == true,            "dup first [3]=2 2ª → true")
    check(duplicate_mask:get(5) == true,            "dup first [5]=1 repetido → true")
    check(duplicate_mask:get(6) == false,           "dup first [6]=NA 1ª → false")
    check(duplicate_mask:get(7) == true,            "dup first [7]=NA 2ª → true (null é valor)")

    local duplicate_mask_2 = nullable_integer_series:duplicated("last")
    check(duplicate_mask_2:get(1) == true,            "dup last [1]=1 não-última → true")
    check(duplicate_mask_2:get(5) == false,           "dup last [5]=1 última → false")
    check(duplicate_mask_2:get(6) == true,            "dup last [6]=NA não-última → true")
    check(duplicate_mask_2:get(7) == false,           "dup last [7]=NA última → false")

    local duplicate_mask_3 = nullable_integer_series:duplicated("none")
    check(duplicate_mask_3:get(1) == true,            "dup none [1]=1 tem cópia → true")
    check(duplicate_mask_3:get(4) == false,           "dup none [4]=3 único → false")
    check(duplicate_mask_3:get(6) == true,            "dup none [6]=NA tem cópia → true")

    -- default = first
    check(nullable_integer_series:duplicated():get(3) == true, "duplicated() default = first")

    -- keep inválido → erro
    check(not pcall(function() nullable_integer_series:duplicated("bad") end), "duplicated keep inválido = erro")
end

-- =====================================================================
-- 12. Series:drop_duplicates
-- =====================================================================
do
    local nullable_integer_series = smaug.Series({1, 2, 2, 3, 1, smaug.NA, smaug.NA}, "int64")

    local dd_first = nullable_integer_series:drop_duplicates("first")
    -- mantém: 1, 2, 3, NA (primeira de cada)
    check(dd_first:len() == 4,          "drop_duplicates first: 4 elementos")
    check(dd_first:get(1) == 1,         "drop first: 1")
    check(dd_first:get(2) == 2,         "drop first: 2")
    check(dd_first:get(3) == 3,         "drop first: 3")
    check(dd_first:get(4) == nil,       "drop first: NA")

    -- none: só o que não tem cópia → 3
    local dd_none = nullable_integer_series:drop_duplicates("none")
    check(dd_none:len() == 1,           "drop_duplicates none: 1 elemento")
    check(dd_none:get(1) == 3,          "drop none: só o 3")

    -- série sem duplicatas → inalterada
    local integer_series = smaug.Series({1, 2, 3}, "int64")
    check(integer_series:drop_duplicates():len() == 3, "drop sem duplicatas: inalterada")
end

-- =====================================================================
-- 13. Series:combine_first
-- =====================================================================
do
    local nullable_integer_series = smaug.Series({1, smaug.NA, 3, smaug.NA}, "int64")
    local nullable_integer_series_2 = smaug.Series({9, 8, 7, smaug.NA}, "int64")

    local combine_first_result = nullable_integer_series:combine_first(nullable_integer_series_2)
    check(combine_first_result:get(1) == 1,             "combine_first: self não-null preservado")
    check(combine_first_result:get(2) == 8,             "combine_first: null preenchido por other")
    check(combine_first_result:get(3) == 3,             "combine_first: self preservado")
    check(combine_first_result:get(4) == nil,           "combine_first: ambos null → null")

    -- string
    local nullable_string_series = smaug.Series({"x", smaug.NA}, "string")
    local string_series = smaug.Series({"y", "z"}, "string")
    check(nullable_string_series:combine_first(string_series):get(2) == "z", "combine_first string")

    -- erros
    check(not pcall(function() nullable_integer_series:combine_first(42) end), "combine_first não-Series = erro")
    check(not pcall(function()
        nullable_integer_series:combine_first(smaug.Series({1.0}, "float64"))
    end), "combine_first dtype diferente = erro")
    check(not pcall(function()
        nullable_integer_series:combine_first(smaug.Series({1,2}, "int64"))
    end), "combine_first tamanho diferente = erro")
end

-- =====================================================================
-- 14. Series:searchsorted — binary search
-- =====================================================================
do
    local integer_series = smaug.Series({10, 20, 20, 30, 40}, "int64")

    check(integer_series:searchsorted(20) == 2,            "searchsorted 20 left = 2 (antes dos iguais)")
    check(integer_series:searchsorted(20, "right") == 4,   "searchsorted 20 right = 4 (após os iguais)")
    check(integer_series:searchsorted(25) == 4,            "searchsorted 25 = 4 (entre 20 e 30)")
    check(integer_series:searchsorted(5) == 1,             "searchsorted 5 = 1 (antes de tudo)")
    check(integer_series:searchsorted(99) == 6,            "searchsorted 99 = 6 (após tudo)")
    check(integer_series:searchsorted(10) == 1,            "searchsorted 10 left = 1")
    check(integer_series:searchsorted(40, "right") == 6,   "searchsorted 40 right = 6")

    -- série não-ordenada → erro
    local unsorted_datetime_series = smaug.Series({1, 2, 2, 3, 1, smaug.NA, smaug.NA}, "int64")
    check(not pcall(function() unsorted_datetime_series:searchsorted(2) end), "searchsorted não-ordenada = erro")

    -- side inválido → erro
    check(not pcall(function() integer_series:searchsorted(20, "bad") end), "searchsorted side inválido = erro")

    -- float
    local floating_point_series = smaug.Series({1.5, 2.5, 3.5}, "float64")
    check(floating_point_series:searchsorted(2.0) == 2,          "searchsorted float")

    -- string (ordenada lexicograficamente)
    local string_series = smaug.Series({"apple", "mango", "zebra"}, "string")
    check(string_series:searchsorted("banana") == 2,     "searchsorted string")
end

-- =====================================================================
-- 15. Series:rep_each
-- =====================================================================
do
    -- escalar
    local repeated_series = smaug.Series({1, 2, 3}, "int64"):rep_each(2)
    check(repeated_series:len() == 6,               "rep_each(2): 6 elementos")
    check(repeated_series:get(1) == 1 and repeated_series:get(2) == 1, "rep_each(2): 1,1")
    check(repeated_series:get(5) == 3 and repeated_series:get(6) == 3, "rep_each(2): 3,3")

    -- n=1 → cópia
    local repeated_series_2 = smaug.Series({1, 2}, "int64"):rep_each(1)
    check(repeated_series_2:len() == 2,               "rep_each(1): inalterado em tamanho")

    -- n=0 → vazia
    local repeated_series_3 = smaug.Series({1, 2, 3}, "int64"):rep_each(0)
    check(repeated_series_3:len() == 0,               "rep_each(0): série vazia")

    -- por Series<int64>
    local integer_series  = smaug.Series({10, 20, 30}, "int64")
    local times = smaug.Series({1, 0, 2}, "int64")
    local repeated_series_4 = integer_series:rep_each(times)
    check(repeated_series_4:len() == 3,               "rep_each Series: 1+0+2 = 3 elementos")
    check(repeated_series_4:get(1) == 10,             "rep_each Series: 10 (1x)")
    check(repeated_series_4:get(2) == 30,             "rep_each Series: 30 (2x, 1º)")
    check(repeated_series_4:get(3) == 30,             "rep_each Series: 30 (2x, 2º)")

    -- nulos repetidos como nulos
    local repeated_series_5 = smaug.Series({smaug.NA, 5}, "int64"):rep_each(2)
    check(repeated_series_5:get(1) == nil and repeated_series_5:get(2) == nil, "rep_each: nulos repetidos")
    check(repeated_series_5:get(3) == 5,               "rep_each: valor após nulos")

    -- erros
    check(not pcall(function() integer_series:rep_each(-1) end), "rep_each n negativo = erro")
    check(not pcall(function() integer_series:rep_each(1.5) end), "rep_each n não-inteiro = erro")
    check(not pcall(function()
        integer_series:rep_each(smaug.Series({1.0,2.0,3.0}, "float64"))
    end), "rep_each Series não-int64 = erro")
end

-- =====================================================================
-- 16. DataSet:duplicated
-- =====================================================================
do
    local source_dataset = smaug.DataSet({
        {"a", {1, 1, 2, 2, 3},          "int64"},
        {"b", {"x", "x", "y", "z", "w"}, "string"},
    })

    -- por todas as colunas: linha 2 (1,x) == linha 1
    local duplicate_mask = source_dataset:duplicated()
    check(duplicate_mask:get(1) == false,          "DataSet dup all [1] → false")
    check(duplicate_mask:get(2) == true,           "DataSet dup all [2] = (1,x) repetida → true")
    check(duplicate_mask:get(4) == false,          "DataSet dup all [4] = (2,z) único → false")

    -- por subset "a"
    local duplicate_mask_2 = source_dataset:duplicated("a")
    check(duplicate_mask_2:get(2) == true,           "DataSet dup subset a [2]=1 → true")
    check(duplicate_mask_2:get(4) == true,           "DataSet dup subset a [4]=2 → true")
    check(duplicate_mask_2:get(5) == false,          "DataSet dup subset a [5]=3 → false")

    -- subset como lista
    local duplicate_mask_3 = source_dataset:duplicated({"a", "b"})
    check(duplicate_mask_3:get(2) == true,           "DataSet dup [a,b] [2] → true")
    check(duplicate_mask_3:get(3) == false,          "DataSet dup [a,b] [3] → false")

    -- keep none por "a"
    local duplicate_mask_4 = source_dataset:duplicated("a", "none")
    check(duplicate_mask_4:get(1) == true,           "DataSet dup a none [1] → true (tem cópia)")
    check(duplicate_mask_4:get(5) == false,          "DataSet dup a none [5]=3 único → false")

    -- coluna inexistente → erro
    check(not pcall(function() source_dataset:duplicated("zzz") end), "DataSet dup coluna inexistente = erro")
end

-- =====================================================================
-- 17. DataSet:drop_duplicates
-- =====================================================================
do
    local source_dataset = smaug.DataSet({
        {"a", {1, 1, 2, 2, 3},          "int64"},
        {"b", {"x", "x", "y", "z", "w"}, "string"},
    })

    -- por todas: remove linha 2
    local ddall = source_dataset:drop_duplicates()
    check(ddall:nrows() == 4,           "DataSet drop all: 4 linhas")

    -- por subset a: mantém a=1,2,3 (primeiras)
    local deduplicated_result = source_dataset:drop_duplicates("a")
    check(deduplicated_result:nrows() == 3,             "DataSet drop subset a: 3 linhas")
    check(deduplicated_result:at(1, "a") == 1,          "DataSet drop a: primeira a=1")
    check(deduplicated_result:at(2, "a") == 2,          "DataSet drop a: primeira a=2")
    check(deduplicated_result:at(3, "a") == 3,          "DataSet drop a: a=3")

    -- keep last por a
    local deduplicated_result_2 = source_dataset:drop_duplicates("a", "last")
    check(deduplicated_result_2:nrows() == 3,             "DataSet drop a last: 3 linhas")
    check(deduplicated_result_2:at(1, "b") == "x",        "DataSet drop a last: última a=1 tem b=x")
end

-- =====================================================================
-- 18. 10.6 Passo B (série+série): combine_first delega a coalesce (Anel 0)
-- =====================================================================
do
    local ffi = require("ffi")
    local large_integer = ffi.new("int64_t", 9007199254740993LL)  -- 2^53+1

    -- self mantém o valor grande; buraco preenchido por other também grande;
    -- posição ambos-nulos permanece nula.
    local allocated_integer_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "int64", "a"); allocated_integer_series:set(1, large_integer); allocated_integer_series:set_null(2); allocated_integer_series:set_null(3)
    local allocated_integer_series_2 = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "int64", "b"); allocated_integer_series_2:set(1, 7LL); allocated_integer_series_2:set(2, large_integer); allocated_integer_series_2:set_null(3)
    local combine_first_result = allocated_integer_series:combine_first(allocated_integer_series_2)
    check(tostring(combine_first_result:get_raw(1)) == tostring(large_integer), "10.6B: combine_first self 2^53+1 exato")
    check(tostring(combine_first_result:get_raw(2)) == tostring(large_integer), "10.6B: combine_first buraco por other 2^53+1 exato")
    check(combine_first_result:is_null(3),                            "10.6B: combine_first ambos-nulos → nulo")

    -- não-regressão: int64 <= 2^53 intacto.
    local allocated_integer_series_3 = smaug.Series({smaug.NA}, "int64", "a"); allocated_integer_series_3:set_null(1)
    local integer_series = smaug.Series({42}, "int64")
    check(allocated_integer_series_3:combine_first(integer_series):get(1) == 42, "10.6B: combine_first i64<=2^53 intacto")

    -- f64: tabela-verdade completa (self mantém / other preenche / ambos-nulos).
    local allocated_floating_point_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64"); allocated_floating_point_series:set(1, 1.5); allocated_floating_point_series:set_null(2); allocated_floating_point_series:set_null(3)
    local allocated_floating_point_series_2 = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64"); allocated_floating_point_series_2:set(1, 9.9); allocated_floating_point_series_2:set(2, 2.5); allocated_floating_point_series_2:set_null(3)
    local combine_first_result_2 = allocated_floating_point_series:combine_first(allocated_floating_point_series_2)
    check(combine_first_result_2:get(1) == 1.5,  "10.6B: combine_first f64 self mantido")
    check(combine_first_result_2:get(2) == 2.5,  "10.6B: combine_first f64 buraco por other")
    check(combine_first_result_2:is_null(3),     "10.6B: combine_first f64 ambos-nulos → nulo")

    -- str: \0 embutido preservado, '' de self mantida (válida), ambos-nulos → nulo.
    local allocated_string_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA, smaug.NA}, "string"); allocated_string_series:set(1, "abc"); allocated_string_series:set_null(2); allocated_string_series:set_null(3); allocated_string_series:set(4, "")
    local allocated_string_series_2 = smaug.Series({smaug.NA, smaug.NA, smaug.NA, smaug.NA}, "string"); allocated_string_series_2:set(1, "X"); allocated_string_series_2:set(2, "a\0b"); allocated_string_series_2:set_null(3); allocated_string_series_2:set(4, "Y")
    local combine_first_result_3 = allocated_string_series:combine_first(allocated_string_series_2)
    check(combine_first_result_3:get(1) == "abc",  "10.6B: combine_first str self mantido")
    check(combine_first_result_3:get(2) == "a\0b", "10.6B: combine_first str buraco por other, \\0 preservado")
    check(combine_first_result_3:is_null(3),       "10.6B: combine_first str ambos-nulos → nulo")
    check(combine_first_result_3:get(4) == "",     "10.6B: combine_first str '' de self mantido (válido)")

    -- str total==0: ambas toda-nulas → resultado toda-nulo, buffer final vazio
    -- (exercita o ramo `total>0 ? total : INIT`).
    local allocated_string_series_3 = smaug.Series({smaug.NA, smaug.NA}, "string"); allocated_string_series_3:set_null(1); allocated_string_series_3:set_null(2)
    local allocated_string_series_4 = smaug.Series({smaug.NA, smaug.NA}, "string"); allocated_string_series_4:set_null(1); allocated_string_series_4:set_null(2)
    local combine_first_result_4 = allocated_string_series_3:combine_first(allocated_string_series_4)
    check(combine_first_result_4:is_null(1) and combine_first_result_4:is_null(2), "10.6B: combine_first str ambas toda-nulas → toda-nulo")

    -- datetime (epoch_ms): self mantém / other preenche / ambos-nulos → nulo.
    local allocated_datetime_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "datetime"); allocated_datetime_series:set(1, 1000); allocated_datetime_series:set_null(2); allocated_datetime_series:set_null(3)
    local allocated_datetime_series_2 = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "datetime"); allocated_datetime_series_2:set(1, 9999); allocated_datetime_series_2:set(2, 2000); allocated_datetime_series_2:set_null(3)
    local combine_first_result_5 = allocated_datetime_series:combine_first(allocated_datetime_series_2)
    check(combine_first_result_5:get(1) == 1000, "10.6B: combine_first dt self mantido")
    check(combine_first_result_5:get(2) == 2000, "10.6B: combine_first dt buraco por other")
    check(combine_first_result_5:is_null(3),     "10.6B: combine_first dt ambos-nulos → nulo")
end

-- =====================================================================
-- 19. L2: int64 > 2^53 em operações de cardinalidade/igualdade (core/keys)
-- =====================================================================
do
    local ffi = require("ffi")
    local large_integer = ffi.new("int64_t", 9007199254740992LL)  -- 2^53
    local large_integer_2 = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1
    local large_integer_3 = ffi.new("int64_t", 9007199254740994LL) -- 2^53 + 2

    local integer_series = smaug.Series({large_integer, large_integer_2, large_integer}, "int64")   -- 2 distintos, A repetido

    check(integer_series:nunique() == 2,        "L2 nunique int64>2^53 = 2")
    check(integer_series:unique():len() == 2,   "L2 unique int64>2^53 → 2 elementos")
    check(integer_series:value_counts():nrows() == 2, "L2 value_counts int64>2^53 → 2 linhas")
    check(integer_series:mode() == large_integer,           "L2 mode int64>2^53 = valor exato mais frequente")

    local duplicate_mask = integer_series:duplicated()
    check(duplicate_mask:get(1) == false and duplicate_mask:get(2) == false and duplicate_mask:get(3) == true,
          "L2 duplicated int64>2^53 exato (A,B,A → f,f,t)")

    local integer_series_2 = smaug.Series({large_integer, large_integer_2, large_integer_3}, "int64")
    local isin_result  = integer_series_2:isin({large_integer_2})        -- só B presente no conjunto
    check(isin_result:get(1) == false and isin_result:get(2) == true and isin_result:get(3) == false,
          "L2 isin int64>2^53 distingue exato")

    -- isin com número cru na lista (usuário passa 5, não 5LL) segue funcionando
    local integer_series_3 = smaug.Series({1, 5, 9}, "int64")
    local isin_result_2 = integer_series_3:isin({5})
    check(isin_result_2:get(1) == false and isin_result_2:get(2) == true and isin_result_2:get(3) == false,
          "L2 isin: número cru na lista bate com int64 da série")
end

print(string.format("OK — %d checks passaram (Series: predicados, duplicatas, searchsorted, rep_each)", passed_checks))
