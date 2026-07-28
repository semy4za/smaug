# Smaug — Roadmap

Este roadmap é uma **timeline sequencial**. Cada número é um tema; os decimais são
subtarefas. A ordem reflete dependência e risco — temas anteriores são fundação
dos seguintes. A **v1.0 ganha o direito de existir quando a timeline zerar**
(item 14 não achar inconsistência nova).

O arquivo lista **o que falta**. O que fechou vive em duas camadas: o *Índice do
concluído* (abaixo) resolve as referências por número que o código faz em
comentários, e o `CHANGELOG` guarda o raciocínio, as medições e os achados de
cada item. A descrição arquitetural permanente (Filosofia, Anéis) fica antes da
timeline.

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

---

## Índice do concluído

Os itens abaixo **fecharam**. Ficam aqui como **stubs resolvíveis**, não como
histórico: o código referencia estes números em comentários (`10.6` aparece 52
vezes, `12.21` 30, `9.1` 25) para explicar por que ele é como é — apagar as
entradas orfanaria essas referências. O **raciocínio, as medições e os achados
de cada um estão no `CHANGELOG`** (103 entradas), que é o registro histórico do
projeto. Aqui fica só o suficiente para resolver uma referência.

**Temas fechados por inteiro**

| # | tema | ambiente |
|---|------|----------|
| 1 | Fonte única de nulidade no Ring 0 | [Fedora] |
| 2 | Sentinela único na camada Lua | [Windows] |
| 3 | `bool_view` | [Windows] |
| 4 | NA relacional unificado + Contrato 7 | [Windows] |
| 5 | Reduções + element-wise no DataSet | [Windows/Fedora] |
| 6 | Paridade Series↔DataSet e auditor | [Windows] |
| 7 | Completude do motor (Ring 0) | [Fedora] |
| 8 | Rolling → Ring 0 | [Windows+Fedora] |
| 9 | Contratos de fronteira | [Fedora] |
| 11 | Ergonomia REPL | [Windows] |

**Subitens fechados referenciados pelo código** (blocos 5, 7, 9 e 11)

- 5.0 / 5.1 / 5.3 — reduções e element-wise no DataSet; `5.5` cobriu
  `sum(min_count)`.
- 7.1 / 7.1b — movimentação de dados (`ffill`/`bfill`) como responsabilidade do
  Anel 0.
- 7.2a — `argmin`/`argmax` de string (ordem lexicográfica por bytes; `SIZE_MAX`
  para vazia ou toda-NA).
- 7.2b — `min`/`max` de string.
- 7.3 — todos os dtypes ordenáveis (f64/i64/dt/str/bool) com `sort`/`argsort`.
- 9.1 — int64 acima de 2^53 sem caminho de entrada correto: `check_value` passou
  a aceitar `cdata int64_t` (Sub-B) e `get_raw` deu a saída exata (Sub-A). É a
  raiz da família que os itens 9.3 e 9.4 continuaram.
- 9.2 — `string` ganhou view + Copy-on-Write, com detach seguro sob OOM.
- 9.3 — fronteira do escalar int-based nos call-sites de **operação**
  (comparadores e aritmética escalar): `core/int_scalar.lua` como fonte única;
  cdata aceito, `number >= 2^53` recusado por origem.
- 9.4 — `nlargest`/`nsmallest` devolviam valor **ausente do dataset** (o buffer
  int64 passava por `tonumber`, e `…995` virava `…996`); separado em
  `c_sorted_nonnull_native` (exato) e wrapper que normaliza para double.
- 11.3 — invariante + auditoria de exibição (eixo de paridade `13_tostring`).
- 11.4 — exibição de int64 exato (`cell_of` → `get_raw`).

**Subitens fechados do bloco 10** (completude de vetorização)

- 10.2 — `between` → Anel 0 nos **quatro** dtypes ordenáveis (f64/i64/datetime/
  string). Primitiva dedicada de passada única em vez de compor `ge`+`le`
  internamente (que custaria três pares de alocação e três varreduras); os dois
  `bool` `inc_lo`/`inc_hi` cobrem os quatro modos de `inclusive`. Fechou também
  uma violação de **P3**: o fallback em Lua e o degrau `check_i64` saíram do
  `_predicates.lua`, e a comparação element-wise deixou de existir em dois anéis.
  Em int64 o suporte a > 2^53 virou real — os limites entram exatos pela fronteira
  do escalar (9.3). Fatiado em f64+i64 e depois dt+str; a lição de cobertura das
  duas fatias está no `CHANGELOG` (testar os modos num dtype não cobre os outros).
- 10.5 — chave de igualdade/cardinalidade → int64 exato (L2). Passo A: `core/keys.lua`
  como fonte única de codificação de chave. Passo B (hash no Anel 0) segue aberto → ver 10.5-B abaixo.
- 10.6 — família seleção/preenchimento por máscara (`fillna`/`combine_first`/`where`/`select`/`ffill`) → Anel 0.
- 10.7 — `astype`: matriz `src×dst` no Anel 0.
- 10.8 — `BoolSeries`: coerência de caminho com o Anel 0; `boolseries.lua` era código morto, removido.
- 10.9 — formatação de serialização canônica (`smaug_fmt_*`, `smaug_parse_*`) como fonte única.

**Subitens fechados do bloco 12** (achados menores)

12.1 a 12.7, 12.9, 12.10, 12.12, 12.15, 12.17, 12.18, 12.20 a 12.24, 12.27,
12.28, 12.29, 12.31, 12.32 — correções pontuais de robustez, cobertura, paridade
e contratos. Cada um narrado no `CHANGELOG` na data em que fechou. Dois merecem
menção por mudarem processo, não só código:

- 12.31 — a inferência de dtype passou a decidir por **família** (numérico /
  string / bool) em vez de por rank; mistura sem promoção segura erra na
  inferência, nomeando os tipos e as posições, em vez de construir um container
  que rejeita a própria lista.
- 12.32 — **um** gerador de MANIFEST (o `.ps1` delega ao `.sh`), acabando com seis
  eixos de divergência entre plataformas; cabeçalho ganhou **procedência**
  (`# Arvore: <commit>`), porque hash de arquivo prova consistência interna e
  nunca atualidade — um MANIFEST antigo valida limpo contra a própria árvore
  antiga. Escrita atômica: falha no meio deixa o arquivo anterior intacto.

**Fronteiras encerradas (decisões de "não fazer")** — registradas no `CHANGELOG`:
broadcasting axis-aware pertence ao Anel 6, não ao 1; `map` sobre FFI é
intrínseco ao Anel 1; `get()` degradar int64 > 2^53 é limitação do Lua com saída
documentada (`get_raw`).

**Antes da timeline** — trabalho que originou esta lista, sem numeração de item:

- **Fases 1–5** — inventário arquitetural, decisões de fundação (Bloco G),
  migração de primitivas para Ring 0, split dos arquivos-deus, hardening global
  (Valgrind, cobertura, allocfail).
- **Bloco H** — coerência de API e convenções de entrada: separador de data `/`,
  decimal CSV configurável (BR), validação `sep==decimal`, `dayfirst` completo.
- **Bloco I** — fechamento de coerência pré-auditoria: docs sync, Ring 0 fixes
  (rank i64, make_error OOM guard), camada Lua (dt_view exposto), parity eixo 10.
- **Auditoria dos 4 anéis** — a campanha de revisão cujos achados viraram os
  itens numerados desta timeline.

> Números frágeis (contagens de check, cobertura) vivem em `COVERAGE.md`,
> `MANIFEST.txt` e na saída do `build.sh` — não são copiados para cá, onde
> envelheceriam em silêncio.

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

## 10. Completude de vetorização (Anel 0)  [Fedora]

Operações que fazem o loop em Lua cruzando FFI por elemento, quando o padrão
correto — delegar ao descritor → C — já existe. Subitens 10.5 a 10.9 fechados
(ver índice acima); 10.5 Passo B segue aberto.

- 10.1 **`prod()` → Ring 0** (E3). Única redução escalar fora do C — sum/mean/min/
  max/std/var todas têm primitiva; existe `cumprod`, falta `prod`. Assimetria por
  omissão (passou batido no item 5). Criar `smaug_f64_prod`/`smaug_i64_prod`.
- 10.3 **Família matemática element-wise → Anel 0** (E5).
  **[Fatia A: Windows OK · Fedora PENDENTE · Fatia B: não iniciada]** Fatiado por concern e
  por arquivo Lua: **A** = as seis matemáticas (`_selection.lua`), mecânicas e
  sem decisão semântica; **B** = `abs`/`round`/`clip` (`_transform.lua`), a
  família que preserva dtype, onde vivem as três decisões e o degrau que sai.
  - **Fatia A — `sin`/`cos`/`tan`/`exp`/`log`/`sqrt`: [implementada
    2026-07-27 · selos PENDENTES]** Uma **macro** (`F64_MATH_IMPL`) gera os seis
    corpos, que diferiam apenas pela função de libm — seis corpos à mão seriam
    seis lugares para repetir cada correção, e cinco para esquecê-la. Padrão que
    a casa já usa (`DT_CMP_IMPL`). Entrada int64 não tem versão própria (Opção
    1): o frontend encadeia `astype("float64")` — já vetorizado (10.7) — e chama
    a versão f64; converter antes não perde nada porque a saída é f64 de todo
    jeito. Testes guiados por **tabela** pelo mesmo motivo da macro: cada
    instanciação tem os próprios ramos, então cobrir uma não cobre as outras
    cinco (lição do 10.2 fatia 1). `test_ops_edge` 307→346, `test_integration`
    78→92, allocfail 1918→**1972**; Windows MSYS2-UCRT64 confirmado 2026-07-27
    (falta o Fedora: Valgrind e cobertura não rodam lá).
    Cobertura **subiu** (94.81→94.87% branch-alvo)
    com descobertos **iguais em 227** — as seis entraram 100% cobertas. Mutação
    verificada em dois eixos: tirar a propagação de nulo e trocar `sqrt` por
    `fabs` abortam o teste. `tan` não era exercitada antes.
  - **Fatia B — `abs`/`round`/`clip`** (não iniciada). Aqui ficam as três
    decisões e o degrau `check_i64`, que só sai quando as três descerem.
  **Correção ao desenho original (2026-07-27):** são **12** funções em C, não 11
  — a decisão "`round(int64)` preserva int64" tornou `round` uma operação que
  preserva dtype, exigindo versão i64; o número anterior assumia saída f64. E a
  macro cobre **7**, não 6: `abs` de f64 tem a mesma forma das seis (unária,
  f64→f64, só troca a função de libm — `fabs`). Resultado: 1 macro + 5 corpos à
  mão para 12 funções.
  Confirmado no fonte: **não existe nenhuma** dessas primitivas no Anel 0 — nem
  para f64. "Delegar" aqui é criar as primitivas, não religar.
  - **Escopo real: nove operações, não três.** O item nasceu como
    `abs`/`round`/`clip` (as que tinham degrau, porque são as que preservam
    valor), mas elas são 3 de uma família que vive inteira no Anel 1 via `map`.
    As outras seis (`sin`/`cos`/`tan`/`exp`/`log`/`sqrt`, `_selection.lua:272`)
    não têm degrau só porque a saída é `float64` e não há int64 a preservar —
    mas o loop sobre FFI é o mesmo. Fechar só três deixaria seis irmãs esperando
    a mesma encanação: retrabalho garantido.
  - **Quatro formas:** (A) unária pura, saída sempre f64 — as seis matemáticas;
    (B) unária + param, saída f64 — `round(ndigits)`; (C) unária, preserva dtype
    — `abs`; (D) dois escalares opcionais, preserva dtype — `clip(lo, hi)`.
  - **Superfície em C — Opção 1 (decidida).** Nas formas A e B a saída é `float64`
    **independente da entrada**, então só as versões f64 nascem em C; para entrada
    int64 o Anel 1 encadeia `astype("float64")` (já vetorizado, 10.7) e chama a
    versão f64. Não é reimplementação — é sequenciar duas chamadas do Anel 0, e
    converter antes não perde nada que a operação não fosse perder (a saída é f64
    de todo jeito). **11 funções** em vez de 18. O custo é uma passada e uma
    alocação extras para entrada int64; o benefício é metade da superfície de
    varredura OOM, que é o custo que mais pesa neste projeto.
  - **Macro para a forma A**, no padrão do `DT_CMP_IMPL`: as seis são idênticas
    exceto pela função de libm. O Lua já as gera por laço (`_selection.lua:276`),
    ou seja, a casa já as trata como família.
  - **Três decisões semânticas que a implementação em C força** (hoje implícitas
    ou erradas; todas decididas em 2026-07-27):
    - **`abs(INT64_MIN)` → erro.** `-9223372036854775808` não tem contrapartida
      positiva em int64. Hoje "funciona" porque o degrau barra por outro motivo
      (excede 2^53); removido o degrau, vira caso genuíno. Erro na operação, não
      nulo no elemento — nulo seria converter valor em ausência, que o Contrato 9
      trata como coisa distinta.
    - **`clip(lo, hi)` com `lo > hi` → erro.** Bug de lógica **existente hoje**,
      em qualquer dtype, sem relação com 2^53: provado que `{1,5,9}:clip(8,2)`
      devolve `{8,8,2}`. O `return lo` curto-circuita antes de checar `hi`, então
      valor abaixo de `lo` vira `lo` e nunca é limitado por `hi` — o resultado não
      está dentro de faixa nenhuma. Faixa contraditória não tem semântica válida.
    - **`round` em int64 preserva int64.** Hoje devolve `float64`
      (`_transform.lua:474`), o que **degrada acima de 2^53** justamente na
      operação que estamos consertando por precisão. Com `ndigits >= 0` é
      identidade; com `ndigits < 0` arredonda dezenas e continua inteiro. Fica
      coerente com `abs` e `clip`, que preservam dtype. Verificado que **nada
      depende** do comportamento atual: nenhum teste assevera o dtype, o
      `API_INDEX` não promete dtype, e o `round` do DataSet delega via
      `map_frame` (o teste dele checa coluna float). Borda a definir na execução:
      `ndigits <= -19` estoura o fator `10^n` em int64.
  - **Confirmado sem decisão:** `sqrt(-4)` e `log(-4)` → **NaN**, não erro nem
    nulo — coerente com o Contrato 9 (NaN é valor; ausência é `null_mask`), e é o
    que o C faz nativamente. Nulos preservados nas nove.
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

- 10.5 Passo B **hash de chave no Anel 0** (resto do 10.5). O `keys.lua` já é o
  ponto de plugue: a canonicalização de chave vira primitiva do Núcleo
  (`smaug_hash_table_t`, ao lado do `multi_argsort`) e o Lua delega sem tocar
  call-site. Trabalho maior: hash de string e datetime em C. Vínculo: 12.4.

## 12. Achados menores + débitos antigos  [Windows+Fedora]

Vinte e quatro subitens já fecharam (ver índice acima). Restam:

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
- 12.11 **`Series:nrows()` — NÃO FAZER (decisão 2026-07-14).** A leitura do
  código mostrou que o "gap" contradiz uma convenção deliberada: o eixo 08
  registra "Series tem len+size (size = alias de len); DataSet tem nrows+ncols" —
  `nrows` é vocabulário tabular (uma Series não tem linhas, tem elementos),
  `len`/`size` é vocabulário de sequência. Não é ausência, é separação de
  domínio. Pandas faz igual: `Series` não tem `nrows` (é `DataFrame.shape[0]`).
  Adicionar o alias violaria a convenção que o próprio parity audita. Sub-item
  encerrado sem código.
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
- 12.16 **`fillna` de datetime aceitar string ISO** — [Windows] (registrado
  2026-07-07, futuro próximo). O `check_value` de datetime já aceita `number`
  (epoch_ms) **ou** string ISO 8601, como `set`/`append`. Mas o `fillna` de
  datetime aceita só `number` — na integração ao `coalesce_scalar` (Anel 0) o
  `dt` ficou restrito a `number` para não ampliar escopo. Alinhar: aceitar string
  ISO no `fillna` de datetime, parseando via `dt_parse` antes de delegar —
  uniformiza `fillna` com `set`/`append`.
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
 - 12.33 **Duas semânticas visíveis ao usuário sem contrato** — [Fedora]
   (doc; sem C, sem Lua). Achado ao verificar o desenho da fatia 2 do 10.2 contra
   o CONTRACT (2026-07-27). Nenhum dos 11 contratos cobre:
   - **Colação de string.** `str_cmp_at` (`smaug_ops_str.c:24`) define
     lexicográfico **por byte**, com prefixo igual desempatando pela **mais
     curta**. Isso existe só num comentário de código, e determina o que
     `sort`, `min`/`max`, os seis comparadores e o `between` de string devolvem —
     semântica visível ao usuário. Sem contrato, não se sabe se é promessa ou
     detalhe de implementação: alguém poderia trocar por colação por locale
     achando que é melhoria, e nada diz que isso quebraria expectativa. Fica mais
     exposto com `between` (consulta por faixa).
   - **Propagação de nulo em comparação.** Nulo entra → nulo sai, consistente nos
     seis comparadores de cada dtype e no `between`. Implementado certo, nunca
     prometido. O Contrato 6 fala de `filter` descartando `NA`; o 9 distingue NaN
     (valor) de ausência (`null_mask`); a propagação em si não está em lugar
     nenhum.
   - **Não é bug** — os dois comportamentos existem e estão corretos e uniformes.
     É lacuna de contrato: comportamento sem promessa é comportamento que pode
     mudar por acidente. Vira Contrato 12 e 13, ou notas nos existentes (o de
     nulo talvez caiba como parágrafo no Contrato 9).
   - **Vínculo:** 10.2 fatia 2 (que tornou as duas visíveis); Contrato 6, 9;
     item 12.34 (a colação está implementada cinco vezes).
 - 12.34 **Colação de string implementada cinco vezes** — **[Done — Fedora
   2026-07-27]** (refatoração interna do C: nenhuma função pública nova, nenhum
   `cdef` — **não muda ABI**). Valgrind 0 erros; cobertura confirmou a previsão
   exata: **226 ramos descobertos antes e depois**, com 24 ramos cobertos a menos
   no total (a lógica duplicada). MANIFEST 126→128 arquivos.
   A edição do `build_win.ps1` (lista de testes Lua), que não pôde ser testada no
   ambiente de desenvolvimento, foi **confirmada no Windows em 2026-07-27**: os
   dois testes de `core/` passaram a aparecer na saída de lá, o que também
   comprovou na prática o achado das listas divergentes.
   - **Resolvido:** núcleo único `smaug_cmp_bytes(pa, la, pb, lb)` em
     `include/smaug_str_internal.h` (`static inline`, no padrão do
     `smaug_io_internal.h` — não exporta símbolo). As quatro implementações
     passaram a delegar: `str_cmp_at` e `str_cmp_idx` viraram invólucros de duas
     linhas; `sort_cmp_idx` virou `str_cmp_idx` + desempate por índice (que é
     preocupação de *sort*, não de colação); o `memcmp` inline do
     `ops_window.c` passou a chamar o núcleo. `str_cmp_idx` foi movida para
     antes de `sort_cmp_idx` — ordem lógica, colação antes de ordenação.
   - **Não era só duplicação: uma das quatro divergia.** A do `ops_window.c`
     chamava `memcmp(pa, pb, lmin)` **sem a guarda `lmin > 0`** — a única das
     quatro sem ela. `memcmp` exige ponteiro válido mesmo com `n == 0`, e em
     série vazia `buffer + offset` pode ser `NULL + 0`: UB pelo padrão C, ainda
     que inofensivo na prática. Unificar eliminou o caso.
   - **Sobrou um `memcmp` e ele é legítimo:** o atalho de *igualdade* em
     `str_compare` (eq/ne), que compara comprimento primeiro (rejeição O(1)) e
     só então compara bytes. Não é colação — não ordena nem desempata — e é
     semanticamente equivalente ao núcleo (`cmp_bytes(...) == 0` ⟺ mesmo
     comprimento e bytes iguais).
   - **A invariante Lua↔C virou teste:** `tests/core/test_collation.lua` (59
     checks) assevera que o `<`/`>`/`==` do LuaJIT concordam com o C em pares
     onde `memcmp` e colação de locale **divergem de fato** — maiúscula ×
     minúscula, `"Z"` × `"a"`, acento multibyte, NUL embutido, prefixo, vazia —,
     que `CategoricalSeries` (compara em Lua) dá o mesmo que `Series<string>`
     (compara no C), e que `sort` ordena por byte. Se o interpretador mudar, ou
     alguém rodar sob outro runtime com `strcoll`, isto falha alto em vez de
     divergir em silêncio. **Mutação verificada:** inverter o desempate de
     prefixo no núcleo aborta o teste.
   - **Cobertura:** descobertos **227 antes e 227 depois** — a refatoração
     removeu 24 ramos que estavam totalmente cobertos (a lógica duplicada) e não
     introduziu nenhum descoberto. O percentual mexeu só porque o denominador
     encolheu (4397→4373): efeito de tirar redundância, não regressão.
   - **Dois achados colaterais, ambos corrigidos aqui:**
     - **O `Makefile` não declarava dependência de header.** `$(TARGET): $(SRCS)`
       — editar um `.h` **não** recompilava, então a `.so` ficava velha e a suíte
       passava sobre código que não é o da árvore. Falso verde silencioso.
       Descoberto na pele: um teste de mutação num header "passou" indevidamente.
       Agora `$(TARGET): $(SRCS) $(HDRS)`, com `$(HDRS) = $(wildcard include/*.h)`
       espelhando o glob do 12.19. O `build.sh` era imune (recompila todos os
       fontes num comando só); o `make` é o que se usa no dia a dia.
     - **As três listas de teste Lua tinham divergido.** `core/test_keys` — que
       guarda a correção L2 do int64 > 2^53 — estava só no `build.sh`: **não**
       rodava no Windows nem na cobertura. Mesma família do `test_astype`
       (12 binários no Fedora, 11 no Windows). As três listas foram alinhadas.
       A causa de fundo é manutenção manual de lista, que é o que o 12.19
       (metade C_TESTS, aberta) existe para resolver.
   - **Vínculo:** 12.33 (o contrato de colação passa a ser sustentado por um
     núcleo único + teste de invariante, em vez de cinco cópias que por acaso
     concordam); 10.2 fatia 2 (`str_between` já consome o núcleo); 12.19
     (listas mantidas à mão).
## 13. Reescrita de exemplos + docstrings  [Windows]

Doc reflete a API depois que ela para de mudar (itens 1–12).

- 13.1 exemplos README/API_INDEX → forma oficial `smaug.Series({...})`
- 13.2 docstrings nos métodos públicos de Series e DataSet

## 14. VERIFICAÇÃO PONTA A PONTA — porta de entrega  [Fedora + Windows]

O item que decide se o projeto **pode ser entregue**. Não é uma revisão de código:
é a prova de que motor, contratos, documentação e superfície externa contam a
**mesma história**. Nada aqui é opcional, e achar 🟥 devolve o item à timeline.

Cinco frentes. As três primeiras verificam o que existe; as duas últimas
verificam o que falta para alguém **de fora** conseguir usar.

### 14.1 Motor (Anel 0) — leitura linha a linha do C

Não é rodar a suíte: é **ler**. A suíte prova o que foi testado; a leitura acha o
que ninguém pensou em testar. Um arquivo por vez, com estas lentes:

- **Fronteira pública valida?** Toda função exportada checa ponteiro nulo,
  índice fora de faixa e tamanho zero — o engine não confia no caller.
- **Todo caminho de erro libera o que alocou?** Especialmente os parciais: alocou
  dois buffers e o segundo falhou.
- **Overflow e casos degenerados estão decididos?** `INT64_MIN` em `abs`/negação,
  faixa contraditória em `clip`, `10^n` estourando, divisão por zero, série vazia,
  `malloc(0)`.
- **Duplicação de regra.** Mesma semântica escrita em mais de um lugar é onde a
  divergência nasce. Precedente: a colação de string existe em quatro pontos do C
  (`str_cmp_at`, `sort_cmp_idx`, `str_cmp_idx`, `ops_window`) — ver 12.34.
- **Reentrância.** Nenhum estado global mutável (Contrato 11, eixo 14).
- **Convenções divergentes entre dtypes** para a mesma operação lógica: alocação
  de máscara (dt sempre × f64/i64 condicional), `malloc(0)` vs `malloc(size?:1)`.

### 14.2 Anéis 1–3 — coerência de camada

- Nenhum loop element-wise sobre FFI sobrou no Anel 1 (é o item 10 fechado de fato).
- Nenhuma regra do Anel 0 reimplementada acima dele (P3).
- Fonte única por concern: `keys.lua`, `int_scalar.lua`, `errors.lua` — e nenhum
  guard cru sobrevivendo ao lado deles.
- Paridade Series ↔ DataSet ↔ CategoricalSeries: o que existe num existe nos
  outros, ou a exceção está registrada em `exceptions.txt`.

### 14.3 Contratos e documentação — a doc descreve o que o código faz

O eixo `12_docs_sync` prova **presença** do método na referência, não **correção**
da descrição. Staleness semântica não tem rede automática — só leitura. Já
aconteceu: a nota de int64 > 2^53 no README ficou factualmente errada por semanas
com o eixo verde.

- Reler `CONTRACT.md` **contra o código**, contrato por contrato, executando os
  exemplos.
- Todo comportamento visível ao usuário tem contrato, ou está explicitamente
  fora dele. Ver 12.33 (colação, propagação de nulo).
- `ARCHITECTURE.md` descreve os anéis como eles são hoje — inclusive o que
  `[Done]` significa em cada um.
- `README`, `API_INDEX`, `API_Reference`, `COW`, `Build_and_Testing`: sem promessa
  vencida.
- `CHANGELOG` com entrada para cada sessão; `Roadmap` sem item fantasma.

### 14.4 Verificação executável — as duas plataformas

- **Fedora:** `build.sh --all` verde, Valgrind 0 erros em todos os binários,
  cobertura medida (linha e branch-alvo), `allocfail` varrendo todos os pontos,
  stress.
- **Windows MSYS2-UCRT64:** `build_win.ps1` verde, com a **mesma** contagem de
  checks do Fedora. Divergência de contagem é sintoma, não detalhe.
- **Paridade 15/15**, com `exceptions.txt` limpo e reconciliado — cada exceção
  ainda justificada, nenhuma herdada por inércia.
- Cada teste C rodando nas duas plataformas: hoje o Windows roda 11 binários e o
  Fedora 12 (falta `test_astype` na lista do `build_win.ps1`).
- MANIFEST idêntico nas duas plataformas para a mesma árvore (12.32), com
  procedência apontando o commit certo.

### 14.5 Superfície externa — o que falta para ser usável por terceiros

Verificado em 2026-07-27 e **ausente**. Correção interna não substitui isto: sem
estes pontos o projeto é excelente e inutilizável por quem não é o autor.

- **`LICENSE`** — não existe. Sem licença, ninguém pode legalmente usar, copiar ou
  derivar. É o maior bloqueio do projeto e o mais barato de resolver.
- **Fronteira público × interno** — hoje é um comentário no `init.lua`, não um
  contrato. Nada impede alguém de acoplar em `smaug.core.series._types`. Declarar,
  e idealmente verificar por eixo de paridade.
- **Política de versão** — `_VERSION = "1.0.0-dev"` sem semver declarado nem
  janela de depreciação. Depois de existirem usuários, isto fica caro.
- **Instalação** — sem rockspec, sem artefato de release; o caminho é "clone e
  compile", que exige gcc (e MSYS2 no Windows). Ver 15.1/15.2.
- **Taxonomia de erro** — erros são string. Um pipeline que precise ramificar por
  causa (arquivo ausente × dtype incompatível × OOM) só pode fazer match em texto,
  que quebra quando a mensagem melhora. `smaug_status_t` existe no C e não sobe.
  Mudança de contrato: barata agora, cara depois.
- **Medição de performance** — correção é medida à exaustão (MC/DC, allocfail,
  property-based, mutação); performance **não é medida**. O bloco 10 inteiro se
  justifica por coerência arquitetural, não por número. Uma fundação de pipeline
  precisa poder afirmar performance.

### 14.6 Critério de saída

A timeline zera — e a v1.0 ganha o direito de existir — somente se 14.1 a 14.4
não acharem inconsistência nova **e** 14.5 estiver resolvido ou explicitamente
adiado com justificativa registrada.


## 15. RELEASE v1.0 (último)  [Windows+Fedora]

- 15.1 FFI loader instalável (descobre `.so`/`.dll`/`.dylib` em layout instalado)
- 15.2 distribuição / LuaRocks
- 15.3 LDoc + GitHub Pages
- 15.4 tag v1.0.0
- 15.5 `LICENSE` — pré-requisito de qualquer distribuição (ver 14.5)

---

# Pós-v1.0 — trilhas paralelas (fora desta timeline)

- **Versão em inglês** — documentação, mensagens de erro e i18n. Trilha própria;
  mensagens de erro são API, mas a internacionalização completa é projeto à parte.
- **Trilha Analítica** — Matrix → Tensor → ML.
- **Trilha Projeto** — I/O estendido (SQL, Excel, Parquet) → Persistência → Models.
- **Frentes diferidas** — `replace({de=para})`, índice/MultiIndex, plotting,
  tipos extras (float32, int32/16/8). Só se caso real justificar.
  (`sum(min_count)` subiu para a timeline, item 5.5.)
