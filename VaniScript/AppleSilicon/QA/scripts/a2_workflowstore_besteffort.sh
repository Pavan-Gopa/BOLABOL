#!/usr/bin/env bash
# QA/scripts/a2_workflowstore_besteffort.sh — A2 (invariant §14.4): recording usage must
# never fail the translation. Assert recordCloudTranslationUsage is non-throwing (async,
# no `throws`), returns early when there is no delta, and documents the §14.4 contract.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScript/Stores/WorkflowStore.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

# Signature spans two lines: `private func recordCloudTranslationUsage(` ... `) async {`.
sig="$(awk '/private func recordCloudTranslationUsage\(/{f=1} f{print} f&&/\) async/{exit}' "$FILE")"
[[ -n "$sig" ]] || { echo "FAIL: recordCloudTranslationUsage signature not found"; exit 1; }
if printf '%s' "$sig" | grep -q "throws"; then
  echo "FAIL: recordCloudTranslationUsage must be non-throwing (best-effort, §14.4)"; exit 1
fi
printf '%s' "$sig" | grep -q ") async {" \
  || { echo "FAIL: recordCloudTranslationUsage must be an async, non-throwing func"; exit 1; }

grep -Fq "guard delta != nil else { return }" "$FILE" \
  || { echo "FAIL: must early-return when no usage was captured"; exit 1; }
grep -Fq "§14.4" "$FILE" \
  || { echo "FAIL: best-effort §14.4 contract must be documented at the call layer"; exit 1; }

echo "PASS: recordCloudTranslationUsage is async, non-throwing, and best-effort (§14.4)."
