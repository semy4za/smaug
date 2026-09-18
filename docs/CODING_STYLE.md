# Convenções de escrita do Smaug

Estas regras se aplicam ao código, aos testes e aos exemplos novos ou revisados.
A migração dos arquivos existentes é incremental; este documento não declara
que toda a base já foi convertida.

Os 33 arquivos de testes C e Lua em `tests/` foram padronizados em 2026-09-18.
As fixtures de dados foram preservadas. O núcleo e o frontend não fazem parte
desta etapa de padronização.

Validação desta etapa no Windows (GCC/MinGW e LuaJIT): 13 suítes C e 20 suítes
Lua passaram, totalizando 450.104 verificações, com as mesmas contagens por
arquivo da execução anterior à migração. Isso inclui stress e propriedades;
não representa uma nova certificação de ausência de UB ou de vazamentos.

## Nomes

- Variáveis, parâmetros e funções auxiliares usam nomes descritivos em inglês,
  em `snake_case`: `source_series`, `expected_values`, `row_index`.
- Nenhuma variável ou parâmetro pode ter nome de uma letra, inclusive índices
  de loops e argumentos de callbacks. Use `row_index`, `column_index`,
  `left_value`, `right_value` ou outro nome que explique o papel do valor.
- Não substitua nomes por abreviações opacas: use `condition`, `message`,
  `passed_checks` e `result_series` em vez de `cond`, `msg`, `n_ok` e `res`.
- Para posições ignoradas, use um nome descritivo como `unused_index`.
- Nomes estabelecidos pela linguagem, FFI ou API, como `self`, `ffi`, `int64_t`,
  `__index`, `Series` e `DataSet`, conservam sua grafia. Literais de dados de
  uma letra, como a string `"a"`, não são nomes de variáveis.

## Construção e chamadas Lua

Importe o módulo como `local smaug = require("smaug")` e acesse os construtores
pelo módulo. Não crie aliases de construtores, mesmo que o alias seja `Series`
ou `DataSet`. Não use `S`, `DS` ou equivalentes.

Prefira `smaug.Series(...)` e `smaug.DataSet(...)`. Quando uma chamada explícita
ao construtor de arrays for necessária, use `smaug.Series.from_array(...)`.
Não use `from_table` para preparar dados de testes ou ensinar a API pública.
A implementação interna existente de `from_table` não é removida por esta
convenção. Testes dedicados a ela devem identificar expressamente o contrato
interno ou de compatibilidade que verificam.

Construtores especializados podem ser chamados pelo caminho completo quando
o próprio construtor for o objeto do teste. Preserve a operação sob teste:
padronização de escrita não deve eliminar cobertura de uma API.

Use ponto para funções de módulo e construtores; dois-pontos para chamadas
de métodos de instância; colchetes para índices e nomes de colunas. Accessors
como `.dt` e `.str` são propriedades cujos métodos recebem dois-pontos.
Chamadas internas diretas à tabela de métodos mantêm o receptor explícito
quando necessário para evitar recursão no despacho.

```lua
local smaug = require("smaug")

local sales_series = smaug.Series({100, 200, 300}, "int64")
local sales_dataset = smaug.DataSet({
    {"sales", {100, 200, 300}, "int64"},
})
local total_sales = sales_series:sum()
local first_sale = sales_dataset["sales"]:get(1)

local datetime_series = smaug.Series({"2026-01-01"}, "datetime")
local year_series = datetime_series.dt:year()
```

## Testes

- Nomeie os dados pelo cenário: `nullable_integer_series`, `all_null_series`,
  `expected_values`, `actual_values`.
- Use o mesmo nome para o mesmo papel nos helpers: `check(condition, message)`
  e `passed_checks` para o contador.
- Mantenha mensagens e casos de teste que descrevam o comportamento observado.
- Renomeie declarações e referências no mesmo escopo; não altere textos,
  campos da API ou dados de teste por substituição cega.
- Ao migrar um arquivo, execute seus testes e confira que nenhum cenário ou
  verificação foi perdido.

## Checagem de regressões de estilo

Execute `python scripts/check_test_style.py` para verificar todos os testes C
e Lua. O script usa somente a biblioteca padrão do Python e recusa
identificadores de uma letra, aliases diretos de `smaug.Series`/`smaug.DataSet`
e chamadas a `from_table`. Literais, comentários, campos da API e chaves de
tabelas não são nomes de variáveis. O próprio verificador pode ser exercitado
com `python scripts/check_test_style.py --self-test`.

Esta checagem léxica não substitui revisão dos nomes, compilação ou execução
da suíte. Construtores especializados permanecem nos testes dedicados às suas
APIs; os geradores de propriedades também podem pré-alocar séries com tamanho
calculado em tempo de execução. As demais fixtures preferem os construtores
chamáveis.
