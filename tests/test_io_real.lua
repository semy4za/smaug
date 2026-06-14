-- tests/test_io_real.lua
-- Teste do Anel 3 com dados reais: tests/pedidos_digitados.csv
-- Tabela: pedidos_digitados — 916 linhas, 15 colunas, separador ';'
-- Valida o parser, a inferência de tipos e operações sobre dados reais.
-- Rode da raiz:  luajit tests/test_io_real.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- ================================================================
-- Leitura com separador customizado
-- ================================================================
local ds = smaug.read_csv("tests/pedidos_digitados.csv", { sep = ";" })
check(ds ~= nil,                         "leitura: sem erro")
check(ds:nrows() == 916,                 "nrows: 916 linhas de dados")
check(ds:ncols() == 15,                  "ncols: 15 colunas")

-- ================================================================
-- Nomes das colunas
-- ================================================================
local cols = ds:columns()
check(cols[1]  == "MES_COMP",            "col[1] = MES_COMP")
check(cols[4]  == "N_PEDIDO_SAP",        "col[4] = N_PEDIDO_SAP")
check(cols[13] == "(un)",                "col[13] = (un)")
check(cols[14] == "(R$)",                "col[14] = (R$)")
check(cols[15] == "motivo_recusa",       "col[15] = motivo_recusa")

-- ================================================================
-- Inferência de tipos
-- ================================================================
-- MES_COMP é "2026/06" — string (barra impede int/float)
check(ds:col("MES_COMP")._dtype    == "string", "MES_COMP: string")
-- N_PEDIDO_SAP é inteiro de 8 dígitos
check(ds:col("N_PEDIDO_SAP")._dtype == "int64", "N_PEDIDO_SAP: int64")
-- (un) é inteiro (1, 2, 3...)
check(ds:col("(un)")._dtype         == "int64", "(un): int64")
-- (R$) tem vírgula decimal ("34,12") — string, não float
check(ds:col("(R$)")._dtype         == "string", "(R$): string (vírgula decimal)")
-- Empresa, produto etc: string
check(ds:col("Empresa")._dtype      == "string", "Empresa: string")
check(ds:col("tp_produto")._dtype   == "string", "tp_produto: string")

-- ================================================================
-- Valores individuais (linha 1)
-- ================================================================
check(ds:col("MES_COMP"):get(1)    == "2026/06",  "MES_COMP[1]")
check(ds:col("Empresa"):get(1)     == "DB10",      "Empresa[1]")
check(ds:col("N_PEDIDO_SAP"):get(1) == 51208236,   "N_PEDIDO_SAP[1]")
check(ds:col("(un)"):get(1)        == 2,           "(un)[1] = 2")
check(ds:col("(R$)"):get(1)        == "34,12",     "(R$)[1] = 34,12")

-- ================================================================
-- NA em motivo_recusa (913 vazios, 3 com texto)
-- ================================================================
local motivo = ds:col("motivo_recusa")
local com_motivo = 0
for i = 1, ds:nrows() do
    if not motivo:is_null(i) then com_motivo = com_motivo + 1 end
end
check(com_motivo == 3,                   "motivo_recusa: 3 linhas com motivo")
check(ds:nrows() - com_motivo == 913,    "motivo_recusa: 913 NAs")

-- ================================================================
-- Empresas únicas
-- ================================================================
local emp_unique = ds:col("Empresa"):unique()
check(emp_unique:len() == 5,             "Empresa: 5 valores únicos")
check(ds:col("Empresa"):nunique() == 5,  "Empresa nunique: 5")

-- ================================================================
-- Contagens por empresa (groupby count)
-- ================================================================
local por_empresa = ds:groupby("Empresa"):count()
check(por_empresa:nrows() == 5,          "groupby Empresa: 5 grupos")

local cnt = {}
for i = 1, por_empresa:nrows() do
    cnt[por_empresa:col("Empresa"):get(i)] = por_empresa:col("count"):get(i)
end
check(cnt["DB10"] == 210,  "count DB10 = 210")
check(cnt["DC10"] == 454,  "count DC10 = 454")
check(cnt["DG10"] == 194,  "count DG10 = 194")
check(cnt["DP10"] == 33,   "count DP10 = 33")
check(cnt["DS10"] == 25,   "count DS10 = 25")

-- ================================================================
-- Soma de unidades por empresa (groupby sum)
-- ================================================================
local uns_empresa = ds:groupby("Empresa"):sum("(un)")
local uns = {}
for i = 1, uns_empresa:nrows() do
    uns[uns_empresa:col("Empresa"):get(i)] = uns_empresa:col("(un)"):get(i)
end
check(uns["DB10"] == 228,  "sum (un) DB10 = 256")
check(uns["DC10"] == 839,  "sum (un) DC10 = 839")
check(uns["DG10"] == 216,  "sum (un) DG10 = 216")
check(uns["DP10"] == 50,   "sum (un) DP10 = 50")
check(uns["DS10"] == 30,   "sum (un) DS10 = 30")

-- ================================================================
-- tp_produto: 5 marcas
-- ================================================================
local tp_count = ds:groupby("tp_produto"):count()
check(tp_count:nrows() == 5,             "tp_produto: 5 marcas")
local tp = {}
for i = 1, tp_count:nrows() do
    tp[tp_count:col("tp_produto"):get(i)] = tp_count:col("count"):get(i)
end
check(tp["ALFAPARF"] == 129,  "ALFAPARF: 129 linhas")
check(tp["DBELLA"]   == 207,  "DBELLA: 207 linhas")
check(tp["RAAVI"]    == 454,  "RAAVI: 454 linhas")
check(tp["YELLOW"]   == 111,  "YELLOW: 111 linhas")
check(tp["ALTAMODA"] == 15,   "ALTAMODA: 15 linhas")

-- ================================================================
-- Pedidos únicos
-- ================================================================
check(ds:col("N_PEDIDO_SAP"):nunique() == 155, "pedidos únicos: 155")

-- ================================================================
-- filter: só pedidos DB10
-- ================================================================
local db10 = ds:filter(ds:col("Empresa"):eq("DB10"))
check(db10:nrows() == 210,               "filter DB10: 210 linhas")
check(db10:col("Empresa"):nunique() == 1,"filter DB10: só 1 empresa")

-- ================================================================
-- filter + groupby encadeado
-- ================================================================
local db10_tp = db10:groupby("tp_produto"):sum("(un)")
check(db10_tp:nrows() > 0,               "DB10 groupby tp_produto: tem grupos")

-- ================================================================
-- join: empresas com metadata
-- ================================================================
local meta = smaug.DataSet({
    {"Empresa",  {"DB10","DC10","DG10","DP10","DS10"}, "string"},
    {"regiao",   {"SP","SP","SP","SP","SP"},            "string"},
    {"ativa",    {true, true, true, true, true},        "bool"},
})
local joined = ds:join(meta, "Empresa", "left")
check(joined:nrows() == 916,             "join left: preserva todas as 916 linhas")
check(joined:has_column("regiao"),       "join: coluna regiao presente")
check(joined:has_column("ativa"),        "join: coluna ativa presente")
check(joined:col("regiao"):get(1) == "SP", "join: regiao[1] = SP")

-- ================================================================
-- Roundtrip CSV: escrever e ler de volta
-- ================================================================
local tmp = "/tmp/smaug_pedidos_rt.csv"
ds:to_csv(tmp, { sep = ";" })
local ds2 = smaug.read_csv(tmp, { sep = ";" })
check(ds2:nrows() == 916,               "roundtrip: 916 linhas")
check(ds2:ncols() == 15,               "roundtrip: 15 colunas")
check(ds2:col("N_PEDIDO_SAP"):get(1) == 51208236, "roundtrip: N_PEDIDO_SAP[1]")
check(ds2:col("(R$)"):get(1) == "34,12",           "roundtrip: (R$)[1] preservado")

-- ================================================================
-- Roundtrip JSON
-- ================================================================
local tmpj = "/tmp/smaug_pedidos_rt.json"
ds:to_json(tmpj)
local ds3 = smaug.read_json(tmpj)
check(ds3:nrows() == 916,              "json roundtrip: 916 linhas")
check(ds3:ncols() == 15,              "json roundtrip: 15 colunas")
check(ds3:col("N_PEDIDO_SAP"):get(1) == 51208236, "json roundtrip: N_PEDIDO_SAP[1]")

print(string.format("OK — %d checks passaram (I/O dados reais: pedidos_digitados)", n_ok))
