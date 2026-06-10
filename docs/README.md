# 🐉 Smaug

Biblioteca de dados tabulares para Lua com backend em C.

Smaug fornece estruturas tipadas para análise e transformação de dados, combinando uma API de alto nível em Lua com um núcleo de processamento implementado em C e acessado através de LuaJIT FFI.

O projeto foi desenvolvido com foco em:

* previsibilidade semântica;
* controle explícito de tipos;
* suporte consistente a valores nulos;
* robustez de memória;
* baixo overhead de execução;
* portabilidade.

---

## Principais Características

### Tipos suportados

* float64
* int64
* bool
* string

Todos os tipos possuem suporte a valores nulos (NA).

---

### Estruturas disponíveis

#### Series

Coluna tipada unidimensional.

Exemplo:

```lua
local smaug = require("smaug")

local s = smaug.Series.from_table(
    {10, 20, smaug.NA, 40},
    "float64"
)

print(s:sum())
print(s:mean())
```

---

#### BoolSeries

Resultado de operações lógicas e comparações.

Implementa lógica booleana de três estados:

* true
* false
* null

---

#### DataSet

Coleção de colunas tipadas organizadas em formato tabular.

Exemplo:

```lua
local ds = smaug.DataSet.from_columns({
    {"idade", {25, 30, 35}, "int64"},
    {"salario", {5000, 7000, 9000}, "float64"}
})
```

---

## Copy-on-Write (CoW)

Views compartilham armazenamento com o objeto de origem.

Na primeira operação de escrita ocorre materialização automática da view, criando um armazenamento privado e preservando a integridade do objeto original.

Esse comportamento permite:

* criação de views sem cópia inicial;
* isolamento automático após mutação;
* redução de cópias desnecessárias.

---

## Valores Nulos

Smaug trata valores nulos explicitamente.

Nulo (NA) não é equivalente a:

* NaN
* string vazia
* zero
* false

A presença de um valor é controlada por uma máscara dedicada de nulidade.

---

## Arquitetura

```text
Lua API
   │
LuaJIT FFI
   │
Backend C
```

Frontend:

* Series
* BoolSeries
* DataSet

Backend:

* gerenciamento de memória
* operações numéricas
* operações de string
* filtros
* ordenação
* reduções
* comparações

---

## Qualidade e Testes

O projeto possui:

* testes unitários em C;
* testes unitários em Lua;
* testes de falha de alocação;
* testes de Copy-on-Write;
* validação com Valgrind;
* medição de cobertura.

---

## Compilação

Linux:

```bash
make
```

Executar testes:

```bash
make test
make test-lua
```

Cobertura:

```bash
make coverage
```

Windows:

```powershell
scripts/windows-build.ps1
```

---

## Estrutura do Projeto

```text
include/
src/
lua/
tests/
docs/
scripts/
```

### include

Headers públicos.

### src

Implementação do backend C.

### lua

Frontend e integração LuaJIT FFI.

### tests

Testes automatizados.

### docs

Documentação técnica.

### scripts

Ferramentas auxiliares de build e cobertura.

---

## Documentação

* API_INDEX.md
* API_Reference.md
* Build_and_Testing.md
* CHANGELOG.md
* CODE_REVIEW.md
* CONTRACT.md
* COVERAGE.md
* COW.md
* Roadmap.md

---

## Status Atual

Implementado:

* tipos numéricos
* bool
* string
* suporte a nulos
* Series
* BoolSeries
* DataSet
* Copy-on-Write
* contrato defensivo
* testes de falha de alocação

Em evolução:

* expansão do ecossistema tabular
* amadurecimento da semântica de Dataset
* ampliação de operações e documentação

---

## Licença

Definida pelo projeto.
