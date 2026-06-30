-- tests/dataset/test_core.lua
-- DataSet: factories, CRUD, acesso, seleção, filter, sort_by, dropna, take,
-- head/tail, iloc, sample, assign, nunique, rename, describe, to_table,
-- pivot_table, stack, unstack, explode.
-- Consolida: test_dataset.lua + test_dataset_ops.lua + seção DataSet de test_enrich.lua
-- Rode da raiz: luajit tests/dataset/test_core.lua

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

-- boolean → bool (H.6.1: bool nativo infere "bool", não int64 1/0)
df_bc["ativo"] = true
check(df_bc:col("ativo")._dtype == "bool", "broadcast bool: dtype bool")
check(df_bc:col("ativo"):get(1) == true,   "broadcast bool true → true")
df_bc["inativo"] = false
check(df_bc:col("inativo"):get(2) == false,"broadcast bool false → false")

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
check(sf4:get(1) == true,   "Series.full: bool true → true")
check(sf4._dtype == "bool", "Series.full: bool dtype bool")

-- =====================================================================
-- Series<bool> como coluna de primeira classe no DataSet
-- =====================================================================
local df_bool = smaug.DataSet({
    {"preco",  {10.0, 20.0, 30.0, 40.0}, "float64"},
    {"cidade", {"SP", "RJ", "SP", "MG"}, "string"},
})

-- broadcast de boolean cria coluna bool de fato (H.6.1), não mais int64 (1/0)
df_bool["flag"] = true
check(df_bool:col("flag")._dtype == "bool", "broadcast bool -> bool")
check(df_bool:col("flag"):get(1) == true,   "broadcast bool valor")

-- adicionar coluna Series<bool> explícita via __newindex
local mask_sp = df_bool:col("cidade"):eq("SP")
df_bool["eh_sp"] = mask_sp
check(df_bool:col("eh_sp")._dtype == "bool",  "Series<bool> como coluna")
check(df_bool:col("eh_sp"):get(1) == true,    "bool coluna: pos 1 = true")
check(df_bool:col("eh_sp"):get(2) == false,   "bool coluna: pos 2 = false")

-- head/tail sobre DataSet com coluna bool
local h = df_bool:head(2)
check(h:nrows() == 2,                            "head com bool coluna")
check(h:col("eh_sp")._dtype == "bool",           "head preserva bool coluna")
check(h:col("eh_sp"):get(1) == true,             "head bool valor correto")

local tl = df_bool:tail(2)
check(tl:nrows() == 2,                        "tail com bool coluna")
check(tl:col("eh_sp"):get(1) == true,         "tail bool: pos 1 = SP (true)")
check(tl:col("eh_sp"):get(2) == false,        "tail bool: pos 2 = MG (false)")

-- filter sobre DataSet com coluna bool
local sp_df = df_bool:filter(df_bool:col("cidade"):eq("SP"))
check(sp_df:nrows() == 2,                          "filter com bool coluna")
check(sp_df:col("eh_sp")._dtype == "bool",         "filter preserva bool coluna")

-- to_table sobre DataSet com coluna bool
local tt = df_bool:to_table()
check(type(tt.eh_sp) == "table",   "to_table: bool coluna vira tabela")
check(tt.eh_sp[1] == true,         "to_table: bool valor 1")
check(tt.eh_sp[2] == false,        "to_table: bool valor 2")

-- describe sobre DataSet com coluna bool
local desc = df_bool:describe()
check(type(desc.eh_sp) == "table",         "describe: bool coluna tem entrada")
check(desc.eh_sp.count == 4,               "describe bool: count")
check(desc.eh_sp.count_true == 2,          "describe bool: count_true")
check(desc.eh_sp.count_false == 2,         "describe bool: count_false")

-- sort_by com coluna bool (false < true)
local sorted_b = df_bool:sort_by("eh_sp", true)
check(sorted_b:nrows() == 4,                        "sort_by bool coluna")
check(sorted_b:col("eh_sp"):get(1) == false,        "sort_by bool: falses primeiro")
check(sorted_b:col("eh_sp"):get(3) == true,         "sort_by bool: trues depois")

-- dropna com coluna bool (sem NAs aqui — deve retornar tudo)
local dn = df_bool:dropna()
check(dn:nrows() == 4, "dropna com bool coluna sem NAs")

-- fillna sobre Series<bool> diretamente (sem NAs: fillna é no-op semântico)
local bs_fn = df_bool:col("eh_sp"):fillna(false)
check(bs_fn._dtype == "bool", "fillna DataSet: bool coluna preservada")

-- =====================================================================
-- df[mask]: indexação por Series<bool> (__index dispatch)
-- =====================================================================
-- df[mask] é açúcar para df:filter(mask); testa o dispatch do __index.
local mask_caros = df["preco"]:gt(25)          -- preco > 25 -> linhas 3,4,5
local r_mask = df[mask_caros]
check(r_mask:nrows() == 3,              "df[mask]: nrows correto")
check(r_mask["id"]:get(1) == 3,        "df[mask]: primeira linha correta")
check(r_mask["preco"]:get(3) == 50,    "df[mask]: última linha correta")

-- resultado idêntico ao df:filter(mask) explícito
local r_filter = df:filter(mask_caros)
check(r_mask:nrows() == r_filter:nrows(),            "df[mask] == df:filter: nrows")
check(r_mask["id"]:get(2) == r_filter["id"]:get(2), "df[mask] == df:filter: valores")

-- expressão inline: df[df["col"]:op(val)]
local r_inline = df[df["preco"]:lt(25)]        -- preco < 25 -> linhas 1,2
check(r_inline:nrows() == 2,           "df[mask] inline: nrows")
check(r_inline["id"]:get(1) == 1,     "df[mask] inline: primeira linha")

-- máscara que seleciona zero linhas
local r_empty = df[df["preco"]:gt(999)]
check(r_empty:nrows() == 0,            "df[mask] zero linhas")
check(r_empty:ncols() == df:ncols(),   "df[mask] zero linhas preserva colunas")


-- =====================================================================
-- DataSet ops (de test_dataset_ops.lua)
-- =====================================================================

local ds = smaug.DataSet({
    {"uf",     {"SP","RJ","MG","SP","RJ"}, "string"},
    {"vendas", {10,  20,  30,  40,  50},   "int64"},
    {"custo",  {1.0, 2.0, 3.0, 4.0, 5.0}, "float64"},
})

-- ================================================================
-- assign
-- ================================================================

-- adicionar coluna nova via função
local ds2 = ds:assign("margem", function(d)
    return d:col("vendas"):map(function(v) return v * 2 end, "int64")
end)
check(ds2:has_column("margem"),            "assign: coluna margem adicionada")
check(ds2:col("margem"):get(1) == 20,     "assign: margem[1]=20")
check(ds2:col("margem"):get(5) == 100,    "assign: margem[5]=100")
check(ds2:nrows() == 5,                   "assign: nrows inalterado")
-- original não mutado
check(not ds:has_column("margem"),        "assign: original imutável")

-- adicionar coluna via Series direta
local nova = smaug.Series.from_table({1,2,3,4,5}, "int64")
local ds3 = ds:assign("idx", nova)
check(ds3:has_column("idx"),              "assign Series: coluna adicionada")
check(ds3:col("idx"):get(3) == 3,        "assign Series: valor correto")

-- substituir coluna existente
local ds4 = ds:assign("vendas", function(d)
    return d:col("vendas"):map(function(v) return v + 1000 end, "int64")
end)
check(ds4:col("vendas"):get(1) == 1010,  "assign substituir: valor novo")
check(ds4:ncols() == ds:ncols(),         "assign substituir: ncols inalterado")
-- posição da coluna preservada
check(ds4._col_names[2] == "vendas",     "assign substituir: posição preservada")
-- original não mutado, mesmo SUBSTITUINDO coluna existente (H.6.6.2: contrato
-- de imutabilidade do assign — fácil esquecer de capturar o retorno)
check(ds:col("vendas"):get(1) == 10,     "assign substituir: original preserva valor antigo")

-- erro: tamanho errado
local ok1, _ = pcall(function()
    ds:assign("x", smaug.Series.from_table({1,2}, "int64"))
end)
check(not ok1,                            "assign: erro tamanho errado")

-- erro: não é Series nem função
local ok2, _ = pcall(function() ds:assign("x", 42) end)
check(not ok2,                            "assign: erro tipo inválido")

-- ================================================================
-- nunique
-- ================================================================
local nu = ds:nunique()
check(nu.uf == 3,                         "nunique uf: 3")
check(nu.vendas == 5,                     "nunique vendas: 5")

local ds_na = smaug.DataSet({
    {"k", {1,1,NA,2}, "int64"},
    {"v", {"a","b","a","a"}, "string"},
})
local nu2 = ds_na:nunique()
check(nu2.k == 2,                         "nunique com NA: 2 distintos (NA excluído)")
check(nu2.v == 2,                         "nunique string: 2")

-- ================================================================
-- rolling
-- ================================================================
-- window=3
local r3 = ds:rolling(3):sum("vendas")
check(r3:is_null(1),                      "rolling(3) sum: [1]=NA")
check(r3:is_null(2),                      "rolling(3) sum: [2]=NA")
check(r3:get(3) == 60,                    "rolling(3) sum: [3]=60 (10+20+30)")
check(r3:get(4) == 90,                    "rolling(3) sum: [4]=90 (20+30+40)")
check(r3:get(5) == 120,                   "rolling(3) sum: [5]=120 (30+40+50)")

-- mean
local rm = ds:rolling(2):mean("vendas")
check(rm:is_null(1),                      "rolling(2) mean: [1]=NA")
check(approx(rm:get(2), 15.0),            "rolling(2) mean: [2]=15")
check(approx(rm:get(5), 45.0),            "rolling(2) mean: [5]=45")

-- min/max
local rmin = ds:rolling(2):min("vendas")
check(rmin:get(2) == 10,                  "rolling min: [2]=10")
check(rmin:get(5) == 40,                  "rolling min: [5]=40")

local rmax = ds:rolling(2):max("vendas")
check(rmax:get(2) == 20,                  "rolling max: [2]=20")
check(rmax:get(5) == 50,                  "rolling max: [5]=50")

-- window=1: sem NA
local r1 = ds:rolling(1):sum("vendas")
check(r1:get(1) == 10,                    "rolling(1): sem NA")
check(r1:get(5) == 50,                    "rolling(1): [5]=50")

-- NA dentro da janela: ignorado
local ds_na2 = smaug.DataSet({{"v",{10,NA,30},"int64"}})
local rna = ds_na2:rolling(2):sum("v")
check(rna:is_null(1),                     "rolling com NA: [1]=NA (janela incompleta)")
check(rna:get(2) == 10,                   "rolling com NA: [2]=10 (NA ignorado)")
check(rna:get(3) == 30,                   "rolling com NA: [3]=30 (NA ignorado)")

-- erro: window inválido
local ok3, _ = pcall(function() ds:rolling(0) end)
check(not ok3,                            "rolling: window=0 recusado")
local ok4, _ = pcall(function() ds:rolling(1.5) end)
check(not ok4,                            "rolling: window fracionário recusado")

-- item 8c: DataSet rolling delega à Series (que delega ao C). Ganha
-- std/var/count e min_periods de graça; sem _agg próprio.
local rstd = ds:rolling(3):std("vendas")
check(rstd:is_null(2),                    "8c ds rolling std[2]=NA")
check(approx(rstd:get(3), 10.0),          "8c ds rolling std[3]=10 ({10,20,30})")
local rcnt = ds:rolling(3):count("vendas")
check(rcnt:get(3) == 3,                   "8c ds rolling count[3]=3")
check(rcnt:dtype() == "int64",            "8c ds rolling count→int64")
-- min_periods no DataSet (bug-free, delega ao C corrigido)
local rmp = ds:rolling(3):min_periods(1):sum("vendas")
check(rmp:get(1) == 10,                   "8c ds rolling mp1 sum[1]=10 (parcial)")
check(rmp:get(2) == 30,                   "8c ds rolling mp1 sum[2]=30")
check(rmp:get(3) == 60,                   "8c ds rolling mp1 sum[3]=60")
-- correção de tipo: mean de i64 → float64 (antes truncava)
local dsi = smaug.DataSet({{"v",{10,20,30},"int64"}})
check(dsi:rolling(2):mean("v"):dtype() == "float64", "8c ds rolling mean i64→float64")

-- ================================================================
-- pivot
-- ================================================================
local long = smaug.DataSet({
    {"uf",    {"SP","SP","RJ","RJ","MG"}, "string"},
    {"prod",  {"A", "B", "A", "B", "A"}, "string"},
    {"val",   {10,  20,  30,  40,  50},   "int64"},
})
local wide = long:pivot("uf","prod","val")
check(wide:nrows() == 3,                  "pivot: 3 linhas (3 UFs)")
check(wide:has_column("uf"),              "pivot: coluna uf")
check(wide:has_column("A"),               "pivot: coluna A")
check(wide:has_column("B"),               "pivot: coluna B")
-- valores
local uf_vals = {}
for i=1,3 do uf_vals[wide:col("uf"):get(i)] = i end
check(wide:col("A"):get(uf_vals["SP"]) == 10, "pivot SP-A=10")
check(wide:col("B"):get(uf_vals["SP"]) == 20, "pivot SP-B=20")
check(wide:col("A"):get(uf_vals["RJ"]) == 30, "pivot RJ-A=30")
check(wide:col("A"):get(uf_vals["MG"]) == 50, "pivot MG-A=50")
check(wide:col("B"):is_null(uf_vals["MG"]),   "pivot MG-B=NA")

-- erros
local ok5, _ = pcall(function() long:pivot("xxx","prod","val") end)
check(not ok5,                            "pivot: coluna inexistente")
local ok6, _ = pcall(function() long:pivot("uf","prod",42) end)
check(not ok6,                            "pivot: argumento não-string")

-- ================================================================
-- melt
-- ================================================================
local wide2 = smaug.DataSet({
    {"uf",   {"SP","RJ"},    "string"},
    {"2022", {100, 200},     "int64"},
    {"2023", {150, 250},     "int64"},
})

-- melt básico
local long2 = wide2:melt("uf")
check(long2:nrows() == 4,                 "melt: 4 linhas (2 UFs × 2 anos)")
check(long2:has_column("uf"),             "melt: id_var uf presente")
check(long2:has_column("variable"),       "melt: coluna variable")
check(long2:has_column("value"),          "melt: coluna value")
-- valores: SP/2022=100, RJ/2022=200, SP/2023=150, RJ/2023=250
local rows = {}
for i=1,4 do
    rows[i] = {
        uf=long2:col("uf"):get(i),
        var=long2:col("variable"):get(i),
        val=long2:col("value"):get(i)
    }
end
check(rows[1].uf=="SP" and rows[1].var=="2022" and rows[1].val==100, "melt [1]: SP/2022/100")
check(rows[4].uf=="RJ" and rows[4].var=="2023" and rows[4].val==250, "melt [4]: RJ/2023/250")

-- var_name / value_name customizados
local long3 = wide2:melt("uf", nil, "ano", "vendas")
check(long3:has_column("ano"),            "melt var_name: coluna ano")
check(long3:has_column("vendas"),         "melt value_name: coluna vendas")
check(not long3:has_column("variable"),   "melt: variable renomeado")

-- value_vars específicos
local long4 = wide2:melt("uf", {"2022"})
check(long4:nrows() == 2,                 "melt value_vars: só 2022 → 2 linhas")
check(long4:col("variable"):get(1) == "2022", "melt value_vars: variável = 2022")

-- melt sem id_vars
local long5 = wide2:melt({})
check(long5:nrows() == 6,              "melt sem id: 6 linhas (3 colunas x 2 linhas)")
check(long5:col("variable"):get(1) == "uf", "melt sem id: uf virou variable")

-- erros
local ok7, _ = pcall(function() wide2:melt("xxx") end)
check(not ok7,                            "melt: id_var inexistente")
local ok8, _ = pcall(function() wide2:melt("uf", {"xxx"}) end)
check(not ok8,                            "melt: value_var inexistente")


-- =====================================================================
-- DataSet novos: rename, pivot_table, stack, unstack, explode (de test_enrich.lua)
-- =====================================================================

local ds = smaug.DataSet({
    {"uf",    {"SP","RJ","SP","MG","RJ","SP"}, "string"},
    {"v",     {10.0,20.0,30.0,40.0,50.0,20.0},"float64"},
})
local gb = ds:groupby("uf")

-- ================================================================
-- DataSet novos
-- ================================================================

-- rename
local ds2 = ds:rename({uf="estado", v="valor"})
check(ds2:has_column("estado"),    "rename: estado existe")
check(ds2:has_column("valor"),     "rename: valor existe")
check(not ds2:has_column("uf"),    "rename: uf não existe mais")
check(ds2:nrows() == ds:nrows(),   "rename: nrows preservado")

-- rename em lote preserva ordem
local cols_new = ds2:columns()
check(cols_new[1] == "estado",     "rename: ordem [1]=estado")
check(cols_new[2] == "valor",      "rename: ordem [2]=valor")

-- pivot_table
local ds3 = smaug.DataSet({
    {"ano",  {2023,2023,2024,2024},    "int64"},
    {"mes",  {"jan","fev","jan","fev"},"string"},
    {"val",  {10.0,20.0,30.0,40.0},   "float64"},
})
local pt = ds3:pivot_table("ano","mes","val","sum")
check(pt:nrows() == 2,             "pivot_table: 2 anos")
check(pt:has_column("jan"),        "pivot_table: coluna jan")
check(pt:has_column("fev"),        "pivot_table: coluna fev")
check(pt:has_column("ano"),        "pivot_table: coluna index")
-- 2023 jan=10, 2023 fev=20
local ano2023 = nil
for i=1,pt:nrows() do
    if pt:col("ano"):get(i) == 2023 then ano2023=i; break end
end
check(pt:col("jan"):get(ano2023) == 10.0, "pivot jan 2023=10")
check(pt:col("fev"):get(ano2023) == 20.0, "pivot fev 2023=20")

-- pivot_table aggfunc "mean"
local ptm = ds3:pivot_table("ano","mes","val","mean")
check(ptm:col("jan"):get(ano2023) == 10.0, "pivot mean jan 2023=10")

-- stack
local wide = smaug.DataSet({
    {"id", {1,2},       "int64"},
    {"a",  {10.0,20.0}, "float64"},
    {"b",  {30.0,40.0}, "float64"},
})
local stk = wide:stack({"a","b"})
check(stk:nrows() == 4,            "stack nrows=4")
check(stk:has_column("variable"),  "stack: coluna variable")
check(stk:has_column("value"),     "stack: coluna value")
check(stk:has_column("id"),        "stack: coluna id preservada")
-- ordem: (1,a,10), (1,b,30), (2,a,20), (2,b,40)
local var_col = stk:col("variable"):to_table()
check(var_col[1] == "a" or var_col[1] == "b", "stack: variable[1] é a ou b")

-- unstack (pivot com first)
local us = ds3:unstack("ano","mes","val")
check(us:nrows() == 2,             "unstack nrows=2")
check(us:has_column("jan"),        "unstack: coluna jan")

-- explode com tabelas Lua (uso via assign)
local edst = smaug.DataSet({{"id", {1,2}, "int64"}})
-- simula coluna com listas usando melt/map não é direto,
-- mas explode pode ser testado via coluna string que representa lista
-- Para este teste, validamos que explode funciona com valores escalares
-- (caso degenerado: cada valor já é escalar → linha 1-para-1)
local eds2 = smaug.DataSet({
    {"id",  {10,20,30}, "int64"},
    {"val", {1.0,2.0,3.0}, "float64"},
})
local expl = eds2:explode("val")
check(expl:nrows() == 3,           "explode escalar: nrows=3")
check(expl:col("val"):get(1) == 1.0, "explode escalar: val[1]=1.0")


-- ================================================================
-- 6.5 — DataSet:clone() (par de Series:clone; cópia profunda)
-- ================================================================
do
    local df = smaug.DataSet({{"a", {1, 2}, "int64"}, {"b", {"x", "y"}, "string"}})
    local cp = df:clone()
    check(#cp:to_dict().a == 2 and cp:column("a"):get(1) == 1, "6.5 clone: valores copiados")
    check(table.concat(cp._col_names, ",") == "a,b", "6.5 clone: nomes e ordem preservados")
    -- cópia PROFUNDA: mutar o clone não afeta o original
    cp:column("a"):set(1, 99)
    check(df:column("a"):get(1) == 1, "6.5 clone: profundo (original intacto)")
    check(cp:column("a"):get(1) == 99, "6.5 clone: mutação isolada no clone")
    -- DataSet vazio
    check(smaug.DataSet.new("vazio"):clone():ncols() == 0, "6.5 clone: DataSet vazio")
end


print(string.format("OK — %d checks passaram (DataSet: core, ops, rename, pivot_table, stack, unstack, explode)", n_ok))
