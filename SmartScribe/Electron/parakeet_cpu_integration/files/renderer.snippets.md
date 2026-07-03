# Renderer Snippets

Resample audio to 16 kHz Float32 mono and invoke local transcription via IPC.

```ts
const TARGET_SR = 16000;

export async function transcribeWithParakeetCPU(audioBlob: Blob, modelId: string): Promise<string> {
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

    // With contextIsolation + preload bridge
    const result = await window.parakeet.transcribeLocal(modelId, buf);
    return result.text || '';

    // If nodeIntegration is enabled instead, you could do:
    // const { ipcRenderer } = require('electron');
    // const result = await ipcRenderer.invoke('transcribe-local', { modelId, audioData: buf });
  } finally {
    if (audioContext && audioContext.state !== 'closed') await audioContext.close().catch(() => {});
  }
}
```

Optional model entries for UI:
```ts
export const AVAILABLE_LOCAL_MODELS = [
  { id: 'istupakov/parakeet-tdt-0.6b-v3-onnx', name: 'Parakeet V3 Multilingual' },
  { id: 'istupakov/parakeet-tdt-0.6b-v2-onnx', name: 'Parakeet V2 English' },
];
```
