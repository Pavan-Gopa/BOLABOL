import React from 'react';
import { MandalaSettings, AppMode } from '../types';
import { motion, AnimatePresence } from 'motion/react';
import { 
  Settings2, 
  CircleDot, 
  Brush, 
  Eraser, 
  Download, 
  Save, 
  Play,
  RotateCcw,
  Palette
} from 'lucide-react';

interface ControlsProps {
  settings: MandalaSettings;
  setSettings: React.Dispatch<React.SetStateAction<MandalaSettings>>;
  mode: AppMode;
  setMode: (mode: AppMode) => void;
  activeColor: string;
  setActiveColor: (color: string) => void;
  tool: 'brush' | 'dots';
  setTool: (tool: 'brush' | 'dots') => void;
  onClear: () => void;
  onUndo: () => void;
}

export const Controls: React.FC<ControlsProps> = ({
  settings,
  setSettings,
  mode,
  setMode,
  activeColor,
  setActiveColor,
  tool,
  setTool,
  onClear,
  onUndo
}) => {
  const updateSetting = (key: keyof MandalaSettings, value: any) => {
    setSettings(prev => ({ ...prev, [key]: value }));
  };

  const colors = [
    '#44E2CD', // Secondary (Teal)
    '#CEBDFF', // Tertiary (Lavender)
    '#FFB4AB', // Error (Coral)
    '#FFFFFF', // White
    '#FFFBFE', // Off-white
    '#E3E3E3',
    '#FFD700',
    '#FF69B4',
    '#00FF00',
    '#4169E1'
  ];

  return (
    <div className="absolute top-20 right-6 flex flex-col gap-4 w-80 z-40 pointer-events-none">
      {/* Mode Switcher */}
      <div className="glass-panel p-1 rounded-xl flex gap-1 pointer-events-auto">
        <button
          onClick={() => setMode('TEMPLATE')}
          className={`flex-1 py-2 px-4 rounded-lg text-sm font-semibold transition-all ${
            mode === 'TEMPLATE' 
              ? 'bg-secondary text-on-secondary shadow-lg' 
              : 'text-on-surface-variant hover:bg-white/5'
          }`}
        >
          Template
        </button>
        <button
          onClick={() => setMode('WORKSPACE')}
          className={`flex-1 py-2 px-4 rounded-lg text-sm font-semibold transition-all ${
            mode === 'WORKSPACE' 
              ? 'bg-secondary text-on-secondary shadow-lg' 
              : 'text-on-surface-variant hover:bg-white/5'
          }`}
        >
          Workspace
        </button>
      </div>

      <AnimatePresence mode="wait">
        {mode === 'TEMPLATE' ? (
          <motion.div
            key="template-panel"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: 20 }}
            className="glass-panel p-6 rounded-2xl flex flex-col gap-6 pointer-events-auto"
          >
            <div className="flex items-center gap-2 border-b border-white/10 pb-3">
              <Settings2 size={18} className="text-secondary" />
              <h2 className="text-sm font-bold uppercase tracking-widest text-on-surface">Generator</h2>
            </div>

            {/* Symmetry / Grid */}
            <div className="space-y-4">
              <label className="block">
                <div className="flex justify-between text-xs text-on-surface-variant mb-2">
                  <span>Symmetry Sections</span>
                  <span className="text-secondary font-mono">{settings.sections}</span>
                </div>
                <input
                  type="range"
                  min="4"
                  max="64"
                  value={settings.sections}
                  onChange={(e) => updateSetting('sections', parseInt(e.target.value))}
                  className="w-full accent-secondary"
                />
              </label>

              <label className="block">
                <div className="flex justify-between text-xs text-on-surface-variant mb-2">
                  <span>Concentric Rings</span>
                  <span className="text-secondary font-mono">{settings.rings}</span>
                </div>
                <input
                  type="range"
                  min="1"
                  max="20"
                  value={settings.rings}
                  onChange={(e) => updateSetting('rings', parseInt(e.target.value))}
                  className="w-full accent-secondary"
                />
              </label>

              <div className="flex gap-4">
                 <button 
                  onClick={() => updateSetting('showGridLines', !settings.showGridLines)}
                  className={`flex-1 p-2 rounded-lg text-[10px] border transition-all ${settings.showGridLines ? 'border-secondary bg-secondary/10 text-secondary' : 'border-white/10 text-on-surface-variant'}`}
                >
                  Grid Lines
                </button>
                <button 
                  onClick={() => updateSetting('showRings', !settings.showRings)}
                  className={`flex-1 p-2 rounded-lg text-[10px] border transition-all ${settings.showRings ? 'border-secondary bg-secondary/10 text-secondary' : 'border-white/10 text-on-surface-variant'}`}
                >
                  Rings
                </button>
              </div>

              <div className="flex items-center justify-between pt-2">
                <span className="text-xs text-on-surface-variant">Reflection (Mirror)</span>
                <button 
                  onClick={() => updateSetting('reflect', !settings.reflect)}
                  className={`w-8 h-4 rounded-full transition-colors relative ${settings.reflect ? 'bg-secondary' : 'bg-white/10'}`}
                >
                   <div className={`absolute top-0.5 w-3 h-3 rounded-full bg-white transition-all ${settings.reflect ? 'left-4.5' : 'left-0.5'}`} />
                </button>
              </div>
            </div>

            {/* Rose Curve */}
            <div className="space-y-4 pt-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-on-surface">Rose Petals</span>
                <button 
                  onClick={() => updateSetting('showPetals', !settings.showPetals)}
                  className={`w-8 h-4 rounded-full transition-colors relative ${settings.showPetals ? 'bg-secondary' : 'bg-white/10'}`}
                >
                   <div className={`absolute top-0.5 w-3 h-3 rounded-full bg-white transition-all ${settings.showPetals ? 'left-4.5' : 'left-0.5'}`} />
                </button>
              </div>
              
              <label className="block opacity-80">
                <div className="flex justify-between text-[11px] text-on-surface-variant mb-2">
                  <span>Petal Length</span>
                  <span>{settings.petalLength}%</span>
                </div>
                <input
                  type="range"
                  min="10"
                  max="100"
                  value={settings.petalLength}
                  onChange={(e) => updateSetting('petalLength', parseInt(e.target.value))}
                  className="w-full accent-secondary"
                />
              </label>
              
              <label className="block opacity-80">
                <div className="flex justify-between text-[11px] text-on-surface-variant mb-2">
                  <span>Frequency (k)</span>
                  <span>{settings.petalFrequency}</span>
                </div>
                <input
                  type="range"
                  min="1"
                  max="12"
                  step="0.1"
                  value={settings.petalFrequency}
                  onChange={(e) => updateSetting('petalFrequency', parseFloat(e.target.value))}
                  className="w-full accent-secondary"
                />
              </label>
            </div>

             {/* Spiral */}
             <div className="space-y-4 pt-2">
              <div className="flex items-center justify-between">
                <span className="text-xs font-bold text-on-surface">Phi Spiral</span>
                <button 
                  onClick={() => updateSetting('showSpiral', !settings.showSpiral)}
                  className={`w-8 h-4 rounded-full transition-colors relative ${settings.showSpiral ? 'bg-secondary' : 'bg-white/10'}`}
                >
                   <div className={`absolute top-0.5 w-3 h-3 rounded-full bg-white transition-all ${settings.showSpiral ? 'left-4.5' : 'left-0.5'}`} />
                </button>
              </div>
              
              <label className="block opacity-80">
                <div className="flex justify-between text-[11px] text-on-surface-variant mb-2">
                  <span>Growth Rate</span>
                  <span>{settings.spiralGrowth}</span>
                </div>
                <input
                  type="range"
                  min="0.1"
                  max="2"
                  step="0.05"
                  value={settings.spiralGrowth}
                  onChange={(e) => updateSetting('spiralGrowth', parseFloat(e.target.value))}
                  className="w-full accent-secondary"
                />
              </label>
            </div>

            <button 
              onClick={() => setMode('WORKSPACE')}
              className="mt-4 bg-gradient-to-r from-secondary to-tertiary text-on-secondary p-3 rounded-xl font-bold text-sm shadow-xl hover:scale-105 active:scale-95 transition-all flex items-center justify-center gap-2"
            >
              <Play size={16} />
              Set to Workspace
            </button>
          </motion.div>
        ) : (
          <motion.div
            key="workspace-panel"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: 20 }}
            className="glass-panel p-6 rounded-2xl flex flex-col gap-6 pointer-events-auto"
          >
            <div className="flex items-center gap-2 border-b border-white/10 pb-3">
              <Palette size={18} className="text-secondary" />
              <h2 className="text-sm font-bold uppercase tracking-widest text-on-surface">Studio Tools</h2>
            </div>

            {/* Tools */}
            <div className="grid grid-cols-2 gap-3">
              <button
                onClick={() => setTool('brush')}
                className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-all ${
                  tool === 'brush' ? 'border-secondary bg-secondary/10 text-secondary' : 'border-white/10 text-on-surface-variant hover:bg-white/5'
                }`}
              >
                <Brush size={20} />
                <span className="text-[10px] uppercase tracking-tighter">Brush</span>
              </button>
              <button
                onClick={() => setTool('dots')}
                className={`p-3 rounded-xl border flex flex-col items-center gap-2 transition-all ${
                  tool === 'dots' ? 'border-secondary bg-secondary/10 text-secondary' : 'border-white/10 text-on-surface-variant hover:bg-white/5'
                }`}
              >
                <CircleDot size={20} />
                <span className="text-[10px] uppercase tracking-tighter">Smart Dots</span>
              </button>
            </div>

            {/* Color Palette */}
            <div>
              <span className="text-[11px] text-on-surface-variant uppercase tracking-widest block mb-3">Palette</span>
              <div className="grid grid-cols-5 gap-3">
                {colors.map(c => (
                  <button
                    key={c}
                    onClick={() => setActiveColor(c)}
                    className={`w-10 h-10 rounded-full border-2 transition-transform hover:scale-110 active:scale-90 ${activeColor === c ? 'border-white scale-110 shadow-lg' : 'border-transparent'}`}
                    style={{ backgroundColor: c }}
                  />
                ))}
              </div>
            </div>

            {/* Actions */}
            <div className="flex gap-2 pt-4">
              <button 
                onClick={onUndo}
                className="flex-1 bg-white/5 hover:bg-white/10 text-on-surface p-3 rounded-xl text-xs flex items-center justify-center gap-2 transition-all"
              >
                <RotateCcw size={14} />
                Undo
              </button>
              <button 
                onClick={onClear}
                className="flex-1 bg-white/5 hover:bg-white/10 text-on-error p-3 rounded-xl text-xs flex items-center justify-center gap-2 transition-all"
              >
                <Eraser size={14} />
                Clear
              </button>
            </div>

            <button className="bg-white/10 hover:bg-white/20 text-on-background p-3 rounded-xl font-bold text-sm shadow-lg transition-all flex items-center justify-center gap-2">
              <Download size={16} />
              Export Artwork
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
};
