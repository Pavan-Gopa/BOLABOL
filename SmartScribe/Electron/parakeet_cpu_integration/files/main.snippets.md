# Main Process Snippets (copy into your main process)

```js
// 1) Start worker once
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

// 2) IPC: transcribe
ipcMain.handle('transcribe-local', async (_event, { modelId, audioData }) => {
  if (!transcriptionProcess) transcriptionProcess = startTranscriptionProcess();
  const id = ++requestCounter;
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { pendingRequests.delete(id); reject(new Error('Transcription timed out')); }, 600000);
    pendingRequests.set(id, { resolve: (r) => { clearTimeout(timeout); resolve(r); }, reject: (e) => { clearTimeout(timeout); reject(e); } });
    transcriptionProcess.send({ type: 'transcribe', id, audioData, modelId, options: {} });
  });
});

// 3) IPC: install/remove model
ipcMain.on('precache-local-model', async (event, { id }) => {
  if (!transcriptionProcess) transcriptionProcess = startTranscriptionProcess();
  const done = (msg) => { if (msg.type === 'download-complete' && msg.modelId === id) { event.reply('download-complete', { id, path: null }); cleanup(); } };
  const fail = (msg) => { if (msg.type === 'download-failed'   && msg.modelId === id) { event.reply('download-failed',   { id, error: msg.error }); cleanup(); } };
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
