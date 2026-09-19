# Primeiros passos

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

<details>
<summary>Nesta página</summary>

- [O que é Smaug](#section-o-que-e-smaug)
- [Instalação e ambiente](#section-instalacao-e-ambiente)
- [Introdução às estruturas de dados](#section-introducao-as-estruturas-de-dados)
- [Dados ausentes e tipos](#section-dados-ausentes-e-tipos)
- [Próximos passos](#section-proximos-passos)

</details>

<a id="section-o-que-e-smaug"></a>

## O que é Smaug

Smaug combina operações tabulares em Lua com armazenamento e processamento em C.
Uma Series representa uma coluna tipada; um DataSet reúne colunas de mesmo
comprimento. O projeto ainda está em pré-1.0; consulte o [roadmap](Roadmap.md)
antes de depender de estabilidade da API.

<a id="section-instalacao-e-ambiente"></a>

## Instalação e ambiente

O caminho documentado é compilar a partir do repositório com GCC e LuaJIT.
Execute os comandos a partir da raiz do projeto.

No Windows com MSYS2-UCRT64:

```powershell
scripts/build.ps1
```

No Linux:

```bash
bash scripts/build.sh
```

As dependências, opções e verificações estão em
[Compilação e testes](Build_and_Testing.md). O guia não pressupõe um pacote
publicado no LuaRocks.

<a id="section-introducao-as-estruturas-de-dados"></a>

## Introdução às estruturas de dados

Importe o módulo e crie uma Series pelo construtor do Smaug:

```lua
local smaug = require("smaug")

local sales_series = smaug.Series({100, 200, 300}, "int64")
local first_sale = sales_series:get(1)
local total_sales = sales_series:sum()
```

Os índices Lua começam em 1. Para funções e construtores, use ponto;
para métodos de instância, dois-pontos.

Um DataSet reúne as colunas em uma estrutura tabular:

```lua
local smaug = require("smaug")

local sales_dataset = smaug.DataSet({
    {"city", {"SP", "RJ", "SP"}, "string"},
    {"sales", {100, 200, 300}, "int64"},
})
local sales_series = sales_dataset["sales"]
local totals_by_city = sales_dataset:groupby("city"):sum("sales")
```

Tipos diferentes têm operações diferentes. Consulte o
[catálogo da API](API_INDEX.md) para os métodos de cada estrutura.

<a id="section-dados-ausentes-e-tipos"></a>

## Dados ausentes e tipos

Use `smaug.NA` para expressar ausência. Um valor ausente não é igual a zero,
string vazia ou erro de execução. A máscara de validade é separada dos dados.

```lua
local smaug = require("smaug")

local nullable_sales = smaug.Series({100, smaug.NA, 300}, "int64")
local has_missing_sale = nullable_sales:is_null(2)
```

As regras de promoção, conversão e propagação estão no
[guia do usuário](USER_GUIDE.md) e no [contrato](CONTRACT.md).

<a id="section-proximos-passos"></a>

## Próximos passos

Siga o [guia do usuário](USER_GUIDE.md) para estudar um tema.
Use a [referência da API](API_INDEX.md) para consultar métodos.
Para contribuir com o projeto, leia o [referência do Núcleo C](API_Reference.md).


---

[Continuar no guia do usuário](USER_GUIDE.md) · [Consultar a API](API_INDEX.md) · [Início da documentação](README.md)
