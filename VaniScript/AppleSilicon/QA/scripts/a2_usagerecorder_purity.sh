#!/usr/bin/env bash
# QA/scripts/a2_usagerecorder_purity.sh — A2 (§8.2, §14): UsageRecorder is a PURE,
# side-effect-free aggregation layer in VaniScriptCore. It must NOT do I/O, touch
# settings persistence, or know about engines/stores (so it is trivially unit-testable
# with mock JSON/maps). Assert: enum UsageRecorder, imports Foundation only, and no
# network / filesystem / persistence / throwing in the recorder.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScriptCore/UsageRecorder.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "public enum UsageRecorder" "$FILE" || { echo "FAIL: UsageRecorder is not a public enum"; exit 1; }
grep -Fq "import Foundation" "$FILE" || { echo "FAIL: UsageRecorder must import Foundation"; exit 1; }

# Purity: no UI / networking / filesystem / persistence symbols anywhere in the file.
if grep -Eq "URLSession|URLRequest|FileManager|\.write\(|NSKeyedArchiver|UserDefaults|import SwiftUI|import AppKit" "$FILE"; then
  echo "FAIL: UsageRecorder contains I/O or UI symbols (must stay pure)"; exit 1
fi

# record(...) must be non-throwing (best-effort aggregator, invariant §14.4).
if grep -Eq "static func record\([^)]*throws" "$FILE"; then
  echo "FAIL: UsageRecorder.record must not throw (best-effort)"; exit 1
fi

echo "PASS: UsageRecorder is a pure, non-throwing VaniScriptCore enum (no I/O)."
