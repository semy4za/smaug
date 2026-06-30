-- lua/smaug/core/series/stats/_reduce.lua
--
-- Reduções core numéricas via descriptores DTYPES.
-- Recebe I com: I.methods, I.reduce_num
-- Contribui: methods.sum, mean, min, max, var, std

return function(I)
    local methods    = I.methods
    local reduce_num = I.reduce_num

    function methods.sum(self, ignore_na, min_count)
        -- 5.5: min_count opt-in. Default (0) preserva soma de vazio/all-null = 0.
        if min_count and min_count > 0 and self:count_nonnull() < min_count then return nil end
        return reduce_num(self, "sum",  ignore_na)
    end
    function methods.mean(self, ignore_na) return reduce_num(self, "mean", ignore_na) end
    -- min/max (7.2b): str e bool retornam valor não-numérico (string/bool), cujo
    -- wrapper no descritor já materializa o valor final ou nil — não passam por
    -- reduce_num (que faria tonumber e quebraria). f64/i64/dt seguem numéricos.
    local function reduce_ordinal(self, fn_name, ignore_na)
        if self._d[fn_name] == nil then
            error("smaug: operação '"..fn_name.."' não se aplica a séries do tipo "
                  ..self._dtype, 3)
        end
        if self._dtype == "string" or self._dtype == "bool" then
            if ignore_na == nil then ignore_na = true end
            return self._d[fn_name](self._c, ignore_na)   -- wrapper → valor|nil
        end
        return reduce_num(self, fn_name, ignore_na)        -- f64/i64/dt
    end
    function methods.min(self, ignore_na)  return reduce_ordinal(self, "min", ignore_na) end
    function methods.max(self, ignore_na)  return reduce_ordinal(self, "max", ignore_na) end
    function methods.var(self, ignore_na)  return reduce_num(self, "var",  ignore_na) end
    function methods.std(self, ignore_na)  return reduce_num(self, "std",  ignore_na) end
end
