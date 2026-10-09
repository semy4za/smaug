-- Observational study of dtype API design; this is not a pass/fail test suite.
-- Run from the repository root: luajit scripts/audit_dtype_api.lua
-- Each JSON line records a returned value or a caught Lua error, not approval.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require("ffi")
local original_load = ffi.load
local loaded_paths = {}
ffi.load = function(path, ...)
    local library = original_load(path, ...)
    loaded_paths[#loaded_paths + 1] = path
    return library
end
local smaug = require("smaug")
ffi.load = original_load

local function quote_json(value)
    local escaped = tostring(value):gsub('[%z\1-\31\\"]', function(character)
        if character == '"' then return '\\"' end
        if character == '\\' then return '\\\\' end
        return string.format('\\u%04x', string.byte(character))
    end)
    return '"' .. escaped .. '"'
end

local function emit(case_id, status, detail)
    print('{"id":' .. quote_json(case_id) .. ',"status":' .. quote_json(status)
        .. ',"detail":' .. quote_json(detail) .. '}')
end

local function describe_series(series)
    local values = {}
    for row_index = 1, series:len() do
        if series:is_null(row_index) then
            values[#values + 1] = "NA"
        elseif series._dtype == "int64" then
            values[#values + 1] = tostring(series:get_raw(row_index))
        elseif series._dtype == "string" then
            values[#values + 1] = string.format("%q", series:get(row_index))
        else
            values[#values + 1] = tostring(series:get(row_index))
        end
    end
    return series._dtype .. " len=" .. series:len() .. " name=" .. tostring(series._name)
        .. " values=[" .. table.concat(values, ",") .. "]"
end

local function describe_dataset(dataset)
    local columns = {}
    for unused_index, column_name in ipairs(dataset:columns()) do
        columns[#columns + 1] = column_name .. ":" .. describe_series(dataset[column_name])
    end
    return "rows=" .. dataset:nrows() .. " columns=[" .. table.concat(columns, ";") .. "]"
end

local function observe(case_id, operation)
    local succeeded, result = pcall(operation)
    emit(case_id, succeeded and "returned" or "error", result)
end

local function series_case(case_id, values, dtype, name)
    observe(case_id, function() return describe_series(smaug.Series(values, dtype, name)) end)
end

emit("environment", "observed", ffi.os .. " " .. ffi.arch .. " " .. jit.version
    .. " library=" .. table.concat(loaded_paths, ","))
series_case("S01_bool_inferred", {true, false})
series_case("S02_integer_inferred", {1, 2, 3})
series_case("S03_decimal_spelling", {1.0, 2.0})
series_case("S04_float_explicit", {1, 2}, "float64")
series_case("S05_empty_inferred", {})
series_case("S06_empty_bool", {}, "bool")
series_case("S07_all_na_inferred", {smaug.NA, smaug.NA})
series_case("S08_all_na_bool", {smaug.NA, smaug.NA}, "bool")
series_case("S09_name_only", {true, false}, nil, "active")
series_case("S10_invalid_dtype", {1, 2}, "invalid")
series_case("S11_false_dtype", {1, 2}, false)
series_case("S12_numeric_promotion", {1, 2.5})
series_case("S13_mixed_families", {1, "2"})
series_case("S14_fraction_as_integer", {1.5}, "int64")
local precise_integer = ffi.new("int64_t", 9007199254740993LL)
series_case("S15_cdata_inferred", {precise_integer})
series_case("S16_cdata_explicit", {precise_integer}, "int64")
series_case("S17_identifiers", {"00123", "00456"})
series_case("S18_options_not_supported", {1, 2}, {dtype = "float64"})
observe("S19_descriptor_not_supported", function()
    return describe_series(smaug.Series{data = {1, 2}, dtype = "float64"})
end)
observe("S20_metadata_inside_data", function()
    return describe_series(smaug.Series{1, 2, dtype = "float64"})
end)
observe("D01_positional_dtype", function()
    return describe_dataset(smaug.DataSet({{"price", {1, 2}, "float64"}}))
end)
observe("D02_named_dtype_not_supported", function()
    return describe_dataset(smaug.DataSet({{"price", {1, 2}, dtype = "float64"}}))
end)
observe("D03_named_typo_not_supported", function()
    return describe_dataset(smaug.DataSet({{"price", {1, 2}, dytpe = "float64"}}))
end)
observe("D04_typed_series_conflict", function()
    local quantity_series = smaug.Series({1, 2})
    return describe_dataset(smaug.DataSet({{"quantity", quantity_series, "float64"}}))
end)
observe("D05_typed_series_invalid_dtype", function()
    local quantity_series = smaug.Series({1, 2})
    return describe_dataset(smaug.DataSet({{"quantity", quantity_series, "invalid"}}))
end)
observe("D06_duplicate_column", function()
    return describe_dataset(smaug.DataSet({{"quantity", {1}}, {"quantity", {2}}}))
end)
observe("D07_misaligned_columns", function()
    return describe_dataset(smaug.DataSet({{"quantity", {1, 2}}, {"price", {3}}}))
end)
observe("D08_names_are_data", function()
    return describe_dataset(smaug.DataSet({{"dtype", {1}}, {"name", {"item"}},
        {"data", {true}}, {"schema", {"v1"}}}))
end)
local code_schema = smaug.Schema({{name = "code", dtype = "string", nullable = false}})
local active_schema = smaug.Schema({{name = "active", dtype = "bool", nullable = true}})
observe("I01_csv_inferred", function()
    return describe_dataset(smaug.read_csv_mem("code\n00123\n00456\n"))
end)
observe("I02_csv_schema", function()
    return describe_dataset(smaug.read_csv_mem("code\n00123\n00456\n", {schema = code_schema}))
end)
observe("I03_json_all_na_schema", function()
    return describe_dataset(smaug.read_json_mem('[{}, {"active":null}]', {schema = active_schema}))
end)
observe("I04_empty_json_schema", function()
    return describe_dataset(smaug.read_json_mem("[]", {schema = active_schema}))
end)
observe("I05_nullable_not_tolerant", function()
    return describe_dataset(smaug.read_json_mem('[{"active":"invalid"}]', {schema = active_schema}))
end)
observe("I06_schema_typo", function()
    return tostring(smaug.Schema({{name = "active", dytpe = "bool", nullable = true}}))
end)
observe("I07_dataset_schema_not_supported", function()
    local dataset = smaug.DataSet({{"active", {smaug.NA, smaug.NA}}}, {schema = active_schema})
    return describe_dataset(dataset) .. " dataset_name_type=" .. type(dataset._name)
end)
observe("F01_full_cdata_inferred", function()
    return describe_series(smaug.Series.full(2, precise_integer))
end)
observe("F02_full_cdata_explicit", function()
    return describe_series(smaug.Series.full(2, precise_integer, "int64"))
end)
observe("F03_map_first_result", function()
    return describe_series(smaug.Series({1, 2}):map(function(value)
        if value == 1 then return 1 end
        return 2.5
    end))
end)
observe("F04_map_all_na", function()
    return describe_series(smaug.Series({1, 2}):map(function(unused_value) return smaug.NA end))
end)
observe("F05_map_all_na_explicit", function()
    local result_series = smaug.Series({1, 2}):map(function(unused_value)
        return smaug.NA
    end, "bool")
    return describe_series(result_series)
end)

-- Existing repository fixture: report shape/types only, without customer data.
local function describe_orders(dataset)
    return "rows=" .. dataset:nrows() .. " cols=" .. dataset:ncols()
        .. " order=" .. dataset["N_PEDIDO_SAP"]._dtype
        .. " quantity=" .. dataset["(un)"]._dtype
        .. " amount=" .. dataset["(R$)"]._dtype
        .. " date=" .. dataset["DATA_CRIACAO"]._dtype
end
observe("W01_orders_inferred", function()
    return describe_orders(smaug.read_csv("tests/fixtures/pedidos_digitados.csv", {sep = ";"}))
end)
local order_fields = {}
for unused_index, column_name in ipairs({"MES_COMP", "DATA_CRIACAO", "Empresa",
    "N_PEDIDO_SAP", "cl_comercial", "subcanal", "grupo/cliente", "cliente",
    "tp_produto", "linha", "tp_sku", "produto", "(un)", "(R$)", "motivo_recusa"}) do
    local dtype = "string"
    if column_name == "(un)" then dtype = "int64" end
    if column_name == "(R$)" then dtype = "float64" end
    order_fields[#order_fields + 1] = {name = column_name, dtype = dtype, nullable = true}
end
local order_schema = smaug.Schema(order_fields)
observe("W02_orders_schema", function()
    local dataset = smaug.read_csv("tests/fixtures/pedidos_digitados.csv",
        {sep = ";", decimal = ",", schema = order_schema})
    return describe_orders(dataset)
end)
observe("W03_orders_reusable_pipeline", function()
    local dataset = smaug.read_csv("tests/fixtures/pedidos_digitados.csv",
        {sep = ";", decimal = ",", schema = order_schema})
    dataset["reviewed"] = smaug.Series.new("bool", dataset:nrows(), "reviewed")
    local summarized = smaug.DataSet({
        {"order_code", dataset["N_PEDIDO_SAP"]},
        {"quantity", dataset["(un)"]},
        {"reviewed", dataset["reviewed"]},
    }, "orders_for_review")
    return "rows=" .. summarized:nrows() .. " cols=" .. summarized:ncols()
        .. " code=" .. summarized["order_code"]._dtype
        .. " reviewed=" .. summarized["reviewed"]._dtype
        .. " first_review_is_na=" .. tostring(summarized["reviewed"]:is_null(1))
end)
