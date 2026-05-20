# 🐉 Smaug: Documentação Técnica Completa e Referência
## Biblioteca de Análise de Dados em Lua com Backend em C

**Versão:** 1.1 (Pré-desenvolvimento - Referência)  
**Data:** 2026-05-18  
**Status:** PHASE 1 (Setup + Core structures)

---

## 📋 Índice

1. [Visão Geral](#1-visão-geral)
2. [Referência de Estruturas](#2-referência-de-estruturas)
3. [Referência de Funções - Float64](#3-referência-de-funções---float64)
4. [Referência de Funções - Int64](#4-referência-de-funções---int64)
5. [Arquitetura Detalhada](#5-arquitetura-detalhada)
6. [Implementação - Padrões e Exemplos](#6-implementação--padrões-e-exemplos)
7. [Gerenciamento de Memória](#7-gerenciamento-de-memória)
8. [Null Handling (Bitmasks)](#8-null-handling-bitmasks)
9. [Roadmap Faseado](#9-roadmap-faseado)
10. [Troubleshooting e Casos Edge](#10-troubleshooting-e-casos-edge)

---

## 1. Visão Geral

### 1.1 Propósito

**Smaug** é uma biblioteca de análise de dados que traz as funcionalidades do **Pandas** (Python) para o **Lua**, com performance comparable ao **NumPy** via backend em C otimizado.

**Por quê?**
- Python+Pandas é pesado para edge computing, game engines, IoT
- Lua é leve (~400KB) e tem LuaJIT com FFI nativo (zero-copy)
- Resultado: Lua frontend + C backend = melhor dos dois mundos

### 1.2 Stack Tecnológico

| Camada | Tecnologia | Responsabilidade |
|--------|-----------|------------------|
| **Frontend** | Lua 5.1 + LuaJIT | Classes Series/DataSet, API expressiva, metamétodos |
| **Bridge** | LuaJIT FFI | Zero-copy data passing, native function calls |
| **Backend** | C11 | Operações numéricas, malloc/free, SIMD-friendly |
| **Build** | CMake 3.10+ | Portabilidade (Linux/macOS/Windows) |

### 1.3 Requisitos Não-Funcionais

| Aspecto | Alvo | Justificativa |
|---------|------|---------------|
| **Memory Footprint** | < 2MB compilado | Embarcabilidade |
| **Startup Time** | < 100ms | Scripting interativo |
| **Performance** | ≥ 80% NumPy | Operações numéricas grandes |
| **Type Safety** | Zero segfaults | Validação em hot paths |
| **API Compatibility** | 90% Pandas | Curva de aprendizado baixa |

---

## 2. Referência de Estruturas

### 2.1 `smaug_mask_t`

```c
typedef uint8_t smaug_mask_t;
```

**Propósito:** Bitmask simples para marcar valores nulos em arrays.

**Convenção:**
- `0xFF` (255): valor **válido**
- `0x00` (0): valor **nulo (NA)**

**Por quê uint8_t e não bit-packing?**
- Cache-friendly (8 bytes por valor)
- Sem complexidade bitwise
- Trade-off: +8x RAM vs +10x velocidade (aceitável)

**Exemplo:**
```c
smaug_series_f64_t *s = smaug_f64_create(5);
// s->null_mask inicialmente: [0x00, 0x00, 0x00, 0x00, 0x00] (todos nulos)

smaug_f64_set(s, 0, 42.0);
// Após set: s->null_mask[0] = 0xFF (agora válido)
// Após set: s->null_mask[1..4] = 0x00 (ainda nulos)
```

---

### 2.2 `smaug_metadata_t`

```c
typedef struct {
    const char *name;       /* Nome da coluna (ex: "salario") */
    const char *dtype;      /* Tipo como string (ex: "float64") */
    bool is_view;           /* True se é uma view (não owner de memória) */
    bool external_alloc;    /* True se alocado fora (não chamar free) */
} smaug_metadata_t;
```

**Propósito:** Metadados sobre uma série.

**Campos:**

| Campo | Tipo | Propósito | Exemplo |
|-------|------|----------|---------|
| `name` | `const char*` | Identificador da coluna | `"salario"`, `"idade"` |
| `dtype` | `const char*` | Tipo de dados como string | `"float64"`, `"int64"` |
| `is_view` | `bool` | Se é uma view (slice sem cópia) | `false` (cópia), `true` (view) |
| `external_alloc` | `bool` | Se malloc foi externo | `false` (Smaug), `true` (user) |

**Casos de uso:**

```c
/* Caso 1: Series normal (owner) */
smaug_series_f64_t *s = smaug_f64_create(100);
// s->meta.is_view = false
// s->meta.external_alloc = false
// smaug_f64_free() irá liberar data + null_mask

/* Caso 2: View (não copia memória) */
smaug_series_f64_t *view = smaug_f64_view(s, 10, 50);
// view->meta.is_view = true
// view não aloca memória própria, apenas aponta para s->data[10..59]
// NÃO chamar smaug_f64_free(view) enquanto s existe!

/* Caso 3: Memória externa */
double *external_data = malloc(100 * sizeof(double));
// ... preencher external_data ...
// Então: criar struct que aponta para ela
// s->meta.external_alloc = true
// smaug_f64_free() não vai chamar free(s->data)
```

**Notas Críticas:**
- `name` é apenas identificador, não é usado internamente
- `dtype` deve ser mantido consistente com operações (não há validação!)
- Views **não devem outlive** sua série original

---

### 2.3 `smaug_series_f64_t`

```c
typedef struct {
    double *data;              /* Array contíguo de double */
    smaug_mask_t *null_mask;   /* Array paralelo: 0xFF=válido, 0x00=NA */
    size_t size;               /* Elementos preenchidos */
    size_t capacity;           /* Elementos alocados */
    smaug_metadata_t meta;     /* Metadados */
} smaug_series_f64_t;
```

**Propósito:** Representa uma série 1D de números double (float64).

**Layout de Memória:**
```
Memória:
┌──────────────────────────────────┐
│ smaug_series_f64_t (struct)      │
│  ├─ data* ─────────────────────┐ │
│  ├─ null_mask* ──────────────┐ │ │
│  ├─ size: 100               │ │ │
│  ├─ capacity: 128           │ │ │
│  └─ meta {...}              │ │ │
└─────────────────────────────│─│─┘
                              │ │
        Heap Memory           │ │
    ┌──────────────────────────┘ │
    │                             │
    ├─ data[0..127]: double      │
    │  [10.5, 20.3, ..., ?, ?]   │
    │  (últimos 28 são não inicializados)
    │
    └─ null_mask[0..127]: uint8_t
       [0xFF, 0xFF, ..., 0x00, 0x00]
```

**Invariantes:**
- `size <= capacity` (sempre!)
- `data` e `null_mask` têm **mesmo tamanho** (`capacity`)
- `data[size..capacity-1]` é não-inicializado (garbage)
- `null_mask[size..capacity-1]` é não-inicializado

**Exemplo de criação:**
```c
/* Criar série com 10 elementos */
smaug_series_f64_t *s = smaug_f64_create(10);
// Resultado: size=10, capacity=10, data/mask alocados

/* Criar com capacidade extra (para append) */
smaug_series_f64_t *s = smaug_f64_create_with_capacity(10, 20);
// Resultado: size=10, capacity=20
// Pode fazer 10 appends antes de realloc

/* Criar a partir de array existente */
double arr[] = {1.0, 2.0, 3.0};
smaug_series_f64_t *s = smaug_f64_create_from_array(arr, 3);
// Cria série com 3 elementos copiados de arr
```

---

### 2.4 `smaug_series_i64_t`

```c
typedef struct {
    int64_t *data;             /* Array contíguo de int64_t */
    smaug_mask_t *null_mask;   /* Array paralelo: 0xFF=válido, 0x00=NA */
    size_t size;               /* Elementos preenchidos */
    size_t capacity;           /* Elementos alocados */
    smaug_metadata_t meta;     /* Metadados */
} smaug_series_i64_t;
```

**Propósito:** Representa uma série 1D de inteiros 64-bit.

**Diferenças de f64:**
- `data` é `int64_t*`, não `double*`
- Operações retornam `int64_t`, não `double` (exceto mean/std/var que retornam `double`)
- Mesmo layout e invariantes que f64

**Por que int64_t?**
- Lua usa números como `double` nativamente, mas suporta até 2^53 inteiros sem perda de precisão
- int64_t cabe no range de Lua double sem perda
- Melhor para contadores, IDs, índices

---

## 3. Referência de Funções - Float64

### 3.1 Alocação e Destruição

#### `smaug_series_f64_t* smaug_f64_create(size_t size)`

```c
smaug_series_f64_t* smaug_f64_create(100);
```

**Propósito:** Criar série nova com tamanho exato.

**Parâmetros:**
- `size`: número de elementos iniciais

**Retorna:**
- Ponteiro para `smaug_series_f64_t` alocado via malloc
- **NULL se allocation falhar**

**Inicialização:**
- `data` alocado, conteúdo é garbage
- `null_mask` alocado, **todos bytes = 0x00** (tudo nulo por padrão)
- `size = capacity = size`

**Casos Edge:**
```c
smaug_f64_create(0);      // OK: size=0, capacity=0, ptrs podem ser NULL
smaug_f64_create(1000000); // OK: aloca 8MB + 1MB (data + mask)
smaug_f64_create(-1);     // Comportamento indefinido (size_t é unsigned!)
```

**Memory:**
- Aloca: `sizeof(smaug_series_f64_t) + size*sizeof(double) + size*sizeof(uint8_t)`
- Típico: ~8 bytes struct + 8*size + 1*size = **~9*size bytes**

**Caller responsibilities:**
- Verificar retorno NULL
- Chamar `smaug_f64_free()` quando done
- Não acessar `data[size..capacity-1]` (garbage!)

---

#### `smaug_series_f64_t* smaug_f64_create_with_capacity(size_t size, size_t capacity)`

```c
smaug_series_f64_t* s = smaug_f64_create_with_capacity(10, 100);
// Cria série com 10 elementos, mas 100 alocados
// Pode fazer 90 appends antes de realloc
```

**Propósito:** Criar série com capacidade extra (otimização para append).

**Parâmetros:**
- `size`: elementos iniciais
- `capacity`: elementos alocados

**Validação:**
- Se `size > capacity`: **retorna NULL**

**Típico para:**
- Builder pattern (append iterativo)
- Pre-alocação sabendo tamanho futuro

---

#### `smaug_series_f64_t* smaug_f64_create_from_array(const double *array, size_t len)`

```c
double data[] = {1.5, 2.7, 3.9};
smaug_series_f64_t *s = smaug_f64_create_from_array(data, 3);
// Cria série, copia os 3 valores de data[]
// Resultado: s->data = [1.5, 2.7, 3.9], null_mask = [0xFF, 0xFF, 0xFF]
```

**Propósito:** Criar série e popular a partir de array C.

**Parâmetros:**
- `array`: ponteiro para dados (const, não modificado)
- `len`: número de elementos a copiar

**Comportamento:**
- Aloca nova série com `size=capacity=len`
- **Copia** elementos de `array` para `s->data`
- Marca todos como válidos (`null_mask[i] = 0xFF`)

**Casos Edge:**
```c
smaug_f64_create_from_array(NULL, 10);  // Undefined behavior (null ptr)
smaug_f64_create_from_array(arr, 0);    // OK: cria série vazia
```

---

#### `void smaug_f64_free(smaug_series_f64_t *s)`

```c
smaug_f64_free(s);  // Libera memória
s = NULL;           // Boa prática (evita use-after-free)
```

**Propósito:** Liberar série e seus dados.

**Comportamento:**
- Se `s == NULL`: **não faz nada** (idempotent, safe)
- Se `s->meta.external_alloc == false`: libera `data` e `null_mask`
- Se `s->meta.external_alloc == true`: **não libera** (dados são do usuário)
- Sempre libera o struct `s` próprio

**Crítico:**
- Views **não devem ser liberadas** enquanto série original existe
- Views têm `external_alloc=true` por isso
- Tentar liberar view causa **double-free se série original também for liberada**

---

#### `smaug_series_f64_t* smaug_f64_clone(const smaug_series_f64_t *s)`

```c
smaug_series_f64_t *original = smaug_f64_create(100);
// ... preencher original ...
smaug_series_f64_t *cópia = smaug_f64_clone(original);
// cópia tem mesmos dados + null_mask que original
// mas é independente (free um não afeta o outro)
```

**Propósito:** Fazer deep copy da série.

**Comportamento:**
- Aloca série nova
- **Copia** `data` e `null_mask` de original
- Copia `meta` (incluindo flags)
- Clone é **100% independente**

**Memory:**
- Aloca 2x a memória de original

---

#### `smaug_series_f64_t* smaug_f64_view(smaug_series_f64_t *s, size_t start, size_t len)`

```c
smaug_series_f64_t *s = smaug_f64_create(100);
// Preenchido com 100 valores

smaug_series_f64_t *view = smaug_f64_view(s, 10, 20);
// view aponta para s[10..29] (20 elementos)
// view->size = 20
// view->data = s->data + 10 (mesmo array!)
// view->null_mask = s->null_mask + 10 (mesma máscara!)
```

**Propósito:** Criar "slice" sem copiar dados.

**Parâmetros:**
- `s`: série original
- `start`: índice inicial (0-based)
- `len`: número de elementos na view

**Validação:**
- Se `start + len > s->size`: **retorna NULL**

**Comportamento:**
- Aloca struct novo
- **Não copia dados** (aponta para original)
- `view->data = s->data + start`
- `view->null_mask = s->null_mask + start`
- `view->meta.is_view = true`
- `view->meta.external_alloc = true`

**Crítico:**
- View é **válida apenas enquanto `s` existe**
- Não chame `free(view)` antes de `free(s)` (order importa!)
- Modificar via view **modifica original**

**Exemplo perigoso:**
```c
smaug_series_f64_t* create_view_buggy() {
    smaug_series_f64_t *original = smaug_f64_create(100);
    smaug_series_f64_t *view = smaug_f64_view(original, 10, 20);
    smaug_f64_free(original);  // BUG! original foi deletado
    return view;               // view aponta para memória liberada
}
```

---

### 3.2 Getters/Setters

#### `double smaug_f64_get(smaug_series_f64_t *s, size_t idx)`

```c
smaug_series_f64_t *s = smaug_f64_create(5);
smaug_f64_set(s, 0, 42.0);

double val = smaug_f64_get(s, 0);  // val = 42.0
double na_val = smaug_f64_get(s, 1);  // val = NAN (índice 1 é nulo)
```

**Propósito:** Obter valor em índice.

**Parâmetros:**
- `s`: série
- `idx`: índice (0-based)

**Retorna:**
- Valor em `s->data[idx]` se válido (`null_mask[idx] == 0xFF`)
- **NAN se nulo** (`null_mask[idx] == 0x00`)

**Validação:**
- Se `idx >= s->size`: **retorna NAN** (acesso out-of-bounds!)
- Não há bounds check strict (confie em user)

**Nota:**
- Diferente do Lua que retorna `nil`, aqui retorna `NAN`
- Lua wrapper deve converter `NAN` → `nil`

---

#### `void smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val)`

```c
smaug_series_f64_t *s = smaug_f64_create(5);
smaug_f64_set(s, 0, 42.5);   // s->data[0] = 42.5, mask[0] = 0xFF
smaug_f64_set(s, 1, -3.14);  // s->data[1] = -3.14, mask[1] = 0xFF
```

**Propósito:** Definir valor em índice, marcar como válido.

**Parâmetros:**
- `s`: série
- `idx`: índice (0-based)
- `val`: valor a armazenar

**Comportamento:**
- `s->data[idx] = val`
- `s->null_mask[idx] = 0xFF` (marca válido)

**Validação:**
- Se `idx >= s->size`: **sem efeito** (silenciosamente ignora)

**Nota:**
- Sempre marca como válido, mesmo que `val == NAN`
- Para marcar como nulo, use `smaug_f64_set_null()`

---

#### `void smaug_f64_set_null(smaug_series_f64_t *s, size_t idx)`

```c
smaug_f64_set(s, 0, 42.0);
smaug_f64_set_null(s, 0);    // Marca s[0] como nulo
// Agora: smaug_f64_get(s, 0) == NAN
//        smaug_f64_is_null(s, 0) == true
```

**Propósito:** Marcar posição como nula (NA).

**Comportamento:**
- `s->null_mask[idx] = 0x00`
- `s->data[idx] = 0.0` (limpar para evitar garbage)

**Use case:**
- Marcar valores inválidos/missing
- Diferente de set(NAN) que ainda marca como válido!

---

#### `bool smaug_f64_is_null(smaug_series_f64_t *s, size_t idx)`

```c
smaug_f64_set(s, 0, 42.0);
smaug_f64_is_null(s, 0);     // false (é válido)

smaug_f64_set_null(s, 0);
smaug_f64_is_null(s, 0);     // true (é nulo)
```

**Propósito:** Verificar se posição é nula.

**Retorna:**
- `true` se `null_mask[idx] == 0x00`
- `false` se `null_mask[idx] == 0xFF`

---

### 3.3 Append Dinâmico

#### `int smaug_f64_append(smaug_series_f64_t *s, double val)`

```c
smaug_series_f64_t *s = smaug_f64_create_with_capacity(0, 10);
// size=0, capacity=10

smaug_f64_append(s, 1.0);   // OK: size=1
smaug_f64_append(s, 2.0);   // OK: size=2
// ... 8 mais vezes ...
smaug_f64_append(s, 10.0);  // OK: size=10, capacity=10 (full)

smaug_f64_append(s, 11.0);  // Realloc! capacity *= 1.5 → 15
                             // size=11, capacity=15
```

**Propósito:** Adicionar valor ao final, com realloc automático.

**Parâmetros:**
- `s`: série
- `val`: valor a adicionar

**Retorna:**
- `0` se sucesso
- `-1` se realloc falhar (OOM)

**Comportamento:**
- Incrementa `size`
- Marca novo elemento como válido (`mask[size-1] = 0xFF`)
- Se `size >= capacity` antes de append:
  - Realoca: `capacity = capacity + (capacity >> 1)` (cresce 1.5x)
  - Se realloc falha: retorna -1, série fica inconsistente!

**Grow strategy (importante):**
```
Capacity progression: 10 → 15 → 22 → 33 → 49 → 73 → 109 → ...
Fator: 1.5x (melhor que 2x para memory, pior que 1.5x for cache)
```

**Casos Edge:**
```c
smaug_f64_append(NULL, 1.0);     // Undefined (null ptr)
smaug_f64_append(s, INFINITY);   // OK: append infinity
smaug_f64_append(s, NAN);        // OK: append NAN (mas marca válido!)

/* Teste de crescimento */
smaug_series_f64_t *s = smaug_f64_create_with_capacity(0, 1);
for (int i = 0; i < 1000000; i++) {
    if (smaug_f64_append(s, i) == -1) {
        perror("OOM");
        break;
    }
}
// Pode falhar em machines com pouca RAM
```

**Memory Efficiency:**
- Com 1M appends: ~15M allocado (20% waste)
- Com 10M appends: ~150M allocado (5% waste)

---

#### `int smaug_f64_append_null(smaug_series_f64_t *s)`

```c
smaug_f64_append(s, 1.0);        // Valor válido
smaug_f64_append_null(s);        // Valor nulo
// size agora = 2
// mask = [0xFF, 0x00]
```

**Propósito:** Adicionar valor nulo.

**Retorna:**
- `0` se sucesso
- `-1` se realloc falhar

**Comportamento:**
- `s->data[size] = 0.0` (não importa, é nulo)
- `s->null_mask[size] = 0x00` (marca nulo)
- Incrementa `size`
- Realloc se necessário

---

### 3.4 Operações Aritméticas

#### `smaug_series_f64_t* smaug_f64_add(const smaug_series_f64_t *a, const smaug_series_f64_t *b)`

```c
smaug_series_f64_t *a = smaug_f64_create(3);
smaug_f64_set(a, 0, 1.0);
smaug_f64_set(a, 1, 2.0);
smaug_f64_set(a, 2, 3.0);
// a = [1.0, 2.0, 3.0]

smaug_series_f64_t *b = smaug_f64_create(3);
smaug_f64_set(b, 0, 10.0);
smaug_f64_set(b, 1, 20.0);
smaug_f64_set(b, 2, 30.0);
// b = [10.0, 20.0, 30.0]

smaug_series_f64_t *c = smaug_f64_add(a, b);
// c = [11.0, 22.0, 33.0] (nova série)
// a, b não são modificados (imutabilidade)
```

**Propósito:** Adicionar duas séries elemento a elemento.

**Parâmetros:**
- `a`, `b`: séries a somar

**Retorna:**
- Nova série com `a[i] + b[i]`
- **NULL se** `a->size != b->size` (tamanhos diferentes)
- **NULL se** alocação falhar

**Null handling:**
- Se ambas posições válidas: `result[i] = a[i] + b[i]`, marca válido
- Se qualquer uma nula: `result[i]` marcado como nulo

**Exemplo com nulos:**
```c
a = [1.0, 2.0, NA]
b = [10.0, NA, 30.0]
a + b = [11.0, NA, NA]  // NA propagado
```

**Casos Edge:**
```c
smaug_f64_add(a, b);              // OK
smaug_f64_add(NULL, b);           // NULL (null ptr)
smaug_f64_add(a, a);              // OK: a + a é válido (new series)
smaug_f64_add(a, b);              // NULL se size diferente
```

---

#### `smaug_series_f64_t* smaug_f64_sub(const smaug_series_f64_t *a, const smaug_series_f64_t *b)`

**Análogo a `add`, mas subtração.**

```c
smaug_series_f64_t *c = smaug_f64_sub(a, b);  // c[i] = a[i] - b[i]
```

---

#### `smaug_series_f64_t* smaug_f64_mul(const smaug_series_f64_t *a, const smaug_series_f64_t *b)`

**Análogo a `add`, mas multiplicação.**

```c
smaug_series_f64_t *c = smaug_f64_mul(a, b);  // c[i] = a[i] * b[i]
```

---

#### `smaug_series_f64_t* smaug_f64_div(const smaug_series_f64_t *a, const smaug_series_f64_t *b)`

**Análogo a `add`, mas divisão.**

```c
smaug_series_f64_t *c = smaug_f64_div(a, b);  // c[i] = a[i] / b[i]
```

**⚠️ Cuidado:**
- Divisão por zero → `INFINITY` ou `NAN`
- Não há check, precisa validar no Lua

---

#### `smaug_series_f64_t* smaug_f64_add_scalar(const smaug_series_f64_t *a, double scalar)`

```c
smaug_series_f64_t *a = smaug_f64_create(3);
smaug_f64_set(a, 0, 1.0);
smaug_f64_set(a, 1, 2.0);
smaug_f64_set(a, 2, 3.0);

smaug_series_f64_t *b = smaug_f64_add_scalar(a, 10.0);
// b = [11.0, 12.0, 13.0]
```

**Propósito:** Adicionar escalar a todos elementos.

**Retorna:**
- Nova série com `a[i] + scalar`

---

#### `smaug_series_f64_t* smaug_f64_mul_scalar(const smaug_series_f64_t *a, double scalar)`

**Análogo, mas multiplicação.**

```c
smaug_series_f64_t *b = smaug_f64_mul_scalar(a, 2.0);
// b = [2.0, 4.0, 6.0]
```

---

### 3.5 Reduções

#### `double smaug_f64_sum(const smaug_series_f64_t *s, bool ignore_na)`

```c
smaug_series_f64_t *s = smaug_f64_create(5);
smaug_f64_set(s, 0, 1.0);
smaug_f64_set(s, 1, 2.0);
smaug_f64_set(s, 2, 3.0);
smaug_f64_set_null(s, 3);  // nulo
smaug_f64_set(s, 4, 4.0);

double sum1 = smaug_f64_sum(s, true);   // 1+2+3+4 = 10.0
double sum2 = smaug_f64_sum(s, false);  // NAN (há nulo)
```

**Propósito:** Somar todos elementos válidos.

**Parâmetros:**
- `s`: série
- `ignore_na`: se true, ignora nulos; se false, qualquer nulo → NAN

**Retorna:**
- Soma dos valores válidos
- **NAN se** `ignore_na=false` **e há nulo**

**Otimização:**
- Loop SIMD-friendly (compilador pode vetorizar)
- Usar `restrict` para ajudar compilador

---

#### `double smaug_f64_mean(const smaug_series_f64_t *s, bool ignore_na)`

```c
double mean = smaug_f64_mean(s, true);  // Sum / count_nonnull
```

**Propósito:** Média aritmética.

**Implementação:**
```
mean = sum(s, ignore_na) / count_nonnull(s)
```

**Casos Edge:**
```c
smaug_f64_mean(s_empty, true);     // NAN (size=0)
smaug_f64_mean(s_all_na, true);    // NAN (count=0)
smaug_f64_mean(s_with_inf, true);  // INFINITY (if sum é inf)
```

---

#### `double smaug_f64_min(const smaug_series_f64_t *s, bool ignore_na)`

```c
double min = smaug_f64_min(s, true);  // Mínimo
```

**Propósito:** Mínimo valor.

**Comportamento:**
- Itera sobre valores válidos
- Rastreia mínimo
- Retorna `INFINITY` se nenhum válido

---

#### `double smaug_f64_max(const smaug_series_f64_t *s, bool ignore_na)`

**Análogo a `min`, retorna máximo.**

---

#### `double smaug_f64_std(const smaug_series_f64_t *s, bool ignore_na)`

```c
double std = smaug_f64_std(s, true);  // Desvio padrão (população)
```

**Propósito:** Desvio padrão populacional.

**Fórmula:**
```
std = sqrt( sum((x - mean)^2) / count )
```

**Nota:**
- **Populacional**, não amostral (divide por N, não N-1)
- Para amostral, multiplicar por sqrt(N/(N-1))

---

#### `double smaug_f64_var(const smaug_series_f64_t *s, bool ignore_na)`

**Análogo, variância (std^2).**

---

### 3.6 Comparações

#### `uint8_t* smaug_f64_gt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask)`

```c
smaug_series_f64_t *s = smaug_f64_create(5);
smaug_f64_set(s, 0, 1.0);
smaug_f64_set(s, 1, 20.0);
smaug_f64_set(s, 2, 3.0);
smaug_f64_set_null(s, 3);
smaug_f64_set(s, 4, 50.0);

smaug_mask_t *out_mask = NULL;
uint8_t *result = smaug_f64_gt(s, 10.0, &out_mask);
// result = [0x00, 0xFF, 0x00, 0x00, 0xFF]
//          (20.0 > 10 e 50.0 > 10, outros não)
```

**Propósito:** Comparação greater-than, retorna boolean array.

**Parâmetros:**
- `s`: série
- `threshold`: valor a comparar
- `out_mask`: ponteiro para receber mask (NÃO usado aqui, mas reserved)

**Retorna:**
- Array `uint8_t` com `0xFF` (true) ou `0x00` (false)
- **NULL se** alocação falhar

**Null handling:**
- NA comparado como false (`0x00`)

**Casos de uso:**
```c
uint8_t *mask = smaug_f64_gt(s, 100.0, NULL);
// Agora pode filtrar:
smaug_series_f64_t *filtered = smaug_f64_filter(s, mask);
free(mask);  // Liberar manualmente (not GC'd)
```

---

#### `uint8_t* smaug_f64_lt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask)`

**Análogo, less-than.**

---

#### `uint8_t* smaug_f64_eq(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask)`

**Análogo, equal.**

⚠️ **Cuidado com floating-point:**
```c
smaug_f64_eq(s, 0.1, NULL);  // Pode falhar devido a precision!
// Use com cuidado, considerar range checks
```

---

### 3.7 Ordenação

#### `size_t* smaug_f64_argsort(const smaug_series_f64_t *s, bool ascending)`

```c
smaug_series_f64_t *s = smaug_f64_create(5);
smaug_f64_set(s, 0, 30.0);
smaug_f64_set(s, 1, 10.0);
smaug_f64_set(s, 2, 50.0);
smaug_f64_set(s, 3, 20.0);
smaug_f64_set(s, 4, 40.0);
// s = [30, 10, 50, 20, 40]

size_t *indices = smaug_f64_argsort(s, true);
// indices = [1, 3, 0, 4, 2]  (índices em ordem crescente)
// s[1]=10, s[3]=20, s[0]=30, s[4]=40, s[2]=50
```

**Propósito:** Retornar índices que ordenariam a série.

**Retorna:**
- Array de `size_t` com índices
- **NULL se** alocação falhar ou série tem nulos

**Null handling:**
- Se há nulos: retorna NULL (não sabe como ordenar NAs)

---

#### `smaug_series_f64_t* smaug_f64_sort(const smaug_series_f64_t *s, bool ascending)`

**Variante que retorna série ordenada (nova série).**

```c
smaug_series_f64_t *sorted = smaug_f64_sort(s, true);
// sorted = [10, 20, 30, 40, 50] (nova série ordenada)
```

---

### 3.8 Utilitários

#### `size_t smaug_f64_count_nonnull(const smaug_series_f64_t *s)`

```c
size_t count = smaug_f64_count_nonnull(s);  // Número de valores válidos
```

---

#### `smaug_series_f64_t* smaug_f64_take(const smaug_series_f64_t *s, const size_t *indices, size_t len)`

```c
size_t take_indices[] = {0, 2, 4};
smaug_series_f64_t *result = smaug_f64_take(s, take_indices, 3);
// result = [s[0], s[2], s[4]] (cópia de elementos específicos)
```

**Propósito:** Selecionar e copiar elementos por índice.

---

## 4. Referência de Funções - Int64

**(Análogo a Float64, com tipos `int64_t` em vez de `double`)**

Todas as funções existem em versão int64:
- `smaug_i64_create()`
- `smaug_i64_free()`
- `smaug_i64_get()` → retorna `int64_t`
- `smaug_i64_set()` → aceita `int64_t`
- Etc...

**Diferenças principais:**
- `sum/min/max`: retornam `int64_t`
- `mean/std/var`: retornam `double` (podem ter decimais)
- Comparações `gt/lt/eq`: threshold é `int64_t`

---

## 5. Arquitetura Detalhada

### 5.1 Estrutura de Diretórios

```
smaug/
├── include/
│   ├── smaug_math.h      # Operações: sum, mean, add, mul, etc
│   └── smaug_types.h     # Tipos: structs, masks, metadata
├── src/
│   ├── smaug_core.c      # Create, free, append (Fase 1)
│   ├── smaug_ops_f64.c   # Operações float64 (Fase 1)
│   ├── smaug_ops_i64.c   # Operações int64 (Fase 1)
│   ├── smaug_csv.c       # Parser CSV (Fase 5)
│   ├── smaug_sort.c      # Sorting (Fase 2)
│   └── smaug_hash.c      # Hash tables (Fase 6)
├── lua/smaug/
│   ├── ffi_loader.lua    # FFI bridge
│   ├── series.lua        # Classe Series
│   └── dataset.lua       # Classe DataSet
├── tests/
│   ├── test_alloc.c      # Testes alocação
│   ├── test_ops.c        # Testes operações
│   └── test_ffi.lua      # Testes FFI
├── CMakeLists.txt
└── build/
    └── lib/libsmaug_math.so
```

### 5.2 Decisões Arquiteturais

| Decisão | Escolha | Por quê |
|---------|---------|--------|
| **Tipos** | Estruturas separadas f64 e i64 | Type safety, sem casting |
| **Null** | Bitmask paralelo | Funciona com todos tipos |
| **Views** | Sem cópia | Performance (slicing eficiente) |
| **Imutabilidade** | Operações retornam new | Evita aliasing bugs |
| **FFI** | LuaJIT FFI | Zero-copy, ~1-2% overhead |
| **Memory** | Manual (malloc/free) | Controle, sem GC overhead |

---

## 6. Implementação - Padrões e Exemplos

### 6.1 Padrão: Operação Binária (add, sub, mul, div)

```c
smaug_series_f64_t* smaug_f64_add(const smaug_series_f64_t *a, 
                                   const smaug_series_f64_t *b) {
    /* Validação */
    if (!a || !b || a->size != b->size) {
        return NULL;
    }
    
    /* Alocar resultado */
    smaug_series_f64_t *result = smaug_f64_create(a->size);
    if (!result) return NULL;
    
    /* Loop principal (SIMD-friendly) */
    for (size_t i = 0; i < a->size; i++) {
        bool a_valid = (a->null_mask[i] != 0x00);
        bool b_valid = (b->null_mask[i] != 0x00);
        
        if (a_valid && b_valid) {
            result->data[i] = a->data[i] + b->data[i];
            result->null_mask[i] = 0xFF;  /* Válido */
        } else {
            result->null_mask[i] = 0x00;  /* Nulo se qualquer um é */
        }
    }
    
    return result;
}
```

**Princípios:**
1. Validar inputs
2. Alocar resultado
3. Copiar metadados (dtype, name)
4. Loop elemento a elemento com null check

---

### 6.2 Padrão: Redução (sum, mean, min, max)

```c
double smaug_f64_sum(const smaug_series_f64_t *s, bool ignore_na) {
    if (!s) return NAN;
    
    double sum = 0.0;
    
    for (size_t i = 0; i < s->size; i++) {
        if (s->null_mask[i] != 0x00) {  /* Válido */
            sum += s->data[i];
        } else if (!ignore_na) {        /* Nulo encontrado */
            return NAN;
        }
    }
    
    return sum;
}
```

**Princípios:**
1. Validar null mask
2. Acumular resultado
3. Retornar NAN se há problema

---

### 6.3 Padrão: Append com Realloc

```c
int smaug_f64_append(smaug_series_f64_t *s, double val) {
    if (!s) return -1;
    
    /* Checar se precisa crescer */
    if (s->size >= s->capacity) {
        /* Crescimento: capacity *= 1.5 */
        size_t new_capacity = s->capacity + (s->capacity >> 1);
        if (new_capacity == s->capacity) new_capacity++;
        
        /* Realloc data */
        double *new_data = realloc(s->data, new_capacity * sizeof(double));
        if (!new_data) return -1;
        
        /* Realloc mask */
        smaug_mask_t *new_mask = realloc(s->null_mask, new_capacity);
        if (!new_mask) {
            free(new_data);
            return -1;
        }
        
        /* Atualizar */
        s->data = new_data;
        s->null_mask = new_mask;
        s->capacity = new_capacity;
    }
    
    /* Adicionar */
    s->data[s->size] = val;
    s->null_mask[s->size] = 0xFF;
    s->size++;
    
    return 0;
}
```

---

## 7. Gerenciamento de Memória

### 7.1 Ownership Model

```
Operação              | Ownership | Caller responsibility
──────────────────────┼───────────┼─────────────────────
create()              | Smaug     | chamar free() quando done
clone()               | Smaug     | chamar free() quando done
add/sub/mul/div()     | Smaug     | chamar free() resultado
view()                | Smaug     | NÃO chamar free enquanto s existe
create_from_array()   | Smaug     | chamar free() quando done
```

### 7.2 Memory Leak Prevention

**Checklist:**
- [ ] Todo `malloc` tem correspondente `free`
- [ ] Views liberadas **após** série original
- [ ] Resultados de operações são liberados
- [ ] FFI em Lua usa `ffi.gc()` para auto-cleanup

### 7.3 Valgrind Testing

```bash
valgrind --leak-check=full ./test_alloc
```

---

## 8. Null Handling (Bitmasks)

### 8.1 Por quê Bitmask?

| Abordagem | Pros | Cons |
|-----------|------|------|
| **Bitmask (0xFF/0x00)** | Funciona com todos tipos | Mais RAM que bit-packing |
| **Bit-packing** | Melhor RAM | Complexo, mais lento |
| **NaN (floats)** | Simples | Não funciona em ints/strings |
| **Sentinel value** | Simples | Conflita com dados válidos |

**Escolha:** Bitmask byte (uint8_t) = trade-off ótimo

### 8.2 Comportamento Esperado

```c
/* Criação */
s = smaug_f64_create(5);
// null_mask = [0x00, 0x00, 0x00, 0x00, 0x00] (tudo nulo)

/* Set marca como válido */
smaug_f64_set(s, 0, 42.0);
// null_mask[0] = 0xFF

/* Set_null marca como nulo */
smaug_f64_set_null(s, 0);
// null_mask[0] = 0x00

/* Get verifica mask */
val = smaug_f64_get(s, 0);
// if mask[0] == 0x00 → retorna NAN
```

---

## 9. Roadmap Faseado

| Fase | Duração | O que | Status |
|------|---------|-------|--------|
| **1** | 2-3 sem | Setup C, header, core functions, FFI | 👈 AQUI |
| **2** | 2 sem | Classe Series Lua, metamétodos | Próxima |
| **3** | 2 sem | Classe DataSet, slicing | +2 sem |
| **4** | 1.5 sem | Boolean indexing, filtros | +3 sem |
| **5** | 2.5 sem | CSV I/O, type inference | +4 sem |
| **6+** | 3+ sem | GroupBy, Joins, tipos complexos | Futuro |

---

## 10. Troubleshooting e Casos Edge

### 10.1 Segmentation Fault

**Causa comum:** Usar série/view após liberar

```c
smaug_series_f64_t *s = smaug_f64_create(10);
smaug_f64_free(s);
double val = smaug_f64_get(s, 0);  // SEGFAULT! s foi deletado
```

**Prevenção:**
```c
smaug_f64_free(s);
s = NULL;  // Boa prática
```

### 10.2 Memory Leak

**Causa:** Não liberar results de operações

```c
smaug_series_f64_t *result = smaug_f64_add(a, b);
// ... uso ...
// LEAK! Nunca liberou result
```

**Prevenção:**
```c
smaug_f64_free(result);
```

### 10.3 View Outliving Original

```c
smaug_series_f64_t* create_view() {
    smaug_series_f64_t *s = smaug_f64_create(10);
    smaug_series_f64_t *view = smaug_f64_view(s, 0, 10);
    smaug_f64_free(s);  // BUG! s foi deletado
    return view;        // view aponta para memória liberada
}
```

**Prevenção:**
- Manter `original` vivo enquanto `view` é usado
- Ou clonar: `clone = smaug_f64_clone(view)`

### 10.4 NAN vs Null

```c
smaug_f64_set(s, 0, NAN);      // Set NAN, mas marca como VÁLIDO
smaug_f64_set_null(s, 0);      // Marca como NULO

smaug_f64_get(s, 0);           // Retorna NAN
smaug_f64_is_null(s, 0);       // Retorna true (é nulo)
```

**Diferença:** NAN pode ser válido (set(NAN)), null_mask marca como inválido

### 10.5 Divisão por Zero

```c
smaug_f64_div(a, b);           // Se b[i] == 0.0 → inf/nan
// Sem check! Atenção no Lua wrapper
```

---

## Resumo Rápido

### Tabela de Funções (Float64)

| Categoria | Funções |
|-----------|---------|
| **Alloc** | create, create_with_capacity, create_from_array, free, clone, view |
| **Getters** | get, is_null, count_nonnull |
| **Setters** | set, set_null |
| **Append** | append, append_null |
| **Arithmetic** | add, sub, mul, div, add_scalar, mul_scalar |
| **Reductions** | sum, mean, min, max, std, var |
| **Comparisons** | gt, lt, eq |
| **Sorting** | argsort, sort |
| **Utils** | take |

### Checklist de Implementação

- [ ] smaug_types.h (struct definitions)
- [ ] smaug_math.h (function declarations)
- [ ] smaug_core.c (create, free, append)
- [ ] smaug_ops_f64.c (operations float64)
- [ ] smaug_ops_i64.c (operations int64)
- [ ] CMakeLists.txt (build system)
- [ ] tests/test_alloc.c (allocation tests)
- [ ] tests/test_ops.c (operation tests)
- [ ] lua/smaug/ffi_loader.lua (FFI bridge)
- [ ] tests/test_ffi.lua (FFI validation)

---

**Smaug: Data analysis in Lua, performance of C** 🐉

*Documentação Completa v1.1 - Use como referência permanente*
