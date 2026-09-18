-- tests/series/test_window.lua
-- Janela deslizante (rolling) e janela crescente (expanding).
-- Consolida: test_rolling_series.lua + seção rolling de test_enrich.lua
-- Rode da raiz: luajit tests/series/test_window.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local function approximately_equal(left_value, right_value, tolerance) tolerance = tolerance or 1e-9; return math.abs(left_value - right_value) < tolerance end
local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local function approximately_equal_2(left_value, right_value) return math.abs(left_value - right_value) < 1e-9 end

local integer_series = smaug.Series({1,2,3,4,5}, "int64")

-- ================================================================
-- sum
-- ================================================================
local sum_result = integer_series:rolling(3):sum()
check(sum_result:is_null(1),                  "sum(3): [1]=NA")
check(sum_result:is_null(2),                  "sum(3): [2]=NA")
check(sum_result:get(3) == 6,                 "sum(3): [3]=6")
check(sum_result:get(4) == 9,                 "sum(3): [4]=9")
check(sum_result:get(5) == 12,               "sum(3): [5]=12")
check(sum_result._dtype == "int64",           "sum: dtype int64")

-- window=1: sem NA
local sum_result_2 = integer_series:rolling(1):sum()
check(sum_result_2:get(1) == 1,                 "sum(1): sem NA, [1]=1")
check(sum_result_2:get(5) == 5,                 "sum(1): [5]=5")

-- window=n: só último não-NA
local sum_result_3 = integer_series:rolling(5):sum()
check(sum_result_3:is_null(4),                  "sum(n): [4]=NA")
check(sum_result_3:get(5) == 15,               "sum(n): [5]=15")

-- float64
local floating_point_series = smaug.Series({1.0,2.0,3.0}, "float64")
local sum_result_4 = floating_point_series:rolling(2):sum()
check(approximately_equal_2(sum_result_4:get(2), 3.0),        "sum float: [2]=3.0")
check(approximately_equal_2(sum_result_4:get(3), 5.0),        "sum float: [3]=5.0")

-- ================================================================
-- mean
-- ================================================================
local mean_result = integer_series:rolling(2):mean()
check(mean_result:is_null(1),                  "mean(2): [1]=NA")
check(approximately_equal_2(mean_result:get(2), 1.5),        "mean(2): [2]=1.5")
check(approximately_equal_2(mean_result:get(5), 4.5),        "mean(2): [5]=4.5")
check(mean_result._dtype == "float64",         "mean: dtype sempre float64")

-- ================================================================
-- min / max
-- ================================================================
local minimum_result = integer_series:rolling(2):min()
check(minimum_result:is_null(1),                  "min(2): [1]=NA")
check(minimum_result:get(2) == 1,                 "min(2): [2]=1")
check(minimum_result:get(5) == 4,                 "min(2): [5]=4")

local maximum_result = integer_series:rolling(2):max()
check(maximum_result:is_null(1),                  "max(2): [1]=NA")
check(maximum_result:get(2) == 2,                 "max(2): [2]=2")
check(maximum_result:get(5) == 5,                 "max(2): [5]=5")

-- ================================================================
-- NA dentro da janela: ignorado
-- ================================================================
local nullable_integer_series = smaug.Series({10, smaug.NA, 30, 40}, "int64")
local sum_result_5 = nullable_integer_series:rolling(2):sum()
check(sum_result_5:is_null(1),                   "NA na janela: [1]=NA")
check(sum_result_5:get(2) == 10,                 "NA na janela: [2]=10 (NA ignorado)")
check(sum_result_5:get(3) == 30,                 "NA na janela: [3]=30 (NA ignorado)")
check(sum_result_5:get(4) == 70,                 "NA na janela: [4]=70 (30+40)")

-- janela toda de NA: resultado NA
local nullable_integer_series_2 = smaug.Series({smaug.NA, smaug.NA, 30}, "int64")
local mean_result_2 = nullable_integer_series_2:rolling(2):mean()
check(mean_result_2:is_null(1),                  "janela NA: [1]=NA")
check(mean_result_2:is_null(2),                  "janela toda NA: [2]=NA")
check(approximately_equal_2(mean_result_2:get(3), 30.0),       "janela com 1 válido: [3]=30.0")

-- ================================================================
-- Série pequena (tamanho < window)
-- ================================================================
local integer_series_2 = smaug.Series({1,2}, "int64")
local sum_result_6 = integer_series_2:rolling(5):sum()
check(sum_result_6:len() == 2,                   "janela > len: tamanho preservado")
check(sum_result_6:is_null(1),                   "janela > len: [1]=NA")
check(sum_result_6:is_null(2),                   "janela > len: [2]=NA")

-- ================================================================
-- Série vazia
-- ================================================================
local empty_integer_series = smaug.Series({}, "int64")
local sum_result_7 = empty_integer_series:rolling(3):sum()
check(sum_result_7:len() == 0,                   "série vazia: len=0")

-- ================================================================
-- Erros
-- ================================================================
local succeeded, unused_error = pcall(function() integer_series:rolling(0) end)
check(not succeeded,                         "erro: window=0")
local succeeded_2, unused_error_2 = pcall(function() integer_series:rolling(1.5) end)
check(not succeeded_2,                         "erro: window fracionário")
local succeeded_3, unused_error_3 = pcall(function() integer_series:rolling(-1) end)
check(not succeeded_3,                         "erro: window negativo")

-- dtype inválido
local string_series = smaug.Series({"a","b"}, "string")
local succeeded_4, unused_error_4 = pcall(function() string_series:rolling(2) end)
check(not succeeded_4,                         "erro: rolling em string")

-- =====================================================================
-- Rolling estendido e expanding (de test_enrich.lua)
-- =====================================================================

-- Rolling estendido
-- ================================================================

local floating_point_series_2 = smaug.Series({1.0,2.0,3.0,4.0,5.0}, "float64")

-- std / var
local standard_deviation_result = floating_point_series_2:rolling(3):std()
check(standard_deviation_result:is_null(1),             "rolling std[1]=NA")
check(standard_deviation_result:is_null(2),             "rolling std[2]=NA")
check(approximately_equal_2(standard_deviation_result:get(3), 1.0),   "rolling std[3]=1.0")

local variance_result = floating_point_series_2:rolling(3):var()
check(variance_result:is_null(1),             "rolling var[1]=NA")
check(approximately_equal_2(variance_result:get(3), 1.0),   "rolling var[3]=1.0")

-- count
local rolling_counts = smaug.Series({1.0,smaug.NA,3.0,smaug.NA,5.0}, "float64"):rolling(3):count()
check(rolling_counts:is_null(1),              "rolling count[1]=NA (janela incompleta)")
check(rolling_counts:is_null(2),              "rolling count[2]=NA")
check(rolling_counts:get(3) == 2,             "rolling count[3]=2 ({1,NA,3}→2 não-nulos)")
check(rolling_counts:get(4) == 1,             "rolling count[4]=1 ({NA,3,NA}→1)")

-- median
local median_result = floating_point_series_2:rolling(3):median()
check(median_result:is_null(1),            "rolling median[1]=NA")
check(approximately_equal_2(median_result:get(3), 2.0),  "rolling median[3]=2.0")
check(approximately_equal_2(median_result:get(5), 4.0),  "rolling median[5]=4.0")

-- quantile
local quantile_result = floating_point_series_2:rolling(3):quantile(0.0)
check(quantile_result:is_null(1),              "rolling q0[1]=NA")
check(approximately_equal_2(quantile_result:get(3), 1.0),    "rolling q0[3]=1.0 (min da janela)")

-- min_periods
local standard_deviation_result_2 = floating_point_series_2:rolling(3):min_periods(2):std()
check(standard_deviation_result_2:is_null(1),             "rolling mp std[1]=NA (1 val < mp=2)")
check(approximately_equal_2(standard_deviation_result_2:get(2), 0.7071067811865476, 1e-9), "rolling mp std[2]=sqrt(0.5)")
check(approximately_equal_2(standard_deviation_result_2:get(3), 1.0),   "rolling mp std[3]=1.0")

-- item 8a: min_periods aplicado a sum/min/max (REGRESSÃO do bug histórico —
-- o caminho C ignorava min_periods; agora respeita). rs = {1,2,3,4,5}
local sum_result_8 = floating_point_series_2:rolling(3):min_periods(1):sum()
check(approximately_equal_2(sum_result_8:get(1), 1.0),  "8a sum mp1[1]=1 (parcial; ANTES era NA)")
check(approximately_equal_2(sum_result_8:get(2), 3.0),  "8a sum mp1[2]=3 (parcial)")
check(approximately_equal_2(sum_result_8:get(3), 6.0),  "8a sum mp1[3]=6 (janela cheia)")
local bsum2 = floating_point_series_2:rolling(3):min_periods(2):sum()
check(bsum2:is_null(1),          "8a sum mp2[1]=NA (1 val < mp=2)")
check(approximately_equal_2(bsum2:get(2), 3.0), "8a sum mp2[2]=3")
-- min/max com min_periods → rescan type-preserving
local minimum_result_2 = floating_point_series_2:rolling(3):min_periods(1):min()
check(approximately_equal_2(minimum_result_2:get(1), 1.0),  "8a min mp1[1]=1 (rescan parcial)")
check(approximately_equal_2(minimum_result_2:get(5), 3.0),  "8a min mp1[5]=3 ({3,4,5})")
local maximum_result_2 = floating_point_series_2:rolling(3):min_periods(1):max()
check(approximately_equal_2(maximum_result_2:get(1), 1.0),  "8a max mp1[1]=1")
check(approximately_equal_2(maximum_result_2:get(2), 2.0),  "8a max mp1[2]=2 (parcial {1,2})")
-- mean com min_periods (caminho motor)
local bmean = floating_point_series_2:rolling(3):min_periods(1):mean()
check(approximately_equal_2(bmean:get(1), 1.0), "8a mean mp1[1]=1")
check(approximately_equal_2(bmean:get(2), 1.5), "8a mean mp1[2]=1.5")
-- i64 min_periods preserva tipo no rescan
local maximum_result_3 = smaug.Series({10,20,30,40}, "int64"):rolling(2):min_periods(1):max()
check(maximum_result_3:get(1) == 10,           "8a i64 max mp1[1]=10")
check(maximum_result_3:get(4) == 40,           "8a i64 max mp1[4]=40")
-- default (min_periods=0) inalterado: janela-cheia
local sum_result_9 = floating_point_series_2:rolling(3):sum()
check(sum_result_9:is_null(1) and sum_result_9:is_null(2), "8a sum default[1,2]=NA (janela-cheia preservada)")
check(approximately_equal_2(sum_result_9:get(3), 6.0),  "8a sum default[3]=6")

-- expanding
local expanding_float_series = smaug.Series({1.0,2.0,3.0,4.0}, "float64")
local sum_result_10 = expanding_float_series:expanding():sum()
check(sum_result_10:get(1) == 1, "expanding sum[1]=1")
check(sum_result_10:get(2) == 3, "expanding sum[2]=3")
check(sum_result_10:get(4) == 10,"expanding sum[4]=10")

local mean_result_3 = expanding_float_series:expanding():mean()
check(approximately_equal_2(mean_result_3:get(2), 1.5),  "expanding mean[2]=1.5")
check(approximately_equal_2(mean_result_3:get(4), 2.5),  "expanding mean[4]=2.5")

local standard_deviation_result_3 = expanding_float_series:expanding():std()
check(standard_deviation_result_3:is_null(1),         "expanding std[1]=nil (n<2)")
check(approximately_equal_2(standard_deviation_result_3:get(2), 0.7071067811865476, 1e-9), "expanding std[2]")

local median_result_2 = expanding_float_series:expanding():median()
check(approximately_equal_2(median_result_2:get(2), 1.5), "expanding median[2]=1.5")

-- item 8b: expanding delega a rolling(n, min_periods>=1). Tipos coerentes
-- com rolling: sum→dtype, mean/std/var→float64, count→int64 (correção: o
-- expanding antigo retornava col._dtype p/ tudo, truncando mean de i64).
local expanding_integer_series = smaug.Series({10,20,30}, "int64")
check(expanding_integer_series:expanding():sum():dtype()   == "int64",   "8b expanding sum i64→int64")
check(expanding_integer_series:expanding():mean():dtype()  == "float64", "8b expanding mean i64→float64 (corrigido)")
check(expanding_integer_series:expanding():count():dtype() == "int64",   "8b expanding count→int64")
check(expanding_integer_series:expanding():std():dtype()   == "float64", "8b expanding std→float64")
check(approximately_equal_2(expanding_integer_series:expanding():mean():get(2), 15.0),  "8b expanding mean i64 não trunca (10,20→15)")
-- expanding com min_periods explícito
local sum_result_11 = expanding_float_series:expanding(2):sum()
check(sum_result_11:is_null(1),          "8b expanding(mp=2) sum[1]=NA")
check(approximately_equal_2(sum_result_11:get(2), 3.0), "8b expanding(mp=2) sum[2]=3")
-- expanding count acumula não-nulos
local count_result = smaug.Series({1.0, smaug.NA, 3.0}, "float64"):expanding():count()
check(count_result:get(1) == 1 and count_result:get(2) == 1 and count_result:get(3) == 2, "8b expanding count acumula não-nulos")

-- ===================================================================
-- ffill/bfill agnósticos a tipo (item 7.1): bool, string, datetime
-- delegam ao C; antes só numéricos tinham C, o resto era fallback Lua.
-- ===================================================================

-- bool
local nullable_boolean_series  = smaug.Series({true, smaug.NA, smaug.NA, false, smaug.NA}, "bool")
local forward_fill_result = nullable_boolean_series:ffill()
check(forward_fill_result:get(1) == true  and forward_fill_result:get(3) == true,  "bool ffill: carry true")
check(forward_fill_result:get(4) == false and forward_fill_result:get(5) == false, "bool ffill: carry false")
local backward_fill_result = nullable_boolean_series:bfill()
check(backward_fill_result:get(2) == false and backward_fill_result:get(1) == true,  "bool bfill: carry")
check(backward_fill_result:is_null(5),                              "bool bfill: borda final NA")

-- string (com vazia válida e multibyte)
local nullable_string_series  = smaug.Series({"a", smaug.NA, "", smaug.NA, "héllo"}, "string")
local forward_fill_result_2 = nullable_string_series:ffill()
check(forward_fill_result_2:get(2) == "a",      "str ffill: [2]=a (carry)")
check(forward_fill_result_2:get(3) == "",       "str ffill: [3]= (vazia válida)")
check(forward_fill_result_2:get(4) == "",       "str ffill: [4]= (carry vazia)")
check(forward_fill_result_2:get(5) == "héllo",  "str ffill: [5]=héllo (multibyte)")
local backward_fill_result_2 = nullable_string_series:bfill()
check(backward_fill_result_2:get(1) == "a",      "str bfill: [1]=a")
check(backward_fill_result_2:get(2) == "",       "str bfill: [2]= (carry vazia seguinte)")
check(backward_fill_result_2:get(4) == "héllo",  "str bfill: [4]=héllo")
-- bordas sem fonte permanecem NA
local nullable_string_series_2 = smaug.Series({smaug.NA, "x", smaug.NA}, "string")
check(nullable_string_series_2:ffill():is_null(1), "str ffill: borda inicial NA")
check(nullable_string_series_2:bfill():is_null(3), "str bfill: borda final NA")

-- datetime
local nullable_datetime_series  = smaug.Series({"2020-01-01", smaug.NA, smaug.NA, "2020-06-15"}, "datetime")
local forward_fill_result_3 = nullable_datetime_series:ffill()
check(forward_fill_result_3:count_nonnull() == 4,        "dt ffill: preenche 4")
check(forward_fill_result_3:get(2) == forward_fill_result_3:get(1),        "dt ffill: [2] carrega [1]")
local backward_fill_result_3 = nullable_datetime_series:bfill()
check(backward_fill_result_3:get(3) == backward_fill_result_3:get(4),        "dt bfill: [3] carrega [4]")

-- int64 > 2^53: ffill/bfill carregam o valor EXATO (cópia C direta de int64_t,
-- sem round-trip por get()). Fecha a prova da família null-mask/seleção (10.6).
do
    local ffi = require("ffi")
    local large_integer = ffi.new("int64_t", 9007199254740993LL)  -- 2^53+1
    local allocated_integer_series  = smaug.Series({smaug.NA, smaug.NA, smaug.NA, smaug.NA}, "int64", "big")
    allocated_integer_series:set(1, large_integer); allocated_integer_series:set_null(2); allocated_integer_series:set_null(3); allocated_integer_series:set(4, 5LL)
    local forward_fill_result_4 = allocated_integer_series:ffill()   -- [BIG, BIG, BIG, 5]
    check(tostring(forward_fill_result_4:get_raw(1)) == tostring(large_integer), "i64 ffill: [1] 2^53+1 exato")
    check(tostring(forward_fill_result_4:get_raw(2)) == tostring(large_integer), "i64 ffill: [2] carrega 2^53+1 exato")
    check(tostring(forward_fill_result_4:get_raw(3)) == tostring(large_integer), "i64 ffill: [3] carrega 2^53+1 exato")
    check(forward_fill_result_4:get(4) == 5,                            "i64 ffill: [4] mantém 5")
    local backward_fill_result_4 = allocated_integer_series:bfill()   -- [BIG, 5, 5, 5]
    check(tostring(backward_fill_result_4:get_raw(1)) == tostring(large_integer), "i64 bfill: [1] 2^53+1 exato mantido")
    check(backward_fill_result_4:get(2) == 5 and backward_fill_result_4:get(3) == 5,        "i64 bfill: [2]/[3] carregam 5")
end

-- série toda nula permanece toda nula
local all_null_string_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "string")
check(all_null_string_series:ffill():count_nonnull() == 0, "str ffill all-null: 0 válidos")
check(all_null_string_series:bfill():count_nonnull() == 0, "str bfill all-null: 0 válidos")

-- ===================================================================
-- shift com sinal (item 7.1b): negativo agora vem do C (antes era Lua,
-- e sem cobertura em lugar nenhum). Testa os dois sentidos em todos os dtypes.
-- ===================================================================

-- f64 positivo e negativo
local floating_point_series_3 = smaug.Series({1.0, 2.0, 3.0, 4.0}, "float64")
local shift_result = floating_point_series_3:shift(1)   -- [NA,1,2,3]
check(shift_result:is_null(1) and shift_result:get(2) == 1 and shift_result:get(4) == 3, "f64 shift(1)")
local shift_result_2 = floating_point_series_3:shift(-1)  -- [2,3,4,NA]
check(shift_result_2:get(1) == 2 and shift_result_2:get(3) == 4 and shift_result_2:is_null(4), "f64 shift(-1)")
check(floating_point_series_3:shift(0):get(1) == 1 and floating_point_series_3:shift(0):get(4) == 4,    "f64 shift(0)=clone")
check(floating_point_series_3:shift(10):count_nonnull() == 0,                      "f64 shift(>=size)=all-NA")
check(floating_point_series_3:shift(-10):count_nonnull() == 0,                     "f64 shift(<=-size)=all-NA")

-- f64 com NA preservado no deslocamento
local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 3.0}, "float64")
check(nullable_floating_point_series:shift(-1):is_null(1) and nullable_floating_point_series:shift(-1):get(2) == 3, "f64 shift(-1) preserva NA")

-- i64 negativo
local integer_series_3 = smaug.Series({10, 20, 30}, "int64")
check(integer_series_3:shift(-1):get(1) == 20 and integer_series_3:shift(-1):is_null(3), "i64 shift(-1)")

-- string negativo (offset-based)
local string_series_2 = smaug.Series({"a", "b", "c", "d"}, "string")
local shift_result_3 = string_series_2:shift(-2)  -- [c,d,NA,NA]
check(shift_result_3:get(1) == "c" and shift_result_3:get(2) == "d", "str shift(-2): valores")
check(shift_result_3:is_null(3) and shift_result_3:is_null(4),       "str shift(-2): bordas NA")
local shift_result_4 = string_series_2:shift(2)   -- [NA,NA,a,b]
check(shift_result_4:is_null(1) and shift_result_4:get(3) == "a" and shift_result_4:get(4) == "b", "str shift(2)")

-- bool negativo
local boolean_series = smaug.Series({true, false, true}, "bool")
local shift_result_5 = boolean_series:shift(-1)  -- [false,true,NA]
check(shift_result_5:get(1) == false and shift_result_5:get(2) == true and shift_result_5:is_null(3), "bool shift(-1)")

-- datetime negativo
local datetime_series = smaug.Series({"2020-01-01", "2020-02-01", "2020-03-01"}, "datetime")
local shift_result_6 = datetime_series:shift(-1)
check(shift_result_6:count_nonnull() == 2 and shift_result_6:get(1) == datetime_series:get(2), "dt shift(-1)")

-- validação de entrada mantida
check(not pcall(function() return floating_point_series_3:shift(1.5) end), "shift(1.5) erra (não-inteiro)")

-- ===================================================================
-- 7.2a — argmin/argmax em str e bool: o gate na Lua é por CAPACIDADE
-- (self._d.argmin), não por dtype. O Anel 0 já tinha smaug_str_argmin e
-- smaug_bool_argmin (testados em test_ops_window) e o descritor já os ligava,
-- mas um guard por dtype barrava str/bool antes do gate — capacidade morta.
-- Nenhum teste Lua exercitava esses dtypes, por isso a suíte ficava verde.
local fruit_names_series = smaug.Series({"banana", "abacaxi", "caju"})
check(fruit_names_series:argmin() == 2, "7.2a str argmin = 2 (abacaxi, lexicográfico, 1-based)")
check(fruit_names_series:argmax() == 3, "7.2a str argmax = 3 (caju)")
check(fruit_names_series:min() == fruit_names_series:get(fruit_names_series:argmin()), "7.2a str min == get(argmin)")
check(fruit_names_series:max() == fruit_names_series:get(fruit_names_series:argmax()), "7.2a str max == get(argmax)")

-- str: vazia é a menor; prefixo mais curto vem antes
local nullable_string_series_3 = smaug.Series({"z", smaug.NA, "", "m"})
check(nullable_string_series_3:argmin() == 3, "7.2a str argmin ignora NA e acha a vazia")
check(nullable_string_series_3:argmax() == 1, "7.2a str argmax = 1 (z)")
check(smaug.Series({"abc", "ab"}):argmin() == 2, "7.2a str prefixo: 'ab' < 'abc'")

-- bool: false < true
local boolean_series_2 = smaug.Series({true, false, true})
check(boolean_series_2:argmin() == 2, "7.2a bool argmin = 2 (false < true)")
check(boolean_series_2:argmax() == 1, "7.2a bool argmax = 1 (true)")

-- aliases idxmin/idxmax herdam o comportamento
check(fruit_names_series:idxmin() == fruit_names_series:argmin(), "7.2a str idxmin == argmin")
check(boolean_series_2:idxmax() == boolean_series_2:argmax(), "7.2a bool idxmax == argmax")

-- bordas: toda-NA e vazia → nil (SIZE_MAX do C traduzido)
check(smaug.Series({smaug.NA, smaug.NA}, "string"):argmin() == nil, "7.2a str toda-NA = nil")
check(smaug.Series({}, "string"):argmin() == nil,        "7.2a str vazia = nil")
check(smaug.Series({smaug.NA, smaug.NA}, "bool"):argmax() == nil,    "7.2a bool toda-NA = nil")

print(string.format("OK — %d checks passaram (Series: rolling, expanding, cumsum, cummin, cummax, diff, shift, ffill, bfill, argmin, argmax)", passed_checks))
