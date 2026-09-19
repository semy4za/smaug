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
O mapeamento inicial de datetime foi concluído; a implementação não começou.
As alterações desta etapa são documentais. Não há nova certificação de testes,
cobertura ou memória.

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

Estender aos outros dez componentes de calendário o padrão aprovado para
`smaug_dt_year`: status no retorno, resultado por ponteiro, sem sufixo
`_checked`, saída preservada em falha. No Lua, manter `.dt:year()`.

Depois, fechar saída de séries e diagnóstico por chamada, opções de ordem de
data e helpers Lua, compatibilidade e formatação. A lista técnica completa
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
