-- tests/series/test_access.lua
-- Acesso elementar, casos degenerados (edge) e fillna.
-- Rode da raiz: luajit tests/series/test_access.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local ffi    = require("ffi")

local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local function approximately_equal(left_value, right_value)
    if left_value == nil or right_value == nil then return false end
    return math.abs(left_value - right_value) < 1e-9
end

local function is_nan(value)
    return value ~= value
end

-- Verifica que uma chamada lança erro (para casos que devem ser recusados).
local function check_error(callback, message)
    local succeeded = pcall(callback)
    check(not succeeded, message .. " (deveria lançar erro)")
end

-- NOTA: marcações "PENDENTE (1.6)" indicam asserções a adicionar quando a
-- funcionalidade correspondente for implementada nesta fase. Não remover sem
-- implementar.

-- ===================================================================
-- SÉRIE VAZIA (size 0)
-- ===================================================================
do
    local empty_float_series = smaug.Series({}, "float64")
    check(empty_float_series:len() == 0, "vazia: len 0")
    check(empty_float_series:count_nonnull() == 0, "vazia: count_nonnull 0")
    -- sum de vazia = 0 (default min_count=0; alinhado com pandas)
    check(empty_float_series:sum() == 0, "vazia: sum 0")
    -- PENDENTE (1.6): quando min_count existir, e:sum(nil, {min_count=1}) == nil
    -- mean/min/max/std de vazia = nil (sem valor neutro)
    check(empty_float_series:mean() == nil, "vazia: mean nil")
    check(empty_float_series:min() == nil, "vazia: min nil")
    check(empty_float_series:max() == nil, "vazia: max nil")
    check(empty_float_series:std() == nil, "vazia: std nil")
    check(empty_float_series:var() == nil, "vazia: var nil")
    -- transformações em vazia devolvem vazia, sem quebrar
    check(empty_float_series:clone():len() == 0, "vazia: clone vazia")
    check(empty_float_series:sort():len() == 0, "vazia: sort vazia")
    check(empty_float_series:head(3):len() == 0, "vazia: head vazia")
    check(empty_float_series:tail(3):len() == 0, "vazia: tail vazia")
    check(empty_float_series:take({}):len() == 0, "vazia: take vazio")
    -- comparação de vazia → Series <bool> vazia
    check(empty_float_series:gt(0):len() == 0, "vazia: gt len 0")
    check(empty_float_series:gt(0):count_true() == 0, "vazia: gt count_true 0")
    check(empty_float_series:gt(0):any() == false, "vazia: any false")
    check(empty_float_series:gt(0):all() == true, "vazia: all true (vacuamente)")
    -- to_table de vazia → tabela vazia
    check(#empty_float_series:to_table() == 0, "vazia: to_table vazio")
end

-- ===================================================================
-- SÉRIE DE 1 ELEMENTO
-- ===================================================================
do
    local single_value_series = smaug.Series({42}, "float64")
    check(single_value_series:len() == 1, "1-elem: len 1")
    check(single_value_series:sum() == 42, "1-elem: sum 42")
    check(single_value_series:mean() == 42, "1-elem: mean 42")
    check(single_value_series:min() == 42 and single_value_series:max() == 42, "1-elem: min==max==42")
    -- variância/desvio amostral (ddof=1) de 1 elemento = NA (n <2 indefinido)
    check(single_value_series:std() == nil, "1-elem: std NA (amostral, n <2)")
    check(single_value_series:var() == nil, "1-elem: var NA")
    check(single_value_series:sort():get(1) == 42, "1-elem: sort")
    check(single_value_series:clone():get(1) == 42, "1-elem: clone")
    check(single_value_series:head(5):len() == 1, "1-elem: head(5) limita a 1")
    -- view de 1 elemento
    local series_view = single_value_series:view(1, 1)
    check(series_view:len() == 1 and series_view:get(1) == 42, "1-elem: view")
end

-- ===================================================================
-- SÉRIE TODA-NULA
-- ===================================================================
do
    local all_null_float_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64")
    check(all_null_float_series:len() == 3, "toda-nula: len 3")
    check(all_null_float_series:count_nonnull() == 0, "toda-nula: count_nonnull 0")
    -- sum toda-nula = 0 (default). PENDENTE (1.6): sum(min_count=1) == nil
    check(all_null_float_series:sum() == 0, "toda-nula: sum 0 (default)")
    check(all_null_float_series:mean() == nil, "toda-nula: mean nil")
    check(all_null_float_series:min() == nil, "toda-nula: min nil")
    check(all_null_float_series:max() == nil, "toda-nula: max nil")
    -- sort recusa série com nulos
    check_error(function() return all_null_float_series:sort() end, "toda-nula: sort recusa nulos")
    -- comparação: nulo não é > 0 → 0 trues, mas a máscara mantém os NA
    check(all_null_float_series:gt(0):count_true() == 0, "toda-nula: gt count_true 0")
    check(all_null_float_series:gt(0):is_null(1) == true, "toda-nula: gt preserva NA na máscara")
    -- todas as posições são null
    check(all_null_float_series:is_null(1) and all_null_float_series:is_null(3), "toda-nula: is_null em todas")
end

-- ===================================================================
-- SÉRIE TODA-IGUAL
-- ===================================================================
do
    local constant_series = smaug.Series({5, 5, 5, 5}, "float64")
    check(constant_series:sum() == 20, "toda-igual: sum 20")
    check(constant_series:mean() == 5, "toda-igual: mean 5")
    check(constant_series:min() == 5 and constant_series:max() == 5, "toda-igual: min==max==5")
    -- variância/desvio de valores idênticos = 0
    check(constant_series:std() == 0, "toda-igual: std 0")
    check(constant_series:var() == 0, "toda-igual: var 0")
    -- sort de toda-igual = ela mesma
    local sorted_series = constant_series:sort()
    check(sorted_series:get(1) == 5 and sorted_series:get(4) == 5, "toda-igual: sort estável")
    -- gt(5) → nenhum; gt(4) → todos
    check(constant_series:gt(5):count_true() == 0, "toda-igual: gt(5) nenhum")
    check(constant_series:gt(4):count_true() == 4, "toda-igual: gt(4) todos")
    check(constant_series:eq(5):all() == true, "toda-igual: eq(5) all true")
end

-- ===================================================================
-- i64: paridade nos casos degenerados + sentinela
-- ===================================================================
do
    local empty_integer_series = smaug.Series({}, "int64")
    check(empty_integer_series:sum() == 0, "i64 vazia: sum 0")
    check(empty_integer_series:mean() == nil, "i64 vazia: mean nil")
    local all_null_integer_series = smaug.Series({smaug.NA, smaug.NA}, "int64")
    check(all_null_integer_series:sum() == 0, "i64 toda-nula: sum 0 (ignore_na)")
    -- sentinela INT64_MIN deve virar nil quando ignore_na=false
    check(all_null_integer_series:sum(false) == nil, "i64 toda-nula: sum(false) nil (sentinela→nil)")
    check(all_null_integer_series:max() == nil, "i64 toda-nula: max nil")
    local single_integer_series = smaug.Series({7}, "int64")
    check(single_integer_series:sum() == 7 and single_integer_series:std() == nil, "i64 1-elem: sum=7, std=NA (amostral)")
end

-- ===================================================================
-- PROPAGAÇÃO DE NULL EM COMPARAÇÃO (série mista)
-- Comparar um nulo produz NA na máscara — nunca false.
-- ===================================================================
do
    local nullable_floating_point_series = smaug.Series({10, smaug.NA, 30}, "float64")
    local greater_than_mask = nullable_floating_point_series:gt(15)              -- F, NA, T
    check(greater_than_mask:get(1) == false, "cmp-misto: 10 >15 false")
    check(greater_than_mask:get(2) == nil,   "cmp-misto: NA >15 → NA (não false)")
    check(greater_than_mask:is_null(2) == true, "cmp-misto: posição NA marcada na máscara")
    check(greater_than_mask:get(3) == true,  "cmp-misto: 30 >15 true")
    check(greater_than_mask:count_true() == 1, "cmp-misto: count_true 1 (NA não conta)")
    -- filter descarta a linha NA da máscara
    check(nullable_floating_point_series:filter(greater_than_mask):len() == 1, "cmp-misto: filter descarta NA e false")
end

-- ===================================================================
-- dropna: remove NULLs (qualquer dtype); habilita sort em série com nulos
-- ===================================================================
do
    -- f64 com NULL intercalado
    local nullable_floating_point_series = smaug.Series({1, smaug.NA, 3, smaug.NA, 5}, "float64")
    local non_null_result = nullable_floating_point_series:dropna()
    check(non_null_result:len() == 3, "dropna: remove os NULLs (5->3)")
    check(non_null_result:get(1) == 1 and non_null_result:get(2) == 3 and non_null_result:get(3) == 5, "dropna: mantem ordem dos validos")
    -- a mensagem "use dropna primeiro" agora e verdadeira: dropna+sort funciona
    local nullable_integer_series = smaug.Series({3, smaug.NA, 1, 2}, "int64")
    local sorted = nullable_integer_series:dropna():sort()
    check(sorted:len() == 3 and sorted:get(1) == 1 and sorted:get(3) == 3,
          "dropna habilita sort em serie com nulos")
    -- string tambem
    local nullable_string_series = smaug.Series({"SP", smaug.NA, "MG"}, "string")
    check(nullable_string_series:dropna():len() == 2, "dropna string")
    -- tudo NULL -> serie vazia (sem erro)
    local all_null_floating_point_series = smaug.Series({smaug.NA, smaug.NA}, "float64")
    check(all_null_floating_point_series:dropna():len() == 0, "dropna tudo-NULL = serie vazia")
    -- sem NULL -> copia de mesmo tamanho
    local floating_point_series = smaug.Series({1, 2, 3}, "float64")
    check(floating_point_series:dropna():len() == 3, "dropna sem NULL = copia igual")
    -- string vazia "" NAO e NULL: dropna a mantem
    local nullable_string_series_2 = smaug.Series({"", smaug.NA, "a"}, "string")
    check(nullable_string_series_2:dropna():len() == 2, "dropna: '' nao e NULL, e mantida")
end

-- =====================================================================
-- fillna (Series e DataSet)
-- =====================================================================
do
    -- Series:fillna — preenche null, devolve NOVA series
    local nullable_floating_point_series = smaug.Series({1.0, smaug.NA, 3.0, smaug.NA}, "float64")
    local filled_result = nullable_floating_point_series:fillna(0)
    -- nova series, original intacta
    check(nullable_floating_point_series:is_null(2) == true, "fillna: original não muda (imutável)")
    check(filled_result:is_null(2) == false, "fillna: null preenchido na nova")
    check(filled_result:get(2) == 0, "fillna: valor preenchido = 0")
    check(filled_result:get(4) == 0, "fillna: segundo null preenchido")
    -- não-nulos inalterados
    check(filled_result:get(1) == 1.0 and filled_result:get(3) == 3.0, "fillna: não-nulos intactos")
    check(filled_result:count_nonnull() == 4, "fillna: todos não-nulos após preencher")
    check(filled_result:len() == nullable_floating_point_series:len(), "fillna: mesmo comprimento")

    -- fillna preenche NULL mas deixa NaN intacto (contrato NaN ≠ null)
    local nan_value = 0/0
    local series_nan = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "float64")
    series_nan:set(1, nil)    -- null
    series_nan:set(2, nan_value)    -- NaN (valor)
    series_nan:set(3, 5.0)    -- normal
    local nan_float_series = series_nan:fillna(99)
    check(nan_float_series:get(1) == 99, "fillna: null → 99")
    check(is_nan(nan_float_series:get(2)), "fillna: NaN permanece NaN (não é null, não preenche)")
    check(nan_float_series:get(3) == 5.0, "fillna: valor normal intacto")
    check(nan_float_series:is_null(2) == false, "fillna: posição NaN não era null")

    -- sem argumento → erro; sem coerção de tipo → erro
    check_error(function() return nullable_floating_point_series:fillna() end, "fillna: sem argumento")
    check_error(function() return nullable_floating_point_series:fillna(nil) end, "fillna: argumento nil")
    -- i64: preencher com não-inteiro é erro (sem coerção)
    local nullable_integer_series = smaug.Series({1, smaug.NA, 3}, "int64")
    check_error(function() return nullable_integer_series:fillna(1.5) end, "fillna: i64 recusa 1.5 (sem coerção)")
    -- i64 com inteiro funciona
    local filled_result_2 = nullable_integer_series:fillna(0)
    check(filled_result_2:get(2) == 0, "fillna: i64 preenche com inteiro")
    check(filled_result_2:count_nonnull() == 3, "fillna: i64 todos preenchidos")

    -- casos degenerados
    -- série sem nulos: fillna devolve cópia equivalente
    local series_clean = smaug.Series({1.0, 2.0}, "float64")
    local clean_float_series = series_clean:fillna(0)
    check(clean_float_series:get(1) == 1.0 and clean_float_series:get(2) == 2.0, "fillna: sem nulos = cópia igual")
    -- série vazia: fillna não quebra
    local empty_floating_point_series = smaug.Series({}, "float64")
    check(empty_floating_point_series:fillna(0):len() == 0, "fillna: vazia ok")
    -- série toda-nula: tudo vira o valor
    local all_null_integer_series = smaug.Series({smaug.NA, smaug.NA}, "float64")
    local all_null_float_series = all_null_integer_series:fillna(7)
    check(all_null_float_series:get(1) == 7 and all_null_float_series:get(2) == 7, "fillna: toda-nula → tudo 7")
    check(all_null_float_series:count_nonnull() == 2, "fillna: toda-nula preenchida")

    -- DataSet:fillna

    local source_dataset = smaug.DataSet({
        { "a", {1.0, smaug.NA, 3.0}, "float64"},
        { "b", {smaug.NA, 20.0, 30.0}, "float64"},
    })
    -- fillna(valor) → todas as colunas
    local filled_result_3 = source_dataset:fillna(0)
    check(filled_result_3:column("a"):get(2) == 0, "DS fillna: col a preenchida")
    check(filled_result_3:column("b"):get(1) == 0, "DS fillna: col b preenchida")
    -- original intacto
    check(source_dataset:column("a"):is_null(2) == true, "DS fillna: original intacto")
    -- fillna({col=valor}) → por coluna; coluna omitida mantém nulos
    local filled_dataset = source_dataset:fillna({a = -1})
    check(filled_dataset:column("a"):get(2) == -1, "DS fillna map: col a = -1")
    check(filled_dataset:column("b"):is_null(1) == true, "DS fillna map: col b omitida mantém null")
end

-- =====================================================================
-- Item 6 — pares Series↔DataSet: dtype, sample, to_string
-- =====================================================================
do
    -- 6.1 dtype singular
    check(smaug.Series({1, 2}, "int64"):dtype() == "int64", "6.1 dtype int64")
    check(smaug.Series({1.0}, "float64"):dtype() == "float64", "6.1 dtype float64")
    check(smaug.Series({"a"}, "string"):dtype() == "string", "6.1 dtype string")
    -- 6.3 sample: n elementos, sem reposição, determinístico com seed
    local integer_series = smaug.Series({10, 20, 30, 40, 50}, "int64")
    local sampled_dataset = integer_series:sample(3, 1)
    check(sampled_dataset:len() == 3, "6.3 sample: tamanho n")
    check(integer_series:sample(3, 1):to_table()[1] == sampled_dataset:to_table()[1], "6.3 sample: determinístico com seed")
    check(integer_series:sample(99):len() == 5, "6.3 sample: n > len limita a len")
    -- 6.3 to_string / to_markdown (1 coluna, NA legível)
    local nullable_integer_series = smaug.Series({1, smaug.NA}, "int64")
    local formatted_text = nullable_integer_series:to_string()
    check(formatted_text:find("NA") ~= nil, "6.3 to_string mostra NA")
    local markdown_text = nullable_integer_series:to_markdown()
    check(markdown_text:find("|") ~= nil and markdown_text:find("%-%-") ~= nil, "6.3 to_markdown tem cabeçalho/separador")
    check(select(2, markdown_text:gsub("\n", "\n")) == 3, "6.3 to_markdown: 4 linhas (header+sep+2 dados)")
    -- 11.5/11.4 invariantes de display
    local large_integer = ffi.new("int64_t", 9007199254740993LL)  -- 2^53 + 1
    local allocated_integer_series  = smaug.Series({smaug.NA}, "int64", "big"); allocated_integer_series:set(1, large_integer)
    check(allocated_integer_series:to_string():find("9007199254740993", 1, true) ~= nil,
          "11.4 to_string: int64 > 2^53 EXATO (sem notação científica)")
    check(tostring(allocated_integer_series):find("9007199254740993", 1, true) ~= nil,
          "11.4 __tostring: int64 > 2^53 EXATO")
    check(allocated_integer_series:to_string():find("e+", 1, true) == nil,
          "11.4 to_string: sem notação científica no int64 grande")
    local floating_point_series = smaug.Series({3.14159265358979}, "float64")
    check(floating_point_series:to_string():find("3.14159", 1, true) ~= nil,
          "11.5 to_string: float via %.6g")
    local floating_point_series_2 = smaug.Series({0/0, 1/0, -1/0}, "float64")
    local formatted_text_2 = floating_point_series_2:to_string()
    check(formatted_text_2:find("nan", 1, true) and formatted_text_2:find("inf", 1, true) and formatted_text_2:find("-inf", 1, true),
          "11.5 to_string: NaN/inf normalizados")
    local string_series = smaug.Series({"José", "François"}, "string")
    local unicode_lines = {}; for line in (string_series:to_string().."\n"):gmatch("(.-)\n") do unicode_lines[#unicode_lines+1] = line end
    local display = require("smaug.core.display")
    check(display.dwidth(unicode_lines[2]) == display.dwidth(unicode_lines[3]),
          "11.5 to_string: alinhamento UTF-8 por codepoint (José vs François)")
end

-- =====================================================================
-- 10.6 Passo B: fillna em int64 delega a coalesce_scalar (Anel 0).
-- =====================================================================
do
    local large_integer = ffi.new("int64_t", 9007199254740993LL)   -- 2^53 + 1
    -- nao-nulo > 2^53 preservado exato
    local allocated_integer_series = smaug.Series({smaug.NA, smaug.NA}, "int64", "big"); allocated_integer_series:set_null(1); allocated_integer_series:set(2, large_integer)
    local filled_result = allocated_integer_series:fillna(0)
    check(tostring(filled_result:get_raw(2)) == tostring(large_integer), "10.6B: fillna i64 nao-nulo 2^53+1 preservado exato")
    check(filled_result:get(1) == 0, "10.6B: fillna i64 preenche buraco")
    -- value cdata int64 grande agora aceito (desparidade curada)
    local allocated_integer_series_2 = smaug.Series({smaug.NA, smaug.NA}, "int64", "big2"); allocated_integer_series_2:set_null(1); allocated_integer_series_2:set(2, 10)
    local filled_result_2 = allocated_integer_series_2:fillna(large_integer)
    check(tostring(filled_result_2:get_raw(1)) == tostring(large_integer), "10.6B: fillna value cdata int64 > 2^53 (desparidade curada)")
    -- <= 2^53 intacto
    local allocated_integer_series_3 = smaug.Series({smaug.NA, smaug.NA}, "int64", "p"); allocated_integer_series_3:set_null(1); allocated_integer_series_3:set(2, 42)
    local filled_result_3 = allocated_integer_series_3:fillna(7)
    check(filled_result_3:get(1) == 7 and filled_result_3:get(2) == 42, "10.6B: fillna i64 <=2^53 intacto (nao-regressao)")
    -- fracionário ainda recusa (check_value)
    check_error(function() return allocated_integer_series_3:fillna(1.5) end, "10.6B: fillna i64 fracionário recusa")

    -- 10.6B: fillna string toda-nula com value=""
    local allocated_string_series = smaug.Series({smaug.NA, smaug.NA}, "string", "sv"); allocated_string_series:set_null(1); allocated_string_series:set_null(2)
    local filled_result_4 = allocated_string_series:fillna("")
    check(filled_result_4:get(1) == "" and filled_result_4:get(2) == "", "10.6B: fillna string toda-nula value='' -> vazias válidas")
    check(not filled_result_4:is_null(1) and not filled_result_4:is_null(2), "10.6B: fillna string '' resulta válido (não nulo)")
    -- mistura: buraco + string não-vazia
    local allocated_string_series_2 = smaug.Series({smaug.NA, smaug.NA}, "string", "sm"); allocated_string_series_2:set_null(1); allocated_string_series_2:set(2, "abc")
    local filled_result_5 = allocated_string_series_2:fillna("")
    check(filled_result_5:get(1) == "" and filled_result_5:get(2) == "abc", "10.6B: fillna string mistura buraco/'abc'")
end

-- =====================================================================
-- 11.2: proxies expostos têm __tostring legível
-- =====================================================================
do
    local function notleaky(value, tag)
        local formatted_text = tostring(value)
        check(type(formatted_text) == "string" and formatted_text:find("^table:") == nil and #formatted_text > 0, tag)
    end
    local string_series = smaug.Series({"a", "b"}, "string"); string_series._name = "s"
    local datetime_series  = smaug.Series({1000, 2000}, "datetime"); datetime_series._name = "t"
    local floating_point_series = smaug.Series({1, 2, 3, 4}, "float64"); floating_point_series._name = "v"
    notleaky(string_series.str,           "11.2 .str proxy __tostring")
    notleaky(datetime_series.dt,             "11.2 .dt proxy __tostring")
    notleaky(string_series.at,            "11.2 .at proxy __tostring")
    notleaky(floating_point_series:rolling(2),    "11.2 rolling proxy __tostring")
    notleaky(floating_point_series:expanding(),   "11.2 expanding proxy __tostring")
    check(tostring(string_series.str):find(".str", 1, true) ~= nil, "11.2 .str rótulo referencia acessor")
end

-- =====================================================================
-- 12.12: método desconhecido erra com sugestão
-- =====================================================================
do
    local floating_point_series = smaug.Series({1, 2, 3}, "float64")
    local function error_message_of(callback) local succeeded, error_message = pcall(callback); return tostring(error_message) end
    local suggestion_error = error_message_of(function() return floating_point_series:sumn() end)
    check(suggestion_error:find("não existe", 1, true) ~= nil, "12.12 Series: método inexistente erra")
    check(suggestion_error:find("'sum'", 1, true) ~= nil,      "12.12 Series: sugere 'sum' para 'sumn'")
    local unknown_method_error = error_message_of(function() return floating_point_series:xyzabc() end)
    check(unknown_method_error:find("não existe", 1, true) ~= nil, "12.12 Series: nome distante erra")
    check(unknown_method_error:find("quis dizer", 1, true) == nil, "12.12 Series: nome distante NÃO sugere")
    -- campos internos seguem devolvendo nil (não podem erguer erro)
    check(floating_point_series._inexistente == nil,                "12.12 Series: chave _interna devolve nil")
    -- acessores e métodos reais intactos
    check(floating_point_series:mean() == 2,                        "12.12 Series: método real intacto")
    check(floating_point_series.at[1] == 1,                         "12.12 Series: acessor .at intacto")
end

-- =====================================================================
-- 10.3 fatia B — abs/round/clip desceram ao Anel 0.
-- =====================================================================
do
    local large_integer = ffi.new("int64_t", 9007199254740993LL)     -- 2^53 + 1
    local negative_large_integer = ffi.new("int64_t", -9007199254740993LL)
    -- 10.3.1 — o caso que era corrupção, depois erro, e agora é resultado certo
    local allocated_integer_series = smaug.Series({smaug.NA}, "int64", "neg"); allocated_integer_series:set(1, negative_large_integer)
    check(allocated_integer_series:abs():get_raw(1) == large_integer,
          "10.3.1 abs preserva int64 > 2^53 exato (era ...992 corrompido)")
    check(allocated_integer_series:abs()._dtype == "int64", "10.3.1 abs preserva dtype")
    local allocated_integer_series_2 = smaug.Series({smaug.NA}, "int64", "big"); allocated_integer_series_2:set(1, large_integer)
    check(allocated_integer_series_2:clip(negative_large_integer, large_integer):get_raw(1) == large_integer, "10.3.1 clip preserva exato")
    -- 10.3.2 — round em int64 preserva int64
    check(allocated_integer_series_2:round()._dtype == "int64",       "10.3.2 round(int64) devolve int64")
    check(allocated_integer_series_2:round():get_raw(1) == large_integer,       "10.3.2 round(n>=0) é identidade exata")
    check(allocated_integer_series_2:round(3):get_raw(1) == large_integer,      "10.3.2 ndigits positivo também é identidade")
    -- 10.3.3 — ndigits < 0 faz trabalho real, em aritmética inteira
    local integer_series = smaug.Series({1234, -1567, 7}, "int64")
    check(integer_series:round(-2):get(1) == 1200,   "10.3.3 round(1234,-2)=1200")
    check(integer_series:round(-2):get(2) == -1600,  "10.3.3 round(-1567,-2)=-1600 (half-away-from-zero)")
    check(integer_series:round(-3):get(1) == 1000,   "10.3.3 round(1234,-3)=1000")
    check(integer_series:round(-1):get(3) == 10,     "10.3.3 round(7,-1)=10")
    -- 10.3.3b — o PONTO EXATO de meio caminho
    local integer_series_2 = smaug.Series({1250, -1250, 1350, 50}, "int64")
    check(integer_series_2:round(-2):get(1) == 1300,  "10.3.3b round(1250,-2)=1300 (meio → afasta do zero)")
    check(integer_series_2:round(-2):get(2) == -1300, "10.3.3b round(-1250,-2)=-1300 (simétrico)")
    check(integer_series_2:round(-2):get(3) == 1400,  "10.3.3b round(1350,-2)=1400")
    check(integer_series_2:round(-2):get(4) == 100,   "10.3.3b round(50,-2)=100 (meio de zero afasta)")
    -- abaixo do meio arredonda para baixo
    local integer_series_3 = smaug.Series({1249, -1249}, "int64")
    check(integer_series_3:round(-2):get(1) == 1200,  "10.3.3b round(1249,-2)=1200")
    check(integer_series_3:round(-2):get(2) == -1200, "10.3.3b round(-1249,-2)=-1200")
    -- 10.3.4 — as três decisões: casos sem resposta erram
    local allocated_integer_series_3 = smaug.Series({smaug.NA}, "int64", "min")
    allocated_integer_series_3:set(1, ffi.new("int64_t", -9223372036854775807LL - 1))   -- INT64_MIN
    local succeeded, overflow_error = pcall(function() return allocated_integer_series_3:abs() end)
    check(not succeeded, "10.3.4 abs(INT64_MIN) erra (não tem contrapartida positiva)")
    check(tostring(overflow_error):match("INT64_MIN") ~= nil,
          "10.3.4 mensagem nomeia a causa, não só 'falhou'")
    local succeeded_2, error_message = pcall(function() return smaug.Series({1,5,9},"int64"):clip(8,2) end)
    check(not succeeded_2, "10.3.4 clip(lo>hi) erra (antes devolvia {8,8,2}, fora de faixa)")
    check(tostring(error_message):match("contradit") ~= nil, "10.3.4 mensagem explica a faixa")
    check(not pcall(function() return integer_series:round(-19) end),
          "10.3.4 round(-19) erra (fator 10^19 não cabe em int64)")
    -- 10.3.5 — caminho normal intacto nos dois dtypes
    local integer_series_4 = smaug.Series({-3, 2}, "int64")
    check(integer_series_4:abs():get(1) == 3,          "10.3.5 abs int64 pequeno")
    check(integer_series_4:clip(-1, 1):get(1) == -1,   "10.3.5 clip int64 pequeno")
    check(integer_series_4:clip(nil, 1):get(2) == 1,   "10.3.5 clip só com limite superior")
    check(integer_series_4:clip(-1, nil):get(1) == -1, "10.3.5 clip só com limite inferior")
    local source_series = smaug.Series({-1.7, 2.345})
    check(source_series:abs():get(1) == 1.7,         "10.3.5 abs float64")
    check(source_series:round():get(1) == -2,        "10.3.5 round float64 half-away-from-zero")
    check(source_series:round(2):get(2) == 2.35,     "10.3.5 round float64 com ndigits")
    check(source_series:clip(-1, 1):get(1) == -1,    "10.3.5 clip float64")
    -- 10.3.6 — nulo propaga nas três, nos dois dtypes
    local allocated_integer_series_4 = smaug.Series({smaug.NA, smaug.NA}, "int64", "wn"); allocated_integer_series_4:set_null(1); allocated_integer_series_4:set(2, 5)
    check(allocated_integer_series_4:abs():is_null(1),           "10.3.6 abs preserva nulo (int64)")
    check(allocated_integer_series_4:round():is_null(1),         "10.3.6 round preserva nulo (int64)")
    check(allocated_integer_series_4:clip(0, 10):is_null(1),     "10.3.6 clip preserva nulo (int64)")
    local nullable_float_series = smaug.Series({4.0, smaug.NA}, "float64")
    check(nullable_float_series:abs():is_null(2),           "10.3.6 abs preserva nulo (f64)")
    -- 10.3.7 — série vazia e dtype não numérico
    check(smaug.Series({}, "int64"):abs():len() == 0,   "10.3.7 série vazia não estoura")
    check(not pcall(function() return smaug.Series({"a"},"string"):abs() end),
          "10.3.7 dtype não numérico recusado")
end

-- =====================================================================
-- 10.2 (fatia 1: f64+i64) — between desceu ao Anel 0.
-- =====================================================================
do
    local exact_double_limit  = ffi.new("int64_t", 9007199254740992LL)   -- 2^53
    local above_double_limit  = ffi.new("int64_t", 9007199254740993LL)   -- 2^53 + 1
    local larger_integer = ffi.new("int64_t", 9007199254740995LL)   -- 2^53 + 3
    local integer_series  = smaug.Series({exact_double_limit, above_double_limit, larger_integer}, "int64", "big")
    -- 10.2.1 — between(x, x) no próprio x. Só a linha de B pode ser true.
    local between_result = integer_series:between(above_double_limit, above_double_limit)
    check(between_result:get(1) == false and between_result:get(2) == true and between_result:get(3) == false,
          "10.2.1 between exato em int64 > 2^53 (era falha visível)")
    -- 10.2.2 — os quatro modos de inclusividade
    local between_result_2 = integer_series:between(exact_double_limit, larger_integer)
    check(between_result_2:get(1) and between_result_2:get(2) and between_result_2:get(3),
          "10.2.2 inclusive=both inclui as duas pontas")
    local neither = integer_series:between(exact_double_limit, larger_integer, "neither")
    check(neither:get(1) == false and neither:get(2) == true and neither:get(3) == false,
          "10.2.2 inclusive=neither exclui as duas pontas")
    local between_result_3 = integer_series:between(exact_double_limit, larger_integer, "left")
    check(between_result_3:get(1) == true and between_result_3:get(3) == false,
          "10.2.2 inclusive=left inclui só a inferior")
    local right = integer_series:between(exact_double_limit, larger_integer, "right")
    check(right:get(1) == false and right:get(3) == true,
          "10.2.2 inclusive=right inclui só a superior")
    -- 10.2.3 — limite como number >= 2^53 é recusado
    check(not pcall(function() return integer_series:between(9007199254740993, larger_integer) end),
          "10.2.3 limite inferior number >= 2^53 recusado")
    check(not pcall(function() return integer_series:between(exact_double_limit, 9007199254740993) end),
          "10.2.3 limite superior number >= 2^53 recusado")
    -- 10.2.4 — nulo propaga nulo; NaN em f64 é false com máscara válida.
    local allocated_integer_series = smaug.Series({smaug.NA, smaug.NA, smaug.NA}, "int64", "wn")
    allocated_integer_series:set(1, 10); allocated_integer_series:set_null(2); allocated_integer_series:set(3, 20)
    local between_result_4 = allocated_integer_series:between(0, 15)
    check(between_result_4:get(1) == true and between_result_4:is_null(2) and between_result_4:get(3) == false,
          "10.2.4 nulo propaga nulo")
    local nan_float_series = smaug.Series({1.0, 0/0, 3.0}, "float64", "f")
    local between_result_5 = nan_float_series:between(0.5, 3.5)
    check(between_result_5:get(1) == true and between_result_5:get(2) == false and between_result_5:get(3) == true,
          "10.2.4 NaN → false (não nulo), coerente com os comparadores")
    check(not between_result_5:is_null(2), "10.2.4 NaN tem máscara válida")
    -- 10.2.5 — os quatro modos TAMBÉM em f64.
    local floating_point_series = smaug.Series({1.0, 2.0, 3.0}, "float64", "fm")
    local between_result_6 = floating_point_series:between(1.0, 3.0)
    check(between_result_6:get(1) and between_result_6:get(2) and between_result_6:get(3), "10.2.5 f64 both")
    local between_result_7 = floating_point_series:between(1.0, 3.0, "neither")
    check(between_result_7:get(1) == false and between_result_7:get(2) == true and between_result_7:get(3) == false,
          "10.2.5 f64 neither")
    local between_result_8 = floating_point_series:between(1.0, 3.0, "left")
    check(between_result_8:get(1) == true and between_result_8:get(3) == false, "10.2.5 f64 left")
    local between_result_9 = floating_point_series:between(1.0, 3.0, "right")
    check(between_result_9:get(1) == false and between_result_9:get(3) == true, "10.2.5 f64 right")
    -- 10.2.6 — série vazia não estoura (nos dois dtypes).
    check(smaug.Series({}, "int64"):between(1, 5):len() == 0, "10.2.6 série int64 vazia → len 0")
    check(smaug.Series({}, "float64"):between(1, 5):len() == 0, "10.2.6 série f64 vazia → len 0")
    -- 10.2.7 (fatia 2) — string desceu ao Anel 0
    local string_series = smaug.Series({"a", "c", "e"}, "string", "s")
    local between_result_10 = string_series:between("a", "c")
    check(between_result_10:get(1) and between_result_10:get(2) and between_result_10:get(3) == false, "10.2.7 string both")
    local between_result_11 = string_series:between("a", "e", "neither")
    check(between_result_11:get(1) == false and between_result_11:get(2) == true and between_result_11:get(3) == false,
          "10.2.7 string neither")
    local between_result_12 = string_series:between("a", "e", "left")
    check(between_result_12:get(1) == true and between_result_12:get(3) == false, "10.2.7 string left")
    local between_result_13 = string_series:between("a", "e", "right")
    check(between_result_13:get(1) == false and between_result_13:get(3) == true, "10.2.7 string right")
    -- desempate por prefixo
    check(smaug.Series({"ab"}, "string"):between("a", "b"):get(1) == true,
          "10.2.7 string prefixo mais curta vem antes")
    -- 10.2.8 (fatia 2) — datetime, os quatro modos.
    local datetime_series = smaug.Series({0, 1000, 2000}, "datetime", "d")
    check(datetime_series:between(0, 2000):get(1) and datetime_series:between(0, 2000):get(3),
          "10.2.8 datetime both inclui as pontas")
    local between_result_14 = datetime_series:between(0, 2000, "neither")
    check(between_result_14:get(1) == false and between_result_14:get(2) == true and between_result_14:get(3) == false,
          "10.2.8 datetime neither")
    local between_result_15 = datetime_series:between(0, 2000, "left")
    check(between_result_15:get(1) == true and between_result_15:get(3) == false, "10.2.8 datetime left")
    local between_result_16 = datetime_series:between(0, 2000, "right")
    check(between_result_16:get(1) == false and between_result_16:get(3) == true, "10.2.8 datetime right")
    -- 10.2.9 — nulo propaga nos QUATRO dtypes
    check(smaug.Series({"a", smaug.NA, "c"}, "string"):between("a", "z"):is_null(2),
          "10.2.9 string propaga nulo")
    check(smaug.Series({0, smaug.NA, 2000}, "datetime"):between(0, 3000):is_null(2),
          "10.2.9 datetime propaga nulo")
    check(smaug.Series({"a"}, "string"):between("a", "z"):len() == 1,
          "10.2.9 string série de 1 elemento")
    -- 10.2.10 — dtype sem ordem continua recusado (bool não tem cmp_between).
    check(not pcall(function() return smaug.Series({true}, "bool"):between(true, true) end),
          "10.2.10 bool recusado (sem ordem)")
end

print(string.format("OK — %d checks passaram (Series: acesso, edge cases, fillna)", passed_checks))
