#!/usr/bin/env bash
# QA/scripts/a2_appsettings_usage_migration_safe.sh — A2 (invariant §14.1 + A1 regression):
# the persisted AppSettings decode must stay migration-safe. Assert settings.usage decodes
# via decodeIfPresent ?? [:] (old settings without usage still load), ProviderUsage is
# Codable, and the A1 last* fields stay optional + decodeIfPresent.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScriptCore/AppSettings.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

# usage map decodes leniently with an empty default (migration-safe).
grep -Fq "self.usage = try container.decodeIfPresent([String: ProviderUsage].self, forKey: .usage) ?? [:]" "$FILE" \
  || { echo "FAIL: settings.usage must decode via decodeIfPresent ?? [:] (migration-safe)"; exit 1; }

# ProviderUsage stays Codable + Sendable.
grep -Fq "public struct ProviderUsage: Codable, Equatable, Sendable" "$FILE" \
  || { echo "FAIL: ProviderUsage must remain Codable/Equatable/Sendable"; exit 1; }

# A1 regression: the optional last* fields remain optional.
grep -Fq "public var lastModel: String?" "$FILE" || { echo "FAIL: ProviderUsage.lastModel must stay optional"; exit 1; }
grep -Fq "public var lastTransactionAt: String?" "$FILE" || { echo "FAIL: ProviderUsage.lastTransactionAt must stay optional"; exit 1; }
for field in lastModel lastTransactionAt; do
  grep -q "decodeIfPresent(.*, forKey: .$field)" "$FILE" \
    || { echo "FAIL: $field must keep using decodeIfPresent (A1 regression)"; exit 1; }
done

echo "PASS: AppSettings.usage decode is migration-safe; ProviderUsage last* fields intact (A1 regression OK)."
