#!/usr/bin/env bash
# ADR-018 GO surface contract (S7):
# 1) Package.swift: no canary/gigaam product/target/module naming surface anywhere.
# 2) Sources/: GO catalog entries, backend cases, capabilities, and recommendation logic ALLOWED.
# 3) STILL FORBIDDEN:
#    - Canary/GigaAM engine types in Sources/ (e.g. CanaryCoreMLEngine, GigaAMCoreMLEngine).
#    - NO-GO HuggingFace 1B download sources in Sources/ (FluidInference/canary-1b-v2-coreml or alexwengg).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FAILED=0

# 1. Package.swift: canary and gigaam forbidden in products, targets, and dependencies.
if grep -inE "canary|gigaam" Package.swift; then
  echo "FAIL: canary or gigaam product/module/target name found in Package.swift"
  FAILED=1
fi

# 2. Sources/: Engine types forbidden.
if grep -rnE "CanaryCoreMLEngine|GigaAMCoreMLEngine|class Canary|class GigaAM|struct CanaryCoreMLEngine|struct GigaAMCoreMLEngine" Sources --include='*.swift'; then
  echo "FAIL: Canary or GigaAM engine types found in Sources"
  FAILED=1
fi

# 3. Sources/: NO-GO HuggingFace 1B install sources forbidden (must use bolabol-canary-1b-v2-coreml-r1 package).
if grep -rnE "FluidInference/canary-1b-v2-coreml|alexwengg/canary-1b-v2-coreml" Sources --include='*.swift'; then
  echo "FAIL: NO-GO HuggingFace 1B package source found in Sources"
  FAILED=1
fi

# 4. Sources/: Install source mapping must use authorized ADR-018 GO sources.
if ! grep -q "aufklarer/Canary-180M-Flash-CoreML" Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift; then
  echo "FAIL: Canary Flash install source mapping missing or incorrect"
  FAILED=1
fi

if ! grep -q "huggingfinger0/gigaam-v3-coreml" Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift; then
  echo "FAIL: GigaAM v3 install source mapping missing or incorrect"
  FAILED=1
fi

if ! grep -q "bolabol-canary-1b-v2-coreml-r1" Sources/NativeBolabolCore/Models/TranscriptionModelDescriptor.swift; then
  echo "FAIL: Canary 1B v2 CDN install source mapping missing or incorrect"
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "FAIL: ADR-018 GO product surface contract broken"
  exit 1
fi

echo "OK: ADR-018 GO catalog/backend surface permitted; engines and NO-GO 1B HF sources forbidden"
