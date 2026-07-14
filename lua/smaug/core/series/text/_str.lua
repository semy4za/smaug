-- lua/smaug/core/series/text/_str.lua
--
-- StrProxy: accessor .str para Series<string>. Tier A+B+C.
-- Semântica de bytes (não Unicode). Todos os métodos propagam null.
-- Recebe I com: I.Series, I.C, I.ffi, I.wrap, I.NA
-- Produz em I: I.StrProxy

return function(I)
    local Series = I.Series
    local C      = I.C
    local ffi    = I.ffi
    local wrap   = I.wrap
    local NA     = I.NA

    local StrProxy = {}
    StrProxy.__index = StrProxy
    StrProxy.__tostring = function(self)
        return string.format("<accessor .str de Series '%s'>", self._s._name or "unnamed")
    end
    I.StrProxy = StrProxy

    -- =====================================================================
    -- Helpers internos
    -- =====================================================================

    -- str_map: itera e devolve nova Series<string>. fn(v: string) → string | nil.
    local function str_map(src, fn)
        local n   = src:len()
        local out = Series.new("string", n, src._name)
        for i = 1, n do
            local v = src:get(i)
            if v == nil then
                out:set_null(i)
            else
                local r = fn(v)
                if r == nil then out:set_null(i) else out:set(i, r) end
            end
        end
        return out
    end

    -- bool_map: itera e devolve Series<bool>. fn(v: string) → boolean.
    local function bool_map(src, fn)
        local n = src:len()
        local s = C.smaug_bool_create(n)
        if s == nil then error("smaug: OOM em bool_map", 2) end
        for i = 1, n do
            local v = src:get(i)
            if v == nil then
                C.smaug_bool_set_null(s, i - 1)
            else
                C.smaug_bool_set(s, i - 1, fn(v) and 1 or 0)
            end
        end
        return wrap(ffi.gc(s, C.smaug_bool_free), "bool", src._name)
    end

    -- Predicados de byte (ASCII)
    local function all_bytes(v, pred)
        if #v == 0 then return false end
        for k = 1, #v do
            if not pred(v:byte(k)) then return false end
        end
        return true
    end

    local function b_is_digit(b) return b >= 48 and b <= 57 end
    local function b_is_lower(b) return b >= 97 and b <= 122 end
    local function b_is_upper(b) return b >= 65 and b <= 90 end
    local function b_is_alpha(b) return b_is_lower(b) or b_is_upper(b) end
    local function b_is_alnum(b) return b_is_alpha(b) or b_is_digit(b) end
    local function b_is_space(b)
        return b == 32 or (b >= 9 and b <= 13)
    end

    -- =====================================================================
    -- Tier A
    -- =====================================================================

    -- len(): comprimento em bytes → Series<int64>. Null → null.
    function StrProxy:len()
        local n   = self._s:len()
        local out = Series.new("int64", n, self._s._name)
        for i = 1, n do
            local v = self._s:get(i)
            if v == nil then out:set_null(i) else out:set(i, #v) end
        end
        return out
    end

    function StrProxy:lower() return str_map(self._s, string.lower) end
    function StrProxy:upper() return str_map(self._s, string.upper) end

    function StrProxy:strip()
        return str_map(self._s, function(v) return (v:match("^%s*(.-)%s*$")) end)
    end

    function StrProxy:contains(sub)
        if type(sub) ~= "string" then
            error("smaug: str:contains espera uma string; recebido " .. type(sub), 2)
        end
        return bool_map(self._s, function(v) return v:find(sub, 1, true) ~= nil end)
    end

    function StrProxy:startswith(prefix)
        if type(prefix) ~= "string" then
            error("smaug: str:startswith espera uma string; recebido " .. type(prefix), 2)
        end
        local n = #prefix
        return bool_map(self._s, function(v) return v:sub(1, n) == prefix end)
    end

    function StrProxy:endswith(suffix)
        if type(suffix) ~= "string" then
            error("smaug: str:endswith espera uma string; recebido " .. type(suffix), 2)
        end
        local n = #suffix
        return bool_map(self._s, function(v)
            return n == 0 or v:sub(-n) == suffix
        end)
    end

    function StrProxy:replace(old, new)
        if type(old) ~= "string" then
            error("smaug: str:replace espera string como 1º argumento; recebido " .. type(old), 2)
        end
        if type(new) ~= "string" then
            error("smaug: str:replace espera string como 2º argumento; recebido " .. type(new), 2)
        end
        if #old == 0 then return str_map(self._s, function(v) return v end) end
        local esc_old = old:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
        local esc_new = new:gsub("%%", "%%%%")
        return str_map(self._s, function(v) return (v:gsub(esc_old, esc_new)) end)
    end

    -- =====================================================================
    -- Tier B
    -- =====================================================================

    -- find(sub): índice 1-based da primeira ocorrência, ou 0 se ausente.
    function StrProxy:find(sub)
        if type(sub) ~= "string" then
            error("smaug: str:find espera uma string; recebido " .. type(sub), 2)
        end
        local n   = self._s:len()
        local out = Series.new("int64", n, self._s._name)
        for i = 1, n do
            local v = self._s:get(i)
            if v == nil then
                out:set_null(i)
            else
                local pos = v:find(sub, 1, true)
                out:set(i, pos or 0)
            end
        end
        return out
    end

    -- slice(start, [stop]): substring 1-based. Índices negativos contam do fim.
    function StrProxy:slice(start, stop)
        if type(start) ~= "number" then
            error("smaug: str:slice espera número como start; recebido " .. type(start), 2)
        end
        return str_map(self._s, function(v) return v:sub(start, stop) end)
    end

    -- pad(width, [side], [fillchar]): preenche até width caracteres.
    function StrProxy:pad(width, side, fillchar)
        if type(width) ~= "number" or width < 0 then
            error("smaug: str:pad espera width >= 0; recebido " .. tostring(width), 2)
        end
        side     = side     or "left"
        fillchar = fillchar or " "
        if #fillchar ~= 1 then
            error("smaug: str:pad fillchar deve ter exatamente 1 caractere", 2)
        end
        if side ~= "left" and side ~= "right" and side ~= "both" then
            error("smaug: str:pad side deve ser 'left', 'right' ou 'both'", 2)
        end
        return str_map(self._s, function(v)
            local missing = width - #v
            if missing <= 0 then return v end
            if side == "right" then
                return v .. fillchar:rep(missing)
            elseif side == "left" then
                return fillchar:rep(missing) .. v
            else
                local left  = math.floor(missing / 2)
                local right = missing - left
                return fillchar:rep(left) .. v .. fillchar:rep(right)
            end
        end)
    end

    -- zfill(width): preenche com '0' à esquerda.
    function StrProxy:zfill(width) return self:pad(width, "left", "0") end

    -- rep(n, [sep]): repete a string n vezes.
    function StrProxy:rep(n, sep)
        if type(n) ~= "number" or n < 0 or n ~= math.floor(n) then
            error("smaug: str:rep espera inteiro >= 0; recebido " .. tostring(n), 2)
        end
        sep = sep or ""
        return str_map(self._s, function(v)
            if n == 0 then return "" end
            return string.rep(v, n, sep)
        end)
    end

    -- cat([sep]): concatena todos os não-nulos em string Lua.
    function StrProxy:cat(sep)
        sep = sep or ""
        local parts = {}
        local n     = self._s:len()
        for i = 1, n do
            local v = self._s:get(i)
            if v ~= nil then parts[#parts+1] = v end
        end
        return table.concat(parts, sep)
    end

    -- split(sep, [max_splits]): divide cada elemento. Retorna tabela de Series.
    function StrProxy:split(sep, max_splits)
        if type(sep) ~= "string" or #sep == 0 then
            error("smaug: str:split espera separador string não-vazio", 2)
        end
        max_splits = max_splits or 0
        local rows      = self._s:len()
        local all_parts = {}
        local max_parts = 0

        for i = 1, rows do
            local v = self._s:get(i)
            if v == nil then
                all_parts[i] = nil
            else
                local parts = {}
                local start = 1
                local slen  = #sep
                local splits = 0
                while true do
                    local found = v:find(sep, start, true)
                    if not found or (max_splits > 0 and splits >= max_splits) then
                        parts[#parts+1] = v:sub(start)
                        break
                    end
                    parts[#parts+1] = v:sub(start, found - 1)
                    start  = found + slen
                    splits = splits + 1
                end
                all_parts[i] = parts
                if #parts > max_parts then max_parts = #parts end
            end
        end

        local result = {}
        for col = 1, max_parts do
            local vals = {}
            for i = 1, rows do
                local parts = all_parts[i]
                if parts == nil or parts[col] == nil then
                    vals[i] = NA
                else
                    vals[i] = parts[col]
                end
            end
            result[col] = Series.from_table(vals, "string")
        end
        return result
    end

    -- =====================================================================
    -- Tier C
    -- =====================================================================

    -- count(sub): nº de ocorrências literais não-sobrepostas.
    function StrProxy:count(sub)
        if type(sub) ~= "string" then
            error("smaug: str:count espera uma string; recebido " .. type(sub), 2)
        end
        if #sub == 0 then error("smaug: str:count espera substring não-vazia", 2) end
        local sub_len = #sub
        local n       = self._s:len()
        local out     = Series.new("int64", n, self._s._name)
        for i = 1, n do
            local v = self._s:get(i)
            if v == nil then
                out:set_null(i)
            else
                local c, start = 0, 1
                while true do
                    local found = v:find(sub, start, true)
                    if not found then break end
                    c = c + 1
                    start = found + sub_len
                end
                out:set(i, c)
            end
        end
        return out
    end

    function StrProxy:isdigit() return bool_map(self._s, function(v) return all_bytes(v, b_is_digit) end) end
    function StrProxy:isalpha() return bool_map(self._s, function(v) return all_bytes(v, b_is_alpha) end) end
    function StrProxy:isalnum() return bool_map(self._s, function(v) return all_bytes(v, b_is_alnum) end) end
    function StrProxy:isspace() return bool_map(self._s, function(v) return all_bytes(v, b_is_space) end) end

    function StrProxy:islower()
        return bool_map(self._s, function(v)
            local has_alpha = false
            for k = 1, #v do
                local b = v:byte(k)
                if b_is_upper(b) then return false end
                if b_is_lower(b) then has_alpha = true end
            end
            return has_alpha
        end)
    end

    function StrProxy:isupper()
        return bool_map(self._s, function(v)
            local has_alpha = false
            for k = 1, #v do
                local b = v:byte(k)
                if b_is_lower(b) then return false end
                if b_is_upper(b) then has_alpha = true end
            end
            return has_alpha
        end)
    end

    function StrProxy:removeprefix(p)
        if type(p) ~= "string" then
            error("smaug: str:removeprefix espera uma string; recebido " .. type(p), 2)
        end
        local np = #p
        if np == 0 then return str_map(self._s, function(v) return v end) end
        return str_map(self._s, function(v)
            if v:sub(1, np) == p then return v:sub(np + 1) end
            return v
        end)
    end

    function StrProxy:removesuffix(suf)
        if type(suf) ~= "string" then
            error("smaug: str:removesuffix espera uma string; recebido " .. type(suf), 2)
        end
        local ns = #suf
        if ns == 0 then return str_map(self._s, function(v) return v end) end
        return str_map(self._s, function(v)
            if v:sub(-ns) == suf then return v:sub(1, #v - ns) end
            return v
        end)
    end

    function StrProxy:capitalize()
        return str_map(self._s, function(v)
            if #v == 0 then return v end
            return v:sub(1, 1):upper() .. v:sub(2):lower()
        end)
    end

    function StrProxy:title()
        return str_map(self._s, function(v)
            local out       = {}
            local prev_alpha = false
            for k = 1, #v do
                local b        = v:byte(k)
                local is_alpha = b_is_alpha(b)
                if is_alpha then
                    if prev_alpha then
                        out[k] = string.char(b_is_upper(b) and b + 32 or b)
                    else
                        out[k] = string.char(b_is_lower(b) and b - 32 or b)
                    end
                else
                    out[k] = string.char(b)
                end
                prev_alpha = is_alpha
            end
            return table.concat(out)
        end)
    end

    function StrProxy:swapcase()
        return str_map(self._s, function(v)
            local out = {}
            for k = 1, #v do
                local b = v:byte(k)
                if b_is_lower(b)     then out[k] = string.char(b - 32)
                elseif b_is_upper(b) then out[k] = string.char(b + 32)
                else                      out[k] = string.char(b) end
            end
            return table.concat(out)
        end)
    end

    -- join(sep): atalho de :cat — idêntico por compatibilidade de nome.
    function StrProxy:join(sep) return self:cat(sep) end
end
