-- tests/series/test_stat.lua
-- Series: estatísticas descritivas (F.1), análise de distintos,
-- transformações element-wise standalone e estatísticas avançadas.
-- Testa métodos de lua/smaug/core/series/stats/_stat.lua e _stat_adv.lua.
-- Todo valor de referência abaixo foi conferido rodando contra o código
-- real (não deduzido de memória) — ver notas onde o comportamento não é óbvio.
-- Rode da raiz: luajit tests/series/test_stat.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")

local passed_checks = 0

local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local function approximately_equal(left_value, right_value, tolerance)
    tolerance = tolerance or 1e-9
    if left_value == nil and right_value == nil then return true end
    if left_value == nil or right_value == nil then return false end
    local formatted_text, formatted_text_2 = tostring(left_value), tostring(right_value)
    if formatted_text == "nan" or formatted_text == "-nan" or formatted_text == "1.#SNAN" then
        return formatted_text_2 == "nan" or formatted_text_2 == "-nan" or formatted_text_2 == "1.#SNAN"
    end
    if formatted_text == "inf" or formatted_text == "1.#INF" then return formatted_text_2 == "inf" or formatted_text_2 == "1.#INF" end
    if formatted_text == "-inf" or formatted_text == "-1.#INF" then return formatted_text_2 == "-inf" or formatted_text_2 == "-1.#INF" end
    return math.abs(left_value - right_value) < tolerance
end

local function is_nan(value)
    return value ~= value
end

local function rejects(callback)
    return not pcall(callback)
end

-- =====================================================================
-- 1 — Estatísticas básicas (unique, nunique, value_counts, prod, median, quantile, mode)
-- =====================================================================
do
    -- unique(): valores distintos, NA conta como distinto
    local nullable_integer_series = smaug.Series({1, 2, 2, 3, smaug.NA}, "int64")
    local unique_values = nullable_integer_series:unique()
    check(unique_values:len() == 4, "unique: 4 distintos (1,2,3,NA)")
    check(nullable_integer_series:nunique() == 3, "nunique: 3 distintos (NA não conta)")

    -- value_counts(): ordenado por frequência
    local value_counts = nullable_integer_series:value_counts()
    check(value_counts:len() == 3, "value_counts: 3 linhas (NA excluído)")
    check(value_counts:column("value"):get(1) == 2, "value_counts: valor mais freq = 2")
    check(value_counts:column("count"):get(1) == 2, "value_counts: count = 2")

    -- prod(): int64 com NA ignorado
    local product_result = smaug.Series({2, 3, smaug.NA, 4}, "int64"):prod()
    check(product_result == 24, "prod int64 ignora NA = 24")
    local product_result_2 = smaug.Series({2, smaug.NA, 3}, "int64"):prod(false)
    check(product_result_2 == nil, "prod int64 ignore_na=false com NA = nil")

    -- prod(): float64 com NaN
    local nullable_floating_point_series = smaug.Series({2.0, 3.0, smaug.NA}, "float64")
    check(approximately_equal(nullable_floating_point_series:prod(true), 6.0), "prod float64 com NA ignorado (default) = 6")
    check(nullable_floating_point_series:prod(false) == nil, "prod float64 com NA e ignore_na=false → nil")

    -- median(): float64
    local median_result = smaug.Series({1.0, 2.0, 3.0, 4.0, 5.0}, "float64"):median()
    check(approximately_equal(median_result, 3.0), "median {1,2,3,4,5} = 3")

    -- quantile(): q=0.5 == median
    local quantile_result = smaug.Series({1.0, 2.0, 3.0, 4.0, 5.0}, "float64"):quantile(0.5)
    check(approximately_equal(quantile_result, 3.0), "quantile q=0.5 = median")

    -- mode(): primeiro em ordem de aparição em caso de empate
    local mode_result = smaug.Series({1, 2, 2, 3, 3}, "int64"):mode()
    check(mode_result == 2, "mode: empate → primeiro em aparição")
end

-- =====================================================================
-- 2 — describe() numérico
-- =====================================================================
do
    local floating_point_series = smaug.Series({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    local description = floating_point_series:describe()
    check(description.count == 5, "describe count = 5")
    check(approximately_equal(description.mean, 3.0), "describe mean = 3")
    check(approximately_equal(description.std, math.sqrt(2.5)), "describe std = sqrt(2.5) amostral")
    check(approximately_equal(description.min, 1.0), "describe min = 1")
    check(approximately_equal(description["25%"], 2.0), "describe 25% = 2")
    check(approximately_equal(description["50%"], 3.0), "describe 50% = 3")
    check(approximately_equal(description["75%"], 4.0), "describe 75% = 4")
    check(approximately_equal(description.max, 5.0), "describe max = 5")
end

-- =====================================================================
-- 3 — describe() bool (count_true, count_false)
-- =====================================================================
do
    local nullable_boolean_series = smaug.Series({true, false, true, smaug.NA, false}, "bool")
    local description = nullable_boolean_series:describe()
    check(description.count == 4, "describe bool count = 4 não-nulos")
    check(description.count_true == 2, "describe bool count_true = 2")
    check(description.count_false == 2, "describe bool count_false = 2")
    check(description.nulls == 1, "describe bool nulls = 1")
end

-- =====================================================================
-- 4 — describe() datetime (min/max formatados)
-- =====================================================================
do
    local datetime_series = smaug.Series({1609459200000, 1609545600000, 1609632000000}, "datetime")
    local description = datetime_series:describe()
    check(description.count == 3, "describe datetime count = 3")
    check(type(description.min) == "string", "describe datetime min = string formatada")
    check(type(description.max) == "string", "describe datetime max = string formatada")
    check(description.min:sub(1, 10) == "2021-01-01", "describe datetime min = 2021-01-01")
    check(description.max:sub(1, 10) == "2021-01-03", "describe datetime max = 2021-01-03")
end

-- =====================================================================
-- 5 — describe() string (unique, top, freq)
-- =====================================================================
do
    local nullable_string_series = smaug.Series({"a", "b", "a", "a", smaug.NA}, "string")
    local description = nullable_string_series:describe()
    check(description.count == 4, "describe string count = 4 não-nulos")
    check(description.unique == 2, "describe string unique = 2 (a,b)")
    check(description.top == "a", "describe string top = 'a'")
    check(description.freq == 3, "describe string freq = 3")
    check(description.nulls == 1, "describe string nulls = 1")
end

-- =====================================================================
-- 6 — rank() 4 métodos (average, min, max, first)
-- =====================================================================
do
    -- float64: rank average (default)
    local floating_point_series = smaug.Series({1.0, 2.0, 2.0, 3.0}, "float64")
    local ranked_series = floating_point_series:rank()
    check(approximately_equal(ranked_series:get(1), 1.0), "rank average [1] = 1")
    check(approximately_equal(ranked_series:get(2), 2.5), "rank average [2] = 2.5 (empate)")
    check(approximately_equal(ranked_series:get(3), 2.5), "rank average [3] = 2.5 (empate)")
    check(approximately_equal(ranked_series:get(4), 4.0), "rank average [4] = 4")

    -- rank min
    local ranked_series_2 = floating_point_series:rank("min")
    check(approximately_equal(ranked_series_2:get(2), 2.0), "rank min [2] = 2")
    check(approximately_equal(ranked_series_2:get(3), 2.0), "rank min [3] = 2")

    -- rank max
    local ranked_series_3 = floating_point_series:rank("max")
    check(approximately_equal(ranked_series_3:get(2), 3.0), "rank max [2] = 3")
    check(approximately_equal(ranked_series_3:get(3), 3.0), "rank max [3] = 3")

    -- rank first
    local ranked_series_4 = floating_point_series:rank("first")
    check(approximately_equal(ranked_series_4:get(2), 2.0), "rank first [2] = 2")
    check(approximately_equal(ranked_series_4:get(3), 3.0), "rank first [3] = 3")

    -- rank method inválido → erro
    check(rejects(function() floating_point_series:rank("invalido") end), "rank method inválido = erro")

    -- rank com nulls → NA no resultado
    local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 2.0}, "float64")
    local ranked_series_5 = nullable_floating_point_series:rank()
    check(approximately_equal(ranked_series_5:get(1), 1.0), "rank com null [1] = 1")
    check(ranked_series_5:get(2) == nil, "rank com null [2] = NA")
    check(approximately_equal(ranked_series_5:get(3), 2.0), "rank com null [3] = 2")

    -- rank int64
    local integer_series = smaug.Series({10, 20, 30}, "int64")
    local ranked_series_6 = integer_series:rank()
    check(approximately_equal(ranked_series_6:get(1), 1.0), "rank int64 [1] = 1")
    check(approximately_equal(ranked_series_6:get(3), 3.0), "rank int64 [3] = 3")

    -- rank string
    local string_series = smaug.Series({"a", "b", "c"}, "string")
    local ranked_series_7 = string_series:rank()
    check(approximately_equal(ranked_series_7:get(1), 1.0), "rank string [1] = 1")
    check(approximately_equal(ranked_series_7:get(3), 3.0), "rank string [3] = 3")

    -- rank datetime
    local datetime_series = smaug.Series({1609459200000, 1609545600000, 1609632000000}, "datetime")
    local ranked_series_8 = datetime_series:rank()
    check(approximately_equal(ranked_series_8:get(1), 1.0), "rank datetime [1] = 1")
    check(approximately_equal(ranked_series_8:get(3), 3.0), "rank datetime [3] = 3")

    -- rank bool
    local boolean_series = smaug.Series({false, true, false, true}, "bool")
    local ranked_series_9 = boolean_series:rank()
    check(approximately_equal(ranked_series_9:get(1), 1.5), "rank bool [1] = 1.5 (false empate)")
    check(approximately_equal(ranked_series_9:get(2), 3.5), "rank bool [2] = 3.5 (true empate)")

    -- rank série vazia → série vazia
    local empty_floating_point_series = smaug.Series({}, "float64")
    local ranked_series_10 = empty_floating_point_series:rank()
    check(ranked_series_10:len() == 0, "rank série vazia = série vazia")
end

-- =====================================================================
-- 7 — pct_rank() normalização [0, 1]
-- =====================================================================
do
    local floating_point_series = smaug.Series({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    local percentage_rank_result = floating_point_series:pct_rank()
    check(approximately_equal(percentage_rank_result:get(1), 0.0), "pct_rank [1] = 0.0")
    check(approximately_equal(percentage_rank_result:get(5), 1.0), "pct_rank [5] = 1.0")
    check(approximately_equal(percentage_rank_result:get(3), 0.5), "pct_rank [3] = 0.5")

    -- pct_rank com nulls
    local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 3.0}, "float64")
    local percentage_rank_result_2 = nullable_floating_point_series:pct_rank()
    check(approximately_equal(percentage_rank_result_2:get(1), 0.0), "pct_rank com null [1] = 0")
    check(percentage_rank_result_2:get(2) == nil, "pct_rank com null [2] = NA")
    check(approximately_equal(percentage_rank_result_2:get(3), 1.0), "pct_rank com null [3] = 1")

    -- pct_rank série vazia → série vazia
    local empty_floating_point_series = smaug.Series({}, "float64")
    local percentage_rank_result_3 = empty_floating_point_series:pct_rank()
    check(percentage_rank_result_3:len() == 0, "pct_rank série vazia = série vazia")

    -- pct_rank int64
    local integer_series = smaug.Series({10, 20, 30}, "int64")
    local percentage_rank_result_4 = integer_series:pct_rank()
    check(approximately_equal(percentage_rank_result_4:get(1), 0.0), "pct_rank int64 [1] = 0")
    check(approximately_equal(percentage_rank_result_4:get(3), 1.0), "pct_rank int64 [3] = 1")
end

-- =====================================================================
-- 8 — cov() e corr() bivariadas
-- =====================================================================
do
    local floating_point_series = smaug.Series({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    local floating_point_series_2 = smaug.Series({2.0, 4.0, 6.0, 8.0, 10.0}, "float64")

    -- cov: 5.0 amostral (n-1)
    local covariance_result = floating_point_series:cov(floating_point_series_2)
    check(approximately_equal(covariance_result, 5.0), "cov(a,b) = 5.0 amostral")

    -- corr: 1.0 (correlação perfeita)
    local correlation_result = floating_point_series:corr(floating_point_series_2)
    check(approximately_equal(correlation_result, 1.0), "corr(a,b) = 1.0 perfeita")

    -- corr com nulls (pares ignorados)
    local nullable_floating_point_series = smaug.Series({1.0, 2.0, smaug.NA, 4.0, 5.0}, "float64")
    local nullable_floating_point_series_2 = smaug.Series({2.0, smaug.NA, 6.0, 8.0, 10.0}, "float64")
    local correlation_result_2 = nullable_floating_point_series:corr(nullable_floating_point_series_2)
    -- pares válidos: (1,2) e (4,8), (5,10) → 3 pares, corr = 1.0
    check(approximately_equal(correlation_result_2, 1.0), "corr com nulls ignora pares")

    -- cov/corr com <2 pares → NaN
    local floating_point_series_3 = smaug.Series({1.0}, "float64")
    local floating_point_series_4 = smaug.Series({2.0}, "float64")
    local covariance_result_2 = floating_point_series_3:cov(floating_point_series_4)
    check(is_nan(covariance_result_2), "cov com 1 par = NaN")
    local correlation_result_3 = floating_point_series_3:corr(floating_point_series_4)
    check(is_nan(correlation_result_3), "corr com 1 par = NaN")

    -- cov/corr dtype não-numérico → erro
    local string_series = smaug.Series({"a", "b", "c"}, "string")
    check(rejects(function() floating_point_series:cov(string_series) end), "cov string = erro")
    check(rejects(function() floating_point_series:corr(string_series) end), "corr string = erro")
end

-- =====================================================================
-- 9 — autocorr()
-- =====================================================================
do
    local floating_point_series = smaug.Series({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")

    -- autocorr lag=1 (default)
    local autocorrelation_result = floating_point_series:autocorr()
    check(approximately_equal(autocorrelation_result, 1.0), "autocorr lag=1 série linear = 1.0")

    -- autocorr lag=2
    local autocorrelation_result_2 = floating_point_series:autocorr(2)
    check(approximately_equal(autocorrelation_result_2, 1.0), "autocorr lag=2 série linear = 1.0")

    -- autocorr série aleatória (valores conhecidos)
    local floating_point_series_2 = smaug.Series({2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0}, "float64")
    local autocorrelation_result_3 = floating_point_series_2:autocorr()
    check(autocorrelation_result_3 ~= nil and not is_nan(autocorrelation_result_3), "autocorr retorna valor válido")

    -- autocorr com nulls (shift propaga NA)
    local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 3.0, 4.0}, "float64")
    local autocorrelation_result_4 = nullable_floating_point_series:autocorr()
    check(autocorrelation_result_4 ~= nil, "autocorr com nulls retorna valor ou NaN")
end

-- =====================================================================
-- 10 — dot() produto interno
-- =====================================================================
do
    local floating_point_series = smaug.Series({1.0, 2.0, 3.0}, "float64")
    local floating_point_series_2 = smaug.Series({4.0, 5.0, 6.0}, "float64")

    -- dot: 1*4 + 2*5 + 3*6 = 32
    local dot_result = floating_point_series:dot(floating_point_series_2)
    check(approximately_equal(dot_result, 32.0), "dot {1,2,3}·{4,5,6} = 32")

    -- dot com nulls → nil (qualquer par com null)
    local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 3.0}, "float64")
    local dot_result_2 = floating_point_series:dot(nullable_floating_point_series)
    check(dot_result_2 == nil, "dot com null = nil")

    -- dot tamanhos diferentes → erro
    local floating_point_series_3 = smaug.Series({1.0, 2.0}, "float64")
    check(rejects(function() floating_point_series:dot(floating_point_series_3) end), "dot tamanhos diferentes = erro")

    -- dot dtype não-numérico → erro
    local string_series = smaug.Series({"a", "b", "c"}, "string")
    check(rejects(function() floating_point_series:dot(string_series) end), "dot string = erro")
end

-- =====================================================================
-- 11 — pct_change() variação percentual
-- =====================================================================
do
    local floating_point_series = smaug.Series({100.0, 110.0, 121.0}, "float64")

    -- pct_change periods=1 (default)
    local percentage_change_result = floating_point_series:pct_change()
    check(percentage_change_result:get(1) == nil, "pct_change [1] = NA (sem anterior)")
    check(approximately_equal(percentage_change_result:get(2), 0.1), "pct_change [2] = 0.1 (10%)")
    check(approximately_equal(percentage_change_result:get(3), 0.1), "pct_change [3] = 0.1 (10%)")

    -- pct_change periods=2
    local percentage_change_result_2 = floating_point_series:pct_change(2)
    check(percentage_change_result_2:get(1) == nil, "pct_change periods=2 [1] = NA")
    check(percentage_change_result_2:get(2) == nil, "pct_change periods=2 [2] = NA")
    check(approximately_equal(percentage_change_result_2:get(3), 0.21), "pct_change periods=2 [3] = 0.21 (21%)")

    -- pct_change divisor zero → NA
    local floating_point_series_2 = smaug.Series({0.0, 100.0}, "float64")
    local percentage_change_result_3 = floating_point_series_2:pct_change()
    check(percentage_change_result_3:get(2) == nil, "pct_change divisor zero = NA")

    -- pct_change com nulls
    local nullable_floating_point_series = smaug.Series({100.0, smaug.NA, 121.0}, "float64")
    local percentage_change_result_4 = nullable_floating_point_series:pct_change()
    check(percentage_change_result_4:get(2) == nil, "pct_change com null [2] = NA")
    check(percentage_change_result_4:get(3) == nil, "pct_change com null [3] = NA (anterior é NA)")
end

-- =====================================================================
-- 12 — skew() assimetria (n >= 3)
-- =====================================================================
do
    -- skew de {2,4,4,4,5,5,7,9} = 0.818... (valor conferido com scipy bias=False)
    local floating_point_series = smaug.Series({2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0}, "float64")
    local skewness_result = floating_point_series:skew()
    check(approximately_equal(skewness_result, 0.818, 0.001), "skew {2,4,4,4,5,5,7,9} = 0.818")

    -- skew n=3 (mínimo)
    local floating_point_series_2 = smaug.Series({1.0, 2.0, 3.0}, "float64")
    local skewness_result_2 = floating_point_series_2:skew()
    check(skewness_result_2 ~= nil and not is_nan(skewness_result_2), "skew n=3 retorna valor")

    -- skew n<3 → nil
    local floating_point_series_3 = smaug.Series({1.0, 2.0}, "float64")
    local skewness_result_3 = floating_point_series_3:skew()
    check(skewness_result_3 == nil, "skew n=2 = nil")

    local floating_point_series_4 = smaug.Series({1.0}, "float64")
    local skewness_result_4 = floating_point_series_4:skew()
    check(skewness_result_4 == nil, "skew n=1 = nil")

    local empty_floating_point_series = smaug.Series({}, "float64")
    local skewness_result_5 = empty_floating_point_series:skew()
    check(skewness_result_5 == nil, "skew série vazia = nil")

    -- skew com nulls (ignora)
    local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 2.0, 3.0, 4.0}, "float64")
    local skewness_result_6 = nullable_floating_point_series:skew()
    check(skewness_result_6 ~= nil and not is_nan(skewness_result_6), "skew com nulls ignora NA")

    -- skew int64
    local integer_series = smaug.Series({1, 2, 3, 4, 5}, "int64")
    local skewness_result_7 = integer_series:skew()
    check(skewness_result_7 ~= nil and not is_nan(skewness_result_7), "skew int64 retorna valor")

    -- skew dtype não-numérico → erro
    local string_series = smaug.Series({"a", "b", "c"}, "string")
    check(rejects(function() string_series:skew() end), "skew string = erro")

    local boolean_series = smaug.Series({true, false, true}, "bool")
    check(rejects(function() boolean_series:skew() end), "skew bool = erro (exceção registrada)")
end

-- =====================================================================
-- 13 — kurtosis() curtose (n >= 4)
-- =====================================================================
do
    -- kurtosis de {2,4,4,4,5,5,7,9} = 0.94... (excess kurtosis, bias=False como scipy)
    local floating_point_series = smaug.Series({2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0}, "float64")
    local kurtosis_result = floating_point_series:kurtosis()
    check(approximately_equal(kurtosis_result, 0.94, 0.01), "kurtosis {2,4,4,4,5,5,7,9} = 0.94")

    -- kurtosis n=4 (mínimo)
    local floating_point_series_2 = smaug.Series({1.0, 2.0, 3.0, 4.0}, "float64")
    local kurtosis_result_2 = floating_point_series_2:kurtosis()
    check(kurtosis_result_2 ~= nil and not is_nan(kurtosis_result_2), "kurtosis n=4 retorna valor")

    -- kurtosis n<4 → nil
    local floating_point_series_3 = smaug.Series({1.0, 2.0, 3.0}, "float64")
    local kurtosis_result_3 = floating_point_series_3:kurtosis()
    check(kurtosis_result_3 == nil, "kurtosis n=3 = nil")

    local floating_point_series_4 = smaug.Series({1.0, 2.0}, "float64")
    local kurtosis_result_4 = floating_point_series_4:kurtosis()
    check(kurtosis_result_4 == nil, "kurtosis n=2 = nil")

    local empty_floating_point_series = smaug.Series({}, "float64")
    local kurtosis_result_5 = empty_floating_point_series:kurtosis()
    check(kurtosis_result_5 == nil, "kurtosis série vazia = nil")

    -- kurtosis com nulls (ignora)
    local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 2.0, 3.0, 4.0, 5.0}, "float64")
    local kurtosis_result_6 = nullable_floating_point_series:kurtosis()
    check(kurtosis_result_6 ~= nil and not is_nan(kurtosis_result_6), "kurtosis com nulls ignora NA")

    -- kurtosis int64
    local integer_series = smaug.Series({1, 2, 3, 4, 5, 6}, "int64")
    local kurtosis_result_7 = integer_series:kurtosis()
    check(kurtosis_result_7 ~= nil and not is_nan(kurtosis_result_7), "kurtosis int64 retorna valor")

    -- kurtosis dtype não-numérico → erro
    local string_series = smaug.Series({"a", "b", "c", "d"}, "string")
    check(rejects(function() string_series:kurtosis() end), "kurtosis string = erro")
end

-- =====================================================================
-- 14 — mad() desvio absoluto mediano
-- =====================================================================
do
    -- mad de {1,2,3,4,5} = mediana({2,1,0,1,2}) = 1.0
    local floating_point_series = smaug.Series({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    local mean_absolute_deviation_result = floating_point_series:mad()
    check(approximately_equal(mean_absolute_deviation_result, 1.0), "mad {1,2,3,4,5} = 1.0")

    -- mad robusto a outliers
    local floating_point_series_2 = smaug.Series({1.0, 2.0, 3.0, 4.0, 100.0}, "float64")
    local mean_absolute_deviation_result_2 = floating_point_series_2:mad()
    check(approximately_equal(mean_absolute_deviation_result_2, 1.0), "mad robusto a outlier (100)")

    -- mad série vazia → nil
    local empty_floating_point_series = smaug.Series({}, "float64")
    local mean_absolute_deviation_result_3 = empty_floating_point_series:mad()
    check(mean_absolute_deviation_result_3 == nil, "mad série vazia = nil")

    -- mad com 1 elemento → 0 (desvio de si mesmo)
    local floating_point_series_3 = smaug.Series({5.0}, "float64")
    local mean_absolute_deviation_result_4 = floating_point_series_3:mad()
    check(approximately_equal(mean_absolute_deviation_result_4, 0.0), "mad 1 elemento = 0")

    -- mad com nulls (ignora)
    local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 3.0, 4.0, 5.0}, "float64")
    local mean_absolute_deviation_result_5 = nullable_floating_point_series:mad()
    check(approximately_equal(mean_absolute_deviation_result_5, 1.0), "mad com nulls ignora NA")

    -- mad int64
    local integer_series = smaug.Series({1, 2, 3, 4, 5}, "int64")
    local mean_absolute_deviation_result_6 = integer_series:mad()
    check(approximately_equal(mean_absolute_deviation_result_6, 1.0), "mad int64 = 1.0")

    -- mad dtype não-numérico → erro
    local string_series = smaug.Series({"a", "b", "c"}, "string")
    check(rejects(function() string_series:mad() end), "mad string = erro")
end

-- =====================================================================
-- 15 — sem() erro padrão da média (n >= 2)
-- =====================================================================
do
    -- sem de {1,2,3,4,5} = std/√n = sqrt(2.5)/√5 ≈ 0.707
    local floating_point_series = smaug.Series({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    local standard_error_result = floating_point_series:sem()
    check(approximately_equal(standard_error_result, 0.707, 0.001), "sem {1,2,3,4,5} = 0.707")

    -- sem n=2 (mínimo)
    local floating_point_series_2 = smaug.Series({1.0, 2.0}, "float64")
    local standard_error_result_2 = floating_point_series_2:sem()
    check(standard_error_result_2 ~= nil and not is_nan(standard_error_result_2), "sem n=2 retorna valor")

    -- sem n<2 → nil
    local floating_point_series_3 = smaug.Series({1.0}, "float64")
    local standard_error_result_3 = floating_point_series_3:sem()
    check(standard_error_result_3 == nil, "sem n=1 = nil")

    local empty_floating_point_series = smaug.Series({}, "float64")
    local standard_error_result_4 = empty_floating_point_series:sem()
    check(standard_error_result_4 == nil, "sem série vazia = nil")

    -- sem com nulls (ignora)
    local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 3.0, 4.0, 5.0}, "float64")
    local standard_error_result_5 = nullable_floating_point_series:sem()
    check(approximately_equal(standard_error_result_5, 0.854, 0.001), "sem com nulls ignora NA")

    -- sem int64
    local integer_series = smaug.Series({1, 2, 3, 4, 5}, "int64")
    local standard_error_result_6 = integer_series:sem()
    check(approximately_equal(standard_error_result_6, 0.707, 0.001), "sem int64 = 0.707")

    -- sem dtype não-numérico → erro
    local string_series = smaug.Series({"a", "b", "c"}, "string")
    check(rejects(function() string_series:sem() end), "sem string = erro")
end

-- =====================================================================
-- 16 — Casos de borda unificados
-- =====================================================================
do
    -- Série vazia
    local empty_floating_point_series = smaug.Series({}, "float64")
    check(empty_floating_point_series:rank():len() == 0, "rank série vazia = vazia")
    check(empty_floating_point_series:pct_rank():len() == 0, "pct_rank série vazia = vazia")
    check(empty_floating_point_series:skew() == nil, "skew série vazia = nil")
    check(empty_floating_point_series:kurtosis() == nil, "kurtosis série vazia = nil")
    check(empty_floating_point_series:mad() == nil, "mad série vazia = nil")
    check(empty_floating_point_series:sem() == nil, "sem série vazia = nil")

    -- Série toda null
    local all_null_floating_point_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64")
    check(all_null_floating_point_series:rank():get(1) == nil, "rank toda null = NA")
    check(all_null_floating_point_series:skew() == nil, "skew toda null = nil")
    check(all_null_floating_point_series:kurtosis() == nil, "kurtosis toda null = nil")
    check(all_null_floating_point_series:mad() == nil, "mad toda null = nil")
    check(all_null_floating_point_series:sem() == nil, "sem toda null = nil")

    -- Série com 1 elemento
    local floating_point_series = smaug.Series({5.0}, "float64")
    check(approximately_equal(floating_point_series:rank():get(1), 1.0), "rank 1 elemento = 1")
    check(approximately_equal(floating_point_series:pct_rank():get(1), 0.0), "pct_rank 1 elemento = 0")
    check(floating_point_series:skew() == nil, "skew 1 elemento = nil")
    check(floating_point_series:kurtosis() == nil, "kurtosis 1 elemento = nil")
    check(approximately_equal(floating_point_series:mad(), 0.0), "mad 1 elemento = 0")
    check(floating_point_series:sem() == nil, "sem 1 elemento = nil")
end

-- =====================================================================
-- FIM DOS TESTES
-- =====================================================================

print(string.format("OK — %d checks passaram (Series: estatísticas F.1 + avançadas + describe polimórfico)", passed_checks))
