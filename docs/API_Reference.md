# Smaug — Referência da API C

Referência do contrato público do backend C. Todas as funções numéricas existem
em duas variantes, `f64` (`double`) e `i64` (`int64_t`), com estruturas e
semântica análogas. As diferenças de int64 estão na seção final.

**Status:** todas as funções abaixo estão **implementadas** para f64 e i64
(`smaug_core.c` + `smaug_ops_f64.c` + `smaug_ops_i64.c`), mais as operações
booleanas (`smaug_ops_bool.c`) e o tipo `string` Tier 1
(`smaug_str.c` + `smaug_ops_str.c`).

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
| `smaug.h` | **Umbrella** — inclui os de operação. | todos acima |

> O antigo `smaug_math.h` foi **removido** (o nome "math" não refletia o
> conteúdo). Use `smaug.h` ou o header específico. A biblioteca compilada
> permanece `libsmaug.so`/`smaug.dll` (nome do binário).

---

## Tipos

### `smaug_mask_t`

```c
typedef uint8_t smaug_mask_t;   /* 0xFF = válido, 0x00 = nulo (NA) */
```

Bitmask de 1 byte por elemento. Array paralelo aos dados.

### `smaug_metadata_t`

```c
typedef struct {
    const char *name;        /* nome da coluna, ex: "salario" */
    const char *dtype;       /* "float64", "int64" */
    bool is_view;            /* true se é uma view (não dona da memória) */
    bool external_alloc;     /* true se não deve liberar data/null_mask */
} smaug_metadata_t;
```

`name` e `dtype` são apenas identificadores — não há validação interna que os
use. Mantê-los consistentes é responsabilidade do caller.

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

---

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
- **Views não podem sobreviver à série-pai.** A view aponta para a memória da
  pai; liberar a pai antes invalida a view (use-after-free). Modificar via view
  modifica a pai. Se precisar de independência, use `clone`.

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

## Reduções

| Função | f64 retorna | i64 retorna |
|--------|-------------|-------------|
| `sum(s, ignore_na)` | `double` | `int64_t` |
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

`var`/`std` são **populacionais** (dividem por N, não N-1). Para amostral,
multiplique a variância por `N/(N-1)`. `mean` de série vazia ou só-nulos → NAN.
`min`/`max` retornam NAN (f64) ou `INT64_MIN` (i64) se nenhum elemento válido.

> ⚠️ **Sentinela ambíguo no i64.** Como `INT64_MIN` é um inteiro válido, uma
> série cujo `sum`/`min`/`max` legitimamente dê `INT64_MIN` é indistinguível do
> caso de erro. O frontend Lua deve chamar `count_nonnull()` antes (ou usar
> `ignore_na = true`) quando essa ambiguidade importar.

---

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

## Ordenação

| Função | Retorno | Notas |
|--------|---------|-------|
| `argsort(s, ascending)` | `size_t*` / NULL | índices que ordenam; **NULL se a série tem qualquer nulo** |
| `sort(s, ascending)` | série / NULL | série nova ordenada (usa `argsort` + `take`) |

Não sabem posicionar NA, então falham se houver nulos. Filtre antes (futuro
`dropna`). O `size_t*` de `argsort` é alocado — o caller libera.

---

## Utilitários

| Função | Retorno | Notas |
|--------|---------|-------|
| `count_nonnull(s)` | `size_t` | número de elementos válidos |
| `take(s, idx, len)` | série / NULL | copia elementos nas posições `idx[0..len-1]`; NULL se algum índice fora dos limites |
| `filter(s, mask)` | série / NULL | série nova só com posições onde `mask[i] != 0` |

---

## Operações Boolean (BoolSeries)

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

No frontend, a classe `BoolSeries` (`lua/smaug/core/boolseries.lua`) possui
esses arrays via `ffi.gc(ptr, free)` e expõe `:land/:lor/:lxor/:lnot`,
`:count_true/:any/:all`, e os operadores `*` (and), `+` (or), `-` (xor).
`Series:filter(bool_series)` usa os valores como máscara de `smaug_*_filter`.

---

## Strings (`smaug_str_*`)

Tipo Tier 1 completo. Representação **offset-based** (estilo Arrow): um buffer de
bytes concatenados + um array de offsets. Trata **bytes crus** — não há
normalização nem validação UTF-8 (dívida futura). Comparações e ordenação são
**lexicográficas por byte**, não Unicode-aware. A string vazia `""` é um valor
**válido e distinto de NULL**.

> **String não tem views nem Copy-on-Write** (diferente de f64/i64). Toda série
> string é dona do próprio buffer; não há detach.

### Lifecycle

| Função | Retorno | Notas |
|--------|---------|-------|
| `create(size)` | série / NULL | todos os elementos nascem NULL |
| `create_with_capacity(size, buffer_capacity)` | série / NULL | pré-aloca o buffer de bytes para `set`/`append` |
| `create_from_array(array, len)` | série / NULL | `array` é `const char *const *`; entrada `NULL` no array → posição NULL |
| `free(s)` | void | idempotente (`NULL` seguro); respeita `external_alloc` |
| `clone(s)` | série / NULL | deep copy independente |

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
> `f64_set`/`i64_set`. Como string não tem views, o `SMG_ERR_NOMEM` vem da
> realocação do buffer de bytes, não de detach COW.

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

## Diferenças do int64 (`i64`)

A API i64 é idêntica em forma à f64, trocando `double` por `int64_t`. Diferenças
semânticas:

- `sum`, `min`, `max` retornam `int64_t` (não `double`). Com `ignore_na=false`
  e algum nulo — ou série vazia/só-nulos — retornam **`INT64_MIN`** como
  sentinela (ver aviso de ambiguidade na seção Reduções).
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

## Gerenciamento de memória — resumo

| Operação | Quem aloca | Responsabilidade do caller |
|----------|-----------|----------------------------|
| `create`, `clone`, `create_from_array` | Smaug | chamar `free` |
| `add`/`sub`/`mul`/`div`, `*_scalar`, `sort`, `take`, `filter` | Smaug | `free` o resultado |
| `view` | Smaug | **não** liberar enquanto a série-pai existir |
| `gt`/`lt`/`eq` | Smaug | `free` no array `uint8_t*` (e no `out_mask`) |
| `argsort` | Smaug | `free` no `size_t*` |
| `smaug_bool_*` (and/or/xor/not) | Smaug | `free` no array `uint8_t*` (e no `out_mask`) |

No frontend Lua, use `ffi.gc(ptr, C.smaug_f64_free)` para automatizar a limpeza
dos structs de série.

---

## Problemas conhecidos

1. ~~**`f64_grow` / `i64_grow` em falha parcial de realloc.**~~ **RESOLVIDO.**
   Antes, se o `realloc` do `data` tinha sucesso mas o do `null_mask` falhava,
   `s->data` era atualizado mas `s->capacity` não — série inconsistente. Agora,
   em falha do `null_mask`, o `data` é encolhido de volta para o `capacity`
   antigo, preservando o invariante (ambos os buffers sempre com `capacity`
   elementos). Coberto por `tests/test_alloc.c`.

2. **Convenção de `0xFF`/`0x00` vs `1`/`0`.** As máscaras de null usam
   `0xFF`/`0x00`, mas `gt`/`lt`/`eq` devolvem `1`/`0` no array booleano.
   `filter` checa `if (mask[i])`, então funciona, mas é uma inconsistência de
   convenção — documentar ou unificar.

3. **`alloc_result` em `smaug_ops_f64.c` usa `extern` para declarar
   `smaug_f64_create`** em vez de só incluir o header. Funciona, mas o ideal é
   confiar no include.

4. **`memset(s->data, 0.0, ...)`** (caso aparecer em algum reimplemento): o
   `0.0` vira `int(0)`; correto em IEEE 754, mas gera warning com `-Wall`. Use
   `memset(s->data, 0, ...)`.

---

## Anel 3 — I/O (`smaug_io.h`)

Parsers CSV e JSON escritos do zero, zero dependências externas.
Fronteira `smaug_table_t` entre leitores e o frontend Lua.

### `smaug_table_t` — struct intermediária

```c
typedef struct {
    const char          *name;     /* nome da coluna */
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

### CSV

```c
smaug_csv_opts_t smaug_csv_default_opts(void);
/* sep=',', header=1, quote='"', na={"","NA","null","N/A","nan","NaN","NULL"} */

smaug_table_t* smaug_read_csv(const char *path, const smaug_csv_opts_t *opts);
smaug_table_t* smaug_read_csv_mem(const char *buf, size_t len,
                                   const smaug_csv_opts_t *opts);

smaug_csv_write_opts_t smaug_csv_write_default_opts(void);
int   smaug_write_csv(const char *path, const smaug_table_t *t,
                      const smaug_csv_write_opts_t *opts);
char* smaug_write_csv_mem(const smaug_table_t *t,
                           const smaug_csv_write_opts_t *opts, size_t *out_len);
/* buffer retornado terminado em \0; liberar com smaug_free */
```

**Inferência de tipo:** cada coluna testada em ordem `bool → int64 → float64 → string`.
Coluna mista sobe para o tipo mais abrangente. Coluna toda NA → string.

**RFC 4180:** aspas duplas suportadas (`"campo com, vírgula"`, `""aspas""` → `"`).

### JSON

```c
smaug_table_t* smaug_read_json(const char *path);
smaug_table_t* smaug_read_json_mem(const char *buf, size_t len);
/* Formato: array de records [ {...}, {...} ] */

int   smaug_write_json(const char *path, const smaug_table_t *t,
                       const smaug_json_write_opts_t *opts);
char* smaug_write_json_mem(const smaug_table_t *t,
                            const smaug_json_write_opts_t *opts, size_t *out_len);
/* NaN → null no JSON. Escapes: \n \t \\ \" \uXXXX para controles. */
```

### Ciclo de vida

```c
void smaug_table_free(smaug_table_t *t);   /* NULL-safe */
```

Propriedade: `smaug_table_t*` possui seus recursos. O frontend Lua chama
`smaug_table_free` após consumir a tabela e construir o `DataSet`.

---

## Anel 0 — Datetime (`smaug_datetime.h`)

Dtype Tier 2 implementado em C puro. Armazenamento: `int64_t` representando
**epoch em milissegundos UTC**. Calendário Gregoriano proléptico, sem
dependência de timezone (UTC no armazenamento, apresentação local é do caller).

Mesmos contratos defensivos dos outros dtypes: `smaug_status_t` em `get`/`set`,
null por bitmask, COW em views.

### Lifecycle

```c
smaug_series_dt_t* smaug_dt_create(size_t size);
smaug_series_dt_t* smaug_dt_create_with_capacity(size_t size, size_t capacity);
smaug_series_dt_t* smaug_dt_create_from_array(const int64_t *array, size_t len);
void               smaug_dt_free(smaug_series_dt_t *s);                  /* NULL-safe */
smaug_series_dt_t* smaug_dt_clone(const smaug_series_dt_t *s);
smaug_series_dt_t* smaug_dt_view(smaug_series_dt_t *s, size_t start, size_t len);
```

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

### Parsing / formatação ISO 8601

```c
int smaug_dt_parse(const char *str, size_t len, int64_t *epoch_ms);
/* Aceita: "YYYY-MM-DD", "YYYY-MM-DDTHH:MM:SS[.mmm][Z|±HH:MM]". */
/* Retorna 0 em sucesso, -1 em formato inválido. epoch_ms escrito só em sucesso. */

int smaug_dt_format(int64_t epoch_ms, char *buf, size_t buf_size);
/* Formato fixo: "YYYY-MM-DDTHH:MM:SS.mmmZ" (25 chars + \0). Buf >= 26. */
```

### Extração de componentes (operam em epoch_ms escalar; retornam -1 em erro)

```c
int smaug_dt_year   (int64_t epoch_ms);   int smaug_dt_month  (int64_t epoch_ms);
int smaug_dt_day    (int64_t epoch_ms);   int smaug_dt_hour   (int64_t epoch_ms);
int smaug_dt_minute (int64_t epoch_ms);   int smaug_dt_second (int64_t epoch_ms);
int smaug_dt_ms     (int64_t epoch_ms);   int smaug_dt_weekday(int64_t epoch_ms);
int smaug_dt_yearday(int64_t epoch_ms);   int smaug_dt_quarter(int64_t epoch_ms);
int smaug_dt_week   (int64_t epoch_ms);   /* ISO 8601 (semana 1 = primeira com >= 4 dias) */
```

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
