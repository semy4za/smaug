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
local warn = require("smaug.core.warn")

-- 12.10: aviso passivo de separador suspeito.
--
-- Decisão registrada: NÃO detectar/escolher separador sozinho (esperto demais;
-- falso-positivo pior que o problema). Apenas ilumina: se o arquivo virou UMA
-- coluna e os valores contêm outro separador comum repetido, provavelmente o
-- `sep` está errado — mas pode ser intencional, então é warn, não erro.
--
-- Fica nos pontos de entrada do CSV (M.read/M.read_mem), NÃO no
-- table_to_dataset: aquele é compartilhado com o json.lua, e "verifique o
-- separador" não faz sentido para JSON.
local SUSPECT_SEPS = { [";"] = "';'", ["\t"] = "'\\t'", ["|"] = "'|'" }

local function warn_if_suspect_sep(ds, copts)
    if ds:ncols() ~= 1 then return end
    local name = ds._col_names[1]
    local col  = ds._columns[name]
    local used = string.char(copts.sep)

    -- amostra: o header (nome da coluna) + até 5 valores. O header sozinho já
    -- denuncia o caso típico ("a;b;c" virando um nome de coluna só).
    local sample = { name }
    if col._dtype == "string" then
        for i = 1, math.min(col:len(), 5) do
            local v = col:get(i)
            if v ~= nil then sample[#sample + 1] = v end
        end
    end

    for sep, label in pairs(SUSPECT_SEPS) do
        if sep ~= used then
            local hits = 0
            for _, s in ipairs(sample) do
                local _, n = s:gsub(sep, "")
                if n >= 1 then hits = hits + 1 end
            end
            -- exige o separador em TODAS as linhas amostradas (>=2 amostras):
            -- um ';' solto num texto livre não dispara.
            if hits == #sample and #sample >= 2 then
                warn("read_csv leu o arquivo como 1 coluna; se esperava mais, "
                     .. "verifique o separador (sep=" .. label .. "?)")
                return
            end
        end
    end
end

-- ===================================================================
-- smaug_table_t → DataSet
-- ===================================================================

-- table_to_dataset(t, op): `op` é o nome da função pública que o usuário
-- chamou (read_csv, read_csv_mem, read_json, read_json_mem). O Anel 0 devolve
-- só a RAZÃO do erro ("entrada vazia"); quem sabe a operação é o Anel 3 (12.1).
-- Antes o C prefixava "smaug_read_csv:" e o Lua somava "smaug: ", produzindo
-- "smaug: smaug_read_csv: ..." — e o prefixo fixo mentia no _mem (dizia
-- read_csv quando a chamada era read_csv_mem, e "arquivo" quando era buffer).
local function table_to_dataset(t, op)
    op = op or "read_csv"
    if t == nil then
        error("smaug: " .. op .. " — retornou NULL (OOM)", 3)
    end
    if t.error ~= nil then
        local msg = ffi.string(t.error)
        C.smaug_table_free(t)
        error("smaug: " .. op .. " — " .. msg, 3)
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

-- free_table_lua é declarada aqui (forward) porque dataset_to_table a usa para
-- liberar o parcial em caso de OOM no meio da construção (12.27); a definição
-- vem logo abaixo.
local free_table_lua

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

    -- 12.27: a construção abaixo aloca, por coluna, o nome (ffi.C.malloc) e a
    -- série C (smaug_*_create). Um OOM no meio (create devolve nil → error)
    -- deixaria o parcial vazando, pois `t` nunca chega ao caller para ser
    -- liberado. Protegemos com pcall: em falha, free_table_lua libera o que já
    -- foi alocado (seguro sobre parcial — o ffi.fill zerou tudo e o free pula
    -- campos nil) e repropaga o erro original.
    local build_ok, build_err = pcall(function()
    for ci, cname in ipairs(ds._col_names) do
        local col   = ds:_raw_column(cname)
        local dtype = col._dtype
        local idx   = ci - 1

        -- 12.3: `smaug_column_t` carrega f64/i64/bool/str — não tem dt. O mapa
        -- de dtype abaixo já traduzia datetime para "string", mas entregava a
        -- coluna datetime crua: o C recebia a promessa de string e o laço da
        -- string fazia `#v` num número (epoch_ms) → crash em to_csv/to_json.
        -- Convertemos aqui, no Anel 3: astype("string") de datetime produz ISO
        -- 8601 (o mesmo formato do smaug_dt_format), e o round-trip de VALOR é
        -- preservado — quem lê faz astype("datetime") de volta (ver 12.25, que
        -- decide se o reader deve inferir ISO sozinho).
        -- CSV não tem tipos e JSON não tem tipo "date": texto ISO é o que ambos
        -- comportam, então isto preserva o dado, não o degrada (CONTRATO 9).
        if dtype == "datetime" then
            col   = col:astype("string")
            dtype = "string"
        end

        -- nome: precisamos manter a string viva durante a escrita
        -- alocamos com strdup para ser gerenciado pelo C
        local name_c = ffi.C.malloc(#cname + 1)  -- heap do luajit → free com ffi.C.free (ver free_table_lua)
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
    end)  -- fim do pcall de construção

    if not build_ok then
        free_table_lua(t, ncols)   -- libera o parcial (fill+guard nil = seguro)
        error(build_err, 0)        -- repropaga o erro original (nível 0: sem prefixo extra)
    end

    return t
end

function free_table_lua(t, ncols)
    -- libera recursos alocados por dataset_to_table. IMPORTANTE (bug de heap
    -- no Windows): `name` e `columns` foram alocados com ffi.C.malloc (heap do
    -- luajit.exe), então DEVEM ser liberados com ffi.C.free — não com
    -- C.smaug_free, que libera no heap da DLL. No Linux o heap é único e a
    -- troca é inócua; no Windows luajit e smaug.dll têm heaps separados e
    -- liberar no heap errado corrompe o heap (crash). As séries, ao contrário,
    -- foram criadas pela lib (C.smaug_*_create) e saem por C.smaug_*_free.
    for ci = 0, ncols - 1 do
        ffi.C.free(ffi.cast("void*", t.columns[ci].name))
        if t.columns[ci].i64     ~= nil then C.smaug_i64_free(t.columns[ci].i64)     end
        if t.columns[ci].f64     ~= nil then C.smaug_f64_free(t.columns[ci].f64)     end
        if t.columns[ci].boolcol ~= nil then C.smaug_bool_free(t.columns[ci].boolcol) end
        if t.columns[ci].str     ~= nil then C.smaug_str_free(t.columns[ci].str)      end
    end
    ffi.C.free(t.columns)
end

-- ===================================================================
-- API pública
-- ===================================================================

-- apply_opts: traduz opts Lua -> smaug_csv_opts_t.
-- Devolve (copts, anchor). O `anchor` PRECISA continuar vivo até a chamada C
-- terminar: copts.na_values aponta para o array de const char* e para as
-- strings Lua. Sem segurá-lo, o GC pode coletá-los durante a leitura.
--
-- na_values era documentado desde sempre ("opts: { sep, header, na_values }")
-- mas nunca implementado — o C tinha os campos, o frontend não os populava.
-- Implementado no 12.21, quando "nan"/"NaN" saíram do BUILTIN_NA: quem lê CSV
-- de terceiros onde "nan" significa ausência precisa deste opt-in.
local function apply_opts(opts)
    local copts = C.smaug_csv_default_opts()
    if not opts then return copts, nil end
    if opts.sep     then copts.sep     = string.byte(opts.sep) end
    if opts.quote   then copts.quote   = string.byte(opts.quote) end
    if opts.decimal then copts.decimal = string.byte(opts.decimal) end
    if opts.header ~= nil then copts.header = opts.header and 1 or 0 end
    local anchor
    if opts.na_values ~= nil then
        if type(opts.na_values) ~= "table" then
            error("smaug: read_csv — na_values espera tabela de strings", 3)
        end
        local n = #opts.na_values
        local arr = ffi.new("const char*[?]", n > 0 and n or 1)
        local keep = {}
        for i = 1, n do
            local v = opts.na_values[i]
            if type(v) ~= "string" then
                error("smaug: read_csv — na_values[" .. i .. "] deve ser string; recebido "
                      .. type(v), 3)
            end
            keep[i]  = v
            arr[i-1] = keep[i]
        end
        copts.na_values = arr
        copts.na_count  = n
        anchor = { arr, keep }
    end
    return copts, anchor
end

local M = {}

-- opts: { sep=",", header=true, na_values={...} }
function M.read(path, opts)
    if type(path) ~= "string" then
        error("smaug: read_csv espera string como path", 2)
    end
    local copts, anchor = apply_opts(opts)
    local t = C.smaug_read_csv(path, copts)
    local ds = table_to_dataset(t, "read_csv")
    warn_if_suspect_sep(ds, copts)
    local _ = anchor   -- mantém na_values vivo até aqui
    return ds
end

function M.read_mem(buf, opts)
    if type(buf) ~= "string" then
        error("smaug: read_csv_mem espera string", 2)
    end
    local copts, anchor = apply_opts(opts)
    local t = C.smaug_read_csv_mem(buf, #buf, copts)
    local ds = table_to_dataset(t, "read_csv_mem")
    warn_if_suspect_sep(ds, copts)
    local _ = anchor   -- mantém na_values vivo até aqui
    return ds
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
        if opts.decimal then wopts.decimal = string.byte(opts.decimal) end
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
        if opts.decimal then wopts.decimal = string.byte(opts.decimal) end
        if opts.header ~= nil then wopts.header = opts.header and 1 or 0 end
    end
    local outlen = ffi.new("size_t[1]")
    local errp   = ffi.new("char*[1]")   -- 12.30: recebe a causa; C zera em sucesso
    local buf = C.smaug_write_csv_mem(t, wopts, outlen, errp)
    free_table_lua(t, ds:ncols())
    if buf == nil then
        -- antes: "OOM" fixo — mentia quando a causa era sep==decimal. Agora o C
        -- diz a causa (heap da DLL → liberar com smaug_free, não ffi.C.free).
        local msg = errp[0] ~= nil and ffi.string(errp[0]) or "erro desconhecido"
        if errp[0] ~= nil then C.smaug_free(errp[0]) end
        error("smaug: to_csv_mem — " .. msg, 2)
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
