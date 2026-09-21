# Rework da suíte de testes

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

<details>
<summary>Nesta página</summary>

- [Estado atual](#section-estado-atual)
- [Onde está cada informação](#section-onde-esta-cada-informacao)
- [Próxima decisão](#section-proxima-decisao)
- [Sequência do trabalho](#section-sequencia-do-trabalho)
- [Como manter estes documentos](#section-como-manter-estes-documentos)
- [Proveniência](#section-proveniencia)

</details>

[Documentação do projeto](README.md)

<a id="section-estado-atual"></a>

## Estado atual

Estamos fechando contratos e a migração das APIs antes de reconstruir a suíte.
O mapeamento inicial de datetime foi concluído. A migração do motor ainda não
começou; foi aplicada a integração Lua de `dayfirst` em `DataSet:astype` e a
validação booleana no helper e nas conversões. Validação focada: 283 checks
de datetime e 136 checks de DataSet passaram, além de `git diff --check`.
Isso não certifica a suíte inteira, cobertura ou memória.

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
