#!/usr/bin/env node
// test-fork.js — прямой тест transcription.fork.js (ждём установки модели; можно передать готовый WAV в воркер)

const { fork } = require('child_process');
const fs = require('fs');
const path = require('path');

function parseArgs() {
  const a = {
    wav: null,
    model: 'whisper-small-en-q8',
    baseDir: path.join(process.cwd(), 'Models'),
    cpu: false,
    noFallback: false,
    useFile: false,
    log: 'info'
  };
  const av = process.argv.slice(2);
  for (let i = 0; i < av.length; i++) {
    const t = av[i];
    if (t === '--wav') a.wav = av[++i];
    else if (t === '--model') a.model = av[++i];
    else if (t === '--base') a.baseDir = av[++i];
    else if (t === '--cpu') a.cpu = true;
    else if (t === '--no-fallback') a.noFallback = true;
    else if (t === '--use-file') a.useFile = true;      // ⬅️ новый флаг
    else if (t === '--log') a.log = av[++i];
    else if (t === '--help' || t === '-h') a.help = true;
  }
  return a;
}
function usage() {
  console.log(`
Usage:
  node test-fork.js --wav <path-to-wav> [--model whisper-small-en-q8] [--cpu] [--no-fallback] [--use-file] [--base ./Models] [--log debug]

Models:
  whisper-small-en-q8
  whisper-small-q8
  whisper-medium-en-q8
  whisper-large-v3-turbo-q8
  whisper-large-v3-q8
`);}
function ensureDir(p){ fs.mkdirSync(p, { recursive:true }); }

const MODEL_MAP = {
  'whisper-small-en-q8':        'ggml-small.en-q8_0.bin',
  'whisper-small-q8':           'ggml-small-q8_0.bin',
  'whisper-medium-en-q8':       'ggml-medium.en-q8_0.bin',
  'whisper-large-v3-turbo-q8':  'ggml-large-v3-turbo-q8_0.bin',
  'whisper-large-v3-q8':        'ggml-large-v3-q8_0.bin',
};

function safeId(id){ return String(id).replace(/[^a-z0-9._-]/gi, '_'); }
function expectedModelPath(baseDir, modelId) {
  if (/\.bin$/i.test(modelId) && path.isAbsolute(modelId)) return modelId;
  const file = MODEL_MAP[modelId] || path.basename(modelId);
  const dir = path.join(baseDir, safeId(modelId));
  return path.join(dir, file);
}

// WAV → Float32 (если не --use-file)
function readWavAsF32(p) {
  const buf = fs.readFileSync(p);
  if (buf.toString('ascii',0,4) !== 'RIFF' || buf.toString('ascii',8,12) !== 'WAVE') {
    throw new Error('Not a RIFF/WAVE file: ' + p);
  }
  let off = 12;
  let fmt = null, data = { off:0, len:0 };
  function u32(o){ return buf.readUInt32LE(o); }
  function u16(o){ return buf.readUInt16LE(o); }
  while (off + 8 <= buf.length) {
    const id = buf.toString('ascii', off, off+4);
    const sz = u32(off+4);
    const body = off+8;
    if (id === 'fmt ') {
      fmt = {
        audioFmt: u16(body+0),
        channels: u16(body+2),
        sampleRate: u32(body+4),
        bits: u16(body+14),
      };
    } else if (id === 'data') {
      data = { off: body, len: sz };
      break;
    }
    off = body + sz + (sz & 1);
  }
  if (!fmt || !data.len) throw new Error('Malformed WAV (no fmt/data)');
  if (fmt.audioFmt !== 1) throw new Error('Only PCM is supported (fmt='+fmt.audioFmt+')');
  if (fmt.bits !== 16) throw new Error('Only 16-bit PCM supported (bits='+fmt.bits+')');

  const bytes = fmt.bits/8;
  const frames = Math.floor(data.len / (bytes * fmt.channels));
  const f32 = new Float32Array(frames);

  if (fmt.channels === 1) {
    for (let i=0; i<frames; i++) {
      const s = buf.readInt16LE(data.off + i*2);
      f32[i] = Math.max(-1, Math.min(1, s / 32768));
    }
  } else if (fmt.channels === 2) {
    for (let i=0; i<frames; i++) {
      const l = buf.readInt16LE(data.off + i*4 + 0);
      const r = buf.readInt16LE(data.off + i*4 + 2);
      f32[i] = Math.max(-1, Math.min(1, ((l + r) / 2) / 32768));
    }
  } else {
    throw new Error('Unsupported channels='+fmt.channels);
  }

  return { f32, sampleRate: fmt.sampleRate };
}

function waitForInstall(child, modelId, baseDir, timeoutMs=10*60*1000) {
  const target = expectedModelPath(baseDir, modelId);
  if (fs.existsSync(target)) return Promise.resolve(target);

  child.send({ type: 'install_model', modelId });
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      if (fs.existsSync(target)) resolve(target);
      else reject(new Error('Model install timeout'));
    }, timeoutMs);

    const onMsg = (m) => {
      if (!m || !m.type) return;
      if (m.type === 'download-progress' && m.modelId === modelId) {
        console.log('[download]', modelId, m.status || '');
      }
      if (m.type === 'download-complete' && m.modelId === modelId) {
        clearTimeout(timer);
        child.off('message', onMsg);
        console.log('[download] complete:', modelId);
        resolve(target);
      }
      if (m.type === 'download-failed' && m.modelId === modelId) {
        clearTimeout(timer);
        child.off('message', onMsg);
        reject(new Error(m.error || 'download failed'));
      }
    };
    child.on('message', onMsg);
  });
}

(async () => {
  const a = parseArgs();
  if (a.help || !a.wav) { usage(); process.exit(a.help ? 0 : 1); }
  if (!fs.existsSync(a.wav)) { console.error('WAV not found:', a.wav); process.exit(2); }
  ensureDir(a.baseDir);

  const workerPath = path.join(process.cwd(), 'transcription.fork.js');
  if (!fs.existsSync(workerPath)) {
    console.error('transcription.fork.js not found at', workerPath);
    process.exit(3);
  }

  console.log('[info] Fork:', workerPath);
  const child = fork(workerPath, [], { stdio: ['pipe','pipe','pipe','ipc'] });

  child.stdout?.on('data', d => process.stdout.write(String(d)));
  child.stderr?.on('data', d => process.stderr.write(String(d)));

  const once = (ev) => new Promise(res => child.once(ev, res));

  // базовая конфигурация воркера
  child.send({ type: 'set_base_dir', baseDir: a.baseDir });
  child.send({ type: 'set_log_level', payload: { level: a.log } });

  // 1) Ждём модель
  try {
    const modelPath = await waitForInstall(child, a.model, a.baseDir);
    console.log('[info] model ready at:', modelPath);
  } catch (e) {
    console.error('Model install error:', e.message);
    child.send({ type: 'dispose' });
    await once('exit');
    process.exit(4);
  }

  // 2) Готовим payload
  let payload;
  if (a.useFile) {
    console.log('[info] Using external WAV path directly (no temp WAV).');
    payload = {
      type: 'transcribe',
      id: 1,
      modelId: a.model,
      options: {
        fname_inp: a.wav,        // ⬅️ передаём готовый файл прямо в воркер
        fallbackCpu: !a.noFallback,
        forceCpu: !!a.cpu
      },
      audioData: Buffer.alloc(0), // не нужен; но поле оставляем пустым
    };
  } else {
    // читаем WAV → Float32, как раньше
    const { f32, sampleRate } = readWavAsF32(a.wav);
    console.log('[info] WAV ok:', path.basename(a.wav), `rate=${sampleRate}Hz`, `len=${f32.length} samples (~${(f32.length/sampleRate).toFixed(2)}s)`);
    payload = {
      type: 'transcribe',
      id: 1,
      modelId: a.model,
      options: {
        sourceSampleRate: sampleRate,
        fallbackCpu: !a.noFallback,
        forceCpu: !!a.cpu
      },
      audioData: Buffer.from(f32.buffer, f32.byteOffset, f32.byteLength),
    };
  }

  // 3) Старт
  child.send(payload);

  // 4) Ответ
  child.on('message', (m) => {
    if (!m || !m.type) return;
    if (m.type === 'transcription-complete' && m.id === 1) {
      const r = m.result || {};
      console.log('--- RESULT ---');
      console.log('engine:', r.engine, r.engineAssumed ? '(assumed)' : '');
      console.log('segments:', Array.isArray(r.segments) ? r.segments.length : 0);
      console.log('text:', r.text || '');
      child.send({ type: 'dispose' });
    }
    if (m.type === 'transcription-error' && m.id === 1) {
      console.error('ERROR:', m.error);
      child.send({ type: 'dispose' });
    }
  });

  await once('exit');
})();
