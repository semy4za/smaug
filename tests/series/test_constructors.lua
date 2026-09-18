-- tests/series/test_constructors.lua
-- Series: construtores, acesso elementar, aritmética, reduções core,
-- lifecycle (clone/view/COW), take, head/tail, astype, describe,
-- comparações, filter, lógica Kleene, map.
-- Consolida: test_series.lua + test_i64.lua + test_bool_dtype.lua
-- Baseado estritamente no API_INDEX v1.0.
-- Rode da raiz: luajit tests/series/test_constructors.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")

local ffi    = require("ffi")

local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local function approximately_equal(left_value, right_value, tolerance)
    tolerance = tolerance or 1e-9
    if left_value == nil and right_value == nil then return true end
    if left_value == nil or right_value == nil then return false end
    return math.abs(left_value - right_value) < tolerance
end

local function check_error(callback, message)
    local succeeded = pcall(callback)
    check(not succeeded, message .. " (deveria lançar erro)")
end

-- =====================================================================
-- 1. Factories e Acesso Básico
-- =====================================================================
do
    -- Series.float64
    local floating_point_series = smaug.Series.float64(3, "x")
    floating_point_series:set(1, 1.0); floating_point_series:set(2, 2.0); floating_point_series:set(3, 3.0)
    check(floating_point_series:len() == 3, "float64: len = 3")
    check(floating_point_series:get(2) == 2.0, "float64: get 1-based")
    check(floating_point_series[3] == 3.0, "float64: __index numérico")
    floating_point_series[1] = 10.0
    check(floating_point_series[1] == 10.0, "float64: __newindex numérico")

    -- nil <-> null
    floating_point_series:set(2, nil)
    check(floating_point_series:is_null(2), "set nil -> null")
    check(floating_point_series:get(2) == nil, "get null -> nil")
    check(floating_point_series:count_nonnull() == 2, "count_nonnull")

    -- Cobertura explícita da factory from_array, incluindo nulos.
    local nullable_floating_point_series = smaug.Series.from_array({5, smaug.NA, 15, 20}, "float64", "t")
    check(nullable_floating_point_series:len() == 4, "from_array: len")
    check(nullable_floating_point_series:is_null(2), "from_array: nil -> null")
    check(approximately_equal(nullable_floating_point_series:sum(), 40.0), "from_array: sum")

    -- Series.new
    local allocated_boolean_series = smaug.Series.new("bool", 3)
    check(allocated_boolean_series:len() == 3, "new: len")
    check(allocated_boolean_series:is_null(1), "new: todos null")
    allocated_boolean_series:set(1, true); allocated_boolean_series:set(2, false); allocated_boolean_series:set_null(3)
    check(allocated_boolean_series:get(1) == true, "new: set true")
    check(allocated_boolean_series:get(2) == false, "new: set false")
    check(allocated_boolean_series:is_null(3), "new: set_null")

    -- smaug.Series() chamável
    local source_series = smaug.Series({1, 2, 3})
    check(source_series and source_series:len() == 3, "init: smaug.Series({...}) chamável")
    check(source_series._dtype == "int64", "init: inferência int64")
    local floating_point_series_2 = smaug.Series({1.5, 2.5}, "float64")
    check(floating_point_series_2._dtype == "float64", "init: dtype explícito")

    -- factories no top-level
    check(type(smaug.float64) == "function", "init: smaug.float64 exposto")
    check(type(smaug.int64) == "function", "init: smaug.int64 exposto")
    check(type(smaug.string) == "function", "init: smaug.string exposto")
    check(type(smaug.datetime) == "function", "init: smaug.datetime exposto")
    check(smaug.from_table == nil, "init: from_table removido do top-level")
end

-- =====================================================================
-- 2. Reduções Core (f64)
-- =====================================================================
do
    local nullable_floating_point_series = smaug.Series({10.0, smaug.NA, 3.0}, "float64")

    -- ignore_na = true (default)
    check(approximately_equal(nullable_floating_point_series:sum(), 13.0), "sum ignora NA")
    check(approximately_equal(nullable_floating_point_series:mean(), 6.5), "mean ignora NA")

    -- ignore_na = false
    check(nullable_floating_point_series:sum(false) == nil, "sum(false) com NA -> nil")

    -- describe
    local description = smaug.Series({1, 2, 3, 4, smaug.NA}, "float64"):describe()
    check(description.count == 4 and description.nulls == 1, "describe: count/nulls")
    check(approximately_equal(description.mean, 2.5), "describe: mean")
    check(description.min == 1 and description.max == 4, "describe: min/max")
    check(approximately_equal(description["50%"], 2.5), "describe: mediana")
end

-- =====================================================================
-- 3. Aritmética: Série × Escalar e Série × Série
-- =====================================================================
do
    -- série × escalar
    local source_series = smaug.Series({1, 2, 3}, "float64")
    local scalar_sum_series = source_series + 10
    check(scalar_sum_series:get(1) == 11.0 and scalar_sum_series:get(3) == 13.0, "Series + escalar")
    local scalar_product_series = 2 * source_series
    check(scalar_product_series:get(2) == 4.0, "escalar * Series (comuta)")
    check(source_series:get(1) == 1.0, "imutabilidade: original intacto")

    -- série × série
    local left_series = smaug.Series({1, 2, 3}, "float64")
    local right_series = smaug.Series({10, 20, 30}, "float64")
    local sum_series = left_series + right_series
    check(sum_series:get(1) == 11.0 and sum_series:get(3) == 33.0, "Series + Series")

    -- propagação de NA
    local nullable_series = smaug.Series({1, smaug.NA, 3}, "float64")
    local nullable_sum_series = nullable_series + right_series
    check(nullable_sum_series:is_null(2), "NA propaga em Series+Series")
end

-- =====================================================================
-- 4. int64: Aritmética, Sentinela e Precisão > 2^53
-- =====================================================================
do
    -- aritmética básica
    local left_integer_series = smaug.Series({10, 20, 30}, "int64")
    local right_integer_series = smaug.Series({3, 4, 5}, "int64")
    check((left_integer_series + right_integer_series):get(1) == 13, "i64: add")
    check((left_integer_series - right_integer_series):get(1) == 7, "i64: sub")
    check((left_integer_series * right_integer_series):get(1) == 30, "i64: mul")

    -- Overflow não faz wrap: o FFI preserva SMG_ERR_OVERFLOW e a superfície
    -- Lua explica a causa em vez de confundir com OOM ou erro genérico.
    local maximum_int64 = 9223372036854775807LL
    local maximum_integer_series = smaug.Series({maximum_int64}, "int64")
    local overflow_succeeded, overflow_error = pcall(function() return maximum_integer_series + 1 end)
    check(not overflow_succeeded and overflow_error:match("smaug: %+%(%) excede o intervalo int64"),
          "i64: add overflow devolve erro Lua claro")

    -- divisão: '/' é float64, floordiv é int64
    local numerator_series = smaug.Series({10, 20}, "int64")
    local denominator_series = smaug.Series({2, 0}, "int64")
    local quotient_series = numerator_series / denominator_series
    check(quotient_series._dtype == "float64", "N.3: '/' entre int64 promove a float64")
    check(quotient_series:get(1) == 5, "f64 div ok (10/2=5)")
    check(quotient_series:is_null(2), "div por zero -> null")

    local integer_quotient_series = numerator_series:floordiv(denominator_series)
    check(integer_quotient_series._dtype == "int64", "N.4: floordiv preserva int64")
    check(integer_quotient_series:get(1) == 5, "floordiv ok (10//2=5)")
    check(integer_quotient_series:is_null(2), "floordiv por zero -> null")

    -- sentinela INT64_MIN
    local nullable_integer_series = smaug.Series({10, smaug.NA, 30}, "int64")
    check(nullable_integer_series:sum() == 40, "i64 sum ignora NA")
    check(nullable_integer_series:sum(false) == nil, "i64 sum(false) com NA -> nil (sentinela)")
    check(nullable_integer_series:max() == 30, "i64 max")

    -- precisão > 2^53 via cdata e get_raw
    local large_integer = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1
    local integer_series = smaug.Series({smaug.NA}, "int64")
    integer_series:set(1, large_integer)
    check(integer_series:get_raw(1) == large_integer, "9.1.1: int64 cdata preserva 2^53+1 via get_raw")
    check(integer_series:get(1) == 9007199254740992, "9.1.1: get() comum trunca em double (limitação documentada)")

    -- number > 2^53 é aceito (avisa, não bloqueia)
    local succeeded = pcall(function() integer_series:set(1, 9007199254740994) end)
    check(succeeded == true, "9.1.2: number > 2^53 é aceito")

    -- uint64_t > INT64_MAX é recusado
    local unsigned_maximum = 18446744073709551615ULL
    local succeeded_2 = pcall(function() integer_series:set(1, unsigned_maximum) end)
    check(succeeded_2 == false, "9.1.3: uint64_t acima de INT64_MAX é recusado")

    -- get_raw só se aplica a int64
    local floating_point_series = smaug.Series({smaug.NA}, "float64")
    floating_point_series:set(1, 3.5)
    local succeeded_3 = pcall(function() floating_point_series:get_raw(1) end)
    check(succeeded_3 == false, "get_raw recusa dtype != int64")
end

-- =====================================================================
-- 5. Fronteira do Escalar em Operações (9.3)
-- =====================================================================
do
    local exact_double_limit = ffi.new("int64_t", 9007199254740992LL)  -- 2^53
    local above_double_limit = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1
    local integer_series = smaug.Series({exact_double_limit, above_double_limit}, "int64", "id")

    -- cdata int64_t no threshold: aceito e distingue exato
    local equality_mask = integer_series:eq(above_double_limit)
    check(equality_mask:get(1) == false and equality_mask:get(2) == true, "9.3.1: comparador aceita cdata e distingue 2^53+1")

    local greater_than_mask = integer_series:gt(exact_double_limit)
    check(greater_than_mask:get(1) == false and greater_than_mask:get(2) == true, "9.3.1: gt com cdata int64_t exato")

    -- number >= 2^53 no threshold: RECUSADO
    local succeeded = pcall(function() return integer_series:eq(9007199254740993) end)
    check(succeeded == false, "9.3.2: number 2^53+1 (degrada p/ 2^53) recusado")

    -- number seguro (< 2^53): comparação normal
    local integer_series_2 = smaug.Series({5, 9}, "int64")
    local equality_mask_2 = integer_series_2:eq(5)
    check(equality_mask_2:get(1) == true and equality_mask_2:get(2) == false, "9.3.3: number < 2^53 compara normal")

    -- aritmética escalar com cdata
    local integer_series_3 = smaug.Series({1}, "int64")
    check((integer_series_3 + above_double_limit):get_raw(1) == 9007199254740994LL, "9.3.7: série int64 + cdata preserva exato")
    check((integer_series_3:floordiv(above_double_limit)):get_raw(1) == 0LL, "9.3.7: floordiv por cdata exato")

    -- number >= 2^53 na aritmética: RECUSADO
    check(pcall(function() return integer_series_3 + 9007199254740993 end) == false, "9.3.8: série int64 + number >= 2^53 recusado")
end

-- =====================================================================
-- 6. Promoção de Tipo (Bloco N)
-- =====================================================================
do
    -- int64 + float64 promove para float64
    local integer_series = smaug.Series({2, 3, 4}, "int64")
    local floating_point_series = smaug.Series({1.5, 2.0, 0.5}, "float64")
    check((integer_series * floating_point_series)._dtype == "float64", "N.1: int*float -> float64")
    check((integer_series * floating_point_series):get(1) == 3.0, "N.1: valor correto (2*1.5=3)")

    -- int * escalar float promove
    check((integer_series * 2.5)._dtype == "float64", "N.2: int*2.5 -> float64")
    check((integer_series * 2.5):get(1) == 5.0, "N.2: valor correto (2*2.5=5)")

    -- guardas: numérico × não-numérico barra
    check_error(function() return integer_series * smaug.Series({true,false,true}, "bool") end, "N: int*bool barrado")
    check_error(function() return integer_series * smaug.Series({"a","b","c"}, "string") end, "N: int*string barrado")
end

-- =====================================================================
-- 7. Inferência de Tipo por Famílias (12.31)
-- =====================================================================
-- Aqui from_array é a API sob teste; as demais fixtures usam smaug.Series().
do
    -- promoção segura dentro da família numérica
    check(smaug.Series.from_array({1, 2, 3})._dtype == "int64", "12.31.1: só inteiros → int64")
    check(smaug.Series.from_array({1, 2.5})._dtype == "float64", "12.31.1: int+float → float64")
    check(smaug.Series.from_array({1, smaug.NA, 2.5})._dtype == "float64", "12.31.1: nulos não atrapalham")

    -- famílias homogêneas
    check(smaug.Series.from_array({"a", "b"})._dtype == "string", "12.31.2: só strings → string")
    check(smaug.Series.from_array({true, false})._dtype == "bool", "12.31.2: só booleanos → bool")
    check(smaug.Series.from_array({})._dtype == "string", "12.31.2: lista vazia → string")
    check(smaug.Series.from_array({smaug.NA})._dtype == "string", "12.31.2: só-nula → string")

    -- mistura entre famílias: erro na inferência
    check_error(function() return smaug.Series.from_array({1, "x"}) end, "12.31.3: número + string recusado")
    check_error(function() return smaug.Series.from_array({true, 1}) end, "12.31.3: booleano + número recusado")
    check_error(function() return smaug.Series.from_array({"a", true}) end, "12.31.3: string + booleano recusado")

    -- dtype explícito ignora inferência
    local succeeded, error_message = pcall(function() return smaug.Series.from_array({1, "x"}, "string") end)
    check(not succeeded and tostring(error_message):match("valor para string") ~= nil, "12.31.5: dtype explícito ignora inferência")
end

-- =====================================================================
-- 8. Lifecycle: clone, view (COW), append
-- =====================================================================
do
    -- clone independente
    local original_series = smaug.Series({1, 2, 3}, "float64")
    local cloned_series = original_series:clone()
    cloned_series[1] = 99
    check(original_series[1] == 1.0, "clone: original intacto")
    check(cloned_series[1] == 99, "clone: modificado")

    -- view: zero-copy, COW-writable
    local floating_point_series = smaug.Series({10, 20, 30, 40, 50}, "float64", "base")
    local series_view = floating_point_series:view(2, 3)  -- [20, 30, 40]
    check(series_view:len() == 3, "view: len")
    check(series_view:get(1) == 20.0 and series_view:get(3) == 40.0, "view: valores")
    check(series_view._c.meta.is_view == true, "view: marcada como view no struct C")

    -- zero-copy: reflete mutações da pai até o primeiro set
    floating_point_series:set(2, 99.0)
    check(series_view:get(1) == 99.0, "view: reflete mutação da pai antes do detach")

    -- COW: set na view destaca o buffer
    local view_write_succeeded = pcall(function() series_view:set(1, 0.0) end)
    check(view_write_succeeded, "view: set via COW não dá erro")
    check(series_view._c.meta.is_view == false, "view: detachada após primeiro set")
    check(series_view:get(1) == 0.0, "view: set gravou o valor")
    check(floating_point_series:get(2) == 99.0, "view: pai preservada pelo COW")

    -- COW: append em view
    local series_view_2 = floating_point_series:view(1, 2)
    local view_append_succeeded = pcall(function() series_view_2:append(1.0) end)
    check(view_append_succeeded, "view: append via COW não dá erro")
    check(series_view_2:len() == 3, "view: append incrementou tamanho")
    check(series_view_2:get(3) == 1.0, "view: append gravou valor")

    -- view fora dos limites dá erro
    local view_oob = pcall(function() return floating_point_series:view(4, 5) end)
    check(not view_oob, "view: fora dos limites dá erro")

    -- clone de view → série independente
    local series_view_3 = floating_point_series:view(2, 3)
    local view_clone = series_view_3:clone()
    view_clone:set(1, -1.0)
    check(view_clone:get(1) == -1.0 and series_view_3:get(1) == 99.0, "clone de view é independente")

    -- view em string (suportado, 9.2)
    local sv_base = smaug.Series({"SP", "RJ", "MG", "BA"}, "string")
    local sv_win = sv_base:view(2, 2)
    sv_win:set(1, "MINAS")
    check(sv_win:get(1) == "MINAS", "view string: set na view reflete")
    check(sv_base:get(2) == "RJ", "view string: pai intacta após COW")

    -- view em categorical não é suportado
    local succeeded, categorical_view_error = pcall(function() return smaug.Series({"x", "y"}, "categorical"):view(1,1) end)
    check(not succeeded and categorical_view_error:match("'categorical'") and categorical_view_error:match("sem buffer"), "view categorical: erro com razão")
end

-- =====================================================================
-- 9. Seleção: take, head, tail, sort, argsort
-- =====================================================================
do
    -- take
    local source_series = smaug.Series({100, 200, 300, 400}, "float64")
    local selected_result = source_series:take({4, 1, 3})
    check(selected_result:len() == 3, "take: len")
    check(selected_result:get(1) == 400.0 and selected_result:get(2) == 100.0 and selected_result:get(3) == 300.0, "take: ordem")
    check_error(function() return source_series:take({1, 99}) end, "take: índice fora dos limites")

    -- head / tail
    local floating_point_series = smaug.Series({1, 2, 3, 4, 5, 6}, "float64")
    local head_result = floating_point_series:head(2)
    check(head_result:len() == 2 and head_result:get(1) == 1.0 and head_result:get(2) == 2.0, "head")
    local tail_result = floating_point_series:tail(2)
    check(tail_result:len() == 2 and tail_result:get(1) == 5.0 and tail_result:get(2) == 6.0, "tail")

    -- sort
    local floating_point_series_2 = smaug.Series({3, 1, 2}, "float64")
    local sorted = floating_point_series_2:sort(true)
    check(sorted:get(1) == 1.0 and sorted:get(3) == 3.0, "sort asc")
    local nullable_floating_point_series = smaug.Series({1, smaug.NA, 3}, "float64")
    check_error(function() return nullable_floating_point_series:sort() end, "sort com NA dá erro")

    -- tostring não crasha
    check(type(tostring(floating_point_series_2)) == "string", "__tostring")
end

-- =====================================================================
-- 10. astype: Conversão entre dtypes
-- =====================================================================
do
    -- f64 → i64 (trunca)
    local floats = smaug.Series({1.9, 2.1, smaug.NA, 4.7}, "float64")
    local converted_series = floats:astype("int64")
    check(converted_series._dtype == "int64", "astype: muda dtype")
    check(converted_series:get(1) == 1 and converted_series:get(2) == 2, "astype: f64->i64 trunca")
    check(converted_series:is_null(3), "astype: preserva null")

    -- i64 → f64
    local converted_series_2 = smaug.Series({5, 6}, "int64"):astype("float64")
    check(converted_series_2._dtype == "float64" and converted_series_2:get(1) == 5.0, "astype: i64->f64")

    -- i64 > 2^53 em astype (10.7)
    local large_integer = ffi.new("int64_t", 9007199254740993LL)
    local allocated_integer_series = smaug.Series({smaug.NA}, "int64", "big")
    allocated_integer_series:set(1, large_integer)
    check(allocated_integer_series:astype("string"):get(1) == "9007199254740993", "10.7: i64->string > 2^53 EXATO")
    check(allocated_integer_series:astype("int64"):astype("string"):get(1) == "9007199254740993", "10.7: i64->i64 preserva exato")

    -- bool → int64/string
    local boolean_series = smaug.Series({true, false, true}, "bool")
    local converted_series_3 = boolean_series:astype("int64")
    check(converted_series_3._dtype == "int64" and converted_series_3:get(1) == 1 and converted_series_3:get(2) == 0, "astype: bool->int64")
    local converted_series_4 = boolean_series:astype("string")
    check(converted_series_4._dtype == "string" and converted_series_4:get(1) == "true", "astype: bool->string")

    -- int64 → bool (rígido: só 0/1)
    check_error(function() smaug.Series({0, 1, 2, 0}, "int64"):astype("bool") end, "astype: int64->bool: 2 é erro")

    -- string → bool
    local string_series = smaug.Series({"true", "false", "x"}, "string")
    local converted_series_5 = string_series:astype("bool")
    check(converted_series_5:get(1) == true and converted_series_5:get(2) == false and converted_series_5:is_null(3), "astype: string->bool")

    -- datetime ↔ bool não suportado
    local boolean_series_2 = smaug.Series({true, false}, "bool")
    local succeeded, error_message = pcall(function() return boolean_series_2:astype("datetime") end)
    check(not succeeded and tostring(error_message):match("não suportado") ~= nil, "10.7: bool->datetime erro limpo")

    -- set/append em int64 recusam não-inteiro
    local series_int64 = smaug.Series({smaug.NA, smaug.NA}, "int64")
    check_error(function() series_int64:set(1, 1.5) end, "i64 set recusa 1.5")
    check_error(function() series_int64:set(1, 0/0) end, "i64 set recusa NaN")
    local empty_integer_series = smaug.Series({}, "int64")
    check_error(function() empty_integer_series:append(2.7) end, "i64 append recusa 2.7")

    -- astype f64->i64: NaN/Inf → null
    local floating_point_series = smaug.Series({1.9, 2.1, -3.7, 0/0, 1/0}, "float64")
    local converted_series_6 = floating_point_series:astype("int64")
    check(converted_series_6:get(1) == 1 and converted_series_6:get(2) == 2 and converted_series_6:get(3) == -3, "astype: trunca em direção a zero")
    check(converted_series_6:is_null(4) and converted_series_6:is_null(5), "astype: NaN/Inf → null")
end

-- =====================================================================
-- 11. Comparações (gt, lt, eq, ge, le, ne)
-- =====================================================================
do
    -- f64
    local floating_point_series = smaug.Series({10, 20, 30, 40}, "float64")
    local greater_than_mask = floating_point_series:gt(25)
    check(greater_than_mask:len() == 4, "gt: len")
    check(greater_than_mask:get(1) == false and greater_than_mask:get(3) == true, "gt: valores")
    check(greater_than_mask:count_true() == 2, "count_true")
    check(greater_than_mask:any() == true and greater_than_mask:all() == false, "any/all")

    -- ge/le/ne com NA
    local nullable_floating_point_series = smaug.Series({10, 20, 30, smaug.NA}, "float64")
    check(nullable_floating_point_series:ge(20):get(1) == false, "f64 ge: abaixo -> false")
    check(nullable_floating_point_series:ge(20):get(2) == true, "f64 ge: igual -> true")
    check(nullable_floating_point_series:ge(20):is_null(4), "f64 ge: null -> NA")
    check(nullable_floating_point_series:ne(20):get(1) == true, "f64 ne: diferente -> true")
    check(nullable_floating_point_series:ne(20):get(2) == false, "f64 ne: igual -> false")

    -- NaN (IEEE: NaN >= x = false)
    local nan_series = smaug.Series({0/0}, "float64")
    check(nan_series:ge(0):get(1) == false, "f64 ge: NaN -> false")
    check(nan_series:ne(0):get(1) == true, "f64 ne: NaN != 0 -> true")

    -- i64
    local nullable_integer_series = smaug.Series({1, 2, 3, smaug.NA}, "int64")
    check(nullable_integer_series:ge(2):get(1) == false, "i64 ge: abaixo -> false")
    check(nullable_integer_series:ge(2):get(2) == true, "i64 ge: igual -> true")
    check(nullable_integer_series:ge(2):is_null(4), "i64 ge: null -> NA")

    -- string
    local nullable_string_series = smaug.Series({"a", "b", "c", smaug.NA}, "string")
    check(nullable_string_series:ge("b"):get(1) == false, "str ge: abaixo -> false")
    check(nullable_string_series:ge("b"):get(2) == true, "str ge: igual -> true")
    check(nullable_string_series:ge("b"):is_null(4), "str ge: null -> NA")

    -- integração: df[s:ge(x)]
    local source_dataset = smaug.DataSet({{"v", {1,2,3,4,5}, "int64"}})
    check(source_dataset[source_dataset.v:ge(3)]:nrows() == 3, "ge integração: >= 3 -> 3 linhas")
end

-- =====================================================================
-- 12. Boolean: filter, lógica Kleene, operadores
-- =====================================================================
do
    -- filter
    local floating_point_series = smaug.Series({10, 20, 30, 40}, "float64")
    local greater_than_mask = floating_point_series:gt(25)
    local filtered_result = floating_point_series:filter(greater_than_mask)
    check(filtered_result:len() == 2 and filtered_result:get(1) == 30.0 and filtered_result:get(2) == 40.0, "filter")
    check_error(function() return floating_point_series:filter({}) end, "filter exige Series<bool>")

    -- lógica AND/OR/XOR/NOT
    local greater_than_mask_2 = smaug.Series({1, 1, 0, 0}, "int64"):gt(0)  -- [T,T,F,F]
    local greater_than_mask_3 = smaug.Series({1, 0, 1, 0}, "int64"):gt(0)  -- [T,F,T,F]
    check(greater_than_mask_2:land(greater_than_mask_3):to_table()[1] == true and greater_than_mask_2:land(greater_than_mask_3):get(2) == false, "and")
    check((greater_than_mask_2 + greater_than_mask_3):get(2) == true, "or via operador +")
    check((greater_than_mask_2 - greater_than_mask_3):get(1) == false and (greater_than_mask_2 - greater_than_mask_3):get(2) == true, "xor via operador -")
    check((greater_than_mask_2 * greater_than_mask_3):get(1) == true and (greater_than_mask_2 * greater_than_mask_3):get(2) == false, "and via operador *")
    check(greater_than_mask_2:lnot():get(1) == false and greater_than_mask_2:lnot():get(3) == true, "not")

    -- Kleene (três valores)
    local greater_than_mask_4 = smaug.Series({1, smaug.NA, smaug.NA}, "int64"):gt(0)  -- [T, NA, NA]
    local greater_than_mask_5 = smaug.Series({0, 0, 1}, "int64"):gt(0)    -- [F, F, T]
    local kleene_and_mask = greater_than_mask_4:land(greater_than_mask_5)
    check(kleene_and_mask:get(1) == false, "T and F = F")
    check(kleene_and_mask:get(2) == false, "NA and F = F (Kleene)")
    check(kleene_and_mask:get(3) == nil, "NA and T = NA (Kleene)")
    local kleene_or_mask = greater_than_mask_4:lor(greater_than_mask_5)
    check(kleene_or_mask:get(2) == nil, "NA or F = NA (Kleene)")
    check(kleene_or_mask:get(3) == true, "NA or T = T (Kleene)")
    check(greater_than_mask_4:lnot():get(2) == nil, "NOT NA = NA")

    -- tostring da Series<bool>
    check(type(tostring(greater_than_mask)) == "string", "Series<bool> __tostring")
end

-- =====================================================================
-- 13. Bool: Construção, fillna, dropna, describe, sort
-- =====================================================================
do
    local nullable_boolean_series = smaug.Series({true, smaug.NA, false, true}, "bool")

    check(nullable_boolean_series._dtype == "bool", "dtype bool")
    check(nullable_boolean_series:len() == 4, "len")
    check(nullable_boolean_series:get(1) == true, "get true")
    check(nullable_boolean_series:get(2) == nil, "get NA -> nil")
    check(nullable_boolean_series:count_nonnull() == 3, "count_nonnull")

    -- check_value: rejeita não-boolean
    local allocated_boolean_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "bool")
    check_error(function() allocated_boolean_series:set(1, 42) end, "set(42) rejeitado")
    check_error(function() allocated_boolean_series:set(1, "x") end, "set('x') rejeitado")
    check_error(function() allocated_boolean_series:set(1, 1.5) end, "set(1.5) rejeitado")

    -- append
    local allocated_boolean_series_2 = smaug.Series({}, "bool")
    allocated_boolean_series_2:append(true); allocated_boolean_series_2:append(false); allocated_boolean_series_2:append(smaug.NA)
    check(allocated_boolean_series_2:len() == 3, "append len")
    check(allocated_boolean_series_2:get(1) == true, "append true")
    check(allocated_boolean_series_2:is_null(3), "append NA")

    -- fillna
    local filled_result = nullable_boolean_series:fillna(false)
    check(filled_result:get(2) == false, "fillna false substituiu NA")
    check(filled_result:count_nonnull() == 4, "fillna count_nonnull")
    check_error(function() nullable_boolean_series:fillna(1) end, "fillna(1) rejeitado")

    -- dropna
    local non_null_result = nullable_boolean_series:dropna()
    check(non_null_result:len() == 3, "dropna len")
    check(non_null_result:count_nonnull() == 3, "dropna nonnull")

    -- describe
    local description = nullable_boolean_series:describe()
    check(description.count == 3, "describe count")
    check(description.nulls == 1, "describe nulls")
    check(description.count_true == 2, "describe count_true")
    check(description.count_false == 1, "describe count_false")

    -- sort / argsort (sem null)
    local boolean_series = smaug.Series({true, false, true, false}, "bool")

    local ascending_series = boolean_series:sort(true)
    check(ascending_series:get(1) == false, "sort asc: false primeiro")
    check(ascending_series:get(3) == true, "sort asc: true terceiro")

    local descending_series = boolean_series:sort(false)
    check(descending_series:get(1) == true, "sort desc: true primeiro")

    local sort_indices = boolean_series:argsort(true)
    check(sort_indices[1] == 2 and sort_indices[2] == 4, "argsort estável: falses 2,4")

    check_error(function() return nullable_boolean_series:sort(true) end, "sort com null recusado")

    -- DataSet com coluna bool
    local source_dataset = smaug.DataSet({
        {"ativo", {true, smaug.NA, false, true}, "bool"},
        {"nome", {"SP", "RJ", "MG", "RS"}, "string"},
    })

    check(source_dataset:col("ativo")._dtype == "bool", "DataSet col dtype bool")
    check(source_dataset:dtypes().ativo == "bool", "DataSet dtypes ativo")

    local head_result = source_dataset:head(2)
    check(head_result:col("ativo")._dtype == "bool", "head preserva dtype bool")

    local description_2 = source_dataset:describe()
    check(description_2.ativo ~= nil, "describe DataSet tem ativo")
    check(description_2.ativo.count_true == 2, "describe ativo count_true")
end

-- =====================================================================
-- 14. map: Transformação elemento a elemento
-- =====================================================================
do
    -- básico: transformação inteira
    local integer_series = smaug.Series({1, 2, 3}, "int64")
    local map_result = integer_series:map(function(value) return value * 2 end)
    check(map_result._dtype == "int64", "map: dtype inferido int64")
    check(map_result:get(1) == 2, "map: valor 1")
    check(map_result:get(3) == 6, "map: valor 3")
    check(map_result:len() == 3, "map: comprimento preservado")

    -- null na entrada -> null na saída
    local nullable_integer_series = smaug.Series({1, smaug.NA, 3}, "int64")
    local map_result_2 = nullable_integer_series:map(function(value) if value == nil then return nil end return value + 10 end)
    check(map_result_2:get(1) == 11, "map: null in: valor 1 ok")
    check(map_result_2:is_null(2), "map: null in -> null out")
    check(map_result_2:get(3) == 13, "map: null in: valor 3 ok")

    -- fn retorna nil condicionalmente -> null
    local integer_series_2 = smaug.Series({5, 15, 25}, "int64")
    local conditionally_mapped_series = integer_series_2:map(function(value) if value > 10 then return value end return nil end)
    check(conditionally_mapped_series:is_null(1), "map: nil cond -> null")
    check(conditionally_mapped_series:get(2) == 15, "map: nil cond: valor 2 ok")

    -- dtype explícito prevalece
    local map_result_3 = integer_series:map(function(value) return value / 2 end, "float64")
    check(map_result_3._dtype == "float64", "map: dtype explícito float64")
    check(map_result_3:get(1) == 0.5, "map: valor com dtype explícito")

    -- inferência: float64 quando retorno tem fração
    local map_result_4 = integer_series:map(function(value) return value + 0.5 end)
    check(map_result_4._dtype == "float64", "map: inferência float64 por fração")

    -- inferência: string
    local map_result_5 = integer_series:map(function(value) return "v"..value end)
    check(map_result_5._dtype == "string", "map: inferência string")
    check(map_result_5:get(1) == "v1", "map: valor string")

    -- índice disponível na fn
    local map_result_6 = integer_series:map(function(value, row_index) return value + row_index end)
    check(map_result_6:get(1) == 2, "map: índice fn: 1+1=2")
    check(map_result_6:get(3) == 6, "map: índice fn: 3+3=6")

    -- tipo misto -> erro com índice
    local succeeded, error_message = pcall(function()
        integer_series:map(function(value) if value == 1 then return "x" end return value end)
    end)
    check(not succeeded, "map: tipo misto -> erro")
    check(error_message:find("índice") ~= nil, "map: erro aponta índice")

    -- toda-null sem dtype -> erro
    local succeeded_2 = pcall(function() integer_series:map(function() return nil end) end)
    check(not succeeded_2, "map: toda-null sem dtype -> erro")

    -- toda-null com dtype -> série null
    local map_result_7 = integer_series:map(function() return nil end, "int64")
    check(map_result_7:is_null(1) and map_result_7:is_null(3), "map: toda-null com dtype -> série null")

    -- fn não é função -> erro
    local succeeded_3 = pcall(function() integer_series:map(42) end)
    check(not succeeded_3, "map: fn não-função -> erro")

    -- imutabilidade: original intacto
    check(integer_series:get(1) == 1, "map: original imutável")
end

-- =====================================================================
-- FIM DOS TESTES
-- =====================================================================
print(string.format("OK — %d checks passaram (Series: constructors, f64, i64, bool, aritmética, lifecycle, map)", passed_checks))
