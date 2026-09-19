# Documentação do Smaug

Smaug é uma biblioteca de dados tabulares em Lua, com motor em C e integração
LuaJIT FFI. Trabalha com Series e DataSet, com tipos numéricos, booleanos,
strings, datetime e categorias.

<a id="section-primeiros-passos"></a>

## Primeiros passos

Conheça as estruturas de dados, prepare o ambiente e siga um primeiro exemplo.

[Começar com Smaug →](GETTING_STARTED.md)

<a id="section-guia-do-usuario"></a>

## Guia do usuário

Aprenda por assunto: entrada e saída, seleção, dados ausentes, texto,
categorias, agrupamentos, janelas e datas.

[Abrir o guia do usuário →](USER_GUIDE.md)

<a id="section-referencia-da-api"></a>

## Referência da API

Consulte funções, métodos e assinaturas em duas referências separadas:
[Lua](API_INDEX.md) para objetos e métodos; [Núcleo C](API_Reference.md) para
headers, tipos e funções do backend. Na segunda ficam também
arquitetura, memória, compilação, testes e o rework.

[Consultar a API →](API_INDEX.md) · [Referência C](API_Reference.md)

<a id="section-estado-e-versoes"></a>

## Estado e versões

O projeto está em pré-1.0. Há mudanças de API e contratos aprovados ainda
pendentes de implementação. O [roadmap](Roadmap.md) registra o planejamento;
o [changelog](CHANGELOG.md) preserva o histórico. A
[revisão da suíte](TEST_SUITE_REWORK.md) identifica o trabalho atual.

A organização adapta a [documentação do pandas](https://pandas.pydata.org/docs/)
em três entradas: primeiros passos, guia do usuário e referência da API.
O conteúdo de desenvolvimento fica dentro da referência do Núcleo C.
Os temas foram adaptados à superfície existente do Smaug. Todos os documentos
manuais permanecem diretamente em `docs/`.

[Licença MIT](../LICENSE)
