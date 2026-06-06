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
local BoolSeries = require("smaug.core.boolseries")

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
        -- wrappers de comparação: validam escalar numérico e chamam a função C.
        cmp_gt = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_gt(c,t,om) end,
        cmp_lt = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_lt(c,t,om) end,
        cmp_eq = function(c, t, om) if type(t)~="number" then error("smaug: comparação f64 espera número",4) end return C.smaug_f64_eq(c,t,om) end,
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
        cmp_gt = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_gt(c,t,om) end,
        cmp_lt = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_lt(c,t,om) end,
        cmp_eq = function(c, t, om) if type(t)~="number" then error("smaug: comparação i64 espera número",4) end return C.smaug_i64_eq(c,t,om) end,
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
    else  -- float64
        if type(v) ~= "number" then
            error("smaug: valor para " .. dt .. " deve ser número; "
                  .. "recebido " .. type(v), level or 3)
        end
    end
end

-- Contrato defensivo: o backend devolve smaug_status_t (0 == SMG_OK; o str_set
-- legado também usa 0 == ok). Qualquer status ≠ 0 após validação de índice/valor
-- é tratado como segue:
--   SMG_ERR_NOMEM (4): COW-detach falhou por OOM — erro de usuário propagado.
--   Qualquer outro: invariante do backend violado (ou dessincronização do cdef).
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
    -- Phase B pendente: COW-detach para append/append_null ainda não implementado.
    -- Quando Phase B estiver pronto esta guarda é removida. Enquanto isso, a leitura
    -- de is_view é feita ao vivo (sem cache) para não depender de estado stale.
    if self._c.meta.is_view then
        error("smaug: append em view não suportado ainda; use :set() ou :clone():append()", 2)
    end
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

function methods.astype(self, dtype, name)
    if not DTYPES[dtype] then
        error("smaug: dtype desconhecido '"..tostring(dtype).."'", 2)
    end
    local n = self:len()
    local out = Series.new(dtype, n, name or self._name)
    local to_int = (dtype == "int64")
    for i = 1, n do
        local v = self:get(i)
        if v == nil then
            out:set_null(i)
        elseif to_int then
            -- f64 -> i64: NaN não tem representação em inteiro → vira null
            -- (coerente: NaN = indefinido; em i64, indefinido = ausente).
            -- Inf idem (não cabe em int64). Demais: truncagem em direção a zero.
            if v ~= v or v == math.huge or v == -math.huge then
                out:set_null(i)
            else
                out:set(i, trunc_to_int(v))
            end
        else
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
    -- sem valor seguro de preenchimento (fwd/bwd-fill é dívida técnica)
    if value == nil or value == NA then
        error("smaug: fillna requer um valor de preenchimento", 2)
    end
    if type(value) ~= "number" then
        error("smaug: fillna requer um número compatível com o dtype", 2)
    end
    -- sem coerção: i64 só aceita inteiro (1.5 em i64 é erro, não trunca)
    if self._dtype == "int64" and value % 1 ~= 0 then
        error("smaug: fillna em int64 requer valor inteiro (sem coerção); "
              .. "recebido " .. tostring(value), 2)
    end
    local n = self:len()
    local out = Series.new(self._dtype, n, self._name)
    for i = 1, n do
        if self:is_null(i) then
            out:set(i, value)                 -- preenche o null
        else
            out:set(i, self:get(i))           -- copia o valor (NaN incluso)
        end
    end
    return out
end

-- describe: resumo estatístico (tabela Lua). Percentis calculados a partir dos
-- valores não-nulos ordenados em Lua (não exige dropna no C).
function methods.describe(self)
    local vals = {}
    for i = 1, self:len() do
        local v = self:get(i)
        if v ~= nil then vals[#vals + 1] = v end
    end
    table.sort(vals)
    local m = #vals
    local function pct(p)
        if m == 0 then return nil end
        if m == 1 then return vals[1] end
        local rank = p * (m - 1) + 1           -- interpolação linear (tipo numpy)
        local lo = math.floor(rank)
        local frac = rank - lo
        if lo >= m then return vals[m] end
        return vals[lo] + frac * (vals[lo + 1] - vals[lo])
    end
    return {
        count   = m,                            -- não-nulos
        nulls   = self:len() - m,
        mean    = self:mean(),
        std     = self:std(),
        min     = self:min(),
        ["25%"] = pct(0.25),
        ["50%"] = pct(0.50),                    -- mediana
        ["75%"] = pct(0.75),
        max     = self:max(),
    }
end

-- =====================================================================
-- Comparações -> BoolSeries, e filtragem
-- =====================================================================
local function compare(self, cmp_name, target)
    -- cada dtype tem seu wrapper de comparação no descritor (cmp_eq/cmp_lt/
    -- cmp_gt): ele valida o alvo no tipo certo e chama a função C com a
    -- assinatura adequada (numéricos passam escalar; string passa ponteiro+len).
    -- Mantém os métodos genéricos agnósticos ao dtype (encapsulamento limpo).
    local wrapper = self._d[cmp_name]
    if wrapper == nil then
        error("smaug: comparação '" .. cmp_name .. "' não se aplica ao tipo "
              .. self._dtype, 3)
    end
    local om = ffi.new("smaug_mask_t*[1]")
    local vals = wrapper(self._c, target, om)
    if vals == nil then error("smaug: comparação falhou", 3) end
    return BoolSeries._own(vals, om[0], self:len(), self._name)
end

function methods.gt(self, target) return compare(self, "cmp_gt", target) end
function methods.lt(self, target) return compare(self, "cmp_lt", target) end
function methods.eq(self, target) return compare(self, "cmp_eq", target) end

-- filter(bool_series): nova Series só com as linhas onde a máscara é true.
-- NA na máscara conta como false (linha descartada).
function methods.filter(self, mask)
    if getmetatable(mask) ~= BoolSeries then
        error("smaug: filter espera uma BoolSeries (use :gt/:lt/:eq)", 2)
    end
    if mask:len() ~= self:len() then
        error("smaug: filter com máscara de tamanho diferente ("..
              mask:len().." vs "..self:len()..")", 2)
    end
    local r = self._d.filter(self._c, mask._vals)
    if r == nil then error("smaug: filter falhou", 2) end
    return wrap(r, self._dtype, self._name)
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

-- __index: índice numérico -> get(); senão, método.
Series.__index = function(self, k)
    if type(k) == "number" then return methods.get(self, k) end
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
