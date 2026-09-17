-- tests/core/test_keys.lua
-- core/keys.lua: chave de igualdade/agrupamento (encode) + valor exato (value).
-- Guarda a correção do L2 (int64 > 2^53) e a preservação do baseline.
-- Rode da raiz: luajit tests/core/test_keys.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local ffi    = require("ffi")
local smaug  = require("smaug")
local keys   = require("smaug.core.keys")

local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

-- ===================================================================
-- L2: int64 acima de 2^53 gera chaves DISTINTAS (o bug era colapsarem)
-- ===================================================================
local exact_double_limit = ffi.new("int64_t", 9007199254740992LL)  -- 2^53
local above_double_limit = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1
local large_integer_series = smaug.Series({exact_double_limit, above_double_limit}, "int64")

check(keys.encode(large_integer_series, 1) ~= keys.encode(large_integer_series, 2),
      "int64 2^53 vs 2^53+1 → chaves distintas")
-- prefixo pelo dtype da série; int64 normalizado sem o sufixo LL do cdata.
check(keys.encode(large_integer_series, 1) == "int64:9007199254740992",
      "encode int64 preserva o valor exato (2^53)")
check(keys.encode(large_integer_series, 2) == "int64:9007199254740993",
      "encode int64 preserva o valor exato (2^53+1)")

-- value preserva o cdata exato (para reconstruir coluna)
check(keys.value(large_integer_series, 2) == above_double_limit, "value int64 devolve cdata exato (2^53+1)")

-- COESÃO isin: número cru (lista do usuário) bate com o cdata da série.
-- O prefixo vem do dtype, não do type() Lua — senão number 100 (lista) e
-- cdata 100 (série via get_raw) divergiriam e o isin não acharia o valor.
local hundred_integer_series = smaug.Series({ffi.new("int64_t", 100LL)}, "int64")
check(keys.encode(hundred_integer_series, 1) == keys.encode_value(100, "int64"),
      "encode(série int64) == encode_value(number, int64) — isin coeso")
check(keys.encode_value(ffi.new("int64_t", 100LL), "int64")
      == keys.encode_value(100, "int64"),
      "encode_value: cdata 100 e number 100 → mesma chave")

-- ===================================================================
-- Baseline: dtypes que já funcionavam continuam idênticos
-- ===================================================================
-- int64 pequeno
local integer_series = smaug.Series({1, 2, 1}, "int64")
check(keys.encode(integer_series, 1) == keys.encode(integer_series, 3), "int64 iguais → mesma chave")
check(keys.encode(integer_series, 1) ~= keys.encode(integer_series, 2), "int64 distintos → chaves distintas")

-- float64
local floating_point_series = smaug.Series({1.5, 2.5, 1.5}, "float64")
check(keys.encode(floating_point_series, 1) == keys.encode(floating_point_series, 3), "float iguais → mesma chave")
check(keys.encode(floating_point_series, 1) ~= keys.encode(floating_point_series, 2), "float distintos → chaves distintas")

-- string
local string_series = smaug.Series({"x", "y", "x"}, "string")
check(keys.encode(string_series, 1) == keys.encode(string_series, 3), "string iguais → mesma chave")

-- bool
local boolean_series = smaug.Series({true, false, true}, "bool")
check(keys.encode(boolean_series, 1) == keys.encode(boolean_series, 3), "bool iguais → mesma chave")
check(keys.encode(boolean_series, 1) ~= keys.encode(boolean_series, 2), "bool distintos → chaves distintas")

-- ===================================================================
-- Prefixo de tipo: 1 (int) distinto de "1" (string) — o fix do mode
-- ===================================================================
local numeric_value_series = smaug.Series({1}, "int64")
local text_value_series = smaug.Series({"1"}, "string")
check(keys.encode(numeric_value_series, 1) ~= keys.encode(text_value_series, 1),
      "int64 1 vs string '1' → chaves distintas (prefixo de tipo)")

-- ===================================================================
-- NULL → sentinela estável, distinta de qualquer valor
-- ===================================================================
local nullable_integer_series = smaug.Series({smaug.NA, 5}, "int64")
check(keys.encode(nullable_integer_series, 1) == keys.encode(nullable_integer_series, 1), "NULL → chave estável")
check(keys.encode(nullable_integer_series, 1) ~= keys.encode(nullable_integer_series, 2), "NULL distinto de valor")
check(keys.value(nullable_integer_series, 1) == nil, "value de NULL → nil")

-- dois NULLs de séries diferentes colapsam (NA = NA na chave textual;
-- a política relacional de NA-em-chave é responsabilidade do caller, não daqui)
local nullable_float_series = smaug.Series({smaug.NA}, "float64")
check(keys.encode(nullable_integer_series, 1) == keys.encode(nullable_float_series, 1), "NULL de dtypes diferentes → mesma chave sentinela")

print("OK — " .. passed_checks .. " checks passaram (core/keys: encode + value, L2 + baseline)")
