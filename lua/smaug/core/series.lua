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
        -- Grupo A (Fase 3 Ring 0): janela e redução posicional
        cumsum  = C.smaug_f64_cumsum,
        cumprod = C.smaug_f64_cumprod,
        cummin  = C.smaug_f64_cummin,
        cummax  = C.smaug_f64_cummax,
        diff    = C.smaug_f64_diff,
        shift   = C.smaug_f64_shift,
        ffill   = C.smaug_f64_ffill,
        bfill   = C.smaug_f64_bfill,
        argmin  = C.smaug_f64_argmin,
        argmax  = C.smaug_f64_argmax,
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
        -- Grupo A (Fase 3 Ring 0): janela e redução posicional
        cumsum  = C.smaug_i64_cumsum,
        cumprod = C.smaug_i64_cumprod,
        cummin  = C.smaug_i64_cummin,
        cummax  = C.smaug_i64_cummax,
        diff    = C.smaug_i64_diff,
        shift   = C.smaug_i64_shift,
        ffill   = C.smaug_i64_ffill,
        bfill   = C.smaug_i64_bfill,
        argmin  = C.smaug_i64_argmin,
        argmax  = C.smaug_i64_argmax,
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
    -- datetime: epoch ms UTC (int64 internamente). Dtype Tier 2.
    -- Valores: int64 Lua (epoch_ms). Nulos via bitmask uniforme.
    -- Parsing/formatação via C; componentes calendário via funções C.
    -- ----------------------------------------------------------------
    datetime = {
        name        = "datetime",
        free        = C.smaug_dt_free,
        create      = C.smaug_dt_create,
        clone       = C.smaug_dt_clone,
        get_value   = function(c, i)
            local st = ffi.new("smaug_status_t[1]")
            local v  = C.smaug_dt_get(c, i, st)
            if st[0] ~= 0 then return nil end
            return tonumber(v)   -- epoch_ms como número Lua
        end,
        set = function(c, i, v)
            -- aceita número inteiro (epoch_ms) ou string ISO 8601
            if type(v) == "string" then
                local ep = ffi.new("int64_t[1]")
                if C.smaug_dt_parse(v, #v, ep) ~= 0 then
                    error("smaug: datetime parse falhou: " .. v, 3)
                end
                return C.smaug_dt_set(c, i, ep[0])
            end
            return C.smaug_dt_set(c, i, v)
        end,
        set_null    = C.smaug_dt_set_null,
        is_null     = C.smaug_dt_is_null,
        append = function(c, v)
            if type(v) == "string" then
                local ep = ffi.new("int64_t[1]")
                if C.smaug_dt_parse(v, #v, ep) ~= 0 then
                    error("smaug: datetime parse falhou: " .. v, 3)
                end
                return C.smaug_dt_append(c, ep[0])
            end
            return C.smaug_dt_append(c, v)
        end,
        append_null = C.smaug_dt_append_null,
        count_nonnull = C.smaug_dt_count_nonnull,
        filter  = C.smaug_dt_filter,
        take    = C.smaug_dt_take,
        sort    = C.smaug_dt_sort,
        argsort = C.smaug_dt_argsort,
        cmp_gt = function(c, t, om) return C.smaug_dt_gt(c, t, om) end,
        cmp_lt = function(c, t, om) return C.smaug_dt_lt(c, t, om) end,
        cmp_eq = function(c, t, om) return C.smaug_dt_eq(c, t, om) end,
        cmp_ge = function(c, t, om) return C.smaug_dt_ge(c, t, om) end,
        cmp_le = function(c, t, om) return C.smaug_dt_le(c, t, om) end,
        cmp_ne = function(c, t, om) return C.smaug_dt_ne(c, t, om) end,
        is_int_sentinel = function(v)
            -- INT64_MIN como sentinela (mesmo padrão do i64)
            return v == -9223372036854775808
        end,
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
    elseif dt == "datetime" then
        -- aceita número (epoch_ms) ou string ISO 8601
        if type(v) ~= "number" and type(v) ~= "string" then
            error("smaug: valor para datetime deve ser número (epoch_ms) ou string ISO 8601; "
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

-- cumsum(): soma cumulativa. Null na posição i → null em [i, n-1].
function methods.cumsum(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: cumsum() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    local r = self._d.cumsum(self._c)
    if r == nil then error("smaug: cumsum falhou (OOM)", 2) end
    return wrap(r, self._dtype, self._name)
end

-- cumprod(): produto cumulativo. Null propaga igual ao cumsum.
function methods.cumprod(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: cumprod() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    local r = self._d.cumprod(self._c)
    if r == nil then error("smaug: cumprod falhou (OOM)", 2) end
    return wrap(r, self._dtype, self._name)
end

-- diff(periods): diferença entre elemento i e elemento i-periods.
-- Primeiros `periods` elementos são NA. Nulos propagam.
-- Numérico (f64/i64): delega para C. Datetime: permanece em Lua (usa smaug_dt_diff_ms).
function methods.diff(self, periods)
    if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
        error("smaug: diff() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
    end
    periods = periods or 1
    if periods < 1 then error("smaug: diff() requer periods >= 1", 2) end
    -- datetime: diferença de epochs via smaug_dt_diff_ms → int64 (ms)
    if self._dtype == "datetime" then
        local NA   = Series.NA
        local n    = self:len()
        local vals = {}
        for i = 1, n do
            if i <= periods then
                vals[i] = NA
            else
                local a = self:get(i)
                local b = self:get(i - periods)
                vals[i] = (a ~= nil and b ~= nil) and tonumber(C.smaug_dt_diff_ms(a, b)) or NA
            end
        end
        return Series.from_table(vals, "int64", self._name)
    end
    -- numérico: C
    local r = self._d.diff(self._c, periods)
    if r == nil then error("smaug: diff falhou (OOM)", 2) end
    return wrap(r, self._dtype, self._name)
end

-- shift(periods): desloca os valores `periods` posições para frente (> 0) ou
-- para trás (< 0). Posições descobertas viram NA.
-- periods > 0: C (size_t, caso comum). periods <= 0: Lua.
function methods.shift(self, periods)
    periods = periods or 1
    if type(periods) ~= "number" or periods % 1 ~= 0 then
        error("smaug: shift() requer periods inteiro", 2)
    end
    if periods > 0 and self._d.shift then
        -- caminho rápido C: deslocamento positivo
        local r = self._d.shift(self._c, periods)
        if r == nil then error("smaug: shift falhou (OOM)", 2) end
        return wrap(r, self._dtype, self._name)
    end
    -- Lua: periods <= 0 ou dtype sem C (datetime/string/bool)
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
-- F.1 — Pacote estatístico (Series)
-- corr, cov, autocorr, dot, pct_change.
-- Pearson para corr/cov; pares com qualquer null são ignorados.
-- =====================================================================

-- Helper: coleta os pares (x_i, y_i) onde AMBOS são não-nulos.
-- Exige mesmo comprimento. Retorna duas tabelas paralelas xs, ys e o n efetivo.
local function paired_nonnull(a, b)
    if getmetatable(b) ~= Series then
        error("smaug: esperado outra Series como argumento", 3)
    end
    if a:len() ~= b:len() then
        error("smaug: séries de tamanhos diferentes ("..a:len().." vs "..b:len()..")", 3)
    end
    local xs, ys, m = {}, {}, 0
    for i = 1, a:len() do
        local x, y = a:get(i), b:get(i)
        if x ~= nil and y ~= nil then
            m = m + 1
            xs[m] = x; ys[m] = y
        end
    end
    return xs, ys, m
end

-- cov(other): covariância amostral de Pearson (divide por n-1).
-- Pares com qualquer null são pulados. Menos de 2 pares válidos → NaN.
function methods.cov(self, other)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: cov() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    local xs, ys, m = paired_nonnull(self, other)
    if m < 2 then return 0/0 end   -- NaN: variância amostral indefinida
    local mx, my = 0, 0
    for i = 1, m do mx = mx + xs[i]; my = my + ys[i] end
    mx = mx / m; my = my / m
    local acc = 0
    for i = 1, m do acc = acc + (xs[i] - mx) * (ys[i] - my) end
    return acc / (m - 1)
end

-- corr(other): correlação de Pearson ∈ [-1, 1].
-- Pares com null pulados. Menos de 2 pares ou variância zero → NaN.
function methods.corr(self, other)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: corr() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    local xs, ys, m = paired_nonnull(self, other)
    if m < 2 then return 0/0 end
    local mx, my = 0, 0
    for i = 1, m do mx = mx + xs[i]; my = my + ys[i] end
    mx = mx / m; my = my / m
    local sxy, sxx, syy = 0, 0, 0
    for i = 1, m do
        local dx, dy = xs[i] - mx, ys[i] - my
        sxy = sxy + dx * dy
        sxx = sxx + dx * dx
        syy = syy + dy * dy
    end
    local denom = math.sqrt(sxx * syy)
    if denom == 0 then return 0/0 end   -- variância zero: correlação indefinida
    return sxy / denom
end

-- autocorr([lag]): correlação da série com ela mesma deslocada `lag` (default 1).
-- = self:corr(self:shift(lag)). Pares descobertos pelo shift são null → pulados.
function methods.autocorr(self, lag)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: autocorr() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    lag = lag or 1
    return self:corr(self:shift(lag))
end

-- dot(other): produto interno Σ xᵢ·yᵢ. Qualquer par com null → resultado null (nil).
-- Diferente de cov/corr: dot propaga null em vez de pular o par.
function methods.dot(self, other)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: dot() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    if getmetatable(other) ~= Series then
        error("smaug: dot() espera outra Series como argumento", 2)
    end
    if self:len() ~= other:len() then
        error("smaug: dot() — tamanhos diferentes ("..self:len().." vs "..other:len()..")", 2)
    end
    local acc = 0
    for i = 1, self:len() do
        local x, y = self:get(i), other:get(i)
        if x == nil or y == nil then return nil end   -- null propaga
        acc = acc + x * y
    end
    return acc
end

-- pct_change([periods]): variação percentual = (xᵢ - xᵢ₋ₚ) / xᵢ₋ₚ.
-- Primeiros `periods` elementos são NA. Null em qualquer operando → NA.
-- Divisor zero → NA (não Inf), por previsibilidade. Resultado sempre float64.
function methods.pct_change(self, periods)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: pct_change() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    periods = periods or 1
    if periods < 1 then error("smaug: pct_change() requer periods >= 1", 2) end
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    for i = 1, n do
        if i <= periods then
            vals[i] = NA
        else
            local cur  = self:get(i)
            local prev = self:get(i - periods)
            if cur == nil or prev == nil or prev == 0 then
                vals[i] = NA
            else
                vals[i] = (cur - prev) / prev
            end
        end
    end
    return Series.from_table(vals, "float64", self._name)
end

-- =====================================================================
-- F.2 — Pacote de predicados (Series)
-- between, isin, is_unique, is_monotonic_*, equals, compare,
-- idxmin/idxmax, first_valid_index/last_valid_index.
-- =====================================================================

-- between(lo, hi, [inclusive]): máscara booleana lo ≤ x ≤ hi.
-- inclusive ∈ {"both" (default), "left", "right", "neither"}.
-- Null propaga (resultado null naquela posição).
function methods.between(self, lo, hi, inclusive)
    if self._dtype ~= "float64" and self._dtype ~= "int64"
       and self._dtype ~= "datetime" and self._dtype ~= "string" then
        error("smaug: between() requer dtype ordenável (numérico, datetime ou string), não '"
              ..self._dtype.."'", 2)
    end
    inclusive = inclusive or "both"
    if inclusive ~= "both" and inclusive ~= "left"
       and inclusive ~= "right" and inclusive ~= "neither" then
        error("smaug: between() inclusive ∈ {both, left, right, neither}", 2)
    end
    local inc_lo = (inclusive == "both" or inclusive == "left")
    local inc_hi = (inclusive == "both" or inclusive == "right")
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    for i = 1, n do
        local v = self:get(i)
        if v == nil then
            vals[i] = NA
        else
            local ge_lo = inc_lo and (v >= lo) or (v > lo)
            local le_hi = inc_hi and (v <= hi) or (v < hi)
            vals[i] = (ge_lo and le_hi)
        end
    end
    return Series.from_table(vals, "bool", self._name)
end

-- isin(values): máscara booleana — true onde o valor está em `values`.
-- values: tabela Lua (lista). Null na série → resultado null.
-- Comparação por igualdade direta (tostring para uniformizar chaves).
function methods.isin(self, values)
    if type(values) ~= "table" then
        error("smaug: isin() espera uma tabela de valores", 2)
    end
    -- conjunto de busca (chaves por tostring para casar tipos numéricos/string)
    local set = {}
    for _, val in ipairs(values) do
        set[tostring(val)] = true
    end
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    for i = 1, n do
        local v = self:get(i)
        if v == nil then
            vals[i] = NA
        else
            vals[i] = set[tostring(v)] == true
        end
    end
    return Series.from_table(vals, "bool", self._name)
end

-- is_unique(): true se todos os valores não-nulos são distintos.
-- Nulos são ignorados na verificação.
function methods.is_unique(self)
    local seen = {}
    for i = 1, self:len() do
        local v = self:get(i)
        if v ~= nil then
            local k = tostring(v)
            if seen[k] then return false end
            seen[k] = true
        end
    end
    return true
end

-- Helper de monotonicidade. dir = "inc" ou "dec"; strict = true/false.
-- Nulos: a presença de qualquer null torna a série não-monotônica (sem ordem
-- definida com o vizinho). Série vazia ou de 1 elemento é monotônica (vacuamente).
local function is_monotonic(self, dir, strict)
    if self._dtype ~= "float64" and self._dtype ~= "int64"
       and self._dtype ~= "datetime" and self._dtype ~= "string" then
        error("smaug: is_monotonic requer dtype ordenável, não '"..self._dtype.."'", 3)
    end
    local n = self:len()
    local prev = nil
    for i = 1, n do
        local v = self:get(i)
        if v == nil then return false end   -- null quebra a ordem
        if prev ~= nil then
            if dir == "inc" then
                if strict then if not (v > prev) then return false end
                else if not (v >= prev) then return false end end
            else  -- dec
                if strict then if not (v < prev) then return false end
                else if not (v <= prev) then return false end end
            end
        end
        prev = v
    end
    return true
end

-- is_monotonic_increasing([strict]): não-decrescente (strict=false, default)
-- ou estritamente crescente (strict=true).
function methods.is_monotonic_increasing(self, strict)
    return is_monotonic(self, "inc", strict == true)
end

-- is_monotonic_decreasing([strict]): não-crescente ou estritamente decrescente.
function methods.is_monotonic_decreasing(self, strict)
    return is_monotonic(self, "dec", strict == true)
end

-- equals(other): igualdade estrutural — mesmo dtype, tamanho, valores e nulls.
-- NaN == NaN nesta comparação (igualdade estrutural, não IEEE 754).
function methods.equals(self, other)
    if getmetatable(other) ~= Series then return false end
    if self._dtype ~= other._dtype then return false end
    if self:len() ~= other:len() then return false end
    for i = 1, self:len() do
        local a, b = self:get(i), other:get(i)
        if (a == nil) ~= (b == nil) then return false end   -- null vs não-null
        if a ~= nil then
            -- NaN estrutural: dois NaN são "iguais" aqui
            if a ~= b and not (a ~= a and b ~= b) then return false end
        end
    end
    return true
end

-- compare(other): diferenças posicionais → DataSet {i, self, other}.
-- Só inclui as posições onde os valores diferem (semântica equals).
-- DataSet vazio se idênticas. Erro se dtype/tamanho incompatíveis.
function methods.compare(self, other)
    if getmetatable(other) ~= Series then
        error("smaug: compare() espera outra Series", 2)
    end
    if self._dtype ~= other._dtype then
        error("smaug: compare() — dtypes diferentes ('"..self._dtype.."' vs '"
              ..other._dtype.."')", 2)
    end
    if self:len() ~= other:len() then
        error("smaug: compare() — tamanhos diferentes ("..self:len().." vs "
              ..other:len()..")", 2)
    end
    local NA = Series.NA
    local idx, self_vals, other_vals = {}, {}, {}
    for i = 1, self:len() do
        local a, b = self:get(i), other:get(i)
        local differ
        if (a == nil) ~= (b == nil) then
            differ = true
        elseif a == nil then
            differ = false   -- ambos null
        else
            differ = (a ~= b) and not (a ~= a and b ~= b)  -- NaN estrutural igual
        end
        if differ then
            local m = #idx + 1
            idx[m]       = i
            self_vals[m] = (a == nil) and NA or a
            other_vals[m]= (b == nil) and NA or b
        end
    end
    local DataSet = require("smaug.core.dataset")
    return DataSet.from_columns({
        {"i",     idx,        "int64"},
        {"self",  self_vals,  self._dtype},
        {"other", other_vals, self._dtype},
    }, (self._name or "series") .. "_compare")
end

-- idxmin/idxmax: aliases de argmin/argmax (compatibilidade pandas).
function methods.idxmin(self) return self:argmin() end
function methods.idxmax(self) return self:argmax() end

-- first_valid_index(): índice 1-based do 1º valor não-nulo; nil se toda nula.
function methods.first_valid_index(self)
    for i = 1, self:len() do
        if self:get(i) ~= nil then return i end
    end
    return nil
end

-- last_valid_index(): índice 1-based do último valor não-nulo; nil se toda nula.
function methods.last_valid_index(self)
    for i = self:len(), 1, -1 do
        if self:get(i) ~= nil then return i end
    end
    return nil
end

-- =====================================================================
-- F.6 — Duplicatas e operações binárias (Series)
-- duplicated, drop_duplicates, combine_first, searchsorted, rep_each.
-- =====================================================================

-- Chave de igualdade consistente com unique/nunique. Null tem chave própria.
local function dup_key(v)
    if v == nil then return "\0NULL\0" end
    return type(v) .. ":" .. tostring(v)
end

-- duplicated([keep]): Series<bool> marcando posições duplicadas.
-- keep="first" (default): primeira ocorrência = false, demais = true.
-- keep="last": última ocorrência = false, demais = true.
-- keep="none": TODAS as ocorrências de um valor repetido = true.
-- Nulos contam como valor (dois nulos são duplicatas entre si — semântica pandas).
function methods.duplicated(self, keep)
    keep = keep or "first"
    if keep ~= "first" and keep ~= "last" and keep ~= "none" then
        error("smaug: duplicated() keep ∈ {first, last, none}", 2)
    end
    local n    = self:len()
    local vals = {}

    if keep == "first" then
        local seen = {}
        for i = 1, n do
            local k = dup_key(self:get(i))
            if seen[k] then vals[i] = true else seen[k] = true; vals[i] = false end
        end
    elseif keep == "last" then
        local seen = {}
        for i = n, 1, -1 do
            local k = dup_key(self:get(i))
            if seen[k] then vals[i] = true else seen[k] = true; vals[i] = false end
        end
    else  -- none: marca tudo que aparece mais de uma vez
        local count = {}
        for i = 1, n do
            local k = dup_key(self:get(i))
            count[k] = (count[k] or 0) + 1
        end
        for i = 1, n do
            vals[i] = count[dup_key(self:get(i))] > 1
        end
    end
    return Series.from_table(vals, "bool", self._name)
end

-- drop_duplicates([keep]): nova Series sem as posições marcadas por duplicated.
-- keep como em duplicated. Preserva a ordem original das mantidas.
function methods.drop_duplicates(self, keep)
    local mask = self:duplicated(keep)   -- valida keep
    local NA   = Series.NA
    local vals = {}
    for i = 1, self:len() do
        if mask:get(i) == false then
            local v = self:get(i)
            vals[#vals + 1] = (v == nil) and NA or v
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- combine_first(other): onde self é null, usa o valor de other na mesma posição.
-- Exige mesmo tamanho e dtype compatível. → nova Series do dtype de self.
function methods.combine_first(self, other)
    if getmetatable(other) ~= Series then
        error("smaug: combine_first() espera outra Series", 2)
    end
    if self._dtype ~= other._dtype then
        error("smaug: combine_first() — dtypes diferentes ('"..self._dtype
              .."' vs '"..other._dtype.."')", 2)
    end
    if self:len() ~= other:len() then
        error("smaug: combine_first() — tamanhos diferentes ("..self:len()
              .." vs "..other:len()..")", 2)
    end
    local NA   = Series.NA
    local vals = {}
    for i = 1, self:len() do
        local v = self:get(i)
        if v == nil then
            local o = other:get(i)
            vals[i] = (o == nil) and NA or o
        else
            vals[i] = v
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- searchsorted(value, [side]): posição de inserção (1-based) que mantém a ordem.
-- Exige série ordenada crescente (verifica via is_monotonic_increasing).
-- side="left" (default): primeira posição onde value caberia (antes dos iguais).
-- side="right": após os iguais. Nulos não são permitidos (série deve ser ordenável).
function methods.searchsorted(self, value, side)
    if self._dtype ~= "float64" and self._dtype ~= "int64"
       and self._dtype ~= "datetime" and self._dtype ~= "string" then
        error("smaug: searchsorted() requer dtype ordenável, não '"..self._dtype.."'", 2)
    end
    side = side or "left"
    if side ~= "left" and side ~= "right" then
        error("smaug: searchsorted() side ∈ {left, right}", 2)
    end
    if not self:is_monotonic_increasing() then
        error("smaug: searchsorted() requer série ordenada crescente (sem nulos)", 2)
    end
    local lo, hi = 1, self:len() + 1   -- busca em [lo, hi)
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        local v   = self:get(mid)
        local go_right
        if side == "left" then
            go_right = (v < value)
        else
            go_right = (v <= value)
        end
        if go_right then lo = mid + 1 else hi = mid end
    end
    return lo
end

-- rep_each(n): repete cada elemento `n` vezes, em ordem.
-- n: inteiro escalar >= 0, OU Series<int64> com contagem por elemento.
-- Nulos são repetidos como nulos. n=0 (escalar) → série vazia.
-- Nota: nome é rep_each (não "repeat") porque `repeat` é palavra reservada
-- em Lua e impediria a sintaxe de chamada s:repeat(...).
function methods.rep_each(self, n)
    local NA   = Series.NA
    local len  = self:len()
    local vals = {}
    local counts

    if type(n) == "number" then
        if n < 0 or n ~= math.floor(n) then
            error("smaug: rep_each(n) — n deve ser inteiro >= 0", 2)
        end
        counts = nil   -- escalar
    elseif getmetatable(n) == Series then
        if n._dtype ~= "int64" then
            error("smaug: rep_each(Series) requer Series<int64>", 2)
        end
        if n:len() ~= len then
            error("smaug: rep_each(Series) — tamanho diferente ("..n:len()
                  .." vs "..len..")", 2)
        end
        counts = n
    else
        error("smaug: rep_each(n) — n deve ser inteiro ou Series<int64>", 2)
    end

    for i = 1, len do
        local times
        if counts == nil then
            times = n
        else
            times = counts:get(i)
            if times == nil or times < 0 then
                error("smaug: rep_each — contagem inválida na posição "..i, 2)
            end
        end
        local v = self:get(i)
        for _ = 1, times do
            vals[#vals + 1] = (v == nil) and NA or v
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

-- rolling:std() / var(): desvio padrão / variância amostral (÷ n-1) da janela.
function SeriesRolling:std()
    return self:_agg(function(vs)
        local n = #vs
        if n < 2 then return nil end
        local mean = 0; for _, v in ipairs(vs) do mean = mean + v end; mean = mean / n
        local s = 0; for _, v in ipairs(vs) do local d = v - mean; s = s + d*d end
        return math.sqrt(s / (n - 1))
    end, "float64")
end

function SeriesRolling:var()
    return self:_agg(function(vs)
        local n = #vs
        if n < 2 then return nil end
        local mean = 0; for _, v in ipairs(vs) do mean = mean + v end; mean = mean / n
        local s = 0; for _, v in ipairs(vs) do local d = v - mean; s = s + d*d end
        return s / (n - 1)
    end, "float64")
end

-- rolling:count(): número de não-nulos na janela.
function SeriesRolling:count()
    local col, w, NA = self._s, self._window, Series.NA
    local n    = col:len()
    local vals = {}
    for i = 1, n do
        if i < w then vals[i] = NA
        else
            local cnt = 0
            for j = i - w + 1, i do
                if col:get(j) ~= nil then cnt = cnt + 1 end
            end
            vals[i] = cnt
        end
    end
    return Series.from_table(vals, "int64", col._name)
end

-- rolling:median(): mediana da janela.
function SeriesRolling:median()
    return self:_agg(function(vs)
        if #vs == 0 then return nil end
        local sv = {}; for _, v in ipairs(vs) do sv[#sv+1] = v end
        table.sort(sv)
        local n = #sv
        local m = math.floor(n / 2)
        return (n % 2 == 1) and sv[m+1] or (sv[m] + sv[m+1]) / 2
    end, "float64")
end

-- rolling:quantile(q): percentil da janela (interpolação linear).
function SeriesRolling:quantile(q)
    if type(q) ~= "number" or q < 0 or q > 1 then
        error("smaug: rolling:quantile() espera 0 ≤ q ≤ 1", 2)
    end
    return self:_agg(function(vs)
        local n = #vs
        if n == 0 then return nil end
        local sv = {}; for _, v in ipairs(vs) do sv[#sv+1] = v end
        table.sort(sv)
        if n == 1 then return sv[1] end
        local pos  = q * (n - 1)
        local lo   = math.floor(pos)
        local frac = pos - lo
        local hi   = lo + 1
        if hi >= n then return sv[n] end
        return sv[lo+1] + frac * (sv[hi+1] - sv[lo+1])
    end)
end

-- rolling:min_periods(p): define mínimo de não-nulos para produzir resultado.
-- Retorna novo objeto rolling com min_periods configurado.
function SeriesRolling:min_periods(p)
    if type(p) ~= "number" or p < 1 then
        error("smaug: rolling:min_periods() espera p >= 1", 2)
    end
    return setmetatable({ _s=self._s, _window=self._window, _min_periods=p }, SeriesRolling)
end

-- Aplica min_periods na _agg base também
-- min_periods: mínimo de não-nulos necessários dentro da janela para produzir
-- resultado. A janela sempre tem tamanho `w`; posições anteriores a `w` são NA
-- a menos que min_periods < w (nesse caso janelas parciais são permitidas).
function SeriesRolling:_agg(fn, out_dtype)
    local col  = self._s
    local n    = col:len()
    local w    = self._window
    local min_p = self._min_periods or 1   -- default: 1 não-nulo na janela
    local NA   = Series.NA
    local vals = {}
    for i = 1, n do
        -- janela efetiva: sem min_periods, começa em i-w+1; com min_periods < w,
        -- pode começar em i-w+1 mesmo se i < w, desde que haja dados suficientes.
        local wstart = math.max(1, i - w + 1)
        -- se i < w e não há min_periods customizado: janela incompleta → NA
        if i < w and not self._min_periods then
            vals[i] = NA
        else
            local wv = {}
            for j = wstart, i do
                local v = col:get(j)
                if v ~= nil then wv[#wv+1] = v end
            end
            local res = (#wv >= min_p) and fn(wv) or nil
            vals[i] = (res ~= nil) and res or NA
        end
    end
    return Series.from_table(vals, out_dtype or col._dtype, col._name)
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
    -- categorical é Lua puro — não está em DTYPES, mas é suportado
    if dtype == "categorical" then
        local Cat = Series.Categorical   -- lazy: definido após esta função
        if not Cat then
            error("smaug: astype 'categorical' — CategoricalSeries não disponível", 2)
        end
        local vals = {}
        local n = self:len()
        for i = 1, n do
            local v = self:get(i)
            vals[i] = v ~= nil and tostring(v) or NA
        end
        return Cat.from_table(vals, name or self._name)
    end
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
        elseif src == "datetime" and dtype ~= "datetime" then
            -- datetime → string: ISO 8601 via smaug_dt_format
            -- datetime → int64:  epoch_ms direto (inteiro)
            -- datetime → float64: epoch_ms como double
            if dtype == "string" then
                local buf = ffi.new("char[26]")
                C.smaug_dt_format(v, buf, 26)
                out:set(i, ffi.string(buf))
            elseif dtype == "int64" then
                out:set(i, trunc_to_int(v))
            else -- float64
                out:set(i, tonumber(v))
            end
        elseif dtype == "datetime" and src ~= "datetime" then
            -- string → datetime: parse ISO 8601 tolerante (falha → null)
            -- int64/float64 → datetime: epoch_ms direto
            if src == "string" then
                local ep = ffi.new("int64_t[1]")
                if C.smaug_dt_parse(v, #v, ep) == 0 then
                    out:set(i, tonumber(ep[0]))
                else
                    out:set_null(i)   -- parse falhou → null (contrato tolerante)
                end
            else -- numérico → epoch_ms
                if v ~= v or v == math.huge or v == -math.huge then
                    out:set_null(i)
                else
                    out:set(i, trunc_to_int(v))
                end
            end
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
    -- datetime: estatísticas temporais (min, max, count, nulls)
    if self._dtype == "datetime" then
        local min_ep, max_ep = nil, nil
        for i = 1, n do
            local v = self:get(i)
            if v ~= nil then
                if min_ep == nil or v < min_ep then min_ep = v end
                if max_ep == nil or v > max_ep then max_ep = v end
            end
        end
        local buf = ffi.new("char[26]")
        local function fmt(ep)
            if ep == nil then return nil end
            C.smaug_dt_format(ep, buf, 26)
            return ffi.string(buf)
        end
        return {
            dtype = "datetime",
            count = n - nulls,
            nulls = nulls,
            min   = fmt(min_ep),
            max   = fmt(max_ep),
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

-- =====================================================================
-- .str Tier C — contagem, predicados ASCII, remoção de afixos, caixas.
-- Tudo semântica de bytes/ASCII (sem regex, sem Unicode), consistente
-- com o restante do accessor .str.
-- =====================================================================

-- count(sub): nº de ocorrências literais NÃO-sobrepostas de `sub` por string.
-- Null -> null. sub vazio -> erro (contagem indefinida / loop). → Series<int64>
function StrProxy:count(sub)
    if type(sub) ~= "string" then
        error("smaug: str:count espera uma string; recebido " .. type(sub), 2)
    end
    if #sub == 0 then
        error("smaug: str:count espera substring não-vazia", 2)
    end
    local sub_len = #sub
    local n   = self._s:len()
    local out = Series.new("int64", n, self._s._name)
    for i = 1, n do
        local v = self._s:get(i)
        if v == nil then
            out:set_null(i)
        else
            local c, start = 0, 1
            while true do
                local found = v:find(sub, start, true)
                if not found then break end
                c = c + 1
                start = found + sub_len   -- não-sobreposto
            end
            out:set(i, c)
        end
    end
    return out
end

-- ---- Predicados ASCII → Series<bool>. String vazia → false (semântica Python).
-- Null → NA. Todos operam byte a byte sobre o intervalo ASCII.

-- Helper: true se todos os bytes satisfazem `pred` E a string é não-vazia.
local function all_bytes(v, pred)
    if #v == 0 then return false end
    for k = 1, #v do
        if not pred(v:byte(k)) then return false end
    end
    return true
end

local function b_is_digit(b) return b >= 48 and b <= 57 end
local function b_is_lower(b) return b >= 97 and b <= 122 end
local function b_is_upper(b) return b >= 65 and b <= 90 end
local function b_is_alpha(b) return b_is_lower(b) or b_is_upper(b) end
local function b_is_alnum(b) return b_is_alpha(b) or b_is_digit(b) end
local function b_is_space(b)
    -- ASCII whitespace: espaço(32) \t(9) \n(10) \v(11) \f(12) \r(13)
    return b == 32 or (b >= 9 and b <= 13)
end

function StrProxy:isdigit()
    return bool_map(self._s, function(v) return all_bytes(v, b_is_digit) end)
end
function StrProxy:isalpha()
    return bool_map(self._s, function(v) return all_bytes(v, b_is_alpha) end)
end
function StrProxy:isalnum()
    return bool_map(self._s, function(v) return all_bytes(v, b_is_alnum) end)
end
function StrProxy:isspace()
    return bool_map(self._s, function(v) return all_bytes(v, b_is_space) end)
end

-- islower(): há ao menos uma letra ASCII e nenhuma maiúscula (semântica Python).
function StrProxy:islower()
    return bool_map(self._s, function(v)
        local has_alpha = false
        for k = 1, #v do
            local b = v:byte(k)
            if b_is_upper(b) then return false end
            if b_is_lower(b) then has_alpha = true end
        end
        return has_alpha
    end)
end

-- isupper(): há ao menos uma letra ASCII e nenhuma minúscula.
function StrProxy:isupper()
    return bool_map(self._s, function(v)
        local has_alpha = false
        for k = 1, #v do
            local b = v:byte(k)
            if b_is_lower(b) then return false end
            if b_is_upper(b) then has_alpha = true end
        end
        return has_alpha
    end)
end

-- ---- Remoção de afixos (literal, no máximo uma vez, idempotente) ----

-- removeprefix(p): remove `p` do início, se presente. → Series<string>
function StrProxy:removeprefix(p)
    if type(p) ~= "string" then
        error("smaug: str:removeprefix espera uma string; recebido " .. type(p), 2)
    end
    local np = #p
    if np == 0 then return str_map(self._s, function(v) return v end) end
    return str_map(self._s, function(v)
        if v:sub(1, np) == p then return v:sub(np + 1) end
        return v
    end)
end

-- removesuffix(s): remove `s` do fim, se presente. → Series<string>
function StrProxy:removesuffix(suf)
    if type(suf) ~= "string" then
        error("smaug: str:removesuffix espera uma string; recebido " .. type(suf), 2)
    end
    local ns = #suf
    if ns == 0 then return str_map(self._s, function(v) return v end) end
    return str_map(self._s, function(v)
        if v:sub(-ns) == suf then return v:sub(1, #v - ns) end
        return v
    end)
end

-- ---- Caixas adicionais (ASCII) ----

-- capitalize(): primeira letra maiúscula, restante minúsculo. → Series<string>
function StrProxy:capitalize()
    return str_map(self._s, function(v)
        if #v == 0 then return v end
        return v:sub(1, 1):upper() .. v:sub(2):lower()
    end)
end

-- title(): primeira letra de cada palavra maiúscula, resto minúsculo.
-- Palavra = sequência de letras ASCII; qualquer não-letra é separador.
function StrProxy:title()
    return str_map(self._s, function(v)
        local out = {}
        local prev_alpha = false
        for k = 1, #v do
            local b = v:byte(k)
            local is_alpha = b_is_alpha(b)
            if is_alpha then
                if prev_alpha then
                    out[k] = string.char(b_is_upper(b) and b + 32 or b)  -- minúscula
                else
                    out[k] = string.char(b_is_lower(b) and b - 32 or b)  -- maiúscula
                end
            else
                out[k] = string.char(b)
            end
            prev_alpha = is_alpha
        end
        return table.concat(out)
    end)
end

-- swapcase(): inverte a caixa de cada letra ASCII. → Series<string>
function StrProxy:swapcase()
    return str_map(self._s, function(v)
        local out = {}
        for k = 1, #v do
            local b = v:byte(k)
            if b_is_lower(b)     then out[k] = string.char(b - 32)
            elseif b_is_upper(b) then out[k] = string.char(b + 32)
            else                      out[k] = string.char(b) end
        end
        return table.concat(out)
    end)
end

-- join(sep): atalho de :cat — concatena os não-nulos numa string Lua única.
-- Mantido por compatibilidade de nome (pandas/Python); idêntico a :cat(sep).
function StrProxy:join(sep)
    return self:cat(sep)
end

-- __index: unificado abaixo (junto com .dt)
-- =====================================================================
-- Enriquecimento: reduções, transformações e conveniência
-- =====================================================================

-- =====================================================================
-- Grupo B — sorted_nonnull e rank migrados para C (Fase 3 Ring 0)
-- Helpers Lua para operar sobre o double* ordenado devolvido pelo C.
-- =====================================================================

-- Chama sorted_nonnull C conforme o dtype. Devolve (double_array, n) onde
-- double_array é um ffi double[] gerenciado pelo GC (ffi.new) para ambos os
-- tipos — uniforme para os helpers de mediana/quantil abaixo.
-- Para f64: os dados vêm direto do C (malloc); libera com smaug_free.
-- Para i64: aloca ffi.new double[] e copia convertendo.
local function c_sorted_nonnull(self)
    local out_n = ffi.new("size_t[1]")
    if self._dtype == "float64" then
        local ptr = C.smaug_f64_sorted_nonnull(self._c, out_n)
        local n = tonumber(out_n[0])
        if ptr == nil or n == 0 then return nil, 0 end
        -- copiar para ffi.new para uniformizar lifecycle (GC vs smaug_free)
        local arr = ffi.new("double[?]", n)
        ffi.copy(arr, ptr, n * ffi.sizeof("double"))
        C.smaug_free(ptr)
        return arr, n
    else  -- int64
        local iptr = C.smaug_i64_sorted_nonnull(self._c, out_n)
        local n = tonumber(out_n[0])
        if iptr == nil or n == 0 then
            if iptr ~= nil then C.smaug_free(iptr) end
            return nil, 0
        end
        local arr = ffi.new("double[?]", n)
        for i = 0, n - 1 do arr[i] = tonumber(iptr[i]) end
        C.smaug_free(iptr)
        return arr, n
    end
end

-- Mediana de double* ordenado com n elementos (interpolação linear).
local function median_of_sorted(ptr, n)
    if n == 0 then return nil end
    local m = math.floor(n / 2)
    if n % 2 == 1 then return tonumber(ptr[m]) end
    return (tonumber(ptr[m - 1]) + tonumber(ptr[m])) / 2
end

-- Quantil de double* ordenado (0 ≤ q ≤ 1, interpolação linear).
local function quantile_of_sorted(ptr, n, q)
    if n == 0 then return nil end
    if n == 1 then return tonumber(ptr[0]) end
    local pos  = q * (n - 1)
    local lo   = math.floor(pos)
    local frac = pos - lo
    local hi   = lo + 1
    if hi >= n then return tonumber(ptr[n - 1]) end
    return tonumber(ptr[lo]) + frac * (tonumber(ptr[hi]) - tonumber(ptr[lo]))
end

-- collect_sorted: mantido como fallback Lua para dtypes sem C (datetime, string).
local function collect_sorted(self)
    local n, vals = self:len(), {}
    for i = 1, n do
        local v = self:get(i)
        if v ~= nil then vals[#vals+1] = v end
    end
    table.sort(vals)
    return vals
end

-- median_sorted: mantido para uso em mad() que opera sobre tabela Lua.
local function median_sorted(vals)
    local n = #vals
    if n == 0 then return nil end
    local m = math.floor(n / 2)
    return (n % 2 == 1) and vals[m+1] or (vals[m] + vals[m+1]) / 2
end

-- quantile_sorted: mantido para compatibilidade interna.
local function quantile_sorted(vals, q)
    local n = #vals
    if n == 0 then return nil end
    if n == 1 then return vals[1] end
    local pos  = q * (n - 1)
    local lo   = math.floor(pos)
    local frac = pos - lo
    local hi   = lo + 1
    if hi >= n then return vals[n] end
    return vals[lo+1] + frac * (vals[hi+1] - vals[lo+1])
end

-- prod([ignore_na]): produto de todos os valores.
function methods.prod(self, ignore_na)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: prod() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    ignore_na = (ignore_na == nil) and true or ignore_na
    local p, n = 1, 0
    for i = 1, self:len() do
        local v = self:get(i)
        if v == nil then
            if not ignore_na then return nil end
        else
            p = p * v; n = n + 1
        end
    end
    return n > 0 and p or nil
end

-- median([ignore_na]): mediana (ignora nulos por padrão). float64.
function methods.median(self, ignore_na)
    if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
        error("smaug: median() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
    end
    ignore_na = (ignore_na == nil) and true or ignore_na
    if not ignore_na then
        for i = 1, self:len() do
            if self:get(i) == nil then return nil end
        end
    end
    -- datetime: usa tabela Lua (sem primitiva C sorted_nonnull para datetime)
    if self._dtype == "datetime" then
        return median_sorted(collect_sorted(self))
    end
    local arr, n = c_sorted_nonnull(self)
    return median_of_sorted(arr, n)
end

-- quantile(q, [ignore_na]): percentil 0 ≤ q ≤ 1. Interpolação linear. float64.
function methods.quantile(self, q, ignore_na)
    if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
        error("smaug: quantile() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
    end
    if type(q) ~= "number" or q < 0 or q > 1 then
        error("smaug: quantile() espera 0 ≤ q ≤ 1", 2)
    end
    ignore_na = (ignore_na == nil) and true or ignore_na
    if not ignore_na then
        for i = 1, self:len() do
            if self:get(i) == nil then return nil end
        end
    end
    if self._dtype == "datetime" then
        return quantile_sorted(collect_sorted(self), q)
    end
    local arr, n = c_sorted_nonnull(self)
    return quantile_of_sorted(arr, n, q)
end

-- mode(): valor mais frequente (ignora nulos). Empate: primeiro em ordem de valor.
function methods.mode(self)
    if self._dtype == "bool" then
        error("smaug: mode() não suportado para bool", 2)
    end
    local freq = {}
    local order = {}
    for i = 1, self:len() do
        local v = self:get(i)
        if v ~= nil then
            local k = tostring(v)
            if not freq[k] then freq[k] = 0; order[#order+1] = v end
            freq[k] = freq[k] + 1
        end
    end
    if #order == 0 then return nil end
    local best, best_f = order[1], 0
    for _, v in ipairs(order) do
        local f = freq[tostring(v)]
        if f > best_f then best = v; best_f = f end
    end
    return best
end

-- ffill(): preenche nulos com o último valor válido anterior.
function methods.ffill(self)
    if self._d.ffill then
        local r = self._d.ffill(self._c)
        if r == nil then error("smaug: ffill falhou (OOM)", 2) end
        return wrap(r, self._dtype, self._name)
    end
    -- fallback Lua para dtypes sem C (datetime, string, bool, categorical)
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    local last = NA
    for i = 1, n do
        local v = self:get(i)
        if v ~= nil then last = v end
        vals[i] = last
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- bfill(): preenche nulos com o próximo valor válido seguinte.
function methods.bfill(self)
    if self._d.bfill then
        local r = self._d.bfill(self._c)
        if r == nil then error("smaug: bfill falhou (OOM)", 2) end
        return wrap(r, self._dtype, self._name)
    end
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    local next_val = NA
    for i = n, 1, -1 do
        local v = self:get(i)
        if v ~= nil then next_val = v end
        vals[i] = next_val
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- cummin(): mínimo cumulativo. Nulos na posição i ficam nulos mas não propagam.
-- Numérico → C. Datetime → Lua (sem primitiva C para datetime cummin).
function methods.cummin(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
        error("smaug: cummin() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
    end
    if self._d.cummin then
        local r = self._d.cummin(self._c)
        if r == nil then error("smaug: cummin falhou (OOM)", 2) end
        return wrap(r, self._dtype, self._name)
    end
    -- Lua: datetime (e qualquer dtype sem C)
    local NA, n, vals = Series.NA, self:len(), {}
    local cur = nil
    for i = 1, n do
        local v = self:get(i)
        if v == nil then
            vals[i] = NA
        else
            cur = (cur == nil or v < cur) and v or cur
            vals[i] = cur
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- cummax(): máximo cumulativo. Mesmo contrato de cummin.
function methods.cummax(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
        error("smaug: cummax() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
    end
    if self._d.cummax then
        local r = self._d.cummax(self._c)
        if r == nil then error("smaug: cummax falhou (OOM)", 2) end
        return wrap(r, self._dtype, self._name)
    end
    local NA, n, vals = Series.NA, self:len(), {}
    local cur = nil
    for i = 1, n do
        local v = self:get(i)
        if v == nil then
            vals[i] = NA
        else
            cur = (cur == nil or v > cur) and v or cur
            vals[i] = cur
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- argmin(): índice 1-based do mínimo (ignora nulos). nil se vazia ou toda nula.
-- f64/i64: C (SIZE_MAX → nil, 0-based → 1-based). datetime: Lua.
function methods.argmin(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
        error("smaug: argmin() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
    end
    if self._d.argmin then
        local idx = self._d.argmin(self._c)
        -- SIZE_MAX em C = valor máximo de size_t; em LuaJIT é número grande
        local n = tonumber(idx)
        if n == nil or n >= tonumber(self._c.size) then return nil end
        return n + 1   -- 0-based → 1-based
    end
    -- Lua: datetime
    local best_v, best_i = nil, nil
    for i = 1, self:len() do
        local v = self:get(i)
        if v ~= nil and (best_v == nil or v < best_v) then
            best_v, best_i = v, i
        end
    end
    return best_i
end

-- argmax(): índice 1-based do máximo (ignora nulos).
function methods.argmax(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" and self._dtype ~= "datetime" then
        error("smaug: argmax() requer dtype numérico ou datetime, não '"..self._dtype.."'", 2)
    end
    if self._d.argmax then
        local idx = self._d.argmax(self._c)
        local n = tonumber(idx)
        if n == nil or n >= tonumber(self._c.size) then return nil end
        return n + 1
    end
    local best_v, best_i = nil, nil
    for i = 1, self:len() do
        local v = self:get(i)
        if v ~= nil and (best_v == nil or v > best_v) then
            best_v, best_i = v, i
        end
    end
    return best_i
end

-- rank([method]): posição de cada valor no ranking (1-based, ignora nulos → NA).
-- method: "average" (default), "min", "max", "first".
-- Delega para C (smaug_f64_rank / smaug_i64_rank). Retorna float64.
function methods.rank(self, method)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: rank() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    method = method or "average"
    local method_int
    if     method == "average" then method_int = 0
    elseif method == "min"     then method_int = 1
    elseif method == "max"     then method_int = 2
    elseif method == "first"   then method_int = 3
    else error("smaug: rank() method ∈ {average, min, max, first}", 2) end

    local raw
    if self._dtype == "float64" then
        raw = C.smaug_f64_rank(self._c, method_int)
    else
        raw = C.smaug_i64_rank(self._c, method_int)
    end
    if raw == nil then error("smaug: rank falhou (OOM)", 2) end

    -- Converter double* → Series<float64>: NAN → NA
    local NA  = Series.NA
    local n   = self:len()
    local out = Series.new("float64", n, self._name)
    for i = 0, n - 1 do
        local v = tonumber(raw[i])
        if v ~= v then  -- NAN → null
            out:set_null(i + 1)
        else
            out:set(i + 1, v)
        end
    end
    C.smaug_free(raw)
    return out
end

-- pct_rank(): rank normalizado para [0, 1]. Atalho sobre rank("average") / n.
function methods.pct_rank(self)
    local r = self:rank("average")
    local n = tonumber(self._d.count_nonnull and self._d.count_nonnull(self._c) or self:count_nonnull())
    if n == 0 then return r end
    return r:map(function(v) return v ~= nil and (v / n) or nil end, "float64", self._name)
end

-- skew(): assimetria amostral (denominador n-1). nil se < 3 valores.
function methods.skew(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: skew() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    local arr, n = c_sorted_nonnull(self)  -- sorted não importa; só precisamos dos valores
    if n < 3 then return nil end
    local mean = 0
    for i = 0, n - 1 do mean = mean + tonumber(arr[i]) end
    mean = mean / n
    local m2, m3 = 0, 0
    for i = 0, n - 1 do
        local d = tonumber(arr[i]) - mean
        m2 = m2 + d*d
        m3 = m3 + d*d*d
    end
    m2 = m2 / n; m3 = m3 / n
    if m2 == 0 then return 0 end
    local g1 = (m3 / (m2 ^ 1.5)) * (math.sqrt(n*(n-1)) / (n-2))
    return g1
end

-- kurtosis(): curtose amostral (excess kurtosis, base normal = 0).
function methods.kurtosis(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: kurtosis() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    local arr, n = c_sorted_nonnull(self)
    if n < 4 then return nil end
    local mean = 0
    for i = 0, n - 1 do mean = mean + tonumber(arr[i]) end
    mean = mean / n
    local m2, m4 = 0, 0
    for i = 0, n - 1 do
        local d = tonumber(arr[i]) - mean
        local d2 = d * d
        m2 = m2 + d2
        m4 = m4 + d2 * d2
    end
    m2 = m2 / n; m4 = m4 / n
    if m2 == 0 then return 0 end
    local kurt = (n*(n+1) / ((n-1)*(n-2)*(n-3))) * (m4/(m2*m2)) - 3*(n-1)^2/((n-2)*(n-3))
    return kurt
end

-- mad(): desvio absoluto mediano (robusto a outliers).
function methods.mad(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: mad() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    local arr, n = c_sorted_nonnull(self)
    if n == 0 then return nil end
    local med = median_of_sorted(arr, n)
    -- desvios absolutos em tabela Lua (depois mediana deles)
    local devs = {}
    for i = 0, n - 1 do devs[i + 1] = math.abs(tonumber(arr[i]) - med) end
    table.sort(devs)
    return median_sorted(devs)
end

-- sem(): erro padrão da média = std / sqrt(n).
function methods.sem(self)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: sem() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    local arr, n = c_sorted_nonnull(self)
    if n < 2 then return nil end
    local mean = 0
    for i = 0, n - 1 do mean = mean + tonumber(arr[i]) end
    mean = mean / n
    local s2 = 0
    for i = 0, n - 1 do local d = tonumber(arr[i]) - mean; s2 = s2 + d*d end
    local std = math.sqrt(s2 / (n - 1))
    return std / math.sqrt(n)
end

-- where(cond, other): mantém valor onde cond é true, substitui por `other` onde false/NA.
-- cond: Series<bool> do mesmo tamanho. other: escalar ou Series.
function methods.where(self, cond, other)
    if type(cond) ~= "table" or cond._dtype ~= "bool" then
        error("smaug: where() espera Series<bool> como primeiro argumento", 2)
    end
    if cond:len() ~= self:len() then
        error("smaug: where() — tamanhos diferentes ("..cond:len().." vs "..self:len()..")", 2)
    end
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    local is_series_other = type(other) == "table" and other._dtype ~= nil
    for i = 1, n do
        local c = cond:get(i)
        if c == true then
            vals[i] = self:get(i)
        else
            vals[i] = is_series_other and other:get(i) or (other == nil and NA or other)
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- mask(cond, other): inverso de where — substitui onde cond é true.
function methods.mask(self, cond, other)
    if type(cond) ~= "table" or cond._dtype ~= "bool" then
        error("smaug: mask() espera Series<bool> como primeiro argumento", 2)
    end
    if cond:len() ~= self:len() then
        error("smaug: mask() — tamanhos diferentes ("..cond:len().." vs "..self:len()..")", 2)
    end
    local NA   = Series.NA
    local n    = self:len()
    local vals = {}
    local is_series_other = type(other) == "table" and other._dtype ~= nil
    for i = 1, n do
        local c = cond:get(i)
        if c == true then
            vals[i] = is_series_other and other:get(i) or (other == nil and NA or other)
        else
            vals[i] = self:get(i)
        end
    end
    return Series.from_table(vals, self._dtype, self._name)
end

-- ifelse(cond, a, b): vetorizado — a onde cond=true, b onde cond=false/NA.
-- cond: Series<bool>. a, b: escalar ou Series.
function Series.ifelse(cond, a, b)
    if type(cond) ~= "table" or cond._dtype ~= "bool" then
        error("smaug: ifelse() espera Series<bool> como primeiro argumento", 2)
    end
    local n    = cond:len()
    local NA   = Series.NA
    local is_a = type(a) == "table" and a._dtype ~= nil
    local is_b = type(b) == "table" and b._dtype ~= nil
    -- inferir dtype do resultado
    local dtype = "float64"
    if is_a     then dtype = a._dtype
    elseif is_b then dtype = b._dtype
    elseif type(a) == "string" or type(b) == "string" then dtype = "string"
    elseif type(a) == "boolean" or type(b) == "boolean" then dtype = "bool"
    elseif type(a) == "number" and a % 1 == 0 and
           (b == nil or (type(b) == "number" and b % 1 == 0)) then dtype = "int64"
    end
    local vals = {}
    for i = 1, n do
        local c = cond:get(i)
        if c == true then
            vals[i] = is_a and a:get(i) or (a == nil and NA or a)
        else
            vals[i] = is_b and b:get(i) or (b == nil and NA or b)
        end
    end
    return Series.from_table(vals, dtype)
end

-- isna(i) / notna(i): alias de is_null / not is_null.
function methods.isna(self, i)  return self:is_null(i) end
function methods.notna(self, i) return not self:is_null(i) end

-- nlargest(n): os n maiores valores → nova Series ordenada desc.
function methods.nlargest(self, n)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: nlargest() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    if type(n) ~= "number" or n < 1 then
        error("smaug: nlargest() espera n >= 1", 2)
    end
    local arr, m = c_sorted_nonnull(self)
    local result = {}
    local take = math.min(n, m)
    for i = 0, take - 1 do
        -- arr está ordenado asc; os n maiores estão no fim
        local v = tonumber(arr[m - 1 - i])
        result[i + 1] = (self._dtype == "int64") and math.floor(v) or v
    end
    return Series.from_table(result, self._dtype, self._name)
end

-- nsmallest(n): os n menores valores → nova Series ordenada asc.
function methods.nsmallest(self, n)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: nsmallest() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    if type(n) ~= "number" or n < 1 then
        error("smaug: nsmallest() espera n >= 1", 2)
    end
    local arr, m = c_sorted_nonnull(self)
    local result = {}
    local take = math.min(n, m)
    for i = 0, take - 1 do
        local v = tonumber(arr[i])
        result[i + 1] = (self._dtype == "int64") and math.floor(v) or v
    end
    return Series.from_table(result, self._dtype, self._name)
end

-- Funções matemáticas vetorizadas: sin, cos, tan, exp, log, sqrt.
-- Nulos propagam. Resultado sempre float64.
local _math_fns = {
    sin  = math.sin,  cos = math.cos, tan = math.tan,
    exp  = math.exp,  log = math.log, sqrt = math.sqrt,
}
for fname, fn in pairs(_math_fns) do
    methods[fname] = function(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: "..fname.."() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        return self:map(function(v) return v ~= nil and fn(v) or nil end, "float64", self._name)
    end
end

-- expanding(): janela crescente — equivale a rolling(i) para cada posição i.
-- Retorna objeto com os mesmos métodos do rolling.
local SeriesExpanding = {}
SeriesExpanding.__index = SeriesExpanding

function SeriesExpanding:_agg(fn)
    local col  = self._s
    local n    = col:len()
    local NA   = Series.NA
    local min_p = self._min_periods or 1
    local vals = {}
    for i = 1, n do
        local wv = {}
        for j = 1, i do
            local v = col:get(j)
            if v ~= nil then wv[#wv+1] = v end
        end
        vals[i] = (#wv >= min_p) and fn(wv) or NA
    end
    return Series.from_table(vals, col._dtype, col._name)
end

function SeriesExpanding:sum()
    return self:_agg(function(vs) local s=0; for _,v in ipairs(vs) do s=s+v end; return s end)
end
function SeriesExpanding:mean()
    return self:_agg(function(vs)
        if #vs == 0 then return nil end
        local s=0; for _,v in ipairs(vs) do s=s+v end; return s/#vs
    end)
end
function SeriesExpanding:min()
    return self:_agg(function(vs)
        if #vs == 0 then return nil end
        local m=vs[1]; for _,v in ipairs(vs) do if v<m then m=v end end; return m
    end)
end
function SeriesExpanding:max()
    return self:_agg(function(vs)
        if #vs == 0 then return nil end
        local m=vs[1]; for _,v in ipairs(vs) do if v>m then m=v end end; return m
    end)
end
function SeriesExpanding:std()
    return self:_agg(function(vs)
        local n = #vs
        if n < 2 then return nil end
        local mean = 0; for _,v in ipairs(vs) do mean=mean+v end; mean=mean/n
        local s = 0; for _,v in ipairs(vs) do local d=v-mean; s=s+d*d end
        return math.sqrt(s / (n-1))
    end)
end
function SeriesExpanding:var()
    return self:_agg(function(vs)
        local n = #vs
        if n < 2 then return nil end
        local mean = 0; for _,v in ipairs(vs) do mean=mean+v end; mean=mean/n
        local s = 0; for _,v in ipairs(vs) do local d=v-mean; s=s+d*d end
        return s / (n-1)
    end)
end
function SeriesExpanding:count()
    return self:_agg(function(vs) return #vs end)
end
function SeriesExpanding:median()
    return self:_agg(function(vs)
        local sv = {}; for _,v in ipairs(vs) do sv[#sv+1]=v end
        table.sort(sv)
        return median_sorted(sv)
    end)
end

function methods.expanding(self, min_periods)
    if self._dtype ~= "float64" and self._dtype ~= "int64" then
        error("smaug: expanding() requer dtype numérico, não '"..self._dtype.."'", 2)
    end
    return setmetatable({ _s=self, _min_periods=min_periods or 1 }, SeriesExpanding)
end

-- __newindex: série[i] = v -> set(); outras chaves gravam no objeto.
Series.__newindex = function(self, k, v)
    if type(k) == "number" then methods.set(self, k, v)
    else rawset(self, k, v) end
end

-- =====================================================================
-- .dt — proxy para operações de calendário em Series<datetime>
-- Uso: s.dt:year(), s.dt:month(), s.dt:format(), s.dt:truncate("M")
-- =====================================================================

local SeriesDT = {}
SeriesDT.__index = SeriesDT

-- Aplica uma função C de componente (int64_t → int) em cada elemento.
-- Retorna Series<int64>.
local function dt_component(s, fn)
    local n    = s:len()
    local NA   = Series.NA
    local vals = {}
    for i = 1, n do
        local v = s:get(i)
        if v == nil then
            vals[i] = NA
        else
            local r = fn(v)
            vals[i] = r >= 0 and r or NA
        end
    end
    return Series.from_table(vals, "int64", s._name)
end

function SeriesDT:year()    return dt_component(self._s, C.smaug_dt_year)    end
function SeriesDT:month()   return dt_component(self._s, C.smaug_dt_month)   end
function SeriesDT:day()     return dt_component(self._s, C.smaug_dt_day)     end
function SeriesDT:hour()    return dt_component(self._s, C.smaug_dt_hour)    end
function SeriesDT:minute()  return dt_component(self._s, C.smaug_dt_minute)  end
function SeriesDT:second()  return dt_component(self._s, C.smaug_dt_second)  end
function SeriesDT:ms()      return dt_component(self._s, C.smaug_dt_ms)      end
function SeriesDT:weekday() return dt_component(self._s, C.smaug_dt_weekday) end
function SeriesDT:yearday() return dt_component(self._s, C.smaug_dt_yearday) end
function SeriesDT:quarter() return dt_component(self._s, C.smaug_dt_quarter) end
function SeriesDT:week()    return dt_component(self._s, C.smaug_dt_week)    end

-- format(): formata cada epoch_ms como string ISO 8601 → Series<string>
function SeriesDT:format()
    local s    = self._s
    local n    = s:len()
    local NA   = Series.NA
    local vals = {}
    local buf  = ffi.new("char[26]")
    for i = 1, n do
        local v = s:get(i)
        if v == nil then
            vals[i] = NA
        else
            C.smaug_dt_format(v, buf, 26)
            vals[i] = ffi.string(buf)
        end
    end
    return Series.from_table(vals, "string", s._name)
end

-- truncate(unit): trunca cada elemento para o início do período.
-- unit: 's' 'm' 'h' 'D' 'W' 'M' 'Q' 'Y'
function SeriesDT:truncate(unit)
    if type(unit) ~= "string" or #unit ~= 1 then
        error("smaug: dt:truncate() espera uma letra de unidade ('D','M','Y',...)", 2)
    end
    local s    = self._s
    local n    = s:len()
    local NA   = Series.NA
    local vals = {}
    local u    = string.byte(unit)
    for i = 1, n do
        local v = s:get(i)
        if v == nil then
            vals[i] = NA
        else
            local r = C.smaug_dt_truncate(v, u)
            -- DT_SENTINEL = INT64_MIN
            vals[i] = (r == -9223372036854775808) and NA or tonumber(r)
        end
    end
    return Series.from_table(vals, "datetime", s._name)
end

-- diff(): diferença em ms entre elemento i e i-1. → Series<int64>
function SeriesDT:diff(periods)
    periods = periods or 1
    local s    = self._s
    local n    = s:len()
    local NA   = Series.NA
    local vals = {}
    for i = 1, n do
        if i <= periods then
            vals[i] = NA
        else
            local a = s:get(i)
            local b = s:get(i - periods)
            vals[i] = (a ~= nil and b ~= nil) and tonumber(C.smaug_dt_diff_ms(a, b)) or NA
        end
    end
    return Series.from_table(vals, "int64", s._name)
end

-- add_ms(delta_ms): adiciona delta em ms a cada elemento → Series<datetime>
function SeriesDT:add_ms(delta_ms)
    if type(delta_ms) ~= "number" then
        error("smaug: dt:add_ms() espera número", 2)
    end
    local s    = self._s
    local n    = s:len()
    local NA   = Series.NA
    local vals = {}
    for i = 1, n do
        local v = s:get(i)
        if v == nil then
            vals[i] = NA
        else
            local r = C.smaug_dt_add_ms(v, delta_ms)
            vals[i] = (r == -9223372036854775808) and NA or tonumber(r)
        end
    end
    return Series.from_table(vals, "datetime", s._name)
end

-- Atalhos de add_ms para unidades comuns
function SeriesDT:add_days(n)    return self:add_ms(n * 86400000) end
function SeriesDT:add_hours(n)   return self:add_ms(n * 3600000)  end
function SeriesDT:add_minutes(n) return self:add_ms(n * 60000)    end
function SeriesDT:add_seconds(n) return self:add_ms(n * 1000)     end

-- =====================================================================
-- F.3 — .dt estendido
-- Predicados de calendário, nomes, e arredondamento de período.
-- Tudo derivado das primitivas C (year/month/day/.../from_parts/truncate).
-- =====================================================================

local DT_SENTINEL = -9223372036854775808LL   -- INT64_MIN (data inválida)

-- Tabelas de nomes (inglês, alinhado a pandas). weekday do C: 0=seg..6=dom.
local MONTH_NAMES = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}
local DAY_NAMES = {
    [0] = "Monday", [1] = "Tuesday", [2] = "Wednesday", [3] = "Thursday",
    [4] = "Friday", [5] = "Saturday", [6] = "Sunday",
}

-- Bissexto pela regra gregoriana.
local function leap(y)
    return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

-- Dias no mês (1-12) de um dado ano.
local MDAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
local function days_in(y, m)
    if m == 2 and leap(y) then return 29 end
    return MDAYS[m]
end

-- Helper: aplica fn(epoch_ms) → valor por elemento, montando Series<dtype>.
-- Nulos propagam. fn pode retornar nil para sinalizar null.
local function dt_map(self, fn, out_dtype)
    local s    = self._s
    local n    = s:len()
    local NA   = Series.NA
    local vals = {}
    for i = 1, n do
        local v = s:get(i)
        if v == nil then
            vals[i] = NA
        else
            local r = fn(v)
            vals[i] = (r == nil) and NA or r
        end
    end
    return Series.from_table(vals, out_dtype, s._name)
end

-- ---- Predicados de início/fim de período → Series<bool> ----

-- is_month_start: dia == 1
function SeriesDT:is_month_start()
    return dt_map(self, function(v) return C.smaug_dt_day(v) == 1 end, "bool")
end

-- is_month_end: dia == dias_no_mês(ano, mês)
function SeriesDT:is_month_end()
    return dt_map(self, function(v)
        local y, m, d = C.smaug_dt_year(v), C.smaug_dt_month(v), C.smaug_dt_day(v)
        return d == days_in(y, m)
    end, "bool")
end

-- is_quarter_start: mês ∈ {1,4,7,10} e dia == 1
function SeriesDT:is_quarter_start()
    return dt_map(self, function(v)
        local m, d = C.smaug_dt_month(v), C.smaug_dt_day(v)
        return d == 1 and (m == 1 or m == 4 or m == 7 or m == 10)
    end, "bool")
end

-- is_quarter_end: mês ∈ {3,6,9,12} e dia == último dia do mês
function SeriesDT:is_quarter_end()
    return dt_map(self, function(v)
        local y, m, d = C.smaug_dt_year(v), C.smaug_dt_month(v), C.smaug_dt_day(v)
        return d == days_in(y, m) and (m == 3 or m == 6 or m == 9 or m == 12)
    end, "bool")
end

-- is_year_start: mês == 1 e dia == 1
function SeriesDT:is_year_start()
    return dt_map(self, function(v)
        return C.smaug_dt_month(v) == 1 and C.smaug_dt_day(v) == 1
    end, "bool")
end

-- is_year_end: mês == 12 e dia == 31
function SeriesDT:is_year_end()
    return dt_map(self, function(v)
        return C.smaug_dt_month(v) == 12 and C.smaug_dt_day(v) == 31
    end, "bool")
end

-- is_leap_year: ano é bissexto → Series<bool>
function SeriesDT:is_leap_year()
    return dt_map(self, function(v) return leap(C.smaug_dt_year(v)) end, "bool")
end

-- days_in_month: número de dias do mês de cada elemento → Series<int64>
function SeriesDT:days_in_month()
    return dt_map(self, function(v)
        return days_in(C.smaug_dt_year(v), C.smaug_dt_month(v))
    end, "int64")
end

-- ---- Nomes ----

-- month_name: nome do mês em inglês → Series<string>
function SeriesDT:month_name()
    return dt_map(self, function(v) return MONTH_NAMES[C.smaug_dt_month(v)] end, "string")
end

-- day_name: nome do dia da semana em inglês → Series<string>
function SeriesDT:day_name()
    return dt_map(self, function(v) return DAY_NAMES[C.smaug_dt_weekday(v)] end, "string")
end

-- ---- normalize: zera a hora (= truncate("D")) → Series<datetime> ----
function SeriesDT:normalize()
    return self:truncate("D")
end

-- ---- round / ceil de período (complementam truncate = floor) ----

-- Avança um epoch_ms truncado por exatamente uma unidade `unit`, retornando
-- o início do PRÓXIMO período. Usa from_parts para unidades de calendário
-- (M/Q/Y, comprimento variável) e add_ms para as de comprimento fixo.
local function next_period(floor_ms, unit)
    if unit == "Y" then
        local y = C.smaug_dt_year(floor_ms)
        return C.smaug_dt_from_parts(y + 1, 1, 1, 0, 0, 0, 0)
    elseif unit == "Q" then
        local y, m = C.smaug_dt_year(floor_ms), C.smaug_dt_month(floor_ms)
        -- floor de Q tem mês ∈ {1,4,7,10}; próximo trimestre = +3 meses
        local nm = m + 3
        if nm > 12 then nm = nm - 12; y = y + 1 end
        return C.smaug_dt_from_parts(y, nm, 1, 0, 0, 0, 0)
    elseif unit == "M" then
        local y, m = C.smaug_dt_year(floor_ms), C.smaug_dt_month(floor_ms)
        local nm = m + 1
        if nm > 12 then nm = 1; y = y + 1 end
        return C.smaug_dt_from_parts(y, nm, 1, 0, 0, 0, 0)
    elseif unit == "W" then
        return C.smaug_dt_add_ms(floor_ms, 7 * 86400000)
    elseif unit == "D" then
        return C.smaug_dt_add_ms(floor_ms, 86400000)
    elseif unit == "h" then
        return C.smaug_dt_add_ms(floor_ms, 3600000)
    elseif unit == "m" then
        return C.smaug_dt_add_ms(floor_ms, 60000)
    elseif unit == "s" then
        return C.smaug_dt_add_ms(floor_ms, 1000)
    end
    return DT_SENTINEL
end

local VALID_UNITS = { s=true, m=true, h=true, D=true, W=true, M=true, Q=true, Y=true }

-- ceil(unit): menor início-de-período >= v. Se v já está no limite, retorna v.
function SeriesDT:ceil(unit)
    if type(unit) ~= "string" or not VALID_UNITS[unit] then
        error("smaug: dt:ceil() unidade inválida (use s/m/h/D/W/M/Q/Y)", 2)
    end
    local u = string.byte(unit)
    return dt_map(self, function(v)
        local floor = C.smaug_dt_truncate(v, u)
        if floor == DT_SENTINEL then return nil end
        if floor == v then return tonumber(v) end   -- já alinhado
        local nxt = next_period(floor, unit)
        if nxt == DT_SENTINEL then return nil end
        return tonumber(nxt)
    end, "datetime")
end

-- round(unit): início-de-período mais próximo. Empate (exatamente no meio)
-- arredonda para cima (half-up), consistente com pandas.
function SeriesDT:round(unit)
    if type(unit) ~= "string" or not VALID_UNITS[unit] then
        error("smaug: dt:round() unidade inválida (use s/m/h/D/W/M/Q/Y)", 2)
    end
    local u = string.byte(unit)
    return dt_map(self, function(v)
        local floor = C.smaug_dt_truncate(v, u)
        if floor == DT_SENTINEL then return nil end
        local nxt = next_period(floor, unit)
        if nxt == DT_SENTINEL then return nil end
        -- distâncias (em ms) ao floor e ao próximo período
        local to_floor = tonumber(C.smaug_dt_diff_ms(v, floor))       -- v - floor >= 0
        local to_next  = tonumber(C.smaug_dt_diff_ms(nxt, v))         -- next - v >= 0
        if to_floor < to_next then
            return tonumber(floor)
        else
            return tonumber(nxt)   -- half-up no empate
        end
    end, "datetime")
end

-- ---- strftime: formatação por tokens estilo C → Series<string> ----
-- Tokens suportados: %Y %y %m %d %H %M %S %j %B %b %A %a %p %% .
-- Tokens desconhecidos são mantidos literais (com o %).
local ABBR_MONTH = {
    "Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec",
}
local ABBR_DAY = {
    [0]="Mon",[1]="Tue",[2]="Wed",[3]="Thu",[4]="Fri",[5]="Sat",[6]="Sun",
}

function SeriesDT:strftime(fmt)
    if type(fmt) ~= "string" then
        error("smaug: dt:strftime() espera string de formato", 2)
    end
    return dt_map(self, function(v)
        local Y = C.smaug_dt_year(v)
        local mo = C.smaug_dt_month(v)
        local d = C.smaug_dt_day(v)
        local H = C.smaug_dt_hour(v)
        local Mi = C.smaug_dt_minute(v)
        local Se = C.smaug_dt_second(v)
        local j = C.smaug_dt_yearday(v)
        local wd = C.smaug_dt_weekday(v)
        local h12 = H % 12; if h12 == 0 then h12 = 12 end
        local subst = {
            Y = string.format("%04d", Y),
            y = string.format("%02d", Y % 100),
            m = string.format("%02d", mo),
            d = string.format("%02d", d),
            H = string.format("%02d", H),
            M = string.format("%02d", Mi),
            S = string.format("%02d", Se),
            j = string.format("%03d", j),
            I = string.format("%02d", h12),
            p = (H < 12) and "AM" or "PM",
            B = MONTH_NAMES[mo],
            b = ABBR_MONTH[mo],
            A = DAY_NAMES[wd],
            a = ABBR_DAY[wd],
            ["%"] = "%",
        }
        -- substitui %X; token desconhecido fica literal (mantém o %X)
        return (fmt:gsub("%%(.)", function(c)
            local r = subst[c]
            if r ~= nil then return r end
            return "%" .. c
        end))
    end, "string")
end

-- =====================================================================

-- Acesso ao proxy .dt na Series
methods.dt = nil  -- reservado; resolvido via __index abaixo

-- SeriesAt: proxy de acesso escalar para s.at / s.iat.
-- Suporta indexação (s.at[i]) e chamada (s.at(i)); ambos delegam a get().
local SeriesAt = {
    __index = function(self, i)
        if type(i) ~= "number" then
            error("smaug: at/iat espera índice numérico (1-based)", 2)
        end
        return methods.get(self._s, i)
    end,
    __call = function(self, i)
        return methods.get(self._s, i)
    end,
}

-- __index unificado: índice numérico → get(); .str → StrProxy; .dt → SeriesDT; método.
Series.__index = function(self, k)
    if k == "dt" then
        if self._dtype ~= "datetime" then
            error("smaug: accessor .dt só se aplica a séries datetime; dtype é '"
                  .. self._dtype .. "'", 2)
        end
        return setmetatable({ _s = self }, SeriesDT)
    end
    if type(k) == "number" then return methods.get(self, k) end
    if k == "str" then
        if self._dtype ~= "string" then
            error("smaug: accessor .str só se aplica a séries string; dtype é '"
                  .. self._dtype .. "'", 2)
        end
        return setmetatable({ _s = self }, StrProxy)
    end
    -- at / iat: acesso escalar posicional. Suporta s.at[i] e s.at(i).
    -- Em uma Series 1-D, at e iat são equivalentes (índice = posição).
    if k == "at" or k == "iat" then
        return setmetatable({ _s = self }, SeriesAt)
    end
    return methods[k]
end

-- Factory: Series.datetime(size, name)
function Series.datetime(size, name) return Series.new("datetime", size, name) end

-- Helper público: parse de string ISO 8601 → epoch_ms (número Lua)
function Series.dt_parse(str)
    if type(str) ~= "string" then
        error("smaug: Series.dt_parse() espera string", 2)
    end
    local ep = ffi.new("int64_t[1]")
    if C.smaug_dt_parse(str, #str, ep) ~= 0 then
        return nil
    end
    return tonumber(ep[0])
end

-- Helper público: epoch_ms → string ISO 8601
function Series.dt_format(epoch_ms)
    local buf = ffi.new("char[26]")
    if C.smaug_dt_format(epoch_ms, buf, 26) ~= 0 then return nil end
    return ffi.string(buf)
end

-- Construção a partir de partes
function Series.dt_from_parts(year, month, day, hour, minute, second, ms)
    hour = hour or 0; minute = minute or 0; second = second or 0; ms = ms or 0
    local r = C.smaug_dt_from_parts(year, month, day, hour, minute, second, ms)
    if r == -9223372036854775808 then return nil end
    return tonumber(r)
end

-- expõe o registro de dtypes para extensão futura (bool, string, ...)
Series._DTYPES = DTYPES
Series.NA = NA

-- =====================================================================
-- CategoricalSeries — dtype Tier 2 (Lua puro, sem C backend)
-- =====================================================================
-- Armazenamento: dictionary encoding.
--   _codes  : tabela Lua de inteiros 1-based (índice em _levels); nil = null
--   _levels : lista ordenada de strings únicas (o "dicionário")
--   _level_map: hash inverso {string → índice em _levels}
--   _name   : nome da série (string ou nil)
--   _dtype  : "categorical" (constante)
--   _size   : número de elementos
--
-- Contratos:
--   - Null é representado por _codes[i] == nil.
--   - Levels são sempre strings; valores numéricos são convertidos via tostring.
--   - Levels são mantidos em ordem de primeira aparição; reordenaveis via :set_categories().
--   - Imutabilidade de levels: adicionar valor novo cria level novo; remover level
--     converte referências existentes em null.
-- =====================================================================

local CategoricalSeries = {}
CategoricalSeries.__index = CategoricalSeries
CategoricalSeries._dtype  = "categorical"

-- Construtor interno — não use diretamente, use CategoricalSeries.from_table()
local function cat_new(codes, levels, level_map, n, name)
    return setmetatable({
        _codes     = codes,
        _levels    = levels,
        _level_map = level_map,
        _name      = name,
        _size      = n,
        _dtype     = "categorical",
    }, CategoricalSeries)
end

-- ----------------------------------------------------------------
-- Factories
-- ----------------------------------------------------------------

-- from_table: constrói a partir de uma lista Lua de strings (ou nil/NA).
-- Ordem dos levels = ordem de primeira aparição.
function CategoricalSeries.from_table(arr, name)
    local n         = #arr
    local codes     = {}
    local levels    = {}
    local level_map = {}

    for i = 1, n do
        local v = arr[i]
        if v == nil or v == NA then
            codes[i] = nil   -- null
        else
            local s = tostring(v)
            local idx = level_map[s]
            if idx == nil then
                levels[#levels + 1] = s
                idx = #levels
                level_map[s] = idx
            end
            codes[i] = idx
        end
    end
    return cat_new(codes, levels, level_map, n, name)
end

-- from_codes: constrói a partir de codes (int 1-based) e levels explícitos.
-- codes: tabela de inteiros (nil = null). levels: lista de strings.
-- from_codes: aceita NA (smaug.NA ou false) como marcador de null.
-- Para arrays com nil no meio, passe n explicitamente como 4º argumento.
function CategoricalSeries.from_codes(codes_arr, levels_arr, name, n)
    if type(levels_arr) ~= "table" then
        error("smaug: CategoricalSeries.from_codes — levels deve ser tabela", 2)
    end
    n = n or #codes_arr
    local lev = {}
    local lmap = {}
    for i, v in ipairs(levels_arr) do
        lev[i] = tostring(v)
        lmap[tostring(v)] = i
    end
    local codes = {}
    for i = 1, n do
        local c = codes_arr[i]
        if c == nil or c == NA then
            codes[i] = nil
        elseif type(c) ~= "number" or c < 1 or c > #lev then
            error("smaug: from_codes — code "..tostring(c).." fora do intervalo [1,"..#lev.."]", 2)
        else
            codes[i] = c
        end
    end
    return cat_new(codes, lev, lmap, n, name)
end

-- ----------------------------------------------------------------
-- Acesso básico
-- ----------------------------------------------------------------

function CategoricalSeries:len()  return self._size end
function CategoricalSeries:size() return self._size end

function CategoricalSeries:get(i)
    if type(i) ~= "number" or i < 1 or i > self._size then
        error("smaug: índice "..tostring(i).." fora dos limites [1, "..self._size.."]", 2)
    end
    local c = self._codes[i]
    if c == nil then return nil end
    return self._levels[c]
end

function CategoricalSeries:is_null(i)
    if type(i) ~= "number" or i < 1 or i > self._size then
        error("smaug: índice "..tostring(i).." fora dos limites [1, "..self._size.."]", 2)
    end
    return self._codes[i] == nil
end

function CategoricalSeries:set(i, v)
    if type(i) ~= "number" or i < 1 or i > self._size then
        error("smaug: índice "..tostring(i).." fora dos limites [1, "..self._size.."]", 2)
    end
    if v == nil or v == NA then
        self._codes[i] = nil
        return
    end
    local s = tostring(v)
    local idx = self._level_map[s]
    if idx == nil then
        self._levels[#self._levels + 1] = s
        idx = #self._levels
        self._level_map[s] = idx
    end
    self._codes[i] = idx
end

function CategoricalSeries:set_null(i)
    if type(i) ~= "number" or i < 1 or i > self._size then
        error("smaug: índice "..tostring(i).." fora dos limites [1, "..self._size.."]", 2)
    end
    self._codes[i] = nil
end

function CategoricalSeries:append(v)
    self._size = self._size + 1
    local i = self._size
    if v == nil or v == NA then
        self._codes[i] = nil
    else
        local s = tostring(v)
        local idx = self._level_map[s]
        if idx == nil then
            self._levels[#self._levels + 1] = s
            idx = #self._levels
            self._level_map[s] = idx
        end
        self._codes[i] = idx
    end
    return self
end

function CategoricalSeries:count_nonnull()
    local n = 0
    for i = 1, self._size do
        if self._codes[i] ~= nil then n = n + 1 end
    end
    return n
end

-- ----------------------------------------------------------------
-- Transformações (sempre retornam novo objeto)
-- ----------------------------------------------------------------

function CategoricalSeries:clone()
    local codes = {}
    for i = 1, self._size do codes[i] = self._codes[i] end
    local levels = {}
    local lmap   = {}
    for i, v in ipairs(self._levels) do
        levels[i] = v
        lmap[v]   = i
    end
    return cat_new(codes, levels, lmap, self._size, self._name)
end

function CategoricalSeries:head(n)
    n = math.min(n or 5, self._size)
    local codes = {}
    for i = 1, n do codes[i] = self._codes[i] end
    -- reusar mesmos levels (clone defensivo)
    local levels, lmap = {}, {}
    for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
    return cat_new(codes, levels, lmap, n, self._name)
end

function CategoricalSeries:tail(n)
    n = math.min(n or 5, self._size)
    local start = self._size - n + 1
    local codes = {}
    for i = 1, n do codes[i] = self._codes[start + i - 1] end
    local levels, lmap = {}, {}
    for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
    return cat_new(codes, levels, lmap, n, self._name)
end

function CategoricalSeries:take(idx)
    if type(idx) ~= "table" then
        error("smaug: take espera uma tabela de índices", 2)
    end
    local codes = {}
    for j, i in ipairs(idx) do
        if type(i) ~= "number" or i < 1 or i > self._size then
            error("smaug: take — índice "..tostring(i).." fora dos limites", 2)
        end
        codes[j] = self._codes[i]
    end
    local levels, lmap = {}, {}
    for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
    return cat_new(codes, levels, lmap, #idx, self._name)
end

function CategoricalSeries:filter(mask)
    -- mask: Series<bool>
    if type(mask) ~= "table" or mask._dtype ~= "bool" then
        error("smaug: filter espera Series<bool>", 2)
    end
    if mask:len() ~= self._size then
        error("smaug: filter — tamanhos diferentes", 2)
    end
    local codes = {}
    local n = 0
    for i = 1, self._size do
        if mask:get(i) == true then
            n = n + 1
            codes[n] = self._codes[i]
        end
    end
    local levels, lmap = {}, {}
    for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
    return cat_new(codes, levels, lmap, n, self._name)
end

function CategoricalSeries:dropna()
    local codes = {}
    local n = 0
    for i = 1, self._size do
        if self._codes[i] ~= nil then
            n = n + 1
            codes[n] = self._codes[i]
        end
    end
    local levels, lmap = {}, {}
    for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
    return cat_new(codes, levels, lmap, n, self._name)
end

function CategoricalSeries:fillna(value)
    if value == nil or value == NA then
        error("smaug: fillna requer um valor de preenchimento", 2)
    end
    local s = tostring(value)
    -- encontra ou cria o code do valor de preenchimento
    local fill_idx = self._level_map[s]
    local new_levels, new_lmap = {}, {}
    for i, v in ipairs(self._levels) do new_levels[i] = v; new_lmap[v] = i end
    if fill_idx == nil then
        new_levels[#new_levels + 1] = s
        fill_idx = #new_levels
        new_lmap[s] = fill_idx
    end
    local codes = {}
    for i = 1, self._size do
        codes[i] = self._codes[i] ~= nil and self._codes[i] or fill_idx
    end
    return cat_new(codes, new_levels, new_lmap, self._size, self._name)
end

-- sort (ascendente por label string)
function CategoricalSeries:sort(ascending)
    if ascending == nil then ascending = true end
    -- garante sem nulos
    for i = 1, self._size do
        if self._codes[i] == nil then
            error("smaug: sort não suporta séries com nulos (use dropna primeiro)", 2)
        end
    end
    -- cria índices e ordena por label
    local idx = {}
    for i = 1, self._size do idx[i] = i end
    local levels = self._levels
    local codes  = self._codes
    if ascending then
        table.sort(idx, function(a, b) return levels[codes[a]] < levels[codes[b]] end)
    else
        table.sort(idx, function(a, b) return levels[codes[a]] > levels[codes[b]] end)
    end
    local new_codes = {}
    for j, i in ipairs(idx) do new_codes[j] = codes[i] end
    local new_levels, new_lmap = {}, {}
    for i, v in ipairs(levels) do new_levels[i] = v; new_lmap[v] = i end
    return cat_new(new_codes, new_levels, new_lmap, self._size, self._name)
end

function CategoricalSeries:argsort(ascending)
    if ascending == nil then ascending = true end
    for i = 1, self._size do
        if self._codes[i] == nil then return nil end
    end
    local idx    = {}
    local levels = self._levels
    local codes  = self._codes
    for i = 1, self._size do idx[i] = i end
    if ascending then
        table.sort(idx, function(a, b) return levels[codes[a]] < levels[codes[b]] end)
    else
        table.sort(idx, function(a, b) return levels[codes[a]] > levels[codes[b]] end)
    end
    return idx
end

-- Comparações → Series<bool>
local function cat_compare(self, target, fn)
    if type(target) ~= "string" then
        error("smaug: comparação categorical espera string", 2)
    end
    local vals = {}
    for i = 1, self._size do
        local v = self:get(i)
        if v == nil then
            vals[i] = NA
        else
            vals[i] = fn(v, target)
        end
    end
    return Series.from_table(vals, "bool", self._name)
end

function CategoricalSeries:eq(t) return cat_compare(self, t, function(a,b) return a == b end) end
function CategoricalSeries:ne(t) return cat_compare(self, t, function(a,b) return a ~= b end) end
function CategoricalSeries:lt(t) return cat_compare(self, t, function(a,b) return a <  b end) end
function CategoricalSeries:le(t) return cat_compare(self, t, function(a,b) return a <= b end) end
function CategoricalSeries:gt(t) return cat_compare(self, t, function(a,b) return a >  b end) end
function CategoricalSeries:ge(t) return cat_compare(self, t, function(a,b) return a >= b end) end

-- unique / nunique / value_counts
function CategoricalSeries:unique()
    local seen  = {}
    local vals  = {}
    for i = 1, self._size do
        local v = self:get(i)
        if v ~= nil and not seen[v] then
            seen[v]         = true
            vals[#vals + 1] = v
        end
    end
    return CategoricalSeries.from_table(vals, self._name)
end

function CategoricalSeries:nunique()
    local seen = {}
    local n    = 0
    for i = 1, self._size do
        local v = self:get(i)
        if v ~= nil and not seen[v] then
            seen[v] = true; n = n + 1
        end
    end
    return n
end

function CategoricalSeries:value_counts()
    local freq  = {}
    local order = {}
    for i = 1, self._size do
        local v = self:get(i)
        if v ~= nil then
            if not freq[v] then order[#order+1] = v end
            freq[v] = (freq[v] or 0) + 1
        end
    end
    table.sort(order, function(a, b)
        if freq[a] ~= freq[b] then return freq[a] > freq[b] end
        return a < b
    end)
    local vals   = {}
    local counts = {}
    for i, v in ipairs(order) do
        vals[i]   = v
        counts[i] = freq[v]
    end
    -- retorna DataSet (mesmo contrato de Series:value_counts)
    -- importado via upvalue DataSet (ainda não disponível aqui — retorna tabelas)
    return { value = vals, count = counts }
end

-- ----------------------------------------------------------------
-- Predicados de nulidade
-- ----------------------------------------------------------------

-- isna(i) / notna(i): aliases de is_null / not is_null.
function CategoricalSeries:isna(i)  return self:is_null(i) end
function CategoricalSeries:notna(i) return not self:is_null(i) end

-- ----------------------------------------------------------------
-- Reduções de ordem (lexicográfica sobre labels)
-- ----------------------------------------------------------------

-- min(): menor label lexicográfico entre não-nulos. nil se vazia ou toda nula.
function CategoricalSeries:min()
    local best = nil
    for i = 1, self._size do
        local v = self:get(i)
        if v ~= nil and (best == nil or v < best) then best = v end
    end
    return best
end

-- max(): maior label lexicográfico entre não-nulos. nil se vazia ou toda nula.
function CategoricalSeries:max()
    local best = nil
    for i = 1, self._size do
        local v = self:get(i)
        if v ~= nil and (best == nil or v > best) then best = v end
    end
    return best
end

-- ----------------------------------------------------------------
-- Valores ausentes — preenchimento temporal
-- ----------------------------------------------------------------

-- ffill(): preenche nulos com o último label não-nulo anterior.
-- Opera ao nível de codes para eficiência; preserva levels existentes.
function CategoricalSeries:ffill()
    local codes = {}
    local last  = nil
    for i = 1, self._size do
        if self._codes[i] ~= nil then last = self._codes[i] end
        codes[i] = last   -- nil se ainda não encontrou nenhum não-nulo
    end
    local levels, lmap = {}, {}
    for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
    return cat_new(codes, levels, lmap, self._size, self._name)
end

-- bfill(): preenche nulos com o próximo label não-nulo seguinte.
function CategoricalSeries:bfill()
    local codes     = {}
    local next_code = nil
    for i = self._size, 1, -1 do
        if self._codes[i] ~= nil then next_code = self._codes[i] end
        codes[i] = next_code   -- nil se nenhum não-nulo à direita
    end
    local levels, lmap = {}, {}
    for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
    return cat_new(codes, levels, lmap, self._size, self._name)
end

-- ----------------------------------------------------------------
-- Janela temporal
-- ----------------------------------------------------------------

-- shift(periods): desloca valores `periods` posições (default 1). Posições
-- descobertas tornam-se null. Opera ao nível de codes.
function CategoricalSeries:shift(periods)
    periods = periods or 1
    local codes = {}
    for i = 1, self._size do
        local src = i - periods
        codes[i] = (src >= 1 and src <= self._size) and self._codes[src] or nil
    end
    local levels, lmap = {}, {}
    for i, v in ipairs(self._levels) do levels[i] = v; lmap[v] = i end
    return cat_new(codes, levels, lmap, self._size, self._name)
end

-- ----------------------------------------------------------------
-- Transformação elemento a elemento
-- ----------------------------------------------------------------

-- map(fn, [dtype], [name]): aplica fn a cada label (nil para null).
-- nil retornado por fn → null. dtype do resultado inferido do 1º retorno não-null.
-- Retorna Series do dtype inferido (não CategoricalSeries).
function CategoricalSeries:map(fn, dtype, name)
    if type(fn) ~= "function" then
        error("smaug: map() espera uma função", 2)
    end
    local vals     = {}
    local inferred = dtype
    for i = 1, self._size do
        local v   = self:get(i)
        local out = fn(v)
        if out == nil or out == NA then
            vals[i] = NA
        else
            if inferred == nil then
                if     type(out) == "boolean" then inferred = "bool"
                elseif type(out) == "string"  then inferred = "string"
                elseif type(out) == "number" and out % 1 == 0 then inferred = "int64"
                else   inferred = "float64"
                end
            end
            vals[i] = out
        end
    end
    return Series.from_table(vals, inferred or "string", name or self._name)
end

-- ----------------------------------------------------------------
-- Seleção condicional
-- ----------------------------------------------------------------

-- where(cond, other): mantém self onde cond=true; usa other onde false/NA.
-- other: string escalar, nil (→ null) ou Series/CategoricalSeries alinhada.
-- Retorna novo CategoricalSeries reconstruído via from_table.
function CategoricalSeries:where(cond, other)
    if type(cond) ~= "table" or cond._dtype ~= "bool" then
        error("smaug: where() espera Series<bool> como primeiro argumento", 2)
    end
    if cond:len() ~= self._size then
        error("smaug: where() — tamanhos diferentes ("..cond:len().." vs "..self._size..")", 2)
    end
    local has_other = type(other) == "table" and other._dtype ~= nil
    local vals = {}
    for i = 1, self._size do
        local c = cond:get(i)
        if c == true then
            vals[i] = self:get(i)
        else
            vals[i] = has_other and other:get(i) or (other == nil and NA or other)
        end
    end
    return CategoricalSeries.from_table(vals, self._name)
end

-- mask(cond, other): inverso de where — substitui onde cond=true.
function CategoricalSeries:mask(cond, other)
    if type(cond) ~= "table" or cond._dtype ~= "bool" then
        error("smaug: mask() espera Series<bool> como primeiro argumento", 2)
    end
    if cond:len() ~= self._size then
        error("smaug: mask() — tamanhos diferentes ("..cond:len().." vs "..self._size..")", 2)
    end
    local has_other = type(other) == "table" and other._dtype ~= nil
    local vals = {}
    for i = 1, self._size do
        local c = cond:get(i)
        if c == true then
            vals[i] = has_other and other:get(i) or (other == nil and NA or other)
        else
            vals[i] = self:get(i)
        end
    end
    return CategoricalSeries.from_table(vals, self._name)
end

-- describe
function CategoricalSeries:describe()
    local freq  = {}
    local top, top_freq = nil, 0
    for i = 1, self._size do
        local v = self:get(i)
        if v ~= nil then
            freq[v] = (freq[v] or 0) + 1
            if freq[v] > top_freq then top, top_freq = v, freq[v] end
        end
    end
    local nulls = self._size - self:count_nonnull()
    local u = 0
    for _ in pairs(freq) do u = u + 1 end
    return {
        dtype   = "categorical",
        count   = self._size - nulls,
        nulls   = nulls,
        unique  = u,
        levels  = #self._levels,
        top     = top,
        freq    = top_freq > 0 and top_freq or nil,
    }
end

-- to_table: lista Lua de valores (nil para null)
function CategoricalSeries:to_table(na_value)
    local t = {}
    for i = 1, self._size do
        local v = self:get(i)
        t[i] = v ~= nil and v or na_value
    end
    return t
end

-- astype
function CategoricalSeries:astype(dtype, name)
    name = name or self._name
    if dtype == "categorical" then return self:clone() end
    if dtype == "string" then
        local vals = {}
        for i = 1, self._size do
            vals[i] = self._codes[i] ~= nil and self._levels[self._codes[i]] or NA
        end
        return Series.from_table(vals, "string", name)
    end
    -- numérico: tenta tonumber em cada label
    if dtype == "float64" or dtype == "int64" or dtype == "int32" then
        local vals = {}
        for i = 1, self._size do
            if self._codes[i] == nil then
                vals[i] = NA
            else
                local num = tonumber(self._levels[self._codes[i]])
                vals[i] = num ~= nil and num or NA
            end
        end
        return Series.from_table(vals, dtype == "int32" and "int64" or dtype, name)
    end
    error("smaug: astype categorical → '"..tostring(dtype).."' não suportado", 2)
end

-- ----------------------------------------------------------------
-- .cat accessor
-- ----------------------------------------------------------------

local CatProxy = {}
CatProxy.__index = CatProxy

-- codes(): Series<int64> com os índices internos (1-based; null → null)
function CatProxy:codes()
    local vals = {}
    local s    = self._s
    for i = 1, s._size do
        vals[i] = s._codes[i] ~= nil and s._codes[i] or NA
    end
    return Series.from_table(vals, "int64", s._name)
end

-- levels(): tabela Lua com os levels em ordem
function CatProxy:levels()
    local t = {}
    for i, v in ipairs(self._s._levels) do t[i] = v end
    return t
end

-- rename_categories({old = new, ...}): novo CategoricalSeries com levels renomeados
function CatProxy:rename_categories(mapping)
    if type(mapping) ~= "table" then
        error("smaug: rename_categories espera tabela {old = new, ...}", 2)
    end
    local s      = self._s
    local new_levels = {}
    local new_lmap   = {}
    for i, v in ipairs(s._levels) do
        local nv = mapping[v] ~= nil and tostring(mapping[v]) or v
        new_levels[i] = nv
        new_lmap[nv]  = i
    end
    local codes = {}
    for i = 1, s._size do codes[i] = s._codes[i] end
    return cat_new(codes, new_levels, new_lmap, s._size, s._name)
end

-- set_categories(new_levels): reordena/restringe levels.
-- Valores cujo label não está nos novos levels viram null.
function CatProxy:set_categories(new_levels_arr)
    if type(new_levels_arr) ~= "table" then
        error("smaug: set_categories espera tabela de strings", 2)
    end
    local s       = self._s
    local new_lev = {}
    local new_map = {}
    for i, v in ipairs(new_levels_arr) do
        new_lev[i]       = tostring(v)
        new_map[tostring(v)] = i
    end
    -- remapeia: code antigo → novo code (ou nil se label não existe nos novos levels)
    local remap = {}
    for i, v in ipairs(s._levels) do
        remap[i] = new_map[v]   -- nil se não encontrado
    end
    local codes = {}
    for i = 1, s._size do
        local old_c = s._codes[i]
        codes[i]    = old_c ~= nil and remap[old_c] or nil
    end
    return cat_new(codes, new_lev, new_map, s._size, s._name)
end

-- add_categories(vals): adiciona novos levels sem alterar dados
function CatProxy:add_categories(vals)
    local s       = self._s
    local new_lev = {}
    local new_map = {}
    for i, v in ipairs(s._levels) do new_lev[i] = v; new_map[v] = i end
    for _, v in ipairs(vals) do
        local sv = tostring(v)
        if not new_map[sv] then
            new_lev[#new_lev + 1] = sv
            new_map[sv]           = #new_lev
        end
    end
    local codes = {}
    for i = 1, s._size do codes[i] = s._codes[i] end
    return cat_new(codes, new_lev, new_map, s._size, s._name)
end

-- remove_categories(vals): remove levels; referências tornam-se null
function CatProxy:remove_categories(vals)
    local s      = self._s
    local remove = {}
    for _, v in ipairs(vals) do remove[tostring(v)] = true end
    local new_lev = {}
    local new_map = {}
    local remap   = {}   -- old_idx → new_idx
    for i, v in ipairs(s._levels) do
        if not remove[v] then
            new_lev[#new_lev + 1] = v
            new_map[v]            = #new_lev
            remap[i]              = #new_lev
        end
    end
    local codes = {}
    for i = 1, s._size do
        local c = s._codes[i]
        codes[i] = c ~= nil and remap[c] or nil
    end
    return cat_new(codes, new_lev, new_map, s._size, s._name)
end

-- __index: cat[k] numérico → get; método CatProxy; erro claro
CategoricalSeries.__index = function(self, k)
    if k == "cat" then
        return setmetatable({ _s = self }, CatProxy)
    end
    if type(k) == "number" then return CategoricalSeries.get(self, k) end
    return CategoricalSeries[k]
end

-- Expõe como factory via Series.from_table("categorical")
-- e como classe separada em Series.Categorical
Series.Categorical = CategoricalSeries

-- Intercepta from_table para dtype "categorical"
local _orig_from_table = Series.from_table
function Series.from_table(arr, dtype, name)
    if dtype == "categorical" then
        return CategoricalSeries.from_table(arr, name)
    end
    return _orig_from_table(arr, dtype, name)
end

-- Helper público
function Series.is_categorical(x)
    return getmetatable(x) == CategoricalSeries
end

return Series
