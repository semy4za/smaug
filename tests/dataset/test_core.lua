-- tests/dataset/test_core.lua
-- DataSet: factories, CRUD, acesso, seleção, filter, sort_by, dropna, take,
-- head/tail, iloc, sample, assign, nunique, rename, describe, to_table,
-- pivot_table, stack, unstack, explode.
-- Consolida: test_dataset.lua + test_dataset_ops.lua + seção DataSet de test_enrich.lua
-- Rode da raiz: luajit tests/dataset/test_core.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local function approximately_equal(left_value, right_value) return math.abs(left_value - right_value) < 1e-9 end
local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local source_dataset = smaug.DataSet({
    {"id",    {1, 2, 3, 4, 5}, "int64"},
    {"preco", {10, 20, 30, 40, 50}, "float64"},
    {"qtd",   {1, 0, 5, 2, 0}, "int64"},
}, "pedidos")
check(source_dataset:nrows() == 5, "nrows")
check(source_dataset:ncols() == 3, "ncols")
check(source_dataset:nrows() == 5, "nrows (método; # não funciona em tabelas no LuaJIT 5.1)")
local column_names = source_dataset:columns()
check(column_names[1] == "id" and column_names[3] == "qtd", "ordem das colunas")

-- ---- acesso por coluna ----
check(source_dataset["preco"]:sum() == 150, "df[col] e sum")
check(source_dataset:column("id"):get(2) == 2, "column()")
check(source_dataset:has_column("qtd") and not source_dataset:has_column("zzz"), "has_column")
local column_types = source_dataset:dtypes()
check(column_types.id == "int64" and column_types.preco == "float64", "dtypes")

-- ---- add_column: validação de comprimento e duplicidade ----
local succeeded = pcall(function()
    source_dataset:add_column("ruim", smaug.Series({1, 2}, "int64"))
end)
check(not succeeded, "add_column rejeita comprimento diferente")
local succeeded_2 = pcall(function()
    source_dataset:add_column("id", smaug.Series({1,2,3,4,5}, "int64"))
end)
check(not succeeded_2, "add_column rejeita nome duplicado")

-- ---- row ----
local row_values = source_dataset:row(3)
check(row_values.id == 3 and row_values.preco == 30 and row_values.qtd == 5, "row")

-- ---- filter (mantém alinhamento entre colunas) ----
local expensive_orders = source_dataset:filter(source_dataset["preco"]:gt(25))      -- preco > 25 -> linhas 3,4,5
check(expensive_orders:nrows() == 3, "filter nrows")
check(expensive_orders["id"]:get(1) == 3 and expensive_orders["preco"]:get(1) == 30, "filter alinhamento")

-- ---- sort_by: reordena TODAS as colunas pela permutação da chave ----
local descending_dataset = source_dataset:sort_by("preco", false)
check(descending_dataset["preco"]:get(1) == 50 and descending_dataset["id"]:get(1) == 5, "sort_by desc")
local ascending_dataset = source_dataset:sort_by("qtd", true)
check(ascending_dataset["qtd"]:get(1) == 0, "sort_by asc")
-- sort_by com nulos na chave -> erro
local source_dataset_2 = smaug.DataSet({{"k", {1, smaug.NA, 3}, "int64"}, {"v", {7,8,9}, "int64"}})
local succeeded_3 = pcall(function() return source_dataset_2:sort_by("k") end)
check(not succeeded_3, "sort_by rejeita nulos na chave")

-- ---- head / tail / iloc / take ----
check(source_dataset:head(2):nrows() == 2 and source_dataset:head(2)["id"]:get(2) == 2, "head")
check(source_dataset:tail(2)["id"]:get(1) == 4, "tail")
local dataset_slice = source_dataset:iloc(2, 4)
check(dataset_slice:nrows() == 3 and dataset_slice["id"]:get(1) == 2 and dataset_slice["id"]:get(3) == 4, "iloc")
local selected_result = source_dataset:take({5, 1})
check(selected_result:nrows() == 2 and selected_result["id"]:get(1) == 5 and selected_result["id"]:get(2) == 1, "take")

-- ---- select / drop / rename ----
local selected_dataset = source_dataset:select({"qtd", "id"})
check(selected_dataset:ncols() == 2 and selected_dataset:columns()[1] == "qtd", "select (subset + ordem)")
-- drop não afeta o original (select compartilha Series, mas estrutura é própria)
selected_dataset:drop_column("qtd")
check(selected_dataset:ncols() == 1 and source_dataset:ncols() == 3, "drop_column não afeta o original")
local source_dataset_3 = smaug.DataSet({{"a", {1,2}}, {"b", {3,4}}})
source_dataset_3:rename_column("a", "x")
check(source_dataset_3:has_column("x") and not source_dataset_3:has_column("a"), "rename_column")

-- ---- sample (determinístico com seed) ----
local sampled_dataset = source_dataset:sample(3, 42)
check(sampled_dataset:nrows() == 3, "sample nrows")

-- ---- describe ----
local description = source_dataset:describe()
check(description.preco.count == 5 and approximately_equal(description.preco.mean, 30), "describe por coluna")
check(approximately_equal(description.preco["50%"], 30), "describe mediana")

-- ---- to_table ----
local table_values = source_dataset:to_table()
check(#table_values.id == 5 and table_values.preco[1] == 10, "to_table")

-- ---- imutabilidade: derivados não afetam o original ----
local before = source_dataset["preco"]:sum()
local sorted_dataset = source_dataset:filter(source_dataset["preco"]:gt(0)):sort_by("preco")
check(source_dataset["preco"]:sum() == before, "operações derivadas não mutam o original")

-- ---- tostring ----
check(type(tostring(source_dataset)) == "string", "__tostring")
check(tostring(smaug.DataSet.new("vazio")):find("vazio") ~= nil, "tostring vazio")

-- ---- select(): independência (deve clonar, não alias) ----
local selected_dataset_2 = source_dataset:select({"id", "preco"})
check(selected_dataset_2:ncols() == 2,                       "select: ncols")
check(selected_dataset_2:col("id"):get(1) == 1,              "select: valor ok")
-- 9.2: col() retorna view COW protegida — set numa coluna extraída NÃO
-- propaga para o frame (nem no derivado, nem no original). E2 morto.
selected_dataset_2:col("preco"):set(1, 999.0)
check(source_dataset:col("preco"):get(1) == 10.0,            "select: original intacto (col protege)")
check(selected_dataset_2:col("preco"):get(1) == 10.0,        "select: frame derivado também protegido (E2 morto)")
-- mutação intencional de coluna é via update_column (caminho explícito)
selected_dataset_2:update_column("preco", smaug.Series({999.0, 20, 30, 40, 50}, "float64"))
check(selected_dataset_2:col("preco"):get(1) == 999.0,       "update_column: mutação intencional funciona")
check(source_dataset:col("preco"):get(1) == 10.0,            "update_column: original permanece intacto")

-- ---- dropna(): remove linhas com NULL ----
-- (dados nascem com os nulos no lugar — não dependem de mutação pós-criação)
local source_dataset_4 = smaug.DataSet({
    {"x", smaug.Series({1, smaug.NA, 3, 4, smaug.NA}, "float64")},   -- null nas linhas 2 e 5
    {"y", smaug.Series({10, 20, 30, smaug.NA, smaug.NA}, "float64")}, -- null nas linhas 4 e 5
}, "nulltest")

local clean = source_dataset_4:dropna()
check(clean:nrows() == 2,                "dropna: remove linhas com null (sobram 2)")
check(clean:col("x"):get(1) == 1.0,     "dropna: linha 1 preservada")
check(clean:col("x"):get(2) == 3.0,     "dropna: linha 3 preservada como linha 2")

-- dropna com subset: só verifica coluna x
local clean_value_series = source_dataset_4:dropna({"x"})
check(clean_value_series:nrows() == 3,             "dropna(subset): ignora null em y (3 linhas)")

-- dropna em dataset limpo: retorna tudo
local non_null_result = source_dataset:dropna()
check(non_null_result:nrows() == source_dataset:nrows(),        "dropna sem nulls: nrows igual")

-- dropna em dataset todo-null: retorna vazio
local source_dataset_5 = smaug.DataSet({
    {"z", smaug.Series({smaug.NA, smaug.NA}, "float64")},
}, "allnull")
local empty = source_dataset_5:dropna()
check(empty:nrows() == 0,               "dropna todo-null: dataset vazio")

-- dropna no sort_by (resolve a promessa do erro 'use dropna primeiro')
local source_dataset_6 = smaug.DataSet({
    {"val",   smaug.Series({3, smaug.NA, 2}, "float64")},   -- null na linha 2
    {"label", smaug.Series({1, 2, 3}, "int64")},
}, "sorttest")
local non_null_result_2 = source_dataset_6:dropna()
local sorted_dataset_2 = non_null_result_2:sort_by("val")
check(sorted_dataset_2:col("val"):get(1) == 2.0, "dropna + sort_by: primeiro = 2.0")
check(sorted_dataset_2:col("val"):get(2) == 3.0, "dropna + sort_by: segundo = 3.0")

-- =====================================================================
-- FASE 8 (b) — endurecimento dos contratos de select()/dropna()
-- Apenas testes. Nenhuma feature, nenhuma mudança de semântica.
-- =====================================================================

-- ---- select(): lista vazia -> DataSet vazio (0 col, 0 linha) ----
local sel_empty = source_dataset:select({})
check(sel_empty:ncols() == 0, "select({}) -> 0 colunas")
check(sel_empty:nrows() == 0, "select({}) -> 0 linhas")

-- ---- select(): argumento não-tabela -> erro ----
check(not pcall(function() return source_dataset:select("id") end),
      "select(string) rejeitado (espera tabela)")

-- ---- select(): nome inexistente -> erro ----
check(not pcall(function() return source_dataset:select({"zzz"}) end),
      "select com coluna inexistente rejeitado")

-- ---- select(): nome duplicado -> erro (sem dedupe; add_column recusa) ----
check(not pcall(function() return source_dataset:select({"id", "id"}) end),
      "select com nome duplicado rejeitado")

-- ---- select(): independência também no sentido original -> derivado ----
local base_sel = smaug.DataSet({
    {"a", smaug.Series({1, 2, 3}, "float64")},
    {"b", smaug.Series({4, 5, 6}, "float64")},
}, "sel_indep")
local selected_dataset_3 = base_sel:select({"a"})
-- muta o ORIGINAL de forma intencional (update_column); derivado não acompanha
base_sel:update_column("a", smaug.Series({111.0, 2, 3}, "float64"))
check(selected_dataset_3:col("a"):get(1) == 1.0, "select: mutar original não afeta o derivado")

-- ---- dropna(): subset vazio -> mantém todas as linhas ----
local dn_base = smaug.DataSet({
    {"x", smaug.Series({1, smaug.NA, 3}, "float64")},   -- null na linha 2 desde a criação
}, "dn_empty_subset")
local non_null_result_3 = dn_base:dropna({})
check(non_null_result_3:nrows() == 3, "dropna({}) mantém todas as linhas (subset vazio)")

-- ---- dropna(): argumento não-tabela e não-nil -> erro ----
check(not pcall(function() return dn_base:dropna("x") end),
      "dropna(string) rejeitado (espera nil ou lista)")

-- ---- dropna(): subset com coluna inexistente -> erro ----
check(not pcall(function() return dn_base:dropna({"zzz"}) end),
      "dropna com coluna de subset inexistente rejeitado")

-- ---- dropna(): resultado independente do original ----
local dn_indep = smaug.DataSet({
    {"v", smaug.Series({10, smaug.NA, 30}, "float64")},   -- null na linha 2 desde a criação
}, "dn_indep")
local dn_clean = dn_indep:dropna()              -- sobram linhas 1 e 3
check(dn_clean:nrows() == 2, "dropna independência: sobram 2 linhas")
-- mutar o derivado (via update_column) não toca o original
dn_clean:update_column("v", smaug.Series({999.0, 30}, "float64"))
check(dn_indep:col("v"):get(1) == 10.0, "dropna: derivado independente do original")

-- =====================================================================
-- API pública: smaug.DataSet({...}) com inferência de dtype
-- =====================================================================
local source_dataset_7 = smaug.DataSet({
    {"venda", {10, 20, 30}},
    {"custo", {3,  7,  2}},
})
check(source_dataset_7:ncols() == 2,              "smaug.DataSet: 2 colunas")
check(source_dataset_7:nrows() == 3,              "smaug.DataSet: 3 linhas")
check(source_dataset_7:col("venda"):get(1) == 10, "smaug.DataSet: valor coluna")
check(source_dataset_7:col("venda")._dtype == "int64",   "smaug.DataSet: dtype inferido int64")
check(source_dataset_7:col("custo")._dtype == "int64",   "smaug.DataSet: dtype inferido int64 2")

-- fracionário → float64
local source_dataset_8 = smaug.DataSet({{"preco", {1.5, 2.0, 3.7}}})
check(source_dataset_8:col("preco")._dtype == "float64", "smaug.DataSet: dtype inferido float64")

-- string → string
local source_dataset_9 = smaug.DataSet({{"uf", {"SP","RJ","MG"}}})
check(source_dataset_9:col("uf")._dtype == "string", "smaug.DataSet: dtype inferido string")

-- dtype explícito sobrepõe inferência
local source_dataset_10 = smaug.DataSet({{"val", {1, 2, 3}, "float64"}})
check(source_dataset_10:col("val")._dtype == "float64", "smaug.DataSet: dtype explícito respeitado")

-- =====================================================================
-- df["col"] = series via __newindex (add + update)
-- =====================================================================
local source_dataset_11 = smaug.DataSet({
    {"venda", {10.0, 20.0, 30.0}, "float64"},
    {"custo", {3.0,  7.0,  2.0},  "float64"},
})

-- criar coluna derivada
source_dataset_11["lucro"] = source_dataset_11["venda"] - source_dataset_11["custo"]
check(source_dataset_11:has_column("lucro"),               "newindex: coluna criada")
check(source_dataset_11:col("lucro"):get(1) == 7.0,        "newindex: valor correto (10-3)")
check(source_dataset_11:col("lucro"):get(2) == 13.0,       "newindex: valor correto (20-7)")

-- atualizar coluna existente
source_dataset_11["venda"] = source_dataset_11["venda"] * 1.1
check(math.abs(source_dataset_11:col("venda"):get(1) - 11.0) < 1e-9, "newindex: update in-place")

-- encadeamento
source_dataset_11["margem"] = source_dataset_11["lucro"] / source_dataset_11["venda"]
check(source_dataset_11:has_column("margem"),              "newindex: encadeamento ok")

-- tamanho diferente deve falhar
check(not pcall(function()
    source_dataset_11["ruim"] = smaug.Series({1, 2}, "int64")
end), "newindex: rejeita série com tamanho diferente")

-- =====================================================================
-- Broadcast de escalares via __newindex
-- =====================================================================
local source_dataset_12 = smaug.DataSet({{"val", {1.0, 2.0, 3.0}, "float64"}})

-- string
source_dataset_12["pais"] = "BR"
check(source_dataset_12:has_column("pais"),          "broadcast string: coluna criada")
check(source_dataset_12:col("pais"):get(1) == "BR",  "broadcast string: valor")
check(source_dataset_12:col("pais"):get(3) == "BR",  "broadcast string: todas as linhas")

-- inteiro → int64
source_dataset_12["ano"] = 2024
check(source_dataset_12:col("ano"):get(1) == 2024,   "broadcast int: valor")
check(source_dataset_12:col("ano")._dtype == "int64","broadcast int: dtype int64")

-- fracionário → float64
source_dataset_12["taxa"] = 0.15
check(source_dataset_12:col("taxa"):get(1) == 0.15,     "broadcast float: valor")
check(source_dataset_12:col("taxa")._dtype == "float64","broadcast float: dtype float64")

-- boolean → bool (H.6.1: bool nativo infere "bool", não int64 1/0)
source_dataset_12["ativo"] = true
check(source_dataset_12:col("ativo")._dtype == "bool", "broadcast bool: dtype bool")
check(source_dataset_12:col("ativo"):get(1) == true,   "broadcast bool true → true")
source_dataset_12["inativo"] = false
check(source_dataset_12:col("inativo"):get(2) == false,"broadcast bool false → false")

-- DataSet vazio rejeita broadcast
check(not pcall(function()
    local empty_2 = smaug.DataSet.new("vazio")
    empty_2["x"] = "BR"
end), "broadcast em DataSet vazio: erro")

-- =====================================================================
-- Series.full
-- =====================================================================
local full_result = smaug.Series.full(4, "ok", nil, "t")
check(full_result:len() == 4,          "Series.full: tamanho")
check(full_result:get(1) == "ok",      "Series.full: valor")
check(full_result:get(4) == "ok",      "Series.full: último valor")
check(full_result._dtype == "string",  "Series.full: dtype string")

local full_result_2 = smaug.Series.full(3, 42)
check(full_result_2._dtype == "int64",  "Series.full: dtype inferido int64")
check(full_result_2:get(2) == 42,       "Series.full: valor int")

local full_result_3 = smaug.Series.full(2, 1.5)
check(full_result_3._dtype == "float64","Series.full: dtype inferido float64")

local full_result_4 = smaug.Series.full(3, true)
check(full_result_4:get(1) == true,   "Series.full: bool true → true")
check(full_result_4._dtype == "bool", "Series.full: bool dtype bool")

-- =====================================================================
-- Series<bool> como coluna de primeira classe no DataSet
-- =====================================================================
local source_dataset_13 = smaug.DataSet({
    {"preco",  {10.0, 20.0, 30.0, 40.0}, "float64"},
    {"cidade", {"SP", "RJ", "SP", "MG"}, "string"},
})

-- broadcast de boolean cria coluna bool de fato (H.6.1), não mais int64 (1/0)
source_dataset_13["flag"] = true
check(source_dataset_13:col("flag")._dtype == "bool", "broadcast bool -> bool")
check(source_dataset_13:col("flag"):get(1) == true,   "broadcast bool valor")

-- adicionar coluna Series<bool> explícita via __newindex
local mask_sp = source_dataset_13:col("cidade"):eq("SP")
source_dataset_13["eh_sp"] = mask_sp
check(source_dataset_13:col("eh_sp")._dtype == "bool",  "Series<bool> como coluna")
check(source_dataset_13:col("eh_sp"):get(1) == true,    "bool coluna: pos 1 = true")
check(source_dataset_13:col("eh_sp"):get(2) == false,   "bool coluna: pos 2 = false")

-- head/tail sobre DataSet com coluna bool
local head_result = source_dataset_13:head(2)
check(head_result:nrows() == 2,                            "head com bool coluna")
check(head_result:col("eh_sp")._dtype == "bool",           "head preserva bool coluna")
check(head_result:col("eh_sp"):get(1) == true,             "head bool valor correto")

local tail_result = source_dataset_13:tail(2)
check(tail_result:nrows() == 2,                        "tail com bool coluna")
check(tail_result:col("eh_sp"):get(1) == true,         "tail bool: pos 1 = SP (true)")
check(tail_result:col("eh_sp"):get(2) == false,        "tail bool: pos 2 = MG (false)")

-- filter sobre DataSet com coluna bool
local sp_dataset = source_dataset_13:filter(source_dataset_13:col("cidade"):eq("SP"))
check(sp_dataset:nrows() == 2,                          "filter com bool coluna")
check(sp_dataset:col("eh_sp")._dtype == "bool",         "filter preserva bool coluna")

-- to_table sobre DataSet com coluna bool
local table_values_2 = source_dataset_13:to_table()
check(type(table_values_2.eh_sp) == "table",   "to_table: bool coluna vira tabela")
check(table_values_2.eh_sp[1] == true,         "to_table: bool valor 1")
check(table_values_2.eh_sp[2] == false,        "to_table: bool valor 2")

-- describe sobre DataSet com coluna bool
local description_2 = source_dataset_13:describe()
check(type(description_2.eh_sp) == "table",         "describe: bool coluna tem entrada")
check(description_2.eh_sp.count == 4,               "describe bool: count")
check(description_2.eh_sp.count_true == 2,          "describe bool: count_true")
check(description_2.eh_sp.count_false == 2,         "describe bool: count_false")

-- sort_by com coluna bool (false < true)
local sorted_boolean_series = source_dataset_13:sort_by("eh_sp", true)
check(sorted_boolean_series:nrows() == 4,                        "sort_by bool coluna")
check(sorted_boolean_series:col("eh_sp"):get(1) == false,        "sort_by bool: falses primeiro")
check(sorted_boolean_series:col("eh_sp"):get(3) == true,         "sort_by bool: trues depois")

-- dropna com coluna bool (sem NAs aqui — deve retornar tudo)
local non_null_result_4 = source_dataset_13:dropna()
check(non_null_result_4:nrows() == 4, "dropna com bool coluna sem NAs")

-- fillna sobre Series<bool> diretamente (sem NAs: fillna é no-op semântico)
local base_columns_callback = source_dataset_13:col("eh_sp"):fillna(false)
check(base_columns_callback._dtype == "bool", "fillna DataSet: bool coluna preservada")

-- =====================================================================
-- df[mask]: indexação por Series<bool> (__index dispatch)
-- =====================================================================
-- df[mask] é açúcar para df:filter(mask); testa o dispatch do __index.
local mask_caros = source_dataset["preco"]:gt(25)          -- preco > 25 -> linhas 3,4,5
local mask_result = source_dataset[mask_caros]
check(mask_result:nrows() == 3,              "df[mask]: nrows correto")
check(mask_result["id"]:get(1) == 3,        "df[mask]: primeira linha correta")
check(mask_result["preco"]:get(3) == 50,    "df[mask]: última linha correta")

-- resultado idêntico ao df:filter(mask) explícito
local filtered_result = source_dataset:filter(mask_caros)
check(mask_result:nrows() == filtered_result:nrows(),            "df[mask] == df:filter: nrows")
check(mask_result["id"]:get(2) == filtered_result["id"]:get(2), "df[mask] == df:filter: valores")

-- expressão inline: df[df["col"]:op(val)]
local inline_result = source_dataset[source_dataset["preco"]:lt(25)]        -- preco < 25 -> linhas 1,2
check(inline_result:nrows() == 2,           "df[mask] inline: nrows")
check(inline_result["id"]:get(1) == 1,     "df[mask] inline: primeira linha")

-- máscara que seleciona zero linhas
local empty_result = source_dataset[source_dataset["preco"]:gt(999)]
check(empty_result:nrows() == 0,            "df[mask] zero linhas")
check(empty_result:ncols() == source_dataset:ncols(),   "df[mask] zero linhas preserva colunas")

-- =====================================================================
-- DataSet ops (de test_dataset_ops.lua)
-- =====================================================================

local source_dataset_14 = smaug.DataSet({
    {"uf",     {"SP","RJ","MG","SP","RJ"}, "string"},
    {"vendas", {10,  20,  30,  40,  50},   "int64"},
    {"custo",  {1.0, 2.0, 3.0, 4.0, 5.0}, "float64"},
})

-- ================================================================
-- assign
-- ================================================================

-- adicionar coluna nova via função
local assign_result = source_dataset_14:assign("margem", function(dataset)
    return dataset:col("vendas"):map(function(value) return value * 2 end, "int64")
end)
check(assign_result:has_column("margem"),            "assign: coluna margem adicionada")
check(assign_result:col("margem"):get(1) == 20,     "assign: margem[1]=20")
check(assign_result:col("margem"):get(5) == 100,    "assign: margem[5]=100")
check(assign_result:nrows() == 5,                   "assign: nrows inalterado")
-- original não mutado
check(not source_dataset_14:has_column("margem"),        "assign: original imutável")

-- adicionar coluna via Series direta
local replacement_series = smaug.Series({1,2,3,4,5}, "int64")
local assign_result_2 = source_dataset_14:assign("idx", replacement_series)
check(assign_result_2:has_column("idx"),              "assign Series: coluna adicionada")
check(assign_result_2:col("idx"):get(3) == 3,        "assign Series: valor correto")

-- substituir coluna existente
local assign_result_3 = source_dataset_14:assign("vendas", function(dataset)
    return dataset:col("vendas"):map(function(value) return value + 1000 end, "int64")
end)
check(assign_result_3:col("vendas"):get(1) == 1010,  "assign substituir: valor novo")
check(assign_result_3:ncols() == source_dataset_14:ncols(),         "assign substituir: ncols inalterado")
-- posição da coluna preservada
check(assign_result_3._col_names[2] == "vendas",     "assign substituir: posição preservada")
-- original não mutado, mesmo SUBSTITUINDO coluna existente (H.6.6.2: contrato
-- de imutabilidade do assign — fácil esquecer de capturar o retorno)
check(source_dataset_14:col("vendas"):get(1) == 10,     "assign substituir: original preserva valor antigo")

-- erro: tamanho errado
local succeeded_4, unused_error = pcall(function()
    source_dataset_14:assign("x", smaug.Series({1,2}, "int64"))
end)
check(not succeeded_4,                            "assign: erro tamanho errado")

-- erro: não é Series nem função
local succeeded_5, unused_error_2 = pcall(function() source_dataset_14:assign("x", 42) end)
check(not succeeded_5,                            "assign: erro tipo inválido")

-- ================================================================
-- nunique
-- ================================================================
local unique_count = source_dataset_14:nunique()
check(unique_count.uf == 3,                         "nunique uf: 3")
check(unique_count.vendas == 5,                     "nunique vendas: 5")

local source_dataset_15 = smaug.DataSet({
    {"k", {1,1,smaug.NA,2}, "int64"},
    {"v", {"a","b","a","a"}, "string"},
})
local unique_count_2 = source_dataset_15:nunique()
check(unique_count_2.k == 2,                         "nunique com NA: 2 distintos (NA excluído)")
check(unique_count_2.v == 2,                         "nunique string: 2")

-- ================================================================
-- rolling
-- ================================================================
-- window=3
local sum_result = source_dataset_14:rolling(3):sum("vendas")
check(sum_result:is_null(1),                      "rolling(3) sum: [1]=NA")
check(sum_result:is_null(2),                      "rolling(3) sum: [2]=NA")
check(sum_result:get(3) == 60,                    "rolling(3) sum: [3]=60 (10+20+30)")
check(sum_result:get(4) == 90,                    "rolling(3) sum: [4]=90 (20+30+40)")
check(sum_result:get(5) == 120,                   "rolling(3) sum: [5]=120 (30+40+50)")

-- mean
local mean_result = source_dataset_14:rolling(2):mean("vendas")
check(mean_result:is_null(1),                      "rolling(2) mean: [1]=NA")
check(approximately_equal(mean_result:get(2), 15.0),            "rolling(2) mean: [2]=15")
check(approximately_equal(mean_result:get(5), 45.0),            "rolling(2) mean: [5]=45")

-- min/max
local minimum_result = source_dataset_14:rolling(2):min("vendas")
check(minimum_result:get(2) == 10,                  "rolling min: [2]=10")
check(minimum_result:get(5) == 40,                  "rolling min: [5]=40")

local maximum_result = source_dataset_14:rolling(2):max("vendas")
check(maximum_result:get(2) == 20,                  "rolling max: [2]=20")
check(maximum_result:get(5) == 50,                  "rolling max: [5]=50")

-- window=1: sem NA
local sum_result_2 = source_dataset_14:rolling(1):sum("vendas")
check(sum_result_2:get(1) == 10,                    "rolling(1): sem NA")
check(sum_result_2:get(5) == 50,                    "rolling(1): [5]=50")

-- NA dentro da janela: ignorado
local source_dataset_16 = smaug.DataSet({{"v",{10,smaug.NA,30},"int64"}})
local sum_result_3 = source_dataset_16:rolling(2):sum("v")
check(sum_result_3:is_null(1),                     "rolling com NA: [1]=NA (janela incompleta)")
check(sum_result_3:get(2) == 10,                   "rolling com NA: [2]=10 (NA ignorado)")
check(sum_result_3:get(3) == 30,                   "rolling com NA: [3]=30 (NA ignorado)")

-- erro: window inválido
local succeeded_6, unused_error_3 = pcall(function() source_dataset_14:rolling(0) end)
check(not succeeded_6,                            "rolling: window=0 recusado")
local succeeded_7, unused_error_4 = pcall(function() source_dataset_14:rolling(1.5) end)
check(not succeeded_7,                            "rolling: window fracionário recusado")

-- item 8c: DataSet rolling delega à Series (que delega ao C). Ganha
-- std/var/count e min_periods de graça; sem _agg próprio.
local standard_deviation_result = source_dataset_14:rolling(3):std("vendas")
check(standard_deviation_result:is_null(2),                    "8c ds rolling std[2]=NA")
check(approximately_equal(standard_deviation_result:get(3), 10.0),          "8c ds rolling std[3]=10 ({10,20,30})")
local count_result = source_dataset_14:rolling(3):count("vendas")
check(count_result:get(3) == 3,                   "8c ds rolling count[3]=3")
check(count_result:dtype() == "int64",            "8c ds rolling count→int64")
-- min_periods no DataSet (bug-free, delega ao C corrigido)
local sum_result_4 = source_dataset_14:rolling(3):min_periods(1):sum("vendas")
check(sum_result_4:get(1) == 10,                   "8c ds rolling mp1 sum[1]=10 (parcial)")
check(sum_result_4:get(2) == 30,                   "8c ds rolling mp1 sum[2]=30")
check(sum_result_4:get(3) == 60,                   "8c ds rolling mp1 sum[3]=60")
-- correção de tipo: mean de i64 → float64 (antes truncava)
local source_dataset_17 = smaug.DataSet({{"v",{10,20,30},"int64"}})
check(source_dataset_17:rolling(2):mean("v"):dtype() == "float64", "8c ds rolling mean i64→float64")

-- ================================================================
-- pivot
-- ================================================================
local source_dataset_18 = smaug.DataSet({
    {"uf",    {"SP","SP","RJ","RJ","MG"}, "string"},
    {"prod",  {"A", "B", "A", "B", "A"}, "string"},
    {"val",   {10,  20,  30,  40,  50},   "int64"},
})
local pivot_result = source_dataset_18:pivot("uf","prod","val")
check(pivot_result:nrows() == 3,                  "pivot: 3 linhas (3 UFs)")
check(pivot_result:has_column("uf"),              "pivot: coluna uf")
check(pivot_result:has_column("A"),               "pivot: coluna A")
check(pivot_result:has_column("B"),               "pivot: coluna B")
-- valores
local uf_vals = {}
for row_index=1,3 do uf_vals[pivot_result:col("uf"):get(row_index)] = row_index end
check(pivot_result:col("A"):get(uf_vals["SP"]) == 10, "pivot SP-A=10")
check(pivot_result:col("B"):get(uf_vals["SP"]) == 20, "pivot SP-B=20")
check(pivot_result:col("A"):get(uf_vals["RJ"]) == 30, "pivot RJ-A=30")
check(pivot_result:col("A"):get(uf_vals["MG"]) == 50, "pivot MG-A=50")
check(pivot_result:col("B"):is_null(uf_vals["MG"]),   "pivot MG-B=NA")

-- erros
local succeeded_8, unused_error_5 = pcall(function() source_dataset_18:pivot("xxx","prod","val") end)
check(not succeeded_8,                            "pivot: coluna inexistente")
local succeeded_9, unused_error_6 = pcall(function() source_dataset_18:pivot("uf","prod",42) end)
check(not succeeded_9,                            "pivot: argumento não-string")

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
local values = {}
for row_index=1,4 do
    values[row_index] = {
        uf=long2:col("uf"):get(row_index),
        var=long2:col("variable"):get(row_index),
        val=long2:col("value"):get(row_index)
    }
end
check(values[1].uf=="SP" and values[1].var=="2022" and values[1].val==100, "melt [1]: SP/2022/100")
check(values[4].uf=="RJ" and values[4].var=="2023" and values[4].val==250, "melt [4]: RJ/2023/250")

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
local succeeded_10, unused_error_7 = pcall(function() wide2:melt("xxx") end)
check(not succeeded_10,                            "melt: id_var inexistente")
local succeeded_11, unused_error_8 = pcall(function() wide2:melt("uf", {"xxx"}) end)
check(not succeeded_11,                            "melt: value_var inexistente")

-- =====================================================================
-- DataSet novos: rename, pivot_table, stack, unstack, explode (de test_enrich.lua)
-- =====================================================================

local source_dataset_19 = smaug.DataSet({
    {"uf",    {"SP","RJ","SP","MG","RJ","SP"}, "string"},
    {"v",     {10.0,20.0,30.0,40.0,50.0,20.0},"float64"},
})
local grouped_dataset = source_dataset_19:groupby("uf")

-- ================================================================
-- DataSet novos
-- ================================================================

-- rename
local rename_result = source_dataset_19:rename({uf="estado", v="valor"})
check(rename_result:has_column("estado"),    "rename: estado existe")
check(rename_result:has_column("valor"),     "rename: valor existe")
check(not rename_result:has_column("uf"),    "rename: uf não existe mais")
check(rename_result:nrows() == source_dataset_19:nrows(),   "rename: nrows preservado")

-- rename em lote preserva ordem
local columns_new = rename_result:columns()
check(columns_new[1] == "estado",     "rename: ordem [1]=estado")
check(columns_new[2] == "valor",      "rename: ordem [2]=valor")

-- pivot_table
local source_dataset_20 = smaug.DataSet({
    {"ano",  {2023,2023,2024,2024},    "int64"},
    {"mes",  {"jan","fev","jan","fev"},"string"},
    {"val",  {10.0,20.0,30.0,40.0},   "float64"},
})
local pivoted_dataset = source_dataset_20:pivot_table("ano","mes","val","sum")
check(pivoted_dataset:nrows() == 2,             "pivot_table: 2 anos")
check(pivoted_dataset:has_column("jan"),        "pivot_table: coluna jan")
check(pivoted_dataset:has_column("fev"),        "pivot_table: coluna fev")
check(pivoted_dataset:has_column("ano"),        "pivot_table: coluna index")
-- 2023 jan=10, 2023 fev=20
local ano2023 = nil
for row_index=1,pivoted_dataset:nrows() do
    if pivoted_dataset:col("ano"):get(row_index) == 2023 then ano2023=row_index; break end
end
check(pivoted_dataset:col("jan"):get(ano2023) == 10.0, "pivot jan 2023=10")
check(pivoted_dataset:col("fev"):get(ano2023) == 20.0, "pivot fev 2023=20")

-- pivot_table aggfunc "mean"
local pivoted_dataset_2 = source_dataset_20:pivot_table("ano","mes","val","mean")
check(pivoted_dataset_2:col("jan"):get(ano2023) == 10.0, "pivot mean jan 2023=10")

-- stack
local source_dataset_21 = smaug.DataSet({
    {"id", {1,2},       "int64"},
    {"a",  {10.0,20.0}, "float64"},
    {"b",  {30.0,40.0}, "float64"},
})
local stacked_dataset = source_dataset_21:stack({"a","b"})
check(stacked_dataset:nrows() == 4,            "stack nrows=4")
check(stacked_dataset:has_column("variable"),  "stack: coluna variable")
check(stacked_dataset:has_column("value"),     "stack: coluna value")
check(stacked_dataset:has_column("id"),        "stack: coluna id preservada")
-- ordem: (1,a,10), (1,b,30), (2,a,20), (2,b,40)
local variance_column = stacked_dataset:col("variable"):to_table()
check(variance_column[1] == "a" or variance_column[1] == "b", "stack: variable[1] é a ou b")

-- unstack (pivot com first)
local unstacked_dataset = source_dataset_20:unstack("ano","mes","val")
check(unstacked_dataset:nrows() == 2,             "unstack nrows=2")
check(unstacked_dataset:has_column("jan"),        "unstack: coluna jan")

-- explode com tabelas Lua (uso via assign)
local source_dataset_22 = smaug.DataSet({{"id", {1,2}, "int64"}})
-- simula coluna com listas usando melt/map não é direto,
-- mas explode pode ser testado via coluna string que representa lista
-- Para este teste, validamos que explode funciona com valores escalares
-- (caso degenerado: cada valor já é escalar → linha 1-para-1)
local source_dataset_23 = smaug.DataSet({
    {"id",  {10,20,30}, "int64"},
    {"val", {1.0,2.0,3.0}, "float64"},
})
local exploded_dataset = source_dataset_23:explode("val")
check(exploded_dataset:nrows() == 3,           "explode escalar: nrows=3")
check(exploded_dataset:col("val"):get(1) == 1.0, "explode escalar: val[1]=1.0")

-- ================================================================
-- 6.5 — DataSet:clone() (par de Series:clone; cópia profunda)
-- ================================================================
do
    local source_dataset_24 = smaug.DataSet({{"a", {1, 2}, "int64"}, {"b", {"x", "y"}, "string"}})
    local cloned_series = source_dataset_24:clone()
    check(#cloned_series:to_dict().a == 2 and cloned_series:column("a"):get(1) == 1, "6.5 clone: valores copiados")
    check(table.concat(cloned_series._col_names, ",") == "a,b", "6.5 clone: nomes e ordem preservados")
    -- cópia PROFUNDA: mutar o clone (via update_column) não afeta o original
    cloned_series:update_column("a", smaug.Series({99, 2}, "int64"))
    check(source_dataset_24:column("a"):get(1) == 1, "6.5 clone: profundo (original intacto)")
    check(cloned_series:column("a"):get(1) == 99, "6.5 clone: mutação isolada no clone")
    -- DataSet vazio
    check(smaug.DataSet.new("vazio"):clone():ncols() == 0, "6.5 clone: DataSet vazio")
end

-- ================================================================
-- 9.2 — Contrato de fronteira: column()/col() protege o frame (E2 morto)
-- ================================================================
do
    local source_dataset_24 = smaug.DataSet({
        {"num", {10, 20, 30}, "float64"},
        {"cnt", {1, 2, 3}, "int64"},
        {"txt", {"a", "b", "c"}, "string"},
    })
    -- set numa coluna extraída NÃO propaga para o frame (view COW)
    source_dataset_24:col("num"):set(1, 999.0)
    check(source_dataset_24:col("num"):get(1) == 10.0, "9.2 float64: col() protege o frame")
    source_dataset_24:col("cnt"):set(1, 999)
    check(source_dataset_24:col("cnt"):get(1) == 1,    "9.2 int64: col() protege o frame")
    source_dataset_24:col("txt"):set(1, "ZZZ")
    check(source_dataset_24:col("txt"):get(1) == "a",  "9.2 string: col() protege o frame")

    -- set_null e append também não propagam
    source_dataset_24:col("num"):set_null(2)
    check(source_dataset_24:col("num"):get(2) == 20.0, "9.2 float64: set_null em col() não propaga")
    local before_2 = source_dataset_24:nrows()
    source_dataset_24:col("num"):append(77.0)
    check(source_dataset_24:nrows() == before_2,         "9.2: append em col() não altera nrows do frame")

    -- a view reflete a própria mutação (só o frame é que fica intacto)
    local column_result = source_dataset_24:col("num")
    column_result:set(1, 555.0)
    check(column_result:get(1) == 555.0,            "9.2: a view extraída vê a própria escrita")
    check(source_dataset_24:col("num"):get(1) == 10.0, "9.2: mas o frame permanece intacto")

    -- categorical: protegido via clone (não tem view)
    local source_dataset_25 = smaug.DataSet({{"cat", {"x", "y", "x"}, "categorical"}})
    local extracted = source_dataset_25:col("cat")
    check(extracted ~= nil,             "9.2 categorical: col() retorna cópia protegida")
end

do
    -- 12.12: chave desconhecida erra com sugestão (método OU coluna)
    local source_dataset_24 = smaug.DataSet({ {"vendas", {10, 20}, "int64"},
                                {"regiao", {"SP", "RJ"}, "string"} })
    local function message(callback) local succeeded_12, error_message = pcall(callback); return tostring(error_message) end

    local error_message = message(function() return source_dataset_24:group_by("regiao") end)
    check(error_message:find("não existe", 1, true) ~= nil, "12.12 DataSet: método inexistente erra")
    check(error_message:find("'groupby'", 1, true) ~= nil,  "12.12 DataSet: sugere 'groupby' para 'group_by'")

    -- typo de COLUNA sugere a coluna (candidatos incluem os nomes reais)
    local error_message_2 = message(function() return source_dataset_24.vendass end)
    check(error_message_2:find("'vendas'", 1, true) ~= nil,   "12.12 DataSet: sugere coluna 'vendas' para 'vendass'")

    local error_message_3 = message(function() return source_dataset_24.xyzabc end)
    check(error_message_3:find("não existe", 1, true) ~= nil, "12.12 DataSet: nome distante erra")
    check(error_message_3:find("quis dizer", 1, true) == nil, "12.12 DataSet: nome distante NÃO sugere")

    -- contratos preservados
    check(source_dataset_24._inexistente == nil,               "12.12 DataSet: chave _interna devolve nil")
    check(source_dataset_24:has_column("foo") == false,        "12.12 DataSet: has_column('foo') = false (não erra)")
    check(source_dataset_24.vendas ~= nil,                     "12.12 DataSet: coluna real intacta")
    check(source_dataset_24:nrows() == 2,                      "12.12 DataSet: método real intacto")
end

print(string.format("OK — %d checks passaram (DataSet: core, ops, rename, pivot_table, stack, unstack, explode)", passed_checks))
