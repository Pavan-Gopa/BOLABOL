#!/usr/bin/env python3
"""
Per-Function Review Script Generator
Reads .review/registry/functions.json and generates a review script per function.
Usage: python3 .review/generate_scripts.py [--project-root .]
"""
import json, os, re, sys, stat

def sanitize_name(name):
    return re.sub(r'[^a-zA-Z0-9_]', '_', name)

def generate_script(func, project_root):
    fid = func['id']
    name = func['name']
    file_path = func['file']
    line = func['line']
    module = func['module']
    context = func['context']
    access = func['access']
    kind = func['kind']
    body_lines = func.get('body_lines', 0)
    param_count = func.get('param_count', 0)
    is_async = func.get('is_async', False)
    is_throwing = func.get('is_throwing', False)
    return_type = func.get('return_type', 'Void')
    seq_id = func.get('seq_id', 0)

    safe_module = sanitize_name(module)
    safe_file = sanitize_name(os.path.splitext(os.path.basename(file_path))[0])
    safe_ctx = sanitize_name(context) if context else 'global'
    safe_name = sanitize_name(name)
    script_name = f"{seq_id:04d}_{safe_module}_{safe_file}_{safe_ctx}_{safe_name}.sh"

    checks_dir = os.path.join(project_root, '.review', 'checks')
    check_scripts = sorted([f for f in os.listdir(checks_dir) if f.endswith('.sh')])

    lines = [
        '#!/bin/bash',
        f'# ============================================================',
        f'# Auto-generated review script for function #{seq_id}',
        f'# Function: {context + "." if context else ""}{name}',
        f'# File:     {file_path}:{line}',
        f'# Module:   {module}',
        f'# Kind:     {kind}',
        f'# Access:   {access}',
        f'# Params:   {param_count}',
        f'# Async:    {is_async}',
        f'# Throws:   {is_throwing}',
        f'# Returns:  {return_type}',
        f'# Body:     {body_lines} lines',
        f'# ============================================================',
        '',
        'set -euo pipefail',
        '',
        f'PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"',
        f'FILE_PATH="$PROJECT_ROOT/{file_path}"',
        f'FUNC_NAME="{name}"',
        f'FUNC_LINE={line}',
        f'CHECKS_DIR="$PROJECT_ROOT/.review/checks"',
        '',
        'if [ ! -f "$FILE_PATH" ]; then',
        '    echo "[SKIP] Source file not found: $FILE_PATH"',
        '    exit 0',
        'fi',
        '',
        f'echo "🔍 Reviewing: {context + "." if context else ""}{name} ({file_path}:{line})"',
        f'echo "   Module: {module} | Kind: {kind} | Access: {access}"',
        'echo "   ------------------------------------------------------------"',
        '',
        'ISSUES=0',
        '',
    ]

    for check in check_scripts:
        lines.extend([
            f'# --- Check: {check} ---',
            f'if [ -x "$CHECKS_DIR/{check}" ]; then',
            f'    OUTPUT=$("$CHECKS_DIR/{check}" "$FILE_PATH" "$FUNC_NAME" 2>&1) || true',
            '    if [ -n "$OUTPUT" ]; then',
            '        echo "$OUTPUT"',
            '        ISSUES=$((ISSUES + $(echo "$OUTPUT" | wc -l)))',
            '    fi',
            'fi',
            '',
        ])

    lines.extend([
        'echo "   ------------------------------------------------------------"',
        'if [ "$ISSUES" -gt 0 ]; then',
        '    echo "   ⚠️  Total findings: $ISSUES"',
        '    exit 1',
        'else',
        '    echo "   ✅ No issues found"',
        '    exit 0',
        'fi',
    ])

    return script_name, '\n'.join(lines) + '\n'


def main():
    project_root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else '.')
    registry_path = os.path.join(project_root, '.review', 'registry', 'functions.json')
    output_dir = os.path.join(project_root, '.review', 'per_function')

    if not os.path.exists(registry_path):
        print("Error: Registry not found. Run scan_functions.py first.", file=sys.stderr)
        sys.exit(1)

    with open(registry_path, 'r') as f:
        registry = json.load(f)

    os.makedirs(output_dir, exist_ok=True)
    # Clean old scripts
    for old in os.listdir(output_dir):
        if old.endswith('.sh'):
            os.remove(os.path.join(output_dir, old))

    count = 0
    for func in registry['functions']:
        script_name, content = generate_script(func, project_root)
        script_path = os.path.join(output_dir, script_name)
        with open(script_path, 'w') as f:
            f.write(content)
        os.chmod(script_path, os.stat(script_path).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
        count += 1

    print(f"✅ Generated {count} per-function review scripts in {output_dir}")

    # Generate index
    index_path = os.path.join(output_dir, 'INDEX.md')
    with open(index_path, 'w') as f:
        f.write(f"# Per-Function Review Scripts Index\n\n")
        f.write(f"Total: {count} scripts\n\n")
        f.write(f"| # | Script | Function | File | Line |\n")
        f.write(f"|---|--------|----------|------|------|\n")
        for func in registry['functions']:
            sn, _ = generate_script(func, project_root)
            ctx = func['context'] + '.' if func['context'] else ''
            f.write(f"| {func['seq_id']} | `{sn}` | `{ctx}{func['name']}` | `{func['file']}` | {func['line']} |\n")

    print(f"📄 Index written to {index_path}")


if __name__ == '__main__':
    main()
