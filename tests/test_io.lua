-- tests/test_io.lua
-- Teste do Anel 3: read_csv, to_csv, read_json, to_json.
-- Rode da raiz:  luajit tests/test_io.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local NA    = smaug.Series.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
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

-- ================================================================
-- JSON — read_json_mem
-- ================================================================
local jbuf = '[{"uf":"SP","pop":12,"pib":1.5,"cap":true},{"uf":"RJ","pop":6,"pib":0.8,"cap":false},{"uf":"MG","pop":null,"pib":0.5,"cap":true}]'
local dsj = smaug.read_json_mem(jbuf)
check(dsj:nrows() == 3,                     "json: 3 linhas")
check(dsj:ncols() == 4,                     "json: 4 colunas")
check(dsj:col("uf")._dtype   == "string",   "json: uf=string")
check(dsj:col("pop")._dtype  == "int64",    "json: pop=int64")
check(dsj:col("pib")._dtype  == "float64",  "json: pib=float64")
check(dsj:col("cap")._dtype  == "bool",     "json: cap=bool")
check(dsj:col("uf"):get(1)  == "SP",        "json: uf[1]=SP")
check(dsj:col("pop"):get(2) == 6,           "json: pop[2]=6")
check(approx(dsj:col("pib"):get(1), 1.5),   "json: pib[1]=1.5")
check(dsj:col("cap"):get(1) == true,        "json: cap[1]=true")
check(dsj:col("cap"):get(2) == false,       "json: cap[2]=false")
check(dsj:col("pop"):is_null(3),            "json: pop[3]=null")

-- null em string
local jnull = '[{"s":"hello"},{"s":null},{"s":"world"}]'
local jnd = smaug.read_json_mem(jnull)
check(jnd:col("s"):get(1) == "hello",       "json null str: s[1]=hello")
check(jnd:col("s"):is_null(2),              "json null str: s[2]=null")

-- array vazio
local jempty = '[]'
local jed = smaug.read_json_mem(jempty)
check(jed:nrows() == 0,                     "json vazio: 0 linhas")

-- ================================================================
-- JSON — to_json_mem (roundtrip)
-- ================================================================
local jout = dsj:to_json_mem()
check(type(jout) == "string",               "to_json_mem: retorna string")
check(#jout > 0,                            "to_json_mem: não vazia")

local dsj2 = smaug.read_json_mem(jout)
check(dsj2:nrows() == 3,                    "json roundtrip: 3 linhas")
check(dsj2:col("uf"):get(1) == "SP",        "json roundtrip: uf[1]=SP")
check(dsj2:col("cap"):get(1) == true,       "json roundtrip: cap[1]=true")
check(dsj2:col("cap"):get(2) == false,      "json roundtrip: cap[2]=false")
check(dsj2:col("pop"):is_null(3),           "json roundtrip: pop[3]=null")

-- pretty print
local jpretty = dsj:to_json_mem({pretty=true})
check(jpretty:find("\n") ~= nil,            "json pretty: tem newlines")

-- ================================================================
-- JSON — to_json / read_json (arquivo)
-- ================================================================
local jtmp = tmp_path("smaug_test_io.json")
dsj:to_json(jtmp)
local dsj3 = smaug.read_json(jtmp)
check(dsj3:nrows() == 3,                    "json arquivo: 3 linhas")
check(dsj3:col("uf"):get(3) == "MG",        "json arquivo: uf[3]=MG")

-- ================================================================
-- Integração: read_csv → groupby → to_json
-- ================================================================
local ds_g = smaug.read_csv_mem("cat,val\nA,10\nB,20\nA,30\n")
local gb = ds_g:groupby("cat"):sum("val")
check(gb:nrows() == 2,                      "integração csv→groupby: 2 grupos")
local gb_json = gb:to_json_mem()
local gb_back = smaug.read_json_mem(gb_json)
check(gb_back:nrows() == 2,                 "integração csv→groupby→json: roundtrip")

print(string.format("OK — %d checks passaram (I/O CSV+JSON)", n_ok))
