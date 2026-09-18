-- tests/series/test_str.lua
-- Accessor .str completo: construção/mutação/clone, comparações, seleção,
-- ordenação, fillna/describe/astype, e todos os métodos de .str (len, lower,
-- upper, strip, contains, startswith, endswith, replace, find, slice, pad,
-- zfill, rep, cat, split, count, predicados ASCII, removeprefix/removesuffix,
-- capitalize/title/swapcase, join) e integração com DataSet.
-- Rode da raiz: luajit tests/series/test_str.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local passed_checks = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    passed_checks = passed_checks + 1
end

local function rejects(callback) return pcall(callback) == false end

-- ===================================================================
-- Construção e acesso
-- ===================================================================
do
    local state_names = smaug.Series({"SP", "RJ", smaug.NA, "Minas"}, "string")
    check(state_names:len() == 4, "len")
    check(state_names:get(1) == "SP", "get string")
    check(state_names:get(4) == "Minas", "get string longa")
    check(state_names:get(3) == nil, "get NA -> nil")
    check(state_names:is_null(3), "is_null no NA")
    check(not state_names:is_null(1), "is_null false em valido")
    check(state_names:count_nonnull() == 3, "count_nonnull")
end

-- ===================================================================
-- String vazia é distinta de NULL
-- ===================================================================
do
    local with_empty_string = smaug.Series({"", smaug.NA, "x"}, "string")
    check(with_empty_string:get(1) == "", "vazia -> '' (nao nil)")
    check(not with_empty_string:is_null(1), "vazia nao e null")
    check(with_empty_string:get(2) == nil, "NA -> nil")
    check(with_empty_string:is_null(2), "NA e null")
    check(with_empty_string:count_nonnull() == 2, "vazia conta como valida")
end

-- ===================================================================
-- Mutação: set (3 casos via backend), set_null, append
-- ===================================================================
do
    local state_names = smaug.Series({"SP", "RJ", "MG"}, "string")
    -- mesmo tamanho
    state_names:set(1, "AC")
    check(state_names:get(1) == "AC", "set mesmo tamanho")
    -- maior (desloca buffer)
    state_names:set(1, "Bahia")
    check(state_names:get(1) == "Bahia" and state_names:get(2) == "RJ" and state_names:get(3) == "MG",
          "set maior preserva vizinhos")
    -- menor
    state_names:set(1, "PB")
    check(state_names:get(1) == "PB" and state_names:get(3) == "MG", "set menor preserva vizinhos")
    -- set vazia
    state_names:set(2, "")
    check(state_names:get(2) == "" and not state_names:is_null(2), "set '' = vazia valida")
    -- set_null
    state_names:set_null(3)
    check(state_names:is_null(3), "set_null")
    check(state_names:get(1) == "PB", "set_null preserva vizinho")

    -- append (encadeável) e append de NA
    local appended_series = smaug.Series({}, "string")
    appended_series:append("um"):append("dois")
    appended_series:append(smaug.NA)
    appended_series:append("quatro")
    check(appended_series:len() == 4, "append len")
    check(appended_series:get(1) == "um" and appended_series:get(4) == "quatro", "append valores")
    check(appended_series:is_null(3), "append NA -> null")
    check(appended_series:count_nonnull() == 3, "count apos append com NA")
end

-- ===================================================================
-- clone independente
-- ===================================================================
do
    local original = smaug.Series({"alpha", smaug.NA, "gamma"}, "string")
    local cloned_series = original:clone()
    check(cloned_series:get(1) == "alpha" and cloned_series:is_null(2) and cloned_series:get(3) == "gamma",
          "clone copia conteudo")
    cloned_series:set(1, "MUDADO")
    check(cloned_series:get(1) == "MUDADO" and original:get(1) == "alpha", "clone independente")
end

-- ===================================================================
-- Sem coerção: set recusa não-string; ops numéricas recusam com erro claro
-- ===================================================================
do
    local letter_series = smaug.Series({"a", "b"}, "string")
    check(rejects(function() letter_series:set(1, 42) end), "set recusa numero")
    check(rejects(function() letter_series:set(1, true) end), "set recusa boolean")
    -- operações numéricas não se aplicam
    check(rejects(function() return letter_series:sum() end), "sum recusa string")
    check(rejects(function() return letter_series:mean() end), "mean recusa string")
    check(rejects(function() return letter_series:add(letter_series) end), "add recusa string")
end

-- ===================================================================
-- Integração com DataSet (coluna de string)
-- ===================================================================
do
    local dataset = smaug.DataSet({
        {"uf",  {"SP", "RJ", "MG"}, "string"},
        {"pop", {44, 17, 21},       "int64"},
    })
    check(dataset:nrows() == 3 and dataset:ncols() == 2, "dataset com coluna string")
    check(dataset:col("uf"):get(2) == "RJ", "acesso a coluna string")
    check(dataset:col("pop"):sum() == 82, "coluna numerica ao lado funciona")
end

-- ===================================================================
-- Comparações (eq/lt/gt) -> Series<bool>
-- ===================================================================
do
    local state_names = smaug.Series({"SP", "RJ", smaug.NA, "MG", "SP"}, "string")

    local equals_state_mask = state_names:eq("SP")
    check(equals_state_mask:get(1) == true and equals_state_mask:get(5) == true, "eq casa SP")
    check(equals_state_mask:get(2) == false, "eq nao casa RJ")
    check(equals_state_mask:get(3) == nil, "eq NULL -> nil")
    check(equals_state_mask:count_true() == 2, "eq count_true")

    local less_than_state_mask = state_names:lt("RJ")
    check(less_than_state_mask:get(4) == true, "lt: MG < RJ")
    check(less_than_state_mask:get(1) == false, "lt: SP nao < RJ")
    check(less_than_state_mask:get(3) == nil, "lt NULL -> nil")

    local greater_than_state_mask = state_names:gt("RJ")
    check(greater_than_state_mask:get(1) == true, "gt: SP > RJ")
    check(greater_than_state_mask:get(4) == false, "gt: MG nao > RJ")

    -- string vazia compara normalmente
    local with_empty_string = smaug.Series({"", "a"}, "string")
    check(with_empty_string:eq(""):get(1) == true, "eq '' casa vazia")
    check(with_empty_string:lt("a"):get(1) == true, "lt: '' < 'a'")

    -- recusa de tipo (sem coerção), nos dois sentidos
    check(rejects(function() return state_names:eq(42) end), "string:eq(numero) recusa")
    local number_series = smaug.Series({1, 2}, "int64")
    check(rejects(function() return number_series:eq("x") end), "int64:eq(string) recusa")
end

-- ===================================================================
-- Seleção: filter (por máscara de comparação) e take (por índices)
-- ===================================================================
do
    local state_names = smaug.Series({"SP", "RJ", smaug.NA, "MG", "SP"}, "string")

    -- o caso de uso principal: filter(eq)
    local filtered_state_series = state_names:filter(state_names:eq("SP"))
    check(filtered_state_series:len() == 2, "filter(eq SP) conta")
    check(filtered_state_series:get(1) == "SP" and filtered_state_series:get(2) == "SP", "filter(eq SP) valores")

    -- filter por lt (NULL nao passa)
    local filtered_less_than_series = state_names:filter(state_names:lt("RJ"))
    check(filtered_less_than_series:len() == 1 and filtered_less_than_series:get(1) == "MG", "filter(lt RJ) = MG")

    -- take reordenado, preserva NULL
    local reordered_series = state_names:take({4, 1, 3})
    check(reordered_series:len() == 3, "take conta")
    check(reordered_series:get(1) == "MG" and reordered_series:get(2) == "SP" and reordered_series:get(3) == nil,
          "take reordena e preserva NULL")

    -- take fora dos limites recusa
    check(rejects(function() return state_names:take({99}) end), "take fora-limites recusa")

    -- DataSet: filtrar linhas por coluna de texto, aplicar noutra coluna
    local dataset = smaug.DataSet({
        {"uf",  {"SP", "RJ", "SP"}, "string"},
        {"pop", {44, 17, 11},       "int64"},
    })
    local state_population = dataset:col("pop"):filter(dataset:col("uf"):eq("SP"))
    check(state_population:len() == 2 and state_population:get(1) == 44 and state_population:get(2) == 11,
          "filtrar dataset por coluna de texto")
end

-- ===================================================================
-- Ordenação: sort e argsort (lexicográfico; recusa NULL)
-- ===================================================================
do
    local state_names = smaug.Series({"MG", "AC", "SP", "BA", "AC"}, "string")

    local ascending_series = state_names:sort()
    check(ascending_series:get(1) == "AC" and ascending_series:get(2) == "AC" and ascending_series:get(3) == "BA"
          and ascending_series:get(4) == "MG" and ascending_series:get(5) == "SP", "sort ascendente")

    local descending_series = state_names:sort(false)
    check(descending_series:get(1) == "SP" and descending_series:get(5) == "AC", "sort descendente")

    -- argsort 1-based, permutação estável
    local indices = state_names:argsort()
    check(indices[1] == 2 and indices[2] == 5 and indices[5] == 3, "argsort 1-based estavel")

    -- vazia ordena primeiro
    local sorted_with_empty_string = smaug.Series({"b", "", "a"}, "string"):sort()
    check(sorted_with_empty_string:get(1) == "" and sorted_with_empty_string:get(2) == "a"
          and sorted_with_empty_string:get(3) == "b", "sort: vazia vem primeiro")

    -- NULL recusa (sort levanta erro; argsort retorna nil)
    local nullable_series = smaug.Series({"x", smaug.NA, "a"}, "string")
    check(rejects(function() return nullable_series:sort() end), "sort recusa NULL")
    check(nullable_series:argsort() == nil, "argsort com NULL -> nil")

    -- sort + take coerentes: ordenar e reordenar dá o mesmo
    local sorted_series = state_names:sort()
    check(sorted_series:len() == 5, "sort preserva tamanho")
end

-- =====================================================================
-- fillna / describe / astype para string
-- =====================================================================
local function test_string_filled_describe_astype()
    -- fillna: preenche NULL com string; mantém não-nulos intactos
    local state_codes = smaug.Series({"SP", smaug.NA, "RJ", smaug.NA}, "string", "uf")
    local filled_series = state_codes:fillna("?")
    check(filled_series:get(1) == "SP", "fillna string: não-nulo preservado")
    check(filled_series:get(2) == "?",  "fillna string: null preenchido")
    check(filled_series:get(3) == "RJ", "fillna string: não-nulo preservado 2")
    check(filled_series:get(4) == "?",  "fillna string: null preenchido 2")
    check(state_codes:is_null(2),            "fillna string: original imutável")

    -- fillna com tipo errado dá erro descritivo
    check(rejects(function() state_codes:fillna(0)   end), "fillna str+num -> erro")
    check(rejects(function() state_codes:fillna(nil) end), "fillna nil -> erro")

    -- describe: retorna count/nulls/unique/top/freq
    local description = state_codes:describe()
    check(description.count  == 2,    "describe str: count não-nulos")
    check(description.nulls  == 2,    "describe str: nulls")
    check(description.unique == 2,    "describe str: unique")
    check(description.top ~= nil,     "describe str: top existe")
    check(description.freq   >= 1,    "describe str: freq >= 1")

    -- describe: série com valor mais frequente
    local repeated_values = smaug.Series({"a","b","a","a","b"}, "string")
    local repeated_description = repeated_values:describe()
    check(repeated_description.top == "a" and repeated_description.freq == 3,
          "describe str: top/freq corretos")
    check(repeated_description.unique == 2, "describe str: unique 2 valores")

    -- describe: série toda NULL
    local all_null_series = smaug.Series({smaug.NA, smaug.NA}, "string")
    local all_null_description = all_null_series:describe()
    check(all_null_description.count == 0 and all_null_description.nulls == 2, "describe str: toda-null")
    check(all_null_description.top == nil and all_null_description.freq == nil,
          "describe str: top nil em toda-null")

    -- astype string → float64: parse numérico
    local numeric_text_series = smaug.Series({"1.5", "2.0", "abc", smaug.NA}, "string")
    local as_float64 = numeric_text_series:astype("float64")
    check(as_float64._dtype == "float64", "astype str->f64: dtype")
    check(as_float64:get(1) == 1.5,       "astype str->f64: valor")
    check(as_float64:get(2) == 2.0,       "astype str->f64: valor 2")
    check(as_float64:is_null(3),          "astype str->f64: parse inválido -> null")
    check(as_float64:is_null(4),          "astype str->f64: null preservado")

    -- astype string → int64
    local as_int64 = smaug.Series({"3", "7", "x"}, "string"):astype("int64")
    check(as_int64:get(1) == 3,  "astype str->i64: valor")
    check(as_int64:get(2) == 7,  "astype str->i64: valor 2")
    check(as_int64:is_null(3),   "astype str->i64: parse inválido -> null")

    -- astype float64 → string
    local as_string = smaug.Series({1.5, 0.0/0.0, smaug.NA}, "float64"):astype("string")
    check(as_string._dtype == "string", "astype f64->str: dtype")
    check(as_string:get(1) == "1.5",    "astype f64->str: valor")
    check(as_string:get(2) ~= nil,      "astype f64->str: NaN vira string (nao null)")
    check(as_string:is_null(3),         "astype f64->str: null preservado")

    -- astype int64 → string
    local integers_as_string = smaug.Series({10, 20, smaug.NA}, "int64"):astype("string")
    check(integers_as_string:get(1) == "10" and integers_as_string:get(2) == "20",
          "astype i64->str: valores")
    check(integers_as_string:is_null(3), "astype i64->str: null preservado")
end

test_string_filled_describe_astype()

-- =====================================================================
-- .str: len, lower, upper, strip, contains, startswith, endswith
-- =====================================================================
local function test_basic_string_accessor()
    local city_names = smaug.Series({"  Sao Paulo  ", "rio", smaug.NA, "MINAS"}, "string")

    -- len: comprimento em bytes; null -> null
    local string_lengths = city_names.str:len()
    check(string_lengths._dtype == "int64",  "str:len dtype int64")
    check(string_lengths:get(1) == 13,       "str:len espaços inclusos")
    check(string_lengths:get(2) == 3,        "str:len valor simples")
    check(string_lengths:is_null(3),         "str:len null -> null")
    check(string_lengths:get(4) == 5,        "str:len uppercase")

    -- lower: ASCII; null -> null
    local lowercase_series = city_names.str:lower()
    check(lowercase_series._dtype == "string", "str:lower dtype string")
    check(lowercase_series:get(2) == "rio",    "str:lower já minúsculo")
    check(lowercase_series:get(4) == "minas",  "str:lower uppercase -> lower")
    check(lowercase_series:is_null(3),         "str:lower null -> null")

    -- upper: ASCII; null -> null
    local uppercase_series = city_names.str:upper()
    check(uppercase_series:get(2) == "RIO",   "str:upper lower -> upper")
    check(uppercase_series:get(4) == "MINAS", "str:upper já maiúsculo")
    check(uppercase_series:is_null(3),        "str:upper null -> null")

    -- strip: remove espaços nas bordas; null -> null
    local stripped_series = city_names.str:strip()
    check(stripped_series:get(1) == "Sao Paulo", "str:strip remove bordas")
    check(stripped_series:get(2) == "rio",       "str:strip sem espaço: inalterado")
    check(stripped_series:is_null(3),            "str:strip null -> null")

    -- strip: string de só espaços vira ""
    local whitespace_series = smaug.Series({"   "}, "string")
    check(whitespace_series.str:strip():get(1) == "", "str:strip só espaços -> ''")

    -- contains: busca de substring; null -> NA
    local contains_suffix_mask = city_names.str:contains("ao")
    check(contains_suffix_mask:get(1) == true,  "str:contains match")
    check(contains_suffix_mask:get(2) == false, "str:contains no-match")
    check(contains_suffix_mask:is_null(3),      "str:contains null -> NA")

    -- contains: string vazia sempre true
    check(city_names.str:contains(""):get(2) == true, "str:contains '' sempre true")

    -- startswith; null -> NA
    local starts_with_prefix_mask = city_names.str:startswith("  S")
    check(starts_with_prefix_mask:get(1) == true,  "str:startswith match")
    check(starts_with_prefix_mask:get(2) == false, "str:startswith no-match")
    check(starts_with_prefix_mask:is_null(3),      "str:startswith null -> NA")

    -- startswith: prefixo vazio sempre true
    check(city_names.str:startswith(""):get(2) == true, "str:startswith '' sempre true")

    -- endswith; null -> NA
    local ends_with_suffix_mask = city_names.str:endswith("AS")
    check(ends_with_suffix_mask:get(4) == true,  "str:endswith match")
    check(ends_with_suffix_mask:get(2) == false, "str:endswith no-match")
    check(ends_with_suffix_mask:is_null(3),      "str:endswith null -> NA")

    -- endswith: sufixo vazio sempre true
    check(city_names.str:endswith(""):get(2) == true, "str:endswith '' sempre true")

    -- dtype errado dá erro descritivo
    local floating_point_series = smaug.Series({1.0, 2.0}, "float64")
    check(rejects(function() return floating_point_series.str:lower() end), "str em float64 -> erro")
    local integer_series = smaug.Series({1, 2}, "int64")
    check(rejects(function() return integer_series.str:len() end), "str em int64 -> erro")

    -- argumento de tipo errado
    check(rejects(function() city_names.str:contains(42)      end), "contains(num) -> erro")
    check(rejects(function() city_names.str:startswith(false)  end), "startswith(bool) -> erro")
    check(rejects(function() city_names.str:endswith(nil)      end), "endswith(nil) -> erro")

    -- integração: filter com .str:contains
    -- "tos" só ocorre em "Santos"; NA na máscara conta como false (descartado)
    local other_city_names = smaug.Series({"São Paulo", "Rio de Janeiro", "Santos", smaug.NA}, "string")
    local substring_mask = other_city_names.str:contains("tos")
    check(substring_mask:get(1) == false, "str:contains integração: SP false")
    check(substring_mask:get(3) == true,  "str:contains integração: Santos true")
    check(substring_mask:is_null(4),      "str:contains integração: null -> NA")
    local filtered_cities = other_city_names:filter(substring_mask)
    check(filtered_cities:len() == 1,         "filter com str:contains: 1 resultado")
    check(filtered_cities:get(1) == "Santos", "filter com str:contains: valor correto")
end

test_basic_string_accessor()

-- =====================================================================
-- .str:replace — substituição literal de substring
-- =====================================================================
local function test_literal_string_replacement()
    local sentences = smaug.Series({"foo bar foo", "hello", smaug.NA, "foo"}, "string")

    -- substituição básica
    local replaced_series = sentences.str:replace("foo", "baz")
    check(replaced_series:get(1) == "baz bar baz", "str:replace: todas as ocorrências")
    check(replaced_series:get(2) == "hello",       "str:replace: sem match: inalterado")
    check(replaced_series:is_null(3),              "str:replace: null -> null")
    check(replaced_series:get(4) == "baz",         "str:replace: ocorrência única")

    -- substituição por string vazia (remoção)
    local removed_substring_series = sentences.str:replace("foo", "")
    check(removed_substring_series:get(1) == " bar ", "str:replace: remove todas ocorrências")
    check(removed_substring_series:get(4) == "",      "str:replace: string vira vazia")

    -- old vazio: no-op (semântica indefinida -> cópia sem alterar)
    check(sentences.str:replace("", "x"):get(1) == "foo bar foo", "str:replace: old vazio -> no-op")

    -- metacaracteres Lua no old e new são tratados literalmente
    local metacharacter_series = smaug.Series({"a.b.c", "x+y", "2^3"}, "string")
    check(metacharacter_series.str:replace(".", "-"):get(1)    == "a-b-c",  "str:replace: '.' literal")
    check(metacharacter_series.str:replace("+", "plus"):get(2) == "xplusy", "str:replace: '+' literal")
    check(metacharacter_series.str:replace("^", ""):get(3)     == "23",     "str:replace: '^' literal")

    -- argumentos de tipo errado
    check(rejects(function() sentences.str:replace(1, "x")   end), "str:replace: old não-string -> erro")
    check(rejects(function() sentences.str:replace("x", nil) end), "str:replace: new nil -> erro")
end

test_literal_string_replacement()

-- =====================================================================
-- .str: find, slice, pad, zfill, rep, cat, split
-- =====================================================================
local function test_advanced_string_accessor()
    local sentences = smaug.Series({"hello world","foo bar","baz",smaug.NA}, "string")

    -- ================================================================
    -- find
    -- ================================================================
    local character_positions = sentences.str:find("o")
    check(character_positions:get(1) == 5,       "find 'o' em 'hello world' = 5")
    check(character_positions:get(2) == 2,       "find 'o' em 'foo bar' = 2")
    check(character_positions:get(3) == 0,       "find 'o' em 'baz' = 0 (ausente)")
    check(character_positions:is_null(4),        "find: NA propaga")
    check(character_positions._dtype == "int64", "find: dtype int64")

    -- find string vazia -> sempre 1 (string vazia encontrada no início)
    local empty_substring_positions = sentences.str:find("")
    check(empty_substring_positions:get(1) == 1, "find '': sempre 1")
    check(empty_substring_positions:get(3) == 1, "find '' em 'baz' = 1")

    -- find inexistente
    local missing_substring_positions = sentences.str:find("xyz")
    check(missing_substring_positions:get(1) == 0, "find 'xyz' = 0")
    check(missing_substring_positions:get(3) == 0, "find 'xyz' = 0")

    -- erro: não-string
    check(rejects(function() sentences.str:find(42) end), "find: erro não-string")

    -- ================================================================
    -- slice
    -- ================================================================
    local sliced_series = sentences.str:slice(1, 3)
    check(sliced_series:get(1) == "hel", "slice(1,3): 'hello world' -> 'hel'")
    check(sliced_series:get(2) == "foo", "slice(1,3): 'foo bar' -> 'foo'")
    check(sliced_series:get(3) == "baz", "slice(1,3): 'baz' -> 'baz'")
    check(sliced_series:is_null(4),      "slice: NA propaga")

    -- índice negativo
    local negative_slice = sentences.str:slice(-3)
    check(negative_slice:get(1) == "rld", "slice(-3): 'hello world' -> 'rld'")
    check(negative_slice:get(3) == "baz", "slice(-3): 'baz' -> 'baz'")

    -- slice além do tamanho (Lua retorna o que tiver)
    local beyond_length_slice = sentences.str:slice(1, 100)
    check(beyond_length_slice:get(1) == "hello world", "slice(1,100): retorna toda a string")

    -- sem stop: vai até o fim
    local open_ended_slice = sentences.str:slice(7)
    check(open_ended_slice:get(1) == "world", "slice(7): 'hello world' -> 'world'")

    -- série vazia
    local empty_series = smaug.Series({}, "string")
    check(empty_series.str:slice(1,3):len() == 0, "slice: série vazia -> vazia")

    -- ================================================================
    -- pad
    -- ================================================================
    local left_padded_series = sentences.str:pad(12, "left")
    check(left_padded_series:get(1) == " hello world", "pad(12,left): 1 espaço antes")
    check(left_padded_series:get(2) == "     foo bar", "pad(12,left): 5 espaços antes")
    check(left_padded_series:get(3) == "         baz", "pad(12,left): 9 espaços antes")
    check(left_padded_series:is_null(4),                "pad: NA propaga")
    check(left_padded_series._dtype == "string",        "pad: dtype string")

    local right_padded_series = sentences.str:pad(10, "right", "*")
    check(right_padded_series:get(3) == "baz*******", "pad(10,right,*): baz*******")

    local centered_series = sentences.str:pad(12, "both")
    check(#centered_series:get(2) == 12, "pad(12,both): comprimento total=12")

    -- string maior que width: retorna intacta
    local longer_than_width = sentences.str:pad(3, "left")
    check(longer_than_width:get(1) == "hello world", "pad: string maior não trunca")

    -- erros
    check(rejects(function() sentences.str:pad(-1) end),              "pad: width negativo recusado")
    check(rejects(function() sentences.str:pad(5, "left", "ab") end), "pad: fillchar >1 char recusado")
    check(rejects(function() sentences.str:pad(5, "centro") end),     "pad: side inválido recusado")

    -- ================================================================
    -- zfill
    -- ================================================================
    local numeric_strings = smaug.Series({"42","7","100","1000",smaug.NA}, "string")
    local zero_padded_series = numeric_strings.str:zfill(5)
    check(zero_padded_series:get(1) == "00042", "zfill(5): '42' -> '00042'")
    check(zero_padded_series:get(2) == "00007", "zfill(5): '7' -> '00007'")
    check(zero_padded_series:get(3) == "00100", "zfill(5): '100' -> '00100'")
    check(zero_padded_series:get(4) == "01000", "zfill(5): '1000' -> '01000' (5 chars total)")
    check(zero_padded_series:is_null(5),         "zfill: NA propaga")

    -- ================================================================
    -- rep
    -- ================================================================
    local short_strings = smaug.Series({"ab","x",smaug.NA}, "string")
    local twice_repeated_series = short_strings.str:rep(2)
    check(twice_repeated_series:get(1) == "abab", "rep(2): 'ab' -> 'abab'")
    check(twice_repeated_series:get(2) == "xx",   "rep(2): 'x' -> 'xx'")
    check(twice_repeated_series:is_null(3),       "rep: NA propaga")

    local separator_repeated_series = short_strings.str:rep(2, "-")
    check(separator_repeated_series:get(1) == "ab-ab", "rep(2,'-'): 'ab' -> 'ab-ab'")
    check(separator_repeated_series:get(2) == "x-x",   "rep(2,'-'): 'x' -> 'x-x'")

    local zero_repeated_series = short_strings.str:rep(0)
    check(zero_repeated_series:get(1) == "", "rep(0): string vazia")

    -- erro: n < 0
    check(rejects(function() short_strings.str:rep(-1) end), "rep: n<0 recusado")

    -- ================================================================
    -- cat
    -- ================================================================
    local comma_concatenated_series = sentences.str:cat(", ")
    check(comma_concatenated_series == "hello world, foo bar, baz", "cat: NA ignorado, sep correto")

    local directly_concatenated_series = sentences.str:cat()
    check(directly_concatenated_series == "hello worldfoo barbaz", "cat sem sep")

    -- todos NA
    local all_null_series = smaug.Series({smaug.NA, smaug.NA}, "string")
    check(all_null_series.str:cat() == "", "cat: todos NA -> string vazia")

    -- série vazia
    check(empty_series.str:cat() == "", "cat: série vazia -> string vazia")

    -- ================================================================
    -- split
    -- ================================================================
    local csv_rows = smaug.Series({"a:b:c","x:y","z",smaug.NA}, "string")
    local columns = csv_rows.str:split(":")

    check(#columns == 3,             "split: 3 colunas (max partes)")
    check(columns[1]:get(1) == "a", "split col1[1] = a")
    check(columns[2]:get(1) == "b", "split col2[1] = b")
    check(columns[3]:get(1) == "c", "split col3[1] = c")
    check(columns[1]:get(2) == "x", "split col1[2] = x")
    check(columns[2]:get(2) == "y", "split col2[2] = y")
    check(columns[3]:is_null(2),    "split: col3[2] = NA (sem terceira parte)")
    check(columns[1]:get(3) == "z", "split col1[3] = z (sem sep)")
    check(columns[2]:is_null(3),    "split: col2[3] = NA (sem segunda parte)")
    check(columns[1]:is_null(4),    "split: col1[4] = NA (entrada NA)")

    -- separador multi-char
    local double_separator_rows = smaug.Series({"a::b::c","x::y"}, "string")
    local double_separator_columns = double_separator_rows.str:split("::")
    check(double_separator_columns[1]:get(1) == "a", "split '::' col1 = a")
    check(double_separator_columns[2]:get(1) == "b", "split '::' col2 = b")
    check(double_separator_columns[3]:get(1) == "c", "split '::' col3 = c")

    -- max_splits
    local limited_split_row = smaug.Series({"a:b:c:d"}, "string")
    local limited_split_columns = limited_split_row.str:split(":", 2)
    check(#limited_split_columns == 3,             "split max=2: 3 partes")
    check(limited_split_columns[1]:get(1) == "a", "split max=2 [1]=a")
    check(limited_split_columns[2]:get(1) == "b", "split max=2 [2]=b")
    check(limited_split_columns[3]:get(1) == "c:d", "split max=2 [3]=c:d (resto)")

    -- nenhum match: 1 coluna com a string original
    local without_separator = smaug.Series({"abc","def"}, "string")
    local unmatched_columns = without_separator.str:split(",")
    check(#unmatched_columns == 1,              "split sem match: 1 coluna")
    check(unmatched_columns[1]:get(1) == "abc", "split sem match: valor original")

    -- série vazia
    local empty_split_series = empty_series.str:split(":")
    check(#empty_split_series == 0, "split série vazia: 0 colunas")

    -- erro: sep vazio
    check(rejects(function() sentences.str:split("") end), "split: sep vazio recusado")
end

test_advanced_string_accessor()

-- =====================================================================
-- .str: count, predicados ASCII, removeprefix/removesuffix,
-- capitalize/title/swapcase, join, e view de string (COW)
-- =====================================================================
local function test_string_accessor_extras()
    -- ================================================================
    -- count — ocorrências literais não-sobrepostas
    -- ================================================================
    local character_texts = smaug.Series({"banana", "aaaa", "xyz", "", smaug.NA}, "string")
    local single_character_counts = character_texts.str:count("a")
    check(single_character_counts._dtype == "int64", "count → int64")
    check(single_character_counts:get(1) == 3,       "count 'a' em banana = 3")
    check(single_character_counts:get(2) == 4,       "count 'a' em aaaa = 4")
    check(single_character_counts:get(3) == 0,       "count 'a' em xyz = 0")
    check(single_character_counts:get(4) == 0,       "count 'a' em vazia = 0")
    check(single_character_counts:get(5) == nil,     "count NA → nil")

    -- não-sobreposto: "aa" em "aaaa" = 2 (não 3)
    local double_character_counts = character_texts.str:count("aa")
    check(double_character_counts:get(2) == 2, "count 'aa' em aaaa = 2 (não-sobreposto)")
    check(double_character_counts:get(1) == 0, "count 'aa' em banana = 0 (a's não-adjacentes)")

    -- substring multichar
    local repeated_text = smaug.Series({"abcabcabc"}, "string")
    check(repeated_text.str:count("abc"):get(1) == 3, "count 'abc' = 3")

    -- sub vazio → erro
    check(rejects(function() character_texts.str:count("") end), "count substring vazia = erro")
    -- não-string → erro
    check(rejects(function() character_texts.str:count(5) end), "count não-string = erro")

    -- ================================================================
    -- Predicados ASCII — string vazia sempre false; null → nil
    -- ================================================================
    local varied_texts = smaug.Series({
        "abc123",  -- 1: alnum
        "abc",     -- 2: alpha, lower
        "123",     -- 3: digit
        "   ",     -- 4: space
        "ABC",     -- 5: alpha, upper
        "abC",     -- 6: alpha, misto
        "",        -- 7: vazia
        smaug.NA,  -- 8: null
    }, "string")

    local alphanumeric_mask = varied_texts.str:isalnum()
    check(alphanumeric_mask._dtype == "bool", "isalnum → bool")
    check(alphanumeric_mask:get(1) == true,   "isalnum abc123 → true")
    check(alphanumeric_mask:get(4) == false,  "isalnum espaços → false")
    check(alphanumeric_mask:get(7) == false,  "isalnum vazia → false")
    check(alphanumeric_mask:get(8) == nil,    "isalnum NA → nil")

    local alphabetic_mask = varied_texts.str:isalpha()
    check(alphabetic_mask:get(1) == false, "isalpha abc123 → false (tem dígitos)")
    check(alphabetic_mask:get(2) == true,  "isalpha abc → true")
    check(alphabetic_mask:get(7) == false, "isalpha vazia → false")

    local digit_mask = varied_texts.str:isdigit()
    check(digit_mask:get(3) == true,  "isdigit 123 → true")
    check(digit_mask:get(1) == false, "isdigit abc123 → false")
    check(digit_mask:get(7) == false, "isdigit vazia → false")

    local whitespace_mask = varied_texts.str:isspace()
    check(whitespace_mask:get(4) == true,  "isspace '   ' → true")
    check(whitespace_mask:get(2) == false, "isspace abc → false")
    check(whitespace_mask:get(7) == false, "isspace vazia → false")

    local lowercase_mask = varied_texts.str:islower()
    check(lowercase_mask:get(2) == true,  "islower abc → true")
    check(lowercase_mask:get(5) == false, "islower ABC → false")
    check(lowercase_mask:get(6) == false, "islower abC → false (tem maiúscula)")
    check(lowercase_mask:get(3) == false, "islower 123 → false (sem letras)")
    check(lowercase_mask:get(7) == false, "islower vazia → false")

    local uppercase_mask = varied_texts.str:isupper()
    check(uppercase_mask:get(5) == true,  "isupper ABC → true")
    check(uppercase_mask:get(2) == false, "isupper abc → false")
    check(uppercase_mask:get(6) == false, "isupper abC → false (tem minúscula)")
    check(uppercase_mask:get(3) == false, "isupper 123 → false (sem letras)")

    -- isspace com tab/newline
    local special_whitespace_series = smaug.Series({"\t\n", " \t ", "a b"}, "string")
    check(special_whitespace_series.str:isspace():get(1) == true,  "isspace tab+newline → true")
    check(special_whitespace_series.str:isspace():get(3) == false, "isspace 'a b' → false")

    -- ================================================================
    -- removeprefix / removesuffix — idempotente
    -- ================================================================
    local prefix_suffix_series = smaug.Series({"unhappy", "happy", "test.lua", "test", smaug.NA}, "string")

    local without_prefix = prefix_suffix_series.str:removeprefix("un")
    check(without_prefix._dtype == "string", "removeprefix → string")
    check(without_prefix:get(1) == "happy",  "removeprefix un de unhappy → happy")
    check(without_prefix:get(2) == "happy",  "removeprefix un de happy → happy (idempotente)")
    check(without_prefix:get(5) == nil,      "removeprefix NA → nil")

    local without_suffix = prefix_suffix_series.str:removesuffix(".lua")
    check(without_suffix:get(3) == "test", "removesuffix .lua de test.lua → test")
    check(without_suffix:get(4) == "test", "removesuffix .lua de test → test (idempotente)")

    -- prefixo/sufixo vazio → cópia inalterada
    check(prefix_suffix_series.str:removeprefix(""):get(1) == "unhappy", "removeprefix vazio → inalterado")
    check(prefix_suffix_series.str:removesuffix(""):get(1) == "unhappy", "removesuffix vazio → inalterado")

    -- prefixo maior que a string
    local short_text = smaug.Series({"ab"}, "string")
    check(short_text.str:removeprefix("abcdef"):get(1) == "ab", "removeprefix maior → inalterado")

    -- não-string → erro
    check(rejects(function() prefix_suffix_series.str:removeprefix(5) end), "removeprefix não-string = erro")

    -- ================================================================
    -- capitalize / title / swapcase
    -- ================================================================
    local mixed_case_texts = smaug.Series({"hello WORLD", "foo bar baz", "aBcD", "", smaug.NA}, "string")

    local capitalized_series = mixed_case_texts.str:capitalize()
    check(capitalized_series:get(1) == "Hello world", "capitalize hello WORLD → Hello world")
    check(capitalized_series:get(3) == "Abcd",        "capitalize aBcD → Abcd")
    check(capitalized_series:get(4) == "",            "capitalize vazia → vazia")
    check(capitalized_series:get(5) == nil,           "capitalize NA → nil")

    local title_case_series = mixed_case_texts.str:title()
    check(title_case_series:get(1) == "Hello World", "title hello WORLD → Hello World")
    check(title_case_series:get(2) == "Foo Bar Baz", "title foo bar baz → Foo Bar Baz")
    check(title_case_series:get(3) == "Abcd",        "title aBcD → Abcd")

    -- title com separadores não-letra
    local varied_separator_series = smaug.Series({"a-b c.d", "joão123silva"}, "string")
    check(varied_separator_series.str:title():get(1) == "A-B C.D", "title com hífen/ponto/espaço")
    -- 'joão' tem byte não-ASCII (ã); título trata cada letra ASCII; verifica que ç/ã não quebram
    check(type(varied_separator_series.str:title():get(2)) == "string", "title com não-ASCII não quebra")

    local swapped_case_series = mixed_case_texts.str:swapcase()
    check(swapped_case_series:get(1) == "HELLO world", "swapcase hello WORLD → HELLO world")
    check(swapped_case_series:get(3) == "AbCd",        "swapcase aBcD → AbCd")

    -- ================================================================
    -- join (atalho de cat)
    -- ================================================================
    local words = smaug.Series({"a", "b", smaug.NA, "c"}, "string")
    check(words.str:join("-") == "a-b-c", "join '-' ignora nulos")
    check(words.str:join("") == "abc",    "join '' concatena")
    check(words.str:join("-") == words.str:cat("-"), "join idêntico a cat")

    -- série vazia
    local empty_words = smaug.Series({}, "string")
    check(empty_words.str:join(",") == "", "join série vazia → vazia")

    -- view de string agora suportada (9.2): zero-copy na leitura, COW na escrita
    local state_names = smaug.Series({"SP", "RJ", "MG"}, "string")
    local state_window = state_names:view(1, 2)                  -- [SP, RJ]
    check(state_window:len() == 2, "string view: janela com len correto")
    check(state_window:get(1) == "SP" and state_window:get(2) == "RJ",
          "string view: lê o pai (zero-copy)")
    state_window:set(1, "SAOPAULO")                          -- dispara COW detach
    check(state_window:get(1) == "SAOPAULO", "string view: set reflete na view")
    check(state_names:get(1) == "SP",              "string view: pai intacto após COW")
    check(state_names:take({1, 2}):len() == 2,     "string take: cópia independente também funciona")
end

test_string_accessor_extras()

-- ================================================================
-- Resultado
-- ================================================================

print(string.format("OK — %d checks passaram (Series: .str completo)", passed_checks))
