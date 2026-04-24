/**
 * SmartScribe Parakeet TDT Transcription Worker (CPU-only)
 * Node.js + onnxruntime-node, no Python required
 */

const ort = require('onnxruntime-node');
const path = require('path');
const fs = require('fs');
const https = require('https');

// Default cache dir; can be overridden via init payload.cacheDir from the main process
let MODEL_CACHE_DIR = path.join(require('os').homedir(), 'AppData', 'Roaming', 'smartscribe-app', 'Models');

// Logging
const LOG_LEVELS = { error: 0, warn: 1, info: 2, debug: 3 };
const parseLogLevel = (lvl) => LOG_LEVELS[String(lvl || 'warn').toLowerCase()] ?? LOG_LEVELS.warn;
let currentLogLevel = parseLogLevel(process.env.SMARTSCRIBE_LOG_LEVEL || process.env.SMARTSCRIBE_LOG || 'warn');
const shouldLog = (lvl) => LOG_LEVELS[lvl] <= currentLogLevel;
const logger = {
  setLevel: (lvl) => { currentLogLevel = parseLogLevel(lvl); },
  debug: (m, ...a) => { if (shouldLog('debug')) { console.debug(`[Worker] ${m}`, ...a); process.send?.({ type: 'log', level: 'debug', message: String(m), args: a }); } },
  info:  (m, ...a) => { if (shouldLog('info'))  { console.log(`[Worker] ${m}`, ...a);  process.send?.({ type: 'log', level: 'info',  message: String(m), args: a }); } },
  warn:  (m, ...a) => { if (shouldLog('warn'))  { console.warn(`[Worker] ${m}`, ...a); process.send?.({ type: 'log', level: 'warn',  message: String(m), args: a }); } },
  error: (e, ...a) => { const msg = e instanceof Error ? `${e.name}: ${e.message}` : String(e); console.error(`[Worker] ${msg}`, ...a); process.send?.({ type: 'log', level: 'error', message: msg, args: a }); },
};

// Models (HF)
const MODEL_CONFIGS = {
  'istupakov/parakeet-tdt-0.6b-v2-onnx': {
    files: [
      'encoder-model.onnx',
      'encoder-model.onnx.data',
      'decoder_joint-model.onnx',
      'nemo128.onnx',
      'vocab.txt',
      'config.json'
    ],
    baseUrl: 'https://huggingface.co/istupakov/parakeet-tdt-0.6b-v2-onnx/resolve/main/',
    language: 'English'
  },
  'istupakov/parakeet-tdt-0.6b-v3-onnx': {
    files: [
      'encoder-model.onnx',
      'encoder-model.onnx.data',
      'decoder_joint-model.onnx',
      'nemo128.onnx',
      'vocab.txt',
      'config.json'
    ],
    baseUrl: 'https://huggingface.co/istupakov/parakeet-tdt-0.6b-v3-onnx/resolve/main/',
    language: 'Multilingual'
  }
};

// Utilities
function isReadableNonZero(filePath) {
  try { const st = fs.statSync(filePath); return st.isFile() && st.size > 0; } catch { return false; }
}

async function downloadFile(url, filePath, onProgress) {
  const tmpPath = `${filePath}.part`;
  try { if (fs.existsSync(tmpPath)) fs.unlinkSync(tmpPath); } catch {}
  return new Promise((resolve, reject) => {
    const ws = fs.createWriteStream(tmpPath);
    const handle = (res, currentUrl) => {
      if ([301,302,303,307,308].includes(res.statusCode)) {
        let next = res.headers.location; if (!next) return reject(new Error(`Redirect w/o location: ${currentUrl}`));
        if (!/^https?:/i.test(next)) { const u = new URL(currentUrl); next = new URL(next, `${u.protocol}//${u.host}`).href; }
        return https.get(next, (r) => handle(r, next)).on('error', (e) => { try { ws.close(); } catch {}; fs.unlink(tmpPath, () => {}); reject(e); });
      }
      if (res.statusCode !== 200) { try { ws.close(); } catch {}; fs.unlink(tmpPath, () => {}); return reject(new Error(`HTTP ${res.statusCode} for ${currentUrl}`)); }
      const total = parseInt(res.headers['content-length'] || '0'); let done = 0;
      res.on('data', (c) => { done += c.length; if (onProgress && total>0) onProgress(done,total); });
      res.on('error', (e) => { try { ws.close(); } catch {}; fs.unlink(tmpPath, () => {}); reject(e); });
      res.pipe(ws);
    };

    const req = https.get(url, (res) => handle(res, url));
    req.on('error', (e) => { try { ws.close(); } catch {}; fs.unlink(tmpPath, () => {}); reject(e); });
    ws.on('finish', () => {
      ws.close();
      try {
        try { if (fs.existsSync(filePath)) fs.unlinkSync(filePath); } catch {}
        fs.renameSync(tmpPath, filePath);
        if (!isReadableNonZero(filePath)) { try { fs.unlinkSync(filePath); } catch {}; return reject(new Error(`Invalid/empty download: ${filePath}`)); }
        resolve();
      } catch (e) { try { fs.unlinkSync(tmpPath); } catch {}; reject(e); }
    });
    ws.on('error', (e) => { try { ws.close(); } catch {}; fs.unlink(tmpPath, () => {}); reject(e); });
  });
}

const modelDownloadPromises = new Map();

async function ensureModelFiles(modelId) {
  const cfg = MODEL_CONFIGS[modelId];
  if (!cfg) throw new Error(`Unknown model: ${modelId}`);
  const dir = path.join(MODEL_CACHE_DIR, modelId.replace('/', '_'));
  if (!fs.existsSync(MODEL_CACHE_DIR)) fs.mkdirSync(MODEL_CACHE_DIR, { recursive: true });
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const missing = [];
  for (const f of cfg.files) {
    const p = path.join(dir, f);
    try { const tmp = `${p}.part`; if (fs.existsSync(tmp)) fs.unlinkSync(tmp); } catch {}
    if (!isReadableNonZero(p)) { try { if (fs.existsSync(p)) fs.unlinkSync(p); } catch {}; missing.push(f); }
  }
  if (missing.length === 0) return dir;
  if (modelDownloadPromises.has(modelId)) { await modelDownloadPromises.get(modelId); return dir; }

  const run = (async () => {
    const totalFiles = missing.length;
    const emitProgress = (fileIndex, fraction) => {
      const clamped = Math.max(0, Math.min(1, Number.isFinite(fraction) ? fraction : 0));
      const overall = totalFiles > 0 ? Math.round(((fileIndex + clamped) / totalFiles) * 100) : 100;
      process.send?.({
        type: 'download_progress',
        modelId,
        fileName: missing[fileIndex] || null,
        currentFile: Math.min(totalFiles, fileIndex + 1),
        totalFiles,
        progress: overall,
      });
    };

    process.send?.({ type: 'download_progress', modelId, status: 'start', progress: 0, currentFile: 0, totalFiles });
    for (let i=0;i<missing.length;i++) {
      const name = missing[i];
      const url = cfg.baseUrl + name;
      emitProgress(i, 0);
      const maxAttempts = 3; let attempt = 0;
      while (attempt < maxAttempts) {
        try {
          await downloadFile(url, path.join(dir, name), (done,total) => {
            const fraction = total > 0 ? done / total : 0;
            emitProgress(i, fraction);
          });
          break;
        } catch (e) {
          attempt++;
          logger.warn(`Download failed for ${name} (attempt ${attempt}/${maxAttempts}): ${e.message}`);
          if (attempt >= maxAttempts) {
            if (name === 'vocab.txt') { logger.warn('vocab.txt missing, continuing'); break; }
            throw e;
          }
          await new Promise(r => setTimeout(r, 200 * attempt));
        }
      }
      emitProgress(i, 1);
    }
    process.send?.({ type: 'download_progress', modelId, progress: 100, currentFile: totalFiles, totalFiles, status: 'complete' });
  })();

  modelDownloadPromises.set(modelId, run);
  try { await run; } finally { modelDownloadPromises.delete(modelId); }
  return dir;
}

async function loadVocabulary(modelDir) {
  const p = path.join(modelDir, 'vocab.txt');
  if (!fs.existsSync(p)) {
    logger.warn(`vocab.txt not found at ${p}, using minimal vocab`);
    return { vocab: { '<pad>':0,'<unk>':1,'<s>':2,'</s>':3 }, id_to_token: { 0:'<pad>',1:'<unk>',2:'<s>',3:'</s>' } };
  }
  const content = fs.readFileSync(p, 'utf-8');
  const token_to_id = {}; const id_to_token = {};
  for (const line of content.split(/\r?\n/).map(s=>s.trim()).filter(Boolean)) {
    const [tok, idStr] = line.split(/\s+/); const id = parseInt(idStr,10);
    if (!Number.isFinite(id)) continue;
    token_to_id[tok] = id; id_to_token[id] = tok;
  }
  return { vocab: token_to_id, id_to_token };
}

function preprocessAudio(audioBuffer) {
  let audioData;
  if (audioBuffer instanceof Float32Array) {
    audioData = audioBuffer;
  } else if (audioBuffer instanceof ArrayBuffer) {
    audioData = new Float32Array(audioBuffer);
  } else if (audioBuffer && audioBuffer.type === 'Buffer' && Array.isArray(audioBuffer.data)) {
    const bytes = new Uint8Array(audioBuffer.data);
    if (bytes.length % 4 === 0) {
      const f32 = new Float32Array(bytes.buffer, bytes.byteOffset, bytes.length/4);
      audioData = new Float32Array(f32);
    } else {
      const i16 = new Int16Array(bytes.buffer, bytes.byteOffset, Math.floor(bytes.length/2));
      audioData = new Float32Array(i16.length);
      for (let i=0;i<i16.length;i++) audioData[i] = i16[i] / 32768.0;
    }
  } else if (Buffer.isBuffer(audioBuffer)) {
    if (audioBuffer.length % 4 === 0) {
      const f32 = new Float32Array(audioBuffer.buffer, audioBuffer.byteOffset, audioBuffer.length/4);
      audioData = new Float32Array(f32);
    } else {
      const i16 = new Int16Array(audioBuffer.buffer, audioBuffer.byteOffset, Math.floor(audioBuffer.length/2));
      audioData = new Float32Array(i16.length);
      for (let i=0;i<i16.length;i++) audioData[i] = i16[i] / 32768.0;
    }
  } else if (Array.isArray(audioBuffer)) {
    audioData = new Float32Array(audioBuffer);
  } else {
    logger.error(`Unsupported audio buffer format: ${typeof audioBuffer}`);
    throw new Error('Unsupported audio buffer format');
  }
  // Clip into [-1,1]
  for (let i=0;i<audioData.length;i++) if (audioData[i] > 1) audioData[i] = 1; else if (audioData[i] < -1) audioData[i] = -1;
  return audioData;
}

class ParakeetTDTModel {
  constructor(modelDir, vocabData) {
    this.modelDir = modelDir; this.vocab = vocabData.vocab; this.id_to_token = vocabData.id_to_token;
    this.encoderSession = null; this.decoderJointSession = null; this.preprocessorSession = null;
    this.decoderInputNames = []; this.decoderInputMeta = {}; this.decoderOutputNames = []; this.names = null;
    this.vocabSize = Object.keys(this.id_to_token).length;
    const blankCandidates = ['<blk>', '<blank>', '<pad>'];
    let foundBlank = null; for (const bc of blankCandidates) { if (typeof this.vocab[bc] === 'number') { foundBlank = this.vocab[bc]; break; } }
    this.blankId = foundBlank ?? 0;
    this.subsamplingFactor = 8; this.featuresSize = 128; this.maxTokensPerStep = 10;
    try { const cfg = JSON.parse(fs.readFileSync(path.join(this.modelDir, 'config.json'), 'utf-8')); this.subsamplingFactor = cfg.subsampling_factor ?? 8; this.featuresSize = cfg.features_size ?? 128; } catch {}
  }
  async initialize() {
    logger.info('Initializing ONNX sessions (CPUExecutionProvider)');
    const create = async (p) => ort.InferenceSession.create(p, { providers: ['CPUExecutionProvider'], graphOptimizationLevel: 'all' });
    const pre = path.join(this.modelDir, 'nemo128.onnx');
    const enc = path.join(this.modelDir, 'encoder-model.onnx');
    const encData = path.join(this.modelDir, 'encoder-model.onnx.data');
    const dec = path.join(this.modelDir, 'decoder_joint-model.onnx');
    if (!isReadableNonZero(encData)) throw new Error(`Missing encoder data file: ${encData}`);
    this.preprocessorSession = await create(pre);
    this.encoderSession      = await create(enc);
    this.decoderJointSession = await create(dec);
    this.decoderInputNames = this.decoderJointSession.inputNames || [];
    this.decoderInputMeta  = this.decoderJointSession.inputMetadata || {};
    this.decoderOutputNames= this.decoderJointSession.outputNames || [];
    this._resolveDecoderNames();
  }
  _resolveDecoderNames() {
    const names = new Set(this.decoderInputNames);
    const pick = (c) => c.find((n) => names.has(n)) || this.decoderInputNames.find((n) => c.some((cc) => n.toLowerCase().includes(cc.replace(/_/g, ''))));
    const enc = pick(['encoder_outputs','encoder_output','encoder','enc_out']);
    const targets = pick(['targets','target','y','labels']);
    const targetLen = pick(['target_length','target_lengths','target_len','y_length','length']);
    const state1 = pick(['input_states_1','input_state_1','states_1','state_1']);
    const state2 = pick(['input_states_2','input_state_2','states_2','state_2']);
    if (!enc || !targets || !targetLen || !state1 || !state2) throw new Error('Unable to resolve decoder joint input names');
    this.names = { enc, targets, targetLen, state1, state2 };
  }
  createDecoderState() {
    const meta = this.decoderInputMeta;
    const s1 = (meta[this.names.state1]?.dimensions)||[2,1,640];
    const s2 = (meta[this.names.state2]?.dimensions)||[2,1,640];
    const s1Shape = [typeof s1[0]==='number'?s1[0]:2, 1, typeof s1[2]==='number'?s1[2]:640];
    const s2Shape = [typeof s2[0]==='number'?s2[0]:2, 1, typeof s2[2]==='number'?s2[2]:640];
    return { state1: new Float32Array(s1Shape[0]*s1Shape[1]*s1Shape[2]).fill(0), state2: new Float32Array(s2Shape[0]*s2Shape[1]*s2Shape[2]).fill(0), state1Shape: s1Shape, state2Shape: s2Shape };
  }
  async tdtDecodeStep(encoderOutput, t, prevTokens, prevState) {
    const [B,T,D] = encoderOutput.dims;
    if (t >= T) return null;
    const slice = new Float32Array(D); const start = t*D; for (let i=0;i<D;i++) slice[i] = encoderOutput.data[start+i];
    const encTensor = new ort.Tensor('float32', slice, [1,D,1]);
    const lastToken = prevTokens.length>0 ? prevTokens[prevTokens.length-1] : this.blankId;
    const targets = new ort.Tensor('int32', new Int32Array([lastToken]), [1,1]);
    const targetLen = new ort.Tensor('int32', new Int32Array([1]), [1]);
    const s1 = new ort.Tensor('float32', prevState.state1, prevState.state1Shape);
    const s2 = new ort.Tensor('float32', prevState.state2, prevState.state2Shape);
    const feeds = {}; feeds[this.names.enc]=encTensor; feeds[this.names.targets]=targets; feeds[this.names.targetLen]=targetLen; feeds[this.names.state1]=s1; feeds[this.names.state2]=s2;
    const out = await this.decoderJointSession.run(feeds);
    const logits = out.outputs || out.logits || out['0'] || Object.values(out)[0];
    const s1o = out.output_states_1 || Object.values(out)[1];
    const s2o = out.output_states_2 || Object.values(out)[2];
    const tokenProbs = Array.from(logits.data.slice(0, this.vocabSize));
    const stepProbs  = Array.from(logits.data.slice(this.vocabSize));
    const predictedStep = stepProbs.length>0 ? stepProbs.indexOf(Math.max(...stepProbs)) : 0;
    return { tokenProbs, predictedStep, newState: { state1: s1o.data, state2: s2o.data, state1Shape: prevState.state1Shape, state2Shape: prevState.state2Shape } };
  }
  async tdtDecode(encBTD) {
    const [B,T,D] = encBTD.dims; let prev = this.createDecoderState(); const tokens=[]; let t=0, emitted=0;
    while (t < T) {
      const step = await this.tdtDecodeStep(encBTD, t, tokens, prev); if (!step) break;
      const tok = step.tokenProbs.indexOf(Math.max(...step.tokenProbs));
      if (tok !== this.blankId) { prev = step.newState; tokens.push(tok); emitted++; }
      if (step.predictedStep > 0) { t += step.predictedStep; emitted = 0; }
      else if (tok === this.blankId || emitted === this.maxTokensPerStep) { t += 1; emitted = 0; }
    }
    return { tokens };
  }
  tokensToText(tokens) {
    if (!tokens || tokens.length===0) return '';
    if (!this.id_to_token || !Object.keys(this.id_to_token).length) return `[${tokens.length} tokens decoded]`;
    return tokens.map(id => this.id_to_token[id]).filter(tok => tok && tok !== '<blk>' && tok !== '<pad>' && tok !== '<unk>').map(tok => tok.replace(/▁/g,' ').replace(/Ġ/g,' ')).join('').replace(/\s+/g,' ').trim();
  }
  async transcribe(audioData) {
    const x = preprocessAudio(audioData);
    const SAMPLE_RATE = 16000; const CHUNK_SEC = 25, OVERLAP_SEC = 0.5;
    const CHUNK_SAMPLES = CHUNK_SEC * SAMPLE_RATE; const OVERLAP_SAMPLES = Math.floor(OVERLAP_SEC * SAMPLE_RATE);
    const STEP = Math.max(1, CHUNK_SAMPLES - OVERLAP_SAMPLES);
    const runOnce = async (chunk) => {
      const waveforms = new ort.Tensor('float32', chunk, [1, chunk.length]);
      const lens = new ort.Tensor('int64', new BigInt64Array([BigInt(chunk.length)]), [1]);
      const pre = await this.preprocessorSession.run({ waveforms, waveforms_lens: lens });
      const features = pre.features || pre.mel || Object.values(pre)[0];
      const features_lens = pre.features_lens || pre.length || Object.values(pre)[1];
      const enc = await this.encoderSession.run({ audio_signal: features, length: features_lens });
      let encBTD = enc.outputs || enc.encoded || Object.values(enc)[0];
      if (encBTD.dims.length===3 && encBTD.dims[1] > encBTD.dims[2]) {
        const [B,D,T] = encBTD.dims; const src = encBTD.data; const trans = new Float32Array(src.length);
        for (let b=0;b<B;b++) for (let t=0;t<T;t++) for (let d=0;d<D;d++) trans[b*T*D + t*D + d] = src[b*D*T + d*T + t];
        encBTD = new ort.Tensor('float32', trans, [B,T,D]);
      }
      const { tokens } = await this.tdtDecode(encBTD);
      return this.tokensToText(tokens) || '';
    };

    if (x.length <= CHUNK_SAMPLES) return await runOnce(x) || '[No speech detected]';
    const parts = [];
    for (let s=0; s<x.length; s+=STEP) {
      const e = Math.min(x.length, s+CHUNK_SAMPLES);
      try { const t = await runOnce(x.subarray(s,e)); if (t && t.trim()) parts.push(t.trim()); } catch (e) { logger.warn(`Chunk failed [${s},${e}) ${e.message}`); }
      await new Promise(r=>setTimeout(r,0));
    }
    return parts.join(' ').replace(/\s+/g,' ').trim() || '[No speech detected]';
  }
  dispose() { this.preprocessorSession?.release(); this.encoderSession?.release(); this.decoderJointSession?.release(); }
}

let currentModel = null; let currentModelId = null; let loadingPromise = null;

async function loadModel(modelId) {
  if (currentModelId === modelId && currentModel) return currentModel;
  if (loadingPromise && currentModelId === modelId) return await loadingPromise;
  loadingPromise = (async () => {
    try {
      currentModel?.dispose(); currentModel = null;
      process.send?.({ type: 'model_loading_started', modelId });
      const dir = await ensureModelFiles(modelId);
      const vocab = await loadVocabulary(dir);
      const m = new ParakeetTDTModel(dir, vocab);
      await m.initialize();
      currentModel = m; currentModelId = modelId;
      process.send?.({ type: 'model_loaded', modelId });
      return m;
    } catch (e) {
      process.send?.({ type: 'model_load_error', modelId, error: e.message });
      throw e;
    } finally { loadingPromise = null; }
  })();
  return await loadingPromise;
}

async function processTranscription(audioData, modelId) {
  const model = await loadModel(modelId);
  const start = Date.now();
  const text = await model.transcribe(audioData);
  const duration = Date.now() - start;
  return { text, confidence: 0.95, duration, modelId };
}

process.on('message', async (data) => {
  try {
    const { type, id, audioData, modelId, payload } = data || {};
    if (type === 'init') {
      if (payload?.logLevel) logger.setLevel(payload.logLevel);
      if (payload?.cacheDir) MODEL_CACHE_DIR = payload.cacheDir;
      process.send?.({ type: 'init_complete', id });
    } else if (type === 'install_model') {
      await ensureModelFiles(modelId);
      process.send?.({ type: 'download-complete', modelId });
    } else if (type === 'transcribe') {
      const result = await processTranscription(audioData, modelId);
      process.send?.({ type: 'transcription_result', id, result });
    } else if (type === 'dispose') {
      currentModel?.dispose(); currentModel = null; currentModelId = null; process.send?.({ type: 'disposed', id });
    } else if (type === 'set_log_level') {
      if (payload?.level) logger.setLevel(payload.level);
      process.send?.({ type: 'log_level_changed', id, level: payload?.level || 'unchanged' });
    }
  } catch (e) {
    process.send?.({ type: 'transcription_error', id: data?.id, error: e.message });
  }
});

module.exports = { MODEL_CONFIGS };

logger.info('Parakeet CPU worker initialized');
