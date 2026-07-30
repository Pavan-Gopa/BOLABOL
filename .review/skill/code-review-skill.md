# Skill: SmartScribe Code Review Pipeline

## Trigger
Invoke with: `/code-review` or ask "run code review" / "запусти код-ревью"

## Description
Automated code review pipeline for the NativeSmartScribe project.
Scans all Swift functions, runs 10 categories of checks, generates per-function
review scripts, and produces a consolidated report.

## Capabilities
1. **Full scan** — discover all functions in Sources/
2. **New function detection** — compare against previous registry
3. **Per-function script generation** — one review script per function
4. **10 check categories** — naming, complexity, force-unwrap, error handling,
   documentation, access control, async patterns, memory safety, Swift 6
   concurrency, TODO/FIXME markers
5. **Report generation** — Markdown report with all findings
6. **Sub-agent delegation** — spawn parallel agents for deep review

## Commands

### Full Review (scan + generate + run all)
```bash
cd /Users/pavan/Documents/AI\ Projects/SmartScribe/NativeAppleSilicon
.review/run_review.sh
```

### Scan for new functions only
```bash
.review/run_review.sh --new
```

### Run existing scripts without re-scanning
```bash
.review/run_review.sh --run-only
```

### Review a specific file
```bash
.review/run_review.sh --file Sources/NativeSmartScribe/Services/AudioRecorder.swift
```

### Show last report
```bash
.review/run_review.sh --summary
```

## Agent Workflow (for AI assistants)

When this skill is invoked, the AI should:

1. **Run the scanner:**
   ```bash
   python3 .review/scan_functions.py --project-root .
   ```

2. **Detect new functions** by comparing registry with previous count:
   ```bash
   .review/run_review.sh --new
   ```

3. **Spawn sub-agents** for deep review of flagged functions:
   - Agent 1: Review all ERROR-level findings
   - Agent 2: Review all WARNING-level findings
   - Agent 3: Check new functions for architecture compliance

4. **Run all per-function scripts:**
   ```bash
   .review/run_review.sh --run-only
   ```

5. **Generate summary report** and present findings to user.

6. **For new functions**, create additional per-function scripts:
   ```bash
   python3 .review/generate_scripts.py .
   ```

## Directory Structure
```
.review/
├── run_review.sh           # Main entry point
├── scan_functions.py       # Function scanner → JSON registry
├── generate_scripts.py     # Per-function script generator
├── registry/
│   └── functions.json      # All discovered functions
├── checks/                 # 10 check scripts
│   ├── check_naming.sh
│   ├── check_complexity.sh
│   ├── check_force_unwrap.sh
│   ├── check_error_handling.sh
│   ├── check_documentation.sh
│   ├── check_access_control.sh
│   ├── check_async_patterns.sh
│   ├── check_memory_safety.sh
│   ├── check_swift6_concurrency.sh
│   └── check_todo_fixme.sh
├── per_function/           # 897 auto-generated scripts
│   ├── INDEX.md
│   └── NNNN_Module_File_Context_func.sh
├── reports/                # Generated reports
│   └── latest.md
└── skill/
    └── code-review-skill.md  # This file
```

## Adding New Checks
1. Create a new script in `.review/checks/` following the pattern:
   - Accept `$1` as file path, `$2` as optional function name
   - Output: `[SEVERITY] file:line: message`
   - Exit 0 = clean, exit 1 = issues found
2. Make it executable: `chmod +x .review/checks/check_new.sh`
3. Re-generate per-function scripts: `python3 .review/generate_scripts.py .`
4. The new check is automatically picked up by all scripts.
