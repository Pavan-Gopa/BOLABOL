import React, { useRef, useEffect, useState, useCallback, useMemo } from 'react';
import { Stroke, Point, BrushSettings, TemplateSettings, DrawingLayer } from '../types';
import { computeAllGuides, renderGuides } from '../utils/guides';
import { RenderScheduler } from '../utils/RenderScheduler';
import { PathBatcher } from '../utils/PathBatcher';
import { SpatialHash } from '../utils/SpatialHash';
import { isCacheableStroke } from '../utils/StrokeBaker';
import {
  WorldScene,
  getMandalaWorld,
  MandalaExportSnapshot,
  getWorldBakeQuality
} from '../utils/WorldScene';
import {
  DRAW_WORLD_SIZE,
  cameraFitToContent
} from '../utils/projectCanvas';
import { perfLog, perfTime, perfTimeAsync } from '../utils/perfLog';
import { SmudgeShader } from '../utils/SmudgeShader';
import { perfHud } from '../utils/PerfHud';
import {
  loadCanvasPrefs,
  workspaceFillColor,
  CAMERA_ZOOM_MIN,
  CAMERA_ZOOM_MAX,
  CanvasPrefs
} from '../utils/canvasPrefs';

export type MandalaExportRenderOpts = {
  outSize: number;
  centerX: number;
  centerY: number;
  side: number;
  /** true → transparent PNG (no background fill, no color-key punch) */
  transparent: boolean;
  bg: string | null;
  bakeGrid: boolean;
  templateSettings: TemplateSettings;
};

declare global {
  interface Window {
    resetMandalaCanvasViewport?: () => void;
    /** Frame camera so all strokes are visible (no world resize). */
    fitMandalaContentToView?: () => boolean;
    /** Актуальный snapshot мира+камеры для квадратного экспорта */
    getMandalaExportSnapshot?: () => MandalaExportSnapshot | null;
    /** Принудительно синхронизировать bake перед экспортом */
    flushMandalaScene?: () => void;
    /**
     * High-quality export: re-draw strokes into outSize×outSize at full resolution.
     * Avoids upscaling the interactive bake buffer and avoids punch-to-alpha hole artifacts.
     */
    renderMandalaExportSquare?: (opts: MandalaExportRenderOpts) => HTMLCanvasElement | null;
  }
}

interface CanvasRendererProps {
  strokes: Stroke[];
  addStroke: (s: Stroke) => void;
  brushSettings: BrushSettings;
  templateSettings: TemplateSettings;
  drawingLayers: DrawingLayer[];
  /** Export quality (square). Drawable world is always DRAW_WORLD_SIZE. */
  canvasSize: number;
}

export default function CanvasRenderer({
  strokes,
  addStroke,
  brushSettings,
  templateSettings,
  drawingLayers,
  canvasSize
}: CanvasRendererProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const dynamicCanvasRef = useRef<HTMLCanvasElement>(null);
  
  // Scratch canvas ref for smudge and stretch tools
  const scratchCanvasRef = useRef<HTMLCanvasElement | null>(null);
  
  // Viewport (окно), не мир. Мир — всегда квадрат больше окна (getMandalaWorld).
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 });

  const mandalaWorld = useMemo(
    () => getMandalaWorld(dimensions.width, dimensions.height, DRAW_WORLD_SIZE),
    [dimensions.width, dimensions.height]
  );

  // Настройки холста/HUD (Settings → localStorage)
  const [canvasPrefs, setCanvasPrefs] = useState<CanvasPrefs>(() => loadCanvasPrefs());
  const [bakeQ, setBakeQ] = useState(() => getWorldBakeQuality());
  useEffect(() => {
    const onPrefs = (e: Event) => {
      const detail = (e as CustomEvent<CanvasPrefs>).detail;
      setCanvasPrefs(detail ? { ...detail } : loadCanvasPrefs());
    };
    const onQuality = () => {
      setBakeQ(getWorldBakeQuality());
      worldSceneRef.current?.invalidate();
      schedulerRef.current?.schedule(() => drawAllStrokesRef.current());
    };
    window.addEventListener('mandala-prefs-changed', onPrefs as EventListener);
    window.addEventListener('mandala-quality-changed', onQuality);
    window.addEventListener('mandala-app-settings', onQuality);
    return () => {
      window.removeEventListener('mandala-prefs-changed', onPrefs as EventListener);
      window.removeEventListener('mandala-quality-changed', onQuality);
      window.removeEventListener('mandala-app-settings', onQuality);
    };
  }, []);

  const fillColor = workspaceFillColor(canvasPrefs);

  // Lattice scale follows export quality (working mandala disk), centered in draw world
  const latticeRadius = useMemo(() => {
    return (Math.max(256, canvasSize) / 2) * 0.85;
  }, [canvasSize]);

  // 2D Camera Viewport navigation — pan/zoom live in refs (no React re-render per move, M1).
  const zoomRef = useRef(1.0);
  const panRef = useRef({ x: 0, y: 0 });
  const panStartRef = useRef({ x: 0, y: 0 });
  // Чтобы при первом resize выставить pan в центр квадратного мира
  const panInitializedRef = useRef(false);

  // Drawing interaction state — refs (M1): no per-move React re-render.
  const isDrawingRef = useRef(false);
  const currentPointsRef = useRef<Point[]>([]);
  const hoverPointRef = useRef<Point | null>(null);
  const lastRawPointRef = useRef<Point | null>(null);

  // UI-only state: toggles at gesture boundaries (not per move), needed for cursor styling.
  const [isSpacePressed, setIsSpacePressed] = useState(false);
  const [isPanning, setIsPanning] = useState(false);

  // Планировщик рендера на requestAnimationFrame (устраняет множественные рендеры за кадр — узкое место #6)
  const schedulerRef = useRef<RenderScheduler | null>(null);
  if (schedulerRef.current === null) schedulerRef.current = new RenderScheduler();

  // Актуальные draw-функции для wheel/listeners с пустым deps (иначе stale closure:
  // zoom двигает только guides на overlay, а main canvas «застывает»).
  const drawAllStrokesRef = useRef<() => void>(() => {});
  const drawOverlayRef = useRef<() => void>(() => {});

  // Пространственный хеш для ускорения snapping к направляющим (узкое место #4)
  const snapHashRef = useRef<SpatialHash | null>(null);
  if (snapHashRef.current === null) snapHashRef.current = new SpatialHash(20);

  // Единый world-space растр сцены (pan/zoom = blit; rebuild только при смене strokes).
  const worldSceneRef = useRef<WorldScene | null>(null);
  if (worldSceneRef.current === null) worldSceneRef.current = new WorldScene();
  /** Cancels in-flight async full rebuilds when a newer sync arrives. */
  const rebuildGenRef = useRef(0);
  const rebuildInFlightRef = useRef(false);
  const rebuildTargetSigRef = useRef('');

  // WebGL2 только для live smudge/stretch. Blur — всегда Canvas2D (WebGL ROI давал «квадраты»).
  const webglSupportedRef = useRef<boolean>((() => {
    try {
      return typeof document !== 'undefined' && !!document.createElement('canvas').getContext('webgl2');
    } catch {
      return false;
    }
  })());
  const smudgeShaderRef = useRef<SmudgeShader | null>(null);

  // Camera reset + fit + export hooks
  useEffect(() => {
    window.resetMandalaCanvasViewport = () => {
      zoomRef.current = 1.0;
      const w = getMandalaWorld(
        containerRef.current?.clientWidth || dimensions.width,
        containerRef.current?.clientHeight || dimensions.height,
        DRAW_WORLD_SIZE
      );
      panRef.current = { ...w.defaultPan };
      schedulerRef.current?.schedule(() => drawAllStrokesRef.current());
      schedulerRef.current?.schedule(() => drawOverlayRef.current());
    };

    window.fitMandalaContentToView = () => {
      const viewW = containerRef.current?.clientWidth || dimensions.width;
      const viewH = containerRef.current?.clientHeight || dimensions.height;
      const cam = cameraFitToContent(
        strokes,
        {
          segments: templateSettings.segments,
          mirror: !!templateSettings.mirror,
          rotation: templateSettings.rotation || 0
        },
        DRAW_WORLD_SIZE,
        viewW,
        viewH
      );
      if (!cam) return false;
      zoomRef.current = cam.zoom;
      panRef.current = { ...cam.pan };
      schedulerRef.current?.schedule(() => drawAllStrokesRef.current());
      schedulerRef.current?.schedule(() => drawOverlayRef.current());
      return true;
    };

    window.flushMandalaScene = () => {
      drawAllStrokesRef.current();
    };

    window.getMandalaExportSnapshot = (): MandalaExportSnapshot | null => {
      const scene = worldSceneRef.current;
      if (!scene || dimensions.width <= 0 || mandalaWorld.size <= 0) return null;
      drawAllStrokesRef.current();
      return {
        worldScene: scene,
        viewW: dimensions.width,
        viewH: dimensions.height,
        pan: { ...panRef.current },
        zoom: zoomRef.current,
        worldSize: mandalaWorld.size,
        cx: mandalaWorld.cx,
        cy: mandalaWorld.cy,
        latticeRadius
      };
    };

    return () => {
      delete window.resetMandalaCanvasViewport;
      delete window.fitMandalaContentToView;
      delete window.getMandalaExportSnapshot;
      delete window.flushMandalaScene;
    };
  }, [dimensions.width, dimensions.height, mandalaWorld, canvasSize, latticeRadius, strokes, templateSettings]);

  // Handle Resize (viewport). World = DRAW_WORLD_SIZE; pan centered on first layout.
  useEffect(() => {
    const handleResize = () => {
      if (!containerRef.current) return;
      const { clientWidth, clientHeight } = containerRef.current;
      const w = getMandalaWorld(clientWidth, clientHeight, DRAW_WORLD_SIZE);
      if (!panInitializedRef.current || dimensions.width === 0) {
        panRef.current = { ...w.defaultPan };
        panInitializedRef.current = true;
      } else if (
        clientWidth !== dimensions.width ||
        clientHeight !== dimensions.height
      ) {
        const z = zoomRef.current;
        const centerScreenX = dimensions.width / 2;
        const centerScreenY = dimensions.height / 2;
        const worldX = (centerScreenX - panRef.current.x) / z;
        const worldY = (centerScreenY - panRef.current.y) / z;
        panRef.current = {
          x: clientWidth / 2 - worldX * z,
          y: clientHeight / 2 - worldY * z
        };
      }
      setDimensions({ width: clientWidth, height: clientHeight });
    };

    handleResize();
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, [dimensions.width, dimensions.height]);

  // Export quality change → lattice radius only (overlay); world size is fixed
  useEffect(() => {
    schedulerRef.current?.schedule(() => drawOverlayRef.current());
  }, [canvasSize]);

  // Update canvas dimensions with high-DPR scaling
  useEffect(() => {
    const canvas = canvasRef.current;
    const dtCanvas = dynamicCanvasRef.current;
    if (canvas && dtCanvas && (canvas.width !== dimensions.width || canvas.height !== dimensions.height)) {
      const dpr = window.devicePixelRatio || 1;
      
      canvas.width = dimensions.width * dpr;
      canvas.height = dimensions.height * dpr;
      canvas.style.width = `${dimensions.width}px`;
      canvas.style.height = `${dimensions.height}px`;

      dtCanvas.width = dimensions.width * dpr;
      dtCanvas.height = dimensions.height * dpr;
      dtCanvas.style.width = `${dimensions.width}px`;
      dtCanvas.style.height = `${dimensions.height}px`;
    }
  }, [dimensions]);

  // Handle mouse wheel zoom — всегда через refs, не через stale drawAllStrokes из mount
  useEffect(() => {
    const canvas = dynamicCanvasRef.current;
    if (!canvas) return;

    const handleWheel = (e: WheelEvent) => {
      e.preventDefault();
      perfHud.markPanZoom();
      // Общие лимиты с Templates (CAMERA_ZOOM_*) — широкий диапазон
      const curZoom = zoomRef.current;
      const zoomFactor = curZoom < 0.25 ? 1.2 : curZoom > 8 ? 1.14 : 1.12;
      const nextZoom = e.deltaY < 0 ? curZoom * zoomFactor : curZoom / zoomFactor;
      const clampedZoom = Math.max(CAMERA_ZOOM_MIN, Math.min(CAMERA_ZOOM_MAX, nextZoom));

      const rect = canvas.getBoundingClientRect();
      const cursorX = e.clientX - rect.left;
      const cursorY = e.clientY - rect.top;

      const curPan = panRef.current;
      panRef.current = {
        x: cursorX - (cursorX - curPan.x) * (clampedZoom / curZoom),
        y: cursorY - (cursorY - curPan.y) * (clampedZoom / curZoom)
      };
      zoomRef.current = clampedZoom;

      // Важно: не захватывать drawAllStrokes из closure первого mount
      schedulerRef.current?.schedule(() => drawAllStrokesRef.current());
      schedulerRef.current?.schedule(() => drawOverlayRef.current());
    };

    canvas.addEventListener('wheel', handleWheel, { passive: false });
    return () => canvas.removeEventListener('wheel', handleWheel);
  }, [dimensions.width, dimensions.height]);

  // Handle space key down for panning shortcut
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.code === 'Space') {
        setIsSpacePressed(true);
      }
    };
    const handleKeyUp = (e: KeyboardEvent) => {
      if (e.code === 'Space') {
        setIsSpacePressed(false);
        setIsPanning(false);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    window.addEventListener('keyup', handleKeyUp);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
      window.removeEventListener('keyup', handleKeyUp);
    };
  }, []);

  /**
   * Full device copy src → scratch (smudge/stretch/blur).
   * Must be full frame for mandala replicas (they sample far from the seed path).
   */
  const syncScratchFull = useCallback((srcCanvas: HTMLCanvasElement) => {
    if (!scratchCanvasRef.current) {
      scratchCanvasRef.current = document.createElement('canvas');
    }
    const scratch = scratchCanvasRef.current;
    if (scratch.width !== srcCanvas.width || scratch.height !== srcCanvas.height) {
      scratch.width = srcCanvas.width;
      scratch.height = srcCanvas.height;
    }
    const sCtx = scratch.getContext('2d');
    if (!sCtx) return;
    sCtx.setTransform(1, 0, 0, 1, 0, 0);
    sCtx.clearRect(0, 0, scratch.width, scratch.height);
    sCtx.drawImage(srcCanvas, 0, 0);
  }, []);

  // Guide points: центр мира + радиус от viewport (как Templates visualizer)
  const guidePointsCache = useMemo(() => {
    if (mandalaWorld.size <= 0) return {} as ReturnType<typeof computeAllGuides>;
    return computeAllGuides(mandalaWorld.cx, mandalaWorld.cy, latticeRadius, templateSettings);
  }, [mandalaWorld, latticeRadius, templateSettings]);

  // Guide rails — colors contrast-adapted to canvas background
  const drawGuides = useCallback(
    (ctx: CanvasRenderingContext2D, cx: number, cy: number, maxRadius: number) => {
      renderGuides(ctx, cx, cy, maxRadius, templateSettings, zoomRef.current, fillColor, {
        drawCenter: true
      });
    },
    [templateSettings, fillColor]
  );

  // WebGL smudge/stretch — лениво. Blur всегда CPU (без BlurShader).
  const getSmudgeShader = (): SmudgeShader | null => {
    if (!webglSupportedRef.current) return null;
    if (!smudgeShaderRef.current) {
      smudgeShaderRef.current = new SmudgeShader(document.createElement('canvas'));
    }
    return smudgeShaderRef.current;
  };

  // Перевод мировых координат штриха в device-пиксели с учётом текущего контекста
  // (dpr + pan + zoom + поворот/зеркало реплики, применённые drawSymmetric).
  const toDevicePoints = (ctx: CanvasRenderingContext2D, pts: Point[]): Point[] => {
    const m = ctx.getTransform();
    return pts.map(p => ({
      x: p.x * m.a + p.y * m.c + m.e,
      y: p.x * m.b + p.y * m.d + m.f
    }));
  };

  // Построение массивов точек для всех симметричных копий штриха в мировых координатах
  const getSymmetricPaths = (points: Point[], cx: number, cy: number): Point[][] => {
    const { segments, mirror, rotation } = templateSettings;
    const angleStep = (Math.PI * 2) / segments;
    const baseRotation = (rotation * Math.PI) / 180;
    const paths: Point[][] = [];

    for (let i = 0; i < segments; i++) {
      const theta = baseRotation + i * angleStep;
      const cosT = Math.cos(theta);
      const sinT = Math.sin(theta);

      // Поворот точек вокруг центра (cx, cy)
      const rotated = points.map(p => {
        const dx = p.x - cx;
        const dy = p.y - cy;
        return {
          x: cx + dx * cosT - dy * sinT,
          y: cy + dx * sinT + dy * cosT,
          pressure: p.pressure
        };
      });
      paths.push(rotated);

      if (mirror) {
        // Отражение относительно вертикальной оси в центре (cx, cy)
        const mirrored = rotated.map(p => ({
          x: 2 * cx - p.x,
          y: p.y,
          pressure: p.pressure
        }));
        paths.push(mirrored);
      }
    }
    return paths;
  };

  // Live WebGL только для smudge/stretch. Blur — всегда CPU (круглый clip, без «квадратов»).
  interface EffectSession {
    type: BrushSettings['type'];
    settings: BrushSettings;
    smudge: SmudgeShader;
  }
  const effectSessionRef = useRef<EffectSession | null>(null);

  const worldToDev = (p: Point): Point => {
    const dpr = window.devicePixelRatio || 1;
    return {
      x: dpr * (panRef.current.x + zoomRef.current * p.x),
      y: dpr * (panRef.current.y + zoomRef.current * p.y)
    };
  };

  // WebGL live ROI отключён для smudge/stretch/blur — квадратные «дыры».
  // Все эффекты: CPU + круглый clip (как рабочий blur).
  const beginEffectSession = (_stroke: Stroke): boolean => false;

  const stampEffectSegment = (prev: Point, curr: Point): void => {
    const sess = effectSessionRef.current;
    if (!sess) return;
    const cx = dimensions.width / 2;
    const cy = dimensions.height / 2;
    const dpr = window.devicePixelRatio || 1;
    const zoom = zoomRef.current;
    const pathsWorld = getSymmetricPaths([prev, curr], cx, cy);
    const pathsDev = pathsWorld.map(path => path.map(worldToDev));
    const mainCanvas = canvasRef.current;
    const mainCtx = mainCanvas ? mainCanvas.getContext('2d') : null;
    if (!mainCanvas || !mainCtx) return;

    const radiusDev = (sess.settings.size * zoom * dpr) / 2;
    const strength = sess.type === 'stretch' ? 0.95 : 0.4;
    const dirty = sess.smudge.stamp(pathsDev, radiusDev, sess.settings.opacity, strength);
    const out = sess.smudge.getOutputCanvas();
    if (dirty && out) {
      mainCtx.save();
      mainCtx.setTransform(1, 0, 0, 1, 0, 0);
      mainCtx.drawImage(out, dirty.x, dirty.y, dirty.w, dirty.h, dirty.x, dirty.y, dirty.w, dirty.h);
      mainCtx.restore();
    }
  };

  const endEffectSession = (): void => {
    if (!effectSessionRef.current) return;
    effectSessionRef.current.smudge.endStroke();
    effectSessionRef.current = null;
  };

  // Main drawing engine for a single segment path
  const drawSegment = (ctx: CanvasRenderingContext2D, points: Point[], settings: BrushSettings, cx: number, cy: number) => {
    if (points.length === 0) return;
    
    if (settings.type === 'vector' || settings.type === 'eraser' || settings.type === 'glow' || settings.type === 'sketch') {
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.globalCompositeOperation = settings.type === 'eraser' ? 'destination-out' : 'source-over';
      ctx.globalAlpha = settings.type === 'eraser' ? 1.0 : settings.opacity / 100;
      
      if (settings.type === 'glow') {
        ctx.shadowBlur = settings.size * 1.5;
        ctx.shadowColor = settings.color;
      } else {
        ctx.shadowBlur = 0;
      }

      if (settings.type === 'sketch') {
        ctx.strokeStyle = settings.color;
        const sketchAlpha = (settings.opacity / 100) * 0.25;
        
        const offsets = [
          { dx: 0, dy: 0, w: settings.size },
          { dx: -1.5, dy: 1, w: settings.size * 0.6 },
          { dx: 1, dy: -1.5, w: settings.size * 0.6 },
          { dx: 2, dy: 2, w: settings.size * 0.4 },
          { dx: -1, dy: -1, w: settings.size * 0.5 }
        ];

        offsets.forEach(offset => {
          ctx.lineWidth = Math.max(0.5, offset.w);
          ctx.globalAlpha = sketchAlpha;
          ctx.beginPath();
          ctx.moveTo(points[0].x + offset.dx, points[0].y + offset.dy);
          for (let i = 1; i < points.length; i++) {
            const p = points[i];
            const pres = p.pressure !== undefined ? p.pressure : 1.0;
            ctx.lineWidth = Math.max(0.5, offset.w * pres);
            ctx.lineTo(p.x + offset.dx, p.y + offset.dy);
          }
          ctx.stroke();
        });
      } else {
        ctx.strokeStyle = settings.type === 'eraser' ? '#000000' : settings.color;

        if (points.length === 1) {
          ctx.fillStyle = ctx.strokeStyle;
          ctx.beginPath();
          ctx.arc(points[0].x, points[0].y, settings.size / 2, 0, Math.PI * 2);
          ctx.fill();
        } else {
          // Батчинг GPU-вызовов: вместо stroke() на каждый сегмент (узкое место #2)
          // группируем последовательные точки по уровням толщины (pressure) в Path2D.
          const batched = PathBatcher.buildPressureBatchedPaths(points, settings.size);
          batched.forEach(({ path, width }) => {
            ctx.lineWidth = width;
            ctx.stroke(path);
          });
        }
      }
      
      // Reset composites
      ctx.globalCompositeOperation = 'source-over';
      ctx.shadowBlur = 0;
      
    } else if (settings.type === 'dotting') {
      ctx.fillStyle = settings.color;
      ctx.globalAlpha = settings.opacity / 100;
      ctx.shadowBlur = 0;
      
      const numPoints = points.length;
      points.forEach((p, idx) => {
        const progress = numPoints > 1 ? idx / (numPoints - 1) : 0.5;
        let scale = 1.0;
        
        const profile = settings.dotProfile || 'sine';
        if (profile === 'sine') {
          scale = Math.sin(Math.PI * progress);
        } else if (profile === 'growing') {
          scale = progress;
        } else if (profile === 'shrinking') {
          scale = 1.0 - progress;
        } else {
          scale = 1.0;
        }
        
        const minR = 2.0;
        const maxR = settings.size;
        const pressureVal = p.pressure !== undefined ? p.pressure : 1.0;
        const dotRadius = (minR + (maxR - minR) * scale) * pressureVal;

        ctx.beginPath();
        ctx.arc(p.x, p.y, Math.max(0.5, dotRadius), 0, Math.PI * 2);
        ctx.fill();
      });

    } else if (settings.type === 'pixel') {
      ctx.fillStyle = settings.color;
      ctx.globalAlpha = settings.opacity / 100;
      ctx.shadowBlur = 0;

      const gridSize = Math.max(4, settings.size);
      const drawnPixels = new Set<string>();

      points.forEach(p => {
        const relX = p.x - cx;
        const relY = p.y - cy;
        const snapX = Math.round(relX / gridSize) * gridSize;
        const snapY = Math.round(relY / gridSize) * gridSize;
        const key = `${snapX},${snapY}`;
        
        if (!drawnPixels.has(key)) {
          drawnPixels.add(key);
          ctx.fillRect(cx + snapX - gridSize / 2, cy + snapY - gridSize / 2, gridSize, gridSize);
        }
      });

    } else if (settings.type === 'rainbow') {
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';
      ctx.globalAlpha = settings.opacity / 100;
      ctx.shadowBlur = 0;

      if (points.length === 1) {
        ctx.fillStyle = 'hsl(0, 100%, 60%)';
        ctx.beginPath();
        ctx.arc(points[0].x, points[0].y, settings.size / 2, 0, Math.PI * 2);
        ctx.fill();
      } else {
        const numSegments = points.length - 1;
        for (let i = 0; i < numSegments; i++) {
          const p1 = points[i];
          const p2 = points[i + 1];
          const hue = (i / Math.max(1, numSegments)) * 360;
          
          ctx.strokeStyle = `hsl(${hue}, 100%, 60%)`;
          const pres = p1.pressure !== undefined ? p1.pressure : 1.0;
          ctx.lineWidth = settings.size * pres;
          
          ctx.beginPath();
          ctx.moveTo(p1.x, p1.y);
          ctx.lineTo(p2.x, p2.y);
          ctx.stroke();
        }
      }

    } else if (settings.type === 'smudge' || settings.type === 'stretch') {
      // Canvas 2D smudge/stretch — размер из текущей матрицы (world rebuild: scale=dpr; live: dpr*zoom)
      const scratch = scratchCanvasRef.current;
      if (!scratch) return;

      ctx.save();
      
      for (let i = 1; i < points.length; i++) {
        const pPrev = points[i - 1];
        const pCurr = points[i];
        
        // Compute raw device/screen pixel coordinates
        const m = ctx.getTransform();
        const scale = Math.hypot(m.a, m.b) || 1;
        const prevScreenX = pPrev.x * m.a + pPrev.y * m.c + m.e;
        const prevScreenY = pPrev.x * m.b + pPrev.y * m.d + m.f;
        const currScreenX = pCurr.x * m.a + pCurr.y * m.c + m.e;
        const currScreenY = pCurr.x * m.b + pCurr.y * m.d + m.f;
        
        const size = settings.size * scale;

        ctx.save();
        ctx.setTransform(1, 0, 0, 1, 0, 0); // reset transform context to screen pixels

        // Smudge uses low opacity to mix pixels, stretch is solid displacement warp
        ctx.globalAlpha = settings.type === 'smudge' 
          ? (settings.opacity / 100) * 0.4 
          : (settings.opacity / 100) * 0.95;
        
        const dx = currScreenX - prevScreenX;
        const dy = currScreenY - prevScreenY;
        const dist = Math.sqrt(dx * dx + dy * dy);
        // Coarser steps — was /2 and caused multi-second freezes with symmetry
        const stepPx = Math.max(3, size * 0.35);
        const steps = Math.min(24, Math.ceil(dist / stepPx));
        
        for (let s = 0; s <= steps; s++) {
          const t = steps > 0 ? s / steps : 1.0;
          const sx = prevScreenX + dx * t;
          const sy = prevScreenY + dy * t;
          
          ctx.save();
          ctx.beginPath();
          ctx.arc(sx, sy, size / 2, 0, Math.PI * 2);
          ctx.clip(); // clip to brush radius
          
          // Draw copied pixel patch from scratch canvas at offset
          // Smearing shifts the source slightly to create a physical paint push
          const sourceX = prevScreenX + dx * t * 0.15;
          const sourceY = prevScreenY + dy * t * 0.15;

          ctx.drawImage(
            scratch,
            sourceX - size / 2,
            sourceY - size / 2,
            size,
            size,
            sx - size / 2,
            sy - size / 2,
            size,
            size
          );
          ctx.restore();
        }
        ctx.restore();
      }
      ctx.restore();

    } else if (settings.type === 'bleach') {
      // Bleach/desaturate - converts color to grayscale using standard HSL math
      ctx.save();
      ctx.globalCompositeOperation = 'color';
      ctx.fillStyle = 'rgba(128, 128, 128, 1)'; // mid-gray removes saturation
      ctx.globalAlpha = settings.opacity / 100;
      
      if (points.length === 1) {
        ctx.beginPath();
        ctx.arc(points[0].x, points[0].y, settings.size / 2, 0, Math.PI * 2);
        ctx.fill();
      } else {
        ctx.lineCap = 'round';
        ctx.lineJoin = 'round';
        ctx.lineWidth = settings.size;
        ctx.strokeStyle = 'rgba(128, 128, 128, 1)';
        
        ctx.beginPath();
        ctx.moveTo(points[0].x, points[0].y);
        for (let i = 1; i < points.length; i++) {
          const p = points[i];
          ctx.lineTo(p.x, p.y);
        }
        ctx.stroke();
      }
      ctx.restore();
    } else if (settings.type === 'airbrush') {
      ctx.fillStyle = settings.color;
        ctx.shadowBlur = 0;
        const size = settings.size;
        const density = Math.floor(size * 1.5);
        const opacity = (settings.opacity / 100) * 0.15;

        points.forEach(p => {
          ctx.globalAlpha = opacity * (p.pressure !== undefined ? p.pressure : 1.0);
          for (let i = 0; i < density; i++) {
            const angle = Math.random() * Math.PI * 2;
            const dist = (Math.random() + Math.random() + Math.random()) / 3 * (size / 2);
            const px = p.x + Math.cos(angle) * dist;
            const py = p.y + Math.sin(angle) * dist;
            
            ctx.beginPath();
            ctx.arc(px, py, Math.max(0.5, size * 0.05 * Math.random()), 0, Math.PI * 2);
            ctx.fill();
          }
        });
        ctx.globalAlpha = 1.0;

      } else if (settings.type === 'blur') {
        // Canvas 2D blur — круглый clip (без WebGL scissor-квадратов)
        const scratch = scratchCanvasRef.current;
        if (!scratch) return;

        ctx.save();
        for (let i = 1; i < points.length; i++) {
          const pPrev = points[i - 1];
          const pCurr = points[i];
          
          const m = ctx.getTransform();
          const scale = Math.hypot(m.a, m.b) || 1;
          const prevScreenX = pPrev.x * m.a + pPrev.y * m.c + m.e;
          const prevScreenY = pPrev.x * m.b + pPrev.y * m.d + m.f;
          const currScreenX = pCurr.x * m.a + pCurr.y * m.c + m.e;
          const currScreenY = pCurr.x * m.b + pCurr.y * m.d + m.f;
          
          const size = settings.size * scale;

          ctx.save();
          ctx.setTransform(1, 0, 0, 1, 0, 0);
          ctx.globalAlpha = (settings.opacity / 100) * 0.6;
          
          const dx = currScreenX - prevScreenX;
          const dy = currScreenY - prevScreenY;
          const dist = Math.sqrt(dx * dx + dy * dy);
          // Шаг ~0.35 радиуса — меньше квадратных «перекрытий»
          const steps = Math.max(1, Math.ceil(dist / Math.max(2, size * 0.35)));
          
          for (let s = 0; s <= steps; s++) {
            const t = steps > 0 ? s / steps : 1.0;
            const sx = prevScreenX + dx * t;
            const sy = prevScreenY + dy * t;
            
            ctx.save();
            ctx.beginPath();
            ctx.arc(sx, sy, size / 2, 0, Math.PI * 2);
            ctx.clip();
            
            const blurRadius = Math.max(1, size / 10);
            ctx.filter = `blur(${blurRadius}px)`;

            ctx.drawImage(
              scratch,
              sx - size / 2,
              sy - size / 2,
              size,
              size,
              sx - size / 2,
              sy - size / 2,
              size,
              size
            );
            ctx.restore();
          }
          ctx.restore();
        }
        ctx.restore();
      }
    };

  // Symmetric replicas — CPU path для всех кистей (в т.ч. blur/smudge fallback).
  const drawSymmetric = useCallback((ctx: CanvasRenderingContext2D, stroke: Stroke, cx: number, cy: number) => {
    const { segments, mirror, rotation } = templateSettings;
    const angleStep = (Math.PI * 2) / segments;
    const baseRotation = (rotation * Math.PI) / 180;

    for (let i = 0; i < segments; i++) {
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(baseRotation + i * angleStep);
      ctx.translate(-cx, -cy);
      
      drawSegment(ctx, stroke.points, stroke.settings, cx, cy);
      
      if (mirror) {
        ctx.translate(cx, cy);
        ctx.scale(-1, 1);
        ctx.translate(-cx, -cy);
        drawSegment(ctx, stroke.points, stroke.settings, cx, cy);
      }
      
      ctx.restore();
    }
  }, [templateSettings]);

  /**
   * Effect brushes (smudge/stretch/blur) with mandala symmetry.
   * Per-segment full-canvas snapshot is O(points × canvas) — freezes on long strokes.
   * We decimate the path so bake stays interactive while keeping symmetric sampling.
   */
  const drawSymmetricEffect = useCallback(
    (ctx: CanvasRenderingContext2D, stroke: Stroke, cx: number, cy: number) => {
      const raw = stroke.points;
      if (raw.length === 0) return;

      // Cap segments: full scratch each step is the hang source (was points-1 copies of whole buffer)
      const MAX_EFFECT_SEGS = 36;
      let pts = raw;
      if (raw.length > MAX_EFFECT_SEGS + 1) {
        const out: Point[] = [raw[0]];
        const step = (raw.length - 1) / MAX_EFFECT_SEGS;
        for (let i = 1; i < MAX_EFFECT_SEGS; i++) {
          out.push(raw[Math.round(i * step)]);
        }
        out.push(raw[raw.length - 1]);
        pts = out;
      }

      const dest = ctx.canvas;
      if (pts.length === 1) {
        syncScratchFull(dest);
        drawSymmetric(ctx, stroke, cx, cy);
        return;
      }

      for (let i = 1; i < pts.length; i++) {
        syncScratchFull(dest);
        const seg: Stroke = {
          ...stroke,
          points: [pts[i - 1], pts[i]]
        };
        drawSymmetric(ctx, seg, cx, cy);
      }
    },
    [drawSymmetric, syncScratchFull]
  );

  // HQ export must be registered after drawSymmetric* exist (avoids TDZ)
  useEffect(() => {
    window.renderMandalaExportSquare = (opts: MandalaExportRenderOpts) => {
      const outSize = Math.max(16, Math.round(opts.outSize));
      const side = Math.max(8, opts.side);
      const canvas = document.createElement('canvas');
      canvas.width = outSize;
      canvas.height = outSize;
      const ctx = canvas.getContext('2d');
      if (!ctx) return null;

      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, outSize, outSize);
      if (!opts.transparent && opts.bg) {
        ctx.fillStyle = opts.bg;
        ctx.fillRect(0, 0, outSize, outSize);
      }

      const scale = outSize / side;
      const ox = opts.centerX - side / 2;
      const oy = opts.centerY - side / 2;
      ctx.setTransform(scale, 0, 0, scale, -ox * scale, -oy * scale);

      const { cx, cy } = mandalaWorld;
      for (const layer of drawingLayers) {
        if (!layer.visible) continue;
        for (const stroke of strokes) {
          if ((stroke.layerId || 'default') !== layer.id) continue;
          if (!isCacheableStroke(stroke)) {
            drawSymmetricEffect(ctx, stroke, cx, cy);
          } else {
            drawSymmetric(ctx, stroke, cx, cy);
          }
        }
      }

      if (opts.bakeGrid) {
        renderGuides(
          ctx,
          cx,
          cy,
          latticeRadius,
          opts.templateSettings,
          1,
          opts.transparent ? '#000000' : opts.bg || '#051424',
          { drawCenter: false, rayLength: latticeRadius * 2 }
        );
      }

      ctx.setTransform(1, 0, 0, 1, 0, 0);
      return canvas;
    };
    return () => {
      delete window.renderMandalaExportSquare;
    };
  }, [
    mandalaWorld,
    drawingLayers,
    strokes,
    latticeRadius,
    drawSymmetric,
    drawSymmetricEffect
  ]);

  /** Структура мира (без списка strokes) — для incremental append. */
  const buildStructureSig = useCallback((): string => {
    const worldSig = `${templateSettings.segments}|${templateSettings.mirror ? 1 : 0}|${templateSettings.rotation}`;
    const layerSig = drawingLayers.map(l => `${l.id}:${l.visible ? 1 : 0}`).join('|');
    return `canvas${canvasSize}|q${bakeQ}|${worldSig}|${layerSig}`;
  }, [drawingLayers, templateSettings, canvasSize, bakeQ]);

  /** Полная сигнатура контента (без камеры). */
  const buildSceneSig = useCallback((): string => {
    const strokeSig = strokes
      .map(s => `${s.id || ''}:${s.settings.type}:${s.points.length}:${s.layerId || 'd'}`)
      .join(';');
    return `${buildStructureSig()}|${strokeSig}`;
  }, [strokes, buildStructureSig]);

  /**
   * Full rebuild in back-buffer → swap.
   * Chunked across animation frames so the UI stays responsive (no multi-second freezes).
   */
  const rebuildWorldSceneFull = useCallback((): void => {
    if (mandalaWorld.size <= 0) return;
    const scene = worldSceneRef.current!;
    const gen = ++rebuildGenRef.current;
    const strokeList = strokes;
    const layers = drawingLayers;
    const { size, cx, cy } = mandalaWorld;
    const sig = buildSceneSig();
    const structureSig = buildStructureSig();
    rebuildInFlightRef.current = true;
    rebuildTargetSigRef.current = sig;

    void perfTimeAsync(
      'bake',
      'full-rebuild-async',
      { strokes: strokeList.length, world: size, layers: layers.length },
      async () => {
        try {
          scene.setBackgroundColor(fillColor);
          const dpr = window.devicePixelRatio || 1;
          const wctx = scene.beginRebuild(size, size, dpr);
          if (!wctx) {
            perfLog('bake', 'beginRebuild returned null', undefined, 'warn');
            return;
          }
          const stats0 = scene.getBakeStats();
          perfLog('bake', 'buffer ready', {
            buf: stats0.bufferW,
            dpr: +stats0.bakeDpr.toFixed(4),
            mp: stats0.megapixels
          });

          const work: Stroke[] = [];
          for (const layer of layers) {
            if (!layer.visible) continue;
            for (const stroke of strokeList) {
              if ((stroke.layerId || 'default') !== layer.id) continue;
              work.push(stroke);
            }
          }

          const CHUNK = 3; // strokes per frame — keeps UI alive
          let drawn = 0;
          let effects = 0;
          for (let i = 0; i < work.length; i++) {
            if (gen !== rebuildGenRef.current) {
              perfLog('bake', 'full-rebuild cancelled', { gen, at: i }, 'warn');
              return;
            }
            const stroke = work[i];
            if (!isCacheableStroke(stroke)) {
              effects++;
              drawSymmetricEffect(wctx, stroke, cx, cy);
            } else {
              drawSymmetric(wctx, stroke, cx, cy);
            }
            drawn++;
            if (i > 0 && i % CHUNK === 0) {
              await new Promise<void>(r => requestAnimationFrame(() => r()));
            }
          }

          if (gen !== rebuildGenRef.current) {
            perfLog('bake', 'full-rebuild cancelled before end', { gen }, 'warn');
            return;
          }

          scene.endRebuild(sig, strokeList.length, structureSig);
          perfLog('bake', 'full-rebuild done', {
            drawn,
            effects,
            ...scene.getBakeStats()
          });
          schedulerRef.current?.schedule(() => drawAllStrokesRef.current());
        } finally {
          if (gen === rebuildGenRef.current) {
            rebuildInFlightRef.current = false;
          }
        }
      }
    );
  }, [
    mandalaWorld,
    drawingLayers,
    strokes,
    drawSymmetric,
    drawSymmetricEffect,
    buildSceneSig,
    buildStructureSig,
    fillColor
  ]);

  /**
   * Incremental bake: append one new stroke on display (no full replay).
   */
  const appendStrokeToScene = useCallback(
    (stroke: Stroke): boolean => {
      if (mandalaWorld.size <= 0) return false;
      const scene = worldSceneRef.current!;
      return perfTime(
        'bake',
        'append-one',
        {
          type: stroke.settings.type,
          pts: stroke.points.length,
          effect: !isCacheableStroke(stroke)
        },
        () => {
          const dpr = window.devicePixelRatio || 1;
          const { size, cx, cy } = mandalaWorld;
          const wctx = scene.beginAppend(size, size, dpr);
          if (!wctx) {
            perfLog('bake', 'append fell back (resized/empty)', scene.getBakeStats(), 'warn');
            return false;
          }

          if (!isCacheableStroke(stroke)) {
            drawSymmetricEffect(wctx, stroke, cx, cy);
          } else {
            drawSymmetric(wctx, stroke, cx, cy);
          }
          return true;
        }
      );
    },
    [mandalaWorld, drawSymmetric, drawSymmetricEffect]
  );

  /**
   * Sync scene with strokes: append-one if possible, else full rebuild.
   */
  const syncWorldScene = useCallback((): void => {
    if (mandalaWorld.size <= 0) return;
    const scene = worldSceneRef.current!;
    const sig = buildSceneSig();
    if (scene.isCurrent(sig)) return;

    const structureSig = buildStructureSig();

    // Ctrl+Z / multi-undo: restore bake snapshot — no full rebuild
    if (strokes.length < scene.strokeCount) {
      const fromCount = scene.strokeCount;
      const restored = scene.tryRestoreUndo(strokes.length, structureSig, sig);
      if (restored) {
        perfLog('bake', 'undo-restore', { from: fromCount, to: strokes.length });
        // Cancel any in-flight full rebuild so it doesn't overwrite the restore
        rebuildGenRef.current++;
        rebuildInFlightRef.current = false;
        return;
      }
      perfLog(
        'bake',
        'undo without snap → full rebuild',
        { to: strokes.length, baked: fromCount },
        'warn'
      );
    }

    if (scene.canAppendOne(structureSig, strokes.length) && strokes.length > 0) {
      const last = strokes[strokes.length - 1];
      if (appendStrokeToScene(last)) {
        scene.endAppend(sig, strokes.length, structureSig);
        return;
      }
      perfLog('bake', 'append failed → full rebuild', { strokes: strokes.length }, 'warn');
    } else {
      // Already baking this exact content — don't restart (would cancel forever)
      if (rebuildInFlightRef.current && rebuildTargetSigRef.current === sig) {
        return;
      }
      perfLog(
        'bake',
        'full rebuild path',
        {
          strokes: strokes.length,
          baked: scene.strokeCount,
          canAppend: scene.canAppendOne(structureSig, strokes.length)
        },
        strokes.length > 20 ? 'info' : 'debug'
      );
    }

    rebuildWorldSceneFull();
  }, [
    mandalaWorld.size,
    strokes,
    buildSceneSig,
    buildStructureSig,
    appendStrokeToScene,
    rebuildWorldSceneFull
  ]);

  const drawAllStrokes = useCallback(() => {
    perfHud.frame();
    const t0 = performance.now();

    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    if (dimensions.width <= 0 || dimensions.height <= 0 || mandalaWorld.size <= 0) return;

    const dpr = window.devicePixelRatio || 1;
    worldSceneRef.current!.setBackgroundColor(fillColor);

    syncWorldScene();

    worldSceneRef.current!.blitTo(
      ctx,
      canvas.width,
      canvas.height,
      dpr,
      zoomRef.current,
      panRef.current
    );

    const ms = performance.now() - t0;
    perfHud.recordDrawAll(ms, strokes.length);
    if (ms >= 50) {
      perfLog(
        'draw',
        'drawAllStrokes slow',
        {
          ms: +ms.toFixed(1),
          strokes: strokes.length,
          ...worldSceneRef.current!.getBakeStats()
        },
        ms >= 200 ? 'error' : 'warn'
      );
    }
  }, [syncWorldScene, dimensions.width, dimensions.height, mandalaWorld.size, strokes.length, fillColor]);

  // Держим refs на актуальные функции (wheel / external listeners)
  drawAllStrokesRef.current = drawAllStrokes;

  // Draw mathematical guides and intermediate drawing strokes on the overlay canvas
  const drawOverlay = useCallback(() => {
    const t0 = performance.now();

    const canvas = dynamicCanvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    ctx.save();
    ctx.scale(dpr, dpr);
    ctx.translate(panRef.current.x, panRef.current.y);
    ctx.scale(zoomRef.current, zoomRef.current);

    const { cx, cy } = mandalaWorld;

    // Draw active drawing preview stroke if drawing (WebGL or fallback)
    if (isDrawingRef.current && currentPointsRef.current.length > 0 && brushSettings.type !== 'smudge' && brushSettings.type !== 'stretch' && brushSettings.type !== 'blur') {
      const tempStroke: Stroke = { points: currentPointsRef.current, settings: brushSettings };
      drawSymmetric(ctx, tempStroke, cx, cy);
    }

    // Draw guidelines — latticeRadius as in Templates
    drawGuides(ctx, cx, cy, latticeRadius);

    // Brush cursor ring
    if (hoverPointRef.current && !isPanning && !isSpacePressed) {
      ctx.beginPath();
      ctx.arc(hoverPointRef.current.x, hoverPointRef.current.y, brushSettings.size / 2, 0, Math.PI * 2);
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.45)';
      ctx.lineWidth = 1 / zoomRef.current;
      ctx.setLineDash([3 / zoomRef.current, 3 / zoomRef.current]);
      ctx.stroke();
      ctx.setLineDash([]);
    }

    ctx.restore();

    perfHud.recordDrawOverlay(performance.now() - t0);
  }, [drawGuides, brushSettings, drawSymmetric, dimensions, mandalaWorld, latticeRadius, isPanning, isSpacePressed]);

  drawOverlayRef.current = drawOverlay;

  // Re-draw overlay when guides/brush chrome change
  useEffect(() => {
    schedulerRef.current!.schedule(() => drawOverlayRef.current());
  }, [drawOverlay, dimensions.width, dimensions.height, brushSettings, isSpacePressed, isPanning]);

  // Re-draw when strokes/size/bg/project resolution change
  useEffect(() => {
    schedulerRef.current!.schedule(() => drawAllStrokesRef.current());
  }, [drawAllStrokes, dimensions.width, dimensions.height, strokes, drawingLayers, fillColor, canvasSize]);

  // Background color change → full rebake (quality size does not change world buffer)
  useEffect(() => {
    worldSceneRef.current?.invalidate();
    worldSceneRef.current?.setBackgroundColor(fillColor);
    schedulerRef.current?.schedule(() => drawAllStrokesRef.current());
  }, [fillColor]);

  // Отмена всех отложенных рендеров при размонтировании
  useEffect(() => {
    return () => schedulerRef.current?.cancel();
  }, []);

  // Освобождение WebGL / world scene при размонтировании
  useEffect(() => {
    return () => {
      smudgeShaderRef.current?.dispose();
      smudgeShaderRef.current = null;
      worldSceneRef.current?.dispose();
    };
  }, []);

  // Построение пространственного хеша из активных точек направляющих для быстрого snapping
  useEffect(() => {
    const allPoints: Point[] = [];
    Object.keys(guidePointsCache).forEach(key => {
      let enabled = false;
      if (key === 'spirograph') enabled = templateSettings.showSpirograph;
      else if (key === 'superellipse') enabled = templateSettings.showSuperellipse;
      else if (key === 'maurer') enabled = templateSettings.showMaurer;
      else if (key === 'petals') enabled = templateSettings.showPetals;
      else if (key === 'lissajous') enabled = templateSettings.showLissajous;
      else if (key === 'cardioid') enabled = templateSettings.showCardioid;
      else if (key === 'spiral') enabled = templateSettings.showSpiral;

      if (enabled) {
        const pts = guidePointsCache[key];
        for (let i = 0; i < pts.length; i++) allPoints.push(pts[i]);
      }
    });
    snapHashRef.current!.build(allPoints);
  }, [guidePointsCache, templateSettings]);

  // Compute pointer position mapped onto infinite camera + guide snapping
  const getCanvasPoint = (e: React.PointerEvent<HTMLCanvasElement>): Point => {
    const rect = canvasRef.current?.getBoundingClientRect();
    if (!rect) return { x: 0, y: 0 };
    
    const screenX = e.clientX - rect.left;
    const screenY = e.clientY - rect.top;

    let x = (screenX - panRef.current.x) / zoomRef.current;
    let y = (screenY - panRef.current.y) / zoomRef.current;

    // Guide Snapping Math (квадратный world)
    if (templateSettings.snapToGuides && mandalaWorld.size > 0) {
      const cx = mandalaWorld.cx;
      const cy = mandalaWorld.cy;
      const maxRadius = latticeRadius;

      const relativeX = x - cx;
      const relativeY = y - cy;
      const rawRadius = Math.sqrt(relativeX * relativeX + relativeY * relativeY);
      
      let angle = Math.atan2(relativeY, relativeX);
      if (angle < 0) angle += Math.PI * 2;

      let bestSnapPoint: Point | null = null;
      let bestDist = Infinity; // Infinite constraint range to lock drawing on rails

      // Snap 1: Radial sector rays grid
      if (templateSettings.showGridLines) {
        const sectorAngle = (Math.PI * 2) / templateSettings.segments;
        const baseRotation = (templateSettings.rotation * Math.PI) / 180;
        const relAngle = (angle - baseRotation + Math.PI * 4) % (Math.PI * 2);
        const closestSectorIdx = Math.round(relAngle / sectorAngle);
        const snappedAngle = baseRotation + closestSectorIdx * sectorAngle;

        const distanceToRay = rawRadius * Math.sin(Math.abs(angle - snappedAngle));
        if (distanceToRay < bestDist) {
          bestDist = distanceToRay;
          bestSnapPoint = {
            x: cx + rawRadius * Math.cos(snappedAngle),
            y: cy + rawRadius * Math.sin(snappedAngle)
          };
        }
      }

      // Snap 2: Wave-modulated Concentric rings
      if (templateSettings.showRings) {
        const amp = (templateSettings.ringModulationAmp || 0) / 100;
        const freq = templateSettings.ringModulationFreq || 4;
        const modulationFactor = 1 + amp * Math.cos(freq * angle);
        
        const unmodulatedRadius = rawRadius / modulationFactor;
        const ringSpacing = maxRadius / templateSettings.layers;
        const closestRingIndex = Math.round(unmodulatedRadius / ringSpacing);
        
        if (closestRingIndex >= 1 && closestRingIndex <= templateSettings.layers) {
          const snappedUnmodRadius = closestRingIndex * ringSpacing;
          const snappedModRadius = snappedUnmodRadius * modulationFactor;
          const radiusDiff = Math.abs(rawRadius - snappedModRadius);
          
          if (radiusDiff < bestDist) {
            bestDist = radiusDiff;
            bestSnapPoint = {
              x: cx + snappedModRadius * Math.cos(angle),
              y: cy + snappedModRadius * Math.sin(angle)
            };
          }
        }
      }

      // Snap 3: Spatial hash lookup для прекомпьютерных активных направляющих
      // (Spirograph, Rose, Spiral, etc.) — O(n) → O(соседи) (узкое место #4)
      const nearestGuide = snapHashRef.current!.nearest(x, y);
      if (nearestGuide && nearestGuide.distance < bestDist) {
        bestDist = nearestGuide.distance;
        bestSnapPoint = nearestGuide.point;
      } else if (!nearestGuide) {
        // Резервный линейный поиск (для мгновенного снейпинга при клике/резком прыжке далеко от линий)
        let linearBest: Point | null = null;
        let linearBestDist = Infinity;
        Object.keys(guidePointsCache).forEach(key => {
          let enabled = false;
          if (key === 'spirograph') enabled = templateSettings.showSpirograph;
          else if (key === 'superellipse') enabled = templateSettings.showSuperellipse;
          else if (key === 'maurer') enabled = templateSettings.showMaurer;
          else if (key === 'petals') enabled = templateSettings.showPetals;
          else if (key === 'lissajous') enabled = templateSettings.showLissajous;
          else if (key === 'cardioid') enabled = templateSettings.showCardioid;
          else if (key === 'spiral') enabled = templateSettings.showSpiral;

          if (enabled) {
            const pts = guidePointsCache[key];
            for (let i = 0; i < pts.length; i++) {
              const p = pts[i];
              const dx = x - p.x;
              const dy = y - p.y;
              const d = Math.sqrt(dx * dx + dy * dy);
              if (d < linearBestDist) {
                linearBestDist = d;
                linearBest = p;
              }
            }
          }
        });
        if (linearBest && linearBestDist < bestDist) {
          bestDist = linearBestDist;
          bestSnapPoint = linearBest;
        }
      }

      if (bestSnapPoint) {
        x = (bestSnapPoint as Point).x;
        y = (bestSnapPoint as Point).y;
      }
    }

    return {
      x,
      y,
      pressure: e.pressure || 1.0
    };
  };

  const handlePointerDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    e.preventDefault();

    // Middle click or Space triggers camera pan
    if (isSpacePressed || e.button === 1 || e.button === 2) {
      setIsPanning(true);
      panStartRef.current = { x: e.clientX - panRef.current.x, y: e.clientY - panRef.current.y };
      return;
    }

    isDrawingRef.current = true;
    const point = getCanvasPoint(e);
    hoverPointRef.current = point;
    lastRawPointRef.current = point;
    currentPointsRef.current = [point];
    schedulerRef.current?.schedule(drawOverlay);

    // Effect-кисти: полный snapshot main → scratch (все реплики симметрии).
    const isEffect =
      brushSettings.type === 'smudge' ||
      brushSettings.type === 'stretch' ||
      brushSettings.type === 'blur';
    if (isEffect) {
      const mainCanvas = canvasRef.current;
      if (mainCanvas) {
        // WebGL session отключена; CPU + full scratch
        beginEffectSession({ points: [point], settings: brushSettings });
        syncScratchFull(mainCanvas);
      }
    }
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (isPanning) {
      perfHud.markPanZoom();
      panRef.current = {
        x: e.clientX - panStartRef.current.x,
        y: e.clientY - panStartRef.current.y
      };
      schedulerRef.current?.schedule(drawAllStrokes);
      schedulerRef.current?.schedule(drawOverlay);
      return;
    }

    const point = getCanvasPoint(e);
    hoverPointRef.current = point;
    lastRawPointRef.current = point;

    if (!isDrawingRef.current) {
      schedulerRef.current?.schedule(drawOverlay);
      return;
    }

    const type = brushSettings.type;
    const lastPoint = currentPointsRef.current[currentPointsRef.current.length - 1];

    // Min-distance decimation (world px): effect brushes 3–5px, dotting keeps its 8px,
    // other path brushes 0.5–1.5px. Skips both the push and any incremental effect draw.
    let minDist = 1;
    if (type === 'smudge' || type === 'stretch' || type === 'blur') minDist = 4;
    else if (type === 'dotting') minDist = 8;

    if (lastPoint) {
      const dist = Math.hypot(point.x - lastPoint.x, point.y - lastPoint.y);
      if (dist < minDist) {
        schedulerRef.current?.schedule(drawOverlay);
        return;
      }
    }

    // Effect: full scratch → все симметричные реплики одного сегмента (мандала).
    if (type === 'smudge' || type === 'stretch' || type === 'blur') {
      const mainCanvas = canvasRef.current;
      const mainCtx = mainCanvas?.getContext('2d') ?? null;

      if (mainCanvas && mainCtx && lastPoint) {
        const segmentStroke: Stroke = {
          points: [lastPoint, point],
          settings: brushSettings
        };
        const dpr = window.devicePixelRatio || 1;
        // 1) snapshot всего холста — реплики сэмплят актуальные пиксели
        syncScratchFull(mainCanvas);

        const cx = mandalaWorld.cx;
        const cy = mandalaWorld.cy;

        mainCtx.save();
        mainCtx.scale(dpr, dpr);
        mainCtx.translate(panRef.current.x, panRef.current.y);
        mainCtx.scale(zoomRef.current, zoomRef.current);
        // 2) один сегмент × segments × mirror
        drawSymmetric(mainCtx, segmentStroke, cx, cy);
        mainCtx.restore();
      }
    }

    // push WITHOUT array spread (M1) — mutate the live points array in place
    currentPointsRef.current.push(point);
    schedulerRef.current?.schedule(drawOverlay);
  };

  const handlePointerUp = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (isPanning) {
      setIsPanning(false);
      return;
    }

    if (!isDrawingRef.current) return;
    isDrawingRef.current = false;

    // Ensure the final cursor position is captured even if sub-threshold (decimation).
    const pts = currentPointsRef.current;
    const raw = lastRawPointRef.current;
    if (raw && (pts.length === 0 || raw.x !== pts[pts.length - 1].x || raw.y !== pts[pts.length - 1].y)) {
      pts.push(raw);
    }

    if (pts.length > 0) {
      const newStroke: Stroke = {
        points: pts,
        settings: { ...brushSettings }
      };

      if (effectSessionRef.current) endEffectSession();

      addStroke(newStroke);
    }

    currentPointsRef.current = [];
    lastRawPointRef.current = null;
    // Не invalidate: append-one bake в следующем drawAllStrokes (плавно, без full replay)
    schedulerRef.current?.schedule(() => drawAllStrokesRef.current());
    schedulerRef.current?.schedule(() => drawOverlayRef.current());
  };

  const handlePointerLeave = (e: React.PointerEvent<HTMLCanvasElement>) => {
    hoverPointRef.current = null;
    handlePointerUp(e);
  };

  return (
    <div
      ref={containerRef}
      className="w-full h-full relative touch-none"
      style={{ backgroundColor: fillColor }}
    >
      <canvas
        id="mandala-canvas"
        ref={canvasRef}
        className="absolute inset-0 z-0"
        style={{ backgroundColor: fillColor }}
      />
      <canvas
        ref={dynamicCanvasRef}
        className={`absolute inset-0 z-10 ${
          isSpacePressed ? (isPanning ? 'cursor-grabbing' : 'cursor-grab') : 'cursor-none'
        }`}
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerLeave={handlePointerLeave}
        onContextMenu={e => e.preventDefault()}
      />
    </div>
  );
}
