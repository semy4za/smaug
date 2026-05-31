# Smaug — Referência da API C

Referência do contrato público definido em `include/smaug_math.h`. Todas as
funções existem em duas variantes, `f64` (`double`) e `i64` (`int64_t`), com
estruturas e semântica análogas. As diferenças de int64 estão na seção final.

**Status:** todas as funções abaixo estão **implementadas** para f64 e i64
(`smaug_core.c` + `smaug_ops_f64.c` + `smaug_ops_i64.c`), mais as operações
booleanas (`smaug_ops_bool.c`).

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
| `get(s, idx)` | `double` | valor se válido; **NAN se nulo ou fora dos limites** (f64) |
| `set(s, idx, val)` | void | grava `val`, marca **válido**; sem efeito se `idx >= size` |
| `set_null(s, idx)` | void | marca **nulo** e zera o dado; sem efeito se fora dos limites |
| `is_null(s, idx)` | `bool` | `true` se nulo (ou fora dos limites) |

`set` sempre marca como válido — mesmo com `val == NAN`. Para marcar nulo, use
`set_null`. Ou seja, *NaN não é o mesmo que NA*: um `set(NAN)` produz um valor
válido cujo conteúdo é NaN, enquanto `set_null` marca a posição como ausente.

---

## Append dinâmico

| Função | Retorno | Notas |
|--------|---------|-------|
| `append(s, val)` | `0` ok / `-1` erro | adiciona ao fim, marca válido |
| `append_null(s)` | `0` ok / `-1` erro | adiciona posição nula |

Grow strategy: quando `size >= capacity`, a capacidade cresce **1.5×**
(`capacity + capacity/2`), com guarda de overflow. Capacidade vazia cresce para
4. Append em uma **view** falha (`-1`): views são read-only.

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
free(mask);
free(out);
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
  máscara do resultado). **O caller libera ambos** com `free()`.
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
