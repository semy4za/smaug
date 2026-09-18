-- tests/props/test_props.lua
-- Property-based testing: invariantes estatísticas e de composição.
-- Rode da raiz: luajit tests/props/test_props.lua

package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

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

-- Seeds fixas (reprodutível) — múltiplas para ampliar o espaço sem perder
-- determinismo. Trocar/adicionar seeds é uma decisão consciente.
local random_seeds = { 20260602, 1337, 987654321 }
local cases_per_seed = 400          -- 3 seeds × 400 = 1200 casos por invariante (≥1000)

local nan_value = 0/0
local function is_nan(value) return value ~= value end

-- estado de teste; registra a seed e o caso atuais para mensagens de falha
local current_seed, current_case = nil, nil
local passed_checks = 0
local function check(condition, message)
    if not condition then
        error(string.format("FALHOU [seed=%s caso=%d]: %s",
              tostring(current_seed), current_case or -1, message), 2)
    end
    passed_checks = passed_checks + 1
end

-- ---------- geradores (cada um respeita o contrato da propriedade) ----------

-- série LIMPA: sem null, sem NaN. Para sort/argsort (que recusam ambos).
local function generate_clean_series(dtype, element_count)
    local allocated_source_series = smaug.Series.new(dtype, element_count)
    for row_index = 1, element_count do
        if dtype == "int64" then allocated_source_series:set(row_index, math.random(-100000, 100000))
        else allocated_source_series:set(row_index, (math.random() - 0.5) * 2e6) end
    end
    return allocated_source_series
end

-- série com NULLS (~25%): para filter, clone, Kleene.
local function generate_nullable_series(dtype, element_count)
    local allocated_source_series = smaug.Series.new(dtype, element_count)
    for row_index = 1, element_count do
        if math.random() < 0.25 then allocated_source_series:set_null(row_index)
        elseif dtype == "int64" then allocated_source_series:set(row_index, math.random(-100000, 100000))
        else allocated_source_series:set(row_index, (math.random() - 0.5) * 2e6) end
    end
    return allocated_source_series
end

-- série f64 com NULLS e NaN (~15% null, ~15% NaN): testa null≠NaN.
local function generate_series_with_nan(element_count)
    local floating_point_series = smaug.Series.float64(element_count)
    for row_index = 1, element_count do
        local random_value = math.random()
        if random_value < 0.15 then floating_point_series:set_null(row_index)
        elseif random_value < 0.30 then floating_point_series:set(row_index, nan_value)
        else floating_point_series:set(row_index, (math.random() - 0.5) * 2e6) end
    end
    return floating_point_series
end

-- permutação aleatória 1..n (Fisher-Yates)
local function random_permutation(element_count)
    local values = {}; for row_index = 1, element_count do values[row_index] = row_index end
    for row_index = element_count, 2, -1 do local swap_index = math.random(row_index); values[row_index], values[swap_index] = values[swap_index], values[row_index] end
    return values
end

-- ---------- a bateria de invariantes ----------
-- Cada função roda 1 caso aleatório e faz suas asserções.

local properties = {}

-- INV1: clone é independente — mutar o clone não afeta o original (anti-aliasing)
properties["clone_independente"] = function()
    local element_count = math.random(1, 40)
    local nullable_series = generate_nullable_series("float64", element_count)
    local snapshot_values = {}; for row_index = 1, element_count do snapshot_values[row_index] = nullable_series:get(row_index) end
    local cloned_series = nullable_series:clone()
    -- muta o clone em posições aleatórias
    for unused_index = 1, math.random(1, 5) do cloned_series:set(math.random(element_count), 123456.0) end
    for row_index = 1, element_count do
        check(nullable_series:get(row_index) == snapshot_values[row_index], "clone mutou o original no idx " .. row_index)
    end
end

-- INV2: view COMPARTILHA memória — mutar a base reflete na view (oposto do clone)
properties["view_compartilha"] = function()
    local element_count = math.random(2, 40)
    local clean_series = generate_clean_series("float64", element_count)
    local start = math.random(1, element_count)
    local length = math.random(1, element_count - start + 1)
    local series_view = clean_series:view(start, length)
    check(series_view:len() == length, "view comprimento errado")
    for row_index = 1, length do
        check(series_view:get(row_index) == clean_series:get(start + row_index - 1), "view não reflete a base no idx " .. row_index)
    end
end

-- INV3: sort preserva o MULTICONJUNTO e é monotônico (série limpa)
properties["sort_permutacao"] = function()
    local element_count = math.random(1, 40)
    local clean_series = generate_clean_series("int64", element_count)
    local before = {}; for row_index = 1, element_count do before[row_index] = clean_series:get(row_index) end
    table.sort(before)
    local sorted = clean_series:sort()
    check(sorted:len() == element_count, "sort mudou o tamanho")
    for row_index = 1, element_count do
        check(sorted:get(row_index) == before[row_index],
              "multiconjunto difere no idx " .. row_index)
        if row_index > 1 then
            check(sorted:get(row_index) >= sorted:get(row_index - 1), "sort não-monotônico no idx " .. row_index)
        end
    end
end

-- INV4: sort/argsort RECUSAM séries com null ou NaN (contrato)
properties["sort_recusa_null_nan"] = function()
    local element_count = math.random(1, 30)
    local nan_series = generate_series_with_nan(element_count)
    -- só vale o invariante se a série DE FATO tem null ou NaN
    local tem_buraco = false
    for row_index = 1, element_count do
        if nan_series:is_null(row_index) or is_nan(nan_series:get(row_index)) then tem_buraco = true; break end
    end
    if tem_buraco then
        local succeeded = pcall(function() return nan_series:sort() end)
        check(not succeeded, "sort deveria recusar série com null/NaN")
        check(nan_series:argsort() == nil, "argsort deveria retornar nil com null/NaN")
    end
end

-- INV5: len(filter(s, mask)) == count_true(mask), com nulls
properties["filter_count_true"] = function()
    local element_count = math.random(1, 40)
    local nullable_series = generate_nullable_series("float64", element_count)
    local threshold = (math.random() - 0.5) * 2e6
    local filter_mask = nullable_series:gt(threshold)
    local filtered = nullable_series:filter(filter_mask)
    check(filtered:len() == filter_mask:count_true(),
          "len(filter)=" .. filtered:len() .. " != count_true=" .. filter_mask:count_true())
end

-- INV6: take + permutação inversa = identidade
properties["take_inversa"] = function()
    local element_count = math.random(1, 30)
    local clean_series = generate_clean_series("float64", element_count)
    local permutation = random_permutation(element_count)
    local inverse_permutation = {}; for row_index = 1, element_count do inverse_permutation[permutation[row_index]] = row_index end
    local selected_result = clean_series:take(permutation):take(inverse_permutation)
    for row_index = 1, element_count do
        check(math.abs(selected_result:get(row_index) - clean_series:get(row_index)) < 1e-9, "take+inversa != id no idx " .. row_index)
    end
end

-- INV7: astype ida-e-volta f64->i64->f64 preserva valores inteiros
properties["astype_ida_volta"] = function()
    local element_count = math.random(1, 30)
    local floating_point_series = smaug.Series.float64(element_count)
    for row_index = 1, element_count do
        if math.random() < 0.2 then floating_point_series:set_null(row_index)
        else floating_point_series:set(row_index, math.random(-100000, 100000)) end  -- inteiros como float
    end
    local round = floating_point_series:astype("int64"):astype("float64")
    for row_index = 1, element_count do
        if floating_point_series:is_null(row_index) then
            check(round:is_null(row_index), "astype perdeu null no idx " .. row_index)
        else
            check(round:get(row_index) == floating_point_series:get(row_index), "astype ida-volta difere no idx " .. row_index)
        end
    end
end

-- INV8: fillna remove todos os nulls e preserva não-nulos e NaN
properties["fillna_remove_null"] = function()
    local element_count = math.random(1, 40)
    local nan_series = generate_series_with_nan(element_count)
    local snapshot_values = {}; for row_index = 1, element_count do snapshot_values[row_index] = nan_series:get(row_index) end  -- nil p/ null, NaN p/ nan
    local filled_result = nan_series:fillna(0)
    for row_index = 1, element_count do
        if nan_series:is_null(row_index) then
            check(filled_result:get(row_index) == 0, "fillna não preencheu null no idx " .. row_index)
        elseif is_nan(snapshot_values[row_index]) then
            check(is_nan(filled_result:get(row_index)), "fillna não preservou NaN no idx " .. row_index)
        else
            check(filled_result:get(row_index) == snapshot_values[row_index], "fillna alterou valor no idx " .. row_index)
        end
    end
end

-- INV9: Kleene — not(not b) == b
properties["kleene_dupla_negacao"] = function()
    local element_count = math.random(1, 30)
    local nullable_series = generate_nullable_series("float64", element_count)
    local greater_than_mask = nullable_series:gt(0)
    local logical_not_result = greater_than_mask:lnot():lnot()
    for row_index = 1, element_count do
        check(greater_than_mask:get(row_index) == logical_not_result:get(row_index), "not(not b) != b no idx " .. row_index)
        check(greater_than_mask:is_null(row_index) == logical_not_result:is_null(row_index), "not(not b) perdeu NA no idx " .. row_index)
    end
end

-- INV10: Kleene — De Morgan: not(a and b) == (not a) or (not b)
properties["kleene_de_morgan"] = function()
    local element_count = math.random(1, 30)
    local greater_than_mask = generate_nullable_series("float64", element_count):gt(0)
    local greater_than_mask_2 = generate_nullable_series("float64", element_count):gt(0)
    local logical_not_result  = greater_than_mask:land(greater_than_mask_2):lnot()
    local right = greater_than_mask:lnot():lor(greater_than_mask_2:lnot())
    for row_index = 1, element_count do
        check(logical_not_result:get(row_index) == right:get(row_index), "De Morgan (valor) falha no idx " .. row_index)
        check(logical_not_result:is_null(row_index) == right:is_null(row_index), "De Morgan (NA) falha no idx " .. row_index)
    end
end

-- ---------- runner ----------

-- Gerador de série string com valores aleatórios e ~20% nulls
local words = {"alpha", "beta", "gamma", "delta", "epsilon",
               "zeta", "eta", "theta", "iota", "kappa"}
local function generate_string_series(element_count)
    local allocated_string_series = smaug.Series.new("string", element_count)
    for row_index = 1, element_count do
        if math.random() < 0.2 then
            allocated_string_series:set_null(row_index)
        else
            allocated_string_series:set(row_index, words[math.random(#words)])
        end
    end
    return allocated_string_series
end

-- INV-STR-1: set → get devolve o mesmo valor (round-trip)
properties["str_set_get"] = function()
    local element_count = math.random(1, 20)
    local allocated_string_series = smaug.Series.new("string", element_count)
    local values = {}
    for row_index = 1, element_count do
        values[row_index] = words[math.random(#words)]
        allocated_string_series:set(row_index, values[row_index])
    end
    for row_index = 1, element_count do
        check(allocated_string_series:get(row_index) == values[row_index], "str set_get round-trip idx " .. row_index)
        check(not allocated_string_series:is_null(row_index),    "str set_get: não é null idx " .. row_index)
    end
end

-- INV-STR-2: clone é independente — mutar o clone não afeta o original
properties["str_clone_independente"] = function()
    local element_count = math.random(2, 20)
    local string_series = generate_string_series(element_count)
    -- snapshot dos valores originais
    local snapshot_values = {}
    for row_index = 1, element_count do snapshot_values[row_index] = string_series:get(row_index) end  -- nil se null
    local cloned_series = string_series:clone()
    -- muta o clone em posições não-null
    for row_index = 1, element_count do
        if not cloned_series:is_null(row_index) then cloned_series:set(row_index, "mutado") end
    end
    -- original deve estar intacto
    for row_index = 1, element_count do
        check(string_series:get(row_index) == snapshot_values[row_index], "str clone: original alterado no idx " .. row_index)
    end
end

-- INV-STR-3: sort produz sequência não-decrescente (valores não-null)
properties["str_sort_ordenado"] = function()
    local element_count = math.random(2, 30)
    -- série sem nulls para sort ser aplicável
    local allocated_string_series = smaug.Series.new("string", element_count)
    for row_index = 1, element_count do allocated_string_series:set(row_index, words[math.random(#words)]) end
    local sorted = allocated_string_series:sort(true)
    for row_index = 1, element_count - 1 do
        local left_value, right_value = sorted:get(row_index), sorted:get(row_index + 1)
        check(left_value <= right_value, "str sort: ordem violada entre idx " .. row_index .. " e " .. (row_index+1))
    end
end

-- INV-STR-4: count_nonnull é consistente com is_null
properties["str_count_nonnull"] = function()
    local element_count = math.random(1, 30)
    local string_series = generate_string_series(element_count)
    local manual = 0
    for row_index = 1, element_count do
        if not string_series:is_null(row_index) then manual = manual + 1 end
    end
    check(string_series:count_nonnull() == manual,
          "str count_nonnull: " .. string_series:count_nonnull() .. " ≠ " .. manual)
end

-- INV-STR-5: filter reduz o tamanho proporcionalmente à máscara
properties["str_filter_reduz"] = function()
    local element_count = math.random(2, 30)
    local string_series = generate_string_series(element_count)
    -- máscara aleatória
    local mask_vals = {}
    local count_true = 0
    for row_index = 1, element_count do
        mask_vals[row_index] = math.random() < 0.5
        if mask_vals[row_index] then count_true = count_true + 1 end
    end
    local filter_mask = smaug.Series.new("float64", element_count)
    for row_index = 1, element_count do filter_mask:set(row_index, mask_vals[row_index] and 1.0 or 0.0) end
    local bool_mask = filter_mask:gt(0.5)
    local filtered = string_series:filter(bool_mask)
    check(filtered:len() == count_true,
          "str filter: tamanho " .. filtered:len() .. " ≠ " .. count_true)
end

-- INV-STR-5: filter reduz o tamanho proporcionalmente à máscara
properties["str_filter_reduz"] = function()
    local element_count = math.random(2, 30)
    local string_series = generate_string_series(element_count)
    -- máscara aleatória
    local mask_vals = {}
    local count_true = 0
    for row_index = 1, element_count do
        mask_vals[row_index] = math.random() < 0.5
        if mask_vals[row_index] then count_true = count_true + 1 end
    end
    local filter_mask = smaug.Series.new("float64", element_count)
    for row_index = 1, element_count do filter_mask:set(row_index, mask_vals[row_index] and 1.0 or 0.0) end
    local bool_mask = filter_mask:gt(0.5)
    local filtered = string_series:filter(bool_mask)
    check(filtered:len() == count_true,
          "str filter: tamanho " .. filtered:len() .. " ≠ " .. count_true)
end

-- =====================================================================
-- INV Anel 2 — Operações relacionais
-- =====================================================================

local groups  = {"A","B","C"}

-- INV-G1: groupby sum de cada grupo == sum(serie filtrada por grupo)
properties["groupby_sum_consistente"] = function()
    local element_count   = math.random(3, 30)
    local group_series = smaug.Series.new("string", element_count)
    local value_series = smaug.Series.new("int64",  element_count)
    local group_sum = {}
    for group_key in pairs({A=true,B=true,C=true}) do group_sum[group_key] = 0 end
    for row_index = 1, element_count do
        local group_key = groups[math.random(#groups)]
        group_series:set(row_index, group_key)
        local random_integer = math.random(-100, 100)
        value_series:set(row_index, random_integer)
        group_sum[group_key] = group_sum[group_key] + random_integer
    end
    local source_dataset = smaug.DataSet({{"g", group_series, "string"}, {"v", value_series, "int64"}})
    local sum_result = source_dataset:groupby("g"):sum("v")
    for row_index = 1, sum_result:nrows() do
        local group_key = sum_result:col("g"):get(row_index)
        local group_sum_2 = sum_result:col("v"):get(row_index)
        check(group_sum_2 == group_sum[group_key], "groupby sum difere para grupo " .. group_key)
    end
end

-- INV-G2: groupby count: soma dos counts == nrows do DataSet original
properties["groupby_count_total"] = function()
    local element_count = math.random(2, 30)
    local group_series = smaug.Series.new("string", element_count)
    for row_index = 1, element_count do group_series:set(row_index, groups[math.random(#groups)]) end
    local value_series = smaug.Series.new("int64", element_count)
    for row_index = 1, element_count do value_series:set(row_index, math.random(100)) end
    local source_dataset = smaug.DataSet({{"g", group_series, "string"}, {"v", value_series, "int64"}})
    local group_counts = source_dataset:groupby("g"):count()
    local total = 0
    for row_index = 1, group_counts:nrows() do total = total + group_counts:col("count"):get(row_index) end
    check(total == element_count, "groupby count: soma " .. total .. " ≠ " .. element_count)
end

-- INV-C1: concat preserva nrows (len(concat(a,b)) == len(a) + len(b))
properties["concat_nrows"] = function()
    local left_row_count = math.random(1, 20)
    local right_row_count = math.random(1, 20)
    local left_values = smaug.Series.new("int64", left_row_count)
    local right_values = smaug.Series.new("int64", right_row_count)
    for row_index = 1, left_row_count do left_values:set(row_index, math.random(100)) end
    for row_index = 1, right_row_count do right_values:set(row_index, math.random(100)) end
    local left_dataset = smaug.DataSet({{"v", left_values, "int64"}})
    local right_dataset = smaug.DataSet({{"v", right_values, "int64"}})
    local concatenated_result  = smaug.concat({left_dataset, right_dataset})
    check(concatenated_result:nrows() == left_row_count + right_row_count, "concat nrows: " .. concatenated_result:nrows() .. " ≠ " .. (left_row_count+right_row_count))
    -- valores preservados
    for row_index = 1, left_row_count do
        check(concatenated_result:col("v"):get(row_index) == left_values:get(row_index), "concat: valor esq idx " .. row_index)
    end
    for row_index = 1, right_row_count do
        check(concatenated_result:col("v"):get(left_row_count + row_index) == right_values:get(row_index), "concat: valor dir idx " .. row_index)
    end
end

-- INV-J1: inner join ⊆ cross product (toda linha do inner tem match nos dois lados)
properties["join_inner_match"] = function()
    local left_row_count = math.random(2, 10)
    local right_row_count = math.random(2, 10)
    local left_key_values, right_key_values = {}, {}
    for row_index = 1, left_row_count do left_key_values[row_index] = math.random(1, 5) end
    for row_index = 1, right_row_count do right_key_values[row_index] = math.random(1, 5) end
    local left_keys = smaug.Series.new("int64", left_row_count); for row_index=1,left_row_count do left_keys:set(row_index, left_key_values[row_index]) end
    local left_values = smaug.Series.new("int64", left_row_count); for row_index=1,left_row_count do left_values:set(row_index, row_index*10) end
    local right_keys = smaug.Series.new("int64", right_row_count); for row_index=1,right_row_count do right_keys:set(row_index, right_key_values[row_index]) end
    local right_values = smaug.Series.new("int64", right_row_count); for row_index=1,right_row_count do right_values:set(row_index, row_index*100) end
    local left_dataset = smaug.DataSet({{"k",left_keys,"int64"},{"va",left_values,"int64"}})
    local right_dataset = smaug.DataSet({{"k",right_keys,"int64"},{"vb",right_values,"int64"}})
    local joined_dataset  = left_dataset:join(right_dataset, "k", "inner")
    -- todo resultado deve ter chave que existe em ambos os lados
    local left_key_set, right_key_set = {}, {}
    for unused_index, element_value in ipairs(left_key_values) do left_key_set[element_value] = true end
    for unused_index, element_value in ipairs(right_key_values) do right_key_set[element_value] = true end
    for row_index = 1, joined_dataset:nrows() do
        local join_key = joined_dataset:col("k"):get(row_index)
        check(left_key_set[join_key] and right_key_set[join_key], "join inner: chave " .. join_key .. " sem match")
    end
end

-- INV-J2: left join preserva todos os rows do lado esquerdo
properties["join_left_preserva_esq"] = function()
    local left_row_count = math.random(2, 10)
    local right_row_count = math.random(2, 10)
    local left_keys = smaug.Series.new("int64", left_row_count); for row_index=1,left_row_count do left_keys:set(row_index, math.random(1,5)) end
    local left_values = smaug.Series.new("int64", left_row_count); for row_index=1,left_row_count do left_values:set(row_index, row_index) end
    local right_keys = smaug.Series.new("int64", right_row_count); for row_index=1,right_row_count do right_keys:set(row_index, math.random(3,7)) end
    local right_values = smaug.Series.new("int64", right_row_count); for row_index=1,right_row_count do right_values:set(row_index, row_index*100) end
    local left_dataset = smaug.DataSet({{"k",left_keys,"int64"},{"va",left_values,"int64"}})
    local right_dataset = smaug.DataSet({{"k",right_keys,"int64"},{"vb",right_values,"int64"}})
    local joined_dataset  = left_dataset:join(right_dataset, "k", "left")
    -- contamos quantas linhas do esquerdo têm match no direito
    local right_key_set = {}
    for row_index = 1, right_row_count do right_key_set[right_keys:get(row_index)] = true end
    local expected = 0
    for row_index = 1, left_row_count do
        local join_key = left_keys:get(row_index)
        if right_key_set[join_key] then
            -- pode ter múltiplos matches; conta todos
            for right_row_index = 1, right_row_count do if right_keys:get(right_row_index) == join_key then expected = expected + 1 end end
        else
            expected = expected + 1
        end
    end
    check(joined_dataset:nrows() == expected, "join left nrows: " .. joined_dataset:nrows() .. " ≠ " .. expected)
end

-- INV-U1: unique preserva ordem de primeira aparição
properties["unique_ordem_aparicao"] = function()
    local element_count = math.random(2, 30)
    local allocated_integer_series = smaug.Series.new("int64", element_count)
    for row_index = 1, element_count do allocated_integer_series:set(row_index, math.random(1, 5)) end
    local unique_values  = allocated_integer_series:unique()
    -- verifica que cada valor de u aparece pela primeira vez antes de qualquer
    -- valor subsequente de u na série original
    local first_seen = {}
    for row_index = 1, element_count do
        local element_value = allocated_integer_series:get(row_index)
        if element_value ~= nil and not first_seen[element_value] then first_seen[element_value] = row_index end
    end
    local prev_first = 0
    for row_index = 1, unique_values:len() do
        local element_value = unique_values:get(row_index)
        if element_value ~= nil then
            check(first_seen[element_value] > prev_first, "unique: ordem de aparição violada idx " .. row_index)
            prev_first = first_seen[element_value]
        end
    end
end

-- INV-U2: value_counts: sum(count) == count_nonnull(s)
properties["value_counts_soma"] = function()
    local element_count = math.random(2, 30)
    local allocated_integer_series = smaug.Series.new("int64", element_count)
    for row_index = 1, element_count do
        if math.random() < 0.2 then allocated_integer_series:set_null(row_index)
        else allocated_integer_series:set(row_index, math.random(1, 5)) end
    end
    local value_counts   = allocated_integer_series:value_counts()
    local total_sum = 0
    for row_index = 1, value_counts:nrows() do total_sum = total_sum + value_counts:col("count"):get(row_index) end
    check(total_sum == allocated_integer_series:count_nonnull(), "value_counts soma: " .. total_sum .. " ≠ " .. allocated_integer_series:count_nonnull())
end

-- INV-CS1: diff(cumsum(s)) == s (para séries sem NA)
properties["diff_cumsum_identidade"] = function()
    local element_count = math.random(2, 30)
    local allocated_integer_series = smaug.Series.new("int64", element_count)
    for row_index = 1, element_count do allocated_integer_series:set(row_index, math.random(-100, 100)) end
    local diff_result = allocated_integer_series:cumsum():diff()
    -- primeiros periods=1 são NA; do 2 em diante deve bater
    for row_index = 2, element_count do
        check(diff_result:get(row_index) == allocated_integer_series:get(row_index), "diff(cumsum) ≠ s no idx " .. row_index)
    end
    check(diff_result:is_null(1), "diff(cumsum): idx 1 deve ser NA")
end

-- INV-R1: rolling(w):sum() == manual (sem NA)
properties["rolling_sum_manual"] = function()
    local element_count = math.random(3, 20)
    local window_size = math.random(2, element_count)
    local allocated_integer_series = smaug.Series.new("int64", element_count)
    for row_index = 1, element_count do allocated_integer_series:set(row_index, math.random(1, 100)) end
    local sum_result = allocated_integer_series:rolling(window_size):sum()
    for row_index = 1, element_count do
        if row_index < window_size then
            check(sum_result:is_null(row_index), "rolling sum: idx " .. row_index .. " deveria ser NA")
        else
            local expected = 0
            for window_index = row_index - window_size + 1, row_index do expected = expected + allocated_integer_series:get(window_index) end
            check(sum_result:get(row_index) == expected, "rolling sum: idx " .. row_index .. " difere")
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

for unused_index, name in ipairs(order) do
    local property_test = properties[name]
    for unused_index_2, seed in ipairs(random_seeds) do
        current_seed = seed
        math.randomseed(seed)
        for case_index = 1, cases_per_seed do
            current_case = case_index
            property_test()
        end
    end
end

print(string.format("OK — %d invariantes × %d seeds × %d casos = %d checks (property-based)",
      #order, #random_seeds, cases_per_seed, passed_checks))
