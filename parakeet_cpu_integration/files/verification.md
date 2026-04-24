# Verification steps

1) Install dependency
```bash
npm i onnxruntime-node
```

2) Place files
- Copy `transcription.fork.js` to your app root (or update paths accordingly)
- Wire main IPC using the snippets
- If using contextIsolation: add the preload bridge and its `global.d.ts`

3) Dev run
- Start your Electron app in dev mode
- In your renderer UI or devtools console, trigger a download:
```js
window.parakeet.precacheModel('istupakov/parakeet-tdt-0.6b-v2-onnx');
```
- Wait for `download-complete`

4) Record and transcribe
- Record a short audio (2–5s)
- Call your helper:
```js
await transcribeWithParakeetCPU(blob, 'istupakov/parakeet-tdt-0.6b-v2-onnx');
```
- Expect a string back. If empty, try a longer sample.

5) Production build checks
- Ensure `build.files` contains `transcription.fork.js`
- Ensure `asarUnpack` includes `**/onnxruntime-node/**`

6) Troubleshooting
- If you see `Cannot load onnxruntime binding`: check `asarUnpack` and arch.
- If timeouts: confirm model finished downloading and worker is running (add logs in main + worker).
- If nonsense text: verify 16 kHz mono Float32 PCM path and that the correct model ID is used.
