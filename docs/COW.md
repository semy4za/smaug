# Views e Copy-on-Write

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

<details>
<summary>Nesta página</summary>

- [Criar uma view de tipo fixo é O(1)](#section-criar-uma-view-de-tipo-fixo-e-o-1)
- [Leitura reflete o pai](#section-leitura-reflete-o-pai)
- [Primeira escrita dispara o detach](#section-primeira-escrita-dispara-o-detach)
- [Views de views](#section-views-de-views)
- [Falha segura no detach (OOM)](#section-falha-segura-no-detach-oom)
- [O que dispara o detach](#section-o-que-dispara-o-detach)
- [O que NÃO dispara o detach](#section-o-que-nao-dispara-o-detach)
- [Tipos suportados](#section-tipos-suportados)
- [Resumo do contrato](#section-resumo-do-contrato)

</details>

Uma view é uma janela sobre uma faixa de elementos de uma série.
Compartilha o buffer do pai até a primeira escrita — aí materializa um buffer
privado automaticamente. O pai nunca é tocado.

---

<a id="section-criar-uma-view-de-tipo-fixo-e-o-1"></a>

## Criar uma view de tipo fixo é O(1)

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

Neste exemplo numérico, nenhum dado é copiado; apenas a struct é alocada.
String compartilha bytes e máscara, mas copia offsets: criação O(len).

---

<a id="section-leitura-reflete-o-pai"></a>

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

O exemplo demonstra alteração de valor em buffer numérico existente. Não
estabelece segurança para realocação, liberação do pai ou mudança de comprimento
de strings. Lifetime e invalidação nesses casos permanecem decisões abertas
na revisão da suíte; não se deve inferir garantia universal deste exemplo.

---

<a id="section-primeira-escrita-dispara-o-detach"></a>

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

<a id="section-views-de-views"></a>

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

<a id="section-falha-segura-no-detach-oom"></a>

## Falha segura no detach (OOM)

O detach aloca memória. O contrato de falha na API C é:

- `set` / `set_null` → retornam `SMG_ERR_NOMEM`; view continua apontando pro pai;
  nenhuma escrita ocorre.
- `append` / `append_null` → retornam `-1`; mesmas garantias.

Em qualquer caso: pai intacto, view intacta, sistema consistente.

---

<a id="section-o-que-dispara-o-detach"></a>

## O que dispara o detach

| operação Lua | C |
|---|---|
| `v:set(i, val)` | `smaug_f64_set` / `smaug_i64_set` / `smaug_dt_set` / `smaug_bool_set` |
| `v:set_null(i)` | `smaug_f64_set_null` / `smaug_i64_set_null` / `smaug_dt_set_null` / `smaug_bool_set_null` |
| `v:append(val)` | `smaug_f64_append` / `smaug_i64_append` / `smaug_dt_append` / `smaug_bool_append` |
| `v:append(nil)` | `smaug_f64_append_null` / `smaug_i64_append_null` / `smaug_dt_append_null` / `smaug_bool_append_null` |

<a id="section-o-que-nao-dispara-o-detach"></a>

## O que NÃO dispara o detach

Leituras e operações que produzem novo objeto não disparam detach da origem:
`get`, `is_null`, `len`, `count_nonnull`, `clone`, `filter`, `take`, `sort`,
`argsort`, comparações, aritméticas.

---

<a id="section-tipos-suportados"></a>

## Tipos suportados

| dtype | view | COW |
|---|---|---|
| `float64` | ✅ | ✅ |
| `int64` | ✅ | ✅ |
| `datetime` | ✅ | ✅ |
| `string` | ✅ | ✅ |
| `bool` | ✅ | ✅ |

`datetime` tem view + COW completos: é um buffer de `int64_t` (epoch_ms) de
tamanho fixo, então a janela é zero-copy e o detach copia uma fatia contígua —
mesma mecânica de `float64`/`int64`.
`bool` também tem view + COW completos: é um buffer de `uint8_t` de valores mais
a máscara de nulos paralela, ambos de tamanho fixo — mesma mecânica zero-copy +
detach contíguo de `float64`. (BoolSeries é mutável: tem `set`/`set_null`.)
`string` tem view + COW (item 9.2). Diferente dos numéricos (buffer fixo, view =
soma de ponteiro O(1)), a string é offset-based, então usa um **modelo de posse
mista** (campo `offsets_owned` na struct): a view compartilha `buffer` e
`null_mask` com o pai (zero-copy) mas possui um `offsets` próprio de (len+1)
marcadores absolutos, copiados da janela — O(len), não O(1), mas sem copiar os
bytes. Criar a view aloca a struct e o array de offsets. A primeira mutação dispara o
detach, que materializa buffer + offsets (rebaseados para 0) + null_mask
privados da janela; o pai fica intacto. O único dtype sem view é `categorical`
(Lua puro: codes + dicionário, sem buffer compartilhável) — `:view()` nele lança
erro orientado.

---

<a id="section-resumo-do-contrato"></a>

## Resumo do contrato

1. Criar uma view de tipo fixo é O(1); string é O(len), com cópia de offsets.
2. Compartilhamento depende da validade dos buffers e metadados da janela;
   lifetime e invalidação por mutação do pai precisam de contrato explícito.
3. A primeira escrita dispara COW detach automaticamente.
4. O detach copia apenas a janela, não o pai inteiro.
5. Após o detach, a view é independente — o pai pode ser liberado sem afetar a view.
6. Falha de OOM no detach é segura — operação retorna erro, sistema intacto.
7. Todas as mutações respeitam este contrato uniformemente — sem exceções.

---

[Continuar no guia do usuário](USER_GUIDE.md) · [Consultar a API](API_INDEX.md) · [Início da documentação](README.md)
