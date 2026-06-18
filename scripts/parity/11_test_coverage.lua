-- scripts/parity/11_test_coverage.lua
-- Eixo 11: cobertura de testes proporcional por dtype.
-- Examina os testes Lua e classifica quantos checks de cada arquivo
-- mencionam cada dtype.

local C = dofile("scripts/parity/common.lua")

-- Lista de testes Lua (estrutura por domínio — tests/{series,dataset,io,props}/)
local test_files = {
    "series/test_constructors", "series/test_access", "series/test_reduce",
    "series/test_stat", "series/test_window", "series/test_predicates",
    "series/test_selection", "series/test_str", "series/test_dt",
    "series/test_categorical",
    "dataset/test_core", "dataset/test_relational", "dataset/test_stat",
    "dataset/test_io_support",
    "io/test_csv", "io/test_json",
    "props/test_props", "props/test_integration",
}

local dtypes = { "float64", "int64", "bool", "string", "datetime", "categorical" }

-- Conta menções de cada dtype em cada arquivo de teste
local mention_count = {}
local check_count = {}
for _, tf in ipairs(test_files) do
    local content = C.read_file("tests/" .. tf .. ".lua") or ""
    check_count[tf] = 0
    for _ in content:gmatch('check%s*%(') do
        check_count[tf] = check_count[tf] + 1
    end
    mention_count[tf] = {}
    for _, dt in ipairs(dtypes) do
        local n = 0
        for _ in content:gmatch('"'..dt..'"') do n = n + 1 end
        mention_count[tf][dt] = n
    end
end

-- Agregado: total de menções de cada dtype em toda a suite
local total_per_dtype = {}
for _, dt in ipairs(dtypes) do total_per_dtype[dt] = 0 end
for _, tf in ipairs(test_files) do
    for _, dt in ipairs(dtypes) do
        total_per_dtype[dt] = total_per_dtype[dt] + mention_count[tf][dt]
    end
end

-- Total de checks
local total_checks = 0
for _, tf in ipairs(test_files) do total_checks = total_checks + check_count[tf] end

-- Saída
local rows_tests = {}
for _, tf in ipairs(test_files) do
    local row = { "`"..tf.."`", check_count[tf] }
    for _, dt in ipairs(dtypes) do
        row[#row+1] = mention_count[tf][dt] > 0 and tostring(mention_count[tf][dt]) or "—"
    end
    rows_tests[#rows_tests+1] = row
end

local header_t = { "arquivo", "checks" }
for _, dt in ipairs(dtypes) do header_t[#header_t+1] = dt end

local rows_dt = {}
for _, dt in ipairs(dtypes) do
    rows_dt[#rows_dt+1] = { dt, total_per_dtype[dt] }
end

local out = {
    C.section(11, "Cobertura de testes proporcional",
        "Quantos checks cada arquivo de teste tem, e quantas vezes cada dtype é "
        .. "mencionado em cada arquivo (heurística: contagem de strings literais "
        .. "como `\"float64\"`, `\"int64\"` etc.)."),
    "",
    "### Por arquivo de teste",
    "",
    C.render_table(header_t, rows_tests),
    "",
    string.format("**Total de checks:** %d", total_checks),
    "",
    "### Menções totais por dtype (toda a suite)",
    "",
    C.render_table({"dtype", "menções"}, rows_dt),
    "",
}

io.write(table.concat(out, "\n"))
