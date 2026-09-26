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
