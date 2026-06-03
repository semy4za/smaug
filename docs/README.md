# 🐉 Smaug

**Análise de dados tabulares em Lua, com um backend em C.**

Smaug traz uma API estilo pandas/numpy para Lua, sobre um backend em C conectado
via LuaJIT FFI. O alvo é uma ferramenta de dados **leve** o bastante para edge
computing, IoT e game engines — onde Python+pandas é pesado demais — sem abrir
mão de performance numérica.

```lua
local smaug = require("smaug")

-- Uma coluna de dados, com suporte a nulos (NA)
local s = smaug.Series.from_table({10, 20, smaug.NA, 40}, "float64")
print(s:sum())            -- 70      (ignora NA por padrão)
print(s:mean())           -- 23.33
print(s:count_nonnull())  -- 3

-- Uma tabela com colunas tipadas
local df = smaug.DataSet.from_columns({
  {"idade",   {25, 30, 35},              "int64"},
  {"salario", {5000.0, 7000.0, 9000.0},  "float64"},
})

-- Filtra linhas: quem tem mais de 27 anos
local senior = df:filter(df:col("idade"):gt(27))
print(senior:nrows())     -- 2
```

> **Status:** backend numérico (float64, int64, bool) e frontend (`Series`,
> `BoolSeries`, `DataSet`) implementados e endurecidos. `string`, I/O (CSV/JSON)
> e demais tipos são fases futuras — ver [Roadmap](Roadmap.md).

---

## Por quê

Python + pandas é o padrão para dados tabulares, mas é pesado: import lento,
footprint alto, difícil de embarcar. Lua é o oposto — runtime de ~400 KB — e o
LuaJIT traz JIT + FFI nativo. Smaug junta os dois: **frontend Lua expressivo,
backend C rápido**, com a passagem de dados pela fronteira FFI sem cópia.

## Como rodar

Requer **LuaJIT** e um compilador C (gcc/clang). No Linux:

```bash
make                       # compila o backend -> build/libsmaug.so
make test                  # testes em C (inclui falha de alocacao)
make test-lua              # testes do frontend Lua
```

No Windows há o script `scripts/windows-build.ps1` (compila a `smaug.dll` e roda
os testes); detalhes em [Build_and_Testing.md](Build_and_Testing.md).

Para usar na sua aplicação, garanta que o `package.path` encontre `lua/` e que a
biblioteca compilada esteja em `build/`, e então `require("smaug")`.

## O que existe hoje

| Componente | Estado |
|------------|--------|
| Backend C — `float64`, `int64` (lifecycle + aritmética/reduções/comparações/sort/take/filter) | ✅ |
| Backend C — `bool` (lógica de Kleene, 3 valores) | ✅ |
| Frontend — `Series` (despacho por dtype), `BoolSeries`, `DataSet` | ✅ |
| `fillna`, `astype`, `clone`, `view`, `describe` | ✅ |
| Build (`Makefile`) + portabilidade Windows | ✅ |
| **Endurecimento (Fase 1.6)** — cobertura medida, property-based, falha de alocação | ✅ **fechada** |
| Tipo `string` | ❌ próxima fase |
| Contrato defensivo do backend C (validação de entrada) | ❌ planejado, antes da `string` |
| I/O — CSV, JSON, XML, SQL | ❌ fase futura |

O **rigor de teste** é parte do projeto, não um acréscimo. A suíte atual: 4
testes em C (incluindo `test_allocfail`, que força `malloc`/`realloc` a falhar em
cada ponto), 7 suítes em Lua (~222 mil verificações somando o property-based),
tudo Valgrind-clean, com cobertura de linha **medida** em ~90%. O modelo de
referência é o SQLite; ver [Build_and_Testing.md](Build_and_Testing.md) e
[COVERAGE.md](COVERAGE.md).

---

## Stack

| Camada | Tecnologia | Responsabilidade |
|--------|-----------|------------------|
| Frontend | Lua 5.1 / LuaJIT | `Series`/`BoolSeries`/`DataSet`, API, metamétodos, validação |
| Bridge | LuaJIT FFI | Passagem de dados sem cópia, `ffi.gc` para limpeza |
| Backend | C11 | Operações numéricas, gerência de memória, bitmask de nulos |

Fluxo de uma chamada como `df:col("idade"):sum()`: o frontend devolve a `Series`
da coluna, `:sum()` chama `C.smaug_i64_sum(ptr, ...)` via FFI, o C roda o loop e
devolve o número direto ao Lua.

## Decisões de design

Estas são as escolhas que moldam o comportamento do Smaug — úteis para quem vai
contribuir ou depender do projeto:

**Tipos separados, sem coerção implícita.** Cada tipo numérico tem sua própria
struct (`smaug_series_f64_t`, `smaug_series_i64_t`) e seu conjunto de funções.
Sem casting silencioso — o usuário converte explicitamente (`astype`). Preencher
um `int64` com `1.5` é erro, não truncamento.

**Null ≠ NaN.** Nulo (NA) é *ausência*, registrada num bitmask paralelo
(`0xFF` = válido, `0x00` = nulo). `NaN` é um valor de ponto flutuante presente,
porém indefinido. Os dois **nunca** se convertem: `sort` recusa ambos, mas por
razões distintas; `fillna` preenche nulos e preserva NaN. Inteiros e strings não
têm NaN — o bitmask dá suporte a nulos para qualquer tipo.

**Imutabilidade por padrão.** Operações (`add`, `filter`, `sort`, …) retornam uma
série nova; nunca modificam in-place. Só `set`/`set_null`/`append` mutam. Evita
bugs de aliasing. A exceção são **views** (fatias sem cópia), que compartilham a
memória da série-pai e não devem sobreviver a ela (use `clone` se precisar).

**Indexação 1-based no Lua, 0-based no C.** Cada mundo na sua convenção; a
conversão acontece no wrapper Lua, que também valida os índices.

**Memória manual no C, `ffi.gc` no Lua.** O backend controla seu próprio
malloc/free. No Lua, cada ponteiro é registrado com `ffi.gc(...)` para liberação
automática — sem o usuário gerenciar memória.

## Estrutura do projeto

```
smaug/
├── include/          # 5 headers, separados por responsabilidade
│   ├── smaug_types.h    # tipos base (mask, metadata, structs) — zero funções
│   ├── smaug_core.h     # lifecycle, get/set, append, smaug_free
│   ├── smaug_numeric.h  # aritmetica/reducoes/comparacoes/sort/utils (f64+i64)
│   ├── smaug_bool.h     # logica de Kleene
│   └── smaug.h          # umbrella
├── src/              # backend C (core, ops_f64, ops_i64, ops_bool)
├── lua/smaug/        # frontend: init, ffi_loader, core/{series,boolseries,dataset}
├── tests/            # 4 em C + 7 suites Lua (ver Build_and_Testing.md)
├── scripts/          # make_manifest.sh, make_coverage.sh, windows-build.ps1
└── docs/             # esta doc
```

## Documentação

| Documento | Conteúdo |
|-----------|----------|
| [Roadmap.md](Roadmap.md) | Fases, visão de longo prazo (viz, ML, ORM, port Lua 5.4), dívida técnica |
| [API_INDEX.md](API_INDEX.md) | Catálogo de todos os métodos (Series, BoolSeries, DataSet) e funções C |
| [API_Reference.md](API_Reference.md) | Referência detalhada da API |
| [Build_and_Testing.md](Build_and_Testing.md) | Compilação, testes, estratégia de qualidade |
| [COVERAGE.md](COVERAGE.md) | Cobertura medida (gerado por `make coverage`) |
| [CODE_REVIEW.md](CODE_REVIEW.md) | Achados de revisão e seu tratamento |
| [CHANGELOG.md](CHANGELOG.md) | Histórico de mudanças |
