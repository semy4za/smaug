# Rework da suíte de testes

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

<details>
<summary>Nesta página</summary>

- [Estado atual](#section-estado-atual)
- [Retomada relacional — 2026-09-25](#section-retomada-relacional-2026-09-25)
- [Onde está cada informação](#section-onde-esta-cada-informacao)
- [Próxima decisão](#section-proxima-decisao)
- [Sequência do trabalho](#section-sequencia-do-trabalho)
- [Como manter estes documentos](#section-como-manter-estes-documentos)
- [Proveniência](#section-proveniencia)

</details>

[Documentação do projeto](README.md)

<a id="section-estado-atual"></a>

## Estado atual

Continuamos fechando contratos e a migração das APIs. Em 2026-09-25, por
solicitação do mantenedor, foi iniciada a reescrita isolada de
`tests/dataset/test_relational.lua`; o checkpoint está registrado abaixo.
Essa frente não conclui a reconstrução geral da suíte.
O mapeamento inicial de datetime foi concluído. A migração do motor ainda não
começou; foi aplicada a integração Lua de `dayfirst` em `DataSet:astype` e a
validação booleana no helper e nas conversões. Validação focada: 283 checks
de datetime e 136 checks de DataSet passaram, além de `git diff --check`.
Isso não certifica a suíte inteira, cobertura ou memória.

<a id="section-retomada-relacional-2026-09-25"></a>

## Retomada relacional — 2026-09-25

**Estado: reescrita inicial implementada; os três defeitos do checkpoint foram
corrigidos no seguimento abaixo. A auditoria da migração ainda não foi concluída.**
O pedido foi avaliar conteúdo, estrutura e coerência de apenas
[`test_relational.lua`](../tests/dataset/test_relational.lua), com base no
[parecer da suíte](TEST_SUITE_REWRITE_REVIEW.md) e no
[relatório de cobertura](COVERAGE.md). Nenhum fonte de produção foi alterado.
O mantenedor pediu este registro e uma entrada no changelog para continuar depois.

O arquivo agora tem um único bootstrap, helpers de comparação e casos nomeados
com escopo próprio. Verifica schema, valores, máscaras e multiplicidades;
usa esperados literais para agregações/pivot e um modelo independente por
comparação de listas para join. Os casos antigos de groupby, concat, join,
rejeição de NA em chaves, precisão int64 e NaN foram reorganizados. Foram
acrescentados resultados válidos de pivot/pivot_table, matrizes de join nos
quatro modos, interpolação de quantile e uma colisão de chave composta.
O executor percorre todos os casos e termina com erro se qualquer um falhar.

### Validação deste checkpoint

- Backend recompilado dos fontes locais com GCC/UCRT64, `-O2 -fwrapv`, em
  `build/smaug.dll`.
- `luajit tests/dataset/test_relational.lua`: **66 casos executados,
  63 passaram e 3 falharam; código de saída 1**. Não apresentar como suíte verde.
- O verificador `python scripts/check_test_style.py` não aponta violações
  no arquivo reescrito. A execução global ainda acusa três ocorrências de
  identificador `_` fora do escopo: duas em `dataset/test_stat.lua` e uma
  em `series/test_dt.lua`.
- `git diff --check` passou. Não houve execução da suíte completa, campanha
  de mutação, sanitizers ou nova medição de cobertura.

Falhas reproduzidas na implementação atual:

| Caso | Esperado | Observado |
|---|---|---|
| `groupby: agg rejeita nome de função desconhecido com erro orientado` | Rejeição explícita da função desconhecida | Erro Lua genérico: tentativa de chamar `fn_real`, que é string |
| `groupby: transform rejeita nome de função desconhecido com erro orientado` | Rejeição explícita da função desconhecida | Erro Lua genérico: tentativa de chamar `fn`, que é string |
| `groupby: chaves compostas não colidem com separadores no texto` | Dois grupos, somas 10 e 101 | Um único grupo |

Em `agg`/`transform`, a expressão `condição and builtin[nome] or nome`
mantém a string quando a função não existe, contornando a validação de função
ausente. Na colisão, as tuplas `("a", "b\1string:c")` e
`("a\1string:b", "c")` produzem a mesma codificação concatenada; `\1` denota
o byte 1 em Lua. A fixture distingue as tuplas sem reutilizar `keys.encode`.
Os testes permanecem ativos e falhando; nenhuma expectativa foi ajustada
para aceitar esses comportamentos.

### Seguimento — correção dos três defeitos (2026-09-25)

`agg` e `transform` agora resolvem nomes com uma condição explícita e validam
o tipo da função antes da execução, inclusive quando não há grupos. Callbacks
continuam aceitos. O helper comum de join/groupby delimita componentes pelo
comprimento da chave codificada, eliminando a ambiguidade do separador textual.
A sintaxe pública de join não foi alterada.

A suíte relacional passou com **68 casos**: os 66 anteriores e duas regressões
para funções inválidas em dados vazios/não vazios e callbacks com índices de
grupo. O verificador de estilo não acusa o arquivo alterado; persistem as três
ocorrências históricas de `_` em outros testes.

Build Windows completa com `scripts/build.ps1 -SkipManifest`: código 0,
13 suítes C (incluindo stress), 20 suítes Lua e 15 eixos de paridade passaram.
`git diff --check` passou. Não houve nova medição de cobertura, sanitizers ou
campanha de mutações; a migração desta família ainda requer a auditoria abaixo.

A busca por consumidores também encontrou concatenação com `\1` em
`dataset/_stat.lua` (chave de linha). Essa ocorrência permanece para revisão
da família de duplicatas; não está coberta por esta correção relacional.

### Próximos passos desta frente

1. Correção dos três defeitos acima concluída no seguimento; preservar as
   regressões ao continuar a auditoria.
2. Resolver as divergências de contrato antes de acrescentar expectativas:
   `groupby:count()` aparece como contagem de não-nulos na referência, mas
   conta linhas; `pivot_table` documenta padrão `mean`, mas usa `sum`;
   a documentação promete join composto, enquanto uma lista de duas strings
   é interpretada como `{chave_esquerda, chave_direita}`. Os testes atuais
   usam count sem NA nos valores, aggfunc explícito e chaves compostas em
   groupby; não certificam essas partes ambíguas de join/pivot_table.
3. Validar os comparadores com contraexemplos e executar mutações controladas:
   join vazio ou com multiplicidade incorreta, transform identidade,
   var totalmente NA e perda de máscara. Como o baseline já falha, verificar
   quais casos novos cada mutação faz falhar, não apenas o status global.
4. Auditar a correspondência dos cenários antigos com os novos e completar
   as lacunas restantes, incluindo independência do concat de múltiplas
   entradas, callbacks e preservação de int64 em colunas de valores.
5. Após as etapas restantes de contrato, mutação e auditoria, executar novamente
   este arquivo e os checks pertinentes. Só então concluir a migração desta família.

`COVERAGE.md` mede apenas o backend C, no commit `51184cb` de 2026-08-11.
Seus números não medem a árvore atual nem a cobertura de `_relational.lua`.
O relatório foi considerado como contexto para fronteiras de tipos, vazios
e máscaras; não houve alteração dos percentuais, exclusões ou alegação de
cobertura nova. O parecer histórico e os contratos normativos foram preservados.

<a id="section-onde-esta-cada-informacao"></a>

## Onde está cada informação

| Documento | Responsabilidade |
|---|---|
| [Contrato](CONTRACT.md) | Decisões normativas aprovadas: domínio datetime, entrada, erros e detecção de datas |
| [Referência Lua](API_INDEX.md#section-datetime-migracao-lua) | Métodos Lua, opções, mensagens e consumidores do frontend |
| [Referência C](API_Reference.md#section-datetime-migracao-c) | Assinaturas, status, memória, consumidores C e fronteira FFI |
| [Parecer da suíte](TEST_SUITE_REWRITE_REVIEW.md) | Diagnóstico R01–R09, plano de reconstrução e critérios de encerramento |
| [Inventário de exclusões](TEST_SUITE_EXCLUSIONS_REVIEW.md) | Evidências e triagem individual das 153 marcações |
| [Arquitetura](ARCHITECTURE.md) e [COW](COW.md) | Responsabilidades e contratos de memória |

<a id="section-proxima-decisao"></a>

## Próxima decisão

O padrão dos 11 componentes escalares está aprovado e registrado na
[referência C](API_Reference.md#section-decisao-fechada-e-alcance).
O comportamento das 11 operações de componentes em série foi aprovado em
2026-09-21 e registrado no [contrato](CONTRACT.md#section-perfil-datetime-decisoes-aprovadas-em-2026-09-18).
O padrão C dessas 11 funções também está aprovado: status, série por `out`
somente em sucesso e `error_index` opcional, sem estrutura nova de diagnóstico.
Está aprovado que o índice apenas transporta a posição do primeiro elemento
que falhou do C ao Lua: status permanece no C e mensagem é montada no Lua.
Regra de escrita aprovada: índice escrito apenas em falha de elemento;
em sucesso ou falha sem posição, fica intocado e não é consultado, sem sentinela.
A correspondência entre status e validade do índice está aprovada e registrada
na referência C. A prioridade de interpretação textual foi revista e aprovada
no contrato: formato explícito, reconhecimento com ordem configurada e padrão
documentado. Foi aprovado preservar o padrão mês/dia existente, conforme o
contrato. O conjunto inicial de formatos também está aprovado e registrado
no contrato. O argumento Lua `dayfirst=false` está aprovado, preservando
`Series.dt_parse(str, dayfirst)`. A API inicial reconhece `/` e `-` nos
formatos aprovados, sem argumento de formato explícito; essa opção fica para
ampliação futura. O próximo ponto é fechar a integração de `dayfirst` nas
demais entradas, antes de retomar o diagnóstico
da conversão textual. Modo automático estrito
opt-in permanece proposta separada.
Integração Lua aplicada: `DataSet:astype` encaminha `dayfirst` às conversões
string→datetime; helper e astype validam o booleano. Ver a referência Lua.
Essa etapa não implementa conversão estrita nem a migração C. As demais
implementações e validações continuam pendentes; alterações no motor devem
ficar restritas às correções e à comunicação de erros necessárias.

Depois, fechar opções de ordem de data e helpers Lua, compatibilidade e
formatação. A lista técnica completa
fica nas referências [C](API_Reference.md#section-decisoes-restantes-em-ordem)
e [Lua](API_INDEX.md#section-datetime-migracao-lua).

<a id="section-sequencia-do-trabalho"></a>

## Sequência do trabalho

1. Fechar a migração datetime antes de alterar assinaturas.
2. Continuar contratos de lifetime/invalidação de views, overflow intermediário,
   conversões numéricas, preservação de estado em falhas e suporte por dtype.
3. Reconstruir por famílias com regressões discriminantes, oracles independentes
   e rastreabilidade das exclusões, conforme o parecer.

<a id="section-como-manter-estes-documentos"></a>

## Como manter estes documentos

Atualizar decisões no contrato, propostas e impactos na referência Lua ou C,
e somente o ponto
de parada nesta página. Não copiar o contrato em notas de sessão. Parecer e
inventário preservam o diagnóstico da árvore auditada; fatos posteriores devem
ser identificados como seguimento, sem reescrever a evidência histórica.

A política inicial de astype datetime tolerante foi substituída pela conversão
explícita estrita; eventual modo tolerante opt-in continua em discussão.
A sugestão inicial de nome `smaug_dt_year_checked` foi substituída pelo nome
público `smaug_dt_year`. As decisões atuais estão no contrato.

<a id="section-proveniencia"></a>

## Proveniência

Esta página consolida as antigas notas de sessão de 2026-09-18; decisões e
gaps técnicos foram incorporados ao contrato e às referências Lua e C. O parecer conserva
a auditoria inicial. A exclusão anterior de `docs/CODE_REVIEW.md` já estava
presente antes das notas originais e não foi atribuída ao assistente.
Relatórios históricos e contagem de checks não certificam a árvore atual.
Nenhum commit foi criado nesta organização.

---

[Referência do Núcleo C](API_Reference.md) · [Rework da suíte](TEST_SUITE_REWORK.md) · [Início da documentação](README.md)
