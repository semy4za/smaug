# Smaug â€” RelatÃ³rio de Paridade

> Arquivo gerado por `bash scripts/parity/parity.sh` ou `powershell scripts/parity/parity.ps1`.
> **NÃ£o editar Ã  mÃ£o.** DecisÃµes conscientes de nÃ£o-paridade ficam em
> `scripts/parity/exceptions.txt`.

ConvenÃ§Ã£o de status:

- âœ… paridade presente
- âšª nÃ£o aplicÃ¡vel (exceÃ§Ã£o registrada em `exceptions.txt`)
- âš ï¸ ausÃªncia sem registro â€” suspeita, requer revisÃ£o humana
- âŒ inconsistÃªncia clara â€” gap real

Gerado em: 2026-06-15 17:32:25 UTC

## Eixo 1 ÔÇö Paridade de m├®todos entre dtypes

Cada linha = um m├®todo rastreado em `Series.methods` ou `CategoricalSeries`. Coluna = um dos 6 dtypes. Ô£à dispon├¡vel ┬À ÔÜ¬ n├úo aplic├ível (exce├º├úo registrada) ┬À ÔÜá´©Å aus├¬ncia sem registro (suspeita) ┬À ÔØî inconsist├¬ncia clara.

| m├®todo | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `abs` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `all` | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `any` | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `append` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `argmax` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ |
| `argmin` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ |
| `argsort` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `astype` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `autocorr` | Ô£à | Ô£à | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `between` | Ô£à | Ô£à | ÔÜá´©Å | Ô£à | Ô£à | ÔÜá´©Å |
| `bfill` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `clip` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `clone` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `combine_first` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `compare` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `corr` | Ô£à | Ô£à | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `count_nonnull` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `count_true` | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `cov` | Ô£à | Ô£à | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `cummax` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ |
| `cummin` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ |
| `cumprod` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `cumsum` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `describe` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `diff` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ |
| `dot` | Ô£à | Ô£à | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `drop_duplicates` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `dropna` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `duplicated` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `eq` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `equals` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `expanding` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `ffill` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `fillna` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `filter` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `first_valid_index` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `ge` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `get` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `gt` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `head` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `idxmax` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `idxmin` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `is_monotonic_decreasing` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `is_monotonic_increasing` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `is_null` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `is_unique` | Ô£à | Ô£à | ÔÜá´©Å | Ô£à | Ô£à | ÔÜá´©Å |
| `isin` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `isna` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `kurtosis` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `land` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜ¬ |
| `last_valid_index` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `le` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `len` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `lnot` | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `lor` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜ¬ |
| `lt` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `lxor` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜ¬ |
| `mad` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `map` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `mask` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `max` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `mean` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜ¬ |
| `median` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ |
| `min` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `mode` | Ô£à | Ô£à | ÔÜ¬ | Ô£à | Ô£à | ÔÜ¬ |
| `ne` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `nlargest` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `notna` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `nsmallest` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `nunique` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `pct_change` | Ô£à | Ô£à | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `pct_rank` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜ¬ |
| `prod` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `quantile` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | Ô£à | ÔÜ¬ |
| `rank` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `rep_each` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `rolling` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `round` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `searchsorted` | Ô£à | Ô£à | ÔÜá´©Å | Ô£à | Ô£à | ÔÜá´©Å |
| `sem` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `set` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `set_null` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `shift` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `size` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `skew` | Ô£à | Ô£à | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ | ÔÜ¬ |
| `sort` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `std` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜ¬ |
| `sum` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜ¬ |
| `tail` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `take` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `to_table` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `unique` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `value_counts` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `var` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜ¬ |
| `view` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜ¬ |
| `where` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |

**Sum├írio Eixo 1:** 96 m├®todos ├ù 6 dtypes = 576 c├®lulas ┬À Ô£à 425 (73.8%) ┬À ÔÜ¬ 112 (19.4%) ┬À ÔÜá´©Å 39 (6.8%)

## Eixo 2 ÔÇö Paridade Series Ôåö DataSet

M├®todos que existem em cada lado. Algumas assimetrias s├úo intencionais (ex: `Series:len` vs `DataSet:nrows/ncols`). Outras podem ser gaps reais.

| m├®todo | Series | DataSet | nota |
| :--- | :-: | :-: | :-: |
| `abs` | Ô£à | ÔÇö | s├│ em Series |
| `add_column` | ÔÇö | Ô£à | s├│ em DataSet |
| `all` | Ô£à | ÔÇö | s├│ em Series |
| `any` | Ô£à | ÔÇö | s├│ em Series |
| `append` | Ô£à | ÔÇö | s├│ em Series |
| `argmax` | Ô£à | ÔÇö | s├│ em Series |
| `argmin` | Ô£à | ÔÇö | s├│ em Series |
| `argsort` | Ô£à | ÔÇö | s├│ em Series |
| `assign` | ÔÇö | Ô£à | s├│ em DataSet |
| `astype` | Ô£à | ÔÇö | s├│ em Series |
| `at` | ÔÇö | Ô£à | s├│ em DataSet |
| `autocorr` | Ô£à | ÔÇö | s├│ em Series |
| `between` | Ô£à | ÔÇö | s├│ em Series |
| `bfill` | Ô£à | ÔÇö | s├│ em Series |
| `clip` | Ô£à | ÔÇö | s├│ em Series |
| `clone` | Ô£à | ÔÇö | s├│ em Series |
| `column` | ÔÇö | Ô£à | s├│ em DataSet |
| `columns` | ÔÇö | Ô£à | s├│ em DataSet |
| `combine_first` | Ô£à | ÔÇö | s├│ em Series |
| `compare` | Ô£à | Ô£à |  |
| `concat` | ÔÇö | Ô£à | s├│ em DataSet |
| `corr` | Ô£à | Ô£à |  |
| `count_nonnull` | Ô£à | ÔÇö | s├│ em Series |
| `count_true` | Ô£à | ÔÇö | s├│ em Series |
| `cov` | Ô£à | Ô£à |  |
| `cummax` | Ô£à | ÔÇö | s├│ em Series |
| `cummin` | Ô£à | ÔÇö | s├│ em Series |
| `cumprod` | Ô£à | ÔÇö | s├│ em Series |
| `cumsum` | Ô£à | ÔÇö | s├│ em Series |
| `describe` | Ô£à | Ô£à |  |
| `diff` | Ô£à | ÔÇö | s├│ em Series |
| `dot` | Ô£à | ÔÇö | s├│ em Series |
| `drop_column` | ÔÇö | Ô£à | s├│ em DataSet |
| `drop_duplicates` | Ô£à | Ô£à |  |
| `dropna` | Ô£à | Ô£à |  |
| `dtypes` | ÔÇö | Ô£à | s├│ em DataSet |
| `duplicated` | Ô£à | Ô£à |  |
| `eq` | Ô£à | ÔÇö | s├│ em Series |
| `equals` | Ô£à | Ô£à |  |
| `expanding` | Ô£à | ÔÇö | s├│ em Series |
| `explode` | ÔÇö | Ô£à | s├│ em DataSet |
| `ffill` | Ô£à | ÔÇö | s├│ em Series |
| `fillna` | Ô£à | Ô£à |  |
| `filter` | Ô£à | Ô£à |  |
| `first_valid_index` | Ô£à | ÔÇö | s├│ em Series |
| `ge` | Ô£à | ÔÇö | s├│ em Series |
| `get` | Ô£à | ÔÇö | s├│ em Series |
| `groupby` | ÔÇö | Ô£à | s├│ em DataSet |
| `gt` | Ô£à | ÔÇö | s├│ em Series |
| `has_column` | ÔÇö | Ô£à | s├│ em DataSet |
| `head` | Ô£à | Ô£à |  |
| `iat` | ÔÇö | Ô£à | s├│ em DataSet |
| `idxmax` | Ô£à | ÔÇö | s├│ em Series |
| `idxmin` | Ô£à | ÔÇö | s├│ em Series |
| `iloc` | ÔÇö | Ô£à | s├│ em DataSet |
| `insert` | ÔÇö | Ô£à | s├│ em DataSet |
| `is_monotonic_decreasing` | Ô£à | ÔÇö | s├│ em Series |
| `is_monotonic_increasing` | Ô£à | ÔÇö | s├│ em Series |
| `is_null` | Ô£à | ÔÇö | s├│ em Series |
| `is_unique` | Ô£à | ÔÇö | s├│ em Series |
| `isin` | Ô£à | ÔÇö | s├│ em Series |
| `isna` | Ô£à | ÔÇö | s├│ em Series |
| `join` | ÔÇö | Ô£à | s├│ em DataSet |
| `kurtosis` | Ô£à | ÔÇö | s├│ em Series |
| `land` | Ô£à | ÔÇö | s├│ em Series |
| `last_valid_index` | Ô£à | ÔÇö | s├│ em Series |
| `le` | Ô£à | ÔÇö | s├│ em Series |
| `len` | Ô£à | ÔÇö | s├│ em Series |
| `lnot` | Ô£à | ÔÇö | s├│ em Series |
| `lor` | Ô£à | ÔÇö | s├│ em Series |
| `lt` | Ô£à | ÔÇö | s├│ em Series |
| `lxor` | Ô£à | ÔÇö | s├│ em Series |
| `mad` | Ô£à | ÔÇö | s├│ em Series |
| `map` | Ô£à | ÔÇö | s├│ em Series |
| `mask` | Ô£à | ÔÇö | s├│ em Series |
| `max` | Ô£à | ÔÇö | s├│ em Series |
| `mean` | Ô£à | ÔÇö | s├│ em Series |
| `median` | Ô£à | ÔÇö | s├│ em Series |
| `melt` | ÔÇö | Ô£à | s├│ em DataSet |
| `min` | Ô£à | ÔÇö | s├│ em Series |
| `mode` | Ô£à | ÔÇö | s├│ em Series |
| `ncols` | ÔÇö | Ô£à | s├│ em DataSet |
| `ne` | Ô£à | ÔÇö | s├│ em Series |
| `nlargest` | Ô£à | ÔÇö | s├│ em Series |
| `notna` | Ô£à | ÔÇö | s├│ em Series |
| `nrows` | ÔÇö | Ô£à | s├│ em DataSet |
| `nsmallest` | Ô£à | ÔÇö | s├│ em Series |
| `nunique` | Ô£à | Ô£à |  |
| `pct_change` | Ô£à | ÔÇö | s├│ em Series |
| `pct_rank` | Ô£à | ÔÇö | s├│ em Series |
| `pivot` | ÔÇö | Ô£à | s├│ em DataSet |
| `pivot_table` | ÔÇö | Ô£à | s├│ em DataSet |
| `prod` | Ô£à | ÔÇö | s├│ em Series |
| `quantile` | Ô£à | ÔÇö | s├│ em Series |
| `rank` | Ô£à | ÔÇö | s├│ em Series |
| `rename` | ÔÇö | Ô£à | s├│ em DataSet |
| `rename_column` | ÔÇö | Ô£à | s├│ em DataSet |
| `rep_each` | Ô£à | ÔÇö | s├│ em Series |
| `rolling` | Ô£à | Ô£à |  |
| `round` | Ô£à | ÔÇö | s├│ em Series |
| `row` | ÔÇö | Ô£à | s├│ em DataSet |
| `sample` | ÔÇö | Ô£à | s├│ em DataSet |
| `searchsorted` | Ô£à | ÔÇö | s├│ em Series |
| `select` | ÔÇö | Ô£à | s├│ em DataSet |
| `sem` | Ô£à | ÔÇö | s├│ em Series |
| `set` | Ô£à | ÔÇö | s├│ em Series |
| `set_null` | Ô£à | ÔÇö | s├│ em Series |
| `shift` | Ô£à | ÔÇö | s├│ em Series |
| `skew` | Ô£à | ÔÇö | s├│ em Series |
| `sort` | Ô£à | ÔÇö | s├│ em Series |
| `sort_by` | ÔÇö | Ô£à | s├│ em DataSet |
| `stack` | ÔÇö | Ô£à | s├│ em DataSet |
| `std` | Ô£à | ÔÇö | s├│ em Series |
| `sum` | Ô£à | ÔÇö | s├│ em Series |
| `tail` | Ô£à | Ô£à |  |
| `take` | Ô£à | Ô£à |  |
| `to_dict` | ÔÇö | Ô£à | s├│ em DataSet |
| `to_markdown` | ÔÇö | Ô£à | s├│ em DataSet |
| `to_string` | ÔÇö | Ô£à | s├│ em DataSet |
| `to_table` | Ô£à | Ô£à |  |
| `unique` | Ô£à | ÔÇö | s├│ em Series |
| `unstack` | ÔÇö | Ô£à | s├│ em DataSet |
| `update_column` | ÔÇö | Ô£à | s├│ em DataSet |
| `value_counts` | Ô£à | ÔÇö | s├│ em Series |
| `var` | Ô£à | ÔÇö | s├│ em Series |
| `view` | Ô£à | ÔÇö | s├│ em Series |
| `where` | Ô£à | ÔÇö | s├│ em Series |

**Sum├írio Eixo 2:** 16 m├®todos em ambos ┬À 79 s├│ em Series ┬À 32 s├│ em DataSet

## Eixo 3 ÔÇö Espelhamento C Ôåö Lua

Cada fun├º├úo p├║blica do backend C deveria ter caminho no frontend Lua (direto via FFI ou exposto via m├®todo Series). ÔÜá´©Å = fun├º├úo C que n├úo aparece em `lua/smaug/core/series.lua` (pode ser ├│rf├ú ou exposta indiretamente via outro nome).


### f64 ÔÇö 37 fun├º├Áes C

| fun├º├úo C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add` | Ô£à |  |
| `add_scalar` | Ô£à |  |
| `append` | Ô£à |  |
| `append_null` | Ô£à |  |
| `argsort` | Ô£à |  |
| `clone` | Ô£à |  |
| `count_nonnull` | Ô£à |  |
| `create` | Ô£à |  |
| `create_from_array` | ÔÜá´©Å |  |
| `create_with_capacity` | ÔÜá´©Å |  |
| `div` | Ô£à |  |
| `div_scalar` | Ô£à |  |
| `eq` | Ô£à |  |
| `filter` | Ô£à |  |
| `free` | Ô£à |  |
| `ge` | Ô£à |  |
| `get` | Ô£à |  |
| `gt` | Ô£à |  |
| `is_null` | Ô£à |  |
| `le` | Ô£à |  |
| `lt` | Ô£à |  |
| `max` | Ô£à |  |
| `mean` | Ô£à |  |
| `min` | Ô£à |  |
| `mul` | Ô£à |  |
| `mul_scalar` | Ô£à |  |
| `ne` | Ô£à |  |
| `set` | Ô£à |  |
| `set_null` | Ô£à |  |
| `sort` | Ô£à |  |
| `std` | Ô£à |  |
| `sub` | Ô£à |  |
| `sub_scalar` | Ô£à |  |
| `sum` | Ô£à |  |
| `take` | Ô£à |  |
| `var` | Ô£à |  |
| `view` | Ô£à |  |


### i64 ÔÇö 37 fun├º├Áes C

| fun├º├úo C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add` | Ô£à |  |
| `add_scalar` | Ô£à |  |
| `append` | Ô£à |  |
| `append_null` | Ô£à |  |
| `argsort` | Ô£à |  |
| `clone` | Ô£à |  |
| `count_nonnull` | Ô£à |  |
| `create` | Ô£à |  |
| `create_from_array` | ÔÜá´©Å |  |
| `create_with_capacity` | ÔÜá´©Å |  |
| `div` | Ô£à |  |
| `div_scalar` | Ô£à |  |
| `eq` | Ô£à |  |
| `filter` | Ô£à |  |
| `free` | Ô£à |  |
| `ge` | Ô£à |  |
| `get` | Ô£à |  |
| `gt` | Ô£à |  |
| `is_null` | Ô£à |  |
| `le` | Ô£à |  |
| `lt` | Ô£à |  |
| `max` | Ô£à |  |
| `mean` | Ô£à |  |
| `min` | Ô£à |  |
| `mul` | Ô£à |  |
| `mul_scalar` | Ô£à |  |
| `ne` | Ô£à |  |
| `set` | Ô£à |  |
| `set_null` | Ô£à |  |
| `sort` | Ô£à |  |
| `std` | Ô£à |  |
| `sub` | Ô£à |  |
| `sub_scalar` | Ô£à |  |
| `sum` | Ô£à |  |
| `take` | Ô£à |  |
| `var` | Ô£à |  |
| `view` | Ô£à |  |


### bool ÔÇö 19 fun├º├Áes C

| fun├º├úo C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `all` | ÔÜá´©Å |  |
| `and` | ÔÜá´©Å |  |
| `any` | ÔÜá´©Å |  |
| `append` | Ô£à |  |
| `append_null` | Ô£à |  |
| `clone` | Ô£à |  |
| `count_true` | ÔÜá´©Å |  |
| `create` | Ô£à |  |
| `create_from_array` | ÔÜá´©Å |  |
| `create_with_capacity` | ÔÜá´©Å |  |
| `free` | Ô£à |  |
| `get` | Ô£à |  |
| `is_null` | Ô£à |  |
| `not` | ÔÜá´©Å |  |
| `or` | ÔÜá´©Å |  |
| `set` | Ô£à |  |
| `set_null` | Ô£à |  |
| `view` | ÔÜá´©Å |  |
| `xor` | ÔÜá´©Å |  |


### str ÔÇö 22 fun├º├Áes C

| fun├º├úo C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `append` | Ô£à |  |
| `append_null` | Ô£à |  |
| `argsort` | Ô£à |  |
| `clone` | Ô£à |  |
| `count_nonnull` | Ô£à |  |
| `create` | Ô£à |  |
| `create_from_array` | ÔÜá´©Å |  |
| `create_with_capacity` | ÔÜá´©Å |  |
| `eq` | Ô£à |  |
| `filter` | Ô£à |  |
| `free` | Ô£à |  |
| `ge` | Ô£à |  |
| `get` | Ô£à |  |
| `gt` | Ô£à |  |
| `is_null` | Ô£à |  |
| `le` | Ô£à |  |
| `lt` | Ô£à |  |
| `ne` | Ô£à |  |
| `set` | Ô£à |  |
| `set_null` | Ô£à |  |
| `sort` | Ô£à |  |
| `take` | Ô£à |  |


### dt ÔÇö 40 fun├º├Áes C

| fun├º├úo C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add_ms` | Ô£à |  |
| `append` | Ô£à |  |
| `append_null` | Ô£à |  |
| `argsort` | Ô£à |  |
| `clone` | Ô£à |  |
| `count_nonnull` | Ô£à |  |
| `create` | Ô£à |  |
| `create_from_array` | ÔÜá´©Å |  |
| `create_with_capacity` | ÔÜá´©Å |  |
| `day` | Ô£à |  |
| `diff_ms` | Ô£à |  |
| `eq` | Ô£à |  |
| `filter` | Ô£à |  |
| `format` | Ô£à |  |
| `free` | Ô£à |  |
| `from_parts` | Ô£à |  |
| `ge` | Ô£à |  |
| `get` | Ô£à |  |
| `gt` | Ô£à |  |
| `hour` | Ô£à |  |
| `is_null` | Ô£à |  |
| `le` | Ô£à |  |
| `lt` | Ô£à |  |
| `minute` | Ô£à |  |
| `month` | Ô£à |  |
| `ms` | Ô£à |  |
| `ne` | Ô£à |  |
| `parse` | Ô£à |  |
| `quarter` | Ô£à |  |
| `second` | Ô£à |  |
| `set` | Ô£à |  |
| `set_null` | Ô£à |  |
| `sort` | Ô£à |  |
| `take` | Ô£à |  |
| `truncate` | Ô£à |  |
| `view` | ÔÜá´©Å |  |
| `week` | Ô£à |  |
| `weekday` | Ô£à |  |
| `year` | Ô£à |  |
| `yearday` | Ô£à |  |

## Eixo 4 ÔÇö Paridade Anel 2 (opera├º├Áes relacionais) por dtype

Heur├¡stica conservadora: verifica men├º├úo expl├¡cita do dtype no corpo da fun├º├úo. Ô£à = dtype mencionado explicitamente (prov├ível suporte). ÔÜá´©Å = dtype n├úo mencionado (pode ser sem suporte, pode ser polimorfismo via dispatcher gen├®rico ÔÇö requer revis├úo manual).


### DataSet ÔÇö opera├º├Áes estruturais

| opera├º├úo | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `groupby` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | Ô£à | ÔÜá´©Å | ÔÜá´©Å |
| `join` | Ô£à | Ô£à | ÔÜá´©Å | Ô£à | ÔÜá´©Å | ÔÜá´©Å |
| `concat` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `pivot` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | Ô£à | ÔÜá´©Å | ÔÜá´©Å |
| `pivot_table` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `melt` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | Ô£à | ÔÜá´©Å | ÔÜá´©Å |
| `stack` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `unstack` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `explode` | Ô£à | Ô£à | Ô£à | Ô£à | ÔÜá´©Å | ÔÜá´©Å |
| `rolling` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `sort_by` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `filter` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |

### GroupBy ÔÇö agrega├º├Áes

| opera├º├úo | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `groupby.agg` | Ô£à | ÔÜá´©Å | ÔÜá´©Å | Ô£à | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.count` | ÔÜá´©Å | Ô£à | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.first` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.last` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.max` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.mean` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.median` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.min` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.nunique` | ÔÜá´©Å | Ô£à | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.prod` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.quantile` | Ô£à | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.std` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.sum` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.transform` | Ô£à | ÔÜá´©Å | ÔÜá´©Å | Ô£à | ÔÜá´©Å | ÔÜá´©Å |
| `groupby.var` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |

## Eixo 5 ÔÇö Paridade I/O por dtype

Ô£à = dtype mencionado/usado nos arquivos do parser/writer. ÔÜá´©Å = sem men├º├úo (dtype provavelmente n├úo suportado no formato). Limita├º├Áes conhecidas: `categorical` n├úo tem representa├º├úo nativa em CSV/JSON (lida como string e convertida via `astype`).


| dtype | CSV C | CSV Lua | JSON C | JSON Lua |
| :--- | :-: | :-: | :-: | :-: |
| `float64` | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `int64` | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `bool` | Ô£à | Ô£à | Ô£à | ÔÜá´©Å |
| `string` | Ô£à | Ô£à | Ô£à | Ô£à |
| `datetime` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |
| `categorical` | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å | ÔÜá´©Å |

## Eixo 6 ÔÇö Tipos de retorno consistentes

M├®todos cr├¡ticos: o tipo de retorno est├í conforme o esperado e sim├®trico entre dtypes? ÔÜá´©Å = diverg├¬ncia poss├¡vel. ÔØî = inconsist├¬ncia clara.


| m├®todo | esperado | detectado | status |
| :--- | :-: | :-: | :-: |
| `eq` | Series<bool> | ÔÇö | ÔØî n├úo encontrado |
| `ne` | Series<bool> | outro (compare(self, "cmp_ne", target) end) | ÔÜá´©Å |
| `lt` | Series<bool> | ÔÇö | ÔØî n├úo encontrado |
| `le` | Series<bool> | ÔÇö | ÔØî n├úo encontrado |
| `gt` | Series<bool> | ÔÇö | ÔØî n├úo encontrado |
| `ge` | Series<bool> | ÔÇö | ÔØî n├úo encontrado |
| `is_null` | valor escalar (bool) | outro (self._d.is_null(self._c, i - 1)) | ÔÜá´©Å |
| `isna` | valor escalar (bool) | ÔÇö | ÔØî n├úo encontrado |
| `notna` | valor escalar (bool) | Series (self) | ÔÜá´©Å |
| `unique` | Series | Series | Ô£à |
| `value_counts` | DataSet | outro (cnt[a.key] > cnt[b.key] end)) | ÔÜá´©Å |
| `describe` | tabela Lua | tabela Lua | Ô£à |
| `head` | Series | Series | Ô£à |
| `tail` | Series | Series | Ô£à |
| `take` | Series | outro (wrap(r, self._dtype, self._name)) | ÔÜá´©Å |
| `filter` | Series | outro (wrap(r, self._dtype, self._name)) | ÔÜá´©Å |
| `clone` | Series | outro (wrap(self._d.clone(self._c), self._dtype) | ÔÜá´©Å |
| `sort` | Series | outro (wrap(r, self._dtype, self._name)) | ÔÜá´©Å |
| `argsort` | tabela de ├¡ndices | nil/valor | ÔÜá´©Å |
| `to_table` | tabela Lua | outro (t) | ÔÜá´©Å |
| `cumsum` | Series | Series | Ô£à |
| `cumprod` | Series | Series | Ô£à |
| `cummax` | Series | Series | Ô£à |
| `cummin` | Series | Series | Ô£à |
| `diff` | Series | Series | Ô£à |
| `shift` | Series | Series | Ô£à |
| `map` | Series | outro (out) | ÔÜá´©Å |
| `CategoricalSeries:value_counts` | DataSet (paridade com Series) | outro (freq[a] > freq[b] end) | ÔØî inconsistente com Series |

## Eixo 7 ÔÇö Tratamento de null consistente

Cada m├®todo tem uma pol├¡tica de null esperada (ignore_na, erra, propaga). Verifica├º├úo heur├¡stica sobre o corpo da fun├º├úo. ÔÜá´©Å = padr├úo esperado n├úo foi detectado; pode ser implementa├º├úo alternativa ou bug.


| m├®todo | pol├¡tica esperada | detectado | status |
| :--- | :-: | :-: | :-: |
| `sum` | ignore_na flag | tem ignore_na | Ô£à |
| `mean` | ignore_na flag | tem ignore_na | Ô£à |
| `min` | ignore_na flag | tem ignore_na | Ô£à |
| `max` | ignore_na flag | tem ignore_na | Ô£à |
| `median` | ignore_na flag | tem ignore_na | Ô£à |
| `quantile` | ignore_na flag | tem ignore_na | Ô£à |
| `var` | ignore_na flag | tem ignore_na | Ô£à |
| `std` | ignore_na flag | tem ignore_na | Ô£à |
| `prod` | ignore_na flag | tem ignore_na | Ô£à |
| `skew` | ignore_na flag | sem ignore_na | ÔÜá´©Å |
| `kurtosis` | ignore_na flag | sem ignore_na | ÔÜá´©Å |
| `mad` | ignore_na flag | sem ignore_na | ÔÜá´©Å |
| `sem` | ignore_na flag | sem ignore_na | ÔÜá´©Å |
| `mode` | ignore_na flag | sem ignore_na | ÔÜá´©Å |
| `sort` | erra com null | verifica nulls | Ô£à |
| `argsort` | erra com null | verifica nulls | Ô£à |
| `abs` | propaga null | sem propaga├º├úo vis├¡vel | ÔÜá´©Å |
| `round` | propaga null | propaga | Ô£à |
| `clip` | propaga null | propaga | Ô£à |
| `cumsum` | propaga null | propaga | Ô£à |
| `cumprod` | propaga null | propaga | Ô£à |
| `cummin` | propaga null | propaga | Ô£à |
| `cummax` | propaga null | propaga | Ô£à |
| `diff` | propaga null | propaga | Ô£à |
| `shift` | propaga null | propaga | Ô£à |
| `sin` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `cos` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `tan` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `exp` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `log` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `sqrt` | propaga null | ÔÇö | ÔØî n├úo encontrado |

## Eixo 8 ÔÇö Nomenclatura consistente

Grupos de nomes que devem seguir conven├º├Áes claras. Aliases declarados via `methods.X = methods.Y` s├úo identificados automaticamente.


| grupo | m├®todo | Series | DataSet | nota |
| :--- | :-: | :-: | :-: | :-: |
| **Tamanho** | `len` | Ô£à | ÔÇö | DataSet: alias de `nrows` |
| **Tamanho** | `size` | ÔÇö | ÔÇö | Series: alias de `len` |
| **Nulidade ÔÇö predicados** | `is_null` | Ô£à | ÔÇö |  |
| **Nulidade ÔÇö predicados** | `isna` | Ô£à | ÔÇö |  |
| **Nulidade ÔÇö predicados** | `notna` | Ô£à | ÔÇö |  |
| **Contagem** | `count_nonnull` | Ô£à | ÔÇö |  |
| **Contagem** | `count_true` | Ô£à | ÔÇö |  |
| **L├│gica Kleene** | `land` | Ô£à | ÔÇö |  |
| **L├│gica Kleene** | `lor` | Ô£à | ÔÇö |  |
| **L├│gica Kleene** | `lxor` | Ô£à | ÔÇö |  |
| **L├│gica Kleene** | `lnot` | Ô£à | ÔÇö |  |
| **Sele├º├úo posicional** | `head` | Ô£à | Ô£à |  |
| **Sele├º├úo posicional** | `tail` | Ô£à | Ô£à |  |
| **Sele├º├úo posicional** | `take` | Ô£à | Ô£à |  |
| **Sele├º├úo posicional** | `view` | Ô£à | ÔÇö |  |
| **Sele├º├úo posicional** | `iloc` | ÔÇö | Ô£à |  |

### Conven├º├Áes

- **Tamanho:** Series tem ambos (size = alias de len). DataSet tem nrows + ncols.
- **Nulidade ÔÇö predicados:** Conven├º├úo: is_null ├® original; isna/notna s├úo aliases ergon├┤micos.
- **Contagem:** count_nonnull ├® universal; count_true ├® s├│ de Series<bool>.
- **L├│gica Kleene:** Exclusivos de Series<bool>. Nome com prefixo 'l' para n├úo chocar com palavras-chave Lua.
- **Sele├º├úo posicional:** Series tem head/tail/take/view. DataSet tem head/tail/take/iloc. iloc ├® range-based.

## Eixo 9 ÔÇö Sentinelas e contratos defensivos

Backend C deve usar sentinela documentada em retorno de `get`. Frontend Lua deve usar prefixo `smaug:` em todas as mensagens de erro.


### Sentinelas C

| dtype | sentinela esperada | presente? |
| :--- | :-: | :-: |
| `f64` | NaN | Ô£à usa |
| `i64` | INT64_MIN | Ô£à usa |
| `bool` | false / mask | Ô£à usa |
| `str` | NULL ptr | Ô£à usa |
| `dt` | INT64_MIN / DT_SENTINEL | Ô£à usa |

### Mensagens de erro Lua

- `series.lua`: 189/189 erros com prefixo `smaug:` (100.0%)
- `dataset.lua`: 88/88 erros com prefixo `smaug:` (100.0%)

## Eixo 10 ÔÇö Paridade de lifecycle

Cada dtype com backend C deve oferecer o mesmo conjunto de opera├º├Áes de lifecycle. `categorical` ├® Lua puro e n├úo entra nesta tabela (exce├º├úo em `exceptions.txt`).


| fun├º├úo | f64 | i64 | bool | str | dt |
| :--- | :-: | :-: | :-: | :-: | :-: |
| `create` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `create_with_capacity` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `create_from_array` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `free` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `clone` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `view` | Ô£à | Ô£à | Ô£à | ÔÜá´©Å | Ô£à |
| `append` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `append_null` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `set` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `set_null` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `get` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `is_null` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |

## Eixo 11 ÔÇö Cobertura de testes proporcional

Quantos checks cada arquivo de teste tem, e quantas vezes cada dtype ├® mencionado em cada arquivo (heur├¡stica: contagem de strings literais como `"float64"`, `"int64"` etc.).


### Por arquivo de teste

| arquivo | checks | float64 | int64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| `test_series` | 132 | 20 | 17 | ÔÇö | 4 | ÔÇö | ÔÇö |
| `test_dataset` | 125 | 20 | 16 | 4 | 4 | ÔÇö | ÔÇö |
| `test_edge` | 67 | 7 | 3 | ÔÇö | 2 | ÔÇö | ÔÇö |
| `test_special` | 37 | 7 | ÔÇö | ÔÇö | ÔÇö | ÔÇö | ÔÇö |
| `test_fillna` | 24 | 6 | 1 | ÔÇö | ÔÇö | ÔÇö | ÔÇö |
| `test_props` | 40 | 10 | 32 | ÔÇö | 7 | ÔÇö | ÔÇö |
| `test_i64` | 70 | 2 | 21 | ÔÇö | ÔÇö | ÔÇö | ÔÇö |
| `test_string` | 140 | 4 | 7 | ÔÇö | 27 | ÔÇö | ÔÇö |
| `test_bool_dtype` | 65 | 3 | 3 | 14 | 4 | ÔÇö | ÔÇö |
| `test_groupby` | 47 | 2 | 12 | 1 | 7 | ÔÇö | ÔÇö |
| `test_concat` | 36 | 4 | 8 | 3 | 8 | ÔÇö | ÔÇö |
| `test_join` | 53 | ÔÇö | 21 | ÔÇö | 6 | ÔÇö | ÔÇö |
| `test_series_ops` | 74 | 5 | 13 | ÔÇö | 2 | ÔÇö | ÔÇö |
| `test_dataset_ops` | 62 | 1 | 10 | ÔÇö | 5 | ÔÇö | ÔÇö |
| `test_str_tier_b` | 68 | ÔÇö | 1 | ÔÇö | 10 | ÔÇö | ÔÇö |
| `test_rolling_series` | 38 | 2 | 6 | ÔÇö | 1 | ÔÇö | ÔÇö |
| `test_io` | 71 | 3 | 2 | 2 | 5 | ÔÇö | ÔÇö |
| `test_io_real` | 56 | ÔÇö | 2 | 1 | 6 | ÔÇö | ÔÇö |
| `test_enrich` | 152 | 32 | 6 | ÔÇö | 2 | ÔÇö | ÔÇö |
| `test_datetime` | 189 | 3 | 5 | 1 | 7 | 42 | ÔÇö |
| `test_categorical` | 200 | 7 | 3 | 2 | 3 | 1 | 41 |

**Total de checks:** 1746

### Men├º├Áes totais por dtype (toda a suite)

| dtype | men├º├Áes |
| :--- | :-: |
| float64 | 138 |
| int64 | 189 |
| bool | 28 |
| string | 110 |
| datetime | 43 |
| categorical | 41 |

## Eixo 12 ÔÇö Sincroniza├º├úo docs Ôåö c├│digo

Cada m├®todo p├║blico do c├│digo deveria aparecer em `API_INDEX.md`. Faltantes podem ser gaps de documenta├º├úo ou m├®todos intencionalmente privados.


| categoria | total | documentados | faltam | % | detalhe |
| :--- | :-: | :-: | :-: | :-: | :-: |
| `Series.methods` | 95 | 95 | 0 | 100% | Ô£à completo |
| `DataSet.methods` | 48 | 48 | 0 | 100% | Ô£à completo |
| `GroupBy:*` | 15 | 15 | 0 | 100% | Ô£à completo |
| `CategoricalSeries:*` | 41 | 41 | 0 | 100% | Ô£à completo |
| `CatProxy:*` (.cat) | 6 | 6 | 0 | 100% | Ô£à completo |
| `StrProxy:*` (.str) | 28 | 28 | 0 | 100% | Ô£à completo |
| `SeriesDT:*` (.dt) | 33 | 33 | 0 | 100% | Ô£à completo |

---

## Resumo executivo


**Contagem global de status no relatÃ³rio:**

- âœ… paridade: 1
- âšª exceÃ§Ã£o registrada: 1
- âš ï¸ suspeita (revisar): 1
- âŒ inconsistÃªncia clara: 1


## Como usar este relatÃ³rio

1. Procure por âš ï¸ â€” cada um Ã© um candidato a gap real ou exceÃ§Ã£o a registrar.
2. Se for decisÃ£o consciente, adicione em `scripts/parity/exceptions.txt`.
3. Se for gap real, registre em `Roadmap.md` ou corrija e rode novamente.
4. Procure por âŒ â€” sempre gap real, exige aÃ§Ã£o.
