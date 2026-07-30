#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract canonical EN key order + values, and report interpolation/format keys."""
import re
import json

PATH = "Sources/NativeSmartScribeCore/Services/AppText.swift"

with open(PATH, encoding="utf-8") as f:
    lines = f.readlines()

# Find EN block
start = None
for i, line in enumerate(lines):
    if line.strip() == '"en": [':
        start = i + 1
        break
assert start is not None

keys = []
values = {}
entry_re = re.compile(r'^\s*\.([A-Za-z0-9_]+): "(.*)",?\s*$')
for line in lines[start:]:
    if line.strip().startswith('],'):
        break
    s = line.strip()
    if s.startswith('//') or not s:
        continue
    m = entry_re.match(line)
    if m:
        key, val = m.group(1), m.group(2)
        keys.append(key)
        values[key] = val

with open("en_keys.txt", "w", encoding="utf-8") as f:
    f.write("\n".join(keys) + "\n")
with open("en_values.json", "w", encoding="utf-8") as f:
    json.dump(values, f, ensure_ascii=False, indent=0)

# Report keys needing token preservation
tok = [k for k, v in values.items() if ("%" in v) or ("\\(" in v)]
print(f"Total EN keys: {len(keys)}")
print(f"Unique EN keys: {len(set(keys))}")
if len(keys) != len(set(keys)):
    from collections import Counter
    dupes = [k for k, c in Counter(keys).items() if c > 1]
    print("DUPLICATE KEYS:", dupes)
print(f"Keys with format/interpolation tokens: {len(tok)}")
with open("token_keys.txt", "w", encoding="utf-8") as f:
    for k in tok:
        f.write(f"{k}\t{values[k]}\n")
print("Wrote en_keys.txt, en_values.json, token_keys.txt")
