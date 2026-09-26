# Verificação dirigida dos helpers aritméticos int64 — 2026-09-26

## Escopo e arquitetura

Verificação da solidez de quatro mecanismos existentes do Anel 0:
`smaug_i64_add_checked`, `smaug_i64_sub_checked`, `smaug_i64_mul_checked` e
`smaug_i64_div_checked`, em `src/smaug_core.c`. Nenhuma alteração de produção.
Não redefine overflow de outros operadores, contratos de Series ou políticas
de CSV/JSON. Dependências e responsabilidades seguem `ARCHITECTURE.md`.

A pergunta foi se as defesas são efetivas, e não apenas comentários associados
a um percentual de cobertura. O resultado desta rodada é positivo **para o
domínio finito executado desses quatro helpers**, com limitações abaixo.

## Evidência reproduzível

```sh
python3 scripts/audit_checked_arithmetic.py
```

O script usa somente a biblioteca padrão Python e GCC. Copia o fonte e headers
para diretório temporário, compila a baseline e cada mutação separadamente,
sem tocar nos fontes originais ou em `build/`. Registra o hash do core e versão
do compilador. O manifesto passou a incluir arquivos `.py` para cobrir o novo
reprodutor; Python não é dependência do runtime de produção do Smaug.

- Fonte SHA-256: `83bd7eaa90bee2175687fe6716d796163450571be153c8acadf61044446c8ef0`.
- GCC 16.2.1, Linux x64; `-std=c11 -O2 -g -Wall -Wextra -Werror -fPIC -shared`.
- Compilado sem `-fwrapv`: o mecanismo checked deve validar antes de calcular.
  Isso não demonstra sozinho ausência de UB e não muda flags do projeto.
- 3.839 pares distintos: cruzamento de extremos e vizinhos de potências de 2,
  casos próximos aos limites de produtos e 2.048 pares pseudoaleatórios com
  semente fixa 20260926 (deduplicados com os demais).
- Cada par passa por quatro operações, com saída válida e com saída `NULL`:
  **30.712 chamadas, nenhuma divergência**.

O oráculo usa inteiros Python de precisão arbitrária, calcula a operação antes
de confrontar o intervalo int64 e não replica os guards C por sinais. Divisão
usa magnitude inteira e sinal para truncar em direção a zero; não passa por
float nem usa diretamente o arredondamento para baixo de `//` em negativos.
Divisão por zero é falha; `INT64_MIN / -1` falha por resultado fora da faixa.

Para cada chamada com saída, o teste inicializa sentinela 79225 e exige:

- Sucesso: status verdadeiro e valor exato do oráculo.
- Falha: status falso e sentinela intacta.
- Saída `NULL`: mesmo status que a chamada com saída; nenhuma escrita exigida.

`out == NULL` é suportado intencionalmente nesses helpers, conforme comentário
do fonte. Não confundir com os parsers numéricos, nos quais a ausência de guard
foi reproduzida como crash. Cada API precisa de seu próprio contrato.

## Mutações compiláveis detectadas

Todas modificam cópias temporárias; cada substituição exige exatamente uma
ocorrência. Compilação bem-sucedida não conta como detecção: o oráculo deve
rejeitar o comportamento, e o script falha se algum mutante sobreviver.

| Mutação | Primeiro contraexemplo encontrado |
|---|---|
| Soma: `>` passa a `>=` no limite superior | `0 + INT64_MAX` rejeitado indevidamente |
| Subtração: `<` passa a `<=` no limite inferior | `(INT64_MIN + 1) - 1` rejeitado indevidamente |
| Multiplicação: `>` passa a `>=` no caso positivo | `1 * 2^62` rejeitado indevidamente |
| Divisão: rejeitar também divisor 1 | `INT64_MIN / 1` rejeitado indevidamente |
| Soma: escrever zero antes de retornar falha | `INT64_MIN + INT64_MIN` altera saída em falha |

Essas mutações não removem a proteção para executar uma operação assinada
fora da faixa. Elas demonstram detecção de rejeição indevida e violação da
preservação da saída; não constituem campanha exaustiva sobre todos os guards.

## Relação com cobertura e limites da conclusão

O relatório atual já mostra ramos descobertos nesses helpers. A execução nova
não foi instrumentada para gcov/MC/DC, portanto não altera `COVERAGE.md`, não
recalcula percentuais e não atesta independência de todas as condições.

Não foi executada a suíte integral, nem comparado o poder de detecção dos
mutantes com a suíte preexistente. A evidência de mutação é do novo oráculo.
ASan/UBSan permanecem indisponíveis nesta máquina conforme tentativa documentada
em `IO_REVIEW.md`; esta campanha não foi executada sob esses sanitizers ou
Valgrind. Não foi executada no Windows nem em outro compilador/otimização.
As rotinas restantes do core, operações sobre séries, alocações, COW e lifetime
não são certificadas por essa verificação escalar.

O próximo endurecimento deve manter esse padrão: especificação independente,
valor exato/status/estado verificados e evidência de que o teste percebe a
quebra da propriedade, sem transferir políticas de anéis externos ao núcleo.
