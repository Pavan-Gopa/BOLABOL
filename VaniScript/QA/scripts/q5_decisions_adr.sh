#!/usr/bin/env bash
# QA: q5_decisions_adr.sh — Q5 ADR present in DECISIONS.md
# Asserts:
#   1. DECISIONS.md exists
#   2. ADR D-2026-07-25-Q5 present
#   3. Marked DOC-ONLY
#   4. Documents SSE endpoint (19789)
#   5. Documents Bearer auth
#   6. Documents CORS / loopback policy
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DECISIONS="$PROJECT_ROOT/AppleSilicon/AI_Workflow_Kit/docs/DECISIONS.md"

echo "=== q5_decisions_adr: ADR D-2026-07-25-Q5 in DECISIONS.md ==="

# 1. File exists
[ -f "$DECISIONS" ] || { echo "FAIL: DECISIONS.md not found"; exit 1; }

# 2. ADR id
grep -q 'D-2026-07-25-Q5' "$DECISIONS" || { echo "FAIL: ADR D-2026-07-25-Q5 missing"; exit 1; }

# 3. DOC-ONLY marker
grep -q 'DOC-ONLY' "$DECISIONS" || { echo "FAIL: DOC-ONLY marker missing in ADR"; exit 1; }

# 4. Endpoint documented
grep -q '19789' "$DECISIONS" || { echo "FAIL: SSE endpoint 19789 missing in ADR"; exit 1; }

# 5. Bearer auth documented
grep -q 'Bearer' "$DECISIONS" || { echo "FAIL: Bearer auth missing in ADR"; exit 1; }

# 6. CORS / loopback documented
grep -qi 'CORS' "$DECISIONS" || { echo "FAIL: CORS policy missing in ADR"; exit 1; }
grep -qi 'loopback' "$DECISIONS" || { echo "FAIL: loopback policy missing in ADR"; exit 1; }

echo "PASS: q5_decisions_adr — ADR D-2026-07-25-Q5 with DOC-ONLY/endpoint/auth/CORS present"
exit 0
