# Views e Copy-on-Write

Uma view é uma janela zero-copy sobre uma faixa de elementos de uma série.
Compartilha o buffer do pai até a primeira escrita — aí materializa um buffer
privado automaticamente. O pai nunca é tocado.

---

## Criar uma view é O(1)

```lua
local smaug = require("smaug")

local payload = {{"vendas", {10.0, 20.0, 30.0, 40.0, 50.0}}}
local ds = smaug.DataSet(payload)

local v = ds["vendas"]:view(2, 3)   -- janela sobre [20, 30, 40]

print(v:get(1))
print(v:len())
```

```
20.0
3
```

Nenhum dado copiado. Apenas o struct da view é alocado.

---

## Leitura reflete o pai

```lua
local smaug = require("smaug")

local payload = {{"vendas", {10.0, 20.0, 30.0}}}
local ds = smaug.DataSet(payload)
local v  = ds["vendas"]:view(1, 2)

ds["vendas"]:set(1, 99.0)   -- muta o pai

print(v:get(1))              -- view ainda aponta pro pai
```

```
99.0
```

Antes de qualquer escrita na view, leituras refletem mutações no pai.

---

## Primeira escrita dispara o detach

```lua
local smaug = require("smaug")

local payload = {{"vendas", {10.0, 20.0, 30.0, 40.0, 50.0}}}
local ds = smaug.DataSet(payload)
local v  = ds["vendas"]:view(2, 3)   -- janela: [20, 30, 40]

v:set(1, 99.0)   -- detach aqui — buffer privado criado com [20, 30, 40]

print(v:get(1))
print(ds["vendas"]:get(2))  -- pai intacto
```

```
99.0
20.0
```

O detach copia apenas a janela (3 elementos), não o pai inteiro (5 elementos).
Escritas subsequentes vão direto ao buffer privado — sem nova cópia.

---

## Views de views

```lua
local smaug = require("smaug")

local payload = {{"vendas", {10.0, 20.0, 30.0, 40.0, 50.0}}}
local ds = smaug.DataSet(payload)

local v1 = ds["vendas"]:view(2, 4)   -- janela sobre ds["vendas"]
local v2 = v1:view(1, 2)             -- janela sobre v1

v2:set(1, 99.0)   -- detach de v2 apenas

print(v2:get(1))
print(v1:get(1))              -- v1 intacta
print(ds["vendas"]:get(2))   -- pai intacto
```

```
99.0
20.0
20.0
```

O detach afeta apenas a view imediata. `v1` continua sendo view de `ds["vendas"]`.

---

## Falha segura no detach (OOM)

O detach aloca memória. Se falhar:

- `set` / `set_null` → retornam `SMG_ERR_NOMEM`; view continua apontando pro pai;
  nenhuma escrita ocorre.
- `append` / `append_null` → retornam `-1`; mesmas garantias.

Em qualquer caso: pai intacto, view intacta, sistema consistente.

---

## O que dispara o detach

| operação Lua | C |
|---|---|
| `v:set(i, val)` | `smaug_f64_set` / `smaug_i64_set` |
| `v:set_null(i)` | `smaug_f64_set_null` / `smaug_i64_set_null` |
| `v:append(val)` | `smaug_f64_append` / `smaug_i64_append` |
| `v:append(nil)` | `smaug_f64_append_null` / `smaug_i64_append_null` |

## O que NÃO dispara o detach

Operações que produzem novo objeto nunca tocam o armazenamento compartilhado:
`get`, `is_null`, `len`, `count_nonnull`, `clone`, `filter`, `take`, `sort`,
`argsort`, comparações, aritméticas.

---

## Tipos suportados

| dtype | view | COW |
|---|---|---|
| `float64` | ✅ | ✅ |
| `int64` | ✅ | ✅ |
| `string` | ❌ (futuro) | — |
| `bool` | ❌ (imutável por construção) | — |

`BoolSeries` são resultados de comparações — imutáveis por natureza.
`string` não tem view ainda; quando ganhar, o detach será mais complexo
(buffer de bytes + offsets rebaseados).

---

## Resumo do contrato

1. Criar uma view é O(1) — sem cópia de dados.
2. Leitura antes de qualquer escrita reflete o estado atual do pai.
3. A primeira escrita dispara COW detach automaticamente.
4. O detach copia apenas a janela, não o pai inteiro.
5. Após o detach, a view é independente — o pai pode ser liberado sem afetar a view.
6. Falha de OOM no detach é segura — operação retorna erro, sistema intacto.
7. Todas as mutações respeitam este contrato uniformemente — sem exceções.
