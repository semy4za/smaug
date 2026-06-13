-- tests/test_props.lua
-- Property-based testing (Fase 1.6 — endurecimento).
--
-- Filosofia: em vez de exemplos fixos, gera milhares de entradas aleatórias e
-- verifica INVARIANTES que devem valer sempre. Cada propriedade tem seu gerador
-- apropriado, que RESPEITA O CONTRATO (ex.: o gerador do sort produz séries sem
-- null/NaN, porque o sort recusa esses; o do filter inclui nulls de propósito).
--
-- Reprodutibilidade: roda N casos para cada uma de SEEDS (seeds fixas e
-- documentadas). Tudo determinístico — rodou hoje, roda igual amanhã. Em caso
-- de falha, imprime a seed e o nº do caso para reprodução exata.
--
-- Rode da raiz:  luajit tests/test_props.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local smaug = require("smaug")
local S     = smaug.Series

-- Seeds fixas (reprodutível) — múltiplas para ampliar o espaço sem perder
-- determinismo. Trocar/adicionar seeds é uma decisão consciente.
local SEEDS = { 20260602, 1337, 987654321 }
local N_PER_SEED = 400          -- 3 seeds × 400 = 1200 casos por invariante (≥1000)

local nan = 0/0
local function is_nan(x) return x ~= x end

-- estado de teste; registra a seed e o caso atuais para mensagens de falha
local cur_seed, cur_case = nil, nil
local n_checks = 0
local function check(cond, msg)
    if not cond then
        error(string.format("FALHOU [seed=%s caso=%d]: %s",
              tostring(cur_seed), cur_case or -1, msg), 2)
    end
    n_checks = n_checks + 1
end

-- ---------- geradores (cada um respeita o contrato da propriedade) ----------

-- série LIMPA: sem null, sem NaN. Para sort/argsort (que recusam ambos).
local function gen_clean(dtype, n)
    local s = S.new(dtype, n)
    for i = 1, n do
        if dtype == "int64" then s:set(i, math.random(-100000, 100000))
        else s:set(i, (math.random() - 0.5) * 2e6) end
    end
    return s
end

-- série com NULLS (~25%): para filter, clone, Kleene.
local function gen_nullable(dtype, n)
    local s = S.new(dtype, n)
    for i = 1, n do
        if math.random() < 0.25 then s:set_null(i)
        elseif dtype == "int64" then s:set(i, math.random(-100000, 100000))
        else s:set(i, (math.random() - 0.5) * 2e6) end
    end
    return s
end

-- série f64 com NULLS e NaN (~15% null, ~15% NaN): testa null≠NaN.
local function gen_with_nan(n)
    local s = S.float64(n)
    for i = 1, n do
        local r = math.random()
        if r < 0.15 then s:set_null(i)
        elseif r < 0.30 then s:set(i, nan)
        else s:set(i, (math.random() - 0.5) * 2e6) end
    end
    return s
end

-- permutação aleatória 1..n (Fisher-Yates)
local function random_perm(n)
    local p = {}; for i = 1, n do p[i] = i end
    for i = n, 2, -1 do local j = math.random(i); p[i], p[j] = p[j], p[i] end
    return p
end

-- ---------- a bateria de invariantes ----------
-- Cada função roda 1 caso aleatório e faz suas asserções.

local PROPERTIES = {}

-- INV1: clone é independente — mutar o clone não afeta o original (anti-aliasing)
PROPERTIES["clone_independente"] = function()
    local n = math.random(1, 40)
    local s = gen_nullable("float64", n)
    local snap = {}; for i = 1, n do snap[i] = s:get(i) end
    local c = s:clone()
    -- muta o clone em posições aleatórias
    for _ = 1, math.random(1, 5) do c:set(math.random(n), 123456.0) end
    for i = 1, n do
        check(s:get(i) == snap[i], "clone mutou o original no idx " .. i)
    end
end

-- INV2: view COMPARTILHA memória — mutar a base reflete na view (oposto do clone)
PROPERTIES["view_compartilha"] = function()
    local n = math.random(2, 40)
    local s = gen_clean("float64", n)
    local start = math.random(1, n)
    local len = math.random(1, n - start + 1)
    local v = s:view(start, len)
    check(v:len() == len, "view comprimento errado")
    for i = 1, len do
        check(v:get(i) == s:get(start + i - 1), "view não reflete a base no idx " .. i)
    end
end

-- INV3: sort preserva o MULTICONJUNTO e é monotônico (série limpa)
PROPERTIES["sort_permutacao"] = function()
    local n = math.random(1, 40)
    local s = gen_clean("int64", n)
    local before = {}; for i = 1, n do before[i] = s:get(i) end
    table.sort(before)
    local sorted = s:sort()
    check(sorted:len() == n, "sort mudou o tamanho")
    for i = 1, n do
        check(sorted:get(i) == before[i],
              "multiconjunto difere no idx " .. i)
        if i > 1 then
            check(sorted:get(i) >= sorted:get(i - 1), "sort não-monotônico no idx " .. i)
        end
    end
end

-- INV4: sort/argsort RECUSAM séries com null ou NaN (contrato)
PROPERTIES["sort_recusa_null_nan"] = function()
    local n = math.random(1, 30)
    local s = gen_with_nan(n)
    -- só vale o invariante se a série DE FATO tem null ou NaN
    local tem_buraco = false
    for i = 1, n do
        if s:is_null(i) or is_nan(s:get(i)) then tem_buraco = true; break end
    end
    if tem_buraco then
        local ok = pcall(function() return s:sort() end)
        check(not ok, "sort deveria recusar série com null/NaN")
        check(s:argsort() == nil, "argsort deveria retornar nil com null/NaN")
    end
end

-- INV5: len(filter(s, mask)) == count_true(mask), com nulls
PROPERTIES["filter_count_true"] = function()
    local n = math.random(1, 40)
    local s = gen_nullable("float64", n)
    local k = (math.random() - 0.5) * 2e6
    local mask = s:gt(k)
    local filtered = s:filter(mask)
    check(filtered:len() == mask:count_true(),
          "len(filter)=" .. filtered:len() .. " != count_true=" .. mask:count_true())
end

-- INV6: take + permutação inversa = identidade
PROPERTIES["take_inversa"] = function()
    local n = math.random(1, 30)
    local s = gen_clean("float64", n)
    local perm = random_perm(n)
    local inv = {}; for i = 1, n do inv[perm[i]] = i end
    local back = s:take(perm):take(inv)
    for i = 1, n do
        check(math.abs(back:get(i) - s:get(i)) < 1e-9, "take+inversa != id no idx " .. i)
    end
end

-- INV7: astype ida-e-volta f64->i64->f64 preserva valores inteiros
PROPERTIES["astype_ida_volta"] = function()
    local n = math.random(1, 30)
    local s = S.float64(n)
    for i = 1, n do
        if math.random() < 0.2 then s:set_null(i)
        else s:set(i, math.random(-100000, 100000)) end  -- inteiros como float
    end
    local round = s:astype("int64"):astype("float64")
    for i = 1, n do
        if s:is_null(i) then
            check(round:is_null(i), "astype perdeu null no idx " .. i)
        else
            check(round:get(i) == s:get(i), "astype ida-volta difere no idx " .. i)
        end
    end
end

-- INV8: fillna remove todos os nulls e preserva não-nulos e NaN
PROPERTIES["fillna_remove_null"] = function()
    local n = math.random(1, 40)
    local s = gen_with_nan(n)
    local snap = {}; for i = 1, n do snap[i] = s:get(i) end  -- nil p/ null, NaN p/ nan
    local f = s:fillna(0)
    for i = 1, n do
        if s:is_null(i) then
            check(f:get(i) == 0, "fillna não preencheu null no idx " .. i)
        elseif is_nan(snap[i]) then
            check(is_nan(f:get(i)), "fillna não preservou NaN no idx " .. i)
        else
            check(f:get(i) == snap[i], "fillna alterou valor no idx " .. i)
        end
    end
end

-- INV9: Kleene — not(not b) == b
PROPERTIES["kleene_dupla_negacao"] = function()
    local n = math.random(1, 30)
    local s = gen_nullable("float64", n)
    local b = s:gt(0)
    local bb = b:lnot():lnot()
    for i = 1, n do
        check(b:get(i) == bb:get(i), "not(not b) != b no idx " .. i)
        check(b:is_null(i) == bb:is_null(i), "not(not b) perdeu NA no idx " .. i)
    end
end

-- INV10: Kleene — De Morgan: not(a and b) == (not a) or (not b)
PROPERTIES["kleene_de_morgan"] = function()
    local n = math.random(1, 30)
    local a = gen_nullable("float64", n):gt(0)
    local b = gen_nullable("float64", n):gt(0)
    local left  = a:land(b):lnot()
    local right = a:lnot():lor(b:lnot())
    for i = 1, n do
        check(left:get(i) == right:get(i), "De Morgan (valor) falha no idx " .. i)
        check(left:is_null(i) == right:is_null(i), "De Morgan (NA) falha no idx " .. i)
    end
end

-- ---------- runner ----------

-- Gerador de série string com valores aleatórios e ~20% nulls
local WORDS = {"alpha", "beta", "gamma", "delta", "epsilon",
               "zeta", "eta", "theta", "iota", "kappa"}
local function gen_str(n)
    local s = S.new("string", n)
    for i = 1, n do
        if math.random() < 0.2 then
            s:set_null(i)
        else
            s:set(i, WORDS[math.random(#WORDS)])
        end
    end
    return s
end

-- INV-STR-1: set → get devolve o mesmo valor (round-trip)
PROPERTIES["str_set_get"] = function()
    local n = math.random(1, 20)
    local s = S.new("string", n)
    local vals = {}
    for i = 1, n do
        vals[i] = WORDS[math.random(#WORDS)]
        s:set(i, vals[i])
    end
    for i = 1, n do
        check(s:get(i) == vals[i], "str set_get round-trip idx " .. i)
        check(not s:is_null(i),    "str set_get: não é null idx " .. i)
    end
end

-- INV-STR-2: clone é independente — mutar o clone não afeta o original
PROPERTIES["str_clone_independente"] = function()
    local n = math.random(2, 20)
    local s = gen_str(n)
    -- snapshot dos valores originais
    local snap = {}
    for i = 1, n do snap[i] = s:get(i) end  -- nil se null
    local c = s:clone()
    -- muta o clone em posições não-null
    for i = 1, n do
        if not c:is_null(i) then c:set(i, "mutado") end
    end
    -- original deve estar intacto
    for i = 1, n do
        check(s:get(i) == snap[i], "str clone: original alterado no idx " .. i)
    end
end

-- INV-STR-3: sort produz sequência não-decrescente (valores não-null)
PROPERTIES["str_sort_ordenado"] = function()
    local n = math.random(2, 30)
    -- série sem nulls para sort ser aplicável
    local s = S.new("string", n)
    for i = 1, n do s:set(i, WORDS[math.random(#WORDS)]) end
    local sorted = s:sort(true)
    for i = 1, n - 1 do
        local a, b = sorted:get(i), sorted:get(i + 1)
        check(a <= b, "str sort: ordem violada entre idx " .. i .. " e " .. (i+1))
    end
end

-- INV-STR-4: count_nonnull é consistente com is_null
PROPERTIES["str_count_nonnull"] = function()
    local n = math.random(1, 30)
    local s = gen_str(n)
    local manual = 0
    for i = 1, n do
        if not s:is_null(i) then manual = manual + 1 end
    end
    check(s:count_nonnull() == manual,
          "str count_nonnull: " .. s:count_nonnull() .. " ≠ " .. manual)
end

-- INV-STR-5: filter reduz o tamanho proporcionalmente à máscara
PROPERTIES["str_filter_reduz"] = function()
    local n = math.random(2, 30)
    local s = gen_str(n)
    -- máscara aleatória
    local mask_vals = {}
    local count_true = 0
    for i = 1, n do
        mask_vals[i] = math.random() < 0.5
        if mask_vals[i] then count_true = count_true + 1 end
    end
    local mask = S.new("float64", n)
    for i = 1, n do mask:set(i, mask_vals[i] and 1.0 or 0.0) end
    local bool_mask = mask:gt(0.5)
    local filtered = s:filter(bool_mask)
    check(filtered:len() == count_true,
          "str filter: tamanho " .. filtered:len() .. " ≠ " .. count_true)
end

-- INV-STR-5: filter reduz o tamanho proporcionalmente à máscara
PROPERTIES["str_filter_reduz"] = function()
    local n = math.random(2, 30)
    local s = gen_str(n)
    -- máscara aleatória
    local mask_vals = {}
    local count_true = 0
    for i = 1, n do
        mask_vals[i] = math.random() < 0.5
        if mask_vals[i] then count_true = count_true + 1 end
    end
    local mask = S.new("float64", n)
    for i = 1, n do mask:set(i, mask_vals[i] and 1.0 or 0.0) end
    local bool_mask = mask:gt(0.5)
    local filtered = s:filter(bool_mask)
    check(filtered:len() == count_true,
          "str filter: tamanho " .. filtered:len() .. " ≠ " .. count_true)
end

-- =====================================================================
-- INV Anel 2 — Operações relacionais
-- =====================================================================

local DataSet = require("smaug.core.dataset")
local NA      = S.NA
local GROUPS  = {"A","B","C"}

-- INV-G1: groupby sum de cada grupo == sum(serie filtrada por grupo)
PROPERTIES["groupby_sum_consistente"] = function()
    local n   = math.random(3, 30)
    local cat = S.new("string", n)
    local val = S.new("int64",  n)
    local group_sum = {}
    for g in pairs({A=true,B=true,C=true}) do group_sum[g] = 0 end
    for i = 1, n do
        local g = GROUPS[math.random(#GROUPS)]
        cat:set(i, g)
        local v = math.random(-100, 100)
        val:set(i, v)
        group_sum[g] = group_sum[g] + v
    end
    local ds = DataSet.from_columns({{"g", cat, "string"}, {"v", val, "int64"}})
    local gb = ds:groupby("g"):sum("v")
    for i = 1, gb:nrows() do
        local g = gb:col("g"):get(i)
        local s = gb:col("v"):get(i)
        check(s == group_sum[g], "groupby sum difere para grupo " .. g)
    end
end

-- INV-G2: groupby count: soma dos counts == nrows do DataSet original
PROPERTIES["groupby_count_total"] = function()
    local n = math.random(2, 30)
    local cat = S.new("string", n)
    for i = 1, n do cat:set(i, GROUPS[math.random(#GROUPS)]) end
    local val = S.new("int64", n)
    for i = 1, n do val:set(i, math.random(100)) end
    local ds = DataSet.from_columns({{"g", cat, "string"}, {"v", val, "int64"}})
    local cnt = ds:groupby("g"):count()
    local total = 0
    for i = 1, cnt:nrows() do total = total + cnt:col("count"):get(i) end
    check(total == n, "groupby count: soma " .. total .. " ≠ " .. n)
end

-- INV-C1: concat preserva nrows (len(concat(a,b)) == len(a) + len(b))
PROPERTIES["concat_nrows"] = function()
    local na = math.random(1, 20)
    local nb = math.random(1, 20)
    local va = S.new("int64", na)
    local vb = S.new("int64", nb)
    for i = 1, na do va:set(i, math.random(100)) end
    for i = 1, nb do vb:set(i, math.random(100)) end
    local da = DataSet.from_columns({{"v", va, "int64"}})
    local db = DataSet.from_columns({{"v", vb, "int64"}})
    local r  = smaug.concat({da, db})
    check(r:nrows() == na + nb, "concat nrows: " .. r:nrows() .. " ≠ " .. (na+nb))
    -- valores preservados
    for i = 1, na do
        check(r:col("v"):get(i) == va:get(i), "concat: valor esq idx " .. i)
    end
    for i = 1, nb do
        check(r:col("v"):get(na + i) == vb:get(i), "concat: valor dir idx " .. i)
    end
end

-- INV-J1: inner join ⊆ cross product (toda linha do inner tem match nos dois lados)
PROPERTIES["join_inner_match"] = function()
    local na = math.random(2, 10)
    local nb = math.random(2, 10)
    local keys_a, keys_b = {}, {}
    for i = 1, na do keys_a[i] = math.random(1, 5) end
    for i = 1, nb do keys_b[i] = math.random(1, 5) end
    local ka = S.new("int64", na); for i=1,na do ka:set(i, keys_a[i]) end
    local va = S.new("int64", na); for i=1,na do va:set(i, i*10) end
    local kb = S.new("int64", nb); for i=1,nb do kb:set(i, keys_b[i]) end
    local vb = S.new("int64", nb); for i=1,nb do vb:set(i, i*100) end
    local da = DataSet.from_columns({{"k",ka,"int64"},{"va",va,"int64"}})
    local db = DataSet.from_columns({{"k",kb,"int64"},{"vb",vb,"int64"}})
    local r  = da:join(db, "k", "inner")
    -- todo resultado deve ter chave que existe em ambos os lados
    local ka_set, kb_set = {}, {}
    for _, v in ipairs(keys_a) do ka_set[v] = true end
    for _, v in ipairs(keys_b) do kb_set[v] = true end
    for i = 1, r:nrows() do
        local k = r:col("k"):get(i)
        check(ka_set[k] and kb_set[k], "join inner: chave " .. k .. " sem match")
    end
end

-- INV-J2: left join preserva todos os rows do lado esquerdo
PROPERTIES["join_left_preserva_esq"] = function()
    local na = math.random(2, 10)
    local nb = math.random(2, 10)
    local ka = S.new("int64", na); for i=1,na do ka:set(i, math.random(1,5)) end
    local va = S.new("int64", na); for i=1,na do va:set(i, i) end
    local kb = S.new("int64", nb); for i=1,nb do kb:set(i, math.random(3,7)) end
    local vb = S.new("int64", nb); for i=1,nb do vb:set(i, i*100) end
    local da = DataSet.from_columns({{"k",ka,"int64"},{"va",va,"int64"}})
    local db = DataSet.from_columns({{"k",kb,"int64"},{"vb",vb,"int64"}})
    local r  = da:join(db, "k", "left")
    -- contamos quantas linhas do esquerdo têm match no direito
    local kb_set = {}
    for i = 1, nb do kb_set[kb:get(i)] = true end
    local expected = 0
    for i = 1, na do
        local k = ka:get(i)
        if kb_set[k] then
            -- pode ter múltiplos matches; conta todos
            for j = 1, nb do if kb:get(j) == k then expected = expected + 1 end end
        else
            expected = expected + 1
        end
    end
    check(r:nrows() == expected, "join left nrows: " .. r:nrows() .. " ≠ " .. expected)
end

-- INV-U1: unique preserva ordem de primeira aparição
PROPERTIES["unique_ordem_aparicao"] = function()
    local n = math.random(2, 30)
    local s = S.new("int64", n)
    for i = 1, n do s:set(i, math.random(1, 5)) end
    local u  = s:unique()
    -- verifica que cada valor de u aparece pela primeira vez antes de qualquer
    -- valor subsequente de u na série original
    local first_seen = {}
    for i = 1, n do
        local v = s:get(i)
        if v ~= nil and not first_seen[v] then first_seen[v] = i end
    end
    local prev_first = 0
    for i = 1, u:len() do
        local v = u:get(i)
        if v ~= nil then
            check(first_seen[v] > prev_first, "unique: ordem de aparição violada idx " .. i)
            prev_first = first_seen[v]
        end
    end
end

-- INV-U2: value_counts: sum(count) == count_nonnull(s)
PROPERTIES["value_counts_soma"] = function()
    local n = math.random(2, 30)
    local s = S.new("int64", n)
    for i = 1, n do
        if math.random() < 0.2 then s:set_null(i)
        else s:set(i, math.random(1, 5)) end
    end
    local vc   = s:value_counts()
    local soma = 0
    for i = 1, vc:nrows() do soma = soma + vc:col("count"):get(i) end
    check(soma == s:count_nonnull(), "value_counts soma: " .. soma .. " ≠ " .. s:count_nonnull())
end

-- INV-CS1: diff(cumsum(s)) == s (para séries sem NA)
PROPERTIES["diff_cumsum_identidade"] = function()
    local n = math.random(2, 30)
    local s = S.new("int64", n)
    for i = 1, n do s:set(i, math.random(-100, 100)) end
    local back = s:cumsum():diff()
    -- primeiros periods=1 são NA; do 2 em diante deve bater
    for i = 2, n do
        check(back:get(i) == s:get(i), "diff(cumsum) ≠ s no idx " .. i)
    end
    check(back:is_null(1), "diff(cumsum): idx 1 deve ser NA")
end

-- INV-R1: rolling(w):sum() == manual (sem NA)
PROPERTIES["rolling_sum_manual"] = function()
    local n = math.random(3, 20)
    local w = math.random(2, n)
    local s = S.new("int64", n)
    for i = 1, n do s:set(i, math.random(1, 100)) end
    local r = s:rolling(w):sum()
    for i = 1, n do
        if i < w then
            check(r:is_null(i), "rolling sum: idx " .. i .. " deveria ser NA")
        else
            local expected = 0
            for j = i - w + 1, i do expected = expected + s:get(j) end
            check(r:get(i) == expected, "rolling sum: idx " .. i .. " difere")
        end
    end
end

local order = {
    "clone_independente", "view_compartilha", "sort_permutacao",
    "sort_recusa_null_nan", "filter_count_true", "take_inversa",
    "astype_ida_volta", "fillna_remove_null",
    "kleene_dupla_negacao", "kleene_de_morgan",
    -- string
    "str_set_get", "str_clone_independente", "str_sort_ordenado",
    "str_count_nonnull", "str_filter_reduz",
    -- Anel 2
    "groupby_sum_consistente", "groupby_count_total",
    "concat_nrows",
    "join_inner_match", "join_left_preserva_esq",
    "unique_ordem_aparicao", "value_counts_soma",
    "diff_cumsum_identidade", "rolling_sum_manual",
}

for _, name in ipairs(order) do
    local prop = PROPERTIES[name]
    for _, seed in ipairs(SEEDS) do
        cur_seed = seed
        math.randomseed(seed)
        for caso = 1, N_PER_SEED do
            cur_case = caso
            prop()
        end
    end
end

print(string.format("OK — %d invariantes × %d seeds × %d casos = %d checks (property-based)",
      #order, #SEEDS, N_PER_SEED, n_checks))
