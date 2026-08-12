-- tests/series/test_constructors.lua
-- Series: construtores, acesso elementar, aritmética, reduções core,
-- lifecycle (clone/view/COW), take, head/tail, astype, describe,
-- comparações, filter, lógica Kleene, map.
-- Consolida: test_series.lua + test_i64.lua + test_bool_dtype.lua
-- Baseado estritamente no API_INDEX v1.0.
-- Rode da raiz: luajit tests/series/test_constructors.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug  = require("smaug")
local Series = smaug.Series
local NA     = Series.NA
local DataSet = smaug.DataSet
local ffi    = require("ffi")

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

local function approx(a, b, tol)
    tol = tol or 1e-9
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end
    return math.abs(a - b) < tol
end

local function check_err(fn, msg)
    local ok = pcall(fn)
    check(not ok, msg .. " (deveria lançar erro)")
end

-- =====================================================================
-- 1. Factories e Acesso Básico
-- =====================================================================
do
    -- Series.float64
    local s = Series.float64(3, "x")
    s:set(1, 1.0); s:set(2, 2.0); s:set(3, 3.0)
    check(s:len() == 3, "float64: len = 3")
    check(s:get(2) == 2.0, "float64: get 1-based")
    check(s[3] == 3.0, "float64: __index numérico")
    s[1] = 10.0
    check(s[1] == 10.0, "float64: __newindex numérico")
    
    -- nil <-> null
    s:set(2, nil)
    check(s:is_null(2), "set nil -> null")
    check(s:get(2) == nil, "get null -> nil")
    check(s:count_nonnull() == 2, "count_nonnull")
    
    -- from_table com nulos
    local t = Series.from_array({5, NA, 15, 20}, "float64", "t")
    check(t:len() == 4, "from_table: len")
    check(t:is_null(2), "from_table: nil -> null")
    check(approx(t:sum(), 40.0), "from_table: sum")
    
    -- Series.new
    local sn = Series.new("bool", 3)
    check(sn:len() == 3, "new: len")
    check(sn:is_null(1), "new: todos null")
    sn:set(1, true); sn:set(2, false); sn:set_null(3)
    check(sn:get(1) == true, "new: set true")
    check(sn:get(2) == false, "new: set false")
    check(sn:is_null(3), "new: set_null")
    
    -- smaug.Series() chamável
    local sc = smaug.Series({1, 2, 3})
    check(sc and sc:len() == 3, "init: smaug.Series({...}) chamável")
    check(sc._dtype == "int64", "init: inferência int64")
    local scf = smaug.Series({1.5, 2.5}, "float64")
    check(scf._dtype == "float64", "init: dtype explícito")
    
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
    local s = Series.from_array({10.0, NA, 3.0}, "float64")
    
    -- ignore_na = true (default)
    check(approx(s:sum(), 13.0), "sum ignora NA")
    check(approx(s:mean(), 6.5), "mean ignora NA")
    
    -- ignore_na = false
    check(s:sum(false) == nil, "sum(false) com NA -> nil")
    
    -- describe
    local dd = Series.from_array({1, 2, 3, 4, NA}, "float64"):describe()
    check(dd.count == 4 and dd.nulls == 1, "describe: count/nulls")
    check(approx(dd.mean, 2.5), "describe: mean")
    check(dd.min == 1 and dd.max == 4, "describe: min/max")
    check(approx(dd["50%"], 2.5), "describe: mediana")
end

-- =====================================================================
-- 3. Aritmética: Série × Escalar e Série × Série
-- =====================================================================
do
    -- série × escalar
    local a = Series.from_array({1, 2, 3}, "float64")
    local b = a + 10
    check(b:get(1) == 11.0 and b:get(3) == 13.0, "Series + escalar")
    local c = 2 * a
    check(c:get(2) == 4.0, "escalar * Series (comuta)")
    check(a:get(1) == 1.0, "imutabilidade: original intacto")
    
    -- série × série
    local d = Series.from_array({1, 2, 3}, "float64")
    local e = Series.from_array({10, 20, 30}, "float64")
    local f = d + e
    check(f:get(1) == 11.0 and f:get(3) == 33.0, "Series + Series")
    
    -- propagação de NA
    local g = Series.from_array({1, NA, 3}, "float64")
    local h = g + e
    check(h:is_null(2), "NA propaga em Series+Series")
end

-- =====================================================================
-- 4. int64: Aritmética, Sentinela e Precisão > 2^53
-- =====================================================================
do
    -- aritmética básica
    local i64s = Series.from_array({10, 20, 30}, "int64")
    local i64b = Series.from_array({3, 4, 5}, "int64")
    check((i64s + i64b):get(1) == 13, "i64: add")
    check((i64s - i64b):get(1) == 7, "i64: sub")
    check((i64s * i64b):get(1) == 30, "i64: mul")
    
    -- divisão: '/' é float64, floordiv é int64
    local num = Series.from_array({10, 20}, "int64")
    local den = Series.from_array({2, 0}, "int64")
    local q = num / den
    check(q._dtype == "float64", "N.3: '/' entre int64 promove a float64")
    check(q:get(1) == 5, "f64 div ok (10/2=5)")
    check(q:is_null(2), "div por zero -> null")
    
    local qi = num:floordiv(den)
    check(qi._dtype == "int64", "N.4: floordiv preserva int64")
    check(qi:get(1) == 5, "floordiv ok (10//2=5)")
    check(qi:is_null(2), "floordiv por zero -> null")
    
    -- sentinela INT64_MIN
    local k = Series.from_array({10, NA, 30}, "int64")
    check(k:sum() == 40, "i64 sum ignora NA")
    check(k:sum(false) == nil, "i64 sum(false) com NA -> nil (sentinela)")
    check(k:max() == 30, "i64 max")
    
    -- precisão > 2^53 via cdata e get_raw
    local BIG = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1
    local s = Series.int64(1)
    s:set(1, BIG)
    check(s:get_raw(1) == BIG, "9.1.1: int64 cdata preserva 2^53+1 via get_raw")
    check(s:get(1) == 9007199254740992, "9.1.1: get() comum trunca em double (limitação documentada)")
    
    -- number > 2^53 é aceito (avisa, não bloqueia)
    local ok_warn = pcall(function() s:set(1, 9007199254740994) end)
    check(ok_warn == true, "9.1.2: number > 2^53 é aceito")
    
    -- uint64_t > INT64_MAX é recusado
    local u_big = 18446744073709551615ULL
    local ok_wrap = pcall(function() s:set(1, u_big) end)
    check(ok_wrap == false, "9.1.3: uint64_t acima de INT64_MAX é recusado")
    
    -- get_raw só se aplica a int64
    local sf = Series.float64(1)
    sf:set(1, 3.5)
    local ok_rawf = pcall(function() sf:get_raw(1) end)
    check(ok_rawf == false, "get_raw recusa dtype != int64")
end

-- =====================================================================
-- 5. Fronteira do Escalar em Operações (9.3)
-- =====================================================================
do
    local A = ffi.new("int64_t", 9007199254740992LL)  -- 2^53
    local B = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1
    local s = Series.from_array({A, B}, "int64", "id")
    
    -- cdata int64_t no threshold: aceito e distingue exato
    local m = s:eq(B)
    check(m:get(1) == false and m:get(2) == true, "9.3.1: comparador aceita cdata e distingue 2^53+1")
    
    local mg = s:gt(A)
    check(mg:get(1) == false and mg:get(2) == true, "9.3.1: gt com cdata int64_t exato")
    
    -- number >= 2^53 no threshold: RECUSADO
    local ok_boundary = pcall(function() return s:eq(9007199254740993) end)
    check(ok_boundary == false, "9.3.2: number 2^53+1 (degrada p/ 2^53) recusado")
    
    -- number seguro (< 2^53): comparação normal
    local sp = Series.from_array({5, 9}, "int64")
    local ms = sp:eq(5)
    check(ms:get(1) == true and ms:get(2) == false, "9.3.3: number < 2^53 compara normal")
    
    -- aritmética escalar com cdata
    local x = Series.from_array({1}, "int64")
    check((x + B):get_raw(1) == 9007199254740994LL, "9.3.7: série int64 + cdata preserva exato")
    check((x:floordiv(B)):get_raw(1) == 0LL, "9.3.7: floordiv por cdata exato")
    
    -- number >= 2^53 na aritmética: RECUSADO
    check(pcall(function() return x + 9007199254740993 end) == false, "9.3.8: série int64 + number >= 2^53 recusado")
end

-- =====================================================================
-- 6. Promoção de Tipo (Bloco N)
-- =====================================================================
do
    -- int64 + float64 promove para float64
    local i = Series.from_array({2, 3, 4}, "int64")
    local f = Series.from_array({1.5, 2.0, 0.5}, "float64")
    check((i * f)._dtype == "float64", "N.1: int*float -> float64")
    check((i * f):get(1) == 3.0, "N.1: valor correto (2*1.5=3)")
    
    -- int * escalar float promove
    check((i * 2.5)._dtype == "float64", "N.2: int*2.5 -> float64")
    check((i * 2.5):get(1) == 5.0, "N.2: valor correto (2*2.5=5)")
    
    -- guardas: numérico × não-numérico barra
    check_err(function() return i * Series.from_array({true,false,true}, "bool") end, "N: int*bool barrado")
    check_err(function() return i * Series.from_array({"a","b","c"}, "string") end, "N: int*string barrado")
end

-- =====================================================================
-- 7. Inferência de Tipo por Famílias (12.31)
-- =====================================================================
do
    -- promoção segura dentro da família numérica
    check(Series.from_array({1, 2, 3})._dtype == "int64", "12.31.1: só inteiros → int64")
    check(Series.from_array({1, 2.5})._dtype == "float64", "12.31.1: int+float → float64")
    check(Series.from_array({1, NA, 2.5})._dtype == "float64", "12.31.1: nulos não atrapalham")
    
    -- famílias homogêneas
    check(Series.from_array({"a", "b"})._dtype == "string", "12.31.2: só strings → string")
    check(Series.from_array({true, false})._dtype == "bool", "12.31.2: só booleanos → bool")
    check(Series.from_array({})._dtype == "string", "12.31.2: lista vazia → string")
    check(Series.from_array({NA})._dtype == "string", "12.31.2: só-nula → string")
    
    -- mistura entre famílias: erro na inferência
    check_err(function() return Series.from_array({1, "x"}) end, "12.31.3: número + string recusado")
    check_err(function() return Series.from_array({true, 1}) end, "12.31.3: booleano + número recusado")
    check_err(function() return Series.from_array({"a", true}) end, "12.31.3: string + booleano recusado")
    
    -- dtype explícito ignora inferência
    local ok2, err2 = pcall(function() return Series.from_array({1, "x"}, "string") end)
    check(not ok2 and tostring(err2):match("valor para string") ~= nil, "12.31.5: dtype explícito ignora inferência")
end

-- =====================================================================
-- 8. Lifecycle: clone, view (COW), append
-- =====================================================================
do
    -- clone independente
    local orig = Series.from_array({1, 2, 3}, "float64")
    local cl = orig:clone()
    cl[1] = 99
    check(orig[1] == 1.0, "clone: original intacto")
    check(cl[1] == 99, "clone: modificado")
    
    -- view: zero-copy, COW-writable
    local base = Series.from_array({10, 20, 30, 40, 50}, "float64", "base")
    local vw = base:view(2, 3)  -- [20, 30, 40]
    check(vw:len() == 3, "view: len")
    check(vw:get(1) == 20.0 and vw:get(3) == 40.0, "view: valores")
    check(vw._c.meta.is_view == true, "view: marcada como view no struct C")
    
    -- zero-copy: reflete mutações da pai até o primeiro set
    base:set(2, 99.0)
    check(vw:get(1) == 99.0, "view: reflete mutação da pai antes do detach")
    
    -- COW: set na view destaca o buffer
    local vw_cow_ok = pcall(function() vw:set(1, 0.0) end)
    check(vw_cow_ok, "view: set via COW não dá erro")
    check(vw._c.meta.is_view == false, "view: detachada após primeiro set")
    check(vw:get(1) == 0.0, "view: set gravou o valor")
    check(base:get(2) == 99.0, "view: pai preservada pelo COW")
    
    -- COW: append em view
    local vw2 = base:view(1, 2)
    local vw_ap_ok = pcall(function() vw2:append(1.0) end)
    check(vw_ap_ok, "view: append via COW não dá erro")
    check(vw2:len() == 3, "view: append incrementou tamanho")
    check(vw2:get(3) == 1.0, "view: append gravou valor")
    
    -- view fora dos limites dá erro
    local vw_oob = pcall(function() return base:view(4, 5) end)
    check(not vw_oob, "view: fora dos limites dá erro")
    
    -- clone de view → série independente
    local vw3 = base:view(2, 3)
    local vw_clone = vw3:clone()
    vw_clone:set(1, -1.0)
    check(vw_clone:get(1) == -1.0 and vw3:get(1) == 99.0, "clone de view é independente")
    
    -- view em string (suportado, 9.2)
    local sv_base = Series.from_array({"SP", "RJ", "MG", "BA"}, "string")
    local sv_win = sv_base:view(2, 2)
    sv_win:set(1, "MINAS")
    check(sv_win:get(1) == "MINAS", "view string: set na view reflete")
    check(sv_base:get(2) == "RJ", "view string: pai intacta após COW")
    
    -- view em categorical não é suportado
    local ok_cv, e_cv = pcall(function() return Series.from_array({"x", "y"}, "categorical"):view(1,1) end)
    check(not ok_cv and e_cv:match("'categorical'") and e_cv:match("sem buffer"), "view categorical: erro com razão")
end

-- =====================================================================
-- 9. Seleção: take, head, tail, sort, argsort
-- =====================================================================
do
    -- take
    local src = Series.from_array({100, 200, 300, 400}, "float64")
    local tk = src:take({4, 1, 3})
    check(tk:len() == 3, "take: len")
    check(tk:get(1) == 400.0 and tk:get(2) == 100.0 and tk:get(3) == 300.0, "take: ordem")
    check_err(function() return src:take({1, 99}) end, "take: índice fora dos limites")
    
    -- head / tail
    local long = Series.from_array({1, 2, 3, 4, 5, 6}, "float64")
    local hd = long:head(2)
    check(hd:len() == 2 and hd:get(1) == 1.0 and hd:get(2) == 2.0, "head")
    local tl = long:tail(2)
    check(tl:len() == 2 and tl:get(1) == 5.0 and tl:get(2) == 6.0, "tail")
    
    -- sort
    local uns = Series.from_array({3, 1, 2}, "float64")
    local sorted = uns:sort(true)
    check(sorted:get(1) == 1.0 and sorted:get(3) == 3.0, "sort asc")
    local g = Series.from_array({1, NA, 3}, "float64")
    check_err(function() return g:sort() end, "sort com NA dá erro")
    
    -- tostring não crasha
    check(type(tostring(uns)) == "string", "__tostring")
end

-- =====================================================================
-- 10. astype: Conversão entre dtypes
-- =====================================================================
do
    -- f64 → i64 (trunca)
    local floats = Series.from_array({1.9, 2.1, NA, 4.7}, "float64")
    local ints = floats:astype("int64")
    check(ints._dtype == "int64", "astype: muda dtype")
    check(ints:get(1) == 1 and ints:get(2) == 2, "astype: f64->i64 trunca")
    check(ints:is_null(3), "astype: preserva null")
    
    -- i64 → f64
    local back = Series.from_array({5, 6}, "int64"):astype("float64")
    check(back._dtype == "float64" and back:get(1) == 5.0, "astype: i64->f64")
    
    -- i64 > 2^53 em astype (10.7)
    local BIG = ffi.new("int64_t", 9007199254740993LL)
    local s = Series.new("int64", 1, "big")
    s:set(1, BIG)
    check(s:astype("string"):get(1) == "9007199254740993", "10.7: i64->string > 2^53 EXATO")
    check(s:astype("int64"):astype("string"):get(1) == "9007199254740993", "10.7: i64->i64 preserva exato")
    
    -- bool → int64/string
    local sb = Series.from_array({true, false, true}, "bool")
    local si = sb:astype("int64")
    check(si._dtype == "int64" and si:get(1) == 1 and si:get(2) == 0, "astype: bool->int64")
    local ss = sb:astype("string")
    check(ss._dtype == "string" and ss:get(1) == "true", "astype: bool->string")
    
    -- int64 → bool (rígido: só 0/1)
    check_err(function() Series.from_array({0, 1, 2, 0}, "int64"):astype("bool") end, "astype: int64->bool: 2 é erro")
    
    -- string → bool
    local st = Series.from_array({"true", "false", "x"}, "string")
    local stb = st:astype("bool")
    check(stb:get(1) == true and stb:get(2) == false and stb:is_null(3), "astype: string->bool")
    
    -- datetime ↔ bool não suportado
    local bb = Series.from_array({true, false}, "bool")
    local ok1, err1 = pcall(function() return bb:astype("datetime") end)
    check(not ok1 and tostring(err1):match("não suportado") ~= nil, "10.7: bool->datetime erro limpo")
    
    -- set/append em int64 recusam não-inteiro
    local s_i64 = Series.int64(2)
    check_err(function() s_i64:set(1, 1.5) end, "i64 set recusa 1.5")
    check_err(function() s_i64:set(1, 0/0) end, "i64 set recusa NaN")
    local a = Series.int64(0)
    check_err(function() a:append(2.7) end, "i64 append recusa 2.7")
    
    -- astype f64->i64: NaN/Inf → null
    local f = Series.from_array({1.9, 2.1, -3.7, 0/0, 1/0}, "float64")
    local i = f:astype("int64")
    check(i:get(1) == 1 and i:get(2) == 2 and i:get(3) == -3, "astype: trunca em direção a zero")
    check(i:is_null(4) and i:is_null(5), "astype: NaN/Inf → null")
end

-- =====================================================================
-- 11. Comparações (gt, lt, eq, ge, le, ne)
-- =====================================================================
do
    -- f64
    local cmp = Series.from_array({10, 20, 30, 40}, "float64")
    local gt = cmp:gt(25)
    check(gt:len() == 4, "gt: len")
    check(gt:get(1) == false and gt:get(3) == true, "gt: valores")
    check(gt:count_true() == 2, "count_true")
    check(gt:any() == true and gt:all() == false, "any/all")
    
    -- ge/le/ne com NA
    local cmpf = Series.from_array({10, 20, 30, NA}, "float64")
    check(cmpf:ge(20):get(1) == false, "f64 ge: abaixo -> false")
    check(cmpf:ge(20):get(2) == true, "f64 ge: igual -> true")
    check(cmpf:ge(20):is_null(4), "f64 ge: null -> NA")
    check(cmpf:ne(20):get(1) == true, "f64 ne: diferente -> true")
    check(cmpf:ne(20):get(2) == false, "f64 ne: igual -> false")
    
    -- NaN (IEEE: NaN >= x = false)
    local nan_s = Series.from_array({0/0}, "float64")
    check(nan_s:ge(0):get(1) == false, "f64 ge: NaN -> false")
    check(nan_s:ne(0):get(1) == true, "f64 ne: NaN != 0 -> true")
    
    -- i64
    local cmpi = Series.from_array({1, 2, 3, NA}, "int64")
    check(cmpi:ge(2):get(1) == false, "i64 ge: abaixo -> false")
    check(cmpi:ge(2):get(2) == true, "i64 ge: igual -> true")
    check(cmpi:ge(2):is_null(4), "i64 ge: null -> NA")
    
    -- string
    local cmps = Series.from_array({"a", "b", "c", NA}, "string")
    check(cmps:ge("b"):get(1) == false, "str ge: abaixo -> false")
    check(cmps:ge("b"):get(2) == true, "str ge: igual -> true")
    check(cmps:ge("b"):is_null(4), "str ge: null -> NA")
    
    -- integração: df[s:ge(x)]
    local ds = DataSet({{"v", {1,2,3,4,5}, "int64"}})
    check(ds[ds.v:ge(3)]:nrows() == 3, "ge integração: >= 3 -> 3 linhas")
end

-- =====================================================================
-- 12. Boolean: filter, lógica Kleene, operadores
-- =====================================================================
do
    -- filter
    local cmp = Series.from_array({10, 20, 30, 40}, "float64")
    local gt = cmp:gt(25)
    local kept = cmp:filter(gt)
    check(kept:len() == 2 and kept:get(1) == 30.0 and kept:get(2) == 40.0, "filter")
    check_err(function() return cmp:filter({}) end, "filter exige Series<bool>")
    
    -- lógica AND/OR/XOR/NOT
    local a = Series.from_array({1, 1, 0, 0}, "int64"):gt(0)  -- [T,T,F,F]
    local b = Series.from_array({1, 0, 1, 0}, "int64"):gt(0)  -- [T,F,T,F]
    check(a:land(b):to_table()[1] == true and a:land(b):get(2) == false, "and")
    check((a + b):get(2) == true, "or via operador +")
    check((a - b):get(1) == false and (a - b):get(2) == true, "xor via operador -")
    check((a * b):get(1) == true and (a * b):get(2) == false, "and via operador *")
    check(a:lnot():get(1) == false and a:lnot():get(3) == true, "not")
    
    -- Kleene (três valores)
    local x = Series.from_array({1, NA, NA}, "int64"):gt(0)  -- [T, NA, NA]
    local y = Series.from_array({0, 0, 1}, "int64"):gt(0)    -- [F, F, T]
    local kand = x:land(y)
    check(kand:get(1) == false, "T and F = F")
    check(kand:get(2) == false, "NA and F = F (Kleene)")
    check(kand:get(3) == nil, "NA and T = NA (Kleene)")
    local kor = x:lor(y)
    check(kor:get(2) == nil, "NA or F = NA (Kleene)")
    check(kor:get(3) == true, "NA or T = T (Kleene)")
    check(x:lnot():get(2) == nil, "NOT NA = NA")
    
    -- tostring da Series<bool>
    check(type(tostring(gt)) == "string", "Series<bool> __tostring")
end

-- =====================================================================
-- 13. Bool: Construção, fillna, dropna, describe, sort
-- =====================================================================
do
    local s = Series.from_table({true, NA, false, true}, "bool")

    check(s._dtype == "bool", "dtype bool")
    check(s:len() == 4, "len")
    check(s:get(1) == true, "get true")
    check(s:get(2) == nil, "get NA -> nil")
    check(s:count_nonnull() == 3, "count_nonnull")

    -- check_value: rejeita não-boolean
    local sn = Series.new("bool", 3)
    check_err(function() sn:set(1, 42) end, "set(42) rejeitado")
    check_err(function() sn:set(1, "x") end, "set('x') rejeitado")
    check_err(function() sn:set(1, 1.5) end, "set(1.5) rejeitado")

    -- append
    local sa = Series.new("bool", 0)
    sa:append(true); sa:append(false); sa:append(NA)
    check(sa:len() == 3, "append len")
    check(sa:get(1) == true, "append true")
    check(sa:is_null(3), "append NA")

    -- fillna
    local f = s:fillna(false)
    check(f:get(2) == false, "fillna false substituiu NA")
    check(f:count_nonnull() == 4, "fillna count_nonnull")
    check_err(function() s:fillna(1) end, "fillna(1) rejeitado")

    -- dropna
    local dn = s:dropna()
    check(dn:len() == 3, "dropna len")
    check(dn:count_nonnull() == 3, "dropna nonnull")

    -- describe
    local d = s:describe()
    check(d.count == 3, "describe count")
    check(d.nulls == 1, "describe nulls")
    check(d.count_true == 2, "describe count_true")
    check(d.count_false == 1, "describe count_false")

    -- sort / argsort (sem null)
    local s2 = Series.from_table({true, false, true, false}, "bool")

    local asc = s2:sort(true)
    check(asc:get(1) == false, "sort asc: false primeiro")
    check(asc:get(3) == true, "sort asc: true terceiro")

    local desc = s2:sort(false)
    check(desc:get(1) == true, "sort desc: true primeiro")

    local p = s2:argsort(true)
    check(p[1] == 2 and p[2] == 4, "argsort estável: falses 2,4")

    check_err(function() return s:sort(true) end, "sort com null recusado")

    -- DataSet com coluna bool
    local ds = DataSet({
        {"ativo", {true, NA, false, true}, "bool"},
        {"nome", {"SP", "RJ", "MG", "RS"}, "string"},
    })

    check(ds:col("ativo")._dtype == "bool", "DataSet col dtype bool")
    check(ds:dtypes().ativo == "bool", "DataSet dtypes ativo")

    local h = ds:head(2)
    check(h:col("ativo")._dtype == "bool", "head preserva dtype bool")

    local dd = ds:describe()
    check(dd.ativo ~= nil, "describe DataSet tem ativo")
    check(dd.ativo.count_true == 2, "describe ativo count_true")
end

-- =====================================================================
-- 14. map: Transformação elemento a elemento
-- =====================================================================
do
    -- básico: transformação inteira
    local s = Series.from_array({1, 2, 3}, "int64")
    local r = s:map(function(v) return v * 2 end)
    check(r._dtype == "int64", "map: dtype inferido int64")
    check(r:get(1) == 2, "map: valor 1")
    check(r:get(3) == 6, "map: valor 3")
    check(r:len() == 3, "map: comprimento preservado")
    
    -- null na entrada -> null na saída
    local sn = Series.from_array({1, NA, 3}, "int64")
    local rn = sn:map(function(v) if v == nil then return nil end return v + 10 end)
    check(rn:get(1) == 11, "map: null in: valor 1 ok")
    check(rn:is_null(2), "map: null in -> null out")
    check(rn:get(3) == 13, "map: null in: valor 3 ok")
    
    -- fn retorna nil condicionalmente -> null
    local sc = Series.from_array({5, 15, 25}, "int64")
    local rc = sc:map(function(v) if v > 10 then return v end return nil end)
    check(rc:is_null(1), "map: nil cond -> null")
    check(rc:get(2) == 15, "map: nil cond: valor 2 ok")
    
    -- dtype explícito prevalece
    local rf = s:map(function(v) return v / 2 end, "float64")
    check(rf._dtype == "float64", "map: dtype explícito float64")
    check(rf:get(1) == 0.5, "map: valor com dtype explícito")
    
    -- inferência: float64 quando retorno tem fração
    local rf2 = s:map(function(v) return v + 0.5 end)
    check(rf2._dtype == "float64", "map: inferência float64 por fração")
    
    -- inferência: string
    local rs = s:map(function(v) return "v"..v end)
    check(rs._dtype == "string", "map: inferência string")
    check(rs:get(1) == "v1", "map: valor string")
    
    -- índice disponível na fn
    local ri = s:map(function(v, i) return v + i end)
    check(ri:get(1) == 2, "map: índice fn: 1+1=2")
    check(ri:get(3) == 6, "map: índice fn: 3+3=6")
    
    -- tipo misto -> erro com índice
    local ok1, err1 = pcall(function()
        s:map(function(v) if v == 1 then return "x" end return v end)
    end)
    check(not ok1, "map: tipo misto -> erro")
    check(err1:find("índice") ~= nil, "map: erro aponta índice")
    
    -- toda-null sem dtype -> erro
    local ok2 = pcall(function() s:map(function() return nil end) end)
    check(not ok2, "map: toda-null sem dtype -> erro")
    
    -- toda-null com dtype -> série null
    local rz = s:map(function() return nil end, "int64")
    check(rz:is_null(1) and rz:is_null(3), "map: toda-null com dtype -> série null")
    
    -- fn não é função -> erro
    local ok3 = pcall(function() s:map(42) end)
    check(not ok3, "map: fn não-função -> erro")
    
    -- imutabilidade: original intacto
    check(s:get(1) == 1, "map: original imutável")
end

-- =====================================================================
-- FIM DOS TESTES
-- =====================================================================
print(string.format("OK — %d checks passaram (Series: constructors, f64, i64, bool, aritmética, lifecycle, map)", n_ok))