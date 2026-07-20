-- tests/core/test_keys.lua
-- core/keys.lua: chave de igualdade/agrupamento (encode) + valor exato (value).
-- Guarda a correção do L2 (int64 > 2^53) e a preservação do baseline.
-- Rode da raiz: luajit tests/core/test_keys.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi    = require("ffi")
local smaug  = require("smaug")
local Series = smaug.Series
local NA     = Series.NA
local keys   = require("smaug.core.keys")

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- ===================================================================
-- L2: int64 acima de 2^53 gera chaves DISTINTAS (o bug era colapsarem)
-- ===================================================================
local big1 = ffi.new("int64_t", 9007199254740992LL)  -- 2^53
local big2 = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1
local s = Series.from_table({big1, big2}, "int64")

check(keys.encode(s, 1) ~= keys.encode(s, 2),
      "int64 2^53 vs 2^53+1 → chaves distintas")
-- prefixo pelo dtype da série; int64 normalizado sem o sufixo LL do cdata.
check(keys.encode(s, 1) == "int64:9007199254740992",
      "encode int64 preserva o valor exato (2^53)")
check(keys.encode(s, 2) == "int64:9007199254740993",
      "encode int64 preserva o valor exato (2^53+1)")

-- value preserva o cdata exato (para reconstruir coluna)
check(keys.value(s, 2) == big2, "value int64 devolve cdata exato (2^53+1)")

-- COESÃO isin: número cru (lista do usuário) bate com o cdata da série.
-- O prefixo vem do dtype, não do type() Lua — senão number 100 (lista) e
-- cdata 100 (série via get_raw) divergiriam e o isin não acharia o valor.
local si100 = Series.from_table({ffi.new("int64_t", 100LL)}, "int64")
check(keys.encode(si100, 1) == keys.encode_value(100, "int64"),
      "encode(série int64) == encode_value(number, int64) — isin coeso")
check(keys.encode_value(ffi.new("int64_t", 100LL), "int64")
      == keys.encode_value(100, "int64"),
      "encode_value: cdata 100 e number 100 → mesma chave")

-- ===================================================================
-- Baseline: dtypes que já funcionavam continuam idênticos
-- ===================================================================
-- int64 pequeno
local si = Series.from_table({1, 2, 1}, "int64")
check(keys.encode(si, 1) == keys.encode(si, 3), "int64 iguais → mesma chave")
check(keys.encode(si, 1) ~= keys.encode(si, 2), "int64 distintos → chaves distintas")

-- float64
local sf = Series.from_table({1.5, 2.5, 1.5}, "float64")
check(keys.encode(sf, 1) == keys.encode(sf, 3), "float iguais → mesma chave")
check(keys.encode(sf, 1) ~= keys.encode(sf, 2), "float distintos → chaves distintas")

-- string
local ss = Series.from_table({"x", "y", "x"}, "string")
check(keys.encode(ss, 1) == keys.encode(ss, 3), "string iguais → mesma chave")

-- bool
local sb = Series.from_table({true, false, true}, "bool")
check(keys.encode(sb, 1) == keys.encode(sb, 3), "bool iguais → mesma chave")
check(keys.encode(sb, 1) ~= keys.encode(sb, 2), "bool distintos → chaves distintas")

-- ===================================================================
-- Prefixo de tipo: 1 (int) distinto de "1" (string) — o fix do mode
-- ===================================================================
local snum = Series.from_table({1}, "int64")
local sstr = Series.from_table({"1"}, "string")
check(keys.encode(snum, 1) ~= keys.encode(sstr, 1),
      "int64 1 vs string '1' → chaves distintas (prefixo de tipo)")

-- ===================================================================
-- NULL → sentinela estável, distinta de qualquer valor
-- ===================================================================
local sn = Series.from_table({NA, 5}, "int64")
check(keys.encode(sn, 1) == keys.encode(sn, 1), "NULL → chave estável")
check(keys.encode(sn, 1) ~= keys.encode(sn, 2), "NULL distinto de valor")
check(keys.value(sn, 1) == nil, "value de NULL → nil")

-- dois NULLs de séries diferentes colapsam (NA = NA na chave textual;
-- a política relacional de NA-em-chave é responsabilidade do caller, não daqui)
local sn2 = Series.from_table({NA}, "float64")
check(keys.encode(sn, 1) == keys.encode(sn2, 1), "NULL de dtypes diferentes → mesma chave sentinela")

print("OK — " .. n_ok .. " checks passaram (core/keys: encode + value, L2 + baseline)")
