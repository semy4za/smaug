-- tests/test_join.lua
-- Teste do DataSet:join (Anel 2 — Operações Relacionais).
-- Hash join: inner, left, right, outer, chaves diferentes, sufixos,
-- múltiplos matches, DataSets vazios.
-- Rode da raiz:  luajit tests/test_join.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- Datasets base
local pedidos = smaug.DataSet({
    {"id",      {1, 2, 3, 4},           "int64"},
    {"cliente", {"A","B","A","C"},       "string"},
    {"valor",   {100, 200, 150, 300},    "int64"},
})
local clientes = smaug.DataSet({
    {"cliente", {"A","B","D"},           "string"},
    {"cidade",  {"SP","RJ","MG"},        "string"},
})

-- ================================================================
-- INNER JOIN
-- ================================================================
local ri = pedidos:join(clientes, "cliente")   -- default = inner
check(ri:nrows() == 3,                         "inner: 3 linhas (C e D sem match)")
check(ri:ncols() == 4,                         "inner: 4 colunas")
check(ri:has_column("id"),                     "inner: tem id")
check(ri:has_column("cliente"),                "inner: tem cliente")
check(ri:has_column("valor"),                  "inner: tem valor")
check(ri:has_column("cidade"),                 "inner: tem cidade")
-- A aparece 2x (pedidos 1 e 3)
local cidades = {}
for i = 1, ri:nrows() do cidades[i] = ri:col("cidade"):get(i) end
check(cidades[1] == "SP" and cidades[2] == "RJ" and cidades[3] == "SP",
      "inner: cidades corretas (SP,RJ,SP)")
check(ri:col("id"):get(1) == 1,                "inner: id linha 1 = 1")
check(ri:col("id"):get(3) == 3,                "inner: id linha 3 = 3 (segundo A)")
-- C (pedido 4) não aparece
local ids = {}; for i=1,ri:nrows() do ids[ri:col("id"):get(i)] = true end
check(not ids[4],                              "inner: pedido 4 (C) excluído")

-- how explícito
local ri2 = pedidos:join(clientes, "cliente", "inner")
check(ri2:nrows() == 3,                        "inner explícito: 3 linhas")

-- ================================================================
-- LEFT JOIN
-- ================================================================
local rl = pedidos:join(clientes, "cliente", "left")
check(rl:nrows() == 4,                         "left: 4 linhas (todos os pedidos)")
check(rl:col("cidade"):is_null(4),             "left: cidade NULL para C")
check(rl:col("cliente"):get(4) == "C",         "left: cliente C na linha 4")
check(not rl:col("cidade"):is_null(1),         "left: cidade não-null para A")
check(rl:col("cidade"):get(1) == "SP",         "left: cidade SP para A")

-- ================================================================
-- RIGHT JOIN
-- ================================================================
local rr = pedidos:join(clientes, "cliente", "right")
check(rr:nrows() == 4,                         "right: 4 linhas (A×2, B, D)")
-- D aparece com NAs no lado esquerdo
local d_row = nil
for i = 1, rr:nrows() do
    if rr:col("cliente"):get(i) == "D" then d_row = i; break end
end
check(d_row ~= nil,                            "right: D presente")
check(rr:col("id"):is_null(d_row),             "right: id NULL para D")
check(rr:col("valor"):is_null(d_row),          "right: valor NULL para D")

-- ================================================================
-- OUTER JOIN
-- ================================================================
local ro = pedidos:join(clientes, "cliente", "outer")
check(ro:nrows() == 5,                         "outer: 5 linhas (A×2, B, C, D)")
-- C: cidade NULL; D: id e valor NULL
local c_row, d_row_o = nil, nil
for i = 1, ro:nrows() do
    local cl = ro:col("cliente"):get(i)
    if cl == "C" then c_row = i end
    if cl == "D" then d_row_o = i end
end
check(c_row ~= nil,                            "outer: C presente")
check(d_row_o ~= nil,                          "outer: D presente")
check(ro:col("cidade"):is_null(c_row),         "outer: cidade NULL para C")
check(ro:col("id"):is_null(d_row_o),           "outer: id NULL para D")

-- ================================================================
-- CHAVES DIFERENTES
-- ================================================================
local fa = smaug.DataSet({
    {"id_pedido", {1,2,3},   "int64"},
    {"val",       {10,20,30}, "int64"},
})
local fb = smaug.DataSet({
    {"id_cliente", {2,3,4},    "int64"},
    {"desc",       {"b","c","d"}, "string"},
})
local rc = fa:join(fb, {"id_pedido","id_cliente"}, "inner")
check(rc:nrows() == 2,                         "chaves diff inner: 2 linhas (2,3)")
check(rc:has_column("id_pedido"),              "chaves diff: coluna esq presente")
check(rc:col("val"):get(1) == 20,              "chaves diff: val linha 1 = 20")
check(rc:col("desc"):get(1) == "b",            "chaves diff: desc linha 1 = b")

local rl2 = fa:join(fb, {"id_pedido","id_cliente"}, "left")
check(rl2:nrows() == 3,                        "chaves diff left: 3 linhas")
check(rl2:col("desc"):is_null(1),              "chaves diff left: desc NULL para id=1")

-- ================================================================
-- SUFIXOS
-- ================================================================
local sx = smaug.DataSet({{"k",{1,2},"int64"},{"nome",{"a","b"},"string"},{"x",{10,20},"int64"}})
local sy = smaug.DataSet({{"k",{1,2},"int64"},{"nome",{"x","y"},"string"},{"y",{100,200},"int64"}})
local rs = sx:join(sy, "k", "inner")
check(rs:has_column("nome_left"),              "sufixos: nome_left presente")
check(rs:has_column("nome_right"),             "sufixos: nome_right presente")
check(not rs:has_column("nome"),               "sufixos: nome sem sufixo ausente")
check(rs:has_column("x"),                      "sufixos: x sem sufixo (só em esq)")
check(rs:has_column("y"),                      "sufixos: y sem sufixo (só em dir)")
check(rs:col("nome_left"):get(1) == "a",       "sufixos: nome_left valor correto")
check(rs:col("nome_right"):get(1) == "x",      "sufixos: nome_right valor correto")

-- sufixos customizados
local rsc = sx:join(sy, "k", "inner", {"_esq","_dir"})
check(rsc:has_column("nome_esq"),              "sufixos custom: nome_esq")
check(rsc:has_column("nome_dir"),              "sufixos custom: nome_dir")

-- ================================================================
-- MÚLTIPLOS MATCHES (N para N)
-- ================================================================
local ma = smaug.DataSet({{"k",{1,1,2},"int64"},{"va",{10,20,30},"int64"}})
local mb = smaug.DataSet({{"k",{1,1,2},"int64"},{"vb",{100,200,300},"int64"}})
local rm = ma:join(mb, "k", "inner")
-- 1×1 cruzado = 4 linhas para k=1, mais 1 para k=2
check(rm:nrows() == 5,                         "N×N: 5 linhas (2×2 + 1×1)")

-- ================================================================
-- DATASETS VAZIOS
-- ================================================================
local empty = smaug.DataSet({{"k",{},"int64"},{"v",{},"int64"}})
local normal = smaug.DataSet({{"k",{1,2},"int64"},{"v",{10,20},"int64"}})

local re1 = empty:join(normal, "k", "inner")
check(re1:nrows() == 0,                        "vazio inner: 0 linhas")
local re2 = normal:join(empty, "k", "inner")
check(re2:nrows() == 0,                        "inner vazio: 0 linhas")
local re3 = normal:join(empty, "k", "left")
check(re3:nrows() == 2,                        "left com right vazio: 2 linhas")
check(re3:col("v_right"):is_null(1),           "left vazio: v_right NULL")
local re4 = empty:join(normal, "k", "outer")
check(re4:nrows() == 2,                        "outer esq-vazio: 2 linhas (do dir)")

-- ================================================================
-- CHAVE INT64
-- ================================================================
local ia = smaug.DataSet({{"id",{10,20,30},"int64"},{"a",{1,2,3},"int64"}})
local ib = smaug.DataSet({{"id",{20,30,40},"int64"},{"b",{20,30,40},"int64"}})
local rii = ia:join(ib, "id", "inner")
check(rii:nrows() == 2,                        "chave int64 inner: 2 linhas")
check(rii:col("id"):get(1) == 20,              "chave int64: id=20")

-- ================================================================
-- ERROS ESPERADOS
-- ================================================================
local ok1, _ = pcall(function() pedidos:join("nao_dataset", "cliente") end)
check(not ok1,                                 "erro: other não-DataSet")

local ok2, _ = pcall(function() pedidos:join(clientes, "inexistente") end)
check(not ok2,                                 "erro: chave esq inexistente")

local ok3, _ = pcall(function() pedidos:join(clientes, {"cliente","inexistente"}) end)
check(not ok3,                                 "erro: chave dir inexistente")

local ok4, _ = pcall(function() pedidos:join(clientes, "cliente", "bad") end)
check(not ok4,                                 "erro: how inválido")

print(string.format("OK — %d checks passaram (join)", n_ok))
