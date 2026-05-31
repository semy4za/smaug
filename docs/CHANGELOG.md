# Changelog — Smaug

Formato baseado em [Keep a Changelog](https://keepachangelog.com/).

## [Não lançado]

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
