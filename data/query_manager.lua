local dotenv = require 'tools.dotenv'
local sqlite3 = require 'lsqlite3'

local qm = {}
local env = dotenv.load()

qm.db_path = env.DB_SQLITE

-- Função auxiliar para abrir a conexão
function qm:db() 
    return sqlite3.open(qm.db_path)
end

function qm:query(sql) 
    local db = qm:db() -- Abre a conexão
    local records = {}

    -- O nrows precisa ser chamado a partir da instância 'db'
    for row in db:nrows(sql) do
        table.insert(records, row)
    end

    db:close() -- Fecha a conexão após iterar tudo
    return records
end

return qm