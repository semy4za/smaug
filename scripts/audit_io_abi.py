#!/usr/bin/env python3
"""Confere layouts C/FFI e rejeição de bibliotecas incompatíveis (Linux/GCC)."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(args, cwd=ROOT):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout.strip()


def main():
    library = ROOT / "build/libsmaug.so"
    if not library.exists():
        raise SystemExit("Compile a biblioteca com make antes da auditoria.")
    with tempfile.TemporaryDirectory(prefix="smaug-abi-") as temporary:
        base = Path(temporary)
        probe = base / "layout.c"
        probe.write_text('''#include "smaug_io.h"
#include <stdio.h>
#include <stddef.h>
int main(void) {
    printf("%zu %zu %zu %zu %zu %zu %zu %zu %zu %zu", sizeof(smaug_column_t),
           sizeof(smaug_table_t), sizeof(smaug_csv_opts_t), offsetof(smaug_column_t, name_len),
           sizeof(smaug_schema_t), sizeof(smaug_schema_field_t),
           offsetof(smaug_schema_t, count), offsetof(smaug_schema_field_t, name_len),
           offsetof(smaug_schema_field_t, dtype), offsetof(smaug_schema_field_t, nullable));
    return 0;
}
''')
        run(["gcc", "-std=c11", "-Wall", "-Wextra", "-Werror", f"-I{ROOT / 'include'}",
             str(probe), "-o", str(base / "layout")])
        expected = run([str(base / "layout")])
        loader = str(ROOT / "lua/smaug/ffi_loader.lua")
        lua_layout = '''local ffi = require("ffi")
local lib = dofile(arg[1])
assert(lib.smaug_abi_version() == 1)
print(string.format("%d %d %d %d %d %d %d %d %d %d", ffi.sizeof("smaug_column_t"),
    ffi.sizeof("smaug_table_t"), ffi.sizeof("smaug_csv_opts_t"),
    ffi.offsetof("smaug_column_t", "name_len"), ffi.sizeof("smaug_schema_t"),
    ffi.sizeof("smaug_schema_field_t"), ffi.offsetof("smaug_schema_t", "count"),
    ffi.offsetof("smaug_schema_field_t", "name_len"), ffi.offsetof("smaug_schema_field_t", "dtype"),
    ffi.offsetof("smaug_schema_field_t", "nullable")))
'''
        layout_script = base / "layout.lua"
        layout_script.write_text(lua_layout)
        if run(["luajit", str(layout_script), loader]) != expected:
            raise RuntimeError("layout C/FFI diverge")
        print("PASS: layouts C/FFI e ABI 1")
        # O segundo candidato é válido: incompatibilidade do primeiro deve interromper.
        fallback = base / "build"
        fallback.mkdir()
        shutil.copy2(library, fallback / "libsmaug.so")
        work = base / "work"
        (work / "build").mkdir(parents=True)
        validator = base / "validate.lua"
        validator.write_text('''local ok, result = pcall(dofile, arg[1])
assert(not ok, "biblioteca incompatível foi aceita ou houve fallback")
assert(tostring(result):find("ABI incompatível", 1, true), tostring(result))
assert(tostring(result):find(arg[2], 1, true), tostring(result))
''')
        for label, source, message in [
            ("símbolo ausente", "int unrelated(void) { return 0; }", "sem símbolo"),
            ("versão divergente", "unsigned int smaug_abi_version(void) { return 99; }", "99"),
        ]:
            stub = base / "stub.c"
            stub.write_text(source)
            run(["gcc", "-shared", "-fPIC", str(stub), "-o",
                 str(work / "build/libsmaug.so")])
            run(["luajit", str(validator), loader, message], cwd=work)
            print(f"PASS: {label}, sem fallback para biblioteca válida")
        stub = base / "stub.c"
        stub.write_text("unsigned int smaug_abi_version(void) { return 1; }")
        run(["gcc", "-shared", "-fPIC", str(stub), "-o", str(work / "build/libsmaug.so")])
        schema_probe = base / "schema_capability.lua"
        schema_probe.write_text('''package.path = arg[1] .. "/lua/?.lua;" .. package.path
local Schema = require("smaug.core.schema")
local succeeded, message = pcall(function()
    return Schema({ { name = "value", dtype = "int64", nullable = true } })
end)
assert(not succeeded and tostring(message):find("sem suporte a Schema", 1, true), tostring(message))
''')
        run(["luajit", str(schema_probe), str(ROOT)], cwd=work)
        print("PASS: ABI 1 sem símbolos de schema recebe diagnóstico de capacidade")
        (work / "build/libsmaug.so").unlink()
        if run(["luajit", str(layout_script), loader], cwd=work) != expected:
            raise RuntimeError("fallback retornou layout divergente")
        print("PASS: candidato não carregável permite fallback")
        cleanup = base / "cleanup.lua"
        cleanup.write_text('''package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require("ffi")
local original_load = ffi.load
local fail_string = false
local fail_integer = false
local integer_frees = 0
local table_frees = 0
local frees = 0
ffi.load = function(path)
    local lib = original_load(path)
    return setmetatable({}, {__index = function(_, key)
        if key == "smaug_i64_set" then
            return function(...)
                if fail_integer then return 4 end
                return lib.smaug_i64_set(...)
            end
        end
        if key == "smaug_i64_free" then
            return function(...)
                integer_frees = integer_frees + 1
                return lib.smaug_i64_free(...)
            end
        end
        if key == "smaug_table_free" then
            return function(...)
                table_frees = table_frees + 1
                return lib.smaug_table_free(...)
            end
        end
        if key == "smaug_str_set" then
            return function(...)
                if fail_string then return 4 end
                return lib.smaug_str_set(...)
            end
        end
        if key == "smaug_str_free" then
            return function(...)
                frees = frees + 1
                return lib.smaug_str_free(...)
            end
        end
        return lib[key]
    end})
end
local smaug = require("smaug")
local source = smaug.DataSet({{"name", {"text"}, "string"}})
local baseline = frees
fail_string = true
local ok, message = pcall(function() return source:to_json_mem() end)
assert(not ok and tostring(message):find("falha ao copiar string", 1, true))
assert(frees == baseline + 1, "série parcial não foi liberada exatamente uma vez")
fail_string = false
assert(source:to_json_mem():find("text", 1, true))
local integers = smaug.DataSet({{"id", {9007199254740993LL}, "int64"}})
local integer_baseline = integer_frees
fail_integer = true
ok, message = pcall(function() return integers:to_json_mem() end)
assert(not ok and tostring(message):find("falha ao copiar int64", 1, true))
assert(integer_frees == integer_baseline + 1, "série int64 parcial não liberada")
fail_integer = false
assert(integers:to_json_mem():find("9007199254740993", 1, true))
local Series = require("smaug.core.series")
local original_from_table = Series.from_table
local calls = 0
Series.from_table = function(...)
    calls = calls + 1
    if calls == 2 then error("injected adaptation failure") end
    return original_from_table(...)
end
local table_baseline = table_frees
ok, message = pcall(function() return smaug.read_json_mem('[{"a":1,"b":2}]') end)
Series.from_table = original_from_table
assert(not ok and tostring(message):find("injected adaptation failure", 1, true))
assert(table_frees == table_baseline + 1, "tabela C não liberada após exceção Lua")
collectgarbage("collect")
assert(smaug.read_json_mem('[{"a":1,"b":2}]'):col("b"):get_raw(1) == 2LL)

''')
        run(["luajit", str(cleanup)])
        print("PASS: setters string/int64 e exceção de leitura liberam parciais e recuperam")
        shutil.copytree(ROOT / "lua", work / "lua")
        bridge = work / "lua/smaug/io/csv.lua"
        original_bridge = bridge.read_text()
        tests = [
            ("leitura int64 via number", "vals[r+1] = (st[0] == 0) and v or NA",
             "vals[r+1] = (st[0] == 0) and tonumber(v) or NA",
             ROOT / "tests/io/test_json.lua", "JSON leitura int64 exato"),
            ("escrita int64 via number", "local value = col:get_raw(row)",
             "local value = col:get(row)", ROOT / "tests/io/test_json.lua",
             "JSON escrita int64 exata sem reader"),
            ("tabela C abandonada na adaptação", "    C.smaug_table_free(t)",
             "    -- mutante: tabela abandonada", cleanup,
             "tabela C não liberada após exceção Lua"),
        ]
        run(["luajit", str(ROOT / "tests/io/test_json.lua")], cwd=work)
        for label, original, replacement, test, evidence in tests:
            if original_bridge.count(original) != 1:
                raise RuntimeError(f"Mutação Lua desatualizada: {label}")
            bridge.write_text(original_bridge.replace(original, replacement))
            try:
                result = subprocess.run(["luajit", str(test)], cwd=work,
                                        capture_output=True, text=True, timeout=120)
                if result.returncode == 0 or evidence not in result.stdout + result.stderr:
                    raise RuntimeError(f"Mutante não detectado: {label}\n{result.stderr}")
                print(f"DETECTADO: {label}")
            finally:
                bridge.write_text(original_bridge)
        print("PASS: três mutações da ponte Lua detectadas")


if __name__ == "__main__":
    main()
