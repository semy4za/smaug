# Smaug — Compilação e Testes

**Plataformas suportadas:** Linux (Fedora, Ubuntu) e Windows (MSYS2-UCRT64).
**Compilador:** GCC ≥ 11. **Runtime:** LuaJIT ≥ 2.0.5.

---

## Dependências

```bash
# Fedora
sudo dnf install gcc make valgrind luajit git

# Ubuntu/Debian
sudo apt install build-essential valgrind luajit libluajit-5.1-dev git
```

No macOS o Valgrind não funciona — use Linux para rodar a suite completa.

---

## Linux — comandos

### Suite completa (recomendado)

```bash
bash scripts/build.sh --all
```

Executa em sequência: build da `.so`, testes C, stress, testes Lua,
Valgrind em todos os binários, coverage (gcov), manifest. Aborta no
primeiro erro.

### Desenvolvimento (sem stress, sem manifest)

```bash
bash scripts/build.sh
```

### Só cobertura

```bash
make coverage
```

### Só um teste específico

```bash
luajit tests/test_io_real.lua
./build/test_io_c
```

---

## Windows — MSYS2-UCRT64

```powershell
scripts/windows_build.ps1
```

Detecta automaticamente todos os `.c` em `src/` (incluindo parsers I/O).
Compila `libsmaug.dll` e todos os testes. Coverage/Valgrind rodam no Fedora.

---

## Estrutura de testes

### Testes C (Anel 0 + Anel 3)

| Binário | Checks | O que cobre |
|---------|--------|-------------|
| `test_alloc` | — | lifecycle f64/i64: create, clone, view, free |
| `test_ops` | — | aritmética, reduções, comparações, sort f64/i64 |
| `test_ops_edge` | 269 | casos degenerados: vazio, NaN, ±Inf, overflow |
| `test_bool` | — | lifecycle bool, Kleene |
| `test_bool_lifecycle` | 154 | COW em bool, integração |
| `test_string` | 118 | lifecycle string, sort, filter |
| `test_cow` | 15 | COW detach, isolamento após mutação |
| `test_io_c` | 174 | parsers CSV/JSON: CRLF, aspas RFC 4180, NA, inferência, roundtrips |
| `test_allocfail` | 1158 | OOM em todos os pontos públicos (Anéis 0+3, via `--wrap`) |
| `test_stress` | 51k+ | N=1M, chains, 200 views simultâneas, 10k ciclos |

### Testes Lua (Anéis 1+2+3)

| Arquivo | Checks | O que cobre |
|---------|--------|-------------|
| `test_series.lua` | 131 | Series f64/i64/bool: métodos, bordas, NaN |
| `test_dataset.lua` | 124 | DataSet: CRUD, filter, sort, select |
| `test_edge.lua` | 66 | casos degenerados no frontend |
| `test_special.lua` | 37 | valores especiais f64 (NaN, ±Inf) |
| `test_fillna.lua` | 25 | fillna dtype-aware |
| `test_props.lua` | 360 862 | property-based: 24 invariantes × 3 seeds × 400 casos |
| `test_i64.lua` | 69 | int64 dedicado |
| `test_string.lua` | 139 | frontend string, `.str` Tier A, astype, describe |
| `test_bool_dtype.lua` | 64 | bool como dtype pleno, Kleene, DataSet |
| `test_groupby.lua` | 46 | groupby sum/mean/min/max/count, chave composta |
| `test_concat.lua` | 35 | concat vertical, validação de schema |
| `test_join.lua` | 52 | inner/left/right/outer, chave composta |
| `test_series_ops.lua` | 73 | cumsum/cumprod/diff/shift, unique/value_counts, abs/round/clip |
| `test_dataset_ops.lua` | 61 | pivot/melt/assign, rolling DataSet |
| `test_str_tier_b.lua` | 67 | `.str` Tier B: find/slice/pad/zfill/rep/cat/split |
| `test_rolling_series.lua` | 37 | rolling sum/mean/min/max em Series |
| `test_io.lua` | 70 | I/O CSV+JSON: roundtrips, inferência, NA, bool false, aspas |
| `test_io_real.lua` | 55 | dados reais: pedidos_digitados.csv (916 linhas, sep `;`) |

### Fixtures de dados reais

| Arquivo | Descrição |
|---------|-----------|
| `tests/pedidos_digitados.csv` | 916 linhas, 15 colunas, sep `;`, vírgula decimal, 5 empresas |
| `tests/cotacoes.csv` | 26 linhas (13 USD_BRL + 13 SHIB_BRL), float64 de precisão |
| `tests/cotacoes.json` | array flat de 26 records |
| `tests/cotacoes_USD_BRL.json` | 13 records USD |
| `tests/cotacoes_SHIB_BRL.json` | 13 records SHIB (floats pequenos: 0.00002492) |

---

## Cobertura (gcov)

```bash
make coverage
# ou
bash scripts/make_coverage.sh
```

Agrega: testes C diretos, `test_allocfail` (via `--wrap`) e testes Lua (via FFI).
Resultado gerado em `docs/COVERAGE.md`.

**Métricas atuais:** linha 97.95%, branch-alvo 92.18% (66 exclusões `COV-EXCL-BR`
documentadas no rodapé de `COVERAGE.md`).

**Critério `COV-EXCL-BR`:** ramo inalcançável via API pública com justificativa
técnica auditável. Exemplos: overflow de `SIZE_MAX`, guard de realloc-shrink,
invariante matemática, OOM de syscall sem injeção de falha.

**Plataforma autoritativa:** Linux (Fedora/Ubuntu). O `.gcda` no Windows tem
flush via FFI instável — cobertura sempre medida no Linux.

---

## Valgrind

```bash
bash scripts/build.sh --all   # roda Valgrind em todos os 10 binários
```

**Estado atual:** clean em todos os 10 binários. Zero leaks, zero reads de
memória não inicializada.

Dois bugs encontrados e corrigidos pelo Valgrind no Anel 3:
- `smaug_json.c`: `col_names` (array) não liberado no caminho de sucesso.
- Writers CSV/JSON: buffer retornado sem terminador `\0`.

---

## Makefile

```bash
make           # compila build/libsmaug.so
make coverage  # executa make_coverage.sh
make clean     # remove build/
```

O `make` detecta o Makefile com timestamp adiantado (clock skew Windows↔Linux)
e emite um aviso — inofensivo para compilação e cobertura.

---

## CMake

> **⚠️ Bloco desatualizado / decisão pendente.** O CMake não está em uso.
> O desenvolvimento usa o Makefile no Linux e `scripts/windows_build.ps1`
> no Windows. O futuro deste bloco depende da decisão sobre portar para
> Lua 5.4 (ver "Visão de longo prazo" no Roadmap).
