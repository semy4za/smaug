package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")
local Series = smaug.Series

local s = Series.from_table({1609459200000}, "datetime")
local d = s:describe()

print("=== DIAGNÓSTICO describe() datetime ===")
print("d.min:", d.min)
print("type(d.min):", type(d.min))
print("#d.min (length):", d.min and #d.min)
print("d.min:byte(1,5):", d.min and string.byte(d.min, 1, 5))
print("d.min:sub(1,10):", d.min and d.min:sub(1, 10))
print("d.min:find('2021-01-01', 1, true):", d.min and d.min:find("2021-01-01", 1, true))
print("d.min:match('2021-01-01'):", d.min and d.min:match("2021-01-01"))

-- Teste direto com string literal (deveria funcionar)
local test = "2021-01-01T00:00:00.000Z"
print("\n=== TESTE LITERAL ===")
print("test:match('2021-01-01'):", test:match("2021-01-01"))