"""One parity runner for Windows and Linux; results are data, never emoji counts."""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys

AXES = {
    1: "Métodos por dtype", 2: "Series e DataSet", 3: "Fronteira C/FFI/Lua",
    4: "Relacional", 5: "I/O por dtype", 6: "Tipos de retorno", 7: "Nulidade",
    8: "Nomenclatura", 9: "Status e sentinelas", 10: "Lifecycle",
    11: "Inventário de testes", 12: "Documentação", 13: "Representação textual",
    14: "Estado compartilhado e reentrância", 15: "Layout compilado C/FFI",
}
STATUSES = {"PASS", "FAIL", "ERROR", "REVIEW", "OBSERVED", "NOT_APPLICABLE"}
RUNTIME_AXES = set(AXES) - {11, 14}


def result(axis, identifier, status, claim, evidence, limit=""):
    if status not in STATUSES:
        raise ValueError("invalid status")
    return dict(version=1, axis=axis, id=identifier, status=status, claim=claim,
                evidence=evidence, limit=limit)


def parse_protocol(stdout, axis, returncode):
    if returncode != 0:
        raise ValueError(f"worker exit {returncode}; partial results are not accepted")
    rows, identifiers = [], set()
    ended = False
    for line in stdout.splitlines():
        record = json.loads(line)
        if ended or record.get("version") != 1 or record.get("axis") != axis:
            raise ValueError("invalid protocol envelope or output after end")
        if "end" in record:
            if type(record["end"]) is not int or record["end"] != len(rows) or not rows:
                raise ValueError("empty or incomplete result set")
            ended = True
        else:
            if record.get("status") not in STATUSES:
                raise ValueError("unknown status")
            for field in ("id", "claim", "evidence", "limit"):
                if not isinstance(record.get(field), str):
                    raise ValueError(f"missing string field {field}")
            if not record["id"] or record["id"] in identifiers:
                raise ValueError("empty or duplicate identifier")
            identifiers.add(record["id"])
            rows.append(record)
    if not ended:
        raise ValueError("missing completion record")
    return rows


def rollup(rows):
    states = {row["status"] for row in rows}
    if not rows or "ERROR" in states:
        return "ERROR"
    if "FAIL" in states:
        return "FAIL"
    if "REVIEW" in states:
        return "REVIEW"
    return "PASS" if "PASS" in states else "OBSERVED"


def exit_code(rows):
    status = rollup(rows)
    return 2 if status == "ERROR" else (1 if status == "FAIL" else 0)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inputs(root):
    paths = []
    for folder in ("src", "include", "lua", "tests", "scripts"):
        paths += [path for path in (root / folder).rglob("*") if path.is_file()
                  and "__pycache__" not in path.parts and path.suffix != ".pyc"]
    paths += [root / "docs/API_INDEX.md", root / "docs/CONTRACT.md", root / "Makefile"]
    return {path.relative_to(root).as_posix(): sha256(path) for path in sorted(paths)}


def markdown_cell(text):
    return str(text).replace("&", "&amp;").replace("<", "&lt;").replace(
        "|", "&#124;").replace("\r", "").replace("\n", "<br>")


def render(report):
    rows = report["results"]
    counts = Counter(row["status"] for row in rows)
    lines = ["# Smaug — Relatório de Paridade", "",
        "Gerado por `scripts/parity/runner.py`. Não editar à mão.", "",
        f"**Resultado: {report['status']}.** Plataforma: {report['platform']}. "
        f"Execução UTC: {report['utc']}.", "",
        "PASS valida somente a afirmação e a fixture indicadas. OBSERVED é inventário; "
        "REVIEW exige análise. FAIL é uma divergência reproduzida; ERROR indica verificação "
        "incompleta. NOT_APPLICABLE exige motivo explícito. Nenhum total mede cobertura "
        "semântica ou certifica toda a biblioteca.", "",
        f"Árvore Git: `{report.get('head', 'indisponível')}`; alterações locais: "
        f"`{report.get('dirty', 'indisponível')}`.", "",
        f"Hash agregado das entradas: `{report.get('input_digest', 'indisponível')}`.", "",
        f"Biblioteca reconstruída: `{report.get('library_sha256', 'indisponível')}`.", "",
        "Ferramentas: " + markdown_cell(json.dumps(report.get("tools", {}), ensure_ascii=False)), "",
        "JSON completo: [PARITY_REPORT.json](PARITY_REPORT.json). "
        "Logs/comandos locais: `" + report["run_directory"] + "`.", "",
        "## Resumo por eixo", "", "| Eixo | Resultado | Registros |",
        "| --- | --- | ---: |"]
    for axis, title in AXES.items():
        selected = [row for row in rows if row["axis"] == axis]
        lines.append(f"| {axis} — {title} | {rollup(selected)} | {len(selected)} |")
    lines += ["", "Contagens de registros estruturados (sem legendas ou duplicação): "
              + ", ".join(f"{status}={counts[status]}" for status in sorted(STATUSES)) + ".",
              "", "## Divergências e erros", "",
              "| Eixo / ID | Estado | Afirmação | Evidência |", "| --- | --- | --- | --- |"]
    findings = [row for row in rows if row["status"] in ("FAIL", "ERROR")]
    for row in findings:
        lines.append("| " + " | ".join(markdown_cell(value) for value in
            (str(row["axis"]) + "/" + row["id"], row["status"], row["claim"], row["evidence"])) + " |")
    if not findings:
        lines.append("| — | — | Nenhuma divergência nos casos executados | Revisões abaixo permanecem |")
    for axis, title in AXES.items():
        selected = [row for row in rows if row["axis"] == axis]
        lines += ["", f"## Eixo {axis} — {title}", "", "<details>",
                  "<summary>Resultados, evidências e limites</summary>", "",
                  "| ID | Estado | Afirmação | Evidência | Limite |",
                  "| --- | --- | --- | --- | --- |"]
        for row in selected:
            lines.append("| " + " | ".join(markdown_cell(row[field]) for field in
                ("id", "status", "claim", "evidence", "limit")) + " |")
        lines += ["", "</details>"]
    lines += ["", "## Reprodução e limites", "",
        "Execute `python scripts/parity/runner.py` no Windows ou "
        "`python3 scripts/parity/runner.py` no Linux. GCC e LuaJIT são obrigatórios. "
        "Cada execução recompila a biblioteca em diretório próprio; não reutiliza uma DLL/.so "
        "preexistente. Exit 1 indica divergência e exit 2 erro/incompletude; REVIEW não vira PASS.",
        "", "Os testes de família, mutações, sanitizers e medição de cobertura têm comandos "
        "próprios no [guia de build](Build_and_Testing.md). Este relatório não os substitui.", ""]
    return "\n".join(lines)


class Audit:
    def __init__(self, root, timeout):
        self.root = root
        self.timeout = timeout
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
        self.directory = root / "build/parity" / timestamp
        (self.directory / "build").mkdir(parents=True)
        self.compiler = shutil.which("gcc")
        self.luajit = shutil.which("luajit")
        self.rows = []
        self.commands = []
        self.library = self.directory / "build" / ("smaug.dll" if os.name == "nt" else "libsmaug.so")

    def command(self, command, label, cwd=None, check=True):
        arguments = [str(value) for value in command]
        entry = {"command": arguments, "cwd": str(cwd or self.root)}
        try:
            completed = subprocess.run(arguments, cwd=cwd or self.root, capture_output=True,
                                       timeout=self.timeout)
        except (OSError, subprocess.TimeoutExpired) as error:
            entry["error"] = str(error)
            self.commands.append(entry)
            raise RuntimeError(f"{label}: {error}") from error
        entry["exit"] = completed.returncode
        entry["stdout"] = completed.stdout.decode("utf-8", errors="replace")
        entry["stderr"] = completed.stderr.decode("utf-8", errors="replace")
        self.commands.append(entry)
        (self.directory / (label + ".log")).write_text(
            json.dumps(entry, indent=2, ensure_ascii=False), encoding="utf-8")
        if check and completed.returncode:
            raise RuntimeError(f"{label}: exit {completed.returncode}: " + entry["stderr"][-3000:])
        return entry

    def runtime(self, axis, extra=""):
        completed = self.command([self.luajit, self.root / "scripts/parity/runtime.lua",
                                  axis, self.root, extra], f"axis-{axis}",
                                 cwd=self.directory, check=False)
        rows = parse_protocol(completed["stdout"], axis, completed["exit"])
        identity = [row for row in rows if row["id"] == "library"]
        if len(identity) != 1:
            raise ValueError("missing loaded library identity")
        loaded = Path(identity[0]["evidence"])
        if not loaded.is_absolute():
            loaded = self.directory / loaded
        if loaded.resolve() != self.library.resolve():
            raise ValueError(f"unexpected library loaded: {loaded}")
        return rows

    def prepare(self):
        if not self.compiler or not self.luajit:
            raise RuntimeError("GCC and LuaJIT are required; no dependency skip")
        shutil.copytree(self.root / "lua", self.directory / "lua")
        sources = sorted((self.root / "src").glob("*.c"))
        if not sources:
            raise RuntimeError("empty C source inventory")
        flags = ["-std=c11", "-O2", "-fwrapv", "-Wall", "-Wextra", "-Wpedantic", "-Werror"]
        self.command([self.compiler, *flags, "-shared", "-fPIC", "-I" + str(self.root / "include"),
                      *sources, "-lm", "-o", self.library], "compile-library")

    def run(self):
        from static_checks import signatures, layouts, test_inventory, documentation, shared_state
        self.prepare()
        for axis in AXES:
            try:
                if axis == 3:
                    selected = signatures(self)
                elif axis == 11:
                    selected = test_inventory(self.root)
                elif axis == 12:
                    selected = documentation(self.root, self.runtime(axis))
                elif axis == 14:
                    selected = shared_state(self)
                elif axis == 15:
                    selected = layouts(self)
                else:
                    selected = self.runtime(axis)
                if not selected:
                    raise ValueError("zero results")
                identifiers = [row["id"] for row in selected]
                if len(set(identifiers)) != len(identifiers):
                    raise ValueError("duplicate result IDs")
                self.rows.extend(selected)
                print(f"{axis:02d} {AXES[axis]}: {rollup(selected)} ({len(selected)} records)", flush=True)
            except (RuntimeError, ValueError, OSError) as error:
                self.rows.append(result(axis, "infrastructure", "ERROR", "Axis completed", str(error)))
                print(f"{axis:02d} {AXES[axis]}: ERROR", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--timeout", type=float, default=120)
    options = parser.parse_args()
    root = options.root.resolve()
    audit = Audit(root, options.timeout)
    report = dict(version=1, status="ERROR", utc=datetime.now(timezone.utc).isoformat(),
                  platform=platform.platform(), run_directory=audit.directory.relative_to(root).as_posix())
    try:
        before = inputs(root)
        report["input_sha256"] = before
        report["input_digest"] = hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest()
        report["tools"] = {}
        for name, executable, option in (("gcc", audit.compiler, "--version"),
                                         ("luajit", audit.luajit, "-v")):
            if executable:
                report["tools"][name] = audit.command([executable, option], "version-" + name)["stdout"].strip()
        if shutil.which("git"):
            report["head"] = audit.command(["git", "rev-parse", "HEAD"], "git-head", check=False)["stdout"].strip()
            report["dirty"] = audit.command(["git", "status", "--short"], "git-status", check=False)["stdout"].splitlines()
        audit.run()
        if before != inputs(root):
            raise RuntimeError("input files changed during audit")
        report["library_sha256"] = sha256(audit.library)
    except (OSError, RuntimeError, ValueError) as error:
        for axis in AXES:
            if not any(row["axis"] == axis for row in audit.rows):
                audit.rows.append(result(axis, "infrastructure", "ERROR", "Verification executed", str(error)))
        if all(any(row["axis"] == axis for row in audit.rows) for axis in AXES):
            audit.rows.append(result(15, "run-integrity", "ERROR", "Run integrity", str(error)))
    report["results"] = audit.rows
    report["status"] = rollup(audit.rows)
    report["commands"] = audit.commands
    document = root / "docs/PARITY_REPORT.md"
    machine = root / "docs/PARITY_REPORT.json"
    document.with_suffix(".md.tmp").write_text(render(report), encoding="utf-8")
    machine.with_suffix(".json.tmp").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    document.with_suffix(".md.tmp").replace(document)
    machine.with_suffix(".json.tmp").replace(machine)
    print(f"Parity: {report['status']}; {document}")
    return exit_code(audit.rows)


if __name__ == "__main__":
    sys.exit(main())
