-- lua/smaug/core/series/init.lua
--
-- Orquestrador da Series: monta o módulo _internal (I) progressivamente,
-- carregando os submódulos na ordem correta de dependências.
--
-- REGRA: nenhum submódulo conhece outro submódulo.
--        Só o orquestrador faz ligações.
--
-- Ordem de carregamento:
--   1.  _types.lua        → I.DTYPES
--   2.  _core.lua         → I.Series, I.methods, I.wrap, I.check_*, I.require_op, I.reduce_num
--   3.  _factories.lua    → Series.new, from_table (base), full, float64, int64, string, datetime
--   4.  _bool_ops.lua     → I.bool_mask_parts, I.bool_series_from_raw, I.binop, I.kleene_binop
--                           + metamétodos __add/__mul/__sub/__div/__len/__tostring/__newindex
--   5.  access/_access.lua   → methods.get, set, is_null, set_null, append, len, clone
--   6.  access/_transform.lua→ methods.sort, argsort, view, take, dropna, head, tail,
--                               to_table, astype, fillna, map, abs, round, clip
--   7.  stats/_reduce.lua    → methods.sum, mean, min, max, var, std
--   8.  stats/_stat.lua      → helpers c_sorted_nonnull, median_of_sorted, quantile_of_sorted,
--                               collect_sorted, median_sorted, quantile_sorted
--                             → methods.unique, nunique, value_counts, prod, median, quantile,
--                               mode, describe
--   9.  stats/_stat_adv.lua  → methods.cov, corr, autocorr, dot, pct_change, rank, pct_rank,
--                               skew, kurtosis, mad, sem
--   10. window/_cumulative.lua→ methods.cumsum, cumprod, diff, shift, ffill, bfill,
--                               cummin, cummax, argmin, argmax
--   11. window/_rolling.lua   → I.SeriesRolling, I.SeriesExpanding
--                             → methods.rolling, expanding
--   12. selection/_predicates.lua→ I.is_monotonic
--                               → methods.between, isin, is_unique, is_monotonic_*,
--                                 equals, compare, idxmin, idxmax, first/last_valid_index,
--                                 duplicated, drop_duplicates, combine_first,
--                                 searchsorted, rep_each
--   13. selection/_selection.lua → methods.gt, lt, eq, ge, le, ne, filter,
--                                  land, lor, lxor, lnot, count_true, any, all,
--                                  where, mask, Series.ifelse, isna, notna,
--                                  nlargest, nsmallest, sin, cos, tan, exp, log, sqrt
--   14. text/_str.lua         → I.StrProxy
--   15. temporal/_dt.lua      → I.SeriesDT, I.SeriesAt
--                             → Series.dt_parse, dt_format, dt_from_parts
--   16. categorical/_categorical.lua → I.CategoricalSeries
--   17. Ligações finais (neste arquivo):
--       - Series.Categorical
--       - Series._DTYPES, Series.NA
--       - Series.is_categorical
--       - intercepção de Series.from_table para "categorical"
--       - Series.__index dispatcher

local ffi = require("ffi")
local C   = require("smaug.ffi_loader")
local Err = require("smaug.core.errors")

-- Sentinelas globais (usados por múltiplos módulos)
local NAN     = 0 / 0
local I64_MIN = -9223372036854775807LL - 1LL
-- ^ I64_MIN: sentinela i64/datetime. Escrito como (-MAX - 1) porque o literal
--   mais-negativo não é representável diretamente. Tem DOIS contextos distintos:
--     1. Leitura de elemento (get): o C devolve 0 + status SMG_NULL_VALUE para
--        NULL. O 0 NÃO é sentinela (0 é valor i64 válido); quem sinaliza é o
--        status, e a fronteira Lua converte para nil.
--     2. Redução posicional (sum/min/max sobre vazio/all-null): o C devolve
--        I64_MIN como sentinela de resultado (canal único, sem status). É
--        detectado por is_int_sentinel (ver reduce_num em _core.lua) → nil.
--   Toda comparação com este sentinela passa pelo predicado is_int_sentinel;
--   nunca por literal cru (vira double e bate por coerção frágil).

local function is_nan(v) return v ~= v end

local NA = setmetatable({}, { __tostring = function() return "NA" end })
local function is_na(v) return v == nil or v == NA end

-- Aviso não-fatal (stderr) — canal único, agora em core/warn.lua (item 12.10),
-- para que o Anel 3 (io/csv) use o MESMO canal em vez de um segundo stderr.
local warn = require("smaug.core.warn")

-- =====================================================================
-- Módulo interno _internal (I): ponto de encontro entre submódulos
-- =====================================================================
local I = {
    ffi     = ffi,
    C       = C,
    NAN     = NAN,
    I64_MIN = I64_MIN,
    is_nan  = is_nan,
    NA      = NA,
    is_na   = is_na,
    warn    = warn,
}

-- 1. DTYPES
I.DTYPES = require("smaug.core.series._types")(I)

-- 2. Core (Series, methods, wrap, check_*, require_op, reduce_num)
require("smaug.core.series._core")(I)

-- 3. Factories (Series.new, from_table base, full, float64, int64, string, datetime)
require("smaug.core.series._factories")(I)

-- 4. Bool ops (bool_mask_parts, bool_series_from_raw, binop, kleene_binop + metamétodos)
require("smaug.core.series._bool_ops")(I)

-- 5. Acesso elementar (get, set, is_null, set_null, append, len, clone)
require("smaug.core.series.access._access")(I)

-- 6. Transformações (sort, view, take, astype, fillna, map, abs, round, clip)
require("smaug.core.series.access._transform")(I)

-- 7. Reduções core (sum, mean, min, max, var, std)
require("smaug.core.series.stats._reduce")(I)

-- 8. Estatísticas + helpers (unique, nunique, value_counts, prod, median, quantile,
--    mode, describe + c_sorted_nonnull, median_of_sorted, ...)
require("smaug.core.series.stats._stat")(I)

-- 9. Estatísticas avançadas (cov, corr, rank, pct_rank, skew, kurtosis, mad, sem)
require("smaug.core.series.stats._stat_adv")(I)

-- 10. Cumulativos (cumsum, cumprod, diff, shift, ffill, bfill, cummin, cummax, argmin, argmax)
require("smaug.core.series.window._cumulative")(I)

-- 11. Rolling/Expanding (SeriesRolling, SeriesExpanding, methods.rolling, expanding)
require("smaug.core.series.window._rolling")(I)

-- 12. Predicados (between, isin, is_unique, is_monotonic_*, equals, compare,
--     idxmin, idxmax, first/last_valid_index, duplicated, drop_duplicates,
--     combine_first, searchsorted, rep_each)
require("smaug.core.series.selection._predicates")(I)

-- 13. Seleção (gt, lt, eq, filter, land, lor, where, mask, ifelse, isna, nlargest, sin...)
--     Depende de: c_sorted_nonnull (de _stat), bool_mask_parts, bool_series_from_raw,
--                 kleene_binop (de _bool_ops)
require("smaug.core.series.selection._selection")(I)

-- 14. StrProxy (.str Tier A+B+C)
require("smaug.core.series.text._str")(I)

-- 15. SeriesDT (.dt base + F.3) + SeriesAt + helpers públicos
require("smaug.core.series.temporal._dt")(I)

-- 16. CategoricalSeries + CatProxy
require("smaug.core.series.categorical._categorical")(I)

-- =====================================================================
-- 17. Ligações finais
-- =====================================================================

local Series           = I.Series
local methods          = I.methods
local NA_              = I.NA   -- mesmo NA do início
local DTYPES           = I.DTYPES
local StrProxy         = I.StrProxy
local SeriesDT         = I.SeriesDT
local SeriesAt         = I.SeriesAt
local CategoricalSeries = I.CategoricalSeries

-- Exposição de constantes públicas
Series._DTYPES = DTYPES
Series.NA      = NA_
Series.NAN     = NAN

-- Expõe CategoricalSeries como Series.Categorical
Series.Categorical = CategoricalSeries

-- Helper público
function Series.is_categorical(x)
    return getmetatable(x) == CategoricalSeries
end

-- Intercepção de from_table para dtype "categorical"
-- (from_table base foi definida em _factories.lua sem saber de CategoricalSeries)
local _orig_from_table = Series.from_table
function Series.from_table(arr, dtype, name)
    if dtype == "categorical" then
        return CategoricalSeries.from_table(arr, name)
    end
    return _orig_from_table(arr, dtype, name)
end

-- __index unificado: índice numérico → get(); .str → StrProxy; .dt → SeriesDT;
-- .at/.iat → SeriesAt; método.
Series.__index = function(self, k)
    if k == "dt" then
        if self._dtype ~= "datetime" then
            error("smaug: accessor .dt só se aplica a séries datetime; dtype é '"
                  .. self._dtype .. "'", 2)
        end
        return setmetatable({ _s = self }, SeriesDT)
    end
    if type(k) == "number" then return methods.get(self, k) end
    if k == "str" then
        if self._dtype ~= "string" then
            error("smaug: accessor .str só se aplica a séries string; dtype é '"
                  .. self._dtype .. "'", 2)
        end
        return setmetatable({ _s = self }, StrProxy)
    end
    if k == "at" or k == "iat" then
        return setmetatable({ _s = self }, SeriesAt)
    end
    local m = methods[k]
    if m ~= nil then return m end
    -- 12.12: método desconhecido falha visível, com sugestão. Chaves com "_"
    -- seguem devolvendo nil (campos internos: _c, _dtype, _name...).
    if type(k) == "string" and k:sub(1, 1) ~= "_" then
        error(Err.unknown_key("método", k, methods), 2)
    end
    return nil
end

return Series
