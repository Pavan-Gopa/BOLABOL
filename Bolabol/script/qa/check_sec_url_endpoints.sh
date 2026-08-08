#!/usr/bin/env bash
# Security guard: every hardcoded HTTPS endpoint in product sources must be on
# the reviewed allowlist. New hosts (SSRF surface, exfil channels, shadow
# download sources) fail the gate until reviewed and added here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

ALLOWED_HOSTS=(
    "huggingface.co"
    "cdn.bolabol.app"
    "bolabol.app"
    "generativelanguage.googleapis.com"
    "aistudio.google.com"
    "api.openai.com"
    "platform.openai.com"
    "api.anthropic.com"
    "console.anthropic.com"
    "openrouter.ai"
    "token-plan.ap-southeast-1.maas.aliyuncs.com"
    "modelstudio.console.alibabacloud.com"
    "dashscope.aliyuncs.com"
)

validate_endpoints() {
    local root="$1"
    local sources="$root/Sources"
    local failed=0

    if [ ! -d "$sources" ]; then
        echo "FAIL: Sources/ not found under $root"
        return 1
    fi

    # 1. No plaintext http:// endpoints (everything must be TLS).
    local plaintext
    plaintext="$(grep -RInoE 'http://[a-zA-Z0-9._-]+' --include='*.swift' "$sources" \
        | grep -v 'http://www.apple.com/DTDs' || true)"
    if [ -n "$plaintext" ]; then
        echo "FAIL: plaintext http endpoint in product sources:"
        echo "$plaintext"
        failed=1
    fi

    # 2. Every https host must be allowlisted.
    local hosts
    hosts="$(grep -RIhoE 'https://[a-zA-Z0-9._-]+' --include='*.swift' "$sources" \
        | sed -E 's#https://##' | sort -u || true)"
    while IFS= read -r host; do
        [ -n "$host" ] || continue
        local known=0
        for allowed in "${ALLOWED_HOSTS[@]}"; do
            if [ "$host" = "$allowed" ]; then
                known=1
                break
            fi
        done
        if [ "$known" -eq 0 ]; then
            echo "FAIL: unreviewed HTTPS host in product sources: $host"
            failed=1
        fi
    done <<< "$hosts"

    [ "$failed" -eq 0 ]
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-endpoints.XXXXXX")"
    trap 'rm -rf "$fixture"' RETURN
    mkdir -p "$fixture/Sources/App"

    cat > "$fixture/Sources/App/Clean.swift" <<'EOF'
let modelAPI = "https://huggingface.co/api/models/repo/tree/main"
let cdn = URL(string: "https://cdn.bolabol.app/models/")!
let openai = "https://api.openai.com/v1"
EOF
    validate_endpoints "$fixture" >/dev/null || {
        echo "FAIL: clean fixture was rejected"
        return 1
    }

    cat > "$fixture/Sources/App/Unknown.swift" <<'EOF'
let shadow = "https://evil.example.com/payload"
EOF
    if validate_endpoints "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted an unreviewed host"
        return 1
    fi
    rm "$fixture/Sources/App/Unknown.swift"

    cat > "$fixture/Sources/App/Plaintext.swift" <<'EOF'
let insecure = "http://huggingface.co/model.bin"
EOF
    if validate_endpoints "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted a plaintext http endpoint"
        return 1
    fi

    echo "OK: endpoint allowlist guard negative self-test"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if ! validate_endpoints "$ROOT"; then
    echo "FAIL: network endpoint surface changed without review"
    exit 1
fi

echo "OK: all hardcoded endpoints are HTTPS and on the reviewed allowlist"
