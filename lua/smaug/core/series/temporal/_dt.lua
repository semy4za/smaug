-- lua/smaug/core/series/temporal/_dt.lua
--
-- SeriesDT: accessor .dt para Series<datetime>. Base + F.3 estendido.
-- SeriesAt: proxy at/iat.
-- Helpers públicos: Series.dt_parse, Series.dt_format, Series.dt_from_parts.
-- Recebe I com: I.Series, I.methods, I.C, I.ffi, I.NA, I.wrap,
--               I.I64_MIN, I.DTYPES (para is_int_sentinel de datetime)
-- Produz em I: I.SeriesDT, I.SeriesAt

return function(I)
    local Series  = I.Series
    local methods = I.methods
    local C       = I.C
    local ffi     = I.ffi
    local NA      = I.NA
    local wrap    = I.wrap

    -- Sentinela i64 central (init.lua). Operações de datetime do Ring 0 devolvem
    -- I64_MIN como valor inválido/overflow; is_int_sentinel é o predicado canônico
    -- (mesmo idioma de reduce_num em _core.lua). Nada de literal cru aqui.
    local I64_MIN         = I.I64_MIN
    local is_int_sentinel = I.DTYPES.datetime.is_int_sentinel

    -- =====================================================================
    -- SeriesDT
    -- =====================================================================
    local SeriesDT = {}
    SeriesDT.__index = SeriesDT
    I.SeriesDT = SeriesDT

    -- Helper: aplica fn(epoch_ms) por elemento → Series<dtype>. Nulos propagam.
    local function dt_component(s, fn)
        local n    = s:len()
        local vals = {}
        for i = 1, n do
            local v = s:get(i)
            if v == nil then
                vals[i] = NA
            else
                local r = fn(v)
                vals[i] = r >= 0 and r or NA
            end
        end
        return Series.from_table(vals, "int64", s._name)
    end

    local function dt_map(self, fn, out_dtype)
        local s    = self._s
        local n    = s:len()
        local vals = {}
        for i = 1, n do
            local v = s:get(i)
            if v == nil then
                vals[i] = NA
            else
                local r = fn(v)
                vals[i] = (r == nil) and NA or r
            end
        end
        return Series.from_table(vals, out_dtype, s._name)
    end

    -- Componentes base (11)
    function SeriesDT:year()    return dt_component(self._s, C.smaug_dt_year)    end
    function SeriesDT:month()   return dt_component(self._s, C.smaug_dt_month)   end
    function SeriesDT:day()     return dt_component(self._s, C.smaug_dt_day)     end
    function SeriesDT:hour()    return dt_component(self._s, C.smaug_dt_hour)    end
    function SeriesDT:minute()  return dt_component(self._s, C.smaug_dt_minute)  end
    function SeriesDT:second()  return dt_component(self._s, C.smaug_dt_second)  end
    function SeriesDT:ms()      return dt_component(self._s, C.smaug_dt_ms)      end
    function SeriesDT:weekday() return dt_component(self._s, C.smaug_dt_weekday) end
    function SeriesDT:yearday() return dt_component(self._s, C.smaug_dt_yearday) end
    function SeriesDT:quarter() return dt_component(self._s, C.smaug_dt_quarter) end
    function SeriesDT:week()    return dt_component(self._s, C.smaug_dt_week)    end

    -- format(): epoch_ms → ISO 8601 → Series<string>
    function SeriesDT:format()
        local s    = self._s
        local n    = s:len()
        local vals = {}
        local buf  = ffi.new("char[26]")
        for i = 1, n do
            local v = s:get(i)
            if v == nil then
                vals[i] = NA
            else
                C.smaug_dt_format(v, buf, 26)
                vals[i] = ffi.string(buf)
            end
        end
        return Series.from_table(vals, "string", s._name)
    end

    -- truncate(unit): trunca para o início do período. unit: 's' 'm' 'h' 'D' 'W' 'M' 'Q' 'Y'
    function SeriesDT:truncate(unit)
        if type(unit) ~= "string" or #unit ~= 1 then
            error("smaug: dt:truncate() espera uma letra de unidade ('D','M','Y',...)", 2)
        end
        local s    = self._s
        local n    = s:len()
        local vals = {}
        local u    = string.byte(unit)
        for i = 1, n do
            local v = s:get(i)
            if v == nil then
                vals[i] = NA
            else
                local r = C.smaug_dt_truncate(v, u)
                vals[i] = is_int_sentinel(r) and NA or tonumber(r)
            end
        end
        return Series.from_table(vals, "datetime", s._name)
    end

    -- diff(): diferença em ms entre elemento i e i-periods → Series<int64>
    function SeriesDT:diff(periods)
        periods = periods or 1
        local s    = self._s
        local n    = s:len()
        local vals = {}
        for i = 1, n do
            if i <= periods then
                vals[i] = NA
            else
                local a = s:get(i)
                local b = s:get(i - periods)
                vals[i] = (a ~= nil and b ~= nil) and tonumber(C.smaug_dt_diff_ms(a, b)) or NA
            end
        end
        return Series.from_table(vals, "int64", s._name)
    end

    -- add_ms(delta_ms): adiciona delta em ms → Series<datetime>
    function SeriesDT:add_ms(delta_ms)
        if type(delta_ms) ~= "number" then
            error("smaug: dt:add_ms() espera número", 2)
        end
        local s    = self._s
        local n    = s:len()
        local vals = {}
        for i = 1, n do
            local v = s:get(i)
            if v == nil then
                vals[i] = NA
            else
                local r = C.smaug_dt_add_ms(v, delta_ms)
                vals[i] = is_int_sentinel(r) and NA or tonumber(r)
            end
        end
        return Series.from_table(vals, "datetime", s._name)
    end

    function SeriesDT:add_days(n)    return self:add_ms(n * 86400000)  end
    function SeriesDT:add_hours(n)   return self:add_ms(n * 3600000)   end
    function SeriesDT:add_minutes(n) return self:add_ms(n * 60000)     end
    function SeriesDT:add_seconds(n) return self:add_ms(n * 1000)      end

    -- =====================================================================
    -- F.3 — .dt estendido: predicados, nomes, arredondamento
    -- =====================================================================


    local MONTH_NAMES = {
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    }
    local DAY_NAMES = {
        [0]="Monday",[1]="Tuesday",[2]="Wednesday",[3]="Thursday",
        [4]="Friday",[5]="Saturday",[6]="Sunday",
    }

    local function leap(y)
        return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
    end

    local MDAYS = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    local function days_in(y, m)
        if m == 2 and leap(y) then return 29 end
        return MDAYS[m]
    end

    -- Predicados de período
    function SeriesDT:is_month_start()
        return dt_map(self, function(v) return C.smaug_dt_day(v) == 1 end, "bool")
    end
    function SeriesDT:is_month_end()
        return dt_map(self, function(v)
            local y, m, d = C.smaug_dt_year(v), C.smaug_dt_month(v), C.smaug_dt_day(v)
            return d == days_in(y, m)
        end, "bool")
    end
    function SeriesDT:is_quarter_start()
        return dt_map(self, function(v)
            local m, d = C.smaug_dt_month(v), C.smaug_dt_day(v)
            return d == 1 and (m == 1 or m == 4 or m == 7 or m == 10)
        end, "bool")
    end
    function SeriesDT:is_quarter_end()
        return dt_map(self, function(v)
            local y, m, d = C.smaug_dt_year(v), C.smaug_dt_month(v), C.smaug_dt_day(v)
            return d == days_in(y, m) and (m == 3 or m == 6 or m == 9 or m == 12)
        end, "bool")
    end
    function SeriesDT:is_year_start()
        return dt_map(self, function(v)
            return C.smaug_dt_month(v) == 1 and C.smaug_dt_day(v) == 1
        end, "bool")
    end
    function SeriesDT:is_year_end()
        return dt_map(self, function(v)
            return C.smaug_dt_month(v) == 12 and C.smaug_dt_day(v) == 31
        end, "bool")
    end
    function SeriesDT:is_leap_year()
        return dt_map(self, function(v) return leap(C.smaug_dt_year(v)) end, "bool")
    end
    function SeriesDT:days_in_month()
        return dt_map(self, function(v)
            return days_in(C.smaug_dt_year(v), C.smaug_dt_month(v))
        end, "int64")
    end

    -- Nomes
    function SeriesDT:month_name()
        return dt_map(self, function(v) return MONTH_NAMES[C.smaug_dt_month(v)] end, "string")
    end
    function SeriesDT:day_name()
        return dt_map(self, function(v) return DAY_NAMES[C.smaug_dt_weekday(v)] end, "string")
    end

    -- normalize: zera a hora (= truncate("D"))
    function SeriesDT:normalize() return self:truncate("D") end

    -- next_period: início do próximo período após um epoch_ms já truncado
    local function next_period(floor_ms, unit)
        if unit == "Y" then
            local y = C.smaug_dt_year(floor_ms)
            return C.smaug_dt_from_parts(y + 1, 1, 1, 0, 0, 0, 0)
        elseif unit == "Q" then
            local y, m = C.smaug_dt_year(floor_ms), C.smaug_dt_month(floor_ms)
            local nm = m + 3
            if nm > 12 then nm = nm - 12; y = y + 1 end
            return C.smaug_dt_from_parts(y, nm, 1, 0, 0, 0, 0)
        elseif unit == "M" then
            local y, m = C.smaug_dt_year(floor_ms), C.smaug_dt_month(floor_ms)
            local nm = m + 1
            if nm > 12 then nm = 1; y = y + 1 end
            return C.smaug_dt_from_parts(y, nm, 1, 0, 0, 0, 0)
        elseif unit == "W" then return C.smaug_dt_add_ms(floor_ms, 7 * 86400000)
        elseif unit == "D" then return C.smaug_dt_add_ms(floor_ms, 86400000)
        elseif unit == "h" then return C.smaug_dt_add_ms(floor_ms, 3600000)
        elseif unit == "m" then return C.smaug_dt_add_ms(floor_ms, 60000)
        elseif unit == "s" then return C.smaug_dt_add_ms(floor_ms, 1000)
        end
        return I64_MIN
    end

    local VALID_UNITS = { s=true, m=true, h=true, D=true, W=true, M=true, Q=true, Y=true }

    function SeriesDT:ceil(unit)
        if type(unit) ~= "string" or not VALID_UNITS[unit] then
            error("smaug: dt:ceil() unidade inválida (use s/m/h/D/W/M/Q/Y)", 2)
        end
        local u = string.byte(unit)
        return dt_map(self, function(v)
            local floor = C.smaug_dt_truncate(v, u)
            if is_int_sentinel(floor) then return nil end
            if floor == v then return tonumber(v) end
            local nxt = next_period(floor, unit)
            if is_int_sentinel(nxt) then return nil end
            return tonumber(nxt)
        end, "datetime")
    end

    function SeriesDT:round(unit)
        if type(unit) ~= "string" or not VALID_UNITS[unit] then
            error("smaug: dt:round() unidade inválida (use s/m/h/D/W/M/Q/Y)", 2)
        end
        local u = string.byte(unit)
        return dt_map(self, function(v)
            local floor = C.smaug_dt_truncate(v, u)
            if is_int_sentinel(floor) then return nil end
            local nxt = next_period(floor, unit)
            if is_int_sentinel(nxt) then return nil end
            local to_floor = tonumber(C.smaug_dt_diff_ms(v, floor))
            local to_next  = tonumber(C.smaug_dt_diff_ms(nxt, v))
            if to_floor < to_next then
                return tonumber(floor)
            else
                return tonumber(nxt)
            end
        end, "datetime")
    end

    -- strftime
    local ABBR_MONTH = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
    local ABBR_DAY   = {[0]="Mon",[1]="Tue",[2]="Wed",[3]="Thu",[4]="Fri",[5]="Sat",[6]="Sun"}

    function SeriesDT:strftime(fmt)
        if type(fmt) ~= "string" then
            error("smaug: dt:strftime() espera string de formato", 2)
        end
        return dt_map(self, function(v)
            local Y  = C.smaug_dt_year(v)
            local mo = C.smaug_dt_month(v)
            local d  = C.smaug_dt_day(v)
            local H  = C.smaug_dt_hour(v)
            local Mi = C.smaug_dt_minute(v)
            local Se = C.smaug_dt_second(v)
            local j  = C.smaug_dt_yearday(v)
            local wd = C.smaug_dt_weekday(v)
            local h12 = H % 12; if h12 == 0 then h12 = 12 end
            local subst = {
                Y = string.format("%04d", Y),
                y = string.format("%02d", Y % 100),
                m = string.format("%02d", mo),
                d = string.format("%02d", d),
                H = string.format("%02d", H),
                M = string.format("%02d", Mi),
                S = string.format("%02d", Se),
                j = string.format("%03d", j),
                I = string.format("%02d", h12),
                p = (H < 12) and "AM" or "PM",
                B = MONTH_NAMES[mo],
                b = ABBR_MONTH[mo],
                A = DAY_NAMES[wd],
                a = ABBR_DAY[wd],
                ["%"] = "%",
            }
            return (fmt:gsub("%%(.)", function(c)
                local r = subst[c]
                if r ~= nil then return r end
                return "%" .. c
            end))
        end, "string")
    end

    -- =====================================================================
    -- SeriesAt: proxy at/iat
    -- =====================================================================
    local SeriesAt = {
        __index = function(self, i)
            if type(i) ~= "number" then
                error("smaug: at/iat espera índice numérico (1-based)", 2)
            end
            return methods.get(self._s, i)
        end,
        __call = function(self, i)
            return methods.get(self._s, i)
        end,
    }
    I.SeriesAt = SeriesAt

    -- =====================================================================
    -- Helpers públicos
    -- =====================================================================

    function Series.dt_parse(str, dayfirst)
        if type(str) ~= "string" then
            error("smaug: Series.dt_parse() espera string", 2)
        end
        local df = dayfirst and 1 or 0
        local ep = ffi.new("int64_t[1]")
        if C.smaug_dt_parse(str, #str, ep, df) ~= 0 then return nil end
        return tonumber(ep[0])
    end

    function Series.dt_format(epoch_ms)
        local buf = ffi.new("char[26]")
        if C.smaug_dt_format(epoch_ms, buf, 26) ~= 0 then return nil end
        return ffi.string(buf)
    end

    function Series.dt_from_parts(year, month, day, hour, minute, second, ms)
        hour = hour or 0; minute = minute or 0; second = second or 0; ms = ms or 0
        local r = C.smaug_dt_from_parts(year, month, day, hour, minute, second, ms)
        if is_int_sentinel(r) then return nil end
        return tonumber(r)
    end

    -- Reservado no methods; resolvido via __index no init.lua
    methods.dt = nil
end
