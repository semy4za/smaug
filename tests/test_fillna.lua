-- tests/test_fillna.lua
-- fillna (Fase 1.6). Preenche NULLs; deixa NaN intacto (NaN é valor, não null).
-- Contrato (Roadmap): nova Series; sem argumento = erro; sem coerção de tipo
-- (1.5 em i64 = erro); DataSet:fillna(v) em todas as colunas ou {col=v} por coluna.
-- Rode da raiz:  luajit tests/test_fillna.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local S     = smaug.Series
local D     = smaug.DataSet

local nan = 0/0
local function is_nan(x) return x ~= x end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
local function check_err(fn, msg)
    local ok = pcall(fn)
    check(not ok, msg .. " (deveria lançar erro)")
end

-- ===================================================================
-- Series:fillna — preenche null, devolve NOVA series
-- ===================================================================
do
    local s = S.from_table({1.0, smaug.NA, 3.0, smaug.NA}, "float64")
    local f = s:fillna(0)
    -- nova series, original intacta
    check(s:is_null(2) == true, "fillna: original não muda (imutável)")
    check(f:is_null(2) == false, "fillna: null preenchido na nova")
    check(f:get(2) == 0, "fillna: valor preenchido = 0")
    check(f:get(4) == 0, "fillna: segundo null preenchido")
    -- não-nulos inalterados
    check(f:get(1) == 1.0 and f:get(3) == 3.0, "fillna: não-nulos intactos")
    check(f:count_nonnull() == 4, "fillna: todos não-nulos após preencher")
    check(f:len() == s:len(), "fillna: mesmo comprimento")
end

-- ===================================================================
-- fillna preenche NULL mas deixa NaN intacto (contrato NaN ≠ null)
-- ===================================================================
do
    local s = S.float64(3)
    s:set(1, nil)    -- null
    s:set(2, nan)    -- NaN (valor)
    s:set(3, 5.0)    -- normal
    local f = s:fillna(99)
    check(f:get(1) == 99, "fillna: null → 99")
    check(is_nan(f:get(2)), "fillna: NaN permanece NaN (não é null, não preenche)")
    check(f:get(3) == 5.0, "fillna: valor normal intacto")
    check(f:is_null(2) == false, "fillna: posição NaN não era null")
end

-- ===================================================================
-- sem argumento → erro; sem coerção de tipo → erro
-- ===================================================================
do
    local s = S.from_table({1.0, smaug.NA}, "float64")
    check_err(function() return s:fillna() end, "fillna: sem argumento")
    check_err(function() return s:fillna(nil) end, "fillna: argumento nil")

    -- i64: preencher com não-inteiro é erro (sem coerção)
    local si = S.from_table({1, smaug.NA, 3}, "int64")
    check_err(function() return si:fillna(1.5) end, "fillna: i64 recusa 1.5 (sem coerção)")
    -- i64 com inteiro funciona
    local fi = si:fillna(0)
    check(fi:get(2) == 0, "fillna: i64 preenche com inteiro")
    check(fi:count_nonnull() == 3, "fillna: i64 todos preenchidos")
end

-- ===================================================================
-- casos degenerados
-- ===================================================================
do
    -- série sem nulos: fillna devolve cópia equivalente
    local s = S.from_table({1.0, 2.0}, "float64")
    local f = s:fillna(0)
    check(f:get(1) == 1.0 and f:get(2) == 2.0, "fillna: sem nulos = cópia igual")
    -- série vazia: fillna não quebra
    local e = S.float64(0)
    check(e:fillna(0):len() == 0, "fillna: vazia ok")
    -- série toda-nula: tudo vira o valor
    local n = S.from_table({smaug.NA, smaug.NA}, "float64")
    local fn = n:fillna(7)
    check(fn:get(1) == 7 and fn:get(2) == 7, "fillna: toda-nula → tudo 7")
    check(fn:count_nonnull() == 2, "fillna: toda-nula preenchida")
end

-- ===================================================================
-- DataSet:fillna
-- ===================================================================
do
    local df = D.from_columns({
        {"a", {1.0, smaug.NA, 3.0}, "float64"},
        {"b", {smaug.NA, 20.0, 30.0}, "float64"},
    })
    -- fillna(valor) → todas as colunas
    local f = df:fillna(0)
    check(f:column("a"):get(2) == 0, "DS fillna: col a preenchida")
    check(f:column("b"):get(1) == 0, "DS fillna: col b preenchida")
    -- original intacto
    check(df:column("a"):is_null(2) == true, "DS fillna: original intacto")

    -- fillna({col=valor}) → por coluna; coluna omitida mantém nulos
    local f2 = df:fillna({a = -1})
    check(f2:column("a"):get(2) == -1, "DS fillna map: col a = -1")
    check(f2:column("b"):is_null(1) == true, "DS fillna map: col b omitida mantém null")
end

print(string.format("OK — %d checks passaram (fillna)", n_ok))
