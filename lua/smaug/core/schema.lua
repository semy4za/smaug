-- Immutable reusable schema description; import policy belongs to the readers.
local ffi = require("ffi")
local C = require("smaug.ffi_loader")

local Schema = {}
local states = setmetatable({}, { __mode = "k" })
local prototype = newproxy(true)
local metatable = getmetatable(prototype)
metatable.__metatable = "smaug.Schema"
metatable.__newindex = function()
    error("smaug: Schema é imutável", 2)
end
metatable.__tostring = function(object)
    return "smaug.Schema(" .. states[object].count .. " campos)"
end

local dtype_codes = {
    bool = C.SMAUG_DTYPE_BOOL, int64 = C.SMAUG_DTYPE_INT64,
    float64 = C.SMAUG_DTYPE_FLOAT64, string = C.SMAUG_DTYPE_STRING,
}
local allowed_properties = { name = true, dtype = true, nullable = true }

local function capability(symbol)
    local succeeded, operation = pcall(function() return C[symbol] end)
    if not succeeded then
        error("smaug: biblioteca sem suporte a Schema; recompile biblioteca e frontend", 3)
    end
    return operation
end

local function create(fields)
    if type(fields) ~= "table" or getmetatable(fields) ~= nil then
        error("smaug: Schema espera sequência simples de campos", 2)
    end
    local count = 0
    local maximum = 0
    for key in pairs(fields) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            error("smaug: Schema exige índices inteiros consecutivos a partir de 1", 2)
        end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    if count == 0 or count ~= maximum then
        error("smaug: Schema exige campos, sem buracos na sequência", 2)
    end
    local validate = capability("smaug_schema_validate")
    local descriptors = ffi.new("smaug_schema_field_t[?]", count)
    local names = {}
    local used_names = {}
    for field_index = 1, count do
        local field = fields[field_index]
        if type(field) ~= "table" or getmetatable(field) ~= nil then
            error("smaug: Schema campo " .. field_index .. " deve ser tabela simples", 2)
        end
        for key in pairs(field) do
            if not allowed_properties[key] then
                error("smaug: Schema propriedade desconhecida: " .. tostring(key), 2)
            end
        end
        if type(field.name) ~= "string" or type(field.dtype) ~= "string"
            or dtype_codes[field.dtype] == nil or type(field.nullable) ~= "boolean" then
            error("smaug: Schema campo " .. field_index
                .. " exige name string, dtype válido e nullable booleano", 2)
        end
        if used_names[field.name] then
            error("smaug: Schema nome duplicado no campo " .. field_index, 2)
        end
        used_names[field.name] = true
        names[field_index] = field.name
        descriptors[field_index - 1].name = names[field_index]
        descriptors[field_index - 1].name_len = #names[field_index]
        descriptors[field_index - 1].dtype = dtype_codes[field.dtype]
        descriptors[field_index - 1].nullable = field.nullable and 1 or 0
    end
    local descriptor = ffi.new("smaug_schema_t")
    descriptor.fields = descriptors
    descriptor.count = count
    if validate(descriptor, nil) ~= 0 then
        error("smaug: Schema descritor C inválido", 2)
    end
    local object = newproxy(prototype)
    states[object] = { descriptor = descriptor, fields = descriptors, names = names, count = count }
    return object
end

-- Internal adapter. Return the owners as well as the borrowed descriptor;
-- callers keep the anchor reachable until the C call has returned.
function Schema._borrow(object, symbol)
    local state = states[object]
    if state == nil then
        error("smaug: schema espera um objeto smaug.Schema", 3)
    end
    return state.descriptor, state, capability(symbol)
end

return setmetatable(Schema, { __call = function(unused_class, fields) return create(fields) end })
