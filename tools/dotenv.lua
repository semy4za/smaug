local dotenv = {}

---@param filename? string The path to the .env file (defaults to ".env")
---@param inject_global? boolean Whether to inject variables into _G
---@return table env_vars Returns a table of variables (empty if file missing)
function dotenv.load(filename, inject_global)
  filename = filename or ".env"
  local file = io.open(filename, "r")

  if not file then
    print("Aviso: Arquivo " .. filename .. " não encontrado.")
    -- Returning an empty table prevents crashes in config.lua
    return {} 
  end

  local env_vars = {}

  for line in file:lines() do
    -- Matches keys with alphanumeric, underscores, dots, and hyphens
    if line:match("^%s*[^#%s]") then
      local key, value = line:match("^%s*([%w_%.-]+)%s*=%s*(.-)%s*$")

      if key and value then
        value = value:gsub("%s*#.*$", "")
        value = value:match('^"(.-)"$') or value:match("^'(.-)'$") or value

        env_vars[key] = value

        if inject_global then
          _G[key] = value
        end
      end
    end
  end

  file:close()
  return env_vars
end

return dotenv