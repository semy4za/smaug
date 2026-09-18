"""Lightweight test-style guard. Uses only the Python standard library.

This lexical check catches one-letter identifiers and constructor aliases.
It does not replace compilation, test execution, or a review of name meanings.
Run from any directory: python scripts/check_test_style.py
"""

import re
import sys
from pathlib import Path


def tokenize(source, language):
    """Ignore comments and literal contents, retaining source line numbers."""
    comment = (
        r"--\[(?P<comment_equals>=*)\[.*?\](?P=comment_equals)\]|--[^\n]*"
        if language == "lua" else r"/\*.*?\*/|//[^\n]*"
    )
    patterns = [
        rf"(?P<comment>{comment})",
        r"(?P<string>\[(?P<string_equals>=*)\[.*?\](?P=string_equals)\]|"
        r"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*')",
        r"(?P<number>(?:0[xX][0-9a-fA-F]+(?:\.[0-9a-fA-F]*)?(?:[pP][+-]?\d+)?|"
        r"(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)[uUlLfF]*)",
        r"(?P<identifier>[A-Za-z_]\w*)",
        r"(?P<space>\s+)",
        r"(?P<symbol>->|\.\.|==|~=|!=|<=|>=|.)",
    ]
    expression = re.compile("|".join(patterns), re.DOTALL)
    tokens = []
    line_number = 1
    for match in expression.finditer(source):
        token_kind = match.lastgroup
        token_value = match.group()
        if token_kind not in ("comment", "space"):
            tokens.append((token_kind, token_value, line_number))
        line_number += token_value.count("\n")
    return tokens


def check_source(source, language):
    tokens = tokenize(source, language)
    problems = []
    brace_depth = 0
    for token_index, (token_kind, token_value, line_number) in enumerate(tokens):
        previous_value = tokens[token_index - 1][1] if token_index else ""
        next_value = tokens[token_index + 1][1] if token_index + 1 < len(tokens) else ""
        if token_value == "{":
            brace_depth += 1
        elif token_value == "}":
            brace_depth -= 1
        if token_kind != "identifier":
            continue
        # Public members and literal table keys are not local variable names.
        is_member = previous_value in (".", ":", "->")
        is_table_key = (language == "lua" and brace_depth > 0 and
                        previous_value in ("{", ",", ";") and next_value == "=")
        if len(token_value) == 1 and not is_member and not is_table_key:
            problems.append((line_number, f"one-letter identifier: {token_value}"))
        if language != "lua":
            continue
        if token_value == "from_table" and previous_value == "." and next_value == "(":
            problems.append((line_number, "use smaug.Series() or from_array(), not from_table()"))
        if token_value == "local" and token_index + 5 < len(tokens):
            declaration = [token[1] for token in tokens[token_index:token_index + 7]]
            if (declaration[2:6] in (["=", "smaug", ".", "Series"],
                                     ["=", "smaug", ".", "DataSet"]) and
                    (len(declaration) == 6 or declaration[6] not in ("(", ".", "{"))):
                problems.append((line_number, "do not alias smaug.Series or smaug.DataSet"))
    return problems


def self_test():
    assert check_source("local s = smaug.Series({1})", "lua")
    assert check_source("local Series = smaug.Series\nreturn Series", "lua")
    assert check_source("for i = 1, 3 do print(i) end", "lua")
    assert check_source("local function check(x) return x end", "lua")
    assert check_source("smaug.Series.from_table({1})", "lua")
    assert check_source("#define COMPARE(a, b) ((a) == (b))", "c")
    assert check_source("for (int i = 0; i < 3; i++) {}", "c")
    assert not check_source('local values = {a = 1, b = "x"}; return values.a', "lua")
    assert not check_source('local series = smaug.Series({1, 2}, "int64")', "lua")
    assert not check_source('check(smaug.from_table == nil, "removed")', "lua")
    assert not check_source('-- local s = nil\nlocal value = [=[x]=]', "lua")
    assert not check_source('int64_t value = 9007199254740993LL; /* i */', "c")
    print("OK: style guard self-tests")


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return 0
    project_root = Path(__file__).resolve().parent.parent
    test_paths = sorted(path for path in (project_root / "tests").rglob("*")
                        if path.suffix in (".c", ".lua"))
    failures = 0
    for test_path in test_paths:
        source = test_path.read_text(encoding="utf-8")
        for line_number, message in check_source(source, test_path.suffix[1:]):
            print(f"{test_path.relative_to(project_root)}:{line_number}: {message}")
            failures += 1
    if failures:
        print(f"FAIL: {failures} style violations")
        return 1
    print(f"OK: style guard checked {len(test_paths)} test files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
