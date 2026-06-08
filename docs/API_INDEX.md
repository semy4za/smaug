# API_INDEX — catálogo do que já existe

**Propósito:** inventário de tudo que já está implementado. Antes de criar
qualquer função/método novo, consulte aqui se já não existe. É a defesa contra
reimplementação e deriva ("espaguete").

**Como manter:** atualizar a cada função/método adicionado ou removido. Gerado a
partir do código real (não de memória).

> Convenção: `f64`/`i64` = as duas variantes numéricas. Onde aparece `<t>`, leia
> as duas (`smaug_f64_*` e `smaug_i64_*`). Índices em C são 0-based; no Lua,
> 1-based.

> **Contrato de status (`smaug_types.h`):** `smaug_status_t` =
> `SMG_OK (0)` / `SMG_NULL_VALUE` / `SMG_ERR_OOB` / `SMG_ERR_ARGUMENT` /
> `SMG_ERR_NOMEM` (falha de alocação no COW detach).
> Princípio: o engine valida e comunica — não confia que o caller validou. As
> mutações (`set`/`set_null`) devolvem este código; em erro não há escrita.
> `get` devolve o valor + `smaug_status_t*` anulável (Shape 1), distinguindo
> `SMG_OK` / `SMG_NULL_VALUE` / `SMG_ERR_OOB` / `SMG_ERR_ARGUMENT` — sem colisão
> com NaN/valor; sentinela definida (NAN/0) se `status == NULL`.

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
| `smaug_<t>_view(s, start, len)` | view zero-copy; COW na primeira mutação (ver `docs/COW.md`) |
| `smaug_<t>_get(s, idx, status)` | lê valor + `smaug_status_t*` anulável (OK/NULL_VALUE/OOB/ARGUMENT); sentinela definida em erro (f64: NAN, i64: 0) |
| `smaug_<t>_set(s, idx, val)` | grava valor → `smaug_status_t` (OK/OOB/ARGUMENT/NOMEM); COW detach se view; em erro não escreve |
| `smaug_<t>_set_null(s, idx)` | marca posição como NULL → `smaug_status_t` (idem) |
| `smaug_<t>_is_null(s, idx)` | testa se posição é NULL |
| `smaug_<t>_append(s, val)` | adiciona valor ao fim; COW detach se view (0=ok, -1=erro) |
| `smaug_<t>_append_null(s)` | adiciona NULL ao fim; COW detach se view |
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

### String (`smaug_string.h`)
Representação offset-based (buffer de bytes concatenados + array de offsets).
Trata bytes crus (UTF-8 = dívida futura). String vazia `""` é distinta de NULL.
| Função | O que faz |
|--------|-----------|
| `smaug_str_create(size)` | cria série de `size` strings, todas NULL |
| `smaug_str_create_with_capacity(size, buf_cap)` | cria com buffer pré-alocado |
| `smaug_str_create_from_array(arr, len)` | cria de `char*` array (NULL no array → NULL) |
| `smaug_str_free(s)` | libera (NULL-safe; respeita external_alloc) |
| `smaug_str_clone(s)` | cópia profunda independente |
| `smaug_str_get(s, idx, &out_len)` | → ponteiro p/ bytes + comprimento (NÃO terminado em \0) |
| `smaug_str_set(s, idx, str, len)` | grava (realoca o buffer via memmove; 0=ok, -1=erro) |
| `smaug_str_set_null(s, idx)` / `smaug_str_is_null(s, idx)` | nulos (`set_null` → `smaug_status_t`) |
| `smaug_str_append(s, str, len)` / `smaug_str_append_null(s)` | adiciona ao fim (0=ok, -1=erro) |
| `smaug_str_count_nonnull(s)` | size_t |
| `smaug_str_eq/lt/gt(s, target, target_len, &out_mask)` | → bool array (uint8_t*); lexicográfico por bytes; caller libera c/ `smaug_free` |
| `smaug_str_filter(s, mask)` | → nova série onde mask é true (preserva NULL) |
| `smaug_str_take(s, idx, len)` | → nova série com os índices dados (preserva NULL) |
| `smaug_str_argsort(s, asc)` | → size_t* (permutação); NULL se há nulos; libera c/ `smaug_free` |
| `smaug_str_sort(s, asc)` | → nova série ordenada (= argsort+take); NULL se há nulos |

### Tipos (`smaug_types.h`)
`smaug_mask_t` (uint8: 0xFF=válido, 0x00=NA), `smaug_metadata_t`,
`smaug_series_f64_t`, `smaug_series_i64_t`, `smaug_series_str_t`,
`smaug_hash_table_t` (opaque, futuro).

---

## Camada Lua — frontend (`lua/smaug/`)

### `Series` (`core/series.lua`) — dtypes: float64, int64, string
**Factories:** `Series.new(dtype, size, name)`, `Series.float64(size, name)`,
`Series.int64(size, name)`, `Series.string(size, name)`,
`Series.from_table(arr, dtype, name)`. `Series.NA` (sentinela de nulo em tabelas).

> **String:** dtype de primeira classe. Aceita só string Lua (numéricos recusam
> string e vice-versa — sem coerção). Comparações/sort são lexicográficos por
> bytes (não Unicode-aware). String vazia `""` ≠ NULL.

> **NaN ≠ null (implementado).** `nil` e `Series.NA` → null (ausente, bitmask).
> `NaN` (ex.: `0/0` ou `0/0` de operação) → valor **presente** porém indefinido,
> NÃO null: `is_null`→false, `count_nonnull` conta. `ignore_na` pula null, não
> NaN (NaN contamina reduções → resultado nil). `sort`/`argsort` **recusam** NaN
> (além de null). Comparação com NaN → false (máscara válida, não NA).

| Método | O que faz |
|--------|-----------|
| `:get(i)` / `:set(i, v)` | acesso 1-based; nil↔NA |
| `:is_null(i)` / `:set_null(i)` | nulos || `:append(v)` | adiciona ao fim (chainable) |
| `:len()` / `:size()` | tamanho (use isto, não `#`) |
| `:sum/mean/min/max/var/std([ignore_na])` | reduções (default ignore_na=true) |
| `:count_nonnull()` | nº de não-nulos |
| `:clone()` | cópia independente |
| `:sort(asc)` / `:argsort(asc)` | ordenar / permutação de ordenação |
| `:view(start, len)` | view zero-copy COW-gravável (detach automático na primeira mutação) |
| `:take(idx)` / `:head(n)` / `:tail(n)` | seleção de linhas → nova Series |
| `:dropna()` | → nova Series sem NULLs (qualquer dtype; habilita sort em série c/ nulos) |
| `:astype(dtype)` | conversão de tipo |
| `:fillna(value)` | nova Series com NULLs→value; sem coerção; NaN intacto; sem arg=erro |
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
| `:fillna(value)` / `:fillna({col=value})` | preenche NULLs (todas as colunas, ou por coluna) → novo DataSet |
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

`median`/`quantile` nativos, `abs`/`round`/`clip`, `cumsum`/`cumprod`,
`diff`/`shift`, `unique`/`value_counts`, broadcasting, `apply`/`map`,
`.str` (lower/upper/strip/contains/...), `DataSet:dropna`, `datetime`,
`categorical`, I/O (CSV/JSON/XML/SQL), GroupBy/joins. Ver `Roadmap.md` para
quando cada um entra.
