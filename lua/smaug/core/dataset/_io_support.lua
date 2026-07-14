-- lua/smaug/core/dataset/_io_support.lua
--
-- F.5 acesso escalar, I/O e pretty-print estendido.
-- Recebe I com: I.Series, I.DataSet, I.methods,
--               I.is_series, I.is_boolseries, I.is_categorical
-- Contribui: methods.at, iat, insert, to_dict, DataSet.from_dict,
--            methods.to_markdown, to_string

local Display = require("smaug.core.display")

return function(I)
    local Series        = I.Series
    local DataSet       = I.DataSet
    local methods       = I.methods
    local is_series     = I.is_series
    local is_boolseries = I.is_boolseries
    local is_categorical = I.is_categorical

    -- =====================================================================
    -- F.5 — Acesso escalar
    -- =====================================================================

    -- at(i, col): célula única por nome de coluna.
    function methods.at(self, i, col)
        if type(col) ~= "string" then
            error("smaug: df:at(i, col) — col deve ser nome de coluna (string)", 2)
        end
        local c = self._columns[col]
        if c == nil then error("smaug: coluna '"..tostring(col).."' não existe", 2) end
        return c:get(i)
    end

    -- iat(i, ci): célula única por índice posicional de coluna (1-based).
    function methods.iat(self, i, ci)
        if type(ci) ~= "number" or ci < 1 or ci > #self._col_names then
            error("smaug: df:iat(i, ci) — ci fora dos limites [1, "..#self._col_names.."]", 2)
        end
        return self._columns[self._col_names[ci]]:get(i)
    end

    -- insert(loc, name, series): insere coluna na posição loc (1-based).
    function methods.insert(self, loc, name, series)
        if type(loc) ~= "number" or loc < 1 or loc > #self._col_names + 1 then
            error("smaug: df:insert — loc fora dos limites [1, "..(#self._col_names+1).."]", 2)
        end
        if type(name) ~= "string" then
            error("smaug: df:insert — name deve ser string", 2)
        end
        if self._columns[name] ~= nil then
            error("smaug: coluna '"..name.."' já existe", 2)
        end
        if not (is_series(series) or is_boolseries(series) or is_categorical(series)) then
            error("smaug: df:insert espera uma Series", 2)
        end
        local n = series:len()
        if self._length == nil then
            self._length = n
        elseif n ~= self._length then
            error("smaug: coluna '"..name.."' tem "..n.." linhas; esperado "..self._length, 2)
        end
        self._columns[name] = series
        table.insert(self._col_names, loc, name)
        return self
    end

    -- =====================================================================
    -- to_dict / from_dict
    -- =====================================================================

    function methods.to_dict(self, orient)
        orient = orient or "columns"
        if orient == "columns" then
            return self:to_table()
        elseif orient == "records" then
            local out = {}
            for i = 1, self:nrows() do
                out[i] = self:row(i)
            end
            return out
        end
        error("smaug: to_dict orient ∈ {columns, records}", 2)
    end

    function DataSet.from_dict(t, orient)
        orient = orient or "columns"
        if type(t) ~= "table" then error("smaug: from_dict espera tabela", 2) end

        local function infer_and_build(name, values, n)
            local seen_num, seen_float, seen_bool, seen_str = false, false, false, false
            for i = 1, n do
                local v = values[i]
                if v ~= nil and v ~= Series.NA then
                    local tv = type(v)
                    if tv == "boolean" then seen_bool = true
                    elseif tv == "number" then
                        seen_num = true
                        if v % 1 ~= 0 then seen_float = true end
                    elseif tv == "string" then seen_str = true end
                end
            end
            local dtype
            if seen_str then dtype = "string"
            elseif seen_bool and not seen_num then dtype = "bool"
            elseif seen_float then dtype = "float64"
            elseif seen_num then dtype = "int64"
            else dtype = "string" end
            local vals = {}
            for i = 1, n do
                local v = values[i]
                vals[i] = (v == nil) and Series.NA or v
            end
            return Series.from_table(vals, dtype, name)
        end

        local df = DataSet.new("from_dict")
        if orient == "columns" then
            local order = t._order
            if order == nil then
                order = {}
                for k in pairs(t) do
                    if k ~= "_order" then order[#order + 1] = k end
                end
                table.sort(order)
            end
            for _, name in ipairs(order) do
                local values = t[name]
                df:add_column(name, infer_and_build(name, values, #values))
            end
            return df
        elseif orient == "records" then
            local order, seen = {}, {}
            for _, rec in ipairs(t) do
                for k in pairs(rec) do
                    if not seen[k] then seen[k] = true; order[#order + 1] = k end
                end
            end
            local nrows = #t
            for _, name in ipairs(order) do
                local values = {}
                for i = 1, nrows do values[i] = t[i][name] end
                df:add_column(name, infer_and_build(name, values, nrows))
            end
            return df
        end
        error("smaug: from_dict orient ∈ {columns, records}", 2)
    end

    -- =====================================================================
    -- Pretty-print estendido
    -- =====================================================================

    -- to_markdown(): tabela em formato Markdown. Inclui todas as linhas.
    -- Formatação/largura/alinhamento via módulo display (fonte única).
    function methods.to_markdown(self)
        local names = self._col_names
        if #names == 0 then return "" end
        local nrows = self:nrows()
        local widths = {}
        local aligns = {}
        for _, n in ipairs(names) do
            widths[n] = Display.dwidth(n)
            aligns[n] = Display.align_for(self._columns[n]._dtype)
        end
        local cells = {}
        for i = 1, nrows do
            cells[i] = {}
            for _, n in ipairs(names) do
                local s = Display.cell_str(Display.cell_of(self._columns[n], i))
                cells[i][n] = s
                local dw = Display.dwidth(s)
                if dw > widths[n] then widths[n] = dw end
            end
        end
        local out = {}
        local header = {}
        for _, n in ipairs(names) do header[#header + 1] = Display.pad(n, widths[n]) end
        out[#out + 1] = "| " .. table.concat(header, " | ") .. " |"
        local sep = {}
        for _, n in ipairs(names) do sep[#sep + 1] = string.rep("-", widths[n]) end
        out[#out + 1] = "| " .. table.concat(sep, " | ") .. " |"
        for i = 1, nrows do
            local line = {}
            for _, n in ipairs(names) do line[#line + 1] = Display.pad(cells[i][n], widths[n], aligns[n]) end
            out[#out + 1] = "| " .. table.concat(line, " | ") .. " |"
        end
        return table.concat(out, "\n")
    end

    -- to_string([opts]): render tabular em texto plano. opts.max_rows limita
    -- linhas com truncamento cabeça+cauda (estilo pandas), marcador "..." no meio.
    function methods.to_string(self, opts)
        opts = opts or {}
        local names = self._col_names
        local nrows = self:nrows()
        if #names == 0 then return "DataSet '"..self._name.."' (vazio)" end
        local widths = {}
        local aligns = {}
        for _, n in ipairs(names) do
            widths[n] = Display.dwidth(n)
            aligns[n] = Display.align_for(self._columns[n]._dtype)
        end
        local idx, brk = Display.plan_rows(nrows, opts.max_rows)
        local idxw = math.max(#tostring(nrows), 1)
        local rows = {}
        for _, i in ipairs(idx) do
            rows[i] = {}
            for _, n in ipairs(names) do
                local s = Display.cell_str(Display.cell_of(self._columns[n], i))
                rows[i][n] = s
                local dw = Display.dwidth(s)
                if dw > widths[n] then widths[n] = dw end
            end
        end
        local out = {}
        local header = { string.rep(" ", idxw) }
        for _, n in ipairs(names) do header[#header + 1] = Display.pad(n, widths[n], aligns[n]) end
        out[#out + 1] = table.concat(header, "  ")
        for pos, i in ipairs(idx) do
            local line = { Display.pad(tostring(i), idxw) }
            for _, n in ipairs(names) do line[#line + 1] = Display.pad(rows[i][n], widths[n], aligns[n]) end
            out[#out + 1] = table.concat(line, "  ")
            if brk and pos == brk then
                local mk = { Display.pad("...", idxw) }
                for _, n in ipairs(names) do mk[#mk + 1] = Display.pad("...", widths[n], aligns[n]) end
                out[#out + 1] = table.concat(mk, "  ")
            end
        end
        return table.concat(out, "\n")
    end
end
