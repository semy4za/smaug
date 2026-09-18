-- tests/props/test_integration.lua
-- Fluxos completos integrando Series + DataSet com dados reais e cenários
-- de ponta a ponta. Absorve: reduções avançadas de test_enrich.lua (prod,
-- median, quantile, mode, rank, skew, kurtosis, mad, sem, nlargest, funções matemáticas).
-- Rode da raiz: luajit tests/props/test_integration.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local function approximately_equal(left_value, right_value, tolerance) tolerance = tolerance or 1e-9; return math.abs(left_value - right_value) < tolerance end
local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

-- ================================================================
-- Series — reduções novas
-- ================================================================

local floating_point_series = smaug.Series({3,1,4,1,5,9,2,6}, "float64")
local integer_series = smaug.Series({3,1,4,1,5,9,2,6}, "int64")

-- prod
check(floating_point_series:prod() == 6480,      "prod: 3*1*4*1*5*9*2*6=6480")
check(integer_series:prod() == 6480,     "prod i64: 6480")
local nullable_floating_point_series = smaug.Series({2, smaug.NA, 3}, "float64")
check(nullable_floating_point_series:prod() == 6,       "prod ignore_na: 2*3=6")
check(nullable_floating_point_series:prod(false) == nil,"prod !ignore_na com NA: nil")

-- median
check(floating_point_series:median() == 3.5,     "median: (3+4)/2=3.5")
check(smaug.Series({5}, "float64"):median() == 5, "median 1 elem: 5")
check(nullable_floating_point_series:median() == 2.5,   "median ignore_na: (2+3)/2=2.5")

-- quantile
check(approximately_equal(floating_point_series:quantile(0.0), 1),   "q0=min=1")
check(approximately_equal(floating_point_series:quantile(1.0), 9),   "q1=max=9")
check(approximately_equal(floating_point_series:quantile(0.5), 3.5), "q0.5=median=3.5")
check(approximately_equal(floating_point_series:quantile(0.25), 1.75),"q0.25=1.75")

-- mode
check(smaug.Series({1,2,1,3}, "int64"):mode() == 1, "mode: 1")
check(smaug.Series({5,5,5},   "float64"):mode() == 5,"mode único: 5")

-- ffill
local nullable_floating_point_series_2 = smaug.Series({1.0, smaug.NA, smaug.NA, 4.0, smaug.NA}, "float64")
local forward_fill_result = nullable_floating_point_series_2:ffill()
check(forward_fill_result:get(1) == 1.0,   "ffill[1]=1.0")
check(forward_fill_result:get(2) == 1.0,   "ffill[2]=1.0 (propagado)")
check(forward_fill_result:get(3) == 1.0,   "ffill[3]=1.0")
check(forward_fill_result:get(4) == 4.0,   "ffill[4]=4.0")
check(forward_fill_result:get(5) == 4.0,   "ffill[5]=4.0")
-- NA no início: permanece NA
local nullable_floating_point_series_3 = smaug.Series({smaug.NA, smaug.NA, 3.0}, "float64")
local forward_fill_result_2 = nullable_floating_point_series_3:ffill()
check(forward_fill_result_2:is_null(1),     "ffill NA início[1]=NA")
check(forward_fill_result_2:is_null(2),     "ffill NA início[2]=NA")
check(forward_fill_result_2:get(3) == 3.0,  "ffill[3]=3.0")

-- bfill
local backward_fill_result = nullable_floating_point_series_2:bfill()
check(backward_fill_result:get(1) == 1.0,   "bfill[1]=1.0")
check(backward_fill_result:get(2) == 4.0,   "bfill[2]=4.0 (propagado para trás)")
check(backward_fill_result:get(5) == nil,   "bfill[5]=NA (sem próximo)")

-- cummin
local cumulative_minimum_result = floating_point_series:cummin()
check(cumulative_minimum_result:get(1) == 3,     "cummin[1]=3")
check(cumulative_minimum_result:get(2) == 1,     "cummin[2]=1")
check(cumulative_minimum_result:get(8) == 1,     "cummin[8]=1")
-- NA propaga
local nullable_floating_point_series_4 = smaug.Series({5.0, smaug.NA, 2.0}, "float64")
check(nullable_floating_point_series_4:cummin():is_null(2),   "cummin NA propaga[2]")
check(nullable_floating_point_series_4:cummin():get(3) == 2.0,"cummin após NA[3]=2.0")

-- cummax
local cumulative_maximum_result = floating_point_series:cummax()
check(cumulative_maximum_result:get(1) == 3,     "cummax[1]=3")
check(cumulative_maximum_result:get(3) == 4,     "cummax[3]=4")
check(cumulative_maximum_result:get(6) == 9,     "cummax[6]=9")
check(cumulative_maximum_result:get(8) == 9,     "cummax[8]=9")

-- argmin / argmax
check(floating_point_series:argmin() == 2,    "argmin: idx=2 (val=1)")
check(floating_point_series:argmax() == 6,    "argmax: idx=6 (val=9)")
check(smaug.Series({smaug.NA,smaug.NA}, "float64"):argmin() == nil, "argmin all NA: nil")

-- rank
local ranked_series = smaug.Series({3,1,4,1,5}, "float64"):rank()
check(approximately_equal(ranked_series:get(1), 3.0), "rank[1]=3")
check(approximately_equal(ranked_series:get(2), 1.5), "rank[2]=1.5 (empate avg)")
check(approximately_equal(ranked_series:get(4), 1.5), "rank[4]=1.5")
check(approximately_equal(ranked_series:get(5), 5.0), "rank[5]=5")
-- rank com NA → NA
local ranked_series_2 = smaug.Series({3.0, smaug.NA, 1.0}, "float64"):rank()
check(ranked_series_2:is_null(2),         "rank NA → NA")
check(approximately_equal(ranked_series_2:get(1), 2), "rank[1]=2")

-- pct_rank: fórmula (rank-1)/(n-1) — min→0, max→1 (ver series/test_stat.lua
-- seção 7 para a bateria completa, incluindo os casos de borda n=0/n=1)
local percentage_rank_result = smaug.Series({1.0,2.0,3.0,4.0}, "float64"):pct_rank()
check(approximately_equal(percentage_rank_result:get(1), 0.0), "pct_rank[1]=0.0")
check(approximately_equal(percentage_rank_result:get(4), 1.0),  "pct_rank[4]=1.0")

-- rank em dtypes ordenáveis não-numéricos (item 7.3): str/dt/bool delegam ao C
-- string lexicográfico, com empate
local ranked_series_3 = smaug.Series({"banana","abacaxi","caju","abacaxi"}, "string"):rank()
check(approximately_equal(ranked_series_3:get(1), 3.0), "7.3 str rank banana=3")
check(approximately_equal(ranked_series_3:get(2), 1.5), "7.3 str rank abacaxi=1.5 (empate)")
check(approximately_equal(ranked_series_3:get(3), 4.0), "7.3 str rank caju=4")
check(approximately_equal(ranked_series_3:get(4), 1.5), "7.3 str rank abacaxi=1.5")
-- string method first
local ranked_series_4 = smaug.Series({"b","a","a"}, "string"):rank("first")
check(approximately_equal(ranked_series_4:get(2), 1.0) and approximately_equal(ranked_series_4:get(3), 2.0), "7.3 str rank first empate")
-- string com NA
local ranked_series_5 = smaug.Series({"b", smaug.NA, "a"}, "string"):rank()
check(ranked_series_5:is_null(2) and approximately_equal(ranked_series_5:get(3), 1.0), "7.3 str rank NA preservado")

-- datetime cronológico
local ranked_series_6 = smaug.Series({"2020-03-01","2020-01-01","2020-06-15","2020-01-01"}, "datetime"):rank()
check(approximately_equal(ranked_series_6:get(2), 1.5) and approximately_equal(ranked_series_6:get(4), 1.5), "7.3 dt rank empate cronológico")
check(approximately_equal(ranked_series_6:get(1), 3.0) and approximately_equal(ranked_series_6:get(3), 4.0), "7.3 dt rank ordem")

-- bool: false<true
local ranked_series_7 = smaug.Series({true,false,true,false}, "bool"):rank()
check(approximately_equal(ranked_series_7:get(2), 1.5) and approximately_equal(ranked_series_7:get(1), 3.5), "7.3 bool rank avg")
local ranked_series_8 = smaug.Series({true,false,true,false}, "bool"):rank("min")
check(approximately_equal(ranked_series_8:get(2), 1.0) and approximately_equal(ranked_series_8:get(1), 3.0), "7.3 bool rank min")

-- método inválido erra; dtype sem rank (categorical) erra
check(not pcall(function() return smaug.Series({1.0}, "float64"):rank("xyz") end), "7.3 rank método inválido erra")
check(not pcall(function() return smaug.Series({"x"}, "string"):astype("categorical"):rank() end), "7.3 categorical rank erra")

-- skew / kurtosis / mad / sem
local floating_point_series_2 = smaug.Series({2,4,4,4,5,5,7,9}, "float64")
check(approximately_equal(floating_point_series_2:mad(), 0.5, 1e-9), "mad: 0.5")
check(floating_point_series_2:sem() ~= nil,              "sem: não nil")
check(floating_point_series_2:skew() ~= nil,             "skew: não nil")
check(floating_point_series_2:kurtosis() ~= nil,         "kurtosis: não nil")
-- série pequena demais
check(smaug.Series({1.0,2.0}, "float64"):skew() == nil, "skew n<3: nil")
check(smaug.Series({1.0,2.0,3.0}, "float64"):kurtosis() == nil, "kurtosis n<4: nil")

-- nlargest / nsmallest
local largest_result = floating_point_series:nlargest(3)
check(largest_result:len() == 3,   "nlargest len=3")
check(largest_result:get(1) == 9,  "nlargest[1]=9")
check(largest_result:get(2) == 6,  "nlargest[2]=6")
check(largest_result:get(3) == 5,  "nlargest[3]=5")
local smallest_result = floating_point_series:nsmallest(3)
check(smallest_result:get(1) == 1,  "nsmallest[1]=1")
check(smallest_result:get(3) == 2,  "nsmallest[3]=2")

-- sin / cos / exp / log / sqrt
local floating_point_series_3 = smaug.Series({0.0, math.pi/2}, "float64")
check(approximately_equal(floating_point_series_3:sin():get(1), 0.0),   "sin(0)=0")
check(approximately_equal(floating_point_series_3:sin():get(2), 1.0),   "sin(π/2)=1")
check(approximately_equal(floating_point_series_3:cos():get(1), 1.0),   "cos(0)=1")
local floating_point_series_4 = smaug.Series({0.0, 1.0}, "float64")
check(approximately_equal(floating_point_series_4:exp():get(1), 1.0),   "exp(0)=1")
check(approximately_equal(floating_point_series_4:exp():get(2), math.exp(1)), "exp(1)=e")
check(approximately_equal(floating_point_series_4:log():get(2), 0.0),   "log(1)=0")
local floating_point_series_5 = smaug.Series({4.0, 9.0}, "float64")
check(floating_point_series_5:sqrt():get(1) == 2.0,        "sqrt(4)=2")
check(floating_point_series_5:sqrt():get(2) == 3.0,        "sqrt(9)=3")
-- nulos propagam
local smath = smaug.Series({4.0, smaug.NA}, "float64")
check(smath:sqrt():get(1) == 2.0,     "sqrt propaga não-nulo")
check(smath:sqrt():is_null(2),         "sqrt propaga NA")

-- 10.3 fatia A: as seis desceram ao Anel 0.
-- Entrada int64 não tem versão própria em C (Opção 1): o frontend encadeia
-- astype("float64") e chama a versão f64. A saída é float64 nos dois casos.
local integer_series_2 = smaug.Series({0, 1, 4}, "int64")
check(integer_series_2:sqrt():get(3) == 2.0,          "10.3 sqrt aceita int64 (via astype)")
check(integer_series_2:sqrt()._dtype == "float64",    "10.3 saída é float64 mesmo com entrada int64")
check(approximately_equal(integer_series_2:exp():get(1), 1.0),     "10.3 exp de int64")
check(integer_series_2:sqrt():len() == 3,             "10.3 tamanho preservado")

-- domínio inválido → NaN como VALOR presente (Contrato 9), não nulo nem erro
local floating_point_series_6 = smaug.Series({-4.0}, "float64")
check(floating_point_series_6:sqrt():get(1) ~= floating_point_series_6:sqrt():get(1), "10.3 sqrt(-4) = NaN")
check(not floating_point_series_6:sqrt():is_null(1),       "10.3 NaN tem máscara válida, não é nulo")
check(floating_point_series_6:log():get(1) ~= floating_point_series_6:log():get(1),   "10.3 log(-4) = NaN")

-- tan não era exercitada antes; cada função da macro é um corpo próprio
check(approximately_equal(smaug.Series({0.0}, "float64"):tan():get(1), 0.0), "10.3 tan(0)=0")

-- dtype não numérico recusado nas seis
for unused_index, callback in ipairs({"sin","cos","tan","exp","log","sqrt"}) do
    local string_series = smaug.Series({"a"}, "string")
    check(not pcall(function() return string_series[callback](string_series) end),
          "10.3 " .. callback .. "() recusa dtype não numérico")
end

print(string.format("OK — %d checks passaram (integração: reduções avançadas, rank, skew, kurtosis, mad, sem, funções matemáticas)", passed_checks))
