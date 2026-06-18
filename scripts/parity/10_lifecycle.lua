-- scripts/parity/10_lifecycle.lua
-- Eixo 10: paridade de lifecycle entre dtypes.
-- Cada dtype com backend C deve ter o mesmo conjunto de funções de lifecycle.

local C = dofile("scripts/parity/common.lua")

local lifecycle = {
    "create", "create_with_capacity", "create_from_array",
    "free", "clone", "view", "append", "append_null",
    "set", "set_null", "get", "is_null",
}

local headers_by_dtype = {
    f64 = (C.read_file("include/smaug_numeric.h") or "")
       .. (C.read_file("include/smaug_core.h") or ""),
    i64 = (C.read_file("include/smaug_numeric.h") or "")
       .. (C.read_file("include/smaug_core.h") or ""),
    bool = (C.read_file("include/smaug_bool.h") or "")
        .. (C.read_file("include/smaug_core.h") or ""),
    str = (C.read_file("include/smaug_string.h") or "")
       .. (C.read_file("include/smaug.h") or ""),
    dt = (C.read_file("include/smaug_datetime.h") or ""),
}

local dtypes = {"f64", "i64", "bool", "str", "dt"}

local excs = C.load_exceptions()
local excs10 = excs["10"] or {}

local rows = {}
for _, fn in ipairs(lifecycle) do
    local row = { "`"..fn.."`" }
    for _, d in ipairs(dtypes) do
        local content = headers_by_dtype[d] or ""
        local needle = "smaug_" .. d .. "_" .. fn
        local found = content:find(needle, 1, true) ~= nil
        local exc_key = fn .. "/" .. d
        if found then
            row[#row+1] = "🟩"
        elseif excs10[exc_key] then
            row[#row+1] = "⬜"
        else
            row[#row+1] = "🟨"
        end
    end
    rows[#rows+1] = row
end

local header = { "função", "f64", "i64", "bool", "str", "dt" }

local out = {
    C.section(10, "Paridade de lifecycle",
        "Cada dtype com backend C deve oferecer o mesmo conjunto de operações "
        .. "de lifecycle. `categorical` é Lua puro e não entra nesta tabela "
        .. "(exceção em `exceptions.txt`)."),
    "",
    C.render_table(header, rows),
    "",
}

io.write(table.concat(out, "\n"))
