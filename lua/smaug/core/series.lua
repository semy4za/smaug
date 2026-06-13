-- lua/smaug/core/series.lua
--
-- Classe Series: uma coluna tipada, 1-dimensional, com null handling.
--
-- ARQUITETURA: a Series NÃO conhece os detalhes de cada tipo. Ela despacha
-- para uma família de funções C (`smaug_<dtype>_*`) através de um DESCRITOR de
-- dtype (tabela DTYPES abaixo). Adicionar um novo tipo (bool, string, datetime,
-- float32, ...) = registrar um descritor novo + o backend C, sem tocar na
-- lógica da Series. É o ponto de extensão central do frontend.
--
-- Convenções traduzidas aqui (a fronteira Lua↔C):
--   * Índices 1-based (Lua) -> 0-based (C).
--   * `nil` (Lua) <-> NA/null (C). get() de posição nula devolve nil.
--   * Sentinelas do C (NAN no f64; INT64_MIN nas reduções i64) viram nil.

local ffi = require("ffi")
local C   = require("smaug.ffi_loader")

local NAN     = 0 / 0
local I64_MIN = -9223372036854775807LL - 1LL   -- INT64_MIN sem overflow de literal

local function is_nan(v) return v ~= v end

-- Sentinela de valor ausente. Use em tabelas passadas a from_table, já que um
-- `nil` no meio de uma tabela Lua torna o comprimento (#) indefinido.
--   Series.from_table({1, Series.NA, 3}, "float64")   -- 3 elementos, [2] nulo
local NA = setmetatable({}, { __tostring = function() return "NA" end })

-- Ausência (null) é APENAS nil ou o sentinela NA. NaN NÃO é ausência —
-- é um valor de ponto flutuante presente, porém indefinido (contrato:
-- "NaN é distinto de null"). Ver Roadmap, "Contrato de valores especiais".
local function is_na(v) return v == nil or v == NA end

-- =====================================================================
-- Descritores de dtype: o coração da abstração.
-- Cada descritor mapeia o nome do dtype para o conjunto de funções C e
-- as particularidades semânticas daquele tipo.
-- =====================================================================
local DTYPES = {
    float64 = {
        name        = "float64",
        free        = C.smaug_f64_free,
        create      = C.smaug_f64_create,
        clone       = C.smaug_f64_clone,
        get         = C.smaug_f64_get,
        -- get_value: converte o retorno C para o tipo Lua certo deste dtype.
        -- (o método genérico Series:get apenas repassa, sem saber o tipo)
        get_value   = function(c, i) return tonumber(C.smaug_f64_get(c, i, nil)) end,
        set         = C.smaug_f64_set,
        set_null    = C.smaug_f64_set_null,
        is_null     = C.smaug_f64_is_null,
        append      = C.smaug_f64_append,
        append_null = C.smaug_f64_append_null,
        add = C.smaug_f64_add, sub = C.smaug_f64_sub,
        mul = C.smaug_f64_mul, div = C.smaug_f64_div,
        add_scalar = C.smaug_f64_add_scalar, sub_scalar = C.smaug_f64_sub_scalar,
        mul_scalar = C.smaug_f64_mul_scalar, div_scalar = C.smaug_f64_div_scalar,
        sum = C.smaug_f64_sum, mean = C.smaug_f64_mean,
        min = C.smaug_f64_min, max = C.smaug_f64_max,
        var = C.smaug_f64_var, std = C.smaug_f64_std,
        count_nonnull = C.smaug_f64_count_nonnull,
        sort = C.smaug_f64_sort,
        view = C.smaug_f64_view, take = C.smaug_f64_take,
        filter = C.smaug_f64_filter,
        gt = C.smaug_f64_gt, lt = C.smaug_f64_lt, eq = C.smaug_f64_eq,
        ge = C.smaug_f64_ge, le = C.smaug_f64_le, ne = C.smaug_f64_ne,
        -- wrappers de comparação: validam escalar numérico e chamam a função C.
        cmp_gt = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_gt(c,t,om) end,
        cmp_lt = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_lt(c,t,om) end,
        cmp_eq = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_eq(c,t,om) end,
        cmp_ge = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_ge(c,t,om) end,
        cmp_le = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_le(c,t,om) end,
        cmp_ne = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_ne(c,t,om) end,
        argsort = C.smaug_f64_argsort,
        -- Uma redução int (sum/min/max) devolveu o sentinela de erro?
        -- No f64 isso é detectado por NaN no próprio valor.
        is_int_sentinel = function(_) return false end,
    },
    int64 = {
        name        = "int64",
        free        = C.smaug_i64_free,
        create      = C.smaug_i64_create,
        clone       = C.smaug_i64_clone,
        get         = C.smaug_i64_get,
        get_value   = function(c, i) return tonumber(C.smaug_i64_get(c, i, nil)) end,
        set         = C.smaug_i64_set,
        set_null    = C.smaug_i64_set_null,
        is_null     = C.smaug_i64_is_null,
        append      = C.smaug_i64_append,
        append_null = C.smaug_i64_append_null,
        add = C.smaug_i64_add, sub = C.smaug_i64_sub,
        mul = C.smaug_i64_mul, div = C.smaug_i64_div,
        add_scalar = C.smaug_i64_add_scalar, sub_scalar = C.smaug_i64_sub_scalar,
        mul_scalar = C.smaug_i64_mul_scalar, div_scalar = C.smaug_i64_div_scalar,
        sum = C.smaug_i64_sum, mean = C.smaug_i64_mean,
        min = C.smaug_i64_min, max = C.smaug_i64_max,
        var = C.smaug_i64_var, std = C.smaug_i64_std,
        count_nonnull = C.smaug_i64_count_nonnull,
        sort = C.smaug_i64_sort,
        view = C.smaug_i64_view, take = C.smaug_i64_take,
        filter = C.smaug_i64_filter,
        gt = C.smaug_i64_gt, lt = C.smaug_i64_lt, eq = C.smaug_i64_eq,
        ge = C.smaug_i64_ge, le = C.smaug_i64_le, ne = C.smaug_i64_ne,
        cmp_gt = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_gt(c,t,om) end,
        cmp_lt = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_lt(c,t,om) end,
        cmp_eq = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_eq(c,t,om) end,
        cmp_ge = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_ge(c,t,om) end,
        cmp_le = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_le(c,t,om) end,
        cmp_ne = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_ne(c,t,om) end,
        argsort = C.smaug_i64_argsort,
        -- sum/min/max do i64 retornam INT64_MIN quando há nulo + !ignore_na.
        is_int_sentinel = function(v) return v == I64_MIN end,
    },
    string = {
        name        = "string",
        free        = C.smaug_str_free,
        create      = C.smaug_str_create,
        clone       = C.smaug_str_clone,
        -- Acesso: a string passa ponteiro+comprimento pelo FFI (não valor).
        -- Os wrappers escondem essa diferença; o método genérico não sabe.
        get_value   = function(c, i)
            local len = ffi.new("size_t[1]")
            local p   = C.smaug_str_get(c, i, len)
            if p == nil then return nil end       -- elemento NULL
            return ffi.string(p, len[0])          -- bytes -> string Lua
        end,
        set         = function(c, i, v)
            -- v é string Lua; passa ponteiro + comprimento. Retorna rc do C.
            return C.smaug_str_set(c, i, v, #v)
        end,
        set_null    = C.smaug_str_set_null,
        is_null     = C.smaug_str_is_null,
        append      = function(c, v) return C.smaug_str_append(c, v, #v) end,
        append_null = C.smaug_str_append_null,
        count_nonnull = C.smaug_str_count_nonnull,
        -- comparações: validam string Lua e passam ponteiro + comprimento.
        cmp_eq = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_eq(c,t,#t,om) end,
        cmp_lt = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_lt(c,t,#t,om) end,
        cmp_gt = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_gt(c,t,#t,om) end,
        cmp_ge = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_ge(c,t,#t,om) end,
        cmp_le = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_le(c,t,#t,om) end,
        cmp_ne = function(c, t, om) if type(t)~="string" then error("smaug: comparação de string espera string",4) end return C.smaug_str_ne(c,t,#t,om) end,
        -- seleção: filter (por máscara) e take (por índices) -> nova série string
        filter = C.smaug_str_filter,
        take   = C.smaug_str_take,
        -- ordenação: lexicográfica por bytes; recusa NULL (como os numéricos)
        sort    = C.smaug_str_sort,
        argsort = C.smaug_str_argsort,
        -- string NÃO tem ops numéricas (add/sum/sort/...) nem comparações ainda.
        -- O método genérico checa a existência do campo e recusa com erro claro.
        is_int_sentinel = function(_) return false end,
    },

    -- ----------------------------------------------------------------
    -- bool: dtype de primeira classe. Armazenamento smaug_series_bool_t.
    -- true/false/nil (NA) são os valores Lua. Internamente 0/1 + null_mask.
    -- Comparações (gt/lt/eq/...) retornam Series<bool> — Fase 3.
    -- ----------------------------------------------------------------
    bool = {
        name        = "bool",
        free        = C.smaug_bool_free,
        create      = C.smaug_bool_create,
        clone       = C.smaug_bool_clone,
        -- get_value: converte uint8_t C para boolean Lua (ou nil se null).
        get_value   = function(c, i)
            local st = ffi.new("smaug_status_t[1]")
            local v  = C.smaug_bool_get(c, i, st)
            if st[0] == C.SMG_NULL_VALUE or st[0] == C.SMG_ERR_OOB then return nil end
            return v ~= 0   -- 0 -> false, 1 -> true
        end,
        -- set: aceita boolean Lua, nil (→ null) ou número (0/1 canônico).
        set = function(c, i, v)
            if v == nil then return C.smaug_bool_set_null(c, i) end
            return C.smaug_bool_set(c, i, v and 1 or 0)
        end,
        set_null    = C.smaug_bool_set_null,
        is_null     = C.smaug_bool_is_null,
        append = function(c, v)
            if v == nil then return C.smaug_bool_append_null(c) end
            return C.smaug_bool_append(c, v and 1 or 0)
        end,
        append_null = C.smaug_bool_append_null,
        count_nonnull = C.smaug_bool_count_nonnull,
        -- seleção
        filter  = C.smaug_bool_filter,
        take    = C.smaug_bool_take,
        -- ordenação: false < true; recusa NULL
        sort    = C.smaug_bool_sort,
        argsort = C.smaug_bool_argsort,
        -- bool NÃO tem ops numéricas nem comparações nesta fase.
        is_int_sentinel = function(_) return false end,
    },
}

local Series = {}
Series.__index = Series   -- placeholder; sobrescrito no fim com dispatcher

-- métodos ficam aqui; o __index real decide entre índice numérico e método
local methods = {}

-- =====================================================================
-- Construção interna
-- =====================================================================
local function wrap(c_ptr, dtype, name, parent)
    if c_ptr == nil then error("smaug: falha ao alocar Series ("..dtype..")", 2) end
    local d = DTYPES[dtype]
    ffi.gc(c_ptr, d.free)   -- limpeza automática quando o objeto Lua morrer
    -- Para views, c_ptr tem external_alloc=true: o free só libera o struct da
    -- view, nunca os dados da pai. Guardamos `_parent` para impedir que o GC
    -- do Lua colete a pai enquanto a view viver (evita use-after-free).
    -- Após o primeiro COW-detach (set/set_null), a view tem buffer privado e
    -- não depende mais da memória da pai — manter _parent é seguro (harmless).
    return setmetatable({
        _c      = c_ptr,
        _d      = d,
        _dtype  = dtype,
        _name   = name or "unnamed",
        _parent = parent,                     -- nil exceto em views
    }, Series)
end

local function check_index(self, i)
    if type(i) ~= "number" or i < 1 or i > self._c.size or i % 1 ~= 0 then
        error("smaug: índice "..tostring(i).." fora dos limites [1, "..
              tonumber(self._c.size).."]", 3)
    end
end

-- Valida um valor a gravar, conforme o dtype. int64 não aceita coerção:
-- sem este guard, o FFI truncaria não-inteiros (1.5 -> 1) e Inf/NaN virariam
-- lixo. float64 aceita qualquer número (incl. NaN/Inf, que são valores válidos).
-- Usado por set e append (CODE_REVIEW A7). Nível de pilha configurável p/ a
-- mensagem de erro apontar para a chamada do usuário.
local function check_value(self, v, level)
    local dt = self._dtype
    if dt == "int64" then
        if type(v) ~= "number" or v % 1 ~= 0 then
            error("smaug: valor para int64 deve ser inteiro (sem coerção); "
                  .. "recebido " .. tostring(v), level or 3)
        end
    elseif dt == "string" then
        if type(v) ~= "string" then
            error("smaug: valor para string deve ser uma string Lua; "
                  .. "recebido " .. type(v), level or 3)
        end
    elseif dt == "bool" then
        if type(v) ~= "boolean" then
            error("smaug: valor para bool deve ser boolean Lua (true/false); "
                  .. "recebido " .. type(v), level or 3)
        end
    else  -- float64
        if type(v) ~= "number" then
            error("smaug: valor para " .. dt .. " deve ser número; "
                  .. "recebido " .. type(v), level or 3)
        end
    end
end

-- Contrato defensivo: todas as funções de fronteira devolvem smaug_status_t
-- (0 == SMG_OK). str_set foi convertido de int (0/-1) para smaug_status_t,
-- portanto o aviso sobre "legado" é removido.
--   SMG_ERR_NOMEM (4): COW-detach ou alocação falhou — erro propagado.
--   Qualquer outro: invariante do backend violado.
local SMG_ERR_NOMEM = 4   -- espelha smaug_types.h (enum fixo, 0-indexed)
local function checkrc(rc, what)
    if rc == 0 then return end
    if tonumber(rc) == SMG_ERR_NOMEM then
        error("smaug: falha de memória ao materializar view (COW detach)", 3)
    end
    error("smaug: backend "..what.." devolveu status "..tonumber(rc)..
          " (esperado SMG_OK=0); invariante interno violado", 3)
end
function Series.new(dtype, size, name)
    if not DTYPES[dtype] then
        error("smaug: dtype desconhecido '"..tostring(dtype)..
              "'. Suportados: float64, int64, string.", 2)
    end
    return wrap(DTYPES[dtype].create(size or 0), dtype, name)
end

function Series.float64(size, name) return Series.new("float64", size, name) end
function Series.int64(size, name)   return Series.new("int64",   size, name) end
function Series.string(size, name)  return Series.new("string",  size, name) end

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

-- Cria a partir de uma tabela Lua. `nil` na tabela vira null.
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

-- =====================================================================
-- Acesso (1-based; nil <-> null)
-- =====================================================================
function methods.get(self, i)
    check_index(self, i)
    if self._d.is_null(self._c, i - 1) then return nil end
    -- get_value do descritor devolve já no tipo Lua certo (number, string, ...).
    return self._d.get_value(self._c, i - 1)
end

function methods.set(self, i, v)
    check_index(self, i)
    if is_na(v) then
        checkrc(self._d.set_null(self._c, i - 1), "set_null")
    else
        check_value(self, v, 3)
        checkrc(self._d.set(self._c, i - 1, v), "set")
    end
end

function methods.is_null(self, i)
    check_index(self, i)
    return self._d.is_null(self._c, i - 1)
end

function methods.set_null(self, i)
    check_index(self, i)
    checkrc(self._d.set_null(self._c, i - 1), "set_null")
end

function methods.append(self, v)
    local rc
    if is_na(v) then
        rc = self._d.append_null(self._c)
    else
        check_value(self, v, 3)
        rc = self._d.append(self._c, v)
    end
    if rc ~= 0 then error("smaug: append falhou (OOM)", 2) end
    return self   -- chainable
end

-- =====================================================================
-- Reduções. ignore_na default = true (comportamento pandas-like).
-- =====================================================================
-- Garante que o dtype suporta a operação `fn_name`; senão, erro claro.
-- (string, por ex., não tem sum/add/sort — em vez do críptico "call a nil
-- value", explica que a operação não se aplica ao dtype.)
local function require_op(self, fn_name, level)
    if self._d[fn_name] == nil then
        error("smaug: operação '" .. fn_name .. "' não se aplica a séries do tipo "
              .. self._dtype, level or 3)
    end
    return self._d[fn_name]
end

local function reduce_num(self, fn_name, ignore_na)
    require_op(self, fn_name, 3)
    if ignore_na == nil then ignore_na = true end
    local v = self._d[fn_name](self._c, ignore_na)
    -- min/max/sum do i64: INT64_MIN é sentinela de "nulo encontrado"
    if (fn_name == "sum" or fn_name == "min" or fn_name == "max")
       and self._d.is_int_sentinel(v) then
        return nil
    end
    v = tonumber(v)
    if is_nan(v) then return nil end
    return v
end

function methods.sum(self, ignore_na)  return reduce_num(self, "sum",  ignore_na) end
function methods.mean(self, ignore_na) return reduce_num(self, "mean", ignore_na) end
function methods.min(self, ignore_na)  return reduce_num(self, "min",  ignore_na) end
function methods.max(self, ignore_na)  return reduce_num(self, "max",  ignore_na) end
function methods.var(self, ignore_na)  return reduce_num(self, "var",  ignore_na) end
function methods.std(self, ignore_na)  return reduce_num(self, "std",  ignore_na) end

-- =====================================================================
-- Análise de distintos
-- =====================================================================

-- unique(): nova Series com os valores distintos na ordem de primeira aparição.
-- Nulos são incluídos (como nil/NA).
function methods.unique(self)
    local n    = self:len()
    local seen = {}
    local vals = {}
    local NA   = Series.NA
    for i = 1, n do
        local v   = self:get(i)
        local key = (v == nil) and "\0NULL\0" or (type(v)..":"..tostring(v))
        if not seen[key] then
            seen[key]    = true
            vals[#vals+1] = (v == nil) and NA or v
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- nunique(): contagem de valores distintos não-nulos.
function methods.nunique(self)
    local seen = {}
    local n    = self:len()
    local c    = 0
    for i = 1, n do
        local v = self:get(i)
        if v ~= nil then
            local key = type(v)..":"..tostring(v)
            if not seen[key] then seen[key] = true; c = c + 1 end
        end
    end
    return c
end

-- value_counts(): DataSet com colunas "value" e "count", ordenado por count desc.
-- Nulos são excluídos da contagem.
function methods.value_counts(self)
    local n     = self:len()
    local cnt   = {}    -- key -> count
    local order = {}    -- preserva primeira aparição para estabilidade
    for i = 1, n do
        local v = self:get(i)
        if v ~= nil then
            local key = type(v)..":"..tostring(v)
            if not cnt[key] then
                cnt[key]         = 0
                order[#order+1] = {key=key, val=v}
            end
            cnt[key] = cnt[key] + 1
        end
    end
    -- ordena por count desc, estável por ordem de aparição
    table.sort(order, function(a, b) return cnt[a.key] > cnt[b.key] end)
    local vals, counts = {}, {}
    local NA = Series.NA
    for _, item in ipairs(order) do
        vals[#vals+1]   = item.val
        counts[#counts+1] = cnt[item.key]
    end
    -- importar DataSet inline para evitar dependência circular
    local DataSet = require("smaug.core.dataset")
    local ds = DataSet.new("value_counts")
    ds:add_column("value", Series.from_table(vals,   self._dtype, "value"))
    ds:add_column("count", Series.from_table(counts, "int64",     "count"))
    return ds
end

-- =====================================================================
-- Transformações elementares (retornam nova Series numérica)
-- =====================================================================

-- abs(): valor absoluto elemento a elemento. Nulos propagam.
function methods.abs(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: abs() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    return self:map(function(v) return v ~= nil and math.abs(v) or nil end, self._dtype, self._name)
end

-- round(ndigits): arredonda para `ndigits` casas decimais (default 0). float64.
function methods.round(self, ndigits)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: round() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    ndigits = ndigits or 0
    local factor = 10 ^ ndigits
    return self:map(function(v)
        if v == nil then return nil end
        -- round half-away-from-zero (comportamento padrão do pandas/Python)
        if v >= 0 then
            return math.floor(v * factor + 0.5) / factor
        else
            return math.ceil(v * factor - 0.5) / factor
        end
    end, "float64", self._name)
end

-- clip(lo, hi): limita valores ao intervalo [lo, hi]. Nulos propagam.
function methods.clip(self, lo, hi)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: clip() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    if lo == nil and hi == nil then return self:clone() end
    return self:map(function(v)
        if v == nil then return nil end
        if lo ~= nil and v < lo then return lo end
        if hi ~= nil and v > hi then return hi end
        return v
    end, self._dtype, self._name)
end

-- =====================================================================
-- Operações de janela temporal (retornam nova Series alinhada)
-- =====================================================================

-- cumsum(): soma cumulativa. Nulos propagam (resultado é NA a partir do 1º nulo).
function methods.cumsum(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: cumsum() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    local acc  = 0
    local null = false
    for i = 1, n do
        local v = self:get(i)
        if v == nil or null then
            null = true; vals[i] = NA
        else
            acc = acc + v; vals[i] = acc
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- cumprod(): produto cumulativo. Nulos propagam.
function methods.cumprod(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: cumprod() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    local acc  = 1
    local null = false
    for i = 1, n do
        local v = self:get(i)
        if v == nil or null then
            null = true; vals[i] = NA
        else
            acc = acc * v; vals[i] = acc
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- diff(periods): diferença entre elemento i e elemento i-periods.
-- Primeiros `periods` elementos são NA. Nulos propagam.
function methods.diff(self, periods)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: diff() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    periods = periods or 1
    if periods < 1 then error("smaug: diff() requer periods >= 1", 2) end
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    for i = 1, n do
        if i <= periods then
            vals[i] = NA
        else
            local cur  = self:get(i)
            local prev = self:get(i - periods)
            vals[i] = (cur == nil or prev == nil) and NA or (cur - prev)
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- shift(periods): desloca os valores `periods` posições para frente (> 0) ou
-- para trás (< 0). Posições descobertas viram NA.
function methods.shift(self, periods)
    periods = periods or 1
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    for i = 1, n do
        local src = i - periods
        if src < 1 or src > n then
            vals[i] = NA
        else
            local v = self:get(src)
            vals[i] = (v == nil) and NA or v
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- =====================================================================
-- Rolling (janela deslizante) na Series
-- Uso: s:rolling(3):sum() / s:rolling(3):mean() / etc.
-- Primeiras (window-1) posições são NA. Nulos dentro da janela são ignorados.
-- =====================================================================
local SeriesRolling = {}
SeriesRolling.__index = SeriesRolling

function SeriesRolling:_agg(fn)
    local col  = self._s
    local n    = col:len()
    local w    = self._window
    local NA   = Series.NA
    local vals = {}
    for i = 1, n do
        if i < w then
            vals[i] = NA
        else
            local wv = {}
            for j = i - w + 1, i do
                local v = col:get(j)
                if v ~= nil then wv[#wv+1] = v end
            end
            vals[i] = fn(wv)
        end
    end
    return Series.from_table(vals, col._dtype, col._name)
end

function SeriesRolling:sum()
    return self:_agg(function(vs)
        local s = 0; for _, v in ipairs(vs) do s = s + v end; return s
    end)
end
function SeriesRolling:mean()
    local col  = self._s
    local n    = col:len()
    local w    = self._window
    local NA   = Series.NA
    local vals = {}
    for i = 1, n do
        if i < w then
            vals[i] = NA
        else
            local wv = {}
            for j = i - w + 1, i do
                local v = col:get(j)
                if v ~= nil then wv[#wv+1] = v end
            end
            if #wv == 0 then vals[i] = NA
            else
                local s = 0; for _, v in ipairs(wv) do s = s + v end
                vals[i] = s / #wv
            end
        end
    end
    return Series.from_table(vals, "float64", col._name)
end
function SeriesRolling:min()
    return self:_agg(function(vs)
        if #vs == 0 then return nil end
        local m = vs[1]; for _, v in ipairs(vs) do if v < m then m = v end end
        return m
    end)
end
function SeriesRolling:max()
    return self:_agg(function(vs)
        if #vs == 0 then return nil end
        local m = vs[1]; for _, v in ipairs(vs) do if v > m then m = v end end
        return m
    end)
end

function methods.rolling(self, window)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: rolling() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    if type(window) ~= "number" or window < 1 or window ~= math.floor(window) then
        error("smaug: rolling — window deve ser inteiro >= 1", 2)
    end
    return setmetatable({ _s = self, _window = window }, SeriesRolling)
end


function methods.count_nonnull(self)
    return tonumber(self._d.count_nonnull(self._c))
end

-- Tamanho da série. NOTA: o operador `#` só chama __len em builds do LuaJIT
-- com compat 5.2; por padrão (5.1) `#serie` não funciona. Use :len().
function methods.len(self)  return tonumber(self._c.size) end
methods.size = methods.len

-- =====================================================================
-- Transformações (retornam nova Series; imutabilidade por padrão)
-- =====================================================================
function methods.clone(self)
    return wrap(self._d.clone(self._c), self._dtype, self._name)
end

function methods.sort(self, ascending)
    if ascending == nil then ascending = true end
    local r = self._d.sort(self._c, ascending)
    if r == nil then
        error("smaug: sort não suporta séries com nulos (use dropna primeiro)", 2)
    end
    return wrap(r, self._dtype, self._name)
end

-- argsort: tabela Lua 1-based de índices que ordenam a série. Devolve `nil` se
-- a série contém nulos (o backend não sabe posicionar NA). Usado por
-- DataSet:sort_by para reordenar todas as colunas pela mesma permutação.
function methods.argsort(self, ascending)
    if ascending == nil then ascending = true end
    local p = self._d.argsort(self._c, ascending)
    if p == nil then return nil end          -- série com nulos
    local n = self:len()
    local idx = {}
    for i = 1, n do idx[i] = tonumber(p[i - 1]) + 1 end   -- 0-based -> 1-based
    C.smaug_free(p)
    return idx
end

-- View: fatia zero-copy [start, start+len-1] (1-based). A view aponta para a
-- memória da pai (read-only) e segura uma referência a ela (_parent) para o GC
-- do Lua não coletar a pai enquanto a view existir.
function methods.view(self, start, len)
    start = start or 1
    len   = len or (self:len() - start + 1)
    local n = self:len()
    if type(start) ~= "number" or type(len) ~= "number"
       or start < 1 or len < 0 or start + len - 1 > n then
        error("smaug: view("..tostring(start)..", "..tostring(len)..
              ") fora dos limites [1, "..n.."]", 2)
    end
    local r = self._d.view(self._c, start - 1, len)
    -- a pai real é a raiz (se self já é view, encadeia para a pai original)
    return wrap(r, self._dtype, self._name, self._parent or self)
end

-- Take: nova série (cópia independente) com os elementos nas posições `idx`
-- (tabela Lua 1-based). Erro se algum índice estiver fora dos limites.
function methods.take(self, idx)
    if type(idx) ~= "table" then error("smaug: take espera uma tabela de índices", 2) end
    local n = self:len()
    local len = #idx
    local cidx = ffi.new("size_t[?]", len)
    for i = 1, len do
        local k = idx[i]
        if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
            error("smaug: take índice "..tostring(k).." fora dos limites [1, "..n.."]", 2)
        end
        cidx[i - 1] = k - 1
    end
    local r = self._d.take(self._c, cidx, len)
    if r == nil then error("smaug: take falhou", 2) end
    return wrap(r, self._dtype, self._name)
end

-- dropna: nova série (cópia) sem os elementos NULL. Funciona para qualquer
-- dtype (reusa take com os índices não-nulos). Útil antes de sort/argsort,
-- que recusam séries com NULL — daí as mensagens "use dropna primeiro".
function methods.dropna(self)
    local n = self:len()
    local idx = {}
    local j = 0
    for i = 1, n do
        if not self:is_null(i) then j = j + 1; idx[j] = i end
    end
    -- take com lista vazia daria série vazia, que é o resultado correto se
    -- tudo for NULL; take já lida com isso.
    return self:take(idx)
end

-- head/tail: nova série (cópia) com as primeiras / últimas n linhas.
function methods.head(self, n)
    n = math.min(n or 5, self:len())
    local idx = {}
    for i = 1, n do idx[i] = i end
    return self:take(idx)
end

function methods.tail(self, n)
    local total = self:len()
    n = math.min(n or 5, total)
    local idx = {}
    for i = 1, n do idx[i] = total - n + i end
    return self:take(idx)
end

-- Converte para tabela Lua. Nulos viram `na_value` (default nil).
function methods.to_table(self, na_value)
    local t = {}
    for i = 1, self:len() do
        local v = self:get(i)
        if v == nil then v = na_value end
        t[i] = v
    end
    return t
end

-- astype: nova série de outro dtype, convertendo valor a valor. Nulos
-- permanecem nulos. f64->i64 trunca em direção a zero (semântica C) — esta é a
-- conversão EXPLÍCITA e intencional (diferente de set/append, que recusam
-- não-inteiros em i64 para evitar coerção acidental; ver CODE_REVIEW A7).
local function trunc_to_int(x)
    -- trunca em direção a zero (igual ao cast (int64_t) do C)
    return x >= 0 and math.floor(x) or math.ceil(x)
end

-- astype(dtype): converte a série para outro dtype, devolvendo uma NOVA série.
-- Contrato de conversão: tolerante a falha por elemento.
--   Elementos inconversíveis tornam-se null — a série inteira nunca é descartada.
--   "abc"→float64 = null | "abc"→int64 = null | NaN→int64 = null | Inf→int64 = null
--   null→qualquer = null (ausência se propaga).
-- Sem coerção implícita: i64 só aceita inteiro (1.5 em i64 vira null, não trunca
-- silenciosamente — exceto na conversão f64→i64, que trunca em direção a zero por
-- ser operação numérica explícita entre tipos de mesma família).
function methods.astype(self, dtype, name)
    if not DTYPES[dtype] then
        error("smaug: dtype desconhecido '" .. tostring(dtype) .. "'", 2)
    end
    local src  = self._dtype
    local n    = self:len()
    local out  = Series.new(dtype, n, name or self._name)

    for i = 1, n do
        local v = self:get(i)
        if v == nil then
            out:set_null(i)
        elseif src == "bool" and dtype ~= "bool" then
            -- bool → numérico: true=1, false=0; bool → string: "true"/"false"
            if dtype == "string" then
                out:set(i, tostring(v))
            elseif dtype == "int64" then
                out:set(i, v and 1 or 0)
            else -- float64
                out:set(i, v and 1.0 or 0.0)
            end
        elseif dtype == "bool" and src ~= "bool" then
            -- numérico/string → bool: 0/""/"false" = false, resto = true; nulo propaga
            if src == "string" then
                if v == "true" then out:set(i, true)
                elseif v == "false" then out:set(i, false)
                else out:set_null(i) end  -- string não reconhecida → null
            else -- numérico
                out:set(i, v ~= 0)
            end
        elseif src == "string" and dtype ~= "string" then
            -- string → numérico: tonumber; falha de parse → null
            local num = tonumber(v)
            if num == nil then
                out:set_null(i)
            elseif dtype == "int64" then
                -- mesmo contrato do f64→i64: NaN/Inf → null, resto trunca
                if num ~= num or num == math.huge or num == -math.huge then
                    out:set_null(i)
                else
                    out:set(i, trunc_to_int(num))
                end
            else
                out:set(i, num)
            end
        elseif dtype == "string" and src ~= "string" then
            -- numérico → string: tostring; NaN/Inf viram suas representações
            -- (NaN é valor presente no Smaug — não vira null na conversão)
            out:set(i, tostring(v))
        elseif dtype == "int64" and src ~= "int64" then
            -- f64 → i64: NaN/Inf → null, resto trunca em direção a zero
            if v ~= v or v == math.huge or v == -math.huge then
                out:set_null(i)
            else
                out:set(i, trunc_to_int(v))
            end
        else
            -- mesmo dtype ou f64→f64, i64→i64: cópia direta
            out:set(i, v)
        end
    end
    return out
end

-- fillna: devolve NOVA Series com cada NULL substituído por `value`.
-- Contrato: sem argumento = erro; sem coerção de tipo (i64 só aceita inteiro);
-- preenche NULL (ausência), NÃO NaN (NaN é valor presente — fica intacto).
-- Posições não-nulas inalteradas. Não altera o dtype.
function methods.fillna(self, value)
    if value == nil or value == NA then
        error("smaug: fillna requer um valor de preenchimento", 2)
    end
    local dt = self._dtype
    -- validação dtype-aware: sem coerção, o valor deve casar com o tipo da série
    if dt == "string" then
        if type(value) ~= "string" then
            error("smaug: fillna em série string espera uma string Lua; "
                  .. "recebido " .. type(value), 2)
        end
    elseif dt == "bool" then
        if type(value) ~= "boolean" then
            error("smaug: fillna em série bool espera boolean (true/false); "
                  .. "recebido " .. type(value), 2)
        end
    else
        if type(value) ~= "number" then
            error("smaug: fillna em série " .. dt .. " espera um número; "
                  .. "recebido " .. type(value), 2)
        end
        -- sem coerção: i64 só aceita inteiro (1.5 em i64 é erro, não trunca)
        if dt == "int64" and value % 1 ~= 0 then
            error("smaug: fillna em int64 requer valor inteiro (sem coerção); "
                  .. "recebido " .. tostring(value), 2)
        end
    end
    local n = self:len()
    local out = Series.new(dt, n, self._name)
    for i = 1, n do
        if self:is_null(i) then
            out:set(i, value)           -- preenche o null
        else
            out:set(i, self:get(i))     -- copia o valor (NaN incluso)
        end
    end
    return out
end

-- map(fn, dtype?): aplica fn a cada elemento, devolvendo nova Series.
-- Contrato:
--   nil retornado -> null na saída (semântica de ausência já estabelecida).
--   dtype omitido -> inferido do primeiro retorno não-null.
--   dtype explícito -> prevalece; retornos devem ser compatíveis.
--   tipos mistos -> erro imediato (sem coerção silenciosa).
--   série toda-null (ou fn retorna nil em todos) -> série null do dtype
--     informado; sem dtype -> erro (impossível inferir).
-- fn recebe o valor Lua (nil se null) e o índice 1-based.
-- O índice permite: fn(v, i) -> construções dependentes de posição.
local function infer_from_value(v)
    local t = type(v)
    if t == "string"  then return "string" end
    if t == "number"  then
        return (v % 1 == 0) and "int64" or "float64"
    end
    return nil   -- tipo não suportado
end

local function check_map_value(v, dtype, i)
    if dtype == "int64" then
        if type(v) ~= "number" or v % 1 ~= 0 then
            error("smaug: map: tipo inconsistente no índice " .. i
                  .. " (esperado int64, recebido " .. type(v) .. ")", 4)
        end
    elseif dtype == "string" then
        if type(v) ~= "string" then
            error("smaug: map: tipo inconsistente no índice " .. i
                  .. " (esperado string, recebido " .. type(v) .. ")", 4)
        end
    else  -- float64
        if type(v) ~= "number" then
            error("smaug: map: tipo inconsistente no índice " .. i
                  .. " (esperado float64, recebido " .. type(v) .. ")", 4)
        end
    end
end

function methods.map(self, fn, dtype, name)
    if type(fn) ~= "function" then
        error("smaug: map espera uma função como 1º argumento", 2)
    end
    if dtype ~= nil and not DTYPES[dtype] then
        error("smaug: map: dtype desconhecido '" .. tostring(dtype) .. "'", 2)
    end

    local n       = self:len()
    local results = {}      -- coleta todos os retornos antes de alocar
    local inferred = dtype  -- nil = ainda não inferido

    -- passo 1: aplica fn, infere dtype, valida consistência
    for i = 1, n do
        local v  = self:get(i)   -- nil se null
        local r  = fn(v, i)
        if r == nil or r == NA then
            results[i] = nil     -- null na saída
        else
            local rt = infer_from_value(r)
            if rt == nil then
                error("smaug: map: retorno de tipo não suportado no índice "
                      .. i .. " (" .. type(r) .. ")", 2)
            end
            if inferred == nil then
                inferred = rt    -- primeiro não-null: fixa o dtype
            else
                -- valida consistência (sem coerção silenciosa)
                check_map_value(r, inferred, i)
            end
            results[i] = r
        end
    end

    -- passo 2: sem dtype e série toda-null -> erro (impossível inferir)
    if inferred == nil then
        error("smaug: map: todos os retornos são nil — informe dtype explicitamente", 2)
    end

    -- passo 3: monta a série de saída
    local out = Series.new(inferred, n, name or self._name)
    for i = 1, n do
        if results[i] == nil then
            out:set_null(i)
        else
            out:set(i, results[i])
        end
    end
    return out
end

-- describe: resumo estatístico (tabela Lua). Percentis calculados a partir dos
-- valores não-nulos ordenados em Lua (não exige dropna no C).
function methods.describe(self)
    local n = self:len()
    local nulls = n - self:count_nonnull()
    -- bool: estatísticas categóricas (count_true, count_false, nulls)
    if self._dtype == "bool" then
        local count_true = 0
        for i = 1, n do
            local v = self:get(i)
            if v == true then count_true = count_true + 1 end
        end
        return {
            count       = n - nulls,
            nulls       = nulls,
            count_true  = count_true,
            count_false = (n - nulls) - count_true,
        }
    end
    -- string: estatísticas categóricas (sem média/std/percentis)
    if self._dtype == "string" then
        local freq = {}
        local top, top_freq = nil, 0
        for i = 1, n do
            local v = self:get(i)
            if v ~= nil then
                freq[v] = (freq[v] or 0) + 1
                if freq[v] > top_freq then top, top_freq = v, freq[v] end
            end
        end
        return {
            count  = n - nulls,
            nulls  = nulls,
            unique = (function()
                local u = 0
                for _ in pairs(freq) do u = u + 1 end
                return u
            end)(),
            top    = top,
            freq   = top_freq > 0 and top_freq or nil,
        }
    end
    -- numérico: estatísticas contínuas
    local vals = {}
    for i = 1, n do
        local v = self:get(i)
        if v ~= nil then vals[#vals + 1] = v end
    end
    table.sort(vals)
    local m = #vals
    local function pct(p)
        if m == 0 then return nil end
        if m == 1 then return vals[1] end
        local rank = p * (m - 1) + 1
        local lo = math.floor(rank)
        local frac = rank - lo
        if lo >= m then return vals[m] end
        return vals[lo] + frac * (vals[lo + 1] - vals[lo])
    end
    return {
        count   = m,
        nulls   = nulls,
        mean    = self:mean(),
        std     = self:std(),
        min     = self:min(),
        ["25%"] = pct(0.25),
        ["50%"] = pct(0.50),
        ["75%"] = pct(0.75),
        max     = self:max(),
    }
end

-- =====================================================================
-- Comparações -> Series<bool>, e filtragem
-- =====================================================================

-- Helper: extrai (uint8_t* vals, smaug_mask_t* nulls, size_t n) de uma
-- Series<bool>. Retorna nil se o argumento não for uma Series<bool> válida.
local function bool_mask_parts(mask)
    if type(mask) == "table" and mask._dtype == "bool" then
        return mask._c.data, mask._c.null_mask, tonumber(mask._c.size)
    end
    return nil
end

-- Constrói uma Series<bool> a partir de arrays crus (uint8_t* vals,
-- smaug_mask_t* nulls, size_t n). Copia os dados e libera os originais.
local function bool_series_from_raw(vals, nulls, n, name)
    local s = C.smaug_bool_create(n)
    if s == nil then
        C.smaug_free(vals)
        if nulls ~= nil then C.smaug_free(nulls) end
        error("smaug: OOM ao criar Series<bool>", 3)
    end
    for i = 0, n - 1 do
        s.data[i]      = vals[i]
        s.null_mask[i] = nulls ~= nil and nulls[i] or 0xFF
    end
    C.smaug_free(vals)
    if nulls ~= nil then C.smaug_free(nulls) end
    return wrap(ffi.gc(s, C.smaug_bool_free), "bool", name)
end

local function compare(self, cmp_name, target)
    local wrapper = self._d[cmp_name]
    if wrapper == nil then
        error("smaug: comparação '" .. cmp_name .. "' não se aplica ao tipo "
              .. self._dtype, 3)
    end
    local om = ffi.new("smaug_mask_t*[1]")
    local vals = wrapper(self._c, target, om)
    if vals == nil then error("smaug: comparação falhou", 3) end
    return bool_series_from_raw(vals, om[0], self:len(), self._name)
end

function methods.gt(self, target) return compare(self, "cmp_gt", target) end
function methods.lt(self, target) return compare(self, "cmp_lt", target) end
function methods.eq(self, target) return compare(self, "cmp_eq", target) end
function methods.ge(self, target) return compare(self, "cmp_ge", target) end
function methods.le(self, target) return compare(self, "cmp_le", target) end
function methods.ne(self, target) return compare(self, "cmp_ne", target) end

-- filter(mask): nova Series só com as linhas onde a máscara é true.
-- Aceita Series<bool> (novo) ou BoolSeries (legado).
function methods.filter(self, mask)
    local vals, _, mlen = bool_mask_parts(mask)
    if vals == nil then
        error("smaug: filter espera uma Series<bool> ou BoolSeries (use :gt/:lt/:eq)", 2)
    end
    if mlen ~= self:len() then
        error("smaug: filter com máscara de tamanho diferente ("..
              mlen.." vs "..self:len()..")", 2)
    end
    local r = self._d.filter(self._c, vals)
    if r == nil then error("smaug: filter falhou", 2) end
    return wrap(r, self._dtype, self._name)
end

-- =====================================================================
-- Lógica Kleene para Series<bool> (land/lor/lxor/lnot).
-- Espelham os métodos da BoolSeries legada, usando as funções struct-based
-- do Anel 0 (smaug_bool_series_and/or/xor/not).
-- =====================================================================
local function kleene_binop(a, b, fn, opname)
    if a._dtype ~= "bool" then
        error("smaug: " .. opname .. " requer Series<bool>", 3)
    end
    local bv
    if type(b) == "table" and b._dtype == "bool" then
        bv = b._c
    else
        error("smaug: " .. opname .. " requer Series<bool>", 3)
    end
    local r = fn(a._c, bv)
    if r == nil then error("smaug: " .. opname .. " falhou (tamanhos diferentes ou OOM)", 3) end
    return wrap(ffi.gc(r, C.smaug_bool_free), "bool", a._name)
end

function methods.land(self, other)
    return kleene_binop(self, other, C.smaug_bool_series_and, "land")
end
function methods.lor(self, other)
    return kleene_binop(self, other, C.smaug_bool_series_or, "lor")
end
function methods.lxor(self, other)
    return kleene_binop(self, other, C.smaug_bool_series_xor, "lxor")
end
function methods.lnot(self)
    if self._dtype ~= "bool" then
        error("smaug: lnot requer Series<bool>", 2)
    end
    local r = C.smaug_bool_series_not(self._c)
    if r == nil then error("smaug: lnot falhou (OOM)", 2) end
    return wrap(ffi.gc(r, C.smaug_bool_free), "bool", self._name)
end

-- Agregações booleanas: count_true, any, all.
-- Espelham os métodos da BoolSeries, usando funções struct-based do Anel 0.
function methods.count_true(self)
    if self._dtype ~= "bool" then
        error("smaug: count_true requer Series<bool>", 2)
    end
    return tonumber(C.smaug_bool_series_count_true(self._c))
end
function methods.any(self)
    if self._dtype ~= "bool" then
        error("smaug: any requer Series<bool>", 2)
    end
    return C.smaug_bool_series_any(self._c)
end
function methods.all(self)
    if self._dtype ~= "bool" then
        error("smaug: all requer Series<bool>", 2)
    end
    return C.smaug_bool_series_all(self._c)
end

-- =====================================================================
-- Aritmética (metamétodos). Series±Series exige mesmo dtype e tamanho.
-- =====================================================================
local function both_series(a, b)
    return getmetatable(a) == Series and getmetatable(b) == Series
end

local function binop(a, b, series_fn, scalar_fn, scalar_left_ok, opname)
    -- Series op Series
    if both_series(a, b) then
        if a._dtype ~= b._dtype then
            error("smaug: '"..opname.."' entre dtypes diferentes ("..
                  a._dtype.." e "..b._dtype..") não é permitido", 2)
        end
        if a._c.size ~= b._c.size then
            error("smaug: '"..opname.."' entre séries de tamanhos diferentes", 2)
        end
        -- Series<bool>: operadores aritméticos mapeiam para Kleene
        -- (+ = or, - = xor, * = and), espelhando o comportamento da BoolSeries.
        if a._dtype == "bool" then
            local kleene_fn = (series_fn == "add") and C.smaug_bool_series_or
                           or (series_fn == "sub") and C.smaug_bool_series_xor
                           or (series_fn == "mul") and C.smaug_bool_series_and
                           or nil
            if kleene_fn == nil then
                error("smaug: operação '"..opname.."' não se aplica a Series<bool>", 2)
            end
            local r = kleene_fn(a._c, b._c)
            if r == nil then error("smaug: '"..opname.."' falhou", 2) end
            return wrap(ffi.gc(r, C.smaug_bool_free), "bool", a._name)
        end
        local r = a._d[series_fn](a._c, b._c)
        if r == nil then error("smaug: '"..opname.."' falhou", 2) end
        return wrap(r, a._dtype, a._name)
    end
    -- Series op scalar  (a é Series, b é número)
    if getmetatable(a) == Series and type(b) == "number" then
        local r = a._d[scalar_fn](a._c, b)
        return wrap(r, a._dtype, a._name)
    end
    -- scalar op Series  (a é número, b é Series)
    if type(a) == "number" and getmetatable(b) == Series then
        if scalar_left_ok == "commute" then
            local r = b._d[scalar_fn](b._c, a)
            return wrap(r, b._dtype, b._name)
        end
        error("smaug: 'escalar "..opname.." Series' não é suportado; "..
              "inverta a ordem ou use métodos explícitos", 2)
    end
    error("smaug: operandos inválidos para '"..opname.."'", 2)
end

Series.__add = function(a, b) return binop(a, b, "add", "add_scalar", "commute", "+") end
Series.__mul = function(a, b) return binop(a, b, "mul", "mul_scalar", "commute", "*") end
Series.__sub = function(a, b) return binop(a, b, "sub", "sub_scalar", false,      "-") end
Series.__div = function(a, b) return binop(a, b, "div", "div_scalar", false,      "/") end

-- =====================================================================
-- Metamétodos de inspeção/acesso
-- =====================================================================
Series.__len = function(self) return tonumber(self._c.size) end

Series.__tostring = function(self)
    local n = tonumber(self._c.size)
    local parts = {}
    local limit = math.min(n, 10)
    for i = 1, limit do
        local v = self:get(i)
        parts[#parts + 1] = string.format("  [%d] %s", i,
            v == nil and "NA" or tostring(v))
    end
    if n > limit then parts[#parts + 1] = "  ... ("..(n - limit).." mais)" end
    return string.format("Series '%s' (%s, len=%d)\n%s",
        self._name, self._dtype, n, table.concat(parts, "\n"))
end

-- =====================================================================
-- Accessor .str — operações sobre séries do tipo string.
-- s.str devolve um proxy com os 7 métodos Tier A; erro claro se o dtype
-- não for string. Todas as operações propagam null: elemento null na entrada
-- -> null na saída. Sem C novo: tudo em Lua sobre smaug_str_get.
-- Semântica de bytes (não Unicode): len = bytes, lower/upper = ASCII only.
-- =====================================================================
local StrProxy = {}
StrProxy.__index = StrProxy

-- Helpers internos para as operações mais usadas.
-- new_str_series: aloca Series string de tamanho n e preenche via iterador.
local function str_map(src, fn)
    -- fn(v: string | nil) -> string | nil
    local n   = src:len()
    local out = Series.new("string", n, src._name)
    for i = 1, n do
        local v = src:get(i)
        if v == nil then
            out:set_null(i)
        else
            local r = fn(v)
            if r == nil then out:set_null(i) else out:set(i, r) end
        end
    end
    return out
end

-- bool_map: itera e devolve Series<bool> (null -> NA na máscara).
local function bool_map(src, fn)
    local n = src:len()
    local s = C.smaug_bool_create(n)
    if s == nil then error("smaug: OOM em bool_map", 2) end
    for i = 1, n do
        local v = src:get(i)
        if v == nil then
            C.smaug_bool_set_null(s, i - 1)
        else
            C.smaug_bool_set(s, i - 1, fn(v) and 1 or 0)
        end
    end
    return wrap(ffi.gc(s, C.smaug_bool_free), "bool", src._name)
end

-- len(): comprimento em bytes de cada elemento -> Series int64.
-- Null -> null. String vazia "" -> 0.
function StrProxy:len()
    local n   = self._s:len()
    local out = Series.new("int64", n, self._s._name)
    for i = 1, n do
        local v = self._s:get(i)
        if v == nil then out:set_null(i) else out:set(i, #v) end
    end
    return out
end

-- lower() / upper(): conversão ASCII de caixa -> nova Series string.
-- Null -> null. Apenas bytes ASCII 65-90 / 97-122 são alterados
-- (semântica de bytes; sem Unicode).
function StrProxy:lower()
    return str_map(self._s, string.lower)
end

function StrProxy:upper()
    return str_map(self._s, string.upper)
end

-- strip(): remove espaços e tabulações das extremidades -> nova Series string.
-- Padrão Lua %s inclui: espaço, \t, \n, \r, \f, \v.
function StrProxy:strip()
    return str_map(self._s, function(v)
        return (v:match("^%s*(.-)%s*$"))
    end)
end

-- contains(sub): Series<bool> true onde a string contém a substring `sub`.
-- Null -> NA. String vazia "" é substring de qualquer string.
function StrProxy:contains(sub)
    if type(sub) ~= "string" then
        error("smaug: str:contains espera uma string; recebido " .. type(sub), 2)
    end
    return bool_map(self._s, function(v) return v:find(sub, 1, true) ~= nil end)
end

-- startswith(prefix): Series<bool> true onde a string começa com `prefix`.
function StrProxy:startswith(prefix)
    if type(prefix) ~= "string" then
        error("smaug: str:startswith espera uma string; recebido " .. type(prefix), 2)
    end
    local n = #prefix
    return bool_map(self._s, function(v) return v:sub(1, n) == prefix end)
end

-- endswith(suffix): Series<bool> true onde a string termina com `suffix`.
function StrProxy:endswith(suffix)
    if type(suffix) ~= "string" then
        error("smaug: str:endswith espera uma string; recebido " .. type(suffix), 2)
    end
    local n = #suffix
    return bool_map(self._s, function(v)
        return n == 0 or v:sub(-n) == suffix
    end)
end

-- replace(old, new): substitui todas as ocorrências literais de `old` por `new`
-- -> nova Series string. Null -> null. old vazio não substitui nada (retorna
-- cópia). Semântica de bytes (não regex, não Unicode).
function StrProxy:replace(old, new)
    if type(old) ~= "string" then
        error("smaug: str:replace espera string como 1º argumento; recebido " .. type(old), 2)
    end
    if type(new) ~= "string" then
        error("smaug: str:replace espera string como 2º argumento; recebido " .. type(new), 2)
    end
    if #old == 0 then
        return str_map(self._s, function(v) return v end)
    end
    local esc_old = old:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local esc_new = new:gsub("%%", "%%%%")
    return str_map(self._s, function(v)
        return (v:gsub(esc_old, esc_new))
    end)
end

-- =====================================================================
-- .str Tier B
-- =====================================================================

-- find(sub): índice (1-based) da primeira ocorrência de `sub`, ou 0 se ausente.
-- Null -> null. String vazia sub -> 0 (comportamento estável).
function StrProxy:find(sub)
    if type(sub) ~= "string" then
        error("smaug: str:find espera uma string; recebido " .. type(sub), 2)
    end
    local n   = self._s:len()
    local out = Series.new("int64", n, self._s._name)
    for i = 1, n do
        local v = self._s:get(i)
        if v == nil then
            out:set_null(i)
        else
            local pos = v:find(sub, 1, true)
            out:set(i, pos or 0)
        end
    end
    return out
end

-- slice(start, [stop]): substring de `start` até `stop` (1-based, inclusivo).
-- Índices negativos contam do fim. Null -> null.
-- Se stop for omitido, vai até o final.
function StrProxy:slice(start, stop)
    if type(start) ~= "number" then
        error("smaug: str:slice espera número como start; recebido " .. type(start), 2)
    end
    return str_map(self._s, function(v)
        return v:sub(start, stop)
    end)
end

-- pad(width, [side], [fillchar]): preenche até `width` caracteres.
-- side: "left" (default), "right", "both".
-- fillchar: caractere de preenchimento (default " ").
-- Null -> null. Strings mais longas que `width` são retornadas intactas.
function StrProxy:pad(width, side, fillchar)
    if type(width) ~= "number" or width < 0 then
        error("smaug: str:pad espera width >= 0; recebido " .. tostring(width), 2)
    end
    side     = side     or "left"
    fillchar = fillchar or " "
    if #fillchar ~= 1 then
        error("smaug: str:pad fillchar deve ter exatamente 1 caractere", 2)
    end
    if side ~= "left" and side ~= "right" and side ~= "both" then
        error("smaug: str:pad side deve ser 'left', 'right' ou 'both'", 2)
    end
    return str_map(self._s, function(v)
        local missing = width - #v
        if missing <= 0 then return v end
        if side == "right" then
            return v .. fillchar:rep(missing)
        elseif side == "left" then
            return fillchar:rep(missing) .. v
        else  -- both: metade à esquerda, metade à direita
            local left  = math.floor(missing / 2)
            local right = missing - left
            return fillchar:rep(left) .. v .. fillchar:rep(right)
        end
    end)
end

-- zfill(width): preenche com '0' à esquerda até `width` caracteres.
-- Equivalente a str:pad(width, "left", "0"). Null -> null.
function StrProxy:zfill(width)
    return self:pad(width, "left", "0")
end

-- rep(n, [sep]): repete a string `n` vezes, separada por `sep` (default "").
-- n deve ser >= 0. n=0 -> string vazia. Null -> null.
function StrProxy:rep(n, sep)
    if type(n) ~= "number" or n < 0 or n ~= math.floor(n) then
        error("smaug: str:rep espera inteiro >= 0; recebido " .. tostring(n), 2)
    end
    sep = sep or ""
    return str_map(self._s, function(v)
        if n == 0 then return "" end
        return string.rep(v, n, sep)
    end)
end

-- cat([sep]): concatena todos os valores não-nulos numa única string Lua.
-- sep: separador (default ""). Nulos são ignorados.
-- Retorna string Lua (não Series).
function StrProxy:cat(sep)
    sep = sep or ""
    local parts = {}
    local n = self._s:len()
    for i = 1, n do
        local v = self._s:get(i)
        if v ~= nil then parts[#parts+1] = v end
    end
    return table.concat(parts, sep)
end

-- split(sep, [n]): divide cada elemento pelo separador `sep`.
-- Retorna uma tabela Lua de Series string (uma por posição de resultado).
-- Posições sem valor (split curto) ficam como NA. Nulos na entrada -> NA em todas.
-- n: número máximo de splits (0 = ilimitado, default).
-- Nota: retorna tabela, não DataSet, para manter o tipo correto.
function StrProxy:split(sep, max_splits)
    if type(sep) ~= "string" or #sep == 0 then
        error("smaug: str:split espera separador string não-vazio", 2)
    end
    max_splits = max_splits or 0

    local rows = self._s:len()
    -- primeiro passo: descobrir o máximo de partes para alocar as Series
    local all_parts = {}
    local max_parts = 0
    local sep_len = #sep
    for i = 1, rows do
        local v = self._s:get(i)
        if v == nil then
            all_parts[i] = nil
        else
            local parts = {}
            local start = 1
            local count = 0
            while true do
                local found = v:find(sep, start, true)
                if not found or (max_splits > 0 and count >= max_splits) then
                    parts[#parts+1] = v:sub(start)
                    break
                end
                parts[#parts+1] = v:sub(start, found - 1)
                start = found + sep_len
                count = count + 1
            end
            all_parts[i] = parts
            if #parts > max_parts then max_parts = #parts end
        end
    end

    -- construir uma Series por posição
    local NA = Series.NA
    local result = {}
    for col = 1, max_parts do
        local vals = {}
        for i = 1, rows do
            local parts = all_parts[i]
            if parts == nil or parts[col] == nil then
                vals[i] = NA
            else
                vals[i] = parts[col]
            end
        end
        result[col] = Series.from_table(vals, "string")
    end
    return result  -- tabela Lua de Series; col = result[1], result[2], ...
end

-- __index: índice numérico -> get(); "str" em série string -> proxy; senão, método.
Series.__index = function(self, k)
    if type(k) == "number" then return methods.get(self, k) end
    if k == "str" then
        if self._dtype ~= "string" then
            error("smaug: accessor .str só se aplica a séries string; dtype é '"
                  .. self._dtype .. "'", 2)
        end
        return setmetatable({ _s = self }, StrProxy)
    end
    return methods[k]
end

-- __newindex: série[i] = v -> set(); outras chaves gravam no objeto.
Series.__newindex = function(self, k, v)
    if type(k) == "number" then methods.set(self, k, v)
    else rawset(self, k, v) end
end

-- expõe o registro de dtypes para extensão futura (bool, string, ...)
Series._DTYPES = DTYPES
Series.NA = NA

return Series
