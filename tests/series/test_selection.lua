-- tests/series/test_selection.lua
-- Seleção condicional (where/mask/ifelse/nlargest/nsmallest/isna/notna)
-- e acesso posicional escalar (at/iat).
-- Consolida: test_access.lua (parte Series) + seção seleção de test_enrich.lua
-- Rode da raiz: luajit tests/series/test_selection.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local Series = smaug.Series
local S      = Series
local NA     = Series.NA

local function approx(a, b) return math.abs(a - b) < 1e-9 end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end


package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")
local S  = smaug.Series
local NA = smaug.NA

local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

-- ================================================================
-- 1. Series:at / iat — acesso escalar (indexação e chamada)
-- ================================================================

local s = S.from_table({10, 20, NA, 40}, "int64")

-- indexação s.at[i]
check(s.at[1] == 10,                "at[1] = 10")
check(s.at[2] == 20,                "at[2] = 20")
check(s.at[3] == nil,               "at[3] = nil (null)")
check(s.at[4] == 40,                "at[4] = 40")

-- chamada s.at(i)
check(s.at(1) == 10,                "at(1) = 10")
check(s.iat(4) == 40,               "iat(4) = 40")

-- iat equivalente a at em Series 1-D
check(s.iat[2] == s.at[2],          "iat[2] == at[2]")

-- string e datetime
local ss = S.from_table({"x", "y"}, "string")
check(ss.at[1] == "x",              "at[1] string = x")

-- fora dos limites → erro
check(not pcall(function() return s.at[99] end),  "at[99] = erro (fora dos limites)")
check(not pcall(function() return s.at[0] end),   "at[0] = erro")
-- índice não-numérico → erro
check(not pcall(function() return s.at["x"] end), "at['x'] = erro (não-numérico)")

-- ================================================================

-- =====================================================================
-- Seleção condicional (de test_enrich.lua seção isna/where/mask/ifelse)
-- =====================================================================

-- isna / notna
local isn = S.from_table({1.0, NA, 3.0}, "float64")
check(isn:isna(2) == true,   "isna(2)=true")
check(isn:isna(1) == false,  "isna(1)=false")
check(isn:notna(1) == true,  "notna(1)=true")
check(isn:notna(2) == false, "notna(2)=false")

-- where / mask / ifelse
local sw  = S.from_table({1.0,2.0,3.0,4.0}, "float64")
local cnd = sw:gt(2)
local w   = sw:where(cnd, 0.0)
check(w:get(1) == 0.0, "where[1]=0 (falso)")
check(w:get(3) == 3.0, "where[3]=3 (verdadeiro)")
local mk  = sw:mask(cnd, 0.0)
check(mk:get(1) == 1.0, "mask[1]=1 (falso, mantém)")
check(mk:get(3) == 0.0, "mask[3]=0 (verdadeiro, substitui)")
local ife = S.ifelse(cnd, sw, S.full(4, 0.0, "float64"))
check(ife:get(1) == 0.0, "ifelse[1]=0 (falso)")
check(ife:get(4) == 4.0, "ifelse[4]=4 (verdadeiro)")

-- ================================================================

-- ================================================================
-- 7.4 — bool eq/ne (único dtype que faltava igualdade)
-- ================================================================
do
    local b = S.from_table({true, false, NA}, "bool")
    local function show(r) local o = {}; for i = 1, r:len() do o[i] = r:is_null(i) and "NA" or tostring(r:get(i)) end; return table.concat(o, ",") end

    check(show(b:eq(true)) == "true,false,NA", "7.4 bool eq(true)")
    check(show(b:eq(false)) == "false,true,NA", "7.4 bool eq(false)")
    check(show(b:ne(true)) == "false,true,NA", "7.4 bool ne(true)")
    check(b:eq(true):is_null(3), "7.4 bool eq: NA preservado (Kleene)")
    check(b:eq(true):dtype() == "bool", "7.4 bool eq retorna Series<bool>")
    -- erro de tipo orientado
    local ok = pcall(function() return b:eq(1) end)
    check(not ok, "7.4 bool eq(número) erra (espera true/false)")
end


print(string.format("OK — %d checks passaram (Series: at/iat, where, mask, ifelse, isna/notna)", n_ok))
