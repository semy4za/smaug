-- tests/series/test_constructors.lua
-- Construtores, acesso elementar, aritmética, reduções core, lifecycle (clone/view/COW),
-- take, head/tail, astype, describe, comparações, filter, lógica Kleene, map.
-- Consolida: test_series.lua + test_i64.lua + test_bool_dtype.lua
-- Rode da raiz: luajit tests/series/test_constructors.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local Series = smaug.Series
local NA     = Series.NA

local function approx(a, b) return math.abs(a - b) < 1e-9 end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end


local smaug  = require("smaug")
local Series = smaug.Series

local function approx(a, b) return math.abs(a - b) < 1e-9 end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- ---- factories + acesso 1-based ----
local s = Series.float64(3, "x")
s:set(1, 1.0); s:set(2, 2.0); s:set(3, 3.0)
check(s:len() == 3, "len")
check(s:get(2) == 2.0, "get 1-based")
check(s[3] == 3.0, "__index numérico")
s[1] = 10.0
check(s[1] == 10.0, "__newindex numérico")

-- ---- nil <-> null ----
s:set(2, nil)
check(s:is_null(2), "set nil -> null")
check(s:get(2) == nil, "get null -> nil")
check(s:count_nonnull() == 2, "count_nonnull")

-- ---- reduções (ignore_na default = true) ----
check(approx(s:sum(), 13.0), "sum ignora NA")           -- 10 + 3
check(approx(s:mean(), 6.5), "mean ignora NA")
check(s:sum(false) == nil, "sum(false) com NA -> nil")  -- propaga NA

-- ---- from_table com nulos ----
local t = Series.from_table({5, Series.NA, 15, 20}, "float64", "t")
check(t:len() == 4, "from_table len")
check(t:is_null(2), "from_table nil -> null")
check(approx(t:sum(), 40.0), "from_table sum")

-- ---- aritmética: série × escalar ----
local a = Series.from_table({1, 2, 3}, "float64")
local b = a + 10
check(b:get(1) == 11.0 and b:get(3) == 13.0, "Series + escalar")
local c = 2 * a                       -- escalar à esquerda (comutativo)
check(c:get(2) == 4.0, "escalar * Series (comuta)")
check(a:get(1) == 1.0, "imutabilidade: original intacto")

-- ---- aritmética: série × série ----
local d = Series.from_table({1, 2, 3}, "float64")
local e = Series.from_table({10, 20, 30}, "float64")
local f = d + e
check(f:get(1) == 11.0 and f:get(3) == 33.0, "Series + Series")

-- ---- propagação de NA em série × série ----
local g = Series.from_table({1, Series.NA, 3}, "float64")
local h = g + e
check(h:is_null(2), "NA propaga em Series+Series")

-- ---- promoção e erros de tipo/tamanho (Bloco N) ----
local i64s = Series.from_table({1, 2, 3}, "int64")
-- N.1: int64 + float64 promove para float64 (não barra mais)
local promoted = i64s + d
check(promoted._dtype == "float64", "N.1: int64+float64 promove a float64")
-- guarda que CONTINUA válida: numérico × não-numérico barra
local okb = pcall(function() return i64s + Series.from_table({true,false,true},"bool") end)
check(not okb, "erro: + entre numérico e bool")
local oks = pcall(function() return i64s + Series.from_table({"a","b","c"},"string") end)
check(not oks, "erro: + entre numérico e string")

-- ---- int64: sentinela INT64_MIN vira nil ----
local k = Series.from_table({10, Series.NA, 30}, "int64")
check(k:sum() == 40, "i64 sum ignora NA")
check(k:sum(false) == nil, "i64 sum(false) com NA -> nil (INT64_MIN)")
check(k:max() == 30, "i64 max")

-- ---- divisão por zero vira null; '/' é float (N.3), :floordiv é int (N.4) ----
local num = Series.from_table({10, 20}, "int64")
local den = Series.from_table({2, 0}, "int64")
local q = num / den
check(q._dtype == "float64", "N.3: '/' entre int64 promove a float64")
check(q:get(1) == 5, "f64 div ok (10/2=5.0)")
check(q:is_null(2), "div por zero -> null")
-- :floordiv preserva int64 e o null em /0
local qi = num:floordiv(den)
check(qi._dtype == "int64", "N.4: floordiv preserva int64")
check(qi:get(1) == 5, "floordiv ok (10//2=5)")
check(qi:is_null(2), "floordiv por zero -> null")

-- ---- clone independente ----
local orig = Series.from_table({1, 2, 3}, "float64")
local cl = orig:clone()
cl[1] = 99
check(orig[1] == 1.0, "clone independente")

-- ---- sort ----
local uns = Series.from_table({3, 1, 2}, "float64")
local sorted = uns:sort(true)
check(sorted:get(1) == 1.0 and sorted:get(3) == 3.0, "sort asc")
local sort_fail = pcall(function() return g:sort() end)  -- g tem NA
check(not sort_fail, "sort com NA dá erro")

-- ---- tostring não crasha ----
check(type(tostring(s)) == "string", "__tostring")

-- ---- view: zero-copy, COW-writable, reflete a pai até o primeiro set ----
local base = Series.from_table({10, 20, 30, 40, 50}, "float64", "base")
local vw = base:view(2, 3)                       -- [20, 30, 40]
check(vw:len() == 3, "view len")
check(vw:get(1) == 20.0 and vw:get(3) == 40.0, "view valores")
check(vw._c.meta.is_view == true, "view marcada como view no struct C")

-- Enquanto não escrita, a view reflete mutações da pai (zero-copy)
base:set(2, 99.0)
check(vw:get(1) == 99.0, "view reflete mutação da pai antes do detach (zero-copy)")

-- COW: set na view destaca o buffer, preserva a pai
local vw_cow_ok = pcall(function() vw:set(1, 0.0) end)
check(vw_cow_ok,                      "set em view via COW não dá erro")
check(vw._c.meta.is_view == false,    "view detachada após primeiro set")
check(vw:get(1) == 0.0,               "set em view gravou o valor correto")
check(base:get(2) == 99.0,            "pai preservada pelo COW (não foi modificada)")

-- COW: append em view fresca destaca e adiciona o elemento
local vw2 = base:view(1, 2)
local vw_ap_ok = pcall(function() vw2:append(1.0) end)
check(vw_ap_ok,                    "append em view via COW não dá erro")
check(vw2._c.meta.is_view == false,"view detachada após append")
check(vw2:len() == 3,              "append em view incrementou o tamanho")
check(vw2:get(3) == 1.0,          "append em view gravou o valor correto")
check(base:get(1) == 10.0,        "pai preservada após append COW")
local vw_oob = pcall(function() return base:view(4, 5) end)
check(not vw_oob, "view fora dos limites dá erro")

-- clone de view → série independente e mutável (view fresca para estado limpo)
local vw3 = base:view(2, 3)
local vw_clone = vw3:clone()
vw_clone:set(1, -1.0)
check(vw_clone:get(1) == -1.0 and vw3:get(1) == 99.0, "clone de view é independente/mutável")

-- ---- bool: view zero-copy + COW (bool é mutável, tem set; mecânica idêntica a f64) ----
local bbase = Series.from_table({true, false, true, false, true}, "bool", "bbase")
local bvw = bbase:view(2, 3)                       -- [false, true, false]
check(bvw:len() == 3, "bool view len")
check(bvw:get(1) == false and bvw:get(2) == true, "bool view valores")
check(bvw._c.meta.is_view == true, "bool view marcada como view no struct C")

-- enquanto não escrita, reflete mutações da pai (zero-copy)
bbase:set(2, true)
check(bvw:get(1) == true, "bool view reflete mutação da pai antes do detach")

-- COW: set na view destaca o buffer, preserva a pai
local bvw_cow_ok = pcall(function() bvw:set(1, false) end)
check(bvw_cow_ok,                    "bool set em view via COW não dá erro")
check(bvw._c.meta.is_view == false,  "bool view detachada após primeiro set")
check(bvw:get(1) == false,           "bool set em view gravou o valor correto")
check(bbase:get(2) == true,          "pai bool preservada pelo COW")

-- COW: append em view fresca destaca e adiciona
local bvw2 = bbase:view(1, 2)
local bvw_ap_ok = pcall(function() bvw2:append(true) end)
check(bvw_ap_ok,                     "bool append em view via COW não dá erro")
check(bvw2._c.meta.is_view == false, "bool view detachada após append")
check(bvw2:len() == 3,               "bool append em view incrementou o tamanho")
check(bvw2:get(3) == true,           "bool append em view gravou o valor correto")

-- COW: set_null em view fresca destaca e grava NA (bool tem nulos)
local bvw3 = bbase:view(1, 3)
local bvw_sn_ok = pcall(function() bvw3:set_null(1) end)
check(bvw_sn_ok,                     "bool set_null em view via COW não dá erro")
check(bvw3._c.meta.is_view == false, "bool view detachada após set_null")
check(bvw3:get(1) == nil,            "bool set_null em view gravou NA")
check(bbase:get(1) == true,          "pai bool preservada após set_null COW")

-- view de bool fora dos limites dá erro
local bvw_oob = pcall(function() return bbase:view(4, 5) end)
check(not bvw_oob, "bool view fora dos limites dá erro")

-- view() de string agora é suportado (9.2): funciona + COW. Categorical não.
local sv_str = Series.from_table({"SP","RJ","MG","BA"}, "string"):view(2, 2)  -- [RJ,MG]
check(sv_str:get(1) == "RJ" and sv_str:get(2) == "MG", "view string: janela correta")
local sv_base = Series.from_table({"SP","RJ","MG","BA"}, "string")
local sv_win  = sv_base:view(2, 2)
sv_win:set(1, "MINAS")                        -- detach COW
check(sv_win:get(1) == "MINAS",               "view string: set na view reflete")
check(sv_base:get(2) == "RJ",                 "view string: pai intacto após COW")
local ok_cv, e_cv = pcall(function() return Series.from_table({"x","y"}, "categorical"):view(1,1) end)
check(not ok_cv and e_cv:match("'categorical'") and e_cv:match("sem buffer"),
      "view categorical: erro com razão correta (Lua puro)")

-- ---- take: seleção por índices (cópia independente) ----
local src = Series.from_table({100, 200, 300, 400}, "float64")
local tk = src:take({4, 1, 3})
check(tk:len() == 3, "take len")
check(tk:get(1) == 400.0 and tk:get(2) == 100.0 and tk:get(3) == 300.0, "take ordem")
local tk_oob = pcall(function() return src:take({1, 99}) end)
check(not tk_oob, "take índice fora dos limites dá erro")

-- ---- head / tail (retornam Series) ----
local long = Series.from_table({1, 2, 3, 4, 5, 6}, "float64")
local hd = long:head(2)
check(hd:len() == 2 and hd:get(1) == 1.0 and hd:get(2) == 2.0, "head")
local tl = long:tail(2)
check(tl:len() == 2 and tl:get(1) == 5.0 and tl:get(2) == 6.0, "tail")

-- ---- astype: conversão entre dtypes ----
local floats = Series.from_table({1.9, 2.1, Series.NA, 4.7}, "float64")
local ints = floats:astype("int64")
check(ints._dtype == "int64", "astype muda dtype")
check(ints:get(1) == 1 and ints:get(2) == 2, "astype f64->i64 trunca")
check(ints:is_null(3), "astype preserva null")
local back = Series.from_table({5, 6}, "int64"):astype("float64")
check(back._dtype == "float64" and back:get(1) == 5.0, "astype i64->f64")

-- ---- describe ----
local dd = Series.from_table({1, 2, 3, 4, Series.NA}, "float64"):describe()
check(dd.count == 4 and dd.nulls == 1, "describe count/nulls")
check(approx(dd.mean, 2.5), "describe mean")
check(dd.min == 1 and dd.max == 4, "describe min/max")
check(approx(dd["50%"], 2.5), "describe mediana")

-- ===== Camada bool: comparações, filter, lógica Kleene =====

-- ---- comparações -> Series<bool> ----
local cmp = Series.from_table({10, 20, 30, 40}, "float64")
local gt = cmp:gt(25)                       -- [F, F, T, T]
check(gt:len() == 4, "gt len")
check(gt:get(1) == false and gt:get(3) == true, "gt valores")
check(gt:count_true() == 2, "count_true")
check(gt:any() == true and gt:all() == false, "any/all")
local lt = cmp:lt(25)
check(lt:get(1) == true and lt:get(4) == false, "lt")
local eq = cmp:eq(30)
check(eq:get(3) == true and eq:count_true() == 1, "eq")

-- ---- filter ----
local kept = cmp:filter(gt)
check(kept:len() == 2 and kept:get(1) == 30.0 and kept:get(2) == 40.0, "filter")
local filt_dtype = pcall(function() return cmp:filter({}) end)
check(not filt_dtype, "filter exige Series<bool>")

-- ---- lógica AND/OR/XOR/NOT (métodos e operadores * + -) ----
local a = Series.from_table({1, 1, 0, 0}, "int64"):gt(0)   -- [T,T,F,F]
local b = Series.from_table({1, 0, 1, 0}, "int64"):gt(0)   -- [T,F,T,F]
check(a:land(b):to_table()[1] == true and a:land(b):get(2) == false, "and")
check((a + b):get(2) == true, "or via operador +")          -- T or F
check((a - b):get(1) == false and (a - b):get(2) == true, "xor via operador -")
check((a * b):get(1) == true and (a * b):get(2) == false, "and via operador *")
check(a:lnot():get(1) == false and a:lnot():get(3) == true, "not")

-- ---- Kleene (três valores) ----
local x = Series.from_table({1, Series.NA, Series.NA}, "int64"):gt(0)  -- [T, NA, NA]
local y = Series.from_table({0, 0, 1}, "int64"):gt(0)                  -- [F, F, T]
local kand = x:land(y)
check(kand:get(1) == false, "T and F = F")
check(kand:get(2) == false, "NA and F = F (Kleene)")
check(kand:get(3) == nil,   "NA and T = NA (Kleene)")
local kor = x:lor(y)
check(kor:get(2) == nil,  "NA or F = NA (Kleene)")
check(kor:get(3) == true, "NA or T = T (Kleene)")
check(x:lnot():get(2) == nil, "NOT NA = NA")

-- ---- tostring da Series<bool> ----
check(type(tostring(gt)) == "string", "Series<bool> __tostring")

-- ---- ge / le / ne ----
-- f64
local cmpf = Series.from_table({10, 20, 30, smaug.NA}, "float64")
check(cmpf:ge(20):get(1) == false,  "f64 ge: abaixo -> false")
check(cmpf:ge(20):get(2) == true,   "f64 ge: igual -> true")
check(cmpf:ge(20):get(3) == true,   "f64 ge: acima -> true")
check(cmpf:ge(20):is_null(4),       "f64 ge: null -> NA")
check(cmpf:le(20):get(1) == true,   "f64 le: abaixo -> true")
check(cmpf:le(20):get(2) == true,   "f64 le: igual -> true")
check(cmpf:le(20):get(3) == false,  "f64 le: acima -> false")
check(cmpf:le(20):is_null(4),       "f64 le: null -> NA")
check(cmpf:ne(20):get(1) == true,   "f64 ne: diferente -> true")
check(cmpf:ne(20):get(2) == false,  "f64 ne: igual -> false")
check(cmpf:ne(20):is_null(4),       "f64 ne: null -> NA")

-- f64: NaN (valor presente, não null) — IEEE: NaN >= x = false
local nan_s = Series.from_table({0/0}, "float64")
check(nan_s:ge(0):get(1) == false,  "f64 ge: NaN -> false (IEEE)")
check(nan_s:ne(0):get(1) == true,   "f64 ne: NaN != 0 -> true (IEEE)")

-- i64
local cmpi = Series.from_table({1, 2, 3, smaug.NA}, "int64")
check(cmpi:ge(2):get(1) == false,   "i64 ge: abaixo -> false")
check(cmpi:ge(2):get(2) == true,    "i64 ge: igual -> true")
check(cmpi:ge(2):is_null(4),        "i64 ge: null -> NA")
check(cmpi:le(2):get(3) == false,   "i64 le: acima -> false")
check(cmpi:le(2):get(2) == true,    "i64 le: igual -> true")
check(cmpi:ne(2):get(1) == true,    "i64 ne: diferente -> true")
check(cmpi:ne(2):get(2) == false,   "i64 ne: igual -> false")

-- string
local cmps = Series.from_table({"a","b","c",smaug.NA}, "string")
check(cmps:ge("b"):get(1) == false, "str ge: abaixo -> false")
check(cmps:ge("b"):get(2) == true,  "str ge: igual -> true")
check(cmps:ge("b"):get(3) == true,  "str ge: acima -> true")
check(cmps:ge("b"):is_null(4),      "str ge: null -> NA")
check(cmps:le("b"):get(1) == true,  "str le: abaixo -> true")
check(cmps:le("b"):get(3) == false, "str le: acima -> false")
check(cmps:ne("b"):get(1) == true,  "str ne: diferente -> true")
check(cmps:ne("b"):get(2) == false, "str ne: igual -> false")
check(cmps:ne("b"):is_null(4),      "str ne: null -> NA")

-- integração: df[s:ge(x)]
local ds = smaug.DataSet({{"v", {1,2,3,4,5}, "int64"}})
check(ds[ds.v:ge(3)]:nrows() == 3,  "ge integração: >= 3 -> 3 linhas")
check(ds[ds.v:le(2)]:nrows() == 2,  "le integração: <= 2 -> 2 linhas")
check(ds[ds.v:ne(3)]:nrows() == 4,  "ne integração: != 3 -> 4 linhas")

-- ===== map =====
local function test_map()
    -- básico: transformação inteira
    local s = Series.from_table({1, 2, 3}, "int64")
    local r = s:map(function(v) return v * 2 end)
    check(r._dtype == "int64",      "map: dtype inferido int64")
    check(r:get(1) == 2,            "map: valor 1")
    check(r:get(3) == 6,            "map: valor 3")
    check(r:len() == 3,             "map: comprimento preservado")

    -- null na entrada -> null na saída
    local sn = Series.from_table({1, smaug.NA, 3}, "int64")
    local rn = sn:map(function(v) if v == nil then return nil end return v + 10 end)
    check(rn:get(1) == 11,          "map: null in: valor 1 ok")
    check(rn:is_null(2),            "map: null in -> null out")
    check(rn:get(3) == 13,          "map: null in: valor 3 ok")

    -- fn retorna nil condicionalmente -> null
    local sc = Series.from_table({5, 15, 25}, "int64")
    local rc = sc:map(function(v) if v > 10 then return v end return nil end)
    check(rc:is_null(1),            "map: nil cond -> null")
    check(rc:get(2) == 15,          "map: nil cond: valor 2 ok")
    check(rc:get(3) == 25,          "map: nil cond: valor 3 ok")

    -- dtype explícito prevalece
    local rf = s:map(function(v) return v / 2 end, "float64")
    check(rf._dtype == "float64",   "map: dtype explícito float64")
    check(rf:get(1) == 0.5,         "map: valor com dtype explícito")

    -- inferência: float64 quando retorno tem fração
    local rf2 = s:map(function(v) return v + 0.5 end)
    check(rf2._dtype == "float64",  "map: inferência float64 por fração")

    -- inferência: string
    local rs = s:map(function(v) return "v"..v end)
    check(rs._dtype == "string",    "map: inferência string")
    check(rs:get(1) == "v1",        "map: valor string")

    -- índice disponível na fn
    local ri = s:map(function(v, i) return v + i end)
    check(ri:get(1) == 2,           "map: índice fn: 1+1=2")
    check(ri:get(3) == 6,           "map: índice fn: 3+3=6")

    -- tipo misto -> erro com índice
    local ok1, err1 = pcall(function()
        s:map(function(v) if v == 1 then return "x" end return v end)
    end)
    check(not ok1,                  "map: tipo misto -> erro")
    check(err1:find("índice") ~= nil, "map: erro aponta índice")

    -- toda-null sem dtype -> erro
    local ok2 = pcall(function() s:map(function() return nil end) end)
    check(not ok2,                  "map: toda-null sem dtype -> erro")

    -- toda-null com dtype -> série null
    local rz = s:map(function() return nil end, "int64")
    check(rz:is_null(1) and rz:is_null(3), "map: toda-null com dtype -> série null")

    -- fn não é função -> erro
    local ok3 = pcall(function() s:map(42) end)
    check(not ok3,                  "map: fn não-função -> erro")

    -- imutabilidade: original intacto
    check(s:get(1) == 1,            "map: original imutável")
end
test_map()


-- =====================================================================
-- int64 dedicado (de test_i64.lua)
-- =====================================================================


local smaug = require("smaug")
local S     = smaug.Series

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
local function approx(a, b) return math.abs(a - b) < 1e-9 end

-- ===================================================================
-- Aritmética elemento-a-elemento
-- ===================================================================
do
    local a = S.from_table({10, 20, 30}, "int64")
    local b = S.from_table({3, 4, 5}, "int64")
    check((a + b):get(1) == 13, "i64 add")
    check((a - b):get(1) == 7,  "i64 sub")
    check((a * b):get(1) == 30, "i64 mul")
    -- N.3: '/' é divisão verdadeira → float64 (10/3 = 3.333...)
    local d = a / b
    check(d._dtype == "float64", "N.3: int64 '/' promove a float64")
    check(math.abs(d:get(1) - 10/3) < 1e-9, "i64 '/' = divisão verdadeira")
    -- N.4: divisão inteira (truncada) agora via :floordiv
    local fd = a:floordiv(b)
    check(fd._dtype == "int64", "N.4: floordiv preserva int64")
    check(fd:get(1) == 3, "i64 floordiv trunca (10//3=3)")
    check((a + b):len() == 3, "i64 add preserva tamanho")
end

-- ===================================================================
-- Divisão por zero → NULL; propagação de NA na aritmética
-- ===================================================================
do
    local num = S.from_table({10, 20, 30}, "int64")
    local den = S.from_table({2, 0, 3}, "int64")
    local q = num / den
    check(q:get(1) == 5, "i64 div ok")
    check(q:is_null(2), "i64 div por zero → null")
    check(q:get(3) == 10, "i64 div terceiro ok")

    -- NA em um operando propaga para o resultado
    local x = S.from_table({1, smaug.NA, 3}, "int64")
    local y = S.from_table({1, 2, 3}, "int64")
    local r = x + y
    check(r:get(1) == 2, "i64 add [1] ok")
    check(r:is_null(2), "i64 add propaga NA")
    check(r:get(3) == 6, "i64 add [3] ok")
end

-- ===================================================================
-- Operações com escalar
-- ===================================================================
do
    local a = S.from_table({10, 20, 30}, "int64")
    check((a + 100):get(1) == 110, "i64 add_scalar")
    check((a - 5):get(2) == 15, "i64 sub_scalar")
    check((a * 2):get(3) == 60, "i64 mul_scalar")
    check((a / 10):get(2) == 2, "i64 div_scalar inteira")
    -- divisão escalar por zero → null em todas as posições
    local z = a / 0
    check(z:is_null(1) and z:is_null(2) and z:is_null(3), "i64 div_scalar por zero → null")
end

-- ===================================================================
-- Reduções (min, max, mean, var, std populacionais)
-- ===================================================================
do
    local a = S.from_table({10, 20, 30}, "int64")
    check(a:sum() == 60, "i64 sum")
    check(a:min() == 10, "i64 min")
    check(a:max() == 30, "i64 max")
    check(approx(a:mean(), 20.0), "i64 mean")
    -- var amostral (ddof=1): ((10-20)²+(20-20)²+(30-20)²)/(3-1) = 200/2 = 100
    check(approx(a:var(), 100.0), "i64 var amostral")
    check(approx(a:std(), 10.0), "i64 std amostral")

    -- reduções ignoram NA por padrão
    local k = S.from_table({10, smaug.NA, 30}, "int64")
    check(k:sum() == 40, "i64 sum ignora NA")
    check(k:min() == 10, "i64 min ignora NA")
    check(k:max() == 30, "i64 max ignora NA")
    -- com ignore_na=false e havendo NA → sentinela → nil
    check(k:sum(false) == nil, "i64 sum(false) com NA → nil")
end

-- ===================================================================
-- Reduções em casos degenerados
-- ===================================================================
do
    local one = S.from_table({42}, "int64")
    check(one:sum() == 42 and one:min() == 42 and one:max() == 42, "i64 reduções 1-elemento")
    check(one:var() == nil, "i64 var de 1 elemento = NA (amostral, n<2)")

    local allnull = S.from_table({smaug.NA, smaug.NA}, "int64")
    check(allnull:sum() == 0, "i64 sum toda-nula = 0")
    check(allnull:min() == nil, "i64 min toda-nula = nil")
    check(allnull:max() == nil, "i64 max toda-nula = nil")
    check(allnull:mean() == nil, "i64 mean toda-nula = nil")
end

-- ===================================================================
-- Comparações (gt, lt, eq) → Series<bool>
-- ===================================================================
do
    local a = S.from_table({10, 20, 30}, "int64")
    check(a:gt(15):count_true() == 2, "i64 gt")
    check(a:lt(25):count_true() == 2, "i64 lt")
    check(a:eq(20):count_true() == 1, "i64 eq")
    -- comparação com NA → NA (não conta como true)
    local k = S.from_table({10, smaug.NA, 30}, "int64")
    local m = k:gt(15)
    check(m:get(1) == false, "i64 gt: 10>15 false")
    check(m:is_null(2), "i64 gt: NA propaga")
    check(m:get(3) == true, "i64 gt: 30>15 true")
    check(m:count_true() == 1, "i64 gt count_true ignora NA")
end

-- ===================================================================
-- Ordenação (sort asc/desc, argsort) e recusa de NULL
-- ===================================================================
do
    local a = S.from_table({30, 10, 20}, "int64")
    local asc = a:sort()
    check(asc:get(1) == 10 and asc:get(2) == 20 and asc:get(3) == 30, "i64 sort asc")
    local desc = a:sort(false)
    check(desc:get(1) == 30 and desc:get(3) == 10, "i64 sort desc")
    -- argsort devolve permutação 1-based
    local idx = a:argsort()
    check(idx[1] == 2 and idx[2] == 3 and idx[3] == 1, "i64 argsort (índices do menor→maior)")

    -- sort recusa série com NULL
    local k = S.from_table({3, smaug.NA, 1}, "int64")
    check(pcall(function() return k:sort() end) == false, "i64 sort recusa NULL")
    check(k:argsort() == nil, "i64 argsort com NULL → nil")
end

-- ===================================================================
-- Seleção (take, filter)
-- ===================================================================
do
    local a = S.from_table({10, 20, 30, 40}, "int64")
    local t = a:take({4, 1, 3})
    check(t:len() == 3, "i64 take comprimento")
    check(t:get(1) == 40 and t:get(2) == 10 and t:get(3) == 30, "i64 take reordena")

    local f = a:filter(a:gt(15))
    check(f:len() == 3, "i64 filter len = count_true")
    check(f:get(1) == 20, "i64 filter primeiro elemento")
end

-- ===================================================================
-- Lifecycle: clone (independente), view (compartilha), append (grow)
-- ===================================================================
do
    local a = S.from_table({1, 2, 3}, "int64")
    -- clone independente
    local c = a:clone()
    c:set(1, 999)
    check(a:get(1) == 1, "i64 clone independente (original intacto)")
    check(c:get(1) == 999, "i64 clone mutável")

    -- view compartilha
    local v = a:view(2, 2)   -- [2,3]
    check(v:len() == 2 and v:get(1) == 2 and v:get(2) == 3, "i64 view janela")

    -- append faz crescer
    local g = S.int64(0)
    for i = 1, 50 do g:append(i) end
    check(g:len() == 50, "i64 append grow comprimento")
    check(g:get(1) == 1 and g:get(50) == 50, "i64 append valores")
    g:append(nil)   -- append null
    check(g:is_null(51), "i64 append_null")
    check(g:count_nonnull() == 50, "i64 count_nonnull após append_null")
end

-- ===================================================================
-- astype i64 ↔ f64 (paridade de conversão)
-- ===================================================================
do
    local i = S.from_table({5, 6, 7}, "int64")
    local f = i:astype("float64")
    check(f:get(1) == 5.0, "i64→f64 astype")
    local back = f:astype("int64")
    check(back:get(1) == 5, "f64→i64 astype ida-volta")
    check(back._dtype == "int64", "i64 astype preserva dtype final")
end

-- ===================================================================
-- Degrau 10.7: astype de int64 > 2^53 falha VISIVEL nos pares que
-- perdem digitos (i64->i64, i64->string). i64->f64 e i64->bool seguem
-- OK (double e o destino correto; 0/1 cabem sob 2^53).
-- ===================================================================
do
    local ffi = require("ffi")
    local function mk()
        local s = S.new("int64", 1, "big")
        s:set(1, ffi.new("int64_t", 9007199254740993LL))   -- 2^53 + 1
        return s
    end
    -- 10.7 Passo B: o degrau saiu — a conversão migrou ao Anel 0 e agora
    -- PRESERVA exato (antes recusava). Exatidão verificada via ->string
    -- (o get() de i64 converte a double; ->string mostra os dígitos reais).
    check(mk():astype("string"):get(1) == "9007199254740993",
          "10.7: astype i64->string > 2^53 EXATO (era recusa; conserto no Anel 0)")
    check(mk():astype("int64"):astype("string"):get(1) == "9007199254740993",
          "10.7: astype i64->i64 > 2^53 clone preserva exato (era recusa)")
    -- round-trip str->i64->str > 2^53 exato ponta-a-ponta (Anel 0)
    check(S.from_table({"9007199254740993"}, "string")
            :astype("int64"):astype("string"):get(1) == "9007199254740993",
          "10.7: round-trip str->i64->str > 2^53 EXATO")
    -- pares seguros permanecem funcionando
    check(mk():astype("float64")._dtype == "float64",
          "10.7: astype i64->f64 permitido (double e o destino correto)")
    local sb = S.new("int64", 2, "b")
    sb:set(1, ffi.new("int64_t", 0LL)); sb:set(2, ffi.new("int64_t", 1LL))
    local b = sb:astype("bool")
    check(b:get(1) == false and b:get(2) == true,
          "10.7: astype i64->bool 0/1 permitido")
    check(S.from_table({10, 20}, "int64"):astype("int64"):get(1) == 10,
          "10.7: astype i64->i64 <=2^53 intacto (nao-regressao)")
end

-- 10.7 Passo B: cantos datetime<->bool não têm semântica natural -> erro limpo
do
    local bb = S.from_table({true, false}, "bool")
    local ok1, err1 = pcall(function() return bb:astype("datetime") end)
    check(not ok1 and tostring(err1):match("não suportado") ~= nil,
          "10.7: astype bool->datetime erro limpo")
    local dd = S.from_table({0, 1}, "int64"):astype("datetime")
    local ok2, err2 = pcall(function() return dd:astype("bool") end)
    check(not ok2 and tostring(err2):match("não suportado") ~= nil,
          "10.7: astype datetime->bool erro limpo")
end

-- ===================================================================
-- Sem coerção: set/append em int64 recusam não-inteiro (CODE_REVIEW A7).
-- astype f64->i64 é a conversão EXPLÍCITA (trunca em direção a zero).
-- ===================================================================
do
    local s = S.int64(2)
    -- set recusa não-inteiro, NaN e Inf (não trunca silenciosamente)
    check(pcall(function() s:set(1, 1.5) end) == false, "i64 set recusa 1.5")
    check(pcall(function() s:set(1, 0/0) end) == false, "i64 set recusa NaN")
    check(pcall(function() s:set(1, 1/0) end) == false, "i64 set recusa Inf")
    s:set(1, 5)  -- inteiro funciona
    check(s:get(1) == 5, "i64 set aceita inteiro")
    -- append idem
    local a = S.int64(0)
    check(pcall(function() a:append(2.7) end) == false, "i64 append recusa 2.7")
    a:append(7)
    check(a:get(1) == 7, "i64 append aceita inteiro")

    -- astype f64->i64: conversão explícita TRUNCA em direção a zero
    local f = S.from_table({1.9, 2.1, -3.7, 0/0, 1/0}, "float64")
    local i = f:astype("int64")
    check(i:get(1) == 1,  "astype trunca 1.9 -> 1")
    check(i:get(2) == 2,  "astype trunca 2.1 -> 2")
    check(i:get(3) == -3, "astype trunca -3.7 -> -3 (direção a zero)")
    check(i:is_null(4),   "astype NaN -> null (sem repr. em int64)")
    check(i:is_null(5),   "astype Inf -> null (sem repr. em int64)")
end


-- ===================================================================
-- 9.1: int64 acima de 2^53 — cdata na entrada (check_value) e get_raw
-- na saída, preservando precisão de 64 bits ponta a ponta.
-- ===================================================================
do
    local ffi = require("ffi")
    local s = S.int64(1)

    -- 9.1.1 — cdata int64_t: aceito, preserva valor exato acima de 2^53
    local big = 9007199254740993LL  -- 2^53 + 1, não representável em double
    s:set(1, big)
    check(s:get_raw(1) == big, "9.1.1 int64 cdata preserva 2^53+1 via get_raw")

    -- get() comum ainda passa por tonumber (double) — perda esperada e
    -- documentada (get_raw existe exatamente para contornar isso).
    check(s:get(1) == 9007199254740992,
          "9.1.1 get() comum trunca em double (limitação conhecida, documentada)")

    -- cdata uint64_t dentro do range de int64: aceito
    local u_ok = ffi.new("uint64_t", 123)
    s:set(1, u_ok)
    check(s:get_raw(1) == 123LL, "9.1.1 uint64_t dentro do range aceito")

    -- 9.1.2 — number > 2^53: aceito (avisar-mas-aceitar), sem erro
    local ok_warn = pcall(function() s:set(1, 9007199254740994) end)
    check(ok_warn == true, "9.1.2 number > 2^53 é aceito (avisa, não bloqueia)")

    -- 9.1.3 — uint64_t > INT64_MAX: recusado (sem wraparound silencioso)
    local u_big = 18446744073709551615ULL  -- maior uint64_t possível
    local ok_wrap = pcall(function() s:set(1, u_big) end)
    check(ok_wrap == false, "9.1.3 uint64_t acima de INT64_MAX é recusado")

    -- cdata float/double continuam recusados (mesma exigência do A7)
    local ok_fcdata = pcall(function() s:set(1, ffi.new("double", 3.5)) end)
    check(ok_fcdata == false, "9.1.1 cdata double continua recusado")

    -- get_raw só se aplica a int64
    local sf = S.float64(1)
    sf:set(1, 3.5)
    local ok_rawf = pcall(function() sf:get_raw(1) end)
    check(ok_rawf == false, "get_raw recusa dtype != int64")
end



local smaug  = require("smaug")
local Series = smaug.Series
local NA     = Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- ---- from_table + acesso ----
local s = Series.from_table({true, NA, false, true}, "bool")
check(s._dtype == "bool",        "dtype bool")
check(s:len()  == 4,             "len")
check(s:get(1) == true,          "get true")
check(s:get(2) == nil,           "get NA -> nil")
check(s:get(3) == false,         "get false")
check(s:get(4) == true,          "get true 2")

-- ---- Series.new ----
local sn = Series.new("bool", 3)
check(sn:len() == 3,             "new len")
check(sn:is_null(1),             "new todos null")
sn:set(1, true); sn:set(2, false); sn:set_null(3)
check(sn:get(1) == true,         "new set true")
check(sn:get(2) == false,        "new set false")
check(sn:is_null(3),             "new set_null")

-- ---- check_value: rejeita não-boolean ----
local ok, _ = pcall(function() sn:set(1, 42) end)
check(not ok, "set(42) rejeitado")
ok, _ = pcall(function() sn:set(1, "x") end)
check(not ok, "set('x') rejeitado")
ok, _ = pcall(function() sn:set(1, 1.5) end)
check(not ok, "set(1.5) rejeitado")

-- ---- append ----
local sa = Series.new("bool", 0)
sa:append(true); sa:append(false); sa:append(NA)
check(sa:len() == 3,             "append len")
check(sa:get(1) == true,         "append true")
check(sa:get(2) == false,        "append false")
check(sa:is_null(3),             "append NA")

-- ---- count_nonnull / is_null ----
check(s:count_nonnull() == 3,    "count_nonnull")
check(s:is_null(2),              "is_null(2) = true")
check(not s:is_null(1),          "is_null(1) = false")

-- ---- fillna ----
local f = s:fillna(false)
check(f:get(2) == false,         "fillna false substituiu NA")
check(f:get(1) == true,          "fillna nao-null inalterado")
check(f:count_nonnull() == 4,    "fillna count_nonnull")
-- fillna rejeita não-boolean
ok, _ = pcall(function() s:fillna(1) end)
check(not ok, "fillna(1) rejeitado")

-- ---- dropna ----
local dn = s:dropna()
check(dn:len() == 3,             "dropna len")
check(dn:count_nonnull() == 3,   "dropna nonnull")

-- ---- describe ----
local d = s:describe()
check(d.count      == 3,         "describe count")
check(d.nulls      == 1,         "describe nulls")
check(d.count_true == 2,         "describe count_true")
check(d.count_false== 1,         "describe count_false")

-- ---- sort / argsort (sem null) ----
local s2 = Series.from_table({true, false, true, false}, "bool")
local asc = s2:sort(true)
check(asc:get(1) == false,       "sort asc: false primeiro")
check(asc:get(2) == false,       "sort asc: false segundo")
check(asc:get(3) == true,        "sort asc: true terceiro")
check(asc:get(4) == true,        "sort asc: true quarto")
local desc = s2:sort(false)
check(desc:get(1) == true,       "sort desc: true primeiro")
check(desc:get(4) == false,      "sort desc: false ultimo")

local p = s2:argsort(true)
check(p[1] == 2 and p[2] == 4,   "argsort estavel: falses 2,4")
check(p[3] == 1 and p[4] == 3,   "argsort estavel: trues 1,3")

-- sort com null recusa
ok, _ = pcall(function() s:sort(true) end)
check(not ok, "sort com null recusado")

-- ---- astype bidirecional ----
local sb = Series.from_table({true, false, true}, "bool")
-- bool → int64
local si = sb:astype("int64")
check(si._dtype == "int64",      "astype bool->int64 dtype")
check(si:get(1) == 1,            "astype true->1")
check(si:get(2) == 0,            "astype false->0")
-- bool → float64
local sf = sb:astype("float64")
check(sf._dtype == "float64",    "astype bool->float64 dtype")
check(sf:get(1) == 1.0,          "astype true->1.0")
-- bool → string
local ss = sb:astype("string")
check(ss._dtype == "string",     "astype bool->string dtype")
check(ss:get(1) == "true",       "astype true->'true'")
check(ss:get(2) == "false",      "astype false->'false'")
-- int64 → bool (H.6.5.a: rígido, só 0/1 — valor fora disso é erro, não coerção)
local ni = Series.from_table({0, 1, 1, 0}, "int64")
local nb = ni:astype("bool")
check(nb._dtype == "bool",       "astype int64->bool dtype")
check(nb:get(1) == false,        "astype 0->false")
check(nb:get(2) == true,         "astype 1->true")
check(not pcall(function()
    Series.from_table({0, 1, 2, 0}, "int64"):astype("bool")
end), "astype int64->bool: 2 (nao-zero, nao-um) -> erro, nao coercao")
-- string → bool
local st = Series.from_table({"true","false","x"}, "string")
local stb = st:astype("bool")
check(stb:get(1) == true,        "astype 'true'->true")
check(stb:get(2) == false,       "astype 'false'->false")
check(stb:is_null(3),            "astype 'x'->null")
-- float64 → bool (H.6.5.a: 1.0/0.0 valem, fracionário trava)
local ff = Series.from_table({0.0, 1.0, 1.0}, "float64")
local fb = ff:astype("bool")
check(fb:get(1) == false,        "astype 0.0->false")
check(fb:get(2) == true,         "astype 1.0->true")
check(not pcall(function()
    Series.from_table({0.0, 1.5, -1.0}, "float64"):astype("bool")
end), "astype float64->bool: 1.5 (fracionario) -> erro, nao coercao")

-- ---- DataSet com coluna bool ----
local ds = smaug.DataSet({
    {"ativo", {true, NA, false, true}, "bool"},
    {"nome",  {"SP","RJ","MG","RS"},   "string"},
})
check(ds:col("ativo")._dtype == "bool", "DataSet col dtype bool")
check(ds:dtypes().ativo == "bool",      "DataSet dtypes ativo")
check(ds:len() == 4,                    "DataSet len")

-- head/tail preservam dtype
local h = ds:head(2)
check(h:col("ativo")._dtype == "bool",  "head preserva dtype bool")
check(h:col("ativo"):get(1) == true,    "head ativo[1]")

-- DataSet.describe com coluna bool
local dd = ds:describe()
check(dd.ativo ~= nil,                  "describe DataSet tem ativo")
check(dd.ativo.count_true == 2,         "describe ativo count_true")


-- ===================================================================
-- Bloco N — aritmética numérica: promoção e divisão
-- ===================================================================
do
    -- N.1: promoção série × série (int64 ↔ float64 → float64)
    local i = Series.from_table({2, 3, 4}, "int64")
    local f = Series.from_table({1.5, 2.0, 0.5}, "float64")
    check((i * f)._dtype == "float64",        "N.1: int*float -> float64")
    check((f * i)._dtype == "float64",        "N.1: float*int -> float64")
    check((i * f):get(1) == 3.0,              "N.1: int*float valor (2*1.5=3)")
    check((i + f):get(1) == 3.5,              "N.1: int+float valor (2+1.5=3.5)")
    -- mesmo dtype: inalterado
    check((i * Series.from_table({2,2,2},"int64"))._dtype == "int64", "N.1: int*int continua int64")

    -- N.2: promoção série × escalar (corrige corrupção do escalar truncado)
    check((i * 2.5)._dtype == "float64",      "N.2: int*2.5 -> float64")
    check((i * 2.5):get(1) == 5.0,            "N.2: int*2.5 valor (2*2.5=5, não 4)")
    check((i + 1.5):get(1) == 3.5,            "N.2: int+1.5 valor (2+1.5=3.5)")
    check((i * 2)._dtype == "int64",          "N.2: escalar int mantém int64")
    check((i * 2):get(1) == 4,                "N.2: int*2 valor")
    check((2.5 * i):get(1) == 5.0,            "N.2: escalar float à esquerda (2.5*2=5)")

    -- N.3: '/' é divisão verdadeira (sempre float64)
    local a = Series.from_table({7, 8, 9}, "int64")
    local b = Series.from_table({2, 2, 2}, "int64")
    check((a / b)._dtype == "float64",        "N.3: int/int -> float64")
    check((a / b):get(1) == 3.5,              "N.3: 7/2 = 3.5")
    check((a / 2):get(1) == 3.5,              "N.3: int/escalar int -> float (7/2=3.5)")

    -- N.4: :floordiv repõe a divisão inteira (int64, truncada, /0 → null)
    check(a:floordiv(b)._dtype == "int64",    "N.4: floordiv -> int64")
    check(a:floordiv(b):get(1) == 3,          "N.4: 7//2 = 3")
    check(a:floordiv(2):get(1) == 3,          "N.4: floordiv escalar (7//2=3)")
    local z = Series.from_table({10}, "int64"):floordiv(Series.from_table({0}, "int64"))
    check(z:is_null(1),                       "N.4: floordiv por zero -> null")
    -- floordiv exige int: float e escalar fracionário orientam erro
    check(not pcall(function() return f:floordiv(2) end),  "N.4: floordiv em float -> erro")
    check(not pcall(function() return a:floordiv(2.5) end),"N.4: floordiv por fracionário -> erro")

    -- guardas: numérico × não-numérico continua barrando
    check(not pcall(function() return i * Series.from_table({true,false,true},"bool") end),
          "N: int*bool continua barrando")
    check(not pcall(function() return i * Series.from_table({"a","b","c"},"string") end),
          "N: int*string continua barrando")
end


-- =====================================================================
-- Superfície pública do init.lua (smaug.*) — guarda a API exposta
-- =====================================================================
do
    -- forma OFICIAL: smaug.Series chamável (com e sem dtype explícito)
    local sc = smaug.Series({1, 2, 3})
    check(sc and sc:len() == 3,                  "init: smaug.Series({...}) chamável")
    check(sc._dtype == "int64",                  "init: smaug.Series infere int64")
    local scf = smaug.Series({1.5, 2.5}, "float64")
    check(scf._dtype == "float64",               "init: smaug.Series(x, dtype) explícito")

    -- disponível (não-oficial): from_array delega para from_table
    check(type(smaug.from_array) == "function",  "init: smaug.from_array disponível")
    local fa = smaug.from_array({7, 8, 9})
    check(fa and fa:len() == 3,                  "init: from_array constrói")

    -- factories de dtype expostas no top-level (os quatro)
    check(type(smaug.float64) == "function",     "init: smaug.float64 exposto")
    check(type(smaug.int64) == "function",       "init: smaug.int64 exposto")
    check(type(smaug.string) == "function",      "init: smaug.string exposto")
    check(type(smaug.datetime) == "function",    "init: smaug.datetime exposto")

    -- from_table REMOVIDO do top-level (mas vivo como infraestrutura em Series)
    check(smaug.from_table == nil,               "init: smaug.from_table removido do top-level")
    check(type(smaug.Series.from_table) == "function",
                                                 "init: Series.from_table vivo como infraestrutura")
end


print(string.format("OK — %d checks passaram (Series: constructors, f64, i64, bool, aritmética, lifecycle, map)", n_ok))
