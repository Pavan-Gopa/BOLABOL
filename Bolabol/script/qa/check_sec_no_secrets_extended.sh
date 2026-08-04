#!/usr/bin/env bash
# Security guard: extended secrets scan for directories not covered by
# the baseline check_no_secrets.sh (docs/, scratch/, AI_Workflow_Kit/docs/).
# Skips binary model artifacts (.mlmodelc, .model, .bin) to avoid false positives.
#
# Rationale: Closes finding F1 (medium) from SECURITY_REPORT.md.
# Scope: script/qa/** (allowed), does not modify Sources/**.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DIRS=(
    "docs"
    "scratch"
    "AI_Workflow_Kit/docs"
)

# Secrets patterns: common token/key formats, private keys, high-entropy strings.
# Skips: common words like "API_KEY" (placeholder), URLs, base64 padding.
PATTERNS=(
    "AKIA[0-9A-Z]{16}"                          # AWS access key
    "sk-[a-zA-Z0-9]{20,}"                       # OpenAI/Anthropic-style
    "ghp_[a-zA-Z0-9]{36}"                       # GitHub PAT
    "github_pat_[a-zA-Z0-9_]{20,}"              # GitHub fine-grained PAT
    "BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY"
    "-----BEGIN.*SECRET"
    "password[[:space:]]*=[[:space:]]*['\"][^'\"]{8,}"
    "api_key[[:space:]]*=[[:space:]]*['\"][a-zA-Z0-9]{20,}"
    "token[[:space:]]*=[[:space:]]*['\"][a-zA-Z0-9]{20,}"
    "secret[[:space:]]*=[[:space:]]*['\"][a-zA-Z0-9]{20,}"
)

FOUND=0

for dir in "${DIRS[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "SKIP: $dir does not exist"
        continue
    fi
    for pattern in "${PATTERNS[@]}"; do
        # -I skip binary, -E extended regex, -n line numbers
        # Exclude binary model dirs and specific binary extensions
        hits=$(grep -r -I -E -n "$pattern" "$dir" \
            --exclude-dir="*.mlmodelc" \
            --exclude-dir=".git" \
            --exclude-dir="node_modules" \
            --exclude="*.mlmodelc" \
            --exclude="*.model" \
            --exclude="*.bin" \
            --exclude="*.wav" \
            --exclude="*.mp3" \
            --exclude="*.flac" \
            --exclude="*.png" \
            --exclude="*.jpg" \
            --exclude="*.jpeg" \
            --exclude="*.gif" \
            2>/dev/null || true)
        if [ -n "$hits" ]; then
            echo "FAIL: possible secret in $dir matching pattern '$pattern':"
            echo "$hits" | head -5
            FOUND=1
        fi
    done
done

if [ "$FOUND" -ne 0 ]; then
    echo "FAIL: extended secrets scan found potential leaks"
    exit 1
fi

echo "OK: no secrets detected in docs/, scratch/, AI_Workflow_Kit/docs/ (extended scan)"
