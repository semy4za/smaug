# Smaug — roadmap

[Documentação](README.md) · [Contrato](CONTRACT.md) · [Arquitetura](ARCHITECTURE.md)

Revisão: 2026-09-28. Base inspecionada: `320b4bc`; parser R1 aplicado e
consumidores CSV/JSON ainda em verificação. Objetivo imediato: preservar valores e tornar confiáveis
os contratos e sua verificação nos anéis 0–3. Esta fila substitui a anterior;
não aprova automaticamente mudanças de contrato ainda abertas.

[Checkpoint](#checkpoint) · [Verificação](#verificacao) ·
[Review de comentários](#comentarios)

**Régua de revisão:** para cada afirmação, perguntar “isso é verdade na árvore
atual?” e registrar a evidência. Leitura de código é observação; teste executado
valida apenas seu domínio/ambiente; contrato aprovado pode ter implementação
pendente. Sem evidência suficiente, manter a lacuna aberta. Nenhum percentual,
comentário ou suíte verde isolada significa certificação geral.

## Estado de partida

- Existem `Series`, `DataSet`, categorical e I/O CSV/JSON próprios.
- `prod` já tem implementação C e consumidores Lua. Aritmética i64 checked,
  conversão estrita string/int64/float64→datetime e correções de join/groupby
  também existem. Não são tarefas de implementação inicial.
- Foram reproduzidos problemas de sintaxe/associação JSON, preservação de NUL
  e transporte exato de int64. [Evidências e decisões](IO_REVIEW.md).
- A suíte relacional foi reescrita inicialmente e corrigida; a auditoria de
  migração e o poder de detecção ainda precisam ser concluídos.
- Os quatro helpers aritméticos checked têm evidência dirigida favorável.
  Isso não certifica consumidores, memória ou restante do core.
- O parser R1 tem contrato de saída obrigatória, consumo integral, gramática
  explícita e diagnósticos testados. A integração dos leitores ainda não é
  contabilizada como concluída.
- A licença MIT já existe. Distribuição e política de compatibilidade seguem
  abertas; não recriar a tarefa de adicionar licença.

## Ordem de trabalho

1. Fechar o mecanismo numérico e seu uso pelos consumidores (R1), com a
   evidência pertinente de R6 em cada correção.
2. Fechar transporte de valores e layouts de I/O (R2) antes de implementar
   toda a adaptação CSV/JSON (R3).
3. Concluir a auditoria de inferência e entrada Lua (R4), então retomar
   `dayfirst`, detecção de datas e componentes datetime (R5).
4. Concluir a reconstrução e verificação por famílias (R6); tratar R7 nas
   famílias afetadas e fechar a entrega pública (R8).

Discussão de R2–R4 pode ocorrer antes de R1 terminar quando esclarecer seus
consumidores. Esta ordem preserva a decisão de auditar inferência antes de
ampliar datetime. Não exige reescrever todo o motor para corrigir um mecanismo.

<a id="r1"></a>
## R1 — Conversão numérica e defesas do core

**Estado:** parser e `astype` implementados conforme a gramática aprovada;
integração CSV/JSON e verificação ampliada permanecem em andamento.

Direção solicitada em 28/09: preservar os anéis e estabilizar as convenções
de biblioteca C. O [padrão C/Lua consolidado](CODING_STYLE.md) usa o C11 já selecionado
pelos builds e explicita tipos, erros, memória e portabilidade. Conferir também
locale e dependência de `-fwrapv`; não migrar assinaturas por padronização estética.

Aplicar C01–C08 aos parsers e L02/L04–L07 aos consumidores alterados. A
gramática, saída obrigatória, consumo integral, comprimento sem truncamento e
política de subnormal/underflow foram registrados e implementados no core.

Evidência de 28/09: probe em GCC/glibc reproduziu dependência de locale
(`1.5` versus `1,5`), rejeição do subnormal decimal testado e divergência de
comprimento entre slice e `_cstr`. [Resultados e recomendação](IO_REVIEW.md#r1-padrao-c).
Decisão aprovada em 28/09: formato/inferência no leitor, conversão no core;
causas por código no core e contexto/mensagem na camada externa. `astype`
tolerante distingue elemento inconversível de falha operacional, sem converter
OOM em NA. [Contrato](CONTRACT.md#conversao-numerica-responsabilidades).
Próximo passo: verificar consumidores CSV/JSON, formatadores e o mapeamento de
diagnósticos antes de ampliar a ABI.

[Matriz de comparação](IO_REVIEW.md#r1-proposta): gramática atual versus
destino, mudanças de compatibilidade e categorias de falha. A migração de astype e inferência CSV distingue falha operacional de texto
inconversível desde a revisão de 29/09; JSON e transporte seguem abertos.
Suporte explícito a hexadecimal aprovado em 28/09. A
[gramática detalhada](IO_REVIEW.md#r1-gramatica) registra as regras aprovadas
e casos de aceitação/rejeição; hexadecimal inteiro é aceito em i64 e f64. A
suíte C cobre limites, subnormais e underflow; a inferência CSV ainda precisa
de verificação dirigida.

Conferir as quatro funções `smaug_parse_i64/f64` e `_cstr`, seus headers,
`astype` e wrappers CSV. Validar o mapeamento dos códigos nos consumidores.
NUL dentro de um slice não pode permitir aceitação silenciosa de seu prefixo
numérico. Falha deve preservar saída válida.

Slices e `_cstr` usam a mesma gramática e não truncam tokens longos.
Não migrar CSV cegamente sem verificar seus limites próprios. `astype` numérico conserva
seu contrato de elemento inconversível→NA; escolha de dtype do arquivo é R3.

**Conclusão:** decisões documentadas; regressões de NUL inicial/intermediário/
final, buffers não terminados, limites representáveis e ponteiros; consumidores
C/Lua verificados; mutações detectadas; evidência de memória/UB com lacunas
de ambiente explicitadas. [Review](IO_REVIEW.md#core).

<a id="r2"></a>
## R2 — Preservação C/Lua e compatibilidade ABI

**Estado:** preservação de NUL e identificação da ABI aprovadas; implementação
pendente. Detalhes do transporte de marcadores ainda propostos.

- Preservar int64 nas duas direções: tabela C→DataSet e DataSet→writer,
  sem passagem intermediária por `number` Lua.
- Transportar comprimento de valores e nomes; distinguir `a` de `a\0b`.
- Coordenar `smaug_column_t.name_len`, opções de `na_values`, produtores C,
  cdef, buffers Lua e ownership. Metadata permanece fora desse recorte.
- Implementar consulta estável `smaug_abi_version()` antes de acessar estruturas;
  biblioteca carregada incompatível deve falhar sem fallback silencioso.
- Verificar cleanup quando a adaptação Lua lança erro e nos caminhos parciais C.

**Conclusão:** comparação de bytes/valores/máscaras nos dois sentidos, nomes
com NUL e colisões, biblioteca ausente/incompatível/correta, sizeof/offsetof
entre C compilado e FFI, falhas de alocação e testes Linux/Windows identificados.
[Desenho e limites](IO_REVIEW.md#transporte).

<a id="r3"></a>
## R3 — Leitura e escrita CSV/JSON

**Estado:** defeitos reproduzidos; políticas parcialmente fechadas.

Implementar as decisões aprovadas: associação JSON por nome, união de campos,
ordem por primeira aparição, desambiguação sem perda e ausência/null→NA;
strings `""`, `"null"` e `"NA"` continuam texto. Validar documento completo,
com erro por posição/motivo e sem resultado parcial.

Antes das respectivas mudanças, fechar largura irregular e dialeto CSV;
inteiros fora da faixa, mistura int64/float64, zeros iniciais e schema explícito;
BOM, UTF-8 e surrogates. Corrigir corte de tokens e saturação numérica sem
escolher silenciosamente uma política de representação.

Completar diagnóstico da escrita em arquivo, propagação de erros de leitura/
escrita/fechamento, limpeza parcial e fixtures com expectativas independentes.
Não ampliar automaticamente o perfil JSON para objetos aninhados.

**Conclusão:** corpus válido/inválido com resultados externos esperados,
preservação de valores, diagnósticos e cleanup; regressões por defeito;
opções e limitações refletidas na API. [Review](IO_REVIEW.md).

<a id="r4"></a>
## R4 — Inferência e entrada nas APIs Lua

**Estado:** consumidores mapeados; decisões de uniformização pendentes.

Confrontar `Series`/`from_table`, `from_dict`, `full`, `map` normal/categórico,
`explode`, `ifelse`, `where` e `mask`. Separar inferência de dtype, validação de
dtype já fixado e conversão explícita. Não substituir um pelo outro apenas
para eliminar duplicação. Conferir cdata int64, ordem dos valores, tudo NA,
misturas de famílias e preservação das colunas reconstruídas.

**Conclusão:** matriz de comportamento por entrada, decisões para divergências,
regressões de precisão/nulidade/ordem e consumidores do mecanismo comum listados.
[Mapa atual](IO_REVIEW.md#inferencia-lua).

<a id="r5"></a>
## R5 — Completar datetime

**Estado:** parser e `astype` estritos implementados; demais entradas e
componentes ainda em migração. Depende da auditoria R1–R4.

Integrar `dayfirst` nas entradas restantes; definir detecção automática e
gatilhos de diagnóstico sem mudar o padrão mês/dia aprovado. Migrar os 11
componentes escalares e os 11 de série para as assinaturas já aprovadas,
preservando anos negativos e NA. Corrigir semana ISO, revisar formatter,
buffers, helpers, construção, set/append, fillna e operações derivadas.

Aliases de outras famílias e opções futuras permanecem propostas próprias.
**Conclusão:** limites UTC e offsets, ano -1 distinto de falha, precisão exata,
posição de erro, saída preservada e todos os consumidores C/FFI/Lua atualizados.
[Contrato](CONTRACT.md#section-perfil-datetime-decisoes-aprovadas-em-2026-09-18) ·
[API C planejada](API_Reference.md#section-datetime-migracao-c) ·
[Integração Lua](API_INDEX.md#section-datetime-migracao-lua).

<a id="r6"></a>
## R6 — Verificação por famílias e executores confiáveis

**Estado:** reconstrução incremental iniciada; auditoria geral aberta.

Padrão C/Lua consolidado em 28/09: regras, contrato mínimo, critérios de revisão
e registro de exceções ficam em CODING_STYLE. Falta configurar baseline e gates
de análise estática C, lint LuaJIT e formatação; o verificador atual cobre apenas
convenções dos testes. Avaliar ferramentas contra C11/LuaJIT/FFI, testar se
detectam violações reais e documentar suas limitações antes de exigir o gate.
Começar a adoção funcional por R1; conformidade integral da base não foi medida.

Concluir migração relacional e repetir o método nas demais famílias:
contrato independente, estado/resultado completos, destino dos casos antigos
e mutações que demonstrem detecção. Enumerar pontos reais de OOM e eliminar
asserções sem poder de rejeição.

Corrigir executores para exigir código de saída, arquivos/dependências e
quantidade de casos; identificar a biblioteca FFI testada. Unificar inventários
preservando as categorias plain, wrap e stress. Revisar os 15 eixos de paridade,
incluindo layout compilado e reentrância. Refazer cobertura bruta íntegra,
incluindo headers executáveis, dados brutos e exclusões por ramo comprovadas.

**Conclusão:** evidências reproduzíveis por árvore e plataforma, falhas do
próprio executor detectadas, exclusões auditadas e nenhuma equivalência entre
branches e MC/DC. Não manter contagens antigas como meta de qualidade.
[Checkpoint](#checkpoint) · [R01–R09](#verificacao).

<a id="r7"></a>
## R7 — Contratos e débitos remanescentes dos anéis 0–2

**Estado:** tratar por família, após conferir se cada pendência ainda existe.

- Lifetime/invalidação de views, realocação do pai, COW e rollback por dtype.
- Overflow intermediário e canais de status nos consumidores dos helpers.
- Divergências relacionais: `count`, padrão de `pivot_table`, join composto;
  codificação das chaves de duplicatas em `dataset/_stat.lua`.
- Colação e nulidade em comparações como contrato explícito; compartilhamento
  de interpolação de quantis; distinção NaN/NA nas mensagens.
- Vetorização `.str`/operações derivadas `.dt` e otimização de igualdade apenas
  com semântica fechada e benchmark reproduzível. O bloqueio histórico por NaN
  do antigo 10.5-B não deve ser presumido atual.
- Despacho por capacidades/dtypes novos exige desenho próprio, incluindo os
  auditores que hoje deduzem suporte de texto do código.

**Conclusão:** cada item verificado ou adiado com motivo, sem transferir
políticas externas ao core nem reformar APIs por uniformidade superficial.

<a id="r8"></a>
## R8 — Entrega pública

**Estado:** posterior às correções e à verificação; sem data de release.

Fechar superfície pública/interna, política de versões/depreciação, instalação
e distribuição, taxonomia de erros, exemplos/docstrings e benchmarks.
Linux e Windows precisam executar o mesmo conjunto previsto para a mesma
árvore; diferenças e skips têm de aparecer no relatório. Licença já presente.

**Conclusão:** limitações documentadas; correções prioritárias concluídas;
contratos, código e APIs coerentes; evidências de memória, testes, ABI e
cobertura disponíveis. Só então preparar release/tag; não publicar por esta
reorganização documental.


<a id="checkpoint"></a>
## Checkpoint de retomada — 2026-09-29

Gramática R1 aprovada em 28/09. A revisão de 29/09 corrigiu o parser,
`astype` e o consumidor CSV, mantendo a ABI e a arquitetura de anéis.
**Estado de entrega:** mudanças locais sem commit; R1 permanece aberta.

**Concluído nesta etapa:**

- Inteiros continuam a validar o sufixo após exceder a faixa, sem continuar
  a acumulação. `SYNTAX` prevalece sobre overflow de um prefixo; fronteiras
  decimais/hexadecimais e preservação da saída têm regressões.
- f64 distingue overflow saturado em `DBL_MAX` com `ERANGE` de subnormal
  representável, inclusive na fronteira que arredonda para `DBL_MIN`.
  Removido o ramo duplicado de underflow; quatro modos de arredondamento
  exercitados nativamente, sem alterar o modo do caller.
- `astype` tolera apenas SYNTAX/OVERFLOW/UNDERFLOW; outras falhas abortam.
  OOM na cópia de token longo e na criação de locale têm injeção dirigida.
- CSV consome status na conversão numérica: falha operacional não altera
  inferência nem vira NA. Decimal customizado aceita tokens longos por inteiro.
  Cleanup do crescimento de linhas preserva o ponteiro retornado pelo primeiro
  realloc se o segundo falhar; falha no setter de string aborta a tabela.
- Nomes, blocos, ownership e limites dos trechos revisados seguem CODING_STYLE.
  Não houve mudança de layout/assinatura nem nova dependência de runtime.

**Verificação e vínculo com os reviews:** `make test` e `make test-lua`
aprovados no Linux, GCC 16.2.1/glibc 2.43. Astype também passou com
`-O2 -Wall -Wextra -Wpedantic -Werror`, sem `-fwrapv`. O guard de estilo passou
nos 33 arquivos de teste; `git diff --check` passou. Probes em `C` e
`pt_BR.utf8` confirmaram ponto decimal e subnormais.

`python3 scripts/audit_numeric_regressions.py` exige baseline válida e testa
seis mutantes compiláveis em cópias temporárias: seis detectados, nenhum
sobrevivente na rodada final. O mutante que ignorava o setter de string
sobreviveu inicialmente; o caso novo força crescimento do buffer e o rejeita.
O script registra hashes dos fontes. `test_allocfail` passou sob Valgrind
3.27.1 com verificação de leaks e erro não zero habilitado. Os casos de CSV
misto/100 linhas substituem limites fixos e a asserção `|| 1`: enumeram as
alocações da baseline, confirmam injeção e verificam recuperação/conteúdo.
Isso aplica R03/R05 do review; não certifica todos os casos antigos de OOM.

**Limitações:** Valgrind divergiu da execução nativa no arredondamento de
`1e-400` para subnormal sob FE_UPWARD; a suíte astype inteira não foi aprovada
sob essa ferramenta. ASan/UBSan não executado: link falhou por ausência de
`/usr/lib64/libasan.so.8.0.0`. Não há compilador Windows neste ambiente;
portabilidade desse ramo continua sem verificação nova. Coverage, parity e
manifest não foram regenerados; não usar relatórios históricos como selo.

**Seguimento — formatação concluída no Linux:** os formatadores agora usam
ponto decimal fixo e retornam zero sem alterar o buffer em falha (inclusive
capacidade insuficiente). Astype/CSV/JSON conferem o retorno, sem strings vazias
ou tabelas parciais. O contrato de 17 dígitos permanece; roundtrip verificado
sob FE_TONEAREST, sem alterar o arredondamento do caller. Locale global e
objeto de locale da thread são preservados. Foram exercitados C e pt_BR.utf8,
falha de criação/ativação de locale, capacidade exata e recuperação após OOM.

Validação do seguimento: `make test` (12 binários; astype 525 checks e
allocfail 2.665), `make test-lua` (20 suítes), astype com
`-O2 -Wall -Wextra -Wpedantic -Werror`, guard dos 33 arquivos e diff aprovados.
`python3 scripts/audit_numeric_regressions.py` agora detecta nove mutantes
compiláveis (três de formatação); baseline allocfail aprovada sob Valgrind.
A seleção/restauração POSIX é nova para formatação; o ramo `_snprintf_l` não
foi verificado no Windows. Mantidas as limitações de sanitizers e de Valgrind
nos testes de arredondamento acima. Detalhes em IO_REVIEW, sem novo diário.

**Próximo passo:** continuar R2/R3 para bytes/comprimentos no CSV e
lexer/conversão JSON, que ainda usa libc diretamente e depende de locale. A política de faixa/inferência dos leitores permanece explícita: CSV
sem schema ainda pode inferir texto para elemento numericamente inconversível.
Não declarar leitura estrita implementada por a propagação de OOM ter passado.
Completar Windows/sanitizers quando disponíveis e manter revisão incremental
da suíte conforme R01–R09, sem nova campanha de renomeação global.

| Frente | Já conferido | Falta para avançar |
|---|---|---|
| Core numérico | Helpers checked: 30.712 chamadas e cinco mutações detectadas; parser/formatter/astype/CSV com regressões de status, OOM e nove mutações detectadas | Leitura JSON, transporte CSV, Windows e sanitizers |
| I/O | 30 + 23 casos observacionais; baseline recompilada; NUL, int64 e associação JSON reproduzidos | Fechar transporte/opções e implementar R2/R3 |
| Inferência Lua | Entradas mapeadas no review de I/O | Decidir divergências, sem uniformizar por conveniência |
| Datetime | Parser e astype estritos C/Lua implementados em 25/09; build Windows histórica passou | Integração restante, 11 componentes escalares + 11 de série, formatter e semana ISO |
| Relacional | Reescrita inicial; três defeitos corrigidos; 68 casos passaram no seguimento de 25/09 | Contratos count/pivot/join, migração dos casos antigos e mutações |
| Verificação | Inventário/review dos executores; cobertura e parity disponíveis como artefatos históricos | Corrigir confiabilidade e comprovar detecção por família |
| Documentação | Roadmap substituído; checkpoints unificados; redundâncias removidas | Manter este checkpoint após cada frente, sem novos diários paralelos |

A implementação R1 tem regressões C para gramática, limites, subnormal,
underflow, overflow e preservação de saída. Isso não é teste da futura migração
ABI. Não houve nova cobertura Windows ou sanitizers para esta frente.
As evidências específicas ficam nos reviews [I/O](IO_REVIEW.md) e
[aritmético](CORE_ARITHMETIC_REVIEW.md), sem manter outra fila de execução.

<a id="verificacao"></a>
## Review da verificação — origem e destino dos achados

R01–R09 abaixo são IDs da auditoria histórica de 18/09, distintos das frentes
R1–R8. A árvore auditada era `9787701` com mudanças locais; números e linhas
daquela auditoria não certificam a árvore atual. A reconstrução é incremental:
cada caso antigo recebe destino (manter, fortalecer, substituir, fundir ou
retirar com justificativa); só retirar depois de validar o substituto.

| Achado histórico | Evidência que orienta a revisão | Frente atual |
|---|---|---|
| R01 — testes aceitam resultado errado | Mutações view→clone, join vazio, last→first e aceitação de índice inválido escaparam às suítes indicadas | R6: completude, multiplicidade, estado e rejeição efetiva |
| R02 — datetime | Semana de 2023-01-01 retornou 53 em vez de 52; extração em série anulou ano -2 | R5: esperado único independente, ano separado de status |
| R03 — OOM | Contagem de checks não enumera alocações e rollback de cada caminho | R6: registrar ponto atingido e estado após cada falha |
| R04 — cobertura | Relatório histórico, coleta parcial e headers executáveis fora da visão podem ocultar lacunas | R6: dados brutos íntegros, árvore e ferramenta identificadas |
| R05 — exclusões | Guards classificados como inalcançáveis foram atingidos por entradas públicas | R6: manter triagem individual do inventário de exclusões |
| R06 — parity | Campo extra no cdef f64 e global mutável escaparam; fonte ausente virou texto vazio | R2/R6: layout compilado, inventário completo e falha explícita |
| R07 — executores | PASS textual pode ocultar exit não zero; skips e eixos parity não barram aprovação | R6: testar executor, não só os testes |
| R08 — fixtures/manifest | Uso das quatro fixtures de cotações não demonstrado; manifest omite csv/json/txt | R6: origem, licença, hashes e expectativas externas; Python já entrou no manifest |
| R09 — duplicação/contratos | Propriedade redefinida, bootstrap repetido e contratos documentais contraditórios | R6/R7: revisar expectativas antes de copiar implementação |

Cada família deve registrar entrada, dtype/shape, ordem, máscara, saída/status,
ownership, efeitos, limites e oracle. Compartilhar infraestrutura de teste é
útil; compartilhar a lógica de produção como oracle anula a independência.
Testar os comparadores com resultados deliberadamente errados. As mutações
relacionais devem partir de baseline verde e identificar a regressão causada.

Nos executores, exigir rejeição de PASS seguido de erro, arquivo/dependência
ausente, zero casos, timeout e relatório parcial. Confirmar caminho/hash da
biblioteca carregada. Preservar inventários plain/wrap/stress e os 15 eixos de
parity; revisar seu significado, não apenas sua contagem. Concorrência usa
objetos independentes; não certifica mutação simultânea de um mesmo objeto.

<a id="comentarios"></a>
## Review de comentários e coerência documental

Leitura dirigida nesta revisão; não é uma auditoria linha a linha de todo o
repositório. Antes de corrigir cada comentário, conferir função, consumidores
e teste que sustentam a redação. Comentário não resolve contrato aberto.

| Local conferido | Divergência ou limite | Encaminhamento |
|---|---|---|
| `src/smaug_ops_i64.c`, abertura do Grupo A | Diz overflow por wrap; cumsum/cumprod checked rejeitam antes de calcular | R7: revisar bloco por operação e corrigir descrição |
| `include/smaug_core.h`, helpers checked | false descrito só como overflow; divisão também rejeita zero e out NULL é permitido | R1/R7: documentar casos e preservação da saída por API |
| `include/smaug_numeric.h`, smaug_i64_div | `/0 → NULL` confunde ponteiro com célula NA; implementação produz máscara NA | R7: esclarecer forma de falha sem trocar semântica |
| `include/smaug_numeric.h`, reduções f64 | Dizia var/std populacionais; código divide por n−1 e exige n≥2 | Corrigido para amostral; consumidores e contrato completo seguem em R7 |
| `src/smaug_ops_str.c`, introdução | Categorical era descrito como futura otimização do backend; já existe como superfície Lua separada | Comentário alinhado; colação por bytes e separação de tipos seguem em R7 |
| `src/smaug_ops_bool.c`, API struct-based | Comentário tratava a aposentadoria de BoolSeries como destino certo; bool continua dtype de primeira classe | Comentário alinhado para superfície legada; R7/R8 ainda decidem os consumidores raw |
| `scripts/build.sh` / `scripts/build.ps1` | Comentários de execução completa não mostram todas as condições de skip/aprovação | R6: alinhar comentários à correção dos runners |
| Referência C, catálogo rápido duplicado | Assinaturas simplificadas divergiam das tabelas principais | Consolidado nesta revisão; manter uma descrição por operação |
| Referência C, views/memória e soma i64 | Dizia que escrever na view alterava o pai, invertia lifetime e sugeria contar não-nulos para resolver ambiguidade de overflow | Corrigido contra COW, destrutores e sum_checked; não implica auditoria integral da API |
| Guia datetime e fila antiga | Parser/astype já implementados ainda apareciam como futuros | Corrigido nesta revisão; componentes/formatter continuam abertos |
| Referência C, writers em memória | Omitia `err_out` em CSV/JSON e a responsabilidade de liberar a causa | Corrigido contra `smaug_io.h`; conferir consumidores FFI em R2 |
| Referência C, CSV | Listava `nan`/`NaN` como NA padrão, mas o parser preserva esses tokens como valores IEEE | Corrigido contra `src/smaug_csv.c`; manter teste que distingue NaN de null em R3 |
| Referência C, datetime parse | Omitia `dayfirst` na assinatura legada e misturava API atual com assinatura aprovada futura | Separado nesta revisão; migração permanece R5 |
| Referência Lua, reduções | Omitia `min_count` em `sum`/`prod` e dizia NaN onde o wrapper central entrega `nil` | Corrigido contra `series/_core.lua`; confirmar a matriz completa em R4 |
| Referência Lua, bool | Apontava uma classe `BoolSeries` que não existe mais no caminho público | Corrigido para `Series<bool>`; raw arrays C continuam legados até R7/R8 |
| `include/smaug_io.h`, comentário de erro global | Citava `smaug_io_last_error()`, símbolo que não existe; a implementação usa `table->error` e `err_out` | Corrigido no header; manter o transporte local de causa em R2 |
| Referência C, operações de janela | O header `smaug_ops_window.h` tinha multi-argsort/rolling sem seção correspondente | Seção adicionada; conferir consumers Lua e status de overflow em R6/R7 |
| Referência C, problemas conhecidos | Apontava `tests/test_alloc.c`, `extern` e `memset` que não correspondem mais à árvore | Caminho corrigido e itens não reproduzidos removidos |
| `lua/smaug/core/series/stats/_stat.lua`, produto i64 | Comentário dizia que overflow reutilizava `SMG_ERR_OOB`, mas o enum atual possui `SMG_ERR_OVERFLOW`; o teste do wrapper ainda está divergente | Comentário alinhado ao código observado; corrigir despacho em R7 |

### Review executável da referência de API — 2026-09-27

Um probe Lua isolado recompilou a biblioteca da árvore atual e verificou 24
comportamentos pequenos, cobrindo NaN/NULL, precisão i64, datetime, CSV/JSON,
views, categorias, seleção e agregações. Vinte e dois casos confirmaram a
descrição ou o contrato observado. Dois não são problemas de redação:

- `Series<int64>:prod()` em overflow devolve uma mensagem genérica porque o
  wrapper não reconhece o status efetivo `SMG_ERR_OVERFLOW`; revisar o canal de
  status em R7 antes de prometer diagnóstico específico.
- `Series<bool>:where(cond, outra_series)` falha quando o valor selecionado
  de `other` é false: a expressão Lua `and/or` usa a própria tabela como
  fallback. Selecionar true funciona. Conferir também NA, `mask` e `ifelse`
  em R4/R7.

Outras observações que ficam explícitas na documentação: `INT64_MIN` válido é
indistinguível da sentinela em algumas reduções Lua; `corr`/`cov` preservam NaN,
enquanto as reduções centrais o convertem em `nil`; a semana ISO de
`2023-01-01` ainda retorna 53; e `dt:format()` ignora a falha de formatação no
wrapper. Esses pontos são evidência dirigida, não certificação do restante da
API.

Comentários de exclusões precisam de prova por ramo, conforme o
[inventário](TEST_SUITE_EXCLUSIONS_REVIEW.md). Referências numéricas antigas
no código continuam rastreáveis na versão Git indicada abaixo. Não renumerar
comentários mecanicamente nem interpretar marcações históricas como garantias.
O cabeçalho do teste relacional foi atualizado para este roadmap e deixou de
fixar a revisão antiga de coverage. Nenhuma asserção ou lógica foi alterada.

### Conferência da revisão — 2026-09-28

A revisão documental anterior também exigiu correção: `multi_argsort` não
valida máscaras/tamanhos das colunas; rolling permite janelas iniciais parciais
com `min_periods >= 1`; `ne(NaN)` é true; remoção de afixos não é idempotente.
Leitura do C e execução Lua dirigida confirmaram rolling(3)/min_periods(1)
com somas 1, 3, 6 e distinguiram `where` selecionando true (sucesso) de false
(erro). A saída registrada do build anterior contém 12 binários e 5.002
verificações, corrigindo a contagem do changelog. Não houve nova suíte completa.
O diff documental inclui uma mudança de texto no erro de `filter`; portanto,
o relato anterior de alterações exclusivamente em comentários era impreciso.

## Como atualizar este roadmap

Ao concluir uma etapa, atualizar sua frente e este checkpoint com: decisão,
código/consumidores conferidos, evidência (árvore, comando, plataforma), lacunas
e próximo passo. Contrato aprovado fica em CONTRACT; assinatura em API;
resultado detalhado em review específico quando necessário; changelog recebe
apenas o marco. Evitar repetir o relato da sessão nessas quatro fontes.

<a id="historico"></a>
## Referências antigas e trabalho futuro

Os IDs antigos `1`–`15`, inclusive `10.x`, `12.x` e `14.x`, continuam
consultáveis no [roadmap anterior](https://github.com/semy4za/smaug/blob/320b4bcbd5b50df20872668dd36afbe54ca941e2/docs/Roadmap.md).
Eles identificam contexto histórico; novos trabalhos usam R1–R8.

| Frente antiga | Destino atual |
|---|---|
| 10.1 prod; 12.34 colação; LICENSE | Implementações/arquivo existentes; verificar em R6/R7/R8 |
| 10.4; 12.16; 12.25; 12.36 | R5; `.str` e performance em R7 |
| 10.5-B; 12.14; 12.33; 12.35; 12.39 | R7 |
| 12.8; 12.26; 12.30 | R2/R3 e evidência em R6 |
| 12.19; 14.1–14.4 | R6/R7 |
| 12.13; 13; 14.5; 15 | R8 e documentação do comportamento correspondente |

Persistência `.smg`, Models, Matrix, Tensor, ML, interfaces e formatos
adicionais ficam na [visão arquitetural](ARCHITECTURE.md#futuro), sem compromisso
de implementação nesta fila. Internacionalização, tipos extras, índices e
visualização dependem de caso de uso e desenho próprios.
