# Smaug: Documentação Técnica e Roadmap Arquitetural
## Biblioteca de Análise de Dados em Lua com Backend em C

**Versão:** 1.0 (Pré-desenvolvimento)  
**Data:** 2026-05-18  
**Objetivo:** Replicar as funcionalidades essenciais do Pandas (Python) em Lua com performance comparável ao NumPy via backend C otimizado.

---

## Índice

1. [Visão Geral Estratégica](#1-visão-geral-estratégica)
2. [Análise Comparativa: Pandas vs Smaug](#2-análise-comparativa-pandas-vs-Smaug)
3. [Arquitetura de Alto Nível](#3-arquitetura-de-alto-nível)
4. [Especificação do Backend em C](#4-especificação-do-backend-em-c)
5. [Especificação do Frontend em Lua](#5-especificação-do-frontend-em-lua)
6. [LuaJIT FFI: A Ponte de Performance](#6-luajit-ffi-a-ponte-de-performance)
7. [Estruturas de Dados Detalhadas](#7-estruturas-de-dados-detalhadas)
8. [Gerenciamento de Memória](#8-gerenciamento-de-memória)
9. [Roadmap Faseado](#9-roadmap-faseado)
10. [Decisões de Design Críticas](#10-decisões-de-design-críticas)
11. [Benchmarking e Performance](#11-benchmarking-e-performance)
12. [Mitigação de Riscos](#12-mitigação-de-riscos)

---

## 1. Visão Geral Estratégica

### 1.1 Motivação e Contexto

**Pandas** em Python é a ferramenta *de facto* para manipulação tabular de dados, mas:
- Inicialização lenta (~1-2s por import)
- Overhead da GC do Python em operações numéricas massivas
- Difícil de distribuir em ambientes embarcados (edge computing, game mods, scripts leves)
- Memory footprint elevado para datasets pequenos

**Lua**, por sua vez:
- Extremamente leve (~400KB de runtime)
- Suporta **LuaJIT** com compilação JIT e FFI nativo
- Excelente para scripting em game engines, IoT, edge computing
- Comunidade crescente em data science / analytical scripting

**Smaug** visa preencher este nicho: uma biblioteca de análise de dados **verdadeiramente leve** com performance **comparable a NumPy** em operações críticas.

### 1.2 Requisitos Não-Funcionais

| Aspecto | Requisito | Justificativa |
|---------|-----------|---------------|
| **Memory Footprint** | < 2MB para compilado + runtime | Embarcabilidade em edge devices |
| **Startup Time** | < 100ms para require + init | Scripting interativo |
| **Performance Numérica** | ≥ 80% de NumPy em soma/produto | Viável para dados até ~100M linhas |
| **Type Safety** | Runtime checks em hot paths | Evitar segfaults silenciosos |
| **Compatibility** | API próxima a Pandas | Curva de aprendizado mínima |

---

## 2. Análise Comparativa: Pandas vs Smaug

### 2.1 Funcionalidades Críticas do Pandas

O Pandas oferece os seguintes pilares:

| Funcionalidade | Pandas | Smaug (Fase) | Importância |
|---|---|---|---|
| Series (1D) | ✓ | Fase 2 | **CRÍTICA** |
| DataFrame (2D) | ✓ | Fase 3 | **CRÍTICA** |
| Índices customizados | ✓ | Fase 3 | Alta |
| MultiIndex | ✓ | Fase 6 | Média |
| Slicing (`.loc`, `.iloc`) | ✓ | Fase 3 | **CRÍTICA** |
| Boolean masking | ✓ | Fase 4 | **CRÍTICA** |
| GroupBy | ✓ | Fase 6 | Alta |
| Merge/Join | ✓ | Fase 6 | Alta |
| I/O (CSV, Excel, SQL) | ✓ | Fase 5 | **CRÍTICA** |
| Resample (Time Series) | ✓ | Fase 7 | Média |
| Window ops (rolling, expanding) | ✓ | Fase 7 | Média |
| Pivot Tables | ✓ | Fase 7 | Média |

**Decisão de Escopo:** Focar em **Fases 1-5** para MVP (Mínimo Produto Viável). Fases 6-7 são extensões pós-launch.

### 2.2 Tipos de Dados do Pandas vs Smaug

**Pandas suporta:**
- int8, int16, int32, int64 (signed integers)
- uint8, uint16, uint32, uint64 (unsigned)
- float32, float64 (IEEE 754 floating-point)
- bool (boolean)
- object (genérico: strings, dicts, etc.)
- datetime64 (timestamps)
- timedelta64 (durações)
- category (categorical, com encoding)

**Smaug (MVP):**

| Tipo | Suporte (Fase) | Representação C | Notas |
|------|---|---|---|
| int64 | Fase 1 | `int64_t` | Interop com Lua numbers |
| uint64 | Fase 2 | `uint64_t` | Para contadores, flags |
| float64 | Fase 1 | `double` | Padrão Lua |
| float32 | Fase 2 | `float` | Para economizar RAM |
| bool | Fase 2 | `uint8_t` (0/1) | Compacto |
| string | Fase 5 | Ponteiros + dictionary encoding | Ver §7.5 |
| datetime | Fase 6 | `int64_t` (Unix timestamp em ms) | Futuro |

---

## 3. Arquitetura de Alto Nível

### 3.1 Diagrama de Camadas

```
┌─────────────────────────────────────────────────────────┐
│           Aplicação do Usuário (Lua)                    │
│  local df = dataset.read_csv("dados.csv")               │
│  local resultado = df["salario"]:sum()                  │
└────────────────────┬────────────────────────────────────┘
                     │
┌─────────────────────┴────────────────────────────────────┐
│         Frontend em Lua (Smaug Module)               │
│  • Classes: DataSet, Series, Indexer                    │
│  • Metamétodos: __add, __index, __tostring              │
│  • Validação e conversão de tipos                        │
│  • API expressiva (method chaining, syntactic sugar)    │
└────────────────────┬────────────────────────────────────┘
                     │ LuaJIT FFI Calls
┌─────────────────────┴────────────────────────────────────┐
│    Bridge FFI (ffi.cdef + ffi.load)                     │
│  • Assinaturas das funções C                            │
│  • Garbage collector hooks (ffi.gc)                      │
│  • Conversão userdata ↔ pointer                         │
└────────────────────┬────────────────────────────────────┘
                     │ Native Calls
┌─────────────────────┴────────────────────────────────────┐
│       Backend em C (libsmaug_math.so/.dll)              │
│  • Structs tipadas (SeriesInt64, SeriesFloat64, etc.)   │
│  • Alocação contínua (malloc / realloc)                 │
│  • Laços SIMD-friendly, qsort, hash tables              │
│  • I/O otimizado (CSV parsing, compression)             │
│  • Null handling (bitmasks)                             │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Fluxo de Execução (Exemplo: `df["idade"]:sum()`)

```
1. Usuário escreve:  df["idade"]:sum()

2. Lua:
   - __index(df, "idade") ──→ retorna Series Lua
   - Series:sum() ──────────→ chama método Lua

3. Método Series:sum() em Lua:
   - Valida argumentos (ignore_na: bool)
   - Chama C via FFI: result = C.series_f64_sum(ptr, ignore_na)

4. C (libsmaug_math.so):
   - Recebe ponteiro e flag
   - Aloca/usa buffer acumulador (SIMD-friendly)
   - Loop otimizado: for (i = 0; i < size; i++) sum += data[i]
   - Retorna double

5. Lua:
   - Recebe result (double)
   - Retorna ao usuário
```

### 3.3 Premissas de Design

1. **Imutabilidade por padrão:** Operações geram novas Series/DataSets, não modificam in-place.
2. **Lazy evaluation (futuro):** Operações podem ser compiladas em kernels C, não executadas imediatamente.
3. **Type coercion:** Quando possível, promover tipos (int32 → int64, float32 → float64) em operações mistas.
4. **Copy-on-write (futuro):** Views não copiam memória até modificação.

---

## 4. Especificação do Backend em C

### 4.1 Estrutura de Projeto C

```
smaug_math/
├── CMakeLists.txt          # Build system
├── Makefile.simple         # Alternativa simplificada
├── src/
│   ├── smaug_math.h        # Header público
│   ├── smaug_core.c        # Alocação, free, init
│   ├── smaug_ops_f64.c     # Operações float64
│   ├── smaug_ops_i64.c     # Operações int64
│   ├── smaug_csv.c         # Parser CSV
│   ├── smaug_sort.c        # Sorting algorithms
│   └── smaug_hash.c        # Hash tables para GroupBy
├── tests/
│   ├── test_alloc.c        # Testes de alocação
│   ├── test_ops.c          # Testes de operações
│   └── test_csv.c          # Testes CSV
└── build/
    └── libsmaug_math.so    # Output compilado
```

### 4.2 Header Público (smaug_math.h)

```c
#ifndef SMAUG_MATH_H
#define SMAUG_MATH_H

#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stddef.h>

/* ===== Tipo Opaque para Hash Table ===== */
typedef struct smaug_hash_table smaug_hash_table_t;

/* ===== Estruturas Base ===== */

/* Máscara de nulos: array paralelo (1 byte por valor)
   Convenção: 0xFF = válido, 0x00 = NA/NULL */
typedef uint8_t smaug_mask_t;

/* Metadados de uma série
   Útil para tracking de tipos e memory ownership */
typedef struct {
    const char *name;        /* Nome da coluna (opcional) */
    const char *dtype;       /* "int64", "float64", etc */
    bool is_view;           /* True se é uma view (não owner) */
    bool external_alloc;    /* True se alocado fora (não free) */
} smaug_metadata_t;

/* ===== Tipos Float64 ===== */

typedef struct {
    double *data;
    smaug_mask_t *null_mask;
    size_t size;
    size_t capacity;
    smaug_metadata_t meta;
} smaug_series_f64_t;

/* Construtores e Destrutores */
smaug_series_f64_t* smaug_f64_create(size_t size);
smaug_series_f64_t* smaug_f64_create_with_capacity(size_t size, size_t capacity);
smaug_series_f64_t* smaug_f64_create_from_array(const double *array, size_t len);
void smaug_f64_free(smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_clone(const smaug_series_f64_t *s);
smaug_series_f64_t* smaug_f64_view(smaug_series_f64_t *s, size_t start, size_t len);

/* Getters/Setters */
double smaug_f64_get(smaug_series_f64_t *s, size_t idx);
void smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val);
void smaug_f64_set_null(smaug_series_f64_t *s, size_t idx);
bool smaug_f64_is_null(smaug_series_f64_t *s, size_t idx);

/* Append */
int smaug_f64_append(smaug_series_f64_t *s, double val);  /* Retorna 0 success, -1 fail */
int smaug_f64_append_null(smaug_series_f64_t *s);

/* Operações Aritméticas */
smaug_series_f64_t* smaug_f64_add(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_sub(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_mul(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_div(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
smaug_series_f64_t* smaug_f64_add_scalar(const smaug_series_f64_t *a, double scalar);
smaug_series_f64_t* smaug_f64_mul_scalar(const smaug_series_f64_t *a, double scalar);

/* Reduções */
double smaug_f64_sum(const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_mean(const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_min(const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_max(const smaug_series_f64_t *s, bool ignore_na);
double smaug_f64_std(const smaug_series_f64_t *s, bool ignore_na);  /* Population std */
double smaug_f64_var(const smaug_series_f64_t *s, bool ignore_na);  /* Population var */

/* Comparações (retorna SeriesBool como uint8_t* array) */
uint8_t* smaug_f64_gt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_lt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
uint8_t* smaug_f64_eq(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);

/* Ordenação */
size_t* smaug_f64_argsort(const smaug_series_f64_t *s, bool ascending);
smaug_series_f64_t* smaug_f64_sort(const smaug_series_f64_t *s, bool ascending);

/* ===== Tipos Int64 ===== */

typedef struct {
    int64_t *data;
    smaug_mask_t *null_mask;
    size_t size;
    size_t capacity;
    smaug_metadata_t meta;
} smaug_series_i64_t;

/* Similar ao f64, mas para int64_t
   (implementação análoga, omitida por brevidade) */
smaug_series_i64_t* smaug_i64_create(size_t size);
void smaug_i64_free(smaug_series_i64_t *s);
int64_t smaug_i64_sum(const smaug_series_i64_t *s, bool ignore_na);
/* ... etc */

/* ===== Tipos Bool ===== */

typedef struct {
    uint8_t *data;          /* Array de 0 ou 1 */
    size_t size;
    size_t capacity;
} smaug_series_bool_t;

smaug_series_bool_t* smaug_bool_create(size_t size);
void smaug_bool_free(smaug_series_bool_t *s);

/* ===== Filtração (Masking) ===== */

/* Retorna índices das linhas onde mask == true */
size_t* smaug_f64_where(const smaug_series_f64_t *s, const uint8_t *mask, size_t *out_count);
smaug_series_f64_t* smaug_f64_filter(const smaug_series_f64_t *s, const uint8_t *mask);

/* ===== CSV I/O ===== */

/* Parser CSV com inferência de tipos
   Retorna um array de ponteiros genéricos (typed) */
typedef struct {
    void **columns;         /* Array de ponteiros para series */
    const char **dtypes;    /* Array de strings com tipos */
    const char **col_names; /* Nomes das colunas */
    size_t num_cols;
    size_t num_rows;
} smaug_csv_table_t;

smaug_csv_table_t* smaug_csv_read(const char *filename, bool has_header, char delimiter);
void smaug_csv_table_free(smaug_csv_table_t *tbl);

/* ===== Utilidades ===== */

/* Contar valores não-nulos */
size_t smaug_f64_count_nonnull(const smaug_series_f64_t *s);

/* Copiar com reindexação */
smaug_series_f64_t* smaug_f64_take(const smaug_series_f64_t *s, const size_t *indices, size_t len);

#endif  /* SMAUG_MATH_H */
```

### 4.3 Estratégia de Implementação de Operações (Float64)

Cada operação precisa considerar:
1. **Null handling:** Verificar `null_mask` antes de acessar
2. **SIMD friendliness:** Usar data layout contíguo, evitar branches no loop interior
3. **Overflow/underflow:** Documentar comportamento (IEEE 754 para floats)
4. **Error handling:** Retornar `NULL` ou código de erro em casos críticos

**Exemplo: `smaug_f64_sum`**

```c
double smaug_f64_sum(const smaug_series_f64_t *s, bool ignore_na) {
    if (s == NULL || s->data == NULL) return 0.0;
    
    double sum = 0.0;
    size_t valid_count = 0;
    
    if (!ignore_na) {
        /* Verificar se há NAs; se sim, retornar NaN */
        for (size_t i = 0; i < s->size; i++) {
            if (s->null_mask[i] == 0x00) {
                return NAN;
            }
        }
    }
    
    /* Sum com null masking
       Compiladores modernos devem vetorizar isto se houver
       poucas divergências no padrão de nulos */
    for (size_t i = 0; i < s->size; i++) {
        if (s->null_mask[i] == 0xFF) {  /* Válido */
            sum += s->data[i];
            valid_count++;
        }
    }
    
    return sum;
}
```

**Observações:**
- O compilador (gcc -O3 / clang -O3) **pode** vetorizar, mas nem sempre
- Para garantir SIMD, pode ser necessário compilar com `-march=native` ou usar intrinsics
- Usar `restrict` pointers ajuda o compilador a otimizar

```c
double smaug_f64_sum_restrict(const smaug_series_f64_t *restrict s, bool ignore_na) {
    /* ... mesmo código, mas com 'restrict' para ajudar otimizações ... */
}
```

### 4.4 Estratégia de Parsing CSV

CSV é deceptivamente complexo:

```
idade,nome,salario
25,"Silva, João",3000.50
30,"Costa, Maria",3500.00
```

**Desafios:**
- Aspas ao redor de campos (quoted fields)
- Quebras de linha dentro de quoted fields
- Escapadas de aspas (`\"`)
- Delimitadores variáveis (`,`, `;`, `\t`)
- Tipos mistos (int vs float)

**Estratégia simplificada (MVP):**

1. **Read-ahead:** Ler arquivo inteiro em buffer na RAM (pode falhar para >1GB)
2. **First pass:** Contar linhas, detectar delimitador, alocar structs
3. **Type inference:** Examinar primeira linha (ou primeiras N linhas) e tentar parse como:
   - int64 (se casa com `^-?\d+$`)
   - float64 (se casa com `^-?\d+\.?\d*([eE]-?\d+)?$`)
   - bool (se "true"/"false"/"1"/"0")
   - string (fallback)
4. **Second pass:** Parse pelo tipo inferido, popula arrays

```c
smaug_csv_table_t* smaug_csv_read(const char *filename, bool has_header, char delimiter) {
    FILE *f = fopen(filename, "rb");
    if (!f) return NULL;
    
    /* 1. Medir tamanho do arquivo */
    fseek(f, 0, SEEK_END);
    size_t file_size = ftell(f);
    fseek(f, 0, SEEK_SET);
    
    /* 2. Ler arquivo inteiro */
    char *buffer = malloc(file_size + 1);
    if (!buffer) { fclose(f); return NULL; }
    size_t bytes_read = fread(buffer, 1, file_size, f);
    fclose(f);
    buffer[bytes_read] = '\0';
    
    /* 3. Contar colunas e linhas */
    /* ... parse field by field ... */
    
    /* 4. Inferir tipos */
    /* ... analyze samples ... */
    
    /* 5. Alocar series e preencher */
    /* ... reparse com tipos conhecidos ... */
    
    free(buffer);
    /* ... retornar resultado ... */
}
```

**Compilação (CMakeLists.txt)**

```cmake
cmake_minimum_required(VERSION 3.10)
project(smaug_math C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_FLAGS_RELEASE "-O3 -march=native -ffast-math")
set(CMAKE_C_FLAGS_DEBUG "-g -O0 -Wall -Wextra -Werror")

# Detectar sistema operacional
if (WIN32)
    set(LIB_EXTENSION ".dll")
    set(COMPILE_FLAGS "-fPIC")
else()
    set(LIB_EXTENSION ".so")
    set(COMPILE_FLAGS "-fPIC")
endif()

add_library(smaug_math SHARED
    src/smaug_core.c
    src/smaug_ops_f64.c
    src/smaug_ops_i64.c
    src/smaug_csv.c
    src/smaug_sort.c
)

target_compile_options(smaug_math PRIVATE ${COMPILE_FLAGS})

set_target_properties(smaug_math PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)

# Testes (opcional)
enable_testing()
add_executable(test_alloc tests/test_alloc.c src/smaug_core.c)
add_test(NAME AllocationTests COMMAND test_alloc)
```

---

## 5. Especificação do Frontend em Lua

### 5.1 Estrutura de Módulos Lua

```
smaug/
├── init.lua              # Carrega todo o módulo
├── ffi_loader.lua        # FFI bindings (§6)
├── core/
│   ├── series.lua        # Classe Series
│   ├── dataset.lua       # Classe DataSet
│   ├── indexer.lua       # Classe Indexer (loc/iloc)
│   └── utils.lua         # Funções utilitárias
├── io/
│   ├── csv.lua           # Leitor/escritor CSV
│   └── json.lua          # Leitor/escritor JSON
├── ops/
│   ├── arithmetic.lua    # Operações aritméticas
│   ├── logical.lua       # Operações lógicas
│   └── groupby.lua       # GroupBy (Fase 6)
└── viz/
    ├── table.lua         # Formatação tabular
    └── plot.lua          # Plotting (futuro)
```

### 5.2 Classe Series (smaug/core/series.lua)

```lua
-- smaug/core/series.lua

local ffi = require("ffi")
local C = require("smaug.ffi_loader")

local Series = {}
Series.__index = Series

-- ===== Construtor =====

function Series:new(dtype, size, data_ptr, null_mask_ptr, name)
    -- dtype: string ("float64", "int64", etc)
    -- size: número de elementos
    -- data_ptr: ponteiro C para array de dados
    -- null_mask_ptr: ponteiro C para bitmask
    -- name: nome da coluna (opcional)
    
    local obj = {
        _dtype = dtype,
        _size = size,
        _ptr_data = data_ptr,
        _ptr_mask = null_mask_ptr,
        _name = name or "unnamed",
    }
    setmetatable(obj, self)
    
    -- Instruir GC do Lua a liberar memória C quando Series for coletada
    -- Ver §6.3 para mais detalhes
    return obj
end

function Series:create_float64(size, name)
    -- Factory: criar Series float64 nova
    local c_series = C.smaug_f64_create(size)
    if c_series == nil then
        error("Failed to allocate Series (float64)")
    end
    
    -- Extrair pointers da struct C
    local data_ptr = c_series.data
    local mask_ptr = c_series.null_mask
    
    -- Criar objeto Lua
    local series = Series:new("float64", size, data_ptr, mask_ptr, name)
    
    -- Guardar referência ao struct C completo para later access
    series._c_struct = c_series
    
    -- Garbage collector hook
    ffi.gc(c_series, C.smaug_f64_free)
    
    return series
end

-- ===== Getters/Setters =====

function Series:get(index)
    -- index: 1-based (Lua convention) ou 0-based (C)?
    -- Decisão: Usar 1-based no Lua, converter para 0-based em C
    
    if index < 1 or index > self._size then
        error(string.format("Index out of bounds: %d (size=%d)", index, self._size))
    end
    
    local c_index = index - 1  -- Convert to 0-based
    
    if self._dtype == "float64" then
        return C.smaug_f64_get(self._c_struct, c_index)
    elseif self._dtype == "int64" then
        return C.smaug_i64_get(self._c_struct, c_index)
    else
        error("Unsupported dtype: " .. self._dtype)
    end
end

function Series:set(index, value)
    if index < 1 or index > self._size then
        error(string.format("Index out of bounds: %d (size=%d)", index, self._size))
    end
    
    local c_index = index - 1
    
    if self._dtype == "float64" then
        C.smaug_f64_set(self._c_struct, c_index, tonumber(value))
    elseif self._dtype == "int64" then
        C.smaug_i64_set(self._c_struct, c_index, tonumber(value))
    else
        error("Unsupported dtype: " .. self._dtype)
    end
end

function Series:append(value)
    -- Adicionar valor ao final
    if value == nil then
        if self._dtype == "float64" then
            C.smaug_f64_append_null(self._c_struct)
        end
    else
        if self._dtype == "float64" then
            local ret = C.smaug_f64_append(self._c_struct, tonumber(value))
            if ret ~= 0 then
                error("Failed to append value")
            end
        end
    end
end

-- ===== Operações Aritméticas =====

function Series:sum(ignore_na)
    ignore_na = ignore_na or false
    
    if self._dtype == "float64" then
        return C.smaug_f64_sum(self._c_struct, ignore_na)
    elseif self._dtype == "int64" then
        return C.smaug_i64_sum(self._c_struct, ignore_na)
    else
        error("Unsupported dtype for sum: " .. self._dtype)
    end
end

function Series:mean(ignore_na)
    ignore_na = ignore_na or false
    
    if self._dtype == "float64" then
        return C.smaug_f64_mean(self._c_struct, ignore_na)
    else
        error("Unsupported dtype for mean: " .. self._dtype)
    end
end

function Series:min(ignore_na)
    ignore_na = ignore_na or false
    
    if self._dtype == "float64" then
        return C.smaug_f64_min(self._c_struct, ignore_na)
    end
end

function Series:max(ignore_na)
    ignore_na = ignore_na or false
    
    if self._dtype == "float64" then
        return C.smaug_f64_max(self._c_struct, ignore_na)
    end
end

function Series:std(ignore_na)
    ignore_na = ignore_na or false
    
    if self._dtype == "float64" then
        return C.smaug_f64_std(self._c_struct, ignore_na)
    end
end

-- ===== Operadores Metamétodos =====

function Series:__add(other)
    -- self + other
    -- other pode ser uma Series ou um escalar
    
    if type(other) == "number" then
        -- Series + scalar
        local result_c = C.smaug_f64_add_scalar(self._c_struct, other)
        if result_c == nil then error("Addition failed") end
        return Series:new(self._dtype, self._size, result_c.data, result_c.null_mask)
    elseif getmetatable(other) == Series then
        -- Series + Series
        if self._dtype ~= other._dtype then
            error("Cannot add Series of different dtypes")
        end
        if self._size ~= other._size then
            error("Cannot add Series of different sizes")
        end
        
        local result_c = C.smaug_f64_add(self._c_struct, other._c_struct)
        if result_c == nil then error("Addition failed") end
        return Series:new(self._dtype, self._size, result_c.data, result_c.null_mask)
    else
        error("Cannot add Series to type: " .. type(other))
    end
end

function Series:__sub(other)
    -- Análogo a __add
    if type(other) == "number" then
        other = -other
        return self:__add(other)
    else
        -- Implementar series - series via C
        error("Series subtraction not yet implemented")
    end
end

function Series:__mul(other)
    if type(other) == "number" then
        local result_c = C.smaug_f64_mul_scalar(self._c_struct, other)
        if result_c == nil then error("Multiplication failed") end
        return Series:new(self._dtype, self._size, result_c.data, result_c.null_mask)
    else
        error("Series multiplication not yet fully implemented")
    end
end

function Series:__tostring()
    -- Formatar para exibição
    local lines = {}
    table.insert(lines, string.format("Series(%s, dtype=%s, len=%d)", 
        self._name, self._dtype, self._size))
    
    -- Mostrar primeiros 5 e últimos 5 elementos
    local display_count = math.min(5, self._size)
    
    for i = 1, display_count do
        local val = self:get(i)
        table.insert(lines, string.format("  [%d] %s", i - 1, tostring(val)))
    end
    
    if self._size > 2 * display_count then
        table.insert(lines, "  ...")
    end
    
    for i = self._size - display_count + 1, self._size do
        if i > display_count then
            local val = self:get(i)
            table.insert(lines, string.format("  [%d] %s", i - 1, tostring(val)))
        end
    end
    
    return table.concat(lines, "\n")
end

-- ===== Comparações (Boolean Indexing) =====

function Series:gt(threshold)
    -- Greater than: retorna Series[bool]
    if self._dtype ~= "float64" then
        error("Comparison only supported for float64 (for now)")
    end
    
    local mask_ptr_ptr = ffi.new("smaug_mask_t*[1]")
    local bool_array = C.smaug_f64_gt(self._c_struct, threshold, mask_ptr_ptr)
    
    -- Retorna um objeto BoolSeries que encapsula bool_array
    return BoolSeries:new(self._size, bool_array, mask_ptr_ptr[0])
end

function Series:lt(threshold)
    -- Less than
    if self._dtype ~= "float64" then
        error("Comparison only supported for float64 (for now)")
    end
    
    local mask_ptr_ptr = ffi.new("smaug_mask_t*[1]")
    local bool_array = C.smaug_f64_lt(self._c_struct, threshold, mask_ptr_ptr)
    
    return BoolSeries:new(self._size, bool_array, mask_ptr_ptr[0])
end

function Series:eq(threshold)
    -- Equal
    if self._dtype ~= "float64" then
        error("Comparison only supported for float64 (for now)")
    end
    
    local mask_ptr_ptr = ffi.new("smaug_mask_t*[1]")
    local bool_array = C.smaug_f64_eq(self._c_struct, threshold, mask_ptr_ptr)
    
    return BoolSeries:new(self._size, bool_array, mask_ptr_ptr[0])
end

-- ===== Filtração =====

function Series:filter(bool_series)
    -- Retornar nova Series apenas com elementos onde bool_series é true
    if bool_series._dtype ~= "bool" then
        error("Filter requires a BoolSeries")
    end
    
    local count_ptr = ffi.new("size_t[1]")
    local result_c = C.smaug_f64_filter(self._c_struct, bool_series._ptr_data)
    
    if result_c == nil then
        error("Filtering failed")
    end
    
    return Series:new(self._dtype, result_c.size, result_c.data, result_c.null_mask)
end

return Series
```

### 5.3 Classe DataSet (smaug/core/dataset.lua)

```lua
-- smaug/core/dataset.lua

local Series = require("smaug.core.series")
local Indexer = require("smaug.core.indexer")

local DataSet = {}
DataSet.__index = DataSet

function DataSet:new(columns_data)
    -- columns_data: { col1 = Series, col2 = Series, ... }
    
    local obj = {
        _columns = {},      -- { "col1" = Series, ... }
        _col_names = {},    -- Array para manter ordem: { "col1", "col2", ... }
        _dtypes = {},       -- { "col1" = "float64", ... }
        _length = 0,
    }
    setmetatable(obj, self)
    
    -- Adicionar colunas
    for col_name, series in pairs(columns_data) do
        if not obj._columns[col_name] then
            table.insert(obj._col_names, col_name)
        end
        obj._columns[col_name] = series
        obj._dtypes[col_name] = series._dtype
    end
    
    -- Validar comprimento
    local first_length = nil
    for col_name, series in pairs(columns_data) do
        if first_length == nil then
            first_length = series._size
        elseif first_length ~= series._size then
            error(string.format(
                "Column %s has size %d, but expected %d",
                col_name, series._size, first_length
            ))
        end
    end
    
    obj._length = first_length or 0
    return obj
end

-- ===== Metamétodos =====

function DataSet:__index(key)
    -- Sintaxe: df["coluna"] retorna Series
    if type(key) == "string" then
        if self._columns[key] then
            return self._columns[key]
        end
    end
    
    -- Senão, retorna o método
    return DataSet[key]
end

function DataSet:__tostring()
    -- Formatar como tabela ASCII
    local lines = {}
    
    table.insert(lines, string.format("DataSet(%d rows, %d cols)", self._length, #self._col_names))
    table.insert(lines, "")
    
    -- Cabeçalho
    local header = {}
    for _, col_name in ipairs(self._col_names) do
        table.insert(header, col_name)
    end
    table.insert(lines, "  " .. table.concat(header, " | "))
    table.insert(lines, "  " .. string.rep("-", 50))
    
    -- Primeiras 5 linhas
    local display_rows = math.min(5, self._length)
    for row_idx = 1, display_rows do
        local row = {}
        for _, col_name in ipairs(self._col_names) do
            local val = self._columns[col_name]:get(row_idx)
            table.insert(row, tostring(val))
        end
        table.insert(lines, "  " .. table.concat(row, " | "))
    end
    
    if self._length > 2 * display_rows then
        table.insert(lines, "  ...")
    end
    
    return table.concat(lines, "\n")
end

-- ===== CRUD de Colunas =====

function DataSet:add_column(col_name, series)
    if self._length > 0 and series._size ~= self._length then
        error(string.format(
            "Column %s has size %d, but DataSet has %d rows",
            col_name, series._size, self._length
        ))
    end
    
    if not self._columns[col_name] then
        table.insert(self._col_names, col_name)
    end
    
    self._columns[col_name] = series
    self._dtypes[col_name] = series._dtype
    
    if self._length == 0 then
        self._length = series._size
    end
end

function DataSet:drop_column(col_name)
    if not self._columns[col_name] then
        error("Column not found: " .. col_name)
    end
    
    self._columns[col_name] = nil
    self._dtypes[col_name] = nil
    
    -- Remove from _col_names
    for i, name in ipairs(self._col_names) do
        if name == col_name then
            table.remove(self._col_names, i)
            break
        end
    end
end

-- ===== Slicing (loc/iloc) =====

function DataSet:iloc(start_row, end_row)
    -- Retorna novo DataSet com linhas [start_row, end_row]
    -- 1-based indexing, inclusive on both ends
    
    if start_row < 1 or end_row > self._length then
        error("Index out of bounds")
    end
    
    local new_columns = {}
    for col_name, series in pairs(self._columns) do
        -- Usar view ou slice
        local sliced_series = self:_slice_series(series, start_row, end_row)
        new_columns[col_name] = sliced_series
    end
    
    return DataSet:new(new_columns)
end

function DataSet:_slice_series(series, start_row, end_row)
    -- Helper: criar uma nova série com elementos [start_row, end_row]
    local len = end_row - start_row + 1
    local new_series = Series:create_float64(len, series._name)
    
    for i = 1, len do
        new_series:set(i, series:get(start_row + i - 1))
    end
    
    return new_series
end

function DataSet:head(n)
    n = n or 5
    return self:iloc(1, math.min(n, self._length))
end

function DataSet:tail(n)
    n = n or 5
    local start = math.max(1, self._length - n + 1)
    return self:iloc(start, self._length)
end

-- ===== Estatísticas =====

function DataSet:describe()
    -- Retornar resumo estatístico de todas as colunas numéricas
    local stats = DataSet:new({})
    
    for _, col_name in ipairs(self._col_names) do
        local series = self._columns[col_name]
        
        if series._dtype == "float64" then
            local stat_names = { "count", "mean", "std", "min", "25%", "50%", "75%", "max" }
            local stat_values = {
                series._size,
                series:mean(true),
                series:std(true),
                series:min(true),
                -- percentiles não implementados yet
                series:max(true),
            }
            
            -- Criar Series com estatísticas
            local stat_series = Series:create_float64(#stat_values, col_name)
            for i, val in ipairs(stat_values) do
                stat_series:set(i, val)
            end
            stats:add_column(col_name, stat_series)
        end
    end
    
    return stats
end

return DataSet
```

### 5.4 I/O Module (smaug/io/csv.lua)

```lua
-- smaug/io/csv.lua

local Series = require("smaug.core.series")
local DataSet = require("smaug.core.dataset")
local C = require("smaug.ffi_loader")
local ffi = require("ffi")

local CSV = {}

function CSV.read(filename, opts)
    -- opts: { has_header=true, delimiter=",", ... }
    opts = opts or {}
    
    local has_header = opts.has_header ~= false  -- default true
    local delimiter = opts.delimiter or ","
    
    -- Chamar função C
    local csv_table = C.smaug_csv_read(filename, has_header, string.byte(delimiter))
    
    if csv_table == nil then
        error(string.format("Failed to read CSV: %s", filename))
    end
    
    -- Converter para DataSet
    local columns = {}
    
    for col_idx = 0, csv_table.num_cols - 1 do
        local col_name = ffi.string(csv_table.col_names[col_idx])
        local dtype = ffi.string(csv_table.dtypes[col_idx])
        
        -- O ponteiro está em csv_table.columns[col_idx]
        -- Precisa ter sido retornado como um struct específico (f64, i64, etc)
        -- Aqui estamos assumindo que foi pre-cast para smaug_series_f64_t*
        
        local series_ptr = ffi.cast("smaug_series_f64_t*", csv_table.columns[col_idx])
        
        local series = Series:new(dtype, series_ptr.size, series_ptr.data, series_ptr.null_mask, col_name)
        series._c_struct = series_ptr
        
        columns[col_name] = series
    end
    
    local ds = DataSet:new(columns)
    
    -- Limpeza
    C.smaug_csv_table_free(csv_table)
    
    return ds
end

function CSV.write(dataset, filename, opts)
    opts = opts or {}
    
    -- Implementação futuro
    error("CSV.write not yet implemented")
end

return CSV
```

---

## 6. LuaJIT FFI: A Ponte de Performance

### 6.1 Por que LuaJIT FFI?

| Abordagem | Overhead | Tipo Safety | Komplexidade |
|-----------|----------|-------------|--------------|
| **Lua C API** | Alto (conversão stack) | Baixa | Alta |
| **LuaJIT FFI** | Baixo (~1-2% em calls) | Média | Média |
| **Cython (Python)** | Muito Alto | Alta | Muito Alta |

LuaJIT FFI permite:
- **Zero-copy data passing:** Passar ponteiros diretamente, sem serialização
- **Native calls:** Invocar C direto, sem wrapping em Lua
- **JIT compilation:** Código C pode ser inlineado no bytecode Lua compilado

### 6.2 Arquivo de Bindings (smaug/ffi_loader.lua)

```lua
-- smaug/ffi_loader.lua

local ffi = require("ffi")

-- ===== Declarar estruturas C para FFI =====

ffi.cdef([[
    /* Tipos básicos */
    typedef uint8_t smaug_mask_t;
    
    typedef struct {
        const char *name;
        const char *dtype;
        bool is_view;
        bool external_alloc;
    } smaug_metadata_t;
    
    /* ===== Series Float64 ===== */
    typedef struct {
        double *data;
        smaug_mask_t *null_mask;
        size_t size;
        size_t capacity;
        smaug_metadata_t meta;
    } smaug_series_f64_t;
    
    smaug_series_f64_t* smaug_f64_create(size_t size);
    smaug_series_f64_t* smaug_f64_create_with_capacity(size_t size, size_t capacity);
    void smaug_f64_free(smaug_series_f64_t *s);
    smaug_series_f64_t* smaug_f64_clone(const smaug_series_f64_t *s);
    
    double smaug_f64_get(smaug_series_f64_t *s, size_t idx);
    void smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val);
    void smaug_f64_set_null(smaug_series_f64_t *s, size_t idx);
    bool smaug_f64_is_null(smaug_series_f64_t *s, size_t idx);
    
    int smaug_f64_append(smaug_series_f64_t *s, double val);
    int smaug_f64_append_null(smaug_series_f64_t *s);
    
    smaug_series_f64_t* smaug_f64_add(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
    smaug_series_f64_t* smaug_f64_sub(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
    smaug_series_f64_t* smaug_f64_mul(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
    smaug_series_f64_t* smaug_f64_div(const smaug_series_f64_t *a, const smaug_series_f64_t *b);
    
    smaug_series_f64_t* smaug_f64_add_scalar(const smaug_series_f64_t *a, double scalar);
    smaug_series_f64_t* smaug_f64_mul_scalar(const smaug_series_f64_t *a, double scalar);
    
    double smaug_f64_sum(const smaug_series_f64_t *s, bool ignore_na);
    double smaug_f64_mean(const smaug_series_f64_t *s, bool ignore_na);
    double smaug_f64_min(const smaug_series_f64_t *s, bool ignore_na);
    double smaug_f64_max(const smaug_series_f64_t *s, bool ignore_na);
    double smaug_f64_std(const smaug_series_f64_t *s, bool ignore_na);
    
    uint8_t* smaug_f64_gt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_f64_lt(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
    uint8_t* smaug_f64_eq(const smaug_series_f64_t *s, double threshold, smaug_mask_t **out_mask);
    
    smaug_series_f64_t* smaug_f64_filter(const smaug_series_f64_t *s, const uint8_t *mask);
    size_t* smaug_f64_argsort(const smaug_series_f64_t *s, bool ascending);
    smaug_series_f64_t* smaug_f64_sort(const smaug_series_f64_t *s, bool ascending);
    
    /* ===== CSV I/O ===== */
    typedef struct {
        void **columns;
        const char **dtypes;
        const char **col_names;
        size_t num_cols;
        size_t num_rows;
    } smaug_csv_table_t;
    
    smaug_csv_table_t* smaug_csv_read(const char *filename, bool has_header, char delimiter);
    void smaug_csv_table_free(smaug_csv_table_t *tbl);
    
    /* ===== Series Int64 (similar, omitido por brevidade) ===== */
    typedef struct {
        int64_t *data;
        smaug_mask_t *null_mask;
        size_t size;
        size_t capacity;
        smaug_metadata_t meta;
    } smaug_series_i64_t;
    
    smaug_series_i64_t* smaug_i64_create(size_t size);
    void smaug_i64_free(smaug_series_i64_t *s);
    int64_t smaug_i64_get(smaug_series_i64_t *s, size_t idx);
    void smaug_i64_set(smaug_series_i64_t *s, size_t idx, int64_t val);
    int64_t smaug_i64_sum(const smaug_series_i64_t *s, bool ignore_na);
]])

-- ===== Carregar biblioteca compilada =====

-- Detectar SO
local lib_name
if ffi.os == "Windows" then
    lib_name = "smaug_math.dll"
elseif ffi.os == "OSX" then
    lib_name = "libsmaug_math.dylib"
else  -- Linux
    lib_name = "libsmaug_math.so"
end

-- Procurar biblioteca em caminhos conhecidos
local lib_paths = {
    "./lib/" .. lib_name,
    "./build/lib/" .. lib_name,
    "/usr/local/lib/" .. lib_name,
    "/usr/lib/" .. lib_name,
    lib_name,  -- Sistema vai procurar em LD_LIBRARY_PATH
}

local C = nil
for _, path in ipairs(lib_paths) do
    local ok, result = pcall(function() return ffi.load(path) end)
    if ok then
        C = result
        break
    end
end

if not C then
    error(string.format(
        "Failed to load smaug_math library. Tried: %s",
        table.concat(lib_paths, ", ")
    ))
end

return C
```

### 6.3 Garbage Collection Bridge

Um ponto crítico: LuaJIT FFI não automatically limpa memória C. Precisamos usar `ffi.gc()`:

```lua
-- Em Series:create_float64()

function Series:create_float64(size, name)
    local c_series = C.smaug_f64_create(size)
    if c_series == nil then
        error("Failed to allocate Series")
    end
    
    -- Registrar destrutor
    -- Quando `c_series` for coletado pelo GC, chama smaug_f64_free
    ffi.gc(c_series, C.smaug_f64_free)
    
    -- ... resto da construção ...
    
    return series
end
```

**Cuidado:** `ffi.gc()` pode ser lento se usado em hot paths. Para construções em massa, considerar agrupar allocations em um array e liberar tudo de uma vez.

---

## 7. Estruturas de Dados Detalhadas

### 7.1 Null Handling: Bitmask vs NaN

**Abordagem escolhida: Array paralelo de `uint8_t` (bitmask simples)**

```c
/* Convenção:
   null_mask[i] == 0xFF (255): valor válido
   null_mask[i] == 0x00 (0):   valor nulo (NA)
*/
```

**Por que não usar bit-packing (1 bit por valor)?**
- Complexidade aumenta (bitwise operations)
- Cache misses aumentam
- Ganho de RAM marginal (8x menor, mas acesso mais lento)

**Por que não usar NaN para floats?**
- `NaN` só existe em floats
- Inteiros não têm representação nativa
- Strings não podem usar NaN

**Implementação de Get/Set com nulos:**

```c
double smaug_f64_get(smaug_series_f64_t *s, size_t idx) {
    if (s->null_mask[idx] == 0x00) {
        return NAN;  /* Retornar NaN para indicar NA */
    }
    return s->data[idx];
}

void smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val) {
    s->data[idx] = val;
    s->null_mask[idx] = 0xFF;  /* Marcar como válido */
}

void smaug_f64_set_null(smaug_series_f64_t *s, size_t idx) {
    s->null_mask[idx] = 0x00;
    s->data[idx] = 0.0;  /* Limpar dados, optional */
}
```

### 7.2 Variabilidade de Tamanhos: Capacity vs Size

Em Lua/Python, arrays podem crescer dinamicamente. Smaug suporta isso via:

```c
typedef struct {
    double *data;
    size_t size;      /* Elementos usados */
    size_t capacity;  /* Elementos alocados */
} smaug_series_f64_t;
```

**Estratégia de reallocação (similar a `std::vector`):**

```c
int smaug_f64_append(smaug_series_f64_t *s, double val) {
    if (s->size >= s->capacity) {
        /* Crescimento exponencial: capacity *= 1.5 */
        size_t new_capacity = s->capacity * 3 / 2;
        if (new_capacity <= s->capacity) new_capacity = s->capacity + 1;
        
        double *new_data = realloc(s->data, new_capacity * sizeof(double));
        if (!new_data) return -1;  /* OOM */
        
        smaug_mask_t *new_mask = realloc(s->null_mask, new_capacity);
        if (!new_mask) {
            free(new_data);
            return -1;
        }
        
        s->data = new_data;
        s->null_mask = new_mask;
        s->capacity = new_capacity;
    }
    
    s->data[s->size] = val;
    s->null_mask[s->size] = 0xFF;
    s->size++;
    
    return 0;
}
```

### 7.3 Enum de Tipos (Para Dispatch)

Para suportar múltiplos tipos sem C11 `_Generic()`, usar enum dispatch:

```c
/* Em smaug_core.h */

typedef enum {
    SMAUG_DTYPE_FLOAT64 = 0,
    SMAUG_DTYPE_INT64 = 1,
    SMAUG_DTYPE_BOOL = 2,
    SMAUG_DTYPE_STRING = 3,  /* Futuro */
} smaug_dtype_t;

/* Struct genérico */
typedef struct {
    void *data;
    smaug_mask_t *null_mask;
    size_t size;
    size_t capacity;
    smaug_dtype_t dtype;
} smaug_series_generic_t;

/* Ou usar union para type safety */
typedef union {
    smaug_series_f64_t *f64;
    smaug_series_i64_t *i64;
    /* ... */
} smaug_series_ptr_t;
```

### 7.4 String Handling: Dictionary Encoding

Para evitar overhead de ponteiros de strings:

```c
/* Representação 1: Array de ponteiros (simples, mais lento) */
typedef struct {
    char **strings;        /* Array de ponteiros para strings */
    size_t *lengths;       /* Comprimento de cada string */
    size_t size;
} smaug_series_string_simple_t;

/* Representação 2: Dictionary encoding (otimizado) */
typedef struct {
    int64_t *indices;           /* Referências para dicionário (0, 1, 2, ...) */
    char **dictionary;          /* Valores únicos ("SP", "RJ", "MG") */
    size_t dict_size;
    size_t series_size;
} smaug_series_string_categorical_t;
```

**Dictionary encoding é 100-1000x mais rápido para:**
- Agrupamentos (GroupBy)
- Comparações
- Memória (se dict_size << series_size)

---

## 8. Gerenciamento de Memória

### 8.1 Estratégia de Allocação

| Fase | Estratégia | Motivo |
|------|-----------|--------|
| **Inicialização** | `malloc` com size exato | Fácil, previsível |
| **Append** | Realloc com fator 1.5x | Evita reallocations frequentes |
| **Slicing** | View (sem cópia) se possível | Performance |
| **Operações binárias** | Sempre cria novo | Imutabilidade |

### 8.2 Memory Leak Prevention

**Checklist:**
- [ ] Todos os `malloc` têm um `free` correspondente
- [ ] Funções que retornam `NULL` em erro são tratadas pelo caller
- [ ] `ffi.gc()` é chamado para cada struct C retornado ao Lua
- [ ] Testes com valgrind (Linux):
  ```bash
  valgrind --leak-check=full ./test_alloc
  ```

**Exemplo: Implementar função com cleanup correto**

```c
smaug_series_f64_t* smaug_f64_add(const smaug_series_f64_t *a, const smaug_series_f64_t *b) {
    if (!a || !b) return NULL;
    if (a->size != b->size) return NULL;
    
    /* Alocar resultado */
    smaug_series_f64_t *result = smaug_f64_create(a->size);
    if (!result) return NULL;  /* malloc falhou */
    
    /* Operação */
    for (size_t i = 0; i < a->size; i++) {
        if (a->null_mask[i] && b->null_mask[i]) {
            result->data[i] = a->data[i] + b->data[i];
            result->null_mask[i] = 0xFF;
        } else {
            result->null_mask[i] = 0x00;
        }
    }
    
    return result;  /* Caller é responsável por free (via ffi.gc no Lua) */
}
```

### 8.3 SIMD e Cache Optimization

**Data Layout:** Manter arrays contíguos para cache friendliness.

**Loop Optimization:**

```c
/* Versão 1: Safe, sem SIMD */
for (size_t i = 0; i < size; i++) {
    sum += data[i];
}

/* Versão 2: Com restrict pointer (ajuda compilador) */
double smaug_f64_sum_fast(const double *restrict data, size_t size) {
    double sum = 0.0;
    for (size_t i = 0; i < size; i++) {
        sum += data[i];
    }
    return sum;
}

/* Compilar com: gcc -O3 -march=native -ffast-math
   O compilador pode gerar instruções SIMD automaticamente */
```

---

## 9. Roadmap Faseado

### FASE 1: O Alicerce (Engine C & FFI) ⚙️

**Duração estimada:** 2-3 semanas

#### 1.1 Setup do Projeto C
- [ ] Criar estrutura de diretórios (`src/`, `tests/`, `build/`)
- [ ] Escrever `CMakeLists.txt` com suporte Linux/Windows/macOS
- [ ] Configurar compilador flags para O3 optimization
- [ ] Criar Makefile alternativo (simples) para quick builds

**Testes:**
```bash
mkdir build && cd build
cmake ..
make -j4
./bin/test_alloc  # Deve passar
```

#### 1.2 Structs Iniciais
- [ ] Implementar `smaug_series_f64_t` com getters/setters básicos
- [ ] Implementar `smaug_series_i64_t` análogo
- [ ] Usar `smaug_mask_t` array paralelo para nulos
- [ ] Escrever `smaug_f64_create()` e `smaug_f64_free()`

**Checklist:**
- [ ] Array contíguo (não fragmentado)
- [ ] Bitmask para nulos
- [ ] Metadados (name, dtype)

#### 1.3 Gestão de Memória
- [ ] Testar `malloc` e `free` com Valgrind
- [ ] Implementar `append` com reallocation dinâmica
- [ ] Escrever testes unitários para memory leak

**Test case:**
```c
void test_memory_safety() {
    smaug_series_f64_t *s = smaug_f64_create(100);
    for (int i = 0; i < 100; i++) {
        smaug_f64_append(s, (double)i);
    }
    smaug_f64_free(s);
    /* Valgrind deve passar sem leaks */
}
```

#### 1.4 Bindings LuaJIT
- [ ] Instalar LuaJIT (ou usar Lua 5.1 com LuaJIT)
- [ ] Escrever `ffi_loader.lua` com `ffi.cdef()` completo
- [ ] Implementar `ffi.load()` com fallback para paths múltiplos
- [ ] Testar carregamento básico

**Script Lua:**
```lua
local C = require("smaug.ffi_loader")
local series = C.smaug_f64_create(10)
assert(series ~= nil)
C.smaug_f64_free(series)
print("FFI loading works!")
```

#### 1.5 Garbage Collector Bridge
- [ ] Implementar `Series:create_float64()` com `ffi.gc()` hook
- [ ] Verificar que GC do Lua libera memória C corretamente
- [ ] Testar com múltiplas alocações/coletas

**Test:**
```lua
for i = 1, 10000 do
    local s = Series:create_float64(1000)
    -- s sairá de escopo, GC deve liberar
end
collectgarbage("collect")
-- Usar externa ferramenta para monitorar pss/rss
```

**Deliverables Fase 1:**
- libsmaug_math.so compilado e testado
- FFI bindings funcionais
- Zero memory leaks confirmados

---

### FASE 2: A Classe Series (1D) 📊

**Duração estimada:** 2 semanas

#### 2.1 Construtor
- [ ] Implementar `Series:new()` em Lua
- [ ] Implementar `Series:create_float64()` factory
- [ ] Adicionar validação de argumentos
- [ ] Suporte para `Series:create_int64()`

#### 2.2 Metamétodos Aritméticos
- [ ] `__add`: Series + Series, Series + scalar
- [ ] `__sub`: Series - Series, Series - scalar
- [ ] `__mul`: Series * scalar, Series * Series
- [ ] `__div`: Series / scalar, Series / Series
- [ ] Testes com numpy para validar resultados

**Test case (Lua):**
```lua
local s1 = Series:create_float64(10, "s1")
for i = 1, 10 do s1:set(i, i) end

local s2 = Series:create_float64(10, "s2")
for i = 1, 10 do s2:set(i, i * 2) end

local s3 = s1 + s2
assert(s3:get(1) == 3)  -- 1 + 2
assert(s3:get(5) == 15) -- 5 + 10
```

#### 2.3 Reduções e Estatísticas
- [ ] Implementar C functions: `smaug_f64_sum()`, `smaug_f64_mean()`, etc.
- [ ] Encapsular em Lua: `Series:sum()`, `Series:mean()`, etc.
- [ ] Tratamento de nulos obrigatório (parâmetro `ignore_na`)
- [ ] Testes contra Pandas

**C implementation pattern:**
```c
double smaug_f64_mean(const smaug_series_f64_t *s, bool ignore_na) {
    double sum = smaug_f64_sum(s, ignore_na);
    size_t count = smaug_f64_count_nonnull(s);
    if (count == 0) return NAN;
    return sum / count;
}
```

#### 2.4 Inspeção Visível
- [ ] Implementar `Series:__tostring()`
- [ ] Exibir primeiros/últimos 5 elementos
- [ ] Mostrar dtype, nome, tamanho
- [ ] Pretty-format para números grandes

**Output esperado:**
```
Series(edad, dtype=float64, len=1000)
  [0] 25.5
  [1] 30.2
  [2] 28.9
  [3] 22.1
  [4] 35.7
  ...
  [995] 29.3
  [996] 31.0
  [997] 27.5
  [998] 33.2
  [999] 26.8
```

**Deliverables Fase 2:**
- Classe Series completa com aritméticas
- Todas as reduções (sum, mean, min, max, std, var)
- Testes validados contra numpy
- Documentação de API

---

### FASE 3: A Classe DataSet (2D) 📈

**Duração estimada:** 2 semanas

#### 3.1 Estrutura Colunar
- [ ] Implementar `DataSet:new()` aceitando dicionário de Series
- [ ] Validar que todas as colunas têm mesmo tamanho
- [ ] Manter ordem das colunas (`_col_names`)
- [ ] Cache de metadados (dtype por coluna)

#### 3.2 CRUD de Colunas
- [ ] `DataSet:add_column(name, series)`
- [ ] `DataSet:drop_column(name)`
- [ ] `DataSet:rename_column(old_name, new_name)`
- [ ] Testes para validação de constraints

#### 3.3 Slicing Básico
- [ ] `df["colname"]` retorna Series (metamétodo `__index`)
- [ ] `df:iloc(start, end)` corta por índice
- [ ] `df:head(n)` primeiras n linhas
- [ ] `df:tail(n)` últimas n linhas
- [ ] `df:sample(n)` amostra aleatória

**Test case:**
```lua
local df = DataSet:new({
    idade = Series(...),
    salario = Series(...),
})

local idade_col = df["idade"]
assert(idade_col._dtype == "float64")

local primeiro_cinco = df:head(5)
assert(primeiro_cinco._length == 5)
```

#### 3.4 Impressão Tabular
- [ ] Formatar DataSet como tabela ASCII
- [ ] Alinhar colunas dinamicamente
- [ ] Truncar strings longas
- [ ] Mostrar primeiras/últimas 5 linhas

**Output esperado:**
```
DataSet(100 rows, 3 cols)
  idade | nome           | salario
  ------|----------------|----------
  25    | João Silva     | 3000.50
  30    | Maria Costa    | 3500.00
  ...
  29    | Pedro Santos   | 3250.00
  31    | Ana Oliveira   | 3600.00
```

**Deliverables Fase 3:**
- Classe DataSet operacional
- Slicing e acesso por coluna
- Formatação tabularde qualidade production
- Testes contra Pandas

---

### FASE 4: Filtros e Máscaras 🔍

**Duração estimada:** 1.5 semanas

#### 4.1 Series Booleanas
- [ ] Tipo `smaug_series_bool_t` em C
- [ ] Classe `BoolSeries` em Lua
- [ ] Construtor e métodos básicos

#### 4.2 Operadores Lógicos
- [ ] Implementar C functions: `smaug_f64_gt()`, `smaug_f64_lt()`, `smaug_f64_eq()`, etc.
- [ ] Encapsular em Lua: `Series:gt(val)`, `Series:lt(val)`, etc.
- [ ] Suporte para operadores lógicos: `&` (AND), `|` (OR), `~` (NOT)
- [ ] Testes contra Pandas boolean indexing

**Test case:**
```lua
local salarios = Series:create_float64(5)
salarios:set(1, 3000)
salarios:set(2, 5000)
salarios:set(3, 2500)
salarios:set(4, 4000)
salarios:set(5, 3500)

local mask = salarios:gt(3500)  -- Retorna BoolSeries
-- mask deve ser [false, true, false, true, false]
```

#### 4.3 Filtragem no DataSet
- [ ] `DataSet:filter(bool_series)` retorna novo DataSet apenas com linhas true
- [ ] Validar que bool_series tem mesmo tamanho do DataSet
- [ ] Testes combinados (filtro + seleção de coluna)

**Test case:**
```lua
local mask = df["salario"]:gt(3000)
local df_filtered = df:filter(mask)
assert(df_filtered._length < df._length)
```

**Deliverables Fase 4:**
- Series booleanas completas
- Operadores de comparação
- Filtragem no DataSet
- Testes validados

---

### FASE 5: Input / Output 💾

**Duração estimada:** 2.5 semanas

#### 5.1 Leitor CSV em C (CRÍTICA)
- [ ] Implementar parser CSV com suporte a:
  - [ ] Header detection
  - [ ] Type inference (int, float, string, bool)
  - [ ] Delimitadores customizáveis
  - [ ] Quoted fields (com aspas)
  - [ ] Escaped quotes
  - [ ] Empty/NA values
- [ ] Testes com arquivos diversos (do pandas/sklearn)
- [ ] Validar resultados contra Pandas read_csv

**CSV test file:**
```
age,name,salary
25,"Silva, João",3000.50
30,"Costa, Maria",3500.00
40,"Oliveira, Pedro",4000.00
```

**Estratégia de tipo inference:**
```
Coluna "age": "25", "30", "40" → int64
Coluna "salary": "3000.50", "3500.00" → float64
Coluna "name": strings → string
```

#### 5.2 Escritor CSV
- [ ] Implementar `CSV:write(dataset, filename)`
- [ ] Preservar tipos (não converter tudo para string)
- [ ] Header output
- [ ] Escaped quotes/newlines

#### 5.3 JSON I/O (Bonus)
- [ ] Leitor JSON básico (se time permitir)
- [ ] Array of objects → DataSet
- [ ] Escritor DataSet → JSON

**Deliverables Fase 5:**
- CSV reader/writer robusto
- Type inference automático
- Testes com datasets reais
- Documentação de API

---

### FASE 6: Operações Avançadas 🚀

**Duração estimada:** 3+ semanas (pós-MVP)

#### 6.1 GroupBy
- [ ] Implementar `DataSet:groupby(col_name)`
- [ ] Retornar objeto `GroupBy` que suporta agregações
- [ ] Agregações: sum, mean, count, min, max, std
- [ ] Validar contra Pandas groupby

**Example:**
```lua
local df = load_data()
local grouped = df:groupby("departamento")
local salarios_medio = grouped["salario"]:mean()
```

#### 6.2 Joins (Merge)
- [ ] Implementar inner join, left join, outer join
- [ ] Otimizar com hash table em C
- [ ] Validar resultados

#### 6.3 Tipos Complexos
- [ ] Suporte robusto a strings (não apenas categorical)
- [ ] DateTime support (int64 Unix timestamp)
- [ ] Timedelta

**Deliverables Fase 6:**
- GroupBy operacional
- Merge/joins funcionando
- Tipos complexos suportados

---

### FASE 7: Recursos Avançados (Futuro)

- Resample (Time Series)
- Window functions (rolling, expanding)
- Pivot tables
- Plotting integrado
- Lazy evaluation + query compilation
- Distributed execution (se escopo permitir)

---

## 10. Decisões de Design Críticas

### 10.1 Imutabilidade vs Mutação In-place

**Decisão:** Imutabilidade por padrão (como Pandas com `copy=True`).

**Justificativa:**
- Evita bugs sutis de aliasing
- Facilita reasoning sobre código
- FFI calls são rápidos; cópia de memória é o overhead dominante, não a operação em si

**Exceção:** Views (§7.1) não copiam, mas são read-only.

### 10.2 1-based vs 0-based Indexing

**Decisão:** 1-based no Lua (convenção), 0-based internamente em C.

```lua
-- Lua
local val = series:get(1)  -- Primeiro elemento

-- C
double smaug_f64_get(smaug_series_f64_t *s, size_t idx)  // idx=0 é primeiro
```

### 10.3 Error Handling Strategy

**Abordagem:**
1. **Validação em Lua** (tipo, tamanho, limites) → lança Lua `error()`
2. **Operações C críticas** → retornam NULL ou código de erro
3. **FFI calls** → checam retorno NULL antes de usar

**Nunca** permitir segfault silencioso.

### 10.4 NA/NULL Representation

**Decisão:** Bitmask + NaN para floats, 0x00 para inteiros.

```lua
-- Lua: get retorna nil ou número
local val = series:get(5)
if val == nil then print("NA") end
```

### 10.5 Type Coercion

**Regra simples:**
- int + int → int
- int + float → float
- float + float → float
- **Nunca** coerce para string automaticamente (erro explícito)

---

## 11. Benchmarking e Performance

### 11.1 Métricas Alvo

| Operação | Alvo | Baseline (NumPy) |
|----------|------|---|
| `sum(1M floats)` | < 5ms | 1ms |
| `mean(1M floats)` | < 10ms | 2ms |
| `Series + Series (1M)` | < 20ms | 5ms |
| `filter(1M bool)` | < 15ms | 3ms |
| `CSV read (100K rows)` | < 500ms | 50ms |

**Overhead esperado:** 3-5x vs NumPy (aceitável para MVP).

### 11.2 Ferramenta de Profiling

**Linux/macOS:**
```bash
perf record -g ./my_benchmark
perf report
```

**Windows:**
Usar Visual Studio Profiler ou cmake-enable instrumentation.

### 11.3 Testes de Escalabilidade

Testar com datasets crescentes: 1K, 10K, 100K, 1M, 10M linhas.

```lua
-- bench/scale_test.lua
local smaug = require("smaug")

for _, size in ipairs({1000, 10000, 100000, 1000000}) do
    local s = Series:create_float64(size)
    for i = 1, size do
        s:set(i, math.random())
    end
    
    local t0 = os.time()
    local sum = s:sum()
    local elapsed = os.time() - t0
    
    print(string.format("sum(%d): %.3f seconds", size, elapsed))
end
```

---

## 12. Mitigação de Riscos

### 12.1 Riscos Técnicos

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---|---|---|
| **Segmentation fault silencioso via FFI** | Alta | Crítico | Validação rigorosa em Lua; FFI debugging tools |
| **Memory leak em C** | Média | Alto | Valgrind CI; code review obrigatório |
| **Parser CSV com edge cases** | Alta | Médio | Test-driven com datasets reais; coverage 100% |
| **Performance não atinge alvo** | Média | Médio | Profiling early; otimizações incrementais |
| **LuaJIT incompatibilidade** | Baixa | Alto | Testar em múltiplas versões; fallback Lua 5.1 |

### 12.2 Plano de Ação para Segmentation Faults

1. **Debug FFI:**
   ```lua
   local ok, err = pcall(C.smaug_f64_sum, nil_ptr, false)
   if not ok then print("Error caught:", err) end
   ```

2. **Valgrind com LuaJIT:**
   ```bash
   valgrind --suppressions=/path/to/luajit.supp ./luajit test.lua
   ```

3. **AddressSanitizer (ASan):**
   ```bash
   gcc -fsanitize=address -g test.c
   ```

### 12.3 Critério de Definição de "Concluído"

Uma fase é concluída quando:
- [ ] Todos os features estão implementados
- [ ] Testes unitários passam (100%)
- [ ] Testes de regressão contra Pandas/NumPy passam
- [ ] Zero memory leaks (Valgrind)
- [ ] Documentação atualizada
- [ ] Benchmarks executados e documentados

---

## Apêndice A: Ambiente de Desenvolvimento Recomendado

### A.1 Linux (Fedora/Ubuntu)

```bash
# Dependências
sudo dnf install cmake gcc valgrind luajit luajit-devel git

# Build
mkdir -p smaug/build
cd smaug/build
cmake ..
make -j$(nproc)
make test

# FFI testing
luajit ../tests/ffi_basic.lua
```

### A.2 Windows

- Instalar MSVC Build Tools ou MinGW
- CMake com Visual Studio generator
- LuaJIT Windows binaries

### A.3 macOS

```bash
brew install cmake luajit valgrind
# Resto similar a Linux
```

---

## Apêndice B: Referências e Recursos

### B.1 Documentação Externa

- [LuaJIT FFI Documentation](http://luajit.org/ext_ffi.html)
- [Pandas Documentation](https://pandas.pydata.org/docs/)
- [NumPy C API](https://numpy.org/doc/stable/reference/c-api.html)
- [C11 Standard](https://en.cppreference.com/w/c)

### B.2 Projetos Similares

- **lualib** (Lua data frame library, abandonado)
- **torch** (scientific computing in Lua, 2012)
- **gnuplot** via Lua bindings

### B.3 Performance References

- *Computer Architecture: A Quantitative Approach* (SIMD, cache optimization)
- *Effective C* (Scott Meyers-like resource para C)
- LuaJIT implementation papers

---

## Changelog

| Versão | Data | Mudanças |
|--------|------|----------|
| 1.0 | 2026-05-18 | Documentação inicial e roadmap completo |

---

**FIM DO DOCUMENTO**

---

## Notas Finais para o Desenvolvedor (Gui)

Este documento foi estruturado como uma **roadmap de engenharia real**, não um esboço. Cada seção contém:

1. **Especificações técnicas concretas** (não vagas)
2. **Exemplos de código** (pseudo-código compilável)
3. **Testes claros** (como validar cada feature)
4. **Mitigação de riscos** (evitar pitfalls comuns)
5. **Estimativas de tempo** (em semanas)

### Como Usar Este Documento:

- **Semana 1:** Ler integralmente (especialmente §1-3, §9)
- **Durante desenvolvimento:** Referência contínua para detalhe técnico
- **Code reviews:** Checklist da seção relevante (ex: §8.2 para memory leaks)
- **Decisões de design:** Consultar §10 antes de desviar do plano

### Próximos Passos Imediatos:

1. **Criar repositório Git** com estrutura de FASE 1
2. **Instalar LuaJIT FFI** e validar carregamento
3. **Escrever struct base** (`smaug_series_f64_t`) em C
4. **Teste sanity:** Alocar, preencher, liberar sem leaks
5. **Commit** com mensagem "PHASE1.1: Initial C structures and memory management"

**Boa sorte com Smaug!** 🚀
