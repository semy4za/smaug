# Changelog — Smaug

Formato baseado em [Keep a Changelog](https://keepachangelog.com/).

## [Não lançado]

### Adicionado (Fase string — ordenação: sort/argsort) — FASE STRING COMPLETA
- **`smaug_str_argsort`** (permutação de índices, lexicográfica por bytes, via
  `qsort` com desempate estável por índice) e **`smaug_str_sort`** (= argsort +
  take) em `src/smaug_ops_str.c`. Política coerente com os numéricos: **recusam
  séries com qualquer NULL** (retornam NULL — ordenar com ausência é indefinido;
  use dropna antes). String vazia `""` ordena normalmente (vem primeiro).
  `ascending` controla crescente/decrescente. Reusa `take` (já existente).
- **Frontend Lua:** `series:sort([ascending])` e `series:argsort([ascending])`
  para dtype string (os métodos genéricos já delegavam ao descritor).
- Testes: `test_string.c` 79 -> 87; `test_string.lua` 53 -> 59. Removido um teste
  obsoleto que assertava "sort recusa string (ainda)" — agora sort existe.
  Valgrind-clean. Cobertura: total 93.48% -> 93.67% / branch 68.88% -> 69.32%.

**Com isto a string é um dtype de primeira classe**, com paridade às operações
dos numéricos onde fazem sentido: lifecycle, acesso, mutação, comparações
(eq/lt/gt), seleção (filter/take) e ordenação (sort/argsort). Próximo marco do
projeto: I/O (CSV/JSON) para carregar dados reais.

### Adicionado (Fase string — seleção: filter e take)
- **`smaug_str_filter`** (nova série com os elementos onde a máscara é 1) e
  **`smaug_str_take`** (nova série com os elementos nos índices dados, na ordem
  pedida) em `src/smaug_ops_str.c`. Ambos preservam NULL e reusam
  `append`/`append_null` por baixo (que já gerenciam buffer/offsets de tamanho
  variável, Valgrind-clean) em vez de mexer em offsets na mão. `take` com índice
  fora dos limites retorna NULL. Valgrind-clean.
- **Frontend Lua:** `series:filter(bool)` e `series:take({i,...})` para dtype
  string (e `head`/`slice` ganham string de graça, pois usam take). Destrava o
  caso de uso central: **filtrar um DataSet por coluna de texto** —
  `df:col("pop"):filter(df:col("uf"):eq("SP"))`.
- Testes: `test_string.c` 72 -> 79; `test_string.lua` 46 -> 53 (inclui filtro de
  DataSet por coluna de texto). Cobertura: total 93.25% -> 93.48%.

### Próximo (fecha a fase string)
- `sort`/`argsort` para string (ordem alfabética, usa lt/gt). Depois disso, a
  string é um dtype de primeira classe — e o próximo marco é CSV/JSON (I/O).

### Adicionado (Fase string — comparações eq/lt/gt)
- **`src/smaug_ops_str.c`** (arquivo de ops da string, antes reservado vazio na
  refatoração — agora ganha conteúdo): `smaug_str_eq/lt/gt` comparam cada
  elemento contra uma string-alvo, retornando `uint8_t*` + máscara (NULL ->
  resultado 0, máscara 0x00). Ordem lexicográfica por **bytes** (não
  Unicode-aware; ver Roadmap). Otimização honesta (a mesma dos modelos para
  string simples): `eq` compara comprimento primeiro (O(1) via offsets), só faz
  `memcmp` se baterem; `lt`/`gt` fazem `memcmp` até o menor comprimento e
  desempatam pelo comprimento. A otimização real (dictionary) é o `categorical`
  futuro — a interface encapsulada permite trocar por baixo sem mudar o frontend.
- **Frontend Lua:** `series:eq/lt/gt("alvo")` para dtype string -> BoolSeries.
  O `compare` genérico passou a delegar a wrappers `cmp_eq/cmp_lt/cmp_gt` no
  descritor de cada dtype (numéricos validam escalar; string valida string Lua e
  passa ponteiro+len) — métodos genéricos seguem agnósticos ao dtype. Recusa de
  tipo nos dois sentidos (string:eq(número) e número:eq(string)).
- Testes: `test_string.c` 62 -> 72 checks (C); `test_string.lua` 33 -> 46
  (frontend). Valgrind-clean. Cobertura: `smaug_ops_str.c` 100% linha / 78.57%
  branch; total 92.96% -> 93.25% / branch 68.31% -> 68.64%.

### Próximo (fase string)
- `take`/`filter` para string (destrava `series:filter(series:eq("SP"))`).
- `sort`/`argsort` para string (usa lt/gt — ordem alfabética).

### Build/teste — review e correção (causa raiz do commit quebrado)
- **Makefile: listas de teste centralizadas.** Antes os testes C apareciam em 3
  blocos (compilar/rodar/valgrind) e os Lua noutro — adicionar um teste exigia
  editar 4 lugares, e esquecer um quebrava o build (foi o que aconteceu). Agora
  há **fonte única**: `C_TESTS_PLAIN`, `C_TEST_WRAP`, `LUA_TESTS`; os alvos
  iteram sobre elas. Adicionar teste = editar uma linha.
- **`windows-build.ps1` atualizado** (estava bem defasado): rodava só 3 testes C
  (faltavam `test_string`, `test_allocfail`) e 2 suítes Lua (faltavam 6). Agora
  cobre os 5 testes C (incl. `test_allocfail` com `--wrap`) e as 8 suítes Lua,
  alinhado ao Makefile. Mantido ASCII puro. Checagem de saída corrigida para
  aceitar "PASS: ..." (testes com texto após PASS).
- `make_manifest.sh` revisado: já pega arquivos por extensão (sem lista
  hardcoded), acompanha arquivos novos sozinho — sem mudança necessária.

### Cobertura — dívida paga (agregação de todos os testes)
- **`make coverage` agora mede TODOS os testes do projeto.** Antes media só via
  `.so` + testes Lua; `test_allocfail` (caminhos de erro/OOM) e `test_string`
  (lifecycle/set/clone em C) ficavam de fora. Reescrito para compilar os
  `src/*.c` como `.o` instrumentados compartilhados — `.so`, testes C diretos e
  `test_allocfail` (via `--wrap` + `--coverage`) linkam contra os mesmos `.o`, e
  os `.gcda` agregam no gcov. Paga a dívida "agregar test_allocfail à cobertura".
- **Resultado (medido, honesto — não infla, conta testes que já existiam):**
  linha **89.54% → 92.96%**, branch **62.45% → 68.31%**. `smaug_str.c`: linha
  52% → 97.58% (o `test_string.c` em C agora conta). Ganho de branch em core
  (56%→70.67%), i64 (67.83%→70.54%), str (52%→67.14%).
- Gap de branch restante: caminhos de erro de **string** (o allocfail cobre
  f64/i64/core, ainda não string) e ramos de valores especiais. Registrado.

### Adicionado (Fase string — frontend Lua, núcleo)
- **Dtype `string` registrado na `Series`** (`series.lua` + `ffi_loader.lua`):
  `from_table`/`Series.string`, `get` (devolve string Lua via `ffi.string`),
  `set`/`append` (passam ponteiro+comprimento), `set_null`, `is_null`,
  `count_nonnull`, `clone`. Encapsulamento limpo: a diferença de assinatura da
  string (ponteiro+len vs. valor) fica em **wrappers no descritor do dtype**; os
  métodos genéricos não foram ramificados. Para isso, a conversão de tipo no
  `get` migrou do método genérico (`tonumber`) para `get_value` em cada descritor
  — cada dtype converte seu próprio valor para o tipo Lua certo.
- **Recusa clara de operações inaplicáveis:** `require_op` faz `sum`/`add`/`sort`
  etc. em string darem erro explicativo ("operação X não se aplica ao tipo
  string") em vez do críptico "call a nil value". `check_value` estendido: string
  só aceita string Lua; numéricos só aceitam número.
- **DataSet com coluna de string** funciona de graça (composição: DataSet é
  coleção de Series).
- **`tests/test_string.lua`** (33 checks): acesso, vazia≠NULL, mutação (set 3
  casos, set_null, append com NA), clone independente, recusas, integração com
  DataSet. Integrado a `make test-lua` (8 suítes) e `make coverage`. Valgrind-clean.

### Cobertura
- Revisada ao integrar a string: `smaug_ops_str.c` agora medido via Lua (84.85%
  linha). Total **90.54% → 89.54%** — não é regressão; é o número passando a
  contar um arquivo novo cujo caminho de `set` (deslocamento) o frontend básico
  não exercita todo (o `test_string.c` em C cobre, mas não entra na medição via
  .so, como o allocfail). Gap registrado na dívida; fechar com testes Lua de
  `set` de string ou aceitar conscientemente.

### Adicionado (Fase string — backend C completo)
- **`src/smaug_ops_str.c`** implementa o tipo string (offset-based) no C:
  - Lifecycle: `create`, `create_with_capacity`, `create_from_array`, `clone`
    (cópia profunda independente), `free`.
  - Acesso: `get` (devolve ponteiro+comprimento, sem cópia), `is_null`.
  - Mutação: `set` (3 casos — igual sobrescreve in-place; maior/menor deslocam o
    buffer via `memmove` e recalculam offsets, com realocação quando preciso),
    `set_null`, `append`, `append_null`.
  - Utilidade: `count_nonnull`.
  - String vazia `""` distinta de NULL; trata bytes crus (validação UTF-8 fica
    como enriquecimento futuro — ver Roadmap/dívida).
- **`tests/test_string.c`** (62 checks): lifecycle, construção em lote, os 3
  casos do `set` (incl. no meio e sobre NULL), `set_null`, append com NULL
  intercalado, e independência do `clone`. Integrado a `make test`/`make valgrind`
  (agora 5 testes C). Validado sob Valgrind (0 errors, no leaks) em todos os
  caminhos — incluindo o deslocamento de buffer.

### Próximo
- Frontend Lua: registrar o dtype `string` na `Series` (descritor + ffi_loader).
- Depois: comparações (eq/lt/gt), sort/argsort, take/filter para string.

### Adicionado (Fase string — esqueleto)
- **Tipo `string` iniciado** (representação offset-based, estilo Arrow). Struct
  `smaug_series_str_t` em `smaug_types.h`: buffer de bytes concatenados + array
  de offsets (`size+1` marcadores) + bitmask de nulos. Comprimento O(1); string
  vazia distinta de NULL.
- **6º header `smaug_string.h`** (irmão de `smaug_core.h`): assinaturas de
  lifecycle (create/with_capacity/from_array/free/clone) e acesso
  (get/set/set_null/is_null/append/count_nonnull). Inclui só `smaug_types.h`
  (lifecycle próprio). Adicionado ao umbrella `smaug.h`. Headers compilam; build
  da lib intacto (ainda sem `.c` — só declarações).
- Implementação (`src/smaug_ops_str.c`), registro do dtype no frontend e testes
  são as próximas peças (ver Roadmap).

### Corrigido / documentado (contrato de entrada do backend)
- **Contrato de acesso do backend C documentado** no `smaug_core.h`: as funções
  get/set/set_null/is_null/view **já validam** ponteiro/índice (não corrompem
  memória), mas falham silenciosamente — o frontend Lua é quem sinaliza erro ao
  usuário (check_index). Tornar a sinalização explícita no C (assinaturas com
  código de retorno) foi **adiado** até existir um cliente em C que use o backend
  sem o frontend Lua (decisão registrada no Roadmap; evita mudança grande sem
  caso de uso concreto). A sondagem revelou que o backend não era "inseguro" como
  se supunha — só silencioso.
- **A7 corrigido — `set`/`append` em int64 não truncam mais.** Guard comum
  (`check_value`) recusa não-inteiro/NaN/Inf em int64 com erro claro (a truncagem
  ocorria na conversão FFI, então a validação fica no Lua). Conversão explícita
  segue via `astype("int64")` (trunca em direção a zero; NaN/Inf → null).
  `test_i64.lua`: +11 checks (58 → 69), validado por mutation testing.

### Documentação
- **README reescrito** para o recém-chegado: exemplo de código funcional no topo
  (verificado), status atualizado (Fase 1.6 fechada), inconsistências do antigo
  corrigidas (frontend descrito como feito, testes/cobertura reais), promessas
  não-medidas removidas.
- **Roadmap reformulado** (681 → 213 linhas): separa **✅ feito (resumo)** /
  **🔨 DECIDIDO** (contrato C → string → CSV/JSON) / **💭 CONCEITUAL** (SQL,
  GroupBy/Join/Window, Lazy por último) / **visão de longo prazo** / dívida.
  Marcadores visuais distinguem decisão batida de ideia. Removido o código de
  implementação duplicado das fases concluídas (vive no código/API_INDEX).
  Decisões incorporadas: string simples + categorical-dictionary depois (não
  dictionary-first); SQL focado em SQLite (abstração de dialeto adiada, fronteira
  concentrada); XML pós-release; ORM pós-release com roadmap próprio (migrações
  inspiradas no Alembic); lazy como camada sobre operações imutáveis existentes.
  Incorpora parecer técnico externo (Matrix/Tensor2D para ML, broadcasting como
  pré-requisito, string bem-encapsulada).

### Adicionado (Fase 1.6 — falha de alocação; FASE FECHADA)
- `tests/test_allocfail.c`: teste de falha de alocação no padrão SQLite —
  intercepta `malloc`/`realloc` via `-Wl,--wrap` e faz a N-ésima alocação falhar,
  varrendo **cada ponto** de alocação de cada operação (create, from_array,
  clone, view, append/grow, add, add_scalar, comparações, argsort, sort) em
  **f64 e i64**. Verifica recuperação graciosa (NULL/erro, sem crash) e, sob
  Valgrind, ausência de vazamento em todos os ~215 cenários. Integrado a
  `make test`/`make valgrind`.

### Corrigido
- **Double-free no caminho de reversão do `grow`** (f64 e i64), exposto pelo
  test_allocfail: quando `capacity == 0`, o `realloc(data, 0)` de reversão
  liberava o buffer e deixava `s->data` pendente. Agora a reversão só ocorre se
  `capacity > 0`. Validado por mutation testing. Ver CODE_REVIEW A5.

### Marco
- **Fase 1.6 (endurecimento) FECHADA** — todos os 5 critérios do gate atingidos:
  cobertura de linha ≥90% (medida), testes sistemáticos + Valgrind, property-based
  (~222k checks), fillna, e dívida registrada. Próxima fase: contrato defensivo
  do backend C, antes da string.

### Adicionado (Fase 1.6 — cobertura do int64)
- `tests/test_i64.lua`: suíte dedicada ao int64 (58 checks) — aritmética
  (add/sub/mul/div inteira, /0→null, propagação de NA), escalares, reduções
  (min/max/mean/var/std populacionais, sentinela INT64_MIN→nil), comparações
  (gt/lt/eq + NA), ordenação (sort asc/desc, argsort, recusa de NULL), seleção
  (take/filter), lifecycle (clone independente, view, append-grow) e astype.
  Cada caso **asserta** o resultado (valores verificados por sondagem, não
  supostos). Integrado a `make test-lua` e ao `make coverage`. Valgrind-clean.
- **Cobertura de linha: 77% → 90.65%** — gate da Fase 1.6 (linha ≥90%) agora
  **ATINGIDO**. `smaug_ops_i64.c`: 56% → 96%. Branch ~65% segue como norte de
  longo prazo. (Rótulo de conversa "opção A" também removido da doc de cobertura.)

### Adicionado (Fase 1.6 — medição de cobertura)
- `make coverage` (via `scripts/make_coverage.sh`): mede a cobertura do backend
  C e **gera** `docs/COVERAGE.md` (artefato gerado, como o MANIFEST — nunca
  escrito à mão). Compila uma `.so` instrumentada e roda os testes C **e** Lua
  contra ela (acumula os dois caminhos), agrega com gcov, reporta linha e branch
  ("taken at least once", métrica SQLite), com commit/data e status do gate.
- `docs/COVERAGE.md`: baseline medido — **~77% linha, ~55% branch**. Gate da
  1.6 (linha ≥90%) **NÃO atingido**; o buraco é `smaug_ops_i64.c` (56%, pouco
  exercitado — os testes usam mais f64). Regenerar e commitar a cada mudança de
  código/testes.
- `.gitignore`: ignora artefatos de cobertura (`cov/`, `*.gcda/gcno/gcov`).
- Norte de longo prazo registrado (Roadmap/COVERAGE): meta **branch 100%**
  (padrão SQLite), atingida incrementalmente atacando os caminhos de erro via
  `test_allocfail.c` e testes de entrada inválida.

### Adicionado (Fase 1.6 — property-based)
- `tests/test_props.lua`: testes baseados em propriedades — 10 invariantes ×
  3 seeds fixas × 400 casos (~222 mil checks). Invariantes: clone independente
  (anti-aliasing), view compartilha memória, sort é permutação (multiconjunto +
  monotonia), sort recusa null/NaN, filter↔count_true, take+inversa=identidade,
  astype ida-volta, fillna remove null/preserva NaN, Kleene (dupla negação, De
  Morgan). Cada invariante com gerador próprio que respeita o contrato. Seeds
  fixas (reprodutível); falha imprime seed+caso. **Validado por mutation
  testing** (bug de aliasing injetado no clone → property-based detectou).
  Valgrind-clean mesmo com 222k checks (prova o `ffi.gc` sob carga). Integrado
  ao `make test-lua`.

### Adicionado (Fase 1.6 — `fillna`)
- **`Series:fillna(value)`** e **`DataSet:fillna(value | {col=value})`**: nova
  Series/DataSet com NULLs substituídos. Cumpre o contrato: sem argumento =
  erro; **sem coerção** (`fillna(1.5)` em int64 = erro, não trunca); preenche
  **null** e **preserva NaN** (NaN é valor, não ausência — distinção null≠NaN em
  ação). Original imutável. Implementado em Lua (não toca no backend C).
- `tests/test_fillna.lua`: 25 checks (Series + DataSet, casos degenerados,
  preservação de NaN, recusa de coerção). Integrado ao `make test-lua`.
  Valgrind-clean.
- Achado **A7** registrado no `CODE_REVIEW.md`: `set` em int64 trunca não-inteiro
  silenciosamente (e NaN vira lixo) — a corrigir em peça dedicada; o `fillna`
  já valida por conta própria, então cumpre o contrato mesmo antes dessa correção.

### Corrigido (Fase 1.6 — contrato de NaN agora implementado)
- **`NaN` deixa de virar `null`.** O `is_na` do `series.lua` tratava `NaN`
  como ausente; agora só `nil`/`Series.NA` são null. `set(i, NaN)`,
  `from_table` e `append` gravam `NaN` como valor presente (`is_null`→false,
  `count_nonnull` conta). Cumpre a decisão "NaN ≠ null". Permite null e NaN
  **distintos** na mesma série (vantagem sobre pandas/numpy).
- **`sort`/`argsort` (f64) passam a recusar `NaN`** além de null (checagem
  `isnan` no `smaug_ops_f64.c`). NaN não tem ordem definida → recusa, como já
  acontecia com null. `±Inf` continuam ordenáveis.

### Adicionado (Fase 1.6 — endurecimento)
- `tests/test_special.lua`: 35 checks dos valores especiais do f64 — `±Inf`
  (ordenáveis, reduções), `NaN` distinto de null (set/from_table/op, contágio,
  recusa no sort, comparação→false), `-0.0`. Integrado ao `make test-lua`.
  Valgrind-clean. As asserções falharam antes das correções (prova de que as
  violações existiam) e passam depois.

### Adicionado (Fase 1.6 — endurecimento, em andamento)
- `tests/test_edge.lua`: bateria de casos degenerados (59 checks) — série
  vazia, 1 elemento, toda-nula, toda-igual — cobrindo reduções, sort, view,
  take, filter, comparações, em f64 e i64. Inclui verificação explícita de
  **propagação de NA em comparação** (comparar nulo → NA na máscara, nunca
  false). Integrado ao `make test-lua`. Valgrind-clean. Confirma que o
  comportamento atual nos limites é são; marca com "PENDENTE (1.6)" os pontos
  que dependem de `min_count`/`fillna`/recusa-de-NaN ainda a implementar.

### Alterado (infra)
- **Biblioteca renomeada** `libsmaug_math` → `libsmaug` (`.so`/`.dll`/`.dylib`),
  coordenado em 3 lugares: `Makefile` (TARGET), `ffi_loader.lua` (nomes do
  `ffi.load`) e `windows-build.ps1`. O nome "math" não refletia mais o conteúdo
  (a lib é o Smaug inteiro). Validado: Lua carrega e passa os 99 checks nas duas
  plataformas. Docs de comandos/exemplos atualizadas.
- `.gitattributes`: força `eol=lf` em todo arquivo de texto. Resolve a conversão
  CRLF↔LF do Git no Windows, que mudava os bytes e quebrava a verificação por
  hash do `MANIFEST.txt` (e gerava diffs-fantasma). Agora Windows e Linux
  produzem bytes idênticos.

### Decidido (contrato de valores especiais — Fase 1.6)
- **`NaN` ≠ `null`** no Smaug: `null` é ausência (bitmask), `NaN` é valor IEEE
  indefinido. Nunca se converte um no outro (vantagem sobre pandas/numpy).
- `NaN` contagioso na aritmética (IEEE, de graça); comparações com `NaN` dão
  `false` (`:gt`/`:lt`/`:eq`), não `null`.
- **`sort`/`argsort` recusam `NaN`** (além de `null`) — regra uniforme "sem
  ordem definida → recusa". `±Inf` são ordenáveis (não recusados).
- **`sum(min_count=...)`**: `sum()` retorna 0 por padrão; `sum(min_count=1)`
  retorna `null` se não houver valor válido (evita erro silencioso). Segue o
  pandas. `mean`/`min`/`max` de vazio seguem `null`/`NAN`.
- **Warnings adiados** para uma fase de observabilidade dedicada (tratados de
  forma sistemática, não ad-hoc). Registrado na dívida técnica.
- Documentado em `Roadmap.md` ("Contrato de valores especiais" + dívida).

### Adicionado (qualidade / processo)
- `docs/CODE_REVIEW.md`: review completo do código (baseline pré-Fase 1.6).
  Veredito: correto e consistente; achados A1–A6 de robustez para tratar no
  endurecimento (assimetria de empty-reduction, overflow em `view`, valores
  especiais f64, overflow i64, caminho de falha de `realloc`, validação de
  `take`).
- `docs/MANIFEST.txt` + `scripts/make_manifest.sh` + alvos `make manifest` /
  `make verify`: método de integridade (sha256 + linhas por arquivo) para
  transferir o projeto sem perdas/divergência. Seção "Integridade do projeto" no
  `Build_and_Testing.md`.

### Alterado (arquitetura de headers — refactor)
- `smaug_math.h` **removido** e separado por responsabilidade (inspirado no
  NumPy): `smaug_types.h` (tipos base, zero funções), `smaug_core.h` (lifecycle
  + `smaug_free`), `smaug_numeric.h` (aritmética/reduções/comparações/sort/utils
  f64+i64), `smaug_bool.h` (Kleene) e `smaug.h` (umbrella). Cada `.c` passou a
  incluir o header específico; testes incluem o umbrella. Removida a gambiarra
  `extern smaug_*_create` nos ops (agora declarado via header). A lib compilada
  permanece `libsmaug_math.so`/`smaug_math.dll`. Prepara o terreno para
  `smaug_string.h` (6º header) entrar sem tocar nos demais. Refactor validado:
  build limpo, 3 testes C + 99 checks Lua, Valgrind-clean. Mapa de headers
  documentado na `API_Reference.md`.

### Planejado (Fase 1.6 — Endurecimento, gate atual)
- Definida a Fase 1.6 como **gate obrigatório** antes de `string` e I/O:
  endurecer Fases 1–4 ao nível "aviação". Critério de fechamento documentado no
  `Roadmap.md` (cobertura ≥90% medida por gcov, testes sistemáticos +
  property-based, `fillna`).
- Estratégia de testes documentada no `Build_and_Testing.md`: casos
  degenerados, valores especiais do f64, overflow do i64, **property-based em
  Lua** (decisão registrada), e **falha de alocação em C**. Alvo `make coverage`.
- Registrada a **dívida técnica** explícita (`Roadmap.md`): `median`/`quantile`
  nativo, `abs`/`round`/`clip`, `cumsum`/`cumprod`, `diff`/`shift`, `unique`/
  `value_counts`, `dropna`, broadcasting, `apply`/`map`, tipos Tier 2/3, e
  benchmarks/estresse.
- **Reordenação registrada:** `string` (Tier 1) promovido para **antes** do I/O
  (um CSV/JSON real tem colunas de texto). Sequência do MVP: 1.6 → `string` →
  CSV/JSON → XML/SQL. `fillna` é a única funcionalidade nova da 1.6.

### Corrigido (portabilidade Windows)
- `smaug_free()`: nova função exportada pela lib para liberar os buffers crus
  (arrays de comparações/bool ops, `size_t*` do argsort). Substitui o uso da
  `free()` da libc via FFI, que falhava no Windows (`cannot resolve symbol
  'free'` — a DLL não exporta a `free` do runtime). O frontend (`series.lua`,
  `boolseries.lua`, `ffi_loader.lua`) passa a usar `C.smaug_free`. Validado
  Valgrind-clean no Linux e funcionando no Windows.

### Adicionado (ferramentas)
- `scripts\windows-build.ps1`: setup + build + testes no Windows via PowerShell.
  Compila `build\smaug_math.dll` com gcc (sem make), roda os testes C e Lua.
  Flag `-Setup` instala MSYS2 + gcc + luajit. Seção "Windows (PowerShell)" no
  `Build_and_Testing.md`. (Valgrind permanece exclusivo do Linux.) Script em
  ASCII puro para evitar problemas de codificação no Windows PowerShell 5.1.

### Adicionado (Fase 3 — DataSet)
- `lua/smaug/core/dataset.lua`: classe `DataSet` (tabela 2D = coleção de Series
  alinhadas). Construção (`new`, `from_columns`, açúcar `smaug.dataset{...}`);
  CRUD de colunas (`add_column`/`drop_column`/`rename_column`, com validação de
  comprimento e nome único); acesso `df["col"]` via `__index` e `:column`;
  metadados (`columns`/`ncols`/`nrows`/`dtypes`/`row`); operações de linha que
  retornam novo DataSet (`filter`/`sort_by`/`head`/`tail`/`iloc`/`take`/
  `sample`); `select` de colunas; `describe`, `to_table` e `__tostring`
  tabular.
- `Series:argsort(asc)`: tabela 1-based de índices que ordenam (nil se há
  nulos). Base do `DataSet:sort_by`, que reordena todas as colunas pela mesma
  permutação mantendo o alinhamento.
- `tests/test_dataset.lua`: 30 checks (dims, acesso, CRUD, filter/sort_by/
  head/tail/iloc/take/sample/select, describe, imutabilidade de derivados,
  tostring). Valgrind-clean. `Makefile`: `test_dataset.lua` em `make test-lua`.
- `init.lua`: expõe `DataSet` e `smaug.dataset`. Versão → 0.3.0-dev.


### Adicionado (Fase 4 — bool, comparações e filtro)
- `src/smaug_ops_bool.c`: backend booleano com **lógica de três valores
  (Kleene)** — `and`/`or`/`xor`/`not` e agregações `count_true`/`any`/`all`
  (NA ignorado). Declarações em `smaug_math.h` e no `ffi_loader.lua`.
- `lua/smaug/core/boolseries.lua`: classe `BoolSeries` que possui o par de
  arrays brutos (valores `uint8_t*` + máscara) via `ffi.gc(C.free)`. Métodos
  `:land`/`:lor`/`:lxor`/`:lnot`, `:count_true`/`:any`/`:all`, `:get`/`:is_null`/
  `:to_table`/`:len`/`__tostring`, e operadores `*` (and), `+` (or), `-` (xor).
- `Series`: `:gt(t)`/`:lt(t)`/`:eq(t)` → `BoolSeries`; `:filter(bool_series)` →
  nova Series (NA na máscara = linha descartada).
- `tests/test_bool.c`: testa a lógica Kleene e as agregações no nível C
  (Valgrind-clean). `tests/test_series.lua` estendido para 69 checks (cobre
  comparações, filter, lógica e Kleene). `Makefile`: `test_bool` em
  `make test`/`make valgrind`.


### Adicionado (Fase 2 — frontend)
- `lua/smaug/core/series.lua`: classe `Series` com **despacho por dtype**
  (tabela de descritores `DTYPES`), cobrindo `float64` e `int64`. Factories
  (`float64`/`int64`/`new`/`from_table`), acesso 1-based com `nil`↔null,
  reduções (com `ignore_na`), aritmética via metamétodos (`__add`/`__sub`/
  `__mul`/`__div`, Series×Series e Series×escalar), `clone`, `sort`,
  `to_table`, `__tostring`, `__index`/`__newindex`. `ffi.gc` para limpeza
  automática. Trata os sentinelas do backend (NAN e `INT64_MIN`) como `nil`.
- `Series` — transformações/inspeção adicionais: `:view(start, len)` (fatia
  zero-copy segura, ver abaixo), `:take(idx)`, `:head(n)`, `:tail(n)`,
  `:astype(dtype)` (conversão entre tipos), `:describe()` (count, nulls, mean,
  std, min, quartis 25/50/75%, max).
- **Segurança de views.** A view guarda `_parent` (impede o GC do Lua de
  coletar a pai → sem use-after-free) e é read-only (`set`/`set_null`/`append`
  dão erro). Validado sob Valgrind com GC forçado. `:clone()` de view devolve
  cópia independente e mutável.
- `lua/smaug/init.lua`: entry point (`require("smaug")`), expõe `Series` e
  açúcares (`smaug.float64`, `smaug.int64`, `smaug.from_table`, `smaug.NA`).
- `tests/test_series.lua`: smoke test do frontend (49 checks, f64 + i64).
  Valgrind-clean com `ffi.gc`.
- `Makefile`: alvo `make test-lua`.
- Sentinela `Series.NA` para representar nulos em `from_table` (contorna o
  comprimento indefinido de tabelas Lua com `nil` no meio).

### Decisões de design (sistema de tipos)
- Adotado um sistema de tipos **em camadas**: núcleo (`float64`✅, `int64`✅,
  `bool`, `string`), alto valor (`datetime`, `categorical`) e otimização
  (`float32`/`int32`/… — mesma API, storage estreito, só se necessário).
  Variações de largura não proliferam no MVP. Documentado em
  `Roadmap.md` → "Sistema de tipos", com o mapeamento NumPy/pandas → Smaug.
- A `Series` abstrai o dtype por descritor: novo tipo = descritor + backend C,
  sem mudar a API. Sem coerção implícita entre dtypes (erro explícito).
- Documentado o gotcha do LuaJIT 5.1: `#` não chama `__len` em tabelas; o
  tamanho oficial é `:len()`.

### Corrigido
- `Makefile`: `cc = GCC` (ignorado, compilava por acidente com o `cc` do
  sistema) corrigido para `CC = gcc`.
- Falha parcial de `realloc` em `f64_grow`/`i64_grow`: quando o `realloc` do
  `null_mask` falhava após o do `data` ter sucesso, a série ficava inconsistente.
  Agora o `data` é encolhido de volta, preservando o invariante. Coberto por
  `test_alloc.c`.

### Adicionado
- `tests/test_alloc.c`: testes de lifecycle/memória (create, create_with_capacity,
  create_from_array, free idempotente, clone independente, view com aliasing e
  read-only, append/grow, paridade i64). Valgrind-clean (0 leaks, 0 erros).
- `Makefile`: alvos `make test` e `make valgrind`.

### Documentação
- `API_Reference.md`: documentado o sentinela **`INT64_MIN`** das reduções i64
  (`sum`/`min`/`max` com `ignore_na=false` ou série vazia/só-nulos) e a
  ambiguidade associada. Documentado que a **divisão por zero no i64 vira NULL**
  (série e escalar), em contraste com o `±Inf`/`NaN` do f64. Problema conhecido
  #1 (realloc) marcado como resolvido.
- `Build_and_Testing.md`: corrigido `cc`→`CC` e `-Wall`→`-Wall -Wextra` na
  Opção 2; seção de testes atualizada (deixou de ser "a criar"); seção de
  carregamento LuaJIT agora aponta para o `ffi_loader.lua`; documentados
  `make test`/`make valgrind`.

### Adicionado (Fase 2 — ponte FFI)
- `lua/smaug/ffi_loader.lua`: ponte FFI completa. `ffi.cdef` com todas as
  assinaturas de `smaug_math.h` (f64 + i64) e `void free(void*)` da libc para
  liberar arrays brutos de comparações/argsort. `ffi.load` com fallback de paths
  (`./build/`, `../build/`, `../../build/`, `/usr/local/lib/`, nome puro) e
  detecção de SO (`.so` / `.dylib` / `.dll`).

### Concluído (Fase 1)
- Backend C f64 + i64: lifecycle, getters/setters, append dinâmico, aritmética
  (série×série e série×escalar), reduções, comparações, ordenação, utilitários.
- `Makefile` compila `build/libsmaug_math.so` com `-Wall -Wextra`, sem warnings.
- `tests/test_ops.c` passa.
- Smoke test FFI (`test_load.lua`) carrega a lib e soma uma série.

### Notas / armadilhas
- O parser de C do LuaJIT trata comentários `/* ... */` literalmente: um `*/`
  no meio de um comentário (ex. ao escrever o tipo `uint8_t*` seguido de `/`)
  fecha o comentário cedo e quebra o `ffi.cdef`. Evitar `*/` dentro de
  comentários do cdef.

### Decisões de design (I/O — Fase 5)
- Definidos os **4 formatos padrão** de I/O — CSV, JSON, XML, SQL — como o
  contrato oficial do projeto. Outros formatos ficam fora de escopo.
- Struct intermediária comum `smaug_table_t` (substitui `smaug_csv_table_t`):
  todos os leitores a produzem, todos os escritores partem de um `DataSet`.
  Isola o parsing por formato da montagem do DataSet.
- SQL = integração com **SQLite** (dependência opcional via
  `-DSMAUG_WITH_SQLITE`), não outros bancos. Design documentado; nada
  implementado ainda.

## Próximo (Fase 2)
- `lua/smaug/core/series.lua`: classe `Series` com `ffi.gc`, metamétodos
  (`__add`, `__len`, `__tostring`, `__index`/`__newindex`) e conversões
  1-based↔0-based e `nil`↔`NAN`.
- `lua/smaug/init.lua`: entry point.
- Smoke test do frontend Lua.
