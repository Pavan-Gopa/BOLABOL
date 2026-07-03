const fs = require('fs');
const path = require('path');

// Ensure the compiled addon resides at build/Release/whisper_vulkan_addon.node (what worker expects)
const buildDir = path.join(__dirname, '..', 'build');
const releaseDir = path.join(buildDir, 'Release');
const targetName = 'whisper_vulkan_addon.node';

function findAddon(dir) {
  if (!fs.existsSync(dir)) return null;
  const entries = fs.readdirSync(dir);
  for (const e of entries) {
    const p = path.join(dir, e);
    if (e === targetName) return p;
    try {
      const stat = fs.statSync(p);
      if (stat.isDirectory()) {
        const nested = findAddon(p);
        if (nested) return nested;
      }
    } catch {}
  }
  return null;
}

function copyIfExists(srcDir, files, destDir) {
  for (const f of files) {
    const src = path.join(srcDir, f);
    if (fs.existsSync(src)) {
      const dst = path.join(destDir, f);
      fs.mkdirSync(path.dirname(dst), { recursive: true });
      if (f === 'MoltenVK_icd.json') {
        try {
          const raw = fs.readFileSync(src, 'utf8');
          const j = JSON.parse(raw);
          if (j && j.ICD) { j.ICD.library_path = 'libMoltenVK.dylib'; }
          fs.writeFileSync(dst, JSON.stringify(j, null, 2));
          console.log('[post-build-copy] Copied and normalized MoltenVK_icd.json');
        } catch (e) {
          fs.copyFileSync(src, dst);
          console.warn('[post-build-copy] Copied MoltenVK_icd.json without normalization:', e?.message || e);
        }
      } else {
        fs.copyFileSync(src, dst);
        console.log(`[post-build-copy] Copied ${f}`);
      }
    }
  }
}

function main() {
  const found = findAddon(buildDir);
  if (!fs.existsSync(releaseDir)) fs.mkdirSync(releaseDir, { recursive: true });
  const dest = path.join(releaseDir, targetName);
  if (found && found !== dest) {
    fs.copyFileSync(found, dest);
    console.log(`[post-build-copy] Copied addon to ${dest}`);
  } else if (found) {
    console.log('[post-build-copy] Addon already at expected path.');
  } else {
    console.warn('[post-build-copy] Could not locate built addon .node file.');
  }

  // Copy dependent dylibs next to the addon (for runtime resolution)
  const dylibs = [
    'libwhisper.dylib', 'libwhisper.1.dylib', 'libwhisper.1.7.6.dylib',
    'libggml.dylib', 'libggml-base.dylib', 'libggml-cpu.dylib', 'libggml-blas.dylib', 'libggml-vulkan.dylib',
  ];
  const srcBase = found ? path.dirname(found) : releaseDir;
  copyIfExists(srcBase, dylibs, releaseDir);

  // On macOS, also try to bundle Vulkan loader + MoltenVK runtime from VULKAN_SDK
  if (process.platform === 'darwin') {
    const VULKAN_SDK = process.env.VULKAN_SDK || '';
    if (!VULKAN_SDK) {
      console.warn('[post-build-copy] VULKAN_SDK not set; will try Homebrew/known paths for libvulkan/MoltenVK.');
    } else {
      const candidates = [];
      const sdkLib = path.join(VULKAN_SDK, 'lib');
      const sdkMacLib = path.join(VULKAN_SDK, 'macOS', 'lib');
      // libvulkan variants
      candidates.push({ src: path.join(sdkLib, 'libvulkan.1.dylib'), dst: path.join(releaseDir, 'libvulkan.1.dylib') });
      candidates.push({ src: path.join(sdkLib, 'libvulkan.dylib'),   dst: path.join(releaseDir, 'libvulkan.dylib') });
      candidates.push({ src: path.join(sdkMacLib, 'libvulkan.1.dylib'), dst: path.join(releaseDir, 'libvulkan.1.dylib') });
      candidates.push({ src: path.join(sdkMacLib, 'libvulkan.dylib'),   dst: path.join(releaseDir, 'libvulkan.dylib') });

      // MoltenVK dylib and ICD json in typical LunarG SDK layout
      const moltenRootA = path.join(VULKAN_SDK, '..', 'MoltenVK');
      const moltenRootB = path.join(VULKAN_SDK, 'MoltenVK');
      const moltenRoots = [moltenRootA, moltenRootB];
      for (const root of moltenRoots) {
        candidates.push({ src: path.join(root, 'dylib', 'macOS', 'libMoltenVK.dylib'), dst: path.join(releaseDir, 'libMoltenVK.dylib') });
        candidates.push({ src: path.join(root, 'icd', 'MoltenVK_icd.json'),            dst: path.join(releaseDir, 'MoltenVK_icd.json') });
      }

      let copiedAny = false;
      for (const { src, dst } of candidates) {
        try {
          if (fs.existsSync(src)) {
            fs.mkdirSync(path.dirname(dst), { recursive: true });
            if (path.basename(dst) === 'MoltenVK_icd.json') {
              try {
                const raw = fs.readFileSync(src, 'utf8');
                const j = JSON.parse(raw);
                if (j && j.ICD) { j.ICD.library_path = 'libMoltenVK.dylib'; }
                fs.writeFileSync(dst, JSON.stringify(j, null, 2));
                console.log(`[post-build-copy] Bundled normalized MoltenVK_icd.json -> ${dst}`);
              } catch (e) {
                fs.copyFileSync(src, dst);
                console.warn('[post-build-copy] Bundled MoltenVK_icd.json without normalization:', e?.message || e);
              }
            } else {
              fs.copyFileSync(src, dst);
              console.log(`[post-build-copy] Bundled ${path.basename(src)} -> ${dst}`);
            }
            copiedAny = true;
          }
        } catch (e) {
          console.warn(`[post-build-copy] Failed to copy ${src}: ${e?.message}`);
        }
      }
      if (!copiedAny) console.warn('[post-build-copy] Could not find Vulkan loader/MoltenVK files under VULKAN_SDK.');
    }

    // Also scan common Homebrew locations and system-wide typical installs
    const knownRoots = [
      '/opt/homebrew/opt',
      '/usr/local/opt',
      '/opt/homebrew/Cellar',
      '/usr/local/Cellar',
      '/usr/local/lib',
      '/opt/homebrew/lib',
    ];
    const candidates = [];
    for (const root of knownRoots) {
      // libMoltenVK
      candidates.push(path.join(root, 'molten-vk', 'lib', 'libMoltenVK.dylib'));
      candidates.push(path.join(root, 'MoltenVK', 'dylib', 'macOS', 'libMoltenVK.dylib'));
      candidates.push(path.join(root, 'libMoltenVK.dylib'));
      // ICD json
      candidates.push(path.join(root, 'molten-vk', 'share', 'vulkan', 'icd.d', 'MoltenVK_icd.json'));
      candidates.push(path.join(root, 'MoltenVK', 'icd', 'MoltenVK_icd.json'));
    }
    let copiedBrew = false;
    for (const src of candidates) {
      try {
        if (fs.existsSync(src)) {
          const base = path.basename(src);
          const dst = path.join(releaseDir, base);
          if (base === 'MoltenVK_icd.json') {
            try {
              const raw = fs.readFileSync(src, 'utf8');
              const j = JSON.parse(raw);
              if (j && j.ICD) { j.ICD.library_path = 'libMoltenVK.dylib'; }
              fs.writeFileSync(dst, JSON.stringify(j, null, 2));
              console.log(`[post-build-copy] Bundled normalized MoltenVK_icd.json from system: ${src} -> ${dst}`);
            } catch (e) {
              fs.copyFileSync(src, dst);
              console.warn('[post-build-copy] Bundled system MoltenVK_icd.json without normalization:', e?.message || e);
            }
          } else {
            fs.copyFileSync(src, dst);
            console.log(`[post-build-copy] Bundled from system: ${src} -> ${dst}`);
          }
          copiedBrew = true;
        }
      } catch {}
    }
    if (!copiedBrew) {
      console.warn('[post-build-copy] MoltenVK not found in Homebrew/system paths. If Vulkan is required, set VULKAN_SDK before building.');
    }

    // As a last resort: if we have libMoltenVK.dylib but no MoltenVK_icd.json, synthesize a minimal ICD file
    try {
      const moltenPath = path.join(releaseDir, 'libMoltenVK.dylib');
      const icdPath = path.join(releaseDir, 'MoltenVK_icd.json');
      if (fs.existsSync(moltenPath) && !fs.existsSync(icdPath)) {
        const icd = {
          file_format_version: '1.0.0',
          ICD: {
            library_path: 'libMoltenVK.dylib',
            api_version: '1.3.0'
          }
        };
        fs.writeFileSync(icdPath, JSON.stringify(icd, null, 2));
        console.log('[post-build-copy] Synthesized MoltenVK_icd.json next to libMoltenVK.dylib');
      }
    } catch (e) {
      console.warn('[post-build-copy] Failed to synthesize MoltenVK_icd.json:', e?.message || e);
    }
  }
}

main();
