# API_INDEX — catálogo do que já existe

**Propósito:** inventário de tudo que já está implementado. Antes de criar
qualquer função/método novo, consulte aqui se já não existe. É a defesa contra
reimplementação e deriva ("espaguete").

**Como manter:** atualizar a cada função/método adicionado ou removido. Gerado a
partir do código real (não de memória). Última sincronização: commit `67d8da2`
(headers separados + `libsmaug` + `.gitattributes`).

> Convenção: `f64`/`i64` = as duas variantes numéricas. Onde aparece `<t>`, leia
> as duas (`smaug_f64_*` e `smaug_i64_*`). Índices em C são 0-based; no Lua,
> 1-based.

---

## Camada C — backend (`include/*.h`, `src/*.c`)

### Lifecycle e acesso (`smaug_core.h`)
| Função | O que faz |
|--------|-----------|
| `smaug_<t>_create(size)` | cria série de `size` elementos, todos NULL |
| `smaug_<t>_create_with_capacity(size, cap)` | cria com capacidade pré-alocada |
| `smaug_<t>_create_from_array(arr, len)` | cria a partir de array C, tudo válido |
| `smaug_<t>_free(s)` | libera a série (NULL-safe; respeita external_alloc) |
| `smaug_<t>_clone(s)` | cópia profunda independente |
| `smaug_<t>_view(s, start, len)` | view zero-copy (external_alloc=true) |
| `smaug_<t>_get(s, idx)` | lê valor (f64: NAN se nulo; i64: cheque is_null antes) |
| `smaug_<t>_set(s, idx, val)` | grava valor |
| `smaug_<t>_set_null(s, idx)` | marca posição como NULL |
| `smaug_<t>_is_null(s, idx)` | testa se posição é NULL |
| `smaug_<t>_append(s, val)` | adiciona valor ao fim (0=ok, -1=erro) |
| `smaug_<t>_append_null(s)` | adiciona NULL ao fim |
| `smaug_free(ptr)` | libera buffers crus (compare/argsort/bool); use SEMPRE esta |

### Aritmética (`smaug_numeric.h`)
| Função | O que faz |
|--------|-----------|
| `smaug_<t>_add/sub/mul/div(a, b)` | aritmética série×série (propaga NA) |
| `smaug_<t>_add/sub/mul/div_scalar(a, k)` | aritmética série×escalar |

Notas: f64 `div`/0 segue IEEE (±Inf/NaN); i64 `div`/0 → NULL.

### Reduções (`smaug_numeric.h`)
| Função | Retorno |
|--------|---------|
| `smaug_<t>_sum(s, ignore_na)` | f64→double, i64→int64 (sentinela INT64_MIN) |
| `smaug_<t>_mean(s, ignore_na)` | double (ambos) |
| `smaug_<t>_min/max(s, ignore_na)` | f64→double, i64→int64 (sentinela INT64_MIN) |
| `smaug_<t>_var/std(s, ignore_na)` | double, populacional (÷N) |
| `smaug_<t>_count_nonnull(s)` | size_t |

### Comparações e ordenação (`smaug_numeric.h`)
| Função | O que faz |
|--------|-----------|
| `smaug_<t>_gt/lt/eq(s, k, &out_mask)` | → bool array (uint8_t*); caller libera c/ `smaug_free` |
| `smaug_<t>_argsort(s, asc)` | → size_t* (permutação); NULL se há nulos; libera c/ `smaug_free` |
| `smaug_<t>_sort(s, asc)` | → nova série ordenada; NULL se há nulos |
| `smaug_<t>_take(s, idx, len)` | → nova série com os índices dados |
| `smaug_<t>_filter(s, mask)` | → nova série onde mask é true |

### Booleano / Kleene (`smaug_bool.h`)
| Função | O que faz |
|--------|-----------|
| `smaug_bool_and/or/xor(a, am, b, bm, n, &out)` | lógica de 3 valores; caller libera |
| `smaug_bool_not(a, am, n, &out)` | negação Kleene |
| `smaug_bool_count_true(a, am, n)` | conta trues (NA ignorado) |
| `smaug_bool_any/all(a, am, n)` | agregações (NA ignorado; all de vazio=true) |

### Tipos (`smaug_types.h`)
`smaug_mask_t` (uint8: 0xFF=válido, 0x00=NA), `smaug_metadata_t`,
`smaug_series_f64_t`, `smaug_series_i64_t`, `smaug_hash_table_t` (opaque, futuro).

---

## Camada Lua — frontend (`lua/smaug/`)

### `Series` (`core/series.lua`) — dtypes: float64, int64
**Factories:** `Series.new(dtype, size, name)`, `Series.float64(size, name)`,
`Series.int64(size, name)`, `Series.from_table(arr, dtype, name)`.
`Series.NA` (sentinela de nulo em tabelas).

| Método | O que faz |
|--------|-----------|
| `:get(i)` / `:set(i, v)` | acesso 1-based; nil↔NA |
| `:is_null(i)` / `:set_null(i)` | nulos |
| `:append(v)` | adiciona ao fim (chainable) |
| `:len()` / `:size()` | tamanho (use isto, não `#`) |
| `:sum/mean/min/max/var/std([ignore_na])` | reduções (default ignore_na=true) |
| `:count_nonnull()` | nº de não-nulos |
| `:clone()` | cópia independente |
| `:sort(asc)` / `:argsort(asc)` | ordenar / permutação de ordenação |
| `:view(start, len)` | view zero-copy segura (read-only, segura `_parent`) |
| `:take(idx)` / `:head(n)` / `:tail(n)` | seleção de linhas → nova Series |
| `:astype(dtype)` | conversão de tipo |
| `:to_table([na])` | → tabela Lua |
| `:describe()` | resumo estatístico (count, nulls, mean, std, min, quartis, max) |
| `:gt(k)` / `:lt(k)` / `:eq(k)` | comparação → BoolSeries |
| `:filter(boolseries)` | → nova Series filtrada |
**Operadores:** `+ - * /` (série×série e série×escalar; `+`/`*` comutam c/ escalar à esquerda), `tostring`, `serie[i]`.

### `BoolSeries` (`core/boolseries.lua`)
| Método | O que faz |
|--------|-----------|
| `:get(i)` | true/false/nil(NA), 1-based |
| `:is_null(i)` / `:len()` / `:to_table([na])` | acesso |
| `:count_true()` / `:any()` / `:all()` | agregações (NA ignorado) |
| `:land/:lor/:lxor(other)` / `:lnot()` | lógica Kleene |
**Operadores:** `*`=and, `+`=or, `-`=xor, `tostring`, `bs[i]`.

### `DataSet` (`core/dataset.lua`) — tabela 2D de Series alinhadas
**Construção:** `DataSet.new(name)`, `DataSet.from_columns({{nome, dados, dtype?}, ...})`.

| Método | O que faz |
|--------|-----------|
| `:add_column(nome, series)` | adiciona (valida comprimento e nome único) |
| `:drop_column(nome)` / `:rename_column(old, new)` | CRUD de colunas |
| `:column(nome)` / `:col(nome)` / `df[nome]` | acessa coluna (Series) |
| `:has_column(nome)` / `:columns()` | metadados |
| `:ncols()` / `:nrows()` / `:len()` | dimensões |
| `:dtypes()` / `:row(i, [na])` | tipos por coluna / linha como tabela |
| `:filter(boolseries)` | linhas onde mask é true → novo DataSet |
| `:sort_by(col, asc)` | ordena todas as colunas pela chave → novo DataSet |
| `:head(n)` / `:tail(n)` / `:iloc(start, stop)` / `:take(idx)` | fatias → novo DataSet |
| `:sample(n, [seed])` | amostra aleatória → novo DataSet |
| `:select(nomes)` | subconjunto/reordenação de colunas → novo DataSet |
| `:describe()` / `:to_table([na])` | inspeção |
**Operadores:** `tostring` (tabular), `df[coluna]`.

### Entry point (`init.lua`)
`require("smaug")` expõe: `.Series`, `.BoolSeries`, `.DataSet`, e açúcares
`.float64`, `.int64`, `.from_table`, `.NA`, `.dataset` (= `DataSet.from_columns`).

---

## NÃO existe ainda (não procure — consulte o Roadmap para a fase)

`fillna`, `dropna`, `median`/`quantile` nativos, `abs`/`round`/`clip`,
`cumsum`/`cumprod`, `diff`/`shift`, `unique`/`value_counts`, broadcasting,
`apply`/`map`, tipo `string`, `datetime`, `categorical`, I/O (CSV/JSON/XML/SQL),
GroupBy/joins. Ver `Roadmap.md` para quando cada um entra.
