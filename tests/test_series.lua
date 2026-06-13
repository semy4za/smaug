-- tests/test_series.lua
-- Smoke test do frontend Lua (classe Series, ambos os dtypes).
-- Rode da raiz do projeto:  luajit tests/test_series.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

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

-- ---- erros de tipo/tamanho ----
local i64s = Series.int64(3)
local ok = pcall(function() return i64s + d end)   -- dtypes diferentes
check(not ok, "erro: + entre dtypes diferentes")

-- ---- int64: sentinela INT64_MIN vira nil ----
local k = Series.from_table({10, Series.NA, 30}, "int64")
check(k:sum() == 40, "i64 sum ignora NA")
check(k:sum(false) == nil, "i64 sum(false) com NA -> nil (INT64_MIN)")
check(k:max() == 30, "i64 max")

-- ---- int64: divisão por zero vira null ----
local num = Series.from_table({10, 20}, "int64")
local den = Series.from_table({2, 0}, "int64")
local q = num / den
check(q:get(1) == 5, "i64 div ok")
check(q:is_null(2), "i64 div por zero -> null")

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

print(string.format("OK — %d checks passaram (Series f64 + i64 + bool)", n_ok))
