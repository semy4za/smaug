-- tests/series/test_dt.lua
-- Accessor .dt completo: componentes base, truncate, diff, add_*, comparações,
-- sort, filter, astype, integração DataSet. F.3 estendido: is_*_start/end,
-- is_leap_year, days_in_month, month_name/day_name, normalize, round/ceil, strftime.
-- Consolida: test_datetime.lua + test_dt_extended.lua
-- Rode da raiz: luajit tests/series/test_dt.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local Series = smaug.Series
local NA     = Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

local smaug = require("smaug")
local S  = smaug.Series
local NA = smaug.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
local function approx(a, b, tol)
    tol = tol or 1e-9
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= tol
end

-- Épocas de referência (ms UTC):
-- 2024-01-15T12:30:00.500Z
-- 2024-03-20T00:00:00.000Z  (equinócio — útil para trimestre)
-- 2024-12-31T23:59:59.999Z
-- 1970-01-01T00:00:00.000Z  = 0
-- 1969-12-31T23:59:59.000Z  = -1000  (pré-epoch)
local ep_ref  = S.dt_parse("2024-01-15T12:30:00.500Z")
local ep_mar  = S.dt_parse("2024-03-20T00:00:00Z")
local ep_dec  = S.dt_parse("2024-12-31T23:59:59.999Z")
local ep_zero = S.dt_parse("1970-01-01T00:00:00Z")
local ep_neg  = S.dt_parse("1969-12-31T23:59:59Z")

-- Sanidade básica das âncoras
check(ep_zero == 0,            "epoch 1970-01-01 = 0")
check(ep_neg  == -1000,        "epoch 1969-12-31T23:59:59Z = -1000 ms")
check(ep_ref  ~= nil,          "parse 2024-01-15: não nil")
check(ep_mar  ~= nil,          "parse 2024-03-20: não nil")
check(ep_dec  ~= nil,          "parse 2024-12-31: não nil")

-- ================================================================
-- 1. Factories e construção
-- ================================================================

-- Series.new("datetime", n)
local s0 = S.new("datetime", 3)
check(s0:len() == 3,           "new: len=3")
check(s0:is_null(1),           "new: elemento nulo por padrão")
check(s0._dtype == "datetime", "new: dtype=datetime")

-- Series.datetime(n)
local sd = S.datetime(2)
check(sd:len() == 2,           "datetime factory: len=2")
check(sd._dtype == "datetime", "datetime factory: dtype correto")

-- Series.full(n, epoch_ms)
local sf = S.full(3, ep_zero, "datetime")
check(sf:len() == 3,           "full: len=3")
check(sf:get(1) == 0,          "full: get(1)=0 (epoch)")
check(sf:get(3) == 0,          "full: get(3)=0")

-- Series.from_table com números (epoch_ms)
local se = S.from_table({ep_ref, ep_mar, NA, ep_dec}, "datetime")
check(se:len() == 4,           "from_table[num]: len=4")
check(se:get(1) == ep_ref,     "from_table[num]: get(1)=ep_ref")
check(se:is_null(3),           "from_table[num]: NA → null")
check(se:get(4) == ep_dec,     "from_table[num]: get(4)=ep_dec")

-- Series.from_table com strings ISO 8601
local ss = S.from_table({"2024-01-15T12:30:00.500Z", "2024-03-20T00:00:00Z", NA}, "datetime")
check(ss:len() == 3,           "from_table[str]: len=3")
check(ss:get(1) == ep_ref,     "from_table[str]: parse correto ep_ref")
check(ss:get(2) == ep_mar,     "from_table[str]: parse correto ep_mar")
check(ss:is_null(3),           "from_table[str]: NA → null")

-- Series.dt_parse / dt_format (helpers estáticos)
local ep = S.dt_parse("2024-06-01T00:00:00Z")
check(ep ~= nil,               "dt_parse: não nil")
local fmt = S.dt_format(ep)
check(type(fmt) == "string",   "dt_format: retorna string")
check(fmt:sub(1, 10) == "2024-06-01", "dt_format: prefixo correto")

-- dt_parse: formatos suportados
check(S.dt_parse("2024-01-15") ~= nil,                     "parse: YYYY-MM-DD")
check(S.dt_parse("2024-01-15T12:30:00") ~= nil,            "parse: sem offset")
check(S.dt_parse("2024-01-15T12:30:00.500Z") ~= nil,       "parse: com ms e Z")
check(S.dt_parse("2024-01-15T14:30:00+02:00") ~= nil,      "parse: com offset +")
check(S.dt_parse("formato-invalido") == nil,                "parse: inválido → nil")
check(S.dt_parse("") == nil,                               "parse: vazio → nil")

-- dt_from_parts
local ep_parts = S.dt_from_parts(2024, 1, 15, 12, 30, 0, 500)
check(ep_parts == ep_ref,      "dt_from_parts: bate com parse ISO")
local ep_mid   = S.dt_from_parts(1970, 1, 1, 0, 0, 0, 0)
check(ep_mid == 0,             "dt_from_parts: epoch zero")
check(S.dt_from_parts(2024, 13, 1) == nil, "dt_from_parts: mês inválido → nil")
check(S.dt_from_parts(2024,  2, 30) == nil,"dt_from_parts: dia inválido → nil")

-- ================================================================
-- 2. Acesso e mutação
-- ================================================================

local sm = S.new("datetime", 3)
sm:set(1, ep_ref)
sm:set(2, "2024-03-20T00:00:00Z")  -- set via string ISO
sm:set_null(3)

check(sm:get(1) == ep_ref,     "set/get: epoch_ms")
check(sm:get(2) == ep_mar,     "set via string ISO 8601")
check(sm:get(3) == nil,        "set_null → get=nil")
check(sm:is_null(3),           "is_null após set_null")
check(not sm:is_null(1),       "is_null false após set")

-- append
local sa = S.new("datetime", 0)
sa:append(ep_zero)
sa:append("1970-01-01T00:00:00Z")
check(sa:len() == 2,           "append: len=2")
check(sa:get(1) == 0,          "append epoch_ms")
check(sa:get(2) == 0,          "append string ISO")

-- count_nonnull
local sc = S.from_table({ep_ref, NA, ep_mar, NA, ep_dec}, "datetime")
check(sc:count_nonnull() == 3, "count_nonnull: 3")

-- ================================================================
-- 3. Accessor .dt — componentes calendário
-- ================================================================

-- Série base: 2024-01-15T12:30:00.500Z
local s1 = S.from_table({ep_ref}, "datetime")

check(s1.dt:year():get(1)    == 2024, "dt:year()")
check(s1.dt:month():get(1)   == 1,    "dt:month() = 1 (janeiro)")
check(s1.dt:day():get(1)     == 15,   "dt:day() = 15")
check(s1.dt:hour():get(1)    == 12,   "dt:hour() = 12")
check(s1.dt:minute():get(1)  == 30,   "dt:minute() = 30")
check(s1.dt:second():get(1)  == 0,    "dt:second() = 0")
check(s1.dt:ms():get(1)      == 500,  "dt:ms() = 500")
-- 2024-01-15 é segunda-feira (weekday=0)
check(s1.dt:weekday():get(1) == 0,    "dt:weekday() = 0 (seg)")
check(s1.dt:quarter():get(1) == 1,    "dt:quarter() = 1 (Q1)")

-- Outros componentes com ep_mar (2024-03-20)
local s2 = S.from_table({ep_mar}, "datetime")
check(s2.dt:month():get(1)   == 3,    "dt:month() = 3 (março)")
check(s2.dt:day():get(1)     == 20,   "dt:day() = 20")
check(s2.dt:quarter():get(1) == 1,    "dt:quarter() = 1 (mar ainda Q1)")

-- ep_dec (2024-12-31)
local s3 = S.from_table({ep_dec}, "datetime")
check(s3.dt:year():get(1)    == 2024, "dt:year() dec")
check(s3.dt:month():get(1)   == 12,   "dt:month() = 12")
check(s3.dt:day():get(1)     == 31,   "dt:day() = 31")
check(s3.dt:quarter():get(1) == 4,    "dt:quarter() = 4 (Q4)")

-- Nulos propagam
local sn = S.from_table({ep_ref, NA, ep_mar}, "datetime")
check(sn.dt:year():is_null(2),   "year: NA propaga")
check(sn.dt:month():is_null(2),  "month: NA propaga")
check(sn.dt:day():is_null(2),    "day: NA propaga")

-- Componentes retornam Series<int64>
local ys = sn.dt:year()
check(ys._dtype == "int64",      "dt:year() → Series<int64>")
check(ys:get(1) == 2024,         "dt:year()[1] = 2024")
check(ys:get(3) == 2024,         "dt:year()[3] = 2024")

-- ================================================================
-- 4. format() e truncate()
-- ================================================================

-- format(): epoch_ms → string ISO 8601
local sf2 = S.from_table({ep_zero, NA, ep_ref}, "datetime")
local fmts = sf2.dt:format()
check(fmts._dtype == "string",              "format: dtype=string")
check(fmts:get(1) == "1970-01-01T00:00:00.000Z", "format: epoch zero")
check(fmts:is_null(2),                     "format: NA → null")
check(fmts:get(3):sub(1,10) == "2024-01-15", "format: ep_ref prefixo")

-- truncate('D'): trunca para meia-noite do dia
local st = S.from_table({ep_ref, NA}, "datetime")
local td = st.dt:truncate("D")
check(td._dtype == "datetime",             "truncate: dtype=datetime")
check(td:is_null(2),                       "truncate: NA propaga")
local td1 = td:get(1)
check(td1 ~= nil,                          "truncate D: não nil")
-- 2024-01-15T12:30:00.500Z truncado para D = 2024-01-15T00:00:00.000Z
local ep_day = S.dt_from_parts(2024, 1, 15, 0, 0, 0, 0)
check(td1 == ep_day,                       "truncate D: meia-noite correta")

-- truncate('M'): trunca para o 1º do mês
local tm = st.dt:truncate("M")
local ep_month = S.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
check(tm:get(1) == ep_month,               "truncate M: 1º do mês")

-- truncate('Y'): trunca para 1º de janeiro
local ty = st.dt:truncate("Y")
local ep_year = S.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
check(ty:get(1) == ep_year,                "truncate Y: 1º de jan")

-- truncate('h'): trunca para hora
local th = st.dt:truncate("h")
local ep_hour = S.dt_from_parts(2024, 1, 15, 12, 0, 0, 0)
check(th:get(1) == ep_hour,                "truncate h: hora inteira")

-- ================================================================
-- 5. diff() e add_*
-- ================================================================

-- diff(): diferença entre elementos consecutivos em ms
local MS_PER_DAY = 86400000
local ep_d1 = S.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
local ep_d2 = S.dt_from_parts(2024, 1, 2, 0, 0, 0, 0)  -- +1 dia
local ep_d3 = S.dt_from_parts(2024, 1, 4, 0, 0, 0, 0)  -- +3 dias desde d1

local sdt = S.from_table({ep_d1, ep_d2, ep_d3}, "datetime")
local diffs = sdt.dt:diff()
check(diffs._dtype == "int64",     "diff: dtype=int64")
check(diffs:is_null(1),            "diff: primeiro elemento = null")
check(diffs:get(2) == MS_PER_DAY,  "diff[2] = 1 dia em ms")
check(diffs:get(3) == 2 * MS_PER_DAY, "diff[3] = 2 dias em ms")

-- diff(2): periods=2
local d2 = sdt.dt:diff(2)
check(d2:is_null(1),               "diff(2)[1] = null")
check(d2:is_null(2),               "diff(2)[2] = null")
check(d2:get(3) == 3 * MS_PER_DAY, "diff(2)[3] = 3 dias")

-- NA propaga no diff
local sna2 = S.from_table({ep_d1, NA, ep_d3}, "datetime")
local dna  = sna2.dt:diff()
check(dna:is_null(1),              "diff NA: [1] null")
check(dna:is_null(2),              "diff NA: [2] null (era NA)")
check(dna:is_null(3),              "diff NA: [3] null (b era NA)")

-- add_ms
local base = S.from_table({ep_zero, NA}, "datetime")
local added = base.dt:add_ms(1000)
check(added:get(1) == 1000,        "add_ms: epoch+1000ms")
check(added:is_null(2),            "add_ms: NA propaga")

-- add_days
local ad = base.dt:add_days(1)
check(ad:get(1) == MS_PER_DAY,     "add_days(1): +1 dia em ms")

-- add_hours
local ah = base.dt:add_hours(2)
check(ah:get(1) == 2 * 3600000,    "add_hours(2)")

-- add_minutes
local am = base.dt:add_minutes(90)
check(am:get(1) == 90 * 60000,     "add_minutes(90)")

-- add_seconds
local as_ = base.dt:add_seconds(30)
check(as_:get(1) == 30 * 1000,     "add_seconds(30)")

-- ================================================================
-- 6. Comparações → Series<bool>
-- ================================================================

local ep_a = S.dt_from_parts(2024, 1, 1, 0, 0, 0, 0)
local ep_b = S.dt_from_parts(2024, 6, 1, 0, 0, 0, 0)
local ep_c = S.dt_from_parts(2024, 12, 1, 0, 0, 0, 0)

local sc2 = S.from_table({ep_a, ep_b, ep_c, NA}, "datetime")
local pivot = ep_b  -- comparar contra junho

-- gt: só dezembro é maior que junho
local gt = sc2:gt(pivot)
check(gt._dtype == "bool",    "gt: dtype=bool")
check(gt:get(1) == false,     "gt: jan > jun = false")
check(gt:get(2) == false,     "gt: jun > jun = false")
check(gt:get(3) == true,      "gt: dec > jun = true")
check(gt:is_null(4),          "gt: NA → NA")

-- lt
local lt = sc2:lt(pivot)
check(lt:get(1) == true,      "lt: jan < jun = true")
check(lt:get(2) == false,     "lt: jun < jun = false")
check(lt:get(3) == false,     "lt: dec < jun = false")

-- eq
local eq = sc2:eq(pivot)
check(eq:get(1) == false,     "eq: jan == jun = false")
check(eq:get(2) == true,      "eq: jun == jun = true")

-- ge
local ge = sc2:ge(pivot)
check(ge:get(1) == false,     "ge: jan >= jun = false")
check(ge:get(2) == true,      "ge: jun >= jun = true")
check(ge:get(3) == true,      "ge: dec >= jun = true")

-- le
local le = sc2:le(pivot)
check(le:get(1) == true,      "le: jan <= jun = true")
check(le:get(2) == true,      "le: jun <= jun = true")
check(le:get(3) == false,     "le: dec <= jun = false")

-- ne
local ne = sc2:ne(pivot)
check(ne:get(1) == true,      "ne: jan != jun = true")
check(ne:get(2) == false,     "ne: jun != jun = false")

-- ================================================================
-- 7. Ordenação e seleção
-- ================================================================

-- sort (ascendente)
local su = S.from_table({ep_c, ep_a, ep_b}, "datetime")
local sorted = su:sort(true)
check(sorted:get(1) == ep_a,  "sort asc: 1º = jan")
check(sorted:get(2) == ep_b,  "sort asc: 2º = jun")
check(sorted:get(3) == ep_c,  "sort asc: 3º = dec")

-- sort (descendente)
local sortd = su:sort(false)
check(sortd:get(1) == ep_c,   "sort desc: 1º = dec")
check(sortd:get(3) == ep_a,   "sort desc: 3º = jan")

-- sort com nulo: lança erro (mesmo contrato que f64/i64/str)
local snu = S.from_table({ep_b, NA, ep_a}, "datetime")
local ok_sort, _ = pcall(function() snu:sort(true) end)
check(not ok_sort,            "sort com null: lança erro")

-- argsort
local idx = su:argsort(true)
check(type(idx) == "table",   "argsort: retorna tabela")
check(idx[1] == 2,            "argsort asc: 1º idx=2 (ep_a)")
check(idx[2] == 3,            "argsort asc: 2º idx=3 (ep_b)")
check(idx[3] == 1,            "argsort asc: 3º idx=1 (ep_c)")

-- argsort com nulo → nil
check(snu:argsort(true) == nil, "argsort com null: nil")

-- take
local tk = su:take({2, 1})
check(tk:len() == 2,          "take: len=2")
check(tk:get(1) == ep_a,      "take: 1º = ep_a (era idx 2)")
check(tk:get(2) == ep_c,      "take: 2º = ep_c (era idx 1)")

-- head / tail
local shead = su:head(2)
check(shead:len() == 2,       "head(2): len=2")
check(shead:get(1) == ep_c,   "head(2): 1º = ep_c")

local stail = su:tail(1)
check(stail:len() == 1,       "tail(1): len=1")
check(stail:get(1) == ep_b,   "tail(1): 1º = ep_b")

-- dropna
local sdn = S.from_table({ep_a, NA, ep_b, NA, ep_c}, "datetime")
local dropped = sdn:dropna()
check(dropped:len() == 3,     "dropna: len=3")
check(dropped:get(1) == ep_a, "dropna: 1º = ep_a")
check(dropped:get(3) == ep_c, "dropna: 3º = ep_c")

-- filter via Series<bool>
local mask = sdn:gt(ep_a)
local filtered = sdn:filter(mask)
check(filtered:len() == 2,    "filter gt: len=2 (jun e dec)")
check(filtered:get(1) == ep_b,"filter gt: 1º = ep_b")
check(filtered:get(2) == ep_c,"filter gt: 2º = ep_c")

-- clone: independência
local cl = su:clone()
cl:set(1, ep_zero)
check(su:get(1) == ep_c,      "clone: original intacto")

-- ================================================================
-- 8. fillna / is_null
-- ================================================================

local sfn = S.from_table({ep_a, NA, NA, ep_c}, "datetime")
local filled = sfn:fillna(ep_b)
check(filled:get(1) == ep_a,   "fillna: não-nulo intacto")
check(filled:get(2) == ep_b,   "fillna: NA preenchido")
check(filled:get(3) == ep_b,   "fillna: NA preenchido [3]")
check(filled:get(4) == ep_c,   "fillna: não-nulo intacto [4]")
-- original intacto
check(sfn:is_null(2),          "fillna: original não mutado")

-- ================================================================
-- 9. astype
-- ================================================================

-- datetime → string: usa format ISO 8601
local sas = S.from_table({ep_zero, NA}, "datetime")
local as_str = sas:astype("string")
check(as_str._dtype == "string",          "astype dt→str: dtype")
check(as_str:get(1) == "1970-01-01T00:00:00.000Z", "astype dt→str: epoch zero")
check(as_str:is_null(2),                  "astype dt→str: NA → null")

-- datetime → int64: epoch_ms direto
local as_i64 = sas:astype("int64")
check(as_i64._dtype == "int64",           "astype dt→i64: dtype")
check(as_i64:get(1) == 0,                 "astype dt→i64: epoch zero = 0")
check(as_i64:is_null(2),                  "astype dt→i64: NA → null")

-- int64 → datetime: epoch_ms
local si = S.from_table({0, NA, ep_ref}, "int64")
local as_dt = si:astype("datetime")
check(as_dt._dtype == "datetime",         "astype i64→dt: dtype")
check(as_dt:get(1) == 0,                  "astype i64→dt: 0 = epoch")
check(as_dt:is_null(2),                   "astype i64→dt: NA → null")
check(as_dt:get(3) == ep_ref,             "astype i64→dt: ep_ref")

-- string → datetime: parse ISO 8601
local ss2 = S.from_table({"2024-01-15T12:30:00.500Z", NA, "invalido"}, "string")
local as_dt2 = ss2:astype("datetime")
check(as_dt2._dtype == "datetime",        "astype str→dt: dtype")
check(as_dt2:get(1) == ep_ref,            "astype str→dt: parse correto")
check(as_dt2:is_null(2),                  "astype str→dt: NA → null")
check(as_dt2:is_null(3),                  "astype str→dt: inválido → null")

-- ================================================================
-- 10. describe
-- ================================================================

local sd2 = S.from_table({ep_a, NA, ep_b, ep_c}, "datetime")
local desc = sd2:describe()
check(type(desc) == "table",                    "describe: retorna tabela")
check(desc.dtype == "datetime",                 "describe: dtype=datetime")
check(desc.count == 3,                          "describe: count=3 (sem NA)")
check(desc.nulls == 1,                          "describe: nulls=1")
check(type(desc.min) == "string",               "describe: min é string ISO")
check(type(desc.max) == "string",               "describe: max é string ISO")
check(desc.min:sub(1,10) == "2024-01-01",       "describe: min = jan")
check(desc.max:sub(1,10) == "2024-12-01",       "describe: max = dez")

-- ================================================================
-- 11. Integração com DataSet
-- ================================================================

local ds = smaug.DataSet({
    {"data",   {"2024-01-15T12:30:00.500Z", "2024-03-20T00:00:00Z",
                "2024-12-31T23:59:59.999Z"}, "datetime"},
    {"valor",  {10.0, 20.0, 30.0}, "float64"},
})

check(ds:has_column("data"),              "DataSet: coluna datetime existe")
check(ds:col("data")._dtype == "datetime","DataSet: dtype correto")

-- Acesso a componentes via DataSet
local anos = ds:col("data").dt:year()
check(anos:get(1) == 2024,                "DataSet .dt:year()[1] = 2024")
check(anos:get(2) == 2024,                "DataSet .dt:year()[2] = 2024")

-- Filter por data
local pivot2 = S.dt_from_parts(2024, 6, 1, 0, 0, 0, 0)
local mask2 = ds:col("data"):gt(pivot2)
local dsf = ds:filter(mask2)
check(dsf:nrows() == 1,                   "DataSet filter por data: 1 linha")
check(dsf:col("valor"):get(1) == 30.0,    "DataSet filter: linha correta")

-- sort_by data
local dss = ds:sort_by("data", false)  -- descendente
check(dss:col("valor"):get(1) == 30.0,    "sort_by data desc: 1º = dez")
check(dss:col("valor"):get(3) == 10.0,    "sort_by data desc: 3º = jan")

-- assign com coluna calculada de .dt (retorna novo DataSet)
local ds_with_mes = ds:assign("mes", ds:col("data").dt:month())
check(ds_with_mes:has_column("mes"),      "assign: coluna mes criada")
check(ds_with_mes:col("mes"):get(1) == 1, "assign: mes[1] = 1")
check(ds_with_mes:col("mes"):get(2) == 3, "assign: mes[2] = 3")

-- select preserva coluna datetime
local dsel = ds:select({"data", "valor"})
check(dsel:col("data")._dtype == "datetime", "select: datetime preservado")

-- head/tail com datetime
local dh = ds:head(2)
check(dh:nrows() == 2,                    "DataSet head: 2 linhas")
check(dh:col("data")._dtype == "datetime","DataSet head: dtype preservado")

-- dropna com coluna datetime
local ds_na = smaug.DataSet({
    {"data",  {ep_a, NA, ep_b}, "datetime"},
    {"v",     {1.0, 2.0, 3.0}, "float64"},
})
local dna2 = ds_na:dropna()
check(dna2:nrows() == 2,                  "DataSet dropna: 2 linhas")

-- describe do DataSet não explode com datetime
local ddesc = ds:describe()
check(type(ddesc) == "table",             "DataSet describe com datetime: não explode")
check(ddesc["data"] ~= nil,               "DataSet describe: coluna data presente")
check(ddesc["data"].dtype == "datetime",  "DataSet describe: dtype=datetime na coluna")

-- ================================================================
-- 12. Erros esperados
-- ================================================================

-- .dt em dtype errado
local ok, err = pcall(function()
    S.from_table({1.0, 2.0}, "float64").dt:year()
end)
check(not ok,                             "erro: .dt em float64")
check(err:find("datetime") ~= nil,        "erro: mensagem menciona datetime")

-- set com string inválida
local se2 = S.new("datetime", 3)
ok, err = pcall(function()
    se2:set(1, "nao-e-data")
end)
check(not ok,                             "erro: set com string inválida")

-- from_table com string inválida → erro (diferente do astype que tolera)
ok, err = pcall(function()
    S.from_table({"2024-01-15", "INVALIDO"}, "datetime")
end)
check(not ok,                             "erro: from_table string inválida")

-- append com string inválida
ok, err = pcall(function()
    local sx = S.new("datetime", 0)
    sx:append("nao-e-data")
end)
check(not ok,                             "erro: append string inválida")

-- dt_from_parts com valores inválidos
check(S.dt_from_parts(2024, 0, 1) == nil, "dt_from_parts: mês=0 → nil")
check(S.dt_from_parts(2024, 1, 0) == nil, "dt_from_parts: dia=0 → nil")
check(S.dt_from_parts(2024, 1, 1, 25, 0, 0) == nil, "dt_from_parts: hora=25 → nil")


-- =====================================================================
-- .dt F.3 estendido (de test_dt_extended.lua)
-- =====================================================================

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


print(string.format("OK — %d checks passaram (Series: .dt base + F.3 estendido)", n_ok))
