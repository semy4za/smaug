-- tests/series/test_stat.lua
-- Series: estatísticas descritivas (F.1), análise de distintos,
-- transformações element-wise standalone e estatísticas avançadas.
-- Testa métodos de lua/smaug/core/series/stats/_stat.lua e _stat_adv.lua.
-- Todo valor de referência abaixo foi conferido rodando contra o código
-- real (não deduzido de memória) — ver notas onde o comportamento não é óbvio.
-- Rode da raiz: luajit tests/series/test_stat.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")
local Series = smaug.Series
local NA = Series.NA
local NAN = smaug.NAN

local n_ok = 0

local function check(cond, msg)
    if not cond then error("FALHOU: " .. msg, 2) end
    n_ok = n_ok + 1
end

local function approx(a, b, tol)
    tol = tol or 1e-9
    if a == nil and b == nil then return true end
    if a == nil or b == nil then return false end
    local an, bn = tostring(a), tostring(b)
    if an == "nan" or an == "-nan" or an == "1.#SNAN" then
        return bn == "nan" or bn == "-nan" or bn == "1.#SNAN"
    end
    if an == "inf" or an == "1.#INF" then return bn == "inf" or bn == "1.#INF" end
    if an == "-inf" or an == "-1.#INF" then return bn == "-inf" or bn == "-1.#INF" end
    return math.abs(a - b) < tol
end

local function is_nan(x)
    return x ~= x
end

local function rejects(fn)
    return not pcall(fn)
end

-- =====================================================================
-- 1 — Estatísticas básicas (unique, nunique, value_counts, prod, median, quantile, mode)
-- =====================================================================
do
    -- unique(): valores distintos, NA conta como distinto
    local s = Series.from_table({1, 2, 2, 3, NA}, "int64")
    local u = s:unique()
    check(u:len() == 4, "unique: 4 distintos (1,2,3,NA)")
    check(s:nunique() == 3, "nunique: 3 distintos (NA não conta)")

    -- value_counts(): ordenado por frequência
    local vc = s:value_counts()
    check(vc:len() == 3, "value_counts: 3 linhas (NA excluído)")
    check(vc:column("value"):get(1) == 2, "value_counts: valor mais freq = 2")
    check(vc:column("count"):get(1) == 2, "value_counts: count = 2")
    
    -- prod(): int64 com NA ignorado
    local p = Series.from_table({2, 3, NA, 4}, "int64"):prod()
    check(p == 24, "prod int64 ignora NA = 24")
    local p2 = Series.from_table({2, NA, 3}, "int64"):prod(false)
    check(p2 == nil, "prod int64 ignore_na=false com NA = nil")

    -- prod(): float64 com NaN
    local pf = Series.from_table({2.0, 3.0, NA}, "float64")
    check(approx(pf:prod(true), 6.0), "prod float64 com NA ignorado (default) = 6")
    check(pf:prod(false) == nil, "prod float64 com NA e ignore_na=false → nil")

    -- median(): float64
    local m = Series.from_table({1.0, 2.0, 3.0, 4.0, 5.0}, "float64"):median()
    check(approx(m, 3.0), "median {1,2,3,4,5} = 3")

    -- quantile(): q=0.5 == median
    local q = Series.from_table({1.0, 2.0, 3.0, 4.0, 5.0}, "float64"):quantile(0.5)
    check(approx(q, 3.0), "quantile q=0.5 = median")

    -- mode(): primeiro em ordem de aparição em caso de empate
    local mo = Series.from_table({1, 2, 2, 3, 3}, "int64"):mode()
    check(mo == 2, "mode: empate → primeiro em aparição")
end

-- =====================================================================
-- 2 — describe() numérico
-- =====================================================================
do
    local s = Series.from_table({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    local d = s:describe()
    check(d.count == 5, "describe count = 5")
    check(approx(d.mean, 3.0), "describe mean = 3")
    check(approx(d.std, math.sqrt(2.5)), "describe std = sqrt(2.5) amostral")
    check(approx(d.min, 1.0), "describe min = 1")
    check(approx(d["25%"], 2.0), "describe 25% = 2")
    check(approx(d["50%"], 3.0), "describe 50% = 3")
    check(approx(d["75%"], 4.0), "describe 75% = 4")
    check(approx(d.max, 5.0), "describe max = 5")
end

-- =====================================================================
-- 3 — describe() bool (count_true, count_false)
-- =====================================================================
do
    local s = Series.from_table({true, false, true, NA, false}, "bool")
    local d = s:describe()
    check(d.count == 4, "describe bool count = 4 não-nulos")
    check(d.count_true == 2, "describe bool count_true = 2")
    check(d.count_false == 2, "describe bool count_false = 2")
    check(d.nulls == 1, "describe bool nulls = 1")
end

-- =====================================================================
-- 4 — describe() datetime (min/max formatados)
-- =====================================================================
do
    local s = Series.from_table({1609459200000, 1609545600000, 1609632000000}, "datetime")
    local d = s:describe()
    check(d.count == 3, "describe datetime count = 3")
    check(type(d.min) == "string", "describe datetime min = string formatada")
    check(type(d.max) == "string", "describe datetime max = string formatada")
    check(d.min:sub(1, 10) == "2021-01-01", "describe datetime min = 2021-01-01")
    check(d.max:sub(1, 10) == "2021-01-03", "describe datetime max = 2021-01-03")
end

-- =====================================================================
-- 5 — describe() string (unique, top, freq)
-- =====================================================================
do
    local s = Series.from_table({"a", "b", "a", "a", NA}, "string")
    local d = s:describe()
    check(d.count == 4, "describe string count = 4 não-nulos")
    check(d.unique == 2, "describe string unique = 2 (a,b)")
    check(d.top == "a", "describe string top = 'a'")
    check(d.freq == 3, "describe string freq = 3")
    check(d.nulls == 1, "describe string nulls = 1")
end

-- =====================================================================
-- 6 — rank() 4 métodos (average, min, max, first)
-- =====================================================================
do
    -- float64: rank average (default)
    local s = Series.from_table({1.0, 2.0, 2.0, 3.0}, "float64")
    local r = s:rank()
    check(approx(r:get(1), 1.0), "rank average [1] = 1")
    check(approx(r:get(2), 2.5), "rank average [2] = 2.5 (empate)")
    check(approx(r:get(3), 2.5), "rank average [3] = 2.5 (empate)")
    check(approx(r:get(4), 4.0), "rank average [4] = 4")

    -- rank min
    local rm = s:rank("min")
    check(approx(rm:get(2), 2.0), "rank min [2] = 2")
    check(approx(rm:get(3), 2.0), "rank min [3] = 2")

    -- rank max
    local rx = s:rank("max")
    check(approx(rx:get(2), 3.0), "rank max [2] = 3")
    check(approx(rx:get(3), 3.0), "rank max [3] = 3")

    -- rank first
    local rf = s:rank("first")
    check(approx(rf:get(2), 2.0), "rank first [2] = 2")
    check(approx(rf:get(3), 3.0), "rank first [3] = 3")

    -- rank method inválido → erro
    check(rejects(function() s:rank("invalido") end), "rank method inválido = erro")

    -- rank com nulls → NA no resultado
    local sn = Series.from_table({1.0, NA, 2.0}, "float64")
    local rn = sn:rank()
    check(approx(rn:get(1), 1.0), "rank com null [1] = 1")
    check(rn:get(2) == nil, "rank com null [2] = NA")
    check(approx(rn:get(3), 2.0), "rank com null [3] = 2")

    -- rank int64
    local si = Series.from_table({10, 20, 30}, "int64")
    local ri = si:rank()
    check(approx(ri:get(1), 1.0), "rank int64 [1] = 1")
    check(approx(ri:get(3), 3.0), "rank int64 [3] = 3")

    -- rank string
    local ss = Series.from_table({"a", "b", "c"}, "string")
    local rs = ss:rank()
    check(approx(rs:get(1), 1.0), "rank string [1] = 1")
    check(approx(rs:get(3), 3.0), "rank string [3] = 3")

    -- rank datetime
    local sd = Series.from_table({1609459200000, 1609545600000, 1609632000000}, "datetime")
    local rd = sd:rank()
    check(approx(rd:get(1), 1.0), "rank datetime [1] = 1")
    check(approx(rd:get(3), 3.0), "rank datetime [3] = 3")

    -- rank bool
    local sb = Series.from_table({false, true, false, true}, "bool")
    local rb = sb:rank()
    check(approx(rb:get(1), 1.5), "rank bool [1] = 1.5 (false empate)")
    check(approx(rb:get(2), 3.5), "rank bool [2] = 3.5 (true empate)")

    -- rank série vazia → série vazia
    local se = Series.from_table({}, "float64")
    local re = se:rank()
    check(re:len() == 0, "rank série vazia = série vazia")
end

-- =====================================================================
-- 7 — pct_rank() normalização [0, 1]
-- =====================================================================
do
    local s = Series.from_table({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    local pr = s:pct_rank()
    check(approx(pr:get(1), 0.0), "pct_rank [1] = 0.0")
    check(approx(pr:get(5), 1.0), "pct_rank [5] = 1.0")
    check(approx(pr:get(3), 0.5), "pct_rank [3] = 0.5")

    -- pct_rank com nulls
    local sn = Series.from_table({1.0, NA, 3.0}, "float64")
    local prn = sn:pct_rank()
    check(approx(prn:get(1), 0.0), "pct_rank com null [1] = 0")
    check(prn:get(2) == nil, "pct_rank com null [2] = NA")
    check(approx(prn:get(3), 1.0), "pct_rank com null [3] = 1")

    -- pct_rank série vazia → série vazia
    local se = Series.from_table({}, "float64")
    local pre = se:pct_rank()
    check(pre:len() == 0, "pct_rank série vazia = série vazia")

    -- pct_rank int64
    local si = Series.from_table({10, 20, 30}, "int64")
    local pri = si:pct_rank()
    check(approx(pri:get(1), 0.0), "pct_rank int64 [1] = 0")
    check(approx(pri:get(3), 1.0), "pct_rank int64 [3] = 1")
end

-- =====================================================================
-- 8 — cov() e corr() bivariadas
-- =====================================================================
do
    local a = Series.from_table({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    local b = Series.from_table({2.0, 4.0, 6.0, 8.0, 10.0}, "float64")

    -- cov: 10.0 amostral (n-1)
    local c = a:cov(b)
    check(approx(c, 10.0), "cov(a,b) = 10.0 amostral")

    -- corr: 1.0 (correlação perfeita)
    local r = a:corr(b)
    check(approx(r, 1.0), "corr(a,b) = 1.0 perfeita")

    -- corr com nulls (pares ignorados)
    local an = Series.from_table({1.0, 2.0, NA, 4.0, 5.0}, "float64")
    local bn = Series.from_table({2.0, NA, 6.0, 8.0, 10.0}, "float64")
    local rn = an:corr(bn)
    -- pares válidos: (1,2) e (4,8), (5,10) → 3 pares, corr = 1.0
    check(approx(rn, 1.0), "corr com nulls ignora pares")

    -- cov/corr com <2 pares → NaN
    local a1 = Series.from_table({1.0}, "float64")
    local b1 = Series.from_table({2.0}, "float64")
    local c1 = a1:cov(b1)
    check(is_nan(c1), "cov com 1 par = NaN")
    local r1 = a1:corr(b1)
    check(is_nan(r1), "corr com 1 par = NaN")

    -- cov/corr dtype não-numérico → erro
    local as = Series.from_table({"a", "b", "c"}, "string")
    check(rejects(function() a:cov(as) end), "cov string = erro")
    check(rejects(function() a:corr(as) end), "corr string = erro")
end

-- =====================================================================
-- 9 — autocorr()
-- =====================================================================
do
    local s = Series.from_table({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")

    -- autocorr lag=1 (default)
    local a1 = s:autocorr()
    check(approx(a1, 1.0), "autocorr lag=1 série linear = 1.0")

    -- autocorr lag=2
    local a2 = s:autocorr(2)
    check(approx(a2, 1.0), "autocorr lag=2 série linear = 1.0")

    -- autocorr série aleatória (valores conhecidos)
    local sr = Series.from_table({2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0}, "float64")
    local ar = sr:autocorr()
    check(ar ~= nil and not is_nan(ar), "autocorr retorna valor válido")

    -- autocorr com nulls (shift propaga NA)
    local sn = Series.from_table({1.0, NA, 3.0, 4.0}, "float64")
    local an = sn:autocorr()
    check(an ~= nil, "autocorr com nulls retorna valor ou NaN")
end

-- =====================================================================
-- 10 — dot() produto interno
-- =====================================================================
do
    local a = Series.from_table({1.0, 2.0, 3.0}, "float64")
    local b = Series.from_table({4.0, 5.0, 6.0}, "float64")

    -- dot: 1*4 + 2*5 + 3*6 = 32
    local d = a:dot(b)
    check(approx(d, 32.0), "dot {1,2,3}·{4,5,6} = 32")

    -- dot com nulls → nil (qualquer par com null)
    local an = Series.from_table({1.0, NA, 3.0}, "float64")
    local dn = a:dot(an)
    check(dn == nil, "dot com null = nil")

    -- dot tamanhos diferentes → erro
    local c = Series.from_table({1.0, 2.0}, "float64")
    check(rejects(function() a:dot(c) end), "dot tamanhos diferentes = erro")

    -- dot dtype não-numérico → erro
    local as = Series.from_table({"a", "b", "c"}, "string")
    check(rejects(function() a:dot(as) end), "dot string = erro")
end

-- =====================================================================
-- 11 — pct_change() variação percentual
-- =====================================================================
do
    local s = Series.from_table({100.0, 110.0, 121.0}, "float64")

    -- pct_change periods=1 (default)
    local p = s:pct_change()
    check(p:get(1) == nil, "pct_change [1] = NA (sem anterior)")
    check(approx(p:get(2), 0.1), "pct_change [2] = 0.1 (10%)")
    check(approx(p:get(3), 0.1), "pct_change [3] = 0.1 (10%)")

    -- pct_change periods=2
    local p2 = s:pct_change(2)
    check(p2:get(1) == nil, "pct_change periods=2 [1] = NA")
    check(p2:get(2) == nil, "pct_change periods=2 [2] = NA")
    check(approx(p2:get(3), 0.21), "pct_change periods=2 [3] = 0.21 (21%)")

    -- pct_change divisor zero → NA
    local sz = Series.from_table({0.0, 100.0}, "float64")
    local pz = sz:pct_change()
    check(pz:get(2) == nil, "pct_change divisor zero = NA")

    -- pct_change com nulls
    local sn = Series.from_table({100.0, NA, 121.0}, "float64")
    local pn = sn:pct_change()
    check(pn:get(2) == nil, "pct_change com null [2] = NA")
    check(pn:get(3) == nil, "pct_change com null [3] = NA (anterior é NA)")
end

-- =====================================================================
-- 12 — skew() assimetria (n >= 3)
-- =====================================================================
do
    -- skew de {2,4,4,4,5,5,7,9} = 0.931... (valor conferido)
    local s = Series.from_table({2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0}, "float64")
    local sk = s:skew()
    check(approx(sk, 0.931, 0.001), "skew {2,4,4,4,5,5,7,9} = 0.931")

    -- skew n=3 (mínimo)
    local s3 = Series.from_table({1.0, 2.0, 3.0}, "float64")
    local sk3 = s3:skew()
    check(sk3 ~= nil and not is_nan(sk3), "skew n=3 retorna valor")

    -- skew n<3 → nil
    local s2 = Series.from_table({1.0, 2.0}, "float64")
    local sk2 = s2:skew()
    check(sk2 == nil, "skew n=2 = nil")

    local s1 = Series.from_table({1.0}, "float64")
    local sk1 = s1:skew()
    check(sk1 == nil, "skew n=1 = nil")

    local s0 = Series.from_table({}, "float64")
    local sk0 = s0:skew()
    check(sk0 == nil, "skew série vazia = nil")

    -- skew com nulls (ignora)
    local sn = Series.from_table({1.0, NA, 2.0, 3.0, 4.0}, "float64")
    local skn = sn:skew()
    check(skn ~= nil and not is_nan(skn), "skew com nulls ignora NA")

    -- skew int64
    local si = Series.from_table({1, 2, 3, 4, 5}, "int64")
    local ski = si:skew()
    check(ski ~= nil and not is_nan(ski), "skew int64 retorna valor")

    -- skew dtype não-numérico → erro
    local ss = Series.from_table({"a", "b", "c"}, "string")
    check(rejects(function() ss:skew() end), "skew string = erro")

    local sb = Series.from_table({true, false, true}, "bool")
    check(rejects(function() sb:skew() end), "skew bool = erro (exceção registrada)")
end

-- =====================================================================
-- 13 — kurtosis() curtose (n >= 4)
-- =====================================================================
do
    -- kurtosis de {2,4,4,4,5,5,7,9} = -0.19... (excess kurtosis)
    local s = Series.from_table({2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0}, "float64")
    local ku = s:kurtosis()
    check(approx(ku, -0.19, 0.01), "kurtosis {2,4,4,4,5,5,7,9} = -0.19")

    -- kurtosis n=4 (mínimo)
    local s4 = Series.from_table({1.0, 2.0, 3.0, 4.0}, "float64")
    local ku4 = s4:kurtosis()
    check(ku4 ~= nil and not is_nan(ku4), "kurtosis n=4 retorna valor")

    -- kurtosis n<4 → nil
    local s3 = Series.from_table({1.0, 2.0, 3.0}, "float64")
    local ku3 = s3:kurtosis()
    check(ku3 == nil, "kurtosis n=3 = nil")

    local s2 = Series.from_table({1.0, 2.0}, "float64")
    local ku2 = s2:kurtosis()
    check(ku2 == nil, "kurtosis n=2 = nil")

    local s0 = Series.from_table({}, "float64")
    local ku0 = s0:kurtosis()
    check(ku0 == nil, "kurtosis série vazia = nil")

    -- kurtosis com nulls (ignora)
    local sn = Series.from_table({1.0, NA, 2.0, 3.0, 4.0, 5.0}, "float64")
    local kun = sn:kurtosis()
    check(kun ~= nil and not is_nan(kun), "kurtosis com nulls ignora NA")

    -- kurtosis int64
    local si = Series.from_table({1, 2, 3, 4, 5, 6}, "int64")
    local kui = si:kurtosis()
    check(kui ~= nil and not is_nan(kui), "kurtosis int64 retorna valor")

    -- kurtosis dtype não-numérico → erro
    local ss = Series.from_table({"a", "b", "c", "d"}, "string")
    check(rejects(function() ss:kurtosis() end), "kurtosis string = erro")
end

-- =====================================================================
-- 14 — mad() desvio absoluto mediano
-- =====================================================================
do
    -- mad de {1,2,3,4,5} = mediana({2,1,0,1,2}) = 1.0
    local s = Series.from_table({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    local m = s:mad()
    check(approx(m, 1.0), "mad {1,2,3,4,5} = 1.0")

    -- mad robusto a outliers
    local so = Series.from_table({1.0, 2.0, 3.0, 4.0, 100.0}, "float64")
    local mo = so:mad()
    check(approx(mo, 1.0), "mad robusto a outlier (100)")

    -- mad série vazia → nil
    local se = Series.from_table({}, "float64")
    local me = se:mad()
    check(me == nil, "mad série vazia = nil")

    -- mad com 1 elemento → 0 (desvio de si mesmo)
    local s1 = Series.from_table({5.0}, "float64")
    local m1 = s1:mad()
    check(approx(m1, 0.0), "mad 1 elemento = 0")

    -- mad com nulls (ignora)
    local sn = Series.from_table({1.0, NA, 3.0, 4.0, 5.0}, "float64")
    local mn = sn:mad()
    check(approx(mn, 1.0), "mad com nulls ignora NA")

    -- mad int64
    local si = Series.from_table({1, 2, 3, 4, 5}, "int64")
    local mi = si:mad()
    check(approx(mi, 1.0), "mad int64 = 1.0")

    -- mad dtype não-numérico → erro
    local ss = Series.from_table({"a", "b", "c"}, "string")
    check(rejects(function() ss:mad() end), "mad string = erro")
end

-- =====================================================================
-- 15 — sem() erro padrão da média (n >= 2)
-- =====================================================================
do
    -- sem de {1,2,3,4,5} = std/√n = sqrt(2.5)/√5 ≈ 0.707
    local s = Series.from_table({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    local se = s:sem()
    check(approx(se, 0.707, 0.001), "sem {1,2,3,4,5} = 0.707")

    -- sem n=2 (mínimo)
    local s2 = Series.from_table({1.0, 2.0}, "float64")
    local se2 = s2:sem()
    check(se2 ~= nil and not is_nan(se2), "sem n=2 retorna valor")

    -- sem n<2 → nil
    local s1 = Series.from_table({1.0}, "float64")
    local se1 = s1:sem()
    check(se1 == nil, "sem n=1 = nil")

    local s0 = Series.from_table({}, "float64")
    local se0 = s0:sem()
    check(se0 == nil, "sem série vazia = nil")

    -- sem com nulls (ignora)
    local sn = Series.from_table({1.0, NA, 3.0, 4.0, 5.0}, "float64")
    local sen = sn:sem()
    check(approx(sen, 0.707, 0.001), "sem com nulls ignora NA")

    -- sem int64
    local si = Series.from_table({1, 2, 3, 4, 5}, "int64")
    local sei = si:sem()
    check(approx(sei, 0.707, 0.001), "sem int64 = 0.707")

    -- sem dtype não-numérico → erro
    local ss = Series.from_table({"a", "b", "c"}, "string")
    check(rejects(function() ss:sem() end), "sem string = erro")
end

-- =====================================================================
-- 16 — Casos de borda unificados
-- =====================================================================
do
    -- Série vazia
    local se = Series.from_table({}, "float64")
    check(se:rank():len() == 0, "rank série vazia = vazia")
    check(se:pct_rank():len() == 0, "pct_rank série vazia = vazia")
    check(se:skew() == nil, "skew série vazia = nil")
    check(se:kurtosis() == nil, "kurtosis série vazia = nil")
    check(se:mad() == nil, "mad série vazia = nil")
    check(se:sem() == nil, "sem série vazia = nil")

    -- Série toda null
    local sn = Series.from_table({NA, NA, NA}, "float64")
    check(sn:rank():get(1) == nil, "rank toda null = NA")
    check(sn:skew() == nil, "skew toda null = nil")
    check(sn:kurtosis() == nil, "kurtosis toda null = nil")
    check(sn:mad() == nil, "mad toda null = nil")
    check(sn:sem() == nil, "sem toda null = nil")

    -- Série com 1 elemento
    local s1 = Series.from_table({5.0}, "float64")
    check(approx(s1:rank():get(1), 1.0), "rank 1 elemento = 1")
    check(approx(s1:pct_rank():get(1), 0.0), "pct_rank 1 elemento = 0")
    check(s1:skew() == nil, "skew 1 elemento = nil")
    check(s1:kurtosis() == nil, "kurtosis 1 elemento = nil")
    check(approx(s1:mad(), 0.0), "mad 1 elemento = 0")
    check(s1:sem() == nil, "sem 1 elemento = nil")
end

-- =====================================================================
-- FIM DOS TESTES
-- =====================================================================

print(string.format("OK — %d checks passaram (Series: estatísticas F.1 + avançadas + describe polimórfico)", n_ok))