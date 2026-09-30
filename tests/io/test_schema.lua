package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local smaug = require("smaug")
local ffi = require("ffi")
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end
local function fails(operation, reason)
    local succeeded, message = pcall(operation)
    check(not succeeded and tostring(message):find(reason, 1, true),
          "expected " .. reason .. ", got " .. tostring(message))
end
local source_fields = {
    { name = "code", dtype = "string", nullable = false },
    { name = "quantity", dtype = "int64", nullable = true },
    { name = "active", dtype = "bool", nullable = true },
    { name = "price", dtype = "float64", nullable = true },
}
local schema = smaug.Schema(source_fields)
source_fields[1].name = "changed"
source_fields[2].dtype = "string"
collectgarbage("collect")
local json = '[{"price":1.5,"active":false,"quantity":9223372036854775807,"code":"00123"},'
    .. '{"code":"00234"}]'
local csv = "price,active,quantity,code\n1.5,false,9223372036854775807,00123\n,,,00234\n"
local function check_dataset(dataset)
    check(dataset:nrows() == 2 and dataset:ncols() == 4, "schema shape")
    check(dataset._col_names[1] == "code" and dataset._col_names[4] == "price", "schema order")
    check(dataset["code"]:get(1) == "00123", "schema leading zeros")
    check(dataset["quantity"]:get_raw(1) == ffi.new("int64_t", 9223372036854775807LL),
          "schema exact int64")
    check(dataset["active"]:get(1) == false, "schema false preserved")
    check(dataset["price"]:get(1) == 1.5, "schema float preserved")
    check(dataset["quantity"]:is_null(2) and dataset["active"]:is_null(2), "schema NA")
end
check_dataset(smaug.read_csv_mem(csv, { schema = schema }))
check_dataset(smaug.read_json_mem(json, { schema = schema }))
fails(function() schema.fields = {} end, "imutável")

for unused_index, empty in ipairs({
    smaug.read_csv_mem("code,quantity,active,price\n", { schema = schema }),
    smaug.read_json_mem("[]", { schema = schema }),
}) do
    check(empty:nrows() == 0 and empty:ncols() == 4, "schema empty columns")
    check(empty["quantity"]._dtype == "int64" and empty["active"]._dtype == "bool",
          "schema empty dtypes")
end
local bool_schema = smaug.Schema({ { name = "flag", dtype = "bool", nullable = true } })
local nulls = smaug.read_json_mem('[{}, {"flag":null}]', { schema = bool_schema })
check(nulls["flag"]._dtype == "bool" and nulls["flag"]:is_null(1), "schema all NA bool")

local invalid_fields = {
    {},
    { [2] = { name = "code", dtype = "string", nullable = false } },
    { { name = "code", dtype = "invalid", nullable = false } },
    { { name = "code", dtype = "string" } },
    { { name = "code", dtype = "string", nullable = 1 } },
    { { name = "code", dtype = "string", nullable = true, default = "value" } },
    { { name = "same", dtype = "string", nullable = true },
      { name = "same", dtype = "int64", nullable = true } },
}
for unused_index, fields in ipairs(invalid_fields) do
    fails(function() smaug.Schema(fields) end, "Schema")
end
fails(function() smaug.Schema(false) end, "Schema")
fails(function() smaug.read_csv_mem(csv, { schema = {} }) end, "smaug.Schema")
fails(function() smaug.read_json_mem(json, { schema = false }) end, "smaug.Schema")
fails(function() smaug.read_csv_mem(csv, false) end, "opts")
fails(function() smaug.read_json_mem(json, false) end, "opts")
fails(function() smaug.read_json_mem(json, { tolerant = true }) end, "opção desconhecida")
fails(function() smaug.read_json_mem('[{"code":"x","quantity":"123"}]', { schema = schema })
    end, "column 2 expected int64")
fails(function() smaug.read_csv_mem("code,quantity,active,price\nx,bad,true,1\n", { schema = schema })
    end, "record 1 column 2 expected int64")
fails(function() smaug.read_json_mem('[{"code":"x","price":9007199254740993}]', { schema = schema })
    end, "PRECISION")
fails(function() smaug.read_json_mem('[{"code":null}]', { schema = schema }) end, "non-nullable")
fails(function() smaug.read_json_mem('[{"code":"x","extra":1}]', { schema = schema })
    end, "unknown field")
fails(function() smaug.read_csv_mem("code,code,active,price\nx,y,true,1", { schema = schema })
    end, "duplicate")

local byte_schema = smaug.Schema({ { name = "id\0tail", dtype = "string", nullable = false } })
local bytes = smaug.read_csv_mem("id\0tail\n001\0tail\n", { schema = byte_schema })
check(bytes["id\0tail"]:get(1) == "001\0tail", "CSV schema NUL name and value")
bytes = smaug.read_json_mem('[{"id\\u0000tail":"001\\u0000tail"}]', { schema = byte_schema })
check(bytes["id\0tail"]:get(1) == "001\0tail", "JSON schema NUL name and value")
local no_header = smaug.read_csv_mem("00123;42;true;2,5", {
    schema = schema, header = false, sep = ";", decimal = ",",
})
check(no_header["code"]:get(1) == "00123" and no_header["price"]:get(1) == 2.5,
      "headerless schema CSV with decimal option")
local marker_schema = smaug.Schema({ { name = "text", dtype = "string", nullable = true } })
local markers = smaug.read_csv_mem("text\nN\0A\n", { schema = marker_schema, na_values = { "N\0A" } })
check(markers["text"]:is_null(1), "schema keeps custom NA byte lengths")
local literal_na = smaug.read_csv_mem("text\nNA\n", { schema = marker_schema, na_values = {} })
check(literal_na["text"]:get(1) == "NA", "schema permits disabled NA markers")

-- File APIs exercise the same contract, including a growing input buffer.
local path = os.tmpname()
for unused_index, sample in ipairs({ { csv, smaug.read_csv }, { json, smaug.read_json } }) do
    local file = assert(io.open(path, "wb"))
    assert(file:write(sample[1]))
    assert(file:close())
    check_dataset(sample[2](path, { schema = schema }))
end
local file = assert(io.open(path, "wb"))
assert(file:write('[{"text":"' .. string.rep("x", 10000) .. '"}]'))
assert(file:close())
local large = smaug.read_json(path, { schema = marker_schema })
check(large["text"]:get(1) == string.rep("x", 10000), "schema file grows without truncating")
assert(os.remove(path))
fails(function() smaug.read_csv(path, { schema = schema }) end, "open failed")
fails(function() smaug.read_json(path, { schema = schema }) end, "open failed")
fails(function() smaug.read_json(path .. "\0ignored", { schema = schema }) end, "NUL")

-- Temporary schema remains alive through conversion and collection.
for iteration = 1, 20 do
    local dataset = smaug.read_json_mem('[{"value":false}]', { schema = smaug.Schema({
        { name = "value", dtype = "bool", nullable = false },
    }) })
    collectgarbage("collect")
    check(dataset["value"]:get(1) == false, "temporary schema lifetime")
end
print("OK — " .. checks .. " checks passaram (schema reutilizável CSV/JSON)")
