-- tests/series/test_selection.lua
-- Seleção condicional (where/mask/ifelse/nlargest/nsmallest/isna/notna)
-- e acesso posicional escalar (at/iat).
-- Consolida: test_access.lua (parte Series) + seção seleção de test_enrich.lua
-- Rode da raiz: luajit tests/series/test_selection.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local function approximately_equal(left_value, right_value) return math.abs(left_value - right_value) < 1e-9 end
local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- ================================================================
-- 1. Series:at / iat — acesso escalar (indexação e chamada)
-- ================================================================

local nullable_integer_series = smaug.Series({10, 20, smaug.NA, 40}, "int64")

-- indexação s.at[i]
check(nullable_integer_series.at[1] == 10,                "at[1] = 10")
check(nullable_integer_series.at[2] == 20,                "at[2] = 20")
check(nullable_integer_series.at[3] == nil,               "at[3] = nil (null)")
check(nullable_integer_series.at[4] == 40,                "at[4] = 40")

-- chamada s.at(i)
check(nullable_integer_series.at(1) == 10,                "at(1) = 10")
check(nullable_integer_series.iat(4) == 40,               "iat(4) = 40")

-- iat equivalente a at em Series 1-D
check(nullable_integer_series.iat[2] == nullable_integer_series.at[2],          "iat[2] == at[2]")

-- 12.9: s:iat(i) (forma method) orienta em vez de passar a Series como índice
do
    local succeeded, error_message = pcall(function() return nullable_integer_series:iat(3) end)
    error_message = tostring(error_message)
    check(not succeeded,                          "12.9 s:iat(3) → erro")
    check(error_message:find("s.iat[i]", 1, true) ~= nil,
                                           "12.9 s:iat(3) orienta a forma correta")
    check(error_message:find("[1] 10", 1, true) == nil,
                                           "12.9 s:iat(3) NÃO despeja os valores da Series")
    check(error_message:find("<Series", 1, true) ~= nil,
                                           "12.9 s:iat(3) descreve a Series sem conteúdo")
    -- a classe toda: nenhum método de acesso vaza dados na mensagem
    local string_series = smaug.Series({"aaa", "bbb", "ccc"}, "string")
    for unused_index, case in ipairs({
        { "get",      function() string_series:get(string_series) end },
        { "set",      function() string_series:set(string_series, "x") end },
        { "is_null",  function() string_series:is_null(string_series) end },
        { "set_null", function() string_series:set_null(string_series) end },
    }) do
        local succeeded_2, error_message_2 = pcall(case[2])
        error_message_2 = tostring(error_message_2)
        check(error_message_2:find("aaa", 1, true) == nil,
              "12.9 " .. case[1] .. "(Series) não vaza valores no erro")
    end
end

-- string e datetime
local string_series = smaug.Series({"x", "y"}, "string")
check(string_series.at[1] == "x",              "at[1] string = x")

-- fora dos limites → erro
check(not pcall(function() return nullable_integer_series.at[99] end),  "at[99] = erro (fora dos limites)")
check(not pcall(function() return nullable_integer_series.at[0] end),   "at[0] = erro")
-- índice não-numérico → erro
check(not pcall(function() return nullable_integer_series.at["x"] end), "at['x'] = erro (não-numérico)")

-- ================================================================

-- =====================================================================
-- Seleção condicional (de test_enrich.lua seção isna/where/mask/ifelse)
-- =====================================================================

-- isna / notna
local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 3.0}, "float64")
check(nullable_floating_point_series:isna(2) == true,   "isna(2)=true")
check(nullable_floating_point_series:isna(1) == false,  "isna(1)=false")
check(nullable_floating_point_series:notna(1) == true,  "notna(1)=true")
check(nullable_floating_point_series:notna(2) == false, "notna(2)=false")

-- where / mask / ifelse
local floating_point_series  = smaug.Series({1.0,2.0,3.0,4.0}, "float64")
local condition_mask = floating_point_series:gt(2)
local conditional_series   = floating_point_series:where(condition_mask, 0.0)
check(conditional_series:get(1) == 0.0, "where[1]=0 (falso)")
check(conditional_series:get(3) == 3.0, "where[3]=3 (verdadeiro)")
local masked_series  = floating_point_series:mask(condition_mask, 0.0)
check(masked_series:get(1) == 1.0, "mask[1]=1 (falso, mantém)")
check(masked_series:get(3) == 0.0, "mask[3]=0 (verdadeiro, substitui)")
local conditional_series_2 = smaug.Series.ifelse(condition_mask, floating_point_series, smaug.Series.full(4, 0.0, "float64"))
check(conditional_series_2:get(1) == 0.0, "ifelse[1]=0 (falso)")
check(conditional_series_2:get(4) == 4.0, "ifelse[4]=4 (verdadeiro)")

-- ================================================================

-- ================================================================
-- 7.4 — bool eq/ne (único dtype que faltava igualdade)
-- ================================================================
do
    local nullable_boolean_series = smaug.Series({true, false, smaug.NA}, "bool")
    local function format_boolean_series(source_series) local formatted_values = {}; for row_index = 1, source_series:len() do formatted_values[row_index] = source_series:is_null(row_index) and "NA" or tostring(source_series:get(row_index)) end; return table.concat(formatted_values, ",") end

    check(format_boolean_series(nullable_boolean_series:eq(true)) == "true,false,NA", "7.4 bool eq(true)")
    check(format_boolean_series(nullable_boolean_series:eq(false)) == "false,true,NA", "7.4 bool eq(false)")
    check(format_boolean_series(nullable_boolean_series:ne(true)) == "false,true,NA", "7.4 bool ne(true)")
    check(nullable_boolean_series:eq(true):is_null(3), "7.4 bool eq: NA preservado (Kleene)")
    check(nullable_boolean_series:eq(true):dtype() == "bool", "7.4 bool eq retorna Series<bool>")
    -- erro de tipo orientado
    local succeeded = pcall(function() return nullable_boolean_series:eq(1) end)
    check(not succeeded, "7.4 bool eq(número) erra (espera true/false)")
end

-- ===================================================================
-- 10.6 Passo (b): where/mask/ifelse delegam a select (Anel 0).
-- cond true → a, false OU NA → b (decisão 1a). int64 > 2^53 exato nos
-- dois ramos; degrau saiu. Broadcast de escalar/nil em Lua.
-- ===================================================================
do
    local ffi = require("ffi")
    local large_integer = ffi.new("int64_t", 9007199254740993LL)  -- 2^53+1

    -- cond = [true, false, NA]
    local condition = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "bool", "c"); condition:set(1, true); condition:set(2, false); condition:set_null(3)

    -- i64: BIG em ambos os ramos + valores distintos pra provar a fonte.
    -- a=[BIG,5,5]  o=[7,BIG,NA]
    local allocated_integer_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "int64", "a"); allocated_integer_series:set(1, large_integer); allocated_integer_series:set(2, 5); allocated_integer_series:set(3, 5)
    local fallback_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "int64", "o"); fallback_series:set(1, 7); fallback_series:set(2, large_integer); fallback_series:set_null(3)

    local conditional_series_3 = allocated_integer_series:where(condition, fallback_series)          -- true→a, false/NA→o
    check(tostring(conditional_series_3:get_raw(1)) == tostring(large_integer), "10.6b: where true→a (2^53+1 exato)")
    check(tostring(conditional_series_3:get_raw(2)) == tostring(large_integer), "10.6b: where false→o (2^53+1 exato)")
    check(conditional_series_3:is_null(3),                            "10.6b: where NA→o (nulo)")

    local masked_series_2 = allocated_integer_series:mask(condition, fallback_series)           -- inverso: true→o, false/NA→a
    check(masked_series_2:get(1) == 7,                "10.6b: mask true→o")
    check(masked_series_2:get(2) == 5,                "10.6b: mask false→a")
    check(masked_series_2:get(3) == 5,                "10.6b: mask NA→a")

    local conditional_series_4 = smaug.Series.ifelse(condition, allocated_integer_series, fallback_series)     -- = where(a,cond,o)
    check(tostring(conditional_series_4:get_raw(1)) == tostring(large_integer) and
          tostring(conditional_series_4:get_raw(2)) == tostring(large_integer) and conditional_series_4:is_null(3),
          "10.6b: ifelse = where (a,o)")

    -- operando escalar (broadcast em Lua): false/NA → 0
    local conditional_series_5 = allocated_integer_series:where(condition, 0)
    check(tostring(conditional_series_5:get_raw(1)) == tostring(large_integer), "10.6b: where escalar true→a")
    check(conditional_series_5:get(2) == 0 and conditional_series_5:get(3) == 0,        "10.6b: where escalar false/NA→0")

    -- operando nil → NA
    local conditional_series_6 = allocated_integer_series:where(condition, nil)
    check(tostring(conditional_series_6:get_raw(1)) == tostring(large_integer), "10.6b: where nil true→a")
    check(conditional_series_6:is_null(2) and conditional_series_6:is_null(3),          "10.6b: where nil false/NA→NA")

    -- f64
    local allocated_floating_point_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64"); allocated_floating_point_series:set(1, 1.5); allocated_floating_point_series:set(2, 9.0); allocated_floating_point_series:set(3, 9.0)
    local allocated_floating_point_series_2 = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64"); allocated_floating_point_series_2:set(1, 7.0); allocated_floating_point_series_2:set(2, 2.5); allocated_floating_point_series_2:set_null(3)
    local conditional_series_7 = allocated_floating_point_series:where(condition, allocated_floating_point_series_2)
    check(conditional_series_7:get(1) == 1.5 and conditional_series_7:get(2) == 2.5 and conditional_series_7:is_null(3), "10.6b: where f64 tabela-verdade")

    -- str: \0 embutido, ambos ramos, NA→b nulo
    local allocated_string_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "string"); allocated_string_series:set(1, "abc"); allocated_string_series:set(2, "z"); allocated_string_series:set(3, "q")
    local allocated_string_series_2 = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "string"); allocated_string_series_2:set(1, "x"); allocated_string_series_2:set(2, "a\0b"); allocated_string_series_2:set_null(3)
    local conditional_series_8 = allocated_string_series:where(condition, allocated_string_series_2)
    check(conditional_series_8:get(1) == "abc",  "10.6b: where str true→a")
    check(conditional_series_8:get(2) == "a\0b", "10.6b: where str false→b (\\0 preservado)")
    check(conditional_series_8:is_null(3),       "10.6b: where str NA→b nulo")

    -- str: '' válida selecionada em ambos → len==0 nos dois lados e total==0
    -- (exercita `if (len>0)` e o ramo `total>0 ? total : INIT`).
    local allocated_string_series_3 = smaug.Series({smaug.NA, smaug.NA}, "string"); allocated_string_series_3:set(1, ""); allocated_string_series_3:set_null(2)
    local allocated_string_series_4 = smaug.Series({smaug.NA, smaug.NA}, "string"); allocated_string_series_4:set_null(1); allocated_string_series_4:set(2, "")
    local boolean_series = smaug.Series({true, false}, "bool")
    local conditional_series_9 = allocated_string_series_3:where(boolean_series, allocated_string_series_4)   -- [ea[1]="", eb[2]=""]
    check(conditional_series_9:get(1) == "" and conditional_series_9:get(2) == "" and not conditional_series_9:is_null(1) and not conditional_series_9:is_null(2),
          "10.6b: where str '' válida len==0 / total==0")

    -- datetime (epoch_ms)
    local allocated_datetime_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "datetime"); allocated_datetime_series:set(1, 1000); allocated_datetime_series:set(2, 9); allocated_datetime_series:set(3, 9)
    local allocated_datetime_series_2 = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "datetime"); allocated_datetime_series_2:set(1, 7); allocated_datetime_series_2:set(2, 2000); allocated_datetime_series_2:set_null(3)
    local conditional_series_10 = allocated_datetime_series:where(condition, allocated_datetime_series_2)
    check(conditional_series_10:get(1) == 1000 and conditional_series_10:get(2) == 2000 and conditional_series_10:is_null(3), "10.6b: where dt tabela-verdade")

    -- não-regressão: int64 <= 2^53 intacto
    local integer_series = smaug.Series({10, 20}, "int64")
    local boolean_series_2 = smaug.Series({true, false}, "bool")
    check(integer_series:where(boolean_series_2, integer_series):get(1) == 10,     "10.6b: where i64<=2^53 intacto")
    check(smaug.Series.ifelse(boolean_series_2, integer_series, integer_series):get(1) == 10, "10.6b: ifelse i64<=2^53 intacto")

    -- falha visível: operando série de dtype diferente
    local wrong = smaug.Series({1.0, 2.0, 3.0}, "float64")
    check(not pcall(function() return allocated_integer_series:where(condition, wrong) end),
          "10.6b: where dtype divergente → erro visível")
    -- falha visível: cond de tamanho diferente
    check(not pcall(function() return allocated_integer_series:where(smaug.Series({true}, "bool"), fallback_series) end),
          "10.6b: where cond tamanho errado → erro visível")
end

-- ===================================================================
-- 9.4: nlargest/nsmallest preservam int64 exato (não fabricam valor)
-- Antes liam o buffer via tonumber() → double: em int64 > 2^53 o valor
-- não só perdia dígito como podia virar um número FORA do dataset
-- (…995 → …996, arredondado para o double representável mais próximo).
-- Numa operação de seleção isso é invenção de dado. Agora usam o buffer
-- nativo (int64_t[?]) e passam o cdata direto ao construtor.
-- ===================================================================
do
    local ffi = require("ffi")
    local exact_double_limit = ffi.new("int64_t", 9007199254740992LL)  -- 2^53
    local above_double_limit = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1
    local larger_integer = ffi.new("int64_t", 9007199254740995LL)  -- 2^53 + 3 (vira …996 em double)
    local integer_series = smaug.Series({exact_double_limit, above_double_limit, larger_integer}, "int64", "big")

    -- 9.4.1 — os valores devolvidos ESTÃO no dataset (nada fabricado).
    local largest_series = integer_series:nlargest(2)
    check(largest_series:get_raw(1) == 9007199254740995LL,
          "9.4.1 nlargest devolve o maior exato (não …996 fabricado)")
    check(largest_series:get_raw(2) == 9007199254740993LL,
          "9.4.1 nlargest devolve o segundo maior exato")

    -- 9.4.2 — nsmallest idem, e a ordem é crescente.
    local smallest_series = integer_series:nsmallest(2)
    check(smallest_series:get_raw(1) == 9007199254740992LL, "9.4.2 nsmallest menor exato")
    check(smallest_series:get_raw(2) == 9007199254740993LL, "9.4.2 nsmallest segundo exato")

    -- 9.4.3 — dtype preservado e n > len não estoura.
    check(largest_series._dtype == "int64", "9.4.3 nlargest preserva dtype int64")
    check(integer_series:nlargest(10):len() == 3, "9.4.3 n > len devolve o que há")

    -- 9.4.4 — float64 segue igual (double é nativo, nada a preservar).
    local floating_point_series_2 = smaug.Series({3.5, 1.25, 9.75}, "float64", "f")
    check(floating_point_series_2:nlargest(1):get(1) == 9.75, "9.4.4 float64 nlargest inalterado")
    check(floating_point_series_2:nsmallest(1):get(1) == 1.25, "9.4.4 float64 nsmallest inalterado")

    -- 9.4.5 — nulos continuam ignorados (sorted_nonnull), sem degradar o resto.
    local nullable_integer_series_2 = smaug.Series({above_double_limit, smaug.NA, larger_integer}, "int64", "comnull")
    local largest_result = nullable_integer_series_2:nlargest(2)
    check(largest_result:len() == 2, "9.4.5 nulos ignorados")
    check(largest_result:get_raw(1) == 9007199254740995LL, "9.4.5 exatidão mantida com nulos")
end

-- ===================================================================
-- 12.38: objeto do Smaug onde se espera tabela Lua
-- `type(v) == "table"` não distingue array de Series/DataSet — os dois são
-- table. Como esses objetos não têm parte array, `#v` dá 0 e `ipairs` não
-- itera, então a chamada devolvia resultado VAZIO ou ERRADO em silêncio.
-- Medido antes da correção: take→0 elementos, isin→tudo false, select→0
-- colunas, drop_duplicates→contagem errada.
-- ===================================================================
do
    local string_series_2  = smaug.Series({"a", "b", "c"}, "string")
    local integer_series = smaug.Series({1, 2}, "int64")

    -- 12.38.1 — os cinco casos que aceitavam em silêncio agora erram
    check(not pcall(function() return string_series_2:take(integer_series) end),
          "12.38.1 take(Series) recusado (devolvia 0 elementos)")
    check(not pcall(function() return string_series_2:isin(integer_series) end),
          "12.38.1 isin(Series) recusado (devolvia tudo false)")
    local converted_series = smaug.Series({"a", "b", "a"}, "string"):astype("categorical")
    check(not pcall(function() return converted_series:take(integer_series) end),
          "12.38.1 categorical:take(Series) recusado")

    -- 12.38.2 — a mensagem nomeia a saída, não só reclama
    local succeeded, error_message = pcall(function() return string_series_2:take(integer_series) end)
    check(not succeeded and tostring(error_message):match("to_table") ~= nil,
          "12.38.2 mensagem sugere :to_table() como conversão")
    check(tostring(error_message):match("objeto do Smaug") ~= nil,
          "12.38.2 mensagem nomeia a causa")

    -- 12.38.3 — o caminho legítimo segue intacto: tabela Lua simples funciona
    check(string_series_2:take({1, 3}):len() == 2,        "12.38.3 take com tabela Lua intacto")
    check(string_series_2:isin({"a"}):get(1) == true,     "12.38.3 isin com tabela Lua intacto")
    check(string_series_2:take(integer_series:to_table()):len() == 2,"12.38.3 :to_table() é a saída e funciona")

    -- 12.38.4 — tipo errado (não-tabela) continua com a mensagem antiga
    check(not pcall(function() return string_series_2:take(5) end), "12.38.4 take(number) recusado")
end

print(string.format("OK — %d checks passaram (Series: at/iat, where, mask, ifelse, isna/notna)", passed_checks))
