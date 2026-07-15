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

-- 12.9: s:iat(i) (forma method) orienta em vez de passar a Series como índice
do
    local ok, err = pcall(function() return s:iat(3) end)
    err = tostring(err)
    check(not ok,                          "12.9 s:iat(3) → erro")
    check(err:find("s.iat[i]", 1, true) ~= nil,
                                           "12.9 s:iat(3) orienta a forma correta")
    check(err:find("[1] 10", 1, true) == nil,
                                           "12.9 s:iat(3) NÃO despeja os valores da Series")
    check(err:find("<Series", 1, true) ~= nil,
                                           "12.9 s:iat(3) descreve a Series sem conteúdo")
    -- a classe toda: nenhum método de acesso vaza dados na mensagem
    local big = S.from_table({"aaa", "bbb", "ccc"}, "string")
    for _, case in ipairs({
        { "get",      function() big:get(big) end },
        { "set",      function() big:set(big, "x") end },
        { "is_null",  function() big:is_null(big) end },
        { "set_null", function() big:set_null(big) end },
    }) do
        local _, e = pcall(case[2])
        e = tostring(e)
        check(e:find("aaa", 1, true) == nil,
              "12.9 " .. case[1] .. "(Series) não vaza valores no erro")
    end
end

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

-- ===================================================================
-- 10.6 Passo (b): where/mask/ifelse delegam a select (Anel 0).
-- cond true → a, false OU NA → b (decisão 1a). int64 > 2^53 exato nos
-- dois ramos; degrau saiu. Broadcast de escalar/nil em Lua.
-- ===================================================================
do
    local ffi = require("ffi")
    local BIG = ffi.new("int64_t", 9007199254740993LL)  -- 2^53+1

    -- cond = [true, false, NA]
    local cond = S.new("bool", 3, "c"); cond:set(1, true); cond:set(2, false); cond:set_null(3)

    -- i64: BIG em ambos os ramos + valores distintos pra provar a fonte.
    -- a=[BIG,5,5]  o=[7,BIG,NA]
    local a = S.new("int64", 3, "a"); a:set(1, BIG); a:set(2, 5); a:set(3, 5)
    local o = S.new("int64", 3, "o"); o:set(1, 7); o:set(2, BIG); o:set_null(3)

    local w = a:where(cond, o)          -- true→a, false/NA→o
    check(tostring(w:get_raw(1)) == tostring(BIG), "10.6b: where true→a (2^53+1 exato)")
    check(tostring(w:get_raw(2)) == tostring(BIG), "10.6b: where false→o (2^53+1 exato)")
    check(w:is_null(3),                            "10.6b: where NA→o (nulo)")

    local m = a:mask(cond, o)           -- inverso: true→o, false/NA→a
    check(m:get(1) == 7,                "10.6b: mask true→o")
    check(m:get(2) == 5,                "10.6b: mask false→a")
    check(m:get(3) == 5,                "10.6b: mask NA→a")

    local fi = S.ifelse(cond, a, o)     -- = where(a,cond,o)
    check(tostring(fi:get_raw(1)) == tostring(BIG) and
          tostring(fi:get_raw(2)) == tostring(BIG) and fi:is_null(3),
          "10.6b: ifelse = where (a,o)")

    -- operando escalar (broadcast em Lua): false/NA → 0
    local ws = a:where(cond, 0)
    check(tostring(ws:get_raw(1)) == tostring(BIG), "10.6b: where escalar true→a")
    check(ws:get(2) == 0 and ws:get(3) == 0,        "10.6b: where escalar false/NA→0")

    -- operando nil → NA
    local wn = a:where(cond, nil)
    check(tostring(wn:get_raw(1)) == tostring(BIG), "10.6b: where nil true→a")
    check(wn:is_null(2) and wn:is_null(3),          "10.6b: where nil false/NA→NA")

    -- f64
    local fa = S.new("float64", 3); fa:set(1, 1.5); fa:set(2, 9.0); fa:set(3, 9.0)
    local fo = S.new("float64", 3); fo:set(1, 7.0); fo:set(2, 2.5); fo:set_null(3)
    local fw = fa:where(cond, fo)
    check(fw:get(1) == 1.5 and fw:get(2) == 2.5 and fw:is_null(3), "10.6b: where f64 tabela-verdade")

    -- str: \0 embutido, ambos ramos, NA→b nulo
    local sa = S.new("string", 3); sa:set(1, "abc"); sa:set(2, "z"); sa:set(3, "q")
    local sb = S.new("string", 3); sb:set(1, "x"); sb:set(2, "a\0b"); sb:set_null(3)
    local sw = sa:where(cond, sb)
    check(sw:get(1) == "abc",  "10.6b: where str true→a")
    check(sw:get(2) == "a\0b", "10.6b: where str false→b (\\0 preservado)")
    check(sw:is_null(3),       "10.6b: where str NA→b nulo")

    -- str: '' válida selecionada em ambos → len==0 nos dois lados e total==0
    -- (exercita `if (len>0)` e o ramo `total>0 ? total : INIT`).
    local ea = S.new("string", 2); ea:set(1, ""); ea:set_null(2)
    local eb = S.new("string", 2); eb:set_null(1); eb:set(2, "")
    local c2s = S.from_table({true, false}, "bool")
    local ew = ea:where(c2s, eb)   -- [ea[1]="", eb[2]=""]
    check(ew:get(1) == "" and ew:get(2) == "" and not ew:is_null(1) and not ew:is_null(2),
          "10.6b: where str '' válida len==0 / total==0")

    -- datetime (epoch_ms)
    local da = S.new("datetime", 3); da:set(1, 1000); da:set(2, 9); da:set(3, 9)
    local dob = S.new("datetime", 3); dob:set(1, 7); dob:set(2, 2000); dob:set_null(3)
    local dw = da:where(cond, dob)
    check(dw:get(1) == 1000 and dw:get(2) == 2000 and dw:is_null(3), "10.6b: where dt tabela-verdade")

    -- não-regressão: int64 <= 2^53 intacto
    local sm = S.from_table({10, 20}, "int64")
    local c2 = S.from_table({true, false}, "bool")
    check(sm:where(c2, sm):get(1) == 10,     "10.6b: where i64<=2^53 intacto")
    check(S.ifelse(c2, sm, sm):get(1) == 10, "10.6b: ifelse i64<=2^53 intacto")

    -- falha visível: operando série de dtype diferente
    local wrong = S.from_table({1.0, 2.0, 3.0}, "float64")
    check(not pcall(function() return a:where(cond, wrong) end),
          "10.6b: where dtype divergente → erro visível")
    -- falha visível: cond de tamanho diferente
    check(not pcall(function() return a:where(S.from_table({true}, "bool"), o) end),
          "10.6b: where cond tamanho errado → erro visível")
end


print(string.format("OK — %d checks passaram (Series: at/iat, where, mask, ifelse, isna/notna)", n_ok))
