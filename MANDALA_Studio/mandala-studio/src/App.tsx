import React, { useState } from 'react';
import { MandalaCanvas } from './components/MandalaCanvas';
import { Controls } from './components/Controls';
import { MandalaSettings, AppMode, Stroke } from './types';
import { 
  Plus, 
  Search, 
  Settings, 
  CircleUser, 
  Brush, 
  LayoutGrid, 
  Layers, 
  Share2 
} from 'lucide-react';

export default function App() {
  const [mode, setMode] = useState<AppMode>('TEMPLATE');
  const [settings, setSettings] = useState<MandalaSettings>({
    sections: 12,
    rings: 6,
    showGridLines: true,
    showRings: true,
    petalLength: 60,
    petalFrequency: 4,
    showPetals: true,
    spiralGrowth: 0.5,
    showSpiral: false,
    reflect: true
  });

  const [strokes, setStrokes] = useState<Stroke[]>([]);
  const [activeColor, setActiveColor] = useState('#44E2CD');
  const [tool, setTool] = useState<'brush' | 'dots'>('dots');

  const handleAddStroke = (stroke: Stroke) => {
    setStrokes(prev => [...prev, stroke]);
  };

  const handleUndo = () => {
    setStrokes(prev => prev.slice(0, -1));
  };

  const handleClear = () => {
    if (window.confirm('Clear all strokes?')) {
      setStrokes([]);
    }
  };

  return (
    <div className="flex bg-background text-on-background min-h-screen font-body-base overflow-hidden">
      {/* Top Navbar */}
      <header className="fixed top-0 left-0 right-0 h-16 glass-panel border-b border-white/10 flex items-center justify-between px-8 z-50">
        <div className="flex items-center gap-4">
          <div className="text-lg font-bold tracking-tighter text-transparent bg-clip-text bg-gradient-to-r from-secondary to-tertiary">
            MANDALA Pro Studio
          </div>
        </div>
        
        <nav className="hidden md:flex items-center gap-8 text-xs font-bold uppercase tracking-widest text-on-surface-variant">
          <button 
             onClick={() => setMode('WORKSPACE')}
             className={`transition-colors h-full flex items-center px-2 border-b-2 hover:text-on-background ${mode === 'WORKSPACE' ? 'border-secondary text-on-background' : 'border-transparent'}`}
          >
            Studio
          </button>
          <button 
             onClick={() => setMode('TEMPLATE')}
             className={`transition-colors h-full flex items-center px-2 border-b-2 hover:text-on-background ${mode === 'TEMPLATE' ? 'border-secondary text-on-background' : 'border-transparent'}`}
          >
            Generator
          </button>
          <button className="hover:text-on-background transition-colors">Gallery</button>
        </nav>

        <div className="flex items-center gap-4">
          <div className="relative hidden sm:block">
            <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-on-surface-variant" />
            <input 
              type="text" 
              placeholder="Search..." 
              className="bg-white/5 border border-white/10 rounded-full pl-10 pr-4 py-1.5 text-xs text-on-background focus:outline-none focus:ring-1 focus:ring-secondary w-40"
            />
          </div>
          <button className="text-on-surface-variant hover:text-on-background p-2 transition-colors">
            <Settings size={20} />
          </button>
          <button className="text-on-surface-variant hover:text-on-background p-2 transition-colors">
            <CircleUser size={20} />
          </button>
        </div>
      </header>

      {/* Side Navbar */}
      <aside className="fixed left-4 top-24 bottom-6 w-20 glass-panel rounded-2xl flex flex-col items-center py-8 gap-8 border border-white/10 z-40">
        <button className="text-secondary p-3 rounded-xl hover:bg-white/5 transition-all group relative">
          <Brush size={24} />
          <span className="absolute left-20 bg-surface-container-high px-2 py-1 rounded text-[10px] opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none border border-white/10">Design Mode</span>
        </button>
        <button className="text-on-surface-variant p-3 rounded-xl hover:bg-white/5 transition-all group relative">
          <LayoutGrid size={24} />
           <span className="absolute left-20 bg-surface-container-high px-2 py-1 rounded text-[10px] opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none border border-white/10">Library</span>
        </button>
        <button className="text-on-surface-variant p-3 rounded-xl hover:bg-white/5 transition-all group relative">
          <Layers size={24} />
           <span className="absolute left-20 bg-surface-container-high px-2 py-1 rounded text-[10px] opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none border border-white/10">Layers</span>
        </button>
        <button className="mt-auto text-on-surface-variant p-3 rounded-xl hover:bg-white/5 transition-all group relative">
          <Share2 size={24} />
           <span className="absolute left-20 bg-surface-container-high px-2 py-1 rounded text-[10px] opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none border border-white/10">Share</span>
        </button>
      </aside>

      {/* Main Content Area */}
      <main className="flex-1 relative">
        <MandalaCanvas 
          settings={settings}
          mode={mode}
          activeColor={activeColor}
          tool={tool}
          onAddStroke={handleAddStroke}
          strokes={strokes}
        />
        
        {/* Float Controls Overlay */}
        <Controls 
          settings={settings}
          setSettings={setSettings}
          mode={mode}
          setMode={setMode}
          activeColor={activeColor}
          setActiveColor={setActiveColor}
          tool={tool}
          setTool={setTool}
          onClear={handleClear}
          onUndo={handleUndo}
        />

        {/* Global Floating Action */}
        <button className="fixed bottom-8 left-1/2 -translate-x-1/2 bg-secondary text-on-secondary px-6 py-3 rounded-full font-bold text-sm shadow-xl hover:scale-105 active:scale-95 transition-all flex items-center gap-2 z-40">
           <Plus size={18} />
           New Element
        </button>
      </main>
    </div>
  );
}
