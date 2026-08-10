-- tests/series/test_stat.lua
-- Series: estatísticas descritivas (F.1), análise de distintos e
-- transformações element-wise standalone.
-- Testa métodos de lua/smaug/core/series/stats/_stat.lua e _stat_adv.lua.
-- Todo valor de referência abaixo foi conferido rodando contra o código
-- real (não deduzido de memória) — ver notas onde o comportamento não é óbvio.
-- Rode da raiz: luajit tests/series/test_stat.lua

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

-- =====================================================================
-- F.1 — Pacote estatístico (corr, cov, autocorr, dot, pct_change)
-- =====================================================================
do
    local x = Series.from_table({1.0, 2.0, 3.0, 4.0}, "float64")
    local y = Series.from_table({2.0, 4.0, 6.0, 8.0}, "float64") -- perfeito linear (y=2x)

    -- corr: correlação de Pearson ∈ [-1, 1]
    check(approx(x:corr(y), 1.0), "corr: correlação perfeita = 1.0")
    check(approx(x:corr(x), 1.0), "corr: auto-correlação = 1.0")

    -- cov: covariância amostral (divide por n-1).
    -- mean_x=2.5, mean_y=5.0; Σ(dx*dy) = 4.5+0.5+0.5+4.5 = 10.0; cov = 10/3.
    check(approx(x:cov(y), 10.0 / 3.0), "cov: covariância amostral = 10/3")

    -- autocorr: default lag=1. Verificado com valor independente (não só
    -- comparado à própria fórmula): z={1..5} é linear, então
    -- corr(z[2..5], z[1..4]) = 1.0 exatamente.
    local z = Series.from_table({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
    check(approx(z:autocorr(), 1.0), "autocorr(lag=1) de série linear = 1.0")
    check(approx(z:autocorr(), z:corr(z:shift(1))), "autocorr(lag) == corr(self, shift(lag))")

    -- dot: produto interno Σxᵢyᵢ. x·y = 1*2+2*4+3*6+4*8 = 60.
    check(x:dot(y) == 60.0, "dot: produto interno = 60")

    -- dot propaga null — qualquer par com null → nil. Mesmo tamanho de y,
    -- senão o erro de tamanho mascara o que este caso quer provar.
    local xn = Series.from_table({1.0, NA, 3.0, 4.0}, "float64")
    check(xn:dot(y) == nil, "dot: propaga null")

    -- pct_change: variação percentual = (cur - prev) / prev, prev = valor
    -- em i-periods. O DIVISOR é prev, não cur — o zero em p[3] afeta o
    -- cálculo em i=4 (onde prev=p[3]=0), não em i=3.
    local p = Series.from_table({10.0, 20.0, 0.0, 40.0}, "float64")
    local pc = p:pct_change()
    check(pc._dtype == "float64", "pct_change: dtype float64")
    check(pc:is_null(1), "pct_change[1] = NA (sem período anterior)")
    check(approx(pc:get(2), 1.0), "pct_change[2] = (20-10)/10 = 1.0")
    check(approx(pc:get(3), -1.0), "pct_change[3] = (0-20)/20 = -1.0")
    check(pc:is_null(4), "pct_change[4]: prev=p[3]=0 (divisor zero) → NA, não Inf")

    -- Erros: tamanho diferente, other não é Series, self não numérico.
    local ok1 = pcall(function() return x:corr(Series.from_table({1.0, 2.0}, "float64")) end)
    check(not ok1, "corr: tamanho diferente → erro")
    local ok2 = pcall(function() return x:corr(42) end)
    check(not ok2, "corr: other não é Series → erro")
    local sb = Series.from_table({true, false, true, false}, "bool")
    local ok3 = pcall(function() return sb:corr(x) end)
    check(not ok3, "corr: self dtype não numérico (bool) → erro")
    local ok4 = pcall(function() return xn:dot(Series.from_table({1.0, 2.0}, "float64")) end)
    check(not ok4, "dot: tamanho diferente → erro")
end

-- =====================================================================
-- Análise de distintos (unique, nunique, value_counts, mode)
-- =====================================================================
do
    local s = Series.from_table({"a", "b", "a", NA, "c", "b"}, "string")

    -- unique: ordem de primeira aparição. IMPORTANTE — ao contrário de
    -- nunique/value_counts, unique() NÃO exclui null: o null conta como
    -- uma chave distinta e entra no resultado (verificado por execução:
    -- {"a","b",NA,"c"}, 4 elementos, não 3).
    local u = s:unique()
    check(u:len() == 4, "unique: 4 valores distintos (NA inclusa)")
    check(u:get(1) == "a" and u:get(2) == "b", "unique: ordem correta (a,b,...)")
    check(u:is_null(3), "unique: NA aparece como valor distinto na posição 3")
    check(u:get(4) == "c", "unique: 'c' após a NA")

    -- nunique: conta não-nulos distintos (aqui SIM exclui null).
    check(s:nunique() == 3, "nunique: 3 valores distintos (null excluído)")

    -- value_counts: DataSet com "value" e "count", ordenado por count desc,
    -- nulos excluídos, empate resolvido por ordem de aparição.
    local vc = s:value_counts()
    check(vc:nrows() == 3, "value_counts: 3 linhas (null excluído)")
    check(vc:column("count"):get(1) == 2, "value_counts: 'a' tem count=2")
    check(vc:column("value"):get(1) == "a", "value_counts: 'a' antes de 'b' em empate (1ª aparição)")

    -- mode: mais frequente, primeiro em empate, ignora NA.
    check(s:mode() == "a", "mode: 'a' é o primeiro com frequência máxima")

    -- mode: bool não suportado
    local b = Series.from_table({true, false}, "bool")
    local ok = pcall(function() return b:mode() end)
    check(not ok, "mode: bool não suportado")
end

-- =====================================================================
-- Estatísticas (prod, median, quantile, describe)
-- =====================================================================
do
    -- prod
    local p = Series.from_table({2, 3, 4}, "int64")
    check(p:prod() == 24, "prod: int64 = 24")

    local pf = Series.from_table({2.0, 3.0, NA}, "float64")
    check(approx(pf:prod(true), 6.0), "prod: f64 com NA ignorado (default) = 6")
    -- Regressão: prod(false) com NA presente DEVE ser nil, não NaN. O bug
    -- original vinha do idioma `is_nan(result) and nil or result`, que
    -- devolvia o NaN em vez de nil quando is_nan(result) era true — corrigido
    -- para if/then explícito. Este check trava a correção.
    check(pf:prod(false) == nil, "prod: f64 com NA e ignore_na=false → nil (regressão)")

    -- median
    local m = Series.from_table({1, 2, 3, 4}, "int64")
    check(m:median() == 2.5, "median: int64 par → float64 2.5")
    local mn = Series.from_table({1, NA, 3}, "int64")
    check(mn:median() == 2.0, "median: ignora NA por padrão")
    check(mn:median(false) == nil, "median: com NA e ignore_na=false → nil")

    -- quantile
    local q = Series.from_table({1, 2, 3, 4, 5}, "int64")
    check(q:quantile(0.0) == 1, "quantile(0): mínimo")
    check(q:quantile(1.0) == 5, "quantile(1): máximo")
    check(q:quantile(0.5) == 3, "quantile(0.5): mediana ímpar")
    local qe = Series.from_table({1, 2, 3, 4}, "int64")
    check(qe:quantile(0.5) == 2.5, "quantile(0.5): mediana par")
    local ok = pcall(function() return q:quantile(1.5) end)
    check(not ok, "quantile: q>1 → erro")

    -- describe: numérico
    local d = Series.from_table({1, 2, 3, NA}, "int64"):describe()
    check(d.count == 3, "describe: count não-nulos")
    check(d.nulls == 1, "describe: nulls")
    check(d.mean == 2.0, "describe: mean")
    check(d["50%"] == 2.0, "describe: mediana")
    check(d.min == 1, "describe: min")
    check(d.max == 3, "describe: max")
end

-- =====================================================================
-- Transformações element-wise (standalone, não rolling — ver
-- series/test_window.lua para o angulo de janela sobre cum*/diff/shift)
-- =====================================================================
do
    local s = Series.from_table({-2.5, 3.7, NA}, "float64")

    -- abs
    local a = s:abs()
    check(a:get(1) == 2.5, "abs: valor absoluto")
    check(a:is_null(3), "abs: preserva NA")

    -- round: half-away-from-zero (C: ceil(v*f-0.5) p/ v<0, floor(v*f+0.5) p/
    -- v>=0). -2.5 vai PARA LONGE de zero → -3, não -2 (conferido por execução).
    local r = s:round()
    check(r:get(1) == -3, "round: half-away-from-zero (-2.5 -> -3)")
    check(r:get(2) == 4, "round: 3.7 -> 4")

    -- clip
    local c = s:clip(0, 3)
    check(c:get(1) == 0, "clip: abaixo do limite -> lo")
    check(c:get(2) == 3, "clip: acima do limite -> hi")
    check(c:is_null(3), "clip: preserva NA")
    local ok = pcall(function() return s:clip(5, 0) end)
    check(not ok, "clip: lo>hi → erro")

    -- isna / notna (por índice — assinatura escalar, não retorna Series)
    check(s:isna(3) == true, "isna: NA → true")
    check(s:notna(1) == true, "notna: não-NA → true")

    -- astype: trunca em direção a zero (não arredonda; -2.5 -> -2, não -3 —
    -- diferente de round(), conferido por execução)
    local i = s:astype("int64")
    check(i:get(1) == -2, "astype f64->i64: trunca em direção a zero")
    check(i:get(2) == 3, "astype f64->i64: 3.7 -> 3")
    check(i:is_null(3), "astype: preserva NA")
end

print(string.format("OK — %d checks passaram (Series: estatísticas F.1, análise de distintos, transformações)", n_ok))