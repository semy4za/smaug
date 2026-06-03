# Smaug — Compilação e Testes

**Alvo principal:** Linux (Fedora / Ubuntu). Funciona em macOS e Windows com
ajustes (ver final). Compilador GCC ≥ 11. LuaJIT necessário para o frontend.

---

## Dependências

```bash
# Fedora
sudo dnf install gcc make cmake valgrind luajit luajit-devel git

# Ubuntu/Debian
sudo apt install build-essential cmake valgrind luajit libluajit-5.1-dev git
```

Verificar: `gcc --version`, `cmake --version` (≥ 3.10), `luajit -v` (≥ 2.0.5).

No macOS o Valgrind é limitado — use `leaks` (Xcode) ou rode os testes de
memória em Linux/WSL.

---

## Opção 1 — Makefile (recomendado para desenvolvimento)

Crie `smaug/Makefile`:

```makefile
CC      = gcc
CFLAGS  = -std=c11 -fPIC -Wall -Wextra -O2 -I./include
LDFLAGS = -shared

# Backend C completo (f64 + i64)
SRCS = src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c

TARGET = build/libsmaug.so

$(TARGET): $(SRCS) | build
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^
	@echo "✓ Compilado: $@"

build:
	mkdir -p build

clean:
	rm -rf build

.PHONY: clean
```

```bash
cd smaug && make
# → build/libsmaug.so

make test       # compila e roda tests/test_alloc.c e test_ops.c
make valgrind   # roda os testes sob Valgrind (--leak-check=full)
```

## Opção 2 — Comando direto

```bash
mkdir -p build
gcc -std=c11 -fPIC -Wall -Wextra -O2 -I./include -shared \
    src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c src/smaug_ops_bool.c \
    -o build/libsmaug.so
```

## Opção 3 — CMake (cross-platform)

> **⚠️ Bloco desatualizado / decisão pendente.** Este CMake é um rascunho antigo
> e **não** está em uso (o desenvolvimento usa o Makefile no Linux e
> `scripts/windows-build.ps1` no Windows). Problemas conhecidos: usa o nome
> antigo `smaug_math` (geraria `libsmaug_math`, que o `ffi_loader` não procura
> mais — hoje é `libsmaug`/`smaug.dll`); e usa `-ffast-math`, **incompatível com
> o contrato de NaN** (permite ao compilador assumir que NaN não ocorre).
> O futuro deste bloco depende da decisão sobre portar para Lua 5.4 (ver
> "Visão de longo prazo" no Roadmap): se mantivermos só LuaJIT/FFI, o CMake pode
> ser removido; se portarmos para 5.4 com bindings C, ele será revisado e
> provavelmente promovido (CMake facilita achar headers/libs do Lua). Até lá,
> **não use este bloco como está.**

```cmake
cmake_minimum_required(VERSION 3.10)
project(smaug_math C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

if(MSVC)
    set(CMAKE_C_FLAGS_RELEASE "/O2 /Oi /Ot")
else()
    set(CMAKE_C_FLAGS_RELEASE "-O3 -march=native -ffast-math -fPIC")
    set(CMAKE_C_FLAGS_DEBUG   "-g -O0 -Wall -Wextra -Wpedantic")
endif()

include_directories(${CMAKE_SOURCE_DIR}/include)

add_library(smaug_math SHARED
    src/smaug_core.c
    src/smaug_ops_f64.c
    src/smaug_ops_i64.c
    src/smaug_ops_bool.c)

set_target_properties(smaug_math PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/build"
    PREFIX "" SUFFIX ".so")
```

```bash
mkdir build && cd build && cmake .. && make -j$(nproc)
```

---

## Flags de compilação — referência

| Flag | Quando usar |
|------|-------------|
| `-O2` | desenvolvimento padrão |
| `-O3 -march=native -ffast-math` | release / benchmarks |
| `-g -O0` | debug com gdb/valgrind |
| `-fsanitize=address` | detectar buffer overflow / use-after-free |
| `-Wall -Wextra` | sempre |

---

## Verificar o build

```bash
# símbolos exportados
nm -D build/libsmaug.so | grep smaug | head
# esperado: T smaug_f64_create, T smaug_f64_sum, T smaug_i64_create, ...
```

---

## Windows (PowerShell)

No Windows não há `make` nem Valgrind por padrão. Use o script
`scripts\windows-build.ps1`, que compila o backend em `build\smaug.dll`
(nome que o `ffi_loader.lua` procura no Windows) chamando o `gcc` diretamente, e
roda os testes C e Lua.

Toolchain recomendada: **MSYS2** (entrega `gcc` e `luajit` juntos). O script
instala tudo com a flag `-Setup`:

```powershell
# da raiz do projeto:
powershell -ExecutionPolicy Bypass -File .\scripts\windows-build.ps1 -Setup   # 1ª vez
powershell -ExecutionPolicy Bypass -File .\scripts\windows-build.ps1          # depois
```

O `-Setup` instala o MSYS2 (via `winget`, se ausente) e os pacotes
`mingw-w64-ucrt-x86_64-gcc` e `mingw-w64-ucrt-x86_64-luajit`. Se o `pacman`
reclamar de runtime desatualizado, abra o app "MSYS2 UCRT64" e rode
`pacman -Syu` uma vez (pode pedir reinício), depois repita o script.

Saída esperada: os três testes C imprimem `PASS` e os dois testes Lua imprimem
`OK — N checks passaram`, terminando em `TUDO PASSOU.`

Diferenças vs. Linux: a checagem de vazamentos (Valgrind) **não** roda no
Windows — ela continua sendo feita no Linux com `make valgrind`. Os testes de
correção são os mesmos nos dois sistemas.

A ponte FFI oficial é `lua/smaug/ffi_loader.lua` — ela declara o `ffi.cdef`
completo (f64 + i64 + bool + `smaug_free`) e faz o `ffi.load` com fallback de
paths e detecção de SO, devolvendo o namespace `C`.

```lua
-- smoke test usando o loader oficial
package.path = "./lua/?.lua;" .. package.path
local C = require("smaug.ffi_loader")

local s = C.smaug_f64_create(3)
C.smaug_f64_set(s, 0, 1.0)
C.smaug_f64_set(s, 1, 2.0)
C.smaug_f64_set(s, 2, 3.0)
assert(math.abs(C.smaug_f64_sum(s, true) - 6.0) < 1e-9)
C.smaug_f64_free(s)
print("OK — soma = 6")
```

---

## Integridade do projeto (transferência sem perdas)

Para garantir que o projeto seja transferido entre máquinas (e entre sessões de
trabalho) sem perder ou divergir arquivos, o repositório mantém um
`docs/MANIFEST.txt` com o **sha256 e a contagem de linhas** de cada arquivo
versionável (fontes, headers, Lua, docs, scripts — exceto `build/`).

```bash
make manifest    # regenera docs/MANIFEST.txt
make verify      # regenera e mostra o diff contra a versão anterior (via git)
```

Fluxo recomendado:

1. **Antes de empacotar/enviar:** rode `make manifest` e inclua o
   `MANIFEST.txt` no pacote. Ele é o inventário canônico do que deve existir.
2. **Ao receber o projeto:** rode `make manifest` de novo e compare com o
   `MANIFEST.txt` recebido (ou `git diff`). Hashes diferentes denunciam arquivos
   alterados; arquivos ausentes denunciam perda na transferência.
3. **A fonte da verdade é o projeto completo** (o `.zip`/repo), não cópias
   parciais. Nunca se presume que uma cópia anterior está atual.

O `MANIFEST.txt` é gerado por `scripts/make_manifest.sh` (portável: roda em
bash, inclusive no MSYS2/Git Bash no Windows).

---

## Estratégia de testes

O modelo de referência é o **SQLite**, cujo regime de testes define o padrão que
este projeto adota incrementalmente. Os critérios concretos derivados desse
modelo:

- Cobre-se o espaço de entradas **sistematicamente** (casos degenerados, valores
  especiais, overflow), não só os casos felizes.
- Verificam-se **invariantes** que devem valer sempre, via testes baseados em
  propriedade (property-based) com entradas aleatórias reprodutíveis.
- Os próprios testes são **validados por mutação** (injeta-se um bug e confirma-se
  que o teste falha) — um teste que passa sob bug injetado é falsa confiança.
- A **cobertura é medida**, não estimada (alvo: cobertura de *branch*, não só de
  linha — o padrão do SQLite, equivalente ao MC/DC da aviônica).
- Exercita-se o comportamento sob **falha de alocação** em cada ponto.
- **Zero** vazamento ou erro de memória (Valgrind-clean).

Nem todos os critérios estão plenamente atingidos ainda; a Fase 1.6 (ver
`Roadmap.md`) é o gate que os formaliza, e o restante evolui fase a fase. O que
já se cumpre e o que falta está marcado abaixo e no Roadmap.

Camadas de teste:

1. **Testes C** (`test_*.c`) — exercitam o backend diretamente; rodam sob
   Valgrind para garantir ausência de vazamentos e erros de memória. É a única
   camada que pode testar **falha de alocação** (interceptando `malloc`/`realloc`
   para falhar sob demanda e exercitar os caminhos de erro do `grow`).
2. **Testes Lua** (`test_*.lua`) — exercitam o sistema como o usuário o usa
   (Lua → FFI → C), validando de quebra a fronteira FFI: índices 1-based↔0-based,
   `nil`↔NA, e os sentinelas (`NAN`, `INT64_MIN`) virando `nil`.
3. **Property-based em Lua** (`test_props.lua`) — gera milhares de entradas
   aleatórias por invariante e verifica propriedades que devem valer para
   qualquer entrada. Usa um conjunto de **seeds fixas** (múltiplas, para ampliar
   o espaço sem perder determinismo); cada invariante roda N casos por seed
   (≥1000 casos no total). Em caso de falha, imprime a seed e o nº do caso para
   reprodução exata. Cada propriedade tem seu **gerador apropriado**, que respeita
   o contrato: o gerador do `sort` produz séries sem null/NaN (pois o sort
   recusa), o do `filter` injeta nulls, e há um gerador com NaN para testar a
   distinção null≠NaN. Invariantes cobertos: clone independente (anti-aliasing),
   view compartilha memória, sort é permutação (multiconjunto + monotonia),
   sort recusa null/NaN, filter↔count_true, take+inversa=identidade, astype
   ida-volta, fillna remove null e preserva NaN, e leis de Kleene (dupla negação,
   De Morgan).

Decisão registrada: o **property-based testing é feito em Lua**, porque a stack
do Smaug é fina e determinística — testar em Lua exercita o mesmo código C e
ainda cobre a fronteira FFI. A única exceção é a falha de alocação, que fica em C.

**Validação do próprio teste (mutation testing).** Para garantir que os
invariantes realmente detectam bugs (e não passam por serem fracos), o teste foi
validado injetando bugs propositais no código (ex.: fazer `clone` retornar
`self`, criando aliasing) e confirmando que o property-based **falha** — e aponta
seed+caso. Um property-based que passa sob bug injetado é falsa confiança; este
foi verificado contra isso.

O que a bateria sistemática cobre, por categoria:

- **Casos degenerados**, em toda operação: série vazia, de 1 elemento,
  toda-nula, toda-igual.
- **Valores especiais do f64**: `+Inf`, `-Inf`, `NaN` do usuário (≠ nulo),
  `-0.0`.
- **Overflow do i64**: perto de `INT64_MAX`/`INT64_MIN`; colisão com o sentinela.
- **Invariantes (property-based)**: `len(filter)==count_true(mask)`; `sort` é
  permutação; `clone` igual e independente; `take`+inversa = identidade;
  `astype` ida-e-volta; leis de Kleene (`not not b == b`, De Morgan).
- **Falha de alocação (C)**: série permanece consistente após erro de `realloc`.

### Cobertura medida (gcov)

A cobertura é **medida, não estimada**, e o relatório é um **artefato gerado**
(como o `MANIFEST.txt`), não escrito à mão — assim nunca desatualiza.

```bash
make coverage    # mede e (re)gera docs/COVERAGE.md
```

O alvo (via `scripts/make_coverage.sh`) compila uma `.so` instrumentada com
`--coverage`, linka os testes C contra ela e roda **os testes C e os testes Lua**
(que carregam a mesma `.so` via FFI) — assim a cobertura acumula os dois
caminhos de execução. Agrega com `gcov` e escreve `docs/COVERAGE.md` com a tabela
por arquivo, o total ponderado, o commit/data medidos e o status do gate.
Artefatos intermediários (`cov/`, `*.gcda`, `*.gcno`, `*.gcov`) são limpos ao
final e ignorados pelo git.

**Métrica.** O relatório mostra **linha** (básica) e **branch / "taken at least
once"** (rigorosa — padrão SQLite/aviônica). O gate da Fase 1.6 usa linha ≥ 90%
(opção A); a meta de longo prazo é branch 100%. Ver `docs/COVERAGE.md` para o
número atual e o plano.

**Regenerar a cada mudança.** Sempre que código ou testes mudarem, rode
`make coverage` e committe o `COVERAGE.md` atualizado junto — o histórico do git
passa a registrar a evolução da cobertura, commit a commit.

> Requer `gcov` (vem com o gcc no Linux). Não é confiável no Windows; a medição
> de cobertura é tarefa de Linux, como o Valgrind.

---

## Testes em C

Estrutura atual (**implementada**):

```
tests/
├── test_alloc.c    # create/free/clone/view/append, invariantes, grow — Valgrind-clean
├── test_ops.c      # resultados numéricos contra valores conhecidos
├── test_bool.c     # lógica booleana de três valores (Kleene) + agregações
├── test_series.lua # frontend: Series (f64/i64), BoolSeries, comparações, filter
├── test_dataset.lua# frontend: DataSet (CRUD, filter, sort_by, slicing, etc.)
├── test_edge.lua   # ✅ casos degenerados (vazia/1-elem/toda-nula/toda-igual) + propagação NA
├── test_special.lua# ✅ valores especiais f64 (Inf, NaN distinto de null, -0.0)
├── test_fillna.lua # ✅ fillna (Series + DataSet), preservação de NaN, sem coerção
├── test_props.lua  # ✅ property-based: 10 invariantes × 3 seeds × 400 casos (~222k checks)
└── (Fase 1.6, ainda planejado)
    └── test_allocfail.c # falha de alocação injetada (caminho de erro do grow)
```

Rode os C com `make test` (ou `make valgrind` para checar leaks) e o frontend
Lua com `make test-lua` (roda `test_series.lua`, `test_dataset.lua`,
`test_edge.lua` e `test_special.lua`). Todos
passam e os testes C são validados sob Valgrind sem vazamentos.

Exemplo de teste de operações (`tests/test_ops.c`):

```c
#include "../include/smaug.h"   /* umbrella; ou smaug_numeric.h p/ só numérico */
#include <assert.h>
#include <math.h>
#include <stdio.h>

#define EQ(a,b) (fabs((a)-(b)) < 1e-9)

int main(void) {
    smaug_series_f64_t *s = smaug_f64_create(5);
    for (size_t i = 0; i < 5; i++) smaug_f64_set(s, i, (double)(i+1)*10);
    assert(EQ(smaug_f64_sum(s, true), 150.0));
    assert(EQ(smaug_f64_mean(s, true), 30.0));
    assert(EQ(smaug_f64_min(s, true), 10.0));
    assert(EQ(smaug_f64_max(s, true), 50.0));

    smaug_f64_set_null(s, 2);
    assert(smaug_f64_is_null(s, 2));
    assert(smaug_f64_count_nonnull(s) == 4);

    smaug_f64_free(s);
    printf("PASS\n");
    return 0;
}
```

Compilar e rodar:

```bash
gcc -std=c11 -g -O0 -I./include \
    tests/test_ops.c src/smaug_core.c src/smaug_ops_f64.c \
    -lm -o build/test_ops
./build/test_ops
```

---

## Verificação de memória com Valgrind

O alvo `make valgrind` já roda os dois testes sob Valgrind. Manualmente:

```bash
gcc -std=c11 -g -O0 -I./include \
    tests/test_alloc.c src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c \
    -lm -o build/test_alloc

valgrind --leak-check=full --error-exitcode=1 ./build/test_alloc
# → HEAP SUMMARY: all heap blocks were freed -- no leaks are possible
```

Para FFI + LuaJIT, o Valgrind precisa de supressões do próprio LuaJIT:

```bash
valgrind --suppressions=/path/to/luajit.supp luajit tests/test_ffi.lua
```

---

## Onde o LuaJIT procura a `.so`

**A) Caminho relativo (mais simples no dev):**
```lua
local C = ffi.load("./build/libsmaug.so")
```

**B) `LD_LIBRARY_PATH`:**
```bash
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:./build
luajit meu_script.lua
```

**C) Instalar no sistema (produção):**
```bash
sudo cp build/libsmaug.so /usr/local/lib/ && sudo ldconfig
```

---

## Outras plataformas

- **macOS:** `brew install gcc cmake luajit`. A lib vira `libsmaug.dylib`.
- **Windows:** MSVC Build Tools + CMake + binários do LuaJIT. A lib vira
  `smaug.dll`. Adicione o diretório dela ao PATH.

---

## Troubleshooting

| Sintoma | Causa provável | Ação |
|---------|---------------|------|
| `libsmaug.so not found` | build não feito ou path errado | recompilar; conferir `ls build/` |
| `Segmentation fault` | ponteiro NULL ou OOB via FFI | rodar sob Valgrind / ASan |
| build sem otimização | modo Debug | usar `-O2`/`-O3` ou `-DCMAKE_BUILD_TYPE=Release` |
