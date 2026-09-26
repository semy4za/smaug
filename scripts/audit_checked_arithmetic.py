"""Check int64 helpers against Python integers and five compilable mutations.

Run from the repository: python3 scripts/audit_checked_arithmetic.py
Uses a temporary source snapshot; never modifies production sources or build/.
This is a bounded arithmetic audit, not proof of all inputs or of absence of UB.
"""
import ctypes
import hashlib
import itertools
from pathlib import Path
import random
import shutil
import subprocess
import tempfile


MINIMUM = -(1 << 63)
MAXIMUM = (1 << 63) - 1
SENTINEL = 79225
ROOT = Path(__file__).resolve().parents[1]


def expected_result(operation, left, right):
    if operation == "add":
        result = left + right
    elif operation == "sub":
        result = left - right
    elif operation == "mul":
        result = left * right
    else:
        if right == 0:
            return False, SENTINEL
        magnitude = abs(left) // abs(right)
        result = -magnitude if (left < 0) != (right < 0) else magnitude
    return (True, result) if MINIMUM <= result <= MAXIMUM else (False, SENTINEL)


def input_pairs():
    boundaries = {MINIMUM, MINIMUM + 1, MAXIMUM - 1, MAXIMUM, -1, 0, 1}
    for exponent in (1, 15, 31, 32, 53, 62):
        for offset in (-1, 0, 1):
            boundaries.add((1 << exponent) + offset)
            boundaries.add(-((1 << exponent) + offset))
    pairs = list(itertools.product(sorted(boundaries), repeat=2))
    # Products immediately around a representability boundary, independent
    # of the implementation's sign-case guards.
    for divisor in sorted(boundaries):
        if divisor:
            for limit in (MINIMUM, MAXIMUM):
                quotient = limit // divisor
                for offset in (-1, 0, 1):
                    candidate = quotient + offset
                    if MINIMUM <= candidate <= MAXIMUM:
                        pairs.append((candidate, divisor))
    generator = random.Random(20260926)
    pairs.extend((generator.randint(MINIMUM, MAXIMUM), generator.randint(MINIMUM, MAXIMUM))
                 for unused_index in range(2048))
    return list(dict.fromkeys(pairs))


def check_library(path, pairs):
    library = ctypes.CDLL(str(path))
    calls = 0
    for operation in ("add", "sub", "mul", "div"):
        function = getattr(library, "smaug_i64_" + operation + "_checked")
        function.argtypes = [ctypes.c_int64, ctypes.c_int64, ctypes.POINTER(ctypes.c_int64)]
        function.restype = ctypes.c_bool
        for left, right in pairs:
            expected_status, expected_value = expected_result(operation, left, right)
            output = ctypes.c_int64(SENTINEL)
            status = function(left, right, ctypes.byref(output))
            calls += 1
            if (status, output.value) != (expected_status, expected_value):
                return calls, (f"{operation}({left}, {right}): "
                               f"got {(status, output.value)}, expected {(expected_status, expected_value)}")
            status_without_output = function(left, right, None)
            calls += 1
            if status_without_output != expected_status:
                return calls, f"{operation}({left}, {right}, NULL): wrong status"
    return calls, None


def main():
    source = (ROOT / "src/smaug_core.c").read_text()
    print("core sha256:", hashlib.sha256(source.encode()).hexdigest(), flush=True)
    print(subprocess.check_output(["gcc", "--version"], text=True).splitlines()[0], flush=True)
    pairs = input_pairs()
    mutations = [
        ("add_rejects_boundary", "a > INT64_MAX - b", "a >= INT64_MAX - b"),
        ("sub_rejects_boundary", "a < INT64_MIN + b", "a <= INT64_MIN + b"),
        ("mul_rejects_boundary", "a > INT64_MAX / b", "a >= INT64_MAX / b"),
        ("div_rejects_one", "if (b == 0 || (a == INT64_MIN && b == -1))",
         "if (b == 0 || b == 1 || (a == INT64_MIN && b == -1))"),
        ("add_writes_on_failure", "(b < 0 && a < INT64_MIN - b)) return false;",
         "(b < 0 && a < INT64_MIN - b)) { if (out) *out = 0; return false; }"),
    ]
    with tempfile.TemporaryDirectory(prefix="smaug-arithmetic-") as directory:
        workspace = Path(directory)
        (workspace / "src").mkdir()
        shutil.copytree(ROOT / "include", workspace / "include")
        variants = [("baseline", source)]
        for name, before, after in mutations:
            if source.count(before) != 1:
                raise RuntimeError(f"Mutation {name} does not identify exactly one location")
            variants.append((name, source.replace(before, after, 1)))
        for name, contents in variants:
            source_path = workspace / "src" / (name + ".c")
            library_path = workspace / (name + ".so")
            source_path.write_text(contents)
            # No -fwrapv: the checked helpers must guard before signed arithmetic.
            subprocess.run(["gcc", "-std=c11", "-O2", "-g", "-Wall", "-Wextra", "-Werror",
                            "-fPIC", "-shared", str(source_path), "-o", str(library_path)], check=True)
            calls, failure = check_library(library_path, pairs)
            if name == "baseline":
                if failure:
                    raise AssertionError("Baseline failed: " + failure)
                print(f"baseline: {len(pairs)} pairs x 4 operations x 2 output modes = {calls} calls passed", flush=True)
            else:
                if failure is None:
                    raise AssertionError("Undetected mutation: " + name)
                print(f"detected {name}: {failure}", flush=True)


if __name__ == "__main__":
    main()
