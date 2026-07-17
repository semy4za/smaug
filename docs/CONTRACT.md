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

### Contrato 9 — não-finito é valor; ausência é `null_mask`

`NaN` e `±inf` são **valores** IEEE 754. Ausência é o `null_mask`, e só ele. O
Smaug mantém essa distinção que o pandas não tem (lá `NaN` *é* o missing) — e
que o R tem (`NA` vs `NaN`, literais distintos no CSV).

Regra para todo I/O, presente e futuro:

> **Cada formato preserva `NaN`/`±inf` se comportar. Se não comportar, converte
> para ausência e AVISA — nunca em silêncio.**

Estado por formato:

| formato | `NaN` / `±inf` | por quê |
|---|---|---|
| **CSV** | preserva (`nan`/`inf`/`-inf`) | sem norma; escrevemos e lemos. `smaug_fmt_f64` normaliza a grafia (independe de libc) |
| **JSON** | → `null` **+ warn** | RFC 8259 não tem `Infinity`/`NaN` na gramática de `number` |
| **Parquet** *(futuro)* | preserva | IEEE 754 nativo + null separado |
| **`.smg`** *(futuro)* | preserva | binário nosso |

Vocabulário do CSV, deliberado:

- **saída:** ausência → campo vazio; `NaN` → `nan`; `±inf` → `inf`/`-inf`.
- **entrada (`BUILTIN_NA`):** `""`, `NA`, `null`, `N/A`, `NULL`. **`nan`/`NaN`
  não estão aqui** — são valores, via `strtod` (que aceita todas as grafias,
  case-insensitive: `nan`/`NaN`/`NAN`/`inf`/`Infinity`/`INF`).
- **opt-in:** quem lê CSV de terceiros onde `nan` significa ausência passa
  `na_values = {"nan"}`.

Isto garante round-trip fiel no CSV (`NaN` → `nan` → `NaN`) e elimina dois
defeitos históricos: o writer escrevia `nan` como valor enquanto o reader o lia
como ausência (contratos contraditórios entre `smaug_convert.c` e
`smaug_csv.c`), e o destino do dado dependia da **caixa** (`nan`/`NaN` viravam
ausência; `NAN` escapava para o `strtod` e virava valor).

Para avisar sem colapsar o Anel 0, o Anel 3 consulta
`smaug_f64_count_nonfinite` antes de serializar — o C não tem canal de aviso, e
o `warn` (`core/warn.lua`) é do Lua.

### Contrato 10 — guard de fronteira pública se testa; `COV-EXCL-BR` é para o inalcançável

Decorre do princípio acima. Se o engine **não confia no caller**, todo guard de
fronteira pública é **alcançável por definição** — qualquer programa C, binding
ou porte pode passar `NULL`. Logo:

> **Fronteira pública + guard alcançável → TESTA** (custo: 1 linha).
> **`COV-EXCL-BR` → só para o genuinamente inalcançável**, com justificativa
> verificada: OOM sem injeção, overflow com `~SIZE_MAX`, invariante interno
> provado, ramo morto por construção.

**Justificativa não se copia entre dtypes.** Cada uma vale para o código que está
embaixo dela — e o código diverge. Exemplo real (auditado 2026-07-14):

```c
/* f64_coalesce_scalar — o guard é REDUNDANTE */      /* str_coalesce_scalar — o guard é ESSENCIAL */
if (!self) return NULL;                               if (!self) return NULL;
r = smaug_f64_clone(self);   /* clone(NULL)→NULL */   for (i = 0; i < self->size; i++)
if (!r) return NULL;         /* ESTE pega */               /* toca self direto → SIGSEGV */
```

Mesma função, mesmo nome, mesma justificativa herdada — naturezas opostas. Só a
verificação caso-a-caso distingue.

**Por que isto importa mais que a métrica:** um guard excluído e sem teste é um
guard que ninguém protege. Medido: ao remover um guard essencial, a suíte inteira
passa, o Valgrind acusa 0 erros e o branch-alvo não se move — enquanto a API
pública passa a segfaultar. Testar e excluir produzem **o mesmo percentual**; só
o teste produz proteção.

### Contrato 11 — o Anel 0 é thread-safe (reentrante)

**O Smaug é thread-safe.** Toda função do backend C recebe o que precisa por
parâmetro; não há estado compartilhado entre chamadas. Duas threads operando em
séries **diferentes** nunca colidem — e o Smaug é uma biblioteca: quem a usa
decide sobre threads, não nós.

> **Nenhum estado global mutável no Anel 0.** `static const` (tabelas de lookup,
> literais) é permitido — é imutável. Auditado a cada build pelo **eixo 14** de
> paridade.

O que este contrato **não** promete: mutação concorrente da **mesma** série. Duas
threads chamando `set` no mesmo objeto competem pelo mesmo buffer — sincronizar o
acesso a um objeto compartilhado é responsabilidade do caller, como em qualquer
biblioteca. A promessa é sobre o *engine*, não sobre os *dados do usuário*.

**Precedente (2026-07-14):** `smaug_ops_str.c` mantinha `g_sort_series` e
`g_sort_ascending` como contexto do comparador do `qsort` — os únicos globais
mutáveis do Anel 0. O comentário dizia *"single-thread: o projeto não usa
threads"*, o que é a mesma classe de erro do CONTRATO 10 (*"o frontend valida
antes"*): **confiar no caller**. Medido: duas threads ordenando séries
**diferentes** segfaultavam em 6/6 execuções — a primeira a terminar zerava o
global enquanto a outra ainda estava dentro do `qsort`, e o comparador
desreferenciava `NULL`. Todo o resto do Anel 0 já era reentrante, o que tornava
o caso pior que ser declaradamente single-thread: uma armadilha sem aviso.

Substituído por quicksort com contexto por parâmetro. Alternativas descartadas,
com medição: `qsort_r`/`qsort_s` têm assinaturas divergentes entre glibc, BSD e
UCRT (traria `#ifdef` e comportamento por plataforma); `struct {ptr,len,idx}` +
`qsort` é 1.45x mais lenta e usa 4x mais memória. O sort próprio empata em
performance (1.04x mais rápido no aleatório; 0.66–0.95x nos padrões
patológicos), é in-place, e garante o **mesmo algoritmo em toda plataforma** —
o `qsort` da libc não especifica o seu.

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
