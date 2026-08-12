-- tests/series/test_dt.lua
-- Accessor .dt completo: componentes base, truncate, diff, add_*, comparações,
-- sort, filter, astype, integração DataSet. F.3 estendido: is_*_start/end,
-- is_leap_year, days_in_month, month_name/day_name, normalize, round/ceil, strftime.
-- Consolida: test_datetime.lua + test_dt_extended.lua
-- Baseado no padrão de test_constructors.lua.
-- Rode da raiz: luajit tests/series/test_dt.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug   = require("smaug")
local Series  = smaug.Series
local NA      = Series.NA or smaug.NA
local DataSet = smaug.DataSet

local n_ok = 0

local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

local function check_err(fn, msg)
    local ok = pcall(fn)
    check(not ok, msg .. " (deveria lançar erro)")
end

local function check_err_match(fn, pattern, msg)
    local ok, err = pcall(fn)
    check(not ok, msg .. " (deveria lançar erro)")
    if not ok then
        check(type(err) == "string" and err:find(pattern, 1, true) ~= nil,
              msg .. " (mensagem deveria conter '" .. pattern .. "')")
    end
end

local function P(iso)
    return Series.dt_parse(iso)
end

local function iso_of(series_dt, i)
    return series_dt.dt:format():get(i)
end

-- =====================================================================
-- Épocas de referência (ms UTC)
-- =====================================================================

local ep_ref  = Series.dt_parse("2024-01-15T12:30:00.500Z")
local ep_mar  = Series.dt_parse("2024-03-20T00:00:00Z")
local ep_dec  = Series.dt_parse("2024-12-31T23:59:59.999Z")
local ep_zero = Series.dt_parse("1970-01-01T00:00:00Z")
local ep_neg  = Series.dt_parse("1969-12-31T23:59:59Z")

local ep_a = Series.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
local ep_b = Series.dt_from_parts(2024, 6, 1, 0, 0, 0, 0)
local ep_c = Series.dt_from_parts(2024, 12, 1, 0, 0, 0, 0)

do
    check(ep_zero == 0, "epoch 1970-01-01 = 0")
    check(ep_neg == -1000, "epoch 1969-12-31T23:59:59Z = -1000 ms")
    check(ep_ref ~= nil, "parse 2024-01-15: não nil")
    check(ep_mar ~= nil, "parse 2024-03-20: não nil")
    check(ep_dec ~= nil, "parse 2024-12-31: não nil")
end

-- =====================================================================
-- 1. Factories e construção
-- =====================================================================
do
    local s0 = Series.new("datetime", 3)
    check(s0:len() == 3, "new: len=3")
    check(s0:is_null(1), "new: elemento nulo por padrão")
    check(s0._dtype == "datetime", "new: dtype=datetime")

    local s_datetime = Series.datetime(2)
    check(s_datetime:len() == 2, "datetime factory: len=2")
    check(s_datetime._dtype == "datetime", "datetime factory: dtype correto")

    local s_full = Series.full(3, ep_zero, "datetime")
    check(s_full:len() == 3, "full: len=3")
    check(s_full:get(1) == 0, "full: get(1)=0 (epoch)")
    check(s_full:get(3) == 0, "full: get(3)=0")

    local s_epochs = Series.from_table({ep_ref, ep_mar, NA, ep_dec}, "datetime")
    check(s_epochs:len() == 4, "from_table[num]: len=4")
    check(s_epochs:get(1) == ep_ref, "from_table[num]: get(1)=ep_ref")
    check(s_epochs:is_null(3), "from_table[num]: NA -> null")
    check(s_epochs:get(4) == ep_dec, "from_table[num]: get(4)=ep_dec")

    local s_iso = Series.from_table({
        "2024-01-15T12:30:00.500Z",
        "2024-03-20T00:00:00Z",
        NA
    }, "datetime")

    check(s_iso:len() == 3, "from_table[str]: len=3")
    check(s_iso:get(1) == ep_ref, "from_table[str]: parse correto ep_ref")
    check(s_iso:get(2) == ep_mar, "from_table[str]: parse correto ep_mar")
    check(s_iso:is_null(3), "from_table[str]: NA -> null")

    local ep = Series.dt_parse("2024-06-01T00:00:00Z")
    check(ep ~= nil, "dt_parse: não nil")

    local fmt = Series.dt_format(ep)
    check(type(fmt) == "string", "dt_format: retorna string")
    check(fmt:sub(1, 10) == "2024-06-01", "dt_format: prefixo correto")

    check(Series.dt_parse("2024-01-15") ~= nil, "parse: YYYY-MM-DD")
    check(Series.dt_parse("2024-01-15T12:30:00") ~= nil, "parse: sem offset")
    check(Series.dt_parse("2024-01-15T12:30:00.500Z") ~= nil, "parse: com ms e Z")
    check(Series.dt_parse("2024-01-15T14:30:00+02:00") ~= nil, "parse: com offset +")
    check(Series.dt_parse("formato-invalido") == nil, "parse: inválido -> nil")
    check(Series.dt_parse("") == nil, "parse: vazio -> nil")

    local ep_parts = Series.dt_from_parts(2024, 1, 15, 12, 30, 0, 500)
    check(ep_parts == ep_ref, "dt_from_parts: bate com parse ISO")

    local ep_mid = Series.dt_from_parts(1970, 1, 1, 0, 0, 0, 0)
    check(ep_mid == 0, "dt_from_parts: epoch zero")

    check(Series.dt_from_parts(2024, 13, 1) == nil, "dt_from_parts: mês inválido -> nil")
    check(Series.dt_from_parts(2024, 2, 30) == nil, "dt_from_parts: dia inválido -> nil")
end

-- =====================================================================
-- 2. Acesso e mutação
-- =====================================================================
do
    local sm = Series.new("datetime", 3)
    sm:set(1, ep_ref)
    sm:set(2, "2024-03-20T00:00:00Z")
    sm:set_null(3)

    check(sm:get(1) == ep_ref, "set/get: epoch_ms")
    check(sm:get(2) == ep_mar, "set via string ISO 8601")
    check(sm:get(3) == nil, "set_null -> get=nil")
    check(sm:is_null(3), "is_null após set_null")
    check(not sm:is_null(1), "is_null false após set")

    local sa = Series.new("datetime", 0)
    sa:append(ep_zero)
    sa:append("1970-01-01T00:00:00Z")

    check(sa:len() == 2, "append: len=2")
    check(sa:get(1) == 0, "append epoch_ms")
    check(sa:get(2) == 0, "append string ISO")

    local sc = Series.from_table({ep_ref, NA, ep_mar, NA, ep_dec}, "datetime")
    check(sc:count_nonnull() == 3, "count_nonnull: 3")
end

-- =====================================================================
-- 3. Accessor .dt — componentes calendário
-- =====================================================================
do
    local s1 = Series.from_table({ep_ref}, "datetime")

    check(s1.dt:year():get(1) == 2024, "dt:year()")
    check(s1.dt:month():get(1) == 1, "dt:month() = 1 (janeiro)")
    check(s1.dt:day():get(1) == 15, "dt:day() = 15")
    check(s1.dt:hour():get(1) == 12, "dt:hour() = 12")
    check(s1.dt:minute():get(1) == 30, "dt:minute() = 30")
    check(s1.dt:second():get(1) == 0, "dt:second() = 0")
    check(s1.dt:ms():get(1) == 500, "dt:ms() = 500")
    check(s1.dt:weekday():get(1) == 0, "dt:weekday() = 0 (seg)")
    check(s1.dt:quarter():get(1) == 1, "dt:quarter() = 1 (Q1)")

    local s2 = Series.from_table({ep_mar}, "datetime")
    check(s2.dt:month():get(1) == 3, "dt:month() = 3 (março)")
    check(s2.dt:day():get(1) == 20, "dt:day() = 20")
    check(s2.dt:quarter():get(1) == 1, "dt:quarter() = 1 (mar ainda Q1)")

    local s3 = Series.from_table({ep_dec}, "datetime")
    check(s3.dt:year():get(1) == 2024, "dt:year() dec")
    check(s3.dt:month():get(1) == 12, "dt:month() = 12")
    check(s3.dt:day():get(1) == 31, "dt:day() = 31")
    check(s3.dt:quarter():get(1) == 4, "dt:quarter() = 4 (Q4)")

    local sn = Series.from_table({ep_ref, NA, ep_mar}, "datetime")
    check(sn.dt:year():is_null(2), "year: NA propaga")
    check(sn.dt:month():is_null(2), "month: NA propaga")
    check(sn.dt:day():is_null(2), "day: NA propaga")

    local ys = sn.dt:year()
    check(ys._dtype == "int64", "dt:year() -> Series<int64>")
    check(ys:get(1) == 2024, "dt:year()[1] = 2024")
    check(ys:get(3) == 2024, "dt:year()[3] = 2024")
end

-- =====================================================================
-- 4. format() e truncate()
-- =====================================================================
do
    local s_fmt = Series.from_table({ep_zero, NA, ep_ref}, "datetime")
    local fmts = s_fmt.dt:format()

    check(fmts._dtype == "string", "format: dtype=string")
    check(fmts:get(1) == "1970-01-01T00:00:00.000Z", "format: epoch zero")
    check(fmts:is_null(2), "format: NA -> null")
    check(fmts:get(3):sub(1, 10) == "2024-01-15", "format: ep_ref prefixo")

    local st = Series.from_table({ep_ref, NA}, "datetime")

    local td = st.dt:truncate("D")
    check(td._dtype == "datetime", "truncate: dtype=datetime")
    check(td:is_null(2), "truncate: NA propaga")

    local td1 = td:get(1)
    check(td1 ~= nil, "truncate D: não nil")

    local ep_day = Series.dt_from_parts(2024, 1, 15, 0, 0, 0, 0)
    check(td1 == ep_day, "truncate D: meia-noite correta")

    local tm = st.dt:truncate("M")
    local ep_month = Series.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
    check(tm:get(1) == ep_month, "truncate M: 1º do mês")

    local ty = st.dt:truncate("Y")
    local ep_year = Series.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
    check(ty:get(1) == ep_year, "truncate Y: 1º de jan")

    local th = st.dt:truncate("h")
    local ep_hour = Series.dt_from_parts(2024, 1, 15, 12, 0, 0, 0)
    check(th:get(1) == ep_hour, "truncate h: hora inteira")
end

-- =====================================================================
-- 5. diff() e add_*
-- =====================================================================
do
    local MS_PER_DAY = 86400000

    local ep_d1 = Series.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
    local ep_d2 = Series.dt_from_parts(2024, 1, 2, 0, 0, 0, 0)
    local ep_d3 = Series.dt_from_parts(2024, 1, 4, 0, 0, 0, 0)

    local sdt = Series.from_table({ep_d1, ep_d2, ep_d3}, "datetime")
    local diffs = sdt.dt:diff()

    check(diffs._dtype == "int64", "diff: dtype=int64")
    check(diffs:is_null(1), "diff: primeiro elemento = null")
    check(diffs:get(2) == MS_PER_DAY, "diff[2] = 1 dia em ms")
    check(diffs:get(3) == 2 * MS_PER_DAY, "diff[3] = 2 dias em ms")

    local d2 = sdt.dt:diff(2)
    check(d2:is_null(1), "diff(2)[1] = null")
    check(d2:is_null(2), "diff(2)[2] = null")
    check(d2:get(3) == 3 * MS_PER_DAY, "diff(2)[3] = 3 dias")

    local sna2 = Series.from_table({ep_d1, NA, ep_d3}, "datetime")
    local dna = sna2.dt:diff()

    check(dna:is_null(1), "diff NA: [1] null")
    check(dna:is_null(2), "diff NA: [2] null (era NA)")
    check(dna:is_null(3), "diff NA: [3] null (b era NA)")

    local base = Series.from_table({ep_zero, NA}, "datetime")

    local added = base.dt:add_ms(1000)
    check(added:get(1) == 1000, "add_ms: epoch+1000ms")
    check(added:is_null(2), "add_ms: NA propaga")

    local ad = base.dt:add_days(1)
    check(ad:get(1) == MS_PER_DAY, "add_days(1): +1 dia em ms")

    local ah = base.dt:add_hours(2)
    check(ah:get(1) == 2 * 3600000, "add_hours(2)")

    local am = base.dt:add_minutes(90)
    check(am:get(1) == 90 * 60000, "add_minutes(90)")

    local as_ = base.dt:add_seconds(30)
    check(as_:get(1) == 30 * 1000, "add_seconds(30)")
end

-- =====================================================================
-- 6. Comparações -> Series<bool>
-- =====================================================================
do
    local sc2 = Series.from_table({ep_a, ep_b, ep_c, NA}, "datetime")
    local pivot = ep_b

    local gt = sc2:gt(pivot)
    check(gt._dtype == "bool", "gt: dtype=bool")
    check(gt:get(1) == false, "gt: jan > jun = false")
    check(gt:get(2) == false, "gt: jun > jun = false")
    check(gt:get(3) == true, "gt: dec > jun = true")
    check(gt:is_null(4), "gt: NA -> NA")

    local lt = sc2:lt(pivot)
    check(lt:get(1) == true, "lt: jan < jun = true")
    check(lt:get(2) == false, "lt: jun < jun = false")
    check(lt:get(3) == false, "lt: dec < jun = false")

    local eq = sc2:eq(pivot)
    check(eq:get(1) == false, "eq: jan == jun = false")
    check(eq:get(2) == true, "eq: jun == jun = true")

    local ge = sc2:ge(pivot)
    check(ge:get(1) == false, "ge: jan >= jun = false")
    check(ge:get(2) == true, "ge: jun >= jun = true")
    check(ge:get(3) == true, "ge: dec >= jun = true")

    local le = sc2:le(pivot)
    check(le:get(1) == true, "le: jan <= jun = true")
    check(le:get(2) == true, "le: jun <= jun = true")
    check(le:get(3) == false, "le: dec <= jun = false")

    local ne = sc2:ne(pivot)
    check(ne:get(1) == true, "ne: jan != jun = true")
    check(ne:get(2) == false, "ne: jun != jun = false")
end

-- =====================================================================
-- 7. Ordenação e seleção
-- =====================================================================
do
    local su = Series.from_table({ep_c, ep_a, ep_b}, "datetime")

    local sorted = su:sort(true)
    check(sorted:get(1) == ep_a, "sort asc: 1º = jan")
    check(sorted:get(2) == ep_b, "sort asc: 2º = jun")
    check(sorted:get(3) == ep_c, "sort asc: 3º = dec")

    local sortd = su:sort(false)
    check(sortd:get(1) == ep_c, "sort desc: 1º = dec")
    check(sortd:get(3) == ep_a, "sort desc: 3º = jan")

    local snu = Series.from_table({ep_b, NA, ep_a}, "datetime")
    check_err(function() snu:sort(true) end, "sort com null")

    local idx = su:argsort(true)
    check(type(idx) == "table", "argsort: retorna tabela")
    check(idx[1] == 2, "argsort asc: 1º idx=2 (ep_a)")
    check(idx[2] == 3, "argsort asc: 2º idx=3 (ep_b)")
    check(idx[3] == 1, "argsort asc: 3º idx=1 (ep_c)")

    check(snu:argsort(true) == nil, "argsort com null: nil")

    local tk = su:take({2, 1})
    check(tk:len() == 2, "take: len=2")
    check(tk:get(1) == ep_a, "take: 1º = ep_a (era idx 2)")
    check(tk:get(2) == ep_c, "take: 2º = ep_c (era idx 1)")

    local shead = su:head(2)
    check(shead:len() == 2, "head(2): len=2")
    check(shead:get(1) == ep_c, "head(2): 1º = ep_c")

    local stail = su:tail(1)
    check(stail:len() == 1, "tail(1): len=1")
    check(stail:get(1) == ep_b, "tail(1): 1º = ep_b")

    local sdn = Series.from_table({ep_a, NA, ep_b, NA, ep_c}, "datetime")
    local dropped = sdn:dropna()

    check(dropped:len() == 3, "dropna: len=3")
    check(dropped:get(1) == ep_a, "dropna: 1º = ep_a")
    check(dropped:get(3) == ep_c, "dropna: 3º = ep_c")

    local mask = sdn:gt(ep_a)
    local filtered = sdn:filter(mask)

    check(filtered:len() == 2, "filter gt: len=2 (jun e dec)")
    check(filtered:get(1) == ep_b, "filter gt: 1º = ep_b")
    check(filtered:get(2) == ep_c, "filter gt: 2º = ep_c")

    check_err(function() sdn:gt("2024-01-01") end, "gt: string como target")
    check_err(function() sdn:lt(true) end, "lt: boolean como target")
    check_err(function() sdn:eq(nil) end, "eq: nil como target")

    local cl = su:clone()
    cl:set(1, ep_zero)
    check(su:get(1) == ep_c, "clone: original intacto")

    local sv_base = Series.from_table({ep_a, ep_b, ep_c}, "datetime")
    local sv = sv_base:view(2, 2)

    check(sv:len() == 2, "dt view: len da janela = 2")
    check(sv:get(1) == ep_b, "dt view: 1º = ep_b")
    check(sv:get(2) == ep_c, "dt view: 2º = ep_c")

    sv:set(1, ep_zero)
    check(sv:get(1) == ep_zero, "dt view: escrita reflete na view")
    check(sv_base:get(2) == ep_b, "dt view: detach COW — pai intacto após escrita")

    check_err(function() sv_base:view(2, 5) end, "dt view: fora dos limites")

    -- dayfirst na API pública
    check(Series.dt_parse("2026-06-13") == Series.dt_parse("2026-06-13", true),
          "dt_parse year-first ignora dayfirst")

    check(Series.dt_parse("13/06/2026", true) == Series.dt_parse("2026-06-13"),
          "dt_parse DD/MM (dayfirst=true)")

    check(Series.dt_parse("06/13/2026") == Series.dt_parse("2026-06-13"),
          "dt_parse MM/DD (default)")

    check(Series.dt_parse("13/06/2026") == nil,
          "dt_parse 13/06 sem dayfirst -> nil (falha visível)")

    check(Series.dt_parse("5/6/2026", true) == Series.dt_parse("2026-06-05"),
          "dt_parse 5/6 dayfirst=true = 5 jun")

    local sd_day = Series.from_table({"13/06/2026", "25/12/2026"}, "string")
    local conv = sd_day:astype("datetime", {dayfirst = true})

    check(conv:get(1) == Series.dt_parse("2026-06-13"),
          "astype datetime dayfirst=true: 13/06 -> 13 jun")

    check(conv:get(2) == Series.dt_parse("2026-12-25"),
          "astype datetime dayfirst=true: 25/12 -> natal")

    local sd_default = Series.from_table({"13/06/2026"}, "string")
    local conv2 = sd_default:astype("datetime")

    check(conv2:is_null(1),
          "astype datetime default: 13/06 -> null (MM/DD, mês 13 inválido)")

    local sd_name = Series.from_table({"2026-06-13"}, "string")
    local conv3 = sd_name:astype("datetime", "nome_custom")

    check(conv3._name == "nome_custom",
          "astype 3º arg string = name (retrocompat)")
end

-- =====================================================================
-- 8. fillna / is_null
-- =====================================================================
do
    local s_fill = Series.from_table({ep_a, NA, NA, ep_c}, "datetime")
    local filled = s_fill:fillna(ep_b)

    check(filled:get(1) == ep_a, "fillna: não-nulo intacto")
    check(filled:get(2) == ep_b, "fillna: NA preenchido")
    check(filled:get(3) == ep_b, "fillna: NA preenchido [3]")
    check(filled:get(4) == ep_c, "fillna: não-nulo intacto [4]")

    check(s_fill:is_null(2), "fillna: original não mutado")
end

-- =====================================================================
-- 9. astype
-- =====================================================================
do
    local sas = Series.from_table({ep_zero, NA}, "datetime")

    local as_str = sas:astype("string")
    check(as_str._dtype == "string", "astype dt->str: dtype")
    check(as_str:get(1) == "1970-01-01T00:00:00.000Z", "astype dt->str: epoch zero")
    check(as_str:is_null(2), "astype dt->str: NA -> null")

    local as_i64 = sas:astype("int64")
    check(as_i64._dtype == "int64", "astype dt->i64: dtype")
    check(as_i64:get(1) == 0, "astype dt->i64: epoch zero = 0")
    check(as_i64:is_null(2), "astype dt->i64: NA -> null")

    local si = Series.from_table({0, NA, ep_ref}, "int64")
    local as_dt = si:astype("datetime")

    check(as_dt._dtype == "datetime", "astype i64->dt: dtype")
    check(as_dt:get(1) == 0, "astype i64->dt: 0 = epoch")
    check(as_dt:is_null(2), "astype i64->dt: NA -> null")
    check(as_dt:get(3) == ep_ref, "astype i64->dt: ep_ref")

    local ss2 = Series.from_table({
        "2024-01-15T12:30:00.500Z",
        NA,
        "invalido"
    }, "string")

    local as_dt2 = ss2:astype("datetime")

    check(as_dt2._dtype == "datetime", "astype str->dt: dtype")
    check(as_dt2:get(1) == ep_ref, "astype str->dt: parse correto")
    check(as_dt2:is_null(2), "astype str->dt: NA -> null")
    check(as_dt2:is_null(3), "astype str->dt: inválido -> null")
end

-- =====================================================================
-- 10. describe
-- =====================================================================
do
    local s_desc = Series.from_table({ep_a, NA, ep_b, ep_c}, "datetime")
    local desc = s_desc:describe()

    check(type(desc) == "table", "describe: retorna tabela")
    check(desc.dtype == "datetime", "describe: dtype=datetime")
    check(desc.count == 3, "describe: count=3 (sem NA)")
    check(desc.nulls == 1, "describe: nulls=1")
    check(type(desc.min) == "string", "describe: min é string ISO")
    check(type(desc.max) == "string", "describe: max é string ISO")
    check(desc.min:sub(1, 10) == "2024-01-01", "describe: min = jan")
    check(desc.max:sub(1, 10) == "2024-12-01", "describe: max = dez")
end

-- =====================================================================
-- 11. Integração com DataSet
-- =====================================================================
do
    local ds = DataSet({
        {"data", {
            "2024-01-15T12:30:00.500Z",
            "2024-03-20T00:00:00Z",
            "2024-12-31T23:59:59.999Z"
        }, "datetime"},
        {"valor", {10.0, 20.0, 30.0}, "float64"},
    })

    check(ds:has_column("data"), "DataSet: coluna datetime existe")
    check(ds:col("data")._dtype == "datetime", "DataSet: dtype correto")

    local anos = ds:col("data").dt:year()
    check(anos:get(1) == 2024, "DataSet .dt:year()[1] = 2024")
    check(anos:get(2) == 2024, "DataSet .dt:year()[2] = 2024")

    local pivot2 = Series.dt_from_parts(2024, 6, 1, 0, 0, 0, 0)
    local mask2 = ds:col("data"):gt(pivot2)
    local dsf = ds:filter(mask2)

    check(dsf:nrows() == 1, "DataSet filter por data: 1 linha")
    check(dsf:col("valor"):get(1) == 30.0, "DataSet filter: linha correta")

    local dss = ds:sort_by("data", false)
    check(dss:col("valor"):get(1) == 30.0, "sort_by data desc: 1º = dez")
    check(dss:col("valor"):get(3) == 10.0, "sort_by data desc: 3º = jan")

    local ds_with_mes = ds:assign("mes", ds:col("data").dt:month())
    check(ds_with_mes:has_column("mes"), "assign: coluna mes criada")
    check(ds_with_mes:col("mes"):get(1) == 1, "assign: mes[1] = 1")
    check(ds_with_mes:col("mes"):get(2) == 3, "assign: mes[2] = 3")

    local dsel = ds:select({"data", "valor"})
    check(dsel:col("data")._dtype == "datetime", "select: datetime preservado")

    local dh = ds:head(2)
    check(dh:nrows() == 2, "DataSet head: 2 linhas")
    check(dh:col("data")._dtype == "datetime", "DataSet head: dtype preservado")

    local ds_na = DataSet({
        {"data", {ep_a, NA, ep_b}, "datetime"},
        {"v", {1.0, 2.0, 3.0}, "float64"},
    })

    local dna2 = ds_na:dropna()
    check(dna2:nrows() == 2, "DataSet dropna: 2 linhas")

    local ddesc = ds:describe()
    check(type(ddesc) == "table", "DataSet describe com datetime: não explode")
    check(ddesc["data"] ~= nil, "DataSet describe: coluna data presente")
    check(ddesc["data"].dtype == "datetime", "DataSet describe: dtype=datetime na coluna")
end

-- =====================================================================
-- 12. Erros esperados
-- =====================================================================
do
    check_err_match(
        function()
            Series.from_table({1.0, 2.0}, "float64").dt:year()
        end,
        "datetime",
        "erro: .dt em float64"
    )

    local se2 = Series.new("datetime", 3)
    check_err(function() se2:set(1, "nao-e-data") end, "set com string inválida")

    check_err(
        function()
            Series.from_table({"2024-01-15", "INVALIDO"}, "datetime")
        end,
        "from_table string inválida"
    )

    check_err(
        function()
            local sx = Series.new("datetime", 0)
            sx:append("nao-e-data")
        end,
        "append string inválida"
    )

    check(Series.dt_from_parts(2024, 0, 1) == nil, "dt_from_parts: mês=0 -> nil")
    check(Series.dt_from_parts(2024, 1, 0) == nil, "dt_from_parts: dia=0 -> nil")
    check(Series.dt_from_parts(2024, 1, 1, 25, 0, 0) == nil, "dt_from_parts: hora=25 -> nil")
end

-- =====================================================================
-- F.3.1 is_month_start / is_month_end
-- =====================================================================
do
    local m = Series.from_table({
        P("2024-01-01T00:00:00Z"),
        P("2024-02-29T12:00:00Z"),
        P("2024-03-15T00:00:00Z"),
        P("2025-02-28T00:00:00Z"),
        NA,
    }, "datetime")

    local ms = m.dt:is_month_start()
    check(ms._dtype == "bool", "is_month_start -> bool")
    check(ms:get(1) == true, "is_month_start[1]=01 -> true")
    check(ms:get(2) == false, "is_month_start[2]=29 -> false")
    check(ms:get(5) == nil, "is_month_start[5]=NA -> nil")

    local me = m.dt:is_month_end()
    check(me:get(2) == true, "is_month_end[2]=29 fev bissexto -> true")
    check(me:get(3) == false, "is_month_end[3]=15 -> false")
    check(me:get(4) == true, "is_month_end[4]=28 fev não-bissexto -> true")
end

-- =====================================================================
-- F.3.2 is_quarter_start / is_quarter_end
-- =====================================================================
do
    local q = Series.from_table({
        P("2024-01-01T00:00:00Z"),
        P("2024-04-01T00:00:00Z"),
        P("2024-03-31T00:00:00Z"),
        P("2024-12-31T00:00:00Z"),
        P("2024-05-15T00:00:00Z"),
    }, "datetime")

    local qs = q.dt:is_quarter_start()
    check(qs:get(1) == true, "is_quarter_start jan-01 -> true")
    check(qs:get(2) == true, "is_quarter_start abr-01 -> true")
    check(qs:get(5) == false, "is_quarter_start mai-15 -> false")

    local qe = q.dt:is_quarter_end()
    check(qe:get(3) == true, "is_quarter_end mar-31 -> true")
    check(qe:get(4) == true, "is_quarter_end dez-31 -> true")
    check(qe:get(1) == false, "is_quarter_end jan-01 -> false")
end

-- =====================================================================
-- F.3.3 is_year_start / is_year_end
-- =====================================================================
do
    local y = Series.from_table({
        P("2024-01-01T00:00:00Z"),
        P("2024-12-31T00:00:00Z"),
        P("2024-06-15T00:00:00Z"),
    }, "datetime")

    check(y.dt:is_year_start():get(1) == true, "is_year_start jan-01 -> true")
    check(y.dt:is_year_start():get(2) == false, "is_year_start dez-31 -> false")
    check(y.dt:is_year_end():get(2) == true, "is_year_end dez-31 -> true")
    check(y.dt:is_year_end():get(3) == false, "is_year_end jun-15 -> false")
end

-- =====================================================================
-- F.3.4 is_leap_year
-- =====================================================================
do
    local ly = Series.from_table({
        P("2024-06-01T00:00:00Z"),
        P("2023-06-01T00:00:00Z"),
        P("2000-06-01T00:00:00Z"),
        P("1900-06-01T00:00:00Z"),
    }, "datetime")

    local lyr = ly.dt:is_leap_year()
    check(lyr:get(1) == true, "is_leap_year 2024 -> true")
    check(lyr:get(2) == false, "is_leap_year 2023 -> false")
    check(lyr:get(3) == true, "is_leap_year 2000 -> true (regra ÷400)")
    check(lyr:get(4) == false, "is_leap_year 1900 -> false (secular não-÷400)")
end

-- =====================================================================
-- F.3.5 days_in_month
-- =====================================================================
do
    local dim = Series.from_table({
        P("2024-01-15T00:00:00Z"),
        P("2024-02-15T00:00:00Z"),
        P("2025-02-15T00:00:00Z"),
        P("2024-04-15T00:00:00Z"),
    }, "datetime")

    local d = dim.dt:days_in_month()
    check(d._dtype == "int64", "days_in_month -> int64")
    check(d:get(1) == 31, "days_in_month jan -> 31")
    check(d:get(2) == 29, "days_in_month fev-2024 -> 29")
    check(d:get(3) == 28, "days_in_month fev-2025 -> 28")
    check(d:get(4) == 30, "days_in_month abr -> 30")
end

-- =====================================================================
-- F.3.6 month_name / day_name
-- =====================================================================
do
    local nm = Series.from_table({
        P("2024-01-01T00:00:00Z"),
        P("2024-07-04T00:00:00Z"),
        P("2024-12-25T00:00:00Z"),
    }, "datetime")

    local mn = nm.dt:month_name()
    check(mn._dtype == "string", "month_name -> string")
    check(mn:get(1) == "January", "month_name jan -> January")
    check(mn:get(2) == "July", "month_name jul -> July")
    check(mn:get(3) == "December", "month_name dez -> December")

    local dn = nm.dt:day_name()
    check(dn:get(1) == "Monday", "day_name 2024-01-01 -> Monday")
    check(dn:get(2) == "Thursday", "day_name 2024-07-04 -> Thursday")
    check(dn:get(3) == "Wednesday", "day_name 2024-12-25 -> Wednesday")
end

-- =====================================================================
-- F.3.7 normalize (= truncate D)
-- =====================================================================
do
    local nz = Series.from_table({
        P("2024-06-15T14:30:45Z"),
        P("2024-06-15T00:00:00Z"),
        NA,
    }, "datetime")

    local n = nz.dt:normalize()
    check(n._dtype == "datetime", "normalize -> datetime")
    check(iso_of(n, 1) == "2024-06-15T00:00:00.000Z", "normalize zera hora")
    check(iso_of(n, 2) == "2024-06-15T00:00:00.000Z", "normalize idempotente")
    check(n:get(3) == nil, "normalize NA -> nil")
end

-- =====================================================================
-- F.3.8 ceil — menor início-de-período >= v
-- =====================================================================
do
    local ch = Series.from_table({
        P("2024-06-15T10:20:00Z"),
        P("2024-06-15T10:00:00Z"),
    }, "datetime")

    local ceil_h = ch.dt:ceil("h")
    check(iso_of(ceil_h, 1) == "2024-06-15T11:00:00.000Z", "ceil h 10:20 -> 11:00")
    check(iso_of(ceil_h, 2) == "2024-06-15T10:00:00.000Z", "ceil h alinhado -> mesmo")

    local cm = Series.from_table({
        P("2024-01-10T00:00:00Z"),
        P("2024-12-20T00:00:00Z"),
        P("2024-03-01T00:00:00Z"),
    }, "datetime")

    local ceil_m = cm.dt:ceil("M")
    check(iso_of(ceil_m, 1) == "2024-02-01T00:00:00.000Z", "ceil M jan-10 -> fev-01")
    check(iso_of(ceil_m, 2) == "2025-01-01T00:00:00.000Z", "ceil M dez-20 -> 2025-jan-01")
    check(iso_of(ceil_m, 3) == "2024-03-01T00:00:00.000Z", "ceil M alinhado -> mesmo")

    local cq = Series.from_table({P("2024-02-15T00:00:00Z")}, "datetime")
    check(iso_of(cq.dt:ceil("Q"), 1) == "2024-04-01T00:00:00.000Z", "ceil Q fev -> abr-01")
    check(iso_of(cq.dt:ceil("Y"), 1) == "2025-01-01T00:00:00.000Z", "ceil Y 2024 -> 2025-01-01")

    check_err(function() cq.dt:ceil("X") end, "ceil unidade inválida")
end

-- =====================================================================
-- F.3.9 round — período mais próximo (half-up no empate)
-- =====================================================================
do
    local rh = Series.from_table({
        P("2024-06-15T10:20:00Z"),
        P("2024-06-15T10:40:00Z"),
        P("2024-06-15T10:30:00Z"),
    }, "datetime")

    local round_h = rh.dt:round("h")
    check(iso_of(round_h, 1) == "2024-06-15T10:00:00.000Z", "round h 10:20 -> 10:00")
    check(iso_of(round_h, 2) == "2024-06-15T11:00:00.000Z", "round h 10:40 -> 11:00")
    check(iso_of(round_h, 3) == "2024-06-15T11:00:00.000Z", "round h 10:30 empate -> 11:00 (half-up)")

    local rd = Series.from_table({
        P("2024-06-15T05:00:00Z"),
        P("2024-06-15T20:00:00Z"),
    }, "datetime")

    local round_d = rd.dt:round("D")
    check(iso_of(round_d, 1) == "2024-06-15T00:00:00.000Z", "round D 05h -> mesmo dia")
    check(iso_of(round_d, 2) == "2024-06-16T00:00:00.000Z", "round D 20h -> próximo dia")
end

-- =====================================================================
-- F.3.10 strftime
-- =====================================================================
do
    local s_strftime = Series.from_table({P("2024-02-05T14:09:07Z")}, "datetime")

    local out = s_strftime.dt:strftime("%Y-%m-%d %H:%M:%S")
    check(out._dtype == "string", "strftime -> string")
    check(out:get(1) == "2024-02-05 14:09:07", "strftime ISO básico")

    check(s_strftime.dt:strftime("%A"):get(1) == "Monday", "strftime %A -> Monday")
    check(s_strftime.dt:strftime("%a"):get(1) == "Mon", "strftime %a -> Mon")
    check(s_strftime.dt:strftime("%B"):get(1) == "February", "strftime %B -> February")
    check(s_strftime.dt:strftime("%b"):get(1) == "Feb", "strftime %b -> Feb")
    check(s_strftime.dt:strftime("%y"):get(1) == "24", "strftime %y -> 24")
    check(s_strftime.dt:strftime("%j"):get(1) == "036", "strftime %j -> 036 (dia do ano)")
    check(s_strftime.dt:strftime("%I%p"):get(1) == "02PM", "strftime %I%p -> 02PM")
    check(s_strftime.dt:strftime("100%%"):get(1) == "100%", "strftime %% -> %")
    check(s_strftime.dt:strftime("%Z"):get(1) == "%Z", "strftime token desconhecido -> literal")

    local mid = Series.from_table({
        P("2024-01-01T00:00:00Z"),
        P("2024-01-01T12:00:00Z")
    }, "datetime")

    check(mid.dt:strftime("%I %p"):get(1) == "12 AM", "strftime meia-noite -> 12 AM")
    check(mid.dt:strftime("%I %p"):get(2) == "12 PM", "strftime meio-dia -> 12 PM")

    local s_na = Series.from_table({NA}, "datetime")
    check(s_na.dt:strftime("%Y"):get(1) == nil, "strftime NA -> nil")

    check_err(function() s_strftime.dt:strftime(42) end, "strftime fmt não-string")
end

-- =====================================================================
-- Resultado
-- =====================================================================
print(string.format("OK — %d checks passaram (Series: .dt base + F.3 estendido)", n_ok))