#!/usr/bin/env bash
# QA: run_all.sh — Run the full VaniScript QA suite
# Usage: QA/run_all.sh
# Exit 0 = all pass, Exit 1 = at least one failure
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  VaniScript QA Suite — Full Run                        ║"
echo "║  $(date '+%Y-%m-%d %H:%M:%S')                                  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILED_SCRIPTS=()

# Ordered list: source checks first (fast), then builds, then tests, then regression
SCRIPTS=(
    # B. MCP Server Smoke (source-level, instant)
    "mcp_smoke_as.sh"
    "mcp_smoke_electron.sh"
    "mcp_security_as.sh"
    "mcp_security_electron.sh"
    "mcp_isolation.sh"
    "mcp_bridge_token.sh"
    "mcp_cors_origin.sh"
    # C. Provider (source-level, instant)
    "provider_codex_flags.sh"
    "provider_grok_flags.sh"
    "provider_cli_absent.sh"
    "provider_no_fallback.sh"
    "provider_error_types.sh"
    # D. Settings / Routes (source-level, instant)
    "settings_backward_compat.sh"
    "settings_view_agents.sh"
    "routes_selector.sh"
    # E. Security (source-level, instant)
    "security_no_tokens_argv.sh"
    "security_token_env_only.sh"
    # F. Q2 Delta (source-level, instant)
    "qwen_parser_ndjson.sh"
    "qwen_model_catalog.sh"
    "qwen_mcp_wiring.sh"
    "qwen_no_reasoning.sh"
    "qwen_cli_flags.sh"
    "qwen_workspace_isolation.sh"
    # F. Q5 Delta (doc-only, source-level, instant)
    "q5_mcp_instructions_section.sh"
    "q5_endpoint_electron.sh"
    "q5_endpoint_as.sh"
    "q5_auth_bearer.sh"
    "q5_auth_alt_header.sh"
    "q5_cors_loopback.sh"
    "q5_decisions_adr.sh"
    "q5_doc_only_no_code.sh"
    "q5_qwen_settings_format.sh"
    "q5_no_fallback_doc.sh"
    # H. Q6 Delta — in-app API hardening (source-level, instant)
    "q6_streaming_api_surface.sh"
    "q6_error_cases.sh"
    "q6_cancel_sigterm.sh"
    "q6_no_zombie.sh"
    "q6_oslock_async_safe.sh"
    "q6_ndjson_parser.sh"
    "q6_token_env_only.sh"
    "q6_no_silent_fallback.sh"
    "q6_history_item_public.sh"
    "q6_helpers_internal.sh"
    "q6_login_detection.sh"
    "q6_done_exactly_once.sh"
    "q6_no_ui_changes.sh"
    "q6_bug002_electron.sh"
    # G. Regression (source-level, instant)
    "electron_grok_embedded.sh"
    "electron_mcp_cors.sh"
    "regression_mcp_tools_count.sh"
    "regression_profiles.sh"
    "regression_test_count.sh"
    # A. Build Gates (compilation)
    "build_gate_as.sh"
    "build_gate_electron.sh"
    # C. Provider (swift test)
    "provider_codex_tests.sh"
    "provider_grok_tests.sh"
    "provider_qwen_tests.sh"
    # H. Q6 Delta (swift test)
    "q6_test_coverage.sh"
    # D. Settings (swift test)
    "settings_decode.sh"
    # E. Security (swift test)
    "security_contract_tests.sh"
    "security_secrets_snapshot.sh"
    # G. Full regression (swift test, last)
    "regression_swift_test.sh"
)

for SCRIPT in "${SCRIPTS[@]}"; do
    SCRIPT_PATH="$SCRIPT_DIR/scripts/$SCRIPT"
    echo "──────────────────────────────────────────────────────────"
    echo "▶ $SCRIPT"
    echo "──────────────────────────────────────────────────────────"

    if [ ! -f "$SCRIPT_PATH" ]; then
        echo "  SKIP: $SCRIPT not found"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    chmod +x "$SCRIPT_PATH" 2>/dev/null || true

    if bash "$SCRIPT_PATH"; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_SCRIPTS+=("$SCRIPT")
    fi
    echo ""
done

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  QA RESULTS                                            ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  PASS: $PASS_COUNT"
echo "║  FAIL: $FAIL_COUNT"
echo "║  SKIP: $SKIP_COUNT"
echo "║  TOTAL: $((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"
echo "╚══════════════════════════════════════════════════════════╝"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "FAILED SCRIPTS:"
    for S in "${FAILED_SCRIPTS[@]}"; do
        echo "  ✗ $S"
    done
    echo ""
    echo "QA RED — see QA/BUG_REPORT.md for details"
    exit 1
fi

echo ""
echo "QA GREEN — all scripts passed"
exit 0
