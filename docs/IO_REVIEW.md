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

## Decisões aprovadas, implementação de I/O pendente

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
  JSON sempre emite ponto. A leitura JSON ainda usa conversão própria e
  continua pendente de migração, inclusive para independência de locale.

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

Recorte aprovado: comprimento de nome em `smaug_column_t` e seus consumidores,
metadata separada. Proposta de layout: `name_len` após `name`, primeira ABI
identificada 1. Todos os produtores fornecem comprimento real, sem fallback
para `strlen`; nome vazio tem comprimento zero legítimo. Aceitação de
`name == NULL` nos writers ainda precisa de regra explícita.

**Proposta para marcadores CSV:** array emprestado `na_lengths` junto a
`na_values`, ambos com `na_count` elementos e ancorados pelo Lua até a chamada
terminar. NULL mantém padrões internos; array explícito de contagem zero
mantém `na_values={}`. Comparar bytes/comprimento exatamente, incluindo
marcador vazio ou com NUL. Nenhuma sentinela de tamanho ou parsing duplicado.
Fechar esse layout junto da migração, antes de congelar a ABI.

Na leitura, `io/csv.lua` chama `tonumber` para int64. Na escrita, chama `get`,
que também retorna number, antes de preencher a tabela C. Corrigir ambos os
sentidos. Verificar liberação da tabela quando construção de DataSet ou
adição de coluna lançar erro, e limpeza de tokens/records em retornos C.

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

## Políticas abertas e evidência exigida

R3 ainda precisa fechar largura irregular/dialeto CSV, limites numéricos,
misturas int64/float64, zeros iniciais, schema explícito, BOM, UTF-8 e surrogates.
As referências externas do registro histórico informam a discussão; não
substituem a escolha do Smaug nem impõem dependências de runtime.

Para cada correção, verificar valor/status/máscara/estado, saída em falha,
cleanup e mutações. O probe `audit_numeric_parse.c` rodou 28 cenários normais
sob Valgrind na auditoria anterior, sem erro de memória reportado; a semântica
continuava defeituosa. ASan/UBSan não linkaram naquele ambiente. Cobertura
histórica e o teste `|| 1` de allocfail não comprovam a ausência desses defeitos.
