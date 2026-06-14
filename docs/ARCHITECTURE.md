# Smaug — Arquitetura

Documento de referência para a estrutura conceitual e o modelo de crescimento
do ecossistema Smaug. Muda raramente — descreve teoria, não entregas.

Para o estado atual de cada anel e as próximas entregas concretas, ver
`Roadmap.md`. Para o histórico de mudanças, ver `CHANGELOG.md`.

---

## Princípios

**P1 — Crescimento para fora.**
A evolução ocorre pela adição de anéis externos. Novas funcionalidades não
exigem expansão estrutural do núcleo.

**P2 — Dependências fluem para dentro.**
Um anel pode depender de anéis internos. O inverso é proibido.

```
Anel N → Anel N-1 → ... → Anel 0   ✓
Anel 0 → Anel 1                     ✗
```

**P3 — Propriedade semântica isolada.**
Cada responsabilidade pertence a exatamente um anel. Conceitos não são
duplicados entre camadas.

**P4 — Estabilidade cresce para dentro.**
Quanto mais próximo do centro, mais conservadora é a evolução esperada.
Camadas externas podem mudar rapidamente. O núcleo muda com cautela.

---

## Modelo de anéis

```
┌──────────────────────────────────────────────────────────┐
│  Anel 7  Interação — TUI, Studio, Web, Notebooks         │
│  ┌──────────────────────────────────────────────────┐    │
│  │  Anel 6  Ferramentas — Console, Debug, Profiling │    │
│  │  ┌────────────────────────────────────────────┐  │    │
│  │  │  Anel 5  Analytics e Machine Learning      │  │    │
│  │  │  ┌──────────────────────────────────────┐  │  │    │
│  │  │  │  Anel 4  Persistência — ORM, Schema  │  │  │    │
│  │  │  │  ┌────────────────────────────────┐  │  │  │    │
│  │  │  │  │  Anel 3  Conectividade — I/O   │  │  │  │    │
│  │  │  │  │  ┌──────────────────────────┐  │  │  │  │    │
│  │  │  │  │  │  Anel 2  Op. Relacionais │  │  │  │  │    │
│  │  │  │  │  │  ┌────────────────────┐  │  │  │  │  │    │
│  │  │  │  │  │  │  Anel 1  Abstrações│  │  │  │  │  │    │
│  │  │  │  │  │  │  ┌──────────────┐  │  │  │  │  │  │    │
│  │  │  │  │  │  │  │  Anel 0     │  │  │  │  │  │  │    │
│  │  │  │  │  │  │  │  Núcleo C   │  │  │  │  │  │  │    │
│  │  │  │  │  │  │  └──────────────┘  │  │  │  │  │  │    │
│  │  │  │  │  │  └────────────────────┘  │  │  │  │  │    │
│  │  │  │  │  └──────────────────────────┘  │  │  │  │    │
│  │  │  │  └────────────────────────────────┘  │  │  │    │
│  │  │  └──────────────────────────────────────┘  │  │    │
│  │  └────────────────────────────────────────────┘  │    │
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

---

## Anel 0 — Núcleo Computacional `[Done]`

Mecanismos fundamentais de execução. Máxima estabilidade, mínimo conhecimento
externo. Não conhece Series, DataSet, CSV, SQL, modelos nem interfaces.

**Responsabilidades:**
- Gerenciamento de memória (alloc, grow, free)
- Estruturas de armazenamento colunar (f64, i64, bool, string offset-based)
- Ownership, views, Copy-on-Write
- Máscaras de nulidade (null bitmask uniforme)
- Operações primitivas (aritmética, comparações, sort, filter, take)
- Contratos defensivos — toda fronteira pública valida e comunica o resultado

**Não conhece:** Series, DataSet, CSV, SQL, modelos, interfaces.

---

## Anel 1 — Abstrações de Dados `[Done]`

Transforma mecanismos do Anel 0 em estruturas semânticas. Define a forma
como usuários interagem e raciocinam sobre dados.

**Responsabilidades:**
- `Series` — coluna tipada 1D com null handling (dtypes: f64/i64/bool/string)
- `DataSet` — coleção de Series alinhadas
- Filtros, agregações, ordenação, transformações elementares
- Ergonomia Lua: açúcar sintático, metamétodos, accessor `.str`

**Dependência:** Anel 1 → Anel 0.

---

## Anel 2 — Operações Relacionais `[Done]`

Completa o modelo tabular com operações que transformam conjuntos de linhas
em novos DataSets. Pertence ao Anel 2 — não ao I/O — porque depende apenas
do Anel 1. GroupBy/Join são o coração do DataFrame.

**Responsabilidades:**
- GroupBy + agregações (sum/mean/count/min/max por grupo)
- Join / Merge (inner, left, right, outer)
- Window functions (rolling, cumulative)
- Concat (vertical e horizontal)
- Pivot / Melt

**DSL encadeável** (propriedade emergente do design eager):
`ds:filter(...):groupby(...):sum()` e `ds:join(other, "k"):sort_by("v")` funcionam
porque cada operação retorna um DataSet.

**Dependência:** Anel 2 → Anel 1 → Anel 0.

---

## Anel 3 — Conectividade / I/O `[Done — v1.0]`

Integra o ecossistema com fontes externas de dados. Transporta dados — não
define semântica, não define persistência, não define regras de negócio.

**Versões e dependências externas:**

| Formato | Versão | Dependência | Status |
|---|---|---|---|
| CSV | **1.0** | nenhuma — parser próprio | `[Done]` |
| JSON | **1.0** | nenhuma — parser próprio | `[Done]` |
| NDJSON | **1.2** | nenhuma | `[Planned]` |
| SQLite | **1.5** | libsqlite3 | `[Planned]` |
| Excel `.xlsx` | **1.5** | zlib + XML | `[Planned]` |
| Parquet / Arrow | **futuro** | — | `[Concept]` |

**Princípio de zero-dependências no 1.0:** CSV e JSON são parsers escritos do
zero. Nenhuma biblioteca externa no 1.0. A linha de versão passa exatamente
onde a independência do núcleo seria quebrada.

**Fronteira `smaug_table_t`:** todo leitor produz `smaug_table_t`, todo escritor
parte de um `DataSet`. Adicionar um novo formato é implementar um plugue — sem
tocar no núcleo nem nos anéis internos.

**Contrato P5 (ativo desde v1.0):**
```
Fonte externa → Conectividade → DataSet   (carregar)
DataSet → Conectividade → Destino         (exportar)
```

**Dependência:** Anel 3 → Anel 2 → Anel 1 → Anel 0.

---

## Anel 4 — Persistência `[Concept — v2.0]`

Gerencia estruturas persistidas e sua evolução ao longo do tempo.

**Responsabilidades:**
- ORM e Query Builder
- Registro de metadados e schema formal
- Engine de migração (estilo Alembic)
- Versionamento de schema

**Distinção fundamental:**
- Conectividade (Anel 3) responde: *como os dados entram e saem?*
- Persistência (Anel 4) responde: *como estruturas persistidas são organizadas e evoluem?*

**Dependência:** Anel 4 → Anel 3 → Anel 2 → Anel 1 → Anel 0.

---

## Anel 5 — Analytics e Machine Learning `[Concept]`

Transforma dados em conhecimento, métricas ou modelos preditivos.

**Responsabilidades:**
- Análise exploratória, profiling, estatísticas descritivas avançadas
- Engenharia de atributos
- Pipelines de treinamento e inferência
- Tipo `Matrix`/`Tensor2D` (distinto do `DataSet` heterogêneo)
- Broadcasting axis-aware (pertence aqui, não ao Anel 1)

**Regra arquitetural:** ML consome DataSets. DataSets não conhecem ML.

**Lazy evaluation:** vem junto com ou depois do SQL (Anel 3 v1.5), porque o
maior ganho é o predicate pushdown sobre fontes externas.

**Dependência:** Anel 5 → anéis internos conforme necessário.

---

## Anel 6 — Ferramentas `[Concept]`

Observabilidade e produtividade. Ferramentas observam — não definem semântica.

**Responsabilidades:**
- Rich console: `describe`, `explain`, inspeção de schema
- Relatórios de profiling
- Ferramentas de debug e exploração de dados

---

## Anel 7 — Interação `[Concept]`

Mecanismos de interação humana. Interfaces consomem serviços — não definem
lógica de negócio nem semântica de dados.

**Responsabilidades:**
- TUI, Studio (Smaug|Vialactea Studio)
- Dashboards, integrações com notebooks
- Interfaces web, exploradores visuais

---

## Régua de versões

| Versão | Marco | Critério |
|---|---|---|
| **1.0** | DataFrame library completa | Anéis 0+1+2+3 + estatística robusta + dtypes `datetime`/`categorical` + transformações vetorizadas. Zero dependências externas. |
| **1.5** | Conectividade avançada + Lazy | SQLite, Excel, Parquet/Arrow, `lazy execution`, `groupby.agg/transform`. Primeira dependência externa (libsqlite3, zlib). |
| **2.0** | Persistência/ORM | Schema, migrations, audit trail. Anel 4 completo. |
| **2.x** | ML e Analytics | `Matrix`/`Tensor2D`, broadcasting, pipelines. Anel 5. |

---

## Regra de decisão arquitetural

Toda nova funcionalidade deve responder:

> *Qual é o anel mais interno capaz de resolver este problema sem violar
> a separação de responsabilidades?*

A implementação ocorre nesse anel — nunca mais profundamente do que o necessário.

---

## Estado atual do núcleo

### Robustez arquitetural

| Área | Estado |
|---|---|
| Tipos colunares (f64/i64/bool/string) | ✅ Forte |
| Separação por tipo (core vs ops) | ✅ Forte |
| Null bitmask uniforme | ✅ Forte |
| Semântica null / NaN / ±Inf / div/0 | ✅ Forte — contratos explícitos e decididos |
| Ordenação determinística | ✅ Forte |
| Contratos defensivos | ✅ Forte — toda fronteira pública valida |
| Tratamento de OOM | ✅ Forte — todos os pontos públicos cobertos, incluindo parsers I/O |
| Integridade de memória | ✅ Forte — Valgrind-clean em 9 binários |
| Views e Copy-on-Write | ✅ Forte |
| Isolamento após COW detach | ✅ Forte |
| Álgebra booleana Kleene | ✅ Forte |
| Filter / Take / Sort | ✅ Forte |
| Consistência de API | ✅ Forte |
| Dependências externas | ✅ Forte — núcleo e Anel 3 v1.0 independentes |
| Extensibilidade para novos formatos I/O | ✅ Forte — fronteira `smaug_table_t` plugável |

### Validação e evidências

| Área | Estado |
|---|---|
| Testes C (Anéis 0+3) | ✅ test_alloc, test_ops, test_ops_edge (269), test_bool, test_bool_lifecycle (154), test_string (118), test_cow (15), test_io_c (174 checks) |
| Testes Lua (Anéis 1+2+3) | ✅ 18 suítes, 360 862+ checks |
| Stress tests (51k+ checks) | ✅ Forte |
| Property-based testing (360k+ checks) | ✅ Forte |
| AllocFail testing (1158 verificações) | ✅ Forte — inclui parsers CSV/JSON |
| Branch coverage / MC/DC | ✅ 88.12% branch-alvo (parsers I/O incluídos, 90 exclusões) |
| Cobertura de linhas | ✅ 95.99% |
| Cross-platform (Windows/Linux) | ✅ Validado — MSYS2-UCRT64 + Fedora |
| Dados reais | ✅ pedidos_digitados.csv (916 linhas), cotações CSV/JSON |
| Fuzzing | ⚠️ Ausente — lacuna registrada |
