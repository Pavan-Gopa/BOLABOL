#!/usr/bin/env bash
set -uo pipefail

LOG="$HOME/Desktop/vani-app-launch-diagnostics-$(date +%Y%m%d-%H%M%S).log"
EXPECTED_SMARTSCRIBE="6cc243747617e5a11334b683052dbb3f72cbfa234637c1ffbccd1f7343ee2455"
EXPECTED_VANISCRIPT="d05008836de2e4e1c270355be04d9418f270c1a15029da3016d18d67e2bfe752"
EXPECTED_VANISCRIPT_ELECTRON="50b2c3a9004fa2950f09823bd4582e087c01032c1575d4836a76639f87fb2682"

exec > >(tee "$LOG") 2>&1

section() {
  printf '\n===== %s =====\n' "$1"
}

run() {
  printf '\n$ %s\n' "$*"
  "$@" 2>&1 || true
}

expected_sha_for_dmg() {
  case "$(basename "$1")" in
    SmartScribe.dmg) echo "$EXPECTED_SMARTSCRIBE" ;;
    VaniScript.dmg) echo "$EXPECTED_VANISCRIPT" ;;
    VaniScript-Electron.dmg) echo "$EXPECTED_VANISCRIPT_ELECTRON" ;;
    *) echo "" ;;
  esac
}

inspect_dmg() {
  local dmg="$1"
  local expected actual mount app

  section "DMG: $dmg"
  if [[ ! -f "$dmg" ]]; then
    echo "missing"
    return
  fi

  expected="$(expected_sha_for_dmg "$dmg")"
  actual="$(shasum -a 256 "$dmg" | awk '{print $1}')"
  echo "sha256=$actual"
  if [[ -n "$expected" ]]; then
    if [[ "$actual" == "$expected" ]]; then
      echo "sha256_expected=OK"
    else
      echo "sha256_expected=MISMATCH expected=$expected"
    fi
  fi

  run ls -lh "$dmg"
  run xattr -l "$dmg"
  run hdiutil verify "$dmg"
  run xcrun stapler validate "$dmg"
  run spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"

  mount="$(hdiutil attach -nobrowse -readonly "$dmg" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"
  if [[ -n "$mount" ]]; then
    app="$(find "$mount" -maxdepth 1 -name '*.app' -type d | head -n 1)"
    if [[ -n "$app" ]]; then
      inspect_app "$app"
    else
      echo "no app bundle found in mounted dmg"
    fi
    hdiutil detach "$mount" >/dev/null 2>&1 || true
  else
    echo "failed to mount dmg"
  fi
}

inspect_app() {
  local app="$1"
  local plist exe name bundle min archs

  section "APP: $app"
  if [[ ! -d "$app" ]]; then
    echo "missing"
    return
  fi

  plist="$app/Contents/Info.plist"
  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist" 2>/dev/null || true)"
  name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$plist" 2>/dev/null || basename "$app" .app)"
  bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
  min="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist" 2>/dev/null || true)"

  echo "name=$name"
  echo "bundle=$bundle"
  echo "executable=$exe"
  echo "minimum_macos=${min:-unset}"

  if [[ -n "$exe" && -f "$app/Contents/MacOS/$exe" ]]; then
    archs="$(lipo -archs "$app/Contents/MacOS/$exe" 2>/dev/null || true)"
    echo "archs=${archs:-unknown}"
    run stat -f '%Sp %OLp %N' "$app/Contents/MacOS/$exe"
    run file "$app/Contents/MacOS/$exe"
    run otool -l "$app/Contents/MacOS/$exe"
  else
    echo "main executable missing at $app/Contents/MacOS/$exe"
  fi

  run xattr -lr "$app"
  run codesign --verify --deep --strict --verbose=4 "$app"
  run codesign -dvvv --entitlements :- "$app"
  run xcrun stapler validate "$app"
  if command -v syspolicy_check >/dev/null 2>&1; then
    run syspolicy_check distribution "$app"
  else
    echo "syspolicy_check is not available on this macOS"
  fi
  run spctl --assess --type execute --verbose=4 "$app"
}

launch_app() {
  local app="$1"
  local exe

  section "LAUNCH: $app"
  if [[ ! -d "$app" ]]; then
    echo "missing"
    return
  fi

  exe="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null || true)"
  if [[ -z "$exe" ]]; then
    echo "no executable in Info.plist"
    return
  fi

  pkill -x "$exe" >/dev/null 2>&1 || true
  run open -n "$app"
  sleep 8
  if pgrep -x "$exe" >/dev/null 2>&1; then
    echo "launch_result=RUNNING"
    osascript -e "quit app \"$exe\"" >/dev/null 2>&1 || true
    sleep 2
    pkill -x "$exe" >/dev/null 2>&1 || true
  else
    echo "launch_result=NOT_RUNNING"
  fi
}

section "SYSTEM"
run sw_vers
run uname -a
run spctl --status
run csrutil status
run system_profiler SPHardwareDataType

section "DOWNLOADED DMGS"
for dmg in \
  "$HOME/Downloads/SmartScribe.dmg" \
  "$HOME/Downloads/VaniScript.dmg" \
  "$HOME/Downloads/VaniScript-Electron.dmg" \
  "$(pwd)/SmartScribe.dmg" \
  "$(pwd)/VaniScript.dmg" \
  "$(pwd)/VaniScript-Electron.dmg"; do
  [[ -f "$dmg" ]] && inspect_dmg "$dmg"
done

section "INSTALLED APPS"
for app in \
  "/Applications/SmartScribe.app" \
  "/Applications/VaniScript.app" \
  "/Applications/VaniScript-Electron.app"; do
  inspect_app "$app"
done

section "LAUNCH CHECKS"
for app in \
  "/Applications/SmartScribe.app" \
  "/Applications/VaniScript.app" \
  "/Applications/VaniScript-Electron.app"; do
  launch_app "$app"
done

section "RECENT DIAGNOSTIC REPORTS"
run find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 \
  '(' -name '*SmartScribe*' -o -name '*VaniScript*' ')' \
  -type f -print

section "RECENT SECURITY LOGS"
run log show --last 20m --style compact --predicate \
  'process == "syspolicyd" OR process == "taskgated" OR eventMessage CONTAINS[c] "SmartScribe" OR eventMessage CONTAINS[c] "VaniScript" OR eventMessage CONTAINS[c] "notar" OR eventMessage CONTAINS[c] "Gatekeeper"'

section "DONE"
echo "Log written to: $LOG"
