-- tests/series/test_dt.lua
-- Accessor .dt completo: componentes base, truncate, diff, add_*, comparações,
-- sort, filter, astype, integração DataSet. F.3 estendido: is_*_start/end,
-- is_leap_year, days_in_month, month_name/day_name, normalize, round/ceil, strftime.
-- Consolida: test_datetime.lua + test_dt_extended.lua
-- Baseado no padrão de test_constructors.lua.
-- Rode da raiz: luajit tests/series/test_dt.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local passed_checks = 0

local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local function check_error(callback, message)
    local succeeded = pcall(callback)
    check(not succeeded, message .. " (deveria lançar erro)")
end

local function check_error_match(callback, pattern, message)
    local succeeded, error_message = pcall(callback)
    check(not succeeded, message .. " (deveria lançar erro)")
    if not succeeded then
        check(type(error_message) == "string" and error_message:find(pattern, 1, true) ~= nil,
              message .. " (mensagem deveria conter '" .. pattern .. "')")
    end
end

local function parse_datetime(iso_timestamp)
    return smaug.Series.dt_parse(iso_timestamp)
end

local function iso_at(series_datetime, row_index)
    return series_datetime.dt:format():get(row_index)
end

-- =====================================================================
-- Épocas de referência (ms UTC)
-- =====================================================================

local reference_epoch  = smaug.Series.dt_parse("2024-01-15T12:30:00.500Z")
local march_epoch  = smaug.Series.dt_parse("2024-03-20T00:00:00Z")
local year_end_epoch  = smaug.Series.dt_parse("2024-12-31T23:59:59.999Z")
local unix_epoch = smaug.Series.dt_parse("1970-01-01T00:00:00Z")
local negative_epoch  = smaug.Series.dt_parse("1969-12-31T23:59:59Z")

local january_epoch = smaug.Series.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
local june_epoch = smaug.Series.dt_from_parts(2024, 6, 1, 0, 0, 0, 0)
local december_epoch = smaug.Series.dt_from_parts(2024, 12, 1, 0, 0, 0, 0)

do
    check(unix_epoch == 0, "epoch 1970-01-01 = 0")
    check(negative_epoch == -1000, "epoch 1969-12-31T23:59:59Z = -1000 ms")
    check(reference_epoch ~= nil, "parse 2024-01-15: não nil")
    check(march_epoch ~= nil, "parse 2024-03-20: não nil")
    check(year_end_epoch ~= nil, "parse 2024-12-31: não nil")
end

-- =====================================================================
-- 1. Factories e construção
-- =====================================================================
do
    local allocated_datetime_series = smaug.Series.new("datetime", 3)
    check(allocated_datetime_series:len() == 3, "new: len=3")
    check(allocated_datetime_series:is_null(1), "new: elemento nulo por padrão")
    check(allocated_datetime_series._dtype == "datetime", "new: dtype=datetime")

    local series_datetime = smaug.Series.datetime(2)
    check(series_datetime:len() == 2, "datetime factory: len=2")
    check(series_datetime._dtype == "datetime", "datetime factory: dtype correto")

    local series_full = smaug.Series.full(3, unix_epoch, "datetime")
    check(series_full:len() == 3, "full: len=3")
    check(series_full:get(1) == 0, "full: get(1)=0 (epoch)")
    check(series_full:get(3) == 0, "full: get(3)=0")

    local series_epochs = smaug.Series({reference_epoch, march_epoch, smaug.NA, year_end_epoch}, "datetime")
    check(series_epochs:len() == 4, "Series[num]: len=4")
    check(series_epochs:get(1) == reference_epoch, "Series[num]: get(1)=reference_epoch")
    check(series_epochs:is_null(3), "Series[num]: NA -> null")
    check(series_epochs:get(4) == year_end_epoch, "Series[num]: get(4)=year_end_epoch")

    local series_iso = smaug.Series({
        "2024-01-15T12:30:00.500Z",
        "2024-03-20T00:00:00Z",
        smaug.NA
    }, "datetime")

    check(series_iso:len() == 3, "Series[str]: len=3")
    check(series_iso:get(1) == reference_epoch, "Series[str]: parse correto reference_epoch")
    check(series_iso:get(2) == march_epoch, "Series[str]: parse correto march_epoch")
    check(series_iso:is_null(3), "Series[str]: NA -> null")

    local datetime_parse_result = smaug.Series.dt_parse("2024-06-01T00:00:00Z")
    check(datetime_parse_result ~= nil, "dt_parse: não nil")

    local datetime_format_result = smaug.Series.dt_format(datetime_parse_result)
    check(type(datetime_format_result) == "string", "dt_format: retorna string")
    check(datetime_format_result:sub(1, 10) == "2024-06-01", "dt_format: prefixo correto")

    check(smaug.Series.dt_parse("2024-01-15") ~= nil, "parse: YYYY-MM-DD")
    check(smaug.Series.dt_parse("2024-01-15T12:30:00") ~= nil, "parse: sem offset")
    check(smaug.Series.dt_parse("2024-01-15T12:30:00.500Z") ~= nil, "parse: com ms e Z")
    check(smaug.Series.dt_parse("2024-01-15T14:30:00+02:00") ~= nil, "parse: com offset +")
    check(smaug.Series.dt_parse("formato-invalido") == nil, "parse: inválido -> nil")
    check(smaug.Series.dt_parse("") == nil, "parse: vazio -> nil")

    local epoch_parts = smaug.Series.dt_from_parts(2024, 1, 15, 12, 30, 0, 500)
    check(epoch_parts == reference_epoch, "dt_from_parts: bate com parse ISO")

    local epoch_mid = smaug.Series.dt_from_parts(1970, 1, 1, 0, 0, 0, 0)
    check(epoch_mid == 0, "dt_from_parts: epoch zero")

    check(smaug.Series.dt_from_parts(2024, 13, 1) == nil, "dt_from_parts: mês inválido -> nil")
    check(smaug.Series.dt_from_parts(2024, 2, 30) == nil, "dt_from_parts: dia inválido -> nil")
end

-- =====================================================================
-- 2. Acesso e mutação
-- =====================================================================
do
    local allocated_datetime_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "datetime")
    allocated_datetime_series:set(1, reference_epoch)
    allocated_datetime_series:set(2, "2024-03-20T00:00:00Z")
    allocated_datetime_series:set_null(3)

    check(allocated_datetime_series:get(1) == reference_epoch, "set/get: epoch_ms")
    check(allocated_datetime_series:get(2) == march_epoch, "set via string ISO 8601")
    check(allocated_datetime_series:get(3) == nil, "set_null -> get=nil")
    check(allocated_datetime_series:is_null(3), "is_null após set_null")
    check(not allocated_datetime_series:is_null(1), "is_null false após set")

    local allocated_datetime_series_2 = smaug.Series({}, "datetime")
    allocated_datetime_series_2:append(unix_epoch)
    allocated_datetime_series_2:append("1970-01-01T00:00:00Z")

    check(allocated_datetime_series_2:len() == 2, "append: len=2")
    check(allocated_datetime_series_2:get(1) == 0, "append epoch_ms")
    check(allocated_datetime_series_2:get(2) == 0, "append string ISO")

    local nullable_datetime_series = smaug.Series({reference_epoch, smaug.NA, march_epoch, smaug.NA, year_end_epoch}, "datetime")
    check(nullable_datetime_series:count_nonnull() == 3, "count_nonnull: 3")
end

-- =====================================================================
-- 3. Accessor .dt — componentes calendário
-- =====================================================================
do
    local datetime_series = smaug.Series({reference_epoch}, "datetime")

    check(datetime_series.dt:year():get(1) == 2024, "dt:year()")
    check(datetime_series.dt:month():get(1) == 1, "dt:month() = 1 (janeiro)")
    check(datetime_series.dt:day():get(1) == 15, "dt:day() = 15")
    check(datetime_series.dt:hour():get(1) == 12, "dt:hour() = 12")
    check(datetime_series.dt:minute():get(1) == 30, "dt:minute() = 30")
    check(datetime_series.dt:second():get(1) == 0, "dt:second() = 0")
    check(datetime_series.dt:ms():get(1) == 500, "dt:ms() = 500")
    check(datetime_series.dt:weekday():get(1) == 0, "dt:weekday() = 0 (seg)")
    check(datetime_series.dt:quarter():get(1) == 1, "dt:quarter() = 1 (Q1)")

    local datetime_series_2 = smaug.Series({march_epoch}, "datetime")
    check(datetime_series_2.dt:month():get(1) == 3, "dt:month() = 3 (março)")
    check(datetime_series_2.dt:day():get(1) == 20, "dt:day() = 20")
    check(datetime_series_2.dt:quarter():get(1) == 1, "dt:quarter() = 1 (mar ainda Q1)")

    local datetime_series_3 = smaug.Series({year_end_epoch}, "datetime")
    check(datetime_series_3.dt:year():get(1) == 2024, "dt:year() dec")
    check(datetime_series_3.dt:month():get(1) == 12, "dt:month() = 12")
    check(datetime_series_3.dt:day():get(1) == 31, "dt:day() = 31")
    check(datetime_series_3.dt:quarter():get(1) == 4, "dt:quarter() = 4 (Q4)")

    local nullable_datetime_series = smaug.Series({reference_epoch, smaug.NA, march_epoch}, "datetime")
    check(nullable_datetime_series.dt:year():is_null(2), "year: NA propaga")
    check(nullable_datetime_series.dt:month():is_null(2), "month: NA propaga")
    check(nullable_datetime_series.dt:day():is_null(2), "day: NA propaga")

    local year_result = nullable_datetime_series.dt:year()
    check(year_result._dtype == "int64", "dt:year() -> Series<int64>")
    check(year_result:get(1) == 2024, "dt:year()[1] = 2024")
    check(year_result:get(3) == 2024, "dt:year()[3] = 2024")
end

-- =====================================================================
-- 4. format() e truncate()
-- =====================================================================
do
    local series_fmt = smaug.Series({unix_epoch, smaug.NA, reference_epoch}, "datetime")
    local format_result = series_fmt.dt:format()

    check(format_result._dtype == "string", "format: dtype=string")
    check(format_result:get(1) == "1970-01-01T00:00:00.000Z", "format: epoch zero")
    check(format_result:is_null(2), "format: NA -> null")
    check(format_result:get(3):sub(1, 10) == "2024-01-15", "format: ep_ref prefixo")

    local nullable_datetime_series = smaug.Series({reference_epoch, smaug.NA}, "datetime")

    local day_truncated_series = nullable_datetime_series.dt:truncate("D")
    check(day_truncated_series._dtype == "datetime", "truncate: dtype=datetime")
    check(day_truncated_series:is_null(2), "truncate: NA propaga")

    local first_truncated_day = day_truncated_series:get(1)
    check(first_truncated_day ~= nil, "truncate D: não nil")

    local epoch_day = smaug.Series.dt_from_parts(2024, 1, 15, 0, 0, 0, 0)
    check(first_truncated_day == epoch_day, "truncate D: meia-noite correta")

    local month_truncated_series = nullable_datetime_series.dt:truncate("M")
    local epoch_month = smaug.Series.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
    check(month_truncated_series:get(1) == epoch_month, "truncate M: 1º do mês")

    local year_truncated_series = nullable_datetime_series.dt:truncate("Y")
    local epoch_year = smaug.Series.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
    check(year_truncated_series:get(1) == epoch_year, "truncate Y: 1º de jan")

    local hour_truncated_series = nullable_datetime_series.dt:truncate("h")
    local epoch_hour = smaug.Series.dt_from_parts(2024, 1, 15, 12, 0, 0, 0)
    check(hour_truncated_series:get(1) == epoch_hour, "truncate h: hora inteira")
end

-- =====================================================================
-- 5. diff() e add_*
-- =====================================================================
do
    local milliseconds_per_day = 86400000

    local epoch_d1 = smaug.Series.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
    local epoch_d2 = smaug.Series.dt_from_parts(2024, 1, 2, 0, 0, 0, 0)
    local epoch_d3 = smaug.Series.dt_from_parts(2024, 1, 4, 0, 0, 0, 0)

    local datetime_series = smaug.Series({epoch_d1, epoch_d2, epoch_d3}, "datetime")
    local diffs = datetime_series.dt:diff()

    check(diffs._dtype == "int64", "diff: dtype=int64")
    check(diffs:is_null(1), "diff: primeiro elemento = null")
    check(diffs:get(2) == milliseconds_per_day, "diff[2] = 1 dia em ms")
    check(diffs:get(3) == 2 * milliseconds_per_day, "diff[3] = 2 dias em ms")

    local diff_result = datetime_series.dt:diff(2)
    check(diff_result:is_null(1), "diff(2)[1] = null")
    check(diff_result:is_null(2), "diff(2)[2] = null")
    check(diff_result:get(3) == 3 * milliseconds_per_day, "diff(2)[3] = 3 dias")

    local nullable_datetime_series = smaug.Series({epoch_d1, smaug.NA, epoch_d3}, "datetime")
    local diff_result_2 = nullable_datetime_series.dt:diff()

    check(diff_result_2:is_null(1), "diff NA: [1] null")
    check(diff_result_2:is_null(2), "diff NA: [2] null (era NA)")
    check(diff_result_2:is_null(3), "diff NA: [3] null (b era NA)")

    local nullable_datetime_series_2 = smaug.Series({unix_epoch, smaug.NA}, "datetime")

    local added = nullable_datetime_series_2.dt:add_ms(1000)
    check(added:get(1) == 1000, "add_ms: epoch+1000ms")
    check(added:is_null(2), "add_ms: NA propaga")

    local add_days_result = nullable_datetime_series_2.dt:add_days(1)
    check(add_days_result:get(1) == milliseconds_per_day, "add_days(1): +1 dia em ms")

    local add_hours_result = nullable_datetime_series_2.dt:add_hours(2)
    check(add_hours_result:get(1) == 2 * 3600000, "add_hours(2)")

    local add_minutes_result = nullable_datetime_series_2.dt:add_minutes(90)
    check(add_minutes_result:get(1) == 90 * 60000, "add_minutes(90)")

    local added_seconds_series = nullable_datetime_series_2.dt:add_seconds(30)
    check(added_seconds_series:get(1) == 30 * 1000, "add_seconds(30)")
end

-- =====================================================================
-- 6. Comparações -> Series<bool>
-- =====================================================================
do
    local comparison_series = smaug.Series({january_epoch, june_epoch, december_epoch, smaug.NA}, "datetime")
    local pivot = june_epoch

    local greater_than_mask = comparison_series:gt(pivot)
    check(greater_than_mask._dtype == "bool", "gt: dtype=bool")
    check(greater_than_mask:get(1) == false, "gt: jan > jun = false")
    check(greater_than_mask:get(2) == false, "gt: jun > jun = false")
    check(greater_than_mask:get(3) == true, "gt: dec > jun = true")
    check(greater_than_mask:is_null(4), "gt: NA -> NA")

    local less_than_mask = comparison_series:lt(pivot)
    check(less_than_mask:get(1) == true, "lt: jan < jun = true")
    check(less_than_mask:get(2) == false, "lt: jun < jun = false")
    check(less_than_mask:get(3) == false, "lt: dec < jun = false")

    local equality_mask = comparison_series:eq(pivot)
    check(equality_mask:get(1) == false, "eq: jan == jun = false")
    check(equality_mask:get(2) == true, "eq: jun == jun = true")

    local greater_or_equal_mask = comparison_series:ge(pivot)
    check(greater_or_equal_mask:get(1) == false, "ge: jan >= jun = false")
    check(greater_or_equal_mask:get(2) == true, "ge: jun >= jun = true")
    check(greater_or_equal_mask:get(3) == true, "ge: dec >= jun = true")

    local less_or_equal_mask = comparison_series:le(pivot)
    check(less_or_equal_mask:get(1) == true, "le: jan <= jun = true")
    check(less_or_equal_mask:get(2) == true, "le: jun <= jun = true")
    check(less_or_equal_mask:get(3) == false, "le: dec <= jun = false")

    local inequality_mask = comparison_series:ne(pivot)
    check(inequality_mask:get(1) == true, "ne: jan != jun = true")
    check(inequality_mask:get(2) == false, "ne: jun != jun = false")
end

-- =====================================================================
-- 7. Ordenação e seleção
-- =====================================================================
do
    local unsorted_datetime_series = smaug.Series({december_epoch, january_epoch, june_epoch}, "datetime")

    local sorted = unsorted_datetime_series:sort(true)
    check(sorted:get(1) == january_epoch, "sort asc: 1º = jan")
    check(sorted:get(2) == june_epoch, "sort asc: 2º = jun")
    check(sorted:get(3) == december_epoch, "sort asc: 3º = dec")

    local sortd = unsorted_datetime_series:sort(false)
    check(sortd:get(1) == december_epoch, "sort desc: 1º = dec")
    check(sortd:get(3) == january_epoch, "sort desc: 3º = jan")

    local nullable_unsorted_series = smaug.Series({june_epoch, smaug.NA, january_epoch}, "datetime")
    check_error(function() nullable_unsorted_series:sort(true) end, "sort com null")

    local indices = unsorted_datetime_series:argsort(true)
    check(type(indices) == "table", "argsort: retorna tabela")
    check(indices[1] == 2, "argsort asc: 1º idx=2 (ep_a)")
    check(indices[2] == 3, "argsort asc: 2º idx=3 (ep_b)")
    check(indices[3] == 1, "argsort asc: 3º idx=1 (ep_c)")

    check(nullable_unsorted_series:argsort(true) == nil, "argsort com null: nil")

    local selected_result = unsorted_datetime_series:take({2, 1})
    check(selected_result:len() == 2, "take: len=2")
    check(selected_result:get(1) == january_epoch, "take: 1º = ep_a (era idx 2)")
    check(selected_result:get(2) == december_epoch, "take: 2º = ep_c (era idx 1)")

    local shead = unsorted_datetime_series:head(2)
    check(shead:len() == 2, "head(2): len=2")
    check(shead:get(1) == december_epoch, "head(2): 1º = ep_c")

    local stail = unsorted_datetime_series:tail(1)
    check(stail:len() == 1, "tail(1): len=1")
    check(stail:get(1) == june_epoch, "tail(1): 1º = ep_b")

    local interleaved_null_series = smaug.Series({january_epoch, smaug.NA, june_epoch, smaug.NA, december_epoch}, "datetime")
    local dropped = interleaved_null_series:dropna()

    check(dropped:len() == 3, "dropna: len=3")
    check(dropped:get(1) == january_epoch, "dropna: 1º = ep_a")
    check(dropped:get(3) == december_epoch, "dropna: 3º = ep_c")

    local greater_than_mask = interleaved_null_series:gt(january_epoch)
    local filtered = interleaved_null_series:filter(greater_than_mask)

    check(filtered:len() == 2, "filter gt: len=2 (jun e dec)")
    check(filtered:get(1) == june_epoch, "filter gt: 1º = ep_b")
    check(filtered:get(2) == december_epoch, "filter gt: 2º = ep_c")

    check_error(function() interleaved_null_series:gt("2024-01-01") end, "gt: string como target")
    check_error(function() interleaved_null_series:lt(true) end, "lt: boolean como target")
    check_error(function() interleaved_null_series:eq(nil) end, "eq: nil como target")

    local cloned_series = unsorted_datetime_series:clone()
    cloned_series:set(1, unix_epoch)
    check(unsorted_datetime_series:get(1) == december_epoch, "clone: original intacto")

    local sv_base = smaug.Series({january_epoch, june_epoch, december_epoch}, "datetime")
    local series_view = sv_base:view(2, 2)

    check(series_view:len() == 2, "dt view: len da janela = 2")
    check(series_view:get(1) == june_epoch, "dt view: 1º = ep_b")
    check(series_view:get(2) == december_epoch, "dt view: 2º = ep_c")

    series_view:set(1, unix_epoch)
    check(series_view:get(1) == unix_epoch, "dt view: escrita reflete na view")
    check(sv_base:get(2) == june_epoch, "dt view: detach COW — pai intacto após escrita")

    check_error(function() sv_base:view(2, 5) end, "dt view: fora dos limites")

    -- dayfirst na API pública
    check(smaug.Series.dt_parse("2026-06-13") == smaug.Series.dt_parse("2026-06-13", true),
          "dt_parse year-first ignora dayfirst")

    check(smaug.Series.dt_parse("13/06/2026", true) == smaug.Series.dt_parse("2026-06-13"),
          "dt_parse DD/MM (dayfirst=true)")

    check(smaug.Series.dt_parse("06/13/2026") == smaug.Series.dt_parse("2026-06-13"),
          "dt_parse MM/DD (default)")

    check(smaug.Series.dt_parse("13/06/2026") == nil,
          "dt_parse 13/06 sem dayfirst -> nil (falha visível)")

    check(smaug.Series.dt_parse("5/6/2026", true) == smaug.Series.dt_parse("2026-06-05"),
          "dt_parse 5/6 dayfirst=true = 5 jun")

    local sd_day = smaug.Series({"13/06/2026", "25/12/2026"}, "string")
    local converted_series = sd_day:astype("datetime", {dayfirst = true})

    check(converted_series:get(1) == smaug.Series.dt_parse("2026-06-13"),
          "astype datetime dayfirst=true: 13/06 -> 13 jun")

    check(converted_series:get(2) == smaug.Series.dt_parse("2026-12-25"),
          "astype datetime dayfirst=true: 25/12 -> natal")

    local sd_default = smaug.Series({"13/06/2026"}, "string")
    local conv2 = sd_default:astype("datetime")

    check(conv2:is_null(1),
          "astype datetime default: 13/06 -> null (MM/DD, mês 13 inválido)")

    local sd_name = smaug.Series({"2026-06-13"}, "string")
    local conv3 = sd_name:astype("datetime", "nome_custom")

    check(conv3._name == "nome_custom",
          "astype 3º arg string = name (retrocompat)")
end

-- =====================================================================
-- 8. fillna / is_null
-- =====================================================================
do
    local series_fill = smaug.Series({january_epoch, smaug.NA, smaug.NA, december_epoch}, "datetime")
    local filled = series_fill:fillna(june_epoch)

    check(filled:get(1) == january_epoch, "fillna: não-nulo intacto")
    check(filled:get(2) == june_epoch, "fillna: NA preenchido")
    check(filled:get(3) == june_epoch, "fillna: NA preenchido [3]")
    check(filled:get(4) == december_epoch, "fillna: não-nulo intacto [4]")

    check(series_fill:is_null(2), "fillna: original não mutado")
end

-- =====================================================================
-- 9. astype
-- =====================================================================
do
    local nullable_datetime_series = smaug.Series({unix_epoch, smaug.NA}, "datetime")

    local as_string = nullable_datetime_series:astype("string")
    check(as_string._dtype == "string", "astype dt->str: dtype")
    check(as_string:get(1) == "1970-01-01T00:00:00.000Z", "astype dt->str: epoch zero")
    check(as_string:is_null(2), "astype dt->str: NA -> null")

    local as_int64 = nullable_datetime_series:astype("int64")
    check(as_int64._dtype == "int64", "astype dt->i64: dtype")
    check(as_int64:get(1) == 0, "astype dt->i64: epoch zero = 0")
    check(as_int64:is_null(2), "astype dt->i64: NA -> null")

    local nullable_integer_series = smaug.Series({0, smaug.NA, reference_epoch}, "int64")
    local as_datetime = nullable_integer_series:astype("datetime")

    check(as_datetime._dtype == "datetime", "astype i64->dt: dtype")
    check(as_datetime:get(1) == 0, "astype i64->dt: 0 = epoch")
    check(as_datetime:is_null(2), "astype i64->dt: NA -> null")
    check(as_datetime:get(3) == reference_epoch, "astype i64->dt: ep_ref")

    local nullable_string_series = smaug.Series({
        "2024-01-15T12:30:00.500Z",
        smaug.NA,
        "invalido"
    }, "string")

    local as_dt2 = nullable_string_series:astype("datetime")

    check(as_dt2._dtype == "datetime", "astype str->dt: dtype")
    check(as_dt2:get(1) == reference_epoch, "astype str->dt: parse correto")
    check(as_dt2:is_null(2), "astype str->dt: NA -> null")
    check(as_dt2:is_null(3), "astype str->dt: inválido -> null")
end

-- =====================================================================
-- 10. describe
-- =====================================================================
do
    local descending_dataset = smaug.Series({january_epoch, smaug.NA, june_epoch, december_epoch}, "datetime")
    local description = descending_dataset:describe()

    check(type(description) == "table", "describe: retorna tabela")
    check(description.dtype == "datetime", "describe: dtype=datetime")
    check(description.count == 3, "describe: count=3 (sem NA)")
    check(description.nulls == 1, "describe: nulls=1")
    check(type(description.min) == "string", "describe: min é string ISO")
    check(type(description.max) == "string", "describe: max é string ISO")
    check(description.min:sub(1, 10) == "2024-01-01", "describe: min = jan")
    check(description.max:sub(1, 10) == "2024-12-01", "describe: max = dez")
end

-- =====================================================================
-- 11. Integração com DataSet
-- =====================================================================
do
    local source_dataset = smaug.DataSet({
        {"data", {
            "2024-01-15T12:30:00.500Z",
            "2024-03-20T00:00:00Z",
            "2024-12-31T23:59:59.999Z"
        }, "datetime"},
        {"valor", {10.0, 20.0, 30.0}, "float64"},
    })

    check(source_dataset:has_column("data"), "DataSet: coluna datetime existe")
    check(source_dataset:col("data")._dtype == "datetime", "DataSet: dtype correto")

    local year_series = source_dataset:col("data").dt:year()
    check(year_series:get(1) == 2024, "DataSet .dt:year()[1] = 2024")
    check(year_series:get(2) == 2024, "DataSet .dt:year()[2] = 2024")

    local pivot2 = smaug.Series.dt_from_parts(2024, 6, 1, 0, 0, 0, 0)
    local mask2 = source_dataset:col("data"):gt(pivot2)
    local filtered_result = source_dataset:filter(mask2)

    check(filtered_result:nrows() == 1, "DataSet filter por data: 1 linha")
    check(filtered_result:col("valor"):get(1) == 30.0, "DataSet filter: linha correta")

    local sorted_dataset = source_dataset:sort_by("data", false)
    check(sorted_dataset:col("valor"):get(1) == 30.0, "sort_by data desc: 1º = dez")
    check(sorted_dataset:col("valor"):get(3) == 10.0, "sort_by data desc: 3º = jan")

    local assign_result = source_dataset:assign("mes", source_dataset:col("data").dt:month())
    check(assign_result:has_column("mes"), "assign: coluna mes criada")
    check(assign_result:col("mes"):get(1) == 1, "assign: mes[1] = 1")
    check(assign_result:col("mes"):get(2) == 3, "assign: mes[2] = 3")

    local selected_dataset = source_dataset:select({"data", "valor"})
    check(selected_dataset:col("data")._dtype == "datetime", "select: datetime preservado")

    local head_result = source_dataset:head(2)
    check(head_result:nrows() == 2, "DataSet head: 2 linhas")
    check(head_result:col("data")._dtype == "datetime", "DataSet head: dtype preservado")

    local source_dataset_2 = smaug.DataSet({
        {"data", {january_epoch, smaug.NA, june_epoch}, "datetime"},
        {"v", {1.0, 2.0, 3.0}, "float64"},
    })

    local non_null_result = source_dataset_2:dropna()
    check(non_null_result:nrows() == 2, "DataSet dropna: 2 linhas")

    local ddesc = source_dataset:describe()
    check(type(ddesc) == "table", "DataSet describe com datetime: não explode")
    check(ddesc["data"] ~= nil, "DataSet describe: coluna data presente")
    check(ddesc["data"].dtype == "datetime", "DataSet describe: dtype=datetime na coluna")
end

-- =====================================================================
-- 12. Erros esperados
-- =====================================================================
do
    check_error_match(
        function()
            smaug.Series({1.0, 2.0}, "float64").dt:year()
        end,
        "datetime",
        "erro: .dt em float64"
    )

    local allocated_datetime_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "datetime")
    check_error(function() allocated_datetime_series:set(1, "nao-e-data") end, "set com string inválida")

    check_error(
        function()
            smaug.Series({"2024-01-15", "INVALIDO"}, "datetime")
        end,
        "Series: string de data inválida"
    )

    check_error(
        function()
            local allocated_datetime_series_2 = smaug.Series({}, "datetime")
            allocated_datetime_series_2:append("nao-e-data")
        end,
        "append string inválida"
    )

    check(smaug.Series.dt_from_parts(2024, 0, 1) == nil, "dt_from_parts: mês=0 -> nil")
    check(smaug.Series.dt_from_parts(2024, 1, 0) == nil, "dt_from_parts: dia=0 -> nil")
    check(smaug.Series.dt_from_parts(2024, 1, 1, 25, 0, 0) == nil, "dt_from_parts: hora=25 -> nil")
end

-- =====================================================================
-- F.3.1 is_month_start / is_month_end
-- =====================================================================
do
    local month_boundary_series = smaug.Series({
        parse_datetime("2024-01-01T00:00:00Z"),
        parse_datetime("2024-02-29T12:00:00Z"),
        parse_datetime("2024-03-15T00:00:00Z"),
        parse_datetime("2025-02-28T00:00:00Z"),
        smaug.NA,
    }, "datetime")

    local is_month_start_result = month_boundary_series.dt:is_month_start()
    check(is_month_start_result._dtype == "bool", "is_month_start -> bool")
    check(is_month_start_result:get(1) == true, "is_month_start[1]=01 -> true")
    check(is_month_start_result:get(2) == false, "is_month_start[2]=29 -> false")
    check(is_month_start_result:get(5) == nil, "is_month_start[5]=NA -> nil")

    local is_month_end_result = month_boundary_series.dt:is_month_end()
    check(is_month_end_result:get(2) == true, "is_month_end[2]=29 fev bissexto -> true")
    check(is_month_end_result:get(3) == false, "is_month_end[3]=15 -> false")
    check(is_month_end_result:get(4) == true, "is_month_end[4]=28 fev não-bissexto -> true")
end

-- =====================================================================
-- F.3.2 is_quarter_start / is_quarter_end
-- =====================================================================
do
    local quarter_boundary_series = smaug.Series({
        parse_datetime("2024-01-01T00:00:00Z"),
        parse_datetime("2024-04-01T00:00:00Z"),
        parse_datetime("2024-03-31T00:00:00Z"),
        parse_datetime("2024-12-31T00:00:00Z"),
        parse_datetime("2024-05-15T00:00:00Z"),
    }, "datetime")

    local is_quarter_start_result = quarter_boundary_series.dt:is_quarter_start()
    check(is_quarter_start_result:get(1) == true, "is_quarter_start jan-01 -> true")
    check(is_quarter_start_result:get(2) == true, "is_quarter_start abr-01 -> true")
    check(is_quarter_start_result:get(5) == false, "is_quarter_start mai-15 -> false")

    local is_quarter_end_result = quarter_boundary_series.dt:is_quarter_end()
    check(is_quarter_end_result:get(3) == true, "is_quarter_end mar-31 -> true")
    check(is_quarter_end_result:get(4) == true, "is_quarter_end dez-31 -> true")
    check(is_quarter_end_result:get(1) == false, "is_quarter_end jan-01 -> false")
end

-- =====================================================================
-- F.3.3 is_year_start / is_year_end
-- =====================================================================
do
    local year_boundary_series = smaug.Series({
        parse_datetime("2024-01-01T00:00:00Z"),
        parse_datetime("2024-12-31T00:00:00Z"),
        parse_datetime("2024-06-15T00:00:00Z"),
    }, "datetime")

    check(year_boundary_series.dt:is_year_start():get(1) == true, "is_year_start jan-01 -> true")
    check(year_boundary_series.dt:is_year_start():get(2) == false, "is_year_start dez-31 -> false")
    check(year_boundary_series.dt:is_year_end():get(2) == true, "is_year_end dez-31 -> true")
    check(year_boundary_series.dt:is_year_end():get(3) == false, "is_year_end jun-15 -> false")
end

-- =====================================================================
-- F.3.4 is_leap_year
-- =====================================================================
do
    local leap_year_series = smaug.Series({
        parse_datetime("2024-06-01T00:00:00Z"),
        parse_datetime("2023-06-01T00:00:00Z"),
        parse_datetime("2000-06-01T00:00:00Z"),
        parse_datetime("1900-06-01T00:00:00Z"),
    }, "datetime")

    local is_leap_year_result = leap_year_series.dt:is_leap_year()
    check(is_leap_year_result:get(1) == true, "is_leap_year 2024 -> true")
    check(is_leap_year_result:get(2) == false, "is_leap_year 2023 -> false")
    check(is_leap_year_result:get(3) == true, "is_leap_year 2000 -> true (regra ÷400)")
    check(is_leap_year_result:get(4) == false, "is_leap_year 1900 -> false (secular não-÷400)")
end

-- =====================================================================
-- F.3.5 days_in_month
-- =====================================================================
do
    local month_length_series = smaug.Series({
        parse_datetime("2024-01-15T00:00:00Z"),
        parse_datetime("2024-02-15T00:00:00Z"),
        parse_datetime("2025-02-15T00:00:00Z"),
        parse_datetime("2024-04-15T00:00:00Z"),
    }, "datetime")

    local days_in_month_result = month_length_series.dt:days_in_month()
    check(days_in_month_result._dtype == "int64", "days_in_month -> int64")
    check(days_in_month_result:get(1) == 31, "days_in_month jan -> 31")
    check(days_in_month_result:get(2) == 29, "days_in_month fev-2024 -> 29")
    check(days_in_month_result:get(3) == 28, "days_in_month fev-2025 -> 28")
    check(days_in_month_result:get(4) == 30, "days_in_month abr -> 30")
end

-- =====================================================================
-- F.3.6 month_name / day_name
-- =====================================================================
do
    local named_date_series = smaug.Series({
        parse_datetime("2024-01-01T00:00:00Z"),
        parse_datetime("2024-07-04T00:00:00Z"),
        parse_datetime("2024-12-25T00:00:00Z"),
    }, "datetime")

    local month_name_result = named_date_series.dt:month_name()
    check(month_name_result._dtype == "string", "month_name -> string")
    check(month_name_result:get(1) == "January", "month_name jan -> January")
    check(month_name_result:get(2) == "July", "month_name jul -> July")
    check(month_name_result:get(3) == "December", "month_name dez -> December")

    local day_name_result = named_date_series.dt:day_name()
    check(day_name_result:get(1) == "Monday", "day_name 2024-01-01 -> Monday")
    check(day_name_result:get(2) == "Thursday", "day_name 2024-07-04 -> Thursday")
    check(day_name_result:get(3) == "Wednesday", "day_name 2024-12-25 -> Wednesday")
end

-- =====================================================================
-- F.3.7 normalize (= truncate D)
-- =====================================================================
do
    local normalization_series = smaug.Series({
        parse_datetime("2024-06-15T14:30:45Z"),
        parse_datetime("2024-06-15T00:00:00Z"),
        smaug.NA,
    }, "datetime")

    local normalize_result = normalization_series.dt:normalize()
    check(normalize_result._dtype == "datetime", "normalize -> datetime")
    check(iso_at(normalize_result, 1) == "2024-06-15T00:00:00.000Z", "normalize zera hora")
    check(iso_at(normalize_result, 2) == "2024-06-15T00:00:00.000Z", "normalize idempotente")
    check(normalize_result:get(3) == nil, "normalize NA -> nil")
end

-- =====================================================================
-- F.3.8 ceil — menor início-de-período >= v
-- =====================================================================
do
    local hour_ceiling_series = smaug.Series({
        parse_datetime("2024-06-15T10:20:00Z"),
        parse_datetime("2024-06-15T10:00:00Z"),
    }, "datetime")

    local hour_ceiling_series = hour_ceiling_series.dt:ceil("h")
    check(iso_at(hour_ceiling_series, 1) == "2024-06-15T11:00:00.000Z", "ceil h 10:20 -> 11:00")
    check(iso_at(hour_ceiling_series, 2) == "2024-06-15T10:00:00.000Z", "ceil h alinhado -> mesmo")

    local month_ceiling_series = smaug.Series({
        parse_datetime("2024-01-10T00:00:00Z"),
        parse_datetime("2024-12-20T00:00:00Z"),
        parse_datetime("2024-03-01T00:00:00Z"),
    }, "datetime")

    local month_ceiling_series = month_ceiling_series.dt:ceil("M")
    check(iso_at(month_ceiling_series, 1) == "2024-02-01T00:00:00.000Z", "ceil M jan-10 -> fev-01")
    check(iso_at(month_ceiling_series, 2) == "2025-01-01T00:00:00.000Z", "ceil M dez-20 -> 2025-jan-01")
    check(iso_at(month_ceiling_series, 3) == "2024-03-01T00:00:00.000Z", "ceil M alinhado -> mesmo")

    local quarter_ceiling_series = smaug.Series({parse_datetime("2024-02-15T00:00:00Z")}, "datetime")
    check(iso_at(quarter_ceiling_series.dt:ceil("Q"), 1) == "2024-04-01T00:00:00.000Z", "ceil Q fev -> abr-01")
    check(iso_at(quarter_ceiling_series.dt:ceil("Y"), 1) == "2025-01-01T00:00:00.000Z", "ceil Y 2024 -> 2025-01-01")

    check_error(function() quarter_ceiling_series.dt:ceil("X") end, "ceil unidade inválida")
end

-- =====================================================================
-- F.3.9 round — período mais próximo (half-up no empate)
-- =====================================================================
do
    local hour_rounding_series = smaug.Series({
        parse_datetime("2024-06-15T10:20:00Z"),
        parse_datetime("2024-06-15T10:40:00Z"),
        parse_datetime("2024-06-15T10:30:00Z"),
    }, "datetime")

    local hour_rounded_series = hour_rounding_series.dt:round("h")
    check(iso_at(hour_rounded_series, 1) == "2024-06-15T10:00:00.000Z", "round h 10:20 -> 10:00")
    check(iso_at(hour_rounded_series, 2) == "2024-06-15T11:00:00.000Z", "round h 10:40 -> 11:00")
    check(iso_at(hour_rounded_series, 3) == "2024-06-15T11:00:00.000Z", "round h 10:30 empate -> 11:00 (half-up)")

    local day_rounding_series = smaug.Series({
        parse_datetime("2024-06-15T05:00:00Z"),
        parse_datetime("2024-06-15T20:00:00Z"),
    }, "datetime")

    local day_rounded_series = day_rounding_series.dt:round("D")
    check(iso_at(day_rounded_series, 1) == "2024-06-15T00:00:00.000Z", "round D 05h -> mesmo dia")
    check(iso_at(day_rounded_series, 2) == "2024-06-16T00:00:00.000Z", "round D 20h -> próximo dia")
end

-- =====================================================================
-- F.3.10 strftime
-- =====================================================================
do
    local series_strftime = smaug.Series({parse_datetime("2024-02-05T14:09:07Z")}, "datetime")

    local strftime_result = series_strftime.dt:strftime("%Y-%m-%d %H:%M:%S")
    check(strftime_result._dtype == "string", "strftime -> string")
    check(strftime_result:get(1) == "2024-02-05 14:09:07", "strftime ISO básico")

    check(series_strftime.dt:strftime("%A"):get(1) == "Monday", "strftime %A -> Monday")
    check(series_strftime.dt:strftime("%a"):get(1) == "Mon", "strftime %a -> Mon")
    check(series_strftime.dt:strftime("%B"):get(1) == "February", "strftime %B -> February")
    check(series_strftime.dt:strftime("%b"):get(1) == "Feb", "strftime %b -> Feb")
    check(series_strftime.dt:strftime("%y"):get(1) == "24", "strftime %y -> 24")
    check(series_strftime.dt:strftime("%j"):get(1) == "036", "strftime %j -> 036 (dia do ano)")
    check(series_strftime.dt:strftime("%I%p"):get(1) == "02PM", "strftime %I%p -> 02PM")
    check(series_strftime.dt:strftime("100%%"):get(1) == "100%", "strftime %% -> %")
    check(series_strftime.dt:strftime("%Z"):get(1) == "%Z", "strftime token desconhecido -> literal")

    local midnight_series = smaug.Series({
        parse_datetime("2024-01-01T00:00:00Z"),
        parse_datetime("2024-01-01T12:00:00Z")
    }, "datetime")

    check(midnight_series.dt:strftime("%I %p"):get(1) == "12 AM", "strftime meia-noite -> 12 AM")
    check(midnight_series.dt:strftime("%I %p"):get(2) == "12 PM", "strftime meio-dia -> 12 PM")

    local all_null_datetime_series = smaug.Series({smaug.NA}, "datetime")
    check(all_null_datetime_series.dt:strftime("%Y"):get(1) == nil, "strftime NA -> nil")

    check_error(function() series_strftime.dt:strftime(42) end, "strftime fmt não-string")
end

-- =====================================================================
-- Resultado
-- =====================================================================
do
    local source_series = smaug.Series({"02/05/2026"}, "string")
    for _, invalid_option in ipairs({"false", 0, 1}) do
        check_error_match(function()
            smaug.Series.dt_parse("02/05/2026", invalid_option)
        end, "dayfirst", "dt_parse rejeita dayfirst não-booleano")
        check_error_match(function()
            source_series:astype("datetime", {dayfirst = invalid_option})
        end, "dayfirst", "astype rejeita dayfirst não-booleano")
    end
end

print(string.format("OK — %d checks passaram (Series: .dt base + F.3 estendido)", passed_checks))
