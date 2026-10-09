-- Resultados estruturados; texto de apresentacao nunca determina aprovacao.
local protocol = {}
local count = 0
local emitted = {}
local selected_axis = assert(tonumber(arg[1]), "axis required")

local function quote(value)
    local escaped = tostring(value):gsub('[%z\1-\31\\"]', function(character)
        return string.format("\\u%04x", string.byte(character))
    end)
    return '"' .. escaped .. '"'
end

function protocol.result(identifier, status, claim, evidence, limit)
    assert(not emitted[identifier], "duplicate result: " .. identifier)
    emitted[identifier] = true
    count = count + 1
    io.write('{"version":1,"axis":', selected_axis, ',"id":', quote(identifier),
        ',"status":', quote(status), ',"claim":', quote(claim),
        ',"evidence":', quote(evidence), ',"limit":', quote(limit or ""), '}\n')
end

function protocol.check(identifier, claim, callback, limit)
    local succeeded, evidence = pcall(callback)
    protocol.result(identifier, succeeded and "PASS" or "FAIL", claim,
        evidence or "assertions completed", limit)
end

function protocol.finish()
    assert(count > 0, "zero results")
    io.write('{"version":1,"axis":', selected_axis, ',"end":', count, '}\n')
end

return protocol
