-- lua/smaug/core/series/access/_transform.lua
--
-- Transformações elementares: sort, view, take, astype, fillna, map, abs, round, clip.
-- Recebe I com: I.methods, I.Series, I.wrap, I.DTYPES, I.ffi, I.C,
--               I.NA, I.is_na, I.is_nan, I.infer_dtype_from_value,
--               (I.check_int64_lossless foi aposentado no 10.3)
-- Contribui: methods.sort, argsort, view, take, dropna, head, tail,
--            to_table, astype, fillna, map, abs, round, clip

local Display = require("smaug.core.display")
local Err     = require("smaug.core.errors")
local int_scalar = require("smaug.core.int_scalar")   -- fronteira do escalar (9.3)

return function(I)
    local methods = I.methods
    local Series  = I.Series
    local wrap    = I.wrap
    local DTYPES  = I.DTYPES
    local ffi     = I.ffi
    local C       = I.C
    local NA      = I.NA
    local is_na   = I.is_na
    local check_value = I.check_value                     -- porteiro canônico (9.1)
    -- (o degrau `check_int64_lossless` foi APOSENTADO no 10.3: era importado
    --  aqui para abs/round/clip, que desceram ao Anel 0 e passaram a fazer
    --  aritmética inteira pura. Sem consumidor, saiu também do _core.lua.)

    -- =====================================================================
    -- astype: matriz de conversão src×dst delegada ao Anel 0 (10.7 Passo B).
    -- Tabela explícita [src][dst] -> primitiva C (diagonal usa clone; pares
    -- com bool/categorical ficam no Anel 1 até 10.8). str->dt recebe dayfirst.
    -- =====================================================================
    local ASTYPE_C = {
        int64    = { float64  = C.smaug_i64_to_f64,
                     string   = C.smaug_i64_to_str,
                     datetime = C.smaug_i64_to_dt  },
        float64  = { int64    = C.smaug_f64_to_i64,
                     string   = C.smaug_f64_to_str,
                     datetime = C.smaug_f64_to_dt  },
        string   = { int64    = C.smaug_str_to_i64,
                     float64  = C.smaug_str_to_f64,
                     datetime = C.smaug_str_to_dt  },
        datetime = { int64    = C.smaug_dt_to_i64,
                     float64  = C.smaug_dt_to_f64,
                     string   = C.smaug_dt_to_str  },
    }

    -- =====================================================================
    -- Ordenação
    -- =====================================================================
    function methods.sort(self, ascending)
        if ascending == nil then ascending = true end
        local r = self._d.sort(self._c, ascending)
        if r == nil then
            error("smaug: sort não suporta séries com nulos (use dropna primeiro)", 2)
        end
        return wrap(r, self._dtype, self._name)
    end

    -- argsort: tabela Lua 1-based de índices que ordenam a série.
    -- Devolve nil se a série contém nulos. Usado por DataSet:sort_by.
    function methods.argsort(self, ascending)
        if ascending == nil then ascending = true end
        local p = self._d.argsort(self._c, ascending)
        if p == nil then return nil end
        local n   = self:len()
        local idx = {}
        for i = 1, n do idx[i] = tonumber(p[i - 1]) + 1 end   -- 0-based → 1-based
        C.smaug_free(p)
        return idx
    end

    -- =====================================================================
    -- View e Take
    -- =====================================================================

    -- view: fatia zero-copy [start, start+len-1] (1-based).
    function methods.view(self, start, len)
        if self._d.view == nil then
            error("smaug: view() não é suportado para dtype '"..self._dtype..
                  "'; use :take(idx) ou :head(n)/:tail(n) para uma cópia", 2)
        end
        start = start or 1
        len   = len or (self:len() - start + 1)
        local n = self:len()
        if type(start) ~= "number" or type(len) ~= "number"
           or start < 1 or len < 0 or start + len - 1 > n then
            error("smaug: view("..Err.describe(start)..", "..Err.describe(len)..
                  ") fora dos limites [1, "..n.."]", 2)
        end
        local r = self._d.view(self._c, start - 1, len)
        return wrap(r, self._dtype, self._name, self._parent or self)
    end

    -- take: nova série (cópia independente) com os elementos nas posições idx.
    function methods.take(self, idx)
        if type(idx) ~= "table" then error("smaug: take espera uma tabela de índices", 2) end
        local n   = self:len()
        local len = #idx
        local cidx = ffi.new("size_t[?]", len)
        for i = 1, len do
            local k = idx[i]
            if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
                error("smaug: take índice "..Err.describe(k).." fora dos limites [1, "..n.."]", 2)
            end
            cidx[i - 1] = k - 1
        end
        local r = self._d.take(self._c, cidx, len)
        if r == nil then error("smaug: take falhou", 2) end
        return wrap(r, self._dtype, self._name)
    end

    -- dropna: nova série sem elementos NULL.
    function methods.dropna(self)
        local n   = self:len()
        local idx = {}
        local j   = 0
        for i = 1, n do
            if not self:is_null(i) then j = j + 1; idx[j] = i end
        end
        return self:take(idx)
    end

    -- head/tail: cópia das primeiras/últimas n linhas.
    function methods.head(self, n)
        n = math.min(n or 5, self:len())
        local idx = {}
        for i = 1, n do idx[i] = i end
        return self:take(idx)
    end

    function methods.tail(self, n)
        local total = self:len()
        n = math.min(n or 5, total)
        local idx = {}
        for i = 1, n do idx[i] = total - n + i end
        return self:take(idx)
    end

    -- to_table: converte para tabela Lua. Nulos → na_value (default nil).
    function methods.to_table(self, na_value)
        local t = {}
        for i = 1, self:len() do
            local v = self:get(i)
            if v == nil then v = na_value end
            t[i] = v
        end
        return t
    end

    -- =====================================================================
    -- 6.3 — pares do DataSet: sample / to_string / to_markdown
    -- =====================================================================

    -- sample(n, [seed]): amostra n elementos sem reposição (Fisher-Yates parcial).
    -- Espelha DataSet:sample (take de índices), com len no lugar de nrows.
    function methods.sample(self, n, seed)
        local total = self:len()
        n = math.min(n or 1, total)
        if seed ~= nil then math.randomseed(seed) end
        local perm = {}
        for i = 1, total do perm[i] = i end
        for i = 1, n do
            local j = math.random(i, total)
            perm[i], perm[j] = perm[j], perm[i]
        end
        local idx = {}
        for i = 1, n do idx[i] = perm[i] end
        return self:take(idx)
    end

    -- to_string([opts]): texto plano, índice + valor. opts.max_rows limita.
    -- Formatação e largura vêm do módulo display (fonte única).
    function methods.to_string(self, opts)
        opts = opts or {}
        local n     = self:len()
        local name  = self._name or "value"
        local align = Display.align_for(self._dtype)
        local idx, brk = Display.plan_rows(n, opts.max_rows)
        local w     = Display.dwidth(name)
        local cells = {}
        for _, i in ipairs(idx) do
            local s = Display.cell_str(Display.cell_of(self, i)); cells[i] = s
            local dw = Display.dwidth(s)
            if dw > w then w = dw end
        end
        local idxw = math.max(#tostring(n > 0 and n or 1), 1)
        local out = { Display.pad("", idxw) .. "  " .. name }
        for pos, i in ipairs(idx) do
            out[#out + 1] = Display.pad(tostring(i), idxw) .. "  " .. Display.pad(cells[i], w, align)
            if brk and pos == brk then
                out[#out + 1] = Display.pad("...", idxw) .. "  " .. Display.pad("...", w, align)
            end
        end
        return table.concat(out, "\n")
    end

    -- to_markdown(): tabela Markdown de 1 coluna (sem índice, como DataSet:to_markdown).
    function methods.to_markdown(self)
        local n    = self:len()
        local name = self._name or "value"
        local align = Display.align_for(self._dtype)
        local w    = Display.dwidth(name)
        local cells = {}
        for i = 1, n do
            local s = Display.cell_str(Display.cell_of(self, i)); cells[i] = s
            local dw = Display.dwidth(s)
            if dw > w then w = dw end
        end
        local out = {}
        out[#out + 1] = "| " .. Display.pad(name, w) .. " |"
        out[#out + 1] = "| " .. string.rep("-", w) .. " |"
        for i = 1, n do out[#out + 1] = "| " .. Display.pad(cells[i], w, align) .. " |" end
        return table.concat(out, "\n")
    end

    -- =====================================================================
    -- astype
    -- =====================================================================

    -- astype(dtype): converte a série para outro dtype. Tolerante por elemento:
    -- inconversíveis → null. Nunca descarta a série inteira.
    function methods.astype(self, dtype, name)
        -- 3º argumento: string = name (retrocompat) | tabela = {name=, dayfirst=}
        local dayfirst = 0
        if type(name) == "table" then
            local opts = name
            name = opts.name
            if opts.dayfirst == true then dayfirst = 1
            elseif opts.dayfirst == false then dayfirst = 0 end
        end

        -- categorical é Lua puro — não está em DTYPES, mas é suportado
        if dtype == "categorical" then
            local Cat = Series.Categorical
            if not Cat then
                error("smaug: astype 'categorical' — CategoricalSeries não disponível", 2)
            end
            local vals = {}
            local n    = self:len()
            for i = 1, n do
                local v = self:get(i)
                vals[i] = v ~= nil and tostring(v) or NA
            end
            return Cat.from_table(vals, name or self._name)
        end
        if not DTYPES[dtype] then
            error("smaug: dtype desconhecido " .. Err.describe(dtype), 2)
        end

        local src = self._dtype

        -- Zona 1 — mesmo dtype: clone (Anel 0). Sem round-trip por get():
        -- int64 > 2^53 preservado exato (o degrau some).
        if src == dtype then
            return wrap(self._d.clone(self._c), dtype, name or self._name)
        end

        -- Zona 2 — matriz C (src×dst entre int64/float64/string/datetime).
        local row  = ASTYPE_C[src]
        local conv = row and row[dtype]
        if conv then
            local r
            if src == "string" and dtype == "datetime" then
                r = conv(self._c, dayfirst)
            else
                r = conv(self._c)
            end
            return wrap(r, dtype, name or self._name)
        end

        -- Zona 3 — cantos datetime<->bool: sem semântica natural, erro limpo.
        if (src == "bool" and dtype == "datetime")
        or (src == "datetime" and dtype == "bool") then
            error("smaug: astype " .. src .. "->" .. dtype ..
                  " não suportado; use :map(fn) para definir a regra", 2)
        end

        -- Zona 4 — pares com bool (bool<->int64/float64/string): Anel 1 até 10.8.
        -- Loop reduzido: só os ramos que envolvem bool.
        local n   = self:len()
        local out = Series.new(dtype, n, name or self._name)
        for i = 1, n do
            local v = self:get(i)
            if v == nil then
                out:set_null(i)
            elseif src == "bool" then          -- bool -> int64/float64/string
                if dtype == "string" then
                    out:set(i, tostring(v))
                elseif dtype == "int64" then
                    out:set(i, v and 1 or 0)
                else -- float64
                    out:set(i, v and 1.0 or 0.0)
                end
            else                                -- int64/float64/string -> bool
                if src == "string" then
                    if v == "true" then out:set(i, true)
                    elseif v == "false" then out:set(i, false)
                    else out:set_null(i) end
                else  -- int64/float64 -> bool: rígido, só 0/1 (H.6.5.a)
                    if v == 0 or v == 1 then
                        out:set(i, v == 1)
                    else
                        error("smaug: astype('bool'): valor " .. Err.describe(v) .. " no índice "
                              .. i .. " não é 0/1; use :map(fn) para definir a regra", 2)
                    end
                end
            end
        end
        return out
    end

    -- =====================================================================
    -- fillna
    -- =====================================================================

    -- fillna: nova Series com cada NULL substituído por value.
    -- Sem coerção de tipo. NaN é valor presente — fica intacto.
    function methods.fillna(self, value)
        if value == nil or value == NA then
            error("smaug: fillna requer um valor de preenchimento", 2)
        end
        local dt = self._dtype

        -- bool (10.8): guarda de tipo + Anel 0 (smaug_bool_coalesce_scalar).
        -- value normalizado a 0/1 na fronteira FFI — não depende de coerção
        -- implícita boolean→número do LuaJIT. Sem loop/travessia por elemento.
        if dt == "bool" then
            if type(value) ~= "boolean" then
                error("smaug: fillna em série bool espera boolean (true/false); "
                      .. "recebido " .. type(value), 2)
            end
            return wrap(self._d.coalesce_scalar(self._c, value and 1 or 0), dt, self._name)
        end

        -- datetime restrito a number (epoch_ms) nesta leva; string ISO → 12.16.
        if dt == "datetime" and type(value) ~= "number" then
            error("smaug: fillna em série datetime espera número (epoch_ms); "
                  .. "recebido " .. type(value) .. " (string ISO ainda não; ver 12.16)", 2)
        end

        -- Anel 0: valida o value uma vez pelo porteiro canônico (aceita cdata
        -- int64, curando a antiga desparidade) e delega a coalesce_scalar. Sem
        -- round-trip por get() → int64 > 2^53 preservado exato (degrau sai).
        check_value(self, value, 3)
        local r
        if dt == "string" then
            r = self._d.coalesce_scalar(self._c, value, #value)
        else
            r = self._d.coalesce_scalar(self._c, value)
        end
        return wrap(r, dt, self._name)
    end

    -- =====================================================================
    -- map
    -- =====================================================================

    -- infer_from_value: reusa a fonte única definida em _factories.lua (Bloco H,
    -- H.2/H.6) em vez de uma cópia local incompleta. H.6.6.1: antes não
    -- reconhecia boolean — map(fn) com retorno true/false falhava mesmo com
    -- dtype="bool" explícito, porque o valor era rejeitado aqui antes de
    -- chegar no check_map_value que respeitaria o dtype declarado.
    local infer_from_value = I.infer_dtype_from_value

    local function check_map_value(v, dtype, i)
        if dtype == "int64" then
            if type(v) ~= "number" or v % 1 ~= 0 then
                error("smaug: map: tipo inconsistente no índice " .. i
                      .. " (esperado int64, recebido " .. type(v) .. ")", 4)
            end
        elseif dtype == "string" then
            if type(v) ~= "string" then
                error("smaug: map: tipo inconsistente no índice " .. i
                      .. " (esperado string, recebido " .. type(v) .. ")", 4)
            end
        elseif dtype == "bool" then
            if type(v) ~= "boolean" then
                error("smaug: map: tipo inconsistente no índice " .. i
                      .. " (esperado bool, recebido " .. type(v) .. ")", 4)
            end
        else  -- float64
            if type(v) ~= "number" then
                error("smaug: map: tipo inconsistente no índice " .. i
                      .. " (esperado float64, recebido " .. type(v) .. ")", 4)
            end
        end
    end

    -- map(fn, dtype?): aplica fn a cada elemento, devolvendo nova Series.
    -- nil retornado → null. dtype omitido → inferido do 1º retorno não-null.
    function methods.map(self, fn, dtype, name)
        if type(fn) ~= "function" then
            error("smaug: map espera uma função como 1º argumento", 2)
        end
        if dtype ~= nil and not DTYPES[dtype] then
            error("smaug: map: dtype desconhecido " .. Err.describe(dtype), 2)
        end

        local n       = self:len()
        local results = {}
        local inferred = dtype

        for i = 1, n do
            local v = self:get(i)
            local r = fn(v, i)
            if r == nil or r == NA then
                results[i] = nil
            else
                local rt = infer_from_value(r)
                if rt == nil then
                    error("smaug: map: retorno de tipo não suportado no índice "
                          .. i .. " (" .. type(r) .. ")", 2)
                end
                if inferred == nil then
                    inferred = rt
                else
                    check_map_value(r, inferred, i)
                end
                results[i] = r
            end
        end

        if inferred == nil then
            error("smaug: map: todos os retornos são nil — informe dtype explicitamente", 2)
        end

        local out = Series.new(inferred, n, name or self._name)
        for i = 1, n do
            if results[i] == nil then
                out:set_null(i)
            else
                out:set(i, results[i])
            end
        end
        return out
    end

    -- =====================================================================
    -- abs, round, clip → Anel 0 (10.3 fatia B)
    -- =====================================================================
    -- As três preservam o dtype, e é por isso que têm versão int64 em C. Antes
    -- passavam por `map` → `get()` → double: acima de 2^53 perdiam dígito EM
    -- SILÊNCIO (abs(-9007199254740993) devolvia 9007199254740992), e o degrau
    -- `check_i64` trocava a corrupção calada por falha visível. Com a descida,
    -- a aritmética é inteira pura e o suporte virou real — o degrau saiu.
    --
    -- Três casos ganharam resposta explícita, todos via smaug_status_t:
    --   abs(INT64_MIN)  — não tem contrapartida positiva em int64
    --   clip(lo > hi)   — faixa contraditória (antes devolvia algo fora de
    --                     qualquer faixa: {1,5,9}:clip(8,2) dava {8,8,2})
    --   round(int64)    — |ndigits| >= 19, ou resultado fora da faixa
    local function check_status(st, op, extra)
        if st[0] ~= C.SMG_OK then
            error("smaug: " .. op .. "() " .. extra, 3)
        end
    end

    function methods.abs(self)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: abs() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        if self._dtype == "float64" then
            local r = C.smaug_f64_abs(self._c)
            if r == nil then error("smaug: abs() falhou", 2) end
            return wrap(r, "float64", self._name)
        end
        local st = ffi.new("smaug_status_t[1]")
        local r  = C.smaug_i64_abs(self._c, st)
        if r == nil then
            check_status(st, "abs",
                "não tem resposta para INT64_MIN (-9223372036854775808): "
                .. "o valor não tem contrapartida positiva em int64")
            error("smaug: abs() falhou", 2)
        end
        return wrap(r, "int64", self._name)
    end

    -- round: em int64 com ndigits >= 0 a operação é IDENTIDADE — inteiro não
    -- tem casas decimais. Isso preserva o dtype (antes devolvia float64, o que
    -- degradava > 2^53 justamente na operação que este item conserta). Com
    -- ndigits < 0 arredonda casas antes da vírgula: round(1234, -2) = 1200.
    function methods.round(self, ndigits)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: round() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        ndigits = ndigits or 0
        if self._dtype == "float64" then
            local r = C.smaug_f64_round(self._c, ndigits)
            if r == nil then error("smaug: round() falhou", 2) end
            return wrap(r, "float64", self._name)
        end
        local st = ffi.new("smaug_status_t[1]")
        local r  = C.smaug_i64_round(self._c, ndigits, st)
        if r == nil then
            check_status(st, "round",
                "não conseguiu arredondar em int64 com ndigits=" .. ndigits
                .. ": o fator 10^" .. math.abs(ndigits) .. " ou o resultado "
                .. "excede a faixa de int64")
            error("smaug: round() falhou", 2)
        end
        return wrap(r, "int64", self._name)
    end

    function methods.clip(self, lo, hi)
        if self._dtype ~= "float64" and self._dtype ~= "int64" then
            error("smaug: clip() requer dtype numérico, não '"..self._dtype.."'", 2)
        end
        if lo == nil and hi == nil then return self:clone() end
        local has_lo, has_hi = lo ~= nil, hi ~= nil
        local st = ffi.new("smaug_status_t[1]")
        local r
        if self._dtype == "float64" then
            r = C.smaug_f64_clip(self._c, has_lo and lo or 0, has_lo,
                                          has_hi and hi or 0, has_hi, st)
        else
            -- limites int64 pela fronteira do escalar (9.3): cdata exato
            -- aceito, number >= 2^53 recusado por origem — senão o valor da
            -- série ficaria exato e o limite viria degradado.
            local clo = has_lo and int_scalar.check_operation(lo, "clip (limite inferior)", 4) or 0
            local chi = has_hi and int_scalar.check_operation(hi, "clip (limite superior)", 4) or 0
            r = C.smaug_i64_clip(self._c, clo, has_lo, chi, has_hi, st)
        end
        if r == nil then
            check_status(st, "clip",
                "recebeu faixa contraditória (lo > hi): não existe valor que "
                .. "satisfaça os dois limites")
            error("smaug: clip() falhou", 2)
        end
        return wrap(r, self._dtype, self._name)
    end
end
