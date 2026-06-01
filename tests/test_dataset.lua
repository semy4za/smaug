-- tests/test_dataset.lua
-- Testes da classe DataSet (Fase 3). Rode da raiz do projeto:
--   luajit tests/test_dataset.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug   = require("smaug")
local Series  = smaug.Series

local function approx(a, b) return math.abs(a - b) < 1e-9 end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- ---- construção e dimensões ----
local df = smaug.dataset({
    {"id",    {1, 2, 3, 4, 5}, "int64"},
    {"preco", {10, 20, 30, 40, 50}, "float64"},
    {"qtd",   {1, 0, 5, 2, 0}, "int64"},
}, "pedidos")
check(df:nrows() == 5, "nrows")
check(df:ncols() == 3, "ncols")
check(df:nrows() == 5, "nrows (método; # não funciona em tabelas no LuaJIT 5.1)")
local cols = df:columns()
check(cols[1] == "id" and cols[3] == "qtd", "ordem das colunas")

-- ---- acesso por coluna ----
check(df["preco"]:sum() == 150, "df[col] e sum")
check(df:column("id"):get(2) == 2, "column()")
check(df:has_column("qtd") and not df:has_column("zzz"), "has_column")
local dt = df:dtypes()
check(dt.id == "int64" and dt.preco == "float64", "dtypes")

-- ---- add_column: validação de comprimento e duplicidade ----
local ok_len = pcall(function()
    df:add_column("ruim", Series.from_table({1, 2}, "int64"))
end)
check(not ok_len, "add_column rejeita comprimento diferente")
local ok_dup = pcall(function()
    df:add_column("id", Series.from_table({1,2,3,4,5}, "int64"))
end)
check(not ok_dup, "add_column rejeita nome duplicado")

-- ---- row ----
local r = df:row(3)
check(r.id == 3 and r.preco == 30 and r.qtd == 5, "row")

-- ---- filter (mantém alinhamento entre colunas) ----
local caros = df:filter(df["preco"]:gt(25))      -- preco > 25 -> linhas 3,4,5
check(caros:nrows() == 3, "filter nrows")
check(caros["id"]:get(1) == 3 and caros["preco"]:get(1) == 30, "filter alinhamento")

-- ---- sort_by: reordena TODAS as colunas pela permutação da chave ----
local s_desc = df:sort_by("preco", false)
check(s_desc["preco"]:get(1) == 50 and s_desc["id"]:get(1) == 5, "sort_by desc")
local s_asc = df:sort_by("qtd", true)
check(s_asc["qtd"]:get(1) == 0, "sort_by asc")
-- sort_by com nulos na chave -> erro
local dfn = smaug.dataset({{"k", {1, smaug.NA, 3}, "int64"}, {"v", {7,8,9}, "int64"}})
local ok_sortnull = pcall(function() return dfn:sort_by("k") end)
check(not ok_sortnull, "sort_by rejeita nulos na chave")

-- ---- head / tail / iloc / take ----
check(df:head(2):nrows() == 2 and df:head(2)["id"]:get(2) == 2, "head")
check(df:tail(2)["id"]:get(1) == 4, "tail")
local sl = df:iloc(2, 4)
check(sl:nrows() == 3 and sl["id"]:get(1) == 2 and sl["id"]:get(3) == 4, "iloc")
local tk = df:take({5, 1})
check(tk:nrows() == 2 and tk["id"]:get(1) == 5 and tk["id"]:get(2) == 1, "take")

-- ---- select / drop / rename ----
local sel = df:select({"qtd", "id"})
check(sel:ncols() == 2 and sel:columns()[1] == "qtd", "select (subset + ordem)")
-- drop não afeta o original (select compartilha Series, mas estrutura é própria)
sel:drop_column("qtd")
check(sel:ncols() == 1 and df:ncols() == 3, "drop_column não afeta o original")
local rn = smaug.dataset({{"a", {1,2}}, {"b", {3,4}}})
rn:rename_column("a", "x")
check(rn:has_column("x") and not rn:has_column("a"), "rename_column")

-- ---- sample (determinístico com seed) ----
local sm = df:sample(3, 42)
check(sm:nrows() == 3, "sample nrows")

-- ---- describe ----
local desc = df:describe()
check(desc.preco.count == 5 and approx(desc.preco.mean, 30), "describe por coluna")
check(approx(desc.preco["50%"], 30), "describe mediana")

-- ---- to_table ----
local tt = df:to_table()
check(#tt.id == 5 and tt.preco[1] == 10, "to_table")

-- ---- imutabilidade: derivados não afetam o original ----
local before = df["preco"]:sum()
local _ = df:filter(df["preco"]:gt(0)):sort_by("preco")
check(df["preco"]:sum() == before, "operações derivadas não mutam o original")

-- ---- tostring ----
check(type(tostring(df)) == "string", "__tostring")
check(tostring(smaug.DataSet.new("vazio")):find("vazio") ~= nil, "tostring vazio")

print(string.format("OK — %d checks passaram (DataSet)", n_ok))
