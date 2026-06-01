-- lua/smaug/init.lua
--
-- Entry point do Smaug. Expõe a API pública de alto nível.
--   local smaug = require("smaug")
--   local s = smaug.Series.float64(3)
--
-- À medida que as fases avançam, DataSet e os leitores de I/O (read_csv,
-- read_json, read_xml, read_sql) serão expostos aqui também.

local Series     = require("smaug.core.series")
local BoolSeries = require("smaug.core.boolseries")
local DataSet    = require("smaug.core.dataset")

local smaug = {
    _VERSION = "0.3.0-dev",   -- Fase 3 em andamento
    Series     = Series,
    BoolSeries = BoolSeries,
    DataSet    = DataSet,
}

-- Açúcar: smaug.float64(...) == smaug.Series.float64(...)
smaug.float64    = Series.float64
smaug.int64      = Series.int64
smaug.from_table = Series.from_table
smaug.NA = Series.NA
smaug.dataset = DataSet.from_columns   -- smaug.dataset({{"a", {1,2}}, {"b", {3,4}}})

return smaug
