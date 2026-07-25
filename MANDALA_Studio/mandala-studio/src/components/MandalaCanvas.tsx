import React, { useRef, useEffect, useState, useCallback } from 'react';
import { MandalaSettings, Point, Stroke } from '../types';

interface MandalaCanvasProps {
  settings: MandalaSettings;
  mode: 'TEMPLATE' | 'WORKSPACE';
  activeColor: string;
  tool: 'brush' | 'dots';
  onAddStroke: (stroke: Stroke) => void;
  strokes: Stroke[];
}

export const MandalaCanvas: React.FC<MandalaCanvasProps> = ({
  settings,
  mode,
  activeColor,
  tool,
  onAddStroke,
  strokes,
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [isDrawing, setIsDrawing] = useState(false);
  const [currentPoints, setCurrentPoints] = useState<Point[]>([]);

  // Draw the mathematical template
  const drawTemplate = useCallback((ctx: CanvasRenderingContext2D, width: number, height: number) => {
    const cx = width / 2;
    const cy = height / 2;
    const maxRadius = Math.min(width, height) / 2 * 0.9;

    ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
    ctx.lineWidth = 1;

    // 1. Grid Lines (Sections)
    if (settings.showGridLines) {
      for (let i = 0; i < settings.sections; i++) {
        const angle = (i * 2 * Math.PI) / settings.sections;
        ctx.beginPath();
        ctx.moveTo(cx, cy);
        ctx.lineTo(
          cx + Math.cos(angle) * maxRadius,
          cy + Math.sin(angle) * maxRadius
        );
        ctx.stroke();
      }
    }

    // 2. Concentric Rings
    if (settings.showRings) {
      for (let j = 1; j <= settings.rings; j++) {
        const r = (j * maxRadius) / settings.rings;
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, 2 * Math.PI);
        ctx.stroke();
      }
    }

    // 3. Rose Curve (Petals)
    if (settings.showPetals) {
      ctx.strokeStyle = 'rgba(68, 226, 205, 0.4)'; // secondary color
      ctx.lineWidth = 2;
      ctx.beginPath();
      // Plotting the Rhodonea curve: r = a * cos(k * theta)
      // k = settings.petalFrequency
      // a = settings.petalLength (as percentage of maxRadius)
      const a = (settings.petalLength / 100) * maxRadius;
      const k = settings.petalFrequency;
      
      for (let theta = 0; theta < 2 * Math.PI; theta += 0.01) {
        const r = a * Math.cos(k * theta);
        const x = cx + r * Math.cos(theta);
        const y = cy + r * Math.sin(theta);
        if (theta === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.closePath();
      ctx.stroke();
    }

    // 4. Logarithmic Spiral: r = a * e^(b * theta)
    if (settings.showSpiral) {
      ctx.strokeStyle = 'rgba(206, 189, 255, 0.3)'; // tertiary color
      ctx.lineWidth = 1.5;
      const b = settings.spiralGrowth / 10;
      const a = 10; // start size
      
      for (let i = 0; i < settings.sections; i++) {
        const startAngle = (i * 2 * Math.PI) / settings.sections;
        ctx.beginPath();
        for (let theta = 0; theta < Math.PI * 4; theta += 0.1) {
          const r = a * Math.exp(b * theta);
          if (r > maxRadius) break;
          const x = cx + r * Math.cos(theta + startAngle);
          const y = cy + r * Math.sin(theta + startAngle);
          if (theta === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        ctx.stroke();
      }
    }
  }, [settings]);

  // Draw user strokes with symmetry
  const drawStrokes = useCallback((ctx: CanvasRenderingContext2D, width: number, height: number) => {
    const cx = width / 2;
    const cy = height / 2;

    const renderStroke = (stroke: Stroke) => {
      ctx.strokeStyle = stroke.color;
      ctx.fillStyle = stroke.color;
      ctx.lineCap = 'round';
      ctx.lineJoin = 'round';

      for (let i = 0; i < stroke.sections; i++) {
        const angleOffset = (i * 2 * Math.PI) / stroke.sections;

        // Draw normal rotated stroke
        const drawSymmetry = (isReflected: boolean) => {
          if (stroke.type === 'brush') {
            ctx.lineWidth = stroke.size;
            ctx.beginPath();
            stroke.points.forEach((p, idx) => {
              let relX = p.x - cx;
              let relY = p.y - cy;
              
              if (isReflected) {
                // To reflect across the axis of the segment:
                // We rotate the point back, flip it, then rotate it forward manually, 
                // but simpler: just flip Y before applying the segment rotation.
                // However, for dihedral symmetry, we usually reflect across the sector mid-line.
                // Let's use a simpler reflection for now:
                const tempX = relX;
                relX = relX * Math.cos(0) + relY * Math.sin(0); // unchanged
                relY = -relY;
              }

              const rx = relX * Math.cos(angleOffset) - relY * Math.sin(angleOffset);
              const ry = relX * Math.sin(angleOffset) + relY * Math.cos(angleOffset);
              
              if (idx === 0) ctx.moveTo(cx + rx, cy + ry);
              else ctx.lineTo(cx + rx, cy + ry);
            });
            ctx.stroke();
          } else if (stroke.type === 'dots') {
            const numPoints = stroke.points.length;
            stroke.points.forEach((p, idx) => {
              let relX = p.x - cx;
              let relY = p.y - cy;

              if (isReflected) relY = -relY;

              const rx = relX * Math.cos(angleOffset) - relY * Math.sin(angleOffset);
              const ry = relX * Math.sin(angleOffset) + relY * Math.cos(angleOffset);

              const progress = numPoints > 1 ? idx / (numPoints - 1) : 0.5;
              const minR = 2;
              const maxR = stroke.size;
              const dotRadius = minR + (maxR - minR) * Math.sin(Math.PI * progress);

              ctx.beginPath();
              ctx.arc(cx + rx, cy + ry, dotRadius, 0, Math.PI * 2);
              ctx.fill();
            });
          }
        };

        drawSymmetry(false);
        if (settings.reflect) {
          drawSymmetry(true);
        }
      }
    };

    strokes.forEach(renderStroke);

    // Current stroke being drawn
    if (isDrawing && currentPoints.length > 0) {
      renderStroke({
        points: currentPoints,
        color: activeColor,
        size: tool === 'dots' ? 12 : 5,
        type: tool,
        sections: settings.sections
      });
    }
  }, [strokes, isDrawing, currentPoints, activeColor, tool, settings.sections]);

  // Main Render Loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animationFrameId: number;

    const handleResize = () => {
      const dpr = window.devicePixelRatio || 1;
      const rect = canvas.getBoundingClientRect();
      canvas.width = rect.width * dpr;
      canvas.height = rect.height * dpr;
      ctx.setTransform(1, 0, 0, 1, 0, 0); // clear scale
      ctx.scale(dpr, dpr);
    };

    const resizeObserver = new ResizeObserver(() => {
      handleResize();
    });
    resizeObserver.observe(canvas.parentElement || canvas);

    const render = () => {
      const rect = canvas.getBoundingClientRect();
      ctx.clearRect(0, 0, rect.width, rect.height);
      
      // Draw background (dark)
      ctx.fillStyle = '#051424';
      ctx.fillRect(0, 0, rect.width, rect.height);

      drawTemplate(ctx, rect.width, rect.height);
      drawStrokes(ctx, rect.width, rect.height);
      
      animationFrameId = requestAnimationFrame(render);
    };

    handleResize();
    animationFrameId = requestAnimationFrame(render);

    return () => {
      resizeObserver.disconnect();
      cancelAnimationFrame(animationFrameId);
    };
  }, [drawTemplate, drawStrokes]);

  const handlePointerDown = (e: React.PointerEvent) => {
    if (mode === 'TEMPLATE') return;
    setIsDrawing(true);
    const rect = canvasRef.current?.getBoundingClientRect();
    if (rect) {
      setCurrentPoints([{ x: e.clientX - rect.left, y: e.clientY - rect.top }]);
    }
  };

  const handlePointerMove = (e: React.PointerEvent) => {
    if (!isDrawing) return;
    const rect = canvasRef.current?.getBoundingClientRect();
    if (rect) {
      const newPoint = { x: e.clientX - rect.left, y: e.clientY - rect.top };
      
      // For dots, we might want to space them out
      if (tool === 'dots') {
        const lastPoint = currentPoints[currentPoints.length - 1];
        const dist = Math.sqrt(Math.pow(newPoint.x - lastPoint.x, 2) + Math.pow(newPoint.y - lastPoint.y, 2));
        if (dist < 10) return; // threshold to prevent dot overlap cluster
      }

      setCurrentPoints(prev => [...prev, newPoint]);
    }
  };

  const handlePointerUp = () => {
    if (!isDrawing) return;
    setIsDrawing(false);
    if (currentPoints.length > 0) {
      onAddStroke({
        points: currentPoints,
        color: activeColor,
        size: tool === 'dots' ? 12 : 5,
        type: tool,
        sections: settings.sections
      });
    }
    setCurrentPoints([]);
  };

  return (
    <canvas
      ref={canvasRef}
      className="w-full h-full cursor-crosshair touch-none overflow-hidden"
      onPointerDown={handlePointerDown}
      onPointerMove={handlePointerMove}
      onPointerUp={handlePointerUp}
      onPointerLeave={handlePointerUp}
    />
  );
};
