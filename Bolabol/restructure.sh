#!/bin/bash
# ============================================================
# BOLABOL — Restructure: Remove Electron, Flatten Directory
# ============================================================
# This script:
# 1. Removes Electron version (if exists)
# 2. Moves all content from NativeAppleSilicon/ to Bolabol/ root
# 3. Updates path references in SKILL.md files
# 4. Cleans up empty directories
# ============================================================

set -euo pipefail

PROJECT_ROOT="/Users/pavan/Documents/AI Projects/Bolabol"
NATIVE_DIR="$PROJECT_ROOT/NativeAppleSilicon"

echo "🚀 BOLABOL Restructure Script"
echo "   Project root: $PROJECT_ROOT"
echo ""

# ---- Step 1: Check current structure ----
if [ ! -d "$NATIVE_DIR" ]; then
    echo "❌ Error: $NATIVE_DIR not found"
    exit 1
fi

echo "📁 Current structure:"
ls -la "$PROJECT_ROOT" | grep -E '^d' | awk '{print "   " $9}'
echo ""

# ---- Step 2: Remove Electron version (if exists) ----
ELECTRON_DIRS=("electron" "Electron" "electron-app" "desktop-app")
for dir in "${ELECTRON_DIRS[@]}"; do
    if [ -d "$PROJECT_ROOT/$dir" ]; then
        echo "🗑️  Removing Electron directory: $dir"
        rm -rf "$PROJECT_ROOT/$dir"
    fi
done

# Remove package.json, node_modules, etc. (Electron artifacts)
ELECTRON_FILES=("package.json" "package-lock.json" "yarn.lock" "node_modules" "electron-builder.yml")
for file in "${ELECTRON_FILES[@]}"; do
    if [ -e "$PROJECT_ROOT/$file" ]; then
        echo "🗑️  Removing Electron artifact: $file"
        rm -rf "$PROJECT_ROOT/$file"
    fi
done

echo "✅ Electron cleanup complete"
echo ""

# ---- Step 3: Move NativeAppleSilicon contents to root ----
echo "📦 Moving NativeAppleSilicon/ contents to root..."

# Move all files and directories
cd "$NATIVE_DIR"
for item in *; do
    if [ -e "$item" ]; then
        echo "   Moving: $item"
        mv "$item" "$PROJECT_ROOT/"
    fi
done

# Move hidden files (.review, .cline, .agents, .gitignore, etc.)
for item in .*; do
    if [ -e "$item" ] && [ "$item" != "." ] && [ "$item" != ".." ]; then
        echo "   Moving: $item"
        mv "$item" "$PROJECT_ROOT/"
    fi
done

cd "$PROJECT_ROOT"

# Remove empty NativeAppleSilicon directory
rmdir "$NATIVE_DIR" 2>/dev/null || rm -rf "$NATIVE_DIR"

echo "✅ Directory flattened"
echo ""

# ---- Step 4: Update SKILL.md paths ----
echo "📝 Updating SKILL.md paths..."

SKILL_FILES=(
    "$PROJECT_ROOT/.agents/skills/code-review/SKILL.md"
    "$PROJECT_ROOT/.cline/skills/code-review/SKILL.md"
)

for skill_file in "${SKILL_FILES[@]}"; do
    if [ -f "$skill_file" ]; then
        sed -i '' 's|/Users/pavan/Documents/AI Projects/Bolabol/NativeAppleSilicon|/Users/pavan/Documents/AI Projects/Bolabol|g' "$skill_file"
        echo "   Updated: $(basename "$(dirname "$(dirname "$skill_file")")")/$(basename "$skill_file")"
    fi
done

echo "✅ SKILL.md paths updated"
echo ""

# ---- Step 5: Verify structure ----
echo "📁 New structure:"
ls -la "$PROJECT_ROOT" | grep -E '^d|^-' | awk '{print "   " $9}' | head -20
echo ""

# ---- Step 6: Test build ----
echo "🔨 Testing build..."
cd "$PROJECT_ROOT"
if swift build > /tmp/bolabol_build.log 2>&1; then
    echo "✅ Build successful"
else
    echo "⚠️  Build failed (see /tmp/bolabol_build.log)"
    tail -10 /tmp/bolabol_build.log
fi
echo ""

# ---- Step 7: Run tests ----
echo "🧪 Running tests..."
if swift test > /tmp/bolabol_test.log 2>&1; then
    echo "✅ Tests passed"
    grep "Test run with" /tmp/bolabol_test.log | tail -1
else
    echo "⚠️  Tests failed (see /tmp/bolabol_test.log)"
    tail -10 /tmp/bolabol_test.log
fi
echo ""

echo "🎉 Restructure complete!"
echo ""
echo "Project is now at: $PROJECT_ROOT"
echo "Run 'cd \"$PROJECT_ROOT\" && swift build' to build."