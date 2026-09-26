-- Observação de preservação de valores; código 0 não certifica correção.
-- Execute da raiz: luajit scripts/audit_io_values.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require("ffi")
local smaug = require("smaug")
local backend = require("smaug.ffi_loader")

-- Sondagem das primitivas públicas usadas internamente pelo C; não adiciona
-- dependência de produção no frontend nem altera seu cdef permanente.
ffi.cdef[[
    int smaug_parse_i64(const char *source, size_t length, int64_t *output);
    int smaug_parse_f64(const char *source, size_t length, double *output);
]]

local function describe(value)
    if type(value) == "string" then
        return string.format("%q", value) .. " bytes=" .. #value
    end
    if type(value) == "number" then return string.format("%.17g", value) end
    return tostring(value)
end

local csv_cases = {
    {"csv_nul", "\0"},
    {"csv_integer_prefix", "123\0abc"},
    {"csv_float_prefix", "1.5\0abc"},
    {"csv_bool_prefix", "true\0abc"},
    {"csv_na_prefix", "NA\0xyz"},
    {"csv_null_prefix", "null\0xyz"},
    {"csv_nan_prefix", "nan\0xyz"},
    {"csv_nul_no_na", "\0", {na_values = {}}},
    {"csv_custom_exact", "NA\0xyz", {na_values = {"NA\0xyz"}}},
    {"csv_custom_prefix", "NA", {na_values = {"NA\0xyz"}}},
    {"csv_custom_other_suffix", "NA\0other", {na_values = {"NA\0xyz"}}},
}
for case_index, entry in ipairs(csv_cases) do
    local source = "v\n" .. entry[2] .. "\n"
    local succeeded, result = pcall(function()
        local series = smaug.read_csv_mem(source, entry[3]):column("v")
        local value = series._dtype == "int64" and series:get_raw(1) or series:get(1)
        return series._dtype .. " null=" .. tostring(series:is_null(1)) .. " value=" .. describe(value)
    end)
    print(entry[1] .. " | " .. (succeeded and result or "ERROR " .. result))
end

local cases = {
    {"nul", '"a\\u0000b"'},
    {"i53", "9007199254740993"},
    {"imax", "9223372036854775807"},
    {"overflow", "9223372036854775808"},
    {"underflow_i64", "-9223372036854775809"},
    {"float_overflow", "1e400"},
    {"float_underflow", "1e-400"},
    {"long_token", "1" .. string.rep("0", 63) .. "e-63"},
}
print(jit.version .. " / " .. ffi.os .. " / " .. ffi.arch)
for case_index, entry in ipairs(cases) do
    local source = '[{"v":' .. entry[2] .. '}]'
    local pointer = backend.smaug_read_json_mem(source, #source)
    local result = "NULL"
    if pointer ~= nil then
        if pointer.error ~= nil then
            result = "ERROR " .. ffi.string(pointer.error)
        else
            local column = pointer.columns[0]
            local dtype = ffi.string(column.dtype)
            local status = ffi.new("smaug_status_t[1]")
            local value
            if dtype == "int64" then
                value = backend.smaug_i64_get(column.i64, 0, status)
            elseif dtype == "float64" then
                value = backend.smaug_f64_get(column.f64, 0, status)
            else
                local length = ffi.new("size_t[1]")
                local data = backend.smaug_str_get(column.str, 0, length)
                value = data ~= nil and ffi.string(data, length[0]) or nil
            end
            result = dtype .. " " .. describe(value)
        end
        backend.smaug_table_free(pointer)
    end
    local succeeded, value = pcall(function()
        local series = smaug.read_json_mem(source):column("v")
        return describe(series._dtype == "int64" and series:get_raw(1) or series:get(1))
    end)
    print(entry[1] .. " | C=" .. result .. " | Lua=" .. (succeeded and value or "ERROR " .. value))
end

local core_cases = {"123\0abc", "1.5\0abc", " \0abc", "1" .. string.rep("0", 63) .. "e-63"}
for case_index, source in ipairs(core_cases) do
    local integer_output = ffi.new("int64_t[1]", 77)
    local float_output = ffi.new("double[1]", 77)
    local integer_status = backend.smaug_parse_i64(source, #source, integer_output)
    local float_status = backend.smaug_parse_f64(source, #source, float_output)
    local series = smaug.Series({source}, "string")
    print("core_" .. case_index .. " | input=" .. describe(source)
        .. " | i64=" .. integer_status .. ":" .. tostring(integer_output[0])
        .. " | f64=" .. float_status .. ":" .. describe(float_output[0])
        .. " | astype_i64=" .. describe(series:astype("int64"):get_raw(1))
        .. " | astype_f64=" .. describe(series:astype("float64"):get(1)))
end
