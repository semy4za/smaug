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

**Métricas (após sessão de bugfix dos parsers I/O):** linha 95.99% (2248/2342),
branch-alvo 88.12% (2270/2576, 90 exclusões `COV-EXCL-BR` documentadas).
Valgrind-clean em todos os 9 binários (incluindo `test_allocfail` com 15330
allocs/15330 frees e `test_stress` com 90751/90751). Zero warnings `-Wall -Wextra`.

**Testes C:** `test_alloc`, `test_ops`, `test_ops_edge` (269 checks),
`test_bool`, `test_bool_lifecycle` (154 checks), `test_string` (118 checks),
`test_cow` (15 checks), `test_io_c` (174 checks), `test_datetime_c` (201 checks),
`test_allocfail` (1158 verificações via `--wrap`), `test_stress` (51 851 checks).

| Componente | Status |
|---|---|
| Lifecycle f64/i64 (create, clone, view, free) | `[Done]` |
| Ops f64/i64 (aritmética, reduções, sort, comparações) | `[Done]` |
| Lógica bool Kleene (and/or/xor/not, agregações) | `[Done]` |
| Tipo string offset-based (Arrow-like) | `[Done]` |
| Tipo datetime (epoch ms UTC, calendário Gregoriano proléptico) | `[Done]` |
| Contrato defensivo (`smaug_status_t`, Shape 1 get) | `[Done]` |
| Copy-on-Write em views (f64/i64/datetime) | `[Done]` |
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
- **Tier 2 — alto valor:** `datetime` (epoch ms) `[Done]`, `categorical` (codes + levels) `[Done]`.
- **Tier 3 — otimização (futuro):** `float32`, `int32/16/8` — só se caso real justificar.

Sem coerção implícita entre dtypes. Null por bitmask uniforme. Conversão
explícita via `astype` (suporta os pares entre os 6 dtypes).

---

## Anel 1 — Frontend Lua `[Done]`

Series, DataSet, ergonomia. A API Lua é a linguagem principal do Smaug.

**Testes Lua:** 21 suítes, 360k+ checks (incluindo property-based com 360 862 verificações).

| Componente | Status |
|---|---|
| `Series` — 74 métodos (acesso, aritmética, reduções, comparações, sort, map, rolling, unique/value_counts, abs/round/clip, cumsum/cumprod/diff/shift, ffill/bfill, cummin/cummax, argmin/argmax, rank/pct_rank, skew/kurtosis, mad/sem, mode/prod, median/quantile, where/mask, nlargest/nsmallest, expanding, sin/cos/tan/exp/log/sqrt) | `[Done]` |
| `bool` como dtype de primeira classe (`Series<bool>`, Kleene, `land`/`lor`/`lnot`/`lxor`) | `[Done]` |
| `DataSet` — 36 métodos (CRUD, filter, sort, select, assign, nunique, rolling, rename, pivot_table, stack/unstack, explode) | `[Done]` |
| `df[mask]` — indexação por `Series<bool>` (`__index` dispatch) | `[Done]` |
| `.str` Tier A: `len`, `lower`/`upper`, `strip`, `contains`, `startswith`/`endswith`, `replace` | `[Done]` |
| `.str` Tier B: `find`, `slice`, `pad`/`zfill`, `rep`, `cat`, `split` | `[Done]` |
| `.dt` accessor: 11 componentes + `format`/`truncate`/`diff`/`add_ms`/`add_days`/`add_hours`/`add_minutes`/`add_seconds` | `[Done]` |
| `.cat` accessor: `codes`/`levels`/`rename_categories`/`set_categories`/`add_categories`/`remove_categories` | `[Done]` |
| `CategoricalSeries` — Lua puro, dictionary encoding, integração total DataSet | `[Done]` |
| Comparações `gt`/`lt`/`eq`/`ge`/`le`/`ne` para f64, i64, string, datetime, categorical | `[Done]` |
| `Series:map(fn, dtype?)` com inferência e validação de tipo | `[Done]` |
| `div/0 → null` para f64 (uniforme com i64) | `[Done]` |
| `df["col"] = serie_ou_escalar` via `__newindex` (aceita f64/i64/bool/string/datetime/categorical) | `[Done]` |
| `Series.full(n, val)` (broadcast de escalar) | `[Done]` |
| `smaug.DataSet({{...}})` (açúcar de construção) | `[Done]` |
| `fillna` / `dropna` dtype-aware | `[Done]` |
| `describe` para numérico, string, bool, datetime, categorical | `[Done]` |
| `astype` tolerante por elemento (pares entre os 6 dtypes) | `[Done]` |

### Nota — limite da linguagem

`df[df.idade > 18]` com operadores nativos Lua não é implementável: `__lt`/`__le`
só disparam entre objetos do mesmo metatype (Lua 5.1/LuaJIT). A sintaxe
`:gt()`/`:lt()`/`:eq()` é o teto da linguagem, não uma escolha do Smaug.

---

## Anel 2 — Operações Relacionais `[Done]`

GroupBy, Join, Concat, Pivot, Melt, Rolling — implementados e testados.

**Testes Lua:** `test_groupby` (46), `test_concat` (35), `test_join` (52),
`test_dataset_ops` (61), `test_rolling_series` (37), `test_series_ops` (73),
`test_enrich` (151) — agregados, transformações, rolling estendido, expanding.

| Componente | Status |
|---|---|
| `groupby(key):sum/mean/min/max/count/std/var/median/first/last/prod/nunique/quantile` — chave simples e composta | `[Done]` |
| `groupby.agg({col = fn \| {fn1,...}})` — múltiplas agregações de uma vez | `[Done]` |
| `groupby.transform(fn, col)` — broadcast do resultado dentro do grupo | `[Done]` |
| `join(other, on, how)` — inner/left/right/outer, chave simples e composta | `[Done]` |
| `concat({ds1, ds2, ...})` — empilhamento vertical com validação de schema | `[Done]` |
| `pivot(index, columns, values)` — long → wide | `[Done]` |
| `pivot_table(index, columns, values, aggfunc)` — com agregação | `[Done]` |
| `melt(id_vars, value_vars)` — wide → long | `[Done]` |
| `stack` / `unstack` | `[Done]` |
| `explode(col)` | `[Done]` |
| `assign(nome, fn_ou_series)` — nova coluna calculada | `[Done]` |
| `rename(mapping)` em lote | `[Done]` |
| `rolling(w):sum/mean/min/max/std/var/count/median/quantile + min_periods` | `[Done]` |
| `expanding():sum/mean/min/max/std/var/count/median` | `[Done]` |
| DSL encadeável | `[Done]` (propriedade emergente do design eager) |

---

## Anel 3 — Conectividade / I/O `[Done]`

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
| allocfail nos parsers — 9 funções `af_csv_*`/`af_json_*`, Valgrind-clean | `[Done]` |
| NDJSON | `[Planned]` — bloqueado por schema (ver seção pós-1.0) |
| SQLite (read/write) | `[Planned]` — pós-1.0 |
| Excel `.xlsx` | `[Planned]` — pós-1.0 |
| Parquet / Arrow | `[Concept]` |

---

## Estado atual — caminho para v1.0

Tudo abaixo está implementado, testado e Valgrind-clean. Os blocos A/B/C/D
foram concluídos nas sessões de junho/2026.

### Bloco A — Estatística e valores ausentes `[Done]`

| Item | Onde |
|---|---|
| `median` / `quantile` | `Series` |
| `ffill` / `bfill` | `Series` |
| `groupby.std` / `var` / `median` / `quantile` | `GroupBy` |
| `rolling.std` / `var` / `count` / `median` / `quantile` + `min_periods` | `SeriesRolling` |

### Bloco B — Dtypes novos `[Done]`

| Item | Onde |
|---|---|
| `datetime` (epoch ms UTC + 11 componentes + parse/format/truncate/diff/add_*) | Anel 0 (C) + `.dt` accessor |
| `categorical` (dictionary encoding) | Anel 1 (Lua puro) + `.cat` accessor |

### Bloco C — Transformações e seleção `[Done]`

| Item | Onde |
|---|---|
| `cummin` / `cummax` | `Series` |
| `argmin` / `argmax` | `Series` |
| `nlargest` / `nsmallest` | `Series` |
| `where` / `mask` / `ifelse` (vetorizados) | `Series` |
| `groupby.first` / `last` / `nunique` / `prod` | `GroupBy` |
| `mode` / `prod` | `Series` |

### Bloco D — Matemática e conveniência `[Done]`

| Item | Onde |
|---|---|
| `sin` / `cos` / `tan` / `exp` / `log` / `sqrt` (vetorizadas) | `Series` |
| `isna` / `notna` (alias de `is_null`) | `Series` |
| `rename` em lote | `DataSet` |

### Bloco E — Robustez (encerra v1.0) `[In progress]`

| Item | Status |
|---|---|
| Bugs Valgrind dos parsers I/O (CSV+JSON, paths de OOM) | `[Done]` |
| Suite completo Valgrind-clean em 9 binários | `[Done]` |
| Auditoria de docs (Roadmap, API_INDEX, README, etc.) | `[Done]` |
| Hardening global de cobertura (`smaug_csv` 85%, `smaug_json` 72%, `smaug_datetime` 70%) | `[Planned]` |
| Docstrings nos métodos públicos de `Series` e `DataSet` | `[Planned]` |

### Bloco F — Enriquecimento dos núcleos (encerra v1.0) `[Planned]`

Decisão arquitetural: a v1.0 não fecha com o mínimo viável. Fecha com cobertura
operacional ampla das pretensões reais de uma DataFrame library, mantendo a
filosofia "zero dependências externas + null por bitmask + sem index".

A lista de referência foi a API pública do pandas (Series + DataFrame),
filtrada pelos princípios do Smaug:
- **Index nomeado:** rejeitado. Posição 1-based é o índice. Sem `loc`/`reindex`/
  `MultiIndex`/`align`/`reset_index`. Toda a família que depende de index fica
  fora (`xs`, `swaplevel`, `droplevel`, `reorder_levels`, `at_time`, `between_time`,
  `asof`, `asfreq`, `align`, `resample`, `to_period`, `to_timestamp`).
- **Plotting:** rejeitado. Smaug é engine, não GUI. Sem `.plot`, `.hist`, `.boxplot`.
- **I/O exótico:** `to_pickle`, `to_hdf`, `to_xarray`, `to_stata`, `to_clipboard`,
  `to_latex`, `to_orc`, `to_feather`, `to_html`, `style`, `__dataframe__` — fora.
  CSV+JSON cobrem o caso real; Parquet/Excel/SQL ficam para v1.5.
- **Operadores reversos** (`radd`/`rsub`/etc.) — não-issue: `__add` em Lua já cobre
  `1 + s` e `s + 1`.
- **Tipos extras:** `sparse`, `list`, `struct`, `period`, `timedelta` separado,
  `interval`, `decimal` — fora. Os 6 dtypes atuais cobrem o caso real.
- **`pipe`, `combine`, `update`, `squeeze`, `to_frame`** — pouco valor; Lua já
  encadeia `:method()` naturalmente.

Os pacotes abaixo entram um por sessão, com teste dedicado, entrada no CHANGELOG
e revisão de cobertura antes do próximo.

#### F.1 — Pacote estatístico `[Done]`

| Item | Onde | Notas |
|---|---|---|
| `corr(other)` / `cov(other)` | `Series` | Pearson; NA pula par; <2 pares ou var zero → NaN |
| `corr()` / `cov()` | `DataSet` | Matriz N×N retornada como DataSet (coluna `__index__` + uma por variável) |
| `autocorr([lag])` | `Series` | `:corr(:shift(lag))`; default lag=1 |
| `dot(other)` | `Series` | Produto interno; null propaga (resultado null) |
| `pct_change([periods])` | `Series` | `:diff()` normalizado pelo valor anterior; divisor zero → null |

#### F.2 — Pacote de predicados `[Done]`

| Item | Onde | Notas |
|---|---|---|
| `between(lo, hi, [inclusive])` | `Series` | `inclusive` ∈ {"both","left","right","neither"}; null propaga |
| `isin(values)` | `Series` | values = tabela Lua; retorna `Series<bool>`; null propaga |
| `is_unique` | `Series` | true se valores não-nulos distintos; nulos ignorados |
| `is_monotonic_increasing` / `is_monotonic_decreasing` | `Series` | `[strict]` opcional; null quebra a ordem |
| `equals(other)` | `Series` + `DataSet` | igualdade estrutural (tipos + tamanhos + valores + nulls); NaN==NaN |
| `compare(other)` | `Series` + `DataSet` | diff estruturado: Series `{i,self,other}`, DataSet `{linha,coluna,self,other}` |
| `idxmin` / `idxmax` | `Series` | aliases de `argmin`/`argmax` |
| `first_valid_index` / `last_valid_index` | `Series` | índice 1-based do 1º / último não-null |

#### F.3 — Pacote `.dt` estendido `[Done]`

| Item | Notas |
|---|---|
| `.dt:is_month_start()` / `:is_month_end()` | → `Series<bool>` |
| `.dt:is_quarter_start()` / `:is_quarter_end()` | → `Series<bool>` |
| `.dt:is_year_start()` / `:is_year_end()` | → `Series<bool>` |
| `.dt:is_leap_year()` | → `Series<bool>` |
| `.dt:days_in_month()` | → `Series<int64>` (28..31) |
| `.dt:round(unit)` / `.dt:ceil(unit)` | espelho de `truncate` (floor); mesmos units |
| `.dt:strftime(fmt)` | subset de strftime: `%Y %m %d %H %M %S %j %w %A %a %B %b`; locale = inglês fixo |
| `.dt:normalize()` | alias de `:truncate("D")` |
| `.dt:month_name()` / `:day_name()` | inglês fixo (português pode ser feito via `.cat` + `rename_categories`) |

#### F.4 — Pacote `.str` Tier C (sem regex, sem Unicode) `[Done]`

| Item | Notas |
|---|---|
| `.str:count(sub)` | quantas ocorrências literais por string → `Series<int64>` |
| `.str:isalnum()` / `:isalpha()` / `:isdigit()` / `:isspace()` / `:islower()` / `:isupper()` | predicados ASCII → `Series<bool>` |
| `.str:removeprefix(p)` / `:removesuffix(s)` | remoção literal idempotente |
| `.str:capitalize()` / `:title()` / `:swapcase()` | caixas adicionais (ASCII) |
| `.str:join(sep)` | inverso de `:cat` (atalho do `table.concat`) |

Regex (`extract`/`findall`/`match`/`fullmatch`) e normalização Unicode-aware
permanecem em v1.5 como `.str` Tier D.

#### F.5 — Pacote de acesso e ergonomia `[Done]`

| Item | Onde | Notas |
|---|---|---|
| `at[i]` / `iat[i]` | `Series` | acesso escalar direto (alias semântico de `get`) |
| `at[i, col]` / `iat[i, col]` | `DataSet` | acesso a célula única |
| `insert(loc, name, series)` | `DataSet` | inserir coluna em posição específica |
| `to_dict([orient])` | `DataSet` | `"records"` (lista de tabelas) e `"columns"` (default) |
| `from_dict(t, [orient])` | `DataSet` | construtor a partir de tabela Lua |
| `to_markdown()` | `DataSet` | tabela markdown (útil em READMEs, issues, PRs) |
| `to_string([opts])` | `DataSet` | render plain text (já temos via `print`, formalizar) |

#### F.6 — Pacote de duplicatas e operações binárias

| Item | Onde | Notas |
|---|---|---|
| `duplicated([keep])` | `Series` + `DataSet` | `keep` ∈ {"first","last","none"}; → `Series<bool>` |
| `drop_duplicates([subset], [keep])` | `Series` + `DataSet` | multi-coluna |
| `combine_first(other)` | `Series` | preenche null de self com valores de other |
| `searchsorted(value)` | `Series` | binary search; pede série ordenada (verifica via `is_monotonic_increasing`) |
| `repeat(n)` | `Series` | repete cada elemento n vezes (n escalar ou Series<int64>) |

### Checklist de release v1.0

- [x] Bloco A implementado e testado.
- [x] Bloco B implementado e testado.
- [x] Bloco C implementado e testado.
- [x] Bloco D implementado e testado.
- [x] `test_io_real.lua` para cotações (float64 alta precisão, SHIB).
- [x] Bugs Valgrind dos parsers I/O corrigidos.
- [x] Auditoria de docs concluída.
- [x] Bloco F.1 — Pacote estatístico.
- [x] Bloco F.2 — Pacote de predicados.
- [x] Bloco F.3 — Pacote `.dt` estendido.
- [x] Bloco F.4 — Pacote `.str` Tier C (sem regex/Unicode).
- [x] Bloco F.5 — Pacote de acesso e ergonomia.
- [ ] Bloco F.6 — Pacote de duplicatas e operações binárias.
- [ ] Hardening global (cobertura ≥ 95% branch-alvo nos arquivos restantes).
- [ ] Docstrings nos métodos públicos de `Series` e `DataSet`.
- [ ] `bash scripts/build.sh --all` verde + `make valgrind` clean.
- [ ] CHANGELOG entry v1.0.0.
- [ ] `git tag v1.0.0`.

---

## Pós-1.0 — v1.5 (com dependências externas)

| Item | Área |
|---|---|
| NDJSON | I/O (depende de schema declarativo — sem schema, inferência por linha é frágil) |
| SQLite (read/write) | I/O |
| Excel `.xlsx` | I/O |
| Parquet / Arrow | I/O |
| `lazy execution` (`LazyDataSet → plano → .collect()`) | engine |
| predicate / projection pushdown | engine |
| `expanding.*` adicionais / `resample` | rolling / temporal |
| `interpolate` | valores ausentes |
| regex string operations | `.str` Tier C |
| `cross_join` / `join por expressão` | joins |
| `query` / `eval` | DataSet |
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
- Cobertura `smaug_datetime.c` (70.33% branch-alvo) — fechar no hardening global.
- Cobertura `smaug_json.c` (72.27% branch-alvo) — fechar no hardening global.
- Cobertura `smaug_csv.c` (85.13% branch-alvo) — fechar no hardening global.
- Branches novos dos cleanup paths de OOM nos parsers I/O — `test_allocfail` precisa
  estender para cobrir os `for (k=0; k<c; k++) free(col_names[k])` introduzidos
  na sessão de bugfix.

**Anel 1:**
- `.str` Tier C: regex (`extract`/`findall`/`match`), normalização UTF-8 Unicode-aware. Registrado em v1.5.

**Decisões arquiteturais encerradas:**
- **Broadcasting rejeitado para Anel 1:** operações escalares cobrem o caso de uso.
  Broadcasting real (axis-aware) pertence ao `Tensor2D`/ML (Anel 5).
- **`bool` como dtype de primeira classe:** `[Done]`. `BoolSeries` aposentada.
- **COW string:** view/COW excluídos do tipo string conscientemente.
  String usa modelo de cópia direta. Limitação documentada em `COW.md`.
- **`categorical` como Lua puro:** sem C backend. Dictionary encoding gerenciado
  em Lua usando tabelas para `_codes`, `_levels`, `_level_map`. Decisão consciente
  para evitar fragmentação do contrato C com um tipo que é essencialmente um
  índice + tabela de strings.
- **NDJSON adiado:** o formato exige schema global para ser robusto. Inferência
  por linha gera conflitos de tipo entre linhas (ex: `false` JSON vira `null`
  no parser C, linha com `"a":null` infere `string`, conflita com linha com
  `"a":1` que infere `int64`). NDJSON entra junto com o schema declarativo.
- **Sem index nomeado:** posição 1-based é o índice. Tudo da família `loc`/
  `MultiIndex`/`reindex`/`align`/`set_index`/`reset_index`/`xs`/`swaplevel`/
  `droplevel`/`reorder_levels` fica fora — permanentemente, não adiado.
  Operações que dependem implicitamente de index temporal (`at_time`,
  `between_time`, `asof`, `asfreq`, `resample`, `to_period`, `to_timestamp`,
  `tz_convert`, `tz_localize`) também ficam fora. Quando o caso de uso aparecer,
  resolve-se com coluna `datetime` explícita.
- **Sem plotting:** Smaug é engine de dados, não GUI. `.plot`, `.hist`, `.boxplot`
  e família ficam fora. Visualização é responsabilidade de quem consome o Smaug.
- **I/O exótico fora:** `to_pickle`, `to_hdf`, `to_xarray`, `to_stata`,
  `to_clipboard`, `to_latex`, `to_orc`, `to_feather`, `to_html`, `style`,
  `__dataframe__` não fazem parte do escopo. CSV+JSON cobrem o caso real.
  Parquet/Excel/SQL ficam em v1.5 como peças encaixáveis no Anel 3.
- **Tipos extras descartados:** `sparse`, `list`, `struct`, `period`, `timedelta`
  separado, `interval`, `decimal` não entram. Os 6 dtypes (`float64`, `int64`,
  `bool`, `string`, `datetime`, `categorical`) cobrem o caso real.
- **Operadores reversos sem ação:** `radd`/`rsub`/`rmul`/etc. são solução pandas
  para um problema Python. `__add` no metatable Lua já cobre `1 + s` e `s + 1`
  simetricamente — não-issue.
- **`pipe`, `combine`, `update`, `squeeze`, `to_frame`** rejeitados: Lua já tem
  `:method()` encadeado nativamente; semântica de `combine`/`update` é frágil;
  a fronteira Series↔DataSet em Smaug é mais limpa que em pandas (sem necessidade
  de squeeze/to_frame).
