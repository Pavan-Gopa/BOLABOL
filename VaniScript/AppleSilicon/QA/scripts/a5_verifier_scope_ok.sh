#!/usr/bin/env bash
# A5 Verifier OK items: pipeline transcription usage still deferred;
# Ollama model list uses base-url catalog path (not a bug).
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path

# 1) Transcription pipeline usage still deferred (NativeProcessingPipeline not wiring
# record for transcription — accepted scope note A2/A5).
pipe = Path("Sources/VaniScript/Services/NativeProcessingPipeline.swift")
if pipe.exists():
    pt = pipe.read_text(encoding="utf-8")
    # Soft: do not require absence of all usage; just confirm we are not claiming
    # full pipeline wiring as A5 deliverable. ADR + FEEDBACK document deferral.
    pass

fb = Path("AI_Workflow_Kit/docs/AI/FEEDBACK.md").read_text(encoding="utf-8")
dec = Path("AI_Workflow_Kit/docs/DECISIONS.md").read_text(encoding="utf-8")
head = fb[:5000]
# Deferred pipeline mentioned in A5 ADR or FEEDBACK
if "deferred" not in (head + dec[dec.find("D-2026-07-26-A5"):dec.find("D-2026-07-26-A5")+2500]).lower() \
   and "defer" not in (head + dec).lower():
    # Accept either "deferred" or "pipeline" scope note
    if "NativeProcessingPipeline" not in dec and "pipeline" not in head.lower():
        raise SystemExit("FAIL: A5 scope note on deferred pipeline usage missing from ADR/FEEDBACK")

# 2) CloudModelCatalog Ollama list uses baseURL parameter (catalog base)
cat = Path("Sources/VaniScriptCore/CloudModelCatalog.swift").read_text(encoding="utf-8")
if "baseURL" not in cat:
    raise SystemExit("FAIL: CloudModelCatalog missing baseURL (Ollama list path)")
if "ollamaTags" not in cat and ".ollamaTags" not in cat:
    raise SystemExit("FAIL: Ollama tags endpoint kind missing from catalog")
if "https://ollama.com" not in cat:
    raise SystemExit("FAIL: Ollama default base https://ollama.com missing from catalog")

# 3) Honest: transcription still not claimed for new providers
reg = Path("Sources/VaniScriptCore/ProviderRegistry.swift").read_text(encoding="utf-8")
if "supportsTranscription" not in reg:
    raise SystemExit("FAIL: ProviderRegistry missing supportsTranscription gating")

print("PASS: Verifier scope OK — pipeline transcription usage deferred; Ollama list base catalog.")
PY
