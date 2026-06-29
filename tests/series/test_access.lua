-- tests/series/test_access.lua
-- Acesso elementar, casos degenerados (edge) e fillna.
-- Consolida: test_edge.lua + test_fillna.lua
-- Rode da raiz: luajit tests/series/test_access.lua

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

-- NOTA: marcações "PENDENTE (1.6)" indicam asserções a adicionar quando a
-- funcionalidade correspondente for implementada nesta fase. Não remover sem
-- implementar.

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug  = require("smaug")
local S      = smaug.Series

local function approx(a, b) return math.abs(a - b) < 1e-9 end
local n_ok = 0
local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end
-- Verifica que uma chamada lança erro (para casos que devem ser recusados).
local function check_err(fn, msg)
    local ok = pcall(fn)
    check(not ok, msg .. " (deveria lançar erro)")
end

-- ===================================================================
-- SÉRIE VAZIA (size 0)
-- ===================================================================
do
    local e = S.float64(0)
    check(e:len() == 0, "vazia: len 0")
    check(e:count_nonnull() == 0, "vazia: count_nonnull 0")
    -- sum de vazia = 0 (default min_count=0; alinhado com pandas)
    check(e:sum() == 0, "vazia: sum 0")
    -- PENDENTE (1.6): quando min_count existir, e:sum(nil, {min_count=1}) == nil
    -- mean/min/max/std de vazia = nil (sem valor neutro)
    check(e:mean() == nil, "vazia: mean nil")
    check(e:min() == nil, "vazia: min nil")
    check(e:max() == nil, "vazia: max nil")
    check(e:std() == nil, "vazia: std nil")
    check(e:var() == nil, "vazia: var nil")
    -- transformações em vazia devolvem vazia, sem quebrar
    check(e:clone():len() == 0, "vazia: clone vazia")
    check(e:sort():len() == 0, "vazia: sort vazia")
    check(e:head(3):len() == 0, "vazia: head vazia")
    check(e:tail(3):len() == 0, "vazia: tail vazia")
    check(e:take({}):len() == 0, "vazia: take vazio")
    -- comparação de vazia → Series<bool> vazia
    check(e:gt(0):len() == 0, "vazia: gt len 0")
    check(e:gt(0):count_true() == 0, "vazia: gt count_true 0")
    check(e:gt(0):any() == false, "vazia: any false")
    check(e:gt(0):all() == true, "vazia: all true (vacuamente)")
    -- to_table de vazia → tabela vazia
    check(#e:to_table() == 0, "vazia: to_table vazio")
end

-- ===================================================================
-- SÉRIE DE 1 ELEMENTO
-- ===================================================================
do
    local one = S.from_table({42}, "float64")
    check(one:len() == 1, "1-elem: len 1")
    check(one:sum() == 42, "1-elem: sum 42")
    check(one:mean() == 42, "1-elem: mean 42")
    check(one:min() == 42 and one:max() == 42, "1-elem: min==max==42")
    -- variância/desvio amostral (ddof=1) de 1 elemento = NA (n<2 indefinido)
    check(one:std() == nil, "1-elem: std NA (amostral, n<2)")
    check(one:var() == nil, "1-elem: var NA")
    check(one:sort():get(1) == 42, "1-elem: sort")
    check(one:clone():get(1) == 42, "1-elem: clone")
    check(one:head(5):len() == 1, "1-elem: head(5) limita a 1")
    -- view de 1 elemento
    local v = one:view(1, 1)
    check(v:len() == 1 and v:get(1) == 42, "1-elem: view")
end

-- ===================================================================
-- SÉRIE TODA-NULA
-- ===================================================================
do
    local n = S.from_table({smaug.NA, smaug.NA, smaug.NA}, "float64")
    check(n:len() == 3, "toda-nula: len 3")
    check(n:count_nonnull() == 0, "toda-nula: count_nonnull 0")
    -- sum toda-nula = 0 (default). PENDENTE (1.6): sum(min_count=1) == nil
    check(n:sum() == 0, "toda-nula: sum 0 (default)")
    check(n:mean() == nil, "toda-nula: mean nil")
    check(n:min() == nil, "toda-nula: min nil")
    check(n:max() == nil, "toda-nula: max nil")
    -- sort recusa série com nulos
    check_err(function() return n:sort() end, "toda-nula: sort recusa nulos")
    -- comparação: nulo não é > 0 → 0 trues, mas a máscara mantém os NA
    check(n:gt(0):count_true() == 0, "toda-nula: gt count_true 0")
    check(n:gt(0):is_null(1) == true, "toda-nula: gt preserva NA na máscara")
    -- todas as posições são null
    check(n:is_null(1) and n:is_null(3), "toda-nula: is_null em todas")
end

-- ===================================================================
-- SÉRIE TODA-IGUAL
-- ===================================================================
do
    local eq = S.from_table({5, 5, 5, 5}, "float64")
    check(eq:sum() == 20, "toda-igual: sum 20")
    check(eq:mean() == 5, "toda-igual: mean 5")
    check(eq:min() == 5 and eq:max() == 5, "toda-igual: min==max==5")
    -- variância/desvio de valores idênticos = 0
    check(eq:std() == 0, "toda-igual: std 0")
    check(eq:var() == 0, "toda-igual: var 0")
    -- sort de toda-igual = ela mesma
    local s = eq:sort()
    check(s:get(1) == 5 and s:get(4) == 5, "toda-igual: sort estável")
    -- gt(5) → nenhum; gt(4) → todos
    check(eq:gt(5):count_true() == 0, "toda-igual: gt(5) nenhum")
    check(eq:gt(4):count_true() == 4, "toda-igual: gt(4) todos")
    check(eq:eq(5):all() == true, "toda-igual: eq(5) all true")
end

-- ===================================================================
-- i64: paridade nos casos degenerados + sentinela
-- ===================================================================
do
    local e = S.int64(0)
    check(e:sum() == 0, "i64 vazia: sum 0")
    check(e:mean() == nil, "i64 vazia: mean nil")

    local n = S.from_table({smaug.NA, smaug.NA}, "int64")
    check(n:sum() == 0, "i64 toda-nula: sum 0 (ignore_na)")
    -- sentinela INT64_MIN deve virar nil quando ignore_na=false
    check(n:sum(false) == nil, "i64 toda-nula: sum(false) nil (sentinela→nil)")
    check(n:max() == nil, "i64 toda-nula: max nil")

    local one = S.from_table({7}, "int64")
    check(one:sum() == 7 and one:std() == nil, "i64 1-elem: sum=7, std=NA (amostral)")
end

-- ===================================================================
-- PENDENTE (1.6) — adicionar quando implementado:
--   * sum(min_count=1) em série vazia/toda-nula → nil (contrato decidido)
--   * NaN do usuário: sort/argsort devem RECUSAR (hoje só recusam null);
--     comparação com NaN → false. Ver test_special.lua (a criar).
--   * fillna: preencher nulos em vazia/toda-nula.
-- ===================================================================

-- ===================================================================
-- PROPAGAÇÃO DE NULL EM COMPARAÇÃO (série mista)
-- Comparar um nulo produz NA na máscara — nunca false.
-- ===================================================================
do
    local s = S.from_table({10, smaug.NA, 30}, "float64")
    local b = s:gt(15)              -- F, NA, T
    check(b:get(1) == false, "cmp-misto: 10>15 false")
    check(b:get(2) == nil,   "cmp-misto: NA>15 → NA (não false)")
    check(b:is_null(2) == true, "cmp-misto: posição NA marcada na máscara")
    check(b:get(3) == true,  "cmp-misto: 30>15 true")
    check(b:count_true() == 1, "cmp-misto: count_true 1 (NA não conta)")
    -- filter descarta a linha NA da máscara
    check(s:filter(b):len() == 1, "cmp-misto: filter descarta NA e false")
end

-- ===================================================================
-- dropna: remove NULLs (qualquer dtype); habilita sort em série com nulos
-- ===================================================================
do
    -- f64 com NULL intercalado
    local a = S.from_table({1, smaug.NA, 3, smaug.NA, 5}, "float64")
    local c = a:dropna()
    check(c:len() == 3, "dropna: remove os NULLs (5->3)")
    check(c:get(1) == 1 and c:get(2) == 3 and c:get(3) == 5, "dropna: mantem ordem dos validos")

    -- a mensagem "use dropna primeiro" agora e verdadeira: dropna+sort funciona
    local x = S.from_table({3, smaug.NA, 1, 2}, "int64")
    local sorted = x:dropna():sort()
    check(sorted:len() == 3 and sorted:get(1) == 1 and sorted:get(3) == 3,
          "dropna habilita sort em serie com nulos")

    -- string tambem
    local s = S.from_table({"SP", smaug.NA, "MG"}, "string")
    check(s:dropna():len() == 2, "dropna string")

    -- tudo NULL -> serie vazia (sem erro)
    local z = S.from_table({smaug.NA, smaug.NA}, "float64")
    check(z:dropna():len() == 0, "dropna tudo-NULL = serie vazia")

    -- sem NULL -> copia de mesmo tamanho
    local f = S.from_table({1, 2, 3}, "float64")
    check(f:dropna():len() == 3, "dropna sem NULL = copia igual")

    -- string vazia "" NAO e NULL: dropna a mantem
    local sv = S.from_table({"", smaug.NA, "a"}, "string")
    check(sv:dropna():len() == 2, "dropna: '' nao e NULL, e mantida")
end


-- =====================================================================
-- fillna (de test_fillna.lua)
-- =====================================================================

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


-- ================================================================
-- Item 6 — pares Series↔DataSet: dtype (6.1), sample/to_string/to_markdown (6.3)
-- ================================================================
do
    -- 6.1 dtype singular (par de DataSet:dtypes)
    check(S.from_table({1, 2}, "int64"):dtype() == "int64", "6.1 dtype int64")
    check(S.from_table({1.0}, "float64"):dtype() == "float64", "6.1 dtype float64")
    check(S.from_table({"a"}, "string"):dtype() == "string", "6.1 dtype string")

    -- 6.3 sample: n elementos, sem reposição, determinístico com seed
    local x = S.from_table({10, 20, 30, 40, 50}, "int64")
    local sm = x:sample(3, 1)
    check(sm:len() == 3, "6.3 sample: tamanho n")
    check(x:sample(3, 1):to_table()[1] == sm:to_table()[1], "6.3 sample: determinístico com seed")
    check(x:sample(99):len() == 5, "6.3 sample: n > len limita a len")

    -- 6.3 to_string / to_markdown (1 coluna, NA legível)
    local y = S.from_table({1, NA}, "int64")
    local ts = y:to_string()
    check(ts:find("NA") ~= nil, "6.3 to_string mostra NA")
    local md = y:to_markdown()
    check(md:find("|") ~= nil and md:find("%-%-") ~= nil, "6.3 to_markdown tem cabeçalho/separador")
    check(select(2, md:gsub("\n", "\n")) == 3, "6.3 to_markdown: 4 linhas (header+sep+2 dados)")
end


print(string.format("OK — %d checks passaram (Series: acesso, edge cases, fillna)", n_ok))
