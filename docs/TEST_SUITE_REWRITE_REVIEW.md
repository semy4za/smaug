# Parecer técnico — reconstrução da suíte de verificação do Smaug

Data: 2026-09-18. Estado: **proposta para aprovação; implementação não iniciada**.

Árvore avaliada: HEAD `9787701`, com alterações locais de padronização já existentes. O commit sozinho não identifica essa árvore modificada. As referências de linha deste parecer são as observadas nesta avaliação.

## 1. Decisão recomendada

Reconstruir o sistema de verificação inteiro, orientado por contratos e capacidade demonstrada de detectar defeitos: testes C/Lua, propriedades, parity, fixtures, injeção de falhas, executores, cobertura e documentação das evidências.

Não recomendo apagar tudo primeiro. Recomendo uma **reescrita completa de responsabilidade, executada incrementalmente por família**: cada cenário existente recebe destino explícito — manter, fortalecer, substituir, fundir ou retirar com justificativa. O teste antigo só sai quando o substituto estiver validado. Isso preserva regressões úteis sem tornar o comportamento atual da implementação a especificação da nova suíte.

Critério central: um teste precisa distinguir o comportamento correto de um defeito plausível. Executar uma linha, mencionar uma função, não crashar ou aumentar um contador são evidências diferentes e não devem ser apresentadas como equivalentes.

Não há motivo para conservar o número atual de checks, a distribuição dos arquivos ou um percentual histórico. A padronização de escrita já acordada permanece; não será uma nova campanha de renomeação.

## 2. Escopo, método e limites desta avaliação

Inventário: **13 suítes C, 20 suítes Lua, 15 eixos parity, 5 fixtures de dados e 153 marcações `COV-EXCL-BR` nos fontes atuais**. Incluem-se Makefile, build Windows/Linux, geração de cobertura e manifest, helpers e exceções de parity, contratos e documentação de testes/COW.

Nesta avaliação foram realizados:

- Leitura dos 15 eixos parity, helpers, exceções e executores; análise dos scripts de build, coverage e manifest.
- Inventário de todos os arquivos de testes e fixtures; revisão semântica dirigida por riscos e pelos falsos positivos encontrados na avaliação anterior.
- Recompilação da biblioteca e dos 13 testes C, seguida dos 20 testes Lua no Windows. Todos passaram: **450.104 verificações**. Registro local: `build/audit-current.json`.
- Execução individual dos 15 eixos parity, sem sobrescrever o relatório versionado.
- Mutações processuais em memória para avaliar testes e verificadores; nenhum fonte de produção ou teste versionado foi modificado para isso.
- Compilação de diagnóstico nativo com os fontes atuais e instrumentação gcov, para demonstrar alcançabilidade de ramos específicos. Isso não é uma nova medição da cobertura integral.
- Leitura e validação estrutural das cinco fixtures com parsers independentes da biblioteca; registro dos hashes.

Ambiente diagnóstico: Windows/MSYS2 UCRT64, GCC 16.1.0, LuaJIT 2.1.1779665312. Os scripts e binários experimentais ficaram em `build/`, que é descartável. As evidências necessárias estão resumidas aqui para o parecer não depender de conservar esse diretório.

**Limites:** esta é uma auditoria diagnóstica e um plano de reconstrução, não a certificação semântica de cada asserção existente. Não foi executada uma nova campanha Linux de cobertura integral, Valgrind, sanitizers, fuzzing ou concorrência. A aprovação deste parecer autoriza o trabalho proposto, não transforma essas verificações pendentes em concluídas.

## 3. Diagnóstico executivo

### R01 — Alto: suíte verde aceita erros de resultado

Evidências reproduzidas:

| Experimento | Resultado | Lacuna demonstrada |
| :--- | :--- | :--- |
| `view` substituída por `view(...):clone()` | Suíte de propriedades passa, 360.862 checks | `view_compartilha` compara valores, mas não testa compartilhamento |
| `inner join` substituído pelo resultado real limitado a zero linhas | Suíte de propriedades passa, 352.374 checks | Verifica apenas linhas presentes; não exige completude/multiplicidade |
| `drop_duplicates(..., "last")` executando `"first"` | `dataset/test_stat.lua` passa, 106 checks | Asserção observa grupo em que primeiro e último têm o mesmo valor |
| `get/set/is_null/set_null` aceitando índice Series e retornando normalmente | `series/test_selection.lua` passa, 75 checks | O sucesso de `pcall` não é rejeitado; só se procura vazamento de dados no texto |
| `take` substituído pela identidade | Suíte de propriedades falha em `groupby_sum_consistente` | Controle positivo: o experimento também detecta mutações; não é um harness que sempre passa |

Referências: `tests/props/test_props.lua:101,158,348,407,458`, `tests/dataset/test_stat.lua:154`, `tests/series/test_selection.lua:58`. O cenário de `last` também aparece em `tests/series/test_predicates.lua:491`.

Estas mutações provam lacunas nas suítes indicadas, não que todas as outras suítes deixariam escapar o mesmo defeito. `groupby_sum_consistente` e `unique_ordem_aparicao` também precisam verificar completude: seus loops de validação permitem zero iterações se o resultado vier vazio.

### R02 — Alto: duas divergências reais de datetime escapam à suíte

1. `2023-01-01`: `smaug_dt_week` devolve **53**, mas a semana ISO é **52**. O teste em `tests/c/test_datetime_c.c:838` aceita 52 **ou** 53. A expectativa foi conferida independentemente com `datetime.isocalendar()`; o resultado foi reproduzido em executável recompilado dos fontes atuais.
2. `smaug_dt_from_parts_checked(-2, 3, 1, 0, 0, 0, 0, &epoch)` retorna `SMG_OK`, produzindo `-62225193600000`. `smaug_dt_year(epoch)` devolve `-2`; `smaug_dt_year_series` produz elemento nulo (`SMG_NULL_VALUE`). O guard `v >= 0` rejeita anos negativos válidos na representação aceita pelo próprio construtor.

A anotação em `src/smaug_datetime.c:645,654` afirma que o ramo falso não acontece. O diagnóstico refuta isso para `year`. A política de anos negativos e a colisão entre ano `-1` e sentinela precisam ser explicitadas; o comentário da implementação não deve decidir sozinho o contrato. A semântica ISO já está prometida no header, portanto devolver sempre 53 na passagem ao ano anterior não é uma expectativa aceitável.

### R03 — Alto: injeção de falhas não comprova toda a promessa de OOM

`tests/c/test_allocfail.c` tem pontos fortes — intercepta quatro famílias de alocação e já exercita recuperação — mas parte dos casos só valida o resultado **se ele não for NULL**. Por exemplo, o caso de clone em torno da linha 92 não exige sucesso após ultrapassar os pontos de falha. O limite global `MAX_ALLOCS=12`, e limites de I/O como 64, não provam que todas as alocações de cada cenário foram enumeradas.

Em `tests/c/test_allocfail.c:1725`, `OK(!result || result->error || 1, ...)` é sempre verdadeiro. Em outros cenários, completar sem crash é uma observação legítima de robustez, mas não valida conteúdo, estado ou status e não deve ser contado como se validasse.

A nova campanha deve comprovar: baseline sem falha; número e identidade dos pontos exercitados; falha efetivamente injetada; resultado permitido pelo contrato; preservação do estado; cleanup e possibilidade de uso posterior. Falhar alocação não implica necessariamente falhar a operação: fallback bem-sucedido pode ser válido, desde que verificado. Falhas em rollback podem exigir duas falhas no mesmo cenário; uma única falha por rodada não basta para esse caso.

### R04 — Alto: o relatório de cobertura não é um selo confiável da árvore atual

O `docs/COVERAGE.md` versionado mede `51184cb`, datado de 2026-08-11: linhas 98,83%, branches brutos 92,22%, branch-alvo 94,95%, 139 ramos excluídos naquela execução. **Esses valores não medem a árvore atual.** As 153 marcações atuais são comentários nos fontes, não 153 ramos e não uma comparação direta com os 139 ramos históricos.

Problemas em `scripts/make_coverage.sh`:

- Linhas 103–105 ignoram falha de `gcov` e pulam arquivo cujo `.gcov` não apareceu. O denominador pode perder um fonte sem invalidar o relatório.
- Uma marcação em uma linha exclui **todos os ramos não tomados dessa linha**. Em uma linha com condição de negócio e tratamento de OOM, uma justificativa de OOM pode retirar também um caminho de negócio. Macros agravam essa imprecisão.
- O conjunto excluído depende dos ramos não executados no próprio run; não há registro estável de ramos aprovados independentemente do resultado.
- Só são agregados os arquivos `src/*.c`. Código executável em headers do projeto pode gerar cobertura própria e ficar fora da tabela. O diagnóstico produziu registros para `smaug_io_internal.h` e `smaug_str_internal.h`.
- A data vem do último commit, não do momento da medição; falta identificar dirty tree, versões, flags, entradas e binário carregado pelo Lua.
- A execução substitui `build/libsmaug.so` e a remove ao terminar, em vez de usar um artefato instrumentado isolado. Também descarta os dados brutos; isso dificulta reproduzir e auditar o número.
- O relatório chama cobertura de branches de **MC/DC** e usa analogias de certificação que o mecanismo não demonstra. `gcov -b` mede branches; MC/DC exige avaliação do efeito independente das condições e instrumentação apropriada. A documentação oficial do GCC distingue `-b` de `--conditions`/`-fcondition-coverage`: [Invoking gcov](https://gcc.gnu.org/onlinedocs/gcc/Invoking-Gcov.html).

Não foi recalculado um novo percentual global nesta avaliação. A primeira entrega deverá produzir uma baseline bruta íntegra, mesmo que fique abaixo da histórica.

### R05 — Alto: há exclusões comprovadamente incorretas

Diagnóstico nativo, sem forjar structs inválidas nem acessar ponteiros arbitrários:

| Local atual | Justificativa atual / pressuposto | Contraexemplo ou evidência |
| :--- | :--- | :--- |
| `smaug_datetime.c:65,83` | Ramos negativos só antes de aproximadamente 292 milhões a.C. | Ano `-2` aceito pela API; gcov registrou ambos os lados das decisões |
| `smaug_datetime.c:152` | `size > capacity` é invariante, pois `create()` nunca viola | A função pública `create_with_capacity(2,1)` alcança e rejeita o argumento |
| `smaug_datetime.c:645,654` | Componentes escalares nunca negativos | Ano `-2` produz componente escalar negativo e saída vetorizada nula |
| `smaug_json.c:114` | Inalcançável em JSON bem-formado | Buffer truncado no escape final alcança o ramo e devolve erro de parsing |
| `smaug_ops_window.c:685` | Corpo do cleanup de deque inalcançável | Série `[5, NA, NA]`, rolling max int64, janela 2, `min_periods=0`; corpo da linha 686 executou uma vez |

Outras justificativas precisam ser reabertas: OOM “sem injeção” numa campanha que possui injeção; guard redundante confundido com inalcançável; API pública chamada de interna; ausência de mock de syscall confundida com impossibilidade; “nunca quebrou em 400k checks” usada como prova; comparação de índice de argsort com pivô possivelmente igual, apesar de índices distintos no vetor.

Há também candidatos defensáveis: em `smaug_ops_bool.c:48`, após eliminar o caso de falso e exigir ambos válidos, `at && bt` é verdadeiro; em `smaug_str.c:486`, o contexto `len > old_len` com comprimentos não negativos implica `len > 0`. São argumentos locais verificáveis, diferentes de ausência empírica de falhas. Sua aprovação deve apontar o **ramo exato**, não excluir a linha inteira.

O inventário completo das marcações, com triagem e pendências, está em `TEST_SUITE_EXCLUSIONS_REVIEW.md`. A triagem não aprova automaticamente nenhuma exclusão.

### R06 — Alto: parity estático não demonstra suporte, ABI ou reentrância completos

Os eixos 1–13 são majoritariamente heurísticas textuais. Exemplos: dtype citado no corpo vira provável suporte; nome C citado vira exposição Lua; ocorrência de sentinela vira conformidade; ocorrência de `check(` e literais de dtype vira “cobertura”. Comentários, funções geradas e corpos indentados podem distorcer essas conclusões. O corpo extraído até a próxima `\nfunction ` pode incluir funções vizinhas quando as declarações são indentadas.

Experimentos em memória, alterando apenas a entrada textual do verificador:

- Acrescentar um campo ao cdef de `smaug_series_f64_t`: eixo 15 passa. Sua lista não inclui as structs f64 e i64.
- Acrescentar `int audit_mutable_global = 0;` a um fonte: eixo 14 informa zero globais e passa. Ele procura `static` em coluna zero, não todos os objetos de armazenamento estático/mutável.
- Simular fonte C ausente na leitura: eixo 14 trata o conteúdo como string vazia, mostra verde e passa.

O eixo 15 deve continuar existindo, mas com inventário completo, `sizeof`/alinhamento/`offsetof` produzidos pelo compilador e confrontados com o FFI; também enums, assinaturas e símbolos. Igualdade textual limitada não cobre toda a fronteira.

O eixo 14 deve analisar declarações e escopos, tratar dependências e arquivos ausentes como falha, e complementar a inspeção com execução concorrente sobre objetos independentes. Nenhum teste isolado comprova ausência universal de races; a confiança vem da combinação de contrato, revisão, análise e ferramentas adequadas.

### R07 — Alto: executores podem anunciar sucesso sem uma execução completa válida

- `scripts/build.ps1:142,158,172`: resultado C é decidido pelo texto `PASS`, sem exigir o código de saída do executável. Um processo que imprima `PASS` e termine com erro pode ser aceito nesse caminho.
- Builds permitem ausência de LuaJIT; o Linux também pode pular Valgrind/gcov solicitados e ainda imprimir “TUDO PASSOU”. Skip pode ser legítimo em perfil local, mas não deve equivaler a validação completa.
- Runners parity terminam com zero mesmo se um eixo falhar. No PowerShell, stdout do eixo que falha não é anexado ao relatório; justamente a tabela de achados pode desaparecer. Falhas precisam constar no artefato final, além do console.
- A contagem global de emojis inclui legendas e textos explicativos, não apenas resultados. Não é um número confiável de requisitos satisfeitos.
- Existem listas repetidas de testes no Makefile, build.sh, build.ps1, coverage e parity. O eixo 11 lista 18 suítes Lua e omite `core/test_keys` e `core/test_collation`.
- `build.sh` combina `set -e` com comandos que esperam inspecionar `$?` depois; falhas podem abortar antes da coleta prevista. Isso não cria aprovação indevida por si só, mas pode perder o diagnóstico.
- A carga FFI tem fallback para biblioteca instalada. Para testes, precisamos confirmar caminho/hash do artefato do run, não aceitar silenciosamente outra versão.

A reconstrução precisa testar os próprios runners: exit não zero com `PASS`, arquivo ausente, dependência ausente, zero casos, timeout, relatório parcial e cenário deliberadamente errado.

### R08 — Médio: fixtures e manifest não oferecem toda a rastreabilidade necessária

As cinco fixtures têm estrutura legível e consistente nesta leitura. Isso não prova que seus valores de referência estejam completos, independentes ou efetivamente usados.

| Fixture | Estrutura confirmada | Tratamento proposto |
| :--- | :--- | :--- |
| `pedidos_digitados.csv` | 916 registros, 15 campos por registro, 913 células vazias | Preservar como integração; documentar origem/licença/anonimização; adicionar expectativas independentes por coluna/grupo |
| `cotacoes.csv` | 26 registros, 4 campos por registro | Vincular explicitamente a cenários de precisão e comparação entre formatos |
| `cotacoes.json` | 26 records, quatro chaves | Comparar conteúdo/ordem/nulidade/tipos com oracle independente |
| `cotacoes_USD_BRL.json` | 13 records, três chaves | Registrar relação com a fixture combinada e resultado esperado |
| `cotacoes_SHIB_BRL.json` | 13 records, três chaves | Exercitar pequenos floats com tolerância justificada, não arredondamento arbitrário |

Nas referências literais das 33 suítes, só encontrei consumo explícito de `pedidos_digitados.csv`. As quatro fixtures de cotações não têm integração demonstrada nessa inspeção; não devem contar como proteção só por estarem no repositório.

O caso real tem checks úteis, mas roundtrips observam sobretudo dimensões e valores da primeira linha. Reader e writer podem compartilhar o mesmo erro. Precisamos validar a saída contra representação externa esperada e ler entradas não produzidas pelo próprio Smaug. A mensagem em `test_csv.lua:224` diz 256 enquanto a asserção exige 228 — exemplo de diagnóstico desatualizado.

`scripts/make_manifest.sh:65–68` não inclui `.csv`, `.json`, `.txt` ou `.py`: fixtures, exceções parity e o novo verificador de estilo ficam fora desse manifest. `make verify` regenera o manifest e mostra um diff, mas não é um verificador read-only que falha por divergência. Integridade e correção semântica devem continuar métricas separadas.

### R09 — Médio: duplicação e contratos contraditórios dificultam escolher o esperado

- `package.path` duplicado em quatro suítes; propriedade `str_filter_reduz` redefinida em `test_props.lua:305,324`, com a primeira definição sobrescrita.
- Há auxiliares duplicados e cenários DataSet dentro de suites Series. A organização precisa refletir a responsabilidade, sem simplesmente remover checks semelhantes que protegem camadas diferentes.
- `CONTRACT.md` defende testar guards públicos, mas admite OOM sem injeção como inalcançável; a campanha precisa distinguir as duas coisas.
- `CODE_REVIEW.md` ainda apresenta overflow como wrap aceito e resolvido; o contrato de status documentado não lista `SMG_ERR_OVERFLOW`. Isso conflita com a direção atual de erro explícito via C/FFI/Lua.
- `COW.md` descreve string view O(len), mas mantém afirmações genéricas de view O(1). Exceções parity ainda dizem que string não possui view.
- Datas, números de checks e conclusões históricas não devem ser apresentados como certificações da árvore atual.

Antes de escrever expectativas novas, registrar a decisão do projeto quando documentos e implementação discordarem. Nem o código atual nem pandas devem ser escolhidos automaticamente como verdade.

## 4. Como deve ser a nova arquitetura de verificação

### 4.1 Catálogo rastreável de contratos

Para cada operação pública e família interna relevante, registrar: identificador estável; camada; dtypes suportados e recusados; entrada; saída/shape/dtype/nulidade; ordem e multiplicidade; erros e status; efeitos colaterais; ownership; limites; oracle; casos associados; mutações que devem ser detectadas; plataforma; pendências.

Exemplo de obrigação: “`Series<int64>:add` preserva operandos e retorna resultado exato quando representável; quando não representável, propaga status C pelo FFI e lança erro Lua orientado”. O catálogo precisa distinguir esse contrato de APIs legadas e de divisão por zero. Não assumir que uma política de overflow resolve automaticamente os outros casos.

Um inventário de símbolos ajuda a encontrar omissões, mas não cria expectativas copiando a implementação. O contrato é revisado; os testes o exercitam; o código é comparado com ele.

### 4.2 Camadas com responsabilidades diferentes

| Camada | Evidência exigida |
| :--- | :--- |
| Helpers/núcleo C | Aritmética e limites exatos, status, máscaras, ownership, atomicidade observável em falha, pré-condições válidas e rejeições documentadas |
| Fronteira FFI | Layout real compilado, enums/símbolos/assinaturas, precisão int64, null/status, índice e lifetime/GC |
| API Lua | Resultado público completo, tipo/shape/ordem/nulidade, erro orientado, nenhuma coerção silenciosa e nenhuma mutação indevida |
| Relacional | Modelo de referência independente com todas as linhas e multiplicidades, chaves compostas, duplicatas, vazios e rejeição de NA em chave |
| I/O | Leitura e escrita verificadas separadamente; corpus válido/inválido; limites de buffer, codificação, opções, avisos, erros de arquivo e perdas permitidas |
| Propriedades/stateful | Modelo simples independente e sequências de operações; casos obrigatórios de borda além do aleatório; geração e reprodução controladas |
| Memória/robustez | OOM, rollback, sanitizers, Valgrind, stress e concorrência com objetivo declarado; nenhum deles substitui o oracle funcional |
| Infraestrutura | Runners, comparadores, geradores, parsers de relatório e exclusões com testes positivos e negativos próprios |

Compartilhar infraestrutura pequena — bootstrap, assertions, comparadores, diretório temporário e registro de casos — sem compartilhar a lógica de produção que deveria ser desafiada. Helpers também precisam falhar diante de resultados errados.

### 4.3 Oracles e dados

- int64: valores exatos, inclusive `INT64_MIN/MAX`, vizinhos de ±2^53, resultado válido igual à sentinela e overflow em intermediários. Nunca construir o esperado com a mesma operação C sob teste nem converter tudo para `number` Lua.
- Floats: tolerância absoluta/relativa ou ULP por algoritmo; tratar NaN, infinitos, signed zero e máscara separadamente. Uma tolerância única de `1e-9` não serve para toda a biblioteca.
- Calendário: tabelas independentes de datas/semana ISO/bissextos/offsets e um modelo verificado para o domínio adotado. Python datetime ajuda no domínio suportado por ele; não é oracle suficiente para anos negativos ou extremos int64.
- Estatística e janela: referências simples por varredura, distintas dos algoritmos otimizados; empates, ddof, cancelamento numérico, vazio, só-NA, janela maior que série e fronteiras de capacidade.
- Relações: modelo por listas/mapas com cardinalidade e multiplicidade completas; não apenas `nrows > 0` ou “toda linha retornada parece válida”.
- Comparação com bibliotecas externas: apenas nos contratos compatíveis, versões fixadas e diferenças documentadas. pandas pode auxiliar onde fizer sentido; não deve impor sua política de NA/NaN ou precisão ao Smaug.
- Fixtures mínimas e sintéticas para diagnóstico; casos reais preservados como integração. Cada fixture precisa de ID, propósito, schema, encoding, hash, procedência, consumidores e esperado independente. Mudança no golden exige revisão; não regenerar o esperado com o Smaug para fazer o teste passar.

## 5. Destino proposto de toda a suíte atual

Cada arquivo abaixo entra na revisão semântica da implementação. A tabela define responsabilidade e critério, não presume que tudo o que existe nele está errado ou ausente.

| Arquivo(s) atual(is) | Trabalho obrigatório |
| :--- | :--- |
| `c/test_alloc.c` | Construção, capacidade, vazio, clone e view; estado completo, rejeições e propriedade dos buffers |
| `c/test_allocfail.c` | Reconstruir enumeração/injeção e oracles de OOM; falhas simples e rollback; eliminar asserções tautológicas |
| `c/test_astype.c` | Matriz origem/destino, limites exatos, elementos inconversíveis e nulidade; separar perda permitida de bug |
| `c/test_bool.c`, `c/test_bool_lifecycle.c` | Tabelas-verdade Kleene completas, máscaras opcionais, lifecycle e mutação; preservar cenários fortes existentes |
| `c/test_cow.c` | Preservar checks úteis; completar matriz dtype × operação × estado × falha; pai/view/view de view, antes/depois de detach |
| `c/test_datetime_c.c` | ISO week, domínio temporal, escalares versus vetores, extremos, parse/format, status sem colisão com dado |
| `c/test_io_c.c` | Corpus de parsers/writers, especificações independentes, truncamento e buffer, inferência, erro e ownership |
| `c/test_ops.c`, `c/test_ops_edge.c` | Operações e bordas sob contrato explícito; conteúdo/status/máscaras, saídas inalteradas em erro, sem wrap usado como prova de ausência de UB |
| `c/test_ops_window.c` | Modelo de referência de janelas/cumulativas/multi-sort; null-path da deque, estabilidade e overflow |
| `c/test_stress.c` | Separar verificação funcional, estabilidade/memória e eventual desempenho; não chamar no-crash de correção completa |
| `c/test_string.c` | Comprimentos/offsets, vazio versus NA, bytes/NUL conforme contrato, ownership, COW e crescimento |
| `core/test_keys.lua`, `core/test_collation.lua` | Colisões e codificação de chaves, ordem e equivalência C/Lua; referência externa à mesma implementação |
| `series/test_constructors.lua` | Inferência/explícito, factories dedicadas, promoção, precisão, erros e estado inicial |
| `series/test_access.lua` | Índices, getters exatos, setters, validação antes do FFI, atomicidade e mensagens |
| `series/test_reduce.lua`, `series/test_stat.lua` | Referências de reduções/estatística, NA≠NaN, denominadores, empates e extremos |
| `series/test_window.lua` | Resultados completos de rolling/expanding/cum/diff/shift/fill e tipos; modelos separados do backend |
| `series/test_predicates.lua`, `series/test_selection.lua` | Máscaras, ordem/multiplicidade, empates/keep, erros efetivos; mover responsabilidade DataSet sem perder cenários |
| `series/test_str.lua` | Contratos de bytes/UTF-8/padrões, limites, nulidade, comprimentos e erros; corpus mínimo discriminante |
| `series/test_dt.lua` | Casos públicos do calendário e FFI, unidade/offset/timezone, domínio aceito, dtype/nulidade e mensagens |
| `series/test_categorical.lua` | Dicionário/codes, categorias ausentes, ordem, mutação, NA e retornos; assimetrias explícitas |
| `dataset/test_core.lua` | Alinhamento, seleção/transformação/reshape e preservação; schema e conteúdo completos |
| `dataset/test_relational.lua` | Join/groupby/concat/pivot com modelo independente; casos 1:1, 1:N, N:N, sem match, chave composta e colisões |
| `dataset/test_stat.lua` | Estatísticas por coluna e deduplicação com fixtures que distinguem todas as políticas |
| `dataset/test_io_support.lua` | Acesso 2-D, conversão/representação e inserção; retorno, ordem, erros e preservação |
| `io/test_csv.lua`, `io/test_json.lua` | Binding/opções/warnings e corpus externo; comparar todas as células relevantes, não só primeira linha |
| `props/test_props.lua` | Eliminar vacuidade/redefinições; cada propriedade com contraexemplo/mutante e gerador de bordas |
| `props/test_integration.lua` | Pipelines com resultado independente e invariantes intermediários; não duplicar unitários sob novo nome |

A migração manterá `smaug.Series(...)`/`smaug.DataSet(...)`, `from_array` nos casos apropriados, ausência de aliases de construtores e nomes completos em `snake_case`. APIs especializadas continuam sendo exercitadas quando forem o objeto do teste.

## 6. Reconstrução dos 15 eixos parity

| Eixo | Destino |
| :--- | :--- |
| 1 — dtypes | Matriz de capacidades declaradas + provas positivas/negativas executáveis por dtype |
| 2 — Series/DataSet | Classificar diferenças dimensionais e gaps; nomes iguais não significam semântica igual |
| 3 — C/Lua | Inventário real de símbolos e mapeamentos FFI, separado de suporte público comportamental |
| 4 — relacional | Casos executáveis por dtype de chave e de valor; incluir operações agregadas |
| 5 — I/O | Capacidade separada de ler/escrever/preservar tipo/preservar valor e avisar perda |
| 6 — retornos | Observar tipo/shape/nulidade reais; registrar diferenças aprovadas, inclusive categorical |
| 7 — null | Matrizes de ausência explícitas, executadas; distinguir NA, NaN e inválido |
| 8 — nomes | Contrato de alias e de convenção; alias semântico exige comportamento correspondente |
| 9 — sentinelas/erros | Status + valor + máscara e mensagens via canal central; testar dado válido igual à sentinela |
| 10 — lifecycle | Operações completas por dtype, despacho Lua real, COW/GC e falhas; `take/filter` não podem constar só de uma tabela auxiliar não iterada |
| 11 — testes | Substituir contagem textual por mapa contrato → caso → resultado → evidência; inventário completo |
| 12 — docs | Conferir superfície pública/assinaturas/exemplos e decisões; nome mencionado não basta |
| 13 — tostring | Instanciar cada objeto/acessor e testar representação legível, limites e privacidade |
| 14 — reentrância | Inventário/análise estrutural e contratos de dependências; testes concorrentes e ferramentas no perfil suportado |
| 15 — ABI | Probe C compilado versus FFI, todas as structs, enums e símbolos/assinaturas relevantes |

Estados propostos: **verificado**, **falhou**, **não executado**, **não suportado por contrato**, **gap conhecido/admitido**, **evidência insuficiente**. Não confundir uma exceção intencional com implementação adiada. Exceções terão ID, escopo, motivo, evidência, decisão e condição de revisão; entradas obsoletas, duplicadas ou sem consumidor serão denunciadas.

Falha do mecanismo de verificação deve invalidar o run. Uma hipótese heurística pode continuar consultiva, mas não pode virar verde ou desaparecer se a ferramenta falhar.

## 7. Política proposta para cobertura e invariantes

### 7.1 Classes obrigatórias

1. **Alcançável por entrada pública:** testar, inclusive argumentos inválidos que a API promete rejeitar. Não exige aceitar ponteiros arbitrários nem memória ilegível como entrada válida de C.
2. **Alcançável por falha ambiental:** injeção de alloc, read/write/seek/close conforme o contrato; indisponibilidade atual do mecanismo é gap, não prova de impossibilidade.
3. **Invariante interno:** escrever a implicação, domínio, estabelecedores e preservadores. Testar a entrada que estabelece a precondição e o comportamento protegido. Prova condicional pode justificar o ramo impossível, nunca todos os ramos da linha.
4. **Limite físico ou dependente de plataforma:** separar impossibilidade na máquina de impossibilidade lógica. Testar helpers de cálculo de tamanho/overflow sem tentar alocar SIZE_MAX; não forjar estados que levam a acesso inválido só para atingir uma linha.
5. **Código morto/redundante:** avaliar simplificação e proteção remanescente. Redundante não significa inalcançável; mutante equivalente não significa teste fraco automaticamente.
6. **Desconhecido/não demonstrado:** manter visível como pendência; não excluir da métrica só para alcançar meta.

### 7.2 Registro e medição

- Cobertura bruta sempre visível; ajustada é secundária, com exclusões aprovadas e denominador explícito.
- Cada exclusão: ID estável, função/condição e ramo, fingerprint do trecho, justificativa, domínio/plataforma, evidência, data/revisor e motivo para reabrir. Mudança relevante invalida a aprovação anterior.
- Ramos excluídos não entram como testes passados. Se um ramo aprovado como impossível for executado, o registro precisa ser reavaliado automaticamente.
- Agregar C e headers próprios corretamente, evitando tanto omissão quanto dupla contagem de inline/macros. Excluir código de sistema explicitamente. Medição Lua, se adotada, é separada, validada e não inferida a partir de FFI.
- Preservar dados brutos, logs, inventário, flags, versões, hashes e status do run; medição isolada, sem biblioteca instalada como fallback.
- Sem relatório de sucesso para arquivo ausente, zero fontes/casos, falha de parser ou execução incompleta. Publicação atômica do resultado, mantendo a evidência da falha.
- MC/DC apenas em condições críticas selecionadas, com ferramenta e versão verificadas; não chamar branch coverage de MC/DC nem estabelecer meta genérica de certificação.

## 8. Ordem de trabalho após aprovação

| Fase | Entregas | Critério para avançar |
| :--- | :--- | :--- |
| A — Contratos e baseline honesta | Catálogo inicial, divergências documentais, inventário dos cenários e fixtures, estado de cada obrigação | Nenhuma política conflitante usada silenciosamente como esperado |
| B — Infraestrutura confiável | Registro único de testes/capacidades, helpers mínimos, runners que respeitam exit/skip, artefato FFI fixado, testes do harness | Falhas artificiais conhecidas são detectadas; execução incompleta nunca parece completa |
| C — Núcleo e regressões prioritárias | int64/datetime, status/FFI, máscaras, lifecycle/COW, OOM/rollback e regressões R01–R05 | Casos discriminantes e mutantes críticos detectados; contrato e comportamento coerentes |
| D — Superfície e dados | Restante de Series/DataSet, relações, strings/categorical, I/O, fixtures e propriedades stateful | Todas as famílias da seção 5 têm destino rastreável e oracle adequado |
| E — Parity, coverage e exclusões | Os 15 eixos reconstruídos; revisão individual das 153 marcações; baseline Linux bruta e ajustada auditáveis | Nenhuma exclusão sem decisão/evidência; relatórios completos e reproduzíveis |
| F — Campanha final | Windows/Linux, debug/release, sanitizers/Valgrind, mutação, fuzzing e documentação | Critérios de encerramento abaixo satisfeitos; remoção final do legado sem perder contratos |

Cobertura deve ser coletada durante as fases, não apenas ao final; a fase E conclui sua revisão. Nenhuma fase autoriza ampliar funcionalidades para tornar toda assimetria “paritária”. Gaps de produto entram no backlog; só erros contra contratos aprovados são candidatos a correção nessa campanha.

Perfis propostos: rápido/local, completo, memória/UB, falhas de alocação/I/O, propriedades/fuzzing, mutação e concorrência. O ambiente Linux é necessário para a campanha autoritativa prevista pelo projeto; a falta dele deve aparecer como pendência, não como aprovação. Ferramentas/dependências de desenvolvimento serão escolhidas e fixadas sem adicionar dependências de runtime à biblioteca.

Para UB, incluir build diagnóstico sem depender de `-fwrapv`, com instrumentação apropriada e otimizações relevantes. Não remover a flag nem proclamar UB resolvido só por passar testes. A substituição de APIs legadas ou mudança semântica precisa permanecer explícita no contrato.

## 9. Critérios de encerramento — substituem a meta de “mais checks”

- Todos os 33 arquivos atuais e 15 eixos têm mapa de destino; cada cenário retirado possui justificativa. Nenhuma obrigação some durante a migração.
- Contratos críticos possuem casos de sucesso, rejeição, borda e preservação de estado, além de mutantes discriminantes. Classes válidas e inválidas são explicitadas por dtype/camada.
- Todos os defeitos e falsos positivos confirmados neste parecer têm regressão; a versão defeituosa falha e a correta passa pelo motivo esperado.
- Testes de mutação registram: total, detectados, sobreviventes, equivalentes revisados, inválidos/não compiláveis e timeouts. Não esconder sobreviventes; sem meta percentual inventada antes da baseline. Todo sobrevivente crítico deve ser corrigido ou justificado.
- Geradores têm seeds, casos obrigatórios de borda, reprodução do input e redução de contraexemplo; não apenas muitos números pequenos. Zero casos e propriedades nunca executadas são falhas do harness.
- Cada fixture possui contrato/consumidor/hash/esperado; corpus adversarial complementa os dados reais. Diretórios temporários são exclusivos por execução e limpos com segurança.
- Todas as exclusões foram revisadas individualmente; as reprovadas voltam ao universo medido; candidatas não comprovadas continuam como gaps, não como “inalcançáveis”.
- Resultados de Linux/Windows e perfis aplicáveis estão vinculados à árvore/artefatos reais, com skips explícitos; falhas de ferramentas ou teste não produzem sucesso.
- Relatórios separam execução estrutural, correção funcional, memória/UB, mutação e cumprimento de contratos. Nenhuma dessas dimensões é vendida como prova das demais.
- Não resta defeito crítico conhecido contra contrato aprovado. Pendências aceitas têm impacto, decisão e próximo passo registrados, sem declaração genérica de “núcleo selado”.

## 10. Decisões submetidas à aprovação

1. Aprovar o escopo completo e a substituição incremental por famílias, preservando apenas os cenários que tenham proteção demonstrável.
2. Aprovar a suspensão do uso de percentuais antigos/contagens como selo de qualidade; manter cobertura bruta, evidência e gaps visíveis.
3. Aprovar a revisão de todas as exclusões e exceções parity, sem presunção de validade por já estarem documentadas.
4. Aprovar alinhar documentação e contratos antes de fixar expectativas; manter a direção já acordada de overflow explícito via C/FFI/erro Lua. Domínio temporal, sentinelas, garantias de lifetime e diferenças de API que ainda forem ambíguas serão decisões explícitas, não alterações silenciosas.
5. Aprovar que bugs encontrados tenham reproducer e classificação próprios. Correções contra contrato aprovado podem integrar a campanha; expansão de API ou mudança de política será apresentada separadamente.

**Conclusão:** há material útil para preservar, mas o sistema atual mistura evidências fortes com proxies frágeis e justificativas refutadas. A reconstrução é justificada. O resultado esperado não é uma suíte maior: é uma suíte cujo alcance, limites e capacidade de detectar erros sejam demonstráveis.

## Anexo — hashes das fixtures observadas

| Fixture | SHA-256 |
| :--- | :--- |
| cotacoes.csv | `1214a9706e5a214c5ca7d92895cba81d2c22e963ac200a024f1fc5a5fccd7187` |
| cotacoes.json | `c9600920a978956a3b4fd1264f8d78eda37024190e308d6c02ed7a2f177b6beb` |
| cotacoes_SHIB_BRL.json | `ffcdc6b8ef09b638d48a24271b7ac1b319d4e866f25d51c13378818b8eafcfc0` |
| cotacoes_USD_BRL.json | `9ecec1c7f1d135383688c6567d0fc42dfd9aa602da4301972e2534e351429e4f` |
| pedidos_digitados.csv | `282f7fca004eda9aa34962345a8b3c3f1561213de5ef15e04b755fbaff83d0a0` |
