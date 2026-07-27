# Smaug — Roadmap

Este roadmap é uma **timeline sequencial**. Cada número é um tema; os decimais são
subtarefas. A ordem reflete dependência e risco — temas anteriores são fundação
dos seguintes. A **v1.0 ganha o direito de existir quando a timeline zerar**
(item 14 não achar inconsistência nova).

O histórico do que já foi entregue está no apêndice e no `CHANGELOG`. A descrição
arquitetural permanente (Filosofia, Anéis) está abaixo, antes da timeline.

---

## Filosofia

Smaug é fluido e robusto — uma engine feita para processar dados. Features
novas só entram sobre uma fundação sólida — um engine confiável vale mais
do que dez operações frágeis.

Robustez é funcionalidade. Testes não são suporte às funcionalidades, são
funcionalidades. Cobertura é ferramenta de confiança, não métrica de vaidade.
Valgrind é parte do desenvolvimento, não etapa final. A capacidade de sobreviver
a entradas inválidas é tão importante quanto qualquer operação matemática.

E o design importa. A API deve ser bonita de escrever e o fluxo de dados
deve ser natural de ler e conciso de compor.

Coerência se verifica, não se presume. Disparidade estrutural ("existe aqui mas
não ali") é trabalho de auditor automatizável — paridade cruzada com lista de
exceções conscientes. Erro semântico de implementação (ex.: precisão perdida numa
conversão) escapa ao auditor estrutural e exige leitura humana e revisão cruzada.
As duas camadas se complementam; nenhuma substitui a outra.

---

## Arquitetura em anéis

O projeto cresce de dentro pra fora. Um anel só expande quando o interior está
sólido — não o contrário. A partir do Anel 3, o crescimento segue **duas trilhas
paralelas** (Projeto: Persistência→Models; Analítica: Matrix→Tensor→ML). Ver
`ARCHITECTURE.md` para o modelo completo (10 anéis, duas trilhas), princípios,
diagrama, regra de decisão e régua de versões.

- **Anel 0 — Backend C.** Memória, tipos, operações primitivas. O engine não
  confia no caller — toda fronteira pública valida e comunica o resultado.
- **Anel 1 — Frontend Lua.** Series, BoolSeries, operações vetorizadas.
- **Anel 2 — Operações Relacionais.** DataSet, join, groupby, reshape. Depende
  só do Anel 1.
- **Anel 3 — Conectividade / I/O.** CSV, JSON, conectores externos.

---

## Já entregue (fora da timeline)

Resumo enxuto — detalhe histórico no apêndice e no `CHANGELOG`.

- **Anéis 0–3 completos e funcionais** — motor C, camada Lua, relacional, I/O.
- **Ring 0 hardened** — Valgrind-clean, meta de 95% branch-alvo, `test_allocfail`
  varrendo todos os pontos, stress N=1M.
- **Blocos A–I** — estatística, dtypes, transformações, robustez, enriquecimento
  dos núcleos, coerência de API (Bloco H: separador/decimal/dayfirst), fechamento
  de coerência (Bloco I).
- **Auditoria dos 4 anéis** — campanha de revisão que originou esta timeline. Os
  achados viraram os itens abaixo.

---

# Timeline — caminho até a v1.0

**Critério geral de fechamento** (vale para todo item, salvo exceção explícita):
build verde (`build.sh --all` no Fedora / `build_win.ps1` no Windows), teste
que guarda o comportamento novo, parity 12/12, e — para itens de Ring 0 —
Valgrind-clean + cobertura medida no Fedora. Nenhum item fecha sem um teste que o
proteja de regressão. Documentação afetada (`CHANGELOG`, contrato, COW.md)
atualizada no mesmo passo.

Legenda de ambiente:
- **[Windows]** fecha no Windows (Lua/teste — sem Valgrind/gcov).
- **[Fedora]** exige Fedora (Ring 0 — Valgrind/gcov autoritativos).
- **[Windows+Fedora]** toca os dois (C + Lua).

---

## 1. Fonte única de nulidade no Ring 0  [Fedora]  [Done]

> **Concluído (2026-06-28).** Verificado no Fedora: suíte verde com contadores
> idênticos ao baseline, **Valgrind-clean** nos 12 binários
> (`ERROR SUMMARY: 0 errors`, incluindo allocfail e stress), cobertura
> Linha 98.86% / Branch-alvo 95.63%, parity 12/12. Refatoração pura confirmada.

O invariante mais central do motor (válido = `0xFF`, nulo = `0x00`) é hoje testado
por quatro macros incompatíveis e teste cru espalhado. Funciona por convenção, não
por construção — a doença "sem fonte única". Fundação: tudo acima depende de
nulidade coerente.

- 1.1 macro única `SMAUG_VALID(mask,i)` / `SMAUG_NULL(mask,i)` em `smaug_types.h`
- 1.2 substituir as macros divergentes: `VALID(s,i)` (ops_f64/i64), `VALID_DT(s,i)`
  (datetime), `VALID(m,i)` (ops_bool, assinatura diferente)
- 1.3 substituir testes crus `== 0xFF` em `smaug_core.c` e `smaug_str.c`

*Exceção de fechamento:* nenhuma mudança de comportamento esperada — a prova é que
toda a suíte permanece verde e Valgrind-clean após a centralização (refatoração
pura).

## 2. Sentinela único na camada Lua  [Windows]  [Done — via Fedora]

> **Concluído (2026-06-28), com ressalva de verificação.** Item Lua puro (nenhum
> byte de C tocado). Critério `[Windows]` **suprido por validação Fedora**: 18
> suítes Lua verdes (mesmo LuaJIT que o Windows), parity eixo 09 (sentinels) OK,
> e o ponto sensível — carregamento do `_dt.lua` com `is_int_sentinel` — foi
> exercitado de fato (chegou a regredir e foi corrigido). O risco conhecido do
> MSYS2 (flush de `.gcda` via FFI) não se aplica: item 2 não tem cobertura-C.
> **Follow-up leve:** rodar `build_win.ps1` como confirmação; reabrir se
> acusar algo. Esta equivalência vale SÓ por ser Lua puro — não vira regra para
> itens `[Windows]` que expõem C novo (ex.: item 3).

O `_dt.lua` ignora o `I64_MIN` central do `init.lua` e reinventa o sentinela de
três formas, incluindo literal cru sem `LL` (vira double, bate por coerção —
frágil). Correção cirúrgica: fazer o infrator consumir o central.

- 2.1 `_dt.lua` consome `I64_MIN` central; remove literal `-9223372036854775808`
  (linhas 102, 140, 371) e o `DT_SENTINEL` local (linha 155)
- 2.2 `_dt.lua` usa `is_int_sentinel` em vez de comparar com literal
- 2.3 sentinela i64: nomear (não `INT64_MIN` cru) e documentar os dois contextos
  (`get` retorna 0, reduções retornam `INT64_MIN`)
- 2.4 NaN: centralizar produção E teste.
  - Produção: a constante central `I.NAN` **já existe** (init.lua) — correção é
    consumi-la, não criá-la. `_stat_adv.lua` troca os `0/0` crus (linhas 51, 66, 78).
  - Teste: o predicado central `is_nan` é reinventado inline (`v ~= v`) em
    `_transform.lua` (188, 220, 231 — que inclusive já importa `is_nan` e não usa),
    `_stat_adv.lua` (167) e `_factories.lua` (31). Consumir o central nesses sites.
    (achado da varredura ampla de sentinelas — mesma natureza, fora do mapa original)
  - Fora de escopo (lacuna registrada, não infração): não há `is_inf`/`is_finite`
    central; as checagens `== math.huge` seguem inline por falta de quem consumir.
    Eventual helper futuro, não bloqueia.

## 3. bool_view  [Windows]  [Done — via Fedora]

> **Concluído (2026-06-28), com ressalva de verificação.** Reavaliação de risco:
> item 3 **não tocou C** (só `.lua`/`.txt`/`.md`); `smaug_bool_view` já existia e
> já estava no cdef do FFI (`ffi_loader.lua`), com ABI idêntica à de
> `smaug_f64_view`, que já roda no Windows. Logo é a mesma categoria Lua-pura do
> item 2 — **não** expõe C novo. Critério `[Windows]` suprido por validação
> Fedora: suíte Lua verde (incl. teste bool view+COW), parity 12/12 (eixos 1 e 10
> coerentes com bool=view), Valgrind-clean (nenhuma regressão de memória).
> **Follow-up leve:** confirmar com `build_win.ps1`; reabrir se acusar algo.
> A regra "itens que expõem C novo não fecham por equivalência" segue válida —
> item 3 simplesmente não se enquadra nela.

O C tem `smaug_bool_view` + `bool_cow_detach` (bool é mutável, tem `set`), mas a
camada Lua não expõe. As exceções do parity se contradizem (eixo 1 pergunta "bool
tem view?"; eixo 10 afirma "imutável"). A justificativa "imutável" é falsa.
Decisão tomada: **expor**. Demonstrado rodando (view + COW idênticos a f64/i64/dt).

- 3.1 expor `bool_view` no descritor `_types.lua`
- 3.2 limpar exceptions contraditórias (`view/bool` nos eixos 1 e 10)
- 3.3 revisar mensagem de erro do view — distinguir string (offset-based) de
  categorical (Lua puro); ambos seguem sem view, mas pela razão correta
- 3.4 teste Lua: bool view + COW
- 3.5 COW.md: bool → ✅

## 4. NA relacional unificado + Contrato 7  [Windows]  [Done]

> **Concluído (2026-06-28), com ressalva de verificação.** Lua puro (nenhum C
> tocado — política relacional é Anel 2). É **mudança de comportamento** + contrato
> novo, então o guard são os testes: 8 novos cobrindo os quatro caminhos (simples,
> composta, dois lados do join, NA em valores não dispara). Critério `[Windows]`
> suprido por validação Fedora: suíte Lua verde, parity 12/12, Valgrind-clean.
> **Follow-up leve:** confirmar com `build_win.ps1`; reabrir se acusar algo.
> Nota: documentado como **Contrato 8** (o nº 7 já existe — "índices 1-based").

Hoje join (casa NA com NA), groupby (erro) e pivot_table (aceita) tratam NA na
chave de três formas. Viola o Contrato 6 (NA = ausência que não participa). Decisão
tomada: **erro orientado nas três**, alinhado ao groupby (que já está certo).
"Falha visível > acerto adivinhado" — o usuário trata com fillna/dropna na pipeline.

- 4.1 helper central `validate_keys_no_na(cols, op_name)`
- 4.2 join: NA na chave deixa de casar → erro
- 4.3 groupby: ajustar mensagem ao padrão (mencionar fillna além de dropna)
- 4.4 pivot_table: NA no índice/coluna deixa de ser aceito → erro
- 4.5 documentar **Contrato 8** — NA em chave relacional (o nº 7 já existe:
  "índices são 1-based"; corrigido na implementação)
- 4.6 testes guardando as três operações (chave simples e composta)

*Padrão da mensagem:* `smaug: <op> — <chave/coluna> 'X' contém NA; trate com fillna
ou dropna antes`. NA em qualquer coluna da chave composta dispara.

## 5. Reduções + element-wise no DataSet  [Windows] [Fedora: 5.0]  [Done]

> **Concluído (2026-06-29).** 5.0 valida no Fedora (Anel 0: Valgrind-clean,
> cobertura 101→99 exclusões fechando no ramo n<2). 5.1–5.5 (Lua-puro) verdes no
> Fedora **e no Windows** (`build_win.ps1`, MSYS2-UCRT64). **Decisões:**
> reduções mantêm DataSet 1-linha (cada coluna preserva seu dtype); std/var
> amostrais (ddof=1); element-wise numérico erra em coluna não-numérica; astype
> por mapa.

O DataSet não tinha reduções diretas (`df.sum()`) nem element-wise. O GroupBy
reimplementava reduções por não ter a quem delegar. Maior bloco de paridade.

- 5.0 ✅ **[fundação]** `ddof` de `std`/`var` reconciliado. Era incoerente: Series
  std/var **populacionais** (÷N, no C), mas `cov`/`skew`/`kurtosis`, o GroupBy
  (÷n-1) e o pandas **amostrais** (÷N-1). Sem isso, 5.4 impossível. **Opção A:**
  tudo amostral (ddof=1), NaN para n<2. Anel 0 (`smaug_f64_var`/`smaug_i64_var`)
  → `[Fedora]`. C ajustado, 3 testes recalculados, docs atualizados.
- 5.1 ✅ reduções → **DataSet 1-linha** (cada coluna mantém seu dtype): sum,
  mean, min, max, std, var, median, prod, quantile, skew, kurtosis, mad, sem,
  count_nonnull. Helper `reduce_frame` delega às reduções da Series.
- 5.2 ✅ element-wise → DataSet mesma forma: abs, round, clip, cumsum, cummin,
  cummax, cumprod. Erra em coluna não-numérica.
- 5.3 ✅ transforms: ffill/bfill/shift (qualquer dtype), diff (numérico),
  isna/notna (mask bool, qualquer dtype), astype (mapa `{col=dtype}`).
- 5.4 ✅ GroupBy delega às reduções da Series (`col:take(idx):<redução>()`);
  duplicação inline eliminada; behavior-preserving (possível após a 5.0).
- 5.5 ✅ `min_count` opt-in em sum/prod (Series e DataSet). Default preserva o
  atual (soma de vazio = 0); `min_count=N` exige N não-nulos, senão NA.

## 6. Paridade Series↔DataSet e auditor  [Windows]  [Done]

Fecha as assimetrias restantes e transforma o eixo 02 do parity de **diff de
presença** em **paridade classificada**: cada assimetria é (1) intencional
(dimensionalidade — Series 1-D, DataSet 2-D), (2) par de nome conhecido, ou (3)
gap real. Decisões da sessão de levantamento (2026-06-29), a partir do output real
do parity (83 assimetrias: 51 só-Series, 32 só-DataSet, 44 em ambos):

- 6.1 ✅ `Series:dtype()` — singular que faltava.
- 6.2 ✅ `sort`/`sort_by`: mantidos os dois; pareados no auditor (sem rename).
- 6.3 ✅ `Series:sample/to_markdown/to_string` adicionados.
- 6.4 ✅ eixo 02 reescrito: pares de nome + 74 intencionais em `exceptions.txt` +
  **falha em gap real** (os.exit). 48 ambos · 6 pares · 74 intencionais · 0 gaps.
- 6.5 ✅ `DataSet:clone()` (cópia profunda).

> **Concluído (2026-06-29), Lua-puro.** Windows verde (`build_win.ps1`,
> Series acesso 34, DataSet core 212); equivalência Fedora de praxe para Lua-puro.
> Build verde, parity 12/12.

## 7. Completude do motor (Ring 0)  [Fedora]  [Done]

O motor foi construído numérico-primeiro. Operações agnósticas a tipo e de tipo
ordenável só existem em f64/i64 no C; para os demais dtypes a Lua reimplementa via
fallback element-wise. Depende do item 1 (nulidade coerente) já pronto.

- 7.0 **[fundação, 2026-06-29]** tudo do item 7 vai pro **C (Anel 0)**, a Lua
  apenas delega — **sem fallback**. É responsabilidade do Anel 0 (dono do buffer
  e da máscara). Elimina a duplicação Lua↔C (mesma tese do item 8). Levantamento
  confirmou no fonte: shift/ffill/bfill já funcionam via fallback Lua (mover);
  min/max/rank erram em str/dt (preencher); argmin/argmax erram em str mas dt já
  tem fallback Lua (mover+preencher); eq/ne existem em f64/i64/dt/str, só bool
  não (preencher). String NÃO é bloqueio: a limitação do COW.md é sobre `view`
  (zero-copy), não sobre cópia — `str_take`/`clone`/`filter` já reconstroem buffer.

- 7.1 ✅ shift/ffill/bfill em bool/str/dt (agnósticas a tipo) — **[Fedora]**, era 🟥 do inventário
  - 7.1a ✅ **ffill/bfill** no C (bool/str/dt) + descritor liga, fallback Lua removido.
    str é offset-based (reconstrói por append, padrão de `str_take` — não view).
    Teste C +41 (test_ops_window 244→285), Lua +18 (test_window 62→80),
    allocfail +45 → 1677. Fedora: Valgrind-clean, cobertura 98.97%, 97 exclusões.
  - 7.1b ✅ **shift com sinal** (`int64_t`): negativo tratado no C (fórmula única
    `src = i - periods`), short-circuit `|periods|>=size` evita overflow. ABI de
    `smaug_f64_shift`/`smaug_i64_shift` mudou (size_t→int64_t); shift novo em
    bool/str/dt. Fallback Lua removido por inteiro. Cobriu shift negativo que NÃO
    tinha teste em lugar nenhum. Teste C +29 (285→314), Lua +13 (80→93),
    allocfail +28 → 1705. Fedora: Valgrind-clean, cobertura 98.98%, 97 exclusões.
    **[Done]** — 7.1 fechado (toda movimentação agnóstica a tipo no Anel 0).
- 7.2 min/max/argmin/argmax em ordenáveis (str/dt; bool também incluído)
  - 7.2a ✅ **argmin/argmax** no C para str (lexicográfico), bool (false<true) e
    dt (movido de fallback Lua → C). Fecha a incoerência `dt:argmin`✓/`dt:min`✗ pela
    metade do argmin; gate na Lua passou a ser por capacidade (`self._d.argmin`),
    sem fallback. Removidas 4 exceptions órfãs do parity (argmin/argmax × str/bool).
    Teste C +24 (test_ops_window 314→338), Lua +9 (test_window 93→102). argmin/argmax
    não alocam → allocfail inalterado. Aguarda Fedora p/ Valgrind+cobertura.
    - **Correção (2026-07-22, achado da auditoria dos itens 1–11):** o Anel 0 e o
      descritor estavam corretos, mas o gate na Lua **não** era por capacidade —
      `_cumulative.lua` mantinha um guard por dtype (`~= float64 and ~= int64 and
      ~= datetime`) que barrava str/bool **antes** de chegar em `self._d.argmin`.
      Resultado: capacidade morta — `smaug_str_argmin`/`smaug_bool_argmin` prontos,
      testados no C (411 checks) e ligados no descritor (`_types.lua` 191-192,
      299-300), mas inacessíveis pelo Lua. Nenhum teste Lua exercitava argmin/argmax
      em str/bool, por isso a suíte ficava verde e a lacuna não aparecia.
      Corrigido: guard por dtype → gate por capacidade (`self._d and self._d.argmin`),
      como o item já descrevia; fallback element-wise removido (era código morto —
      os 5 dtypes com descritor têm argmin; categorical não expõe o método).
      Aliases `idxmin`/`idxmax` herdam (delegam a argmin/argmax). +14 guards em
      `test_window` (122→136), cobrindo str/bool, bordas (toda-NA, vazia) e os
      aliases. Lua puro — fecha no Windows.
  - 7.2b ✅ **min/max** em dt/str/bool (decisão: retornam valor). dt → int64
    (sentinela INT64_MIN, via reduce_num); str → ponteiro+len materializado por
    wrapper no descritor (ffi.string), "" distinta de NULL; bool → Shape 1
    (valor+status SMG_NULL_VALUE). `ignore_na` uniforme. Fecha a incoerência
    `dt:min`✗ → agora `dt:min == get(argmin)`. Não alocam → allocfail inalterado.
    Teste C +22 (test_ops_window 338→360), Lua +14 (test_reduce 43→57).
    Fedora: Valgrind-clean, cobertura 98.75%, 97 exclusões. **[Done — 7.2 completo]**
    - Achado (não acionado): `df:min()`/`df:max()` no DataSet ainda filtram só
      colunas numéricas (contrato do item 5). Agora que a Series faz min/max em
      str/dt/bool, estender o DataSet a essas colunas (como pandas) é decisão de
      escopo do frame — registrado para avaliação futura, fora do 7.2.
- 7.3 ✅ **rank em dt/str/bool** (lexicográfico/cronológico/false<true) — **[Fedora]**.
  Os 4 métodos uniformes (average/min/max/first); NA → NaN→nil como os numéricos.
  Retorno `double*` serve todos os dtypes (o rank é sempre double). dt espelha
  i64 (int64, precisão exata); str ordena índices via `str_cmp_idx` (reusa o
  contexto de sort); bool sem qsort (dois grupos false/true). O gate Lua
  `if float64...else i64` virou delegação `self._d.rank` (descritor liga os 5).
  `pct_rank` passou a funcionar em str/dt/bool de graça (chama rank average).
  Removidas 6 exceptions órfãs do parity (rank/pct_rank × str/dt/bool — eram
  "gap real não implementado"; agora suportado). Teste C +31 (test_ops_window
  360→391), Lua +12 (integração 66→78), allocfail +31 → 1736. Caminho numérico
  inalterado (f64/i64 agora via descritor, mesmo C). **[Done]** — Fedora: Valgrind-clean, cobertura 98.71%. Item 7 completo (7.1✓ 7.2✓ 7.3✓ 7.4✓).
  - bool incluído — desvio do escopo literal "dt/str", registrado.
  - Achado (não acionado): rank/pct_rank por-coluna no DataSet = escopo futuro.
- 7.4 ✅ bool eq/ne no C (único dtype sem igualdade). C+header+cdef+wrapper Lua,
  teste C (+11), Lua (+6), allocfail (+20). Fedora-validado (Valgrind-clean + cobertura).

## 8. Rolling → Ring 0  [Windows+Fedora]  [Done]

A versão Lua do rolling (Series e DataSet) reimplementa o que o C faz — e faz
**mais** que o C (std/var/count/min_periods/expanding). "Mandar pro Ring 0" exige
estender o C primeiro, depois Series/DataSet delegam. Decisão: eliminar a
duplicação, fonte única no C.

- 8.1 ✅ estender C: rolling std/var/count (motor genérico double-safe)
- 8.2 ✅ estender C: min_periods (convenção 0=janela-cheia, >=1=parcial, espelha
  min_count do 5.5) — assinatura dos 8 rolling mudou p/ (s, window, min_periods)
- 8.3 ✅ estender C: expanding (é rolling(n, min_periods>=1) — sem C novo)
- 8.4 ✅ Series delega ao C (sum/mean/min/max/std/var/count; median/quantile Lua)
- 8.5 ✅ DataSet delega à Series (remove _agg próprio; ganha std/var/count+min_periods)

> **Status: [Done]** — Fedora: Valgrind-clean (motor genérico + rescan de min/max sem leak/leitura inválida).
> Decisões: o motor cobre mean/std/var/count (double-safe); sum/min/max
> preservam tipo + ganham min_periods local. min/max com min_periods≥1
> usam rescan O(n·window) type-preserving (deque intocada no modo default).
> **Bug morto**: caminho C ignorava min_periods — `rolling(3):min_periods(1):sum()`
> agora dá 1,3,6,9 (era nil,nil,6,9). **Correção de tipo**: expanding/DataSet
> mean de i64 agora → float64 (antes truncava via col._dtype). Testes: C +20
> (test_ops_window 391→411), allocfail +71 (→1804), test_window +23 (93→116),
> ds test_core +8 (212→220). median/quantile rolling/expanding ficam Lua.

> **Achado (levantamento, 2026-06-29):** `rolling:min_periods(p):sum()` **ignora
> min_periods quando o C é usado** — `rolling(3):min_periods(1):sum()` dá
> `nil,nil,6,9` em vez de `1,3,6,9`. O resultado depende do caminho (C/Lua). É a
> própria incoerência que o item 8 cura: a raiz é o C não conhecer min_periods.
> Decisão: não corrigir isolado — o C passa a conhecer min_periods
> (na assinatura, `rolling_*(s, window, min_periods)`), e o bug some.
> **Achado 2:** o DataSet Rolling (`_stat.lua`) NÃO delega à Series — tem `_agg`
> próprio. Duplicação é tripla (C / Series Lua / DataSet Lua); 8.5 faz o DataSet
> passar pela Series. Recorte: sum/mean/min/max/std/var/count vão pro C;
> median/quantile ficam Lua (janela ordenada, padrão diferente) — registrado.
> C estendido + min_periods + Series delega (8.1, 8.2, 8.4); expanding no C
> (8.3); DataSet delega (8.5).

## 9. Contratos de fronteira  [Fedora]  [Done]

Dois achados da exploração de 2026-06-30 sobre o que a lib **promete ao usuário na
borda** — precisão de dados e posse de dados. Não são bugs de corrupção
espontânea; são decisões de contrato com aresta, que precisam estar resolvidas
**antes** do congelamento da API (item 11). "Falha visível > acerto adivinhado"
é o princípio em jogo nas duas.

- 9.1 **int64 acima de 2^53 sem caminho de entrada correto** (E1). Tensão entre o
  guard anti-coerção (CODE_REVIEW A7, correto — recusa `1.5`/`NaN` em int64) e o
  suporte a int64 real. Dois sub-problemas de naturezas distintas:
  - **Sub-problema A** (limitação do Lua, não da lib): literal grande comum
    (`9007199254740993`) já chega truncado — em Lua esse literal *é*
    `9007199254740992` (double) antes de entrar na lib. A lib não pode recuperar,
    só tornar visível.
  - **Sub-problema B** (a lib controla — o bug real): `check_value` (`_core.lua`)
    exige `type(v) == "number"`, o que recusa **cdata int64** (`9007199254740993LL`,
    `ffi.new("int64_t", ...)`) — a única forma que preserva 64 bits. Provado: o C
    guarda até 2^63-1 sem perda; o gargalo é só o guard Lua. Conserto é
    Lua-puro (Anel 0 intocado): `check_value` aceitar cdata `int64_t`/`uint64_t`
    via `ffi.istype`, distinguindo de `double`/`float` cdata (que seguem recusados).
  - **Decisões (fechadas, 2026-07-01):**
    - 9.1.1 consertar Sub-A e Sub-B juntos (não meia-porta).
    - 9.1.2 número > 2^53 em int64 → **avisar-mas-aceitar** (aviso educativo,
      sem bloquear — mesmo padrão do 12.10).
    - 9.1.3 `uint64_t` acima de `INT64_MAX` → **recusar** com erro claro (sem
      wraparound silencioso — coerente com CODE_REVIEW A7 e "falha visível >
      acerto adivinhado").
  - **Achado durante a implementação (2026-07-01):** o `check_value` corrigido
    resolve a **entrada** (`set`/`append`), mas `Series:get(i)` usa
    `get_value`, que aplica `tonumber()` no `int64_t` devolvido pelo C — a
    MESMA limitação da Sub-A, só que na **saída**. O valor fica correto no
    buffer C, mas `get()` reintroduz a perda de precisão acima de 2^53 na
    leitura. **Decisão: escopo estendido no mesmo item.** Novo método
    `Series:get_raw(i)` (só para int64) devolve o `int64_t` cru (cdata),
    sem passar por `get_value`/`tonumber` — espelha o que `check_value` já
    aceita na entrada. `get()` normal mantém o comportamento antigo
    (documentado como limitação conhecida), sem quebrar nada existente.
  - **[Done — 9.1 completo]** `check_value` (`_core.lua`) e `get_raw`
    (`access/_access.lua`) implementados; helper `warn` central adicionado em
    `init.lua` (reutilizável pelo 12.10). Guardado por teste em
    `test_constructors.lua` (9.1.1-9.1.3 + round-trip via `get_raw`).
    **Confirmado no Windows** (`build_win.ps1`, MSYS2-UCRT64): C 10/10
    binários PASS, stress 81851 checks, Lua 18/18 suítes verdes (incl.
    property-based 360862 checks), **parity 12/12**. `get_raw` registrado
    como exceção intencional do Eixo 2 (`scripts/parity/exceptions.txt`) —
    é acesso 1-D como `get`; DataSet não precisa de espelho porque acessa
    via `column()` (que devolve a própria Series).
  - Vínculo: CODE_REVIEW A7; inferência de tipos (item 12.3).
- 9.2 **`df:column(name)` compartilha buffer com o frame** (E2) — **[Fedora]**
  (passou a tocar Anel 0: view+COW de string em C). `column()` retornava a
  referência Series interna direto (aliasing de **objeto**); mutar a coluna
  extraída com `set()` alterava o DataFrame silenciosamente.
  - **Decisão tomada e implementada:** `column()`/`col()` retorna **view COW**
    (não a referência). Leitura zero-copy; primeira mutação destaca buffer
    privado, frame intacto. Categorical (sem view, é Lua puro) retorna `clone()`.
  - **Estendido para tocar Anel 0 (decisão 2026-07-01):** string não tinha view.
    Foi implementada `smaug_str_view` + `str_cow_detach` em C, com **modelo de
    posse mista A1** (campo novo `offsets_owned` na struct `smaug_series_str_t`):
    view compartilha `buffer`/`null_mask`, possui `offsets` próprio absoluto.
    Detach materializa a janela com offsets rebaseados. Ver COW.md.
  - **Op1 (mata o E2 na raiz):** acesso público `column()` protege; código
    interno (relacional, csv, stat — ~40 call-sites) migrado para `_raw_column`
    (referência crua explícita). Mutação intencional de coluna é via
    `update_column`, não mais pelo aliasing.
  - **[Done — 9.2 completo, selado Fedora 2026-07-02]** C: struct + view + detach; FFI cdef sincronizado
    (layout binário); `_types.lua` liga view; `column()`/`_raw_column` em
    `dataset/_core.lua`; testes de proteção E2 (test_core, +8) e de string view
    (test_cow +70, allocfail +70). Testes que dependiam do aliasing E2 migrados
    para dados que nascem com NA (Op A) / `update_column`. `_raw_column`
    registrado como exceção intencional do Eixo 2. **Valgrind-clean**
    (test_cow, test_string, allocfail: 0 leaks, 0 errors); parity 12/12; 18/18
    suítes Lua. Aguarda `--all` do Gui no Fedora (Valgrind + cobertura) para
    selo final.
  - Vínculo: COW.md (string ❌→✅); CODE_REVIEW A7 (posse de dados).

- 9.3 **Fronteira do escalar int-based nos call-sites de operação** — **[Done —
  Fedora 2026-07-26]** (Anel 1, Lua puro → equivalência; ambas as fases seladas).
  Reabre o bloco 9: o 9.1 varreu a **entrada**
  (`check_value`/`get_raw`), mas os call-sites de **operação** (comparadores,
  aritmética escalar) ficaram com o guard cru `type=="number"` — rejeitam a forma
  exata (`cdata int64_t`) e engolem `number > 2^53` degradado, sem o aviso que o
  `check_value` daria. Mesma família do 9.1 Sub-B, nos pontos que o 9.1 não
  alcançou. Achado 2026-07-24 (análise do 10.2 + reescrita do Contrato 1).
  - **Diagnóstico (provado 2026-07-24).** Família de escalar int64 mutuamente
    incoerente hoje: `s:eq(number>2^53)` degrada calado e rejeita cdata;
    `s + number>2^53` opera no degradado e rejeita cdata; `s:fillna(...)` já
    correto (usa o porteiro canônico `check_value` — aceita cdata, preserva). O
    `fillna` é o **modelo**; comparadores e aritmética são os atrasados.
  - **Desenho — porteiro classificador (fonte única).** Extrair do ramo int64 do
    `check_value` (`_core.lua:63-87`) um `normalize_int_scalar(v)` **puro**, que
    devolve `(classe, valor)` sem avisar nem errar. Classes: `number_ok`,
    `number_overflow` (>2^53), `cdata_i64`, `cdata_u64_ok`, `uint_overflow`,
    `not_integer`, `invalid`. A **política** fica no call-site — a única classe que
    diverge é `number_overflow`:
    - **entrada-de-dado** (`set`/`append`/`fillna`, via `check_value`):
      `number_overflow` → **avisa-aceita** (Sub-A irrecuperável, escolha do
      usuário); demais classes idênticas ao atual (equivalência, provada por
      `test_constructors` 9.1.1-9.1.3).
    - **operação** (comparadores, aritmética): `number_overflow` → **erro por
      origem** (o double já perdeu o dígito; o resultado seria mentira); cdata
      exato → aceita. Coerente com o Contrato 1 (narrowing consumado recusado).
  - **Fase 1 — comparadores** (`cmp_*`, int64 + datetime). **[Done — Fedora
    2026-07-26]** Reaponta os 12 wrappers (6 int64 + 6 datetime) do guard cru
    para o porteiro `int_scalar.check_operation` — aceitam `cdata int64_t` (forma
    exata) e recusam `number >= 2^53` por origem. `check_value` delega o
    reconhecimento a `int_scalar.classify` com política de storage inline (level
    preservado → equivalência 9.1.x). **Destrava o 10.2** (os limites do `between`
    entram exatos). Datetime entrou por **coerência de família int-based** (epoch_ms
    é `int64_t`): benefício latente (epoch > 2^53 ms = ano 287586), custo ~zero —
    precedente do `keys.lua` (10.5-A). NB: datetime compartilha o porteiro só no
    **threshold**; sua *entrada* tem parse próprio (não tocada).
    - **Achado (2026-07-26):** o caso canônico `number 2^53+1` degrada para
      **exatamente 2^53**, então o limiar `> 2^53` o deixava escapar. Corrigido com
      a classe `number_at_boundary` (`== 2^53`, ambíguo): a operação recusa
      `>= 2^53`; a entrada preserva `> 2^53`. Sem a leitura/teste teria passado
      silencioso.
    - Testes: `test_constructors` 9.3.1-9.3.6 (cdata aceito e distingue, `number
      >= 2^53` recusado, uint no range, fracionário/inválido, datetime); 9.1.x
      provam a equivalência da extração. Contrato 1 ganhou a nota da divergência
      entrada-vs-operação.
    - **Selo Fedora:** Valgrind-clean (0 erros, 13 binários); 15/15 parity; linha
      98.82%, branch-alvo 94.73%; property-based 360862 checks. Lua puro → sem C,
      sem ABI (dispensa Windows).
  - **Fase 2 — aritmética escalar** (`binop` série×escalar + comutativo, e
    `floordiv`; **só int64** — datetime não tem `*_scalar`). **[Done — Fedora
    2026-07-26]** Integra o porteiro na camada de promoção N.1-N.3 do `binop`,
    **completando a intenção já registrada do N.2** (*"evita o truncamento
    silencioso do escalar na FFI"*, que só cobriu o caso fracionário). Ordem que
    importa: a promoção vem **primeiro** (fracionário ou `/` → float64, o escalar
    vira double legítimo); se a série **permanece int64**, o escalar passa pelo
    porteiro. `is_int_cdata` adicionado ao `int_scalar` para os guards de entrada.
    - **D1 (decidida):** `float64 + cdata int64_t` **mantém o erro** — o porteiro
      só vale com série int64. Float não preserva por natureza; aceitar não
      ganharia nada e alargaria a superfície.
    - **Achado — `cdata + Series` é inalcançável.** O LuaJIT resolve o `__add` do
      próprio `cdata int64_t` antes de chegar em `Series.__add`, então o ramo
      comutativo para cdata-à-esquerda era **dead code** (removido). A forma
      suportada é `Series + cdata`; documentado no código e no teste.
    - **Achado — o `level` do erro depende da mecânica de chamada.** Metamétodo
      (`binop`) usa level 3; método `:` (`floordiv`) tem um frame `[C]` de
      dispatch extra e precisa de 4. Medido com `debug.getinfo`, não estimado.
    - **Nuance (design, não furo):** `/` promove a float64 por N.3 — não preserva
      int64 por definição; o divisor cdata vira double como em qualquer divisão
      verdadeira. Fora da questão de preservação.
    - Testes: `test_constructors` 9.3.7-9.3.10 (cdata preservado em `+`/`floordiv`,
      `number >= 2^53` recusado nos três call-sites, comportamento preservado para
      number seguro/promoção/float, D1).
    - **Selo Fedora:** Valgrind-clean (0 erros, 13 binários); 15/15 parity; linha
      98.82%, branch-alvo 94.73%; 363 checks no `test_constructors`; property-based
      360862 checks.
  - **Não-escopo (explícito, não é esquecimento).** `f64`/`string`/`bool` fora:
    double é nativo (number já exato), string sem degradação, bool sem
    comparadores de ordem. Unificar os guards crus deles depois é *limpeza de
    código* separada, não correção. `map` → item à parte (10.3 reclassificado).
    `fillna` → já resolvido (é o modelo).
  - **Doc.** Contrato 1 ganhou a linha registrando a divergência: *parâmetros de
    operação recusam `number >= 2^53` onde o armazenamento avisa-aceita* — senão o
    leitor não entende por que `eq(number grande)` erra e `set`/`fillna` avisam.
    README: nota do int64 > 2^53 atualizada para o estado real (2026-07-26).
  - **Selo.** Anel 1, Lua puro → fecha por equivalência Fedora (`test_constructors`
    9.1.x prova a extração; 9.3.x provam os call-sites de operação). Sem C,
    sem ABI.
  - **Vínculo:** 9.1 (Sub-B, mesma família); Contrato 1 (reescrito 2026-07-24);
    10.2 (consumidor da Fase 1 — limites do `between` entram exatos); 10.3
    (`map`, item irmão); `keys.lua` (precedente de datetime latente).

- 9.4 **`nlargest`/`nsmallest` fabricavam valor fora do dataset** — **[Done —
  Fedora 2026-07-26]** (Anel 1, Lua puro → equivalência). Achado 2026-07-26 na
  leitura macro do item 10. Categoria **acima** de degradação: numa operação de
  *seleção* — cujo contrato é "devolva os N maiores **que estão** nos dados" —
  o retorno continha um número **ausente do dataset**.
  - **Provado.** Série `{…992, …993, …995}`: `nlargest(2)` devolvia `…996` e
    `…992`. Mecanismo: `c_sorted_nonnull` normalizava o buffer para `double[?]`
    (`arr[i] = tonumber(iptr[i])`), e acima de 2^53 só os pares são
    representáveis — `…995` arredonda para `…996`, valor que nunca existiu.
    Agravante: **avisava**, mas com mensagem enganosa (o warn do `check_value`
    fala em "literais Lua", e o usuário não escreveu literal — o valor veio dos
    dados dele), apontando a causa errada.
  - **Correção.** `c_sorted_nonnull` foi separada em duas, com a normalização
    deixando de ser escondida: `c_sorted_nonnull_native` devolve o buffer **no
    tipo nativo** (`double[?]` para f64, `int64_t[?]` para int64) e é a fonte
    única da chamada C, da cópia e do `free`; `c_sorted_nonnull` virou um wrapper
    fino que normaliza para `double[?]`. `nlargest`/`nsmallest` passaram à
    nativa e entregam o `cdata int64_t` direto ao `from_table` (que o aceita
    desde o 9.1) — sem `tonumber`, sem `math.floor`.
  - **Limitação registrada (não é bug).** `median`, `quantile`, `skew` e
    `kurtosis` seguem na versão `double`: interpolação e momentos são float por
    natureza e o retorno é `number` Lua, que não comporta > 2^53 de todo jeito.
    Em int64 > 2^53 esses valores perdem dígito — limitação de tipo de retorno,
    documentada, distinta da corrupção de container tipado que era o 9.4.
    `mode` está correto (migrado ao `keys.lua` no 10.5-A).
  - **Bug secundário corrigido.** O ramo f64 vazava o ponteiro do C quando
    `ptr != NULL` e `n == 0` (`return nil, 0` antes do `smaug_free`); o ramo i64
    já tratava. Agora ambos liberam.
  - Testes: `test_selection` 9.4.1-9.4.5 (valores exatos e presentes no dataset,
    dtype preservado, `n > len`, f64 inalterado, nulos ignorados). **Mutação
    verificada:** reintroduzir o `tonumber` faz o 9.4.1 abortar.
  - **Selo Fedora:** suíte verde (66 checks em `test_selection`, +10); 15/15
    parity. Lua puro → sem C, sem ABI.
  - **Vínculo:** 9.1 Sub-A (`get_raw` existe porque `get`/`tonumber` degrada —
    mesma fronteira de leitura); 9.3 (fronteira do escalar); 10.5-A (`keys.lua`,
    que já curou `mode`).

## 10. Completude de vetorização (Anel 0)  [Fedora]

Mesma tese do item 7 (completude do motor), agora para **transformações
element-wise**. A exploração de 2026-06-30 mapeou operações que fazem o loop em
Lua cruzando FFI por elemento, quando o padrão correto (delegar ao descritor → C)
já existe e é seguido em toda a aritmética (o `binop` é exemplar).

**Classificação corrigida (2026-07-23, auditoria do item 10).** O texto original
dizia que "10.1–10.4 não são bugs — são assimetrias de vetorização (performance)".
Isso estava **errado para 10.2 e 10.3**, e foi provado empiricamente na auditoria:
`between(x, x)` no próprio `x` devolvia **false** para `x = 9007199254740993`, e
`abs(-9007199254740993)` devolvia `9007199254740992` — corrupção **silenciosa**,
sem aviso nem erro. A causa é a mesma do 10.5–10.7: o loop Lua round-tripa por
`get()`/`tonumber()` (double), perdendo dígitos acima de 2^53. Classificação real:
- **10.1 e 10.4 — performance.** Confirmado: `.dt`/`.str` operam sobre epoch_ms e
  strings, sem risco de degradação; `prod()` devolve double por escolha de tipo de
  retorno (discutível à parte, não é corrupção de leitura).
- **10.2, 10.3, 10.5–10.7 — defeito de correção.** A assimetria vem com perda
  silenciosa de dado. 10.5–10.7 já foram tratados; **10.2/10.3 ganharam o degrau
  paliativo** (falha visível) na mesma auditoria — ver abaixo —, mas a correção
  de verdade (descer ao Anel 0) continua pendente.

> **Meta-decisão:** levar ao Anel 0 o que o projeto já sabe fazer (o `binop`
> prova o padrão). Onde a primitiva escalar já existe mas falta a vetorizada,
> criar a versão de série; onde nem escalar existe, criar. A Lua passa a delegar.

- 10.1 **`prod()` → Ring 0** (E3). Única redução escalar fora do C — sum/mean/min/
  max/std/var todas têm primitiva; existe `cumprod`, falta `prod`. Assimetria por
  omissão (passou batido no item 5). Criar `smaug_f64_prod`/`smaug_i64_prod`.
- 10.2 **`between()` → Anel 0** (E4). Element-wise. **Fatiado por risco:** a
  correção de 2^53 é toda em int64, mas o loop no Anel 1 é dos quatro dtypes —
  fazer só um deixaria a desparidade de pé. Fatiar é aditivo (nada se joga fora),
  então custa no máximo um selo extra, nunca retrabalho.
  - **Fatia 1 — `float64` + `int64`: [Windows OK 2026-07-27 · selo Fedora
    PENDENTE]** Confirmada no MSYS2-UCRT64 (carga dos `cdef` novos, 11 binários C,
    suíte Lua completa, 15/15 parity). Falta o selo `[Fedora]`: **Valgrind** não
    roda no Windows. Cobertura já medida fora do Fedora (gcov): linha 98.83%,
    branch-alvo 94.76% — acima do baseline anterior (98.82% / 94.73%).
    `smaug_f64_between` / `smaug_i64_between`: **primitiva dedicada de passada
    única**, não composição interna de `ge`+`le`. Motivo: compor exigiria três
    pares de alocação (result+mask) e três varreduras para o que uma varredura e
    um par fazem, e os quatro modos de `inclusive` obrigariam a alternar
    `ge`/`gt` e `le`/`lt` dinamicamente. Os dois `bool` (`inc_lo`/`inc_hi`)
    cobrem os quatro modos direto.
    - Em int64 a comparação é feita em `int64_t` puro — **> 2^53 passa a
      funcionar de verdade**, não só a falhar visível. `between(x, x)` no próprio
      `x` para `x = 9007199254740993` agora acerta; era erro visível (degrau) e,
      antes dele, silenciosamente `false`. **O degrau saiu do `between`.**
    - Os **dois limites** entram pela fronteira do escalar (9.3): cdata exato
      aceito, `number >= 2^53` recusado por origem. Sem isso o valor da série
      seria exato e o limite viria degradado — é o que faz o suporte ser real.
    - NaN em f64 → `0` com máscara **válida** (comparação com NaN é falsa, não é
      null), coerente com os comparadores e com o CODE_REVIEW A3. Nulo propaga
      nulo. Série vazia → len 0.
    - Testes: `test_access` 10.2.1-10.2.7 (exatidão > 2^53, os quatro modos em
      **ambos** os dtypes, limite number recusado, nulo/NaN, vazia, fallback
      intacto) e `test_ops_edge` (nível C: série NULL, `out_mask` NULL, nulo no
      elemento, quatro modos, exatidão > 2^53). **Mutação verificada:** inverter
      a inclusividade e reintroduzir a comparação via `double` fazem o teste
      abortar. Varredura OOM: `af_f64_between` / `af_i64_between` (allocfail
      1878 → 1898).
    - **Achado de cobertura (2026-07-27):** a primeira leva de testes exercitava
      os quatro modos só em `int64`; os ramos `inc_lo`/`inc_hi` falsos do f64 e
      os caminhos `out_mask == NULL` / série NULL de ambos ficaram descobertos, e
      a branch-alvo **caiu** de 94.73% para 94.39%. Cada dtype tem implementação
      própria — testar os modos num não prova nada sobre o outro. Corrigido com
      os testes acima; a métrica voltou a 94.76%.
    - **FFI/ABI** (cdefs novos) → Windows obrigatório, feito. Falta Valgrind
      (Fedora) para fechar o selo.
  - **Fatia 2 — `datetime` + `string`** (pendente). `datetime` é gesto igual ao
    i64 (epoch_ms é `int64_t`), mas o arquivo usa macro geradora (`DT_CMP_IMPL`)
    e `between` não cabe nela (dois limites + dois flags) — nasce função normal.
    `string` **deve reusar `str_cmp_at`** (a colação já é fonte única em
    `str_compare`); reimplementar `memcmp` duplicaria semântica de ordenação
    entre funções. Enquanto não entrar, `between` mantém o fallback em Lua com o
    degrau para esses dois — estado **transitório e documentado no código**, não
    desparidade permanente.
  - **Degrau paliativo (2026-07-23) — saiu de `between` na fatia 1.** Era
    **defeito de correção**, não performance: o loop lia via `get()` (double) e a
    comparação ficava errada em silêncio. `check_int64_lossless` trocou o
    resultado errado por falha visível; a vetorização trocou a falha visível por
    resultado certo. Segue ativo em `abs`/`round`/`clip` (10.3) e no fallback de
    datetime/string até a fatia 2.
- 10.3 **`abs`/`round`/`clip` → Ring 0** (E5). Element-wise matemáticos fixos, hoje
  via `self:map(closure)` (FFI por elemento). Provável que **falte a primitiva C**
  — então "delegar" aqui é criar a primitiva vetorizada, não só religar. Confirmar
  no fonte antes de executar.
  - **Degrau paliativo aplicado (2026-07-23).** Também **defeito de correção**:
    `abs(-9007199254740993)` devolvia `9007199254740992` — perda silenciosa de
    dígito, e `clip` idem. As três (`abs`/`round`/`clip`) passam pelo `map`, que
    lê via `get()`; o degrau roda dentro da closure (o `map` já passa `(v, i)`,
    então é uma passada só, sem custo extra). **`map()` reclassificado sob o
    Contrato 1 (2026-07-24):** hoje `map(fn, "int64")` sobre int64 > 2^53 entrega
    o valor **degradado** à closure (`v = get(i)` → double) e grava sem aviso —
    provado: entra `...993`, sai `...992`. Isso é **narrowing silencioso**, o
    único que o Contrato 1 reescrito proíbe; a justificativa antiga ("API
    genérica, o caller escolhe dtype e closure, bloquear seria invasivo") não
    sobrevive ao princípio — "o caller escolheu" não autoriza degradar em
    silêncio. Decisão a tomar (**preservar-ou-recusar**, nunca degradar): (a) com
    dtype de saída int64, passar o valor **cru** (cdata `get_raw`) à closure —
    preserva, mas muda o que a closure recebe (cdata int64_t, não `number`: a
    aritmética Lua difere, pode quebrar closures que assumem number); ou (b)
    recusar int64 > 2^53 na entrada do `map`, como as demais (falha visível, mesma
    fronteira do degrau). Item próprio — não é mais "fora por decisão".
  - **Lacuna de teste que escondeu isto:** `Series:abs()`, `:round()` e `:clip()`
    não tinham **nenhum** teste direto (só via DataFrame, e nunca com int64 > 2^53).
    Guards adicionados em `test_access` (+13, 127→140): recusa acima de 2^53,
    mensagem nomeando a operação e mostrando o valor exato, fronteira 2^53 exato
    ainda aceita, caminho normal (int64 pequeno, float64, nulos) intacto.
- 10.4 **família `.dt` e `.str` vetorizadas** (E6). `dt_component` chama
  `C.smaug_dt_year(v)` **por elemento** num loop Lua — a lógica escalar está no C,
  falta a versão de série (`smaug_dt_year_series(s) → série`). Mesmo padrão em
  `.str` (upper/lower/len/...). Criar as primitivas de série; a Lua delega.
- 10.5 **chave de igualdade/cardinalidade → int64 exato (L2)** (E7). Não é
  performance — é **defeito de correção**, mesma família do 10.6/10.7. O padrão
  `type(v)..":"..tostring(v)` sobre `series:get(i)` estava repetido em 6+
  call-sites: `unique`/`nunique`/`value_counts`/`mode`/`isin`/`duplicated`
  (Series), `join`/`groupby` (relacional) e `row_dup_key` (DataSet). O furo é a
  propagação da mesma perda do 9.1: `get()` reintroduz o double na saída (o valor
  está exato no buffer C, mas `tonumber` degrada acima de 2^53). **Provado (L2,
  2026-07-19):** dois int64 distintos > 2^53 (ex.: 9007199254740992 e ...993 —
  IDs, contadores) colapsavam na MESMA chave → join casava linhas erradas,
  groupby/unique/value_counts fundiam grupos/valores, isin/duplicated erravam —
  em silêncio, sem teste que guardasse. E a chave era guardada como VALOR no
  resultado (groupby/value_counts/join), degradando o int64 no próprio resultado.
  - **Enquadramento arquitetural (P3 — responsabilidade única).** "Canonicalizar
    valor de coluna para comparar" já vive no Anel 0 para *ordenação*
    (`smaug_multi_argsort`), e o `smaug_hash_table_t` já está reservado lá "para
    GroupBy futuro". A chave de *igualdade* pertence ao mesmo anel — deixá-la no
    Lua duplicaria o conceito entre camadas (o que P3 proíbe). Logo, como no 10.6:
    Passo A corrige na camada acessível; Passo B desce ao Anel 0 (destino).
  - **Passo A — fonte única em Lua CONCLUÍDO (selo Fedora 2026-07-19):**
    `core/keys.lua` (`encode`/`value`/`encode_value`) — uma canonicalização só,
    prefixo pelo **dtype da coluna** (não `type()` do valor: assim o int64 100 da
    série via `get_raw` e o 100 cru da lista do `isin` batem). int64 lê via
    `get_raw` (preserva); demais via `get`. Migrados os 6+ call-sites; eliminados
    `dup_key` (morto, exposto sem uso), a 3ª cópia em `row_dup_key`, e o `mode`
    sem prefixo de tipo. Diferente do Passo A do 10.6 (guarda que **recusa**),
    aqui **preserva** — alinhado ao *destino* do 10.6 (Passo B preserva exato).
    Guards permanentes (`test_keys` 18, +5 relacional, +7 predicates).
    Valgrind-clean, parity 14/14, cobertura de linha 98.82%.
  - **Passo B — descer ao Anel 0 (destino, não otimização opcional):** a
    canonicalização/hash de igualdade vira primitiva do Núcleo (usando o
    `smaug_hash_table_t` reservado), e `keys.encode` passa a delegar a ela —
    fechando o P3 (conceito num anel só, junto do `multi_argsort`). O `keys.lua`
    já é o ponto de plugue: o Passo B substitui o corpo de `encode`/`value` sem
    tocar nenhum call-site. Precisa de levantamento próprio (hash de valores
    arbitrários incl. string/datetime em C é trabalho real). Vínculo: 12.4
    (categorical hash — a ponta já registrada).
- 10.6 **Família seleção/preenchimento por máscara → Anel 0** (achado 2026-07-02,
  ampliado 2026-07-06). Toda a família que escolhe/preenche valor por posição
  segundo uma máscara vive no Anel 1 via loop `get→set`+`from_table`: `fillna`
  (null→escalar), `combine_first` (null→`other[i]`), `where`/`mask`/`ifelse`
  (cond bool→a/b), e os parentes de propagação `ffill`/`bfill`. Todos round-tripam
  por `tonumber()` e **corrompem int64 > 2^53** (provado 2026-07-06 em
  where/mask/ifelse/combine_first, além de fillna/astype). Dois regimes: muito
  acima de 2^53 avisa (ruidoso, grava errado); na fronteira (double arredonda a ≤
  2^53) grava em **silêncio total**. Datetime fora do raio (epoch_ms ≪ 2^53).
  - **Passo A — degrau estendido à família (selo [Fedora] 2026-07-06):** a guarda
    única `check_int64_lossless` (fronteira única do 9.1) passou a proteger
    `where`/`mask`/`ifelse`/`combine_first` — recusam visível int64 > 2^53 em vez
    de corromper calado. Reuso da mesma guarda, sem critério novo. Testes: +5
    selection, +2 predicates. (fillna/astype já cobertos em 2026-07-05.)
  - **Passo B (plano revisado, 2026-07-06):** **não** criar `fillna` isolado — a
    pergunta "isso deveria estar no C?" expôs que fillna é membro de uma família;
    primitiva isolada bifurcaria a categoria (metade C, metade Lua), a desparidade
    que o item combate. Desenhar as primitivas **fundamentais**: (a) seleção por
    null-mask + fonte escalar/série (serve `fillna`, `combine_first`); (b) seleção
    por cond-bool com Kleene (serve `where`/`mask`/`ifelse`); (c) o caso à parte
    da propagação (`ffill`/`bfill`). Todos os membros delegam. As 3 primitivas C
    `*_fillna` isoladas (i64/f64/dt) tentadas antes foram **descartadas**
    (2026-07-06) — reintroduzidas integradas no desenho da família. Paridade:
    property-based + Lua-ref lado a lado + casos dirigidos int64 > 2^53. `str` e
    `bool` são casos especiais (offset-based; bool alinha ao 10.8).
  - **Passo B.1 — null-mask escalar CONCLUÍDO (2026-07-07):** `coalesce_scalar`
    por dtype (`i64`/`f64`/`dt`/`str`), no molde do `binop_scalar` — `i64`/`f64`/`dt`
    reusam `clone`; `str` faz two-pass O(n) (offset-based, preserva `\0`). O
    `fillna` delega: valida o `value` uma vez via `check_value` canônico (aceita
    `cdata int64` — **cura a desparidade** do porteiro caseiro) e chama a primitiva.
    int64 > 2^53 preservado exato; o **degrau saiu do `fillna`** (segue nos demais
    membros). `bool` no Anel 1 até 10.8; `dt` restrito a `number` (ISO → 12.16).
    Provado por FFI + suíte (fillna 39 checks). Valgrind 0-errors; cobertura de
    linha 98.73→98.75%.
  - **Passo B.1.cov — branch-alvo do `coalesce_scalar` [CONCLUÍDO 2026-07-08]:**
    7 guards de contrato marcados `COV-EXCL-BR`; ramos alcançáveis do `str`
    cobertos pelo teste de string vazia. Selo Fedora: Valgrind 0, branch-alvo
    94.26%. Detalhe no CHANGELOG.
  - **Passo B.2 — null-mask série CONCLUÍDO (2026-07-09):** `coalesce` série+série
    por dtype (i64/f64/dt/str), irmão do escalar. `combine_first` delega (bool no
    Anel 1 até 10.8; degrau sai). int64 > 2^53 exato; ambos-nulos → nulo. Fecha a
    primitiva **(a)** do Passo B (escalar + série); restam (b) cond-bool e (c)
    propagação. Selo Fedora: Valgrind 0, branch-alvo 94.26→94.33%. Detalhe no CHANGELOG.
  - **Passo B.3 — cond-bool `select` CONCLUÍDO (2026-07-09):** `select(cond,a,b)`
    por dtype (i64/f64/dt/str); cond true→a, false/NA→b (1a). Unifica
    where/mask/ifelse; escalar/nil por broadcast em Lua. Degrau sai. **Fecha a
    primitiva (b)**; resta (c). Windows OK; branch-alvo 94.38→94.49%. **Selo Fedora
    obtido (2026-07-09):** Valgrind 12/12 clean, branch-alvo 94.49% (3825/4048).
  - **Passo (c) — propagação `ffill`/`bfill`:** já no Anel 0 desde o item 7.1
    (movimentação de dados agnóstica a tipo, 5 dtypes, Lua delega limpo).
    Teste dirigido int64 > 2^53 adicionado (2026-07-09). **10.6 CONCLUÍDO:
    (a) coalesce + (b) select + (c) ffill/bfill — família inteira no Anel 0.**
- 10.7 **`astype` — matriz `src×dst` no Anel 0** (achado 2026-07-02, mesma
  natureza do 10.6). O loop geral do `astype` também round-tripa por `get()`:
  conversão de/para int64 com valores > 2^53 grava corrompido. **Decisão
  (2026-07-05): matriz `src×dst` completa em C**, não só as faixas int64 — a
  opção parcial deixaria o `astype` com dois caminhos para a mesma operação
  (metade C, metade Lua), a desparidade que o item existe para eliminar.
  Condição de fechamento: paridade provada contra o comportamento Lua atual
  (rigidez bool 0/1, tolerância string→num/datetime, `dayfirst`), que hoje é o
  oráculo. Fora do raio (delegam ao C): `take`/`filter`/`view`.
  - **Passo A — degrau (selo [Fedora] 2026-07-05):** guarda única
    `check_int64_lossless` (`_core.lua`, ao lado do `check_value`, fronteira
    única do 9.1) troca corrupção silenciosa por falha visível. `fillna` e
    `astype` (`int64→{int64,string}`) recusam > 2^53; `int64→float64` e
    `int64→bool` seguem OK (double é o destino correto / 0-1). Paliativo — sai
    quando o Anel 0 (Passo B) entrar. Testes: +2 `fillna`, +5 `astype`.
    Desparidade registrada e não consertada aqui: `fillna` rejeita `value`
    cdata (validação divergente do `check_value`) — morre no Passo B ao delegar.
  - **Passo B (em execução, 2026-07-05; escopo revisto 2026-07-09):** matriz
    `src×dst` explícita no C, em arquivo dedicado `smaug_astype.c` (cast é
    responsabilidade própria — não se espalha pelos `ops_*`), **uma função por
    par** (type-safe no FFI). **Escopo (2026-07-09):** os 4 dtypes de struct
    (int64/float64/string/datetime), matriz 4×4. `bool` fica no Anel 1 até o 10.8
    — caminho-duplo temporário, débito conhecido e alinhado ao precedente da
    família 10.6 (não é a desparidade permanente que o item combate);
    `categorical` é Lua puro, fora do C. Cantos `datetime↔bool` → **erro limpo**
    ("conversão não suportada; use `:map`"). Gabaritos **intencionais**:
    `str→i64`/`str→f64` **rígidos** via fonte única `smaug_convert` (`strtoll`
    base-10 / `strtod`; rejeitam trailing/vazio/overflow — i64 sem hex/float,
    f64 com hex/inf/nan). Coerência com o `str→num` do CSV, divergindo do oráculo
    `tonumber` de propósito (*falha visível*); `f64→{i64,dt}`
    fora-do-range/NaN/±inf → null (Contrato 2 + evita UB do cast). Paridade
    (opção 2): `astype` Lua como oráculo lado a lado; property-based onde o
    oráculo é válido, dirigidos onde ele tem o bug (> 2^53) e nos cantos. Lua-ref
    e degrau saem ao fechar. **Execução em 5 fases** (detalhe no CHANGELOG):
    - **Fase 0 — infra:** `smaug_astype.c`/`.h` integrados ao build. Selo
      [Fedora] 2026-07-09.
    - **Fase 1 — Grupo A (arrays diretos):** 6 primitivas i64/f64/dt (`dt↔i64`
      copia int64 exata — conserta o > 2^53). Arquivo 100%/100%, Valgrind clean.
      Selo [Fedora] 2026-07-09 (global: linha 98.70%, branch-alvo 94.56%).
    - **Fase 2 — Grupo B-out (`→str`) selada (2026-07-09):** `i64→str` (`%lld`
      exato, conserta > 2^53), `f64→str` (`%.17g`), `dt→str` (`smaug_dt_format`).
      Construção single-pass via `append`. Arquivo 100%/100%, Valgrind clean,
      `test_astype` 52 checks; global linha 98.71% / branch-alvo 94.60%.
    - **Fase 3 — Grupo B-in (`str→`) selada (2026-07-09):** `str→i64`/`str→f64`
      via `smaug_convert` (parse rígido, fonte única), `str→dt` via
      `dt_parse`+`dayfirst`. `test_astype` 90 checks; `smaug_convert.c` e
      `smaug_astype.c` 100%/100%, Valgrind clean; global linha 98.72% /
      branch-alvo 94.66%. **As 9 primitivas do Passo B completas.**
    - **Fase 4 — rewire no Anel 1 CONCLUÍDA (2026-07-09):** `cdef` +12
      primitivas; `astype` Lua vira dispatch de 5 zonas (clone / matriz C /
      erro limpo `datetime↔bool` / loop reduzido a bool / categorical);
      degrau e loop elemento-a-elemento removidos. Comportamento: `num→str`
      `%.17g`, `str→num` rígido, `datetime↔bool` erro limpo, int64 > 2^53 exato.
    - **Fase 5 — selo:** Fedora `--all` (Valgrind 13/13, 98.72%/94.66%, parity
      12/12) **+ Windows `build_win.ps1` verde** (o gate Windows revelou e
      corrigiu um crash de heap cross-runtime no I/O, pré-existente e ortogonal
      — ver CHANGELOG). **10.7 Passo B CONCLUÍDO nos dois ambientes.** `astype`
      inteiramente no Anel 0, exceto pares com bool (Anel 1 até 10.8). Resta o
      follow-up 10.9 (unificação de formatação).
- 10.8 **`BoolSeries` — coerência de caminho com o Anel 0** —
  **CONCLUÍDO (2026-07-13, Fedora; Windows follow-up).** O achado 2026-07-02
  apontava loops Lua no `boolseries.lua`; desde então o caminho vivo passou a ser
  a `Series<bool>` struct e o `boolseries.lua` ficou **órfão** (sem `require`, sem
  teste). Resolução em 3 incrementos: (a) removido o módulo morto; (b)
  `describe(bool)` usa `:count_true()` (Anel 0) no lugar do loop; (c) criada
  `smaug_bool_coalesce_scalar` — fecha a família `coalesce_scalar` (i64/f64/dt/str)
  — e `fillna(bool)` delega a ela. As primitivas C raw permanecem (são o motor que
  as `smaug_bool_series_*` reusam). Detalhe no CHANGELOG.
  - **Achado da auditoria (2026-07-23) — cinco comentários órfãos apontam para
    este item, que já fechou.** O 10.8 encerrou com escopo **redefinido** (o
    achado original era o `boolseries.lua` órfão), mas cinco pontos do código
    dizem "bool fica no Anel 1 **até 10.8**", esperando que ele trouxesse bool
    para as famílias do 10.6/10.7: `_predicates.lua:264` (combine_first),
    `_selection.lua:143`/`:203` (where/mask), `_transform.lua:29`/`:277` (astype).
    Quem ler o código vai buscar o 10.8, ver "CONCLUÍDO" e concluir que bool foi
    resolvido — não foi. **O que falta para bool, medido no fonte:**
    `smaug_bool_coalesce` (série; existe só a `_scalar`), `smaug_bool_select`, e
    **nenhum** par de `astype` com bool (a matriz é 4×4 dos dtypes de struct).
    Sem risco de int64 aqui (bool não degrada), então é coerência de anel, não
    correção. **A decidir:** abrir item próprio para "bool nas famílias 10.6/10.7"
    e reapontar os cinco comentários para ele.
- 10.9 **Formatação de serialização canônica (`smaug_fmt_f64`/`smaug_fmt_i64`)** —
  [decidido 2026-07-09, follow-up do 10.7]. Hoje `%.17g`/`%lld` estão hardcoded
  em 3 pontos C que concordam mas duplicam: `astype`, `csv`, `json`. Criar fonte
  única no Anel 0 e migrar os três (o `csv` aplica seu separador decimal em
  cima). Elimina a redundância — mudar o formato passa a ser um ponto só. Não
  migra o **display**: serialização (exata, `%.17g`) e apresentação (bonita) são
  contratos distintos — ver 11.4/11.5. **Simétrico decidido 2026-07-09:**
  unificar também `str→num`. A fonte única rígida já nasceu na Fase 3 do 10.7
  (`smaug_convert`: `smaug_parse_i64`/`smaug_parse_f64`); falta refatorar o
  `try_i64`/`try_f64` do CSV como thin wrappers dela. Adiado pra cá (não feito na
  Fase 3) porque o CSV passaria a copiar cada campo — regressão de perf no hot
  path de I/O que merece medição própria antes.
  - **Fase A CONCLUÍDA (2026-07-09, Fedora+Windows):** fonte única `num→str`
    (`smaug_fmt_i64`/`smaug_fmt_f64` no `smaug_convert`, bidirecional) +
    normalização NaN/inf/-inf (elimina divergência do `%g` entre glibc/UCRT);
    8 pontos migrados; `smaug_convert.c` 100%/100%.
  - **Fase B CONCLUÍDA (2026-07-09, Fedora+Windows):** `str→num` — núcleos
    `smaug_parse_*_cstr` (sem cópia, hot-path); `smaug_parse_*(s,len)` copia e
    delega; `try_i64`/`try_f64` do CSV viram wrappers `_cstr`. Perf provada sem
    regressão (2613 vs 2618 ms em `read_csv` 100k). **10.9 CONCLUÍDO:**
    `smaug_convert` é a fonte única bidirecional texto↔número (`num→str` via
    `fmt`, `str→num` via `parse`/`_cstr`). Resta o débito 12.21 (JSON não-finitos).

## 11. Ergonomia REPL  [Windows]  [Done]

**CONCLUÍDO (2026-07-13, Fedora — Windows dispensado por equivalência: Lua puro,
sem caminho libc-divergente).** Fonte única `core/display.lua`
(cell_str/dwidth/pad/align/plan_rows); todos os objetos expostos com
`__tostring`; eixo de parity 13 audita o invariante. Detalhe no CHANGELOG.

Objetos que o usuário segura devem se auto-mostrar legíveis — para exploração e
para debug quando dá erro. Requisito de v1.0: a API congela com a ergonomia que
tiver.

- 11.1 CategoricalSeries `__tostring` (objeto de 1ª classe; hoje cospe `table: 0x…`)
- 11.2 proxies `__tostring` (StrProxy, .dt, .at, .cat, Rolling, Expanding, GroupBy)
- 11.3 estabelecer invariante "objeto exposto → `__tostring`" + eixo de auditoria no
  parity que o guarda
- 11.4 exibição de int64 > 2^53: `to_string`/`to_markdown` formatam via
  `cell_str(get(i))` — o número impresso não é o armazenado, sem sinal ("acerto
  adivinhado" impresso). O dado no buffer C está íntegro; defeito só de
  apresentação. Decidir formato: dígitos exatos (via `get_raw`), sufixo `LL`
  como marcador honesto de int64, ou aviso ao exibir acima do limite.
- 11.5 **`pad`/`cell_str` duplicados com formatação divergente** (achado
  2026-07-05). `pad` definido 5× (2 em `access/_transform.lua`, 1 em
  `dataset/_core.lua`, 2 em `dataset/_io_support.lua`) com lógica idêntica —
  redundância pura. `cell_str` definido 2× **divergentes**: Series
  (`_transform.lua:146`) usa `tostring` (14 díg. significativos); DataSet
  (`_core.lua:392`) usa `%.4g`. Mesmo float impresso diferente conforme o
  contêiner — provado: `3.14159265358979` sai `3.1415926535898` na Series e
  `3.142` no DataSet. Consolidar numa fonte única de formatação de célula
  (`I.cell_str` do DataSet já é exportado — candidato a canônico). Vínculo:
  11.4, que consome `cell_str(get(i))`. **Decisão 2026-07-09:** a fonte canônica
  de `cell_str` é de **apresentação** (bonita), distinta da serialização exata
  (`%.17g`, ver 10.9). Consolidar o display não deve alinhá-lo ao `%.17g` —
  "display ≠ serialização" é contrato.

## 12. Achados menores + débitos antigos  [Windows+Fedora]

Baixo risco, não bloqueiam nada acima. Varredura de limpeza.

- 12.1 **CONCLUÍDO (2026-07-14).** Além da duplicação registrada, a leitura
  achou que o prefixo fixo do C **mentia**: `read_csv_mem("")` reportava
  `smaug: smaug_read_csv: arquivo vazio` — função errada e "arquivo" quando a
  entrada é buffer. Corrigido separando responsabilidade: o Anel 0 emite só a
  **razão** (`"entrada vazia"`), o Anel 3 emite a **op** — mesma divisão que os
  writers já usavam (`smaug: to_csv — falha ao escrever`). 15 `make_error`
  limpos; `table_to_dataset(t, op)` recebe a op das 4 entradas
  (read_csv/_mem, read_json/_mem). O contrato de mensagem estava sem teste;
  agora tem.
- 12.2 **CONCLUÍDO (2026-07-14).** Linha comentada removida do `init.lua`. O
  Parquet já está registrado no `ARCHITECTURE.md` (marco 1.5, após `.smg` e
  Excel); o comentário era redundante e sugeria algo meio-feito que não existia.
- 12.3 **CONCLUÍDO (2026-07-14) — era crash, não "decidir".** O registro pedia
  para "decidir: fechar ou registrar pós-1.0". Reproduzido: `to_csv_mem` e
  `to_json_mem` **crashavam** com coluna datetime
  (`attempt to get length of local 'v' (a number value)`). Causa: o
  `smaug_column_t` não tem `dt`, e o mapa de dtype no `dataset_to_table` já
  traduzia datetime → `"string"` mas **entregava a coluna datetime crua** — o C
  recebia a promessa de string e o laço fazia `#v` num epoch_ms. Não era "falta
  de suporte", era incoerência do Anel 3. Fix: converter via `astype("string")`
  (produz ISO 8601) antes de montar a table — **uma correção, dois formatos**
  (o `json.lua` reusa a função). Sem mudança de ABI. Round-trip de **valor**
  preservado (`astype("datetime")` devolve o epoch exato); o **tipo** não
  sobrevive, e isso é do formato (CSV não tem tipos; JSON não tem *date*) —
  registrado no CONTRATO 9. `test_csv` 130→138, `test_json` 43→47.
  Achados colaterais registrados: **12.25** (o reader não infere ISO — e o
  critério de inferência não tem critério) e **12.26** (zeros à esquerda
  destruídos: CEP/CNPJ/telefone).
  - Nota (E10, 2026-06-30): vírgula decimal BR não é bug — o CSV **suporta**
    `decimal=','` (o C troca por `.` em `try_f64`); ler `34,12` como string foi
    default `.`. Mesma natureza do E9 (12.10): default não-BR, não defeito.
    Documentar; conecta com 12.8 (fixtures BR).
- 12.4 **CONCLUÍDO (2026-07-14).** `from_codes` chamava `tostring(v)` 2× (içado
  para um local) e — achado durante o step — **não validava unicidade de níveis**:
  `{"a","a"}` ou `{1,"1"}` (colisão pós-normalização) sobrescreviam o `lmap`
  silenciosamente, corrompendo o categorical. Adicionado guard falha-visível
  (erro em nível duplicado após normalização). O path de dados já dedupe via
  `level_map`; o furo era exclusivo do `from_codes`. Lua puro.
- 12.5 **CONCLUÍDO (2026-07-14) — o registro estava errado.** Dizia
  "single-thread: sem bug". **Medido:** duas threads ordenando séries
  **diferentes** segfaultavam em **6/6 execuções** — a primeira a terminar
  zerava `g_sort_series` enquanto a outra ainda estava dentro do `qsort`.
  Não é ausência de bug; é **segfault garantido em qualquer uso multithread da
  API pública** (`smaug_str_argsort`/`sort`/`rank` são exportados). A
  justificativa — "o projeto não usa threads" — é a mesma classe de erro do
  CONTRATO 10: **confiar no caller**; o Smaug é biblioteca, quem usa decide.
  Agravante: eram os **únicos** globais mutáveis do Anel 0 — todo o resto já era
  reentrante (`f64_sort` em 2 threads: 400 sorts sem arranhão), o que fazia do
  caso uma armadilha sem aviso. **Decisão do Gui: o Smaug é thread-safe**
  (CONTRATO 11). Substituído por quicksort com contexto por parâmetro; mesmo
  teste que segfaultava agora roda 480 sorts em 2 threads limpo. Guardado pelo
  eixo de paridade **14** (audita estado global mutável; detector validado
  injetando um global). Alternativas descartadas com medição: `qsort_r` (3
  assinaturas por plataforma), `struct{ptr,len,idx}`+qsort (1.45x mais lenta,
  4x memória).
- 12.6 **CONCLUÍDO (2026-07-14) — o registro subestimava.** Dizia "assimetria;
  sem bug". Eram **3 padrões**, não 2: f64/i64 descartavam o status; str, dt e
  bool **alocavam out-param a cada get()** (`ffi.new` por chamada). Medido: o
  `get()` variava **50x** entre dtypes (f64 0.0018s vs string 0.0950s por 300k
  acessos) — ninguém sabia, e o item só mencionava o dt. **A raiz:** o Anel 1
  descartava o status e depois pagava uma segunda travessia FFI (`is_null`) para
  obter o que o getter já responde (`SMG_NULL_VALUE`). Corrigido: out-param
  reusado (upvalue) + o status detecta null → **1 travessia**. Ganho medido:
  string **12x**, bool **10.3x**, datetime **5.4x**, f64 1.4x, i64 1.1x — e os 5
  dtypes agora na mesma faixa. `get_raw` mantém o `is_null` explícito (devolve
  cdata cru, não passa pelo get_value).
- 12.7 **CONCLUÍDO (2026-07-14).** `test_constructors.lua` redeclarava
  `local n_ok`/`check` 4× (suites concatenadas) e só imprimia no fim → headline
  subcontava (98 vs 343 reais). Unificado num contador único (removidas as 3
  redeclarações; preâmbulos de seção intactos). Contagem real agora: 343. Lua
  puro, cobertura sempre foi real — só o número enganava.
- 12.8 **Fixtures de I/O órfãos + teatro de "dados reais"** (achado 2026-06-30).
  `tests/fixtures/` tem 5 arquivos; os testes em `tests/io/` abrem só 1
  (`pedidos_digitados.csv`, 917 linhas). Os outros 4 (`cotacoes.csv`,
  `cotacoes.json`, `cotacoes_SHIB_BRL.json`, `cotacoes_USD_BRL.json`) NÃO são
  lidos por nenhum teste — estão no repo decorativos. O parser em si é exercitado
  de verdade (por strings CSV/JSON embutidas nos .lua + o fixture de 917 linhas),
  então não há bug; o "falso" é o rótulo "dados reais" sugerir variedade que não
  é testada. Mesma família do 12.7 (número/aparência engana, validação é real).
  Ação: ou remover os 4 órfãos, ou — preferível — convertê-los em cobertura de
  **variedade real** com asserções específicas. Plano (Gui): separar tabelas
  abertas ≤1.000 linhas de fontes BR (IBGE/dados.gov.br: `;` separador + vírgula
  decimal) e ONU (UTF-8 acentuado, multi-idioma), cada fixture exercitando uma
  armadilha concreta: vírgula decimal → inferência float; data BR `dd/mm/aaaa` →
  o `dayfirst` (item F.3); aspas com vírgula interna; separador de milhar; linha
  malformada. **Invariante:** fixture sem asserção que o exercite é decoração —
  cada arquivo novo entra junto com os `check()` que justificam sua presença.
- 12.9 **CONCLUÍDO (2026-07-14).** A avaliação profunda mostrou que o `iat` era
  só o sintoma mais visível de uma classe: **mensagens de erro interpolavam
  `tostring()` de argumento do usuário**, disparando o `__tostring` do objeto e
  despejando DADOS na mensagem. Medido: os 5 métodos de acesso
  (`get`/`get_raw`/`set`/`is_null`/`set_null`) vazavam igual, e um DataSet 20x1000
  como índice gerava **2459 chars** de erro com o conteúdo das colunas; 8 outros
  pontos (`view`/`take`/`astype`/`str:pad`/`str:rep`/`cat:get`/`cat:take`/
  `Series.new`) idem. Criado `core/errors.lua` (fonte única de descrição segura,
  espelhando o padrão do `display.lua`): objetos viram
  `<Series 'x' (int64, len=200)>`, strings truncam em 60 chars, nada de conteúdo.
  Religados todos os pontos de risco; `SeriesAt.__call` agora detecta a
  chamada-método e orienta "use s.iat[i]". Pós-fix: 2459 → 109 chars. A forma
  `s.at(i)`/`s.iat(i)` (chamada com número) segue suportada — contrato testado
  preservado.
- 12.10 **CONCLUÍDO (2026-07-14).** Aviso passivo implementado conforme a
  decisão registrada (não adivinha separador; só ilumina). Dispara quando
  `ncols==1` **e** o separador suspeito (`;`, `\t`, `|`) aparece em TODAS as
  amostras (header + até 5 valores) — a regra "todas" evita o falso-positivo de
  um `;` solto em texto livre. Hook nos pontos de entrada do CSV
  (`M.read`/`M.read_mem`), **não** no `table_to_dataset`: aquele é compartilhado
  com o `json.lua`, e "verifique o separador" não faz sentido para JSON
  (verificado: `read_json` fica silencioso). Requereu promover o `warn` a módulo
  (`core/warn.lua`) — era `local` no `series/init.lua` e não alcançava o Anel 3;
  escrever um segundo `io.stderr` ali criaria dois canais divergentes, contra o
  "canal único" que o próprio comentário declarava.
- 12.11 **`Series:nrows()` — NÃO FAZER (decisão 2026-07-14).** A leitura do
  código mostrou que o "gap" contradiz uma convenção deliberada: o eixo 08
  registra "Series tem len+size (size = alias de len); DataSet tem nrows+ncols" —
  `nrows` é vocabulário tabular (uma Series não tem linhas, tem elementos),
  `len`/`size` é vocabulário de sequência. Não é ausência, é separação de
  domínio. Pandas faz igual: `Series` não tem `nrows` (é `DataFrame.shape[0]`).
  Adicionar o alias violaria a convenção que o próprio parity audita. Sub-item
  encerrado sem código.
- 12.12 **CONCLUÍDO (2026-07-14).** `Err.suggest`/`Err.unknown_key` em
  `core/errors.lua` (Levenshtein com early-exit, tolerância proporcional ao
  tamanho, normalizando `_`/caixa — pega `group_by`/`groupBy`/`GROUPBY` →
  `groupby`). Plugado nos dois `__index`. **Mudança de contrato deliberada:**
  chave desconhecida agora ERRA em vez de devolver `nil` silencioso —
  `df.vendass` (typo de coluna) falha na hora, não 3 linhas depois. Verificado
  antes: nada no código nem nos testes dependia do `nil` (430 checks das suites
  DataSet passaram com o erro ativo, antes de qualquer teste novo); `has_column`
  não é afetado (lê `self._columns` direto, sem passar pelo `__index`). Chaves
  com `_` seguem devolvendo `nil` (campos internos). No DataSet os candidatos
  incluem as colunas reais, então typo de coluna sugere a coluna.
- 12.13 **documentação prometida pelo 9.1 incompleta** — [Windows]. A limitação
  do `get()` (`tonumber`, perda > 2^53) e a faixa correta `get_raw` estão
  registradas só no API_INDEX; API_Reference e CONTRACT silenciosos. Completar,
  incluindo a herança nos consumidores do `get()` — em especial `map` (a função
  do usuário recebe double, série armazenada intacta).
- 12.14 **`GroupBy:quantile` duplica a interpolação canônica** — [Windows]
  (achado 2026-07-05). `_relational.lua:551` reimplementa linha a linha a
  fórmula de `I.quantile_sorted` (`stats/_stat.lua:93-102`, já exposta em `I`)
  em vez de delegar. Se a regra de interpolação mudar num lugar, diverge. De
  quebra: `col:get(i)` em loop + `table.sort` em Lua (element-wise no Anel 1).
  Delegar a `I.quantile_sorted`.
- 12.15 **CONCLUÍDO (2026-07-23).** [Windows] `CategoricalSeries` aceitava índice
  não-inteiro em silêncio — `get(1.5)` devolvia `nil` calado, onde `Series:get(1.5)`
  erra (viola falha-visível). O guard (`categorical/_categorical.lua`) checava tipo
  e faixa mas faltava `i % 1 ~= 0`. E estava copiado em **4** pontos (o achado dizia
  3): `get`/`is_null`/`set`/`set_null`. Extraído para o helper único
  `check_cat_index`, espelhando o `I.check_index` canônico da Series — não dá para
  reusar o da Series diretamente porque o categorical é Lua puro (`_size`, sem `_c`),
  mas a regra é a mesma. Corrige o bug e mata a duplicação de uma vez. +12 guards em
  `test_categorical` (299→311): os 4 pontos rejeitam fracionário, paridade com
  Series, caminho normal (inteiro válido, faixa, tipo) intacto. Lua puro.
- 12.16 **`fillna` de datetime aceitar string ISO** — [Windows] (registrado
  2026-07-07, futuro próximo). O `check_value` de datetime já aceita `number`
  (epoch_ms) **ou** string ISO 8601, como `set`/`append`. Mas o `fillna` de
  datetime aceita só `number` — na integração ao `coalesce_scalar` (Anel 0) o
  `dt` ficou restrito a `number` para não ampliar escopo. Alinhar: aceitar string
  ISO no `fillna` de datetime, parseando via `dt_parse` antes de delegar —
  uniformiza `fillna` com `set`/`append`.
- 12.17 **`dt_coalesce_scalar` guards sem `COV-EXCL-BR`** — [CONCLUÍDO
  2026-07-09]. Os guards `if (!self)` (datetime:219) e
  `if (!r)` (datetime:222) receberam `COV-EXCL-BR` com a justificativa canônica
  dos irmãos i64/f64/str. **Selo Fedora obtido (2026-07-09):** Valgrind 12/12
  clean, branch-alvo 94.49% (mudança só de comentário, sem alteração funcional).
 - 12.18 **CONCLUÍDO (2026-07-14) — invertido após revisão.** O item pedia
   `COV-EXCL-BR` nos guards; a revisão mostrou que os 3 ramos são **alcançáveis e
   testáveis**, e que o `smaug_core.c` fecha **100%** de branch-alvo justamente
   por testá-los (o `f64_get` tem estrutura idêntica ao `dt_get`). Excluí-los
   esconderia ramo vivo. Feito o oposto: 3 testes
   (`dt_set_null(NULL)`, `dt_append_null(NULL)`, `dt_get(NULL,&st)` — este exercita
   o `if (status)` DENTRO do `if (!s)`, que era o ramo real descoberto).
   Branch-alvo 94.70% → **94.77%** com as mesmas 165 exclusões. Excluir daria o
   mesmo 94.77% com 168 exclusões e zero proteção. Política registrada no
   **CONTRATO 10**.
 - 12.23 **CONCLUÍDO (2026-07-14).** Os 6 guards essenciais (auditados: sem eles,
   SIGSEGV) agora têm teste e saíram da exclusão. `dt_clone`, `dt_coalesce`
   (test_datetime_c 450→456), `f64_coalesce`, `i64_coalesce` (test_ops_edge
   272→280), `str_coalesce_scalar`, `str_coalesce` (test_string 118→126).
   Cobertos **todos os ramos**, não só o NULL: os três do `||` (self, other,
   size divergente) e o `!value && len>0` do str. **16 exclusões removidas**
   (164→148) — cada `||` conta 3 ramos. Branch-alvo inalterado (94.66%), mas o
   **bruto subiu de 91.13% para 91.47%**: o alvo não distingue esconder de
   cobrir, o bruto só sobe quando se cobre — é a métrica honesta.
   **Verificado:** deletar um guard agora QUEBRA a suíte (SIGSEGV no teste);
   antes dava "TUDO PASSOU" com a métrica intacta.
 - 12.25 **`read_csv` não infere ISO 8601 — e o critério de inferência não tem
   critério** — [achado 2026-07-14, durante o 12.3]. Medido: o CSV **já infere**
   3 dtypes (`try_bool` → `try_i64` → `try_f64` → `DT_STR`, csv:296-299). O que
   ele recusa (`2024-03-15`) é o **único não-ambíguo** dos casos — ISO 8601 é
   não-ambíguo por design; `03/04/2024` (mar ou abr?) é que não deveria ser
   inferido, e corretamente não é. Consequência: **o Smaug escreve ISO e não lê
   de volta** — `to_csv` de datetime produz `2024-03-15T00:00:00.000Z`, e o
   `read_csv` devolve string. Mesmo critério que classificou o JSON como bug no
   12.21 ("o Smaug não lê o que o Smaug escreve"), aqui em tipo, não em valor
   (o `astype("datetime")` recupera — round-trip de valor testado, preserva).
   `smaug_dt_parse` já existe no Anel 0. Decidir: inferir só ISO (fecha o
   round-trip, risco baixo) ou `parse_dates` opt-in (estilo pandas / `na_values`
   do 12.21). **Muda contrato público do reader** — precisa de design próprio.
 - 12.26 **zeros à esquerda destruídos na inferência — CEP, CNPJ, telefone** —
   [achado 2026-07-14, durante o 12.3]. **Prioridade alta: perda silenciosa de
   dado, em dados BR (o alvo do projeto).** Medido:

   | coluna | CSV | vira |
   |---|---|---|
   | CEP | `01310100` | `1310100` |
   | CNPJ | `00000000000191` | `191` |
   | telefone | `011999998888` | `11999998888` |

   O `try_i64` aceita zeros à esquerda e o dtype vira int64 — o identificador
   deixa de ser identificador. E o round-trip do próprio Smaug quebra: escrever
   a string `"01310100"` e ler de volta devolve `1310100` (int64). Não há aviso.
   É mais grave que o 12.25: ali se perde o *tipo* (recuperável via astype); aqui
   se perde o *dado*. Conecta com 12.8 (fixtures BR: IBGE/dados.gov.br têm CEP e
   código de município). Decidir: `try_i64` recusar zeros à esquerda (`"007"` vira
   string, `"7"` continua int) — coerente com "falha visível > acerto adivinhado",
   já que hoje adivinha errado; ou `dtype=` explícito por coluna. Verificar antes
   se algum teste/fixture depende do comportamento atual.
 - 12.24 **CONCLUÍDO (2026-07-14) — o item estava errado, e o erro era meu.**
   A reauditoria (pedida como review pré-código) mostrou que **4 dos 7 são
   ESSENCIAIS**, não redundantes: `dt/f64/i64/str_select` **segfaultam** sem o
   guard. A auditoria original os classificou mal porque o script removia só a
   primeira linha do guard (`if (...)`), deixando o `return NULL;` órfão executar
   sempre — a função virava `return NULL` incondicional e não crashava. Artefato
   do harness. **Não eram 6 guards essenciais, eram 10**; os 4 escaparam do 12.23
   por erro de medição. Feito: os 4 `select` viraram teste cobrindo os **5 ramos**
   do `||` (`!cond`/`!a`/`!b`/2× size) + controle positivo — `test_ops_edge`
   280→292, `test_datetime_c` 456→462, `test_string` 126→132; **20 exclusões
   removidas** (148→128). Os 3 `coalesce_scalar` **são** redundantes (confirmado:
   o `clone(NULL)` barra) e mantêm a exclusão, agora com justificativa
   verdadeira. A frase "o frontend valida antes" **sumiu do Anel 0**.
   Bruto 91.49% → **91.93%**; linha 98.71% → **98.81%**.
 - 12.19 **PARCIAL (2026-07-20) — metade SRCS concluída; C_TESTS registrado.**
   [achado 2026-07-09, Fase 1 do 10.7]. Eram 5 listas duplicadas; o levantamento
   mostrou que têm **duas naturezas**:
   - **SRCS (fontes C) — RESOLVIDO.** As 3 cópias viram descoberta automática:
     `build.sh` já era glob (12.29); agora `Makefile` usa `$(wildcard src/*.c)` e
     `make_coverage.sh` deriva por glob + basename (`src/X.c → X`). Mata o risco
     central do achado — esquecer a de coverage deixava o build **verde** com o
     `.c` novo reportando 0% e fora do selo. Provado: um `.c` novo é pego pelos
     três sem editar lista. (Restava só `build.sh:SRCS` no 12.29; agora as 3.)
   - **C_TESTS (test binaries) — REGISTRADO, não derivável por glob puro.** As 2
     cópias (`build.sh:C_TESTS_PLAIN`, `make_coverage.sh:C_TESTS`) têm
     categorização **semântica**: `test_allocfail` exige `-Wl,--wrap`, `test_stress`
     é categoria à parte. Um glob de `tests/c/*.c` pegaria os 13 mas quebraria a
     compilação especial. Unificar exigiria um manifesto que preserve categorias
     (mais invasivo). Menos perigoso que a de coverage: esquecer um teste aqui
     apenas não o roda (visível no contador de checks), não mente sobre cobertura.
     Candidato a fazer junto do item 10, quando `.c`/testes novos entrarem.
 - 12.20 **CONCLUÍDO (2026-07-21) — eixo 03 ampliado em 4 frentes.** [Windows]
   O achado original citava só `astype.h`/`convert.h`; a revisão profunda do
   Anel 0 (pedida antes de tocar em código, "nunca supor") mostrou que a lacuna
   era maior — o eixo tinha 3 problemas adicionais que ninguém tinha registrado.
   Escopo final, 4 frentes:
   - **Frente 1 — `smaug_ops_window.h` ausente.** As 16 funções de rolling
     (`smaug_{f64,i64}_rolling_*`) nunca entravam na composição de headers do
     eixo — encaixam perfeitamente no padrão existente (`smaug_{dtype}_{sufixo}`).
     Adicionado; resultado 🟩 direto (usadas via `_types.lua`/`_d.rolling_*`).
   - **Frente 2 — falso-negativo estrutural em `bool` (achado da revisão, não
     do texto original).** Rodando o eixo antes de mexer, a taxa de 🟨 em bool
     era 47% (9/19) — muito acima dos outros dtypes (4–6%). Causa: as funções
     que o Lua REALMENTE usa (`smaug_bool_series_and/or/xor/count_true/any/all`)
     vivem em `smaug_numeric.h`, não em `smaug_bool.h` — a composição de
     `headers.bool` não incluía `hdr_numeric`, então nem eram buscadas (sumiam
     do relatório, não apareciam nem 🟩 nem 🟨). As de `smaug_bool.h` sem
     `_series_` são primitivas cruas de uso interno (arrays, não Series) —
     corretamente sem caminho Lua direto. Corrigido incluindo `hdr_numeric` na
     composição de bool: 19→42 funções auditadas, taxa de 🟨 cai para 21%
     (9/42) — e os 9 que sobram são exatamente as primitivas cruas esperadas.
   - **Frente 3 — `astype.h`, matriz origem×destino (o achado original).** As 12
     funções (`smaug_{origem}_to_{destino}`) não cabem no padrão "1 dtype +
     sufixo" — carregam DOIS dtypes no nome. Encaixá-las na tabela por-dtype
     confundiria ("função to_f64 do dtype i64"). Seção própria: matriz
     origem→destino, extrator dedicado (`gmatch` do padrão `_to_`). 12/12 🟩
     (usadas de fato em `_transform.lua`, confirmado).
   - **Frente 4 — `convert.h`, fora de escopo por natureza (decisão, não
     lacuna).** As 6 funções (`parse_i64/f64`, `fmt_i64/f64` + variantes _cstr)
     são infraestrutura interna entre `.c` files — zero ocorrências no cdef,
     nunca expostas ao Lua por design. Incluí-las marcaria 🟨 PERMANENTE — ruído,
     não achado. Registrada como nota textual no cabeçalho do eixo, não como
     seção/tabela.
   Cobertura total do eixo: 209→258 funções auditadas (+49), zero ruído novo.
   Vínculo: a revisão profunda também achou o 12.30 (contrato de erro de escrita
   em I/O nunca implementado) — registrado à parte, não é do eixo 03.
 - 12.21 **CONCLUÍDO (2026-07-14).** O registro mirava o JSON; a revisão do Ring
   0 (pedida pelo Gui) mostrou que o problema era o **vocabulário de não-finitos
   como um todo**, sem regra: `smaug_convert.c` escrevia `"nan"` como valor
   enquanto `smaug_csv.c:72` o listava como sentinela de ausência (contratos
   contraditórios), e o destino do dado dependia da **caixa** (`nan`/`NaN` →
   ausência; `NAN` escapava para o `strtod` → valor). Fechado com uma regra
   única, registrada no **CONTRATO 9**: não-finito é valor, ausência é
   `null_mask`; cada formato preserva se comportar, senão converte **e avisa**.
   Entregue: `BUILTIN_NA` sem `"nan"`/`"NaN"` (round-trip CSV agora fiel);
   `!isfinite` no writer JSON; `smaug_f64_count_nonfinite` (Anel 0) alimentando
   o `warn` do Anel 3; e `na_values` **implementado** no frontend Lua — era
   documentado desde sempre e nunca existiu (o C tinha os campos, o Lua não os
   populava), o que tornaria a mudança uma remoção de capacidade sem alternativa.
 - 12.22 **CONCLUÍDO (2026-07-14).** Contador unificado nas 9 suites, mesmo fix
   do 12.7. Verificado antes: as cópias são idênticas dentro de cada arquivo,
   todas as declarações são top-level (nenhuma aninhada em `do...end`) e há um
   único `print` por arquivo — condições que tornam a remoção segura e uniforme.
   Ganhos: `test_str` 66→272, `test_categorical` 97→299, `test_relational`
   60→168, `test_predicates` 89→167, `test_access` 61→127, `test_csv` 64→107.
   Em `test_selection`/`test_reduce`/`test_window` o número não mudou (a 2ª
   declaração estava no preâmbulo, não no meio: quase todos os checks já
   contavam) — a remoção só tirou a redundância. Nenhum check novo: a validação
   sempre foi real, só o relato subcontava.
 - 12.27 **CONCLUÍDO (2026-07-20) — OOM parcial em `dataset_to_table`.** [Windows]
   `dataset_to_table` (`io/csv.lua`) alocava, por coluna, o nome (`ffi.C.malloc`)
   e a série C (`smaug_*_create`) num laço; um OOM no meio (create → nil →
   `error`) deixava o parcial vazando, porque `t` nunca chegava ao caller para ser
   liberado. Afetava `to_csv` e `to_json` (o json reusa `_dataset_to_table`).
   - **Correção:** o laço de construção passou a rodar dentro de um `pcall`; em
     falha, `free_table_lua(t, ncols)` libera o que já foi alocado e o erro
     original é repropagado (`error(err, 0)`). Funcionou porque `free_table_lua`
     já era seguro sobre tabela parcial — o `ffi.fill(columns, 0)` zera tudo e o
     free pula campos nil (cada série só é atribuída após criação bem-sucedida).
     `free_table_lua` foi promovida a forward declaration (é usada por
     `dataset_to_table`, que vem antes dela no arquivo).
   - **Uma correção cobre os dois I/O** — está no ponto compartilhado, então
     `to_json` herda (confirmado).
   - **Provado:** injetando falha no `:get` da 2ª coluna (após a 1ª já alocada), o
     erro é capturado, o parcial liberado (sem crash → free rodou) e o erro
     repropagado; heap íntegro depois. Guard permanente em `test_csv` (+3).
 - 12.28 **CONCLUÍDO (2026-07-20) — eixo `15_abi_layout`.** [Windows] O `cdef` do
   `ffi_loader.lua` replicava à mão o layout das structs sem verificação: um
   esquecimento (campo renomeado/reordenado/tipo trocado) não quebrava o build,
   virava leitura de memória deslocada. Novo eixo de paridade compara a sequência
   (tipo, nome) dos campos entre header e cdef para as 10 structs que cruzam a
   fronteira por layout (opacas como `smaug_hash_table_t` ficam de fora).
   - **Decisão de desenho (verificada, não presumida):** a ideia inicial era
     cruzar `ffi.offsetof` (cdef) com offsets que o C imprime — mas isso exigiria
     ponte C→Lua via `io.popen` (sem precedente no projeto, frágil). A verificação
     mostrou que **não há packing custom** (nenhum `#pragma pack`/`packed`/
     `aligned` nos headers nem no cdef) — logo C e LuaJIT-FFI usam o mesmo
     alinhamento, e sequência textual idêntica de (tipo, nome) ⟹ layout idêntico
     (confirmado empiricamente: sizeof/offsetof batem byte a byte). Comparação
     textual passou a bastar, sem a ponte frágil. **Salvaguarda:** o eixo checa a
     ausência de packing a cada run — se algum dia entrar, ele falha avisando que
     a comparação textual deixou de valer.
   - Resolve typedefs antes de comparar (`smaug_mask_t` ≡ `uint8_t`) para não dar
     falso positivo. Testado nos dois sentidos: pega divergência (renomeei um
     campo → 🟥, exit 1) e passa sincronizado (exit 0). Registrado nos dois
     runners (`parity.sh` e `parity.ps1`). Parity 14→15 eixos.
   - **Achado colateral (registrado, não corrigido aqui):** o cdef usa
     `smaug_mask_t *null_mask` em 4 structs mas `uint8_t *null_mask` no
     `series_dt` — inconsistência de estilo, inofensiva em layout (mesmo tipo).
     Uniformizar para `smaug_mask_t` fecharia. Candidato a limpeza futura.
 - 12.29 **CONCLUÍDO (2026-07-20) — descoberta automática de fontes C.** [Windows]
   O `14_thread_safety.lua` iterava uma lista fixa de `src/*.c` e não detectava um
   `.c` novo não-listado (falha em silêncio). O levantamento mostrou que o A3 era
   mais amplo: **três** listas de fontes, duas hardcoded só no Linux —
   `build.sh` (`SRCS`) e o eixo 14 — enquanto o `build_win.ps1` já descobre via
   glob. A do `build.sh` era até mais grave (um `.c` novo nem compilava no Linux).
   Escopo completo (decisão de alinhar Linux ao Windows):
   - **`build.sh`:** `SRCS` vira `src/*.c` (glob do bash, ordenado). Grava a lista
     descoberta em `build/SOURCES` (uma path por linha) logo após criar `build/`.
   - **`build_win.ps1`:** já fazia glob; passou a gravar o mesmo `build/SOURCES`,
     normalizado para forward slash (formato único nos dois OS).
   - **Eixo 14:** sem lista hardcoded. Lê `build/SOURCES` (lista fresca do build,
     sem defasagem); fallback ao `MANIFEST.txt` (versionado) quando rodado
     standalone; se nenhum der lista, **falha visível** (não audita vazio).
   - **Achado corrigido junto:** o eixo 14 detectava global mutável (🟥) mas
     retornava exit 0 — nunca destacava no runner. Agora faz `os.exit(1)` se há
     global (alinhado ao eixo 15). Não quebra o build (parity sempre `exit 0`),
     só marca FALHOU no relatório — o comportamento certo para um achado real.
   Provado: `.c` novo com global mutável passou a ser detectado (🟥, exit 1);
   removido, volta verde. `build/SOURCES` é gitignored (efêmero).
 - 12.30 **PARCIAL — Fase 1 concluída (2026-07-21). Contrato de erro de escrita
   em I/O.** [Fase 1: Fedora] `smaug_io.h` promete no cabeçalho:
   "toda função que escreve retorna 0/-1 (checar `smaug_io_last_error()`)". Essa
   função **não existe** — nem protótipo, nem definição, nem cdef — em lugar
   nenhum do projeto (confirmado por leitura completa de `smaug_io.h` e
   `smaug_io_internal.h`).
   - **A assimetria é real e específica, não geral.** O lado de LEITURA está bem
     construído: `make_error()` (`smaug_io_internal.h`) aloca a `smaug_table_t`
     com `->error = strdup(msg)`, tratado até no caso raro de falha do próprio
     `strdup` (não deixa `error` NULL por acidente — o caller leria como
     sucesso). Usado consistentemente em TODOS os pontos de falha de
     `smaug_read_csv_mem`/`smaug_read_json_mem` (separador=decimal, entrada
     vazia, sem colunas, "não foi possível abrir", OOM em vários pontos) — sem
     lacuna, li os dois parsers inteiros.
   - **O lado de ESCRITA descarta a causa que já tinha em mãos.** Li
     `smaug_write_csv` (csv.c) e `smaug_write_json` (json.c) por inteiro: os dois
     têm a MESMA estrutura — `fopen(path,"wb")` falha → `free(buf); return -1` —
     sem checar `errno` (que já contém a causa exata: permissão negada, diretório
     inexistente, etc.) e sem diferenciar de uma falha de `fwrite` parcial (disco
     cheio no meio). A assinatura retorna só `int`, sem onde guardar mensagem.
   - **Por que importa:** o Lua repassa isso como `"to_csv — falha ao escrever
     'path'"` — genérico, igual para qualquer causa. Na leitura, o mesmo tipo de
     falha (`fopen` de path inválido) já diz exatamente por quê. Viola em parte
     "falha visível": a falha é visível, a causa não.
   - **Correção — Opção B (canal de erro no C, espelhando `make_error`).**
     Descartadas: (A) resolver no Lua duplicaria a checagem `sep==decimal` que já
     existe no C — fere "fonte única"; (C) implementar o `last_error()` global do
     header exigiria `static` mutável — violaria a thread-safety do Anel 0 (o
     eixo 14 pegaria como 🟥). A Opção B adiciona `char **err_out` às funções de
     escrita, que recebe `strdup` da causa (heap da DLL → Lua libera com
     `smaug_free`, respeitando o heap separado no Windows). Helper
     `set_io_error()` em `smaug_io_internal.h`, ao lado do `make_error`.
   - **Faseado (~45 call-sites, 33 em testes C; selo Fedora por ser C):**
     - **Fase 1 — CONCLUÍDA (2026-07-21):** as 2 variantes `_mem`
       (`smaug_write_csv_mem`/`smaug_write_json_mem`) — o bug mais grave: o NULL
       colapsava OOM com `sep==decimal`, e o Lua repassava "OOM" (mensagem
       factualmente errada). Agora err_out carrega a causa; o teste `sep==decimal`
       em `test_io_c` verifica a mensagem (espelha o que o read já fazia via
       `t->error`); guard Lua em `test_csv` (to_csv_mem não diz mais OOM);
       allocfail cobre o `strdup` do set_io_error sob OOM. Contadores: test_io_c
       312→315, test_csv 141→144, allocfail 1874→1878. Chamadas internas
       `write→write_mem` passam err_out=NULL por ora.
     - **Fase 2 — PENDENTE:** as 2 funções de arquivo (`smaug_write_csv`/
       `smaug_write_json`), que hoje descartam `errno` do `fopen`/`fwrite`. Darão
       err_out próprio e propagarão a causa da serialização + a de sistema
       (`strerror(errno)`). Atualizar os 2 call-sites Lua (`M.write`) e os testes
       C de path inválido (`test_io_c:719`/`:908`). Mesmo padrão da Fase 1.
 - 12.32 **Dois geradores de MANIFEST divergentes + ausência de procedência** —
   **[Windows PENDENTE · Fedora PENDENTE]** (scripts; sem C, sem Lua).
   Achado no checkup de doc (2026-07-27).
   - **Problema A — duas implementações que divergiam em seis eixos.**
     `make_manifest.sh` e `make_manifest.ps1` eram independentes e produziam
     arquivos diferentes para a MESMA árvore: separador de caminho
     (`./docs/x.md` vs `.\docs\x.md`), BOM (o `.ps1` gravava), fim de linha
     (LF vs CRLF), texto do cabeçalho (cada um nomeava a si mesmo, então nunca
     bateriam), critério de ordenação (`LC_ALL=C sort` sobre caminho relativo vs
     `Sort-Object FullName` sobre caminho absoluto) e contagem de linhas
     (`wc -l` conta quebras; `(Get-Content).Count` conta linhas — discordam em
     arquivo sem quebra final). Consequência: o MANIFEST é versionado, então
     trocar de plataforma reescrevia as 126 linhas (diff-fantasma no histórico),
     e comparar integridade **entre máquinas** — a razão de existir do arquivo —
     era impossível porque nenhuma linha batia.
   - **Decisão: fonte única por construção.** Fazer duas implementações
     concordarem exigiria mantê-las em sincronia para sempre. O `.ps1` virou
     **wrapper fino** que delega ao `.sh` via bash do MSYS2 — que já é requisito
     do fluxo Windows (gcc e luajit vêm dele), então não acrescenta dependência.
     Divergência deixa de ser possível, em vez de depender de vigilância.
   - **Problema B — o MANIFEST não dizia QUAL árvore ele descreve.** Hash de
     arquivo prova consistência interna, não atualidade: um MANIFEST antigo
     valida limpo contra a própria árvore antiga. Em 2026-07-27 um zip da
     máquina Windows (atrás do Fedora) passou na verificação de integridade sem
     levantar suspeita — o formato unificado **não** teria pego isso, só a
     procedência pega. Cabeçalho ganhou `# Arvore: <commit curto>`, com
     `+ alteracoes nao commitadas` quando o working tree está sujo, e `sem git`
     fora de repositório (degrada com elegância).
   - **Consumidores verificados antes de mexer:** `parity/14_thread_safety`
     (fallback que lê o MANIFEST com `%./(src/[%w_]+%.c)` — não colide com a
     linha nova) e `make verify` (só regenera e faz `git diff`). Ambos intactos.
   - **Efeito colateral aceito:** em árvore suja, `make verify` passa a mostrar
     também a linha de procedência mudando. É informação correta, não ruído — a
     árvore está suja mesmo.
   - **Achado na primeira execução real (2026-07-27), que o teste teria pego.**
     O wrapper falhou no Windows com `sha256sum: command not found`. Causa: achar
     o bash não basta. As coreutils que o `.sh` usa ficam em
     `C:\msys64\usr\bin`, enquanto o `build_win.ps1` põe no PATH apenas
     `C:\msys64\ucrt64\bin` (gcc e luajit) — e bash **não-interativo não lê
     `/etc/profile`**, então herda o PATH do Windows sem as ferramentas. O
     wrapper passou a garantir o diretório das coreutils no PATH.
   - **Falha secundária que a primeira expôs — truncamento.** O `.sh` escrevia
     direto no arquivo final (`{ ... } > "$out"`), então o redirecionamento
     truncava o MANIFEST **antes** de a falha acontecer: sobrava só o cabeçalho,
     o arquivo válido anterior era destruído, e o resultado *parecia* bom
     (cabeçalho certo, formato certo) mas omitia arquivos. Como a verificação só
     confere o que está listado, omissão não seria detectada — uma falha
     barulhenta virava silenciosa. Corrigido com **verificação prévia** das
     ferramentas (erro claro antes de tocar no arquivo) e **escrita atômica**
     (monta em temporário, `mv` só no sucesso, `trap` limpa o lixo).
   - **Verificação:** o `.sh` foi testado em cinco cenários — fora de git, repo
     limpo, repo sujo, ferramenta ausente (erro claro, arquivo intacto) e falha
     no meio da execução (arquivo preservado byte a byte, sem temporário órfão).
     O `.ps1` **não pôde ser testado** (sem PowerShell no ambiente de
     desenvolvimento); a primeira correção veio da execução real no Windows e
     precisa de nova rodada para confirmar.
 - 12.31 **Inferência de tipos incompatíveis gerava container natimorto** —
   **[Windows OK 2026-07-27 · selo Fedora PENDENTE]** (Lua puro; equivalência).
   Achado durante a reescrita do Contrato 1 (2026-07-24), corrigido em 27/07.
   `infer_dtype` (`_factories.lua`, Bloco H) decide o dtype de uma tabela Lua por
   **rank** (`bool` > `string` > `float64` > `int64`). O rank foi pensado para o
   caso numérico — `{1, 2.5}` → `float64` é promoção segura (int→float, Contrato 1)
   e deve permanecer. Mas em tipos `type()`-incompatíveis ele infere o de maior
   rank e o `set`/`check_value` seguinte **rejeita os valores dos outros tipos** —
   a construção quebra com mensagem que fala do `set`, não da inferência.
   - **Provado (2026-07-24):** `from_table({1, "x"})` infere `string` → `set(número)`
     → *"valor para string deve ser uma string Lua; recebido number"* (o usuário
     passou `{1,"x"}`, não pediu string — mensagem enganosa). `from_table({true, 1})`
     infere `bool` → mesmo desfecho. Afeta `from_table`, `DataSet.__call` e
     `Series.full` (todos via `infer_dtype`). **`map` está fora** — já falha
     visível por caminho próprio (`check_map_value`: "tipo inconsistente no
     índice N").
   - **Enquadramento (Contrato 1 novo).** Promoção segura existe só dentro do
     numérico (int→float não perde informação). Tipos cross-família (número+string,
     bool+número) **não têm supertipo seguro** — forçar `string` via rank é
     exatamente a *adivinhação de semântica* que o Contrato 1 recusa (inferir que
     o número "vira texto"). Hoje a inferência adivinha e a validação desmente:
     as duas discordam entre si.
   - **Decisão (2026-07-24):** mistura incompatível → **erro claro na inferência**,
     nomeando os tipos presentes e pedindo dtype explícito, ANTES de construir.
     Não cair em `string` via `tostring` (seria a adivinhação). A promoção
     numérica (`int`+`float` → `float`) permanece intacta — é o único widening
     seguro.
   - **Escopo:** `infer_dtype`/`infer_dtype_from_value` (`_factories.lua`, Bloco H,
     fonte única). Anel 1, Lua puro → equivalência Fedora. Guard permanente:
     mistura incompatível erra na inferência; `{1,2.5}` → float64 e casos
     homogêneos intactos.
   - **Implementação (2026-07-27) — famílias substituem o rank.** O `DTYPE_RANK`
     (bool>string>float64>int64) saiu. Entrou `DTYPE_FAMILY`: `int64` e `float64`
     são a **mesma** família (int→float é promoção segura, Contrato 1); `string` e
     `bool` são famílias próprias. Dentro do numérico o rank sobrevive
     (`NUMERIC_RANK`, fracionário vence); entre famílias, erro. O erro nomeia os
     **dois dtypes e as duas posições** — sem isso o usuário procuraria o problema
     no lugar errado, que era justamente a falha da mensagem antiga (falava de um
     dtype que ele nunca pediu).
   - **Raio de alcance verificado:** `infer_dtype` é chamada só por
     `Series.from_table`; o DataSet passa por ela; o **CSV não usa** (tem
     inferência de texto própria — 12.25/12.26). `infer_dtype_from_value` segue
     intacta e é usada também pelo `map`, que tem validação própria.
   - **`level` medido, não estimado:** 4, porque `Series.from_table` é
     **sobrescrita** no `init.lua` (intercepção de categorical) e o wrapper
     adiciona um frame. Com 3 o erro não apontava a linha do usuário.
   - Testes: `test_constructors` 12.31.1-12.31.6 (promoção numérica intacta e
     independente de ordem, famílias homogêneas, quatro misturas recusadas,
     conteúdo da mensagem, dtype explícito ignorando a inferência, superfície
     `smaug.Series`). +18 checks (363 → 381). **Mutação verificada:** fundir as
     famílias faz o teste abortar.
   - **Vínculo:** Contrato 1 (reescrito 2026-07-24); item 12.3 (inferência de
     tipos, concluído). Distinto de 12.25/12.26 (inferência de **texto** no CSV —
     parsing, não rank de tabela Lua).
## 13. Reescrita de exemplos + docstrings  [Windows]

Doc reflete a API depois que ela para de mudar (itens 1–12).

- 13.1 exemplos README/API_INDEX → forma oficial `smaug.Series({...})`
- 13.2 docstrings nos métodos públicos de Series e DataSet

## 14. REVISÃO FINAL (penúltimo)  [Fedora]

O teste de que a campanha de coerência fechou. Se achar 🟥 novo, volta pra timeline.

- 14.1 reauditar os 4 anéis com as mesmas lentes (completude, invariantes,
  coerência interna, ergonomia, paridade)
- 14.2 limpar e reconciliar `exceptions.txt` do parity
- 14.3 Fedora: parity 12/12 + Valgrind + cobertura + allocfail
- 14.4 a timeline zera somente se 14.1 não achar inconsistência nova

## 15. RELEASE v1.0 (último)  [Windows+Fedora]

- 15.1 FFI loader instalável (descobre `.so`/`.dll`/`.dylib` em layout instalado)
- 15.2 distribuição / LuaRocks
- 15.3 LDoc + GitHub Pages
- 15.4 tag v1.0.0

---

# Pós-v1.0 — trilhas paralelas (fora desta timeline)

- **Versão em inglês** — documentação, mensagens de erro e i18n. Trilha própria;
  mensagens de erro são API, mas a internacionalização completa é projeto à parte.
- **Trilha Analítica** — Matrix → Tensor → ML.
- **Trilha Projeto** — I/O estendido (SQL, Excel, Parquet) → Persistência → Models.
- **Frentes diferidas** — `replace({de=para})`, índice/MultiIndex, plotting,
  tipos extras (float32, int32/16/8). Só se caso real justificar.
  (`sum(min_count)` subiu para a timeline, item 5.5.)

---

# Apêndice — histórico entregue

> Detalhe das fases e blocos já concluídos. Preservado para rastreabilidade; não
> faz parte da timeline ativa. Números frágeis (contagens, cobertura) vivem em
> `COVERAGE.md`/`MANIFEST.txt`/`build.sh`, não aqui.

- **Fases 1–5** — inventário arquitetural, decisões de fundação (Bloco G),
  migração de primitivas para Ring 0, split dos arquivos-deus, hardening global
  (Valgrind, cobertura, allocfail).
- **Bloco H** — coerência de API e convenções de entrada: separador de data `/`,
  decimal CSV configurável (BR), validação `sep==decimal`, `dayfirst` completo.
- **Bloco I** — fechamento de coerência pré-auditoria: docs sync, Ring 0 fixes
  (rank i64, make_error OOM guard), camada Lua (dt_view exposto), parity eixo 10.
- **Anéis 0–3** — descrição arquitetural e componentes `[Done]` detalhados nas
  versões anteriores deste arquivo (ver histórico Git / CHANGELOG).
