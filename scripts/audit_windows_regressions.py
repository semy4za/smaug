"""Windows/UCRT: build completo, consumidores da DLL e mutacoes numericas reais.

Usa apenas a biblioteca padrao. Logs e hashes ficam em build/windows-regressions.
Falha de compilacao, timeout, zero checks ou crash nao contam como deteccao.
Nao substitui a campanha Linux/Valgrind nem a instrumentacao ASan/UBSan.
"""

import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build/windows-regressions"
C_TESTS = ("test_astype", "test_io_c", "test_schema")
LUA_TESTS = ("series/test_constructors", "io/test_csv", "io/test_json", "io/test_schema")
FLAGS = ["-std=c11", "-O2", "-Wall", "-Wextra", "-Wpedantic", "-Werror"]
MUTATIONS = (
    ("hex_uses_ucrt", "return parse_hex_f64(text, output);", "(void)parse_hex_f64;"),
    ("hex_loses_sticky", "sticky = sticky || bit != 0;", "sticky = sticky;"),
    ("hex_loses_sign", "*output = negative ? -value : value;", "*output = value;"),
    ("decimal_ignores_fix", "parsed_value = negative ? -DBL_TRUE_MIN : DBL_TRUE_MIN;",
     "return SMG_ERR_UNDERFLOW;"),
    ("decimal_loses_sign", "parsed_value = negative ? -DBL_TRUE_MIN : DBL_TRUE_MIN;",
     "parsed_value = DBL_TRUE_MIN;"),
    ("decimal_swaps_modes",
     "(rounding == FE_UPWARD && !negative) ||\n            (rounding == FE_DOWNWARD && negative)",
     "(rounding == FE_DOWNWARD && !negative) ||\n            (rounding == FE_UPWARD && negative)"),
    ("decimal_confuses_zero", "if (!special && parsed_value == 0.0 && lexical_nonzero) {",
     "if (!special && parsed_value == 0.0) {"),
)

# O endereco vem do namespace usado pelo frontend; GetModuleHandleExA identifica
# o modulo que realmente contem esse simbolo, sem presumir a escolha do loader.
LUA_HARNESS = r'''
package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local ffi = require("ffi")
local library = require("smaug.ffi_loader")
ffi.cdef[[
    int __stdcall GetModuleHandleExA(unsigned long flags, const char *address, void **module);
    unsigned long __stdcall GetModuleFileNameA(void *module, char *filename, unsigned long size);
]]
local kernel = ffi.load("kernel32")
local module = ffi.new("void *[1]")
assert(kernel.GetModuleHandleExA(6, ffi.cast("const char *", library.smaug_abi_version), module) ~= 0)
local path = ffi.new("char[32768]")
local length = kernel.GetModuleFileNameA(module[0], path, 32768)
assert(length > 0 and length < 32768)
print("AUDIT_LIBRARY: " .. ffi.string(path, length))
assert(library.smaug_abi_version() == 1)
dofile(arg[1])
'''


def valid_summary(output, language="c"):
    lines = output.strip().splitlines()
    if not lines:
        return False
    expression = (r"PASS: .+\(([1-9][0-9]*) checks\)" if language == "c"
                  else r"OK .+ ([1-9][0-9]*) checks passaram .+")
    return re.fullmatch(expression, lines[-1]) is not None


def check_summary_guard():
    for invalid in ("", "PASS", "PASS: test (0 checks)", "PASS: test (2 checks)\nFAIL"):
        if valid_summary(invalid):
            raise RuntimeError("Summary guard accepted invalid output")
    if not valid_summary("SKIP: platform\nPASS: test (2 checks)"):
        raise RuntimeError("Summary guard rejected valid final summary")


def execute(command, label, timeout=180):
    result = subprocess.run([str(part) for part in command], cwd=ROOT,
                            capture_output=True, timeout=timeout)
    # Windows PowerShell emits OEM/ANSI text under redirection; diagnostics are
    # retained even if a non-ASCII character cannot be decoded as UTF-8.
    stdout = result.stdout.decode("utf-8", errors="replace")
    stderr = result.stderr.decode("utf-8", errors="replace")
    (OUTPUT / f"{label}.log").write_text(
        json.dumps([str(part) for part in command]) + f"\nEXIT: {result.returncode}\n"
        + stdout + "\nSTDERR:\n" + stderr, encoding="utf-8")
    return result.returncode, stdout, stderr


def require_success(command, label, language=None, timeout=180):
    code, stdout, stderr = execute(command, label, timeout)
    if code != 0 or (language and not valid_summary(stdout, language)):
        raise RuntimeError(f"{label} failed (exit {code}); see {OUTPUT / (label + '.log')}\n"
                           + stdout[-1500:] + stderr[-1500:])
    return stdout


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes():
    paths = []
    for directory in ("src", "include", "lua", "tests", "scripts"):
        paths.extend(path for path in (ROOT / directory).rglob("*")
                     if path.suffix in (".c", ".h", ".lua", ".ps1", ".py"))
    return {path.relative_to(ROOT).as_posix(): digest(path) for path in sorted(paths)}


def compile_test(compiler, test_name, executable, label, sources=None):
    command = [compiler, *FLAGS, f"-I{ROOT / 'include'}", ROOT / "tests/c" / f"{test_name}.c"]
    command += sources if sources is not None else [ROOT / "build/smaug.dll"]
    require_success([*command, "-lm", "-o", executable], label)


def audit(report):
    if os.name != "nt":
        raise RuntimeError("This audit requires native Windows and MSYS2 UCRT64")
    check_summary_guard()
    compiler = shutil.which("gcc")
    luajit = shutil.which("luajit")
    powershell = shutil.which("powershell")
    if not all((compiler, luajit, powershell)):
        raise RuntimeError("GCC, LuaJIT and Windows PowerShell are required; no silent skips")
    report["platform"] = platform.platform()
    report["utc"] = datetime.now(timezone.utc).isoformat()
    report["compiler"] = require_success([compiler, "--version"], "compiler").splitlines()[0]
    macros = require_success([compiler, "-dM", "-E", "-include", "_mingw.h", "-x", "c",
                              ROOT / "include/smaug_convert.h"], "compiler-macros")
    if not re.search(r"^#define _UCRT\b", macros, re.MULTILINE) or not re.search(
            r"^#define _WIN64\b", macros, re.MULTILINE):
        raise RuntimeError("Compiler must target Windows x64 UCRT")
    report["target"] = require_success([compiler, "-dumpmachine"], "compiler-target").strip()
    report["ucrt64"] = True
    report["luajit"] = require_success([luajit, "-v"], "luajit").strip()
    report["head"] = require_success(["git", "rev-parse", "HEAD"], "head").strip()
    report["worktree"] = require_success(["git", "status", "--short"], "status").splitlines()
    report["input_sha256"] = source_hashes()
    report["strict_flags"] = FLAGS
    full_output = require_success(
        [powershell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         ROOT / "scripts/build.ps1", "-SkipManifest"], "full-build", timeout=600)
    c_names = re.findall(r"^(test_\w+)\s+->", full_output, re.MULTILINE)
    expected_c = {path.stem for path in (ROOT / "tests/c").glob("test_*.c")}
    lua_count = len(re.findall(r"^OK (?!->).+", full_output, re.MULTILINE))
    expected_lua_count = len(list((ROOT / "tests").glob("*/*.lua")))
    if set(c_names) != expected_c or len(c_names) != len(expected_c):
        raise RuntimeError("Full build C inventory is incomplete or duplicated")
    c_summaries = re.findall(r"PASS: [^\r\n]*\(([1-9][0-9]*) (?:checks|verifica[^\s)]*)\)",
                             full_output)
    if len(c_summaries) != len(expected_c):
        raise RuntimeError("Full build C summaries are missing or contain zero checks")
    if lua_count != expected_lua_count or "TUDO PASSOU." not in full_output:
        raise RuntimeError("Full build Lua inventory is incomplete or final result is absent")
    report["full_build"] = {"c_executables": c_names, "lua_suites": lua_count,
                            "skips": [line for line in full_output.splitlines() if "SKIP" in line]}
    dll = ROOT / "build/smaug.dll"
    report["dll"] = {"path": str(dll), "sha256": digest(dll)}
    report["baselines"] = {}
    sources = sorted((ROOT / "src").glob("*.c"))
    for test_name in C_TESTS:
        for shared in (False, True):
            label = f"{test_name}-{'dll' if shared else 'direct'}"
            executable = ROOT / "build" / f"audit-{label}.exe"
            compile_test(compiler, test_name, executable, f"compile-{label}",
                         None if shared else sources)
            stdout = require_success([executable], label, "c")
            report["baselines"][label] = stdout.strip().splitlines()[-1]
            print(f"BASELINE {label}: {stdout.strip().splitlines()[-1]}", flush=True)
    with tempfile.TemporaryDirectory(prefix="smaug-windows-") as temporary:
        directory = Path(temporary)
        harness = directory / "check_dll.lua"
        harness.write_text(LUA_HARNESS, encoding="utf-8")
        for test_name in LUA_TESTS:
            label = "lua-" + test_name.replace("/", "-")
            stdout = require_success([luajit, harness, ROOT / "tests" / (test_name + ".lua")],
                                     label, "lua")
            paths = re.findall(r"^AUDIT_LIBRARY: (.+)$", stdout, re.MULTILINE)
            if len(paths) != 1 or Path(paths[0].strip()).resolve() != dll.resolve():
                raise RuntimeError(f"Unexpected DLL loaded by {test_name}: {paths}")
            report["baselines"][label] = stdout.strip().splitlines()[-1]
            print(f"BASELINE {label}: DLL path confirmed", flush=True)
        report["mutations"] = []
        original = (ROOT / "src/smaug_convert.c").read_text(encoding="utf-8")
        mutated_source = directory / "smaug_convert.c"
        for name, old, new in MUTATIONS:
            if original.count(old) != 1:
                raise RuntimeError(f"Stale mutation: {name}")
            mutated_source.write_text(original.replace(old, new), encoding="utf-8")
            mutated_sources = [mutated_source if path.name == "smaug_convert.c" else path
                               for path in sources]
            detected_by = []
            for test_name in ("test_io_c", "test_astype"):
                label = f"mutant-{name}-{test_name}"
                executable = directory / f"{label}.exe"
                compile_test(compiler, test_name, executable, f"compile-{label}", mutated_sources)
                code, stdout, stderr = execute([executable], label)
                evidence = ("rounding consumer:" if test_name == "test_io_c" else "FALHOU:")
                if code != 1 or evidence not in stderr or valid_summary(stdout):
                    raise RuntimeError(f"Mutation survived or failed for unrelated reason: {label}")
                detected_by.append(test_name)
            report["mutations"].append({"name": name, "detected_by": detected_by})
            print(f"DETECTED {name}: I/O and astype", flush=True)
    if digest(dll) != report["dll"]["sha256"] or source_hashes() != report["input_sha256"]:
        raise RuntimeError("Inputs or DLL changed during audit")
    report["limitations"] = ["No ASan/UBSan or Valgrind in this audit",
                              "Parity output is informational, not an acceptance gate",
                              "Lua regressions use nearest; C consumers exercise all four modes"]
    report["status"] = "PASS"


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "report.json").write_text('{"status": "RUNNING"}\n', encoding="utf-8")
    report = {"status": "FAILED"}
    try:
        audit(report)
    except (OSError, RuntimeError, subprocess.TimeoutExpired) as error:
        report["error"] = str(error)
        raise
    finally:
        (OUTPUT / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: Windows regression audit; evidence in {OUTPUT}")


if __name__ == "__main__":
    main()
