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
-- Descobre os fontes do Anel 0 a auditar SEM lista hardcoded (12.29/A3). Antes,
-- uma lista fixa aqui não pegava um .c novo não-listado — passava em silêncio.
-- Fonte primária: build/SOURCES (gravado por build.sh/build_win.ps1 a partir do
-- glob que compilou — a lista exata do que foi construído, sem defasagem).
-- Fallback: os src/*.c do MANIFEST (quando rodado standalone, sem build antes).
-- Salvaguarda: se nenhuma fonte der lista, o eixo FALHA (não audita vazio em
-- silêncio) — "falha visível > acerto adivinhado".
local function discover_c_sources()
    local files = {}
    -- 1. build/SOURCES (uma path por linha, forward slash nos dois OS)
    local src_list = C.read_file("build/SOURCES")
    if src_list then
        for path in src_list:gmatch("([^\r\n]+)") do
            path = path:gsub("^%s+", ""):gsub("%s+$", "")
            if path:match("%.c$") then files[#files+1] = path end
        end
    end
    -- 2. Fallback: MANIFEST (formato "<hash> <linhas> ./src/X.c")
    if #files == 0 then
        local manifest = C.read_file("docs/MANIFEST.txt")
        if manifest then
            for path in manifest:gmatch("%./(src/[%w_]+%.c)") do
                files[#files+1] = path
            end
        end
    end
    return files
end

local files = discover_c_sources()
if #files == 0 then
    io.stderr:write("eixo 14: nenhuma fonte C descoberta "
        .. "(build/SOURCES ausente e MANIFEST sem src/*.c) — não é possível auditar\n")
    os.exit(1)
end

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

-- Exit code: o runner (parity.sh/ps1) marca FALHOU se ≠ 0 — sem abortar o build
-- (parity é indicador permanente). Alinhado ao eixo 15: um global mutável no
-- Anel 0 é inconsistência real com o CONTRATO 11, tem de aparecer destacado.
if total_globais > 0 then os.exit(1) end
