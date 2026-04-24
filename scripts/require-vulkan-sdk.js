#!/usr/bin/env node
// Fail fast if Vulkan SDK is not configured when building mac x64, to avoid bundling the stub addon.
const os = require('os');
const path = require('path');

const isDarwin = process.platform === 'darwin';
const arch = process.arch;
// Only enforce for mac x64 builds
if (!(isDarwin && arch === 'x64')) {
  process.exit(0);
}

const env = process.env;
const hasSDK = !!(env.VULKAN_SDK || env.VULKAN_SDK_ROOT);
if (!hasSDK) {
  console.error('[require-vulkan-sdk] VULKAN_SDK not set. Building will package a stub Vulkan addon that cannot transcribe.');
  console.error('Set VULKAN_SDK and rebuild, e.g.:');
  console.error('  export VULKAN_SDK="/path/to/vulkansdk/macOS"');
  process.exit(1);
}

console.log('[require-vulkan-sdk] Vulkan SDK detected at', env.VULKAN_SDK || env.VULKAN_SDK_ROOT);
process.exit(0);
