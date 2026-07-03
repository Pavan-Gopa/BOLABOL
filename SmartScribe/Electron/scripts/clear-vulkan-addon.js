#!/usr/bin/env node
/**
 * Remove Vulkan runtime artifacts so they are not bundled in mac arm64 builds.
 * Keeps the build directory present so electron-builder file globs remain valid.
 */

const fs = require('fs');
const path = require('path');

const releaseDir = path.join(__dirname, '..', 'native', 'whisper-vulkan-addon', 'build', 'Release');

function emptyDirectory(target) {
  try {
    if (!fs.existsSync(target)) {
      fs.mkdirSync(target, { recursive: true });
      return;
    }

    for (const entry of fs.readdirSync(target)) {
      const next = path.join(target, entry);
      fs.rmSync(next, { recursive: true, force: true });
    }
  } catch (error) {
    console.warn('[clear-vulkan-addon] Unable to clean directory:', error?.message || error);
  }
}

if (require.main === module) {
  emptyDirectory(releaseDir);
  console.log('[clear-vulkan-addon] Cleared Vulkan addon artifacts at', releaseDir);
}

module.exports = emptyDirectory;
