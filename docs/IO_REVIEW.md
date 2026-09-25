# Revisão de CSV/JSON e fronteira de inferência — 2026-09-25

## Estado e escopo

Mapeamento para discussão, sem alterações de produção ou de contratos.
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

O perfil atual do Smaug lê arrays de objetos com células escalares. JSON aninhado,
valores escalares no topo e arrays de arrays não precisam ser implementados apenas
porque existem na especificação geral: rejeição explícita pode delimitar o perfil.

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
| JSON J03 | Campo novo depois do primeiro objeto é descartado | Decidir schema: união de campos ou rejeição explícita; evitar descarte silencioso |
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
| JSON J14 / CSV C07 | Nomes duplicados são rejeitados só ao adicionar coluna no Lua | Falha tardia; revisar contrato, diagnóstico e cleanup, inclusive API C |
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

1. Fechar organização de registros: campos JSON por nome; política para campos
   novos/ausentes/duplicados; linhas CSV com largura divergente.
2. Fechar perfil sintático e tolerâncias, com rejeição orientada para entradas
   fora do perfil. Separar isso da inferência de dtype.
3. Corrigir preservação de valores: comprimento de strings, limites numéricos,
   exatidão C/Lua; revisar cleanup e falhas de alocação nos caminhos envolvidos.
4. Concluir o mapa da inferência Lua e I/O: `from_dict`, `full`, mapas normal e
   categórico, `explode`, `ifelse` e consumidores com dtype já determinado.
   Os pontos Lua foram localizados, mas ainda não têm auditoria completa neste documento.
5. Implementar as correções discutidas com regressões independentes. Só depois
   integrar `dayfirst`/detecção automática e migrar os componentes datetime.

São blocos para discutir um de cada vez. Não há autorização inferida para
reescrever todos os módulos ou ampliar o perfil JSON para objetos aninhados.
