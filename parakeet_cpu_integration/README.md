# Parakeet CPU-only Integration (Node + ONNX Runtime)

This guide shows how to add NVIDIA Parakeet (TDT) models for CPU-only machines into your Electron app using Node.js and onnxruntime-node — no Python required.

The integration mirrors the working setup in this repo:
- Persistent Node worker (`transcription.fork.js`) that loads ONNX models with `CPUExecutionProvider`.
- Electron main process that starts the worker, exposes IPC for install/remove/transcribe, and forwards progress.
- Renderer that captures audio, resamples to 16 kHz Float32 PCM, and invokes local transcription via IPC.
- Packaged with electron-builder, including the worker file and native ONNX binaries.

---

## Contents
- `/parakeet_cpu_integration/files/` — ready-to-copy files (worker, preload bridge, type defs)
- This README — step-by-step instructions

---

## 0) Prerequisites

- Electron app (main + renderer). If you use `contextIsolation: true`, use the provided preload bridge.
- Node 18+ recommended.
- Install dependency:

```bash
npm i onnxruntime-node
```

Optional (only if you want to show a model picker UI): store some local state and surface a small Settings section.

---

## 1) Add the worker (CPU-only Parakeet)

Copy `files/transcription.fork.js` into your app (e.g., project root or `workers/`). This worker:
- Downloads Parakeet artifacts from Hugging Face to a cache folder.
- Creates ONNX sessions for nemo128 preprocessor, encoder, and decoder-joint with `CPUExecutionProvider`.
- Implements TDT decoding loop following onnx-asr patterns.
- Accepts messages: `init` (with `cacheDir`, `logLevel`), `install_model`, `transcribe`, `dispose`.

Important: on app start, the main process sends `init` and passes a cross-platform cache dir (e.g., `app.getPath('userData')/models`).

---

## 2) Wire the main process

Add to your Electron main process:

1) Start persistent worker
```js
const { fork } = require('child_process');
let transcriptionProcess;
let requestCounter = 0;
const pendingRequests = new Map();

function startTranscriptionProcess() {
  const scriptPath = path.join(__dirname, 'transcription.fork.js');
  const child = fork(scriptPath, [], {
    silent: true,
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }
  });

  child.send({ type: 'init', payload: { cacheDir: path.join(app.getPath('userData'), 'models'), logLevel: 'warn' } });

  child.on('message', (message) => {
    if (!message.requestId && message.type) {
      if (mainWindow) mainWindow.webContents.send(message.type, message);
      return;
    }
    const id = message.requestId ?? message.id;
    const cb = pendingRequests.get(id);
    if (!cb) return;
    const { resolve, reject } = cb;
    if (message.type === 'transcription_result') resolve(message.result);
    else if (message.type === 'transcription_error') reject(new Error(message.error || 'Worker error'));
    pendingRequests.delete(id);
  });

  child.on('exit', () => {
    pendingRequests.forEach(({ reject }) => reject(new Error('Transcription worker exited')));
    pendingRequests.clear();
    transcriptionProcess = startTranscriptionProcess();
  });

  return child;
}
```

2) IPC: transcribe
```js
ipcMain.handle('transcribe-local', async (_event, { modelId, audioData }) => {
  if (!transcriptionProcess) transcriptionProcess = startTranscriptionProcess();
  const id = ++requestCounter;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { pendingRequests.delete(id); reject(new Error('Transcription timed out')); }, 600000);
    pendingRequests.set(id, { resolve: (r) => { clearTimeout(timeout); resolve(r); }, reject: (e) => { clearTimeout(timeout); reject(e); } });
    transcriptionProcess.send({ type: 'transcribe', id, audioData, modelId, options: {} });
  });
});
```

3) IPC: install/remove model
```js
ipcMain.on('precache-local-model', async (event, { id }) => {
  if (!transcriptionProcess) transcriptionProcess = startTranscriptionProcess();
  const done = (msg) => { if (msg.type === 'download-complete' && msg.modelId === id) { event.reply('download-complete', { id, path: null }); cleanup(); } };
  const fail = (msg) => { if (msg.type === 'download-failed' && msg.modelId === id) { event.reply('download-failed', { id, error: msg.error }); cleanup(); } };
  const cleanup = () => { transcriptionProcess.off('message', done); transcriptionProcess.off('message', fail); };
  transcriptionProcess.on('message', done);
  transcriptionProcess.on('message', fail);
  transcriptionProcess.send({ type: 'install_model', modelId: id });
});

ipcMain.on('remove-local-model', async (event, { id }) => {
  const modelDir = path.join(app.getPath('userData'), 'models', id.replace('/', '_'));
  try {
    transcriptionProcess?.send({ type: 'dispose' });
    await fs.rm(modelDir, { recursive: true, force: true });
    event.reply('local-model-removed', { id, success: true });
  } catch (error) {
    event.reply('local-model-removed', { id, success: false, error: error.message });
  }
});
```

---

## 3) Preload bridge (if contextIsolation: true)

Copy `files/preload.parakeet.ts` to your preload and expose these APIs:
```ts
contextBridge.exposeInMainWorld('parakeet', {
  transcribeLocal: (modelId: string, audioBuffer: ArrayBuffer | Buffer) => ipcRenderer.invoke('transcribe-local', { modelId, audioData: audioBuffer }),
  precacheModel:  (id: string) => ipcRenderer.send('precache-local-model', { id }),
  removeModel:    (id: string) => ipcRenderer.send('remove-local-model', { id }),
  onDownloadComplete: (cb: (m: any) => void) => ipcRenderer.on('download-complete', (_e, m) => cb(m)),
  onDownloadFailed:   (cb: (m: any) => void) => ipcRenderer.on('download-failed',   (_e, m) => cb(m)),
});
```

Add a global type for TS (copy `files/global.d.ts`):
```ts
declare global {
  interface Window {
    parakeet: {
      transcribeLocal(modelId: string, audioBuffer: ArrayBuffer | Buffer): Promise<{ text: string }>;
      precacheModel(id: string): void;
      removeModel(id: string): void;
      onDownloadComplete(cb: (msg: any) => void): void;
      onDownloadFailed(cb: (msg: any) => void): void;
    };
  }
}
export {};
```

---

## 4) Renderer: capture, resample, invoke local

In your renderer, convert recorded audio to 16 kHz mono Float32 and send it:
```ts
const TARGET_SR = 16000;

async function transcribeWithParakeetCPU(audioBlob: Blob, modelId: string) {
  let audioContext: AudioContext | null = null;
  try {
    audioContext = new (window.AudioContext || (window as any).webkitAudioContext)();
    const arrayBuffer = await audioBlob.arrayBuffer();
    const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);

    let pcmData: Float32Array;
    if (audioBuffer.sampleRate === TARGET_SR) {
      pcmData = audioBuffer.getChannelData(0);
    } else {
      const offline = new OfflineAudioContext(1, audioBuffer.duration * TARGET_SR, TARGET_SR);
      const src = offline.createBufferSource();
      src.buffer = audioBuffer;
      src.connect(offline.destination);
      src.start();
      const resampled = await offline.startRendering();
      pcmData = resampled.getChannelData(0);
    }

    const buf = Buffer.from(pcmData.buffer);
    const result = await window.parakeet.transcribeLocal(modelId, buf);
    return result.text || '';
  } finally {
    if (audioContext && audioContext.state !== 'closed') await audioContext.close().catch(() => {});
  }
}
```

Optional: add simple model entries in your UI:
```ts
export const AVAILABLE_LOCAL_MODELS = [
  { id: 'istupakov/parakeet-tdt-0.6b-v3-onnx', name: 'Parakeet V3 Multilingual' },
  { id: 'istupakov/parakeet-tdt-0.6b-v2-onnx', name: 'Parakeet V2 English' },
];
```

---

## 5) Packaging

electron-builder config:
- Include the worker file:
```json
"files": [
  "dist/**/*",
  "main.js",
  "transcription.fork.js",
  "package.json"
]
```
- Unpack native ONNX binaries so Node can dlopen them at runtime:
```json
"asarUnpack": [
  "**/onnxruntime-node/**"
]
```
- The worker caches models under `app.getPath('userData')/models` (works on macOS, Windows, Linux).

---

## 6) Verification

1) Dev run: start your app, open a screen where you can trigger a download and transcription.
2) Download model:
```ts
window.parakeet?.precacheModel('istupakov/parakeet-tdt-0.6b-v2-onnx');
```
3) Wait for `download-complete` event.
4) Record a short sample (2–5s), call `transcribeWithParakeetCPU(blob, 'istupakov/parakeet-tdt-0.6b-v2-onnx')` and inspect returned text.
5) If ONNX loading fails in production build, verify `asarUnpack` and that `transcription.fork.js` is shipped.

---

## 7) Troubleshooting

- "Cannot load onnxruntime binding": ensure `asarUnpack` includes `onnxruntime-node` and that the correct arch is built.
- "Timeout": worker didn’t reply in time (10 min limit). Check logs and model cache; ensure download finished.
- Silent audio / wrong rate: verify resampling to 16 kHz mono Float32, and that you pass `Buffer.from(pcmData.buffer)` to IPC.
- Cross-platform cache: prefer the `cacheDir` sent from main over hardcoded OS paths.

---

## 8) Licenses and models

Models are downloaded from the `istupakov` Hugging Face repos referenced in `MODEL_CONFIGS`. Ensure you comply with model licenses and redistribute only allowed artifacts.
