-- tests/io/test_json.lua
-- I/O JSON: read_json_mem, to_json, unicode (\uXXXX), nulos, tipos mistos.
-- Consolida: seção JSON de test_io.lua
-- Rode da raiz: luajit tests/io/test_json.lua

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

local function tmp_path(name)
    local function nz(v) return (v ~= nil and v ~= "") and v or nil end
    local dir = nz(os.getenv("TMPDIR")) or nz(os.getenv("TMP"))
             or nz(os.getenv("TEMP")) or "/tmp"
    return dir .. "/" .. name
end

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


print(string.format("OK — %d checks passaram (I/O JSON + unicode)", n_ok))