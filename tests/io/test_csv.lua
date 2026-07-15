-- tests/io/test_csv.lua
-- I/O CSV: read_csv_mem, to_csv, e dados reais (pedidos_digitados.csv).
-- Consolida: seção CSV de test_io.lua + test_io_real.lua
-- Rode da raiz: luajit tests/io/test_csv.lua

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


local smaug = require("smaug")
local NA    = smaug.Series.NA

local function approx(a, b) return math.abs(a - b) < 1e-9 end

-- Diretório temporário portátil: respeita TMPDIR/TMP/TEMP (Windows usa TEMP),
-- fallback "/tmp". Separador "/" é aceito pela CRT no Windows e no POSIX.
-- Trata var vazia ("") como ausente (os.getenv devolve "" e não nil nesse caso).
local function tmp_path(name)
    local function nz(v) return (v ~= nil and v ~= "") and v or nil end
    local dir = nz(os.getenv("TMPDIR")) or nz(os.getenv("TMP"))
             or nz(os.getenv("TEMP")) or "/tmp"
    return dir .. "/" .. name
end

-- ================================================================
-- CSV — read_csv_mem
-- ================================================================

-- básico: int64, float64, bool, string, NA
local csv1 = "uf,vendas,custo,ativo,obs\nSP,100,1.5,true,capital\nRJ,200,2.3,false,\nMG,150,,true,interior\n"
local ds = smaug.read_csv_mem(csv1)
check(ds:nrows() == 3,                      "csv: 3 linhas")
check(ds:ncols() == 5,                      "csv: 5 colunas")
check(ds:col("uf")._dtype   == "string",    "csv: uf=string")
check(ds:col("vendas")._dtype == "int64",   "csv: vendas=int64")
check(ds:col("custo")._dtype  == "float64", "csv: custo=float64")
check(ds:col("ativo")._dtype  == "bool",    "csv: ativo=bool")
check(ds:col("uf"):get(1) == "SP",          "csv: uf[1]=SP")
check(ds:col("vendas"):get(2) == 200,       "csv: vendas[2]=200")
check(approx(ds:col("custo"):get(1), 1.5),  "csv: custo[1]=1.5")
check(ds:col("ativo"):get(1) == true,       "csv: ativo[1]=true")
check(ds:col("ativo"):get(2) == false,      "csv: ativo[2]=false")
check(not ds:col("ativo"):is_null(2),       "csv: ativo[2] não é NA")
check(ds:col("custo"):is_null(3),           "csv: custo[3]=NA (vazio)")
check(ds:col("obs"):is_null(2),             "csv: obs[2]=NA (vazio)")
check(ds:col("obs"):get(1) == "capital",    "csv: obs[1]=capital")

-- sep customizado (TSV)
local tsv = "a\tb\tc\n1\t2.5\tX\n4\t5.0\tY\n"
local tv = smaug.read_csv_mem(tsv, {sep="\t"})
check(tv:nrows() == 2,                      "tsv: 2 linhas")
check(tv:col("a"):get(1) == 1,              "tsv: a[1]=1")
check(approx(tv:col("b"):get(2), 5.0),      "tsv: b[2]=5.0")
check(tv:col("c"):get(1) == "X",            "tsv: c[1]=X")

-- sem header
local noh = "1,2\n3,4\n"
local dn = smaug.read_csv_mem(noh, {header=false})
check(dn:nrows() == 2,                      "sem header: 2 linhas")
check(dn:has_column("col0"),               "sem header: col0 existe")
check(dn:col("col0"):get(1) == 1,           "sem header: col0[1]=1")

-- aspas RFC 4180
local qcsv = 'nome,cidade\n"Fulano, Jr.","São Paulo"\nBeltrano,"Rio"\n'
local qds = smaug.read_csv_mem(qcsv)
check(qds:col("nome"):get(1) == "Fulano, Jr.", "aspas: nome com vírgula")
check(qds:col("cidade"):get(1) == "São Paulo",  "aspas: cidade com espaço")

-- aspas duplas escapadas
local esc = 'col\n"valor ""com"" aspas"\n'
local eds = smaug.read_csv_mem(esc)
check(eds:col("col"):get(1) == 'valor "com" aspas', 'aspas escapadas: ""')

-- inferência: coluna mista int/float → float64
local mix = "v\n1\n2.5\n3\n"
local mds = smaug.read_csv_mem(mix)
check(mds:col("v")._dtype == "float64",     "inferência mista: float64")

-- coluna toda NA → string
local allna = "v\n\n\n\n"
local ands = smaug.read_csv_mem(allna)
check(ands:col("v")._dtype == "string",     "col toda NA → string")

-- valores NA customizados (na_values não suportado na API Lua ainda — NA padrão)
local nacsv = "v\nNA\nnull\n1\n"
local nads = smaug.read_csv_mem(nacsv)
check(nads:col("v"):is_null(1),             "NA padrão: 'NA'=null")
check(nads:col("v"):is_null(2),             "NA padrão: 'null'=null")
check(nads:col("v"):get(3) == 1,            "NA padrão: '1'=1")

-- ================================================================
-- CSV — to_csv_mem (roundtrip)
-- ================================================================
local rt_csv = ds:to_csv_mem()
check(type(rt_csv) == "string",              "to_csv_mem: retorna string")
check(#rt_csv > 0,                           "to_csv_mem: não vazia")

local ds_rt = smaug.read_csv_mem(rt_csv)
check(ds_rt:nrows() == 3,                   "roundtrip: 3 linhas")
check(ds_rt:col("vendas"):get(1) == 100,    "roundtrip: vendas[1]=100")
check(ds_rt:col("ativo"):get(1) == true,    "roundtrip: ativo[1]=true")
check(ds_rt:col("ativo"):get(2) == false,   "roundtrip: ativo[2]=false")
check(ds_rt:col("custo"):is_null(3),        "roundtrip: custo[3]=NA")
check(ds_rt:col("obs"):is_null(2),          "roundtrip: obs[2]=NA")

-- float roundtrip
local fcsv = "v\n1.5\n2.7\n"
local fds = smaug.read_csv_mem(fcsv)
local fout = fds:to_csv_mem()
local fds2 = smaug.read_csv_mem(fout)
check(approx(fds2:col("v"):get(1), 1.5),    "float roundtrip: 1.5")
check(approx(fds2:col("v"):get(2), 2.7),    "float roundtrip: 2.7")

-- ================================================================
-- CSV — to_csv / read_csv (arquivo)
-- ================================================================
local tmp = tmp_path("smaug_test_io.csv")
ds:to_csv(tmp)
local ds_f = smaug.read_csv(tmp)
check(ds_f:nrows() == 3,                    "arquivo: 3 linhas")
check(ds_f:col("uf"):get(2) == "RJ",        "arquivo: uf[2]=RJ")
check(ds_f:col("ativo"):get(2) == false,    "arquivo: ativo[2]=false")


-- =====================================================================
-- Dados reais: pedidos_digitados.csv (de test_io_real.lua)
-- =====================================================================


package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA


-- Diretório temporário portátil (ver test_io.lua): TMPDIR/TMP/TEMP, fallback /tmp.
-- Trata var vazia como ausente.
local function tmp_path(name)
    local function nz(v) return (v ~= nil and v ~= "") and v or nil end
    local dir = nz(os.getenv("TMPDIR")) or nz(os.getenv("TMP"))
             or nz(os.getenv("TEMP")) or "/tmp"
    return dir .. "/" .. name
end

-- ================================================================
-- Leitura com separador customizado
-- ================================================================
local ds = smaug.read_csv("tests/fixtures/pedidos_digitados.csv", { sep = ";" })
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
local tmp = tmp_path("smaug_pedidos_rt.csv")
ds:to_csv(tmp, { sep = ";" })
local ds2 = smaug.read_csv(tmp, { sep = ";" })
check(ds2:nrows() == 916,               "roundtrip: 916 linhas")
check(ds2:ncols() == 15,               "roundtrip: 15 colunas")
check(ds2:col("N_PEDIDO_SAP"):get(1) == 51208236, "roundtrip: N_PEDIDO_SAP[1]")
check(ds2:col("(R$)"):get(1) == "34,12",           "roundtrip: (R$)[1] preservado")

-- ================================================================
-- Roundtrip JSON
-- ================================================================
local tmpj = tmp_path("smaug_pedidos_rt.json")
ds:to_json(tmpj)
local ds3 = smaug.read_json(tmpj)
check(ds3:nrows() == 916,              "json roundtrip: 916 linhas")
check(ds3:ncols() == 15,              "json roundtrip: 15 colunas")
check(ds3:col("N_PEDIDO_SAP"):get(1) == 51208236, "json roundtrip: N_PEDIDO_SAP[1]")


-- ================================================================
-- 12.10: aviso passivo de separador suspeito
-- ================================================================
do
    -- captura o stderr do canal de warn (core/warn.lua escreve em io.stderr).
    -- io.stderr é userdata (não aceita atribuição de campo), então trocamos o
    -- objeto inteiro por um stub com :write e restauramos depois.
    local function capture(fn)
        local buf = {}
        local real = io.stderr
        io.stderr = { write = function(_, s) buf[#buf+1] = s end }
        local ok, err = pcall(fn)
        io.stderr = real
        if not ok then error(err, 0) end
        return table.concat(buf)
    end

    -- caso-alvo: CSV com ';' lido com sep=',' default → 1 coluna + aviso
    local w1 = capture(function()
        local ds = smaug.read_csv_mem("a;b;c\n1;2;3\n4;5;6\n")
        check(ds:ncols() == 1, "12.10 CSV com ';' e sep=',' vira 1 coluna")
    end)
    check(w1:find("verifique o separador", 1, true) ~= nil,
          "12.10 avisa sobre separador suspeito (';')")
    check(w1:find("sep=';'", 1, true) ~= nil, "12.10 aviso sugere o sep provável")

    -- tab
    local w2 = capture(function() smaug.read_csv_mem("a\tb\n1\t2\n3\t4\n") end)
    check(w2:find("verifique o separador", 1, true) ~= nil, "12.10 avisa para tab")

    -- NÃO avisa: sep correto (multi-coluna)
    local w3 = capture(function() smaug.read_csv_mem("a;b;c\n1;2;3\n", {sep=";"}) end)
    check(w3 == "", "12.10 sep=';' explícito não avisa")

    -- NÃO avisa: CSV normal multi-coluna
    local w4 = capture(function() smaug.read_csv_mem("a,b,c\n1,2,3\n") end)
    check(w4 == "", "12.10 CSV multi-coluna não avisa")

    -- NÃO avisa: 1 coluna legítima, sem separador suspeito
    local w5 = capture(function() smaug.read_csv_mem("nome\njoao\nmaria\n") end)
    check(w5 == "", "12.10 1 coluna legítima não avisa")

    -- NÃO avisa: ';' em apenas um valor (texto livre) — exige em todas as amostras
    local w6 = capture(function() smaug.read_csv_mem('obs\n"a; b"\nsem ponto\n') end)
    check(w6 == "", "12.10 ';' esporádico em texto livre não avisa (falso-positivo)")

    -- NÃO avisa: read_json reusa table_to_dataset, mas o hook é só do CSV
    local w7 = capture(function()
        smaug.read_json_mem('[{"obs":"a;b;c"},{"obs":"d;e;f"}]')
    end)
    check(w7 == "", "12.10 read_json não avisa sobre separador (hook é do CSV)")
end


print(string.format("OK — %d checks passaram (I/O CSV + dados reais)", n_ok))
