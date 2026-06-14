# 🐉 Smaug

Biblioteca de dados tabulares em Lua com backend em C puro.
Dtypes: `float64`, `int64`, `bool`, `string`. Null por bitmask. Zero dependências externas no núcleo.

---

## O que parece na prática

```lua
local smaug = require("smaug")

-- carrega CSV com inferência automática de tipo
local ds = smaug.read_csv("pedidos.csv", {sep = ";"})

-- filtra, agrupa, exporta
local resultado = ds
    :filter(ds["ativo"]:eq(true))
    :groupby("empresa"):sum("vendas")

resultado:to_json("resumo.json")
print(resultado)
```

```lua
-- ou com dados inline
local ds = smaug.DataSet({
    {"cidade",  {"SP", "RJ", "SP", "MG"},          "string"},
    {"vendas",  {120,  85,   200,  smaug.NA}              },
    {"ativo",   {true, false, true, true},           "bool"},
})

local sp = ds
    :filter(ds["ativo"])
    :fillna({vendas = 0})

print(sp["vendas"]:sum())   -- 320
```

---

## Tipos suportados

`null` não é `NaN`, não é zero, não é string vazia — é ausência explícita via bitmask dedicada.

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

**I/O (Anel 3)** — parsers próprios, zero dependências:

```lua
local ds = smaug.read_csv("dados.csv", {sep=","})
local ds = smaug.read_json("dados.json")
ds:to_csv("saida.csv")
ds:to_json("saida.json", {pretty=true})

-- ou em memória
local buf = ds:to_csv_mem()
local ds2 = smaug.read_csv_mem(buf)
```

---

## Copy-on-Write

Views compartilham o buffer da série pai zero-copy. Na primeira escrita,
a view materializa um buffer privado — o original nunca é tocado.

```lua
local ds = smaug.DataSet({{"vendas", {10.0, 20.0, 30.0}}})
local v = ds["vendas"]:view(1, 2)   -- zero-copy
v:set(1, 99.0)                       -- materializa aqui
print(ds["vendas"]:get(1))           -- 10.0  (original intacto)
print(v:get(1))                      -- 99.0
```

---

## Filosofia

Smaug é fluido e robusto — uma engine feita para processar dados.

Robustez é funcionalidade. Testes não são suporte às funcionalidades, são
funcionalidades. Cobertura é ferramenta de confiança, não métrica de vaidade.
Valgrind é parte do desenvolvimento, não etapa final. A capacidade de
sobreviver a entradas inválidas é tão importante quanto qualquer operação matemática.

E o design importa. O Smaug precisa ser confiável e fluido — uma API que
funciona mas é difícil de escrever entregou só metade do trabalho. O fluxo
de dados deve ser natural de ler e conciso de compor.

---

## Qualidade

| métrica | valor | |
|---|---|---|
| cobertura de linhas | 97.95% — 1909/1949 | [Coverage](COVERAGE.md) |
| branch-alvo (MC/DC) | 92.18% — 1981/2149 ramos | [Coverage](COVERAGE.md) |
| checks OOM (allocfail) | 1158 verificações | [Build and Testing](Build_and_Testing.md) |
| checks property-based | 360 862 | [Build and Testing](Build_and_Testing.md) |
| Valgrind | clean em todos os 10 binários | [Build and Testing](Build_and_Testing.md) |
| warnings `-Wall -Wextra` | zero | [Contract](CONTRACT.md) |

Modelo de referência: SQLite.

---

## Build

**Linux (desenvolvimento e cobertura)**

```bash
bash scripts/build.sh        # build + todos os testes
bash scripts/build.sh --all  # idem + Valgrind + coverage + manifest
make coverage                 # só cobertura (gcov)
```

**Windows (MSYS2-UCRT64)**

```powershell
scripts/windows_build.ps1
```

---

## Documentação

### Entender o projeto
| | |
|---|---|
| [Architecture](ARCHITECTURE.md) | modelo de anéis, princípios, régua de versões |
| [Roadmap](Roadmap.md) | estado de cada anel, entregas planejadas |
| [Contract](CONTRACT.md) | contratos de comportamento Anel 0 e Anel 1 |
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
