# Referência da API — Núcleo C

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

<details>
<summary>Nesta página</summary>

- [Mapa de headers (qual #include usar)](#section-mapa-de-headers-qual-include-usar)
- [Tipos](#section-tipos)
  - [smaug_mask_t](#section--smaug-mask-t)
  - [smaug_metadata_t](#section--smaug-metadata-t)
  - [smaug_series_f64_t / smaug_series_i64_t](#section--smaug-series-f64-t-smaug-series-i64-t)
- [Lifecycle](#section-lifecycle)
- [Getters / Setters](#section-getters-setters)
- [Append dinâmico](#section-append-dinamico)
- [Aritméticas](#section-aritmeticas)
- [Reduções](#section-reducoes)
- [Comparações](#section-comparacoes)
- [Ordenação](#section-ordenacao)
- [Utilitários](#section-utilitarios)
- [Operações Boolean (BoolSeries)](#section-operacoes-boolean-boolseries)
- [Strings (smaug_str_*)](#section-strings-smaug-str)
  - [Lifecycle](#section-lifecycle-1)
  - [Acesso e mutação](#section-acesso-e-mutacao)
  - [Comparações](#section-comparacoes-1)
  - [Filtro e ordenação](#section-filtro-e-ordenacao)
- [Diferenças do int64 (i64)](#section-diferencas-do-int64-i64)
- [Views e Copy-on-Write](#section-views-e-copy-on-write)
- [Gerenciamento de memória — resumo](#section-gerenciamento-de-memoria-resumo)
- [Problemas conhecidos](#section-problemas-conhecidos)
- [Anel 3 — I/O (smaug_io.h)](#section-anel-3-i-o-smaug-io-h)
  - [smaug_table_t — struct intermediária](#section--smaug-table-t-struct-intermediaria)
  - [CSV](#section-csv)
  - [JSON](#section-json)
  - [Ciclo de vida](#section-ciclo-de-vida)
- [Anel 0 — Datetime (smaug_datetime.h)](#section-anel-0-datetime-smaug-datetime-h)
  - [Lifecycle](#section-lifecycle-2)
  - [Acesso](#section-acesso)
  - [Parsing / formatação ISO 8601](#section-parsing-formatacao-iso-8601)
  - [Extração de componentes (operam em epoch_ms escalar; retornam -1 em erro)](#section-extracao-de-componentes-operam-em-epoch-ms-escalar-retornam-1-em-erro)
  - [Construção e aritmética](#section-construcao-e-aritmetica)
  - [Comparações, ordenação e seleção](#section-comparacoes-ordenacao-e-selecao)
- [Datetime — evolução da API C](#section-datetime-migracao-c)
  - [Decisão fechada e alcance](#section-decisao-fechada-e-alcance)
  - [Núcleo de calendário: assinaturas e mudanças](#section-nucleo-de-calendario-assinaturas-e-mudancas)
  - [Outras entradas e operações datetime](#section-outras-entradas-e-operacoes-datetime)
  - [Consumidores C e fronteira FFI](#section-consumidores-a-migrar)
  - [Diagnóstico, status e memória](#section-diagnostico-status-e-memoria)
  - [Compatibilidade e validação da futura migração](#section-compatibilidade-e-validacao-da-futura-migracao)
  - [Decisões restantes, em ordem](#section-decisoes-restantes-em-ordem)
- [Catálogo rápido de funções C](#section-camada-c-backend-include-h-src-c)
  - [Lifecycle e acesso (smaug_core.h)](#section-lifecycle-e-acesso-smaug-core-h)
  - [Aritmética (smaug_numeric.h)](#section-aritmetica-smaug-numeric-h)
  - [Reduções (smaug_numeric.h)](#section-reducoes-smaug-numeric-h)
  - [Comparações e ordenação (smaug_numeric.h)](#section-comparacoes-e-ordenacao-smaug-numeric-h)
  - [Booleano / Kleene (smaug_bool.h)](#section-booleano-kleene-smaug-bool-h)
  - [String (smaug_string.h)](#section-string-smaug-string-h)
  - [I/O — Anel 3 (smaug_io.h)](#section-i-o-anel-3-smaug-io-h)
  - [Tipos (smaug_types.h)](#section-tipos-smaug-types-h)
- [Desenvolvimento do núcleo C](#section-desenvolvimento-do-nucleo-c)
  - [Contribuir com o projeto](#section-contribuir-com-o-projeto)
  - [Preparar o ambiente](#section-preparar-o-ambiente)
  - [Contribuir com o código](#section-contribuir-com-o-codigo)
  - [Internals e memória](#section-internals-e-memoria)
  - [Testes e investigação de regressões](#section-testes-e-investigacao-de-regressoes)
  - [Contribuir com a documentação](#section-contribuir-com-a-documentacao)
  - [Manutenção e versões](#section-manutencao-e-versoes)

</details>

Referência do contrato público do backend C. Todas as funções numéricas existem
em duas variantes, `f64` (`double`) e `i64` (`int64_t`), com estruturas e
semântica análogas. As diferenças de int64 estão na seção final.

**Status:** todas as funções abaixo estão **implementadas** para f64 e i64
(`smaug_core.c` + `smaug_ops_f64.c` + `smaug_ops_i64.c`), mais as operações
booleanas (`smaug_ops_bool.c`) e o tipo `string` Tier 1
(`smaug_str.c` + `smaug_ops_str.c`).

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
| `smaug.h` | **Umbrella** — inclui os de operação. | todos acima |

> O antigo `smaug_math.h` foi **removido** (o nome "math" não refletia o
> conteúdo). Use `smaug.h` ou o header específico. A biblioteca compilada
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
    const char *dtype;       /* "float64", "int64" */
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

<a id="section-reducoes"></a>

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

`var`/`std` são **amostrais** (ddof=1: dividem por N-1). Para n<2 retornam NaN
(variância amostral indefinida). Coerente com `cov`/`skew`/`kurtosis` e com o
`groupby`. `mean` de série vazia ou só-nulos → NAN.
`min`/`max` retornam NAN (f64) ou `INT64_MIN` (i64) se nenhum elemento válido.

> ⚠️ **Sentinela ambíguo no i64.** Como `INT64_MIN` é um inteiro válido, uma
> série cujo `sum`/`min`/`max` legitimamente dê `INT64_MIN` é indistinguível do
> caso de erro. O frontend Lua deve chamar `count_nonnull()` antes (ou usar
> `ignore_na = true`) quando essa ambiguidade importar.

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

Não sabem posicionar NA, então falham se houver nulos. Filtre antes (futuro
`dropna`). O `size_t*` de `argsort` é alocado — o caller libera.

---

<a id="section-utilitarios"></a>

## Utilitários

| Função | Retorno | Notas |
|--------|---------|-------|
| `count_nonnull(s)` | `size_t` | número de elementos válidos |
| `take(s, idx, len)` | série / NULL | copia elementos nas posições `idx[0..len-1]`; NULL se algum índice fora dos limites |
| `filter(s, mask)` | série / NULL | série nova só com posições onde `mask[i] != 0` |

---

<a id="section-operacoes-boolean-boolseries"></a>

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
| `create`, `clone`, `create_from_array` | Smaug | chamar `free` |
| `add`/`sub`/`mul`/`div`, `*_scalar`, `sort`, `take`, `filter` | Smaug | `free` o resultado |
| `view` | Smaug | **não** liberar enquanto a série-pai existir |
| `gt`/`lt`/`eq` | Smaug | `free` no array `uint8_t*` (e no `out_mask`) |
| `argsort` | Smaug | `free` no `size_t*` |
| `smaug_bool_*` (and/or/xor/not) | Smaug | `free` no array `uint8_t*` (e no `out_mask`) |

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

<a id="section-anel-3-i-o-smaug-io-h"></a>

## Anel 3 — I/O (`smaug_io.h`)

Parsers CSV e JSON escritos do zero, zero dependências externas.
Fronteira `smaug_table_t` entre leitores e o frontend Lua.

<a id="section--smaug-table-t-struct-intermediaria"></a>

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

<a id="section-csv"></a>

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

<a id="section-json"></a>

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

Dtype Tier 2 implementado em C puro. Armazenamento: `int64_t` representando
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
int smaug_dt_parse(const char *str, size_t len, int64_t *epoch_ms);
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

### Decisões restantes, em ordem

1. Fechar a integração de `dayfirst` nas demais entradas Lua e seu transporte ao C.
   `astype` textual estrito já usa status/saída/primeira posição inválida desde
   2026-09-25, conforme a seção de diagnóstico. A API inicial
   reconhece os separadores aprovados sem argumento de formato explícito;
   essa opção fica para ampliação futura.
   Prioridade de interpretação, padrão mês/dia e formatos iniciais estão
   aprovados no contrato.
   Assinatura,
   regra de escrita e correspondência dos status de `error_index` estão
   aprovadas para as 11 extrações de componentes em série.
2. Fechar a representação C de ordem automática/DMY/MDY. Opções e helpers
   públicos são definidos na [referência Lua](API_INDEX.md#section-datetime-migracao-lua).
3. Consolidar aliases antigos de aritmética/construção, buffer público e
   domínio de intermediários de parse/round/ceil.
4. Só então implementar por família com regressões, antes dos demais tópicos
   contratuais da reconstrução da suíte. Esta migração não encerra lifetime,
   overflow de outras operações nem revisão geral do núcleo.


<a id="section-camada-c-backend-include-h-src-c"></a>

## Catálogo rápido de funções C

> Convenção: `<t>` = `f64` ou `i64`. Índices em C são 0-based; no Lua, 1-based.

> **Contrato de status (`smaug_types.h`):** `smaug_status_t` =
> `SMG_OK (0)` / `SMG_NULL_VALUE` / `SMG_ERR_OOB` / `SMG_ERR_ARGUMENT` /
> `SMG_ERR_NOMEM` / `SMG_ERR_OVERFLOW`. O engine valida e comunica — não confia que o caller validou.


<a id="section-lifecycle-e-acesso-smaug-core-h"></a>

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

<a id="section-aritmetica-smaug-numeric-h"></a>

### Aritmética (`smaug_numeric.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_<t>_add/sub/mul/div(a, b)` | aritmética série×série (propaga NA) |
| `smaug_<t>_add/sub/mul/div_scalar(a, k)` | aritmética série×escalar |

`div/0 → null` em f64 e i64. `NaN` só existe como valor presente em f64.

<a id="section-reducoes-smaug-numeric-h"></a>

### Reduções (`smaug_numeric.h`)

| Função | Retorno |
|--------|---------|
| `smaug_<t>_sum(s, ignore_na)` | f64→double, i64→int64 |
| `smaug_<t>_mean(s, ignore_na)` | double |
| `smaug_<t>_min/max(s, ignore_na)` | f64→double, i64→int64, dt→int64 (epoch), bool→uint8+status, str→ptr+len |
| `smaug_<t>_var/std(s, ignore_na)` | double, amostral (÷ N-1; <2 → NaN) |
| `smaug_<t>_count_nonnull(s)` | size_t |

<a id="section-comparacoes-e-ordenacao-smaug-numeric-h"></a>

### Comparações e ordenação (`smaug_numeric.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_<t>_gt/lt/eq/ge/le/ne(s, k, &out_mask)` | → bool array (uint8_t*); liberar c/ `smaug_free` |
| `smaug_<t>_argsort(s, asc)` | → size_t* (permutação); NULL se há nulos |
| `smaug_<t>_sort(s, asc)` | → nova série ordenada; NULL se há nulos |
| `smaug_<t>_take(s, idx, len)` | → nova série com os índices dados |
| `smaug_<t>_filter(s, mask)` | → nova série onde mask é true |

<a id="section-booleano-kleene-smaug-bool-h"></a>

### Booleano / Kleene (`smaug_bool.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_bool_and/or/xor(a, am, b, bm, n, &out)` | lógica de 3 valores |
| `smaug_bool_not(a, am, n, &out)` | negação Kleene |
| `smaug_bool_count_true(a, am, n)` | conta trues (NA ignorado) |
| `smaug_bool_eq/ne(s, threshold, &out_mask)` | comparação com escalar → máscara (NA preservado) |
| `smaug_bool_any/all(a, am, n)` | agregações (NA ignorado) |

<a id="section-string-smaug-string-h"></a>

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

<a id="section-i-o-anel-3-smaug-io-h"></a>

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

<a id="section-tipos-smaug-types-h"></a>

### Tipos (`smaug_types.h`)

`smaug_mask_t`, `smaug_metadata_t`, `smaug_series_f64_t`, `smaug_series_i64_t`,
`smaug_series_bool_t`, `smaug_series_str_t`, `smaug_column_t`, `smaug_table_t`.

---

<a id="section-desenvolvimento-do-nucleo-c"></a>

## Desenvolvimento do núcleo C

<a id="section-contribuir-com-o-projeto"></a>

### Contribuir com o projeto

Antes de alterar uma API C, consulte o [catálogo do núcleo](#section-camada-c-backend-include-h-src-c), o
[contrato](CONTRACT.md) e o [roadmap](Roadmap.md). Uma proposta deve distinguir
comportamento atual, decisão aprovada e implementação validada.

<a id="section-preparar-o-ambiente"></a>

### Preparar o ambiente

Siga [Compilação e testes](Build_and_Testing.md) para GCC, LuaJIT, Linux e
Windows. Os comandos partem da raiz do repositório.

<a id="section-contribuir-com-o-codigo"></a>

### Contribuir com o código

As [convenções de escrita](CODING_STYLE.md) definem nomes, chamadas e testes.
A [arquitetura](ARCHITECTURE.md) define as responsabilidades das camadas.
A [referência C](API_Reference.md) detalha os contratos de uso do núcleo.

<a id="section-internals-e-memoria"></a>

### Internals e memória

Leia [Arquitetura](ARCHITECTURE.md), [Contrato](CONTRACT.md) e
[Copy-on-Write](COW.md) antes de alterar ownership, views ou falhas de alocação.
Mudanças de assinatura precisam atualizar header, implementação, FFI e todos
os consumidores; a [migração datetime](#section-datetime-migracao-c) detalha esse trabalho.

<a id="section-testes-e-investigacao-de-regressoes"></a>

### Testes e investigação de regressões

[Compilação e testes](Build_and_Testing.md) descreve como executar as ferramentas.
O [rework da suíte](TEST_SUITE_REWORK.md) concentra o ponto de parada atual.
O [parecer](TEST_SUITE_REWRITE_REVIEW.md) documenta defeitos e critérios de
encerramento; o [inventário de exclusões](TEST_SUITE_EXCLUSIONS_REVIEW.md)
rastreia justificativas de cobertura.

<a id="section-contribuir-com-a-documentacao"></a>

### Contribuir com a documentação

A navegação segue [primeiros passos](GETTING_STARTED.md),
[guia por temas](USER_GUIDE.md), [referência Lua](API_INDEX.md) e [Núcleo C](API_Reference.md),
como na [documentação do pandas](https://pandas.pydata.org/docs/development/index.html).
Os arquivos permanecem planos em `docs/`.

| Informação | Lugar |
|---|---|
| Introdução e primeiro exemplo | Primeiros passos |
| Explicação de um assunto e caminho de leitura | Guia do usuário |
| Método, assinatura e parâmetros | Referência da API |
| Garantia normativa e decisão aprovada | Contrato; COW para memória compartilhada |
| Proposta técnica ainda aberta | Seção do assunto na referência Lua ou C correspondente |
| Defeito observado e evidência | Parecer e inventário |
| Ponto de parada | Rework da suíte |
| Planejamento e histórico | Roadmap e changelog |

Atualize a fonte responsável e adicione links nos guias. Conteúdo Lua pertence
à referência Lua; conteúdo C pertence à referência C. Não criar mapas ou arquivos
paralelos por funcionalidade nem replicar decisões em notas de sessão. Cada documento tem navegação principal e sumário local;
ao mudar uma seção, confira seus links e âncoras.

`COVERAGE.md`, `PARITY_REPORT.md` e `MANIFEST.txt` são artefatos gerados:
não editar manualmente nem reorganizar seus conteúdos. Devem refletir a
execução que os produziu. Eles não foram regenerados nesta reorganização.

<a id="section-manutencao-e-versoes"></a>

### Manutenção e versões

O [roadmap](Roadmap.md) registra entregas e critérios para v1.0.
O [changelog](CHANGELOG.md) preserva o histórico, inclusive decisões superadas.
O contrato e as decisões atuais têm precedência sobre relatos históricos.


---

[Referência do Núcleo C](API_Reference.md) · [Rework da suíte](TEST_SUITE_REWORK.md) · [Início da documentação](README.md)
