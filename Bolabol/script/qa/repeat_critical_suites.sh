#!/usr/bin/env bash
# Deterministic flake runner: no sleeps, no retries hidden as passes, and all
# suites continue after an independent failure.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

ITERATIONS="${1:-20}"
case "$ITERATIONS" in
  ''|*[!0-9]*|0)
    echo "Usage: $0 [positive-iteration-count]" >&2
    exit 2
    ;;
esac

suites=(
  HumorStyleControlTests
  HotkeySettingsTests
  HUDProviderSwitcherFeatureTests
  HUDLayoutAndComposerTests
  HotkeySessionCoordinatorTests
  PolishingWorkflowTests
  PromptTemplateTests
)

passed=0
failed=0
for ((iteration = 1; iteration <= ITERATIONS; iteration++)); do
  for suite in "${suites[@]}"; do
    echo "RUN iteration=$iteration suite=$suite"
    if swift test --filter "$suite"; then
      passed=$((passed + 1))
    else
      failed=$((failed + 1))
    fi
  done
done

echo "SUMMARY iterations=$ITERATIONS runs=$((passed + failed)) passed=$passed failed=$failed"
[ "$failed" -eq 0 ]
