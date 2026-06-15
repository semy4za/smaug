-- tests/test_dt_extended.lua
-- Bloco F.3 — accessor .dt estendido.
--   Predicados: is_month/quarter/year_start/end, is_leap_year
--   Calendário: days_in_month, month_name, day_name, normalize
--   Período: round, ceil (complementam truncate = floor)
--   Formatação: strftime
--
-- Roda da raiz: luajit tests/test_dt_extended.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")
local S  = smaug.Series
local NA = smaug.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

local function P(iso) return S.dt_parse(iso) end

-- Helper: extrai a string ISO de um único elemento datetime (via .dt:format).
local function iso_of(series_dt, i)
    return series_dt.dt:format():get(i)
end

-- ================================================================
-- 1. is_month_start / is_month_end
-- ================================================================

local m = S.from_table({
    P("2024-01-01T00:00:00Z"),  -- start
    P("2024-02-29T12:00:00Z"),  -- end (bissexto)
    P("2024-03-15T00:00:00Z"),  -- meio
    P("2025-02-28T00:00:00Z"),  -- end (não-bissexto)
    NA,
}, "datetime")

local ms = m.dt:is_month_start()
check(ms._dtype == "bool",          "is_month_start → bool")
check(ms:get(1) == true,            "is_month_start[1]=01 → true")
check(ms:get(2) == false,           "is_month_start[2]=29 → false")
check(ms:get(5) == nil,             "is_month_start[5]=NA → nil")

local me = m.dt:is_month_end()
check(me:get(2) == true,            "is_month_end[2]=29 fev bissexto → true")
check(me:get(3) == false,           "is_month_end[3]=15 → false")
check(me:get(4) == true,            "is_month_end[4]=28 fev não-bissexto → true")

-- ================================================================
-- 2. is_quarter_start / is_quarter_end
-- ================================================================

local q = S.from_table({
    P("2024-01-01T00:00:00Z"),  -- Q1 start
    P("2024-04-01T00:00:00Z"),  -- Q2 start
    P("2024-03-31T00:00:00Z"),  -- Q1 end
    P("2024-12-31T00:00:00Z"),  -- Q4 end
    P("2024-05-15T00:00:00Z"),  -- meio
}, "datetime")

local qs = q.dt:is_quarter_start()
check(qs:get(1) == true,            "is_quarter_start jan-01 → true")
check(qs:get(2) == true,            "is_quarter_start abr-01 → true")
check(qs:get(5) == false,           "is_quarter_start mai-15 → false")

local qe = q.dt:is_quarter_end()
check(qe:get(3) == true,            "is_quarter_end mar-31 → true")
check(qe:get(4) == true,            "is_quarter_end dez-31 → true")
check(qe:get(1) == false,           "is_quarter_end jan-01 → false")

-- ================================================================
-- 3. is_year_start / is_year_end
-- ================================================================

local y = S.from_table({
    P("2024-01-01T00:00:00Z"),
    P("2024-12-31T00:00:00Z"),
    P("2024-06-15T00:00:00Z"),
}, "datetime")

check(y.dt:is_year_start():get(1) == true,  "is_year_start jan-01 → true")
check(y.dt:is_year_start():get(2) == false, "is_year_start dez-31 → false")
check(y.dt:is_year_end():get(2) == true,    "is_year_end dez-31 → true")
check(y.dt:is_year_end():get(3) == false,   "is_year_end jun-15 → false")

-- ================================================================
-- 4. is_leap_year
-- ================================================================

local ly = S.from_table({
    P("2024-06-01T00:00:00Z"),  -- 2024 bissexto
    P("2023-06-01T00:00:00Z"),  -- 2023 não
    P("2000-06-01T00:00:00Z"),  -- 2000 bissexto (÷400)
    P("1900-06-01T00:00:00Z"),  -- 1900 NÃO (÷100 mas não ÷400)
}, "datetime")

local lyr = ly.dt:is_leap_year()
check(lyr:get(1) == true,           "is_leap_year 2024 → true")
check(lyr:get(2) == false,          "is_leap_year 2023 → false")
check(lyr:get(3) == true,           "is_leap_year 2000 → true (regra ÷400)")
check(lyr:get(4) == false,          "is_leap_year 1900 → false (secular não-÷400)")

-- ================================================================
-- 5. days_in_month
-- ================================================================

local dim = S.from_table({
    P("2024-01-15T00:00:00Z"),  -- 31
    P("2024-02-15T00:00:00Z"),  -- 29 (bissexto)
    P("2025-02-15T00:00:00Z"),  -- 28
    P("2024-04-15T00:00:00Z"),  -- 30
}, "datetime")

local d = dim.dt:days_in_month()
check(d._dtype == "int64",          "days_in_month → int64")
check(d:get(1) == 31,               "days_in_month jan → 31")
check(d:get(2) == 29,               "days_in_month fev-2024 → 29")
check(d:get(3) == 28,               "days_in_month fev-2025 → 28")
check(d:get(4) == 30,               "days_in_month abr → 30")

-- ================================================================
-- 6. month_name / day_name
-- ================================================================

local nm = S.from_table({
    P("2024-01-01T00:00:00Z"),  -- January, Monday
    P("2024-07-04T00:00:00Z"),  -- July, Thursday
    P("2024-12-25T00:00:00Z"),  -- December, Wednesday
}, "datetime")

local mn = nm.dt:month_name()
check(mn._dtype == "string",        "month_name → string")
check(mn:get(1) == "January",       "month_name jan → January")
check(mn:get(2) == "July",          "month_name jul → July")
check(mn:get(3) == "December",      "month_name dez → December")

local dn = nm.dt:day_name()
check(dn:get(1) == "Monday",        "day_name 2024-01-01 → Monday")
check(dn:get(2) == "Thursday",      "day_name 2024-07-04 → Thursday")
check(dn:get(3) == "Wednesday",     "day_name 2024-12-25 → Wednesday")

-- ================================================================
-- 7. normalize (= truncate D)
-- ================================================================

local nz = S.from_table({
    P("2024-06-15T14:30:45Z"),
    P("2024-06-15T00:00:00Z"),  -- já meia-noite
    NA,
}, "datetime")

local n = nz.dt:normalize()
check(n._dtype == "datetime",       "normalize → datetime")
check(iso_of(n, 1) == "2024-06-15T00:00:00.000Z", "normalize zera hora")
check(iso_of(n, 2) == "2024-06-15T00:00:00.000Z", "normalize idempotente")
check(n:get(3) == nil,              "normalize NA → nil")

-- ================================================================
-- 8. ceil — menor início-de-período >= v
-- ================================================================

local ch = S.from_table({
    P("2024-06-15T10:20:00Z"),  -- ceil h → 11:00
    P("2024-06-15T10:00:00Z"),  -- já alinhado → 10:00
}, "datetime")
local ceil_h = ch.dt:ceil("h")
check(iso_of(ceil_h, 1) == "2024-06-15T11:00:00.000Z", "ceil h 10:20 → 11:00")
check(iso_of(ceil_h, 2) == "2024-06-15T10:00:00.000Z", "ceil h alinhado → mesmo")

-- ceil M, vira ano
local cm = S.from_table({
    P("2024-01-10T00:00:00Z"),  -- → 2024-02-01
    P("2024-12-20T00:00:00Z"),  -- → 2025-01-01
    P("2024-03-01T00:00:00Z"),  -- alinhado → mesmo
}, "datetime")
local ceil_m = cm.dt:ceil("M")
check(iso_of(ceil_m, 1) == "2024-02-01T00:00:00.000Z", "ceil M jan-10 → fev-01")
check(iso_of(ceil_m, 2) == "2025-01-01T00:00:00.000Z", "ceil M dez-20 → 2025-jan-01")
check(iso_of(ceil_m, 3) == "2024-03-01T00:00:00.000Z", "ceil M alinhado → mesmo")

-- ceil Q e Y
local cq = S.from_table({ P("2024-02-15T00:00:00Z") }, "datetime")
check(iso_of(cq.dt:ceil("Q"), 1) == "2024-04-01T00:00:00.000Z", "ceil Q fev → abr-01")
check(iso_of(cq.dt:ceil("Y"), 1) == "2025-01-01T00:00:00.000Z", "ceil Y 2024 → 2025-01-01")

-- unidade inválida → erro
local ok_ceil = pcall(function() cq.dt:ceil("X") end)
check(not ok_ceil,                  "ceil unidade inválida = erro")

-- ================================================================
-- 9. round — período mais próximo (half-up no empate)
-- ================================================================

local rh = S.from_table({
    P("2024-06-15T10:20:00Z"),  -- < 30min → floor 10:00
    P("2024-06-15T10:40:00Z"),  -- > 30min → next 11:00
    P("2024-06-15T10:30:00Z"),  -- empate → half-up 11:00
}, "datetime")
local round_h = rh.dt:round("h")
check(iso_of(round_h, 1) == "2024-06-15T10:00:00.000Z", "round h 10:20 → 10:00")
check(iso_of(round_h, 2) == "2024-06-15T11:00:00.000Z", "round h 10:40 → 11:00")
check(iso_of(round_h, 3) == "2024-06-15T11:00:00.000Z", "round h 10:30 empate → 11:00 (half-up)")

-- round D
local rd = S.from_table({
    P("2024-06-15T05:00:00Z"),  -- < 12h → 06-15
    P("2024-06-15T20:00:00Z"),  -- > 12h → 06-16
}, "datetime")
local round_d = rd.dt:round("D")
check(iso_of(round_d, 1) == "2024-06-15T00:00:00.000Z", "round D 05h → mesmo dia")
check(iso_of(round_d, 2) == "2024-06-16T00:00:00.000Z", "round D 20h → próximo dia")

-- ================================================================
-- 10. strftime
-- ================================================================

local sf = S.from_table({ P("2024-02-05T14:09:07Z") }, "datetime")  -- Monday
local out = sf.dt:strftime("%Y-%m-%d %H:%M:%S")
check(out._dtype == "string",       "strftime → string")
check(out:get(1) == "2024-02-05 14:09:07", "strftime ISO básico")

-- tokens variados
check(sf.dt:strftime("%A"):get(1) == "Monday",     "strftime %A → Monday")
check(sf.dt:strftime("%a"):get(1) == "Mon",        "strftime %a → Mon")
check(sf.dt:strftime("%B"):get(1) == "February",   "strftime %B → February")
check(sf.dt:strftime("%b"):get(1) == "Feb",        "strftime %b → Feb")
check(sf.dt:strftime("%y"):get(1) == "24",         "strftime %y → 24")
check(sf.dt:strftime("%j"):get(1) == "036",        "strftime %j → 036 (dia do ano)")
check(sf.dt:strftime("%I%p"):get(1) == "02PM",     "strftime %I%p → 02PM")
check(sf.dt:strftime("100%%"):get(1) == "100%",    "strftime %% → %")
-- token desconhecido fica literal
check(sf.dt:strftime("%Z"):get(1) == "%Z",         "strftime token desconhecido → literal")

-- meia-noite e meio-dia para %p / %I
local mid = S.from_table({ P("2024-01-01T00:00:00Z"), P("2024-01-01T12:00:00Z") }, "datetime")
check(mid.dt:strftime("%I %p"):get(1) == "12 AM",  "strftime meia-noite → 12 AM")
check(mid.dt:strftime("%I %p"):get(2) == "12 PM",  "strftime meio-dia → 12 PM")

-- NA propaga
local sfn = S.from_table({ NA }, "datetime")
check(sfn.dt:strftime("%Y"):get(1) == nil, "strftime NA → nil")

-- fmt não-string → erro
local ok_sf = pcall(function() sf.dt:strftime(42) end)
check(not ok_sf,                    "strftime fmt não-string = erro")

-- ================================================================
-- Resultado
-- ================================================================

print(string.format(
    "OK — %d checks passaram (F.3 .dt estendido: is_*_start/end, is_leap_year, " ..
    "days_in_month, month_name/day_name, normalize, round/ceil, strftime)",
    n_ok))
