# Changelog — Smaug

[Documentação](README.md) · [Estado e próximos passos](Roadmap.md#checkpoint)

Marcos resumidos. Decisões vigentes ficam no [contrato](CONTRACT.md);
checkpoints e pendências ficam no roadmap. Resultados de uma execução não
certificam versões posteriores.

## 2026-09-29 — Revisão de R1 e falhas operacionais no CSV

Parser inteiro valida sufixos após overflow; f64 reconhece overflow finito
saturado sem descartar subnormais. Astype e CSV propagam falhas operacionais;
CSV aceita decimal customizado longo, corrige rollback de realloc parcial e
confere o setter de string. Casos de OOM passam a comprovar injeção e
recuperação; seis mutações dirigidas detectadas. R1 continua aberta; evidências
e limitações no checkpoint, sem certificação global da suíte.

Seguimento da mesma frente: formatadores i64/f64 publicam texto completo ou
falham preservando o destino; f64 usa ponto fixo e restaura o locale da thread.
Consumidores astype/CSV/JSON passam a conferir falha de formatação. Verificados
buffers, limites, subnormais, locale e OOM; campanha cumulativa com nove
mutações detectadas. Ramo Windows e sanitizers continuam pendentes.

## 2026-09-28 — Padrões de engenharia C e Lua

Parsing: aprovada gramática explícita no review de I/O, com hexadecimal
inteiro em i64/f64 e fração/expoente apenas em f64, ponto independente de
locale, consumo completo, sem espaços nem payload NaN. Core implementado com
locale C explícito, acumulação inteira com limites prévios, diagnósticos de
sintaxe/overflow/underflow e preservação da saída em falha; `astype` propaga
falha operacional e mantém texto inconversível como NA.

Consolidado CODING_STYLE: C11, seleção de práticas CERT C/JPL, princípios de
legibilidade do Google e base LuaRocks/Lua 5.1/LuaJIT. Regras C01–C08 e L01–L07,
adaptações explícitas, contrato mínimo de API e registro de exceções orientam
a adoção incremental, começando por R1. Isso não certifica a base existente;
automação de análise/lint permanece em R6. Arquitetura de anéis preservada.

## 2026-09-27 — Consolidação documental

- Roadmap revisto contra código/consumidores, com frentes R1–R8, dependências,
  critérios de conclusão e checkpoint único. Entregas existentes saíram da
  fila de implementação inicial; comentários desatualizados têm revisão dirigida.
- Rework e parecer da suíte incorporados ao roadmap; removidas páginas
  redundantes e o índice experimental. Reviews especializados preservam
  evidência, sem manter outra fila. Histórico detalhado permanece no Git.
- Parsing numérico: há proposta local para rejeitar NUL interno em slices e
  saída NULL, com regressões C/Lua e validação dirigida. A escolha de contrato
  ainda exige discussão; não é registrada como entrega aprovada.
- Auditoria dos quatro helpers i64 reexecutada: 30.712 chamadas sem divergência,
  cinco mutações detectadas. Escopo e limites no review aritmético.
- Referências C/Lua confrontadas com headers, consumidores e probe de 24 casos:
  assinaturas `err_out`/`dayfirst`, NA de CSV, `min_count`, bool público e
  operações de janela foram alinhados; dois defeitos de execução ficaram
  registrados no R7 (diagnóstico de overflow em `prod` e `where` bool com Series).
- Verificação desta árvore: `scripts/build.sh --skip-lua --skip-stress --skip-manifest` passou
  12 binários C (5.002 verificações reportadas, incluindo alloc-fail); o probe Lua dirigido confirmou 22/24
  observações e preservou os dois achados do R7. Esse resultado é desta árvore,
  não uma certificação geral.

## 2026-09-26 — Auditoria de I/O e aritmética no Linux

Reproduzidas perdas de NUL/int64, saturação e corte de token numérico. Aprovadas
preservação de NUL e consulta de compatibilidade ABI; implementação pendente.
Registrados resultados observacionais, investigação dos consumidores e auditoria
independente dos quatro helpers checked. Ver [I/O](IO_REVIEW.md) e
[aritmética](CORE_ARITHMETIC_REVIEW.md).

## 2026-09-25 — Datetime estrito e correções relacionais

Parser compartilhado e astype string/int64/float64→datetime passaram a validar
precisão exata em milissegundos, anos zero/negativos e domínio UTC após offset,
com status e primeira posição inválida. Wrappers legados preservados; Lua
encaminha dayfirst e diagnóstico. Componentes e formatter continuam pendentes.

Reescrita relacional revelou três defeitos: função desconhecida em agg/transform
e colisão de chave composta. Corrigidos, com 68 casos passando no seguimento.
A auditoria da migração e os contratos count/pivot/join seguem abertos.
Build Windows registrada: 13 suítes C, 20 Lua e 15 eixos de paridade; sem nova
cobertura ou sanitizers. Paridade lexical não certifica comportamento.

## 2026-09-18 — Revisão dos contratos e da verificação

Auditoria diagnosticou testes sem poder de rejeição, lacunas datetime/OOM,
exclusões incorretas e limitações de runners/parity. Decidida reconstrução
incremental por família, mantendo regressões até validar substitutos.
Contratos de precisão, nulidade, COW, status e perfil datetime foram explicitados.
Destino atual dos nove achados: [roadmap](Roadmap.md#verificacao).

## Histórico detalhado

O relato anterior, incluindo decisões superadas e IDs numéricos, está na versão
Git `320b4bc`. Consultar localmente, sem restaurar arquivos:

```sh
git show 320b4bc:docs/CHANGELOG.md
git show 320b4bc:docs/Roadmap.md
git show 320b4bc:docs/TEST_SUITE_REWRITE_REVIEW.md
git log -- docs
```

Não reutilizar IDs antigos nem tratar promessas de uma sessão como contrato.
