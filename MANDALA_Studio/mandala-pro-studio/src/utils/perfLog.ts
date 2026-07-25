/**
 * Hang/perf diagnostics for Mandala Studio.
 *
 * Console:
 *   mandalaDumpPerf()           — last events
 *   mandalaDumpPerfLastSession()— events from previous page load (survives hang+reload)
 *   mandalaPerfVerbose(true)    — log everything
 *   mandalaClearPerf()
 *
 * Slow ops: warn ≥50ms, error ≥200ms (always printed).
 * Last snapshot is written to sessionStorage so a hung tab can be reloaded and inspected.
 */

export type PerfLevel = 'debug' | 'info' | 'warn' | 'error';

export interface PerfEvent {
  t: number;
  wall: number;
  level: PerfLevel;
  tag: string;
  msg: string;
  ms?: number;
  data?: Record<string, string | number | boolean | null | undefined>;
}

const MAX_EVENTS = 250;
const SLOW_MS = 50;
const HANG_MS = 200;
const STORAGE_KEY = 'mandalaPerfLastSession';

const events: PerfEvent[] = [];

function verbose(): boolean {
  try {
    return localStorage.getItem('mandalaPerfVerbose') === '1';
  } catch {
    return false;
  }
}

function formatData(data?: PerfEvent['data']): string {
  if (!data) return '';
  const parts: string[] = [];
  for (const k of Object.keys(data)) {
    const v = data[k];
    if (v === undefined) continue;
    parts.push(`${k}=${v}`);
  }
  return parts.length ? ` { ${parts.join(', ')} }` : '';
}

function persistSlow(): void {
  try {
    const slow = events.filter(e => e.level === 'warn' || e.level === 'error').slice(-80);
    const payload = {
      savedAt: Date.now(),
      events: slow.length ? slow : events.slice(-40)
    };
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
  } catch {
    /* quota / private mode */
  }
}

function push(ev: PerfEvent): void {
  events.push(ev);
  if (events.length > MAX_EVENTS) events.splice(0, events.length - MAX_EVENTS);
  if (ev.level === 'warn' || ev.level === 'error') persistSlow();
}

export function perfLog(
  tag: string,
  msg: string,
  data?: PerfEvent['data'],
  level: PerfLevel = 'info'
): void {
  const ev: PerfEvent = {
    t: performance.now(),
    wall: Date.now(),
    level,
    tag,
    msg,
    data
  };
  push(ev);
  const line = `[mandala:${tag}] ${msg}${formatData(data)}`;
  if (level === 'error') console.error(line);
  else if (level === 'warn') console.warn(line);
  else if (verbose() || level === 'info') console.log(line);
}

export function perfTime<T>(
  tag: string,
  msg: string,
  data: PerfEvent['data'] | undefined,
  fn: () => T
): T {
  const t0 = performance.now();
  try {
    return fn();
  } finally {
    const ms = performance.now() - t0;
    const level: PerfLevel =
      ms >= HANG_MS ? 'error' : ms >= SLOW_MS ? 'warn' : 'debug';
    const ev: PerfEvent = {
      t: t0,
      wall: Date.now(),
      level,
      tag,
      msg,
      ms,
      data: { ...data, ms: +ms.toFixed(2) }
    };
    push(ev);
    const line = `[mandala:${tag}] ${msg} ${ms.toFixed(1)}ms${formatData(ev.data)}`;
    if (level === 'error') console.error(line, '← possible hang source');
    else if (level === 'warn') console.warn(line);
    else if (verbose()) console.log(line);
  }
}

export async function perfTimeAsync<T>(
  tag: string,
  msg: string,
  data: PerfEvent['data'] | undefined,
  fn: () => Promise<T>
): Promise<T> {
  const t0 = performance.now();
  try {
    return await fn();
  } finally {
    const ms = performance.now() - t0;
    const level: PerfLevel =
      ms >= HANG_MS ? 'error' : ms >= SLOW_MS ? 'warn' : 'debug';
    const ev: PerfEvent = {
      t: t0,
      wall: Date.now(),
      level,
      tag,
      msg,
      ms,
      data: { ...data, ms: +ms.toFixed(2) }
    };
    push(ev);
    const line = `[mandala:${tag}] ${msg} ${ms.toFixed(1)}ms${formatData(ev.data)}`;
    if (level === 'error') console.error(line, '← possible hang source');
    else if (level === 'warn') console.warn(line);
    else if (verbose()) console.log(line);
  }
}

export function perfDump(limit = 100): PerfEvent[] {
  const slice = events.slice(-limit);
  console.group(`[mandala perf dump] ${slice.length}/${events.length} events`);
  for (const e of slice) {
    const ms = e.ms != null ? ` ${e.ms.toFixed(1)}ms` : '';
    const line = `${e.level.toUpperCase().padEnd(5)} ${e.tag.padEnd(14)} ${e.msg}${ms}${formatData(e.data)}`;
    if (e.level === 'error') console.error(line);
    else if (e.level === 'warn') console.warn(line);
    else console.log(line);
  }
  console.groupEnd();
  return slice;
}

export function perfDumpLastSession(): unknown {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) {
      console.log('[mandala] no previous session perf snapshot');
      return null;
    }
    const parsed = JSON.parse(raw) as { savedAt: number; events: PerfEvent[] };
    console.group(
      `[mandala previous session] saved ${new Date(parsed.savedAt).toLocaleString()} (${parsed.events?.length || 0} events)`
    );
    for (const e of parsed.events || []) {
      const ms = e.ms != null ? ` ${Number(e.ms).toFixed(1)}ms` : '';
      const line = `${(e.level || '').toUpperCase().padEnd(5)} ${(e.tag || '').padEnd(14)} ${e.msg}${ms}${formatData(e.data)}`;
      if (e.level === 'error') console.error(line);
      else if (e.level === 'warn') console.warn(line);
      else console.log(line);
    }
    console.groupEnd();
    return parsed;
  } catch (e) {
    console.warn('[mandala] failed to read last session', e);
    return null;
  }
}

export function perfClear(): void {
  events.length = 0;
  try {
    sessionStorage.removeItem(STORAGE_KEY);
  } catch {
    /* */
  }
  perfLog('perf', 'cleared');
}

/** Call on boot: surface previous hang clues immediately. */
export function perfReportPreviousSession(): void {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    if (!raw) return;
    const parsed = JSON.parse(raw) as { savedAt: number; events: PerfEvent[] };
    const errs = (parsed.events || []).filter(e => e.level === 'error' || (e.ms != null && e.ms >= HANG_MS));
    if (!errs.length) return;
    console.warn(
      `[mandala] Previous session had ${errs.length} slow/hang event(s). Run mandalaDumpPerfLastSession() for details.`
    );
    for (const e of errs.slice(-8)) {
      console.warn(
        `  · ${e.tag}: ${e.msg}${e.ms != null ? ` ${e.ms.toFixed(0)}ms` : ''}${formatData(e.data)}`
      );
    }
  } catch {
    /* */
  }
}

if (typeof window !== 'undefined') {
  const w = window as unknown as Record<string, unknown>;
  w.mandalaDumpPerf = perfDump;
  w.mandalaDumpPerfLastSession = perfDumpLastSession;
  w.mandalaClearPerf = perfClear;
  w.mandalaPerfVerbose = (on = true) => {
    localStorage.setItem('mandalaPerfVerbose', on ? '1' : '0');
    console.log(`[mandala] verbose=${on ? 'on' : 'off'}`);
  };
}
