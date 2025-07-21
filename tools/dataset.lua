local DataSet = {}
DataSet.__index = DataSet

function DataSet.from_records(records)
    local self = setmetatable({}, DataSet)
    self._data = records
    self._columns = {}
    self._nrows = #records

    if records[1] then
        for k in pairs(records[1]) do
            table.insert(self._columns, k)
        end
        table.sort(self._columns)
    end

    self._ncols = #self._columns
    return self
end

function DataSet:shape()
    return self._nrows, self._ncols
end

function DataSet:head(n)
    n = n or 10
    -- cabeçalho
    print(table.concat(self._columns, "\t"))
    -- linhas
    for i = 1, math.min(n, self._nrows) do
        local row = self._data[i]
        local vals = {}
        for _, col in ipairs(self._columns) do
            table.insert(vals, tostring(row[col] ~= nil and row[col] or "NULL"))
        end
        print(table.concat(vals, "\t"))
    end
end

function DataSet:col(name)
    local series = {}
    for _, row in ipairs(self._data) do
        table.insert(series, row[name])
    end
    return series
end

-- Retorna "number", "string" ou "mixed" para uma coluna
function DataSet:dtype(name)
    local seen = {}
    for _, row in ipairs(self._data) do
        local t = type(row[name])
        seen[t] = true
    end
    if seen["number"] and not seen["string"] then return "number" end
    if seen["string"] and not seen["number"] then return "string" end
    return "mixed"
end

-- Equivalente ao df.info() do pandas
function DataSet:info()
    local rows, cols = self:shape()
    print(string.format("DataSet: %d linhas x %d colunas", rows, cols))
    for _, col in ipairs(self._columns) do
        print(string.format("  %-20s  %s", col, self:dtype(col)))
    end
end

return DataSet