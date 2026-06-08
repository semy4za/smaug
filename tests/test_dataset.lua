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

-- ---- select(): independência (deve clonar, não alias) ----
local df_sel = df:select({"id", "preco"})
check(df_sel:ncols() == 2,                       "select: ncols")
check(df_sel:col("id"):get(1) == 1,              "select: valor ok")
-- mutation no derivado NÃO afeta o original
df_sel:col("preco"):set(1, 999.0)
check(df:col("preco"):get(1) == 10.0,            "select: independente — original intacto")
check(df_sel:col("preco"):get(1) == 999.0,       "select: derivado tem o valor novo")

-- ---- dropna(): remove linhas com NULL ----
local df_nulls = smaug.dataset({
    {"x", Series.from_table({1, 2, 3, 4, 5}, "float64")},
    {"y", Series.from_table({10, 20, 30, 40, 50}, "float64")},
}, "nulltest")
df_nulls:col("x"):set_null(2)           -- linha 2 tem null em x
df_nulls:col("y"):set_null(4)           -- linha 4 tem null em y
df_nulls:col("x"):set_null(5)           -- linha 5 tem null em x e y
df_nulls:col("y"):set_null(5)

local clean = df_nulls:dropna()
check(clean:nrows() == 2,                "dropna: remove linhas com null (sobram 2)")
check(clean:col("x"):get(1) == 1.0,     "dropna: linha 1 preservada")
check(clean:col("x"):get(2) == 3.0,     "dropna: linha 3 preservada como linha 2")

-- dropna com subset: só verifica coluna x
local clean_x = df_nulls:dropna({"x"})
check(clean_x:nrows() == 3,             "dropna(subset): ignora null em y (3 linhas)")

-- dropna em dataset limpo: retorna tudo
local all = df:dropna()
check(all:nrows() == df:nrows(),        "dropna sem nulls: nrows igual")

-- dropna em dataset todo-null: retorna vazio
local df_all_null = smaug.dataset({
    {"z", Series.from_table({1, 2}, "float64")},
}, "allnull")
df_all_null:col("z"):set_null(1)
df_all_null:col("z"):set_null(2)
local empty = df_all_null:dropna()
check(empty:nrows() == 0,               "dropna todo-null: dataset vazio")

-- dropna no sort_by (resolve a promessa do erro 'use dropna primeiro')
local df_sort = smaug.dataset({
    {"val",   Series.from_table({3, 1, 2}, "float64")},
    {"label", Series.from_table({1, 2, 3}, "int64")},
}, "sorttest")
df_sort:col("val"):set_null(2)         -- null na linha 2
local df_clean = df_sort:dropna()
local df_sorted = df_clean:sort_by("val")
check(df_sorted:col("val"):get(1) == 2.0, "dropna + sort_by: primeiro = 2.0")
check(df_sorted:col("val"):get(2) == 3.0, "dropna + sort_by: segundo = 3.0")

print(string.format("OK — %d checks passaram (DataSet)", n_ok))
