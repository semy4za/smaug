# Changelog — Smaug

Registro de o que mudou e por que, em ordem cronológica reversa.
Uma entrada por sessão de trabalho. Foco no que não é óbvio pelo diff:
decisões, achados, motivações. Exemplos de código onde o comportamento
novo vale ser visto, não só descrito.

---

## 2026-06-12 · Ring 1 completo

### Adicionado — `df[mask]` indexação por BoolSeries
`DataSet.__index` passa a despachar para `filter` quando a chave é uma
`BoolSeries`. Açúcar sobre `:filter()` — sem semântica nova.

```lua
local payload = {
    {"idade", {17, 32, 25}, "int64"},
    {"nome",  {"Ana", "Bruno", "Carol"}, "string"},
}
local ds = smaug.DataSet(payload)
local adultos = ds[ds.idade:gt(18)]
```

### Adicionado — `.str` Tier A completo
Accessor `.str` em `Series` do tipo string. Proxy retornado por `s.str`;
7 métodos + `replace`. Null propaga; erro claro em dtype errado.

```lua
local payload = {{"cidade", {"  São Paulo  ", "rio", "MINAS"}, "string"}}
local ds = smaug.DataSet(payload)
local normalizado = ds.cidade.str:strip():lower()
```

Métodos: `len` (→ int64), `lower`, `upper`, `strip`, `replace` (→ string),
`contains`, `startswith`, `endswith` (→ BoolSeries).

### Adicionado — comparações `ge`/`le`/`ne`
Para f64, i64 e string — backend C + wrappers Lua. Completam o conjunto
`gt`/`lt`/`eq`/`ge`/`le`/`ne` nos três tipos.

```lua
local payload = {{"vendas", {10, 20, 30, 40}, "float64"}}
local ds = smaug.DataSet(payload)
local validos = ds[ds.vendas:ge(20) * ds.vendas:le(35)]  -- [20, 30]
```

### Adicionado — `Series:map(fn, dtype?)`
Aplica função Lua elemento a elemento. `nil` retornado → null. Dtype
inferido do primeiro retorno não-null; tipos mistos → erro com índice.
Dtype explícito prevalece.

```lua
local payload = {{"preco", {10, 20, nil, 40}, "float64"}}
local ds = smaug.DataSet(payload)
local com_taxa = ds.preco:map(function(v) if v then return v * 1.1 end end)
```

### Corrigido — `f64` div/0 → null (uniforme com i64)
`smaug_f64_div` e `smaug_f64_div_scalar` passam a produzir `null` quando
o divisor é zero, eliminando `±Inf`/`NaN` silenciosos. Comportamento
agora uniforme entre f64 e i64 — div/0 não passa.

```lua
local payload = {{"vendas", {100.0, 250.0, 0.0}, "float64"}}
local ds = smaug.DataSet(payload)
local r = ds.vendas / 0   -- [null, null, null] — não [Inf, Inf, NaN]
```

### Decisão — Broadcasting rejeitado para Ring 1
Broadcasting de `Series(length=1)` não desbloqueia capacidades novas além
do escalar direto (já existente). Broadcasting real pertence ao `Tensor2D`/ML.
Removido da dívida técnica; registrado como decisão explícita no Roadmap.

---

## 2026-06-11 · 9807b46

### Corrigido — `test_string_ux()` órfã
30 checks de UX de string (fillna dtype-aware, describe, astype string↔numérico)
estavam escritos mas nunca executados — a função estava definida e não chamada.
Qualquer máquina reportava 59 checks; o arquivo tinha 90. Fix: uma linha.

### Corrigido — rodapé do COVERAGE.md incompleto
O gerador (`make_coverage.sh`) usava uma flag `done` que suprimia o segundo ramo
de linhas com dois ramos excluídos (`bool:48` com `&&`, `str:218` com `if` simples).
Resultado: aritmética dizia 19 exclusões, rodapé listava 17. Fix: remove o guard.
O rodapé agora lista 19 itens, espelhando os 19 ramos brutos reais.

Dois bugs da mesma classe: ferramenta de garantia reportando menos que a realidade.

---

## 2026-06-10 · f73c928

### Adicionado — BoolSeries como coluna de primeira classe
`DataSet` aceitava `BoolSeries` em `add_column`, mas `head`/`tail`/`filter`/
`describe`/`dropna`/`fillna`/`argsort` explodiam. Princípio adotado: toda coluna
aceita pelo DataSet deve funcionar em toda a API do DataSet, sem exceções ocultas.
Implementado em Lua puro com `ffi.new` + âncoras `_base/_nbase` para o GC.

Corrigido também um bug de precedência no `argsort` (comparador Lua com `and`/`or`
sem parênteses — resultado silenciosamente errado em certas ordenações).

### Adicionado — UX de string
- `fillna` dtype-aware: string aceita string, número aceita número, sem coerção.
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
- `smaug.DataSet({{"col", dados}, ...})` via `__call` na metatabela.
- `Series.full(n, val)` para broadcast de escalares.
- `df["col"] = serie_ou_escalar` via `__newindex` (mutação inplace).
- `DataSet.update_column`.

```lua
local df = smaug.DataSet({
    {"venda",  Series.from_table({100, 200, 300}, "float64")},
    {"estado", Series.from_table({"SP", "RJ", "SP"}, "string")},
})
df["desconto"] = Series.full(3, 0.1)
```

### Alterado — `windows_build.ps1` renomeado (era `windows-build.ps1`)
Separação de stderr e geração automática de manifest.

---

## 2026-05 · endurecimento Ring 0 (frentes A, B, C)

### Frente B — OOM nas ops
`test_allocfail` estendido para cobrir todas as ops aritméticas (f64/i64/bool/string).
Antes só `add`/`add_scalar`/`gt` eram testados sob falha de alocação.
579 → 767 verificações. Valgrind-clean.

### Milestone — branch-alvo 100% (MC/DC completo)
1095/1095 ramos cobertos. Jornada: 75.42% → 100.00%.
19 exclusões `COV-EXCL-BR` com justificativa auditável (overflows de `SIZE_MAX`,
guards de realloc-shrink, invariantes matemáticas). Métrica adotada: padrão
SQLite/aviônica — branch tomado em ambas as direções, guards inalcançáveis
excluídos com documentação.

### Frente A — guards de input + mecanismo de exclusão de cobertura
O engine passou a não confiar no caller: toda fronteira pública do C valida
ponteiro/argumento/índice e comunica o resultado. Antes a premissa era inversa
("o caller garante a validade"). Tag `COV-EXCL-BR` introduzida para separar
branch-alvo de branch-bruto no relatório.

### Frente C — semântica fechada
- Propagação estrita de null: qualquer operando null → resultado null.
  `0 × null = null`, sem elemento absorvente. Alinhado a pandas/numpy.
- Tabela-verdade Kleene completa para bool (`and`/`or`/`xor`/`not`),
  incluindo assimétricos (`F·NA = F`, `T·NA = T`).

---

## 2026-04 · contrato defensivo do C + COW

### Copy-on-Write em views (f64/i64)
Views compartilham o buffer da série pai zero-copy até a primeira escrita.
Toda mutação materializa um buffer privado antes de escrever; a pai nunca é tocada.
Falha de materialização → `SMG_ERR_NOMEM`, série e pai intactas.

```lua
local v = s:view(2, 3)  -- zero-copy
v:set(1, 99.0)          -- materializa buffer privado aqui
-- s inalterada
```

### Contrato defensivo — `get` Shape 1
`f64_get`/`i64_get` passaram a retornar valor + escrever `smaug_status_t*`.
Eliminou a colisão entre índice inválido e valor legítimo (NaN no f64,
qualquer inteiro no i64). `status == NULL` seguro (sentinela definida).

### Contrato defensivo — mutações comunicam status
`f64_set`/`i64_set`/`str_set` e variantes `_null` retornam `smaug_status_t`
(`OK`/`OOB`/`ARGUMENT`/`NOMEM`). Em erro, nenhuma escrita ocorre.
Frontend checa via `checkrc` — status ≠ OK é invariante interno violado.

### `str_set` migrado para `smaug_status_t`
Consistência com `f64_set`/`i64_set`. `str_set_null` propaga o mesmo enum.

### `Series:dropna()`
Fechou a inconsistência: `sort`/`argsort` recusavam séries com NULL
com a mensagem "use dropna primeiro", mas `dropna` não existia.

```lua
s:dropna():sort()  -- agora funciona
```

---

## 2026-03 · fase string completa

### String como dtype de primeira classe
Percurso: esqueleto (struct offset-based, estilo Arrow) → backend C
(lifecycle, acesso, mutação, comparações, filter/take, sort/argsort) →
frontend Lua (descritor, FFI, integração com DataSet).

String vazia `""` distinta de NULL. Ordenação lexicográfica por bytes
(não Unicode-aware — categorical/dictionary fica para depois).

```lua
local df = smaug.DataSet({
    {"uf",  Series.from_table({"SP", "RJ", "SP"}, "string")},
    {"pop", Series.from_table({12.3, 6.7, 12.3}, "float64")},
})
local sp = df:filter(df:col("uf"):eq("SP"))
```

### `test_allocfail` estendido para string
Caminhos de OOM da string não tinham cobertura de falha de alocação.
10 helpers `af_str_*` cobrem cada ponto de alocação. Valgrind-clean.

---

## 2026-02 · fase 1.6 — endurecimento (property-based, cobertura, fillna)

### Property-based tests
15 invariantes × 3 seeds × ~400 casos ≈ 281k checks.
Invariantes: clone independente, view compartilha memória, sort é permutação,
filter↔count_true, astype ida-volta, fillna remove null/preserva NaN, Kleene.
Validado por mutation testing (bug de aliasing injetado → detectado).

### `fillna`
`Series:fillna(value)` e `DataSet:fillna(value | {col=value})`.
Sem coerção (`fillna(1.5)` em int64 = erro). Preserva NaN (NaN é valor,
não ausência). Original imutável.

### Contrato NaN≠null fixado
`NaN` deixou de virar null. `sort`/`argsort` (f64) recusam NaN além de null.
`±Inf` continuam ordenáveis.

### `make coverage` agregando todos os testes
Antes media só via `.so` + Lua. Reescrito para agregar `test_allocfail`
(OOM, via `--wrap`) e testes C diretos nos mesmos `.gcda`.

---

## 2026-01 · fases 1–4 (backend C, frontend Lua, DataSet, bool)

### DataSet
Coleção de Series alinhadas. CRUD de colunas com validação de comprimento
e nome único. `filter`/`sort_by`/`head`/`tail`/`iloc`/`take`/`sample`/`select`.
`sort_by` reordena todas as colunas pela mesma permutação — preserva alinhamento.

### Bool e lógica Kleene
`BoolSeries` com lógica de três valores. `Series:gt`/`lt`/`eq` → `BoolSeries`.
`Series:filter(bool_series)` → nova Series (NA na máscara = linha descartada).

### Frontend Lua (Series)
Despacho por dtype via tabela de descritores. `ffi.gc` para limpeza automática.
Views read-only com `_parent` para impedir GC da série pai (evita use-after-free).
Sentinela `Series.NA` para representar nulos em `from_table`.

### Backend C (f64 + i64)
Lifecycle, getters/setters, append dinâmico, aritmética, reduções,
comparações, sort/argsort. Compile sem warnings (`-Wall -Wextra`).
`smaug_free()` exportada (portabilidade Windows — `free()` da libc não
é exportada pela DLL do runtime).
