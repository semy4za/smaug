-- lua/smaug/init.lua
--
-- Entry point do Smaug. Expõe a API pública de alto nível.
--   local smaug = require("smaug")
--   local df = smaug.DataSet({{"venda",{10,20,30}},{"custo",{3,7,2}}})
--   local s  = smaug.Series({1, 2, 3})            -- Series chamável (Bloco H.3)
--   local s  = smaug.from_array({1, 2, 3})        -- alias de from_table
--   local t  = smaug.read_csv("dados.csv")        -- I/O (Anel 3)
--
-- API pública:    smaug.Series(...) é a forma OFICIAL de construir Series
--                 (chamável; dtype opcional como 2º arg). smaug.DataSet(...)
--                 idem. smaug.read_csv/read_json (+ _mem), :to_csv/:to_json (+ _mem).
-- Disponível:     smaug.from_array (atalho não-oficial), smaug.float64/int64/
--                 string/datetime (factories de tamanho fixo).
-- Infraestrutura: DataSet.new/from_columns, Series.new/from_table (uso interno;
--                 from_table é o nome canônico, Series(...) e from_array delegam nele).

local Series     = require("smaug.core.series")
local DataSet    = require("smaug.core.dataset")
local io_csv     = require("smaug.io.csv")
local io_json    = require("smaug.io.json")

local smaug = {
    _VERSION   = "1.0.0-dev",
    Series     = Series,
    DataSet    = DataSet,   -- classe com __call: smaug.DataSet({...}) e .from_columns(...)
}

-- API pública
smaug.NA      = Series.NA
smaug.dataset = DataSet
smaug.concat  = DataSet.concat
smaug.join    = function(a, b, on, how, suffixes)
    return a:join(b, on, how, suffixes)
end

-- Anel 3 — I/O
smaug.read_csv       = io_csv.read
smaug.read_csv_mem   = io_csv.read_mem
smaug.read_json      = io_json.read
smaug.read_json_mem  = io_json.read_mem

-- to_csv / to_json como métodos do DataSet
DataSet.methods.to_csv      = function(self, path, opts) return io_csv.write(self, path, opts)  end
DataSet.methods.to_csv_mem  = function(self, opts)       return io_csv.write_mem(self, opts)    end
DataSet.methods.to_json      = function(self, path, opts) return io_json.write(self, path, opts) end
DataSet.methods.to_json_mem  = function(self, opts)       return io_json.write_mem(self, opts)   end

-- Futuro (Anel 3, pós-v1.0):
-- smaug.read_parquet = require("smaug.io.parquet").read

-- Açúcar para Series (uso avançado / interoperabilidade).
-- A forma OFICIAL de construir é smaug.Series({...}) (chamável, dtype opcional
-- como 2º arg). Os atalhos abaixo ficam disponíveis, mas não são a via ensinada.
smaug.float64    = Series.float64
smaug.int64      = Series.int64
smaug.string     = Series.string
smaug.datetime   = Series.datetime
smaug.from_array = Series.from_array

return smaug
