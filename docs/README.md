# Smaug — documentação

Biblioteca de dados tabulares em LuaJIT, com motor C e integração FFI.
`Series` representa uma coluna tipada; `DataSet` reúne colunas alinhadas.
O projeto está em pré-1.0. Tipos disponíveis: float64, int64, bool, string,
datetime e categorical.

## Usar a biblioteca

- [Primeiros passos](GETTING_STARTED.md): ambiente e primeiro programa.
- [Guia por assunto](USER_GUIDE.md): caminhos de leitura e limitações.
- [API Lua](API_INDEX.md) e [API C](API_Reference.md): métodos e assinaturas.
- [Compilação e testes](Build_and_Testing.md): comandos e alcance das ferramentas.

## Desenvolver

| Informação | Fonte responsável |
|---|---|
| Próximo trabalho, dependências e critérios de conclusão | [Roadmap](Roadmap.md) |
| Responsabilidades dos anéis | [Arquitetura](ARCHITECTURE.md) |
| Decisões de comportamento aprovadas | [Contrato](CONTRACT.md) |
| Views, ownership e detach | [COW](COW.md) |
| Nomes, chamadas e estilo de testes | [Convenções](CODING_STYLE.md) |
| Defeitos, decisões e evidência CSV/JSON | [Review de I/O](IO_REVIEW.md) |
| Checkpoint e reconstrução dos testes | [Roadmap](Roadmap.md#checkpoint) e [achados R01–R09](Roadmap.md#verificacao) |
| Verificação limitada dos quatro helpers i64 | [Review aritmético](CORE_ARITHMETIC_REVIEW.md) |
| Triagem das exclusões de cobertura | [Inventário](TEST_SUITE_EXCLUSIONS_REVIEW.md) |
| Mudanças e decisões superadas | [Changelog](CHANGELOG.md) |

O contrato registra o comportamento exigido; uma divergência do código deve
ser apontada como pendência. Propostas não viram contrato pela edição da doc.
O roadmap é a única fila de execução: guias e reviews remetem a seus itens.

## Evidência gerada

[Cobertura](COVERAGE.md), [paridade](PARITY_REPORT.md) e
[manifesto](MANIFEST.txt) identificam execuções ou árvores específicas.
Não editar seus resultados manualmente nem apresentar percentuais históricos
como garantia da árvore atual. Branches do gcov não demonstram MC/DC;
paridade textual não demonstra comportamento, layout compilado ou reentrância.

Ao atualizar a documentação, altere a fonte responsável, use links nas demais
páginas e confira as âncoras. Preserve resultados históricos com sua data e
escopo; mantenha decisões abertas explicitamente identificadas.

[Licença MIT](../LICENSE).
