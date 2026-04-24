// ───────── preload bridge for Whisper + file picker ─────────
const { contextBridge, ipcRenderer } = require('electron');

// надёжный маркер, что мы в Electron
try { contextBridge.exposeInMainWorld('__ELECTRON__', true); } catch {}

// аккуратный IPC-бридж (без event аргумента наружу)
try {
  contextBridge.exposeInMainWorld('ipcRenderer', {
    invoke: (...args) => ipcRenderer.invoke(...args),
    send:   (...args) => ipcRenderer.send(...args),
  // Pass Electron's event object through so listeners that expect (event, payload)
  // or destructure the 2nd argument won't crash.
  on:     (ch, fn)  => ipcRenderer.on(ch, (e, ...a) => fn?.(e, ...a)),
  once:   (ch, fn)  => ipcRenderer.once(ch, (e, ...a) => fn?.(e, ...a)),
    removeAllListeners: (ch) => ipcRenderer.removeAllListeners(ch),
  });
} catch {}

contextBridge.exposeInMainWorld('whisper', {
  // Установка/удаление моделей (invoke → handle)
  installModel: (modelId) => ipcRenderer.invoke('whisper:installModel', modelId),
  removeModel:  (modelId) => ipcRenderer.invoke('whisper:removeModel', modelId),

  // Батч-транскрипция файла и PCM
  transcribeFile: (fname_inp, modelId, opts = {}) =>
    ipcRenderer.invoke('whisper:transcribeFile', { fname_inp, modelId, ...opts }),
  transcribePcm: (pcm32, sampleRate, modelId, opts = {}) =>
    ipcRenderer.invoke('whisper:transcribePcm', { pcm32, sampleRate, modelId, options: opts }),

  // События (если кому-то ещё нужны прогрессы)
  onProgress: (cb) => ipcRenderer.on('download-progress', (_e, m) => cb?.(m)),
  onComplete: (cb) => ipcRenderer.on('download-complete', (_e, m) => cb?.(m)),
  onError:    (cb) => ipcRenderer.on('download-failed',   (_e, m) => cb?.(m)),
});

contextBridge.exposeInMainWorld('dialogs', {
  pickAudioFile: () => ipcRenderer.invoke('pick-audio-file'),
});
// ───────── /preload bridge ─────────
