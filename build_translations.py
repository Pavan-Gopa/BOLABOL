#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Validate per-language translation modules (tr_XX.py) against the EN key set,
check format/interpolation token preservation, then splice full blocks into AppText.swift.

Usage: python3 build_translations.py es de fr ...   (language codes with tr_XX.py present)
"""
import re
import sys
import json
import importlib

PATH = "Sources/NativeSmartScribeCore/Services/AppText.swift"
INDENT = "            "

with open("en_keys.txt", encoding="utf-8") as f:
    EN_KEYS = [ln.strip() for ln in f if ln.strip()]
with open("en_values.json", encoding="utf-8") as f:
    EN_VALUES = json.load(f)

SPEC_RE = re.compile(r"%[.0-9]*[@df]")
INTERP = "\\(PromptTemplate.transcriptionPlaceholder)"

def specs(s):
    return sorted(SPEC_RE.findall(s))

def interp_count(s):
    return s.count(INTERP)

def validate(lang, T):
    errs = []
    tk = set(T.keys())
    ek = set(EN_KEYS)
    missing = ek - tk
    extra = tk - ek
    if missing:
        errs.append(f"[{lang}] MISSING {len(missing)} keys: {sorted(missing)[:20]}")
    if extra:
        errs.append(f"[{lang}] EXTRA {len(extra)} keys: {sorted(extra)[:20]}")
    # Empty values
    empties = [k for k in EN_KEYS if k in T and T[k].strip() == ""]
    if empties:
        errs.append(f"[{lang}] EMPTY values: {empties[:20]}")
    # Token preservation
    for k in EN_KEYS:
        if k not in T:
            continue
        ev, tv = EN_VALUES[k], T[k]
        if specs(ev) != specs(tv):
            errs.append(f"[{lang}] SPEC mismatch {k}: en={specs(ev)} got={specs(tv)}")
        if interp_count(ev) != interp_count(tv):
            errs.append(f"[{lang}] INTERP mismatch {k}: en={interp_count(ev)} got={interp_count(tv)}")
        if '"' in tv:
            errs.append(f"[{lang}] ASCII double-quote inside value for {k} (use curly quotes)")
    return errs

def build_block(T):
    out = []
    for k in EN_KEYS:
        v = T[k].replace("\\", "\\\\") if False else T[k]  # values already Swift-ready
        out.append(f'{INDENT}.{k}: "{T[k]}",')
    # last entry: drop trailing comma to match style (optional; Swift allows trailing comma)
    return out

def splice(lang_blocks):
    with open(PATH, encoding="utf-8") as f:
        lines = f.readlines()
    out = []
    i = 0
    n = len(lines)
    header_re = re.compile(r'^        "([a-z]{2})": \[\s*$')
    while i < n:
        line = lines[i]
        m = header_re.match(line)
        if m and m.group(1) in lang_blocks:
            lang = m.group(1)
            out.append(line)  # keep "xx": [
            # skip old entries until the block terminator ("        ]," or, for the
            # last language block, "        ]" without a trailing comma)
            i += 1
            while i < n and lines[i].rstrip("\n") not in ("        ],", "        ]"):
                i += 1
            # insert new block
            for bl in lang_blocks[lang]:
                out.append(bl + "\n")
            # keep the closing "],"
            if i < n:
                out.append(lines[i])
                i += 1
            continue
        out.append(line)
        i += 1
    with open(PATH, "w", encoding="utf-8") as f:
        f.writelines(out)

def main():
    langs = sys.argv[1:]
    if not langs:
        print("No languages given")
        sys.exit(2)
    all_errs = []
    lang_blocks = {}
    for lang in langs:
        try:
            mod = importlib.import_module(f"tr_{lang}")
        except ModuleNotFoundError:
            all_errs.append(f"[{lang}] tr_{lang}.py not found")
            continue
        T = mod.T
        errs = validate(lang, T)
        all_errs.extend(errs)
        if not errs:
            lang_blocks[lang] = build_block(T)
            print(f"[{lang}] OK — {len(T)} keys validated")
    if all_errs:
        print("\n=== VALIDATION ERRORS ===")
        for e in all_errs:
            print(e)
        print(f"\n{len(all_errs)} error(s). NOT writing file.")
        sys.exit(1)
    splice(lang_blocks)
    print(f"\nSpliced {len(lang_blocks)} language block(s) into {PATH}")

if __name__ == "__main__":
    main()
