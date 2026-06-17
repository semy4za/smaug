# Smaug — Relatório de Paridade

> Arquivo gerado por `bash scripts/parity/parity.sh` ou `powershell scripts/parity/parity.ps1`.
> **Não editar à mão.** Decisões conscientes de não-paridade ficam em
> `scripts/parity/exceptions.txt`.

Convenção de status:

- ✅ paridade presente
- ⚪ não aplicável (exceção registrada em `exceptions.txt`)
- ⚠️ ausência sem registro — suspeita, requer revisão humana
- ❌ inconsistência clara — gap real

Gerado em: 2026-06-17 17:45:08 UTC

## Eixo 1 — Paridade de métodos entre dtypes

Cada linha = um método rastreado em `Series.methods` ou `CategoricalSeries`. Coluna = um dos 6 dtypes. ✅ disponível · ⚪ não aplicável (exceção registrada) · ⚠️ ausência sem registro (suspeita) · ❌ inconsistência clara.

| método | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |

**Sumário Eixo 1:** 0 métodos × 6 dtypes = 0 células · ✅ 0 (nan%) · ⚪ 0 (nan%) · ⚠️ 0 (nan%)

## Eixo 2 — Paridade Series ↔ DataSet

Métodos que existem em cada lado. Algumas assimetrias são intencionais (ex: `Series:len` vs `DataSet:nrows/ncols`). Outras podem ser gaps reais.

| método | Series | DataSet | nota |
| :--- | :-: | :-: | :-: |

**Sumário Eixo 2:** 0 métodos em ambos · 0 só em Series · 0 só em DataSet

## Eixo 3 — Espelhamento C ↔ Lua

Cada função pública do backend C deveria ter caminho no frontend Lua (direto via FFI ou exposto via método Series). ⚠️ = função C que não aparece em `lua/smaug/core/series.lua` (pode ser órfã ou exposta indiretamente via outro nome).


### f64 — 49 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add` | ⚠️ |  |
| `add_scalar` | ⚠️ |  |
| `append` | ⚠️ |  |
| `append_null` | ⚠️ |  |
| `argmax` | ⚠️ |  |
| `argmin` | ⚠️ |  |
| `argsort` | ⚠️ |  |
| `bfill` | ⚠️ |  |
| `clone` | ⚠️ |  |
| `count_nonnull` | ⚠️ |  |
| `create` | ⚠️ |  |
| `create_from_array` | ⚠️ |  |
| `create_with_capacity` | ⚠️ |  |
| `cummax` | ⚠️ |  |
| `cummin` | ⚠️ |  |
| `cumprod` | ⚠️ |  |
| `cumsum` | ⚠️ |  |
| `diff` | ⚠️ |  |
| `div` | ⚠️ |  |
| `div_scalar` | ⚠️ |  |
| `eq` | ⚠️ |  |
| `ffill` | ⚠️ |  |
| `filter` | ⚠️ |  |
| `free` | ⚠️ |  |
| `ge` | ⚠️ |  |
| `get` | ⚠️ |  |
| `gt` | ⚠️ |  |
| `is_null` | ⚠️ |  |
| `le` | ⚠️ |  |
| `lt` | ⚠️ |  |
| `max` | ⚠️ |  |
| `mean` | ⚠️ |  |
| `min` | ⚠️ |  |
| `mul` | ⚠️ |  |
| `mul_scalar` | ⚠️ |  |
| `ne` | ⚠️ |  |
| `rank` | ⚠️ |  |
| `set` | ⚠️ |  |
| `set_null` | ⚠️ |  |
| `shift` | ⚠️ |  |
| `sort` | ⚠️ |  |
| `sorted_nonnull` | ⚠️ |  |
| `std` | ⚠️ |  |
| `sub` | ⚠️ |  |
| `sub_scalar` | ⚠️ |  |
| `sum` | ⚠️ |  |
| `take` | ⚠️ |  |
| `var` | ⚠️ |  |
| `view` | ⚠️ |  |


### i64 — 49 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add` | ⚠️ |  |
| `add_scalar` | ⚠️ |  |
| `append` | ⚠️ |  |
| `append_null` | ⚠️ |  |
| `argmax` | ⚠️ |  |
| `argmin` | ⚠️ |  |
| `argsort` | ⚠️ |  |
| `bfill` | ⚠️ |  |
| `clone` | ⚠️ |  |
| `count_nonnull` | ⚠️ |  |
| `create` | ⚠️ |  |
| `create_from_array` | ⚠️ |  |
| `create_with_capacity` | ⚠️ |  |
| `cummax` | ⚠️ |  |
| `cummin` | ⚠️ |  |
| `cumprod` | ⚠️ |  |
| `cumsum` | ⚠️ |  |
| `diff` | ⚠️ |  |
| `div` | ⚠️ |  |
| `div_scalar` | ⚠️ |  |
| `eq` | ⚠️ |  |
| `ffill` | ⚠️ |  |
| `filter` | ⚠️ |  |
| `free` | ⚠️ |  |
| `ge` | ⚠️ |  |
| `get` | ⚠️ |  |
| `gt` | ⚠️ |  |
| `is_null` | ⚠️ |  |
| `le` | ⚠️ |  |
| `lt` | ⚠️ |  |
| `max` | ⚠️ |  |
| `mean` | ⚠️ |  |
| `min` | ⚠️ |  |
| `mul` | ⚠️ |  |
| `mul_scalar` | ⚠️ |  |
| `ne` | ⚠️ |  |
| `rank` | ⚠️ |  |
| `set` | ⚠️ |  |
| `set_null` | ⚠️ |  |
| `shift` | ⚠️ |  |
| `sort` | ⚠️ |  |
| `sorted_nonnull` | ⚠️ |  |
| `std` | ⚠️ |  |
| `sub` | ⚠️ |  |
| `sub_scalar` | ⚠️ |  |
| `sum` | ⚠️ |  |
| `take` | ⚠️ |  |
| `var` | ⚠️ |  |
| `view` | ⚠️ |  |


### bool — 19 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `all` | ⚠️ |  |
| `and` | ⚠️ |  |
| `any` | ⚠️ |  |
| `append` | ⚠️ |  |
| `append_null` | ⚠️ |  |
| `clone` | ⚠️ |  |
| `count_true` | ⚠️ |  |
| `create` | ⚠️ |  |
| `create_from_array` | ⚠️ |  |
| `create_with_capacity` | ⚠️ |  |
| `free` | ⚠️ |  |
| `get` | ⚠️ |  |
| `is_null` | ⚠️ |  |
| `not` | ⚠️ |  |
| `or` | ⚠️ |  |
| `set` | ⚠️ |  |
| `set_null` | ⚠️ |  |
| `view` | ⚠️ |  |
| `xor` | ⚠️ |  |


### str — 22 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `append` | ⚠️ |  |
| `append_null` | ⚠️ |  |
| `argsort` | ⚠️ |  |
| `clone` | ⚠️ |  |
| `count_nonnull` | ⚠️ |  |
| `create` | ⚠️ |  |
| `create_from_array` | ⚠️ |  |
| `create_with_capacity` | ⚠️ |  |
| `eq` | ⚠️ |  |
| `filter` | ⚠️ |  |
| `free` | ⚠️ |  |
| `ge` | ⚠️ |  |
| `get` | ⚠️ |  |
| `gt` | ⚠️ |  |
| `is_null` | ⚠️ |  |
| `le` | ⚠️ |  |
| `lt` | ⚠️ |  |
| `ne` | ⚠️ |  |
| `set` | ⚠️ |  |
| `set_null` | ⚠️ |  |
| `sort` | ⚠️ |  |
| `take` | ⚠️ |  |


### dt — 40 funções C

| função C | exposta em Lua? | nota |
| :--- | :-: | :-: |
| `add_ms` | ⚠️ |  |
| `append` | ⚠️ |  |
| `append_null` | ⚠️ |  |
| `argsort` | ⚠️ |  |
| `clone` | ⚠️ |  |
| `count_nonnull` | ⚠️ |  |
| `create` | ⚠️ |  |
| `create_from_array` | ⚠️ |  |
| `create_with_capacity` | ⚠️ |  |
| `day` | ⚠️ |  |
| `diff_ms` | ⚠️ |  |
| `eq` | ⚠️ |  |
| `filter` | ⚠️ |  |
| `format` | ⚠️ |  |
| `free` | ⚠️ |  |
| `from_parts` | ⚠️ |  |
| `ge` | ⚠️ |  |
| `get` | ⚠️ |  |
| `gt` | ⚠️ |  |
| `hour` | ⚠️ |  |
| `is_null` | ⚠️ |  |
| `le` | ⚠️ |  |
| `lt` | ⚠️ |  |
| `minute` | ⚠️ |  |
| `month` | ⚠️ |  |
| `ms` | ⚠️ |  |
| `ne` | ⚠️ |  |
| `parse` | ⚠️ |  |
| `quarter` | ⚠️ |  |
| `second` | ⚠️ |  |
| `set` | ⚠️ |  |
| `set_null` | ⚠️ |  |
| `sort` | ⚠️ |  |
| `take` | ⚠️ |  |
| `truncate` | ⚠️ |  |
| `view` | ⚠️ |  |
| `week` | ⚠️ |  |
| `weekday` | ⚠️ |  |
| `year` | ⚠️ |  |
| `yearday` | ⚠️ |  |

## Eixo 4 — Paridade Anel 2 (operações relacionais) por dtype

Heurística conservadora: verifica menção explícita do dtype no corpo da função. ✅ = dtype mencionado explicitamente (provável suporte). ⚠️ = dtype não mencionado (pode ser sem suporte, pode ser polimorfismo via dispatcher genérico — requer revisão manual).


### DataSet — operações estruturais

| operação | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |
| `groupby` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `join` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `concat` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `pivot` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `pivot_table` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `melt` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `stack` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `unstack` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `explode` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `rolling` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `sort_by` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `filter` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### GroupBy — agregações

| operação | f64 | i64 | bool | string | datetime | categorical |
| :--- | :-: | :-: | :-: | :-: | :-: | :-: |

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
| `ne` | Series<bool> | — | ❌ não encontrado |
| `lt` | Series<bool> | — | ❌ não encontrado |
| `le` | Series<bool> | — | ❌ não encontrado |
| `gt` | Series<bool> | — | ❌ não encontrado |
| `ge` | Series<bool> | — | ❌ não encontrado |
| `is_null` | valor escalar (bool) | — | ❌ não encontrado |
| `isna` | valor escalar (bool) | — | ❌ não encontrado |
| `notna` | valor escalar (bool) | — | ❌ não encontrado |
| `unique` | Series | — | ❌ não encontrado |
| `value_counts` | DataSet | — | ❌ não encontrado |
| `describe` | tabela Lua | — | ❌ não encontrado |
| `head` | Series | — | ❌ não encontrado |
| `tail` | Series | — | ❌ não encontrado |
| `take` | Series | — | ❌ não encontrado |
| `filter` | Series | — | ❌ não encontrado |
| `clone` | Series | — | ❌ não encontrado |
| `sort` | Series | — | ❌ não encontrado |
| `argsort` | tabela de índices | — | ❌ não encontrado |
| `to_table` | tabela Lua | — | ❌ não encontrado |
| `cumsum` | Series | — | ❌ não encontrado |
| `cumprod` | Series | — | ❌ não encontrado |
| `cummax` | Series | — | ❌ não encontrado |
| `cummin` | Series | — | ❌ não encontrado |
| `diff` | Series | — | ❌ não encontrado |
| `shift` | Series | — | ❌ não encontrado |
| `map` | Series | — | ❌ não encontrado |
| `CategoricalSeries:value_counts` | DataSet (paridade com Series) | — | ❌ inconsistente com Series |

## Eixo 7 — Tratamento de null consistente

Cada método tem uma política de null esperada (ignore_na, erra, propaga). Verificação heurística sobre o corpo da função. ⚠️ = padrão esperado não foi detectado; pode ser implementação alternativa ou bug.


| método | política esperada | detectado | status |
| :--- | :-: | :-: | :-: |
| `sum` | ignore_na flag | — | ❌ não encontrado |
| `mean` | ignore_na flag | — | ❌ não encontrado |
| `min` | ignore_na flag | — | ❌ não encontrado |
| `max` | ignore_na flag | — | ❌ não encontrado |
| `median` | ignore_na flag | — | ❌ não encontrado |
| `quantile` | ignore_na flag | — | ❌ não encontrado |
| `var` | ignore_na flag | — | ❌ não encontrado |
| `std` | ignore_na flag | — | ❌ não encontrado |
| `prod` | ignore_na flag | — | ❌ não encontrado |
| `skew` | ignore_na flag | — | ❌ não encontrado |
| `kurtosis` | ignore_na flag | — | ❌ não encontrado |
| `mad` | ignore_na flag | — | ❌ não encontrado |
| `sem` | ignore_na flag | — | ❌ não encontrado |
| `mode` | ignore_na flag | — | ❌ não encontrado |
| `sort` | erra com null | — | ❌ não encontrado |
| `argsort` | erra com null | — | ❌ não encontrado |
| `abs` | propaga null | — | ❌ não encontrado |
| `round` | propaga null | — | ❌ não encontrado |
| `clip` | propaga null | — | ❌ não encontrado |
| `cumsum` | propaga null | — | ❌ não encontrado |
| `cumprod` | propaga null | — | ❌ não encontrado |
| `cummin` | propaga null | — | ❌ não encontrado |
| `cummax` | propaga null | — | ❌ não encontrado |
| `diff` | propaga null | — | ❌ não encontrado |
| `shift` | propaga null | — | ❌ não encontrado |
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
| **Tamanho** | `len` | — | — |  |
| **Tamanho** | `size` | — | — |  |
| **Nulidade — predicados** | `is_null` | — | — |  |
| **Nulidade — predicados** | `isna` | — | — |  |
| **Nulidade — predicados** | `notna` | — | — |  |
| **Contagem** | `count_nonnull` | — | — |  |
| **Contagem** | `count_true` | — | — |  |
| **Lógica Kleene** | `land` | — | — |  |
| **Lógica Kleene** | `lor` | — | — |  |
| **Lógica Kleene** | `lxor` | — | — |  |
| **Lógica Kleene** | `lnot` | — | — |  |
| **Seleção posicional** | `head` | — | — |  |
| **Seleção posicional** | `tail` | — | — |  |
| **Seleção posicional** | `take` | — | — |  |
| **Seleção posicional** | `view` | — | — |  |
| **Seleção posicional** | `iloc` | — | — |  |

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

- `series.lua`: 0/0 erros com prefixo `smaug:` (0.0%)
- `dataset.lua`: 0/0 erros com prefixo `smaug:` (0.0%)

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
| `Series.methods` | 0 | 0 | 0 | 0% | ✅ completo |
| `DataSet.methods` | 0 | 0 | 0 | 0% | ✅ completo |
| `GroupBy:*` | 0 | 0 | 0 | 0% | ✅ completo |
| `CategoricalSeries:*` | 0 | 0 | 0 | 0% | ✅ completo |
| `CatProxy:*` (.cat) | 0 | 0 | 0 | 0% | ✅ completo |
| `StrProxy:*` (.str) | 0 | 0 | 0 | 0% | ✅ completo |
| `SeriesDT:*` (.dt) | 0 | 0 | 0 | 0% | ✅ completo |

---

## Resumo executivo


**Contagem global de status no relatório:**

- ✅ paridade: 161
- ⚪ exceção registrada: 3
- ⚠️ suspeita (revisar): 199
- ❌ inconsistência clara: 62


## Como usar este relatório

1. Procure por ⚠️ — cada um é um candidato a gap real ou exceção a registrar.
2. Se for decisão consciente, adicione em `scripts/parity/exceptions.txt`.
3. Se for gap real, registre em `Roadmap.md` ou corrija e rode novamente.
4. Procure por ❌ — sempre gap real, exige ação.