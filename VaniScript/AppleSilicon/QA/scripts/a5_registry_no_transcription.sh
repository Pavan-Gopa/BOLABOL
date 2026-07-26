#!/usr/bin/env bash
# A5: transcription gated by supportsTranscription; all three new providers false → no options.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
reg = Path("Sources/VaniScriptCore/ProviderRegistry.swift").read_text(encoding="utf-8")
cat = Path("Sources/VaniScriptCore/CloudProviderCatalog.swift").read_text(encoding="utf-8")
test = Path("Tests/VaniScriptCoreTests/ProviderRegistryCloudTests.swift").read_text(encoding="utf-8")

fn_start = reg.find("availableTranscriptionProviders")
fn_end = reg.find("availableTranslationProviders", fn_start)
body = reg[fn_start:fn_end if fn_end > 0 else None]
if "supportsTranscription" not in body:
    raise SystemExit("FAIL: transcription registry missing supportsTranscription gate")
if "CloudChatRouter.chatProviderIDs" not in body:
    raise SystemExit("FAIL: transcription loop not limited to chatProviderIDs")

# Catalog: qwen/openrouter/ollama-cloud all have supportsTranscription: false
# Extract each provider block roughly by id constants
for pid, label in (
    ("qwenID", "qwen"),
    ("openrouterID", "openrouter"),
    ("ollamaCloudID", "ollama-cloud"),
):
    # Find the descriptor that uses that id and check supportsTranscription: false nearby
    idx = cat.find(f"id: {pid}")
    if idx < 0:
        idx = cat.find(f"id: {pid}")  # already
    if idx < 0:
        # try inline "qwen" string form
        pass
    # Search capabilities near each id: section of ~400 chars after id:
    # Find all supportsTranscription near the three IDs
# Simpler: count supportsTranscription: false after each provider definition
import re
# Ensure catalog defines false for the three providers by locating their blocks
for block_id in ("qwenID", "openrouterID", "ollamaCloudID"):
    m = re.search(rf"id:\s*{block_id}[\s\S]{{0,500}}supportsTranscription:\s*(true|false)", cat)
    if not m:
        raise SystemExit(f"FAIL: could not find supportsTranscription for {block_id}")
    if m.group(1) != "false":
        raise SystemExit(f"FAIL: {block_id} supportsTranscription expected false, got {m.group(1)}")

if "noTranscriptionOptionsWithoutCapability" not in test:
    raise SystemExit("FAIL: unit test noTranscriptionOptionsWithoutCapability missing")

print("PASS: no transcription registry options for qwen/openrouter/ollama-cloud (supportsTranscription=false).")
PY
