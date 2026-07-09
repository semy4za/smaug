# Changelog — Smaug

Registro de o que mudou e por que, em ordem cronológica reversa.
Uma entrada por sessão de trabalho. Foco no que não é óbvio pelo diff:
decisões, achados, motivações.

---
## 2026-07-09 — where/mask/ifelse → Anel 0 via select (cond-bool)

Primitiva (b) ao Anel 0. `select(cond,a,b)` por dtype: cond true→a, senão
(false ou NA)→b, preservando nulidade do escolhido. NA→false (decisão 1a).
Unifica where=select(cond,self,other), mask=lados trocados, ifelse=select(cond,a,b).
Escalar/nil por broadcast em Lua (reuso create+coalesce_scalar, sem C novo).
Degrau sai das três; int64 > 2^53 exato. bool-valor no Anel 1 até 10.8.

FFI: struct bool movido pra antes do f64 no cdef. Guards de entrada COV-EXCL-BR.
Testes: degrau → paridade Anel 0 nas 4 dtypes (selection 48 checks). Windows
12/12; prévia Ubuntu branch-alvo 94.38→94.49%. Selo Fedora pendente.

---
## 2026-07-09 — rename: scripts/windows_build.ps1 → scripts/build_win.ps1

Renomeado o script de build do Windows para `build_win.ps1`, alinhando com o
par `build.sh`. O replace foi global (docs + scripts + header do próprio
script); nenhuma referência a `windows_build.ps1` permanece no repo.

Nota de registro: o replace alcançou também as entradas históricas deste
CHANGELOG — sessões anteriores a esta data mencionam `build_win.ps1` embora, à
época, o arquivo se chamasse `windows_build.ps1`. Escolha consciente para manter
todas as referências apontando ao arquivo vigente; esta entrada documenta o
rename para que o nome novo nas entradas antigas tenha explicação. Sem mudança
funcional no script.

---
## 2026-07-09 — 12.17: alinha COV-EXCL-BR do dt_coalesce_scalar

Os guards `if (!self)` (datetime:219) e `if (!r)` (datetime:222) do
`dt_coalesce_scalar` estavam sem `COV-EXCL-BR`, ao contrário dos irmãos
i64/f64/str (anotados no B.1.cov). Recebem agora a justificativa idêntica
("engine não confia no caller" / OOM sem injeção). Mudança só de comentário,
sem alteração funcional.

Prévia Ubuntu (gcov, sem Valgrind): branch-alvo 94.33→94.38% — os 2 guards saem
de descobertos para excluídos. Selo Fedora `--all` (Valgrind + gcov) pendente.

---
## 2026-07-09 — combine_first → Anel 0 via coalesce série+série (null-mask, lado série)

Segunda metade da natureza null-mask vai ao Anel 0, fechando a primitiva (a) do
Passo B (escalar + série). `coalesce` série+série por dtype: onde `self[i]` é
nulo entra `other[i]` (se válido), senão `self[i]`; ambos nulos → nulo.
i64/f64/dt reusam `clone` + preenchem buracos a partir de other; str faz
two-pass offset-based (preserva `\0` e agora **pode** gerar nulos — máscara por
caso, ao contrário do escalar, que sempre produzia série sem nulos).

`combine_first` passa a delegar: valida Series/dtype/tamanho e chama
`self._d.coalesce(self._c, other._c)`. O degrau `check_int64_lossless` **sai do
`combine_first`** (int64 > 2^53 exato, sem round-trip por `get()`). bool fica no
Anel 1 até 10.8 (branch próprio, sem degrau — sem risco int64).

Testes: o teste antigo do degrau ("combine_first recusa int64 > 2^53") virou
paridade Anel 0 — 2^53+1 exato nos dois caminhos, ambos-nulos → nulo, str com
`\0`/vazia/`total==0`, dt self/other/ambos-nulos, nas 4 dtypes. Guards de
entrada (`!self||!other||size`) marcados `COV-EXCL-BR` — `combine_first` valida
antes de delegar.

Selo Fedora: Valgrind 0-errors nos 12 binários, branch-alvo 94.26→94.33% (acima
do baseline), zero descoberto nas coalesce. Com a primitiva (a) fechada, resta
(b) cond-bool com Kleene (`where`/`mask`/`ifelse`) e (c) propagação
(`ffill`/`bfill`).

Achado registrado (12.17): `dt_coalesce_scalar` (datetime:219/222) sem
`COV-EXCL-BR`, ao contrário dos irmãos i64/f64/str — inconsistência pré-existente
do B.1, a corrigir (não é regressão; contabilidade de branches fecha exata).

---
## 2026-07-08 — selo do null-mask escalar completo (B.1.cov)

Fecha a cobertura pendente das primitivas `coalesce_scalar`. O `--all` de
2026-07-06 deixara os guards defensivos novos sem cobrir. Resolução: os 7
guards de contrato (`if (!self)`, `if (!r)`, `if (!value && value_len>0)` em
i64/f64/str) marcados `COV-EXCL-BR` com o precedente já firmado. Os dois ramos
alcançáveis do `str` (`total>0?…` e `if (len>0) memcpy`) já ficavam cobertos
pelo teste 10.6B de string vazia — `fillna("")` sobre série toda-nula e sobre
mistura buraco/`"abc"` exercita os dois lados sem teste novo.

Selado no Fedora: Valgrind 0-errors nos 12 binários, branch-alvo 94.26%
(3693/3918, 105 excluídos), zero branch `coalesce_scalar` descoberto. Com isto o
lado escalar da família seleção/preenchimento por máscara está 100% fechado —
próximo: `coalesce` série+série (serve `combine_first`).

---
## 2026-07-07 — fillna → Anel 0 via coalesce_scalar (natureza null-mask, lado escalar)

Primeira das três naturezas da família seleção/preenchimento por máscara vai ao
Anel 0. Primitiva `coalesce_scalar` por dtype (`i64`/`f64`/`dt`/`str`): onde
`self[i]` é nulo entra o `value`, senão mantém `self[i]`; resultado sem nulos.
Molde do `binop_scalar`. `i64`/`f64`/`dt` reusam `clone` (cópia via memcpy — não
reinventam a cópia byte a byte). `str` não pode: preencher muda o tamanho do
buffer, então faz two-pass O(n) espelhando `create_from_array`, mas com os
comprimentos reais dos offsets (não `strlen`) — preserva `\0` embutido. `bool`
fica de fora (tipo paralelo, alinha ao 10.8).

O `fillna` passa a delegar: valida o `value` **uma vez** via `check_value`
canônico e chama a primitiva. Dois ganhos: (1) int64 > 2^53 nos não-nulos é
preservado exato — o degrau **sai do `fillna`** (segue nos outros membros da
família); (2) o `check_value` aceita `cdata int64_t`, que o porteiro caseiro do
`fillna` rejeitava — **cura a desparidade** e passa a aceitar preenchimento int64
exato acima de 2^53. `dt` restrito a `number` (epoch_ms) nesta leva; string ISO
registrada como 12.16.

Descoberta de método (via pergunta "usar str_set num loop é eficiente?"): não —
seria O(n²) pelos memmoves; o two-pass O(n) é o caminho, e o próprio Smaug já o
usa no construtor em massa. Reforça o hábito de medir antes de cravar.

Provado por FFI (2^53+1 exato, NaN preservado, `\0` embutido, `value` cdata) e
suíte (fillna 39 checks, property-based 360k). Valgrind 0-errors; cobertura de
linha 98.73→98.75%. **Pré-selo pendente:** 8 branches de guards defensivos das
primitivas a fechar (7 `COV-EXCL-BR`, 1 confere `str:227`) — ver 10.6 Passo
B.1.cov. Selo do null-mask escalar fecha quando a cobertura fechar.

---
## 2026-07-06 — 10.6 vira família; degrau estendido a where/mask/ifelse/combine_first

A pergunta "isso deveria estar no C?" reenquadrou o 10.6. `fillna` não é uma
operação isolada: é membro de uma família que escolhe/preenche valor por posição
segundo uma máscara — `fillna`, `combine_first`, `where`, `mask`, `ifelse`, e os
parentes de propagação `ffill`/`bfill`. Todos vivem no Anel 1 (loop
`get→set`+`from_table`) e, portanto, herdam a corrupção de int64 > 2^53.

Achado (provado): `where`, `mask`, `ifelse` e `combine_first` corrompiam int64 >
2^53 **em silêncio, agora** — o degrau de 2026-07-05 só cobria `fillna`/`astype`.
Era um bug ativo em meia família.

Degrau estendido: a guarda única `check_int64_lossless` (mesma fronteira 2^53 do
9.1, fonte única) passou a proteger os quatro. Recusam visível em vez de
corromper calado. Reuso da guarda existente — nenhum critério novo, nenhuma
guarda duplicada. Testes: +5 selection, +2 predicates. Suíte verde, parity 12/12,
Valgrind 0-errors, coverage inalterado (Lua-puro).

Decisão de arquitetura: **não** criar `fillna` isolado no Anel 0 — bifurcaria a
família (metade C, metade Lua), a desparidade que o item combate. O Passo B passa
a ser desenhar as primitivas fundamentais da família (seleção por null-mask;
seleção por cond-bool com Kleene; propagação à parte), com todos delegando. As
3 primitivas C `*_fillna` isoladas (i64/f64/dt) tentadas antes foram descartadas
— voltam integradas no desenho da família.

---
## 2026-07-05 — 10.6/10.7 Passo A (degrau): corrupção silenciosa → falha visível

Antes de vetorizar `fillna`/`astype` ao Anel 0, um degrau paliativo que troca
acerto-adivinhado por falha visível.

Achado que refina o Roadmap (10.6, l.449): a corrupção de int64 > 2^53 no
round-trip `get()`→`double` tem **dois regimes**, não um. Muito acima de 2^53
dispara o warn do 9.1 por elemento (ruidoso, grava errado) — esse já era
conhecido. Mas na fronteira (logo acima de 2^53, que o `double` arredonda de
volta a exatamente 2^53) grava em **silêncio total**: o `number` arredondado
passa no guard do 9.1 (`> 2^53` é falso para `== 2^53`) e entra sem aviso. Pior
caso de falha-invisível, não registrado antes. Provado com `2^53+1` (silencioso)
vs `2^60+7` (avisa).

Guarda única `check_int64_lossless` (`_core.lua`, ao lado do `check_value`):
reusa o `INT64_MAX_MAG` (2^53) do 9.1 — **fronteira única**, sem segundo
critério. Lê o valor cru (`cdata int64_t`, sem `tonumber`) só para comparar
magnitude — detecção, não conversão. `fillna` e `astype` delegam; nenhuma regra
de fronteira nova nasce nos call-sites (anti-redundância).

Seletividade por par no `astype`: recusa só onde `double` perde **e** importa —
`int64→int64` e `int64→string`. `int64→float64` **não** recusa (o `double` é o
destino correto; a matriz empírica provou que atravessar `double` nem sempre é
erro); `int64→bool` tampouco (0/1).

Paliativo por construção: não vetoriza, não move nada ao Anel 0, não reescreve
loop nem matriz. Sai quando o Passo B (Anel 0) entrar — junto com os testes que
hoje esperam recusa, que passarão a esperar sucesso com valor exato. Desparidade
registrada e **não** consertada aqui: `fillna` rejeita `value` cdata (validação
divergente do `check_value`) — morre no Passo B ao delegar.

Testes: +2 em `fillna` (`test_access`, visíveis 34→36) e +5 em `astype`
(`test_constructors`, contagem mascarada pelo 12.7 — os checks rodam e passam,
o headline subconta). Suíte verde, parity 12/12, selo [Fedora] 2026-07-05
(Valgrind 0-errors nos 12 binários; coverage inalterado — nenhuma linha C nova).

---
## 2026-07-02 — 9.2: fechamento de cobertura do C novo (pré-selo)

Checkup pós-9.2 rodou o `--all` em Linux (container, pré-checagem — Fedora
segue autoritativo) e encontrou o que o selo existe para encontrar:
`smaug_str.c` com 100% de linha mas **4 ramos descobertos, todos no código
novo do 9.2**. gcov com `-b` identificou as direções exatas:

- **Guard da view (l.115):** nenhuma das 3 sub-condições jamais disparou —
  não existia teste de entrada inválida para `smaug_str_view` (o
  `test_cow_oob_does_not_detach` é só f64). Novo
  `test_str_view_invalid_inputs`: NULL, `start > size`, `len > size-start`,
  borda inválida `start==size, len>0` e a borda VÁLIDA `start==size, len==0`
  (janela vazia no fim — prova que o guard overflow-safe aceita o mesmo
  contrato do f64). Pai intacto após as recusas.
- **Detach de janela toda-vazia (l.306/312):** `byte_count==0` com `size>0`
  (todas as strings `""`) nunca ocorria — caso distinto do
  `test_str_empty_view` (`size==0`). Novo `test_str_detach_all_empty_window`:
  bufcap cai no fallback `SMAUG_STR_BUFFER_INIT`, memcpy pulado, série
  destacada coerente e mutável, `""` ≠ NULL preservado, pai intacto.
- **`offsets_owned` false (l.104):** estruturalmente inalcançável — o campo é
  atribuído `true` nos 3 pontos (create/view/detach) e nunca `false`.
  Decisão: `COV-EXCL-BR`, com justificativa de posse, não de "porta futura":
  o campo paga seu custo hoje porque torna o `free` correto por semântica
  (A1) — sem ele, a posse do offsets seria inferida por acoplamento
  `external_alloc`+`is_view`.

Allocfail NÃO estendido (decisão registrada): o trio de OOM do detach já é
varrido pelo harness; o ramo distinto era só o `byte_count==0`.

**Resultado:** `smaug_str.c` 100% linha / 100% branch-alvo; test_cow 263→279.
Validado: Linux container (Valgrind 0-errors nos 12 binários, 18/18 Lua,
parity 12/12) + Windows (suítes idênticas). **Selo [Fedora] obtido
(2026-07-02):** `--all` verde — Valgrind 0-errors, `smaug_str.c` 100/100,
test_cow 279. 9.2 fechado.

**Auditoria Lua (mesma sessão):** disciplina de erro, warn e helpers de NA
limpos. Fix aplicado: 4 call-sites internos migrados para `_raw_column()`
(`dataset/_core.lua` — select/insert/rename; fecha os retardatários do 9.2).
Achados registrados na estrada: 10.6 (`fillna` corrompe i64 > 2^53 via
round-trip `get`), 10.7 (`astype`, mesma natureza), 10.8 (`BoolSeries` —
coerência de caminho, design prévio), 11.4 (exibição de i64 > 2^53) e 12.13
(doc do 9.1 incompleta). Datetime fora do raio (epoch_ms).

---
## 2026-07-01 — Item 9: Contratos de fronteira (9.1 int64 > 2^53 + 9.2 column COW / view de string)

Fechou os dois contratos de fronteira do item 9. O fio condutor: quem é dono do
dado, e onde a precisão/posse pode se perder silenciosamente.

**9.1 — int64 acima de 2^53 (`check_value`, Lua-puro, Anel 0 intocado).**
Dois sub-problemas distintos:
- Sub-A (limitação da linguagem, não da lib): um literal Lua grande como
  `9007199254740993` já chega **truncado** para `9007199254740992` — o parser do
  Lua o representa como `double` antes de qualquer código do Smaug rodar. A lib
  não pode recuperar o valor, só tornar visível. Decisão (9.1.2):
  **avisar-mas-aceitar** — número > 2^53 dispara um `warn` educativo (helper novo
  `I.warn` central em `init.lua`, reutilizável pelo 12.10), sem bloquear.
- Sub-B (o bug real, a lib controla): `check_value` recusava `cdata int64_t`
  (`9007199254740993LL`, `ffi.new("int64_t")`) — a única forma que preserva 64
  bits — porque exigia `type(v) == "number"`. O C guarda até 2^63-1 sem perda; o
  gargalo era só o guard Lua. Corrigido via `ffi.istype`: aceita cdata
  int64/uint64, recusa `uint64_t > INT64_MAX` (9.1.3, sem wraparound silencioso)
  e segue recusando float/double cdata (mantém A7).

**Achado durante a implementação:** consertar a entrada (`set`) não bastava — a
saída (`get`) reintroduzia a perda, porque `get_value` faz `tonumber()` no
int64_t (mesma limitação da Sub-A, do outro lado). Escopo estendido no mesmo
item: novo `Series:get_raw(i)` devolve o cdata int64_t cru, sem conversão. `get`
normal mantém o comportamento antigo (limitação documentada).

**9.2 — `column()` compartilhava buffer com o frame (E2). Op1: o E2 morre.**
`column()` retornava a referência Series interna; `col = df:column("x");
col:set(...)` mutava o frame silenciosamente. Decisão: `column()`/`col()` passa a
retornar **view COW** protegida (leitura zero-copy, detach na 1ª mutação). O
código interno (relacional, csv, stat — ~40 call-sites) migrou para `_raw_column`
(acesso cru explícito). Mutação intencional agora é via `update_column`.

**Estendido para o Anel 0 (a parte pesada):** string não tinha view. Implementada
`smaug_str_view` + `str_cow_detach` em C. Diferente dos numéricos (buffer fixo,
view O(1)), a string é offset-based → **modelo de posse mista A1**: campo novo
`offsets_owned` na struct `smaug_series_str_t`, a view compartilha
`buffer`/`null_mask` mas possui um `offsets` próprio absoluto. O `free` passou a
separar as duas posses; o detach materializa a janela com offsets rebaseados.
Escolhido A1 sobre A3 (rebase on-the-fly em cada acesso) porque A1 concentra a
complexidade no ciclo de vida da view — A3 a espalharia por toda operação de
string (fonte de regressão distribuída).

**Achado de teste (E2 tinha alcance oculto):** ~14 setups de `test_core` usavam
`df:col("x"):set_null(i)` como atalho para injetar nulos — só funcionava pelo
aliasing que estávamos matando. Migrados (Op A) para dados que **nascem** com
`NA` via `from_table({..., NA, ...})` e mutação via `update_column`. Review do C
confirmou: `from_table(NA)` chama o mesmo `set_null` do C (só escreve a máscara),
então o estado de memória é idêntico — zero reimplementação.

**Sincronização crítica:** o cdef do FFI declara a struct str campo a campo, então
`offsets_owned` teve de entrar no cdef na mesma posição do C (senão o LuaJIT lê o
layout errado — bug de memória silencioso).

**Validação:** Valgrind-clean (test_cow, test_string, allocfail — 0 leaks/errors,
incl. caminhos de OOM do detach); test_cow +70, allocfail +70, test_core +8
(prova E2 morto); 18/18 Lua; parity 12/12 (`get_raw` e `_raw_column` registrados
como exceções intencionais). Docs sincronizados: COW.md (string ❌→✅),
API_Reference, API_INDEX, CONTRACT. 9.1 fechou por Windows (Lua-puro); 9.2 é
[Fedora] (Anel 0 novo) — aguarda `--all` para o selo de cobertura.

---
## 2026-06-30 — Item 8: Rolling → Ring 0 (motor genérico + min_periods + expanding + DataSet)

Levou a tese de "fonte única" ao rolling. Antes a duplicação era TRIPLA (C /
Series Lua / DataSet Lua), e o C fazia menos que o Lua. Agora o C é a fonte;
Series e DataSet delegam.

**Bug histórico corrigido (a motivação real do item):** o caminho C ignorava
min_periods. `rolling(3):min_periods(1):sum()` dava `nil,nil,6,9` (o C era
chamado sem saber de min_periods) em vez de `1,3,6,9`. O resultado dependia de
qual caminho (C/Lua) era tomado. A cura: o C passou a conhecer min_periods, e o
fallback Lua foi removido — não há mais dois caminhos.

**Arquitetura (8a):**
- Motor genérico `rolling_apply(data, mask, n, window, min_periods, kind)` —
  fonte única dentro do C para mean/std/var/count (D8-g opção i: os agregados
  naturalmente double-safe). std/var amostrais (ddof=1, NaN p/ n<2) — coerente
  com a reconciliação do item 5.0.
- sum/min/max NÃO passam pelo motor (preservam tipo exato — sum i64 >2^53 não
  perde precisão, min/max mantêm a deque O(n)). Só ganharam min_periods.
- **min_periods (D8-b)**: convenção `0 = modo janela-cheia (default), >=1 =
  parcial (>= min_periods não-nulos)`. Auditoria do motor confirmou que isso
  espelha o min_count do item 5.5 — não é invenção local, é o idioma já usado.
- **min/max com min_periods (D8-h opção ii)**: a deque não rastreia contagem de
  não-nulos (o resumo inicial subestimou isso). Em vez de mexer na deque (que
  tem invariantes COV-EXCL delicados, arriscado sem Fedora), o modo min_periods>=1
  usa um rescan O(n·window) type-preserving (compara no tipo nativo, sem double);
  a deque fica intocada no modo default (caso comum). "Não pague pelo que não usa".

**Expanding (8b, D8-i opção i):** expanding É rolling com janela = comprimento
total e min_periods>=1. Zero C novo — delega a `rolling(n, min_periods)`.
Eliminou todo o SeriesExpanding reimplementado. Não regride performance (o
expanding Lua já era O(n²)). median/quantile expanding ficam Lua (via _agg).

**DataSet (8c):** Rolling DataSet tinha _agg próprio (3ª cópia). Agora delega à
Series via `column():rolling()`. Ganhou std/var/count e min_periods de graça.

**Correção de tipo (efeito colateral saudável):** o expanding e o DataSet rolling
antigos usavam `col._dtype` para todos os agregados — então `mean` de i64
**truncava** para int64. Agora mean/std/var → float64 (coerente com a Series).
Nenhum teste dependia do comportamento truncado.

**Decisão D8-c:** sum/mean/min/max/std/var/count no C; median/quantile ficam Lua
(janela ordenada é padrão diferente; registrado, candidato a C pós-1.0).

- Testes: C +20 (test_ops_window 391→411: std/var/count, min_periods, rescan,
  i64 >2^53 exato); allocfail +71 (1733→1804: motor, pack_f64, i64_via_motor,
  count, modos min_periods/rescan); Lua test_window +23 (93→116: bug corrigido,
  novos agregados, expanding delega, tipos); ds test_core +8 (212→220).
- Migração de ABI: 100 chamadas rolling em test_ops_window + 18 em allocfail
  atualizadas p/ a assinatura de 3 args (min_periods=0 = comportamento anterior).
- `[Fedora]`: implementado e verde no container + Windows-equivalente; aguarda
  Valgrind + cobertura no Fedora. Fecha JUNTO com o item 7.3. Atenção no Valgrind
  ao motor genérico (malloc/free de tmp em i64_via_motor) e ao rescan de min/max.

---
## 2026-06-29 — Item 7.3: rank em dt/str/bool no Ring 0

Último gap de completude do motor (o 7.4 já estava feito). `rank`/`pct_rank`
existiam só em f64/i64; agora todos os ordenáveis (f64/i64/dt/str/bool) têm.

- **Insight de assinatura**: o resultado do rank é sempre `double` (average pode
  dar .5), em qualquer dtype. Só a comparação dos valores é type-specific. Então
  `double* smaug_<t>_rank(s, method)` serve todos — sem a bifurcação de retorno que
  o 7.2b (min/max) teve. Por isso pacote único (D7.3-e).
- **dt** (`smaug_dt_rank`): espelha `smaug_i64_rank` (epoch é int64, comparação
  exata via `dt_entry_t {idx,val}` — sem converter a double, preserva precisão).
- **str** (`smaug_str_rank`): ordena um array de **índices válidos** via `sort_cmp`
  (mesmo contexto global do argsort) e detecta empates com `str_cmp_idx`. Não cabe
  em par numérico, então é gather de índices. "" é valor válido (a menor string).
- **bool** (`smaug_bool_rank`): sem qsort — só dois grupos. Os `nf` false ocupam
  posições 1..nf, os `nt` true ocupam nf+1..nf+nt; o método decide o valor.
- **Métodos uniformes** (D7.3-b): average/min/max/first em todos. NA → NAN → nil
  (D7.3-c), rankeando só os válidos, igual aos numéricos.
- **D7.3-d (refatoração do gate)**: `methods.rank` tinha `if float64...else i64`
  hardcoded. Agora o descritor liga `rank` nos 5 dtypes e a Lua delega via
  `self._d.rank`, sem branch por dtype — alinha com shift/ffill/min/max. f64/i64
  passaram a ir pelo descritor (mesmo C, comportamento idêntico).
- **Ganho de graça**: `pct_rank` chama `rank("average")` internamente, então passou
  a funcionar em str/dt/bool sem código novo (count_nonnull já existia em todos).
- **Coerência (exceptions órfãs)**: o eixo 1 do parity tinha 6 exceptions marcadas
  "gap real não implementado" / "sem semântica" para rank e pct_rank × str/dt/bool.
  Com a implementação, viraram órfãs — removidas. rank/pct_rank × categorical
  ficam (sem ordem útil). bool saiu de "sem semântica" porque D7.3-a o incluiu.
- D7.3-a: bool incluído (escopo literal era "dt/str") — registrado.
- Testes: C +31 (test_ops_window 360→391: dt/str/bool nos 4 métodos, empates, NA,
  "" válida, toda-NA, NULL); Lua +12 (integração 66→78); allocfail +31 (1705→1736,
  varrendo malloc(result)+malloc(pairs/idx)+qsort de cada).
- Achado (não acionado): rank/pct_rank por-coluna no DataSet = escopo futuro
  (exceptions eixo 2 mantidas).
- Corrigido de passagem: API_INDEX dizia método `dense` (inexistente); o correto
  é `first`.
- `[Fedora]`: aguarda Valgrind + cobertura. Atenção ao `str_rank` (qsort de índices
  com contexto global) e às ramificações de método.

---
## 2026-06-29 — Item 7.2b: min/max em dt/str/bool no Ring 0 (7.2 completo)

Segunda metade do 7.2. Fecha a outra metade da incoerência: `dt:min`/`dt:max`
(e str/bool) passam a existir, retornando o **valor** do menor/maior (decisão
D7.2-a opção ii). Agora `dt:min == get(dt:argmin)` — coerência total.

- **dt** (`smaug_dt_min`/`max`): retorna int64 epoch, espelha `smaug_i64_min/max`.
  INT64_MIN (= DT_SENTINEL) sinaliza vazia/toda-NA/(ignore_na=false) presença de
  NA; a Lua detecta via `is_int_sentinel` → nil. Passa por `reduce_num` limpo
  (já era o caminho dos numéricos).
- **str** (`smaug_str_min`/`max`): retorna ponteiro+len para o elemento vencedor
  (dentro do buffer de `s`), no padrão de `smaug_str_get` — NULL = vazia/toda-NA/
  (ignore_na=false) NA; ptr!=NULL com len==0 = "" (distinta de NULL). Reusa
  `argmin/argmax` (mesma comparação lexicográfica). Wrapper no descritor
  materializa via `ffi.string`. NÃO aloca.
- **bool** (`smaug_bool_min`/`max`): Shape 1 (valor + status), como `bool_get` —
  não há valor fora de {0,1} para sentinela, então `SMG_NULL_VALUE` sinaliza
  ausência. Wrapper no descritor lê o status (distingue `false` de ausência).
- **Decisão de despacho** (`_reduce.lua`): `methods.min/max` ramifica —
  str/bool usam o wrapper do descritor (retorna valor|nil), evitando `reduce_num`
  (que faria `tonumber` e quebraria a string); f64/i64/dt seguem `reduce_num`.
  O caminho numérico não foi tocado (preserva Valgrind-clean já validado).
- `ignore_na` uniforme em todos os dtypes (default true: pula NA; false: NA
  presente → nil). argmin/argmax seguem ignorando NA por natureza.
- Testes: C +22 (test_ops_window 338→360: dt/str/bool min/max, "" válida, NA,
  ignore_na false, toda-NA, NULL, status NULL-safe); Lua +14 (test_reduce 43→57).
  min/max não alocam → allocfail inalterado (1705).
- Achado registrado (não acionado): `df:min()`/`df:max()` no DataSet ainda
  filtram só colunas numéricas (contrato D3 do item 5). Estender a str/dt/bool
  (como pandas) é decisão de escopo do frame — fora do 7.2.
- `[Fedora]`: aguarda Valgrind + cobertura. Atenção aos caminhos `str_min/max`
  (ponteiro pra dentro do buffer) e às ramificações de status do bool.

---
## 2026-06-29 — Item 7.2a: argmin/argmax em str/bool/dt no Ring 0

Primeira metade do 7.2. Fecha parte da incoerência `dt:argmin`✓/`dt:min`✗:
o `dt:argmin` que funcionava via fallback Lua foi movido pro C, e str/bool —
que erravam — ganharam a operação.

- C novo: `smaug_dt_argmin/argmax` (cronológico), `smaug_bool_argmin/argmax`
  (false<true), `smaug_str_argmin/argmax` (lexicográfico por bytes, via novo
  helper `str_cmp_idx` — comparação índice-vs-índice, mesma ordem de sort/cmp).
  Todos espelham `smaug_f64_argmin`: índice 0-based, SIZE_MAX se vazia/toda-NA,
  ignoram NA. Decisão D7.2-b: bool incluído (era o único órfão; trivial).
- `methods.argmin`/`argmax` (`_cumulative.lua`): o gate de dtype hardcoded
  (numérico+datetime) virou gate por **capacidade** (`self._d.argmin` existe?),
  e o fallback Lua foi removido. Erro orientado por dtype quando não há suporte.
  `idxmin`/`idxmax` são aliases → herdam o suporte novo automaticamente.
- Parity: removidas 4 exceptions agora **órfãs** (argmin/argmax × str/bool, antes
  marcadas "gap"/"sem semântica"). Categorical permanece exceção (sem ordem total
  estável — depende do encoding dos codes).
- Testes: C +24 (test_ops_window 314→338: dt/str/bool com NA, vazia, toda-NA,
  string vazia como menor, prefixo "ab"<"abc"); Lua +9 (test_window 93→102).
  argmin/argmax não alocam → allocfail inalterado. Os testes de `dt:argmin` em
  test_categorical passaram a exercitar o C (guard da migração de graça).
- `[Fedora]`: aguarda Valgrind + cobertura para `[Done]`.

---
## 2026-06-29 — Item 7.1b: shift com sinal no Ring 0 (todos os dtypes)

Fecha o 7.1. Move o shift inteiro pro C — incluindo o sentido negativo, que
até aqui era tratado por fallback Lua e (achado) NÃO tinha cobertura em lugar
nenhum.

- **Mudança de ABI** (a parte sensível, por isso isolada do 7.1a): assinatura de
  `smaug_f64_shift`/`smaug_i64_shift` passou de `size_t periods` para
  `int64_t periods`. Os testes C antigos só exercitavam positivos (1, 0, ≥size),
  então sobreviveram sem alteração. Header + cdef FFI atualizados.
- Fórmula unificada para os dois sentidos: para cada posição i de saída, a fonte
  é `src = (int64_t)i - periods`; fora de `[0, size)` → NA. periods>0 desloca p/
  baixo, <0 p/ cima — mesma semântica que o fallback Lua tinha (preservada).
- Short-circuit `|periods| >= size → toda NA`: além de atalho do caso comum, evita
  overflow em `(int64_t)i - periods` quando `periods` está perto de `INT64_MIN`.
- shift novo em bool/dt (buffer plano, idêntico a f64) e str (offset-based,
  reconstruído por append — mesmo padrão de ffill/bfill, não view). Descritores
  bool/str/dt ligam `shift`.
- Fallback Lua **removido por inteiro** de `_cumulative.lua`: `methods.shift` só
  valida `periods` inteiro e delega ao C (guard defensivo se dtype sem shift).
  Categorical tem shift próprio (sobre codes) e já tratava negativo — agora
  Series/DataSet/categorical têm a MESMA semântica de sinal em todos os caminhos.
- Testes: C +29 (test_ops_window 285→314: shift negativo de f64/i64 — antes sem
  cobertura — e shift em bool/str/dt nos dois sentidos, com NA, bordas, all-NA);
  Lua +13 (test_window 80→93); allocfail +28 (1677→1705, incl. `str_shift` sob
  OOM nos dois sentidos). DataSet 5.3 shift negativo confirmado (delega ao C).
- `[Fedora]`: aguarda Valgrind + cobertura no Fedora para `[Done]`. Atenção ao
  ramo `|periods|>=size` e ao `str_shift` sob OOM na cobertura.

---
## 2026-06-29 — Item 7.1a: ffill/bfill no Ring 0 (bool/str/dt)

Continuação da meta-decisão D7 (item 7 vai pro C, sem fallback). Recorte: o 7.1
foi dividido em **7.1a (ffill/bfill)** e **7.1b (shift com sinal)** — separar a
adição pura (ffill/bfill, sem mudança de ABI) da mudança de ABI do shift facilita
bissectar se o Valgrind/cobertura do Fedora acusar algo.

- 7.1a: `ffill`/`bfill` agora no C para bool/str/dt (antes: fallback Lua
  element-wise em `_cumulative.lua`). bool/dt são buffer plano → idênticos a f64.
  **str é offset-based**: a série nova é reconstruída por `append`/`append_null`,
  reusando o padrão de `smaug_str_take` (gather posicional). NÃO usa `view`, então
  a limitação de view-em-string do COW.md não se aplica (produz cópia completa).
- Wiring: protótipos nos headers (`smaug_numeric.h` bool, `smaug_datetime.h`,
  `smaug_string.h`), cdef FFI, e `ffill`/`bfill` ligados nos descritores bool/str/dt
  (`_types.lua`).
- Fallback Lua **removido** de `_cumulative.lua`: `methods.ffill`/`bfill` agora só
  delegam ao C, com guard defensivo (erro orientado se um dtype sem ffill chegar —
  bug de programação, fail-fast em vez de fallback silencioso). Categorical tem
  implementação própria (opera sobre codes) e NÃO passa por aqui — intacto.
- Testes: C +41 (test_ops_window 244→285: bool/str/dt com NA, bordas, all-null,
  string vazia válida e multibyte); Lua +18 (test_window 62→80); allocfail +45
  (1632→1677) varrendo todos os ramos de OOM dos novos ffill/bfill (incl. o
  `malloc(src)` do `str_bfill`). O teste DataSet "5.3 ffill em string" passou a
  exercitar o C novo — vira guard da migração de graça.
- Coerência: shift negativo segue sem cobertura em lugar nenhum (será coberto no
  7.1b, quando mover pro C). Eixo 1 do parity não tinha exceptions de ffill/bfill
  (a mudança foi interna Lua→C, invisível à paridade de API).
- `[Fedora]`: aguarda Valgrind + cobertura no Fedora para `[Done]`.

---
## 2026-06-29 — Item 7.4: bool eq/ne no Ring 0

Meta-decisão D7: todo o item 7 vai pro C (Anel 0), Lua só delega, sem fallback —
coerência de arquitetura (o engine é dono do buffer e da máscara).

- 7.4: bool era o único dtype sem igualdade (`eq`/`ne`). f64/i64/dt/str já tinham
  no C. Adicionado `smaug_bool_eq`/`smaug_bool_ne` (espelham `smaug_f64_eq`:
  compara com escalar 0/1 → máscara uint8_t + out_mask; NA → 0 com máscara NULL,
  preservando a nulidade). Wiring: header, cdef FFI, `cmp_eq`/`cmp_ne` no descritor
  bool (`_types.lua`, converte `true/false`→`1/0`).
- Testes: C bool lifecycle 154→165 (incl. NA, threshold não-normalizado, NULL
  series); Lua selection 21→27 (Kleene: comparar com NA → NA); allocfail +20 (1632)
  varrendo os ramos de malloc de eq/ne — para a cobertura fechar no Fedora.
- `[Fedora]`: aguarda Valgrind + cobertura no Fedora para `[Done]`.



Levantamento a partir do output real do parity (terra firme): 83 assimetrias
classificadas em 3 baldes — intencional (dimensionalidade 1-D vs 2-D), par de nome,
gap real. Nada suposto; cada par/gap aterrado no fonte.

- 6.1 `Series:dtype()` — string do dtype (par singular de `DataSet:dtypes`).
- 6.2 `sort`/`sort_by`: mantidos os dois (Series ordena valores; DataSet ordena
  linhas por coluna — assinaturas diferentes por natureza). Sem rename; pareados
  no auditor.
- 6.3 `Series:sample(n,[seed])`, `:to_string([opts])`, `:to_markdown()` — pares do
  DataSet (sample espelha take; render em 1 coluna).
- 6.4 **eixo 02 reescrito** de diff de presença para **paridade classificada**:
  pares de nome (len↔nrows, dtype↔dtypes, sort↔sort_by) tratados no script; 74
  assimetrias intencionais registradas em `exceptions.txt` (agrupadas por
  categoria); **falha (os.exit) em gap real não-registrado** — vira guard como os
  outros eixos. O `expected_pairs` morto virou lógica viva.
  Resultado: 48 ambos · 6 pares · 74 intencionais · **0 gaps reais**.
- 6.5 `DataSet:clone()` — cópia profunda (par de `Series:clone`); gap achado no
  levantamento. Cada coluna clonada; nome/ordem preservados.
- Tudo Lua-puro. Testes: Series acesso 25→34, DataSet core 207→212. Docs
  (API_INDEX) atualizados. Parity 12/12. Aguarda Fedora + Windows para `[Done]`.

## 2026-06-28 — Item 5 completo: element-wise + transforms (5.2/5.3)

### 5.2 element-wise → DataSet mesma forma
- `df:abs/round/clip/cumsum/cummin/cummax/cumprod`. Helper `map_frame` aplica a
  redução da Series a cada coluna (fonte única). **D4-i:** operação numérica
  **erra** se houver coluna não-numérica, nomeando-a ("selecione as numéricas
  antes"). Contraste com 5.1: reduções mudam a forma → pulam não-numéricas;
  element-wise preserva a forma → não dá pra descartar/passar em silêncio.
### 5.3 transforms
- `df:ffill/bfill/shift` (qualquer dtype), `df:diff` (numérico, D4-i).
- `df:isna/notna` → DataSet **bool**, todas as colunas. Construído via `is_null`
  por índice (Series:isna é escalar por índice, não vetorizado — observação
  registrada; o DataSet não depende dele).
- `df:astype({col=dtype})` (**D4-A**, mapa explícito); colunas fora do mapa seguem
  inalteradas (compartilhadas; Series são COW). Erro em coluna inexistente ou se o
  argumento não for mapa.
- Tudo Lua-puro sobre a 5.0 (Anel 0 já validado no Fedora). DataSet stat: 49→90
  checks. **Item 5 fecha** por equivalência Fedora; follow-up `build_win.ps1`.

---
## 2026-06-28 — Item 5: reduções DataSet (5.1), min_count (5.5), delegação GroupBy (5.4)

### 5.1 — reduções por coluna → DataSet 1-linha (D1)
- `df:sum/mean/min/max/std/var/median/prod/quantile/skew/kurtosis/mad/sem/
  count_nonnull` → DataSet de **1 linha**. Cada coluna mantém SEU dtype de
  resultado (sum de i64→i64 e mean→f64 convivem — por isso 1-linha, não Series
  posicional; decisão D1). Só colunas numéricas; sem numérica → erro. Helper
  `reduce_frame` delega às reduções da Series (fonte única).
### 5.5 — min_count opt-in em sum/prod (Series e DataSet)
- `Series:sum(ignore_na, min_count)` / `:prod(...)`; `DataSet:sum(min_count)` /
  `:prod(...)`. Default (0) preserva o atual (sum de vazio/all-null = 0).
  `min_count=N` exige N não-nulos, senão NA.
### 5.4 — GroupBy delega às reduções da Series (elimina duplicação)
- `agg_sum/mean/min/max/std/var/median/prod/nunique` deixaram de reimplementar
  inline — agora `col:take(idx):<redução>()`. Behavior-preserving (groupby 60
  checks intactos): possível só após a 5.0 reconciliar ddof (std/var amostrais nos
  dois lados). `first`/`last` seguem inline (posicionais, sem redução-Series).
- Tudo Lua-puro sobre a fundação 5.0 já validada no Fedora. Falta 5.2 (element-wise)
  e 5.3 (transforms), pendentes de decisão D4 (não-numéricas).

---
## 2026-06-28 — Item 5 (fundação 5.0): reconciliação de ddof em std/var

### Achado em sessão (bloqueava o item 5)
- O `ddof` estava **incoerente em três vias**: `Series:std/var` eram populacionais
  (÷N, no C `smaug_f64_var`/`smaug_i64_var`, comentado "populacional"), mas
  `cov`/`skew`/`kurtosis`, o GroupBy (`agg_std`/`agg_var` ÷ n-1) e o pandas são
  amostrais (÷ N-1). A delegação do 5.4 era impossível: `groupby:std` (amostral)
  não pode chamar `Series:std` (populacional) — números diferentes.
- Um D2 inicial (alinhar Series→nil em n<2 assumindo amostral) foi tentado e
  **revertido** — partia da premissa errada; os testes "var populacional" pegaram.
  Bom exemplo de "behavior-identical exige prova": a suíte é o guard.

### Decisão (Opção A) e implementação
- **Tudo amostral (ddof=1).** C `smaug_f64_var`/`smaug_i64_var`: ÷(n-1), NaN para
  n<2 (std = sqrt herda). Removidos 2 `COV-EXCL-BR` (o ramo n<2 agora é alcançável
  via n=1). Alinha Series com cov/skew/kurtosis, GroupBy e pandas.
- 3 asserções recalculadas (var de {10,20,30}: 200/3→200/2=100; std→10; var/std de
  1 elemento: 0→NA) em test_constructors e test_access.
- Docs: API_INDEX e API_Reference de "populacional (÷N)" para "amostral (÷ N-1;
  <2 → NaN)".
- **Toca Anel 0 → `[Fedora]`:** precisa de Valgrind + cobertura para fechar. Build
  Linux verde (suíte idêntica fora os 3 valores recalculados).

---
## 2026-06-28 — Timeline item 4: NA relacional unificado + Contrato 8

### Política (mudança de comportamento — adição de contrato, não refatoração)
- **Contrato 8: NA em chave relacional é erro.** Antes, três tratamentos
  divergentes: join **casava** NA com NA (`key_to_str(nil)="\0NULL\0"`), groupby
  **errava** (correto), pivot/pivot_table **descartavam a linha em silêncio**
  (`if iv ~= nil and cv ~= nil` — perda de dado calada, pior que "aceitar"; o
  roadmap subdescreveu como "aceita"). Agora os quatro erram de forma orientada.
- **Helper central `validate_keys_no_na(named_cols, op_name)`** (local em
  `_relational.lua`, onde vivem os consumidores). Valida **só** colunas-chave,
  nunca a coluna de valores. Mensagem única:
  `smaug: <op> — coluna 'X' contém NA; trate com fillna ou dropna antes`.
- Aplicado eagermente no corpo de cada método público (join/groupby/pivot/
  pivot_table), nível de erro uniforme. groupby: check inline removido do
  `multi_argsort` (que é exclusivo de groupby) e centralizado no `methods.groupby`;
  mensagem antiga ("tem nulos; use dropna primeiro") trocada pela padrão (agora
  menciona fillna).
- **Coerência:** validar chave relacional é conceito de **Anel 2**; o C (Anel 0)
  segue genérico. Nenhum C tocado — política mora na camada Lua, mantendo a
  separação de anéis e alinhando o Anel 2 ao Contrato 6.

### Decisões e achados
- **Os dois pivots:** roadmap nomeou só `pivot_table`; `pivot` tinha o mesmo
  silent-drop. Incluídos ambos (senão a incoerência persistiria).
- **Número do contrato:** roadmap dizia "Contrato 7", mas 7 já existe ("índices
  1-based"). Documentado como **Contrato 8**; referência do roadmap corrigida.
- **Sem quebra de teste existente:** o comportamento antigo (join casa NA, pivot
  descarta) estava **sem cobertura** — foi por isso que derivou. O teste de
  groupby-NA só checava `not ok` (sobreviveu à troca de mensagem). 8 testes novos
  (4.6) travam os quatro: chave simples, NA na coluna `columns` do pivot, composta
  no groupby, validação dos dois lados no join, e NA em coluna de valores NÃO
  dispara.
- **Observação (não acionada):** join não expressa chave composta multi-coluna
  via lista de strings — `{"a","b"}` é a forma par-renomeado `{chave_esq,
  chave_dir}`, não composta. Quirk pré-existente da API de join, fora do escopo
  do item 4. Registro para eventual avaliação futura.

### Fechamento
- `[Windows]` Lua-puro, mesma categoria dos itens 2/3 (nenhum C tocado). Build
  Linux verde, parity 12/12. **Mudança de comportamento** + contrato novo, então
  os testes são o guard. Fecha por equivalência Fedora com confirmação do
  `build_win.ps1`.

---
## 2026-06-28 — Timeline item 3: bool_view (exposição na camada Lua)

### Exposição (C já existia e estava testado)
- **`bool_view` exposto** no descritor bool (`_types.lua`): uma linha
  `view = C.smaug_bool_view`. O C já tinha `smaug_bool_view` + COW interno, com
  cobertura completa em `test_allocfail.c` (view, cow_set/set_null/append/
  append_null + OOM). Item 3 é exposição + coerência de docs, não comportamento C novo.
- **Justificativa "imutável" derrubada:** BoolSeries tem `set`/`set_null`, é
  mutável; view + COW idênticos a f64/i64/dt.
- **Exceptions contraditórias removidas** (`parity/exceptions.txt`): `1:view/bool`
  ("bool tem view?") e `10:view/bool` ("imutável... nada a destacar"). As de string
  e categorical permanecem.
- **Mensagem de erro do `view()` por razão correta (3.3):** string → "ainda não
  suportado (planejado)"; categorical → "não se aplica (sem buffer compartilhável)".
  *Correção durante a implementação:* a primeira tentativa pôs o branch de
  categorical em `methods.view`, que CategoricalSeries nunca alcança (metatable
  própria) — era código morto, dava o erro cru `attempt to call method 'view'`.
  Movido para um stub `CategoricalSeries:view()`.
- **Teste Lua (3.4):** bool view + COW (reflexo da pai, detach em set/set_null/
  append, OOB) + asserções das mensagens de erro de string/categorical.
- **COW.md (3.5):** bool → ✅ view / ✅ COW; removidas as frases falsas de
  imutabilidade; bool adicionado às tabelas de funções C.

### Achado registrado (10.7)
- `test_constructors.lua` re-declara `local n_ok` por seção e imprime só no fim:
  headline "98 checks" subconta o real (~328 rodam). Cobertura é real (cada
  `check` aborta em falha); só o número engana. Registrado no item 10, não tocado
  (fora de escopo do item 3).

### Fechamento (Done — via Fedora)
- **Reavaliação de risco:** classifiquei o item como "expõe C, precisa de Windows",
  mas estava errado — item 3 **não tocou C** (só `.lua`/`.txt`/`.md`), e
  `smaug_bool_view` já estava no cdef do FFI com ABI idêntica à de `smaug_f64_view`
  (já provada no Windows). É a mesma categoria Lua-pura do item 2, não expõe C novo.
- Fechado por equivalência Fedora: suíte Lua verde (incl. bool view+COW), parity
  12/12 (eixos 1 e 10 coerentes), Valgrind-clean. Follow-up leve: confirmar no
  `build_win.ps1`. A regra "C novo não fecha por equivalência" segue válida;
  o item só não se enquadra nela.

---
## 2026-06-28 — Fechamento dos itens 1 e 2 + recuperação de regressão no entry point

### Itens fechados
- **Item 1 (Done, Fedora):** Valgrind-clean nos 12 binários (`ERROR SUMMARY: 0
  errors`, incl. allocfail e stress), suíte idêntica ao baseline, cobertura
  Linha 98.86% / Branch-alvo 95.63%. Refatoração pura de nulidade confirmada.
- **Item 2 (Done via Fedora):** Lua puro, sem C tocado. Critério `[Windows]`
  suprido por validação Fedora (mesmo LuaJIT; parity eixo 09 OK; ponto sensível
  do `_dt.lua` exercitado de fato). Follow-up leve: confirmar com
  `build_win.ps1`. **Equivalência vale só por ser Lua puro — não é regra.**

### Incidente: `lua/smaug/init.lua` (entry point) sobrescrito
- Na aplicação do item 2, o orquestrador da Series (`core/series/init.lua`) foi
  parar no entry point de topo (`lua/smaug/init.lua`), deixando os dois idênticos
  e ambos com `return Series`. Efeito: `require("smaug")` devolvia a Series
  achatada, sem o campo `.Series` — **todas** as 18 suítes Lua morriam na primeira
  linha, e o `build.sh` (`set -euo pipefail`) abortava no 1º teste Lua sem
  imprimir o erro. Não era específico do Fedora; reproduzia em qualquer lugar.
- **Causa:** dois arquivos distintos chamados `init.lua` em caminhos diferentes;
  na aplicação manual, um sobrescreveu o outro.
- **Correção:** entry point restaurado a partir do estado pré-regressão (não
  reconstruído de memória). Itens 1 e 2 nunca tocaram esse arquivo.
- **Aprendizado:** ao entregar/aplicar arquivos `init.lua`, sempre conferir o
  caminho completo e que `lua/smaug/init.lua` (termina em `return smaug`) e
  `lua/smaug/core/series/init.lua` (termina em `return Series`) permaneçam
  distintos. Se ficarem idênticos, o sintoma é `attempt to index ... 'Series'`.

---
## 2026-06-26 — Timeline item 2: sentinela único na camada Lua

### Refatoração (consumo do central — sem mudança de comportamento)
- **`_dt.lua` consome o sentinela i64 central** em vez de reinventá-lo. Removidos
  o literal cru `-9223372036854775808` (sem `LL`, virava double e batia por
  coerção frágil) em três sites e o `DT_SENTINEL` local. Produção usa `I.I64_MIN`;
  detecção usa `is_int_sentinel` (mesmo idioma de `reduce_num` em `_core.lua`).
- **Sentinela i64 documentado** na definição central (`series/init.lua`): os dois
  contextos — leitura de elemento (C devolve 0 + status `SMG_NULL_VALUE`; o 0 não
  é sentinela) vs. redução posicional (C devolve `I64_MIN`, detectado por
  `is_int_sentinel`).
- **NaN centralizado — produção e teste:**
  - Produção: `I.NAN` já existia; `_stat_adv.lua` passou a consumi-lo (três `0/0`
    crus removidos). O roadmap supunha que faltava criar a constante — só faltava
    consumir.
  - Teste: o predicado central `is_nan` era reinventado inline (`v ~= v`) em
    `_transform.lua` (que já o importava sem usar), `_stat_adv.lua` e
    `_factories.lua`. Todos passam a consumir o central. (achado de uma varredura
    ampla de sentinelas pedida em sessão; mesma natureza do item 2, registrado e
    incorporado ao 2.4.)
- **Garantia verificada:** varredura completa da camada Lua — os literais/predicados
  de sentinela (`I64_MIN`, `NAN`, `is_nan`) agora nascem em um único lugar
  (`series/init.lua`); todo o resto consome. Nenhuma outra reinvenção.
- **Lacuna registrada (não infração):** não há `is_inf`/`is_finite` central; checagens
  `== math.huge` seguem inline por falta de quem consumir. Eventual helper futuro.
- **Prova:** suíte completa verde, contadores idênticos ao baseline, parity 12/12
  (eixo 09 sentinels incluso). Item `[Windows]`, Lua puro — sem impacto em memória
  C (Valgrind n/a) nem cobertura C (gcov n/a).

---
## 2026-06-26 — Timeline item 1: fonte única de nulidade no Ring 0

### Refatoração (interna — sem mudança de contrato público)
- **Centralização da convenção de máscara de nulos em `smaug_types.h`.** Antes,
  o invariante mais central do motor (válido / NA) era testado por quatro macros
  divergentes (`VALID` em ops_f64/i64 baseada na série; `VALID_DT` em datetime;
  `VALID(m,i)` em ops_bool com assinatura *e* semântica diferentes) e por testes
  crus `== 0xFF`/`== 0x00` espalhados em core, str, ops_window e ops_str. Passou a
  existir uma fonte única.
- **Símbolos no lugar dos literais:** `SMAUG_MASK_VALID`/`SMAUG_MASK_NULL`. Toda
  escrita de máscara (`= 0xFF`, `memset`, ternários) passou a usá-los; nenhum
  literal cru de máscara permanece em código.
- **Dois contratos, por design, não por descuido:**
  - `SMAUG_VALID(mask,i)` / `SMAUG_NULL(mask,i)` — máscara presente exigida; passar
    NULL é bug e deve falhar (não silenciar). Usado por f64/i64/dt/str e pelos
    testes antes crus.
  - `SMAUG_OPTIONAL_VALID(mask,i)` — máscara opcional (NULL = "todos válidos"),
    contrato exclusivo das funções livres do bool (`smaug_bool_*`). O guard de
    NULL que o ops_bool reinventava virou esse macro nomeado. A unificação num
    único macro permissivo foi recusada: esconderia máscara ausente em código de
    Series (falha visível > acerto adivinhado).
  - `SMAUG_NULL` é, por construção, a negação de `SMAUG_VALID` — não podem divergir.
- **Escopo:** item trata dos *testes* de nulidade (1.3); incluiu ops_window/ops_str
  além de core/str (o roadmap citava os dois como exemplo, não lista exaustiva).
  Escritas ganharam o símbolo, mas **não** um setter (`SMAUG_SET_*`) — abstração
  fora de escopo, eventual subitem futuro.
- **Prova de pureza:** suíte completa verde com contadores idênticos ao baseline,
  8 arquivos tocados compilam com `-Wall -Wextra -Werror`. Confirmação final
  (Valgrind-clean + cobertura) pendente no Fedora, conforme critério `[Fedora]`.

---
## 2026-06-23 
- docs(roadmap): sincroniza métricas reais (cobertura 95.83%, checks por suíte), enxuga Blocos H/E, adiciona Bloco I (fechamento de coerência pré-v1.0) e registra achados da auditoria código-vs-código (dt_view, rank i64, rolling-dup, I3/I4)

## 2026-06-22 — Fase 5: cobertura dos parsers + correção de double-free sob OOM

### Corrigido
- **Double-free em `smaug_read_json_mem` sob OOM** (3 sites de limpeza): em
  falha de alocação durante a montagem de colunas, `col_names`/`dtypes` eram
  liberados manualmente antes de um `goto oom_recs` compartilhado que liberava
  de novo. Corrigido anulando os ponteiros após a liberação. Reproduzido por
  varredura de injeção de falha e validado Valgrind-clean (534 allocs = 534
  frees, 0 erros).
- **Double-free em `parse_record` sob OOM** (descoberto ao escrever teste de
  registro JSON largo): no crescimento do array de campos, se o `realloc` de
  `keys` sucede mas o de `vals` falha, `rec->keys` ficava apontando para o
  bloco antigo já liberado pelo realloc bem-sucedido — `free_record` do caller
  dava double-free. Corrigido atualizando `rec->keys`/`rec->vals` imediatamente
  após cada realloc bem-sucedido. Validado Valgrind-clean (1962 = 1962 frees).

### Testes / Hardening
- **Harness de allocfail estendido para `calloc` e `strdup`**: `--wrap=malloc,
  realloc` não intercepta esses dois (resolvem internamente na libc), deixando
  todos os guards de OOM sobre eles sem exercício. Adicionados `__wrap_calloc`
  e `__wrap_strdup`; flag propagada às quatro configurações de build (Makefile,
  build.sh, make_coverage.sh, build_win.ps1). Verificações 1492 → 1515
  (inclui sweep de OOM em `multi_argsort`/`multi_argsort_ffi`, antes sem
  cobertura de falha de alocação).
- **Cobertura branch-alvo dos parsers** (medição Fedora autoritativa):
  - `smaug_csv.c`: 82.64% → 90.53%
  - `smaug_json.c`: 72.30% → 89.80%
  - `smaug_datetime.c`: 72.77% → 92.40%
  - `smaug_ops_window.c`: 85.26% → 95.98%
  - **Total do backend C: 89.06% → 95.83%** (cruzou a meta global de 95%)
- Diagnóstico de densidade de teste por região (não por contagem de checks):
  revelou que os 6 macros `DT_CMP_IMPL` (gt/lt/eq/ge/le/ne) estavam testados
  de forma rasa — 1 cenário de null × 6 operadores, deixando ~28 branches
  descobertos (ramo `out_mask==NULL`, OOM de result/mask). Fechados com teste
  funcional `out_mask=NULL` nos 6 + `af_dt_compare` no allocfail.
- Auditoria de exclusões: categoria C (conveniência disfarçada) substituída por
  testes reais; categoria D (inalcançável fraco) validada por instrumentação +
  400k checks e promovida a A com justificativa formal. Condições redundantes
  (`st==NULL_VALUE || st!=OK`; `v->s != NULL` garantido) simplificadas, não
  excluídas. Novos `COV-EXCL-BR` honestos: `encode_utf8` com cp>0x10FFFF,
  ramos de pureza de inferência de dtype, while-body de deque inalcançável.

## 2026-06-21 — Aritmética numérica: promoção de tipos e divisão verdadeira


## 2026-06-20 — Coerência de construção: inferência universal de dtype

Implementação da camada Lua das decisões de coerência de API tomadas na
sessão de design anterior. Tema: a construção a partir de dados infere o
dtype de forma consistente em todos os pontos de entrada; quando o valor é
ambíguo, o engine recusa em vez de adivinhar.

### Adicionado

- **`Series` chamável:** `smaug.Series({1,2,3})` agora funciona, espelhando
  `smaug.DataSet({...})`. Alias `Series.from_array` (mantém `from_table`).
  Ambos despacham dinamicamente para `from_table`, preservando a interceptação
  de `categorical` feita no orquestrador.
- **`Series.infer_dtype`** — fonte única de inferência de dtype, reusada por
  `Series.from_table`/`full`/`__call`, `DataSet.from_columns`/`__call` e
  `Series:map`. Antes a regra estava duplicada (uma cópia no `DataSet.__call`,
  outra implícita no `map`) e divergente.

### Corrigido — incoerências de construção

- **Fim do default-float64 silencioso:** `Series.from_table` e
  `DataSet.from_columns` sem dtype caíam em `float64` independente do conteúdo;
  uma lista de strings ou booleans quebrava no `set`. Agora inferem como os
  demais construtores.
- **Bool inferido de boolean nativo:** uma lista `{true, false}` sem dtype
  agora vira `bool` (Series, DataSet e broadcast `df["c"] = true`). Antes virava
  `int64`/`float64` e quebrava ou perdia o tipo. Inferência de bool só a partir
  de `boolean` Lua — nunca de `0`/`1` ou `"yes"`/`"no"` (seria adivinhar
  semântica). Lista vazia ou toda-nula → `string` (fallback universal).
- **`map` reconhece retorno boolean:** `s:map(fn)` com `fn` devolvendo
  `true`/`false` agora infere `bool`, inclusive respeitando `dtype="bool"`
  explícito. Antes falhava — a validação rejeitava o booleano antes de honrar o
  dtype declarado.

### Decisões de contrato

- **`astype("bool")` numérico é rígido:** aceita apenas `0`→false e `1`→true
  (e `0.0`/`1.0`). Qualquer outro valor é erro orientando para `:map(fn)`, em
  vez da coerção estilo C (`≠0 → true`), que adivinhava semântica e contradizia
  o construtor rígido. String→bool inalterado (`"true"`/`"false"`, resto → null).
- **`assign` é imutável, inclusive ao substituir coluna:** retorna sempre um
  DataSet novo; o original nunca é mutado, nem quando a coluna já existe.
  Comportamento já existente, agora fixado por teste e documentado.

`test_constructors.lua`, `test_core.lua` — testes atualizados para o novo
comportamento (bool inferido, astype rígido com casos de erro explícitos) e
novo teste de imutabilidade do `assign` ao substituir coluna. Removida uma
duplicação acidental de bloco em `test_core.lua`.

### Docs

`API_INDEX.md` — `assign` marcado como retornando novo DataSet, consistente
com `filter`/`fillna`/`drop_duplicates`/`rename`.

---

## Aritmética numérica: promoção de tipos e divisão verdadeira

Segunda parte da mesma sessão. Tema: operações aritméticas entre numéricos não
barram o que é matematicamente sem ambiguidade, nem corrompem silenciosamente.
Toda a mudança é na camada Lua (o despacho de operadores); nenhuma função C mudou
— a cobertura permaneceu idêntica, confirmando que nenhum caminho novo foi criado.

### Corrigido

- **Promoção numérica em operações:** `int64` e `float64` em lados opostos de
  `+ - * /` agora promovem para `float64`, em vez de barrar com erro de tipo.
  `df["valor"] * df["quantidade"]` (float × int) passa a funcionar. Mistura com
  não-numérico (bool/string/datetime) continua sendo erro.
- **Truncamento silencioso de escalar (bug):** `int_series * 2.5` produzia
  `int64` truncando o escalar para `2` (resultado `4` em vez de `5.0`) — corrupção
  silenciosa. Agora o escalar fracionário sobre série int64 promove a série a
  `float64` antes da operação, e o resultado é correto.

### Decisões de contrato

- **`/` é divisão verdadeira:** `int64 / int64` agora produz `float64`
  (`7 / 2 = 3.5`), alinhado a Python 3, numpy e polars. Antes fazia divisão
  inteira truncada (`7 / 2 = 3`).
- **`:floordiv(outra)` — divisão inteira explícita:** repõe o comportamento que
  `/` deixou de ter. Produz `int64` truncado (`7 // 2 = 3`); divisão por zero → null.
  Exige operandos int64 (float orienta a usar `/` e converter). É o primeiro
  método aritmético nomeado da Series.

`test_constructors.lua` — testes de aritmética atualizados para o novo contrato
(promoção, `/` float) e bloco dedicado novo cobrindo promoção série×série,
série×escalar (incl. o caso que antes corrompia), `/` verdadeira e `:floordiv`.

### Docs

`API_INDEX.md` — documentada a semântica de promoção, `/` verdadeira e o método
`:floordiv`.

---

## 2026-06-17 — Sincronização dos scripts de build com a estrutura da Fase 4

Auditoria completa de `scripts/` (a pedido), motivada pela revisão do Roadmap.
A Fase 4 reorganizou os testes em subpastas (`tests/c/`, `tests/series/`,
`tests/dataset/`, `tests/io/`, `tests/props/`), mas os scripts de build não
acompanharam — continuavam apontando para os arquivos legado na raiz de
`tests/`. A auditoria revelou dois bugs reais (não apenas cosméticos), além da
divergência estrutural.

### Bug 1 — `.so` incompleta no `build.sh` (corrigido)

`build.sh` montava `build/libsmaug.so` a partir de 9 fontes, **sem**
`src/smaug_ops_window.c`. Esse arquivo define `smaug_multi_argsort_ffi` e toda
a família `smaug_{f64,i64}_rolling_*` — símbolos que o `ffi_loader.lua` declara
e consome. A `.so` gerada pelo `build.sh` ficava sem eles: qualquer uso de
rolling ou sort multi-coluna pelo frontend Lua quebraria em runtime com símbolo
indefinido. Confirmado por `nm -D` (0 símbolos antes, 10 depois). O Makefile e
o `build_win.ps1` (que descobre `src/*.c` por glob) já estavam corretos —
o bug era exclusivo do `build.sh`.

### Bug 2 — cobertura cega em `make_coverage.sh` (corrigido)

`make_coverage.sh` não incluía `smaug_ops_window` nos `SRCS` instrumentados nem
`test_ops_window` na lista de testes C. Resultado: as primitivas migradas para
Ring 0 na Fase 3 (cumsum, cumprod, cummin, cummax, diff, shift, ffill, bfill,
argmin, argmax, sorted_nonnull, rank, multi_argsort, rolling) ficavam **fora da
medição inteira de cobertura** — invisíveis ao gcov. Agora entram na medição do
Fedora pela primeira vez.

### Divergência estrutural — scripts realinhados à Fase 4

Três fontes de build apontavam para o legado da raiz; agora todas usam a
estrutura por domínio:

- **`build.sh`** — `SRCS` += `smaug_ops_window.c`; `C_TESTS_PLAIN` += `test_ops_window`;
  testes C compilam de `tests/c/`; `LUA_TESTS` passou a listar as 18 suítes em
  subpasta (`series/…`, `dataset/…`, `io/…`, `props/…`).
- **`build_win.ps1`** — testes C de `tests\c\`; lista Lua atualizada para as
  18 suítes; normalização de separador (`/`→`\`) no caminho do luajit; cabeçalho
  corrigido (era "8 suites Lua").
- **`make_coverage.sh`** — `SRCS` e `C_TESTS` corrigidos (ver Bug 2); testes C e
  `test_allocfail` de `tests/c/`; `LUA_TESTS` para as 18 suítes; comentário do
  cabeçalho citava `test_enrich_c` (inexistente) — corrigido.
- **`Makefile`** — embora fora de `scripts/`, é a "fonte única" que os scripts
  espelham. Compilava os testes C da raiz (`tests/$t.c`); realinhado a
  `tests/c/$t.c` nos três alvos (`test`, `test-stress`, wrap). Sem isso,
  `make test` quebraria ao remover o legado.
- **`scripts/parity/11_test_coverage.lua`** (Eixo 11) — lia 5 arquivos
  inexistentes na raiz (que retornariam 0 checks); reapontado para as 18 suítes
  reais. Os demais eixos (01–10, 12) e `common.lua` já tinham fallback
  mono↔pasta e não precisaram de mudança.

### Lixo removido

`scripts/parity/PARITY_REPORT.md` — relatório de paridade órfão (gerado em
14/jun). Os scripts `parity.sh`/`parity.ps1` escrevem em `docs/PARITY_REPORT.md`;
essa cópia em `scripts/parity/` nunca era regravada e entrava no MANIFEST
indevidamente. Removida.

### Legado da raiz removido

Após o realinhamento, os 28 `.lua` + 12 `.c` + 5 fixtures (`.csv`/`.json`) na
raiz de `tests/` tornaram-se órfãos — nenhum script ativo os referenciava.
Removidos. Teste de fogo antes da remoção: mover todo o legado para fora e rodar
`build.sh` + `make test` + `make test-stress` — tudo passou apenas com a
estrutura nova, confirmando zero dependência residual.

### Validação

`build_win.ps1` verde no Windows (MSYS2-UCRT64): DLL com 10 fontes, 12
testes C (incl. `test_ops_window` 207 checks, `test_io_c` 190 checks), 18 suítes
Lua, 12 eixos de paridade OK, property-based 360 862 checks. MANIFEST: 113
arquivos (era 154 antes da limpeza). Valgrind + cobertura no Fedora pendentes
(autoritativos; gcov não é confiável no Windows).

**Métricas de doc desatualizadas (a corrigir na revisão do Roadmap):** o Anel 0
no Roadmap ainda cita `test_io_c` com 174 checks (real: 190), não menciona
`test_ops_window`, e diz "9 binários" (real: 12). Essas e outras inconsistências
ficam para a sessão de revisão do Roadmap.

---

## 2026-06-16 — Fase 4: reorganização estrutural (series/, dataset/, tests/)

Reorganização dos monolíticos do Ring 1 em módulos coesos e da suíte de testes
em subpastas por domínio. Zero alteração de comportamento — todas as sessões
confirmadas por `make test` + `make test-lua` + `parity.sh 12/12`.

### Ciclo 1 — series.lua (4389 linhas) → series/ (16 submódulos)

`lua/smaug/core/series.lua` desmembrado em:

```
series/
├── init.lua               ← orquestrador (17 etapas)
├── _types.lua             ← DTYPES (5 descritores)
├── _core.lua              ← metatipo Series, methods, wrap, check_*, require_op
├── _factories.lua         ← new, float64, int64, from_table, full
├── _bool_ops.lua          ← bool_mask_parts, binop, kleene_binop, metamétodos
├── access/_access.lua     ← get, set, is_null, set_null, append, len, clone
├── access/_transform.lua  ← sort, argsort, view, take, head, tail, astype, fillna, map
├── stats/_reduce.lua      ← sum, mean, min, max, var, std
├── stats/_stat.lua        ← prod, median, quantile, mode, unique, nunique, value_counts, describe
├── stats/_stat_adv.lua    ← cov, corr, rank, pct_rank, skew, kurtosis, mad, sem
├── window/_cumulative.lua ← cumsum, cumprod, cummin, cummax, diff, shift, ffill, bfill, argmin, argmax
├── window/_rolling.lua    ← SeriesRolling + SeriesExpanding
├── selection/_predicates.lua ← between, isin, is_unique, is_monotonic_*, equals, compare,
│                                idxmin, idxmax, first/last_valid_index, duplicated, searchsorted, rep_each
├── selection/_selection.lua  ← where, mask, ifelse, nlargest, nsmallest, gt/lt/eq/ge/le/ne,
│                                filter, land/lor/lxor/lnot, sin/cos/..., isna, notna
├── text/_str.lua          ← StrProxy Tier A+B+C
├── temporal/_dt.lua       ← SeriesDT (base + F.3) + SeriesAt
└── categorical/_categorical.lua ← CategoricalSeries + CatProxy
```

Mecanismo: cada submódulo é `return function(I)` onde `I` é o módulo interno
montado progressivamente em `init.lua`. Zero `require` cruzado entre submódulos;
upvalues passados via `I`. `scripts/parity/common.lua` ganhou `read_series_lua()`
para análise estática de paridade com a estrutura em pasta.

### Ciclo 2 — dataset.lua (2256 linhas) → dataset/ (4 submódulos)

`lua/smaug/core/dataset.lua` desmembrado em:

```
dataset/
├── init.lua         ← orquestrador (4 etapas)
├── _core.lua        ← factories, CRUD, acesso, seleção, assign, nunique, rename,
│                       describe, to_table, __tostring, __index, __newindex, __len, __call
├── _relational.lua  ← concat, join, GroupBy, pivot, melt, pivot_table, stack, unstack, explode
├── _stat.lua        ← corr, cov, equals, compare, duplicated, drop_duplicates, Rolling DataSet
└── _io_support.lua  ← at, iat, insert, to_dict, from_dict, to_markdown, to_string
```

Mesmo mecanismo de `I` do Ciclo 1. `I.map_columns` e `I.cell_str` exportados
por `_core.lua` para uso nos submódulos subsequentes.
`scripts/parity/common.lua` ganhou `read_dataset_lua()`.

### Ciclo 3 — tests/ reorganização (28 arquivos → 18 suítes em subpastas)

```
tests/
├── series/    ← 10 suítes (constructors, access, reduce, stat, window,
│                 predicates, selection, str, dt, categorical)
├── dataset/   ← 4 suítes (core, relational, stat, io_support)
├── io/        ← 2 suítes (test_csv, test_json)
├── props/     ← 2 suítes (test_props, test_integration)
├── fixtures/  ← 5 arquivos de dados (cotacoes.*, pedidos_digitados.csv)
└── c/         ← 12 arquivos .c (cópias dos testes C originais)
```

`Makefile` atualizado com quatro variáveis por domínio (`LUA_TESTS_SERIES`,
`LUA_TESTS_DATASET`, `LUA_TESTS_IO`, `LUA_TESTS_PROPS`); `LUA_TESTS` é a
sua concatenação. Path `tests/fixtures/pedidos_digitados.csv` atualizado nos
testes de I/O.

### Resultado

- `make test` (12 C): PASS
- `make test-lua` (18 suítes): PASS
- `parity.sh`: 12/12

---

## 2026-06-16 — Fase 3 Grupos A+B (Ring 0) + G.1 UTF-8 JSON

Início da Fase 3: migração de primitivas Lua puro para Ring 0 (C), guiada
pelo Bloco G. Duas frentes paralelas nesta sessão: G.1 (bloqueante de release)
e Grupos A+B do inventário de primitivas.

### G.1 — Decodificação UTF-8 no reader JSON

Eliminada a degradação silenciosa `\uXXXX → '?'` que existia em
`smaug_json.c`. Implementação completa em `read_json_string`:

- `read_hex4`: lê 4 dígitos hex → codepoint; retorna -1 se hex inválido.
- `encode_utf8`: codepoint → 1–4 bytes UTF-8 (cobre U+0000–U+10FFFF).
- BMP (U+0000–U+FFFF): decodificado diretamente.
- Surrogate pairs (`\uD800–\uDBFF` + `\uDC00–\uDFFF`): montados em
  codepoint suplementar (U+10000–U+10FFFF) e codificados em 4 bytes UTF-8.
- Surrogate isolado ou hex inválido → `TOK_ERROR` → `make_error` com
  mensagem clara. Nunca silencioso.

`.str` permanece byte-oriented — contrato inalterado. `str:len()` retorna
bytes, não codepoints. `test_io_c`: 174 → 190 checks (+16, 8 casos unicode).

**Motivação:** `json.dumps` Python com `ensure_ascii=True` (default) serializa
qualquer não-ASCII como `\uXXXX`. Dados brasileiros reais (nomes, cidades com
acento) produzem escapes rotineiramente. O `'?'` silencioso era bug de
integridade indetectável em produção.

### Grupo A — 10 primitivas O(N) para Ring 0

Migradas de Lua puro para C em `smaug_ops_f64.c` e `smaug_ops_i64.c`,
declaradas em `smaug_numeric.h`, registradas no `DTYPES` de `series.lua`
e no `ffi_loader.lua`:

`cumsum`, `cumprod`, `cummin`, `cummax`, `diff`, `shift`, `ffill`, `bfill`,
`argmin`, `argmax` — para `smaug_series_f64_t` e `smaug_series_i64_t`.

**Contratos relevantes:**
- `cummin`/`cummax`: nulos não propagam para frente (posição nula fica nula,
  mas as seguintes continuam recebendo o acumulado). Contrato mais útil que o
  `cumsum`/`cumprod` onde null contamina o restante.
- `diff` datetime: permanece Lua (usa `smaug_dt_diff_ms`).
- `shift` negativo (periods < 0): permanece Lua (C usa `size_t`).
- `argmin`/`argmax`: retornam `SIZE_MAX` se série vazia ou toda-null; Lua
  converte `SIZE_MAX → nil` e ajusta 0-based → 1-based.
- `cummin`/`cummax`/`ffill`/`bfill` datetime: fallback Lua via nil-check em
  `self._d.xxx`.

Regra de migração aplicada: todas as funções C registradas nos descritores
`DTYPES` (`float64` e `int64`) e acessadas via `self._d.fn(self._c)` — nunca
`C.smaug_f64_fn` diretamente no corpo do método.

### Grupo B — sorted_nonnull e rank para Ring 0

Migradas de Lua puro para C:

- `smaug_f64_sorted_nonnull` / `smaug_i64_sorted_nonnull`: coleta não-nulos
  em `double*` / `int64_t*` ordenado crescente. Série toda-null retorna
  `NULL` com `*out_n = 0` (não é erro). Caller libera com `smaug_free`.
- `smaug_f64_rank` / `smaug_i64_rank`: rank 1-based com 4 methods
  (0=average, 1=min, 2=max, 3=first). Nulos → `NAN` no resultado.
  Caller libera com `smaug_free`.

Comparadores (`cmp_double`, `cmp_rank_pair`, `cmp_i64`, `cmp_i64_rank_pair`)
definidos como `static` no escopo do arquivo — C11 padrão, sem extensões GCC.

**Consumidores Lua reescritos:** `median`, `quantile`, `nlargest`, `nsmallest`,
`skew`, `kurtosis`, `mad`, `sem`, `rank`, `pct_rank` — todos delegam para C
via `c_sorted_nonnull` (helper Lua que chama a primitiva C e devolve
`ffi.new double[]` uniforme). `datetime` e `mad` (segundo passe sobre desvios)
permanecem com fallback Lua.

Grupo B não usa `DTYPES`: as funções retornam ponteiros brutos (`double*`,
`int64_t*`), não `smaug_series_*_t` — são primitivas de buffer chamadas
diretamente pelos métodos, não via descritor de dtype.

### Testes

`test_ops_window.c` — novo, cobre Grupos A e B: 150 checks.
ASan+UBSan limpos. `test_allocfail` estável em 1158 verificações.

### Próximo

Fase 3 Grupo C: `multi_argsort` composto (DataSet) e `SeriesRolling:_agg`,
após medição de performance no Windows.

---



Último sub-bloco do enriquecimento dos núcleos. Com ele, **o Bloco F inteiro
(F.1–F.6) está fechado**.

### Adicionado

- **Series:** `duplicated([keep])` (keep ∈ {first,last,none}; null conta como
  valor — dois nulos são duplicatas entre si, semântica pandas);
  `drop_duplicates([keep])`; `combine_first(other)` (preenche nulls de self com
  other); `searchsorted(value, [side])` (busca binária, exige série ordenada
  crescente verificada via `is_monotonic_increasing`; side ∈ {left,right});
  `rep_each(n)` (repete cada elemento n vezes; n escalar ≥0 ou `Series<int64>`).
- **DataSet:** `duplicated([subset], [keep])` (subset = nome/lista/nil) e
  `drop_duplicates([subset], [keep])` (multi-coluna).

**Decisões de contrato:**
- O nome do método de repetição é `rep_each`, não `repeat`: `repeat` é palavra
  reservada em Lua e impediria tanto a definição (`function methods.repeat`)
  quanto a chamada (`s:repeat(n)`) — ambas falham no parse. `rep_each` deixa a
  intenção explícita (repete cada elemento) e segue o espírito do `:rep` já
  existente no `.str`.
- `duplicated` reaproveita o mesmo esquema de chave de `unique`/`nunique`
  (`type:tostring`, mais sentinela própria para null), garantindo semântica
  consistente de igualdade em todo o frontend.
- `combine_first` exige dtype e tamanho iguais — não faz coerção implícita.
- `searchsorted` exige ordenação crescente e rejeita séries com nulos (não há
  ordem definida com null), com erro claro em vez de resultado silenciosamente
  errado.

`test_duplicates.lua` (74 checks).

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `Series.methods` 90→95, `DataSet.methods`
46→48. Roadmap marca F.6 e o **Bloco F** inteiro como `[Done]`.

---

## 2026-06-15 — Bloco F.5 (acesso e ergonomia)

### Adicionado

- **Series:** `at`/`iat` — acesso escalar posicional. Implementado via proxy no
  `__index` que suporta tanto indexação (`s.at[i]`) quanto chamada (`s.at(i)`),
  cobrindo a sintaxe pandas-like e a forma idiomática Lua. Em Series 1-D, `at` e
  `iat` são equivalentes (índice = posição). Ambos delegam a `get`, herdando o
  guard de bounds.
- **DataSet:** `at(i, col)` (célula por nome) e `iat(i, ci)` (célula por índice
  posicional de coluna); `insert(loc, name, series)` (insere em posição 1-based,
  desloca as seguintes); `to_dict([orient])` (`"columns"` default ou `"records"`);
  `from_dict(t, [orient])` (construtor com inferência de dtype por coluna);
  `to_markdown()` (GitHub-flavored, sem o limite de 10 linhas do `__tostring`);
  `to_string([opts])` (texto plano com `max_rows` opcional).

**Decisões de contrato:**
- `at`/`iat` no DataSet são métodos chamáveis (`df:at(i, col)`), não indexers de
  duplo subscrito — Lua não tem `tbl[i, col]`. A forma de chamada é a tradução
  fiel e sem ambiguidade.
- `from_dict` orient `"columns"`: ordem das colunas é indefinida em Lua (chaves
  de tabela), então aceita `t._order` (lista de nomes) para ordem determinística;
  sem ele, ordena alfabeticamente. Orient `"records"`: colunas pela união das
  chaves (1ª aparição); chave ausente em um registro → NA naquela linha.
- `from_dict` infere dtype por coluna: string domina; senão bool puro; senão
  float se houver não-inteiro; senão int64; coluna toda-nula → string.

`test_access.lua` (54 checks), incluindo roundtrip `to_dict→from_dict`, bordas de
`insert` e erros de acesso.

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `DataSet.methods` 40→46 (`from_dict` é
função de classe, documentada à parte como `from_columns`). Roadmap marca F.5
`[Done]`.

---

## 2026-06-15 — Portabilidade de I/O + Blocos F.3 e F.4 + sync de builds

### Corrigido — testes de I/O com path hardcoded (Windows)

`build_win.ps1` falhou em `test_io_c`, `test_io` e `test_io_real`: os testes
escreviam em `/tmp/...`, que não existe no Windows/UCRT64. Não era regressão da
biblioteca — `to_csv`/`smaug_write_csv` reportaram fielmente a falha de escrita.
Introduzido helper `tmp_path` (um em C, um em Lua) que resolve o diretório
temporário via `TMPDIR`→`TMP`→`TEMP`→`/tmp`, montando o caminho com separador
`/` (aceito pela CRT do Windows e pelo POSIX). Detalhe que exigiu cuidado:
`os.getenv` devolve `""` (truthy em Lua), não `nil`, para variável vazia — o
helper trata string vazia como ausente, espelhando o `!dir || !*dir` do C.
Validado em três cenários: fallback `/tmp`, `TEMP` setado, e variável vazia.

### Adicionado — Bloco F.3: accessor `.dt` estendido

Toda a lógica de calendário derivada vive no Ring 1 (Lua), reaproveitando as
primitivas C (`year`/`month`/`day`/.../`from_parts`/`truncate`/`add_ms`). Nenhuma
mudança no Ring 0 — funções de calendário derivadas são responsabilidade do
frontend.

- **Predicados** (→ `Series<bool>`): `is_month_start`/`is_month_end`,
  `is_quarter_start`/`is_quarter_end`, `is_year_start`/`is_year_end`,
  `is_leap_year` (regra gregoriana completa, incluindo a exceção secular ÷400).
- **Atributos:** `days_in_month` (→ int64), `month_name`/`day_name` (inglês fixo).
- **Período:** `round(unit)`/`ceil(unit)` complementam o `truncate` (= floor) já
  existente. `ceil` retorna o próprio valor quando já alinhado; `round` usa
  half-up no empate (consistente com pandas). `next_period` usa `from_parts`
  para unidades de calendário (M/Q/Y, comprimento variável) e `add_ms` para as
  de comprimento fixo.
- **`normalize()`:** zera a hora (= `truncate("D")`), nome herdado do pandas.
- **`strftime(fmt)`:** tokens `%Y %y %m %d %H %M %S %I %p %j %B %b %A %a %%`;
  token desconhecido é mantido literal (com o `%`).

`test_dt_extended.lua` (65 checks), com casos seculares (1900 não-bissexto, 2000
bissexto), empates de round e meia-noite/meio-dia para `%I`/`%p`.

### Adicionado — Bloco F.4: accessor `.str` Tier C

ASCII puro, sem regex, sem Unicode — consistente com Tier A/B. Reaproveita os
helpers `str_map` (→ Series<string>) e `bool_map` (→ Series<bool>) existentes.

- **count(sub):** ocorrências literais não-sobrepostas → int64. `sub` vazio é
  erro (contagem indefinida / risco de loop).
- **Predicados** (→ Series<bool>): `isalnum`/`isalpha`/`isdigit`/`isspace`/
  `islower`/`isupper`. Semântica Python: string vazia → false; `islower`/
  `isupper` exigem ao menos uma letra e nenhuma da caixa oposta.
- **removeprefix/removesuffix:** remoção literal de afixo, no máximo uma vez,
  idempotente quando não casa.
- **capitalize/title/swapcase:** caixas ASCII. `title` trata qualquer não-letra
  como separador de palavra.
- **join(sep):** atalho de `:cat` (mesma saída: string Lua única). Mantido pelo
  nome familiar de pandas/Python.

`test_str_tier_c.lua` (61 checks), incluindo vazias, nulos, não-ASCII em `title`
(não quebra), e contagem não-sobreposta.

### Sincronização das três fontes de build

`build_win.ps1` estava atrás em duas dimensões: faltava `test_datetime_c`
(C) e seis suítes Lua (`test_datetime`, `test_categorical`, `test_completeness`,
`test_dt_extended`, `test_stats`, `test_predicates`). Alinhado ao Makefile
canônico — as três fontes (`Makefile`, `build.sh`, `build_win.ps1`) agora
rodam o conjunto idêntico, verificado por diff: 9 binários C plain + allocfail +
stress, e 26 suítes Lua.

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `SeriesDT:*` 19→33, `StrProxy:*` 15→28.
Roadmap marca F.3 e F.4 `[Done]`.

---

## 2026-06-15 — Completude de paridade + Blocos F.1 e F.2

Sessão de fechamento de lacunas antes de avançar o enriquecimento dos núcleos.

### Corrigido — checkup de build e oráculos de teste

Auditoria do `Makefile` e do `build.sh` expôs que `make test`/`make valgrind`
não exercitavam `test_io_c` nem `test_datetime_c` (375 checks C fora do CI), e
que `LUA_TESTS` cobria 8 de 21 suítes (362k+ checks ignorados pelo `make`). As
duas listas foram completadas e sincronizadas entre `Makefile` e `build.sh`.
Removido um warning `-Wunused-variable` em `test_io_c.c:315` (`s` capturada e
nunca usada). Build agora zero-warning também nos binários de teste.

### Adicionado — completude de métodos em datetime e categorical

Auditoria do `PARITY_REPORT.md` (Eixo 1) apontou 17 ausências sem registro.
Decisão: nesta fase de completude, **implementar**, não registrar exceção.

- **datetime (7):** `argmin`/`argmax`/`cummin`/`cummax`/`median`/`quantile`
  passam a aceitar datetime — operam sobre epoch_ms (já numérico), guard
  estendido. `diff` em datetime retorna `Series<int64>` (duração em ms, não
  timestamp — diferença de dois instantes é uma duração).
- **categorical (10):** `isna`/`notna` (aliases), `min`/`max` (lexicográfico
  sobre labels), `ffill`/`bfill` (opera ao nível de codes), `shift`, `map`
  (retorna Series do dtype inferido), `where`/`mask` (seleção condicional,
  retornam novo CategoricalSeries).

`test_completeness.lua` (93 checks) pina cada comportamento, incluindo nulos e
erros de bounds.

### Adicionado — Bloco F.1: pacote estatístico

- **Series:** `corr(other)` (Pearson ∈ [-1,1]), `cov(other)` (covariância
  amostral ÷ n-1), `autocorr([lag])` = `:corr(:shift(lag))`, `dot(other)`
  (produto interno), `pct_change([periods])`.
- **DataSet:** `corr()` / `cov()` retornam matriz N×N como DataSet (coluna
  identificadora `__index__` + uma coluna float64 por variável numérica;
  colunas não-numéricas ignoradas).

**Decisões de contrato:**
- `corr`/`cov` **pulam** pares onde qualquer operando é null (semântica pandas);
  menos de 2 pares válidos ou variância zero → NaN.
- `dot` **propaga** null (qualquer par com null → resultado null) — diferente de
  corr/cov, porque produto interno não tem semântica de "ignorar" sem mudar o
  significado do resultado.
- `pct_change` com divisor zero → null (não Inf), por previsibilidade.

`test_stats.lua` (60 checks) com valores de referência calculados à mão.

### Adicionado — Bloco F.2: pacote de predicados

- **Series:** `between(lo, hi, [inclusive])` (inclusive ∈ {both,left,right,
  neither}), `isin(values)`, `is_unique()`, `is_monotonic_increasing/
  decreasing([strict])`, `equals(other)` (igualdade estrutural com NaN==NaN),
  `compare(other)` (diferenças → DataSet `{i,self,other}`), `idxmin`/`idxmax`
  (aliases de argmin/argmax), `first_valid_index`/`last_valid_index`.
- **DataSet:** `equals(other)` (colunas+ordem+dtypes+valores), `compare(other)`
  (diferenças célula a célula → DataSet `{linha,coluna,self,other}`).

**Decisões de contrato:**
- `between`/`isin` propagam null (resultado null naquela posição).
- `is_monotonic_*`: qualquer null quebra a monotonicidade (sem ordem definida
  com o vizinho). Série vazia/de 1 elemento é monotônica (vacuamente).
- `equals`/`compare` tratam NaN como estruturalmente igual a NaN (diferente de
  IEEE 754) — a pergunta é "são a mesma série", não "são numericamente iguais".
- `compare` (Series) retorna só as posições que diferem; DataSet vazio se
  idênticas. `compare` (DataSet) normaliza `self`/`other` para string porque as
  colunas têm dtypes heterogêneos.

`test_predicates.lua` (78 checks).

### Docs

`API_INDEX.md` atualizado — Eixo 12 (sincronização docs↔código) de 88/97/60/77%
para **100% nas 7 categorias** (206 métodos documentados). Reduções e
comparações antes agrupadas em uma linha (`:sum/mean/...`) foram separadas em
entradas individuais para o checker detectar por nome exato. Roadmap marca F.1
como `[Done]`.

---

## 2026-06-14 — Decisão: enriquecimento dos núcleos entra na v1.0

Após auditoria comparativa contra a API pública do pandas (Series + DataFrame),
decisão arquitetural: a v1.0 não fecha com o mínimo viável. Fecha com cobertura
operacional ampla, mantendo zero dependências externas.

**6 pacotes adicionados ao Pré-1.0 (Bloco F):**
- F.1 — Estatístico (`corr`/`cov`/`autocorr`/`dot`/`pct_change`)
- F.2 — Predicados (`between`/`isin`/`is_unique`/`is_monotonic_*`/`equals`/`compare`/`idxmin`/`idxmax`/`first/last_valid_index`)
- F.3 — `.dt` estendido (`is_*_start/end`/`is_leap_year`/`days_in_month`/`round`/`ceil`/`strftime`/`normalize`/`month_name`/`day_name`)
- F.4 — `.str` Tier C parcial (`count`/`isalnum`/`isalpha`/etc/`removeprefix`/`removesuffix`/`capitalize`/`title`/`swapcase`/`join`) — sem regex, sem Unicode
- F.5 — Acesso e ergonomia (`at`/`iat`/`insert`/`to_dict`/`from_dict`/`to_markdown`/`to_string`)
- F.6 — Duplicatas e binárias (`duplicated`/`drop_duplicates`/`combine_first`/`searchsorted`/`repeat`)

**Decisões de não-fazer (permanentes, registradas em Roadmap.md):**
- Index nomeado e toda família dependente (`loc`/`MultiIndex`/`reindex`/`align`/
  `set_index`/`reset_index`/`xs`/`swaplevel`/`droplevel`/`at_time`/`between_time`/
  `asof`/`asfreq`/`resample`/`to_period`/`to_timestamp`/`tz_*`).
- Plotting (`.plot`/`.hist`/`.boxplot`).
- I/O exótico (`pickle`/`hdf`/`xarray`/`stata`/`clipboard`/`latex`/`orc`/`feather`/
  `html`/`style`/`__dataframe__`).
- Tipos extras (`sparse`/`list`/`struct`/`period`/`timedelta`/`interval`/`decimal`).
- Operadores reversos (`radd`/`rsub`/etc.) — não-issue em Lua.
- `pipe`/`combine`/`update`/`squeeze`/`to_frame`.

**Trade-off:** v1.0 atrasa em ~6 sessões. Aceito conscientemente porque
v1.0 com cobertura ampla muda a régua do projeto — quando alguém abrir o README,
vê paridade significativa com pandas no que importa, sem o ruído.

Roadmap.md tem a lista detalhada de cada pacote, justificativa de cada
decisão de não-fazer, e checklist atualizado.

---

## 2026-06-14 — Tier 2 dtypes + bugfix Valgrind dos parsers I/O

### Adicionado — datetime no frontend Lua

Backend C de `smaug_datetime.c` já estava pronto (epoch ms UTC, calendário
Gregoriano proléptico, 201 checks em `test_datetime_c`). Esta sessão fechou
a integração com o frontend:

- Descriptor `datetime` no `DTYPES` de `series.lua` (factory, set/get com
  string ISO 8601 ou epoch_ms, append, comparações, sort/filter/take).
- Accessor `.dt` com 19 métodos: 11 componentes calendário (`year`/`month`/
  `day`/`hour`/`minute`/`second`/`ms`/`weekday`/`yearday`/`quarter`/`week`),
  `format`, `truncate(unit)` para `s/m/h/D/W/M/Q/Y`, `diff([periods])` em
  milissegundos, `add_ms`/`add_days`/`add_hours`/`add_minutes`/`add_seconds`.
- Helpers públicos: `Series.dt_parse`, `Series.dt_format`, `Series.dt_from_parts`,
  `Series.datetime(size, name)`.
- `astype` estendido com 6 branches novos: `datetime ↔ string` (via ISO 8601),
  `datetime ↔ int64`, `datetime ↔ float64` (epoch_ms).
- `describe` estendido com branch `datetime` — retorna `{dtype, count, nulls, min, max}`
  onde min/max são strings ISO 8601 formatadas.
- `test_datetime.lua` (188 checks): factories, `.dt`, comparações, sort, filter,
  astype, integração DataSet (filter/sort_by/assign/select/head/dropna/describe).

### Adicionado — categorical (Lua puro)

`CategoricalSeries` implementado inteiramente em Lua usando dictionary encoding.
Decisão consciente de não criar C backend — o tipo é essencialmente um índice
+ tabela de strings, não justifica fragmentar o contrato C.

- Armazenamento: `_codes` (int 1-based; nil = null), `_levels` (lista ordenada
  por primeira aparição), `_level_map` (hash inverso).
- Factories: `Series.from_table(arr, "categorical")`, `Series.Categorical.from_codes(...)`.
- 31 métodos de instância (espelham `Series` onde cabe): acesso, append,
  clone/head/tail/take/filter/dropna/fillna, sort/argsort (lexicográfico),
  comparações (`eq`/`ne`/`lt`/`le`/`gt`/`ge`), `unique`/`nunique`/`value_counts`,
  `describe`, `astype` (para `string`, `int64`, `float64`), `to_table`.
- Accessor `.cat` com 6 métodos: `codes()` → `Series<int64>`, `levels()`,
  `rename_categories`, `set_categories`, `add_categories`, `remove_categories`.
- Integração total com DataSet: `add_column`, `update_column`, `assign`,
  `__newindex`, `__call` todos aceitam `CategoricalSeries`. Princípio
  "toda coluna aceita pelo DataSet funciona em toda a API do DataSet".
- `test_categorical.lua` (199 checks).

### Corrigido — leaks nos parsers I/O capturados pelo Valgrind

Após validar `datetime` + `categorical` no Fedora com `make valgrind`, o
Valgrind capturou ~762 bytes vazando em 79 blocos no `test_allocfail`. Stack
traces apontaram para `smaug_csv.c:227` (strdup de `col_names`) e
`smaug_json.c:267/273` (malloc/calloc após strdups).

**Bugs identificados:**
- Em ambos os parsers, quando `calloc(dtypes)` ou alocações subsequentes
  falhavam **depois** do loop de strdup de `col_names[c]`, o cleanup fazia
  `free(col_names)` (o array) mas não liberava as strings individuais.
- No CSV, o label `done:` (alcançado quando `smaug_X_create` falha no loop
  final) liberava `col_names` mas não os strdups dos índices ainda não
  transferidos para `t->columns[c].name`.
- No JSON, `oom_recs:` libera `recs` mas nem `col_names` nem `dtypes` eram
  visíveis no escopo do label.

**Estratégia comum:**
- Inicializar `col_names[c] = NULL` antes do loop de strdup; libertar
  parcialmente em caso de falha.
- Marcar transferência de ownership com `col_names[c] = NULL` ao atribuir
  ao `tbl->columns[c].name`. `free(NULL)` é seguro, o cleanup itera pelo
  array inteiro.
- No JSON, mover `col_names`/`dtypes` para o escopo da função (com `n_cols_io`)
  para serem visíveis no label de cleanup. No CSV, estender `done:` para
  liberar strdups não-transferidos.

Resultado: Valgrind 100% clean em todos os 9 binários no Fedora. `test_allocfail`
com 15330 allocs / 15330 frees, `test_stress` com 90751/90751.

### Corrigido — warning `-Wtype-limits` no test_allocfail

`t->nrows >= 0` onde `nrows` é `size_t` (unsigned) — sempre verdadeiro.
Substituído por `1` constante; o check útil (`!t || t->error`) permanece.

### Decisão — NDJSON adiado para pós-1.0

Tentativa de implementar NDJSON expôs limitação fundamental: o parser JSON C
infere dtypes por linha. Uma linha com `"a":null` infere `string`, conflitando
com outra linha com `"a":1` que infere `int64`. Sem schema global declarativo,
NDJSON é inerentemente frágil para dados com null. Decisão: adiar para o ciclo
do schema/ORM (v2.0). Registrado em `Roadmap.md`.

### Cobertura

Linha 95.99% (2248/2342), branch-alvo 88.12% (2270/2576, 90 exclusões).
Queda em relação a sessões anteriores (96.99% / 88.82%) é resultado dos
cleanup paths novos — código adicionado mas ainda não exercitado pelo
`test_allocfail`. Vai ser fechado no hardening global.

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
# Changelog — Smaug

Registro de o que mudou e por que, em ordem cronológica reversa.
Uma entrada por sessão de trabalho. Foco no que não é óbvio pelo diff:
decisões, achados, motivações.

---

## 2026-06-16 — Fase 3 Grupos A+B (Ring 0) + G.1 UTF-8 JSON

Início da Fase 3: migração de primitivas Lua puro para Ring 0 (C), guiada
pelo Bloco G. Duas frentes paralelas nesta sessão: G.1 (bloqueante de release)
e Grupos A+B do inventário de primitivas.

### G.1 — Decodificação UTF-8 no reader JSON

Eliminada a degradação silenciosa `\uXXXX → '?'` que existia em
`smaug_json.c`. Implementação completa em `read_json_string`:

- `read_hex4`: lê 4 dígitos hex → codepoint; retorna -1 se hex inválido.
- `encode_utf8`: codepoint → 1–4 bytes UTF-8 (cobre U+0000–U+10FFFF).
- BMP (U+0000–U+FFFF): decodificado diretamente.
- Surrogate pairs (`\uD800–\uDBFF` + `\uDC00–\uDFFF`): montados em
  codepoint suplementar (U+10000–U+10FFFF) e codificados em 4 bytes UTF-8.
- Surrogate isolado ou hex inválido → `TOK_ERROR` → `make_error` com
  mensagem clara. Nunca silencioso.

`.str` permanece byte-oriented — contrato inalterado. `str:len()` retorna
bytes, não codepoints. `test_io_c`: 174 → 190 checks (+16, 8 casos unicode).

**Motivação:** `json.dumps` Python com `ensure_ascii=True` (default) serializa
qualquer não-ASCII como `\uXXXX`. Dados brasileiros reais (nomes, cidades com
acento) produzem escapes rotineiramente. O `'?'` silencioso era bug de
integridade indetectável em produção.

### Grupo A — 10 primitivas O(N) para Ring 0

Migradas de Lua puro para C em `smaug_ops_f64.c` e `smaug_ops_i64.c`,
declaradas em `smaug_numeric.h`, registradas no `DTYPES` de `series.lua`
e no `ffi_loader.lua`:

`cumsum`, `cumprod`, `cummin`, `cummax`, `diff`, `shift`, `ffill`, `bfill`,
`argmin`, `argmax` — para `smaug_series_f64_t` e `smaug_series_i64_t`.

**Contratos relevantes:**
- `cummin`/`cummax`: nulos não propagam para frente (posição nula fica nula,
  mas as seguintes continuam recebendo o acumulado). Contrato mais útil que o
  `cumsum`/`cumprod` onde null contamina o restante.
- `diff` datetime: permanece Lua (usa `smaug_dt_diff_ms`).
- `shift` negativo (periods < 0): permanece Lua (C usa `size_t`).
- `argmin`/`argmax`: retornam `SIZE_MAX` se série vazia ou toda-null; Lua
  converte `SIZE_MAX → nil` e ajusta 0-based → 1-based.
- `cummin`/`cummax`/`ffill`/`bfill` datetime: fallback Lua via nil-check em
  `self._d.xxx`.

Regra de migração aplicada: todas as funções C registradas nos descritores
`DTYPES` (`float64` e `int64`) e acessadas via `self._d.fn(self._c)` — nunca
`C.smaug_f64_fn` diretamente no corpo do método.

### Grupo B — sorted_nonnull e rank para Ring 0

Migradas de Lua puro para C:

- `smaug_f64_sorted_nonnull` / `smaug_i64_sorted_nonnull`: coleta não-nulos
  em `double*` / `int64_t*` ordenado crescente. Série toda-null retorna
  `NULL` com `*out_n = 0` (não é erro). Caller libera com `smaug_free`.
- `smaug_f64_rank` / `smaug_i64_rank`: rank 1-based com 4 methods
  (0=average, 1=min, 2=max, 3=first). Nulos → `NAN` no resultado.
  Caller libera com `smaug_free`.

Comparadores (`cmp_double`, `cmp_rank_pair`, `cmp_i64`, `cmp_i64_rank_pair`)
definidos como `static` no escopo do arquivo — C11 padrão, sem extensões GCC.

**Consumidores Lua reescritos:** `median`, `quantile`, `nlargest`, `nsmallest`,
`skew`, `kurtosis`, `mad`, `sem`, `rank`, `pct_rank` — todos delegam para C
via `c_sorted_nonnull` (helper Lua que chama a primitiva C e devolve
`ffi.new double[]` uniforme). `datetime` e `mad` (segundo passe sobre desvios)
permanecem com fallback Lua.

Grupo B não usa `DTYPES`: as funções retornam ponteiros brutos (`double*`,
`int64_t*`), não `smaug_series_*_t` — são primitivas de buffer chamadas
diretamente pelos métodos, não via descritor de dtype.

### Testes

`test_ops_window.c` — novo, cobre Grupos A e B: 150 checks.
ASan+UBSan limpos. `test_allocfail` estável em 1158 verificações.

### Próximo

Fase 3 Grupo C: `multi_argsort` composto (DataSet) e `SeriesRolling:_agg`,
após medição de performance no Windows.

---



Último sub-bloco do enriquecimento dos núcleos. Com ele, **o Bloco F inteiro
(F.1–F.6) está fechado**.

### Adicionado

- **Series:** `duplicated([keep])` (keep ∈ {first,last,none}; null conta como
  valor — dois nulos são duplicatas entre si, semântica pandas);
  `drop_duplicates([keep])`; `combine_first(other)` (preenche nulls de self com
  other); `searchsorted(value, [side])` (busca binária, exige série ordenada
  crescente verificada via `is_monotonic_increasing`; side ∈ {left,right});
  `rep_each(n)` (repete cada elemento n vezes; n escalar ≥0 ou `Series<int64>`).
- **DataSet:** `duplicated([subset], [keep])` (subset = nome/lista/nil) e
  `drop_duplicates([subset], [keep])` (multi-coluna).

**Decisões de contrato:**
- O nome do método de repetição é `rep_each`, não `repeat`: `repeat` é palavra
  reservada em Lua e impediria tanto a definição (`function methods.repeat`)
  quanto a chamada (`s:repeat(n)`) — ambas falham no parse. `rep_each` deixa a
  intenção explícita (repete cada elemento) e segue o espírito do `:rep` já
  existente no `.str`.
- `duplicated` reaproveita o mesmo esquema de chave de `unique`/`nunique`
  (`type:tostring`, mais sentinela própria para null), garantindo semântica
  consistente de igualdade em todo o frontend.
- `combine_first` exige dtype e tamanho iguais — não faz coerção implícita.
- `searchsorted` exige ordenação crescente e rejeita séries com nulos (não há
  ordem definida com null), com erro claro em vez de resultado silenciosamente
  errado.

`test_duplicates.lua` (74 checks).

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `Series.methods` 90→95, `DataSet.methods`
46→48. Roadmap marca F.6 e o **Bloco F** inteiro como `[Done]`.

---

## 2026-06-15 — Bloco F.5 (acesso e ergonomia)

### Adicionado

- **Series:** `at`/`iat` — acesso escalar posicional. Implementado via proxy no
  `__index` que suporta tanto indexação (`s.at[i]`) quanto chamada (`s.at(i)`),
  cobrindo a sintaxe pandas-like e a forma idiomática Lua. Em Series 1-D, `at` e
  `iat` são equivalentes (índice = posição). Ambos delegam a `get`, herdando o
  guard de bounds.
- **DataSet:** `at(i, col)` (célula por nome) e `iat(i, ci)` (célula por índice
  posicional de coluna); `insert(loc, name, series)` (insere em posição 1-based,
  desloca as seguintes); `to_dict([orient])` (`"columns"` default ou `"records"`);
  `from_dict(t, [orient])` (construtor com inferência de dtype por coluna);
  `to_markdown()` (GitHub-flavored, sem o limite de 10 linhas do `__tostring`);
  `to_string([opts])` (texto plano com `max_rows` opcional).

**Decisões de contrato:**
- `at`/`iat` no DataSet são métodos chamáveis (`df:at(i, col)`), não indexers de
  duplo subscrito — Lua não tem `tbl[i, col]`. A forma de chamada é a tradução
  fiel e sem ambiguidade.
- `from_dict` orient `"columns"`: ordem das colunas é indefinida em Lua (chaves
  de tabela), então aceita `t._order` (lista de nomes) para ordem determinística;
  sem ele, ordena alfabeticamente. Orient `"records"`: colunas pela união das
  chaves (1ª aparição); chave ausente em um registro → NA naquela linha.
- `from_dict` infere dtype por coluna: string domina; senão bool puro; senão
  float se houver não-inteiro; senão int64; coluna toda-nula → string.

`test_access.lua` (54 checks), incluindo roundtrip `to_dict→from_dict`, bordas de
`insert` e erros de acesso.

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `DataSet.methods` 40→46 (`from_dict` é
função de classe, documentada à parte como `from_columns`). Roadmap marca F.5
`[Done]`.

---

## 2026-06-15 — Portabilidade de I/O + Blocos F.3 e F.4 + sync de builds

### Corrigido — testes de I/O com path hardcoded (Windows)

`build_win.ps1` falhou em `test_io_c`, `test_io` e `test_io_real`: os testes
escreviam em `/tmp/...`, que não existe no Windows/UCRT64. Não era regressão da
biblioteca — `to_csv`/`smaug_write_csv` reportaram fielmente a falha de escrita.
Introduzido helper `tmp_path` (um em C, um em Lua) que resolve o diretório
temporário via `TMPDIR`→`TMP`→`TEMP`→`/tmp`, montando o caminho com separador
`/` (aceito pela CRT do Windows e pelo POSIX). Detalhe que exigiu cuidado:
`os.getenv` devolve `""` (truthy em Lua), não `nil`, para variável vazia — o
helper trata string vazia como ausente, espelhando o `!dir || !*dir` do C.
Validado em três cenários: fallback `/tmp`, `TEMP` setado, e variável vazia.

### Adicionado — Bloco F.3: accessor `.dt` estendido

Toda a lógica de calendário derivada vive no Ring 1 (Lua), reaproveitando as
primitivas C (`year`/`month`/`day`/.../`from_parts`/`truncate`/`add_ms`). Nenhuma
mudança no Ring 0 — funções de calendário derivadas são responsabilidade do
frontend.

- **Predicados** (→ `Series<bool>`): `is_month_start`/`is_month_end`,
  `is_quarter_start`/`is_quarter_end`, `is_year_start`/`is_year_end`,
  `is_leap_year` (regra gregoriana completa, incluindo a exceção secular ÷400).
- **Atributos:** `days_in_month` (→ int64), `month_name`/`day_name` (inglês fixo).
- **Período:** `round(unit)`/`ceil(unit)` complementam o `truncate` (= floor) já
  existente. `ceil` retorna o próprio valor quando já alinhado; `round` usa
  half-up no empate (consistente com pandas). `next_period` usa `from_parts`
  para unidades de calendário (M/Q/Y, comprimento variável) e `add_ms` para as
  de comprimento fixo.
- **`normalize()`:** zera a hora (= `truncate("D")`), nome herdado do pandas.
- **`strftime(fmt)`:** tokens `%Y %y %m %d %H %M %S %I %p %j %B %b %A %a %%`;
  token desconhecido é mantido literal (com o `%`).

`test_dt_extended.lua` (65 checks), com casos seculares (1900 não-bissexto, 2000
bissexto), empates de round e meia-noite/meio-dia para `%I`/`%p`.

### Adicionado — Bloco F.4: accessor `.str` Tier C

ASCII puro, sem regex, sem Unicode — consistente com Tier A/B. Reaproveita os
helpers `str_map` (→ Series<string>) e `bool_map` (→ Series<bool>) existentes.

- **count(sub):** ocorrências literais não-sobrepostas → int64. `sub` vazio é
  erro (contagem indefinida / risco de loop).
- **Predicados** (→ Series<bool>): `isalnum`/`isalpha`/`isdigit`/`isspace`/
  `islower`/`isupper`. Semântica Python: string vazia → false; `islower`/
  `isupper` exigem ao menos uma letra e nenhuma da caixa oposta.
- **removeprefix/removesuffix:** remoção literal de afixo, no máximo uma vez,
  idempotente quando não casa.
- **capitalize/title/swapcase:** caixas ASCII. `title` trata qualquer não-letra
  como separador de palavra.
- **join(sep):** atalho de `:cat` (mesma saída: string Lua única). Mantido pelo
  nome familiar de pandas/Python.

`test_str_tier_c.lua` (61 checks), incluindo vazias, nulos, não-ASCII em `title`
(não quebra), e contagem não-sobreposta.

### Sincronização das três fontes de build

`build_win.ps1` estava atrás em duas dimensões: faltava `test_datetime_c`
(C) e seis suítes Lua (`test_datetime`, `test_categorical`, `test_completeness`,
`test_dt_extended`, `test_stats`, `test_predicates`). Alinhado ao Makefile
canônico — as três fontes (`Makefile`, `build.sh`, `build_win.ps1`) agora
rodam o conjunto idêntico, verificado por diff: 9 binários C plain + allocfail +
stress, e 26 suítes Lua.

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `SeriesDT:*` 19→33, `StrProxy:*` 15→28.
Roadmap marca F.3 e F.4 `[Done]`.

---

## 2026-06-15 — Completude de paridade + Blocos F.1 e F.2

Sessão de fechamento de lacunas antes de avançar o enriquecimento dos núcleos.

### Corrigido — checkup de build e oráculos de teste

Auditoria do `Makefile` e do `build.sh` expôs que `make test`/`make valgrind`
não exercitavam `test_io_c` nem `test_datetime_c` (375 checks C fora do CI), e
que `LUA_TESTS` cobria 8 de 21 suítes (362k+ checks ignorados pelo `make`). As
duas listas foram completadas e sincronizadas entre `Makefile` e `build.sh`.
Removido um warning `-Wunused-variable` em `test_io_c.c:315` (`s` capturada e
nunca usada). Build agora zero-warning também nos binários de teste.

### Adicionado — completude de métodos em datetime e categorical

Auditoria do `PARITY_REPORT.md` (Eixo 1) apontou 17 ausências sem registro.
Decisão: nesta fase de completude, **implementar**, não registrar exceção.

- **datetime (7):** `argmin`/`argmax`/`cummin`/`cummax`/`median`/`quantile`
  passam a aceitar datetime — operam sobre epoch_ms (já numérico), guard
  estendido. `diff` em datetime retorna `Series<int64>` (duração em ms, não
  timestamp — diferença de dois instantes é uma duração).
- **categorical (10):** `isna`/`notna` (aliases), `min`/`max` (lexicográfico
  sobre labels), `ffill`/`bfill` (opera ao nível de codes), `shift`, `map`
  (retorna Series do dtype inferido), `where`/`mask` (seleção condicional,
  retornam novo CategoricalSeries).

`test_completeness.lua` (93 checks) pina cada comportamento, incluindo nulos e
erros de bounds.

### Adicionado — Bloco F.1: pacote estatístico

- **Series:** `corr(other)` (Pearson ∈ [-1,1]), `cov(other)` (covariância
  amostral ÷ n-1), `autocorr([lag])` = `:corr(:shift(lag))`, `dot(other)`
  (produto interno), `pct_change([periods])`.
- **DataSet:** `corr()` / `cov()` retornam matriz N×N como DataSet (coluna
  identificadora `__index__` + uma coluna float64 por variável numérica;
  colunas não-numéricas ignoradas).

**Decisões de contrato:**
- `corr`/`cov` **pulam** pares onde qualquer operando é null (semântica pandas);
  menos de 2 pares válidos ou variância zero → NaN.
- `dot` **propaga** null (qualquer par com null → resultado null) — diferente de
  corr/cov, porque produto interno não tem semântica de "ignorar" sem mudar o
  significado do resultado.
- `pct_change` com divisor zero → null (não Inf), por previsibilidade.

`test_stats.lua` (60 checks) com valores de referência calculados à mão.

### Adicionado — Bloco F.2: pacote de predicados

- **Series:** `between(lo, hi, [inclusive])` (inclusive ∈ {both,left,right,
  neither}), `isin(values)`, `is_unique()`, `is_monotonic_increasing/
  decreasing([strict])`, `equals(other)` (igualdade estrutural com NaN==NaN),
  `compare(other)` (diferenças → DataSet `{i,self,other}`), `idxmin`/`idxmax`
  (aliases de argmin/argmax), `first_valid_index`/`last_valid_index`.
- **DataSet:** `equals(other)` (colunas+ordem+dtypes+valores), `compare(other)`
  (diferenças célula a célula → DataSet `{linha,coluna,self,other}`).

**Decisões de contrato:**
- `between`/`isin` propagam null (resultado null naquela posição).
- `is_monotonic_*`: qualquer null quebra a monotonicidade (sem ordem definida
  com o vizinho). Série vazia/de 1 elemento é monotônica (vacuamente).
- `equals`/`compare` tratam NaN como estruturalmente igual a NaN (diferente de
  IEEE 754) — a pergunta é "são a mesma série", não "são numericamente iguais".
- `compare` (Series) retorna só as posições que diferem; DataSet vazio se
  idênticas. `compare` (DataSet) normaliza `self`/`other` para string porque as
  colunas têm dtypes heterogêneos.

`test_predicates.lua` (78 checks).

### Docs

`API_INDEX.md` atualizado — Eixo 12 (sincronização docs↔código) de 88/97/60/77%
para **100% nas 7 categorias** (206 métodos documentados). Reduções e
comparações antes agrupadas em uma linha (`:sum/mean/...`) foram separadas em
entradas individuais para o checker detectar por nome exato. Roadmap marca F.1
como `[Done]`.

---

## 2026-06-14 — Decisão: enriquecimento dos núcleos entra na v1.0

Após auditoria comparativa contra a API pública do pandas (Series + DataFrame),
decisão arquitetural: a v1.0 não fecha com o mínimo viável. Fecha com cobertura
operacional ampla, mantendo zero dependências externas.

**6 pacotes adicionados ao Pré-1.0 (Bloco F):**
- F.1 — Estatístico (`corr`/`cov`/`autocorr`/`dot`/`pct_change`)
- F.2 — Predicados (`between`/`isin`/`is_unique`/`is_monotonic_*`/`equals`/`compare`/`idxmin`/`idxmax`/`first/last_valid_index`)
- F.3 — `.dt` estendido (`is_*_start/end`/`is_leap_year`/`days_in_month`/`round`/`ceil`/`strftime`/`normalize`/`month_name`/`day_name`)
- F.4 — `.str` Tier C parcial (`count`/`isalnum`/`isalpha`/etc/`removeprefix`/`removesuffix`/`capitalize`/`title`/`swapcase`/`join`) — sem regex, sem Unicode
- F.5 — Acesso e ergonomia (`at`/`iat`/`insert`/`to_dict`/`from_dict`/`to_markdown`/`to_string`)
- F.6 — Duplicatas e binárias (`duplicated`/`drop_duplicates`/`combine_first`/`searchsorted`/`repeat`)

**Decisões de não-fazer (permanentes, registradas em Roadmap.md):**
- Index nomeado e toda família dependente (`loc`/`MultiIndex`/`reindex`/`align`/
  `set_index`/`reset_index`/`xs`/`swaplevel`/`droplevel`/`at_time`/`between_time`/
  `asof`/`asfreq`/`resample`/`to_period`/`to_timestamp`/`tz_*`).
- Plotting (`.plot`/`.hist`/`.boxplot`).
- I/O exótico (`pickle`/`hdf`/`xarray`/`stata`/`clipboard`/`latex`/`orc`/`feather`/
  `html`/`style`/`__dataframe__`).
- Tipos extras (`sparse`/`list`/`struct`/`period`/`timedelta`/`interval`/`decimal`).
- Operadores reversos (`radd`/`rsub`/etc.) — não-issue em Lua.
- `pipe`/`combine`/`update`/`squeeze`/`to_frame`.

**Trade-off:** v1.0 atrasa em ~6 sessões. Aceito conscientemente porque
v1.0 com cobertura ampla muda a régua do projeto — quando alguém abrir o README,
vê paridade significativa com pandas no que importa, sem o ruído.

Roadmap.md tem a lista detalhada de cada pacote, justificativa de cada
decisão de não-fazer, e checklist atualizado.

---

## 2026-06-14 — Tier 2 dtypes + bugfix Valgrind dos parsers I/O

### Adicionado — datetime no frontend Lua

Backend C de `smaug_datetime.c` já estava pronto (epoch ms UTC, calendário
Gregoriano proléptico, 201 checks em `test_datetime_c`). Esta sessão fechou
a integração com o frontend:

- Descriptor `datetime` no `DTYPES` de `series.lua` (factory, set/get com
  string ISO 8601 ou epoch_ms, append, comparações, sort/filter/take).
- Accessor `.dt` com 19 métodos: 11 componentes calendário (`year`/`month`/
  `day`/`hour`/`minute`/`second`/`ms`/`weekday`/`yearday`/`quarter`/`week`),
  `format`, `truncate(unit)` para `s/m/h/D/W/M/Q/Y`, `diff([periods])` em
  milissegundos, `add_ms`/`add_days`/`add_hours`/`add_minutes`/`add_seconds`.
- Helpers públicos: `Series.dt_parse`, `Series.dt_format`, `Series.dt_from_parts`,
  `Series.datetime(size, name)`.
- `astype` estendido com 6 branches novos: `datetime ↔ string` (via ISO 8601),
  `datetime ↔ int64`, `datetime ↔ float64` (epoch_ms).
- `describe` estendido com branch `datetime` — retorna `{dtype, count, nulls, min, max}`
  onde min/max são strings ISO 8601 formatadas.
- `test_datetime.lua` (188 checks): factories, `.dt`, comparações, sort, filter,
  astype, integração DataSet (filter/sort_by/assign/select/head/dropna/describe).

### Adicionado — categorical (Lua puro)

`CategoricalSeries` implementado inteiramente em Lua usando dictionary encoding.
Decisão consciente de não criar C backend — o tipo é essencialmente um índice
+ tabela de strings, não justifica fragmentar o contrato C.

- Armazenamento: `_codes` (int 1-based; nil = null), `_levels` (lista ordenada
  por primeira aparição), `_level_map` (hash inverso).
- Factories: `Series.from_table(arr, "categorical")`, `Series.Categorical.from_codes(...)`.
- 31 métodos de instância (espelham `Series` onde cabe): acesso, append,
  clone/head/tail/take/filter/dropna/fillna, sort/argsort (lexicográfico),
  comparações (`eq`/`ne`/`lt`/`le`/`gt`/`ge`), `unique`/`nunique`/`value_counts`,
  `describe`, `astype` (para `string`, `int64`, `float64`), `to_table`.
- Accessor `.cat` com 6 métodos: `codes()` → `Series<int64>`, `levels()`,
  `rename_categories`, `set_categories`, `add_categories`, `remove_categories`.
- Integração total com DataSet: `add_column`, `update_column`, `assign`,
  `__newindex`, `__call` todos aceitam `CategoricalSeries`. Princípio
  "toda coluna aceita pelo DataSet funciona em toda a API do DataSet".
- `test_categorical.lua` (199 checks).

### Corrigido — leaks nos parsers I/O capturados pelo Valgrind

Após validar `datetime` + `categorical` no Fedora com `make valgrind`, o
Valgrind capturou ~762 bytes vazando em 79 blocos no `test_allocfail`. Stack
traces apontaram para `smaug_csv.c:227` (strdup de `col_names`) e
`smaug_json.c:267/273` (malloc/calloc após strdups).

**Bugs identificados:**
- Em ambos os parsers, quando `calloc(dtypes)` ou alocações subsequentes
  falhavam **depois** do loop de strdup de `col_names[c]`, o cleanup fazia
  `free(col_names)` (o array) mas não liberava as strings individuais.
- No CSV, o label `done:` (alcançado quando `smaug_X_create` falha no loop
  final) liberava `col_names` mas não os strdups dos índices ainda não
  transferidos para `t->columns[c].name`.
- No JSON, `oom_recs:` libera `recs` mas nem `col_names` nem `dtypes` eram
  visíveis no escopo do label.

**Estratégia comum:**
- Inicializar `col_names[c] = NULL` antes do loop de strdup; libertar
  parcialmente em caso de falha.
- Marcar transferência de ownership com `col_names[c] = NULL` ao atribuir
  ao `tbl->columns[c].name`. `free(NULL)` é seguro, o cleanup itera pelo
  array inteiro.
- No JSON, mover `col_names`/`dtypes` para o escopo da função (com `n_cols_io`)
  para serem visíveis no label de cleanup. No CSV, estender `done:` para
  liberar strdups não-transferidos.

Resultado: Valgrind 100% clean em todos os 9 binários no Fedora. `test_allocfail`
com 15330 allocs / 15330 frees, `test_stress` com 90751/90751.

### Corrigido — warning `-Wtype-limits` no test_allocfail

`t->nrows >= 0` onde `nrows` é `size_t` (unsigned) — sempre verdadeiro.
Substituído por `1` constante; o check útil (`!t || t->error`) permanece.

### Decisão — NDJSON adiado para pós-1.0

Tentativa de implementar NDJSON expôs limitação fundamental: o parser JSON C
infere dtypes por linha. Uma linha com `"a":null` infere `string`, conflitando
com outra linha com `"a":1` que infere `int64`. Sem schema global declarativo,
NDJSON é inerentemente frágil para dados com null. Decisão: adiar para o ciclo
do schema/ORM (v2.0). Registrado em `Roadmap.md`.

### Cobertura

Linha 95.99% (2248/2342), branch-alvo 88.12% (2270/2576, 90 exclusões).
Queda em relação a sessões anteriores (96.99% / 88.82%) é resultado dos
cleanup paths novos — código adicionado mas ainda não exercitado pelo
`test_allocfail`. Vai ser fechado no hardening global.

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