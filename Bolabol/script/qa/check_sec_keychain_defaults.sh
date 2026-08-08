#!/usr/bin/env bash
# Security guard: API credentials live in the Keychain only.
# - No UserDefaults key may carry a secret-like name (key/token/password).
# - The Keychain credential store must use generic passwords with
#   device-only accessibility (no sync off-device, no plaintext files).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CRED_STORE="Sources/NativeBolabol/Services/APIProviderCredentialStore.swift"

validate_credential_storage() {
    local root="$1"
    local sources="$root/Sources"
    local store="$root/$CRED_STORE"
    local failed=0

    if [ ! -d "$sources" ]; then
        echo "FAIL: Sources/ not found under $root"
        return 1
    fi
    if [ ! -f "$store" ]; then
        echo "FAIL: $CRED_STORE missing"
        return 1
    fi

    # 1. UserDefaults must never hold secret-like keys.
    local secret_defaults
    secret_defaults="$(grep -RInE 'forKey: "[^"]*(apiKey|api_key|secret|password|token|credential)[^"]*"' \
        --include='*.swift' "$sources" || true)"
    if [ -n "$secret_defaults" ]; then
        echo "FAIL: secret-like UserDefaults key detected:"
        echo "$secret_defaults"
        failed=1
    fi

    # 2. Keychain store must use generic passwords.
    if ! grep -q "kSecClassGenericPassword" "$store"; then
        echo "FAIL: credential store no longer uses kSecClassGenericPassword"
        failed=1
    fi

    # 3. Keychain items must stay on this device.
    if ! grep -q "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly" "$store"; then
        echo "FAIL: credential store lost its ThisDeviceOnly accessibility class"
        failed=1
    fi

    # 4. No credential value may be written to a file.
    local file_writes
    file_writes="$(grep -RInE '(apiKey|secret|password)[^[:space:]]*\.write\(to' \
        --include='*.swift' "$sources" || true)"
    if [ -n "$file_writes" ]; then
        echo "FAIL: credential value written to a file:"
        echo "$file_writes"
        failed=1
    fi

    # 5. Credentials must not ride along in URL query strings except the
    #    provider-mandated ?key= upload pattern on the Google TLS endpoint.
    local url_keys
    url_keys="$(grep -RInE '\?key=\\\(' --include='*.swift' "$sources" \
        | grep -v 'generativelanguage.googleapis.com' || true)"
    if [ -n "$url_keys" ]; then
        echo "FAIL: API key placed in a non-Google URL query string:"
        echo "$url_keys"
        failed=1
    fi

    [ "$failed" -eq 0 ]
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-keychain.XXXXXX")"
    trap 'rm -rf "$fixture"' RETURN
    mkdir -p "$fixture/Sources/NativeBolabol/Services"

    cat > "$fixture/$CRED_STORE" <<'EOF'
import Security
let query: [CFString: Any] = [
    kSecClass: kSecClassGenericPassword,
    kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
]
EOF
    cat > "$fixture/Sources/NativeBolabol/Settings.swift" <<'EOF'
func persist() {
    defaults.set(theme, forKey: "general.settings")
    defaults.set(language, forKey: "translation.targetLanguage")
}
EOF
    validate_credential_storage "$fixture" >/dev/null || {
        echo "FAIL: clean fixture was rejected"
        return 1
    }

    cat > "$fixture/Sources/NativeBolabol/BadDefaults.swift" <<'EOF'
func persist() {
    defaults.set(key, forKey: "openai.apiKey")
}
EOF
    if validate_credential_storage "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted an apiKey in UserDefaults"
        return 1
    fi
    rm "$fixture/Sources/NativeBolabol/BadDefaults.swift"

    sed -i '' 's/kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly/kSecAttrAccessibleAlways/' \
        "$fixture/$CRED_STORE"
    if validate_credential_storage "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted a non-device-only keychain class"
        return 1
    fi

    echo "OK: credential storage guard negative self-test"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if ! validate_credential_storage "$ROOT"; then
    echo "FAIL: credential storage contract violated"
    exit 1
fi

echo "OK: credentials stay in a device-only Keychain; no secrets in UserDefaults or files"
