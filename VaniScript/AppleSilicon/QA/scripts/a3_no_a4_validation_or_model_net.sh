#!/usr/bin/env bash
# A3 out-of-scope: no A4 validation badge / model dropdown network code.
# Step-aware: only enforced while current_step is A3. From A4 onward A4 files are
# expected and this gate is N/A (PASS) so the regression suite stays green.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

STATE_FILE="AI_Workflow_Kit/docs/AI/STATE.yaml"
current_step=""
if [[ -f "$STATE_FILE" ]]; then
  current_step="$(sed -nE 's/^current_step:[[:space:]]*([A-Za-z0-9_]+).*/\1/p' "$STATE_FILE" | head -1)"
fi
case "$current_step" in
  A3|"")
    echo "current_step='${current_step:-A3}' — enforcing A3 no-A4 gate."
    ;;
  *)
    echo "NOTE: current_step='$current_step' ≥ A4; A3 no-A4 gate is N/A."
    echo "RESULT: PASS (a3_no_a4_validation_or_model_net, step-aware N/A)"
    exit 0
    ;;
esac

# A4 files must not exist yet at A3
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
