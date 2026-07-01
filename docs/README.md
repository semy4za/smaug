# 🐉 Smaug

Biblioteca de dados tabulares em Lua com backend em C puro.
Dtypes: `float64`, `int64`, `bool`, `string`, `datetime`, `categorical`. Null por bitmask. Zero dependências externas.

---

## Começando

Os valores nascem tipados por inferência — você só declara o dtype quando a
inferência não alcança (`bool`, `datetime`, `categorical`).

```lua
local smaug = require("smaug")
local NA    = smaug.NA

local ds = smaug.DataSet({
    {"cidade", {"SP", "RJ", "SP", "MG"}},
    {"vendas", {120,   85,  200,  NA}},
    {"ativo",  {true, false, true, true}, "bool"},
})

print(ds)
```

```
DataSet 'DataSet' [4 linhas x 3 colunas]
   cidade  vendas  ativo
1  SP      120     true
2  RJ      85      false
3  SP      200     true
4  MG      NA      true
```

Aqui `cidade` virou `string` e `vendas` virou `int64` (todos inteiros) por
inferência; `ativo` recebeu `bool` explícito. Um `120.0` no lugar de `120` já
bastaria para inferir `float64`.

---

## Series

Uma coluna tipada. Toda operação retorna uma nova Series — imutabilidade por padrão.

```lua
print(ds["vendas"])
```

```
Series 'vendas' (int64, len=4)
  [1] 120
  [2] 85
  [3] 200
  [4] NA
```

### Reduções

Uma redução colapsa cada coluna num único valor. No DataSet, o resultado é um
frame de uma linha:

```lua
local ds = smaug.DataSet({
    {"vendas", {100.0, 200.0, 150.0, 300.0}},
    {"custo",  {30.0,  70.0,  50.0,  120.0}},
})

print(ds:sum())
print(ds:mean())
```

```
DataSet 'DataSet_sum' [1 linhas x 2 colunas]
   vendas  custo
1  750     270

DataSet 'DataSet_mean' [1 linhas x 2 colunas]
   vendas  custo
1  187.5   67.5
```

A mesma redução existe na Series, devolvendo o escalar direto (`s:sum()`,
`s:mean()`, `s:median()`, `s:min()`, `s:max()`, `s:std()`, `s:var()`,
`s:prod()`, `s:quantile(p)`, `s:argmin()`, `s:argmax()`). Estatística estendida:
`skew`, `kurtosis`, `mad`, `sem`, `rank`, `pct_rank`, `nlargest`, `nsmallest`.

### Nulos

`null` é ausência explícita, guardada em bitmask — não é `NaN`, não é zero.

```lua
local s = smaug.DataSet({{"v", {1.0, NA, NA, 4.0, NA}}})["v"]

print(s:ffill())
```

```
Series 'v' (float64, len=5)
  [1] 1
  [2] 1
  [3] 1
  [4] 4
  [5] 4
```

`bfill`, `fillna(valor)`, `dropna`, `is_null`/`isna`, `notna` completam o
conjunto.

### Janela deslizante e cumulativas

```lua
local s = smaug.DataSet({{"v", {1, 2, 3, 4, 5, 6}}})["v"]

print(s:rolling(3):sum())
```

```
Series 'v' (float64, len=6)
  [1] NA
  [2] NA
  [3] 6
  [4] 9
  [5] 12
  [6] 15
```

O motor de janela cobre `sum`/`mean`/`min`/`max`/`std`/`var`/`count`, com
`min_periods(k)` para janela parcial e `expanding()` para janela crescente
(`median`/`quantile` também disponíveis). Cumulativas: `cumsum`, `cumprod`,
`cummin`, `cummax`, `diff`, `shift`.

### Substituição condicional

```lua
local s = smaug.DataSet({{"v", {1, 2, 3, 4, 5}}})["v"]

print(s:where(s:gt(3), 0.0))   -- mantém onde a condição é true, 0 no resto
```

```
Series 'v' (int64, len=5)
  [1] 0
  [2] 0
  [3] 0
  [4] 4
  [5] 5
```

`mask` é o inverso (zera onde é true). `Series.ifelse(cond, a, b)` escolhe
elemento a elemento entre duas Series.

### Comparações e lógica Kleene

```lua
local s = smaug.DataSet({{"v", {10, 20, 30}}})["v"]

print(s:gt(15))
```

```
Series 'v' (bool, len=3)
  [1] false
  [2] true
  [3] true
```

`eq`, `ne`, `ge`, `le`, `lt` retornam `Series<bool>`. A lógica de três valores
(`land`, `lor`, `lnot`) propaga `NA` corretamente.

### Matemática vetorizada

```lua
local s = smaug.DataSet({{"v", {0.0, 1.0, 4.0, 9.0}}})["v"]

print(s:sqrt())
```

```
Series 'v' (float64, len=4)
  [1] 0
  [2] 1
  [3] 2
  [4] 3
```

`exp`, `log`, `sin`, `cos`, `tan`, `abs`, `round(n)`, `clip(lo, hi)` seguem o
mesmo padrão element-wise.

### `.str` — texto

```lua
local nomes = smaug.DataSet({{"c", {"  São Paulo  ", "rio", "MINAS"}}})["c"]

print(nomes.str:strip())
```

```
Series 'c' (string, len=3)
  [1] São Paulo
  [2] rio
  [3] MINAS
```

Também: `lower`, `upper`, `len`, `contains`, `startswith`, `endswith`,
`replace`, `find`, `slice`, `pad`, `zfill`, `rep_each`, `cat`, `split`. Opera
sobre bytes (não normaliza UTF-8); comparação é lexicográfica por byte.

### `.dt` — calendário

Datetime pede dtype explícito (não há como inferir de strings ISO):

```lua
local ds = smaug.DataSet({
    {"data", {"2026-01-15T12:30:00Z", "2026-06-30T00:00:00Z"}, "datetime"},
})

print(ds["data"].dt:year())
```

```
Series 'data' (int64, len=2)
  [1] 2026
  [2] 2026
```

`month`, `quarter`, `weekday`, `format`, `truncate("M")`, `add_days(n)`, `diff`
e os helpers estáticos `dt_parse` / `dt_from_parts` completam o módulo.

### Series categorical

Dictionary encoding em Lua puro — compacto e com igualdade rápida, ideal para
colunas de baixa cardinalidade (cidades, status, categorias). Também pede dtype
explícito:

```lua
local ds = smaug.DataSet({
    {"uf", {"SP", "RJ", "SP", "MG"}, "categorical"},
})

print(ds["uf"].cat:codes())
```

```
Series 'uf' (int64, len=4)
  [1] 1
  [2] 2
  [3] 1
  [4] 3
```

`levels()` devolve `{"SP", "RJ", "MG"}` (ordem de 1ª aparição).
`rename_categories`, `set_categories`, `add_categories` reorganizam os níveis
sem tocar os dados.

---

## DataSet

Coleção de Series alinhadas. Toda operação retorna um novo DataSet.

```lua
local ds = smaug.DataSet({
    {"uf",    {"SP", "RJ", "SP", "MG"}},
    {"venda", {100.0, 200.0, 150.0, 300.0}},
})
```

### Inspecionar

```lua
ds:nrows()
ds:ncols()
ds:columns()
ds:dtypes()
ds:describe()
print(ds)
```

`nrows`/`ncols` dão as dimensões; `columns` lista os nomes; `dtypes` mapeia cada
coluna ao seu tipo; `describe` resume estatísticas por coluna; `print(ds)`
formata a tabela.

### Acesso e seleção

Acessar uma coluna devolve uma **view protegida** do frame: ler é zero-copy,
mas mutá-la não altera o DataSet original.

```lua
ds["venda"]                 -- Series<float64> (view COW do frame)
ds:col("uf")                -- idem
ds:head(3)                  -- primeiras 3 linhas
ds:iloc(2, 4)               -- linhas 2–3 (topo exclusivo)
ds:select({"uf", "venda"})  -- subconjunto de colunas
```

### Filtrar

```lua
print(ds:filter(ds["venda"]:gt(150.0)))
```

```
DataSet 'DataSet' [2 linhas x 2 colunas]
   uf  venda
1  RJ  200
2  MG  300
```

Açúcar sintático `ds[mask]` e condições compostas via Kleene:
`ds[ds["venda"]:gt(100.0):land(ds["uf"]:eq("SP"))]`.

### Ordenar e mutar

```lua
ds:sort_by("venda", false)                              -- decrescente
ds:sort_by({"uf", "venda"})                             -- chave composta

ds:assign("desconto", function(d) return d["venda"] * 0.1 end)
ds:update_column("venda", nova_series)                  -- mutação intencional
ds:rename({uf = "estado"})                              -- em lote
ds:drop_column("uf")
```

### GroupBy

```lua
local ds = smaug.DataSet({
    {"uf",    {"SP", "RJ", "SP", "MG"}},
    {"venda", {100.0, 200.0, 150.0, 300.0}},
})

print(ds:groupby("uf"):agg({venda = {"sum", "mean"}}))
```

```
DataSet 'DataSet_groupby' [3 linhas x 3 colunas]
   uf  venda_sum  venda_mean
1  MG  300        300
2  RJ  200        200
3  SP  250        125
```

Agregações individuais (`sum`, `mean`, `min`, `max`, `count`, `std`, `var`,
`median`, `prod`, `first`, `last`, `nunique`, `quantile`), chave composta e
`transform` (broadcast do resultado de volta ao tamanho original).

### Join

```lua
local ds   = smaug.DataSet({{"uf", {"SP", "RJ", "MG"}}, {"venda", {100.0, 200.0, 300.0}}})
local meta = smaug.DataSet({{"uf", {"SP", "RJ", "MG"}}, {"regiao", {"Sudeste", "Sudeste", "Sudeste"}}})

print(ds:join(meta, "uf"))
```

```
DataSet 'DataSet_join_DataSet' [3 linhas x 3 colunas]
   uf  venda  regiao
1  SP  100    Sudeste
2  RJ  200    Sudeste
3  MG  300    Sudeste
```

Modos `inner` (default), `left`, `outer` e chave composta.

### Concat e Reshape

```lua
smaug.concat({ds, ds2, ds3})                 -- empilha verticalmente
ds:pivot("uf", "marca", "venda")             -- long → wide
ds:pivot_table("uf", "marca", "venda", "sum")
wide:melt({"id"}, {"a", "b"}, "var", "val")  -- wide → long
wide:stack({"a", "b"})                       -- colunas → linhas
ds:explode("tags")                           -- lista → linhas
```

### Rolling no DataSet

```lua
ds:rolling(3):sum("venda")
ds:rolling(3):mean("venda")
```

### View Copy-on-Write

Views são zero-copy até a primeira escrita, que materializa um buffer privado —
o objeto pai nunca é tocado. Vale para todos os dtypes com buffer, incluindo
`string` (via posse mista — ver [COW](COW.md)).

```lua
local s   = smaug.DataSet({{"v", {10, 20, 30, 40, 50}}})["v"]
local sub = s:view(2, 3)   -- janela [20, 30, 40], compartilha buffer
sub:set(1, 999.0)          -- detach: materializa buffer privado
-- s permanece intacta
```

---

## I/O

Parsers próprios em C puro, zero dependências.

```lua
local ds = smaug.read_csv("pedidos.csv")
local ds = smaug.read_csv("pedidos.csv", {sep = ";", header = true})
ds:to_csv("saida.csv")

local ds = smaug.read_json("dados.json")   -- array de records
ds:to_json("saida.json", {pretty = true})
```

Variantes em memória (`read_csv_mem`, `to_csv_mem`, `read_json_mem`,
`to_json_mem`) trabalham direto com strings Lua. O CSV infere tipo por coluna
(`int64` → `float64` → `bool` → `string`); células vazias, `NA`, `null`, `N/A`,
`nan`, `NaN`, `NULL` viram `null`.

---

## Tipos e nulos

`null` não é `NaN`, não é zero, não é string vazia. É ausência explícita,
armazenada em bitmask dedicada.

| dtype | descrição | nulo |
|---|---|---|
| `float64` | IEEE 754 dupla precisão | bitmask |
| `int64` | inteiro com sinal 64-bit | bitmask |
| `bool` | Kleene (true/false/NA) | bitmask |
| `string` | offset-based, estilo Arrow | bitmask |
| `datetime` | epoch ms UTC (int64 interno) | bitmask |
| `categorical` | dictionary encoding (Lua puro) | `_codes[i] == nil` |

```lua
local s = smaug.DataSet({{"v", {0/0, NA, 1.0}}})["v"]

s:is_null(1)
s:is_null(2)
```

O primeiro elemento é `NaN` — um valor presente — então `is_null(1)` é falso. O
segundo é `NA`, ausência explícita, então `is_null(2)` é verdadeiro. É a
distinção central: `NaN` não é `null`.

`null` propaga em aritmética; `NaN` contamina reduções (`ignore_na` pula `null`,
não `NaN`); divisão por zero → `null` (não `NaN`, não `Inf`).

> **int64 acima de 2^53:** um literal Lua grande (ex. `9007199254740993`) já
> chega truncado, porque o Lua o representa como `double` antes de entrar na
> lib. Para preservar os 64 bits, use `ffi.new("int64_t", ...)` ou o sufixo
> `LL`, e leia de volta com `s:get_raw(i)` (o `get` normal converte para
> `double`). Valores acima de 2^53 disparam aviso.

---

## Qualidade

| métrica | valor |
|---|---|
| cobertura (linha + branch-alvo MC/DC) | ver `COVERAGE.md` (gerado no Fedora) |
| testes OOM (allocfail via `--wrap`) | todos os pontos públicos dos Anéis 0+3 |
| testes property-based | invariantes × seeds × casos |
| testes de stress | N=1M, chains, views, ciclos |
| Valgrind | clean em todos os binários |
| warnings `-Wall -Wextra` | zero |
| suítes de teste | C em `tests/c/`, Lua em `tests/{series,dataset,io,props}/` |

Números exatos vivem nas fontes geradas — output do `build.sh`, `COVERAGE.md`,
`MANIFEST.txt` — nunca cravados aqui, para não defasarem.

---

## Build

```bash
# Linux
bash scripts/build.sh        # build + testes
bash scripts/build.sh --all  # + Valgrind + coverage + manifest
```

```powershell
# Windows (MSYS2-UCRT64)
scripts/windows_build.ps1
```

---

## Documentação

| | |
|---|---|
| [Architecture](ARCHITECTURE.md) | modelo de anéis e régua de versões |
| [Roadmap](Roadmap.md) | estado atual e pré-1.0 |
| [API Index](API_INDEX.md) | catálogo rápido de métodos |
| [API Reference](API_Reference.md) | referência do backend C |
| [Build and Testing](Build_and_Testing.md) | compilação, testes, cobertura |
| [Contract](CONTRACT.md) | contratos defensivos do backend |
| [COW](COW.md) | especificação Copy-on-Write |
| [Changelog](CHANGELOG.md) | histórico de mudanças |
