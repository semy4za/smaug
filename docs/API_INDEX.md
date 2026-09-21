# Referência da API — Lua

[Início](README.md) · [Primeiros passos](GETTING_STARTED.md) · [Guia do usuário](USER_GUIDE.md) · [API Reference: Lua](API_INDEX.md) | [Núcleo C](API_Reference.md)

<details>
<summary>Nesta página</summary>

- [Objetos e funções Lua](#section-camada-lua-frontend-lua-smaug)
  - [Series](#section--series-core-series)
  - [.str — proxy de operações sobre Series string](#section--str-proxy-de-operacoes-sobre-series-string)
  - [.dt — proxy de operações de calendário sobre Series datetime](#section--dt-proxy-de-operacoes-de-calendario-sobre-series-datetime)
  - [Datetime — evolução da API Lua](#section-datetime-migracao-lua)
  - [Métodos exclusivos de Series<bool>](#section-metodos-exclusivos-de-series-bool)
  - [CategoricalSeries](#section--categoricalseries-core-series-categorical-categorical-lua)
  - [.cat — proxy de operações sobre Series categorical](#section--cat-proxy-de-operacoes-sobre-series-categorical)
  - [DataSet](#section--dataset-core-dataset)
  - [Funções do módulo smaug](#section-entry-point-init-lua)
- [Próximas versões](#section-proximas-versoes)

</details>

Esta página documenta os objetos, métodos e funções usados em Lua.
Para tipos, headers, status e funções C, consulte a
[referência do Núcleo C](API_Reference.md).

Índices Lua começam em 1. Use `smaug.Series(...)` e `smaug.DataSet(...)`
para construir dados, ponto para funções de módulo e dois-pontos para métodos.
O [guia do usuário](USER_GUIDE.md) explica os conceitos por assunto.

<a id="section-camada-lua-frontend-lua-smaug"></a>

## Objetos e funções Lua

<a id="section--series-core-series"></a>

### `Series`

**Factories:** `Series.new(dtype, size, name)`, `Series.from_table(arr, dtype, name)`,
`Series.full(n, val)`. `Series.NA` (sentinela de nulo em tabelas).

> **NaN ≠ null:** `nil`/`Series.NA` → null (ausente, bitmask). `NaN` → valor
> presente indefinido, NÃO null. `ignore_na` pula null, não NaN.
> `sort`/`argsort` recusam NaN e null. Comparação com NaN → false (máscara válida).

| Método | O que faz |
|--------|-----------|
| `:get(i)` / `:set(i, v)` | acesso 1-based; nil↔NA |
| `:get_raw(i)` | só int64: devolve o `int64_t` cru (cdata), sem `tonumber` — preserva precisão acima de 2^53 |
| `s[i]` / `s.at[i]` / `s.at(i)` / `s.iat[i]` | acesso escalar (alias de `:get`); at e iat equivalem em Series 1-D |
| `:is_null(i)` / `:set_null(i)` | nulos |
| `:append(v)` | adiciona ao fim (chainable) |
| `:len()` / `:size()` | tamanho |
| `:dtype()` | string do dtype (par singular de `DataSet:dtypes`) |
| `:sum([ignore_na])` | soma; ignore_na=true por padrão |
| `:mean([ignore_na])` | média |
| `:min([ignore_na])` | mínimo (ordenáveis: f64/i64 → número, datetime → epoch, string → lexicográfico, bool → false<true) |
| `:max([ignore_na])` | máximo (mesmos dtypes; valor do maior elemento) |
| `:var([ignore_na])` | variância amostral (÷ N-1; <2 → NaN) |
| `:std([ignore_na])` | desvio padrão amostral (÷ N-1; <2 → NaN) |
| `:count_nonnull()` | nº de não-nulos |
| `:clone()` | cópia independente |
| `:sort(asc)` / `:argsort(asc)` | ordenar / permutação |
| `:view(start, len)` | view zero-copy COW-gravável |
| `:take(idx)` / `:head(n)` / `:tail(n)` | seleção → nova Series |
| `:dropna()` | → nova Series sem NULLs |
| `:astype(dtype, name_or_options)` | aceita nome ou `{name=..., dayfirst=false}`; conversão atual tolerante por elemento (inconversíveis → null), exceto `bool` numérico rígido; migração datetime estrita ainda pendente |
| `:fillna(value)` | nova Series com NULLs→value; NaN intacto |
| `:to_table([na])` | → tabela Lua |
| `:sample(n, [seed])` | amostra n elementos sem reposição (par de `DataSet:sample`) |
| `:to_string([opts])` / `:to_markdown()` | render texto plano / Markdown (1 coluna) |
| `:describe()` | resumo estatístico |
| `:gt(k)` / `:lt(k)` | maior / menor que k → `Series<bool>` |
| `:eq(k)` / `:ne(k)` | igual / diferente de k → `Series<bool>` |
| `:ge(k)` / `:le(k)` | maior-igual / menor-igual → `Series<bool>` |
| `:filter(mask)` | `Series<bool>` como máscara → nova Series filtrada |
| `:map(fn, [dtype])` | transforma elemento a elemento |

> **Escalar int64 em operação (9.3):** quando o escalar *parametriza* uma operação
> — comparadores (`:gt`/`:lt`/`:eq`/`:ge`/`:le`/`:ne`), `:between` (ambos os
> limites) e aritmética escalar (`+ - * //`) sobre série `int64` — vale a forma
> exata: `cdata int64_t` (`ffi.new("int64_t", …)` ou sufixo `LL`) é **aceito e
> preservado**; um `number` Lua a partir de 2^53 é **recusado com erro**, porque
> já perdeu precisão na origem e o resultado sairia errado em silêncio. O limiar
> inclui 2^53 porque `2^53+1` degrada exatamente para lá. Regra distinta da de
> *armazenar* dado (`:set`/`:append`/`:fillna`), que **avisa e aceita** — ver
> Contrato 1. `datetime` herda a regra no threshold (epoch_ms é `int64_t`).
> `Series + cdata` é a forma suportada; `cdata + Series` não é interceptável
> (o LuaJIT resolve o operador do próprio cdata antes).

**Distintos:**

| Método | O que faz |
|--------|-----------|
| `:unique()` | valores distintos em ordem de 1ª aparição |
| `:nunique()` | contagem de distintos não-nulos |
| `:value_counts()` | DataSet `{value, count}` ordenado por freq. desc |

**Elementares:**

| Método | O que faz |
|--------|-----------|
| `:abs()` | valor absoluto (nulos propagam) |
| `:round([n])` | arredonda para n casas decimais |
| `:clip([lo], [hi])` | limita ao intervalo [lo, hi] |

**Reduções estatísticas adicionais:**

| Método | O que faz |
|--------|-----------|
| `:median([ignore_na])` | mediana; suporta f64, i64 e datetime (retorna epoch_ms) |
| `:quantile(q, [ignore_na])` | percentil q ∈ [0, 1] (interpolação linear); suporta f64, i64 e datetime |
| `:mode()` | valor mais frequente; primeira aparição em empates |
| `:prod([ignore_na])` | produto |
| `:rank([method])` | rank (`average`/`min`/`max`/`first`); default `average`. Ordenáveis: f64, i64, datetime (cronológico), string (lexicográfico), bool |
| `:pct_rank()` | rank percentual (0..1); mesmos dtypes de `rank` |
| `:skew()` / `:kurtosis()` | assimetria / curtose (Fisher; bias-corrected) |
| `:mad()` | desvio absoluto mediano |
| `:sem()` | erro padrão da média = std / √n |
| `:isna(i)` / `:notna(i)` | alias de `:is_null(i)` / não-null |

**Estatística bivariada e variação:**

| Método | O que faz |
|--------|-----------|
| `:corr(other)` | correlação de Pearson ∈ [-1,1]; pares com null pulados; <2 pares ou var zero → NaN |
| `:cov(other)` | covariância amostral (÷ n-1); pares com null pulados; <2 pares → NaN |
| `:autocorr([lag])` | autocorrelação = `:corr(:shift(lag))`; default lag=1 |
| `:dot(other)` | produto interno Σ xᵢ·yᵢ; qualquer par com null → resultado null (propaga) |
| `:pct_change([periods])` | variação percentual `(xᵢ-xᵢ₋ₚ)/xᵢ₋ₚ`; divisor zero → null; float64 |

**Predicados e índices:**

| Método | O que faz |
|--------|-----------|
| `:between(lo, hi, [inclusive])` | máscara lo ≤ x ≤ hi; inclusive ∈ {both,left,right,neither} → `Series<bool>` |
| `:isin(values)` | true onde x ∈ values (tabela Lua) → `Series<bool>`; null propaga |
| `:is_unique()` | true se valores não-nulos são todos distintos |
| `:is_monotonic_increasing([strict])` | não-decrescente (ou estritamente crescente); null quebra |
| `:is_monotonic_decreasing([strict])` | não-crescente (ou estritamente decrescente); null quebra |
| `:equals(other)` | igualdade estrutural (dtype+tamanho+valores+nulls; NaN==NaN) → bool |
| `:compare(other)` | diferenças posicionais → DataSet `{i, self, other}` |
| `:idxmin()` / `:idxmax()` | alias de `:argmin()` / `:argmax()` |
| `:first_valid_index()` / `:last_valid_index()` | índice 1-based do 1º / último não-nulo; nil se toda nula |

**Duplicatas e operações binárias:**

| Método | O que faz |
|--------|-----------|
| `:duplicated([keep])` | máscara de duplicatas; keep ∈ {first,last,none}; null é valor → `Series<bool>` |
| `:drop_duplicates([keep])` | remove duplicatas preservando ordem → nova Series |
| `:combine_first(other)` | preenche nulls de self com valores de other (mesmo tamanho/dtype) |
| `:searchsorted(value, [side])` | busca binária; exige série ordenada crescente; side ∈ {left,right} |
| `:rep_each(n)` | repete cada elemento n vezes; n escalar ≥0 ou `Series<int64>` (nome evita keyword `repeat`) |

**Valores ausentes:**

| Método | O que faz |
|--------|-----------|
| `:ffill()` | forward fill (propaga último não-nulo) |
| `:bfill()` | backward fill (propaga próximo não-nulo) |

**Seleção condicional:**

| Método | O que faz |
|--------|-----------|
| `:where(cond, other)` | onde cond=true mantém self; senão usa other (Series ou escalar) |
| `:mask(cond, other)` | inverso de where |
| `Series.ifelse(cond, a, b)` | vetorizado: a onde cond=true, b senão |
| `:nlargest(n)` | n maiores valores |
| `:nsmallest(n)` | n menores valores |
| `:argmin()` / `:argmax()` | índice (1-based) do mínimo/máximo; ordenáveis: f64, i64, datetime, string (lexicográfico), bool |

**Janela temporal:**

| Método | O que faz |
|--------|-----------|
| `:cumsum()` | soma cumulativa (nulos propagam) |
| `:cumprod()` | produto cumulativo (nulos propagam) |
| `:cummin()` / `:cummax()` | mínimo/máximo cumulativo; suporta f64, i64 e datetime |
| `:diff([periods])` | diferença entre elemento i e i-periods; em datetime retorna `Series<int64>` (ms) |
| `:shift([periods])` | desloca valores |
| `:rolling(w):sum/mean/min/max/std/var/count/median/quantile()` ; `:min_periods(p)` | agregação em janela `min_periods(p)`: emite com >= p não-nulos (janelas parciais); sem ele, exige janela cheia |
| `:expanding([min_periods]):sum/mean/min/max/std/var/count/median()` | janela crescente |

**Matemática vetorizada (resultado sempre float64):**

| Método | O que faz |
|--------|-----------|
| `:sin()` / `:cos()` / `:tan()` | trigonométricas |
| `:exp()` / `:log()` / `:sqrt()` | exponencial / log natural / raiz quadrada |

**Operadores aritméticos:** `+ - * /` (série×série e série×escalar), `serie[i]`.
Numéricos de dtypes diferentes promovem para `float64` (int64 ⊕ float64 → float64);
mistura com não-numérico (bool/string/datetime) é erro. `/` é **divisão verdadeira**
(sempre `float64`: `7/2 = 3.5`).

| Método | O que faz |
|--------|-----------|
| `:floordiv(outra)` | divisão inteira truncada → `int64` (`7//2 = 3`); exige int64; `/0` → null |

**Operadores bool** (só em `Series<bool>`): `*`=and, `+`=or, `-`=xor.

<a id="section--str-proxy-de-operacoes-sobre-series-string"></a>

### `.str` — proxy de operações sobre Series string

**Tier A:**

| Método | O que faz |
|--------|-----------|
| `.str:len()` | comprimento em bytes → `Series<int64>` |
| `.str:lower()` / `.str:upper()` | caixa (ASCII) |
| `.str:strip()` | remove espaços |
| `.str:replace(pat, rep)` | substituição literal |
| `.str:contains(sub)` / `.str:startswith(p)` / `.str:endswith(s)` | → `Series<bool>` |

**Tier B:**

| Método | O que faz |
|--------|-----------|
| `.str:find(sub)` | índice 1-based da 1ª ocorrência (0 se ausente) |
| `.str:slice(start, [stop])` | substring por índices |
| `.str:pad(width, [side], [fillchar])` | preenche até `width` chars |
| `.str:zfill(width)` | pad com '0' à esquerda |
| `.str:rep(n, [sep])` | repete n vezes |
| `.str:cat([sep])` | concatena todos os não-nulos → string Lua |
| `.str:split(sep, [max])` | divide pelo separador → tabela de Series |

**Tier C** (ASCII, sem regex/Unicode):

| Método | O que faz |
|--------|-----------|
| `.str:count(sub)` | nº de ocorrências literais não-sobrepostas (sub vazio → erro) → `Series<int64>` |
| `.str:isalnum()` / `:isalpha()` / `:isdigit()` / `:isspace()` | predicados ASCII; vazia → false → `Series<bool>` |
| `.str:islower()` / `:isupper()` | há letra e nenhuma da caixa oposta → `Series<bool>` |
| `.str:removeprefix(p)` / `:removesuffix(s)` | remove afixo literal uma vez (idempotente) |
| `.str:capitalize()` | 1ª letra maiúscula, resto minúsculo |
| `.str:title()` | inicial de cada palavra maiúscula (palavra = letras ASCII) |
| `.str:swapcase()` | inverte a caixa de cada letra ASCII |
| `.str:join([sep])` | atalho de `:cat` — concatena não-nulos → string Lua |

<a id="section--dt-proxy-de-operacoes-de-calendario-sobre-series-datetime"></a>

### `.dt` — proxy de operações de calendário sobre Series datetime

Disponível quando `s._dtype == "datetime"`. Erro claro em qualquer outro dtype.

**Componentes calendário** (todos retornam `Series<int64>`; nulo propaga):

| Método | O que faz |
|--------|-----------|
| `.dt:year()` | ano (ex.: 2026) |
| `.dt:month()` | 1–12 |
| `.dt:day()` | 1–31 |
| `.dt:hour()` | 0–23 |
| `.dt:minute()` | 0–59 |
| `.dt:second()` | 0–59 |
| `.dt:ms()` | 0–999 |
| `.dt:weekday()` | 0=seg … 6=dom |
| `.dt:yearday()` | 1–366 |
| `.dt:quarter()` | 1–4 |
| `.dt:week()` | 1–53 (ISO 8601) |

**Formatação e transformação:**

| Método | O que faz |
|--------|-----------|
| `.dt:format()` | → `Series<string>` ISO 8601 `"YYYY-MM-DDTHH:MM:SS.mmmZ"` |
| `.dt:truncate(unit)` | trunca para início do período: `'s'`/`'m'`/`'h'`/`'D'`/`'W'`/`'M'`/`'Q'`/`'Y'` |
| `.dt:diff([periods])` | diferença em ms entre elemento i e i-periods (default 1) |
| `.dt:add_ms(delta)` / `:add_days(n)` / `:add_hours(n)` / `:add_minutes(n)` / `:add_seconds(n)` | aritmética temporal → novo `Series<datetime>` |
| `.dt:round(unit)` | período mais próximo (half-up no empate); mesmas unidades de truncate → `Series<datetime>` |
| `.dt:ceil(unit)` | menor início-de-período ≥ valor; já-alinhado retorna o próprio → `Series<datetime>` |
| `.dt:normalize()` | zera a hora (= `truncate("D")`) → `Series<datetime>` |
| `.dt:strftime(fmt)` | formata por tokens `%Y %y %m %d %H %M %S %I %p %j %B %b %A %a %%`; desconhecido fica literal → `Series<string>` |

**Predicados de calendário** (→ `Series<bool>`; null propaga):

| Método | O que faz |
|--------|-----------|
| `.dt:is_month_start()` / `:is_month_end()` | primeiro / último dia do mês |
| `.dt:is_quarter_start()` / `:is_quarter_end()` | primeiro / último dia do trimestre |
| `.dt:is_year_start()` / `:is_year_end()` | 1º de janeiro / 31 de dezembro |
| `.dt:is_leap_year()` | ano bissexto (regra gregoriana, incl. ÷400) |

**Atributos de calendário:**

| Método | O que faz |
|--------|-----------|
| `.dt:days_in_month()` | nº de dias do mês (28/29/30/31) → `Series<int64>` |
| `.dt:month_name()` | nome do mês em inglês (January…December) → `Series<string>` |
| `.dt:day_name()` | nome do dia em inglês (Monday…Sunday) → `Series<string>` |

**Helpers estáticos** (não passam pelo proxy):

| Função | O que faz |
|--------|-----------|
| `Series.dt_parse(str)` | ISO 8601 → epoch_ms (número Lua); `nil` se inválido |
| `Series.dt_format(epoch_ms)` | epoch_ms → string ISO 8601; `nil` em overflow |
| `Series.dt_from_parts(y, m, d, [h], [mi], [s], [ms])` | constrói epoch_ms; `nil` se data inválida |
| `Series.datetime(size, name)` | factory: `Series.new("datetime", size, name)` |

<a id="section-datetime-migracao-lua"></a>

### Datetime — evolução da API Lua

As mudanças abaixo foram discutidas na revisão da suíte e ainda não foram
implementadas. A API existente está descrita acima. O
[contrato datetime](CONTRACT.md#section-perfil-datetime-decisoes-aprovadas-em-2026-09-18)
e as [regras de detecção e diagnóstico](CONTRACT.md#section-deteccao-de-datas-e-diagnostico-decisoes-da-retomada)
concentram as decisões normativas; esta seção registra o impacto no Lua.

| Superfície | Mudança planejada |
|---|---|
| `.dt:year()` e outros componentes | Preservar o nome; ano negativo válido continua valor, NA original propaga e falha real gera erro orientado |
| Inferência de strings em Series/DataSet | Examinar a coluna inteira sob a política de interpretação; manter texto se incompatível |
| Conversão explícita para datetime | Prioridade aprovada: formato explícito, reconhecimento com ordem configurada, padrão documentado; erro por data impossível ou incompatível com formato solicitado, sem NA silencioso |
| `.dt:format()` e conversão para string | Propagar falha de formatação; suportar a saída negativa canônica |
| Predicados, nomes, `strftime`, `ceil` e `round` | Conferir falhas intermediárias e impedir sua conversão silenciosa em NA |
| Diagnóstico `DATE_ON_THE_FENCE` | Mensagem aprovada com operação, coluna e posições baseadas em 1; até duas referências em conflito |

**Padrão aprovado:** preservar mês/dia (`dayfirst=false`) quando formato e
ordem não forem informados, sem depender da região do computador. Dia/mês
continua configurável; ano primeiro mantém sua ordem.

**Formatos iniciais aprovados:** ver o conjunto e suas regras no
[contrato de interpretação textual](CONTRACT.md#section-deteccao-de-datas-e-diagnostico-decisoes-da-retomada).
Implementação e validação continuam pendentes.

**Argumento de ordem aprovado:** `dayfirst`, booleano com padrão `false`.
O helper mantém `Series.dt_parse(str, dayfirst)`:

```lua
smaug.Series.dt_parse("02/05/2026")        -- 5 de fevereiro
smaug.Series.dt_parse("02/05/2026", false) -- 5 de fevereiro
smaug.Series.dt_parse("02/05/2026", true)  -- 2 de maio
```

Ano primeiro mantém sua ordem. Reconhecer `/` e `-` automaticamente nos
formatos aprovados, com separadores iguais dentro de cada data. A API inicial
não acrescenta argumento de formato explícito; essa opção fica para ampliação
futura, quando terá prioridade sobre `dayfirst`.

**Integração aplicada em 2026-09-21:** `Series:astype("datetime", {dayfirst=true})`
reutiliza a opção existente. `DataSet:astype({data="datetime"}, {dayfirst=true})`
encaminha a ordem às colunas string convertidas para datetime, mantendo nomes
e colunas fora do mapa. Omitir opções ou usar `false` preserva mês/dia.
`Series.dt_parse`, `Series:astype` e `DataSet:astype` rejeitam `dayfirst`
não-booleano quando informado. Essa mudança é Lua; não implementa a conversão
estrita nem altera as assinaturas C. Atualmente, entradas textuais inválidas
em `astype` ainda viram NA.

**Ainda a decidir:** integração nas demais entradas (construção, set/append e I/O);
eventual modo automático estrito opt-in
e revisão dos gatilhos de `DATE_ON_THE_FENCE` segundo a nova prioridade;
comportamento dos helpers `dt_parse`, `dt_from_parts` e `dt_format` que
hoje retornam nil em determinados erros; eventual conversão tolerante opt-in.
Omitir `dayfirst` equivale a `false` para a interpretação aprovada; não ativa
inferência automática estrita.

**Integração interna Lua:**

| Arquivo | Chamadas e impacto |
|---|---|
| `lua/smaug/core/series/temporal/_dt.lua` | 11 componentes em lote; predicados de início/fim, bissexto, dias no mês, nomes e strftime usam escalares; next_period usa from_parts legado; ceil/round podem produzir nil que dt_map converte em NA; helpers públicos misturam nil e status |
| `lua/smaug/core/series/_types.lua` | Descritor datetime liga operações C; set/append de string chamam parse com dayfirst=0 fixo; atualizar fluxo de validação sem inferir por elemento |
| `lua/smaug/core/series/access/_transform.lua` | Matriz de conversões; astype valida dayfirst booleano e encaminha 0/1; retorno C ainda é ponteiro, migração estrita pendente |
| `lua/smaug/core/series/window/_cumulative.lua` | diff datetime chama diff_ms_checked; precisa acompanhar assinatura e mensagem |
| `lua/smaug/core/series/stats/_stat.lua` | Formatação com char[26], retorno ignorado e ffi.string(buf, 25); retirar comprimento fixo incorreto |
| `lua/smaug/core/series/_factories.lua` | Inferência de strings atualmente resulta em string; ponto de integração da detecção antes de construir/mutar série |
| `lua/smaug/core/dataset/_core.lua`, `_io_support.lua` | Consomem inferência/construção de séries; manter nome da coluna no diagnóstico |
| `lua/smaug/io/csv.lua` | Serialização de datetime via astype string; consumidores de leitura precisam de política de detecção coerente |
| `lua/smaug/core/errors.lua` e helper `check_status` | Descrição de valores e tradução de status; precisam transportar posição/causa sem depender de analisar a frase |

A integração de assinaturas e a posse da memória estão documentadas na
[referência C](API_Reference.md#section-datetime-migracao-c).
Verificar componentes e NA, conversão inválida no último elemento, evidência
inequívoca no fim da coluna, ordens conflitantes e posições das mensagens.
Suítes afetadas incluem `tests/series/test_dt.lua`, `test_constructors.lua`,
`test_categorical.lua`, `test_stat.lua` e testes de entrada/saída.

<a id="section-metodos-exclusivos-de-series-bool"></a>

### Métodos exclusivos de `Series<bool>`

| Método | O que faz |
|--------|-----------|
| `:count_true()` / `:any()` / `:all()` | agregações (NA ignorado) |
| `:land(b)` / `:lor(b)` / `:lxor(b)` / `:lnot()` | lógica Kleene |
| `:describe()` | `{count, nulls, count_true, count_false}` |

<a id="section--categoricalseries-core-series-categorical-categorical-lua"></a>

### `CategoricalSeries`

Dtype Tier 2 implementado em Lua puro (sem C backend). Armazenamento via
dictionary encoding: `_codes` (int 1-based), `_levels` (lista ordenada),
`_level_map` (hash inverso). Detectado por `Series.is_categorical(x)`.

**Factories:**

```lua
Series.from_table({"SP","RJ","SP",NA,"MG"}, "categorical")    -- ordem de 1ª aparição
Series.Categorical.from_table(arr, [name])
Series.Categorical.from_codes(codes_arr, levels_arr, [name], [n])
```

`from_codes` aceita `NA` como marcador de null e `n` explícito para arrays
com `nil` no meio (limitação do `#` do Lua).

| Factory | O que faz |
|---------|-----------|
| `:from_table(arr, [name])` | `CategoricalSeries.from_table` — constrói a partir de tabela Lua |
| `:from_codes(codes_arr, levels_arr, [name], [n])` | `CategoricalSeries.from_codes` — constrói via codes explícitos |

**Métodos** (espelham `Series` quando faz sentido):

| Método | O que faz |
|--------|-----------|
| `:get(i)` / `:set(i, v)` / `:set_null(i)` / `:is_null(i)` | acesso 1-based |
| `:isna(i)` / `:notna(i)` | alias de `is_null` / `not is_null` |
| `:append(v)` | adiciona ao fim (cria level se valor é novo) |
| `:len()` / `:size()` / `:count_nonnull()` | dimensões |
| `:clone()` / `:head(n)` / `:tail(n)` / `:take(idx)` | seleção (clone profundo de levels) |
| `:filter(mask)` | `Series<bool>` → novo `CategoricalSeries` |
| `:dropna()` / `:fillna(value)` | valores ausentes |
| `:ffill()` | forward fill — propaga último label não-nulo anterior |
| `:bfill()` | backward fill — propaga próximo label não-nulo seguinte |
| `:shift([periods])` | desloca valores (default 1); posições descobertas → null |
| `:sort(asc)` / `:argsort(asc)` | ordenação lexicográfica por label |
| `:eq(target)` / `:ne(target)` | igual / diferente → `Series<bool>` |
| `:lt(target)` / `:le(target)` | menor / menor-igual → `Series<bool>` |
| `:gt(target)` / `:ge(target)` | maior / maior-igual → `Series<bool>` |
| `:min()` / `:max()` | menor / maior label lexicográfico entre não-nulos |
| `:unique()` / `:nunique()` / `:value_counts()` | distintos |
| `:map(fn, [dtype], [name])` | aplica fn a cada label; retorna `Series` do dtype inferido |
| `:where(cond, other)` | mantém self onde cond=true; usa other senão → novo `CategoricalSeries` |
| `:mask(cond, other)` | inverso de where |
| `:describe()` | `{dtype, count, nulls, unique, levels, top, freq}` |
| `:astype(dtype)` | → `string`, `int64`, `float64` (parseia labels), ou clone categorical |
| `:to_table([na])` | → tabela Lua |

<a id="section--cat-proxy-de-operacoes-sobre-series-categorical"></a>

### `.cat` — proxy de operações sobre Series categorical

| Método | O que faz |
|--------|-----------|
| `.cat:codes()` | → `Series<int64>` com índices 1-based (null → null) |
| `.cat:levels()` | tabela Lua ordenada com os labels |
| `.cat:rename_categories({old=new, ...})` | renomeia labels; preserva dados |
| `.cat:set_categories(novos)` | reordena/restringe; valores fora viram null |
| `.cat:add_categories(lista)` | adiciona novos labels (idempotente) |
| `.cat:remove_categories(lista)` | remove labels; referências viram null |

<a id="section--dataset-core-dataset"></a>

### `DataSet`

**Construção:** `DataSet.new(name)`, `smaug.DataSet({{nome, dados, dtype?}, ...})`.

| Método | O que faz |
|--------|-----------|
| `:add_column(nome, series)` | adiciona (valida comprimento e nome único) |
| `:drop_column(nome)` / `:rename_column(old, new)` | CRUD de colunas |
| `:column(nome)` / `:col(nome)` / `df[nome]` | acessa coluna → **view COW protegida** (mutar a extraída não altera o frame; use `:update_column` para mutação intencional) |
| `:has_column(nome)` / `:columns()` | metadados |
| `:ncols()` / `:nrows()` / `:len()` | dimensões |
| `:dtypes()` / `:row(i, [na])` | tipos por coluna / linha como tabela |
| `:clone()` | cópia profunda (par de `Series:clone`); cada coluna clonada |
| `:filter(mask)` | `Series<bool>` → novo DataSet; `df[mask]` é açúcar |
| `:fillna(value)` / `:fillna({col=value})` | preenche NULLs → novo DataSet |
| `:sort_by(col, asc)` | ordena todas as colunas pela chave (par de `Series:sort`) |
| `:head(n)` / `:tail(n)` / `:iloc(start, stop)` / `:take(idx)` | fatias |
| `:sample(n, [seed])` | amostra aleatória |
| `:select(nomes)` | subconjunto/reordenação de colunas |
| `:dropna([subset])` | remove linhas com NULL |
| `:update_column(nome, series)` | substitui coluna existente |
| `:assign(nome, fn_ou_series)` | adiciona/substitui coluna calculada → novo DataSet (original nunca é mutado, nem ao substituir coluna existente) |
| `:nunique()` | `{coluna → nº distintos não-nulos}` |
| `:corr()` | matriz N×N de correlação de Pearson entre colunas numéricas → DataSet |
| `:cov()` | matriz N×N de covariância amostral entre colunas numéricas → DataSet |
| `:equals(other)` | igualdade estrutural (colunas, ordem, dtypes, valores) → bool |
| `:compare(other)` | diferenças célula a célula → DataSet `{linha, coluna, self, other}` |
| `:duplicated([subset], [keep])` | máscara de linhas duplicadas; subset = nome/lista/nil; keep ∈ {first,last,none} → `Series<bool>` |
| `:drop_duplicates([subset], [keep])` | remove linhas duplicadas → novo DataSet |
| `:rename(mapping)` | renomeia colunas em lote: `{old=new, ...}` → novo DataSet |
| `:at(i, col)` / `:iat(i, ci)` | célula única por nome / por índice posicional de coluna |
| `:insert(loc, nome, series)` | insere coluna na posição `loc` (1-based) |
| `:to_dict([orient])` | → tabela Lua; `"columns"` (default) ou `"records"` |
| `DataSet.from_dict(t, [orient])` | constrói a partir de tabela Lua; infere dtype por coluna |
| `:to_markdown()` | tabela em Markdown (GitHub-flavored), todas as linhas |
| `:to_string([opts])` | render texto plano; `opts.max_rows` limita linhas |
| `:describe()` / `:to_table([na])` | inspeção |

**Reduções por coluna → DataSet de 1 linha** (só colunas numéricas; cada coluna
mantém seu dtype de resultado). Erro se nenhuma coluna numérica.

| Método | Resultado |
|---|---|
| `:sum([min_count])` / `:prod([min_count])` | redução; `min_count` opt-in (default 0 → soma de vazio = 0) |
| `:mean()` / `:median()` / `:std()` / `:var()` | `std`/`var` **amostrais** (ddof=1; <2 → NA) → float64 |
| `:min()` / `:max()` | preservam dtype |
| `:quantile(q)` / `:skew()` / `:kurtosis()` / `:mad()` / `:sem()` | → float64 |
| `:count_nonnull()` | → int64 |

**Element-wise / transforms → DataSet de mesma forma.** Operações numéricas
(`abs`, `round`, `clip`, `cum*`, `diff`) **erram** se houver coluna não-numérica
(selecione as numéricas antes).

| Método | Resultado |
|---|---|
| `:abs()` / `:round([nd])` / `:clip(lo, hi)` | element-wise numérico → mesma forma |
| `:cumsum()` / `:cummin()` / `:cummax()` / `:cumprod()` | acumulado por coluna (numérico) |
| `:diff()` | diferença sucessiva (numérico) |
| `:ffill()` / `:bfill()` / `:shift([p])` | propagação/deslocamento (qualquer dtype) |
| `:isna()` / `:notna()` | máscara de nulidade por coluna (qualquer dtype) → DataSet bool |
| `:astype({col=dtype}, options)` | conversão por mapa; `{dayfirst=false}` opcional para string→datetime; colunas fora do mapa inalteradas |

**Operações relacionais:**

| Método | O que faz |
|--------|-----------|
| `:concat(other)` | empilha outro DataSet verticalmente (mesmo schema) |
| `:groupby(key):sum(col)` | soma por grupo; chave simples ou composta |
| `:groupby(key):mean(col)` | média por grupo |
| `:groupby(key):min(col)` | mínimo por grupo |
| `:groupby(key):max(col)` | máximo por grupo |
| `:groupby(key):count()` | contagem de não-nulos por grupo |
| `:groupby(key):std(col)` | desvio padrão por grupo |
| `:groupby(key):var(col)` | variância por grupo |
| `:groupby(key):median(col)` | mediana por grupo |
| `:groupby(key):quantile(q, col)` | percentil por grupo |
| `:groupby(key):first(col)` | primeiro valor por grupo |
| `:groupby(key):last(col)` | último valor por grupo |
| `:groupby(key):prod(col)` | produto por grupo |
| `:groupby(key):nunique(col)` | distintos por grupo |
| `:groupby(key):agg({col = fn \| {fn1, ...}})` | múltiplas agregações de uma vez |
| `:groupby(key):transform(fn_name, col)` | broadcast do resultado de volta ao tamanho original |
| `:join(other, on, [how], [suffixes])` | inner/left/right/outer; chave simples ou composta |
| `smaug.concat({ds1, ds2, ...})` | empilha lista de DataSets verticalmente |
| `:pivot(index, columns, values)` | long → wide |
| `:pivot_table(index, columns, values, [aggfunc])` | pivot com agregação (default `mean`) |
| `:melt(id_vars, [value_vars], [var_name], [value_name])` | wide → long |
| `:stack(col_names)` / `:unstack(index, col, values)` | reshape eixo→linha / linha→eixo |
| `:explode(col)` | uma linha por elemento da coluna-lista |
| `:rolling(w):sum/mean/min/max/std/var/count(col)` | janela deslizante por coluna; `:min_periods(p)` antes do agregado p/ janelas parciais |

**Entrada e saída:**

| Método | O que faz |
|--------|-----------|
| `:to_csv(path, [opts])` | escreve CSV em arquivo |
| `:to_csv_mem([opts])` | → string Lua com o CSV |
| `:to_json(path, [opts])` | escreve JSON em arquivo |
| `:to_json_mem([opts])` | → string Lua com o JSON |

<a id="section-entry-point-init-lua"></a>

### Funções do módulo `smaug`

```lua
local smaug = require("smaug")

-- I/O
smaug.read_csv(path, [opts])        -- opts: {sep, header, na_values, quote}
smaug.read_csv_mem(buf, [opts])
smaug.read_json(path)
smaug.read_json_mem(buf)

-- construção
smaug.DataSet({{nome, dados, dtype?}, ...})
smaug.Series                         -- classe (com .Categorical, .NA, .datetime, factories)
smaug.NA                             -- sentinela de nulo
smaug.concat({ds1, ds2, ...})
smaug.join(a, b, on, [how], [suffixes])
```

---

<a id="section-proximas-versoes"></a>

## Próximas versões

Itens documentados em `Roadmap.md`:

- **v1.0 (em finalização):** inventário arquitetural, Bloco G (decisões de fundação),
  migração de primitivas para o núcleo, reorganização estrutural, hardening global
  de cobertura, distribuição (LuaRocks), docstrings.
- **v1.5:** NDJSON (depende de schema), driver de banco (`connect`/`query`/`execute`),
  SQLite, Excel, Parquet/Arrow (I/O), lazy execution, serialização `.smg` (Anel 4),
  `.str` Tier D (regex, Unicode-aware), `interpolate`, `cross_join`, `query`/`eval`,
  stable sort.
- **v2.0:** Models (Anel 5 — schema, validação, CRUD local).
- **Trilha Analítica (2.x+):** `Matrix` (Anel 6), `Tensor` + broadcasting axis-aware
  (Anel 7), ML e pipelines (Anel 8).

*ORM relacional, query builder e tradução SQL são **Fronteiras encerradas** (ver
`Roadmap.md`), não itens de roadmap.*

---

[Continuar no guia do usuário](USER_GUIDE.md) · [Consultar a API](API_INDEX.md) · [Início da documentação](README.md)
