# Changelog — Smaug

Registro de o que mudou e por que, em ordem cronológica reversa.
Uma entrada por sessão de trabalho. Foco no que não é óbvio pelo diff:
decisões, achados, motivações.

---

## 2026-06-14 · f66ba99 — Anel 3 completo + hardening I/O

### Adicionado — Anel 3: I/O CSV e JSON

Parsers próprios em C puro, zero dependências externas. Fronteira
`smaug_table_t` como contrato entre leitores e o frontend Lua — todo
leitor produz uma `smaug_table_t`, o frontend consome e monta um `DataSet`.
Adicionar novos formatos (Parquet, SQLite) é implementar um novo produtor
sem tocar no núcleo.

```lua
-- leitura com inferência automática de tipo
local ds = smaug.read_csv("pedidos.csv", {sep = ";"})
local ds = smaug.read_json("cotacoes.json")

-- escrita
ds:to_csv("saida.csv")
ds:to_json("saida.json", {pretty = true})

-- em memória (sem arquivo)
local buf = ds:to_csv_mem()
local ds2 = smaug.read_csv_mem(buf)
```

Inferência de tipo no CSV: cada coluna é testada em ordem `int64 → float64 → bool → string`.
Coluna mista sobe para o tipo mais abrangente. Células vazias e `NA`/`null`/`N/A`/`nan`/`NaN`/`NULL`
viram null. Separador, aspas e header configuráveis.

JSON suporta o formato array de records `[{...}, {...}]` com escape completo
(`\n`, `\t`, `\\`, `\"`, `\uXXXX`) e writer compacto/pretty. `NaN` → `null`
no JSON (sem representação JSON para NaN).

### Adicionado — test_io_c.c (174 checks)

Cobertura C direta dos parsers: CRLF, CR-only, sem newline final, TSV,
sem header, aspas RFC 4180, aspas escapadas, aspas não fechadas, newline
em campo, NA padrão e customizados, inferência de todos os tipos, linha curta,
linha com 20 colunas, campo longo > 32 bytes, writer com NaN/sep/quote/sem-header/arquivo,
JSON completo, roundtrips, erros de arquivo/path inválido.

### Adicionado — test_io_real.lua (55 checks) com dados reais

`tests/pedidos_digitados.csv`: 916 linhas, 15 colunas, separador `;`, vírgula
decimal, 5 empresas (DB10/DC10/DG10/DP10/DS10), 5 marcas de produto.
Valida leitura, groupby, filter, join e roundtrips sobre dados reais.

Fixtures de cotações: `cotacoes.csv`, `cotacoes.json`, `cotacoes_USD_BRL.json`,
`cotacoes_SHIB_BRL.json` — float64 de alta precisão e valores pequenos (SHIB: 0.00002492).

### Adicionado — allocfail nos parsers I/O (1098 → 1158 verificações)

9 funções de injeção de falha: `af_csv_read_mem`, `af_csv_read_quoted`,
`af_csv_read_many_rows`, `af_csv_write`, `af_json_read_mem`,
`af_json_read_many_records`, `af_json_read_long_string`, `af_json_write`,
`af_table_free_partial`. Toda falha de malloc em qualquer ponto dos parsers
resulta em retorno gracioso sem crash.

### Corrigido — dois bugs encontrados pelo Valgrind

`smaug_json.c`: `col_names` (array de ponteiros) não era liberado no caminho
de sucesso — 8 bytes por coluna vazavam.

`smaug_csv.c` + `smaug_json.c`: writers retornavam buffer sem terminador `\0`.
`strstr` e similares liam além do conteúdo válido. Corrigido: ambos os writers
adicionam `\0` ao final sem contar em `out_len`.

### Adicionado — COV-EXCL-BR nos parsers

66 exclusões totais (era 57). Guards de OOM/syscall inalcançáveis via API
pública nos parsers CSV e JSON documentados com justificativa técnica.

### Cobertura

Linha 97.95% (1909/1949). Branch-alvo 92.18% (1981/2149, 66 excluídos).

---

## 2026-06-12 · Ring 1 completo

### Adicionado — `df[mask]` indexação por BoolSeries

`DataSet.__index` passa a despachar para `filter` quando a chave é uma
`Series<bool>`. Açúcar sobre `:filter()` — sem semântica nova.

```lua
local ds = smaug.DataSet({
    {"idade", {17, 32, 25}, "int64"},
    {"nome",  {"Ana", "Bruno", "Carol"}, "string"},
})
local adultos = ds[ds.idade:gt(18)]
```

### Adicionado — `.str` Tier A completo

Accessor `.str` em `Series` do tipo string. 7 métodos + `replace`.
Null propaga; erro claro em dtype errado.

```lua
local ds = smaug.DataSet({{"cidade", {"  São Paulo  ", "rio", "MINAS"}, "string"}})
local normalizado = ds.cidade.str:strip():lower()
```

Métodos: `len` (→ int64), `lower`, `upper`, `strip`, `replace` (→ string),
`contains`, `startswith`, `endswith` (→ BoolSeries).

### Adicionado — comparações `ge`/`le`/`ne`

Para f64, i64 e string. Completam o conjunto `gt`/`lt`/`eq`/`ge`/`le`/`ne`.

### Adicionado — `Series:map(fn, dtype?)`

Aplica função Lua elemento a elemento. `nil` retornado → null. Dtype
inferido do primeiro retorno não-null; tipos mistos → erro com índice.

### Corrigido — `f64` div/0 → null (uniforme com i64)

`smaug_f64_div` e `smaug_f64_div_scalar` passam a produzir `null` quando
o divisor é zero. Comportamento agora uniforme entre f64 e i64.

### Decisão — Broadcasting rejeitado para Anel 1

Broadcasting de `Series(length=1)` não desbloqueia capacidades novas além
do escalar direto. Broadcasting real pertence ao `Tensor2D`/ML (Anel 5).
Removido da dívida técnica; registrado como decisão explícita.

---

## 2026-06-11 · 9807b46

### Corrigido — `test_string_ux()` órfã

30 checks de UX de string estavam escritos mas nunca executados — função
definida e não chamada. Qualquer máquina reportava 59 checks; o arquivo tinha 90.

### Corrigido — rodapé do COVERAGE.md incompleto

O gerador suprimia o segundo ramo de linhas com dois ramos excluídos.
Resultado: aritmética dizia 19 exclusões, rodapé listava 17. Fix: remove
o guard. O rodapé agora espelha a aritmética real.

---

## 2026-06-10 · f73c928

### Adicionado — BoolSeries como coluna de primeira classe

`DataSet` aceitava `BoolSeries` em `add_column`, mas `head`/`tail`/`filter`/
`describe`/`dropna`/`fillna`/`argsort` explodiam. Princípio adotado: toda coluna
aceita pelo DataSet deve funcionar em toda a API do DataSet, sem exceções ocultas.

Corrigido também um bug de precedência no `argsort` (comparador Lua com `and`/`or`
sem parênteses — resultado silenciosamente errado em certas ordenações).

### Adicionado — UX de string

- `fillna` dtype-aware: string aceita string, número aceita número.
- `describe` para string: count, nulls, unique, top, freq.
- `astype` string↔numérico com conversão tolerante por elemento:
  elementos inconversíveis viram null, nunca erro.

```lua
local s = Series.from_table({"1.5", "2.0", "abc", smaug.NA}, "string")
local f = s:astype("float64")
-- f:get(3) == nil  (null, não erro)
-- f:get(1) == 1.5
```

### Adicionado — API pública do DataSet

- `smaug.DataSet({{...}})` via `__call`.
- `Series.full(n, val)` para broadcast de escalares.
- `df["col"] = serie_ou_escalar` via `__newindex`.
- `DataSet.update_column`.
- `DataSet.methods` exposto para extensão por módulos externos (usado pelo I/O).

---

## 2026-05 · endurecimento Anel 0 (frentes A, B, C)

### Frente B — OOM nas ops

`test_allocfail` estendido para cobrir todas as ops aritméticas (f64/i64/bool/string).
579 → 767 → 1098 → 1158 verificações. Valgrind-clean.

### Milestone — branch-alvo 100% no núcleo (MC/DC completo)

1095/1095 ramos do núcleo cobertos. Jornada: 75.42% → 100.00%.
19 exclusões `COV-EXCL-BR` com justificativa auditável.

### Frente A — guards de input

O engine passou a não confiar no caller: toda fronteira pública do C valida
ponteiro/argumento/índice e comunica o resultado via `smaug_status_t`.

### Frente C — semântica fechada

- Propagação estrita de null: qualquer operando null → resultado null.
- Tabela-verdade Kleene completa para bool.

---

## 2026-04 · contrato defensivo do C + COW

### Copy-on-Write em views (f64/i64)

Views compartilham o buffer da série pai zero-copy até a primeira escrita.
Toda mutação materializa um buffer privado; a pai nunca é tocada.

### Contrato defensivo — `get` Shape 1

`f64_get`/`i64_get` passaram a retornar valor + escrever `smaug_status_t*`.
Eliminou a colisão entre índice inválido e valor legítimo.

---

## 2026-03 · fase string completa

### String como dtype de primeira classe

Percurso: esqueleto (struct offset-based, estilo Arrow) → backend C
(lifecycle, acesso, mutação, comparações, filter/take, sort/argsort) →
frontend Lua.

String vazia `""` distinta de NULL. Ordenação lexicográfica por bytes.

### `test_allocfail` estendido para string

10 helpers `af_str_*` cobrem cada ponto de alocação. Valgrind-clean.

---

## 2026-02 · endurecimento (property-based, cobertura, fillna)

### Property-based tests

24 invariantes × 3 seeds × ~400 casos = 360 862 checks.
Invariantes: clone independente, view compartilha memória, sort é permutação,
filter↔count_true, astype ida-volta, fillna remove null/preserva NaN, Kleene.

### `fillna`

`Series:fillna(value)` e `DataSet:fillna(value | {col=value})`.
Sem coerção. Preserva NaN. Original imutável.

### Contrato NaN≠null fixado

`NaN` deixou de virar null. `sort`/`argsort` (f64) recusam NaN além de null.

---

## 2026-01 · fases 1–4 (backend C, frontend Lua, DataSet, bool)

### DataSet

Coleção de Series alinhadas. CRUD de colunas com validação de comprimento
e nome único. `filter`/`sort_by`/`head`/`tail`/`iloc`/`take`/`sample`/`select`.

### Bool e lógica Kleene

`Series<bool>` com lógica de três valores. `Series:gt`/`lt`/`eq` → `Series<bool>`.

### Frontend Lua (Series)

Despacho por dtype via tabela de descritores. `ffi.gc` para limpeza automática.
Views read-only com `_parent` para impedir GC da série pai.

### Backend C (f64 + i64)

Lifecycle, getters/setters, append dinâmico, aritmética, reduções,
comparações, sort/argsort. Zero warnings (`-Wall -Wextra`).
