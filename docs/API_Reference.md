# Referência da API — Núcleo C

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

Referência do backend C. As famílias f64 e i64 têm diferenças de assinatura,
precisão e falha; não deduzir uma assinatura pela outra. As tabelas descrevem
a API existente, enquanto a seção de evolução datetime distingue assinaturas
aprovadas ainda por implementar. Verificação e pendências: [roadmap](Roadmap.md).

<a id="section-mapa-de-headers-qual-include-usar"></a>

## Mapa de headers (qual `#include` usar)

Os headers são separados por responsabilidade (inspirado no NumPy, onde os tipos
ficam em `ndarraytypes.h` separados das funções). Inclua o mais específico que
cobre o que você usa, ou o umbrella `smaug.h` para tudo:

| Header | Conteúdo | Inclui |
|--------|----------|--------|
| `smaug_types.h` | Tipos base: `smaug_mask_t`, `smaug_metadata_t`, structs `series_f64`/`series_i64`. **Zero funções.** | — |
| `smaug_core.h` | Lifecycle (create/free/clone/view), get/set, append, `smaug_free`. | `smaug_types.h` |
| `smaug_numeric.h` | Aritmética, reduções, comparações, ordenação, take/filter/count (f64+i64). | `smaug_core.h` |
| `smaug_bool.h` | Operações booleanas Kleene. | `smaug_types.h` |
| `smaug_string.h` | Tipo `string`: lifecycle, acesso, comparações, filter/take/sort. | `smaug_types.h` |
| `smaug_datetime.h` | Tipo `datetime`: epoch ms, parser, calendário e operações temporais. | `smaug_types.h` |
| `smaug_ops_window.h` | Janelas, rolling e operações de ordenação múltipla. | `smaug_core.h`, `smaug_string.h` |
| `smaug_io.h` | Tabelas intermediárias e leitura/escrita CSV/JSON. | `smaug_types.h` |
| `smaug_astype.h` | Conversões entre dtypes. | `smaug_core.h` |
| `smaug_convert.h` | Parsing/formatação numérica e textual de baixo nível. | headers C padrão |
| `smaug.h` | **Umbrella** — inclui os de operação. | todos acima |

> Use `smaug.h` ou o header específico. A biblioteca compilada
> permanece `libsmaug.so`/`smaug.dll` (nome do binário).

---

<a id="section-tipos"></a>

## Tipos

<a id="section--smaug-mask-t"></a>

### `smaug_mask_t`

```c
typedef uint8_t smaug_mask_t;   /* 0xFF = válido, 0x00 = nulo (NA) */
```

Bitmask de 1 byte por elemento. Array paralelo aos dados.

<a id="section--smaug-metadata-t"></a>

### `smaug_metadata_t`

```c
typedef struct {
    const char *name;        /* nome da coluna, ex: "salario" */
    const char *dtype;       /* "float64", "int64", "bool", "string", "datetime" */
    bool is_view;            /* true se é uma view (não dona da memória) */
    bool external_alloc;     /* true se não deve liberar data/null_mask */
} smaug_metadata_t;
```

`name` e `dtype` são apenas identificadores — não há validação interna que os
use. Mantê-los consistentes é responsabilidade do caller.

<a id="section--smaug-series-f64-t-smaug-series-i64-t"></a>

### `smaug_series_f64_t` / `smaug_series_i64_t`

```c
typedef struct {
    double       *data;        /* (int64_t* na variante i64) */
    smaug_mask_t *null_mask;   /* paralelo a data */
    size_t        size;        /* elementos preenchidos */
    size_t        capacity;    /* elementos alocados */
    smaug_metadata_t meta;
} smaug_series_f64_t;
```

Invariantes: `size <= capacity` sempre; `data` e `null_mask` têm o mesmo
tamanho (`capacity`); posições em `[size, capacity)` são lixo não-inicializado.
`smaug_series_bool_t`, `smaug_series_str_t` e `smaug_series_dt_t` vivem no
mesmo header e têm contratos de lifecycle próprios descritos nas seções abaixo.

---

<a id="section-lifecycle"></a>

## Lifecycle

| Função | Retorno | Notas |
|--------|---------|-------|
| `create(size)` | série / NULL | `size == capacity`; **todos os elementos nascem NULL** |
| `create_with_capacity(size, capacity)` | série / NULL | NULL se `size > capacity`; pré-aloca para append |
| `create_from_array(array, len)` | série / NULL | copia o array; todos marcados **válidos** |
| `free(s)` | void | idempotente (`NULL` é seguro); respeita `external_alloc` |
| `clone(s)` | série / NULL | deep copy independente |
| `view(s, start, len)` | série / NULL | slice **zero-copy**; NULL se `start+len > size` |

Pontos críticos:

- **`create` inicializa tudo como NULL.** Uma série recém-criada com
  `create(10)` tem os 10 elementos nulos. Eles só se tornam válidos via `set` ou
  `append`. Popular uma série do zero exige um loop de `set`.
- **`free` respeita `external_alloc`.** Se `true` (caso das views), não libera
  `data`/`null_mask`, apenas o struct. Sempre libera o struct em si.
- **Views ainda compartilhadas dependem dos buffers do pai.** Liberar o pai
  antes invalida a view. Mutar a view dispara detach e preserva o pai; após
  detach ela é independente. Realocação do pai exige cuidados próprios:
  consulte [COW](COW.md), sem presumir estabilidade de ponteiros.

```c
/* Padrão de uso */
smaug_series_f64_t *s = smaug_f64_create(100);
if (!s) { /* tratar OOM */ }
for (size_t i = 0; i < 100; i++) smaug_f64_set(s, i, valores[i]);
/* ... usar ... */
smaug_f64_free(s);
s = NULL;   /* boa prática contra use-after-free */
```

---

<a id="section-getters-setters"></a>

## Getters / Setters

| Função | Retorno | Comportamento |
|--------|---------|---------------|
| `get(s, idx, status*)` | `double`/`int64_t` | valor se válido; sentinela + `*status` em erro/null |
| `set(s, idx, val)` | `smaug_status_t` | grava `val`; COW detach se view; `SMG_ERR_NOMEM` se detach falhar |
| `set_null(s, idx)` | `smaug_status_t` | marca nulo; COW detach se view; mesmas garantias |
| `is_null(s, idx)` | `bool` | `true` se nulo ou fora dos limites |

**`get` — Shape 1:** o terceiro argumento `status*` é anulável. Se `NULL`, o
retorno é a sentinela segura sem comunicar o motivo. Se não-NULL, recebe o código
de status. Sentinela: `NAN` (f64) ou `0` (i64).

| caso | retorno | `*status` |
|---|---|---|
| sucesso | valor real | `SMG_OK` |
| elemento NULL | sentinela | `SMG_NULL_VALUE` |
| `idx >= size` | sentinela | `SMG_ERR_OOB` |
| `s == NULL` | sentinela | `SMG_ERR_ARGUMENT` |

**`set` / `set_null` — status de retorno:**

| retorno | condição |
|---|---|
| `SMG_OK` | escrita aplicada |
| `SMG_ERR_OOB` | `idx >= size` — checado antes de qualquer escrita |
| `SMG_ERR_ARGUMENT` | `s == NULL` |
| `SMG_ERR_NOMEM` | view: detach COW falhou por OOM (série intacta) |

`set` sempre marca como válido — mesmo com `val == NAN`. Para marcar nulo, use
`set_null`. *NaN não é o mesmo que NA*: um `set(NAN)` produz um valor válido cujo
conteúdo é NaN, enquanto `set_null` marca a posição como ausente.

---

<a id="section-append-dinamico"></a>

## Append dinâmico

| Função | Retorno | Notas |
|--------|---------|-------|
| `append(s, val)` | `0` ok / `-1` erro | adiciona ao fim, marca válido; COW detach se view |
| `append_null(s)` | `0` ok / `-1` erro | adiciona posição nula; COW detach se view |

Grow strategy: quando `size >= capacity`, a capacidade cresce **1.5×**
(`capacity + capacity/2`), com guarda de overflow. Capacidade vazia cresce para
4. Append em uma view dispara COW detach antes do grow — ver `docs/COW.md`.

```
Progressão típica: 4 → 6 → 9 → 13 → 19 → 28 → 42 → ...
```

> Nota: o `append` cresce `data` e `null_mask` juntos. Se o segundo `realloc`
> falha, o primeiro é revertido para manter o invariante `size <= capacity` e os
> dois buffers sempre com `capacity` elementos (ver "Problemas conhecidos" #1,
> resolvido).

---

<a id="section-aritmeticas"></a>

## Aritméticas

**Série × série** — `add`, `sub`, `mul`, `div`:

- Retornam série nova; **NULL se** `a->size != b->size` ou ponteiro NULL.
- Propagação de NA: se qualquer operando na posição `i` é nulo, o resultado em
  `i` é nulo.
- `div` (f64): divisão por zero segue IEEE 754 (`±Inf` / `NaN`), resultado fica
  **válido**, sem checagem própria.
- `div` (i64): divisão por zero produz **NULL** naquela posição (não há `Inf`
  inteiro, e a divisão inteira por zero é comportamento indefinido em C). Ou
  seja, o i64 difere do f64 aqui: onde o f64 deixa `Inf`/`NaN` válido, o i64
  marca NA.

```
a   = [1.0, 2.0, NA ]
b   = [10.0, NA, 30.0]
a+b = [11.0, NA, NA ]
```

**Série × escalar** — `add_scalar`, `sub_scalar`, `mul_scalar`, `div_scalar`:

- Retornam série nova; o escalar nunca propaga NA. Posições nulas permanecem
  nulas; válidas recebem `op(data[i], scalar)`.
- `div_scalar` (i64) com `scalar == 0` retorna uma série **toda NULL** (mesmo
  motivo do `div` série×série: evita o UB da divisão inteira por zero).
  No f64, `div_scalar` por `0.0` segue IEEE 754 (`±Inf`/`NaN` válido).

---

<a id="section-parsing-formatacao-escalares"></a>

## Parsing e formatação de escalares (`smaug_convert.h`)

Estas funções são utilitários C sem estado. A variante com `(ptr, len)` valida
o slice completo, rejeita NUL dentro do comprimento declarado e não exige
terminador externo. A variante `_cstr` exige uma C-string terminada e não impõe
limite artificial de comprimento. As variantes `_status` retornam `SMG_OK` ou
uma causa explícita (`SMG_ERR_ARGUMENT`, `SMG_ERR_SYNTAX`,
`SMG_ERR_OVERFLOW`, `SMG_ERR_UNDERFLOW` ou `SMG_ERR_NOMEM`); em falha,
preservam o destino. Os wrappers sem `_status` mantêm 1/0 por compatibilidade.
O core usa ponto decimal, rejeita whitespace e consome toda a entrada. i64
aceita decimal e hexadecimal inteiro; f64 aceita decimal, hexadecimal com
expoente binário opcional e `nan`/`inf`/`infinity`.

```c
smaug_status_t smaug_parse_i64_status(const char *s, size_t len, int64_t *out);
smaug_status_t smaug_parse_f64_status(const char *s, size_t len, double *out);
smaug_status_t smaug_parse_i64_cstr_status(const char *s, int64_t *out);
smaug_status_t smaug_parse_f64_cstr_status(const char *s, double *out);
int smaug_parse_i64(const char *s, size_t len, int64_t *out); /* legado 1/0 */
int smaug_parse_f64(const char *s, size_t len, double *out); /* legado 1/0 */
int smaug_parse_i64_cstr(const char *s, int64_t *out);         /* legado 1/0 */
int smaug_parse_f64_cstr(const char *s, double *out);          /* legado 1/0 */
size_t smaug_fmt_i64(char *buf, size_t cap, int64_t value);
size_t smaug_fmt_f64(char *buf, size_t cap, double value);
```

Subnormais representáveis têm sucesso, inclusive quando a libc sinaliza
`ERANGE`; texto não zero que arredonda para zero retorna `SMG_ERR_UNDERFLOW`,
e overflow retorna `SMG_ERR_OVERFLOW`, inclusive saturação em DBL_MAX com
`ERANGE`. Sintaxe inválida prevalece sobre overflow de prefixo. O parser
preserva o modo de arredondamento do caller. Consumidores CSV podem usar a variante
`_cstr` quando o campo já estiver terminado. Os formatadores usam ponto decimal fixo, normalizam não finitos para
`nan`/`inf` e preservam zero negativo. Capacidade inclui o NUL (32 bytes bastam
para i64/f64); retorno positivo é comprimento efetivamente escrito, sem NUL.
Retorno zero indica falha de argumento/capacidade ou falha operacional,
sem alterar os bytes do destino. Não há modo de consulta de tamanho.
No POSIX, locale da thread é temporariamente selecionado e restaurado;
no Windows, a rotina de formatação recebe locale explícito. Não modificam o
locale global ou arredondamento do caller. Roundtrip f64 verificado em
FE_TONEAREST; outros modos seguem a libc sem garantia adicional de roundtrip.

<a id="section-reducoes"></a>

## Reduções

| Função | f64 retorna | i64 retorna |
|--------|-------------|-------------|
| `sum(s, ignore_na)` | `double` | `int64_t` |
| `prod` | `smaug_f64_prod(s, ignore_na)` → `double` | `smaug_i64_prod(s, ignore_na, status*)` → `int64_t` |
| `mean(s, ignore_na)` | `double` | `double` |
| `min(s, ignore_na)` | `double` | `int64_t` |
| `max(s, ignore_na)` | `double` | `int64_t` |
| `var(s, ignore_na)` | `double` | `double` |
| `std(s, ignore_na)` | `double` | `double` |

Regra do `ignore_na`:

- `ignore_na = true` → pula nulos.
- `ignore_na = false` → encontrar um nulo aborta e retorna um sentinela:
  **NAN** nas funções que retornam `double` (todas as f64, e `mean`/`var`/`std`
  do i64); **`INT64_MIN`** nas funções i64 que retornam `int64_t` (`sum`, `min`,
  `max`), já que `int64_t` não tem como representar NAN.

`var`/`std` são **amostrais** (ddof=1: dividem por N-1). Para n<2 retornam NaN
(variância amostral indefinida). Coerente com `cov`/`skew`/`kurtosis` e com o
`groupby`. `mean` de série vazia ou só-nulos → NAN.
`min`/`max` retornam NAN (f64) ou `INT64_MIN` (i64) se nenhum elemento válido.

**Status e sentinelas i64:** `smaug_i64_sum_checked(s, ignore_na, status*)`
retorna 0 com `SMG_ERR_ARGUMENT` para série NULL, 0 com `SMG_ERR_OVERFLOW`
em overflow e `INT64_MIN` com `SMG_NULL_VALUE` ao encontrar NA sem ignorá-lo.
Vazio ou tudo NA ignorado soma 0 com `SMG_OK`. O wrapper `sum` descarta status;
contar não-nulos ou usar `ignore_na=true` não detecta overflow. `min`/`max`
ainda exigem conferir presença de valores e política de NA para distinguir a
sentinela de um resultado válido. Produto i64 também possui canal de status.

---

<a id="section-comparacoes"></a>

## Comparações

```c
uint8_t* smaug_f64_gt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_lt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_eq(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
```

- Retornam um array `uint8_t*` alocado (`1` = verdadeiro, `0` = falso). **O
  caller deve liberar** o array (e o `*out_mask`, se pedido).
- `out_mask` é opcional: se não-NULL, recebe a null_mask do resultado (`0xFF`
  para posições válidas, `0x00` para nulas). Passe `NULL` se não precisar.
- NA de entrada → resultado `0` (falso) e mask `0x00` naquela posição.
- ⚠️ `eq` em floats sofre de imprecisão — evite comparar com `0.1` e afins.

```c
smaug_mask_t *out = NULL;
uint8_t *mask = smaug_f64_gt(s, 100.0, &out);
smaug_series_f64_t *filtrado = smaug_f64_filter(s, mask);
smaug_free(mask);
smaug_free(out);
```

---

<a id="section-ordenacao"></a>

## Ordenação

| Função | Retorno | Notas |
|--------|---------|-------|
| `argsort(s, ascending)` | `size_t*` / NULL | índices que ordenam; **NULL se a série tem qualquer nulo** |
| `sort(s, ascending)` | série / NULL | série nova ordenada (usa `argsort` + `take`) |

Não sabem posicionar NA, então falham se houver nulos. Remova os nulos antes de
chamar a API C. O `size_t*` de `argsort` é alocado — o caller libera com
`smaug_free`.

---

<a id="section-utilitarios"></a>

## Utilitários

| Função | Retorno | Notas |
|--------|---------|-------|
| `count_nonnull(s)` | `size_t` | número de elementos válidos |
| `take(s, idx, len)` | série / NULL | copia elementos nas posições `idx[0..len-1]`; NULL se algum índice fora dos limites |
| `filter(s, mask)` | série / NULL | série nova só com posições onde `mask[i] != 0` |

---

<a id="section-janelas-e-ordenacao-multipla"></a>

## Janelas e ordenação múltipla (`smaug_ops_window.h`)

`smaug_multi_argsort` e `smaug_multi_argsort_ffi` produzem uma permutação
estável de índices C 0-based. Todas as colunas de chave precisam ter o mesmo
`nrows` e posições válidas. Essas são precondições do caller: o C não valida
os tamanhos nem as máscaras das colunas. `cols == NULL`, `ncols == 0`,
`nrows == 0` ou falta de memória retornam `NULL`. O array retornado é liberado com
`smaug_free`.

As operações rolling recebem `window >= 1` e `min_periods`. Com
`min_periods == 0`, as primeiras `window - 1` posições são nulas. Com
`min_periods >= 1`, janelas parciais iniciais podem emitir resultados quando
atingem esse número de valores válidos. Nulos dentro da janela são ignorados e uma
janela sem valores válidos permanece nula. `std`/`var` são amostrais e ficam
indefinidas com menos de dois valores válidos. No i64, `sum`/`min`/`max`/`count`
retornam séries i64 e `mean`/`std`/`var` retornam séries f64; `sum_checked`
comunica overflow por `smaug_status_t`.

```c
size_t *smaug_multi_argsort(const smaug_sort_col_t *cols,
                             size_t ncols, size_t nrows);
smaug_series_f64_t *smaug_f64_rolling_sum(const smaug_series_f64_t *s,
                                          size_t window, size_t min_periods);
smaug_series_i64_t *smaug_i64_rolling_sum_checked(const smaug_series_i64_t *s,
                                                   size_t window, size_t min_periods,
                                                   smaug_status_t *status);
```

As assinaturas completas e os códigos de dtype (`SMAUG_COL_*`) estão no
header; a superfície Lua correspondente é `DataSet:rolling` e permanece
dependente da auditoria de consumidores em R6.

<a id="section-operacoes-boolean-raw-series-bool"></a>

## Operações Boolean (arrays raw e `Series<bool>`)

As comparações (`gt`/`lt`/`eq`) devolvem um par **(valores `uint8_t*`, máscara
`smaug_mask_t*`)** de mesmo comprimento — não um `smaug_series_*_t`. Valores:
`1` = true, `0` = false. As funções em `smaug_ops_bool.c` operam sobre esse par.

```c
uint8_t* smaug_bool_and(const uint8_t *a, const smaug_mask_t *am,
                        const uint8_t *b, const smaug_mask_t *bm,
                        size_t n, smaug_mask_t **out_mask);
/* ... or, xor (mesma assinatura); not tem só um operando ... */
size_t smaug_bool_count_true(const uint8_t *a, const smaug_mask_t *am, size_t n);
bool   smaug_bool_any(const uint8_t *a, const smaug_mask_t *am, size_t n);
bool   smaug_bool_all(const uint8_t *a, const smaug_mask_t *am, size_t n);
```

- Cada op lógica aloca um novo array de valores (e, via `out_mask` não-NULL, a
  máscara do resultado). **O caller libera ambos** com `smaug_free()`.
- Máscara `NULL` na entrada = todos os elementos válidos.
- **Lógica de três valores (Kleene)**, igual a SQL/pandas:

  | op | regra com NA |
  |----|--------------|
  | AND | `NA and false = false`; `NA and true = NA`; `NA and NA = NA` |
  | OR  | `NA or true = true`; `NA or false = NA`; `NA or NA = NA` |
  | XOR | qualquer operando NA → `NA` |
  | NOT | `not NA = NA` |

- Agregações **ignoram NA**: `count_true` conta só os válidos verdadeiros;
  `any` = existe algum válido true; `all` = todos os válidos são true (NA
  pulado); `all` de vazio = `true` (vacuamente verdadeiro).

No frontend atual, a superfície pública é `Series<bool>`, com os métodos
`:land/:lor/:lxor/:lnot`, `:count_true/:any/:all` e os operadores `*` (and),
`+` (or), `-` (xor). Os arrays raw acima permanecem uma API C legada; não há
uma classe `lua/smaug/core/boolseries.lua`. `Series:filter` aceita a série bool
como máscara e a camada Lua converte o resultado para a operação do dtype.

---

<a id="section-strings-smaug-str"></a>

## Strings (`smaug_str_*`)

Tipo Tier 1 completo. Representação **offset-based** (estilo Arrow): um buffer de
bytes concatenados + um array de offsets. Trata **bytes crus** — não há
normalização nem validação UTF-8 (dívida futura). Comparações e ordenação são
**lexicográficas por byte**, não Unicode-aware. A string vazia `""` é um valor
**válido e distinto de NULL**.

> **String tem view + Copy-on-Write** (item 9.2). Diferente de f64/i64 (buffer
> fixo, view = soma de ponteiro O(1)), a string é offset-based, então a view usa
> **posse mista** (campo `offsets_owned` na struct): compartilha `buffer` e
> `null_mask` com o pai, mas possui um `offsets` próprio absoluto de (len+1)
> marcadores. A primeira mutação dispara detach, que materializa buffer/offsets
> (rebaseados)/null_mask privados da janela; o pai fica intacto. Ver COW.md.

<a id="section-lifecycle-1"></a>

### Lifecycle

| Função | Retorno | Notas |
|--------|---------|-------|
| `create(size)` | série / NULL | todos os elementos nascem NULL |
| `create_with_capacity(size, buffer_capacity)` | série / NULL | pré-aloca o buffer de bytes para `set`/`append` |
| `create_from_array(array, len)` | série / NULL | `array` é `const char *const *`; entrada `NULL` no array → posição NULL |
| `free(s)` | void | idempotente (`NULL` seguro); respeita `external_alloc` |
| `clone(s)` | série / NULL | deep copy independente |
| `view(s, start, len)` | série / NULL | janela **zero-copy** `[start, start+len)`; posse mista (offsets próprio); COW na 1ª mutação; NULL se `start+len > size` ou OOM |

<a id="section-acesso-e-mutacao"></a>

### Acesso e mutação

| Função | Retorno | Comportamento |
|--------|---------|---------------|
| `get(s, idx, out_len)` | `const char*` / NULL | ponteiro para os bytes (**não** terminado em `\0`); escreve o comprimento em `*out_len`. NULL se `idx` inválido ou posição NULL |
| `set(s, idx, str, len)` | `smaug_status_t` | grava `len` bytes; pode realocar o buffer. `SMG_OK`/`SMG_ERR_OOB`/`SMG_ERR_ARGUMENT`/`SMG_ERR_NOMEM` |
| `set_null(s, idx)` | `smaug_status_t` | marca a posição como NULL |
| `is_null(s, idx)` | `bool` | `true` se NULL ou fora dos limites |
| `append(s, str, len)` | `0` ok / `-1` erro | adiciona ao fim |
| `append_null(s)` | `0` ok / `-1` erro | adiciona posição nula ao fim |
| `count_nonnull(s)` | `size_t` | número de elementos válidos |

> **`get` não usa `smaug_status_t`** — já distingue erro/NULL de valor pelo
> retorno `NULL` + `out_len`, sem colisão. O ponteiro aponta para dentro do
> buffer interno: **não liberar**, e tratar como inválido após qualquer mutação
> que possa realocar o buffer (`set`/`append`).
>
> **`set` retorna `smaug_status_t`** (migrado do antigo `int`), consistente com
> `f64_set`/`i64_set`. O `SMG_ERR_NOMEM` pode vir da realocação do buffer de
> bytes ou do detach COW (quando a série é uma view — ver `view`, abaixo).

<a id="section-comparacoes-1"></a>

### Comparações

```c
uint8_t* smaug_str_eq(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);
uint8_t* smaug_str_lt(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);
uint8_t* smaug_str_gt(const smaug_series_str_t *s, const char *target, size_t target_len, smaug_mask_t **out_mask);
```

- Comparação **byte-lexicográfica** contra `target` (`target_len` bytes). Mesma
  convenção dos numéricos: devolvem array `uint8_t*` (`1`/`0`) e, via `out_mask`
  não-NULL, a máscara do resultado. **O caller libera ambos** com `smaug_free`.
- NA de entrada → resultado `0` e mask `0x00` naquela posição.

<a id="section-filtro-e-ordenacao"></a>

### Filtro e ordenação

| Função | Retorno | Notas |
|--------|---------|-------|
| `filter(s, mask)` | série / NULL | nova série só com posições onde `mask[i] != 0` (preserva NULL) |
| `take(s, idx, len)` | série / NULL | copia os índices `idx[0..len-1]` (preserva NULL); NULL se algum índice fora dos limites |
| `argsort(s, ascending)` | `size_t*` / NULL | índices que ordenam; **NULL se a série tem qualquer nulo**; libera com `smaug_free` |
| `sort(s, ascending)` | série / NULL | nova série ordenada (= `argsort` + `take`); NULL se há nulos |

> Memória: séries (`create`/`clone`/`filter`/`take`/`sort`) liberam com
> `smaug_str_free`; buffers crus de comparação/`argsort` (`uint8_t*`, `size_t*`,
> `out_mask`) liberam com `smaug_free`. No frontend Lua, `ffi.gc` cuida dos
> structs de série.

---

<a id="section-diferencas-do-int64-i64"></a>

## Diferenças do int64 (`i64`)

A API i64 compartilha operações com f64, mas tem canais checked e assinaturas
próprias. Diferenças semânticas:

- `sum`, `min`, `max` retornam `int64_t`. A soma checked distingue erro via
  status e soma vazia vale 0; min/max sem valores usam `INT64_MIN`.
  Ver detalhes e nulidade na seção Reduções.
- `mean`, `var`, `std` retornam `double` — a média de inteiros pode ser
  fracionária; nunca truncar implicitamente. Usam NAN como sentinela.
- `div` (série e escalar) é **divisão inteira** (trunca). Divisão por zero vira
  **NULL** (não `Inf`/`NaN` como no f64), evitando o UB da divisão inteira.
- `get` retorna `int64_t` e **não tem NAN** para sinalizar nulo. O caller **deve
  checar `is_null` antes** de confiar no valor (um nulo devolve `0`, que é
  ambíguo).

Use i64 para contadores, IDs, índices e timestamps. Evite para razões,
proporções ou medições que exijam precisão fracionária.

---

<a id="section-views-e-copy-on-write"></a>

## Views e Copy-on-Write

Uma view é uma janela sobre uma faixa de elementos de uma série existente,
criada em O(1) sem copiar dados.

```c
smaug_series_f64_t *v = smaug_f64_view(s, start, len);
/* v->data == s->data + start  (ponteiro compartilhado) */
```

**Semântica COW:** a primeira operação de escrita em `v` (qualquer de `set`,
`set_null`, `append`, `append_null`) dispara um detach automático: `v` recebe
um buffer privado com cópia dos seus `len` elementos, e torna-se completamente
independente de `s`.

| operação em view | resultado |
|---|---|
| `get`, `is_null`, `clone`, `filter`, `take`, `sort` | sem detach — lê o armazenamento compartilhado |
| `set`, `set_null` | detach → escreve; `SMG_ERR_NOMEM` se OOM |
| `append`, `append_null` | detach → grow → escreve; `-1` se OOM |
| detach OOM | série intacta, pai intacto (falha segura) |

Após o detach: `is_view = false`, `external_alloc = false`, `capacity = len`.
O pai nunca é modificado. Para a especificação completa, ver `docs/COW.md`.

---

<a id="section-gerenciamento-de-memoria-resumo"></a>

## Gerenciamento de memória — resumo

| Operação | Quem aloca | Responsabilidade do caller |
|----------|-----------|----------------------------|
| `create`, `clone`, `create_from_array` | Smaug | destrutor `smaug_<dtype>_free` |
| `add`/`sub`/`mul`/`div`, `*_scalar`, `sort`, `take`, `filter` | Smaug | destrutor do dtype do resultado |
| `view` | Smaug | destrutor do dtype; manter buffers do pai válidos enquanto compartilhar |
| `gt`/`lt`/`eq` | Smaug | `smaug_free` no array `uint8_t*` e no `out_mask` |
| `argsort` | Smaug | `smaug_free` no `size_t*` |
| bool raw (and/or/xor/not) | Smaug | `smaug_free` nos arrays; API struct usa destrutor bool |

No frontend Lua, use `ffi.gc(ptr, C.smaug_f64_free)` para automatizar a limpeza
dos structs de série.

---

<a id="section-problemas-conhecidos"></a>

## Problemas conhecidos

1. ~~**`f64_grow` / `i64_grow` em falha parcial de realloc.**~~ **RESOLVIDO.**
   Antes, se o `realloc` do `data` tinha sucesso mas o do `null_mask` falhava,
   `s->data` era atualizado mas `s->capacity` não — série inconsistente. Agora,
   em falha do `null_mask`, o `data` é encolhido de volta para o `capacity`
   antigo, preservando o invariante (ambos os buffers sempre com `capacity`
   elementos). Coberto por `tests/c/test_alloc.c`.

2. **Convenção de `0xFF`/`0x00` vs `1`/`0`.** As máscaras de null usam
   `0xFF`/`0x00`, mas `gt`/`lt`/`eq` devolvem `1`/`0` no array booleano.
   `filter` checa `if (mask[i])`, então funciona, mas é uma inconsistência de
   convenção — documentar ou unificar.

---

<a id="section-anel-3-i-o-smaug-io-h"></a>

## Anel 3 — I/O (`smaug_io.h`)

Parsers CSV e JSON escritos do zero, zero dependências externas.
Fronteira `smaug_table_t` entre leitores e o frontend Lua.

<a id="schema-api"></a>
### Schema reutilizável (`smaug_schema.h`)

Descritor independente de formato: sequência não vazia de campos únicos por
bytes. `name` não nulo, comprimento explícito, dtype e nullable (exatamente
0 ou 1). Tipos públicos: `SMAUG_DTYPE_BOOL`, `SMAUG_DTYPE_INT64`,
`SMAUG_DTYPE_FLOAT64`, `SMAUG_DTYPE_STRING`. Schema/nomes são emprestados e
imutáveis durante a chamada; tabelas resultantes possuem suas próprias cópias.

```c
typedef struct {
    const char *name;
    size_t name_len;
    smaug_dtype_t dtype;
    int nullable;
} smaug_schema_field_t;
typedef struct {
    const smaug_schema_field_t *fields;
    size_t count;
} smaug_schema_t;

smaug_status_t smaug_schema_validate(const smaug_schema_t *schema, size_t *error_field);
smaug_table_t *smaug_read_csv_mem_schema(const char *buffer, size_t length,
    const smaug_csv_opts_t *opts, const smaug_schema_t *schema);
smaug_table_t *smaug_read_csv_schema(const char *path,
    const smaug_csv_opts_t *opts, const smaug_schema_t *schema);
smaug_table_t *smaug_read_json_mem_schema(const char *buffer, size_t length,
    const smaug_schema_t *schema);
smaug_table_t *smaug_read_json_schema(const char *path, const smaug_schema_t *schema);
```

`smaug_schema_validate` não aloca: retorna OK, ARGUMENT ou OVERFLOW; o índice
opcional `error_field` é base 0, ou SIZE_MAX para sucesso/erro global. Os leitores
exigem schema válido, retornam tabela de erro ou NULL em OOM, sem resultado
parcial. Liberar qualquer tabela com `smaug_table_free`. `buffer=NULL` só é
admissível com comprimento zero (a gramática ainda exige entrada válida).
Caminhos de arquivo são C-strings não nulas.

CSV com header/JSON associam por nome; CSV sem header por posição. Saída na
ordem do schema; tipos/nulidade são validados antes da publicação. Regras de
conversão e ausência no [contrato](CONTRACT.md#schema-reutilizavel).

São símbolos adicionais sem mudança dos layouts existentes: ABI permanece 1.
Frontend novo verifica capacidade de schema e orienta recompilação quando a
biblioteca carregada não tem os símbolos; ABI não é versão de funcionalidade.
Os descritores em memória não especificam o formato futuro `.smg`.

<a id="section--smaug-table-t-struct-intermediaria"></a>

### `smaug_table_t` — struct intermediária

**ABI 1:** `uint32_t smaug_abi_version(void)` (smaug_core.h) identifica o layout.
Recompile biblioteca e consumidores juntos. O frontend Lua consulta a versão
antes de acessar structs; biblioteca carregada sem símbolo ou com versão
diferente é rejeitada sem fallback. Frontends antigos não têm essa proteção.


```c
typedef struct {
    const char          *name;     /* bytes do nome; ponteiro não nulo */
    size_t               name_len; /* comprimento real, inclusive NUL interno */
    const char          *dtype;    /* "float64" | "int64" | "bool" | "string" */
    smaug_series_f64_t  *f64;
    smaug_series_i64_t  *i64;
    smaug_series_bool_t *boolcol;
    smaug_series_str_t  *str;
} smaug_column_t;

typedef struct {
    smaug_column_t *columns;
    size_t          ncols;
    size_t          nrows;
    char           *error;   /* NULL se ok; mensagem de erro se falhou */
} smaug_table_t;
```

Verificar `t->error != NULL` antes de usar. Liberar sempre com `smaug_table_free`.

<a id="section-csv"></a>

### CSV

```c
/* opts.na_values != NULL: na_lengths aponta para na_count comprimentos.
   Com na_count > 0, ambos os arrays e cada marcador precisam ser válidos.
   Arrays são emprestados pela duração da chamada. na_values == NULL usa
   padrões; na_values != NULL e na_count == 0 desativa todos os marcadores. */
smaug_csv_opts_t smaug_csv_default_opts(void);
/* sep=',', header=1, quote='"', na={"","NA","null","N/A","NULL"} */

smaug_table_t* smaug_read_csv(const char *path, const smaug_csv_opts_t *opts);
smaug_table_t* smaug_read_csv_mem(const char *buf, size_t len,
                                   const smaug_csv_opts_t *opts);

smaug_csv_write_opts_t smaug_csv_write_default_opts(void);
int   smaug_write_csv(const char *path, const smaug_table_t *t,
                      const smaug_csv_write_opts_t *opts);
char* smaug_write_csv_mem(const smaug_table_t *t,
                           const smaug_csv_write_opts_t *opts,
                           size_t *out_len, char **err_out);
/* buffer retornado terminado em \0; liberar com smaug_free.
   err_out recebe uma causa duplicada em erro, quando fornecido. */
```

**Inferência de tipo:** cada coluna testada em ordem `bool → int64 → float64 → string`.
Coluna mista sobe para o tipo mais abrangente. Coluna toda NA → string.

**RFC 4180:** aspas duplas suportadas (`"campo com, vírgula"`, `""aspas""` → `"`).
O leitor aceita um BOM inicial, LF e CRLF; rejeita CR isolado, aspas
malformadas e registros com largura diferente do header. Um campo vazio
explícito é ausência/NA; um campo omitido é erro estrutural. O writer não emite
BOM.

<a id="section-json"></a>

### JSON

```c
smaug_table_t* smaug_read_json(const char *path);
smaug_table_t* smaug_read_json_mem(const char *buf, size_t len);
/* Formato: array de records [ {...}, {...} ] */

int   smaug_write_json(const char *path, const smaug_table_t *t,
                       const smaug_json_write_opts_t *opts);
char* smaug_write_json_mem(const smaug_table_t *t,
                            const smaug_json_write_opts_t *opts,
                            size_t *out_len, char **err_out);
/* NaN → null no JSON. Escapes: \n \t \\ \" \uXXXX para controles.
   err_out recebe uma causa duplicada em erro, quando fornecido. */
```

Na leitura e na escrita, nomes e valores string JSON precisam formar UTF-8
válido conforme RFC 3629. Sequência inválida, truncada, sobrelonga, surrogate
codificada ou codepoint acima de U+10FFFF gera diagnóstico com a posição do
byte e não publica resultado parcial. O core e o CSV continuam trabalhando com
bytes crus, inclusive NUL; essa validação pertence à operação JSON.

<a id="section-ciclo-de-vida"></a>

### Ciclo de vida

```c
void smaug_table_free(smaug_table_t *t);   /* NULL-safe */
```

Propriedade: `smaug_table_t*` possui seus recursos. O frontend Lua chama
`smaug_table_free` após consumir a tabela e construir o `DataSet`.

---

<a id="section-anel-0-datetime-smaug-datetime-h"></a>

## Anel 0 — Datetime (`smaug_datetime.h`)

Implementado no backend C (Anel 0) e
consumido pelo frontend Lua. Armazenamento: `int64_t` representando
**epoch em milissegundos UTC**. Calendário Gregoriano proléptico, sem
dependência de timezone (UTC no armazenamento, apresentação local é do caller).

Mesmos contratos defensivos dos outros dtypes: `smaug_status_t` em `get`/`set`,
null por bitmask, COW em views.

<a id="section-lifecycle-2"></a>

### Lifecycle

```c
smaug_series_dt_t* smaug_dt_create(size_t size);
smaug_series_dt_t* smaug_dt_create_with_capacity(size_t size, size_t capacity);
smaug_series_dt_t* smaug_dt_create_from_array(const int64_t *array, size_t len);
void               smaug_dt_free(smaug_series_dt_t *s);                  /* NULL-safe */
smaug_series_dt_t* smaug_dt_clone(const smaug_series_dt_t *s);
smaug_series_dt_t* smaug_dt_view(smaug_series_dt_t *s, size_t start, size_t len);
```

<a id="section-acesso"></a>

### Acesso

```c
int64_t        smaug_dt_get(const smaug_series_dt_t *s, size_t idx, smaug_status_t *status);
smaug_status_t smaug_dt_set(smaug_series_dt_t *s, size_t idx, int64_t epoch_ms);
smaug_status_t smaug_dt_set_null(smaug_series_dt_t *s, size_t idx);
bool           smaug_dt_is_null(const smaug_series_dt_t *s, size_t idx);
int            smaug_dt_append(smaug_series_dt_t *s, int64_t epoch_ms);   /* 0=ok */
int            smaug_dt_append_null(smaug_series_dt_t *s);
```

Sentinela em erro/null no `get`: `INT64_MIN` (igual `i64`).

<a id="section-parsing-formatacao-iso-8601"></a>

### Parsing / formatação ISO 8601

```c
int smaug_dt_parse(const char *str, size_t len, int64_t *epoch_ms, int dayfirst);
/* dayfirst: 1 para DD/MM/YYYY, 0 para MM/DD/YYYY; formatos year-first ignoram. */
/* Aceita: "YYYY-MM-DD", "YYYY-MM-DDTHH:MM:SS[.mmm][Z|±HH:MM]". */
/* Retorna 0 em sucesso, -1 em formato inválido. epoch_ms escrito só em sucesso. */

int smaug_dt_format(int64_t epoch_ms, char *buf, size_t buf_size);
/* Formato fixo: "YYYY-MM-DDTHH:MM:SS.mmmZ" (25 chars + \0). Buf >= 26. */
```

<a id="section-extracao-de-componentes-operam-em-epoch-ms-escalar-retornam-1-em-erro"></a>

### Extração de componentes (operam em epoch_ms escalar; retornam -1 em erro)

```c
int smaug_dt_year   (int64_t epoch_ms);   int smaug_dt_month  (int64_t epoch_ms);
int smaug_dt_day    (int64_t epoch_ms);   int smaug_dt_hour   (int64_t epoch_ms);
int smaug_dt_minute (int64_t epoch_ms);   int smaug_dt_second (int64_t epoch_ms);
int smaug_dt_ms     (int64_t epoch_ms);   int smaug_dt_weekday(int64_t epoch_ms);
int smaug_dt_yearday(int64_t epoch_ms);   int smaug_dt_quarter(int64_t epoch_ms);
int smaug_dt_week   (int64_t epoch_ms);   /* ISO 8601 (semana 1 = primeira com >= 4 dias) */
```

<a id="section-construcao-e-aritmetica"></a>

### Construção e aritmética

```c
int64_t smaug_dt_from_parts(int year, int month, int day,
                             int hour, int minute, int second, int ms);
/* Retorna INT64_MIN em data inválida (ex.: 13/30/etc). */

int64_t smaug_dt_diff_ms(int64_t a, int64_t b);              /* a - b */
int64_t smaug_dt_add_ms (int64_t epoch_ms, int64_t delta_ms);/* saturação em overflow → INT64_MIN */
int64_t smaug_dt_truncate(int64_t epoch_ms, char unit);
/* unit: 's'=segundo 'm'=minuto 'h'=hora 'D'=dia 'W'=semana(seg) 'M'=mês 'Q'=tri 'Y'=ano */
```

<a id="section-comparacoes-ordenacao-e-selecao"></a>

### Comparações, ordenação e seleção

Mesma assinatura dos outros dtypes; o threshold é `int64_t` (epoch_ms):

```c
uint8_t* smaug_dt_gt/lt/eq/ge/le/ne(const smaug_series_dt_t *s,
                                     int64_t threshold,
                                     smaug_mask_t **out_mask);
/* Caller libera com smaug_free. NULL em erro. */

size_t*             smaug_dt_argsort(const smaug_series_dt_t *s, bool ascending);
smaug_series_dt_t*  smaug_dt_sort   (const smaug_series_dt_t *s, bool ascending);
size_t              smaug_dt_count_nonnull(const smaug_series_dt_t *s);
smaug_series_dt_t*  smaug_dt_take  (const smaug_series_dt_t *s, const size_t *idx, size_t len);
smaug_series_dt_t*  smaug_dt_filter(const smaug_series_dt_t *s, const uint8_t *mask);
```

`sort`/`argsort` recusam séries com null (retornam `NULL`), igual aos outros dtypes.

<a id="section-datetime-migracao-c"></a>

## Datetime — evolução da API C

Levantamento da árvore baseada em `c7f34db`, por leitura de fontes e headers.
As tabelas distinguem implementação atual, decisão aprovada e proposta.
Nenhuma assinatura foi alterada nesta etapa documental. O domínio e as regras
normativas estão no [contrato datetime](CONTRACT.md#section-perfil-datetime-decisoes-aprovadas-em-2026-09-18).

<a id="section-decisao-fechada-e-alcance"></a>

### Decisão fechada e alcance

Assinaturas finais aprovadas para os 11 componentes escalares, ainda não
implementadas:

```c
smaug_status_t smaug_dt_year(int64_t epoch_ms, int *out_year);
smaug_status_t smaug_dt_month(int64_t epoch_ms, int *out_month);
smaug_status_t smaug_dt_day(int64_t epoch_ms, int *out_day);
smaug_status_t smaug_dt_hour(int64_t epoch_ms, int *out_hour);
smaug_status_t smaug_dt_minute(int64_t epoch_ms, int *out_minute);
smaug_status_t smaug_dt_second(int64_t epoch_ms, int *out_second);
smaug_status_t smaug_dt_ms(int64_t epoch_ms, int *out_ms);
smaug_status_t smaug_dt_weekday(int64_t epoch_ms, int *out_weekday);
smaug_status_t smaug_dt_yearday(int64_t epoch_ms, int *out_yearday);
smaug_status_t smaug_dt_quarter(int64_t epoch_ms, int *out_quarter);
smaug_status_t smaug_dt_week(int64_t epoch_ms, int *out_week);
```

Sem `_checked`. Todos validam a entrada e retornam `SMG_OK` em sucesso,
escrevendo o componente no parâmetro de saída correspondente. Falha preserva
a saída; o consumidor deve verificar o status antes de ler o resultado.
Ano `-1` é válido. Os nomes dos métodos `.dt` permanecem no Lua.

A convenção está aprovada para os 11 componentes escalares. Para as 11 variantes
de série, o comportamento foi aprovado em 2026-09-21: resultado completo em
sucesso; datetime inválido gera erro com posição, sem resultado parcial;
NA propaga na mesma posição e a entrada permanece intacta. Ver o
[contrato](CONTRACT.md#section-perfil-datetime-decisoes-aprovadas-em-2026-09-18).
Padrão mínimo de assinatura aprovado para as 11 variantes, ainda não implementado:

```c
smaug_status_t smaug_dt_year_series(
    const smaug_series_dt_t *s,
    smaug_series_i64_t **out,
    size_t *error_index
);
```

Aplicar os mesmos parâmetros às variantes `month`, `day`, `hour`, `minute`,
`second`, `ms`, `weekday`, `yearday`, `quarter` e `week`, preservando seus
nomes `smaug_dt_<componente>_series`. `out` recebe a série completa somente
em sucesso; `error_index` é opcional e transporta apenas o índice do primeiro
elemento que falhou na ordem da série. Interromper nessa falha, sem entregar
resultado parcial; NA não conta como erro. O C usa índice baseado em 0;
o Lua apresenta posição baseada em 1. O parâmetro não substitui o status:
o C valida e comunica status/posição, e o Lua monta e apresenta a mensagem.
Não criar `smaug_dt_diagnostic_t` para essas operações. Quando fornecido,
`error_index` só é escrito se um elemento falhar. Em sucesso ou falha sem
posição (argumento inválido ou falta de memória), permanece intocado e o
consumidor não o consulta. Não usar sentinela como `SIZE_MAX`.

Correspondência aprovada, restrita às 11 extrações de componentes em série:

| Situação | Status | Consultar `error_index`? |
|---|---|---|
| Sucesso | `SMG_OK` | Não |
| Argumento inválido, como ponteiro obrigatório nulo | `SMG_ERR_ARGUMENT` | Não |
| Falta de memória | `SMG_ERR_NOMEM` | Não |
| Primeiro datetime fora do domínio permitido | `SMG_ERR_OVERFLOW` | Sim, se fornecido |

Nessa família, `SMG_ERR_OVERFLOW` indica exclusivamente falha no valor de um
elemento e garante a escrita do índice quando fornecido. O consumidor verifica
o status antes de consultar a posição. NA não gera erro e continua propagando.

Limitar a mudança ao necessário para corrigir a extração e comunicar erros,
atualizando C, FFI, consumidores Lua e testes em conjunto.
Nas demais
famílias abaixo, permanece proposta de migração, não
aprovação automática de uma reforma de todas as APIs C. Ponteiros de saída
devem ser válidos e graváveis; verificar NULL não prova a validade de qualquer
endereço arbitrário fornecido pelo caller.

<a id="section-nucleo-de-calendario-assinaturas-e-mudancas"></a>

### Núcleo de calendário: assinaturas e mudanças

Prefixo `smaug_dt_` omitido na tabela. Fontes principais:
[header](../include/smaug_datetime.h), [implementação](../src/smaug_datetime.c)
e [espelho FFI](../lua/smaug/ffi_loader.lua).

| APIs | Atual | Destino / decisão necessária |
|---|---|---|
| `year` | `int (int64_t)`; header promete -1 em erro | Aprovado: status + `int *out_year`, mesmo nome |
| `month`, `day`, `hour`, `minute`, `second`, `ms`, `weekday`, `yearday`, `quarter`, `week` | Mesmo formato escalar; sem validação integral do domínio aprovado | Aprovado: status + saída `int *out_<componente>`, mesmo nome sem sufixo; validar epoch e preservar saída |
| As 11 variantes `*_series` correspondentes | Ponteiro i64 ou NULL; macro só grava componentes >= 0 | Aprovado: status + `smaug_series_i64_t **out` escrito somente em sucesso + `size_t *error_index` opcional; sem resultado parcial, entrada intacta e NA propagado |
| `parse(str, len, out_epoch, dayfirst)` / `parse_checked` | Parser estrito compartilhado; legado 0/-1, checked com status; ano negativo, precisão exata e domínio UTC implementados | Migração global de assinaturas e eventual ordem automática continuam pendentes |
| `format(epoch, buffer, capacity)` | 0/-1; exige 26 bytes; snprintf pode truncar em falha | Proposto: status, buffer preservado em falha e constante pública de 28 bytes para saída canônica completa |
| `from_parts` / `from_parts_checked` | Sentinela INT64_MIN / status + saída | Proposto: unificar sob `from_parts`, status + saída; validar componentes e domínio |
| `diff_ms` / `diff_ms_checked` | Sentinela INT64_MIN / status + saída | Proposto: unificar sob `diff_ms`; validar os dois instantes; resultado é duração int64, não datetime |
| `add_ms` / `add_ms_checked` | Sentinela INT64_MIN / status + saída | Proposto: unificar sob `add_ms`; validar epoch, soma e domínio do resultado |
| `truncate` / `truncate_checked` | Sentinela INT64_MIN / status + saída | Proposto: unificar sob `truncate`; unidade inválida é argumento; validar fronteiras, inclusive semana no limite inferior |

Dependências internas: `quarter` chama `month`; `week` usa `weekday` e
`yearday`; `truncate` semanal usa `weekday`; parser chama construção e soma;
macro de componentes chama todas as escalares. A migração precisa atualizar
essas chamadas, não apenas os consumidores Lua. A semana ISO de 2023-01-01
deve resultar em 52 (regressão R02).

O parser deve validar o instante final após offset. Não reutilizar uma função
pública que rejeite prematuramente um intermediário local antes de normalizar
para UTC; explicitar o domínio permitido para os componentes textuais locais.

<a id="section-outras-entradas-e-operacoes-datetime"></a>

### Outras entradas e operações datetime

Estas APIs estão inventariadas para evitar brechas no domínio, sem decidir
agora padronização geral de assinaturas. Prefixo `smaug_dt_` omitido.

| Família | Símbolos | Contrato atual / ponto de revisão |
|---|---|---|
| Lifecycle | `create`, `create_with_capacity`, `create_from_array`, `clone`, `view`, `free` | Ponteiro/NULL, free void; distinguir OOM e argumento; array introduz epochs; lifetime de view permanece tópico separado |
| Acesso | `get`, `set`, `set_null`, `is_null`, `append`, `append_null` | get valor + status opcional; set status; append 0/-1; is_null bool. set/append de epoch precisam validar faixa antes de mutar/detach |
| Combinação | `coalesce_scalar`, `coalesce`, `select` | Ponteiro/NULL; valor escalar pode introduzir epoch; conferir compatibilidade de tamanhos e preservação das máscaras |
| Comparação | `gt`, `lt`, `eq`, `ge`, `le`, `ne`, `between` | Dados uint8 + máscara por saída; NULL em falha; definir validação dos thresholds e ownership das duas alocações |
| Ordenação | `argsort`, `sort`, `rank` | Ponteiro/NULL; argsort/sort recusam NA no contrato atual; rank usa NAN para NA. Não alterar política de ausência por analogia com erros |
| Seleção/movimentação | `take`, `filter`, `ffill`, `bfill`, `shift` | Série nova/NULL; preservar semântica de ausência e ownership |
| Redução | `count_nonnull`, `argmin`, `argmax`, `min`, `max` | Contagem ou sentinelas SIZE_MAX/INT64_MIN; distinguir resultado ausente de erro real na futura matriz de status |

Conversões de [smaug_astype.h](../include/smaug_astype.h) e
[smaug_astype.c](../src/smaug_astype.c):

| APIs | Atual | Trabalho necessário |
|---|---|---|
| `smaug_str_to_dt` / `smaug_str_to_dt_checked` | Conversão textual estrita implementada; checked retorna status e primeira posição inválida; legado retorna NULL em falha | Diagnóstico dedicado de conflito/ordem automática continua separado |
| `smaug_i64_to_dt` / `smaug_i64_to_dt_checked` | Validação estrita do domínio; cópia int64 exata; checked informa posição | Implementado; saída apenas em sucesso |
| `smaug_f64_to_dt` / `smaug_f64_to_dt_checked` | Rejeita NaN/inf/fração e valores fora do domínio; checked informa posição | Implementado; valida antes do cast, sem truncamento |
| `smaug_dt_to_i64`, `smaug_dt_to_f64` | Cópia/conversão numérica | Conferir domínio e nulidade; duração e epoch não têm o mesmo contrato |
| `smaug_dt_to_str` | Ignora status do formatter; buffer local 40 bytes | Propagar falha e liberar resultado parcial; buffer já comporta 28 bytes |

<a id="section-consumidores-a-migrar"></a>

### Consumidores C e fronteira FFI

| Arquivo | Chamadas e impacto |
|---|---|
| `lua/smaug/ffi_loader.lua` | Espelha assinaturas públicas; atualizar junto com biblioteca C |
| `src/smaug_csv.c`, `src/smaug_json.c` | Inferência própria no C; detecção de datas exige integração explícita, não surge ao mudar o construtor Lua |

Os consumidores e comportamentos Lua ficam na
[referência Lua](API_INDEX.md#section-datetime-migracao-lua).

<a id="section-diagnostico-status-e-memoria"></a>

### Diagnóstico, status e memória

**Conversão textual e numérica implementada em 2026-09-25:**

```c
smaug_status_t smaug_dt_parse_checked(
    const char *str, size_t len, int64_t *epoch_ms, int dayfirst);
smaug_status_t smaug_str_to_dt_checked(
    const smaug_series_str_t *self, int dayfirst,
    smaug_series_dt_t **out, size_t *error_index);
smaug_status_t smaug_i64_to_dt_checked(
    const smaug_series_i64_t *self, smaug_series_dt_t **out, size_t *error_index);
smaug_status_t smaug_f64_to_dt_checked(
    const smaug_series_f64_t *self, smaug_series_dt_t **out, size_t *error_index);
```

As entradas checked são adicionais; as assinaturas legadas permanecem.
`smaug_dt_parse` delega ao parser checked e traduz qualquer falha para -1.
`smaug_str_to_dt` delega à conversão checked e retorna NULL em qualquer falha,
inclusive texto inválido: a ABI foi preservada, a tolerância antiga foi retirada.
Atualizar DLL e frontend em conjunto para disponibilizar os novos símbolos.

Os wrappers numéricos de ponteiro também delegam às variantes checked e retornam
NULL em qualquer falha. A faixa UTC tem fonte única no header datetime:
`SMAUG_DT_MIN_EPOCH_MS`/`SMAUG_DT_MAX_EPOCH_MS`, inclusivos. Para float64,
NaN/inf geram `SMG_ERR_ARGUMENT`; finito fora da faixa gera `SMG_ERR_OVERFLOW`;
fração dentro da faixa gera `SMG_ERR_ARGUMENT`. O cast só ocorre após validar.
Todos os inteiros do domínio datetime são representáveis exatamente em double.
Int64 é validado diretamente, sem round-trip por double.

O parser retorna `SMG_ERR_ARGUMENT` para sintaxe/data/opção inválida ou perda
de precisão e `SMG_ERR_OVERFLOW` para instante UTC fora do domínio. Escreve
o epoch somente em sucesso. O domínio é validado após normalizar o offset.

Nas três conversões de série, `self`/`out` são obrigatórios; na textual,
`dayfirst` é 0 ou 1.
Argumentos de chamada inválidos retornam `SMG_ERR_ARGUMENT` sem escrever saídas.
**Com esses argumentos válidos**, `SMG_ERR_ARGUMENT`/`SMG_ERR_OVERFLOW` indicam
falha no primeiro elemento não nulo inválido e escrevem `error_index` opcional
(base 0). Essa precondição distingue falha de chamada de falha de elemento;
não aplicar aqui a tabela exclusiva das 11 extrações. O frontend garante a
precondição antes de consultar o índice. `SMG_ERR_NOMEM` e `SMG_OK` preservam
o índice. Não há sentinela nem estrutura de diagnóstico nesta etapa.

`*out` só é escrito em sucesso; o caller assume ownership e libera com
`smaug_dt_free`. Falha libera o resultado temporário, preserva a entrada e
não entrega série parcial. NA propaga. A ordem é única na série (`dayfirst`),
sem detecção automática ou diagnóstico `DATE_ON_THE_FENCE` nesta etapa.

**Direção das etapas restantes:**

- Entrada inválida: `SMG_ERR_ARGUMENT`; resultado fora da faixa:
  `SMG_ERR_OVERFLOW`; falha de alocação: `SMG_ERR_NOMEM`.
- `DATE_ON_THE_FENCE` identifica ambiguidade/conflito, mantendo a mensagem
  aprovada. Status genérico sozinho não informa causa específica nem posições.
- Nas 11 extrações de componentes em série, usar status e `error_index`
  opcional conforme a assinatura aprovada acima, sem estrutura nova.
- Para futuro diagnóstico dedicado de conflito, proposta: diagnóstico fornecido pelo caller, sem estado global, contendo
  motivo e até duas posições. O Lua acrescenta operação, coluna e descrição
  limitada dos valores; índices C baseados em 0 viram posições Lua baseadas em 1.
  Layout e assinatura ainda precisam ser fechados. Não é necessário alocar
  uma mensagem no C para cada elemento.
- Saída escalar/buffer/série só publicada após sucesso. Em falha, liberar
  alocações temporárias. Nas extrações de componentes, `error_index` é
  preenchido somente em falha de elemento, conforme a regra acima; essa
  escrita não contradiz a preservação do parâmetro de resultado.
- Para as 11 extrações em série, saída aprovada `smaug_series_i64_t **out`: ponteiro
  para a variável que receberá o objeto. Em sucesso, caller assume ownership
  e libera pela função apropriada; em falha, não recebe resultado parcial.
- Detecção percorre a coluna inteira, guardando apenas evidências necessárias.
  Custo de varredura é linear no total de bytes examinados; metadados do
  diagnóstico podem ter tamanho constante. Resultado convertido ocupa O(n).

<a id="section-compatibilidade-e-validacao-da-futura-migracao"></a>

### Compatibilidade e validação da futura migração

Reusar o nome com assinatura diferente quebra compatibilidade C/FFI. Recompilar
todos os consumidores e carregar somente a biblioteca correspondente ao novo
cdef. DLL antiga com cdef novo pode não ser detectada pelo linker; planejar
identificação de ABI/artefato no trabalho do runner. Não fazer simples troca
textual de `_checked`, pois existem duas funções com o mesmo nome-base.

Testes diretamente referenciando símbolos: `tests/c/test_datetime_c.c`,
`test_astype.c`, `test_allocfail.c`, `test_ops_window.c`. Regressões Lua relevantes:
`tests/series/test_dt.lua`, `test_constructors.lua`, `test_categorical.lua`,
`test_stat.lua` e testes I/O. Conferir também chamadas indiretas pelo descritor.
Ferramentas: `scripts/parity/03_c_lua_mirror.lua`, `10_lifecycle.lua` e
`common.lua` inspecionam declarações/nomes; seus resultados não certificam ABI.

Validar primeiro casos discriminantes: ano -1 versus NA; falha preserva saída;
limites após offset; fração inexata; erro no último elemento; OOM e limpeza
parcial; ambiguidade e conflito com posições; buffer de 27 versus 28 bytes para
ano negativo; status verificado por todos os consumidores; semana ISO R02.
Depois executar suítes C/Lua e verificações de memória adequadas à mudança.

<a id="section-decisoes-restantes-em-ordem"></a>
### Integração pendente

A ordem de execução e o estado da migração estão em [R5](Roadmap.md#r5).
As assinaturas aprovadas e os consumidores acima permanecem como referência
técnica; propostas de outras famílias não são aprovadas por analogia.

## Desenvolvimento

As tabelas acima são a referência de assinaturas; não manter um segundo
catálogo abreviado. Cabeçalhos públicos estão em include/ e implementações em
src/. Compare ambos ao mudar a referência.

Consulte [compilação/testes](Build_and_Testing.md), [convenções](CODING_STYLE.md),
[contrato](CONTRACT.md), [arquitetura](ARCHITECTURE.md) e [COW](COW.md).
Sequência de trabalho e checkpoint: [roadmap](Roadmap.md#checkpoint).
