# Changelog — Smaug

Formato baseado em [Keep a Changelog](https://keepachangelog.com/).

## [Não lançado]

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
