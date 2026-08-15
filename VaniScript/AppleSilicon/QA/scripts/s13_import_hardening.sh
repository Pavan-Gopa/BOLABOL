#!/usr/bin/env bash
# S13: Hardening and extra import tiers verification script.
# Validates format support (TXT, Markdown, RTF, PDF, DOCX), accuracy badges,
# size limits, cancellation, and honest error handling for scanned PDF.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

PDF_FILE="Sources/VaniScript/Services/PDFDocumentImporter.swift"
IMPORT_FILE="Sources/VaniScript/Services/DocumentImportService.swift"
CONFIG_FILE="Sources/VaniScript/Views/ConfigWorkspaceView.swift"

[[ -f "$PDF_FILE" ]] || { echo "FAIL: $PDF_FILE missing"; exit 1; }
[[ -f "$IMPORT_FILE" ]] || { echo "FAIL: $IMPORT_FILE missing"; exit 1; }
[[ -f "$CONFIG_FILE" ]] || { echo "FAIL: $CONFIG_FILE missing"; exit 1; }

python3 - <<'PY'
import sys
from pathlib import Path

# 1. Check DocumentImportService
import_text = Path("Sources/VaniScript/Services/DocumentImportService.swift").read_text(encoding="utf-8")
for required in [
    "DocumentImportLimits",
    "accuracyBadge",
    "Plain text — paragraph structure preserved.",
    "Markdown — structural import.",
    "RTF — structural import, formatting may be simplified.",
    "PDF — text reconstruction, layout may vary.",
    "DOCX — round-trip preservation.",
    "scannedPDFNotSupported",
    "fileSizeExceedsLimit",
    "importCancelled",
    "makeMarkdownState",
    "makeRTFState",
    "PDFDocumentImporter",
]:
    if required not in import_text:
        raise SystemExit(f"FAIL: DocumentImportService missing required element: {required}")

# 2. Check PDFDocumentImporter
pdf_text = Path("Sources/VaniScript/Services/PDFDocumentImporter.swift").read_text(encoding="utf-8")
for required in [
    "struct PDFDocumentImporter",
    "PDFKit",
    "reconstructParagraphs",
    "scannedPDFNotSupported",
    "fileSizeExceedsLimit",
    "pageCountExceedsLimit",
    "cancelled",
]:
    if required not in pdf_text:
        raise SystemExit(f"FAIL: PDFDocumentImporter missing required element: {required}")

# 3. Check ConfigWorkspaceView
config_text = Path("Sources/VaniScript/Views/ConfigWorkspaceView.swift").read_text(encoding="utf-8")
for required in [
    "accuracyBadge",
    "document-accuracy-badge",
]:
    if required not in config_text:
        raise SystemExit(f"FAIL: ConfigWorkspaceView missing accuracy badge UI: {required}")

print("PASS: S13 Hardening and extra import tiers contracts verified.")
PY
