-- Probes independentes por eixo, executados contra uma biblioteca recem-compilada.
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local protocol = dofile(arg[2] .. "/scripts/parity/protocol.lua")
local smaug = require("smaug")
local ffi = require("ffi")
local library = require("smaug.ffi_loader")
local axis = assert(tonumber(arg[1]))
local dtypes = {"float64", "int64", "bool", "string", "datetime", "categorical"}

local function library_path()
    if ffi.os == "Windows" then
        ffi.cdef[[
            int __stdcall GetModuleHandleExA(unsigned long, const char *, void **);
            unsigned long __stdcall GetModuleFileNameA(void *, char *, unsigned long);
        ]]
        local kernel = ffi.load("kernel32")
        local module = ffi.new("void *[1]")
        local address = ffi.cast("const char *", library.smaug_abi_version)
        assert(kernel.GetModuleHandleExA(6, address, module) ~= 0)
        local buffer = ffi.new("char[32768]")
        local length = kernel.GetModuleFileNameA(module[0], buffer, 32768)
        assert(length > 0 and length < 32768)
        return ffi.string(buffer, length)
    end
    ffi.cdef[[
        typedef struct {
            const char *dli_fname; void *dli_fbase;
            const char *dli_sname; void *dli_saddr;
        } parity_dl_info;
        int dladdr(const void *, parity_dl_info *);
    ]]
    local info = ffi.new("parity_dl_info[1]")
    local dynamic_loader = ffi.load("dl")
    assert(dynamic_loader.dladdr(ffi.cast("const void *", library.smaug_abi_version), info) ~= 0)
    return ffi.string(info[0].dli_fname)
end

protocol.result("library", "OBSERVED", "Loaded library identity", library_path())
assert(library.smaug_abi_version() == 1, "ABI version must be 1")

local function fixture(dtype)
    if dtype == "bool" then
        return smaug.Series({true, smaug.NA, false}, dtype), {true, smaug.NA, false}
    elseif dtype == "string" or dtype == "categorical" then
        return smaug.Series({"b", smaug.NA, "a"}, dtype), {"b", smaug.NA, "a"}
    end
    return smaug.Series({3, smaug.NA, 1}, dtype), {3, smaug.NA, 1}
end

local function expect_series(actual, dtype, values)
    assert(actual._dtype == dtype, "dtype: expected " .. dtype)
    assert(actual:len() == #values, "length mismatch")
    for row_index, expected in ipairs(values) do
        if expected == smaug.NA then
            assert(actual:is_null(row_index), "missing mask at " .. row_index)
        else
            assert(not actual:is_null(row_index), "unexpected NA at " .. row_index)
            local value = dtype == "int64" and actual:get_raw(row_index)
                or actual:get(row_index)
            assert(value == expected, "value mismatch at " .. row_index)
        end
    end
end

-- Inspecao somente leitura da tabela de metodos efetivamente carregada.
local function methods_of(object)
    local metatable = assert(getmetatable(object), "missing metatable")
    if type(metatable.__index) == "table" then
        return metatable.__index
    end
    if type(metatable.__index) == "function" then
        for index = 1, 100 do
            local name, value = debug.getupvalue(metatable.__index, index)
            if not name then break end
            if name == "methods" and type(value) == "table" then return value end
        end
    end
    error("cannot enumerate runtime methods")
end

local function method_names(object)
    local names = {}
    for name, value in pairs(methods_of(object)) do
        if type(name) == "string" and name:sub(1, 1) ~= "_" and type(value) == "function" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    assert(#names > 0, "empty runtime method inventory")
    return names
end

local function inventory(label, object)
    for unused_index, name in ipairs(method_names(object)) do
        protocol.result(label .. "." .. name, "OBSERVED", label .. ":" .. name,
            "Function found in loaded method table", "Presence does not prove dtype support")
    end
end

local checks = {}
checks[1] = function()
    for unused_index, dtype in ipairs(dtypes) do
        local source, expected = fixture(dtype)
        protocol.check(dtype .. ".values", "Constructor preserves dtype, order, values and NA",
            function() expect_series(source, dtype, expected) end)
        protocol.check(dtype .. ".clone.values", "clone preserves the complete series",
            function() expect_series(source:clone(), dtype, expected) end)
        protocol.check(dtype .. ".take.values", "take preserves order and missing mask",
            function() expect_series(source:take({3, 2, 1}), dtype,
                {expected[3], smaug.NA, expected[1]}) end)
    end
    protocol.result("scope", "REVIEW", "Remaining method/dtype combinations",
        "Runtime inventory includes aliases and generated methods",
        "Only named executable cases above certify behavior; no inferred support from source text")
end

checks[2] = function()
    local source = smaug.Series({3, 2, 1}, "int64")
    local dataset = smaug.DataSet({{"value", {3, 2, 1}, "int64"}})
    inventory("Series", source)
    inventory("DataSet", dataset)
    protocol.check("head", "Series/DataSet head select the same rows", function()
        expect_series(source:head(2), "int64", {3, 2})
        local result = dataset:head(2)
        assert(result:nrows() == 2 and result:ncols() == 1)
        expect_series(result:col("value"), "int64", {3, 2})
    end)
    protocol.check("dimensions", "len/nrows and ncols have distinct dimensional contracts",
        function() assert(source:len() == dataset:nrows() and dataset:ncols() == 1) end)
    protocol.result("asymmetry", "REVIEW", "Series/DataSet asymmetries",
        "Full runtime inventories above; historical decisions listed by the runner",
        "A missing peer is not automatically a defect; 1D and 2D contracts differ")
end

checks[3] = function()
    local stream = assert(io.open(arg[3], "r"))
    for symbol in stream:lines() do
        protocol.check("symbol." .. symbol, "FFI symbol exported: " .. symbol, function()
            assert(type(library[symbol]) == "cdata", "symbol unavailable")
        end, "Symbol lookup only; signature checks are compiled separately")
    end
    assert(stream:close())
end

checks[4] = function()
    for unused_index, dtype in ipairs(dtypes) do
        protocol.check(dtype .. ".groupby", "groupby preserves key dtype and exact sums", function()
            local values = (dtype == "string" or dtype == "categorical") and {"b", "a", "b"}
                or (dtype == "bool" and {true, false, true} or {2, 1, 2})
            local dataset = smaug.DataSet({{"key", values, dtype},
                {"value", {3, 4, 5}, "int64"}})
            local grouped = dataset:groupby("key"):sum("value")
            assert(grouped:nrows() == 2 and grouped:ncols() == 2)
            local expected_keys = (dtype == "string" or dtype == "categorical") and {"a", "b"}
                or (dtype == "bool" and {false, true} or {1, 2})
            expect_series(grouped:col("key"), dtype, expected_keys)
            expect_series(grouped:col("value"), "int64", {4, 8})
        end, "Complete keys; does not decide count/pivot defaults or composite join")
    end
    protocol.result("open-contracts", "REVIEW", "Relational contracts awaiting decision",
        "docs/Roadmap.md R7: count, pivot_table default, composite join syntax",
        "No new policy is chosen by the parity checker")
end

checks[5] = function()
    local fixtures = {
        float64 = {1.5, smaug.NA, -2.25},
        int64 = {9007199254740993LL, smaug.NA, -9223372036854775807LL - 1LL},
        bool = {false, smaug.NA, true}, string = {"a\0b", smaug.NA, "NA"},
    }
    for unused_format, format in ipairs({"csv", "json"}) do
        for unused_index, dtype in ipairs({"float64", "int64", "bool", "string"}) do
            protocol.check(format .. "." .. dtype, "I/O preserves complete column with schema",
                function()
                    local values = fixtures[dtype]
                    local source = smaug.DataSet({{"value", values, dtype},
                        {"keep", {1, 1, 1}, "int64"}})
                    local schema = smaug.Schema({
                        {name = "value", dtype = dtype, nullable = true},
                        {name = "keep", dtype = "int64", nullable = false},
                    })
                    local document = source["to_" .. format .. "_mem"](source)
                    local options = {schema = schema}
                    if format == "csv" then options.na_values = {""} end
                    local result = smaug["read_" .. format .. "_mem"](document, options)
                    assert(result:nrows() == 3 and result:ncols() == 2)
                    expect_series(result:col("value"), dtype, values)
                    expect_series(result:col("keep"), "int64", {1, 1, 1})
                end, "Roundtrip plus independent expected values; memory/schema only")
        end
    end
    for unused_index, dtype in ipairs({"datetime", "categorical"}) do
        protocol.check("schema.rejects." .. dtype, "Schema rejects unsupported dtype " .. dtype,
            function()
                local succeeded, message = pcall(smaug.Schema,
                    {{name = "value", dtype = dtype, nullable = true}})
                assert(not succeeded and tostring(message):find("dtype", 1, true))
            end, "CONTRACT.md: complete schema supports bool/int64/float64/string")
    end
end

checks[6] = function()
    local source = smaug.Series({3, 1, 3}, "int64")
    for unused_index, operation in ipairs({"eq", "ne", "lt", "le", "gt", "ge"}) do
        local expected = {eq = {true, false, true}, ne = {false, true, false},
            lt = {false, true, false}, le = {true, true, true},
            gt = {false, false, false}, ge = {true, false, true}}
        protocol.check(operation, "Comparison returns Series<bool> with expected values", function()
            expect_series(source[operation](source, 3), "bool", expected[operation])
        end)
    end
    protocol.check("isna", "isna/notna(index) return scalar booleans", function()
        local nullable = fixture("int64")
        assert(nullable:isna(2) == true and nullable:notna(2) == false)
        assert(nullable:isna(1) == false and nullable:notna(1) == true)
    end)
    protocol.check("int64.value_counts", "value_counts returns DataSet", function()
            local result = smaug.Series({3, 1, 3}, "int64"):value_counts()
            assert(result:nrows() == 2 and result:ncols() == 2)
        end, "Shape/type only; frequencies are covered by family tests")
    protocol.check("categorical.value_counts", "value_counts returns its documented table contract", function()
            local result = smaug.Series({"b", "a", "b"}, "categorical"):value_counts()
            assert(type(result) == "table" and type(result.value) == "table" and type(result.count) == "table")
            assert(result.value[1] == "b" and result.value[2] == "a")
            assert(result.count[1] == 2 and result.count[2] == 1)
        end, "CategoricalSeries intentionally returns {value = ..., count = ...} to avoid a dependency cycle")
    protocol.check("argsort", "argsort returns 1-based index table", function()
        local result = smaug.Series({3, 1, 2}, "int64"):argsort()
        assert(type(result) == "table" and #result == 3)
        assert(result[1] == 2 and result[2] == 3 and result[3] == 1)
    end)
    protocol.result("scope", "REVIEW", "Other return contracts", "Selected methods executed",
        "No classification of return type by searching return statements")
end

checks[7] = function()
    for unused_index, dtype in ipairs(dtypes) do
        protocol.check(dtype .. ".mask", "NA differs from valid false/zero/text", function()
            local source, values = fixture(dtype)
            expect_series(source, dtype, values)
            assert(source:isna(2) and not source:notna(2))
        end)
    end
    for unused_index, dtype in ipairs({"float64", "int64"}) do
        protocol.check(dtype .. ".sum", "sum respects ignore_na", function()
            local source = fixture(dtype)
            assert(source:sum(true) == 4 and source:sum(false) == nil)
        end)
    end
    protocol.check("where.false", "where selects false from other Series without converting it",
        function()
            local source = smaug.Series({true, true}, "bool")
            local condition = smaug.Series({true, false}, "bool")
            local other = smaug.Series({false, false}, "bool")
            expect_series(source:where(condition, other), "bool", {true, false})
        end, "Known R4/R7 issue must remain visible until fixed")
    protocol.result("scope", "REVIEW", "Remaining NA policies", "Explicit cases above",
        "sort, cumulative/window masks and min_count require family-specific matrices")
end

checks[8] = function()
    for unused_index, dtype in ipairs(dtypes) do
        protocol.check(dtype .. ".size", "size and len agree", function()
            local source = fixture(dtype)
            assert(source:size() == 3 and source:len() == 3)
        end)
    end
    protocol.check("isna.notna", "notna complements isna; it is not an identical alias", function()
        local source = fixture("bool")
        for row_index = 1, source:len() do
            assert(source:isna(row_index) == source:is_null(row_index))
            assert(source:notna(row_index) == not source:is_null(row_index))
        end
    end)
    protocol.result("scope", "REVIEW", "Other naming conventions", "Runtime aliases inventoried in 1/2",
        "Names alone do not establish semantic equivalence")
end

checks[9] = function()
    for unused_index, dtype in ipairs({"float64", "int64", "bool", "datetime"}) do
        protocol.check(dtype .. ".status", "C getter distinguishes valid, NA and OOB by status",
            function()
                local source = fixture(dtype)
                local prefixes = {float64 = "f64", int64 = "i64", bool = "bool", datetime = "dt"}
                local getter = library["smaug_" .. prefixes[dtype] .. "_get"]
                local status = ffi.new("smaug_status_t[1]", library.SMG_ERR_ARGUMENT)
                getter(source._c, 0, status)
                assert(status[0] == library.SMG_OK)
                getter(source._c, 1, status)
                assert(status[0] == library.SMG_NULL_VALUE)
                getter(source._c, 3, status)
                assert(status[0] == library.SMG_ERR_OOB)
            end)
    end
    protocol.check("int64.minimum", "INT64_MIN remains valid when the mask/status says valid",
        function()
            local expected = -9223372036854775807LL - 1LL
            local source = smaug.Series({expected, smaug.NA}, "int64")
            expect_series(source, "int64", {expected, smaug.NA})
        end, "Does not settle the legacy scalar reduction sentinel ambiguity")
    protocol.result("errors", "REVIEW", "Error taxonomy", "No percentage from string occurrences",
        "Uniform prefixes and all consumer error causes need a separate contract matrix")
end

checks[10] = function()
    for unused_index, dtype in ipairs(dtypes) do
        protocol.check(dtype .. ".clone", "clone preserves values after the source is collected",
            function()
                local source, values = fixture(dtype)
                local copied = source:clone()
                source = nil
                collectgarbage("collect")
                expect_series(copied, dtype, values)
            end, "Not a leak detector or proof of all view/COW lifetime paths")
        if dtype ~= "categorical" then
            protocol.check(dtype .. ".descriptor", "view/take/filter descriptors are callable",
                function()
                    local source = fixture(dtype)
                    for unused_operation, operation in ipairs({"view", "take", "filter"}) do
                        assert(type(source._d[operation]) == "cdata" or
                            type(source._d[operation]) == "function", "missing " .. operation)
                    end
                end, "Dispatch capability only; lifetime semantics remain in R7")
        end
    end
end

checks[12] = function()
    protocol.result("runtime-inventory", "OBSERVED", "Runtime object families load",
        "Series, DataSet, GroupBy, .str, .dt and .cat are exercised by family tests",
        "Method inventories are static evidence in the source review")
end

checks[13] = function()
    local numeric = smaug.Series({1, 2, 3}, "float64")
    local categorical = smaug.Series({"a", "b"}, "categorical")
    local dataset = smaug.DataSet({{"value", {1, 2, 3}, "float64"}})
    local factories = {
        Series = function() return numeric end,
        DataSet = function() return dataset end,
        CategoricalSeries = function() return categorical end,
        StrProxy = function() return smaug.Series({"a"}, "string").str end,
        SeriesDT = function() return smaug.Series({0}, "datetime").dt end,
        SeriesAt = function() return numeric.at end,
        CatProxy = function() return categorical.cat end,
        SeriesRolling = function() return numeric:rolling(2) end,
        SeriesExpanding = function() return numeric:expanding() end,
        GroupBy = function() return dataset:groupby("value") end,
        DataSetRolling = function() return dataset:rolling(2) end,
        Schema = function() return smaug.Schema({{name = "value", dtype = "int64", nullable = true}}) end,
    }
    local names = {}
    for name in pairs(factories) do names[#names + 1] = name end
    table.sort(names)
    for unused_index, name in ipairs(names) do
        protocol.check(name, "tostring executes and provides a non-address representation", function()
            local actual = tostring(factories[name]())
            assert(#actual > 0 and not actual:match("^table: 0x") and
                not actual:match("^cdata: 0x"), "raw address representation: " .. actual)
            return actual
        end, "Does not certify every formatting option")
    end
end

checks[15] = function()
    local stream = assert(io.open(arg[3], "r"))
    for line in stream:lines() do
        line = line:gsub("\r$", "")
        local kind, name, field, expected = line:match("^(%S+) (%S+) (%S+) (%d+)$")
        if not kind then
            kind, name, expected = line:match("^(%S+) (%S+) %- (%d+)$")
            field = "-"
        end
        assert(kind and name and field and expected, "invalid compiled layout record")
        protocol.check(kind .. "." .. name .. "." .. field, "Compiled C/FFI " .. kind,
            function()
                local actual
                if kind == "size" then actual = ffi.sizeof(name)
                elseif kind == "align" then actual = ffi.alignof(name)
                elseif kind == "offset" then actual = ffi.offsetof(name, field)
                else error("unknown layout kind") end
                assert(actual == tonumber(expected), name .. "." .. field .. ": C=" .. expected
                    .. " FFI=" .. tostring(actual))
                return name .. "." .. field .. " = " .. expected
            end)
    end
    assert(stream:close())
end

assert(checks[axis], "unsupported runtime axis")( )
protocol.finish()
