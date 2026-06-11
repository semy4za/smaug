# Smaug — Roadmap

Este documento descreve a direção do projeto e o estado de cada frente de
trabalho. Ele separa o que já existe, o que está comprometido para a primeira
entrega (v1.0.0) e o que é visão de longo prazo ainda não comprometida.

Marcadores de status: `[Done]`, `[In progress]`, `[Planned]`, `[Concept]`,
`[Deferred]`. O histórico detalhado de mudanças fica no `CHANGELOG.md`; detalhes
de API ficam no `API_INDEX.md` e no `API_Reference.md`.

> Versionamento: o trabalho anterior a este documento é tratado como base
> consolidada (não recebe versões retroativas — não houve releases tagueados). O
> versionamento formal começa agora, mirando o **v1.0.0** como primeira entrega
> de produto.

---

## Princípio orientador

O Smaug é uma engine de dados em C e Lua: o backend existe em C, a API pública
existe em Lua. O objetivo não é competir com visualização, dashboards ou ML —
essas áreas são **consumidoras** da engine, não o foco dela. O foco é uma
fundação sólida para manipulação, transformação e análise de dados tabulares.

Toda decisão responde a uma pergunta: **isso fortalece a engine?** Se não,
provavelmente ainda não é prioridade. O ativo mais importante do projeto não é a
interface nem o ecossistema futuro — é a **confiabilidade da engine**. Toda
decisão deve preservar essa propriedade.

A arquitetura tem três camadas, e a ordem importa: o núcleo existe primeiro, o
ecossistema vem depois.

1. **Core Engine (C)** — memória, tipos, nulls, operações, estruturas e
   algoritmos. Deve ter API estável, comportamento previsível, semântica
   consistente e testes extensivos.
2. **Runtime Lua** — ergonomia, DSL, abstrações, integração. A API Lua é a
   linguagem principal do Smaug.
3. **Ecossistema** — analytics, visualização, telemetria, ML, aplicações.
   Nenhuma dessas áreas deve influenciar negativamente o desenho do núcleo.

---

## Estado atual

Base consolidada (pré-versionamento). O backend numérico (`float64`, `int64`,
`bool`) e o frontend (`Series`, `BoolSeries`, `DataSet`) estão implementados e
endurecidos. O tipo `string` (Tier 1) está completo — lifecycle, acesso,
mutação, comparações, `filter`/`take` e `sort`/`argsort`, validado nos dois
sistemas operacionais.

Métricas: cobertura **99.82% linha / 100.00% branch-alvo** (MC/DC completo,
1095/1095 ramos, 19 exclusões documentadas); suíte de 7 testes em C (inclui
`test_allocfail` via `--wrap`, `test_ops_edge` e `test_stress`) e 8 suítes em
Lua (incluindo property-based, 281083 checks). Valgrind-clean no Linux; build e
testes validados no Windows (MSYS2) via `windows-build.ps1`. Modelo de referência
de teste: SQLite.

| Frente | Entrega | Status |
|--------|---------|--------|
| Backend numérico | structs, lifecycle, ops `f64`/`i64`, null por bitmask | `[Done]` |
| Frontend | `Series` (despacho por dtype, `ffi.gc`, metamétodos) | `[Done]` |
| DataSet | slicing, filter, sort_by, select, CRUD de colunas | `[Done]` |
| BoolSeries | comparações, `filter`, lógica de Kleene (3 valores) | `[Done]` |
| Endurecimento | cobertura medida, property-based, allocfail, `fillna` | `[Done]` |
| Tipo `string` | offset-based (Arrow-like); ops completas | `[Done]` |
| `dropna` (Series) | remove nulos; habilita sort em série com nulos | `[Done]` |

### Contrato de valores especiais (decidido e implementado)

1. **`NaN` ≠ `null`.** `null` (bitmask) é ausência; `NaN` (IEEE 754) é valor
   presente porém indefinido. Nunca se convertem — vantagem do Smaug sobre
   pandas/numpy.
2. **`NaN` é contagioso** na aritmética (IEEE 754); comparações com `NaN` dão
   `false`.
3. **`sort`/`argsort` recusam `NaN`** (além de `null`): valor sem ordem definida
   é recusado, não ordenado errado. `±Inf` são ordenáveis.
4. **`sum` com `min_count`**: default `0` (compatível com pandas); `min_count=1`
   dá `null` se não houver valor válido. *(min_count ainda a implementar — ver
   dívida técnica.)*
5. **Conversões por elemento são tolerantes a falha.** `astype` nunca lança erro
   por causa de um elemento individual — elementos inconversíveis tornam-se
   `null`. A série inteira não é descartada por um dado ruim.

   ```
   "abc"  → float64  =>  null   (parse falhou)
   "abc"  → int64    =>  null   (parse falhou)
   NaN    → int64    =>  null   (sem representação inteira)
   Inf    → int64    =>  null   (sem representação inteira)
   null   → qualquer =>  null   (ausência se propaga)
   ```

   Isso define o comportamento vetorial: operações em lote são tolerantes a
   dados imperfeitos. A `null_mask` absorve o erro por elemento sem interromper
   o processamento da série.

---

## Caminho até v1.0.0 — maturidade do núcleo

A primeira entrega de produto é o **v1.0.0**. A régua não é quantidade de
features — é confiança. O objetivo desta fase não é adicionar funcionalidades, é
aumentar a confiança no que já existe. A pergunta correta não é "quantas features
existem?", e sim "quão confiável é o que já existe?".

Robustez é funcionalidade: testes não são suporte às funcionalidades, são
funcionalidades; cobertura é ferramenta de confiança, não métrica de vaidade;
Valgrind é parte do desenvolvimento, não etapa final. A capacidade de sobreviver
a entradas inválidas é tão importante quanto qualquer operação matemática.

O v1.0.0 fecha quando estes itens estiverem completos:

### 1. Contrato defensivo do backend C — `[Done]`

Toda fronteira pública em C valida e comunica. O engine não confia no caller.
Implementado: `smaug_status_t` (enum com `SMG_OK`, `SMG_NULL_VALUE`,
`SMG_ERR_OOB`, `SMG_ERR_ARGUMENT`, `SMG_ERR_NOMEM`); mutações `set`/`set_null`
retornam status; leituras `get` em Shape 1 (valor + status anulável, sem colisão
NaN/zero); nota de contrato em `smaug_core.h` invertida. Views adotam
**Copy-on-Write**: toda mutação (`set`, `set_null`, `append`, `append_null`)
materializa um buffer privado antes de escrever, preservando o pai. Falha de
alocação no detach retorna `SMG_ERR_NOMEM` com série intacta. Ver `docs/COW.md`
e `docs/CONTRACT.md` para a especificação completa.

### 2. String completa — `[Done]`

A string é a primeira expansão real da engine além dos tipos numéricos. Ela
validou ownership, realocação, semântica de null, operações de cópia e
crescimento dinâmico — por isso é um marco arquitetural, não apenas mais um
dtype. A representação é offset-based estilo Arrow (buffer de bytes concatenados
+ array de offsets). O dictionary encoding não entra aqui — é a essência do
`categorical` (Tier 2), tipo separado, depois.

### 3. Semântica fechada — `[Done]`

Comportamento de `null`, `NaN`, ordenação, comparação e agregações definido de
forma permanente e coberto por testes. Mudanças futuras que contradigam estes
contratos serão intencionais e versionadas.

Contratos pinados (ver `tests/test_special.lua` e `tests/test_ops_edge.c`):

- **`NaN` ≠ `null`.** `set(NaN)` grava um valor válido; `is_null` devolve
  `false`. `set_null` marca ausência. Nunca se convertem.
- **`NaN` é contagioso** na aritmética (IEEE 754). `ignore_na` pula `null`, não
  `NaN` — um `NaN` presente contamina reduções.
- **`sort`/`argsort` recusam `NaN`** (e `null`). Valores sem ordem total são
  rejeitados, não silenciados.
- **`±Inf` são ordenáveis.** `−Inf` no começo, `+Inf` no fim. `sum(+Inf, −Inf) =
  NaN` (IEEE).
- **Comparações com `NaN` devolvem `false` com máscara válida** (não NA). Um
  `null` em comparação devolve `false` com máscara `0x00` (NA) — distinção
  explícita.
- **`−0.0 == +0.0`** em todas as comparações. Soma neutra.
- **`sum` de série vazia ou toda-null = 0** (neutro de soma). `mean`/`min`/`max`
  de série vazia = `NaN`.
- **`i64` overflow faz wrap** (complemento de 2, igual a pandas/numpy). Resultado
  é um valor presente, não `null`. Comportamento definido na prática em todas as
  plataformas suportadas, mesmo sendo UB formal em C.
- **View `start + len` overflow-safe:** a checagem usa
  `start > size || len > size − start` (imune a wrap de `size_t`).

### 4. Testes de stress — `[Done]`

Confiança em datasets grandes, operações encadeadas, crescimento de memória e
cenários extremos. Implementado em `tests/test_stress.c` (alvo `make test-stress`),
Valgrind-clean com 90k+ allocs:

- **N=1M** (f64 + i64): criação, set em massa, sum/min/max/count/clone — ops
  lineares sem sort para manter Valgrind viável.
- **N=50k** (sort): sort + argsort, correctude verificada (extremos e centro).
- **N=50k** (append stress): 50k appends a partir de série vazia, múltiplos grow.
- **N=10k** (chain): create → filter → sort → take encadeados.
- **COW stress**: 200 views sobre série de 1k elementos, cada uma detachada via
  set; pai verificada como completamente intacta.
- **String N=1k**: set + sort + clone em escala moderada (alocação por elemento é cara).
- **10k ciclos** create/clone/view+COW/free sem acumulação de memória.

### 5. Consistência da API — `[Done]`

Divergências entre documentação, roadmap e implementação eliminadas. A
documentação reflete o código real: `API_Reference.md` tem seção String completa,
`CONTRACT.md` alinhado com `str_set` → `smaug_status_t`, `Build_and_Testing.md`
com listas e contagens corretas, `CHANGELOG.md` com histórico completo.

---

## Pós-v1.0.0 — expansão sobre núcleo confiável

Estas frentes alargam a engine. Vêm depois da maturidade do núcleo: expandir
antes de consolidar confiança tornaria a fundação instável. Ordem provável, não
comprometida.

### Enriquecimento de métodos — `[Planned]`

Sobre um núcleo confiável, alargar a capacidade de trabalho com dados:
- `.str` Tier A: `len`, `lower`/`upper`, `strip`, `contains`,
  `startswith`/`endswith`.
- Numéricas exploratórias: `value_counts`/`unique`, `median`/`quantile`,
  `abs`/`round`/`clip`.
- `DataSet:dropna()` (a `Series` já tem).

### I/O — CSV + JSON — `[Planned]`

Lê/escreve CSV (`.csv`/`.tsv`, com inferência de tipo) e JSON (records ou
columnar). Depende da string (já pronta). Sem coerção implícita entre dtypes. É o
que torna o Smaug utilizável com dados de arquivo reais — por isso é a expansão
de maior valor logo após o núcleo maduro.

### I/O — SQL — `[Concept]`

SQL é fonte de produção real; XML é nicho e fica para depois. Foco inicial: só
SQLite. A abstração de dialeto (MySQL/Postgres) não será feita agora — seria
abstração prematura com um banco só. Disciplina barata no lugar: concentrar toda
a interação SQL num único módulo de fronteira (como o `ffi_loader` faz para o C),
para que adicionar dialetos no futuro seja mexer num módulo, não caçar SQL
espalhado.

### Indexação expressiva — `[Planned]`

O padrão pandas `df[df.cidade == "SP"]` é um objetivo explícito de UX do Smaug.
A ergonomia não pode ser ignorada: uma pessoa que vem do pandas vai tentar isso
antes de qualquer outra coisa.

A forma Lua natural para isso é via `__index` e `__newindex` no DataSet, e via
`__eq` / `__lt` / `__le` no BoolSeries. O design precisa resolver três tensões:

1. `__eq` em Lua é usado para igualdade de tabelas — sobrescrever tem consequências
   sobre `==` em geral. A solução provável é um operador dedicado (ex. `s:is(v)`)
   ou aceitar o override com documentação clara do comportamento.
2. `df[mask]` exige que `__index` do DataSet distinga entre `mask` (BoolSeries) e
   `"coluna"` (string) — factível, a distinção é por tipo.
3. `df[df.cidade == "SP"]` encadeado exige que `df.cidade` retorne a Series
   (já funciona via `__index`) e que `series == valor` retorne uma BoolSeries
   (override de `__eq`).

Isso é Ring 1 puro — zero impacto no C. Entra depois do I/O básico (Ring 2),
quando o loop completo `lê → transforma → filtra` estiver disponível e a API
puder ser validada com dados reais. A implementação sem I/O seria açúcar
sintático sem contexto de uso real para validar as decisões de design.

### Analytics — GroupBy, Join, Window — `[Concept]`

Diferente de "mais uma operação": cada um exige estrutura nova. GroupBy precisa
de estrutura intermediária (grupos → agregações); Join precisa de
indexação/hashing de chaves e tipos de join; Window precisa de janelas
deslizantes com estado. Serão desenhados quando chegar a vez — depois do I/O
(analytics sem dados de fontes reais vale menos).

### DSL sobre Lua — `[Concept]`

O futuro do Smaug não depende de uma linguagem própria — Lua já é a linguagem do
projeto. A evolução natural é uma DSL baseada em Lua, encadeável, do tipo
`dados:filter(...):groupby(...):agg(...)`. O objetivo não é criar sintaxe nova, e
sim uma forma consistente de expressar operações.

### Lazy evaluation — `[Concept]` (por último)

Camada de orquestração (`LazyDataSet` → plano → `.collect()`) sobre as operações
eager que já existem; o modo eager continua o default. Pré-requisito de design já
parcialmente satisfeito: operações imutáveis e componíveis (imutabilidade por
padrão foi decidida cedo). Vem por último porque otimiza justamente o
GroupBy/Join — só há o que otimizar depois que eles existem.

---

## Escopo e visão de longo prazo

O Smaug é uma plataforma **single-node**: o objetivo é extrair o máximo de uma
única máquina. Primeiro corretude, robustez e previsibilidade; só depois
paralelismo, otimizações e escalabilidade. A excelência local vem antes da
distribuição.

A longo prazo, o Smaug deve ser uma fundação reutilizável, com consumidores como
analytics, telemetria de jogos, ETL, ML, visualização e aplicações embarcadas —
todos dependendo da mesma fundação. Por isso cada fraqueza no núcleo se
multiplica, o que justifica o rigor de teste antes de crescer.

O ecossistema (todos `[Concept]`, sem compromisso):
- **Visualização** (Matplotlib/UI propria 'Smaug|Vialactea Studio' (c++ futuro distante)): renderiza a partir de dados do Smaug. Implicação
  presente: a interface de exportação (`to_table` e afins) é API pública —
  mantê-la limpa e estável.
- **Machine Learning**: exige uma matriz numérica densa 2-D homogênea, tipo novo
  (`Matrix`/`Tensor2D`), distinto do `DataSet` heterogêneo. Broadcasting é
  pré-requisito. Distinguir scikit-like (factível) de TensorFlow-like (autodiff —
  drasticamente mais difícil em Lua).
- **ORM** (roadmap próprio): ciclo carregar → visualizar → manter → versionar,
  com versionamento de schema inspirado no conceito do Alembic (sistema próprio
  em Lua, não integração com o Alembic real). Das partes mais complexas;
  aspiração de longo prazo.
- **Port para Lua 5.4**: LuaJIT (Lua 5.1) tem FFI, Lua 5.4 não. Exige bindings C
  manuais. Implicação presente: manter a fronteira Lua↔C centralizada (no
  `ffi_loader`) facilita o port.

---

## Sistema de tipos

Conjunto curado, em três camadas. A `Series` abstrai o dtype (descritor +
backend C), então adicionar tipo não quebra a API.

- **Tier 1 — núcleo:** `float64` `[Done]`, `int64` `[Done]`, `bool` `[Done]`,
  `string` `[Done]`.
- **Tier 2 — alto valor (pós-v1.0):** `datetime` (`int64` epoch ms);
  `categorical` (codes `int32` + levels) — é aqui que entra o dictionary encoding
  (IDs + dicionário), acelerando groupby/comparação/sort com repetição.
- **Tier 3 — otimização (talvez):** `float32`, `int32/16/8`, `uint*` — mesma
  semântica, storage estreito. Só se um caso real justificar.

Princípios transversais: sem coerção implícita (conversão explícita via
`astype`); null por bitmask uniforme (inclusive para tipos sem NaN nativo);
mapeamento NumPy/pandas → Smaug documentado.

---

## Dívida técnica (registrada, não esquecida)

Itens conscientemente adiados, reagendados em fase dedicada. Os já pagos saíram
desta lista (ver `CHANGELOG.md`): allocfail estendido à string, cobertura de
branch dos numéricos, `Series:dropna`, correção do `set` i64 (CODE_REVIEW A7),
`windows-build.ps1` (auto-descoberta de fontes + todos os testes).

**Estatísticas/utilitárias:** `median`/`quantile` nativos; `abs`/`round`/`clip`;
`cumsum`/`cumprod`; `diff`/`shift`; `unique`/`value_counts`/`mode`; `fillna` por
método (fwd/bwd-fill); `sum(min_count)` (implementação). *(Os mais usados entram
no enriquecimento pós-v1.0.)*

**Semântica numérica:** broadcasting (Series de tamanhos diferentes / Series ×
array — pré-requisito de ML); `apply`/`map` (função Lua elemento a elemento);
reconciliar assimetria de div/0 entre f64 (IEEE: ±Inf/NaN) e i64 (→ NULL).

**Operações de string (`.str`, incremental por camadas):**
- *Tier A (mais usados):* `len`, `lower`/`upper`, `strip`/`lstrip`/`rstrip`,
  `contains`, `startswith`/`endswith`, `replace` (literal).
- *Tier B:* `split`, `cat`/join, `slice`, `pad`/`zfill`, `repeat`, `find`.
- *Tier C (caro/complexo):* regex (`extract`/`findall`/`match` — subprojeto à
  parte), `get_dummies`, normalização/validação UTF-8 (hoje trata bytes crus;
  case-folding Unicode-aware exige tabelas de caso).

**DataSet:** `DataSet:dropna()` (remover linhas com nulo, com possível `subset`
de colunas como no pandas) — o `sort_by` ainda menciona "use dropna primeiro" no
nível DataSet.

**Performance/robustez:** benchmarks e estresse (10⁷+ elementos); avaliação de
SIMD; `ffi.gc` em hot paths. *(Os testes de stress são item do v1.0.0.)*

**Observabilidade (fase dedicada):** sistema de warnings unificado (ex.: avisar
opt-in quando uma operação encontra `NaN`, overflow de i64), de forma sistemática
e sem penalizar os loops quentes.

**Build:** decidir o futuro do bloco CMake (atrelado à decisão Lua 5.4).
