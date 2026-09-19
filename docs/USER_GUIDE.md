# Guia do usuário

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

<details>
<summary>Nesta página</summary>

- [Introdução às estruturas de dados](#section-introducao-as-estruturas-de-dados)
- [Funcionalidades básicas](#section-funcionalidades-basicas)
- [Entrada e saída de dados](#section-entrada-e-saida-de-dados)
- [Indexação e seleção](#section-indexacao-e-selecao)
- [Copy-on-Write](#section-copy-on-write)
- [Junção, concatenação e comparação](#section-juncao-concatenacao-e-comparacao)
- [Remodelagem e tabelas dinâmicas](#section-remodelagem-e-tabelas-dinamicas)
- [Trabalhando com texto](#section-trabalhando-com-texto)
- [Trabalhando com dados ausentes](#section-trabalhando-com-dados-ausentes)
- [Dados categóricos](#section-dados-categoricos)
- [Inteiros e booleanos anuláveis](#section-inteiros-e-booleanos-anulaveis)
- [Apresentação de tabelas](#section-apresentacao-de-tabelas)
- [Funções definidas pelo usuário](#section-funcoes-definidas-pelo-usuario)
- [Agrupamento de dados](#section-agrupamento-de-dados)
- [Operações de janela](#section-operacoes-de-janela)
- [Séries temporais e datas](#section-series-temporais-e-datas)
- [Diferenças de tempo](#section-diferencas-de-tempo)
- [Desempenho e limitações](#section-desempenho-e-limitacoes)

</details>

Este guia organiza os recursos do Smaug por assunto. Para começar do zero,
leia [Primeiros passos](GETTING_STARTED.md). As listas de métodos ficam na
[Referência da API](API_INDEX.md); regras de comportamento ficam no
[Contrato](CONTRACT.md).

A sequência de assuntos acompanha o [guia do pandas](https://pandas.pydata.org/docs/user_guide/index.html).
Ela não implica compatibilidade de assinaturas nem suporte a todos os recursos
do pandas.

<a id="section-introducao-as-estruturas-de-dados"></a>

## Introdução às estruturas de dados

Series é uma coluna tipada. DataSet reúne colunas com o mesmo comprimento.
CategoricalSeries representa valores por categorias e códigos.
Comece pelos construtores em [Primeiros passos](GETTING_STARTED.md) e consulte
Series, DataSet e CategoricalSeries no [catálogo](API_INDEX.md).

<a id="section-funcionalidades-basicas"></a>

## Funcionalidades básicas

Inspecione tamanho e dtype, selecione colunas, ordene dados e aplique operações
numéricas. Promoção de tipo e conversão explícita obedecem regras diferentes:
a promoção não deve perder informação silenciosamente. Consulte
[contratos de tipos](CONTRACT.md) e [métodos disponíveis](API_INDEX.md).

<a id="section-entrada-e-saida-de-dados"></a>

## Entrada e saída de dados

A superfície documentada inclui CSV e JSON, em arquivo e em memória, com
funções como `smaug.read_csv` e `smaug.read_json`. Os métodos de DataSet
incluem `to_csv` e `to_json`.
Veja [funções de entrada e saída](API_INDEX.md#section-entry-point-init-lua) e
[parsers e ownership no C](API_Reference.md).

<a id="section-indexacao-e-selecao"></a>

## Indexação e seleção

No Lua, posições começam em 1. Use acesso por posição, seleção de colunas e
máscaras conforme a estrutura. Máscara com NA descarta a linha no filtro.
Consulte [índices e máscaras](CONTRACT.md#section-contrato-7-indices-sao-1-based) e
[seleção em Series e DataSet](API_INDEX.md).
Index nomeado, MultiIndex e alinhamento avançado precisam ser conferidos no
[roadmap](Roadmap.md); não são presumidos por analogia com pandas.

<a id="section-copy-on-write"></a>

## Copy-on-Write

Views compartilham dados até a mutação que exige materialização.
Ownership, detach, OOM e restrições por tipo estão no
[guia de views e Copy-on-Write](COW.md).
As pendências de lifetime permanecem explícitas no contrato.

<a id="section-juncao-concatenacao-e-comparacao"></a>

## Junção, concatenação e comparação

DataSet fornece `join`, `concat` e operações de comparação.
Chaves ausentes têm regra própria: NA em chave relacional é erro.
Veja [operações relacionais](API_INDEX.md#section--dataset-core-dataset) e [contrato das chaves](CONTRACT.md#section-contrato-8-na-em-chave-relacional-e-erro).

<a id="section-remodelagem-e-tabelas-dinamicas"></a>

## Remodelagem e tabelas dinâmicas

Use as operações documentadas `pivot`, `pivot_table`, `melt`,
`stack`, `unstack` e `explode` para reorganizar linhas e colunas.
Consulte as assinaturas na [referência de DataSet](API_INDEX.md#section--dataset-core-dataset).

<a id="section-trabalhando-com-texto"></a>

## Trabalhando com texto

O accessor `.str` reúne operações para Series de strings.
Consulte [métodos de texto](API_INDEX.md#section--str-proxy-de-operacoes-sobre-series-string); para integração com o núcleo,
veja [representação e operações de string no C](API_Reference.md).

<a id="section-trabalhando-com-dados-ausentes"></a>

## Trabalhando com dados ausentes

`smaug.NA` expressa ausência. A validade é armazenada separadamente do valor.
`fillna`, `dropna`, `isna` e `notna` têm contratos específicos.
NaN e infinitos não devem ser confundidos automaticamente com ausência.
Veja [regras de nulidade](CONTRACT.md#section-contrato-9-nao-finito-e-valor-ausencia-e-null-mask) e [métodos](API_INDEX.md).

<a id="section-dados-categoricos"></a>

## Dados categóricos

CategoricalSeries e o accessor `.cat` tratam categorias, códigos e operações
sobre os labels. Consulte [referência de categorias](API_INDEX.md#section--categoricalseries-core-series-categorical-categorical-lua).
As garantias de views não são idênticas às de séries armazenadas no C;
veja [tipos suportados por COW](COW.md#section-tipos-suportados).

<a id="section-inteiros-e-booleanos-anulaveis"></a>

## Inteiros e booleanos anuláveis

Inteiros usam `int64`; booleanos têm lógica de nulidade própria.
Confira promoção e precisão, lógica booleana e o tratamento de máscaras em
[contratos](CONTRACT.md), [API Lua](API_INDEX.md) e [API C](API_Reference.md).

<a id="section-apresentacao-de-tabelas"></a>

## Apresentação de tabelas

DataSet oferece `to_string` e `to_markdown`.
Consulte [métodos de apresentação](API_INDEX.md#section--dataset-core-dataset).
Esses recursos não implicam a existência de um sistema de gráficos ou Styler.

<a id="section-funcoes-definidas-pelo-usuario"></a>

## Funções definidas pelo usuário

Operações como `map` permitem expressar transformações explícitas.
Use as [assinaturas da API](API_INDEX.md) e respeite as
[convenções de chamadas Lua](CODING_STYLE.md#section-construcao-e-chamadas-lua).
Consulte o dtype de resultado e a política de NA da operação utilizada.

<a id="section-agrupamento-de-dados"></a>

## Agrupamento de dados

`groupby` agrupa por chave simples ou composta; agregações e `transform`
estão descritos na [referência de DataSet](API_INDEX.md#section--dataset-core-dataset).
Veja também a [regra de NA em chaves](CONTRACT.md#section-contrato-8-na-em-chave-relacional-e-erro).

<a id="section-operacoes-de-janela"></a>

## Operações de janela

Rolling, expanding, operações cumulativas, shift e diff têm resultados e
políticas de nulidade específicos. Consulte as operações de Series e DataSet
na [referência](API_INDEX.md), incluindo `min_periods` quando disponível.

<a id="section-series-temporais-e-datas"></a>

## Séries temporais e datas

O dtype datetime armazena epochs em milissegundos UTC; `.dt` expõe operações
de calendário. O parser atual aceita datas sem horário, mas a detecção de uma
coluna inteira de strings como datetime ainda faz parte do rework.

Consulte a [API datetime existente](API_INDEX.md#section--dt-proxy-de-operacoes-de-calendario-sobre-series-datetime), o
[perfil e detecção aprovados](CONTRACT.md#section-perfil-datetime-decisoes-aprovadas-em-2026-09-18) e o
[evolução da API Lua](API_INDEX.md#section-datetime-migracao-lua).
A nova faixa de anos, formato negativo e diagnóstico `DATE_ON_THE_FENCE`
são contratos a implementar; não devem ser apresentados como funcionalidades
já validadas.

<a id="section-diferencas-de-tempo"></a>

## Diferenças de tempo

Diferenças entre epochs produzem durações em milissegundos.
Uma duração não é um instante datetime; sua faixa e operação precisam ser
tratadas separadamente. Veja [contrato da aritmética temporal](API_Reference.md#section-nucleo-de-calendario-assinaturas-e-mudancas)
e [métodos datetime](API_INDEX.md).

<a id="section-desempenho-e-limitacoes"></a>

## Desempenho e limitações

Operações vetorizadas usam o núcleo C; o modelo de camadas está na
[arquitetura](ARCHITECTURE.md). Medições históricas não substituem benchmarks
atuais. Consulte o [roadmap](Roadmap.md) para performance, escala e recursos
ainda em planejamento.

PyArrow, estruturas esparsas, resampling, fusos nomeados e visualização gráfica
não ganham suporte por aparecerem na documentação do pandas. Este guia cobre
os temas aplicáveis ao Smaug e remete o restante ao planejamento.


---

[Continuar no guia do usuário](USER_GUIDE.md) · [Consultar a API](API_INDEX.md) · [Início da documentação](README.md)
