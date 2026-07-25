import {StrictMode} from 'react';
import {createRoot} from 'react-dom/client';
import App from './App.tsx';
import './index.css';
import { perfLog, perfReportPreviousSession } from './utils/perfLog';

perfReportPreviousSession();
perfLog('boot', 'app mount', {
  dpr: typeof window !== 'undefined' ? window.devicePixelRatio : 0,
  mem:
    typeof performance !== 'undefined' && (performance as unknown as { memory?: { jsHeapSizeLimit: number } }).memory
      ? Math.round(
          ((performance as unknown as { memory: { usedJSHeapSize: number } }).memory.usedJSHeapSize || 0) /
            1048576
        )
      : -1
});

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

console.info(
  '[mandala] Perf: mandalaDumpPerf() · mandalaDumpPerfLastSession() (after hang+reload) · mandalaPerfVerbose(true)'
);
