-- lua/smaug/io/json.lua
--
-- Frontend Lua do leitor/escritor JSON do Smaug (Anel 3).
--
-- smaug.read_json(path)        → DataSet
-- smaug.read_json_mem(buf)     → DataSet
-- ds:to_json(path, [opts])
-- ds:to_json_mem([opts])       → string Lua

local ffi  = require("ffi")
local C    = require("smaug.ffi_loader")
local csv  = require("smaug.io.csv")   -- reutiliza table_to_dataset e dataset_to_table

-- Reutiliza table_to_dataset do módulo CSV
-- (ambos produzem / consomem smaug_table_t com a mesma estrutura)
local M = {}

function M.read(path)
    if type(path) ~= "string" then
        error("smaug: read_json espera string como path", 2)
    end
    local t = C.smaug_read_json(path)
    -- delega ao csv que sabe converter smaug_table_t → DataSet
    -- (table_to_dataset é interno ao csv.lua; reexpomos via wrapper)
    return csv._table_to_dataset(t)
end

function M.read_mem(buf)
    if type(buf) ~= "string" then
        error("smaug: read_json_mem espera string", 2)
    end
    local t = C.smaug_read_json_mem(buf, #buf)
    return csv._table_to_dataset(t)
end

function M.write(ds, path, opts)
    if type(path) ~= "string" then
        error("smaug: to_json espera string como path", 2)
    end
    local t = csv._dataset_to_table(ds)
    local wopts = ffi.new("smaug_json_write_opts_t")
    wopts.pretty = (opts and opts.pretty) and 1 or 0
    local rc = C.smaug_write_json(path, t, wopts)
    csv._free_table_lua(t, ds:ncols())
    if rc ~= 0 then
        error("smaug: to_json — falha ao escrever '" .. path .. "'", 2)
    end
end

function M.write_mem(ds, opts)
    local t = csv._dataset_to_table(ds)
    local wopts = ffi.new("smaug_json_write_opts_t")
    wopts.pretty = (opts and opts.pretty) and 1 or 0
    local outlen = ffi.new("size_t[1]")
    local buf = C.smaug_write_json_mem(t, wopts, outlen)
    csv._free_table_lua(t, ds:ncols())
    if buf == nil then
        error("smaug: to_json_mem — OOM", 2)
    end
    local result = ffi.string(buf, outlen[0])
    C.smaug_free(buf)
    return result
end

return M
