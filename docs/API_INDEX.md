# API_INDEX — catálogo do que já existe

**Propósito:** inventário de tudo que está implementado. Antes de criar
qualquer função/método novo, consulte aqui se já não existe. É a defesa contra
reimplementação e deriva.

**Como manter:** atualizar a cada função/método adicionado ou removido.

> Convenção: `<t>` = `f64` ou `i64`. Índices em C são 0-based; no Lua, 1-based.

> **Contrato de status (`smaug_types.h`):** `smaug_status_t` =
> `SMG_OK (0)` / `SMG_NULL_VALUE` / `SMG_ERR_OOB` / `SMG_ERR_ARGUMENT` /
> `SMG_ERR_NOMEM`. O engine valida e comunica — não confia que o caller validou.

---

## Camada C — backend (`include/*.h`, `src/*.c`)

### Lifecycle e acesso (`smaug_core.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_<t>_create(size)` | cria série de `size` elementos, todos NULL |
| `smaug_<t>_create_with_capacity(size, cap)` | cria com capacidade pré-alocada |
| `smaug_<t>_create_from_array(arr, len)` | cria a partir de array C, tudo válido |
| `smaug_<t>_free(s)` | libera a série (NULL-safe) |
| `smaug_<t>_clone(s)` | cópia profunda independente |
| `smaug_<t>_view(s, start, len)` | view zero-copy; COW na primeira mutação |
| `smaug_<t>_get(s, idx, status)` | lê valor + `smaug_status_t*` anulável |
| `smaug_<t>_set(s, idx, val)` | grava valor → `smaug_status_t`; COW detach se view |
| `smaug_<t>_set_null(s, idx)` | marca posição como NULL → `smaug_status_t` |
| `smaug_<t>_is_null(s, idx)` | testa se posição é NULL |
| `smaug_<t>_append(s, val)` | adiciona ao fim; COW detach se view |
| `smaug_<t>_append_null(s)` | adiciona NULL ao fim |
| `smaug_free(ptr)` | libera buffers crus (compare/argsort/bool) — usar SEMPRE esta |

### Aritmética (`smaug_numeric.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_<t>_add/sub/mul/div(a, b)` | aritmética série×série (propaga NA) |
| `smaug_<t>_add/sub/mul/div_scalar(a, k)` | aritmética série×escalar |

`div/0 → null` em f64 e i64. `NaN` só existe como valor presente em f64.

### Reduções (`smaug_numeric.h`)

| Função | Retorno |
|--------|---------|
| `smaug_<t>_sum(s, ignore_na)` | f64→double, i64→int64 |
| `smaug_<t>_mean(s, ignore_na)` | double |
| `smaug_<t>_min/max(s, ignore_na)` | f64→double, i64→int64 |
| `smaug_<t>_var/std(s, ignore_na)` | double, populacional (÷N) |
| `smaug_<t>_count_nonnull(s)` | size_t |

### Comparações e ordenação (`smaug_numeric.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_<t>_gt/lt/eq/ge/le/ne(s, k, &out_mask)` | → bool array (uint8_t*); liberar c/ `smaug_free` |
| `smaug_<t>_argsort(s, asc)` | → size_t* (permutação); NULL se há nulos |
| `smaug_<t>_sort(s, asc)` | → nova série ordenada; NULL se há nulos |
| `smaug_<t>_take(s, idx, len)` | → nova série com os índices dados |
| `smaug_<t>_filter(s, mask)` | → nova série onde mask é true |

### Booleano / Kleene (`smaug_bool.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_bool_and/or/xor(a, am, b, bm, n, &out)` | lógica de 3 valores |
| `smaug_bool_not(a, am, n, &out)` | negação Kleene |
| `smaug_bool_count_true(a, am, n)` | conta trues (NA ignorado) |
| `smaug_bool_any/all(a, am, n)` | agregações (NA ignorado) |

### String (`smaug_string.h`)

Representação offset-based (buffer de bytes + array de offsets). String vazia `""` ≠ NULL.

| Função | O que faz |
|--------|-----------|
| `smaug_str_create(size)` | cria série de `size` strings, todas NULL |
| `smaug_str_create_with_capacity(size, buf_cap)` | cria com buffer pré-alocado |
| `smaug_str_create_from_array(arr, len)` | cria de `char*` array |
| `smaug_str_free(s)` | libera (NULL-safe) |
| `smaug_str_clone(s)` | cópia profunda independente |
| `smaug_str_get(s, idx, &out_len)` | → ponteiro p/ bytes + comprimento (sem `\0`) |
| `smaug_str_set(s, idx, str, len)` | grava (realoca buffer via memmove) |
| `smaug_str_set_null(s, idx)` / `smaug_str_is_null(s, idx)` | nulos |
| `smaug_str_append(s, str, len)` / `smaug_str_append_null(s)` | adiciona ao fim |
| `smaug_str_count_nonnull(s)` | size_t |
| `smaug_str_eq/lt/gt(s, target, target_len, &out_mask)` | → bool array; lexicográfico por bytes |
| `smaug_str_filter(s, mask)` | → nova série onde mask é true |
| `smaug_str_take(s, idx, len)` | → nova série com os índices dados |
| `smaug_str_argsort(s, asc)` | → size_t* (permutação); NULL se há nulos |
| `smaug_str_sort(s, asc)` | → nova série ordenada |

### I/O — Anel 3 (`smaug_io.h`)

Fronteira `smaug_table_t`: toda função de leitura produz `smaug_table_t*`
(checar `->error` antes de usar). Liberar com `smaug_table_free`.

| Função | O que faz |
|--------|-----------|
| `smaug_table_free(t)` | libera tabela e todos os recursos (NULL-safe) |
| `smaug_csv_default_opts()` | opções padrão: sep=`,` header=1 quote=`"` |
| `smaug_read_csv(path, opts)` | lê CSV de arquivo → `smaug_table_t*` |
| `smaug_read_csv_mem(buf, len, opts)` | lê CSV de buffer em memória |
| `smaug_write_csv(path, t, opts)` | escreve CSV em arquivo (0=ok, -1=erro) |
| `smaug_write_csv_mem(t, opts, &len)` | escreve CSV em buffer alocado; liberar c/ `smaug_free` |
| `smaug_read_json(path)` | lê JSON de arquivo (array de records) |
| `smaug_read_json_mem(buf, len)` | lê JSON de buffer em memória |
| `smaug_write_json(path, t, opts)` | escreve JSON em arquivo |
| `smaug_write_json_mem(t, opts, &len)` | escreve JSON em buffer alocado |

### Tipos (`smaug_types.h`)

`smaug_mask_t`, `smaug_metadata_t`, `smaug_series_f64_t`, `smaug_series_i64_t`,
`smaug_series_bool_t`, `smaug_series_str_t`, `smaug_column_t`, `smaug_table_t`.

---

## Camada Lua — frontend (`lua/smaug/`)

### `Series` (`core/series.lua`)

**Factories:** `Series.new(dtype, size, name)`, `Series.from_table(arr, dtype, name)`,
`Series.full(n, val)`. `Series.NA` (sentinela de nulo em tabelas).

> **NaN ≠ null:** `nil`/`Series.NA` → null (ausente, bitmask). `NaN` → valor
> presente indefinido, NÃO null. `ignore_na` pula null, não NaN.
> `sort`/`argsort` recusam NaN e null. Comparação com NaN → false (máscara válida).

| Método | O que faz |
|--------|-----------|
| `:get(i)` / `:set(i, v)` | acesso 1-based; nil↔NA |
| `:is_null(i)` / `:set_null(i)` | nulos |
| `:append(v)` | adiciona ao fim (chainable) |
| `:len()` / `:size()` | tamanho |
| `:sum/mean/min/max/var/std([ignore_na])` | reduções (default ignore_na=true) |
| `:count_nonnull()` | nº de não-nulos |
| `:clone()` | cópia independente |
| `:sort(asc)` / `:argsort(asc)` | ordenar / permutação |
| `:view(start, len)` | view zero-copy COW-gravável |
| `:take(idx)` / `:head(n)` / `:tail(n)` | seleção → nova Series |
| `:dropna()` | → nova Series sem NULLs |
| `:astype(dtype)` | conversão tolerante por elemento (inconversíveis → null) |
| `:fillna(value)` | nova Series com NULLs→value; NaN intacto |
| `:to_table([na])` | → tabela Lua |
| `:describe()` | resumo estatístico |
| `:gt/lt/eq/ge/le/ne(k)` | comparação → `Series<bool>` |
| `:filter(mask)` | `Series<bool>` como máscara → nova Series filtrada |
| `:map(fn, [dtype])` | transforma elemento a elemento |

**Distintos:**

| Método | O que faz |
|--------|-----------|
| `:unique()` | valores distintos em ordem de 1ª aparição |
| `:nunique()` | contagem de distintos não-nulos |
| `:value_counts()` | DataSet `{value, count}` ordenado por freq. desc |

**Elementares:**

| Método | O que faz |
|--------|-----------|
| `:abs()` | valor absoluto (nulos propagam) |
| `:round([n])` | arredonda para n casas decimais |
| `:clip([lo], [hi])` | limita ao intervalo [lo, hi] |

**Janela temporal:**

| Método | O que faz |
|--------|-----------|
| `:cumsum()` | soma cumulativa (nulos propagam) |
| `:cumprod()` | produto cumulativo (nulos propagam) |
| `:diff([periods])` | diferença entre elemento i e i-periods |
| `:shift([periods])` | desloca valores |
| `:rolling(w):sum/mean/min/max()` | agregação em janela de tamanho w |

**Operadores:** `+ - * /` (série×série e série×escalar), `serie[i]`.
**Operadores bool** (só em `Series<bool>`): `*`=and, `+`=or, `-`=xor.

### `.str` — proxy de operações sobre Series string

**Tier A:**

| Método | O que faz |
|--------|-----------|
| `.str:len()` | comprimento em bytes → `Series<int64>` |
| `.str:lower()` / `.str:upper()` | caixa (ASCII) |
| `.str:strip()` | remove espaços |
| `.str:replace(pat, rep)` | substituição literal |
| `.str:contains(sub)` / `.str:startswith(p)` / `.str:endswith(s)` | → `Series<bool>` |

**Tier B:**

| Método | O que faz |
|--------|-----------|
| `.str:find(sub)` | índice 1-based da 1ª ocorrência (0 se ausente) |
| `.str:slice(start, [stop])` | substring por índices |
| `.str:pad(width, [side], [fillchar])` | preenche até `width` chars |
| `.str:zfill(width)` | pad com '0' à esquerda |
| `.str:rep(n, [sep])` | repete n vezes |
| `.str:cat([sep])` | concatena todos os não-nulos → string Lua |
| `.str:split(sep, [max])` | divide pelo separador → tabela de Series |

### Métodos exclusivos de `Series<bool>`

| Método | O que faz |
|--------|-----------|
| `:count_true()` / `:any()` / `:all()` | agregações (NA ignorado) |
| `:land(b)` / `:lor(b)` / `:lxor(b)` / `:lnot()` | lógica Kleene |
| `:describe()` | `{count, nulls, count_true, count_false}` |

### `DataSet` (`core/dataset.lua`)

**Construção:** `DataSet.new(name)`, `smaug.DataSet({{nome, dados, dtype?}, ...})`.

| Método | O que faz |
|--------|-----------|
| `:add_column(nome, series)` | adiciona (valida comprimento e nome único) |
| `:drop_column(nome)` / `:rename_column(old, new)` | CRUD de colunas |
| `:column(nome)` / `:col(nome)` / `df[nome]` | acessa coluna |
| `:has_column(nome)` / `:columns()` | metadados |
| `:ncols()` / `:nrows()` / `:len()` | dimensões |
| `:dtypes()` / `:row(i, [na])` | tipos por coluna / linha como tabela |
| `:filter(mask)` | `Series<bool>` → novo DataSet; `df[mask]` é açúcar |
| `:fillna(value)` / `:fillna({col=value})` | preenche NULLs → novo DataSet |
| `:sort_by(col, asc)` | ordena todas as colunas pela chave |
| `:head(n)` / `:tail(n)` / `:iloc(start, stop)` / `:take(idx)` | fatias |
| `:sample(n, [seed])` | amostra aleatória |
| `:select(nomes)` | subconjunto/reordenação de colunas |
| `:dropna([subset])` | remove linhas com NULL |
| `:update_column(nome, series)` | substitui coluna existente |
| `:assign(nome, fn_ou_series)` | adiciona/substitui coluna calculada |
| `:nunique()` | `{coluna → nº distintos não-nulos}` |
| `:describe()` / `:to_table([na])` | inspeção |

**Operações relacionais (Anel 2):**

| Método | O que faz |
|--------|-----------|
| `:groupby(key):sum/mean/min/max/count(col)` | agrupamento; chave simples ou composta |
| `:join(other, on, [how], [suffixes])` | inner/left/right/outer; chave simples ou composta |
| `smaug.concat({ds1, ds2, ...})` | empilha DataSets verticalmente |
| `:pivot(index, columns, values)` | long → wide |
| `:melt(id_vars, [value_vars], ...)` | wide → long |
| `:rolling(w):sum/mean/min/max(col)` | janela deslizante por coluna |

**I/O (Anel 3):**

| Método | O que faz |
|--------|-----------|
| `:to_csv(path, [opts])` | escreve CSV em arquivo |
| `:to_csv_mem([opts])` | → string Lua com o CSV |
| `:to_json(path, [opts])` | escreve JSON em arquivo |
| `:to_json_mem([opts])` | → string Lua com o JSON |

### Entry point (`init.lua`)

```lua
local smaug = require("smaug")

-- I/O
smaug.read_csv(path, [opts])       -- opts: {sep, header, na_values, quote}
smaug.read_csv_mem(buf, [opts])
smaug.read_json(path)
smaug.read_json_mem(buf)

-- construção
smaug.DataSet({{nome, dados, dtype?}, ...})
smaug.Series                        -- classe
smaug.NA                            -- sentinela de nulo
smaug.concat({ds1, ds2, ...})
smaug.join(a, b, on, [how], [suffixes])
```

---

## Não existe ainda

`median`/`quantile`, `ffill`/`bfill`, `datetime`, `categorical`,
`groupby.std/var/median`, `rolling.std/var/count`, `argmin`/`argmax`,
`where`/`mask`, `cummin`/`cummax`, funções matemáticas vetorizadas (`sin`/`cos`/`exp`/`log`/`sqrt`),
NDJSON, SQLite, Excel, Parquet, lazy evaluation.

Ver `Roadmap.md` (seção "Próximas versões") para quando cada um entra.
