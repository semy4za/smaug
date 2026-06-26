# Smaug — Roadmap

Este roadmap é uma **timeline sequencial**. Cada número é um tema; os decimais são
subtarefas. A ordem reflete dependência e risco — temas anteriores são fundação
dos seguintes. A **v1.0 ganha o direito de existir quando a timeline zerar**
(item 12 não achar inconsistência nova).

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

## 1. Fonte única de nulidade no Ring 0  [Fedora]

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

## 2. Sentinela único na camada Lua  [Windows]

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

## 3. bool_view  [Windows]

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

## 4. NA relacional unificado + Contrato 7  [Windows]

Hoje join (casa NA com NA), groupby (erro) e pivot_table (aceita) tratam NA na
chave de três formas. Viola o Contrato 6 (NA = ausência que não participa). Decisão
tomada: **erro orientado nas três**, alinhado ao groupby (que já está certo).
"Falha visível > acerto adivinhado" — o usuário trata com fillna/dropna na pipeline.

- 4.1 helper central `validate_keys_no_na(cols, op_name)`
- 4.2 join: NA na chave deixa de casar → erro
- 4.3 groupby: ajustar mensagem ao padrão (mencionar fillna além de dropna)
- 4.4 pivot_table: NA no índice/coluna deixa de ser aceito → erro
- 4.5 documentar **Contrato 7** — NA em chave relacional
- 4.6 testes guardando as três operações (chave simples e composta)

*Padrão da mensagem:* `smaug: <op> — <chave/coluna> 'X' contém NA; trate com fillna
ou dropna antes`. NA em qualquer coluna da chave composta dispara.

## 5. Reduções + element-wise no DataSet  [Windows]

O DataSet não tem reduções diretas (`df.sum()`) nem operações element-wise. O
usuário itera colunas na mão, e o GroupBy reimplementa reduções por não ter a quem
delegar. Maior bloco de paridade; destrava o item 5.4.

- 5.1 reduções por coluna → Series de resultado: sum, mean, min, max, std, var,
  median, prod, quantile, skew, kurtosis, mad, sem, count_nonnull
- 5.2 element-wise → DataSet: abs, round, clip, cumsum, cummin, cummax, cumprod
- 5.3 transformações: ffill, bfill, shift, diff, astype, isna, notna
- 5.4 GroupBy delega às reduções da Series/coluna (elimina a duplicação inline)
- 5.5 `min_count` em sum/prod (Series e DataSet) — opt-in. Default preserva o
  comportamento atual (soma de conjunto vazio = 0, neutro matemático);
  `min_count=N` exige N não-nulos, senão NA. Semântica já decidida, e este é o
  momento natural por estarmos construindo as reduções agora

## 6. Paridade Series↔DataSet e auditor  [Windows]

Fecha as assimetrias restantes e ensina o parity a pegar a classe que escapou
(pares singular↔plural — o caso `dtype`/`dtypes` que abriu a auditoria).

- 6.1 `Series:dtype()` (DataSet tem `dtypes`, Series não tinha o singular)
- 6.2 reconciliar `sort` (Series) vs `sort_by` (DataSet) — definir nome canônico
- 6.3 avaliar sample/to_markdown/to_string na Series (decidir quais fazem sentido)
- 6.4 ensinar o parity a parear singular↔plural (`dtype`↔`dtypes`, `len`↔`nrows`)

## 7. Completude do motor (Ring 0)  [Fedora]

O motor foi construído numérico-primeiro. Operações agnósticas a tipo e de tipo
ordenável só existem em f64/i64. Depende do item 1 (nulidade coerente) já pronto.

- 7.1 shift/ffill/bfill em bool/str/dt (agnósticas a tipo) — **[Fedora]**, 🟥 do inventário
- 7.2 min/max/argmin/argmax em ordenáveis (dt/str têm sort/gt/lt)
- 7.3 rank em dt/str
- 7.4 bool eq/ne (único dtype sem igualdade)

## 8. Rolling → Ring 0  [Windows+Fedora]

A versão Lua do rolling (Series e DataSet) reimplementa o que o C faz — e faz
**mais** que o C (std/var/count/min_periods/expanding). "Mandar pro Ring 0" exige
estender o C primeiro, depois Series/DataSet delegam. Decisão: eliminar a
duplicação, fonte única no C.

- 8.1 estender C: rolling std/var/count
- 8.2 estender C: min_periods (usa o invariante de nulidade do item 1)
- 8.3 estender C: expanding (janela crescente)
- 8.4 Series delega ao C (remove reimplementação em `_rolling.lua`)
- 8.5 DataSet delega (remove Rolling Lua em `_stat.lua`)

## 9. Ergonomia REPL  [Windows]

Objetos que o usuário segura devem se auto-mostrar legíveis — para exploração e
para debug quando dá erro. Requisito de v1.0: a API congela com a ergonomia que
tiver.

- 9.1 CategoricalSeries `__tostring` (objeto de 1ª classe; hoje cospe `table: 0x…`)
- 9.2 proxies `__tostring` (StrProxy, .dt, .at, .cat, Rolling, Expanding, GroupBy)
- 9.3 estabelecer invariante "objeto exposto → `__tostring`" + eixo de auditoria no
  parity que o guarda

## 10. Achados menores + débitos antigos  [Windows+Fedora]

Baixo risco, não bloqueiam nada acima. Varredura de limpeza.

- 10.1 mensagens I/O: remover "smaug" duplicado (`smaug: smaug_read_csv:` →
  padrão `smaug: <op> —`)
- 10.2 `read_parquet` fantasma (init.lua:50 comentado) — remover ou marcar pós-1.0
- 10.3 `column_t` sem datetime / CSV não infere dt — decidir: fechar ou registrar
  como pós-1.0 (conecta Anel 0 ↔ Anel 3)
- 10.4 D4 — categorical hash via `tostring` (cosmético)
- 10.5 I3 — `g_sort_series` global em `ops_str` (single-thread: sem bug)
- 10.6 I4 — `get_value` passa `nil` como status (assimetria; sem bug)

## 11. Reescrita de exemplos + docstrings  [Windows]

Doc reflete a API depois que ela para de mudar (itens 1–10).

- 11.1 exemplos README/API_INDEX → forma oficial `smaug.Series({...})`
- 11.2 docstrings nos métodos públicos de Series e DataSet

## 12. REVISÃO FINAL (penúltimo)  [Fedora]

O teste de que a campanha de coerência fechou. Se achar 🟥 novo, volta pra timeline.

- 12.1 reauditar os 4 anéis com as mesmas lentes (completude, invariantes,
  coerência interna, ergonomia, paridade)
- 12.2 limpar e reconciliar `exceptions.txt` do parity
- 12.3 Fedora: parity 12/12 + Valgrind + cobertura + allocfail
- 12.4 a timeline zera somente se 12.1 não achar inconsistência nova

## 13. RELEASE v1.0 (último)  [Windows+Fedora]

- 13.1 FFI loader instalável (descobre `.so`/`.dll`/`.dylib` em layout instalado)
- 13.2 distribuição / LuaRocks
- 13.3 LDoc + GitHub Pages
- 13.4 tag v1.0.0

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
