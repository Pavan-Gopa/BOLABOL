#!/usr/bin/env bash
# LASR-01: FluidAudio must be pinned exactly at 0.15.5 in manifest and lockfile.
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

python3 - <<'PY'
from pathlib import Path
import json
import re

manifest_path = Path("Package.swift")
resolved_path = Path("Package.resolved")
for path in (manifest_path, resolved_path):
    if not path.is_file():
        raise SystemExit(f"FAIL: {path} missing")

manifest = manifest_path.read_text(encoding="utf-8")
fluid_packages = re.findall(r"\.package\([^\n]*FluidAudio[^\n]*\)", manifest)
if len(fluid_packages) != 1:
    raise SystemExit(f"FAIL: expected one FluidAudio package declaration, found {len(fluid_packages)}")
declaration = fluid_packages[0]
if not re.search(r'exact:\s*"0\.15\.5"', declaration):
    raise SystemExit(f"FAIL: FluidAudio is not exact 0.15.5: {declaration}")
for floating in ("branch:", "from:", ".upToNextMajor", ".upToNextMinor"):
    if floating in declaration:
        raise SystemExit(f"FAIL: FluidAudio pin uses floating requirement {floating}")
if '.product(name: "FluidAudio", package: "FluidAudio")' not in manifest:
    raise SystemExit("FAIL: VaniScript target does not link the FluidAudio product")

resolved = json.loads(resolved_path.read_text(encoding="utf-8"))
pins = [pin for pin in resolved.get("pins", []) if pin.get("identity", "").lower() == "fluidaudio"]
if len(pins) != 1:
    raise SystemExit(f"FAIL: expected one FluidAudio lock pin, found {len(pins)}")
state = pins[0].get("state", {})
if state.get("version") != "0.15.5":
    raise SystemExit(f"FAIL: Package.resolved FluidAudio version is {state.get('version')!r}")
if state.get("revision") != "19600a485baa4998812e4654b70d2bab8f2c9949":
    raise SystemExit(f"FAIL: unexpected FluidAudio 0.15.5 revision {state.get('revision')!r}")

print("PASS: FluidAudio is pinned exact 0.15.5 in Package.swift and Package.resolved.")
PY
