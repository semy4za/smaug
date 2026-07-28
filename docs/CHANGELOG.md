# Changelog — Smaug

Registro de o que mudou e por que, em ordem cronológica reversa.
Uma entrada por sessão de trabalho. Foco no que não é óbvio pelo diff:
decisões, achados, motivações.

---
## 2026-07-27 — Roadmap enxuto: só o que falta, e uma porta de entrega de verdade

O roadmap tinha 1562 linhas e ~70% delas descreviam trabalho já feito. Um arquivo
que deveria responder "o que falta" respondia principalmente "o que já foi" — e a
resposta útil ficava soterrada.

Antes de cortar, duas verificações que mudaram o plano. A primeira: o `CHANGELOG`
tem 103 entradas e cobre todos os itens fechados, então copiar o detalhe para lá
seria **duplicar**, não mover — o raciocínio já estava preservado. A segunda, mais
importante: o **código referencia números de item pesadamente** em comentários que
explicam por que ele é como é — `10.6` aparece 52 vezes, `12.21` 30, `9.1` 25.
Apagar as entradas orfanaria essas referências: alguém lendo `-- ver 10.6` não
acharia nada.

Daí a forma escolhida. Os itens fechados viraram **stubs resolvíveis** num "Índice
do concluído" — número, título, uma linha —, suficiente para resolver uma
referência do código, com o detalhe apontando para o `CHANGELOG`. Os abertos
ficaram por inteiro. 1562 → ~700 linhas, sem perder rastreabilidade.

O item 14 foi reescrito. Era um checklist de quatro linhas; virou a **porta de
entrega**, com cinco frentes. As três primeiras verificam o que existe: leitura
linha a linha do C (não rodar a suíte — *ler*, porque a suíte prova o que foi
testado e a leitura acha o que ninguém pensou em testar), coerência de camada nos
anéis 1–3, e contratos contra código. A quarta é execução nas duas plataformas com
contagens que precisam bater. A quinta é a que faltava: **superfície externa** —
LICENSE (inexistente, e sem ela ninguém pode legalmente usar o projeto), fronteira
público×interno, política de versão, instalação, taxonomia de erro e medição de
performance. Correção interna não substitui isso; sem esses pontos o projeto é
excelente e inutilizável por quem não é o autor.

Cada frente cita os precedentes concretos que a motivaram, para não virar
checklist genérico: a nota de 2^53 que ficou errada por semanas com o eixo de doc
verde, a divergência de contagem de binários entre Fedora (12) e Windows (11), as
convenções de alocação que diferem por dtype.

Aberto no caminho: **12.34** — a colação de string está implementada cinco vezes.
Quatro em C são duplicação injustificada (duas delas no mesmo arquivo, 200 linhas
de distância, com o comentário de uma admitindo que repete a outra) e colapsam num
núcleo folha. A quinta é o `CategoricalSeries` comparando com o `<` do Lua, o que
está arquiteturalmente certo — ele é Tier 2, Lua puro — mas depende de o LuaJIT
ordenar por `memcmp`. No Lua padrão seria `strcoll`, dependente de locale, e o
categorical divergiria em silêncio. Vira teste de invariante.

Nenhum C, nenhum Lua.

---
## 2026-07-27 — 10.2 fechado, e a edição não testada do build_win.ps1 se provou

Uma rodada no Windows fechou três pendências. A fatia 2 do 10.2 atravessou a ABI
do MSYS2-UCRT64 — o `str_between` tem a assinatura mais larga do conjunto, com
dois pares (ponteiro, tamanho), que é justamente o caso em que o Linux passa e o
Windows quebra. **Com isso o 10.2 está completo: os quatro dtypes ordenáveis
comparam no Anel 0**, e o item saiu da timeline para o índice do concluído.

A edição do `build_win.ps1` que eu havia entregue com a ressalva de "não pôde ser
testada" funcionou: `core/test_keys` e `core/test_collation` apareceram na saída
do Windows. Isso confirmou na prática o achado das listas divergentes — os dois
testes existiam e passavam, mas o Windows nunca os rodava. O `test_keys` guarda a
correção do int64 > 2^53 desde o 10.5; passou meses verificado em uma só das três
configurações.

A fatia A do 10.3 também passou no Windows, mas segue **sem selo**: Valgrind e
cobertura só rodam no Fedora, e é lá que a medição vale.

Fica registrado o que ainda diverge entre plataformas: Fedora roda 12 binários em
C, Windows 11 — falta `test_astype` na lista do `build_win.ps1`. A matriz de
conversão nunca foi confirmada na ABI do Windows.

---
## 2026-07-27 — 10.3 fatia A: as seis matemáticas descem ao Anel 0, por macro

`sin`, `cos`, `tan`, `exp`, `log` e `sqrt` eram seis `self:map(closure)` — loop em
Lua cruzando FFI por elemento, o padrão que o item 10 existe para eliminar. Agora
são seis funções em C geradas por **uma** macro, porque diferiam exclusivamente
pela função de libm que aplicam. Seis corpos escritos à mão seriam seis lugares
para repetir cada correção futura e cinco para esquecê-la; a casa já usa esse
padrão no `DT_CMP_IMPL`.

Entrada int64 não ganhou versão própria (Opção 1, decidida no bloco de design): a
saída é `float64` independente da entrada, então o frontend encadeia
`astype("float64")` — já vetorizado — e chama a versão f64. Não é reimplementação,
são duas chamadas do Anel 0 em sequência; e converter antes não perde nada que a
operação não fosse perder.

Os testes foram escritos guiados por tabela pelo mesmo motivo de a implementação
ser macro: depois da expansão, **cada instanciação é um corpo próprio**, com seus
próprios ramos. Cobrir `sqrt` não cobre `tan`. É a mesma lição da fatia 1 do 10.2,
onde testar os quatro modos só em int64 deixou os ramos do f64 descobertos. De
quebra apareceu que `tan` não era exercitada por teste nenhum.

Cobertura subiu de 94.81% para 94.87% de branch-alvo com o número de descobertos
**inalterado em 227** — as seis entraram integralmente cobertas. Mutação verificada
em dois eixos: remover a propagação de nulo e trocar `sqrt` por `fabs` abortam o
teste.

Duas correções ao desenho que estava registrado, achadas relendo o código antes de
escrever. São **12** funções em C, não 11: a decisão "`round(int64)` preserva
int64" tornou `round` uma operação que preserva dtype, e o número anterior assumia
saída f64. E a macro cobre **7**, não 6 — `abs` de f64 tem exatamente a mesma forma
das seis, só troca a função de libm por `fabs`. Fica 1 macro + 5 corpos à mão.

Fatia B (`abs`/`round`/`clip`) segue aberta: é onde estão as três decisões
semânticas e o degrau que só sai quando as três descerem.

---
## 2026-07-27 — 12.34: uma colação só, e dois buracos de build que ela expôs

A regra de ordenação de string estava escrita em quatro lugares do C. Agora está
num núcleo `smaug_cmp_bytes` (`static inline` em header interno, no padrão do
`smaug_io_internal.h`), e os quatro delegam. `sort_cmp_idx` virou `str_cmp_idx` +
desempate por índice — porque estabilidade é preocupação de *sort*, não de
colação, e misturar as duas era o que fazia parecer que eram funções diferentes.

Não era só duplicação: **uma das quatro divergia**. A do `ops_window.c` chamava
`memcmp(pa, pb, lmin)` sem a guarda `lmin > 0`, a única sem ela. `memcmp` exige
ponteiro válido mesmo com `n == 0`, e em série vazia `buffer + offset` pode ser
`NULL + 0` — UB pelo padrão, inofensivo na prática, mas é o tipo de coisa que só
aparece quando alguém troca de compilador. Unificar eliminou o caso.

Sobrou um `memcmp` e ele fica: o atalho de igualdade no `eq`/`ne`, que compara
comprimento primeiro. Não é colação — não ordena nem desempata — e é equivalente
ao núcleo.

A invariante Lua↔C virou teste (`tests/core/test_collation.lua`, 59 checks). O
`CategoricalSeries` compara com o `<` do Lua e está certo em fazer isso, mas só
concorda com o resto da biblioteca porque o LuaJIT compara por `memcmp`; no Lua
padrão seria `strcoll`, dependente de locale. Os pares do teste são escolhidos
onde as duas semânticas realmente divergem: `"a"` × `"B"`, `"Z"` × `"a"`, acento
multibyte, NUL embutido. Antes isso era suposição; agora falha alto.

Dois achados colaterais, e o primeiro é constrangedor no melhor sentido.

**O `Makefile` não declarava dependência de header.** `$(TARGET): $(SRCS)` — editar
um `.h` não recompilava. Descobri na pele: o teste de mutação no núcleo novo
"passou", e passou porque a `.so` era a antiga. Um teste de mutação que dá falso
positivo é pior que nenhum, porque dá confiança falsa. Corrigido com
`$(HDRS) = $(wildcard include/*.h)`, espelhando o glob do 12.19. O `build.sh` era
imune porque recompila tudo num comando só — o que explica por que nunca apareceu:
o selo sempre foi honesto, só o loop de desenvolvimento é que não era.

**As três listas de teste Lua tinham divergido.** `core/test_keys` — que guarda a
correção do int64 > 2^53 — estava só no `build.sh`. Não rodava no Windows nem na
cobertura. Mesma família do `test_astype` (12 binários no Fedora, 11 no Windows).
Alinhadas as três; a causa de fundo é lista mantida à mão, que é o que a metade
aberta do 12.19 existe para resolver.

Cobertura: descobertos 227 antes, 227 depois. A refatoração removeu 24 ramos que
estavam totalmente cobertos e não criou nenhum descoberto — o percentual mexeu só
porque o denominador encolheu.

**Selo Fedora (mesmo dia):** Valgrind 0 erros nos 13 binários. A medição no
ambiente autoritativo confirmou a previsão com precisão — **226 ramos descobertos
antes e 226 depois**, com 24 ramos cobertos a menos no total. É a evidência de que
a refatoração foi neutra em comportamento: só saiu código redundante, e ele estava
inteiramente testado. MANIFEST 126→128 arquivos (o header interno e o teste de
colação).

Os dois testes de `core/` apareceram na saída da suíte pela primeira vez, o que
confirma na prática o achado das listas divergentes: o `test_keys` existia e
passava, mas o build só o rodava numa das três configurações.

Ressalva registrada: o `build_win.ps1` foi editado e **não pôde ser testado** —
não há PowerShell no ambiente de desenvolvimento. Mesma situação do
`make_manifest.ps1`, que falhou na primeira execução real. A próxima rodada no
Windows valida a edição.

---
## 2026-07-27 — 10.2 fatia 2: between fecha nos quatro dtypes, e o Anel 1 para de comparar

`datetime` e `string` desceram ao Anel 0, e com isso o `between` deixou de existir
em dois anéis. O ganho maior não é performance: até aqui o `_predicates.lua`
reimplementava em Lua uma comparação que o Anel 0 já sabia fazer — violação de P3
— e o degrau `check_i64` existia só para tornar visível o erro que esse loop
produzia. Com o fallback removido, o degrau saiu junto e o import ficou órfão: o
`between` era o único consumidor dele naquele arquivo.

O `dt_between` nasceu **fora** da macro `DT_CMP_IMPL`. A macro assume um threshold
e um operador; aqui são dois limites e dois flags. Forçar caberia só deformando a
macro para todos os outros usos, o que é pior. O `str_between` reusa `str_cmp_at`
em vez de escrever `memcmp` de novo — a colação já está implementada quatro vezes
no C (12.34), e criar a quinta enquanto se discute unificá-las seria incoerente.

O trabalho difícil foi cobertura, e a lição da fatia 1 se repetiu quase igual: a
branch-alvo **caiu** de 94.78% para 94.66% ao adicionar as duas funções. Em vez de
adivinhar, o mapa de ramos descobertos do próprio `COVERAGE.md` apontou os cinco
pontos. Quatro eram previsíveis em retrospecto; um não era.

O previsível: `malloc(size ? size : 1)` só exercita o `: 1` com série vazia **que
peça a máscara**; o `if (mask)` falso dentro do ramo de nulo é inalcançável pelo
frontend, que sempre pede a máscara; e a guarda `!lo && lo_len > 0` precisa de um
caso com **len 0** — alvo nulo com comprimento zero é string vazia, não chamada
inválida, e sem esse caso a segunda condição da guarda nunca é avaliada.

O que não era previsível: no `dt`, o ramo descoberto era o **curto-circuito do
`&&`**. Em `A && B`, se A é falso o B nem roda — e nenhum teste anterior falhava
pela esquerda, porque todos usavam limites que o valor satisfazia. Precisou de um
caso com `lo` acima de tudo. Esse tipo de ramo não aparece lendo o código; aparece
medindo.

Fechou em 94.84% branch-alvo e 98.84% linha, ambos acima do baseline. `test_string`
132→142, `test_datetime_c` 462→473, `test_access` 156→168, allocfail 1898→1918.
Mutação verificada nas duas implementações.

Fica anotado que o `datetime` não tinha varredura OOM de comparador nenhum — a do
`between` foi a primeira. Lacuna pré-existente, não expandida aqui.

---
## 2026-07-27 — selo Fedora: fecha 10.2 fatia 1, 12.31 e 12.32

Valgrind 0 erros nos 13 binários, incluindo os dois `between` novos e a varredura
de falha de alocação (1898 verificações). Cobertura **acima** do baseline anterior:
linha 98.83% contra 98.82%, branch-alvo 94.78% contra 94.73% — o código novo entrou
integralmente coberto, depois da correção dos ramos que faltavam.

O detalhe que vale registrar é a **igualdade de contagem entre plataformas**:
`test_ops_edge` 307, `test_access` 156, `test_constructors` 381, `allocfail` 1898,
idênticos no Fedora e no MSYS2-UCRT64. Divergência de contagem entre plataformas
seria sintoma de comportamento dependente de ambiente, não detalhe de relatório.

Fecha três itens que estavam represados esperando o Valgrind — só um deles tocava
C. Com a fatia 1 selada, a fatia 2 do 10.2 (datetime + string) está desbloqueada,
com o desenho já aprovado.

Fica registrado que o Fedora roda **12** binários em C e o Windows **11**: falta
`test_astype` na lista do `build_win.ps1`. Não afeta estes itens (astype não foi
tocado), mas significa que a matriz de conversão nunca foi confirmada no Windows.

---
## 2026-07-27 — Roadmap enxugado: só o que falta, e uma porta de entrega

O Roadmap tinha 1562 linhas e ~1086 delas descreviam trabalho **já concluído** —
dez temas inteiros mais 29 subitens dos blocos 10 e 12. Ler o que falta exigia
garimpar. Reduzido para 658 linhas.

A primeira ideia era mover o conteúdo concluído para cá. Ao verificar, não fazia
sentido: este CHANGELOG tem 103 entradas e já cobre cada item fechado, com o
raciocínio, as medições e os achados da sessão em que fechou. Copiar 1086 linhas
seria duplicar o registro, não movê-lo. O CHANGELOG **já é** o histórico; o
Roadmap é que estava fazendo o papel errado.

Mas apagar os itens não era opção, e isso só ficou claro ao olhar o código: os
comentários referenciam números de item o tempo todo para explicar por que o
código é como é — `10.6` aparece 52 vezes, `12.21` 30, `9.1` 25. Apagar as
entradas orfanaria essas referências: quem lesse `-- ver 10.6` não acharia nada.
Então o concluído virou um **índice de stubs resolvíveis** — número, título, uma
linha — com o detalhe apontando para cá. Resolve a referência sem carregar o peso.

O item 14 deixou de ser quatro linhas genéricas e virou uma **porta de entrega**
com cinco frentes. As três primeiras verificam o que existe: leitura linha a linha
do C (não rodar a suíte — ler, porque a suíte prova o que foi testado e a leitura
acha o que ninguém pensou em testar), coerência dos anéis 1–3, e contratos contra
o código. A quarta é a verificação executável nas duas plataformas. A quinta é
nova e desconfortável: a superfície externa — `LICENSE` inexistente, fronteira
público/interno que é só um comentário, sem política de versão, sem instalação,
erros que só existem como string, e performance que nunca foi medida enquanto
correção é medida à exaustão. Sem isso o projeto é excelente e inutilizável por
quem não é o autor.

A leitura do C que preparou o item 14 rendeu dois itens novos. **12.33:** colação
de string e propagação de nulo em comparação são semânticas visíveis ao usuário e
não têm contrato — e a doc atual chega a errar, dizendo que a lógica de três
valores "propaga NA", quando Kleene absorve (`false AND nulo = false`). **12.34:**
a colação está implementada **cinco vezes** — quatro em C, sendo duas delas no
mesmo arquivo a 200 linhas de distância, e uma em Lua no `CategoricalSeries`. As
quatro do C são duplicação e colapsam num núcleo folha. A quinta é legítima
(categorical é Tier 2, Lua puro; chamar o C por elemento seria o antipadrão que o
item 10 combate), mas funciona por uma razão que ninguém escreveu: o LuaJIT
compara string por byte, não por `strcoll`. Vira teste.

Nenhum código tocado.

---
## 2026-07-27 — 12.32: um gerador de MANIFEST só, e ele agora diz qual árvore descreve

Duas correções que nasceram do mesmo incidente. Um zip veio da máquina Windows
atrás do Fedora, e o MANIFEST validou **limpo** — porque um MANIFEST sempre
valida contra a árvore que o gerou. Hash de arquivo prova consistência interna,
nunca atualidade. O erro só apareceu quando fui procurar o trabalho da sessão e
ele não estava lá.

A primeira correção é a que eu tinha proposto: os dois geradores divergiam. Ao
ler o código, não eram dois eixos como eu havia reportado no checkup — eram seis.
Separador de caminho, BOM, fim de linha, texto do cabeçalho (cada script nomeava
a si mesmo, então os arquivos nunca bateriam nem em árvore idêntica), critério de
ordenação (`LC_ALL=C sort` sobre caminho relativo contra `Sort-Object` sobre
caminho absoluto) e contagem de linhas (`wc -l` conta quebras, `(Get-Content).Count`
conta linhas, e discordam em arquivo sem quebra final).

Em vez de fazer as duas implementações concordarem — o que exigiria sincronia
eterna, e eu nem podia testar o `.ps1` aqui — o `.ps1` virou wrapper que delega ao
`.sh` pelo bash do MSYS2. O bash já é requisito do fluxo Windows, então não entra
dependência nova. Divergência deixa de ser possível por construção, que é o mesmo
raciocínio do `keys.lua` e do `int_scalar.lua`: fonte única resolve, vigilância
não.

A segunda correção é a que importa mais, e é a que me obrigou a corrigir minha
própria justificativa: unificar o formato **não** teria pego o incidente. Nenhum
formato pega. O que pega é procedência — o cabeçalho agora traz
`# Arvore: <commit>`, com `+ alteracoes nao commitadas` quando o working tree está
sujo e `sem git` fora de repositório. Agora um zip diz de qual árvore veio antes
de qualquer análise.

Consumidores checados antes de mexer, porque o MANIFEST é lido por código:
`parity/14_thread_safety` tem um fallback que o parseia (`%./(src/[%w_]+%.c)`, não
colide com a linha nova) e `make verify` só regenera e faz diff. Efeito colateral
aceito: em árvore suja o `make verify` mostra também a linha de procedência
mudando — informação correta, a árvore está suja mesmo.

O `.sh` foi testado nos três casos (fora de git, repo limpo, repo sujo). O `.ps1`
**não pôde ser testado** — não há PowerShell no ambiente de desenvolvimento. E ele
falhou na primeira execução real, de um jeito que rende duas lições.

A primeira: achar o bash não basta. As coreutils que o `.sh` usa vivem em
`C:\msys64\usr\bin`, e o `build_win.ps1` só põe `ucrt64\bin` no PATH — de onde vêm
gcc e luajit. Bash não-interativo não lê `/etc/profile`, então herda o PATH do
Windows sem as ferramentas, e o script morre em `sha256sum: command not found`. O
wrapper agora garante o diretório das coreutils.

A segunda é mais séria e só apareceu porque a primeira falhou: o `.sh` escrevia
direto no arquivo final. O redirecionamento trunca o alvo **antes** de qualquer
falha, então sobrou um MANIFEST só com cabeçalho — e o arquivo válido anterior foi
destruído. Pior: um MANIFEST truncado *parece* bom (cabeçalho certo, formato
certo) e omite arquivos, e como a verificação só confere o que está listado, a
omissão não seria detectada. Uma falha barulhenta virando silenciosa, que é
exatamente o que o projeto não aceita. Corrigido com verificação prévia das
ferramentas (erro claro antes de tocar no arquivo) e escrita atômica (temporário
+ `mv` no sucesso, com `trap` limpando o lixo).

Vale registrar o encadeamento: o wrapper falhar foi bom. Ele falhou alto, e ao
investigar por que, apareceu um risco que estava lá desde sempre e nunca tinha se
manifestado.

Nenhum C, nenhum Lua.

---
## 2026-07-27 — 12.31: inferência de dtype passa a decidir por família, não por rank

Achado na reescrita do Contrato 1: `from_table({1, "x"})` inferia `string`, porque
o rank (bool > string > float64 > int64) mandava escolher o de maior rank, e
depois estourava no `set` com *"valor para string deve ser uma string Lua"*. O
usuário nunca pediu string. A inferência escolhia um dtype e a validação o
desmentia — as duas discordavam entre si, e a mensagem apontava para o lugar
errado, o que é pior que não avisar.

A causa é que o rank foi desenhado para o caso numérico, onde ele está certo:
`{1, 2.5}` → float64 é promoção segura, e int→float não perde informação. O erro
foi generalizar isso para tipos que não têm supertipo. Entre número e texto não
existe promoção — escolher string significaria decidir que o número "vira texto",
que é a adivinhação de semântica que o Contrato 1 recusa.

Trocado por famílias: `int64` e `float64` são a mesma família, `string` e `bool`
são famílias próprias. Dentro do numérico o rank sobrevive (o fracionário vence);
entre famílias, erro na inferência, nomeando os dois dtypes e as duas posições.
Nomear a posição importa: é a diferença entre "conserte sua lista" e "conserte sua
lista no índice 2".

Raio de alcance verificado antes de mexer, porque é fonte única: `infer_dtype` é
chamada só pelo `from_table`, o DataSet passa por ela, e o CSV **não** usa (tem
inferência de texto própria, 12.25/12.26). `infer_dtype_from_value` ficou intacta.

O `level` do erro foi medido, não estimado — e deu 4, não 3. Motivo: o
`Series.from_table` é **sobrescrito** no `init.lua` para interceptar categorical, e
esse wrapper adiciona um frame. Com 3 o erro não apontava a linha do usuário. Já
tinha acontecido algo parecido no 9.3 (metamétodo 3, método `:` 4); a lição é que
`level` em Lua é empírico.

+18 checks (363 → 381), com mutação verificada: fundir as famílias faz o teste
abortar.

Lua puro, nenhum C tocado.

---
## 2026-07-27 — 10.2 fatia 1: between desce ao Anel 0 (f64 + i64)

Primeiro item do bloco 10 a sair depois que o 9.3 destravou a fronteira do
escalar. O `between` fazia o loop em Lua lendo por `get()` — double — e por isso
carregava o degrau desde 23/07: em int64 acima de 2^53 a comparação saía errada
em silêncio (`between(x, x)` no próprio `x` devolvia false), e o degrau trocou
isso por falha visível. Agora a falha visível virou resultado certo.

Desvio do que estava registrado, e vale o registro do porquê. O roadmap dizia
"compor `ge & le` no C". Lendo a implementação real, compor internamente custaria
três pares de alocação (result+mask) e três varreduras para o que uma varredura e
um par fazem — e os quatro modos de `inclusive` obrigariam a alternar `ge`/`gt` e
`le`/`lt` dinamicamente. Primitiva dedicada de passada única com dois `bool`
(`inc_lo`/`inc_hi`) resolve os quatro modos direto e é mais simples. O propósito
do item (tirar o loop do Anel 1) é servido melhor assim.

O 9.3 paga aqui, e essa é a parte que não é óbvia: vetorizar sozinho não bastaria.
O C compara o valor da série exato, mas os *limites* entram pela fronteira do
escalar — que antes do 9.3 rejeitava cdata e degradava number. Sem a Fase 1, o
`between` vetorizado teria valor exato e limite degradado, e o suporte a > 2^53
continuaria de mentira. Os dois limites passam por `int_scalar.check_operation`.

Fatiado em f64+i64 agora, dt+str depois. A correção de 2^53 é toda em int64, mas
o loop no Anel 1 é dos quatro dtypes — fazer só o int64 deixaria a desparidade de
pé. Fatiar é aditivo (nada se joga fora), então o custo máximo é um selo extra,
nunca retrabalho. Enquanto a fatia 2 não entra, `between` é híbrido: delega para
f64/i64, mantém o loop com degrau para datetime/string. Transitório e documentado
no código, não desparidade permanente.

Um teste existente falhou, e era pra falhar: `test_access` asseverava que
`between` **recusa** int64 > 2^53 — o comportamento do degrau. O degrau saiu do
`between`, então a asserção virou o oposto (agora tem que acertar). Atualizada, e
o bloco separado: 10.3 (abs/round/clip) segue no degrau.

Cobertura de falha de alocação para as duas funções novas (`af_f64_between`,
`af_i64_between`): allocfail 1878 → 1898 verificações. Mutação verificada em
dois eixos — inverter a inclusividade e reintroduzir a comparação via double
fazem o teste abortar.

Achado que o número pegou e a leitura não pegaria: a primeira leva de testes
exercitava os quatro modos de `inclusive` só em `int64`, e a branch-alvo **caiu**
de 94.73% para 94.39%. Cada dtype tem implementação própria — testar os modos num
não prova nada sobre o outro, e os ramos `inc_lo`/`inc_hi` falsos do f64 nunca
rodavam. Faltavam também os caminhos `out_mask == NULL` e série NULL nos dois, que
o frontend nunca exercita porque sempre pede a máscara (os comparadores antigos já
tinham esses testes em `test_ops_edge`; o between não herdou sozinho). Corrigido;
a métrica subiu para 94.76%, acima do baseline.

+16 checks em test_access (140 → 156) e +15 em test_ops_edge (292 → 307). FFI/ABI
(cdefs novos), então Windows obrigatório — feito. Valgrind ainda pendente (só roda
no Fedora), então o selo do item não fechou.

---
## 2026-07-26 — 9.4: nlargest/nsmallest devolviam valor que não estava nos dados

Achado na leitura macro do item 10, olhando o que ainda faz loop em Lua sobre
FFI. Série `{…992, …993, …995}` (int64 acima de 2^53): `nlargest(2)` devolvia
`…996` e `…992`. O `…996` é o ponto: não é um valor impreciso, é um valor que
**nunca existiu na série**. Numa operação de seleção — o contrato é "os N maiores
QUE ESTÃO nos dados" — isso é invenção, não perda de precisão. Um `abs()` errado
dá um número errado e o usuário pode desconfiar; um `nlargest` que inventa dado
não tem como ser percebido.

Mecanismo: `c_sorted_nonnull` normalizava o buffer do C para `double[?]` — o
comentário até vendia isso como "uniforme para f64 e i64", mas a uniformidade era
obtida degradando o int64. Acima de 2^53 só os inteiros pares são representáveis
em double, então `…995` arredonda para `…996`. Depois `math.floor` e `from_table`
gravavam o resultado.

Agravante que merece nota: **avisava**. O `from_table` chamava `check_value`, que
disparava "literais Lua acima desse limite podem já ter perdido precisão". Só que
o usuário não escreveu literal nenhum — o valor veio dos dados dele. O aviso
existia e apontava para a causa errada, o que é pior que não avisar: manda
investigar o lugar errado.

Correção: a normalização deixou de ser escondida na leitura. `c_sorted_nonnull`
virou duas — `c_sorted_nonnull_native` devolve o buffer no tipo nativo
(`int64_t[?]` em int64) e concentra a chamada C, a cópia e o free; a antiga virou
wrapper fino que converte para double. `nlargest`/`nsmallest` usam a nativa e
entregam o cdata direto ao `from_table`, que aceita cdata desde o 9.1 — sem
`tonumber`, sem `math.floor`. A conversão para double continua existindo, mas
agora é um passo explícito e documentado, não um efeito colateral da leitura.

Ficam na versão double, e isso é limitação de contrato, não bug: `median`,
`quantile`, `skew`, `kurtosis`. Interpolação e momentos são float por natureza, e
o retorno é `number` Lua — que não comporta > 2^53 mesmo se calculássemos exato.
Registrado como limitação. `mode` já estava certo (migrado ao `keys.lua` no
10.5-A).

De brinde, um vazamento: o ramo f64 devolvia `nil, 0` sem liberar o ponteiro do C
quando `ptr != NULL` e `n == 0`. O ramo i64 já tratava — desparidade entre os dois
ramos da mesma função. Agora ambos liberam.

+10 checks em test_selection (56→66), com mutação verificada: reintroduzir o
`tonumber` faz o teste abortar.

Lua puro, nenhum C tocado.

---
## 2026-07-26 — 9.3: fronteira do escalar int-based (comparadores + aritmética)

O 9.1 tinha curado a *entrada* de int64 (check_value/get_raw), mas os call-sites
de *operação* ficaram para trás com o guard cru `type(v)=="number"`: comparadores
e aritmética escalar rejeitavam `cdata int64_t` — a única forma que preserva os
64 bits — e engoliam `number > 2^53` degradado sem nem o aviso que a entrada dá.
Diagnóstico: `s:eq(number grande)` marcava a linha errada em silêncio, `s + number
grande` operava no valor errado, enquanto `fillna` já estava correto (usa o
porteiro canônico). Mesma família, três comportamentos diferentes.

Criado `core/int_scalar.lua` como fonte única — mesmo padrão do `keys.lua`.
Separa RECONHECIMENTO de POLÍTICA: `classify(v)` é puro (não avisa, não erra) e
devolve a classe da forma; cada call-site aplica a política que o seu contrato
pede. A divergência é de uma classe só: `number` grande **avisa-e-aceita** na
entrada (o valor vira dado do usuário, a perda é irrecuperável, a escolha é
dele) e **erra** na operação (é operando; o resultado seria mentira). Módulo
próprio em vez de função no `_core` porque `_types.lua` roda ANTES do `_core` no
init — dependência de ordem seria frágil.

Achado que quase passou: o caso canônico `2^53+1` degrada para **exatamente
2^53**, então o limiar `> 2^53` deixava escapar justamente o valor de teste. Daí
a classe `number_at_boundary`: a operação recusa `>= 2^53` (o boundary é
ambíguo — pode ser 2^53 legítimo ou 2^53+1 degradado), a entrada preserva o
`> 2^53` de antes. Sem rodar o teste isso teria fechado como resolvido.

Fase 2 (aritmética) trouxe dois achados que só apareceram medindo. Primeiro:
`cdata + Series` é **inalcançável** — o LuaJIT resolve o `__add` do próprio cdata
antes de chegar em `Series.__add`, então o ramo comutativo para cdata-à-esquerda
era dead code (removido; a forma suportada é `Series + cdata`). Segundo: o
`level` do erro depende da mecânica de chamada — metamétodo usa 3, método `:`
tem um frame [C] de dispatch extra e precisa de 4. Medido com `debug.getinfo`,
não estimado.

Ordem importa no `binop`: a promoção N.2/N.3 vem primeiro (fracionário ou `/`
→ float64, e o escalar vira double legítimo); só se a série permanece int64 o
escalar passa pelo porteiro. Decidido que `float64 + cdata int64_t` mantém o
erro — float não preserva por natureza, aceitar não ganharia nada.

+9 checks (354→363). Contrato 1 ganhou a nota da divergência entrada-vs-operação;
README teve a nota do 2^53 corrigida (estava dizendo que where/mask/astype
recusam, mas essas migraram no 10.6/10.7). Destrava o 10.2: os limites do
`between` agora entram exatos.

Lua puro, nenhum C tocado.

---
## 2026-07-23 — 12.15: CategoricalSeries rejeita índice não-inteiro

Bug de falha-silenciosa: CategoricalSeries:get(1.5) devolvia nil calado, enquanto
Series:get(1.5) erra. O guard checava type=="number" e faixa, mas não i % 1 ~= 0.
Pior nos setters: set(1.5, x) gravava numa chave fracionária de _codes, sem
reclamar.

O guard estava copiado em 4 pontos (get/is_null/set/set_null — o achado dizia 3;
o set_null tinha passado batido). Extraído para check_cat_index, um helper único
que espelha o I.check_index canônico da Series. Não deu para reusar o da Series
diretamente: o categorical é Lua puro (_size/_codes), sem a struct _c que o
check_index da Series acessa — mas a regra de validação é idêntica, incluindo o
i % 1 ~= 0 que faltava. Corrige o bug e remove a duplicação num movimento só.

+12 guards em test_categorical (299→311): os 4 pontos rejeitam fracionário,
paridade explícita com Series:get(1.5), e caminho normal preservado (inteiro
válido lê/escreve, faixa e tipo continuam errando). Provados nos dois sentidos.

Mesmo tema das últimas auditorias: falha silenciosa é o que mais escapa neste
projeto, e categorical:get/is_null não tinham teste de índice inválido antes.

Lua puro, nenhum C tocado.

---
## 2026-07-23 — auditoria do item 10: classificação corrigida + degrau em between/abs/round/clip

Mesma lente da auditoria dos itens 1–11, agora no item 10. Os cinco subitens
concluídos (10.5-A, 10.6, 10.7, 10.8, 10.9) confirmados no código, com prova
empírica onde dava: nunique=2 para ...992/...993 (10.5-A), combine_first delegando
de fato ao coalesce (10.6, lido por inteiro), i64→str preservando ...993 exato
(10.7), astype/csv/json todos chamando smaug_fmt_* e try_i64 sendo wrapper puro de
smaug_parse_i64_cstr (10.9).

O achado principal foi de classificação. O cabeçalho do item 10 afirmava que
"10.1–10.4 não são bugs — são assimetrias de vetorização (performance)". Testando
em vez de acreditar: between(x, x) no próprio x devolvia FALSE para
x = 9007199254740993, e abs(-9007199254740993) devolvia 9007199254740992. Ou seja,
10.2 e 10.3 são defeito de correção da mesma família do 10.5–10.7 — a mesma
degradação por get()/tonumber() —, e estavam classificados como performance, o que
os manteve no fim da fila. Cabeçalho corrigido.

Correção aplicada agora: o degrau check_int64_lossless, que estava órfão desde que
o 10.6/10.7 desceram ao Anel 0 (ninguém mais o chamava), voltou a ser usado — é
exatamente para isso que existe. Roda em between, abs, round e clip, trocando
corrupção silenciosa por falha visível. Nas três do map, o degrau vai dentro da
closure, aproveitando que o map já passa (v, i) — uma passada só, sem custo extra.
map() ficou de fora por decisão: é API genérica onde o caller escolhe dtype de
saída e closure; bloquear seria invasivo.

Isto é paliativo, não conserto: quando 10.2/10.3 descerem ao Anel 0, o degrau sai
e o suporte a int64 > 2^53 passa a ser real. Mesmo padrão do Passo A do 10.6/10.7.

Por que passou despercebido: Series:abs(), :round() e :clip() não tinham NENHUM
teste direto — eram exercitados só via DataFrame, e nunca com int64 grande. +13
guards em test_access (127→140) cobrindo recusa acima de 2^53, mensagem com o
valor exato, fronteira 2^53 ainda aceita, e caminho normal intacto. Provados nos
dois sentidos.

Segundo achado, registrado sem atacar: cinco comentários no código dizem "bool
fica no Anel 1 até 10.8", mas o 10.8 fechou com escopo redefinido e não trouxe
bool para as famílias do 10.6/10.7. Falta smaug_bool_coalesce (existe só a
_scalar), smaug_bool_select e os pares de astype com bool. Sem risco de int64 —
é coerência de anel. A decidir: item próprio e reapontar os comentários.

Lua puro, nenhum C tocado.

---
## 2026-07-22 — auditoria dos itens 1–11 + correção do 7.2a (capacidade morta)

Auditoria reversa pedida pelo Gui: em vez de confiar na marca [Done], verificar no
código se o trabalho existe. Dez dos onze itens confirmados, vários com prova
empírica — var([1,2,3])=1.0 (ddof=1 do 5.0), get_raw preservando
9007199254740993LL (9.1), mutar column() não altera o frame (E2 do 9.2 morto),
to_string exibindo int64 exato via cell_of→get_raw (11.4), pad/cell_str
consolidados em display.lua (11.5), eixo 02 com 0 gaps reais (6.4).

Um achado: o 7.2a afirmava "gate na Lua passou a ser por capacidade
(self._d.argmin), sem fallback" — mas o código tinha um guard por dtype que
barrava str/bool antes de alcançar esse gate. O Anel 0 estava certo o tempo
todo: smaug_str_argmin/argmax e smaug_bool_argmin/argmax existem, são testados no
C (test_ops_window, incluindo "str argmin = 1 (abacaxi)") e o descritor já os
ligava. Capacidade morta: escrita, testada, ligada, inacessível.

Por que ninguém viu: nenhum teste Lua chamava argmin/argmax em string ou bool. A
suíte ficava verde porque a lacuna nunca era exercitada do lado do Anel 1 — o
tipo de ponto cego que só uma auditoria de "o que foi prometido existe mesmo?"
encontra.

Correção: guard por dtype → gate por capacidade, exatamente como o item já
descrevia. O fallback element-wise saiu junto (código morto: os 5 dtypes com
descritor têm argmin, e categorical nem expõe o método). Os aliases idxmin/idxmax
herdam de graça, pois delegam. +14 guards em test_window (122→136) cobrindo str,
bool, bordas (toda-NA, vazia) e os aliases — provados nos dois sentidos
(reintroduzi a regressão, o teste quebrou; restaurei, voltou verde).

Detalhe menor registrado: o roadmap cita datetime/_dt.lua, mas o arquivo vive em
temporal/_dt.lua — caminho da época do registro, não erro de trabalho.

Lua puro, nenhum C tocado. Contadores do resto da suíte idênticos ao baseline.

---
## 2026-07-21 — 12.30 Fase 1: to_csv_mem/to_json_mem comunicam a causa do erro

Ataque faseado do 12.30 (contrato de erro de escrita). Fase 1: as duas variantes
_mem, que tinham o bug mais grave — o retorno NULL colapsava OOM com sep==decimal,
e o Lua repassava "OOM" mesmo quando a causa era erro de configuração (mensagem
factualmente errada, não só imprecisa).

Escolha de desenho (Opção B, das três levantadas): adicionar um out-param
char **err_out às funções de escrita, espelhando o t->error que a leitura já usa.
Helper set_io_error() em smaug_io_internal.h, ao lado do make_error. Rejeitadas:
resolver no Lua duplicaria a checagem sep==decimal (fere fonte única); implementar
o smaug_io_last_error() que o header promete exigiria static mutável — violaria a
thread-safety do Anel 0 que o eixo 14 protege (seria um retrocesso auto-infligido,
e o próprio contrato do header está obsoleto por isso).

Detalhe de heap que o design respeita: err_out é strdup dentro da DLL, então o Lua
libera com smaug_free (heap da DLL), nunca ffi.C.free — mesma regra do buffer de
write_mem, por causa dos heaps separados de luajit.exe e smaug.dll no Windows.

O teste sep==decimal em test_io_c já materializava o achado: verificava t->error
com "decimal" no read, mas só out==NULL no write (assimetria escrita no próprio
teste). Agora o write também verifica a causa. Guard Lua em test_csv confirma que
to_csv_mem não diz mais OOM. Allocfail ganhou cobertura do strdup do set_io_error
(err_out não-NULL sob OOM) — o novo ponto de alocação entra na mesma disciplina
de alloc-failure do resto do projeto. test_io_c 312→315, test_csv 141→144,
allocfail 1874→1878.

Faseado porque a migração toca ~45 call-sites (33 em testes C) e muda assinatura
pública — selo Fedora. Fase 2 (smaug_write_csv/json, o errno do fopen/fwrite)
fica registrada para a próxima. Eixo 14 segue verde: nenhum estado global
introduzido.

---
## 2026-07-21 — 12.20: eixo 03 ampliado (4 frentes) + 12.30 registrado (review do Anel 0)

Pedido explícito antes de tocar em código: revisão profunda do Anel 0, "nunca
suponha nada". O achado original do 12.20 (eixo 03 não audita astype.h/
convert.h) virou 4 frentes depois da verificação — duas a mais que ninguém
tinha registrado.

Frente 1 (ops_window.h ausente): as 16 funções de rolling nunca entravam na
composição de headers do eixo, apesar de encaixarem perfeitamente no padrão
existente. Resultado 🟩 direto ao adicionar.

Frente 2 (o achado que a revisão descobriu, não o texto original): rodando o
eixo antes de mexer em qualquer coisa, bool tinha 47% de 🟨 — muito acima dos
outros dtypes. Investigando por que, achei que as funções que o Lua realmente
usa em massa (smaug_bool_series_and/or/xor/count_true/any/all) vivem em
smaug_numeric.h, não em smaug_bool.h — e a composição de headers.bool não
incluía numeric.h, então essas 7 funções nem eram buscadas, sumiam do relatório
sem aparecer nem 🟩 nem 🟨. As de bool.h sem "_series_" são primitivas cruas
corretamente sem caminho Lua (arrays, não Series). Corrigido: 19→42 funções
auditadas, 🟨 cai para 21% — e o que sobra é exatamente o esperado.

Frente 3 (astype.h, o achado original): 12 funções smaug_{origem}_to_{destino}
carregam dois dtypes no nome — não cabem no padrão "1 dtype + sufixo" do eixo.
Encaixar na tabela por-dtype confundiria. Seção própria: matriz origem→destino.
12/12 🟩.

Frente 4 (convert.h, decisão consciente de excluir): as 6 funções são
infraestrutura interna entre .c files, zero no cdef, nunca deveriam aparecer no
espelho C↔Lua. Incluí-las marcaria 🟨 permanente — ruído, não achado. Nota
textual no cabeçalho do eixo, não seção nova.

Cobertura do eixo: 209→258 funções, zero ruído novo.

Achado colateral da mesma revisão, registrado à parte como 12.30 (não é do eixo
03): smaug_io.h promete "checar smaug_io_last_error()" para escrita, mas essa
função não existe em lugar nenhum — nem protótipo, nem definição, nem cdef. Li
smaug_io.h e smaug_io_internal.h por inteiro para confirmar. A leitura tem
mecanismo rico (make_error() preenche t->error consistentemente, com cuidado
até no caso de OOM ao copiar a própria mensagem); a escrita (smaug_write_csv/
smaug_write_json, ambos lidos por inteiro) descarta errno do fopen/fwrite e
retorna só -1 — mesma estrutura idêntica nos dois. Correção não atacada agora
(mudaria assinatura pública), só registrada para decisão futura.

---
## 2026-07-20 — 12.19 (metade SRCS): fontes C descobertas por glob nos 3 scripts

Continuação do 12.29. O 12.19 apontava 5 listas duplicadas de SRCS/C_TESTS; o
levantamento mostrou que são duas naturezas distintas, e só uma é limpa de
resolver por descoberta automática.

SRCS (fontes C) — as 3 cópias agora descobrem sozinhas: build.sh já era glob
(12.29), Makefile passou a `$(wildcard src/*.c)`, make_coverage.sh deriva por glob
bash + basename. Isso mata o risco central do achado: a cópia de coverage era a
perigosa — esquecer um `.c` novo lá deixava o build verde enquanto o arquivo
reportava 0% e ficava fora do selo. Agora coverage descobre igual ao build.
Provado: um .c fake foi pego pelos três sem editar nenhuma lista.

C_TESTS (binários de teste) — deixado registrado, não resolvido. O não-óbvio: ao
contrário das SRCS (todas idênticas), os testes têm categorização semântica —
test_allocfail exige -Wl,--wrap, test_stress é categoria à parte. Um glob puro
pegaria os 13 mas quebraria a compilação especial. Unificar exigiria um manifesto
de categorias (bem mais invasivo), e o risco é menor: esquecer um teste na lista
apenas não o roda (o contador de checks muda, visível), não mente sobre cobertura.
Registrado no 12.19 para fazer junto do item 10.

Verificado que Makefile ($(wildcard)) e coverage (glob) produzem exatamente os 12
fontes atuais. Cobertura reproduzida: 98.81% linha / 94.71% branch-alvo.

---
## 2026-07-20 — 12.27: OOM parcial em dataset_to_table não vaza mais (L1)

Achado (L1): `dataset_to_table` (io/csv.lua) alocava, por coluna, o nome
(ffi.C.malloc) e a série C (smaug_*_create) num laço. Um OOM no meio — create
devolve nil → error — deixava o parcial vazando: `t` nunca chegava ao caller para
ser liberado por free_table_lua. Afetava to_csv e to_json (reusa o mesmo
_dataset_to_table). Assimétrico com o rigor do C, que protege OOM parcial
(str_slots_reserve_one). Raro (só sob OOM), mas real, e num núcleo que tem
allocfail justamente para esses caminhos.

Correção: o laço passou a rodar dentro de um pcall; em falha, free_table_lua
libera o parcial e o erro original é repropagado. O não-óbvio foi verificar que
free_table_lua já era seguro sobre tabela parcial — o ffi.fill(columns, 0) zera
tudo no início e o free pula campos nil, e cada série só é atribuída a
columns[i] após create bem-sucedido. Então não precisou de bookkeeping extra de
"quantas colunas alocadas": free_table_lua(t, ncols) sobre o parcial já é
idempotente. free_table_lua virou forward declaration (dataset_to_table a usa e
vem antes dela no arquivo).

Uma correção no ponto compartilhado cobre os dois I/O (to_json herda —
confirmado). Provado com injeção: erro no :get da 2ª coluna (1ª já alocada) →
capturado, parcial liberado sem crash, erro repropagado, heap íntegro depois.
Guard permanente em test_csv. Único dos colaterais desta leva com correção de
comportamento (12.28/12.29 eram auditoria). Lua puro.

---
## 2026-07-20 — 12.29: descoberta automática de fontes C (A3)

Achado (A3): o eixo 14 (thread-safety) iterava uma lista fixa de `src/*.c`. Um
`.c` novo não-listado não era auditado — passava em silêncio. O levantamento
revelou que o problema era maior que o registrado: **três** listas de fontes, e
as duas hardcoded eram só do Linux (`build.sh` `SRCS` e o eixo 14), enquanto o
`build_win.ps1` já descobria via glob. A do `build.sh` era mais grave — um `.c`
novo nem compilaria no Linux até editarem a lista. Optamos pelo escopo completo:
alinhar o Linux ao Windows nas duas.

Solução: `build.sh` usa `SRCS=(src/*.c)` (glob) e grava a lista descoberta em
`build/SOURCES`; `build_win.ps1` grava o mesmo arquivo (normalizado para forward
slash, formato único nos dois OS). O eixo 14 lê `build/SOURCES` — a lista fresca
do que foi de fato compilado, sem defasagem — com fallback ao MANIFEST versionado
quando rodado standalone, e falha-visível se nenhum der lista.

O não-óbvio: por que `build/SOURCES` e não ler o MANIFEST direto. O parity roda
ANTES do MANIFEST ser regenerado no build; ler o MANIFEST daria a lista do ciclo
anterior (defasagem de 1 build — um `.c` novo só auditado na segunda rodada).
`build/SOURCES` é gravado pelo mesmo glob que compilou, no início do build →
o eixo audita exatamente o que foi construído, agora.

Achado corrigido junto: o eixo 14 detectava global mutável (🟥) mas retornava
exit 0 — nunca marcava FALHOU no runner. Verifiquei que era pré-existente (o
único os.exit era a salvaguarda nova). Alinhei ao eixo 15: `os.exit(1)` se há
global. Confirmado que isso não quebra o build — `parity.sh` sempre retorna 0,
só destaca o eixo no relatório —, preservando a política "parity é indicador
permanente". Provado nos dois sentidos: `.c` com global → 🟥 exit 1; limpo → 0.

Nenhum C ou runtime tocado. `build/SOURCES` é gitignored (efêmero).

---
## 2026-07-20 — 12.28: eixo `15_abi_layout`, sincronia cdef↔header verificada

Achado (A-FFI): o `cdef` do `ffi_loader.lua` replicava à mão o layout das structs
dos headers, sem nada que verificasse a sincronia. Um campo renomeado, reordenado
ou com tipo trocado num lado só não quebra o build — vira leitura de memória
deslocada (o LuaJIT lê bytes errados). Mesma classe do A3 (eixo 14): coerência
presumida, não verificada.

**A decisão de desenho é o não-óbvio aqui.** Plano inicial: cruzar `ffi.offsetof`
do cdef com os offsets reais que o C imprime — verificação do layout COMPILADO
(D2). Isso exigiria o Lua rodar um binário C e ler stdout (`io.popen`), padrão sem
precedente no projeto e frágil (PATH, portabilidade). Antes de montar essa ponte,
verifiquei o pressuposto: **há packing custom?** Não — nenhum `#pragma pack`,
`__attribute__((packed))`, bitfield ou `aligned` nos headers nem no cdef. Sem
isso, C e LuaJIT-FFI usam o MESMO alinhamento padrão, então sequência textual
idêntica de (tipo, nome) ⟹ layout idêntico em memória (confirmei empiricamente:
sizeof=88 e todos os offsets batem byte a byte entre gcc e ffi.sizeof). Ou seja,
a comparação textual (D1) é tão forte quanto a compilada NESTE projeto — sem a
ponte frágil. Lição: por pouco não montei a solução complexa presumindo que era
mais segura; a verificação mostrou a equivalência.

Salvaguarda contra a única brecha do textual: o eixo re-checa a ausência de
packing a cada run. Se algum dia entrar `#pragma pack`, ele falha avisando que a
comparação textual deixou de bastar — o teste é consciente do próprio pressuposto.

Detalhe que exigiu cuidado: resolver typedefs antes de comparar. O primeiro run
acusou `series_dt` como divergente (`smaug_mask_t*` no header vs `uint8_t*` no
cdef) — falso positivo, pois `smaug_mask_t` é `typedef uint8_t`. Em vez de
presumir, verifiquei e adicionei resolução de alias. Ficou o achado colateral: o
cdef usa os dois nomes para o mesmo tipo (inconsistência de estilo, inofensiva em
layout) — registrado no 12.28 para limpeza futura.

Escopo: 10 structs que cruzam a fronteira por layout (opacas como
`smaug_hash_table_t` ficam de fora — o Lua nunca lê seus campos). Testado nos dois
sentidos (pega divergência → exit 1; sincronizado → exit 0). Registrado em
`parity.sh` e `parity.ps1`. Parity 14→15 eixos. Nenhum C ou runtime tocado —
puramente auditoria.

---
## 2026-07-19 — 10.5 Passo A: `core/keys.lua`, chave de igualdade com int64 exato (L2)

Achado (L2): o padrão `type(v)..":"..tostring(v)` sobre `series:get(i)`, repetido
em 6+ call-sites (unique/nunique/value_counts/mode/isin/duplicated + join/groupby
+ row_dup_key), propaga a mesma perda do 9.1 — `get()` reintroduz o double na
saída. Dois int64 distintos > 2^53 colapsavam na MESMA chave: **join casava
linhas erradas, groupby/unique/value_counts fundiam, isin/duplicated erravam** —
em silêncio, sem teste que guardasse. Provado com 9007199254740992 vs ...993.
Pior que os 10.6/10.7: lá o valor errado é visível; aqui as linhas se fundem
DENTRO de uma agregação, e a chave ainda era guardada como VALOR no resultado
(groupby/value_counts/join), degradando o int64 no próprio resultado.

**A pergunta que definiu o desenho (não-óbvio): "onde isso pertence?"** A
arquitetura respondeu, não a conveniência. P3 (responsabilidade única) +
precedente: "canonicalizar valor de coluna para comparar" já vive no Anel 0 para
ordenação (`smaug_multi_argsort`), e `smaug_hash_table_t` já está reservado lá
"para GroupBy futuro". A chave de igualdade pertence ao mesmo anel. Logo isto é um
**Passo A** (correção na camada acessível), como no 10.6 — não o destino.

Diferença vs Passo A do 10.6: lá a guarda **recusa** int64 > 2^53 (falha visível);
aqui **preserva** via `get_raw`. Escolha deliberada — preservar alinha com o
*destino* do 10.6 (Passo B preserva exato), e a chave de igualdade não tem por que
recusar o que o buffer já guarda certo.

**Desenho de `core/keys.lua`** (`encode`/`value`/`encode_value`): o prefixo da
chave é o **dtype da coluna**, não o `type()` do valor Lua. Descoberto na
verificação do isin: o mesmo int64 chega como `number` via get() e `cdata` via
get_raw() — prefixar por type() faria a lista crua do isin (number) divergir da
série (cdata) e quebrar o casamento. Prefixar por dtype (fixo, conhecido) faz
`int64:100` bater dos dois lados. Uma canônica só; `encode` delega a
`encode_value`.

Coesão/limpeza no mesmo passo: eliminados `dup_key` (código morto, exposto em
`I.dup_key` sem consumidor), a 3ª cópia da canonicalização em `row_dup_key`
(DataSet), e o `mode` que usava `tostring` sem prefixo de tipo (colisão latente
1 vs "1") e o chamava 2×.

Passo B (registrado no Roadmap 10.5): descer a canonicalização/hash ao Anel 0
(usando o `smaug_hash_table_t` reservado) fecha o P3 — conceito num anel só, junto
do `multi_argsort`. O `keys.lua` já é o ponto de plugue: substitui o corpo de
`encode`/`value` sem tocar call-sites.

Lua puro (nenhum C tocado). Guards permanentes: `test_keys` (18), `test_relational`
(+5), `test_predicates` (+7). Fedora `--all` verde: Valgrind-clean, parity 14/14,
cobertura de linha 98.82%. Colaterais registrados (12.27/12.28/12.29): OOM parcial
no dataset_to_table (L1), sincronia cdef↔header sem verificação (A-FFI), eixo 14
com lista hardcoded (A3).

---
## 2026-07-14 — 12.6 + 12.2: uma travessia FFI por `get()`

**12.2:** removida a linha comentada `-- smaug.read_parquet = ...` do
`init.lua`. O Parquet já está registrado no `ARCHITECTURE.md` (marco 1.5, depois
de `.smg` e Excel); o comentário era redundante e sugeria algo meio-feito.

**12.6** — o registro dizia *"`get_value` passa nil como status (assimetria; sem
bug)"*. A revisão (o Gui pediu "a solução ideal, não o que já existe") mostrou
que o diagnóstico do item — e o meu primeiro — estavam errados.

**Não eram 2 padrões, eram 3:**
- f64/i64: `get(c, i, nil)` — descartam o status;
- str: `ffi.new("size_t[1]")` **por chamada** (o len);
- dt/bool: `ffi.new("smaug_status_t[1]")` **por chamada** (o status).

**Medido: o `get()` variava 50x entre dtypes** (300k acessos: f64 0.0018s vs
string 0.0950s). O item só falava do dt; string e bool eram os piores, e ninguém
sabia.

**Meu primeiro diagnóstico estava errado.** Propus "uniformizar por baixo" —
descartar o status no dt, como f64/i64. Isso é jogar informação fora para ganhar
velocidade. O Gui não aceitou o remendo, e a análise correta é a inversa:

> A alocação nunca foi o problema — alocar **por chamada** era. E o status não é
> custo: é a resposta que já estávamos pagando uma segunda travessia FFI
> (`is_null`) para obter.

O `methods.get` fazia duas travessias: `is_null(...)` perguntava "é null?" e
`get_value(..., nil)` **descartava** a mesma resposta. O CONTRACT chama isso de
"Shape 1: valor + status anulável" — o Anel 0 desenhou certo; o Anel 1 é que não
usava.

**Design:** out-param reusado (upvalue no `_types.lua`) + o status traduz null →
`nil`. Uma travessia. O `is_null` sai do `methods.get`; o `check_index` fica (a
mensagem dele, com `Err.describe`, é melhor que um nil silencioso). O `get_raw`
mantém o `is_null` explícito — devolve cdata cru, não passa pelo `get_value`.

Ganho medido (300k `s:get(i)` pela API pública):

| dtype | antes | depois | ganho |
|---|---|---|---|
| string | 0.0950s | 0.0079s | **12x** |
| bool | 0.0866s | 0.0084s | **10.3x** |
| datetime | 0.0451s | 0.0083s | **5.4x** |
| float64 | 0.0018s | 0.0013s | 1.4x |
| int64 | 0.0078s | 0.0071s | 1.1x |

Os 5 dtypes agora na mesma faixa (0.0013–0.0084s); antes havia 50x de spread.

**Thread-safety (relação com o CONTRATO 11):** os buffers são upvalues **Lua**,
não globais **C**. Lua não é thread-safe por natureza — cada thread tem seu
state, logo seu buffer; e são escritos e lidos na mesma expressão, sem yield
entre os dois. Não é o caso do 12.5, onde o global vivia no C e a janela era o
`qsort` inteiro (segfault provado).

Lua puro. Fedora `--all`: Valgrind 0, parity 14/14, suites de acesso intactas
(`test_access` 127, `test_dt` 271, `test_str` 272, `constructors` 343).

---
## 2026-07-14 — 12.3: datetime no to_csv/to_json (era crash, não "decidir")

O item pedia *"decidir: fechar ou registrar pós-1.0"*. Reproduzido: **crash**.
`to_csv_mem` e `to_json_mem` morriam com coluna datetime —
`attempt to get length of local 'v' (a number value)`. Não havia o que decidir:
API pública quebrada.

**A causa não era "column_t sem datetime".** Era incoerência do Anel 3: o mapa de
dtype no `dataset_to_table` já traduzia datetime → `"string"`, mas entregava a
**coluna datetime crua**. O C recebia a promessa de string e o laço fazia `#v`
num `epoch_ms`.

**Fix:** converter via `astype("string")` antes de montar a table — que já produz
ISO 8601 (mesmo formato do `smaug_dt_format`). **Uma correção, dois formatos**: o
`json.lua` reusa o `dataset_to_table`. Sem mudança de ABI.

Round-trip de **valor** preservado (testado): `astype("datetime")` devolve o
epoch_ms exato. O **tipo** não sobrevive — e isso é do formato: CSV não tem
tipos, JSON não tem *date*. Registrado no **CONTRATO 9**, que é a tabela por
formato. Não avisa: seria ruído em toda escrita de data, e o dado está intacto.

Testes: `test_csv` 130→**138**, `test_json` 43→**47** (o crash, o ISO no output,
round-trip de valor, NA em datetime sobrevivendo, e categorical como controle —
ele também está fora do `column_t` e já funcionava, porque o `get` dele devolve
string).

**Dois achados colaterais, medidos e registrados** (não tocados aqui):

- **12.25** — o `read_csv` **já infere 3 dtypes** (`try_bool`→`try_i64`→`try_f64`).
  O caso que ele recusa (`2024-03-15`) é o **único não-ambíguo** — ISO 8601 é
  não-ambíguo por design, enquanto `03/04/2024` (mar ou abr?) corretamente não é
  inferido. Ou seja: o critério atual não é "evitar ambiguidade". Consequência: o
  Smaug escreve ISO e não lê de volta — o mesmo critério que classificou o JSON
  como bug no 12.21, aqui em tipo (não em valor). Muda contrato público do
  reader: precisa de design próprio.
- **12.26 — prioridade alta:** zeros à esquerda **destruídos** na inferência, em
  dados BR (o alvo do projeto). CEP `01310100` → `1310100`; **CNPJ
  `00000000000191` → `191`**; telefone `011999998888` → `11999998888`. E o
  round-trip do próprio Smaug quebra: escrever a string `"01310100"` e ler de
  volta devolve `1310100` (int64). Sem aviso. É pior que o 12.25: ali se perde o
  tipo (recuperável); aqui se perde o **dado**.

Fedora `--all`: Valgrind 0, linha 98.81%, parity 14/14.

---
## 2026-07-14 — 12.24: os `select` eram essenciais — o item estava errado

O Gui pediu review antes do código. O review derrubou o item — e o erro era meu.

O 12.24 estava registrado como cosmético: *"7 guards redundantes; trocar o texto
da justificativa"*. **Reauditando neste tree, 4 dos 7 SEGFAULTAM sem o guard:**
`dt_select`, `f64_select`, `i64_select`, `str_select`.

**Por que a auditoria do 12.18 errou:** o guard do `select` ocupa duas linhas —
`if (...)` numa, `return NULL;` na outra. Meu script removia **uma**. O
`return NULL;` ficava órfão e passava a executar **sempre**: a função virava
`return NULL` incondicional, nunca crashava, e era classificada como redundante.
**Artefato do harness, não do código.**

Consequência: **não eram 6 guards essenciais, eram 10.** O 12.23 tratou 6; os 4
`select` escaparam pelo meu erro de medição. E se este item tivesse sido
executado como registrado, eu teria "corrigido o texto" de 4 guards essenciais —
trocando uma justificativa falsa por outra, e deixando 4 segfaults destrancados.

O corpo do `select` toca os três ponteiros direto: `create(a->size)`,
`cond->null_mask[i]` no laço, e `b` quando `cond[i]` é false. Cinco ramos, nenhum
decorativo.

Entregue:
- **Os 4 `select` viraram teste**, cobrindo os **5 ramos** do `||` (`!cond`,
  `!a`, `!b`, `cond->size != a->size`, `a->size != b->size`) + controle positivo.
  `test_ops_edge` 280→**292**, `test_datetime_c` 456→**462**, `test_string`
  126→**132**. **20 exclusões removidas** (148→128) — 4 guards × 5 ramos.
- **Os 3 `coalesce_scalar` são mesmo redundantes** (confirmado: o `clone(NULL)`
  devolve NULL e o `if (!r)` barra). Mantêm o `COV-EXCL-BR`, agora com
  justificativa **verdadeira**: *"redundante — o clone barra; auditado, remover
  não crasha. Defesa em profundidade, não a única proteção."*
- A frase **"o frontend valida antes" sumiu do Anel 0** — era o veículo que
  propagou a exclusão indevida entre dtypes.

| | 12.23 | **12.24** |
|---|---|---|
| exclusões | 148 | **128** |
| branch bruto | 91.49% | **91.93%** |
| linha | 98.71% | **98.81%** |
| branch-alvo | 94.66% | 94.68% |

Desde o 12.18: **164 → 128 exclusões**, bruto **91.13% → 91.93%**. O alvo mal se
moveu — ele não distingue esconder de cobrir. O bruto é a métrica honesta.

**CONTRATO 10** ganhou a lição: *"auditoria não se aceita sem verificar o
harness"*. Um falso negativo em auditoria de segurança é pior que não auditar —
produz confiança sem base.

**Verificado:** deletar o guard do `f64_select` agora dá SIGSEGV no teste.

Fedora `--all`: Valgrind 0, parity 14/14.

---
## 2026-07-14 — 12.23: os 6 guards essenciais viram teste

Execução do que a auditoria empírica do 12.18 achou: seis guards de fronteira
**pública** que, removidos, causam **SIGSEGV** — não são defesa redundante como
os do `coalesce_scalar` (onde o `clone(NULL)` barra antes). Estavam todos
`COV-EXCL-BR` com *"o frontend valida antes"*, contra o CONTRATO 10.

Auditoria **refeita neste tree** antes de agir (as linhas mudaram com o 12.5):
os 6 reconfirmados, um a um, removendo o guard e chamando com `NULL`.

| guard | suíte | checks |
|---|---|---|
| `dt_clone`, `dt_coalesce` | `test_datetime_c` | 450 → **456** |
| `f64_coalesce`, `i64_coalesce` | `test_ops_edge` | 272 → **280** |
| `str_coalesce_scalar`, `str_coalesce` | `test_string` | 118 → **126** |

Cobertos **todos os ramos**, não só o `NULL`: os três do `||` (`!self`,
`!other`, `size` divergente) e o `!value && len>0` do `str_coalesce_scalar` —
mais um controle positivo em cada, para provar que o guard não passou a rejeitar
entrada válida.

**16 exclusões removidas** (164→148): cada `||` de três condições conta 3 ramos.

O número que importa:

| | antes | depois |
|---|---|---|
| branch-alvo | 94.66% | 94.66% — **igual** |
| **branch bruto** | 91.13% | **91.47%** |

O **alvo não distingue esconder de cobrir** — foi o ponto do 12.18, e aqui se
confirma do outro lado: 16 ramos saíram da exclusão e entraram cobertos, e o
alvo não se moveu. O **bruto só sobe quando se cobre de verdade**. É a métrica
honesta.

**Verificação final:** deletei um guard essencial e rodei a suíte. Antes do
12.23: *"TUDO PASSOU"*, Valgrind 0, branch-alvo inalterado — ninguém percebia.
Agora: **SIGSEGV no teste**. Os guards estão protegidos.

Fedora `--all`: Valgrind 0, linha 98.71%, parity 14/14. Sobra o **12.24** (os 7
redundantes cuja justificativa é falsa) — registrado, não tocado.

---
## 2026-07-14 — 12.5: o Anel 0 é thread-safe (CONTRATO 11)

O registro dizia *"`g_sort_series` global em `ops_str` (single-thread: **sem
bug**)"*. O Gui pediu revisão crítica — "estamos construindo um motor". O
registro estava errado.

**Medido, não argumentado:**

| teste | resultado |
|---|---|
| 80 sorts **sequenciais** | 0 erros — o código está correto |
| **2 threads**, séries **diferentes**, 20k linhas | **SEGFAULT, 6/6 execuções** |
| `f64_sort` em 2 threads, 400 sorts | OK |

O mecanismo: a thread 1 termina e executa `g_sort_series = NULL` enquanto a
thread 2 ainda está **dentro** do `qsort`; o comparador lê `s->offsets[ia]` com
`s == NULL`. **Séries diferentes, nenhum dado compartilhado** — é o que qualquer
um faria ao paralelizar o sort de colunas distintas.

**Dois achados que mudaram o peso do item:**

1. `g_sort_series`/`g_sort_ascending` eram os **únicos globais mutáveis do Anel
   0 inteiro**. Todo o resto já era reentrante — provado. O Smaug era uma
   biblioteca thread-safe **com exatamente uma função que segfalta**: pior que
   ser declaradamente single-thread, porque é armadilha sem aviso.
2. A justificativa — *"o projeto não usa threads"* — é a **mesma classe de erro
   do CONTRATO 10** (*"o frontend valida antes"*): confiar no caller. O
   **projeto** não usa threads; o Smaug é **biblioteca**, e quem a usa decide.

**Decisão do Gui: o Smaug é thread-safe.** Isso transforma o item de "limitação
a registrar" em "bug a corrigir".

**CONTRATO 11** (`docs/CONTRACT.md`): nenhum estado global mutável no Anel 0;
`static const` permitido (imutável). Delimita o que **não** é prometido: mutação
concorrente da *mesma* série é responsabilidade do caller — a promessa é sobre o
engine, não sobre os dados do usuário.

**Implementação:** quicksort com contexto por parâmetro, substituindo
`qsort`+global nos dois usos (`argsort` e `rank`). Mediana de 3 (evita O(n²) em
dados ordenados), insertion sort abaixo de 16, recursão só na metade menor
(pilha O(log n) — medida: profundidade 22 para 100k, log₂≈17). `descending` =
ascending revertido em O(n), mais barato que carregar o flag na comparação.

Alternativas descartadas **com medição**, não por preferência:
- `qsort_r`/`qsort_s`: assinaturas divergem entre glibc, BSD e UCRT → `#ifdef` e
  comportamento por plataforma.
- `struct {ptr,len,idx}` + `qsort`: **1.45x mais lenta, 4x mais memória** (o
  qsort move 24B por swap em vez de 8B).
- Sort próprio: **empata em performance** (1.04x mais rápido no aleatório;
  0.66–0.95x nos patológicos: ordenado, reverso, todos-iguais, poucos-distintos)
  e produz **ordem idêntica** ao `qsort` nos 5 padrões. Bônus: garante o mesmo
  algoritmo em toda plataforma — o `qsort` da libc não especifica o seu.

**Guardião: eixo de paridade 14** (`14_thread_safety`). Auditoria estática, não
teste com threads — um teste de corrida exigiria `-lpthread` (e winpthreads no
Windows) e races são não-determinísticos: passariam por sorte. A ausência de
estado global é o que de fato garante o invariante, e é verificável no fonte.
**Detector validado**: injetei um global mutável e um `const` — pegou o mutável
(🟥, com arquivo:linha), ignorou o `const`.

Verificação final: o mesmo teste que segfaultava 6/6 roda **480 sorts em 2
threads sem um erro**. Fedora `--all`: Valgrind 0, `test_string` 118, parity
14/14.

---
## 2026-07-14 — 12.18: guards testados, não excluídos (CONTRATO 10)

O item pedia `COV-EXCL-BR` nos guards de `dt_get`/`dt_set`, "alinhando com o
12.17". A revisão (o Gui pediu três, cada uma mais funda) inverteu o item e
expôs um problema estrutural.

**1. Os ramos eram alcançáveis.** O `smaug_core.c` fecha **100%** de branch-alvo
com guards idênticos: o `f64_get` cobre `get(NULL,&st)` **e** `get(NULL,NULL)`; o
`dt_get` só cobria o segundo. O ramo descoberto nunca foi o `if (!s)` — era o
`if (status)` **dentro** dele. Excluir seria esconder ramo vivo.

**2. Não havia política.** Mesmo guard, mesma família `coalesce_scalar`, todas
públicas: i64/f64/str/dt **excluem**, bool **testa**. O bool só é diferente
porque no 10.8 eu quase excluí e corrigi no meio — foi acaso, não processo.

**3. A justificativa contradiz o princípio.** O CONTRACT declara *"nunca assume
que o caller validou"*; a exclusão diz *"o frontend nunca passa NULL"*. O guard
existe porque não confiamos; a exclusão o dispensa porque confiamos. E são
**símbolos públicos exportados** (`T` na .so) — o frontend Lua é *um* caller.

**4. A auditoria empírica** (removi cada guard, compilei, chamei com NULL):
**6 de 13 segfaultam** — são a única proteção, não defesa redundante. Estão
todos excluídos e sem teste. Com o guard removido: **a suíte passa, o Valgrind
acusa 0 erros, o branch-alvo não se move**. Os três guardiões do projeto passam
sorrindo enquanto a API pública segfalta.

**5. A raiz:** a justificativa foi **copiada entre dtypes sem verificar o código
embaixo**. `f64_coalesce_scalar` clona primeiro (o `clone(NULL)` barra → guard
redundante); `str_coalesce_scalar` mede o buffer tocando `self->size` direto
(→ SIGSEGV). Mesmo nome, mesma justificativa, naturezas opostas.

Entregue neste item:
- **3 testes** em `test_datetime_c` (447→450): `dt_set_null(NULL)`,
  `dt_append_null(NULL)` e `dt_get(NULL,&st)`. Branch-alvo **94.70% → 94.77%**
  com as **mesmas 165 exclusões**. Excluir daria o **mesmo 94.77%** com 168
  exclusões e zero proteção — o número é idêntico, o significado é oposto.
- **CONTRATO 10** (`docs/CONTRACT.md`): fronteira pública alcançável → testa;
  `COV-EXCL-BR` só para inalcançável verificado; **justificativa não se copia
  entre dtypes**, com o exemplo f64-vs-str no texto.

Registrados para execução própria (a pedido do Gui, fora deste item): **12.23**
(os 6 essenciais — segfaults esperando um refactor, 6 linhas de teste,
prioridade alta) e **12.24** (os 7 redundantes cuja justificativa é falsa e foi o
veículo da propagação).

Fedora `--all`: Valgrind 0, linha 98.76%, branch-alvo 94.77%.

---
## 2026-07-14 — 12.1: mensagens de I/O no padrão `smaug: <op> — <razão>`

O registro pedia só tirar o `"smaug"` duplicado. Reproduzindo as 6 mensagens de
I/O, apareceram três defeitos, não um:

1. **Duplicação:** o C prefixava `smaug_read_csv:` em cada `make_error` e o Lua
   somava `smaug: ` → `smaug: smaug_read_csv: ...`.
2. **Fora do padrão:** os *writers* já usavam `smaug: to_csv — falha ao...`; só
   os readers usavam `smaug_...:`. O padrão-alvo já existia no código.
3. **A mensagem mentia** (o mais grave): `read_csv_mem("")` reportava
   `smaug: smaug_read_csv: arquivo vazio` — nomeava a função **errada** (o
   prefixo era fixo no C, que não sabe se veio de `read_csv` ou `read_csv_mem`)
   e falava em "arquivo" quando a entrada é um buffer.

Fix pela separação de responsabilidade, espelhando o que os writers já faziam
(o C devolve `rc`, o Lua diz `smaug: to_csv — ...`):

- **Anel 0** emite só a **razão**: `"entrada vazia"`, `"sem colunas"`,
  `"não foi possível abrir '%s'"`. 15 `make_error` limpos (7 csv + 8 json). O
  `"arquivo vazio"` virou `"entrada vazia"` — neutro entre path e buffer.
- **Anel 3** emite a **op**: `table_to_dataset(t, op)` recebe `read_csv`,
  `read_csv_mem`, `read_json` ou `read_json_mem` das 4 entradas e formata
  `smaug: <op> — <razão>`. O `_table_to_dataset` (usado pelo json.lua) é alias
  direto, repassa naturalmente.

O consumidor do C puro não perde nada: ele sabe qual função chamou, e a razão é
o que ele não teria como saber.

Verificado que nenhum teste casava com o texto antigo — o contrato de mensagem
estava **sem teste nenhum**. Agora tem: `test_csv` 124→130, `test_json` 39→43
(ausência de duplicação, padrão `smaug: <op> —`, a op correta no `_mem`, "arquivo"
ausente quando é buffer, e a simetria reader/writer).

Fedora `--all`: Valgrind 0, coverage 98.76%/94.70%.

---
## 2026-07-14 — 12.21: vocabulário de não-finitos (CONTRATO 9) — CSV, JSON, Ring 0

O registro dizia "JSON writer emite `inf`, que é JSON inválido". A revisão pedida
pelo Gui — primeiro "a assimetria CSV/JSON faz sentido?", depois "leva pro Ring
0" — mostrou que o item era a ponta de um problema sem dono: **não havia regra
para não-finitos**, havia sedimentos.

O que a leitura do Ring 0 revelou (tudo medido):

1. **Contratos contraditórios.** `smaug_convert.h` promete formatar `NaN` como
   `"nan"` (fonte única, item 10.9). `smaug_csv.c:72` listava `"nan"` como
   sentinela de ausência. O writer escrevia valor, o reader lia ausência — o
   mesmo token, dois significados, dois arquivos que não se conhecem.
2. **A caixa decidia o destino do dado.** `BUILTIN_NA` é case-sensitive e o
   `strtod` não: `nan`/`NaN` viravam ausência (estavam na lista), `NAN` escapava
   para o `strtod` e virava **valor**. Três grafias, dois destinos.
3. **Round-trip quebrado no próprio produto.** `read_json` do Smaug não lia o
   `to_json` do Smaug (`{"v":inf}` → "erro ao parsear objeto").
4. **`na_values` era promessa vazia.** Documentado no `csv.lua` desde sempre; o
   struct C tinha os campos; o frontend nunca os populava.

**Correção de rumo minha, registrada:** eu havia proposto "não-finitos viram NA
em todos os formatos" como regra de consistência. Errado — isso joga fora a
distinção que o `null_mask` existe para manter, e alinha o Smaug com o pandas
justamente onde o Smaug é melhor (lá `NaN` *é* o missing; aqui não). O R, que
também distingue, escreve `NA` e `NaN` como literais separados: ler `"NaN"` como
ausência destrói uma distinção que o R preservou.

**CONTRATO 9** (novo, em `docs/CONTRACT.md`): *não-finito é valor; ausência é
`null_mask`. Cada formato preserva se comportar; se não comportar, converte e
**avisa** — nunca em silêncio.* A tabela por formato (CSV/JSON/Parquet/`.smg`)
está lá para os I/O futuros não reinventarem vocabulário — era a preocupação do
Gui com compatibilidade, e é o que transforma o fix num precedente.

Entregue:
- **CSV** (`smaug_csv.c`): `BUILTIN_NA` = `{"", "NA", "null", "N/A", "NULL"}` —
  sem `"nan"`/`"NaN"`. Round-trip agora é fiel (`NA`→NA, `NaN`→NaN, `inf`→inf) e
  todas as grafias caem no mesmo destino via `strtod`. **Mudança de contrato
  público**, testada nos dois sentidos.
- **JSON** (`smaug_json.c:589`): `v != v` → `!isfinite(v)`. NaN **e** ±inf →
  `null`. O Smaug voltou a ler o próprio output.
- **Anel 0**: `smaug_f64_count_nonfinite` (espelha `count_nonnull`) — o C não tem
  canal de aviso, então o Anel 3 consulta antes de serializar.
- **Anel 3** (`json.lua`): `warn` com a contagem exata ("3 valor(es) não-finito(s)
  viraram null"). NA não conta — ausência não é não-finito.
- **`na_values` implementado** no `csv.lua` (`apply_opts`, com anchor de GC para
  o array de `const char*` e as strings Lua). Sem isso, tirar `"nan"` do
  `BUILTIN_NA` seria remover capacidade sem oferecer alternativa.

Testes: `test_io_c` 298→312 (`test_csv_nonfinite_values`: as 6 grafias +
`na_values` opt-in; `test_csv_na_values` atualizado — fixava o contrato antigo),
`test_alloc` 243→247 (`count_nonfinite`), `test_csv` 107→124 (round-trip,
grafias, vocabulário de ausência, opt-in), `test_json` 27→39 (null, round-trip,
aviso, e os dois casos que **não** avisam: sem não-finitos e NA puro).

Ring 0 + contrato público. Fedora `--all`: Valgrind 0, coverage 98.73%/94.70%.
**Windows obrigatório** (símbolo C novo + mudança de parser).

---
## 2026-07-14 — 12.22: contador unificado nas 9 suites restantes

Generalização do 12.7 (que corrigiu só `test_constructors`). Achado durante o
12.4: o padrão de `local n_ok`/`check` redeclarado por seção era sistêmico.

Verificação antes de aplicar (o 12.7 ensinou o que checar): (a) as cópias são
**idênticas** dentro de cada arquivo — então todas as chamadas resolvem para o
primeiro `check`; (b) todas as declarações são **top-level**, nenhuma aninhada em
`do...end` — remover não quebra escopo; (c) **um único `print`** por arquivo.
Só com as três confirmadas o fix é seguro e uniforme.

Ganhos de honestidade no relato:

| suite | antes | real |
|---|---|---|
| `test_str` | 66 | **272** |
| `test_categorical` | 97 | **299** |
| `test_relational` | 60 | **168** |
| `test_predicates` | 89 | **167** |
| `test_access` | 61 | **127** |
| `test_csv` | 64 | **107** |

Em `test_selection` (56), `test_reduce` (57) e `test_window` (122) o número não
mudou: ali a 2ª declaração estava no preâmbulo, não no meio do arquivo, então
quase todos os checks já caíam no mesmo contador. A remoção só tirou a
redundância.

Nenhum check novo foi escrito — a validação sempre foi real (cada `check` aborta
em falha). Só o número enganava. Total do relato Lua sobe de ~1958 para ~2465.

Lua puro. Fedora `--all` verde (18 suites, parity 13/13).

---
## 2026-07-14 — 12.12: chave desconhecida com sugestão ("você quis dizer X?")

**Um diagnóstico errado meu, corrigido pela verificação empírica.** Eu havia
concluído que interceptar o `__index` do DataSet quebraria o `has_column` —
raciocinando que ambos passam pelo mesmo ramo de "chave string desconhecida".
Errado: `has_column` é `self._columns[name] ~= nil`, acessa o campo `_columns`
diretamente e **nunca passa pelo `__index`** (o campo existe). Só descobri porque
o Gui pediu para ver o exemplo rodando em vez do argumento. Lição registrada: a
dedução sobre o próprio código não substitui executá-lo.

Verificação antes do martelo: apliquei o erro no `__index` como experimento e
rodei as 4 suites do DataSet — **430 checks passaram**, antes de escrever
qualquer teste novo. Grep no código e nos testes: ninguém dependia de
`df.chave_inexistente == nil`. Só então a mudança foi aprovada.

**Mudança de contrato deliberada** (decisão do Gui): chave desconhecida passa de
`nil` silencioso para erro. Alinha com "falha visível > acerto adivinhado" —
`df.vendass` (typo de coluna) falhava 3 linhas depois com um `nil` misterioso;
agora falha no ponto, sugerindo `vendas`. Chaves com `_` seguem devolvendo `nil`
(campos internos: `_columns`, `_c`, `_dtype`…).

**Implementação:** `Err.suggest(name, candidates)` + `Err.unknown_key(...)` em
`core/errors.lua` — não um quarto módulo, porque isto é mensagem de erro e o
`errors.lua` já é a fonte única desse domínio (verificado: não havia nenhum
helper de distância/sugestão no projeto). Levenshtein com early-exit (só importa
se está PERTO, não a distância exata); tolerância proporcional (2 para nomes >= 5
chars, 1 para curtos) para não sugerir "sum" para "abs"; normaliza `_` e caixa
antes de comparar, o que faz `group_by`, `groupBy` e `GROUPBY` caírem em
`groupby` com distância 0 — o caso mais comum de confusão de convenção.

Nos dois `__index`. No DataSet os candidatos incluem **as colunas reais** do
DataSet, além dos métodos: `df.vendass` sugere a coluna `vendas`. Nomes
distantes (`xyz`) erram sem sugestão — testado, incluindo que nomes de coluna
legítimos não recebem sugestão de método.

Testes: `test_access` 54 → 61, `test_core` 228 → 237 (sugestão certa, ausência de
sugestão para nome distante, `_interna` → nil, `has_column` intacto, métodos e
acessores reais intactos).

Lua puro. Fedora `--all` verde (Valgrind 0, parity 13/13, 18 suites incluindo
property-based e integração).

---
## 2026-07-14 — 12.10: aviso de separador suspeito no `read_csv` + `core/warn.lua`

Implementado o aviso passivo conforme a decisão já registrada: **não** detectar
nem escolher separador sozinho (esperto demais; falso-positivo pior que o
problema) — apenas iluminar quando o arquivo virou 1 coluna e os dados sugerem
outro `sep`. O usuário ignora se foi intencional.

**Promoção do `warn` a módulo (`core/warn.lua`).** O `warn` era `local` no
`core/series/init.lua` e só alcançava os submódulos da Series via a tabela `I`;
o `io/csv.lua` (Anel 3) não tinha acesso. Escrever um `io.stderr:write` direto
ali criaria um **segundo** canal de aviso — contra o "canal único" que o próprio
comentário do `warn` declara, e a mesma classe de duplicação que o item 11 (3
`cell_str`) e o 12.9 (26 `tostring`) mataram. Auditado antes de mover: havia
exatamente um canal e um consumidor (o aviso de int64 > 2^53), então a migração
é transparente — `I.warn` segue igual, `_core.lua` intacto, aviso do int64 sai
idêntico. Terceiro utilitário transversal, mesmo padrão de `display.lua`
(apresentação) e `errors.lua` (descrição-em-erro).

**Regra do aviso:** `ncols == 1` **e** o separador suspeito (`;`, `\t`, `|`,
exceto o que foi usado) presente em **todas** as amostras (header + até 5
valores, mínimo 2 amostras). O "todas" é o que evita o falso-positivo: um `;`
solto em texto livre (`obs = "a; b"`) não dispara — testado.

**Onde o hook mora (achado que evitou um bug):** nos pontos de entrada do CSV
(`M.read`/`M.read_mem`), **não** no `table_to_dataset`. Aquele é reusado pelo
`json.lua` (`csv._table_to_dataset`), então o hook lá dentro faria um
`read_json` de 1 coluna com `;` nos valores sugerir "verifique o separador" —
nonsense para JSON. Verificado na prática: `read_json` fica silencioso.

Testes em `test_csv` (55 → 64): caso-alvo `;` e `\t`, mais 5 casos que **não**
devem avisar (sep correto, CSV multi-coluna, 1 coluna legítima, `;` esporádico
em texto livre, e `read_json`). Captura de stderr trocando `io.stderr` pelo stub
(o objeto é userdata; não aceita atribuição de campo).

Lua puro. Fedora `--all` verde (Valgrind 0, parity 13/13, 121 arquivos).

---
## 2026-07-14 — 12.9: `core/errors.lua` — descrição segura em mensagens de erro

O registro dizia "`s:iat(i)` despeja a Series inteira no erro". A avaliação
profunda (pedida antes do aval) mostrou que o `iat` era só a porta mais fácil de
uma classe sistêmica: **`error("... " .. tostring(v))` com `v` do usuário dispara
o `__tostring` do objeto e despeja os dados na mensagem**.

Medido, não suposto:
- os **5 métodos públicos** de acesso vazavam igual (`s:get(s)`, `s:set(s,1)`,
  `s:is_null(s)`, `s:set_null(s)`, `s:get_raw(s)`) — não era exclusividade do iat;
- escala real: Series string 100k → 428 chars; **DataSet 20x1000 como índice →
  2459 chars** com o conteúdo das colunas. O truncamento do item 11 limitava mas
  não impedia (um DataSet largo é grande por definição);
- o padrão aparecia em 26 pontos; dos 8 testados onde o usuário pode passar
  objeto, **os 8 vazavam** (`view`, `take`, `astype`, `str:pad`, `str:rep`,
  `cat:get`, `cat:take`, `Series.new`).

Decisão (Gui): opção 3 — helper canônico, não fix por callsite (senão o furo volta
no próximo `error()` que alguém escrever). Criado **`lua/smaug/core/errors.lua`**
com `describe(v)`: número/bool/nil literais; string entre aspas truncada em 60
chars; cdata direto (int64 é curto e informativo); Series/CategoricalSeries/
DataSet identificados **pela estrutura** e renderizados como
`<Series 'x' (int64, len=200)>` — sem chamar o `__tostring`, que é justamente o
que despejaria os dados; outra table vira `"table"`.

Contrato: **descrição-em-erro ≠ apresentação**. `display.lua` responde "como o
usuário vê este valor numa tabela" (e deve mostrar o dado); `errors.lua` responde
"como referenciar sem vazar". Separação deliberada, mesma lógica de fonte única do
item 11.

Escopo definido por leitura, não por grep: 3 dos 26 pontos ficaram de fora por
serem seguros (`_selection.lua:115` usa `x._dtype`, string interna, com o `if`
acima garantindo que `x` é Series; `_core.lua:73/117` usam cdata int64 já
type-checado, onde o número É a informação). `SeriesAt.__call` ganhou guarda:
`s:iat(3)` é açúcar de `s.iat(s, 3)` — o proxy vira `self`, a Series cai em `i` e
o `3` é descartado; agora erra com "use s.iat[i]" em vez de tratar a Series como
índice. `s.at(i)`/`s.iat(i)` com número seguem suportados (contrato testado em
`test_selection` preservado).

Resultado: 2459 → **109** chars no pior caso; os 5 métodos, 181 → 87; os 8 pontos
de risco, todos limpos. Testes novos em `test_selection` (orientação do iat + a
classe inteira: nenhum método de acesso vaza valores).

Lua puro. Fedora `--all` verde (Valgrind 0, parity 13/13, 120 arquivos).

---
## 2026-07-14 — 12.11: `Series:nrows()` — decisão de não fazer

O sub-item pedia `methods.nrows = methods.len` na Series ("alias faltando").
A leitura do código mostrou que o gap contradiz uma convenção deliberada já
registrada no eixo 08 de paridade: *"Series tem len+size (size = alias de len);
DataSet tem nrows+ncols"*. `nrows` é vocabulário tabular — uma Series não tem
linhas, tem elementos; `len`/`size` é vocabulário de sequência. Não é ausência,
é separação de domínio. Pandas segue a mesma linha (`Series` não tem `nrows`;
contagem de linhas é `DataFrame.shape[0]`).

Adicionar o alias violaria a convenção que o próprio parity audita, e exigiria
reescrever a regra do `08_naming.lua` — doc e código passariam a divergir do
conceito. Decisão (Gui): não fazer. Sub-item encerrado sem código; nenhum
arquivo de código tocado.

---
## 2026-07-14 — 12.4: dedup do `tostring` + guard de unicidade em `from_codes`

O cosmético registrado era `tostring(v)` chamado 2× na normalização de níveis do
`from_codes` (içado para um local). Durante o step, achado maior: `from_codes`
**não validava unicidade dos níveis**. Dois níveis que normalizam para a mesma
string — duplicata literal `{"a","a"}` ou colisão de tipo `{1,"1"}` —
sobrescreviam o `lmap` silenciosamente, deixando dois códigos apontando para o
mesmo nível: categorical corrompido, sem aviso.

Decisão (Gui): não faz sentido arrumar só o visual e deixar o furo. Adicionado
guard falha-visível — erro em nível duplicado após normalização, com os dois
índices. O path de construção por dados já dedupe naturalmente (via `level_map`
no append); o furo era exclusivo do `from_codes`. Teste cobre os dois casos de
colisão + controle positivo (níveis numéricos distintos normalizam sem colidir).

Achado colateral registrado (12.22): o padrão de `n_ok` subcontado do 12.7 é
sistêmico — 9 outras suites concatenadas têm o mesmo relato enganoso. Não tocado
neste step (fora de escopo); registrado para varredura própria.

Lua puro. Fedora `--all` verde (parity 13/13).

---
## 2026-07-14 — 12.7: contador de checks unificado em `test_constructors`

O arquivo é 4 suites concatenadas; cada uma redeclarava `local n_ok = 0` +
`local function check` no seu preâmbulo. Como são `local` top-level, cada uma
sombreava a anterior, e o único `print` no fim via só o contador da última seção
→ headline "98 checks" quando 343 rodavam de fato. A validação sempre foi real
(cada `check` aborta em falha); só o número enganava — mesma família do "teatro
de números" do 12.8.

Fix: contador único. Removidas as 3 redeclarações de `n_ok`/`check` (os corpos
eram idênticos, então todas as chamadas resolvem para o `check` da linha 14); os
demais preâmbulos de seção (`require`, `Series`, `approx`, `NA`) ficaram intactos
— fora do escopo do 12.7. Escolhido contador único (não print-por-seção) porque o
harness do `build.sh` espera uma linha `OK — N checks...` por suite.

Lua puro. Fedora `--all` verde (parity 13/13). Headline agora reporta 343.

---
## 2026-07-13 — 11: Ergonomia REPL (display canônico + __tostring universal)

Análise profunda comparando com pandas revelou que o item era maior que
"faltam __tostring": havia **valor quebrado na apresentação** e três formatações
de célula divergentes. Provado rodando: int64 `2^53+1` saía `9.007…e+15` (não o
valor no buffer); `3.14159265358979` saía `3.1415926535898` na Series e `3.142`
no DataSet; texto acentuado desalinhava (largura por byte).

**Fonte única `lua/smaug/core/display.lua`** consolidando o que eram 3 `cell_str`
divergentes + 5 `pad` duplicados:
- `cell_str`: int64 exato (via `cell_of`->`get_raw`, cdata cru — nunca o double de
  `get()`), float `%.6g` de apresentação (distinto da serialização `%.17g` do
  10.9, contrato "display != serialização"), NaN/±inf normalizados ("nan"/"inf"/
  "-inf", eliminando divergência de libc no display).
- `dwidth`: largura em codepoints UTF-8, não bytes — alinhamento correto com
  acento/unicode.
- `pad`+`align_for`: número à direita, texto à esquerda (estilo pandas).
- `plan_rows`: truncamento cabeça+cauda com marcador "..." no meio (só nas vistas
  humanas `to_string`/`__tostring`; `to_markdown` não trunca — é exportação).
Os 6 consumidores religados; `I.cell_str` (export órfão) removido.

**11.1/11.2 — __tostring universal:** CategoricalSeries (valores + rodapé de
categorias) e os 8 proxies (`.str`/`.dt`/`.at`/`.cat`, Series rolling/expanding,
DataSet groupby/rolling) ganharam `__tostring` — nenhum vaza mais `table: 0x…`.

**11.3 — invariante + auditoria:** eixo de parity **13** (`13_tostring`) verifica
estaticamente que cada objeto exposto tem `__tostring`; roda a cada build (11
objetos, todos verde).

Item 11 é **Lua puro** (nenhum C tocado): selo Fedora `--all` (Valgrind 0,
parity 13/13). **Fechado por equivalência Fedora; Windows dispensado** — a única
superfície de divergência libc (`%g` em nan/inf) foi eliminada por construção
(cell_str intercepta nan/±inf como literais antes de qualquer `%.6g`/`%d`,
guardado por teste no Fedora); o resto é Lua puro ou LuaJIT-interno, e o eixo 13
é Lua puro.

---
## 2026-07-13 — 10.8: `BoolSeries` — coerência de caminho com o Anel 0

O achado 2026-07-02 mirava loops Lua no `boolseries.lua`. A leitura do código
atual reenquadrou o item: o caminho bool **vivo** virou a `Series<bool>`
struct-based (dtype de primeira classe, delega `take`/`filter`/`argsort`/`sort`/
`ffill`/`rank`/`count_nonnull` ao Anel 0 via descritor), e o `boolseries.lua`
(par de arrays crus, "legada") ficou **órfão** — nenhum `require` em `lua/`,
`tests/` ou `scripts/`, nenhum caller de `_own`/`from_lua_arrays`, nenhum teste.
Confirmado por leitura caso-a-caso, não por grep. A "questão arquitetural" do
roadmap (delegar às mesmas primitivas vs. encapsular o struct) já estava
respondida no código: `Series<bool>` venceu; a tensão "dois caminhos" existia só
porque o cadáver não fora removido.

Três incrementos, cada um selado antes do próximo:

- **(a) Remoção do código morto.** Deletado `lua/smaug/core/boolseries.lua`.
  Coverage **idêntico** pós-remoção (98.72%/94.68%) — prova de que nunca era
  executado. As primitivas C raw (`smaug_bool_and/or/xor/not/count_true/any/all`
  sobre `uint8_t*`) **permanecem**: não são código morto, são o motor que as
  `smaug_bool_series_*` reusam (`smaug_bool_series_and` → `smaug_bool_and`).
  Removê-las duplicaria a lógica Kleene 7× inline — o oposto do objetivo. O que o
  comentário do `ffi_loader` chamava de "legada até a Fase 4" era a exposição ao
  Lua (via `BoolSeries`), não a existência em C.

- **(b) `describe(bool)` → Anel 0.** Trocado o loop Lua que recontava trues
  posição-a-posição por `self:count_true()` (`smaug_bool_series_count_true`).
  Nulos já vinham de `count_nonnull`. Guardado por `describe count_true/false`
  (`test_constructors`) e DataSet describe bool (`test_core`).

- **(c) `fillna(bool)` → Anel 0.** Era o único resíduo real no caminho vivo:
  fazia `Series.new` + loop `set()` enquanto i64/f64/dt/str delegavam a
  `coalesce_scalar` (família 10.6) — bool ficara de fora de propósito. Criada
  `smaug_bool_coalesce_scalar` (espelho exato do `smaug_i64_coalesce_scalar`:
  `clone` + preenche nulos com value, revalida). `value` normalizado a 0/1 nas
  **duas pontas** — Lua passa `value and 1 or 0` (sem depender da coerção
  implícita boolean→número do LuaJIT) e o C faz `value ? 1 : 0` (engine não confia
  no caller). `fillna(bool)` perde o loop e delega via descritor, mantendo a
  guarda de tipo com erro claro. Teste C novo `test_coalesce` em
  `test_bool_lifecycle` (NA→value, não-nulos intactos, origem preservada,
  sem-NA no-op, vazia, guarda NULL). Um único `COV-EXCL-BR` (OOM do clone); a
  guarda `!self` **não** é excluída porque `test_coalesce` a cobre.

Selo Fedora `--all`: Valgrind 0 erros (13 binários), 18 suites Lua +
property-based (360862 checks), coverage 98.73%/94.69%, parity 12/12.
**Windows (`build_win.ps1`) é follow-up obrigatório** antes de considerar o 10.8
fechado de vez — (c) introduz símbolo C novo (ABI/FFI).

---
## 2026-07-09 — 10.9 Fase B: `str→num` unificado via `_cstr`

`smaug_parse_i64_cstr`/`smaug_parse_f64_cstr` no `smaug_convert`: núcleo de
parsing **sem cópia** (C-string já terminada, hot-path do CSV).
`smaug_parse_*(s,len)` passa a copiar pra buffer local e delegar ao `_cstr`.
`try_i64`/`try_f64` do CSV viram wrappers `_cstr` — comportamento idêntico, sem
o `strtoll`/`strtod` duplicado. **Perf provada sem regressão**: `read_csv` 100k
linhas medido 2613 (baseline) vs 2618 ms (refactor), diferença 0.2% (ruído) — o
`_cstr` faz o mesmo trabalho do `try_*` original, evitando a cópia por campo que
um wrapper ingênuo custaria. Testes diretos dos `_cstr` (NULL/vazio/sucesso/
trailing) em `test_astype` (106 checks). `smaug_convert.c` 100%/100%. Selo Fedora
`--all` (98.72%/94.68%, parity 12/12) **+ Windows verde. 10.9 concluído**
(`smaug_convert` é agora a fonte única bidirecional texto↔número).

---
## 2026-07-09 — 10.9 Fase A: fonte única de formatação `num→str`

`smaug_fmt_i64`/`smaug_fmt_f64` no `smaug_convert` (agora conversão texto↔número
**bidirecional**): `i64`→`%lld`, `f64`→`%.17g`. Não-finitos normalizados na raiz
— `NaN`→`"nan"`, `±inf`→`"inf"`/`"-inf"` — eliminando a divergência do `%g` entre
libc (glibc vs UCRT). Os 8 pontos `snprintf` de `num→str` (astype 2, csv 2, json
4) migrados; o caso `NaN` especial do CSV vira redundante e sai; o CSV mantém a
troca de separador decimal por cima. Teste dirigido `test_fmt_direto`.
`smaug_convert.c` 100%/100%, Valgrind clean. Selo Fedora `--all` (98.73%/94.67%,
parity 12/12) **+ Windows verde**. Resta a Fase B (`str→num` via `_cstr`).

---
## 2026-07-09 — fix: crash de heap cross-runtime no I/O (Windows)

`io/csv.lua` alocava `name`/`columns` da `smaug_table_t` com `ffi.C.malloc`
(heap do `luajit.exe`) mas liberava com `C.smaug_free` (heap da `smaug.dll`). No
Linux (heap único glibc) é inócuo; no Windows (heaps separados luajit/DLL-UCRT)
corrompe o heap → crash silencioso no `to_csv_mem`/`to_json_mem`. Correção:
`name`/`columns` saem por `ffi.C.free` (casa com o `malloc`); séries seguem em
`C.smaug_*_free` (alocadas pela lib). Ponto único (`free_table_lua`, compartilhado
CSV+JSON). Pré-existente, ortogonal ao 10.7 — revelado pelo gate Windows.
Verificado limpo sob ASan; varredura confirma que era o único cross-heap do
projeto. Com isto o Windows fica verde: **10.7 Passo B concluído (Fedora+Windows).**

---
## 2026-07-09 — 10.7 Passo B Fase 4: rewire do `astype` ao Anel 0 (FFI-ABI)

Religa o `astype` (Series) às 12 primitivas C da matriz `src×dst`; o loop
elemento-a-elemento e o degrau saem. `cdef` +12 declarações (`str→dt` recebe
`dayfirst`). Dispatch de 5 zonas: clone (`src==dst`), matriz C
(`ASTYPE_C[src][dst]`), erro limpo `datetime↔bool`, loop Lua reduzido a
`bool↔{i64,f64,str}` (Anel 1 até 10.8), categorical no topo. Remove
`trunc_to_int`/`check_int64_lossless`/`is_nan` (órfãos). **Comportamento
(mudanças intencionais):** `num→str` passa a `%.17g` (round-trip, formato dos
writers); `str→num` fica rígido (`smaug_convert`, coerente com o CSV);
`datetime↔bool` vira erro limpo. Conserta int64 > 2^53: `i64↔dt`, `str↔i64`
exatos. Testes: bloco 10.7 troca recusa por conversão exata; +round-trip
`str→i64→str` >2^53; +erro limpo. Selo Fedora `--all` verde (Valgrind 13/13,
98.72%/94.66%, parity 12/12). O gate Windows expôs um crash de I/O pré-existente,
corrigido na entrada acima.

---
## 2026-07-09 — 10.7 Passo B: Fase 3 (Grupo B-in → string→num/dt)

Fonte única de parsing `smaug_convert.c` (`smaug_parse_i64`/`smaug_parse_f64`):
`strtoll` base-10 / `strtod`, rígidos — rejeitam trailing/vazio/overflow; i64 sem
hex/float, f64 com hex/inf/nan. Cópia null-terminada obrigatória (slice de buffer
concatenado). Três primitivas: `str→i64`, `str→f64`, `str→dt` (`dt_parse` +
`dayfirst`, exceção de assinatura). Inconversível → null; `"9007199254740993"` →
int64 exato (conserto). Semântica **rígida**, coerente com o `try_i64`/`try_f64`
do CSV, divergindo do oráculo `tonumber` de propósito (*falha visível*).
`test_astype` 90 checks (inclui teste direto de `smaug_convert` p/ ramos
`!s`/`len==0`/`len≥64`/overflow). `smaug_convert.c` + `smaug_astype.c` 100% linha
/ branch, Valgrind clean. Global: linha 98.72% (3863/3913), branch-alvo 94.66%
(3954/4177). `astype` Lua intacto (rewire na Fase 4).

---
## 2026-07-09 — 10.7 Passo B: Fase 2 (Grupo B-out → string)

Três primitivas `→str` no `smaug_astype.c`: `i64→str` (`%lld`, exato — conserta
o > 2^53 do oráculo), `f64→str` (`%.17g`, round-trip, formato canônico do
projeto), `dt→str` (ISO via `smaug_dt_format`). Construção single-pass
(`create_with_capacity(0,est)` + `append`/`append_null`). `test_astype` agora 52
checks (Grupos A+B-out); arquivo 100% linha / 100% branch, Valgrind clean.
Global: linha 98.71% (3812/3862), branch-alvo 94.60% (3907/4130). `astype` Lua
ainda intacto (rewire na Fase 4).

---
## 2026-07-09 — 10.7 Passo B: Fases 0-1 (infra + Grupo A do `astype` no Anel 0)

Início da migração do `astype` para o Anel 0 (matriz `src×dst`). Arquivo dedicado
`smaug_astype.c` (separação de responsabilidades — cast não se espalha pelos
`ops_*`), uma primitiva type-safe por par.

**Fase 0 (infra):** `smaug_astype.c`/`smaug_astype.h` criados e integrados ao
build; header documenta a matriz e o contrato.

**Fase 1 (Grupo A — arrays diretos):** 6 primitivas — `i64→f64`, `dt→f64`,
`i64→dt`, `dt→i64`, `f64→i64`, `f64→dt`. As cópias `dt↔i64` são int64→int64
diretas: **consertam** a corrupção > 2^53 do round-trip por `get()`/double
(dirigido em 2^53+1). `f64→{i64,dt}`: trunc direção zero; NaN/±inf/fora-do-range
→ null (Contrato 2, evita UB). Lógica de trunc+guarda em helper único
`f64_to_i64_trunc`. `test_astype.c` (32 checks); guard `if(!self)` testado com
NULL, OOM com `COV-EXCL-BR`. Arquivo em 100% linha / 100% branch (MC/DC),
Valgrind clean. `astype` Lua **intacto** — sem rewire até a Fase 4.

Selo [Fedora] `--all`: linha 98.70% (3785/3835), branch-alvo 94.56% (3877/4100),
Valgrind 13/13, paridade 12/12.

**Achado (12.19):** adicionar um `.c`+teste exigiu editar 5 listas de config
duplicadas (`SRCS`/`C_TESTS` em Makefile/build.sh/make_coverage.sh) — registrado
como dívida.

---
## 2026-07-09 — selo Fedora `--all`: fecha 10.6 (select) e 12.17

Sessão de validação. `build.sh --all` no Fedora selou os dois pendentes que
sessões anteriores de hoje deixaram registrados: o Passo B.3 do 10.6 (`select`
cond-bool — where/mask/ifelse ao Anel 0) e o 12.17 (`COV-EXCL-BR` nos guards do
`dt_coalesce_scalar`). Sem mudança de código — só a prova.

Resultado: Valgrind 0-errors nos 12 binários; linha 98.68% (3727/3777);
branch-alvo 94.49% (3825/4048, 147 excluídos). O código do 10.6 já estava
completo desde a entrada de ffill/bfill; faltava o **selo** (Valgrind + gcov no
Fedora), que vem agora — família seleção/preenchimento por máscara
**inteiramente selada** no Anel 0: (a) coalesce + (b) select + (c) ffill/bfill.
Integridade 113/113 SHA256 no MANIFEST.

---
## 2026-07-09 — 10.6 fechado: teste int64 > 2^53 em ffill/bfill

A primitiva (c) da família (`ffill`/`bfill`) já estava no Anel 0 desde o 7.1 —
não exigiu migração. Adicionado teste dirigido de int64 > 2^53 (cópia C direta
preserva exato) para fechar a prova da família com o mesmo rigor de (a)/(b).
Fecha o 10.6: seleção/preenchimento por máscara inteiramente no Anel 0.
Window 116→122 checks. Teste-only.

---
## 2026-07-09 — where/mask/ifelse → Anel 0 via select (cond-bool)

Primitiva (b) ao Anel 0. `select(cond,a,b)` por dtype: cond true→a, senão
(false ou NA)→b, preservando nulidade do escolhido. NA→false (decisão 1a).
Unifica where=select(cond,self,other), mask=lados trocados, ifelse=select(cond,a,b).
Escalar/nil por broadcast em Lua (reuso create+coalesce_scalar, sem C novo).
Degrau sai das três; int64 > 2^53 exato. bool-valor no Anel 1 até 10.8.

FFI: struct bool movido pra antes do f64 no cdef. Guards de entrada COV-EXCL-BR.
Testes: degrau → paridade Anel 0 nas 4 dtypes (selection 48 checks). Windows
12/12; prévia Ubuntu branch-alvo 94.38→94.49%. Selo Fedora pendente.

---
## 2026-07-09 — rename: scripts/windows_build.ps1 → scripts/build_win.ps1

Renomeado o script de build do Windows para `build_win.ps1`, alinhando com o
par `build.sh`. O replace foi global (docs + scripts + header do próprio
script); nenhuma referência a `windows_build.ps1` permanece no repo.

Nota de registro: o replace alcançou também as entradas históricas deste
CHANGELOG — sessões anteriores a esta data mencionam `build_win.ps1` embora, à
época, o arquivo se chamasse `windows_build.ps1`. Escolha consciente para manter
todas as referências apontando ao arquivo vigente; esta entrada documenta o
rename para que o nome novo nas entradas antigas tenha explicação. Sem mudança
funcional no script.

---
## 2026-07-09 — 12.17: alinha COV-EXCL-BR do dt_coalesce_scalar

Os guards `if (!self)` (datetime:219) e `if (!r)` (datetime:222) do
`dt_coalesce_scalar` estavam sem `COV-EXCL-BR`, ao contrário dos irmãos
i64/f64/str (anotados no B.1.cov). Recebem agora a justificativa idêntica
("engine não confia no caller" / OOM sem injeção). Mudança só de comentário,
sem alteração funcional.

Prévia Ubuntu (gcov, sem Valgrind): branch-alvo 94.33→94.38% — os 2 guards saem
de descobertos para excluídos. Selo Fedora `--all` (Valgrind + gcov) pendente.

---
## 2026-07-09 — combine_first → Anel 0 via coalesce série+série (null-mask, lado série)

Segunda metade da natureza null-mask vai ao Anel 0, fechando a primitiva (a) do
Passo B (escalar + série). `coalesce` série+série por dtype: onde `self[i]` é
nulo entra `other[i]` (se válido), senão `self[i]`; ambos nulos → nulo.
i64/f64/dt reusam `clone` + preenchem buracos a partir de other; str faz
two-pass offset-based (preserva `\0` e agora **pode** gerar nulos — máscara por
caso, ao contrário do escalar, que sempre produzia série sem nulos).

`combine_first` passa a delegar: valida Series/dtype/tamanho e chama
`self._d.coalesce(self._c, other._c)`. O degrau `check_int64_lossless` **sai do
`combine_first`** (int64 > 2^53 exato, sem round-trip por `get()`). bool fica no
Anel 1 até 10.8 (branch próprio, sem degrau — sem risco int64).

Testes: o teste antigo do degrau ("combine_first recusa int64 > 2^53") virou
paridade Anel 0 — 2^53+1 exato nos dois caminhos, ambos-nulos → nulo, str com
`\0`/vazia/`total==0`, dt self/other/ambos-nulos, nas 4 dtypes. Guards de
entrada (`!self||!other||size`) marcados `COV-EXCL-BR` — `combine_first` valida
antes de delegar.

Selo Fedora: Valgrind 0-errors nos 12 binários, branch-alvo 94.26→94.33% (acima
do baseline), zero descoberto nas coalesce. Com a primitiva (a) fechada, resta
(b) cond-bool com Kleene (`where`/`mask`/`ifelse`) e (c) propagação
(`ffill`/`bfill`).

Achado registrado (12.17): `dt_coalesce_scalar` (datetime:219/222) sem
`COV-EXCL-BR`, ao contrário dos irmãos i64/f64/str — inconsistência pré-existente
do B.1, a corrigir (não é regressão; contabilidade de branches fecha exata).

---
## 2026-07-08 — selo do null-mask escalar completo (B.1.cov)

Fecha a cobertura pendente das primitivas `coalesce_scalar`. O `--all` de
2026-07-06 deixara os guards defensivos novos sem cobrir. Resolução: os 7
guards de contrato (`if (!self)`, `if (!r)`, `if (!value && value_len>0)` em
i64/f64/str) marcados `COV-EXCL-BR` com o precedente já firmado. Os dois ramos
alcançáveis do `str` (`total>0?…` e `if (len>0) memcpy`) já ficavam cobertos
pelo teste 10.6B de string vazia — `fillna("")` sobre série toda-nula e sobre
mistura buraco/`"abc"` exercita os dois lados sem teste novo.

Selado no Fedora: Valgrind 0-errors nos 12 binários, branch-alvo 94.26%
(3693/3918, 105 excluídos), zero branch `coalesce_scalar` descoberto. Com isto o
lado escalar da família seleção/preenchimento por máscara está 100% fechado —
próximo: `coalesce` série+série (serve `combine_first`).

---
## 2026-07-07 — fillna → Anel 0 via coalesce_scalar (natureza null-mask, lado escalar)

Primeira das três naturezas da família seleção/preenchimento por máscara vai ao
Anel 0. Primitiva `coalesce_scalar` por dtype (`i64`/`f64`/`dt`/`str`): onde
`self[i]` é nulo entra o `value`, senão mantém `self[i]`; resultado sem nulos.
Molde do `binop_scalar`. `i64`/`f64`/`dt` reusam `clone` (cópia via memcpy — não
reinventam a cópia byte a byte). `str` não pode: preencher muda o tamanho do
buffer, então faz two-pass O(n) espelhando `create_from_array`, mas com os
comprimentos reais dos offsets (não `strlen`) — preserva `\0` embutido. `bool`
fica de fora (tipo paralelo, alinha ao 10.8).

O `fillna` passa a delegar: valida o `value` **uma vez** via `check_value`
canônico e chama a primitiva. Dois ganhos: (1) int64 > 2^53 nos não-nulos é
preservado exato — o degrau **sai do `fillna`** (segue nos outros membros da
família); (2) o `check_value` aceita `cdata int64_t`, que o porteiro caseiro do
`fillna` rejeitava — **cura a desparidade** e passa a aceitar preenchimento int64
exato acima de 2^53. `dt` restrito a `number` (epoch_ms) nesta leva; string ISO
registrada como 12.16.

Descoberta de método (via pergunta "usar str_set num loop é eficiente?"): não —
seria O(n²) pelos memmoves; o two-pass O(n) é o caminho, e o próprio Smaug já o
usa no construtor em massa. Reforça o hábito de medir antes de cravar.

Provado por FFI (2^53+1 exato, NaN preservado, `\0` embutido, `value` cdata) e
suíte (fillna 39 checks, property-based 360k). Valgrind 0-errors; cobertura de
linha 98.73→98.75%. **Pré-selo pendente:** 8 branches de guards defensivos das
primitivas a fechar (7 `COV-EXCL-BR`, 1 confere `str:227`) — ver 10.6 Passo
B.1.cov. Selo do null-mask escalar fecha quando a cobertura fechar.

---
## 2026-07-06 — 10.6 vira família; degrau estendido a where/mask/ifelse/combine_first

A pergunta "isso deveria estar no C?" reenquadrou o 10.6. `fillna` não é uma
operação isolada: é membro de uma família que escolhe/preenche valor por posição
segundo uma máscara — `fillna`, `combine_first`, `where`, `mask`, `ifelse`, e os
parentes de propagação `ffill`/`bfill`. Todos vivem no Anel 1 (loop
`get→set`+`from_table`) e, portanto, herdam a corrupção de int64 > 2^53.

Achado (provado): `where`, `mask`, `ifelse` e `combine_first` corrompiam int64 >
2^53 **em silêncio, agora** — o degrau de 2026-07-05 só cobria `fillna`/`astype`.
Era um bug ativo em meia família.

Degrau estendido: a guarda única `check_int64_lossless` (mesma fronteira 2^53 do
9.1, fonte única) passou a proteger os quatro. Recusam visível em vez de
corromper calado. Reuso da guarda existente — nenhum critério novo, nenhuma
guarda duplicada. Testes: +5 selection, +2 predicates. Suíte verde, parity 12/12,
Valgrind 0-errors, coverage inalterado (Lua-puro).

Decisão de arquitetura: **não** criar `fillna` isolado no Anel 0 — bifurcaria a
família (metade C, metade Lua), a desparidade que o item combate. O Passo B passa
a ser desenhar as primitivas fundamentais da família (seleção por null-mask;
seleção por cond-bool com Kleene; propagação à parte), com todos delegando. As
3 primitivas C `*_fillna` isoladas (i64/f64/dt) tentadas antes foram descartadas
— voltam integradas no desenho da família.

---
## 2026-07-05 — 10.6/10.7 Passo A (degrau): corrupção silenciosa → falha visível

Antes de vetorizar `fillna`/`astype` ao Anel 0, um degrau paliativo que troca
acerto-adivinhado por falha visível.

Achado que refina o Roadmap (10.6, l.449): a corrupção de int64 > 2^53 no
round-trip `get()`→`double` tem **dois regimes**, não um. Muito acima de 2^53
dispara o warn do 9.1 por elemento (ruidoso, grava errado) — esse já era
conhecido. Mas na fronteira (logo acima de 2^53, que o `double` arredonda de
volta a exatamente 2^53) grava em **silêncio total**: o `number` arredondado
passa no guard do 9.1 (`> 2^53` é falso para `== 2^53`) e entra sem aviso. Pior
caso de falha-invisível, não registrado antes. Provado com `2^53+1` (silencioso)
vs `2^60+7` (avisa).

Guarda única `check_int64_lossless` (`_core.lua`, ao lado do `check_value`):
reusa o `INT64_MAX_MAG` (2^53) do 9.1 — **fronteira única**, sem segundo
critério. Lê o valor cru (`cdata int64_t`, sem `tonumber`) só para comparar
magnitude — detecção, não conversão. `fillna` e `astype` delegam; nenhuma regra
de fronteira nova nasce nos call-sites (anti-redundância).

Seletividade por par no `astype`: recusa só onde `double` perde **e** importa —
`int64→int64` e `int64→string`. `int64→float64` **não** recusa (o `double` é o
destino correto; a matriz empírica provou que atravessar `double` nem sempre é
erro); `int64→bool` tampouco (0/1).

Paliativo por construção: não vetoriza, não move nada ao Anel 0, não reescreve
loop nem matriz. Sai quando o Passo B (Anel 0) entrar — junto com os testes que
hoje esperam recusa, que passarão a esperar sucesso com valor exato. Desparidade
registrada e **não** consertada aqui: `fillna` rejeita `value` cdata (validação
divergente do `check_value`) — morre no Passo B ao delegar.

Testes: +2 em `fillna` (`test_access`, visíveis 34→36) e +5 em `astype`
(`test_constructors`, contagem mascarada pelo 12.7 — os checks rodam e passam,
o headline subconta). Suíte verde, parity 12/12, selo [Fedora] 2026-07-05
(Valgrind 0-errors nos 12 binários; coverage inalterado — nenhuma linha C nova).

---
## 2026-07-02 — 9.2: fechamento de cobertura do C novo (pré-selo)

Checkup pós-9.2 rodou o `--all` em Linux (container, pré-checagem — Fedora
segue autoritativo) e encontrou o que o selo existe para encontrar:
`smaug_str.c` com 100% de linha mas **4 ramos descobertos, todos no código
novo do 9.2**. gcov com `-b` identificou as direções exatas:

- **Guard da view (l.115):** nenhuma das 3 sub-condições jamais disparou —
  não existia teste de entrada inválida para `smaug_str_view` (o
  `test_cow_oob_does_not_detach` é só f64). Novo
  `test_str_view_invalid_inputs`: NULL, `start > size`, `len > size-start`,
  borda inválida `start==size, len>0` e a borda VÁLIDA `start==size, len==0`
  (janela vazia no fim — prova que o guard overflow-safe aceita o mesmo
  contrato do f64). Pai intacto após as recusas.
- **Detach de janela toda-vazia (l.306/312):** `byte_count==0` com `size>0`
  (todas as strings `""`) nunca ocorria — caso distinto do
  `test_str_empty_view` (`size==0`). Novo `test_str_detach_all_empty_window`:
  bufcap cai no fallback `SMAUG_STR_BUFFER_INIT`, memcpy pulado, série
  destacada coerente e mutável, `""` ≠ NULL preservado, pai intacto.
- **`offsets_owned` false (l.104):** estruturalmente inalcançável — o campo é
  atribuído `true` nos 3 pontos (create/view/detach) e nunca `false`.
  Decisão: `COV-EXCL-BR`, com justificativa de posse, não de "porta futura":
  o campo paga seu custo hoje porque torna o `free` correto por semântica
  (A1) — sem ele, a posse do offsets seria inferida por acoplamento
  `external_alloc`+`is_view`.

Allocfail NÃO estendido (decisão registrada): o trio de OOM do detach já é
varrido pelo harness; o ramo distinto era só o `byte_count==0`.

**Resultado:** `smaug_str.c` 100% linha / 100% branch-alvo; test_cow 263→279.
Validado: Linux container (Valgrind 0-errors nos 12 binários, 18/18 Lua,
parity 12/12) + Windows (suítes idênticas). **Selo [Fedora] obtido
(2026-07-02):** `--all` verde — Valgrind 0-errors, `smaug_str.c` 100/100,
test_cow 279. 9.2 fechado.

**Auditoria Lua (mesma sessão):** disciplina de erro, warn e helpers de NA
limpos. Fix aplicado: 4 call-sites internos migrados para `_raw_column()`
(`dataset/_core.lua` — select/insert/rename; fecha os retardatários do 9.2).
Achados registrados na estrada: 10.6 (`fillna` corrompe i64 > 2^53 via
round-trip `get`), 10.7 (`astype`, mesma natureza), 10.8 (`BoolSeries` —
coerência de caminho, design prévio), 11.4 (exibição de i64 > 2^53) e 12.13
(doc do 9.1 incompleta). Datetime fora do raio (epoch_ms).

---
## 2026-07-01 — Item 9: Contratos de fronteira (9.1 int64 > 2^53 + 9.2 column COW / view de string)

Fechou os dois contratos de fronteira do item 9. O fio condutor: quem é dono do
dado, e onde a precisão/posse pode se perder silenciosamente.

**9.1 — int64 acima de 2^53 (`check_value`, Lua-puro, Anel 0 intocado).**
Dois sub-problemas distintos:
- Sub-A (limitação da linguagem, não da lib): um literal Lua grande como
  `9007199254740993` já chega **truncado** para `9007199254740992` — o parser do
  Lua o representa como `double` antes de qualquer código do Smaug rodar. A lib
  não pode recuperar o valor, só tornar visível. Decisão (9.1.2):
  **avisar-mas-aceitar** — número > 2^53 dispara um `warn` educativo (helper novo
  `I.warn` central em `init.lua`, reutilizável pelo 12.10), sem bloquear.
- Sub-B (o bug real, a lib controla): `check_value` recusava `cdata int64_t`
  (`9007199254740993LL`, `ffi.new("int64_t")`) — a única forma que preserva 64
  bits — porque exigia `type(v) == "number"`. O C guarda até 2^63-1 sem perda; o
  gargalo era só o guard Lua. Corrigido via `ffi.istype`: aceita cdata
  int64/uint64, recusa `uint64_t > INT64_MAX` (9.1.3, sem wraparound silencioso)
  e segue recusando float/double cdata (mantém A7).

**Achado durante a implementação:** consertar a entrada (`set`) não bastava — a
saída (`get`) reintroduzia a perda, porque `get_value` faz `tonumber()` no
int64_t (mesma limitação da Sub-A, do outro lado). Escopo estendido no mesmo
item: novo `Series:get_raw(i)` devolve o cdata int64_t cru, sem conversão. `get`
normal mantém o comportamento antigo (limitação documentada).

**9.2 — `column()` compartilhava buffer com o frame (E2). Op1: o E2 morre.**
`column()` retornava a referência Series interna; `col = df:column("x");
col:set(...)` mutava o frame silenciosamente. Decisão: `column()`/`col()` passa a
retornar **view COW** protegida (leitura zero-copy, detach na 1ª mutação). O
código interno (relacional, csv, stat — ~40 call-sites) migrou para `_raw_column`
(acesso cru explícito). Mutação intencional agora é via `update_column`.

**Estendido para o Anel 0 (a parte pesada):** string não tinha view. Implementada
`smaug_str_view` + `str_cow_detach` em C. Diferente dos numéricos (buffer fixo,
view O(1)), a string é offset-based → **modelo de posse mista A1**: campo novo
`offsets_owned` na struct `smaug_series_str_t`, a view compartilha
`buffer`/`null_mask` mas possui um `offsets` próprio absoluto. O `free` passou a
separar as duas posses; o detach materializa a janela com offsets rebaseados.
Escolhido A1 sobre A3 (rebase on-the-fly em cada acesso) porque A1 concentra a
complexidade no ciclo de vida da view — A3 a espalharia por toda operação de
string (fonte de regressão distribuída).

**Achado de teste (E2 tinha alcance oculto):** ~14 setups de `test_core` usavam
`df:col("x"):set_null(i)` como atalho para injetar nulos — só funcionava pelo
aliasing que estávamos matando. Migrados (Op A) para dados que **nascem** com
`NA` via `from_table({..., NA, ...})` e mutação via `update_column`. Review do C
confirmou: `from_table(NA)` chama o mesmo `set_null` do C (só escreve a máscara),
então o estado de memória é idêntico — zero reimplementação.

**Sincronização crítica:** o cdef do FFI declara a struct str campo a campo, então
`offsets_owned` teve de entrar no cdef na mesma posição do C (senão o LuaJIT lê o
layout errado — bug de memória silencioso).

**Validação:** Valgrind-clean (test_cow, test_string, allocfail — 0 leaks/errors,
incl. caminhos de OOM do detach); test_cow +70, allocfail +70, test_core +8
(prova E2 morto); 18/18 Lua; parity 12/12 (`get_raw` e `_raw_column` registrados
como exceções intencionais). Docs sincronizados: COW.md (string ❌→✅),
API_Reference, API_INDEX, CONTRACT. 9.1 fechou por Windows (Lua-puro); 9.2 é
[Fedora] (Anel 0 novo) — aguarda `--all` para o selo de cobertura.

---
## 2026-06-30 — Item 8: Rolling → Ring 0 (motor genérico + min_periods + expanding + DataSet)

Levou a tese de "fonte única" ao rolling. Antes a duplicação era TRIPLA (C /
Series Lua / DataSet Lua), e o C fazia menos que o Lua. Agora o C é a fonte;
Series e DataSet delegam.

**Bug histórico corrigido (a motivação real do item):** o caminho C ignorava
min_periods. `rolling(3):min_periods(1):sum()` dava `nil,nil,6,9` (o C era
chamado sem saber de min_periods) em vez de `1,3,6,9`. O resultado dependia de
qual caminho (C/Lua) era tomado. A cura: o C passou a conhecer min_periods, e o
fallback Lua foi removido — não há mais dois caminhos.

**Arquitetura (8a):**
- Motor genérico `rolling_apply(data, mask, n, window, min_periods, kind)` —
  fonte única dentro do C para mean/std/var/count (D8-g opção i: os agregados
  naturalmente double-safe). std/var amostrais (ddof=1, NaN p/ n<2) — coerente
  com a reconciliação do item 5.0.
- sum/min/max NÃO passam pelo motor (preservam tipo exato — sum i64 >2^53 não
  perde precisão, min/max mantêm a deque O(n)). Só ganharam min_periods.
- **min_periods (D8-b)**: convenção `0 = modo janela-cheia (default), >=1 =
  parcial (>= min_periods não-nulos)`. Auditoria do motor confirmou que isso
  espelha o min_count do item 5.5 — não é invenção local, é o idioma já usado.
- **min/max com min_periods (D8-h opção ii)**: a deque não rastreia contagem de
  não-nulos (o resumo inicial subestimou isso). Em vez de mexer na deque (que
  tem invariantes COV-EXCL delicados, arriscado sem Fedora), o modo min_periods>=1
  usa um rescan O(n·window) type-preserving (compara no tipo nativo, sem double);
  a deque fica intocada no modo default (caso comum). "Não pague pelo que não usa".

**Expanding (8b, D8-i opção i):** expanding É rolling com janela = comprimento
total e min_periods>=1. Zero C novo — delega a `rolling(n, min_periods)`.
Eliminou todo o SeriesExpanding reimplementado. Não regride performance (o
expanding Lua já era O(n²)). median/quantile expanding ficam Lua (via _agg).

**DataSet (8c):** Rolling DataSet tinha _agg próprio (3ª cópia). Agora delega à
Series via `column():rolling()`. Ganhou std/var/count e min_periods de graça.

**Correção de tipo (efeito colateral saudável):** o expanding e o DataSet rolling
antigos usavam `col._dtype` para todos os agregados — então `mean` de i64
**truncava** para int64. Agora mean/std/var → float64 (coerente com a Series).
Nenhum teste dependia do comportamento truncado.

**Decisão D8-c:** sum/mean/min/max/std/var/count no C; median/quantile ficam Lua
(janela ordenada é padrão diferente; registrado, candidato a C pós-1.0).

- Testes: C +20 (test_ops_window 391→411: std/var/count, min_periods, rescan,
  i64 >2^53 exato); allocfail +71 (1733→1804: motor, pack_f64, i64_via_motor,
  count, modos min_periods/rescan); Lua test_window +23 (93→116: bug corrigido,
  novos agregados, expanding delega, tipos); ds test_core +8 (212→220).
- Migração de ABI: 100 chamadas rolling em test_ops_window + 18 em allocfail
  atualizadas p/ a assinatura de 3 args (min_periods=0 = comportamento anterior).
- `[Fedora]`: implementado e verde no container + Windows-equivalente; aguarda
  Valgrind + cobertura no Fedora. Fecha JUNTO com o item 7.3. Atenção no Valgrind
  ao motor genérico (malloc/free de tmp em i64_via_motor) e ao rescan de min/max.

---
## 2026-06-29 — Item 7.3: rank em dt/str/bool no Ring 0

Último gap de completude do motor (o 7.4 já estava feito). `rank`/`pct_rank`
existiam só em f64/i64; agora todos os ordenáveis (f64/i64/dt/str/bool) têm.

- **Insight de assinatura**: o resultado do rank é sempre `double` (average pode
  dar .5), em qualquer dtype. Só a comparação dos valores é type-specific. Então
  `double* smaug_<t>_rank(s, method)` serve todos — sem a bifurcação de retorno que
  o 7.2b (min/max) teve. Por isso pacote único (D7.3-e).
- **dt** (`smaug_dt_rank`): espelha `smaug_i64_rank` (epoch é int64, comparação
  exata via `dt_entry_t {idx,val}` — sem converter a double, preserva precisão).
- **str** (`smaug_str_rank`): ordena um array de **índices válidos** via `sort_cmp`
  (mesmo contexto global do argsort) e detecta empates com `str_cmp_idx`. Não cabe
  em par numérico, então é gather de índices. "" é valor válido (a menor string).
- **bool** (`smaug_bool_rank`): sem qsort — só dois grupos. Os `nf` false ocupam
  posições 1..nf, os `nt` true ocupam nf+1..nf+nt; o método decide o valor.
- **Métodos uniformes** (D7.3-b): average/min/max/first em todos. NA → NAN → nil
  (D7.3-c), rankeando só os válidos, igual aos numéricos.
- **D7.3-d (refatoração do gate)**: `methods.rank` tinha `if float64...else i64`
  hardcoded. Agora o descritor liga `rank` nos 5 dtypes e a Lua delega via
  `self._d.rank`, sem branch por dtype — alinha com shift/ffill/min/max. f64/i64
  passaram a ir pelo descritor (mesmo C, comportamento idêntico).
- **Ganho de graça**: `pct_rank` chama `rank("average")` internamente, então passou
  a funcionar em str/dt/bool sem código novo (count_nonnull já existia em todos).
- **Coerência (exceptions órfãs)**: o eixo 1 do parity tinha 6 exceptions marcadas
  "gap real não implementado" / "sem semântica" para rank e pct_rank × str/dt/bool.
  Com a implementação, viraram órfãs — removidas. rank/pct_rank × categorical
  ficam (sem ordem útil). bool saiu de "sem semântica" porque D7.3-a o incluiu.
- D7.3-a: bool incluído (escopo literal era "dt/str") — registrado.
- Testes: C +31 (test_ops_window 360→391: dt/str/bool nos 4 métodos, empates, NA,
  "" válida, toda-NA, NULL); Lua +12 (integração 66→78); allocfail +31 (1705→1736,
  varrendo malloc(result)+malloc(pairs/idx)+qsort de cada).
- Achado (não acionado): rank/pct_rank por-coluna no DataSet = escopo futuro
  (exceptions eixo 2 mantidas).
- Corrigido de passagem: API_INDEX dizia método `dense` (inexistente); o correto
  é `first`.
- `[Fedora]`: aguarda Valgrind + cobertura. Atenção ao `str_rank` (qsort de índices
  com contexto global) e às ramificações de método.

---
## 2026-06-29 — Item 7.2b: min/max em dt/str/bool no Ring 0 (7.2 completo)

Segunda metade do 7.2. Fecha a outra metade da incoerência: `dt:min`/`dt:max`
(e str/bool) passam a existir, retornando o **valor** do menor/maior (decisão
D7.2-a opção ii). Agora `dt:min == get(dt:argmin)` — coerência total.

- **dt** (`smaug_dt_min`/`max`): retorna int64 epoch, espelha `smaug_i64_min/max`.
  INT64_MIN (= DT_SENTINEL) sinaliza vazia/toda-NA/(ignore_na=false) presença de
  NA; a Lua detecta via `is_int_sentinel` → nil. Passa por `reduce_num` limpo
  (já era o caminho dos numéricos).
- **str** (`smaug_str_min`/`max`): retorna ponteiro+len para o elemento vencedor
  (dentro do buffer de `s`), no padrão de `smaug_str_get` — NULL = vazia/toda-NA/
  (ignore_na=false) NA; ptr!=NULL com len==0 = "" (distinta de NULL). Reusa
  `argmin/argmax` (mesma comparação lexicográfica). Wrapper no descritor
  materializa via `ffi.string`. NÃO aloca.
- **bool** (`smaug_bool_min`/`max`): Shape 1 (valor + status), como `bool_get` —
  não há valor fora de {0,1} para sentinela, então `SMG_NULL_VALUE` sinaliza
  ausência. Wrapper no descritor lê o status (distingue `false` de ausência).
- **Decisão de despacho** (`_reduce.lua`): `methods.min/max` ramifica —
  str/bool usam o wrapper do descritor (retorna valor|nil), evitando `reduce_num`
  (que faria `tonumber` e quebraria a string); f64/i64/dt seguem `reduce_num`.
  O caminho numérico não foi tocado (preserva Valgrind-clean já validado).
- `ignore_na` uniforme em todos os dtypes (default true: pula NA; false: NA
  presente → nil). argmin/argmax seguem ignorando NA por natureza.
- Testes: C +22 (test_ops_window 338→360: dt/str/bool min/max, "" válida, NA,
  ignore_na false, toda-NA, NULL, status NULL-safe); Lua +14 (test_reduce 43→57).
  min/max não alocam → allocfail inalterado (1705).
- Achado registrado (não acionado): `df:min()`/`df:max()` no DataSet ainda
  filtram só colunas numéricas (contrato D3 do item 5). Estender a str/dt/bool
  (como pandas) é decisão de escopo do frame — fora do 7.2.
- `[Fedora]`: aguarda Valgrind + cobertura. Atenção aos caminhos `str_min/max`
  (ponteiro pra dentro do buffer) e às ramificações de status do bool.

---
## 2026-06-29 — Item 7.2a: argmin/argmax em str/bool/dt no Ring 0

Primeira metade do 7.2. Fecha parte da incoerência `dt:argmin`✓/`dt:min`✗:
o `dt:argmin` que funcionava via fallback Lua foi movido pro C, e str/bool —
que erravam — ganharam a operação.

- C novo: `smaug_dt_argmin/argmax` (cronológico), `smaug_bool_argmin/argmax`
  (false<true), `smaug_str_argmin/argmax` (lexicográfico por bytes, via novo
  helper `str_cmp_idx` — comparação índice-vs-índice, mesma ordem de sort/cmp).
  Todos espelham `smaug_f64_argmin`: índice 0-based, SIZE_MAX se vazia/toda-NA,
  ignoram NA. Decisão D7.2-b: bool incluído (era o único órfão; trivial).
- `methods.argmin`/`argmax` (`_cumulative.lua`): o gate de dtype hardcoded
  (numérico+datetime) virou gate por **capacidade** (`self._d.argmin` existe?),
  e o fallback Lua foi removido. Erro orientado por dtype quando não há suporte.
  `idxmin`/`idxmax` são aliases → herdam o suporte novo automaticamente.
- Parity: removidas 4 exceptions agora **órfãs** (argmin/argmax × str/bool, antes
  marcadas "gap"/"sem semântica"). Categorical permanece exceção (sem ordem total
  estável — depende do encoding dos codes).
- Testes: C +24 (test_ops_window 314→338: dt/str/bool com NA, vazia, toda-NA,
  string vazia como menor, prefixo "ab"<"abc"); Lua +9 (test_window 93→102).
  argmin/argmax não alocam → allocfail inalterado. Os testes de `dt:argmin` em
  test_categorical passaram a exercitar o C (guard da migração de graça).
- `[Fedora]`: aguarda Valgrind + cobertura para `[Done]`.

---
## 2026-06-29 — Item 7.1b: shift com sinal no Ring 0 (todos os dtypes)

Fecha o 7.1. Move o shift inteiro pro C — incluindo o sentido negativo, que
até aqui era tratado por fallback Lua e (achado) NÃO tinha cobertura em lugar
nenhum.

- **Mudança de ABI** (a parte sensível, por isso isolada do 7.1a): assinatura de
  `smaug_f64_shift`/`smaug_i64_shift` passou de `size_t periods` para
  `int64_t periods`. Os testes C antigos só exercitavam positivos (1, 0, ≥size),
  então sobreviveram sem alteração. Header + cdef FFI atualizados.
- Fórmula unificada para os dois sentidos: para cada posição i de saída, a fonte
  é `src = (int64_t)i - periods`; fora de `[0, size)` → NA. periods>0 desloca p/
  baixo, <0 p/ cima — mesma semântica que o fallback Lua tinha (preservada).
- Short-circuit `|periods| >= size → toda NA`: além de atalho do caso comum, evita
  overflow em `(int64_t)i - periods` quando `periods` está perto de `INT64_MIN`.
- shift novo em bool/dt (buffer plano, idêntico a f64) e str (offset-based,
  reconstruído por append — mesmo padrão de ffill/bfill, não view). Descritores
  bool/str/dt ligam `shift`.
- Fallback Lua **removido por inteiro** de `_cumulative.lua`: `methods.shift` só
  valida `periods` inteiro e delega ao C (guard defensivo se dtype sem shift).
  Categorical tem shift próprio (sobre codes) e já tratava negativo — agora
  Series/DataSet/categorical têm a MESMA semântica de sinal em todos os caminhos.
- Testes: C +29 (test_ops_window 285→314: shift negativo de f64/i64 — antes sem
  cobertura — e shift em bool/str/dt nos dois sentidos, com NA, bordas, all-NA);
  Lua +13 (test_window 80→93); allocfail +28 (1677→1705, incl. `str_shift` sob
  OOM nos dois sentidos). DataSet 5.3 shift negativo confirmado (delega ao C).
- `[Fedora]`: aguarda Valgrind + cobertura no Fedora para `[Done]`. Atenção ao
  ramo `|periods|>=size` e ao `str_shift` sob OOM na cobertura.

---
## 2026-06-29 — Item 7.1a: ffill/bfill no Ring 0 (bool/str/dt)

Continuação da meta-decisão D7 (item 7 vai pro C, sem fallback). Recorte: o 7.1
foi dividido em **7.1a (ffill/bfill)** e **7.1b (shift com sinal)** — separar a
adição pura (ffill/bfill, sem mudança de ABI) da mudança de ABI do shift facilita
bissectar se o Valgrind/cobertura do Fedora acusar algo.

- 7.1a: `ffill`/`bfill` agora no C para bool/str/dt (antes: fallback Lua
  element-wise em `_cumulative.lua`). bool/dt são buffer plano → idênticos a f64.
  **str é offset-based**: a série nova é reconstruída por `append`/`append_null`,
  reusando o padrão de `smaug_str_take` (gather posicional). NÃO usa `view`, então
  a limitação de view-em-string do COW.md não se aplica (produz cópia completa).
- Wiring: protótipos nos headers (`smaug_numeric.h` bool, `smaug_datetime.h`,
  `smaug_string.h`), cdef FFI, e `ffill`/`bfill` ligados nos descritores bool/str/dt
  (`_types.lua`).
- Fallback Lua **removido** de `_cumulative.lua`: `methods.ffill`/`bfill` agora só
  delegam ao C, com guard defensivo (erro orientado se um dtype sem ffill chegar —
  bug de programação, fail-fast em vez de fallback silencioso). Categorical tem
  implementação própria (opera sobre codes) e NÃO passa por aqui — intacto.
- Testes: C +41 (test_ops_window 244→285: bool/str/dt com NA, bordas, all-null,
  string vazia válida e multibyte); Lua +18 (test_window 62→80); allocfail +45
  (1632→1677) varrendo todos os ramos de OOM dos novos ffill/bfill (incl. o
  `malloc(src)` do `str_bfill`). O teste DataSet "5.3 ffill em string" passou a
  exercitar o C novo — vira guard da migração de graça.
- Coerência: shift negativo segue sem cobertura em lugar nenhum (será coberto no
  7.1b, quando mover pro C). Eixo 1 do parity não tinha exceptions de ffill/bfill
  (a mudança foi interna Lua→C, invisível à paridade de API).
- `[Fedora]`: aguarda Valgrind + cobertura no Fedora para `[Done]`.

---
## 2026-06-29 — Item 7.4: bool eq/ne no Ring 0

Meta-decisão D7: todo o item 7 vai pro C (Anel 0), Lua só delega, sem fallback —
coerência de arquitetura (o engine é dono do buffer e da máscara).

- 7.4: bool era o único dtype sem igualdade (`eq`/`ne`). f64/i64/dt/str já tinham
  no C. Adicionado `smaug_bool_eq`/`smaug_bool_ne` (espelham `smaug_f64_eq`:
  compara com escalar 0/1 → máscara uint8_t + out_mask; NA → 0 com máscara NULL,
  preservando a nulidade). Wiring: header, cdef FFI, `cmp_eq`/`cmp_ne` no descritor
  bool (`_types.lua`, converte `true/false`→`1/0`).
- Testes: C bool lifecycle 154→165 (incl. NA, threshold não-normalizado, NULL
  series); Lua selection 21→27 (Kleene: comparar com NA → NA); allocfail +20 (1632)
  varrendo os ramos de malloc de eq/ne — para a cobertura fechar no Fedora.
- `[Fedora]`: aguarda Valgrind + cobertura no Fedora para `[Done]`.



Levantamento a partir do output real do parity (terra firme): 83 assimetrias
classificadas em 3 baldes — intencional (dimensionalidade 1-D vs 2-D), par de nome,
gap real. Nada suposto; cada par/gap aterrado no fonte.

- 6.1 `Series:dtype()` — string do dtype (par singular de `DataSet:dtypes`).
- 6.2 `sort`/`sort_by`: mantidos os dois (Series ordena valores; DataSet ordena
  linhas por coluna — assinaturas diferentes por natureza). Sem rename; pareados
  no auditor.
- 6.3 `Series:sample(n,[seed])`, `:to_string([opts])`, `:to_markdown()` — pares do
  DataSet (sample espelha take; render em 1 coluna).
- 6.4 **eixo 02 reescrito** de diff de presença para **paridade classificada**:
  pares de nome (len↔nrows, dtype↔dtypes, sort↔sort_by) tratados no script; 74
  assimetrias intencionais registradas em `exceptions.txt` (agrupadas por
  categoria); **falha (os.exit) em gap real não-registrado** — vira guard como os
  outros eixos. O `expected_pairs` morto virou lógica viva.
  Resultado: 48 ambos · 6 pares · 74 intencionais · **0 gaps reais**.
- 6.5 `DataSet:clone()` — cópia profunda (par de `Series:clone`); gap achado no
  levantamento. Cada coluna clonada; nome/ordem preservados.
- Tudo Lua-puro. Testes: Series acesso 25→34, DataSet core 207→212. Docs
  (API_INDEX) atualizados. Parity 12/12. Aguarda Fedora + Windows para `[Done]`.

## 2026-06-28 — Item 5 completo: element-wise + transforms (5.2/5.3)

### 5.2 element-wise → DataSet mesma forma
- `df:abs/round/clip/cumsum/cummin/cummax/cumprod`. Helper `map_frame` aplica a
  redução da Series a cada coluna (fonte única). **D4-i:** operação numérica
  **erra** se houver coluna não-numérica, nomeando-a ("selecione as numéricas
  antes"). Contraste com 5.1: reduções mudam a forma → pulam não-numéricas;
  element-wise preserva a forma → não dá pra descartar/passar em silêncio.
### 5.3 transforms
- `df:ffill/bfill/shift` (qualquer dtype), `df:diff` (numérico, D4-i).
- `df:isna/notna` → DataSet **bool**, todas as colunas. Construído via `is_null`
  por índice (Series:isna é escalar por índice, não vetorizado — observação
  registrada; o DataSet não depende dele).
- `df:astype({col=dtype})` (**D4-A**, mapa explícito); colunas fora do mapa seguem
  inalteradas (compartilhadas; Series são COW). Erro em coluna inexistente ou se o
  argumento não for mapa.
- Tudo Lua-puro sobre a 5.0 (Anel 0 já validado no Fedora). DataSet stat: 49→90
  checks. **Item 5 fecha** por equivalência Fedora; follow-up `build_win.ps1`.

---
## 2026-06-28 — Item 5: reduções DataSet (5.1), min_count (5.5), delegação GroupBy (5.4)

### 5.1 — reduções por coluna → DataSet 1-linha (D1)
- `df:sum/mean/min/max/std/var/median/prod/quantile/skew/kurtosis/mad/sem/
  count_nonnull` → DataSet de **1 linha**. Cada coluna mantém SEU dtype de
  resultado (sum de i64→i64 e mean→f64 convivem — por isso 1-linha, não Series
  posicional; decisão D1). Só colunas numéricas; sem numérica → erro. Helper
  `reduce_frame` delega às reduções da Series (fonte única).
### 5.5 — min_count opt-in em sum/prod (Series e DataSet)
- `Series:sum(ignore_na, min_count)` / `:prod(...)`; `DataSet:sum(min_count)` /
  `:prod(...)`. Default (0) preserva o atual (sum de vazio/all-null = 0).
  `min_count=N` exige N não-nulos, senão NA.
### 5.4 — GroupBy delega às reduções da Series (elimina duplicação)
- `agg_sum/mean/min/max/std/var/median/prod/nunique` deixaram de reimplementar
  inline — agora `col:take(idx):<redução>()`. Behavior-preserving (groupby 60
  checks intactos): possível só após a 5.0 reconciliar ddof (std/var amostrais nos
  dois lados). `first`/`last` seguem inline (posicionais, sem redução-Series).
- Tudo Lua-puro sobre a fundação 5.0 já validada no Fedora. Falta 5.2 (element-wise)
  e 5.3 (transforms), pendentes de decisão D4 (não-numéricas).

---
## 2026-06-28 — Item 5 (fundação 5.0): reconciliação de ddof em std/var

### Achado em sessão (bloqueava o item 5)
- O `ddof` estava **incoerente em três vias**: `Series:std/var` eram populacionais
  (÷N, no C `smaug_f64_var`/`smaug_i64_var`, comentado "populacional"), mas
  `cov`/`skew`/`kurtosis`, o GroupBy (`agg_std`/`agg_var` ÷ n-1) e o pandas são
  amostrais (÷ N-1). A delegação do 5.4 era impossível: `groupby:std` (amostral)
  não pode chamar `Series:std` (populacional) — números diferentes.
- Um D2 inicial (alinhar Series→nil em n<2 assumindo amostral) foi tentado e
  **revertido** — partia da premissa errada; os testes "var populacional" pegaram.
  Bom exemplo de "behavior-identical exige prova": a suíte é o guard.

### Decisão (Opção A) e implementação
- **Tudo amostral (ddof=1).** C `smaug_f64_var`/`smaug_i64_var`: ÷(n-1), NaN para
  n<2 (std = sqrt herda). Removidos 2 `COV-EXCL-BR` (o ramo n<2 agora é alcançável
  via n=1). Alinha Series com cov/skew/kurtosis, GroupBy e pandas.
- 3 asserções recalculadas (var de {10,20,30}: 200/3→200/2=100; std→10; var/std de
  1 elemento: 0→NA) em test_constructors e test_access.
- Docs: API_INDEX e API_Reference de "populacional (÷N)" para "amostral (÷ N-1;
  <2 → NaN)".
- **Toca Anel 0 → `[Fedora]`:** precisa de Valgrind + cobertura para fechar. Build
  Linux verde (suíte idêntica fora os 3 valores recalculados).

---
## 2026-06-28 — Timeline item 4: NA relacional unificado + Contrato 8

### Política (mudança de comportamento — adição de contrato, não refatoração)
- **Contrato 8: NA em chave relacional é erro.** Antes, três tratamentos
  divergentes: join **casava** NA com NA (`key_to_str(nil)="\0NULL\0"`), groupby
  **errava** (correto), pivot/pivot_table **descartavam a linha em silêncio**
  (`if iv ~= nil and cv ~= nil` — perda de dado calada, pior que "aceitar"; o
  roadmap subdescreveu como "aceita"). Agora os quatro erram de forma orientada.
- **Helper central `validate_keys_no_na(named_cols, op_name)`** (local em
  `_relational.lua`, onde vivem os consumidores). Valida **só** colunas-chave,
  nunca a coluna de valores. Mensagem única:
  `smaug: <op> — coluna 'X' contém NA; trate com fillna ou dropna antes`.
- Aplicado eagermente no corpo de cada método público (join/groupby/pivot/
  pivot_table), nível de erro uniforme. groupby: check inline removido do
  `multi_argsort` (que é exclusivo de groupby) e centralizado no `methods.groupby`;
  mensagem antiga ("tem nulos; use dropna primeiro") trocada pela padrão (agora
  menciona fillna).
- **Coerência:** validar chave relacional é conceito de **Anel 2**; o C (Anel 0)
  segue genérico. Nenhum C tocado — política mora na camada Lua, mantendo a
  separação de anéis e alinhando o Anel 2 ao Contrato 6.

### Decisões e achados
- **Os dois pivots:** roadmap nomeou só `pivot_table`; `pivot` tinha o mesmo
  silent-drop. Incluídos ambos (senão a incoerência persistiria).
- **Número do contrato:** roadmap dizia "Contrato 7", mas 7 já existe ("índices
  1-based"). Documentado como **Contrato 8**; referência do roadmap corrigida.
- **Sem quebra de teste existente:** o comportamento antigo (join casa NA, pivot
  descarta) estava **sem cobertura** — foi por isso que derivou. O teste de
  groupby-NA só checava `not ok` (sobreviveu à troca de mensagem). 8 testes novos
  (4.6) travam os quatro: chave simples, NA na coluna `columns` do pivot, composta
  no groupby, validação dos dois lados no join, e NA em coluna de valores NÃO
  dispara.
- **Observação (não acionada):** join não expressa chave composta multi-coluna
  via lista de strings — `{"a","b"}` é a forma par-renomeado `{chave_esq,
  chave_dir}`, não composta. Quirk pré-existente da API de join, fora do escopo
  do item 4. Registro para eventual avaliação futura.

### Fechamento
- `[Windows]` Lua-puro, mesma categoria dos itens 2/3 (nenhum C tocado). Build
  Linux verde, parity 12/12. **Mudança de comportamento** + contrato novo, então
  os testes são o guard. Fecha por equivalência Fedora com confirmação do
  `build_win.ps1`.

---
## 2026-06-28 — Timeline item 3: bool_view (exposição na camada Lua)

### Exposição (C já existia e estava testado)
- **`bool_view` exposto** no descritor bool (`_types.lua`): uma linha
  `view = C.smaug_bool_view`. O C já tinha `smaug_bool_view` + COW interno, com
  cobertura completa em `test_allocfail.c` (view, cow_set/set_null/append/
  append_null + OOM). Item 3 é exposição + coerência de docs, não comportamento C novo.
- **Justificativa "imutável" derrubada:** BoolSeries tem `set`/`set_null`, é
  mutável; view + COW idênticos a f64/i64/dt.
- **Exceptions contraditórias removidas** (`parity/exceptions.txt`): `1:view/bool`
  ("bool tem view?") e `10:view/bool` ("imutável... nada a destacar"). As de string
  e categorical permanecem.
- **Mensagem de erro do `view()` por razão correta (3.3):** string → "ainda não
  suportado (planejado)"; categorical → "não se aplica (sem buffer compartilhável)".
  *Correção durante a implementação:* a primeira tentativa pôs o branch de
  categorical em `methods.view`, que CategoricalSeries nunca alcança (metatable
  própria) — era código morto, dava o erro cru `attempt to call method 'view'`.
  Movido para um stub `CategoricalSeries:view()`.
- **Teste Lua (3.4):** bool view + COW (reflexo da pai, detach em set/set_null/
  append, OOB) + asserções das mensagens de erro de string/categorical.
- **COW.md (3.5):** bool → ✅ view / ✅ COW; removidas as frases falsas de
  imutabilidade; bool adicionado às tabelas de funções C.

### Achado registrado (10.7)
- `test_constructors.lua` re-declara `local n_ok` por seção e imprime só no fim:
  headline "98 checks" subconta o real (~328 rodam). Cobertura é real (cada
  `check` aborta em falha); só o número engana. Registrado no item 10, não tocado
  (fora de escopo do item 3).

### Fechamento (Done — via Fedora)
- **Reavaliação de risco:** classifiquei o item como "expõe C, precisa de Windows",
  mas estava errado — item 3 **não tocou C** (só `.lua`/`.txt`/`.md`), e
  `smaug_bool_view` já estava no cdef do FFI com ABI idêntica à de `smaug_f64_view`
  (já provada no Windows). É a mesma categoria Lua-pura do item 2, não expõe C novo.
- Fechado por equivalência Fedora: suíte Lua verde (incl. bool view+COW), parity
  12/12 (eixos 1 e 10 coerentes), Valgrind-clean. Follow-up leve: confirmar no
  `build_win.ps1`. A regra "C novo não fecha por equivalência" segue válida;
  o item só não se enquadra nela.

---
## 2026-06-28 — Fechamento dos itens 1 e 2 + recuperação de regressão no entry point

### Itens fechados
- **Item 1 (Done, Fedora):** Valgrind-clean nos 12 binários (`ERROR SUMMARY: 0
  errors`, incl. allocfail e stress), suíte idêntica ao baseline, cobertura
  Linha 98.86% / Branch-alvo 95.63%. Refatoração pura de nulidade confirmada.
- **Item 2 (Done via Fedora):** Lua puro, sem C tocado. Critério `[Windows]`
  suprido por validação Fedora (mesmo LuaJIT; parity eixo 09 OK; ponto sensível
  do `_dt.lua` exercitado de fato). Follow-up leve: confirmar com
  `build_win.ps1`. **Equivalência vale só por ser Lua puro — não é regra.**

### Incidente: `lua/smaug/init.lua` (entry point) sobrescrito
- Na aplicação do item 2, o orquestrador da Series (`core/series/init.lua`) foi
  parar no entry point de topo (`lua/smaug/init.lua`), deixando os dois idênticos
  e ambos com `return Series`. Efeito: `require("smaug")` devolvia a Series
  achatada, sem o campo `.Series` — **todas** as 18 suítes Lua morriam na primeira
  linha, e o `build.sh` (`set -euo pipefail`) abortava no 1º teste Lua sem
  imprimir o erro. Não era específico do Fedora; reproduzia em qualquer lugar.
- **Causa:** dois arquivos distintos chamados `init.lua` em caminhos diferentes;
  na aplicação manual, um sobrescreveu o outro.
- **Correção:** entry point restaurado a partir do estado pré-regressão (não
  reconstruído de memória). Itens 1 e 2 nunca tocaram esse arquivo.
- **Aprendizado:** ao entregar/aplicar arquivos `init.lua`, sempre conferir o
  caminho completo e que `lua/smaug/init.lua` (termina em `return smaug`) e
  `lua/smaug/core/series/init.lua` (termina em `return Series`) permaneçam
  distintos. Se ficarem idênticos, o sintoma é `attempt to index ... 'Series'`.

---
## 2026-06-26 — Timeline item 2: sentinela único na camada Lua

### Refatoração (consumo do central — sem mudança de comportamento)
- **`_dt.lua` consome o sentinela i64 central** em vez de reinventá-lo. Removidos
  o literal cru `-9223372036854775808` (sem `LL`, virava double e batia por
  coerção frágil) em três sites e o `DT_SENTINEL` local. Produção usa `I.I64_MIN`;
  detecção usa `is_int_sentinel` (mesmo idioma de `reduce_num` em `_core.lua`).
- **Sentinela i64 documentado** na definição central (`series/init.lua`): os dois
  contextos — leitura de elemento (C devolve 0 + status `SMG_NULL_VALUE`; o 0 não
  é sentinela) vs. redução posicional (C devolve `I64_MIN`, detectado por
  `is_int_sentinel`).
- **NaN centralizado — produção e teste:**
  - Produção: `I.NAN` já existia; `_stat_adv.lua` passou a consumi-lo (três `0/0`
    crus removidos). O roadmap supunha que faltava criar a constante — só faltava
    consumir.
  - Teste: o predicado central `is_nan` era reinventado inline (`v ~= v`) em
    `_transform.lua` (que já o importava sem usar), `_stat_adv.lua` e
    `_factories.lua`. Todos passam a consumir o central. (achado de uma varredura
    ampla de sentinelas pedida em sessão; mesma natureza do item 2, registrado e
    incorporado ao 2.4.)
- **Garantia verificada:** varredura completa da camada Lua — os literais/predicados
  de sentinela (`I64_MIN`, `NAN`, `is_nan`) agora nascem em um único lugar
  (`series/init.lua`); todo o resto consome. Nenhuma outra reinvenção.
- **Lacuna registrada (não infração):** não há `is_inf`/`is_finite` central; checagens
  `== math.huge` seguem inline por falta de quem consumir. Eventual helper futuro.
- **Prova:** suíte completa verde, contadores idênticos ao baseline, parity 12/12
  (eixo 09 sentinels incluso). Item `[Windows]`, Lua puro — sem impacto em memória
  C (Valgrind n/a) nem cobertura C (gcov n/a).

---
## 2026-06-26 — Timeline item 1: fonte única de nulidade no Ring 0

### Refatoração (interna — sem mudança de contrato público)
- **Centralização da convenção de máscara de nulos em `smaug_types.h`.** Antes,
  o invariante mais central do motor (válido / NA) era testado por quatro macros
  divergentes (`VALID` em ops_f64/i64 baseada na série; `VALID_DT` em datetime;
  `VALID(m,i)` em ops_bool com assinatura *e* semântica diferentes) e por testes
  crus `== 0xFF`/`== 0x00` espalhados em core, str, ops_window e ops_str. Passou a
  existir uma fonte única.
- **Símbolos no lugar dos literais:** `SMAUG_MASK_VALID`/`SMAUG_MASK_NULL`. Toda
  escrita de máscara (`= 0xFF`, `memset`, ternários) passou a usá-los; nenhum
  literal cru de máscara permanece em código.
- **Dois contratos, por design, não por descuido:**
  - `SMAUG_VALID(mask,i)` / `SMAUG_NULL(mask,i)` — máscara presente exigida; passar
    NULL é bug e deve falhar (não silenciar). Usado por f64/i64/dt/str e pelos
    testes antes crus.
  - `SMAUG_OPTIONAL_VALID(mask,i)` — máscara opcional (NULL = "todos válidos"),
    contrato exclusivo das funções livres do bool (`smaug_bool_*`). O guard de
    NULL que o ops_bool reinventava virou esse macro nomeado. A unificação num
    único macro permissivo foi recusada: esconderia máscara ausente em código de
    Series (falha visível > acerto adivinhado).
  - `SMAUG_NULL` é, por construção, a negação de `SMAUG_VALID` — não podem divergir.
- **Escopo:** item trata dos *testes* de nulidade (1.3); incluiu ops_window/ops_str
  além de core/str (o roadmap citava os dois como exemplo, não lista exaustiva).
  Escritas ganharam o símbolo, mas **não** um setter (`SMAUG_SET_*`) — abstração
  fora de escopo, eventual subitem futuro.
- **Prova de pureza:** suíte completa verde com contadores idênticos ao baseline,
  8 arquivos tocados compilam com `-Wall -Wextra -Werror`. Confirmação final
  (Valgrind-clean + cobertura) pendente no Fedora, conforme critério `[Fedora]`.

---
## 2026-06-23 
- docs(roadmap): sincroniza métricas reais (cobertura 95.83%, checks por suíte), enxuga Blocos H/E, adiciona Bloco I (fechamento de coerência pré-v1.0) e registra achados da auditoria código-vs-código (dt_view, rank i64, rolling-dup, I3/I4)

## 2026-06-22 — Fase 5: cobertura dos parsers + correção de double-free sob OOM

### Corrigido
- **Double-free em `smaug_read_json_mem` sob OOM** (3 sites de limpeza): em
  falha de alocação durante a montagem de colunas, `col_names`/`dtypes` eram
  liberados manualmente antes de um `goto oom_recs` compartilhado que liberava
  de novo. Corrigido anulando os ponteiros após a liberação. Reproduzido por
  varredura de injeção de falha e validado Valgrind-clean (534 allocs = 534
  frees, 0 erros).
- **Double-free em `parse_record` sob OOM** (descoberto ao escrever teste de
  registro JSON largo): no crescimento do array de campos, se o `realloc` de
  `keys` sucede mas o de `vals` falha, `rec->keys` ficava apontando para o
  bloco antigo já liberado pelo realloc bem-sucedido — `free_record` do caller
  dava double-free. Corrigido atualizando `rec->keys`/`rec->vals` imediatamente
  após cada realloc bem-sucedido. Validado Valgrind-clean (1962 = 1962 frees).

### Testes / Hardening
- **Harness de allocfail estendido para `calloc` e `strdup`**: `--wrap=malloc,
  realloc` não intercepta esses dois (resolvem internamente na libc), deixando
  todos os guards de OOM sobre eles sem exercício. Adicionados `__wrap_calloc`
  e `__wrap_strdup`; flag propagada às quatro configurações de build (Makefile,
  build.sh, make_coverage.sh, build_win.ps1). Verificações 1492 → 1515
  (inclui sweep de OOM em `multi_argsort`/`multi_argsort_ffi`, antes sem
  cobertura de falha de alocação).
- **Cobertura branch-alvo dos parsers** (medição Fedora autoritativa):
  - `smaug_csv.c`: 82.64% → 90.53%
  - `smaug_json.c`: 72.30% → 89.80%
  - `smaug_datetime.c`: 72.77% → 92.40%
  - `smaug_ops_window.c`: 85.26% → 95.98%
  - **Total do backend C: 89.06% → 95.83%** (cruzou a meta global de 95%)
- Diagnóstico de densidade de teste por região (não por contagem de checks):
  revelou que os 6 macros `DT_CMP_IMPL` (gt/lt/eq/ge/le/ne) estavam testados
  de forma rasa — 1 cenário de null × 6 operadores, deixando ~28 branches
  descobertos (ramo `out_mask==NULL`, OOM de result/mask). Fechados com teste
  funcional `out_mask=NULL` nos 6 + `af_dt_compare` no allocfail.
- Auditoria de exclusões: categoria C (conveniência disfarçada) substituída por
  testes reais; categoria D (inalcançável fraco) validada por instrumentação +
  400k checks e promovida a A com justificativa formal. Condições redundantes
  (`st==NULL_VALUE || st!=OK`; `v->s != NULL` garantido) simplificadas, não
  excluídas. Novos `COV-EXCL-BR` honestos: `encode_utf8` com cp>0x10FFFF,
  ramos de pureza de inferência de dtype, while-body de deque inalcançável.

## 2026-06-21 — Aritmética numérica: promoção de tipos e divisão verdadeira


## 2026-06-20 — Coerência de construção: inferência universal de dtype

Implementação da camada Lua das decisões de coerência de API tomadas na
sessão de design anterior. Tema: a construção a partir de dados infere o
dtype de forma consistente em todos os pontos de entrada; quando o valor é
ambíguo, o engine recusa em vez de adivinhar.

### Adicionado

- **`Series` chamável:** `smaug.Series({1,2,3})` agora funciona, espelhando
  `smaug.DataSet({...})`. Alias `Series.from_array` (mantém `from_table`).
  Ambos despacham dinamicamente para `from_table`, preservando a interceptação
  de `categorical` feita no orquestrador.
- **`Series.infer_dtype`** — fonte única de inferência de dtype, reusada por
  `Series.from_table`/`full`/`__call`, `DataSet.from_columns`/`__call` e
  `Series:map`. Antes a regra estava duplicada (uma cópia no `DataSet.__call`,
  outra implícita no `map`) e divergente.

### Corrigido — incoerências de construção

- **Fim do default-float64 silencioso:** `Series.from_table` e
  `DataSet.from_columns` sem dtype caíam em `float64` independente do conteúdo;
  uma lista de strings ou booleans quebrava no `set`. Agora inferem como os
  demais construtores.
- **Bool inferido de boolean nativo:** uma lista `{true, false}` sem dtype
  agora vira `bool` (Series, DataSet e broadcast `df["c"] = true`). Antes virava
  `int64`/`float64` e quebrava ou perdia o tipo. Inferência de bool só a partir
  de `boolean` Lua — nunca de `0`/`1` ou `"yes"`/`"no"` (seria adivinhar
  semântica). Lista vazia ou toda-nula → `string` (fallback universal).
- **`map` reconhece retorno boolean:** `s:map(fn)` com `fn` devolvendo
  `true`/`false` agora infere `bool`, inclusive respeitando `dtype="bool"`
  explícito. Antes falhava — a validação rejeitava o booleano antes de honrar o
  dtype declarado.

### Decisões de contrato

- **`astype("bool")` numérico é rígido:** aceita apenas `0`→false e `1`→true
  (e `0.0`/`1.0`). Qualquer outro valor é erro orientando para `:map(fn)`, em
  vez da coerção estilo C (`≠0 → true`), que adivinhava semântica e contradizia
  o construtor rígido. String→bool inalterado (`"true"`/`"false"`, resto → null).
- **`assign` é imutável, inclusive ao substituir coluna:** retorna sempre um
  DataSet novo; o original nunca é mutado, nem quando a coluna já existe.
  Comportamento já existente, agora fixado por teste e documentado.

`test_constructors.lua`, `test_core.lua` — testes atualizados para o novo
comportamento (bool inferido, astype rígido com casos de erro explícitos) e
novo teste de imutabilidade do `assign` ao substituir coluna. Removida uma
duplicação acidental de bloco em `test_core.lua`.

### Docs

`API_INDEX.md` — `assign` marcado como retornando novo DataSet, consistente
com `filter`/`fillna`/`drop_duplicates`/`rename`.

---

## Aritmética numérica: promoção de tipos e divisão verdadeira

Segunda parte da mesma sessão. Tema: operações aritméticas entre numéricos não
barram o que é matematicamente sem ambiguidade, nem corrompem silenciosamente.
Toda a mudança é na camada Lua (o despacho de operadores); nenhuma função C mudou
— a cobertura permaneceu idêntica, confirmando que nenhum caminho novo foi criado.

### Corrigido

- **Promoção numérica em operações:** `int64` e `float64` em lados opostos de
  `+ - * /` agora promovem para `float64`, em vez de barrar com erro de tipo.
  `df["valor"] * df["quantidade"]` (float × int) passa a funcionar. Mistura com
  não-numérico (bool/string/datetime) continua sendo erro.
- **Truncamento silencioso de escalar (bug):** `int_series * 2.5` produzia
  `int64` truncando o escalar para `2` (resultado `4` em vez de `5.0`) — corrupção
  silenciosa. Agora o escalar fracionário sobre série int64 promove a série a
  `float64` antes da operação, e o resultado é correto.

### Decisões de contrato

- **`/` é divisão verdadeira:** `int64 / int64` agora produz `float64`
  (`7 / 2 = 3.5`), alinhado a Python 3, numpy e polars. Antes fazia divisão
  inteira truncada (`7 / 2 = 3`).
- **`:floordiv(outra)` — divisão inteira explícita:** repõe o comportamento que
  `/` deixou de ter. Produz `int64` truncado (`7 // 2 = 3`); divisão por zero → null.
  Exige operandos int64 (float orienta a usar `/` e converter). É o primeiro
  método aritmético nomeado da Series.

`test_constructors.lua` — testes de aritmética atualizados para o novo contrato
(promoção, `/` float) e bloco dedicado novo cobrindo promoção série×série,
série×escalar (incl. o caso que antes corrompia), `/` verdadeira e `:floordiv`.

### Docs

`API_INDEX.md` — documentada a semântica de promoção, `/` verdadeira e o método
`:floordiv`.

---

## 2026-06-17 — Sincronização dos scripts de build com a estrutura da Fase 4

Auditoria completa de `scripts/` (a pedido), motivada pela revisão do Roadmap.
A Fase 4 reorganizou os testes em subpastas (`tests/c/`, `tests/series/`,
`tests/dataset/`, `tests/io/`, `tests/props/`), mas os scripts de build não
acompanharam — continuavam apontando para os arquivos legado na raiz de
`tests/`. A auditoria revelou dois bugs reais (não apenas cosméticos), além da
divergência estrutural.

### Bug 1 — `.so` incompleta no `build.sh` (corrigido)

`build.sh` montava `build/libsmaug.so` a partir de 9 fontes, **sem**
`src/smaug_ops_window.c`. Esse arquivo define `smaug_multi_argsort_ffi` e toda
a família `smaug_{f64,i64}_rolling_*` — símbolos que o `ffi_loader.lua` declara
e consome. A `.so` gerada pelo `build.sh` ficava sem eles: qualquer uso de
rolling ou sort multi-coluna pelo frontend Lua quebraria em runtime com símbolo
indefinido. Confirmado por `nm -D` (0 símbolos antes, 10 depois). O Makefile e
o `build_win.ps1` (que descobre `src/*.c` por glob) já estavam corretos —
o bug era exclusivo do `build.sh`.

### Bug 2 — cobertura cega em `make_coverage.sh` (corrigido)

`make_coverage.sh` não incluía `smaug_ops_window` nos `SRCS` instrumentados nem
`test_ops_window` na lista de testes C. Resultado: as primitivas migradas para
Ring 0 na Fase 3 (cumsum, cumprod, cummin, cummax, diff, shift, ffill, bfill,
argmin, argmax, sorted_nonnull, rank, multi_argsort, rolling) ficavam **fora da
medição inteira de cobertura** — invisíveis ao gcov. Agora entram na medição do
Fedora pela primeira vez.

### Divergência estrutural — scripts realinhados à Fase 4

Três fontes de build apontavam para o legado da raiz; agora todas usam a
estrutura por domínio:

- **`build.sh`** — `SRCS` += `smaug_ops_window.c`; `C_TESTS_PLAIN` += `test_ops_window`;
  testes C compilam de `tests/c/`; `LUA_TESTS` passou a listar as 18 suítes em
  subpasta (`series/…`, `dataset/…`, `io/…`, `props/…`).
- **`build_win.ps1`** — testes C de `tests\c\`; lista Lua atualizada para as
  18 suítes; normalização de separador (`/`→`\`) no caminho do luajit; cabeçalho
  corrigido (era "8 suites Lua").
- **`make_coverage.sh`** — `SRCS` e `C_TESTS` corrigidos (ver Bug 2); testes C e
  `test_allocfail` de `tests/c/`; `LUA_TESTS` para as 18 suítes; comentário do
  cabeçalho citava `test_enrich_c` (inexistente) — corrigido.
- **`Makefile`** — embora fora de `scripts/`, é a "fonte única" que os scripts
  espelham. Compilava os testes C da raiz (`tests/$t.c`); realinhado a
  `tests/c/$t.c` nos três alvos (`test`, `test-stress`, wrap). Sem isso,
  `make test` quebraria ao remover o legado.
- **`scripts/parity/11_test_coverage.lua`** (Eixo 11) — lia 5 arquivos
  inexistentes na raiz (que retornariam 0 checks); reapontado para as 18 suítes
  reais. Os demais eixos (01–10, 12) e `common.lua` já tinham fallback
  mono↔pasta e não precisaram de mudança.

### Lixo removido

`scripts/parity/PARITY_REPORT.md` — relatório de paridade órfão (gerado em
14/jun). Os scripts `parity.sh`/`parity.ps1` escrevem em `docs/PARITY_REPORT.md`;
essa cópia em `scripts/parity/` nunca era regravada e entrava no MANIFEST
indevidamente. Removida.

### Legado da raiz removido

Após o realinhamento, os 28 `.lua` + 12 `.c` + 5 fixtures (`.csv`/`.json`) na
raiz de `tests/` tornaram-se órfãos — nenhum script ativo os referenciava.
Removidos. Teste de fogo antes da remoção: mover todo o legado para fora e rodar
`build.sh` + `make test` + `make test-stress` — tudo passou apenas com a
estrutura nova, confirmando zero dependência residual.

### Validação

`build_win.ps1` verde no Windows (MSYS2-UCRT64): DLL com 10 fontes, 12
testes C (incl. `test_ops_window` 207 checks, `test_io_c` 190 checks), 18 suítes
Lua, 12 eixos de paridade OK, property-based 360 862 checks. MANIFEST: 113
arquivos (era 154 antes da limpeza). Valgrind + cobertura no Fedora pendentes
(autoritativos; gcov não é confiável no Windows).

**Métricas de doc desatualizadas (a corrigir na revisão do Roadmap):** o Anel 0
no Roadmap ainda cita `test_io_c` com 174 checks (real: 190), não menciona
`test_ops_window`, e diz "9 binários" (real: 12). Essas e outras inconsistências
ficam para a sessão de revisão do Roadmap.

---

## 2026-06-16 — Fase 4: reorganização estrutural (series/, dataset/, tests/)

Reorganização dos monolíticos do Ring 1 em módulos coesos e da suíte de testes
em subpastas por domínio. Zero alteração de comportamento — todas as sessões
confirmadas por `make test` + `make test-lua` + `parity.sh 12/12`.

### Ciclo 1 — series.lua (4389 linhas) → series/ (16 submódulos)

`lua/smaug/core/series.lua` desmembrado em:

```
series/
├── init.lua               ← orquestrador (17 etapas)
├── _types.lua             ← DTYPES (5 descritores)
├── _core.lua              ← metatipo Series, methods, wrap, check_*, require_op
├── _factories.lua         ← new, float64, int64, from_table, full
├── _bool_ops.lua          ← bool_mask_parts, binop, kleene_binop, metamétodos
├── access/_access.lua     ← get, set, is_null, set_null, append, len, clone
├── access/_transform.lua  ← sort, argsort, view, take, head, tail, astype, fillna, map
├── stats/_reduce.lua      ← sum, mean, min, max, var, std
├── stats/_stat.lua        ← prod, median, quantile, mode, unique, nunique, value_counts, describe
├── stats/_stat_adv.lua    ← cov, corr, rank, pct_rank, skew, kurtosis, mad, sem
├── window/_cumulative.lua ← cumsum, cumprod, cummin, cummax, diff, shift, ffill, bfill, argmin, argmax
├── window/_rolling.lua    ← SeriesRolling + SeriesExpanding
├── selection/_predicates.lua ← between, isin, is_unique, is_monotonic_*, equals, compare,
│                                idxmin, idxmax, first/last_valid_index, duplicated, searchsorted, rep_each
├── selection/_selection.lua  ← where, mask, ifelse, nlargest, nsmallest, gt/lt/eq/ge/le/ne,
│                                filter, land/lor/lxor/lnot, sin/cos/..., isna, notna
├── text/_str.lua          ← StrProxy Tier A+B+C
├── temporal/_dt.lua       ← SeriesDT (base + F.3) + SeriesAt
└── categorical/_categorical.lua ← CategoricalSeries + CatProxy
```

Mecanismo: cada submódulo é `return function(I)` onde `I` é o módulo interno
montado progressivamente em `init.lua`. Zero `require` cruzado entre submódulos;
upvalues passados via `I`. `scripts/parity/common.lua` ganhou `read_series_lua()`
para análise estática de paridade com a estrutura em pasta.

### Ciclo 2 — dataset.lua (2256 linhas) → dataset/ (4 submódulos)

`lua/smaug/core/dataset.lua` desmembrado em:

```
dataset/
├── init.lua         ← orquestrador (4 etapas)
├── _core.lua        ← factories, CRUD, acesso, seleção, assign, nunique, rename,
│                       describe, to_table, __tostring, __index, __newindex, __len, __call
├── _relational.lua  ← concat, join, GroupBy, pivot, melt, pivot_table, stack, unstack, explode
├── _stat.lua        ← corr, cov, equals, compare, duplicated, drop_duplicates, Rolling DataSet
└── _io_support.lua  ← at, iat, insert, to_dict, from_dict, to_markdown, to_string
```

Mesmo mecanismo de `I` do Ciclo 1. `I.map_columns` e `I.cell_str` exportados
por `_core.lua` para uso nos submódulos subsequentes.
`scripts/parity/common.lua` ganhou `read_dataset_lua()`.

### Ciclo 3 — tests/ reorganização (28 arquivos → 18 suítes em subpastas)

```
tests/
├── series/    ← 10 suítes (constructors, access, reduce, stat, window,
│                 predicates, selection, str, dt, categorical)
├── dataset/   ← 4 suítes (core, relational, stat, io_support)
├── io/        ← 2 suítes (test_csv, test_json)
├── props/     ← 2 suítes (test_props, test_integration)
├── fixtures/  ← 5 arquivos de dados (cotacoes.*, pedidos_digitados.csv)
└── c/         ← 12 arquivos .c (cópias dos testes C originais)
```

`Makefile` atualizado com quatro variáveis por domínio (`LUA_TESTS_SERIES`,
`LUA_TESTS_DATASET`, `LUA_TESTS_IO`, `LUA_TESTS_PROPS`); `LUA_TESTS` é a
sua concatenação. Path `tests/fixtures/pedidos_digitados.csv` atualizado nos
testes de I/O.

### Resultado

- `make test` (12 C): PASS
- `make test-lua` (18 suítes): PASS
- `parity.sh`: 12/12

---

## 2026-06-16 — Fase 3 Grupos A+B (Ring 0) + G.1 UTF-8 JSON

Início da Fase 3: migração de primitivas Lua puro para Ring 0 (C), guiada
pelo Bloco G. Duas frentes paralelas nesta sessão: G.1 (bloqueante de release)
e Grupos A+B do inventário de primitivas.

### G.1 — Decodificação UTF-8 no reader JSON

Eliminada a degradação silenciosa `\uXXXX → '?'` que existia em
`smaug_json.c`. Implementação completa em `read_json_string`:

- `read_hex4`: lê 4 dígitos hex → codepoint; retorna -1 se hex inválido.
- `encode_utf8`: codepoint → 1–4 bytes UTF-8 (cobre U+0000–U+10FFFF).
- BMP (U+0000–U+FFFF): decodificado diretamente.
- Surrogate pairs (`\uD800–\uDBFF` + `\uDC00–\uDFFF`): montados em
  codepoint suplementar (U+10000–U+10FFFF) e codificados em 4 bytes UTF-8.
- Surrogate isolado ou hex inválido → `TOK_ERROR` → `make_error` com
  mensagem clara. Nunca silencioso.

`.str` permanece byte-oriented — contrato inalterado. `str:len()` retorna
bytes, não codepoints. `test_io_c`: 174 → 190 checks (+16, 8 casos unicode).

**Motivação:** `json.dumps` Python com `ensure_ascii=True` (default) serializa
qualquer não-ASCII como `\uXXXX`. Dados brasileiros reais (nomes, cidades com
acento) produzem escapes rotineiramente. O `'?'` silencioso era bug de
integridade indetectável em produção.

### Grupo A — 10 primitivas O(N) para Ring 0

Migradas de Lua puro para C em `smaug_ops_f64.c` e `smaug_ops_i64.c`,
declaradas em `smaug_numeric.h`, registradas no `DTYPES` de `series.lua`
e no `ffi_loader.lua`:

`cumsum`, `cumprod`, `cummin`, `cummax`, `diff`, `shift`, `ffill`, `bfill`,
`argmin`, `argmax` — para `smaug_series_f64_t` e `smaug_series_i64_t`.

**Contratos relevantes:**
- `cummin`/`cummax`: nulos não propagam para frente (posição nula fica nula,
  mas as seguintes continuam recebendo o acumulado). Contrato mais útil que o
  `cumsum`/`cumprod` onde null contamina o restante.
- `diff` datetime: permanece Lua (usa `smaug_dt_diff_ms`).
- `shift` negativo (periods < 0): permanece Lua (C usa `size_t`).
- `argmin`/`argmax`: retornam `SIZE_MAX` se série vazia ou toda-null; Lua
  converte `SIZE_MAX → nil` e ajusta 0-based → 1-based.
- `cummin`/`cummax`/`ffill`/`bfill` datetime: fallback Lua via nil-check em
  `self._d.xxx`.

Regra de migração aplicada: todas as funções C registradas nos descritores
`DTYPES` (`float64` e `int64`) e acessadas via `self._d.fn(self._c)` — nunca
`C.smaug_f64_fn` diretamente no corpo do método.

### Grupo B — sorted_nonnull e rank para Ring 0

Migradas de Lua puro para C:

- `smaug_f64_sorted_nonnull` / `smaug_i64_sorted_nonnull`: coleta não-nulos
  em `double*` / `int64_t*` ordenado crescente. Série toda-null retorna
  `NULL` com `*out_n = 0` (não é erro). Caller libera com `smaug_free`.
- `smaug_f64_rank` / `smaug_i64_rank`: rank 1-based com 4 methods
  (0=average, 1=min, 2=max, 3=first). Nulos → `NAN` no resultado.
  Caller libera com `smaug_free`.

Comparadores (`cmp_double`, `cmp_rank_pair`, `cmp_i64`, `cmp_i64_rank_pair`)
definidos como `static` no escopo do arquivo — C11 padrão, sem extensões GCC.

**Consumidores Lua reescritos:** `median`, `quantile`, `nlargest`, `nsmallest`,
`skew`, `kurtosis`, `mad`, `sem`, `rank`, `pct_rank` — todos delegam para C
via `c_sorted_nonnull` (helper Lua que chama a primitiva C e devolve
`ffi.new double[]` uniforme). `datetime` e `mad` (segundo passe sobre desvios)
permanecem com fallback Lua.

Grupo B não usa `DTYPES`: as funções retornam ponteiros brutos (`double*`,
`int64_t*`), não `smaug_series_*_t` — são primitivas de buffer chamadas
diretamente pelos métodos, não via descritor de dtype.

### Testes

`test_ops_window.c` — novo, cobre Grupos A e B: 150 checks.
ASan+UBSan limpos. `test_allocfail` estável em 1158 verificações.

### Próximo

Fase 3 Grupo C: `multi_argsort` composto (DataSet) e `SeriesRolling:_agg`,
após medição de performance no Windows.

---



Último sub-bloco do enriquecimento dos núcleos. Com ele, **o Bloco F inteiro
(F.1–F.6) está fechado**.

### Adicionado

- **Series:** `duplicated([keep])` (keep ∈ {first,last,none}; null conta como
  valor — dois nulos são duplicatas entre si, semântica pandas);
  `drop_duplicates([keep])`; `combine_first(other)` (preenche nulls de self com
  other); `searchsorted(value, [side])` (busca binária, exige série ordenada
  crescente verificada via `is_monotonic_increasing`; side ∈ {left,right});
  `rep_each(n)` (repete cada elemento n vezes; n escalar ≥0 ou `Series<int64>`).
- **DataSet:** `duplicated([subset], [keep])` (subset = nome/lista/nil) e
  `drop_duplicates([subset], [keep])` (multi-coluna).

**Decisões de contrato:**
- O nome do método de repetição é `rep_each`, não `repeat`: `repeat` é palavra
  reservada em Lua e impediria tanto a definição (`function methods.repeat`)
  quanto a chamada (`s:repeat(n)`) — ambas falham no parse. `rep_each` deixa a
  intenção explícita (repete cada elemento) e segue o espírito do `:rep` já
  existente no `.str`.
- `duplicated` reaproveita o mesmo esquema de chave de `unique`/`nunique`
  (`type:tostring`, mais sentinela própria para null), garantindo semântica
  consistente de igualdade em todo o frontend.
- `combine_first` exige dtype e tamanho iguais — não faz coerção implícita.
- `searchsorted` exige ordenação crescente e rejeita séries com nulos (não há
  ordem definida com null), com erro claro em vez de resultado silenciosamente
  errado.

`test_duplicates.lua` (74 checks).

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `Series.methods` 90→95, `DataSet.methods`
46→48. Roadmap marca F.6 e o **Bloco F** inteiro como `[Done]`.

---

## 2026-06-15 — Bloco F.5 (acesso e ergonomia)

### Adicionado

- **Series:** `at`/`iat` — acesso escalar posicional. Implementado via proxy no
  `__index` que suporta tanto indexação (`s.at[i]`) quanto chamada (`s.at(i)`),
  cobrindo a sintaxe pandas-like e a forma idiomática Lua. Em Series 1-D, `at` e
  `iat` são equivalentes (índice = posição). Ambos delegam a `get`, herdando o
  guard de bounds.
- **DataSet:** `at(i, col)` (célula por nome) e `iat(i, ci)` (célula por índice
  posicional de coluna); `insert(loc, name, series)` (insere em posição 1-based,
  desloca as seguintes); `to_dict([orient])` (`"columns"` default ou `"records"`);
  `from_dict(t, [orient])` (construtor com inferência de dtype por coluna);
  `to_markdown()` (GitHub-flavored, sem o limite de 10 linhas do `__tostring`);
  `to_string([opts])` (texto plano com `max_rows` opcional).

**Decisões de contrato:**
- `at`/`iat` no DataSet são métodos chamáveis (`df:at(i, col)`), não indexers de
  duplo subscrito — Lua não tem `tbl[i, col]`. A forma de chamada é a tradução
  fiel e sem ambiguidade.
- `from_dict` orient `"columns"`: ordem das colunas é indefinida em Lua (chaves
  de tabela), então aceita `t._order` (lista de nomes) para ordem determinística;
  sem ele, ordena alfabeticamente. Orient `"records"`: colunas pela união das
  chaves (1ª aparição); chave ausente em um registro → NA naquela linha.
- `from_dict` infere dtype por coluna: string domina; senão bool puro; senão
  float se houver não-inteiro; senão int64; coluna toda-nula → string.

`test_access.lua` (54 checks), incluindo roundtrip `to_dict→from_dict`, bordas de
`insert` e erros de acesso.

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `DataSet.methods` 40→46 (`from_dict` é
função de classe, documentada à parte como `from_columns`). Roadmap marca F.5
`[Done]`.

---

## 2026-06-15 — Portabilidade de I/O + Blocos F.3 e F.4 + sync de builds

### Corrigido — testes de I/O com path hardcoded (Windows)

`build_win.ps1` falhou em `test_io_c`, `test_io` e `test_io_real`: os testes
escreviam em `/tmp/...`, que não existe no Windows/UCRT64. Não era regressão da
biblioteca — `to_csv`/`smaug_write_csv` reportaram fielmente a falha de escrita.
Introduzido helper `tmp_path` (um em C, um em Lua) que resolve o diretório
temporário via `TMPDIR`→`TMP`→`TEMP`→`/tmp`, montando o caminho com separador
`/` (aceito pela CRT do Windows e pelo POSIX). Detalhe que exigiu cuidado:
`os.getenv` devolve `""` (truthy em Lua), não `nil`, para variável vazia — o
helper trata string vazia como ausente, espelhando o `!dir || !*dir` do C.
Validado em três cenários: fallback `/tmp`, `TEMP` setado, e variável vazia.

### Adicionado — Bloco F.3: accessor `.dt` estendido

Toda a lógica de calendário derivada vive no Ring 1 (Lua), reaproveitando as
primitivas C (`year`/`month`/`day`/.../`from_parts`/`truncate`/`add_ms`). Nenhuma
mudança no Ring 0 — funções de calendário derivadas são responsabilidade do
frontend.

- **Predicados** (→ `Series<bool>`): `is_month_start`/`is_month_end`,
  `is_quarter_start`/`is_quarter_end`, `is_year_start`/`is_year_end`,
  `is_leap_year` (regra gregoriana completa, incluindo a exceção secular ÷400).
- **Atributos:** `days_in_month` (→ int64), `month_name`/`day_name` (inglês fixo).
- **Período:** `round(unit)`/`ceil(unit)` complementam o `truncate` (= floor) já
  existente. `ceil` retorna o próprio valor quando já alinhado; `round` usa
  half-up no empate (consistente com pandas). `next_period` usa `from_parts`
  para unidades de calendário (M/Q/Y, comprimento variável) e `add_ms` para as
  de comprimento fixo.
- **`normalize()`:** zera a hora (= `truncate("D")`), nome herdado do pandas.
- **`strftime(fmt)`:** tokens `%Y %y %m %d %H %M %S %I %p %j %B %b %A %a %%`;
  token desconhecido é mantido literal (com o `%`).

`test_dt_extended.lua` (65 checks), com casos seculares (1900 não-bissexto, 2000
bissexto), empates de round e meia-noite/meio-dia para `%I`/`%p`.

### Adicionado — Bloco F.4: accessor `.str` Tier C

ASCII puro, sem regex, sem Unicode — consistente com Tier A/B. Reaproveita os
helpers `str_map` (→ Series<string>) e `bool_map` (→ Series<bool>) existentes.

- **count(sub):** ocorrências literais não-sobrepostas → int64. `sub` vazio é
  erro (contagem indefinida / risco de loop).
- **Predicados** (→ Series<bool>): `isalnum`/`isalpha`/`isdigit`/`isspace`/
  `islower`/`isupper`. Semântica Python: string vazia → false; `islower`/
  `isupper` exigem ao menos uma letra e nenhuma da caixa oposta.
- **removeprefix/removesuffix:** remoção literal de afixo, no máximo uma vez,
  idempotente quando não casa.
- **capitalize/title/swapcase:** caixas ASCII. `title` trata qualquer não-letra
  como separador de palavra.
- **join(sep):** atalho de `:cat` (mesma saída: string Lua única). Mantido pelo
  nome familiar de pandas/Python.

`test_str_tier_c.lua` (61 checks), incluindo vazias, nulos, não-ASCII em `title`
(não quebra), e contagem não-sobreposta.

### Sincronização das três fontes de build

`build_win.ps1` estava atrás em duas dimensões: faltava `test_datetime_c`
(C) e seis suítes Lua (`test_datetime`, `test_categorical`, `test_completeness`,
`test_dt_extended`, `test_stats`, `test_predicates`). Alinhado ao Makefile
canônico — as três fontes (`Makefile`, `build.sh`, `build_win.ps1`) agora
rodam o conjunto idêntico, verificado por diff: 9 binários C plain + allocfail +
stress, e 26 suítes Lua.

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `SeriesDT:*` 19→33, `StrProxy:*` 15→28.
Roadmap marca F.3 e F.4 `[Done]`.

---

## 2026-06-15 — Completude de paridade + Blocos F.1 e F.2

Sessão de fechamento de lacunas antes de avançar o enriquecimento dos núcleos.

### Corrigido — checkup de build e oráculos de teste

Auditoria do `Makefile` e do `build.sh` expôs que `make test`/`make valgrind`
não exercitavam `test_io_c` nem `test_datetime_c` (375 checks C fora do CI), e
que `LUA_TESTS` cobria 8 de 21 suítes (362k+ checks ignorados pelo `make`). As
duas listas foram completadas e sincronizadas entre `Makefile` e `build.sh`.
Removido um warning `-Wunused-variable` em `test_io_c.c:315` (`s` capturada e
nunca usada). Build agora zero-warning também nos binários de teste.

### Adicionado — completude de métodos em datetime e categorical

Auditoria do `PARITY_REPORT.md` (Eixo 1) apontou 17 ausências sem registro.
Decisão: nesta fase de completude, **implementar**, não registrar exceção.

- **datetime (7):** `argmin`/`argmax`/`cummin`/`cummax`/`median`/`quantile`
  passam a aceitar datetime — operam sobre epoch_ms (já numérico), guard
  estendido. `diff` em datetime retorna `Series<int64>` (duração em ms, não
  timestamp — diferença de dois instantes é uma duração).
- **categorical (10):** `isna`/`notna` (aliases), `min`/`max` (lexicográfico
  sobre labels), `ffill`/`bfill` (opera ao nível de codes), `shift`, `map`
  (retorna Series do dtype inferido), `where`/`mask` (seleção condicional,
  retornam novo CategoricalSeries).

`test_completeness.lua` (93 checks) pina cada comportamento, incluindo nulos e
erros de bounds.

### Adicionado — Bloco F.1: pacote estatístico

- **Series:** `corr(other)` (Pearson ∈ [-1,1]), `cov(other)` (covariância
  amostral ÷ n-1), `autocorr([lag])` = `:corr(:shift(lag))`, `dot(other)`
  (produto interno), `pct_change([periods])`.
- **DataSet:** `corr()` / `cov()` retornam matriz N×N como DataSet (coluna
  identificadora `__index__` + uma coluna float64 por variável numérica;
  colunas não-numéricas ignoradas).

**Decisões de contrato:**
- `corr`/`cov` **pulam** pares onde qualquer operando é null (semântica pandas);
  menos de 2 pares válidos ou variância zero → NaN.
- `dot` **propaga** null (qualquer par com null → resultado null) — diferente de
  corr/cov, porque produto interno não tem semântica de "ignorar" sem mudar o
  significado do resultado.
- `pct_change` com divisor zero → null (não Inf), por previsibilidade.

`test_stats.lua` (60 checks) com valores de referência calculados à mão.

### Adicionado — Bloco F.2: pacote de predicados

- **Series:** `between(lo, hi, [inclusive])` (inclusive ∈ {both,left,right,
  neither}), `isin(values)`, `is_unique()`, `is_monotonic_increasing/
  decreasing([strict])`, `equals(other)` (igualdade estrutural com NaN==NaN),
  `compare(other)` (diferenças → DataSet `{i,self,other}`), `idxmin`/`idxmax`
  (aliases de argmin/argmax), `first_valid_index`/`last_valid_index`.
- **DataSet:** `equals(other)` (colunas+ordem+dtypes+valores), `compare(other)`
  (diferenças célula a célula → DataSet `{linha,coluna,self,other}`).

**Decisões de contrato:**
- `between`/`isin` propagam null (resultado null naquela posição).
- `is_monotonic_*`: qualquer null quebra a monotonicidade (sem ordem definida
  com o vizinho). Série vazia/de 1 elemento é monotônica (vacuamente).
- `equals`/`compare` tratam NaN como estruturalmente igual a NaN (diferente de
  IEEE 754) — a pergunta é "são a mesma série", não "são numericamente iguais".
- `compare` (Series) retorna só as posições que diferem; DataSet vazio se
  idênticas. `compare` (DataSet) normaliza `self`/`other` para string porque as
  colunas têm dtypes heterogêneos.

`test_predicates.lua` (78 checks).

### Docs

`API_INDEX.md` atualizado — Eixo 12 (sincronização docs↔código) de 88/97/60/77%
para **100% nas 7 categorias** (206 métodos documentados). Reduções e
comparações antes agrupadas em uma linha (`:sum/mean/...`) foram separadas em
entradas individuais para o checker detectar por nome exato. Roadmap marca F.1
como `[Done]`.

---

## 2026-06-14 — Decisão: enriquecimento dos núcleos entra na v1.0

Após auditoria comparativa contra a API pública do pandas (Series + DataFrame),
decisão arquitetural: a v1.0 não fecha com o mínimo viável. Fecha com cobertura
operacional ampla, mantendo zero dependências externas.

**6 pacotes adicionados ao Pré-1.0 (Bloco F):**
- F.1 — Estatístico (`corr`/`cov`/`autocorr`/`dot`/`pct_change`)
- F.2 — Predicados (`between`/`isin`/`is_unique`/`is_monotonic_*`/`equals`/`compare`/`idxmin`/`idxmax`/`first/last_valid_index`)
- F.3 — `.dt` estendido (`is_*_start/end`/`is_leap_year`/`days_in_month`/`round`/`ceil`/`strftime`/`normalize`/`month_name`/`day_name`)
- F.4 — `.str` Tier C parcial (`count`/`isalnum`/`isalpha`/etc/`removeprefix`/`removesuffix`/`capitalize`/`title`/`swapcase`/`join`) — sem regex, sem Unicode
- F.5 — Acesso e ergonomia (`at`/`iat`/`insert`/`to_dict`/`from_dict`/`to_markdown`/`to_string`)
- F.6 — Duplicatas e binárias (`duplicated`/`drop_duplicates`/`combine_first`/`searchsorted`/`repeat`)

**Decisões de não-fazer (permanentes, registradas em Roadmap.md):**
- Index nomeado e toda família dependente (`loc`/`MultiIndex`/`reindex`/`align`/
  `set_index`/`reset_index`/`xs`/`swaplevel`/`droplevel`/`at_time`/`between_time`/
  `asof`/`asfreq`/`resample`/`to_period`/`to_timestamp`/`tz_*`).
- Plotting (`.plot`/`.hist`/`.boxplot`).
- I/O exótico (`pickle`/`hdf`/`xarray`/`stata`/`clipboard`/`latex`/`orc`/`feather`/
  `html`/`style`/`__dataframe__`).
- Tipos extras (`sparse`/`list`/`struct`/`period`/`timedelta`/`interval`/`decimal`).
- Operadores reversos (`radd`/`rsub`/etc.) — não-issue em Lua.
- `pipe`/`combine`/`update`/`squeeze`/`to_frame`.

**Trade-off:** v1.0 atrasa em ~6 sessões. Aceito conscientemente porque
v1.0 com cobertura ampla muda a régua do projeto — quando alguém abrir o README,
vê paridade significativa com pandas no que importa, sem o ruído.

Roadmap.md tem a lista detalhada de cada pacote, justificativa de cada
decisão de não-fazer, e checklist atualizado.

---

## 2026-06-14 — Tier 2 dtypes + bugfix Valgrind dos parsers I/O

### Adicionado — datetime no frontend Lua

Backend C de `smaug_datetime.c` já estava pronto (epoch ms UTC, calendário
Gregoriano proléptico, 201 checks em `test_datetime_c`). Esta sessão fechou
a integração com o frontend:

- Descriptor `datetime` no `DTYPES` de `series.lua` (factory, set/get com
  string ISO 8601 ou epoch_ms, append, comparações, sort/filter/take).
- Accessor `.dt` com 19 métodos: 11 componentes calendário (`year`/`month`/
  `day`/`hour`/`minute`/`second`/`ms`/`weekday`/`yearday`/`quarter`/`week`),
  `format`, `truncate(unit)` para `s/m/h/D/W/M/Q/Y`, `diff([periods])` em
  milissegundos, `add_ms`/`add_days`/`add_hours`/`add_minutes`/`add_seconds`.
- Helpers públicos: `Series.dt_parse`, `Series.dt_format`, `Series.dt_from_parts`,
  `Series.datetime(size, name)`.
- `astype` estendido com 6 branches novos: `datetime ↔ string` (via ISO 8601),
  `datetime ↔ int64`, `datetime ↔ float64` (epoch_ms).
- `describe` estendido com branch `datetime` — retorna `{dtype, count, nulls, min, max}`
  onde min/max são strings ISO 8601 formatadas.
- `test_datetime.lua` (188 checks): factories, `.dt`, comparações, sort, filter,
  astype, integração DataSet (filter/sort_by/assign/select/head/dropna/describe).

### Adicionado — categorical (Lua puro)

`CategoricalSeries` implementado inteiramente em Lua usando dictionary encoding.
Decisão consciente de não criar C backend — o tipo é essencialmente um índice
+ tabela de strings, não justifica fragmentar o contrato C.

- Armazenamento: `_codes` (int 1-based; nil = null), `_levels` (lista ordenada
  por primeira aparição), `_level_map` (hash inverso).
- Factories: `Series.from_table(arr, "categorical")`, `Series.Categorical.from_codes(...)`.
- 31 métodos de instância (espelham `Series` onde cabe): acesso, append,
  clone/head/tail/take/filter/dropna/fillna, sort/argsort (lexicográfico),
  comparações (`eq`/`ne`/`lt`/`le`/`gt`/`ge`), `unique`/`nunique`/`value_counts`,
  `describe`, `astype` (para `string`, `int64`, `float64`), `to_table`.
- Accessor `.cat` com 6 métodos: `codes()` → `Series<int64>`, `levels()`,
  `rename_categories`, `set_categories`, `add_categories`, `remove_categories`.
- Integração total com DataSet: `add_column`, `update_column`, `assign`,
  `__newindex`, `__call` todos aceitam `CategoricalSeries`. Princípio
  "toda coluna aceita pelo DataSet funciona em toda a API do DataSet".
- `test_categorical.lua` (199 checks).

### Corrigido — leaks nos parsers I/O capturados pelo Valgrind

Após validar `datetime` + `categorical` no Fedora com `make valgrind`, o
Valgrind capturou ~762 bytes vazando em 79 blocos no `test_allocfail`. Stack
traces apontaram para `smaug_csv.c:227` (strdup de `col_names`) e
`smaug_json.c:267/273` (malloc/calloc após strdups).

**Bugs identificados:**
- Em ambos os parsers, quando `calloc(dtypes)` ou alocações subsequentes
  falhavam **depois** do loop de strdup de `col_names[c]`, o cleanup fazia
  `free(col_names)` (o array) mas não liberava as strings individuais.
- No CSV, o label `done:` (alcançado quando `smaug_X_create` falha no loop
  final) liberava `col_names` mas não os strdups dos índices ainda não
  transferidos para `t->columns[c].name`.
- No JSON, `oom_recs:` libera `recs` mas nem `col_names` nem `dtypes` eram
  visíveis no escopo do label.

**Estratégia comum:**
- Inicializar `col_names[c] = NULL` antes do loop de strdup; libertar
  parcialmente em caso de falha.
- Marcar transferência de ownership com `col_names[c] = NULL` ao atribuir
  ao `tbl->columns[c].name`. `free(NULL)` é seguro, o cleanup itera pelo
  array inteiro.
- No JSON, mover `col_names`/`dtypes` para o escopo da função (com `n_cols_io`)
  para serem visíveis no label de cleanup. No CSV, estender `done:` para
  liberar strdups não-transferidos.

Resultado: Valgrind 100% clean em todos os 9 binários no Fedora. `test_allocfail`
com 15330 allocs / 15330 frees, `test_stress` com 90751/90751.

### Corrigido — warning `-Wtype-limits` no test_allocfail

`t->nrows >= 0` onde `nrows` é `size_t` (unsigned) — sempre verdadeiro.
Substituído por `1` constante; o check útil (`!t || t->error`) permanece.

### Decisão — NDJSON adiado para pós-1.0

Tentativa de implementar NDJSON expôs limitação fundamental: o parser JSON C
infere dtypes por linha. Uma linha com `"a":null` infere `string`, conflitando
com outra linha com `"a":1` que infere `int64`. Sem schema global declarativo,
NDJSON é inerentemente frágil para dados com null. Decisão: adiar para o ciclo
do schema/ORM (v2.0). Registrado em `Roadmap.md`.

### Cobertura

Linha 95.99% (2248/2342), branch-alvo 88.12% (2270/2576, 90 exclusões).
Queda em relação a sessões anteriores (96.99% / 88.82%) é resultado dos
cleanup paths novos — código adicionado mas ainda não exercitado pelo
`test_allocfail`. Vai ser fechado no hardening global.

---

## 2026-06-14 · f66ba99 — Anel 3 completo + hardening I/O

### Adicionado — Anel 3: I/O CSV e JSON

Parsers próprios em C puro, zero dependências externas. Fronteira
`smaug_table_t` como contrato entre leitores e o frontend Lua — todo
leitor produz uma `smaug_table_t`, o frontend consome e monta um `DataSet`.
Adicionar novos formatos (Parquet, SQLite) é implementar um novo produtor
sem tocar no núcleo.

```lua
-- leitura com inferência automática de tipo
local ds = smaug.read_csv("pedidos.csv", {sep = ";"})
local ds = smaug.read_json("cotacoes.json")

-- escrita
ds:to_csv("saida.csv")
ds:to_json("saida.json", {pretty = true})

-- em memória (sem arquivo)
local buf = ds:to_csv_mem()
local ds2 = smaug.read_csv_mem(buf)
```

Inferência de tipo no CSV: cada coluna é testada em ordem `int64 → float64 → bool → string`.
Coluna mista sobe para o tipo mais abrangente. Células vazias e `NA`/`null`/`N/A`/`nan`/`NaN`/`NULL`
viram null. Separador, aspas e header configuráveis.

JSON suporta o formato array de records `[{...}, {...}]` com escape completo
(`\n`, `\t`, `\\`, `\"`, `\uXXXX`) e writer compacto/pretty. `NaN` → `null`
no JSON (sem representação JSON para NaN).

### Adicionado — test_io_c.c (174 checks)

Cobertura C direta dos parsers: CRLF, CR-only, sem newline final, TSV,
sem header, aspas RFC 4180, aspas escapadas, aspas não fechadas, newline
em campo, NA padrão e customizados, inferência de todos os tipos, linha curta,
linha com 20 colunas, campo longo > 32 bytes, writer com NaN/sep/quote/sem-header/arquivo,
JSON completo, roundtrips, erros de arquivo/path inválido.

### Adicionado — test_io_real.lua (55 checks) com dados reais

`tests/pedidos_digitados.csv`: 916 linhas, 15 colunas, separador `;`, vírgula
decimal, 5 empresas (DB10/DC10/DG10/DP10/DS10), 5 marcas de produto.
Valida leitura, groupby, filter, join e roundtrips sobre dados reais.

Fixtures de cotações: `cotacoes.csv`, `cotacoes.json`, `cotacoes_USD_BRL.json`,
`cotacoes_SHIB_BRL.json` — float64 de alta precisão e valores pequenos (SHIB: 0.00002492).

### Adicionado — allocfail nos parsers I/O (1098 → 1158 verificações)

9 funções de injeção de falha: `af_csv_read_mem`, `af_csv_read_quoted`,
`af_csv_read_many_rows`, `af_csv_write`, `af_json_read_mem`,
`af_json_read_many_records`, `af_json_read_long_string`, `af_json_write`,
`af_table_free_partial`. Toda falha de malloc em qualquer ponto dos parsers
resulta em retorno gracioso sem crash.

### Corrigido — dois bugs encontrados pelo Valgrind

`smaug_json.c`: `col_names` (array de ponteiros) não era liberado no caminho
de sucesso — 8 bytes por coluna vazavam.

`smaug_csv.c` + `smaug_json.c`: writers retornavam buffer sem terminador `\0`.
`strstr` e similares liam além do conteúdo válido. Corrigido: ambos os writers
adicionam `\0` ao final sem contar em `out_len`.

### Adicionado — COV-EXCL-BR nos parsers

66 exclusões totais (era 57). Guards de OOM/syscall inalcançáveis via API
pública nos parsers CSV e JSON documentados com justificativa técnica.

### Cobertura

Linha 97.95% (1909/1949). Branch-alvo 92.18% (1981/2149, 66 excluídos).

---

## 2026-06-12 · Ring 1 completo

### Adicionado — `df[mask]` indexação por BoolSeries

`DataSet.__index` passa a despachar para `filter` quando a chave é uma
`Series<bool>`. Açúcar sobre `:filter()` — sem semântica nova.

```lua
local ds = smaug.DataSet({
    {"idade", {17, 32, 25}, "int64"},
    {"nome",  {"Ana", "Bruno", "Carol"}, "string"},
})
local adultos = ds[ds.idade:gt(18)]
```

### Adicionado — `.str` Tier A completo

Accessor `.str` em `Series` do tipo string. 7 métodos + `replace`.
Null propaga; erro claro em dtype errado.

```lua
local ds = smaug.DataSet({{"cidade", {"  São Paulo  ", "rio", "MINAS"}, "string"}})
local normalizado = ds.cidade.str:strip():lower()
```

Métodos: `len` (→ int64), `lower`, `upper`, `strip`, `replace` (→ string),
`contains`, `startswith`, `endswith` (→ BoolSeries).

### Adicionado — comparações `ge`/`le`/`ne`

Para f64, i64 e string. Completam o conjunto `gt`/`lt`/`eq`/`ge`/`le`/`ne`.

### Adicionado — `Series:map(fn, dtype?)`

Aplica função Lua elemento a elemento. `nil` retornado → null. Dtype
inferido do primeiro retorno não-null; tipos mistos → erro com índice.

### Corrigido — `f64` div/0 → null (uniforme com i64)

`smaug_f64_div` e `smaug_f64_div_scalar` passam a produzir `null` quando
o divisor é zero. Comportamento agora uniforme entre f64 e i64.

### Decisão — Broadcasting rejeitado para Anel 1

Broadcasting de `Series(length=1)` não desbloqueia capacidades novas além
do escalar direto. Broadcasting real pertence ao `Tensor2D`/ML (Anel 5).
Removido da dívida técnica; registrado como decisão explícita.

---

## 2026-06-11 · 9807b46

### Corrigido — `test_string_ux()` órfã

30 checks de UX de string estavam escritos mas nunca executados — função
definida e não chamada. Qualquer máquina reportava 59 checks; o arquivo tinha 90.

### Corrigido — rodapé do COVERAGE.md incompleto

O gerador suprimia o segundo ramo de linhas com dois ramos excluídos.
Resultado: aritmética dizia 19 exclusões, rodapé listava 17. Fix: remove
o guard. O rodapé agora espelha a aritmética real.

---

## 2026-06-10 · f73c928

### Adicionado — BoolSeries como coluna de primeira classe

`DataSet` aceitava `BoolSeries` em `add_column`, mas `head`/`tail`/`filter`/
`describe`/`dropna`/`fillna`/`argsort` explodiam. Princípio adotado: toda coluna
aceita pelo DataSet deve funcionar em toda a API do DataSet, sem exceções ocultas.

Corrigido também um bug de precedência no `argsort` (comparador Lua com `and`/`or`
sem parênteses — resultado silenciosamente errado em certas ordenações).

### Adicionado — UX de string

- `fillna` dtype-aware: string aceita string, número aceita número.
- `describe` para string: count, nulls, unique, top, freq.
- `astype` string↔numérico com conversão tolerante por elemento:
  elementos inconversíveis viram null, nunca erro.

```lua
local s = Series.from_table({"1.5", "2.0", "abc", smaug.NA}, "string")
local f = s:astype("float64")
-- f:get(3) == nil  (null, não erro)
-- f:get(1) == 1.5
```

### Adicionado — API pública do DataSet

- `smaug.DataSet({{...}})` via `__call`.
- `Series.full(n, val)` para broadcast de escalares.
- `df["col"] = serie_ou_escalar` via `__newindex`.
- `DataSet.update_column`.
- `DataSet.methods` exposto para extensão por módulos externos (usado pelo I/O).

---

## 2026-05 · endurecimento Anel 0 (frentes A, B, C)

### Frente B — OOM nas ops

`test_allocfail` estendido para cobrir todas as ops aritméticas (f64/i64/bool/string).
579 → 767 → 1098 → 1158 verificações. Valgrind-clean.

### Milestone — branch-alvo 100% no núcleo (MC/DC completo)

1095/1095 ramos do núcleo cobertos. Jornada: 75.42% → 100.00%.
19 exclusões `COV-EXCL-BR` com justificativa auditável.

### Frente A — guards de input

O engine passou a não confiar no caller: toda fronteira pública do C valida
ponteiro/argumento/índice e comunica o resultado via `smaug_status_t`.
# Changelog — Smaug

Registro de o que mudou e por que, em ordem cronológica reversa.
Uma entrada por sessão de trabalho. Foco no que não é óbvio pelo diff:
decisões, achados, motivações.

---

## 2026-06-16 — Fase 3 Grupos A+B (Ring 0) + G.1 UTF-8 JSON

Início da Fase 3: migração de primitivas Lua puro para Ring 0 (C), guiada
pelo Bloco G. Duas frentes paralelas nesta sessão: G.1 (bloqueante de release)
e Grupos A+B do inventário de primitivas.

### G.1 — Decodificação UTF-8 no reader JSON

Eliminada a degradação silenciosa `\uXXXX → '?'` que existia em
`smaug_json.c`. Implementação completa em `read_json_string`:

- `read_hex4`: lê 4 dígitos hex → codepoint; retorna -1 se hex inválido.
- `encode_utf8`: codepoint → 1–4 bytes UTF-8 (cobre U+0000–U+10FFFF).
- BMP (U+0000–U+FFFF): decodificado diretamente.
- Surrogate pairs (`\uD800–\uDBFF` + `\uDC00–\uDFFF`): montados em
  codepoint suplementar (U+10000–U+10FFFF) e codificados em 4 bytes UTF-8.
- Surrogate isolado ou hex inválido → `TOK_ERROR` → `make_error` com
  mensagem clara. Nunca silencioso.

`.str` permanece byte-oriented — contrato inalterado. `str:len()` retorna
bytes, não codepoints. `test_io_c`: 174 → 190 checks (+16, 8 casos unicode).

**Motivação:** `json.dumps` Python com `ensure_ascii=True` (default) serializa
qualquer não-ASCII como `\uXXXX`. Dados brasileiros reais (nomes, cidades com
acento) produzem escapes rotineiramente. O `'?'` silencioso era bug de
integridade indetectável em produção.

### Grupo A — 10 primitivas O(N) para Ring 0

Migradas de Lua puro para C em `smaug_ops_f64.c` e `smaug_ops_i64.c`,
declaradas em `smaug_numeric.h`, registradas no `DTYPES` de `series.lua`
e no `ffi_loader.lua`:

`cumsum`, `cumprod`, `cummin`, `cummax`, `diff`, `shift`, `ffill`, `bfill`,
`argmin`, `argmax` — para `smaug_series_f64_t` e `smaug_series_i64_t`.

**Contratos relevantes:**
- `cummin`/`cummax`: nulos não propagam para frente (posição nula fica nula,
  mas as seguintes continuam recebendo o acumulado). Contrato mais útil que o
  `cumsum`/`cumprod` onde null contamina o restante.
- `diff` datetime: permanece Lua (usa `smaug_dt_diff_ms`).
- `shift` negativo (periods < 0): permanece Lua (C usa `size_t`).
- `argmin`/`argmax`: retornam `SIZE_MAX` se série vazia ou toda-null; Lua
  converte `SIZE_MAX → nil` e ajusta 0-based → 1-based.
- `cummin`/`cummax`/`ffill`/`bfill` datetime: fallback Lua via nil-check em
  `self._d.xxx`.

Regra de migração aplicada: todas as funções C registradas nos descritores
`DTYPES` (`float64` e `int64`) e acessadas via `self._d.fn(self._c)` — nunca
`C.smaug_f64_fn` diretamente no corpo do método.

### Grupo B — sorted_nonnull e rank para Ring 0

Migradas de Lua puro para C:

- `smaug_f64_sorted_nonnull` / `smaug_i64_sorted_nonnull`: coleta não-nulos
  em `double*` / `int64_t*` ordenado crescente. Série toda-null retorna
  `NULL` com `*out_n = 0` (não é erro). Caller libera com `smaug_free`.
- `smaug_f64_rank` / `smaug_i64_rank`: rank 1-based com 4 methods
  (0=average, 1=min, 2=max, 3=first). Nulos → `NAN` no resultado.
  Caller libera com `smaug_free`.

Comparadores (`cmp_double`, `cmp_rank_pair`, `cmp_i64`, `cmp_i64_rank_pair`)
definidos como `static` no escopo do arquivo — C11 padrão, sem extensões GCC.

**Consumidores Lua reescritos:** `median`, `quantile`, `nlargest`, `nsmallest`,
`skew`, `kurtosis`, `mad`, `sem`, `rank`, `pct_rank` — todos delegam para C
via `c_sorted_nonnull` (helper Lua que chama a primitiva C e devolve
`ffi.new double[]` uniforme). `datetime` e `mad` (segundo passe sobre desvios)
permanecem com fallback Lua.

Grupo B não usa `DTYPES`: as funções retornam ponteiros brutos (`double*`,
`int64_t*`), não `smaug_series_*_t` — são primitivas de buffer chamadas
diretamente pelos métodos, não via descritor de dtype.

### Testes

`test_ops_window.c` — novo, cobre Grupos A e B: 150 checks.
ASan+UBSan limpos. `test_allocfail` estável em 1158 verificações.

### Próximo

Fase 3 Grupo C: `multi_argsort` composto (DataSet) e `SeriesRolling:_agg`,
após medição de performance no Windows.

---



Último sub-bloco do enriquecimento dos núcleos. Com ele, **o Bloco F inteiro
(F.1–F.6) está fechado**.

### Adicionado

- **Series:** `duplicated([keep])` (keep ∈ {first,last,none}; null conta como
  valor — dois nulos são duplicatas entre si, semântica pandas);
  `drop_duplicates([keep])`; `combine_first(other)` (preenche nulls de self com
  other); `searchsorted(value, [side])` (busca binária, exige série ordenada
  crescente verificada via `is_monotonic_increasing`; side ∈ {left,right});
  `rep_each(n)` (repete cada elemento n vezes; n escalar ≥0 ou `Series<int64>`).
- **DataSet:** `duplicated([subset], [keep])` (subset = nome/lista/nil) e
  `drop_duplicates([subset], [keep])` (multi-coluna).

**Decisões de contrato:**
- O nome do método de repetição é `rep_each`, não `repeat`: `repeat` é palavra
  reservada em Lua e impediria tanto a definição (`function methods.repeat`)
  quanto a chamada (`s:repeat(n)`) — ambas falham no parse. `rep_each` deixa a
  intenção explícita (repete cada elemento) e segue o espírito do `:rep` já
  existente no `.str`.
- `duplicated` reaproveita o mesmo esquema de chave de `unique`/`nunique`
  (`type:tostring`, mais sentinela própria para null), garantindo semântica
  consistente de igualdade em todo o frontend.
- `combine_first` exige dtype e tamanho iguais — não faz coerção implícita.
- `searchsorted` exige ordenação crescente e rejeita séries com nulos (não há
  ordem definida com null), com erro claro em vez de resultado silenciosamente
  errado.

`test_duplicates.lua` (74 checks).

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `Series.methods` 90→95, `DataSet.methods`
46→48. Roadmap marca F.6 e o **Bloco F** inteiro como `[Done]`.

---

## 2026-06-15 — Bloco F.5 (acesso e ergonomia)

### Adicionado

- **Series:** `at`/`iat` — acesso escalar posicional. Implementado via proxy no
  `__index` que suporta tanto indexação (`s.at[i]`) quanto chamada (`s.at(i)`),
  cobrindo a sintaxe pandas-like e a forma idiomática Lua. Em Series 1-D, `at` e
  `iat` são equivalentes (índice = posição). Ambos delegam a `get`, herdando o
  guard de bounds.
- **DataSet:** `at(i, col)` (célula por nome) e `iat(i, ci)` (célula por índice
  posicional de coluna); `insert(loc, name, series)` (insere em posição 1-based,
  desloca as seguintes); `to_dict([orient])` (`"columns"` default ou `"records"`);
  `from_dict(t, [orient])` (construtor com inferência de dtype por coluna);
  `to_markdown()` (GitHub-flavored, sem o limite de 10 linhas do `__tostring`);
  `to_string([opts])` (texto plano com `max_rows` opcional).

**Decisões de contrato:**
- `at`/`iat` no DataSet são métodos chamáveis (`df:at(i, col)`), não indexers de
  duplo subscrito — Lua não tem `tbl[i, col]`. A forma de chamada é a tradução
  fiel e sem ambiguidade.
- `from_dict` orient `"columns"`: ordem das colunas é indefinida em Lua (chaves
  de tabela), então aceita `t._order` (lista de nomes) para ordem determinística;
  sem ele, ordena alfabeticamente. Orient `"records"`: colunas pela união das
  chaves (1ª aparição); chave ausente em um registro → NA naquela linha.
- `from_dict` infere dtype por coluna: string domina; senão bool puro; senão
  float se houver não-inteiro; senão int64; coluna toda-nula → string.

`test_access.lua` (54 checks), incluindo roundtrip `to_dict→from_dict`, bordas de
`insert` e erros de acesso.

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `DataSet.methods` 40→46 (`from_dict` é
função de classe, documentada à parte como `from_columns`). Roadmap marca F.5
`[Done]`.

---

## 2026-06-15 — Portabilidade de I/O + Blocos F.3 e F.4 + sync de builds

### Corrigido — testes de I/O com path hardcoded (Windows)

`build_win.ps1` falhou em `test_io_c`, `test_io` e `test_io_real`: os testes
escreviam em `/tmp/...`, que não existe no Windows/UCRT64. Não era regressão da
biblioteca — `to_csv`/`smaug_write_csv` reportaram fielmente a falha de escrita.
Introduzido helper `tmp_path` (um em C, um em Lua) que resolve o diretório
temporário via `TMPDIR`→`TMP`→`TEMP`→`/tmp`, montando o caminho com separador
`/` (aceito pela CRT do Windows e pelo POSIX). Detalhe que exigiu cuidado:
`os.getenv` devolve `""` (truthy em Lua), não `nil`, para variável vazia — o
helper trata string vazia como ausente, espelhando o `!dir || !*dir` do C.
Validado em três cenários: fallback `/tmp`, `TEMP` setado, e variável vazia.

### Adicionado — Bloco F.3: accessor `.dt` estendido

Toda a lógica de calendário derivada vive no Ring 1 (Lua), reaproveitando as
primitivas C (`year`/`month`/`day`/.../`from_parts`/`truncate`/`add_ms`). Nenhuma
mudança no Ring 0 — funções de calendário derivadas são responsabilidade do
frontend.

- **Predicados** (→ `Series<bool>`): `is_month_start`/`is_month_end`,
  `is_quarter_start`/`is_quarter_end`, `is_year_start`/`is_year_end`,
  `is_leap_year` (regra gregoriana completa, incluindo a exceção secular ÷400).
- **Atributos:** `days_in_month` (→ int64), `month_name`/`day_name` (inglês fixo).
- **Período:** `round(unit)`/`ceil(unit)` complementam o `truncate` (= floor) já
  existente. `ceil` retorna o próprio valor quando já alinhado; `round` usa
  half-up no empate (consistente com pandas). `next_period` usa `from_parts`
  para unidades de calendário (M/Q/Y, comprimento variável) e `add_ms` para as
  de comprimento fixo.
- **`normalize()`:** zera a hora (= `truncate("D")`), nome herdado do pandas.
- **`strftime(fmt)`:** tokens `%Y %y %m %d %H %M %S %I %p %j %B %b %A %a %%`;
  token desconhecido é mantido literal (com o `%`).

`test_dt_extended.lua` (65 checks), com casos seculares (1900 não-bissexto, 2000
bissexto), empates de round e meia-noite/meio-dia para `%I`/`%p`.

### Adicionado — Bloco F.4: accessor `.str` Tier C

ASCII puro, sem regex, sem Unicode — consistente com Tier A/B. Reaproveita os
helpers `str_map` (→ Series<string>) e `bool_map` (→ Series<bool>) existentes.

- **count(sub):** ocorrências literais não-sobrepostas → int64. `sub` vazio é
  erro (contagem indefinida / risco de loop).
- **Predicados** (→ Series<bool>): `isalnum`/`isalpha`/`isdigit`/`isspace`/
  `islower`/`isupper`. Semântica Python: string vazia → false; `islower`/
  `isupper` exigem ao menos uma letra e nenhuma da caixa oposta.
- **removeprefix/removesuffix:** remoção literal de afixo, no máximo uma vez,
  idempotente quando não casa.
- **capitalize/title/swapcase:** caixas ASCII. `title` trata qualquer não-letra
  como separador de palavra.
- **join(sep):** atalho de `:cat` (mesma saída: string Lua única). Mantido pelo
  nome familiar de pandas/Python.

`test_str_tier_c.lua` (61 checks), incluindo vazias, nulos, não-ASCII em `title`
(não quebra), e contagem não-sobreposta.

### Sincronização das três fontes de build

`build_win.ps1` estava atrás em duas dimensões: faltava `test_datetime_c`
(C) e seis suítes Lua (`test_datetime`, `test_categorical`, `test_completeness`,
`test_dt_extended`, `test_stats`, `test_predicates`). Alinhado ao Makefile
canônico — as três fontes (`Makefile`, `build.sh`, `build_win.ps1`) agora
rodam o conjunto idêntico, verificado por diff: 9 binários C plain + allocfail +
stress, e 26 suítes Lua.

### Docs

`API_INDEX.md` — Eixo 12 mantém 100%: `SeriesDT:*` 19→33, `StrProxy:*` 15→28.
Roadmap marca F.3 e F.4 `[Done]`.

---

## 2026-06-15 — Completude de paridade + Blocos F.1 e F.2

Sessão de fechamento de lacunas antes de avançar o enriquecimento dos núcleos.

### Corrigido — checkup de build e oráculos de teste

Auditoria do `Makefile` e do `build.sh` expôs que `make test`/`make valgrind`
não exercitavam `test_io_c` nem `test_datetime_c` (375 checks C fora do CI), e
que `LUA_TESTS` cobria 8 de 21 suítes (362k+ checks ignorados pelo `make`). As
duas listas foram completadas e sincronizadas entre `Makefile` e `build.sh`.
Removido um warning `-Wunused-variable` em `test_io_c.c:315` (`s` capturada e
nunca usada). Build agora zero-warning também nos binários de teste.

### Adicionado — completude de métodos em datetime e categorical

Auditoria do `PARITY_REPORT.md` (Eixo 1) apontou 17 ausências sem registro.
Decisão: nesta fase de completude, **implementar**, não registrar exceção.

- **datetime (7):** `argmin`/`argmax`/`cummin`/`cummax`/`median`/`quantile`
  passam a aceitar datetime — operam sobre epoch_ms (já numérico), guard
  estendido. `diff` em datetime retorna `Series<int64>` (duração em ms, não
  timestamp — diferença de dois instantes é uma duração).
- **categorical (10):** `isna`/`notna` (aliases), `min`/`max` (lexicográfico
  sobre labels), `ffill`/`bfill` (opera ao nível de codes), `shift`, `map`
  (retorna Series do dtype inferido), `where`/`mask` (seleção condicional,
  retornam novo CategoricalSeries).

`test_completeness.lua` (93 checks) pina cada comportamento, incluindo nulos e
erros de bounds.

### Adicionado — Bloco F.1: pacote estatístico

- **Series:** `corr(other)` (Pearson ∈ [-1,1]), `cov(other)` (covariância
  amostral ÷ n-1), `autocorr([lag])` = `:corr(:shift(lag))`, `dot(other)`
  (produto interno), `pct_change([periods])`.
- **DataSet:** `corr()` / `cov()` retornam matriz N×N como DataSet (coluna
  identificadora `__index__` + uma coluna float64 por variável numérica;
  colunas não-numéricas ignoradas).

**Decisões de contrato:**
- `corr`/`cov` **pulam** pares onde qualquer operando é null (semântica pandas);
  menos de 2 pares válidos ou variância zero → NaN.
- `dot` **propaga** null (qualquer par com null → resultado null) — diferente de
  corr/cov, porque produto interno não tem semântica de "ignorar" sem mudar o
  significado do resultado.
- `pct_change` com divisor zero → null (não Inf), por previsibilidade.

`test_stats.lua` (60 checks) com valores de referência calculados à mão.

### Adicionado — Bloco F.2: pacote de predicados

- **Series:** `between(lo, hi, [inclusive])` (inclusive ∈ {both,left,right,
  neither}), `isin(values)`, `is_unique()`, `is_monotonic_increasing/
  decreasing([strict])`, `equals(other)` (igualdade estrutural com NaN==NaN),
  `compare(other)` (diferenças → DataSet `{i,self,other}`), `idxmin`/`idxmax`
  (aliases de argmin/argmax), `first_valid_index`/`last_valid_index`.
- **DataSet:** `equals(other)` (colunas+ordem+dtypes+valores), `compare(other)`
  (diferenças célula a célula → DataSet `{linha,coluna,self,other}`).

**Decisões de contrato:**
- `between`/`isin` propagam null (resultado null naquela posição).
- `is_monotonic_*`: qualquer null quebra a monotonicidade (sem ordem definida
  com o vizinho). Série vazia/de 1 elemento é monotônica (vacuamente).
- `equals`/`compare` tratam NaN como estruturalmente igual a NaN (diferente de
  IEEE 754) — a pergunta é "são a mesma série", não "são numericamente iguais".
- `compare` (Series) retorna só as posições que diferem; DataSet vazio se
  idênticas. `compare` (DataSet) normaliza `self`/`other` para string porque as
  colunas têm dtypes heterogêneos.

`test_predicates.lua` (78 checks).

### Docs

`API_INDEX.md` atualizado — Eixo 12 (sincronização docs↔código) de 88/97/60/77%
para **100% nas 7 categorias** (206 métodos documentados). Reduções e
comparações antes agrupadas em uma linha (`:sum/mean/...`) foram separadas em
entradas individuais para o checker detectar por nome exato. Roadmap marca F.1
como `[Done]`.

---

## 2026-06-14 — Decisão: enriquecimento dos núcleos entra na v1.0

Após auditoria comparativa contra a API pública do pandas (Series + DataFrame),
decisão arquitetural: a v1.0 não fecha com o mínimo viável. Fecha com cobertura
operacional ampla, mantendo zero dependências externas.

**6 pacotes adicionados ao Pré-1.0 (Bloco F):**
- F.1 — Estatístico (`corr`/`cov`/`autocorr`/`dot`/`pct_change`)
- F.2 — Predicados (`between`/`isin`/`is_unique`/`is_monotonic_*`/`equals`/`compare`/`idxmin`/`idxmax`/`first/last_valid_index`)
- F.3 — `.dt` estendido (`is_*_start/end`/`is_leap_year`/`days_in_month`/`round`/`ceil`/`strftime`/`normalize`/`month_name`/`day_name`)
- F.4 — `.str` Tier C parcial (`count`/`isalnum`/`isalpha`/etc/`removeprefix`/`removesuffix`/`capitalize`/`title`/`swapcase`/`join`) — sem regex, sem Unicode
- F.5 — Acesso e ergonomia (`at`/`iat`/`insert`/`to_dict`/`from_dict`/`to_markdown`/`to_string`)
- F.6 — Duplicatas e binárias (`duplicated`/`drop_duplicates`/`combine_first`/`searchsorted`/`repeat`)

**Decisões de não-fazer (permanentes, registradas em Roadmap.md):**
- Index nomeado e toda família dependente (`loc`/`MultiIndex`/`reindex`/`align`/
  `set_index`/`reset_index`/`xs`/`swaplevel`/`droplevel`/`at_time`/`between_time`/
  `asof`/`asfreq`/`resample`/`to_period`/`to_timestamp`/`tz_*`).
- Plotting (`.plot`/`.hist`/`.boxplot`).
- I/O exótico (`pickle`/`hdf`/`xarray`/`stata`/`clipboard`/`latex`/`orc`/`feather`/
  `html`/`style`/`__dataframe__`).
- Tipos extras (`sparse`/`list`/`struct`/`period`/`timedelta`/`interval`/`decimal`).
- Operadores reversos (`radd`/`rsub`/etc.) — não-issue em Lua.
- `pipe`/`combine`/`update`/`squeeze`/`to_frame`.

**Trade-off:** v1.0 atrasa em ~6 sessões. Aceito conscientemente porque
v1.0 com cobertura ampla muda a régua do projeto — quando alguém abrir o README,
vê paridade significativa com pandas no que importa, sem o ruído.

Roadmap.md tem a lista detalhada de cada pacote, justificativa de cada
decisão de não-fazer, e checklist atualizado.

---

## 2026-06-14 — Tier 2 dtypes + bugfix Valgrind dos parsers I/O

### Adicionado — datetime no frontend Lua

Backend C de `smaug_datetime.c` já estava pronto (epoch ms UTC, calendário
Gregoriano proléptico, 201 checks em `test_datetime_c`). Esta sessão fechou
a integração com o frontend:

- Descriptor `datetime` no `DTYPES` de `series.lua` (factory, set/get com
  string ISO 8601 ou epoch_ms, append, comparações, sort/filter/take).
- Accessor `.dt` com 19 métodos: 11 componentes calendário (`year`/`month`/
  `day`/`hour`/`minute`/`second`/`ms`/`weekday`/`yearday`/`quarter`/`week`),
  `format`, `truncate(unit)` para `s/m/h/D/W/M/Q/Y`, `diff([periods])` em
  milissegundos, `add_ms`/`add_days`/`add_hours`/`add_minutes`/`add_seconds`.
- Helpers públicos: `Series.dt_parse`, `Series.dt_format`, `Series.dt_from_parts`,
  `Series.datetime(size, name)`.
- `astype` estendido com 6 branches novos: `datetime ↔ string` (via ISO 8601),
  `datetime ↔ int64`, `datetime ↔ float64` (epoch_ms).
- `describe` estendido com branch `datetime` — retorna `{dtype, count, nulls, min, max}`
  onde min/max são strings ISO 8601 formatadas.
- `test_datetime.lua` (188 checks): factories, `.dt`, comparações, sort, filter,
  astype, integração DataSet (filter/sort_by/assign/select/head/dropna/describe).

### Adicionado — categorical (Lua puro)

`CategoricalSeries` implementado inteiramente em Lua usando dictionary encoding.
Decisão consciente de não criar C backend — o tipo é essencialmente um índice
+ tabela de strings, não justifica fragmentar o contrato C.

- Armazenamento: `_codes` (int 1-based; nil = null), `_levels` (lista ordenada
  por primeira aparição), `_level_map` (hash inverso).
- Factories: `Series.from_table(arr, "categorical")`, `Series.Categorical.from_codes(...)`.
- 31 métodos de instância (espelham `Series` onde cabe): acesso, append,
  clone/head/tail/take/filter/dropna/fillna, sort/argsort (lexicográfico),
  comparações (`eq`/`ne`/`lt`/`le`/`gt`/`ge`), `unique`/`nunique`/`value_counts`,
  `describe`, `astype` (para `string`, `int64`, `float64`), `to_table`.
- Accessor `.cat` com 6 métodos: `codes()` → `Series<int64>`, `levels()`,
  `rename_categories`, `set_categories`, `add_categories`, `remove_categories`.
- Integração total com DataSet: `add_column`, `update_column`, `assign`,
  `__newindex`, `__call` todos aceitam `CategoricalSeries`. Princípio
  "toda coluna aceita pelo DataSet funciona em toda a API do DataSet".
- `test_categorical.lua` (199 checks).

### Corrigido — leaks nos parsers I/O capturados pelo Valgrind

Após validar `datetime` + `categorical` no Fedora com `make valgrind`, o
Valgrind capturou ~762 bytes vazando em 79 blocos no `test_allocfail`. Stack
traces apontaram para `smaug_csv.c:227` (strdup de `col_names`) e
`smaug_json.c:267/273` (malloc/calloc após strdups).

**Bugs identificados:**
- Em ambos os parsers, quando `calloc(dtypes)` ou alocações subsequentes
  falhavam **depois** do loop de strdup de `col_names[c]`, o cleanup fazia
  `free(col_names)` (o array) mas não liberava as strings individuais.
- No CSV, o label `done:` (alcançado quando `smaug_X_create` falha no loop
  final) liberava `col_names` mas não os strdups dos índices ainda não
  transferidos para `t->columns[c].name`.
- No JSON, `oom_recs:` libera `recs` mas nem `col_names` nem `dtypes` eram
  visíveis no escopo do label.

**Estratégia comum:**
- Inicializar `col_names[c] = NULL` antes do loop de strdup; libertar
  parcialmente em caso de falha.
- Marcar transferência de ownership com `col_names[c] = NULL` ao atribuir
  ao `tbl->columns[c].name`. `free(NULL)` é seguro, o cleanup itera pelo
  array inteiro.
- No JSON, mover `col_names`/`dtypes` para o escopo da função (com `n_cols_io`)
  para serem visíveis no label de cleanup. No CSV, estender `done:` para
  liberar strdups não-transferidos.

Resultado: Valgrind 100% clean em todos os 9 binários no Fedora. `test_allocfail`
com 15330 allocs / 15330 frees, `test_stress` com 90751/90751.

### Corrigido — warning `-Wtype-limits` no test_allocfail

`t->nrows >= 0` onde `nrows` é `size_t` (unsigned) — sempre verdadeiro.
Substituído por `1` constante; o check útil (`!t || t->error`) permanece.

### Decisão — NDJSON adiado para pós-1.0

Tentativa de implementar NDJSON expôs limitação fundamental: o parser JSON C
infere dtypes por linha. Uma linha com `"a":null` infere `string`, conflitando
com outra linha com `"a":1` que infere `int64`. Sem schema global declarativo,
NDJSON é inerentemente frágil para dados com null. Decisão: adiar para o ciclo
do schema/ORM (v2.0). Registrado em `Roadmap.md`.

### Cobertura

Linha 95.99% (2248/2342), branch-alvo 88.12% (2270/2576, 90 exclusões).
Queda em relação a sessões anteriores (96.99% / 88.82%) é resultado dos
cleanup paths novos — código adicionado mas ainda não exercitado pelo
`test_allocfail`. Vai ser fechado no hardening global.

---

## 2026-06-14 · f66ba99 — Anel 3 completo + hardening I/O

### Adicionado — Anel 3: I/O CSV e JSON

Parsers próprios em C puro, zero dependências externas. Fronteira
`smaug_table_t` como contrato entre leitores e o frontend Lua — todo
leitor produz uma `smaug_table_t`, o frontend consome e monta um `DataSet`.
Adicionar novos formatos (Parquet, SQLite) é implementar um novo produtor
sem tocar no núcleo.

```lua
-- leitura com inferência automática de tipo
local ds = smaug.read_csv("pedidos.csv", {sep = ";"})
local ds = smaug.read_json("cotacoes.json")

-- escrita
ds:to_csv("saida.csv")
ds:to_json("saida.json", {pretty = true})

-- em memória (sem arquivo)
local buf = ds:to_csv_mem()
local ds2 = smaug.read_csv_mem(buf)
```

Inferência de tipo no CSV: cada coluna é testada em ordem `int64 → float64 → bool → string`.
Coluna mista sobe para o tipo mais abrangente. Células vazias e `NA`/`null`/`N/A`/`nan`/`NaN`/`NULL`
viram null. Separador, aspas e header configuráveis.

JSON suporta o formato array de records `[{...}, {...}]` com escape completo
(`\n`, `\t`, `\\`, `\"`, `\uXXXX`) e writer compacto/pretty. `NaN` → `null`
no JSON (sem representação JSON para NaN).

### Adicionado — test_io_c.c (174 checks)

Cobertura C direta dos parsers: CRLF, CR-only, sem newline final, TSV,
sem header, aspas RFC 4180, aspas escapadas, aspas não fechadas, newline
em campo, NA padrão e customizados, inferência de todos os tipos, linha curta,
linha com 20 colunas, campo longo > 32 bytes, writer com NaN/sep/quote/sem-header/arquivo,
JSON completo, roundtrips, erros de arquivo/path inválido.

### Adicionado — test_io_real.lua (55 checks) com dados reais

`tests/pedidos_digitados.csv`: 916 linhas, 15 colunas, separador `;`, vírgula
decimal, 5 empresas (DB10/DC10/DG10/DP10/DS10), 5 marcas de produto.
Valida leitura, groupby, filter, join e roundtrips sobre dados reais.

Fixtures de cotações: `cotacoes.csv`, `cotacoes.json`, `cotacoes_USD_BRL.json`,
`cotacoes_SHIB_BRL.json` — float64 de alta precisão e valores pequenos (SHIB: 0.00002492).

### Adicionado — allocfail nos parsers I/O (1098 → 1158 verificações)

9 funções de injeção de falha: `af_csv_read_mem`, `af_csv_read_quoted`,
`af_csv_read_many_rows`, `af_csv_write`, `af_json_read_mem`,
`af_json_read_many_records`, `af_json_read_long_string`, `af_json_write`,
`af_table_free_partial`. Toda falha de malloc em qualquer ponto dos parsers
resulta em retorno gracioso sem crash.

### Corrigido — dois bugs encontrados pelo Valgrind

`smaug_json.c`: `col_names` (array de ponteiros) não era liberado no caminho
de sucesso — 8 bytes por coluna vazavam.

`smaug_csv.c` + `smaug_json.c`: writers retornavam buffer sem terminador `\0`.
`strstr` e similares liam além do conteúdo válido. Corrigido: ambos os writers
adicionam `\0` ao final sem contar em `out_len`.

### Adicionado — COV-EXCL-BR nos parsers

66 exclusões totais (era 57). Guards de OOM/syscall inalcançáveis via API
pública nos parsers CSV e JSON documentados com justificativa técnica.

### Cobertura

Linha 97.95% (1909/1949). Branch-alvo 92.18% (1981/2149, 66 excluídos).

---

## 2026-06-12 · Ring 1 completo

### Adicionado — `df[mask]` indexação por BoolSeries

`DataSet.__index` passa a despachar para `filter` quando a chave é uma
`Series<bool>`. Açúcar sobre `:filter()` — sem semântica nova.

```lua
local ds = smaug.DataSet({
    {"idade", {17, 32, 25}, "int64"},
    {"nome",  {"Ana", "Bruno", "Carol"}, "string"},
})
local adultos = ds[ds.idade:gt(18)]
```

### Adicionado — `.str` Tier A completo

Accessor `.str` em `Series` do tipo string. 7 métodos + `replace`.
Null propaga; erro claro em dtype errado.

```lua
local ds = smaug.DataSet({{"cidade", {"  São Paulo  ", "rio", "MINAS"}, "string"}})
local normalizado = ds.cidade.str:strip():lower()
```

Métodos: `len` (→ int64), `lower`, `upper`, `strip`, `replace` (→ string),
`contains`, `startswith`, `endswith` (→ BoolSeries).

### Adicionado — comparações `ge`/`le`/`ne`

Para f64, i64 e string. Completam o conjunto `gt`/`lt`/`eq`/`ge`/`le`/`ne`.

### Adicionado — `Series:map(fn, dtype?)`

Aplica função Lua elemento a elemento. `nil` retornado → null. Dtype
inferido do primeiro retorno não-null; tipos mistos → erro com índice.

### Corrigido — `f64` div/0 → null (uniforme com i64)

`smaug_f64_div` e `smaug_f64_div_scalar` passam a produzir `null` quando
o divisor é zero. Comportamento agora uniforme entre f64 e i64.

### Decisão — Broadcasting rejeitado para Anel 1

Broadcasting de `Series(length=1)` não desbloqueia capacidades novas além
do escalar direto. Broadcasting real pertence ao `Tensor2D`/ML (Anel 5).
Removido da dívida técnica; registrado como decisão explícita.

---

## 2026-06-11 · 9807b46

### Corrigido — `test_string_ux()` órfã

30 checks de UX de string estavam escritos mas nunca executados — função
definida e não chamada. Qualquer máquina reportava 59 checks; o arquivo tinha 90.

### Corrigido — rodapé do COVERAGE.md incompleto

O gerador suprimia o segundo ramo de linhas com dois ramos excluídos.
Resultado: aritmética dizia 19 exclusões, rodapé listava 17. Fix: remove
o guard. O rodapé agora espelha a aritmética real.

---

## 2026-06-10 · f73c928

### Adicionado — BoolSeries como coluna de primeira classe

`DataSet` aceitava `BoolSeries` em `add_column`, mas `head`/`tail`/`filter`/
`describe`/`dropna`/`fillna`/`argsort` explodiam. Princípio adotado: toda coluna
aceita pelo DataSet deve funcionar em toda a API do DataSet, sem exceções ocultas.

Corrigido também um bug de precedência no `argsort` (comparador Lua com `and`/`or`
sem parênteses — resultado silenciosamente errado em certas ordenações).

### Adicionado — UX de string

- `fillna` dtype-aware: string aceita string, número aceita número.
- `describe` para string: count, nulls, unique, top, freq.
- `astype` string↔numérico com conversão tolerante por elemento:
  elementos inconversíveis viram null, nunca erro.

```lua
local s = Series.from_table({"1.5", "2.0", "abc", smaug.NA}, "string")
local f = s:astype("float64")
-- f:get(3) == nil  (null, não erro)
-- f:get(1) == 1.5
```

### Adicionado — API pública do DataSet

- `smaug.DataSet({{...}})` via `__call`.
- `Series.full(n, val)` para broadcast de escalares.
- `df["col"] = serie_ou_escalar` via `__newindex`.
- `DataSet.update_column`.
- `DataSet.methods` exposto para extensão por módulos externos (usado pelo I/O).

---

## 2026-05 · endurecimento Anel 0 (frentes A, B, C)

### Frente B — OOM nas ops

`test_allocfail` estendido para cobrir todas as ops aritméticas (f64/i64/bool/string).
579 → 767 → 1098 → 1158 verificações. Valgrind-clean.

### Milestone — branch-alvo 100% no núcleo (MC/DC completo)

1095/1095 ramos do núcleo cobertos. Jornada: 75.42% → 100.00%.
19 exclusões `COV-EXCL-BR` com justificativa auditável.

### Frente A — guards de input

O engine passou a não confiar no caller: toda fronteira pública do C valida
ponteiro/argumento/índice e comunica o resultado via `smaug_status_t`.

### Frente C — semântica fechada

- Propagação estrita de null: qualquer operando null → resultado null.
- Tabela-verdade Kleene completa para bool.

---

## 2026-04 · contrato defensivo do C + COW

### Copy-on-Write em views (f64/i64)

Views compartilham o buffer da série pai zero-copy até a primeira escrita.
Toda mutação materializa um buffer privado; a pai nunca é tocada.

### Contrato defensivo — `get` Shape 1

`f64_get`/`i64_get` passaram a retornar valor + escrever `smaug_status_t*`.
Eliminou a colisão entre índice inválido e valor legítimo.

---

## 2026-03 · fase string completa

### String como dtype de primeira classe

Percurso: esqueleto (struct offset-based, estilo Arrow) → backend C
(lifecycle, acesso, mutação, comparações, filter/take, sort/argsort) →
frontend Lua.

String vazia `""` distinta de NULL. Ordenação lexicográfica por bytes.

### `test_allocfail` estendido para string

10 helpers `af_str_*` cobrem cada ponto de alocação. Valgrind-clean.

---

## 2026-02 · endurecimento (property-based, cobertura, fillna)

### Property-based tests

24 invariantes × 3 seeds × ~400 casos = 360 862 checks.
Invariantes: clone independente, view compartilha memória, sort é permutação,
filter↔count_true, astype ida-volta, fillna remove null/preserva NaN, Kleene.

### `fillna`

`Series:fillna(value)` e `DataSet:fillna(value | {col=value})`.
Sem coerção. Preserva NaN. Original imutável.

### Contrato NaN≠null fixado

`NaN` deixou de virar null. `sort`/`argsort` (f64) recusam NaN além de null.

---

## 2026-01 · fases 1–4 (backend C, frontend Lua, DataSet, bool)

### DataSet

Coleção de Series alinhadas. CRUD de colunas com validação de comprimento
e nome único. `filter`/`sort_by`/`head`/`tail`/`iloc`/`take`/`sample`/`select`.

### Bool e lógica Kleene

`Series<bool>` com lógica de três valores. `Series:gt`/`lt`/`eq` → `Series<bool>`.

### Frontend Lua (Series)

Despacho por dtype via tabela de descritores. `ffi.gc` para limpeza automática.
Views read-only com `_parent` para impedir GC da série pai.

### Backend C (f64 + i64)

Lifecycle, getters/setters, append dinâmico, aritmética, reduções,
comparações, sort/argsort. Zero warnings (`-Wall -Wextra`).

### Frente C — semântica fechada

- Propagação estrita de null: qualquer operando null → resultado null.
- Tabela-verdade Kleene completa para bool.

---

## 2026-04 · contrato defensivo do C + COW

### Copy-on-Write em views (f64/i64)

Views compartilham o buffer da série pai zero-copy até a primeira escrita.
Toda mutação materializa um buffer privado; a pai nunca é tocada.

### Contrato defensivo — `get` Shape 1

`f64_get`/`i64_get` passaram a retornar valor + escrever `smaug_status_t*`.
Eliminou a colisão entre índice inválido e valor legítimo.

---

## 2026-03 · fase string completa

### String como dtype de primeira classe

Percurso: esqueleto (struct offset-based, estilo Arrow) → backend C
(lifecycle, acesso, mutação, comparações, filter/take, sort/argsort) →
frontend Lua.

String vazia `""` distinta de NULL. Ordenação lexicográfica por bytes.

### `test_allocfail` estendido para string

10 helpers `af_str_*` cobrem cada ponto de alocação. Valgrind-clean.

---

## 2026-02 · endurecimento (property-based, cobertura, fillna)

### Property-based tests

24 invariantes × 3 seeds × ~400 casos = 360 862 checks.
Invariantes: clone independente, view compartilha memória, sort é permutação,
filter↔count_true, astype ida-volta, fillna remove null/preserva NaN, Kleene.

### `fillna`

`Series:fillna(value)` e `DataSet:fillna(value | {col=value})`.
Sem coerção. Preserva NaN. Original imutável.

### Contrato NaN≠null fixado

`NaN` deixou de virar null. `sort`/`argsort` (f64) recusam NaN além de null.

---

## 2026-01 · fases 1–4 (backend C, frontend Lua, DataSet, bool)

### DataSet

Coleção de Series alinhadas. CRUD de colunas com validação de comprimento
e nome único. `filter`/`sort_by`/`head`/`tail`/`iloc`/`take`/`sample`/`select`.

### Bool e lógica Kleene

`Series<bool>` com lógica de três valores. `Series:gt`/`lt`/`eq` → `Series<bool>`.

### Frontend Lua (Series)

Despacho por dtype via tabela de descritores. `ffi.gc` para limpeza automática.
Views read-only com `_parent` para impedir GC da série pai.

### Backend C (f64 + i64)

Lifecycle, getters/setters, append dinâmico, aritmética, reduções,
comparações, sort/argsort. Zero warnings (`-Wall -Wextra`).