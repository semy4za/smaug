# Smaug — roadmap

[Documentação](README.md) · [Contrato](CONTRACT.md) · [Arquitetura](ARCHITECTURE.md)

Revisão documental: 2026-10-08. Base: `ac695d1` com regressões locais; parser, formatadores,
consumidores CSV/JSON, transporte C/Lua e schema completo implementados.
Correções Windows hexadecimal (`699acc6`) e decimal (`f93d4a5`) entregues;
execução completa Windows após ambas consolidada no checkpoint.
Objetivo imediato: preservar valores e tornar confiáveis
os contratos e sua verificação nos anéis 0–3. Esta fila substitui a anterior;
não aprova automaticamente mudanças de contrato ainda abertas.

[Checkpoint](#checkpoint) · [Verificação](#verificacao) ·
[Review de comentários](#comentarios)

**Régua de revisão:** para cada afirmação, perguntar “isso é verdade na árvore
atual?” e registrar a evidência. Leitura de código é observação; teste executado
valida apenas seu domínio/ambiente; contrato aprovado pode ter implementação
pendente. Sem evidência suficiente, manter a lacuna aberta. Nenhum percentual,
comentário ou suíte verde isolada significa certificação geral.

## Estado atual

- Existem `Series`, `DataSet`, categorical e I/O CSV/JSON próprios.
- `prod` já tem implementação C e consumidores Lua. Aritmética i64 checked,
  conversão estrita string/int64/float64→datetime e correções de join/groupby
  também existem. Não são tarefas de implementação inicial.
- Sintaxe/associação JSON, preservação de NUL e transporte exato de int64
  foram corrigidos. Schema completo CSV/JSON está implementado em memória
  e arquivo. [Evidências e decisões](IO_REVIEW.md).
- A suíte relacional foi reescrita inicialmente e corrigida; a auditoria de
  migração e o poder de detecção ainda precisam ser concluídos.
- Os quatro helpers aritméticos checked têm evidência dirigida favorável.
  Isso não certifica consumidores, memória ou restante do core.
- O parser R1 tem contrato de saída obrigatória, consumo integral, gramática
  explícita e diagnósticos testados. Leitores e formatadores foram migrados;
  regressões de arredondamento nos consumidores e execução Windows ampliadas.
  Sanitizers e auditoria das famílias restantes continuam abertos.
- A licença MIT já existe. Distribuição e política de compatibilidade seguem
  abertas; não recriar a tarefa de adicionar licença.

## Ordem de trabalho

1. Após a consolidação Windows registrada abaixo, reconstruir a paridade de
   ponta a ponta (R6), conforme solicitado pelo mantenedor. Executar sanitizers
   em ambiente compatível e ampliar as famílias numéricas restantes.
2. Consolidar verificação de transporte/layouts (R2) e revisar diagnóstico
   de arquivo/readers (R3). Schema completo já implementado; schema parcial,
   defaults e modo tolerante exigem decisão própria.
3. Concluir a auditoria de inferência e entrada Lua (R4), então retomar
   `dayfirst`, detecção de datas e componentes datetime (R5).
4. Concluir a reconstrução e verificação por famílias (R6); tratar R7 nas
   famílias afetadas e fechar a entrega pública (R8).

Discussão de R2–R4 pode ocorrer antes de R1 terminar quando esclarecer seus
consumidores. Esta ordem preserva a decisão de auditar inferência antes de
ampliar datetime. Não exige reescrever todo o motor para corrigir um mecanismo.

<a id="r1"></a>
## R1 — Conversão numérica e defesas do core

**Estado:** parser, `astype`, formatadores e consumidores CSV/JSON migrados.
Correções hexadecimal/decimal e regressões dos consumidores verificadas no
Windows. Registro completo no checkpoint; sanitizers e demais famílias abertos.

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
Casos de arredondamento hexadecimal/decimal estendidos aos consumidores
CSV/JSON/astype no Windows; repetir a matriz ampliada no Linux e sob sanitizers.

[Matriz de comparação](IO_REVIEW.md#r1-proposta): gramática atual versus
destino, mudanças de compatibilidade e categorias de falha. A migração de astype e inferência CSV distingue falha operacional de texto
inconversível desde a revisão de 29/09. A leitura numérica JSON foi migrada no
seguimento abaixo; transporte também implementado. Lacunas restantes estão em R3.
Suporte explícito a hexadecimal aprovado em 28/09. A
[gramática detalhada](IO_REVIEW.md#r1-gramatica) registra as regras aprovadas
e casos de aceitação/rejeição; hexadecimal inteiro é aceito em i64 e f64. A
suíte C cobre limites, subnormais e underflow; a inferência CSV agora tem
regressões dirigidas de arredondamento, sem encerrar sua auditoria geral.

Conferir as quatro funções `smaug_parse_i64/f64` e `_cstr`, seus headers,
`astype` e wrappers CSV. Validar o mapeamento dos códigos nos consumidores.
NUL dentro de um slice não pode permitir aceitação silenciosa de seu prefixo
numérico. Falha deve preservar saída válida.

Slices e `_cstr` usam a mesma gramática e não truncam tokens longos.
CSV já tem regressões de tokens longos e falhas operacionais. `astype` numérico conserva
seu contrato de elemento inconversível→NA; escolha de dtype do arquivo é R3.

**Conclusão:** decisões documentadas; regressões de NUL inicial/intermediário/
final, buffers não terminados, limites representáveis e ponteiros; consumidores
C/Lua verificados; mutações detectadas; evidência de memória/UB com lacunas
de ambiente explicitadas. [Review](IO_REVIEW.md#core).

<a id="r2"></a>
## R2 — Preservação C/Lua e compatibilidade ABI

**Estado:** transporte de NUL, comprimentos dos marcadores CSV e identificação
da ABI implementados em 29/09. Ponte int64 e cleanup da adaptação de leitura
também implementados; layouts C/FFI Windows e inferência geral ainda abertos.

Entregas implementadas (critérios de verificação no checkpoint):

- Preservar int64 nas duas direções: tabela C→DataSet e DataSet→writer,
  sem passagem intermediária por `number` Lua.
- Transportar comprimento de valores e nomes; distinguir `a` de `a\0b`.
- Coordenar `smaug_column_t.name_len`, opções de `na_values`, produtores C,
  cdef, buffers Lua e ownership. Metadata permanece fora desse recorte.
- Consulta `smaug_abi_version()` implementada antes de acessar estruturas;
  biblioteca carregada incompatível deve falhar sem fallback silencioso.
- Cleanup da adaptação Lua e dos caminhos parciais C tem regressões de falha
  e recuperação; ampliar a auditoria aos caminhos restantes.

**Conclusão:** comparação de bytes/valores/máscaras nos dois sentidos, nomes
com NUL e colisões, biblioteca ausente/incompatível/correta, sizeof/offsetof
entre C compilado e FFI, falhas de alocação e testes Linux/Windows identificados.
[Desenho e limites](IO_REVIEW.md#transporte).

<a id="r3"></a>
## R3 — Leitura e escrita CSV/JSON

**Estado:** políticas estritas, transporte e schema completo implementados,
incluindo leitura em memória/arquivo e falha no fechamento dos writers.
Restam revisar diagnóstico detalhado de arquivo e validação dos readers,
consolidar evidência por plataforma e decidir eventuais extensões.

Implementadas inclusive para nomes com NUL: associação JSON por nome, união de campos,
ordem por primeira aparição, desambiguação sem perda e ausência/null→NA;
strings `""`, `"null"` e `"NA"` continuam texto. Estrutura do documento exige
consumo completo e erro por posição/motivo sem resultado parcial. O JSON também
valida UTF-8 estrito em nomes e valores, com diagnóstico por byte e sem saída
parcial. Políticas implementadas de strings e dialeto constam no contrato.

Gramática numérica, faixa e promoção int64/float64 JSON foram aprovadas e
implementadas em 29/09; corte de tokens e saturação foram corrigidos. O CSV
agora exige largura exata, aceita BOM inicial/LF/CRLF e rejeita CR isolado e
aspas malformadas. Schema explícito completo entregue em `1eafa7a`; schema
parcial, defaults e modo tolerante exigem decisão própria.

Revisar diagnóstico detalhado de arquivo e validação dos readers. Falha de
fechamento dos writers e cleanup/OOM de schema já têm regressões; ampliar a
verificação dos caminhos restantes com expectativas independentes.
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

Próxima frente solicitada pelo mantenedor após consolidar Windows: refazer a
paridade de ponta a ponta, revisando o significado dos 15 eixos, verificadores,
fontes de evidência, falhas/skips e geração de `PARITY_REPORT.md`. A aprovação
textual dos verificadores atuais não encerra essa reconstrução.

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
## Checkpoint de retomada — 2026-10-09

**Reconstrução da paridade ponta a ponta:** a campanha Windows desta árvore
executou `python scripts/parity/runner.py` depois de recompilar uma DLL limpa
em diretório próprio. Os 15 eixos produziram 1.125 registros (839 PASS, 273
OBSERVED, 12 REVIEW e 1 FAIL), sem erro de infraestrutura. Assinaturas C,
símbolos FFI, layouts compilados, I/O, lifecycle e representação textual
passaram; as revisões permanecem separadas para contratos abertos e análise
lexical. O único FAIL é reproduzível em
`Series<bool>:where(cond, other_series)`: ao selecionar `false` da série
alternativa, o wrapper entrega uma tabela ao construtor bool. Esse caso já
estava registrado na matriz R4/R7 e agora é um resultado executável em
`docs/PARITY_REPORT.json`/`docs/PARITY_REPORT.md`, com exit 1 deliberado.

O probe relacional foi alinhado à ordenação de chaves exigida pelos testes
existentes (`1,2`, `false,true`, `a,b`), e o retorno tabular de
`CategoricalSeries:value_counts` foi verificado como contrato intencional. O
runner registra a biblioteca efetivamente carregada, comandos, ferramentas,
hashes e limites em `build/parity/<timestamp>/`; sua saída é regenerável e não
substitui a suíte completa. Próxima ação: repetir a mesma campanha no Linux,
comparar divergências de plataforma e só então corrigir/fechar o FAIL de
`where` em R4/R7.

**Consolidação Windows — consumidores numéricos:** base `ac695d1` com alterações
locais nos testes e na auditoria; produção, contratos e ABI preservados.
Windows 11 x64 (build 26200), GCC MSYS2 UCRT64 15.2.0 Rev13,
LuaJIT 2.1.ROLLING, UCRT do sistema 10.0.26100.9444. A execução de
`scripts/build.ps1 -SkipManifest` passou nos 14 executáveis C (12 plain, um
wrap e stress) e nas 21 suítes Lua, sem skip de Lua. Contagens dirigidas:
astype 1.808, I/O C 2.778, schema C 129; Lua constructors 232, CSV 185,
JSON 129 e schema 82. `/dev/full` permanece skip explícito no Windows.

A matriz C usa expectativas binary64 exatas, quatro modos e ambos os sinais;
cobre fronteira subnormal/normal, empate em zero, sticky bit, underflow decimal,
overflow e zero textual negativo. CSV/JSON são exercitados em memória e arquivo,
com inferência e schema completo. Verifica dtype, shape, máscara, valor/sinal,
diagnóstico, ausência de tabela parcial e preservação do modo do caller.
CSV sem schema preserva o token inconversível como texto; schema/JSON rejeitam
com causa, e JSON continua rejeitando hexadecimal. Astype verifica valores,
NA, fonte intacta e continuidade depois do elemento inconversível.

`python scripts/audit_windows_regressions.py` recompila astype, I/O e schema
com `-O2 -Wall -Wextra -Wpedantic -Werror`, sem `-fwrapv`, diretamente com os
fontes e ligados à DLL; as seis baselines passaram com as contagens acima.
A DLL mantém as flags de produção de `build.ps1`, incluindo `-O2 -fwrapv`;
a compilação direta dos fontes usa as flags estritas acima.
As quatro suítes Lua dirigidas passaram com o módulo efetivamente carregado
identificado pela API Windows: `build/smaug.dll`, SHA-256
`b16d72d1fa52675fc722f1c259c65af89463db0bd1d8f94a16974929c29ce3c5`.
Sete mutações compiláveis foram detectadas, cada uma tanto por I/O quanto por
astype: retorno ao hexadecimal da UCRT, perda de sticky bit/sinal e remoção,
sinal, modos e zero literal da correção decimal. Nenhuma sobrevivente.
Essas sete mutações Windows são uma campanha própria, não se somam à contagem
histórica de 44 mutantes Linux. A campanha concluiu nativamente, fora da
sandbox, com `status: PASS` (o TEMP da sandbox negou a criação das fixtures).
Comando reproduzível e escopo no guia de build. Evidências locais ficam em
`build/windows-regressions/`, incluindo comandos, saídas, versões e hashes de
fontes, headers, testes e scripts. Guard de estilo passou nos 35 arquivos.

Limites: esta matriz ampliada ainda não foi executada no Linux; ASan/UBSan
continuam pendentes. Paridade permanece indicador, sem validação independente
de todos os layouts C/FFI. Coverage e manifest não foram regenerados nesta etapa.
Blocos POSIX de locale da thread e de injeção em `newlocale`/`uselocale` são
excluídos por compilação no Windows; a contagem Windows não equivale à Linux.
`PARITY_REPORT.md` foi regenerado automaticamente pelo build, sem revisão dos
critérios ou dos verificadores; seus resultados não são o gate desta campanha.
Próxima frente: reconstruir a paridade de ponta a ponta conforme R6.

**Histórico anterior à consolidação Windows:** os relatos abaixo identificam
as respectivas árvores e ambientes; limitações antigas não substituem o estado acima.

**Histórico — correção decimal:** base `f93d4a5`, posterior à correção
hexadecimal `699acc6`. O mantenedor trouxe a correção do underflow decimal
prematuro na UCRT. A revisão local confirmou tratamento do sinal textual,
quatro modos, zero literal e saída preservada em erro. `test_astype` passou
856 checks no Linux/GCC 16.2.1 com `-O2 -Wall -Wextra -Wpedantic -Werror`,
e também sob Valgrind 3.27.1: 279 alocações/liberações, zero erros e zero
blocos pendentes. Uma simulação temporária de `strtod_l` retornando zero sem
errno passou 856 checks e interceptou 49 conversões. A divergência decimal
anterior sob Valgrind está resolvida para esta suíte. Runtimes ASan/UBSan
continuam ausentes; não há novo log Windows completo nesta revisão.
Os relatos seguintes também são históricos; a consolidação Windows acima é o estado atual.

**Avanço R6 — auditoria reproduzível:** `scripts/audit_numeric_regressions.py`
agora mantém o wrapper de `strtod_l` em uma baseline separada. Ele força zero
positivo sem errno nos tokens decimais pequenos e exige evidência de execução
da simulação antes de aceitar a baseline. Cinco mutações cobrem remoção da
correção, sinal negativo perdido, modos dirigidos trocados, saída sobrescrita
em erro e zero literal confundido com underflow. A campanha completa na base
`f93d4a5` com esta alteração local terminou com 44 mutantes compiláveis
detectados, nenhum sobrevivente. Baselines astype nativa/simulada aprovadas;
allocfail, I/O C e schema aprovados sob Valgrind. Guia de build atualizado com
o comando reproduzível. Esta campanha não altera os relatórios gerados de
coverage, paridade ou manifest; o ramo simulado não foi incluído no gcov.
Próximo passo: estender os mesmos casos aos consumidores CSV/JSON/astype e
consolidar a evidência Windows da correção decimal; sanitizers seguem pendentes.

**Seguimento Windows — 2026-10-08:** build relatado pelo mantenedor com
MSYS2 UCRT64 e LuaJIT: DLL compilada, schema C com 129 checks, schema Lua com
82, stress e demais suítes Lua aprovados; `test_astype` interrompeu na fronteira
subnormal. Probe direto de `_strtod_l("0x1.fffffffffffffp-1023")`: modo 0,
valor zero, errno 0, consumo de 23 bytes. Portanto, há evidência direta da
conversão incorreta na CRT desse ambiente; não se declarou aprovação Windows.

Correção local em `src/smaug_convert.c`: hexadecimal convertido por bits com
guard/sticky, nearest-even e arredondamentos dirigidos; expoente combinado com
a posição da mantissa antes de limitar a faixa. Sem alocação adicional, troca
de locale ou modo de arredondamento; decimal mantém a libc. Contrato e ABI
preservados. `test_astype.c` passou 808 checks com GCC 16.2.1, inclusive build
`-O2 -Wall -Wextra -Wpedantic -Werror`; `make test` e `make test-lua` passaram
no Linux (13 binários C e 21 suítes Lua). Comparação dirigida temporária com
`strtod` da glibc passou 40.000 entradas hex aleatórias (seed 808) nos quatro
modos, conferindo status, valor e preservação da saída. Coverage e auditoria
de mutantes não foram regeneradas nesta etapa.

O `build.ps1` também marcava falsamente `test_io_c` como falha por seu stdout
começar com o SKIP de `/dev/full`; agora confere a última linha e o exit code,
como já fazia no stress. O teste Lua de schema usa arquivo em `build/` para
evitar o caminho sem permissão fornecido por `os.tmpname()` no Windows.
Próximo passo: copiar as correções e executar novamente `scripts/build.ps1`
no Windows; PowerShell/MinGW indisponíveis neste ambiente Linux. Mantidas as
pendências de ASan/UBSan e do arredondamento decimal sob Valgrind.

**Revisão de test_astype — 2026-10-08:** leitura integral de
`tests/c/test_astype.c`; corrigida a cópia para buffer local no roundtrip de
string (ponteiro, capacidade e consumo completo) e exigido resultado exato
na fronteira subnormal para cada modo de arredondamento. O diagnóstico
temporário de `_strtod_l` agora ocorre após a falha do parser, sem interferir
na chamada observada. Base `8614ccf` com alterações locais; compilação Linux
com `gcc -std=c11 -g -O0 -Wall -Wextra -Wpedantic -Werror -Iinclude
tests/c/test_astype.c src/*.c -lm -o build/test_astype_review` e execução
aprovadas: 526 checks. Guard de estilo e diff aprovados. Sem mudança no core
ou na ABI. O relato Windows indica falha na fronteira (modo 0, status 7);
o probe direto da CRT e a execução deste arquivo revisado no Windows seguem
pendentes. A revisão não certifica injeção de OOM nas fixtures: helpers como
`make_string` ainda não conferem todos os retornos de criação/setter (C03/C04),
pendência de endurecimento dos testes em R6.

Gramática R1 aprovada em 28/09. A revisão de 29/09 corrigiu o parser,
`astype` e o consumidor CSV, mantendo a ABI e a arquitetura de anéis.
**Estado de entrega:** implementação de schema registrada em `1eafa7a`;
revisão documental de 05/10 local, sem commit. R1 permanece aberta.

O checkpoint atual também inclui a frente R3: JSON e CSV seguem o contrato
estrito baseado em RFC 8259/RFC 4180 e TensorFlow comparativo. JSON/CSV aceitam
um BOM inicial apenas na leitura; writers nunca o emitem. CSV exige largura
uniforme, aceita LF/CRLF, rejeita CR isolado e aspas malformadas. UTF-8 inválido
continua sendo rejeitado no JSON, com byte e motivo, sem resultado parcial.

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

**Seguimento — estrutura e números JSON (2026-09-29):** leitura exige fechamento
do array, vírgulas entre registros e consumo integral após whitespace; erros
trazem byte base 0 e motivo, sem tabela parcial. A política numérica foi aprovada
pelo mantenedor após os exemplos e referências de
[representação numérica](IO_REVIEW.md#r3-representacao-proposta). Inteiros usam
int64; fração/expoente usa o core f64, com subnormais preservados, sem truncamento
ou dependência do locale global. Overflow/underflow para zero são diagnosticados.
A promoção de coluna mista exige exatidão dos inteiros, considerando o dtype final.
O probe `scripts/audit_json_numeric_policy.c` permite comparar antes/depois;
não é teste de aceitação por si só.

Validação: `make test` (12 executáveis C; I/O 430, allocfail 2.667 checks) e
`make test-lua` (20 suítes) passaram. I/O passou com `-O2 -Wall -Wextra
-Wpedantic -Werror` e Valgrind: 1.962 alocações/liberações, zero blocos pendentes
e zero erros. Allocfail também passou sob Valgrind, sem erros ou blocos pendentes.
O probe recompilado em `pt_BR.utf8` confirmou ponto fixo, subnormal preservado e
token longo com valor 1. Guard de estilo (33 arquivos) e `git diff --check` passaram.
A campanha numérica detectou 13 mutantes compiláveis, quatro novos de JSON
(precisão, truncamento, zero inicial e overflow); baselines de I/O e allocfail
passaram sob Valgrind. Não é campanha completa de mutações estruturais/Unicode.

**Seguimento — associação JSON por nome (2026-09-29):** união dos campos pela
primeira aparição, NA retroativo e identidade por nome original/ordinal da
ocorrência. Sufixos publicados não participam da associação; colisões com nomes
literais preservam todos os valores. Inferência, promoção numérica e construção
usam o mesmo mapa. O setter de string passa a propagar falha de alocação.

`make test` passou (I/O 467 checks; allocfail 2.745). `make test-lua` passou;
o teste JSON ampliado passou depois com 56 checks, incluindo roundtrip Lua.
A varredura OOM específica usa a contagem real de alocações, exige a injeção e
verifica ausência de resultado parcial e recuperação. Nomes com NUL ainda não
estão cobertos: dependem da migração de comprimentos da fronteira C/Lua.
I/O passou com `-O2 -Wall -Wextra -Wpedantic -Werror` e sob Valgrind: 2.095
alocações/liberações, zero erros/blocos pendentes. Baseline allocfail também
passou sob Valgrind. A campanha ampliada detectou 16 mutantes compiláveis,
três novos de associação JSON; guard de estilo e diff passaram. Sem nova
execução Windows/sanitizers ou regeneração de cobertura global.

**Seguimento — transporte de bytes e ABI 1 (2026-09-29):** NUL preservado em
valores e nomes C↔Lua↔CSV/JSON; JSON exige escape, CSV carrega bytes crus.
`smaug_column_t.name_len` e `smaug_csv_opts_t.na_lengths` transportam tamanhos
reais. Writers rejeitam ponteiro de nome NULL; vazio exige ponteiro válido e
comprimento zero. Marcadores não vazios exigem comprimentos e ponteiros válidos;
lista explícita vazia desativa padrões. Token com NUL não é convertido por prefixo.
Recompilar biblioteca e consumidores juntos: o novo frontend exige ABI 1 antes
de acessar structs. O mecanismo não protege frontends antigos.

`make test` passou (I/O 549 checks; allocfail 2.750), assim como as 20 suítes
Lua; JSON ampliado tem 67 checks. Build I/O com `-O2 -Wall -Wextra -Wpedantic
-Werror` passou; Valgrind registrou 2.383 alocações/liberações, zero erros/blocos
pendentes. Baseline allocfail passou sob Valgrind na campanha de 20 mutantes
compiláveis, todos detectados. `scripts/audit_io_abi.py` verificou sizeof/offsetof,
símbolo ausente/versão divergente sem fallback, fallback de arquivo não carregável
e falha do setter de string na ponte Lua com cleanup/recuperação. Guard e diff
passaram. Sem nova execução Windows/sanitizers ou cobertura global.

**Seguimento — ponte int64 e cleanup Lua (2026-09-29):** reader mantém cdata,
writer usa `get_raw`; getter público `get()` mantém seu contrato. A adaptação
para DataSet libera a tabela C em sucesso/erro; construção da série inteira no
writer registra ownership antes do laço e confere status dos setters.

As 20 suítes Lua passaram (CSV 145 checks, JSON 102). Expectativas independentes
cobrem leitura, escrita e roundtrip de ±(2^53+1), INT64_MAX, INT64_MIN, zero e NA.
O probe ABI manteve suas verificações e adicionou falha no setter int64/exceção
na segunda coluna, com liberação contada e recuperação. Três mutantes Lua foram
detectados: reader via number, writer via get e tabela C abandonada. O teste
antigo de injeção em get agora alcança get_raw e exige uma injeção real. Guard
e diff passaram. Sem mudança C nesta etapa; as evidências C/Valgrind anteriores
não equivalem a nova execução de memória para todo o frontend.

**Preparação — leitura estrita (2026-09-29):** probe
`scripts/audit_io_strict_policy.c` compilado com warnings como erro reproduziu
UTF-8 inválido aceito pelo reader/writer JSON, campos CSV excedentes descartados,
aspas não fechadas aceitas e texto após aspas convertido em linha extra. A
recomendação e as referências estão no review de I/O. Solicitadas as escolhas
JSON UTF-8/BOM e largura CSV; aguardando resposta antes das mudanças dependentes.
A aceitação atual de linha curta tem teste explícito. TensorFlow foi incluído
como referência comparativa no review, a pedido do mantenedor: schema/default
por campo, distinção entre largura inválida e campo vazio, e política explícita
de erros Unicode. Consulta documental/de fonte, sem execução local do TensorFlow. Nenhuma alteração de parser
nesta preparação; o probe é observacional, não um teste de conformidade.

**Decisão documental — referências de I/O (2026-09-29):** mantenedor aprovou
TensorFlow como referência comparativa e a separação entre erro estrutural,
ausência em campo existente e erro de codificação. Registrado em
[CONTRACT](CONTRACT.md#io-erros-estrutura-ausencia-codificacao): leitura estrita
rejeita estrutura inválida; JSON reader/writer rejeitam UTF-8 inválido sem
substituir bytes. Core/CSV preservam bytes crus. Não adotar defaults TensorFlow
nem introduzir dependência. UTF-8 JSON foi implementado no seguimento abaixo;
BOM e largura CSV foram resolvidos pela política estrita seguinte.

**Implementação UTF-8 JSON (2026-09-29):** reader e writer rejeitam sequências
inválidas, truncadas, sobrelongas, surrogate codificadas e codepoints fora de
U+10FFFF em nomes/valores. O diagnóstico informa o byte; falha não publica
tabela nem buffer parcial. Foram adicionados testes C/Lua de fronteira e onze
mutantes dirigidos de UTF-8/dialeto, todos detectados. Core/CSV continuam
preservando bytes crus.

**Implementação do dialeto CSV (2026-09-29):** a leitura remove um único BOM
inicial, aceita LF e CRLF, rejeita CR isolado e diagnostica aspas não fechadas,
texto após aspas fechadas e aspas em campo não citado. Cada registro deve ter a
mesma largura do header; campo vazio explícito continua ausência/NA. A escrita
não emite BOM.

Validação deste checkpoint: `make test` passou com 700 verificações de I/O C e
2.788 verificações de alocação; `make test-lua` passou com 149 verificações CSV
e 103 JSON. O build otimizado com `-Werror` e Valgrind passaram duas vezes no
I/O. ABI, guard de estilo e `git diff --check` passaram. A campanha C agora
detecta 31 mutantes compiláveis, sem sobreviventes. Windows, sanitizers,
schema explícito e modo tolerante opcional permanecem fora desta retomada.

**Retomada — fechamento de arquivo (2026-09-29):** corrigidos os writers CSV/JSON
que retornavam sucesso quando `fclose` falhava ao descarregar o buffer. Regressão
em `/dev/full` falhou nos dois writers antes da correção e passou depois: 703
checks de I/O, build GCC com `-O2 -Wall -Wextra -Wpedantic -Werror` e Valgrind
(2.940 alocações/liberações, zero erros/blocos pendentes). Sem mudança de ABI;
sem garantia de escrita atômica. `make test-lua` passou nas 20 suítes (CSV 149,
JSON 103 checks); guard de estilo e diff aprovados.
ASan/UBSan tentados novamente: link ASan falhou pela mesma biblioteca ausente;
UBSan também tem runtime ausente. Compilador MinGW não encontrado no PATH.
Schema explícito tem direção conceitual aprovada: reutilizável pelo Smaug,
com primeira implementação em CSV/JSON. Opções de importação ficam separadas
da descrição dos dados; `.smg` e Models permanecem futuros. Contrato em
[Schema reutilizável](CONTRACT.md#schema-reutilizavel); detalhes da API,
conversões e modo tolerante continuam em proposta no IO_REVIEW, sem implementação.
Diagnóstico detalhado de arquivo e validação dos readers permanecem pendentes.

**Implementação — schema reutilizável (2026-09-29):** `smaug_schema.h`/C e
`smaug.Schema`/FFI agora implementam o primeiro recorte aprovado. O schema é
completo, não vazio, com nomes únicos por bytes, `bool`/`int64`/`float64`/`string`
e `nullable` explícito. CSV com header e JSON associam por nome; CSV sem header
associa por posição. A saída segue a ordem do schema, inclusive em `[]`, header
sem dados e colunas só NA. Extras, duplicatas, ausência não nullable, famílias
JSON incompatíveis, conversão numérica inválida, perda de precisão, UTF-8
inválido e falhas estruturais geram erro sem tabela parcial. String mantém zeros
iniciais e bytes/NUL; descritores e resultados têm ownership separado.

As APIs existentes sem schema preservam a inferência anterior. Leitores de
memória e arquivo foram adicionados sem alterar layouts ABI existentes; erro de
leitura/fechamento também é propagado. Defaults, overrides parciais, modo
tolerante, datetime/categorical e persistência `.smg` continuam fora do recorte.

**Verificação da implementação:** `bash scripts/build.sh --skip-manifest` passou
no Linux com GCC 16.2.1/glibc 2.43: 13 binários C, incluindo `test_schema`
(131 checks), `test_io_c` (703), e `test_allocfail` (3.927 verificações). As 21
suítes Lua passaram; schema teve 82 checks, CSV 149 e JSON 103. O guard de estilo
(35 arquivos), ABI C/FFI e `git diff --check` passaram. `test_schema` e
`test_allocfail` passaram sob Valgrind, sem erros ou blocos pendentes. A auditoria
numérica/I-O detectou 39 mutantes compiláveis, sem sobreviventes; inclui nove
mutantes específicos de schema. A coleta de coverage foi regenerada: 5.218/5.366
linhas (97,24%) e 5.216/5.660 branches-alvo (92,16%); `smaug_io_schema.c` ficou
91,73%/83,15% e `smaug_schema.c` 100%/97,06%. A paridade atualizada passou nos
15 eixos, incluindo schema no C↔Lua, cobertura de testes e ABI.

**Limitações desta rodada:** Windows/MinGW não foi executado; ASan/UBSan
continuam sem runtime utilizável neste ambiente. O executor Windows foi ajustado
para exigir exit code zero além do texto `PASS`, mas ainda precisa de execução
na plataforma. O relatório de coverage agora inclui as novas fontes e suítes;
parity/manifest continuam artefatos gerados, não substitutos da execução Windows.
Valgrind individual de `test_schema` e `test_allocfail` passou sem erros ou
vazamentos. A rodada Valgrind completa para no `test_astype` por divergência
numérica conhecida no arredondamento de subnormal sob Valgrind; o erro não é de
memória e o binário libera todos os blocos.

**Retomada — consumidores públicos de schema (2026-10-05):** revisão dirigida
de `smaug_schema.h`, validação C, leitores de memória/arquivo CSV/JSON,
`smaug.core.schema` e adaptadores Lua. Conferidos descritores emprestados,
âncoras de lifetime, capacidade de símbolos, ordem e transporte de resultados.
Não foi identificada necessidade de alterar contrato ou ABI nesse recorte.
O consumidor externo exercitado foi a suíte C existente, desta vez ligada à
biblioteca compartilhada; isso não certifica aplicações de terceiros.

Árvore base `1eafa7a`, Linux, GCC 16.2.1, glibc 2.43, LuaJIT 2.1.1767980792:

- `make -B build/libsmaug.so` recompilou a biblioteca; `test_schema.c` ligado
  com `-Lbuild -lsmaug` passou 131 checks. O consumidor compilou com
  `-std=c11 -Wall -Wextra -Wpedantic -Werror`.
- `luajit tests/io/test_schema.lua` passou 82 checks.
- `python3 scripts/audit_io_abi.py` passou layouts C/FFI, rejeição de ABI
  incompatível, ausência de capacidade schema, fallback e cleanup; detectou
  as três mutações da ponte Lua.
- `valgrind --leak-check=full --error-exitcode=1 ./build/test_schema_shared`
  passou com Valgrind 3.27.1: 728 alocações/liberações, zero erros e zero
  blocos pendentes.
- `smaug_schema.h`, `smaug_io.h` e `smaug.h` compilaram isoladamente com
  `-fsyntax-only` e os mesmos warnings estritos.
- `python3 scripts/check_test_style.py` passou nos 35 arquivos;
  `git diff --check` passou. A alteração preexistente de CODING_STYLE foi preservada.

ASan/UBSan continuam sem validação: o link da suíte instrumentada falhou pela
ausência de `/usr/lib64/libasan.so.8.0.0`; um probe independente de UBSan
também falhou pela ausência de `/usr/lib64/libubsan.so.1.0.0`. MinGW e PowerShell
não foram encontrados no PATH; Windows não foi executado. Não houve nova
campanha completa, coverage ou regeneração de manifest/parity nesta revisão.
Comandos reproduzíveis e escopo da validação foram adicionados ao
[guia de build](Build_and_Testing.md), incluindo as suítes de schema no inventário.

**Próximo passo:** executar a validação Windows e a suíte instrumentada em
ambiente com runtimes ASan/UBSan disponíveis; ampliar depois a campanha para
as famílias numéricas/I/O e falhas de alocação. Schema parcial, defaults e modo
tolerante exigem decisão própria antes de qualquer extensão.

| Frente | Já conferido | Falta para avançar |
|---|---|---|
| Core numérico | Parser/formatter/astype/CSV/JSON migrados; correções Windows e regressões ampliadas nos consumidores verificadas; evidências Linux anteriores preservadas | Executar matriz ampliada no Linux/sanitizers; auditar famílias restantes |
| I/O | NUL, int64, associação JSON, UTF-8, dialeto estrito e schema completo memória/arquivo implementados; baselines Valgrind anteriores e regressões numéricas Windows diretas/DLL registradas | Revisar diagnóstico de arquivo/readers e executar sanitizers; schema parcial/defaults/modo tolerante dependem de decisão |
| Inferência Lua | Entradas mapeadas no review de I/O | Decidir divergências, sem uniformizar por conveniência |
| Datetime | Parser e astype estritos C/Lua implementados em 25/09; build Windows histórica passou | Integração restante, 11 componentes escalares + 11 de série, formatter e semana ISO |
| Relacional | Reescrita inicial; três defeitos corrigidos; 68 casos passaram no seguimento de 25/09 | Contratos count/pivot/join, migração dos casos antigos e mutações |
| Verificação | Inventário/review dos executores; cobertura e parity disponíveis como artefatos históricos | Corrigir confiabilidade e comprovar detecção por família |
| Documentação | Roadmap substituído; checkpoints unificados; redundâncias removidas | Manter este checkpoint após cada frente, sem novos diários paralelos |

A implementação R1 tem regressões C para gramática, limites, subnormal,
underflow, overflow e preservação de saída. Isso não é teste da futura migração
ABI. Correções Windows e execução completa após ambas registradas acima;
a validação com sanitizers permanece pendente.
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
| R05 — exclusões | Guards classificados como inalcançáveis foram atingidos por entradas públicas | R6: manter triagem individual de cada `COV-EXCL-BR` |
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

Comentários de exclusões precisam de prova por ramo, conforme o Contrato 10 e o
relatório de cobertura da árvore medida. Referências numéricas antigas no
código continuam rastreáveis apenas na versão Git indicada abaixo. Não
renumerar comentários mecanicamente nem interpretar marcações históricas como
garantias; `COV-EXCL-BR` é uma decisão local do ramo, não um selo de correção.
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
