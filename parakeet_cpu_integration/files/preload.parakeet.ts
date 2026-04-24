import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('parakeet', {
  transcribeLocal: (modelId: string, audioBuffer: ArrayBuffer | Buffer) => ipcRenderer.invoke('transcribe-local', { modelId, audioData: audioBuffer }),
  precacheModel:  (id: string) => ipcRenderer.send('precache-local-model', { id }),
  removeModel:    (id: string) => ipcRenderer.send('remove-local-model', { id }),
  onDownloadComplete: (cb: (msg: any) => void) => ipcRenderer.on('download-complete', (_e, msg) => cb(msg)),
  onDownloadFailed:   (cb: (msg: any) => void) => ipcRenderer.on('download-failed',   (_e, msg) => cb(msg)),
});
