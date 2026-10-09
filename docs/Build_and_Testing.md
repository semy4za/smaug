# Smaug — Compilação e Testes

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

**Plataformas suportadas:** Linux (Fedora, Ubuntu) e Windows (MSYS2-UCRT64).
**Compilador:** GCC ≥ 11. **Runtime:** LuaJIT ≥ 2.0.5.

---

<a id="section-dependencias"></a>

## Dependências

```bash
# Fedora
sudo dnf install gcc make valgrind luajit git

# Ubuntu/Debian
sudo apt install build-essential valgrind luajit libluajit-5.1-dev git
```

No macOS o Valgrind não funciona — use Linux para rodar a suite completa.

---

<a id="section-linux-comandos"></a>

## Linux — comandos

<a id="section-suite-completa-recomendado"></a>

### Suite completa (recomendado)

```bash
bash scripts/build.sh --all
```

Executa em sequência: build da `.so`, testes C, stress, testes Lua,
Valgrind, coverage (gcov), parity e manifest. Ferramentas ausentes podem
causar skips; parity é indicador e não barra o build. Conferir etapas e códigos
de saída, não apenas a mensagem final. Correções dos executores: [R6](Roadmap.md#r6).

<a id="section-desenvolvimento-sem-stress-sem-manifest"></a>

### Desenvolvimento (sem stress, sem manifest)

```bash
bash scripts/build.sh --skip-stress --skip-manifest
```

Sem flags, build.sh inclui stress, Lua, parity e regeneração do manifesto.

### Paridade ponta a ponta

```bash
python scripts/parity/runner.py       # Windows e Linux
# ou
python3 scripts/parity/runner.py      # Linux
```

O runner recompila a DLL/.so em `build/parity/<timestamp>/`, confirma qual
biblioteca o LuaJIT carregou, executa os 15 eixos e grava
[`PARITY_REPORT.json`](PARITY_REPORT.json) e [`PARITY_REPORT.md`](PARITY_REPORT.md).
Também compila verificações C de assinaturas/layout e registra versões,
comandos, hashes e limitações por execução. Exit 0 cobre PASS/REVIEW/OBSERVED;
exit 1 indica divergência de comportamento e exit 2 indica erro de
infraestrutura ou evidência incompleta. REVIEW aparece separado e não é
convertido em PASS. O relatório é um gate de paridade, não substitui a suíte
completa, sanitizers, Valgrind ou cobertura.

<a id="section-so-cobertura"></a>

### Só cobertura

```bash
make coverage
```

<a id="section-so-um-teste-especifico"></a>

### Só um teste específico

```bash
luajit tests/io/test_csv.lua
./build/test_io_c
```

### Schema como consumidor da biblioteca compartilhada

Os testes C habituais compilam os fontes junto com o teste. Para conferir também
os símbolos públicos e a ligação de um consumidor separado à biblioteca Linux:

```bash
make -B build/libsmaug.so
gcc -std=c11 -Wall -Wextra -Wpedantic -Werror -Iinclude \
    tests/c/test_schema.c -Lbuild -Wl,-rpath,'$ORIGIN' -lsmaug -lm \
    -o build/test_schema_shared
./build/test_schema_shared
luajit tests/io/test_schema.lua
python3 scripts/audit_io_abi.py
valgrind --leak-check=full --error-exitcode=1 ./build/test_schema_shared
```

A auditoria de ABI compara layouts C/FFI, rejeita bibliotecas incompatíveis e
verifica o diagnóstico de capacidade quando uma biblioteca ABI 1 não oferece
schema. Ela exige Linux, GCC e LuaJIT; não valida a DLL Windows.

Para instrumentar a suíte C de schema sem substituir a biblioteca usada pelo Lua:

```bash
gcc -std=c11 -g -O1 -Wall -Wextra -Iinclude \
    -fsanitize=address,undefined -fno-omit-frame-pointer \
    -fno-sanitize-recover=all tests/c/test_schema.c src/*.c -lm \
    -o build/test_schema_sanitized
ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 ./build/test_schema_sanitized
```

Esse comando exige os runtimes ASan e UBSan do compilador. Falha de compilação,
link ou inicialização não conta como validação. Este recorte não instrumenta
LuaJIT nem substitui a campanha das outras famílias e de injeção de OOM.

---

<a id="section-windows-msys2-ucrt64"></a>

## Windows — MSYS2-UCRT64

```powershell
scripts/build.ps1
```

Detecta automaticamente todos os `.c` em `src/` (incluindo parsers I/O).
Compila `smaug.dll` e todos os testes. Coverage/Valgrind rodam no Fedora.

Na retomada de schema, conferir explicitamente `test_schema` e
`io/test_schema.lua` na saída, com código de saída zero e sem skip de Lua.
O build Windows e o carregamento da DLL pelo frontend precisam ser executados
na plataforma; resultados Linux não encerram essa pendência.

### Regressões numéricas e consumidores no Windows

```powershell
python scripts/audit_windows_regressions.py
```

Exige Windows nativo, GCC/UCRT64, LuaJIT e Windows PowerShell no PATH. Executa
`build.ps1 -SkipManifest`, confere o inventário C/Lua e recompila astype, I/O e
schema com `-O2 -Wall -Wextra -Wpedantic -Werror`, diretamente com os fontes e
como consumidores da DLL. Os testes C verificam os quatro modos de
arredondamento; os casos Lua usam nearest e verificam também a tradução para
Series/DataSet. O caminho da DLL usada pelo namespace FFI é obtido do módulo
Windows que contém `smaug_abi_version`, comparado com `build/smaug.dll` e
associado ao SHA-256 dessa biblioteca.

Sete mutações em cópia temporária removem ou corrompem os fixes hexadecimal e
decimal. Cada uma precisa compilar e ser rejeitada tanto por I/O quanto por
astype, com saída de asserção e exit code 1. Falha de compilação, timeout,
crash ou ausência de checks não contam como detecção. Os fontes de produção
permanecem intactos; hashes de entrada são conferidos ao terminar.

Comandos, saídas e relatório JSON ficam em `build/windows-regressions/`.
`report.json` só recebe `status: PASS` após todas as etapas. O relatório inclui
HEAD, alterações locais, hashes, ferramentas, skips e limitações. A execução
de paridade acionada pelo build continua informativa e regenera seu relatório;
não certifica a ABI nem encerra a revisão dos 15 eixos. A campanha não executa
ASan/UBSan ou Valgrind e não substitui a auditoria Linux de OOM/ownership.

---

<a id="section-estrutura-de-testes"></a>

## Estrutura de testes

<a id="section-testes-c-anel-0-anel-3"></a>

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
| `test_schema` | descritores, leitores CSV/JSON com schema, ordem, tipos, nulidade, precisão e rejeição sem tabela parcial |
| `test_datetime_c` | datetime C: lifecycle, parse ISO 8601, componentes calendário, aritmética, comparações, sort, COW, datas negativas, bissextos |
| `test_ops_window` | ops de janela (Grupo C): multi_argsort 5 dtypes, rolling deque, cumulativas |
| `test_astype` | conversões por dtype, falhas e precisão |
| `test_allocfail` | injeção de OOM via `--wrap`; enumeração completa e rollback ainda em auditoria |
| `test_stress` | N=1M, chains, views simultâneas, ciclos |

<a id="section-testes-lua-aneis-1-2-3"></a>

### Testes Lua (Anéis 1+2+3)

As suítes vivem em subpastas por domínio: `tests/series/`, `tests/dataset/`,
`tests/io/`, `tests/props/`.

| Arquivo | O que cobre |
|---------|-------------|
| `core/test_keys.lua` / `core/test_collation.lua` | codificação de chaves e colação |
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
| `io/test_schema.lua` | schema reutilizável C/FFI, memória/arquivo, int64 exato, NUL e lifetime |
| `props/test_props.lua` | property-based: invariantes × seeds × casos |
| `props/test_integration.lua` | integração: reduções avançadas, rank, skew, kurtosis, mad, sem, funções matemáticas |

<a id="section-fixtures-de-dados-reais"></a>

### Fixtures de dados reais

| Arquivo | Descrição |
|---------|-----------|
| `tests/fixtures/pedidos_digitados.csv` | 916 linhas, 15 colunas, sep `;`, vírgula decimal, 5 empresas |
| `tests/fixtures/cotacoes.csv` | 26 linhas (13 USD_BRL + 13 SHIB_BRL), float64 de precisão |
| `tests/fixtures/cotacoes.json` | array flat de 26 records |
| `tests/fixtures/cotacoes_USD_BRL.json` | 13 records USD |
| `tests/fixtures/cotacoes_SHIB_BRL.json` | 13 records SHIB (floats pequenos: 0.00002492) |

---

<a id="section-cobertura-gcov"></a>

## Cobertura (gcov)

```bash
make coverage
# ou
bash scripts/make_coverage.sh
```

Agrega: testes C diretos, `test_allocfail` (via `--wrap`) e testes Lua (via FFI).
Resultado gerado em `docs/COVERAGE.md`.

O relatório identifica a árvore medida; não certifica a árvore atual. Branches
não são MC/DC. Exclusões exigem prova do ramo específico: OOM sem injeção não
é impossibilidade, e overflow de tamanho precisa ser analisado por operação.
Ver o [Contrato 10](CONTRACT.md#section-contrato-10-guard-de-fronteira-publica-se-testa-cov-excl-br-e-para-o-inalcancavel),
o [relatório gerado](COVERAGE.md) e [R6](Roadmap.md#r6).
O script usa listas próprias, omite headers executáveis e pode perder resultados
de gcov; essas limitações estão abertas. Também substitui temporariamente a
biblioteca em build/ e a remove ao final: recompile antes de usar a API depois.

**Plataforma autoritativa:** Linux (Fedora/Ubuntu). O `.gcda` no Windows tem
flush via FFI instável — cobertura sempre medida no Linux.

---

<a id="section-valgrind"></a>

## Valgrind

```bash
bash scripts/build.sh --all   # roda Valgrind em todos os binários
```

**Registro histórico:** campanhas anteriores registraram execução limpa.
Isso não certifica a árvore atual. Consulte a revisão da suíte para as
verificações ainda pendentes.

Correções históricas estão no [changelog](CHANGELOG.md). Registrar comando,
árvore, binários e limitações de cada nova campanha.

## Auditoria de regressões numéricas e I/O

```bash
python3 scripts/audit_numeric_regressions.py
```

Requer Linux, GCC e Valgrind. Compila cópias temporárias dos fontes, valida as
baselines de astype, falhas de alocação, I/O e schema, e introduz alterações
propositalmente incorretas. Um mutante só conta como detectado se compilar e
falhar pelo diagnóstico esperado; baseline inválida interrompe a auditoria.
Os fontes da árvore de trabalho não são alterados.

A baseline adicional `test_astype_early_underflow` intercepta `strtod_l` via
`--wrap`, devolvendo zero positivo e errno zero para os decimais pequenos
dirigidos da suíte. Isso reproduz o comportamento relevante da CRT no Linux
e exige que a recuperação use o sinal textual. Cinco mutações verificam
arredondamento dirigido, sinal, preservação da saída e zero literal. Essa
simulação não substitui a execução Windows nem compõe a cobertura gcov padrão.

<a id="section-makefile"></a>

## Makefile

```bash
make           # compila build/libsmaug.so
make coverage  # executa make_coverage.sh
make clean     # remove build/
```

O `make` detecta o Makefile com timestamp adiantado (clock skew Windows↔Linux)
e emite um aviso — inofensivo para compilação e cobertura.

---

CMake não participa dos comandos mantidos nesta página.
