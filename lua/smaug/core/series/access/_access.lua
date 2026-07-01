-- lua/smaug/core/series/access/_access.lua
--
-- Acesso elementar e ciclo de vida básico da Series.
-- Recebe I com: I.methods, I.check_index, I.check_value, I.checkrc,
--               I.wrap, I.is_na, I.C
-- Contribui: methods.get, get_raw, set, is_null, set_null, append,
--            count_nonnull, len, size, clone

return function(I)
    local methods      = I.methods
    local check_index  = I.check_index
    local check_value  = I.check_value
    local checkrc      = I.checkrc
    local wrap         = I.wrap
    local is_na        = I.is_na
    local C            = I.C

    -- =====================================================================
    -- Acesso (1-based; nil <-> null)
    -- =====================================================================
    function methods.get(self, i)
        check_index(self, i)
        if self._d.is_null(self._c, i - 1) then return nil end
        return self._d.get_value(self._c, i - 1)
    end

    -- get_raw: só para int64. get() normal passa por tonumber() em get_value,
    -- que converte o int64_t pra double — a MESMA limitação da Sub-A do item
    -- 9.1 (2^53), só que na saída em vez da entrada. get_raw devolve o cdata
    -- int64_t direto do C (self._d.get, sem o wrapper get_value), preservando
    -- os 64 bits para quem precisa do valor exato acima de 2^53 (espelha o
    -- que check_value já aceita na entrada via cdata — vínculo 9.1.1-9.1.3).
    function methods.get_raw(self, i)
        if self._dtype ~= "int64" then
            error("smaug: get_raw() só se aplica a séries int64 (preserva "
                  .. "int64_t cru, sem conversão pra double); dtype é '"
                  .. self._dtype .. "'", 2)
        end
        check_index(self, i)
        if self._d.is_null(self._c, i - 1) then return nil end
        return self._d.get(self._c, i - 1, nil)
    end

    function methods.set(self, i, v)
        check_index(self, i)
        if is_na(v) then
            checkrc(self._d.set_null(self._c, i - 1), "set_null")
        else
            check_value(self, v, 3)
            checkrc(self._d.set(self._c, i - 1, v), "set")
        end
    end

    function methods.is_null(self, i)
        check_index(self, i)
        return self._d.is_null(self._c, i - 1)
    end

    function methods.set_null(self, i)
        check_index(self, i)
        checkrc(self._d.set_null(self._c, i - 1), "set_null")
    end

    function methods.append(self, v)
        local rc
        if is_na(v) then
            rc = self._d.append_null(self._c)
        else
            check_value(self, v, 3)
            rc = self._d.append(self._c, v)
        end
        if rc ~= 0 then error("smaug: append falhou (OOM)", 2) end
        return self   -- chainable
    end

    -- =====================================================================
    -- Tamanho e clone
    -- =====================================================================
    function methods.count_nonnull(self)
        return tonumber(self._d.count_nonnull(self._c))
    end

    -- Tamanho da série. NOTA: `#serie` só chama __len em LuaJIT compat 5.2;
    -- por padrão (5.1) use :len().
    function methods.len(self) return tonumber(self._c.size) end
    methods.size = methods.len

    -- 6.1: dtype singular (par de DataSet:dtypes). Retorna a string do dtype.
    function methods.dtype(self) return self._dtype end

    function methods.clone(self)
        return wrap(self._d.clone(self._c), self._dtype, self._name)
    end
end
