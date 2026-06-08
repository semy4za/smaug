# Contrato Defensivo do Backend C — `[Done]`

> Fase de maturidade do núcleo (régua v1.0). Objetivo: aumentar a **confiança**
> no que já existe, não adicionar features. A pergunta-guia não é "quantas
> features?", e sim "quão confiável é o núcleo?".

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

Este princípio está registrado em `smaug_core.h` e substituiu a nota anterior
("o caller garante a validade"), que afirmava exatamente o oposto.

### Por que isto é coerente com o Shape 1 (get com status anulável)

"Não confiar no caller" governa **validação e segurança** (obrigatórias,
incondicionais) — **não** obriga o caller a *ler* o status. O engine sempre
valida e sempre deixa o sistema em estado seguro (erro → sentinela definida, sem
UB); o `status` anulável apenas decide se ele *também* informa a verdade a quem a
pede. A segurança nunca depende de o caller checar nada. São eixos distintos.

## Códigos de status

Definidos em `include/smaug_types.h` (incluído por todos os headers):

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

## Contrato por categoria

### Mutação pontual (`set` / `set_null`) — retorna `smaug_status_t`

Em erro, **nenhuma escrita** ocorre. Em views, dispara COW detach antes de
escrever (ver seção COW abaixo).

| retorno | condição |
|---|---|
| `SMG_OK` | escrita aplicada |
| `SMG_ERR_OOB` | `idx >= size` — checado antes do detach |
| `SMG_ERR_ARGUMENT` | `s == NULL` |
| `SMG_ERR_NOMEM` | detach COW falhou por OOM — série intacta |

Funções (5): `f64_set`, `f64_set_null`, `i64_set`, `i64_set_null`, `str_set_null`.

> `str_set` já retorna `int` (precedente). `str_set_null` propagava internamente
> o retorno do `str_set` — agora retorna `smaug_status_t` de forma consistente.

### Append dinâmico (`append` / `append_null`) — retorna `int` (0 / -1)

Convenção histórica mantida (precedente). Em views, dispara COW detach antes do
grow. Falha (detach-OOM ou grow-OOM) → `-1`; série permanece consistente.

Funções (4 por tipo numérico): `f64_append`, `f64_append_null`, `i64_append`,
`i64_append_null`.

### Leitura (`get`) — Shape 1: valor + status anulável

Assinatura: `T smaug_<t>_get(const S *s, size_t idx, smaug_status_t *status)`.
Retorna o valor; escreve `*status` se `status != NULL`. Em erro/null devolve
sentinela **definida** (`NAN` p/ f64, `0` p/ i64) — segura mesmo para caller que
ignore o status.

| caso | retorno | `*status` |
|---|---|---|
| sucesso | valor real | `SMG_OK` |
| elemento NULL | sentinela | `SMG_NULL_VALUE` |
| `idx >= size` | sentinela | `SMG_ERR_OOB` |
| `s == NULL` | sentinela | `SMG_ERR_ARGUMENT` |

Funções (2): `f64_get`, `i64_get`. Elimina a colisão em que índice inválido e
valor legítimo (NaN no f64, qualquer inteiro no i64) eram indistinguíveis.

> `str_get` já distingue erro de valor via `NULL` + `out_len` — sem colisão, sem
> necessidade de status.

### Já conformes — assinatura mantida

`str_set` → `int`; operações `bool` e `view` → ponteiro com `NULL` como sinal
de erro.

### Validam e degradam com segurança — assinatura inalterada

`is_null` (idx inválido → `true`, resposta conservadora) e `view` (faixa
inválida → `NULL`).

## Copy-on-Write em views

O contrato COW é parte central do contrato defensivo. Toda operação que modifica
uma view a materializa automaticamente antes de escrever, preservando o objeto
original. Ver `docs/COW.md` para a especificação completa.

Resumo para este documento:

- `set` / `set_null`: retornam `SMG_ERR_NOMEM` se o detach falhar.
- `append` / `append_null`: retornam `-1` se o detach ou o grow falharem.
- Em qualquer falha, a view continua apontando para o pai (intacta) e o pai
  permanece inalterado — falha segura em todos os caminhos.
