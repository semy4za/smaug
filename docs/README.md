# 🐉 Smaug

Biblioteca de dados tabulares em Lua com backend em C.
Engine de Ring 0 em C puro — memória, tipos, operações primitivas.
Frontend de Ring 1 em LuaJIT — `Series`, `DataSet`, ergonomia. Dtypes: `float64`, `int64`, `string`, `bool`.

---

## O que parece na prática

```lua
local smaug = require("smaug")

local payload = {
    {"cidade",  {"SP", "RJ", "SP", "MG", "SP"}, "string"},
    {"vendas",  {120,  85,   200,  smaug.NA, 95}},
    {"ativo",   {true, false, true, true, false}, "bool"},
}
local ds = smaug.DataSet(payload)

-- filtra ativos, preenche nulos, calcula total
local resultado = ds
    :filter(ds["ativo"])
    :fillna({vendas = 0.0})

print(resultado:describe())
print(resultado["vendas"]:sum())
```

```
DataSet '' [3 linhas x 3 colunas]
   cidade  vendas  ativo
1  SP      120.0   true
2  SP      200.0   true
3  MG      0.0     true

320.0
```

---

## Tipos suportados

Todos com suporte a `null` via bitmask dedicada. `null` não é `NaN`, não é
zero, não é string vazia — é ausência explícita.

| dtype | descrição |
|---|---|
| `float64` | IEEE 754 dupla precisão |
| `int64` | inteiro com sinal 64-bit |
| `bool` | lógica de três valores (Kleene) |
| `string` | offset-based, estilo Arrow |

---

## Estruturas

**`Series`** — coluna tipada unidimensional. 51 métodos: acesso, mutação,
aritmética, reduções, comparações (→ `Series<bool>`), sort, filter, astype,
fillna, describe, map, unique/nunique/value_counts, abs/round/clip,
cumsum/cumprod/diff/shift, rolling, Kleene (land/lor/lnot/lxor).

**`.str`** — proxy para operações sobre Series string (15 métodos Tier A+B):
len, lower/upper, strip, contains/startswith/endswith, replace,
find, slice, pad/zfill, rep, cat, split.

**`DataSet`** — coleção de colunas alinhadas. 31 métodos: CRUD de colunas,
filter (por `Series<bool>`), sort_by, select, dropna, fillna, describe, sample,
groupby (sum/mean/min/max/count, chave simples e composta), join (inner/left/right/outer),
concat, pivot, melt, assign, nunique, rolling (sum/mean/min/max).

```lua
local payload = {
    {"uf",    {"SP", "RJ", "SP", "MG"}, "string"},
    {"pop",   {12.3,  6.7, 12.3,  2.1}},
    {"cap",   {true, true, false, true}, "bool"},
}
local ds = smaug.DataSet(payload)

-- soma de pop onde uf == "SP"
local sp  = ds:filter(ds["uf"]:eq("SP"))
print(sp["pop"]:sum())
```

```
24.6
```

---

## Copy-on-Write

Views compartilham o buffer da série pai zero-copy. Na primeira escrita,
a view materializa um buffer privado — o original nunca é tocado.

```lua
local payload = {{"vendas", {10.0, 20.0, 30.0}}}
local ds = smaug.DataSet(payload)

local v = ds["vendas"]:view(1, 2)   -- zero-copy
v:set(1, 99.0)                       -- materializa aqui

print(ds["vendas"]:get(1))           -- 10.0  (original intacto)
print(v:get(1))                      -- 99.0
```

```
10.0
99.0
```

---

## Filosofia

Smaug é fluido e robusto — uma engine feita para processar dados.

Robustez é funcionalidade. Testes não são suporte às funcionalidades, são
funcionalidades. Cobertura é ferramenta de confiança, não métrica de vaidade.
Valgrind é parte do desenvolvimento, não etapa final. A capacidade de
sobreviver a entradas inválidas é tão importante quanto qualquer operação
matemática.

E o design importa. O Smaug precisa ser confiável e fluido — uma API que
funciona mas é difícil de escrever entregou só metade do trabalho. O fluxo
de dados deve ser natural de ler e conciso de compor.

---

## Qualidade

| métrica | valor | |
|---|---|---|
| branch-alvo (MC/DC) | 100% — 1095/1095 ramos | [Coverage](COVERAGE.md) |
| cobertura de linhas | 99.82% | [Coverage](COVERAGE.md) |
| checks OOM (allocfail) | 767 | [Build and Testing](Build_and_Testing.md) |
| checks property-based | 281 083 | [Build and Testing](Build_and_Testing.md) |
| Valgrind | clean | [Build and Testing](Build_and_Testing.md) |
| warnings `-Wall -Wextra` | zero | [Contract](CONTRACT.md) |

Modelo de referência: SQLite.

---

## Build

**Linux**

```bash
make          # compila
make test     # testes C
make test-lua # testes Lua
make coverage # cobertura (gcov)
make valgrind # Valgrind
```

**Windows (MSYS2)**

```powershell
scripts/windows_build.ps1
```

---

## Documentação

### Entender o projeto
| | |
|---|---|
| [Roadmap](Roadmap.md) | arquitetura em anéis, filosofia e direção |
| [Contract](CONTRACT.md) | contratos de comportamento Ring 0 e Ring 1 |
| [COW](COW.md) | especificação Copy-on-Write |
| [Changelog](CHANGELOG.md) | histórico de mudanças por sessão |

### Usar a API
| | |
|---|---|
| [API Index](API_INDEX.md) | catálogo rápido de métodos por estrutura |
| [API Reference](API_Reference.md) | referência completa do backend C |

### Desenvolver
| | |
|---|---|
| [Build and Testing](Build_and_Testing.md) | compilação, testes, Valgrind, cobertura |
| [Coverage](COVERAGE.md) | relatório de cobertura (gerado por `make coverage`) |

### Arquivo histórico
| | |
|---|---|
| [Code Review](CODE_REVIEW.md) | baseline pré-endurecimento (referência histórica) |
