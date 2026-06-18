-- lua/smaug/core/series/stats/_reduce.lua
--
-- Reduções core numéricas via descriptores DTYPES.
-- Recebe I com: I.methods, I.reduce_num
-- Contribui: methods.sum, mean, min, max, var, std

return function(I)
    local methods    = I.methods
    local reduce_num = I.reduce_num

    function methods.sum(self, ignore_na)  return reduce_num(self, "sum",  ignore_na) end
    function methods.mean(self, ignore_na) return reduce_num(self, "mean", ignore_na) end
    function methods.min(self, ignore_na)  return reduce_num(self, "min",  ignore_na) end
    function methods.max(self, ignore_na)  return reduce_num(self, "max",  ignore_na) end
    function methods.var(self, ignore_na)  return reduce_num(self, "var",  ignore_na) end
    function methods.std(self, ignore_na)  return reduce_num(self, "std",  ignore_na) end
end
