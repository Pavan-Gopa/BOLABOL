#!/usr/bin/env python3
"""
SmartScribe Function Scanner
Scans all Swift source files and extracts function metadata into a JSON registry.
Usage: python3 .review/scan_functions.py [--sources-dir Sources] [--output .review/registry/functions.json]
"""
import argparse, json, os, re, sys
from datetime import datetime, timezone

FUNC_PATTERN = re.compile(
    r'^\s*(?:(?P<attributes>(?:@\w+(?:\([^)]*\))?\s+)*))?'
    r'(?P<modifiers>(?:(?:public|private|internal|fileprivate|open|static|class|override|mutating|nonisolated|nonmutating|dynamic|lazy|weak|unowned|optional|required|convenience|final|indirect)\s+)*)'
    r'func\s+(?P<name>[a-zA-Z_]\w*)\s*(?P<generics><[^>]*>)?\s*'
    r'\((?P<params>[^)]*)\)(?:\s*(?:async|throws|rethrows)\s*)*'
    r'(?:\s*->\s*(?P<return_type>[^\{]+?))?\s*\{', re.MULTILINE)

INIT_PATTERN = re.compile(
    r'^\s*(?:(?P<modifiers>(?:(?:public|private|internal|fileprivate|open|override|convenience|required|failable)\s+)*)'
    r'init\s*[?!]?\s*\((?P<params>[^)]*)\)(?:\s*(?:async|throws|rethrows)\s*)*\s*\{)', re.MULTILINE)

DEINIT_PATTERN = re.compile(r'^\s*deinit\s*\{', re.MULTILINE)

SUBSCRIPT_PATTERN = re.compile(
    r'^\s*(?:(?P<modifiers>(?:(?:public|private|internal|fileprivate|open|static|class|override)\s+)*)'
    r'subscript\s*(?:<[^>]*>\s*)?\((?P<params>[^)]*)\)'
    r'(?:\s*->\s*(?P<return_type>[^\{]+?))?\s*\{)', re.MULTILINE)

TYPE_PATTERN = re.compile(
    r'^\s*(?:(?:public|private|internal|fileprivate|open|final|indirect)\s+)*'
    r'(class|struct|enum|protocol|extension|actor)\s+(\w+)')


def get_context_at_line(lines, line_num):
    stack, brace_depth = [], 0
    for line in lines[:line_num - 1]:
        m = TYPE_PATTERN.match(line)
        if m: stack.append(m.group(2))
        brace_depth += line.count('{') - line.count('}')
        while len(stack) > max(brace_depth, 0) and stack: stack.pop()
    return '.'.join(stack) if stack else ''


def get_access(modifiers):
    for mod in ['public', 'private', 'fileprivate', 'open']:
        if mod in modifiers: return mod
    return 'internal'


def count_params(params_str):
    if not params_str or not params_str.strip(): return 0
    return len([p for p in params_str.split(',') if p.strip()])


def measure_body(content, start):
    brace_count, i = 1, start
    while i < len(content) and brace_count > 0:
        if content[i] == '{': brace_count += 1
        elif content[i] == '}': brace_count -= 1
        i += 1
    return content[start:i].count('\n')


def extract_functions_from_file(filepath, project_root):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    lines = content.split('\n')
    rel_path = os.path.relpath(filepath, project_root)
    parts = rel_path.split(os.sep)
    module = parts[1] if len(parts) > 1 else "Unknown"
    functions = []

    for match in FUNC_PATTERN.finditer(content):
        ln = content[:match.start()].count('\n') + 1
        name = match.group('name').strip()
        modifiers = (match.group('modifiers') or '').strip()
        attributes = (match.group('attributes') or '').strip()
        params = (match.group('params') or '').strip()
        ret = (match.group('return_type') or '').strip()
        full = match.group(0)
        ctx = get_context_at_line(lines, ln)
        fid = f"{module}/{rel_path}:{ctx}.{name}" if ctx else f"{module}/{rel_path}:{name}"
        functions.append({
            'id': fid, 'name': name, 'module': module, 'file': rel_path,
            'line': ln, 'context': ctx, 'access': get_access(modifiers),
            'modifiers': modifiers, 'attributes': attributes, 'params': params,
            'param_count': count_params(params), 'return_type': ret or 'Void',
            'is_async': 'async' in full, 'is_throwing': 'throws' in full or 'rethrows' in full,
            'body_lines': measure_body(content, match.end()), 'kind': 'function'})

    for match in INIT_PATTERN.finditer(content):
        ln = content[:match.start()].count('\n') + 1
        modifiers = (match.group('modifiers') or '').strip()
        params = (match.group('params') or '').strip()
        ctx = get_context_at_line(lines, ln)
        fid = f"{module}/{rel_path}:{ctx}.init" if ctx else f"{module}/{rel_path}:init"
        functions.append({
            'id': fid, 'name': 'init', 'module': module, 'file': rel_path,
            'line': ln, 'context': ctx, 'access': get_access(modifiers),
            'modifiers': modifiers, 'attributes': '', 'params': params,
            'param_count': count_params(params), 'return_type': 'Self',
            'is_async': 'async' in match.group(0), 'is_throwing': 'throws' in match.group(0),
            'body_lines': 0, 'kind': 'initializer'})

    for match in DEINIT_PATTERN.finditer(content):
        ln = content[:match.start()].count('\n') + 1
        ctx = get_context_at_line(lines, ln)
        fid = f"{module}/{rel_path}:{ctx}.deinit" if ctx else f"{module}/{rel_path}:deinit"
        functions.append({
            'id': fid, 'name': 'deinit', 'module': module, 'file': rel_path,
            'line': ln, 'context': ctx, 'access': 'internal', 'modifiers': '',
            'attributes': '', 'params': '', 'param_count': 0, 'return_type': 'Void',
            'is_async': False, 'is_throwing': False, 'body_lines': 0, 'kind': 'deinitializer'})

    for match in SUBSCRIPT_PATTERN.finditer(content):
        ln = content[:match.start()].count('\n') + 1
        modifiers = (match.group('modifiers') or '').strip()
        params = (match.group('params') or '').strip()
        ret = (match.group('return_type') or '').strip()
        ctx = get_context_at_line(lines, ln)
        fid = f"{module}/{rel_path}:{ctx}.subscript" if ctx else f"{module}/{rel_path}:subscript"
        functions.append({
            'id': fid, 'name': 'subscript', 'module': module, 'file': rel_path,
            'line': ln, 'context': ctx, 'access': get_access(modifiers),
            'modifiers': modifiers, 'attributes': '', 'params': params,
            'param_count': count_params(params), 'return_type': ret or 'Void',
            'is_async': False, 'is_throwing': False, 'body_lines': 0, 'kind': 'subscript'})

    return functions


def scan_project(sources_dir, project_root):
    all_functions, files_scanned = [], 0
    for root, dirs, files in os.walk(sources_dir):
        dirs[:] = [d for d in dirs if d != '.build']
        for filename in sorted(files):
            if filename.endswith('.swift'):
                filepath = os.path.join(root, filename)
                all_functions.extend(extract_functions_from_file(filepath, project_root))
                files_scanned += 1
    all_functions.sort(key=lambda f: (f['file'], f['line']))
    for i, func in enumerate(all_functions):
        func['seq_id'] = i + 1
    return {
        'metadata': {
            'project': 'NativeSmartScribe',
            'scanned_at': datetime.now(timezone.utc).isoformat(),
            'sources_dir': os.path.relpath(sources_dir, project_root),
            'files_scanned': files_scanned,
            'total_functions': len(all_functions),
            'scanner_version': '1.0.0',
        },
        'functions': all_functions,
    }


def main():
    parser = argparse.ArgumentParser(description='Scan Swift functions for code review')
    parser.add_argument('--sources-dir', default='Sources')
    parser.add_argument('--output', default='.review/registry/functions.json')
    parser.add_argument('--project-root', default='.')
    args = parser.parse_args()

    project_root = os.path.abspath(args.project_root)
    sources_dir = os.path.join(project_root, args.sources_dir)
    output_path = os.path.join(project_root, args.output)

    if not os.path.isdir(sources_dir):
        print(f"Error: Sources directory not found: {sources_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"🔍 Scanning {sources_dir} ...")
    registry = scan_project(sources_dir, project_root)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(registry, f, indent=2, ensure_ascii=False)

    meta = registry['metadata']
    print(f"✅ Scanned {meta['files_scanned']} files, found {meta['total_functions']} functions")
    print(f"📄 Registry written to: {output_path}")
    modules = {}
    for func in registry['functions']:
        modules[func['module']] = modules.get(func['module'], 0) + 1
    print("\n📊 Functions per module:")
    for mod, count in sorted(modules.items()):
        print(f"   {mod}: {count}")


if __name__ == '__main__':
    main()
