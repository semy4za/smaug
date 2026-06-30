# API_INDEX — catálogo do que já existe

**Propósito:** inventário de tudo que está implementado. Antes de criar
qualquer função/método novo, consulte aqui se já não existe. É a defesa contra
reimplementação e deriva.

**Como manter:** atualizar a cada função/método adicionado ou removido.

> Convenção: `<t>` = `f64` ou `i64`. Índices em C são 0-based; no Lua, 1-based.

> **Contrato de status (`smaug_types.h`):** `smaug_status_t` =
> `SMG_OK (0)` / `SMG_NULL_VALUE` / `SMG_ERR_OOB` / `SMG_ERR_ARGUMENT` /
> `SMG_ERR_NOMEM`. O engine valida e comunica — não confia que o caller validou.

---

## Camada C — backend (`include/*.h`, `src/*.c`)

### Lifecycle e acesso (`smaug_core.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_<t>_create(size)` | cria série de `size` elementos, todos NULL |
| `smaug_<t>_create_with_capacity(size, cap)` | cria com capacidade pré-alocada |
| `smaug_<t>_create_from_array(arr, len)` | cria a partir de array C, tudo válido |
| `smaug_<t>_free(s)` | libera a série (NULL-safe) |
| `smaug_<t>_clone(s)` | cópia profunda independente |
| `smaug_<t>_view(s, start, len)` | view zero-copy; COW na primeira mutação |
| `smaug_<t>_get(s, idx, status)` | lê valor + `smaug_status_t*` anulável |
| `smaug_<t>_set(s, idx, val)` | grava valor → `smaug_status_t`; COW detach se view |
| `smaug_<t>_set_null(s, idx)` | marca posição como NULL → `smaug_status_t` |
| `smaug_<t>_is_null(s, idx)` | testa se posição é NULL |
| `smaug_<t>_append(s, val)` | adiciona ao fim; COW detach se view |
| `smaug_<t>_append_null(s)` | adiciona NULL ao fim |
| `smaug_free(ptr)` | libera buffers crus (compare/argsort/bool) — usar SEMPRE esta |

### Aritmética (`smaug_numeric.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_<t>_add/sub/mul/div(a, b)` | aritmética série×série (propaga NA) |
| `smaug_<t>_add/sub/mul/div_scalar(a, k)` | aritmética série×escalar |

`div/0 → null` em f64 e i64. `NaN` só existe como valor presente em f64.

### Reduções (`smaug_numeric.h`)

| Função | Retorno |
|--------|---------|
| `smaug_<t>_sum(s, ignore_na)` | f64→double, i64→int64 |
| `smaug_<t>_mean(s, ignore_na)` | double |
| `smaug_<t>_min/max(s, ignore_na)` | f64→double, i64→int64, dt→int64 (epoch), bool→uint8+status, str→ptr+len |
| `smaug_<t>_var/std(s, ignore_na)` | double, amostral (÷ N-1; <2 → NaN) |
| `smaug_<t>_count_nonnull(s)` | size_t |

### Comparações e ordenação (`smaug_numeric.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_<t>_gt/lt/eq/ge/le/ne(s, k, &out_mask)` | → bool array (uint8_t*); liberar c/ `smaug_free` |
| `smaug_<t>_argsort(s, asc)` | → size_t* (permutação); NULL se há nulos |
| `smaug_<t>_sort(s, asc)` | → nova série ordenada; NULL se há nulos |
| `smaug_<t>_take(s, idx, len)` | → nova série com os índices dados |
| `smaug_<t>_filter(s, mask)` | → nova série onde mask é true |

### Booleano / Kleene (`smaug_bool.h`)

| Função | O que faz |
|--------|-----------|
| `smaug_bool_and/or/xor(a, am, b, bm, n, &out)` | lógica de 3 valores |
| `smaug_bool_not(a, am, n, &out)` | negação Kleene |
| `smaug_bool_count_true(a, am, n)` | conta trues (NA ignorado) |
| `smaug_bool_eq/ne(s, threshold, &out_mask)` | comparação com escalar → máscara (NA preservado) |
| `smaug_bool_any/all(a, am, n)` | agregações (NA ignorado) |

### String (`smaug_string.h`)

Representação offset-based (buffer de bytes + array de offsets). String vazia `""` ≠ NULL.

| Função | O que faz |
|--------|-----------|
| `smaug_str_create(size)` | cria série de `size` strings, todas NULL |
| `smaug_str_create_with_capacity(size, buf_cap)` | cria com buffer pré-alocado |
| `smaug_str_create_from_array(arr, len)` | cria de `char*` array |
| `smaug_str_free(s)` | libera (NULL-safe) |
| `smaug_str_clone(s)` | cópia profunda independente |
| `smaug_str_get(s, idx, &out_len)` | → ponteiro p/ bytes + comprimento (sem `\0`) |
| `smaug_str_set(s, idx, str, len)` | grava (realoca buffer via memmove) |
| `smaug_str_set_null(s, idx)` / `smaug_str_is_null(s, idx)` | nulos |
| `smaug_str_append(s, str, len)` / `smaug_str_append_null(s)` | adiciona ao fim |
| `smaug_str_count_nonnull(s)` | size_t |
| `smaug_str_eq/lt/gt(s, target, target_len, &out_mask)` | → bool array; lexicográfico por bytes |
| `smaug_str_filter(s, mask)` | → nova série onde mask é true |
| `smaug_str_take(s, idx, len)` | → nova série com os índices dados |
| `smaug_str_argsort(s, asc)` | → size_t* (permutação); NULL se há nulos |
| `smaug_str_sort(s, asc)` | → nova série ordenada |

### I/O — Anel 3 (`smaug_io.h`)

Fronteira `smaug_table_t`: toda função de leitura produz `smaug_table_t*`
(checar `->error` antes de usar). Liberar com `smaug_table_free`.

| Função | O que faz |
|--------|-----------|
| `smaug_table_free(t)` | libera tabela e todos os recursos (NULL-safe) |
| `smaug_csv_default_opts()` | opções padrão: sep=`,` header=1 quote=`"` |
| `smaug_read_csv(path, opts)` | lê CSV de arquivo → `smaug_table_t*` |
| `smaug_read_csv_mem(buf, len, opts)` | lê CSV de buffer em memória |
| `smaug_write_csv(path, t, opts)` | escreve CSV em arquivo (0=ok, -1=erro) |
| `smaug_write_csv_mem(t, opts, &len)` | escreve CSV em buffer alocado; liberar c/ `smaug_free` |
| `smaug_read_json(path)` | lê JSON de arquivo (array de records) |
| `smaug_read_json_mem(buf, len)` | lê JSON de buffer em memória |
| `smaug_write_json(path, t, opts)` | escreve JSON em arquivo |
| `smaug_write_json_mem(t, opts, &len)` | escreve JSON em buffer alocado |

### Tipos (`smaug_types.h`)

`smaug_mask_t`, `smaug_metadata_t`, `smaug_series_f64_t`, `smaug_series_i64_t`,
`smaug_series_bool_t`, `smaug_series_str_t`, `smaug_column_t`, `smaug_table_t`.

---

## Camada Lua — frontend (`lua/smaug/`)

### `Series` (`core/series/`)

**Factories:** `Series.new(dtype, size, name)`, `Series.from_table(arr, dtype, name)`,
`Series.full(n, val)`. `Series.NA` (sentinela de nulo em tabelas).

> **NaN ≠ null:** `nil`/`Series.NA` → null (ausente, bitmask). `NaN` → valor
> presente indefinido, NÃO null. `ignore_na` pula null, não NaN.
> `sort`/`argsort` recusam NaN e null. Comparação com NaN → false (máscara válida).

| Método | O que faz |
|--------|-----------|
| `:get(i)` / `:set(i, v)` | acesso 1-based; nil↔NA |
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
| `:astype(dtype)` | conversão tolerante por elemento (inconversíveis → null); exceto `bool` numérico, que é rígido (só 0/1, resto orienta para `:map`) |
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
| `:rank([method])` | rank (`average`/`min`/`max`/`dense`); default `average` |
| `:pct_rank()` | rank percentual (0..1) |
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
| `:rolling(w):sum/mean/min/max/std/var/count/median/quantile/min_periods()` | agregação em janela |
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

### Métodos exclusivos de `Series<bool>`

| Método | O que faz |
|--------|-----------|
| `:count_true()` / `:any()` / `:all()` | agregações (NA ignorado) |
| `:land(b)` / `:lor(b)` / `:lxor(b)` / `:lnot()` | lógica Kleene |
| `:describe()` | `{count, nulls, count_true, count_false}` |

### `CategoricalSeries` (`core/series/categorical/_categorical.lua`)

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

### `.cat` — proxy de operações sobre Series categorical

| Método | O que faz |
|--------|-----------|
| `.cat:codes()` | → `Series<int64>` com índices 1-based (null → null) |
| `.cat:levels()` | tabela Lua ordenada com os labels |
| `.cat:rename_categories({old=new, ...})` | renomeia labels; preserva dados |
| `.cat:set_categories(novos)` | reordena/restringe; valores fora viram null |
| `.cat:add_categories(lista)` | adiciona novos labels (idempotente) |
| `.cat:remove_categories(lista)` | remove labels; referências viram null |

### `DataSet` (`core/dataset/`)

**Construção:** `DataSet.new(name)`, `smaug.DataSet({{nome, dados, dtype?}, ...})`.

| Método | O que faz |
|--------|-----------|
| `:add_column(nome, series)` | adiciona (valida comprimento e nome único) |
| `:drop_column(nome)` / `:rename_column(old, new)` | CRUD de colunas |
| `:column(nome)` / `:col(nome)` / `df[nome]` | acessa coluna |
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
| `:astype({col=dtype})` | conversão por mapa; colunas fora do mapa inalteradas |

**Operações relacionais (Anel 2):**

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
| `:rolling(w):sum/mean/min/max(col)` | janela deslizante por coluna |

**I/O (Anel 3):**

| Método | O que faz |
|--------|-----------|
| `:to_csv(path, [opts])` | escreve CSV em arquivo |
| `:to_csv_mem([opts])` | → string Lua com o CSV |
| `:to_json(path, [opts])` | escreve JSON em arquivo |
| `:to_json_mem([opts])` | → string Lua com o JSON |

### Entry point (`init.lua`)

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
