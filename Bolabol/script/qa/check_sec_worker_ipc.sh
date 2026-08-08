#!/usr/bin/env bash
# Security guard: PolishWorker IPC trust boundary.
# - The worker reads its request only from stdin (typed JSON), never argv.
# - The app launches only the worker binary bundled next to its own
#   executable; the path is never user-configurable.
# - No dynamic code loading (dlopen/NSAppleScript/JXA) around the worker.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKER="Sources/NativeBolabolPolishWorker/main.swift"
ENGINE="Sources/NativeBolabol/Services/MLXSwiftPolishingEngine.swift"

validate_worker_ipc() {
    local root="$1"
    local worker="$root/$WORKER"
    local engine="$root/$ENGINE"
    local failed=0

    if [ ! -f "$worker" ]; then
        echo "FAIL: $WORKER missing"
        return 1
    fi
    if [ ! -f "$engine" ]; then
        echo "FAIL: $ENGINE missing"
        return 1
    fi

    # 1. Worker input comes from stdin, decoded as typed JSON.
    if ! grep -q "FileHandle.standardInput.readDataToEndOfFile" "$worker"; then
        echo "FAIL: worker no longer reads its request from stdin"
        failed=1
    fi
    if ! grep -q "JSONDecoder().decode(MLXPolishWorkerRequest.self" "$worker"; then
        echo "FAIL: worker request is no longer decoded through the typed contract"
        failed=1
    fi

    # 2. Worker never trusts command-line arguments.
    if grep -q "CommandLine.arguments" "$worker"; then
        echo "FAIL: worker reads CommandLine.arguments (argv trust boundary violation)"
        failed=1
    fi

    # 3. App resolves the worker from its own bundle, not user input.
    if ! grep -q "Bundle.main.executableURL" "$engine"; then
        echo "FAIL: worker path is no longer resolved from the app bundle"
        failed=1
    fi
    if grep -qE 'executableURL[[:space:]]*=[[:space:]]*URL\(fileURLWithPath:[[:space:]]*request' "$engine"; then
        echo "FAIL: worker executable path derived from request data"
        failed=1
    fi

    # 4. No dynamic code loading primitives in worker or engine.
    local dynamic
    dynamic="$(grep -RInE 'dlopen\(|NSAppleScript|OSAScript|JavaScriptCore' "$worker" "$engine" || true)"
    if [ -n "$dynamic" ]; then
        echo "FAIL: dynamic code loading primitive near worker IPC:"
        echo "$dynamic"
        failed=1
    fi

    [ "$failed" -eq 0 ]
}

self_test() {
    local fixture
    fixture="$(mktemp -d "${TMPDIR:-/tmp}/bolabol-worker.XXXXXX")"
    trap 'rm -rf "$fixture"' RETURN
    mkdir -p "$fixture/Sources/NativeBolabolPolishWorker" \
             "$fixture/Sources/NativeBolabol/Services"

    cat > "$fixture/$WORKER" <<'EOF'
let input = FileHandle.standardInput.readDataToEndOfFile()
let request = try JSONDecoder().decode(MLXPolishWorkerRequest.self, from: input)
EOF
    cat > "$fixture/$ENGINE" <<'EOF'
guard let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else { throw e }
let workerURL = executableDirectory.appendingPathComponent("NativeBolabolPolishWorker")
EOF
    validate_worker_ipc "$fixture" >/dev/null || {
        echo "FAIL: clean fixture was rejected"
        return 1
    }

    cat > "$fixture/$WORKER" <<'EOF'
let args = CommandLine.arguments
let input = FileHandle.standardInput.readDataToEndOfFile()
let request = try JSONDecoder().decode(MLXPolishWorkerRequest.self, from: input)
EOF
    if validate_worker_ipc "$fixture" >/dev/null; then
        echo "FAIL: negative self-test accepted argv trust in the worker"
        return 1
    fi

    echo "OK: worker IPC guard negative self-test"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit $?
fi

if ! validate_worker_ipc "$ROOT"; then
    echo "FAIL: PolishWorker IPC trust boundary violated"
    exit 1
fi

echo "OK: worker IPC stays stdin-only typed JSON with a bundle-resolved binary"
