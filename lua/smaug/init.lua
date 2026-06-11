-- lua/smaug/init.lua
--
-- Entry point do Smaug. Expõe a API pública de alto nível.
--   local smaug = require("smaug")
--   local df = smaug.DataSet({{"venda",{10,20,30}},{"custo",{3,7,2}}})
--   local df = smaug.DataSet.from_columns(...)    -- infraestrutura, ainda funciona
--
-- API pública:    smaug.DataSet(...)   smaug.read_csv(...)  (ring 2, futuro)
-- Infraestrutura: DataSet.new/from_columns, Series.new/from_table (uso interno)

local Series     = require("smaug.core.series")
local BoolSeries = require("smaug.core.boolseries")
local DataSet    = require("smaug.core.dataset")

local smaug = {
    _VERSION   = "1.0.0-dev",
    Series     = Series,
    BoolSeries = BoolSeries,
    DataSet    = DataSet,   -- classe com __call: smaug.DataSet({...}) e .from_columns(...)
}

-- API pública
smaug.NA      = Series.NA
smaug.dataset = DataSet     -- alias legado (smaug.dataset({...}))

-- I/O (Ring 2 — futuro)
-- smaug.read_csv     = require("smaug.io.csv").read
-- smaug.read_json    = require("smaug.io.json").read
-- smaug.read_parquet = require("smaug.io.parquet").read

-- Açúcar para Series (uso avançado / interoperabilidade)
smaug.float64    = Series.float64
smaug.int64      = Series.int64
smaug.from_table = Series.from_table

return smaug
