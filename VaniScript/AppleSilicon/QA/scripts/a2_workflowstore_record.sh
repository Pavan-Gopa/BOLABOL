#!/usr/bin/env bash
# QA/scripts/a2_workflowstore_record.sh — A2 (§8.3): WorkflowStore writes settings.usage
# after each successful cloud translation / shorts generation. Assert the best-effort
# recorder reads takeLastUsage(), guards nil, and folds the delta into settings.usage via
# updateSettings + UsageRecorder.record, and that it is wired at multiple call sites.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScript/Stores/WorkflowStore.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "private func recordCloudTranslationUsage(" "$FILE" \
  || { echo "FAIL: recordCloudTranslationUsage missing"; exit 1; }
grep -Fq "let delta = await engine.takeLastUsage()" "$FILE" \
  || { echo "FAIL: must read the engine's accumulated usage via takeLastUsage()"; exit 1; }
grep -Fq "guard delta != nil else { return }" "$FILE" \
  || { echo "FAIL: must skip recording when the provider returned no usage"; exit 1; }
grep -Fq "updateSettings { settings in" "$FILE" \
  || { echo "FAIL: must persist via updateSettings"; exit 1; }
grep -Fq "into: &settings.usage" "$FILE" \
  || { echo "FAIL: UsageRecorder.record must write into &settings.usage"; exit 1; }
grep -Fq "model: provider.model" "$FILE" \
  || { echo "FAIL: record must use provider.model for the per-model key"; exit 1; }

# Wired after cloud translation/shorts operations at several call sites (review + shorts).
calls="$(grep -Fc "recordCloudTranslationUsage(from:" "$FILE")"
[[ "$calls" -ge 4 ]] || { echo "FAIL: expected >=4 recordCloudTranslationUsage call sites, got $calls"; exit 1; }
grep -Fq "recordCloudTranslationUsage(from: reviewCloudEngine" "$FILE" \
  || { echo "FAIL: review cloud path must record usage"; exit 1; }
grep -Fq "recordCloudTranslationUsage(from: shortsCloudEngine" "$FILE" \
  || { echo "FAIL: shorts cloud path must record usage"; exit 1; }

echo "PASS: WorkflowStore records cloud translation usage into settings.usage at $calls call sites."
