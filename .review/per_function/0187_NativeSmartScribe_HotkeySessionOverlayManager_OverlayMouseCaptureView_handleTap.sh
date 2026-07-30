#!/bin/bash
# ============================================================
# Auto-generated review script for function #187
# Function: OverlayMouseCaptureView.handleTap
# File:     Sources/NativeSmartScribe/Services/HotkeySessionOverlayManager.swift:707
# Module:   NativeSmartScribe
# Kind:     function
# Access:   private
# Params:   1
# Async:    False
# Throws:   False
# Returns:  Void
# Body:     14 lines
# ============================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FILE_PATH="$PROJECT_ROOT/Sources/NativeSmartScribe/Services/HotkeySessionOverlayManager.swift"
FUNC_NAME="handleTap"
FUNC_LINE=707
CHECKS_DIR="$PROJECT_ROOT/.review/checks"

if [ ! -f "$FILE_PATH" ]; then
    echo "[SKIP] Source file not found: $FILE_PATH"
    exit 0
fi

echo "🔍 Reviewing: OverlayMouseCaptureView.handleTap (Sources/NativeSmartScribe/Services/HotkeySessionOverlayManager.swift:707)"
echo "   Module: NativeSmartScribe | Kind: function | Access: private"
echo "   ------------------------------------------------------------"

ISSUES=0

# --- Check: check_access_control.sh ---
if [ -x "$CHECKS_DIR/check_access_control.sh" ]; then
    OUTPUT=$("$CHECKS_DIR/check_access_control.sh" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true
    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))
    fi
fi

# --- Check: check_async_patterns.sh ---
if [ -x "$CHECKS_DIR/check_async_patterns.sh" ]; then
    OUTPUT=$("$CHECKS_DIR/check_async_patterns.sh" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true
    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))
    fi
fi

# --- Check: check_complexity.sh ---
if [ -x "$CHECKS_DIR/check_complexity.sh" ]; then
    OUTPUT=$("$CHECKS_DIR/check_complexity.sh" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true
    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))
    fi
fi

# --- Check: check_documentation.sh ---
if [ -x "$CHECKS_DIR/check_documentation.sh" ]; then
    OUTPUT=$("$CHECKS_DIR/check_documentation.sh" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true
    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))
    fi
fi

# --- Check: check_error_handling.sh ---
if [ -x "$CHECKS_DIR/check_error_handling.sh" ]; then
    OUTPUT=$("$CHECKS_DIR/check_error_handling.sh" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true
    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))
    fi
fi

# --- Check: check_force_unwrap.sh ---
if [ -x "$CHECKS_DIR/check_force_unwrap.sh" ]; then
    OUTPUT=$("$CHECKS_DIR/check_force_unwrap.sh" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true
    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))
    fi
fi

# --- Check: check_memory_safety.sh ---
if [ -x "$CHECKS_DIR/check_memory_safety.sh" ]; then
    OUTPUT=$("$CHECKS_DIR/check_memory_safety.sh" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true
    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))
    fi
fi

# --- Check: check_naming.sh ---
if [ -x "$CHECKS_DIR/check_naming.sh" ]; then
    OUTPUT=$("$CHECKS_DIR/check_naming.sh" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true
    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))
    fi
fi

# --- Check: check_swift6_concurrency.sh ---
if [ -x "$CHECKS_DIR/check_swift6_concurrency.sh" ]; then
    OUTPUT=$("$CHECKS_DIR/check_swift6_concurrency.sh" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true
    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))
    fi
fi

# --- Check: check_todo_fixme.sh ---
if [ -x "$CHECKS_DIR/check_todo_fixme.sh" ]; then
    OUTPUT=$("$CHECKS_DIR/check_todo_fixme.sh" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true
    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))
    fi
fi

echo "   ------------------------------------------------------------"
if [ "$ISSUES" -gt 0 ]; then
    echo "   ⚠️  Total findings: $ISSUES"
    exit 1
else
    echo "   ✅ No issues found"
    exit 0
fi
