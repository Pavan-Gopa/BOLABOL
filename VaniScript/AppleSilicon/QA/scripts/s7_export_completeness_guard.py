#!/usr/bin/env python3
"""Regression guard for S7 PDF/TXT export completeness.

DOCX is allowed to preserve untranslated source paragraphs. PDF/TXT must not
silently present source fallback as a completed translation. This guard checks
that WorkflowStore.exportDocument establishes a document/archive completeness
policy before the save panel is opened.

It intentionally fails on candidate 17, documenting the discovered bug. Once
product code adds a semantic completeness helper/gate, keep this script and
update COMPLETENESS_MARKERS only if the helper receives a different stable name.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
STORE = ROOT / "Sources/VaniScript/Stores/WorkflowStore.swift"

COMPLETENESS_MARKERS = (
    "translationCompleteness",
    "isDocumentTranslationComplete",
    "hasCompleteDocumentTranslation",
    "missingDocumentTranslation",
    "missingTranslatedBlock",
    "incompleteDocumentTranslation",
)


def extract_export_function(text: str) -> str:
    marker = "func exportDocument(format: DocumentOutputFormat)"
    start = text.find(marker)
    if start < 0:
        raise SystemExit("FAIL: WorkflowStore.exportDocument(format:) not found")
    brace = text.find("{", start)
    depth = 0
    for index in range(brace, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise SystemExit("FAIL: could not parse exportDocument body")


def main() -> int:
    text = STORE.read_text(encoding="utf-8")
    body = extract_export_function(text)

    if "DocumentTranslationExportBuilder.translatedDocumentText" not in body:
        print("FAIL: document export no longer uses the reviewed export builder; inspect new path", file=sys.stderr)
        return 1

    panel_pos = body.find("NSSavePanel")
    if panel_pos < 0:
        print("FAIL: expected document save panel boundary not found", file=sys.stderr)
        return 1
    prefix = body[:panel_pos]

    has_semantic_gate = any(marker in prefix for marker in COMPLETENESS_MARKERS)
    has_archive_inspection = "translationsByLanguage" in prefix and (
        "allSatisfy" in prefix or "missing" in prefix.lower() or "complete" in prefix.lower()
    )

    if not (has_semantic_gate or has_archive_inspection):
        print(
            "FAIL: PDF/TXT export reaches NSSavePanel without checking translation completeness.\n"
            "The current aggregate non-empty check can pass on source fallback from "
            "DocumentTranslationExportBuilder.",
            file=sys.stderr,
        )
        return 1

    # Ensure the gate is not merely another aggregate rendered-text test.
    prefix_without_ws = re.sub(r"\s+", " ", prefix)
    if "isUsableTranslationText(text)" in prefix_without_ws and not has_semantic_gate and not has_archive_inspection:
        print("FAIL: aggregate rendered text is not a completeness check", file=sys.stderr)
        return 1

    print("PASS: document export has a pre-save semantic completeness gate")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
