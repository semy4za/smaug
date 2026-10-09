# Changelog — Smaug

[Documentação](README.md) · [Estado e próximos passos](Roadmap.md#checkpoint)

Marcos resumidos. Decisões vigentes ficam no [contrato](CONTRACT.md);
checkpoints e pendências ficam no roadmap. Resultados de uma execução não
certificam versões posteriores.

## 2026-10-09 — Reconstrução da paridade ponta a ponta

Substituído o parity report textual por um runner único e reproduzível em
Python/LuaJIT: ele recompila a biblioteca em diretório isolado, identifica a
DLL/.so carregada, executa os eixos de dtype, Series/DataSet, FFI, relacional,
I/O, nulidade, lifecycle, textualidade e reentrância, e compila probes C de
assinaturas e layout. O resultado estruturado fica em
`docs/PARITY_REPORT.json`, com a versão Markdown derivada no mesmo passo;
comandos, hashes, ferramentas e limites ficam registrados por execução.

A execução Windows desta árvore produziu 1.125 registros: 839 PASS, 273
OBSERVED, 12 REVIEW e 1 FAIL, sem erro de infraestrutura. O status é FAIL por uma
divergência reproduzida: `Series<bool>:where(cond, other_series)` converte uma
tabela em vez de preservar `false`; o caso já estava documentado em R4/R7 e
permanece explícito para a próxima correção. O agrupamento por dtype e o
contrato de `CategoricalSeries:value_counts` foram conferidos contra os testes
existentes e deixaram de gerar falsos positivos. O comando é
`python scripts/parity/runner.py` (exit 1 para divergência, 2 para erro de
infraestrutura). O checkpoint do roadmap registra o próximo passo Linux.

## 2026-10-08 — Consolidação Windows das regressões numéricas

Execução Windows/UCRT64 consolidada após os fixes hexadecimal/decimal: 14
executáveis C e 21 suítes Lua aprovados. Regressões verificam arredondamento
exato, sinal, máscaras e erros em astype e leitores CSV/JSON, em memória/arquivo,
com inferência/schema. Baselines otimizadas com warnings estritos passaram com
fontes diretos e DLL; quatro suítes Lua confirmaram a DLL efetivamente carregada.

Nova auditoria reproduzível registra ferramentas, comandos, hashes e skips;
sete mutações compiláveis foram detectadas por I/O e astype, sem sobreviventes.
Produção, contrato e ABI preservados. ASan/UBSan e execução Linux da matriz
ampliada continuam pendentes. Próxima frente solicitada: reconstruir a paridade
de ponta a ponta, sem usar o relatório atual como certificação.

## 2026-10-08 — Alinhamento dos resumos de retomada

Resumos R1–R3 e fila do roadmap alinhados às entregas já registradas: migração
numérica/formatadores, transporte C/Lua, schema completo e correções Windows
hexadecimal/decimal. A campanha mais recente registra 44 mutantes detectados.
Correção implementada e registro de validação por plataforma aparecem como
estados distintos; execução Windows completa após as correções e sanitizers
continuam sem evidência consolidada. Nenhum teste novo foi executado nesta
revisão documental.

## 2026-10-08 — Underflow decimal com arredondamento dirigido

O commit `f93d4a5` corrige o zero prematuro devolvido pela libc para decimais
muito pequenos: FE_UPWARD positivo e FE_DOWNWARD negativo produzem o menor
subnormal com o sinal da entrada. Os demais modos preservam o diagnóstico e
a saída anterior; zero textual mantém seu sinal. Regressões cobrem ambos os
sinais, quatro modos e entradas C-string/slice. Revisão Linux: 856 checks
aprovados com warnings estritos e no Valgrind, sem erros ou vazamentos,
resolvendo também a divergência anteriormente registrada nessa ferramenta.

A auditoria numérica/I-O ganhou uma baseline com underflow prematuro simulado
e cinco mutações da correção decimal. Campanha completa aprovada no Linux:
44 mutantes compiláveis detectados, nenhum sobrevivente; baselines de I/O,
schema e falhas de alocação aprovadas no Valgrind.

## 2026-10-08 — Conversão hexadecimal na fronteira subnormal

Relato Windows confirmou `_strtod_l` retornando zero para um token que deveria
arredondar para `DBL_MIN`. O core agora converte hexadecimal diretamente, com
arredondamento único e preservação de saída em erro. Regressões cobrem sinais,
quatro modos, empates, bits finais e expoentes longos. O executor Windows passa
a conferir o resumo final `PASS` após avisos `SKIP`, mantendo a exigência de
exit code zero. Suítes C/Lua aprovadas no Linux. Correção Windows implementada;
registro da execução completa após as correções hexadecimal/decimal ainda não
consolidado no checkpoint.

## 2026-10-05 — Revisão dos consumidores de schema

Conferida a ligação de consumidor C à biblioteca compartilhada, além dos
consumidores Lua e da auditoria C/FFI. Guia de build ampliado com validação
dirigida de schema e comandos de sanitizers; limitações de ambiente e evidências
registradas no checkpoint. Sem mudança de contrato ou ABI.

## 2026-09-29 — Schema reutilizável em CSV/JSON

Implementados `smaug.Schema` e leitores C com schema completo: associação por
nome/posição, tipos e nulidade explícitos, ordem estável, nomes/valores com NUL
e conversões estritas. Entrada em memória e arquivo; falhas não publicam tabela
parcial. APIs sem schema e layouts existentes preservados. Testes C/Lua,
varredura OOM, ABI e inventários de build/coverage/paridade ampliados.

## 2026-09-29 — Direção do schema reutilizável

Aprovado o desenho conceitual de schema reutilizável pelo Smaug, começando por
CSV/JSON e separando descrição dos dados das opções de importação. `.smg` e
Models continuam futuros; API e políticas detalhadas ainda em definição.

## 2026-09-29 — Falha no fechamento de arquivos CSV/JSON

Writers em arquivo agora retornam erro quando o fechamento falha ao gravar
bytes pendentes, mesmo se `fwrite` tiver aceitado todo o buffer. Regressão
Linux em `/dev/full`; assinaturas e ABI preservadas.

## 2026-09-29 — Referências e categorias de erro em I/O

Aprovado o uso comparativo de TensorFlow e a separação entre erro estrutural,
ausência e erro de codificação na leitura estrita. Contrato e review registram
fontes, limites da comparação e decisões de dialeto ainda abertas. A validação
UTF-8 JSON foi implementada no seguimento abaixo.

## 2026-09-29 — UTF-8 estrito no JSON

Reader e writer rejeitam UTF-8 inválido em nomes e valores, com diagnóstico no
byte da falha e sem substituição, descarte ou saída parcial. O validador cobre
as fronteiras RFC 3629, escapes Unicode, truncamento e crescimento de buffers.
Testes C/Lua e cinco mutantes dirigidos cobrem as novas regras; CSV/core seguem
byte-oriented.

## 2026-09-29 — Dialeto CSV estrito e BOM de entrada

JSON e CSV aceitam um único BOM inicial na leitura, sem emitir BOM na escrita.
CSV aceita LF/CRLF, rejeita CR isolado, aspas malformadas e registros com
largura diferente do header. Campo vazio explícito continua NA. Seis mutantes
de dialeto e cinco de UTF-8 foram detectados, junto da campanha anterior.

## 2026-09-29 — JSON estrito numérico, associação e transporte de bytes

JSON usa conversão do core com gramática própria, preserva subnormais e exige
exatidão na promoção inteira. União de campos por nome/ocorrência substitui a
associação posicional. CSV/JSON preservam NUL em valores e nomes, inclusive pela
ponte Lua; marcadores CSV passam a ter comprimentos explícitos.

**Mudança de ABI:** `smaug_column_t.name_len`, `smaug_csv_opts_t.na_lengths` e
consulta `smaug_abi_version()` (versão 1). Recompilar biblioteca e consumidores
juntos. O novo frontend rejeita bibliotecas carregadas incompatíveis; frontends
antigos não fazem essa proteção. Evidências e pendências no checkpoint R2/R3.

Seguimento: ponte CSV/JSON preserva int64 como cdata nas duas direções, com
limites e NA verificados independentemente. Exceções na construção do DataSet
liberam a tabela C; setters inteiros na escrita são conferidos. Três mutantes
do frontend detectados, além da campanha C já registrada.


## 2026-09-29 — Revisão de R1 e falhas operacionais no CSV

Parser inteiro valida sufixos após overflow; f64 reconhece overflow finito
saturado sem descartar subnormais. Astype e CSV propagam falhas operacionais;
CSV aceita decimal customizado longo, corrige rollback de realloc parcial e
confere o setter de string. Casos de OOM passam a comprovar injeção e
recuperação; seis mutações dirigidas detectadas. R1 continua aberta; evidências
e limitações no checkpoint, sem certificação global da suíte.

Seguimento da mesma frente: formatadores i64/f64 publicam texto completo ou
falham preservando o destino; f64 usa ponto fixo e restaura o locale da thread.
Consumidores astype/CSV/JSON passam a conferir falha de formatação. Verificados
buffers, limites, subnormais, locale e OOM; campanha cumulativa com nove
mutações detectadas. Ramo Windows e sanitizers continuam pendentes.

## 2026-09-28 — Padrões de engenharia C e Lua

Parsing: aprovada gramática explícita no review de I/O, com hexadecimal
inteiro em i64/f64 e fração/expoente apenas em f64, ponto independente de
locale, consumo completo, sem espaços nem payload NaN. Core implementado com
locale C explícito, acumulação inteira com limites prévios, diagnósticos de
sintaxe/overflow/underflow e preservação da saída em falha; `astype` propaga
falha operacional e mantém texto inconversível como NA.

Consolidado CODING_STYLE: C11, seleção de práticas CERT C/JPL, princípios de
legibilidade do Google e base LuaRocks/Lua 5.1/LuaJIT. Regras C01–C08 e L01–L07,
adaptações explícitas, contrato mínimo de API e registro de exceções orientam
a adoção incremental, começando por R1. Isso não certifica a base existente;
automação de análise/lint permanece em R6. Arquitetura de anéis preservada.

## 2026-09-27 — Consolidação documental

- Roadmap revisto contra código/consumidores, com frentes R1–R8, dependências,
  critérios de conclusão e checkpoint único. Entregas existentes saíram da
  fila de implementação inicial; comentários desatualizados têm revisão dirigida.
- Rework e parecer da suíte incorporados ao roadmap; removidas páginas
  redundantes e o índice experimental. Reviews especializados preservam
  evidência, sem manter outra fila. Histórico detalhado permanece no Git.
- Parsing numérico: há proposta local para rejeitar NUL interno em slices e
  saída NULL, com regressões C/Lua e validação dirigida. A escolha de contrato
  ainda exige discussão; não é registrada como entrega aprovada.
- Auditoria dos quatro helpers i64 reexecutada: 30.712 chamadas sem divergência,
  cinco mutações detectadas. Escopo e limites no review aritmético.
- Referências C/Lua confrontadas com headers, consumidores e probe de 24 casos:
  assinaturas `err_out`/`dayfirst`, NA de CSV, `min_count`, bool público e
  operações de janela foram alinhados; dois defeitos de execução ficaram
  registrados no R7 (diagnóstico de overflow em `prod` e `where` bool com Series).
- Verificação desta árvore: `scripts/build.sh --skip-lua --skip-stress --skip-manifest` passou
  12 binários C (5.002 verificações reportadas, incluindo alloc-fail); o probe Lua dirigido confirmou 22/24
  observações e preservou os dois achados do R7. Esse resultado é desta árvore,
  não uma certificação geral.

## 2026-09-26 — Auditoria de I/O e aritmética no Linux

Reproduzidas perdas de NUL/int64, saturação e corte de token numérico. Aprovadas
preservação de NUL e consulta de compatibilidade ABI; implementação pendente.
Registrados resultados observacionais, investigação dos consumidores e auditoria
independente dos quatro helpers checked. Ver [I/O](IO_REVIEW.md) e
[aritmética](CORE_ARITHMETIC_REVIEW.md).

## 2026-09-25 — Datetime estrito e correções relacionais

Parser compartilhado e astype string/int64/float64→datetime passaram a validar
precisão exata em milissegundos, anos zero/negativos e domínio UTC após offset,
com status e primeira posição inválida. Wrappers legados preservados; Lua
encaminha dayfirst e diagnóstico. Componentes e formatter continuam pendentes.

Reescrita relacional revelou três defeitos: função desconhecida em agg/transform
e colisão de chave composta. Corrigidos, com 68 casos passando no seguimento.
A auditoria da migração e os contratos count/pivot/join seguem abertos.
Build Windows registrada: 13 suítes C, 20 Lua e 15 eixos de paridade; sem nova
cobertura ou sanitizers. Paridade lexical não certifica comportamento.

## 2026-09-18 — Revisão dos contratos e da verificação

Auditoria diagnosticou testes sem poder de rejeição, lacunas datetime/OOM,
exclusões incorretas e limitações de runners/parity. Decidida reconstrução
incremental por família, mantendo regressões até validar substitutos.
Contratos de precisão, nulidade, COW, status e perfil datetime foram explicitados.
Destino atual dos nove achados: [roadmap](Roadmap.md#verificacao).

## Histórico detalhado

O relato anterior, incluindo decisões superadas e IDs numéricos, está na versão
Git `320b4bc`. Consultar localmente, sem restaurar arquivos:

```sh
git show 320b4bc:docs/CHANGELOG.md
git show 320b4bc:docs/Roadmap.md
git show 320b4bc:docs/TEST_SUITE_REWRITE_REVIEW.md
git log -- docs
```

Não reutilizar IDs antigos nem tratar promessas de uma sessão como contrato.
