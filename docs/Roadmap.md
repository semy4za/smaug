# Smaug — Roadmap

O histórico detalhado de mudanças fica no `CHANGELOG.md`. Detalhes de API ficam
no `API_INDEX.md` e no `API_Reference.md`. Contratos defensivos do backend C
ficam no `CONTRACT.md`. A estrutura conceitual e o modelo de crescimento em
anéis ficam no `ARCHITECTURE.md`.

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
sólido — não o contrário. Ver `ARCHITECTURE.md` para o modelo completo (7 anéis),
princípios, diagrama, regra de decisão e régua de versões.

---

## Anel 0 — Backend C `[Done]`

Memória, tipos, operações primitivas. API estável. O engine não confia no
caller — toda fronteira pública valida e comunica o resultado.

**Métricas:** 97.95% linha / 92.18% branch-alvo (1981/2149 ramos, 66 exclusões
`COV-EXCL-BR` documentadas). Valgrind-clean em todos os binários. Zero warnings
`-Wall -Wextra`.

**Testes C:** `test_alloc`, `test_ops`, `test_ops_edge` (269 checks),
`test_bool`, `test_bool_lifecycle` (154 checks), `test_string` (118 checks),
`test_cow` (15 checks), `test_io_c` (174 checks),
`test_allocfail` (1158 verificações via `--wrap`), `test_stress` (51k+ checks).

| Componente | Status |
|---|---|
| Lifecycle f64/i64 (create, clone, view, free) | `[Done]` |
| Ops f64/i64 (aritmética, reduções, sort, comparações) | `[Done]` |
| Lógica bool Kleene (and/or/xor/not, agregações) | `[Done]` |
| Tipo string offset-based (Arrow-like) | `[Done]` |
| Contrato defensivo (`smaug_status_t`, Shape 1 get) | `[Done]` |
| Copy-on-Write em views | `[Done]` |
| Falha de alocação (OOM em todos os pontos públicos, incluindo parsers I/O) | `[Done]` |
| Stress (N=1M, chains, 200 views, 10k ciclos) | `[Done]` |

### Semântica de valores especiais (decidida e implementada)

1. **`NaN` ≠ `null`.** `null` (bitmask) é ausência; `NaN` (IEEE 754) é valor
   presente porém indefinido. Nunca se convertem.
2. **`NaN` é contagioso** na aritmética (IEEE 754). `ignore_na` pula `null`,
   não `NaN` — um `NaN` presente contamina reduções.
3. **`sort`/`argsort` recusam `NaN` e `null`.** Valores sem ordem total são
   rejeitados, não silenciados. `±Inf` são ordenáveis.
4. **Comparações com `NaN`** devolvem `false` com máscara válida (não NA).
   Um `null` em comparação devolve `false` com máscara `0x00` (NA).
5. **`i64` overflow faz wrap** (complemento de 2).
6. **Conversões por elemento são tolerantes a falha.** `astype` nunca lança
   erro por elemento — inconversíveis tornam-se `null`.
7. **`div/0 → null` em ambos os tipos.** Comportamento uniforme, previsível.

### Sistema de tipos

- **Tier 1 — núcleo:** `float64` `[Done]`, `int64` `[Done]`, `bool` `[Done]`, `string` `[Done]`.
- **Tier 2 — alto valor (v1.1+):** `datetime` (epoch ms), `categorical` (codes + levels).
- **Tier 3 — otimização (futuro):** `float32`, `int32/16/8` — só se caso real justificar.

Sem coerção implícita entre dtypes. Null por bitmask uniforme. Conversão
explícita via `astype`.

---

## Anel 1 — Frontend Lua `[Done]`

Series, DataSet, ergonomia. A API Lua é a linguagem principal do Smaug.

**Testes Lua:** 16 suítes, 360k+ checks (incluindo property-based com 360 862 verificações).

| Componente | Status |
|---|---|
| `Series` — 51 métodos (acesso, aritmética, reduções, comparações, sort, map, rolling, unique/value_counts, abs/round/clip, cumsum/cumprod/diff/shift) | `[Done]` |
| `bool` como dtype de primeira classe (`Series<bool>`, Kleene, `land`/`lor`/`lnot`/`lxor`) | `[Done]` |
| `DataSet` — 31 métodos (CRUD, filter, sort, select, assign, nunique, rolling) | `[Done]` |
| `df[mask]` — indexação por `Series<bool>` (`__index` dispatch) | `[Done]` |
| `.str` Tier A: `len`, `lower`/`upper`, `strip`, `contains`, `startswith`/`endswith`, `replace` | `[Done]` |
| `.str` Tier B: `find`, `slice`, `pad`/`zfill`, `rep`, `cat`, `split` | `[Done]` |
| Comparações `gt`/`lt`/`eq`/`ge`/`le`/`ne` para f64, i64 e string | `[Done]` |
| `Series:map(fn, dtype?)` com inferência e validação de tipo | `[Done]` |
| `div/0 → null` para f64 (uniforme com i64) | `[Done]` |
| `df["col"] = serie_ou_escalar` via `__newindex` | `[Done]` |
| `Series.full(n, val)` (broadcast de escalar) | `[Done]` |
| `smaug.DataSet({{...}})` (açúcar de construção) | `[Done]` |
| `fillna` / `dropna` dtype-aware | `[Done]` |
| `describe` para numérico e string | `[Done]` |
| `astype` tolerante por elemento | `[Done]` |

### Nota — limite da linguagem

`df[df.idade > 18]` com operadores nativos Lua não é implementável: `__lt`/`__le`
só disparam entre objetos do mesmo metatype (Lua 5.1/LuaJIT). A sintaxe
`:gt()`/`:lt()`/`:eq()` é o teto da linguagem, não uma escolha do Smaug.

---

## Anel 2 — Operações Relacionais `[Done]`

GroupBy, Join, Concat, Pivot, Melt, Rolling — implementados e testados.

**Testes Lua:** `test_groupby` (46), `test_concat` (35), `test_join` (52),
`test_dataset_ops` (61), `test_rolling_series` (37), `test_series_ops` (73).

| Componente | Status |
|---|---|
| `groupby(key):sum/mean/min/max/count` — chave simples e composta | `[Done]` |
| `join(other, on, how)` — inner/left/right/outer, chave simples e composta | `[Done]` |
| `concat({ds1, ds2, ...})` — empilhamento vertical com validação de schema | `[Done]` |
| `pivot(index, columns, values)` — long → wide | `[Done]` |
| `melt(id_vars, value_vars)` — wide → long | `[Done]` |
| `assign(nome, fn_ou_series)` — nova coluna calculada | `[Done]` |
| `rolling(w):sum/mean/min/max(col)` — janela deslizante no DataSet | `[Done]` |
| DSL encadeável | `[Done]` (propriedade emergente do design eager) |

---

## Anel 3 — Conectividade / I/O `[Done — v1.0]`

Parsers próprios, zero dependências externas. Fronteira `smaug_table_t` plugável.

**Testes:** `test_io_c` (174 checks C), `test_io.lua` (70 checks),
`test_io_real.lua` (55 checks com dados reais: `pedidos_digitados.csv`,
916 linhas, sep `;`).

| Componente | Status |
|---|---|
| `read_csv` / `to_csv` — RFC 4180, inferência de tipo, sep/quote/header configuráveis | `[Done]` |
| `read_json` / `to_json` — array de records, escape completo, pretty/compacto | `[Done]` |
| variantes `_mem` — leitura/escrita em buffer sem arquivo | `[Done]` |
| `smaug_table_t` — fronteira C entre leitores e DataSet | `[Done]` |
| allocfail nos parsers — 9 funções af_csv_*/af_json_* | `[Done]` |
| Valgrind clean nos parsers | `[Done]` |
| NDJSON | `[Planned — v1.2]` |
| SQLite (read/write) | `[Planned — v1.5]` |
| Excel `.xlsx` | `[Planned — v1.5]` |
| Parquet / Arrow | `[Concept]` |

---

## Pré-1.0 — O que falta para o tag

1.0 fecha quando os itens abaixo estiverem implementados, testados e
com `bash scripts/build.sh --all` verde. Tudo aqui é Lua puro + C puro,
sem dependências externas — mesma classe dos Anéis 0-3.

### Bloco A — Estatística e valores ausentes

| Item | Área |
|---|---|
| `median` / `quantile` (qualquer percentil) | reduções Series |
| `ffill` / `bfill` | valores ausentes |
| `groupby.std` / `var` / `median` | groupby |
| `rolling.std` / `var` / `count` + `min_periods` | rolling |

### Bloco B — Dtypes novos

| Item | Área |
|---|---|
| `datetime` (epoch ms + year/month/day/weekday/diff) | dtype novo |
| `categorical` (dictionary encoding, codes int32 + levels) | dtype novo |

### Bloco C — Transformações e seleção

| Item | Área |
|---|---|
| `cummin` / `cummax` | janela temporal |
| `argmin` / `argmax` | ordenação e seleção |
| `nlargest` / `nsmallest` | seleção |
| `where` / `mask` / `ifelse` (vetorizados) | booleano |
| `groupby.first` / `last` / `nunique` / `prod` | groupby |
| `groupby.quantile` / `rolling.median` / `quantile` | estatística avançada |
| `mode` / `prod` | reduções |

### Bloco D — Matemática e conveniência

| Item | Área |
|---|---|
| `sin` / `cos` / `tan` / `exp` / `log` / `sqrt` (vetorizadas) | matemática |
| `isna` / `notna` (alias de `is_null`) | conveniência |
| `rename` em lote | DataSet |
| NDJSON I/O | I/O |

### Checklist de release

- [ ] Bloco A implementado e testado.
- [ ] Bloco B implementado e testado.
- [ ] Bloco C implementado e testado.
- [ ] Bloco D implementado e testado.
- [ ] `test_io_real.lua` para cotações (float64 alta precisão, SHIB).
- [ ] Docstrings nos métodos públicos de `Series` e `DataSet`.
- [ ] `bash scripts/build.sh --all` verde.
- [ ] CHANGELOG entry v1.0.0.
- [ ] `git tag v1.0.0`.

---

## Pós-1.0 — v1.5 (com dependências externas)

| Item | Área |
|---|---|
| SQLite (read/write) | I/O |
| Excel `.xlsx` | I/O |
| Parquet / Arrow | I/O |
| `lazy execution` (`LazyDataSet → plano → .collect()`) | engine |
| predicate / projection pushdown | engine |
| `groupby.agg` / `transform` / `apply` | groupby |
| `expanding.*` / `resample` | rolling / temporal |
| `interpolate` | valores ausentes |
| regex string operations | `.str` Tier C |
| `rank` / `pct_rank` / `skew` / `kurtosis` / `mad` / `sem` | estatística |
| `cross_join` / `join por expressão` | joins |
| `query` / `eval` / `explode` / `pivot_table` / `stack` / `unstack` | DataSet |
| schema formal e lineage | engenharia de dados |
| `stable sort` (timsort) | ordenação |

## Pós-1.0 — v2.0 (Persistência e ML)

ORM, schema declarativo, engine de migração. `Matrix`/`Tensor2D`.
Broadcasting axis-aware. Paralelismo. Anel 4 + Anel 5. Ver `ARCHITECTURE.md`.

---

## Dívida técnica registrada

**Anel 0:**
- `sum(min_count)`: semântica decidida, implementação pendente.
- Observabilidade: sistema de warnings unificado (overflow i64, NaN em operações).
- Build: bloco CMake desatualizado (decisão pendente sobre Lua 5.4 — ver ARCHITECTURE).
- Fuzzing: ausente — lacuna registrada.

**Anel 1:**
- `.str` Tier C: regex (`extract`/`findall`/`match`), normalização UTF-8 Unicode-aware. Registrado em v1.5.

**Decisões arquiteturais encerradas:**
- **Broadcasting rejeitado para Anel 1:** operações escalares cobrem o caso de uso.
  Broadcasting real (axis-aware) pertence ao `Tensor2D`/ML (Anel 5).
- **`bool` como dtype de primeira classe:** `[Done]`. `BoolSeries` aposentada.
- **COW string:** view/COW excluídos do tipo string conscientemente.
  String usa modelo de cópia direta. Limitação documentada em `COW.md`.
