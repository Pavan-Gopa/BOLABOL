#!/usr/bin/env bash
# ADR-018 GO surface contract (S9):
# 1) Package.swift: no canary/gigaam product/target/module naming surface anywhere.
# 2) Sources/: GO catalog entries, backend cases, capabilities, recommendation
#    logic, AND engine implementations (CanaryCoreMLEngine, GigaAMCoreMLEngine)
#    are ALLOWED from S9 onward.
# 3) STILL FORBIDDEN:
#    - NO-GO HuggingFace 1B download sources in Sources/
#      (FluidInference/canary-1b-v2-coreml or alexwengg).
#    - Python / NeMo / PyTorch / ONNX runtime in Sources/.
#    - Non-GO engine types (e.g. any engine referencing NO-GO artifacts).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

FAILED=0

# 1. Package.swift: canary and gigaam forbidden in products, targets, and dependencies.
if grep -inE "canary|gigaam" Package.swift; then
  echo "FAIL: canary or gigaam product/module/target name found in Package.swift"
  FAILED=1
fi

# 2. Sources/: NO-GO HuggingFace 1B install sources forbidden (must use bolabol-canary-1b-v2-coreml-r1 package).
if grep -rnE "FluidInference/canary-1b-v2-coreml|alexwengg/canary-1b-v2-coreml" Sources --include='*.swift'; then
  echo "FAIL: NO-GO HuggingFace 1B package source found in Sources"
  FAILED=1
fi

# 3. Sources/: Install source mapping must use authorized ADR-018 GO sources.
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

# 4. Sources/: No Python/NeMo/PyTorch/ONNX runtime imports or subprocess calls.
if grep -rnE "import Python|import NeMo|import torch|import onnx|subprocess|sys\.executable" Sources --include='*.swift'; then
  echo "FAIL: Python/NeMo/PyTorch/ONNX runtime detected in Sources"
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "FAIL: ADR-018 GO product surface contract broken"
  exit 1
fi

echo "OK: ADR-018 GO surface permitted; NO-GO HF sources, Python runtime, and Package targets forbidden"
