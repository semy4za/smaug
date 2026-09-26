# Contrato Defensivo — Smaug

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

<details>
<summary>Nesta página</summary>

- [Ring 1 — Frontend Lua](#section-ring-1-frontend-lua)
  - [Contrato 1 — promoção segura; nunca narrowing ou adivinhação em silêncio](#section-contrato-1-promocao-segura-nunca-narrowing-ou-adivinhacao-em-silencio)
  - [Contrato 2 — astype converte por elemento, tolerante a falha](#section-contrato-2-astype-converte-por-elemento-tolerante-a-falha)
  - [Contrato 3 — fillna preserva o original e segue a validação de entrada](#section-contrato-3-fillna-preserva-o-original-e-segue-a-validacao-de-entrada)
  - [Contrato 4 — DataSet nunca existe desalinhado](#section-contrato-4-dataset-nunca-existe-desalinhado)
  - [Contrato 5 — BoolSeries é coluna de primeira classe](#section-contrato-5-boolseries-e-coluna-de-primeira-classe)
  - [Contrato 6 — filter descarta NA na máscara](#section-contrato-6-filter-descarta-na-na-mascara)
  - [Contrato 7 — índices são 1-based](#section-contrato-7-indices-sao-1-based)
  - [Contrato 8 — NA em chave relacional é erro](#section-contrato-8-na-em-chave-relacional-e-erro)
  - [Contrato 9 — não-finito é valor; ausência é null_mask](#section-contrato-9-nao-finito-e-valor-ausencia-e-null-mask)
  - [Contrato 10 — guard de fronteira pública se testa; COV-EXCL-BR é para o inalcançável](#section-contrato-10-guard-de-fronteira-publica-se-testa-cov-excl-br-e-para-o-inalcancavel)
  - [Contrato 11 — o Anel 0 é thread-safe (reentrante)](#section-contrato-11-o-anel-0-e-thread-safe-reentrante)
- [Ring 0 — Backend C](#section-ring-0-backend-c)
  - [Princípio: o engine não confia no caller](#section-principio-o-engine-nao-confia-no-caller)
  - [Códigos de status](#section-codigos-de-status)
  - [Perfil datetime — decisões aprovadas em 2026-09-18](#section-perfil-datetime-decisoes-aprovadas-em-2026-09-18)
  - [Detecção de datas e diagnóstico — decisões da retomada](#section-deteccao-de-datas-e-diagnostico-decisoes-da-retomada)
  - [Mutação pontual (set / set_null) — retorna smaug_status_t](#section-mutacao-pontual-set-set-null-retorna-smaug-status-t)
  - [Append dinâmico (append / append_null) — retorna int (0 / -1)](#section-append-dinamico-append-append-null-retorna-int-0-1)
  - [Leitura (get) — Shape 1: valor + status anulável](#section-leitura-get-shape-1-valor-status-anulavel)
  - [Copy-on-Write em views](#section-copy-on-write-em-views)

</details>

Este documento especifica os contratos de comportamento do Ring 1 (frontend Lua)
e do Ring 0 (backend C). Um contrato aqui significa: comportamento garantido,
exigido, e que não muda sem decisão explícita e versionada. O contrato não
certifica seu cumprimento: evidências e gaps estão em
[parecer do rework](TEST_SUITE_REWRITE_REVIEW.md). Revisão documental: 2026-09-18.

---

<a id="section-ring-1-frontend-lua"></a>

## Ring 1 — Frontend Lua

<a id="section-contrato-1-promocao-segura-nunca-narrowing-ou-adivinhacao-em-silencio"></a>

### Contrato 1 — promoção segura; nunca narrowing ou adivinhação em silêncio

```lua
local smaug = require("smaug")

-- dtype INFERIDO quando omitido (do conteúdo)
smaug.Series.from_table({1, 2, 3})     -- int64
smaug.Series.from_table({1, 2, 3.5})   -- float64  (o fracionário promove)

local payload = {
    {"produto", {"caneta", "caderno", "régua"}, "string"},
    {"qtd",     {10, 5, 8},                    "int64"},
}
local ds = smaug.DataSet(payload)

-- dtype FIXADO: só entra o que preserva a informação
ds["qtd"]:set(1, 12)    -- ok    (int64 <- inteiro)
ds["qtd"]:set(1, 1.5)   -- erro  (narrowing: perderia a fração)
ds["qtd"]:set(1, "x")   -- erro  (adivinharia parse)

-- promoção sem perda é automática
local preco = smaug.Series.float64(1)
preco:set(1, 5)         -- ok -> 5.0  (widening seguro: int -> float64)
```

```
smaug: valor para int64 deve ser inteiro (sem coerção); recebido 1.5
smaug: valor para int64 deve ser inteiro (sem coerção); recebido x
```

O dtype é **inferido** quando omitido (inteiro → `int64`, fracionário → `float64`,
`string`, `boolean` → `bool`; lista vazia ou só-nula → `string`) e **explícito**
quando informado. Fixado o dtype, o frontend aceita apenas o que **preserva a
informação**:

- **Promoção sem perda é automática quando representável no destino.** Um
  `number` Lua inteiro, como `5`, pode preencher uma série float64. Isso não
  significa que todo `int64_t` seja representável exatamente em float64.
- **Narrowing e adivinhação são recusados.** Truncar fração (`float → int64`),
  adivinhar parse (`number ↔ string`) ou semântica
  (`number → bool`) falha com erro — nunca em silêncio.

Narrowing **intencional** é o `astype` (Contrato 2), com as exceções ali descritas.
Preservação exata de `int64` além de 2^53 exige a
**forma exata** — `cdata int64_t` na entrada, `get_raw` na leitura (o `number`
Lua já perdeu o dígito antes de chegar; a lib não recupera, só torna visível).

O princípio não é *"sem conversão"* — é **sem perda nem adivinhação em silêncio**.
O que cabe sem perder informação, entra; o que exigiria decidir pelo usuário,
**falha visível**, e o usuário decide com `astype`.

**Entrada vs. operação no limiar 2^53.** Um `number` que armazena dado
(`set`/`append`/`fillna`) e um `number` que parametriza uma operação
(comparação, aritmética escalar) recebem o mesmo valor com políticas diferentes,
por uma razão: no armazenamento o valor *é* o dado do usuário — com `|v| > 2^53` ele
**avisa e aceita** (a perda é irrecuperável na origem, a escolha é dele); numa
operação o valor é *operando* e o resultado seria uma mentira silenciosa — a
partir de `|v| >= 2^53` (inclusive, pois `2^53+1` degrada para `2^53`) ele **recusa**.
No armazenamento, `|v| == 2^53` é aceito sem o aviso de precisão. Acima disso,
o aviso indica possível perda na origem; nem todo inteiro acima do limiar é
inexato. Esta política é da fronteira int-based e não autoriza valores fora da
faixa do destino. `uint64_t` só é aceito até `INT64_MAX`.
Em ambos, a forma exata (`cdata int64_t`) preserva os bits de entrada. Fonte única do
reconhecimento: `core/int_scalar.lua` (ver Roadmap 9.3).

---

<a id="section-contrato-2-astype-converte-por-elemento-tolerante-a-falha"></a>

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

`astype` para `float64`/`int64`/`string` não lança erro por causa de
um elemento individual: nesses pares, elementos inconversíveis tornam-se `null`.
Para datetime, a conversão explícita é estrita a partir de string, int64 e
float64 (implementada em 2026-09-25). Epoch numérico deve ser finito, inteiro
em milissegundos e estar no domínio de -9999 a 9999; não há truncamento.
Texto inválido gera erro com posição, sem resultado parcial ou NA fabricado;
NA já presente na entrada continua sendo ausência. Ver a seção de detecção abaixo.

**Exceção — `astype("bool")` a partir de numérico é estrito:** aceita só `0`/`1`;
qualquer outro valor lança erro que orienta para `:map(fn)`. A regra de truthiness
não é imposta silenciosamente — quem quer defini-la usa `map`.

---

<a id="section-contrato-3-fillna-preserva-o-original-e-segue-a-validacao-de-entrada"></a>

### Contrato 3 — `fillna` preserva o original e segue a validação de entrada

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

ds["vendas"]:fillna(1)     -- válido: number inteiro em float64
ds["vendas"]:fillna("1")   -- erro: não adivinha parse
```

```
true
false
0.0
true
smaug: valor para float64 deve ser número; recebido string
```

`fillna` devolve nova série — o original é imutável. `NaN` é preservado:
`fillna` substitui `null` (ausência), não `NaN` (valor indefinido presente).
São coisas distintas no Smaug.

O preenchimento segue o Contrato 1. Datetime aceita epoch_ms numérico/exato;
string ISO em `fillna` continua pendência do Roadmap 12.16.

---

<a id="section-contrato-4-dataset-nunca-existe-desalinhado"></a>

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

<a id="section-contrato-5-boolseries-e-coluna-de-primeira-classe"></a>

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

Bool é coluna de primeira classe nas operações compatíveis com seu dtype.
Isso não promete aritmética numérica para todo tipo: suporte e rejeições devem
ser explícitos por operação. Gaps conhecidos não se tornam suporte por esta regra.

---

<a id="section-contrato-6-filter-descarta-na-na-mascara"></a>

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

<a id="section-contrato-7-indices-sao-1-based"></a>

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

<a id="section-contrato-8-na-em-chave-relacional-e-erro"></a>

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

<a id="section-contrato-9-nao-finito-e-valor-ausencia-e-null-mask"></a>

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

**NUL em valores e nomes — decisão aprovada em 2026-09-26, implementação
de I/O pendente:** byte NUL é conteúdo válido, distinto de string vazia e NA.
CSV e JSON devem preservá-lo em valores e nomes de colunas, na leitura e escrita,
sem truncamento. JSON usa o escape `\u0000`; NUL literal não escapado permanece
inválido na sintaxe JSON. CSV preserva o byte como extensão do dialeto do Smaug
em relação à RFC 4180. Nomes `a` e `a\0b` são distintos em associação e
desambiguação. A regra de campo vazio/NA abaixo permanece. Ver `IO_REVIEW.md`
para evidências, migração da fronteira C/Lua e limitações atuais.

- **saída:** ausência → campo vazio; `NaN` → `nan`; `±inf` → `inf`/`-inf`.
- **entrada (`BUILTIN_NA`):** `""`, `NA`, `null`, `N/A`, `NULL`. **`nan`/`NaN`
  não estão aqui** — são valores, via `strtod` (que aceita todas as grafias,
  case-insensitive: `nan`/`NaN`/`NAN`/`inf`/`Infinity`/`INF`).
- **opt-in:** quem lê CSV de terceiros onde `nan` significa ausência passa
  `na_values = {"nan"}`.

**Datetime nos formatos de texto (12.3):** `smaug_column_t` (fronteira C de I/O, Anel 3) carrega
f64/i64/bool/str — não tem `dt`. O Anel 3 converte datetime para **ISO 8601** na
escrita (`astype("string")`, o mesmo formato do `smaug_dt_format`). CSV não tem
tipos e JSON não tem tipo *date*: texto ISO é o que ambos comportam, então isto
**preserva o valor** — round-trip testado, `astype("datetime")` devolve o
epoch_ms exato. O que não sobrevive é o **tipo**, e isso é do formato, não nosso:
por isso não avisa (seria ruído em toda escrita de data). Se o reader deve
inferir ISO de volta é outra questão — ver 12.25.

Isto garante round-trip fiel no CSV (`NaN` → `nan` → `NaN`) e elimina dois
defeitos históricos: o writer escrevia `nan` como valor enquanto o reader o lia
como ausência (contratos contraditórios entre `smaug_convert.c` e
`smaug_csv.c`), e o destino do dado dependia da **caixa** (`nan`/`NaN` viravam
ausência; `NAN` escapava para o `strtod` e virava valor).

Para avisar sem colapsar o Anel 0, o Anel 3 consulta
`smaug_f64_count_nonfinite` antes de serializar — o C não tem canal de aviso, e
o `warn` (`core/warn.lua`) é do Lua.

<a id="section-contrato-10-guard-de-fronteira-publica-se-testa-cov-excl-br-e-para-o-inalcancavel"></a>

### Contrato 10 — guard de fronteira pública se testa; `COV-EXCL-BR` é para o inalcançável

Decorre do princípio acima. Se o engine **não confia no caller**, todo guard de
fronteira pública é **alcançável por definição** — qualquer programa C, binding
ou porte pode passar `NULL`. Logo:

> **Fronteira pública + guard alcançável → TESTA** (custo: 1 linha).
> **`COV-EXCL-BR` → só para o genuinamente inalcançável**, com justificativa
> verificada por ramo: invariante interno provado ou ramo morto por construção.

OOM e falhas de I/O são alcançáveis por falha ambiental. Ausência de injeção é
gap de teste, não impossibilidade. Limites próximos de `SIZE_MAX` exigem prova
de domínio e testes dos cálculos sem buffers fictícios ou alocações gigantes.
Cada exclusão exige condição/ramo, evidência e decisão; não exclui a linha
inteira. A cobertura bruta permanece visível. O inventário
[inventário de exclusões](TEST_SUITE_EXCLUSIONS_REVIEW.md) é triagem, não aprovação.

**Justificativa não se copia entre dtypes.** Cada uma vale para o código que está
embaixo dela — e o código diverge.

**E auditoria não se aceita sem verificar o harness.** A primeira auditoria destes
guards (2026-07-14) classificou os quatro `select` como redundantes. Era falso: o
script removia apenas a **primeira** linha do guard, deixando o `return NULL;`
órfão — a função virava `return NULL` incondicional e nunca crashava. Artefato do
método, não do código. Refeita removendo o guard **inteiro**: os quatro
segfaultam. Um falso negativo em auditoria de segurança é pior que não auditar:
produz confiança sem base. Exemplo real (auditado 2026-07-14):

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

---

> **Nota — calibragem do rigor (decidida em 2026-07-28, aplicável a partir da
> v1.0).**
>
> O padrão de verificação do projeto (cobertura de ramos, Valgrind, varredura de falha
> de alocação, teste de mutação) é **uniforme** hoje. A partir da v1.0 ele passa a
> ser **proporcional ao que o código protege** — e o critério é a *natureza* do
> código, não o número da versão nem o calendário.
>
> **O máximo permanece onde o erro é silencioso e caro:** buffers, ciclo de vida,
> propriedade de memória, aritmética exata, fronteiras de tipo — o Anel 0 e tudo
> que decide correção de dado. É onde uma falha não aparece na hora e é cara de
> descobrir tarde. Este contrato inteiro trata desse território, e ele **não**
> afrouxa.
>
> **Camadas externas calibram por risco.** Ergonomia, açúcar sintático, exibição,
> conveniência de API: falham alto e barato, e o custo do rigor máximo ali não se
> paga. Afrouxar é decisão consciente e registrada, não omissão.
>
> **A calibragem depende de evidência do núcleo.** A revisão de 2026-09-18
> encontrou lacunas que impedem declará-lo selado. Reduzir rigor exige decisão
> registrada por risco. Cobertura de ramos não é MC/DC; esta exige
> instrumentação e evidência próprias.
>
> **Duas regras de operação, para o portão continuar passável:**
>
> 1. **Medir continua contínuo.** O `build.sh --all` já roda cobertura em todo
>    selo; o custo nunca foi medir, foi consertar. Deixar de medir cega, e cego
>    não se calibra.
> 2. **Consertar pode adiar; o desvio, não.** Se a cobertura cai e a decisão é não
>    mexer agora, registra-se **onde e por quê**, no momento em que acontece. Sem
>    isso, o portão de fim de etapa deixa de ser "resolver uma lista com contexto"
>    e vira arqueologia — e portão caro é portão que se pula.
>
> A razão de (2) não é burocracia. Ramos descobertos costumam ser não-óbvios:
> guardas que o frontend nunca alcança porque sempre passa os parâmetros
> opcionais, e curto-circuito de `&&` onde nenhum teste falha pelo lado esquerdo.
> Achá-los é barato com a implementação fresca e caro semanas depois.

<a id="section-contrato-11-o-anel-0-e-thread-safe-reentrante"></a>

### Contrato 11 — o Anel 0 é thread-safe (reentrante)

**O Smaug é thread-safe.** Toda função do backend C recebe o que precisa por
parâmetro; não há estado compartilhado entre chamadas. Duas threads operando em
séries **diferentes** nunca colidem — e o Smaug é uma biblioteca: quem a usa
decide sobre threads, não nós.

> **Nenhum estado global mutável no Anel 0.** `static const` (tabelas de lookup,
> literais) é permitido — é imutável. O **eixo 14** de paridade auxilia a
> inspeção, mas suas lacunas atuais (R06) impedem usá-lo como prova completa.

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

<a id="section-ring-0-backend-c"></a>

## Ring 0 — Backend C

<a id="section-principio-o-engine-nao-confia-no-caller"></a>

### Princípio: o engine não confia no caller

Toda fronteira pública em C **valida e comunica**; nunca assume que o caller
validou. Garantias incondicionais:

1. **Validação na entrada.** Ponteiro, argumentos e índice são checados antes de
   qualquer acesso à memória. Isso cobre NULL e argumentos inválidos dentro do
   domínio documentado; não promete validar ponteiros arbitrários, memória já
   liberada ou buffers cujo tamanho real contradiz o informado pelo caller.
2. **Resultado observável.** Cada API documenta seu canal: status, retorno
   `0/-1` ou ponteiro/NULL. APIs legadas com sentinelas ambíguas exigem revisão;
   não herdam uma garantia de status que sua assinatura não oferece.
3. **Falha segura.** Em erro não há escrita parcial; leitura devolve sentinela
   documentada e o estado permanece consistente.

<a id="section-codigos-de-status"></a>

### Códigos de status

```c
typedef enum {
    SMG_OK = 0,        /* operação concluída com sucesso          */
    SMG_NULL_VALUE,    /* leitura: elemento é NULL (não é erro)   */
    SMG_ERR_OOB,       /* índice fora dos limites                 */
    SMG_ERR_ARGUMENT,  /* ponteiro nulo / argumento inconsistente */
    SMG_ERR_NOMEM,     /* falha de alocação (COW detach)          */
    SMG_ERR_OVERFLOW   /* resultado não cabe no intervalo do tipo */
} smaug_status_t;
```

Espelhado no cdef do FFI (`lua/smaug/ffi_loader.lua`).

**Direção acordada para overflow int64:** erro explícito via C/status, FFI e
erro Lua orientado. Wrap silencioso não é resultado esperado. A existência do
enum não significa que todas as APIs já o propaguem: a migração precisa de
mapa por operação, incluindo APIs legadas e intermediários. Divisão por zero
tem contrato próprio e não muda implicitamente com esta decisão.

**Decisões ainda abertas:** detalhes de migração das assinaturas com sentinela
ambígua e garantias de lifetime/invalidação de views em mutações do pai.
As escolhas de datetime abaixo foram aprovadas; sua implementação e validação
permanecem pendentes.
R02 e R05 registram contraexemplos; comportamento defeituoso não vira esperado.

<a id="section-perfil-datetime-decisoes-aprovadas-em-2026-09-18"></a>

### Perfil datetime — decisões aprovadas em 2026-09-18

Este perfil fixa as escolhas de domínio, representação e erro aprovadas
pelo mantenedor. É contrato a implementar/verificar, não declaração de que o
parser, formatter e todas as operações atuais já o cumprem.

Seguimento de 2026-09-25: parser textual e `astype` para datetime implementam
o domínio UTC, ano negativo e precisão exata descritos abaixo. A conversão
explícita textual ou numérica falha com posição e preserva NA/entrada.
Formatter, componentes e outras entradas ainda têm migração pendente; a implementação
parcial não certifica essas outras entradas e operações.

1. **Anos de `-9999` a `9999`, inclusive, incluindo zero.** Calendário gregoriano
   proléptico com numeração astronômica: ano `0` corresponde a 1 a.C., ano `-1`
   a 2 a.C. Todos os anos da faixa são completos. Limites dos instantes UTC:
   `-009999-01-01T00:00:00.000Z` e `9999-12-31T23:59:59.999Z`, ambos inclusivos.
   A faixa é uma decisão do Smaug, não um limite imposto pela ISO nem suporte
   a todo o intervalo de `int64` epoch_ms. Sua implementação ainda será validada.
   Texto, construção por componentes e entrada por epoch devem respeitar o
   mesmo domínio. A validação do instante considera o offset normalizado para
   UTC; normalização ou operação que saia da faixa deve falhar explicitamente,
   sem wrap nem saturação. Conversão explícita por `astype` deve emitir erro
   orientado para o elemento fora do domínio. Ano negativo válido é dado, não ausência ou erro.
2. **Offset omitido significa UTC.** Uma entrada como
   `2026-09-18T14:30:00` representa o mesmo instante que
   `2026-09-18T14:30:00Z`. Data sem horário representa meia-noite UTC.
   O fuso da máquina não participa dessa interpretação. Fusos nomeados,
   horários locais e suas ambiguidades não são introduzidos por esta decisão.
3. **Precisão excedente só entra se for exata em milissegundos.** O
   armazenamento continua sendo `int64` em milissegundos desde o Unix epoch.
   Fração `.123000` é aceita como 123 ms; `.123456` e `.000001` são rejeitadas
   na entrada estrita, sem truncamento ou arredondamento silencioso.
   Em `astype("datetime")`, perda de precisão deve gerar erro orientado;
   falhas de memória ou de infraestrutura também não viram dados ausentes. Arredondamento/truncamento explícito
   poderá ser proposto separadamente.
4. **Representação do ano:** anos de `0000` a `9999` usam quatro dígitos;
   negativos usam sinal menos e seis dígitos, como `-000001` e `-009999`.
   A nova forma negativa aceita somente ano primeiro e separadores de data
   com hífens. Rejeitar `-000000`, ano abreviado como `-1` e sufixos BC/AC.
   Preservar as conveniências existentes para datas positivas, mantendo saída
   canônica: `YYYY-MM-DDTHH:mm:ss.sssZ` ou `-YYYYYY-MM-DDTHH:mm:ss.sssZ`.
5. **Segundos de `00` a `59`:** rejeitar segundo intercalar `:60`, sem
   normalização para o minuto seguinte. Os helpers Lua `dt_parse` e
   `dt_from_parts` continuam retornando `nil` por entrada inválida;
   conversão explícita por `astype` deve emitir erro por elemento inválido.
6. **Valor separado do status:** `-1` é ano válido e não pode sinalizar erro
   na extração. A API C deve seguir o padrão checked, preservando o parâmetro
   de saída em falha. O padrão foi aprovado para os 11 componentes escalares:
   retorno de status, resultado por ponteiro e nome público sem `_checked`.
   As assinaturas estão na [referência C](API_Reference.md#section-decisao-fechada-e-alcance)
   e ainda não foram implementadas.
   No Lua, manter `.dt:year()`: NA de entrada propaga, anos negativos válidos
   permanecem valores e falhas reais seguem o canal de status/erro Lua.
   Não converter um ano negativo em NA por um teste de sinal.
7. **Extração de componentes em série — comportamento aprovado em 2026-09-21:**
   nas 11 operações, sucesso entrega o resultado completo. Um datetime inválido
   causa erro com indicação da posição, sem entregar resultado parcial. NA de
   entrada permanece NA na mesma posição e a série original permanece intacta.
   Padrão C aprovado: retorno `smaug_status_t`, resultado por
   `smaug_series_i64_t **out` escrito somente em sucesso e posição por
   `size_t *error_index` opcional. Esse parâmetro transporta do C ao Lua
   apenas o índice do primeiro elemento que falhou, na ordem da série.
   O status continua comunicando o erro; a montagem e apresentação da
   mensagem pertencem ao Lua, não ao motor C. NA não conta como falha.
   Quando fornecido, o índice só é escrito em falha de um elemento. Em
   sucesso ou falha sem posição (argumento inválido ou falta de memória),
   permanece intocado e não deve ser consultado pelo consumidor. Não usar
   sentinela para indicar ausência de posição. Nessas 11 funções,
   `SMG_ERR_OVERFLOW` indica exclusivamente o primeiro datetime fora do domínio
   permitido e garante o preenchimento do índice, quando fornecido.
   `SMG_OK`, `SMG_ERR_ARGUMENT` e `SMG_ERR_NOMEM` não permitem consultar o índice.
   A tabela de status está na referência C; essa associação é restrita à família.
   Não introduzir estrutura de diagnóstico
   para essa família. Ver a assinatura na referência C; implementação e
   validação pendentes. A mudança fica restrita ao necessário para corrigir
   a extração e comunicar suas falhas, sem reforma geral das APIs do motor.

**Migração ainda a fechar:** ver [evolução da API C](API_Reference.md#section-datetime-migracao-c)
e [evolução da API Lua](API_INDEX.md#section-datetime-migracao-lua).
Foram inventariadas extrações escalares, extrações de
séries e consumidores C/FFI/Lua; definir assinaturas finais, códigos de status
por falha e destino das funções legadas antes de alterá-las. A direção checked
está aprovada; remoção, compatibilidade e cronograma das assinaturas antigas
não estão decididos. Revisar também os outros componentes de calendário e
todos os consumidores do formatter (inclusive astype e buffers no Lua), para
comportar a saída negativa canônica e propagar falhas de formatação.

**Referências de representação:** ISO 8601-1:2019, com emenda de 2022
([ISO](https://www.iso.org/standard/70907.html)), e RFC 3339 para intercâmbio
de timestamps com ano de quatro dígitos
([RFC Editor](https://www.rfc-editor.org/info/rfc3339/)). O perfil Smaug não
declara conformidade integral com essas normas. As escolhas de representação
e segundos acima definem o perfil próprio da biblioteca.

**Evidência exigida na reconstrução:** casos independentes para ano zero,
anos negativos (incluindo `-1` e `-2`), bissextos e passagem de ano; equivalência
de entrada sem offset e com `Z`; precisão exata versus perda; consistência
entre parser, componentes, epoch, formatação e conversão tolerante. Testar ambos
os limites inclusivos, um milissegundo fora de cada um e offsets que cruzem
essas fronteiras. A colisão da sentinela
`-1` deve ser eliminada por canal de erro distinto, com migração explícita da API.
Incluir rejeição das grafias negativas proibidas e de `:60`, preservação de
`out` em falha checked e distinção entre ano `-1` e NA em uma mesma série.
Preservar a regressão R02: `2023-01-01` pertence à semana ISO 52, sem aceitar
52 ou 53 como resultados equivalentes.

<a id="section-deteccao-de-datas-e-diagnostico-decisoes-da-retomada"></a>

### Detecção de datas e diagnóstico — decisões da retomada

Contrato aprovado para implementação futura. Mapear APIs e consumidores antes
de alterar código. A inferência atual de strings no construtor Lua não realiza
esta detecção de datetime.

- Validar todos os valores não nulos da coluna antes de concluir a conversão.
  Uma amostra ou prefixo válido não basta para aprovar o restante.
- **Prioridade de interpretação aprovada em 2026-09-21:** primeiro, respeitar
  o formato explicitamente informado. Sem formato, reconhecer os formatos
  suportados, como ISO, usando a ordem dia/mês ou mês/dia configurada para
  resolver entradas como `02/05/2026`. Sem configuração, usar um padrão
  documentado e previsível.
- **Escopo inicial simplificado:** reconhecer `/` e `-` automaticamente nos
  formatos aprovados, exigindo separadores iguais dentro de cada data.
  `dayfirst` define a ordem, independentemente do separador. Não exigir nem
  acrescentar argumento de formato explícito nesta etapa; essa opção fica
  para ampliação futura. A prioridade de formato acima vale quando tal opção
  for introduzida, não constitui requisito de implementação da API inicial.
- **Padrão preservado, aprovado em 2026-09-21:** mês/dia para formatos com
  ano no fim, equivalente ao `dayfirst=false` existente. Sem formato ou ordem
  explicitamente informados, `02/05/2026` significa 5 de fevereiro. Dia/mês
  permanece configurável; formatos com ano primeiro não mudam de ordem.
  Não depender da região do computador para escolher o padrão. Na API Lua,
  o argumento aprovado é `dayfirst`, booleano com padrão `false`: omitido ou
  `false` significa mês/dia; `true` significa dia/mês. Formato explícito tem
  prioridade sobre esse argumento; ano primeiro mantém sua ordem. O helper
  `Series.dt_parse(str, dayfirst)` preserva a forma existente. A opção de
  formato e a integração nas demais entradas ainda precisam ser fechadas.
- Aplicar uma única ordem dia/mês ou mês/dia aos formatos com ano no fim.
  Com dia/mês configurado, `02/05/2026` é 2 de maio e deve converter normalmente.
  `2026-05-02` identifica a mesma data pelo formato ISO. Uma entrada não é
  inválida apenas porque outra convenção permitiria interpretá-la de outra forma.
- Não trocar a ordem por elemento para aceitar entradas conflitantes:
  `13/02/2026` e `02/13/2026` não admitem uma ordem comum. Formatos com ano
  primeiro, como `2026-02-13`, podem coexistir com os demais sem impor uma
  ordem dia/mês. Aparência idêntica não é exigida.
- Na inferência automática, valor incompatível com a política de interpretação
  mantém a coluna como texto, preservando os valores. Não fabricar NA para
  concluir a detecção.
- Na conversão explicitamente solicitada para datetime, data impossível ou
  incompatível com o formato solicitado gera erro orientado, sem entregar resultado parcial ou transformar
  falha em NA. NA já presente na entrada continua sendo ausência.

Essa prioridade substitui a regra anterior de recusar conversão explícita
apenas por falta de evidência para resolver dia/mês. Um modo automático
estrito, solicitado explicitamente, permanece proposta separada; nele uma
evidência inequívoca na coluna poderia resolver a ordem. Não aplicar esse
modo por omissão. Entradas inválidas devem produzir falhas controladas,
nunca crash do motor.

**Conjunto inicial de formatos aprovado em 2026-09-21:** contrato a
implementar e verificar; esta lista não certifica o parser atual.

| Família | Exemplos | Regra |
|---|---|---|
| Ano primeiro | `2026-05-02`, `2026/05/02` | Ano com 4 dígitos; mês e dia com 2 |
| Ano no fim | `05/02/2026`, `5/2/2026`, `05-02-2026` | Ano com 4 dígitos; dia e mês com 1 ou 2; mês/dia por padrão, dia/mês configurável |
| Data com horário | `2026-05-02T14:30:00`, `2026-05-02 14:30:00` | Separador `T` ou espaço; hora, minuto e segundo com 2 dígitos; segundos obrigatórios |
| Fração após segundos | `.1`, `.123`, `.123000` | Aceitar somente precisão exata em milissegundos, conforme o perfil datetime |
| Offset após horário | `Z`, `-03:00`, `-0300` | Offset numérico com sinal positivo ou negativo; normalizar para UTC; omissão significa UTC |
| Ano negativo | `-000001-05-02` | Sinal menos e 6 dígitos; ano primeiro e hífens, conforme o perfil datetime |

Os dois separadores da data devem ser iguais. Data sem horário representa
meia-noite UTC. As famílias de data podem receber horário, fração e offset
conforme as regras acima; horário ou offset isolados não representam uma data.
Data impossível, segundo `60` e conteúdo extra ao final geram erro controlado.
Um formato explicitamente solicitado deve ser respeitado.

Ficam fora do conjunto inicial, para avaliação em ampliação posterior:
horário sem segundos (`14:30`), data compacta (`20260502`), ano com dois
dígitos (`02/05/26`), meses por nome (`2 maio 2026`), AM/PM e fusos nomeados.
A sintaxe pública para solicitar um formato ainda será definida; a aprovação
deste conjunto não introduz suporte a uma linguagem arbitrária de formatos.

**Diagnóstico dedicado:** `DATE_ON_THE_FENCE`, com a mensagem
`smaug error - there's a date on the fence`. Identifica ambiguidade de ordem
ou conflito de ordens entre elementos. Após a revisão da prioridade de
interpretação, seus gatilhos devem ser revistos: não emitir esse diagnóstico
para uma data resolvida por formato, ordem configurada ou padrão documentado.
Incluir operação, nome da coluna quando
disponível, índice baseado em 1, valor e orientação para corrigir a entrada ou
especificar a ordem. Em conflito, apresentar as duas ocorrências que exigem
ordens incompatíveis. Em Series sem nome, o índice identifica o elemento.
Arquivo e linha física são incluídos somente quando a origem estiver disponível;
não confundir índice da linha de dados com linha física de CSV.

Exemplo histórico de diagnóstico por ambiguidade (formato ilustrativo;
não representa mais a conversão padrão, e o modo estrito ainda é proposta):

```text
smaug error - there's a date on the fence
code: DATE_ON_THE_FENCE
operation: astype("datetime")
column: "data_pedido"
row: 7
value: "03/04/2026"

Could mean 3 April 2026 or 4 March 2026.
Specify day/month or month/day.
```

Uma data impossível como `31/02/2026` exige diagnóstico de data inválida,
não `DATE_ON_THE_FENCE`. O identificador dedicado não implica adicionar um
novo membro ao enum C: mapear sua representação e transporte C/FFI/Lua no
trabalho de erros, reaproveitando `SMG_ERR_ARGUMENT` para entrada inválida e
`SMG_ERR_OVERFLOW` para resultado fora da faixa.

**Atualização da política anterior:** conversão explícita para datetime passa
a exigir erro por entrada inválida; a revisão de 2026-09-21 resolve a ordem
por formato, configuração ou padrão, em vez de recusar datas comuns por
ambiguidade sem contexto. As menções anteriores deste
documento a `astype` tolerante descrevem a política anterior; não autorizam NA
silencioso na nova conversão explícita. A existência e a forma de um modo
tolerante opt-in, assim como a relação com helpers que retornam `nil`, devem
ser fechadas na [referência Lua](API_INDEX.md#section-datetime-migracao-lua)
antes da implementação.

**Verificação exigida:** coluna ambígua inteira; evidência inequívoca no início
e no fim; ordens conflitantes; data impossível; formatos com ano primeiro
misturados com ano no fim; NA preexistente; configuração explícita de ordem;
referências corretas do diagnóstico; preservação integral do texto quando a
inferência não concluir datetime. Verificar a detecção sem gerar expectativas
com o próprio parser sob teste.

<a id="section-mutacao-pontual-set-set-null-retorna-smaug-status-t"></a>

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

<a id="section-append-dinamico-append-append-null-retorna-int-0-1"></a>

### Append dinâmico (`append` / `append_null`) — retorna `int` (0 / -1)

Convenção mantida. Em views, dispara COW detach antes do grow.
Falha → `-1`; série permanece consistente.

<a id="section-leitura-get-shape-1-valor-status-anulavel"></a>

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

<a id="section-copy-on-write-em-views"></a>

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

---

[Referência do Núcleo C](API_Reference.md) · [Rework da suíte](TEST_SUITE_REWORK.md) · [Início da documentação](README.md)
