# Smaug — Roadmap

O histórico detalhado de mudanças fica no `CHANGELOG.md`. Detalhes de API ficam
no `API_INDEX.md` e no `API_Reference.md`. Contratos defensivos do backend C
ficam no `CONTRACT.md`.

Marcadores de status: `[Done]`, `[In progress]`, `[Planned]`, `[Concept]`.

---

## Filosofia

Smaug é fluido e robusto — uma engine feita para processar dados. Features
novas só entram sobre uma fundação sólida — um engine confiável vale mais
do que dez operações frágeis.

Robustez é funcionalidade. Testes não são suporte às funcionalidades, são
funcionalidades. Cobertura é ferramenta de confiança, não métrica de vaidade.
Valgrind é parte do desenvolvimento, não etapa final. A capacidade de sobreviver
a entradas inválidas é tão importante quanto qualquer operação matemática.

E o design importa. A API deve ser bonita de escrever e o fluxo de dados
deve ser natural de ler e conciso de compor.

---

## Arquitetura em anéis

O projeto cresce de dentro pra fora. Um anel só expande quando o interior está
sólido — não o contrário.

```
┌─────────────────────────────────────────┐
│  Ring 2+  I/O, persistência, analytics  │
│  ┌───────────────────────────────────┐  │
│  │  Ring 1  Series, BoolSeries,      │  │
│  │          DataSet, UX Lua          │  │
│  │  ┌─────────────────────────────┐  │  │
│  │  │  Ring 0  C puro: memória,   │  │  │
│  │  │  tipos, ops primitivas      │  │  │
│  │  └─────────────────────────────┘  │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

---

## Ring 0 — Backend C `[Done]`

Memória, tipos, operações primitivas. API estável. O engine não confia no
caller — toda fronteira pública valida e comunica o resultado.

**Métricas:** 99.82% linha / 100.00% branch-alvo (MC/DC completo, 1095/1095
ramos, 19 exclusões `COV-EXCL-BR` documentadas). Valgrind-clean. Zero warnings
`-Wall -Wextra`.

**Testes C:** `test_alloc`, `test_ops`, `test_ops_edge` (249 checks),
`test_bool`, `test_string` (114 checks), `test_cow` (15 checks),
`test_allocfail` (767 checks via `--wrap`), `test_stress` (51k+ checks).

| Componente | Status |
|---|---|
| Lifecycle f64/i64 (create, clone, view, free) | `[Done]` |
| Ops f64/i64 (aritmética, reduções, sort, comparações) | `[Done]` |
| Lógica bool Kleene (and/or/xor/not, agregações) | `[Done]` |
| Tipo string offset-based (Arrow-like) | `[Done]` |
| Contrato defensivo (`smaug_status_t`, Shape 1 get) | `[Done]` |
| Copy-on-Write em views | `[Done]` |
| Falha de alocação (OOM em todos os pontos públicos) | `[Done]` |
| Stress (N=1M, chains, 200 views, 10k ciclos) | `[Done]` |

### Semântica de valores especiais (decidida e implementada)

1. **`NaN` ≠ `null`.** `null` (bitmask) é ausência; `NaN` (IEEE 754) é valor
   presente porém indefinido. Nunca se convertem — vantagem sobre pandas/numpy.
2. **`NaN` é contagioso** na aritmética (IEEE 754). `ignore_na` pula `null`,
   não `NaN` — um `NaN` presente contamina reduções.
3. **`sort`/`argsort` recusam `NaN` e `null`.** Valores sem ordem total são
   rejeitados, não silenciados. `±Inf` são ordenáveis.
4. **Comparações com `NaN`** devolvem `false` com máscara válida (não NA).
   Um `null` em comparação devolve `false` com máscara `0x00` (NA).
5. **`i64` overflow faz wrap** (complemento de 2). Resultado é valor presente,
   não `null`.
6. **Conversões por elemento são tolerantes a falha.** `astype` nunca lança
   erro por elemento — inconversíveis tornam-se `null`.

   ```
   "abc" → float64  =>  null   (parse falhou)
   NaN   → int64    =>  null   (sem representação inteira)
   null  → qualquer =>  null   (ausência se propaga)
   ```

### Sistema de tipos

- **Tier 1 — núcleo:** `float64` `[Done]`, `int64` `[Done]`, `bool` `[Done]`,
  `string` `[Done]`.
- **Tier 2 — alto valor (Ring 1 futuro):** `datetime` (epoch ms); `categorical`
  (codes `int32` + levels, dictionary encoding — acelera groupby/sort com
  repetição).
- **Tier 3 — otimização (talvez):** `float32`, `int32/16/8`, `uint*` — mesma
  semântica, storage estreito. Só se caso real justificar.

Sem coerção implícita entre dtypes. Null por bitmask uniforme. Conversão
explícita via `astype`.

---

## Ring 1 — Frontend Lua `[In progress]`

Series, BoolSeries, DataSet, ergonomia. A API Lua é a linguagem principal do
Smaug. Ring 1 está fechado quando Series/BoolSeries/DataSet têm contratos
estáveis e operações tabulares fundamentais maduras — não quando todas as
features possíveis existem.

**Testes Lua:** 8 suítes, 281k+ checks (incluindo property-based).

| Componente | Status |
|---|---|
| `Series` (29 métodos, despacho por dtype, ffi.gc) | `[Done]` |
| `BoolSeries` (20 métodos, Kleene, coluna de primeira classe) | `[Done]` |
| `DataSet` (23 métodos, CRUD, filter, sort, select) | `[Done]` |
| `__newindex` (`df["col"] = series_ou_escalar`) | `[Done]` |
| `Series.full(n, val)` (broadcast de escalar) | `[Done]` |
| `smaug.DataSet({{"col", dados}, ...})` (açúcar de construção) | `[Done]` |
| UX de string (fillna dtype-aware, describe, astype tolerante) | `[Done]` |
| Contrato formal Ring 1 (`CONTRACT.md` seção Lua) | `[Done]` |

### Próximas frentes de Ring 1 `[Planned]`

**Indexação expressiva** — o padrão pandas `df[df.cidade == "SP"]` é objetivo
explícito de UX. Requer `__index` do DataSet distinguindo BoolSeries de string,
e decisão sobre `__eq` (override com consequências sobre `==` em Lua).
Entra depois do I/O (Ring 2) para validar com dados reais.

```lua
-- objetivo de UX (ainda não implementado)
local sp = df[df:col("uf"):eq("SP")]
```

**Enriquecimento de métodos:**
- `.str` Tier A: `len`, `lower`/`upper`, `strip`, `contains`,
  `startswith`/`endswith`.
- Numéricas: `value_counts`/`unique`, `median`/`quantile`, `abs`/`round`/`clip`.
- `DataSet:dropna()` (a `Series` já tem — `sort_by` ainda menciona "use dropna
  primeiro" no nível DataSet).

---

## Ring 2+ — I/O, persistência, analytics `[Planned / Concept]`

Expande a engine para fontes de dados reais. Depende do Ring 1 estável.

### I/O — CSV + JSON `[Planned]`

Lê/escreve CSV (`.csv`/`.tsv`, com inferência de tipo) e JSON (records ou
columnar). É o que torna o Smaug utilizável com dados de arquivo reais.
Struct intermediária comum `smaug_table_t` — todos os leitores a produzem,
todos os escritores partem de um `DataSet`.

### I/O — SQL `[Concept]`

Foco inicial: só SQLite. Abstração de dialeto adiada (prematura com um banco só).
Toda interação SQL concentrada num único módulo de fronteira — adicionar dialetos
no futuro é mexer num módulo, não caçar SQL espalhado.

### Analytics — GroupBy, Join, Window `[Concept]`

Cada um exige estrutura nova: GroupBy precisa de estrutura intermediária
(grupos → agregações); Join precisa de indexação/hashing de chaves; Window
precisa de janelas deslizantes com estado. Vêm depois do I/O — analytics
sem dados de fontes reais vale menos.

### DSL encadeável `[Concept]`

A evolução natural é uma DSL baseada em Lua do tipo
`dados:filter(...):groupby(...):agg(...)`. Objetivo: forma consistente de
expressar operações, não sintaxe nova.

### Lazy evaluation `[Concept]` (por último)

Camada de orquestração (`LazyDataSet` → plano → `.collect()`) sobre as operações
eager existentes. Vem por último porque otimiza justamente o GroupBy/Join — só
há o que otimizar depois que eles existem.

---

## Visão de longo prazo

O Smaug é single-node: extrair o máximo de uma única máquina. Primeiro
corretude, robustez e previsibilidade; só depois paralelismo e escalabilidade.

O ecossistema futuro (todos `[Concept]`, sem compromisso):
- **Visualização** (Smaug|Vialactea Studio, C++ — futuro distante): renderiza
  a partir de dados do Smaug. Implicação presente: `to_table` e afins são API
  pública — mantê-los limpos e estáveis.
- **Machine Learning**: exige `Matrix`/`Tensor2D` (tipo novo, distinto do
  `DataSet` heterogêneo). Broadcasting é pré-requisito. Distinguir scikit-like
  (factível) de TensorFlow-like (autodiff — drasticamente mais difícil em Lua).
- **ORM**: ciclo carregar → visualizar → manter → versionar, com versionamento
  de schema inspirado no Alembic (sistema próprio em Lua). Das partes mais
  complexas; aspiração de longo prazo.
- **Port para Lua 5.4**: LuaJIT (Lua 5.1) tem FFI; Lua 5.4 não. Exige bindings
  C manuais. Implicação presente: manter a fronteira Lua↔C centralizada no
  `ffi_loader` facilita o port.

---

## Dívida técnica registrada

Itens conscientemente adiados. Os já pagos saíram desta lista (ver `CHANGELOG.md`).

**Ring 0:**
- `sum(min_count)`: implementação pendente (semântica já decidida).
- Observabilidade: sistema de warnings unificado (overflow i64, NaN em
  operações) — fase dedicada, sem penalizar loops quentes.
- Build: decidir futuro do bloco CMake (atrelado à decisão Lua 5.4).

**Ring 1:**
- `DataSet:dropna()` com `subset` de colunas.
- `apply`/`map` (função Lua elemento a elemento).
- Broadcasting (Series de tamanhos diferentes / Series × array).
- Reconciliar assimetria de div/0: f64 (IEEE: ±Inf/NaN) vs i64 (→ null).
- Contrato formal Ring 1 escrito em `CONTRACT.md`.

**String (`.str`, incremental por camadas):**
- Tier A: `len`, `lower`/`upper`, `strip`, `contains`, `startswith`/`endswith`,
  `replace` (literal).
- Tier B: `split`, `cat`/join, `slice`, `pad`/`zfill`, `repeat`, `find`.
- Tier C: regex (`extract`/`findall`/`match` — subprojeto), normalização UTF-8
  (hoje trata bytes crus; case-folding Unicode-aware exige tabelas de caso).

**Performance:**
- Benchmarks e estresse a 10⁷+ elementos.
- Avaliação de SIMD.
- `ffi.gc` em hot paths.
