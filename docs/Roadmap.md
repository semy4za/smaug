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

Coerência se verifica, não se presume. Disparidade estrutural ("existe aqui mas
não ali") é trabalho de auditor automatizável — paridade cruzada com lista de
exceções conscientes. Erro semântico de implementação (ex.: precisão perdida numa
conversão) escapa ao auditor estrutural e exige leitura humana e revisão cruzada.
As duas camadas se complementam; nenhuma substitui a outra.

---

## Arquitetura em anéis

O projeto cresce de dentro pra fora. Um anel só expande quando o interior está
sólido — não o contrário. A partir do Anel 3, o crescimento segue **duas trilhas
paralelas** (Projeto: Persistência→Models; Analítica: Matrix→Tensor→ML). Ver
`ARCHITECTURE.md` para o modelo completo (10 anéis, duas trilhas), princípios,
diagrama, regra de decisão e régua de versões.

---

## Anel 0 — Backend C `[Done]`

Memória, tipos, operações primitivas. API estável. O engine não confia no
caller — toda fronteira pública valida e comunica o resultado.

**Cobertura (Fedora autoritativo):** linha e branch-alvo medidos via gcov, com
exclusões `COV-EXCL-BR` documentadas — ver `COVERAGE.md` (gerado, nunca cravado
aqui). Meta de 95% branch-alvo atingida na campanha de hardening da Fase 5.
Valgrind-clean em todos os binários. Zero warnings `-Wall -Wextra`.

**Testes C (em `tests/c/`):** `test_alloc`, `test_ops`, `test_ops_edge`,
`test_bool`, `test_bool_lifecycle`, `test_string`, `test_cow`, `test_io_c`,
`test_datetime_c`, `test_ops_window` (primitivas Ring 0 da Fase 3: cumulativas,
rank, sorted_nonnull, multi_argsort, rolling), `test_allocfail` (via `--wrap`,
intercepta `malloc`/`realloc`/`calloc`/`strdup`), `test_stress`. Contagens no
output do `build.sh`.

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
6. **Conversões por elemento são tolerantes a falha — com uma exceção rígida.**
   `astype` para `float64`/`int64`/`string`/`datetime` não lança erro por
   elemento: inconversíveis tornam-se `null`. **Exceção:** `astype("bool")` a
   partir de numérico é estrito — aceita só `0`/`1`; qualquer outro valor lança
   erro que orienta para `:map(fn)` (decisão H.6.5.a). A regra de truthiness não
   é imposta silenciosamente; quem quer defini-la usa `map`.
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

**Testes Lua:** suítes em subpastas por domínio (`tests/series/`, `tests/dataset/`,
`tests/io/`, `tests/props/`), checks diretos + property-based (invariantes × seeds
× casos). Contagens no output do `build.sh`.

| Componente | Status |
|---|---|
| `Series` — métodos de acesso, aritmética, reduções, comparações, sort, map, rolling, unique/value_counts, abs/round/clip, cumsum/cumprod/diff/shift, ffill/bfill, cummin/cummax, argmin/argmax, rank/pct_rank, skew/kurtosis, mad/sem, mode/prod, median/quantile, where/mask, nlargest/nsmallest, expanding, sin/cos/tan/exp/log/sqrt | `[Done]` |
| `bool` como dtype de primeira classe (`Series<bool>`, Kleene, `land`/`lor`/`lnot`/`lxor`) | `[Done]` |
| `DataSet` — métodos de CRUD, filter, sort, select, assign, nunique, rolling, rename, pivot_table, stack/unstack, explode | `[Done]` |
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
| `astype` — tolerante por elemento (→`null`), exceto `bool` numérico que é rígido (só 0/1, resto orienta para `map`) | `[Done]` |

### Nota — limite da linguagem

`df[df.idade > 18]` com operadores nativos Lua não é implementável: `__lt`/`__le`
só disparam entre objetos do mesmo metatype (Lua 5.1/LuaJIT). A sintaxe
`:gt()`/`:lt()`/`:eq()` é o teto da linguagem, não uma escolha do Smaug.

---

## Anel 2 — Operações Relacionais `[Done]`

GroupBy, Join, Concat, Pivot, Melt, Rolling — implementados e testados.

**Testes Lua:** cobertos em `tests/dataset/test_relational.lua` (groupby, concat,
join) e `tests/series/test_window.lua` (rolling, expanding); agregados,
transformações e rolling estendido também exercitados em
`tests/dataset/test_core.lua` e `tests/series/test_stat.lua`.

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

**Testes:** `tests/c/test_io_c.c` (inclui casos UTF-8 do G.1),
`tests/io/test_csv.lua` (inclui dados reais: `pedidos_digitados.csv` em
`tests/fixtures/`, sep `;`), `tests/io/test_json.lua` (inclui unicode).

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

### Bloco E — Robustez (encerra v1.0) `[Substancialmente concluído]`

| Item | Status |
|---|---|
| Bugs Valgrind dos parsers I/O (CSV+JSON, paths de OOM) | `[Done]` |
| Suite completo Valgrind-clean em todos os binários | `[Done]` |
| Auditoria de docs (Roadmap, API_INDEX, README, etc.) | `[Done]` |
| Hardening global de cobertura dos parsers (csv/json/datetime) e ops_window até a meta de 95% branch-alvo | `[Done]` |
| Auditoria de asserção (C + Lua, caso a caso) — `test_ops`/`test_cow`/`test_bool`/`test_alloc`/`test_stress` convertidos de assert-only para checks reais | `[Done]` |
| 2 double-frees corrigidos em `smaug_json.c` (`smaug_read_json_mem` 3 sites; `parse_record` realloc parcial) — descobertos ao escrever testes de cobertura | `[Done]` |
| allocfail estendido a `calloc`/`strdup` (`--wrap` não interceptava em libc) | `[Done]` |
| Sincronização factual das docs (README, ARCHITECTURE, `Build_and_Testing.md`) | `[Done]` (Bloco I.1) |
| `COVERAGE.md` + `MANIFEST.txt` regenerados no Fedora a cada commit | `[Done]` (processo) |
| Docstrings nos métodos públicos de `Series` e `DataSet` | `[Planned]` (Fase 7) |

### Bloco F — Enriquecimento dos núcleos (encerra v1.0) `[Done]`

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

#### F.6 — Pacote de duplicatas e operações binárias `[Done]`

| Item | Onde | Notas |
|---|---|---|
| `duplicated([keep])` | `Series` + `DataSet` | `keep` ∈ {"first","last","none"}; → `Series<bool>` |
| `drop_duplicates([subset], [keep])` | `Series` + `DataSet` | multi-coluna |
| `combine_first(other)` | `Series` | preenche null de self com valores de other |
| `searchsorted(value)` | `Series` | binary search; pede série ordenada (verifica via `is_monotonic_increasing`) |
| `rep_each(n)` | `Series` | repete cada elemento n vezes (n escalar ou Series<int64>). Nome é `rep_each`, não `repeat` — `repeat` é palavra reservada em Lua |

---

# Caminho para a v1.0 e além

> **Princípio de governança.** A coerência de um fluxo futuro justifica *verificar
> que a porta está aberta* (barato, agora, via teste de negação no Bloco G).
> Nunca justifica *construir a porta antes da hora* (caro, fora de escopo). Toda
> vez que uma decisão revelar um caminho de longo prazo consistente (ML, banco,
> Models, Matrix), a resposta é a mesma: o Bloco G confirma que nada o bloqueia;
> a implementação fica na trilha pós-v1.0.

Três naturezas, nunca confundidas:
- **Dívida pré-v1.0 (obrigatória)** — ameaça estabilidade, memória, corrupção de
  dados, instalação ou contrato documentado. Segura o release.
- **Feature futura** — adiciona capacidade nova. *Não é dívida.* Não segura release.
- **Fronteira encerrada** — decidiu-se conscientemente não fazer. *Não é dívida.*

---

## PARTE I — Caminho até a v1.0 (fila sequencial)

Cada fase só começa quando a anterior entrega o dado que ela consome. ML e a
Trilha de Projeto entram aqui apenas como **lente** (teste de negação), nunca como
implementação.

### Fase 1 — Inventário arquitetural `[Done]`
*Leitura, não escrita. Produziu o mapa que alimentou o Bloco G. Entregável é um
documento de trabalho interno (mapa de `series.lua`/`dataset.lua` por blocos,
mapa de upvalues, débitos técnicos D1–D4, candidatos a Ring 0) — mantido fora do
repositório por escolha consciente: guia de sessão, não artefato versionável.*
- Mapear `series.lua` e `dataset.lua` por blocos de responsabilidade (linhas, eixo).
- Mapear accessors (`.str`, `.dt`, `.cat`) e `CategoricalSeries`.
- Três dimensões por bloco: (A) responsabilidade certa Lua ou C? (B) coeso ou
  arquivo-deus? (C) fecha alguma porta de Ring/Trilha futura? (resposta por **negação**).
- Mapa de acoplamento por upvalue (`DTYPES`, `methods`, `NA`, `str_map`, `bool_map`,
  `check_index`, …).
- Marcar candidatos a primitiva Ring 0 (loop denso + aritmética mecânica).
- Entregável: documento de inventário, sem alterar código.

### Fase 2 — Bloco G: decisões de fundação `[Done]`
*Consumiu o inventário. Decidiu (não implementou). Documento de decisões mantido
fora do repositório, junto ao inventário. Resultado consolidado: G.1
**implementado** (UTF-8 no JSON); G.2 **confirmado** (epoch_ms int64 definitivo;
semana ISO 53 é simplificação documentada, não bug); G.3 **boundary audit
fechado** (multi_argsort/rank/rolling → C; GroupBy/Join/Expanding → Lua); G.4
**todas as primitivas implementadas** (Grupos A+B+C, ver Fase 3); G.5 checklist
permanente de lições do Bloco F; G.6–G.9 **portas confirmadas abertas, sem ação
pré-v1.0** (buffer contíguo já exposto, from_dict+astype cobrem construção
defensiva, dtypes mapeiam SQL, formato `.smg` é pós-v1.0).*
- **G.1 — UTF-8 / strings:** `[IMPLEMENTADO]` `.str` permanece byte-oriented; o
  reader JSON decodifica `\uXXXX` para UTF-8 (antes degradava silenciosamente para
  `?`). Surrogate isolado ou hex inválido → erro claro. Ver Fase 3 / CHANGELOG.
- **G.2 — Datetime:** `[CONFIRMADO]` epoch_ms int64 UTC definitivo. Semana ISO
  retorna 53 para dias pertencentes ao ano anterior — simplificação consciente,
  documentada na API, não é bug.
- **G.3 — Boundary audit:** `[FECHADO]` `multi_argsort`, `rank`, rolling
  `sum/mean/min/max` → C. GroupBy (orquestração + agg), Join (hash) e Expanding →
  permanecem Lua.
- **G.4 — Engine candidates (Ring 0):** `[IMPLEMENTADO]` Grupo A (10 cumulativas/
  shift/fill/argmin/argmax), Grupo B (sorted_nonnull, rank, pct_rank), Grupo C
  (multi_argsort 5 dtypes + rolling com deque monotônica). Ver Fase 3.
- **G.5 — Lições do Bloco F:** `[CHECKLIST PERMANENTE]` palavras reservadas Lua
  (`repeat`→`rep_each`), `#table` com nil → sentinela `NA`, sem `tbl[i,j]` (usar
  `df:at`), `__lt`/`__le` só entre mesmos metatypes, função C nova sempre via
  descritor `DTYPES`.
- **G.6 — Buffer/matriz:** `[PORTA ABERTA]` `smaug_series_f64_t.data` já expõe
  `double*` contíguo; layout de N séries independentes é o caminho natural
  pós-v1.0 (Trilha Analítica).
- **G.7 — Construção defensiva de DataSet:** `[PORTA ABERTA]` `from_dict` + `astype`
  cobrem o caso v1.0; validação de schema externa fica no Anel 3 (Trilha de Projeto).
- **G.8 — Persistência e Model Layer:** `[PORTA ABERTA]` dtypes/schema atuais
  comportam Persistence (Anel 4) e Models (Anel 5) por cima; formato `.smg` com
  magic bytes + versionamento é pós-v1.0.
- **G.9 — Conectividade futura:** `[PORTA ABERTA]` os 6 dtypes têm mapeamento SQL
  direto; roundtrip categorical via dois `astype` explícitos. Verificado barato
  agora; nenhuma ação pré-v1.0.

### Fase 3 — Migração de primitivas para Ring 0 `[Done]`
*Só o que o Bloco G decidiu. Grupos A+B+C migrados e validados por
`tests/c/test_ops_window.c` (ampliado pela auditoria de asserção da Fase 5).
Consumidores Lua reescritos; suíte Lua permanece verde. Cada migração registrada
no CHANGELOG.*
- Por primitiva aprovada: implementar em C com guards → teste C dedicado (+allocfail
  se aloca) → reescrever o consumidor Lua → suíte Lua permanece verde → Valgrind +
  cobertura.
- Atualizar paridade (eixo C↔Lua mirror) se aplicável. Cada migração: CHANGELOG.

### Fase 4 — Reorganização estrutural (split dos arquivos-deus) `[Done]`
*Comportamento idêntico, zero mudança de API. `series.lua` (4389 linhas) → 16
submódulos + `init.lua` em `series/`; `dataset.lua` (2256 linhas) → 4 submódulos
+ `init.lua` em `dataset/`;
testes em subpastas por domínio (`tests/c/`, `tests/series/`, `tests/dataset/`,
`tests/io/`, `tests/props/`). Mecanismo de injeção via `I` (sem `require`
cruzado). As três fontes de build e o Eixo 12 atualizados (este último na sessão
de sincronização de scripts, 2026-06-17). Ver CHANGELOG.*

### Fase 5 — Hardening global `[Substancialmente concluído]`
*Estrutura congelada; cada teste mira o lugar definitivo. Esta fase IMPLEMENTA
decisões já tomadas (não delibera contrato).*
- ~~Medição de cobertura no Fedora (gcov autoritativo)~~ **`[Done]`** —
  `COVERAGE.md` real (números lá, não aqui). `smaug_ops_window.c`
  integrado à medição.
- ~~**Fechar cobertura dos parsers** → ≥95% branch-alvo~~ **`[Done]`** —
  `smaug_json.c`, `smaug_datetime.c`, `smaug_csv.c` e `smaug_ops_window.c` elevados
  à meta; transições registradas no CHANGELOG. O que resta nos parsers são branches
  de inputs malformados muito específicos e macros de comparação — rendimento
  decrescente, exclusões honestas auditadas.
- ~~**Auditoria de asserção** (cobertura mede execução, não verificação)~~
  **`[Done]`** — leitura caso a caso de todos os testes C e Lua. Binários
  assert-only convertidos para checks reais; `test_io_c`/`test_ops_edge`
  fortalecidos. Lição: grep/regex não auditam qualidade de teste (falso negativo
  em todos os C).
- ~~**2 double-frees em `smaug_json.c`**~~ **`[Done]`** — descobertos ao escrever
  os testes de cobertura. Confirma coverage-como-processo, não como métrica.
- ~~`test_allocfail` estendido à camada de ops (Frente B)~~ **`[Done]`** —
  f64/i64/bool/str/ops_str, window e datetime; estendido a `calloc`/`strdup`.
- ~~Implementar a decisão de G.1 sobre `\uXXXX`~~ **`[Done]`** — JSON decodifica
  para UTF-8; degradação silenciosa eliminada (Fase 3).
- ~~**Parity checker portável e determinístico**~~ **`[Done]`** — `common.lua` em
  Lua puro; relatório idêntico Fedora/Windows; 12 eixos.
- ~~**Coerência de construção (camada Lua)**~~ **`[Done]`** — inferência de dtype
  unificada numa fonte única (`Series.infer_dtype`), reusada por
  `from_table`/`from_columns`/`__call`/`full`/`map`; fim do default-float64
  silencioso; bool de boolean nativo; `Series` chamável + `from_array`;
  `astype("bool")` rígido; imutabilidade do `assign` fixada por teste.
- ~~Guard de tipo nos `cmp_*` de datetime~~ **`[Done]`** — alinhado com
  f64/i64/string; `target` não-número → erro orientado (achado I2 da auditoria
  código-vs-código).
- **Pendente:** docs sync (README/ARCHITECTURE/`Build_and_Testing.md`) → agendado
  no Bloco I, item 1. Property-based adicional / fuzzing dos parsers fica como
  lacuna registrada (não-bloqueante).

### Fase 5.H — Bloco H: coerência de API e convenções de entrada `[Parcial]`
*Design fechado. Camada Lua concluída (barata, container); camada Ring 0/I/O é
ciclo próprio com cobertura + Valgrind no Fedora.*

- **Camada Lua `[Done]`** — H.1 (`full` constrói vs `fill` modifica), H.2 (inferência
  universal, fim do default-float64), H.3 (`Series` chamável + `from_array`),
  H.6.1/6.2/6.3 (bool de boolean nativo; lista vazia → string), H.6.5.a
  (`astype("bool")` rígido). Tudo via fonte única `Series.infer_dtype`.
- **Camada Ring 0/I/O `[Planned]`** — H.5.b (`decimal` em `smaug_csv_opts_t`),
  H.5.c (`sep == decimal` → erro), H.5.a (`dayfirst` no reader), H.6.4 (ampliar
  `smaug_dt_parse` para formatos não-ambíguos). Escopo exato de H.6.4 confirmado
  ao atacar o bloco.
- **Testes pendentes (Lua) `[Planned]`** — `from_array`/`__call` (existem, sem teste
  explícito); `map` com retorno bool; contrato de imutabilidade do `assign`.

### Fase 5.I — Bloco I: fechamento de coerência pré-v1.0 `[Substancialmente concluído]`
*Correções pontuais de robustez e coerência, agrupadas. Cada uma pequena; juntas,
fecharam a classe de inconsistências achada na auditoria código-vs-código. Ordem
executada: docs, Ring 0, camada Lua, auditor por último (validou que tudo fechou).*

1. **Docs sync** `[Done]` — README, ARCHITECTURE, `Build_and_Testing.md`, I1
   `astype("bool")` em CONTRACT.md + API_INDEX. Números frágeis eliminados (vivem
   em COVERAGE.md/MANIFEST/build.sh). COW.md sincronizado (datetime na tabela de
   tipos + gatilhos de detach). **Pendente residual:** reescrever exemplos de
   README/API_INDEX para a forma OFICIAL `smaug.Series({...})` (hoje usam
   `Series.from_table(...)`, que é infraestrutura) — baixo risco, doc.
2. **Ring 0** `[Done]` — `rank` i64 ordena por int64 direto (precisão >2^53);
   D1 `strdup` guard no `make_error`; D2 assimetria `append`/`set` documentada
   como deliberada (não unificada — set sinaliza por quê, append só OOM).
3. **Camada Lua** `[Done]` — `init.lua`: `smaug.Series({...})` é a forma oficial,
   `from_array` disponível, `from_table` removido do top-level (vivo como
   infraestrutura). `dt_view` exposto no descritor (+ teste Lua de detach; fecha as
   três pontas com COW.md). `view` em dtype sem suporte (string/bool) → erro
   orientado, não `nil`-call cru. linha `_types.lua` → `I64_MIN` (elimina literal
   e armadilha latente).
4. **Auditor** `[Done]` — eixo 10 do parity agora cruza header C ↔ descritor DTYPES
   para funções de dois-lados (`view`/`take`/`filter`): marca 🟥 quando o C tem mas
   o descritor não expõe, salvo exceção registrada. Validado por prova de fogo
   (removido `dt_view` → 🟥; restaurado → 🟩). Reporta sem travar build.

**Achados de tooling resolvidos no caminho** (mesma natureza dos da Fase 5 —
ferramenta silenciosamente furada): (a) `test_dt.lua` tinha três preâmbulos
concatenados com `local n_ok` redeclarado; o print final contava só o último
segmento — reportava 65 de 262 checks reais (os 197 já existiam e rodavam, só não
eram contados). Unificado num escopo único. (b) Exceção `view/string` no
`exceptions.txt` usava nome longo, mas o eixo 10 gera a chave com nome curto
(`view/str`) — a exceção nunca casava. Corrigida.

### Débitos técnicos registrados (não-agendados)
*Rastreados, sem bloquear a v1.0. O que está agendado vive no Bloco I, não aqui.*

| # | Local | Descrição | Severidade |
|---|---|---|---|
| D4 | Categorical | chave de hash via `tostring` (uniforme; sem bug observado) | Cosmético |
| I3 | `smaug_ops_str.c` | `g_sort_series` global (vs contexto por parâmetro do `multi_argsort`). Single-thread: sem bug; inconsistência arquitetural | Baixa |
| I4 | `get_value` f64/i64 (`_types.lua`) | passa `nil` como status; datetime checa. Sem bug (sempre após `check_index`); assimetria | Baixa |
| — | Rolling DataSet (`_stat.lua`) | reimplementa rolling em Lua O(N×W), duplica o caminho C da Series, só sum/mean/min/max. Funciona; débito de duplicação + performance | Baixa |

*Resolvido nesta sessão: I2 (guard de tipo nos `cmp_*` de datetime, alinhado com
f64/i64/string).*


### Fase 6 — Spike: FFI loader instalável `[Planned]` *(pode ser puxado para antes)*
- `ffi_loader` descobre a `.so`/`.dll`/`.dylib` num layout *instalado* (não só
  `./build/` ou `SMAUG_LIB`); resolve os três sufixos por plataforma em runtime.
- Teste de fogo: carregar de diretório de instalação simulado, máquina sem toolchain.
- Cadeia de fallback (env var → caminho do rock → relativo ao módulo).

### Fase 7 — Documentação de API (pré-release) `[Planned]`
- Docstrings nos métodos públicos de `Series` e `DataSet`.
- Revisar API_INDEX, API_Reference, ARCHITECTURE, COW, CONTRACT contra o estado
  pós-reorganização. README final.
- Registrar decisões conscientes (string view/COW, dtypes Tier 3, boolean indexing
  diferido, Tier D).

### Fase 8 — Distribuição e empacotamento `[Planned]`
*"O usuário não compila." Decisão de distribuição é fundação.*
- **Decisão de distribuição:** rocks binários por plataforma OU GitHub releases com
  binários OU rock que compila na instalação (viola "não compilar" — provável
  descarte). Critério, não default.
- Pipeline de build de binários: Linux x64, Windows x64, macOS (decidir se entra na v1.0).
- Empacotamento: `.so`/`.dll`/`.dylib` + árvore `lua/` + versão.
- `smaug-1.0.0-1.rockspec` (se LuaRocks); integrar o loader da Fase 6.
- **Teste de fogo:** `luarocks install smaug` em máquina limpa, sem toolchain.
- Publicar; verificar que o empacotamento não fecha porta para ecossistema
  multi-pacote futuro (`smaug` + `smaug-ml`?).

### Fase 9 — Onboarding e lançamento público `[Planned]`
- **Installation guide:** caminho LuaRocks (uma linha) + instalação manual (binário
  + path) como fallback.
- Quickstart: do `require("smaug")` ao primeiro DataSet em ~10 linhas.
- Requisitos de plataforma e versão de LuaJIT documentados; troubleshooting do FFI.
- Site / blog / plano de divulgação.

### Fase 10 — Release v1.0.0 (marco) `[Planned]`
- `build.sh --all` verde + `make valgrind` clean (Fedora) · `windows_build.ps1`
  verde (Windows) · `luarocks install` validado em máquina limpa.
- Entrada CHANGELOG v1.0.0 · `git tag v1.0.0` · publicação e anúncio.

---

## PARTE II — Pós-v1.0: trilhas paralelas

*Não é fila. Frentes que compartilham o núcleo (Anel 0–2) e avançam conforme
demanda. Cada item vira seu mini-roadmap quando começar. Nada aqui antes da Fase 10.
Rege o Princípio de governança no topo.*

### Trilha Analítica — `Series → DataSet → Matrix → Tensor → ML`
*A linha matemática. Porta: buffer contíguo (G.6).*
- **Anel 6 — Matrix** `[Concept]`: layout 2D denso sobre buffer contíguo; álgebra
  linear básica.
- **Anel 7 — Tensor** `[Concept]`: N-dimensional; broadcasting axis-aware.
- **Anel 8 — ML** `[Concept]`: pipeline de preparação (imputação, encoding,
  normalização) reusando primitivas do Anel 0; modelos consomem schema do Anel 5
  (**ponto de encontro das trilhas**).

### Trilha de Projeto — `I/O → Persistence → Models`
*A linha de construção de aplicações. Portas: G.7, G.8, G.9.*
- **Anel 3 estendido — Driver de banco** `[Planned]` (depende de driver externo → v1.5):
  - `smaug.connect(...)` — ciclo de vida de conexão (connect/close, vazamento, GC).
  - `db:query(sql, params)` → DataSet · `db:execute(sql, params)` → linhas afetadas.
  - `db:begin()` / `commit()` / `rollback()` — repassados ao banco.
  - **Bindings obrigatórios** (`?`/`$1`) — segurança contra injection, não-opcional.
  - Conversão defensiva tipo-do-banco → dtype-Smaug (consome G.7/G.9).
  - Usuário escreve SQL, Smaug transporta. Não gera, não traduz. `write_table` /
    query-builder: **fora de escopo**.
- **Anel 4 — Persistência / Serialização** `[Concept]` (reusa fundação atual; candidato cedo):
  - Formato `.smg`: header (magic, versão, schema) + buffers por coluna + máscara
    de nulos. `df:save(...)` / `smaug.load(...)`. Snapshots.
  - Endianness/portabilidade (ARM↔x64); versionamento do formato; categorical
    (levels) e datetime (epoch_ms).
  - Reader defensivo: truncado/corrompido/versão futura → erro claro, nunca crash.
- **Anel 5 — Models** `[Concept]` (ring próprio; NÃO é ORM relacional, NÃO é persistência):
  - `smaug.Model("Pedido", {id="int64", valor="float64", uf="string"})` — schema nomeado.
  - Validação, constraints, defaults, documentação do dado.
  - CRUD sobre DataSet **em memória**; persistência via Anel 4.
  - Sem transação/índice/concorrência — quem precisa disso usa SQLite via driver.
  - **Diretriz de design (forma, não cronograma):** Models não deve ser um catálogo
    de tipos — isso só duplicaria o que o DataSet já infere. O valor está no schema
    como *contrato executável* (`nullable`, `unique`, `enum`, `default`, constraints).
    Esse é o critério que separa um Anel 5 que agrega de um que é redundante. Decisão
    de forma; não antecipa a implementação nem altera a fila pré-v1.0.

### Features futuras (não são dívida; v1.5+)
*Adicionam capacidade. Entram quando houver demanda.*
- **Dtypes Tier 3:** float32, int32/16/8 (só se caso real justificar — ML é candidato).
- **`.str` Tier D:** regex (`extract`/`findall`/`match`/`fullmatch`), normalização
  Unicode-aware (depende de G.1).
- **I/O v1.5:** NDJSON (bloqueado por schema), Excel `.xlsx`, Parquet/Arrow.
- **Engine:** lazy execution, predicate/projection pushdown, stable sort (timsort).
- **DataSet:** `query`/`eval`, `cross_join`/join por expressão, boolean indexing
  `df[df.cidade == "SP"]`.
- **Temporal/rolling:** `expanding.*` adicionais, `resample`, `interpolate`.
- **Engenharia de dados:** schema formal e lineage.
- **Runtime:** `sum(min_count)` (semântica decidida, implementação pendente),
  sistema de warnings unificado (overflow i64, NaN).
- **String view/COW:** buffer-of-bytes + offset rebasing (hoje string usa cópia direta).
- **Build:** resolver bloco CMake desatualizado / decisão Lua 5.4.

---

## FRONTEIRAS ENCERRADAS — contrato contra a erosão

*Esta seção é um contrato, não um apêndice. Cada item foi uma batalha que
escolhemos não lutar — e a maior parte da complexidade histórica do pandas nasceu
de não ter essa lista. Reabrir qualquer item exige **motivo novo e explícito,
registrado** — nunca "parece pequeno".*

*A erosão vem de dois vetores: de fora pra dentro (o usuário que pede "só um
reindex...") e de dentro pra fora (o desenvolvedor que racionaliza "já que estou
fazendo broadcasting no Tensor, trago um pouco pro Ring 1"). O segundo é o mais
perigoso, porque se disfarça de consolidação.*

### Grupo 1 — Fronteiras de princípio (permanentes)
*Dizem respeito ao que o Smaug **é**. Reabrir muda a natureza do produto.*
- **Sem index nomeado.** Posição 1-based é o índice; datas são colunas datetime
  explícitas. Fora *permanentemente*, e com elas: `loc`/`iloc`-por-label/`reindex`/
  `align`/`set_index`/`reset_index`/`MultiIndex`/`xs`/`swaplevel`/`droplevel`/
  `reorder_levels`, e as temporais dependentes de index (`at_time`/`between_time`/
  `asof`/`asfreq`/`resample`/`to_period`/`to_timestamp`/`tz_convert`/`tz_localize`).
  *É a Fronteira mais importante da lista* — a coexistência posição+label+alinhamento
  é a raiz da complexidade do pandas.
- **Sem plotting.** `.plot`/`.hist`/`.boxplot`. Plot é interface; Smaug é motor.
- **Operadores reversos** (`radd`/`rsub`/…). Solução pandas pra limitação do Python;
  o metatable Lua já cobre `1 + s` e `s + 1` simetricamente.
- **Broadcasting no Ring 1.** Escalar cobre o caso de Series; broadcasting axis-aware
  pertence a Matrix/Tensor. *Atenção ao vetor de erosão interno na Trilha Analítica.*
- **`pipe`/`combine`/`update`/`squeeze`/`to_frame`.** Lua tem `:method()` encadeado;
  a fronteira Series↔DataSet já é limpa.
- **Framework de estrutura de projeto** ("Smaug entende `/project /models /reports`").
  É outro projeto que *importa* o Smaug.
- **ORM relacional** (objeto↔banco estilo SQLAlchemy). Responsabilidade do SQLite via driver.
- **Query builder / tradução de operações → SQL.** Custo altíssimo, valor baixo.
  O usuário escreve o SQL.
- **I/O de apresentação ou de outro ecossistema:** `to_pickle`/`to_hdf`/`to_xarray`/
  `to_stata`/`to_clipboard`/`to_latex`/`to_orc`/`to_html`/`style`/`__dataframe__`.

### Grupo 2 — Fronteiras de momento (reavaliar com caso real)
*Certas hoje pela ausência de caso real. Não são princípio — são "ainda não".*
- **Dtypes Tier 3 (float32, int32/16/8).** Os 6 dtypes cobrem o caso tabular. **Mas:**
  quando ML entrar, `float32` deixa de ser exótico e vira concreto. Linguagem:
  *"fora enquanto não houver caso real; ML provavelmente é esse caso para float32"* —
  não "descartado permanentemente".
- **`categorical` como Lua puro** (sem backend C). Decisão para v1.0. Marcar como
  *"implementação atual"*, não princípio: se houver datasets grandes e *profiling
  mostrar gargalo real*, um backend C pode valer.

### Grupo 3 — Fronteiras a observar
*Fora do escopo atual, mas não "nunca".*
- **feather / Arrow como formato de I/O.** Diferente de pickle/stata/html: é o
  formato de interop analítico moderno. Reavaliar como **I/O (Anel 3)** se houver
  demanda. **Trava de escopo:** vale só para Arrow-como-arquivo. **Arrow como
  representação interna de memória permanece fora** — seria decisão de fundação do
  tamanho de um Bloco G, não uma adição de I/O.
