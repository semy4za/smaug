# Smaug — arquitetura

[Documentação](README.md) · [Contrato](CONTRACT.md) · [Roadmap](Roadmap.md)

Este documento define responsabilidades e direção de crescimento. Entregas,
revisões e checkpoints pertencem ao roadmap. Funcionalidade existente não
significa contrato integralmente verificado.

<a id="section-principios"></a>
## Princípios

- **P1:** crescer por anéis externos, sem transferir suas políticas ao núcleo.
- **P2:** dependências fluem para dentro; o núcleo não depende do frontend.
- **P3:** cada responsabilidade semântica tem um único dono.
- **P4:** estabilidade e cautela aumentam em direção ao núcleo.
- **P5:** fonte → conectividade → DataSet; DataSet → conectividade → destino.

Anel é responsabilidade, não linguagem ou diretório. Um parser CSV escrito em
C continua no Anel 3. Converter um slice numérico é mecanismo; decidir dtype,
dialeto e o significado de um token no arquivo é política do leitor.

<a id="section-modelo-de-aneis"></a>
## Base existente — anéis 0–3

| Anel | Responsabilidade | Fronteira |
|---|---|---|
| 0 — núcleo C | Buffers colunares, alocação, máscaras, ownership, views/COW e operações primitivas | Não conhece DataSet, CSV, SQL, modelos ou interface |
| 1 — abstrações | Series, DataSet alinhado, categorical, filtros, agregações e ergonomia Lua | Dá significado tabular aos mecanismos |
| 2 — relacional | Join, groupby, concat, pivot/melt e operações de janela | Trabalha sobre abstrações de dados, independente de formato |
| 3 — conectividade | Leitura/escrita CSV e JSON, gramática e adaptação de formatos | Transporta dados; não define persistência do projeto |

O schema reutilizável é uma descrição neutra compartilhada, não um novo anel.
Seu descritor e sua validação básica (`smaug_schema.c`) permanecem compatíveis
com o Anel 0: não conhecem DataSet, CSV, JSON, `.smg` ou Models. A aplicação do
descritor durante a leitura (`smaug_io_schema.c`) pertence ao Anel 3 e usa os
tokenizadores/conversores de cada formato. O Anel 1 expõe o construtor Lua e
recebe o DataSet; a persistência do Anel 4 e Models do Anel 5 poderão consumir
o mesmo descritor quando forem implementados. Assim as dependências continuam
fluindo para dentro, sem fazer o núcleo conhecer políticas de formato ou
persistência.

<a id="section-anel-0-nucleo-computacional-done"></a>
### Núcleo e fronteira pública

Valida argumentos e comunica erros conforme cada API. Reentrância é exigida
para objetos independentes; não promete mutação simultânea segura de um mesmo
objeto. A estrutura e os canais de falha estão no [contrato](CONTRACT.md), e
ownership/detach em [COW](COW.md). Arenas, SIMD, scheduler e backend CPU/GPU só
entram mediante necessidade medida, preservando semântica e lifetime explícitos.

<a id="section-anel-1-abstracoes-de-dados-done"></a>
### Abstrações

float64, int64, bool, string e datetime usam backend C. Categorical é composto
no Lua por códigos e níveis. Series é 1D; DataSet reúne colunas alinhadas.
Accessors `.str`, `.dt` e `.cat` organizam operações, sem criar outro motor.
Inferência, validação de dtype fixado e conversão explícita são responsabilidades
distintas; uma rotina comum não deve apagar seus contratos.

<a id="section-anel-2-operacoes-relacionais-done"></a>
### Relacional

Encadeamento resulta dos retornos definidos por cada operação: groupby produz
objeto agrupado; a agregação produz DataSet. Não se presume que toda função
retorne DataSet. Ordem, multiplicidade, chaves compostas e NA exigem contrato
e testes próprios, independentemente do mecanismo de armazenamento.

<a id="section-anel-3-conectividade-i-o-done-v1-0"></a>
### Conectividade e FFI

CSV/JSON têm parsers próprios. `smaug_table_t` é estrutura de transporte do
I/O; os buffers que ela contém usam o núcleo. A ponte Lua traduz DataSet e
tabela C, preservando bytes, precisão, máscara e ownership. FFI espelha layout
e assinaturas; não deve reinventar parsing ou inferência.
Novos conectores devem usar essa fronteira. Dependências externas podem ser
opcionais por formato, sem se tornarem dependências do runtime do núcleo.

<a id="futuro"></a>
## Visão futura — duas trilhas

Persistência → Models e Matrix → Tensor → ML crescem sobre a base 0–3.
Matrix não depende de persistência. ML pode consumir schema de Models e dados
das abstrações; estas não conhecem ML. Interfaces atendem ambas as trilhas.
Os itens abaixo são conceitos, sem release ou prazo comprometido.

<a id="section-anel-4-persistencia-concept"></a>
### 4 — Persistência

Direção aprovada em 2026-09-29: schema reutilizável entre os consumidores do
Smaug, com implementação inicial em CSV/JSON. A descrição dos dados é separada
das opções de importação; seu uso no anel 3 não cria dependência de persistência
ou Models. Compartilhamento concreto de tipos/módulos será definido no desenho
da API. Escopo e pendências no [contrato](CONTRACT.md#schema-reutilizavel).

`.smg` é contêiner nativo versionado de trabalho editável: DataSets, schema,
buffers, máscaras e metadata; posteriormente fontes, etapas, parâmetros e
snapshots. Começar por um DataSet e crescer para projeto. Reader deve rejeitar
truncamento, corrupção e versão incompatível; migrações são explícitas.
Exportar CSV/JSON é conectividade; reabrir o trabalho é persistência.

Orientação de implementação: manter C como padrão também no `.smg`. C++ é
uma alternativa possível, não uma escolha aprovada nem requisito. Sua adoção
só deve ser considerada diante de necessidade concreta e benefício justificado,
com avaliação do impacto em build, runtime, portabilidade e fronteira C/Lua.

<a id="section-anel-5-models-concept"></a>
### 5 — Models

Schema, validação, constraints, defaults e CRUD sobre DataSet em memória;
persistência delegada ao anel 4. Transações, índices e concorrência de banco
ficam fora desse conceito. Model descreve features, targets, tipos e nulidade
para consumidores como pipelines de ML, sem depender deles.

<a id="section-anel-6-matrix-concept"></a>
### 6 — Matrix

Tipo 2D denso: layout, reduções por eixo, normalização, produtos e decomposições
LU/QR/Cholesky/SVD. Consome buffers do núcleo; DataSet não conhece Matrix.
Esparso, FFT e convoluções dependem de caso de uso. Layout e contrato próprios,
com possibilidade de BLAS como backend opcional.

<a id="section-anel-7-tensor-concept"></a>
### 7 — Tensor

N dimensões, shape, strides, views, reshape, transpose e broadcasting por eixo.
Broadcasting multidimensional pertence aqui. Ordem de construção: motor de
forma → grafo de execução → autograd reverso; cada estágio deve ser útil sozinho.
Fusão, lazy, forward mode e checkpointing exigem benefício demonstrado.

<a id="section-anel-8-machine-learning-concept"></a>
### 8 — Machine Learning

Três escopos separados: preparação/ML clássico (Matrix e otimização simples),
treino de redes (autograd, losses, otimizadores) e inferência (pesos/layouts,
execução compacta). Escala pode exigir paralelismo/GPU. Quantização, KV cache,
tokenizadores e decodificação são projetos posteriores; imagens usam tensores,
sem representação concorrente. Pipelines de preparação reutilizam o tabular.

<a id="section-anel-9-interacao-e-ferramentas-concept"></a>
### 9 — Interação e ferramentas

TUI, Studio, web e notebooks consomem APIs públicas. Observabilidade,
benchmarks, diagnóstico e extensões não duplicam regras de negócio.

<a id="section-principios-da-trilha-analitica"></a>
## Critérios de expansão

Manter referência CPU em C, sem dependências obrigatórias no núcleo; aceleradores
opcionais precisam concordar com essa referência. Ser dono de estruturas,
contratos e lifetime não exige reimplementar toda biblioteca de álgebra.
Primeiro tornar ETL e corpus verificáveis; depois acrescentar cada estágio
analítico com exemplos reproduzíveis. O objetivo didático não substitui
verificação de valores, memória e custo.

<a id="section-regua-de-versoes"></a>
<a id="section-regra-de-decisao-arquitetural"></a>
<a id="section-estado-da-verificacao-revisao-de-2026-09-18"></a>
Versões e sequência de entrega serão decididas no [roadmap](Roadmap.md).
Antes de criar um módulo, identificar responsabilidade, consumidores, contrato,
ownership, falhas observáveis e evidência. Uma linguagem ou otimização não
justifica inverter dependências ou duplicar semântica entre anéis.
