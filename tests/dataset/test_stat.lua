-- tests/dataset/test_stat.lua
-- DataSet: corr/cov (matriz N×N), equals, compare, duplicated, drop_duplicates,
-- reduções 5.1 (sum..sem), element-wise/transforms 5.2/5.3.
-- Consolida: seções DataSet de test_stats.lua + test_predicates.lua + test_duplicates.lua
-- Todo valor de referência abaixo foi conferido rodando contra o código real.
-- Rode da raiz: luajit tests/dataset/test_stat.lua

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
-- F.1 — DataSet:corr / DataSet:cov — matriz N×N
-- =====================================================================
do
    local ds = smaug.DataSet({
        {"a",    {1, 2, 3, 4, 5},   "float64"},
        {"b",    {2, 4, 6, 8, 10},  "float64"},   -- corr(a,b) = 1
        {"c",    {5, 4, 3, 2, 1},   "float64"},   -- corr(a,c) = -1
        {"nome", {"x","y","z","w","v"}, "string"}, -- ignorada
    })

    local cm = ds:corr()
    -- estrutura: __index__ + a,b,c = 4 colunas; 3 linhas (variáveis numéricas)
    check(cm:ncols() == 4,                "corr matriz: 4 colunas (__index__ + 3 num)")
    check(cm:nrows() == 3,                "corr matriz: 3 linhas")
    check(cm:has_column("__index__"),     "corr matriz: tem coluna __index__")
    check(not cm:has_column("nome"),      "corr matriz: coluna string ignorada")

    -- identificador de linhas
    check(cm:column("__index__"):get(1) == "a", "corr __index__[1] = a")
    check(cm:column("__index__"):get(2) == "b", "corr __index__[2] = b")
    check(cm:column("__index__"):get(3) == "c", "corr __index__[3] = c")

    -- diagonal = 1
    check(approx(cm:column("a"):get(1), 1.0), "corr[a,a] = 1")
    check(approx(cm:column("b"):get(2), 1.0), "corr[b,b] = 1")
    check(approx(cm:column("c"):get(3), 1.0), "corr[c,c] = 1")

    -- correlações conhecidas
    check(approx(cm:column("b"):get(1), 1.0),  "corr[a,b] = 1")
    check(approx(cm:column("c"):get(1), -1.0), "corr[a,c] = -1")

    -- simetria da matriz
    check(approx(cm:column("b"):get(1), cm:column("a"):get(2)), "corr matriz simétrica [a,b]=[b,a]")

    local cov = ds:cov()
    check(cov:ncols() == 4,               "cov matriz: 4 colunas")
    check(cov:nrows() == 3,               "cov matriz: 3 linhas")

    -- diagonal = variância amostral de cada coluna
    -- var amostral de {1,2,3,4,5} = 10/4 = 2.5
    check(approx(cov:column("a"):get(1), 2.5), "cov[a,a] = var amostral a = 2.5")
    -- var de {2,4,6,8,10} = 40/4 = 10
    check(approx(cov:column("b"):get(2), 10.0), "cov[b,b] = var amostral b = 10")

    -- simetria
    check(approx(cov:column("b"):get(1), cov:column("a"):get(2)), "cov matriz simétrica")

    -- sem coluna numérica → erro
    local ds_str = smaug.DataSet({{"nome", {"x", "y"}, "string"}})
    check(not pcall(function() return ds_str:corr() end), "corr sem coluna numérica = erro")
end

-- =====================================================================
-- F.2 — DataSet:equals / DataSet:compare
-- =====================================================================
do
    local d1 = smaug.DataSet({{"a", {1,2,3}, "int64"}, {"b", {"x","y","z"}, "string"}})
    local d2 = smaug.DataSet({{"a", {1,2,3}, "int64"}, {"b", {"x","y","z"}, "string"}})
    local d3 = smaug.DataSet({{"a", {1,2,9}, "int64"}, {"b", {"x","y","z"}, "string"}})

    check(d1:equals(d2) == true,          "DataSet equals idênticos")
    check(d1:equals(d3) == false,         "DataSet equals difere")

    -- colunas em ordem diferente → false
    local d4 = smaug.DataSet({{"b", {"x","y","z"}, "string"}, {"a", {1,2,3}, "int64"}})
    check(d1:equals(d4) == false,         "DataSet equals ordem diferente = false")

    -- ncols diferente
    local d5 = smaug.DataSet({{"a", {1,2,3}, "int64"}})
    check(d1:equals(d5) == false,         "DataSet equals ncols diferente")

    -- não-DataSet
    check(d1:equals(42) == false,         "DataSet equals não-DataSet = false")

    local dcmp = d1:compare(d3)
    check(dcmp:nrows() == 1,              "DataSet compare: 1 diferença")
    check(dcmp:column("linha"):get(1) == 3,   "DataSet compare linha = 3")
    check(dcmp:column("coluna"):get(1) == "a", "DataSet compare coluna = a")
    check(dcmp:column("self"):get(1) == "3",   "DataSet compare self = 3")
    check(dcmp:column("other"):get(1) == "9",  "DataSet compare other = 9")

    -- idênticos → vazio
    check(d1:compare(d2):nrows() == 0,    "DataSet compare idênticos = vazio")

    -- formas diferentes → erro
    check(not pcall(function() return d1:compare(d5) end), "DataSet compare formas diferentes = erro")
end

-- =====================================================================
-- F.6 — DataSet:duplicated / DataSet:drop_duplicates
-- =====================================================================
do
    local ds = smaug.DataSet({
        {"a", {1, 1, 2, 2, 3},          "int64"},
        {"b", {"x", "x", "y", "z", "w"}, "string"},
    })

    -- por todas as colunas: linha 2 (1,x) == linha 1
    local dsd = ds:duplicated()
    check(dsd:get(1) == false,          "DataSet dup all [1] → false")
    check(dsd:get(2) == true,           "DataSet dup all [2] = (1,x) repetida → true")
    check(dsd:get(4) == false,          "DataSet dup all [4] = (2,z) único → false")

    -- por subset "a"
    local dsa = ds:duplicated("a")
    check(dsa:get(2) == true,           "DataSet dup subset a [2]=1 → true")
    check(dsa:get(4) == true,           "DataSet dup subset a [4]=2 → true")
    check(dsa:get(5) == false,          "DataSet dup subset a [5]=3 → false")

    -- subset como lista
    local dsl = ds:duplicated({"a", "b"})
    check(dsl:get(2) == true,           "DataSet dup [a,b] [2] → true")
    check(dsl:get(3) == false,          "DataSet dup [a,b] [3] → false")

    -- keep none por "a"
    local dsn = ds:duplicated("a", "none")
    check(dsn:get(1) == true,           "DataSet dup a none [1] → true (tem cópia)")
    check(dsn:get(5) == false,          "DataSet dup a none [5]=3 único → false")

    -- coluna inexistente → erro
    check(not pcall(function() return ds:duplicated("zzz") end), "DataSet dup coluna inexistente = erro")

    -- por todas: remove linha 2
    local ddall = ds:drop_duplicates()
    check(ddall:nrows() == 4,           "DataSet drop all: 4 linhas")

    -- por subset a: mantém a=1,2,3 (primeiras)
    local dda = ds:drop_duplicates("a")
    check(dda:nrows() == 3,             "DataSet drop subset a: 3 linhas")
    check(dda:at(1, "a") == 1,          "DataSet drop a: primeira a=1")
    check(dda:at(2, "a") == 2,          "DataSet drop a: primeira a=2")
    check(dda:at(3, "a") == 3,          "DataSet drop a: a=3")

    -- keep last por a
    local ddl = ds:drop_duplicates("a", "last")
    check(ddl:nrows() == 3,             "DataSet drop a last: 3 linhas")
    check(ddl:at(1, "b") == "x",        "DataSet drop a last: última a=1 tem b=x")
end

-- =====================================================================
-- 5.1 — reduções por coluna → DataSet 1-linha
-- =====================================================================
do
    local df = smaug.DataSet({
        {"a", {10, 20, 30}, "int64"},
        {"b", {1.0, 2.0, 3.0}, "float64"},
        {"nome", {"x", "y", "z"}, "string"},
    })

    -- forma: 1 linha, só colunas numéricas, string excluída
    local r = df:sum()
    check(r:nrows() == 1, "5.1 sum: 1 linha")
    check(#r._col_names == 2 and r:has_column("a") and r:has_column("b"), "5.1 sum: só numéricas")
    check(not r:has_column("nome"), "5.1 sum: string excluída")

    -- sum preserva dtype (i64→i64, f64→f64); valores
    check(r:column("a"):get(1) == 60 and r:column("a")._dtype == "int64", "5.1 sum a=60 int64")
    check(approx(r:column("b"):get(1), 6.0) and r:column("b")._dtype == "float64", "5.1 sum b=6 float64")

    -- mean/std/var amostrais → float64
    check(approx(df:mean():column("a"):get(1), 20.0), "5.1 mean a=20")
    check(approx(df:std():column("a"):get(1), 10.0), "5.1 std a=10 (amostral)")
    check(approx(df:var():column("a"):get(1), 100.0), "5.1 var a=100 (amostral)")
    check(df:mean():column("a")._dtype == "float64", "5.1 mean dtype float64")

    -- min/max preservam dtype; median/quantile
    check(df:min():column("a"):get(1) == 10 and df:max():column("a"):get(1) == 30, "5.1 min/max")
    check(approx(df:median():column("b"):get(1), 2.0), "5.1 median b=2")
    check(approx(df:quantile(0.5):column("a"):get(1), 20.0), "5.1 quantile 0.5 a=20")

    -- count_nonnull → int64
    local cnn = df:count_nonnull()
    check(cnn:column("a"):get(1) == 3 and cnn:column("a")._dtype == "int64", "5.1 count_nonnull=3 int64")

    -- prod (int64) e regressão de prod (float64) — cobre o mesmo defeito
    -- corrigido em Series:prod (delegação C invertida no i64, idioma
    -- `and nil or` no f64); no DataSet, ignore_na é sempre true (não há
    -- parâmetro exposto — só min_count), então o caso relevante aqui é
    -- confirmar que a NA é ignorada corretamente com a implementação nova.
    check(df:prod():column("a"):get(1) == 6000, "5.1 prod a=6000 (int64)")
    local dfp_na = smaug.DataSet({{"a", {2, NA, 3}, "int64"}, {"b", {2.0, NA, 3.0}, "float64"}})
    check(dfp_na:prod():column("a"):get(1) == 6, "5.1 prod int64 ignora NA = 6")
    check(approx(dfp_na:prod():column("b"):get(1), 6.0), "5.1 prod float64 ignora NA = 6.0 (regressão)")

    -- skew/kurtosis/mad/sem: delegação pura à Series (Anel 1 não reimplementa
    -- a fórmula) — checado contra o mesmo cálculo chamado direto na coluna,
    -- não contra um valor decorado à mão.
    local dfsk = smaug.DataSet({{"a", {2, 4, 4, 4, 5, 5, 7, 9}, "float64"}})
    local col  = dfsk:column("a")
    check(approx(dfsk:skew():column("a"):get(1), col:skew()), "5.1 skew: DataSet delega à Series")
    check(approx(dfsk:kurtosis():column("a"):get(1), col:kurtosis()), "5.1 kurtosis: DataSet delega à Series")
    check(approx(dfsk:mad():column("a"):get(1), col:mad()), "5.1 mad: DataSet delega à Series")
    check(approx(dfsk:sem():column("a"):get(1), col:sem()), "5.1 sem: DataSet delega à Series")

    -- NA quando a coluna não tem dados suficientes (var de 1 não-nulo = NA amostral)
    local dfsmall = smaug.DataSet({{"a", {5, NA}, "int64"}})
    check(dfsmall:var():column("a"):is_null(1), "5.1 var de 1 não-nulo = NA (amostral)")
    check(dfsmall:sum():column("a"):get(1) == 5, "5.1 sum ignora NA")

    -- erro: nenhuma coluna numérica
    check(not pcall(function() return smaug.DataSet({{"x", {"a"}, "string"}}):sum() end),
          "5.1 erro sem coluna numérica")
    check(not pcall(function() return smaug.DataSet({{"x", {"a"}, "string"}}):skew() end),
          "5.1 skew erro sem coluna numérica")

    -- 5.5: min_count opt-in em sum e prod (DataSet)
    local dfmc = smaug.DataSet({{"a", {10, NA, NA}, "int64"}, {"b", {1, 2, 3}, "int64"}})
    check(dfmc:sum():column("a"):get(1) == 10, "5.5 sum default: NA ignorado (a=10)")
    local mc = dfmc:sum(2)
    check(mc:column("a"):is_null(1), "5.5 sum(min_count=2): a tem 1 não-nulo → NA")
    check(mc:column("b"):get(1) == 6, "5.5 sum(min_count=2): b tem 3 não-nulos → 6")

    local mcp = dfmc:prod(2)
    check(mcp:column("a"):is_null(1), "5.5 prod(min_count=2): a tem 1 não-nulo → NA")
    check(mcp:column("b"):get(1) == 6, "5.5 prod(min_count=2): b tem 3 não-nulos → 6")
end

-- =====================================================================
-- 5.2 / 5.3 — element-wise e transforms → DataSet mesma forma
-- =====================================================================
do
    local df = smaug.DataSet({{"a", {-1, 2, -3}, "int64"}, {"b", {1.5, 2.5, 3.5}, "float64"}})

    -- forma preservada
    local r = df:abs()
    check(r:nrows() == 3 and #r._col_names == 2, "5.2 abs: mesma forma")
    check(r:column("a"):get(1) == 1 and r:column("a"):get(3) == 3, "5.2 abs valores")

    -- cumsum/cummin/cummax/cumprod acumulam por coluna
    local dfc = smaug.DataSet({{"a", {3, 1, 4, 1, 5}, "int64"}, {"b", {2.0, 4.0, 1.0, 3.0, 5.0}, "float64"}})
    local cs = df:cumsum()
    check(cs:column("a"):get(3) == -2, "5.2 cumsum a[3]=-2")
    check(approx(cs:column("b"):get(3), 7.5), "5.2 cumsum b[3]=7.5")

    local cmi = dfc:cummin()
    check(cmi:column("a"):get(1) == 3 and cmi:column("a"):get(2) == 1
      and cmi:column("a"):get(5) == 1, "5.2 cummin a: 3,1,1,1,1")
    local cma = dfc:cummax()
    check(cma:column("b"):get(1) == 2.0 and cma:column("b"):get(2) == 4.0
      and cma:column("b"):get(5) == 5.0, "5.2 cummax b: 2,4,4,4,5")

    -- round / clip com argumentos
    check(df:round(0):column("b"):get(2) == 3, "5.2 round(0) b[2]=3")
    check(df:clip(0, 2):column("a"):get(1) == 0, "5.2 clip(0,2) a[1]=0")
    check(df:cumprod():column("a"):get(2) == -2, "5.2 cumprod a[2]=-2")

    -- shift desloca (NA na borda); diff
    check(df:shift(1):column("a"):is_null(1), "5.3 shift(1): a[1]=NA")
    check(df:diff():column("a"):get(2) == 3, "5.3 diff a[2]=3")

    -- D4-i: element-wise numérico erra com coluna não-numérica
    local dfs = smaug.DataSet({{"a", {1, 2}, "int64"}, {"nome", {"x", "y"}, "string"}})
    check(not pcall(function() return dfs:abs() end), "5.2 D4-i: abs erra com coluna string")
    check(not pcall(function() return dfs:cumsum() end), "5.2 D4-i: cumsum erra com coluna string")
    check(not pcall(function() return dfs:cummin() end), "5.2 D4-i: cummin erra com coluna string")
    check(not pcall(function() return dfs:cummax() end), "5.2 D4-i: cummax erra com coluna string")

    -- ffill/bfill/shift funcionam em qualquer dtype (string incluída)
    local dff = smaug.DataSet({{"s", {"a", NA, "c"}, "string"}})
    check(dff:ffill():column("s"):get(2) == "a", "5.3 ffill em string")
    check(dff:shift(1):column("s"):is_null(1), "5.3 shift em string: borda NA")

    local dfb = smaug.DataSet({{"a", {NA, 2.0, NA, 4.0}, "float64"}})
    local bf = dfb:bfill()
    check(bf:column("a"):get(1) == 2.0, "5.3 bfill a[1]=2.0 (preenche do próximo)")
    check(bf:column("a"):get(3) == 4.0, "5.3 bfill a[3]=4.0")
    local dfbs = smaug.DataSet({{"s", {NA, "y", NA}, "string"}})
    check(dfbs:bfill():column("s"):get(1) == "y", "5.3 bfill funciona em string também")

    -- isna/notna → DataSet bool, todas as colunas (qualquer dtype)
    local dfm = smaug.DataSet({{"x", {1, NA}, "int64"}, {"nome", {"a", NA}, "string"}})
    local na = dfm:isna()
    check(na:column("x")._dtype == "bool", "5.3 isna: dtype bool")
    check(na:column("x"):get(2) == true and na:column("nome"):get(2) == true, "5.3 isna: linha 2 nula")
    check(na:column("x"):get(1) == false, "5.3 isna: linha 1 não-nula")
    check(dfm:notna():column("nome"):get(1) == true, "5.3 notna: inverso de isna")

    -- astype mapa { coluna = dtype } (D4-A); coluna fora do mapa inalterada
    local at = dfm:astype({x = "float64"})
    check(at:column("x")._dtype == "float64", "5.3 astype: x → float64")
    check(at:column("nome")._dtype == "string", "5.3 astype: coluna fora do mapa inalterada")
    check(not pcall(function() return dfm:astype({zzz = "int64"}) end), "5.3 astype: erro em coluna inexistente")
    check(not pcall(function() return dfm:astype("float64") end), "5.3 astype: erro se não for mapa")
end

print(string.format("OK — %d checks passaram (DataSet: corr/cov, equals, compare, duplicated, drop_duplicates, reduções, transforms)", n_ok))
