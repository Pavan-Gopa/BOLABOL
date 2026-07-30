#!/bin/bash
# SmartScribe Code Review Pipeline
# Usage:
#   .review/run_review.sh              # Full review
#   .review/run_review.sh --scan-only  # Only scan functions
#   .review/run_review.sh --run-only   # Only run existing scripts
#   .review/run_review.sh --file FILE  # Review a specific file
#   .review/run_review.sh --new        # Scan for new functions only
#   .review/run_review.sh --summary    # Show summary of last report
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW_DIR="$PROJECT_ROOT/.review"
REGISTRY="$REVIEW_DIR/registry/functions.json"
PER_FUNCTION_DIR="$REVIEW_DIR/per_function"
REPORTS_DIR="$REVIEW_DIR/reports"
CHECKS_DIR="$REVIEW_DIR/checks"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$REPORTS_DIR/review_${TIMESTAMP}.md"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
mkdir -p "$REPORTS_DIR"

scan_functions() {
    echo -e "${BLUE}📡 Step 1: Scanning functions...${NC}"
    python3 "$REVIEW_DIR/scan_functions.py" --project-root "$PROJECT_ROOT"
    echo ""
}

detect_new_functions() {
    [ ! -f "$REGISTRY" ] && echo -e "${YELLOW}⚠️  No registry. Run full scan first.${NC}" && return
    local total
    total=$(python3 -c "import json; d=json.load(open('$REGISTRY')); print(d['metadata']['total_functions'])")
    echo -e "${BLUE}📊 Registry: $total functions${NC}"
    local prev_count_file="$REVIEW_DIR/registry/.prev_count"
    if [ -f "$prev_count_file" ]; then
        local prev_count; prev_count=$(cat "$prev_count_file")
        if [ "$total" -gt "$prev_count" ]; then
            echo -e "${GREEN}🆕 $((total - prev_count)) new function(s)!${NC}"
        elif [ "$total" -lt "$prev_count" ]; then
            echo -e "${YELLOW}🗑  $((prev_count - total)) function(s) removed${NC}"
        else
            echo -e "${GREEN}✅ No changes since last scan${NC}"
        fi
    fi
    echo "$total" > "$prev_count_file"
}

generate_scripts() {
    echo -e "${BLUE}🔧 Step 2: Generating per-function scripts...${NC}"
    python3 "$REVIEW_DIR/generate_scripts.py" "$PROJECT_ROOT"
    echo ""
}

run_all_scripts() {
    echo -e "${BLUE}🚀 Step 3: Running per-function review scripts...${NC}"
    local total=0 passed=0 failed=0 all_output=""
    for script in "$PER_FUNCTION_DIR"/*.sh; do
        [ -f "$script" ] || continue
        total=$((total + 1))
        local name; name=$(basename "$script")
        local output
        if output=$(bash "$script" 2>&1); then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            all_output="${all_output}\n### ❌ ${name}\n\`\`\`\n${output}\n\`\`\`\n"
        fi
    done
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Total: $total | ${GREEN}Passed: $passed${NC} | ${RED}Failed: $failed${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    {
        echo "# Code Review Report"
        echo ""
        echo "- **Date:** $(date '+%Y-%m-%d %H:%M:%S')"
        echo "- **Total:** $total | **Passed:** $passed | **Failed:** $failed"
        echo ""
        if [ -n "$all_output" ]; then
            echo "## Findings"
            echo -e "$all_output"
        else
            echo "## ✅ All checks passed!"
        fi
    } > "$REPORT_FILE"
    ln -sf "review_${TIMESTAMP}.md" "$REPORTS_DIR/latest.md"
    echo -e "\n📄 Report: $REPORT_FILE"
}

run_file_checks() {
    local file="$1" abs_file
    if [ -f "$file" ]; then abs_file="$file"
    elif [ -f "$PROJECT_ROOT/$file" ]; then abs_file="$PROJECT_ROOT/$file"
    else echo -e "${RED}File not found: $file${NC}"; exit 1; fi
    echo -e "${BLUE}🔍 Reviewing: $file${NC}\n"
    local issues=0
    for check in "$CHECKS_DIR"/*.sh; do
        [ -x "$check" ] || continue
        local output; output=$("$check" "$abs_file" 2>&1) || true
        if [ -n "$output" ]; then
            echo -e "${YELLOW}--- $(basename "$check") ---${NC}"
            echo "$output"
            issues=$((issues + $(echo "$output" | wc -l)))
        fi
    done
    echo ""
    [ "$issues" -gt 0 ] && echo -e "${RED}Total: $issues findings${NC}" || echo -e "${GREEN}✅ Clean${NC}"
}

case "${1:-}" in
    --scan-only) scan_functions ;;
    --run-only) run_all_scripts ;;
    --file) [ -z "${2:-}" ] && echo "Usage: $0 --file <path>" && exit 1; run_file_checks "$2" ;;
    --new) scan_functions; detect_new_functions; generate_scripts ;;
    --summary) [ -f "$REPORTS_DIR/latest.md" ] && cat "$REPORTS_DIR/latest.md" || echo "No reports yet." ;;
    --help|-h) head -8 "$0" | tail -7 ;;
    *)
        echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║  SmartScribe Code Review Pipeline          ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}\n"
        scan_functions; detect_new_functions; generate_scripts; run_all_scripts ;;
esac
