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
build verde (`build.sh --all` no Fedora / `windows_build.ps1` no Windows), teste
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
> **Follow-up leve:** rodar `windows_build.ps1` como confirmação; reabrir se
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
> **Follow-up leve:** confirmar com `windows_build.ps1`; reabrir se acusar algo.
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
> **Follow-up leve:** confirmar com `windows_build.ps1`; reabrir se acusar algo.
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
> Fedora **e no Windows** (`windows_build.ps1`, MSYS2-UCRT64). **Decisões:**
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

> **Concluído (2026-06-29), Lua-puro.** Windows verde (`windows_build.ps1`,
> Series acesso 34, DataSet core 212); equivalência Fedora de praxe para Lua-puro.
> Build verde, parity 12/12.

## 7. Completude do motor (Ring 0)  [Fedora]

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

## 8. Rolling → Ring 0  [Windows+Fedora]

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

## 9. Contratos de fronteira  [Fedora]

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
    **Confirmado no Windows** (`windows_build.ps1`, MSYS2-UCRT64): C 10/10
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
  - **[Done — 9.2 completo]** C: struct + view + detach; FFI cdef sincronizado
    (layout binário); `_types.lua` liga view; `column()`/`_raw_column` em
    `dataset/_core.lua`; testes de proteção E2 (test_core, +8) e de string view
    (test_cow +70, allocfail +70). Testes que dependiam do aliasing E2 migrados
    para dados que nascem com NA (Op A) / `update_column`. `_raw_column`
    registrado como exceção intencional do Eixo 2. **Valgrind-clean**
    (test_cow, test_string, allocfail: 0 leaks, 0 errors); parity 12/12; 18/18
    suítes Lua. Aguarda `--all` do Gui no Fedora (Valgrind + cobertura) para
    selo final.
  - Vínculo: COW.md (string ❌→✅); CODE_REVIEW A7 (posse de dados).

## 10. Completude de vetorização (Anel 0)  [Fedora]

Mesma tese do item 7 (completude do motor), agora para **transformações
element-wise**. A exploração de 2026-06-30 mapeou operações que fazem o loop em
Lua cruzando FFI por elemento, quando o padrão correto (delegar ao descritor → C)
já existe e é seguido em toda a aritmética (o `binop` é exemplar). Não são bugs —
são assimetrias de vetorização (performance): 1 travessia FFI por linha vs 1 total.

> **Meta-decisão:** levar ao Anel 0 o que o projeto já sabe fazer (o `binop`
> prova o padrão). Onde a primitiva escalar já existe mas falta a vetorizada,
> criar a versão de série; onde nem escalar existe, criar. A Lua passa a delegar.

- 10.1 **`prod()` → Ring 0** (E3). Única redução escalar fora do C — sum/mean/min/
  max/std/var todas têm primitiva; existe `cumprod`, falta `prod`. Assimetria por
  omissão (passou batido no item 5). Criar `smaug_f64_prod`/`smaug_i64_prod`.
- 10.2 **`between()` compõe no C** (E4). Element-wise (máscara `ge & le`); os
  comparadores `gt/lt/ge/le` já existem no Anel 0 — compor em C e usar o motor,
  eliminando o loop Lua.
- 10.3 **`abs`/`round`/`clip` → Ring 0** (E5). Element-wise matemáticos fixos, hoje
  via `self:map(closure)` (FFI por elemento). Provável que **falte a primitiva C**
  — então "delegar" aqui é criar a primitiva vetorizada, não só religar. Confirmar
  no fonte antes de executar.
- 10.4 **família `.dt` e `.str` vetorizadas** (E6). `dt_component` chama
  `C.smaug_dt_year(v)` **por elemento** num loop Lua — a lógica escalar está no C,
  falta a versão de série (`smaug_dt_year_series(s) → série`). Mesmo padrão em
  `.str` (upper/lower/len/...). Criar as primitivas de série; a Lua delega.
- 10.5 **primitiva `hash_series` no Anel 0** (E7) — **precisa de levantamento
  próprio antes de executar**. Padrão `tostring`-como-hash repetido em 6
  call-sites: `unique`/`nunique`/`value_counts`/`mode`/`isin` (Series) +
  `key_to_str` (relacional). Padrão repetido = primitiva ausente. É a de **maior
  alavancagem** (resolve 6 lugares), mas também a mais pesada (hash de valores
  arbitrários incl. string/datetime em C é trabalho real). Levantar escopo e
  decisões antes de cravar. Vínculo: item 12.4 (categorical hash — a ponta já
  registrada).

## 11. Ergonomia REPL  [Windows]

Objetos que o usuário segura devem se auto-mostrar legíveis — para exploração e
para debug quando dá erro. Requisito de v1.0: a API congela com a ergonomia que
tiver.

- 11.1 CategoricalSeries `__tostring` (objeto de 1ª classe; hoje cospe `table: 0x…`)
- 11.2 proxies `__tostring` (StrProxy, .dt, .at, .cat, Rolling, Expanding, GroupBy)
- 11.3 estabelecer invariante "objeto exposto → `__tostring`" + eixo de auditoria no
  parity que o guarda

## 12. Achados menores + débitos antigos  [Windows+Fedora]

Baixo risco, não bloqueiam nada acima. Varredura de limpeza.

- 12.1 mensagens I/O: remover "smaug" duplicado (`smaug: smaug_read_csv:` →
  padrão `smaug: <op> —`)
- 12.2 `read_parquet` fantasma (init.lua:50 comentado) — remover ou marcar pós-1.0
- 12.3 `column_t` sem datetime / CSV não infere dt — decidir: fechar ou registrar
  como pós-1.0 (conecta Anel 0 ↔ Anel 3)
  - Nota (E10, 2026-06-30): vírgula decimal BR não é bug — o CSV **suporta**
    `decimal=','` (o C troca por `.` em `try_f64`); ler `34,12` como string foi
    default `.`. Mesma natureza do E9 (12.10): default não-BR, não defeito.
    Documentar; conecta com 12.8 (fixtures BR).
- 12.4 categorical hash via `tostring` (cosmético)
- 12.5 I3 — `g_sort_series` global em `ops_str` (single-thread: sem bug)
- 12.6 I4 — `get_value` passa `nil` como status (assimetria; sem bug)
- 12.7 `tests/series/test_constructors.lua` re-declara `local n_ok` por seção
  (linhas 14/25/394/616) mas só imprime uma vez no fim → o headline "98 checks"
  subconta o real (~328 `check()` rodam de fato; cada um aborta em falha, então a
  cobertura é real, só o número impresso engana). Achado durante o item 3.
  Corrigir o relato (um contador único ou um print por seção) — cosmético, não
  afeta validação.
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
- 12.9 **`s:iat(i)` produz erro que despeja a Series inteira** (E8) — [Windows].
  `at`/`iat` são acessores por colchete (`s.iat[i]`, estilo pandas). A forma
  method `s:iat(i)` faz `self` cair como índice no `check_index` e, como a
  mensagem usa `tostring(i)`, imprime a Series toda (numa série grande, milhares
  de linhas). Detectar a chamada-método e orientar "use s.iat[i]".
- 12.10 **`read_csv` — aviso passivo quando lê 1 coluna com separador suspeito**
  (E9) — [Windows]. Default `sep=','` num CSV com `;` lê N colunas como 1, sem
  erro. **Decisão tomada:** NÃO detectar/escolher separador sozinho (esperto
  demais, falso-positivo pior que o problema); apenas, quando `ncols==1` e a
  coluna contém `;`/`\t` repetido, emitir `warn` "lido como 1 coluna; se
  esperava mais, verifique o separador (sep=';'?)". Ilumina cedo sem adivinhar;
  o usuário ignora se foi intencional. Vínculo: 12.8 (dados BR), 12.3.
- 12.11 **`Series:nrows()` — alias faltando** (E11) — [Windows]. Series tem `len`
  e `size`; DataSet tem `nrows` e `len`. Falta só `methods.nrows = methods.len`
  na Series (confirmado: não falta lógica, só o alias). Considerar alinhar os três
  nomes (len/size/nrows) nos dois lados para simetria total.
- 12.12 **sugestão em método errado** (E12) — [Windows]. `df:group_by()` cai no
  erro cru do Lua (`attempt to call method ... (nil)`). Polish: sugerir "você quis
  dizer groupby?" no `__index` quando o método não existe. Não é defeito; melhora
  a descoberta.

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
