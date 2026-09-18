# Retomada da revisão da suíte — 2026-09-18

## Ponto de parada

Estamos alinhando contratos antes de reconstruir a suíte. Ler `CONTRACT.md`,
`ARCHITECTURE.md`, `TEST_SUITE_REWRITE_REVIEW.md` e
`TEST_SUITE_EXCLUSIONS_REVIEW.md`. A implementação da reconstrução não começou.
Nesta sessão foram feitas alterações documentais; nenhum fonte ou teste foi
alterado. `git diff --check` passou; não houve execução de testes.

## Decisões de datetime já registradas no contrato

- Calendário gregoriano proléptico, numeração astronômica, ano zero e negativos.
- Anos completos de -9999 a 9999, inclusive. Instantes UTC extremos:
  `-009999-01-01T00:00:00.000Z` e `9999-12-31T23:59:59.999Z`.
- Limites após normalização do offset para UTC, aplicados a texto, componentes,
  epoch e resultados de operações. Não prometer todo o domínio de int64.
- Offset ausente significa UTC; data sem hora significa meia-noite UTC.
- Armazenamento int64 em milissegundos. `.123000` é exato e aceito;
  `.123456` perde informação e é rejeitado na entrada estrita. Em astype,
  elemento inconversível vira NA; falha de infraestrutura não vira NA.

## Últimas sugestões acolhidas pelo mantenedor

Após os exemplos abaixo, o mantenedor respondeu “gostei” e pediu esta anotação.
Essas direções ainda precisam ser consolidadas no texto normativo do contrato;
não estão implementadas. Retomar daí, sem reabrir as três escolhas anteriores.

1. **Gramática:** anos 0000–9999 com quatro dígitos; negativos com sinal e seis
   dígitos, como `-000001` e `-009999`. Nova forma negativa somente ano primeiro
   e hífens; rejeitar `-000000`, ano abreviado `-1` e sufixos BC/AC. Preservar as
   conveniências existentes para datas positivas, mantendo saída canônica.
2. **Segundos intercalares:** segundos 00–59; rejeitar :60 sem normalizar.
   Preservar retorno nil por entrada inválida nos helpers Lua dt_parse e
   dt_from_parts. Conversão tolerante astype produz NA por elemento inválido.
3. **Ano versus erro:** -1 é ano válido. Separar valor de status no C, seguindo
   o padrão checked existente; assinatura sugerida, ainda inexistente:
   `smaug_status_t smaug_dt_year_checked(int64_t epoch_ms, int *out)`.
   Falha preserva out. Manter `.dt:year()` no Lua; NA de entrada propaga,
   negativos válidos permanecem valores e falhas reais usam status/erro Lua.
   Planejar migração explícita das assinaturas legadas e dos outros componentes.

Exemplos discutidos (expectativas propostas, não execução comprovada):

```lua
local smaug = require("smaug")
local epoch = smaug.Series.dt_parse("-000001-03-01T00:00:00Z")
-- Depois da correção do parser/formatter:
-- smaug.Series.dt_format(epoch) == "-000001-03-01T00:00:00.000Z"

local antigo = smaug.Series.dt_from_parts(-1, 3, 1)
local datas = smaug.Series({antigo, smaug.NA}, "datetime")
local anos = datas.dt:year()
-- Depois da correção da extração:
-- anos:get(1) == -1; anos:is_null(1) == false; anos:is_null(2) == true

-- A rejeição abaixo já corresponde à leitura do código atual:
-- smaug.Series.dt_parse("2016-12-31T23:59:60Z") == nil
-- smaug.Series.dt_from_parts(2016, 12, 31, 23, 59, 60, 0) == nil
```

## Base de código conferida e gaps

- `src/smaug_datetime.c`: parse_date_part não aceita ano com sinal;
  smaug_dt_format usa `%04d`; parser de frações descarta casas depois da terceira.
- Parser e from_parts_checked já rejeitam segundo > 59.
- from_parts_checked já separa status e resultado; não aplica a faixa aprovada
  de anos como contrato completo. Examinar também normalização de offsets.
- DT_COMPONENT_SERIES_IMPL usa `v >= 0`, convertendo anos negativos em NA.
  Comentários de inalcançabilidade foram refutados pela auditoria.
- `lua/smaug/core/series/temporal/_dt.lua`: dt_parse retorna nil em falha;
  dt_from_parts retorna nil para SMG_ERR_ARGUMENT e trata outros status.
  Há buffers de 26 bytes; `.dt:format()` ignora retorno do formatter.
  Revisar todos os consumidores de formatação, inclusive C e astype, para
  comportar ano negativo canônico e propagar erros corretamente.
- R02 também registra erro de semana ISO em 2023-01-01. Não perdê-lo na migração.

## Próximos passos

1. Consolidar as últimas três direções no contrato e atualizar suas pendências.
2. Fechar detalhes de migração/status sem alterar silenciosamente APIs legadas.
3. Continuar os outros tópicos contratuais: lifetime/invalidação de views,
   overflow intermediário por operação, faixa/conversões numéricas, estado
   preservado em falhas (valor versus capacidade/ponteiros) e suporte por dtype.
4. Só então avançar na reconstrução por famílias, com regressões discriminantes,
   casos de fronteira, oracles independentes e rastreabilidade das exclusões.

## Estado documental e cuidado na retomada

Foram alinhados contrato, arquitetura, COW, roadmap e seguimento da revisão.
Não tratar cobertura histórica, parity ou contagem de checks como certificação.
A exclusão de `docs/CODE_REVIEW.md` já estava presente no working tree antes
desta anotação; sua origem não foi estabelecida nesta sessão. Não restaurar nem
atribuir essa exclusão automaticamente ao trabalho do assistente. Há referências
históricas a esse arquivo nos documentos; verificar seu destino na retomada.
Nenhum commit foi criado pelo assistente.
