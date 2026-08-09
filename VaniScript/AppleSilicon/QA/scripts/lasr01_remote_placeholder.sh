#!/usr/bin/env bash
# LASR-01 negative gate: Canary 1B remains an unbound, vendor-neutral remotePackage placeholder.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
import re

catalog_path = Path("Sources/VaniScriptCore/NativeModelCatalog.swift")
if not catalog_path.is_file():
    raise SystemExit(f"FAIL: {catalog_path} missing")
text = catalog_path.read_text(encoding="utf-8")

marker = "public static let canaryOneBPlaceholder = RemoteModelPackageRelease("
start = text.find(marker)
if start < 0:
    raise SystemExit("FAIL: Canary 1B remote-package placeholder missing")
paren_start = text.find("(", start)
depth = 0
end = None
for index in range(paren_start, len(text)):
    char = text[index]
    if char == "(":
        depth += 1
    elif char == ")":
        depth -= 1
        if depth == 0:
            end = index + 1
            break
if end is None:
    raise SystemExit("FAIL: could not parse Canary 1B placeholder constructor")
placeholder = text[start:end]

required = (
    'packageID: "canary-1b-v2-coreml"',
    'layoutVersion: "path-b-v1"',
    'directURLOverrideEnvironmentKey: "VANISCRIPT_CANARY_1B_PACKAGE_URL"',
    'baseURLEnvironmentKey: "VANISCRIPT_MODEL_PACKAGE_BASE_URL"',
)
for snippet in required:
    if snippet not in placeholder:
        raise SystemExit(f"FAIL: Canary 1B placeholder missing {snippet}")

for bound_field in (
    "relativeArchivePath:",
    "expectedArchiveSHA256:",
    "expectedCompressedSizeBytes:",
    "expectedUncompressedSizeBytes:",
    "allowlistedFiles:",
):
    if bound_field in placeholder:
        raise SystemExit(f"FAIL: Canary 1B placeholder prematurely binds {bound_field}")

if not re.search(r"case\s+remotePackage\s*\(RemoteModelPackageRelease\)", text):
    raise SystemExit("FAIL: generic remotePackage install-source case missing")
if "installSource: .remotePackage(.canaryOneBPlaceholder)" not in text:
    raise SystemExit("FAIL: Canary 1B descriptor does not use the placeholder")

source_text = "\n".join(
    path.read_text(encoding="utf-8", errors="replace")
    for path in Path("Sources").rglob("*.swift")
)
lower = source_text.lower()
for forbidden in ("bolabol", "drive.google", "docs.google", "googleusercontent", "cdn.bolabol"):
    if forbidden in lower:
        raise SystemExit(f"FAIL: forbidden concrete/vendor package source leaked into product Sources: {forbidden}")
if re.search(r"https?://", placeholder, re.I):
    raise SystemExit("FAIL: Canary 1B placeholder contains a concrete URL")

print("PASS: Canary 1B is a vendor-neutral remotePackage placeholder with no URL, digest or CDN leakage.")
PY
