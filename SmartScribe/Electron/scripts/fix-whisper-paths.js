#!/usr/bin/env node
/**
 * Fix whisper-node-addon platform path mapping for macOS
 * 
 * The addon expects 'darwin-x64' but the actual directory is 'mac-x64'
 * This script creates the necessary symlink to fix the issue.
 */

const fs = require('fs');
const path = require('path');

function fixWhisperPaths() {
  const addonPath = path.join(__dirname, '..', 'node_modules', '@kutalia', 'whisper-node-addon', 'dist');

  if (process.platform !== 'darwin') {
    console.log('[fix-whisper-paths] Not on macOS, skipping.');
    return;
  }
  if (!fs.existsSync(addonPath)) {
    console.log('[fix-whisper-paths] whisper-node-addon dist folder not found, skipping.');
    return;
  }

  // We attempt to prepare BOTH architectures if their actual directories exist.
  // This helps when producing universal / cross-arch artifacts on one machine (e.g., packaging).
  const mappings = [
    { arch: 'x64', expected: 'darwin-x64', actual: 'mac-x64' },
    { arch: 'arm64', expected: 'darwin-arm64', actual: 'mac-arm64' },
  ];

  let created = 0;
  let skipped = 0;
  let failures = 0;

  for (const m of mappings) {
    const actualPath = path.join(addonPath, m.actual);
    const expectedPath = path.join(addonPath, m.expected);

    if (!fs.existsSync(actualPath)) {
      skipped++;
      console.log(`[fix-whisper-paths] ${m.actual} not present → skip (${m.arch}).`);
      continue;
    }

    // If expected already exists, ensure it's a symlink pointing to the correct target.
    if (fs.existsSync(expectedPath)) {
      try {
        const stat = fs.lstatSync(expectedPath);
        if (stat.isSymbolicLink()) {
          const currentTarget = fs.readlinkSync(expectedPath);
          if (currentTarget === m.actual) {
            console.log(`[fix-whisper-paths] ${m.expected} already correct.`);
            continue; // nothing to do
          }
        }
        // Remove wrong file / wrong symlink
        fs.unlinkSync(expectedPath);
        console.log(`[fix-whisper-paths] Replacing existing ${m.expected}.`);
      } catch (e) {
        failures++;
        console.warn(`[fix-whisper-paths] Could not remove existing ${m.expected}: ${e.message}`);
        continue;
      }
    }

    try {
      fs.symlinkSync(m.actual, expectedPath);
      created++;
      console.log(`✅ [fix-whisper-paths] Created ${m.expected} -> ${m.actual}`);
    } catch (e) {
      failures++;
      console.error(`❌ [fix-whisper-paths] Failed to create ${m.expected} -> ${m.actual}: ${e.message}`);
    }
  }

  console.log(`[fix-whisper-paths] Summary: created=${created}, skipped=${skipped}, failures=${failures}`);
}

if (require.main === module) {
  fixWhisperPaths();
}

module.exports = fixWhisperPaths;
