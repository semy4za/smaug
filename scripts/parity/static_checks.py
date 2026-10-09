"""Compiled boundary checks and explicitly limited inventories for parity."""

from pathlib import Path
import re

from runner import result

PROTOTYPE = re.compile(
    r"(?P<return>(?:(?:const|unsigned|signed|struct|enum)\s+)*[A-Za-z_]\w*\s*\**\s*)"
    r"(?P<name>smaug_\w+)\s*\((?P<params>[^()]*?)\)\s*;", re.MULTILINE)


def strip_comments(text):
    # Preserve quoted strings, so comment delimiters inside literals are not comments.
    return re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
                  lambda match: " " if match[0].startswith(("/*", "//")) else match[0],
                  text, flags=re.DOTALL)


def cdef_text(root):
    loader = (root / "lua/smaug/ffi_loader.lua").read_text(encoding="utf-8")
    blocks = re.findall(r"ffi\.cdef\(\[\[(.*?)\]\]\)", loader, re.DOTALL)
    if len(blocks) != 1:
        raise ValueError("expected one explicit ffi.cdef block; review new declaration mechanism")
    return strip_comments(blocks[0])


def declarations(text):
    matches = list(PROTOTYPE.finditer(text))
    values = {match["name"]: match.groupdict() for match in matches}
    if not values or len(values) != len(matches):
        raise ValueError("empty or duplicate C declaration inventory")
    references = set(re.findall(r"\b(smaug_\w+)\s*\(", text))
    if references != values.keys():
        raise ValueError("unsupported declarations: " + ", ".join(sorted(references - values.keys())))
    return values


def signatures(audit):
    ffi_declarations = declarations(cdef_text(audit.root))
    public_text = "\n".join(strip_comments(path.read_text(encoding="utf-8"))
                            for path in sorted((audit.root / "include").glob("*.h")))
    public_names = {match["name"] for match in PROTOTYPE.finditer(public_text)}
    source = ['#include "smaug.h"', '#include "smaug_convert.h"']
    rows = []
    for name, declaration in ffi_declarations.items():
        if name not in public_names:
            rows.append(result(3, "header." + name, "FAIL", "FFI symbol declared in headers", name))
            continue
        source.append(f"typedef {declaration['return']} (*parity_{name})({declaration['params']});")
        source.append(f'_Static_assert(__builtin_types_compatible_p(__typeof__(&{name}), '
                      f'parity_{name}), "signature:{name}");')
    probe = audit.directory / "signatures.c"
    probe.write_text("\n".join(source) + "\n", encoding="utf-8")
    compiled = audit.command([audit.compiler, "-std=c11", "-Wall", "-Wextra", "-Wpedantic",
                              "-Werror", "-I" + str(audit.root / "include"), "-fsyntax-only", probe],
                             "signatures", check=False)
    failures = set(re.findall(r'static assertion failed: [^\n]*signature:(smaug_\w+)',
                              compiled["stderr"]))
    if compiled["exit"] != 0 and not failures:
        raise RuntimeError("signature probe failed without a classified mismatch: " + compiled["stderr"])
    # Compiler may report independent errors alongside a static assertion failure.
    unclassified = [line for line in compiled["stderr"].splitlines()
                    if "error:" in line and "static assertion failed:" not in line]
    if unclassified:
        raise RuntimeError("unclassified signature diagnostics: " + "\n".join(unclassified))
    for name in sorted(ffi_declarations.keys() & public_names):
        rows.append(result(3, "signature." + name, "FAIL" if name in failures else "PASS",
                           "Compiler type compatibility: C prototype versus FFI declaration", name,
                           "GCC target ABI; does not prove semantic behavior"))
    for name in sorted(public_names - ffi_declarations.keys()):
        rows.append(result(3, "c-only." + name, "OBSERVED", "Header symbol without FFI declaration", name,
                           "C mechanisms need not all be exposed directly in Lua"))
    symbols = audit.directory / "symbols.txt"
    symbols.write_text("\n".join(sorted(ffi_declarations)) + "\n", encoding="utf-8")
    rows.extend(audit.runtime(3, symbols))
    return rows


def struct_fields(text):
    structures = {}
    for match in re.finditer(r"typedef\s+struct\s*(?:\w+\s*)?\{([^{}]*)\}\s*(\w+)\s*;",
                             text, re.DOTALL):
        body, name = match.groups()
        fields = []
        for declaration in body.split(";"):
            declaration = declaration.strip()
            if not declaration:
                continue
            field = re.search(r"\b([A-Za-z_]\w*)\s*$", declaration)
            if not field or any(character in declaration for character in "[]():,"):
                raise ValueError(f"unsupported field syntax in {name}: {declaration}")
            fields.append(field[1])
        if not fields or name in structures:
            raise ValueError("empty or duplicate struct: " + name)
        structures[name] = fields
    count = len(re.findall(r"typedef\s+struct\s*(?:\w+\s*)?\{", text))
    if count != len(structures) or not structures:
        raise ValueError("incomplete struct inventory; nested/union declarations need explicit support")
    return structures


def layouts(audit):
    structures = struct_fields(cdef_text(audit.root))
    source = ['#include "smaug.h"', '#include <stddef.h>', '#include <stdio.h>', 'int main(void) {']
    for name, fields in sorted(structures.items()):
        source.append(f'    printf("size {name} - %zu\\n", sizeof({name}));')
        source.append(f'    printf("align {name} - %zu\\n", _Alignof({name}));')
        for field in fields:
            source.append(f'    printf("offset {name} {field} %zu\\n", offsetof({name}, {field}));')
    source += ["    return 0;", "}"]
    probe = audit.directory / "layout.c"
    probe.write_text("\n".join(source) + "\n", encoding="utf-8")
    executable = audit.directory / ("layout.exe" if audit.library.suffix == ".dll" else "layout")
    audit.command([audit.compiler, "-std=c11", "-Wall", "-Wextra", "-Wpedantic", "-Werror",
                   "-I" + str(audit.root / "include"), probe, "-o", executable], "compile-layout")
    measurements = audit.command([executable], "measure-layout")["stdout"]
    expected_count = sum(2 + len(fields) for fields in structures.values())
    if len(measurements.splitlines()) != expected_count:
        raise ValueError("partial C layout output")
    data = audit.directory / "layout.txt"
    data.write_text(measurements, encoding="utf-8")
    rows = audit.runtime(15, data)
    rows.append(result(15, "inventory", "OBSERVED", "Every non-opaque struct in the cdef measured",
                       ", ".join(sorted(structures)),
                       "Includes f64/i64; sizes, alignments and every declared field offset"))
    return rows


def quoted_test_names(text, suffix):
    return set(re.findall(r'["\']((?:[a-z_]+/)?test_[a-z_]+)' + re.escape(suffix) + r'["\']', text))


def test_inventory(root):
    c_files = sorted((root / "tests/c").glob("test_*.c"))
    lua_files = sorted((root / "tests").glob("*/*.lua"))
    if not c_files or not lua_files:
        raise ValueError("empty test inventory")
    rows = []
    for path in c_files + lua_files:
        category = ("wrap" if path.stem == "test_allocfail" else
                    "stress" if path.stem == "test_stress" else "plain")
        language = "C" if path.suffix == ".c" else "Lua"
        relative = path.relative_to(root).as_posix()
        rows.append(result(11, relative, "OBSERVED", f"{language} test file, category={category}", relative,
                           "File inventory is not executed checks, coverage or detection strength"))
    windows = (root / "scripts/build.ps1").read_text(encoding="utf-8")
    linux = (root / "scripts/build.sh").read_text(encoding="utf-8")
    expected_c = {path.stem for path in c_files}
    expected_lua = {path.relative_to(root / "tests").with_suffix("").as_posix() for path in lua_files}
    for name, text in (("Windows", windows), ("Linux", linux)):
        candidates = set(re.findall(r"\b(?:[a-z_]+/)?test_[a-z_]+\b", strip_comments(text)))
        for kind, expected in (("C", expected_c), ("Lua", expected_lua)):
            missing = sorted(expected - candidates)
            rows.append(result(11, name + "." + kind, "FAIL" if missing else "PASS",
                               "Build script enumerates discovered tests",
                               "missing: " + ", ".join(missing) if missing else f"{len(expected)} paths found",
                               "Static list comparison; does not prove that commands execute"))
    rows.append(result(11, "coverage", "REVIEW", "Coverage and mutation evidence",
                       "Family tests and separate coverage/mutation commands remain necessary",
                       "No counts of dtype strings or check() tokens are called coverage"))
    return rows


def documentation(root, inventory):
    text = (root / "docs/API_INDEX.md").read_text(encoding="utf-8")
    rows = [row for row in inventory if row["id"] == "library"]
    for row in inventory:
        if row["id"] == "library" or "." not in row["id"]:
            continue
        group, method = row["id"].split(".", 1)
        pattern = r"(?<![\w])" + re.escape(method) + r"\s*(?:\(|`)"
        matches = [index for index, line in enumerate(text.splitlines(), 1) if re.search(pattern, line)]
        rows.append(result(12, row["id"], "OBSERVED" if matches else "REVIEW",
                           "Documentation token for " + group + ":" + method,
                           "docs/API_INDEX.md:" + ",".join(map(str, matches)) if matches else "No token found",
                           "Token occurrence is not signature/contract agreement or proof of class scope"))
    rows.append(result(12, "semantics", "REVIEW", "Documentation agrees with contracts",
                       "Runtime inventory complete for the seven enumerated object families",
                       "Names are indexed, not certified; semantic documentation review remains manual"))
    return rows


def file_scope_declarations(text):
    """Extract top-level declarations; includes indented and external storage.

    This is a candidate inventory, not a proof of reentrancy. Initializers and
    declarations with function-pointer syntax remain candidates for review.
    """
    text = strip_comments(text)
    text = re.sub(r'^\s*#.*(?:\\\n.*)*', '', text, flags=re.MULTILINE)
    text = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '""', text)
    declarations, current = [], []
    depth = 0
    function_body = False
    for character in text:
        if character == "{" and depth == 0:
            prefix = "".join(current).strip()
            function_body = prefix.endswith(")") and "=" not in prefix
        if character == "{":
            depth += 1
        if not function_body:
            current.append(character)
        if character == "}":
            depth -= 1
            if depth < 0:
                declarations.append("<unbalanced lexical scope: manual review required>")
                depth = 0
            if depth == 0 and function_body:
                current = []
                function_body = False
        if character == ";" and depth == 0:
            declaration = " ".join("".join(current).split())
            current = []
            if declaration and not declaration.startswith("typedef "):
                # Plain prototypes carry no object storage. Function pointers do.
                if "(" in declaration and "=" not in declaration and "(*" not in declaration:
                    continue
                declarations.append(declaration)
    if depth:
        # Preprocessor branches and initializer macros can defeat this lexical
        # scanner. Keep the axis reviewable instead of turning an incomplete
        # candidate inventory into a false PASS or infrastructure crash.
        declarations.append("<unbalanced lexical scope: manual review required>")
    return declarations


def shared_state(audit):
    rows = []
    sources = sorted((audit.root / "src").glob("*.c"))
    if not sources:
        raise ValueError("empty source inventory")
    for path in sources:
        candidates = file_scope_declarations(path.read_text(encoding="utf-8"))
        rows.append(result(14, path.name, "REVIEW" if candidates else "OBSERVED",
                           "File-scope object candidates, including non-static storage",
                           "\n".join(candidates) if candidates else "No candidate in this lexical inventory",
                           "Includes all src/*.c; const/pointer mutability and macro expansion need review"))
    rows.append(result(14, "reentrancy", "REVIEW", "Reentrancy and concurrency",
                       "No concurrent execution or race detector was run by this axis",
                       "Absence of lexical candidates never certifies thread safety"))
    return rows
