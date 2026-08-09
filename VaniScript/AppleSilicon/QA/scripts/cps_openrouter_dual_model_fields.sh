#!/usr/bin/env bash
# OpenRouter has separate transcription + translation model fields.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScriptCore/AppSettings.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }
for field in openrouterTranscriptionModel openrouterTranslationModel openrouterModel openrouterApiKey openrouterBudgetUsd; do
  grep -q "var $field" "$FILE" || { echo "FAIL: missing AppSettings.$field"; exit 1; }
done
grep -q "func transcriptionModel(for" "$FILE" || { echo "FAIL: transcriptionModel(for:) missing"; exit 1; }
grep -q "func translationModel(for" "$FILE" || { echo "FAIL: translationModel(for:) missing"; exit 1; }
python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScriptCore/AppSettings.swift").read_text(encoding="utf-8")
t1 = text.find("func transcriptionModel")
t2 = text.find("func translationModel")
if "openrouterTranscriptionModel" not in text[t1:t1+900]:
    raise SystemExit("FAIL: transcriptionModel(for:) does not read openrouterTranscriptionModel")
if "openrouterTranslationModel" not in text[t2:t2+1000]:
    raise SystemExit("FAIL: translationModel(for:) does not read openrouterTranslationModel")
print("PASS: OpenRouter dual model fields + role helpers present.")
PY
