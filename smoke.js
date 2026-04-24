#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const https = require('https');
const whisper = require('@kutalia/whisper-node-addon');
const HF_BASE = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/';
const MAP = {
  'small-en-q8': { file: 'ggml-small.en-q8_0.bin', lang: 'en' },
  'small-q8': { file: 'ggml-small-q8_0.bin', lang: 'auto' },
  'medium-en-q8': { file: 'ggml-medium.en-q8_0.bin', lang: 'en' },
  'large-v3-turbo-q8': { file: 'ggml-large-v3-turbo-q8_0.bin', lang: 'auto' },
  'large-v3-q8': { file: 'ggml-large-v3-q8_0.bin', lang: 'auto' },
};
function ensureDir(p){ fs.mkdirSync(p,{recursive:true}); }
function dl(url,dst){ ensureDir(path.dirname(dst)); return new Promise((res,rej)=>{const t=dst+'.part';const f=fs.createWriteStream(t); https.get(url,r=>{ if(r.statusCode>=300&&r.statusCode<400&&r.headers.location){r.destroy();return dl(r.headers.location,dst).then(res,rej);} if(r.statusCode!==200){r.resume();return rej(new Error('HTTP '+r.statusCode));} r.pipe(f); f.on('finish',()=>f.close(()=>{try{fs.renameSync(t,dst);res();}catch(e){rej(e);}}));}).on('error',e=>{try{f.close();}catch{} try{fs.unlinkSync(t);}catch{} rej(e);});});}
(async ()=>{
  const wav = process.argv[2]; const short = process.argv[3]||'small-en-q8'; const use_gpu = process.argv.includes('--gpu');
  if(!wav){ console.log('Usage: node smoke.js <path-to-wav> [small-en-q8|small-q8|medium-en-q8|large-v3-turbo-q8|large-v3-q8] [--gpu]'); process.exit(1); }
  if(!fs.existsSync(wav)) { console.error('WAV not found:', wav); process.exit(2); }
  const m = MAP[short]; if(!m){ console.error('Unknown model:', short); process.exit(3); }
  const modelsDir = path.join(process.cwd(), 'models'); ensureDir(modelsDir);
  const modelPath = path.join(modelsDir, m.file); if(!fs.existsSync(modelPath)){ console.log('[download]', m.file); await dl(HF_BASE+m.file, modelPath); }
  const res = await whisper.transcribe({ fname_inp: wav, model: modelPath, language: m.lang, task: 'transcribe', use_gpu });
  const segs = Array.isArray(res?.segments) ? res.segments
            : Array.isArray(res?.transcription) ? res.transcription.map(([t0,t1,text])=>({t0,t1,text})) : [];
  const text = (res?.text && res.text.trim()) ? res.text.trim() : segs.map(s=>s.text).join(' ').trim();
  const engine = res?.engine || res?.backend || (process.platform==='darwin'?(use_gpu?'metal':'cpu'):(use_gpu?'vulkan':'cpu'));
  console.log('engine:', engine);
  console.log('segments:', segs.length);
  console.log('text:', text);
})().catch(e=>{ console.error(e); process.exit(4); });
