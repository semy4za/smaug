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
sólido — não o contrário. A partir do Anel 3, o crescimento segue **duas trilhas
paralelas** (Projeto: Persistência→Models; Analítica: Matrix→Tensor→ML). Ver
`ARCHITECTURE.md` para o modelo completo (10 anéis, duas trilhas), princípios,
diagrama, regra de decisão e régua de versões.

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

### Fase 1 — Inventário arquitetural `[Planned]`
*Leitura, não escrita. Produz o mapa que alimenta o Bloco G.*
- Mapear `series.lua` e `dataset.lua` por blocos de responsabilidade (linhas, eixo).
- Mapear accessors (`.str`, `.dt`, `.cat`) e `CategoricalSeries`.
- Três dimensões por bloco: (A) responsabilidade certa Lua ou C? (B) coeso ou
  arquivo-deus? (C) fecha alguma porta de Ring/Trilha futura? (resposta por **negação**).
- Mapa de acoplamento por upvalue (`DTYPES`, `methods`, `NA`, `str_map`, `bool_map`,
  `check_index`, …).
- Marcar candidatos a primitiva Ring 0 (loop denso + aritmética mecânica).
- Entregável: documento de inventário, sem alterar código.

### Fase 2 — Bloco G: decisões de fundação `[Planned]`
*Consome o inventário. Decide, não implementa. Cada item: critério explícito
(contrato OU performance medida OU porta-de-fundação). Esperado para G.6–G.9:
majoritariamente "porta aberta, registrar".*
- **G.1 — UTF-8 / strings:** byte-oriented permanece ou vira codepoint-aware?
  Afeta `.str` inteiro. **Âncora concreta:** decide o que acontece com `"caf\u00e9"`
  no parser JSON — hoje vira `caf?` (degradação silenciosa). A decisão define se a
  implementação (Fase 5) vai *decodificar* `\uXXXX` para UTF-8 ou *rejeitar* com
  erro claro. Invariante: sair da degradação silenciosa antes da v1.0.
- **G.2 — Datetime:** confirmar epoch_ms int64 como definitivo; listar helpers de
  calendário candidatos a C; decidir a simplificação da semana ISO
  (`smaug_datetime.c:494` retorna 53 quando pertence ao ano anterior).
- **G.3 — Boundary audit:** GroupBy, Join, Rank, Unique, Factorize, Rolling — "se
  começasse hoje, Lua ou C?".
- **G.4 — Engine candidates (Ring 0):** lista final de primitivas que descem
  (`multi_argsort`, `group_runs`, `factorize`, `rank`, helpers UTF-8/datetime).
- **G.5 — Lições do Bloco F:** restrições de linguagem (`repeat`→`rep_each`), APIs
  desconfortáveis, decisões boas.
- **G.6 — Buffer/matriz:** o Ring 0 expõe (ou pode expor sem quebra) ponteiro de
  buffer contíguo? (porta da Trilha Analítica — Matrix/Tensor).
- **G.7 — Construção defensiva de DataSet:** o caminho de construção comporta fonte
  externa não-confiável (banco, API, driver, formato binário) com coerção de tipos,
  sem reescrita? (porta da Trilha de Projeto).
- **G.8 — Persistência e Model Layer:** dtypes, schema e metadata atuais permitem
  construir Persistence (Anel 4) e Models (Anel 5) por cima sem alterar Series/DataSet?
- **G.9 — Conectividade futura** (mesmo nível de importância de G.6): DataSet
  construível de fonte externa? dtypes comportam mapeamento SQL? datetime epoch_ms
  comporta drivers? categorical faz roundtrip? Verificação barata agora, caríssima
  depois.
- Entregável: documento de decisões do Bloco G.

### Fase 3 — Migração de primitivas para Ring 0 `[Planned]`
*Só o que o Bloco G decidiu. Uma por vez, validar antes da próxima. Vem antes do
split para não fatiar duas vezes.*
- Por primitiva aprovada: implementar em C com guards → teste C dedicado (+allocfail
  se aloca) → reescrever o consumidor Lua → suíte Lua permanece verde → Valgrind +
  cobertura.
- Atualizar paridade (eixo C↔Lua mirror) se aplicável. Cada migração: CHANGELOG.

### Fase 4 — Reorganização estrutural (split dos arquivos-deus) `[Planned]`
*Guiada pelo formato final que a Fase 3 deixou. Comportamento idêntico, zero
mudança de API.*
- Decidir mecanismo de cruzamento de upvalue (`core/internal` exporta helpers vs
  setup por parâmetro).
- Extrair accessors (mais seguros primeiro): `.str`, `.dt`, `.cat`/`CategoricalSeries`.
- Extrair blocos coesos de Series (estatística, predicados, duplicatas, rolling).
- Extrair orquestração de DataSet (groupby, join, reshape).
- Reorganizar testes espelhando a estrutura (`tests/series/`, `tests/dataset/`, …).
- Rede de segurança: suítes verdes a cada extração; nunca misturar "mover" com "mudar".
- Atualizar as três fontes de build e o Eixo 12.

### Fase 5 — Hardening global `[In progress]`
*Estrutura congelada; cada teste mira o lugar definitivo. Esta fase IMPLEMENTA
decisões já tomadas (não delibera contrato).*
- Medição de cobertura no Fedora (gcov autoritativo) → `COVERAGE.md` real.
- **Fechar cobertura dos parsers** (números reais): `smaug_datetime.c` 70.33% ·
  `smaug_json.c` 72.27% · `smaug_csv.c` 85.13% → ≥95% branch-alvo.
- `test_allocfail` estendido à camada de ops (Frente B: ~33 branches em
  f64/i64/bool/str/ops_str + ~25 residuais) e aos cleanup paths de OOM dos parsers.
- **Implementar a decisão de G.1 sobre `\uXXXX`** (decodificar OU rejeitar). Sair
  da degradação silenciosa. **Bloqueia release.**
- Property-based tests adicionais; avaliar fuzzing dos parsers (lacuna registrada).
- Valgrind clean em todos os binários. `COVERAGE.md` + `MANIFEST.txt` regenerados.

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
