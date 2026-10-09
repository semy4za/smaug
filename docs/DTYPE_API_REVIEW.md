# Dtype na API Lua — pesquisa e avaliação

[Roadmap R4](Roadmap.md#r4) · [Contrato](CONTRACT.md) · [Arquitetura](ARCHITECTURE.md)

Estado: estudo para decisão, 2026-10-09. Nenhuma sintaxe nova foi aprovada ou
implementada. Preferência do mantenedor: equilibrar scripts de análise e código
reutilizável. Os exemplos identificados como proposta não são a API atual.
A convenção de omitir dtype redundante continua válida na API existente.

**Direção atual acordada:** priorizar ingestão, transformação, composição e
exportação. Dados literais nos scripts são casos auxiliares; sua frequência
nos testes não deve determinar a API principal. A pesquisa anterior permanece
como evidência, mas sua ênfase na sintaxe de construção precisa ser revista.
Construção programática de resultados/colunas e entrada externa/FFI continuam
relevantes. O checkpoint de retomada está no roadmap.

## O problema a resolver

Dar nome à intenção de tipo, preservando a construção curta por inferência.
Elegância será avaliada por legibilidade, composição, previsibilidade de erros,
reutilização de descrições e custo de migração. Quantidade de caracteres é só
um dos critérios. Este estudo não transforma semelhança com outra biblioteca
em requisito do Smaug.

Separar quatro decisões: escrita dos argumentos; inferência quando ausentes;
validação quando presentes; conversão explícita. Uma mudança na escrita não
aprova novas coerções, fallback de nulos, promoção ou constraints de mutação.

## Referências consultadas e contribuição

Consulta às páginas oficiais em 2026-10-09. Comparação documental: NumPy,
pandas, Arrow, TensorFlow e Polars não foram instalados nem executados neste
estudo. Polars é referência complementar desta avaliação. Lua/LuaJIT, NumPy,
pandas, Arrow e TensorFlow já aparecem nas referências do projeto. As páginas
TensorFlow consultadas se identificam como v2.16.1; não são evidência da versão
instalada ou mais recente do runtime.

| Fonte | Fato documentado | Aplicação à discussão Smaug |
|---|---|---|
| [Lua: argumentos nomeados](https://www.lua.org/pil/5.3.html) e [manual 5.1](https://www.lua.org/manual/5.1/manual.html#2.5.7) | Argumentos de chamada são posicionais; tabelas representam campos nomeados | Avaliar opções separadas e descritores, em sintaxe Lua válida. O capítulo do livro é da primeira edição; o manual 5.1 é a referência de linguagem alvo |
| [Lua: next](https://www.lua.org/manual/5.1/manual.html#pdf-next) | A enumeração de chaves não tem ordem especificada | Manter sequência explícita de colunas; um mapa de nomes não substitui a ordem do DataSet |
| [LuaJIT FFI](https://luajit.org/ext_ffi_semantics.html) | Inteiros de 64 bits são cdata; conversão a number pode perder precisão | Comparar aceitação de cdata e preservação exata, sem converter para inferir |
| [NumPy array](https://numpy.org/doc/stable/reference/generated/numpy.array.html) | Dtype pode ser omitido; regras de promoção participam da escolha | Separar escolha explícita de inferência; não importar a promoção NumPy automaticamente |
| [NumPy asarray](https://numpy.org/doc/stable/reference/generated/numpy.asarray.html) | Solicitar dtype diferente pode exigir cópia | Uma Series pronta com dtype conflitante exige decisão sobre erro/conversão/ownership |
| [pandas Series](https://pandas.pydata.org/docs/reference/api/pandas.Series.html) e [DataFrame](https://pandas.pydata.org/docs/reference/api/pandas.DataFrame.html) | Series tem dtype opcional; DataFrame aceita um único dtype no construtor | Referência de ergonomia; a limitação tabular não orienta o Smaug |
| [pandas boolean anulável](https://pandas.pydata.org/docs/user_guide/boolean.html) | A documentação distingue boolean anulável e lógica Kleene | Comparar ausência e valor booleano sem copiar o catálogo de dtypes; Smaug já tem máscara separada |
| [Arrow array](https://arrow.apache.org/docs/python/generated/pyarrow.array.html) | Tipo opcional, máscara e verificação safe são parâmetros distintos | Dtype, NA e tolerância não devem se confundir |
| [Arrow schema](https://arrow.apache.org/docs/format/Columnar.html#schema-message) | Campos ordenados descrevem nome, tipo e nulidade | Reutilização de descrição independente dos buffers e do formato de entrada |
| [TensorFlow constant](https://www.tensorflow.org/api_docs/python/tf/constant) e [convert_to_tensor](https://www.tensorflow.org/api_docs/python/tf/convert_to_tensor) | Inferência na ausência de dtype; convert_to_tensor distingue dtype de dtype_hint | Uma preferência flexível seria outro contrato, não um alias de dtype |
| [TensorFlow TensorSpec](https://www.tensorflow.org/api_docs/python/tf/TensorSpec) | Descritor contém shape, dtype e nome e serve a restrições de entrada | Distinguir descrição de dados de construção e conversão |
| [TensorFlow decode_csv](https://www.tensorflow.org/api_docs/python/tf/io/decode_csv) | Tipo/default/obrigatoriedade por coluna na leitura | Declarar o tipo antes do parsing pode preservar informação impossível de recuperar depois |
| [Polars DataFrame](https://docs.pola.rs/api/python/stable/reference/dataframe/index.html) | Schema, sobrescritas por coluna e strict têm papéis distintos | Explicitar conflitos e alcance de declarações parciais; não adotar tolerância que transforma erro em null |

C11, CERT C, JPL e os guias de estilo citados em CODING_STYLE continuam orientando
implementação, diagnóstico, ownership e validação. Eles não escolhem a sintaxe
pública de dtype. Não foi necessária nova interpretação desses padrões para
comparar as formas Lua neste estudo. Normas CSV/JSON/Unicode também não decidem
a escrita dos construtores; as políticas de cada leitor continuam próprias.

## Evidência executada no Smaug

Base Git `8016e73933e1ff7410143b5324e606a1c1eb72d9`, com alterações locais desta
sessão. Windows x64, LuaJIT 2.1.1779665312, DLL existente em `./build/smaug.dll`
identificada durante a carga, SHA256
`aef709528d98f08d7f5688b22721fafe3288ae6fa6e03fe3619f925c41f542d1`.
Não houve recompilação C, alteração de produção ou execução de Linux/sanitizers.

Comando: `luajit scripts/audit_dtype_api.lua`, a partir da raiz. O
[probe](../scripts/audit_dtype_api.lua) emite JSONL observacional: 43 casos,
31 retornos e 12 erros capturados. Esses números não são PASS/FAIL nem aprovação
dos comportamentos. Erros esperados e aceitação indevida são ambos evidências.
Falha ao carregar dependências interrompe o script. Resultados locais completos:
[JSONL](../build/dtype-api-study/observations.jsonl) e
[relatório com hashes](../build/dtype-api-study/report.json).

| Caso | Observação na API atual | Consequência para o desenho |
|---|---|---|
| S01–S04: bool, inteiro, `1.0`, float explícito | Bool é inferido; `1.0` continua int64; float64 explícito funciona | A escrita decimal não declara precisão; preservar a opção explícita |
| S05–S08: vazio/só NA | Sem tipo: string; com bool: bool, mantendo NA | A nova escrita precisa suportar vazio e ausência sem mudar fallback |
| S09: apenas nome | Exige `Series(values, nil, name)` | Opções nomeadas eliminam um placeholder |
| S10–S11: tipo inválido | String desconhecida gera erro; `false` aciona inferência | Proposta: ausente/nil inferem; false deve ser argumento inválido, sujeito a decisão de compatibilidade |
| S12–S14: misturas e fração | Numéricos promovem; famílias incompatíveis e fração para int64 geram erro | Nomear dtype não autoriza conversão silenciosa |
| S15–S16/F01–F02: cdata | Inferência de Series/full falha; int64 explícito preserva 9007199254740993 | Relevante para código reutilizável e transportes; não resolver convertendo para number |
| S18: opções no segundo argumento | Erro `dtype desconhecido table` | Forma proposta exige implementação, não uma mudança só nos exemplos |
| S19: `Series{data=...,dtype=...}` | Retorna string vazia | Descritor puro exige despacho e validação explícitos |
| S20: `Series{1,2,dtype=...}` | Campo dtype é ignorado, resultado int64 | Evitar misturar metadados dentro da própria sequência de valores |
| D02–D03: dtype nomeado ou digitado errado na coluna | Ambos ignorados | Uma futura API precisa validar as chaves, não apenas procurar dtype |
| D04–D05: Series pronta + dtype adicional | Dtype adicional, inclusive inválido, é ignorado | Decidir conflito explicitamente antes da implementação |
| D06–D08: forma tabular | Duplicata e tamanho desigual geram erro; nomes dtype/name/data/schema são aceitos como nomes de coluna | Preservar alinhamento, ordem e espaço de nomes dos dados |
| I01–I02: códigos CSV | Inferência lê 00123 como 123; schema string preserva 00123 | Declaração na leitura tem efeito que astype posterior não reverte |
| I03–I06: schema/ausência | JSON vazio/só NA preserva bool; valor incompatível falha mesmo nullable; typo no schema falha | Reusar a disciplina do schema; nullable não significa tolerante |
| I07: DataSet com `{schema=...}` no segundo argumento | Tabela é armazenada como nome; schema não é aplicado | Integração ao DataSet ainda precisa de contrato e implementação |
| F03–F05: map | Primeiro retorno fixa tipo; tudo NA exige tipo explícito | Não uniformizar toda inferência ao mudar construtores |

## Fluxo real: fixture de pedidos

Executados W01–W03 sobre `tests/fixtures/pedidos_digitados.csv`, já usada em
`tests/io/test_csv.lua`. O relatório expõe shape e tipos, sem reproduzir dados
de clientes. A autoria/licença da fixture não foi auditada nesta pesquisa.

| Etapa | Resultado executado |
|---|---|
| Leitura com `sep = ";"` e inferência | 916 linhas, 15 colunas; pedido int64, quantidade int64, valor string, data string |
| Schema completo com pedido string, quantidade int64 e valor float64; `decimal = ","` | 916 linhas, 15 colunas; tipos declarados preservados; data permanece string |
| Preparação para revisão: coluna bool toda NA e DataSet com três Series prontas | 916 linhas, 3 colunas; identificador string e reviewed bool com primeiro elemento NA |

A escolha de tratar o pedido como identificador string é um cenário de desenho,
não uma nova regra para essa fixture. No segundo caso, o tipo e o separador
decimal são decisões distintas: schema descreve o dado; opções interpretam o
arquivo. Conversão automática de data não foi introduzida.

Construção atual da coluna ainda sem respostas:

```lua
local review_series = smaug.Series.new("bool", orders_dataset:nrows(), "reviewed")
```

Esse fluxo combina leitura, tipo explícito, ausência e reutilização de Series.
Ele pesa tanto quanto o exemplo curto `Series({true, false})` na avaliação.

## Alternativas de escrita — todas em avaliação

Os blocos desta seção são propostas, não comandos suportados hoje. Para scripts,
a forma simples atual `smaug.Series(values)` e a lista ordenada de colunas são
pontos de partida. Não se propõe implementar simultaneamente todas as variantes.

### A — dados e opções separados

```lua
local active_series = smaug.Series({true, false})
local amount_series = smaug.Series({100, 200}, {dtype = "float64", name = "amount"})
local named_active_series = smaug.Series({true, false}, {name = "active"})

local orders_dataset = smaug.DataSet({
    {"code", {"00123", "00456"}},
    {"amount", {100, 200}, {dtype = "float64"}},
    {"reviewed", {smaug.NA, smaug.NA}, {dtype = "bool"}},
}, {name = "orders"})
```

Vantagens: opções são reutilizáveis; a chamada de Series mantém seus dados no
primeiro argumento; o padrão se aproxima do objeto de opções dos leitores já
existentes. Custo: cada coluna tipada ganha outra tabela. Dtype presente como
tabela no slot antes textual exige adaptação do despacho e plano de migração.

Caso de biblioteca reutilizável (proposto):

```lua
local amount_options = {dtype = "float64", name = "amount"}
local function build_amounts(values)
    return smaug.Series(values, amount_options)
end
```

Não modificar nem reter opções mutáveis como fonte de estado após a construção
é um critério proposto de avaliação. Ainda não existe medição de desempenho.

### B — opções para Series, campos nomeados no descritor de coluna

```lua
local amount_series = smaug.Series({100, 200}, {dtype = "float64"})
local orders_dataset = smaug.DataSet({
    {"code", {"00123", "00456"}},
    {"amount", {100, 200}, dtype = "float64"},
    {"reviewed", {smaug.NA, smaug.NA}, dtype = "bool"},
}, {name = "orders"})
```

Vantagem: menos aninhamento na tabela, dados separados da declaração da coluna.
Custo: dois formatos para a mesma intenção; copiar um objeto de opções para a
coluna não é direto. A tabela da coluna mistura índices 1/2 e chaves nomeadas,
exigindo validação explícita do descritor completo. Não confundir com S20, que
mistura metadados na tabela dos próprios valores.

### C — descritores totalmente nomeados

```lua
local amount_series = smaug.Series{
    data = {100, 200}, dtype = "float64", name = "amount",
}
local orders_dataset = smaug.DataSet{
    name = "orders",
    columns = {
        {name = "code", data = {"00123", "00456"}},
        {name = "amount", data = {100, 200}, dtype = "float64"},
        {name = "reviewed", data = {smaug.NA, smaug.NA}, dtype = "bool"},
    },
}
```

Vantagem: vocabulário explícito e fácil geração de descritores por código.
Custo: verbosidade nos scripts; convivência com tabelas de valores requer
regras de despacho inequívocas. Acrescentar `data` a uma tabela de usuário não
pode mudar seu significado por heurística silenciosa. Não colocar propriedades
do DataSet no mesmo mapa das colunas; dtype/name/data/schema são nomes válidos.

### Schema — dimensão independente das três formas

O schema atual é completo, imutável, requer nullable explícito e suporta
bool/int64/float64/string. Series também suporta datetime e categorical.
Logo, encapsular todo dtype no schema atual não seria uma simples adaptação.
A integração desejada pode ser investigada separadamente:

```lua
-- Proposta: atualmente esse segundo argumento é tratado como nome (caso I07).
local orders_dataset = smaug.DataSet(columns, {schema = order_schema})
```

Antes disso, decidir associação, ordem, colunas extras/ausentes, Series já
tipadas, conflito com dtype local e o alcance temporal de nullable. O schema
atual valida a importação; não mantém constraints futuras nas mutações.
Schema parcial, defaults e tolerância permanecem fora do contrato aprovado.

## Comparação para os dois usos prioritários

Julgamento de desenho, sem pontuação numérica ou teste de usabilidade realizado.

| Situação | A — opções separadas | B — coluna híbrida | C — descritores |
|---|---|---|---|
| Series rápida com inferência | Preserva forma curta | Preserva forma curta | Precisa manter atalho ou exige data= |
| Nome sem tipo | Direto | Direto | Direto |
| DataSet de 15 colunas, poucas tipadas | Mais chaves | Mais compacto | Mais texto, campos explícitos |
| Função recebe opções prontas | Encaminha tabela diretamente | Coluna exige adaptação | Encaminha descritor; precisa incorporar dados |
| Formato uniforme de opções | Mais uniforme | Dois formatos | Mais uniforme, mas distinto da API curta |
| Validação e migração | Distinguir string/tabela no slot de dtype | Também validar chaves dentro de cada coluna | Também resolver despacho dados/descritor |
| Schema reutilizável | Possível, contrato pendente | Possível, contrato pendente | Próximo visualmente, mas não equivale ao schema |

## Três fluxos para comparar A e B

Estes blocos completos são rascunhos de API para leitura, não executados.
Os dados pequenos do primeiro cenário são sintéticos, inspirados nos campos
da fixture; não são apresentados como extração dos pedidos reais.

### 1. Script de análise: tabela pequena, poucos tipos declarados

A — opções separadas:

```lua
local smaug = require("smaug")
local orders_dataset = smaug.DataSet({
    {"order_code", {"00123", "00456"}},
    {"company", {"company_a", "company_b"}},
    {"quantity", {2, 1}},
    {"amount", {100, 200}, {dtype = "float64"}},
    {"reviewed", {smaug.NA, smaug.NA}, {dtype = "bool"}},
}, {name = "orders"})
local units_by_company = orders_dataset:groupby("company"):sum("quantity")
```

B — campos no descritor de coluna:

```lua
local smaug = require("smaug")
local orders_dataset = smaug.DataSet({
    {"order_code", {"00123", "00456"}},
    {"company", {"company_a", "company_b"}},
    {"quantity", {2, 1}},
    {"amount", {100, 200}, dtype = "float64"},
    {"reviewed", {smaug.NA, smaug.NA}, dtype = "bool"},
}, {name = "orders"})
local units_by_company = orders_dataset:groupby("company"):sum("quantity")
```

B retira uma camada de chaves por coluna tipada. A usa o mesmo objeto de opções
que uma Series receberia. Ambas preservam ordem e deixam visível que reviewed
nasce bool mesmo sem respostas.

### 2. Biblioteca: dados e opções recebidos pelo chamador

A:

```lua
local smaug = require("smaug")
local function build_report(amount_values, amount_options)
    return smaug.DataSet({
        {"amount", amount_values, amount_options},
    })
end
local report = build_report({100, 200}, {dtype = "float64"})
```

B:

```lua
local smaug = require("smaug")
local function build_report(amount_values, amount_dtype)
    return smaug.DataSet({
        {"amount", amount_values, dtype = amount_dtype},
    })
end
local report = build_report({100, 200}, "float64")
```

Aqui a interface local B escolheu receber só o tipo. Para receber e encaminhar
opções arbitrárias, precisaria montar/copiar o descritor ou receber um descritor
pronto; A encaminha a tabela diretamente. Nenhuma das duas deve mutar os
valores nem opções fornecidos. Uma função que recebe uma Series pronta pode
simplesmente preservá-la, sem redeclarar dtype.

### 3. Pipeline com schema e coluna derivada

Esta versão usa somente a API atual e funciona para ambas as propostas, que
poderiam preservar essa composição. A função recebe um schema completo aprovado
pelo caller, como o de W02; schema é aplicado na leitura, sem fingir que o
construtor de DataSet já o suporta.

```lua
local smaug = require("smaug")
local function prepare_orders(csv_path, order_schema)
    local imported_orders = smaug.read_csv(csv_path, {
        sep = ";", decimal = ",", schema = order_schema,
    })
    local reviewed_series = smaug.Series.new("bool", imported_orders:nrows(), "reviewed")
    return smaug.DataSet({
        {"order_code", imported_orders["N_PEDIDO_SAP"]},
        {"quantity", imported_orders["(un)"]},
        {"reviewed", reviewed_series},
    }, "orders_for_review")
end
```

Esse caso reduz o peso da sintaxe de dtype dentro do DataSet: quando as Series
já têm tipos corretos, repetir dtype é dispensável. O que resta decidir é como
nomear o DataSet e como uma declaração conflitante deve falhar. A integração
de schema diretamente no DataSet pode ser avaliada depois, sem bloquear uma
melhoria de escrita dos construtores.

## Casos que precisam de decisão explícita

| Entrada | Proposta inicial para debate | Motivo |
|---|---|---|
| Sem dtype / dtype nil | Inferir pelas regras atuais | nil representa ausência de campo em Lua |
| Dtype false, vazio ou desconhecido | Erro | Não esconder argumento inválido com fallback por truthiness |
| Opção dytpe ou propriedade desconhecida | Erro contextual | Evitar sucesso com tipo diferente da intenção |
| Dtype legado e nomeado presentes | Rejeitar combinação | Uma única fonte da escolha evita precedência oculta |
| Series pronta + mesmo dtype | Aceitar apenas se confirmado o contrato de ownership | Igualdade de tipo não decide cópia/view |
| Series pronta + dtype diferente | Erro inicial; conversão explícita separada | Não converter ou ignorar silenciosamente |
| Schema + dtype por coluna | Rejeitar conflito; avaliar se permitir redundância | Definir autoridade única |
| Dois campos dtype na mesma tabela Lua | Limite da representação: não prometer detectar repetição já perdida na tabela | Validador recebe tabela avaliada, não o texto fonte |
| Opções compartilhadas entre chamadas | Ler e normalizar sem mutar a tabela fornecida | Reutilização previsível |
| Vazio, tudo NA, int64 cdata e nome com NUL | Preservar resultado e diagnóstico nas formas aprovadas | Exercitar ausência, precisão e bytes |
| map/full/from_array e factories especializados | Definir alcance da migração separadamente | Mesma palavra dtype não implica mesma regra de inferência |

## Parecer provisório e próxima avaliação

O foco anterior em comparar A e B na construção literal foi redirecionado
pelo mantenedor. As alternativas continuam disponíveis, mas não são o ponto de
partida da próxima decisão. Priorizar o fluxo da fixture de pedidos e código
reutilizável que recebe dados externos.

1. Entrada: onde declarar schema/dtype antes que a interpretação perca zeros
   iniciais, precisão ou informação de ausência? Distinguir tipo e dialeto.
2. Transformação: quando preservar o tipo e quando exigir/inferir o tipo do
   resultado? Examinar colunas calculadas, map, vazio e tudo NA, mantendo
   distintos os contratos existentes.
3. Composição: como receber Series já tipadas sem redeclarar dtype? Decidir
   conflitos e ownership, evitando conversão implícita ou declaração ignorada.
4. Saída: conferir preservação de valores e limites do formato; não presumir
   que CSV/JSON preservam todo dtype do Smaug.
5. Ergonomia: comparar opções nomeadas e reutilização de schema nos pontos
   encontrados; só então decidir se os construtores precisam mudar e quanto.

Elegância deve ser avaliada na continuidade desse percurso, equilibrando
scripts de análise e funções reutilizáveis. Os exemplos literais anteriores
servem para explicar e testar escolhas, não para definir sozinhos a prioridade.
Nenhuma alternativa A/B/C foi aprovada e não há implementação autorizada pela
pesquisa. Não alterar a inferência como efeito incidental da nova escrita.

Critério para encerrar a decisão: cenários prioritários avaliados, regras de
conflito/erro escritas, convivência com schema delimitada e expectativas
acordadas. Discussão e evidências ficam neste review; pendências continuam no
R4 e no checkpoint do roadmap, sem outra fila de implementação.
