#!/usr/bin/env python3
"""Verifica mutações de R1 em cópias temporárias, sem alterar a árvore.

Linux/GCC: exige Valgrind para os mutantes de ownership. Uma falha de build
não conta como detecção. Baselines precisam passar antes de qualquer mutação.
"""

import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
WRAP_FLAGS = [f"-Wl,--wrap={name}" for name in
              ("malloc", "calloc", "realloc", "strdup", "newlocale", "uselocale")]
MUTATIONS = [
    ("overflow antes do sufixo", "smaug_convert.c", "test_astype",
     "overflow = true;", "return SMG_ERR_OVERFLOW;", "sintaxe integral"),
    ("ERANGE finito ignorado", "smaug_convert.c", "test_astype",
     "(parse_errno == ERANGE && fabs(parsed_value) == DBL_MAX)", "0",
     "overflow dirigido"),
    ("OOM de astype vira NA", "smaug_astype.c", "test_allocfail",
     "parse_status != SMG_ERR_UNDERFLOW) {",
     "parse_status != SMG_ERR_UNDERFLOW && parse_status != SMG_ERR_NOMEM) {",
     "astype propaga cada OOM"),
    ("OOM na inferência vira texto", "smaug_csv.c", "test_allocfail",
     "status == SMG_ERR_NOMEM || status == SMG_ERR_ARGUMENT",
     "status == SMG_ERR_ARGUMENT", "CSV propaga locale OOM"),
    ("rollback usa ponteiro anterior", "smaug_csv.c", "test_allocfail",
     "rows = resized_rows;", "/* mutante: perde o buffer movido */",
     "Invalid"),
    ("falha no setter de string ignorada", "smaug_csv.c", "test_allocfail",
     "if (status != 0) {", "if (0) {", "CSV string longa: setter OOM"),
    ("formatter usa locale externo", "smaug_convert.c", "test_astype",
     "locale_t previous_locale = uselocale(numeric_locale);",
     "locale_t previous_locale = uselocale((locale_t)0);",
     "formatter usa ponto"),
    ("formatter anuncia sucesso truncado", "smaug_convert.c", "test_astype",
     "if (!buffer || length <= 0 || (size_t)length >= capacity) {\n        return 0;",
     "if (!buffer || length <= 0 || (size_t)length >= capacity) {\n        return (size_t)length;",
     "formatter buffer curto"),
    ("astype ignora falha de formatação", "smaug_astype.c", "test_allocfail",
     "if (formatted_length == 0) {", "if (0) {",
     "astype saída não transforma formatter OOM"),
]


def run(command, timeout=120):
    return subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=timeout)


def compile_test(directory, test_name):
    executable = directory / test_name
    command = ["gcc", "-std=c11", "-g", "-O0", "-Wall", "-Wextra",
               f"-I{directory / 'include'}"]
    if test_name == "test_allocfail":
        command += WRAP_FLAGS
    command += [str(ROOT / "tests/c" / f"{test_name}.c")]
    command += [str(source) for source in sorted((directory / "src").glob("*.c"))]
    result = run(command + ["-lm", "-o", str(executable)])
    if result.returncode:
        raise RuntimeError(f"Build inválido; não conta como detecção:\n{result.stderr}")
    return executable


def execute(executable, memory=False):
    command = [str(executable)]
    if memory:
        command = ["valgrind", "--error-exitcode=99", "--leak-check=full",
                   "--errors-for-leak-kinds=definite,indirect"] + command
    return run(command)


def main():
    if not shutil.which("gcc") or not shutil.which("valgrind"):
        raise SystemExit("GCC e Valgrind são obrigatórios; auditoria não executada.")
    print(run(["gcc", "--version"]).stdout.splitlines()[0], flush=True)
    for filename in ("smaug_convert.c", "smaug_astype.c", "smaug_csv.c"):
        digest = hashlib.sha256((ROOT / "src" / filename).read_bytes()).hexdigest()
        print(f"{filename}: {digest}", flush=True)
    with tempfile.TemporaryDirectory(prefix="smaug-r1-mutations-") as temporary:
        directory = Path(temporary)
        shutil.copytree(ROOT / "src", directory / "src")
        shutil.copytree(ROOT / "include", directory / "include")
        for test_name in ("test_astype", "test_allocfail"):
            memory = test_name == "test_allocfail"
            result = execute(compile_test(directory, test_name), memory=memory)
            if result.returncode:
                raise RuntimeError(f"Baseline inválida: {result.stdout}\n{result.stderr}")
            profile = "Valgrind" if memory else "nativo (modos de arredondamento)"
            print(f"BASELINE: {test_name}, {profile} aprovado", flush=True)
        for name, filename, test_name, original, replacement, evidence in MUTATIONS:
            source = directory / "src" / filename
            original_text = source.read_text()
            expected_count = 2 if filename == "smaug_astype.c" else 1
            if original_text.count(original) != expected_count:
                raise RuntimeError(f"Mutação desatualizada: {name}")
            source.write_text(original_text.replace(original, replacement))
            try:
                executable = compile_test(directory, test_name)
                result = execute(executable, memory=(evidence == "Invalid"))
                output = result.stdout + result.stderr
                if result.returncode == 0 or evidence not in output:
                    raise RuntimeError(f"Mutante não detectado pelo motivo esperado: {name}\n{output}")
                print(f"DETECTADO: {name}", flush=True)
            finally:
                source.write_text(original_text)
    print(f"PASS: {len(MUTATIONS)} mutantes compiláveis detectados; nenhum sobrevivente.")


if __name__ == "__main__":
    main()
