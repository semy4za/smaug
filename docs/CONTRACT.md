# Contrato Defensivo do Backend C — Especificação `[Planned]`

> Fase de maturidade do núcleo (régua v1.0, prioridade máxima). Objetivo desta
> fase **não** é adicionar features — é aumentar a **confiança** no que já existe.
> A pergunta-guia não é "quantas features?", e sim "quão confiável é o núcleo?".

## Princípio fundador: o engine não confia no caller

Toda fronteira pública em C **valida e comunica**; nunca assume que o caller
validou. Garantias incondicionais (independem do que o caller passe):

1. **Validação na entrada.** Ponteiro, argumentos e índice são checados antes de
   qualquer acesso à memória. Entrada inválida nunca causa comportamento
   indefinido, corrupção ou crash evitável.
2. **Resultado observável.** Toda operação comunica sucesso/falha por código de
   status — o caller pode sempre saber se a operação pegou ou foi rejeitada.
3. **Falha segura.** Em erro não há escrita parcial; leitura devolve sentinela
   documentada e o estado permanece consistente.

Este princípio **substitui** a nota anterior em `smaug_core.h` ("modelo 'o caller
garante a validade'" / "um caller em C deve garantir a validade dos índices"),
que afirma exatamente o oposto e passa a ser a violação a corrigir.

### Por que isto é coerente com o Shape 1 (get com status anulável)

"Não confiar no caller" governa **validação e segurança** (obrigatórias,
incondicionais) — **não** obriga o caller a *ler* o status. O engine sempre
valida e sempre deixa o sistema em estado seguro (erro → sentinela definida, sem
UB); o `status` anulável apenas decide se ele *também* informa a verdade a quem a
pede. A segurança nunca depende de o caller checar nada. São eixos distintos.

## Códigos de status

Definidos em `include/smaug_types.h` (a fundação, incluída por todos os headers):

```c
typedef enum {
    SMG_OK = 0,        /* operação concluída com sucesso          */
    SMG_NULL_VALUE,    /* leitura: elemento é NULL (não é erro)   */
    SMG_ERR_OOB,       /* índice fora dos limites                 */
    SMG_ERR_ARGUMENT   /* ponteiro nulo / argumento inconsistente */
} smaug_status_t;
```

## Contrato por categoria

### Mutação (`set` / `set_null`) — `void` → `int`

Retorna `smaug_status_t`. Em erro, **nenhuma escrita** ocorre.

| retorno | condição |
|---|---|
| `SMG_OK` | escrita aplicada |
| `SMG_ERR_OOB` | `idx >= size` |
| `SMG_ERR_ARGUMENT` | `s == NULL` |

Funções (5): `f64_set`, `f64_set_null`, `i64_set`, `i64_set_null`,
`str_set_null`.

> `str_set` já retorna `int` (precedente). `str_set_null` hoje é `void` **e
> descarta** o `int` do `str_set` que chama internamente — incluí-lo fecha a
> inconsistência interna do próprio tipo string, que é o nosso tipo-modelo do
> contrato forte.

### Leitura (`get`) — Shape 1: valor + status anulável

Assinatura: `T smaug_<t>_get(const S *s, size_t idx, smaug_status_t *status)`.
Retorna o valor; escreve `*status` se `status != NULL`. Em erro/null devolve uma
sentinela **definida** (`NAN` p/ f64, `0` p/ i64) — segura mesmo para um caller
que ignore o status.

| caso | retorno | `*status` |
|---|---|---|
| sucesso | valor real | `SMG_OK` |
| elemento NULL | sentinela | `SMG_NULL_VALUE` |
| `idx >= size` | sentinela | `SMG_ERR_OOB` |
| `s == NULL` | sentinela | `SMG_ERR_ARGUMENT` |

Funções (2): `f64_get`, `i64_get`. Resolve a colisão atual em que índice inválido
e valor legítimo (NaN no f64, qualquer inteiro no i64) eram indistinguíveis.

> `str_get` já distingue erro de valor via `NULL` + `out_len` (não há colisão).
> Pode ganhar um `status` opcional por simetria — **opcional**, não obrigatório.

### Já conformes — mantêm (são o precedente)

`*_append` → `int` (0/-1); `str_set` → `int`; operações `bool` e `view` →
ponteiro com `NULL` como sinal de erro não-colidente.

### Validam e degradam com segurança — assinatura mantida

`is_null` (idx inválido → `true`, resposta conservadora) e `view` (faixa
inválida → `NULL`). Já honram o princípio sem mudar assinatura.

## Questões a fechar antes de codar (precisam do martelo)

1. **`str_set_null` entra no escopo?** Recomendação: **sim** (consistência do
   tipo-modelo). Define 5 mutações em vez de 4.
2. **`set` em uma view.** `append` **rejeita** view (read-only); `set` hoje
   **permite** (escreve no buffer compartilhado com o pai). Inconsistência a
   resolver explicitamente: view gravável (estilo NumPy) ou read-only como
   `append`? Se read-only, qual status — reusar `SMG_ERR_ARGUMENT` ou criar
   `SMG_ERR_READONLY`?

## Ordem de implementação (uma peça por vez, validar cada)

1. `smaug_status_t` em `smaug_types.h`.
2. As 5 mutações `void → int` — FFI + frontend (`series.lua`/`dataset.lua`) +
   call sites + testes, juntos por função/grupo.
3. As 2 leituras `get` (Shape 1) — idem.
4. Reescrever a nota de contrato em `smaug_core.h` (inverter "caller garante" →
   "engine valida e comunica").
5. A cada peça: build sem warnings, testes C + Lua, Valgrind-clean (Linux),
   allocfail; atualizar CHANGELOG + COVERAGE + MANIFEST + API_INDEX. Windows
   valida no fim via `windows-build.ps1`.
