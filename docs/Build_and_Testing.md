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
luajit tests/io/test_csv.lua
./build/test_io_c
```

---

## Windows — MSYS2-UCRT64

```powershell
scripts/build.ps1
```

Detecta automaticamente todos os `.c` em `src/` (incluindo parsers I/O).
Compila `libsmaug.dll` e todos os testes. Coverage/Valgrind rodam no Fedora.

---

## Estrutura de testes

### Testes C (Anel 0 + Anel 3)

| Binário | O que cobre |
|---------|-------------|
| `test_alloc` | lifecycle f64/i64: create, clone, view, free |
| `test_ops` | aritmética, reduções, comparações, sort f64/i64 |
| `test_ops_edge` | casos degenerados: vazio, NaN, ±Inf, overflow |
| `test_bool` | lifecycle bool, Kleene |
| `test_bool_lifecycle` | COW em bool, integração |
| `test_string` | lifecycle string, sort, filter |
| `test_cow` | COW detach, isolamento após mutação |
| `test_io_c` | parsers CSV/JSON: CRLF, aspas RFC 4180, NA, inferência, UTF-8 `\uXXXX`, roundtrips |
| `test_datetime_c` | datetime C: lifecycle, parse ISO 8601, componentes calendário, aritmética, comparações, sort, COW, datas negativas, bissextos |
| `test_ops_window` | ops de janela (Grupo C): multi_argsort 5 dtypes, rolling deque, cumulativas |
| `test_allocfail` | OOM em todos os pontos públicos (Anéis 0+3, via `--wrap`); inclui Grupo A/B e datetime |
| `test_stress` | N=1M, chains, views simultâneas, ciclos |

### Testes Lua (Anéis 1+2+3)

As suítes vivem em subpastas por domínio: `tests/series/`, `tests/dataset/`,
`tests/io/`, `tests/props/`.

| Arquivo | O que cobre |
|---------|-------------|
| `series/test_constructors.lua` | Series f64/i64/bool: construtores, aritmética, lifecycle, map, astype |
| `series/test_access.lua` | acesso, edge cases, fillna |
| `series/test_reduce.lua` | reduções, valores especiais f64 (NaN, ±Inf) |
| `series/test_stat.lua` | stat, transformações, cumsum/diff/shift |
| `series/test_window.lua` | rolling, expanding, cum*, diff, shift, ffill/bfill, argmin/argmax |
| `series/test_predicates.lua` | predicados, duplicatas, searchsorted, rep_each |
| `series/test_selection.lua` | at/iat, where, mask, ifelse, isna/notna |
| `series/test_str.lua` | `.str` Tier A+B+C completo |
| `series/test_dt.lua` | `.dt` base + F.3 estendido |
| `series/test_categorical.lua` | categorical + completude datetime/categorical |
| `dataset/test_core.lua` | core, ops, rename, pivot_table, stack, unstack, explode |
| `dataset/test_relational.lua` | groupby, concat, join |
| `dataset/test_stat.lua` | corr/cov, equals, compare, duplicated, drop_duplicates |
| `dataset/test_io_support.lua` | at/iat, insert, to_dict, from_dict, to_markdown, to_string |
| `io/test_csv.lua` | I/O CSV + dados reais (pedidos_digitados.csv, sep `;`) |
| `io/test_json.lua` | I/O JSON + unicode |
| `props/test_props.lua` | property-based: invariantes × seeds × casos |
| `props/test_integration.lua` | integração: reduções avançadas, rank, skew, kurtosis, mad, sem, funções matemáticas |

### Fixtures de dados reais

| Arquivo | Descrição |
|---------|-----------|
| `tests/fixtures/pedidos_digitados.csv` | 916 linhas, 15 colunas, sep `;`, vírgula decimal, 5 empresas |
| `tests/fixtures/cotacoes.csv` | 26 linhas (13 USD_BRL + 13 SHIB_BRL), float64 de precisão |
| `tests/fixtures/cotacoes.json` | array flat de 26 records |
| `tests/fixtures/cotacoes_USD_BRL.json` | 13 records USD |
| `tests/fixtures/cotacoes_SHIB_BRL.json` | 13 records SHIB (floats pequenos: 0.00002492) |

---

## Cobertura (gcov)

```bash
make coverage
# ou
bash scripts/make_coverage.sh
```

Agrega: testes C diretos, `test_allocfail` (via `--wrap`) e testes Lua (via FFI).
Resultado gerado em `docs/COVERAGE.md`.

**Métricas (Fedora, gcov):** linha e branch-alvo com exclusões `COV-EXCL-BR`
documentadas — geradas em `docs/COVERAGE.md`, nunca cravadas aqui. A meta de
≥95% branch-alvo foi atingida na campanha de hardening; o que resta nos parsers
são branches de inputs malformados muito específicos (rendimento decrescente).

**Critério `COV-EXCL-BR`:** ramo inalcançável via API pública com justificativa
técnica auditável. Exemplos: overflow de `SIZE_MAX`, guard de realloc-shrink,
invariante matemática, OOM de syscall sem injeção de falha.

**Plataforma autoritativa:** Linux (Fedora/Ubuntu). O `.gcda` no Windows tem
flush via FFI instável — cobertura sempre medida no Linux.

---

## Valgrind

```bash
bash scripts/build.sh --all   # roda Valgrind em todos os binários
```

**Estado atual:** clean em todos os binários. Zero leaks, zero reads de
memória não inicializada, todos os blocos alocados liberados.

Bugs encontrados e corrigidos pelo Valgrind:
- **Anel 3 (sessão inicial):** `smaug_json.c` — `col_names` (array) não liberado
  no caminho de sucesso. Writers CSV/JSON — buffer retornado sem terminador `\0`.
- **Anel 3 (sessão de hardening):** ambos os parsers — `strdup`s de `col_names`
  vazavam quando OOM acontecia depois do strdup (calloc de `dtypes`, alocação
  de `tbl`, falha de `smaug_X_create` no loop final). Corrigido com transferência
  de ownership marcada (`col_names[c] = NULL`) e cleanup robusto nos paths de erro.

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
> O desenvolvimento usa o Makefile no Linux e `scripts/build.ps1`
> no Windows. O futuro deste bloco depende da decisão sobre portar para
> Lua 5.4 (ver "Visão de longo prazo" no Roadmap).
