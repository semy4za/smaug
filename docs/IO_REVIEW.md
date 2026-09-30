# CSV/JSON — decisões, evidência e pendências

[Documentação](README.md) · [Roadmap R1–R4](Roadmap.md#r1)

Consolidado em 2026-09-27 a partir de `320b4bc` e da inspeção de consumidores.
As reproduções completas, referências consultadas e evolução das decisões
estão no [registro de 2026-09-25/26](https://github.com/semy4za/smaug/blob/320b4bcbd5b50df20872668dd36afbe54ca941e2/docs/IO_REVIEW.md).
Os scripts `audit_io*.lua` observam resultados; saída 0 não aprova a semântica.

## Responsabilidades e percurso

| Etapa | Responsável | Implementação |
|---|---|---|
| Converter texto completo em número, validar argumentos e preservar saída | Anel 0 | `smaug_convert` |
| Política de `astype` por elemento | Anel 1 | `smaug_astype` e adaptador Series |
| Tokenizar, validar gramática e inferir/adaptar formato | Anel 3 | `smaug_csv`, `smaug_json`, `smaug_io_internal` |
| Transportar nomes, valores e opções | Anel 3 / fronteira C/Lua | `smaug_column_t`, opções e `io/csv.lua` compartilhado com JSON |
| Espelhar layout/assinaturas e carregar biblioteca compatível | FFI/loader | `ffi_loader.lua` |

O armazenamento de string do core já usa bytes e comprimentos. A perda de NUL
no formato não justifica substituir esse armazenamento. Leitura e escrita
precisam preservar os valores em todo o percurso, inclusive na adaptação Lua.

## Decisões aprovadas, implementação de I/O parcial

As regras normativas estão no [Contrato 9](CONTRACT.md#section-contrato-9-nao-finito-e-valor-ausencia-e-null-mask).

- JSON: associar por nome; unir campos; colunas pela primeira aparição;
  preencher campos ausentes e `null` com NA, inclusive linhas anteriores.
- Preservar strings `""`, `"null"` e `"NA"` como texto JSON.
- Desambiguar nomes repetidos com `.1`, `.2`, etc., continuando até obter nome
  livre, sem perder valores. Chaves repetidas entre objetos identificam a mesma
  coluna; ocorrências repetidas dentro do objeto precisam de colunas distintas
  e associação estável entre registros, mesmo com sufixos já existentes.
- Validar sintaxe JSON e consumir o documento completo: erro com posição e
  motivo, sem DataSet parcial. O perfil é array de objetos com células escalares;
  isso não autoriza ampliar para objetos aninhados.
- Preservar NUL em valores e nomes. JSON usa `\u0000`; NUL literal continua
  inválido. CSV preserva o byte como extensão do dialeto. NUL não equivale a
  vazio, NA ou fim do valor; `a` e `a\0b` são nomes distintos.

## Defeitos reproduzidos

| Caso | Resultado observado na baseline | Local a conferir |
|---|---|---|
| Objetos JSON com chaves reordenadas/novas/ausentes | Valores trocados, campo novo descartado | Inferência/preenchimento por posição em `smaug_json.c` |
| Documento sem fechamento, vírgulas/escape/número inválidos ou sufixo extra | Casos malformados aceitos | Lexer e parser JSON |
| `a\u0000b` JSON / `a\0b` CSV | Texto reduzido a `a` | Comprimentos descartados, `strlen`/`strdup` |
| CSV `123\0abc`, `true\0abc`, `NA\0xyz` | Prefixo vira número, booleano ou NA | `_cstr` e `strcmp` na inferência |
| Marcador configurado `NA\0xyz` | Também casa com `NA` e `NA\0other` | Opções sem comprimento |
| Inteiro `9007199254740993` | Exato no C, arredondado no DataSet Lua | `tonumber` em `table_to_dataset` |
| `INT64_MAX` | Exato no C, chega como `INT64_MIN` no Lua | Mesma ponte numérica |
| Inteiro JSON fora de int64 | Saturação no C | `strtoll` sem verificar `errno` |
| Token `1` + 63 zeros + `e-63` (valor 1) | `1e62` | Corte do token a 63 bytes |
| Slice numérico `123\0abc` | Sucesso com 123 em HEAD | `smaug_parse_i64/f64` |

Reprodução: `luajit scripts/audit_io.lua` (30 casos) e
`luajit scripts/audit_io_values.lua` (23 casos). Registrar a biblioteca usada;
os quatro casos de core diferem entre o HEAD baseline e a implementação R1.
Uma cópia compilada de HEAD reproduziu os achados de I/O nesta revisão.

<a id="core"></a>
## Mecanismo numérico — R1

`astype` usa os parsers `(ptr, len)`; CSV usa `_cstr`; JSON converte seus tokens
diretamente. Todos os consumidores de produção localizados fornecem saída
válida. Não há declaração desses quatro parsers no cdef de produção.

HEAD aceitava apenas 1..63 bytes nos slices e podia aceitar o prefixo anterior
ao NUL. A implementação atual valida o slice completo e não impõe esse limite;
CSV com decimal customizado passou a usar cópia dinâmica acima do buffer
local na revisão de 29/09, sem limite artificial de comprimento. Na
baseline, os quatro parsers podiam escrever por `out=NULL`; os helpers atuais
retornam `SMG_ERR_ARGUMENT` e preservam a saída.

**Implementação R1:** acrescenta rejeição de NUL no slice, saída NULL segura,
consumo integral, locale C, hexadecimal inteiro em i64 e diagnósticos de
overflow/underflow. `make test` passou após a mudança. Ainda não houve nova
cobertura Windows ou sanitizers. Aritmética checked é uma família diferente:
seus helpers permitem saída NULL intencionalmente.

Manter a política de `astype` numérico: texto inconversível→NA e `NOMEM`
propagado. O core decide se a conversão é válida; o leitor decide o dtype do
campo. Subnormais são aceitos, underflow para zero é diagnosticado e tokens
longos não são truncados. Representação fora da faixa continua distinta.

<a id="r1-padrao-c"></a>
### Aplicação de C03/C06 em R1 — 2026-09-28

Probe observacional recompilado com GCC 16.2.1, glibc 2.43, C11,
`-Wall -Wextra -Wpedantic -O2`, sem warnings. Execuções completas com locales
`C` e `pt_BR.utf8`; não é execução de suíte de aceitação nem validação Windows.

```sh
gcc -std=c11 -Wall -Wextra -Wpedantic -O2 -Iinclude scripts/audit_numeric_parse.c src/smaug_convert.c -lm -o /tmp/smaug-r1-review
/tmp/smaug-r1-review --locale C
/tmp/smaug-r1-review --locale pt_BR.utf8
```

| Entrada/condição | Observação na implementação R1 | Consequência |
|---|---|---|
| `1.5` / `1,5` | Antes dependia do locale; o core agora aceita apenas ponto | Locale do processo não pode alterar o resultado do core; leitor adapta separador antes da chamada |
| `0x1p-1074` / `4.9406564584124654e-324` | Ambos produzem o menor subnormal representável | `ERANGE` com resultado não zero não é rejeição |
| Token de 68 bytes representando 1 | Slice e `_cstr` aceitam sem truncar | Comprimento não altera a gramática; alocação longa é recurso separado |
| `123` com NUL seguido de bytes | Slice rejeita; `_cstr` aceita prefixo terminado | `_cstr` não conhece bytes posteriores ao terminador; transporte com NUL exige comprimento |
| NULL de saída nos probes slice i64/f64 | Rejeição sem crash | `_status` retorna `SMG_ERR_ARGUMENT` e não escreve |

Aplicação de R1: saída obrigatória; falha preserva destino. Consumo integral,
ponto decimal independente de locale e ausência de truncamento estão definidos
na gramática aprovada abaixo. Limite de recursos é explícito e não se confunde
com sintaxe inválida. Subnormais não nulos têm sucesso; arredondamento para
zero de texto não zero retorna `SMG_ERR_UNDERFLOW`.

Princípios aprovados em 28/09: leitor responsável pelo formato, core pela
conversão; causa por código e contexto/mensagem externos; falha operacional
não vira NA no astype tolerante. [Contrato](CONTRACT.md#conversao-numerica-responsabilidades).
Os códigos concretos foram adicionados ao status comum e as variantes `_status`
foram implementadas; wrappers 1/0 permanecem por compatibilidade. A migração
não aprova mudanças silenciosas em inferência CSV/JSON. Não mudar
locale global na biblioteca; o probe faz isso somente em seu processo isolado.

<a id="r1-proposta"></a>
### Comparação da gramática e diagnóstico aplicado

Comparação executada em 28/09 com o probe anterior ampliado, locale C,
GCC 16.2.1/glibc 2.43. A gramática de destino foi aprovada em 28/09;
implementação dos helpers e de `astype` concluída; migração dos consumidores,
limites de recursos de I/O e demais assinaturas permanecem pendentes.

| Entrada/regra | Baseline antes de R1 | Contrato aplicado |
|---|---|---|
| `+12`, `-12`, `0012` | i64/f64 aceitam | Manter sinal opcional e zeros iniciais; sem octal implícito |
| `1.5`, `.5`, `1.`, `1e+2` | f64 aceita; i64 rejeita | Manter formas decimais f64, com pelo menos um dígito na mantissa e dígitos obrigatórios após expoente |
| ` 1` / `1 ` | Core rejeita ambos | Eventual trim pertence à política do consumidor |
| `1,5` | Depende de locale | Core usa ponto; leitor adapta separador configurado sem aceitar agrupamento de milhares implicitamente |
| Hexadecimal (`0x10`, `0x1p-1074`) | f64 aceita, i64 rejeita | Forma inteira aprovada em i64/f64; fração e expoente apenas em f64 |
| `nan`, `inf`, `Infinity` | f64 aceita | Manter tokens sem payload, sem distinção ASCII de caixa; sinal opcional; NaN continua valor, não NA |
| `nan(payload)` | f64 aceita neste runtime | Rejeitar payload textual; não garantir preservação de payload/sinal NaN |
| Vazio, apenas sinal, expoente incompleto, sufixo extra, NUL em slice | Core rejeita | Sintaxe inválida; consumir a entrada completa |
| Texto numérico longo | Slice e `_cstr` aceitam sem truncar | Mesma aceitação numérica; limite de recursos separado |

Há cobertura explícita da migração em `test_inbound_conversions`
(`tests/c/test_astype.c`): `0x1A` agora vira 26 tanto em i64 quanto em f64,
com conversão inteira exata e sem passagem por double. A inferência CSV ainda
precisa de verificação dirigida para esse novo alcance.

As rejeições aprovadas de espaço inicial e payload NaN mudam aceitação
existente e têm regressões no core/astype. Não restringir o core à gramática JSON: o leitor
JSON continua responsável por rejeitar formas que seu formato não admite.
Preservar `-0.0` e o arredondamento normal de float64; precisão exata de texto
decimal não é uma exigência geral de f64 como é para i64.

Categorias de diagnóstico implementadas no status comum:

| Categoria | Significado | Consumidor tolerante |
|---|---|---|
| Sucesso | Valor publicado | Usa resultado |
| Argumento inválido | Chamada viola precondição, por exemplo saída obrigatória NULL | Propaga erro de chamada; não produz NA |
| Sintaxe inválida | Texto completo não pertence à gramática | astype texto→número pode produzir NA; leitor decide inferência |
| Fora da faixa | Valor não cabe no destino | Política do consumidor explícita; não saturar silenciosamente |
| Underflow para zero | Texto não zero perde magnitude ao arredondar para zero | `SMG_ERR_UNDERFLOW`; `astype` tolerante produz NA |
| Memória/limite de recursos | Falha operacional, não propriedade numérica do texto | Aborta/propaga; não tenta outro dtype nem produz NA |

`smaug_status_t` agora possui ARGUMENT/NOMEM/OVERFLOW/SYNTAX/UNDERFLOW.
Os wrappers 1/0 continuam disponíveis; consumidores que precisam da causa
usam as quatro variantes `_status`, evitando inverter condicionais existentes.

`smaug_str_to_i64/f64` convertem falhas de elemento em célula nula;
`SMG_ERR_NOMEM` e erros de chamada abortam a construção e não viram NA.
CSV usa variantes de status desde 29/09 e propaga falhas operacionais na
inferência e no preenchimento. Slices longos alocam a cópia; `_cstr` não copia
o token, mas a criação de locale também pode falhar. Decimal customizado
pertence ao leitor e pode exigir outra cópia dinâmica.
JSON ainda chama libc diretamente e corta tokens; sua migração exige também
validação de gramática/consumo do documento em R3. Conversor comum não substitui
o lexer do formato. Formatação numérica usa locale C explícito desde a revisão de 29/09; o
roundtrip foi verificado em FE_TONEAREST. Isso não corrige o lexer JSON.

<a id="r1-gramatica"></a>
### Gramática explícita — aprovada em 2026-09-28

Gramática aprovada em 28/09, incluindo hexadecimal inteiro nos dois destinos
e fração/expoente exclusivos de f64. É contrato de destino, não descrição de
implementação concluída nos helpers e em `astype`. Migração de CSV/JSON,
políticas de faixa nos leitores e demais assinaturas permanecem pendentes.

Notação: `?` significa opcional, `*` zero ou mais e `+` um ou mais;
`|` separa alternativas. Todos os caracteres são ASCII. Apenas letras dos
tokens e prefixos são insensíveis a caixa; não há normalização Unicode.

```text
sign       = "+" | "-"
digit      = "0" ... "9"
hexdigit   = digit | "a" ... "f" | "A" ... "F"
dec_int    = digit+
hex_int    = ("0x" | "0X") hexdigit+
dec_mant   = digit+ ("." digit*)? | "." digit+
dec_exp    = ("e" | "E") sign? digit+
hex_mant   = hexdigit+ ("." hexdigit*)? | "." hexdigit+
bin_exp    = ("p" | "P") sign? digit+
hex_float  = ("0x" | "0X") hex_mant bin_exp?
special    = "nan" | "inf" | "infinity"  [caixa ASCII indiferente]
i64        = sign? (dec_int | hex_int)
f64        = sign? (dec_mant dec_exp? | hex_float | special)
```

Para f64, expoente hexadecimal é binário e seus dígitos são decimais:
`0x1.8p+1` vale 3. Expoente omitido equivale a zero, inclusive com fração
(`0x1.8` vale 1,5). `e` é dígito hexadecimal, nunca expoente nessa forma:
`0x1e2` vale 482. Essa escolha preserva formas aceitas atualmente pela libc,
mas passa a ser uma regra própria, testável, do Smaug.

Regras complementares:

- Consumir todos os bytes: rejeitar espaços, tabulações e quebras de linha
  em qualquer posição, NUL dentro do slice, sufixos `f`/`L`, separadores de
  milhares, `_`, vírgula, dígitos Unicode e payload `nan(...)`.
- Ponto é o único separador decimal no core, independentemente de locale.
  Leitores tratam suas opções antes da chamada, sem alterar o locale global.
- Zeros iniciais não indicam octal: `012` vale 12. Não aceitar `0o` nem `0b`.
- Pelo menos um dígito na mantissa e em todo expoente presente: rejeitar
  `.`, `0x`, `0x.p1`, `1e`, `0x1p+` e sinal isolado. Não converter prefixos.
- NaN e infinitos são valores, não NA. Aceitar sinal em tokens especiais;
  não garantir sinal/payload de NaN. Preservar zero negativo em f64.
- Separar validade lexical de representabilidade: um inteiro enorme pode
  ser sintaticamente válido e exceder int64; `1e400` não é sintaxe inválida.
  Conversão i64 é exata; f64 admite arredondamento. Subnormal representável
  tem sucesso; arredondamento para zero retorna `SMG_ERR_UNDERFLOW`. O modo de
  arredondamento da libc continua fora do contrato decimal exato.
- Slice e C-string usam a mesma gramática; o terminador da C-string delimita
  sua entrada. Limites de recursos não redefinem a sintaxe nem permitem corte.
- Essa gramática não amplia a sintaxe dos formatos: um token hexadecimal
  aceito pelo core continua inválido como número JSON.

Casos mínimos para a futura suíte de contrato:

| Família | Aceitar | Rejeitar |
|---|---|---|
| Inteiro decimal | `0`, `-0`, `+12`, `0012` | `1.0`, `1e0`, `12x` |
| Inteiro hexadecimal | `0x0`, `+0X1A`, `-0x1a` | `0x1.0`, `0x1p0`, `0x` |
| Float decimal | `1`, `.5`, `1.`, `1.e2`, `-0.0` | `.`, `1e`, `1e+`, `1,5` |
| Float hexadecimal | `0x10`, `-0X1A`, `0x.8`, `0x1.p2`, `0x1e2` | `0x`, `0xp1`, `0x1p`, `0x1p1.5` |
| Especiais f64 | `NaN`, `+INF`, `-Infinity` | `nan(x)`, `infinite`, `inf0` |
| Bytes e consumo | token completo sem espaços | ` 1`, `1 `, `1\t`, `1\0x`, vazio |

Acrescentar fronteiras representáveis, equivalência slice/C-string, locale e
preservação da saída em falha após fechar a política de diagnóstico/faixa.
Essa tabela é especificação de testes futuros; não é relatório de execução.

### Verificação dirigida de R1 — 2026-09-29

O [checkpoint](Roadmap.md#checkpoint) registra comandos, ferramentas e
limitações desta execução. `scripts/audit_numeric_regressions.py` recompila
baselines e seis mutantes em cópias temporárias, exige falha pelo motivo
esperado e não considera erro de build como detecção.

| Obrigação | Caso discriminante / destino do cenário anterior |
|---|---|
| Consumir a gramática inteira | Prefixo decimal/hex fora da faixa seguido de sufixo inválido retorna SYNTAX; saída intacta |
| Não saturar overflow silenciosamente | `±1e400` e `±0x1p1024` rejeitados nos quatro modos; DBL_MAX exato aceito |
| Preservar magnitude representável | Menor subnormal e fronteira DBL_MIN aceitos; arredondamento de não zero para zero tem UNDERFLOW |
| Não ocultar OOM no astype/CSV | Falha real em token longo/locale; CSV falha tanto na inferência quanto no preenchimento |
| Comprimento não redefine tipo | Teste antigo de CSV ≥64 bytes→string substituído por token longo com valor exato 1,5 e máscara válida |
| Cleanup após realloc parcial | Caso de 100 linhas agora enumera todos os pontos; teto antigo de 64 não atingia o crescimento do vetor |
| Não entregar tabela parcial | Asserção tautológica de CSV substituída por status/shape/dtypes/valores/máscaras e recuperação; string longa força falha no setter |

Seis mutantes detectados na rodada final. O último cenário foi fortalecido
após um mutante sobreviver com strings curtas. Valgrind aprovou allocfail;
arredondamento é verificado nativamente por divergência observada sob Valgrind.
Isso não fecha políticas de inferência, transporte NUL ou lexer JSON, nem
substitui a reconstrução restante da suíte. O seguimento abaixo trata dos formatadores.

### Seguimento — formatação e locale, 2026-09-29

O parser já usava locale C, enquanto o formatter finito chamava `snprintf`
sob o locale externo: `1.5` podia virar `1,5`, incompatível com o core e JSON.
Também havia retornos positivos para buffers truncados, embora o caminho de
NaN/inf retornasse zero. A revisão torna o contrato uniforme: buffer completo
com NUL ou zero sem alterar o destino; 32 bytes bastam para i64/float64.

- POSIX: `newlocale`/`uselocale` selecionam C apenas na thread durante a
  formatação; o objeto de locale anterior é restaurado antes de liberar o novo.
  O caller mantém válido esse objeto durante a chamada. O ramo de restauração
  só pode falhar se esse contrato de validade não for respeitado; nesse caso
  não se libera o locale ainda ativo. Não há chamada a `setlocale` no core.
  A seleção por thread foi conferida também no
  [fonte de uselocale da glibc](https://raw.githubusercontent.com/bminor/glibc/master/locale/uselocale.c);
  a execução desta etapa não certifica outras libcs.
- Windows: `_snprintf_l` recebe o locale C explicitamente; retorno e terminação
  são conferidos antes de publicar. Referência da API:
  [Microsoft CRT](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/snprintf-snprintf-snprintf-l-snwprintf-snwprintf-l?view=msvc-170).
  Esse ramo permanece sem execução Windows nesta etapa.
- Astype, CSV e JSON conferem zero. Inclui a conversão de números para string
  durante inferência de coluna mista JSON; falha não publica tabela parcial.
  Não foi alterada a gramática ou associação dos registros JSON.
- CSV adapta ponto ao separador decimal configurado na camada de formato;
  JSON sempre emite ponto. Naquela etapa, a leitura JSON ainda usava conversão
  própria; foi migrada no seguimento de representação numérica registrado abaixo.

Regressões: bytes intactos em capacidade insuficiente, espaço exato com NUL,
NULL, limites int64, zero negativo, subnormais e roundtrip f64 em FE_TONEAREST.
Locales C, global pt_BR.utf8 e locale próprio de thread foram exercitados no
Linux. Os testes verificam restauração do locale e reportam skip se o locale
de vírgula não estiver instalado. CSV/JSON têm expectativas literais de saída.
Injeção de falha em `newlocale` e na ativação por `uselocale` verifica
preservação/cleanup; astype e writers falham inclusive depois de processar o
primeiro valor. Nove mutantes compiláveis detectados na campanha cumulativa,
com três novos para locale externo, sucesso truncado e falha ignorada no astype.
`test_allocfail` passou sob Valgrind; testes C/Lua, build otimizada com Werror,
guard de estilo e diff aprovados. Limitações gerais mantidas no checkpoint.

<a id="transporte"></a>
## Transporte e ABI — R2

Desenho aprovado: consultar `uint32_t smaug_abi_version(void)` logo após
carregar a biblioteca e antes de acessar structs. Comparar por igualdade com
a versão esperada pelo cdef; símbolo ausente ou versão diferente gera erro
orientado. Continuar busca apenas quando o candidato não puder ser carregado;
se carregar e for incompatível, interromper. Não prometer proteção a frontend
antigo que não faz a consulta. Versão ABI é distinta de versão de produto/hash.

Recorte implementado em 29/09: `name_len` após `name` em `smaug_column_t`,
primeira ABI identificada 1; metadata separada. Todos os produtores fornecem
comprimento real, sem fallback para strlen. Nome vazio usa ponteiro válido e
comprimento zero; writers rejeitam ponteiro de nome NULL.

Marcadores CSV: `na_lengths` após `na_values`, ambos emprestados com `na_count`
entradas e ancorados pelo Lua até a chamada terminar. Comprimentos são
obrigatórios para lista não vazia; marcadores NULL são rejeitados. `na_values`
NULL mantém padrões internos; lista explícita de contagem zero mantém
`na_values={}`. Comparação por bytes/comprimento, inclusive vazio ou NUL.
Layout C, cdef e produtores migrados juntos; não é compatível com o layout antigo.

Seguimento de 29/09: `io/csv.lua` mantém cdata int64 na leitura e usa `get_raw`
na escrita. A adaptação para DataSet é protegida e libera a tabela C tanto no
sucesso quanto na exceção. Getters públicos e políticas de inferência fora do
I/O mantêm seus contratos.

Aceitação: roundtrip com duas colunas e nomes `a`/`a\0b`; tamanho/offsets C/FFI;
biblioteca sem símbolo, incompatível e correta; candidato local incompatível
com alternativa instalada; lifetime de buffers e testes nas duas plataformas.

<a id="inferencia-lua"></a>
## Inferência Lua — R4

| Entrada | Comportamento inspecionado |
|---|---|
| `Series` / `from_table` | Inferência por famílias; numérico promove; vazio/tudo NA→string |
| `from_dict` | Regra local de precedência antes de construir com dtype fixo |
| `full` | Regra escalar própria; não reconhece cdata quando dtype é omitido |
| `map` | Primeiro retorno não-NA fixa dtype; tudo NA exige dtype |
| `CategoricalSeries:map` | Primeiro retorno fixa dtype; tudo NA→string |
| `explode` | Primeiro não-NA fixa dtype; reconstrução passa por `get` |
| `ifelse` / `where` / `mask` | Dtype da Series e broadcast por outro caminho de validação |

É mapa de leitura, não aprovação nem certificação. Conferir cdata, precisão,
ordem dos valores, misturas e tudo NA. `map` documenta primeiro retorno:
uniformizar com inferência de coluna inteira seria mudança de contrato.
Conversão categórica numérica usa `tonumber` Lua e requer revisão separada.

<a id="r3-representacao-proposta"></a>
## Representação numérica JSON — discussão de 2026-09-29

**Estado: política aprovada pelo mantenedor em 2026-09-29**, após a discussão
dos exemplos e referências. Contrato em CONTRACT: int64 estrito, float64 com
subnormais e promoção inteira exata; diagnóstico nas falhas. A tabela abaixo
registra o comportamento anterior à implementação, não o comportamento atual.

Probe executável, observacional (saída zero não aprova a semântica):

```sh
gcc -std=c11 -O2 -Wall -Wextra -Werror -Iinclude scripts/audit_json_numeric_policy.c src/*.c -lm -o /tmp/smaug-json-policy
/tmp/smaug-json-policy C
/tmp/smaug-json-policy pt_BR.utf8
```

Evidência histórica anterior à correção, compilada com GCC 16.2.1. SHA-256 de `smaug_json.c`:
`d29719233559ac746ed3e31a3827f13e3c49887936ddc4ba4072ede98d48aad8`.
A observação usa a API C, sem introduzir a perda adicional da ponte Lua/R2.

| Entrada na coluna v | Observação no locale C | Classificação |
|---|---|---|
| `9007199254740993` sozinho | int64 exato | Caminho que já preserva o inteiro |
| `9223372036854775809` sozinho | int64 com valor `9223372036854775807` | Defeito: errno de strtoll ignorado; política substituta pendente |
| `42` e `1.5` | float64, ambos exatos | Promoção sem perda neste caso |
| `9007199254740993` e `1.5` | primeiro valor vira `9007199254740992` | Cast int64→double na construção da coluna; escolher política |
| `0.1` | float64 mostrado como `0.10000000000000001` com 17 dígitos | Arredondamento de decimal para binário; não confundir com identidade inteira |
| `5e-324` | erro genérico; core f64 aceita o menor subnormal | Integração incorreta do leitor, não ausência de magnitude representável |
| `1e-400` / `1e400` | erro genérico; core distingue UNDERFLOW/OVERFLOW | Diagnóstico disponível; resposta do leitor ainda pendente |
| `1` + 63 zeros + `e-63` | `1e62`, embora o valor seja 1 | Defeito de truncamento; comprimento não define a faixa |
| `01` | aceito como 1 | Sintaxe JSON inválida, distinta da sintaxe de inteiro do core/CSV |
| string JSON `"9223372036854775809"` | string exata | Texto explícito é suportado hoje |

Sob pt_BR.utf8, o leitor rejeita `1.5`/`0.1`; o core já converte com ponto fixo.
`9223372036854775808` também saturava no leitor observado, embora seja exatamente
representável em binary64 (2^63). O vizinho 2^63+1 não é. Portanto, testar apenas
se o inteiro excede 2^53 é conservador, mas não é um teste completo de exatidão.

### Referências e o alcance de cada uma

- [C11 N1570, 7.22.1.4](https://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf):
  strtoll retorna um extremo e sinaliza ERANGE fora de faixa. O extremo não
  deve virar resultado válido só porque o token foi consumido.
- [CERT ERR34-C](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/rules/error-handling-err/err34-c/):
  detectar e tratar falhas de conversão. Não escolhe dtype de uma coluna JSON.
- [JPL Power of Ten, regra 7](https://spinroot.com/gerard/pdf/P10.pdf):
  validar argumentos e conferir retornos. No Smaug, aplica-se à propagação de
  status/cleanup; não exige bigint, float ou rejeição como política de produto.
- [RFC 8259, seção 6](https://www.rfc-editor.org/rfc/rfc8259.html#section-6):
  define a gramática e permite limites de faixa/precisão da implementação.
  `1e400` tem sintaxe válida; `01` não. O intervalo inteiro interoperável de
  binary64 não significa que todo inteiro acima dele seja inexato.
- [Python json](https://docs.python.org/3/library/json.html#json.load):
  parse_int/parse_float recebem o texto do token e permitem representação
  configurável. É precedente de separação entre parsing e representação,
  não aprovação de novos hooks ou tipos para a API Smaug.

### Alternativas consideradas

| Política | Resultado quando não cabe exatamente no tipo escolhido | Custo/efeito |
|---|---|---|
| Rejeitar com diagnóstico | Nenhuma tabela parcial | Previsível; usuário precisa escolher outra representação |
| Promover automaticamente para float | Número aproximado quando necessário | Integra cálculos, mas pode alterar identificadores e valores inteiros |
| Preservar token como string | Dígitos e expoente originais preservados | Coluna deixa de ser numérica; muda a escrita JSON e exige política para a coluna inteira |
| Novo tipo bigint/decimal | Representação numérica mais ampla/exata | Novo escopo de armazenamento, operações, FFI e serialização |

Decisão aprovada: inteiros em int64 enquanto couberem; promoção de
coluna mista para f64 apenas se os inteiros forem preservados; decimal f64 com
arredondamento usual; preservar subnormais não zero. Nos demais casos,
diagnóstico por padrão. Uma opção explícita de texto/representação aproximada
ainda precisaria de decisão e desenho de API. Não implementar uma nova opção como
se já estivesse disponível. Se escolhermos texto, guardar o token antes de
qualquer conversão — formatar um double arredondado não recupera os dígitos.

### Implementação e verificação da decisão

O lexer numérico agora valida a gramática JSON e entrega o slice inteiro ao
core; não usa strtoll/strtod diretamente. O teste de exatidão da promoção conta
dígitos significativos na base de FLT_RADIX, sem converter double de volta para
int64 (o cast seria inválido quando INT64_MAX arredonda para 2^63). A inferência
termina antes dessa validação, respeitando o dtype final string quando aplicável.

Regressões verificam limites int64, subnormais, sinal de zero, underflow/overflow,
token longo, precedência de sintaxe, exatidão nos dois sentidos de ordem das
linhas, locale com vírgula e falha operacional sem resultado parcial/recuperação.
`make test`, `make test-lua`, build I/O otimizado com warnings como erro e guard
passaram. I/O sob Valgrind: zero erros e zero blocos pendentes. A campanha de
`scripts/audit_numeric_regressions.py` detectou 13 mutantes compiláveis, incluindo
quatro novos de JSON. Contagens e limitações ficam no checkpoint do Roadmap.

### Associação JSON por nome — seguimento de 2026-09-29

Implementada união de campos pela primeira aparição, com NA retroativo e
associação por nome original/ordinal da ocorrência dentro de cada objeto.
Nomes publicados usam o primeiro sufixo livre; chaves literais com sufixos não
se confundem com nomes gerados. A inferência e a validação de promoção inteira
usam os mesmos índices de coluna, evitando misturar números de campos distintos.
Objetos vazios mantêm a cardinalidade na tabela C, sem depender de malloc(0).

Regressões C verificam nomes, dtypes, valores e máscaras em linhas reordenadas,
campos tardios, null, strings vazias/marcadores e colisões nos dois sentidos.
Lua verifica o percurso C/FFI/DataSet e roundtrip dos nomes publicados. A
varredura OOM usa a contagem observada da execução de sucesso, exige uma falha
real por índice e rejeita resultados parciais; depois verifica recuperação.
Também foi corrigida a propagação do setter de string na construção da tabela.
Três mutantes novos comprovam detecção de associação posicional, fusão de
ocorrências repetidas e schema limitado à primeira linha.

Na etapa inicial, nomes ainda usavam C-string. O seguimento de transporte abaixo
migrou a associação para bytes/comprimentos.
O resolvedor reserva descritores até a soma verificada dos campos e usa buscas
lineares; não há promessa nova de desempenho para documentos muito largos.
Validação completa de strings, limites de recursos e migração de ABI continuam
abertos. Evidência executada e contagens ficam no checkpoint do Roadmap.

### Transporte de NUL e ABI 1 — seguimento de 2026-09-29

JSON guarda comprimento de chave e valor após decodificar escapes; associação,
sufixos e escrita preservam bytes. NUL literal/controle não escapado é rejeitado.
CSV tokeniza em buffers com comprimento; inferência usa slices completos, então
`123\0x`, `true\0x` e `NA\0x` não são prefixos numéricos/bool/NA. Leitores,
writers em memória/arquivo e ponte Lua transportam os tamanhos. O setter de
string no writer Lua é conferido e o buffer parcial tem ownership antes da cópia.

`scripts/audit_io_abi.py` compila comparação de sizeof/offsetof C↔FFI, carrega
bibliotecas reais com símbolo ausente/versão divergente e verifica que não há
fallback mesmo com candidato seguinte válido. Também verifica fallback após
arquivo não carregável e injeta falha no setter Lua, exigindo cleanup e recuperação.
A campanha numérica inclui mutantes de truncamento de valores/nomes e de
comprimento do marcador. Casos C/Lua verificam bytes, máscaras, nomes vazios,
colisões NUL, roundtrip e diagnósticos. Evidências no checkpoint.

O seguimento abaixo resolve int64 e cleanup da adaptação de leitura. Metadata,
UTF-8 completo e limites de recursos permanecem fora desse recorte. Windows/sanitizers não foram executados nesta migração.

### Ponte int64 e exceções Lua — seguimento de 2026-09-29

Leitura e escrita CSV/JSON mantêm cdata int64, sem passagem por number. Testes
usam literais cdata e textos independentes para ±(2^53+1), INT64_MAX, INT64_MIN,
zero e NA: verificam leitura, escrita isolada e roundtrips. A coluna auxiliar
no CSV preserva a linha NA sem depender da política de linhas vazias.

A tabela C é liberada após adaptação com sucesso ou exceção. O writer registra
ownership da série inteira antes do laço e confere setters. O probe ABI injeta
falha no setter int64 e na segunda construção de coluna, exige uma liberação
do recurso parcial e verifica recuperação. O teste antigo de falha em `get`
foi migrado para interceptar `get_raw` também e comprovar a injeção; ausência
de crash deixou de ser apresentada como prova de cleanup.

`scripts/audit_io_abi.py` executa baseline e três mutantes em cópias temporárias
do frontend: reader via number, writer via get e ausência de liberação da tabela.
Todos precisam falhar pelo diagnóstico esperado, não por erro de sintaxe Lua.
Isso complementa os 20 mutantes C da campanha anterior, sem equiparar as contagens
nem declarar certificação completa da memória Lua. Windows permanece pendente.

### Leitura estrita — proposta e probe de 2026-09-29

**Estado histórico da proposta:** as escolhas de formato foram apresentadas
antes da comparação com TensorFlow abaixo. A orientação estrita foi aprovada
nesse seguimento; BOM e compatibilidade CSV continuam pendentes. A implementação
do UTF-8 JSON foi concluída no seguimento abaixo; BOM e compatibilidade CSV
continuam pendentes. Referências verificadas: [RFC 8259, §§8–10](https://www.rfc-editor.org/rfc/rfc8259.html#section-8),
[RFC 3629, §4](https://www.rfc-editor.org/rfc/rfc3629.html#section-4) e
[RFC 4180, §2](https://www.rfc-editor.org/rfc/rfc4180.html#section-2).
JSON interoperável usa UTF-8; o reader pode ignorar BOM, mas o writer não deve
emiti-lo. Surrogates isolados escapados aparecem na gramática JSON, porém têm
interoperabilidade problemática; a restrição do Smaug precisa ser explícita.
CSV tem múltiplos dialetos: a RFC descreve largura uniforme, aspas duplas e CRLF;
as extensões Smaug de LF, bytes crus/NUL e linhas vazias não são conformidade
integral com a RFC.

Probe independente da suíte de aceitação:

```sh
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror -Iinclude scripts/audit_io_strict_policy.c src/*.c -lm -o /tmp/smaug-strict-probe
/tmp/smaug-strict-probe
```

Observações em 15 cenários (14 leituras e uma escrita), sem alterar os parsers:

| Caso | Comportamento observado |
|---|---|
| JSON: byte de continuação isolado, NUL overlong, surrogate codificado em UTF-8, acima de U+10FFFF | Aceitos pelo reader |
| JSON writer recebe byte 0x80 via coluna string | Emite JSON com UTF-8 inválido |
| JSON com BOM inicial | Rejeitado no byte 0 |
| JSON surrogate isolado escapado | Rejeitado com motivo genérico |
| CSV linha curta | Aceita; comportamento coberto por test_csv_short_row |
| CSV linha longa | Aceita, descartando campo excedente na construção |
| CSV aspas não fechadas | Aceitas |
| CSV texto após aspas fechadas | Vira uma linha adicional |
| CSV aspas em campo sem aspas externas | Aceitas como texto |
| CSV byte 0x80, BOM inicial e CR isolado | Aceitos; BOM permanece no nome |

SHA-256 observados: JSON `c19e4491ca75c0ee22391e4e2a20bf44f82babcf7546631d4a08ebbd7de9067a`;
CSV `6a23d4befe55a8b1e57d1ae60fcb5b97a814419d41bf4ef46d1646034d8f4feb`.
Saída zero do probe só significa observação concluída, não aprovação dessas regras.

Proposta JSON: validar nomes/valores UTF-8 no reader e writer, rejeitar sequências
inválidas/surrogates isolados, ignorar um único BOM apenas no byte 0 da leitura,
nunca emitir BOM. U+FEFF dentro da string permanece conteúdo. NUL escapado segue
válido; não normalizar Unicode nem substituir silenciosamente bytes inválidos.

Proposta CSV: manter bytes crus/NUL, LF/CRLF e linhas vazias ignoradas fora de
aspas; rejeitar aspas malformadas e largura diferente da primeira linha/header.
Alternativa oferecida: manter preenchimento de linhas curtas com NA e rejeitar
apenas excedentes. Rejeitar curtas muda uma expectativa já existente, então o
teste só deve ser migrado após a decisão. CSV BOM e CR isolado devem ter regra
explícita ao consolidar o dialeto; não mudar por analogia ao JSON.

<a id="tensorflow-referencia"></a>
### TensorFlow como referência comparativa — 2026-09-29

Referência comparativa aprovada pelo mantenedor em 2026-09-29, sem adoção
automática de defaults ou dependência de runtime. A separação de erros e a
orientação estrita estão registradas no [contrato](CONTRACT.md#io-erros-estrutura-ausencia-codificacao).
Documentação oficial consultada identifica Python API v2.16.1; não é afirmação
sobre a versão mais recente nem resultado de execução local do TensorFlow.

- [`tf.io.decode_csv`](https://www.tensorflow.org/api_docs/python/tf/io/decode_csv)
  define dtype/default por coluna, colunas obrigatórias e tratamento configurável
  de aspas. Aceita espaços periféricos em campos numéricos, enquanto o core Smaug
  mantém sua gramática própria. `select_cols` é projeção explícita; não justifica
  descartar excedentes silenciosamente quando todas as colunas são solicitadas.
- No [kernel consultado no repositório Google/Android](https://android.googlesource.com/platform/external/tensorflow.git/+/refs/heads/android14-d2-release/tensorflow/core/kernels/decode_csv_op.cc),
  sem projeção, a quantidade extraída precisa coincidir com a quantidade de tipos.
  Só depois cada campo vazio/NA usa o default ou gera erro se obrigatório.
  Portanto `1,` pode usar default para o segundo campo; `1` tem largura incorreta
  para duas colunas. Aspas malformadas também são diagnosticadas quando habilitadas.
  Esse fonte é o snapshot Android indicado no link, não o tag v2.16.1; o tag
  upstream não ficou acessível na ferramenta de consulta. Não declarar paridade
  entre versões sem executar um corpus na versão alvo.
- [`tf.strings.unicode_decode`](https://www.tensorflow.org/api_docs/python/tf/strings/unicode_decode)
  separa strict (erro), replace (substituição) e ignore (descarte). O default
  documentado é replace; copiá-lo conflitaria com a preservação sem perda
  silenciosa do Smaug. Para leitura JSON estrita, a recomendação é strict.
- O [guia Unicode](https://www.tensorflow.org/text/guide/unicode) distingue bytes,
  codificação e codepoints. Isso apoia manter bytes no core/CSV e aplicar as
  regras de texto na operação/formato apropriados, sem impor UTF-8 a toda Series.

As referências já resolvem a gramática UTF-8, restrições de escapes JSON e
estrutura básica das aspas CSV. A validação UTF-8 JSON e o dialeto estrito
escolhido estão implementados; resta apenas decidir eventual modo tolerante.
C11,
CERT e JPL orientam implementação/erros, mas não escolhem esse dialeto.

Orientação aprovada: separar erro estrutural (largura/aspas), ausência em campo
existente e erro de codificação. Na leitura estrita, rejeitar estrutura inválida
e UTF-8 inválido no JSON; aplicar NA/default apenas conforme a API do Smaug em
campos válidos. O CSV estrito exige largura uniforme, separa campo vazio de
campo ausente, aceita LF/CRLF, rejeita CR isolado e remove um BOM inicial.

### Implementação UTF-8 JSON — seguimento de 2026-09-29

O reader valida cada sequência literal antes de copiá-la e mantém a decodificação
de escapes `\\uXXXX`, incluindo pares surrogate válidos. O writer valida nomes e
valores string antes de reservar o buffer de saída. O validador aplica os limites
RFC 3629, rejeitando continuação isolada, sobrelonga, surrogate codificada,
sequência truncada e codepoint acima de U+10FFFF. O byte da falha aparece no
diagnóstico; não há substituição, descarte ou tabela/saída parcial.

Os testes C cobrem as fronteiras de 1–4 bytes, escapes, truncamento, nomes,
valores, NUL e crescimento de buffer; Lua cobre erro de leitura/escrita e
roundtrip de U+10FFFF. A campanha adicionou cinco mutantes de UTF-8 e seis do
dialeto CSV, detectando todos; são 31 mutantes C no total. O CSV agora cobre
BOM, LF/CRLF, CR isolado, aspas malformadas e largura exata; o core continua
byte-oriented por contrato.

## Políticas abertas e evidência exigida

A política numérica JSON e os zeros iniciais foram resolvidos acima. R3 ainda
precisa fechar schema explícito, eventual modo tolerante e os limites restantes
registrados acima. Associação por nome, transporte de NUL, validação UTF-8 JSON
e dialeto CSV estrito foram implementados nos seguimentos acima.
As referências externas do registro histórico informam a discussão; não
substituem a escolha do Smaug nem impõem dependências de runtime.

Para cada correção, verificar valor/status/máscara/estado, saída em falha,
cleanup e mutações. O probe `audit_numeric_parse.c` rodou 28 cenários normais
sob Valgrind na auditoria anterior, sem erro de memória reportado; a semântica
continuava defeituosa. ASan/UBSan não linkaram naquele ambiente. Cobertura
histórica e o teste `|| 1` de allocfail não comprovam a ausência desses defeitos.

### Escrita em arquivo — retomada de 2026-09-29

`smaug_write_csv` e `smaug_write_json` ignoravam o retorno de `fclose`.
Uma escrita pequena em `/dev/full` cabia no buffer de stdio: `fwrite`
retornava o comprimento completo, mas o fechamento falhava e a API retornava
sucesso. A regressão Linux reproduziu duas falhas antes da correção.
Os writers agora verificam escrita e fechamento, liberam o buffer e retornam
-1 em qualquer uma dessas falhas; caminho NULL também retorna -1.
A assinatura não mudou. O arquivo pode estar parcialmente gravado em erro;
não há promessa de escrita atômica. Diagnóstico detalhado e erros dos readers
em arquivo continuam pendentes.

### Schema explícito — direção aprovada e detalhes em proposta

O mantenedor aprovou em 2026-09-29 o desenho de schema reutilizável pelo Smaug,
com a primeira implementação aplicada ao CSV/JSON. O alcance da decisão está
no [contrato](CONTRACT.md#schema-reutilizavel); `.smg` e Models continuam futuros.
A descrição de dados deve ser independente de opções de leitura de um formato.

Referências comparativas do desenho: [`tf.io.decode_csv`](https://www.tensorflow.org/api_docs/python/tf/io/decode_csv)
separa tipos por coluna e campos obrigatórios/defaults;
[`tf.io.FixedLenFeature`](https://www.tensorflow.org/api_docs/python/tf/io/FixedLenFeature)
descreve tipo, shape e default para ausência;
[Arrow Schema](https://arrow.apache.org/docs/format/Columnar.html#schema-message)
descreve campos ordenados, nomes, tipos, nulidade e metadata, separados dos
buffers. Isso fundamenta a separação proposta, sem adotar APIs, formatos binários
ou dependências dessas bibliotecas. Shape e metadata não são requisitos
implementados por esta decisão.

A API atual infere tipos; schema não está implementado. Detalhes ainda propostos:
selecionar colunas por posição (sem ambiguidade para nomes repetidos ou NUL),
permitir tipo explícito por coluna e inferir as demais. Aplicar o tipo durante
a leitura do token original: converter depois da inferência perderia, por
exemplo, zeros iniciais em uma coluna CSV declarada string.

Tipos iniciais propostos: bool, int64, float64 e string. Ausência válida mantém
NA; token incompatível com tipo explícito aborta com linha/coluna, sem tabela
parcial. Gramáticas e preservação numérica seguem os contratos existentes.
JSON mantém distinção entre string, número e booleano; schema não autoriza
coerção de string JSON para número. Datas exigem desenho próprio.

A opção tolerante, se adotada, deve limitar-se a falhas de conversão do valor.
Estrutura inválida, UTF-8 JSON inválido e falhas operacionais continuam erros.
Esses detalhes permanecem em proposta; a aprovação conceitual acima não fecha
a política de conversão nem a assinatura pública.

<a id="schema-api-proposta"></a>
### Schema reutilizável — desenho da primeira API

**Estado:** desenho aprovado pelo mantenedor no seguimento, com implementação
C/Lua concluída e verificação registrada abaixo. A descrição a seguir preserva
a motivação do desenho; contrato vigente em CONTRACT e assinaturas em API Reference.

#### Descrição dos dados e recorte inicial

O schema é uma sequência ordenada de campos com nome em bytes/comprimento,
tipo explícito e `nullable` obrigatório. Não contém separador, marcadores NA,
seletores de entrada, defaults ou modo tolerante. A descrição é independente
de formato e não depende de `.smg`, Models ou runtime externo.

Para reduzir ambiguidades, esta proposta refina a ideia inicial de overrides
parciais: começar com schema **completo**, que determina todas as colunas e sua
ordem. Sem schema, preservar a inferência atual. Overrides parciais podem ser
adicionados depois como configuração de importação que produz um schema
resolvido; `auto` não seria um tipo armazenado no schema dos dados.

Tipos da primeira implementação: bool, int64, float64 e string. Não expor
novos tipos que os leitores ainda não sabem construir. Datas e categorical
precisam de representação e regras próprias. Nomes vazios e com NUL continuam
válidos por comprimento; nomes duplicados no schema são rejeitados nesta
primeira interface para permitir identificação inequívoca no DataSet.

`nullable=false` rejeita ausência durante a importação; `nullable=true` permite
NA, mas não transforma conversão inválida em ausência. Esta validação é da
operação de leitura. Propagação de constraints por mutações, joins e demais
operações do DataSet não é implementada implicitamente; o descritor reutilizável
não deve ser publicado como garantia permanente de um DataSet mutável.

#### Exemplo Lua

```lua
local smaug = require("smaug")

local schema = smaug.Schema({
    { name = "codigo", dtype = "string", nullable = false },
    { name = "quantidade", dtype = "int64", nullable = true },
})

local csv_dataset = smaug.read_csv_mem("codigo,quantidade\n00123,\n", {
    schema = schema,
})
local json_dataset = smaug.read_json_mem(
    '[{"quantidade":null,"codigo":"00123"}]', { schema = schema }
)
```

Ambas as leituras produzem `codigo="00123"` e `quantidade=NA`, nessa ordem.
O construtor copia/valida a sequência de campos; a tabela original pode mudar
sem alterar o schema. Sequências Lua com buracos e propriedades desconhecidas
são erros. O objeto não oferece mutação dos campos na primeira versão.

#### Associação de entrada e saída

| Entrada | Regra proposta com schema completo |
|---|---|
| CSV com header | Associar por nome original; permitir reordenação; exigir todos os campos, sem extras ou nomes duplicados |
| CSV sem header | Associar por posição e usar nomes/ordem do schema; exigir largura exata |
| JSON | Associar por nome original em cada objeto, independente da ordem das chaves; rejeitar extras e chaves duplicadas |
| Campo JSON ausente ou null | Produzir NA se nullable; erro caso contrário |
| CSV header sem linhas de dados | Produzir colunas tipadas vazias se o header corresponder ao schema |
| JSON `[]` | Produzir colunas tipadas vazias na ordem do schema |
| Coluna inteiramente NA | Manter o tipo declarado, sem fallback para string |

Esta associação por nome refina a sugestão inicial exclusivamente posicional:
JSON já permite objetos reordenados. Posição fica como associação natural para
CSV sem header; seletores/renomeação e schema parcial ficam fora do primeiro
recorte. Sem schema, a desambiguação atual de nomes continua inalterada.
CSV malformado continua erro estrutural, inclusive linha curta: nulidade não
preenche um campo estruturalmente ausente. Entrada CSV vazia mantém o contrato
atual; não recebe uma exceção implícita por fornecer schema.

#### Conversões e falhas

CSV classifica ausência com as opções NA existentes antes da conversão. String
preserva o campo decodificado (inclusive zeros iniciais/NUL); números usam os
parsers do core e decimal configurado; bool usa a gramática booleana existente.
Schema explícito não promove uma coluna para outro tipo em caso de falha.

JSON conserva as famílias dos tokens: string recebe string; bool recebe
booleano; int64 recebe token inteiro representável; float64 recebe fração/
expoente e inteiros que sejam exatamente representáveis. `1.0` para int64 e
`"123"` para número são rejeitados neste recorte, sem coerção implícita.
As regras numéricas estritas já aprovadas continuam valendo para faixa,
subnormais e promoção exata. Números JSON não viram string automaticamente.

Exemplos de aceitação/rejeição independentes da implementação:

| Caso | Resultado proposto |
|---|---|
| CSV `00123` em string | Bytes `00123` |
| CSV `abc` em int64 nullable | Erro de conversão, não NA |
| JSON string `"123"` em int64 | Erro de família do valor |
| JSON inteiro `9007199254740993` em float64 | Erro de precisão |
| JSON null em campo não nullable | Erro de ausência |
| JSON com chaves reordenadas | Mesmos valores e ordem definida pelo schema |

Diagnósticos devem identificar registro lógico, campo do schema, tipo esperado
e motivo; posição de byte quando disponível. Registro/coluna nas mensagens
são base 1; offsets de bytes conservam base 0. Um registro CSV pode ocupar
várias linhas físicas, portanto não rotular registro como linha física.
Erros de schema são validados antes de consumir dados. Nenhuma falha publica
tabela parcial. Falhas operacionais, estrutura e UTF-8 inválido nunca viram NA.
Defaults e modo tolerante ficam fora desta primeira implementação proposta.

#### Fronteira C/FFI e ownership

Proposta de tipos em header próprio `smaug_schema.h`, independente dos headers
de formatos: `smaug_schema_field_t` (nome/comprimento, dtype, nullable) e
`smaug_schema_t` (campos/contagem). Dtype usa identificadores públicos explícitos,
sem exportar os códigos privados `DT_*` da inferência. Layout definitivo e
validação de enums, contagens e ponteiros fazem parte da implementação.

Descritores C são emprestados, const e válidos até o término da chamada; os
readers copiam os nomes e produzem buffers próprios. O Lua mantém os donos
FFI vivos durante a chamada. A tabela resultante não referencia o descritor.
A representação em memória não define o futuro layout binário `.smg`.

Adicionar variantes `smaug_read_csv_mem_schema`, `smaug_read_csv_schema`,
`smaug_read_json_mem_schema` e `smaug_read_json_schema`, com schema separado
das opções de formato. Símbolos e layouts existentes permanecem; frontend
novo que usar schema deve verificar a disponibilidade das novas funções antes
da chamada. A versão ABI não deve ser usada como versão de funcionalidade:
se layouts existentes mudarem, migrar a versão/cdef e seus consumidores juntos.
As assinaturas exatas só passam para API Reference quando implementadas.

#### Verificação necessária e ordem de implementação

1. Descritor/validação C e construtor Lua, com bytes/NUL, enums inválidos,
   nomes duplicados, sequências com buracos e lifetime.
2. CSV: associação e conversão antes da inferência, header reordenado,
   ausência versus estrutura, limites numéricos e colunas vazias.
3. JSON: famílias de tokens, associação, nulidade, precisão e array vazio.
4. Integração de arquivo/memória, OOM e recuperação, consumidores FFI,
   regressões sem schema e mutantes dos novos contratos.

Não declarar schema funcional a partir apenas dos descritores ou exemplos.
Reuso por `.smg` e Models é requisito de separação do desenho; sua implementação
continua fora desta etapa.

### Implementação e vínculo com o review de testes — schema

O descritor/validador público está em `smaug_schema.h`/`smaug_schema.c`, sem
opções de formato. Adaptação de tabela, diagnóstico e leitura de bytes ficam
no Anel 3 (`smaug_io_schema.c`); CSV/JSON reutilizam seus tokenizadores e
parsers numéricos existentes. O Lua mantém descritores/nomes FFI vivos durante
as chamadas e converte os resultados pela ponte existente, com cleanup.
Nenhum layout anterior mudou. Defaults/modo tolerante/overrides parciais e
persistência continuam fora deste recorte.

- R01/R09: `test_schema.c` e `io/test_schema.lua` verificam expectativas
  literais de shape, ordem, tipos, máscaras, false, int64 exato, zeros iniciais,
  bytes/NUL, famílias JSON e diagnósticos. O esperado não usa o parser como
  oráculo. Leitura em arquivo, objetos temporários e alteração dos descritores
  de origem exercitam ownership e recuperação.
- R03/R05: allocfail enumera alocações observadas em quatro entradas, confirma
  cada injeção, exige erro/NULL sem resultado parcial e verifica conteúdo após
  cada recuperação. String de 6.000 bytes força crescimento. Falha simulada de
  fclose fecha o stream real e exige diagnóstico, cleanup e recuperação.
  Não foram adicionadas exclusões de cobertura para esses caminhos.
- R06: auditoria ABI compilada inclui tamanho/offsets dos novos descritores;
  biblioteca ABI 1 sem símbolos de schema deve falhar com diagnóstico de
  capacidade. Inventário textual de layout também inclui os descritores.
- R07: novas suítes integram Makefile, build.sh e build.ps1. Windows exige exit
  zero também nos testes C, além de PASS; teste Lua usa o prefixo OK esperado.
  A mudança do executor Windows ainda exige execução nessa plataforma.
- R04: make_coverage.sh coleta as duas suítes; parity inclui o arquivo Lua no
  eixo 11, símbolos de schema no eixo 3 e descritores no eixo 15. Parity textual
  não substitui execução, e cobertura requer rodada própria para novo relatório.

Comandos e resultados desta árvore ficam no checkpoint; não usar contagens
históricas de coverage/parity como certificação da implementação nova.
