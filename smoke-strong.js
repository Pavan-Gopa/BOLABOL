#!/usr/bin/env node
// smoke-strong.js — проверка @kutalia/whisper-node-addon с явными опциями

const fs = require('fs');
const path = require('path');
const https = require('https');
const os = require('os');
const whisper = require('@kutalia/whisper-node-addon');

const HF_BASE = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/';
const MODELS = {
  'small-en-q8':        { file: 'ggml-small.en-q8_0.bin',        lang: 'en'   },
  'small-q8':           { file: 'ggml-small-q8_0.bin',           lang: 'auto' },
  'medium-en-q8':       { file: 'ggml-medium.en-q8_0.bin',       lang: 'en'   },
  'large-v3-turbo-q8':  { file: 'ggml-large-v3-turbo-q8_0.bin',  lang: 'auto' },
  'large-v3-q8':        { file: 'ggml-large-v3-q8_0.bin',        lang: 'auto' },
};

function args() {
  const a = { wav: null, model: 'small-en-q8', modelsDir: path.join(process.cwd(), 'models'), gpu: false, lang: null };
  const av = process.argv.slice(2);
  for (let i = 0; i < av.length; i++) {
    const t = av[i];
    if (t === '--wav') a.wav = av[++i];
    else if (t === '--model') a.model = av[++i];
    else if (t === '--models-dir') a.modelsDir = av[++i];
    else if (t === '--gpu') a.gpu = true;     // по умолчанию CPU
    else if (t === '--lang') a.lang = av[++i];
  }
  return a;
}
function ensureDir(p){ fs.mkdirSync(p, { recursive:true }); }
function dl(url, dest){
  ensureDir(path.dirname(dest));
  return new Promise((resolve, reject) => {
    const tmp = dest + '.part';
    const f = fs.createWriteStream(tmp);
    https.get(url, (res) => {
      if (res.statusCode >=300 && res.statusCode <400 && res.headers.location) {
        res.destroy(); return resolve(dl(res.headers.location, dest));
      }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error(`HTTP ${res.statusCode} for ${url}`)); }
      res.pipe(f); f.on('finish', () => f.close(() => { try { fs.renameSync(tmp, dest); resolve(dest); } catch(e){ reject(e); } }));
    }).on('error', e => { try{f.close();}catch{} try{fs.unlinkSync(tmp);}catch{} reject(e); });
  });
}

(async () => {
  const a = args();
  if (!a.wav) { console.log('Usage: node smoke-strong.js --wav <path.wav> [--model small-en-q8] [--gpu] [--lang en]'); process.exit(1); }
  if (!fs.existsSync(a.wav)) { console.error('WAV not found:', a.wav); process.exit(2); }

  const m = MODELS[a.model];
  if (!m) { console.error('Unknown model:', a.model); process.exit(3); }

  ensureDir(a.modelsDir);
  const modelPath = path.join(a.modelsDir, m.file);
  if (!fs.existsSync(modelPath)) {
    console.log('[download] fetching', m.file);
    await dl(HF_BASE + m.file, modelPath);
    console.log('[download] complete:', modelPath);
  }
  const language = a.lang || m.lang || 'auto';
  const threads = Math.min(8, Math.max(1, os.cpus().length));

  console.log('[info] WAV:', a.wav);
  console.log('[info] Model:', modelPath);
  console.log('[info] Lang:', language, 'task: transcribe');
  console.log('[info] use_gpu:', a.gpu, 'threads:', threads);

  const t0 = Date.now();
  const res = await whisper.transcribe({
    fname_inp: a.wav,
    model: modelPath,
    language,
    task: 'transcribe',     // фиксируем именно расшифровку (не translate)
    threads,                // явно задаём потоки
    temperature: 0.0,       // детерминированность
    // vad_threshold: 0.3,   // при желании можно ослабить/усилить VAD
    use_gpu: a.gpu
  });
  const ms = Date.now() - t0;

  const segs = Array.isArray(res?.segments) ? res.segments : [];
  const stitched = segs.map(s => s.text).join(' ').trim();
  const text = (res?.text && res.text.trim()) ? res.text.trim() : stitched;
  const engine = res?.engine || res?.backend || (process.platform === 'darwin' ? (a.gpu ? 'metal' : 'cpu') : (a.gpu ? 'vulkan' : 'cpu'));
  console.log('--- RESULT ---');
  console.log('engine:', engine, 'elapsed_ms:', ms, 'segments:', segs.length);
  console.log('text:', text);
})().catch(e => { console.error('Transcribe failed:', e && e.stack || e); process.exit(4); });
