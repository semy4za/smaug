# Revisão de CSV/JSON e fronteira de inferência — 2026-09-25

## Estado e escopo

Mapeamento e registro das decisões discutidas, sem alterações de produção.
Os acordos sobre organização dos registros estão registrados abaixo;
as demais políticas continuam pendentes.
Referência local: commit `b34766c`. CSV e JSON continuam implementações próprias,
sem novas dependências. Bibliotecas externas foram consultadas como referências
de comportamento, não como código a importar nem como especificação do Smaug.

O mantenedor pediu revisão crítica da organização e da lógica antes das correções,
com discussão gradual dos problemas estruturais. A auditoria geral de inferência
continua aberta; este documento detalha a frente de I/O encontrada nessa auditoria.
Depois da revisão/correção da inferência, permanecem na ordem acordada:
`dayfirst` e detecção automática; migração dos 11 componentes datetime.

## Referências e critérios

- [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259.html): objetos associam nomes
  a valores sem depender da ordem; gramática, escapes e representação numérica.
  Limites numéricos da implementação são possíveis; alterar silenciosamente um
  inteiro fora da faixa não é uma política aprovada do Smaug.
- [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180.html): referência informativa
  para campos, aspas e quebras de linha. CSV tem dialetos; uma diferença de dialeto
  não deve ser automaticamente classificada como defeito.
- [Python csv](https://docs.python.org/3/library/csv.html): separa leitura de campos
  e adaptação por cabeçalho; oferece política para campos extras/ausentes e modo
  estrito. O leitor usual retorna strings. Serve para identificar decisões que
  o Smaug precisa explicitar, sem impor a API Python.
- [Python json](https://docs.python.org/3/library/json.html): distingue decodificação,
  conversão numérica e adaptação de objetos. Possui extensões e escolhas próprias,
  como nomes repetidos e números não finitos; seus padrões não são automaticamente
  adotados. Não é um oráculo estrito universal de conformidade JSON.
- [Lua CJSON](https://www.kyne.au/~mark/software/lua-cjson-manual.html): representa
  `null` com `cjson.null`; aceita NaN, infinito e hexadecimal na leitura por padrão,
  com configuração para desabilitar essa tolerância. Serve como referência Lua,
  sem adotar automaticamente suas extensões.
- [dkjson](https://dkolf.de/dkjson-lua/documentation): permite escolher a
  representação de `null` na decodificação, inclusive `json.null`; o padrão é
  `nil`. Essa escolha importa para preservar campos explicitamente nulos.
- [pandas: lista de dicionários](https://pandas.pydata.org/docs/user_guide/dsintro.html#from-a-list-of-dicts):
  a construção de DataFrame sem seleção explícita de colunas incorpora campos
  de registros posteriores e representa células ausentes como valores faltantes.
  Referência de adaptação tabular, não regra da gramática JSON.

O perfil atual do Smaug lê arrays de objetos com células escalares. JSON aninhado,
valores escalares no topo e arrays de arrays não precisam ser implementados apenas
porque existem na especificação geral: rejeição explícita pode delimitar o perfil.

## Decisão aprovada — associação por nome e união de campos

Na retomada após o rebase, o mantenedor aprovou o seguinte comportamento para
a leitura de arrays de objetos sem schema explícito:

- Associar cada valor pelo nome da chave, independentemente da posição no objeto.
- Formar as colunas pela união dos campos encontrados nos registros, incluindo
  campos que só aparecem depois do primeiro objeto.
- Preencher com NA as células de registros sem aquele campo, inclusive as linhas
  anteriores à primeira ocorrência de uma coluna nova.

Por exemplo, `[{"id":1,"nome":"Ana"},{"nome":"Bia","id":2,"idade":30}]`
deve conservar os pares nome/valor e incluir `idade`, com NA na primeira linha
e 30 na segunda. A associação por nome decorre da semântica JSON; a união dos
campos e o preenchimento com NA são decisões da adaptação para DataSet,
com referência no comportamento documentado do pandas.

Esta decisão ainda não foi implementada. A nomeação de colunas repetidas foi
aprovada no seguimento abaixo, assim como o tratamento de `null` e de textos
semelhantes a marcadores de ausência. A ordem de descoberta das colunas e a
validação sintática foram aprovadas no seguimento de 2026-09-26. Permanecem
abertas a inferência de dtype e uma futura API com schema explícito.

## Decisão aprovada — nomes únicos automaticamente, seguindo pandas

O mantenedor confirmou como referência a nomeação de cabeçalhos repetidos do
[pandas.read_csv](https://pandas.pydata.org/docs/reference/api/pandas.read_csv.html):
manter a primeira ocorrência e acrescentar sufixos `.1`, `.2` e assim por diante
às repetições, sem reordenar as colunas durante a desambiguação. Exemplo:
`id, id, nome, id` resulta em `id, id.1, nome, id.2`.

Foi explicitado que nomes repetidos não devem fazer a importação falhar. Se um
nome gerado também colidir, a desambiguação deve continuar até obter um nome
livre, preservando todas as colunas e seus valores, sem sobrescrever nem
descartar ocorrências. A convenção aprovada usa ponto, conforme a referência
do pandas. A regra é aplicada à adaptação tabular do Smaug; não é uma afirmação
de que `pandas.read_json` renomeia chaves JSON repetidas dessa forma.

Na leitura JSON, repetir uma chave em objetos diferentes continua identificando
a mesma coluna; essa repetição entre registros não gera sufixo. Ocorrências
repetidas dentro de um mesmo objeto devem ser preservadas em colunas distintas.
A implementação deve manter a correspondência dessas colunas entre registros,
inclusive quando já existem chaves com sufixos no documento.

Implementação pendente. Validar os casos de colisão contra a referência do
pandas e acrescentar regressões de preservação dos valores e de associação
entre registros.

## Decisão aprovada — nulidade e texto literal

Na conversão de JSON para DataSet:

- Campo ausente no registro corresponde a NA.
- Valor JSON `null` corresponde a NA.
- Strings `""`, `"null"` e `"NA"` permanecem texto válido, sem conversão para NA.

A máscara de nulidade do DataSet representa tanto a ausência de campo quanto
o `null` explícito. Essa adaptação não conserva a distinção entre as duas formas
na tabela resultante; o texto entre aspas continua distinto de ambas.
A política de marcadores textuais do leitor CSV não se aplica automaticamente
ao leitor JSON.

Inspeção dos fontes: `parse_value` já distingue tokens `null` de strings;
o preenchimento das séries já usa a máscara para valores nulos. O alinhamento
por posição ainda impede certificar campos ausentes em registros heterogêneos.
A correção deve preservar essa separação de tokens e cobrir os três textos
acima, junto de `null` e campo ausente, em regressões com máscara e conteúdo.
Não houve nova execução de testes nesta etapa de discussão.

## Decisão aprovada — ordem das colunas e validação sintática (2026-09-26)

As colunas seguem a ordem da primeira aparição no documento: começar pelos
campos do primeiro registro e acrescentar campos novos ao final. A nomeação
automática de repetições preserva essa ordem. O preenchimento continua usando
a correspondência dos campos, independentemente da posição no registro.
Exemplo: `[{"id":1,"nome":"Ana"},{"idade":30,"nome":"Bia","id":2}]`
produz as colunas `id`, `nome`, `idade`, nessa ordem.

A leitura deve validar a sintaxe JSON e consumir o documento completo,
permitindo apenas os espaços em branco previstos pela gramática depois do
valor final. Entradas malformadas devem retornar erro com posição e motivo,
sem entregar um DataSet parcial. Entre as regressões necessárias estão:

- Fechamento ausente de array, objeto ou string.
- Vírgula ausente ou final indevida.
- Escape inválido ou caractere de controle literal dentro de uma string.
- Número com gramática inválida, como `01` ou `1.`.
- Conteúdo não permitido após o documento.

Nomes repetidos seguem a desambiguação aprovada; não são motivo para rejeitar
a importação. A regra de erro acima trata da sintaxe. Limites de representação
numérica, comprimento de strings, BOM, validação de UTF-8 e surrogates isolados
ainda precisam do tratamento específico registrado nas pendências da revisão.
Implementação e testes dessas correções continuam pendentes.

## Organização atual

| Etapa | Implementação | Avaliação |
|---|---|---|
| CSV: campos e registros | `src/smaug_csv.c:next_field`, `smaug_read_csv_mem` | Ring 3; separação por posição é própria do formato |
| JSON: tokens e registros | `src/smaug_json.c:next_token`, `parse_record` | Ring 3; guarda nomes, mas construção posterior usa posições |
| Tipagem das colunas de I/O | `include/smaug_io_internal.h:dtype_upgrade` | Compartilhada por CSV/JSON; promoção numérica e fallback string entre famílias |
| Parsing numérico CSV | `smaug_convert` via wrappers CSV | Reutiliza mecanismo interno; adaptação de decimal fica no Ring 3 |
| Parsing numérico JSON | `strtoll`/`strtod` locais e buffer de 64 bytes | Gramática JSON é responsabilidade local; conversão/faixa precisam de revisão |
| Transporte de colunas | `smaug_table_t`, `smaug_column_t` | Fronteira de I/O; buffers tipados pertencem ao Ring 0 |
| Conversão para DataSet | `lua/smaug/io/csv.lua:table_to_dataset`, reutilizada por JSON | Copia C → tabela Lua → nova Series, com dtype explícito |
| Escrita | Adaptador Lua → writers C | CSV escapa campos; JSON escapa strings; mecanismos numéricos compartilhados |

A função de adaptação comum morar no módulo CSV cria dependência nominal de JSON
em CSV. Extraí-la para suporte comum de I/O é candidata a reorganização, não
condição para corrigir o parser. O problema mais urgente é preservar os dados e
a posse da memória nessa fronteira. Não propor zero-copy sem definir ownership.

Inferência externa e inferência Lua têm entradas diferentes: CSV começa como texto;
JSON conserva tipos de tokens; Series recebe valores Lua. Compartilhar primitivas
e regras aplicáveis não exige apagar essas diferenças. O reconhecimento de datas
deve convergir para o parser existente no Ring 0; regras de organização do arquivo
e decisões sobre schema continuam externas.

## Evidências executadas

Reprodutor: `luajit scripts/audit_io.lua`, executado da raiz com LuaJIT/UCRT64 e
DLL reconstruída dos fontes locais. É um script de observação com 30 casos,
não uma suíte de aprovação: código 0 não significa ausência de defeitos.
Os identificadores abaixo correspondem aos rótulos do script.

| Área / casos | Observado | Classificação / trabalho |
|---|---|---|
| JSON J01–J02 | Chaves reordenadas trocam valores; campo ausente desloca valor para outra coluna | Defeito confirmado: alinhar por nome antes da inferência |
| JSON J03 | Campo novo depois do primeiro objeto é descartado | União de campos aprovada para leitura sem schema explícito, com NA nas células ausentes; implementação pendente |
| JSON J04–J07 | Aceita falta de `]`, lixo após documento, ausência de vírgula e vírgula final | Defeito de validação sintática; revisar estados e consumo completo |
| JSON J08, J17 | Aceita `\q` e quebra literal dentro de string | Defeito de validação de escapes/controles |
| JSON J09, W01 | `a\u0000b` vira `a`; writer gera escape correto, reader perde o restante | Defeito de preservação de comprimento, também no roundtrip |
| JSON J10–J11 | Aceita `01` e `1.` como números | Defeito na gramática numérica |
| JSON J12 | Inteiro `9223372036854775808` chega ao Lua como `INT64_MIN` | Duas falhas: C ignora overflow e satura; adaptador passa por double e altera novamente |
| CSV C01 | Linha com três campos sob cabeçalho de dois perde o terceiro | Decisão pendente: rejeitar ou representar extras; descarte exige revisão |
| CSV C02 | Campo ausente vira NA | Comportamento existente a documentar e preservar/revisar conscientemente |
| CSV C03–C04 | Aceita aspas abertas; texto após aspas fechadas vira outra linha | Tolerância precisa de contrato; fabricação de linha exige correção |
| CSV C05 | NUL interno trunca `a\0b` para `a` | Definir rejeição de bytes não suportados ou suporte por comprimento; não truncar |
| CSV C08 / JSON J16 | Campo multilinha e par surrogate válido preservados | Evidência positiva limitada a esses casos |
| CSV C09 | `"NA"` vira ausência mesmo entre aspas | Política de NA existente, não erro de sintaxe; discutir representação de texto literal |
| CSV C10 | Mistura `true` e `1` permanece texto | Política de fallback do I/O; não confundir com coerção bool→número |
| J13, C06, B01 | C preserva `9007199254740993`; API Lua devolve `9007199254740992` | Defeito confirmado na ponte comum, em `tonumber` antes de reconstruir Series |
| JSON J14 / CSV C07 | Nomes duplicados são rejeitados só ao adicionar coluna no Lua | Nomeação automática com sufixos como no pandas aprovada para a frente JSON; implementar sem perder valores nem falhar por colisão. Revisar também contrato CSV e cleanup, inclusive API C |
| JSON J15 | Objeto aninhado é rejeitado | Restrição atual de perfil; não classificar como funcionalidade obrigatória |

Verificação adicional direta no C para J12: `9223372036854775808` retorna
`9223372036854775807` com status de leitura 0. O lexer não verifica `errno`
após `strtoll`. O limite do inteiro é uma decisão de representação; a corrupção
silenciosa observada não pode ser apresentada como inferência bem-sucedida.

## Pontos de inspeção ainda sem reprodução específica

- CSV cresce `rows` e `row_sizes` com dois `realloc` antes de atualizar os donos.
  Se um mover o bloco e o outro falhar, o caminho de erro merece revisão de
  ponteiros obsoletos e liberação. Não foi feita nova injeção dirigida a esse caso.
- Leitores ignoram resultados de preenchimento, inclusive `smaug_str_set`, que
  pode alocar. Revisar OOM sem entregar coluna parcial aparentemente válida.
- `table_to_dataset` libera a tabela C apenas ao final; erro durante construção,
  como nome duplicado, pode escapar antes da liberação. Verificar cleanup protegido.
- JSON reduz tokens numéricos a 63 bytes antes da conversão. Verificar números
  longos, expoentes, overflow, underflow e diagnóstico sem truncamento de token.
- Rotinas de arquivo e writers precisam conferir leitura curta, erro de stream,
  fechamento e diagnóstico; testes em memória não certificam esses caminhos.
- Validação UTF-8 bruto, BOM, opções inválidas, nomes com NUL, limites de tamanho,
  vazios, precisão em promoções int64→float64 e erros de escrita exigem matriz
  adicional. Não declarar essas áreas verificadas por este mapeamento.

## Testes existentes e limites da revisão

Build Windows completa com `scripts/build.ps1 -SkipManifest` terminou com código 0:
13 suítes C, 20 Lua e 15 scripts de paridade. Log local em
`build/inference-audit-build.log`. Isso não certifica os cenários novos acima.

`test_json_short_record` usa um segundo registro totalmente vazio: verifica NA,
mas não distingue associação por nome de associação por posição.
`test_csv_quotes_unclosed` exige apenas retorno não nulo; não estabelece uma
política completa de erro nem verifica conteúdo. Há testes existentes de aspas,
multilinha, Unicode/surrogates, tipos mistos, NA e roundtrip que devem ser preservados.

Não houve sanitizers, Valgrind, nova cobertura, comparação executável com Python
ou auditoria exaustiva de todos os casos das especificações. A consulta às
bibliotecas foi documental. Nenhuma regra externa foi convertida automaticamente
em mudança de contrato do projeto.

## Verificação de preservação de valores — Linux, 2026-09-26

Seguimento do checkpoint de `TEST_SUITE_REWORK.md`: verificar preservação de
valores e limites antes de propor novas políticas. Nenhum código de produção
foi alterado. A reformulação completa do Roadmap foi solicitada para depois
desta etapa; não faz parte desta verificação.

Ambiente: base `ad6a380`, LuaJIT 2.1.1767980792, Linux x64, Python 3.14.7.
Os binários de teste C existiam, mas `build/libsmaug.so` estava ausente.
`make` reconstruiu a biblioteca com sucesso; depois foram executados os 30
casos de `scripts/audit_io.lua` e os 8 casos de
`scripts/audit_io_values.lua`. Ambos são observacionais: terminar com código
0 não significa aprovação. Os resultados anteriores de perda de valores,
desalinhamento e sintaxe permissiva se reproduziram no Linux.

### Comparação executada: Smaug C, adaptador Lua e Python

Cada token abaixo foi colocado em `[{"v":TOKEN}]`. O script novo consulta
primeiro a tabela C e depois a API Lua; int64 é observado sem `tonumber`.
Python foi executado com `json.loads`, configuração padrão.

| Token / caso | Smaug C | Smaug Lua | Python 3.14.7 |
|---|---|---|---|
| `"a\u0000b"` | `"a"`, 1 byte | `"a"`, 1 byte | `a`, NUL, `b`, 3 caracteres |
| `9007199254740993` | inteiro exato | `9007199254740992` | inteiro exato |
| `9223372036854775807` | inteiro exato | `-9223372036854775808` | inteiro exato |
| `9223372036854775808` | satura em `9223372036854775807` | `-9223372036854775808` | inteiro exato |
| `-9223372036854775809` | satura em `-9223372036854775808` | mesmo valor saturado | inteiro exato |
| `1e400` | erro genérico ao parsear objeto | erro propagado | `inf` |
| `1e-400` | erro genérico ao parsear objeto | erro propagado | `0.0` |
| `1` + 63 zeros + `e-63` (valor exato 1) | `1e62` | `1e62` | `1.0` |

Reprodução da coluna Python, sem dependências externas:

```python
import json
tokens = ['"a\\u0000b"', '9007199254740993', '9223372036854775807',
          '9223372036854775808', '-9223372036854775809',
          '1e400', '1e-400', '1' + '0' * 63 + 'e-63']
for token in tokens:
    value = json.loads('[{"v":' + token + '}]')[0]['v']
    print(repr(value), type(value).__name__)
```

### Causas verificadas no código

- JSON: `read_json_string` decodifica o NUL, mas não transporta o comprimento
  em `json_val_t`; o preenchimento usa `strlen(v->s)` e perde o restante.
  CSV também preenche strings com `strlen(v)`. O caso C05 reproduz a perda.
  A Series string e o adaptador de saída C→Lua usam comprimento explícito;
  portanto o truncamento observado já aconteceu antes dessa saída.
- `table_to_dataset`, em `lua/smaug/io/csv.lua`, converte int64 com
  `tonumber(v)` antes de reconstruir a Series. JSON reutiliza esse adaptador.
  B01 confirma que os dois leitores C preservam `2^53+1` nessa etapa.
- `next_token`, em `src/smaug_json.c`, zera `errno` antes de `strtoll`, mas
  não verifica seu valor depois: overflow e underflow inteiros saturam.
- O mesmo tokenizador consome o número completo, mas copia no máximo 63 bytes
  para conversão. No caso longo, mantém a classificação float pelo expoente
  original e converte apenas o prefixo, sem o expoente. Esse defeito foi agora
  reproduzido, não é mais apenas hipótese de inspeção.
- O caminho `strtod` verifica `errno` e rejeitou os dois extremos testados;
  o diagnóstico atual não distingue erro de sintaxe de limite numérico.

### Referências externas reconferidas

Consulta em 2026-09-26; execução comparativa limitada ao Python acima.

- [RFC 8259, seções 6 e 7](https://www.rfc-editor.org/rfc/rfc8259.html#section-6):
  permite limites de faixa/precisão; não exige bigint. U+0000 é representável
  por escape em strings. Um token longo pode representar um valor pequeno:
  comprimento do token e magnitude não são a mesma restrição.
- [Python json](https://docs.python.org/3/library/json.html#json.load): usa
  `int` e `float` por padrão, com `parse_int`/`parse_float` configuráveis.
  A exatidão dos inteiros observados não obriga o Smaug a ampliar seu int64.
  Os resultados `inf` e zero mostram por que esse decoder não define sozinho
  a política desejada para extremos numéricos.
- [Lua CJSON 2.1.0, decode](https://www.kyne.au/~mark/software/lua-cjson-manual.html#_decode):
  documenta escapes para NUL e passagem de bytes sem validação de UTF-8.
  Suas extensões numéricas são configuráveis. Manual consultado; biblioteca
  não executada nesta rodada, sem alegar equivalência com o Smaug.
- [dkjson 2.11](https://dkolf.de/dkjson-lua/documentation): documenta o marcador
  de null configurável e a posição seguinte retornada pelo decoder. Essa
  documentação não certifica exatidão int64 nem validação de consumo completo
  pelo chamador. Biblioteca não executada nesta rodada.

### Distinção entre defeitos e decisões ainda abertas

Preservar um int64 já válido no C ao transportá-lo ao Lua não exige escolher
uma nova política de inferência. Truncar strings ou tokens silenciosamente
também não é uma alternativa aprovada. As correções permanecem pendentes.

Ainda discutir, um bloco por vez: suporte por comprimento ou rejeição explícita
de NUL (separando valores de nomes); política para inteiros além de int64;
overflow/underflow float e promoções int64→float64; limites de tamanho e
diagnósticos. Nenhuma dessas alternativas virou contrato por esta verificação.
Não foram executados sanitizers, injeção nova de OOM, auditoria UTF-8/BOM,
testes de arquivos/writers ou a suíte completa nesta rodada.

## Revisão do parecer sobre NUL — 2026-09-26

O parecer apresentado pelo mantenedor confirma o diagnóstico de comprimento,
mas as propostas de política abaixo ainda não são tratadas como contrato aprovado.
Continuamos na etapa de documentação e verificação, sem alteração de produção.

- Nome e valor já são separados por estrutura. Não existe delimitador
  `nome\0valor`. Separar a discussão dos nomes da dos valores significa
  examinar representações diferentes: `name` é uma string C sem comprimento
  público; valores string usam Series com comprimento explícito.
- O nome também pode conter NUL na entrada JSON. Executado no Linux:
  `smaug.read_json_mem('[{"a\\u0000b":1}]'):columns()` devolve nome `a`,
  de comprimento 1. Portanto há truncamento de nomes além de valores.
  Rejeitar esses nomes seria restrição da adaptação tabular do Smaug, não
  proibição sintática do JSON. Deve ocorrer antes de `strdup`/comparação que
  perca o sufixo; nomes fornecidos pelo Lua precisam de auditoria equivalente.
- A solução interna para valores JSON é ponteiro **mais comprimento**;
  isso não exige prefixar bytes no buffer nem alterar a ABI pública.
  O comprimento deve atravessar lexer, valor intermediário e preenchimento.
  Adicionar `size_t` em `json_val_t` afeta todos os elementos desse array,
  não apenas os que contêm strings; custo exato depende do layout/alinhamento.
- A [gramática da RFC 4180](https://www.rfc-editor.org/rfc/rfc4180.html#section-2)
  exclui NUL tanto em campos comuns quanto entre aspas. Isso é mais preciso
  que dizer que a RFC apenas não o menciona. Entretanto há dialetos distintos:
  Python 3.14.7 preservou NUL em
  `list(csv.reader(io.StringIO('v\na\x00b\n')))`, produzindo duas linhas,
  com `a\x00b` na segunda. Não foi verificada a alegação sobre a maioria
  dos consumidores. O header atual do Smaug também anuncia bytes crus.
- Se a política escolhida for rejeitar NUL em CSV, leitura e escrita devem
  ser simétricas. Nesse caso, não é obrigatório remodelar todos os campos
  para carregar comprimento: uma verificação sobre o buffer de entrada com
  tamanho conhecido pode bastar, com diagnóstico apropriado. `memchr` é O(n);
  fundir a validação a um percurso existente não a torna O(1).
- Preservar NUL em valores JSON não depende tecnicamente de implementar antes
  a união de campos ou a associação por nome. São defeitos independentes;
  coordenar as mudanças é útil para evitar retrabalho, mas não é pré-requisito.
- O teste proposto para campo vazio CSV não deve exigir string vazia por
  padrão: o Contrato 9 já define campo vazio como NA. NUL, string vazia e NA
  são distintos internamente, sem que todo formato preserve essa distinção.
- Uma mutação discriminante deve trocar o comprimento correto por `strlen`
  e produzir falha de teste. Remover o membro da struct e causar erro de
  compilação não demonstra que a asserção detecta truncamento.
- Os exemplos do parecer são esboços: usar o comprimento real do literal
  (`sizeof(literal)-1`), a assinatura atual do writer com `err_out`, liberar
  os recursos e usar a API Lua `column`. Não copiar os exemplos como testes
  prontos. Exibição de controles precisa de verificação própria; a alegação
  de corrupção do terminal por NUL não foi demonstrada.
- O item 12.33 trata de colação e propagação de NA em comparações. Uma regra
  de transporte de NUL não resolve esses dois contratos e não encerra o item.

Proposta do parecer a deliberar: preservar NUL em valores JSON, rejeitar NUL
na leitura/escrita CSV e rejeitar NUL em nomes de colunas. A primeira se apoia
no armazenamento já existente; as duas últimas restringem a superfície de
entrada e precisam ficar explícitas. A política de display é uma frente
adicional, não certificada pela verificação de I/O.

## Decisão aprovada — preservar NUL em valores e nomes (2026-09-26)

O mantenedor rejeitou a restrição e confirmou preservar NUL em valores e nomes
de colunas, em CSV e JSON. Esta decisão substitui as propostas de rejeição acima;
não aprova as demais políticas numéricas ou de codificação pendentes.

- NUL é conteúdo, distinto de string vazia e NA. Nunca delimita nome/valor.
- JSON lê e escreve NUL escapado como `\u0000`, inclusive em chaves. NUL literal
  não escapado continua inválido pela regra sintática aprovada.
- CSV preserva o byte, inclusive no cabeçalho, como extensão explícita do
  dialeto em relação à RFC 4180. Não se promete compatibilidade com todo leitor.
- Associação, união e desambiguação distinguem `a` de `a\0b` pelos bytes completos.
- Campo vazio CSV continua NA por padrão. Campo com NUL não pode ser confundido
  com vazio, marcador de NA ou número por analisar apenas seu prefixo.

### Percurso dos nomes verificado no Linux

Construção `smaug.DataSet({{"a", {1}, "int64"}, {"a\0b", {2}, "int64"}})`:
o Lua conserva nomes de comprimentos 1 e 3, e `column` recupera 1 e 2.
Porém `to_json_mem()` escreve `[{"a":1,"a":2}]` e `to_csv_mem()` escreve
`a,a\n1,2\n`. Leitura de `[{"a\\u0000b":2}]` (literal Lua) e de
`a\0b\n2\n` também devolve nome `a`, de comprimento 1.
Já o writer CSV de uma coluna `v` contendo `a\0b` emite `v\na\0b\n`,
preservando NUL no valor; a leitura desse valor permanece defeituosa.

| Trecho | Ponto identificado |
|---|---|
| DataSet Lua (`dataset/_core.lua`) | Strings/tabelas já distinguem os nomes no cenário executado |
| Lexer e records JSON | Não transportam comprimento das chaves; `strdup` na cópia perde o sufixo |
| Campos e cabeçalho CSV | Campos não transportam comprimento; cabeçalho copiado por `strdup` |
| Fronteira C de I/O | `smaug_column_t.name` não tem comprimento público |
| C→Lua | `ffi.string(col.name)` usa terminação NUL |
| Lua→C | Aloca `#cname+1` e copia string, mas não transporta comprimento ao writer |
| Writers CSV/JSON | Ambos usam `strlen(name)` |
| União e nomes repetidos | Implementação futura deve comparar comprimento e todos os bytes |

Modificar `smaug_column_t` exige sincronizar header público, `ffi.cdef`,
construtores C/Lua, consumidores, testes de layout e documentação da ABI.
Isso difere da alteração interna de `json_val_t`. A representação pública e
a estratégia de compatibilidade ainda precisam ser definidas.
`smaug_metadata_t.name` também não tem comprimento; auditar seu uso e relação
com o nome do DataSet antes de estabelecer o alcance da migração.

Para valores CSV, revisar reconhecimento de NA, bool e números: levar o
comprimento só até `smaug_str_set` não basta se a inferência anterior examinar
apenas o prefixo. Exibição e diagnósticos com controles permanecem verificação
separada. Implementação e regressões de aprovação continuam pendentes.

## Verificação da proposta de API/FFI para nomes — 2026-09-26

Direção técnica proposta: `name` acompanhado por `name_len` na fronteira de
I/O, propagado nos dois sentidos e usado nos writers. Preservar NUL já está
aprovado; detalhes de layout, compatibilidade e metadata abaixo ainda são
desenho, sem alteração de produção.

Confronto do segundo parecer com os fontes:

- `smaug_column_t` está definido em `include/smaug_types.h`, não em
  `smaug_io.h`. Adicionar comprimento exige atualizar também seu espelho FFI.
- O parecer coloca `name_len` após `name` nos exemplos, mas recomenda no texto
  colocá-lo no final. São layouts diferentes; escolher um só na implementação.
  Mesmo adicionar no final **não preserva ABI**: o tamanho e o passo de arrays
  mudam, assim como alocações feitas por consumidores antigos.
- O eixo 15 (`scripts/parity/15_abi_layout.lua`) compara arquivos header/cdef.
  Não inspeciona o binário carregado. Uma biblioteca antiga com os fontes novos
  pode passar nesse eixo e ainda corromper memória. Quebra de ABI e recompilação
  conjunta não garantem por si só erro explícito; definir verificação de versão
  ABI/layout do artefato carregado antes de prometer detecção em runtime.
  A sentinela SIZE_MAX não resolve incompatibilidade de layout entre binários.
- Accessor é tecnicamente possível se os consumidores FFI migrarem para ele;
  a leitura direta atual não o torna inviável. Ainda seria preciso armazenar
  o comprimento em algum lugar. Não adotar nem descartar sem comparar o escopo.
- Não foi encontrada a cópia presumida de nome de coluna para `meta.name`:
  construtores C usam `"unnamed"`; o nome Lua vive em `_name` e nas chaves do
  DataSet. `smaug_str_clone` copia o ponteiro de metadata. Logo a mudança de
  metadata não é pré-requisito demonstrado para corrigir os nomes de I/O.
  Se incluída, definir ownership/lifetime, nomes ausentes e cópia do comprimento,
  além de sincronizar os layouts das Series afetadas.
- `name[name_len] == 0` pode ser convenção para buffers alocados internamente,
  mas não pode ser dereferenciado quando `name == NULL`. Definir o contrato de
  ponteiro nulo versus nome vazio, e não exigir terminador de um buffer externo
  sem documentar que há espaço adicional acessível. `%s` continua truncando NUL.
- `write_json_string` já recebe `(buffer, string, comprimento)` e percorre o
  comprimento. O problema dos nomes está no `strlen` passado pelo chamador.
- Inferência precisa examinar o campo inteiro. Campos como `123\0abc`,
  `NA\0xyz` e um NUL isolado devem preservar texto, conforme a decisão vigente.
  `na_values` configurável ainda usa `const char **` sem comprimentos; verificar
  esse limite separadamente antes de prometer suporte a marcadores com NUL ou
  estabelecer uma regra absoluta que ignore configuração explícita futura.
- `nan` não é NA por padrão no Smaug (Contrato 9). Não misturar o reconhecimento
  de não finitos com o de marcadores de ausência durante a migração.
- Em testes, escrever NUL com construção inequívoca: em Lua `"1\0" .. "2"`,
  pois `"1\02"` contém escape decimal 2. A mutação precisa compilar e ser
  detectada pelas asserções; remover um campo e quebrar compilação não basta.

Conclusão de desenho: comprimento explícito para nomes de I/O é adequado;
compatibilidade binária e inclusão de metadata precisam ser resolvidas com
essas evidências, sem ampliar o escopo por uma cópia de nomes inexistente.
CSV aceitar NUL em nomes/valores já foi decidido e não deve ser reaberto.

## Desenho aprovado — identificação de ABI no carregamento (2026-09-26)

Recorte aceito pelo mantenedor: migrar `smaug_column_t` e seus consumidores;
metadata fica em frente separada. O mecanismo abaixo concretiza a proposta
de compatibilidade, aprovado no seguimento pelo mantenedor; ainda não está
implementado. A aprovação não certifica execução em Windows nem fecha os
detalhes de nomes ausentes citados ao final.

### Estado confirmado

`ffi_loader.lua:load_library` tenta os caminhos locais de build, o instalado
e a resolução pelo SO. Retorna a primeira biblioteca que `ffi.load` consegue
abrir, sem consultar versão. Não foi encontrada função de identificação de ABI
nos headers/fontes. Uma sondagem com declaração FFI temporária de
`uint32_t smaug_abi_version(void)` e `pcall` sobre a biblioteca atual retornou
`undefined symbol: smaug_abi_version`, capturado como erro Lua. Nenhum ponteiro
de Series/tabela foi acessado nessa sondagem. Evidência limitada ao Linux atual.

### Desenho registrado

1. Exportar `uint32_t smaug_abi_version(void)`, sem argumentos, sem alocação e
   sem estruturas no retorno. A assinatura deve permanecer estável entre ABIs.
   Um header público dedicado pode declarar a função e `SMAUG_ABI_VERSION`,
   incluído pelo umbrella. A primeira ABI identificada seria 1, já com
   `name_len`; bibliotecas anteriores são identificadas pela ausência do símbolo.
2. O frontend mantém o número esperado da ABI de seu próprio cdef. Não o lê do
   binário para aceitar automaticamente qualquer versão. Após `ffi.load`,
   consulta a função dentro de `pcall`, antes de devolver a biblioteca a outro
   módulo ou chamar qualquer API que use estruturas compartilhadas.
3. Símbolo ausente ou versão diferente: falhar com o candidato carregado,
   versão esperada, versão encontrada (ou ausência do identificador) e orientação
   para atualizar/recompilar biblioteca e frontend juntos. Versão maior também
   não implica compatibilidade: a comparação é por igualdade.
4. Continuar a busca quando um candidato não puder ser aberto, como hoje.
   Se abrir e revelar ABI incompatível, interromper, sem recorrer silenciosamente
   a outra instalação. Assim um build local antigo não fica mascarado por uma
   biblioteca do sistema. O candidato informado não é necessariamente o caminho
   absoluto resolvido pelo SO; não apresentá-lo como hash/proveniência verificada.
5. Sem fallback para `strlen` ou sentinela de comprimento: todos os produtores
   da nova ABI devem fornecer comprimento real. Proposta de layout: `name_len`
   imediatamente após `name`, igual no C e no cdef; recompilação conjunta.
   Isso não é declarado compatível com consumidores binários antigos.

Versão de ABI é diferente de versão de produto ou hash de build. Deve mudar ao
alterar layout/assinatura/contrato binário incompatível. A consulta não prova
que toda implementação está correta, nem detecta mudança cujo responsável
esqueceu de atualizar o identificador. Header/cdef continuam verificados pelo
eixo 15; testes de tamanho/offset contra C compilado complementam a verificação.
Não se promete proteção a um frontend antigo que não executa essa consulta.

### Validação planejada para a implementação

- Biblioteca atual sem identificador: rejeição antes de operações de Series/I/O.
- Biblioteca mínima de teste com versão diferente: rejeição orientada.
- Biblioteca nova com versão esperada: carregamento e roundtrip com pelo menos
  duas colunas, incluindo nomes `a` e `a\0b`, para exercitar o passo do array.
- Candidato local incompatível com outro candidato compatível disponível:
  confirmar interrupção, sem fallback que esconda o problema.
- Conferir `sizeof`/`offsetof` de `smaug_column_t` entre C compilado e FFI e
  executar a paridade header/cdef. Validar Linux e Windows na migração; não
  inferir sucesso no Windows pela sondagem feita nesta rodada.

Nomes vazios têm comprimento 0 legítimo. A implementação ainda deve definir
explicitamente a aceitação de `name == NULL` nos writers, separada do transporte
de nome vazio, e preservar as regras de ownership dos buffers existentes.

## Verificação de NUL na inferência e nos marcadores CSV — 2026-09-26

Adicionados 11 casos observacionais a `scripts/audit_io_values.lua` (agora
19 casos no total) e executados com a mesma biblioteca Linux, sem alterações
de produção. Os 8 casos JSON anteriores foram reexecutados junto.

| Campo CSV / opções | Resultado atual |
|---|---|
| NUL isolado, padrão | NA |
| `123\0abc`, padrão | int64 123 |
| `1.5\0abc`, padrão | float64 1.5 |
| `true\0abc`, padrão | bool true |
| `NA\0xyz`, padrão | NA |
| `null\0xyz`, padrão | NA |
| `nan\0xyz`, padrão | float64 NaN |
| NUL isolado, `na_values={}` | string vazia, 0 bytes |
| `NA\0xyz`, `na_values={"NA\0xyz"}` | NA |
| `NA`, `na_values={"NA\0xyz"}` | NA |
| `NA\0other`, `na_values={"NA\0xyz"}` | NA |

Os três últimos resultados demonstram que o caso de igualdade exata isolado
seria um teste insuficiente: o marcador e os campos distintos são reduzidos
ao mesmo prefixo pela comparação `strcmp`. No C, `smaug_csv_opts_t.na_values`
é `const char **` sem comprimentos; o Lua passa strings, mas não seus tamanhos.
`try_bool` também usa `strcmp`; os parsers numéricos chamados são variantes
`_cstr`. A decisão de preservar o campo completo precisa alcançar inferência,
reconhecimento de NA e preenchimento, além da própria extração do campo.

Consequência para o desenho: a fronteira de opções CSV contém outro transporte
de strings fornecidas pelo usuário, além de `smaug_column_t.name`. Para suportar
marcadores configuráveis com NUL sem restringir essa capacidade, é necessário
representar seus comprimentos em `smaug_csv_opts_t` ou em uma API equivalente.
Isso deve ser considerado na mesma migração de ABI, antes de congelar o layout.
Metadata continua fora desse caminho.

Recomendação a incorporar ao desenho: comparação exata por comprimento/bytes
com marcadores explicitamente configurados; se nenhum marcador casar, um campo
com NUL é texto. Assim `na_values={"NA\0xyz"}` pode marcar esse valor como NA
sem converter `NA` ou `NA\0other`. Não confundir essa configuração voluntária
de ausência com truncamento ou inferência automática. Representação pública
dos comprimentos dos marcadores ainda por definir; sem mudança de contrato
implementada por esta rodada.

## Conferência do core e FFI antes da migração CSV — 2026-09-26

Orientação do mantenedor: conferir core e FFI antes de alterar C, buscando
primitivas existentes e verificando contratos, layouts e consumidores.
Nesta rodada foram lidos `include/smaug_convert.h`, `src/smaug_convert.c`,
os consumidores em `src/smaug_astype.c`, o cdef e `apply_opts` do frontend CSV.
Não houve alteração de produção.

### Primitiva existente, mas ainda incorreta para NUL

O core já oferece `smaug_parse_i64(ptr, len, out)` e
`smaug_parse_f64(ptr, len, out)`. Porém ambas copiam para buffer local,
acrescentam terminador e delegam às variantes `_cstr`, que não sabem onde
o slice original termina. NUL interno permite aceitar apenas seu prefixo.

Quatro casos adicionados a `audit_io_values.lua` (23 no total) verificam
essas funções diretamente e seu consumo por `astype`:

| Entrada | Core i64 | Core f64 | astype i64 / f64 |
|---|---|---|---|
| `123\0abc` | sucesso, 123 | sucesso, 123 | 123 / 123 |
| `1.5\0abc` | falha | sucesso, 1.5 | NA / 1.5 |
| espaço seguido de `\0abc` | falha | falha | NA / NA |
| `1` + 63 zeros + `e-63` | falha | falha | NA / NA |

Saída inicializada em 77 ficou intocada nos casos de falha observados.
O último caso atinge o limite explícito de 64 bytes das variantes com tamanho;
as variantes `_cstr` não têm esse mesmo limite. Não substituir cegamente todas
as chamadas CSV: isso mudaria a aceitação de tokens longos. A gramática JSON
também continua responsabilidade do leitor, não das primitivas genéricas.

Conclusão: corrigir validação do slice na fonte comum para exigir o conteúdo
completo antes de reutilizá-la na inferência. Conversão explícita numérica
continua com sua política atual de texto inconversível→NA; leitura CSV pode
preservar como string. São consumidores com políticas diferentes, não motivo
para duplicar mecanismo de conversão. A declaração FFI usada na sondagem ficou
apenas no script observacional; esses parsers não são chamados diretamente
pelo frontend de produção e não precisam de cdef novo só por serem usados no C.

### Proposta de transporte de marcadores sem parsing duplicado

O FFI espelha corretamente a limitação atual de `smaug_csv_opts_t`:
`const char **na_values` acompanhado de contagem, sem comprimentos. `apply_opts`
mantém o array e as strings vivos por uma âncora até a chamada C terminar.

Proposta mínima para a nova ABI: acrescentar `const size_t *na_lengths` junto
de `na_values`; ambos têm `na_count` elementos. Lua fornece `#value` e mantém
o novo array na mesma âncora. Sem alocação/liberação pelo leitor desses buffers
emprestados. Comparar comprimento e bytes; não passar por conversor numérico.

- `na_values == NULL`: marcadores padrão internos, com comprimentos conhecidos.
- Array explícito e contagem zero: nenhum marcador (preservar `na_values={}`).
- Contagem positiva: exigir array de comprimentos válido e entradas válidas;
  não tentar recuperar tamanho com `strlen` nem assumir que zero é sentinela.
- Marcador vazio tem comprimento zero legítimo; marcador com NUL só casa
  quando todos os bytes e o comprimento forem iguais.

Esse desenho exige atualizar header, cdef, valores padrão e todos os callers
C que personalizam marcadores. Deve entrar na mesma migração ABI dos nomes;
representação proposta ainda não implementada. Evita criar um tipo genérico
novo ou mudar metadata apenas para esse transporte.

## Critérios de verificação C vinculados aos anéis — 2026-09-26

O mantenedor exige rigor de evidência e reafirmou que a arquitetura de anéis
é constitutiva do Smaug. Referência: `ARCHITECTURE.md`, princípios P2/P3/P4 e
responsabilidades dos anéis 0, 1 e 3. O critério não autoriza mover políticas
externas ao núcleo nem redesenhar APIs por uniformidade superficial.
Duas revisões independentes de core/consumidores/FFI/testes foram confrontadas
com a inspeção principal; nenhuma alterou produção.

| Responsabilidade | Local da correção/verificação |
|---|---|
| Consumo completo de slice numérico, limites de acesso, ponteiros verificáveis e saída preservada em falha | Primitiva compartilhada `smaug_convert`, Anel 0 |
| Armazenamento de bytes, máscara e ownership de buffers colunares | Anel 0, sem conhecimento de CSV/JSON |
| Contrato de conversão explícita da Series e resultado por elemento | Anel 1, consumindo as conversões C existentes |
| Tokenização, gramática, cabeçalhos, dialeto/decimal, `na_values` e adaptação/inferência dos formatos | Anel 3, inclusive quando implementado em C |
| `smaug_column_t`, opções CSV e buffers de transporte | Fronteira de I/O do Anel 3; localização em header comum não muda a responsabilidade |
| Espelho dos tipos, assinaturas, lifetime de dados emprestados e verificação ABI acordada | FFI/loader; não selecionar dtype, interpretar NA ou reparar valores |

### Evidências adicionais e limites

Novo reprodutor observacional `scripts/audit_numeric_parse.c`, compilado
diretamente com o fonte atual de `smaug_convert` (`-O2 -g -Wall -Wextra -Werror`),
executou 28 cenários normais sob Valgrind com `--error-exitcode=99` e
`--leak-check=full`. Retorno 0 e nenhum erro de memória reportado nesse percurso;
isso não aprova a semântica: NUL interno e NUL final incluído no slice continuam
aceitando apenas o prefixo. O reprodutor imprime observações e não contém
asserções de aprovação. Comandos:

```sh
gcc -std=c11 -Wall -Wextra -Werror -O2 -g -Iinclude scripts/audit_numeric_parse.c src/smaug_convert.c -o /tmp/smaug-audit-numeric
valgrind --quiet --error-exitcode=99 --leak-check=full /tmp/smaug-audit-numeric
```

- Slice sem terminador de exatamente 3 bytes contendo `123` foi aceito sem
  erro de memória reportado. O byte terminador externo não pertence ao slice;
  NUL dentro do comprimento declarado é conteúdo que precisa ser validado.
- `0...01` com comprimento 63 retorna 1; comprimentos 64 e 65 falham e mantêm
  a saída 77. Esse caso distingue o limite de tamanho de overflow numérico.
- Vazio, apenas espaço, sinal isolado e expoente incompleto são rejeitados
  atualmente. Não foram reclassificados como defeitos. Espaço inicial antes
  de número é aceito; espaço final é rejeitado, conforme comportamento existente.
- Limites i64 são aceitos exatamente; seus vizinhos fora da faixa falham.
  Os casos de falha com saída válida mantiveram as sentinelas observadas.
- `0x1p-1074` é aceito como menor subnormal no Linux; o decimal
  `4.9406564584124654e-324` é rejeitado. O caminho de conversão trata `errno`
  como falha. A política de underflow/subnormais continua pendente; não alterar
  silenciosamente essa política junto da correção de NUL.
- Revisão independente executou cada um dos quatro parsers com entrada `1`
  e `out=NULL`, em subprocessos Python isolados com `RLIMIT_CORE=(0,0)`.
  Os quatro terminaram com SIGSEGV. A escrita sem guard também está visível
  no fonte. É uma lacuna frente ao princípio defensivo do núcleo; validar NULL
  não equivale a prometer detecção de todo ponteiro inválido não nulo.
- Tentativa de compilar o probe com ASan/UBSan falhou no link por ausência de
  `/usr/lib64/libasan.so.8.0.0` e `/usr/lib64/libubsan.so.1.0.0`. Não houve
  execução instrumentada nem certificação de ausência de UB. Clang indisponível.

### Porta de aceitação para a correção futura

1. Regressões independentes no core para NUL inicial/intermediário/final, limite
   de slice, buffer não terminado, fronteiras numéricas e ponteiros NULL.
   Reinicializar e conferir `out` em cada falha; comparar bytes/máscara da fonte.
2. Exercitar consumidores C e Lua conforme seus contratos: texto inconversível
   em astype numérico vira NA; campo CSV com NUL permanece texto salvo marcador
   configurado que case integralmente. Não criar política de arquivo no core.
3. Mutação compilável que volte a aceitar só o prefixo deve ser detectada pelas
   asserções. Relacionar cada mutação à propriedade perdida; compilar não é
   substituto de um teste que detecta resultado errado.
4. Verificar falhas de alocação nos caminhos que realmente alocam e exigir
   diagnóstico/cleanup/ausência de saída parcial. As quatro primitivas numéricas
   atuais não fazem alocação dinâmica; OOM nelas não é cenário a inventar.
5. Executar memória/UB com ferramentas funcionais e builds identificados nas
   plataformas suportadas; registrar qualquer lacuna em vez de inferir sucesso.
   Medir cobertura pertinente e justificar exclusões ramo a ramo. Cobertura
   branch-alvo 100% não demonstra MC/DC nem ausência de defeitos.

Limitações concretas da suíte atual: o teste i64 de comprimento usa 79 noves,
caso que também estoura int64 e não discrimina a remoção do guard de tamanho.
`test_allocfail.c:1726` tem `... || 1`, sempre verdadeiro; a campanha de I/O
com teto fixo de 64 alocações não demonstra cobertura de cada ponto de falha.
Registrar esses pontos na revisão dos respectivos testes; não usar suas contagens
como prova suficiente de correção. Não houve suíte completa ou nova cobertura
nesta rodada, nem alterações no núcleo, FFI ou parsers de produção.

## Ordem proposta para discussão e trabalho

1. Organização JSON por nome, união dos campos, nomeação automática de colunas
   repetidas como no pandas e política de nulidade aprovados: campo ausente e
   `null` viram NA; `""`, `"null"` e `"NA"` permanecem texto. Ordem por primeira
   aparição também aprovada. Pendem linhas CSV com largura divergente ou nomes
   duplicados; implementar após a discussão das políticas restantes.
2. Validação da sintaxe JSON e consumo completo aprovados, com erro indicando
   posição e motivo, sem DataSet parcial. Implementação pendente; completar
   políticas específicas de codificação e limites sem confundir sintaxe com
   inferência de dtype.
3. Corrigir preservação de valores: comprimento de strings, limites numéricos,
   exatidão C/Lua; revisar cleanup e falhas de alocação nos caminhos envolvidos.
4. Concluir o mapa da inferência Lua e I/O: `from_dict`, `full`, mapas normal e
   categórico, `explode`, `ifelse` e consumidores com dtype já determinado.
   Os pontos Lua foram localizados, mas ainda não têm auditoria completa neste documento.
5. Implementar as correções discutidas com regressões independentes. Só depois
   integrar `dayfirst`/detecção automática e migrar os componentes datetime.

São blocos para discutir um de cada vez. Não há autorização inferida para
reescrever todos os módulos ou ampliar o perfil JSON para objetos aninhados.
