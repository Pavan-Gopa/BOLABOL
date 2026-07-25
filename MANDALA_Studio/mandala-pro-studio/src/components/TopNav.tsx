import React, { useEffect, useState } from 'react';
import { ViewState } from '../types';
import { loadUserProfile, UserProfile } from '../utils/userProfile';

interface TopNavProps {
  currentView: ViewState;
  onViewChange: (view: ViewState) => void;
  onSave?: () => void;
  onShare?: () => void;
}

export default function TopNav({ currentView, onViewChange, onSave, onShare }: TopNavProps) {
  const [profile, setProfile] = useState<UserProfile>(() => loadUserProfile());

  useEffect(() => {
    const onProfile = (e: Event) => {
      const detail = (e as CustomEvent<UserProfile>).detail;
      setProfile(detail ? { ...detail } : loadUserProfile());
    };
    window.addEventListener('mandala-profile-changed', onProfile as EventListener);
    return () => window.removeEventListener('mandala-profile-changed', onProfile as EventListener);
  }, []);

  return (
    <header
      className="fixed top-0 left-0 right-0 h-11 border-b ui-border z-50 px-4 flex items-center justify-between shadow-[0_2px_15px_rgba(0,0,0,0.15)] backdrop-blur-2xl"
      style={{ background: 'var(--app-nav-bg)' }}
    >
      {/* Brand Logo */}
      <div className="flex items-center gap-2 select-none">
        <span className="text-sm font-extrabold bg-gradient-to-r from-teal-400 to-violet-500 bg-clip-text text-transparent font-manrope tracking-tight">
          Mandala Studio
        </span>
      </div>

      {/* Navigation Tabs */}
      <nav className="flex items-center h-full">
        {[
          { id: 'workspace', label: 'Workspace' },
          { id: 'templates', label: 'Templates' },
          { id: 'gallery', label: 'My Gallery' }
        ].map(tab => {
          const isActive = currentView === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => onViewChange(tab.id as ViewState)}
              className={`h-11 flex items-center px-4 font-manrope text-[10px] font-bold uppercase tracking-widest relative transition-all duration-300 cursor-pointer ${
                isActive
                  ? 'text-secondary border-b-2 border-secondary'
                  : 'text-slate-400 hover:text-white border-b-2 border-transparent hover:bg-white/5'
              }`}
            >
              {tab.label}
            </button>
          );
        })}
      </nav>

      {/* Trailing Action Icons */}
      <div className="flex items-center gap-2">
        <div
          className={`flex items-center gap-1.5 transition-all duration-300 ${
            currentView === 'workspace'
              ? 'opacity-100 translate-x-0'
              : 'opacity-0 translate-x-4 pointer-events-none'
          }`}
        >
          <button
            onClick={onSave}
            aria-label="save"
            className="text-slate-400 hover:bg-white/5 hover:text-white transition-all p-1.5 rounded cursor-pointer flex items-center justify-center"
            title="Save Mandala Project"
          >
            <span className="material-symbols-outlined text-[17px]">save</span>
          </button>
          <button
            onClick={onShare}
            aria-label="share"
            className="text-slate-400 hover:bg-white/5 hover:text-white transition-all p-1.5 rounded cursor-pointer flex items-center justify-center"
            title="Share Mandala Settings"
          >
            <span className="material-symbols-outlined text-[17px]">share</span>
          </button>
          <div className="w-px h-4 bg-white/15 mx-1" />
        </div>

        <button
          aria-label="settings"
          onClick={() => onViewChange('settings')}
          className={`p-1.5 rounded flex items-center justify-center transition-all cursor-pointer ${
            currentView === 'settings'
              ? 'text-white bg-white/10 shadow-[0_0_10px_rgba(255,255,255,0.05)]'
              : 'text-slate-400 hover:bg-white/5 hover:text-white'
          }`}
          title="Settings"
        >
          <span className="material-symbols-outlined text-[17px]">settings</span>
        </button>

        <button
          onClick={() => onViewChange('settings')}
          className="flex items-center gap-1.5 pl-0.5 pr-1.5 py-0.5 rounded-full hover:bg-white/5 transition-all cursor-pointer group"
          title={profile.displayName || 'Account profile'}
        >
          {profile.avatarDataUrl ? (
            <img
              src={profile.avatarDataUrl}
              alt=""
              className="w-7 h-7 rounded-full object-cover border border-white/15 group-hover:border-secondary/50 transition-colors"
            />
          ) : (
            <span className="material-symbols-outlined text-[22px] text-slate-400 group-hover:text-white transition-colors">
              account_circle
            </span>
          )}
          <span className="hidden sm:block font-manrope text-[9px] font-bold text-slate-500 group-hover:text-slate-300 max-w-[5.5rem] truncate">
            {profile.displayName || 'Profile'}
          </span>
        </button>
      </div>
    </header>
  );
}
