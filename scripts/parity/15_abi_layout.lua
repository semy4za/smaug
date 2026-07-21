-- scripts/parity/15_abi_layout.lua
-- Eixo 15: layout de struct — header C (fonte de verdade) ↔ cdef FFI (ffi_loader).
--
-- Por que existe: o `cdef` do `ffi_loader.lua` replica À MÃO o layout de cada
-- struct dos headers. Se as duas declarações divergirem (campo renomeado,
-- reordenado, tipo trocado, campo a mais/a menos), o LuaJIT passa a ler bytes
-- deslocados — corrupção silenciosa que um teste funcional pequeno não pega.
-- Este eixo compara a SEQUÊNCIA (tipo, nome) dos campos de cada struct nos dois
-- lados. 12.28 / achado A-FFI.
--
-- Por que comparação textual basta (verificado, não presumido): nem os headers
-- nem o cdef usam #pragma pack / __attribute__((packed)) / bitfields / aligned.
-- Sem packing custom, C e LuaJIT-FFI usam o MESMO alinhamento padrão da ABI da
-- plataforma — logo, sequência idêntica de (tipo, nome) ⟹ layout idêntico em
-- memória (confirmado empiricamente: sizeof/offsetof batem byte a byte). A
-- salvaguarda abaixo re-afirma esse pressuposto a cada run: se algum dia entrar
-- packing custom, o eixo falha e avisa que a comparação textual deixou de bastar.

local C = dofile("scripts/parity/common.lua")

-- Structs que cruzam a fronteira FFI por LAYOUT (o Lua preenche via ffi.new e o
-- C lê, ou o C devolve e o Lua indexa). Opacas (ex.: smaug_hash_table_t, sem
-- corpo — só ponteiro cego) ficam de fora: seu layout nunca é lido pelo Lua.
-- Cada entrada: nome da struct + headers onde pode estar declarada.
local STRUCTS = {
    { name = "smaug_metadata_t",         headers = {"smaug_types.h"} },
    { name = "smaug_series_bool_t",      headers = {"smaug_types.h", "smaug_bool.h"} },
    { name = "smaug_series_str_t",       headers = {"smaug_types.h", "smaug_string.h"} },
    { name = "smaug_series_dt_t",        headers = {"smaug_types.h", "smaug_datetime.h"} },
    { name = "smaug_column_t",           headers = {"smaug_types.h", "smaug_io.h"} },
    { name = "smaug_table_t",            headers = {"smaug_types.h", "smaug_io.h"} },
    { name = "smaug_csv_opts_t",         headers = {"smaug_io.h"} },
    { name = "smaug_csv_write_opts_t",   headers = {"smaug_io.h"} },
    { name = "smaug_json_write_opts_t",  headers = {"smaug_io.h"} },
    { name = "smaug_sort_col_ffi_t",     headers = {"smaug_ops_window.h", "smaug_types.h"} },
}

-- Remove comentários C (/* ... */ incl. multi-linha e // ...) de um trecho.
local function strip_comments(s)
    s = s:gsub("/%*.-%*/", " ")   -- bloco (não-guloso cobre multi-linha)
    s = s:gsub("//[^\n]*", " ")   -- linha
    return s
end

-- Extrai o corpo de `typedef struct { ... } NAME;` de um texto. Retorna o
-- miolo entre chaves, ou nil se a struct não estiver ali.
local function struct_body(text, name)
    -- Casa "typedef struct <opt-tag> { CORPO } NAME ;"
    local pat = "typedef%s+struct%s*[%w_]*%s*(%b{})%s*" .. name:gsub("_", "_") .. "%s*;"
    local body = text:match(pat)
    if not body then return nil end
    return body:sub(2, -2)  -- remove as chaves externas
end

-- Typedefs que são o MESMO tipo subjacente (layout idêntico), mas aparecem com
-- nomes diferentes entre header e cdef. Comparar o nome do typedef daria falso
-- positivo — o que importa para ABI é o tipo subjacente. Resolvidos aqui antes
-- de comparar. (smaug_mask_t é `typedef uint8_t` — verificado em smaug_types.h.)
local TYPE_ALIASES = {
    ["smaug_mask_t"] = "uint8_t",
}

local function canon_type(typ)
    -- separa um sufixo de ponteiros para resolver o typedef da base
    local base, ptr = typ:match("^([%w_]+)([%*]*)$")
    if base and TYPE_ALIASES[base] then
        return TYPE_ALIASES[base] .. (ptr or "")
    end
    return typ
end

-- Dado o corpo de uma struct (sem comentários), devolve a lista ordenada de
-- campos, cada um normalizado como "tipo|nome". Normaliza espaços e junta o
-- caractere de ponteiro ao tipo (char *buffer e char* buffer → "char*|buffer").
local function parse_fields(body)
    local fields = {}
    for decl in body:gmatch("[^;]+") do
        local d = decl:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        if d ~= "" then
            -- último token alfanumérico é o nome; o resto é o tipo
            local typ, nm = d:match("^(.-)([%w_]+)$")
            if typ and nm then
                typ = typ:gsub("%s+", ""):gsub("%*", "*")  -- compacta tipo+ptr
                -- reanexa '*' que ficou colado ao nome (size_t *offsets)
                -- já tratado: '*' pertence ao typ pois nm é só [%w_]+
                typ = canon_type(typ)                       -- resolve typedefs (mask_t→uint8_t)
                fields[#fields+1] = typ .. "|" .. nm
            end
        end
    end
    return fields
end

-- Lê a declaração de uma struct do lado C (concatena os headers candidatos).
local function c_fields(entry)
    local text = ""
    for _, h in ipairs(entry.headers) do
        text = text .. "\n" .. (C.read_file("include/" .. h) or "")
    end
    local body = struct_body(strip_comments(text), entry.name)
    if not body then return nil end
    return parse_fields(body)
end

-- Lê a declaração do lado cdef (ffi_loader.lua).
local cdef_text = C.read_file("lua/smaug/ffi_loader.lua") or ""
local function cdef_fields(entry)
    local body = struct_body(strip_comments(cdef_text), entry.name)
    if not body then return nil end
    return parse_fields(body)
end

-- ---------------------------------------------------------------------------
-- Salvaguarda: comparação textual só vale sem packing custom. Se aparecer,
-- o pressuposto quebrou e o eixo tem de falhar avisando.
-- ---------------------------------------------------------------------------
local function scan_packing()
    local hits = {}
    local files = {
        "include/smaug_types.h", "include/smaug_string.h", "include/smaug_bool.h",
        "include/smaug_datetime.h", "include/smaug_io.h", "include/smaug_ops_window.h",
        "include/smaug_core.h", "include/smaug_numeric.h",
        "lua/smaug/ffi_loader.lua",
    }
    for _, f in ipairs(files) do
        local t = C.read_file(f) or ""
        if t:match("#pragma%s+pack") or t:match("__attribute__%s*%(%s*%(%s*packed")
           or t:match("__attribute__%s*%(%s*%(%s*aligned") then
            hits[#hits+1] = f
        end
    end
    return hits
end

-- ---------------------------------------------------------------------------
-- Comparação
-- ---------------------------------------------------------------------------
local rows = {}
local problems = 0

local packing = scan_packing()
if #packing > 0 then
    problems = problems + 1
    rows[#rows+1] = { "**packing custom detectado**", "🟥",
        "comparação textual não basta mais: " .. table.concat(packing, ", ") }
end

for _, entry in ipairs(STRUCTS) do
    local cf = c_fields(entry)
    local lf = cdef_fields(entry)
    local status, note

    if not cf then
        status, note = "🟨", "struct não encontrada nos headers " .. table.concat(entry.headers, "/")
        problems = problems + 1
    elseif not lf then
        status, note = "🟥", "declarada no C mas AUSENTE no cdef (ffi_loader)"
        problems = problems + 1
    elseif #cf ~= #lf then
        status = "🟥"
        note = string.format("nº de campos difere: C=%d, cdef=%d", #cf, #lf)
        problems = problems + 1
    else
        local diff = nil
        for i = 1, #cf do
            if cf[i] ~= lf[i] then
                diff = string.format("campo %d: C=`%s` vs cdef=`%s`",
                    i, cf[i]:gsub("|", " "), lf[i]:gsub("|", " "))
                break
            end
        end
        if diff then
            status, note = "🟥", diff
            problems = problems + 1
        else
            status, note = "🟩", string.format("%d campos, layout coerente", #cf)
        end
    end
    rows[#rows+1] = { "`" .. entry.name .. "`", status, note }
end

-- ---------------------------------------------------------------------------
-- Saída (markdown para o PARITY_REPORT)
-- ---------------------------------------------------------------------------
local out = {
    C.section(15, "Layout de struct (ABI) — header ↔ cdef",
        "O `cdef` do `ffi_loader.lua` replica à mão o layout de cada struct dos "
        .. "headers C. Divergência = leitura de memória deslocada (corrupção "
        .. "silenciosa). Este eixo compara a sequência (tipo, nome) dos campos. "
        .. "Válido porque não há packing custom (salvaguarda checa a cada run). "
        .. "🟥 = divergência real; 🟨 = struct não localizada."),
}
local header = { "struct", "layout", "nota" }
out[#out+1] = C.render_table(header, rows)
io.write(table.concat(out, "\n") .. "\n")

-- Exit code: o runner (parity.sh/ps1) marca FALHOU se ≠ 0.
if problems > 0 then os.exit(1) end
