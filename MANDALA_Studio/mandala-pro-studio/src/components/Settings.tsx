import React, { useEffect, useRef, useState } from 'react';
import {
  CanvasPrefs,
  HudCorner,
  loadCanvasPrefs,
  saveCanvasPrefs,
  CAMERA_ZOOM_MIN,
  CAMERA_ZOOM_MAX
} from '../utils/canvasPrefs';
import {
  ACCENT_PRESETS,
  AppSettings,
  AppTheme,
  RenderQuality,
  THEME_OPTIONS,
  applyAppearance,
  bakeQualityScale,
  loadAppSettings,
  themeDefaultAccent,
  updateAppSettings
} from '../utils/appSettings';
import { setWorldBakeQuality } from '../utils/WorldScene';
import {
  UserProfile,
  fileToAvatarDataUrl,
  loadUserProfile,
  saveUserProfile
} from '../utils/userProfile';

type SettingsTab = 'profile' | 'appearance' | 'canvas' | 'performance' | 'ai' | 'keyboard';

const TABS: { id: SettingsTab; icon: string; label: string }[] = [
  { id: 'profile', icon: 'person', label: 'Profile' },
  { id: 'appearance', icon: 'palette', label: 'Theme' },
  { id: 'canvas', icon: 'wallpaper', label: 'Canvas' },
  { id: 'performance', icon: 'speed', label: 'Performance' },
  { id: 'ai', icon: 'psychology', label: 'AI' },
  { id: 'keyboard', icon: 'keyboard', label: 'Keyboard' }
];

const CORNERS: { id: HudCorner; label: string }[] = [
  { id: 'tl', label: 'TL' },
  { id: 'tr', label: 'TR' },
  { id: 'bl', label: 'BL' },
  { id: 'br', label: 'BR' }
];

const SHORTCUTS: { action: string; keys: string[] }[] = [
  { action: 'Undo last stroke', keys: ['⌘/Ctrl', 'Z'] },
  { action: 'Redo stroke', keys: ['⌘/Ctrl', 'Y'] },
  { action: 'Clear canvas', keys: ['⌘/Ctrl', 'Del'] },
  { action: 'Brush smaller', keys: ['['] },
  { action: 'Brush larger', keys: [']'] },
  { action: 'Save project', keys: ['⌘/Ctrl', 'S'] },
  { action: 'Pan canvas', keys: ['Space', 'drag'] },
  { action: 'Zoom', keys: ['Scroll'] }
];

function SectionCard({
  title,
  icon,
  children,
  hint
}: {
  title: string;
  icon: string;
  children: React.ReactNode;
  hint?: string;
}) {
  return (
    <section className="ui-card rounded-xl border p-4 sm:p-5">
      <div className="flex items-center gap-2 mb-1">
        <span className="material-symbols-outlined text-secondary text-[18px]">{icon}</span>
        <h2 className="font-manrope text-[13px] font-bold text-white tracking-wide">{title}</h2>
      </div>
      {hint && (
        <p className="font-manrope text-[10px] text-slate-500 mb-3 leading-relaxed">{hint}</p>
      )}
      {!hint && <div className="mb-3" />}
      {children}
    </section>
  );
}

function Chip({
  active,
  onClick,
  children
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`px-3 py-1.5 rounded-lg text-[10px] font-manrope font-bold border transition-all cursor-pointer ${
        active
          ? 'bg-secondary/15 border-secondary/50 text-secondary'
          : 'bg-black/30 border-white/10 text-slate-400 hover:border-white/20 hover:text-slate-200'
      }`}
    >
      {children}
    </button>
  );
}

export default function Settings() {
  const [tab, setTab] = useState<SettingsTab>('profile');
  const [prefs, setPrefs] = useState<CanvasPrefs>(() => loadCanvasPrefs());
  const [app, setApp] = useState<AppSettings>(() => loadAppSettings());
  const [profile, setProfile] = useState<UserProfile>(() => loadUserProfile());
  const [apiKey, setApiKey] = useState('');
  const [showKey, setShowKey] = useState(false);
  const [localPassword, setLocalPassword] = useState('');
  const [avatarError, setAvatarError] = useState<string | null>(null);
  const [authNote, setAuthNote] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const savedKey = localStorage.getItem('gemini_api_key');
    if (savedKey) setApiKey(savedKey);
    setPrefs(loadCanvasPrefs());
    const a = loadAppSettings();
    setApp(a);
    applyAppearance(a);
    setWorldBakeQuality(bakeQualityScale(a.renderQuality));
    setProfile(loadUserProfile());
  }, []);

  const patchPrefs = (partial: Partial<CanvasPrefs>) => {
    const next = { ...prefs, ...partial };
    setPrefs(next);
    saveCanvasPrefs(next);
  };

  const patchApp = (partial: Partial<AppSettings>) => {
    const next = updateAppSettings(partial);
    setApp(next);
    applyAppearance(next);
    if (partial.renderQuality || partial.theme) {
      setWorldBakeQuality(bakeQualityScale(next.renderQuality));
      window.dispatchEvent(new CustomEvent('mandala-quality-changed'));
    }
  };

  const patchProfile = (partial: Partial<UserProfile>) => {
    const next = { ...profile, ...partial };
    setProfile(next);
    saveUserProfile(next);
  };

  const handleSaveKey = (val: string) => {
    setApiKey(val);
    localStorage.setItem('gemini_api_key', val);
  };

  const onAvatarPick = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setAvatarError(null);
    try {
      const dataUrl = await fileToAvatarDataUrl(file);
      patchProfile({ avatarDataUrl: dataUrl });
    } catch (err) {
      setAvatarError(err instanceof Error ? err.message : 'Upload failed');
    }
  };

  const handleGoogleStub = () => {
    setAuthNote(
      'Google Sign-In will connect in a future release (OAuth + cloud gallery). Profile data is ready for sync.'
    );
    patchProfile({ authProvider: 'google' });
  };

  const handleLocalSignIn = () => {
    if (!profile.email.trim()) {
      setAuthNote('Add an email first.');
      return;
    }
    if (localPassword.length < 6) {
      setAuthNote('Password must be at least 6 characters (stored locally only for now).');
      return;
    }
    // Prep only: never store real password hashes to cloud yet — local flag only
    localStorage.setItem(
      'mandalaLocalAuthStub',
      JSON.stringify({ email: profile.email.trim().toLowerCase(), setAt: Date.now() })
    );
    patchProfile({ authProvider: 'local', userId: `local_${Date.now().toString(36)}` });
    setLocalPassword('');
    setAuthNote('Local account marked on this device. Cloud DB sync is planned next.');
  };

  return (
    <div className="absolute inset-0 overflow-y-auto pt-20 pb-16 px-6 sm:px-12 theme-surface scrollbar-thin">
      <div className="max-w-screen-xl mx-auto mt-6">
        <div className="flex flex-col md:flex-row md:items-end justify-between mb-8 gap-4 border-b border-white/5 pb-6">
          <div>
            <h1 className="font-manrope text-[24px] font-bold tracking-tight text-white flex items-center gap-2">
              <span className="bg-gradient-to-r from-teal-300 via-secondary to-violet-400 bg-clip-text text-transparent">
                Settings
              </span>
            </h1>
            <p className="font-manrope text-[11px] text-slate-400 mt-1 font-medium max-w-lg">
              Compact studio prefs — theme, canvas, performance, profile & shortcuts.
            </p>
          </div>
        </div>

        <div className="flex flex-col lg:flex-row gap-5">
          {/* Side tabs */}
          <nav className="lg:w-44 shrink-0 flex lg:flex-col gap-1 overflow-x-auto pb-1 lg:pb-0">
            {TABS.map(t => {
              const active = tab === t.id;
              return (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => setTab(t.id)}
                  className={`flex items-center gap-2 px-3 py-2 rounded-lg text-left transition-all cursor-pointer whitespace-nowrap ${
                    active
                      ? 'bg-secondary/10 border border-secondary/35 text-secondary'
                      : 'border border-transparent text-slate-400 hover:bg-white/5 hover:text-white'
                  }`}
                >
                  <span className="material-symbols-outlined text-[16px]">{t.icon}</span>
                  <span className="font-manrope text-[11px] font-bold tracking-wide">{t.label}</span>
                </button>
              );
            })}
          </nav>

          <div className="flex-1 min-w-0 space-y-4 max-w-2xl">
            {tab === 'profile' && (
              <>
                <SectionCard
                  title="Your profile"
                  icon="badge"
                  hint="Local profile for now. Ready for Google / password auth and cloud gallery later."
                >
                  <div className="flex flex-col sm:flex-row gap-5 items-start">
                    <div className="flex flex-col items-center gap-2">
                      <button
                        type="button"
                        onClick={() => fileRef.current?.click()}
                        className="relative w-20 h-20 rounded-2xl overflow-hidden border border-white/15 bg-black/40 group cursor-pointer hover:border-secondary/50 transition-colors"
                        title="Upload avatar"
                      >
                        {profile.avatarDataUrl ? (
                          <img
                            src={profile.avatarDataUrl}
                            alt=""
                            className="w-full h-full object-cover"
                          />
                        ) : (
                          <span className="absolute inset-0 flex items-center justify-center text-slate-600">
                            <span className="material-symbols-outlined text-[36px]">person</span>
                          </span>
                        )}
                        <span className="absolute inset-x-0 bottom-0 py-0.5 bg-black/70 text-[8px] font-manrope font-bold text-secondary text-center opacity-0 group-hover:opacity-100 transition-opacity">
                          Upload
                        </span>
                      </button>
                      <input
                        ref={fileRef}
                        type="file"
                        accept="image/*"
                        className="hidden"
                        onChange={onAvatarPick}
                      />
                      {profile.avatarDataUrl && (
                        <button
                          type="button"
                          onClick={() => patchProfile({ avatarDataUrl: '' })}
                          className="text-[9px] text-slate-500 hover:text-red-400 font-manrope cursor-pointer"
                        >
                          Remove photo
                        </button>
                      )}
                      {avatarError && (
                        <p className="text-[9px] text-red-400 font-manrope max-w-[7rem] text-center">
                          {avatarError}
                        </p>
                      )}
                    </div>

                    <div className="flex-1 w-full space-y-3">
                      <label className="block">
                        <span className="font-manrope text-[9px] uppercase tracking-wider text-slate-500">
                          Display name
                        </span>
                        <input
                          value={profile.displayName}
                          onChange={e => patchProfile({ displayName: e.target.value })}
                          className="mt-1 w-full bg-black/40 border border-white/10 rounded-lg px-3 py-2 text-[12px] text-white focus:outline-none focus:border-secondary font-manrope"
                          maxLength={48}
                        />
                      </label>
                      <label className="block">
                        <span className="font-manrope text-[9px] uppercase tracking-wider text-slate-500">
                          Email
                        </span>
                        <input
                          type="email"
                          value={profile.email}
                          onChange={e => patchProfile({ email: e.target.value })}
                          placeholder="you@example.com"
                          className="mt-1 w-full bg-black/40 border border-white/10 rounded-lg px-3 py-2 text-[12px] text-white placeholder-slate-600 focus:outline-none focus:border-secondary font-manrope"
                        />
                      </label>
                      <p className="text-[9px] text-slate-600 font-manrope">
                        Status:{' '}
                        <span className="text-secondary font-semibold capitalize">
                          {profile.authProvider}
                        </span>
                        {profile.userId ? (
                          <span className="text-slate-500"> · {profile.userId}</span>
                        ) : null}
                      </p>
                    </div>
                  </div>
                </SectionCard>

                <SectionCard
                  title="Sign in (prep)"
                  icon="login"
                  hint="Scaffolding only — no cloud backend yet. Saves preferences for future sync & promotions."
                >
                  <div className="flex flex-wrap gap-2 mb-3">
                    <button
                      type="button"
                      onClick={handleGoogleStub}
                      className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-white/5 border border-white/10 hover:border-secondary/40 text-[11px] font-manrope font-bold text-white cursor-pointer transition-colors"
                    >
                      <span className="material-symbols-outlined text-[16px] text-secondary">
                        account_circle
                      </span>
                      Continue with Google
                    </button>
                  </div>
                  <div className="grid sm:grid-cols-[1fr_auto] gap-2 items-end">
                    <label className="block">
                      <span className="font-manrope text-[9px] uppercase tracking-wider text-slate-500">
                        Password (local stub)
                      </span>
                      <input
                        type="password"
                        value={localPassword}
                        onChange={e => setLocalPassword(e.target.value)}
                        placeholder="min 6 characters"
                        className="mt-1 w-full bg-black/40 border border-white/10 rounded-lg px-3 py-2 text-[12px] text-white placeholder-slate-600 focus:outline-none focus:border-secondary font-mono"
                      />
                    </label>
                    <button
                      type="button"
                      onClick={handleLocalSignIn}
                      className="px-4 py-2 rounded-lg bg-secondary/15 border border-secondary/40 text-secondary text-[11px] font-manrope font-bold hover:bg-secondary/25 cursor-pointer"
                    >
                      Save local
                    </button>
                  </div>
                  {authNote && (
                    <p className="mt-3 text-[10px] text-slate-400 font-manrope leading-relaxed border-t border-white/5 pt-3">
                      {authNote}
                    </p>
                  )}
                </SectionCard>
              </>
            )}

            {tab === 'appearance' && (
              <>
                <SectionCard
                  title="Application theme"
                  icon="palette"
                  hint="Applies to Workspace, Templates, Gallery, Settings, and dialogs — not the canvas fill (set under Canvas)."
                >
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    {THEME_OPTIONS.map(opt => {
                      const active = app.theme === opt.id;
                      return (
                        <button
                          key={opt.id}
                          type="button"
                          onClick={() =>
                            patchApp({
                              theme: opt.id as AppTheme,
                              accent: opt.defaultAccent
                            })
                          }
                          className={`text-left rounded-xl border p-2.5 transition-all cursor-pointer ${
                            active
                              ? 'border-secondary glow-accent-ring bg-secondary/5'
                              : 'border-white/10 bg-black/20 hover:border-white/25 opacity-80 hover:opacity-100'
                          }`}
                        >
                          <div
                            className="w-full aspect-[16/10] rounded-lg mb-2 overflow-hidden border border-white/10 flex"
                            style={{ background: opt.preview.bg }}
                          >
                            <div
                              className="w-1/3 h-full border-r border-white/5"
                              style={{ background: opt.preview.panel }}
                            />
                            <div className="flex-1 p-2 flex items-end">
                              <div
                                className="h-1.5 w-8 rounded-full"
                                style={{ background: opt.preview.accent }}
                              />
                            </div>
                          </div>
                          <div className="font-manrope text-[11px] font-bold text-white">
                            {opt.label}
                          </div>
                          <div className="font-manrope text-[9px] text-slate-500 mt-0.5 leading-snug">
                            {opt.blurb}
                          </div>
                        </button>
                      );
                    })}
                  </div>
                  <p className="mt-3 text-[9px] text-slate-600 font-manrope">
                    Language: English only for now. Multi-language will appear here later.
                  </p>
                </SectionCard>

                <SectionCard
                  title="Accent color"
                  icon="colors"
                  hint="Buttons, icons, focus rings, HUD highlights, and active states across the app."
                >
                  <div className="flex flex-wrap gap-2 mb-3">
                    {ACCENT_PRESETS.map(c => (
                      <button
                        key={c}
                        type="button"
                        title={c}
                        onClick={() => patchApp({ accent: c })}
                        className={`w-8 h-8 rounded-full border-2 cursor-pointer transition-transform hover:scale-110 ${
                          app.accent.toLowerCase() === c.toLowerCase()
                            ? 'border-white scale-110 ring-2 ring-secondary/40'
                            : 'border-white/20'
                        }`}
                        style={{ background: c }}
                      />
                    ))}
                  </div>
                  <div className="flex items-center gap-3 p-3 rounded-lg bg-black/30 border border-white/10">
                    <input
                      type="color"
                      value={app.accent}
                      onChange={e => patchApp({ accent: e.target.value })}
                      className="w-10 h-10 rounded cursor-pointer border border-white/20 bg-transparent"
                    />
                    <input
                      type="text"
                      value={app.accent}
                      onChange={e => patchApp({ accent: e.target.value })}
                      className="flex-1 bg-black/40 border border-white/10 rounded-lg px-2.5 py-1.5 text-[11px] text-white font-mono focus:outline-none focus:border-secondary"
                    />
                    <button
                      type="button"
                      onClick={() => patchApp({ accent: themeDefaultAccent(app.theme) })}
                      className="px-2.5 py-1.5 rounded-lg text-[9px] font-manrope font-bold border border-white/10 text-slate-400 hover:text-secondary hover:border-secondary/40 cursor-pointer"
                    >
                      Theme default
                    </button>
                  </div>
                  <div className="mt-3 flex items-center gap-2 text-[10px] font-manrope text-slate-500">
                    <span
                      className="inline-block w-3 h-3 rounded-full"
                      style={{ background: app.accent }}
                    />
                    Live accent · sample{' '}
                    <span className="text-secondary font-bold">secondary text</span>
                    <span className="px-2 py-0.5 rounded bg-secondary text-on-secondary text-[9px] font-bold">
                      button
                    </span>
                  </div>
                </SectionCard>
              </>
            )}

            {tab === 'canvas' && (
              <SectionCard
                title="Canvas & export"
                icon="wallpaper"
                hint="Editor background color, transparent export, and no-canvas mode."
              >
                <div className="flex flex-wrap gap-2 mb-3">
                  <Chip
                    active={prefs.canvasMode === 'color'}
                    onClick={() => patchPrefs({ canvasMode: 'color' })}
                  >
                    Color canvas
                  </Chip>
                  <Chip
                    active={prefs.canvasMode === 'transparent'}
                    onClick={() => patchPrefs({ canvasMode: 'transparent' })}
                  >
                    No canvas (alpha)
                  </Chip>
                </div>

                {prefs.canvasMode === 'color' && (
                  <div className="flex items-center gap-3 p-3 rounded-lg bg-black/30 border border-white/10 mb-3">
                    <input
                      type="color"
                      value={prefs.canvasColor}
                      onChange={e => patchPrefs({ canvasColor: e.target.value })}
                      className="w-9 h-9 rounded cursor-pointer border border-white/20 bg-transparent"
                    />
                    <input
                      type="text"
                      value={prefs.canvasColor}
                      onChange={e => patchPrefs({ canvasColor: e.target.value })}
                      className="flex-1 bg-black/40 border border-white/10 rounded-lg px-2.5 py-1.5 text-[11px] text-white font-mono focus:outline-none focus:border-secondary"
                    />
                  </div>
                )}

                {prefs.canvasMode === 'transparent' && (
                  <p className="text-[10px] text-slate-500 font-manrope mb-3 leading-relaxed">
                    Workspace shows black for contrast; export can be true alpha PNG.
                  </p>
                )}

                <label className="flex items-center gap-2.5 p-3 rounded-lg bg-white/[0.03] border border-white/10 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={prefs.exportTransparent}
                    onChange={e => patchPrefs({ exportTransparent: e.target.checked })}
                    className="rounded border-white/20 bg-black/40 text-secondary cursor-pointer"
                  />
                  <div>
                    <div className="text-[11px] text-white font-manrope font-semibold">
                      Always export transparent
                    </div>
                    <div className="text-[9px] text-slate-500 font-manrope">
                      Even with a colored editor background
                    </div>
                  </div>
                </label>
              </SectionCard>
            )}

            {tab === 'performance' && (
              <>
                <SectionCard
                  title="Canvas quality"
                  icon="tune"
                  hint={`Zoom ${CAMERA_ZOOM_MIN}×–${CAMERA_ZOOM_MAX}×. Eco lowers bake resolution (~55%) for smoother large projects.`}
                >
                  <div className="space-y-2">
                    {(
                      [
                        {
                          id: 'high' as RenderQuality,
                          title: 'High Fidelity',
                          desc: 'Full project-pixel bake. Best quality.'
                        },
                        {
                          id: 'eco' as RenderQuality,
                          title: 'Eco Mode',
                          desc: 'Lower bake DPR — faster, less VRAM, slightly softer.'
                        }
                      ] as const
                    ).map(opt => {
                      const active = app.renderQuality === opt.id;
                      return (
                        <button
                          key={opt.id}
                          type="button"
                          onClick={() => patchApp({ renderQuality: opt.id })}
                          className={`w-full flex items-center justify-between p-3 rounded-lg border text-left transition-all cursor-pointer ${
                            active
                              ? 'bg-secondary/10 border-secondary/40'
                              : 'bg-black/20 border-white/10 hover:border-white/20'
                          }`}
                        >
                          <div>
                            <div className="font-manrope text-[12px] font-bold text-white">
                              {opt.title}
                            </div>
                            <div className="font-manrope text-[9px] text-slate-500 mt-0.5">
                              {opt.desc}
                            </div>
                          </div>
                          <span
                            className={`material-symbols-outlined text-[20px] ${
                              active ? 'text-secondary' : 'text-white/20'
                            }`}
                            style={active ? { fontVariationSettings: "'FILL' 1" } : undefined}
                          >
                            {active ? 'radio_button_checked' : 'radio_button_unchecked'}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                </SectionCard>

                <SectionCard
                  title="Performance HUD"
                  icon="speed"
                  hint="FPS / draw ms only inside the canvas strip (Workspace & Templates)."
                >
                  <label className="flex items-center gap-2 mb-3 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={prefs.hudEnabled}
                      onChange={e => patchPrefs({ hudEnabled: e.target.checked })}
                      className="rounded border-white/20 bg-black/40 text-secondary cursor-pointer"
                    />
                    <span className="text-[11px] text-white font-manrope font-semibold">
                      Show HUD
                    </span>
                  </label>

                  <div className="mb-3">
                    <div className="text-[9px] text-slate-500 font-manrope font-semibold mb-1.5 uppercase tracking-wider">
                      Corner
                    </div>
                    <div className="flex flex-wrap gap-1.5">
                      {CORNERS.map(c => (
                        <React.Fragment key={c.id}>
                          <Chip
                            active={prefs.hudCorner === c.id}
                            onClick={() => patchPrefs({ hudCorner: c.id })}
                          >
                            {c.label}
                          </Chip>
                        </React.Fragment>
                      ))}
                    </div>
                  </div>

                  <div>
                    <div className="flex justify-between text-[9px] text-slate-500 font-manrope font-semibold mb-1 uppercase tracking-wider">
                      <span>Opacity</span>
                      <span className="text-secondary font-mono normal-case">
                        {Math.round(prefs.hudOpacity * 100)}%
                      </span>
                    </div>
                    <input
                      type="range"
                      min={0.05}
                      max={1}
                      step={0.05}
                      disabled={!prefs.hudEnabled}
                      value={prefs.hudOpacity}
                      onChange={e => patchPrefs({ hudOpacity: parseFloat(e.target.value) })}
                      className="w-full accent-secondary cursor-pointer disabled:opacity-40"
                    />
                  </div>
                </SectionCard>
              </>
            )}

            {tab === 'ai' && (
              <SectionCard
                title="Google Gemini"
                icon="psychology"
                hint="API key for Mind & Mood assistant. Stored only in this browser."
              >
                <div className="relative flex items-center bg-black/40 border border-white/10 rounded-lg px-3 py-2">
                  <input
                    type={showKey ? 'text' : 'password'}
                    value={apiKey}
                    onChange={e => handleSaveKey(e.target.value)}
                    placeholder="AI Studio API key…"
                    className="w-full bg-transparent text-[12px] text-white placeholder-slate-600 focus:outline-none pr-9 font-mono"
                  />
                  <button
                    type="button"
                    onClick={() => setShowKey(!showKey)}
                    className="absolute right-2.5 text-slate-400 hover:text-white transition-colors cursor-pointer"
                    title={showKey ? 'Hide' : 'Show'}
                  >
                    <span className="material-symbols-outlined text-[18px] block">
                      {showKey ? 'visibility_off' : 'visibility'}
                    </span>
                  </button>
                </div>
                <div className="mt-2 flex items-center justify-between">
                  <span className="font-manrope text-[9px] text-slate-600 uppercase tracking-widest">
                    Local only
                  </span>
                  <a
                    href="https://aistudio.google.com/app/apikey"
                    target="_blank"
                    rel="noreferrer"
                    className="text-[10px] text-secondary hover:text-white transition-colors flex items-center gap-1 font-manrope font-semibold"
                  >
                    Get key
                    <span className="material-symbols-outlined text-[12px]">open_in_new</span>
                  </a>
                </div>
              </SectionCard>
            )}

            {tab === 'keyboard' && (
              <SectionCard
                title="Keyboard shortcuts"
                icon="keyboard"
                hint="Workspace drawing shortcuts. More bindings coming with tool redesign."
              >
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {SHORTCUTS.map(row => (
                    <div
                      key={row.action}
                      className="flex justify-between items-center gap-2 bg-black/30 px-2.5 py-2 rounded-lg border border-white/5"
                    >
                      <span className="font-manrope text-[10px] text-slate-400">{row.action}</span>
                      <div className="flex flex-wrap gap-1 justify-end">
                        {row.keys.map(k => (
                          <span
                            key={k}
                            className="px-1.5 py-0.5 bg-black/50 border border-white/10 rounded text-[9px] text-slate-300 font-mono"
                          >
                            {k}
                          </span>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              </SectionCard>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
