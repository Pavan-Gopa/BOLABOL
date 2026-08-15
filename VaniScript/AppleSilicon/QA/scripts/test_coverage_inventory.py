#!/usr/bin/env python3
"""Heuristic VaniScript Swift coverage inventory.

This is not line coverage. It identifies production declarations that are never
mentioned by the Swift test corpus, which is useful for finding forgotten APIs
before writing targeted behavioral tests.

Usage:
  python3 QA/scripts/test_coverage_inventory.py
  python3 QA/scripts/test_coverage_inventory.py --json /tmp/coverage-gaps.json
  python3 QA/scripts/test_coverage_inventory.py --fail-if-unmentioned 100
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE_ROOTS = [ROOT / "Sources" / "VaniScriptCore", ROOT / "Sources" / "VaniScript"]
TEST_ROOTS = [ROOT / "Tests" / "VaniScriptCoreTests", ROOT / "Tests" / "VaniScriptTests"]

DECL_RE = re.compile(
    r"^\s*(?:(?:public|internal|package|private|fileprivate|open|final|static|class|actor|nonisolated)\s+)*"
    r"(?P<kind>struct|class|actor|enum|protocol|func)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


def swift_files(roots: list[pathlib.Path]) -> list[pathlib.Path]:
    result: list[pathlib.Path] = []
    for root in roots:
        if root.exists():
            result.extend(sorted(root.rglob("*.swift")))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", type=pathlib.Path)
    parser.add_argument("--fail-if-unmentioned", type=int, default=None)
    args = parser.parse_args()

    source_files = swift_files(SOURCE_ROOTS)
    test_files = swift_files(TEST_ROOTS)
    test_text = "\n".join(path.read_text(encoding="utf-8", errors="replace") for path in test_files)

    rows = []
    by_file: dict[str, list[dict[str, object]]] = defaultdict(list)
    for path in source_files:
        text = path.read_text(encoding="utf-8", errors="replace")
        rel = str(path.relative_to(ROOT))
        for match in DECL_RE.finditer(text):
            name = match.group("name")
            if name in {"init", "deinit"} or len(name) < 3:
                continue
            mentions = len(re.findall(rf"\b{re.escape(name)}\b", test_text))
            line = text.count("\n", 0, match.start()) + 1
            row = {
                "source": rel,
                "line": line,
                "kind": match.group("kind"),
                "name": name,
                "test_mentions": mentions,
            }
            rows.append(row)
            by_file[rel].append(row)

    unmentioned = [row for row in rows if row["test_mentions"] == 0]
    files_without_mentions = []
    for path in source_files:
        rel = str(path.relative_to(ROOT))
        declarations = by_file.get(rel, [])
        if declarations and all(row["test_mentions"] == 0 for row in declarations):
            files_without_mentions.append(rel)

    print(f"Swift source files: {len(source_files)}")
    print(f"Swift test files:   {len(test_files)}")
    print(f"Declarations:       {len(rows)}")
    print(f"Unmentioned:        {len(unmentioned)}")
    print(f"Files with zero declaration mentions: {len(files_without_mentions)}")
    print("\nHighest-priority unmentioned declarations:")
    for row in unmentioned[:200]:
        print(f"  {row['source']}:{row['line']}  {row['kind']} {row['name']}")

    payload = {
        "source_file_count": len(source_files),
        "test_file_count": len(test_files),
        "declaration_count": len(rows),
        "unmentioned_count": len(unmentioned),
        "files_without_test_mentions": files_without_mentions,
        "unmentioned_declarations": unmentioned,
    }
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if args.fail_if_unmentioned is not None and len(unmentioned) > args.fail_if_unmentioned:
        print(
            f"FAIL: {len(unmentioned)} declarations exceed threshold {args.fail_if_unmentioned}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
