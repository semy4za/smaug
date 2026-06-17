# Smaug â€” RelatÃ³rio de Paridade

> Arquivo gerado por `bash scripts/parity/parity.sh` ou `powershell scripts/parity/parity.ps1`.
> **NÃ£o editar Ã  mÃ£o.** DecisÃµes conscientes de nÃ£o-paridade ficam em
> `scripts/parity/exceptions.txt`.

ConvenÃ§Ã£o de status:

- âœ… paridade presente
- âšª nÃ£o aplicÃ¡vel (exceÃ§Ã£o registrada em `exceptions.txt`)
- âš ï¸ ausÃªncia sem registro â€” suspeita, requer revisÃ£o humana
- âŒ inconsistÃªncia clara â€” gap real

Gerado em: 2026-06-17 14:33:25 UTC

## Eixo 1 ÔÇö Paridade de m├®todos entre dtypes

Cada linha = um m├®todo rastreado em `Series.methods` ou `CategoricalSeries`. Coluna = um dos 6 dtypes. Ô£à dispon├¡vel ┬À ÔÜ¬ n├úo aplic├ível (exce├º├úo registrada) ┬À ÔÜá´©Å aus├¬ncia sem registro (suspeita) ┬À ÔØî inconsist├¬ncia clara.

| m├®todo | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |

**Sum├írio Eixo 1:** 0 m├®todos ├ù 6 dtypes = 0 c├®lulas ┬À Ô£à 0 (nan%) ┬À ÔÜ¬ 0 (nan%) ┬À ÔÜá´©Å 0 (nan%)

## Eixo 2 ÔÇö Paridade Series Ôåö DataSet

M├®todos que existem em cada lado. Algumas assimetrias s├úo intencionais (ex: `Series:len` vs `DataSet:nrows/ncols`). Outras podem ser gaps reais.

| m├®todo | Series | DataSet | nota |
| :--- | :-: | :-: | :-: |

**Sum├írio Eixo 2:** 0 m├®todos em ambos ┬À 0 s├│ em Series ┬À 0 s├│ em DataSet

## Eixo 3 ÔÇö Espelhamento C Ôåö Lua

Cada fun├º├úo p├║blica do backend C deveria ter caminho no frontend Lua (direto via FFI ou exposto via m├®todo Series). ÔÜá´©Å = fun├º├úo C que n├úo aparece em `lua/smaug/core/series.lua` (pode ser ├│rf├ú ou exposta indiretamente via outro nome).


### f64 ÔÇö 49 fun├º├Áes C

| fun├º├úo C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add` | ÔÜá´©Å |  |
| `add_scalar` | ÔÜá´©Å |  |
| `append` | ÔÜá´©Å |  |
| `append_null` | ÔÜá´©Å |  |
| `argmax` | ÔÜá´©Å |  |
| `argmin` | ÔÜá´©Å |  |
| `argsort` | ÔÜá´©Å |  |
| `bfill` | ÔÜá´©Å |  |
| `clone` | ÔÜá´©Å |  |
| `count_nonnull` | ÔÜá´©Å |  |
| `create` | ÔÜá´©Å |  |
| `create_from_array` | ÔÜá´©Å |  |
| `create_with_capacity` | ÔÜá´©Å |  |
| `cummax` | ÔÜá´©Å |  |
| `cummin` | ÔÜá´©Å |  |
| `cumprod` | ÔÜá´©Å |  |
| `cumsum` | ÔÜá´©Å |  |
| `diff` | ÔÜá´©Å |  |
| `div` | ÔÜá´©Å |  |
| `div_scalar` | ÔÜá´©Å |  |
| `eq` | ÔÜá´©Å |  |
| `ffill` | ÔÜá´©Å |  |
| `filter` | ÔÜá´©Å |  |
| `free` | ÔÜá´©Å |  |
| `ge` | ÔÜá´©Å |  |
| `get` | ÔÜá´©Å |  |
| `gt` | ÔÜá´©Å |  |
| `is_null` | ÔÜá´©Å |  |
| `le` | ÔÜá´©Å |  |
| `lt` | ÔÜá´©Å |  |
| `max` | ÔÜá´©Å |  |
| `mean` | ÔÜá´©Å |  |
| `min` | ÔÜá´©Å |  |
| `mul` | ÔÜá´©Å |  |
| `mul_scalar` | ÔÜá´©Å |  |
| `ne` | ÔÜá´©Å |  |
| `rank` | ÔÜá´©Å |  |
| `set` | ÔÜá´©Å |  |
| `set_null` | ÔÜá´©Å |  |
| `shift` | ÔÜá´©Å |  |
| `sort` | ÔÜá´©Å |  |
| `sorted_nonnull` | ÔÜá´©Å |  |
| `std` | ÔÜá´©Å |  |
| `sub` | ÔÜá´©Å |  |
| `sub_scalar` | ÔÜá´©Å |  |
| `sum` | ÔÜá´©Å |  |
| `take` | ÔÜá´©Å |  |
| `var` | ÔÜá´©Å |  |
| `view` | ÔÜá´©Å |  |


### i64 ÔÇö 49 fun├º├Áes C

| fun├º├úo C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add` | ÔÜá´©Å |  |
| `add_scalar` | ÔÜá´©Å |  |
| `append` | ÔÜá´©Å |  |
| `append_null` | ÔÜá´©Å |  |
| `argmax` | ÔÜá´©Å |  |
| `argmin` | ÔÜá´©Å |  |
| `argsort` | ÔÜá´©Å |  |
| `bfill` | ÔÜá´©Å |  |
| `clone` | ÔÜá´©Å |  |
| `count_nonnull` | ÔÜá´©Å |  |
| `create` | ÔÜá´©Å |  |
| `create_from_array` | ÔÜá´©Å |  |
| `create_with_capacity` | ÔÜá´©Å |  |
| `cummax` | ÔÜá´©Å |  |
| `cummin` | ÔÜá´©Å |  |
| `cumprod` | ÔÜá´©Å |  |
| `cumsum` | ÔÜá´©Å |  |
| `diff` | ÔÜá´©Å |  |
| `div` | ÔÜá´©Å |  |
| `div_scalar` | ÔÜá´©Å |  |
| `eq` | ÔÜá´©Å |  |
| `ffill` | ÔÜá´©Å |  |
| `filter` | ÔÜá´©Å |  |
| `free` | ÔÜá´©Å |  |
| `ge` | ÔÜá´©Å |  |
| `get` | ÔÜá´©Å |  |
| `gt` | ÔÜá´©Å |  |
| `is_null` | ÔÜá´©Å |  |
| `le` | ÔÜá´©Å |  |
| `lt` | ÔÜá´©Å |  |
| `max` | ÔÜá´©Å |  |
| `mean` | ÔÜá´©Å |  |
| `min` | ÔÜá´©Å |  |
| `mul` | ÔÜá´©Å |  |
| `mul_scalar` | ÔÜá´©Å |  |
| `ne` | ÔÜá´©Å |  |
| `rank` | ÔÜá´©Å |  |
| `set` | ÔÜá´©Å |  |
| `set_null` | ÔÜá´©Å |  |
| `shift` | ÔÜá´©Å |  |
| `sort` | ÔÜá´©Å |  |
| `sorted_nonnull` | ÔÜá´©Å |  |
| `std` | ÔÜá´©Å |  |
| `sub` | ÔÜá´©Å |  |
| `sub_scalar` | ÔÜá´©Å |  |
| `sum` | ÔÜá´©Å |  |
| `take` | ÔÜá´©Å |  |
| `var` | ÔÜá´©Å |  |
| `view` | ÔÜá´©Å |  |


### bool ÔÇö 19 fun├º├Áes C

| fun├º├úo C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `all` | ÔÜá´©Å |  |
| `and` | ÔÜá´©Å |  |
| `any` | ÔÜá´©Å |  |
| `append` | ÔÜá´©Å |  |
| `append_null` | ÔÜá´©Å |  |
| `clone` | ÔÜá´©Å |  |
| `count_true` | ÔÜá´©Å |  |
| `create` | ÔÜá´©Å |  |
| `create_from_array` | ÔÜá´©Å |  |
| `create_with_capacity` | ÔÜá´©Å |  |
| `free` | ÔÜá´©Å |  |
| `get` | ÔÜá´©Å |  |
| `is_null` | ÔÜá´©Å |  |
| `not` | ÔÜá´©Å |  |
| `or` | ÔÜá´©Å |  |
| `set` | ÔÜá´©Å |  |
| `set_null` | ÔÜá´©Å |  |
| `view` | ÔÜá´©Å |  |
| `xor` | ÔÜá´©Å |  |


### str ÔÇö 22 fun├º├Áes C

| fun├º├úo C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `append` | ÔÜá´©Å |  |
| `append_null` | ÔÜá´©Å |  |
| `argsort` | ÔÜá´©Å |  |
| `clone` | ÔÜá´©Å |  |
| `count_nonnull` | ÔÜá´©Å |  |
| `create` | ÔÜá´©Å |  |
| `create_from_array` | ÔÜá´©Å |  |
| `create_with_capacity` | ÔÜá´©Å |  |
| `eq` | ÔÜá´©Å |  |
| `filter` | ÔÜá´©Å |  |
| `free` | ÔÜá´©Å |  |
| `ge` | ÔÜá´©Å |  |
| `get` | ÔÜá´©Å |  |
| `gt` | ÔÜá´©Å |  |
| `is_null` | ÔÜá´©Å |  |
| `le` | ÔÜá´©Å |  |
| `lt` | ÔÜá´©Å |  |
| `ne` | ÔÜá´©Å |  |
| `set` | ÔÜá´©Å |  |
| `set_null` | ÔÜá´©Å |  |
| `sort` | ÔÜá´©Å |  |
| `take` | ÔÜá´©Å |  |


### dt ÔÇö 40 fun├º├Áes C

| fun├º├úo C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add_ms` | ÔÜá´©Å |  |
| `append` | ÔÜá´©Å |  |
| `append_null` | ÔÜá´©Å |  |
| `argsort` | ÔÜá´©Å |  |
| `clone` | ÔÜá´©Å |  |
| `count_nonnull` | ÔÜá´©Å |  |
| `create` | ÔÜá´©Å |  |
| `create_from_array` | ÔÜá´©Å |  |
| `create_with_capacity` | ÔÜá´©Å |  |
| `day` | ÔÜá´©Å |  |
| `diff_ms` | ÔÜá´©Å |  |
| `eq` | ÔÜá´©Å |  |
| `filter` | ÔÜá´©Å |  |
| `format` | ÔÜá´©Å |  |
| `free` | ÔÜá´©Å |  |
| `from_parts` | ÔÜá´©Å |  |
| `ge` | ÔÜá´©Å |  |
| `get` | ÔÜá´©Å |  |
| `gt` | ÔÜá´©Å |  |
| `hour` | ÔÜá´©Å |  |
| `is_null` | ÔÜá´©Å |  |
| `le` | ÔÜá´©Å |  |
| `lt` | ÔÜá´©Å |  |
| `minute` | ÔÜá´©Å |  |
| `month` | ÔÜá´©Å |  |
| `ms` | ÔÜá´©Å |  |
| `ne` | ÔÜá´©Å |  |
| `parse` | ÔÜá´©Å |  |
| `quarter` | ÔÜá´©Å |  |
| `second` | ÔÜá´©Å |  |
| `set` | ÔÜá´©Å |  |
| `set_null` | ÔÜá´©Å |  |
| `sort` | ÔÜá´©Å |  |
| `take` | ÔÜá´©Å |  |
| `truncate` | ÔÜá´©Å |  |
| `view` | ÔÜá´©Å |  |
| `week` | ÔÜá´©Å |  |
| `weekday` | ÔÜá´©Å |  |
| `year` | ÔÜá´©Å |  |
| `yearday` | ÔÜá´©Å |  |

## Eixo 4 ÔÇö Paridade Anel 2 (opera├º├Áes relacionais) por dtype

Heur├¡stica conservadora: verifica men├º├úo expl├¡cita do dtype no corpo da fun├º├úo. Ô£à = dtype mencionado explicitamente (prov├ível suporte). ÔÜá´©Å = dtype n├úo mencionado (pode ser sem suporte, pode ser polimorfismo via dispatcher gen├®rico ÔÇö requer revis├úo manual).


### DataSet ÔÇö opera├º├Áes estruturais

| opera├º├úo | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `groupby` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `join` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `concat` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `pivot` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `pivot_table` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `melt` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `stack` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `unstack` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `explode` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `rolling` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `sort_by` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |
| `filter` | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à | Ô£à |

### GroupBy ÔÇö agrega├º├Áes

| opera├º├úo | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |

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
| `ne` | Series<bool> | ÔÇö | ÔØî n├úo encontrado |
| `lt` | Series<bool> | ÔÇö | ÔØî n├úo encontrado |
| `le` | Series<bool> | ÔÇö | ÔØî n├úo encontrado |
| `gt` | Series<bool> | ÔÇö | ÔØî n├úo encontrado |
| `ge` | Series<bool> | ÔÇö | ÔØî n├úo encontrado |
| `is_null` | valor escalar (bool) | ÔÇö | ÔØî n├úo encontrado |
| `isna` | valor escalar (bool) | ÔÇö | ÔØî n├úo encontrado |
| `notna` | valor escalar (bool) | ÔÇö | ÔØî n├úo encontrado |
| `unique` | Series | ÔÇö | ÔØî n├úo encontrado |
| `value_counts` | DataSet | ÔÇö | ÔØî n├úo encontrado |
| `describe` | tabela Lua | ÔÇö | ÔØî n├úo encontrado |
| `head` | Series | ÔÇö | ÔØî n├úo encontrado |
| `tail` | Series | ÔÇö | ÔØî n├úo encontrado |
| `take` | Series | ÔÇö | ÔØî n├úo encontrado |
| `filter` | Series | ÔÇö | ÔØî n├úo encontrado |
| `clone` | Series | ÔÇö | ÔØî n├úo encontrado |
| `sort` | Series | ÔÇö | ÔØî n├úo encontrado |
| `argsort` | tabela de ├¡ndices | ÔÇö | ÔØî n├úo encontrado |
| `to_table` | tabela Lua | ÔÇö | ÔØî n├úo encontrado |
| `cumsum` | Series | ÔÇö | ÔØî n├úo encontrado |
| `cumprod` | Series | ÔÇö | ÔØî n├úo encontrado |
| `cummax` | Series | ÔÇö | ÔØî n├úo encontrado |
| `cummin` | Series | ÔÇö | ÔØî n├úo encontrado |
| `diff` | Series | ÔÇö | ÔØî n├úo encontrado |
| `shift` | Series | ÔÇö | ÔØî n├úo encontrado |
| `map` | Series | ÔÇö | ÔØî n├úo encontrado |
| `CategoricalSeries:value_counts` | DataSet (paridade com Series) | ÔÇö | ÔØî inconsistente com Series |

## Eixo 7 ÔÇö Tratamento de null consistente

Cada m├®todo tem uma pol├¡tica de null esperada (ignore_na, erra, propaga). Verifica├º├úo heur├¡stica sobre o corpo da fun├º├úo. ÔÜá´©Å = padr├úo esperado n├úo foi detectado; pode ser implementa├º├úo alternativa ou bug.


| m├®todo | pol├¡tica esperada | detectado | status |
| :--- | :-: | :-: | :-: |
| `sum` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `mean` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `min` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `max` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `median` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `quantile` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `var` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `std` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `prod` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `skew` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `kurtosis` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `mad` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `sem` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `mode` | ignore_na flag | ÔÇö | ÔØî n├úo encontrado |
| `sort` | erra com null | ÔÇö | ÔØî n├úo encontrado |
| `argsort` | erra com null | ÔÇö | ÔØî n├úo encontrado |
| `abs` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `round` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `clip` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `cumsum` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `cumprod` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `cummin` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `cummax` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `diff` | propaga null | ÔÇö | ÔØî n├úo encontrado |
| `shift` | propaga null | ÔÇö | ÔØî n├úo encontrado |
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
| **Tamanho** | `len` | ÔÇö | ÔÇö |  |
| **Tamanho** | `size` | ÔÇö | ÔÇö |  |
| **Nulidade ÔÇö predicados** | `is_null` | ÔÇö | ÔÇö |  |
| **Nulidade ÔÇö predicados** | `isna` | ÔÇö | ÔÇö |  |
| **Nulidade ÔÇö predicados** | `notna` | ÔÇö | ÔÇö |  |
| **Contagem** | `count_nonnull` | ÔÇö | ÔÇö |  |
| **Contagem** | `count_true` | ÔÇö | ÔÇö |  |
| **L├│gica Kleene** | `land` | ÔÇö | ÔÇö |  |
| **L├│gica Kleene** | `lor` | ÔÇö | ÔÇö |  |
| **L├│gica Kleene** | `lxor` | ÔÇö | ÔÇö |  |
| **L├│gica Kleene** | `lnot` | ÔÇö | ÔÇö |  |
| **Sele├º├úo posicional** | `head` | ÔÇö | ÔÇö |  |
| **Sele├º├úo posicional** | `tail` | ÔÇö | ÔÇö |  |
| **Sele├º├úo posicional** | `take` | ÔÇö | ÔÇö |  |
| **Sele├º├úo posicional** | `view` | ÔÇö | ÔÇö |  |
| **Sele├º├úo posicional** | `iloc` | ÔÇö | ÔÇö |  |

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

- `series.lua`: 0/0 erros com prefixo `smaug:` (0.0%)
- `dataset.lua`: 0/0 erros com prefixo `smaug:` (0.0%)

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
| `series/test_constructors` | 268 | 25 | 41 | 14 | 8 | ÔÇö | ÔÇö |
| `series/test_access` | 92 | 13 | 4 | ÔÇö | 2 | ÔÇö | ÔÇö |
| `series/test_reduce` | 38 | 7 | ÔÇö | ÔÇö | ÔÇö | ÔÇö | ÔÇö |
| `series/test_stat` | 136 | 30 | 15 | ÔÇö | 5 | ÔÇö | ÔÇö |
| `series/test_window` | 64 | 5 | 6 | ÔÇö | 1 | ÔÇö | ÔÇö |
| `series/test_predicates` | 155 | 6 | 42 | 3 | 11 | ÔÇö | ÔÇö |
| `series/test_selection` | 23 | 3 | 1 | ÔÇö | 1 | ÔÇö | ÔÇö |
| `series/test_str` | 271 | 4 | 9 | 1 | 49 | ÔÇö | ÔÇö |
| `series/test_dt` | 256 | 3 | 6 | 2 | 9 | 58 | ÔÇö |
| `series/test_categorical` | 295 | 7 | 7 | 8 | 5 | 13 | 57 |
| `dataset/test_core` | 208 | 26 | 30 | 4 | 11 | ÔÇö | ÔÇö |
| `dataset/test_relational` | 164 | 10 | 41 | 4 | 22 | ÔÇö | ÔÇö |
| `dataset/test_stat` | 50 | 3 | 6 | ÔÇö | 7 | ÔÇö | ÔÇö |
| `dataset/test_io_support` | 44 | 2 | 13 | 1 | 6 | ÔÇö | ÔÇö |
| `io/test_csv` | 101 | 2 | 3 | 2 | 9 | ÔÇö | ÔÇö |
| `io/test_json` | 28 | 1 | 1 | 1 | 2 | ÔÇö | ÔÇö |
| `props/test_props` | 40 | 10 | 32 | ÔÇö | 7 | ÔÇö | ÔÇö |
| `props/test_integration` | 67 | 18 | 2 | ÔÇö | ÔÇö | ÔÇö | ÔÇö |

**Total de checks:** 2300

### Men├º├Áes totais por dtype (toda a suite)

| dtype | men├º├Áes |
| :--- | :-: |
| float64 | 175 |
| int64 | 259 |
| bool | 40 |
| string | 155 |
| datetime | 71 |
| categorical | 57 |

## Eixo 12 ÔÇö Sincroniza├º├úo docs Ôåö c├│digo

Cada m├®todo p├║blico do c├│digo deveria aparecer em `API_INDEX.md`. Faltantes podem ser gaps de documenta├º├úo ou m├®todos intencionalmente privados.


| categoria | total | documentados | faltam | % | detalhe |
| :--- | :-: | :-: | :-: | :-: | :-: |
| `Series.methods` | 0 | 0 | 0 | 0% | Ô£à completo |
| `DataSet.methods` | 0 | 0 | 0 | 0% | Ô£à completo |
| `GroupBy:*` | 0 | 0 | 0 | 0% | Ô£à completo |
| `CategoricalSeries:*` | 0 | 0 | 0 | 0% | Ô£à completo |
| `CatProxy:*` (.cat) | 0 | 0 | 0 | 0% | Ô£à completo |
| `StrProxy:*` (.str) | 0 | 0 | 0 | 0% | Ô£à completo |
| `SeriesDT:*` (.dt) | 0 | 0 | 0 | 0% | Ô£à completo |

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
