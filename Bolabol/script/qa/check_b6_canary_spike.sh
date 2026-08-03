#!/usr/bin/env bash
# B6 + S4 Canary Core ML spike contracts (docs-only, NO-GO):
#  1) docs/canary/COREML_SPIKE.md exists, verdict matches /NO-GO/i, covers
#     defects D1–D5, and carries a Recommendation section.
#  2) docs/canary/harness/CanarySpike.swift exists and contains NO Python
#     invocation path: python3/python/pip/pip3/nemo binaries or Process /
#     executableURL / launchPath spawning. Literal "Python" is tolerated only
#     inside // comments (e.g. the "pure Swift, no Python" header note).
#  3) S4 dual-check: docs/asr/canary-1b/COREML_SPIKE.md exists with a GO/NO-GO
#     verdict and covers the spike checklist (Environment, Artifact audit,
#     Load, ASR, Latency, Language tokens, Chunking, No Python, AST, Verdict);
#     docs/canary/harness/CanaryFluidSpike.swift is Swift-only (no Python path).
# Structural complement to the B6/S4 spike reviews; no product Sources touched.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DOC="docs/canary/COREML_SPIKE.md"
HARNESS="docs/canary/harness/CanarySpike.swift"
S4_DOC="docs/asr/canary-1b/COREML_SPIKE.md"
S4_HARNESS="docs/canary/harness/CanaryFluidSpike.swift"

FAILED=0

[ -f "$DOC" ] || { echo "FAIL: $DOC not found"; FAILED=1; }
[ -f "$HARNESS" ] || { echo "FAIL: $HARNESS not found"; FAILED=1; }

# S4 dual-check: report + checklist + Swift-only harness.
if [ -f "$S4_DOC" ]; then
  grep -qE "^\*\*Status:\*\* NO-GO" "$S4_DOC" || { echo "FAIL: $S4_DOC lacks explicit NO-GO status"; FAILED=1; }
  for sec in "Environment" "Artifact audit" "Load" "Short audio ASR" "Latency" "Language tokens" "Chunking" "No Python" "AST" "Verdict"; do
    grep -qi "$sec" "$S4_DOC" || { echo "FAIL: $S4_DOC lacks checklist section: $sec"; FAILED=1; }
  done
else
  echo "FAIL: $S4_DOC not found"
  FAILED=1
fi
if [ -f "$S4_HARNESS" ]; then
  # Python invocation vectors (binaries, shebangs, Process spawning).
  if grep -nE "python3|python[0-9.]*([[:space:]]|/)|pip3?([[:space:]]|$)|nemo|/usr/bin/env|Process\(|executableURL|launchPath" "$S4_HARNESS"; then
    echo "FAIL: $S4_HARNESS contains Python/process invocation patterns"
    FAILED=1
  fi
  # Any literal "Python" mention must sit on a comment line.
  hits=$(grep -n "Python" "$S4_HARNESS" || true)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *//*Python*) ;;
      *) echo "FAIL: $S4_HARNESS non-comment Python mention: $line"; FAILED=1 ;;
    esac
  done <<< "$hits"
else
  echo "FAIL: $S4_HARNESS not found"
  FAILED=1
fi

if [ -f "$DOC" ]; then
  grep -qi "NO-GO" "$DOC" || { echo "FAIL: $DOC lacks NO-GO verdict"; FAILED=1; }
  for d in D1 D2 D3 D4 D5; do
    grep -q "$d" "$DOC" || { echo "FAIL: $DOC lacks defect $d"; FAILED=1; }
  done
  grep -qi "Recommendation" "$DOC" || { echo "FAIL: $DOC lacks Recommendation section"; FAILED=1; }
fi

if [ -f "$HARNESS" ]; then
  # Python invocation vectors (binaries, shebangs, Process spawning).
  if grep -nE "python3|python[0-9.]*([[:space:]]|/)|pip3?([[:space:]]|$)|nemo|/usr/bin/env|Process\(|executableURL|launchPath" "$HARNESS"; then
    echo "FAIL: $HARNESS contains Python/process invocation patterns"
    FAILED=1
  fi
  # Any literal "Python" mention must sit on a comment line.
  hits=$(grep -n "Python" "$HARNESS" || true)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *//*Python*) ;;
      *) echo "FAIL: $HARNESS non-comment Python mention: $line"; FAILED=1 ;;
    esac
  done <<< "$hits"
fi

if [ "$FAILED" -ne 0 ]; then
  echo "FAIL: B6/S4 Canary spike contracts broken (docs-only NO-GO, zero Python path)"
  exit 1
fi

echo "OK: B6 + S4 spike docs (NO-GO) + zero-Python harness contracts hold"
