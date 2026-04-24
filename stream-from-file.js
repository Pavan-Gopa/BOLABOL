#!/usr/bin/env node
// stream-from-file.js — подаём аудио чанками (PCM32) в @kutalia/whisper-node-addon
// Быстрый режим по умолчанию (без sleep), скользящее окно для контекста.
// Исправление: гарантируем наличие переменной `segments` в области видимости.

const fs = require('fs');
const path = require('path');
const os = require('os');
const whisper = require('@kutalia/whisper-node-addon');

// ─────────── CLI ───────────
function args() {
  const a = {
    wav: null,
    modelId: 'whisper-small-en-q8',
    modelsDir: path.join(process.cwd(), 'Models'),
    lang: 'en',
    gpu: true,           // --cpu переключает в false
    chunkMs: 2000,       // длина кадра
    ctxSec: 6,           // длина контекста (хвост)
    realtime: false,     // по умолчанию форсаж; включить live-имитацию: --realtime
    logSegs: false,      // логировать новые сегменты
    threads: Math.max(1, os.cpus().length)
  };
  const av = process.argv.slice(2);
  for (let i = 0; i < av.length; i++) {
    const t = av[i];
    if (t === '--wav') a.wav = av[++i];
    else if (t === '--model') a.modelId = av[++i];
    else if (t === '--models-dir') a.modelsDir = av[++i];
    else if (t === '--lang') a.lang = av[++i];
    else if (t === '--gpu') a.gpu = true;
    else if (t === '--cpu') a.gpu = false;
    else if (t === '--chunk-ms') a.chunkMs = +av[++i];
    else if (t === '--ctx-sec') a.ctxSec = +av[++i];
    else if (t === '--fast') a.realtime = false;
    else if (t === '--realtime') a.realtime = true;
    else if (t === '--log-segs') a.logSegs = true;
    else if (t === '--threads') a.threads = Math.max(1, +av[++i] || a.threads);
  }
  if (!a.wav) {
    console.log('Usage: node stream-from-file.js --wav <path.wav> [--model whisper-small-en-q8] [--cpu|--gpu] [--lang en] [--chunk-ms 2000] [--ctx-sec 6] [--threads N] [--fast|--realtime] [--log-segs]');
    process.exit(1);
  }
  return a;
}

// ─────────── utils ───────────
function safeId(id){ return String(id).replace(/[^a-z0-9._-]/gi, '_'); }
const MODEL_MAP = {
  'whisper-small-en-q8':        'ggml-small.en-q8_0.bin',
  'whisper-small-q8':           'ggml-small-q8_0.bin',
  'whisper-medium-en-q8':       'ggml-medium.en-q8_0.bin',
  'whisper-large-v3-turbo-q8':  'ggml-large-v3-turbo-q8_0.bin',
  'whisper-large-v3-q8':        'ggml-large-v3-q8_0.bin',
};
function resolveModelPath(modelsDir, modelId) {
  if (path.isAbsolute(modelId) && modelId.endsWith('.bin')) return modelId;
  const file = MODEL_MAP[modelId] || path.basename(modelId);
  return path.join(modelsDir, safeId(modelId), file);
}

function readWavAsF32(p) {
  const buf = fs.readFileSync(p);
  if (buf.toString('ascii',0,4)!=='RIFF' || buf.toString('ascii',8,12)!=='WAVE') {
    throw new Error('Not a RIFF/WAVE file: '+p);
  }
  let off=12, fmt=null, data={off:0,len:0};
  const u32=o=>buf.readUInt32LE(o), u16=o=>buf.readUInt16LE(o);
  while(off+8<=buf.length){
    const id=buf.toString('ascii', off, off+4), sz=u32(off+4), body=off+8;
    if(id==='fmt '){
      fmt={ audioFmt:u16(body), channels:u16(body+2), sampleRate:u32(body+4), byteRate:u32(body+8), blockAlign:u16(body+12), bits:u16(body+14) };
    } else if(id==='data'){ data={off:body,len:sz}; break; }
    off = body + sz + (sz & 1);
  }
  if(!fmt || !data.len) throw new Error('Malformed WAV (no fmt/data)');
  if(fmt.audioFmt!==1) throw new Error('Only PCM supported (fmt='+fmt.audioFmt+')');
  if(fmt.bits!==16) throw new Error('Only 16-bit PCM supported (bits='+fmt.bits+')');

  const frames = Math.floor(data.len / (fmt.channels * 2));
  const f32 = new Float32Array(frames);
  if (fmt.channels===1){
    for(let i=0;i<frames;i++){ f32[i]=Math.max(-1,Math.min(1,buf.readInt16LE(data.off+i*2)/32768)); }
  } else if (fmt.channels===2){
    for(let i=0;i<frames;i++){
      const l=buf.readInt16LE(data.off+i*4), r=buf.readInt16LE(data.off+i*4+2);
      f32[i]=Math.max(-1,Math.min(1,((l+r)/2)/32768));
    }
  } else {
    throw new Error('Unsupported channels='+fmt.channels);
  }
  return { f32, sampleRate: fmt.sampleRate };
}

function writeWavInt16FromFloat32(floatBuf, sampleRate, outPath) {
  const n=floatBuf.length;
  const b=Buffer.alloc(44+n*2);
  b.write('RIFF',0); b.writeUInt32LE(36+n*2,4); b.write('WAVE',8);
  b.write('fmt ',12); b.writeUInt32LE(16,16); b.writeUInt16LE(1,20);
  b.writeUInt16LE(1,22); b.writeUInt32LE(sampleRate,24); b.writeUInt32LE(sampleRate*2,28);
  b.writeUInt16LE(2,32); b.writeUInt16LE(16,34); b.write('data',36); b.writeUInt32LE(n*2,40);
  let o=44;
  for(let i=0;i<n;i++){
    let s=Math.max(-1,Math.min(1,floatBuf[i]));
    s = s<0 ? s*0x8000 : s*0x7FFF;
    b.writeInt16LE(s,o); o+=2;
  }
  fs.writeFileSync(outPath,b);
  return outPath;
}

async function transcribePCM(pcm32, sampleRate, { modelPath, language, use_gpu, threads }) {
  const base = { model: modelPath, language, task:'transcribe', use_gpu, threads };
  try {
    return await whisper.transcribe({ ...base, pcm32, sample_rate: sampleRate });
  } catch (e) {
    // fallback на temp WAV (на случай, если PCM32 не поддержан в твоём бинаре)
    const tmp = path.join(os.tmpdir(), `ss_stream_${Date.now()}_${Math.random().toString(36).slice(2)}.wav`);
    writeWavInt16FromFloat32(pcm32, sampleRate, tmp);
    try { return await whisper.transcribe({ ...base, fname_inp: tmp }); }
    finally { try { fs.unlinkSync(tmp); } catch {} }
  }
}

function normalize(res) {
  let segments = Array.isArray(res?.segments) ? res.segments : [];
  if (!segments.length && Array.isArray(res?.transcription)) {
    segments = res.transcription.map(([t0,t1,text]) => ({ t0, t1, text }));
  }
  const stitched = segments.map(s=>s.text||'').join(' ').trim();
  const text = (res?.text && res.text.trim()) ? res.text.trim() : stitched;
  const engine = res?.engine || res?.backend || 'unknown';
  return { text, segments, engine };
}

function sleep(ms){ return new Promise(r=>setTimeout(r,ms)); }

// ─────────── main ───────────
(async () => {
  const a = args();
  if (!fs.existsSync(a.wav)) throw new Error('WAV not found: '+a.wav);
  const modelPath = resolveModelPath(a.modelsDir, a.modelId);
  if (!fs.existsSync(modelPath)) {
    console.error('Model file not found:', modelPath);
    console.error('Сначала установи модель (через test-fork.js) или скачай вручную.');
    process.exit(2);
  }

  const { f32, sampleRate } = readWavAsF32(a.wav);
  if (sampleRate !== 16000) {
    console.warn(`[warn] WAV has ${sampleRate} Hz; whisper.cpp ожидает 16 kHz. Я продолжу, но лучше заранее привести к 16 kHz.`);
  }

  const chunkSamples = Math.max(1, Math.round(sampleRate * (a.chunkMs/1000)));
  const ctxSamples   = Math.max(sampleRate, Math.round(sampleRate * a.ctxSec));

  console.log('[info] model:', modelPath);
  console.log('[info] wav:', path.basename(a.wav), `len=${(f32.length/sampleRate).toFixed(2)}s`, `chunk=${a.chunkMs}ms`, `ctx=${a.ctxSec}s`, a.gpu ? 'GPU' : 'CPU', `threads=${a.threads}`);

  let lastPrintedCount = 0;

  for (let off = 0; off < f32.length; off += chunkSamples) {
    const windowEnd = Math.min(off + chunkSamples, f32.length);
    const windowStart = Math.max(0, windowEnd - ctxSamples);
    const window = f32.subarray(windowStart, windowEnd);

    const raw = await transcribePCM(window, sampleRate, {
      modelPath, language: a.lang, use_gpu: a.gpu, threads: a.threads
    });
    const norm = normalize(raw);
    const segs = norm.segments || [];              // ← гарантируем имя `segs`
    const delta = segs.slice(lastPrintedCount);     // ← и используем его
    if (a.logSegs && delta.length) {
      for (const s of delta) console.log(`\n[seg] ${s.t0 ?? ''} ${s.t1 ?? ''} ${s.text}`);
    }
    const stitched = segs.map(s=>s.text||'').join(' ').trim();
    process.stdout.write(`\r[${norm.engine}] ${stitched}`);

    lastPrintedCount = segs.length;
    if (a.realtime) await sleep(a.chunkMs);
  }

  console.log('\n--- DONE ---');
})().catch(e => { console.error(e && e.stack || e); process.exit(1); });
