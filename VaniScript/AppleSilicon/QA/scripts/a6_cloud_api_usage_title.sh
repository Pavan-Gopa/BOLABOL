#!/usr/bin/env bash
# A6: section title is Cloud API Usage (Electron tab 7 style), not old Cloud Usage Statistics.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"
FILE="Sources/VaniScript/Views/UsageStatisticsView.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq 'sectionTitle("Cloud API Usage")' "$FILE" || grep -Fq 'Cloud API Usage' "$FILE" || {
  echo "FAIL: Cloud API Usage title missing from UsageStatisticsView"
  exit 1
}
# Ensure old title is not the live section title in the new view
if grep -Fq 'sectionTitle("Cloud Usage Statistics")' "$FILE"; then
  echo "FAIL: old Cloud Usage Statistics title still used as sectionTitle"
  exit 1
fi
echo "PASS: UsageStatisticsView uses Cloud API Usage title (old title not sectionTitle)."
