# Convenções de escrita do Smaug

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

<details>
<summary>Nesta página</summary>

- [Bases](#bases) · [Governança](#governanca)
- [C](#padrao-c) · [Lua/FFI](#padrao-lua)
- [Formatação](#formatacao)
- [Nomes](#section-nomes)
- [Construção e chamadas Lua](#section-construcao-e-chamadas-lua)
- [Testes](#section-testes)
- [Checagem de regressões de estilo](#section-checagem-de-regressoes-de-estilo)

</details>

Estas regras se aplicam ao código, aos testes, aos exemplos e à documentação
novos ou revisados.
A migração dos arquivos existentes é incremental; este documento não declara
que toda a base já foi convertida.

Os arquivos de testes C e Lua em `tests/` foram padronizados; a árvore atual
tem 35 arquivos verificados pelo guard.
As fixtures de dados foram preservadas. O núcleo e o frontend não fizeram parte
daquela etapa histórica; agora estão no alcance das regras incrementais abaixo.

Validação desta etapa no Windows (GCC/MinGW e LuaJIT): 13 suítes C e 20 suítes
Lua passaram, totalizando 450.104 verificações, com as mesmas contagens por
arquivo da execução anterior à migração. Isso inclui stress e propriedades;
não representa uma nova certificação de ausência de UB ou de vazamentos.

<a id="bases"></a>
## Bases e alcance

Consolidado em 2026-09-28 e revisado em 2026-10-09. Este é o padrão do Smaug
para código novo e trechos
revisados em C e Lua. A arquitetura de anéis permanece: regras de linguagem
não transferem inferência ou políticas de arquivo para o núcleo. A adoção na
base existente é incremental; conformidade integral ainda não foi demonstrada.

| Referência | Uso no Smaug | Limite da adoção |
|---|---|---|
| [C11, rascunho N1570](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf) | Semântica da linguagem e libc; builds já usam C11 | Compilar com C11 não prova portabilidade ou ausência de UB |
| [SEI CERT C](https://www.sei.cmu.edu/library/sei-cert-c-and-c-coding-standards/) | Base técnica para inteiros, memória, strings e erros | Referência para revisão; não declaramos conformidade com todo o catálogo |
| [JPL Power of Ten](https://spinroot.com/gerard/pdf/P10.pdf) | Fluxo verificável, escopo pequeno, retornos conferidos e análise estática | Adaptações abaixo; não é certificação NASA |
| [Google C++ Style Guide](https://google.github.io/styleguide/cppguide) | Princípios de legibilidade, interfaces e organização | Guia de C++; suas regras não são importadas integralmente para C |
| [LuaRocks Lua Style Guide](https://github.com/luarocks/lua-style-guide) | Base de organização e escrita Lua | Prevalecem as convenções explícitas do Smaug, incluindo nomes e indentação |
| [Lua 5.1](https://www.lua.org/manual/5.1/manual.html) e [LuaJIT](https://luajit.org/extensions.html) | Semântica e compatibilidade do frontend | Recursos de versões posteriores exigem suporte comprovado no runtime alvo |
| [LuaJIT FFI](https://luajit.org/ext_ffi_semantics.html) | Conversões, ponteiros, lifetime e cdata | FFI não valida automaticamente os contratos C |
| [TensorFlow `tf.io.decode_csv`](https://www.tensorflow.org/api_docs/python/tf/io/decode_csv) e [`tf.io.FixedLenFeature`](https://www.tensorflow.org/api_docs/python/tf/io/FixedLenFeature) | Referência comparativa para schema por campo, tipos, ausência e defaults em I/O | Não introduz dependência, não define o dialeto Smaug e não exige paridade integral |

As regras identificadas abaixo são a seleção do projeto; os identificadores
C01–C08 e L01–L07 não são IDs dos documentos externos. As fontes técnicas
fundamentam a revisão, e os exemplos não alteram assinaturas existentes.

<a id="governanca"></a>
## Aplicação, exceções e evolução

“Deve”, “exige” e “não usar” são requisitos. Recomendações são identificadas
como tais. Em conflito: comportamento aprovado fica em CONTRACT, assinatura
existente no header/FFI e responsabilidade em ARCHITECTURE. Este guia regula
implementação; uma incompatibilidade entre esses documentos é registrada no
roadmap e resolvida explicitamente antes da mudança dependente.

O escopo de adoção é a função alterada e seus consumidores afetados. Não exige
reescrever o arquivo inteiro. Uma violação preexistente fora desse escopo vai
para o roadmap com localização e impacto; não é considerada conforme porque
é antiga. Dentro do escopo, corrigir ou registrar uma exceção antes de concluir.

Exceções específicas já autorizadas neste documento não exigem nova decisão,
mas devem respeitar suas condições. Qualquer outra exceção deve registrar,
no item correspondente do roadmap: ID da regra, função/arquivo, motivo técnico,
alternativas rejeitadas, risco, verificação compensatória, responsável pela
decisão e condição de reavaliação. A exceção deve ser aceita explicitamente na
revisão pelo mantenedor; silêncio ou passagem de testes não significam aceitação.
Não criar dispensas globais por prazo, preferência estética ou desempenho não
medido. Não adicionar warnings ignorados nem suprimir classes inteiras para
fazer um gate passar.

Mudanças no próprio padrão precisam de justificativa, exemplos antes/depois,
impacto na base existente e verificação correspondente. Registrar a decisão no
roadmap e o marco no changelog. Reavaliar as exceções quando a função, o contrato,
o compilador ou o runtime afetado mudar. Não alterar comportamento ou ABI sob
um commit descrito apenas como formatação.

<a id="padrao-c"></a>
## Padrão C

| Regra | Exigência | Como verificar |
|---|---|---|
| C01 — linguagem e plataforma | C11; extensões de compilador/libc isoladas e documentadas. `size_t` para tamanhos, `int64_t` para valores i64 e `const` nas entradas somente de leitura. Requisitos de representação devem ser explícitos | Compilação e revisão de headers, tipos e casts nas plataformas identificadas |
| C02 — interfaces | Símbolos públicos com prefixo `smaug_`; auxiliares privados `static`; header autocontido com guarda de inclusão. Documentar unidades, limites, nulidade e mutabilidade | Compilar header isolado e conferir assinatura, implementação e FFI |
| C03 — erros e saídas | Verificar chamadas que possam falhar. Quando for necessário distinguir causas, usar o sistema de status existente. Resultado só é publicado em sucesso; exceções ao contrato de preservação devem ser explícitas | Casos de erro com saída previamente preenchida e revisão dos consumidores |
| C04 — memória | Definir dono, destrutor e lifetime de cada buffer. Verificar alocação e limpar resultados parciais. Validar somas/produtos de tamanhos antes de alocar | Testes de OOM, rollback e ferramentas de memória no caminho alterado |
| C05 — aritmética | Provar limites antes da operação/cast; usar helpers checked existentes. Não calcular overflow assinado para depois detectá-lo | Limites representáveis, análise estática e verificações de UB adequadas |
| C06 — texto e números | Distinguir bytes com comprimento de C-string. Documentar gramática, consumo completo, locale, precisão e faixa. Não alterar locale global dentro de uma operação da biblioteca | NUL interno, tokens parciais/longos, limites e ambientes de locale identificados |
| C07 — fluxo e escopo | Funções coesas, escopo mínimo, progresso e término justificáveis para laços. Não introduzir recursão sem exceção registrada com limite de profundidade e memória. Macros não devem ocultar fluxo ou avaliar repetidamente argumentos com efeitos | Revisão de caminhos, limites e expansão de macros |
| C08 — verificação | Não introduzir warnings nos caminhos alterados; justificar individualmente supressões. Executar testes pertinentes e análise estática quando configurada para a família, identificando ferramentas e lacunas | Comandos, versões, resultados e limitações registrados no checkpoint |

Saída obrigatória e saída opcional são contratos distintos: helpers checked
existentes podem permitir NULL; isso não decide o comportamento dos parsers.
`assert` serve a invariantes internas sem efeitos colaterais. Não substitui
validação de entrada pública, pois pode estar desabilitado. Um teste de NULL
não prova que um ponteiro não nulo seja válido: o caller deve fornecer memória
acessível e a capacidade exigida.

Adaptações explícitas do JPL:

- Alocação dinâmica é necessária para Series/DataSet; C04 exige propriedade,
  limites e limpeza, em vez de proibição após inicialização.
- `goto cleanup` é permitido para liberar recursos numa função; saltos que
  ocultem a lógica normal devem ser evitados.
- Ponteiros de função e múltiplos níveis de ponteiro são permitidos quando
  necessários para callbacks, FFI e parâmetros de saída, com contrato explícito.
- Tamanho da função e quantidade de assertions não são metas numéricas.
  Dividir por responsabilidade e verificar invariantes úteis.
- Laços podem depender do tamanho dos dados; devem ter limite/progresso
  verificável e tratamento dos cálculos de índice.

O uso atual de `-fwrapv` deve ser auditado por família antes de ser removido.
Não usar a flag como justificativa para novo código depender de overflow
assinado. Ela é uma opção do compilador, descrita pelo
[GCC](https://gcc.gnu.org/onlinedocs/gcc-15.1.0/gcc/Code-Gen-Options.html).
Windows com GCC/MinGW não demonstra compatibilidade com MSVC; execução em
uma libc não certifica outra. A ABI C/Lua exige verificação própria em R2.

<a id="padrao-lua"></a>
## Padrão Lua e FFI

| Regra | Exigência | Como verificar |
|---|---|---|
| L01 — módulos | Usar variáveis/funções locais e dependências explícitas. Não criar globals acidentais nem modificar módulos de terceiros ou bibliotecas padrão | Revisão de escopo e lint configurado para LuaJIT quando disponível |
| L02 — ausência e booleanos | Distinguir `false`, `nil`, NA e NaN. Não usar `condition and value or fallback` quando o valor verdadeiro puder ser false/nil | Casos com ambos os booleanos, ausência e NaN |
| L03 — sequências | Não usar `#`/`ipairs` para inferir comprimento de tabelas com buracos. Transportar tamanho explícito ou sentinela conforme o contrato; não depender da ordem de `pairs` | Buracos iniciais/intermediários/finais, ordem e cardinalidade |
| L04 — fronteiras e erros | Validar argumentos públicos e preservar causa/contexto de falhas. Não usar `pcall` para transformar erro real em sucesso ou ausência silenciosa | Argumentos inválidos e erros C/Lua propagados com contexto |
| L05 — recursos FFI | Conferir status antes de ler saída; usar o destrutor C correto e um dono responsável. Manter vivos os donos de ponteiros emprestados; coordenar liberação manual e `ffi.gc` para evitar dupla liberação | Caminhos de sucesso, falha parcial, coleta e lifetime |
| L06 — precisão e bytes | Preservar int64 em cdata nos transportes exatos; conversão a `number` exige contrato de precisão. Usar comprimento explícito ao converter buffers que admitem NUL | Valores acima de 2^53, limites i64, NUL e máscaras |
| L07 — camadas | Wrappers traduzem chamada/resultado sem duplicar mecanismos do core. Política Lua de inferência/NA é explícita e não deve ser confundida com validação C | Revisão do percurso C → FFI → Series/DataSet e testes do consumidor |

Exemplo de L02, aplicável à seleção booleana:

```lua
local selected_value
if condition then
    selected_value = primary_value
else
    selected_value = fallback_value
end
-- primary_value == false permanece false.
```

`ffi.gc` não substitui o contrato de ownership. Uma mudança no cdef precisa
acompanhar a biblioteca; identificar a ABI e sua compatibilidade é R2.
As regras de L06 não aprovam mudar automaticamente retornos públicos que hoje
usam `number`: essas mudanças passam pelo contrato da família e seus consumidores.

<a id="contrato-funcao"></a>
## Contrato mínimo de função e revisão

Cada API pública nova ou alterada deve documentar, no header C ou junto à
interface Lua, os pontos aplicáveis abaixo. Itens não aplicáveis não exigem
texto repetitivo; regras comuns podem ser referenciadas sem duplicação.

1. Tipos, unidades, índices base 0/1 e faixa; comprimento em bytes ou elementos.
2. Ponteiros obrigatórios/opcionais, capacidade real, strings terminadas ou
   slices, e possibilidade de alias entre entrada e saída.
3. Resultado, status e significado de NULL/nil/NA/NaN; condições em que cada
   parâmetro de saída pode ser lido ou permanece preservado.
4. Mutação permitida, ownership, destrutor, lifetime de buffers emprestados e
   efeito da falha sobre entrada/saída. Falha parcial deve ter contrato explícito.
5. Dependências de locale, estado global, reentrância e plataforma, quando houver.

Não prometer recuperação de ponteiro arbitrário inválido. Não usar estado global
mutável para transportar erros; objetos independentes devem poder executar sem
compartilhar um diagnóstico mutável. Introduzir cache/estado compartilhado exige
contrato de sincronização e revisão própria.

Para macros C: constantes, guardas de inclusão e compilação por plataforma são
permitidas; macros funcionais exigem parênteses, avaliação documentada dos
argumentos e ausência de efeitos ocultos. Preferir função `static`/`static inline`
quando não houver necessidade de geração de código. Geração por macros exige
revisar a expansão e testar cada variante afetada. VLA e alocação de tamanho
controlado pela entrada na stack exigem exceção com limite demonstrado.

Antes de concluir uma alteração, registrar no checkpoint:

| Evidência obrigatória | Conteúdo |
|---|---|
| Escopo | Funções, anéis, plataformas e consumidores afetados |
| Contrato | Preservado ou alterado por decisão identificada; headers/cdef/docs coerentes |
| Falhas | Entradas inválidas, limites e limpeza/rollback relevantes à alteração |
| Verificação | Comando, ferramenta, resultado, biblioteca/árvore identificada e skips |
| Exceções | IDs aplicáveis e decisões; nenhuma dispensa implícita |

Para mudanças somente documentais, conferir fatos citados, links e diff; não
exigir recompilar o motor. Para mudança executável, compilar e executar a suíte
da família e regressões do comportamento alterado. Mudança de alocação exige
exercitar falha e limpeza; mudança de layout/assinatura exige consumidores C/FFI
e verificação de ABI. Dependência nova de plataforma exige validação na plataforma
afetada ou registro explícito de que a entrega permanece sem essa validação.
Uma ferramenta ausente não conta como execução aprovada.

<a id="formatacao"></a>
## Formatação e comentários

C e Lua novos/revisados usam quatro espaços, sem tabs, sem espaços finais e
com newline final; C usa chaves na mesma linha e blocos explícitos em controle
de fluxo. Limite de 100 colunas no código novo; URLs e literais indivisíveis são exceções
permitidas. Quebrar assinaturas longas entre parâmetros. Tabelas Markdown não
estão sujeitas a esse limite. Não reformatar módulos inteiros incidentalmente. Não há formato automático
configurado para toda a produção; até sua adoção, conferir esses critérios no diff.

Comentários explicam motivos, precondições e limitações verificadas. Não
prometer versões futuras nem chamar uma operação de segura sem delimitar o
contrato. Referências históricas continuam rastreáveis no roadmap.

<a id="section-nomes"></a>

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

<a id="section-construcao-e-chamadas-lua"></a>

## Construção e chamadas Lua

### Inferência e dtype explícito

Na construção de Series e de colunas de DataSet, usar inferência por padrão.
Informar `dtype` quando ele expressar uma intenção que os valores não mostram, como criar `float64`
a partir de inteiros ou definir o tipo de uma série vazia ou só de NA.
Essa convenção também se aplica aos exemplos, tutoriais, guias e demais
trechos de código na documentação; omitir o tipo redundante torna a chamada
mais legível e apresenta o uso habitual da API.

Exemplos de uso habitual, com tipo inferido dos valores:

```lua
local smaug = require("smaug")

local active_series = smaug.Series({true, false})
local quantity_series = smaug.Series({1, 2, 3})
local label_series = smaug.Series({"first", "second"})
```

Usar dtype explícito nos casos abaixo, pois sua omissão mudaria o tipo desejado:

```lua
local smaug = require("smaug")

-- Queremos float64; estes valores seriam inferidos como int64.
local measurement_series = smaug.Series({1, 2, 3}, "float64")
-- Queremos bool, embora ainda não existam valores para inferir o tipo.
local empty_series = smaug.Series({}, "bool")
-- Queremos int64, embora todos os elementos sejam nulos.
local all_null_series = smaug.Series({smaug.NA, smaug.NA}, "int64")
```

Na implementação atual, listas vazias ou só de NA assumem `string` quando o
dtype é omitido; os valores continuam nulos. Declarar outro tipo nesses casos
é necessário para expressar a intenção do chamador.

Nos testes, manter dtype explícito quando o cenário precisa exercitar um tipo
específico; omiti-lo nos testes de inferência. Exemplos que ensinam o próprio
argumento `dtype` também podem explicitá-lo, identificando essa finalidade.
A adoção nos arquivos existentes é incremental, durante sua revisão, sem
remover tipos necessários nem alterar o comportamento ou a cobertura dos testes.
Conferir a intenção de cada chamada em revisão; o guard léxico atual não
verifica esta convenção.

No código interno, preservar dtype explícito quando ele garante o tipo de
saída de uma operação, inclusive para resultados vazios ou só de NA. Valores
dinâmicos e cdata int64 também podem exigir o tipo explícito; não presumir que
a inferência reconhece todo valor aceito pelo construtor tipado. Em Lua,
`1.0` é inferido como `int64`; a escrita decimal não força `float64`.

### Forma das chamadas

Nos testes e exemplos de uso, importe o módulo como
`local smaug = require("smaug")` e acesse os construtores
pelo módulo. Não crie aliases de construtores, mesmo que o alias seja `Series`
ou `DataSet`. Não use `S`, `DS` ou equivalentes.

Prefira `smaug.Series(...)` e `smaug.DataSet(...)`. Quando uma chamada explícita
ao construtor de arrays for necessária, use `smaug.Series.from_array(...)`.
Não use `from_table` para preparar dados de testes ou ensinar a API pública.
A implementação interna existente de `from_table` não é removida por esta
convenção. Testes dedicados a ela devem identificar expressamente o contrato
interno ou de compatibilidade que verificam.

No código interno, dependências locais e objetos recebidos por injeção são
permitidos; isso não autoriza renomeação de símbolos públicos ou ciclos de
`require` apenas para seguir a forma dos exemplos.

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

local sales_series = smaug.Series({100, 200, 300})
local sales_dataset = smaug.DataSet({
    {"sales", {100, 200, 300}},
})
local total_sales = sales_series:sum()
local first_sale = sales_dataset["sales"]:get(1)

-- A string deve ser interpretada como datetime; sem dtype seria string.
local datetime_series = smaug.Series({"2026-01-01"}, "datetime")
local year_series = datetime_series.dt:year()
```

<a id="section-testes"></a>

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

<a id="section-checagem-de-regressoes-de-estilo"></a>

## Checagem de regressões de estilo

Execute `python scripts/check_test_style.py` para verificar todos os testes C
e Lua. O script usa somente a biblioteca padrão do Python e recusa
identificadores de uma letra, aliases diretos de `smaug.Series`/`smaug.DataSet`
e chamadas a `from_table`. Literais, comentários, campos da API e chaves de
tabelas não são nomes de variáveis. O próprio verificador pode ser exercitado
com `python scripts/check_test_style.py --self-test`.

O verificador atual cobre convenções dos testes; não implementa C01–C08 ou
L01–L07 na produção. Lint LuaJIT e análise estática C ainda precisam de
configuração e baseline em R6; não são gates já instalados.

Esta checagem léxica não substitui revisão dos nomes, compilação ou execução
da suíte. Construtores especializados permanecem nos testes dedicados às suas
APIs; os geradores de propriedades também podem pré-alocar séries com tamanho
calculado em tempo de execução. As demais fixtures preferem os construtores
chamáveis.

---

[Referência do Núcleo C](API_Reference.md) · [Rework da suíte](Roadmap.md#checkpoint) · [Início da documentação](README.md)
