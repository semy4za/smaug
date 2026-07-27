-- lua/smaug/core/series/_factories.lua
--
-- Factories públicas da Series.
-- Recebe I com: I.Series, I.DTYPES, I.wrap, I.is_na, I.is_nan, I.NA
-- Contribui: Series.new, Series.float64, Series.int64, Series.string,
--            Series.datetime, Series.full, Series.from_table (base, sem categorical),
--            Series.infer_dtype, I.infer_dtype, I.infer_dtype_from_value
--            (Bloco H, H.2/H.6: fonte única de inferência de dtype, reusada por
--             Series.full/from_table/__call, DataSet.from_columns/__call e Series:map)

local Err = require("smaug.core.errors")

return function(I)
    local Series = I.Series
    local DTYPES = I.DTYPES
    local wrap   = I.wrap
    local is_na  = I.is_na
    local is_nan = I.is_nan
    local NA     = I.NA

    -- =====================================================================
    -- infer_dtype — fonte única de inferência de dtype (Bloco H, H.2/H.6)
    -- =====================================================================
    -- infer_dtype_from_value(v): mapeia UM valor Lua pro dtype que ele
    -- ocuparia. nil = tipo não suportado pela inferência (ex.: table, function);
    -- quem chamar decide o que fazer (cair em "string" ou erro, conforme o
    -- contexto). Regras (H.6.1): bool só de `boolean` Lua nativo — nunca de
    -- 0/1 numérico nem "yes"/"no"; isso seria adivinhar semântica.
    local function infer_dtype_from_value(v)
        local t = type(v)
        if t == "boolean" then return "bool" end
        if t == "string"  then return "string" end
        if t == "number" then
            if is_nan(v) or v % 1 ~= 0 then return "float64" end  -- NaN ou fracionário
            return "int64"
        end
        return nil
    end
    I.infer_dtype_from_value = infer_dtype_from_value

    -- Famílias de tipo (12.31). Dentro de uma família há promoção segura; entre
    -- famílias, não existe supertipo — e escolher um seria adivinhar.
    -- `int64` e `float64` são a MESMA família: int→float não perde informação
    -- (Contrato 1, promoção segura). `string` e `bool` são famílias próprias:
    -- misturar com número exigiria adivinhar parse ("1" vira 1?) ou semântica
    -- (1 vira true?), exatamente o que o Contrato 1 recusa.
    --
    -- Antes daqui a decisão era por RANK (bool > string > float64 > int64), o
    -- que em mistura incompatível escolhia o de maior rank e produzia um
    -- container que rejeitava a própria lista: `{1, "x"}` inferia string e
    -- estourava no set com "valor para string deve ser uma string Lua" — uma
    -- mensagem sobre um dtype que o usuário nunca pediu. Inferência e validação
    -- discordavam entre si. Agora o erro nasce na inferência, nomeando o
    -- conflito. O rank sobrevive só onde faz sentido: dentro do numérico.
    local DTYPE_FAMILY = { int64 = "numérico", float64 = "numérico",
                           string = "string",  bool    = "bool" }
    local NUMERIC_RANK = { int64 = 1, float64 = 2 }   -- fracionário vence

    -- infer_dtype(arr): decide o dtype de uma tabela Lua de valores brutos.
    -- Ignora nulos (nil/NA) ao decidir — lista vazia ou só-nula cai em
    -- "string" (H.6.2, fallback universal, coerente com o CSV). Elementos de
    -- tipo não suportado (table, function, ...) são ignorados aqui; o erro
    -- claro acontece depois, no set/append via check_value, não na inferência.
    -- Mistura de famílias incompatíveis → erro AQUI (12.31).
    local function infer_dtype(arr, level)
        local family, first_dt, first_at        -- primeira família vista
        local num_best, num_rank = nil, 0
        local n = #arr
        for i = 1, n do
            local v = arr[i]
            if not is_na(v) then
                local dt = infer_dtype_from_value(v)
                if dt then
                    local fam = DTYPE_FAMILY[dt]
                    if family == nil then
                        family, first_dt, first_at = fam, dt, i
                    elseif fam ~= family then
                        error("smaug: não foi possível inferir o dtype: a lista mistura "
                              .. "tipos sem promoção segura entre si — " .. first_dt
                              .. " no índice " .. first_at .. " e " .. dt
                              .. " no índice " .. i .. ". Informe o dtype "
                              .. "explicitamente (ex.: from_table(t, \"string\")) ou "
                              .. "uniformize os valores.", level or 4)
                    end
                    if fam == "numérico" then
                        local r = NUMERIC_RANK[dt]
                        if r > num_rank then num_best, num_rank = dt, r end
                    end
                end
            end
        end
        if family == nil      then return "string" end   -- vazia ou só-nula
        if family == "numérico" then return num_best end -- int64 ou float64
        return family                                    -- "string" ou "bool"
    end
    I.infer_dtype = infer_dtype
    Series.infer_dtype = infer_dtype   -- público: reusado por DataSet (H.2/H.6)

    function Series.new(dtype, size, name)
        if not DTYPES[dtype] then
            error("smaug: dtype desconhecido "..Err.describe(dtype)..
                  ". Suportados: float64, int64, string.", 2)
        end
        return wrap(DTYPES[dtype].create(size or 0), dtype, name)
    end

    function Series.float64(size, name)  return Series.new("float64",  size, name) end
    function Series.int64(size, name)    return Series.new("int64",    size, name) end
    function Series.string(size, name)   return Series.new("string",   size, name) end
    function Series.datetime(size, name) return Series.new("datetime", size, name) end

    -- Series.full(n, val, dtype): série de n elementos todos iguais a val.
    -- dtype inferido quando omitido: string→"string", boolean→"bool" (H.6.1),
    -- número inteiro→"int64", fracionário→"float64".
    -- Usado por DataSet.__newindex para broadcast de escalares.
    function Series.full(n, val, dtype, name)
        if val == nil then
            error("smaug: Series.full requer um valor não-nulo", 2)
        end
        if not dtype then
            local t = type(val)
            if     t == "string"  then dtype = "string"
            elseif t == "boolean" then dtype = "bool"
            elseif t == "number"  then
                dtype = (val % 1 == 0) and "int64" or "float64"
            else
                error("smaug: Series.full: tipo não suportado: " .. t, 2)
            end
        end
        local s = Series.new(dtype, n, name)
        for i = 1, n do s:set(i, val) end
        return s
    end

    -- Series.from_table: versão base (sem intercepção categorical).
    -- A intercepção para "categorical" é feita no init.lua após carregar
    -- _categorical.lua, sobrescrevendo esta função.
    -- dtype omitido → infer_dtype(arr) decide (H.2: antes era default float64
    -- silencioso, independente do conteúdo — corrigido).
    function Series.from_table(arr, dtype, name)
        dtype = dtype or infer_dtype(arr)
        if not DTYPES[dtype] then
            error("smaug: dtype desconhecido "..Err.describe(dtype), 2)
        end
        local n = #arr
        local s = Series.new(dtype, n, name)
        for i = 1, n do
            if is_na(arr[i]) then s:set_null(i) else s:set(i, arr[i]) end
        end
        return s
    end

    -- =====================================================================
    -- H.3 — Series chamável + alias from_array
    -- =====================================================================
    -- smaug.Series({1,2,3,4}) — espelha smaug.DataSet({...}), que já tinha
    -- __call. Dispatch dinâmico pra Series.from_table (não captura a versão
    -- antiga): garante que pega a versão final, já com a interceptação
    -- categorical ligada pelo init.lua, não importa quando __call rodar.
    setmetatable(Series, {
        __call = function(_, arr, dtype, name)
            return Series.from_table(arr, dtype, name)
        end,
    })

    -- from_array: alias de from_table. "array" ecoa create_from_array (C) e o
    -- fato de Lua não ter "list" como conceito separado. Mesmo motivo do
    -- __call acima: dispatch dinâmico, não alias estático.
    function Series.from_array(arr, dtype, name)
        return Series.from_table(arr, dtype, name)
    end
end
