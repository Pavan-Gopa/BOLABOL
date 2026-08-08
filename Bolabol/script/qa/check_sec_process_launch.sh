#!/usr/bin/env bash
# Security guard: every subprocess launch in product sources must use a fixed
# allowlisted executable and an argument array. No shell (-c) execution, no
# user-controlled executable paths. This blocks command-injection regressions
# in the curl/log/afplay/worker launch sites.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

validate_process_launch() {
    local root="$1"
    local sources="$root/Sources"
    local failed=0

    if [ ! -d "$sources" ]; then
        echo "FAIL: Sources/ not found under $root"
        return 1
    fi

    # 1. No shell invocations anywhere in product sources.
    local shells
    shells="$(grep -RInE '/bin/(ba)?sh"|"/bin/(ba)?sh|sh[[:space:]]+-c|bash[[:space:]]+-c' --include='*.swift' "$sources" || true)"
    if [ -n "$shells" ]; then
        echo "FAIL: shell invocation detected in product sources:"
        echo "$shells"
        failed=1
    fi

    # 2. Every executableURL assignment must use a fixed absolute path or the
    #    bundled worker resolved from Bundle.main (never interpolated input).
    local launches
    launches="$(grep -RIn 'executableURL[[:space:]]*=' --include='*.swift' "$sources" || true)"
    if [ -n "$launches" ]; then
        while IFS= read -r line; do
            case "$line" in
                *'fileURLWithPath: "/usr/bin/'*) ;;
                *'workerURL'*) ;;
                *)
                    echo "FAIL: executableURL not from allowlist: $line"
                    failed=1
                    ;;
            esac
        done <<< "$launches"
    fi

    # 3. Process launches must pass an explicit arguments array or a typed
    #    stdin payload (worker IPC); never an argv built from one command
    #    string.
    local process_files
    process_files="$(grep -RIl 'Process()' --include='*.swift' "$sources" || true)"
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        if ! grep -q 'arguments' "$file" && ! grep -q 'standardInput' "$file"; then
            echo "FAIL: Process() without arguments array or typed stdin in ${file#"$root/"}"
            failed=1
        fi
        if grep -qE 'arguments[[:space:]]*=[[:space:]]*\[[[:space:]]*"[^"]*\$\(' "$file"; then
            echo "FAIL: interpolated command string in arguments array in ${file#"$root/"}"
            failed=1
        fi
    done <<< "$process_files"

    [ "$failed" -eq 0 ]
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-process-guard.XXXXXX")"
    trap 'rm -rf "$fixture"' RETURN
    mkdir -p "$fixture/Sources/App"

    cat > "$fixture/Sources/App/Clean.swift" <<'EOF'
func launch() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
    process.arguments = ["--fail", url.absoluteString]
    try process.run()
    let worker = Process()
    worker.executableURL = workerURL
    worker.arguments = []
}
EOF
    validate_process_launch "$fixture" >/dev/null || {
        echo "FAIL: clean fixture was rejected"
        return 1
    }

    cat > "$fixture/Sources/App/Shell.swift" <<'EOF'
func bad() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", userCommand]
}
EOF
    if validate_process_launch "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted /bin/sh launch"
        return 1
    fi
    rm "$fixture/Sources/App/Shell.swift"

    cat > "$fixture/Sources/App/Dynamic.swift" <<'EOF'
func bad() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: userSuppliedPath)
    process.arguments = ["x"]
}
EOF
    if validate_process_launch "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted user-controlled executableURL"
        return 1
    fi

    echo "OK: process launch guard negative self-test"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if ! validate_process_launch "$ROOT"; then
    echo "FAIL: subprocess launch surface violates the allowlist contract"
    exit 1
fi

echo "OK: all subprocess launches use allowlisted executables and argument arrays"
