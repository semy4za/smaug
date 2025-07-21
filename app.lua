local smaug_db = require 'data.query_manager'
local ds = require 'tools.dataset'

local consulta = smaug_db:query("SELECT empresa, sub_canal from summarized_SAIDA_CANAL_2026Q1;")


x = ds.from_records(consulta)
print(x:head())