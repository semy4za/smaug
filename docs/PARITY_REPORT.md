# Smaug — Relatório de Paridade

> Arquivo gerado por `bash scripts/parity/parity.sh` ou `powershell scripts/parity/parity.ps1`.
> **Não editar à mão.** Decisões conscientes de não-paridade ficam em
> `scripts/parity/exceptions.txt`.

Convenção de status:

- 🟩 paridade presente
- ⬜ não aplicável (exceção registrada em `exceptions.txt`)
- 🟨 ausência sem registro — suspeita, requer revisão humana
- 🟥 inconsistência clara — gap real

Gerado em: 2026-06-18 14:24:12 UTC

## Eixo 1 — Paridade de métodos entre dtypes

Cada linha = um método rastreado em `Series.methods` ou `CategoricalSeries`. Coluna = um dos 6 dtypes. 🟩 disponível · ⬜ não aplicável (exceção registrada) · 🟨 ausência sem registro (suspeita) · 🟥 inconsistência clara.

| método | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `abs` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `all` | ⬜ | ⬜ | 🟩 | ⬜ | ⬜ | ⬜ |
| `any` | ⬜ | ⬜ | 🟩 | ⬜ | ⬜ | ⬜ |
| `append` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `argmax` | 🟩 | 🟩 | ⬜ | ⬜ | 🟩 | ⬜ |
| `argmin` | 🟩 | 🟩 | ⬜ | ⬜ | 🟩 | ⬜ |
| `argsort` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `astype` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `autocorr` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟨 |
| `between` | 🟩 | 🟩 | 🟨 | 🟩 | 🟩 | 🟨 |
| `bfill` | 🟩 | 🟩 | 🟨 | 🟨 | 🟩 | 🟩 |
| `clip` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `clone` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `combine_first` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `compare` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `corr` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟨 |
| `count_nonnull` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `count_true` | ⬜ | ⬜ | 🟩 | ⬜ | ⬜ | ⬜ |
| `cov` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟨 |
| `cummax` | 🟩 | 🟩 | ⬜ | ⬜ | 🟩 | ⬜ |
| `cummin` | 🟩 | 🟩 | ⬜ | ⬜ | 🟩 | ⬜ |
| `cumprod` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `cumsum` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `describe` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `diff` | 🟩 | 🟩 | ⬜ | ⬜ | 🟩 | ⬜ |
| `dot` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟨 |
| `drop_duplicates` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `dropna` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `duplicated` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `eq` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟩 |
| `equals` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `expanding` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `ffill` | 🟩 | 🟩 | 🟨 | 🟨 | 🟩 | 🟩 |
| `fillna` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `filter` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟩 |
| `first_valid_index` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `ge` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟩 |
| `get` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `gt` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟩 |
| `head` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `idxmax` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `idxmin` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `is_monotonic_decreasing` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `is_monotonic_increasing` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `is_null` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `is_unique` | 🟩 | 🟩 | 🟨 | 🟩 | 🟩 | 🟨 |
| `isin` | 🟩 | 🟩 | 🟨 | 🟩 | 🟩 | 🟨 |
| `isna` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `kurtosis` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `land` | ⬜ | ⬜ | 🟩 | ⬜ | ⬜ | ⬜ |
| `last_valid_index` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `le` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟩 |
| `len` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `lnot` | ⬜ | ⬜ | 🟩 | ⬜ | ⬜ | ⬜ |
| `lor` | ⬜ | ⬜ | 🟩 | ⬜ | ⬜ | ⬜ |
| `lt` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟩 |
| `lxor` | ⬜ | ⬜ | 🟩 | ⬜ | ⬜ | ⬜ |
| `mad` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `map` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `mask` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `max` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `mean` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `median` | 🟩 | 🟩 | ⬜ | ⬜ | 🟩 | ⬜ |
| `min` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `mode` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `ne` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟩 |
| `nlargest` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `notna` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `nsmallest` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `nunique` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `pct_change` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟨 |
| `pct_rank` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `prod` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `quantile` | 🟩 | 🟩 | ⬜ | ⬜ | 🟩 | ⬜ |
| `rank` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `rep_each` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟨 |
| `rolling` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `round` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `searchsorted` | 🟩 | 🟩 | 🟨 | 🟩 | 🟩 | 🟨 |
| `sem` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `set` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `set_null` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `shift` | 🟩 | 🟩 | 🟨 | 🟨 | 🟩 | 🟩 |
| `size` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `skew` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `sort` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `std` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `sum` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `tail` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `take` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `to_table` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `unique` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `value_counts` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `var` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `view` | 🟩 | 🟩 | ⬜ | ⬜ | 🟨 | ⬜ |
| `where` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |

**Sumário Eixo 1:** 96 métodos × 6 dtypes = 576 células · 🟩 267 (46.4%) · ⬜ 143 (24.8%) · 🟨 166 (28.8%)

## Eixo 2 — Paridade Series ↔ DataSet

Métodos que existem em cada lado. Algumas assimetrias são intencionais (ex: `Series:len` vs `DataSet:nrows/ncols`). Outras podem ser gaps reais.

| método | Series | DataSet | nota |
| :--- | :-: | :-: | :-: |
| `abs` | 🟩 | — | só em Series |
| `add_column` | — | 🟩 | só em DataSet |
| `all` | 🟩 | — | só em Series |
| `any` | 🟩 | — | só em Series |
| `append` | 🟩 | — | só em Series |
| `argmax` | 🟩 | — | só em Series |
| `argmin` | 🟩 | — | só em Series |
| `argsort` | 🟩 | — | só em Series |
| `assign` | — | 🟩 | só em DataSet |
| `astype` | 🟩 | — | só em Series |
| `at` | — | 🟩 | só em DataSet |
| `autocorr` | 🟩 | — | só em Series |
| `between` | 🟩 | — | só em Series |
| `bfill` | 🟩 | — | só em Series |
| `clip` | 🟩 | — | só em Series |
| `clone` | 🟩 | — | só em Series |
| `column` | — | 🟩 | só em DataSet |
| `columns` | — | 🟩 | só em DataSet |
| `combine_first` | 🟩 | — | só em Series |
| `compare` | 🟩 | 🟩 |  |
| `concat` | — | 🟩 | só em DataSet |
| `corr` | 🟩 | 🟩 |  |
| `count_nonnull` | 🟩 | — | só em Series |
| `count_true` | 🟩 | — | só em Series |
| `cov` | 🟩 | 🟩 |  |
| `cummax` | 🟩 | — | só em Series |
| `cummin` | 🟩 | — | só em Series |
| `cumprod` | 🟩 | — | só em Series |
| `cumsum` | 🟩 | — | só em Series |
| `describe` | 🟩 | 🟩 |  |
| `diff` | 🟩 | — | só em Series |
| `dot` | 🟩 | — | só em Series |
| `drop_column` | — | 🟩 | só em DataSet |
| `drop_duplicates` | 🟩 | 🟩 |  |
| `dropna` | 🟩 | 🟩 |  |
| `dtypes` | — | 🟩 | só em DataSet |
| `duplicated` | 🟩 | 🟩 |  |
| `eq` | 🟩 | — | só em Series |
| `equals` | 🟩 | 🟩 |  |
| `expanding` | 🟩 | — | só em Series |
| `explode` | — | 🟩 | só em DataSet |
| `ffill` | 🟩 | — | só em Series |
| `fillna` | 🟩 | 🟩 |  |
| `filter` | 🟩 | 🟩 |  |
| `first_valid_index` | 🟩 | — | só em Series |
| `ge` | 🟩 | — | só em Series |
| `get` | 🟩 | — | só em Series |
| `groupby` | — | 🟩 | só em DataSet |
| `gt` | 🟩 | — | só em Series |
| `has_column` | — | 🟩 | só em DataSet |
| `head` | 🟩 | 🟩 |  |
| `iat` | — | 🟩 | só em DataSet |
| `idxmax` | 🟩 | — | só em Series |
| `idxmin` | 🟩 | — | só em Series |
| `iloc` | — | 🟩 | só em DataSet |
| `insert` | — | 🟩 | só em DataSet |
| `is_monotonic_decreasing` | 🟩 | — | só em Series |
| `is_monotonic_increasing` | 🟩 | — | só em Series |
| `is_null` | 🟩 | — | só em Series |
| `is_unique` | 🟩 | — | só em Series |
| `isin` | 🟩 | — | só em Series |
| `isna` | 🟩 | — | só em Series |
| `join` | — | 🟩 | só em DataSet |
| `kurtosis` | 🟩 | — | só em Series |
| `land` | 🟩 | — | só em Series |
| `last_valid_index` | 🟩 | — | só em Series |
| `le` | 🟩 | — | só em Series |
| `len` | 🟩 | — | só em Series |
| `lnot` | 🟩 | — | só em Series |
| `lor` | 🟩 | — | só em Series |
| `lt` | 🟩 | — | só em Series |
| `lxor` | 🟩 | — | só em Series |
| `mad` | 🟩 | — | só em Series |
| `map` | 🟩 | — | só em Series |
| `mask` | 🟩 | — | só em Series |
| `max` | 🟩 | — | só em Series |
| `mean` | 🟩 | — | só em Series |
| `median` | 🟩 | — | só em Series |
| `melt` | — | 🟩 | só em DataSet |
| `min` | 🟩 | — | só em Series |
| `mode` | 🟩 | — | só em Series |
| `ncols` | — | 🟩 | só em DataSet |
| `ne` | 🟩 | — | só em Series |
| `nlargest` | 🟩 | — | só em Series |
| `notna` | 🟩 | — | só em Series |
| `nrows` | — | 🟩 | só em DataSet |
| `nsmallest` | 🟩 | — | só em Series |
| `nunique` | 🟩 | 🟩 |  |
| `pct_change` | 🟩 | — | só em Series |
| `pct_rank` | 🟩 | — | só em Series |
| `pivot` | — | 🟩 | só em DataSet |
| `pivot_table` | — | 🟩 | só em DataSet |
| `prod` | 🟩 | — | só em Series |
| `quantile` | 🟩 | — | só em Series |
| `rank` | 🟩 | — | só em Series |
| `rename` | — | 🟩 | só em DataSet |
| `rename_column` | — | 🟩 | só em DataSet |
| `rep_each` | 🟩 | — | só em Series |
| `rolling` | 🟩 | 🟩 |  |
| `round` | 🟩 | — | só em Series |
| `row` | — | 🟩 | só em DataSet |
| `sample` | — | 🟩 | só em DataSet |
| `searchsorted` | 🟩 | — | só em Series |
| `select` | — | 🟩 | só em DataSet |
| `sem` | 🟩 | — | só em Series |
| `set` | 🟩 | — | só em Series |
| `set_null` | 🟩 | — | só em Series |
| `shift` | 🟩 | — | só em Series |
| `skew` | 🟩 | — | só em Series |
| `sort` | 🟩 | — | só em Series |
| `sort_by` | — | 🟩 | só em DataSet |
| `stack` | — | 🟩 | só em DataSet |
| `std` | 🟩 | — | só em Series |
| `sum` | 🟩 | — | só em Series |
| `tail` | 🟩 | 🟩 |  |
| `take` | 🟩 | 🟩 |  |
| `to_dict` | — | 🟩 | só em DataSet |
| `to_markdown` | — | 🟩 | só em DataSet |
| `to_string` | — | 🟩 | só em DataSet |
| `to_table` | 🟩 | 🟩 |  |
| `unique` | 🟩 | — | só em Series |
| `unstack` | — | 🟩 | só em DataSet |
| `update_column` | — | 🟩 | só em DataSet |
| `value_counts` | 🟩 | — | só em Series |
| `var` | 🟩 | — | só em Series |
| `view` | 🟩 | — | só em Series |
| `where` | 🟩 | — | só em Series |

**Sumário Eixo 2:** 16 métodos em ambos · 79 só em Series · 32 só em DataSet

## Eixo 3 — Espelhamento C ↔ Lua

Cada função pública do backend C deveria ter caminho no frontend Lua (direto via FFI ou exposto via método Series). 🟨 = função C que não aparece em `lua/smaug/core/series.lua` (pode ser órfã ou exposta indiretamente via outro nome).


### f64 — 49 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add` | 🟩 |  |
| `add_scalar` | 🟩 |  |
| `append` | 🟩 |  |
| `append_null` | 🟩 |  |
| `argmax` | 🟩 |  |
| `argmin` | 🟩 |  |
| `argsort` | 🟩 |  |
| `bfill` | 🟩 |  |
| `clone` | 🟩 |  |
| `count_nonnull` | 🟩 |  |
| `create` | 🟩 |  |
| `create_from_array` | 🟨 |  |
| `create_with_capacity` | 🟨 |  |
| `cummax` | 🟩 |  |
| `cummin` | 🟩 |  |
| `cumprod` | 🟩 |  |
| `cumsum` | 🟩 |  |
| `diff` | 🟩 |  |
| `div` | 🟩 |  |
| `div_scalar` | 🟩 |  |
| `eq` | 🟩 |  |
| `ffill` | 🟩 |  |
| `filter` | 🟩 |  |
| `free` | 🟩 |  |
| `ge` | 🟩 |  |
| `get` | 🟩 |  |
| `gt` | 🟩 |  |
| `is_null` | 🟩 |  |
| `le` | 🟩 |  |
| `lt` | 🟩 |  |
| `max` | 🟩 |  |
| `mean` | 🟩 |  |
| `min` | 🟩 |  |
| `mul` | 🟩 |  |
| `mul_scalar` | 🟩 |  |
| `ne` | 🟩 |  |
| `rank` | 🟩 |  |
| `set` | 🟩 |  |
| `set_null` | 🟩 |  |
| `shift` | 🟩 |  |
| `sort` | 🟩 |  |
| `sorted_nonnull` | 🟩 |  |
| `std` | 🟩 |  |
| `sub` | 🟩 |  |
| `sub_scalar` | 🟩 |  |
| `sum` | 🟩 |  |
| `take` | 🟩 |  |
| `var` | 🟩 |  |
| `view` | 🟩 |  |


### i64 — 49 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add` | 🟩 |  |
| `add_scalar` | 🟩 |  |
| `append` | 🟩 |  |
| `append_null` | 🟩 |  |
| `argmax` | 🟩 |  |
| `argmin` | 🟩 |  |
| `argsort` | 🟩 |  |
| `bfill` | 🟩 |  |
| `clone` | 🟩 |  |
| `count_nonnull` | 🟩 |  |
| `create` | 🟩 |  |
| `create_from_array` | 🟨 |  |
| `create_with_capacity` | 🟨 |  |
| `cummax` | 🟩 |  |
| `cummin` | 🟩 |  |
| `cumprod` | 🟩 |  |
| `cumsum` | 🟩 |  |
| `diff` | 🟩 |  |
| `div` | 🟩 |  |
| `div_scalar` | 🟩 |  |
| `eq` | 🟩 |  |
| `ffill` | 🟩 |  |
| `filter` | 🟩 |  |
| `free` | 🟩 |  |
| `ge` | 🟩 |  |
| `get` | 🟩 |  |
| `gt` | 🟩 |  |
| `is_null` | 🟩 |  |
| `le` | 🟩 |  |
| `lt` | 🟩 |  |
| `max` | 🟩 |  |
| `mean` | 🟩 |  |
| `min` | 🟩 |  |
| `mul` | 🟩 |  |
| `mul_scalar` | 🟩 |  |
| `ne` | 🟩 |  |
| `rank` | 🟩 |  |
| `set` | 🟩 |  |
| `set_null` | 🟩 |  |
| `shift` | 🟩 |  |
| `sort` | 🟩 |  |
| `sorted_nonnull` | 🟩 |  |
| `std` | 🟩 |  |
| `sub` | 🟩 |  |
| `sub_scalar` | 🟩 |  |
| `sum` | 🟩 |  |
| `take` | 🟩 |  |
| `var` | 🟩 |  |
| `view` | 🟩 |  |


### bool — 19 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `all` | 🟨 |  |
| `and` | 🟨 |  |
| `any` | 🟨 |  |
| `append` | 🟩 |  |
| `append_null` | 🟩 |  |
| `clone` | 🟩 |  |
| `count_true` | 🟨 |  |
| `create` | 🟩 |  |
| `create_from_array` | 🟨 |  |
| `create_with_capacity` | 🟨 |  |
| `free` | 🟩 |  |
| `get` | 🟩 |  |
| `is_null` | 🟩 |  |
| `not` | 🟨 |  |
| `or` | 🟨 |  |
| `set` | 🟩 |  |
| `set_null` | 🟩 |  |
| `view` | 🟨 |  |
| `xor` | 🟨 |  |


### str — 22 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `append` | 🟩 |  |
| `append_null` | 🟩 |  |
| `argsort` | 🟩 |  |
| `clone` | 🟩 |  |
| `count_nonnull` | 🟩 |  |
| `create` | 🟩 |  |
| `create_from_array` | 🟨 |  |
| `create_with_capacity` | 🟨 |  |
| `eq` | 🟩 |  |
| `filter` | 🟩 |  |
| `free` | 🟩 |  |
| `ge` | 🟩 |  |
| `get` | 🟩 |  |
| `gt` | 🟩 |  |
| `is_null` | 🟩 |  |
| `le` | 🟩 |  |
| `lt` | 🟩 |  |
| `ne` | 🟩 |  |
| `set` | 🟩 |  |
| `set_null` | 🟩 |  |
| `sort` | 🟩 |  |
| `take` | 🟩 |  |


### dt — 40 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add_ms` | 🟩 |  |
| `append` | 🟩 |  |
| `append_null` | 🟩 |  |
| `argsort` | 🟩 |  |
| `clone` | 🟩 |  |
| `count_nonnull` | 🟩 |  |
| `create` | 🟩 |  |
| `create_from_array` | 🟨 |  |
| `create_with_capacity` | 🟨 |  |
| `day` | 🟩 |  |
| `diff_ms` | 🟩 |  |
| `eq` | 🟩 |  |
| `filter` | 🟩 |  |
| `format` | 🟩 |  |
| `free` | 🟩 |  |
| `from_parts` | 🟩 |  |
| `ge` | 🟩 |  |
| `get` | 🟩 |  |
| `gt` | 🟩 |  |
| `hour` | 🟩 |  |
| `is_null` | 🟩 |  |
| `le` | 🟩 |  |
| `lt` | 🟩 |  |
| `minute` | 🟩 |  |
| `month` | 🟩 |  |
| `ms` | 🟩 |  |
| `ne` | 🟩 |  |
| `parse` | 🟩 |  |
| `quarter` | 🟩 |  |
| `second` | 🟩 |  |
| `set` | 🟩 |  |
| `set_null` | 🟩 |  |
| `sort` | 🟩 |  |
| `take` | 🟩 |  |
| `truncate` | 🟩 |  |
| `view` | 🟨 |  |
| `week` | 🟩 |  |
| `weekday` | 🟩 |  |
| `year` | 🟩 |  |
| `yearday` | 🟩 |  |

## Eixo 4 — Paridade Anel 2 (operações relacionais) por dtype

Heurística conservadora: verifica menção explícita do dtype no corpo da função. 🟩 = dtype mencionado explicitamente (provável suporte). 🟨 = dtype não mencionado (pode ser sem suporte, pode ser polimorfismo via dispatcher genérico — requer revisão manual).


### DataSet — operações estruturais

| operação | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `groupby` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `join` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `concat` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `pivot` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `pivot_table` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `melt` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `stack` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `unstack` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `explode` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `rolling` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `sort_by` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `filter` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |

### GroupBy — agregações

| operação | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `groupby.agg` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.count` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.first` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.last` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.max` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.mean` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.median` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.min` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.nunique` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.prod` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.quantile` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.std` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.sum` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.transform` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `groupby.var` | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |

## Eixo 5 — Paridade I/O por dtype

🟩 = dtype mencionado/usado nos arquivos do parser/writer. 🟨 = sem menção (dtype provavelmente não suportado no formato). Limitações conhecidas: `categorical` não tem representação nativa em CSV/JSON (lida como string e convertida via `astype`).


| dtype | CSV C | CSV Lua | JSON C | JSON Lua |
| :--- | :-: | :-: | :-: | :-: |
| `float64` | 🟩 | 🟩 | 🟩 | 🟨 |
| `int64` | 🟩 | 🟩 | 🟩 | 🟨 |
| `bool` | 🟩 | 🟩 | 🟩 | 🟨 |
| `string` | 🟩 | 🟩 | 🟩 | 🟩 |
| `datetime` | 🟨 | 🟨 | 🟨 | 🟨 |
| `categorical` | 🟨 | 🟨 | 🟨 | 🟨 |

## Eixo 6 — Tipos de retorno consistentes

Métodos críticos: o tipo de retorno está conforme o esperado e simétrico entre dtypes? 🟨 = divergência possível. 🟥 = inconsistência clara.


| método | esperado | detectado | status |
| :--- | :-: | :-: | :-: |
| `eq` | Series<bool> | Series<bool> | 🟩 |
| `ne` | Series<bool> | Series<bool> | 🟩 |
| `lt` | Series<bool> | Series<bool> | 🟩 |
| `le` | Series<bool> | Series<bool> | 🟩 |
| `gt` | Series<bool> | Series<bool> | 🟩 |
| `ge` | Series<bool> | Series<bool> | 🟩 |
| `is_null` | valor escalar (bool) | Series<bool> | 🟨 |
| `isna` | valor escalar (bool) | Series<bool> | 🟨 |
| `notna` | valor escalar (bool) | Series<bool> | 🟨 |
| `unique` | Series | Series<bool> | 🟩 |
| `value_counts` | DataSet | Series<bool> | 🟨 |
| `describe` | tabela Lua | Series<bool> | 🟨 |
| `head` | Series | Series<bool> | 🟩 |
| `tail` | Series | Series<bool> | 🟩 |
| `take` | Series | Series<bool> | 🟩 |
| `filter` | Series | Series<bool> | 🟩 |
| `clone` | Series | Series<bool> | 🟩 |
| `sort` | Series | Series<bool> | 🟩 |
| `argsort` | tabela de índices | Series<bool> | 🟨 |
| `to_table` | tabela Lua | Series<bool> | 🟨 |
| `cumsum` | Series | Series<bool> | 🟩 |
| `cumprod` | Series | Series<bool> | 🟩 |
| `cummax` | Series | Series<bool> | 🟩 |
| `cummin` | Series | Series<bool> | 🟩 |
| `diff` | Series | Series<bool> | 🟩 |
| `shift` | Series | Series<bool> | 🟩 |
| `map` | Series | Series<bool> | 🟩 |
| `CategoricalSeries:value_counts` | DataSet (paridade com Series) | Series | 🟥 inconsistente com Series |

## Eixo 7 — Tratamento de null consistente

Cada método tem uma política de null esperada (ignore_na, erra, propaga). Verificação heurística sobre o corpo da função. 🟨 = padrão esperado não foi detectado; pode ser implementação alternativa ou bug.


| método | política esperada | detectado | status |
| :--- | :-: | :-: | :-: |
| `sum` | ignore_na flag | tem ignore_na | 🟩 |
| `mean` | ignore_na flag | tem ignore_na | 🟩 |
| `min` | ignore_na flag | tem ignore_na | 🟩 |
| `max` | ignore_na flag | tem ignore_na | 🟩 |
| `median` | ignore_na flag | tem ignore_na | 🟩 |
| `quantile` | ignore_na flag | tem ignore_na | 🟩 |
| `var` | ignore_na flag | tem ignore_na | 🟩 |
| `std` | ignore_na flag | tem ignore_na | 🟩 |
| `prod` | ignore_na flag | tem ignore_na | 🟩 |
| `skew` | ignore_na flag | sem ignore_na | 🟨 |
| `kurtosis` | ignore_na flag | sem ignore_na | 🟨 |
| `mad` | ignore_na flag | sem ignore_na | 🟨 |
| `sem` | ignore_na flag | sem ignore_na | 🟨 |
| `mode` | ignore_na flag | sem ignore_na | 🟨 |
| `sort` | erra com null | verifica nulls | 🟩 |
| `argsort` | erra com null | verifica nulls | 🟩 |
| `abs` | propaga null | propaga | 🟩 |
| `round` | propaga null | propaga | 🟩 |
| `clip` | propaga null | propaga | 🟩 |
| `cumsum` | propaga null | propaga | 🟩 |
| `cumprod` | propaga null | propaga | 🟩 |
| `cummin` | propaga null | propaga | 🟩 |
| `cummax` | propaga null | propaga | 🟩 |
| `diff` | propaga null | propaga | 🟩 |
| `shift` | propaga null | propaga | 🟩 |
| `sin` | propaga null | — | 🟥 não encontrado |
| `cos` | propaga null | — | 🟥 não encontrado |
| `tan` | propaga null | — | 🟥 não encontrado |
| `exp` | propaga null | — | 🟥 não encontrado |
| `log` | propaga null | — | 🟥 não encontrado |
| `sqrt` | propaga null | — | 🟥 não encontrado |

## Eixo 8 — Nomenclatura consistente

Grupos de nomes que devem seguir convenções claras. Aliases declarados via `methods.X = methods.Y` são identificados automaticamente.


| grupo | método | Series | DataSet | nota |
| :--- | :-: | :-: | :-: | :-: |
| **Tamanho** | `len` | 🟩 | — | DataSet: alias de `nrows` |
| **Tamanho** | `size` | — | — | Series: alias de `len` |
| **Nulidade — predicados** | `is_null` | 🟩 | — |  |
| **Nulidade — predicados** | `isna` | 🟩 | — |  |
| **Nulidade — predicados** | `notna` | 🟩 | — |  |
| **Contagem** | `count_nonnull` | 🟩 | — |  |
| **Contagem** | `count_true` | 🟩 | — |  |
| **Lógica Kleene** | `land` | 🟩 | — |  |
| **Lógica Kleene** | `lor` | 🟩 | — |  |
| **Lógica Kleene** | `lxor` | 🟩 | — |  |
| **Lógica Kleene** | `lnot` | 🟩 | — |  |
| **Seleção posicional** | `head` | 🟩 | 🟩 |  |
| **Seleção posicional** | `tail` | 🟩 | 🟩 |  |
| **Seleção posicional** | `take` | 🟩 | 🟩 |  |
| **Seleção posicional** | `view` | 🟩 | — |  |
| **Seleção posicional** | `iloc` | — | 🟩 |  |

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
| `f64` | NaN | 🟩 usa |
| `i64` | INT64_MIN | 🟩 usa |
| `bool` | false / mask | 🟩 usa |
| `str` | NULL ptr | 🟩 usa |
| `dt` | INT64_MIN / DT_SENTINEL | 🟩 usa |

### Mensagens de erro Lua

- `series.lua`: 204/204 erros com prefixo `smaug:` (100.0%)
- `dataset.lua`: 88/88 erros com prefixo `smaug:` (100.0%)

## Eixo 10 — Paridade de lifecycle

Cada dtype com backend C deve oferecer o mesmo conjunto de operações de lifecycle. `categorical` é Lua puro e não entra nesta tabela (exceção em `exceptions.txt`).


| função | f64 | i64 | bool | str | dt |
| :--- | :-: | :-: | :-: | :-: | :-: |
| `create` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `create_with_capacity` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `create_from_array` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `free` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `clone` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `view` | 🟩 | 🟩 | 🟩 | 🟨 | 🟩 |
| `append` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `append_null` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `set` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `set_null` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `get` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `is_null` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |

## Eixo 11 — Cobertura de testes proporcional

Quantos checks cada arquivo de teste tem, e quantas vezes cada dtype é mencionado em cada arquivo (heurística: contagem de strings literais como `"float64"`, `"int64"` etc.).


### Por arquivo de teste

| arquivo | checks | float64 | int64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| `series/test_constructors` | 268 | 25 | 41 | 14 | 8 | — | — |
| `series/test_access` | 92 | 13 | 4 | — | 2 | — | — |
| `series/test_reduce` | 38 | 7 | — | — | — | — | — |
| `series/test_stat` | 136 | 30 | 15 | — | 5 | — | — |
| `series/test_window` | 64 | 5 | 6 | — | 1 | — | — |
| `series/test_predicates` | 155 | 6 | 42 | 3 | 11 | — | — |
| `series/test_selection` | 23 | 3 | 1 | — | 1 | — | — |
| `series/test_str` | 271 | 4 | 9 | 1 | 49 | — | — |
| `series/test_dt` | 256 | 3 | 6 | 2 | 9 | 58 | — |
| `series/test_categorical` | 295 | 7 | 7 | 8 | 5 | 13 | 57 |
| `dataset/test_core` | 208 | 26 | 30 | 4 | 11 | — | — |
| `dataset/test_relational` | 164 | 10 | 41 | 4 | 22 | — | — |
| `dataset/test_stat` | 50 | 3 | 6 | — | 7 | — | — |
| `dataset/test_io_support` | 44 | 2 | 13 | 1 | 6 | — | — |
| `io/test_csv` | 101 | 2 | 3 | 2 | 9 | — | — |
| `io/test_json` | 28 | 1 | 1 | 1 | 2 | — | — |
| `props/test_props` | 40 | 10 | 32 | — | 7 | — | — |
| `props/test_integration` | 67 | 18 | 2 | — | — | — | — |

**Total de checks:** 2300

### Menções totais por dtype (toda a suite)

| dtype | menções |
| :--- | :-: |
| float64 | 175 |
| int64 | 259 |
| bool | 40 |
| string | 155 |
| datetime | 71 |
| categorical | 57 |

## Eixo 12 — Sincronização docs ↔ código

Cada método público do código deveria aparecer em `API_INDEX.md`. Faltantes podem ser gaps de documentação ou métodos intencionalmente privados.


| categoria | total | documentados | faltam | % | detalhe |
| :--- | :-: | :-: | :-: | :-: | :-: |
| `Series.methods` | 95 | 95 | 0 | 100% | 🟩 completo |
| `DataSet.methods` | 48 | 48 | 0 | 100% | 🟩 completo |
| `GroupBy:*` | 15 | 15 | 0 | 100% | 🟩 completo |
| `CategoricalSeries:*` | 41 | 41 | 0 | 100% | 🟩 completo |
| `CatProxy:*` (.cat) | 6 | 6 | 0 | 100% | 🟩 completo |
| `StrProxy:*` (.str) | 28 | 28 | 0 | 100% | 🟩 completo |
| `SeriesDT:*` (.dt) | 33 | 33 | 0 | 100% | 🟩 completo |

---

## Resumo executivo


**Contagem global de status no relatório:**

- 🟩 paridade: 852
- ⬜ exceção registrada: 146
- 🟨 suspeita (revisar): 244
- 🟥 inconsistência clara: 10


## Como usar este relatório

1. Procure por 🟨 — cada um é um candidato a gap real ou exceção a registrar.
2. Se for decisão consciente, adicione em `scripts/parity/exceptions.txt`.
3. Se for gap real, registre em `Roadmap.md` ou corrija e rode novamente.
4. Procure por 🟥 — sempre gap real, exige ação.