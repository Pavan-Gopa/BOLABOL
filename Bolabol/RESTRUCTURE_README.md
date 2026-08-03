# BOLABOL Restructure Instructions

## What This Does

Removes the Electron version and flattens the directory structure:

**Before:**
```
/Users/pavan/Documents/AI Projects/Bolabol/
├── NativeAppleSilicon/
│   ├── Package.swift
│   ├── Sources/
│   ├── Tests/
│   └── ...
└── (Electron stuff - will be deleted)
```

**After:**
```
/Users/pavan/Documents/AI Projects/Bolabol/
├── Package.swift
├── Sources/
├── Tests/
├── .review/
└── ...
```

## How to Run

Open Terminal and execute:

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol/NativeAppleSilicon"
chmod +x restructure.sh
./restructure.sh
```

## What the Script Does

1. ✅ Removes Electron directories and artifacts (package.json, node_modules, etc.)
2. ✅ Moves all content from `NativeAppleSilicon/` to `Bolabol/` root
3. ✅ Updates path references in `.agents/` and `.cline/` SKILL.md files
4. ✅ Removes empty `NativeAppleSilicon/` directory
5. ✅ Tests build with `swift build`
6. ✅ Runs tests with `swift test`

## Manual Verification

After running the script:

```bash
cd "/Users/pavan/Documents/AI Projects/Bolabol"
ls -la                    # Should see Package.swift, Sources/, Tests/, etc.
swift build               # Should succeed
swift test                # Should pass 228 tests
```

## Rollback (if needed)

If something goes wrong, the script is non-destructive until the final `rmdir` step. You can:

1. Stop the script (Ctrl+C) before it completes
2. Manually move files back:
   ```bash
   cd "/Users/pavan/Documents/AI Projects/Bolabol"
   mkdir NativeAppleSilicon
   mv * NativeAppleSilicon/ 2>/dev/null || true
   mv .* NativeAppleSilicon/ 2>/dev/null || true
   ```

## Notes

- The script preserves `.git/` history
- Logo assets are unchanged
- All 228 tests should pass after restructure
- Code review pipeline will work from new location

---

**Estimated time:** ~2 minutes (including build + test)