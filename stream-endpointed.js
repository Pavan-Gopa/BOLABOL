#!/usr/bin/env node
// stream-endpointed.js — «стриминг по VAD»: режем на фразы и распознаём каждую один раз.
// Исправлено: добавлен fallback на временный WAV, если аддон не принимает pcm32.

const fs = require('fs');
const path = require('path');
const os = require('os');
const whisper = require('@kutalia/whisper-node-addon');

// ── CLI ──
function args() {
  const a = {
    wav: null,
    modelId: 'whisper-small-en-q8',
    modelsDir: path.join(process.cwd(), 'Models'),
    lang: 'en',
    gpu: true,
    threads: Math.max(1, os.cpus().length),
    frameMs: 20,
    hopMs: 10,
    minSpeechMs: 300,
    endHangMs: 400,
    noiseProbeMs: 400,
    thrMul: 3.0
  };
  const av = process.argv.slice(2);
  for (let i=0;i<av.length;i++) {
    const t=av[i];
    if (t==='--wav') a.wav = av[++i];
    else if (t==='--model') a.modelId = av[++i];
    else if (t==='--models-dir') a.modelsDir = av[++i];
    else if (t==='--lang') a.lang = av[++i];
    else if (t==='--cpu') a.gpu = false;
    else if (t==='--gpu') a.gpu = true;
    else if (t==='--threads') a.threads = Math.max(1, +av[++i] || a.threads);
  }
  if (!a.wav) {
    console.log('Usage: node stream-endpointed.js --wav <path.wav> [--model whisper-small-en-q8] [--cpu|--gpu] [--lang en] [--threads N]');
    process.exit(1);
  }
  return a;
}

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

// ── WAV → Float32 ──
function readWavAsF32(p) {
  const buf = fs.readFileSync(p);
  if (buf.toString('ascii',0,4)!=='RIFF' || buf.toString('ascii',8,12)!=='WAVE')
    throw new Error('Not a RIFF/WAVE file: '+p);
  let off=12, fmt=null, data={off:0,len:0};
  const u32=o=>buf.readUInt32LE(o), u16=o=>buf.readUInt16LE(o);
  while(off+8<=buf.length){
    const id=buf.toString('ascii',off,off+4), sz=u32(off+4), body=off+8;
    if(id==='fmt '){ fmt={ audioFmt:u16(body), ch:u16(body+2), sr:u32(body+4), bits:u16(body+14) }; }
    else if(id==='data'){ data={off:body,len:sz}; break; }
    off = body + sz + (sz & 1);
  }
  if(!fmt || !data.len) throw new Error('Malformed WAV (no fmt/data)');
  if(fmt.audioFmt!==1 || fmt.bits!==16) throw new Error('Only 16-bit PCM supported');
  const frames = Math.floor(data.len / (fmt.ch*2));
  const f32 = new Float32Array(frames);
  if (fmt.ch===1) {
    for (let i=0;i<frames;i++) f32[i]=Math.max(-1,Math.min(1,buf.readInt16LE(data.off+i*2)/32768));
  } else if (fmt.ch===2) {
    for (let i=0;i<frames;i++) {
      const l=buf.readInt16LE(data.off+i*4), r=buf.readInt16LE(data.off+i*4+2);
      f32[i]=Math.max(-1,Math.min(1,((l+r)/2)/32768));
    }
  } else throw new Error('Unsupported channels='+fmt.ch);
  return { f32, sampleRate: fmt.sr };
}

// ── VAD (простая энергия + хвост) ──
function vadSegments(f32, sr, { frameMs, hopMs, noiseProbeMs, thrMul, minSpeechMs, endHangMs }) {
  const frame = Math.max(1, Math.round(sr * frameMs/1000));
  const hop   = Math.max(1, Math.round(sr * hopMs/1000));
  const noiseFrames = Math.max(1, Math.round(sr * noiseProbeMs/1000 / hop));
  const minSpeechFrames = Math.max(1, Math.round(sr * minSpeechMs/1000 / hop));
  const hangFrames = Math.max(1, Math.round(sr * endHangMs/1000 / hop));

  const rms = [];
  for (let start=0; start+frame <= f32.length; start+=hop) {
    let s=0; for (let i=0;i<frame;i++){ const v=f32[start+i]; s+=v*v; }
    rms.push(Math.sqrt(s/frame));
  }
  const noise = rms.slice(0, noiseFrames);
  const noiseMean = noise.reduce((a,b)=>a+b,0) / Math.max(1, noise.length);
  const thr = noiseMean * thrMul;

  const segs = [];
  let inSpeech = false, startIdx = 0, below = 0;
  for (let i=0;i<rms.length;i++){
    if (!inSpeech) {
      if (rms[i] >= thr) { inSpeech = true; startIdx = i; below = 0; }
    } else {
      if (rms[i] < thr) below++; else below = 0;
      if (below >= hangFrames) {
        const endIdx = i - hangFrames;
        if (endIdx - startIdx >= minSpeechFrames) {
          const t0 = Math.floor(startIdx*hop);
          const t1 = Math.min(f32.length, Math.floor((endIdx*hop)+frame));
          segs.push({ start: t0, end: t1 });
        }
        inSpeech = false; below = 0;
      }
    }
  }
  if (inSpeech) {
    const endIdx = rms.length-1;
    if (endIdx - startIdx >= minSpeechFrames) {
      const t0 = Math.floor(startIdx*hop);
      const t1 = f32.length;
      segs.push({ start: t0, end: t1 });
    }
  }
  const merged = [];
  for (const s of segs) {
    const last = merged[merged.length-1];
    if (last && s.start - last.end < Math.round(0.15*sr)) last.end = s.end;
    else merged.push(s);
  }
  return merged;
}

// ── PCM32 → transcribe (с fallback на temp WAV) ──
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

async function transcribeSegmentPCM(pcm32, sr, { modelPath, language, use_gpu, threads }) {
  const base = { model: modelPath, language, task: 'transcribe', use_gpu, threads };
  // 1) пытаемся напрямую (если бинарь умеет pcm32)
  try {
    return await whisper.transcribe({ ...base, pcm32, sample_rate: sr });
  } catch (_e) {
    // 2) fallback: пишем временный WAV
    const tmp = path.join(os.tmpdir(), `ss_vad_${Date.now()}_${Math.random().toString(36).slice(2)}.wav`);
    writeWavInt16FromFloat32(pcm32, sr, tmp);
    try { return await whisper.transcribe({ ...base, fname_inp: tmp }); }
    finally { try { fs.unlinkSync(tmp); } catch {} }
  }
}

function normalize(res){
  let segments = Array.isArray(res?.segments) ? res.segments : [];
  if (!segments.length && Array.isArray(res?.transcription)) {
    segments = res.transcription.map(([t0,t1,text]) => ({ t0, t1, text }));
  }
  const text = (res?.text && res.text.trim()) ? res.text.trim() : segments.map(s=>s.text||'').join(' ').trim();
  const engine = res?.engine || res?.backend || 'unknown';
  return { text, segments, engine };
}

// ── main ──
(async () => {
  const a = args();
  if (!fs.existsSync(a.wav)) throw new Error('WAV not found: '+a.wav);
  const modelPath = resolveModelPath(a.modelsDir, a.modelId);
  if (!fs.existsSync(modelPath)) {
    console.error('Model file not found:', modelPath);
    console.error('Установи модель через test-fork.js или положи .bin вручную.');
    process.exit(2);
  }

  const { f32, sampleRate: sr } = readWavAsF32(a.wav);
  if (sr !== 16000) console.warn(`[warn] WAV has ${sr} Hz; желательно 16kHz.`);

  console.log('[info] VAD slicing...');
  const segs = vadSegments(f32, sr, a);
  console.log(`[info] found ${segs.length} segment(s)`);

  let fullText = '';
  for (let i=0;i<segs.length;i++){
    const { start, end } = segs[i];
    const chunk = f32.subarray(start, end);

    const res = await transcribeSegmentPCM(chunk, sr, {
      modelPath,
      language: a.lang,
      use_gpu: a.gpu,
      threads: a.threads
    });
    const { text, engine } = normalize(res);
    const t0 = (start/sr).toFixed(2), t1 = (end/sr).toFixed(2);
    console.log(`[${i+1}/${segs.length}] (${t0}-${t1}s) [${engine}] ${text}`);
    if (text) fullText += (fullText ? ' ' : '') + text;
  }

  console.log('--- FINAL ---');
  console.log(fullText);
})();
