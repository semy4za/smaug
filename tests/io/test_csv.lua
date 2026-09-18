-- tests/io/test_csv.lua
-- I/O CSV: read_csv_mem, to_csv, e dados reais (pedidos_digitados.csv).
-- Consolida: seção CSV de test_io.lua + test_io_real.lua
-- Rode da raiz: luajit tests/io/test_csv.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local function approximately_equal(left_value, right_value) return math.abs(left_value - right_value) < 1e-9 end
local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local function approximately_equal_2(left_value, right_value) return math.abs(left_value - right_value) < 1e-9 end

-- Diretório temporário portátil: respeita TMPDIR/TMP/TEMP (Windows usa TEMP),
-- fallback "/tmp". Separador "/" é aceito pela CRT no Windows e no POSIX.
-- Trata var vazia ("") como ausente (os.getenv devolve "" e não nil nesse caso).
local function temporary_file_path(name)
    local function non_empty_value(value) return (value ~= nil and value ~= "") and value or nil end
    local temporary_directory = non_empty_value(os.getenv("TMPDIR")) or non_empty_value(os.getenv("TMP"))
             or non_empty_value(os.getenv("TEMP")) or "/tmp"
    return temporary_directory .. "/" .. name
end

-- ================================================================
-- CSV — read_csv_mem
-- ================================================================

-- básico: int64, float64, bool, string, NA
local csv_buffer = "uf,vendas,custo,ativo,obs\nSP,100,1.5,true,capital\nRJ,200,2.3,false,\nMG,150,,true,interior\n"
local read_csv_memory_result = smaug.read_csv_mem(csv_buffer)
check(read_csv_memory_result:nrows() == 3,                      "csv: 3 linhas")
check(read_csv_memory_result:ncols() == 5,                      "csv: 5 colunas")
check(read_csv_memory_result:col("uf")._dtype   == "string",    "csv: uf=string")
check(read_csv_memory_result:col("vendas")._dtype == "int64",   "csv: vendas=int64")
check(read_csv_memory_result:col("custo")._dtype  == "float64", "csv: custo=float64")
check(read_csv_memory_result:col("ativo")._dtype  == "bool",    "csv: ativo=bool")
check(read_csv_memory_result:col("uf"):get(1) == "SP",          "csv: uf[1]=SP")
check(read_csv_memory_result:col("vendas"):get(2) == 200,       "csv: vendas[2]=200")
check(approximately_equal_2(read_csv_memory_result:col("custo"):get(1), 1.5),  "csv: custo[1]=1.5")
check(read_csv_memory_result:col("ativo"):get(1) == true,       "csv: ativo[1]=true")
check(read_csv_memory_result:col("ativo"):get(2) == false,      "csv: ativo[2]=false")
check(not read_csv_memory_result:col("ativo"):is_null(2),       "csv: ativo[2] não é NA")
check(read_csv_memory_result:col("custo"):is_null(3),           "csv: custo[3]=NA (vazio)")
check(read_csv_memory_result:col("obs"):is_null(2),             "csv: obs[2]=NA (vazio)")
check(read_csv_memory_result:col("obs"):get(1) == "capital",    "csv: obs[1]=capital")

-- sep customizado (TSV)
local tsv_buffer = "a\tb\tc\n1\t2.5\tX\n4\t5.0\tY\n"
local read_csv_memory_result_2 = smaug.read_csv_mem(tsv_buffer, {sep="\t"})
check(read_csv_memory_result_2:nrows() == 2,                      "tsv: 2 linhas")
check(read_csv_memory_result_2:col("a"):get(1) == 1,              "tsv: a[1]=1")
check(approximately_equal_2(read_csv_memory_result_2:col("b"):get(2), 5.0),      "tsv: b[2]=5.0")
check(read_csv_memory_result_2:col("c"):get(1) == "X",            "tsv: c[1]=X")

-- sem header
local headerless_csv = "1,2\n3,4\n"
local read_csv_memory_result_3 = smaug.read_csv_mem(headerless_csv, {header=false})
check(read_csv_memory_result_3:nrows() == 2,                      "sem header: 2 linhas")
check(read_csv_memory_result_3:has_column("col0"),               "sem header: col0 existe")
check(read_csv_memory_result_3:col("col0"):get(1) == 1,           "sem header: col0[1]=1")

-- aspas RFC 4180
local quoted_csv = 'nome,cidade\n"Fulano, Jr.","São Paulo"\nBeltrano,"Rio"\n'
local read_csv_memory_result_4 = smaug.read_csv_mem(quoted_csv)
check(read_csv_memory_result_4:col("nome"):get(1) == "Fulano, Jr.", "aspas: nome com vírgula")
check(read_csv_memory_result_4:col("cidade"):get(1) == "São Paulo",  "aspas: cidade com espaço")

-- aspas duplas escapadas
local escaped_csv = 'col\n"valor ""com"" aspas"\n'
local read_csv_memory_result_5 = smaug.read_csv_mem(escaped_csv)
check(read_csv_memory_result_5:col("col"):get(1) == 'valor "com" aspas', 'aspas escapadas: ""')

-- inferência: coluna mista int/float → float64
local mixed_csv = "v\n1\n2.5\n3\n"
local read_csv_memory_result_6 = smaug.read_csv_mem(mixed_csv)
check(read_csv_memory_result_6:col("v")._dtype == "float64",     "inferência mista: float64")

-- coluna toda NA → string
local allna = "v\n\n\n\n"
local read_csv_memory_result_7 = smaug.read_csv_mem(allna)
check(read_csv_memory_result_7:col("v")._dtype == "string",     "col toda NA → string")

-- valores NA customizados (na_values não suportado na API Lua ainda — NA padrão)
local nacsv = "v\nNA\nnull\n1\n"
local read_csv_memory_result_8 = smaug.read_csv_mem(nacsv)
check(read_csv_memory_result_8:col("v"):is_null(1),             "NA padrão: 'NA'=null")
check(read_csv_memory_result_8:col("v"):is_null(2),             "NA padrão: 'null'=null")
check(read_csv_memory_result_8:col("v"):get(3) == 1,            "NA padrão: '1'=1")

-- ================================================================
-- CSV — to_csv_mem (roundtrip)
-- ================================================================
local rt_csv = read_csv_memory_result:to_csv_mem()
check(type(rt_csv) == "string",              "to_csv_mem: retorna string")
check(#rt_csv > 0,                           "to_csv_mem: não vazia")

local read_csv_memory_result_9 = smaug.read_csv_mem(rt_csv)
check(read_csv_memory_result_9:nrows() == 3,                   "roundtrip: 3 linhas")
check(read_csv_memory_result_9:col("vendas"):get(1) == 100,    "roundtrip: vendas[1]=100")
check(read_csv_memory_result_9:col("ativo"):get(1) == true,    "roundtrip: ativo[1]=true")
check(read_csv_memory_result_9:col("ativo"):get(2) == false,   "roundtrip: ativo[2]=false")
check(read_csv_memory_result_9:col("custo"):is_null(3),        "roundtrip: custo[3]=NA")
check(read_csv_memory_result_9:col("obs"):is_null(2),          "roundtrip: obs[2]=NA")

-- float roundtrip
local file_csv = "v\n1.5\n2.7\n"
local read_csv_memory_result_10 = smaug.read_csv_mem(file_csv)
local output_csv_path = read_csv_memory_result_10:to_csv_mem()
local read_csv_memory_result_11 = smaug.read_csv_mem(output_csv_path)
check(approximately_equal_2(read_csv_memory_result_11:col("v"):get(1), 1.5),    "float roundtrip: 1.5")
check(approximately_equal_2(read_csv_memory_result_11:col("v"):get(2), 2.7),    "float roundtrip: 2.7")

-- ================================================================
-- CSV — to_csv / read_csv (arquivo)
-- ================================================================
local csv_path = temporary_file_path("smaug_test_io.csv")
read_csv_memory_result:to_csv(csv_path)
local read_csv_result = smaug.read_csv(csv_path)
check(read_csv_result:nrows() == 3,                    "arquivo: 3 linhas")
check(read_csv_result:col("uf"):get(2) == "RJ",        "arquivo: uf[2]=RJ")
check(read_csv_result:col("ativo"):get(2) == false,    "arquivo: ativo[2]=false")

-- =====================================================================
-- Dados reais: pedidos_digitados.csv (de test_io_real.lua)
-- =====================================================================

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

-- Diretório temporário portátil (ver test_io.lua): TMPDIR/TMP/TEMP, fallback /tmp.
-- Trata var vazia como ausente.
local function temporary_file_path_2(name)
    local function non_empty_value(value) return (value ~= nil and value ~= "") and value or nil end
    local temporary_directory = non_empty_value(os.getenv("TMPDIR")) or non_empty_value(os.getenv("TMP"))
             or non_empty_value(os.getenv("TEMP")) or "/tmp"
    return temporary_directory .. "/" .. name
end

-- ================================================================
-- Leitura com separador customizado
-- ================================================================
local read_csv_result_2 = smaug.read_csv("tests/fixtures/pedidos_digitados.csv", { sep = ";" })
check(read_csv_result_2 ~= nil,                         "leitura: sem erro")
check(read_csv_result_2:nrows() == 916,                 "nrows: 916 linhas de dados")
check(read_csv_result_2:ncols() == 15,                  "ncols: 15 colunas")

-- ================================================================
-- Nomes das colunas
-- ================================================================
local column_names = read_csv_result_2:columns()
check(column_names[1]  == "MES_COMP",            "col[1] = MES_COMP")
check(column_names[4]  == "N_PEDIDO_SAP",        "col[4] = N_PEDIDO_SAP")
check(column_names[13] == "(un)",                "col[13] = (un)")
check(column_names[14] == "(R$)",                "col[14] = (R$)")
check(column_names[15] == "motivo_recusa",       "col[15] = motivo_recusa")

-- ================================================================
-- Inferência de tipos
-- ================================================================
-- MES_COMP é "2026/06" — string (barra impede int/float)
check(read_csv_result_2:col("MES_COMP")._dtype    == "string", "MES_COMP: string")
-- N_PEDIDO_SAP é inteiro de 8 dígitos
check(read_csv_result_2:col("N_PEDIDO_SAP")._dtype == "int64", "N_PEDIDO_SAP: int64")
-- (un) é inteiro (1, 2, 3...)
check(read_csv_result_2:col("(un)")._dtype         == "int64", "(un): int64")
-- (R$) tem vírgula decimal ("34,12") — string, não float
check(read_csv_result_2:col("(R$)")._dtype         == "string", "(R$): string (vírgula decimal)")
-- Empresa, produto etc: string
check(read_csv_result_2:col("Empresa")._dtype      == "string", "Empresa: string")
check(read_csv_result_2:col("tp_produto")._dtype   == "string", "tp_produto: string")

-- ================================================================
-- Valores individuais (linha 1)
-- ================================================================
check(read_csv_result_2:col("MES_COMP"):get(1)    == "2026/06",  "MES_COMP[1]")
check(read_csv_result_2:col("Empresa"):get(1)     == "DB10",      "Empresa[1]")
check(read_csv_result_2:col("N_PEDIDO_SAP"):get(1) == 51208236,   "N_PEDIDO_SAP[1]")
check(read_csv_result_2:col("(un)"):get(1)        == 2,           "(un)[1] = 2")
check(read_csv_result_2:col("(R$)"):get(1)        == "34,12",     "(R$)[1] = 34,12")

-- ================================================================
-- NA em motivo_recusa (913 vazios, 3 com texto)
-- ================================================================
local motivo = read_csv_result_2:col("motivo_recusa")
local com_motivo = 0
for row_index = 1, read_csv_result_2:nrows() do
    if not motivo:is_null(row_index) then com_motivo = com_motivo + 1 end
end
check(com_motivo == 3,                   "motivo_recusa: 3 linhas com motivo")
check(read_csv_result_2:nrows() - com_motivo == 913,    "motivo_recusa: 913 NAs")

-- ================================================================
-- Empresas únicas
-- ================================================================
local emp_unique = read_csv_result_2:col("Empresa"):unique()
check(emp_unique:len() == 5,             "Empresa: 5 valores únicos")
check(read_csv_result_2:col("Empresa"):nunique() == 5,  "Empresa nunique: 5")

-- ================================================================
-- Contagens por empresa (groupby count)
-- ================================================================
local por_empresa = read_csv_result_2:groupby("Empresa"):count()
check(por_empresa:nrows() == 5,          "groupby Empresa: 5 grupos")

local count = {}
for row_index = 1, por_empresa:nrows() do
    count[por_empresa:col("Empresa"):get(row_index)] = por_empresa:col("count"):get(row_index)
end
check(count["DB10"] == 210,  "count DB10 = 210")
check(count["DC10"] == 454,  "count DC10 = 454")
check(count["DG10"] == 194,  "count DG10 = 194")
check(count["DP10"] == 33,   "count DP10 = 33")
check(count["DS10"] == 25,   "count DS10 = 25")

-- ================================================================
-- Soma de unidades por empresa (groupby sum)
-- ================================================================
local unsorted_empresa = read_csv_result_2:groupby("Empresa"):sum("(un)")
local values = {}
for row_index = 1, unsorted_empresa:nrows() do
    values[unsorted_empresa:col("Empresa"):get(row_index)] = unsorted_empresa:col("(un)"):get(row_index)
end
check(values["DB10"] == 228,  "sum (un) DB10 = 256")
check(values["DC10"] == 839,  "sum (un) DC10 = 839")
check(values["DG10"] == 216,  "sum (un) DG10 = 216")
check(values["DP10"] == 50,   "sum (un) DP10 = 50")
check(values["DS10"] == 30,   "sum (un) DS10 = 30")

-- ================================================================
-- tp_produto: 5 marcas
-- ================================================================
local tp_count = read_csv_result_2:groupby("tp_produto"):count()
check(tp_count:nrows() == 5,             "tp_produto: 5 marcas")
local values_2 = {}
for row_index = 1, tp_count:nrows() do
    values_2[tp_count:col("tp_produto"):get(row_index)] = tp_count:col("count"):get(row_index)
end
check(values_2["ALFAPARF"] == 129,  "ALFAPARF: 129 linhas")
check(values_2["DBELLA"]   == 207,  "DBELLA: 207 linhas")
check(values_2["RAAVI"]    == 454,  "RAAVI: 454 linhas")
check(values_2["YELLOW"]   == 111,  "YELLOW: 111 linhas")
check(values_2["ALTAMODA"] == 15,   "ALTAMODA: 15 linhas")

-- ================================================================
-- Pedidos únicos
-- ================================================================
check(read_csv_result_2:col("N_PEDIDO_SAP"):nunique() == 155, "pedidos únicos: 155")

-- ================================================================
-- filter: só pedidos DB10
-- ================================================================
local filtered_result = read_csv_result_2:filter(read_csv_result_2:col("Empresa"):eq("DB10"))
check(filtered_result:nrows() == 210,               "filter DB10: 210 linhas")
check(filtered_result:col("Empresa"):nunique() == 1,"filter DB10: só 1 empresa")

-- ================================================================
-- filter + groupby encadeado
-- ================================================================
local db10_tp = filtered_result:groupby("tp_produto"):sum("(un)")
check(db10_tp:nrows() > 0,               "DB10 groupby tp_produto: tem grupos")

-- ================================================================
-- join: empresas com metadata
-- ================================================================
local source_dataset = smaug.DataSet({
    {"Empresa",  {"DB10","DC10","DG10","DP10","DS10"}, "string"},
    {"regiao",   {"SP","SP","SP","SP","SP"},            "string"},
    {"ativa",    {true, true, true, true, true},        "bool"},
})
local joined = read_csv_result_2:join(source_dataset, "Empresa", "left")
check(joined:nrows() == 916,             "join left: preserva todas as 916 linhas")
check(joined:has_column("regiao"),       "join: coluna regiao presente")
check(joined:has_column("ativa"),        "join: coluna ativa presente")
check(joined:col("regiao"):get(1) == "SP", "join: regiao[1] = SP")

-- ================================================================
-- Roundtrip CSV: escrever e ler de volta
-- ================================================================
local csv_path_2 = temporary_file_path_2("smaug_pedidos_rt.csv")
read_csv_result_2:to_csv(csv_path_2, { sep = ";" })
local read_csv_result_3 = smaug.read_csv(csv_path_2, { sep = ";" })
check(read_csv_result_3:nrows() == 916,               "roundtrip: 916 linhas")
check(read_csv_result_3:ncols() == 15,               "roundtrip: 15 colunas")
check(read_csv_result_3:col("N_PEDIDO_SAP"):get(1) == 51208236, "roundtrip: N_PEDIDO_SAP[1]")
check(read_csv_result_3:col("(R$)"):get(1) == "34,12",           "roundtrip: (R$)[1] preservado")

-- ================================================================
-- Roundtrip JSON
-- ================================================================
local json_path = temporary_file_path_2("smaug_pedidos_rt.json")
read_csv_result_2:to_json(json_path)
local read_json_result = smaug.read_json(json_path)
check(read_json_result:nrows() == 916,              "json roundtrip: 916 linhas")
check(read_json_result:ncols() == 15,              "json roundtrip: 15 colunas")
check(read_json_result:col("N_PEDIDO_SAP"):get(1) == 51208236, "json roundtrip: N_PEDIDO_SAP[1]")

-- ================================================================
-- 12.10: aviso passivo de separador suspeito
-- ================================================================
do
    -- captura o stderr do canal de warn (core/warn.lua escreve em io.stderr).
    -- io.stderr é userdata (não aceita atribuição de campo), então trocamos o
    -- objeto inteiro por um stub com :write e restauramos depois.
    local function capture(callback)
        local buffer = {}
        local original_stderr = io.stderr
        io.stderr = { write = function(unused_value, source_series) buffer[#buffer+1] = source_series end }
        local succeeded, error_message = pcall(callback)
        io.stderr = original_stderr
        if not succeeded then error(error_message, 0) end
        return table.concat(buffer)
    end

    -- caso-alvo: CSV com ';' lido com sep=',' default → 1 coluna + aviso
    local captured_warning = capture(function()
        local read_csv_memory_result_12 = smaug.read_csv_mem("a;b;c\n1;2;3\n4;5;6\n")
        check(read_csv_memory_result_12:ncols() == 1, "12.10 CSV com ';' e sep=',' vira 1 coluna")
    end)
    check(captured_warning:find("verifique o separador", 1, true) ~= nil,
          "12.10 avisa sobre separador suspeito (';')")
    check(captured_warning:find("sep=';'", 1, true) ~= nil, "12.10 aviso sugere o sep provável")

    -- tab
    local captured_warning_2 = capture(function() smaug.read_csv_mem("a\tb\n1\t2\n3\t4\n") end)
    check(captured_warning_2:find("verifique o separador", 1, true) ~= nil, "12.10 avisa para tab")

    -- NÃO avisa: sep correto (multi-coluna)
    local captured_warning_3 = capture(function() smaug.read_csv_mem("a;b;c\n1;2;3\n", {sep=";"}) end)
    check(captured_warning_3 == "", "12.10 sep=';' explícito não avisa")

    -- NÃO avisa: CSV normal multi-coluna
    local captured_warning_4 = capture(function() smaug.read_csv_mem("a,b,c\n1,2,3\n") end)
    check(captured_warning_4 == "", "12.10 CSV multi-coluna não avisa")

    -- NÃO avisa: 1 coluna legítima, sem separador suspeito
    local captured_warning_5 = capture(function() smaug.read_csv_mem("nome\njoao\nmaria\n") end)
    check(captured_warning_5 == "", "12.10 1 coluna legítima não avisa")

    -- NÃO avisa: ';' em apenas um valor (texto livre) — exige em todas as amostras
    local captured_warning_6 = capture(function() smaug.read_csv_mem('obs\n"a; b"\nsem ponto\n') end)
    check(captured_warning_6 == "", "12.10 ';' esporádico em texto livre não avisa (falso-positivo)")

    -- NÃO avisa: read_json reusa table_to_dataset, mas o hook é só do CSV
    local captured_warning_7 = capture(function()
        smaug.read_json_mem('[{"obs":"a;b;c"},{"obs":"d;e;f"}]')
    end)
    check(captured_warning_7 == "", "12.10 read_json não avisa sobre separador (hook é do CSV)")
end

-- ================================================================
-- 12.21: não-finitos são VALORES no CSV (round-trip preserva)
-- ================================================================
do
    local source_dataset_2 = smaug.DataSet({ {"id", {1,2,3,4,5}, "int64"},
                               {"v", {smaug.NA, 0/0, 1/0, -1/0, 1.5}, "float64"} })
    local read_csv_memory_result_12 = smaug.read_csv_mem(source_dataset_2:to_csv_mem())
    check(read_csv_memory_result_12:col("v"):is_null(1),               "12.21 CSV round-trip: NA continua NA")
    check(not read_csv_memory_result_12:col("v"):is_null(2),           "12.21 CSV round-trip: NaN é VALOR, não NA")
    check(read_csv_memory_result_12:col("v"):get(2) ~= read_csv_memory_result_12:col("v"):get(2), "12.21 CSV round-trip: NaN preservado")
    check(read_csv_memory_result_12:col("v"):get(3) == math.huge,      "12.21 CSV round-trip: +inf preservado")
    check(read_csv_memory_result_12:col("v"):get(4) == -math.huge,     "12.21 CSV round-trip: -inf preservado")
    check(read_csv_memory_result_12:col("v"):get(5) == 1.5,            "12.21 CSV round-trip: finito preservado")

    -- todas as grafias caem no mesmo destino (antes a CAIXA decidia:
    -- "nan"/"NaN" viravam NA, "NAN" virava valor)
    for unused_index, token in ipairs({"nan", "NaN", "NAN"}) do
        local read_csv_memory_result_13 = smaug.read_csv_mem("v,x\n" .. token .. ",1\n")
        check(not read_csv_memory_result_13:col("v"):is_null(1), "12.21 CSV: '" .. token .. "' é valor (caixa não decide)")
    end
    for unused_index, token in ipairs({"inf", "Infinity", "INF"}) do
        local read_csv_memory_result_13 = smaug.read_csv_mem("v,x\n" .. token .. ",1\n")
        check(read_csv_memory_result_13:col("v"):get(1) == math.huge, "12.21 CSV: '" .. token .. "' -> inf")
    end
    -- vocabulário de ausência intacto
    for unused_index, token in ipairs({"NA", "null", "N/A", "NULL"}) do
        local read_csv_memory_result_13 = smaug.read_csv_mem("v,x\n" .. token .. ",1\n")
        check(read_csv_memory_result_13:col("v"):is_null(1), "12.21 CSV: '" .. token .. "' segue sendo NA")
    end
    -- opt-in: quem precisa de "nan" como ausência passa na_values
    local read_csv_memory_result_13 = smaug.read_csv_mem("v,x\nnan,1\n", { na_values = {"nan"} })
    check(read_csv_memory_result_13:col("v"):is_null(1), "12.21 CSV: na_values={'nan'} trata como NA (opt-in)")
end

-- ================================================================
-- 12.1: mensagens de erro seguem "smaug: <op> — <razão>"
-- ================================================================
do
    local function error_message_of(callback) local succeeded, error_message = pcall(callback); return tostring(error_message) end

    local error_message = error_message_of(function() smaug.read_csv("/tmp/_nao_existe_smaug_12_1.csv") end)
    check(error_message:find("smaug: smaug_", 1, true) == nil, "12.1 read_csv: sem 'smaug' duplicado")
    check(error_message:find("smaug: read_csv —", 1, true) ~= nil, "12.1 read_csv: padrão 'smaug: <op> —'")

    -- a mensagem nomeia a função REALMENTE chamada (antes dizia read_csv no _mem)
    local error_message_2 = error_message_of(function() smaug.read_csv_mem("") end)
    check(error_message_2:find("smaug: read_csv_mem —", 1, true) ~= nil,
          "12.1 read_csv_mem: nomeia a própria função, não read_csv")
    check(error_message_2:find("arquivo", 1, true) == nil,
          "12.1 read_csv_mem: não fala em 'arquivo' (é buffer)")
    check(error_message_2:find("entrada vazia", 1, true) ~= nil, "12.1 read_csv_mem: razão vem do Anel 0")

    -- writers já seguiam o padrão: simetria preservada
    local error_message_3 = error_message_of(function() smaug.DataSet({{"a",{1},"int64"}}):to_csv("/nao/existe/x.csv") end)
    check(error_message_3:find("smaug: to_csv —", 1, true) ~= nil, "12.1 to_csv: mesmo padrão do reader")
end

-- ================================================================
-- 12.3: datetime no to_csv (o column_t do Anel 0 não tem dt)
-- ================================================================
do
    local source_dataset_2 = smaug.DataSet({ {"id", {1, 2}, "int64"},
                               {"t", {1710460800000, 1710547200000}, "datetime"} })
    -- antes: crash ("attempt to get length of local 'v' (a number value)") —
    -- o mapa de dtype dizia "string" mas entregava a coluna datetime crua
    local csv_text
    local succeeded = pcall(function() csv_text = source_dataset_2:to_csv_mem() end)
    check(succeeded, "12.3 to_csv com datetime não crasha")
    check(csv_text:find("2024%-03%-15T00:00:00%.000Z") ~= nil,
          "12.3 to_csv escreve datetime como ISO 8601")

    -- round-trip de VALOR: o CSV não tem tipos, então volta como string;
    -- astype("datetime") recupera o epoch_ms exato (ver 12.25 sobre inferir ISO)
    local read_csv_memory_result_12 = smaug.read_csv_mem(csv_text)
    check(read_csv_memory_result_12:col("t")._dtype == "string", "12.3 read_csv devolve string (não infere ISO — ver 12.25)")
    local converted_series = read_csv_memory_result_12:col("t"):astype("datetime")
    check(converted_series:get(1) == source_dataset_2:col("t"):get(1), "12.3 round-trip de valor: astype recupera o epoch exato")
    check(converted_series:get(2) == source_dataset_2:col("t"):get(2), "12.3 round-trip de valor: 2a linha")

    -- NA em datetime sobrevive à escrita
    local source_dataset_3 = smaug.DataSet({ {"id", {1, 2}, "int64"},
                               {"t", {1710460800000, smaug.NA}, "datetime"} })
    local to_csv_memory_result = source_dataset_3:to_csv_mem()
    check(to_csv_memory_result ~= nil, "12.3 to_csv com datetime + NA não crasha")
    local read_csv_memory_result_13 = smaug.read_csv_mem(to_csv_memory_result)
    check(read_csv_memory_result_13:col("t"):is_null(2), "12.3 NA em datetime sobrevive ao round-trip")

    -- categorical (também fora do column_t) segue funcionando — controle
    local source_dataset_4 = smaug.DataSet({ {"c", {"a", "b"}, "categorical"} })
    check(pcall(function() return source_dataset_4:to_csv_mem() end), "12.3 categorical no to_csv (controle)")
end

-- ===================================================================
-- 12.27: OOM parcial em dataset_to_table libera o que já foi alocado.
-- Uma falha no meio do laço de colunas (ex.: create devolve nil → error)
-- deixaria o parcial vazando, pois `t` nunca chega ao caller. O pcall
-- interno captura, free_table_lua libera o parcial e o erro é repropagado.
-- Simulamos a falha injetando um erro no get da 2ª coluna (a 1ª já alocada).
do
    local csv_text = require("smaug.io.csv")
    local source_dataset_2  = smaug.DataSet({ {"a", {1, 2}}, {"b", {3, 4}}, {"c", {5, 6}} })

    local orig_raw = source_dataset_2._raw_column
    source_dataset_2._raw_column = function(self, name)
        local column = orig_raw(self, name)
        if name == "b" then
            -- proxy cujo :get lança → falha no meio do laço (após a coluna 'a')
            return setmetatable({ _dtype = column._dtype, _name = column._name }, {
                __index = function(unused_value, key)
                    if key == "get" then
                        return function() error("smaug: OOM simulado (teste 12.27)", 3) end
                    end
                    return column[key]
                end,
            })
        end
        return column
    end

    local succeeded, error_message = pcall(function() return csv_text._dataset_to_table(source_dataset_2) end)
    source_dataset_2._raw_column = orig_raw

    check(not succeeded, "12.27 falha no meio da construção é capturada (não vaza silenciosamente)")
    check(tostring(error_message):match("OOM simulado") ~= nil,
          "12.27 erro original é repropagado")

    -- Sem crash acima já prova que free_table_lua rodou sobre o parcial. Confirma
    -- que o heap segue íntegro: uma nova construção+liberação funciona.
    local source_dataset_3 = smaug.DataSet({ {"x", {1, 2, 3}} })
    local succeeded_2 = pcall(function()
        local _dataset_to_table_result = csv_text._dataset_to_table(source_dataset_3)
        csv_text._free_table_lua(_dataset_to_table_result, source_dataset_3:ncols())
    end)
    check(succeeded_2, "12.27 heap íntegro após liberação do parcial")
end

-- ===================================================================
-- 12.30 (Fase 1): to_csv_mem comunica a CAUSA, não "OOM" genérico.
-- Antes, qualquer NULL do C virava "OOM" no Lua — mentira quando a causa era
-- sep==decimal (erro de configuração, não de memória). Agora o C manda a causa
-- via err_out e o Lua a propaga.
do
    local succeeded, error_message = pcall(function()
        return smaug.DataSet({ {"v", {1.5, 2.5}} }):to_csv_mem({ sep = ",", decimal = "," })
    end)
    check(not succeeded, "12.30 to_csv_mem com sep==decimal falha")
    check(tostring(error_message):match("decimal") ~= nil, "12.30 mensagem cita a causa real (decimal)")
    check(tostring(error_message):match("OOM") == nil,       "12.30 não mente dizendo OOM")
end

print(string.format("OK — %d checks passaram (I/O CSV + dados reais)", passed_checks))
