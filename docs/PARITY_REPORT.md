# Smaug — Relatório de Paridade

> Arquivo gerado por `bash scripts/parity/parity.sh` ou `powershell scripts/parity/parity.ps1`.
> **Não editar à mão.** Decisões conscientes de não-paridade ficam em
> `scripts/parity/exceptions.txt`.

Convenção de status:

- 🟩 paridade presente
- ⬜ não aplicável (exceção registrada em `exceptions.txt`)
- 🟨 ausência sem registro — suspeita, requer revisão humana
- 🟥 inconsistência clara — gap real

Gerado em: 2026-07-16 14:43:52 UTC

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
| `dtype` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟨 |
| `duplicated` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `eq` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟩 |
| `equals` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `expanding` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `ffill` | 🟩 | 🟩 | 🟨 | 🟨 | 🟩 | 🟩 |
| `fillna` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `filter` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟩 |
| `first_valid_index` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 | 🟨 |
| `ge` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟩 |
| `get` | 🟨 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `get_raw` | 🟨 | 🟩 | 🟨 | 🟨 | 🟨 | 🟨 |
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
| `pct_rank` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | ⬜ |
| `prod` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `quantile` | 🟩 | 🟩 | ⬜ | ⬜ | 🟩 | ⬜ |
| `rank` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | ⬜ |
| `rep_each` | 🟨 | 🟨 | 🟩 | 🟨 | 🟨 | 🟨 |
| `rolling` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `round` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `sample` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟨 |
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
| `to_markdown` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟨 |
| `to_string` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟨 |
| `to_table` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `unique` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `value_counts` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |
| `var` | 🟩 | 🟩 | ⬜ | ⬜ | ⬜ | ⬜ |
| `view` | 🟩 | 🟩 | 🟨 | ⬜ | 🟨 | 🟩 |
| `where` | 🟩 | 🟩 | 🟨 | 🟨 | 🟨 | 🟩 |

**Sumário Eixo 1:** 101 métodos × 6 dtypes = 606 células · 🟩 276 (45.5%) · ⬜ 135 (22.3%) · 🟨 195 (32.2%)

## Eixo 2 — Paridade Series ↔ DataSet (classificada)

Cada assimetria é classificada: 🟩 ambos · 🟦 par de nome · ⬜ intencional (exceptions.txt) · 🟥 gap real. Series é 1-D, DataSet é 2-D.

| método | Series | DataSet | classificação |
| :--- | :-: | :-: | :-: |
| `_raw_column` | — | 🟩 | ⬜ acesso interno cru à coluna, sem view COW (2-D); só código interno |
| `abs` | 🟩 | 🟩 | 🟩  |
| `add_column` | — | 🟩 | ⬜ gerência de coluna (2-D) |
| `all` | 🟩 | — | ⬜ redução booleana de uma coluna (1-D) |
| `any` | 🟩 | — | ⬜ redução booleana de uma coluna (1-D) |
| `append` | 🟩 | — | ⬜ concatenação de séries (1-D); DataSet usa concat |
| `argmax` | 🟩 | — | ⬜ índice do máximo (1-D) |
| `argmin` | 🟩 | — | ⬜ índice do mínimo (1-D) |
| `argsort` | 🟩 | — | ⬜ permutação de ordenação (1-D) |
| `assign` | — | 🟩 | ⬜ coluna calculada (2-D) |
| `astype` | 🟩 | 🟩 | 🟩  |
| `at` | — | 🟩 | ⬜ célula por (linha, nome) (2-D) |
| `autocorr` | 🟩 | — | ⬜ autocorrelação de uma sequência (1-D) |
| `between` | 🟩 | — | ⬜ faixa element-wise → máscara (1-D) |
| `bfill` | 🟩 | 🟩 | 🟩  |
| `clip` | 🟩 | 🟩 | 🟩  |
| `clone` | 🟩 | 🟩 | 🟩  |
| `column` | — | 🟩 | ⬜ acesso a coluna por nome (2-D) |
| `columns` | — | 🟩 | ⬜ lista de nomes de coluna (2-D) |
| `combine_first` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `compare` | 🟩 | 🟩 | 🟩  |
| `concat` | — | 🟩 | ⬜ concatenação de frames (2-D) |
| `corr` | 🟩 | 🟩 | 🟩  |
| `count_nonnull` | 🟩 | 🟩 | 🟩  |
| `count_true` | 🟩 | — | ⬜ contagem booleana de uma coluna (1-D) |
| `cov` | 🟩 | 🟩 | 🟩  |
| `cummax` | 🟩 | 🟩 | 🟩  |
| `cummin` | 🟩 | 🟩 | 🟩  |
| `cumprod` | 🟩 | 🟩 | 🟩  |
| `cumsum` | 🟩 | 🟩 | 🟩  |
| `describe` | 🟩 | 🟩 | 🟩  |
| `diff` | 🟩 | 🟩 | 🟩  |
| `dot` | 🟩 | — | ⬜ produto escalar entre duas séries (1-D) |
| `drop_column` | — | 🟩 | ⬜ gerência de coluna (2-D) |
| `drop_duplicates` | 🟩 | 🟩 | 🟩  |
| `dropna` | 🟩 | 🟩 | 🟩  |
| `dtype` | 🟩 | — | 🟦 par de `dtypes` |
| `dtypes` | — | 🟩 | 🟦 par de `dtype` |
| `duplicated` | 🟩 | 🟩 | 🟩  |
| `eq` | 🟩 | — | ⬜ comparação element-wise → máscara (1-D) |
| `equals` | 🟩 | 🟩 | 🟩  |
| `expanding` | 🟩 | — | ⬜ janela expansível sobre uma sequência (1-D) |
| `explode` | — | 🟩 | ⬜ explosão de coluna-lista (2-D) |
| `ffill` | 🟩 | 🟩 | 🟩  |
| `fillna` | 🟩 | 🟩 | 🟩  |
| `filter` | 🟩 | 🟩 | 🟩  |
| `first_valid_index` | 🟩 | — | ⬜ primeiro índice não-NA (1-D) |
| `ge` | 🟩 | — | ⬜ comparação element-wise → máscara (1-D) |
| `get` | 🟩 | — | ⬜ acesso a elemento individual (1-D) |
| `get_raw` | 🟩 | — | ⬜ acesso a elemento int64 cru sem perda de precisão (1-D); DataSet acessa via column() |
| `groupby` | — | 🟩 | ⬜ agregação por chave (2-D) |
| `gt` | 🟩 | — | ⬜ comparação element-wise → máscara (1-D) |
| `has_column` | — | 🟩 | ⬜ existência de coluna (2-D) |
| `head` | 🟩 | 🟩 | 🟩  |
| `iat` | — | 🟩 | ⬜ célula por (linha, índice de coluna) (2-D) |
| `idxmax` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `idxmin` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `iloc` | — | 🟩 | ⬜ linha por posição (2-D) |
| `insert` | — | 🟩 | ⬜ inserção de coluna em posição (2-D) |
| `is_monotonic_decreasing` | 🟩 | — | ⬜ monotonicidade de uma sequência (1-D) |
| `is_monotonic_increasing` | 🟩 | — | ⬜ monotonicidade de uma sequência (1-D) |
| `is_null` | 🟩 | — | ⬜ nulidade de elemento individual (1-D); DataSet usa isna (vetorizado) |
| `is_unique` | 🟩 | — | ⬜ unicidade dos valores de uma coluna (1-D) |
| `isin` | 🟩 | — | ⬜ pertencimento element-wise → máscara (1-D) |
| `isna` | 🟩 | 🟩 | 🟩  |
| `join` | — | 🟩 | ⬜ junção por chave (2-D) |
| `kurtosis` | 🟩 | 🟩 | 🟩  |
| `land` | 🟩 | — | ⬜ lógica Kleene element-wise (1-D) |
| `last_valid_index` | 🟩 | — | ⬜ último índice não-NA (1-D) |
| `le` | 🟩 | — | ⬜ comparação element-wise → máscara (1-D) |
| `len` | 🟩 | — | 🟦 par de `nrows` |
| `lnot` | 🟩 | — | ⬜ lógica Kleene element-wise (1-D) |
| `lor` | 🟩 | — | ⬜ lógica Kleene element-wise (1-D) |
| `lt` | 🟩 | — | ⬜ comparação element-wise → máscara (1-D) |
| `lxor` | 🟩 | — | ⬜ lógica Kleene element-wise (1-D) |
| `mad` | 🟩 | 🟩 | 🟩  |
| `map` | 🟩 | — | ⬜ transformação valor-a-valor de uma coluna (1-D); DataSet usa assign |
| `mask` | 🟩 | — | ⬜ mascaramento condicional element-wise (1-D) |
| `max` | 🟩 | 🟩 | 🟩  |
| `mean` | 🟩 | 🟩 | 🟩  |
| `median` | 🟩 | 🟩 | 🟩  |
| `melt` | — | 🟩 | ⬜ desempilhamento largo→longo (2-D) |
| `min` | 🟩 | 🟩 | 🟩  |
| `mode` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `ncols` | — | 🟩 | ⬜ número de colunas (2-D); Series é uma coluna |
| `ne` | 🟩 | — | ⬜ comparação element-wise → máscara (1-D) |
| `nlargest` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `notna` | 🟩 | 🟩 | 🟩  |
| `nrows` | — | 🟩 | 🟦 par de `len` |
| `nsmallest` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `nunique` | 🟩 | 🟩 | 🟩  |
| `pct_change` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `pct_rank` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `pivot` | — | 🟩 | ⬜ pivoteamento (2-D) |
| `pivot_table` | — | 🟩 | ⬜ pivoteamento com agregação (2-D) |
| `prod` | 🟩 | 🟩 | 🟩  |
| `quantile` | 🟩 | 🟩 | 🟩  |
| `rank` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `rename` | — | 🟩 | ⬜ renomeio de colunas em lote (2-D) |
| `rename_column` | — | 🟩 | ⬜ gerência de coluna (2-D) |
| `rep_each` | 🟩 | — | ⬜ repetição element-wise (1-D) |
| `rolling` | 🟩 | 🟩 | 🟩  |
| `round` | 🟩 | 🟩 | 🟩  |
| `row` | — | 🟩 | ⬜ linha como tabela (2-D) |
| `sample` | 🟩 | 🟩 | 🟩  |
| `searchsorted` | 🟩 | — | ⬜ busca binária em série ordenada (1-D) |
| `select` | — | 🟩 | ⬜ projeção de colunas (2-D) |
| `sem` | 🟩 | 🟩 | 🟩  |
| `set` | 🟩 | — | ⬜ escrita de elemento individual (1-D) |
| `set_null` | 🟩 | — | ⬜ marca elemento individual como NA (1-D) |
| `shift` | 🟩 | 🟩 | 🟩  |
| `skew` | 🟩 | 🟩 | 🟩  |
| `sort` | 🟩 | — | 🟦 par de `sort_by` |
| `sort_by` | — | 🟩 | 🟦 par de `sort` |
| `stack` | — | 🟩 | ⬜ empilhamento de colunas (2-D) |
| `std` | 🟩 | 🟩 | 🟩  |
| `sum` | 🟩 | 🟩 | 🟩  |
| `tail` | 🟩 | 🟩 | 🟩  |
| `take` | 🟩 | 🟩 | 🟩  |
| `to_dict` | — | 🟩 | ⬜ export coluna→lista (2-D); Series usa to_table |
| `to_markdown` | 🟩 | 🟩 | 🟩  |
| `to_string` | 🟩 | 🟩 | 🟩  |
| `to_table` | 🟩 | 🟩 | 🟩  |
| `unique` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `unstack` | — | 🟩 | ⬜ desempilhamento (2-D) |
| `update_column` | — | 🟩 | ⬜ gerência de coluna (2-D) |
| `value_counts` | 🟩 | — | ⬜ por-coluna no DataSet faz sentido — escopo futuro |
| `var` | 🟩 | 🟩 | 🟩  |
| `view` | 🟩 | — | ⬜ buffer compartilhado de uma coluna (1-D); DataSet não tem buffer único |
| `where` | 🟩 | — | ⬜ seleção condicional element-wise (1-D) |

**Sumário Eixo 2:** 48 em ambos · 6 pares de nome · 76 intencionais · 0 gaps reais

## Eixo 3 — Espelhamento C ↔ Lua

Cada função pública do backend C deveria ter caminho no frontend Lua (direto via FFI ou exposto via método Series). 🟨 = função C que não aparece em `lua/smaug/core/series.lua` (pode ser órfã ou exposta indiretamente via outro nome).


### f64 — 53 funções C

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
| `coalesce` | 🟩 |  |
| `coalesce_scalar` | 🟩 |  |
| `count_nonfinite` | 🟨 |  |
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
| `select` | 🟩 |  |
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


### i64 — 52 funções C

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
| `coalesce` | 🟩 |  |
| `coalesce_scalar` | 🟩 |  |
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
| `select` | 🟩 |  |
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
| `view` | 🟩 |  |
| `xor` | 🟨 |  |


### str — 34 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `append` | 🟩 |  |
| `append_null` | 🟩 |  |
| `argmax` | 🟩 |  |
| `argmin` | 🟩 |  |
| `argsort` | 🟩 |  |
| `bfill` | 🟩 |  |
| `clone` | 🟩 |  |
| `coalesce` | 🟩 |  |
| `coalesce_scalar` | 🟩 |  |
| `count_nonnull` | 🟩 |  |
| `create` | 🟩 |  |
| `create_from_array` | 🟨 |  |
| `create_with_capacity` | 🟨 |  |
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
| `min` | 🟩 |  |
| `ne` | 🟩 |  |
| `rank` | 🟩 |  |
| `select` | 🟩 |  |
| `set` | 🟩 |  |
| `set_null` | 🟩 |  |
| `shift` | 🟩 |  |
| `sort` | 🟩 |  |
| `take` | 🟩 |  |
| `view` | 🟩 |  |


### dt — 51 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add_ms` | 🟩 |  |
| `append` | 🟩 |  |
| `append_null` | 🟩 |  |
| `argmax` | 🟩 |  |
| `argmin` | 🟩 |  |
| `argsort` | 🟩 |  |
| `bfill` | 🟩 |  |
| `clone` | 🟩 |  |
| `coalesce` | 🟩 |  |
| `coalesce_scalar` | 🟩 |  |
| `count_nonnull` | 🟩 |  |
| `create` | 🟩 |  |
| `create_from_array` | 🟨 |  |
| `create_with_capacity` | 🟨 |  |
| `day` | 🟩 |  |
| `diff_ms` | 🟩 |  |
| `eq` | 🟩 |  |
| `ffill` | 🟩 |  |
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
| `max` | 🟩 |  |
| `min` | 🟩 |  |
| `minute` | 🟩 |  |
| `month` | 🟩 |  |
| `ms` | 🟩 |  |
| `ne` | 🟩 |  |
| `parse` | 🟩 |  |
| `quarter` | 🟩 |  |
| `rank` | 🟩 |  |
| `second` | 🟩 |  |
| `select` | 🟩 |  |
| `set` | 🟩 |  |
| `set_null` | 🟩 |  |
| `shift` | 🟩 |  |
| `sort` | 🟩 |  |
| `take` | 🟩 |  |
| `truncate` | 🟩 |  |
| `view` | 🟩 |  |
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
| `float64` | 🟩 | 🟩 | 🟩 | 🟩 |
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
| **Nulidade — predicados** | `isna` | 🟩 | 🟩 |  |
| **Nulidade — predicados** | `notna` | 🟩 | 🟩 |  |
| **Contagem** | `count_nonnull` | 🟩 | 🟩 |  |
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

- `series.lua`: 242/242 erros com prefixo `smaug:` (100.0%)
- `dataset.lua`: 94/94 erros com prefixo `smaug:` (100.0%)

## Eixo 10 — Paridade de lifecycle

Cada dtype com backend C deve oferecer o mesmo conjunto de operações de lifecycle. `categorical` é Lua puro e não entra nesta tabela (exceção em `exceptions.txt`).


| função | f64 | i64 | bool | str | dt |
| :--- | :-: | :-: | :-: | :-: | :-: |
| `create` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `create_with_capacity` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `create_from_array` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `free` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `clone` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `view` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `append` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `append_null` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `set` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `set_null` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `get` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |
| `is_null` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |

**Cruzamento header C ↔ descritor DTYPES** (funções de dois-lados): a função existe no C *e* é exposta no descritor de `_types.lua`? 🟥 = C tem mas o descritor não expõe (ou vice-versa) sem exceção registrada.

| função | f64 | i64 | bool | str | dt |
| :--- | :-: | :-: | :-: | :-: | :-: |
| `view` | 🟩 | 🟩 | 🟩 | 🟩 | 🟩 |

## Eixo 11 — Cobertura de testes proporcional

Quantos checks cada arquivo de teste tem, e quantas vezes cada dtype é mencionado em cada arquivo (heurística: contagem de strings literais como `"float64"`, `"int64"` etc.).


### Por arquivo de teste

| arquivo | checks | float64 | int64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: | :-: |
| `series/test_constructors` | 344 | 38 | 62 | 22 | 16 | 2 | 1 |
| `series/test_access` | 121 | 19 | 12 | — | 9 | 1 | — |
| `series/test_reduce` | 57 | 7 | 2 | 3 | 4 | 2 | — |
| `series/test_stat` | 70 | 6 | 12 | — | 9 | — | — |
| `series/test_window` | 123 | 10 | 12 | 2 | 5 | 2 | — |
| `series/test_predicates` | 168 | 8 | 46 | 3 | 15 | 2 | — |
| `series/test_selection` | 54 | 6 | 4 | 6 | 6 | 2 | — |
| `series/test_str` | 273 | 4 | 9 | 1 | 50 | — | — |
| `series/test_dt` | 272 | 3 | 6 | 2 | 12 | 62 | — |
| `series/test_categorical` | 300 | 7 | 7 | 8 | 5 | 13 | 58 |
| `dataset/test_core` | 238 | 30 | 33 | 8 | 14 | — | 1 |
| `dataset/test_relational` | 169 | 10 | 50 | 4 | 34 | — | — |
| `dataset/test_stat` | 91 | 10 | 16 | 1 | 13 | — | — |
| `dataset/test_io_support` | 53 | 4 | 15 | 1 | 7 | — | — |
| `io/test_csv` | 124 | 3 | 5 | 2 | 9 | — | — |
| `io/test_json` | 44 | 4 | 3 | 1 | 2 | — | — |
| `props/test_props` | 40 | 10 | 32 | — | 7 | — | — |
| `props/test_integration` | 79 | 19 | 2 | 2 | 4 | 1 | 1 |

**Total de checks:** 2620

### Menções totais por dtype (toda a suite)

| dtype | menções |
| :--- | :-: |
| float64 | 198 |
| int64 | 328 |
| bool | 66 |
| string | 221 |
| datetime | 87 |
| categorical | 61 |

## Eixo 12 — Sincronização docs ↔ código

Cada método público do código deveria aparecer em `API_INDEX.md`. Faltantes podem ser gaps de documentação ou métodos intencionalmente privados.


| categoria | total | documentados | faltam | % | detalhe |
| :--- | :-: | :-: | :-: | :-: | :-: |
| `Series.methods` | 100 | 100 | 0 | 100% | 🟩 completo |
| `DataSet.methods` | 78 | 77 | 1 | 99% | 🟩 completo |
| `GroupBy:*` | 15 | 15 | 0 | 100% | 🟩 completo |
| `CategoricalSeries:*` | 42 | 42 | 0 | 100% | 🟩 completo |
| `CatProxy:*` (.cat) | 6 | 6 | 0 | 100% | 🟩 completo |
| `StrProxy:*` (.str) | 28 | 28 | 0 | 100% | 🟩 completo |
| `SeriesDT:*` (.dt) | 33 | 33 | 0 | 100% | 🟩 completo |

## Eixo 13 — Ergonomia REPL — __tostring de objetos expostos

🟩 = objeto tem __tostring (não vaza 'table: 0x…'). 🟥 = ausente. Invariante do item 11.3: todo objeto que o usuário segura se auto-mostra legível. A formatação de células segue a fonte única `core/display.lua` (itens 11.4/11.5).


| objeto exposto | __tostring |
| :--- | :-: |
| `Series` | 🟩 |
| `DataSet` | 🟩 |
| `CategoricalSeries` | 🟩 |
| `StrProxy (.str)` | 🟩 |
| `SeriesDT (.dt)` | 🟩 |
| `SeriesAt (.at)` | 🟩 |
| `CatProxy (.cat)` | 🟩 |
| `SeriesRolling` | 🟩 |
| `SeriesExpanding` | 🟩 |
| `GroupBy` | 🟩 |
| `Rolling (DataSet)` | 🟩 |

---

## Resumo executivo


**Contagem global de status no relatório:**

- 🟩 paridade: 998
- ⬜ exceção registrada: 215
- 🟨 suspeita (revisar): 270
- 🟥 inconsistência clara: 13


## Como usar este relatório

1. Procure por 🟨 — cada um é um candidato a gap real ou exceção a registrar.
2. Se for decisão consciente, adicione em `scripts/parity/exceptions.txt`.
3. Se for gap real, registre em `Roadmap.md` ou corrija e rode novamente.
4. Procure por 🟥 — sempre gap real, exige ação.