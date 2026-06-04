# Smaug — Roadmap

> Como ler este documento: ele separa **o que já existe** (resumido), do que é
> **🔨 DECISÃO** (batido no martelo, vai ser feito nesta ordem), do que é
> **💭 CONCEITUAL** (ideia/aspiração, ainda não comprometida). A distinção é
> proposital: uma decisão conceitual não deve ser tratada como compromisso.
> Detalhes de implementação do que já existe ficam no código e no `API_INDEX.md`,
> não aqui.

---

## Estado atual

O Smaug tem o backend numérico (`float64`, `int64`, `bool`) e o frontend
(`Series`, `BoolSeries`, `DataSet`) implementados e **endurecidos** — a Fase 1.6
(endurecimento) está fechada. A próxima decisão batida é o **contrato defensivo
do backend C**, seguida do tipo **`string`** e do **I/O (CSV/JSON)**.

---

## ✅ O que já está feito (resumo)

Detalhes no código e no `API_INDEX.md`. Em alto nível:

| Fase | Entrega | Estado |
|------|---------|--------|
| 1 | Backend C: structs, lifecycle, ops `f64`/`i64`, null por bitmask | ✅ |
| 2 | `Series` (despacho por dtype, `ffi.gc`, metamétodos) | ✅ |
| 3 | `DataSet` (slicing, filter, sort_by, select, CRUD de colunas) | ✅ |
| 4 | `BoolSeries`, comparações, `filter` (lógica de Kleene, 3 valores) | ✅ (falta `dropna`, ver dívida) |
| 1.6 | **Endurecimento**: cobertura medida ≥90% linha, testes sistemáticos, property-based (~222k checks), falha de alocação, `fillna` | ✅ **fechada** |

A suíte: 4 testes em C (incl. `test_allocfail` via `--wrap`) + 7 suítes em Lua,
Valgrind-clean, cobertura medida (`make coverage` → `COVERAGE.md`). Modelo de
referência de teste: SQLite.

### Contrato de valores especiais (decidido e implementado)

1. **`NaN` ≠ `null`.** `null` (bitmask) = ausência; `NaN` (IEEE 754) = valor
   presente porém indefinido. Nunca se convertem — vantagem do Smaug sobre
   pandas/numpy. Implementado.
2. **`NaN` é contagioso** na aritmética (IEEE 754); comparações com `NaN` → `false`.
3. **`sort`/`argsort` recusam `NaN`** (além de `null`): valor sem ordem definida
   → recusa, não ordenação errada. `±Inf` são ordenáveis.
4. **`sum` com `min_count`**: default `0` (compatível pandas); `min_count=1` →
   `null` se não houver valor válido. *(min_count ainda a implementar — ver dívida.)*

---

## 🔨 DECIDIDO — próximas fases (nesta ordem)

Estas são decisões batidas no martelo. A ordem é firme.

### 1. Contrato defensivo do backend C *(próxima)*

Hoje o backend C confia no caller (validação fica no frontend Lua). **Decisão:**
mudar para validação defensiva no C — as funções de fronteira (`set`/`get`/`view`
etc.) passam a validar índice/ponteiro e sinalizar erro. Motivo: o Smaug será
fundação de um ecossistema (viz, ML) que chamará o C **direto**, sem passar pelo
frontend Lua; sem validação defensiva, entrada inválida vira corrupção de memória
silenciosa. Mudança de assinaturas (afeta FFI + frontend + call sites) — por isso
é fase própria, antes da `string`. (Origem: discussão do `test_alloc.c`.)

### 2. Tipo `string` (Tier 1) ⏳ EM ANDAMENTO

O maior buraco para trabalho estilo pandas (CSV real tem texto). **Decisão de
arquitetura (batida):** representação **offset-based estilo Arrow** — um buffer
de bytes com todas as strings concatenadas + array de offsets (`size+1`
marcadores; comprimento de cada string = `offsets[i+1]-offsets[i]`). Eficiente
em memória/cache e O(1) para comprimento; strings são imutáveis em tamanho
(combina com a imutabilidade por padrão; construção em lote via `from_table`). O
**dictionary encoding** NÃO entra aqui — é a essência do `categorical` (Tier 2),
tipo separado, depois. Sem migração destrutiva.

**Progresso:** struct `smaug_series_str_t` em `smaug_types.h` ✅; header
`smaug_string.h` (6º header) ✅; **backend C completo** em `src/smaug_ops_str.c`
✅ (lifecycle, get/set/append, clone, count_nonnull — 62 checks, Valgrind-clean,
o `set` faz deslocamento O(n) do buffer com `memmove`). **Falta:** registrar o
dtype `string` no frontend Lua (descritor da `Series` + `ffi_loader`), e depois
comparações/sort/take/filter. (Backend pronto; frontend a seguir.)

> **Encaixe nos headers.** `smaug_string.h` inclui só `smaug_types.h` + lifecycle
> próprio (tamanho variável). Nenhum `.c` existente é tocado — adição, não
> modificação. Foi para viabilizar isso que os tipos foram isolados em
> `smaug_types.h`.

### 3. I/O — CSV + JSON

Alvo de deploy do MVP. Lê/escreve CSV (`.csv`/`.tsv`, inferência de tipo) e JSON
(records ou columnar). Depende da `string` existir (por isso vem depois dela).
Sem coerção implícita entre dtypes.

**MVP = backend endurecido + contrato C + `string` + I/O (CSV/JSON).**

---

## 💭 CONCEITUAL — ainda não batido no martelo

Ideias e aspirações. Ordem **provável**, não comprometida. Cada uma será
detalhada (e decidida) quando chegar sua vez.

### I/O — SQL (priorizado sobre XML)

SQL é fonte de dados de produção real; XML é nicho. **Foco inicial: só SQLite.**
A abstração de dialeto (para MySQL/Postgres depois) **não** será feita agora —
seria abstração prematura com um banco só. Em vez disso, a disciplina barata:
concentrar **toda** a interação SQL num único módulo de fronteira (como o
`ffi_loader` faz para o C), para que adicionar dialetos no futuro seja mexer num
módulo, não caçar SQL espalhado. **XML fica para pós-release.**

### Analytics — GroupBy, Join, Window functions

Diferente de "mais uma operação": cada um exige **estrutura/estratégia nova** que
não existe hoje. GroupBy precisa de uma estrutura intermediária (grupos →
agregações); Join precisa de indexação/hashing de chaves e tipos de join; Window
precisa de janelas deslizantes com estado. Devem ser desenhados quando chegarmos
lá. Ordem provável: depois do I/O (analytics sem carregar dados de fontes reais
vale menos).

### Lazy evaluation *(por último)*

Alvo high-end, crucial para performance em pipelines grandes. **Não exige**
reescrever o backend nem tornar tudo lazy: é uma camada de orquestração
(`LazyDataSet` → constrói um plano → `.collect()`) **sobre** as operações eager
que já existem. O modo eager continua o default. **Pré-requisito de design barato
e já parcialmente satisfeito:** manter operações **imutáveis e componíveis** (já é
o caso — imutabilidade por padrão foi decidida cedo) e não introduzir efeitos
colaterais temporais escondidos. Vem **por último** porque otimiza justamente o
GroupBy/Join — só há o que otimizar depois que eles existem.

---

## 💭 Visão de longo prazo — o ecossistema

> Norte, não tarefa. O Smaug é fundação de um ecossistema de dados em Lua, não um
> fim em si. Inspirado no ecossistema Python (numpy/pandas → matplotlib →
> scikit-learn → SQLAlchemy/Alembic). Tudo aqui depende de o Smaug estar maduro.

**1. Visualização (matplotlib-like, HTML/SVG).** Renderiza gráficos a partir de
dados do Smaug. *Implicação presente:* a interface de exportação (`to_table` e
afins) é API pública consumida por terceiros — manter limpa e estável.

**2. Machine Learning (scikit-learn-like; eventualmente TensorFlow-like).** A peça
mais pesada.
- Exige **matriz numérica densa 2-D homogênea** (tudo `float64`, contígua) —
  distinta do `DataSet` (heterogêneo). Será um **tipo novo** (`Matrix`/`Tensor2D`),
  não uma extensão do DataSet. (Reforçado por parecer externo: não tentar enfiar
  computação matricial no DataSet heterogêneo.)
- **Broadcasting** (hoje dívida técnica) é **pré-requisito** de ML — sobe de
  "talvez" para "vai precisar". *Implicação presente:* novas APIs (ex. operações
  série-a-série) não devem fechar a porta para broadcasting.
- Distinguir scikit-like (regressão, k-means, árvores — factível) de TensorFlow-like
  (autodiff, redes neurais — drasticamente mais difícil em Lua, avaliar escopo).

**3. ORM (pós-release — terá roadmap próprio).** Ciclo de vida de dados:
carregar → visualizar → manter o banco → **versionar**. Bancos-alvo: SQLite,
MySQL, Postgres (com camada de abstração de dialeto). Inclui **versionamento de
schema inspirado no Alembic** (migrações versionadas up/down) — sistema **próprio**
em Lua inspirado no conceito, não integração com o Alembic real (que é Python).
Migração de schema é das partes mais complexas de um ORM — aspiração de longo
prazo, com complexidade explícita. Será planejado em roadmap dedicado.

**4. Port para Lua 5.4.** LuaJIT (Lua 5.1) tem FFI; **Lua 5.4 não**. Portar exige
**bindings C manuais** (via API C do Lua) ou manter as duas vias — mudança
arquitetural, não troca de interpretador. *Implicação presente:* manter a fronteira
Lua↔C **centralizada** (no `ffi_loader`) facilita o port. Pode justificar o CMake
(`FindLua`) no futuro — ver `Build_and_Testing.md`.

Consequência transversal: por ser fundação de várias bibliotecas, **cada fraqueza
no Smaug se multiplica**. Isso justifica o rigor de teste (Fase 1.6) antes de
crescer — confirmado pelo parecer externo, que apontou o crescimento de escopo
como o maior risco, e o endurecimento da fundação como o maior acerto.

---

## Sistema de tipos

Conjunto curado, em três camadas. A `Series` abstrai o dtype (descritor +
backend C), então adicionar tipo não quebra a API.

**Tier 1 — núcleo:** `float64` ✅, `int64` ✅, `bool` ✅, `string` (decidido,
próxima após contrato C).

**Tier 2 — alto valor (pós-MVP):** `datetime` (`int64` epoch ms); `categorical`
(codes `int32` + levels) — **é aqui que entra o dictionary encoding** (IDs +
dicionário), acelerando groupby/comparação/sort com repetição.

**Tier 3 — otimização (talvez):** `float32`, `int32/16/8`, `uint*` — mesma
semântica, storage estreito. Só se um caso real justificar.

**Princípios transversais:** sem coerção implícita (conversão explícita via
`astype`); null por bitmask uniforme (inclusive para tipos sem NaN nativo);
mapeamento NumPy/pandas → Smaug documentado para conversão.

---

## 📋 Dívida técnica (registrada, não esquecida)

Itens conscientemente adiados. Serão reagendados em fase dedicada após o MVP.

**Estatísticas/utilitárias:** `median`/`quantile` nativos; `abs`/`round`/`clip`;
`cumsum`/`cumprod`; `diff`/`shift`; `unique`/`value_counts`/`mode`; `dropna`
(prioritário logo após o I/O — destrava sort em dados com nulos); `fillna` por
método (fwd/bwd-fill); `sum(min_count)` (implementação).

**Semântica numérica:** **broadcasting** (Series de tamanhos diferentes / Series ×
array — pré-requisito de ML); `apply`/`map` (função Lua elemento a elemento);
reconciliar assimetria de div/0 entre f64 (IEEE: ±Inf/NaN) e i64 (→ NULL);
correção do `set` i64 que trunca não-inteiro silenciosamente (CODE_REVIEW A7).

**Operações de string (`.str`, roadmap próprio incremental).** O núcleo (lifecycle,
get/set/append, e — em peças seguintes — comparações/sort/filter) torna a string
utilizável como coluna de dados. A API rica do pandas (`.str`) entra **por camadas,
conforme o uso real pedir**, não num big-bang. Mapa priorizado:
- *Tier A (mais usados):* `len`, `lower`/`upper`, `strip`/`lstrip`/`rstrip`,
  `contains`, `startswith`/`endswith`, `replace` (literal).
- *Tier B:* `split`, `cat`/join, `slice`, `pad`/`zfill`, `repeat`, `find`.
- *Tier C (caro/complexo):* regex (`extract`/`findall`/`match` — subprojeto à
  parte), `get_dummies`, normalização/validação **UTF-8** (hoje trata bytes crus;
  case-folding Unicode-aware exige tabelas de caso). Cada tier é uma fase testada e
  Valgrind-clean. `categorical` (dictionary, Tier 2) acelera muitas dessas sobre
  strings repetidas — e, como observado, torna o `set` O(1) sobre IDs.

**Cobertura:** ao entrar no frontend, `smaug_ops_str.c` passa a ser medido via os
testes Lua; o frontend básico não exercita todos os caminhos do `set` (3 casos de
deslocamento), então o total pode baixar — gap a fechar com testes Lua de string
ou registrar conscientemente. Revisar ao fechar a fase string.

**Performance/robustez:** benchmarks e estresse (10⁷+ elementos); avaliação de
SIMD; `ffi.gc` em hot paths; agregar `test_allocfail` à medição de cobertura.

**Observabilidade (fase dedicada):** sistema de **warnings** unificado (ex.: avisar
opt-in quando operação encontra `NaN`, overflow de i64) — tratado de forma
sistemática, não ad-hoc, sem penalizar os loops quentes.

**Build:** atualizar `windows-build.ps1` para rodar todos os testes; decidir o
futuro do bloco CMake (atrelado à decisão Lua 5.4).
