/**
 * SmartScribe Whisper worker (Vulkan/Metal/CPU)
 * Backend: @kutalia/whisper-node-addon
 * - explicit model download only (install_model), no auto-download anywhere
 * - batch transcribe via fname_inp or PCM->WAV
 */

'use strict';

const path  = require('path');
const fs    = require('fs');
const os    = require('os');
const https = require('https');
const Module = require('module');

let whisper = null;
let whisperBackendTag = null; // 'vulkan' | null (used to override engine labeling when using our custom addon)
let vulkanRuntimeReady = false; // true only if MoltenVK is present and ICD is configured
let _vulkanWarnedOnce = false;

// ---------- logging ----------
const LV = { error:0, warn:1, info:2, debug:3 };
let curLvl = LV.warn; // default quieter; will be updated by main
const shouldLog = (l) => (LV[l] ?? 3) <= curLvl;
function logx(l, msg, ...args) {
  if (!shouldLog(l)) return;
  const line = `[Transcription Worker] ${msg}`;
  if (l === 'error') console.error(line, ...args);
  else if (l === 'warn') console.warn(line, ...args);
  else console.log(line, ...args);
  if (process.send) { try { process.send({ type:'log', level:l, message:String(msg), args }); } catch {} }
}

// BOOT
console.log(`[Transcription Worker BOOT] pid=${process.pid}`);
console.log(`[Transcription Worker] Attempting to load whisper addon(s)`);

const FORCE_BACKEND = (process.env.SMARTSCRIBE_FORCE_BACKEND || '').trim().toLowerCase();
const REQUIRE_VULKAN = /^(1|true|yes)$/i.test(String(process.env.SMARTSCRIBE_REQUIRE_VULKAN || ''));
if (FORCE_BACKEND) console.log(`[Transcription Worker] FORCE backend requested: ${FORCE_BACKEND}`);
const FORCE_THREADS_ENV = (() => { const v = parseInt(process.env.SMARTSCRIBE_FORCE_THREADS || '', 10); return Number.isFinite(v) && v > 0 ? v : null; })();
if (FORCE_THREADS_ENV) console.log(`[Transcription Worker] FORCE threads=${FORCE_THREADS_ENV}`);

function resolveKutaliaBinaryPath(requestPath) {
  if (!requestPath || typeof requestPath !== 'string') return requestPath;

  const candidates = new Set([requestPath]);

  if (requestPath.includes('app.asar')) {
    candidates.add(requestPath.replace('app.asar', 'app.asar.unpacked'));
  }

  if (requestPath.includes(`${path.sep}darwin-`)) {
    candidates.add(requestPath.replace(`${path.sep}darwin-`, `${path.sep}mac-`));
    if (requestPath.includes('app.asar')) {
      candidates.add(
        requestPath
          .replace('app.asar', 'app.asar.unpacked')
          .replace(`${path.sep}darwin-`, `${path.sep}mac-`)
      );
    }
  }

  for (const candidate of candidates) {
    try {
      if (candidate && fs.existsSync(candidate)) {
        return candidate;
      }
    } catch {}
  }

  return requestPath;
}

function prepareKutaliaAddonEnvironment(addonPath) {
  if (!addonPath || process.platform !== 'darwin') return;
  try {
    const dir = path.dirname(addonPath);
    const prev = process.env.DYLD_LIBRARY_PATH || '';
    const parts = prev ? prev.split(':') : [];
    if (!parts.includes(dir)) {
      process.env.DYLD_LIBRARY_PATH = dir + (prev ? ':' + prev : '');
    }

    const fallbackPrev = process.env.DYLD_FALLBACK_LIBRARY_PATH || '';
    const fallbackParts = fallbackPrev ? fallbackPrev.split(':') : [];
    if (!fallbackParts.includes(dir)) {
      process.env.DYLD_FALLBACK_LIBRARY_PATH = dir + (fallbackPrev ? ':' + fallbackPrev : '');
    }

    try {
      const resourcesDir = path.dirname(__dirname);
      const frameworksDir = path.join(path.dirname(resourcesDir), 'Frameworks');
      const resourcesFrameworksDir = path.join(resourcesDir, 'Frameworks');

      const mirrorArm64Dylibs = () => {
        try {
          fs.mkdirSync(frameworksDir, { recursive: true });
          fs.mkdirSync(path.join(frameworksDir, 'mac-arm64'), { recursive: true });
        } catch {}

        const sourceDirs = [
          path.join(resourcesFrameworksDir, 'mac-arm64'),
          path.join(resourcesFrameworksDir, 'darwin-arm64'),
        ];

        for (const sourceDir of sourceDirs) {
          if (!fs.existsSync(sourceDir)) continue;
          try {
            const entries = fs.readdirSync(sourceDir).filter((name) => name.endsWith('.dylib'));
            for (const name of entries) {
              const src = path.join(sourceDir, name);
              const dest = path.join(frameworksDir, name);
              const archDest = path.join(frameworksDir, 'mac-arm64', name);
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
          } catch (err) {
            console.warn('[Transcription Worker] Failed to mirror dylibs from', sourceDir, err?.message || err);
          }
        }

        try {
          const aliasDir = path.join(frameworksDir, 'darwin-arm64');
          if (fs.existsSync(aliasDir)) fs.rmSync(aliasDir, { recursive: true, force: true });
          fs.symlinkSync('mac-arm64', aliasDir);
        } catch {}
      };

      mirrorArm64Dylibs();

      const addToEnv = (pathToAdd, key) => {
        const current = process.env[key] || '';
        const list = current ? current.split(':') : [];
        if (!list.includes(pathToAdd)) {
          process.env[key] = pathToAdd + (current ? ':' + current : '');
        }
      };

      addToEnv(frameworksDir, 'DYLD_LIBRARY_PATH');
      addToEnv(frameworksDir, 'DYLD_FALLBACK_LIBRARY_PATH');

      const envDirs = [
        path.join(frameworksDir, 'mac-arm64'),
        path.join(frameworksDir, 'darwin-arm64'),
        dir,
      ];

      for (const envDir of envDirs) {
        if (!fs.existsSync(envDir)) continue;
        addToEnv(envDir, 'DYLD_LIBRARY_PATH');
        addToEnv(envDir, 'DYLD_FALLBACK_LIBRARY_PATH');
      }
    } catch {}
  } catch (err) {
    console.warn('[Transcription Worker] Failed to prepare DYLD paths for addon:', err?.message || err);
  }
}

function loadKutaliaAddonSafely() {
  const originalLoad = Module._load;
  const patchedLoad = function patched(request, parent, isMain) {
    if (typeof request === 'string' && request.endsWith('whisper.node') && request.includes('@kutalia/whisper-node-addon')) {
      const resolved = resolveKutaliaBinaryPath(request);
      prepareKutaliaAddonEnvironment(resolved);
      return originalLoad.call(this, resolved, parent, isMain);
    }
    return originalLoad.call(this, request, parent, isMain);
  };

  Module._load = patchedLoad;
  try {
    return require('@kutalia/whisper-node-addon');
  } finally {
    Module._load = originalLoad;
  }
}

// Strategy:
// 1. On Intel macOS (darwin x64) try our experimental Vulkan addon first (CMake build)
//    path: native/whisper-vulkan-addon/build/Release/whisper_vulkan_addon.node
// 2. Fallback to @kutalia/whisper-node-addon (Metal on Apple Silicon / CPU everywhere)
// This keeps existing behavior intact while enabling Vulkan on AMD/Nvidia Macs via MoltenVK.

function tryLoadVulkanAddon() {
  if (FORCE_BACKEND && FORCE_BACKEND !== 'vulkan') return false; // user forced something else
  if (process.platform !== 'darwin' || process.arch !== 'x64') return false; // only target Intel mac for now
  try {
    const p = require('path');
    const isPackaged = __dirname.includes('app.asar');
    // Dev path (only when not packaged)
    const devPath = isPackaged ? null : p.join(__dirname, 'native', 'whisper-vulkan-addon', 'build', 'Release', 'whisper_vulkan_addon.node');
    // Packaged paths (__dirname inside asar is .../Resources/app.asar)
    let unpackedPath = null, asarPath = null;
    try {
      const resourcesDir = p.dirname(__dirname); // .../Contents/Resources
      unpackedPath = p.join(resourcesDir, 'app.asar.unpacked', 'native', 'whisper-vulkan-addon', 'build', 'Release', 'whisper_vulkan_addon.node');
      asarPath     = p.join(resourcesDir, 'app.asar',        'native', 'whisper-vulkan-addon', 'build', 'Release', 'whisper_vulkan_addon.node');
    } catch {}
    // Strict priority: unpacked first when packaged, then asar (as a last resort/probe), then dev
    const candidates = (isPackaged
      ? [unpackedPath, asarPath]
      : [devPath, unpackedPath, asarPath]
    ).filter(Boolean);
    console.log('[Transcription Worker] Vulkan addon candidates:', candidates);
    let loadedPath = null;
    for (const c of candidates) {
      try { require('fs').accessSync(c); loadedPath = c; break; } catch {}
    }
  if (!loadedPath) { throw new Error('Vulkan addon binary not found in expected paths'); }
    console.log('[Transcription Worker] Probing Vulkan addon at', loadedPath);
    try {
      if (process.platform === 'darwin') {
        const dir = p.dirname(loadedPath);
        const prev = process.env.DYLD_LIBRARY_PATH || '';
        const parts = prev ? prev.split(':') : [];
        const resourcesDir = p.dirname(__dirname); // .../Contents/Resources
        const frameworksDir = p.join(p.dirname(resourcesDir), 'Frameworks');
        const add = [];
        if (!parts.includes(dir)) add.push(dir);
        if (!parts.includes(frameworksDir)) add.push(frameworksDir);
        if (add.length) {
          process.env.DYLD_LIBRARY_PATH = add.join(':') + (prev ? (':' + prev) : '');
          console.log('[Transcription Worker] Set DYLD_LIBRARY_PATH to include', add.join(' '));
        }

        // If MoltenVK ICD JSON is present in Frameworks, set VK_ICD_FILENAMES so the Vulkan loader can find it
        let pickedIcd = null;
        const moltenIcdCandidates = [
          p.join(frameworksDir, 'MoltenVK_icd.json'),
          p.join(frameworksDir, 'vk_swiftshader_icd.json'), // fallback/alt if present
        ];
        for (const icd of moltenIcdCandidates) {
          try {
            require('fs').accessSync(icd);
            process.env.VK_ICD_FILENAMES = icd; pickedIcd = icd;
            console.log('[Transcription Worker] Set VK_ICD_FILENAMES =', icd);
            break;
          } catch {}
        }

        // Emit quick diagnostics for packaged runtime
        try {
          const hasLoader = fs.existsSync(p.join(frameworksDir, 'libvulkan.1.dylib')) || fs.existsSync(p.join(frameworksDir, 'libvulkan.dylib'));
          const hasMolten = fs.existsSync(p.join(frameworksDir, 'libMoltenVK.dylib'));
          console.log('[Transcription Worker] Vulkan runtime in Frameworks -> loader:', hasLoader, 'MoltenVK:', hasMolten);
          // Consider runtime ready only when MoltenVK is present and the selected ICD is MoltenVK
          vulkanRuntimeReady = !!(hasLoader && hasMolten && pickedIcd && /MoltenVK_icd\.json$/.test(pickedIcd));
        } catch {}
      }
    } catch {}
  whisper = require(loadedPath);
  try { console.log('[Transcription Worker] Vulkan addon exports:', Object.keys(whisper || {})); } catch {}
    // quick probe
    if (typeof whisper.getBackend === 'function') {
      const probe = whisper.getBackend();
      if (!probe || probe.engine !== 'vulkan') throw new Error('backend probe mismatch');
    }
    if (typeof whisper.transcribe !== 'function') {
      if (isPackaged) {
        throw new Error('Packaged build loaded stub addon (no transcribe). Packaging likely included the stub. Rebuild addon with VULKAN_SDK and ensure app.asar.unpacked/native/whisper-vulkan-addon/build/Release is used.');
      } else {
        throw new Error('addon stub detected: no transcribe function');
      }
    }
    whisperBackendTag = 'vulkan';
    console.log('[Transcription Worker] Loaded experimental Vulkan addon (Vulkan)');
    return true;
  } catch (e) {
    console.log('[Transcription Worker] Vulkan addon not available:', e?.message);
    whisper = null;
    whisperBackendTag = null;
    return false;
  }
}

let loaded = false;
try { loaded = tryLoadVulkanAddon(); } catch {}

if (!loaded) {
  if (FORCE_BACKEND === 'vulkan') {
    console.warn('[Transcription Worker] Forced backend=vulkan but addon failed to load – will fallback.');
  }
  if (FORCE_BACKEND === 'cpu') {
    console.log('[Transcription Worker] CPU backend forced; skipping GPU addon load attempts.');
  }
  const isDarwinX64 = (process.platform === 'darwin' && process.arch === 'x64');
  const isPackaged = __dirname.includes('app.asar');
  try {
    if (FORCE_BACKEND !== 'cpu') {
      if (isDarwinX64 && isPackaged && REQUIRE_VULKAN) {
        console.warn('[Transcription Worker] SMARTSCRIBE_REQUIRE_VULKAN=1 set; not falling back to CPU addon.');
      } else {
        whisper = loadKutaliaAddonSafely();
        if (process.platform === 'darwin' && process.arch === 'arm64') {
          whisperBackendTag = 'metal';
        }
        console.log('[Transcription Worker] Loaded @kutalia/whisper-node-addon');
      }
    }
  } catch (e) {
    console.error('[Transcription Worker] Failed to load @kutalia/whisper-node-addon:', e?.message);
  }
}

// Optional self-test: verifies Vulkan path can load a tiny model & perform a 1-second silent inference.
// If this fails, we fallback to CPU addon to avoid user-facing failures.
async function selfTestAndMaybeFallback() {
  if (!whisper || whisperBackendTag !== 'vulkan') return;
  try {
    if (!vulkanRuntimeReady) {
      console.warn('[Transcription Worker] Vulkan runtime not ready (MoltenVK/ICD missing). Falling back to CPU addon.');
      try {
        whisper = loadKutaliaAddonSafely();
        whisperBackendTag = (process.platform === 'darwin' && process.arch === 'arm64') ? 'metal' : null;
        console.log('[Transcription Worker] Fallback addon loaded successfully.');
      } catch (f) {
        console.error('[Transcription Worker] Fallback addon load FAILED:', f?.message || f);
      }
      return;
    }
    const forceSkip = process.env.SMARTSCRIBE_SKIP_SELFTEST === '1';
    if (forceSkip) { console.log('[Transcription Worker] Self-test skipped by env'); return; }
    // Determine a smallest available installed model if requested model unknown.
    const candidates = Object.keys(WHISPER_MODELS).sort((a,b)=>a.length-b.length);
    let testModel = null;
    for (const id of candidates) {
      try { const { modelPath } = getModelPaths(id); if (fs.existsSync(modelPath)) { testModel = modelPath; break; } } catch {}
    }
    if (!testModel) {
      console.log('[Transcription Worker] Self-test: no local model found; skipping functional test (will rely on first transcription).');
      return; // can't test without a model
    }
    console.log('[Transcription Worker] Self-test: loading model', path.basename(testModel));
    await whisper.loadModel?.(testModel);
    // 1 second of silence at 16k
    const silent = new Float32Array(16000);
    const res = await whisper.transcribe(testModel, silent, 16000);
    if (!res || typeof res.text !== 'string') throw new Error('unexpected self-test result');
    console.log('[Transcription Worker] Self-test passed (Vulkan backend functional).');
  } catch (e) {
    console.warn('[Transcription Worker] Self-test failed, falling back to CPU addon:', e?.message || e);
    try {
      whisper = loadKutaliaAddonSafely();
      whisperBackendTag = (process.platform === 'darwin' && process.arch === 'arm64') ? 'metal' : null; // CPU/Metal path
      console.log('[Transcription Worker] Fallback addon loaded successfully.');
    } catch (f) {
      console.error('[Transcription Worker] Fallback addon load FAILED:', f?.message || f);
    }
  }
}

// Kick off self-test asynchronously (do not block readiness)
setTimeout(() => { selfTestAndMaybeFallback(); }, 10);

// ---------- config & model map ----------
let MODEL_BASE_DIR = path.join(os.homedir(), '.smartscribe', 'Models');
function ensureDir(p) { try { fs.mkdirSync(p, { recursive:true }); } catch {} }
function toSafeId(id) { return String(id).replace(/[^a-z0-9._-]/gi, '_'); }

const HF_BASE = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/';
// наш Q8-каталог:
const WHISPER_MODELS = {
  'whisper-small-en-q8':       { filename:'ggml-small.en-q8_0.bin',       lang:'en'   },
  'whisper-small-q8':          { filename:'ggml-small-q8_0.bin',          lang:'auto' },
  'whisper-medium-en-q8':      { filename:'ggml-medium.en-q8_0.bin',      lang:'en'   },
  'whisper-large-v3-turbo-q8': { filename:'ggml-large-v3-turbo-q8_0.bin', lang:'auto' },
  'whisper-large-v3-turbo-ru-q8': {
    filename: 'ggml-large-v3-podlodka-q8_0.bin',
    lang: 'ru',
    url: 'https://github.com/sergheinenov/whisper-podlodka-turbo-ggml/releases/download/v1.0.0/ggml-large-v3-podlodka-q8_0.bin'
  },
  'whisper-large-v3-q8': {
    filename: 'ggml-large-v3-q8_0.bin',
    lang: 'auto',
    url: 'https://github.com/sergheinenov/whisper-large-v3-ggml/releases/download/v1.0.0/ggml-large-v3-q8_0.bin'
  },
};

function getModelInfo(modelId) {
  if (WHISPER_MODELS[modelId]) return WHISPER_MODELS[modelId];
  if (/\.bin$/i.test(String(modelId))) return { filename: String(modelId), lang:'auto' };
  return null;
}

function getModelPaths(modelId) {
  const info = getModelInfo(modelId);
  if (!info) throw new Error(`Unknown modelId: ${modelId}`);
  const idSafe = toSafeId(modelId);
  const dir = path.join(MODEL_BASE_DIR, idSafe);
  ensureDir(dir);
  const modelPath = path.isAbsolute(info.filename) ? info.filename : path.join(dir, info.filename);
  return { info, dir, modelPath };
}

// ---------- helpers ----------
function setLogLevel(level) {
  const k = String(level || '').toLowerCase();
  curLvl = LV[k] ?? LV.info;
  // Only emit confirmation at info+ levels
  if (curLvl >= LV.info) logx('info', `Log level set to ${k}`);
}

function downloadFileWithProgress(url, dest, onProgress) {
  ensureDir(path.dirname(dest));
  return new Promise((resolve, reject) => {
    const tmp = dest + '.part';
    const out = fs.createWriteStream(tmp);
    let received = 0, total = 0;

    const handle = (u) => {
      const req = https.get(u, (res) => {
        // redirects
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          res.destroy();
          return handle(res.headers.location);
        }
        if (res.statusCode !== 200) {
          res.resume();
          return reject(new Error(`HTTP ${res.statusCode} for ${u}`));
        }
        total = Number(res.headers['content-length'] || 0);
        res.on('data', (chunk) => {
          received += chunk.length;
          onProgress && onProgress(received, total);
        });
        res.pipe(out);
        out.on('finish', () => out.close(() => {
          try { fs.renameSync(tmp, dest); resolve(dest); } catch (e) { reject(e); }
        }));
      });
      req.on('error', (err) => {
        try { out.close(); } catch {}
        try { fs.unlinkSync(tmp); } catch {}
        reject(err);
      });
    };

    handle(url);
  });
}

// ---------- install_model ----------
async function handleInstallModel(modelId) {
  try {
    const { modelPath, info } = getModelPaths(modelId);
    const filename = path.basename(info?.filename || modelPath);
    const candidateUrl = info?.url || info?.filename;
    const url = (candidateUrl && /^https?:\/\//i.test(candidateUrl)) ? candidateUrl : (HF_BASE + filename);

    if (fs.existsSync(modelPath) && fs.statSync(modelPath).size > 0) {
      logx('info', `Model already exists: ${modelPath}`);
      process.send?.({ type:'download-complete', modelId, path: modelPath });
      return;
    }

    process.send?.({ type:'download-progress', modelId, status:'start', received:0, total:0 });

    await downloadFileWithProgress(url, modelPath, (rec, tot) => {
      const pct = tot > 0 ? Math.round((rec / tot) * 100) : null;
      process.send?.({ type:'download-progress', modelId, status:'progress', received:rec, total:tot, percent:pct });
    });

    process.send?.({ type:'download-complete', modelId, path: modelPath });
    logx('info', `Model downloaded: ${filename}`);
  } catch (err) {
    process.send?.({ type:'download-failed', modelId, error: err?.message || String(err) });
    logx('error', `Model install failed: ${err?.message || err}`);
  }
}

// ---------- transcribe ----------
function normalizeResult(res, { useGpu }) {
  let segments = [];
  if (Array.isArray(res?.segments)) segments = res.segments;
  else if (Array.isArray(res?.transcription)) segments = res.transcription.map(([t0, t1, text]) => ({ t0, t1, text }));
  const stitched = segments.map(s => s?.text || '').join(' ').trim();
  const text = (typeof res?.text === 'string' && res.text.trim()) ? res.text.trim() : stitched;

  const raw = String(res?.engine || res?.backend || '').toLowerCase();
  const pick = (s) => s && s.trim().toLowerCase();
  const has = (k) => raw.includes(k);
  let engine = 'cpu';

  if (whisperBackendTag === 'vulkan') engine = (vulkanRuntimeReady ? 'vulkan' : 'cpu');
  else if (has('vulkan') || has('vk')) engine = 'vulkan';
  else if (has('metal') || has('mtl')) engine = 'metal';
  else if (has('cuda') || has('cublas')) engine = 'cuda';
  else if (has('rocm') || has('hip')) engine = 'rocm';
  else if (has('openvino')) engine = 'openvino';
  else if (has('directml') || has('dml')) engine = 'directml';
  else if (has('gpu')) engine = (process.platform === 'darwin' ? 'metal' : 'vulkan');
  else if (useGpu) engine = (process.platform === 'darwin' ? 'metal' : 'vulkan');
  // else remains 'cpu'

  if (whisperBackendTag === 'vulkan' && !vulkanRuntimeReady && !_vulkanWarnedOnce) {
    _vulkanWarnedOnce = true;
    logx('warn', 'Vulkan addon loaded but runtime not ready (MoltenVK missing) – reporting CPU.');
  }
  return { text, segments, engine };
}

function float32ToWav(f32, sr, outPath) {
  const n = f32.length;
  const b = Buffer.alloc(44 + n * 2);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * 2, 4); b.write('WAVE', 8);
  b.write('fmt ', 12); b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20);
  b.writeUInt16LE(1, 22); b.writeUInt32LE(sr, 24); b.writeUInt32LE(sr * 2, 28);
  b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(n * 2, 40);
  let o = 44;
  for (let i = 0; i < n; i++) {
    let s = Math.max(-1, Math.min(1, f32[i]));
    s = s < 0 ? s * 0x8000 : s * 0x7FFF;
    b.writeInt16LE(s, o); o += 2;
  }
  fs.writeFileSync(outPath, b);
  return outPath;
}

async function handleTranscribe(msg) {
  try {
    if (!whisper) throw new Error('Addon not available');
    const { modelId, audioData, options } = msg;
    const { modelPath } = getModelPaths(modelId);
    if (!fs.existsSync(modelPath)) throw new Error(`Model not installed: ${modelId}`);
  const cores = Math.max(1, (os.cpus?.().length || 1));
  const useGpu  = options?.forceCpu ? false : true;
  const threads = FORCE_THREADS_ENV || (options?.threads > 0 ? options.threads : cores);
  // if model is *_en* restrict to 'en', otherwise allow 'auto' by default
  const modelLang = getModelInfo(modelId)?.lang || 'auto';
  const language = options?.language || modelLang;
  const translate = !!options?.translate;

    let wavPath = null, tmp = false;

    // Debug audio data
    logx('debug', `handleTranscribe: audioData type=${typeof audioData}, isBuffer=${Buffer.isBuffer(audioData)}, hasBuffer=${!!audioData?.buffer}, byteLength=${audioData?.byteLength || audioData?.length || 'undefined'}`);
    if (audioData && typeof audioData === 'object') {
      logx('debug', `audioData keys: ${Object.keys(audioData)}, type=${audioData?.type}, dataLength=${audioData?.data?.length}`);
    }

    if (options?.fname_inp && fs.existsSync(options.fname_inp)) {
      wavPath = options.fname_inp;
    } else if (audioData && (audioData.byteLength > 0 || audioData.length > 0 || Buffer.isBuffer(audioData) || (audioData.type === 'Buffer' && audioData.data))) {
      // Handle different audioData formats from IPC
      let f32 = null;
      if (Buffer.isBuffer(audioData)) {
        // Direct Buffer from main.js
        f32 = new Float32Array(audioData.buffer, audioData.byteOffset, audioData.byteLength/4);
      } else if (audioData?.type === 'Buffer' && Array.isArray(audioData.data)) {
        // Serialized Buffer from IPC: { type: 'Buffer', data: [...] }
        const buf = Buffer.from(audioData.data);
        f32 = new Float32Array(buf.buffer, buf.byteOffset, buf.byteLength/4);
      } else if (audioData?.buffer) {
        // TypedArray with buffer property
        f32 = new Float32Array(audioData.buffer, audioData.byteOffset || 0, audioData.byteLength/4 || audioData.length);
      } else if (Array.isArray(audioData)) {
        // Plain array of bytes
        const buf = Buffer.from(audioData);
        f32 = new Float32Array(buf.buffer, buf.byteOffset, buf.byteLength/4);
      }

      if (!f32 || f32.length === 0) throw new Error('Could not convert audioData to Float32Array');

      // Quick amplitude diagnostic to catch silence early
      try {
        let sum=0, peak=0; for (let i=0;i<f32.length;i++){ const v=f32[i]; sum+=v*v; const a=Math.abs(v); if(a>peak) peak=a; }
        const rms = Math.sqrt(sum/Math.max(1,f32.length));
        logx('debug', `PCM diag: frames=${f32.length} rms=${rms.toFixed(6)} peak=${peak.toFixed(6)} sr=${options?.sourceSampleRate || 16000}`);
      } catch {}

      // Prefer direct PCM → addon call when available (avoids temp file path issues)
      if (whisperBackendTag === 'vulkan' && typeof whisper?.loadModel === 'function' && typeof whisper?.transcribe === 'function') {
        try {
          // Ensure model is loaded for Mode A in our Vulkan addon
          try { whisper.loadModel(modelPath); } catch {}
          logx('info', `whisper.transcribe (PCM direct) → model=${path.basename(modelPath)} sr=${options?.sourceSampleRate || 16000}`);
          const t0d = Date.now();
          const rawDirect = await whisper.transcribe(modelPath, f32, options?.sourceSampleRate || 16000);
          const dtd = Date.now() - t0d;
          let normDirect = normalizeResult(rawDirect, { useGpu: true });
          normDirect.durationMs = dtd;
          normDirect.threads = threads;
          if (!normDirect.text) throw new Error('Empty transcription result');
          process.send?.({ type:'transcription-complete', id: msg.id, result: normDirect });
          return; // done
        } catch (directErr) {
          logx('warn', `Direct PCM transcribe failed or unsupported; falling back to temp WAV: ${directErr?.message || directErr}`);
        }
      }

      // Fallback: write a temp WAV and use file path (works for both addons)
      const tmpDir = os.tmpdir();
      const out = path.join(tmpDir, `ss-${Date.now()}-${Math.random().toString(36).slice(2)}.wav`);
      float32ToWav(f32, options?.sourceSampleRate || 16000, out);
      wavPath = out; tmp = true;
      logx('debug', `Created temp WAV: ${out}, tmpdir=${tmpDir}, samples=${f32.length}`);
    } else {
      throw new Error('No audio provided');
    }

  const base = { fname_inp: wavPath, model: modelPath, language, task: translate ? 'translate' : 'transcribe', translate, use_gpu: useGpu, threads };
  logx('info', `whisper.transcribe → model=${path.basename(modelPath)} use_gpu=${useGpu} threads=${threads} lang=${language}`);
  const t0 = Date.now();
  let raw = await whisper.transcribe(base);
  const dt = Date.now() - t0;
  let norm = normalizeResult(raw, { useGpu });
  norm.durationMs = dt;
  norm.threads = threads;

    if (tmp) { try { fs.unlinkSync(wavPath); } catch {} }

    if (!norm.text) throw new Error('Empty transcription result');
    process.send?.({ type:'transcription-complete', id: msg.id, result: norm });
  } catch (e) {
    logx('error', `transcribe failed: ${e?.message || e}`);
    process.send?.({ type:'transcription-error', id: msg.id, error: e?.message || String(e) });
  }
}

async function handleTranscribeOgg(msg) {
  try {
    if (!whisper) throw new Error('Addon not available');
    const { modelId, oggData, options } = msg;
    const { modelPath } = getModelPaths(modelId);
    if (!fs.existsSync(modelPath)) throw new Error(`Model not installed: ${modelId}`);

  const cores = Math.max(1, (os.cpus?.().length || 1));
  const useGpu  = options?.forceCpu ? false : true;
  const threads = FORCE_THREADS_ENV || (options?.threads > 0 ? options.threads : cores);
  const modelLang = getModelInfo(modelId)?.lang || 'auto';
  const language = options?.language || modelLang;
  const translate = !!options?.translate;

    // Handle different oggData formats from IPC
    let oggBuffer = null;
    if (Buffer.isBuffer(oggData)) {
      oggBuffer = oggData;
    } else if (oggData?.type === 'Buffer' && Array.isArray(oggData.data)) {
      oggBuffer = Buffer.from(oggData.data);
    } else if (oggData?.buffer) {
      oggBuffer = Buffer.from(oggData.buffer, oggData.byteOffset || 0, oggData.byteLength || oggData.length);
    } else if (Array.isArray(oggData)) {
      oggBuffer = Buffer.from(oggData);
    }

    if (!oggBuffer || !oggBuffer.length) {
      logx('debug', `oggData type=${typeof oggData}, isBuffer=${Buffer.isBuffer(oggData)}, hasBuffer=${!!oggData?.buffer}, byteLength=${oggData?.byteLength || oggData?.length || 'undefined'}`);
      throw new Error('No OGG data provided');
    }

    logx('debug', `OGG buffer created: ${oggBuffer.length} bytes`);

    // Save OGG to temp file and transcribe directly with Whisper.cpp (natively supported)
    const oggTempPath = path.join(os.tmpdir(), `ss-ogg-${Date.now()}-${Math.random().toString(36).slice(2)}.ogg`);
    fs.writeFileSync(oggTempPath, oggBuffer);
    
    try {
      // Direct OGG transcription (natively supported by Whisper.cpp)
  const base = { fname_inp: oggTempPath, model: modelPath, language, task: translate ? 'translate' : 'transcribe', translate, use_gpu: useGpu, threads };
      logx('info', `whisper.transcribe (OGG) → model=${path.basename(modelPath)} use_gpu=${useGpu} threads=${threads} lang=${language}`);
  const t0 = Date.now();
  let raw = await whisper.transcribe(base);
  const dt = Date.now() - t0;
  let norm = normalizeResult(raw, { useGpu });
  norm.durationMs = dt;
  norm.threads = threads;
      
      // Clean up temp file
      try { fs.unlinkSync(oggTempPath); } catch {}
      
      if (!norm.text) throw new Error('Empty transcription result');
      process.send?.({ type:'transcription-complete', id: msg.id, result: norm });
      
    } catch (whisperError) {
      logx('error', `OGG transcription failed: ${whisperError?.message}`);
      // Clean up temp file
      try { fs.unlinkSync(oggTempPath); } catch {}
      throw whisperError;
    }

  } catch (e) {
    logx('error', `OGG transcribe failed: ${e?.message || e}`);
    process.send?.({ type:'transcription-error', id: msg.id, error: e?.message || String(e) });
  }
}

async function handleTranscribeWebM(msg) {
  try {
    if (!whisper) throw new Error('Addon not available');
    const { modelId, webmData, options } = msg;
    const { modelPath } = getModelPaths(modelId);
    if (!fs.existsSync(modelPath)) throw new Error(`Model not installed: ${modelId}`);

  const cores = Math.max(1, (os.cpus?.().length || 1));
  const useGpu  = options?.forceCpu ? false : true;
  const threads = FORCE_THREADS_ENV || (options?.threads > 0 ? options.threads : cores);
  const modelLang = getModelInfo(modelId)?.lang || 'auto';
  const language = options?.language || modelLang;
  const translate = !!options?.translate;

    let wavPath = null, tmp = false;

    // Handle different webmData formats from IPC
    let webmBuffer = null;
    if (Buffer.isBuffer(webmData)) {
      webmBuffer = webmData;
    } else if (webmData?.type === 'Buffer' && Array.isArray(webmData.data)) {
      // Serialized Buffer from IPC
      webmBuffer = Buffer.from(webmData.data);
    } else if (webmData?.buffer) {
      // TypedArray
      webmBuffer = Buffer.from(webmData.buffer, webmData.byteOffset || 0, webmData.byteLength || webmData.length);
    } else if (Array.isArray(webmData)) {
      // Plain array
      webmBuffer = Buffer.from(webmData);
    }

    if (!webmBuffer || !webmBuffer.length) {
      logx('debug', `webmData type=${typeof webmData}, isBuffer=${Buffer.isBuffer(webmData)}, hasBuffer=${!!webmData?.buffer}, byteLength=${webmData?.byteLength || webmData?.length || 'undefined'}`);
      throw new Error('No WebM data provided');
    }

    logx('debug', `WebM buffer created: ${webmBuffer.length} bytes`);

    // For now, save WebM to temp file and let Whisper handle it directly
    // Whisper.cpp with newer versions can handle WebM format
    const webmTempPath = path.join(os.tmpdir(), `ss-webm-${Date.now()}-${Math.random().toString(36).slice(2)}.webm`);
    fs.writeFileSync(webmTempPath, webmBuffer);
    
    try {
      // Try direct WebM transcription first
  const base = { fname_inp: webmTempPath, model: modelPath, language, task: translate ? 'translate' : 'transcribe', translate, use_gpu: useGpu, threads };
      logx('info', `whisper.transcribe (WebM) → model=${path.basename(modelPath)} use_gpu=${useGpu} threads=${threads} lang=${language}`);
  const t0 = Date.now();
  let raw = await whisper.transcribe(base);
  const dt = Date.now() - t0;
  let norm = normalizeResult(raw, { useGpu });
  norm.durationMs = dt;
  norm.threads = threads;
      
      // Clean up temp file
      try { fs.unlinkSync(webmTempPath); } catch {}
      
      if (!norm.text) throw new Error('Empty transcription result');
      process.send?.({ type:'transcription-complete', id: msg.id, result: norm });
      
    } catch (whisperError) {
      logx('warn', `Direct WebM transcription failed: ${whisperError?.message}. WebM format may not be supported by this Whisper version.`);
      // Clean up temp file
      try { fs.unlinkSync(webmTempPath); } catch {}
      throw new Error('WebM format not supported by current Whisper installation. Please use WAV format or update Whisper.');
    }

  } catch (e) {
    logx('error', `WebM transcribe failed: ${e?.message || e}`);
    process.send?.({ type:'transcription-error', id: msg.id, error: e?.message || String(e) });
  }
}

// ---------- IPC ----------
process.on('message', async (m) => {
  try {
    const t = m?.type;
    if (!t) return;
    logx('debug', `IPC message: ${t}`);
    switch (t) {
      case 'set_log_level': setLogLevel(m.payload?.level); return;
      case 'set_base_dir':  if (m.baseDir) { MODEL_BASE_DIR = m.baseDir; ensureDir(MODEL_BASE_DIR); logx('info', `Model base dir: ${MODEL_BASE_DIR}`); } return;
      case 'install_model': return handleInstallModel(m.modelId);
      case 'transcribe':    return handleTranscribe(m);
      case 'transcribeOgg': return handleTranscribeOgg(m);
      case 'transcribeWebM': return handleTranscribeWebM(m);
      case 'dispose':       logx('info','Dispose requested by main, exiting…'); process.exit(0); return;
      default:              logx('warn', `Unknown message type: ${t}`); return;
    }
  } catch (e) {
    logx('error', `Worker message handling failed: ${e?.message || e}`);
  }
});

logx('info', 'Whisper worker ready.');
process.on('SIGTERM', () => { logx('info','SIGTERM, exit'); process.exit(0); });
process.on('SIGINT',  () => { logx('info','SIGINT, exit'); process.exit(0); });
process.on('uncaughtException', (e) => { logx('error','uncaughtException', e); process.exit(1); });
process.on('unhandledRejection', (r) => { logx('error','unhandledRejection', r); });
