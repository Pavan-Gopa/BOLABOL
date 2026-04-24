// >>> BOOT BEACON: must be very first lines <<<
const bootLog = require('electron-log/main');
try { bootLog.initialize(); } catch {}
try { bootLog.transports.file.level = 'debug'; } catch {}
try {
  bootLog.info(`[MAIN BOOT] pid=${process.pid} file=${__filename}`);
  bootLog.info(`[MAIN LOG PATH] ${bootLog.transports.file.getFile().path}`);
} catch {}
// <<< /BOOT BEACON >>>

// main.js — unified & fixed
const {
  app, BrowserWindow, shell, globalShortcut, ipcMain,
  clipboard, Notification, dialog, Menu, Tray, nativeImage, screen, nativeTheme, systemPreferences
} = require('electron');
const path = require('path');
const log = require('electron-log/main');
const fs = require('fs').promises;
const fsSync = require('fs');
const { fork, exec, spawn } = require('child_process');
const os = require('os');

// ---- Command line switches (built app compat) ----
app.commandLine.appendSwitch('enable-unsafe-webgpu');
app.commandLine.appendSwitch('no-sandbox');
app.commandLine.appendSwitch('disable-web-security');
app.commandLine.appendSwitch('allow-running-insecure-content');

// ---- Single instance ----
const gotTheLock = app.requestSingleInstanceLock();
let mainWindow;
let tray = null;
let currentHotkey = '';
let overlayWindow = null;
let overlayReady = false;
let overlayMode = 'listening'; // 'listening' | 'processing'
let overlayPrefs = { position: 'bottom-right', scale: 1, sound: true, volume: 0.6 };
// Keep a small refcount for file-based processing overlays
let overlayFileBusy = 0;
// Track whether the current transcription was started via global hotkey so we can auto-paste
let hotkeyAutoPasteArmed = false;

function openMacAccessibilityPane() {
  if (process.platform !== 'darwin') return;
  try {
    exec('open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"');
  } catch (e) { try { log.warn('[HotkeyPaste] Failed to open Accessibility pane:', e); } catch {} }
}

// Helper: toggle DevTools for a given or focused window
function toggleDevTools(win = null) {
  try {
    const target = (win && !win.isDestroyed()) ? win : BrowserWindow.getFocusedWindow();
    if (!target) { try { log.warn('[DevTools] No target window to toggle DevTools'); } catch {} return; }
    if (target.webContents.isDevToolsOpened()) {
      target.webContents.closeDevTools();
      try { log.info('[DevTools] Closed DevTools'); } catch {}
    } else {
      target.webContents.openDevTools({ mode: 'detach' });
      try { log.info('[DevTools] Opened DevTools (detach)'); } catch {}
    }
  } catch (e) { try { log.warn('[DevTools] toggleDevTools error:', e); } catch {} }
}

function applyOverlayState() {
  const win = overlayWindow;
  if (!win || win.isDestroyed()) return;
  const mode = overlayMode;
  const js = `(() => {
    const mode = ${JSON.stringify(mode)};
    const card = document.querySelector('.card');
    const dot = document.querySelector('.dot');
    const bars = document.querySelectorAll('.bar');
    const label = document.querySelector('.label');
    if (card) card.className = 'card' + (mode === 'processing' ? ' processing' : '');
    if (dot) dot.className = 'dot' + (mode === 'processing' ? ' processing' : '');
    if (bars && bars.length) bars.forEach(b => { b.className = 'bar' + (mode === 'processing' ? ' processing' : ''); });
    if (label) label.textContent = (mode === 'processing' ? 'Processing…' : 'Listening…');
    return {
      mode,
      card: card && card.className,
      dot: dot && dot.className,
      bars: Array.from(bars || []).map(b => b.className),
      label: label && label.textContent
    };
  })();`;
  win.webContents.executeJavaScript(js).then((res) => {
    try { log.info('[Overlay] Applied state snapshot:', res); } catch {}
  }).catch(e => { try { log.warn('[Overlay] applyOverlayState error:', e); } catch {} });
}

function applyOverlayPrefsToDom() {
  const win = overlayWindow;
  if (!win || win.isDestroyed()) return;
  const prefs = overlayPrefs || { scale: 1 };
  const scale = Math.max(0.8, Math.min(1.6, Number(prefs.scale || 1)));
  const js = `(() => {
    const root = document.querySelector('.card');
    if (!root) return false;
    root.style.transform = 'scale(' + ${JSON.stringify(scale)} + ')';
    root.style.transformOrigin = 'top left';
    return true;
  })();`;
  win.webContents.executeJavaScript(js).catch(e => { try { log.warn('[Overlay] applyOverlayPrefsToDom error:', e); } catch {} });
}

function getOverlayBaseSize() { return { width: 260, height: 72 }; }
function getScaledOverlaySize() {
  const base = getOverlayBaseSize();
  const scale = Math.max(0.8, Math.min(1.6, Number((overlayPrefs && overlayPrefs.scale) || 1)));
  return { width: Math.round(base.width * scale), height: Math.round(base.height * scale) };
}
function positionOverlayWindow() {
  const win = overlayWindow; if (!win || win.isDestroyed()) return;
  const display = screen.getPrimaryDisplay(); const wa = display.workArea;
  const { width: w, height: h } = getScaledOverlaySize();
  const margin = 16;
  const pos = (overlayPrefs && overlayPrefs.position) || 'bottom-right';
  let x = wa.x + wa.width - w - margin;
  let y = wa.y + wa.height - h - margin;
  if (pos.includes('left')) x = wa.x + margin;
  if (pos.includes('top')) y = wa.y + margin;
  x = Math.max(wa.x, x); y = Math.max(wa.y, y);
  try { win.setBounds({ x, y, width: w, height: h, animate: false }); } catch (e) { try { log.warn('[Overlay] setBounds failed:', e); } catch {} }
}

if (!gotTheLock) {
  log.info('Another instance is already running. Quitting this instance.');
  app.quit();
} else {
  app.on('second-instance', () => {
    log.info('Second instance detected. Focusing existing window.');
    new Notification({ title: 'SmartScribe', body: 'SmartScribe is already running. Bringing it to focus.', silent: true }).show();
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show(); mainWindow.focus();
    }
  });
}

// ---- Logging ---- (already initialized in BOOT BEACON; avoid duplicate initialize)
const normalizeLevel = (v) => (v || '').toString().toLowerCase();
let currentLogLevel = normalizeLevel(process.env.SMARTSCRIBE_LOG_LEVEL || process.env.SMARTSCRIBE_LOG || 'debug');
const LOG_ORDER = { error: 0, warn: 1, info: 2, debug: 3 };
function canEmit(level) {
  const lvl = normalizeLevel(level);
  return (LOG_ORDER[lvl] ?? 2) <= (LOG_ORDER[currentLogLevel] ?? 3);
}
function applyLogLevel(level) {
  const lvl = normalizeLevel(level);
  currentLogLevel = lvl;
  try { log.transports.file.level = lvl; } catch {}
  try { if (log.transports.console) { log.transports.console.level = lvl; } } catch {}
}
applyLogLevel(currentLogLevel);
log.info(`App starting with log level: ${currentLogLevel}`);

// ---- macOS Microphone Permission Handshake ----
async function ensureMicrophoneAccess() {
  if (process.platform !== 'darwin') { try { log.info('[MicPerm] Skipping microphone permission check (platform != darwin)'); } catch {}; return true; }
  try {
    let status = systemPreferences.getMediaAccessStatus('microphone');
    try { log.info(`[MicPerm] Initial status: ${status}`); } catch {}
    if (status === 'not-determined') {
      let granted = false;
      try {
        granted = await systemPreferences.askForMediaAccess('microphone');
        try { log.info(`[MicPerm] askForMediaAccess returned: ${granted}`); } catch {}
      } catch (e) { try { log.warn('[MicPerm] askForMediaAccess error:', e); } catch {} }
      status = systemPreferences.getMediaAccessStatus('microphone');
      try { log.info(`[MicPerm] Post-request status: ${status}`); } catch {}
      if (!granted) {
        try {
          dialog.showMessageBox({
            type: 'warning', title: 'Microphone Access Required',
            message: 'SmartScribe needs microphone access to capture audio. Please enable microphone permission in System Settings > Privacy & Security > Microphone. Then restart SmartScribe.',
            buttons: ['OK']
          });
        } catch {}
        return false;
      }
    } else if (status === 'denied' || status === 'restricted') {
      try { log.warn(`[MicPerm] Status is ${status}. Informing user.`); } catch {}
      try {
        dialog.showMessageBox({
          type: 'warning', title: 'Microphone Access Denied',
          message: `SmartScribe cannot access the microphone (status: ${status}). Open System Settings > Privacy & Security > Microphone and enable SmartScribe. Then quit and relaunch the app.`,
          buttons: ['OK']
        });
      } catch {}
      return false;
    } else if (status === 'granted') {
      try { log.info('[MicPerm] Microphone access already granted.'); } catch {}
    } else {
      try { log.info(`[MicPerm] Unhandled status: ${status}`); } catch {}
    }
    return status === 'granted';
  } catch (e) {
    try { log.error('[MicPerm] Unexpected error while checking microphone permission:', e); } catch {}
    // Do not block startup on error; allow renderer to attempt getUserMedia which will surface errors.
    return true;
  }
}

// ---- App paths ----
app.setPath('userData', path.join(app.getPath('appData'), app.getName()));

// ---- Window state persistence (size/position) ----
let windowState = null; // { x, y, width, height, isMaximized }
function getWindowStateFile() {
  try { return path.join(app.getPath('userData'), 'window-state.json'); } catch { return null; }
}
function loadWindowState() {
  const file = getWindowStateFile();
  if (!file) return null;
  try {
    if (!fsSync.existsSync(file)) return null;
    const raw = fsSync.readFileSync(file, 'utf8');
    const obj = JSON.parse(raw);
    if (!obj || typeof obj !== 'object') return null;
    const out = {
      x: typeof obj.x === 'number' ? obj.x : undefined,
      y: typeof obj.y === 'number' ? obj.y : undefined,
      width: typeof obj.width === 'number' ? obj.width : 800,
      height: typeof obj.height === 'number' ? obj.height : 980,
      isMaximized: !!obj.isMaximized,
    };
    return out;
  } catch (e) {
    try { log.warn('[WindowState] Failed to load state:', e); } catch {}
    return null;
  }
}
function ensureVisibleOnSomeDisplay(bounds) {
  try {
    const displays = screen.getAllDisplays();
    const wa = (displays && displays.length ? displays : [screen.getPrimaryDisplay()]).map(d => d.workArea);
    const containsPoint = (r, px, py) => px >= r.x && py >= r.y && px < (r.x + r.width) && py < (r.y + r.height);
    const clamp = (v, min, max) => Math.min(max, Math.max(min, v));

    // If no x/y provided, return as-is (Electron will center)
    if (typeof bounds.x !== 'number' || typeof bounds.y !== 'number') return bounds;

    // Pick workArea that contains the top-left point; fallback to primary
    let area = wa.find(r => containsPoint(r, bounds.x, bounds.y)) || (screen.getPrimaryDisplay().workArea);
    const maxW = Math.max(100, area.width);
    const maxH = Math.max(100, area.height);
    const width = clamp(bounds.width || 800, 300, maxW);
    const height = clamp(bounds.height || 980, 300, maxH);
    const x = clamp(bounds.x, area.x, area.x + area.width - width);
    const y = clamp(bounds.y, area.y, area.y + area.height - height);
    return { x, y, width, height };
  } catch {
    return bounds;
  }
}
async function saveWindowState() {
  try {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    if (mainWindow.isMinimized()) return; // don't save minimized positions
    const isMax = mainWindow.isMaximized();
    const b = isMax ? mainWindow.getNormalBounds() : mainWindow.getBounds();
    windowState = { x: b.x, y: b.y, width: b.width, height: b.height, isMaximized: isMax };
    const file = getWindowStateFile(); if (!file) return;
    await fs.writeFile(file, JSON.stringify(windowState), 'utf8');
    try { log.info('[WindowState] Saved:', windowState); } catch {}
  } catch (e) { try { log.warn('[WindowState] Save failed:', e); } catch {} }
}
function saveWindowStateSync() {
  try {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    if (mainWindow.isMinimized()) return; // don't save minimized positions
    const isMax = mainWindow.isMaximized();
    const b = isMax ? mainWindow.getNormalBounds() : mainWindow.getBounds();
    windowState = { x: b.x, y: b.y, width: b.width, height: b.height, isMaximized: isMax };
    const file = getWindowStateFile(); if (!file) return;
    fsSync.writeFileSync(file, JSON.stringify(windowState));
    try { log.info('[WindowState] Saved (sync):', windowState); } catch {}
  } catch (e) { try { log.warn('[WindowState] Sync save failed:', e); } catch {} }
}
let _saveTimer = null;
function scheduleSaveWindowState() {
  try { if (_saveTimer) clearTimeout(_saveTimer); } catch {}
  _saveTimer = setTimeout(() => { saveWindowState(); }, 250);
}

// ---- Tray helpers ----
function getAssetPath(...paths_) {
  const basePath = app.isPackaged ? path.join(process.resourcesPath, 'assets') : path.join(__dirname, 'assets');
  return path.join(basePath, ...paths_);
}
function getAppIconPath() {
  const iconPath = getAssetPath('icons', 'icon.ico');
  if (!fsSync.existsSync(iconPath)) {
    log.error(`[ICON] Main application icon not found at: ${iconPath}`);
    return null;
  }
  return iconPath;
}

// Compute desired tray icon pixel size for Windows based on DPI
function getDesiredWindowsTraySize() {
  try {
    const sf = Math.max(1, Number(screen.getPrimaryDisplay()?.scaleFactor || 1));
    const approx = Math.round(16 * sf);
    const allowed = [16, 20, 24, 32, 40, 48];
    let best = allowed[0];
    let bestDiff = Math.abs(allowed[0] - approx);
    for (const s of allowed) {
      const d = Math.abs(s - approx);
      if (d < bestDiff) { best = s; bestDiff = d; }
    }
    return best;
  } catch { return 32; }
}

function buildMacTemplateImage() {
  // Re-implemented: createFromPath + add 2x representation via buffer to avoid empty image issues
  try {
    const p1x = getAssetPath('icons', 'trayTemplate.png');
    const p2x = getAssetPath('icons', 'trayTemplate@2x.png');
    const has1x = fsSync.existsSync(p1x);
    const has2x = fsSync.existsSync(p2x);
    if (!has1x && !has2x) return null;
    const base = has1x ? p1x : p2x;
    let img = nativeImage.createFromPath(base);
    if (has2x) {
      try {
        const buf2 = fsSync.readFileSync(p2x);
        img.addRepresentation({ scaleFactor: 2, buffer: buf2 });
      } catch (e) { log.warn('[Tray] Failed adding 2x tray representation:', e); }
    }
    try { img.setTemplateImage(true); } catch {}
    return img;
  } catch (e) { try { log.warn('buildMacTemplateImage failed:', e); } catch {} return null; }
}

function pickWindowsTrayPath(isDark) {
  const desired = getDesiredWindowsTraySize();
  const base = isDark ? 'tray-win-dark' : 'tray-win-light';
  // Try size-specific file first (e.g., tray-win-dark-20.png)
  let p = getAssetPath('icons', `${base}-${desired}.png`);
  if (!fsSync.existsSync(p)) {
    // Try nearest smaller then larger among common sizes
    const candidates = [16, 20, 24, 32, 40, 48]
      .sort((a, b) => Math.abs(a - desired) - Math.abs(b - desired))
      .map(sz => getAssetPath('icons', `${base}-${sz}.png`));
    const found = candidates.find(fp => fsSync.existsSync(fp));
    p = found || getAssetPath('icons', `${base}.png`);
  }
  if (!fsSync.existsSync(p)) {
    // Legacy fallbacks (tray-light/dark) then generic tray.png
    const legacy = isDark ? getAssetPath('icons', 'tray-light.png') : getAssetPath('icons', 'tray-dark.png');
    p = fsSync.existsSync(legacy) ? legacy : getAssetPath('icons', 'tray.png');
  }
  return p;
}

// Tray icon selection by platform/theme with safe fallbacks and DPI awareness
function getTrayNativeImage() {
  try {
    const isMac = process.platform === 'darwin';
    const isWindows = process.platform === 'win32';
    if (isMac) {
      // Prefer monochrome template icon (1x/2x representations)
      let img = buildMacTemplateImage();
      if (!img) {
        // Fallback: single file template or generic
        let p = getAssetPath('icons', 'trayTemplate.png');
        if (!fsSync.existsSync(p)) p = getAssetPath('icons', 'tray.png');
        img = nativeImage.createFromPath(p);
        try { img.setTemplateImage(true); } catch {}
      }
      if (!img.isEmpty()) {
        return img;
      }
    } else if (isWindows) {
      const dark = !!nativeTheme?.shouldUseDarkColors;
      let p = pickWindowsTrayPath(dark);
      const img = nativeImage.createFromPath(p);
      if (!img.isEmpty()) return img;
    }
    // Linux or ultimate fallback
    const fallback = getAssetPath('icons', 'tray.png');
    const img = nativeImage.createFromPath(fallback);
    return img;
  } catch (e) {
    try { log.warn('getTrayNativeImage failed, using empty image:', e); } catch {}
    return nativeImage.createEmpty();
  }
}
function destroyTray() {
  try { if (tray) { tray.destroy(); tray = null; log.info('Tray destroyed successfully.'); } } catch (e) { log.error('Error destroying tray:', e); }
}

// ===================================================================
//                    PERSISTENT TRANSCRIBER WORKER
// ===================================================================
let transcriptionProcess = null;
let requestCounter = 0;
const pendingRequests = new Map();
let isAppQuitting = false;
let isWorkerDisposing = false;
let workerStarted = false;

let parakeetProcess = null;
let parakeetWorkerStarted = false;
const parakeetPendingRequests = new Map();

const isParakeetModel = (modelId) => {
  try {
    return typeof modelId === 'string' && /parakeet/i.test(modelId);
  } catch {
    return false;
  }
};

function startTranscriptionProcess() {
  const scriptPath = path.join(__dirname, 'transcription.fork.js');
  log.info('[Transcriber] Starting worker, path:', scriptPath);
  if (!fsSync.existsSync(scriptPath)) {
    log.error('[Transcriber] transcription.fork.js NOT FOUND!');
  } else {
    log.info('[Transcriber] transcription.fork.js size=' + fsSync.statSync(scriptPath).size + ' bytes');
  }

  const child = fork(scriptPath, [], {
    silent: true,
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
    stdio: ['pipe','pipe','pipe','ipc']
  });
  transcriptionProcess = child;
  workerStarted = true;
  log.info('[Transcriber] fork() pid=' + (child && child.pid));

  child.stdout?.on('data', d => log.info('[Fork STDOUT]: ' + String(d).trim()));
  child.stderr?.on('data', d => {
    const s = String(d).trim();
    // Downgrade noisy stderr lines that are informational
    const infoPatterns = [
      /ggml/i,
      /whisper/i,
      /model( |_)?load(ed)?/i,
      /init/i,
      /vulkan/i,
      /buffer|cache|allocator/i
    ];
    if (infoPatterns.some(re => re.test(s))) {
      if (canEmit('info')) log.info('[Fork STDERR→info]: ' + s);
    } else {
      // Keep errors regardless of level
      log.error('[Fork STDERR]: ' + s);
    }
  });

  child.on('message', (m) => {
    if (!m || !m.type) return;

    if (m.type === 'log') {
      const { level='info', message='', args=[] } = m;
      if (level === 'error' || canEmit(level)) {
        (log[level] || log.info)(`[Transcription Worker] ${message}`, ...args);
      }
      return;
    }

    // normalize model download events
    if (m.type === 'download_progress') m.type = 'download-progress';
    if (m.type === 'download-progress') {
      // Map worker fields → progress percent
      let pct = undefined;
      if (typeof m.percent === 'number') pct = m.percent;
      else if (typeof m.received === 'number' && typeof m.total === 'number' && m.total > 0) {
        pct = Math.round((m.received / m.total) * 100);
      }
      const progress = Math.max(0, Math.min(100, Number(pct ?? 0)));
      const payload = { id: m.modelId, modelId: m.modelId, progress, status: m.status, received: m.received, total: m.total };
      try { mainWindow?.webContents?.send('download-progress', payload); } catch {}
      return;
    }
    if (m.type === 'download-complete') {
      const payload = { id: m.modelId, modelId: m.modelId, path: m.path ?? null };
      try { mainWindow?.webContents?.send('download-complete', payload); } catch {}
      return;
    }
    if (m.type === 'download-failed') {
      const payload = { id: m.modelId, modelId: m.modelId, error: m.error || 'failed' };
      try { mainWindow?.webContents?.send('download-failed', payload); } catch {}
      return;
    }
    if (m.type === 'local-model-removed' || m.type === 'model_loaded' || m.type === 'model_load_error' || m.type === 'probe-complete') {
      try { mainWindow?.webContents?.send(m.type === 'probe-complete' ? 'gpu-probe-result' : m.type, m); } catch {}
      return;
    }

    // RPC replies
    const actualId = (m.requestId ?? m.id);
    if (actualId != null) {
      const entry = pendingRequests.get(actualId);
      if (!entry) return;
      if (m.type === 'transcription-complete' || m.type === 'transcription_result') {
        // Forward compute provider (CPU/GPU backend) to renderer for the model used
        try {
          const engine = (m.result && (m.result.engine || m.result.backend)) || '';
          const e = String(engine).toLowerCase();
          let provider = 'cpu';
          if (e.includes('vulkan')) provider = 'vulkan';
          else if (e.includes('metal')) provider = 'metal';
          else if (e.includes('cuda') || e.includes('cublas')) provider = 'cuda';
          else if (e.includes('hip') || e.includes('rocm')) provider = 'rocm';
          else if (e.includes('openvino')) provider = 'openvino';
          else if (e.includes('directml') || e.includes('dml')) provider = 'directml';
          else if (e.includes('gpu')) provider = (process.platform === 'darwin' ? 'metal' : 'vulkan');
          const idForModel = entry.modelId || entry.model || null;
          if (idForModel && mainWindow?.webContents) {
            mainWindow.webContents.send('model-provider-status', { id: idForModel, provider });
          }
        } catch {}
        try {
          if (hotkeyAutoPasteArmed && m?.result?.text) {
            const txt = String(m.result.text).trim();
            autoPasteTranscriptText(txt, 'Whisper');
          }
        } catch (e2) { log.warn('[HotkeyPaste] Auto-paste error:', e2); }
        finally { hotkeyAutoPasteArmed = false; }
        pendingRequests.delete(actualId); entry.resolve(m.result || m);
      } else if (m.type === 'error' || m.type === 'transcription_error') {
        hotkeyAutoPasteArmed = false; // reset on failure
        // Mark provider as failed for this model
        try {
          const idForModel = entry.modelId || entry.model || null;
          if (idForModel && mainWindow?.webContents) {
            mainWindow.webContents.send('model-provider-status', { id: idForModel, provider: 'failed', error: m.error || 'Transcription error' });
          }
        } catch {}
        pendingRequests.delete(actualId); entry.reject(new Error(m.error || 'Transcription error'));
      }
    }
  });

  child.on('exit', (code, signal) => {
    const intentional = isAppQuitting || isWorkerDisposing || signal === 'SIGTERM' || code === 0;
    try { pendingRequests.forEach(({ reject }) => reject(new Error('Transcription process exited'))); pendingRequests.clear(); } catch {}

    if (intentional) {
      log.info(`Transcription process stopped intentionally. Code: ${code}, Signal: ${signal || 'none'}.`);
      isWorkerDisposing = false;
      transcriptionProcess = null;
      workerStarted = false;
      return;
    }
    log.error(`Transcription process crashed. Code: ${code}, Signal: ${signal || 'none'}. Restarting…`);
    startTranscriptionProcess();
  });

  try {
    const modelsDir = path.join(app.getPath('userData'), 'Models');
    child.send({ type: 'set_base_dir', baseDir: modelsDir });
    child.send({ type: 'set_log_level', payload: { level: currentLogLevel } });
  } catch (e) { log.warn('Failed to init transcriber worker:', e); }

  return child;
}
function ensureTranscriber() {
  if (workerStarted && transcriptionProcess && !transcriptionProcess.killed) return transcriptionProcess;
  return startTranscriptionProcess();
}

function handleParakeetMessage(m) {
  if (!m || !m.type) return;

  if (m.type === 'log') {
    const { level = 'info', message = '', args = [] } = m;
    if (level === 'error' || canEmit(level)) {
      (log[level] || log.info)(`[Parakeet Worker] ${message}`, ...args);
    }
    return;
  }

  if (m.type === 'download_progress' || m.type === 'download-progress') {
    const progress = Math.max(0, Math.min(100, Number(m.progress ?? 0)));
    const payload = {
      id: m.modelId,
      modelId: m.modelId,
      progress,
      status: m.status,
      received: m.received,
      total: m.total,
    };
    try { mainWindow?.webContents?.send('download-progress', payload); } catch {}
    return;
  }

  if (m.type === 'model_loading_started') {
    const payload = { id: m.modelId, modelId: m.modelId, status: 'start', progress: 0 };
    try { mainWindow?.webContents?.send('download-progress', payload); } catch {}
    return;
  }

  if (m.type === 'download-complete') {
    const payload = { id: m.modelId, modelId: m.modelId, path: m.path ?? null };
    try { mainWindow?.webContents?.send('download-complete', payload); } catch {}
    return;
  }

  if (m.type === 'download-failed') {
    const payload = { id: m.modelId, modelId: m.modelId, error: m.error || 'failed' };
    try { mainWindow?.webContents?.send('download-failed', payload); } catch {}
    return;
  }

  if (m.type === 'model_loaded' || m.type === 'model_load_error') {
    try { mainWindow?.webContents?.send(m.type, m); } catch {}
    return;
  }

  const actualId = m.requestId ?? m.id;
  if (actualId != null) {
    const entry = parakeetPendingRequests.get(actualId);
    if (!entry) return;
    if (m.type === 'transcription_result') {
      try {
        const providerPayload = { id: entry.modelId || null, provider: 'cpu' };
        if (providerPayload.id) {
          mainWindow?.webContents?.send('model-provider-status', providerPayload);
        }
      } catch {}
      parakeetPendingRequests.delete(actualId);
      entry.resolve(m.result || {});
      try {
        const text = (m.result && typeof m.result.text === 'string') ? m.result.text.trim() : '';
        if (hotkeyAutoPasteArmed && text) {
          autoPasteTranscriptText(text, 'Parakeet');
        }
      } catch (e) {
        log.warn('[HotkeyPaste] Error while handling Parakeet auto paste:', e);
      }
      hotkeyAutoPasteArmed = false;
      return;
    }
    if (m.type === 'transcription_error') {
      try {
        if (entry.modelId) {
          mainWindow?.webContents?.send('model-provider-status', {
            id: entry.modelId,
            provider: 'failed',
            error: m.error || 'Transcription error',
          });
        }
      } catch {}
      parakeetPendingRequests.delete(actualId);
      entry.reject(new Error(m.error || 'Transcription error'));
    }
  }
}

function startParakeetWorker() {
  const scriptPath = path.join(__dirname, 'parakeet.worker.js');
  log.info('[Parakeet] Starting worker, path:', scriptPath);
  if (!fsSync.existsSync(scriptPath)) {
    log.warn('[Parakeet] parakeet.worker.js NOT FOUND!');
  } else {
    log.info('[Parakeet] worker size=' + fsSync.statSync(scriptPath).size + ' bytes');
  }

  const child = fork(scriptPath, [], {
    silent: true,
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
    stdio: ['pipe', 'pipe', 'pipe', 'ipc'],
  });
  parakeetProcess = child;
  parakeetWorkerStarted = true;
  log.info('[Parakeet] fork() pid=' + (child && child.pid));

  child.stdout?.on('data', (d) => log.info('[Parakeet STDOUT]: ' + String(d).trim()));
  child.stderr?.on('data', (d) => log.warn('[Parakeet STDERR]: ' + String(d).trim()));

  child.on('message', handleParakeetMessage);

  child.on('exit', (code, signal) => {
    try {
      parakeetPendingRequests.forEach(({ reject }) => reject(new Error('Parakeet worker exited')));
    } catch {}
    parakeetPendingRequests.clear();

    const intentional = isAppQuitting || signal === 'SIGTERM' || code === 0;
    if (intentional) {
      log.info(`Parakeet worker stopped (code=${code}, signal=${signal || 'none'})`);
      parakeetProcess = null;
      parakeetWorkerStarted = false;
      return;
    }
    log.error(`Parakeet worker crashed (code=${code}, signal=${signal || 'none'}). Restarting…`);
    startParakeetWorker();
  });

  try {
    const cacheDir = path.join(app.getPath('userData'), 'Models');
    child.send({ type: 'init', payload: { cacheDir, logLevel: currentLogLevel } });
  } catch (e) {
    log.warn('Failed to init Parakeet worker:', e);
  }

  return child;
}

function ensureParakeetWorker() {
  if (parakeetWorkerStarted && parakeetProcess && !parakeetProcess.killed) return parakeetProcess;
  return startParakeetWorker();
}

function getWorkerContext(modelId) {
  if (isParakeetModel(modelId)) {
    return { worker: ensureParakeetWorker(), map: parakeetPendingRequests, kind: 'parakeet' };
  }
  return { worker: ensureTranscriber(), map: pendingRequests, kind: 'whisper' };
}

// small helper to RPC worker
function callWorker(msg) {
  ensureTranscriber();
  const id = ++requestCounter;
  const payload = { ...msg, id };
  const p = new Promise((resolve, reject) => pendingRequests.set(id, { resolve, reject }));
  transcriptionProcess.send(payload);
  return p;
}

function autoPasteTranscriptText(text, sourceLabel = 'Whisper') {
  if (!text) return;
  try {
    clipboard.writeText(text);
    log.info(`[HotkeyPaste] Copied ${sourceLabel} transcript to clipboard (len=${text.length})`);
  } catch (err) {
    log.warn(`[HotkeyPaste] Failed to copy ${sourceLabel} transcript to clipboard:`, err);
    return;
  }

  if (!mainWindow?.isFocused()) {
    if (process.platform === 'darwin') {
      setTimeout(() => {
        exec("osascript -e 'tell application \"System Events\" to keystroke \"v\" using {command down}'", (err) => {
          if (err) {
            log.warn('[HotkeyPaste] macOS paste failed (likely Accessibility permission):', err);
            try {
              new Notification({
                title: 'SmartScribe',
                body: 'Enable Accessibility permissions for SmartScribe to allow auto-paste. Opening settings…',
                silent: true,
              }).show();
            } catch {}
            try {
              openMacAccessibilityPane();
            } catch {}
          } else {
            log.info('[HotkeyPaste] macOS paste sent');
          }
        });
      }, 150);
    } else if (process.platform === 'win32') {
      exec("powershell -command \"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^v')\"", (err) => {
        if (err) log.warn('[HotkeyPaste] Windows paste failed:', err); else log.info('[HotkeyPaste] Windows paste sent');
      });
    } else if (process.platform === 'linux') {
      exec('which xdotool', (err) => {
        if (!err) {
          exec('xdotool key --clearmodifiers ctrl+v', (e2) => {
            if (e2) log.warn('[HotkeyPaste] Linux paste failed:', e2); else log.info('[HotkeyPaste] Linux paste sent');
          });
        } else {
          log.warn('[HotkeyPaste] xdotool not found; skipping paste');
        }
      });
    }
  } else {
    log.info('[HotkeyPaste] Main window focused; clipboard only (no paste).');
  }

  try {
    new Notification({
      title: 'SmartScribe',
      body: `Transcribed text copied${!mainWindow?.isFocused() ? ' & pasted' : ''}`,
      silent: true,
    }).show();
  } catch {}
}

// ---- Log level broadcast ----
function broadcastLogLevel(level) {
  try { mainWindow?.webContents?.send('log-level-changed', { level }); } catch {}
  try { transcriptionProcess?.send?.({ type: 'set_log_level', payload: { level } }); } catch {}
  try { parakeetProcess?.send?.({ type: 'set_log_level', payload: { level } }); } catch {}
}
ipcMain.on('set-log-level', (_e, { level }) => {
  if (!level) return;
  applyLogLevel(level);
  log.info(`Log level changed to ${level} (via IPC)`);
  broadcastLogLevel(level);
});

// ===================================================================
//                              TRAY
// ===================================================================
function createTray() {
  try {
  const img = getTrayNativeImage();
  if (!img || img.isEmpty()) { log.error('Failed to load tray icon. Tray will not be created.'); return; }

  tray = new Tray(img);
    tray.setToolTip('SmartScribe - Voice Notes & Transcription');
    const template = [
      { label: 'Show App', click: () => { if (mainWindow) { mainWindow.show(); mainWindow.focus(); } } },
      { label: 'Start Recording', click: () => { mainWindow?.webContents?.send('tray-start-recording'); } },
      { type: 'separator' },
      // Dev-only debug helpers
      ...(!app.isPackaged ? [{
        label: 'Debug',
        submenu: [
          { label: 'Toggle DevTools', click: () => toggleDevTools(mainWindow) },
          { type: 'separator' },
          { label: 'Overlay: Listening', click: () => { try { overlayMode = 'listening'; showOverlay(); } catch (e) { log.warn('[Overlay] Debug Listening failed:', e); } } },
          { label: 'Overlay: Processing', click: () => { try { overlayMode = 'processing'; showOverlay(); applyOverlayState(); } catch (e) { log.warn('[Overlay] Debug Processing failed:', e); } } },
          { label: 'Overlay: Hide', click: () => { try { hideOverlay(); } catch (e) { log.warn('[Overlay] Debug Hide failed:', e); } } },
          { type: 'separator' },
          { label: 'Test Auto-Paste (macOS)', click: () => {
            try {
              clipboard.writeText('SmartScribe paste test');
              if (process.platform === 'darwin') {
                setTimeout(() => {
                  exec("osascript -e 'tell application \"System Events\" to keystroke \"v\" using {command down}'", (err) => {
                    if (err) { log.warn('[Debug] Test paste failed. Opening Accessibility settings…', err); openMacAccessibilityPane(); }
                    else { log.info('[Debug] Test paste sent'); }
                  });
                }, 150);
              }
            } catch (e) { log.warn('[Debug] Test Auto-Paste error:', e); }
          } },
        ]
      }] : []),
      { type: 'separator' },
      { label: 'Quit SmartScribe', click: () => { log.info('Quit requested from tray menu.'); app.isQuiting = true; app.quit(); } },
    ];
    const contextMenu = Menu.buildFromTemplate(template);
    tray.setContextMenu(contextMenu);
    tray.on('click', () => {
      if (!mainWindow) return;
      if (mainWindow.isVisible()) mainWindow.hide(); else { mainWindow.show(); mainWindow.focus(); }
    });

    // Auto-switch tray icon when OS theme changes (Windows), ignored on mac when using template
    try {
      nativeTheme?.on?.('updated', () => {
        try {
          const next = getTrayNativeImage();
          if (next && !next.isEmpty()) tray.setImage(next);
        } catch (e) { log.warn('Failed to update tray icon on theme change:', e); }
      });
    } catch (e) { log.warn('nativeTheme hook failed:', e); }

    // Also update when display metrics (scale factor/DPI) change on Windows
    try {
      if (process.platform === 'win32') {
        const refresh = () => {
          try {
            const img2 = getTrayNativeImage();
            if (img2 && !img2.isEmpty()) tray.setImage(img2);
          } catch (e) { log.warn('Failed to update tray icon on display change:', e); }
        };
        screen.on('display-metrics-changed', refresh);
        screen.on('display-added', refresh);
        screen.on('display-removed', refresh);
      }
    } catch (e) { log.warn('screen hooks failed:', e); }
  } catch (e) { log.error('Failed to create tray:', e); }
}

// ===================================================================
//                           MAIN WINDOW
// ===================================================================
function createWindow() {
  try {
    log.info('Creating main window...');
    // load last window bounds and keep within visible area
    const saved = loadWindowState();
    const startBounds = ensureVisibleOnSomeDisplay({
      x: saved?.x, y: saved?.y, width: saved?.width ?? 800, height: saved?.height ?? 980
    });
    mainWindow = new BrowserWindow({
      width: startBounds.width, height: startBounds.height, minWidth: 600, minHeight: 700,
      x: typeof startBounds.x === 'number' ? startBounds.x : undefined,
      y: typeof startBounds.y === 'number' ? startBounds.y : undefined,
      icon: getAppIconPath(),
      webPreferences: {
        preload: path.join(__dirname, 'preload.js'),
        nodeIntegration: false, contextIsolation: true,
        webSecurity: false, allowRunningInsecureContent: true,
      },
      titleBarStyle: 'hidden',
      titleBarOverlay: { color: '#121212', symbolColor: '#E1E1E1', height: 40 },
      show: true, backgroundColor: '#121212',
    });

    // Restore maximized state after creation
    try { if (saved?.isMaximized) mainWindow.maximize(); } catch {}

    log.info('Loading index.html from dist...');
    mainWindow.loadFile(path.join(__dirname, 'dist', 'index.html'));

    mainWindow.webContents.setWindowOpenHandler(({ url }) => { log.info(`Opening external URL: ${url}`); shell.openExternal(url); return { action: 'deny' }; });

    mainWindow.webContents.on('render-process-gone', (_e, details) => { log.error('[render-process-gone]', details); });
    mainWindow.webContents.on('unresponsive', () => { log.error('[unresponsive] Renderer became unresponsive.'); });
    // Respect app log level when forwarding renderer console messages
  mainWindow.webContents.on('console-message', (_e, level, message, line, sourceId) => {
      // Electron provides: 0=log, 1=warn, 2=error
      // Map to our app levels
      const lvlFromConsole = level === 2 ? 'error' : level === 1 ? 'warn' : 'info';

      // Gate by currentLogLevel (error < warn < info < debug)
      const ORDER = { error: 0, warn: 1, info: 2, debug: 3 };
      const canLog = (ORDER[lvlFromConsole] ?? 2) <= (ORDER[currentLogLevel] ?? 3);
      if (!canLog) return;

  const electronLogLevel = lvlFromConsole; // use 'info'/'warn'/'error' to honor transport levels
  (log[electronLogLevel] || log.info)(`[renderer console] ${message} (${sourceId}:${line})`);
    });

    mainWindow.on('close', (event) => {
      try { scheduleSaveWindowState(); } catch {}
      if (!app.isQuiting) { event.preventDefault(); mainWindow.hide(); return false; }
    });

    // Save size/position changes (debounced)
    try {
      mainWindow.on('resize', scheduleSaveWindowState);
      mainWindow.on('move', scheduleSaveWindowState);
      mainWindow.on('maximize', scheduleSaveWindowState);
      mainWindow.on('unmaximize', scheduleSaveWindowState);
    } catch {}
  } catch (e) {
    log.error('Failed to create window:', e);
    dialog.showErrorBox('Fatal Error', 'An unexpected error occurred during startup. Please check the logs.');
    app.quit();
  }
}

// ===================================================================
//                              APP LIFECYCLE
// ===================================================================
app.whenReady().then(async () => {
  log.info('App is ready. Beginning microphone permission handshake…');
  let micOk = await ensureMicrophoneAccess();
  if (!micOk) {
    try { log.warn('[Startup] Microphone permission not granted. Continuing startup; recorder may yield silence.'); } catch {}
  } else {
    try { log.info('[Startup] Microphone permission confirmed.'); } catch {}
  }
  createWindow();
  createTray();
  ensureTranscriber();

  // DevTools are no longer auto-opened in development; use shortcuts or tray Debug menu to toggle

  // Register global shortcuts to toggle DevTools (F12 and Ctrl+Shift+L) — dev only
  if (!app.isPackaged) {
    try {
      const reg = (accel) => {
        const ok = globalShortcut.register(accel, () => toggleDevTools(mainWindow));
        if (ok) log.info(`[DevTools] Registered shortcut: ${accel}`);
        else log.warn(`[DevTools] Failed to register shortcut: ${accel}`);
      };
      reg('F12');
      reg('Control+Shift+L');
    } catch (e) { log.warn('[DevTools] Failed to register global shortcuts:', e); }
  }

  process.on('exit', () => { log.info('Process exit event fired.'); destroyTray(); });
});

app.on('before-quit', () => {
  log.info('App is quitting.');
  app.isQuiting = true;
  isAppQuitting = true;

  // Save window state immediately to avoid losing it on fast shutdown
  try { saveWindowStateSync(); } catch {}

  try { globalShortcut.unregisterAll(); } catch {}

  try {
    if (transcriptionProcess && !transcriptionProcess.killed) {
      isWorkerDisposing = true;
      log.info('Signaling transcription worker to exit (dispose)…');
      try { transcriptionProcess.send({ type: 'dispose' }); } catch {}
      setTimeout(() => {
        try {
          if (transcriptionProcess && !transcriptionProcess.killed) {
            log.warn('Force-killing transcription worker (SIGKILL) after timeout.');
            transcriptionProcess.kill('SIGKILL');
          }
        } catch {}
      }, 1000);
    }
  } catch (e) { log.warn('Error while stopping transcription worker:', e); }

  try {
    if (parakeetProcess && !parakeetProcess.killed) {
      log.info('Signaling Parakeet worker to exit…');
      try { parakeetProcess.send({ type: 'dispose' }); } catch {}
      setTimeout(() => {
        try {
          if (parakeetProcess && !parakeetProcess.killed) {
            log.warn('Force-killing Parakeet worker (SIGKILL) after timeout.');
            parakeetProcess.kill('SIGKILL');
          }
        } catch {}
      }, 1000);
    }
  } catch (e) { log.warn('Error while stopping Parakeet worker:', e); }

  try { if (overlayWindow && !overlayWindow.isDestroyed()) overlayWindow.destroy(); } catch {}
  destroyTray();
});
app.on('will-quit', () => { log.info('App will quit.'); destroyTray(); });
app.on('window-all-closed', () => { app.quit(); });

// ===================================================================
//                          OVERLAY (hotkey HUD)
// ===================================================================
const OVERLAY_HTML = `<!doctype html><html><head><meta charset="utf-8"/><meta http-equiv="X-UA-Compatible" content="IE=edge"/><meta name="viewport" content="width=device-width, initial-scale=1"/><title>SmartScribe Overlay</title><style>
:root{--bg:rgba(18,18,18,0.6);--border:rgba(255,255,255,0.2);--glow:rgba(255,59,48,0.6);--red:#ff3b30;--green:#34c759;--glow-green:rgba(52,199,89,0.6);--text:#f1f1f1}
html,body{margin:0;padding:0;background:transparent;font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,Apple Color Emoji,Segoe UI Emoji}
.overlay{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;pointer-events:none}
.card{display:flex;gap:10px;align-items:center;padding:10px 14px;border-radius:12px;background:var(--bg);border:1px solid var(--border);box-shadow:0 8px 24px rgba(0,0,0,.35),0 0 24px var(--glow) inset;backdrop-filter:blur(6px) saturate(120%)}
.card.processing{box-shadow:0 8px 24px rgba(0,0,0,.35),0 0 24px var(--glow-green) inset}
.dot{width:10px;height:10px;border-radius:50%;background:var(--red);box-shadow:0 0 10px var(--glow),0 0 18px var(--glow);animation:pulse 1.2s ease-in-out infinite}
.dot.processing{background:var(--green);box-shadow:0 0 10px var(--glow-green),0 0 18px var(--glow-green)}
.label{color:var(--text);font-size:12px;opacity:.9;margin-right:4px}
.bars{display:flex;gap:4px;align-items:end;height:28px}
.bar{width:4px;background:var(--red);border-radius:2px;box-shadow:0 0 10px var(--glow);animation:wave 1.1s ease-in-out infinite}
.bar.processing{background:var(--green);box-shadow:0 0 10px var(--glow-green)}
.bar:nth-child(1){height:30%;animation-delay:0s}.bar:nth-child(2){height:55%;animation-delay:.06s}.bar:nth-child(3){height:80%;animation-delay:.12s}.bar:nth-child(4){height:60%;animation-delay:.18s}.bar:nth-child(5){height:45%;animation-delay:.24s}.bar:nth-child(6){height:75%;animation-delay:.30s}.bar:nth-child(7){height:55%;animation-delay:.36s}.bar:nth-child(8){height:35%;animation-delay:.42s}
@keyframes pulse{0%,100%{transform:scale(1);opacity:1}50%{transform:scale(.76);opacity:.85}}
@keyframes wave{0%,100%{transform:scaleY(.65)}50%{transform:scaleY(1.3)}}
</style></head><body><div class="overlay"><div class="card"><div class="dot" aria-hidden="true"></div><div class="label">Listening…</div><div class="bars" role="img" aria-label="Recording level"><div class="bar"></div><div class="bar"></div><div class="bar"></div><div class="bar"></div><div class="bar"></div><div class="bar"></div><div class="bar"></div><div class="bar"></div></div></div></div></body></html>`;
function createOverlayWindow() {
  if (overlayWindow && !overlayWindow.isDestroyed()) return overlayWindow;
  try {
  const overlaySize = getScaledOverlaySize();
  const display = screen.getPrimaryDisplay(); const wa = display.workArea;
  // temp pos; will be corrected by positionOverlayWindow()
  const x = Math.max(wa.x, wa.x + wa.width - overlaySize.width - 16);
  const y = Math.max(wa.y, wa.y + wa.height - overlaySize.height - 16);

    overlayWindow = new BrowserWindow({
      width: overlaySize.width, height: overlaySize.height, x, y,
      frame: false, transparent: true, resizable: false, movable: false,
      focusable: false, skipTaskbar: true, alwaysOnTop: true, type: 'toolbar',
      backgroundColor: '#00000000',
      webPreferences: { nodeIntegration: false, contextIsolation: true, sandbox: true },
      show: false,
    });
    overlayWindow.setAlwaysOnTop(true, 'screen-saver');
    overlayReady = false;
    try {
      overlayWindow.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent(OVERLAY_HTML));
      overlayWindow.webContents.on('did-finish-load', () => {
        overlayReady = true;
        try { log.info('[Overlay] did-finish-load'); } catch {}
        applyOverlayPrefsToDom();
        positionOverlayWindow();
        applyOverlayState();
      });
    } catch (e) { log.error('Failed to load overlay HTML:', e); }
    return overlayWindow;
  } catch (e) { log.error('Failed to create overlay window:', e); overlayWindow = null; return null; }
}
function showOverlay() {
  const win = createOverlayWindow(); if (!win) return;
  try {
    positionOverlayWindow();
    if (!win.isVisible()) win.showInactive();
    if (overlayReady) applyOverlayState();
  } catch (e) { log.warn('Unable to show overlay:', e); }
}
function hideOverlay() { try { if (overlayWindow && !overlayWindow.isDestroyed()) overlayWindow.hide(); } catch {} }

function showFileProcessingOverlay() {
  try {
    overlayFileBusy++;
    overlayMode = 'processing';
    showOverlay();
  } catch {}
}
function hideFileProcessingOverlay() {
  try {
    overlayFileBusy = Math.max(0, overlayFileBusy - 1);
    if (overlayFileBusy === 0) hideOverlay();
  } catch {}
}

ipcMain.on('hotkey-transcription-start', () => {
  overlayMode = 'listening';
  try { log.info(`[Overlay] Event: transcription-start → mode=listening (ready=${overlayReady})`); } catch {}
  showOverlay();
  const win = overlayWindow; if (!win || win.isDestroyed()) return;
  const attempt = () => applyOverlayState();
  if (overlayReady) attempt(); else setTimeout(attempt, 40);
  setTimeout(() => { if (!win.isDestroyed()) applyOverlayState(); }, 200);
});
ipcMain.on('hotkey-transcription-end',   () => {
  hideOverlay();
  overlayMode = 'listening';
  try { log.info('[Overlay] Event: transcription-end → hide + mode reset to listening'); } catch {}
});
ipcMain.on('hotkey-processing-start',    () => {
  overlayMode = 'processing';
  try { log.info(`[Overlay] Event: processing-start → mode=processing (ready=${overlayReady})`); } catch {}
  const win = createOverlayWindow(); if (!win) return;
  try { if (!win.isVisible()) win.showInactive(); } catch {}
  // Prefer centralized state applier (null-safe) and retry once if DOM isn't ready yet.
  const attempt = () => applyOverlayState();
  if (overlayReady) attempt(); else setTimeout(attempt, 40);
  // Extra safety: schedule a second pass shortly after in case CSS/DOM painted late
  setTimeout(() => { if (!win.isDestroyed()) applyOverlayState(); }, 200);
});

// ===================================================================
//                            IPC (renderer)
// ===================================================================

// --- tiny WAV reader (PCM/IEEE float; mono/stereo → mono avg) ---
function readWavToFloat32(bufOrBuffer) {
  const b = Buffer.isBuffer(bufOrBuffer) ? bufOrBuffer : Buffer.from(bufOrBuffer);
  const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
  const text = (o, n) => String.fromCharCode(...new Uint8Array(dv.buffer, dv.byteOffset + o, n));
  if (text(0,4)!=='RIFF' || text(8,4)!=='WAVE') throw new Error('Not a RIFF/WAVE file');

  let off=12, fmt=null, dataOff=-1, dataLen=0;
  while (off + 8 <= dv.byteLength) {
    const id = text(off,4), sz = dv.getUint32(off+4, true); off += 8;
    if (id==='fmt ') {
      fmt = {
        audioFormat:   dv.getUint16(off+0,  true),
        numChannels:   dv.getUint16(off+2,  true),
        sampleRate:    dv.getUint32(off+4,  true),
        bitsPerSample: dv.getUint16(off+14, true),
      };
    } else if (id==='data') { dataOff = off; dataLen = sz; }
    off += sz + (sz & 1);
  }
  if (!fmt) throw new Error('WAV fmt chunk not found');
  if (dataOff < 0) throw new Error('WAV data chunk not found');

  const bytes = new Uint8Array(dv.buffer, dv.byteOffset + dataOff, dataLen);
  let interleaved;

  if (fmt.audioFormat === 1) {
    if (fmt.bitsPerSample === 16) {
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      const N = view.byteLength / 2, tmp = new Float32Array(N);
      for (let i=0;i<N;i++) tmp[i] = view.getInt16(i*2, true) / 32768;
      interleaved = tmp;
    } else if (fmt.bitsPerSample === 24) {
      const N = Math.floor(bytes.length/3), tmp = new Float32Array(N);
      for (let i=0;i<N;i++){ const i3=i*3; let v=(bytes[i3]|(bytes[i3+1]<<8)|(bytes[i3+2]<<16)); if(v&0x800000)v|=0xff000000; tmp[i]=v/8388608; }
      interleaved = tmp;
    } else if (fmt.bitsPerSample === 8) {
      const tmp = new Float32Array(bytes.length);
      for (let i=0;i<bytes.length;i++) tmp[i]=(bytes[i]-128)/128;
      interleaved = tmp;
    } else {
      throw new Error(`Unsupported PCM bitsPerSample: ${fmt.bitsPerSample}`);
    }
  } else if (fmt.audioFormat === 3) {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const N = view.byteLength / 4, tmp = new Float32Array(N);
    for (let i=0;i<N;i++) tmp[i] = view.getFloat32(i*4, true);
    interleaved = tmp;
  } else {
    throw new Error(`Unsupported WAV format tag: ${fmt.audioFormat}`);
  }

  const ch = fmt.numChannels;
  if (ch > 1) {
    const frames = Math.floor(interleaved.length / ch);
    const mono = new Float32Array(frames);
    for (let f=0,i=0; f<frames; f++) { let s=0; for (let c=0;c<ch;c++,i++) s += interleaved[i]; mono[f]=s/ch; }
    return { pcm: mono, sampleRate: fmt.sampleRate };
  }
  return { pcm: interleaved, sampleRate: fmt.sampleRate };
}

function linearResampleMono(input, fromSR, toSR){
  if (fromSR===toSR) return input;
  const ratio = fromSR/toSR, outLen = Math.max(1, Math.floor(input.length/ratio));
  const out = new Float32Array(outLen);
  for (let i=0;i<outLen;i++){
    const idx=i*ratio, i0=Math.floor(idx), frac=idx-i0;
    const s0=input[i0]||0, s1=input[i0+1]||0;
    out[i]=s0 + (s1-s0)*frac;
  }
  return out;
}
ipcMain.handle('whisper:transcribeFile', async (_event, { fname_inp, modelId, options = {} }) => {
  const { worker, map, kind } = getWorkerContext(modelId);
  return new Promise(async (resolve, reject) => {
    try {
      if (!fname_inp || !fsSync.existsSync(fname_inp)) return reject(new Error('Audio file not found'));
      const b = await fs.readFile(fname_inp);
      log.info(`[IPC:file] read bytes=${b.length}`);

      // Try to detect audio format
      const isWav = b.slice(0,4).toString('ascii')==='RIFF' && b.slice(8,12).toString('ascii')==='WAVE';
      const isMp3 = (b[0] === 0xFF && (b[1] & 0xE0) === 0xE0) || (b.slice(0,3).toString('ascii') === 'ID3');
  const isM4a = b.slice(4,8).toString('ascii') === 'ftyp';
  // Simple AIFF detection: 'FORM' at 0 and 'AIFF' or 'AIFC' at 8
  const isAiff = (b.slice(0,4).toString('ascii') === 'FORM') && ((b.slice(8,12).toString('ascii') === 'AIFF') || (b.slice(8,12).toString('ascii') === 'AIFC'));
      const isOgg = b.slice(0,4).toString('ascii') === 'OggS';
      const isFlac = b.slice(0,4).toString('ascii') === 'fLaC';
      
  const ext = (path.extname(fname_inp) || '').toLowerCase();
      const hasOpusHead = isOgg && b.indexOf('OpusHead') !== -1;
  log.info(`[IPC:file] Audio format detected: WAV=${isWav}, MP3=${isMp3}, M4A=${isM4a}, OGG=${isOgg}, FLAC=${isFlac}, AIFF=${isAiff}, ext=${ext}, OpusHead=${hasOpusHead}`);

      async function ffmpegTranscodeToWav16k(srcPath) {
        let ffmpegPath = (() => { try { return require('ffmpeg-static'); } catch { return null; } })();
        if (!ffmpegPath) throw new Error('ffmpeg-static not available for Opus decoding');
        // In packaged apps, binaries inside app.asar cannot be executed; use the unpacked path.
        try {
          if (app?.isPackaged && typeof ffmpegPath === 'string') {
            if (ffmpegPath.includes('app.asar')) {
              ffmpegPath = ffmpegPath.replace('app.asar', 'app.asar.unpacked');
            }
            // Fallback: construct from resourcesPath if needed
            if (!fsSync.existsSync(ffmpegPath)) {
              const alt = path.join(process.resourcesPath, 'app.asar.unpacked', 'node_modules', 'ffmpeg-static', path.basename(ffmpegPath));
              if (fsSync.existsSync(alt)) ffmpegPath = alt;
            }
          }
        } catch {}
        try { log.info(`[FFmpeg] Using binary: ${ffmpegPath}`); } catch {}
        const outPath = path.join(os.tmpdir(), `ss-${Date.now()}-${Math.random().toString(36).slice(2)}.wav`);
        return await new Promise((res, rej) => {
          log.info(`[FFmpeg] Transcoding to WAV 16k: ${srcPath} -> ${outPath}`);
          const args = ['-y', '-hide_banner', '-loglevel', 'error', '-i', srcPath, '-vn', '-sn', '-acodec', 'pcm_s16le', '-ac', '1', '-ar', '16000', '-f', 'wav', outPath];
          const p = spawn(ffmpegPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });
          let errBuf = '';
          p.stderr.on('data', d => { errBuf += String(d); });
          p.on('close', (code) => {
            if (code === 0 && fsSync.existsSync(outPath)) {
              log.info('[FFmpeg] Transcode complete');
              res(outPath);
            } else {
              log.error('[FFmpeg] Transcode failed', errBuf || `(exit ${code})`);
              rej(new Error('FFmpeg transcode failed'));
            }
          });
        });
      }

      if (isWav) {
        // WAV format - use existing conversion path
        const { pcm, sampleRate } = readWavToFloat32(b);
        const TARGET_SR = 16000;
        const mono16 = (sampleRate===TARGET_SR) ? pcm : linearResampleMono(pcm, sampleRate, TARGET_SR);
        const u8 = new Uint8Array(mono16.buffer, mono16.byteOffset, mono16.byteLength);
        if (!u8.byteLength) return reject(new Error('Decoded audio is empty'));
        log.info(`[IPC:file] WAV converted: sr=${TARGET_SR} frames=${mono16.length} bytes=${u8.byteLength}`);

        // Send converted PCM data to worker
        showFileProcessingOverlay();
        const id = ++requestCounter;
        const timeout = setTimeout(() => {
          map.delete(id); log.error('[IPC] File transcription timed out');
          try { hideFileProcessingOverlay(); } catch {}
          reject(new Error('Transcription timed out'));
        }, 10*60*1000);
        map.set(id, {
          resolve: (r)=>{ clearTimeout(timeout); try { hideFileProcessingOverlay(); } catch {}; log.info('[IPC] File transcription successful'); resolve(r); },
          reject:  (e)=>{ clearTimeout(timeout); try { hideFileProcessingOverlay(); } catch {}; log.error('[IPC] File transcription error:', e); reject(e); },
          modelId,
        });
        log.info(`[IPC:file→send] bytes=${mono16.byteLength}`);
        worker.send({
          type: 'transcribe',
          id, modelId,
          audioData: Buffer.from(mono16.buffer, mono16.byteOffset, mono16.byteLength),
          options: { sourceSampleRate: TARGET_SR, language: options.language || 'auto', threads: options.threads || 0, forceCpu: !!options.forceCpu }
        });
        
      } else if (ext === '.opus' || hasOpusHead) {
        // Explicit Opus-in-Ogg (.opus) — use ffmpeg to convert to WAV 16k, then proceed
        try {
          const wavPath = await ffmpegTranscodeToWav16k(fname_inp);
          const wb = await fs.readFile(wavPath);
          const { pcm, sampleRate } = readWavToFloat32(wb);
          const TARGET_SR = 16000;
          const mono16 = (sampleRate===TARGET_SR) ? pcm : linearResampleMono(pcm, sampleRate, TARGET_SR);
          const u8 = new Uint8Array(mono16.buffer, mono16.byteOffset, mono16.byteLength);
          if (!u8.byteLength) return reject(new Error('Decoded audio is empty after Opus transcode'));
          log.info(`[IPC:file] OPUS→WAV converted: sr=${TARGET_SR} frames=${mono16.length} bytes=${u8.byteLength}`);

          showFileProcessingOverlay();
          const id = ++requestCounter;
          const timeout = setTimeout(() => {
            map.delete(id); log.error('[IPC] File transcription timed out');
            try { hideFileProcessingOverlay(); } catch {}
            reject(new Error('Transcription timed out'));
          }, 10*60*1000);
          map.set(id, {
            resolve: (r)=>{ clearTimeout(timeout); try { hideFileProcessingOverlay(); } catch {}; log.info('[IPC] File transcription successful'); resolve(r); },
            reject:  (e)=>{ clearTimeout(timeout); try { hideFileProcessingOverlay(); } catch {}; log.error('[IPC] File transcription error:', e); reject(e); },
            modelId,
          });
          log.info(`[IPC:file→send] bytes=${mono16.byteLength}`);
          worker.send({
            type: 'transcribe',
            id, modelId,
            audioData: Buffer.from(mono16.buffer, mono16.byteOffset, mono16.byteLength),
            options: { sourceSampleRate: TARGET_SR, language: options.language || 'auto', threads: options.threads || 0, forceCpu: !!options.forceCpu }
          });
        } catch (e) {
          return reject(e);
        }
      } else if (isOgg || isM4a || isAiff || ext === '.aac' || ext === '.aif' || ext === '.aiff' || ext === '.m4a' || ext === '.ogg' || ext === '.oga') {
        log.info('[IPC:file] Transcoding non-WAV (OGG/AIFF/M4A/AAC) via ffmpeg');
        // Transcode OGG/AIFF/M4A/AAC to WAV 16k via ffmpeg, then send PCM
        try {
          const wavPath = await ffmpegTranscodeToWav16k(fname_inp);
          const wb = await fs.readFile(wavPath);
          const { pcm, sampleRate } = readWavToFloat32(wb);
          const TARGET_SR = 16000;
          const mono16 = (sampleRate===TARGET_SR) ? pcm : linearResampleMono(pcm, sampleRate, TARGET_SR);
          const u8 = new Uint8Array(mono16.buffer, mono16.byteOffset, mono16.byteLength);
          if (!u8.byteLength) return reject(new Error('Decoded audio is empty after transcode'));
          log.info(`[IPC:file] TRANSCODE→WAV converted: sr=${TARGET_SR} frames=${mono16.length} bytes=${u8.byteLength}`);

          showFileProcessingOverlay();
          const id = ++requestCounter;
          const timeout = setTimeout(() => {
            map.delete(id); log.error('[IPC] File transcription timed out');
            try { hideFileProcessingOverlay(); } catch {}
            reject(new Error('Transcription timed out'));
          }, 10*60*1000);
          map.set(id, {
            resolve: (r)=>{ clearTimeout(timeout); try { hideFileProcessingOverlay(); } catch {}; log.info('[IPC] File transcription successful'); resolve(r); },
            reject:  (e)=>{ clearTimeout(timeout); try { hideFileProcessingOverlay(); } catch {}; log.error('[IPC] File transcription error:', e); reject(e); },
            modelId,
          });
          log.info(`[IPC:file→send] bytes=${mono16.byteLength}`);
          worker.send({
            type: 'transcribe',
            id, modelId,
            audioData: Buffer.from(mono16.buffer, mono16.byteOffset, mono16.byteLength),
            options: { sourceSampleRate: TARGET_SR, language: options.language || 'auto', threads: options.threads || 0, forceCpu: !!options.forceCpu }
          });
        } catch (e) {
          return reject(e);
        }
      } else if (kind === 'parakeet') {
        log.info('[IPC:file] Parakeet requires PCM input; transcoding non-WAV via ffmpeg');
        try {
          const wavPath = await ffmpegTranscodeToWav16k(fname_inp);
          const wb = await fs.readFile(wavPath);
          const { pcm, sampleRate } = readWavToFloat32(wb);
          const TARGET_SR = 16000;
          const mono16 = (sampleRate===TARGET_SR) ? pcm : linearResampleMono(pcm, sampleRate, TARGET_SR);
          const u8 = new Uint8Array(mono16.buffer, mono16.byteOffset, mono16.byteLength);
          if (!u8.byteLength) return reject(new Error('Decoded audio is empty after transcode'));
          log.info(`[IPC:file] Parakeet transcode→WAV converted: sr=${TARGET_SR} frames=${mono16.length} bytes=${u8.byteLength}`);

          showFileProcessingOverlay();
          const id = ++requestCounter;
          const timeout = setTimeout(() => {
            map.delete(id); log.error('[IPC] File transcription timed out');
            try { hideFileProcessingOverlay(); } catch {}
            reject(new Error('Transcription timed out'));
          }, 10*60*1000);
          map.set(id, {
            resolve: (r)=>{ clearTimeout(timeout); try { hideFileProcessingOverlay(); } catch {}; log.info('[IPC] File transcription successful'); resolve(r); },
            reject:  (e)=>{ clearTimeout(timeout); try { hideFileProcessingOverlay(); } catch {}; log.error('[IPC] File transcription error:', e); reject(e); },
            modelId,
          });
          log.info(`[IPC:file→send] bytes=${mono16.byteLength}`);
          worker.send({
            type: 'transcribe',
            id, modelId,
            audioData: Buffer.from(mono16.buffer, mono16.byteOffset, mono16.byteLength),
            options: { sourceSampleRate: TARGET_SR, language: options.language || 'auto', threads: options.threads || 0, forceCpu: !!options.forceCpu }
          });
          try { fs.unlink(wavPath).catch(() => {}); } catch {}
        } catch (e) {
          return reject(e);
        }
      } else {
        // Non-WAV format - try direct file transcription with Whisper.cpp
        log.info(`[IPC:file] Trying direct file transcription for non-WAV format`);
        showFileProcessingOverlay();
        const id = ++requestCounter;
        const timeout = setTimeout(() => {
          map.delete(id); log.error('[IPC] File transcription timed out');
          try { hideFileProcessingOverlay(); } catch {}
          reject(new Error('Transcription timed out'));
        }, 10*60*1000);
        map.set(id, {
          resolve: (r)=>{ clearTimeout(timeout); try { hideFileProcessingOverlay(); } catch {}; log.info('[IPC] File transcription successful'); resolve(r); },
          reject:  (e)=>{ clearTimeout(timeout); try { hideFileProcessingOverlay(); } catch {}; log.error('[IPC] File transcription error:', e); reject(e); },
          modelId,
        });
        worker.send({
          type: 'transcribe',
          id, modelId,
          options: { fname_inp, language: options.language || 'auto', threads: options.threads || 0, forceCpu: !!options.forceCpu }
        });
      }
    } catch (e) { reject(e); }
  });
});
ipcMain.handle('whisper:transcribeWavBytes', async (_event, { wavBytes, modelId, options = {} }) => {
  const { worker, map } = getWorkerContext(modelId);
  if (!wavBytes) throw new Error('wavBytes is empty');

  const b = Buffer.isBuffer(wavBytes) ? wavBytes : Buffer.from(wavBytes);
  const isWav = b.slice(0,4).toString('ascii')==='RIFF' && b.slice(8,12).toString('ascii')==='WAVE';
  if (!isWav) throw new Error('Only WAV bytes are supported in local mode');

  const { pcm, sampleRate } = readWavToFloat32(b);
  // Quick amplitude diagnostic (helps detect silence at source)
  try {
    let sum=0, peak=0; for (let i=0;i<pcm.length;i++){ const v=pcm[i]; sum+=v*v; const a=Math.abs(v); if(a>peak) peak=a; }
    const rms = Math.sqrt(sum/Math.max(1, pcm.length));
    log.info(`[IPC:wavBytes] amplitude diag: frames=${pcm.length} rms=${rms.toFixed(6)} peak=${peak.toFixed(6)} sr=${sampleRate}`);
  } catch {}
  const TARGET_SR = 16000;
  const mono16 = (sampleRate===TARGET_SR) ? pcm : linearResampleMono(pcm, sampleRate, TARGET_SR);
  const u8 = new Uint8Array(mono16.buffer, mono16.byteOffset, mono16.byteLength);
  if (!u8.byteLength) throw new Error('Decoded audio is empty');
  log.info(`[IPC:wavBytes] frames=${mono16.length} bytes=${u8.byteLength}`);

  return new Promise((resolve, reject) => {
    const id = ++requestCounter;
    const timeout = setTimeout(() => { map.delete(id); log.error('[IPC] WAV-bytes transcription timed out'); reject(new Error('Transcription timed out')); }, 10*60*1000);
    map.set(id, {
      resolve: (r)=>{ clearTimeout(timeout); log.info('[IPC] WAV-bytes transcription successful'); resolve(r); },
      reject:  (e)=>{ clearTimeout(timeout); log.error('[IPC] WAV-bytes transcription error:', e); reject(e); },
      modelId,
    });
    log.info(`[IPC:file→send] bytes=${mono16.byteLength}`);
    worker.send({
      type: 'transcribe',
      id, modelId,
      audioData: Buffer.from(mono16.buffer, mono16.byteOffset, mono16.byteLength),
  options: { sourceSampleRate: TARGET_SR, language: options.language || 'auto', translate: !!options.translate, threads: options.threads || 0, forceCpu: !!options.forceCpu }
    });
  });
});

// Handle OGG transcription (directly supported by Whisper.cpp)
ipcMain.handle('whisper:transcribeOgg', async (_event, { oggBytes, modelId, options = {} }) => {
  const ctx = getWorkerContext(modelId);
  const { worker, map, kind } = ctx;
  if (kind === 'parakeet') {
    throw new Error('Parakeet models require PCM audio input; convert to WAV/PCM before invoking.');
  }
  if (!oggBytes) throw new Error('oggBytes is empty');

  const b = Buffer.isBuffer(oggBytes) ? oggBytes : Buffer.from(oggBytes);
  log.info(`[IPC:ogg] bytes=${b.byteLength}`);
  
  // OGG format - send directly to worker (natively supported)
  return new Promise((resolve, reject) => {
    const id = ++requestCounter;
    const timeout = setTimeout(() => { map.delete(id); log.error('[IPC] OGG transcription timed out'); reject(new Error('Transcription timed out')); }, 10*60*1000);
    map.set(id, {
      resolve: (r)=>{ clearTimeout(timeout); log.info('[IPC] OGG transcription successful'); resolve(r); },
      reject:  (e)=>{ clearTimeout(timeout); log.error('[IPC] OGG transcription error:', e); reject(e); },
      modelId,
    });
    log.info(`[IPC:ogg→send] bytes=${b.byteLength}`);
    worker.send({
      type: 'transcribeOgg',
      id, modelId,
      oggData: b,
  options: { language: options.language || 'auto', translate: !!options.translate, threads: options.threads || 0, forceCpu: !!options.forceCpu }
    });
  });
});

// Handle WebM transcription with format conversion
ipcMain.handle('whisper:transcribeWebM', async (_event, { webmBytes, modelId, options = {} }) => {
  const ctx = getWorkerContext(modelId);
  const { worker, map, kind } = ctx;
  if (kind === 'parakeet') {
    throw new Error('Parakeet models require PCM audio input; convert to WAV/PCM before invoking.');
  }
  if (!webmBytes) throw new Error('webmBytes is empty');

  const b = Buffer.isBuffer(webmBytes) ? webmBytes : Buffer.from(webmBytes);
  log.info(`[IPC:webm] bytes=${b.byteLength}`);
  
  // WebM format - send directly to worker for conversion handling
  return new Promise((resolve, reject) => {
    const id = ++requestCounter;
    const timeout = setTimeout(() => { map.delete(id); log.error('[IPC] WebM transcription timed out'); reject(new Error('Transcription timed out')); }, 10*60*1000);
    map.set(id, {
      resolve: (r)=>{ clearTimeout(timeout); log.info('[IPC] WebM transcription successful'); resolve(r); },
      reject:  (e)=>{ clearTimeout(timeout); log.error('[IPC] WebM transcription error:', e); reject(e); },
      modelId,
    });
    log.info(`[IPC:webm→send] bytes=${b.byteLength}`);
    worker.send({
      type: 'transcribeWebM',
      id, modelId,
      webmData: b,
  options: { language: options.language || 'auto', translate: !!options.translate, threads: options.threads || 0, forceCpu: !!options.forceCpu }
    });
  });
});

ipcMain.once('renderer-is-ready', () => {
  log.info('Renderer is ready, showing main window.');
  if (mainWindow && !mainWindow.isDestroyed() && !mainWindow.isVisible()) mainWindow.show();
});

// Forward renderer logs to electron-log respecting current log level
ipcMain.on('log-message', (_e, { level, message, args }) => {
  try {
    const ORDER = { error: 0, warn: 1, info: 2, debug: 3 };
    const lvl = (typeof level === 'string' ? level : 'info');
    if ((ORDER[lvl] ?? 2) > (ORDER[currentLogLevel] ?? 3)) return; // drop below-threshold
  const electronLogLevel = lvl; // keep native levels so transports can gate
  (log[electronLogLevel] || log.info)(message, ...(args || []));
  } catch {}
});
ipcMain.on('open-log-file', () => { shell.openPath(log.transports.file.getFile().path); });

// Overlay prefs update from renderer
ipcMain.on('overlay:update-prefs', (_e, prefs) => {
  try {
    overlayPrefs = {
      position: (prefs && prefs.position) || overlayPrefs.position || 'bottom-right',
      scale: typeof prefs?.scale === 'number' ? prefs.scale : (overlayPrefs.scale || 1),
      sound: prefs?.sound !== undefined ? !!prefs.sound : (overlayPrefs.sound !== false),
      volume: typeof prefs?.volume === 'number' ? prefs.volume : (overlayPrefs.volume || 0.6),
    };
    log.info('[Overlay] Preferences updated:', overlayPrefs);
    const win = overlayWindow; if (!win || win.isDestroyed()) return;
    // Resize window for new scale
    const { width, height } = getScaledOverlaySize();
    try { win.setSize(width, height, false); } catch {}
    positionOverlayWindow();
    applyOverlayPrefsToDom();
  } catch (e) { log.warn('[Overlay] Failed to update prefs:', e); }
});

// Sync titlebar (caption buttons) colors with renderer theme
ipcMain.on('update-titlebar-theme', (_e, { theme }) => {
  try {
    if (!mainWindow || mainWindow.isDestroyed()) return;
    if (theme === 'light') {
      // Match CSS light tokens: bg ~ #F7F7F7, text ~ #333333
      mainWindow.setTitleBarOverlay?.({ color: '#F7F7F7', symbolColor: '#333333', height: 40 });
      try { mainWindow.setBackgroundColor('#F7F7F7'); } catch {}
      log.info('[Titlebar] Switched to light theme');
    } else {
      // Dark tokens: bg ~ #121212, text ~ #E1E1E1
      mainWindow.setTitleBarOverlay?.({ color: '#121212', symbolColor: '#E1E1E1', height: 40 });
      try { mainWindow.setBackgroundColor('#121212'); } catch {}
      log.info('[Titlebar] Switched to dark theme');
    }
  } catch (e) {
    log.warn('Failed to update titlebar theme:', e);
  }
});

// Auto paste triggered from renderer IPC
ipcMain.on('clipboard-changed', (_e, text) => {
  log.info(`[MAIN] Received clipboard-changed IPC, text length: ${text.length}`);
  try { clipboard.writeText(text); log.info('[MAIN] Clipboard set in main process'); } catch (e) { log.error('[MAIN] Failed to set clipboard:', e); }
  setTimeout(() => {
    if (mainWindow?.isFocused()) { log.info('[MAIN] Window focused; skipping auto-paste.'); try { new Notification({ title: 'SmartScribe', body: 'Note copied to clipboard.' }).show(); } catch {} return; }
    if (process.platform === 'win32') {
      log.info('[MAIN] Starting auto-paste sequence via native exec on Windows');
      const pasteCommand = `powershell -command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('^v')"`;
      exec(pasteCommand, (err) => { if (err) log.error('[MAIN] Auto-paste failed:', err); else log.info('[MAIN] Auto-paste done'); });
    } else if (process.platform === 'darwin') {
      // On macOS, auto-paste is handled via AppleScript only on the hotkey flow; skip IPC-triggered paste here.
      log.info('[MAIN] macOS platform detected; skipping auto-paste for clipboard-changed IPC');
    } else if (process.platform === 'linux') {
      log.info('[MAIN] Linux platform detected; skipping auto-paste for clipboard-changed IPC');
    }
  }, 100);
});

// hotkey registration
ipcMain.on('update-hotkey', (_e, { enabled, hotkey }) => {
  log.info(`Updating hotkey. Enabled: ${enabled}, Hotkey: ${hotkey}`);
  if (currentHotkey && globalShortcut.isRegistered(currentHotkey)) { log.info(`Unregistering previous hotkey: ${currentHotkey}`); globalShortcut.unregister(currentHotkey); }
  currentHotkey = '';
  if (enabled && hotkey) {
    try {
      const ok = globalShortcut.register(hotkey, () => {
        log.info(`Global shortcut ${hotkey} triggered.`);
        hotkeyAutoPasteArmed = true; // arm auto-paste for next successful transcription
        mainWindow?.webContents?.send('global-shortcut-triggered');
      });
      if (ok) { log.info(`Successfully registered hotkey: ${hotkey}`); currentHotkey = hotkey; mainWindow?.webContents?.send('hotkey-registration-success'); }
      else { log.warn(`Failed to register hotkey: ${hotkey}. It might be in use.`); mainWindow?.webContents?.send('hotkey-registration-failed', { hotkey }); }
    } catch (e) { log.error(`Error registering hotkey "${hotkey}":`, e); mainWindow?.webContents?.send('hotkey-registration-failed', { hotkey }); }
  } else { log.info('Hotkey disabled, no action taken.'); }
});

// ===== Whisper model management =====
function toSafeId(id) { try { return String(id).replace(/[^a-z0-9._-]/gi, '_'); } catch { return String(id); } }
ipcMain.on('precache-local-model', async (event, { id }) => {
  log.info(`[IPC] Installing local model: ${id}`);
  try {
    const { worker } = getWorkerContext(id);
    const removeOk = () => {
      if (typeof worker.off === 'function') worker.off('message', onOk);
      else worker.removeListener('message', onOk);
    };
    const removeFail = () => {
      if (typeof worker.off === 'function') worker.off('message', onFail);
      else worker.removeListener('message', onFail);
    };

    const onOk = (m) => {
      if (m?.type === 'download-complete' && m.modelId === id) {
        event.reply('download-complete', { id, path: null });
        log.info(`[IPC] Model ${id} installation complete`);
        removeOk();
        removeFail();
      }
    };
    const onFail = (m) => {
      if (m?.type === 'download-failed' && m.modelId === id) {
        event.reply('download-failed', { id, error: m.error });
        log.error(`[IPC] Model ${id} installation failed:`, m.error);
        removeOk();
        removeFail();
      }
    };
    worker.on('message', onOk);
    worker.on('message', onFail);
    worker.send({ type: 'install_model', modelId: id });
    try { mainWindow?.webContents?.send('download-progress', { modelId: id, status: 'start' }); } catch {}
  } catch (e) {
    log.error(`[IPC] Failed to install model ${id}:`, e);
    event.reply('download-failed', { id, error: e.message });
  }
});
ipcMain.on('remove-local-model', async (event, { id }) => {
  log.info(`[IPC] Removing local model: ${id}`);
  try {
    const modelDir = path.join(app.getPath('userData'), 'Models', toSafeId(id));
    if (fsSync.existsSync(modelDir)) await fs.rm(modelDir, { recursive: true, force: true });
    else log.warn(`[IPC] Model directory not found: ${modelDir}`);
    event.reply('local-model-removed', { id, success: true });
  } catch (e) {
    log.error(`[IPC] Failed to remove local model ${id}:`, e);
    event.reply('local-model-removed', { id, success: false, error: e.message });
  }
});

// New invoke-based removal API for preload.whisper.removeModel
ipcMain.handle('whisper:removeModel', async (_event, modelId) => {
  log.info(`[IPC] (invoke) Removing local model: ${modelId}`);
  try {
    const modelDir = path.join(app.getPath('userData'), 'Models', toSafeId(modelId));
    if (fsSync.existsSync(modelDir)) await fs.rm(modelDir, { recursive: true, force: true });
    else log.warn(`[IPC] Model directory not found: ${modelDir}`);
    // For backward-compat listeners in renderer
    try { mainWindow?.webContents?.send('local-model-removed', { id: modelId, success: true }); } catch {}
    return { ok: true, id: modelId };
  } catch (e) {
    log.error(`[IPC] (invoke) Failed to remove local model ${modelId}:`, e);
    try { mainWindow?.webContents?.send('local-model-removed', { id: modelId, success: false, error: e.message }); } catch {}
    return { ok: false, id: modelId, error: e?.message || String(e) };
  }
});

// ===== Whisper probe backend =====
ipcMain.handle('probe-backend', async () => {
  try { ensureTranscriber(); transcriptionProcess.send({ type: 'probe_backend' }); return { ok: true }; }
  catch (e) { log.error('[IPC] probe-backend failed:', e); return { ok: false, error: e.message }; }
});

// ===== File picker =====
ipcMain.handle('pick-audio-file', async () => {
  const { canceled, filePaths } = await dialog.showOpenDialog({
    properties: ['openFile'],
    filters: [{ name: 'Audio', extensions: ['wav','mp3','m4a','flac','ogg','opus','aif','aiff','aac','oga'] }]
  });
  return canceled ? null : filePaths[0];
});

// ===== Install model (invoke) =====
ipcMain.handle('whisper:installModel', async (_e, modelId) => {
  const { worker } = getWorkerContext(modelId);
  return new Promise((resolve, reject) => {
    const removeOk = () => {
      if (typeof worker.off === 'function') worker.off('message', onOk);
      else worker.removeListener('message', onOk);
    };
    const removeFail = () => {
      if (typeof worker.off === 'function') worker.off('message', onFail);
      else worker.removeListener('message', onFail);
    };

    const onOk = (m) => {
      if (m?.type === 'download-complete' && m.modelId === modelId) {
        try { mainWindow?.webContents?.send('download-complete', { id: modelId, path: null }); } catch {}
        removeOk();
        removeFail();
        resolve({ ok: true, id: modelId });
      }
    };
    const onFail = (m) => {
      if (m?.type === 'download-failed' && m.modelId === modelId) {
        try { mainWindow?.webContents?.send('download-failed', { id: modelId, error: m.error || 'failed' }); } catch {}
        removeOk();
        removeFail();
        reject(new Error(m.error || `Failed to install ${modelId}`));
      }
    };

    worker.on('message', onOk);
    worker.on('message', onFail);
    try {
      worker.send({ type: 'install_model', modelId });
      mainWindow?.webContents?.send('download-progress', { modelId, status: 'start' });
    } catch (e) {
      removeOk();
      removeFail();
      reject(e);
    }
  });
});

// ===== PCM → worker =====
ipcMain.handle('whisper:transcribePcm', async (_event, { pcm32, sampleRate, modelId, options = {} }) => {
  const { worker, map } = getWorkerContext(modelId);
  return new Promise((resolve, reject) => {
    try {
      const id = ++requestCounter;
      const timeout = setTimeout(() => {
        map.delete(id);
        log.error('[IPC] Local transcription timed out after 10 minutes');
        reject(new Error('Transcription timed out'));
      }, 10 * 60 * 1000);
      map.set(id, {
        resolve: (result) => { clearTimeout(timeout); log.info('[IPC] Transcription successful'); resolve(result); },
        reject:  (err)    => { clearTimeout(timeout); log.error('[IPC] Transcription error:', err); reject(err); },
        modelId,
      });

      let f32;
      if (pcm32?.buffer) f32 = new Float32Array(pcm32.buffer, pcm32.byteOffset || 0, pcm32.length || (pcm32.byteLength/4));
      else if (Buffer.isBuffer(pcm32)) f32 = new Float32Array(pcm32.buffer, pcm32.byteOffset || 0, pcm32.byteLength / 4);
      else if (Array.isArray(pcm32)) f32 = new Float32Array(pcm32);
      else throw new Error('pcm32 is not a Float32Array/Buffer/array');
      log.info(`[IPC:pcm→send] bytes=${f32.byteLength}`);
      worker.send({
        type: 'transcribe',
        id,
        modelId,
        audioData: Buffer.from(f32.buffer, f32.byteOffset || 0, f32.byteLength || (f32.length * 4)),
        options: { sourceSampleRate: sampleRate || 16000, ...options }
      });
    } catch (e) { reject(e); }
  });
});


// ===== Ollama stubs (to silence renderer) =====
ipcMain.handle('check-ollama-installation', async () => ({ installed: false, running: false }));
ipcMain.handle('install-ollama', async () => ({ ok: false, message: 'Ollama install not supported in this build' }));

ipcMain.handle('show-context-menu', (event, payload = {}) => {
  try {
    const win = BrowserWindow.fromWebContents(event.sender);
    if (!win) return;
    const isEditable = !!payload?.isEditable;
    const template = [
      { role: 'undo', enabled: isEditable },
      { role: 'redo', enabled: isEditable },
      { type: 'separator' },
      ...(isEditable ? [{ role: 'cut' }] : []),
      { role: 'copy', enabled: payload?.hasSelection ?? true },
      ...(isEditable ? [{ role: 'paste' }, { role: 'pasteAndMatchStyle' }] : []),
      { type: 'separator' },
      { role: 'selectAll' },
    ];
    const menu = Menu.buildFromTemplate(template);
    menu.popup({ window: win });
  } catch (err) {
    try { log.warn('[ContextMenu] popup failed:', err); } catch {}
  }
});

// ===== Debug =====
process.on('uncaughtException', (err) => { log.error('[main uncaughtException]', err); });
process.on('unhandledRejection', (reason) => { log.error('[main unhandledRejection]', reason); });
ipcMain.on('renderer-error', (_e, payload) => { log.error('[renderer-error]', payload); });
ipcMain.on('renderer-unhandledrejection', (_e, payload) => { log.error('[renderer-unhandledrejection]', payload); });
