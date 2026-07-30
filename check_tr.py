#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read-only validator for tr_XX.py. Same rules as build_translations.py but does
NOT splice into AppText.swift. Usage: python3 check_tr.py de fr it ...
Exit code 0 = all given languages clean; 1 = errors found."""
import sys
import json
import re
import importlib

with open("en_keys.txt", encoding="utf-8") as f:
    EN_KEYS = [ln.strip() for ln in f if ln.strip()]
with open("en_values.json", encoding="utf-8") as f:
    EN_VALUES = json.load(f)

SPEC_RE = re.compile(r"%[.0-9]*[@df]")
INTERP = "\\(PromptTemplate.transcriptionPlaceholder)"

def specs(s):
    return sorted(SPEC_RE.findall(s))

def validate(lang, T):
    errs = []
    tk = set(T.keys()); ek = set(EN_KEYS)
    missing = ek - tk; extra = tk - ek
    if missing:
        errs.append(f"[{lang}] MISSING {len(missing)} keys: {sorted(missing)[:25]}")
    if extra:
        errs.append(f"[{lang}] EXTRA {len(extra)} keys: {sorted(extra)[:25]}")
    empties = [k for k in EN_KEYS if k in T and T[k].strip() == ""]
    if empties:
        errs.append(f"[{lang}] EMPTY values: {empties[:25]}")
    for k in EN_KEYS:
        if k not in T:
            continue
        ev, tv = EN_VALUES[k], T[k]
        if specs(ev) != specs(tv):
            errs.append(f"[{lang}] SPEC mismatch {k}: en={specs(ev)} got={specs(tv)}")
        if ev.count(INTERP) != tv.count(INTERP):
            errs.append(f"[{lang}] INTERP mismatch {k}: en={ev.count(INTERP)} got={tv.count(INTERP)}")
        if '"' in tv:
            errs.append(f"[{lang}] ASCII double-quote inside value for {k} (use curly quotes)")
    return errs

def main():
    langs = sys.argv[1:]
    if not langs:
        print("No languages given"); sys.exit(2)
    all_errs = []
    for lang in langs:
        try:
            mod = importlib.import_module(f"tr_{lang}")
        except ModuleNotFoundError:
            all_errs.append(f"[{lang}] tr_{lang}.py not found"); continue
        errs = validate(lang, mod.T)
        all_errs.extend(errs)
        if not errs:
            print(f"[{lang}] OK — {len(mod.T)} keys validated (read-only)")
    if all_errs:
        print("\n=== VALIDATION ERRORS ===")
        for e in all_errs:
            print(e)
        print(f"\n{len(all_errs)} error(s).")
        sys.exit(1)

if __name__ == "__main__":
    main()