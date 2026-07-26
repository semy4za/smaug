-- lua/smaug/core/series/_core.lua
--
-- Núcleo da Series: metatype, helpers de fronteira, reduce_num.
-- Recebe I com: I.C, I.ffi, I.DTYPES, I.NA, I.is_nan, I.is_na, I.I64_MIN, I.warn
-- Produz em I: I.Series, I.methods, I.wrap, I.check_index, I.check_value,
--              I.checkrc, I.require_op, I.reduce_num, I.SMG_ERR_NOMEM

local Err        = require("smaug.core.errors")
local int_scalar = require("smaug.core.int_scalar")

return function(I)
    local C      = I.C
    local ffi    = I.ffi
    local DTYPES = I.DTYPES
    local NA     = I.NA
    local is_nan = I.is_nan
    local is_na  = I.is_na
    local warn   = I.warn

    local SMG_ERR_NOMEM = 4   -- espelha smaug_types.h (enum fixo, 0-indexed)
    I.SMG_ERR_NOMEM = SMG_ERR_NOMEM

    -- =====================================================================
    -- Metatype e tabela de métodos
    -- =====================================================================
    local Series = {}
    Series.__index = Series   -- placeholder; sobrescrito no fim pelo init.lua

    local methods = {}

    -- =====================================================================
    -- Construção interna
    -- =====================================================================
    local function wrap(c_ptr, dtype, name, parent)
        if c_ptr == nil then error("smaug: falha ao alocar Series ("..dtype..")", 2) end
        local d = DTYPES[dtype]
        ffi.gc(c_ptr, d.free)
        return setmetatable({
            _c      = c_ptr,
            _d      = d,
            _dtype  = dtype,
            _name   = name or "unnamed",
            _parent = parent,
        }, Series)
    end
    I.wrap = wrap

    -- check_index: descreve o índice via Err.describe — nunca tostring cru.
    -- Um índice não-numérico (ex.: a própria Series, via `s:iat(i)`) dispararia
    -- o __tostring do objeto e despejaria os DADOS na mensagem (item 12.9).
    local function check_index(self, i)
        if type(i) ~= "number" or i < 1 or i > self._c.size or i % 1 ~= 0 then
            error("smaug: índice "..Err.describe(i).." fora dos limites [1, "..
                  tonumber(self._c.size).."]", 3)
        end
    end
    I.check_index = check_index

    -- Fonte única das constantes int64: int_scalar (alias local para os usos abaixo).
    local INT64_MAX_MAG = int_scalar.INT64_MAX_MAG  -- 2^53: teto de precisão exata do double
    local INT64_MAX_U   = int_scalar.INT64_MAX_U    -- teto de int64_t, visto como uint64_t

    local function check_value(self, v, level)
        local dt = self._dtype
        if dt == "int64" then
            -- Reconhecimento pela fonte unica (int_scalar.classify); a POLITICA de
            -- entrada-de-dado fica aqui, inline: number_overflow AVISA-e-aceita (a
            -- Sub-A e irrecuperavel; o valor vira dado do usuario, a escolha e
            -- dele). Os error/warn ficam neste frame -> `level` identico ao
            -- comportamento pre-9.3 (equivalencia, provada por 9.1.1-9.1.3).
            local cls = int_scalar.classify(v)
            if cls == "number_ok" or cls == "number_at_boundary"
               or cls == "cdata_i64" or cls == "cdata_u64_ok" then
                -- forma exata (cdata) ou number ate 2^53: nada a fazer. O boundary
                -- (== 2^53) e aceito sem aviso -> preserva o `> 2^53` pre-9.3 da
                -- entrada (so avisa ACIMA; a operacao e que recusa o boundary).
            elseif cls == "number_overflow" then
                warn("valor " .. tostring(v) .. " para int64 excede 2^53; "
                     .. "literais Lua acima desse limite podem já ter perdido "
                     .. "precisão antes de chegar aqui — use ffi.new(\"int64_t\", ...) "
                     .. "ou o sufixo LL para preservar o valor exato")
            elseif cls == "uint_overflow" then
                error("smaug: valor uint64_t (" .. tostring(v) .. ") excede o "
                      .. "range de int64 (máx " .. tostring(INT64_MAX_U) .. "); "
                      .. "wraparound não é permitido", level or 3)
            else  -- not_integer, invalid
                error("smaug: valor para int64 deve ser inteiro (sem coerção); "
                      .. "recebido " .. tostring(v), level or 3)
            end
        elseif dt == "string" then
            if type(v) ~= "string" then
                error("smaug: valor para string deve ser uma string Lua; "
                      .. "recebido " .. type(v), level or 3)
            end
        elseif dt == "bool" then
            if type(v) ~= "boolean" then
                error("smaug: valor para bool deve ser boolean Lua (true/false); "
                      .. "recebido " .. type(v), level or 3)
            end
        elseif dt == "datetime" then
            if type(v) ~= "number" and type(v) ~= "string" then
                error("smaug: valor para datetime deve ser número (epoch_ms) ou string ISO 8601; "
                      .. "recebido " .. type(v), level or 3)
            end
        else  -- float64
            if type(v) ~= "number" then
                error("smaug: valor para " .. dt .. " deve ser número; "
                      .. "recebido " .. type(v), level or 3)
            end
        end
    end
    I.check_value = check_value

    -- check_int64_lossless (degrau 10.6/10.7): garante que ler o valor int64 do
    -- indice i via get() (tonumber->double) NAO corromperia digitos. Fronteira
    -- unica: o mesmo INT64_MAX_MAG (2^53) do check_value. Le o valor CRU (cdata
    -- int64_t, sem tonumber) so para comparar magnitude -- deteccao, nao conversao.
    -- PALIATIVO: sai quando fillna/astype forem ao Anel 0 (10.6/10.7). Contrato:
    -- chamado so em indice nao-nulo de serie int64. `op` rotula a operacao.
    local function check_int64_lossless(self, i, op)
        if self._dtype ~= "int64" then return end
        local raw = self._d.get(self._c, i - 1, nil)   -- cdata int64_t, sem tonumber
        if raw > INT64_MAX_MAG or raw < -INT64_MAX_MAG then
            error("smaug: " .. op .. " nao preserva o valor int64 " .. tostring(raw)
                  .. " no indice " .. i .. " (excede 2^53; a conversao interna via "
                  .. "double perderia digitos). Suporte a int64 > 2^53 nesta operacao "
                  .. "chega com a vetorizacao (Anel 0).", 3)
        end
    end
    I.check_int64_lossless = check_int64_lossless

    local function checkrc(rc, what)
        if rc == 0 then return end
        if tonumber(rc) == SMG_ERR_NOMEM then
            error("smaug: falha de memória ao materializar view (COW detach)", 3)
        end
        error("smaug: backend "..what.." devolveu status "..tonumber(rc)..
              " (esperado SMG_OK=0); invariante interno violado", 3)
    end
    I.checkrc = checkrc

    -- =====================================================================
    -- require_op e reduce_num
    -- =====================================================================
    local function require_op(self, fn_name, level)
        if self._d[fn_name] == nil then
            error("smaug: operação '" .. fn_name .. "' não se aplica a séries do tipo "
                  .. self._dtype, level or 3)
        end
        return self._d[fn_name]
    end
    I.require_op = require_op

    local function reduce_num(self, fn_name, ignore_na)
        require_op(self, fn_name, 3)
        if ignore_na == nil then ignore_na = true end
        local v = self._d[fn_name](self._c, ignore_na)
        if (fn_name == "sum" or fn_name == "min" or fn_name == "max")
           and self._d.is_int_sentinel(v) then
            return nil
        end
        v = tonumber(v)
        if is_nan(v) then return nil end
        return v
    end
    I.reduce_num = reduce_num

    I.Series  = Series
    I.methods = methods

    return { Series = Series, methods = methods }
end
