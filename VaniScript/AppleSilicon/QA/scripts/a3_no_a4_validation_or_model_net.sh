#!/usr/bin/env bash
# A3 out-of-scope: no A4 validation badge / model dropdown network code.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

# A4 files must not exist yet
for f in \
  Sources/VaniScriptCore/CloudKeyValidator.swift \
  Sources/VaniScriptCore/CloudModelCatalog.swift; do
  if [[ -f "$f" ]]; then
    echo "FAIL: A4 file present at A3: $f"
    exit 1
  fi
done

FILE="Sources/VaniScript/Views/SettingsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

# No validation status enum / network model listing in SettingsView
if grep -Eq 'CloudKeyValidator|CloudModelCatalog|listModels\(|KeyValidationStatus|validationStatus|\.checking|\.valid|\.invalid\(' "$FILE"; then
  echo "FAIL: A4 validation/model-catalog symbols found in SettingsView at A3"
  exit 1
fi
# Models should still be ReadOnlyRow, not a live network-backed Picker of models for gemini/openai
python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Views/SettingsView.swift").read_text(encoding="utf-8")
start = text.find("private struct ProviderCardView")
if start < 0:
    raise SystemExit("FAIL: ProviderCardView missing")
card = text[start:start+6000]
# Expect ReadOnlyRow for Text Model
if 'ReadOnlyRow(title: "Text Model"' not in card:
    raise SystemExit("FAIL: expected ReadOnlyRow Text Model in ProviderCardView (A4 replaces this)")
# Fail if URLSession appears in ProviderCardView (network for models)
if "URLSession" in card or "URLRequest" in card:
    raise SystemExit("FAIL: network symbols in ProviderCardView (A4 territory)")
print("PASS: no A4 validation badge / model-list network code at A3.")
PY
