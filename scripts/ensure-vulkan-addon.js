// Ensure the Vulkan addon is present and not a stub in dev on mac x64.
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

function log(msg) { console.log(`[ensure-vulkan-addon] ${msg}`); }
function warn(msg) { console.warn(`[ensure-vulkan-addon] ${msg}`); }

function hasTranscribe(mod) {
  return mod && typeof mod.transcribe === 'function';
}

function main() {
  if (process.platform !== 'darwin' || process.arch !== 'x64') return; // only care on Intel mac
  const addonPath = path.join(__dirname, '..', 'native', 'whisper-vulkan-addon', 'build', 'Release', 'whisper_vulkan_addon.node');
  let mod = null;
  try { mod = require(addonPath); } catch (e) {
    warn(`Addon not found at ${addonPath}`);
  }
  if (hasTranscribe(mod)) { log('Vulkan addon OK.'); return; }
  const sdk = process.env.VULKAN_SDK || process.env.VULKAN_SDK_ROOT;
  if (!sdk) { warn('Vulkan SDK not set; skipping auto-build. Set VULKAN_SDK before running dev to enable Vulkan.'); return; }
  log(`Attempting to build Vulkan addon using VULKAN_SDK=${sdk} ...`);
  const r = spawnSync('npm', ['run', 'build'], { cwd: path.join(__dirname, '..', 'native', 'whisper-vulkan-addon'), stdio: 'inherit', shell: true });
  if (r.status !== 0) { warn('Vulkan addon build failed.'); return; }
  try { delete require.cache[require.resolve(addonPath)]; } catch {}
  try { mod = require(addonPath); } catch {}
  if (hasTranscribe(mod)) { log('Vulkan addon built successfully.'); }
  else { warn('Vulkan addon still missing transcribe after build.'); }
}

main();
