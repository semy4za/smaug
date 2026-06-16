# Changelog — Smaug

Registro de o que mudou e por que, em ordem cronológica reversa.
Uma entrada por sessão de trabalho. Foco no que não é óbvio pelo diff:
decisões, achados, motivações.

---

## 2026-06-16 — Fase 3 Grupos A+B (Ring 0) + G.1 UTF-8 JSON

Início da Fase 3: migração de primitivas Lua puro para Ring 0 (C), guiada
pelo Bloco G. Duas frentes paralelas nesta sessão: G.1 (bloqueante de release)
e Grupos A+B do inventário de primitivas.

### G.1 — Decodificação UTF-8 no reader JSON

Eliminada a degradação silenciosa `\uXXXX → '?'` que existia em
`smaug_json.c`. Implementação completa em `read_json_string`:

- `read_hex4`: lê 4 dígitos hex → codepoint; retorna -1 se hex inválido.
- `encode_utf8`: codepoint → 1–4 bytes UTF-8 (cobre U+0000–U+10FFFF).
- BMP (U+0000–U+FFFF): decodificado diretamente.
- Surrogate pairs (`\uD800–\uDBFF` + `\uDC00–\uDFFF`): montados em
  codepoint suplementar (U+10000–U+10FFFF) e codificados em 4 bytes UTF-8.
- Surrogate isolado ou hex inválido → `TOK_ERROR` → `make_error` com
  mensagem clara. Nunca silencioso.

`.str` permanece byte-oriented — contrato inalterado. `str:len()` retorna
bytes, não codepoints. `test_io_c`: 174 → 190 checks (+16, 8 casos unicode).

**Motivação:** `json.dumps` Python com `ensure_ascii=True` (default) serializa
qualquer não-ASCII como `\uXXXX`. Dados brasileiros reais (nomes, cidades com
acento) produzem escapes rotineiramente. O `'?'` silencioso era bug de
integridade indetectável em produção.

### Grupo A — 10 primitivas O(N) para Ring 0

Migradas de Lua puro para C em `smaug_ops_f64.c` e `smaug_ops_i64.c`,
declaradas em `smaug_numeric.h`, registradas no `DTYPES` de `series.lua`
e no `ffi_loader.lua`:

`cumsum`, `cumprod`, `cummin`, `cummax`, `diff`, `shift`, `ffill`, `bfill`,
`argmin`, `argmax` — para `smaug_series_f64_t` e `smaug_series_i64_t`.

**Contratos relevantes:**
- `cummin`/`cummax`: nulos não propagam para frente (posição nula fica nula,
  mas as seguintes continuam recebendo o acumulado). Contrato mais útil que o
  `cumsum`/`cumprod` onde null contamina o restante.
- `diff` datetime: permanece Lua (usa `smaug_dt_diff_ms`).
- `shift` negativo (periods < 0): permanece Lua (C usa `size_t`).
- `argmin`/`argmax`: retornam `SIZE_MAX` se série vazia ou toda-null; Lua
  converte `SIZE_MAX → nil` e ajusta 0-based → 1-based.
- `cummin`/`cummax`/`ffill`/`bfill` datetime: fallback Lua via nil-check em
  `self._d.xxx`.

Regra de migração aplicada: todas as funções C registradas nos descritores
`DTYPES` (`float64` e `int64`) e acessadas via `self._d.fn(self._c)` — nunca
`C.smaug_f64_fn` diretamente no corpo do método.

### Grupo B — sorted_nonnull e rank para Ring 0

Migradas de Lua puro para C:

- `smaug_f64_sorted_nonnull` / `smaug_i64_sorted_nonnull`: coleta não-nulos
  em `double*` / `int64_t*` ordenado crescente. Série toda-null retorna
  `NULL` com `*out_n = 0` (não é erro). Caller libera com `smaug_free`.
- `smaug_f64_rank` / `smaug_i64_rank`: rank 1-based com 4 methods
  (0=average, 1=min, 2=max, 3=first). Nulos → `NAN` no resultado.
  Caller libera com `smaug_free`.

Comparadores (`cmp_double`, `cmp_rank_pair`, `cmp_i64`, `cmp_i64_rank_pair`)
definidos como `static` no escopo do arquivo — C11 padrão, sem extensões GCC.

**Consumidores Lua reescritos:** `median`, `quantile`, `nlargest`, `nsmallest`,
`skew`, `kurtosis`, `mad`, `sem`, `rank`, `pct_rank` — todos delegam para C
via `c_sorted_nonnull` (helper Lua que chama a primitiva C e devolve
`ffi.new double[]` uniforme). `datetime` e `mad` (segundo passe sobre desvios)
permanecem com fallback Lua.

Grupo B não usa `DTYPES`: as funções retornam ponteiros brutos (`double*`,
`int64_t*`), não `smaug_series_*_t` — são primitivas de buffer chamadas
diretamente pelos métodos, não via descritor de dtype.

### Testes

`test_ops_window.c` — novo, cobre Grupos A e B: 150 checks.
ASan+UBSan limpos. `test_allocfail` estável em 1158 verificações.

### Próximo

Fase 3 Grupo C: `multi_argsort` composto (DataSet) e `SeriesRolling:_agg`,
após medição de performance no Windows.

---



Último sub-bloco do enriquecimento dos núcleos. Com ele, **o Bloco F inteiro
(F.1–F.6) está fechado**.

### Adicionado

- **Series:** `duplicated([keep])` (keep ∈ {first,last,none}; null conta como
  valor — dois nulos são duplicatas entre si, semântica pandas);
  `drop_duplicates([keep])`; `combine_first(other)` (preenche nulls de self com
  other); `searchsorted(value, [side])` (busca binária, exige série ordenada
  crescente verificada via `is_monotonic_increasing`; side ∈ {left,right});
  `rep_each(n)` (repete cada elemento n vezes; n escalar ≥0 ou `Series<int64>`).
- **DataSet:** `duplicated([subset], [keep])` (subset = nome/lista/nil) e
  `drop_duplicates([subset], [keep])` (multi-coluna).

**Decisões de contrato:**
- O nome do método de repetição é `rep_each`, não `repeat`: `repeat` é palavra
  reservada em Lua e impediria tanto a definição (`function methods.repeat`)
  quanto a chamada (`s:repeat(n)`) — ambas falham no parse. `rep_each` deixa a
  intenção explícita (repete cada elemento) e segue o espírito do `:rep` já
  existente no `.str`.
- `duplicated` reaproveita o mesmo esquema de chave de `unique`/`nunique`
  (`type:tostring`, mais sentinela própria para null), garantindo semântica
  consistente de igualdade em todo o frontend.
- `combine_first` exige dtype e tamanho iguais — não faz coerção implícita.
- `searchsorted` exige ordenação crescente e rejeita séries com nulos (não há
  ordem definida com null), com erro claro em vez de resultado silenciosamente
  errado.

`test_duplicates.lua` (74 checks).

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `Series.methods` 90→95, `DataSet.methods`
46→48. Roadmap marca F.6 e o **Bloco F** inteiro como `[Done]`.

---

## 2026-06-15 — Bloco F.5 (acesso e ergonomia)

### Adicionado

- **Series:** `at`/`iat` — acesso escalar posicional. Implementado via proxy no
  `__index` que suporta tanto indexação (`s.at[i]`) quanto chamada (`s.at(i)`),
  cobrindo a sintaxe pandas-like e a forma idiomática Lua. Em Series 1-D, `at` e
  `iat` são equivalentes (índice = posição). Ambos delegam a `get`, herdando o
  guard de bounds.
- **DataSet:** `at(i, col)` (célula por nome) e `iat(i, ci)` (célula por índice
  posicional de coluna); `insert(loc, name, series)` (insere em posição 1-based,
  desloca as seguintes); `to_dict([orient])` (`"columns"` default ou `"records"`);
  `from_dict(t, [orient])` (construtor com inferência de dtype por coluna);
  `to_markdown()` (GitHub-flavored, sem o limite de 10 linhas do `__tostring`);
  `to_string([opts])` (texto plano com `max_rows` opcional).

**Decisões de contrato:**
- `at`/`iat` no DataSet são métodos chamáveis (`df:at(i, col)`), não indexers de
  duplo subscrito — Lua não tem `tbl[i, col]`. A forma de chamada é a tradução
  fiel e sem ambiguidade.
- `from_dict` orient `"columns"`: ordem das colunas é indefinida em Lua (chaves
  de tabela), então aceita `t._order` (lista de nomes) para ordem determinística;
  sem ele, ordena alfabeticamente. Orient `"records"`: colunas pela união das
  chaves (1ª aparição); chave ausente em um registro → NA naquela linha.
- `from_dict` infere dtype por coluna: string domina; senão bool puro; senão
  float se houver não-inteiro; senão int64; coluna toda-nula → string.

`test_access.lua` (54 checks), incluindo roundtrip `to_dict→from_dict`, bordas de
`insert` e erros de acesso.

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `DataSet.methods` 40→46 (`from_dict` é
função de classe, documentada à parte como `from_columns`). Roadmap marca F.5
`[Done]`.

---

## 2026-06-15 — Portabilidade de I/O + Blocos F.3 e F.4 + sync de builds

### Corrigido — testes de I/O com path hardcoded (Windows)

`windows_build.ps1` falhou em `test_io_c`, `test_io` e `test_io_real`: os testes
escreviam em `/tmp/...`, que não existe no Windows/UCRT64. Não era regressão da
biblioteca — `to_csv`/`smaug_write_csv` reportaram fielmente a falha de escrita.
Introduzido helper `tmp_path` (um em C, um em Lua) que resolve o diretório
temporário via `TMPDIR`→`TMP`→`TEMP`→`/tmp`, montando o caminho com separador
`/` (aceito pela CRT do Windows e pelo POSIX). Detalhe que exigiu cuidado:
`os.getenv` devolve `""` (truthy em Lua), não `nil`, para variável vazia — o
helper trata string vazia como ausente, espelhando o `!dir || !*dir` do C.
Validado em três cenários: fallback `/tmp`, `TEMP` setado, e variável vazia.

### Adicionado — Bloco F.3: accessor `.dt` estendido

Toda a lógica de calendário derivada vive no Ring 1 (Lua), reaproveitando as
primitivas C (`year`/`month`/`day`/.../`from_parts`/`truncate`/`add_ms`). Nenhuma
mudança no Ring 0 — funções de calendário derivadas são responsabilidade do
frontend.

- **Predicados** (→ `Series<bool>`): `is_month_start`/`is_month_end`,
  `is_quarter_start`/`is_quarter_end`, `is_year_start`/`is_year_end`,
  `is_leap_year` (regra gregoriana completa, incluindo a exceção secular ÷400).
- **Atributos:** `days_in_month` (→ int64), `month_name`/`day_name` (inglês fixo).
- **Período:** `round(unit)`/`ceil(unit)` complementam o `truncate` (= floor) já
  existente. `ceil` retorna o próprio valor quando já alinhado; `round` usa
  half-up no empate (consistente com pandas). `next_period` usa `from_parts`
  para unidades de calendário (M/Q/Y, comprimento variável) e `add_ms` para as
  de comprimento fixo.
- **`normalize()`:** zera a hora (= `truncate("D")`), nome herdado do pandas.
- **`strftime(fmt)`:** tokens `%Y %y %m %d %H %M %S %I %p %j %B %b %A %a %%`;
  token desconhecido é mantido literal (com o `%`).

`test_dt_extended.lua` (65 checks), com casos seculares (1900 não-bissexto, 2000
bissexto), empates de round e meia-noite/meio-dia para `%I`/`%p`.

### Adicionado — Bloco F.4: accessor `.str` Tier C

ASCII puro, sem regex, sem Unicode — consistente com Tier A/B. Reaproveita os
helpers `str_map` (→ Series<string>) e `bool_map` (→ Series<bool>) existentes.

- **count(sub):** ocorrências literais não-sobrepostas → int64. `sub` vazio é
  erro (contagem indefinida / risco de loop).
- **Predicados** (→ Series<bool>): `isalnum`/`isalpha`/`isdigit`/`isspace`/
  `islower`/`isupper`. Semântica Python: string vazia → false; `islower`/
  `isupper` exigem ao menos uma letra e nenhuma da caixa oposta.
- **removeprefix/removesuffix:** remoção literal de afixo, no máximo uma vez,
  idempotente quando não casa.
- **capitalize/title/swapcase:** caixas ASCII. `title` trata qualquer não-letra
  como separador de palavra.
- **join(sep):** atalho de `:cat` (mesma saída: string Lua única). Mantido pelo
  nome familiar de pandas/Python.

`test_str_tier_c.lua` (61 checks), incluindo vazias, nulos, não-ASCII em `title`
(não quebra), e contagem não-sobreposta.

### Sincronização das três fontes de build

`windows_build.ps1` estava atrás em duas dimensões: faltava `test_datetime_c`
(C) e seis suítes Lua (`test_datetime`, `test_categorical`, `test_completeness`,
`test_dt_extended`, `test_stats`, `test_predicates`). Alinhado ao Makefile
canônico — as três fontes (`Makefile`, `build.sh`, `windows_build.ps1`) agora
rodam o conjunto idêntico, verificado por diff: 9 binários C plain + allocfail +
stress, e 26 suítes Lua.

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `SeriesDT:*` 19→33, `StrProxy:*` 15→28.
Roadmap marca F.3 e F.4 `[Done]`.

---

## 2026-06-15 — Completude de paridade + Blocos F.1 e F.2

Sessão de fechamento de lacunas antes de avançar o enriquecimento dos núcleos.

### Corrigido — checkup de build e oráculos de teste

Auditoria do `Makefile` e do `build.sh` expôs que `make test`/`make valgrind`
não exercitavam `test_io_c` nem `test_datetime_c` (375 checks C fora do CI), e
que `LUA_TESTS` cobria 8 de 21 suítes (362k+ checks ignorados pelo `make`). As
duas listas foram completadas e sincronizadas entre `Makefile` e `build.sh`.
Removido um warning `-Wunused-variable` em `test_io_c.c:315` (`s` capturada e
nunca usada). Build agora zero-warning também nos binários de teste.

### Adicionado — completude de métodos em datetime e categorical

Auditoria do `PARITY_REPORT.md` (Eixo 1) apontou 17 ausências sem registro.
Decisão: nesta fase de completude, **implementar**, não registrar exceção.

- **datetime (7):** `argmin`/`argmax`/`cummin`/`cummax`/`median`/`quantile`
  passam a aceitar datetime — operam sobre epoch_ms (já numérico), guard
  estendido. `diff` em datetime retorna `Series<int64>` (duração em ms, não
  timestamp — diferença de dois instantes é uma duração).
- **categorical (10):** `isna`/`notna` (aliases), `min`/`max` (lexicográfico
  sobre labels), `ffill`/`bfill` (opera ao nível de codes), `shift`, `map`
  (retorna Series do dtype inferido), `where`/`mask` (seleção condicional,
  retornam novo CategoricalSeries).

`test_completeness.lua` (93 checks) pina cada comportamento, incluindo nulos e
erros de bounds.

### Adicionado — Bloco F.1: pacote estatístico

- **Series:** `corr(other)` (Pearson ∈ [-1,1]), `cov(other)` (covariância
  amostral ÷ n-1), `autocorr([lag])` = `:corr(:shift(lag))`, `dot(other)`
  (produto interno), `pct_change([periods])`.
- **DataSet:** `corr()` / `cov()` retornam matriz N×N como DataSet (coluna
  identificadora `__index__` + uma coluna float64 por variável numérica;
  colunas não-numéricas ignoradas).

**Decisões de contrato:**
- `corr`/`cov` **pulam** pares onde qualquer operando é null (semântica pandas);
  menos de 2 pares válidos ou variância zero → NaN.
- `dot` **propaga** null (qualquer par com null → resultado null) — diferente de
  corr/cov, porque produto interno não tem semântica de "ignorar" sem mudar o
  significado do resultado.
- `pct_change` com divisor zero → null (não Inf), por previsibilidade.

`test_stats.lua` (60 checks) com valores de referência calculados à mão.

### Adicionado — Bloco F.2: pacote de predicados

- **Series:** `between(lo, hi, [inclusive])` (inclusive ∈ {both,left,right,
  neither}), `isin(values)`, `is_unique()`, `is_monotonic_increasing/
  decreasing([strict])`, `equals(other)` (igualdade estrutural com NaN==NaN),
  `compare(other)` (diferenças → DataSet `{i,self,other}`), `idxmin`/`idxmax`
  (aliases de argmin/argmax), `first_valid_index`/`last_valid_index`.
- **DataSet:** `equals(other)` (colunas+ordem+dtypes+valores), `compare(other)`
  (diferenças célula a célula → DataSet `{linha,coluna,self,other}`).

**Decisões de contrato:**
- `between`/`isin` propagam null (resultado null naquela posição).
- `is_monotonic_*`: qualquer null quebra a monotonicidade (sem ordem definida
  com o vizinho). Série vazia/de 1 elemento é monotônica (vacuamente).
- `equals`/`compare` tratam NaN como estruturalmente igual a NaN (diferente de
  IEEE 754) — a pergunta é "são a mesma série", não "são numericamente iguais".
- `compare` (Series) retorna só as posições que diferem; DataSet vazio se
  idênticas. `compare` (DataSet) normaliza `self`/`other` para string porque as
  colunas têm dtypes heterogêneos.

`test_predicates.lua` (78 checks).

### Docs

`API_INDEX.md` atualizado — Eixo 12 (sincronização docs↔código) de 88/97/60/77%
para **100% nas 7 categorias** (206 métodos documentados). Reduções e
comparações antes agrupadas em uma linha (`:sum/mean/...`) foram separadas em
entradas individuais para o checker detectar por nome exato. Roadmap marca F.1
como `[Done]`.

---

## 2026-06-14 — Decisão: enriquecimento dos núcleos entra na v1.0

Após auditoria comparativa contra a API pública do pandas (Series + DataFrame),
decisão arquitetural: a v1.0 não fecha com o mínimo viável. Fecha com cobertura
operacional ampla, mantendo zero dependências externas.

**6 pacotes adicionados ao Pré-1.0 (Bloco F):**
- F.1 — Estatístico (`corr`/`cov`/`autocorr`/`dot`/`pct_change`)
- F.2 — Predicados (`between`/`isin`/`is_unique`/`is_monotonic_*`/`equals`/`compare`/`idxmin`/`idxmax`/`first/last_valid_index`)
- F.3 — `.dt` estendido (`is_*_start/end`/`is_leap_year`/`days_in_month`/`round`/`ceil`/`strftime`/`normalize`/`month_name`/`day_name`)
- F.4 — `.str` Tier C parcial (`count`/`isalnum`/`isalpha`/etc/`removeprefix`/`removesuffix`/`capitalize`/`title`/`swapcase`/`join`) — sem regex, sem Unicode
- F.5 — Acesso e ergonomia (`at`/`iat`/`insert`/`to_dict`/`from_dict`/`to_markdown`/`to_string`)
- F.6 — Duplicatas e binárias (`duplicated`/`drop_duplicates`/`combine_first`/`searchsorted`/`repeat`)

**Decisões de não-fazer (permanentes, registradas em Roadmap.md):**
- Index nomeado e toda família dependente (`loc`/`MultiIndex`/`reindex`/`align`/
  `set_index`/`reset_index`/`xs`/`swaplevel`/`droplevel`/`at_time`/`between_time`/
  `asof`/`asfreq`/`resample`/`to_period`/`to_timestamp`/`tz_*`).
- Plotting (`.plot`/`.hist`/`.boxplot`).
- I/O exótico (`pickle`/`hdf`/`xarray`/`stata`/`clipboard`/`latex`/`orc`/`feather`/
  `html`/`style`/`__dataframe__`).
- Tipos extras (`sparse`/`list`/`struct`/`period`/`timedelta`/`interval`/`decimal`).
- Operadores reversos (`radd`/`rsub`/etc.) — não-issue em Lua.
- `pipe`/`combine`/`update`/`squeeze`/`to_frame`.

**Trade-off:** v1.0 atrasa em ~6 sessões. Aceito conscientemente porque
v1.0 com cobertura ampla muda a régua do projeto — quando alguém abrir o README,
vê paridade significativa com pandas no que importa, sem o ruído.

Roadmap.md tem a lista detalhada de cada pacote, justificativa de cada
decisão de não-fazer, e checklist atualizado.

---

## 2026-06-14 — Tier 2 dtypes + bugfix Valgrind dos parsers I/O

### Adicionado — datetime no frontend Lua

Backend C de `smaug_datetime.c` já estava pronto (epoch ms UTC, calendário
Gregoriano proléptico, 201 checks em `test_datetime_c`). Esta sessão fechou
a integração com o frontend:

- Descriptor `datetime` no `DTYPES` de `series.lua` (factory, set/get com
  string ISO 8601 ou epoch_ms, append, comparações, sort/filter/take).
- Accessor `.dt` com 19 métodos: 11 componentes calendário (`year`/`month`/
  `day`/`hour`/`minute`/`second`/`ms`/`weekday`/`yearday`/`quarter`/`week`),
  `format`, `truncate(unit)` para `s/m/h/D/W/M/Q/Y`, `diff([periods])` em
  milissegundos, `add_ms`/`add_days`/`add_hours`/`add_minutes`/`add_seconds`.
- Helpers públicos: `Series.dt_parse`, `Series.dt_format`, `Series.dt_from_parts`,
  `Series.datetime(size, name)`.
- `astype` estendido com 6 branches novos: `datetime ↔ string` (via ISO 8601),
  `datetime ↔ int64`, `datetime ↔ float64` (epoch_ms).
- `describe` estendido com branch `datetime` — retorna `{dtype, count, nulls, min, max}`
  onde min/max são strings ISO 8601 formatadas.
- `test_datetime.lua` (188 checks): factories, `.dt`, comparações, sort, filter,
  astype, integração DataSet (filter/sort_by/assign/select/head/dropna/describe).

### Adicionado — categorical (Lua puro)

`CategoricalSeries` implementado inteiramente em Lua usando dictionary encoding.
Decisão consciente de não criar C backend — o tipo é essencialmente um índice
+ tabela de strings, não justifica fragmentar o contrato C.

- Armazenamento: `_codes` (int 1-based; nil = null), `_levels` (lista ordenada
  por primeira aparição), `_level_map` (hash inverso).
- Factories: `Series.from_table(arr, "categorical")`, `Series.Categorical.from_codes(...)`.
- 31 métodos de instância (espelham `Series` onde cabe): acesso, append,
  clone/head/tail/take/filter/dropna/fillna, sort/argsort (lexicográfico),
  comparações (`eq`/`ne`/`lt`/`le`/`gt`/`ge`), `unique`/`nunique`/`value_counts`,
  `describe`, `astype` (para `string`, `int64`, `float64`), `to_table`.
- Accessor `.cat` com 6 métodos: `codes()` → `Series<int64>`, `levels()`,
  `rename_categories`, `set_categories`, `add_categories`, `remove_categories`.
- Integração total com DataSet: `add_column`, `update_column`, `assign`,
  `__newindex`, `__call` todos aceitam `CategoricalSeries`. Princípio
  "toda coluna aceita pelo DataSet funciona em toda a API do DataSet".
- `test_categorical.lua` (199 checks).

### Corrigido — leaks nos parsers I/O capturados pelo Valgrind

Após validar `datetime` + `categorical` no Fedora com `make valgrind`, o
Valgrind capturou ~762 bytes vazando em 79 blocos no `test_allocfail`. Stack
traces apontaram para `smaug_csv.c:227` (strdup de `col_names`) e
`smaug_json.c:267/273` (malloc/calloc após strdups).

**Bugs identificados:**
- Em ambos os parsers, quando `calloc(dtypes)` ou alocações subsequentes
  falhavam **depois** do loop de strdup de `col_names[c]`, o cleanup fazia
  `free(col_names)` (o array) mas não liberava as strings individuais.
- No CSV, o label `done:` (alcançado quando `smaug_X_create` falha no loop
  final) liberava `col_names` mas não os strdups dos índices ainda não
  transferidos para `t->columns[c].name`.
- No JSON, `oom_recs:` libera `recs` mas nem `col_names` nem `dtypes` eram
  visíveis no escopo do label.

**Estratégia comum:**
- Inicializar `col_names[c] = NULL` antes do loop de strdup; libertar
  parcialmente em caso de falha.
- Marcar transferência de ownership com `col_names[c] = NULL` ao atribuir
  ao `tbl->columns[c].name`. `free(NULL)` é seguro, o cleanup itera pelo
  array inteiro.
- No JSON, mover `col_names`/`dtypes` para o escopo da função (com `n_cols_io`)
  para serem visíveis no label de cleanup. No CSV, estender `done:` para
  liberar strdups não-transferidos.

Resultado: Valgrind 100% clean em todos os 9 binários no Fedora. `test_allocfail`
com 15330 allocs / 15330 frees, `test_stress` com 90751/90751.

### Corrigido — warning `-Wtype-limits` no test_allocfail

`t->nrows >= 0` onde `nrows` é `size_t` (unsigned) — sempre verdadeiro.
Substituído por `1` constante; o check útil (`!t || t->error`) permanece.

### Decisão — NDJSON adiado para pós-1.0

Tentativa de implementar NDJSON expôs limitação fundamental: o parser JSON C
infere dtypes por linha. Uma linha com `"a":null` infere `string`, conflitando
com outra linha com `"a":1` que infere `int64`. Sem schema global declarativo,
NDJSON é inerentemente frágil para dados com null. Decisão: adiar para o ciclo
do schema/ORM (v2.0). Registrado em `Roadmap.md`.

### Cobertura

Linha 95.99% (2248/2342), branch-alvo 88.12% (2270/2576, 90 exclusões).
Queda em relação a sessões anteriores (96.99% / 88.82%) é resultado dos
cleanup paths novos — código adicionado mas ainda não exercitado pelo
`test_allocfail`. Vai ser fechado no hardening global.

---

## 2026-06-14 · f66ba99 — Anel 3 completo + hardening I/O

### Adicionado — Anel 3: I/O CSV e JSON

Parsers próprios em C puro, zero dependências externas. Fronteira
`smaug_table_t` como contrato entre leitores e o frontend Lua — todo
leitor produz uma `smaug_table_t`, o frontend consome e monta um `DataSet`.
Adicionar novos formatos (Parquet, SQLite) é implementar um novo produtor
sem tocar no núcleo.

```lua
-- leitura com inferência automática de tipo
local ds = smaug.read_csv("pedidos.csv", {sep = ";"})
local ds = smaug.read_json("cotacoes.json")

-- escrita
ds:to_csv("saida.csv")
ds:to_json("saida.json", {pretty = true})

-- em memória (sem arquivo)
local buf = ds:to_csv_mem()
local ds2 = smaug.read_csv_mem(buf)
```

Inferência de tipo no CSV: cada coluna é testada em ordem `int64 → float64 → bool → string`.
Coluna mista sobe para o tipo mais abrangente. Células vazias e `NA`/`null`/`N/A`/`nan`/`NaN`/`NULL`
viram null. Separador, aspas e header configuráveis.

JSON suporta o formato array de records `[{...}, {...}]` com escape completo
(`\n`, `\t`, `\\`, `\"`, `\uXXXX`) e writer compacto/pretty. `NaN` → `null`
no JSON (sem representação JSON para NaN).

### Adicionado — test_io_c.c (174 checks)

Cobertura C direta dos parsers: CRLF, CR-only, sem newline final, TSV,
sem header, aspas RFC 4180, aspas escapadas, aspas não fechadas, newline
em campo, NA padrão e customizados, inferência de todos os tipos, linha curta,
linha com 20 colunas, campo longo > 32 bytes, writer com NaN/sep/quote/sem-header/arquivo,
JSON completo, roundtrips, erros de arquivo/path inválido.

### Adicionado — test_io_real.lua (55 checks) com dados reais

`tests/pedidos_digitados.csv`: 916 linhas, 15 colunas, separador `;`, vírgula
decimal, 5 empresas (DB10/DC10/DG10/DP10/DS10), 5 marcas de produto.
Valida leitura, groupby, filter, join e roundtrips sobre dados reais.

Fixtures de cotações: `cotacoes.csv`, `cotacoes.json`, `cotacoes_USD_BRL.json`,
`cotacoes_SHIB_BRL.json` — float64 de alta precisão e valores pequenos (SHIB: 0.00002492).

### Adicionado — allocfail nos parsers I/O (1098 → 1158 verificações)

9 funções de injeção de falha: `af_csv_read_mem`, `af_csv_read_quoted`,
`af_csv_read_many_rows`, `af_csv_write`, `af_json_read_mem`,
`af_json_read_many_records`, `af_json_read_long_string`, `af_json_write`,
`af_table_free_partial`. Toda falha de malloc em qualquer ponto dos parsers
resulta em retorno gracioso sem crash.

### Corrigido — dois bugs encontrados pelo Valgrind

`smaug_json.c`: `col_names` (array de ponteiros) não era liberado no caminho
de sucesso — 8 bytes por coluna vazavam.

`smaug_csv.c` + `smaug_json.c`: writers retornavam buffer sem terminador `\0`.
`strstr` e similares liam além do conteúdo válido. Corrigido: ambos os writers
adicionam `\0` ao final sem contar em `out_len`.

### Adicionado — COV-EXCL-BR nos parsers

66 exclusões totais (era 57). Guards de OOM/syscall inalcançáveis via API
pública nos parsers CSV e JSON documentados com justificativa técnica.

### Cobertura

Linha 97.95% (1909/1949). Branch-alvo 92.18% (1981/2149, 66 excluídos).

---

## 2026-06-12 · Ring 1 completo

### Adicionado — `df[mask]` indexação por BoolSeries

`DataSet.__index` passa a despachar para `filter` quando a chave é uma
`Series<bool>`. Açúcar sobre `:filter()` — sem semântica nova.

```lua
local ds = smaug.DataSet({
    {"idade", {17, 32, 25}, "int64"},
    {"nome",  {"Ana", "Bruno", "Carol"}, "string"},
})
local adultos = ds[ds.idade:gt(18)]
```

### Adicionado — `.str` Tier A completo

Accessor `.str` em `Series` do tipo string. 7 métodos + `replace`.
Null propaga; erro claro em dtype errado.

```lua
local ds = smaug.DataSet({{"cidade", {"  São Paulo  ", "rio", "MINAS"}, "string"}})
local normalizado = ds.cidade.str:strip():lower()
```

Métodos: `len` (→ int64), `lower`, `upper`, `strip`, `replace` (→ string),
`contains`, `startswith`, `endswith` (→ BoolSeries).

### Adicionado — comparações `ge`/`le`/`ne`

Para f64, i64 e string. Completam o conjunto `gt`/`lt`/`eq`/`ge`/`le`/`ne`.

### Adicionado — `Series:map(fn, dtype?)`

Aplica função Lua elemento a elemento. `nil` retornado → null. Dtype
inferido do primeiro retorno não-null; tipos mistos → erro com índice.

### Corrigido — `f64` div/0 → null (uniforme com i64)

`smaug_f64_div` e `smaug_f64_div_scalar` passam a produzir `null` quando
o divisor é zero. Comportamento agora uniforme entre f64 e i64.

### Decisão — Broadcasting rejeitado para Anel 1

Broadcasting de `Series(length=1)` não desbloqueia capacidades novas além
do escalar direto. Broadcasting real pertence ao `Tensor2D`/ML (Anel 5).
Removido da dívida técnica; registrado como decisão explícita.

---

## 2026-06-11 · 9807b46

### Corrigido — `test_string_ux()` órfã

30 checks de UX de string estavam escritos mas nunca executados — função
definida e não chamada. Qualquer máquina reportava 59 checks; o arquivo tinha 90.

### Corrigido — rodapé do COVERAGE.md incompleto

O gerador suprimia o segundo ramo de linhas com dois ramos excluídos.
Resultado: aritmética dizia 19 exclusões, rodapé listava 17. Fix: remove
o guard. O rodapé agora espelha a aritmética real.

---

## 2026-06-10 · f73c928

### Adicionado — BoolSeries como coluna de primeira classe

`DataSet` aceitava `BoolSeries` em `add_column`, mas `head`/`tail`/`filter`/
`describe`/`dropna`/`fillna`/`argsort` explodiam. Princípio adotado: toda coluna
aceita pelo DataSet deve funcionar em toda a API do DataSet, sem exceções ocultas.

Corrigido também um bug de precedência no `argsort` (comparador Lua com `and`/`or`
sem parênteses — resultado silenciosamente errado em certas ordenações).

### Adicionado — UX de string

- `fillna` dtype-aware: string aceita string, número aceita número.
- `describe` para string: count, nulls, unique, top, freq.
- `astype` string↔numérico com conversão tolerante por elemento:
  elementos inconversíveis viram null, nunca erro.

```lua
local s = Series.from_table({"1.5", "2.0", "abc", smaug.NA}, "string")
local f = s:astype("float64")
-- f:get(3) == nil  (null, não erro)
-- f:get(1) == 1.5
```

### Adicionado — API pública do DataSet

- `smaug.DataSet({{...}})` via `__call`.
- `Series.full(n, val)` para broadcast de escalares.
- `df["col"] = serie_ou_escalar` via `__newindex`.
- `DataSet.update_column`.
- `DataSet.methods` exposto para extensão por módulos externos (usado pelo I/O).

---

## 2026-05 · endurecimento Anel 0 (frentes A, B, C)

### Frente B — OOM nas ops

`test_allocfail` estendido para cobrir todas as ops aritméticas (f64/i64/bool/string).
579 → 767 → 1098 → 1158 verificações. Valgrind-clean.

### Milestone — branch-alvo 100% no núcleo (MC/DC completo)

1095/1095 ramos do núcleo cobertos. Jornada: 75.42% → 100.00%.
19 exclusões `COV-EXCL-BR` com justificativa auditável.

### Frente A — guards de input

O engine passou a não confiar no caller: toda fronteira pública do C valida
ponteiro/argumento/índice e comunica o resultado via `smaug_status_t`.

### Frente C — semântica fechada

- Propagação estrita de null: qualquer operando null → resultado null.
- Tabela-verdade Kleene completa para bool.

---

## 2026-04 · contrato defensivo do C + COW

### Copy-on-Write em views (f64/i64)

Views compartilham o buffer da série pai zero-copy até a primeira escrita.
Toda mutação materializa um buffer privado; a pai nunca é tocada.

### Contrato defensivo — `get` Shape 1

`f64_get`/`i64_get` passaram a retornar valor + escrever `smaug_status_t*`.
Eliminou a colisão entre índice inválido e valor legítimo.

---

## 2026-03 · fase string completa

### String como dtype de primeira classe

Percurso: esqueleto (struct offset-based, estilo Arrow) → backend C
(lifecycle, acesso, mutação, comparações, filter/take, sort/argsort) →
frontend Lua.

String vazia `""` distinta de NULL. Ordenação lexicográfica por bytes.

### `test_allocfail` estendido para string

10 helpers `af_str_*` cobrem cada ponto de alocação. Valgrind-clean.

---

## 2026-02 · endurecimento (property-based, cobertura, fillna)

### Property-based tests

24 invariantes × 3 seeds × ~400 casos = 360 862 checks.
Invariantes: clone independente, view compartilha memória, sort é permutação,
filter↔count_true, astype ida-volta, fillna remove null/preserva NaN, Kleene.

### `fillna`

`Series:fillna(value)` e `DataSet:fillna(value | {col=value})`.
Sem coerção. Preserva NaN. Original imutável.

### Contrato NaN≠null fixado

`NaN` deixou de virar null. `sort`/`argsort` (f64) recusam NaN além de null.

---

## 2026-01 · fases 1–4 (backend C, frontend Lua, DataSet, bool)

### DataSet

Coleção de Series alinhadas. CRUD de colunas com validação de comprimento
e nome único. `filter`/`sort_by`/`head`/`tail`/`iloc`/`take`/`sample`/`select`.

### Bool e lógica Kleene

`Series<bool>` com lógica de três valores. `Series:gt`/`lt`/`eq` → `Series<bool>`.

### Frontend Lua (Series)

Despacho por dtype via tabela de descritores. `ffi.gc` para limpeza automática.
Views read-only com `_parent` para impedir GC da série pai.

### Backend C (f64 + i64)

Lifecycle, getters/setters, append dinâmico, aritmética, reduções,
comparações, sort/argsort. Zero warnings (`-Wall -Wextra`).
