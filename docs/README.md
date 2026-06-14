# 🐉 Smaug

Biblioteca de dados tabulares em Lua com backend em C puro.
Dtypes: `float64`, `int64`, `bool`, `string`. Null por bitmask. Zero dependências externas.

---

## Começando

```lua
local smaug = require("smaug")
local NA    = smaug.NA

local ds = smaug.DataSet({
    {"cidade",  {"SP", "RJ", "SP", "MG"},         "string"},
    {"vendas",  {120,   85,  200,  NA}                    },
    {"ativo",   {true, false, true, true},          "bool"},
})

print(ds)
```

```
DataSet '' [4 linhas x 3 colunas]
   cidade  vendas  ativo
1  SP      120     true
2  RJ      85      false
3  SP      200     true
4  MG      NA      true
```

---

## Series

Uma coluna tipada. Toda operação retorna uma nova Series — imutabilidade por padrão.

```lua
local s = smaug.Series.from_table({4, 7, 2, 9, 1, 5, 8, 3, 6}, "float64")

-- reduções
s:sum()       -- 45
s:mean()      -- 5.0
s:median()    -- 5
s:min()       -- 1       s:max()    -- 9
s:std()       -- 2.739   s:var()    -- 7.5
s:prod()      -- 362880
s:quantile(0.75)  -- 7.0
s:mad()           -- 2       (desvio absoluto mediano)
s:sem()           -- 0.913   (erro padrão da média)
s:skew()          -- 0.0
s:kurtosis()      -- -1.23

-- posição
s:argmin()  -- 5   (índice do menor)
s:argmax()  -- 4   (índice do maior)

-- ranking
s:rank()            -- {4, 7, 2, 9, 1, 5, 8, 3, 6} → posições 1-based
s:pct_rank()        -- normalizado em [0, 1]

-- seleção
s:nlargest(3)       -- {9, 8, 7}
s:nsmallest(3)      -- {1, 2, 3}
```

### Nulos

```lua
local NA = smaug.NA
local s = smaug.Series.from_table({1.0, NA, NA, 4.0, NA}, "float64")

s:is_null(2)    -- true
s:isna(2)       -- alias
s:notna(1)      -- true

s:ffill():to_table()  -- {1.0, 1.0, 1.0, 4.0, 4.0}
s:bfill():to_table()  -- {1.0, 4.0, 4.0, 4.0, NA}
s:fillna(0.0)         -- substitui NA por 0.0
s:dropna()            -- remove NAs
```

### Transformações de janela

```lua
local s = smaug.Series.from_table({1, 2, 3, 4, 5, 6}, "float64")

-- cumulativas
s:cumsum()    -- {1, 3, 6, 10, 15, 21}
s:cumprod()   -- {1, 2, 6, 24, 120, 720}
s:cummin()    -- {1, 1, 1,  1,  1,  1}
s:cummax()    -- {1, 2, 3,  4,  5,  6}
s:diff()      -- {NA, 1, 1, 1, 1, 1}
s:shift(2)    -- {NA, NA, 1, 2, 3, 4}

-- rolling (janela deslizante)
s:rolling(3):sum()      -- {NA, NA, 6, 9, 12, 15}
s:rolling(3):mean()     -- {NA, NA, 2, 3,  4,  5}
s:rolling(3):std()      -- {NA, NA, 1, 1,  1,  1}
s:rolling(3):var()
s:rolling(3):min()
s:rolling(3):max()
s:rolling(3):count()    -- não-nulos na janela
s:rolling(3):median()
s:rolling(3):quantile(0.5)

-- min_periods: produz resultado com janela parcial
s:rolling(3):min_periods(2):std()  -- resultado a partir da posição 2

-- expanding (janela crescente)
s:expanding():sum()     -- {1, 3, 6, 10, 15, 21}
s:expanding():mean()    -- {1, 1.5, 2, 2.5, 3, 3.5}
s:expanding():std()
s:expanding():min_periods(2):std()
```

### Substituição condicional

```lua
local s    = smaug.Series.from_table({1.0, 2.0, 3.0, 4.0, 5.0}, "float64")
local cond = s:gt(3)

s:where(cond, 0.0)   -- {0, 0, 0, 4, 5}  mantém onde true, 0 onde false
s:mask(cond, 0.0)    -- {1, 2, 3, 0, 0}  inverso do where
smaug.Series.ifelse(cond, s, smaug.Series.full(5, 0.0, "float64"))
```

### Matemática vetorizada

```lua
local s = smaug.Series.from_table({0.0, 1.0, 4.0, 9.0}, "float64")

s:sqrt()   -- {0, 1, 2, 3}
s:exp()    -- {1, e, e⁴, e⁹}
s:log()    -- {-inf, 0, 1.386, 2.197}
s:sin()
s:cos()
s:tan()
```

### Comparações e Bool

```lua
local s = smaug.Series.from_table({10, 20, 30}, "int64")

s:gt(15)   -- Series<bool>: {false, true, true}
s:eq(20)   -- {false, true, false}
s:ne(20)   -- {true, false, true}
s:ge(20)   -- {false, true, true}

-- lógica Kleene
local a = s:gt(15)
local b = s:lt(25)
a:land(b)  -- AND: {false, true, false}
a:lor(b)   -- OR:  {true,  true, true}
a:lnot()   -- NOT: {true, false, false}
```

### Outras operações

```lua
local s = smaug.Series.from_table({"SP","RJ","SP","MG","RJ"}, "string")

s:unique()          -- {"SP","RJ","MG"}  (ordem de 1ª aparição)
s:nunique()         -- 3
s:value_counts()    -- DataSet {value, count} ordenado por freq

local n = smaug.Series.from_table({-3.0, 1.5, 2.7}, "float64")
n:abs()             -- {3.0, 1.5, 2.7}
n:round(1)          -- {-3.0, 1.5, 2.7}
n:clip(0.0, 2.0)    -- {0.0, 1.5, 2.0}
n:sort()            -- nova Series ordenada
n:argsort()         -- permutação de ordenação
n:rank("min")       -- rank com método "min"/"max"/"first"/"average"
n:pct_rank()        -- rank normalizado em [0,1]

-- astype
smaug.Series.from_table({"1.5","2.0","abc"}, "string"):astype("float64")
-- {1.5, 2.0, null}  — inconversíveis viram null, nunca erro
```

### `.str` — operações sobre Series string

```lua
local cidades = smaug.Series.from_table({"  São Paulo  ", "rio", "MINAS"}, "string")

cidades.str:strip()            -- {"São Paulo", "rio", "MINAS"}
cidades.str:lower()            -- {"  são paulo  ", "rio", "minas"}
cidades.str:upper()            -- {"  SÃO PAULO  ", "RIO", "MINAS"}
cidades.str:len()              -- Series<int64>: comprimentos em bytes
cidades.str:contains("Paulo") -- Series<bool>
cidades.str:startswith("rio")
cidades.str:endswith("S")
cidades.str:replace("Paulo", "P.")
cidades.str:find("Paulo")      -- índice 1-based (0 se ausente)
cidades.str:slice(1, 3)        -- primeiros 3 bytes
cidades.str:pad(10, "right")   -- preenche até 10 chars
cidades.str:zfill(6)           -- pad com '0'
cidades.str:rep(2, "-")        -- repete com separador
cidades.str:cat(", ")          -- concatena tudo → string Lua
cidades.str:split(" ")         -- divide → tabela de Series
```

---

## DataSet

Coleção de Series alinhadas. Toda operação retorna um novo DataSet.

```lua
local ds = smaug.DataSet({
    {"uf",    {"SP","RJ","SP","MG","RJ","SP"}, "string"},
    {"venda", {100.0,200.0,150.0,300.0,250.0,120.0},   },
    {"marca", {"A","B","A","A","B","B"},        "string"},
})
```

### Inspecionar

```lua
ds:nrows()     -- 6
ds:ncols()     -- 3
ds:columns()   -- {"uf","venda","marca"}
ds:dtypes()    -- {uf="string", venda="float64", marca="string"}
ds:describe()
print(ds)      -- tabela formatada
```

### Acesso e seleção

```lua
ds["venda"]              -- Series<float64>
ds:col("uf")             -- idem
ds:has_column("marca")   -- true

ds:head(3)               -- primeiras 3 linhas
ds:tail(2)               -- últimas 2 linhas
ds:iloc(2, 4)            -- linhas 2–3 (índice Lua, exclusivo no topo)
ds:sample(3)             -- 3 linhas aleatórias
ds:select({"uf","venda"})-- subconjunto de colunas
ds:row(1)                -- linha 1 como tabela Lua
```

### Filtrar

```lua
-- filtro simples
ds:filter(ds["venda"]:gt(150.0))

-- açúcar sintático: ds[mask]
ds[ds["uf"]:eq("SP")]

-- múltiplas condições (Kleene)
ds[ds["venda"]:gt(100.0):land(ds["marca"]:eq("A"))]
```

### Ordenar e mutar

```lua
ds:sort_by("venda", false)     -- decrescente
ds:sort_by({"uf", "venda"})    -- chave composta

ds:assign("desconto", function(d) return d["venda"] * 0.1 end)
ds:assign("flag", smaug.Series.full(6, true, "bool"))
ds["nova_col"] = smaug.Series.from_table({1,2,3,4,5,6}, "int64")

ds:rename({uf="estado", venda="valor"})   -- em lote
ds:rename_column("marca", "produto")       -- uma coluna
ds:drop_column("marca")
```

### Nulos

```lua
ds:dropna()                   -- remove linhas com qualquer NA
ds:dropna({"venda","marca"})  -- só nessas colunas
ds:fillna(0.0)                -- todas as colunas numéricas
ds:fillna({venda=0.0})        -- coluna específica
```

### GroupBy

```lua
local gb = ds:groupby("uf")    -- chave simples
local gb = ds:groupby({"uf","marca"})  -- chave composta

-- agregações
gb:sum("venda")
gb:mean("venda")
gb:min("venda")   gb:max("venda")
gb:count()
gb:std("venda")   gb:var("venda")
gb:median("venda")
gb:prod("venda")
gb:first("venda") gb:last("venda")
gb:nunique("venda")
gb:quantile(0.75, "venda")

-- múltiplas agregações de uma vez
ds:groupby("uf"):agg({venda = {"sum","mean","std"}})
-- → DataSet com colunas: uf, venda_sum, venda_mean, venda_std

-- transform: broadcast do resultado de volta ao tamanho original
ds:groupby("uf"):transform("mean","venda")
-- → Series com a média do grupo para cada linha
```

### Join

```lua
local meta = smaug.DataSet({
    {"uf",     {"SP","RJ","MG"},        "string"},
    {"regiao", {"Sudeste","Sudeste","Sudeste"}, "string"},
})

ds:join(meta, "uf")              -- inner (default)
ds:join(meta, "uf", "left")      -- left
ds:join(meta, "uf", "outer")     -- outer
ds:join(meta, {"uf","marca"})    -- chave composta
```

### Concat

```lua
smaug.concat({ds, ds2, ds3})   -- empilha verticalmente
ds:concat(ds2)                  -- atalho para dois DataSets
```

### Reshape

```lua
-- pivot: long → wide
ds:pivot("uf", "marca", "venda")

-- pivot_table: pivot com agregação
ds:pivot_table("uf", "marca", "venda", "sum")
ds:pivot_table("uf", "marca", "venda", "mean")

-- melt: wide → long
wide:melt({"id"}, {"a","b"}, "variavel", "valor")

-- stack / unstack
wide:stack({"a","b"})             -- empilha colunas em linhas
long:unstack("index","col","val") -- inverso (pivot com first)

-- explode: lista → linhas
ds:explode("tags")   -- cada elemento da coluna vira uma linha
```

### Rolling no DataSet

```lua
ds:rolling(3):sum("venda")
ds:rolling(3):mean("venda")
ds:rolling(3):min("venda")
ds:rolling(3):max("venda")
```

### View Copy-on-Write

```lua
local s   = ds["venda"]
local sub = s:view(2, 3)   -- zero-copy: compartilha buffer
sub:set(1, 999.0)          -- materializa buffer privado
-- s inalterada
```

---

## I/O

Parsers próprios em C puro. Zero dependências externas.

```lua
-- CSV
local ds = smaug.read_csv("pedidos.csv")
local ds = smaug.read_csv("pedidos.csv", {sep=";", header=true})
local ds = smaug.read_csv_mem(buffer_string)
ds:to_csv("saida.csv")
ds:to_csv("saida.csv", {sep=","})
local s = ds:to_csv_mem()   -- retorna string Lua

-- JSON (array de records: [{...}, {...}])
local ds = smaug.read_json("dados.json")
local ds = smaug.read_json_mem(json_string)
ds:to_json("saida.json")
ds:to_json("saida.json", {pretty=true})
local s = ds:to_json_mem()

-- Inferência automática de tipo no CSV
-- int64 → float64 → bool → string (ordem de teste)
-- Células vazias, "NA", "null", "N/A", "nan", "NaN", "NULL" → null
```

---

## Construção

```lua
-- DataSet inline
local ds = smaug.DataSet({
    {"nome",   {"Ana", "Bruno"}, "string"},
    {"idade",  {28, 35},         "int64"},
    {"ativo",  {true, false},    "bool"},
    {"score",  {9.5, 7.2}              },   -- dtype inferido: float64
})

-- Series fábrica
smaug.Series.from_table({1, 2, 3}, "int64")
smaug.Series.from_table({"a","b","c"}, "string")
smaug.Series.full(5, 0.0, "float64")   -- {0,0,0,0,0}

-- Sentinela de nulo
local NA = smaug.NA
smaug.Series.from_table({1, NA, 3}, "int64")  -- elemento 2 = null
```

---

## Tipos e nulos

`null` não é `NaN`, não é zero, não é string vazia.
É ausência explícita, armazenada em bitmask dedicada.

| dtype | descrição | nulo |
|---|---|---|
| `float64` | IEEE 754 dupla precisão | bitmask |
| `int64` | inteiro com sinal 64-bit | bitmask |
| `bool` | Kleene (true/false/NA) | bitmask |
| `string` | offset-based, estilo Arrow | bitmask |

```lua
-- NaN ≠ null
local s = smaug.Series.from_table({0/0, NA, 1.0}, "float64")
s:is_null(1)   -- false  (NaN é valor presente)
s:is_null(2)   -- true   (NA é ausência)
s:is_null(3)   -- false

-- null propaga em aritmética
-- NaN contamina reduções (ignore_na pula null, não NaN)
-- div/0 → null (não NaN, não Inf)
```

---

## Qualidade

| métrica | valor |
|---|---|
| cobertura de linhas | 97.95% |
| branch-alvo (MC/DC) | 92.18% |
| checks OOM (allocfail) | 1 158 verificações |
| checks property-based | 360 862 |
| Valgrind | clean em todos os binários |
| warnings `-Wall -Wextra` | zero |

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
