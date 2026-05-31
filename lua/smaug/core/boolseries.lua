-- lua/smaug/core/boolseries.lua
--
-- BoolSeries: resultado de comparações (:gt/:lt/:eq) e máscara de filtragem.
--
-- Diferente de Series (f64/i64), a BoolSeries NÃO encapsula um struct
-- smaug_series_*_t. Ela possui o par de arrays brutos devolvidos pelo backend:
--   * _vals  : uint8_t*       (1 = true, 0 = false)
--   * _nulls : smaug_mask_t*  (0xFF = válido, 0x00 = NA)  -- pode ser nil
--   * _n     : comprimento
-- Ambos os arrays são malloc()ados em C; registramos ffi.gc(ptr, C.free) para
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
    ffi.gc(vals, C.free)
    if nulls ~= nil then ffi.gc(nulls, C.free) end
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

return BoolSeries
