# Smaug — Roadmap e Design do Frontend

Este documento descreve o que **ainda não existe**: o roadmap faseado e o design
planejado do frontend Lua e dos módulos de I/O. O backend C (Fase 1) já está
pronto — ver `API_Reference.md`.

---

## Roadmap faseado

| Fase | O que | Status |
|------|-------|--------|
| **1** | Backend C: structs, lifecycle, ops f64/i64, null handling | ✅ Backend pronto; faltam build + testes |
| **2** | Classe `Series` em Lua, metamétodos, `ffi.gc` | ⏳ Próxima |
| **3** | Classe `DataSet`, slicing (`iloc`/`head`/`tail`) | — |
| **4** | Boolean indexing, `BoolSeries`, filtros no DataSet | — |
| **5** | CSV I/O com type inference | — |
| **6+** | GroupBy, joins, strings/categorical/datetime | Futuro |
| **7** | Resample, window ops, pivot, lazy evaluation | Futuro |

**MVP = Fases 1–5.** As fases 6–7 são extensões pós-launch.

Próximos passos imediatos para fechar a Fase 1:

1. Criar o sistema de build (`Makefile` — ver `Build_and_Testing.md`).
2. Escrever `tests/test_alloc.c` e `tests/test_ops.c`; validar com Valgrind.
3. Escrever `lua/smaug/ffi_loader.lua` com o `ffi.cdef` completo.
4. Teste de fumaça FFI carregando a lib e somando uma série.

---

## Frontend Lua — estrutura planejada

```
lua/smaug/
├── init.lua            # entry point
├── ffi_loader.lua      # ffi.cdef + ffi.load (tradução pura, sem lógica)
├── core/
│   ├── series.lua      # classe Series
│   ├── dataset.lua     # classe DataSet
│   ├── indexer.lua     # loc/iloc (futuro)
│   └── groupby.lua     # GroupBy (futuro)
├── io/
│   ├── csv.lua         # read_csv / write_csv
│   └── json.lua        # futuro
└── utils/
    ├── validators.lua
    └── formatters.lua  # pretty-print
```

### FFI Bridge (`ffi_loader.lua`)

Responsabilidade única: **tradução**, sem lógica de negócio. Declara os tipos
(`ffi.cdef`) e carrega a `.so` com fallback de paths, retornando o namespace `C`.
Detecta o SO para escolher `libsmaug_math.so` / `.dylib` / `smaug_math.dll` e
tenta `./build/`, `/usr/local/lib/`, etc.

```lua
local ffi = require("ffi")
ffi.cdef([[ /* tipos e assinaturas de smaug_math.h */ ]])

local function load_library()
    local name = ({ Windows="smaug_math.dll", OSX="libsmaug_math.dylib" })[ffi.os]
                 or "libsmaug_math.so"
    for _, p in ipairs({ "./build/"..name, "/usr/local/lib/"..name, name }) do
        local ok, lib = pcall(ffi.load, p)
        if ok then return lib end
    end
    error("Falha ao carregar smaug_math — compile com 'make' primeiro")
end

return load_library()
```

### Classe `Series` (Fase 2)

Encapsula um struct C de série com uma API amigável, metamétodos de operador e
limpeza automática via `ffi.gc`. Responsabilidades: alocar/chamar C, validar
argumentos, converter índice 1-based (Lua) → 0-based (C), e converter `NAN` ↔
`nil`.

Atributos de instância: `_dtype`, `_size`, `_c_struct` (ponteiro C), `_name`.

Métodos previstos, por categoria:

- **Factories:** `Series.float64(size, name)`, `Series.int64(...)`,
  `Series.from_array(arr, dtype, name)`
- **Acesso:** `:get(i)`, `:set(i, v)`, `:is_null(i)`, `:set_null(i)`,
  `:append(v)` (chainable)
- **Reduções:** `:sum(ignore_na)`, `:mean()`, `:min()`, `:max()`, `:std()`,
  `:var()`, `:count_nonnull()`
- **Comparações:** `:gt(t)`, `:lt(t)`, `:eq(t)` → `BoolSeries`
- **Transformações:** `:clone()`, `:view(s, n)`, `:sort(asc)`, `:filter(bool)`,
  `:take(idx)`
- **Inspeção:** `:describe()`, `:head(n)`, `:tail(n)`

Metamétodos: `__add`, `__sub`, `__mul`, `__div` (Series ou escalar), `__eq`/
`__lt`/`__le` (retornam `BoolSeries`), `__len`, `__tostring`, `__index`/
`__newindex` para `series[i]`.

Esqueleto da factory com `ffi.gc`:

```lua
function Series.float64(size, name)
    local c = C.smaug_f64_create(size)
    if c == nil then error("falha ao alocar Series") end
    ffi.gc(c, C.smaug_f64_free)          -- limpeza automática
    return setmetatable({
        _dtype="float64", _size=size, _c_struct=c, _name=name or "unnamed"
    }, Series)
end
```

> Nota: `ffi.gc` pode pesar em hot paths. Para construção em massa, considere
> agrupar allocations e liberar em lote.

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

### `BoolSeries` e filtros (Fase 4)

Encapsula o array `uint8_t*` devolvido por `gt`/`lt`/`eq`. Suporta operadores
lógicos (`and`/`or`/`not`/`xor`) e agregações (`any`, `all`, `count_true`).
`DataSet:filter(bool_series)` devolve um novo DataSet só com as linhas marcadas.

---

## CSV I/O (Fase 5)

Parser em C (`smaug_csv.c`) que lê o arquivo, infere tipos por coluna e devolve
uma estrutura tabular convertida para `DataSet` no Lua.

Estrutura de retorno prevista:

```c
typedef struct {
    void **columns;          /* ponteiros para séries (f64/i64/...) */
    const char **dtypes;
    const char **col_names;
    size_t num_cols, num_rows;
} smaug_csv_table_t;

smaug_csv_table_t* smaug_csv_read(const char *filename, bool has_header, char delimiter);
void               smaug_csv_table_free(smaug_csv_table_t *tbl);
```

Pipeline: ler arquivo em buffer → 1ª passada (contar linhas/colunas, detectar
delimitador) → amostrar primeiras N linhas por coluna → inferir tipo → alocar
séries → 2ª passada para popular.

Type inference (heurística): inteiro se casa `^-?\d+$`; float se casa
`^-?\d+\.?\d*([eE]-?\d+)?$`; senão string. `"NA"`, `"N/A"`, `""` viram nulos.

Desafios do CSV a tratar: campos com aspas contendo o delimitador
(`"Silva, João"`), aspas escapadas, quebras de linha dentro de campos. CSV não
carrega type hints, então a inferência será heurística e o usuário poderá fazer
override no Lua.

---

## Tipos futuros (Fase 6+)

- **String:** começa como array de ponteiros (`char**` + comprimentos); evolui
  para **dictionary encoding** (IDs inteiros + dicionário de valores únicos),
  que acelera muito groupby, comparações e sorting quando há repetição.
- **Categorical:** índices inteiros + categorias ordenadas (levels).
- **DateTime:** `int64_t` como timestamp Unix em ms (cabe no double do Lua sem
  perda); funções de extração (ano, mês, dia) e aritmética de datas.

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
