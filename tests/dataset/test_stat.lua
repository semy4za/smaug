-- tests/dataset/test_stat.lua
-- DataSet: corr/cov (matriz N×N), equals, compare, duplicated, drop_duplicates,
-- reduções 5.1 (sum..sem), element-wise/transforms 5.2/5.3.
-- Consolida: seções DataSet de test_stats.lua + test_predicates.lua + test_duplicates.lua
-- Todo valor de referência abaixo foi conferido rodando contra o código real.
-- Rode da raiz: luajit tests/dataset/test_stat.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local function approximately_equal(left_value, right_value) return math.abs(left_value - right_value) < 1e-9 end
local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

-- =====================================================================
-- F.1 — DataSet:corr / DataSet:cov — matriz N×N
-- =====================================================================
do
    local source_dataset = smaug.DataSet({
        {"a",    {1, 2, 3, 4, 5},   "float64"},
        {"b",    {2, 4, 6, 8, 10},  "float64"},   -- corr(a,b) = 1
        {"c",    {5, 4, 3, 2, 1},   "float64"},   -- corr(a,c) = -1
        {"nome", {"x","y","z","w","v"}, "string"}, -- ignorada
    })

    local correlation_result = source_dataset:corr()
    -- estrutura: __index__ + a,b,c = 4 colunas; 3 linhas (variáveis numéricas)
    check(correlation_result:ncols() == 4,                "corr matriz: 4 colunas (__index__ + 3 num)")
    check(correlation_result:nrows() == 3,                "corr matriz: 3 linhas")
    check(correlation_result:has_column("__index__"),     "corr matriz: tem coluna __index__")
    check(not correlation_result:has_column("nome"),      "corr matriz: coluna string ignorada")

    -- identificador de linhas
    check(correlation_result:column("__index__"):get(1) == "a", "corr __index__[1] = a")
    check(correlation_result:column("__index__"):get(2) == "b", "corr __index__[2] = b")
    check(correlation_result:column("__index__"):get(3) == "c", "corr __index__[3] = c")

    -- diagonal = 1
    check(approximately_equal(correlation_result:column("a"):get(1), 1.0), "corr[a,a] = 1")
    check(approximately_equal(correlation_result:column("b"):get(2), 1.0), "corr[b,b] = 1")
    check(approximately_equal(correlation_result:column("c"):get(3), 1.0), "corr[c,c] = 1")

    -- correlações conhecidas
    check(approximately_equal(correlation_result:column("b"):get(1), 1.0),  "corr[a,b] = 1")
    check(approximately_equal(correlation_result:column("c"):get(1), -1.0), "corr[a,c] = -1")

    -- simetria da matriz
    check(approximately_equal(correlation_result:column("b"):get(1), correlation_result:column("a"):get(2)), "corr matriz simétrica [a,b]=[b,a]")

    local covariance_result = source_dataset:cov()
    check(covariance_result:ncols() == 4,               "cov matriz: 4 colunas")
    check(covariance_result:nrows() == 3,               "cov matriz: 3 linhas")

    -- diagonal = variância amostral de cada coluna
    -- var amostral de {1,2,3,4,5} = 10/4 = 2.5
    check(approximately_equal(covariance_result:column("a"):get(1), 2.5), "cov[a,a] = var amostral a = 2.5")
    -- var de {2,4,6,8,10} = 40/4 = 10
    check(approximately_equal(covariance_result:column("b"):get(2), 10.0), "cov[b,b] = var amostral b = 10")

    -- simetria
    check(approximately_equal(covariance_result:column("b"):get(1), covariance_result:column("a"):get(2)), "cov matriz simétrica")

    -- sem coluna numérica → erro
    local source_dataset_2 = smaug.DataSet({{"nome", {"x", "y"}, "string"}})
    check(not pcall(function() return source_dataset_2:corr() end), "corr sem coluna numérica = erro")
end

-- =====================================================================
-- F.2 — DataSet:equals / DataSet:compare
-- =====================================================================
do
    local source_dataset = smaug.DataSet({{"a", {1,2,3}, "int64"}, {"b", {"x","y","z"}, "string"}})
    local source_dataset_2 = smaug.DataSet({{"a", {1,2,3}, "int64"}, {"b", {"x","y","z"}, "string"}})
    local source_dataset_3 = smaug.DataSet({{"a", {1,2,9}, "int64"}, {"b", {"x","y","z"}, "string"}})

    check(source_dataset:equals(source_dataset_2) == true,          "DataSet equals idênticos")
    check(source_dataset:equals(source_dataset_3) == false,         "DataSet equals difere")

    -- colunas em ordem diferente → false
    local source_dataset_4 = smaug.DataSet({{"b", {"x","y","z"}, "string"}, {"a", {1,2,3}, "int64"}})
    check(source_dataset:equals(source_dataset_4) == false,         "DataSet equals ordem diferente = false")

    -- ncols diferente
    local source_dataset_5 = smaug.DataSet({{"a", {1,2,3}, "int64"}})
    check(source_dataset:equals(source_dataset_5) == false,         "DataSet equals ncols diferente")

    -- não-DataSet
    check(source_dataset:equals(42) == false,         "DataSet equals não-DataSet = false")

    local comparison_dataset = source_dataset:compare(source_dataset_3)
    check(comparison_dataset:nrows() == 1,              "DataSet compare: 1 diferença")
    check(comparison_dataset:column("linha"):get(1) == 3,   "DataSet compare linha = 3")
    check(comparison_dataset:column("coluna"):get(1) == "a", "DataSet compare coluna = a")
    check(comparison_dataset:column("self"):get(1) == "3",   "DataSet compare self = 3")
    check(comparison_dataset:column("other"):get(1) == "9",  "DataSet compare other = 9")

    -- idênticos → vazio
    check(source_dataset:compare(source_dataset_2):nrows() == 0,    "DataSet compare idênticos = vazio")

    -- formas diferentes → erro
    check(not pcall(function() return source_dataset:compare(source_dataset_5) end), "DataSet compare formas diferentes = erro")
end

-- =====================================================================
-- F.6 — DataSet:duplicated / DataSet:drop_duplicates
-- =====================================================================
do
    local source_dataset = smaug.DataSet({
        {"a", {1, 1, 2, 2, 3},          "int64"},
        {"b", {"x", "x", "y", "z", "w"}, "string"},
    })

    -- por todas as colunas: linha 2 (1,x) == linha 1
    local duplicate_mask = source_dataset:duplicated()
    check(duplicate_mask:get(1) == false,          "DataSet dup all [1] → false")
    check(duplicate_mask:get(2) == true,           "DataSet dup all [2] = (1,x) repetida → true")
    check(duplicate_mask:get(4) == false,          "DataSet dup all [4] = (2,z) único → false")

    -- por subset "a"
    local duplicate_mask_2 = source_dataset:duplicated("a")
    check(duplicate_mask_2:get(2) == true,           "DataSet dup subset a [2]=1 → true")
    check(duplicate_mask_2:get(4) == true,           "DataSet dup subset a [4]=2 → true")
    check(duplicate_mask_2:get(5) == false,          "DataSet dup subset a [5]=3 → false")

    -- subset como lista
    local duplicate_mask_3 = source_dataset:duplicated({"a", "b"})
    check(duplicate_mask_3:get(2) == true,           "DataSet dup [a,b] [2] → true")
    check(duplicate_mask_3:get(3) == false,          "DataSet dup [a,b] [3] → false")

    -- keep none por "a"
    local duplicate_mask_4 = source_dataset:duplicated("a", "none")
    check(duplicate_mask_4:get(1) == true,           "DataSet dup a none [1] → true (tem cópia)")
    check(duplicate_mask_4:get(5) == false,          "DataSet dup a none [5]=3 único → false")

    -- coluna inexistente → erro
    check(not pcall(function() return source_dataset:duplicated("zzz") end), "DataSet dup coluna inexistente = erro")

    -- por todas: remove linha 2
    local ddall = source_dataset:drop_duplicates()
    check(ddall:nrows() == 4,           "DataSet drop all: 4 linhas")

    -- por subset a: mantém a=1,2,3 (primeiras)
    local deduplicated_result = source_dataset:drop_duplicates("a")
    check(deduplicated_result:nrows() == 3,             "DataSet drop subset a: 3 linhas")
    check(deduplicated_result:at(1, "a") == 1,          "DataSet drop a: primeira a=1")
    check(deduplicated_result:at(2, "a") == 2,          "DataSet drop a: primeira a=2")
    check(deduplicated_result:at(3, "a") == 3,          "DataSet drop a: a=3")

    -- keep last por a
    local deduplicated_result_2 = source_dataset:drop_duplicates("a", "last")
    check(deduplicated_result_2:nrows() == 3,             "DataSet drop a last: 3 linhas")
    check(deduplicated_result_2:at(1, "b") == "x",        "DataSet drop a last: última a=1 tem b=x")
end

-- =====================================================================
-- 5.1 — reduções por coluna → DataSet 1-linha
-- =====================================================================
do
    local source_dataset = smaug.DataSet({
        {"a", {10, 20, 30}, "int64"},
        {"b", {1.0, 2.0, 3.0}, "float64"},
        {"nome", {"x", "y", "z"}, "string"},
    })

    -- forma: 1 linha, só colunas numéricas, string excluída
    local sum_result = source_dataset:sum()
    check(sum_result:nrows() == 1, "5.1 sum: 1 linha")
    check(#sum_result._col_names == 2 and sum_result:has_column("a") and sum_result:has_column("b"), "5.1 sum: só numéricas")
    check(not sum_result:has_column("nome"), "5.1 sum: string excluída")

    -- sum preserva dtype (i64→i64, f64→f64); valores
    check(sum_result:column("a"):get(1) == 60 and sum_result:column("a")._dtype == "int64", "5.1 sum a=60 int64")
    check(approximately_equal(sum_result:column("b"):get(1), 6.0) and sum_result:column("b")._dtype == "float64", "5.1 sum b=6 float64")

    -- mean/std/var amostrais → float64
    check(approximately_equal(source_dataset:mean():column("a"):get(1), 20.0), "5.1 mean a=20")
    check(approximately_equal(source_dataset:std():column("a"):get(1), 10.0), "5.1 std a=10 (amostral)")
    check(approximately_equal(source_dataset:var():column("a"):get(1), 100.0), "5.1 var a=100 (amostral)")
    check(source_dataset:mean():column("a")._dtype == "float64", "5.1 mean dtype float64")

    -- min/max preservam dtype; median/quantile
    check(source_dataset:min():column("a"):get(1) == 10 and source_dataset:max():column("a"):get(1) == 30, "5.1 min/max")
    check(approximately_equal(source_dataset:median():column("b"):get(1), 2.0), "5.1 median b=2")
    check(approximately_equal(source_dataset:quantile(0.5):column("a"):get(1), 20.0), "5.1 quantile 0.5 a=20")

    -- count_nonnull → int64
    local count_non_null_result = source_dataset:count_nonnull()
    check(count_non_null_result:column("a"):get(1) == 3 and count_non_null_result:column("a")._dtype == "int64", "5.1 count_nonnull=3 int64")

    -- prod (int64) e regressão de prod (float64) — cobre o mesmo defeito
    -- corrigido em Series:prod (delegação C invertida no i64, idioma
    -- `and nil or` no f64); no DataSet, ignore_na é sempre true (não há
    -- parâmetro exposto — só min_count), então o caso relevante aqui é
    -- confirmar que a NA é ignorada corretamente com a implementação nova.
    check(source_dataset:prod():column("a"):get(1) == 6000, "5.1 prod a=6000 (int64)")
    local dfp_null = smaug.DataSet({{"a", {2, smaug.NA, 3}, "int64"}, {"b", {2.0, smaug.NA, 3.0}, "float64"}})
    check(dfp_null:prod():column("a"):get(1) == 6, "5.1 prod int64 ignora NA = 6")
    check(approximately_equal(dfp_null:prod():column("b"):get(1), 6.0), "5.1 prod float64 ignora NA = 6.0 (regressão)")

    -- skew/kurtosis/mad/sem: delegação pura à Series (Anel 1 não reimplementa
    -- a fórmula) — checado contra o mesmo cálculo chamado direto na coluna,
    -- não contra um valor decorado à mão.
    local source_dataset_2 = smaug.DataSet({{"a", {2, 4, 4, 4, 5, 5, 7, 9}, "float64"}})
    local column  = source_dataset_2:column("a")
    check(approximately_equal(source_dataset_2:skew():column("a"):get(1), column:skew()), "5.1 skew: DataSet delega à Series")
    check(approximately_equal(source_dataset_2:kurtosis():column("a"):get(1), column:kurtosis()), "5.1 kurtosis: DataSet delega à Series")
    check(approximately_equal(source_dataset_2:mad():column("a"):get(1), column:mad()), "5.1 mad: DataSet delega à Series")
    check(approximately_equal(source_dataset_2:sem():column("a"):get(1), column:sem()), "5.1 sem: DataSet delega à Series")

    -- NA quando a coluna não tem dados suficientes (var de 1 não-nulo = NA amostral)
    local dfsmall = smaug.DataSet({{"a", {5, smaug.NA}, "int64"}})
    check(dfsmall:var():column("a"):is_null(1), "5.1 var de 1 não-nulo = NA (amostral)")
    check(dfsmall:sum():column("a"):get(1) == 5, "5.1 sum ignora NA")

    -- erro: nenhuma coluna numérica
    check(not pcall(function() return smaug.DataSet({{"x", {"a"}, "string"}}):sum() end),
          "5.1 erro sem coluna numérica")
    check(not pcall(function() return smaug.DataSet({{"x", {"a"}, "string"}}):skew() end),
          "5.1 skew erro sem coluna numérica")

    -- 5.5: min_count opt-in em sum e prod (DataSet)
    local source_dataset_3 = smaug.DataSet({{"a", {10, smaug.NA, smaug.NA}, "int64"}, {"b", {1, 2, 3}, "int64"}})
    check(source_dataset_3:sum():column("a"):get(1) == 10, "5.5 sum default: NA ignorado (a=10)")
    local sum_result_2 = source_dataset_3:sum(2)
    check(sum_result_2:column("a"):is_null(1), "5.5 sum(min_count=2): a tem 1 não-nulo → NA")
    check(sum_result_2:column("b"):get(1) == 6, "5.5 sum(min_count=2): b tem 3 não-nulos → 6")

    local product_result = source_dataset_3:prod(2)
    check(product_result:column("a"):is_null(1), "5.5 prod(min_count=2): a tem 1 não-nulo → NA")
    check(product_result:column("b"):get(1) == 6, "5.5 prod(min_count=2): b tem 3 não-nulos → 6")
end

-- =====================================================================
-- 5.2 / 5.3 — element-wise e transforms → DataSet mesma forma
-- =====================================================================
do
    local source_dataset = smaug.DataSet({{"a", {-1, 2, -3}, "int64"}, {"b", {1.5, 2.5, 3.5}, "float64"}})

    -- forma preservada
    local abs_result = source_dataset:abs()
    check(abs_result:nrows() == 3 and #abs_result._col_names == 2, "5.2 abs: mesma forma")
    check(abs_result:column("a"):get(1) == 1 and abs_result:column("a"):get(3) == 3, "5.2 abs valores")

    -- cumsum/cummin/cummax/cumprod acumulam por coluna
    local source_dataset_2 = smaug.DataSet({{"a", {3, 1, 4, 1, 5}, "int64"}, {"b", {2.0, 4.0, 1.0, 3.0, 5.0}, "float64"}})
    local cumulative_sum_result = source_dataset:cumsum()
    check(cumulative_sum_result:column("a"):get(3) == -2, "5.2 cumsum a[3]=-2")
    check(approximately_equal(cumulative_sum_result:column("b"):get(3), 7.5), "5.2 cumsum b[3]=7.5")

    local cumulative_minimum_result = source_dataset_2:cummin()
    check(cumulative_minimum_result:column("a"):get(1) == 3 and cumulative_minimum_result:column("a"):get(2) == 1
      and cumulative_minimum_result:column("a"):get(5) == 1, "5.2 cummin a: 3,1,1,1,1")
    local cumulative_maximum_result = source_dataset_2:cummax()
    check(cumulative_maximum_result:column("b"):get(1) == 2.0 and cumulative_maximum_result:column("b"):get(2) == 4.0
      and cumulative_maximum_result:column("b"):get(5) == 5.0, "5.2 cummax b: 2,4,4,4,5")

    -- round / clip com argumentos
    check(source_dataset:round(0):column("b"):get(2) == 3, "5.2 round(0) b[2]=3")
    check(source_dataset:clip(0, 2):column("a"):get(1) == 0, "5.2 clip(0,2) a[1]=0")
    check(source_dataset:cumprod():column("a"):get(2) == -2, "5.2 cumprod a[2]=-2")

    -- shift desloca (NA na borda); diff
    check(source_dataset:shift(1):column("a"):is_null(1), "5.3 shift(1): a[1]=NA")
    check(source_dataset:diff():column("a"):get(2) == 3, "5.3 diff a[2]=3")

    -- D4-i: element-wise numérico erra com coluna não-numérica
    local source_dataset_3 = smaug.DataSet({{"a", {1, 2}, "int64"}, {"nome", {"x", "y"}, "string"}})
    check(not pcall(function() return source_dataset_3:abs() end), "5.2 D4-i: abs erra com coluna string")
    check(not pcall(function() return source_dataset_3:cumsum() end), "5.2 D4-i: cumsum erra com coluna string")
    check(not pcall(function() return source_dataset_3:cummin() end), "5.2 D4-i: cummin erra com coluna string")
    check(not pcall(function() return source_dataset_3:cummax() end), "5.2 D4-i: cummax erra com coluna string")

    -- ffill/bfill/shift funcionam em qualquer dtype (string incluída)
    local source_dataset_4 = smaug.DataSet({{"s", {"a", smaug.NA, "c"}, "string"}})
    check(source_dataset_4:ffill():column("s"):get(2) == "a", "5.3 ffill em string")
    check(source_dataset_4:shift(1):column("s"):is_null(1), "5.3 shift em string: borda NA")

    local source_dataset_5 = smaug.DataSet({{"a", {smaug.NA, 2.0, smaug.NA, 4.0}, "float64"}})
    local backward_fill_result = source_dataset_5:bfill()
    check(backward_fill_result:column("a"):get(1) == 2.0, "5.3 bfill a[1]=2.0 (preenche do próximo)")
    check(backward_fill_result:column("a"):get(3) == 4.0, "5.3 bfill a[3]=4.0")
    local source_dataset_6 = smaug.DataSet({{"s", {smaug.NA, "y", smaug.NA}, "string"}})
    check(source_dataset_6:bfill():column("s"):get(1) == "y", "5.3 bfill funciona em string também")

    -- isna/notna → DataSet bool, todas as colunas (qualquer dtype)
    local source_dataset_7 = smaug.DataSet({{"x", {1, smaug.NA}, "int64"}, {"nome", {"a", smaug.NA}, "string"}})
    local null_mask = source_dataset_7:isna()
    check(null_mask:column("x")._dtype == "bool", "5.3 isna: dtype bool")
    check(null_mask:column("x"):get(2) == true and null_mask:column("nome"):get(2) == true, "5.3 isna: linha 2 nula")
    check(null_mask:column("x"):get(1) == false, "5.3 isna: linha 1 não-nula")
    check(source_dataset_7:notna():column("nome"):get(1) == true, "5.3 notna: inverso de isna")

    -- astype mapa { coluna = dtype } (D4-A); coluna fora do mapa inalterada
    local converted_series = source_dataset_7:astype({x = "float64"})
    check(converted_series:column("x")._dtype == "float64", "5.3 astype: x → float64")
    check(converted_series:column("nome")._dtype == "string", "5.3 astype: coluna fora do mapa inalterada")
    check(not pcall(function() return source_dataset_7:astype({zzz = "int64"}) end), "5.3 astype: erro em coluna inexistente")
    check(not pcall(function() return source_dataset_7:astype("float64") end), "5.3 astype: erro se não for mapa")
end

do
    local source_dataset = smaug.DataSet({
        {"date", {"02/05/2026", "02-05-2026", "2026-05-02", smaug.NA}, "string"},
        {"label", {"a", "b", "c", "d"}, "string"},
    })
    for _, options in ipairs({{}, {dayfirst = false}, {dayfirst = true}}) do
        local converted_dataset = source_dataset:astype({date = "datetime"}, options)
        local expected_month = options.dayfirst and 5 or 2
        local expected_day = options.dayfirst and 2 or 5
        local date_series = converted_dataset:column("date")
        for row_index = 1, 2 do
            check(date_series.dt:month():get(row_index) == expected_month, "astype dayfirst: mês com / e -")
            check(date_series.dt:day():get(row_index) == expected_day, "astype dayfirst: dia com / e -")
        end
        check(date_series.dt:month():get(3) == 5 and date_series.dt:day():get(3) == 2,
              "astype dayfirst: ano primeiro mantém ordem")
        check(date_series:is_null(4), "astype dayfirst: NA preservado")
        check(date_series._name == "date", "astype dayfirst: nome preservado")
        check(rawequal(converted_dataset._columns["label"], source_dataset._columns["label"]),
              "astype dayfirst: coluna fora do mapa compartilhada")
    end
    check(source_dataset:astype({date = "datetime"}):column("date").dt:month():get(1) == 2,
          "astype dayfirst: opções omitidas usam mês/dia")
    check(source_dataset:column("date"):get(1) == "02/05/2026", "astype dayfirst: entrada preservada")
    check(not pcall(function() source_dataset:astype({date = "datetime"}, true) end),
          "astype dayfirst: rejeita opções não-tabela")
    for _, invalid_option in ipairs({"false", 0, 1}) do
        local succeeded, error_message = pcall(function()
            source_dataset:astype({date = "datetime"}, {dayfirst = invalid_option})
        end)
        check(not succeeded and tostring(error_message):find("dayfirst", 1, true) ~= nil,
              "astype dayfirst: rejeita valor não-booleano")
    end
end

print(string.format("OK — %d checks passaram (DataSet: corr/cov, equals, compare, duplicated, drop_duplicates, reduções, transforms)", passed_checks))
