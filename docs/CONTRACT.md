# Contrato Defensivo — Smaug

Este documento especifica os contratos de comportamento do Ring 1 (frontend Lua)
e do Ring 0 (backend C). Um contrato aqui significa: comportamento garantido,
testado, e que não muda sem decisão explícita e versionada.

---

## Ring 1 — Frontend Lua

### Contrato 1 — sem coerção implícita de dtype

```lua
local smaug = require("smaug")

local payload = {
    {"produto", {"caneta", "caderno", "régua"}, "string"},
    {"qtd",     {10, 5, 8},                    "int64"},
}
local ds = smaug.DataSet(payload)

ds["qtd"]:set(1, 1.5)   -- erro
ds["qtd"]:set(1, "x")   -- erro
ds["qtd"]:set(1, 12)    -- ok
```

```
smaug: valor para int64 deve ser inteiro (sem coerção)
smaug: valor para int64 deve ser inteiro (sem coerção)
```

O frontend recusa qualquer valor que exigiria coerção silenciosa. Não há
surpresa de truncagem, arredondamento ou conversão implícita. Quando o dtype
importa, ele é explícito — sempre.

---

### Contrato 2 — `astype` converte por elemento, tolerante a falha

```lua
local smaug = require("smaug")

local payload = {
    {"valor_str", {"1.5", "abc", smaug.NA, "3.0"}, "string"},
}
local ds = smaug.DataSet(payload)
local f  = ds["valor_str"]:astype("float64")

print(f:get(1))
print(f:is_null(2))
print(f:is_null(3))
print(f:get(4))
```

```
1.5
true
true
3.0
```

`astype` para `float64`/`int64`/`string`/`datetime` nunca lança erro por causa de
um elemento individual. Elementos inconversíveis tornam-se `null` — a série inteira
não é descartada por um dado ruim. Operações em lote são tolerantes a dados imperfeitos.

**Exceção — `astype("bool")` a partir de numérico é estrito:** aceita só `0`/`1`;
qualquer outro valor lança erro que orienta para `:map(fn)`. A regra de truthiness
não é imposta silenciosamente — quem quer defini-la usa `map`.

---

### Contrato 3 — `fillna` não muta, não coerce

```lua
local smaug = require("smaug")

local payload = {
    {"vendas", {1.0, smaug.NA, 0/0, smaug.NA}},
}
local ds = smaug.DataSet(payload)
local f  = ds["vendas"]:fillna(0.0)

print(ds["vendas"]:is_null(2))
print(f:is_null(2))
print(f:get(2))
print(f:get(3) ~= f:get(3))

ds["vendas"]:fillna(1)   -- erro
```

```
true
false
0.0
true
smaug: fillna em série float64 espera um número
```

`fillna` devolve nova série — o original é imutável. `NaN` é preservado:
`fillna` substitui `null` (ausência), não `NaN` (valor indefinido presente).
São coisas distintas no Smaug.

---

### Contrato 4 — `DataSet` nunca existe desalinhado

```lua
local smaug = require("smaug")

local payload = {
    {"cidade", {"SP", "RJ", "MG"}, "string"},
    {"vendas", {120, 85},          "float64"},
}
local ds = smaug.DataSet(payload)   -- erro
```

```
smaug: coluna 'vendas' tem 2 elemento(s); DataSet tem 3
```

Toda coluna de um DataSet tem o mesmo número de linhas. Violação é erro
imediato — não existe estado intermediário desalinhado.

---

### Contrato 5 — `BoolSeries` é coluna de primeira classe

```lua
local smaug = require("smaug")

local payload = {
    {"nome",  {"Ana", "Bruno", "Carol"}, "string"},
    {"ativo", {true, false, true},       "bool"},
}
local ds = smaug.DataSet(payload)

print(ds:filter(ds["ativo"]):nrows())
ds["ativo"] = ds["ativo"]:lnot()
local d = ds["ativo"]:describe()
print(d.count, d.nulls, d.count_true, d.count_false)
```

```
2
3	0	1	2
```

Toda coluna aceita pelo DataSet funciona em toda a API do DataSet. O dtype
da coluna não cria casos especiais na API.

---

### Contrato 6 — `filter` descarta `NA` na máscara

```lua
local smaug = require("smaug")

local payload = {
    {"cidade", {"SP", "RJ", "MG", "SP"}, "string"},
    {"vendas", {10,   20,   30,   40}},
}
local ds   = smaug.DataSet(payload)
local mask = ds["cidade"]:eq("SP")
mask:set_null(1)

local r = ds:filter(mask)
print(r:nrows())
print(r["cidade"]:get(1))
```

```
1
SP
```

`NA` na máscara descarta a linha — linha de origem desconhecida não passa.
`filter` nunca lança erro por `NA` na máscara.

---

### Contrato 7 — índices são 1-based

```lua
local smaug = require("smaug")

local payload = {
    {"preco", {10.0, 20.0, 30.0}},
}
local ds = smaug.DataSet(payload)

print(ds["preco"]:get(1))
print(ds["preco"]:get(3))
ds["preco"]:get(0)   -- erro
```

```
10.0
30.0
smaug: índice 0 fora dos limites [1, 3]
```

Toda API pública Lua usa índices 1-based (convenção Lua). A conversão
0-based↔1-based é feita internamente — nunca exposta.

---

### Contrato 8 — `NA` em chave relacional é erro

```lua
local smaug = require("smaug")

local a = smaug.DataSet({
    {"cliente", {"A", smaug.Series.NA, "B"}, "string"},
    {"valor",   {10, 20, 30},               "int64"},
})
local b = smaug.DataSet({
    {"cliente", {"A", "B"}, "string"},
    {"cidade",  {"SP", "RJ"}, "string"},
})

a:join(b, "cliente")          -- erro
a:groupby("cliente"):count()  -- erro
a:pivot("cliente", "x", "valor")        -- erro (idem pivot_table)
```

```
smaug: join — coluna 'cliente' contém NA; trate com fillna ou dropna antes
smaug: groupby — coluna 'cliente' contém NA; trate com fillna ou dropna antes
smaug: pivot — coluna 'cliente' contém NA; trate com fillna ou dropna antes
```

`NA` é ausência que não participa (mesma filosofia do Contrato 6). Em chave
relacional — `join` (`on`), `groupby` (`by`), `pivot`/`pivot_table`
(`index`/`columns`) — `NA` **nunca** casa com `NA`, agrupa por `NA`, nem é
descartado em silêncio: a operação erra de forma orientada. "Falha visível >
acerto adivinhado" — o usuário decide com `fillna`/`dropna` na pipeline. Em chave
composta, `NA` em **qualquer** coluna da chave dispara, nomeando-a. A coluna de
**valores** não é chave e pode conter `NA` normalmente.

---

## Ring 0 — Backend C

### Princípio: o engine não confia no caller

Toda fronteira pública em C **valida e comunica**; nunca assume que o caller
validou. Garantias incondicionais:

1. **Validação na entrada.** Ponteiro, argumentos e índice são checados antes de
   qualquer acesso à memória. Entrada inválida nunca causa comportamento
   indefinido, corrupção ou crash evitável.
2. **Resultado observável.** Toda operação comunica sucesso/falha por código de
   status — o caller pode sempre saber se a operação pegou ou foi rejeitada.
3. **Falha segura.** Em erro não há escrita parcial; leitura devolve sentinela
   documentada e o estado permanece consistente.

### Códigos de status

```c
typedef enum {
    SMG_OK = 0,        /* operação concluída com sucesso          */
    SMG_NULL_VALUE,    /* leitura: elemento é NULL (não é erro)   */
    SMG_ERR_OOB,       /* índice fora dos limites                 */
    SMG_ERR_ARGUMENT,  /* ponteiro nulo / argumento inconsistente */
    SMG_ERR_NOMEM      /* falha de alocação (COW detach)          */
} smaug_status_t;
```

Espelhado no cdef do FFI (`lua/smaug/ffi_loader.lua`).

### Mutação pontual (`set` / `set_null`) — retorna `smaug_status_t`

Em erro, **nenhuma escrita** ocorre. Em views, dispara COW detach antes de
escrever.

| retorno | condição |
|---|---|
| `SMG_OK` | escrita aplicada |
| `SMG_ERR_OOB` | `idx >= size` — checado antes do detach |
| `SMG_ERR_ARGUMENT` | `s == NULL` |
| `SMG_ERR_NOMEM` | detach COW falhou por OOM — série intacta |

Funções: `f64_set`, `f64_set_null`, `i64_set`, `i64_set_null`, `str_set`,
`str_set_null`.

### Append dinâmico (`append` / `append_null`) — retorna `int` (0 / -1)

Convenção mantida. Em views, dispara COW detach antes do grow.
Falha → `-1`; série permanece consistente.

### Leitura (`get`) — Shape 1: valor + status anulável

`T smaug_<t>_get(const S *s, size_t idx, smaug_status_t *status)`

Retorna o valor; escreve `*status` se `status != NULL`. Sentinelas definidas
em erro (`NAN` para f64, `0` para i64) — seguro mesmo ignorando o status.

| caso | retorno | `*status` |
|---|---|---|
| sucesso | valor real | `SMG_OK` |
| elemento NULL | sentinela | `SMG_NULL_VALUE` |
| `idx >= size` | sentinela | `SMG_ERR_OOB` |
| `s == NULL` | sentinela | `SMG_ERR_ARGUMENT` |

### Copy-on-Write em views

Toda mutação em uma view materializa um buffer privado antes de escrever —
o objeto pai nunca é tocado.

- `set` / `set_null`: retornam `SMG_ERR_NOMEM` se o detach falhar.
- `append` / `append_null`: retornam `-1` se o detach ou o grow falharem.
- Em qualquer falha, view e pai permanecem intactos.

Cobertura: `float64`, `int64`, `datetime`, `bool` (buffers fixos, view O(1)) e
`string` (offset-based, view com posse mista — ver COW.md). Apenas `categorical`
não tem view (é Lua puro, sem buffer compartilhável).

Ver `docs/COW.md` para a especificação completa.
