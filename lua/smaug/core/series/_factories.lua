-- lua/smaug/core/series/_factories.lua
--
-- Factories públicas da Series.
-- Recebe I com: I.Series, I.DTYPES, I.wrap, I.is_na, I.NA
-- Contribui: Series.new, Series.float64, Series.int64, Series.string,
--            Series.datetime, Series.full, Series.from_table (base, sem categorical)

return function(I)
    local Series = I.Series
    local DTYPES = I.DTYPES
    local wrap   = I.wrap
    local is_na  = I.is_na
    local NA     = I.NA

    function Series.new(dtype, size, name)
        if not DTYPES[dtype] then
            error("smaug: dtype desconhecido '"..tostring(dtype)..
                  "'. Suportados: float64, int64, string.", 2)
        end
        return wrap(DTYPES[dtype].create(size or 0), dtype, name)
    end

    function Series.float64(size, name)  return Series.new("float64",  size, name) end
    function Series.int64(size, name)    return Series.new("int64",    size, name) end
    function Series.string(size, name)   return Series.new("string",   size, name) end
    function Series.datetime(size, name) return Series.new("datetime", size, name) end

    -- Series.full(n, val, dtype): série de n elementos todos iguais a val.
    -- dtype inferido quando omitido: string→"string", boolean→"int64" (1/0),
    -- número inteiro→"int64", fracionário→"float64".
    -- Usado por DataSet.__newindex para broadcast de escalares.
    function Series.full(n, val, dtype, name)
        if val == nil then
            error("smaug: Series.full requer um valor não-nulo", 2)
        end
        if not dtype then
            local t = type(val)
            if     t == "string"  then dtype = "string"
            elseif t == "boolean" then dtype = "int64"; val = val and 1 or 0
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
    function Series.from_table(arr, dtype, name)
        dtype = dtype or "float64"
        if not DTYPES[dtype] then
            error("smaug: dtype desconhecido '"..tostring(dtype).."'", 2)
        end
        local n = #arr
        local s = Series.new(dtype, n, name)
        for i = 1, n do
            if is_na(arr[i]) then s:set_null(i) else s:set(i, arr[i]) end
        end
        return s
    end
end
