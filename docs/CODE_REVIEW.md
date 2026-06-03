# Code Review — Smaug (baseline pré-Fase 1.6)

Revisão completa do código antes de iniciar o endurecimento. Data da baseline:
ver `MANIFEST.txt`. Escopo: todo o backend C e o frontend Lua.

## Veredito

O código está **correto e consistente** — compila sem warnings (`-Wall
-Wextra`), os 3 testes C passam Valgrind-clean, e os 99 checks Lua passam. A
arquitetura (despacho por dtype, backend em camadas, null por bitmask) está
sólida e pronta para receber `string` sem reescrita. Os achados abaixo são de
robustez/consistência para a Fase 1.6, **não** bugs que quebram o uso atual.

## Achados (para tratar na Fase 1.6)

### A1 — `sum` de série vazia retorna 0.0, mas `mean`/`min`/`max` retornam NAN
`smaug_f64_sum`/`smaug_i64_sum` de uma série vazia retornam 0/0.0 (soma neutra),
enquanto `mean`/`min`/`max` retornam NAN/`INT64_MIN`. É uma assimetria de
"empty reduction". Pandas retorna 0 para `sum()` de vazio e NaN para `mean()`,
então o comportamento atual até **coincide** com pandas — mas não está testado
nem documentado explicitamente. **Ação:** decidir e fixar em teste + doc (não
necessariamente mudar o código).

### A2 — Possível overflow de `size_t` em `view(start, len)`
`start + len > s->size` pode dar wrap-around se `start`+`len` estourar `size_t`.
Hoje os índices vêm validados do Lua (1-based, checados), então não é
explorável na prática. **Ação:** endurecer a checagem em C
(`start > s->size || len > s->size - start`) e cobrir com teste de borda.

### A3 — Valores especiais do f64 não testados
`+Inf`, `-Inf`, `NaN` fornecido pelo usuário (distinto de nulo) e `-0.0` não têm
comportamento testado em `sum`/`min`/`max`/`sort`/comparações. O código os trata
como valores comuns (ex.: um `NaN` do usuário num `gt` dá 0 — falso). **Ação:**
definir o contrato e cobrir com testes (Fase 1.6, Frente 1).

### A4 — Overflow aritmético do i64 é silencioso
`add`/`mul` de i64 perto de `INT64_MAX` dá overflow (UB para sinalizados em C,
na prática wrap). Pandas/numpy também fazem wrap em int64, então é aceitável,
mas precisa ser **testado e documentado** como comportamento conhecido. Há ainda
a colisão: uma soma que legitimamente dê `INT64_MIN` é indistinguível do
sentinela de erro (já documentado em API_Reference). **Ação:** teste + nota.

### A5 — Caminho de falha de `realloc` (grow) — RESOLVIDO, com bug corrigido
O `test_allocfail.c` (Fase 1.6) passou a forçar `malloc`/`realloc` a falhar em
cada ponto (via `-Wl,--wrap`), varrendo todas as operações f64/i64. Isso
**expôs um bug real** no caminho de reversão do `grow`: quando `capacity == 0`,
o `realloc(s->data, 0)` de reversão liberava o buffer e devolvia NULL, deixando
`s->data` pendente → **double-free** no `free` seguinte. **Corrigido:** a
reversão só roda se `capacity > 0` (quando 0, o buffer maior permanece, que é
seguro). Bug encontrado pelo teste e validado por mutation testing (reintroduzir
o bug faz o teste abortar). f64 e i64 corrigidos.

### A6 — `take` não valida `idx == NULL` por elemento, só o ponteiro
`smaug_*_take` checa `!idx` (o array) e cada `idx[i] >= size`, o que está
correto. Sem ação — registrado só para confirmar que foi revisado.

### A7 — `set` em i64 truncava não-inteiro silenciosamente — RESOLVIDO
`Series:set(i, 1.5)` numa série i64 gravava `1` silenciosamente (o FFI trunca
`int64_t` antes de chegar ao C); `set(i, NaN)` gravava lixo. Violava "sem coerção
implícita". **Corrigido:** `set` e `append` agora usam um guard comum
(`check_value`) que **recusa** não-inteiro/NaN/Inf em i64 com erro claro — a
validação fica no Lua porque a truncagem acontece na conversão FFI (o C nunca vê
o valor original). A conversão **explícita** continua possível via
`astype("int64")`, que trunca em direção a zero (semântica C) e mapeia NaN/Inf →
null (sem representação em inteiro). Testado em `test_i64.lua` (set/append
recusam; astype trunca/trata especiais) e validado por mutation testing.

## Pontos confirmados como corretos (revisados, sem ação)

- Lifecycle: create/free/clone/view com `external_alloc` impedindo double-free
  dos dados da pai; `free(NULL)` seguro; struct sempre heap.
- Propagação de NA uniforme nas aritméticas (série×série propaga; escalar não).
- Divisão por zero: f64 segue IEEE 754; i64 vira NULL (série e escalar) — evita
  UB de divisão inteira. Documentado.
- Sentinela `INT64_MIN` nas reduções i64, com `found` distinguindo vazio.
- Comparações alocam (valores, máscara) com contrato "caller libera"; portado
  para `smaug_free` (Windows).
- `argsort`/`sort` recusam séries com NULL (retornam NULL) — comportamento
  documentado.
- Frontend: `ffi.gc` libera structs e arrays brutos; view segura via `_parent`;
  read-only forçado; conversões 1-based↔0-based e `nil`↔NA/sentinela.

## Arquitetura — nota sobre o header (RESOLVIDO)

`smaug_math.h` continha muito além de "math" (lifecycle, null, comparações,
bool). **Resolvido:** o header foi separado por responsabilidade (inspirado no
NumPy) em `smaug_types.h` (tipos), `smaug_core.h` (lifecycle), `smaug_numeric.h`
(operações f64/i64), `smaug_bool.h` (Kleene) e `smaug.h` (umbrella). O
`smaug_math.h` foi removido. Isso prepara o terreno para `smaug_string.h` entrar
como peça encaixável sem tocar nos demais. Ver "Mapa de headers" na
`API_Reference.md`. Refactor validado: build limpo, 3 testes C + 99 checks Lua,
Valgrind-clean (comportamento idêntico ao anterior).
