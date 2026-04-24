#!/usr/bin/env node
/**
 * test-whisper.js
 * Standalone smoke test for @kutalia/whisper-node-addon (CPU/GPU)
 *
 * Usage (Windows PowerShell / macOS / Linux):
 *   node test-whisper.js --wav "C:\path\to\audio.wav" --model small-en-q8 --gpu
 *   node test-whisper.js --wav ./audio.wav --model large-v3-q8 --cpu
 *
 * Models (Q8 only):
 *   small-en-q8, small-q8, medium-en-q8, large-v3-turbo-q8, large-v3-q8
 *
 * Notes:
 * - Скрипт сам докачает модель в ./models, если её нет.
 * - По умолчанию включает GPU (--gpu). Чтобы принудительно на CPU — добавь --cpu.
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const whisper = require('@kutalia/whisper-node-addon');

const HF_BASE = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/';

// Short name -> filename + language hint
const MODEL_MAP = {
  'small-en-q8':        { file: 'ggml-small.en-q8_0.bin',        lang: 'en'   },
  'small-q8':           { file: 'ggml-small-q8_0.bin',           lang: 'auto' },
  'medium-en-q8':       { file: 'ggml-medium.en-q8_0.bin',       lang: 'en'   },
  'large-v3-turbo-q8':  { file: 'ggml-large-v3-turbo-q8_0.bin',  lang: 'auto' },
  'large-v3-q8':        { file: 'ggml-large-v3-q8_0.bin',        lang: 'auto' },
};

function parseArgs() {
  const argv = process.argv.slice(2);
  const out = { gpu: false, cpu: false, modelsDir: path.join(process.cwd(), 'models') };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--gpu') out.gpu = true;
    else if (a === '--cpu') out.cpu = true;
    else if (a === '--wav') out.wav = argv[++i];
    else if (a === '--model') out.model = argv[++i];
    else if (a === '--lang') out.lang = argv[++i];          // optional override
    else if (a === '--models-dir') out.modelsDir = argv[++i]; // optional custom dir
    else if (a === '--help' || a === '-h') out.help = true;
  }
  return out;
}

function usage() {
  console.log(`
Usage:
  node test-whisper.js --wav <path-to-wav> --model <short-model> [--gpu|--cpu] [--lang xx] [--models-dir ./models]

Models:
  small-en-q8-bin, small-q8, medium-en-q8, large-v3-turbo-q8, large-v3-q8

Examples:
  node test-whisper.js --wav ./sample.wav --model small-en-q8 --gpu
  node test-whisper.js --wav ./ru.wav --model large-v3-q8 --gpu
  node test-whisper.js --wav ./call.wav --model medium-en-q8 --cpu --lang en
`);
}

function ensureDir(p) { fs.mkdirSync(p, { recursive: true }); }

function downloadFile(url, dest) {
  ensureDir(path.dirname(dest));
  return new Promise((resolve, reject) => {
    const tmp = dest + '.part';
    const file = fs.createWriteStream(tmp);
    const req = https.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        res.destroy();
        return resolve(downloadFile(res.headers.location, dest));
      }
      if (res.statusCode !== 200) {
        res.resume();
        return reject(new Error('HTTP ' + res.statusCode + ' for ' + url));
      }
      res.pipe(file);
      file.on('finish', () => file.close(() => {
        try { fs.renameSync(tmp, dest); resolve(dest); } catch (e) { reject(e); }
      }));
    });
    req.on('error', (err) => {
      try { file.close(); } catch {}
      try { fs.unlinkSync(tmp); } catch {}
      reject(err);
    });
  });
}

(async function main() {
  const args = parseArgs();
  if (args.help || !args.wav || !args.model) {
    usage(); process.exit(args.help ? 0 : 1);
  }
  if (!fs.existsSync(args.wav)) {
    console.error('WAV not found:', args.wav);
    process.exit(2);
  }
  const entry = MODEL_MAP[args.model];
  if (!entry) {
    console.error('Unknown model:', args.model);
    usage();
    process.exit(3);
  }

  ensureDir(args.modelsDir);
  const modelPath = path.join(args.modelsDir, entry.file);
  if (!fs.existsSync(modelPath)) {
    console.log('[download] fetching', entry.file, '→', modelPath);
    const url = HF_BASE + entry.file;
    await downloadFile(url, modelPath);
    console.log('[download] complete');
  }

  const use_gpu = args.cpu ? false : true; // default GPU unless --cpu
  const language = (args.lang || entry.lang || 'auto');

  console.log('[info] WAV:', args.wav);
  console.log('[info] Model:', modelPath);
  console.log('[info] Language:', language);
  console.log('[info] use_gpu:', use_gpu);

  try {
    const t0 = Date.now();
    const res = await whisper.transcribe({
      fname_inp: args.wav,
      model: modelPath,
      language,
      use_gpu
    });
    const ms = Date.now() - t0;
    const engine = res.engine || res.backend || (process.platform === 'darwin' ? 'metal' : (use_gpu ? 'vulkan' : 'cpu'));

    console.log('--- RESULT ---');
    console.log('engine:', engine);
    console.log('elapsed_ms:', ms);
    if (Array.isArray(res.segments)) {
      console.log('segments:', res.segments.length);
      for (const s of res.segments.slice(0, 8)) {
        console.log(`[${s.t0}-${s.t1}] ${s.text}`);
      }
    }
    console.log('text:', (res.text || '').trim());
  } catch (e) {
    console.error('Transcribe failed:', e && e.stack || e);
    process.exit(4);
  }
})().catch((e) => {
  console.error(e && e.stack || e);
  process.exit(5);
});
