-- scripts/parity/14_thread_safety.lua
-- Eixo 14: thread-safety do Anel 0 — nenhum estado global mutável.
--
-- Invariante (CONTRATO 11): o backend C é reentrante. Toda função recebe o que
-- precisa por parâmetro; não há estado compartilhado entre chamadas. Duas
-- threads operando em séries diferentes nunca colidem.
--
-- Por que auditoria estática e não teste com threads: um teste de corrida
-- exigiria -lpthread no build (e winpthreads no Windows), e races são
-- não-determinísticos — passariam por sorte. A ausência de estado global é
-- verificável no fonte e é o que de fato garante o invariante. Mesmo padrão do
-- eixo 13 (__tostring).
--
-- Histórico: até 2026-07-14 o `smaug_ops_str.c` tinha `g_sort_series` e
-- `g_sort_ascending` (contexto do comparador do qsort). Eram os únicos globais
-- mutáveis do Anel 0 — e faziam argsort/sort/rank segfaultar com 2 threads em
-- séries DIFERENTES (a primeira a terminar zerava o global enquanto a outra
-- ainda estava no qsort). Substituídos por um quicksort com contexto explícito.

local C = dofile("scripts/parity/common.lua")

-- Um global mutável em C é uma declaração em escopo de arquivo que NÃO é:
--   * `const` (imutável — tabelas de lookup, literais)
--   * um protótipo/definição de função (tem '(' antes do ';' ou '{')
-- Buscamos `static <tipo> <nome>` fora de função, sem const.
local files = {
    "src/smaug_astype.c", "src/smaug_convert.c", "src/smaug_core.c",
    "src/smaug_csv.c", "src/smaug_datetime.c", "src/smaug_json.c",
    "src/smaug_ops_bool.c", "src/smaug_ops_f64.c", "src/smaug_ops_i64.c",
    "src/smaug_ops_str.c", "src/smaug_ops_window.c", "src/smaug_str.c",
}

local rows = {}
local total_globais = 0

for _, path in ipairs(files) do
    local src = C.read_file(path) or ""
    local achados = {}
    local lineno = 0
    for line in (src .. "\n"):gmatch("(.-)\n") do
        lineno = lineno + 1
        -- só declarações em escopo de arquivo (coluna 0) começando com `static`
        if line:match("^static%s") then
            local is_const = line:match("^static%s+const%s") ~= nil
            -- função: tem '(' antes de qualquer ';' ou '='
            local head = line:match("^([^;=]*)") or ""
            local is_func = head:find("%(") ~= nil
            if not is_const and not is_func then
                achados[#achados + 1] = string.format("`%s:%d`", path:match("[^/]+$"), lineno)
            end
        end
    end
    total_globais = total_globais + #achados
    local status = (#achados == 0) and "🟩" or "🟥"
    local detalhe = (#achados == 0) and "—" or table.concat(achados, ", ")
    rows[#rows + 1] = { "`" .. path:match("[^/]+$") .. "`", status, detalhe }
end

local header = { "fonte C", "sem global mutável", "achados" }

local out = {
    C.section(14, "Thread-safety — estado global mutável no Anel 0",
        "🟩 = nenhum estado global mutável (função reentrante). 🟥 = global "
        .. "encontrado. Invariante do CONTRATO 11: o Anel 0 é thread-safe — "
        .. "toda função recebe contexto por parâmetro. `static const` não conta "
        .. "(imutável); protótipos e definições de função não contam. "
        .. "Total de globais mutáveis: **" .. total_globais .. "**."),
    "",
    C.render_table(header, rows),
    "",
}

io.write(table.concat(out, "\n"))
