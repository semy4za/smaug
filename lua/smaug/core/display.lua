-- lua/smaug/core/display.lua
--
-- Fonte ÚNICA de formatação de APRESENTAÇÃO (pretty-print) para Series e
-- DataSet. Consolida o que antes eram três `cell_str` divergentes e cinco
-- `pad` duplicados (item 11.5), e garante que nenhum valor chega quebrado na
-- tela (item 11.4).
--
-- Contrato: apresentação ≠ serialização. Aqui o objetivo é legibilidade
-- (`%.6g`, ~6 dígitos significativos); a serialização exata (`%.17g`) vive no
-- Anel 0 (`smaug_fmt_*`, item 10.9). Não alinhar um ao outro é intencional.
--
-- Invariantes:
--   * int64 é formatado a partir do cdata cru (via cell_of → get_raw), nunca do
--     double de get() — valores > 2^53 saem EXATOS, sem notação científica.
--   * larguras e preenchimento contam CODEPOINTS (dwidth), não bytes, então
--     texto acentuado/UTF-8 alinha corretamente.
--   * NaN/±inf normalizados ("nan"/"inf"/"-inf"), eliminando divergência de
--     libc no display (glibc vs UCRT) — espelha a normalização do smaug_fmt.

local M = {}

-- dwidth(s): largura de exibição em codepoints UTF-8 (não bytes). Conta os
-- bytes que NÃO são continuação (continuação = 0x80..0xBF). Suficiente para
-- alinhar texto latino/acentuado; largura dupla (CJK) fica fora do escopo.
function M.dwidth(s)
    local n = 0
    for i = 1, #s do
        local b = string.byte(s, i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

-- cell_str(v): representação de apresentação de UM valor já resolvido.
--   nil                     → "NA"
--   cdata (int64_t/uint64)  → dígitos exatos, sem sufixo LL/ULL
--   number inteiro          → "%d" (dentro de int64); senão "%.6g"
--   NaN / ±inf              → "nan" / "inf" / "-inf" (normalizado)
--   número fracionário      → "%.6g"
--   outro (string/bool)     → tostring
function M.cell_str(v)
    if v == nil then return "NA" end
    local tv = type(v)
    if tv == "cdata" then
        -- int64_t/uint64 cru: tostring dá "…LL"/"…ULL"; tiramos o sufixo.
        return (tostring(v):gsub("U?LL$", ""))
    end
    if tv == "number" then
        if v ~= v            then return "nan"  end   -- NaN
        if v ==  math.huge   then return "inf"  end
        if v == -math.huge   then return "-inf" end
        if v % 1 == 0 and v < 9.2233720368548e18 and v > -9.2233720368548e18 then
            return string.format("%d", v)
        end
        return string.format("%.6g", v)
    end
    return tostring(v)
end

-- cell_of(series, i): valor de apresentação da linha i preservando int64 exato.
-- É o ponto único que decide usar get_raw (cdata) em vez de get (double) para
-- int64 — a regra do item 11.4 mora aqui, não espalhada por callsite.
function M.cell_of(series, i)
    if series._dtype == "int64" then
        return series:get_raw(i)   -- nil em null, cdata int64 caso contrário
    end
    return series:get(i)
end

-- pad(s, w, align): preenche `s` até largura `w` (em codepoints). align:
-- "right" para números, "left" (default) para texto. Se já for mais largo,
-- retorna intacto.
function M.pad(s, w, align)
    local gap = w - M.dwidth(s)
    if gap <= 0 then return s end
    local sp = string.rep(" ", gap)
    if align == "right" then return sp .. s end
    return s .. sp
end

-- align_for(dtype): política de alinhamento por dtype — número à direita,
-- texto/bool/datetime à esquerda (espelha pandas: colunas numéricas alinhadas
-- à direita para leitura vertical).
function M.align_for(dtype)
    if dtype == "int64" or dtype == "float64" then return "right" end
    return "left"
end

-- plan_rows(n, limit): quais linhas exibir (índices 1-based) e após quantas
-- inserir o marcador de corte "…", estilo pandas (cabeça + cauda). Se limit for
-- nil ou n <= limit, devolve todas as linhas e brk=nil (sem corte).
--   n=10, limit=6 → head=3 (1,2,3), cauda=3 (8,9,10), brk=3
function M.plan_rows(n, limit)
    if not limit or limit < 1 or n <= limit then
        local idx = {}
        for i = 1, n do idx[i] = i end
        return idx, nil
    end
    local head = math.ceil(limit / 2)
    local tail = limit - head
    local idx = {}
    for i = 1, head do idx[#idx + 1] = i end
    local brk = #idx                       -- marcador vem após 'brk' linhas
    for i = n - tail + 1, n do idx[#idx + 1] = i end
    return idx, brk
end

return M
