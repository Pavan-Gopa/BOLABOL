export type ViewState = 'workspace' | 'templates' | 'gallery' | 'settings';

export type BrushType = 'vector' | 'dotting' | 'glow' | 'pixel' | 'sketch' | 'rainbow' | 'eraser' | 'smudge' | 'stretch' | 'bleach' | 'airbrush' | 'blur';

export type DotProfile = 'sine' | 'growing' | 'shrinking' | 'fixed';

export interface BrushSettings {
  type: BrushType;
  size: number;
  opacity: number;
  flow: number;
  color: string;
  dotProfile?: DotProfile; // Smart dotting shape profiles
}

export interface TemplateSettings {
  segments: number;
  radius: number;
  rotation: number;
  layers: number; // Rings count
  mirror: boolean; // Dihedral symmetry
  
  // Visibility of guidelines
  showGridLines: boolean;
  showRings: boolean;
  showGridInExport: boolean;
  snapToGuides: boolean; // Snapping to concentric rings or segment lines

  // Rose Curve (Petals)
  petalLength: number; // a
  petalFrequency: number; // k
  showPetals: boolean;

  // Logarithmic Spiral
  spiralGrowth: number; // b
  spiralScale: number; // a (base starting size)
  spiralArms: number; // count of spiral arms
  showSpiral: boolean;

  // Lissajous Curve: x = a*cos(freqX * t + phase), y = b*sin(freqY * t)
  showLissajous: boolean;
  lissFreqX: number;
  lissFreqY: number;
  lissPhase: number; // in degrees (0-360)

  // Cardioid/Limacon: r = a + b * cos(theta)
  showCardioid: boolean;
  cardioidA: number; // baseline size
  cardioidB: number; // indentation factor

  // Ring Modulation (Ripple waves)
  ringModulationAmp: number; // Amplitude (0-40%)
  ringModulationFreq: number; // Wave frequency lobes (2-24)

  // Spirograph (Epicycloid / Hypocycloid)
  showSpirograph: boolean;
  spiroR: number; // Fixed radius
  spiro_r: number; // Rolling radius
  spiroD: number; // Pen offset
  spiroType: 'epi' | 'hypo';
  spiroRotations: number; // Count of 2*PI rotations to complete the gear loop

  // Superellipse (Lame Curve)
  showSuperellipse: boolean;
  superellipseN: number; // Power (0.1 to 8.0)
  superellipseA: number; // H-radius scale
  superellipseB: number; // V-radius scale

  // Maurer Rose
  showMaurer: boolean;
  maurerN: number; // Rose petal factor
  maurerD: number; // Degree step factor (e.g. 29 or 71)

  // Layer ordering list
  guideLayerOrder: string[];
}

export interface DrawingLayer {
  id: string;
  name: string;
  visible: boolean;
}

export interface ProjectMeta {
  id: string;
  name: string;
  updatedAt: number;
  previewDataUrl?: string;
  templateSettings: TemplateSettings;
  strokes: Stroke[];
  drawingLayers?: DrawingLayer[];
  activeLayerId?: string;
  /**
   * Export / project quality (square px). Independent of drawable world size.
   * Strokes live in DRAW_WORLD_SIZE coordinates (see projectCanvas.ts).
   */
  canvasSize?: number;
  /** Set when strokes are stored in fixed draw-world coords (migration flag). */
  drawWorldSize?: number;
}

export interface Point {
  x: number;
  y: number;
  pressure?: number;
}

export interface Stroke {
  id?: string; // Уникальный идентификатор для delta-based истории (действие remove)
  points: Point[];
  settings: BrushSettings;
  layerId?: string; // Links this stroke to a specific drawing layer
  rasterized?: boolean; // M2: effect-штрих запечён в EffectLayer (не volatile re-draw). Опционально — не ломает сериализацию.
}
