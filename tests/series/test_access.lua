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

    -- 11.5/11.4 invariantes de display (fonte única, nenhum valor quebrado)
    local BIG = require("ffi").new("int64_t", 9007199254740993LL)  -- 2^53 + 1
    local sb  = S.new("int64", 1, "big"); sb:set(1, BIG)
    check(sb:to_string():find("9007199254740993", 1, true) ~= nil,
          "11.4 to_string: int64 > 2^53 EXATO (sem notação científica)")
    check(tostring(sb):find("9007199254740993", 1, true) ~= nil,
          "11.4 __tostring: int64 > 2^53 EXATO")
    check(sb:to_string():find("e+", 1, true) == nil,
          "11.4 to_string: sem notação científica no int64 grande")
    local sf = S.from_table({3.14159265358979}, "float64")
    check(sf:to_string():find("3.14159", 1, true) ~= nil,
          "11.5 to_string: float via %.6g")
    local sp2 = S.from_table({0/0, 1/0, -1/0}, "float64")
    local tsp = sp2:to_string()
    check(tsp:find("nan", 1, true) and tsp:find("inf", 1, true) and tsp:find("-inf", 1, true),
          "11.5 to_string: NaN/inf normalizados")
    local su = S.from_table({"José", "François"}, "string")
    local ul = {}; for line in (su:to_string().."\n"):gmatch("(.-)\n") do ul[#ul+1] = line end
    local Display = require("smaug.core.display")
    check(Display.dwidth(ul[2]) == Display.dwidth(ul[3]),
          "11.5 to_string: alinhamento UTF-8 por codepoint (José vs François)")
end

-- =====================================================================
-- 10.6 Passo B: fillna em int64 delega a coalesce_scalar (Anel 0).
-- int64 > 2^53 PRESERVADO exato (o degrau saiu; o C copia sem double).
-- =====================================================================
do
    local ffi = require("ffi")
    local BIG = ffi.new("int64_t", 9007199254740993LL)   -- 2^53 + 1
    -- nao-nulo > 2^53 preservado exato
    local s = S.new("int64", 2, "big"); s:set_null(1); s:set(2, BIG)
    local r = s:fillna(0)
    check(tostring(r:get_raw(2)) == tostring(BIG), "10.6B: fillna i64 nao-nulo 2^53+1 preservado exato")
    check(r:get(1) == 0, "10.6B: fillna i64 preenche buraco")
    -- value cdata int64 grande agora aceito (desparidade curada)
    local s2 = S.new("int64", 2, "big2"); s2:set_null(1); s2:set(2, 10)
    local r2 = s2:fillna(BIG)
    check(tostring(r2:get_raw(1)) == tostring(BIG), "10.6B: fillna value cdata int64 > 2^53 (desparidade curada)")
    -- <= 2^53 intacto
    local sp = S.new("int64", 2, "p"); sp:set_null(1); sp:set(2, 42)
    local fp = sp:fillna(7)
    check(fp:get(1) == 7 and fp:get(2) == 42, "10.6B: fillna i64 <=2^53 intacto (nao-regressao)")
    -- fracionário ainda recusa (check_value)
    check_err(function() return sp:fillna(1.5) end, "10.6B: fillna i64 fracionário recusa")
end

do
    -- 10.6B: fillna string toda-nula com value="" — buffer total 0 e len 0 por
    -- posição (cobre os ramos total==0 e len==0 do coalesce_scalar str).
    local sv = S.new("string", 2, "sv"); sv:set_null(1); sv:set_null(2)
    local rv = sv:fillna("")
    check(rv:get(1) == "" and rv:get(2) == "", "10.6B: fillna string toda-nula value='' -> vazias válidas")
    check(not rv:is_null(1) and not rv:is_null(2), "10.6B: fillna string '' resulta válido (não nulo)")
    -- mistura: buraco + string não-vazia (cobre também os ramos total>0/len>0)
    local sm = S.new("string", 2, "sm"); sm:set_null(1); sm:set(2, "abc")
    local rm = sm:fillna("")
    check(rm:get(1) == "" and rm:get(2) == "abc", "10.6B: fillna string mistura buraco/'abc'")
end


do
    -- 11.2: proxies expostos têm __tostring legível (nunca "table: 0x…")
    local function notleaky(x, tag)
        local t = tostring(x)
        check(type(t) == "string" and t:find("^table:") == nil and #t > 0, tag)
    end
    local sstr = S.from_table({"a", "b"}, "string"); sstr._name = "s"
    local sdt  = S.from_table({1000, 2000}, "datetime"); sdt._name = "t"
    local snum = S.from_table({1, 2, 3, 4}, "float64"); snum._name = "v"
    notleaky(sstr.str,          "11.2 .str proxy __tostring")
    notleaky(sdt.dt,            "11.2 .dt proxy __tostring")
    notleaky(sstr.at,           "11.2 .at proxy __tostring")
    notleaky(snum:rolling(2),   "11.2 rolling proxy __tostring")
    notleaky(snum:expanding(),  "11.2 expanding proxy __tostring")
    check(tostring(sstr.str):find(".str", 1, true) ~= nil, "11.2 .str rótulo referencia acessor")
end


do
    -- 12.12: método desconhecido erra com sugestão (falha visível > nil silencioso)
    local sx = S.from_table({1, 2, 3}, "float64")
    local function msg(fn) local _, e = pcall(fn); return tostring(e) end

    local m1 = msg(function() return sx:sumn() end)
    check(m1:find("não existe", 1, true) ~= nil, "12.12 Series: método inexistente erra")
    check(m1:find("'sum'", 1, true) ~= nil,      "12.12 Series: sugere 'sum' para 'sumn'")

    local m2 = msg(function() return sx:xyzabc() end)
    check(m2:find("não existe", 1, true) ~= nil, "12.12 Series: nome distante erra")
    check(m2:find("quis dizer", 1, true) == nil, "12.12 Series: nome distante NÃO sugere")

    -- campos internos seguem devolvendo nil (não podem erguer erro)
    check(sx._inexistente == nil,                "12.12 Series: chave _interna devolve nil")
    -- acessores e métodos reais intactos
    check(sx:mean() == 2,                        "12.12 Series: método real intacto")
    check(sx.at[1] == 1,                         "12.12 Series: acessor .at intacto")
end

-- =====================================================================
-- 10.3 fatia B — abs/round/clip desceram ao Anel 0.
--
-- Estas três CORROMPIAM EM SILÊNCIO acima de 2^53: liam por map→get()→double,
-- e abs(-9007199254740993) devolvia 9007199254740992. O degrau
-- check_int64_lossless trocou a corrupção calada por falha visível; a descida
-- trocou a falha visível por resultado certo. Com isso o degrau ficou sem
-- consumidor no projeto inteiro e foi APOSENTADO.
--
-- Elas não tinham NENHUM teste direto de Series antes do degrau — foi por isso
-- que a corrupção passou despercebida por tanto tempo.
-- =====================================================================
do
    local ffi = require("ffi")
    local BIG = ffi.new("int64_t", 9007199254740993LL)     -- 2^53 + 1
    local NEG = ffi.new("int64_t", -9007199254740993LL)

    -- 10.3.1 — o caso que era corrupção, depois erro, e agora é resultado certo
    local neg = S.new("int64", 1, "neg"); neg:set(1, NEG)
    check(neg:abs():get_raw(1) == BIG,
          "10.3.1 abs preserva int64 > 2^53 exato (era ...992 corrompido)")
    check(neg:abs()._dtype == "int64", "10.3.1 abs preserva dtype")

    local big = S.new("int64", 1, "big"); big:set(1, BIG)
    check(big:clip(NEG, BIG):get_raw(1) == BIG, "10.3.1 clip preserva exato")

    -- 10.3.2 — round em int64 preserva int64 (antes devolvia float64, que
    -- degradava > 2^53 justamente na operação que este item conserta)
    check(big:round()._dtype == "int64",       "10.3.2 round(int64) devolve int64")
    check(big:round():get_raw(1) == BIG,       "10.3.2 round(n>=0) é identidade exata")
    check(big:round(3):get_raw(1) == BIG,      "10.3.2 ndigits positivo também é identidade")

    -- 10.3.3 — ndigits < 0 faz trabalho real, em aritmética inteira
    local q = S.from_table({1234, -1567, 7}, "int64")
    check(q:round(-2):get(1) == 1200,   "10.3.3 round(1234,-2)=1200")
    check(q:round(-2):get(2) == -1600,  "10.3.3 round(-1567,-2)=-1600 (half-away-from-zero)")
    check(q:round(-3):get(1) == 1000,   "10.3.3 round(1234,-3)=1000")
    check(q:round(-1):get(3) == 10,     "10.3.3 round(7,-1)=10")

    -- 10.3.3b — o PONTO EXATO de meio caminho, que distingue half-away-from-zero
    -- de qualquer variante. Sem estes casos, trocar `>=` por `>` no desempate
    -- passa despercebido (a mutação passou até estes testes existirem).
    local h = S.from_table({1250, -1250, 1350, 50}, "int64")
    check(h:round(-2):get(1) == 1300,  "10.3.3b round(1250,-2)=1300 (meio → afasta do zero)")
    check(h:round(-2):get(2) == -1300, "10.3.3b round(-1250,-2)=-1300 (simétrico)")
    check(h:round(-2):get(3) == 1400,  "10.3.3b round(1350,-2)=1400")
    check(h:round(-2):get(4) == 100,   "10.3.3b round(50,-2)=100 (meio de zero afasta)")
    -- abaixo do meio arredonda para baixo, nos dois sinais
    local u = S.from_table({1249, -1249}, "int64")
    check(u:round(-2):get(1) == 1200,  "10.3.3b round(1249,-2)=1200")
    check(u:round(-2):get(2) == -1200, "10.3.3b round(-1249,-2)=-1200")

    -- 10.3.4 — as três decisões: casos sem resposta erram, não adivinham
    local m = S.new("int64", 1, "min")
    m:set(1, ffi.new("int64_t", -9223372036854775807LL - 1))   -- INT64_MIN
    local ok_min, e_min = pcall(function() return m:abs() end)
    check(not ok_min, "10.3.4 abs(INT64_MIN) erra (não tem contrapartida positiva)")
    check(tostring(e_min):match("INT64_MIN") ~= nil,
          "10.3.4 mensagem nomeia a causa, não só 'falhou'")

    local ok_clip, e_clip = pcall(function() return S.from_table({1,5,9},"int64"):clip(8,2) end)
    check(not ok_clip, "10.3.4 clip(lo>hi) erra (antes devolvia {8,8,2}, fora de faixa)")
    check(tostring(e_clip):match("contradit") ~= nil, "10.3.4 mensagem explica a faixa")

    check(not pcall(function() return q:round(-19) end),
          "10.3.4 round(-19) erra (fator 10^19 não cabe em int64)")

    -- 10.3.5 — caminho normal intacto nos dois dtypes
    local sm = S.from_table({-3, 2}, "int64")
    check(sm:abs():get(1) == 3,          "10.3.5 abs int64 pequeno")
    check(sm:clip(-1, 1):get(1) == -1,   "10.3.5 clip int64 pequeno")
    check(sm:clip(nil, 1):get(2) == 1,   "10.3.5 clip só com limite superior")
    check(sm:clip(-1, nil):get(1) == -1, "10.3.5 clip só com limite inferior")
    local f = S.from_table({-1.7, 2.345})
    check(f:abs():get(1) == 1.7,         "10.3.5 abs float64")
    check(f:round():get(1) == -2,        "10.3.5 round float64 half-away-from-zero")
    check(f:round(2):get(2) == 2.35,     "10.3.5 round float64 com ndigits")
    check(f:clip(-1, 1):get(1) == -1,    "10.3.5 clip float64")

    -- 10.3.6 — nulo propaga nas três, nos dois dtypes
    local wn = S.new("int64", 2, "wn"); wn:set_null(1); wn:set(2, 5)
    check(wn:abs():is_null(1),           "10.3.6 abs preserva nulo (int64)")
    check(wn:round():is_null(1),         "10.3.6 round preserva nulo (int64)")
    check(wn:clip(0, 10):is_null(1),     "10.3.6 clip preserva nulo (int64)")
    local fn = S.from_table({4.0, NA}, "float64")
    check(fn:abs():is_null(2),           "10.3.6 abs preserva nulo (f64)")

    -- 10.3.7 — série vazia e dtype não numérico
    check(S.int64(0):abs():len() == 0,   "10.3.7 série vazia não estoura")
    check(not pcall(function() return S.from_table({"a"},"string"):abs() end),
          "10.3.7 dtype não numérico recusado")
end


-- =====================================================================
-- 10.2 (fatia 1: f64+i64) — between desceu ao Anel 0.
-- Primitiva dedicada de passada única (smaug_{f64,i64}_between), com
-- inc_lo/inc_hi cobrindo os quatro modos. Em int64 a comparação é feita
-- em int64_t puro: > 2^53 passa a funcionar DE VERDADE, não só a falhar
-- visível. Os limites entram pela fronteira do escalar (9.3): cdata
-- exato aceito, number >= 2^53 recusado por origem.
-- =====================================================================
do
    local ffi = require("ffi")
    local A  = ffi.new("int64_t", 9007199254740992LL)   -- 2^53
    local B  = ffi.new("int64_t", 9007199254740993LL)   -- 2^53 + 1
    local Cc = ffi.new("int64_t", 9007199254740995LL)   -- 2^53 + 3
    local s  = S.from_table({A, B, Cc}, "int64", "big")

    -- 10.2.1 — o caso que antes era erro visível (e antes disso, silenciosamente
    -- errado): between(x, x) no próprio x. Só a linha de B pode ser true.
    local m = s:between(B, B)
    check(m:get(1) == false and m:get(2) == true and m:get(3) == false,
          "10.2.1 between exato em int64 > 2^53 (era falha visível)")

    -- 10.2.2 — os quatro modos de inclusividade, com limites nas pontas.
    local both = s:between(A, Cc)
    check(both:get(1) and both:get(2) and both:get(3),
          "10.2.2 inclusive=both inclui as duas pontas")
    local neither = s:between(A, Cc, "neither")
    check(neither:get(1) == false and neither:get(2) == true and neither:get(3) == false,
          "10.2.2 inclusive=neither exclui as duas pontas")
    local left = s:between(A, Cc, "left")
    check(left:get(1) == true and left:get(3) == false,
          "10.2.2 inclusive=left inclui só a inferior")
    local right = s:between(A, Cc, "right")
    check(right:get(1) == false and right:get(3) == true,
          "10.2.2 inclusive=right inclui só a superior")

    -- 10.2.3 — limite como number >= 2^53 é recusado (fronteira 9.3), porque
    -- já degradou na origem; o resultado sairia errado em silêncio.
    check(not pcall(function() return s:between(9007199254740993, Cc) end),
          "10.2.3 limite inferior number >= 2^53 recusado")
    check(not pcall(function() return s:between(A, 9007199254740993) end),
          "10.2.3 limite superior number >= 2^53 recusado")

    -- 10.2.4 — nulo propaga nulo; NaN em f64 é false com máscara válida.
    local wn = S.new("int64", 3, "wn")
    wn:set(1, 10); wn:set_null(2); wn:set(3, 20)
    local rn = wn:between(0, 15)
    check(rn:get(1) == true and rn:is_null(2) and rn:get(3) == false,
          "10.2.4 nulo propaga nulo")
    local fn = S.from_table({1.0, 0/0, 3.0}, "float64", "f")
    local rf = fn:between(0.5, 3.5)
    check(rf:get(1) == true and rf:get(2) == false and rf:get(3) == true,
          "10.2.4 NaN → false (não nulo), coerente com os comparadores")
    check(not rf:is_null(2), "10.2.4 NaN tem máscara válida")

    -- 10.2.5 — os quatro modos TAMBÉM em f64. Sem isto os ramos inc_lo/inc_hi
    -- falsos de smaug_f64_between nunca são exercitados (a cobertura de
    -- branch-alvo cai): cada dtype tem sua própria implementação, e testar os
    -- modos só no int64 não prova nada sobre o f64.
    local fm = S.from_table({1.0, 2.0, 3.0}, "float64", "fm")
    local fb = fm:between(1.0, 3.0)
    check(fb:get(1) and fb:get(2) and fb:get(3), "10.2.5 f64 both")
    local fnei = fm:between(1.0, 3.0, "neither")
    check(fnei:get(1) == false and fnei:get(2) == true and fnei:get(3) == false,
          "10.2.5 f64 neither")
    local fl = fm:between(1.0, 3.0, "left")
    check(fl:get(1) == true and fl:get(3) == false, "10.2.5 f64 left")
    local fr = fm:between(1.0, 3.0, "right")
    check(fr:get(1) == false and fr:get(3) == true, "10.2.5 f64 right")

    -- 10.2.6 — série vazia não estoura (nos dois dtypes).
    check(S.int64(0):between(1, 5):len() == 0, "10.2.6 série int64 vazia → len 0")
    check(S.float64(0):between(1, 5):len() == 0, "10.2.6 série f64 vazia → len 0")

    -- 10.2.7 (fatia 2) — string desceu ao Anel 0, reusando a MESMA colação dos
    -- comparadores (str_cmp_at): lexicográfica por bytes, prefixo igual
    -- desempata pela mais curta. Os quatro modos aqui também: cada dtype tem
    -- sua própria implementação, e testar os modos num não prova nada sobre o
    -- outro (lição do 10.2.5).
    local st = S.from_table({"a", "c", "e"}, "string", "s")
    local sb = st:between("a", "c")
    check(sb:get(1) and sb:get(2) and sb:get(3) == false, "10.2.7 string both")
    local sn = st:between("a", "e", "neither")
    check(sn:get(1) == false and sn:get(2) == true and sn:get(3) == false,
          "10.2.7 string neither")
    local sl = st:between("a", "e", "left")
    check(sl:get(1) == true and sl:get(3) == false, "10.2.7 string left")
    local sr = st:between("a", "e", "right")
    check(sr:get(1) == false and sr:get(3) == true, "10.2.7 string right")
    -- desempate por prefixo: "ab" está entre "a" e "b" porque "a" < "ab" < "b"
    check(S.from_table({"ab"}, "string"):between("a", "b"):get(1) == true,
          "10.2.7 string prefixo mais curta vem antes")

    -- 10.2.8 (fatia 2) — datetime, os quatro modos.
    local d = S.from_table({0, 1000, 2000}, "datetime", "d")
    check(d:between(0, 2000):get(1) and d:between(0, 2000):get(3),
          "10.2.8 datetime both inclui as pontas")
    local dn = d:between(0, 2000, "neither")
    check(dn:get(1) == false and dn:get(2) == true and dn:get(3) == false,
          "10.2.8 datetime neither")
    local dl = d:between(0, 2000, "left")
    check(dl:get(1) == true and dl:get(3) == false, "10.2.8 datetime left")
    local dr = d:between(0, 2000, "right")
    check(dr:get(1) == false and dr:get(3) == true, "10.2.8 datetime right")

    -- 10.2.9 — nulo propaga nos QUATRO dtypes (não só nos numéricos).
    check(S.from_table({"a", NA, "c"}, "string"):between("a", "z"):is_null(2),
          "10.2.9 string propaga nulo")
    check(S.from_table({0, NA, 2000}, "datetime"):between(0, 3000):is_null(2),
          "10.2.9 datetime propaga nulo")
    check(S.from_table({"a"}, "string"):between("a", "z"):len() == 1,
          "10.2.9 string série de 1 elemento")

    -- 10.2.10 — dtype sem ordem continua recusado (bool não tem cmp_between).
    check(not pcall(function() return S.from_table({true}, "bool"):between(true, true) end),
          "10.2.10 bool recusado (sem ordem)")
end


print(string.format("OK — %d checks passaram (Series: acesso, edge cases, fillna)", n_ok))
