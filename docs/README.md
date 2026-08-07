<div align="center">

# 🐉 Smaug

**Dados tabulares em Lua, motor em C puro.**

`float64` · `int64` · `bool` · `string` · `datetime` · `categorical` — null por bitmask, zero dependências externas.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Status](https://img.shields.io/badge/status-pré--1.0-orange)
![Lua](https://img.shields.io/badge/lua-LuaJIT%20FFI-2C2D72)
![C](https://img.shields.io/badge/backend-C11-00599C)

</div>

---

## O que é

Smaug é uma biblioteca de séries e DataSets estilo pandas, com o motor
numérico escrito em C puro e uma fronteira FFI para LuaJIT. Nasceu da
vontade de ter algo pandas-like no ecossistema Lua, sem depender de Python
por baixo.

```lua
local smaug = require("smaug")
local NA    = smaug.NA

local ds = smaug.DataSet({
    {"cidade", {"SP", "RJ", "SP", "MG"}},
    {"vendas", {120,   85,  200,  NA}},
    {"ativo",  {true, false, true, true}, "bool"},
})

print(ds:groupby("cidade"):agg({vendas = {"sum", "mean"}}))
```

## Estado atual — leia isto antes de usar

Smaug está em **pré-1.0**, e vale ser direto sobre o que isso significa na
prática:

- **O motor (Anéis 0–3) funciona e é levado a sério.** Backend C com
  Valgrind limpo em todos os binários, `test_allocfail` cobrindo os pontos
  públicos, testes property-based e de stress. Isso não é aspiracional —
  é o que já roda hoje.
- **A API ainda muda.** Não há garantia de compatibilidade entre commits.
  Se você depender disso em produção, trave um commit específico.
- **Não há caminho de instalação.** Sem LuaRocks, sem release empacotado —
  o único jeito de usar hoje é clonar e compilar (`gcc` + LuaJIT; MSYS2 no
  Windows). Isso está listado como bloqueio conhecido, não escondido.
- **Erros ainda são string.** Existe uma taxonomia de erro no C
  (`smaug_status_t`) que não sobe até o Lua — então um pipeline que
  precise ramificar por causa do erro hoje só pode dar `match` em texto.
- **Performance não é medida sistematicamente.** Correção é verificada à
  exaustão (cobertura, mutação, Valgrind); velocidade tem alguns números
  pontuais registrados no `CHANGELOG`, não uma suíte de benchmark.
- **Existem bugs abertos e documentados**, não escondidos embaixo do
  tapete — a lista completa, com causa e decisão pendente quando houver,
  está no [Roadmap](docs/Roadmap.md).

O critério de saída do pré-1.0 é o item 14 do Roadmap: uma verificação
ponta a ponta que só fecha quando motor, contratos, documentação e
superfície externa (licença, instalação, versionamento) contam a mesma
história. Enquanto esse item não fechar, é pré-1.0 — sem meio-termo.

**Em resumo:** o núcleo é sólido e bem testado; a experiência de alguém de
fora tentando usar isso ainda não existe. Se você está confortável
clonando um repositório C/Lua e compilando na mão, funciona bem. Se você
quer `luarocks install smaug`, ainda não é a hora.

## Por que C + Lua

Despacho por dtype em cima de um descritor único, sem genéricos — a
arquitetura cresce **de dentro para fora**, em anéis: o Anel 0 (backend C)
só expande quando está sólido, e cada anel seguinte depende só do
anterior. O detalhe completo — diagrama, princípios, régua de versões —
está em [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Documentação

| | |
|---|---|
| [Roadmap](Roadmap.md) | o que falta antes do 1.0, sem maquiagem |
| [Architecture](ARCHITECTURE.md) | modelo de anéis, princípios de design |
| [API Index](API_INDEX.md) | catálogo rápido de métodos |
| [API Reference](API_Reference.md) | referência do backend C |
| [Contract](CONTRACT.md) | contratos defensivos do backend |
| [COW](COW.md) | especificação Copy-on-Write |
| [Build and Testing](Build_and_Testing.md) | compilação, testes, cobertura |
| [Changelog](CHANGELOG.md) | histórico de decisões e achados |

## Build

```bash
# Linux
bash scripts/build.sh        # build + testes
bash scripts/build.sh --all  # + Valgrind + coverage + manifest
```

```powershell
# Windows (MSYS2-UCRT64)
scripts/build_win.ps1
```

## Licença

[MIT](LICENSE) — © 2026 Luiz Guilherme Padua.
