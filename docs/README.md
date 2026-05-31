# 🐉 Smaug

**Análise de dados em Lua, com a performance do C.**

Smaug é uma biblioteca que traz funcionalidades estilo Pandas para o Lua, usando
um backend em C otimizado conectado via LuaJIT FFI (zero-copy). O objetivo é uma
ferramenta de análise tabular **leve** o suficiente para edge computing, game
engines e IoT, com performance numérica próxima a NumPy.

---

## Por quê

Python + Pandas é a ferramenta padrão para dados tabulares, mas é pesado:
import lento, footprint alto e difícil de embarcar. Lua é o oposto — runtime de
~400KB, e o LuaJIT traz JIT + FFI nativo. Smaug junta os dois: **frontend Lua
expressivo, backend C rápido**.

## Stack

| Camada | Tecnologia | Responsabilidade |
|--------|-----------|------------------|
| Frontend | Lua 5.1 / LuaJIT | Classes `Series`/`DataSet`, API, metamétodos |
| Bridge | LuaJIT FFI | Passagem de dados zero-copy, chamadas nativas |
| Backend | C11 | Operações numéricas, malloc/free, loops SIMD-friendly |
| Build | Makefile / CMake | Portabilidade Linux/macOS/Windows |

## Alvos não-funcionais

| Aspecto | Alvo |
|---------|------|
| Footprint compilado | < 2 MB |
| Startup (require + init) | < 100 ms |
| Performance numérica | ≥ 80% de NumPy em operações grandes |
| Type safety | zero segfaults silenciosos |
| Compatibilidade de API | ~90% Pandas |

---

## Arquitetura em camadas

```
┌─────────────────────────────────────────────┐
│  Aplicação do usuário (Lua)                  │
│  local df = smaug.read_csv("dados.csv")      │
│  local total = df["salario"]:sum()           │
├─────────────────────────────────────────────┤
│  Frontend Lua                                │
│  Series, DataSet, metamétodos, validação     │
├─────────────────────────────────────────────┤
│  Bridge FFI (ffi.cdef + ffi.load + ffi.gc)   │
│  Assinaturas C, hooks de GC, sem lógica       │
├─────────────────────────────────────────────┤
│  Backend C (libsmaug_math.so)                │
│  Structs tipadas, arrays contíguos, bitmasks  │
└─────────────────────────────────────────────┘
```

Fluxo de uma chamada como `df["idade"]:sum()`: o `__index` do DataSet devolve a
`Series` da coluna, o método `:sum()` em Lua chama `C.smaug_f64_sum(ptr, ...)`
via FFI, o C executa o loop acumulador e devolve um `double` direto ao Lua.

---

## Decisões de design

**Tipos separados, sem coerção implícita.** Cada tipo numérico tem sua própria
struct (`smaug_series_f64_t`, `smaug_series_i64_t`) e seu próprio conjunto de
funções. Sem casting silencioso — o usuário decide explicitamente. Evita classes
inteiras de bugs e elimina overhead de conversão nos loops.

**Null handling por bitmask paralelo.** Cada série carrega um array
`smaug_mask_t` (`uint8_t`) onde `0xFF` = válido e `0x00` = nulo (NA). É 8× mais
RAM que bit-packing, mas cache-friendly, sem complexidade bitwise, e funciona
para qualquer tipo (inteiros e strings não têm NaN nativo).

**Imutabilidade por padrão.** Operações (`add`, `mul`, `filter`, …) sempre
retornam uma série nova; nunca modificam in-place. Só `set`/`set_null`/`append`
mutam. Isso evita bugs de aliasing. A exceção são **views** (slices sem cópia),
que são read-only.

**Views são zero-copy e têm dono externo.** `smaug_f64_view(s, start, len)`
aponta para dentro do array da série-pai. A flag `external_alloc=true` impede que
o `free` da view libere a memória da pai — mas a view **não pode sobreviver** à
pai (use `clone` se precisar).

**Indexação 1-based no Lua, 0-based no C.** Convenção de cada mundo respeitada; a
conversão acontece no wrapper Lua.

**Memória manual no C, `ffi.gc` no Lua.** O backend controla seu próprio
malloc/free (sem overhead de GC). No Lua, cada struct retornado é registrado com
`ffi.gc(ptr, C.smaug_f64_free)` para limpeza automática.

---

## Estrutura do projeto

```
smaug/
├── include/
│   └── smaug_math.h        # Contrato público (tipos + assinaturas f64/i64)
├── src/
│   ├── smaug_core.c        # Lifecycle: create/free/clone/view, get/set, append
│   ├── smaug_ops_f64.c     # Operações float64
│   └── smaug_ops_i64.c     # Operações int64
├── docs/
│   ├── README.md           # Este arquivo
│   ├── API_Reference.md    # Referência da API C
│   ├── Build_and_Testing.md# Compilação e testes
│   └── Roadmap.md          # Fases futuras + design do frontend Lua
└── build/                  # Output da compilação (libsmaug_math.so)
```

A criar (ver `Roadmap.md`): sistema de build, `lua/smaug/` (frontend), `tests/`.

---

## Status rápido

| Camada | Status |
|--------|--------|
| Header `smaug_math.h` | ✅ Completo e estável |
| Backend C — f64 (lifecycle + ops) | ✅ Completo |
| Backend C — i64 (lifecycle + ops) | ✅ Completo |
| Sistema de build | ❌ A criar |
| Frontend Lua | ❌ A criar |
| Testes | ❌ A criar |
| CSV I/O | ❌ Fase 5 |

Detalhes em `API_Reference.md` (o que cada função faz) e `Roadmap.md` (o que vem
a seguir).
