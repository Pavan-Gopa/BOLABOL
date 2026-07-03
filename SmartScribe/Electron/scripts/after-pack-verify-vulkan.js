/*
  Ensures Vulkan runtime (libvulkan + MoltenVK + ICD) are present in the packaged app under Contents/Frameworks on macOS.
  If VULKAN_SDK is present, copies missing files from it. Otherwise, fails the build with a clear message.
*/

const fs = require('fs');
const path = require('path');

/**
 * Electron Builder afterPack hook
 * @param {import('electron-builder').AfterPackContext} context
 */
function ensureWhisperDylibs(context) {
  try {
    const appOutDir = context.appOutDir;
    const contentsDir = path.join(appOutDir, 'Contents');
    const resourcesDir = path.join(contentsDir, 'Resources');
    const frameworksDir = path.join(contentsDir, 'Frameworks');
    const resourcesFrameworksDir = path.join(resourcesDir, 'Frameworks');

    const macArmSrc = path.join(resourcesFrameworksDir, 'mac-arm64');
    if (!fs.existsSync(macArmSrc)) return;

    const macArmDest = path.join(frameworksDir, 'mac-arm64');
    const darwinAlias = path.join(frameworksDir, 'darwin-arm64');

    try { fs.mkdirSync(macArmDest, { recursive: true }); } catch {}

    const entries = fs.readdirSync(macArmSrc).filter((name) => name.endsWith('.dylib'));
    for (const name of entries) {
      const src = path.join(macArmSrc, name);
      const dest = path.join(frameworksDir, name);
      const archDest = path.join(macArmDest, name);
      try {
        if (!fs.existsSync(dest)) {
          fs.copyFileSync(src, dest);
          try { fs.chmodSync(dest, 0o755); } catch {}
        }
      } catch {}
      try {
        fs.copyFileSync(src, archDest);
      } catch {}
    }

    try {
      if (fs.existsSync(darwinAlias)) fs.rmSync(darwinAlias, { recursive: true, force: true });
      fs.symlinkSync('mac-arm64', darwinAlias);
    } catch {}
  } catch {}
}

exports.default = async function afterPack(context) {
  if (process.platform !== 'darwin') {
    return; // only macOS adjustments
  }

  ensureWhisperDylibs(context);

  const skipForArch = context?.arch && context.arch !== 'x64';
  if (skipForArch || process.env.SMARTSCRIBE_SKIP_VULKAN_BUNDLE === '1') {
    return;
  }

  const appOutDir = context.appOutDir; // e.g. dist/mac/SmartScribe.app/Contents/MacOS/..
  const contentsDir = path.join(appOutDir, 'Contents');
  const frameworksDir = path.join(contentsDir, 'Frameworks');

  const need = [
    'libvulkan.1.dylib',
    'libvulkan.dylib',
    'libMoltenVK.dylib',
    'MoltenVK_icd.json',
  ];

  const missing = need.filter((name) => !fs.existsSync(path.join(frameworksDir, name)));

  if (missing.length === 0) {
    return; // all good
  }

  const sdk = process.env.VULKAN_SDK || process.env.VULKAN_SDK_ROOT || '';
  const tried = [];

  // Candidate locations inside the SDK
  if (sdk) {
    const sdkLib = path.join(sdk, 'lib');
    const sdkShare = path.join(sdk, 'share', 'vulkan', 'icd.d');

    for (const name of missing) {
      let src = null;
      if (name === 'MoltenVK_icd.json') {
        const candidate = path.join(sdkShare, 'MoltenVK_icd.json');
        if (fs.existsSync(candidate)) src = candidate;
        tried.push(candidate);
      } else {
        const candidate = path.join(sdkLib, name);
        if (fs.existsSync(candidate)) src = candidate;
        tried.push(candidate);
      }

      if (src) {
        fs.mkdirSync(frameworksDir, { recursive: true });
        fs.copyFileSync(src, path.join(frameworksDir, name));
      }
    }
  }

  let stillMissing = need.filter((name) => !fs.existsSync(path.join(frameworksDir, name)));

  // Try common Homebrew/system paths as a fallback if some files are still missing
  if (stillMissing.length > 0) {
    const knownRoots = [
      '/opt/homebrew/opt',
      '/usr/local/opt',
      '/opt/homebrew/Cellar',
      '/usr/local/Cellar',
      '/usr/local/lib',
      '/opt/homebrew/lib',
    ];
    const sysCandidates = [];
    for (const root of knownRoots) {
      sysCandidates.push({ name: 'libMoltenVK.dylib', path: path.join(root, 'molten-vk', 'lib', 'libMoltenVK.dylib') });
      sysCandidates.push({ name: 'libMoltenVK.dylib', path: path.join(root, 'MoltenVK', 'dylib', 'macOS', 'libMoltenVK.dylib') });
      sysCandidates.push({ name: 'libMoltenVK.dylib', path: path.join(root, 'libMoltenVK.dylib') });
      sysCandidates.push({ name: 'MoltenVK_icd.json', path: path.join(root, 'molten-vk', 'share', 'vulkan', 'icd.d', 'MoltenVK_icd.json') });
      sysCandidates.push({ name: 'MoltenVK_icd.json', path: path.join(root, 'MoltenVK', 'icd', 'MoltenVK_icd.json') });
    }
    for (const { name, path: src } of sysCandidates) {
      try {
        if (stillMissing.includes(name) && fs.existsSync(src)) {
          fs.copyFileSync(src, path.join(frameworksDir, name));
        }
      } catch {}
    }
    stillMissing = need.filter((name) => !fs.existsSync(path.join(frameworksDir, name)));
  }

  // If libMoltenVK.dylib exists but MoltenVK_icd.json is still missing, synthesize it pointing to the adjacent dylib
  try {
    const hasMolten = fs.existsSync(path.join(frameworksDir, 'libMoltenVK.dylib'));
    const hasIcd = fs.existsSync(path.join(frameworksDir, 'MoltenVK_icd.json'));
    if (hasMolten && !hasIcd) {
      const icd = {
        file_format_version: '1.0.0',
        ICD: { library_path: 'libMoltenVK.dylib', api_version: '1.3.0' }
      };
      fs.writeFileSync(path.join(frameworksDir, 'MoltenVK_icd.json'), JSON.stringify(icd, null, 2));
    }
  } catch {}

  if (stillMissing.length > 0) {
    const msg = [
      'Vulkan runtime files are missing in Contents/Frameworks after packaging:',
      `Missing: ${stillMissing.join(', ')}`,
      sdk
        ? `VULKAN_SDK was set to: ${sdk}\nTried: ${tried.join('\n')}`
        : 'VULKAN_SDK is not set in the packaging environment. Please install the Vulkan SDK and export VULKAN_SDK before building.',
      'You can download the SDK from: https://vulkan.lunarg.com/sdk/home',
    ].join('\n');

    // Fail fast to avoid shipping a broken build
    throw new Error(msg);
  }
};
