import React, { useState, useEffect, useRef, useCallback } from 'react';
import { BrushSettings, TemplateSettings, Stroke, DrawingLayer, Point } from '../types';
import CanvasRenderer from './CanvasRenderer';
import ExportModal from './ExportModal';
import ColorPalettePanel from './ColorPalettePanel';
import { generateMandalaFromMood } from '../utils/AiGemini';
import { AmbientSoundscape } from '../utils/SoundEngine';
import { perfHud } from '../utils/PerfHud';
import { loadCanvasPrefs } from '../utils/canvasPrefs';

interface WorkspaceProps {
  brushSettings: BrushSettings;
  setBrushSettings: (s: BrushSettings) => void;
  templateSettings: TemplateSettings;
  setTemplateSettings: (s: TemplateSettings) => void;
  strokes: Stroke[];
  addStroke: (s: Stroke) => void;
  onClear: () => void;
  onUndo: () => void;
  onRedo: () => void;
  canUndo: boolean;
  canRedo: boolean;
  soundEngine: AmbientSoundscape;
  drawingLayers: DrawingLayer[];
  setDrawingLayers: (layers: DrawingLayer[]) => void;
  activeLayerId: string;
  setActiveLayerId: (id: string) => void;
  onDeleteLayerStrokes: (layerId: string) => void;
  canvasSize: number;
  onRequestResizeCanvas: () => void;
  onFitCanvasToContent: () => void;
}

const LAYER_METADATA: { [key: string]: { label: string; key: keyof TemplateSettings; svg: React.ReactNode } } = {
  grid: { 
    label: 'Radial Rays Grid', 
    key: 'showGridLines',
    svg: (
      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <circle cx="12" cy="12" r="1.5" fill="currentColor"/>
        <line x1="12" y1="2" x2="12" y2="22"/>
        <line x1="2" y1="12" x2="22" y2="12"/>
        <line x1="5" y1="5" x2="19" y2="19"/>
        <line x1="19" y1="5" x2="5" y2="19"/>
      </svg>
    )
  },
  rings: { 
    label: 'Concentric Rings', 
    key: 'showRings',
    svg: (
      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <circle cx="12" cy="12" r="9.5"/>
        <circle cx="12" cy="12" r="6"/>
        <circle cx="12" cy="12" r="2.5"/>
      </svg>
    )
  },
  petals: { 
    label: 'Rhodonea Petals', 
    key: 'showPetals',
    svg: (
      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M12,12 C12,7.5 9,3.5 12,3.5 C15,3.5 12,7.5 12,12 C16.5,12 20.5,9 20.5,12 C20.5,15 16.5,12 12,12 C12,16.5 15,20.5 12,20.5 C9,20.5 12,16.5 12,12 C7.5,12 3.5,15 3.5,12 C3.5,9 7.5,12 12,12 Z"/>
      </svg>
    )
  },
  spiral: { 
    label: 'Golden Log-Spiral', 
    key: 'showSpiral',
    svg: (
      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M12,12 A2,2 0 0,0 14,10 A4,4 0 0,0 10,6 A6,6 0 0,0 16,16 A8,8 0 0,0 6,12"/>
      </svg>
    )
  },
  lissajous: { 
    label: 'Lissajous Waveguide', 
    key: 'showLissajous',
    svg: (
      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M4,7 C4,17 20,7 20,17 C20,21 4,3 4,7"/>
      </svg>
    )
  },
  cardioid: { 
    label: 'Pascal Cardioid', 
    key: 'showCardioid',
    svg: (
      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M12,19.5 C10,17.5 4.5,12 4.5,8 C4.5,5.5 6.5,3.5 9,3.5 C10.5,3.5 11.5,4.2 12,5 C12.5,4.2 13.5,3.5 15,3.5 C17.5,3.5 19.5,5.5 19.5,8 C19.5,12 14,17.5 12,19.5 Z"/>
      </svg>
    )
  },
  spirograph: { 
    label: 'Gear Spirograph', 
    key: 'showSpirograph',
    svg: (
      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M12,3 Q13.5,8.5 18,5.5 Q15.5,10 21,12 Q15.5,14 18,18.5 Q13.5,15.5 12,21 Q10.5,15.5 6,18.5 Q8.5,14 3,12 Q8.5,10 6,5.5 Q10.5,8.5 12,3 Z"/>
      </svg>
    )
  },
  superellipse: { 
    label: 'Lamé Superellipse', 
    key: 'showSuperellipse',
    svg: (
      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <path d="M12,3 C17.5,3 21,6.5 21,12 C21,17.5 17.5,21 12,21 C6.5,21 3,17.5 3,12 C3,6.5 6.5,3 12,3 Z"/>
      </svg>
    )
  },
  maurer: { 
    label: 'Maurer Rose Net', 
    key: 'showMaurer',
    svg: (
      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <polygon points="12,3 19,7 19,15 12,21 5,15 5,7"/>
        <line x1="12" y1="3" x2="12" y2="21"/>
        <line x1="5" y1="7" x2="19" y2="15"/>
        <line x1="5" y1="15" x2="19" y2="7"/>
      </svg>
    )
  }
};

// Custom Glass Switch toggle
const ToggleSwitch = ({
  checked,
  onChange,
  label
}: {
  checked: boolean;
  onChange: (val: boolean) => void;
  label: string;
}) => (
  <label className="flex items-center justify-between text-[10.5px] text-slate-300 hover:text-white cursor-pointer select-none py-1.5 transition-colors gap-2">
    <span className="leading-snug">{label}</span>
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className={`ui-switch ${checked ? 'ui-switch-on' : 'ui-switch-off'}`}
    >
      <span className={`ui-switch-knob ${checked ? 'ui-switch-knob-on' : 'ui-switch-knob-off'}`} />
    </button>
  </label>
);

export default function Workspace({ 
  brushSettings, setBrushSettings, 
  templateSettings, setTemplateSettings,
  strokes, addStroke, onClear,
  onUndo, onRedo, canUndo, canRedo,
  soundEngine,
  drawingLayers, setDrawingLayers,
  activeLayerId, setActiveLayerId,
  onDeleteLayerStrokes,
  canvasSize,
  onRequestResizeCanvas,
  onFitCanvasToContent
}: WorkspaceProps) {

  const [leftCollapsed, setLeftCollapsed] = useState(false);
  const [rightCollapsed, setRightCollapsed] = useState(false);
  const [showExportModal, setShowExportModal] = useState(false);
  
  // Audio state variables
  const [isPlayingSound, setIsPlayingSound] = useState(soundEngine.getIsPlaying());
  const [soundMood, setSoundMood] = useState<'cosmic' | 'forest' | 'meditation' | 'wind'>(
    (soundEngine.getCurrentMood() as any) || 'cosmic'
  );
  const [soundVolume, setSoundVolume] = useState(soundEngine.getVolume());
  const [isMuted, setIsMuted] = useState(soundEngine.getMutedState());

  // Floating color panel position
  const [colorPos, setColorPos] = useState({
    x: Math.max(80, window.innerWidth - 240),
    y: Math.max(80, window.innerHeight - 420)
  });

  // Create drawing layer
  const handleCreateDrawingLayer = () => {
    const newId = 'layer_' + Date.now().toString(36);
    const newName = `Layer ${drawingLayers.length + 1}`;
    const updated = [...drawingLayers, { id: newId, name: newName, visible: true }];
    setDrawingLayers(updated);
    setActiveLayerId(newId);
  };

  // Toggle drawing layer visibility
  const handleToggleDrawingLayerVisibility = (layerId: string) => {
    const updated = drawingLayers.map(l => l.id === layerId ? { ...l, visible: !l.visible } : l);
    setDrawingLayers(updated);
  };

  // Rename drawing layer
  const handleRenameDrawingLayer = (layerId: string, newName: string) => {
    const updated = drawingLayers.map(l => l.id === layerId ? { ...l, name: newName } : l);
    setDrawingLayers(updated);
  };

  // Move drawing layer in order (Z-index index)
  const handleMoveDrawingLayer = (index: number, direction: 'up' | 'down') => {
    const newOrder = [...drawingLayers];
    const targetIdx = direction === 'up' ? index - 1 : index + 1;
    if (targetIdx >= 0 && targetIdx < newOrder.length) {
      const temp = newOrder[index];
      newOrder[index] = newOrder[targetIdx];
      newOrder[targetIdx] = temp;
      setDrawingLayers(newOrder);
    }
  };

  // Delete drawing layer (removes associated strokes from app state too!)
  const handleDeleteDrawingLayer = (layerId: string) => {
    if (confirm("Are you sure you want to delete this layer? All strokes drawn on this layer will be deleted.")) {
      const remainingLayers = drawingLayers.filter(l => l.id !== layerId);
      setDrawingLayers(remainingLayers);
      if (activeLayerId === layerId && remainingLayers.length > 0) {
        setActiveLayerId(remainingLayers[remainingLayers.length - 1].id);
      }
      onDeleteLayerStrokes(layerId);
    }
  };

  // Convert a vector mathematical rail into an editable pixel/drawing stroke layer
  const handleConvertGuideToStrokes = (guideId: string) => {
    const cx = window.innerWidth / 2;
    const cy = window.innerHeight / 2;
    const radius = templateSettings.radius;

    const layerId = 'layer_' + Date.now().toString(36);
    let layerName = "";
    const strokePoints: Point[] = [];

    const defaultBrush: BrushSettings = {
      type: 'vector',
      size: 2,
      opacity: 80,
      flow: 100,
      color: brushSettings.color || '#44e2cd' // default to active user color or signature teal
    };

    if (guideId === 'grid') {
      layerName = "Radial Rays Layer";
      strokePoints.push({ x: cx, y: cy });
      strokePoints.push({ x: cx + radius, y: cy });
    } 
    else if (guideId === 'rings') {
      layerName = "Concentric Rings Layer";
      const numRings = templateSettings.layers;
      const strokesList: Stroke[] = [];
      for (let rIdx = 1; rIdx <= numRings; rIdx++) {
        const r = radius * (rIdx / numRings);
        const pts: Point[] = [];
        for (let theta = 0; theta <= Math.PI * 2 + 0.1; theta += 0.05) {
          pts.push({
            x: cx + r * Math.cos(theta),
            y: cy + r * Math.sin(theta)
          });
        }
        strokesList.push({ points: pts, settings: { ...defaultBrush }, layerId });
      }
      
      setDrawingLayers([...drawingLayers, { id: layerId, name: layerName, visible: true }]);
      setActiveLayerId(layerId);
      strokesList.forEach(s => addStroke(s));
      return;
    }
    else if (guideId === 'petals') {
      layerName = "Rose Petals Layer";
      const k = templateSettings.petalFrequency;
      const a = templateSettings.petalLength;
      for (let theta = 0; theta <= Math.PI * 2 + 0.05; theta += 0.02) {
        const r = a * Math.cos(k * theta);
        strokePoints.push({
          x: cx + r * Math.cos(theta),
          y: cy + r * Math.sin(theta)
        });
      }
    }
    else if (guideId === 'spiral') {
      layerName = "Logarithmic Spiral Layer";
      const a = templateSettings.spiralScale;
      const b = templateSettings.spiralGrowth;
      const arms = templateSettings.spiralArms;
      const strokesList: Stroke[] = [];
      
      for (let arm = 0; arm < arms; arm++) {
        const pts: Point[] = [];
        const armOffset = (arm * Math.PI * 2) / arms;
        for (let theta = 0.1; theta <= 15.0; theta += 0.1) {
          const r = a * Math.pow(Math.E, b * theta);
          if (r > radius * 1.5) break;
          pts.push({
            x: cx + r * Math.cos(theta + armOffset),
            y: cy + r * Math.sin(theta + armOffset)
          });
        }
        if (pts.length > 0) {
          strokesList.push({ points: pts, settings: { ...defaultBrush }, layerId });
        }
      }

      setDrawingLayers([...drawingLayers, { id: layerId, name: layerName, visible: true }]);
      setActiveLayerId(layerId);
      strokesList.forEach(s => addStroke(s));
      return;
    }
    else if (guideId === 'lissajous') {
      layerName = "Lissajous Wave Layer";
      const fX = templateSettings.lissFreqX;
      const fY = templateSettings.lissFreqY;
      const phase = (templateSettings.lissPhase * Math.PI) / 180;
      const a = radius * 0.8;
      const b = radius * 0.8;
      for (let t = 0; t <= Math.PI * 2 + 0.05; t += 0.02) {
        strokePoints.push({
          x: cx + a * Math.cos(fX * t + phase),
          y: cy + b * Math.sin(fY * t)
        });
      }
    }
    else if (guideId === 'cardioid') {
      layerName = "Pascal Limacon Layer";
      const a = templateSettings.cardioidA;
      const b = templateSettings.cardioidB;
      for (let theta = 0; theta <= Math.PI * 2 + 0.05; theta += 0.02) {
        const r = a + b * Math.cos(theta);
        strokePoints.push({
          x: cx + r * Math.cos(theta),
          y: cy + r * Math.sin(theta)
        });
      }
    }
    else if (guideId === 'spirograph') {
      layerName = "Spirograph Layer";
      const R = templateSettings.spiroR;
      const r = templateSettings.spiro_r;
      const d = templateSettings.spiroD;
      const type = templateSettings.spiroType;
      const rotations = templateSettings.spiroRotations;
      
      for (let theta = 0; theta <= rotations * Math.PI * 2 + 0.05; theta += 0.05) {
        let x = 0;
        let y = 0;
        if (type === 'epi') {
          x = (R + r) * Math.cos(theta) - d * Math.cos(((R + r) / r) * theta);
          y = (R + r) * Math.sin(theta) - d * Math.sin(((R + r) / r) * theta);
        } else {
          x = (R - r) * Math.cos(theta) + d * Math.cos(((R - r) / r) * theta);
          y = (R - r) * Math.sin(theta) - d * Math.sin(((R - r) / r) * theta);
        }
        strokePoints.push({ x: cx + x, y: cy + y });
      }
    }
    else if (guideId === 'superellipse') {
      layerName = "Superellipse Layer";
      const n = templateSettings.superellipseN;
      const a = templateSettings.superellipseA;
      const b = templateSettings.superellipseB;
      for (let theta = 0; theta <= Math.PI * 2 + 0.05; theta += 0.02) {
        const cosT = Math.cos(theta);
        const sinT = Math.sin(theta);
        const x = a * Math.sign(cosT) * Math.pow(Math.abs(cosT), 2 / n);
        const y = b * Math.sign(sinT) * Math.pow(Math.abs(sinT), 2 / n);
        strokePoints.push({ x: cx + x, y: cy + y });
      }
    }
    else if (guideId === 'maurer') {
      layerName = "Maurer Rose Layer";
      const n = templateSettings.maurerN;
      const d = templateSettings.maurerD;
      const a = radius * 0.8;
      for (let i = 0; i <= 360; i++) {
        const k = i * d;
        const r = a * Math.sin((n * k * Math.PI) / 180);
        const theta = (k * Math.PI) / 180;
        strokePoints.push({
          x: cx + r * Math.cos(theta),
          y: cy + r * Math.sin(theta)
        });
      }
    }

    if (strokePoints.length > 0) {
      const newStroke: Stroke = {
        points: strokePoints,
        settings: defaultBrush,
        layerId
      };
      
      setDrawingLayers([...drawingLayers, { id: layerId, name: layerName, visible: true }]);
      setActiveLayerId(layerId);
      addStroke(newStroke);
    }
  };

  // AI assistant states
  const [showAiModal, setShowAiModal] = useState(false);
  const [aiPrompt, setAiPrompt] = useState('');
  const [aiLoading, setAiLoading] = useState(false);
  const [aiFeedback, setAiFeedback] = useState('');
  const [isListening, setIsListening] = useState(false);

  // Sync state values from global audio engine
  useEffect(() => {
    setIsPlayingSound(soundEngine.getIsPlaying());
    setSoundVolume(soundEngine.getVolume());
    setIsMuted(soundEngine.getMutedState());
  }, [soundEngine]);

  const handleToggleSound = () => {
    if (isPlayingSound) {
      soundEngine.stop();
      setIsPlayingSound(false);
    } else {
      soundEngine.play(soundMood);
      setIsPlayingSound(true);
    }
  };

  const handleChangeSoundMood = (mood: 'cosmic' | 'forest' | 'meditation' | 'wind') => {
    setSoundMood(mood);
    if (isPlayingSound) {
      soundEngine.play(mood);
    }
  };

  const handleVolumeChange = (vol: number) => {
    setSoundVolume(vol);
    soundEngine.setVolume(vol);
  };

  const handleToggleMute = () => {
    const muted = soundEngine.toggleMute();
    setIsMuted(muted);
  };

  // Speech Recognition
  const startListening = () => {
    // @ts-ignore
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
      alert("Speech recognition is not supported in this browser. Please use Chrome or Safari.");
      return;
    }
    const recognition = new SpeechRecognition();
    recognition.lang = 'ru-RU';
    recognition.interimResults = false;
    recognition.maxAlternatives = 1;

    recognition.onstart = () => {
      setIsListening(true);
    };

    recognition.onresult = (event: any) => {
      const speechResult = event.results[0][0].transcript;
      setAiPrompt(prev => prev ? prev + " " + speechResult : speechResult);
    };

    recognition.onerror = (event: any) => {
      console.error("Speech recognition error", event.error);
      setIsListening(false);
    };

    recognition.onend = () => {
      setIsListening(false);
    };

    recognition.start();
  };

  // Trigger Gemini mood mandala layout
  const handleGenerateAiMood = async () => {
    if (!aiPrompt.trim()) return;
    setAiLoading(true);
    setAiFeedback('');
    try {
      const result = await generateMandalaFromMood(aiPrompt);
      
      setTemplateSettings({
        segments: result.segments,
        radius: 400,
        rotation: 0,
        layers: result.layers,
        mirror: result.mirror,
        showGridLines: result.showGridLines,
        showRings: result.showRings,
        showGridInExport: templateSettings.showGridInExport,
        snapToGuides: templateSettings.snapToGuides,
        petalLength: result.petalLength,
        petalFrequency: result.petalFrequency,
        showPetals: result.showPetals,
        spiralGrowth: result.spiralGrowth,
        spiralScale: 15,
        spiralArms: 3,
        showSpiral: result.showSpiral,
        showLissajous: false,
        lissFreqX: 3,
        lissFreqY: 4,
        lissPhase: 0,
        showCardioid: false,
        cardioidA: 50,
        cardioidB: 50,
        ringModulationAmp: 0,
        ringModulationFreq: 4,
        showSpirograph: false,
        spiroR: 60,
        spiro_r: 30,
        spiroD: 40,
        spiroType: 'epi',
        spiroRotations: 10,
        showSuperellipse: false,
        superellipseN: 1.0,
        superellipseA: 50,
        superellipseB: 50,
        showMaurer: false,
        maurerN: 6,
        maurerD: 71,
        guideLayerOrder: templateSettings.guideLayerOrder || ['grid', 'rings', 'petals', 'spiral', 'lissajous', 'cardioid', 'spirograph', 'superellipse', 'maurer']
      });

      setBrushSettings({
        type: result.brushType,
        size: result.brushSize,
        opacity: result.brushOpacity,
        flow: 50,
        color: result.brushColor,
        dotProfile: 'sine'
      });

      handleChangeSoundMood(result.soundscapeMood);
      if (!isPlayingSound) {
        soundEngine.play(result.soundscapeMood);
        setIsPlayingSound(true);
      }

      setAiFeedback(result.aiExplanation);
    } catch (err: any) {
      alert(err.message || 'AI generation failed. Enter your Gemini API Key in the Settings page.');
    } finally {
      setAiLoading(false);
    }
  };

  // Квадратный экспорт — через ExportModal (кадр из текущего zoom/pan)
  const handleOpenExport = () => {
    setShowExportModal(true);
  };

  const handleResetCamera = () => {
    if (typeof (window as any).resetMandalaCanvasViewport === 'function') {
      (window as any).resetMandalaCanvasViewport();
    }
  };

  // Reordering array operations
  const layers = templateSettings.guideLayerOrder || [
    'grid', 'rings', 'petals', 'spiral', 'lissajous', 'cardioid', 'spirograph', 'superellipse', 'maurer'
  ];

  const toggleLayer = (layerId: string) => {
    const meta = LAYER_METADATA[layerId];
    if (meta) {
      const key = meta.key;
      setTemplateSettings({
        ...templateSettings,
        [key]: !templateSettings[key]
      });
    }
  };

  const moveLayer = (index: number, direction: 'up' | 'down') => {
    const newOrder = [...layers];
    const targetIdx = direction === 'up' ? index - 1 : index + 1;
    if (targetIdx >= 0 && targetIdx < newOrder.length) {
      const temp = newOrder[index];
      newOrder[index] = newOrder[targetIdx];
      newOrder[targetIdx] = temp;
      setTemplateSettings({
        ...templateSettings,
        guideLayerOrder: newOrder
      });
    }
  };

  // HUD host: только «полоса холста» между left/right deck (не поверх панелей)
  const hudHostRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const host = hudHostRef.current;
    if (!host) return;
    perfHud.attach(host);
    perfHud.applyPrefs(loadCanvasPrefs());
    return () => perfHud.detach();
  }, [leftCollapsed, rightCollapsed]);

  return (
    <div className="absolute inset-0 flex items-center justify-center z-0 pt-11 overflow-hidden">
      
      {/* Canvas Area */}
      <div className="absolute inset-0 z-0 flex items-center justify-center">
        <CanvasRenderer 
          strokes={strokes}
          addStroke={addStroke}
          brushSettings={brushSettings} 
          templateSettings={templateSettings} 
          drawingLayers={drawingLayers}
          canvasSize={canvasSize}
        />
      </div>

      {/* Зона холста между панелями — сюда монтируется Perf HUD */}
      <div
        ref={hudHostRef}
        className={`pointer-events-none fixed top-11 bottom-0 z-[25] ${
          leftCollapsed ? 'left-0' : 'left-60'
        } ${rightCollapsed ? 'right-0' : 'right-60'}`}
        aria-hidden
      />

      {/* Floating Viewport Reset Tool */}
      <button
        onClick={handleResetCamera}
        className={`ui-float-pill fixed bottom-16 ${leftCollapsed ? 'left-4' : 'left-64'} px-3 py-1.5 rounded-full flex items-center gap-1.5 transition-all cursor-pointer z-20 font-manrope text-[10px] font-bold tracking-wide shadow-md`}
        title="Reset zoom & pan camera to center"
      >
        <span className="material-symbols-outlined text-[13px]">center_focus_strong</span>
        Recenter View
      </button>

      {/* LEFT SIDEBAR: Lattice Guide Layer Manager */}
      <nav 
        className={`ui-panel fixed left-0 top-11 bottom-0 w-60 border-r z-30 flex flex-col transition-transform duration-300 ease-in-out ${leftCollapsed ? '-translate-x-full' : ''}`}
      >
        <div className="flex flex-col h-full overflow-y-auto px-3.5 py-3.5 scrollbar-thin space-y-3.5">
          
          <div className="flex items-center justify-between border-b border-white/5 pb-1.5">
            <span className="font-manrope text-xs font-semibold text-white tracking-wide">Lattice Guides</span>
            <span className="text-[9px] text-slate-500 font-manrope uppercase font-bold tracking-wider">Left Deck</span>
          </div>

          {/* Snapping Preference */}
          <div className="bg-white/5 rounded-lg p-2 border border-white/5">
            <ToggleSwitch 
              checked={templateSettings.snapToGuides}
              onChange={val => setTemplateSettings({ ...templateSettings, snapToGuides: val })}
              label="Snap Drawing to Lattice"
            />
          </div>

          {/* Interactive Layer Manager */}
          <div className="bg-white/5 rounded-lg p-2.5 border border-white/5 space-y-2 flex-1 flex flex-col min-h-[220px]">
            <div className="flex items-center justify-between border-b border-white/5 pb-1.5 mb-0.5">
              <span className="font-manrope text-[9px] text-secondary font-bold uppercase tracking-widest">Active Rail Layers</span>
              <span className="text-[9px] text-slate-500 font-manrope font-semibold">{templateSettings.segments} Sectors</span>
            </div>

            <div className="space-y-1 overflow-y-auto scrollbar-thin pr-0.5 flex-1">
              {layers.map((layerId, idx) => {
                const meta = LAYER_METADATA[layerId];
                if (!meta) return null;
                const isVisible = !!templateSettings[meta.key];
                

                return (
                  <div 
                    key={layerId} 
                    className={`flex items-center justify-between p-1.5 rounded transition-all border relative group ${
                      isVisible 
                        ? 'bg-white/5 border-white/5 text-slate-200' 
                        : 'bg-black/35 border-transparent text-slate-500 opacity-50'
                    }`}
                  >
                    <div className="flex items-center gap-1.5 min-w-0 pr-12 flex-1">
                      {/* Visibility Eye Icon Toggle */}
                      <button
                        onClick={() => toggleLayer(layerId)}
                        className={`p-0.5 rounded hover:bg-white/5 transition-colors cursor-pointer ${
                          isVisible ? 'text-secondary' : 'text-slate-500'
                        }`}
                        title={isVisible ? "Hide Layer" : "Show Layer"}
                      >
                        <span className="material-symbols-outlined text-[12px] block">
                          {isVisible ? 'visibility' : 'visibility_off'}
                        </span>
                      </button>
                      
                      {/* Micro-Lattice SVG Thumbnail */}
                      <div className={`flex-shrink-0 p-0.5 rounded bg-black/40 border border-white/10 ${isVisible ? 'text-secondary' : 'text-slate-600'}`}>
                        {meta.svg}
                      </div>
                      
                      <span className="font-manrope text-[10px] truncate select-none flex-1 min-w-0">
                        {meta.label}
                      </span>
                    </div>

                    {/* Actions: Reorder & Convert (Only visible on hover) */}
                    <div className="absolute right-1 top-1/2 -translate-y-1/2 ui-panel-solid border px-1 py-0.5 rounded flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-200 shadow-xl z-10">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleConvertGuideToStrokes(layerId);
                        }}
                        className="p-0.5 rounded hover:bg-white/10 text-slate-400 hover:text-secondary transition-colors cursor-pointer flex items-center justify-center w-4.5 h-4.5"
                        title="Convert vector rail to editable drawing layer"
                      >
                        <span className="material-symbols-outlined text-[11px] block">layers</span>
                      </button>
                      <button
                        disabled={idx === 0}
                        onClick={(e) => {
                          e.stopPropagation();
                          moveLayer(idx, 'up');
                        }}
                        className="p-0.5 rounded hover:bg-white/10 text-slate-400 hover:text-white disabled:opacity-10 transition-colors cursor-pointer flex items-center justify-center w-4.5 h-4.5"
                        title="Move Layer Up"
                      >
                        <span className="material-symbols-outlined text-[11px] block">keyboard_arrow_up</span>
                      </button>
                      <button
                        disabled={idx === layers.length - 1}
                        onClick={(e) => {
                          e.stopPropagation();
                          moveLayer(idx, 'down');
                        }}
                        className="p-0.5 rounded hover:bg-white/10 text-slate-400 hover:text-white disabled:opacity-10 transition-colors cursor-pointer flex items-center justify-center w-4.5 h-4.5"
                        title="Move Layer Down"
                      >
                        <span className="material-symbols-outlined text-[11px] block">keyboard_arrow_down</span>
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
            
            <div className="pt-1.5 border-t border-white/5">
              <ToggleSwitch 
                checked={templateSettings.mirror}
                onChange={val => setTemplateSettings({ ...templateSettings, mirror: val })}
                label="Mirror Reflections"
              />
            </div>
          </div>

          {/* Drawing Layers ( Photoshop-style Layers ) */}
          <div className="bg-white/5 rounded-lg p-2.5 border border-white/5 space-y-2 flex flex-col min-h-[160px] max-h-[220px]">
            <div className="flex items-center justify-between border-b border-white/5 pb-1 mb-0.5">
              <span className="font-manrope text-[9px] text-secondary font-bold uppercase tracking-widest">Drawing Layers</span>
              <button 
                onClick={handleCreateDrawingLayer}
                className="hover:text-secondary text-slate-400 p-0.5 rounded hover:bg-white/5 transition-colors cursor-pointer flex items-center justify-center"
                title="Create New Drawing Layer"
              >
                <span className="material-symbols-outlined text-[13px] block">add</span>
              </button>
            </div>

            <div className="space-y-1 overflow-y-auto scrollbar-thin pr-0.5 flex-1 text-[10px]">
              {drawingLayers.map((layer, idx) => {
                const isSelected = activeLayerId === layer.id;
                const isVisible = layer.visible;
                return (
                  <div 
                    key={layer.id}
                    onClick={() => setActiveLayerId(layer.id)}
                    className={`flex items-center justify-between p-1.5 rounded transition-all border cursor-pointer relative group ${
                      isSelected 
                        ? 'bg-secondary/10 border-secondary/35 text-white' 
                        : 'bg-white/5 border-transparent text-slate-300 hover:bg-white/10'
                    }`}
                  >
                    <div className="flex items-center gap-1.5 min-w-0 flex-1 pr-16">
                      {/* Hide/Show Eye Button */}
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleToggleDrawingLayerVisibility(layer.id);
                        }}
                        className={`p-0.5 rounded hover:bg-white/10 transition-colors cursor-pointer ${
                          isVisible ? 'text-secondary' : 'text-slate-500'
                        }`}
                        title={isVisible ? "Hide Layer strokes" : "Show Layer strokes"}
                      >
                        <span className="material-symbols-outlined text-[12px] block">
                          {isVisible ? 'visibility' : 'visibility_off'}
                        </span>
                      </button>

                      {/* Inline Renamer Text / Input */}
                      <input 
                        type="text"
                        value={layer.name}
                        onClick={(e) => e.stopPropagation()}
                        onChange={(e) => handleRenameDrawingLayer(layer.id, e.target.value)}
                        className="bg-transparent border-none text-[10px] font-manrope text-slate-200 focus:outline-none focus:bg-black/60 focus:px-1 rounded truncate flex-1 min-w-0"
                        placeholder="Layer Name"
                      />
                    </div>

                    {/* Actions: Reorder & Delete (Only visible on hover) */}
                    <div className="absolute right-1 top-1/2 -translate-y-1/2 ui-panel-solid border px-1 py-0.5 rounded flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-200 shadow-xl z-10">
                      <button
                        disabled={idx === 0}
                        onClick={(e) => {
                          e.stopPropagation();
                          handleMoveDrawingLayer(idx, 'up');
                        }}
                        className="p-0.5 rounded hover:bg-white/10 text-slate-400 hover:text-white disabled:opacity-10 transition-colors cursor-pointer flex items-center justify-center w-4.5 h-4.5"
                        title="Move Layer Up"
                      >
                        <span className="material-symbols-outlined text-[11px] block">keyboard_arrow_up</span>
                      </button>
                      <button
                        disabled={idx === drawingLayers.length - 1}
                        onClick={(e) => {
                          e.stopPropagation();
                          handleMoveDrawingLayer(idx, 'down');
                        }}
                        className="p-0.5 rounded hover:bg-white/10 text-slate-400 hover:text-white disabled:opacity-10 transition-colors cursor-pointer flex items-center justify-center w-4.5 h-4.5"
                        title="Move Layer Down"
                      >
                        <span className="material-symbols-outlined text-[11px] block">keyboard_arrow_down</span>
                      </button>
                      <button
                        disabled={drawingLayers.length <= 1}
                        onClick={(e) => {
                          e.stopPropagation();
                          handleDeleteDrawingLayer(layer.id);
                        }}
                        className="p-0.5 rounded hover:bg-white/10 text-slate-500 hover:text-red-400 disabled:opacity-10 transition-colors cursor-pointer flex items-center justify-center w-4.5 h-4.5"
                        title="Delete Layer & Strokes"
                      >
                        <span className="material-symbols-outlined text-[11px] block">delete</span>
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>

        {/* Toggle Left Sidebar */}
        <button 
          onClick={() => setLeftCollapsed(!leftCollapsed)}
          className="absolute top-1/2 -right-5 -translate-y-1/2 w-5 h-12 ui-panel border border-l-0 rounded-r-lg backdrop-blur-2xl flex items-center justify-center text-slate-500 hover:text-white hover:bg-white/5 transition-colors cursor-pointer shadow-md"
        >
          <span className="material-symbols-outlined text-[15px]">{leftCollapsed ? 'chevron_right' : 'chevron_left'}</span>
        </button>
      </nav>

      {/* RIGHT SIDEBAR: Brush Drawing Tools & Audio */}
      <nav 
        className={`ui-panel fixed right-0 top-11 bottom-0 w-60 border-l z-30 flex flex-col transition-transform duration-300 ease-in-out ${rightCollapsed ? 'translate-x-full' : ''}`}
      >
        <div className="flex flex-col h-full overflow-y-auto px-3.5 py-3.5 scrollbar-thin space-y-3.5">
          
          <div className="flex items-center justify-between border-b border-white/5 pb-1.5">
            <span className="font-manrope text-xs font-semibold text-white tracking-wide">Brush Studio</span>
            <span className="text-[9px] text-slate-500 font-manrope uppercase font-bold tracking-wider">Right Deck</span>
          </div>

          {/* Section: Brush Presets */}
          <div>
            <span className="font-manrope text-[9px] text-slate-500 uppercase tracking-widest block mb-1.5">Instruments</span>
            <div className="grid grid-cols-2 gap-1.5">
              {[
                { id: 'vector', icon: 'brush', label: 'Classic' },
                { id: 'dotting', icon: 'blur_on', label: 'Dotting' },
                { id: 'glow', icon: 'flare', label: 'Neon Glow' },
                { id: 'pixel', icon: 'grid_on', label: 'Pixel' },
                { id: 'sketch', icon: 'gesture', label: 'Sketch' },
                { id: 'rainbow', icon: 'looks', label: 'Rainbow' },
                { id: 'eraser', icon: 'ink_eraser', label: 'Eraser' },
                { id: 'airbrush', icon: 'grain', label: 'Airbrush' },
                { id: 'blur', icon: 'blur_circular', label: 'Blur Blending' },
                { id: 'smudge', icon: 'swipe', label: 'Smudge Smear' },
                { id: 'stretch', icon: 'transform', label: 'Stretch Warp' },
                { id: 'bleach', icon: 'opacity', label: 'Bleach Sat' }
              ].map(tool => (
                <button
                  key={tool.id}
                  onClick={() => setBrushSettings({ ...brushSettings, type: tool.id as any })}
                  className={`flex items-center gap-1.5 p-1.5 rounded border text-left transition-all ${
                    brushSettings.type === tool.id
                      ? 'bg-secondary/15 border-secondary text-secondary glow-accent-soft font-semibold'
                      : 'bg-white/5 border-white/5 text-slate-400 hover:text-white hover:bg-white/10'
                  }`}
                >
                  <span className="material-symbols-outlined text-[13px]">{tool.icon}</span>
                  <span className="font-manrope text-[10px] truncate">{tool.label}</span>
                </button>
              ))}
            </div>
          </div>

          {/* Dotting specific options */}
          {brushSettings.type === 'dotting' && (
            <div className="bg-white/5 rounded p-2.5 border border-white/5 space-y-1">
              <span className="font-manrope text-[9px] text-slate-500 uppercase tracking-widest block">Dot Size Profile</span>
              <div className="grid grid-cols-2 gap-1">
                {[
                  { id: 'sine', label: 'Sine Wave' },
                  { id: 'growing', label: 'Growing' },
                  { id: 'shrinking', label: 'Shrinking' },
                  { id: 'fixed', label: 'Fixed Size' }
                ].map(prof => (
                  <button
                    key={prof.id}
                    onClick={() => setBrushSettings({ ...brushSettings, dotProfile: prof.id as any })}
                    className={`py-1 px-1 rounded font-manrope text-[9px] font-medium border text-center transition-all ${
                      (brushSettings.dotProfile || 'sine') === prof.id
                        ? 'bg-secondary/10 border-secondary text-secondary font-semibold'
                        : 'bg-black/30 border-white/5 text-slate-400 hover:text-white'
                    }`}
                  >
                    {prof.label}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Sliders: Size & Opacity */}
          <div className="space-y-2.5 bg-white/5 p-2.5 rounded-lg border border-white/5">
            <div>
              <div className="flex justify-between items-center mb-0.5 text-[10px] font-manrope">
                <span className="text-slate-400">Brush Size</span>
                <span className="text-white font-mono">{brushSettings.size}px</span>
              </div>
              <input 
                type="range" min="1" max="100" value={brushSettings.size}
                onChange={e => setBrushSettings({...brushSettings, size: parseInt(e.target.value)})}
                className="w-full h-1 bg-white/10 rounded-lg appearance-none cursor-pointer accent-secondary"
              />
            </div>

            <div>
              <div className="flex justify-between items-center mb-0.5 text-[10px] font-manrope">
                <span className="text-slate-400">Brush Opacity</span>
                <span className="text-white font-mono">{brushSettings.opacity}%</span>
              </div>
              <input 
                type="range" min="10" max="100" value={brushSettings.opacity}
                onChange={e => setBrushSettings({...brushSettings, opacity: parseInt(e.target.value)})}
                className="w-full h-1 bg-white/10 rounded-lg appearance-none cursor-pointer accent-secondary"
              />
            </div>
          </div>

          {/* Section: Audio Player */}
          <div className="border-t border-white/5 pt-2.5">
            <div className="flex items-center justify-between mb-1">
              <span className="font-manrope text-[9px] text-slate-500 uppercase tracking-widest">Ambient Music</span>
              <button 
                onClick={handleToggleMute} 
                className="text-slate-400 hover:text-white p-0.5 transition-colors outline-none cursor-pointer"
                title={isMuted ? "Unmute" : "Mute"}
              >
                <span className="material-symbols-outlined text-[15px]">
                  {isMuted ? 'volume_off' : 'volume_up'}
                </span>
              </button>
            </div>

            <div className="bg-black/30 border border-white/5 rounded-lg p-2 space-y-2">
              <div className="flex items-center gap-2">
                <button
                  onClick={handleToggleSound}
                  className={`w-6 h-6 rounded-full flex items-center justify-center transition-all cursor-pointer ${
                    isPlayingSound 
                      ? 'bg-secondary text-on-secondary glow-accent'
                      : 'bg-white/10 text-white hover:bg-white/15'
                  }`}
                >
                  <span className="material-symbols-outlined text-[15px]">
                    {isPlayingSound ? 'pause' : 'play_arrow'}
                  </span>
                </button>
                <div className="flex-1">
                  <select
                    value={soundMood}
                    onChange={e => handleChangeSoundMood(e.target.value as any)}
                    className="w-full bg-black/60 border border-white/10 rounded px-1.5 py-0.5 text-[10px] text-white focus:outline-none focus:border-secondary font-manrope cursor-pointer"
                  >
                    <option value="cosmic">Cosmic Swell</option>
                    <option value="forest">Forest Zen</option>
                    <option value="meditation">Deep Meditation</option>
                    <option value="wind">Aether Wind</option>
                  </select>
                </div>
              </div>

              <div className="space-y-0.5">
                <input
                  type="range" min="0" max="1" step="0.05" value={soundVolume}
                  onChange={e => handleVolumeChange(parseFloat(e.target.value))}
                  className="w-full h-1 bg-white/10 rounded-lg appearance-none cursor-pointer accent-secondary"
                />
              </div>
            </div>
          </div>
          
          {/* Mind & Mood AI button */}
          <button 
            onClick={() => setShowAiModal(true)}
            className="w-full bg-secondary text-on-secondary font-bold py-2 rounded-lg glow-accent-soft hover:scale-[1.02] active:scale-98 transition-all flex items-center justify-center gap-1.5 cursor-pointer font-manrope text-[10px] tracking-wide uppercase"
          >
            <span className="material-symbols-outlined text-[13px] animate-pulse">psychology</span>
            Mind & Mood AI
          </button>

        </div>

        {/* Toggle Right Sidebar */}
        <button 
          onClick={() => setRightCollapsed(!rightCollapsed)}
          className="absolute top-1/2 -left-5 -translate-y-1/2 w-5 h-12 ui-panel border border-r-0 rounded-l-lg backdrop-blur-2xl flex items-center justify-center text-slate-500 hover:text-white hover:bg-white/5 transition-colors cursor-pointer shadow-md"
        >
          <span className="material-symbols-outlined text-[15px]">{rightCollapsed ? 'chevron_left' : 'chevron_right'}</span>
        </button>
      </nav>

      <ColorPalettePanel
        color={brushSettings.color}
        onChange={hex => setBrushSettings({ ...brushSettings, color: hex })}
        pos={colorPos}
        onPosChange={setColorPos}
      />

      {/* Bottom Control Bar — theme tokens (readable on all themes) */}
      <nav className="ui-float-bar fixed bottom-3 left-1/2 -translate-x-1/2 rounded-full z-50 px-4 py-2 flex items-center gap-1">
        <button
          type="button"
          onClick={onUndo}
          disabled={!canUndo}
          className="ui-bar-btn"
          title="Undo"
        >
          <span className="material-symbols-outlined text-[17px]">undo</span>
          <span className="font-manrope text-[10px] font-semibold tracking-wide">Undo</span>
        </button>

        <button
          type="button"
          onClick={onRedo}
          disabled={!canRedo}
          className="ui-bar-btn"
          title="Redo"
        >
          <span className="material-symbols-outlined text-[17px]">redo</span>
          <span className="font-manrope text-[10px] font-semibold tracking-wide">Redo</span>
        </button>

        <button type="button" onClick={onClear} className="ui-bar-btn ui-bar-btn-danger" title="Clear">
          <span className="material-symbols-outlined text-[17px]">delete_sweep</span>
          <span className="font-manrope text-[10px] font-semibold tracking-wide">Clear</span>
        </button>

        <div className="ui-bar-divider" />

        <button
          type="button"
          onClick={onRequestResizeCanvas}
          className="ui-bar-chip"
          title="Change canvas resolution (quality)"
        >
          <span className="material-symbols-outlined text-[13px]">photo_size_select_large</span>
          {canvasSize}²
        </button>
        <button
          type="button"
          onClick={onFitCanvasToContent}
          className="ui-bar-chip"
          title="Fit view to drawing (camera only — no resolution change)"
        >
          <span className="material-symbols-outlined text-[13px]">fit_screen</span>
          Fit
        </button>
        <button
          type="button"
          onClick={handleOpenExport}
          className="ui-bar-chip ui-bar-chip-accent"
          title="Square export from current view"
        >
          <span className="material-symbols-outlined text-[13px]">crop_square</span>
          Export
        </button>
      </nav>

      <ExportModal
        open={showExportModal}
        onClose={() => setShowExportModal(false)}
        templateSettings={templateSettings}
        projectCanvasSize={canvasSize}
      />

      {/* AI Assistant Modal */}
      {showAiModal && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-md flex items-center justify-center z-50 animate-fade-in p-4">
          <div className="ui-modal border rounded-2xl w-full max-w-lg p-6 relative shadow-2xl">
            <button 
              onClick={() => { setShowAiModal(false); setAiPrompt(''); setAiFeedback(''); }} 
              className="absolute top-4 right-4 text-slate-400 hover:text-white transition-colors cursor-pointer"
            >
              <span className="material-symbols-outlined text-[20px]">close</span>
            </button>

            <h3 className="font-manrope text-[16px] font-semibold text-white mb-0.5 flex items-center gap-1.5">
              <span className="material-symbols-outlined text-secondary text-[20px]">psychology</span>
              Mind & Mood AI Hub
            </h3>
            <p className="font-manrope text-slate-400 text-[10.5px] mb-4">
              Let the neural net analyze your current mood or thoughts and dynamically pre-configure a sacred geometric canvas, matching color palettes, and ambient soundscapes.
            </p>

            <div className="space-y-4">
              <div className="relative">
                <textarea
                  value={aiPrompt}
                  onChange={e => setAiPrompt(e.target.value)}
                  placeholder="Describe your current state or a prompt (e.g. 'I am feeling overwhelmed, I need a slow calm forest canvas with green colors', or 'Energetic starlight session')"
                  className="w-full bg-black/40 border border-white/10 rounded-xl p-3 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-secondary h-24 resize-none pr-10 font-manrope"
                />
                
                <button
                  type="button"
                  onClick={startListening}
                  className={`absolute right-3 bottom-3 p-1.5 rounded-full transition-all cursor-pointer ${
                    isListening
                      ? 'bg-red-500 text-white animate-pulse'
                      : 'bg-white/5 text-slate-400 hover:text-white hover:bg-white/10'
                  }`}
                  title="Speak your mood (Voice control)"
                >
                  <span className="material-symbols-outlined text-[16px]">
                    {isListening ? 'mic' : 'mic_none'}
                  </span>
                </button>
              </div>

              {aiFeedback && (
                <div className="bg-white/5 border border-white/5 rounded-xl p-3 text-[11px] font-manrope text-slate-300 leading-normal max-h-32 overflow-y-auto scrollbar-thin">
                  <span className="font-semibold text-secondary block mb-0.5">AI Recommendation:</span>
                  {aiFeedback}
                </div>
              )}

              <div className="flex justify-end gap-2 pt-1.5">
                <button
                  onClick={() => { setShowAiModal(false); setAiPrompt(''); setAiFeedback(''); }}
                  className="px-4 py-2 rounded-lg font-manrope text-[11px] font-semibold text-slate-400 hover:text-white hover:bg-white/5 transition-colors border border-transparent cursor-pointer"
                >
                  Close
                </button>
                <button
                  onClick={handleGenerateAiMood}
                  disabled={aiLoading || !aiPrompt.trim()}
                  className={`px-5 py-2 rounded-lg font-manrope text-[11px] font-semibold flex items-center gap-1.5 shadow-lg transition-all cursor-pointer ${
                    aiLoading || !aiPrompt.trim()
                      ? 'bg-slate-800 text-slate-500 cursor-not-allowed border border-white/5'
                      : 'bg-secondary text-on-secondary hover:bg-secondary/90 hover:scale-105 active:scale-95'
                  }`}
                >
                  {aiLoading ? (
                    <>
                      <div className="w-3 h-3 border-2 border-on-secondary border-t-transparent rounded-full animate-spin"></div>
                      Generating Setup...
                    </>
                  ) : (
                    <>
                      <span className="material-symbols-outlined text-[14px]">draw</span>
                      Configure Studio
                    </>
                  )}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
