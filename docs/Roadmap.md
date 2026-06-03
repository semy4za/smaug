# Smaug — Roadmap e Design do Frontend

Este documento descreve o roadmap faseado e o design do frontend Lua e dos
módulos de I/O. O backend C (f64/i64/bool) e o frontend (`Series`, `BoolSeries`,
`DataSet`) já estão implementados — ver `API_Reference.md` para o contrato C e
"Classe Series/DataSet" abaixo. O foco **atual** é a Fase 1.6 (endurecimento):
levar o que existe ao nível "aviação" antes de avançar para `string` e I/O.

---

## Roadmap faseado

| Fase | O que | Status |
|------|-------|--------|
| **1** | Backend C: structs, lifecycle, ops f64/i64, null handling | ✅ Completo |
| **2** | Classe `Series` (despacho por dtype, `ffi.gc`, metamétodos) | ✅ Completo (f64 + i64) |
| **3** | Classe `DataSet`: slicing, filter, sort_by, select, CRUD | ✅ Completo |
| **4** | `BoolSeries`, comparações, `filter` | ⏳ Quase — comparações + `BoolSeries` + `Series:filter` + `DataSet:filter` ✅; falta `dropna` |
| **1.6** | **Endurecimento (testes nível aviação + cobertura + `fillna`)** | ⏳ **ATUAL — gate antes de avançar** |
| **5** | Tipo `string` (Tier 1) | — (promovido para antes do I/O) |
| **6** | I/O: **CSV + JSON** (alvo de deploy), depois XML + SQL | — (design documentado) |
| **7+** | GroupBy, joins, categorical, datetime | Futuro |
| **8** | Resample, window ops, pivot, lazy evaluation | Futuro |

**MVP = backend endurecido + `string` + I/O (CSV/JSON).** Os demais formatos
(XML/SQL) e as fases 7–8 são extensões pós-launch.

### Ordem de execução revisada (decisão registrada)

Duas decisões tomadas em conjunto e que reordenam o plano original:

1. **Endurecimento antes de tudo (Fase 1.6).** Nenhuma fase nova começa antes de
   o que já existe (Fases 1–4) estar validado em nível aviação — testes
   sistemáticos, cobertura **medida** (não estimada), e o gate de ~90% atingido.
   Ver "Fase 1.6 — Endurecimento".
2. **`string` antes de I/O.** Um CSV/JSON real tem colunas de texto; sem o tipo
   `string`, o I/O nasceria capenga (teria que descartar ou recusar colunas de
   texto). Por isso `string` (antes listado como Fase 6) foi **promovido** para
   antes do I/O.

Sequência daqui pra frente: **Fase 1.6 → `string` → CSV/JSON → (XML/SQL) →
`dropna` e demais funções da dívida técnica**.

A Fase 1 está **fechada**: o `Makefile` compila a lib sem warnings
(`-Wall -Wextra`), e os testes C (`test_alloc`, `test_ops`, `test_bool`) passam,
Valgrind-clean.

---

## Visão de longo prazo — o ecossistema

> **Norte do projeto, não tarefa imediata.** Esta seção registra a intenção de
> longo prazo para que as decisões de arquitetura de hoje sejam tomadas com o
> destino em mente. Nada aqui é curto ou médio prazo; tudo depende do Smaug
> estar maduro e endurecido primeiro.

O Smaug é a **fundação de um ecossistema de dados em Lua**, não um fim em si.
Inspirado no ecossistema Python (numpy/pandas → matplotlib → scikit-learn →
SQLAlchemy), o plano de longo prazo tem três bibliotecas que consomem o Smaug:

1. **Visualização (matplotlib-like, HTML/SVG)** — renderização de gráficos a
   partir de dados do Smaug. *Implicação para hoje:* a interface de **exportação
   de dados** (`to_table`, e futuros acessos a colunas/ranges/bins) será API
   pública consumida por terceiros — deve permanecer limpa e estável. Sem
   trabalho extra agora, mas mudanças nessa superfície passam a ter peso de "API
   pública".

2. **Machine learning (scikit-learn-like; eventualmente TensorFlow-like)** — a
   peça mais pesada, e de outra ordem de grandeza. *Implicações para hoje:*
   - ML exige **matriz numérica densa 2-D homogênea** (tudo float64, contígua),
     diferente do `DataSet` (2-D heterogêneo) e da `Series` (1-D). Essa
     representação ainda **não existe** e será necessária — registrar como
     pré-requisito futuro, não construir agora.
   - **Broadcasting** (hoje na dívida técnica) é pré-requisito de ML — sobe de
     "talvez" para "vai precisar" quando o ML entrar.
   - Distinguir as duas ambições: "scikit-learn-like" (algoritmos clássicos —
     regressão, k-means, árvores) é factível; "TensorFlow-like" (autodiff, redes
     neurais, aceleração) é drasticamente mais difícil em Lua/FFI e deve ser
     avaliado com cautela de escopo quando chegar a hora.

3. **ORM (v2.0)** — mapeamento objeto↔banco. O mais desacoplado: aproveita o
   **I/O de SQL** já planejado (Fase 6). *Implicação para hoje:* praticamente
   nenhuma; encaixa naturalmente depois do I/O.

4. **Port para Lua 5.4** (quando o projeto estiver fechado). Hoje o frontend usa
   **LuaJIT** (Lua 5.1 + FFI), e o FFI é o que liga Lua ao C sem código de
   ligação. **Lua 5.4 não tem FFI** — portar exige escrever **bindings C
   manuais** (via API C do Lua: `lua_pushnumber`, `luaL_check*`, etc.) ou manter
   as duas vias (FFI para LuaJIT + bindings para 5.4). É uma mudança
   **arquitetural**, não só troca de interpretador. *Implicações para hoje:*
   - Manter a fronteira Lua↔C **enxuta e centralizada** (hoje no `ffi_loader.lua`)
     facilita o port futuro — quanto menos lugares falam com o C, menos bindings
     reescrever.
   - É o que pode justificar o **CMake** (ver "Opção 3" em `Build_and_Testing.md`):
     compilar bindings para uma versão específica do Lua é onde o CMake (com
     `FindLua`) ajuda mais que o Makefile atual. A decisão sobre o CMake fica
     atrelada a esta.

Consequência transversal: por ser fundação de três bibliotecas, **cada fraqueza
no Smaug se multiplica**. Isso reforça a decisão de endurecer agora (Fase 1.6)
antes de avançar — o rigor "nível aviação" não é exagero, é o que sustenta o
ecossistema.

---

## Fase 1.6 — Endurecimento (gate atual)

Objetivo: levar o que já existe (Fases 1–4) ao nível de robustez "rotina de
aviação" **antes** de construir `string` e I/O em cima. Não se adiciona
funcionalidade nova aqui (exceto `fillna`, justificado abaixo); o foco é provar
que o existente está correto sob estresse e medir essa garantia.

### Critério de "fase validada" (o gate)

A Fase 1.6 só fecha quando **todos** os itens abaixo forem verdadeiros:

1. **Cobertura medida ≥ 90%** de linhas no backend C (`gcov`/`lcov`), com cada
   ramo não-coberto identificado e justificado por escrito. O número é
   **medido**, nunca estimado. 🟡 **Ferramenta pronta** (`make coverage` gera
   `docs/COVERAGE.md`); **baseline medido: ~77% de linha, ~55% de branch — gate
   NÃO atingido.** Falta cobrir principalmente `smaug_ops_i64.c` (56%), pouco
   exercitado pelos testes (que usam mais f64).
2. Bateria de testes sistemáticos (Frente 1) passando, Valgrind-clean.
3. Property-based tests (Frente 1) passando em N≥1000 casos aleatórios por
   invariante, com seed fixa para reprodutibilidade. ✅ **FEITO** (~222k checks,
   validado por mutation testing)
4. `fillna` implementado, testado e documentado (Series + DataSet). ✅ **FEITO**
5. Dívida técnica registrada (seção "Dívida técnica") — o que ficou de fora é
   decisão explícita, não esquecimento.

### Frente 1 — Testes sistemáticos (nível aviação)

Property-based testing em **Lua** (decisão registrada): a stack do Smaug é fina
e determinística (Lua → FFI → C, sem camadas que escondam comportamento), então
testar em Lua exercita o mesmo código C e ainda valida a fronteira FFI
(1-based↔0-based, `nil`↔NA, sentinelas). A única exceção é o teste de **falha de
alocação**, que precisa ser em C (não há como forçar `realloc` a falhar pelo
Lua).

Cobertura exigida:

- **Casos degenerados**, em toda operação: série vazia, de 1 elemento,
  toda-nula, toda-igual. Cada uma pode quebrar reduções, `sort`, `view`, `take`,
  `filter`, `argsort` de formas diferentes.
- **Valores especiais do f64**: `+Inf`, `-Inf`, `NaN` fornecido pelo usuário
  (distinto de nulo), `-0.0`. Comportamento **decidido** abaixo ("Contrato de
  valores especiais"); a Frente 1 testa cada caso.
- **Overflow do i64**: operações perto de `INT64_MAX`/`INT64_MIN`, e a colisão
  com o sentinela `INT64_MIN` das reduções.
- **Property-based (invariantes que valem sempre)**, p. ex.:
  - `len(filter(s, mask)) == count_true(mask)`
  - `sort` é permutação: mesmos elementos, mesma contagem de nulos, monotônico
  - `clone(s)` é igual a `s` em todos os índices, e independente (mutar um não
    afeta o outro)
  - `take(s, perm)` seguido de `take` pela permutação inversa devolve `s`
  - `astype` ida-e-volta preserva valores representáveis e nulos
  - `not(not b) == b` (Kleene), De Morgan entre `and`/`or`/`not`
- **Falha de alocação (em C)**: interceptar `malloc`/`realloc` para falhar sob
  demanda e exercitar de verdade o caminho de erro do `grow` (o fix do realloc
  parcial), confirmando que a série permanece consistente.

### Contrato de valores especiais (decidido)

Decisões tomadas para o comportamento de `NaN`/`Inf` e reduções de coleções
vazias. Estas são o contrato a implementar na Fase 1.6.

1. **`NaN` é distinto de `null`.** No Smaug, `null` (bitmask) = "valor ausente";
   `NaN` (IEEE 754) = "valor presente, mas matematicamente indefinido". São
   conceitos separados — ao contrário de pandas/numpy, que usam `NaN` como
   `null`. Esta separação é uma vantagem do Smaug e deve ser preservada: uma
   operação **nunca** converte `NaN` em `null` nem vice-versa.

2. **`NaN` é "forte" e contagioso na aritmética** (já garantido pelo IEEE 754,
   sem código extra): `NaN + x = NaN`, `NaN * 0 = NaN`, etc. Comparações com
   `NaN` são sempre `false` (`NaN > 5`, `NaN == NaN` → `false`), então
   `:gt`/`:lt`/`:eq` com `NaN` dão `false` (não `null`).

3. **`sort`/`argsort` recusam séries com `NaN`** — exatamente como já recusam
   séries com `null`. Regra uniforme: **valor sem ordem bem-definida → recusa**
   (retorna erro/NULL), em vez de produzir ordenação silenciosamente errada.
   O usuário limpa antes (`dropna` / futuro tratamento de `NaN`) e então ordena.
   Implementação: o sort, além do check de bitmask, passa a checar `isnan()` nos
   valores f64 (i64 não tem `NaN`, não muda). `+Inf`/`-Inf` **são** ordenáveis
   (maior/menor valor) e **não** são recusados.

4. **Redução de coleção vazia/toda-nula — `sum` com `min_count`** (segue o
   pandas): `sum()` retorna `0` por padrão (`min_count=0`), prático e compatível.
   `sum(min_count=1)` retorna `null` se não houver ao menos 1 valor válido —
   para quem precisa distinguir "soma zero" de "não havia dado" (evita erro
   silencioso). `mean`/`min`/`max` de vazio continuam `null`/`NAN` (não há valor
   neutro). Aplicável a `sum` (e `prod`, se vier).

> **Warnings adiados.** A ideia de emitir aviso quando uma operação encontra
> `NaN` (ex.: na camada Lua, opt-in) foi **adiada para uma fase futura de
> observabilidade**, que tratará warnings de forma sistemática em todo o projeto
> em vez de ad-hoc. Ver "Dívida técnica".

### Frente 2 — Cobertura medida

`make coverage` compila com `--coverage` (gcov), roda toda a suíte, e gera um
relatório (texto via `gcov`, opcional HTML via `lcov`/`genhtml`). O relatório
fica versionado/documentado a cada fechamento de fase. Ramos não-cobertos viram
itens: ou ganham teste, ou ganham justificativa.

### Frente 3 — `fillna` (única funcionalidade nova) ✅ FEITO

`fillna` entra agora por ser o par natural do null handling — nosso diferencial.
Todo o resto das funções estatísticas/utilitárias fica na dívida técnica.

Contrato (a implementar):

- **`Series:fillna(value)`** → nova Series (imutável por padrão) com cada nulo
  substituído por `value`. `value` deve ser compatível com o dtype (número para
  f64/i64). Posições não-nulas inalteradas.
- **`Series:fillna()` sem argumento** → erro (não há "valor padrão" seguro;
  forward/backward-fill é dívida técnica).
- **`DataSet:fillna(value)`** → aplica a todas as colunas; ou
  **`DataSet:fillna({col = value, ...})`** → por coluna. Colunas omitidas no
  mapa permanecem com seus nulos.
- Não altera o dtype. Não há coerção implícita (preencher i64 com `1.5` é erro).

---

## Dívida técnica (registrada explicitamente)

Itens conscientemente adiados para manter o endurecimento sem escopo-creep. Cada
um é decisão registrada, não esquecimento. Serão reagendados em fase dedicada
após o MVP de I/O.

**Funções estatísticas/utilitárias (nível Series/DataSet):**

- `median` / `quantile` nativos (hoje `describe` calcula quantis em Lua; falta
  uma redução de primeira classe)
- `abs`, `round`, `clip`
- `cumsum` / `cumprod` (acumuladores)
- `diff`, `shift` (deslocamento de janela)
- `unique`, `value_counts`, `mode`
- `dropna` (Fase 4; destrava `sort`/`sort_by` em dados com nulos) — adiado mas
  prioritário logo após o MVP de I/O
- `fillna` por método (forward/backward-fill); só o preenchimento por valor
  entra na Fase 1.6

**Semântica numérica:**

- **Broadcasting** (operar Series de tamanhos diferentes / Series × array) — o
  coração do NumPy; hoje só há tamanhos iguais
- `apply` / `map` (aplicar função Lua arbitrária elemento a elemento)
- Reconciliar a assimetria documentada de divisão por zero entre f64 (IEEE 754:
  `±Inf`/`NaN`) e i64 (vira NULL)

**Tipos (Tier 2/3):** `datetime`, `categorical` (Tier 2); larguras estreitas
`float32`/`int32`/`int16`/`int8`/`uint*` (Tier 3). Ver "Sistema de tipos".

**Performance/robustez:** benchmarks e teste de estresse (séries de 10⁷+
elementos); avaliação de SIMD; o `ffi.gc` em hot paths (construção em massa).

**Observabilidade (fase dedicada futura):** sistema de **warnings** unificado —
ex.: avisar (opt-in, na camada Lua) quando uma operação encontra `NaN`, quando
há overflow de i64, ou outras condições silenciosas. Adiado de propósito para
ser tratado de forma sistemática em todo o projeto, em vez de avisos ad-hoc
espalhados. Inclui decidir o mecanismo (retorno de status, callback, log
opt-in) sem penalizar os loops quentes do backend C.

---

```
lua/smaug/
├── init.lua            # entry point ✅
├── ffi_loader.lua      # ffi.cdef + ffi.load (tradução pura, sem lógica) ✅
├── core/
│   ├── series.lua      # classe Series (despacho por dtype) ✅
│   ├── dataset.lua     # classe DataSet ✅
│   ├── indexer.lua     # loc/iloc (futuro)
│   └── groupby.lua     # GroupBy (futuro)
├── io/
│   ├── csv.lua         # read_csv / write_csv
│   ├── json.lua        # read_json / write_json
│   ├── xml.lua         # read_xml / write_xml
│   └── sql.lua         # read_sql / write_sql (SQLite)
└── utils/
    ├── validators.lua
    └── formatters.lua  # pretty-print
```

### FFI Bridge (`ffi_loader.lua`) ✅

Responsabilidade única: **tradução**, sem lógica de negócio. Declara os tipos
(`ffi.cdef`) e carrega a `.so` com fallback de paths, retornando o namespace `C`.
Detecta o SO para escolher `libsmaug.so` / `.dylib` / `smaug.dll` e
tenta `./build/`, `../build/`, `../../build/`, `/usr/local/lib/`, depois o nome
puro (deixa o loader do SO resolver via `LD_LIBRARY_PATH`).

O cdef cobre **todas** as assinaturas dos headers (f64 + i64 + bool) mais
`void free(void*)` da libc — necessário para liberar os arrays brutos
(`uint8_t*` de `gt`/`lt`/`eq`, `size_t*` de `argsort`) que o backend devolve com
contrato "caller libera".

> ⚠️ Armadilha: o parser de C do LuaJIT lê comentários `/* ... */` literalmente.
> Um `*/` no meio de um comentário (ex. escrever o tipo `uint8_t*` seguido de
> `/`) **fecha o comentário cedo** e quebra o parse. Evite `*/` dentro de
> comentários no cdef.

```lua
local ffi = require("ffi")
ffi.cdef([[ /* tipos e assinaturas de smaug.h + void smaug_free(void*) */ ]])

local function load_library()
    local name = ({ Windows="smaug.dll", OSX="libsmaug.dylib" })[ffi.os]
                 or "libsmaug.so"
    for _, p in ipairs({ "./build/"..name, "../build/"..name,
                         "../../build/"..name, "/usr/local/lib/"..name, name }) do
        local ok, lib = pcall(ffi.load, p)
        if ok then return lib end
    end
    error("Falha ao carregar a lib Smaug — compile com 'make' primeiro")
end

return load_library()
```

### Classe `Series` (Fase 2) ✅ implementada (f64 + i64)

Encapsula um struct C de série com uma API amigável, metamétodos de operador e
limpeza automática via `ffi.gc`. Arquivo: `lua/smaug/core/series.lua`.

**Arquitetura — despacho por dtype.** A `Series` **não** conhece os detalhes de
cada tipo. Ela despacha para a família de funções C (`smaug_<dtype>_*`) através
de um **descritor** (tabela `DTYPES`). Cada descritor mapeia o nome do dtype
para o conjunto de funções C e suas particularidades semânticas (ex.: o i64
declara `is_int_sentinel` para detectar o `INT64_MIN`). Consequência: adicionar
um tipo novo (`bool`, `string`, `datetime`, `float32`…) é **registrar um
descritor + o backend C**, sem tocar na lógica da `Series` nem no código do
usuário. Esse é o ponto de extensão central do frontend.

Atributos de instância: `_c` (ponteiro C, com `ffi.gc`), `_d` (descritor do
dtype), `_dtype`, `_name`.

Implementado e testado (`tests/test_series.lua`, 69 checks, Valgrind-clean):

- **Factories:** `Series.float64(size, name)`, `Series.int64(size, name)`,
  `Series.new(dtype, size, name)`, `Series.from_table(arr, dtype, name)`
- **Acesso:** `:get(i)`, `:set(i, v)`, `:is_null(i)`, `:set_null(i)`,
  `:append(v)` (chainable), `:len()`/`:size()`
- **Reduções:** `:sum(ignore_na)`, `:mean()`, `:min()`, `:max()`, `:std()`,
  `:var()`, `:count_nonnull()` — `ignore_na` default `true`
- **Transformações:** `:clone()`, `:sort(asc)`, `:argsort(asc)`,
  `:view(start, len)`, `:take(idx)`, `:head(n)`, `:tail(n)`, `:astype(dtype)`,
  `:to_table(na_value)`
- **Inspeção:** `:describe()` (count, nulls, mean, std, min, 25/50/75%, max)
- **Comparações/filtro:** `:gt(t)`/`:lt(t)`/`:eq(t)` → `BoolSeries`,
  `:filter(bool_series)` → nova Series
- **Metamétodos:** `__add`/`__sub`/`__mul`/`__div` (Series×Series ou
  Series×escalar; escalar à esquerda só comuta em `+`/`*`), `__tostring`,
  `__index`/`__newindex` para `series[i]`.

Semântica da fronteira Lua↔C tratada pela classe:

- **1-based → 0-based** em todo acesso por índice.
- **`nil` ↔ null:** `:get` de posição nula devolve `nil`; `:set(i, nil)` marca
  null. Os sentinelas do C (NAN no f64; `INT64_MIN` nas reduções i64) viram
  `nil` nas reduções.
- **Sem coerção entre dtypes:** `f64 + i64` é erro explícito (respeita a decisão
  de design do backend).

> **Sentinela `NA`.** Uma tabela Lua com `nil` no meio (`{1, nil, 3}`) tem
> comprimento (`#`) **indefinido**. Por isso `from_table` usa um sentinela
> explícito para nulos: `Series.from_table({1, Series.NA, 3}, "float64")`.

> **Gotcha do `#`.** No LuaJIT padrão (semântica Lua 5.1), o operador `#` **não**
> chama `__len` em tabelas. Por isso o tamanho é obtido por `:len()`, não por
> `#serie`. O `__len` fica definido para builds com compat 5.2, mas `:len()` é o
> caminho oficial.

> **Views são seguras por construção.** `:view(start, len)` devolve uma fatia
> zero-copy que aponta para a memória da pai. Para evitar use-after-free, a view
> (a) guarda uma referência `_parent` à série-pai, impedindo o GC do Lua de
> coletá-la enquanto a view viver, e (b) é **read-only** — `set`/`set_null`/
> `append` numa view dão erro (o C só bloqueia `append`; a guarda extra fica no
> Lua). `:clone()` de uma view devolve uma cópia independente e mutável. Views
> encadeadas apontam para a pai-raiz. Validado sob Valgrind com GC forçado.

Comparações (`:gt`/`:lt`/`:eq` → `BoolSeries`), `Series:filter` e
`DataSet:filter` já estão implementados (ver "BoolSeries e filtros" e "Classe
DataSet"). Ainda **não** implementado da Fase 4: `dropna` (destrava
`sort`/`sort_by` em dados com nulos) — adiado para depois do MVP de I/O (ver
"Dívida técnica").

### Classe `DataSet` (Fase 3) ✅ implementada

Tabela 2D = coleção de `Series` alinhadas (mesmo número de linhas). Cada coluna é
uma Series independente — não compartilham dados, só o comprimento. Arquivo:
`lua/smaug/core/dataset.lua`.

Atributos: `_columns` (dict nome→Series), `_col_names` (ordem), `_length`,
`_name`.

Implementado e testado (`tests/test_dataset.lua`, 30 checks, Valgrind-clean):

- **Construção:** `DataSet.new(name)`, `DataSet.from_columns({{nome, dados,
  dtype?}, ...})` (açúcar `smaug.dataset{...}`).
- **CRUD de colunas (mutam, chainable):** `:add_column(name, series)` (valida
  comprimento e nome único), `:drop_column(name)`, `:rename_column(old, new)`.
- **Acesso/metadados:** `df["col"]` (via `__index`), `:column(name)`/`:col`,
  `:has_column`, `:columns()`, `:ncols()`, `:nrows()`/`:len()`, `:dtypes()`,
  `:row(i, na)`.
- **Linhas → novo DataSet:** `:filter(bool_series)`, `:sort_by(col, asc)`,
  `:head(n)`, `:tail(n)`, `:iloc(start, stop)`, `:take(idx)`, `:sample(n, seed)`.
- **Colunas → novo DataSet:** `:select(names)` (subconjunto + reordenação).
- **Inspeção:** `:describe()` (por coluna), `:to_table(na)`, `__tostring`
  (tabular).

Invariantes: todas as colunas têm o mesmo `_length` (validado em `add_column`);
`_col_names` e `_columns` sempre sincronizados.

> **Posse e imutabilidade.** `add_column` assume posse da Series passada (não
> clona). Operações que derivam linhas (`filter`/`head`/`tail`/`take`/`iloc`/
> `sample`/`sort_by`) produzem colunas novas via `Series:take`/`:filter`, então
> o DataSet derivado é independente do original — confirmado em teste.

> **`sort_by` reordena todas as colunas** pela permutação (`Series:argsort`) da
> coluna-chave, mantendo o alinhamento entre colunas. Falha se a chave tem
> nulos (o backend não posiciona NA — use `dropna`, Fase 4).

> **Acesso vs métodos no `__index`.** Métodos têm precedência sobre nomes de
> coluna. Para uma coluna cujo nome colida com um método (ex. uma coluna
> "head"), use `df:column("head")`.

### `BoolSeries` e filtros (Fase 4) — comparações + lógica ✅

Encapsula o par (`uint8_t*` valores, `smaug_mask_t*` máscara) devolvido por
`gt`/`lt`/`eq`. Arquivo: `lua/smaug/core/boolseries.lua`; backend lógico em
`src/smaug_ops_bool.c`. Implementado e testado (`test_bool.c` no C,
`test_series.lua` no Lua):

- **Origem:** `Series:gt(t)`, `:lt(t)`, `:eq(t)` → `BoolSeries`.
- **Operadores lógicos (Kleene, três valores):** `:land`/`:lor`/`:lxor`/`:lnot`,
  e os açúcares `*` (and), `+` (or), `-` (xor). NOT só como `:lnot()` (Lua não
  tem operador unário sobrecarregável conveniente).
- **Agregações (NA ignorado):** `:count_true()`, `:any()`, `:all()`.
- **Acesso:** `:get(i)` (true/false/nil), `:is_null(i)`, `:to_table(na)`,
  `:len()`, `__tostring`.
- **Posse de memória:** os arrays brutos são `ffi.gc(ptr, C.free)`. Validado
  Valgrind-clean.

`Series:filter(bool_series)` ✅ devolve uma nova Series só com as linhas onde a
máscara é true (NA na máscara conta como false → linha descartada).
`DataSet:filter` ✅ também implementado (ver "Classe DataSet").

Ainda da Fase 4: `dropna` — adiado para depois do MVP de I/O (ver "Dívida
técnica").

---

## I/O — formatos de dados padrão (Fase 6)

O Smaug suporta **quatro** formatos de entrada/saída, e **apenas** estes quatro.
Eles são o contrato oficial de I/O do projeto; outros formatos estão fora de
escopo.

| Formato | Extensão | Leitura | Escrita | Notas |
|---------|----------|---------|---------|-------|
| **CSV** | `.csv` / `.tsv` | ✅ planejado | ✅ planejado | **Alvo de deploy.** Sem type hints → inferência heurística |
| **JSON** | `.json` | ✅ planejado | ✅ planejado | **Alvo de deploy.** Tipos nativos → menos inferência |
| **XML** | `.xml` | ✅ planejado | ✅ planejado | Pós-deploy. Precisa de convenção tabular explícita |
| **SQL** | SQLite + `.sql` | ✅ planejado | ✅ planejado | Pós-deploy. Via SQLite; tipos vêm do schema |

> **Status:** design apenas; nada implementado. **Pré-requisito:** o tipo
> `string` (Tier 1) precisa existir antes — um CSV/JSON real tem colunas de
> texto. Ordem de implementação: **CSV → JSON** (alvo de deploy) e depois
> **SQL → XML**.

### Struct intermediária comum

Decisão central: **todos os leitores produzem a mesma estrutura tabular
intermediária**, e o frontend Lua a converte para `DataSet`. Da mesma forma,
todos os escritores recebem um `DataSet` e serializam. Isso isola o parsing
(específico de cada formato) da montagem do DataSet (idêntica para todos).

```c
/* Tabela intermediária genérica, compartilhada pelos 4 formatos.
   Substitui o antigo smaug_csv_table_t. */
typedef struct {
    void        **columns;     /* ponteiros para séries (smaug_series_f64_t*, i64*, ...) */
    const char  **dtypes;      /* "float64", "int64", "string", ... por coluna */
    const char  **col_names;
    size_t        num_cols;
    size_t        num_rows;
} smaug_table_t;

void smaug_table_free(smaug_table_t *tbl);
```

Assinaturas de I/O (todas devolvem/recebem `smaug_table_t`):

```c
/* Leitura: arquivo/fonte -> tabela intermediária */
smaug_table_t* smaug_csv_read (const char *path, bool has_header, char delimiter);
smaug_table_t* smaug_json_read(const char *path);
smaug_table_t* smaug_xml_read (const char *path, const char *row_tag);
smaug_table_t* smaug_sql_read (const char *db_path, const char *query);

/* Escrita: tabela intermediária -> arquivo/fonte (0 = ok, -1 = erro) */
int smaug_csv_write (const smaug_table_t *t, const char *path, char delimiter);
int smaug_json_write(const smaug_table_t *t, const char *path, bool records); /* records vs columnar */
int smaug_xml_write (const smaug_table_t *t, const char *path, const char *row_tag);
int smaug_sql_write (const smaug_table_t *t, const char *db_path, const char *table_name);
```

No Lua, o açúcar fica em `io/`: `smaug.read_csv(path)`, `smaug.read_json(path)`,
`smaug.read_xml(path, opts)`, `smaug.read_sql(db, query)` e os `write_*`
correspondentes como métodos do `DataSet`.

### Type inference comum

CSV e XML chegam como texto puro, então precisam de inferência heurística
(rodada nas primeiras N linhas por coluna):

- inteiro se casa `^-?\d+$` → `int64`
- float se casa `^-?\d+\.?\d*([eE]-?\d+)?$` → `float64`
- senão → `string`
- `""`, `"NA"`, `"N/A"`, `null` → nulo

JSON e SQL **já trazem tipos**, então a inferência é mínima (JSON: number/
string/bool/null; SQL: vem do schema da coluna). O usuário sempre pode dar
override no Lua passando um mapa `{coluna = dtype}`.

### CSV

Parser em C (`smaug_csv.c`). Pipeline: ler arquivo em buffer → 1ª passada
(contar linhas/colunas, detectar delimitador) → amostrar primeiras N linhas →
inferir tipo → alocar séries → 2ª passada para popular.

Desafios a tratar: campos com aspas contendo o delimitador (`"Silva, João"`),
aspas escapadas (`""`), quebras de linha dentro de campos aspas.

### JSON

Parser em C (`smaug_json.c`). Dois layouts suportados na leitura:

- **records** (mais comum): array de objetos — cada objeto vira uma linha, as
  chaves viram colunas. Chaves ausentes em alguma linha → nulo.
  `[{"nome":"Ana","idade":30}, {"nome":"Bia","idade":25}]`
- **columnar**: objeto de arrays — cada chave é uma coluna inteira.
  `{"nome":["Ana","Bia"], "idade":[30,25]}`

Na escrita, `records` é o default (mais interoperável); `columnar` é opção.
Objetos/arrays aninhados não têm representação tabular natural — a política é
**achatar um nível** (`{"end":{"cidade":"SP"}}` → coluna `end.cidade`) ou, se
não der, serializar o valor como string JSON. Sem suporte a aninhamento
profundo no MVP.

### XML

Parser em C (`smaug_xml.c`). XML não tem mapeamento tabular padrão, então o
Smaug **exige uma convenção explícita**: o usuário informa a tag que delimita
uma linha (`row_tag`), e os elementos-filho (e/ou atributos) viram colunas.

```xml
<dados>
  <registro><nome>Ana</nome><idade>30</idade></registro>
  <registro><nome>Bia</nome><idade>25</idade></registro>
</dados>
```

Com `row_tag="registro"`: 2 linhas, colunas `nome` e `idade`. Atributos
(`<registro id="1">`) viram colunas prefixadas (`@id`). Inferência de tipo igual
à do CSV (tudo chega como texto). É o formato mais complexo — implementar por
último. Considerar uma lib leve (ex. `libexpat`) em vez de parser próprio.

### SQL

Não é arquivo de texto como os outros: o "formato SQL" do Smaug significa
**integração com SQLite** (banco embarcado, alinhado com o foco leve do
projeto). `smaug_sql_read(db_path, query)` executa um `SELECT` e converte o
result set em tabela; os tipos vêm direto do schema (`INTEGER`→`int64`,
`REAL`→`float64`, `TEXT`→`string`, `NULL`→nulo). `smaug_sql_write` cria/popula
uma tabela.

Depende da `sqlite3` C API — é uma **dependência opcional** (compilar com
`-DSMAUG_WITH_SQLITE` e linkar `-lsqlite3`). Sem ela, os símbolos `smaug_sql_*`
não são expostos. Suporte a outros bancos (Postgres, MySQL) está **fora de
escopo**. Ler/escrever arquivos `.sql` (dumps DDL/DML) é secundário; o caminho
principal é o banco SQLite.

---

## Sistema de tipos

O pandas/NumPy têm dezenas de dtypes, mas a maioria é **variação de largura**
(int8/16/32, float32, uint…) que existe por memória/SIMD, não por semântica
nova. O Smaug separa **tipos com semântica própria** de **variações de largura**
e adota um conjunto curado, em três camadas. A classe `Series` abstrai o dtype
(ver "Classe Series"), então cada novo tipo é um descritor + um backend C, sem
quebrar a API.

### Tier 1 — núcleo (cobre ~95% de dados tabulares reais)

| dtype | Storage C | Null | Status |
|-------|-----------|------|--------|
| `float64` | `double` | NaN + bitmask | ✅ pronto |
| `int64` | `int64_t` | bitmask (sem NaN) | ✅ pronto |
| `bool` | `uint8_t` | bitmask | ✅ comparações + `BoolSeries` (Fase 4) |
| `string` | dictionary encoding | bitmask | ⏳ **Fase 5** (próxima, pré-requisito do I/O) |

O `bool` já existe de forma embrionária — é o `uint8_t*` que `gt`/`lt`/`eq`
devolvem. A Fase 4 o promove a tipo de primeira classe (`BoolSeries`) com
operadores lógicos (`and`/`or`/`not`/`xor`) e agregações (`any`/`all`).

O `string` é o maior buraco para trabalho estilo pandas. Plano: começa como
array de ponteiros (`char**` + comprimentos) e evolui para **dictionary
encoding** (IDs inteiros + dicionário de valores únicos), que acelera muito
groupby, comparação e sorting quando há repetição.

> **Encaixe na arquitetura de headers.** O `string` entra como o 6º header
> (`smaug_string.h`, ao lado de `smaug_numeric.h` e `smaug_bool.h`), incluindo
> apenas `smaug_types.h` (a fundação que isola os tipos) e um lifecycle próprio
> (tamanho variável exige alocação do texto, diferente dos numéricos de tamanho
> fixo). O umbrella `smaug.h` passará a incluí-lo. Nenhum `.c` existente é
> tocado — é adição, não modificação. Foi para viabilizar isso que os tipos
> foram isolados em `smaug_types.h`.

### Tier 2 — alto valor (pós-MVP)

| dtype | Storage C | Notas |
|-------|-----------|-------|
| `datetime` | `int64_t` (epoch ms) | extração ano/mês/dia, aritmética de datas; cabe no double do Lua sem perda até ~2⁵³ ms |
| `categorical` | `int32` codes + levels | índices inteiros + categorias ordenadas; memória eficiente para repetição |

### Tier 3 — otimização (talvez, bem depois)

`float32`, `int32`, `int16`, `int8`, `uint*`. **Mesma semântica** dos tipos de
64 bits, só storage mais estreito (metade ou menos da RAM, melhor para SIMD).
Entram apenas se um caso real de memória/performance justificar — não fazem
parte do MVP. Como a `Series` despacha por descritor, adicioná-los não muda o
código do usuário.

### Princípios transversais (valem para todos os dtypes)

- **Sem coerção implícita.** Operar entre dtypes diferentes é erro explícito; o
  usuário converte de propósito. (Conversão `:astype(dtype)` virá como método.)
- **Null por bitmask paralelo**, uniforme para todos os tipos — inclusive os que
  não têm um "NaN" nativo (inteiros, bool, string).
- **Mapeamento NumPy/pandas → Smaug** documentado para conversão de dados:
  `np.float64`→`float64`, `np.int64`→`int64`, `np.bool_`→`bool`,
  `object`/`StringDtype`→`string`, `datetime64[ns]`→`datetime`,
  `category`→`categorical`. Larguras menores do NumPy (`int32`, `float32`, …)
  promovem para o tipo de 64 bits correspondente até o Tier 3 existir.

## GroupBy e Joins (Fase 7+)

GroupBy: `df:groupby(col)` → objeto que mapeia chave → índices de linha, com
agregações por grupo (`:sum()`, `:mean()`, `:count()`, `:agg{...}`). Backend
acelerado por hash table em C (`smaug_hash_table_t`, já declarado como tipo
opaque no header). Joins (inner/left/outer) também via hash table.

---

## Critério de "fase concluída"

Uma fase está pronta quando: features implementadas; testes unitários passam;
resultados validados contra Pandas/NumPy quando aplicável; zero leaks no
Valgrind; documentação atualizada; benchmarks rodados.

## Benchmarks alvo (referência)

| Operação | Alvo | NumPy |
|----------|------|-------|
| `sum(1M floats)` | < 5 ms | ~1 ms |
| `Series + Series (1M)` | < 20 ms | ~5 ms |
| `filter(1M)` | < 15 ms | ~3 ms |
| `CSV read (100K linhas)` | < 500 ms | ~50 ms |

Overhead aceitável para o MVP: 3–5× NumPy.
