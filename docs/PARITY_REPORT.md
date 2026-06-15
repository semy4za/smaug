# Smaug — Relatório de Paridade

> Arquivo gerado por `bash scripts/parity/parity.sh`. **Não editar à mão.**
> Decisões conscientes de não-paridade ficam em `scripts/parity/exceptions.txt`.

Convenção de status:

- ✅ paridade presente
- ⚪ não aplicável (exceção registrada em `exceptions.txt`)
- ⚠️ ausência sem registro — suspeita, requer revisão humana
- ❌ inconsistência clara — gap real

Gerado em: 2026-06-15 04:20:31 UTC

## Eixo 1 — Paridade de métodos entre dtypes

Cada linha = um método rastreado em `Series.methods` ou `CategoricalSeries`. Coluna = um dos 6 dtypes. ✅ disponível · ⚪ não aplicável (exceção registrada) · ⚠️ ausência sem registro (suspeita) · ❌ inconsistência clara.

| método | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `abs` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `all` | ⚪ | ⚪ | ✅ | ⚪ | ⚪ | ⚪ |
| `any` | ⚪ | ⚪ | ✅ | ⚪ | ⚪ | ⚪ |
| `append` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `argmax` | ✅ | ✅ | ⚪ | ⚪ | ✅ | ⚪ |
| `argmin` | ✅ | ✅ | ⚪ | ⚪ | ✅ | ⚪ |
| `argsort` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `astype` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `autocorr` | ✅ | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `bfill` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `clip` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `clone` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `corr` | ✅ | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `count_nonnull` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `count_true` | ⚪ | ⚪ | ✅ | ⚪ | ⚪ | ⚪ |
| `cov` | ✅ | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `cummax` | ✅ | ✅ | ⚪ | ⚪ | ✅ | ⚪ |
| `cummin` | ✅ | ✅ | ⚪ | ⚪ | ✅ | ⚪ |
| `cumprod` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `cumsum` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `describe` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `diff` | ✅ | ✅ | ⚪ | ⚪ | ✅ | ⚪ |
| `dot` | ✅ | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `dropna` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `eq` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `expanding` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `ffill` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `fillna` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `filter` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `ge` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `get` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gt` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `head` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `is_null` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `isna` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `kurtosis` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `land` | ✅ | ✅ | ✅ | ✅ | ✅ | ⚪ |
| `le` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `len` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `lnot` | ⚪ | ⚪ | ✅ | ⚪ | ⚪ | ⚪ |
| `lor` | ✅ | ✅ | ✅ | ✅ | ✅ | ⚪ |
| `lt` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `lxor` | ✅ | ✅ | ✅ | ✅ | ✅ | ⚪ |
| `mad` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `map` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `mask` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `max` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `mean` | ✅ | ✅ | ✅ | ✅ | ✅ | ⚪ |
| `median` | ✅ | ✅ | ⚪ | ⚪ | ✅ | ⚪ |
| `min` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `mode` | ✅ | ✅ | ⚪ | ✅ | ✅ | ⚪ |
| `ne` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `nlargest` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `notna` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `nsmallest` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `nunique` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `pct_change` | ✅ | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `pct_rank` | ✅ | ✅ | ✅ | ✅ | ✅ | ⚪ |
| `prod` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `quantile` | ✅ | ✅ | ⚪ | ⚪ | ✅ | ⚪ |
| `rank` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `rolling` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `round` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `sem` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `set` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `set_null` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `shift` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `size` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `skew` | ✅ | ✅ | ⚪ | ⚪ | ⚪ | ⚪ |
| `sort` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `std` | ✅ | ✅ | ✅ | ✅ | ✅ | ⚪ |
| `sum` | ✅ | ✅ | ✅ | ✅ | ✅ | ⚪ |
| `tail` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `take` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `to_table` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `unique` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `value_counts` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `var` | ✅ | ✅ | ✅ | ✅ | ✅ | ⚪ |
| `view` | ✅ | ✅ | ✅ | ✅ | ✅ | ⚪ |
| `where` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

**Sumário Eixo 1:** 80 métodos × 6 dtypes = 480 células · ✅ 348 (72.5%) · ⚪ 112 (23.3%) · ⚠️ 20 (4.2%)

## Eixo 2 — Paridade Series ↔ DataSet

Métodos que existem em cada lado. Algumas assimetrias são intencionais (ex: `Series:len` vs `DataSet:nrows/ncols`). Outras podem ser gaps reais.

| método | Series | DataSet | nota |
| :--- | :-: | :-: | :-: |
| `abs` | ✅ | — | só em Series |
| `add_column` | — | ✅ | só em DataSet |
| `all` | ✅ | — | só em Series |
| `any` | ✅ | — | só em Series |
| `append` | ✅ | — | só em Series |
| `argmax` | ✅ | — | só em Series |
| `argmin` | ✅ | — | só em Series |
| `argsort` | ✅ | — | só em Series |
| `assign` | — | ✅ | só em DataSet |
| `astype` | ✅ | — | só em Series |
| `autocorr` | ✅ | — | só em Series |
| `bfill` | ✅ | — | só em Series |
| `clip` | ✅ | — | só em Series |
| `clone` | ✅ | — | só em Series |
| `column` | — | ✅ | só em DataSet |
| `columns` | — | ✅ | só em DataSet |
| `concat` | — | ✅ | só em DataSet |
| `corr` | ✅ | ✅ |  |
| `count_nonnull` | ✅ | — | só em Series |
| `count_true` | ✅ | — | só em Series |
| `cov` | ✅ | ✅ |  |
| `cummax` | ✅ | — | só em Series |
| `cummin` | ✅ | — | só em Series |
| `cumprod` | ✅ | — | só em Series |
| `cumsum` | ✅ | — | só em Series |
| `describe` | ✅ | ✅ |  |
| `diff` | ✅ | — | só em Series |
| `dot` | ✅ | — | só em Series |
| `drop_column` | — | ✅ | só em DataSet |
| `dropna` | ✅ | ✅ |  |
| `dtypes` | — | ✅ | só em DataSet |
| `eq` | ✅ | — | só em Series |
| `expanding` | ✅ | — | só em Series |
| `explode` | — | ✅ | só em DataSet |
| `ffill` | ✅ | — | só em Series |
| `fillna` | ✅ | ✅ |  |
| `filter` | ✅ | ✅ |  |
| `ge` | ✅ | — | só em Series |
| `get` | ✅ | — | só em Series |
| `groupby` | — | ✅ | só em DataSet |
| `gt` | ✅ | — | só em Series |
| `has_column` | — | ✅ | só em DataSet |
| `head` | ✅ | ✅ |  |
| `iloc` | — | ✅ | só em DataSet |
| `is_null` | ✅ | — | só em Series |
| `isna` | ✅ | — | só em Series |
| `join` | — | ✅ | só em DataSet |
| `kurtosis` | ✅ | — | só em Series |
| `land` | ✅ | — | só em Series |
| `le` | ✅ | — | só em Series |
| `len` | ✅ | — | só em Series |
| `lnot` | ✅ | — | só em Series |
| `lor` | ✅ | — | só em Series |
| `lt` | ✅ | — | só em Series |
| `lxor` | ✅ | — | só em Series |
| `mad` | ✅ | — | só em Series |
| `map` | ✅ | — | só em Series |
| `mask` | ✅ | — | só em Series |
| `max` | ✅ | — | só em Series |
| `mean` | ✅ | — | só em Series |
| `median` | ✅ | — | só em Series |
| `melt` | — | ✅ | só em DataSet |
| `min` | ✅ | — | só em Series |
| `mode` | ✅ | — | só em Series |
| `ncols` | — | ✅ | só em DataSet |
| `ne` | ✅ | — | só em Series |
| `nlargest` | ✅ | — | só em Series |
| `notna` | ✅ | — | só em Series |
| `nrows` | — | ✅ | só em DataSet |
| `nsmallest` | ✅ | — | só em Series |
| `nunique` | ✅ | ✅ |  |
| `pct_change` | ✅ | — | só em Series |
| `pct_rank` | ✅ | — | só em Series |
| `pivot` | — | ✅ | só em DataSet |
| `pivot_table` | — | ✅ | só em DataSet |
| `prod` | ✅ | — | só em Series |
| `quantile` | ✅ | — | só em Series |
| `rank` | ✅ | — | só em Series |
| `rename` | — | ✅ | só em DataSet |
| `rename_column` | — | ✅ | só em DataSet |
| `rolling` | ✅ | ✅ |  |
| `round` | ✅ | — | só em Series |
| `row` | — | ✅ | só em DataSet |
| `sample` | — | ✅ | só em DataSet |
| `select` | — | ✅ | só em DataSet |
| `sem` | ✅ | — | só em Series |
| `set` | ✅ | — | só em Series |
| `set_null` | ✅ | — | só em Series |
| `shift` | ✅ | — | só em Series |
| `skew` | ✅ | — | só em Series |
| `sort` | ✅ | — | só em Series |
| `sort_by` | — | ✅ | só em DataSet |
| `stack` | — | ✅ | só em DataSet |
| `std` | ✅ | — | só em Series |
| `sum` | ✅ | — | só em Series |
| `tail` | ✅ | ✅ |  |
| `take` | ✅ | ✅ |  |
| `to_table` | ✅ | ✅ |  |
| `unique` | ✅ | — | só em Series |
| `unstack` | — | ✅ | só em DataSet |
| `update_column` | — | ✅ | só em DataSet |
| `value_counts` | ✅ | — | só em Series |
| `var` | ✅ | — | só em Series |
| `view` | ✅ | — | só em Series |
| `where` | ✅ | — | só em Series |

**Sumário Eixo 2:** 12 métodos em ambos · 67 só em Series · 26 só em DataSet

## Eixo 3 — Espelhamento C ↔ Lua

Cada função pública do backend C deveria ter caminho no frontend Lua (direto via FFI ou exposto via método Series). ⚠️ = função C que não aparece em `lua/smaug/core/series.lua` (pode ser órfã ou exposta indiretamente via outro nome).


### f64 — 37 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add` | ✅ |  |
| `add_scalar` | ✅ |  |
| `append` | ✅ |  |
| `append_null` | ✅ |  |
| `argsort` | ✅ |  |
| `clone` | ✅ |  |
| `count_nonnull` | ✅ |  |
| `create` | ✅ |  |
| `create_from_array` | ⚠️ |  |
| `create_with_capacity` | ⚠️ |  |
| `div` | ✅ |  |
| `div_scalar` | ✅ |  |
| `eq` | ✅ |  |
| `filter` | ✅ |  |
| `free` | ✅ |  |
| `ge` | ✅ |  |
| `get` | ✅ |  |
| `gt` | ✅ |  |
| `is_null` | ✅ |  |
| `le` | ✅ |  |
| `lt` | ✅ |  |
| `max` | ✅ |  |
| `mean` | ✅ |  |
| `min` | ✅ |  |
| `mul` | ✅ |  |
| `mul_scalar` | ✅ |  |
| `ne` | ✅ |  |
| `set` | ✅ |  |
| `set_null` | ✅ |  |
| `sort` | ✅ |  |
| `std` | ✅ |  |
| `sub` | ✅ |  |
| `sub_scalar` | ✅ |  |
| `sum` | ✅ |  |
| `take` | ✅ |  |
| `var` | ✅ |  |
| `view` | ✅ |  |


### i64 — 37 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add` | ✅ |  |
| `add_scalar` | ✅ |  |
| `append` | ✅ |  |
| `append_null` | ✅ |  |
| `argsort` | ✅ |  |
| `clone` | ✅ |  |
| `count_nonnull` | ✅ |  |
| `create` | ✅ |  |
| `create_from_array` | ⚠️ |  |
| `create_with_capacity` | ⚠️ |  |
| `div` | ✅ |  |
| `div_scalar` | ✅ |  |
| `eq` | ✅ |  |
| `filter` | ✅ |  |
| `free` | ✅ |  |
| `ge` | ✅ |  |
| `get` | ✅ |  |
| `gt` | ✅ |  |
| `is_null` | ✅ |  |
| `le` | ✅ |  |
| `lt` | ✅ |  |
| `max` | ✅ |  |
| `mean` | ✅ |  |
| `min` | ✅ |  |
| `mul` | ✅ |  |
| `mul_scalar` | ✅ |  |
| `ne` | ✅ |  |
| `set` | ✅ |  |
| `set_null` | ✅ |  |
| `sort` | ✅ |  |
| `std` | ✅ |  |
| `sub` | ✅ |  |
| `sub_scalar` | ✅ |  |
| `sum` | ✅ |  |
| `take` | ✅ |  |
| `var` | ✅ |  |
| `view` | ✅ |  |


### bool — 19 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `all` | ⚠️ |  |
| `and` | ⚠️ |  |
| `any` | ⚠️ |  |
| `append` | ✅ |  |
| `append_null` | ✅ |  |
| `clone` | ✅ |  |
| `count_true` | ⚠️ |  |
| `create` | ✅ |  |
| `create_from_array` | ⚠️ |  |
| `create_with_capacity` | ⚠️ |  |
| `free` | ✅ |  |
| `get` | ✅ |  |
| `is_null` | ✅ |  |
| `not` | ⚠️ |  |
| `or` | ⚠️ |  |
| `set` | ✅ |  |
| `set_null` | ✅ |  |
| `view` | ⚠️ |  |
| `xor` | ⚠️ |  |


### str — 22 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `append` | ✅ |  |
| `append_null` | ✅ |  |
| `argsort` | ✅ |  |
| `clone` | ✅ |  |
| `count_nonnull` | ✅ |  |
| `create` | ✅ |  |
| `create_from_array` | ⚠️ |  |
| `create_with_capacity` | ⚠️ |  |
| `eq` | ✅ |  |
| `filter` | ✅ |  |
| `free` | ✅ |  |
| `ge` | ✅ |  |
| `get` | ✅ |  |
| `gt` | ✅ |  |
| `is_null` | ✅ |  |
| `le` | ✅ |  |
| `lt` | ✅ |  |
| `ne` | ✅ |  |
| `set` | ✅ |  |
| `set_null` | ✅ |  |
| `sort` | ✅ |  |
| `take` | ✅ |  |


### dt — 40 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add_ms` | ✅ |  |
| `append` | ✅ |  |
| `append_null` | ✅ |  |
| `argsort` | ✅ |  |
| `clone` | ✅ |  |
| `count_nonnull` | ✅ |  |
| `create` | ✅ |  |
| `create_from_array` | ⚠️ |  |
| `create_with_capacity` | ⚠️ |  |
| `day` | ✅ |  |
| `diff_ms` | ✅ |  |
| `eq` | ✅ |  |
| `filter` | ✅ |  |
| `format` | ✅ |  |
| `free` | ✅ |  |
| `from_parts` | ✅ |  |
| `ge` | ✅ |  |
| `get` | ✅ |  |
| `gt` | ✅ |  |
| `hour` | ✅ |  |
| `is_null` | ✅ |  |
| `le` | ✅ |  |
| `lt` | ✅ |  |
| `minute` | ✅ |  |
| `month` | ✅ |  |
| `ms` | ✅ |  |
| `ne` | ✅ |  |
| `parse` | ✅ |  |
| `quarter` | ✅ |  |
| `second` | ✅ |  |
| `set` | ✅ |  |
| `set_null` | ✅ |  |
| `sort` | ✅ |  |
| `take` | ✅ |  |
| `truncate` | ✅ |  |
| `view` | ⚠️ |  |
| `week` | ✅ |  |
| `weekday` | ✅ |  |
| `year` | ✅ |  |
| `yearday` | ✅ |  |

## Eixo 4 — Paridade Anel 2 (operações relacionais) por dtype

Heurística conservadora: verifica menção explícita do dtype no corpo da função. ✅ = dtype mencionado explicitamente (provável suporte). ⚠️ = dtype não mencionado (pode ser sem suporte, pode ser polimorfismo via dispatcher genérico — requer revisão manual).


### DataSet — operações estruturais

| operação | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `groupby` | ⚠️ | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ |
| `join` | ✅ | ✅ | ⚠️ | ✅ | ⚠️ | ⚠️ |
| `concat` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `pivot` | ⚠️ | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ |
| `pivot_table` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `melt` | ⚠️ | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ |
| `stack` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `unstack` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `explode` | ✅ | ✅ | ✅ | ✅ | ⚠️ | ⚠️ |
| `rolling` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `sort_by` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `filter` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |

### GroupBy — agregações

| operação | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `groupby.agg` | ✅ | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ |
| `groupby.count` | ⚠️ | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.first` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.last` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.max` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.mean` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.median` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.min` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.nunique` | ⚠️ | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.prod` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.quantile` | ✅ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.std` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.sum` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `groupby.transform` | ✅ | ⚠️ | ⚠️ | ✅ | ⚠️ | ⚠️ |
| `groupby.var` | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ | ⚠️ |

## Eixo 5 — Paridade I/O por dtype

✅ = dtype mencionado/usado nos arquivos do parser/writer. ⚠️ = sem menção (dtype provavelmente não suportado no formato). Limitações conhecidas: `categorical` não tem representação nativa em CSV/JSON (lida como string e convertida via `astype`).


| dtype | CSV C | CSV Lua | JSON C | JSON Lua |
| :--- | :-: | :-: | :-: | :-: |
| `float64` | ✅ | ✅ | ✅ | ⚠️ |
| `int64` | ✅ | ✅ | ✅ | ⚠️ |
| `bool` | ✅ | ✅ | ✅ | ⚠️ |
| `string` | ✅ | ✅ | ✅ | ✅ |
| `datetime` | ⚠️ | ⚠️ | ⚠️ | ⚠️ |
| `categorical` | ⚠️ | ⚠️ | ⚠️ | ⚠️ |

## Eixo 6 — Tipos de retorno consistentes

Métodos críticos: o tipo de retorno está conforme o esperado e simétrico entre dtypes? ⚠️ = divergência possível. ❌ = inconsistência clara.


| método | esperado | detectado | status |
| :--- | :-: | :-: | :-: |
| `eq` | Series<bool> | — | ❌ não encontrado |
| `ne` | Series<bool> | outro (compare(self, "cmp_ne", target) end) | ⚠️ |
| `lt` | Series<bool> | — | ❌ não encontrado |
| `le` | Series<bool> | — | ❌ não encontrado |
| `gt` | Series<bool> | — | ❌ não encontrado |
| `ge` | Series<bool> | — | ❌ não encontrado |
| `is_null` | valor escalar (bool) | outro (self._d.is_null(self._c, i - 1)) | ⚠️ |
| `isna` | valor escalar (bool) | — | ❌ não encontrado |
| `notna` | valor escalar (bool) | Series (self) | ⚠️ |
| `unique` | Series | Series | ✅ |
| `value_counts` | DataSet | outro (cnt[a.key] > cnt[b.key] end)) | ⚠️ |
| `describe` | tabela Lua | tabela Lua | ✅ |
| `head` | Series | Series | ✅ |
| `tail` | Series | Series | ✅ |
| `take` | Series | outro (wrap(r, self._dtype, self._name)) | ⚠️ |
| `filter` | Series | outro (wrap(r, self._dtype, self._name)) | ⚠️ |
| `clone` | Series | outro (wrap(self._d.clone(self._c), self._dtype) | ⚠️ |
| `sort` | Series | outro (wrap(r, self._dtype, self._name)) | ⚠️ |
| `argsort` | tabela de índices | nil/valor | ⚠️ |
| `to_table` | tabela Lua | outro (t) | ⚠️ |
| `cumsum` | Series | Series | ✅ |
| `cumprod` | Series | Series | ✅ |
| `cummax` | Series | Series | ✅ |
| `cummin` | Series | Series | ✅ |
| `diff` | Series | Series | ✅ |
| `shift` | Series | Series | ✅ |
| `map` | Series | outro (out) | ⚠️ |
| `CategoricalSeries:value_counts` | DataSet (paridade com Series) | outro (freq[a] > freq[b] end) | ❌ inconsistente com Series |

## Eixo 7 — Tratamento de null consistente

Cada método tem uma política de null esperada (ignore_na, erra, propaga). Verificação heurística sobre o corpo da função. ⚠️ = padrão esperado não foi detectado; pode ser implementação alternativa ou bug.


| método | política esperada | detectado | status |
| :--- | :-: | :-: | :-: |
| `sum` | ignore_na flag | tem ignore_na | ✅ |
| `mean` | ignore_na flag | tem ignore_na | ✅ |
| `min` | ignore_na flag | tem ignore_na | ✅ |
| `max` | ignore_na flag | tem ignore_na | ✅ |
| `median` | ignore_na flag | tem ignore_na | ✅ |
| `quantile` | ignore_na flag | tem ignore_na | ✅ |
| `var` | ignore_na flag | tem ignore_na | ✅ |
| `std` | ignore_na flag | tem ignore_na | ✅ |
| `prod` | ignore_na flag | tem ignore_na | ✅ |
| `skew` | ignore_na flag | sem ignore_na | ⚠️ |
| `kurtosis` | ignore_na flag | sem ignore_na | ⚠️ |
| `mad` | ignore_na flag | sem ignore_na | ⚠️ |
| `sem` | ignore_na flag | sem ignore_na | ⚠️ |
| `mode` | ignore_na flag | sem ignore_na | ⚠️ |
| `sort` | erra com null | verifica nulls | ✅ |
| `argsort` | erra com null | verifica nulls | ✅ |
| `abs` | propaga null | sem propagação visível | ⚠️ |
| `round` | propaga null | propaga | ✅ |
| `clip` | propaga null | propaga | ✅ |
| `cumsum` | propaga null | propaga | ✅ |
| `cumprod` | propaga null | propaga | ✅ |
| `cummin` | propaga null | propaga | ✅ |
| `cummax` | propaga null | propaga | ✅ |
| `diff` | propaga null | propaga | ✅ |
| `shift` | propaga null | propaga | ✅ |
| `sin` | propaga null | — | ❌ não encontrado |
| `cos` | propaga null | — | ❌ não encontrado |
| `tan` | propaga null | — | ❌ não encontrado |
| `exp` | propaga null | — | ❌ não encontrado |
| `log` | propaga null | — | ❌ não encontrado |
| `sqrt` | propaga null | — | ❌ não encontrado |

## Eixo 8 — Nomenclatura consistente

Grupos de nomes que devem seguir convenções claras. Aliases declarados via `methods.X = methods.Y` são identificados automaticamente.


| grupo | método | Series | DataSet | nota |
| :--- | :-: | :-: | :-: | :-: |
| **Tamanho** | `len` | ✅ | — | DataSet: alias de `nrows` |
| **Tamanho** | `size` | — | — | Series: alias de `len` |
| **Nulidade — predicados** | `is_null` | ✅ | — |  |
| **Nulidade — predicados** | `isna` | ✅ | — |  |
| **Nulidade — predicados** | `notna` | ✅ | — |  |
| **Contagem** | `count_nonnull` | ✅ | — |  |
| **Contagem** | `count_true` | ✅ | — |  |
| **Lógica Kleene** | `land` | ✅ | — |  |
| **Lógica Kleene** | `lor` | ✅ | — |  |
| **Lógica Kleene** | `lxor` | ✅ | — |  |
| **Lógica Kleene** | `lnot` | ✅ | — |  |
| **Seleção posicional** | `head` | ✅ | ✅ |  |
| **Seleção posicional** | `tail` | ✅ | ✅ |  |
| **Seleção posicional** | `take` | ✅ | ✅ |  |
| **Seleção posicional** | `view` | ✅ | — |  |
| **Seleção posicional** | `iloc` | — | ✅ |  |

### Convenções

- **Tamanho:** Series tem ambos (size = alias de len). DataSet tem nrows + ncols.
- **Nulidade — predicados:** Convenção: is_null é original; isna/notna são aliases ergonômicos.
- **Contagem:** count_nonnull é universal; count_true é só de Series<bool>.
- **Lógica Kleene:** Exclusivos de Series<bool>. Nome com prefixo 'l' para não chocar com palavras-chave Lua.
- **Seleção posicional:** Series tem head/tail/take/view. DataSet tem head/tail/take/iloc. iloc é range-based.

## Eixo 9 — Sentinelas e contratos defensivos

Backend C deve usar sentinela documentada em retorno de `get`. Frontend Lua deve usar prefixo `smaug:` em todas as mensagens de erro.


### Sentinelas C

| dtype | sentinela esperada | presente? |
| :--- | :-: | :-: |
| `f64` | NaN | ✅ usa |
| `i64` | INT64_MIN | ✅ usa |
| `bool` | false / mask | ✅ usa |
| `str` | NULL ptr | ✅ usa |
| `dt` | INT64_MIN / DT_SENTINEL | ✅ usa |

### Mensagens de erro Lua

- `series.lua`: 162/162 erros com prefixo `smaug:` (100.0%)
- `dataset.lua`: 71/71 erros com prefixo `smaug:` (100.0%)

## Eixo 10 — Paridade de lifecycle

Cada dtype com backend C deve oferecer o mesmo conjunto de operações de lifecycle. `categorical` é Lua puro e não entra nesta tabela (exceção em `exceptions.txt`).


| função | f64 | i64 | bool | str | dt |
| :--- | :-: | :-: | :-: | :-: | :-: |
| `create` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `create_with_capacity` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `create_from_array` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `free` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `clone` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `view` | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| `append` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `append_null` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `set` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `set_null` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `get` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `is_null` | ✅ | ✅ | ✅ | ✅ | ✅ |

## Eixo 11 — Cobertura de testes proporcional

Quantos checks cada arquivo de teste tem, e quantas vezes cada dtype é mencionado em cada arquivo (heurística: contagem de strings literais como `"float64"`, `"int64"` etc.).


### Por arquivo de teste

| arquivo | checks | float64 | int64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| `test_series` | 132 | 20 | 17 | — | 4 | — | — |
| `test_dataset` | 125 | 20 | 16 | 4 | 4 | — | — |
| `test_edge` | 67 | 7 | 3 | — | 2 | — | — |
| `test_special` | 37 | 7 | — | — | — | — | — |
| `test_fillna` | 24 | 6 | 1 | — | — | — | — |
| `test_props` | 40 | 10 | 32 | — | 7 | — | — |
| `test_i64` | 70 | 2 | 21 | — | — | — | — |
| `test_string` | 140 | 4 | 7 | — | 27 | — | — |
| `test_bool_dtype` | 65 | 3 | 3 | 14 | 4 | — | — |
| `test_groupby` | 47 | 2 | 12 | 1 | 7 | — | — |
| `test_concat` | 36 | 4 | 8 | 3 | 8 | — | — |
| `test_join` | 53 | — | 21 | — | 6 | — | — |
| `test_series_ops` | 74 | 5 | 13 | — | 2 | — | — |
| `test_dataset_ops` | 62 | 1 | 10 | — | 5 | — | — |
| `test_str_tier_b` | 68 | — | 1 | — | 10 | — | — |
| `test_rolling_series` | 38 | 2 | 6 | — | 1 | — | — |
| `test_io` | 71 | 3 | 2 | 2 | 5 | — | — |
| `test_io_real` | 56 | — | 2 | 1 | 6 | — | — |
| `test_enrich` | 152 | 32 | 6 | — | 2 | — | — |
| `test_datetime` | 189 | 3 | 5 | 1 | 7 | 42 | — |
| `test_categorical` | 200 | 7 | 3 | 2 | 3 | 1 | 41 |

**Total de checks:** 1746

### Menções totais por dtype (toda a suite)

| dtype | menções |
| :--- | :-: |
| float64 | 138 |
| int64 | 189 |
| bool | 28 |
| string | 110 |
| datetime | 43 |
| categorical | 41 |

## Eixo 12 — Sincronização docs ↔ código

Cada método público do código deveria aparecer em `API_INDEX.md`. Faltantes podem ser gaps de documentação ou métodos intencionalmente privados.


| categoria | total | documentados | faltam | % | detalhe |
| :--- | :-: | :-: | :-: | :-: | :-: |
| `Series.methods` | 79 | 79 | 0 | 100% | ✅ completo |
| `DataSet.methods` | 38 | 38 | 0 | 100% | ✅ completo |
| `GroupBy:*` | 15 | 15 | 0 | 100% | ✅ completo |
| `CategoricalSeries:*` | 41 | 41 | 0 | 100% | ✅ completo |
| `CatProxy:*` (.cat) | 6 | 6 | 0 | 100% | ✅ completo |
| `StrProxy:*` (.str) | 15 | 15 | 0 | 100% | ✅ completo |
| `SeriesDT:*` (.dt) | 19 | 19 | 0 | 100% | ✅ completo |

---

## Resumo executivo


**Contagem global de status no relatório:**

- ✅ paridade: 754
- ⚪ exceção registrada: 115
- ⚠️ suspeita (revisar): 82
- ❌ inconsistência clara: 16


## Como usar este relatório

1. Procure por ⚠️ — cada um é um candidato a gap real ou exceção a registrar.
2. Se for decisão consciente, adicione em `scripts/parity/exceptions.txt`.
3. Se for gap real, registre em `Roadmap.md` ou corrija e rode novamente.
4. Procure por ❌ — sempre gap real, exige ação.
