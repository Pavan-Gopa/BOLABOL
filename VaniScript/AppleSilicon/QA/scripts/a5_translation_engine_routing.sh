#!/usr/bin/env bash
# A5: CloudTextTranslationEngine resolve via CloudChatRouter;
# generateOpenAICompatible shared; parseOpenAIUsage for new providers.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Services/CloudTextTranslationEngine.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

python3 - <<'PY'
from pathlib import Path
text = Path("Sources/VaniScript/Services/CloudTextTranslationEngine.swift").read_text(encoding="utf-8")

if "CloudChatRouter.route" not in text:
    raise SystemExit("FAIL: resolve does not call CloudChatRouter.route")
if "generateOpenAICompatible" not in text:
    raise SystemExit("FAIL: generateOpenAICompatible missing")
if "UsageRecorder.parseOpenAIUsage" not in text:
    raise SystemExit("FAIL: parseOpenAIUsage not used for OpenAI-compatible path")

# Shared path used by gpt-cloud AND new providers
if "func generateOpenAICompatible" not in text and "private func generateOpenAICompatible" not in text:
    raise SystemExit("FAIL: generateOpenAICompatible definition missing")

# resolve default → router; endpoint+headers from route
if "route.endpoint" not in text and "endpoint: route.endpoint" not in text:
    raise SystemExit("FAIL: ActiveCloudTranslationProvider does not carry route.endpoint")
if "route.headers" not in text and "headers: route.headers" not in text:
    raise SystemExit("FAIL: ActiveCloudTranslationProvider does not carry route.headers")

# generate() default branch uses endpoint when present
if "provider.endpoint" not in text:
    raise SystemExit("FAIL: generate() does not branch on provider.endpoint for A5 providers")

print("PASS: translation engine routes via CloudChatRouter + shared generateOpenAICompatible + parseOpenAIUsage.")
PY
