-- lua/smaug/core/int_scalar.lua
--
-- Fonte ÚNICA de reconhecimento de escalar int-based na fronteira Anel 1 -> Anel 0.
--
-- Problema que resolve: um escalar int64 do usuario cruza a fronteira para o C em
-- varios pontos - entrada (set/append/fillna), comparacao (gt/lt/eq/...) e
-- aritmetica escalar (s + n). Cada ponto reconhecia o escalar por conta propria
-- com um guard cru `type(v) == "number"`. Furos desse padrao espalhado:
--   1. o guard recusa `cdata int64_t` - a UNICA forma que preserva os 64 bits -
--      forcando o usuario ao `number`, que degrada acima de 2^53 (Sub-A do 9.1).
--   2. `number > 2^53` ja chega degradado e passava em silencio: comparacao
--      marcava a linha errada, aritmetica operava no valor errado - sem erro.
-- A entrada (check_value) ja fora curada no 9.1; comparadores e aritmetica
-- ficaram para tras (call-sites de operacao que o 9.1 nao varreu). Ver 9.3.
--
-- Desenho: separar RECONHECIMENTO de POLITICA. O reconhecimento ("que forma de
-- int64 e este escalar?") e unico e vive em classify(). A politica ("o que fazer
-- com number > 2^53?") diverge por contexto e fica no call-site:
--   . entrada-de-dado (set/append/fillna): number_overflow AVISA-e-aceita - o
--     valor vira dado do usuario, a Sub-A e irrecuperavel, a escolha e dele.
--   . operacao (comparadores, aritmetica): number_overflow ERRA por origem - o
--     escalar e operando; um resultado sobre valor degradado seria mentira.
-- Coerente com o Contrato 1 (promocao segura; nunca narrowing em silencio):
-- number > 2^53 e narrowing consumado; cdata int64_t/uint64_t e a forma exata.
--
-- Escopo: int-based (int64; datetime herda no threshold, epoch_ms e int64_t).
-- float64/string/bool nao passam por aqui - double e nativo, string/bool nao tem
-- degradacao numerica. Ver 9.3 (nao-escopo).
--
-- Ponto de plugue futuro: quando os comparadores/aritmetica descerem ao Anel 0
-- com escalar exato, a validacao de forma permanece aqui (o C nao enxerga a
-- degradacao de um number Lua - ela ja aconteceu antes da fronteira).

local ffi = require("ffi")

local M = {}

local INT64_MAX_MAG = 9007199254740992      -- 2^53: teto de precisao exata do double
local INT64_MAX_U   = 9223372036854775807ULL -- teto de int64_t, visto como uint64_t
M.INT64_MAX_MAG = INT64_MAX_MAG
M.INT64_MAX_U   = INT64_MAX_U

-- classify(v) -> classe, v : reconhecimento PURO da forma do escalar. Sem warn,
-- sem error. Espelha exatamente o ramo int64 do check_value (mesma ordem de
-- checagem cdata: uint64_t antes de int64_t). Classes:
--   number_ok          number inteiro, |v| < 2^53 (exato e nao-ambiguo)
--   number_at_boundary number inteiro, |v| == 2^53 (exato, mas 2^53+1 degrada
--                      para ca -> ambiguo; a operacao recusa, a entrada aceita)
--   number_overflow    number inteiro, |v| > 2^53 (ja degradado na origem)
--   not_integer        number com parte fracionaria
--   cdata_i64          cdata int64_t (preserva os 64 bits)
--   cdata_u64_ok       cdata uint64_t <= INT64_MAX
--   uint_overflow      cdata uint64_t > INT64_MAX (wraparound proibido)
--   invalid            qualquer outra coisa
--
-- Nota sobre o limiar: um number so e inteiro confiavel se |v| < 2^53. Em
-- |v| == 2^53 ha ambiguidade -- 2^53+1 arredonda para 2^53 (round-half-to-even),
-- entao um number igual a 2^53 pode ser 2^53 legitimo OU 2^53+1 degradado. Daí a
-- classe de fronteira: quem produz resultado (operacao) recusa; quem guarda dado
-- do usuario (entrada) aceita, preservando o comportamento pre-9.3 (`> 2^53`).
function M.classify(v)
    local tv = type(v)
    if tv == "number" then
        if v % 1 ~= 0 then return "not_integer", v end
        local mag = v < 0 and -v or v
        if mag < INT64_MAX_MAG then return "number_ok", v end
        if mag == INT64_MAX_MAG then return "number_at_boundary", v end
        return "number_overflow", v
    elseif tv == "cdata" then
        if ffi.istype("uint64_t", v) then
            if v > INT64_MAX_U then return "uint_overflow", v end
            return "cdata_u64_ok", v
        elseif ffi.istype("int64_t", v) then
            return "cdata_i64", v
        end
    end
    return "invalid", v
end

-- is_int_cdata(v): true se v e cdata int-based (int64_t ou uint64_t) - a forma
-- exata que preserva os 64 bits. Usado pelos guards de entrada da aritmetica
-- escalar para decidir se o escalar entra pela via int-based (ver 9.3 Fase 2).
function M.is_int_cdata(v)
    return type(v) == "cdata"
       and (ffi.istype("int64_t", v) or ffi.istype("uint64_t", v))
end

-- check_operation(v, what, level): politica de OPERACAO (comparadores, aritmetica
-- escalar). Devolve v pronto para o FFI (o C recebe int64_t exato) ou erra
-- visivel. `what` rotula a operacao; `level` aponta o call-site do usuario.
-- number >= 2^53 (overflow e boundary) -> ERRO por origem (nao avisa-aceita como
-- a entrada faz; o limiar da operacao inclui o boundary ambiguo).
function M.check_operation(v, what, level)
    local cls = M.classify(v)
    if cls == "number_ok" or cls == "cdata_i64" or cls == "cdata_u64_ok" then
        return v
    elseif cls == "number_overflow" or cls == "number_at_boundary" then
        error("smaug: " .. what .. ": o escalar int64 " .. tostring(v) .. " atinge ou "
              .. "excede 2^53 como number Lua e pode ter perdido precisao na origem; "
              .. "use ffi.new(\"int64_t\", ...) ou o sufixo LL para o valor exato",
              level or 4)
    elseif cls == "uint_overflow" then
        error("smaug: " .. what .. ": valor uint64_t (" .. tostring(v) .. ") excede o "
              .. "range de int64 (max " .. tostring(INT64_MAX_U) .. "); wraparound "
              .. "nao e permitido", level or 4)
    else  -- not_integer, invalid
        error("smaug: " .. what .. " espera inteiro int64 (number ou cdata int64_t); "
              .. "recebido " .. tostring(v), level or 4)
    end
end

return M
