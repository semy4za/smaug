# Views e Copy-on-Write — Especificação Semântica

> Este documento descreve o contrato definitivo de views e Copy-on-Write no
> Smaug. É a referência canônica para dúvidas sobre comportamento de views,
> ownership e lifetime.

## O que é uma view

Uma view é uma janela sobre uma faixa contínua de elementos de uma série
existente. Ela não copia dados — inicialmente compartilha o armazenamento do
objeto de origem.

```lua
local s = Series.from_table({10, 20, 30, 40, 50}, "float64")
local v = s:view(2, 3)   -- janela sobre [20, 30, 40]
```

Uma view é criada em O(1) (aloca apenas o struct da view, sem copiar dados).
Leituras em `v` refletem o estado atual de `s` enquanto nenhuma escrita em `v`
tiver ocorrido.

## Semântica Copy-on-Write

A primeira operação de escrita sobre uma view dispara um **detach**: a view
recebe um buffer privado com uma cópia dos seus elementos, e a partir daí torna-
se completamente independente do objeto de origem.

```
view criada   →  compartilha armazenamento do pai
                 (leituras em v refletem mutações em s)
                 ↓
primeira escrita em v  →  DETACH: cópia privada dos elementos da janela
                          (v independente; pai preservado, inalterado)
                          ↓
escritas subsequentes  →  vão direto ao buffer privado (sem nova cópia)
```

### O que dispara o detach

Qualquer operação que modifica a view materializa o detach antes de escrever:

| operação | C | Lua |
|---|---|---|
| `set` | `smaug_f64_set` / `smaug_i64_set` | `v:set(i, val)` |
| `set_null` | `smaug_f64_set_null` / `smaug_i64_set_null` | `v:set(i, nil)` |
| `append` | `smaug_f64_append` / `smaug_i64_append` | `v:append(val)` |
| `append_null` | `smaug_f64_append_null` / `smaug_i64_append_null` | `v:append(nil)` |

### O que NÃO dispara o detach

Operações de leitura e operações que produzem um novo objeto nunca tocam o
armazenamento compartilhado:

`get`, `is_null`, `len`, `count_nonnull`, `clone`, `filter`, `take`,
`sort`, `argsort`, comparações, aritméticas.

## Granularidade do detach

O buffer privado tem exatamente o tamanho da janela da view (`size` elementos),
não o tamanho do pai. Apenas a fatia visível é copiada.

Após o detach:

- `v->meta.is_view = false`
- `v->meta.external_alloc = false`
- `v->capacity = size` (janela exata; grow acontece no próximo append se necessário)

O pai nunca é tocado.

## Falha segura no detach (OOM)

O detach aloca memória. Se a alocação falhar:

- `set` / `set_null` → retornam `SMG_ERR_NOMEM`; a view continua apontando para
  o pai; nenhuma escrita ocorre.
- `append` / `append_null` → retornam `-1`; mesmas garantias.
- Em qualquer caso: pai intacto, view intacta (ainda é view), sistema consistente.

Views de tamanho zero são tratadas sem malloc: o detach apenas vira as flags
(`is_view = false`, `data = NULL`, `capacity = 0`) e retorna sucesso.

## Ownership e lifetime

### Referência ao pai (`_parent` no Lua)

O wrapper Lua mantém uma referência ao objeto pai (`_parent`) para impedir que o
GC colete o pai enquanto a view estiver viva. Sem isso, o pai poderia ser
liberado e a view ficaria com ponteiros inválidos (use-after-free).

Após o detach, a view tem buffer privado e não depende mais do armazenamento do
pai. A referência `_parent` é mantida por segurança (harmless), mas não é mais
semanticamente necessária. Liberá-la explicitamente é uma otimização de memória,
não um requisito de corretude.

### Papel do `_parent`

O `_parent` existe exclusivamente para controle de lifetime (GC). Ele não
representa herança lógica, nem indica que a view "pertence" ao pai semanticamente.
Após o detach, a view é um objeto completamente independente.

### Views de views

O detach afeta apenas a view imediata, não a cadeia:

```lua
local v1 = s:view(2, 4)   -- janela sobre s
local v2 = v1:view(1, 2)  -- janela sobre v1 (portanto sobre s)

v2:set(1, 99.0)            -- detach de v2 apenas; v1 e s intactos
```

`v1` continua sendo view de `s`. Apenas `v2` torna-se independente.

## Tipos com suporte a views

| tipo | view | COW |
|---|---|---|
| `float64` | ✅ | ✅ |
| `int64` | ✅ | ✅ |
| `string` | ❌ (futuro) | — |
| `bool` | ❌ (imutável por construção) | — |

`BoolSeries` são resultados de comparações — imutáveis por natureza, sem surface
de mutação. `string` não tem função de view ainda; quando ganhar, o detach será
mais complexo (buffer de bytes + offsets rebaseados).

## Resumo do contrato

1. Criar uma view é O(1) e não copia dados.
2. Ler de uma view antes de qualquer escrita reflete o estado atual do pai.
3. A primeira escrita em uma view dispara COW detach automaticamente.
4. Após o detach, a view é independente — o pai pode ser liberado sem afetar a
   view.
5. O detach copia apenas a janela (não o pai inteiro).
6. Se o detach falhar por OOM, a operação retorna erro e o sistema permanece
   intacto (falha segura).
7. Todas as mutações (`set`, `set_null`, `append`, `append_null`) respeitam este
   contrato uniformemente — não há exceções por tipo de operação.
