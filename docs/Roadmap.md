# Smaug — Roadmap e Design do Frontend

Este documento descreve o que **ainda não existe**: o roadmap faseado e o design
planejado do frontend Lua e dos módulos de I/O. O backend C (Fase 1) já está
pronto — ver `API_Reference.md`.

---

## Roadmap faseado

| Fase | O que | Status |
|------|-------|--------|
| **1** | Backend C: structs, lifecycle, ops f64/i64, null handling | ✅ Completo (build + testes + smoke FFI) |
| **2** | Classe `Series` em Lua, metamétodos, `ffi.gc` | ⏳ Em andamento — `ffi_loader.lua` + `Series` (f64/i64) ✅ |
| **3** | Classe `DataSet`, slicing (`iloc`/`head`/`tail`) | — |
| **4** | Boolean indexing, `BoolSeries`, filtros | ⏳ comparações + `BoolSeries` + `Series:filter` ✅; falta `dropna` e `DataSet:filter` |
| **5** | I/O: 4 formatos padrão (CSV, JSON, XML, SQL) | — (design documentado) |
| **6+** | GroupBy, joins, strings/categorical/datetime | Futuro |
| **7** | Resample, window ops, pivot, lazy evaluation | Futuro |

**MVP = Fases 1–5.** As fases 6–7 são extensões pós-launch.

A Fase 1 está **fechada**: o `Makefile` compila `build/libsmaug_math.so` sem
warnings (`-Wall -Wextra`), `tests/test_ops.c` passa, e o smoke test FFI
(`test_load.lua`) carrega a lib e soma uma série.

Próximos passos imediatos para a Fase 2:

1. ✅ `lua/smaug/ffi_loader.lua` — `ffi.cdef` completo (f64 + i64 + `free`) e
   `ffi.load` com fallback de paths. **Feito e validado.**
2. ⏳ `lua/smaug/core/series.lua` — classe `Series` com `ffi.gc`, metamétodos e
   conversões (1-based↔0-based, `nil`↔`NAN`).
3. ⏳ `lua/smaug/init.lua` — entry point que expõe `Series` (e futuramente
   `DataSet`, `read_csv`).
4. ⏳ Smoke test do frontend Lua exercitando a classe `Series`.

---

## Frontend Lua — estrutura planejada

```
lua/smaug/
├── init.lua            # entry point ✅
├── ffi_loader.lua      # ffi.cdef + ffi.load (tradução pura, sem lógica) ✅
├── core/
│   ├── series.lua      # classe Series (despacho por dtype) ✅
│   ├── dataset.lua     # classe DataSet
│   ├── indexer.lua     # loc/iloc (futuro)
│   └── groupby.lua     # GroupBy (futuro)
├── io/
│   ├── csv.lua         # read_csv / write_csv
│   ├── json.lua        # read_json / write_json
│   ├── xml.lua         # read_xml / write_xml
│   └── sql.lua         # read_sql / write_sql (SQLite)
└── utils/
    ├── validators.lua
    └── formatters.lua  # pretty-print
```

### FFI Bridge (`ffi_loader.lua`) ✅

Responsabilidade única: **tradução**, sem lógica de negócio. Declara os tipos
(`ffi.cdef`) e carrega a `.so` com fallback de paths, retornando o namespace `C`.
Detecta o SO para escolher `libsmaug_math.so` / `.dylib` / `smaug_math.dll` e
tenta `./build/`, `../build/`, `../../build/`, `/usr/local/lib/`, depois o nome
puro (deixa o loader do SO resolver via `LD_LIBRARY_PATH`).

O cdef cobre **todas** as assinaturas de `smaug_math.h` (f64 + i64) mais
`void free(void*)` da libc — necessário para liberar os arrays brutos
(`uint8_t*` de `gt`/`lt`/`eq`, `size_t*` de `argsort`) que o backend devolve com
contrato "caller libera".

> ⚠️ Armadilha: o parser de C do LuaJIT lê comentários `/* ... */` literalmente.
> Um `*/` no meio de um comentário (ex. escrever o tipo `uint8_t*` seguido de
> `/`) **fecha o comentário cedo** e quebra o parse. Evite `*/` dentro de
> comentários no cdef.

```lua
local ffi = require("ffi")
ffi.cdef([[ /* tipos e assinaturas de smaug_math.h + void free(void*) */ ]])

local function load_library()
    local name = ({ Windows="smaug_math.dll", OSX="libsmaug_math.dylib" })[ffi.os]
                 or "libsmaug_math.so"
    for _, p in ipairs({ "./build/"..name, "../build/"..name,
                         "../../build/"..name, "/usr/local/lib/"..name, name }) do
        local ok, lib = pcall(ffi.load, p)
        if ok then return lib end
    end
    error("Falha ao carregar smaug_math — compile com 'make' primeiro")
end

return load_library()
```

### Classe `Series` (Fase 2) ✅ implementada (f64 + i64)

Encapsula um struct C de série com uma API amigável, metamétodos de operador e
limpeza automática via `ffi.gc`. Arquivo: `lua/smaug/core/series.lua`.

**Arquitetura — despacho por dtype.** A `Series` **não** conhece os detalhes de
cada tipo. Ela despacha para a família de funções C (`smaug_<dtype>_*`) através
de um **descritor** (tabela `DTYPES`). Cada descritor mapeia o nome do dtype
para o conjunto de funções C e suas particularidades semânticas (ex.: o i64
declara `is_int_sentinel` para detectar o `INT64_MIN`). Consequência: adicionar
um tipo novo (`bool`, `string`, `datetime`, `float32`…) é **registrar um
descritor + o backend C**, sem tocar na lógica da `Series` nem no código do
usuário. Esse é o ponto de extensão central do frontend.

Atributos de instância: `_c` (ponteiro C, com `ffi.gc`), `_d` (descritor do
dtype), `_dtype`, `_name`.

Implementado e testado (`tests/test_series.lua`, 69 checks, Valgrind-clean):

- **Factories:** `Series.float64(size, name)`, `Series.int64(size, name)`,
  `Series.new(dtype, size, name)`, `Series.from_table(arr, dtype, name)`
- **Acesso:** `:get(i)`, `:set(i, v)`, `:is_null(i)`, `:set_null(i)`,
  `:append(v)` (chainable), `:len()`/`:size()`
- **Reduções:** `:sum(ignore_na)`, `:mean()`, `:min()`, `:max()`, `:std()`,
  `:var()`, `:count_nonnull()` — `ignore_na` default `true`
- **Transformações:** `:clone()`, `:sort(asc)`, `:view(start, len)`,
  `:take(idx)`, `:head(n)`, `:tail(n)`, `:astype(dtype)`, `:to_table(na_value)`
- **Inspeção:** `:describe()` (count, nulls, mean, std, min, 25/50/75%, max)
- **Comparações/filtro:** `:gt(t)`/`:lt(t)`/`:eq(t)` → `BoolSeries`,
  `:filter(bool_series)` → nova Series
- **Metamétodos:** `__add`/`__sub`/`__mul`/`__div` (Series×Series ou
  Series×escalar; escalar à esquerda só comuta em `+`/`*`), `__tostring`,
  `__index`/`__newindex` para `series[i]`.

Semântica da fronteira Lua↔C tratada pela classe:

- **1-based → 0-based** em todo acesso por índice.
- **`nil` ↔ null:** `:get` de posição nula devolve `nil`; `:set(i, nil)` marca
  null. Os sentinelas do C (NAN no f64; `INT64_MIN` nas reduções i64) viram
  `nil` nas reduções.
- **Sem coerção entre dtypes:** `f64 + i64` é erro explícito (respeita a decisão
  de design do backend).

> **Sentinela `NA`.** Uma tabela Lua com `nil` no meio (`{1, nil, 3}`) tem
> comprimento (`#`) **indefinido**. Por isso `from_table` usa um sentinela
> explícito para nulos: `Series.from_table({1, Series.NA, 3}, "float64")`.

> **Gotcha do `#`.** No LuaJIT padrão (semântica Lua 5.1), o operador `#` **não**
> chama `__len` em tabelas. Por isso o tamanho é obtido por `:len()`, não por
> `#serie`. O `__len` fica definido para builds com compat 5.2, mas `:len()` é o
> caminho oficial.

> **Views são seguras por construção.** `:view(start, len)` devolve uma fatia
> zero-copy que aponta para a memória da pai. Para evitar use-after-free, a view
> (a) guarda uma referência `_parent` à série-pai, impedindo o GC do Lua de
> coletá-la enquanto a view viver, e (b) é **read-only** — `set`/`set_null`/
> `append` numa view dão erro (o C só bloqueia `append`; a guarda extra fica no
> Lua). `:clone()` de uma view devolve uma cópia independente e mutável. Views
> encadeadas apontam para a pai-raiz. Validado sob Valgrind com GC forçado.

Comparações (`:gt`/`:lt`/`:eq` → `BoolSeries`) e `:filter` já estão
implementadas (ver "BoolSeries e filtros"). Ainda **não** implementado:
`dropna` (Fase 4, destrava `sort` em séries com nulos); `DataSet:filter`
(depende do DataSet, Fase 3).

### Classe `DataSet` (Fase 3)

Tabela 2D = coleção de `Series` alinhadas (mesmo número de linhas). Cada coluna é
uma Series independente — não compartilham dados, só o comprimento.

Atributos: `_columns` (dict nome→Series), `_col_names` (ordem), `_dtypes`,
`_length`.

Funcionalidades previstas: acesso por coluna (`df["nome"]` via `__index`), CRUD
de colunas (`add_column`/`drop_column`), slicing (`iloc`/`head`/`tail`/`sample`),
filtragem (`filter(bool_series)`), seleção/reordenação de colunas, ordenação
(`sort_by`), `describe`, e pretty-print tabular via `__tostring`.

Invariantes: todas as colunas têm o mesmo `_length` (validado em `add_column`);
`_col_names` e `_columns` sempre sincronizados.

### `BoolSeries` e filtros (Fase 4) — comparações + lógica ✅

Encapsula o par (`uint8_t*` valores, `smaug_mask_t*` máscara) devolvido por
`gt`/`lt`/`eq`. Arquivo: `lua/smaug/core/boolseries.lua`; backend lógico em
`src/smaug_ops_bool.c`. Implementado e testado (`test_bool.c` no C,
`test_series.lua` no Lua):

- **Origem:** `Series:gt(t)`, `:lt(t)`, `:eq(t)` → `BoolSeries`.
- **Operadores lógicos (Kleene, três valores):** `:land`/`:lor`/`:lxor`/`:lnot`,
  e os açúcares `*` (and), `+` (or), `-` (xor). NOT só como `:lnot()` (Lua não
  tem operador unário sobrecarregável conveniente).
- **Agregações (NA ignorado):** `:count_true()`, `:any()`, `:all()`.
- **Acesso:** `:get(i)` (true/false/nil), `:is_null(i)`, `:to_table(na)`,
  `:len()`, `__tostring`.
- **Posse de memória:** os arrays brutos são `ffi.gc(ptr, C.free)`. Validado
  Valgrind-clean.

`Series:filter(bool_series)` ✅ devolve uma nova Series só com as linhas onde a
máscara é true (NA na máscara conta como false → linha descartada).

Ainda da Fase 4: `dropna` (destrava `sort` em séries com nulos) e `DataSet:filter`
(depende de DataSet, Fase 3).

---

## I/O — formatos de dados padrão (Fase 5)

O Smaug suporta **quatro** formatos de entrada/saída, e **apenas** estes quatro.
Eles são o contrato oficial de I/O do projeto; outros formatos estão fora de
escopo.

| Formato | Extensão | Leitura | Escrita | Notas |
|---------|----------|---------|---------|-------|
| **CSV** | `.csv` / `.tsv` | ✅ planejado | ✅ planejado | Sem type hints → inferência heurística |
| **JSON** | `.json` | ✅ planejado | ✅ planejado | Tipos nativos → menos inferência |
| **XML** | `.xml` | ✅ planejado | ✅ planejado | Precisa de convenção tabular explícita |
| **SQL** | SQLite + `.sql` | ✅ planejado | ✅ planejado | Via SQLite; tipos vêm do schema |

> **Status:** design apenas. Nenhum dos quatro está implementado. A ordem de
> implementação sugerida é CSV → JSON → SQL → XML (do mais simples/comum ao mais
> complexo).

### Struct intermediária comum

Decisão central: **todos os leitores produzem a mesma estrutura tabular
intermediária**, e o frontend Lua a converte para `DataSet`. Da mesma forma,
todos os escritores recebem um `DataSet` e serializam. Isso isola o parsing
(específico de cada formato) da montagem do DataSet (idêntica para todos).

```c
/* Tabela intermediária genérica, compartilhada pelos 4 formatos.
   Substitui o antigo smaug_csv_table_t. */
typedef struct {
    void        **columns;     /* ponteiros para séries (smaug_series_f64_t*, i64*, ...) */
    const char  **dtypes;      /* "float64", "int64", "string", ... por coluna */
    const char  **col_names;
    size_t        num_cols;
    size_t        num_rows;
} smaug_table_t;

void smaug_table_free(smaug_table_t *tbl);
```

Assinaturas de I/O (todas devolvem/recebem `smaug_table_t`):

```c
/* Leitura: arquivo/fonte -> tabela intermediária */
smaug_table_t* smaug_csv_read (const char *path, bool has_header, char delimiter);
smaug_table_t* smaug_json_read(const char *path);
smaug_table_t* smaug_xml_read (const char *path, const char *row_tag);
smaug_table_t* smaug_sql_read (const char *db_path, const char *query);

/* Escrita: tabela intermediária -> arquivo/fonte (0 = ok, -1 = erro) */
int smaug_csv_write (const smaug_table_t *t, const char *path, char delimiter);
int smaug_json_write(const smaug_table_t *t, const char *path, bool records); /* records vs columnar */
int smaug_xml_write (const smaug_table_t *t, const char *path, const char *row_tag);
int smaug_sql_write (const smaug_table_t *t, const char *db_path, const char *table_name);
```

No Lua, o açúcar fica em `io/`: `smaug.read_csv(path)`, `smaug.read_json(path)`,
`smaug.read_xml(path, opts)`, `smaug.read_sql(db, query)` e os `write_*`
correspondentes como métodos do `DataSet`.

### Type inference comum

CSV e XML chegam como texto puro, então precisam de inferência heurística
(rodada nas primeiras N linhas por coluna):

- inteiro se casa `^-?\d+$` → `int64`
- float se casa `^-?\d+\.?\d*([eE]-?\d+)?$` → `float64`
- senão → `string`
- `""`, `"NA"`, `"N/A"`, `null` → nulo

JSON e SQL **já trazem tipos**, então a inferência é mínima (JSON: number/
string/bool/null; SQL: vem do schema da coluna). O usuário sempre pode dar
override no Lua passando um mapa `{coluna = dtype}`.

### CSV

Parser em C (`smaug_csv.c`). Pipeline: ler arquivo em buffer → 1ª passada
(contar linhas/colunas, detectar delimitador) → amostrar primeiras N linhas →
inferir tipo → alocar séries → 2ª passada para popular.

Desafios a tratar: campos com aspas contendo o delimitador (`"Silva, João"`),
aspas escapadas (`""`), quebras de linha dentro de campos aspas.

### JSON

Parser em C (`smaug_json.c`). Dois layouts suportados na leitura:

- **records** (mais comum): array de objetos — cada objeto vira uma linha, as
  chaves viram colunas. Chaves ausentes em alguma linha → nulo.
  `[{"nome":"Ana","idade":30}, {"nome":"Bia","idade":25}]`
- **columnar**: objeto de arrays — cada chave é uma coluna inteira.
  `{"nome":["Ana","Bia"], "idade":[30,25]}`

Na escrita, `records` é o default (mais interoperável); `columnar` é opção.
Objetos/arrays aninhados não têm representação tabular natural — a política é
**achatar um nível** (`{"end":{"cidade":"SP"}}` → coluna `end.cidade`) ou, se
não der, serializar o valor como string JSON. Sem suporte a aninhamento
profundo no MVP.

### XML

Parser em C (`smaug_xml.c`). XML não tem mapeamento tabular padrão, então o
Smaug **exige uma convenção explícita**: o usuário informa a tag que delimita
uma linha (`row_tag`), e os elementos-filho (e/ou atributos) viram colunas.

```xml
<dados>
  <registro><nome>Ana</nome><idade>30</idade></registro>
  <registro><nome>Bia</nome><idade>25</idade></registro>
</dados>
```

Com `row_tag="registro"`: 2 linhas, colunas `nome` e `idade`. Atributos
(`<registro id="1">`) viram colunas prefixadas (`@id`). Inferência de tipo igual
à do CSV (tudo chega como texto). É o formato mais complexo — implementar por
último. Considerar uma lib leve (ex. `libexpat`) em vez de parser próprio.

### SQL

Não é arquivo de texto como os outros: o "formato SQL" do Smaug significa
**integração com SQLite** (banco embarcado, alinhado com o foco leve do
projeto). `smaug_sql_read(db_path, query)` executa um `SELECT` e converte o
result set em tabela; os tipos vêm direto do schema (`INTEGER`→`int64`,
`REAL`→`float64`, `TEXT`→`string`, `NULL`→nulo). `smaug_sql_write` cria/popula
uma tabela.

Depende da `sqlite3` C API — é uma **dependência opcional** (compilar com
`-DSMAUG_WITH_SQLITE` e linkar `-lsqlite3`). Sem ela, os símbolos `smaug_sql_*`
não são expostos. Suporte a outros bancos (Postgres, MySQL) está **fora de
escopo**. Ler/escrever arquivos `.sql` (dumps DDL/DML) é secundário; o caminho
principal é o banco SQLite.

---

## Sistema de tipos

O pandas/NumPy têm dezenas de dtypes, mas a maioria é **variação de largura**
(int8/16/32, float32, uint…) que existe por memória/SIMD, não por semântica
nova. O Smaug separa **tipos com semântica própria** de **variações de largura**
e adota um conjunto curado, em três camadas. A classe `Series` abstrai o dtype
(ver "Classe Series"), então cada novo tipo é um descritor + um backend C, sem
quebrar a API.

### Tier 1 — núcleo (cobre ~95% de dados tabulares reais)

| dtype | Storage C | Null | Status |
|-------|-----------|------|--------|
| `float64` | `double` | NaN + bitmask | ✅ pronto |
| `int64` | `int64_t` | bitmask (sem NaN) | ✅ pronto |
| `bool` | `uint8_t` | bitmask | ✅ comparações + `BoolSeries` (Fase 4) |
| `string` | dictionary encoding | bitmask | ⏳ Fase 6 |

O `bool` já existe de forma embrionária — é o `uint8_t*` que `gt`/`lt`/`eq`
devolvem. A Fase 4 o promove a tipo de primeira classe (`BoolSeries`) com
operadores lógicos (`and`/`or`/`not`/`xor`) e agregações (`any`/`all`).

O `string` é o maior buraco para trabalho estilo pandas. Plano: começa como
array de ponteiros (`char**` + comprimentos) e evolui para **dictionary
encoding** (IDs inteiros + dicionário de valores únicos), que acelera muito
groupby, comparação e sorting quando há repetição.

### Tier 2 — alto valor (pós-MVP)

| dtype | Storage C | Notas |
|-------|-----------|-------|
| `datetime` | `int64_t` (epoch ms) | extração ano/mês/dia, aritmética de datas; cabe no double do Lua sem perda até ~2⁵³ ms |
| `categorical` | `int32` codes + levels | índices inteiros + categorias ordenadas; memória eficiente para repetição |

### Tier 3 — otimização (talvez, bem depois)

`float32`, `int32`, `int16`, `int8`, `uint*`. **Mesma semântica** dos tipos de
64 bits, só storage mais estreito (metade ou menos da RAM, melhor para SIMD).
Entram apenas se um caso real de memória/performance justificar — não fazem
parte do MVP. Como a `Series` despacha por descritor, adicioná-los não muda o
código do usuário.

### Princípios transversais (valem para todos os dtypes)

- **Sem coerção implícita.** Operar entre dtypes diferentes é erro explícito; o
  usuário converte de propósito. (Conversão `:astype(dtype)` virá como método.)
- **Null por bitmask paralelo**, uniforme para todos os tipos — inclusive os que
  não têm um "NaN" nativo (inteiros, bool, string).
- **Mapeamento NumPy/pandas → Smaug** documentado para conversão de dados:
  `np.float64`→`float64`, `np.int64`→`int64`, `np.bool_`→`bool`,
  `object`/`StringDtype`→`string`, `datetime64[ns]`→`datetime`,
  `category`→`categorical`. Larguras menores do NumPy (`int32`, `float32`, …)
  promovem para o tipo de 64 bits correspondente até o Tier 3 existir.

## GroupBy e Joins (Fase 6+)

GroupBy: `df:groupby(col)` → objeto que mapeia chave → índices de linha, com
agregações por grupo (`:sum()`, `:mean()`, `:count()`, `:agg{...}`). Backend
acelerado por hash table em C (`smaug_hash_table_t`, já declarado como tipo
opaque no header). Joins (inner/left/outer) também via hash table.

---

## Critério de "fase concluída"

Uma fase está pronta quando: features implementadas; testes unitários passam;
resultados validados contra Pandas/NumPy quando aplicável; zero leaks no
Valgrind; documentação atualizada; benchmarks rodados.

## Benchmarks alvo (referência)

| Operação | Alvo | NumPy |
|----------|------|-------|
| `sum(1M floats)` | < 5 ms | ~1 ms |
| `Series + Series (1M)` | < 20 ms | ~5 ms |
| `filter(1M)` | < 15 ms | ~3 ms |
| `CSV read (100K linhas)` | < 500 ms | ~50 ms |

Overhead aceitável para o MVP: 3–5× NumPy.
