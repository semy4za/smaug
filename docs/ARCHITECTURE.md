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

A partir do Anel 3 o crescimento segue **duas trilhas paralelas** que compartilham
os anéis internos (0–2) e se reencontram no ML:

- **Trilha Analítica** (linha matemática): Matrix → Tensor → ML.
- **Trilha de Projeto** (linha de construção de aplicações): Persistence → Models.

Conectividade (Anel 3) e os anéis externos de ferramentas/interação servem às duas.

```
Anel 0  Núcleo C           buffers, memória, tipos, primitivas, engine
Anel 1  Abstrações          Series, BoolSeries, operações vetorizadas
Anel 2  Op. Relacionais     DataSet, join, groupby, reshape
Anel 3  Conectividade / I/O CSV, JSON, + conectores externos (SQL, Excel, Parquet)

        ── Trilha de Projeto ──        ── Trilha Analítica ──
Anel 4  Persistência                 Anel 6  Matrix
        .smg, save/load, snapshots            layout 2D denso, álgebra linear
Anel 5  Models                        Anel 7  Tensor
        schema, validação, CRUD local         N-dimensional, broadcasting axis-aware
                                       Anel 8  Machine Learning
                                               pipelines, treino/inferência

Anel 9  Interação — TUI, Studio, Web, Notebooks   (serve a todas as trilhas)
```

**Ponto de encontro:** o ML (Anel 8) consome o schema dos Models (Anel 5) e os
buffers contíguos do Núcleo (Anel 0). As duas trilhas convergem ali.

**Dependências (P2):** cada anel pode depender de anéis internos; nunca o inverso.
As duas trilhas dependem de 0–3; não dependem uma da outra (Matrix não conhece
Persistence, e vice-versa).

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

## Anel 4 — Persistência `[Concept]`

Trilha de Projeto. Faz dados sobreviverem ao fim do processo. **Não é um banco
de dados nem um ORM** — é serialização de estruturas Smaug.

**Responsabilidades:**
- Formato binário próprio (`.smg`): header (magic, versão, schema) + buffers por
  coluna + máscara de nulos
- `df:save("vendas.smg")` / `smaug.load("vendas.smg")`
- Snapshots
- Reader defensivo: arquivo truncado/corrompido/versão futura → erro claro, nunca
  crash (o engine não confia no arquivo, como não confia no caller)

**O que NÃO é (Fronteira encerrada):** ORM relacional, query builder, engine de
migração estilo Alembic. Quem precisa de banco relacional usa SQLite via Anel 3.
Persistência aqui responde *"como meu DataSet sobrevive ao processo?"* — não
*"como modelo estruturas relacionais que evoluem?"*.

**Distinção fundamental:**
- Conectividade (Anel 3) responde: *como os dados entram e saem?*
- Persistência (Anel 4) responde: *como um DataSet é serializado e recarregado idêntico?*

**Reuso:** aproveita os buffers contíguos do Anel 0 — salvar é, no essencial,
dump do buffer + cabeçalho de schema.

**Dependência:** Anel 4 → Anel 3 → Anel 2 → Anel 1 → Anel 0.

---

## Anel 5 — Models `[Concept]`

Trilha de Projeto. Camada de schema sobre os dados do próprio Smaug. **Não é ORM
relacional e não é persistência** — é uma camada própria que responde *"qual é a
forma e o contrato do meu dado?"*.

**Responsabilidades:**
- Schema nomeado: `smaug.Model("Pedido", { id="int64", valor="float64", uf="string" })`
- Validação, constraints, defaults, documentação do dado
- CRUD sobre DataSet **em memória** (create/update/delete/filter)
- Persistência delegada ao Anel 4 (`model:save()` / `Model.load(...)`)

**O que NÃO é (Fronteira encerrada):** sem transação, sem índice, sem
concorrência. Quem precisa disso usa SQLite via Anel 3. O Model opera sobre
DataSets em memória e persiste via serialização — não é um engine transacional.

**Papel na arquitetura:** é o contrato entre "os dados" e "o pipeline". Quando o
ML (Anel 8) precisa saber o que é feature, target, tipo de cada coluna e política
de nulo, essa informação mora no Model — não em convenção solta. Por isso Models
é fundação da Trilha Analítica também: **é onde as duas trilhas se encontram.**

**Dependência:** Anel 5 → Anel 4 → ... → Anel 0.

---

## Anel 6 — Matrix `[Concept]`

Trilha Analítica. Tipo matricial 2D denso, distinto do `DataSet` heterogêneo.

**Responsabilidades:**
- Layout 2D denso sobre buffer contíguo (a porta que o Bloco G mantém aberta)
- Álgebra linear básica, reduções por eixo, normalização

**Regra arquitetural:** Matrix consome buffers do Núcleo. O DataSet não conhece
Matrix.

---

## Anel 7 — Tensor `[Concept]`

Trilha Analítica. Generalização N-dimensional do Matrix.

**Responsabilidades:**
- Tensores N-dimensionais
- Broadcasting axis-aware (pertence aqui, **não** ao Anel 1 — Fronteira encerrada)

---

## Anel 8 — Machine Learning `[Concept]`

Trilha Analítica. Transforma dados em modelos preditivos. **Ponto de encontro das
duas trilhas:** consome o schema dos Models (Anel 5) e os buffers do Núcleo.

**Responsabilidades:**
- Pipelines de preparação (imputação, encoding, normalização) reusando primitivas
  do Anel 0
- Treinamento e inferência
- Engenharia de atributos
- Análise exploratória, profiling, estatísticas descritivas avançadas

**Regra arquitetural:** ML consome DataSets e Models. DataSets e Models não
conhecem ML.

**Lazy evaluation:** vem junto com ou depois do SQL (Anel 3 v1.5), porque o maior
ganho é o predicate pushdown sobre fontes externas.

---

## Anel 9 — Interação e Ferramentas `[Concept]`

Mecanismos de interação humana e observabilidade. Interfaces e ferramentas
consomem serviços — não definem lógica de negócio nem semântica de dados.

**Responsabilidades:**
- TUI, Studio (Smaug|Vialactea Studio)
- Rich console: `describe`, `explain`, inspeção de schema; profiling; debug
- Dashboards, integrações com notebooks, exploradores visuais

---

## Régua de versões

| Versão | Marco | Critério |
|---|---|---|
| **1.0** | DataFrame library completa | Anéis 0+1+2+3 + estatística robusta + dtypes `datetime`/`categorical` + transformações vetorizadas. Zero dependências externas. |
| **1.5** | Conectividade avançada + Lazy + Persistência | SQLite, Excel, Parquet/Arrow, `lazy execution`, driver de banco (`connect`/`query`/`execute`). Serialização `.smg` (Anel 4). Primeira dependência externa (libsqlite3/libpq, zlib). |
| **2.0** | Models | Schema, validação, CRUD local, save/load via Anel 4. Anel 5. |
| **2.x+** | Trilha Analítica | `Matrix` (Anel 6), `Tensor` + broadcasting axis-aware (Anel 7), ML e pipelines (Anel 8). |

*A numeração de versões não espelha 1:1 a de anéis — a v1.5 entrega tanto
conectividade (Anel 3 estendido) quanto serialização (Anel 4), porque ambas são
da Trilha de Projeto e dependem de infra externa.*

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

> **Nota:** os números abaixo refletem a medição anterior ao fechamento do Bloco F.
> As contagens atuais são maiores (28 suítes Lua, 10+ binários C). Os percentuais
> de cobertura serão **regenerados a partir do gcov real no hardening global**
> (Fase 5 do Roadmap) — não são atualizados de memória, por princípio.

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
