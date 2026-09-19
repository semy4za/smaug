# Smaug — Arquitetura

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

<details>
<summary>Nesta página</summary>

- [Princípios](#section-principios)
- [Modelo de anéis](#section-modelo-de-aneis)
- [Anel 0 — Núcleo Computacional Done](#section-anel-0-nucleo-computacional-done)
- [Anel 1 — Abstrações de Dados Done](#section-anel-1-abstracoes-de-dados-done)
- [Anel 2 — Operações Relacionais Done](#section-anel-2-operacoes-relacionais-done)
- [Anel 3 — Conectividade / I/O Done — v1.0](#section-anel-3-conectividade-i-o-done-v1-0)
- [Anel 4 — Persistência Concept](#section-anel-4-persistencia-concept)
- [Anel 5 — Models Concept](#section-anel-5-models-concept)
- [Anel 6 — Matrix Concept](#section-anel-6-matrix-concept)
- [Anel 7 — Tensor Concept](#section-anel-7-tensor-concept)
- [Anel 8 — Machine Learning Concept](#section-anel-8-machine-learning-concept)
- [Anel 9 — Interação e Ferramentas Concept](#section-anel-9-interacao-e-ferramentas-concept)
- [Princípios da Trilha Analítica](#section-principios-da-trilha-analitica)
- [Régua de versões](#section-regua-de-versoes)
- [Regra de decisão arquitetural](#section-regra-de-decisao-arquitetural)
- [Estado da verificação — revisão de 2026-09-18](#section-estado-da-verificacao-revisao-de-2026-09-18)

</details>

Documento de referência para a estrutura conceitual e o modelo de crescimento
do ecossistema Smaug. Muda raramente — descreve teoria, não entregas.

Para o estado atual de cada anel e as próximas entregas concretas, ver
`Roadmap.md`. Para o histórico de mudanças, ver `CHANGELOG.md`.

Revisão documental: 2026-09-18. `[Done]` identifica entrega de funcionalidade,
não certificação da implementação. O estado da verificação é o da auditoria
[parecer do rework](TEST_SUITE_REWRITE_REVIEW.md); alegações históricas de cobertura não a substituem.

---

<a id="section-principios"></a>

## Princípios

**P1 — Crescimento para fora.**
A evolução ocorre pela adição de anéis externos. Novas funcionalidades não
exigem expansão estrutural do núcleo.

**P2 — Dependências fluem para dentro.**
Um anel pode depender de anéis internos. O inverso é proibido.

```
Anel N → Anel N-1 → ... → Anel 0   ✓
Anel 0 → Anel 1                     ✗
```

**P3 — Propriedade semântica isolada.**
Cada responsabilidade pertence a exatamente um anel. Conceitos não são
duplicados entre camadas.

**P4 — Estabilidade cresce para dentro.**
Quanto mais próximo do centro, mais conservadora é a evolução esperada.
Camadas externas podem mudar rapidamente. O núcleo muda com cautela.

---

<a id="section-modelo-de-aneis"></a>

## Modelo de anéis

A partir do Anel 3 o crescimento segue **duas trilhas paralelas** que compartilham
os anéis internos (0–2) e se reencontram no ML:

- **Trilha Analítica** (linha matemática): Matrix → Tensor → ML.
- **Trilha de Projeto** (linha de construção de aplicações): Persistence → Models.

Conectividade (Anel 3) e os anéis externos de ferramentas/interação servem às duas.

```
Anel 0  Núcleo C           buffers, memória, tipos, primitivas, engine
Anel 1  Abstrações          Series, DataSet alinhado, operações elementares
Anel 2  Op. Relacionais     join, groupby, reshape sobre DataSet
Anel 3  Conectividade / I/O CSV, JSON, + conectores externos (SQL, Excel, Parquet)

        ── Trilha de Projeto ──        ── Trilha Analítica ──
Anel 4  Persistência                 Anel 6  Matrix
        .smg, save/load, snapshots            layout 2D denso, álgebra linear
Anel 5  Models                        Anel 7  Tensor
        schema, validação, CRUD local         N-dimensional, broadcasting axis-aware
                                       Anel 8  Machine Learning
                                               pipelines, treino/inferência

Anel 9  Interação — TUI, Studio, Web, Notebooks   (serve a todas as trilhas)
```

**Ponto de encontro:** o ML (Anel 8) consome o schema dos Models (Anel 5) e os
buffers contíguos do Núcleo (Anel 0). As duas trilhas convergem ali.

**Dependências (P2):** cada anel pode depender de anéis internos; nunca o inverso.
As duas trilhas dependem de 0–3; não dependem uma da outra (Matrix não conhece
Persistence, e vice-versa).

---

<a id="section-anel-0-nucleo-computacional-done"></a>

## Anel 0 — Núcleo Computacional `[Done]`

Mecanismos fundamentais de execução. Máxima estabilidade, mínimo conhecimento
externo. Não conhece Series, DataSet, CSV, SQL, modelos nem interfaces.

**Responsabilidades:**
- Gerenciamento de memória (alloc, grow, free)
- Estruturas de armazenamento colunar (f64, i64, bool, string offset-based)
- Ownership, views, Copy-on-Write
- Máscaras de nulidade (null bitmask uniforme)
- Operações primitivas (aritmética, comparações, sort, filter, take)
- Contratos defensivos — toda fronteira pública valida e comunica o resultado

**Não conhece:** Series, DataSet, CSV, SQL, modelos, interfaces.

Anel é responsabilidade, não linguagem ou diretório: parsers e writers C de
CSV/JSON pertencem ao Anel 3 e consomem primitivas do núcleo. Sua presença em
`src/` não os transforma em mecanismos do Anel 0. A fronteira `smaug_table_t`
pertence ao I/O; os buffers colunares utilizados por ela pertencem ao núcleo.

**Evolução prevista `[Concept]`** — o Núcleo fechou para o que a v1.0 precisa, não
para sempre. A Trilha Analítica (Anéis 6–8) pressiona o runtime em quatro frentes,
todas *dentro* do Anel 0 porque são mecanismo, não semântica:

- **Alocação especializada** — arenas e pools. Hoje cada série aloca por conta
  própria; um grafo de tensores com milhares de temporários intermediários torna
  isso caro. Arena por escopo de execução resolve, e é a única frente que
  provavelmente vira necessidade antes das outras.
- **SIMD** — os laços element-wise do Anel 0 são vetorizáveis por natureza. Hoje
  dependem do auto-vetorizador do compilador; intrínsecos explícitos são um passo
  possível, com o custo de virar código por arquitetura.
- **Paralelismo** — o Anel 0 já é reentrante por contrato (Contrato 11), o que é
  pré-requisito. Falta o scheduler. Note que **o LuaJIT é single-thread**: o
  paralelismo teria de viver inteiro no C, com o Lua orquestrando, nunca
  participando.
- **Abstração CPU/GPU** — a de maior custo e a que mais muda o modelo mental
  (memória de host × device, assincronia, streams). Ver a nota sobre dependências
  na seção *Princípios da Trilha Analítica*.

---

<a id="section-anel-1-abstracoes-de-dados-done"></a>

## Anel 1 — Abstrações de Dados `[Done]`

Transforma mecanismos do Anel 0 em estruturas semânticas. Define a forma
como usuários interagem e raciocinam sobre dados.

**Responsabilidades:**
- `Series` — coluna tipada 1D com null handling. Dtypes **Tier 1** (com backend
  C, um descritor por tipo): `float64`, `int64`, `bool`, `string`, `datetime`.
  Dtype **Tier 2** (Lua puro, sem backend C, construído sobre os Tier 1):
  `CategoricalSeries` (dictionary encoding — códigos + níveis).
- `DataSet` — coleção de Series alinhadas
- Filtros, agregações, ordenação, transformações elementares
- Ergonomia Lua: açúcar sintático, metamétodos, accessors `.str` / `.dt` / `.cat`

**Dependência:** Anel 1 → Anel 0.

---

<a id="section-anel-2-operacoes-relacionais-done"></a>

## Anel 2 — Operações Relacionais `[Done]`

Completa o modelo tabular com operações que transformam conjuntos de linhas
em novos DataSets. Pertence ao Anel 2 — não ao I/O — porque depende apenas
do Anel 1. GroupBy/Join são o coração do DataFrame.

**Responsabilidades:**
- GroupBy + agregações (sum/mean/count/min/max por grupo)
- Join / Merge (inner, left, right, outer)
- Window functions (rolling, cumulative)
- Concat (vertical e horizontal)
- Pivot / Melt

**DSL encadeável** (propriedade emergente do design eager):
`ds:filter(...):groupby(...):sum()` e `ds:join(other, "k"):sort_by("v")` funcionam
porque essas composições oferecem os retornos apropriados; `groupby` produz
um objeto agrupado e sua agregação produz o DataSet seguinte. Não há promessa
de que toda operação da biblioteca retorne DataSet.

**Dependência:** Anel 2 → Anel 1 → Anel 0.

---

<a id="section-anel-3-conectividade-i-o-done-v1-0"></a>

## Anel 3 — Conectividade / I/O `[Done — v1.0]`

Integra o ecossistema com fontes externas de dados. Transporta dados — não
define semântica, não define persistência, não define regras de negócio.

**Versões e dependências externas:**

| Formato | Versão | Dependência | Status |
|---|---|---|---|
| CSV | **1.0** | nenhuma — parser próprio | `[Done]` |
| JSON | **1.0** | nenhuma — parser próprio | `[Done]` |
| NDJSON | **1.2** | nenhuma | `[Planned]` |
| SQLite | **1.5** | libsqlite3 | `[Planned]` |
| Excel `.xlsx` | **1.5** | zlib + XML | `[Planned]` |
| Parquet / Arrow | **futuro** | — | `[Concept]` |

**Princípio de zero-dependências no 1.0:** CSV e JSON são parsers escritos do
zero. Nenhuma biblioteca externa no 1.0. A linha de versão passa exatamente
onde a independência do núcleo seria quebrada.

**Fronteira `smaug_table_t`:** todo leitor produz `smaug_table_t`, todo escritor
parte de um `DataSet`. Adicionar um novo formato é implementar um plugue — sem
tocar no núcleo nem nos anéis internos.

**Contrato P5 (ativo desde v1.0):**
```
Fonte externa → Conectividade → DataSet   (carregar)
DataSet → Conectividade → Destino         (exportar)
```

**Dependência:** Anel 3 → Anel 2 → Anel 1 → Anel 0.

---

<a id="section-anel-4-persistencia-concept"></a>

## Anel 4 — Persistência `[Concept]`

Trilha de Projeto. Faz dados sobreviverem ao fim do processo. **Não é um banco
de dados nem um ORM** — é serialização de estruturas Smaug.

**Responsabilidades:**
- Formato binário próprio (`.smg`): header (magic, versão, schema) + buffers por
  coluna + máscara de nulos
- `df:save("vendas.smg")` / `smaug.load("vendas.smg")`
- Snapshots
- Reader defensivo: arquivo truncado/corrompido/versão futura → erro claro, nunca
  crash (o engine não confia no arquivo, como não confia no caller)

**O que NÃO é (Fronteira encerrada):** ORM relacional, query builder, engine de
migração estilo Alembic. Quem precisa de banco relacional usa SQLite via Anel 3.
Persistência aqui responde *"como meu DataSet sobrevive ao processo?"* — não
*"como modelo estruturas relacionais que evoluem?"*.

**Distinção fundamental:**
- Conectividade (Anel 3) responde: *como os dados entram e saem?*
- Persistência (Anel 4) responde: *como um DataSet é serializado e recarregado idêntico?*

**Reuso:** aproveita os buffers contíguos do Anel 0 — salvar é, no essencial,
dump do buffer + cabeçalho de schema.

**Dependência:** Anel 4 → Anel 3 → Anel 2 → Anel 1 → Anel 0.

---

<a id="section-anel-5-models-concept"></a>

## Anel 5 — Models `[Concept]`

Trilha de Projeto. Camada de schema sobre os dados do próprio Smaug. **Não é ORM
relacional e não é persistência** — é uma camada própria que responde *"qual é a
forma e o contrato do meu dado?"*.

**Responsabilidades:**
- Schema nomeado: `smaug.Model("Pedido", { id="int64", valor="float64", uf="string" })`
- Validação, constraints, defaults, documentação do dado
- CRUD sobre DataSet **em memória** (create/update/delete/filter)
- Persistência delegada ao Anel 4 (`model:save()` / `Model.load(...)`)

**O que NÃO é (Fronteira encerrada):** sem transação, sem índice, sem
concorrência. Quem precisa disso usa SQLite via Anel 3. O Model opera sobre
DataSets em memória e persiste via serialização — não é um engine transacional.

**Papel na arquitetura:** é o contrato entre "os dados" e "o pipeline". Quando o
ML (Anel 8) precisa saber o que é feature, target, tipo de cada coluna e política
de nulo, essa informação mora no Model — não em convenção solta. Por isso Models
é fundação da Trilha Analítica também: **é onde as duas trilhas se encontram.**

**Dependência:** Anel 5 → Anel 4 → ... → Anel 0.

---

<a id="section-anel-6-matrix-concept"></a>

## Anel 6 — Matrix `[Concept]`

Trilha Analítica. Tipo matricial 2D denso, distinto do `DataSet` heterogêneo.

**Responsabilidades:**
- Layout 2D denso sobre buffer contíguo (a porta que o Bloco G mantém aberta)
- Reduções por eixo, normalização
- **Álgebra linear**: operações no estilo BLAS (produto matricial, produto
  externo, triangulares), decomposições (LU, QR, Cholesky, SVD)
- **FFT** e convoluções, quando houver caso de uso real que as justifique
- **Esparso** como representação alternativa — decisão a tomar quando chegar:
  formato próprio (CSR/CSC) ou fora de escopo

**Regra arquitetural:** Matrix consome buffers do Núcleo. O DataSet não conhece
Matrix.

**Onde a decisão fica difícil:** produto matricial é a operação mais otimizada da
história do software. Um `gemm` honesto escrito à mão roda ordens de magnitude
abaixo de uma BLAS madura. Ver *Princípios da Trilha Analítica* — a regra é ser
dono da estrutura, não da aritmética.

---

<a id="section-anel-7-tensor-concept"></a>

## Anel 7 — Tensor `[Concept]`

Trilha Analítica. Generalização N-dimensional do Matrix, e onde mora a máquina
que torna a diferenciação automática possível.

**Responsabilidades:**
- Tensores N-dimensionais
- Broadcasting axis-aware (pertence aqui, **não** ao Anel 1 — Fronteira encerrada)
- **Motor de forma**: shape, strides, layout. É o que faz `view`, `reshape`,
  `transpose` e slicing serem O(1) em vez de cópia — a mesma tese do COW do Anel
  0, um nível acima
- **Grafo computacional**: representação, execução, e — se houver ganho medido —
  fusão de operações e execução preguiçosa
- **Autograd**: reverse mode (o que serve treino), tape, operadores customizados.
  Forward mode e checkpointing entram só se houver caso concreto

**Ordem interna:** o motor de forma vem antes do grafo, e o grafo antes do
autograd. Cada um é pré-requisito do seguinte, e cada um é útil sozinho — dá para
parar em qualquer ponto com algo que funciona.

---

<a id="section-anel-8-machine-learning-concept"></a>

## Anel 8 — Machine Learning `[Concept]`

Trilha Analítica. Transforma dados em modelos preditivos. **Ponto de encontro das
duas trilhas:** consome o schema dos Models (Anel 5) e os buffers do Núcleo.

**Regra arquitetural:** ML consome DataSets e Models. DataSets e Models não
conhecem ML.

**Lazy evaluation:** vem junto com ou depois do SQL (Anel 3 v1.5), porque o maior
ganho é o predicate pushdown sobre fontes externas.

O anel se divide em três blocos com **viabilidade muito diferente entre si** —
tratá-los como um só é o erro mais fácil de cometer aqui.

**8a. Preparação e ML clássico** — o mais próximo do que o Smaug já é.
- Pipelines de preparação (imputação, encoding, normalização) reusando primitivas
  do Anel 0; engenharia de atributos; análise exploratória e profiling
- `Dataset`/`DataLoader`, transforms, batching, métricas, avaliação
- Regressão, árvores, SVM, k-means, PCA — precisam de **Matrix e otimização
  simples**, não de autograd

**8b. Treino de redes neurais** — depende do autograd (Anel 7) e é onde o custo
salta.
- Losses, callbacks, laço de treinamento
- Otimizadores: SGD, momentum, Nesterov, RMSProp, Adagrad, Adam, AdamW; Adafactor
  quando o tamanho do modelo justificar
- Camadas: Dense, Conv1D/2D/3D, Embedding, BatchNorm, LayerNorm, RMSNorm, Dropout,
  Pooling, Multi-Head Attention, Feed-Forward, Positional Encoding. Mixture of
  Experts é etapa muito posterior, se houver
- **Sem paralelismo e sem GPU (Anel 0), treinar deixa de ser lento e passa a ser
  inviável** para qualquer modelo além do didático. Isso não é opinião sobre
  ambição; é aritmética de tempo de parede.

**8c. Inferência** — o bloco onde o Smaug tem vantagem real, e não derivada.
- Carregamento e serialização de modelos, importação/exportação de pesos
- Execução otimizada, quantização (INT8, INT4; FP8 no futuro), KV cache para
  Transformers
- Geração autoregressiva e estratégias de decodificação (greedy, top-k, top-p,
  beam search); tokenizer, vocabulário, embeddings
- LoRA e outros métodos de ajuste fino eficiente ficam na fronteira entre 8b e 8c

**Por que 8c é diferente dos outros dois:** inferência não precisa de autograd,
não precisa de treino distribuído e tolera muito melhor a ausência de GPU. Um
runtime em C, sem dependências, com pegada pequena e verificação forte roda onde
um stack Python não roda — dispositivo restrito, ambiente sem instalação
possível, contexto auditável. É a única parte desta trilha em que "o Smaug faz
melhor" é uma frase defensável em vez de aspiracional.

**Visão computacional** entra como aplicação sobre 8a e 8c: processamento básico
de imagem, transformações geométricas, filtros, augmentations, datasets — com
interoperabilidade direta com Tensor, sem tipo de imagem paralelo.

---

<a id="section-anel-9-interacao-e-ferramentas-concept"></a>

## Anel 9 — Interação e Ferramentas `[Concept]`

Mecanismos de interação humana e observabilidade. Interfaces e ferramentas
consomem serviços — não definem lógica de negócio nem semântica de dados.

**Responsabilidades:**
- TUI, Studio (Smaug|Vialactea Studio)
- Rich console: `describe`, `explain`, inspeção de schema; profiling; debug
- Dashboards, integrações com notebooks, exploradores visuais
- **Ferramental de engenharia**: profiler, suíte de benchmark, testes de
  regressão de desempenho, documentação automática, sistema de plugins,
  compatibilidade entre versões, testes diferenciais contra implementações de
  referência

**Nota sobre benchmark:** há medições pontuais no Roadmap, mas falta uma suíte
sistemática de regressão de desempenho. A verificação de correção também tem
lacunas documentadas na auditoria de 2026-09-18. Decisões de otimização (SIMD,
BLAS externa, fusão de operações) precisam de medições reproduzíveis; cobertura
de ramos não deve ser apresentada como MC/DC.

---

<a id="section-principios-da-trilha-analitica"></a>

## Princípios da Trilha Analítica

Decisões tomadas **antes** de começar os Anéis 6–8, porque são caras de reverter
depois e porque cada uma responde a uma tentação previsível.

**1. "Zero dependências" é regra do Anel 0, não doutrina global.**
A régua de versões abaixo já diz isto — a v1.5 introduz libsqlite3/zlib. O Núcleo
não depende de nada porque é o que garante que o Smaug compile em qualquer lugar
com um compilador C11. Anéis externos podem depender, desde que a dependência
seja *opcional* e exista caminho de referência sem ela. GPU cai nesta regra.

**2. Ser dono da estrutura, não da aritmética.**
O núcleo é dono de tensor, forma, strides, layout, propriedade de memória e ciclo
de vida — é isso que define o projeto e é onde o esforço próprio compensa. BLAS,
CUDA e afins entram como **aceleradores plugáveis**, atrás de uma interface, com
implementação de referência em C que sempre funciona.

O critério que separa as duas: *reinventar para entender* é legítimo (autograd,
camadas, o grafo — refazer é o mecanismo de aprender como funcionam);
*reinventar o que já foi vencido* não é (um `gemm` competitivo é décadas de
trabalho de gente que faz só isso). A pergunta prática é: se eu escrever isto à
mão, aprendo algo que não aprenderia lendo a especificação?

**3. Treino e inferência não têm a mesma viabilidade.**
Ver Anel 8. Treinar exige paralelismo, GPU e escala; inferência compacta não
exige nada disso e é onde a pegada pequena e a verificação forte viram vantagem.
Tratar os dois como "ML" esconde essa diferença.

**4. A ordem é comer antes de crescer.**
Corpus e ETL antes de modelo. Digitalizar, limpar, normalizar e tokenizar é
trabalho de Anéis 1–3 — que já existem. Um corpus bem construído é reutilizável
em qualquer direção posterior; um modelo mal treinado sobre dado ruim não é
reutilizável em nenhuma.

**5. Ordem de dependência não é ordem de valor.**
A trilha tem ordem técnica obrigatória (runtime → Matrix → Tensor → grafo →
autograd → redes). Mas construir nessa ordem significa anos antes que qualquer
coisa seja usável. Cada anel deve entregar algo utilizável sozinho: Matrix serve
estatística e álgebra sem tensor; Tensor serve manipulação N-d sem autograd;
8a serve ML clássico sem redes neurais.

**Critério de verificação da trilha.** Um alvo concreto e falsificável vale mais
que um inventário de capacidades: **resolver os exemplos e exercícios do *Mãos à
Obra: Aprendizado de Máquina com Scikit-Learn, Keras & TensorFlow* usando apenas
o Smaug**. O livro se divide onde a arquitetura também se divide — os capítulos
de ML clássico exercitam 8a (Matrix, otimização simples, pipelines de dados) e os
de redes neurais exercitam 8b (autograd, camadas, otimizadores). Chegar ao fim da
primeira metade já é marco pleno, e é o ponto natural para reavaliar se a segunda
compensa.

**Sobre escala, honestamente.** O análogo mais próximo desta trilha em C com
poucas dependências é o `ggml`: ~30 mil linhas, focado em inferência, sem autograd
genérico. Os anéis 0–3 do Smaug somam ~18 mil linhas de implementação com
~22 mil de teste. A trilha completa — treino, autograd, GPU, visão — é escala de
framework consolidado, não de projeto solo. Isto não é argumento para não fazer;
é argumento para fatiar, medir e manter cada fatia útil sozinha, que é a
disciplina que o projeto já pratica nos anéis internos.

---

<a id="section-regua-de-versoes"></a>

## Régua de versões

| Versão | Marco | Critério |
|---|---|---|
| **1.0** | DataFrame library completa | Anéis 0+1+2+3 + estatística robusta + dtypes `datetime`/`categorical` + transformações vetorizadas. Zero dependências externas. |
| **1.5** | Conectividade avançada + Lazy + Persistência | SQLite, Excel, Parquet/Arrow, `lazy execution`, driver de banco (`connect`/`query`/`execute`). Serialização `.smg` (Anel 4). Primeira dependência externa (libsqlite3/libpq, zlib). |
| **2.0** | Models | Schema, validação, CRUD local, save/load via Anel 4. Anel 5. |
| **2.x+** | Trilha Analítica | `Matrix` (Anel 6), `Tensor` + broadcasting axis-aware (Anel 7), ML e pipelines (Anel 8). |

*A numeração de versões não espelha 1:1 a de anéis — a v1.5 entrega tanto
conectividade (Anel 3 estendido) quanto serialização (Anel 4), porque ambas são
da Trilha de Projeto e dependem de infra externa.*

---

<a id="section-regra-de-decisao-arquitetural"></a>

## Regra de decisão arquitetural

Toda nova funcionalidade deve responder:

> *Qual é o anel mais interno capaz de resolver este problema sem violar
> a separação de responsabilidades?*

A implementação ocorre nesse anel — nunca mais profundamente do que o necessário.

---

<a id="section-estado-da-verificacao-revisao-de-2026-09-18"></a>

## Estado da verificação — revisão de 2026-09-18

A arquitetura define responsabilidades e garantias exigidas. A auditoria
[parecer do rework](TEST_SUITE_REWRITE_REVIEW.md) registra o alcance das evidências disponíveis;
o inventário [inventário de exclusões](TEST_SUITE_EXCLUSIONS_REVIEW.md) registra a triagem das exclusões.
Nenhum quadro arquitetural certifica toda a árvore como correta ou selada.

| Área | Evidência e pendência |
|---|---|
| Contratos defensivos, máscaras e COW | Garantias em `CONTRACT.md` e `COW.md`; completar matriz por dtype, falha e lifetime |
| Testes C/Lua | 13 suítes C e 20 Lua na auditoria; execução verde no Windows, com lacunas funcionais demonstradas em R01–R03 |
| OOM e rollback | Injeção existente; enumeração e oracles incompletos (R03), sem comprovação de todos os pontos públicos |
| Propriedades e mutação | Mutações diagnósticas revelaram falsos negativos (R01); campanha sistemática pendente |
| Cobertura | Relatório histórico de outra revisão; baseline bruta integral atual pendente (R04) |
| Exclusões | 153 marcações inventariadas, sem aprovação automática; sete refutadas (R05) |
| Reentrância e ABI | Contratos exigidos; verificadores atuais têm lacunas (R06) |
| Runners e artefato FFI | Precisam invalidar execução incompleta e fixar o artefato carregado (R07) |
| Memória e plataformas | Resultados antigos não certificam a árvore atual; campanha Linux, sanitizers e Valgrind pendente |
| Fixtures | Cinco inventariadas; consumidores e expectativas independentes precisam de rastreabilidade (R08) |
| Fuzzing e concorrência | Campanha pendente; ausência não equivale a sucesso |

Medições devem identificar árvore, plataforma, ferramentas, flags e artefatos.
Cobertura de ramos não é MC/DC. Dados históricos permanecem históricos até nova
execução verificável; contagens não são atualizadas por estimativa.

---

[Referência do Núcleo C](API_Reference.md) · [Rework da suíte](TEST_SUITE_REWORK.md) · [Início da documentação](README.md)
