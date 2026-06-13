-- tests/test_bool_dtype.lua
-- Teste do dtype `bool` de primeira classe no frontend Lua (Fase 2).
-- Cobre: from_table, Series.new, set/get, append, fillna, dropna, describe,
-- sort/argsort, astype bidirecional, check_value, DataSet com coluna bool.
-- Rode da raiz:  luajit tests/test_bool_dtype.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

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
-- int64 → bool
local ni = Series.from_table({0, 1, 2, 0}, "int64")
local nb = ni:astype("bool")
check(nb._dtype == "bool",       "astype int64->bool dtype")
check(nb:get(1) == false,        "astype 0->false")
check(nb:get(2) == true,         "astype 1->true")
check(nb:get(3) == true,         "astype 2->true (nao-zero)")
-- string → bool
local st = Series.from_table({"true","false","x"}, "string")
local stb = st:astype("bool")
check(stb:get(1) == true,        "astype 'true'->true")
check(stb:get(2) == false,       "astype 'false'->false")
check(stb:is_null(3),            "astype 'x'->null")
-- float64 → bool
local ff = Series.from_table({0.0, 1.5, -1.0}, "float64")
local fb = ff:astype("bool")
check(fb:get(1) == false,        "astype 0.0->false")
check(fb:get(2) == true,         "astype 1.5->true")

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

print(string.format("OK — %d checks passaram (bool dtype frontend)", n_ok))
