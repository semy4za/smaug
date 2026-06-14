-- lua/smaug/io/csv.lua
--
-- Frontend Lua do leitor/escritor CSV do Smaug (Anel 3).
-- Converte smaug_table_t (produzida pelo C) ↔ DataSet.
--
-- smaug.read_csv(path, [opts])  → DataSet
-- smaug.read_csv_mem(buf, [opts]) → DataSet
-- ds:to_csv(path, [opts])
-- ds:to_csv_mem([opts]) → string Lua

local ffi     = require("ffi")
local C       = require("smaug.ffi_loader")
local Series  = require("smaug.core.series")
local DataSet = require("smaug.core.dataset")

local NA = Series.NA

-- ===================================================================
-- smaug_table_t → DataSet
-- ===================================================================

local function table_to_dataset(t)
    if t == nil then
        error("smaug: read_csv/json retornou NULL (OOM)", 3)
    end
    if t.error ~= nil then
        local msg = ffi.string(t.error)
        C.smaug_table_free(t)
        error("smaug: " .. msg, 3)
    end

    local ds = DataSet.new("DataFrame")
    local n  = tonumber(t.nrows)

    for ci = 0, tonumber(t.ncols) - 1 do
        local col   = t.columns[ci]
        local name  = ffi.string(col.name)
        local dtype = ffi.string(col.dtype)
        local vals  = {}

        if dtype == "int64" then
            for r = 0, n - 1 do
                local st = ffi.new("smaug_status_t[1]")
                local v  = C.smaug_i64_get(col.i64, r, st)
                vals[r+1] = (st[0] == 0) and tonumber(v) or NA
            end
        elseif dtype == "float64" then
            for r = 0, n - 1 do
                local st = ffi.new("smaug_status_t[1]")
                local v  = C.smaug_f64_get(col.f64, r, st)
                vals[r+1] = (st[0] == 0) and tonumber(v) or NA
            end
        elseif dtype == "bool" then
            for r = 0, n - 1 do
                local st = ffi.new("smaug_status_t[1]")
                local v  = C.smaug_bool_get(col.boolcol, r, st)
                if st[0] == 0 then
                    vals[r+1] = (v == 1)  -- true ou false, nunca nil
                else
                    vals[r+1] = NA
                end
            end
        else  -- string
            for r = 0, n - 1 do
                local slen = ffi.new("size_t[1]")
                local sv   = C.smaug_str_get(col.str, r, slen)
                if sv == nil then
                    vals[r+1] = NA
                else
                    vals[r+1] = ffi.string(sv, slen[0])
                end
            end
        end

        ds:add_column(name, Series.from_table(vals, dtype, name))
    end

    C.smaug_table_free(t)
    return ds
end

-- ===================================================================
-- DataSet → smaug_table_t (para escrita)
-- ===================================================================

local function dataset_to_table(ds)
    local ncols = ds:ncols()
    local nrows = ds:nrows()

    local t = ffi.new("smaug_table_t")
    t.ncols = ncols
    t.nrows = nrows
    t.error = nil
    local col_size = ffi.sizeof("smaug_column_t")
    t.columns = ffi.cast("smaug_column_t*", ffi.C.malloc(ncols * col_size))
    if t.columns == nil then
        error("smaug: to_csv/json — OOM ao alocar colunas", 3)
    end
    ffi.fill(t.columns, ncols * col_size, 0)

    for ci, cname in ipairs(ds._col_names) do
        local col   = ds:column(cname)
        local dtype = col._dtype
        local idx   = ci - 1

        -- nome: precisamos manter a string viva durante a escrita
        -- alocamos com strdup para ser gerenciado pelo C
        local name_c = ffi.C.malloc(#cname + 1)  -- liberado por smaug_free via C.smaug_free
        ffi.copy(name_c, cname)
        t.columns[idx].name  = ffi.cast("const char*", name_c)
        t.columns[idx].dtype = dtype == "float64" and "float64"
                            or dtype == "int64"   and "int64"
                            or dtype == "bool"    and "bool"
                            or "string"

        if dtype == "int64" then
            local s = C.smaug_i64_create(nrows)
            if s == nil then error("smaug: OOM", 3) end
            for r = 1, nrows do
                local v = col:get(r)
                if v == nil then C.smaug_i64_set_null(s, r-1)
                else C.smaug_i64_set(s, r-1, v) end
            end
            t.columns[idx].i64 = s

        elseif dtype == "float64" then
            local s = C.smaug_f64_create(nrows)
            if s == nil then error("smaug: OOM", 3) end
            for r = 1, nrows do
                local v = col:get(r)
                if v == nil then C.smaug_f64_set_null(s, r-1)
                else C.smaug_f64_set(s, r-1, v) end
            end
            t.columns[idx].f64 = s

        elseif dtype == "bool" then
            local s = C.smaug_bool_create(nrows)
            if s == nil then error("smaug: OOM", 3) end
            for r = 1, nrows do
                local v = col:get(r)
                if v == nil then C.smaug_bool_set_null(s, r-1)
                else C.smaug_bool_set(s, r-1, v and 1 or 0) end
            end
            t.columns[idx].boolcol = s

        else  -- string
            local s = C.smaug_str_create(nrows)
            if s == nil then error("smaug: OOM", 3) end
            for r = 1, nrows do
                local v = col:get(r)
                if v == nil then C.smaug_str_set_null(s, r-1)
                else C.smaug_str_set(s, r-1, v, #v) end
            end
            t.columns[idx].str = s
        end
    end

    return t
end

local function free_table_lua(t, ncols)
    -- libera recursos alocados por dataset_to_table (não usar smaug_table_free
    -- porque os ponteiros C foram alocados aqui)
    for ci = 0, ncols - 1 do
        C.smaug_free(ffi.cast("void*", t.columns[ci].name))
        if t.columns[ci].i64     ~= nil then C.smaug_i64_free(t.columns[ci].i64)     end
        if t.columns[ci].f64     ~= nil then C.smaug_f64_free(t.columns[ci].f64)     end
        if t.columns[ci].boolcol ~= nil then C.smaug_bool_free(t.columns[ci].boolcol) end
        if t.columns[ci].str     ~= nil then C.smaug_str_free(t.columns[ci].str)      end
    end
    C.smaug_free(t.columns)
end

-- ===================================================================
-- API pública
-- ===================================================================

local M = {}

-- opts: { sep=",", header=true, na_values={...} }
function M.read(path, opts)
    if type(path) ~= "string" then
        error("smaug: read_csv espera string como path", 2)
    end
    local copts = C.smaug_csv_default_opts()
    if opts then
        if opts.sep    then copts.sep    = string.byte(opts.sep) end
        if opts.quote  then copts.quote  = string.byte(opts.quote) end
        if opts.header ~= nil then copts.header = opts.header and 1 or 0 end
    end
    local t = C.smaug_read_csv(path, copts)
    return table_to_dataset(t)
end

function M.read_mem(buf, opts)
    if type(buf) ~= "string" then
        error("smaug: read_csv_mem espera string", 2)
    end
    local copts = C.smaug_csv_default_opts()
    if opts then
        if opts.sep    then copts.sep    = string.byte(opts.sep) end
        if opts.quote  then copts.quote  = string.byte(opts.quote) end
        if opts.header ~= nil then copts.header = opts.header and 1 or 0 end
    end
    local t = C.smaug_read_csv_mem(buf, #buf, copts)
    return table_to_dataset(t)
end

-- ds:to_csv(path, [opts])
function M.write(ds, path, opts)
    if type(path) ~= "string" then
        error("smaug: to_csv espera string como path", 2)
    end
    local t = dataset_to_table(ds)
    local wopts = C.smaug_csv_write_default_opts()
    if opts then
        if opts.sep    then wopts.sep    = string.byte(opts.sep) end
        if opts.quote  then wopts.quote  = string.byte(opts.quote) end
        if opts.header ~= nil then wopts.header = opts.header and 1 or 0 end
    end
    local rc = C.smaug_write_csv(path, t, wopts)
    free_table_lua(t, ds:ncols())
    if rc ~= 0 then
        error("smaug: to_csv — falha ao escrever '" .. path .. "'", 2)
    end
end

-- ds:to_csv_mem([opts]) → string Lua
function M.write_mem(ds, opts)
    local t = dataset_to_table(ds)
    local wopts = C.smaug_csv_write_default_opts()
    if opts then
        if opts.sep    then wopts.sep    = string.byte(opts.sep) end
        if opts.quote  then wopts.quote  = string.byte(opts.quote) end
        if opts.header ~= nil then wopts.header = opts.header and 1 or 0 end
    end
    local outlen = ffi.new("size_t[1]")
    local buf = C.smaug_write_csv_mem(t, wopts, outlen)
    free_table_lua(t, ds:ncols())
    if buf == nil then
        error("smaug: to_csv_mem — OOM", 2)
    end
    local result = ffi.string(buf, outlen[0])
    C.smaug_free(buf)
    return result
end

-- Expõe funções internas para uso pelo json.lua (mesma fronteira smaug_table_t)
M._table_to_dataset  = table_to_dataset
M._dataset_to_table  = dataset_to_table
M._free_table_lua    = free_table_lua

return M
