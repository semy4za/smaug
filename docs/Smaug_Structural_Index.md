# 🐉 Smaug: Índice Estrutural e Arquitetural
## Mapa Completo de Módulos, Componentes e Responsabilidades

**Propósito:** Referência da estrutura COMPLETA de Smaug, explicando lógica, justificativas e organização. Complemento à Documentação Técnica.

---

## 📋 Índice

1. [Filosofia Arquitetural](#1-filosofia-arquitetural)
2. [Backend C - Organização Geral](#2-backend-c---organização-geral)
3. [Módulo Math (Operações Numéricas)](#3-módulo-math-operações-numéricas)
4. [Módulo Core (Alocação e Gerenciamento)](#4-módulo-core-alocação-e-gerenciamento)
5. [Módulo Ops F64 (Float64)](#5-módulo-ops-f64-float64)
6. [Módulo Ops I64 (Int64)](#6-módulo-ops-i64-int64)
7. [Módulo Ops Bool (Booleano)](#7-módulo-ops-bool-booleano)
8. [Módulo I/O - CSV (Fase 5)](#8-módulo-io---csv-fase-5)
9. [Módulo I/O - JSON (Fase 5+)](#9-módulo-io---json-fase-5)
10. [Módulo I/O - SQL (Fase 6+)](#10-módulo-io---sql-fase-6)
11. [Tipos Futuros (String, Categorical, DateTime)](#11-tipos-futuros-string-categorical-datetime)
12. [Frontend Lua - Organização Geral](#12-frontend-lua---organização-geral)
13. [Classe Series](#13-classe-series)
14. [Classe DataSet](#14-classe-dataset)
15. [Classe Indexer](#15-classe-indexer)
16. [Classe GroupBy](#16-classe-groupby)
17. [FFI Bridge](#17-ffi-bridge)
18. [Módulo I/O Lua](#18-módulo-io-lua)
19. [Testes e Validação](#19-testes-e-validação)

---

## 1. Filosofia Arquitetural

### 1.1 Princípios Fundamentais

**Separação de Responsabilidades Clara:**
- **Backend C:** Operações numéricas puras, memory management, performance crítica
- **Frontend Lua:** API expressiva, usabilidade, metamétodos, lógica de alto nível
- **FFI Bridge:** Translação entre mundos, sem lógica de negócio

**Imutabilidade por Padrão:**
- Operações retornam novas séries, nunca modificam in-place
- Evita aliasing bugs, facilita reasoning
- Views são exceção (apenas leitura otimizada)

**Type Safety:**
- Cada tipo (f64, i64, bool, string) tem implementação própria
- Sem casting implícito, sem union types genéricos
- Erro de tipo detectado em tempo de FFI call

**Memory Ownership:**
- Backend C: aloca e libera sua memória
- Frontend Lua: usa `ffi.gc()` para auto-cleanup
- Views têm flag de "external_alloc" para evitar double-free

**Performance como Requisito:**
- Backend C: loops SIMD-friendly, compilador pode vetorizar
- FFI: zero-copy data passing (não converte entre stack Lua)
- Lazy evaluation: (futuro) operações podem ser compiladas em kernels

---

## 2. Backend C - Organização Geral

### 2.1 Estrutura de Diretórios

```
smaug/include/          ← Headers públicos
smaug/src/              ← Implementação C
smaug/lua/smaug/        ← Frontend Lua
smaug/tests/            ← Testes
```

### 2.2 Headers Públicos

**`include/smaug_types.h`**
- Propósito: Definir tipos base (structs, typedefs, constantes)
- Conteúdo: `smaug_mask_t`, `smaug_metadata_t`, enums de dtype
- Inclusão: Incluído por todos outros headers
- Razão de existir: Evitar forward declarations circulares, centralizar tipos

**`include/smaug_math.h`**
- Propósito: Declarar todas as funções matemáticas e de operação
- Conteúdo: Assinaturas de funções (create, free, add, sum, etc)
- Inclusão: Incluído pela implementação C e FFI Lua
- Razão de existir: Interface pública, contrato entre C e Lua

### 2.3 Princípio: Separação Math vs I/O

**Por que não misturar:**
- CSV parsing é **I/O**, não matemática
- I/O pode falhar (file not found, format error) diferente de ops math
- I/O muda frequentemente, math é estável
- Permite desenvolver I/O independentemente (Fase 5 vs Fase 1)
- Testes podem validar math sem dependência de I/O

**Implicação:**
- `smaug_math.h` contém APENAS operações (create, free, add, sum, etc)
- `smaug_io.h` (não no math header) conterá CSV, JSON, SQL
- Cada tipo de I/O em seu próprio arquivo (`smaug_csv.c`, `smaug_json.c`, etc)

---

## 3. Módulo Math (Operações Numéricas)

### 3.1 O que é

Coleção de **funções de operação** (não alocação) sobre séries já alocadas:
- Aritméticas: add, sub, mul, div (dois operandos)
- Escalares: add_scalar, mul_scalar (operando + escalar)
- Reduções: sum, mean, min, max, std, var
- Comparações: gt, lt, eq (retornam bool array)
- Transformações: sqrt, log, exp, abs, round

### 3.2 Organização em Submodelos

**3.2.1 Operações Float64 (`smaug_ops_f64.c`)**
- Quantas funções: ~40 funções
- Quais categorias: aritméticas (6), escalares (4), reduções (8), comparações (6), transformações (8), utilitários (2)
- Propósito: Todas operações com `double` e `smaug_series_f64_t`
- Por que arquivo separado: Permite compilar otimizações específicas para float (AVX2, etc)
- Padrão: Se um operando é f64 e outro é escalar, resultado é f64

**3.2.2 Operações Int64 (`smaug_ops_i64.c`)**
- Quantas funções: ~35 funções
- Quais categorias: análogas a f64, com ajustes (sum/min/max retornam int64, mean/std retornam double)
- Propósito: Operações com `int64_t` e `smaug_series_i64_t`
- Por que arquivo separado: int64 não precisa de SIMD floating-point, compilação separada
- Diferença crucial: mean/std/var retornam double (podem ter decimais), sum/min/max retornam int64

**3.2.3 Operações Bool (`smaug_ops_bool.c` - Fase 4)**
- Quantas funções: ~15 funções
- Quais categorias: lógicas (and, or, not, xor), reduções (count_true, any, all)
- Propósito: Operações lógicas e aggregate booleanas
- Por que arquivo separado: Bool é tipo especial, operações são lógicas não aritméticas

### 3.3 Null Handling em Operações

**Estratégia uniforme:**
- Comparação com `null_mask`: se um operando é nulo, resultado é nulo
- Reduções: se `ignore_na=false` e há nulo, retorna NAN
- Operações escalares: nulo em um lado → nulo no resultado
- Transformações (sqrt, log): nulo → nulo

**Implementação:**
- Cada função verifica `null_mask[i] != 0xFF` antes de usar `data[i]`
- Sem exceções, comportamento previsível

### 3.4 Por que não misturar f64 e i64

- Coerção automática pode esconder bugs
- Type safety: força user a decidir explicitamente
- Performance: sem overhead de conversão no loop
- Compatibilidade: diferentes semânticas (int modulo, float precision)

---

## 4. Módulo Core (Alocação e Gerenciamento)

### 4.1 O que é

Funções de **ciclo de vida** de séries:
- Criação: `create()`, `create_with_capacity()`, `create_from_array()`
- Destruição: `free()`
- Clonagem: `clone()` (deep copy)
- Views: `view()` (slice sem cópia)

### 4.2 Arquivo: `smaug_core.c`

**Quantas funções:** ~12 (3 create + free + clone + view, **por tipo**)
- f64 create, f64 free, f64 clone, f64 view (4)
- i64 create, i64 free, i64 clone, i64 view (4)
- bool create, bool free (2)
- Internals: realloc helper, metadata init (2)

**Propósito:** Gerenciar lifecycle de todos os tipos de série
- Alocar com segurança (check retorno NULL)
- Inicializar metadados e null_mask
- Implementar grow strategy para append (capacity *= 1.5)
- Suportar views (ponteiros para subarray sem cópia)

**Por que arquivo separado:**
- Core memory management é crítico, muda pouco
- Pode ser incluído em bibliotecas que só precisam de create/free
- Testes de alocação isolados aqui

### 4.3 Grow Strategy (Importante)

**Quando append precisa crescer:**
```
size >= capacity
→ new_capacity = capacity + (capacity >> 1)  // *= 1.5
→ realloc(data, new_capacity)
→ realloc(null_mask, new_capacity)
```

**Por que 1.5x:**
- 1.5x é meio-termo (2x desperdicia RAM, 1.1x realoca demais)
- Com N appends: ~1.5x memória total (50% waste)
- Melhor cache locality que 2x

**Invariante crítico:**
- Sempre: `size <= capacity`
- Se realloc falha: return -1, série fica num estado inconsistente (caller responsável)

---

## 5. Módulo Ops F64 (Float64)

### 5.1 Categorização de Funções

**5.1.1 Aritméticas (2 operandos)**
- `add`, `sub`, `mul`, `div`
- Cada uma: aloca nova série, loop com null check
- Retorna NULL se tamanhos diferentes

**5.1.2 Escalares (operando + número)**
- `add_scalar`, `sub_scalar`, `mul_scalar`, `div_scalar`, `rsub_scalar`, `rdiv_scalar`
- Última duas (rsub, rdiv): `scalar - a`, `scalar / a`
- Úteis para operações não-comutativas

**5.1.3 Reduções (série → valor)**
- `sum`, `mean`, `min`, `max`, `median`, `std`, `var`, `quantile`
- Cada uma: itera série, respeita `ignore_na` flag
- `quantile()`: requer sorting (futuro: QuickSelect para eficiência)

**5.1.4 Comparações (série → bool array)**
- `gt`, `lt`, `eq`, `ge`, `le`, `ne`
- Retornam `uint8_t*` (array novo, caller libera)
- Usado para boolean indexing em DataSet

**5.1.5 Transformações (série → nova série)**
- `abs`, `sqrt`, `log`, `exp`, `pow`, `round`, `floor`, `ceil`
- Elementwise: aplica função a cada elemento
- Null handling: nulo → nulo

**5.1.6 Ordenação**
- `argsort()`: retorna `size_t*` com índices
- `sort()`: retorna nova série ordenada
- Ambas: falham se há nulos (não sabe posicionar NA)

**5.1.7 Filtração e Seleção**
- `filter()`: usa bool array para filtrar
- `take()`: copia elementos em índices específicos
- `unique()`: retorna valores únicos (com contagem)
- `dropna()`, `fillna()`: gerenciar nulos

**5.1.8 Utilitários**
- `count_nonnull()`, `count_null()`: contar
- `to_array()`: exportar para `double*` (shallow copy)

### 5.2 Padrão de Implementação

Todas funções seguem:
1. **Validação:** null check, tamanho, overflow
2. **Alocação:** nova série se resultado
3. **Loop:** elemento por elemento, null check
4. **Cleanup:** se erro, liberar e retornar NULL
5. **Retorno:** série nova ou agregação

---

## 6. Módulo Ops I64 (Int64)

### 6.1 Diferenças de F64

**Estrutura análoga:** `smaug_series_i64_t` em vez de `f64_t`
**Funções análogas:** criar, free, append, add, sub, mul, div, filter, etc

**Diferenças semânticas:**

| Operação | Float64 | Int64 |
|----------|---------|-------|
| `sum()` | retorna `double` | retorna `int64_t` |
| `mean()` | retorna `double` | retorna `double` (!) |
| `min/max()` | retorna `double` | retorna `int64_t` |
| `std/var()` | retorna `double` | retorna `double` |
| `add_scalar()` | aceita `double` | aceita `int64_t` |
| `div()` | IEEE 754 division | Integer division (trunca) |

**Por que mean retorna double em i64:**
- Média de [1, 2, 3] é 2.0 (ok como int)
- Média de [1, 2, 4] é 2.333... (precisa double!)
- Nunca truncar implicitamente, sempre retornar double

### 6.2 Quando Usar I64

- Contadores (views, event counts)
- IDs, índices
- Timestamps (Unix seconds)
- Valores que não precisam de ponto flutuante

**Quando NÃO usar:**
- Razões, proporções
- Medições científicas
- Qualquer coisa com precisão crítica

---

## 7. Módulo Ops Bool (Booleano)

### 7.1 Escopo

Operações com **`smaug_series_bool_t`**, usada para:
- Resultado de comparações (`df["age"] > 18`)
- Boolean indexing (`df[mask]`)
- Agregações lógicas (`all(mask)`, `any(mask)`)

### 7.2 Operações

**7.2.1 Lógicas**
- `and`, `or`, `not`, `xor`: operações conjuntivas/disjuntivas
- Cada uma: elemento a elemento
- `not()`: inverte cada bit

**7.2.2 Agregações**
- `count_true()`, `count_false()`: contar verdadeiros/falsos
- `any()`: `true` se existe pelo menos um true
- `all()`: `true` se todos são true
- Útil para: validação de condições

### 7.3 Diferença de Comparações

- **Comparação** (em ops_f64): `gt()` retorna `uint8_t*` (novo array)
- **BoolSeries**: classe Lua que encapsula esse array
- **Operações bool**: trabalham com `smaug_series_bool_t` ou `uint8_t*`

---

## 8. Módulo I/O - CSV (Fase 5)

### 8.1 Escopo

Parser CSV que:
- Lê arquivo, detecta tipos (int, float, string)
- Cria séries C correspondentes
- Retorna tabela de dados
- Suporta header, delimitador, NAs customizados

### 8.2 Arquivo: `smaug_csv.c`

**Quantas funções:** ~8-10
- `smaug_csv_read()`: main parser (retorna `smaug_csv_table_t`)
- `smaug_csv_write()`: exportar tabela
- `smaug_csv_table_free()`: cleanup
- Internals: `infer_type()`, `parse_line()`, `parse_column()`, `handle_quoted_field()`

**Propósito:** Converter CSV (texto) → Estruturas C tipadas
- **Type inference:** examinar valores, adivinhar int/float/string
- **Quoted fields:** suportar campos com vírgulas dentro
- **Escaped quotes:** suportar `\"` dentro de quoted fields
- **NA handling:** converter "NA", "N/A", "" para nulos

### 8.3 Desafios de CSV

CSV é deceptivamente complexo:
```
idade,nome,salario
25,"Silva, João",3000.50
30,"Costa, Maria",3500.00
```

Linha 2 tem vírgula DENTRO de quoted field, não é delimitador.

**Implementação:**
1. **Read file:** buffer inteiro na RAM
2. **First pass:** contar linhas, campos, detectar delimitador (,;|\t)
3. **Sample:** examinar primeiras N linhas por coluna
4. **Infer:** para cada coluna, decidir int/float/string
5. **Allocate:** criar séries C com tipos inferidos
6. **Second pass:** parse novamente, popula arrays

### 8.4 Type Inference

**Heurística simples:**
- Coluna é int se todos samples casam `^-?\d+$`
- Coluna é float se casam `^-?\d+\.?\d*([eE]-?\d+)?$`
- Coluna é string caso contrário

**Problema:** "1" pode ser int ou string (ID). CSV não tem type hints!
- Solução: adivinhar melhor possível, user pode override no Lua

---

## 9. Módulo I/O - JSON (Fase 5+)

### 9.1 Escopo

Parser JSON para:
- Array of objects: `[{col1: val, col2: val}, ...]` → DataSet
- Flat objects: `{col1: [val, val, ...], col2: [...]}` → DataSet
- Nested: futuro (complexo)

### 9.2 Arquivo: `smaug_json.c`

**Quantas funções:** ~5-6
- `smaug_json_read()`: parse JSON file
- `smaug_json_write()`: export DataSet
- `smaug_json_to_csv_table()`: converter estrutura interna
- Internals: `parse_array()`, `parse_object()`, `infer_from_json_value()`

### 9.3 Vantagens de JSON vs CSV

- **Types:** JSON preserva tipos (1 vs "1" é óbvio)
- **Nested:** objetos podem ter arrays
- **Unicode:** melhor suporte nativo

**Desvantagem:**
- Arquivos maiores (mais overhead)
- Parsing mais complexo

---

## 10. Módulo I/O - SQL (Fase 6+)

### 10.1 Escopo

Conectar a databases (SQLite, PostgreSQL, MySQL):
- `read_sql()`: executar query, retornar DataSet
- `write_sql()`: inserir DataSet em tabela

### 10.2 Arquivo: `smaug_sql.c` (futuro)

**Quantas funções:** ~4-5
- `smaug_sql_query()`: executar SELECT
- `smaug_sql_insert()`: inserir rows
- `smaug_sql_execute()`: qualquer comando
- Connection pool (se escalabilidade exigir)

### 10.3 Dependency

Requer driver externo (libsqlite3, libpq, etc). Será linkado via CMake.

---

## 11. Tipos Futuros (String, Categorical, DateTime)

### 11.1 String Series (Fase 5+)

**Propósito:** Armazenar texto (nomes, endereços, etc)

**Desafio:** Strings têm tamanho variável
- Opção 1: Array de ponteiros (simples, fragmentado)
- Opção 2: Buffer contíguo com índices (complexo, fast)

**Implementação inicial:** Opção 1
- `smaug_series_str_t`: `char** strings`, `size_t* lengths`, `size_t size`
- Funções: `create`, `free`, `get`, `set`, `concat`, `upper`, `lower`, `replace`, `contains`

**Otimização (Fase 5+):** Dictionary encoding para strings categóricas
- Se strings são repetidas (e.g., estados "SP", "RJ", "MG"):
- Armazenar IDs inteiros (0, 1, 2) em vez de strings
- Mantém dicionário: {0 → "SP", 1 → "RJ", ...}
- **Vantagem:** 100x mais rápido para groupby, comparações, sorting

### 11.2 Categorical Series (Fase 5+)

**Propósito:** Enumeração ordenada (levels)

**Estrutura:** `smaug_series_categorical_t`
- `int64_t* indices`: referências para categorias
- `char** categories`: valores únicos, em ordem
- `size_t num_categories`

**Funções:** `create`, `set_categories`, `rename_categories`, `reorder_categories`

### 11.3 DateTime Series (Fase 6+)

**Propósito:** Timestamps e durações

**Representação:** Unix timestamp em milliseconds (int64_t)
- Razão: Int64 cabe em Lua double sem perda de precisão
- Granularidade: ms é suficiente para maioria de casos

**Funções:** `create`, `add_days`, `add_seconds`, `extract_year`, `extract_month`, `extract_day`

---

## 12. Frontend Lua - Organização Geral

### 12.1 Estrutura de Diretórios

```
lua/smaug/
├── init.lua              # Entry point, requer modules
├── ffi_loader.lua        # FFI bindings (C ↔ Lua)
├── core/
│   ├── series.lua        # Classe Series
│   ├── dataset.lua       # Classe DataSet
│   ├── indexer.lua       # Classe Indexer (loc, iloc)
│   └── groupby.lua       # Classe GroupBy
├── io/
│   ├── csv.lua           # read_csv, write_csv
│   ├── json.lua          # read_json, write_json
│   └── sql.lua           # read_sql, write_sql
└── utils/
    ├── validators.lua    # Validações
    ├── formatters.lua    # Pretty-print
    └── types.lua         # Type coercion
```

### 12.2 FFI Bridge (`ffi_loader.lua`)

**Propósito:** Conectar Lua com C via LuaJIT FFI
- **Declarar tipos C:** `ffi.cdef()` com structs e funções
- **Carregar DLL/SO:** `ffi.load()` com fallback para múltiplos paths
- **Retornar namespace C:** todos os C functions disponíveis via `C.smaug_f64_create()`, etc

**Não há lógica:** apenas translação

---

## 13. Classe Series

### 13.1 Propósito

Encapsular uma **série C** (f64_t, i64_t, etc) com:
- API amigável ao Lua
- Metamétodos para operadores (`+`, `-`, `*`, etc)
- Métodos para operações (sum, mean, filter, etc)
- Auto-cleanup via `ffi.gc()`

### 13.2 Responsabilidades

| Responsabilidade | Quem faz |
|------------------|----------|
| Alocar memória C | Lua wrapper chama `C.smaug_f64_create()` |
| Chamar funções C | Lua wrapper chama `C.smaug_f64_add()`, etc |
| Gerenciar GC | Lua via `ffi.gc(ptr, C.smaug_f64_free)` |
| Validar argumentos | Lua wrapper (tipos, tamanhos) |
| Error handling | Lua (check retorno NULL de C) |

### 13.3 Variáveis (Instância)

```
_dtype          string: "float64", "int64", "bool"
_size           number: comprimento lógico
_capacity       number: comprimento alocado
_c_struct       userdata: ponteiro C para smaug_series_f64_t
_name           string: identificador (opcional)
```

### 13.4 Métodos (Categorias)

**Factories (Classe):**
- `Series:create_float64(size, name)`
- `Series:create_int64(size, name)`
- `Series:from_array(array, dtype, name)`

**Getters:**
- `series:get(index)` → valor
- `series:is_null(index)` → bool
- `series:size()`, `series:dtype()` → metadados

**Setters:**
- `series:set(index, value)`
- `series:set_null(index)`

**Append:**
- `series:append(value)` → retorna self (chain)
- `series:append_null()` → retorna self

**Aritméticas (retornam nova Series):**
- `series + other` (metamétodo `__add`)
- `series - other`, `series * scalar`, etc.
- `series:mul(scalar)`, `series:div(scalar)`, etc.

**Reduções (retornam número):**
- `series:sum(ignore_na)`, `:mean()`, `:min()`, `:max()`, `:std()`, `:var()`
- `series:count_nonnull()`, `:count_null()`

**Comparações (retornam BoolSeries):**
- `series:gt(threshold)` → BoolSeries
- `series:lt(threshold)`, `:eq()`, `:ge()`, `:le()`, `:ne()`

**Filtração:**
- `series:filter(bool_series)` → nova Series (apenas onde true)
- `series:dropna()` → nova Series (sem nulos)
- `series:fillna(value)` → nova Series (nulos preenchidos)

**Transformações:**
- `series:clone()` → deep copy
- `series:view(start, len)` → slice sem cópia
- `series:sort(ascending)` → nova Series ordenada
- `series:unique()` → valores únicos
- `series:take(indices)` → cópia seletiva

**Inspeção:**
- `series:describe()` → resumo (min, max, mean, std, etc.)
- `series:head(n)` → primeiros n
- `series:tail(n)` → últimos n
- `tostring(series)` (metamétodo `__tostring`) → pretty-print

### 13.5 Metamétodos

| Metamétodo | Comportamento |
|---|---|
| `__add(other)` | `series + other` (+ scalar ou + series) |
| `__sub(other)` | `series - other` |
| `__mul(other)` | `series * scalar` |
| `__div(other)` | `series / scalar` |
| `__pow(exp)` | `series ^ exp` |
| `__eq(other)` | `series == other` (retorna BoolSeries!) |
| `__lt(other)` | `series < other` (retorna BoolSeries) |
| `__le(other)` | `series <= other` (retorna BoolSeries) |
| `__tostring()` | Formato: "Series(name, dtype, size)" |
| `__len()` | `#series` retorna size |
| `__index(i)` | `series[i]` acessa elemento |
| `__newindex(i, val)` | `series[i] = val` modifica elemento |

### 13.6 Características Importantes

**Imutabilidade:**
- `series + other` **não modifica** series, retorna nova
- Only `set()` modifica, não há operações in-place

**Nil vs NAN:**
- Get nulo: retorna `nil` no Lua (não NAN)
- Set nil: marca como nulo
- Operações respeitam nulos (propagam)

**Chaining (parcial):**
- `append` retorna self (pode chain)
- Maioria das operações retornam nova Series (não chainable)

---

## 14. Classe DataSet

### 14.1 Propósito

Representar **tabela 2D** (múltiplas séries alinhadas):
- Cada coluna é uma Series
- Mesmo número de linhas em todas
- Acesso por nome de coluna
- Slicing (linhas por índice)
- Filtragem (boolean indexing)
- Estatísticas por coluna

### 14.2 Relação com Series

- **DataSet = coleção de Series**
- Cada coluna é uma Series independente
- Compartilham tamanho (número de linhas)
- Não compartilham dados (cada uma é independente)

### 14.3 Variáveis (Instância)

```
_columns        dict: { col_name → Series, ... }
_col_names      array: ordem das colunas ["col1", "col2", ...]
_dtypes         dict: { col_name → dtype_string, ... }
_index          Series: índices de linhas (futuro, chave)
_length         number: número de linhas (cache)
```

### 14.4 Métodos (Categorias)

**Factories (Classe):**
- `DataSet:new(columns_dict)` → novo DataSet vazio
- `DataSet:from_table(data_table)` → converter Lua table
- `DataSet:from_csv(filename, opts)` → ler CSV

**Acesso a Colunas:**
- `dataset["col_name"]` (metamétodo) → retorna Series
- `dataset:get_column(name)` → Series
- `dataset:add_column(name, series)` → modifica dataset
- `dataset:drop_column(name)` → remove coluna
- `dataset:set_column(name, series)` → replace

**Metadata:**
- `dataset:columns()` → lista nomes
- `dataset:dtypes()` → dicionário de tipos
- `dataset:shape()` → (num_rows, num_cols)
- `dataset:info()` → resumo detalhado

**Slicing (por índice):**
- `dataset:iloc(start, end)` → novo DataSet com linhas [start, end]
- `dataset:head(n)` → primeiras n
- `dataset:tail(n)` → últimas n
- `dataset:sample(n)` → amostra aleatória

**Filtragem (por condição):**
- `dataset:filter(bool_series)` → novo DataSet onde condição é true
- `dataset:where(func)` → novo DataSet onde func(row) retorna true

**Seleção de Colunas:**
- `dataset:select_columns(names)` → novo DataSet com colunas selecionadas
- `dataset:drop_columns(names)` → novo DataSet sem colunas
- `dataset:reorder_columns(names)` → reordenar colunas

**Ordenação:**
- `dataset:sort_by(col_name, asc)` → novo DataSet ordenado
- `dataset:sort_values([col1, col2], asc)` → ordenado por múltiplas colunas

**Transformações:**
- `dataset:clone()` → deep copy
- `dataset:transpose()` → trocar linhas/colunas
- `dataset:melt(id_vars, value_vars)` → unpivot
- `dataset:pivot(index, columns, values)` → pivot (futuro)

**Agregações:**
- `dataset:describe()` → resumo estatístico de numéricas
- `dataset:groupby(col_name)` → GroupBy object (futuro)

**Duplicatas:**
- `dataset:duplicated(subset)` → BoolSeries marcando duplicatas
- `dataset:drop_duplicates(subset)` → remove duplicatas

**Inspeção:**
- `tostring(dataset)` → pretty-print tabular (primeiras/últimas 5 linhas)
- `dataset:to_table()` → converter para Lua table

**I/O:**
- `dataset:to_csv(filename, opts)` → escrever CSV
- `dataset:to_json(filename, opts)` → escrever JSON (futuro)

### 14.5 Metamétodos

| Metamétodo | Comportamento |
|---|---|
| `__index(col_name)` | `df["col"]` retorna Series |
| `__tostring()` | Pretty-print tabular |
| `__len()` | `#df` retorna número de linhas |

### 14.6 Invariantes Críticos

- **Todas colunas têm mesmo `_length`** (validado em add_column)
- **`_col_names` e `_columns` sincronizados** (sempre)
- **Colunas são independentes** (deletar uma não afeta outras)

---

## 15. Classe Indexer

### 15.1 Propósito

Suportar sintaxe de indexação avançada (inspirada em Pandas):
- `loc`: acesso por rótulo (futuro, chaves de índice)
- `iloc`: acesso por posição
- `at`: acesso single value (rápido)
- `iat`: acesso single value por posição

### 15.2 Métodos

**Loc Indexer (por rótulo):**
- `dataset:loc[label]` → retorna linha com rótulo
- `dataset:loc[start:end]` → retorna range de rótulos
- Requer `dataset._index` preenchido

**Iloc Indexer (por posição):**
- `dataset:iloc[index]` → retorna linha no índice
- `dataset:iloc[start:end]` → retorna range de posições

**At/Iat (single value):**
- `dataset:at[row, col]` → valor em (row_label, col_name)
- `dataset:iat[row_idx, col_idx]` → valor em (row_pos, col_pos)

### 15.3 Implementação

- Não é classe com instância, é mais um **namespace de funções**
- Pode ser implementado como tabela com metatables para suportar sintaxe `[index]`

---

## 16. Classe GroupBy

### 16.1 Propósito

Suportar **aggregação agrupada** (similar a SQL GROUP BY):
- Agrupar por coluna(s)
- Aplicar agregação (sum, mean, count, etc.) por grupo
- Retornar novo DataSet com resultados

### 16.2 Uso

```lua
df = DataSet:from_csv("vendas.csv")
-- Colunas: vendedor, categoria, valor

-- Agrupar por vendedor, somar valor
grouped = df:groupby("vendedor")
resultado = grouped:sum()  -- novo DataSet
```

### 16.3 Métodos

**Construtor:**
- `DataSet:groupby(col_name)` → GroupBy object
- `DataSet:groupby({col1, col2})` → GroupBy por múltiplas colunas

**Propriedades:**
- `grouped.groups` → dicionário { chave → índices das linhas }
- `grouped.ngroups` → número de grupos

**Agregações (retornam DataSet):**
- `grouped:sum()` → soma por grupo
- `grouped:mean()`, `:min()`, `:max()`, `:count()`, `:std()`, `:var()`
- `grouped:first()`, `:last()` → primeiro/último de cada grupo
- `grouped:agg(func)` → agregação customizada
- `grouped:agg({col1=func1, col2=func2})` → funções diferentes por coluna

**Transformações:**
- `grouped:transform(func)` → aplicar função a cada grupo, retorna DataSet original shape
- `grouped:apply(func)` → aplicar função customizada

### 16.4 Implementação

- Backend: hash table em C (future: `smaug_hash_table_t`)
- Frontend Lua: iterar grupos, calcular agregação, construir DataSet resultado

---

## 17. FFI Bridge

### 17.1 Propósito

Conectar Lua com C, **sem lógica**, apenas translação:
- Declarar tipos C (`ffi.cdef()`)
- Carregar biblioteca compilada (`ffi.load()`)
- Disponibilizar namespace C para Lua

### 17.2 Arquivo: `ffi_loader.lua`

**Conteúdo:**
- `ffi.cdef()` com todos os tipos (`smaug_series_f64_t`, etc) e assinaturas
- `ffi.load()` com paths de fallback
- `return C` (namespace global)

**Não há:**
- Wrapper functions
- Type checking
- Error handling
- Conversão de dados

**Uso:**
```lua
local C = require("smaug.ffi_loader")
local s = C.smaug_f64_create(10)
```

---

## 18. Módulo I/O Lua

### 18.1 Propósito

Abstrair I/O do backend C, prover interface Lua amigável

### 18.2 CSV Module (`lua/smaug/io/csv.lua`)

**Funções:**
- `smaug.read_csv(filename, opts)` → DataSet
- `smaug.write_csv(dataset, filename, opts)` → bool (sucesso)

**Opções (`opts`):**
- `has_header`: true/false
- `delimiter`: char ("," por padrão)
- `dtype`: dict de tipos explícitos
- `index_col`: string ou number (qual coluna é índice)
- `na_values`: array de strings que significam NA

**Lógica:**
1. Chamar `C.smaug_csv_read()` (backend C)
2. Converter resultado (`smaug_csv_table_t`) para DataSet Lua
3. Criar Series para cada coluna, agrupar em DataSet

### 18.3 JSON Module (análogo)

### 18.4 SQL Module (futuro)

---

## 19. Testes e Validação

### 19.1 Testes C

**Arquivo: `tests/test_alloc.c`**
- Testes de alocação, realloc, cleanup
- Validar invariantes (size <= capacity)
- Testar múltiplas alocações (leak check via Valgrind)
- ~50 testes

**Arquivo: `tests/test_ops.c`**
- Testes de operações (sum, mean, add, etc)
- Validar null handling
- Comparar contra expected (numpy/pandas quando possível)
- ~100 testes

### 19.2 Testes Lua (FFI)

**Arquivo: `tests/test_ffi.lua`**
- Validar carregamento FFI
- Chamar funções C básicas
- Verificar retornos
- ~20 testes

**Arquivo: `tests/test_series.lua`** (Fase 2+)
- Testar classe Series
- Metamétodos
- Auto-cleanup

**Arquivo: `tests/test_dataset.lua`** (Fase 3+)
- Testar DataSet
- Slicing, filtragem
- Estatísticas

### 19.3 Testes de Integração

**CSV:**
- Ler CSV real, validar tipos, contar linhas
- Escrever, ler de volta, comparar

**Performance:**
- Benchmark sum(1M floats) vs numpy
- Benchmark DataSet operations vs Pandas

---

## Resumo Executivo

### Estrutura C (Backend)
- **3 camadas:** Core (alloc) → Ops (math) → I/O (csv/json/sql)
- **3 tipos primários:** float64, int64, bool
- **2 tipos futuros:** string, categorical, datetime
- **~100 funções** (fase 1-6)

### Estrutura Lua (Frontend)
- **4 classes principais:** Series, DataSet, Indexer, GroupBy
- **3 módulos I/O:** CSV, JSON, SQL
- **FFI Bridge:** translação pura
- **Metamétodos:** operadores + e -, comparações, len, etc

### Todas Fases
1. **Phase 1:** C core + FFI bridge
2. **Phase 2:** Series Lua + metamétodos
3. **Phase 3:** DataSet + slicing
4. **Phase 4:** Boolean indexing + filtros
5. **Phase 5:** CSV I/O
6. **Phase 6:** GroupBy, Joins, tipos complexos
7. **Phase 7:** Advanced (resample, window ops, pivot)

---

*Este índice é referência completa de arquitetura. Consultar Documentação Técnica para detalhes de funções.*
