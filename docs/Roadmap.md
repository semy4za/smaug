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

Métricas: cobertura 96.16% linha / 75.42% branch; suíte de 6 testes em C (inclui
`test_allocfail` via `--wrap` e `test_ops_edge`) e 8 suítes em Lua (incluindo
property-based, ~222k checks). Valgrind-clean no Linux; build e testes validados
no Windows (MSYS2) via `windows-build.ps1`. Modelo de referência de teste:
SQLite.

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

### 1. Contrato defensivo do backend C — `[Planned]` (prioridade máxima)

Hoje o backend confia no caller; a validação mora no frontend Lua. Isso é
aceitável enquanto o único consumidor é o frontend, mas não para uma engine que
pretende durar anos e ser chamada direto do C por consumidores do ecossistema.

Toda fronteira pública em C deve lidar com ponteiros inválidos, índices
inválidos, parâmetros inconsistentes e estados inesperados — sem comportamento
indefinido, sem corrupção de memória, sem crashes evitáveis. Isso muda
assinaturas das funções de fronteira (`set`/`get`/`view` etc.), afetando FFI,
frontend e call sites — por isso é fase própria. Decisão de design a tomar quando
a fase começar: como o C sinaliza erro (provável referência: códigos de retorno
estilo RUST).

### 2. String completa — `[Done]`

A string é a primeira expansão real da engine além dos tipos numéricos. Ela
validou ownership, realocação, semântica de null, operações de cópia e
crescimento dinâmico — por isso é um marco arquitetural, não apenas mais um
dtype. A representação é offset-based estilo Arrow (buffer de bytes concatenados
+ array de offsets). O dictionary encoding não entra aqui — é a essência do
`categorical` (Tier 2), tipo separado, depois.

### 3. Semântica fechada — `[Planned]`

Definir de forma permanente o comportamento de `null`, `NaN`, ordenação,
comparação e agregações, de modo que mudanças futuras sejam mínimas. O contrato
de valores especiais (acima) é a base; esta frente o consolida como estável e
versionado, fechando ambiguidades antes que o ecossistema dependa dele.

### 4. Testes de stress — `[Planned]`

Aumentar a confiança em datasets grandes, operações encadeadas, crescimento de
memória e cenários extremos. Complementa a cobertura e o allocfail já existentes
com pressão real sobre a engine.

### 5. Consistência da API — `[In progress]`

Eliminar divergências entre documentação, roadmap e implementação. A
documentação deve refletir o código real. (Esta reformulação do Roadmap é o
primeiro passo; seguem `API_INDEX.md` e `API_Reference.md`.)

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
