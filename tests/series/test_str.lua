-- tests/series/test_str.lua
-- Accessor .str completo: construção/mutação/clone, comparações, seleção,
-- ordenação, fillna/describe/astype, e todos os métodos de .str (len, lower,
-- upper, strip, contains, startswith, endswith, replace, find, slice, pad,
-- zfill, rep, cat, split, count, predicados ASCII, removeprefix/removesuffix,
-- capitalize/title/swapcase, join) e integração com DataSet.
-- Rode da raiz: luajit tests/series/test_str.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")

local total_checks_ok = 0
local function check(condition, message)
    if not condition then error("FALHOU: " .. message, 2) end
    total_checks_ok = total_checks_ok + 1
end

local function rejects(fn) return pcall(fn) == false end

-- ===================================================================
-- Construção e acesso
-- ===================================================================
do
    local estados = smaug.Series({"SP", "RJ", smaug.NA, "Minas"}, "string")
    check(estados:len() == 4, "len")
    check(estados:get(1) == "SP", "get string")
    check(estados:get(4) == "Minas", "get string longa")
    check(estados:get(3) == nil, "get NA -> nil")
    check(estados:is_null(3), "is_null no NA")
    check(not estados:is_null(1), "is_null false em valido")
    check(estados:count_nonnull() == 3, "count_nonnull")
end

-- ===================================================================
-- String vazia é distinta de NULL
-- ===================================================================
do
    local com_vazia = smaug.Series({"", smaug.NA, "x"}, "string")
    check(com_vazia:get(1) == "", "vazia -> '' (nao nil)")
    check(not com_vazia:is_null(1), "vazia nao e null")
    check(com_vazia:get(2) == nil, "NA -> nil")
    check(com_vazia:is_null(2), "NA e null")
    check(com_vazia:count_nonnull() == 2, "vazia conta como valida")
end

-- ===================================================================
-- Mutação: set (3 casos via backend), set_null, append
-- ===================================================================
do
    local estados = smaug.Series({"SP", "RJ", "MG"}, "string")
    -- mesmo tamanho
    estados:set(1, "AC")
    check(estados:get(1) == "AC", "set mesmo tamanho")
    -- maior (desloca buffer)
    estados:set(1, "Bahia")
    check(estados:get(1) == "Bahia" and estados:get(2) == "RJ" and estados:get(3) == "MG",
          "set maior preserva vizinhos")
    -- menor
    estados:set(1, "PB")
    check(estados:get(1) == "PB" and estados:get(3) == "MG", "set menor preserva vizinhos")
    -- set vazia
    estados:set(2, "")
    check(estados:get(2) == "" and not estados:is_null(2), "set '' = vazia valida")
    -- set_null
    estados:set_null(3)
    check(estados:is_null(3), "set_null")
    check(estados:get(1) == "PB", "set_null preserva vizinho")

    -- append (encadeável) e append de NA
    local acumulada = smaug.Series.string(0)
    acumulada:append("um"):append("dois")
    acumulada:append(smaug.NA)
    acumulada:append("quatro")
    check(acumulada:len() == 4, "append len")
    check(acumulada:get(1) == "um" and acumulada:get(4) == "quatro", "append valores")
    check(acumulada:is_null(3), "append NA -> null")
    check(acumulada:count_nonnull() == 3, "count apos append com NA")
end

-- ===================================================================
-- clone independente
-- ===================================================================
do
    local original = smaug.Series({"alpha", smaug.NA, "gamma"}, "string")
    local copia = original:clone()
    check(copia:get(1) == "alpha" and copia:is_null(2) and copia:get(3) == "gamma",
          "clone copia conteudo")
    copia:set(1, "MUDADO")
    check(copia:get(1) == "MUDADO" and original:get(1) == "alpha", "clone independente")
end

-- ===================================================================
-- Sem coerção: set recusa não-string; ops numéricas recusam com erro claro
-- ===================================================================
do
    local letras = smaug.Series({"a", "b"}, "string")
    check(rejects(function() letras:set(1, 42) end), "set recusa numero")
    check(rejects(function() letras:set(1, true) end), "set recusa boolean")
    -- operações numéricas não se aplicam
    check(rejects(function() return letras:sum() end), "sum recusa string")
    check(rejects(function() return letras:mean() end), "mean recusa string")
    check(rejects(function() return letras:add(letras) end), "add recusa string")
end

-- ===================================================================
-- Integração com DataSet (coluna de string)
-- ===================================================================
do
    local dataset = smaug.DataSet.from_columns({
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
    local estados = smaug.Series({"SP", "RJ", smaug.NA, "MG", "SP"}, "string")

    local igual_sp = estados:eq("SP")
    check(igual_sp:get(1) == true and igual_sp:get(5) == true, "eq casa SP")
    check(igual_sp:get(2) == false, "eq nao casa RJ")
    check(igual_sp:get(3) == nil, "eq NULL -> nil")
    check(igual_sp:count_true() == 2, "eq count_true")

    local menor_que_rj = estados:lt("RJ")
    check(menor_que_rj:get(4) == true, "lt: MG < RJ")
    check(menor_que_rj:get(1) == false, "lt: SP nao < RJ")
    check(menor_que_rj:get(3) == nil, "lt NULL -> nil")

    local maior_que_rj = estados:gt("RJ")
    check(maior_que_rj:get(1) == true, "gt: SP > RJ")
    check(maior_que_rj:get(4) == false, "gt: MG nao > RJ")

    -- string vazia compara normalmente
    local com_vazia = smaug.Series({"", "a"}, "string")
    check(com_vazia:eq(""):get(1) == true, "eq '' casa vazia")
    check(com_vazia:lt("a"):get(1) == true, "lt: '' < 'a'")

    -- recusa de tipo (sem coerção), nos dois sentidos
    check(rejects(function() return estados:eq(42) end), "string:eq(numero) recusa")
    local numeros = smaug.Series({1, 2}, "int64")
    check(rejects(function() return numeros:eq("x") end), "int64:eq(string) recusa")
end

-- ===================================================================
-- Seleção: filter (por máscara de comparação) e take (por índices)
-- ===================================================================
do
    local estados = smaug.Series({"SP", "RJ", smaug.NA, "MG", "SP"}, "string")

    -- o caso de uso principal: filter(eq)
    local filtrado_sp = estados:filter(estados:eq("SP"))
    check(filtrado_sp:len() == 2, "filter(eq SP) conta")
    check(filtrado_sp:get(1) == "SP" and filtrado_sp:get(2) == "SP", "filter(eq SP) valores")

    -- filter por lt (NULL nao passa)
    local filtrado_lt = estados:filter(estados:lt("RJ"))
    check(filtrado_lt:len() == 1 and filtrado_lt:get(1) == "MG", "filter(lt RJ) = MG")

    -- take reordenado, preserva NULL
    local reordenado = estados:take({4, 1, 3})
    check(reordenado:len() == 3, "take conta")
    check(reordenado:get(1) == "MG" and reordenado:get(2) == "SP" and reordenado:get(3) == nil,
          "take reordena e preserva NULL")

    -- take fora dos limites recusa
    check(rejects(function() return estados:take({99}) end), "take fora-limites recusa")

    -- DataSet: filtrar linhas por coluna de texto, aplicar noutra coluna
    local dataset = smaug.DataSet.from_columns({
        {"uf",  {"SP", "RJ", "SP"}, "string"},
        {"pop", {44, 17, 11},       "int64"},
    })
    local pop_sp = dataset:col("pop"):filter(dataset:col("uf"):eq("SP"))
    check(pop_sp:len() == 2 and pop_sp:get(1) == 44 and pop_sp:get(2) == 11,
          "filtrar dataset por coluna de texto")
end

-- ===================================================================
-- Ordenação: sort e argsort (lexicográfico; recusa NULL)
-- ===================================================================
do
    local estados = smaug.Series({"MG", "AC", "SP", "BA", "AC"}, "string")

    local crescente = estados:sort()
    check(crescente:get(1) == "AC" and crescente:get(2) == "AC" and crescente:get(3) == "BA"
          and crescente:get(4) == "MG" and crescente:get(5) == "SP", "sort ascendente")

    local decrescente = estados:sort(false)
    check(decrescente:get(1) == "SP" and decrescente:get(5) == "AC", "sort descendente")

    -- argsort 1-based, permutação estável
    local indices = estados:argsort()
    check(indices[1] == 2 and indices[2] == 5 and indices[5] == 3, "argsort 1-based estavel")

    -- vazia ordena primeiro
    local ordenada_com_vazia = smaug.Series({"b", "", "a"}, "string"):sort()
    check(ordenada_com_vazia:get(1) == "" and ordenada_com_vazia:get(2) == "a"
          and ordenada_com_vazia:get(3) == "b", "sort: vazia vem primeiro")

    -- NULL recusa (sort levanta erro; argsort retorna nil)
    local com_null = smaug.Series({"x", smaug.NA, "a"}, "string")
    check(rejects(function() return com_null:sort() end), "sort recusa NULL")
    check(com_null:argsort() == nil, "argsort com NULL -> nil")

    -- sort + take coerentes: ordenar e reordenar dá o mesmo
    local ordenado = estados:sort()
    check(ordenado:len() == 5, "sort preserva tamanho")
end

-- =====================================================================
-- fillna / describe / astype para string
-- =====================================================================
local function test_string_fillna_describe_astype()
    -- fillna: preenche NULL com string; mantém não-nulos intactos
    local ufs = smaug.Series({"SP", smaug.NA, "RJ", smaug.NA}, "string", "uf")
    local preenchida = ufs:fillna("?")
    check(preenchida:get(1) == "SP", "fillna string: não-nulo preservado")
    check(preenchida:get(2) == "?",  "fillna string: null preenchido")
    check(preenchida:get(3) == "RJ", "fillna string: não-nulo preservado 2")
    check(preenchida:get(4) == "?",  "fillna string: null preenchido 2")
    check(ufs:is_null(2),            "fillna string: original imutável")

    -- fillna com tipo errado dá erro descritivo
    check(rejects(function() ufs:fillna(0)   end), "fillna str+num -> erro")
    check(rejects(function() ufs:fillna(nil) end), "fillna nil -> erro")

    -- describe: retorna count/nulls/unique/top/freq
    local descricao = ufs:describe()
    check(descricao.count  == 2,    "describe str: count não-nulos")
    check(descricao.nulls  == 2,    "describe str: nulls")
    check(descricao.unique == 2,    "describe str: unique")
    check(descricao.top ~= nil,     "describe str: top existe")
    check(descricao.freq   >= 1,    "describe str: freq >= 1")

    -- describe: série com valor mais frequente
    local repetidas = smaug.Series({"a","b","a","a","b"}, "string")
    local descricao_repetidas = repetidas:describe()
    check(descricao_repetidas.top == "a" and descricao_repetidas.freq == 3,
          "describe str: top/freq corretos")
    check(descricao_repetidas.unique == 2, "describe str: unique 2 valores")

    -- describe: série toda NULL
    local toda_null = smaug.Series({smaug.NA, smaug.NA}, "string")
    local descricao_toda_null = toda_null:describe()
    check(descricao_toda_null.count == 0 and descricao_toda_null.nulls == 2, "describe str: toda-null")
    check(descricao_toda_null.top == nil and descricao_toda_null.freq == nil,
          "describe str: top nil em toda-null")

    -- astype string → float64: parse numérico
    local textos_numericos = smaug.Series({"1.5", "2.0", "abc", smaug.NA}, "string")
    local como_float64 = textos_numericos:astype("float64")
    check(como_float64._dtype == "float64", "astype str->f64: dtype")
    check(como_float64:get(1) == 1.5,       "astype str->f64: valor")
    check(como_float64:get(2) == 2.0,       "astype str->f64: valor 2")
    check(como_float64:is_null(3),          "astype str->f64: parse inválido -> null")
    check(como_float64:is_null(4),          "astype str->f64: null preservado")

    -- astype string → int64
    local como_int64 = smaug.Series({"3", "7", "x"}, "string"):astype("int64")
    check(como_int64:get(1) == 3,  "astype str->i64: valor")
    check(como_int64:get(2) == 7,  "astype str->i64: valor 2")
    check(como_int64:is_null(3),   "astype str->i64: parse inválido -> null")

    -- astype float64 → string
    local como_string = smaug.Series({1.5, 0.0/0.0, smaug.NA}, "float64"):astype("string")
    check(como_string._dtype == "string", "astype f64->str: dtype")
    check(como_string:get(1) == "1.5",    "astype f64->str: valor")
    check(como_string:get(2) ~= nil,      "astype f64->str: NaN vira string (nao null)")
    check(como_string:is_null(3),         "astype f64->str: null preservado")

    -- astype int64 → string
    local inteiros_como_string = smaug.Series({10, 20, smaug.NA}, "int64"):astype("string")
    check(inteiros_como_string:get(1) == "10" and inteiros_como_string:get(2) == "20",
          "astype i64->str: valores")
    check(inteiros_como_string:is_null(3), "astype i64->str: null preservado")
end

test_string_fillna_describe_astype()

-- =====================================================================
-- .str: len, lower, upper, strip, contains, startswith, endswith
-- =====================================================================
local function test_str_accessor_basico()
    local cidades = smaug.Series({"  Sao Paulo  ", "rio", smaug.NA, "MINAS"}, "string")

    -- len: comprimento em bytes; null -> null
    local comprimentos = cidades.str:len()
    check(comprimentos._dtype == "int64",  "str:len dtype int64")
    check(comprimentos:get(1) == 13,       "str:len espaços inclusos")
    check(comprimentos:get(2) == 3,        "str:len valor simples")
    check(comprimentos:is_null(3),         "str:len null -> null")
    check(comprimentos:get(4) == 5,        "str:len uppercase")

    -- lower: ASCII; null -> null
    local minusculas = cidades.str:lower()
    check(minusculas._dtype == "string", "str:lower dtype string")
    check(minusculas:get(2) == "rio",    "str:lower já minúsculo")
    check(minusculas:get(4) == "minas",  "str:lower uppercase -> lower")
    check(minusculas:is_null(3),         "str:lower null -> null")

    -- upper: ASCII; null -> null
    local maiusculas = cidades.str:upper()
    check(maiusculas:get(2) == "RIO",   "str:upper lower -> upper")
    check(maiusculas:get(4) == "MINAS", "str:upper já maiúsculo")
    check(maiusculas:is_null(3),        "str:upper null -> null")

    -- strip: remove espaços nas bordas; null -> null
    local sem_bordas = cidades.str:strip()
    check(sem_bordas:get(1) == "Sao Paulo", "str:strip remove bordas")
    check(sem_bordas:get(2) == "rio",       "str:strip sem espaço: inalterado")
    check(sem_bordas:is_null(3),            "str:strip null -> null")

    -- strip: string de só espaços vira ""
    local so_espacos = smaug.Series({"   "}, "string")
    check(so_espacos.str:strip():get(1) == "", "str:strip só espaços -> ''")

    -- contains: busca de substring; null -> NA
    local contem_ao = cidades.str:contains("ao")
    check(contem_ao:get(1) == true,  "str:contains match")
    check(contem_ao:get(2) == false, "str:contains no-match")
    check(contem_ao:is_null(3),      "str:contains null -> NA")

    -- contains: string vazia sempre true
    check(cidades.str:contains(""):get(2) == true, "str:contains '' sempre true")

    -- startswith; null -> NA
    local comeca_com_s = cidades.str:startswith("  S")
    check(comeca_com_s:get(1) == true,  "str:startswith match")
    check(comeca_com_s:get(2) == false, "str:startswith no-match")
    check(comeca_com_s:is_null(3),      "str:startswith null -> NA")

    -- startswith: prefixo vazio sempre true
    check(cidades.str:startswith(""):get(2) == true, "str:startswith '' sempre true")

    -- endswith; null -> NA
    local termina_com_as = cidades.str:endswith("AS")
    check(termina_com_as:get(4) == true,  "str:endswith match")
    check(termina_com_as:get(2) == false, "str:endswith no-match")
    check(termina_com_as:is_null(3),      "str:endswith null -> NA")

    -- endswith: sufixo vazio sempre true
    check(cidades.str:endswith(""):get(2) == true, "str:endswith '' sempre true")

    -- dtype errado dá erro descritivo
    local numeros_float = smaug.Series({1.0, 2.0}, "float64")
    check(rejects(function() return numeros_float.str:lower() end), "str em float64 -> erro")
    local numeros_int = smaug.Series({1, 2}, "int64")
    check(rejects(function() return numeros_int.str:len() end), "str em int64 -> erro")

    -- argumento de tipo errado
    check(rejects(function() cidades.str:contains(42)      end), "contains(num) -> erro")
    check(rejects(function() cidades.str:startswith(false)  end), "startswith(bool) -> erro")
    check(rejects(function() cidades.str:endswith(nil)      end), "endswith(nil) -> erro")

    -- integração: filter com .str:contains
    -- "tos" só ocorre em "Santos"; NA na máscara conta como false (descartado)
    local outras_cidades = smaug.Series({"São Paulo", "Rio de Janeiro", "Santos", smaug.NA}, "string")
    local mascara_tos = outras_cidades.str:contains("tos")
    check(mascara_tos:get(1) == false, "str:contains integração: SP false")
    check(mascara_tos:get(3) == true,  "str:contains integração: Santos true")
    check(mascara_tos:is_null(4),      "str:contains integração: null -> NA")
    local cidades_filtradas = outras_cidades:filter(mascara_tos)
    check(cidades_filtradas:len() == 1,         "filter com str:contains: 1 resultado")
    check(cidades_filtradas:get(1) == "Santos", "filter com str:contains: valor correto")
end

test_str_accessor_basico()

-- =====================================================================
-- .str:replace — substituição literal de substring
-- =====================================================================
local function test_str_replace_substituicao_literal()
    local frases = smaug.Series({"foo bar foo", "hello", smaug.NA, "foo"}, "string")

    -- substituição básica
    local substituida = frases.str:replace("foo", "baz")
    check(substituida:get(1) == "baz bar baz", "str:replace: todas as ocorrências")
    check(substituida:get(2) == "hello",       "str:replace: sem match: inalterado")
    check(substituida:is_null(3),              "str:replace: null -> null")
    check(substituida:get(4) == "baz",         "str:replace: ocorrência única")

    -- substituição por string vazia (remoção)
    local removida = frases.str:replace("foo", "")
    check(removida:get(1) == " bar ", "str:replace: remove todas ocorrências")
    check(removida:get(4) == "",      "str:replace: string vira vazia")

    -- old vazio: no-op (semântica indefinida -> cópia sem alterar)
    check(frases.str:replace("", "x"):get(1) == "foo bar foo", "str:replace: old vazio -> no-op")

    -- metacaracteres Lua no old e new são tratados literalmente
    local com_metacaracteres = smaug.Series({"a.b.c", "x+y", "2^3"}, "string")
    check(com_metacaracteres.str:replace(".", "-"):get(1)    == "a-b-c",  "str:replace: '.' literal")
    check(com_metacaracteres.str:replace("+", "plus"):get(2) == "xplusy", "str:replace: '+' literal")
    check(com_metacaracteres.str:replace("^", ""):get(3)     == "23",     "str:replace: '^' literal")

    -- argumentos de tipo errado
    check(rejects(function() frases.str:replace(1, "x")   end), "str:replace: old não-string -> erro")
    check(rejects(function() frases.str:replace("x", nil) end), "str:replace: new nil -> erro")
end

test_str_replace_substituicao_literal()

-- =====================================================================
-- .str: find, slice, pad, zfill, rep, cat, split
-- =====================================================================
local function test_str_accessor_avancado()
    local frases = smaug.Series({"hello world","foo bar","baz",smaug.NA}, "string")

    -- ================================================================
    -- find
    -- ================================================================
    local posicao_o = frases.str:find("o")
    check(posicao_o:get(1) == 5,       "find 'o' em 'hello world' = 5")
    check(posicao_o:get(2) == 2,       "find 'o' em 'foo bar' = 2")
    check(posicao_o:get(3) == 0,       "find 'o' em 'baz' = 0 (ausente)")
    check(posicao_o:is_null(4),        "find: NA propaga")
    check(posicao_o._dtype == "int64", "find: dtype int64")

    -- find string vazia -> sempre 1 (string vazia encontrada no início)
    local posicao_vazia = frases.str:find("")
    check(posicao_vazia:get(1) == 1, "find '': sempre 1")
    check(posicao_vazia:get(3) == 1, "find '' em 'baz' = 1")

    -- find inexistente
    local posicao_inexistente = frases.str:find("xyz")
    check(posicao_inexistente:get(1) == 0, "find 'xyz' = 0")
    check(posicao_inexistente:get(3) == 0, "find 'xyz' = 0")

    -- erro: não-string
    check(rejects(function() frases.str:find(42) end), "find: erro não-string")

    -- ================================================================
    -- slice
    -- ================================================================
    local recorte = frases.str:slice(1, 3)
    check(recorte:get(1) == "hel", "slice(1,3): 'hello world' -> 'hel'")
    check(recorte:get(2) == "foo", "slice(1,3): 'foo bar' -> 'foo'")
    check(recorte:get(3) == "baz", "slice(1,3): 'baz' -> 'baz'")
    check(recorte:is_null(4),      "slice: NA propaga")

    -- índice negativo
    local recorte_negativo = frases.str:slice(-3)
    check(recorte_negativo:get(1) == "rld", "slice(-3): 'hello world' -> 'rld'")
    check(recorte_negativo:get(3) == "baz", "slice(-3): 'baz' -> 'baz'")

    -- slice além do tamanho (Lua retorna o que tiver)
    local recorte_alem_do_tamanho = frases.str:slice(1, 100)
    check(recorte_alem_do_tamanho:get(1) == "hello world", "slice(1,100): retorna toda a string")

    -- sem stop: vai até o fim
    local recorte_ate_o_fim = frases.str:slice(7)
    check(recorte_ate_o_fim:get(1) == "world", "slice(7): 'hello world' -> 'world'")

    -- série vazia
    local serie_vazia = smaug.Series({}, "string")
    check(serie_vazia.str:slice(1,3):len() == 0, "slice: série vazia -> vazia")

    -- ================================================================
    -- pad
    -- ================================================================
    local preenchida_esquerda = frases.str:pad(12, "left")
    check(preenchida_esquerda:get(1) == " hello world", "pad(12,left): 1 espaço antes")
    check(preenchida_esquerda:get(2) == "     foo bar", "pad(12,left): 5 espaços antes")
    check(preenchida_esquerda:get(3) == "         baz", "pad(12,left): 9 espaços antes")
    check(preenchida_esquerda:is_null(4),                "pad: NA propaga")
    check(preenchida_esquerda._dtype == "string",        "pad: dtype string")

    local preenchida_direita = frases.str:pad(10, "right", "*")
    check(preenchida_direita:get(3) == "baz*******", "pad(10,right,*): baz*******")

    local preenchida_ambos_lados = frases.str:pad(12, "both")
    check(#preenchida_ambos_lados:get(2) == 12, "pad(12,both): comprimento total=12")

    -- string maior que width: retorna intacta
    local maior_que_width = frases.str:pad(3, "left")
    check(maior_que_width:get(1) == "hello world", "pad: string maior não trunca")

    -- erros
    check(rejects(function() frases.str:pad(-1) end),              "pad: width negativo recusado")
    check(rejects(function() frases.str:pad(5, "left", "ab") end), "pad: fillchar >1 char recusado")
    check(rejects(function() frases.str:pad(5, "centro") end),     "pad: side inválido recusado")

    -- ================================================================
    -- zfill
    -- ================================================================
    local numeros_texto = smaug.Series({"42","7","100","1000",smaug.NA}, "string")
    local preenchida_com_zeros = numeros_texto.str:zfill(5)
    check(preenchida_com_zeros:get(1) == "00042", "zfill(5): '42' -> '00042'")
    check(preenchida_com_zeros:get(2) == "00007", "zfill(5): '7' -> '00007'")
    check(preenchida_com_zeros:get(3) == "00100", "zfill(5): '100' -> '00100'")
    check(preenchida_com_zeros:get(4) == "01000", "zfill(5): '1000' -> '01000' (5 chars total)")
    check(preenchida_com_zeros:is_null(5),         "zfill: NA propaga")

    -- ================================================================
    -- rep
    -- ================================================================
    local curtas = smaug.Series({"ab","x",smaug.NA}, "string")
    local repetida_duas_vezes = curtas.str:rep(2)
    check(repetida_duas_vezes:get(1) == "abab", "rep(2): 'ab' -> 'abab'")
    check(repetida_duas_vezes:get(2) == "xx",   "rep(2): 'x' -> 'xx'")
    check(repetida_duas_vezes:is_null(3),       "rep: NA propaga")

    local repetida_com_separador = curtas.str:rep(2, "-")
    check(repetida_com_separador:get(1) == "ab-ab", "rep(2,'-'): 'ab' -> 'ab-ab'")
    check(repetida_com_separador:get(2) == "x-x",   "rep(2,'-'): 'x' -> 'x-x'")

    local repetida_zero_vezes = curtas.str:rep(0)
    check(repetida_zero_vezes:get(1) == "", "rep(0): string vazia")

    -- erro: n < 0
    check(rejects(function() curtas.str:rep(-1) end), "rep: n<0 recusado")

    -- ================================================================
    -- cat
    -- ================================================================
    local concatenada_com_virgula = frases.str:cat(", ")
    check(concatenada_com_virgula == "hello world, foo bar, baz", "cat: NA ignorado, sep correto")

    local concatenada_sem_separador = frases.str:cat()
    check(concatenada_sem_separador == "hello worldfoo barbaz", "cat sem sep")

    -- todos NA
    local todas_nulas = smaug.Series({smaug.NA, smaug.NA}, "string")
    check(todas_nulas.str:cat() == "", "cat: todos NA -> string vazia")

    -- série vazia
    check(serie_vazia.str:cat() == "", "cat: série vazia -> string vazia")

    -- ================================================================
    -- split
    -- ================================================================
    local linhas_csv = smaug.Series({"a:b:c","x:y","z",smaug.NA}, "string")
    local colunas = linhas_csv.str:split(":")

    check(#colunas == 3,             "split: 3 colunas (max partes)")
    check(colunas[1]:get(1) == "a", "split col1[1] = a")
    check(colunas[2]:get(1) == "b", "split col2[1] = b")
    check(colunas[3]:get(1) == "c", "split col3[1] = c")
    check(colunas[1]:get(2) == "x", "split col1[2] = x")
    check(colunas[2]:get(2) == "y", "split col2[2] = y")
    check(colunas[3]:is_null(2),    "split: col3[2] = NA (sem terceira parte)")
    check(colunas[1]:get(3) == "z", "split col1[3] = z (sem sep)")
    check(colunas[2]:is_null(3),    "split: col2[3] = NA (sem segunda parte)")
    check(colunas[1]:is_null(4),    "split: col1[4] = NA (entrada NA)")

    -- separador multi-char
    local linhas_separador_duplo = smaug.Series({"a::b::c","x::y"}, "string")
    local colunas_separador_duplo = linhas_separador_duplo.str:split("::")
    check(colunas_separador_duplo[1]:get(1) == "a", "split '::' col1 = a")
    check(colunas_separador_duplo[2]:get(1) == "b", "split '::' col2 = b")
    check(colunas_separador_duplo[3]:get(1) == "c", "split '::' col3 = c")

    -- max_splits
    local linha_com_limite = smaug.Series({"a:b:c:d"}, "string")
    local colunas_com_limite = linha_com_limite.str:split(":", 2)
    check(#colunas_com_limite == 3,             "split max=2: 3 partes")
    check(colunas_com_limite[1]:get(1) == "a", "split max=2 [1]=a")
    check(colunas_com_limite[2]:get(1) == "b", "split max=2 [2]=b")
    check(colunas_com_limite[3]:get(1) == "c:d", "split max=2 [3]=c:d (resto)")

    -- nenhum match: 1 coluna com a string original
    local sem_separador = smaug.Series({"abc","def"}, "string")
    local colunas_sem_match = sem_separador.str:split(",")
    check(#colunas_sem_match == 1,              "split sem match: 1 coluna")
    check(colunas_sem_match[1]:get(1) == "abc", "split sem match: valor original")

    -- série vazia
    local split_serie_vazia = serie_vazia.str:split(":")
    check(#split_serie_vazia == 0, "split série vazia: 0 colunas")

    -- erro: sep vazio
    check(rejects(function() frases.str:split("") end), "split: sep vazio recusado")
end

test_str_accessor_avancado()

-- =====================================================================
-- .str: count, predicados ASCII, removeprefix/removesuffix,
-- capitalize/title/swapcase, join, e view de string (COW)
-- =====================================================================
local function test_str_accessor_extras()
    -- ================================================================
    -- count — ocorrências literais não-sobrepostas
    -- ================================================================
    local textos_com_a = smaug.Series({"banana", "aaaa", "xyz", "", smaug.NA}, "string")
    local contagem_a = textos_com_a.str:count("a")
    check(contagem_a._dtype == "int64", "count → int64")
    check(contagem_a:get(1) == 3,       "count 'a' em banana = 3")
    check(contagem_a:get(2) == 4,       "count 'a' em aaaa = 4")
    check(contagem_a:get(3) == 0,       "count 'a' em xyz = 0")
    check(contagem_a:get(4) == 0,       "count 'a' em vazia = 0")
    check(contagem_a:get(5) == nil,     "count NA → nil")

    -- não-sobreposto: "aa" em "aaaa" = 2 (não 3)
    local contagem_aa = textos_com_a.str:count("aa")
    check(contagem_aa:get(2) == 2, "count 'aa' em aaaa = 2 (não-sobreposto)")
    check(contagem_aa:get(1) == 0, "count 'aa' em banana = 0 (a's não-adjacentes)")

    -- substring multichar
    local texto_repetido = smaug.Series({"abcabcabc"}, "string")
    check(texto_repetido.str:count("abc"):get(1) == 3, "count 'abc' = 3")

    -- sub vazio → erro
    check(rejects(function() textos_com_a.str:count("") end), "count substring vazia = erro")
    -- não-string → erro
    check(rejects(function() textos_com_a.str:count(5) end), "count não-string = erro")

    -- ================================================================
    -- Predicados ASCII — string vazia sempre false; null → nil
    -- ================================================================
    local textos_variados = smaug.Series({
        "abc123",  -- 1: alnum
        "abc",     -- 2: alpha, lower
        "123",     -- 3: digit
        "   ",     -- 4: space
        "ABC",     -- 5: alpha, upper
        "abC",     -- 6: alpha, misto
        "",        -- 7: vazia
        smaug.NA,  -- 8: null
    }, "string")

    local eh_alnum = textos_variados.str:isalnum()
    check(eh_alnum._dtype == "bool", "isalnum → bool")
    check(eh_alnum:get(1) == true,   "isalnum abc123 → true")
    check(eh_alnum:get(4) == false,  "isalnum espaços → false")
    check(eh_alnum:get(7) == false,  "isalnum vazia → false")
    check(eh_alnum:get(8) == nil,    "isalnum NA → nil")

    local eh_alpha = textos_variados.str:isalpha()
    check(eh_alpha:get(1) == false, "isalpha abc123 → false (tem dígitos)")
    check(eh_alpha:get(2) == true,  "isalpha abc → true")
    check(eh_alpha:get(7) == false, "isalpha vazia → false")

    local eh_digit = textos_variados.str:isdigit()
    check(eh_digit:get(3) == true,  "isdigit 123 → true")
    check(eh_digit:get(1) == false, "isdigit abc123 → false")
    check(eh_digit:get(7) == false, "isdigit vazia → false")

    local eh_space = textos_variados.str:isspace()
    check(eh_space:get(4) == true,  "isspace '   ' → true")
    check(eh_space:get(2) == false, "isspace abc → false")
    check(eh_space:get(7) == false, "isspace vazia → false")

    local eh_lower = textos_variados.str:islower()
    check(eh_lower:get(2) == true,  "islower abc → true")
    check(eh_lower:get(5) == false, "islower ABC → false")
    check(eh_lower:get(6) == false, "islower abC → false (tem maiúscula)")
    check(eh_lower:get(3) == false, "islower 123 → false (sem letras)")
    check(eh_lower:get(7) == false, "islower vazia → false")

    local eh_upper = textos_variados.str:isupper()
    check(eh_upper:get(5) == true,  "isupper ABC → true")
    check(eh_upper:get(2) == false, "isupper abc → false")
    check(eh_upper:get(6) == false, "isupper abC → false (tem minúscula)")
    check(eh_upper:get(3) == false, "isupper 123 → false (sem letras)")

    -- isspace com tab/newline
    local com_espacos_especiais = smaug.Series({"\t\n", " \t ", "a b"}, "string")
    check(com_espacos_especiais.str:isspace():get(1) == true,  "isspace tab+newline → true")
    check(com_espacos_especiais.str:isspace():get(3) == false, "isspace 'a b' → false")

    -- ================================================================
    -- removeprefix / removesuffix — idempotente
    -- ================================================================
    local com_prefixo_sufixo = smaug.Series({"unhappy", "happy", "test.lua", "test", smaug.NA}, "string")

    local sem_prefixo = com_prefixo_sufixo.str:removeprefix("un")
    check(sem_prefixo._dtype == "string", "removeprefix → string")
    check(sem_prefixo:get(1) == "happy",  "removeprefix un de unhappy → happy")
    check(sem_prefixo:get(2) == "happy",  "removeprefix un de happy → happy (idempotente)")
    check(sem_prefixo:get(5) == nil,      "removeprefix NA → nil")

    local sem_sufixo = com_prefixo_sufixo.str:removesuffix(".lua")
    check(sem_sufixo:get(3) == "test", "removesuffix .lua de test.lua → test")
    check(sem_sufixo:get(4) == "test", "removesuffix .lua de test → test (idempotente)")

    -- prefixo/sufixo vazio → cópia inalterada
    check(com_prefixo_sufixo.str:removeprefix(""):get(1) == "unhappy", "removeprefix vazio → inalterado")
    check(com_prefixo_sufixo.str:removesuffix(""):get(1) == "unhappy", "removesuffix vazio → inalterado")

    -- prefixo maior que a string
    local texto_curto = smaug.Series({"ab"}, "string")
    check(texto_curto.str:removeprefix("abcdef"):get(1) == "ab", "removeprefix maior → inalterado")

    -- não-string → erro
    check(rejects(function() com_prefixo_sufixo.str:removeprefix(5) end), "removeprefix não-string = erro")

    -- ================================================================
    -- capitalize / title / swapcase
    -- ================================================================
    local textos_mistos = smaug.Series({"hello WORLD", "foo bar baz", "aBcD", "", smaug.NA}, "string")

    local capitalizado = textos_mistos.str:capitalize()
    check(capitalizado:get(1) == "Hello world", "capitalize hello WORLD → Hello world")
    check(capitalizado:get(3) == "Abcd",        "capitalize aBcD → Abcd")
    check(capitalizado:get(4) == "",            "capitalize vazia → vazia")
    check(capitalizado:get(5) == nil,           "capitalize NA → nil")

    local em_titulo = textos_mistos.str:title()
    check(em_titulo:get(1) == "Hello World", "title hello WORLD → Hello World")
    check(em_titulo:get(2) == "Foo Bar Baz", "title foo bar baz → Foo Bar Baz")
    check(em_titulo:get(3) == "Abcd",        "title aBcD → Abcd")

    -- title com separadores não-letra
    local com_separadores_diversos = smaug.Series({"a-b c.d", "joão123silva"}, "string")
    check(com_separadores_diversos.str:title():get(1) == "A-B C.D", "title com hífen/ponto/espaço")
    -- 'joão' tem byte não-ASCII (ã); título trata cada letra ASCII; verifica que ç/ã não quebram
    check(type(com_separadores_diversos.str:title():get(2)) == "string", "title com não-ASCII não quebra")

    local caixa_trocada = textos_mistos.str:swapcase()
    check(caixa_trocada:get(1) == "HELLO world", "swapcase hello WORLD → HELLO world")
    check(caixa_trocada:get(3) == "AbCd",        "swapcase aBcD → AbCd")

    -- ================================================================
    -- join (atalho de cat)
    -- ================================================================
    local palavras = smaug.Series({"a", "b", smaug.NA, "c"}, "string")
    check(palavras.str:join("-") == "a-b-c", "join '-' ignora nulos")
    check(palavras.str:join("") == "abc",    "join '' concatena")
    check(palavras.str:join("-") == palavras.str:cat("-"), "join idêntico a cat")

    -- série vazia
    local palavras_vazias = smaug.Series({}, "string")
    check(palavras_vazias.str:join(",") == "", "join série vazia → vazia")

    -- view de string agora suportada (9.2): zero-copy na leitura, COW na escrita
    local estados = smaug.Series({"SP", "RJ", "MG"}, "string")
    local janela_estados = estados:view(1, 2)                  -- [SP, RJ]
    check(janela_estados:len() == 2, "string view: janela com len correto")
    check(janela_estados:get(1) == "SP" and janela_estados:get(2) == "RJ",
          "string view: lê o pai (zero-copy)")
    janela_estados:set(1, "SAOPAULO")                          -- dispara COW detach
    check(janela_estados:get(1) == "SAOPAULO", "string view: set reflete na view")
    check(estados:get(1) == "SP",              "string view: pai intacto após COW")
    check(estados:take({1, 2}):len() == 2,     "string take: cópia independente também funciona")
end

test_str_accessor_extras()

-- ================================================================
-- Resultado
-- ================================================================

print(string.format("OK — %d checks passaram (Series: .str completo)", total_checks_ok))
