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
┌──────────────────────────────────────────────────────┐
│  Anel 6  Interação — TUI, Studio, Web, Notebooks     │
│  ┌────────────────────────────────────────────────┐  │
│  │  Anel 5  Ferramentas — Console, Debug, Profiling│  │
│  │  ┌──────────────────────────────────────────┐  │  │
│  │  │  Anel 4  ML e Analytics                  │  │  │
│  │  │  ┌────────────────────────────────────┐  │  │  │
│  │  │  │  Anel 3  Persistência — ORM, Schema│  │  │  │
│  │  │  │  ┌──────────────────────────────┐  │  │  │  │
│  │  │  │  │  Anel 2  Conectividade — I/O │  │  │  │  │
│  │  │  │  │  ┌────────────────────────┐  │  │  │  │  │
│  │  │  │  │  │  Anel 1  Abstrações   │  │  │  │  │  │
│  │  │  │  │  │  ┌──────────────────┐ │  │  │  │  │  │
│  │  │  │  │  │  │  Anel 0  Núcleo │ │  │  │  │  │  │
│  │  │  │  │  │  └──────────────────┘ │  │  │  │  │  │
│  │  │  │  │  └────────────────────┘  │  │  │  │  │  │
│  │  │  │  └──────────────────────────┘  │  │  │  │  │
│  │  │  └────────────────────────────────┘  │  │  │  │
│  │  └──────────────────────────────────────┘  │  │  │
│  └────────────────────────────────────────────┘  │  │
└──────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

---

## Anel 0 — Núcleo Computacional

**Status: `[Done]`**

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

## Anel 2 — Abstrações de Dados

**Status: `[Done]`**

Transforma mecanismos do Anel 0 em estruturas semânticas. Define a forma
como usuários interagem e raciocinam sobre dados.

**Responsabilidades:**
- `Series` — coluna tipada 1D com null handling (dtypes: f64/i64/bool/string)
- `DataSet` — coleção de Series alinhadas
- Filtros, agregações, ordenação, operações relacionais
- Ergonomia Lua: açúcar sintático, metamétodos, accessor `.str`

**Dependência:** Anel 1 → Anel 0.

---

## Anel 2 — Operações Relacionais

**Status: `[Done]`**

Completa o modelo tabular com operações que transformam conjuntos de linhas
em novos DataSets. Pertence ao Anel 2 — não ao I/O — porque depende apenas
do Anel 1. GroupBy/Join são o coração do DataFrame; vêm antes de I/O por
valor e por dependência técnica.

**Responsabilidades:**
- GroupBy + agregações (sum/mean/count/min/max por grupo)
- Join / Merge (inner, left, outer)
- Window functions (rolling, cumulative)
- Concat (vertical e horizontal)
- Pivot / Melt

**DSL encadeável** (propriedade emergente, já presente no Anel 1):
`ds:filter(...):sort_by(...):head(n)` funciona hoje porque cada operação
retorna um DataSet. GroupBy/Join seguirão o mesmo padrão quando implementados.

**Dependência:** Anel 2 → Anel 1 → Anel 0.

---

## Anel 3 — Conectividade / I/O

**Status: `[Planned]`**

Integra o ecossistema com fontes externas de dados. Transporta dados — não
define semântica, não define persistência, não define regras de negócio.

**Versões e dependências externas:**

| Formato | Versão | Dependência externa |
|---|---|---|
| CSV | **1.0** | nenhuma — parser próprio |
| JSON | **1.0** | nenhuma — parser próprio |
| SQLite | **1.5** | libsqlite3 |
| Excel `.xlsx` | **1.5** | zlib + XML |
| Arrow / Parquet | futuro | — |

**Princípio de zero-dependências no 1.0:** CSV e JSON são parsers escritos do
zero. Nenhuma biblioteca externa no 1.0. A linha de versão passa exatamente
onde a independência do núcleo seria quebrada.

**Fronteira plugável:** todo leitor produz DataSet, todo escritor parte de
DataSet. Adicionar um novo formato é implementar um plugue — sem tocar no
núcleo nem nos anéis internos.

**Contrato funcional (P5):**
```
Fonte externa → Conectividade → DataSet   (carregar)
DataSet → Conectividade → Destino         (exportar)
```
Este ciclo é inquebrável a partir do 1.0.

**Dependência:** Anel 3 → Anel 2 → Anel 1 → Anel 0.

---

## Anel 4 — Persistência

**Status: `[Concept]`**

Gerencia estruturas persistidas e sua evolução ao longo do tempo.

**Responsabilidades:**
- ORM e Query Builder
- Registro de metadados e schema
- Engine de migração (estilo Alembic)
- Versionamento de schema

**Distinção importante:**
- Conectividade (Anel 3) responde: *como os dados entram e saem?*
- Persistência responde: *como estruturas persistidas são organizadas e evoluem?*

**Dependência:** Anel 4 → Anel 3 → Anel 2 → Anel 1 → Anel 0.

---

## Anel 5 — Analytics e Machine Learning

**Status: `[Concept]`**

Transforma dados em conhecimento, métricas ou modelos preditivos.

**Responsabilidades:**
- Análise exploratória, profiling, estatísticas descritivas
- Engenharia de atributos
- Pipelines de treinamento e inferência
- Avaliação e serialização de modelos
- Domínios: forecasting, classificação, regressão, clustering

**Regra arquitetural:** ML consome DataSets. DataSets não conhecem ML.

**Nota sobre broadcasting:** broadcasting axis-aware pertence a este anel,
associado ao tipo `Tensor2D` (distinto do `DataSet` heterogêneo). Broadcasting
de Series de tamanho 1 foi rejeitado no Anel 1 — operações escalares já cobrem
o caso sem introduzir semântica de shape.

**Lazy evaluation:** vem depois do SQL (Anel 3, v1.5), porque o maior ganho
é o *predicate pushdown* sobre fontes externas. `LazyDataSet → plano → .collect()`
só vale a pena quando há uma fonte externa rica o suficiente para o pushdown
ser o diferencial.

**Dependência:** Anel 5 → anéis internos conforme necessário.

---

## Anel 6 — Ferramentas

**Status: `[Concept]`**

Observabilidade e produtividade. Ferramentas observam — não definem semântica.

**Responsabilidades:**
- Rich console: `describe`, `explain`, inspeção de schema
- Relatórios de profiling
- Ferramentas de debug e exploração de dados

**Dependência:** Anel 6 → anéis internos conforme necessário.

---

## Anel 7 — Interação

**Status: `[Concept]`**

Mecanismos de interação humana. Interfaces consomem serviços — não definem
lógica de negócio nem semântica de dados.

**Responsabilidades:**
- TUI, Studio (Smaug|Vialactea Studio)
- Dashboards, integrações com notebooks
- Interfaces web, exploradores visuais

**Dependência:** Anel 7 → anéis internos conforme necessário.

---

## Régua de versões

Derivada dos princípios, não arbitrária:

| Versão | Marco | Critério |
|---|---|---|
| **1.0** | Ciclo de dados fechado | Anel 0+1+2+3 (CSV/JSON). Zero dependências externas. P5 ativo. |
| **1.5** | SQL + Excel | Primeiro anel com dependência externa (zlib, libsqlite3). |
| **2.0** | Persistência/ORM | Estruturas que evoluem no tempo (schema, migração). |
| **2.x** | Lazy evaluation | Pushdown sobre SQL — só vale depois que SQL existe. |

---

## Regra de decisão arquitetural

Toda nova funcionalidade deve responder:

> *Qual é o anel mais interno capaz de resolver este problema sem violar
> a separação de responsabilidades?*

A implementação ocorre nesse anel — nunca mais profundamente do que o necessário.

---

## Estado atual do núcleo

Avaliação de robustez e confiabilidade dos Anéis 0 e 1.

### Robustez arquitetural

| Área | Estado |
|---|---|
| Tipos colunares (f64/i64/bool/string) | ✅ Forte |
| Separação por tipo (core vs ops) | ✅ Forte |
| Null bitmask uniforme | ✅ Forte |
| Semântica null / NaN / ±Inf / div/0 | ✅ Forte — contratos explícitos e decididos |
| Ordenação determinística | ✅ Forte |
| Contratos defensivos | ✅ Forte — toda fronteira pública valida |
| Tratamento de OOM | ✅ Forte — todos os pontos públicos cobertos |
| Integridade de memória | ✅ Forte — Valgrind-clean |
| Views e Copy-on-Write | ✅ Forte |
| Isolamento após COW detach | ✅ Forte |
| Álgebra booleana Kleene | ✅ Forte |
| Filter / Take / Sort | ✅ Forte |
| Consistência de API | ✅ Forte |
| Dependências externas | ✅ Forte — núcleo independente |
| Extensibilidade para novos tipos | ✅ Forte — demonstrada sem ruptura |
| Extensibilidade para operações futuras | ✅ Forte |

### Validação e evidências

| Área | Estado |
|---|---|
| Stress tests (N=1M) | ✅ Forte |
| Property-based testing (281k+ checks) | ✅ Forte |
| AllocFail testing (767 verificações) | ✅ Forte |
| Branch coverage / MC/DC | ✅ Forte — 100% branch-alvo (1095/1095) |
| Cobertura de linhas | ✅ Forte — 99.82% |
| Cross-platform (Windows/Linux) | ✅ Validado — MSYS2-UCRT64 + Fedora |
| Strings (robustez) | ✅ Forte — lifecycle, comparações, sort, filter, take |
| Fuzzing | ⚠️ Ausente — lacuna registrada na dívida técnica |

### Capacidade analítica

| Área | Estado |
|---|---|
| Aritmética vetorizada (f64/i64) | ✅ Forte |
| Comparações vetorizadas (gt/lt/eq/ge/le/ne) | ✅ Forte |
| Reduções (sum/min/max/mean/var/std) | ✅ Forte |
| Lógica booleana Kleene (`Series<bool>`, dtype pleno) | ✅ Forte |
| Filtros e seleção | ✅ Forte |
| Ordenação (sort/argsort) | ✅ Forte |
| Transformações (map, astype, fillna, assign) | ✅ Forte |
| Elementares (abs, round, clip) | ✅ Forte |
| `.str` Tier A+B (15 métodos) | ✅ Forte |
| `.str` Tier A | ✅ Forte |
| GroupBy (sum/mean/min/max/count, chave simples e composta) | ✅ Forte |
| Join (inner/left/right/outer, hash-based) | ✅ Forte |
| Concat (vertical, valida esquema) | ✅ Forte |
| Pivot / Melt | ✅ Forte |
| Window functions (rolling sum/mean/min/max) | ✅ Forte |
| Cumsum / Cumprod / Diff / Shift | ✅ Forte |
| Unique / Value counts / Nunique | ✅ Forte |
