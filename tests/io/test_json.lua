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


-- ================================================================
-- 12.21: não-finitos no JSON — null + aviso (RFC 8259 não os comporta)
-- ================================================================
do
    local function capture(fn)
        local buf = {}
        local real = io.stderr
        io.stderr = { write = function(_, s) buf[#buf+1] = s end }
        local ok, err = pcall(fn)
        io.stderr = real
        if not ok then error(err, 0) end
        return table.concat(buf)
    end

    local df = smaug.DataSet({ {"id", {1,2,3,4,5}, "int64"},
                               {"v", {NA, 0/0, 1/0, -1/0, 1.5}, "float64"} })
    local js
    local w = capture(function() js = df:to_json_mem() end)

    -- writer: todos os não-finitos viram null (JSON válido)
    check(js:find("inf", 1, true) == nil,  "12.21 to_json: sem literal 'inf'")
    check(js:find("nan", 1, true) == nil,  "12.21 to_json: sem literal 'nan'")
    check(js:find("null", 1, true) ~= nil, "12.21 to_json: não-finitos viraram null")

    -- round-trip: o Smaug lê o que o Smaug escreve (antes falhava!)
    local back = smaug.read_json_mem(js)
    check(back:nrows() == 5,                  "12.21 read_json do próprio output: 5 linhas")
    check(back:col("v"):is_null(2),           "12.21 round-trip: NaN virou null")
    check(back:col("v"):is_null(3),           "12.21 round-trip: inf virou null")
    check(back:col("v"):get(5) == 1.5,        "12.21 round-trip: finito preservado")

    -- aviso: a perda é real, então é visível (não silenciosa)
    check(w:find("não%-finito"), "12.21 to_json avisa sobre não-finitos")
    check(w:find("3 valor", 1, true) ~= nil, "12.21 aviso conta os 3 (NaN, inf, -inf; NA não conta)")
    check(w:find("null", 1, true) ~= nil,    "12.21 aviso diz que viraram null")

    -- sem não-finitos: silêncio
    local df2 = smaug.DataSet({ {"v", {1.5, 2.5}, "float64"} })
    local w2 = capture(function() df2:to_json_mem() end)
    check(w2 == "", "12.21 to_json sem não-finitos não avisa")

    -- NA sozinho não dispara aviso (ausência não é não-finito)
    local df3 = smaug.DataSet({ {"v", {NA, 1.5}, "float64"} })
    local w3 = capture(function() df3:to_json_mem() end)
    check(w3 == "", "12.21 NA puro não dispara aviso")
end


-- ================================================================
-- 12.1: mensagens de erro seguem "smaug: <op> — <razão>"
-- ================================================================
do
    local function msg(fn) local _, e = pcall(fn); return tostring(e) end

    local m1 = msg(function() smaug.read_json("/tmp/_nao_existe_smaug_12_1.json") end)
    check(m1:find("smaug: smaug_", 1, true) == nil, "12.1 read_json: sem 'smaug' duplicado")
    check(m1:find("smaug: read_json —", 1, true) ~= nil, "12.1 read_json: padrão 'smaug: <op> —'")

    local m2 = msg(function() smaug.read_json_mem("xyz") end)
    check(m2:find("smaug: read_json_mem —", 1, true) ~= nil,
          "12.1 read_json_mem: nomeia a própria função")

    local m3 = msg(function() smaug.DataSet({{"a",{1},"int64"}}):to_json("/nao/existe/x.json") end)
    check(m3:find("smaug: to_json —", 1, true) ~= nil, "12.1 to_json: mesmo padrão do reader")
end


print(string.format("OK — %d checks passaram (I/O JSON + unicode)", n_ok))