-- Observações para docs/IO_REVIEW.md; não é uma suíte de aprovação.
-- Execute da raiz: luajit scripts/audit_io.lua
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")
local ffi = require("ffi")
local backend = require("smaug.ffi_loader")

local function describe_dataset(dataset)
    local columns = {}
    for column_index, column_name in ipairs(dataset:columns()) do
        local series = dataset:column(column_name)
        local values = {}
        for row_index = 1, series:len() do
            local value = series._dtype == "int64" and not series:is_null(row_index)
                and series:get_raw(row_index) or series:get(row_index)
            values[#values + 1] = type(value) == "string" and string.format("%q", value) or tostring(value)
        end
        columns[column_index] = column_name .. ":" .. series._dtype .. "=[" .. table.concat(values, ",") .. "]"
    end
    return "rows=" .. dataset:nrows() .. " " .. table.concat(columns, " ")
end

local function observe(label, callback)
    local succeeded, result = pcall(callback)
    print(label .. " | " .. (succeeded and tostring(result) or ("ERROR " .. tostring(result))))
end

local json_cases = {
    {"J01 reordered", '[{"a":1,"b":10},{"b":20,"a":2}]'},
    {"J02 missing", '[{"a":1,"b":10},{"b":20}]'},
    {"J03 new key", '[{"a":1},{"a":2,"b":20}]'},
    {"J04 missing closing bracket", '[{"v":1}'},
    {"J05 trailing content", '[{"v":1}]garbage'},
    {"J06 missing comma", '[{"v":1}{"v":2}]'},
    {"J07 trailing comma", '[{"v":1},]'},
    {"J08 invalid escape", '[{"v":"a\\q"}]'},
    {"J09 embedded NUL", '[{"v":"a\\u0000b"}]'},
    {"J10 leading zero", '[{"v":01}]'},
    {"J11 incomplete decimal", '[{"v":1.}]'},
    {"J12 int64 overflow", '[{"v":9223372036854775808}]'},
    {"J13 exact int64", '[{"v":9007199254740993}]'},
    {"J14 duplicate key", '[{"v":1,"v":2}]'},
    {"J15 nested value", '[{"v":{"x":1}}]'},
    {"J16 unicode pair", '[{"v":"\\uD83D\\uDE00"}]'},
    {"J17 literal control", '[{"v":"a\nb"}]'},
}
for case_index, entry in ipairs(json_cases) do
    observe(entry[1], function() return describe_dataset(smaug.read_json_mem(entry[2])) end)
end
local csv_cases = {
    {"C01 extra field", "a,b\n1,2,3\n"},
    {"C02 missing field", "a,b\n1\n"},
    {"C03 unclosed quote", 'v\n"abc'},
    {"C04 after quote", 'v\n"a"x\n'},
    {"C05 embedded NUL", "v\na\0b\n"},
    {"C06 exact int64", "v\n9007199254740993\n"},
    {"C07 duplicate header", "v,v\n1,2\n"},
    {"C08 multiline", 'v\n"a\nb"\n'},
    {"C09 quoted NA", 'v\n"NA"\n'},
    {"C10 mixed", "v\ntrue\n1\n"},
}
for case_index, entry in ipairs(csv_cases) do
    observe(entry[1], function() return describe_dataset(smaug.read_csv_mem(entry[2])) end)
end
for case_index, format_name in ipairs({"csv", "json"}) do
    observe("B01 exact int64 C " .. format_name, function()
        local source = format_name == "csv" and "v\n9007199254740993\n" or '[{"v":9007199254740993}]'
        local table_pointer = format_name == "csv"
            and backend.smaug_read_csv_mem(source, #source, nil)
            or backend.smaug_read_json_mem(source, #source)
        assert(table_pointer ~= nil)
        table_pointer = ffi.gc(table_pointer, backend.smaug_table_free)
        assert(table_pointer.error == nil)
        local status = ffi.new("smaug_status_t[1]")
        local value = backend.smaug_i64_get(table_pointer.columns[0].i64, 0, status)
        return tostring(value) .. " status=" .. tonumber(status[0])
    end)
end
observe("W01 JSON NUL roundtrip", function()
    local dataset = smaug.DataSet({{"v", {"a\0b"}, "string"}})
    local encoded = dataset:to_json_mem()
    return string.format("%q", encoded) .. " -> " .. describe_dataset(smaug.read_json_mem(encoded))
end)
