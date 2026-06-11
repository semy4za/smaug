-- lua/smaug/core/boolseries.lua
--
-- BoolSeries: resultado de comparações (:gt/:lt/:eq) e máscara de filtragem.
--
-- Diferente de Series (f64/i64), a BoolSeries NÃO encapsula um struct
-- smaug_series_*_t. Ela possui o par de arrays brutos devolvidos pelo backend:
--   * _vals  : uint8_t*       (1 = true, 0 = false)
--   * _nulls : smaug_mask_t*  (0xFF = válido, 0x00 = NA)  -- pode ser nil
--   * _n     : comprimento
-- Ambos os arrays são malloc()ados em C; registramos ffi.gc(ptr, C.smaug_free) para
-- liberá-los automaticamente.
--
-- Null handling: lógica de três valores (Kleene), feita em C — ver
-- smaug_ops_bool.c. NA AND false = false; NA OR true = true; NOT NA = NA; etc.

local ffi = require("ffi")
local C   = require("smaug.ffi_loader")

local BoolSeries = {}

local methods = {}

-- Constrói a partir de ponteiros brutos já alocados em C, assumindo posse deles.
-- `vals` e `nulls` são cdata uint8_t*/smaug_mask_t* (nulls pode ser nil).
local function own(vals, nulls, n, name)
    if vals == nil then error("smaug: BoolSeries recebeu ponteiro nulo", 2) end
    ffi.gc(vals, C.smaug_free)
    if nulls ~= nil then ffi.gc(nulls, C.smaug_free) end
    return setmetatable({
        _vals  = vals,
        _nulls = nulls,         -- pode ser nil (sem nulos)
        _n     = n,
        _name  = name or "mask",
    }, BoolSeries)
end

-- Aloca um novo out_mask[1] para receber a máscara de saída de uma op em C.
local function new_outmask()
    return ffi.new("smaug_mask_t*[1]")
end

-- =====================================================================
-- Acesso
-- =====================================================================
function methods.len(self) return tonumber(self._n) end
methods.size = methods.len

function methods.is_null(self, i)
    if i < 1 or i > self._n then error("smaug: índice fora dos limites", 2) end
    if self._nulls == nil then return false end
    return self._nulls[i - 1] ~= 0xFF
end

-- get(i): true / false / nil (NA). 1-based.
function methods.get(self, i)
    if i < 1 or i > self._n then error("smaug: índice fora dos limites", 2) end
    if self._nulls ~= nil and self._nulls[i - 1] ~= 0xFF then return nil end
    return self._vals[i - 1] ~= 0
end

function methods.to_table(self, na_value)
    local t = {}
    for i = 1, tonumber(self._n) do
        local v = self:get(i)
        if v == nil then v = na_value end
        t[i] = v
    end
    return t
end

-- =====================================================================
-- Agregações (NA ignorado)
-- =====================================================================
function methods.count_true(self)
    return tonumber(C.smaug_bool_count_true(self._vals, self._nulls, self._n))
end

function methods.any(self) return C.smaug_bool_any(self._vals, self._nulls, self._n) end
function methods.all(self) return C.smaug_bool_all(self._vals, self._nulls, self._n) end

-- =====================================================================
-- Operações lógicas (Kleene) — retornam nova BoolSeries
-- =====================================================================
local function logical_binop(a, b, cfn, opname)
    if getmetatable(a) ~= BoolSeries or getmetatable(b) ~= BoolSeries then
        error("smaug: '"..opname.."' exige duas BoolSeries", 2)
    end
    if a._n ~= b._n then
        error("smaug: '"..opname.."' entre BoolSeries de tamanhos diferentes", 2)
    end
    local om = new_outmask()
    local r = cfn(a._vals, a._nulls, b._vals, b._nulls, a._n, om)
    return own(r, om[0], a._n, a._name)
end

function methods.land(self, other)  -- "and" é palavra reservada
    return logical_binop(self, other, C.smaug_bool_and, "and")
end
function methods.lor(self, other)
    return logical_binop(self, other, C.smaug_bool_or, "or")
end
function methods.lxor(self, other)
    return logical_binop(self, other, C.smaug_bool_xor, "xor")
end
function methods.lnot(self)
    local om = new_outmask()
    local r = C.smaug_bool_not(self._vals, self._nulls, self._n, om)
    return own(r, om[0], self._n, self._name)
end

-- Metamétodos: * = AND, + = OR, - = XOR (NÃO há operador unário lógico em Lua,
-- então NOT fica só como :lnot()). Escolha pragmática para ergonomia.
BoolSeries.__mul = function(a, b) return logical_binop(a, b, C.smaug_bool_and, "and") end
BoolSeries.__add = function(a, b) return logical_binop(a, b, C.smaug_bool_or,  "or")  end
BoolSeries.__sub = function(a, b) return logical_binop(a, b, C.smaug_bool_xor, "xor") end

BoolSeries.__len = function(self) return tonumber(self._n) end

BoolSeries.__tostring = function(self)
    local n = tonumber(self._n)
    local parts = {}
    local limit = math.min(n, 10)
    for i = 1, limit do
        local v = self:get(i)
        parts[#parts + 1] = string.format("  [%d] %s", i,
            v == nil and "NA" or tostring(v))
    end
    if n > limit then parts[#parts + 1] = "  ... ("..(n - limit).." mais)" end
    return string.format("BoolSeries '%s' (len=%d, true=%d)\n%s",
        self._name, n, self:count_true(), table.concat(parts, "\n"))
end

BoolSeries.__index = function(self, k)
    if type(k) == "number" then return methods.get(self, k) end
    return methods[k]
end

-- Construtor interno usado por Series:gt/:lt/:eq (que já têm os ponteiros).
BoolSeries._own = own

-- Constrói BoolSeries a partir de arrays Lua puros (sem posse de C).
-- Usado pelos métodos de coluna que produzem novos buffers em Lua.
local function from_lua_arrays(vals_arr, nulls_arr, n, name)
    local sz  = n == 0 and 1 or n
    local vptr = ffi.new("uint8_t[?]", sz)
    local nptr = nulls_arr and ffi.new("uint8_t[?]", sz) or nil
    for i = 0, n - 1 do
        vptr[i] = vals_arr[i + 1] or 0
        if nptr then nptr[i] = nulls_arr[i + 1] or 0x00 end
    end
    -- cast para uint8_t* para que get()/is_null() usem indexação de ponteiro,
    -- consistente com os buffers criados via own/ffi.gc (que são uint8_t*).
    -- O array ffi.new mantém a memória viva enquanto o cdata existir.
    return setmetatable({
        _vals  = ffi.cast("uint8_t*", vptr),
        _nulls = nptr and ffi.cast("uint8_t*", nptr) or nil,
        _n     = n,
        _name  = name or "mask",
        _base  = vptr,   -- ancora o ffi.new para que o GC não colete a memória
        _nbase = nptr,   -- idem para nulls
    }, BoolSeries)
end

-- =====================================================================
-- API de coluna: métodos necessários para BoolSeries ser cidadão
-- completo do DataSet (toda coluna deve implementar este contrato).
-- =====================================================================

-- take(idx): nova BoolSeries com os elementos nos índices dados (1-based).
function methods.take(self, idx)
    local n      = #idx
    local vals   = {}
    local nulls  = nil
    local has_na = false
    for k, i in ipairs(idx) do
        if i < 1 or i > self:len() then
            error("smaug: take: índice " .. i .. " fora dos limites", 2)
        end
        local v = self:get(i)
        vals[k] = (v == true) and 1 or 0
        if v == nil then has_na = true end
    end
    if has_na then
        nulls = {}
        for k, i in ipairs(idx) do
            nulls[k] = self:is_null(i) and 0x00 or 0xFF
        end
    end
    return from_lua_arrays(vals, nulls, n, self._name)
end

-- head/tail: primeiros/últimos n elementos.
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
    for i = total - n + 1, total do idx[#idx + 1] = i end
    return self:take(idx)
end

-- filter(mask): nova BoolSeries com as posições onde mask é true.
function methods.filter(self, mask)
    local idx = {}
    for i = 1, mask:len() do
        if mask:get(i) == true then idx[#idx + 1] = i end
    end
    return self:take(idx)
end

-- dropna: nova BoolSeries sem posições NA.
function methods.dropna(self)
    local idx = {}
    for i = 1, self:len() do
        if not self:is_null(i) then idx[#idx + 1] = i end
    end
    return self:take(idx)
end

-- fillna(value): substitui NA por value (deve ser boolean).
function methods.fillna(self, value)
    if value == nil then
        error("smaug: fillna requer um valor de preenchimento", 2)
    end
    if type(value) ~= "boolean" then
        error("smaug: fillna em BoolSeries espera boolean; recebido "
              .. type(value), 2)
    end
    local n    = self:len()
    local fill = value and 1 or 0
    local vals = {}
    for i = 1, n do
        local v = self:get(i)
        vals[i] = (v == nil) and fill or (v and 1 or 0)
    end
    return from_lua_arrays(vals, nil, n, self._name)  -- nil = sem NAs
end

-- describe: estatísticas de uma coluna booleana.
function methods.describe(self)
    local n     = self:len()
    local nulls = 0
    local trues = 0
    for i = 1, n do
        local v = self:get(i)
        if v == nil   then nulls = nulls + 1
        elseif v      then trues = trues + 1 end
    end
    local count = n - nulls
    return {
        count  = count,
        nulls  = nulls,
        true_  = trues,
        false_ = count - trues,
        freq   = count > 0 and (trues / count) or nil,
    }
end

-- argsort: false < true, NAs retornam nil (consistente com Series).
function methods.argsort(self, ascending)
    if ascending == nil then ascending = true end
    for i = 1, self:len() do
        if self:is_null(i) then return nil end
    end
    local idx = {}
    for i = 1, self:len() do idx[i] = i end
    table.sort(idx, function(a, b)
        local va = self._vals[a - 1] ~= 0
        local vb = self._vals[b - 1] ~= 0
        if va == vb then return a < b end   -- empate: estável por índice
        -- ascending: false(0) < true(1); descending: true(1) < false(0)
        if ascending then
            return (not va) and vb  -- va=false, vb=true → a vem antes
        else
            return va and (not vb)  -- va=true, vb=false → a vem antes
        end
    end)
    return idx
end

-- count_nonnull: alias para compatibilidade com Series na API do DataSet.
function methods.count_nonnull(self)
    local n = self:len()
    if self._nulls == nil then return n end
    local c = 0
    for i = 0, n - 1 do
        if self._nulls[i] == 0xFF then c = c + 1 end
    end
    return c
end

return BoolSeries
