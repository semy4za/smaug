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

-- =====================================================================
-- FASE 8 (b) — endurecimento dos contratos de select()/dropna()
-- Apenas testes. Nenhuma feature, nenhuma mudança de semântica.
-- =====================================================================

-- ---- select(): lista vazia -> DataSet vazio (0 col, 0 linha) ----
local sel_empty = df:select({})
check(sel_empty:ncols() == 0, "select({}) -> 0 colunas")
check(sel_empty:nrows() == 0, "select({}) -> 0 linhas")

-- ---- select(): argumento não-tabela -> erro ----
check(not pcall(function() return df:select("id") end),
      "select(string) rejeitado (espera tabela)")

-- ---- select(): nome inexistente -> erro ----
check(not pcall(function() return df:select({"zzz"}) end),
      "select com coluna inexistente rejeitado")

-- ---- select(): nome duplicado -> erro (sem dedupe; add_column recusa) ----
check(not pcall(function() return df:select({"id", "id"}) end),
      "select com nome duplicado rejeitado")

-- ---- select(): independência também no sentido original -> derivado ----
local base_sel = smaug.dataset({
    {"a", Series.from_table({1, 2, 3}, "float64")},
    {"b", Series.from_table({4, 5, 6}, "float64")},
}, "sel_indep")
local proj = base_sel:select({"a"})
base_sel:col("a"):set(1, 111.0)                 -- muta o ORIGINAL
check(proj:col("a"):get(1) == 1.0, "select: mutar original não afeta o derivado")

-- ---- dropna(): subset vazio -> mantém todas as linhas ----
local dn_base = smaug.dataset({
    {"x", Series.from_table({1, 2, 3}, "float64")},
}, "dn_empty_subset")
dn_base:col("x"):set_null(2)
local kept = dn_base:dropna({})
check(kept:nrows() == 3, "dropna({}) mantém todas as linhas (subset vazio)")

-- ---- dropna(): argumento não-tabela e não-nil -> erro ----
check(not pcall(function() return dn_base:dropna("x") end),
      "dropna(string) rejeitado (espera nil ou lista)")

-- ---- dropna(): subset com coluna inexistente -> erro ----
check(not pcall(function() return dn_base:dropna({"zzz"}) end),
      "dropna com coluna de subset inexistente rejeitado")

-- ---- dropna(): resultado independente do original ----
local dn_indep = smaug.dataset({
    {"v", Series.from_table({10, 20, 30}, "float64")},
}, "dn_indep")
dn_indep:col("v"):set_null(2)                   -- linha 2 vira null
local dn_clean = dn_indep:dropna()              -- sobram linhas 1 e 3
check(dn_clean:nrows() == 2, "dropna independência: sobram 2 linhas")
dn_clean:col("v"):set(1, 999.0)                 -- muta o derivado
check(dn_indep:col("v"):get(1) == 10.0, "dropna: derivado independente do original")

-- ---- dropna(): resultado independente do original ----
local dn_indep = smaug.dataset({
    {"v", Series.from_table({10, 20, 30}, "float64")},
}, "dn_indep")
dn_indep:col("v"):set_null(2)                   -- linha 2 vira null
local dn_clean = dn_indep:dropna()              -- sobram linhas 1 e 3
check(dn_clean:nrows() == 2, "dropna independência: sobram 2 linhas")
dn_clean:col("v"):set(1, 999.0)                 -- muta o derivado
check(dn_indep:col("v"):get(1) == 10.0, "dropna: derivado independente do original")

-- =====================================================================
-- API pública: smaug.DataSet({...}) com inferência de dtype
-- =====================================================================
local df_pub = smaug.DataSet({
    {"venda", {10, 20, 30}},
    {"custo", {3,  7,  2}},
})
check(df_pub:ncols() == 2,              "smaug.DataSet: 2 colunas")
check(df_pub:nrows() == 3,              "smaug.DataSet: 3 linhas")
check(df_pub:col("venda"):get(1) == 10, "smaug.DataSet: valor coluna")
check(df_pub:col("venda")._dtype == "int64",   "smaug.DataSet: dtype inferido int64")
check(df_pub:col("custo")._dtype == "int64",   "smaug.DataSet: dtype inferido int64 2")

-- fracionário → float64
local df_frac = smaug.DataSet({{"preco", {1.5, 2.0, 3.7}}})
check(df_frac:col("preco")._dtype == "float64", "smaug.DataSet: dtype inferido float64")

-- string → string
local df_str = smaug.DataSet({{"uf", {"SP","RJ","MG"}}})
check(df_str:col("uf")._dtype == "string", "smaug.DataSet: dtype inferido string")

-- dtype explícito sobrepõe inferência
local df_exp = smaug.DataSet({{"val", {1, 2, 3}, "float64"}})
check(df_exp:col("val")._dtype == "float64", "smaug.DataSet: dtype explícito respeitado")

-- =====================================================================
-- df["col"] = series via __newindex (add + update)
-- =====================================================================
local df_ni = smaug.DataSet({
    {"venda", {10.0, 20.0, 30.0}, "float64"},
    {"custo", {3.0,  7.0,  2.0},  "float64"},
})

-- criar coluna derivada
df_ni["lucro"] = df_ni["venda"] - df_ni["custo"]
check(df_ni:has_column("lucro"),               "newindex: coluna criada")
check(df_ni:col("lucro"):get(1) == 7.0,        "newindex: valor correto (10-3)")
check(df_ni:col("lucro"):get(2) == 13.0,       "newindex: valor correto (20-7)")

-- atualizar coluna existente
df_ni["venda"] = df_ni["venda"] * 1.1
check(math.abs(df_ni:col("venda"):get(1) - 11.0) < 1e-9, "newindex: update in-place")

-- encadeamento
df_ni["margem"] = df_ni["lucro"] / df_ni["venda"]
check(df_ni:has_column("margem"),              "newindex: encadeamento ok")

-- tamanho diferente deve falhar
check(not pcall(function()
    df_ni["ruim"] = Series.from_table({1, 2}, "int64")
end), "newindex: rejeita série com tamanho diferente")

-- =====================================================================
-- Broadcast de escalares via __newindex
-- =====================================================================
local df_bc = smaug.DataSet({{"val", {1.0, 2.0, 3.0}, "float64"}})

-- string
df_bc["pais"] = "BR"
check(df_bc:has_column("pais"),          "broadcast string: coluna criada")
check(df_bc:col("pais"):get(1) == "BR",  "broadcast string: valor")
check(df_bc:col("pais"):get(3) == "BR",  "broadcast string: todas as linhas")

-- inteiro → int64
df_bc["ano"] = 2024
check(df_bc:col("ano"):get(1) == 2024,   "broadcast int: valor")
check(df_bc:col("ano")._dtype == "int64","broadcast int: dtype int64")

-- fracionário → float64
df_bc["taxa"] = 0.15
check(df_bc:col("taxa"):get(1) == 0.15,     "broadcast float: valor")
check(df_bc:col("taxa")._dtype == "float64","broadcast float: dtype float64")

-- boolean → int64 (1/0)
df_bc["ativo"] = true
check(df_bc:col("ativo"):get(1) == 1,    "broadcast bool true → 1")
df_bc["inativo"] = false
check(df_bc:col("inativo"):get(2) == 0,  "broadcast bool false → 0")

-- DataSet vazio rejeita broadcast
check(not pcall(function()
    local empty = smaug.DataSet.new("vazio")
    empty["x"] = "BR"
end), "broadcast em DataSet vazio: erro")

-- =====================================================================
-- Series.full
-- =====================================================================
local sf = Series.full(4, "ok", nil, "t")
check(sf:len() == 4,          "Series.full: tamanho")
check(sf:get(1) == "ok",      "Series.full: valor")
check(sf:get(4) == "ok",      "Series.full: último valor")
check(sf._dtype == "string",  "Series.full: dtype string")

local sf2 = Series.full(3, 42)
check(sf2._dtype == "int64",  "Series.full: dtype inferido int64")
check(sf2:get(2) == 42,       "Series.full: valor int")

local sf3 = Series.full(2, 1.5)
check(sf3._dtype == "float64","Series.full: dtype inferido float64")

local sf4 = Series.full(3, true)
check(sf4:get(1) == 1,        "Series.full: bool true → 1")
check(sf4._dtype == "int64",  "Series.full: bool dtype int64")

print(string.format("OK — %d checks passaram (DataSet)", n_ok))
