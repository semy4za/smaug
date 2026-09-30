#!/usr/bin/env python3
"""Verifica mutações numéricas e de I/O em cópias temporárias, sem alterar a árvore.

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
              ("malloc", "calloc", "realloc", "strdup", "newlocale", "uselocale", "fclose")]
MUTATIONS = [
    ("schema CSV ignores nullable", "smaug_csv.c", "test_schema",
     "if (!descriptor->nullable) {", "if (0) {", "non-nullable"),
    ("schema JSON ignores nullable", "smaug_json.c", "test_schema",
     "if (!descriptor->nullable) {", "if (0) {", "non-nullable"),
    ("schema JSON accepts duplicate keys", "smaug_json.c", "test_schema",
     "if (record->vals[previous].column_index == field) {", "if (0) {", "duplicate"),
    ("schema JSON loses integer precision", "smaug_json.c", "test_schema",
     "if (!json_integer_exact_in_double(value->i)) {", "if (0) {", "PRECISION"),
    ("schema ignores duplicate names", "smaug_schema.c", "test_schema",
     "field->name_len == other->name_len &&", "0 &&", "duplicate schema name rejected"),
    ("schema CSV loses NUL in strings", "smaug_csv.c", "test_schema",
     "smaug_str_set(column->str, row, text->data, text->length)",
     "smaug_str_set(column->str, row, text->data, strlen(text->data))",
     "schema CSV preserves NUL bytes"),
    ("schema JSON rejects exact large integers", "smaug_json.c", "test_schema",
     "if (!json_integer_exact_in_double(value->i)) {",
     "if (value->i > INT64_C(9007199254740992)) {", "schema valid input succeeds"),
    ("schema JSON drops empty columns", "smaug_json.c", "test_schema",
     "smaug_table_t *table = smaug_io_schema_table(schema, row_count);",
     "if (row_count == 0) return calloc(1, sizeof(smaug_table_t));\n"
     "    smaug_table_t *table = smaug_io_schema_table(schema, row_count);",
     "schema determines shape"),
    ("JSON reader skips UTF8 validation", "smaug_json.c", "test_io_c",
     "size_t width = json_utf8_sequence_length(l->buf + start, l->len - start);",
     "size_t width = 1;", "JSON reader rejects invalid UTF8 value at byte"),
    ("JSON accepts overlong three byte UTF8", "smaug_json.c", "test_io_c",
     "second_min = 0xa0;", "second_min = 0x80;",
     "JSON reader rejects invalid UTF8 value at byte"),
    ("JSON accepts UTF8 surrogate", "smaug_json.c", "test_io_c",
     "second_max = 0x9f;", "second_max = 0xbf;",
     "JSON reader rejects invalid UTF8 value at byte"),
    ("JSON writer skips UTF8 name", "smaug_json.c", "test_io_c",
     "if (!json_valid_utf8(source->name, source->name_len, &invalid_byte)) {", "if (0) {",
     "JSON writer validates UTF8 names even without rows"),
    ("JSON writer skips UTF8 value", "smaug_json.c", "test_io_c",
     "if (value && !json_valid_utf8(value, length, &invalid_byte)) {", "if (0) {",
     "JSON writer rejects invalid UTF8 value without output"),
    ("JSON rejects initial BOM", "smaug_json.c", "test_io_c",
     "initial_position = 3;", "initial_position = 0;",
     "JSON BOM: leitura aceita um BOM inicial"),
    ("CSV keeps initial BOM in name", "smaug_csv.c", "test_io_c",
     "position = 3;", "position = 0;",
     "CSV BOM: BOM não vira parte do nome"),
    ("CSV accepts irregular row width", "smaug_csv.c", "test_io_c",
     "if (row_sizes[row_index] != column_count) {", "if (0) {",
     "linha curta: erro de largura"),
    ("CSV accepts bare CR", "smaug_csv.c", "test_io_c",
     "if (i + 1 >= len || buf[i + 1] != '\\n') {", "if (0) {",
     "CR only: erro estrutural"),
    ("CSV accepts unclosed quote", "smaug_csv.c", "test_io_c",
     "if (!closed) {", "if (0) {",
     "aspas não fechadas: diagnóstico"),
    ("CSV accepts trailing quote text", "smaug_csv.c", "test_io_c",
     "if (i < len && buf[i] != sep && buf[i] != '\\n' && buf[i] != '\\r') {",
     "if (0) {", "aspas: texto após fechamento é erro"),

    ("CSV marker loses explicit length", "smaug_csv.c", "test_io_c",
     "na_values ? na_lengths[index] : strlen(nav[index])", "strlen(nav[index])",
     "CSV marker compares all bytes and length"),

    ("JSON string truncates at NUL", "smaug_json.c", "test_io_c",
     "v->s, v->string_length", "v->s, strlen(v->s)", "NUL value bytes and length"),
    ("CSV string truncates at NUL", "smaug_csv.c", "test_io_c",
     "smaug_str_set(series, row_index, text, text_length)",
     "smaug_str_set(series, row_index, text, strlen(text))", "NUL value bytes and length"),
    ("JSON writer truncates NUL name", "smaug_json.c", "test_io_c",
     "write_json_string(&b, n, t->columns[c].name_len)",
     "write_json_string(&b, n, strlen(n))", "JSON writer escapes NUL name"),

    ("JSON reads values by position", "smaug_json.c", "test_io_c",
     "if (record->vals[field].column_index == column) {", "if (field == column) {",
     "JSON values and NA follow original name and occurrence"),
    ("JSON merges duplicate occurrences", "smaug_json.c", "test_io_c",
     "identities[column].occurrence == occurrence &&", "1 &&",
     "JSON named union includes fields after empty first row"),
    ("JSON schema ignores later rows", "smaug_json.c", "test_io_c",
     "size_t count = 0;\n    for (size_t row = 0; row < row_count; row++) {",
     "size_t count = 0;\n    for (size_t row = 0; row < row_count; row++) { if (row != 0) break;",
     "JSON named union includes fields after empty first row"),

    ("JSON integer promotion loses precision", "smaug_json.c", "test_io_c",
     "dtypes[column] == DT_F64 && value->type == 1 &&\n                !json_integer_exact_in_double(value->i)",
     "0", "JSON numeric reason and byte"),
    ("JSON truncates numeric token", "smaug_json.c", "test_io_c",
     "size_t length = lexer->pos - start;",
     "size_t length = lexer->pos - start; if (length > 63) { length = 63; }",
     "JSON long number consumes exponent"),
    ("JSON accepts leading zero", "smaug_json.c", "test_io_c",
     "if (lexer->buf[lexer->pos] == '0') {", "if (0) {",
     "JSON numeric reason and byte"),
    ("JSON ignores range failure", "smaug_json.c", "test_io_c",
     'case SMG_ERR_OVERFLOW: lexer->error_reason = "OVERFLOW numérico"; break;',
     'case SMG_ERR_OVERFLOW: return TOK_NUMBER;', "JSON numeric reason and byte"),

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
    for filename in ("smaug_convert.c", "smaug_astype.c", "smaug_csv.c", "smaug_json.c",
                     "smaug_schema.c", "smaug_io_schema.c"):
        digest = hashlib.sha256((ROOT / "src" / filename).read_bytes()).hexdigest()
        print(f"{filename}: {digest}", flush=True)
    with tempfile.TemporaryDirectory(prefix="smaug-r1-mutations-") as temporary:
        directory = Path(temporary)
        shutil.copytree(ROOT / "src", directory / "src")
        shutil.copytree(ROOT / "include", directory / "include")
        for test_name in ("test_astype", "test_allocfail", "test_io_c", "test_schema"):
            memory = test_name != "test_astype"
            result = execute(compile_test(directory, test_name), memory=memory)
            if result.returncode:
                raise RuntimeError(f"Baseline inválida: {result.stdout}\n{result.stderr}")
            profile = "Valgrind" if memory else "nativo (modos de arredondamento)"
            print(f"BASELINE: {test_name}, {profile} aprovado", flush=True)
        for name, filename, test_name, original, replacement, evidence in MUTATIONS:
            source = directory / "src" / filename
            original_text = source.read_text()
            expected_count = 2 if filename == "smaug_astype.c" or name == "CSV accepts bare CR" else 1
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
