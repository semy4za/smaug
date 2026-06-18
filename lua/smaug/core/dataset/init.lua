-- lua/smaug/core/dataset/init.lua
--
-- Orquestrador do DataSet: monta o módulo _internal (I) e carrega
-- os submódulos na ordem correta de dependências.
--
-- Ordem de carregamento:
--   1. _core.lua       → DataSet.new, from_columns, CRUD, acesso,
--                         seleção, assign, nunique, rename, describe,
--                         to_table, __tostring, __index, __newindex,
--                         __len, __call. Produz I.map_columns, I.cell_str.
--   2. _relational.lua → DataSet.concat, methods.concat, methods.join,
--                         methods.groupby, methods.pivot, methods.melt,
--                         methods.pivot_table, methods.stack, methods.unstack,
--                         methods.explode.
--   3. _stat.lua       → methods.corr, cov, equals, compare,
--                         methods.duplicated, drop_duplicates, methods.rolling.
--   4. _io_support.lua → methods.at, iat, insert, to_dict, DataSet.from_dict,
--                         methods.to_markdown, to_string.
--   5. Ligações finais → DataSet.methods, return DataSet.

local Series = require("smaug.core.series")
local ffi    = require("ffi")
local C      = require("smaug.ffi_loader")

-- =====================================================================
-- Helpers de tipo (compartilhados por todos os módulos)
-- =====================================================================
local function is_series(x)     return getmetatable(x) == Series end
local function is_boolseries(x) return type(x) == "table" and x._dtype == "bool" end
local function is_categorical(x)return type(x) == "table" and x._dtype == "categorical" end

-- =====================================================================
-- Módulo interno I
-- =====================================================================
local DataSet = {}
local methods = {}

local I = {
    Series        = Series,
    DataSet       = DataSet,
    methods       = methods,
    ffi           = ffi,
    C             = C,
    is_series     = is_series,
    is_boolseries = is_boolseries,
    is_categorical = is_categorical,
}

-- 1. Core: factories, CRUD, acesso, seleção, assign, nunique, rename,
--          describe, to_table, metamétodos.
--    Produz: I.map_columns, I.cell_str
require("smaug.core.dataset._core")(I)

-- 2. Relational: concat, join, GroupBy, pivot, melt, pivot_table,
--                stack, unstack, explode.
require("smaug.core.dataset._relational")(I)

-- 3. Stat: corr, cov, equals, compare, duplicated, drop_duplicates, rolling.
require("smaug.core.dataset._stat")(I)

-- 4. I/O support: at, iat, insert, to_dict, from_dict,
--                 to_markdown, to_string.
require("smaug.core.dataset._io_support")(I)

-- =====================================================================
-- 5. Ligações finais
-- =====================================================================

-- Expõe methods para extensão por módulos externos (ex: io/csv.lua, io/json.lua)
DataSet.methods = methods

return DataSet
