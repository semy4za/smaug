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

TARGET = build/libsmaug_math.so

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
# → build/libsmaug_math.so
```

## Opção 2 — Comando direto

```bash
mkdir -p build
gcc -std=c11 -fPIC -Wall -O2 -I./include -shared \
    src/smaug_core.c src/smaug_ops_f64.c src/smaug_ops_i64.c \
    -o build/libsmaug_math.so
```

## Opção 3 — CMake (cross-platform)

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
    src/smaug_ops_i64.c)

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
nm -D build/libsmaug_math.so | grep smaug | head
# esperado: T smaug_f64_create, T smaug_f64_sum, T smaug_i64_create, ...
```

---

## Testar o carregamento via LuaJIT

`test_load.lua` na raiz:

```lua
local ffi = require("ffi")
ffi.cdef([[
    typedef uint8_t smaug_mask_t;
    typedef struct { const char *name, *dtype; bool is_view, external_alloc; } smaug_metadata_t;
    typedef struct {
        double *data; smaug_mask_t *null_mask;
        size_t size, capacity; smaug_metadata_t meta;
    } smaug_series_f64_t;
    smaug_series_f64_t* smaug_f64_create(size_t size);
    void   smaug_f64_set(smaug_series_f64_t *s, size_t idx, double val);
    double smaug_f64_sum(const smaug_series_f64_t *s, bool ignore_na);
    void   smaug_f64_free(smaug_series_f64_t *s);
]])

local C = ffi.load("./build/libsmaug_math.so")
local s = C.smaug_f64_create(3)
assert(s ~= nil)
C.smaug_f64_set(s, 0, 1.0)
C.smaug_f64_set(s, 1, 2.0)
C.smaug_f64_set(s, 2, 3.0)
assert(math.abs(C.smaug_f64_sum(s, true) - 6.0) < 1e-9)
C.smaug_f64_free(s)
print("OK — soma = 6, série liberada")
```

```bash
luajit test_load.lua   # → OK — soma = 6, série liberada
```

---

## Testes em C (a criar)

Estrutura mínima sugerida para a Fase 1:

```
tests/
├── test_alloc.c   # create/free/clone/append, invariantes, leaks
└── test_ops.c     # resultados numéricos contra valores conhecidos
```

Exemplo de teste de operações (`tests/test_ops.c`):

```c
#include "../include/smaug_math.h"
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

```bash
gcc -std=c11 -g -O0 -I./include \
    tests/test_alloc.c src/smaug_core.c src/smaug_ops_f64.c \
    -lm -o build/test_alloc

valgrind --leak-check=full --error-exitcode=1 ./build/test_alloc
```

Para FFI + LuaJIT, o Valgrind precisa de supressões do próprio LuaJIT:

```bash
valgrind --suppressions=/path/to/luajit.supp luajit tests/test_ffi.lua
```

---

## Onde o LuaJIT procura a `.so`

**A) Caminho relativo (mais simples no dev):**
```lua
local C = ffi.load("./build/libsmaug_math.so")
```

**B) `LD_LIBRARY_PATH`:**
```bash
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:./build
luajit meu_script.lua
```

**C) Instalar no sistema (produção):**
```bash
sudo cp build/libsmaug_math.so /usr/local/lib/ && sudo ldconfig
```

---

## Outras plataformas

- **macOS:** `brew install gcc cmake luajit`. A lib vira `libsmaug_math.dylib`.
- **Windows:** MSVC Build Tools + CMake + binários do LuaJIT. A lib vira
  `smaug_math.dll`. Adicione o diretório dela ao PATH.

---

## Troubleshooting

| Sintoma | Causa provável | Ação |
|---------|---------------|------|
| `libsmaug_math.so not found` | build não feito ou path errado | recompilar; conferir `ls build/` |
| `Segmentation fault` | ponteiro NULL ou OOB via FFI | rodar sob Valgrind / ASan |
| build sem otimização | modo Debug | usar `-O2`/`-O3` ou `-DCMAKE_BUILD_TYPE=Release` |
