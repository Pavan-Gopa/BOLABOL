/**
 * SpatialHash — grid-based пространственный индекс для ускорения поиска
 * ближайшей точки направляющих при snapping (узкое место #4).
 *
 * Вместо линейного перебора всех guide points (до 5,000) при каждом движении
 * мыши — хеш по ячейкам ~20px, поиск ближайшей точки среди ~10 соседей (3×3 ячейки).
 */

import { Point } from '../types';

export interface NearestResult {
  point: Point;
  distance: number;
}

export class SpatialHash {
  private grid: Map<string, Point[]> = new Map();
  private cellSize: number;

  constructor(cellSize: number = 20) {
    this.cellSize = cellSize;
  }

  private cellCoord(v: number): number {
    return Math.floor(v / this.cellSize);
  }

  private key(cx: number, cy: number): string {
    return `${cx},${cy}`;
  }

  /** Построение индекса из массива точек. */
  build(points: Point[]): void {
    this.clear();
    for (let i = 0; i < points.length; i++) {
      const p = points[i];
      const cx = this.cellCoord(p.x);
      const cy = this.cellCoord(p.y);
      const k = this.key(cx, cy);
      const bucket = this.grid.get(k);
      if (bucket) {
        bucket.push(p);
      } else {
        this.grid.set(k, [p]);
      }
    }
  }

  /** Точки в 3×3 ячейках вокруг (x, y). */
  query(x: number, y: number): Point[] {
    const cx = this.cellCoord(x);
    const cy = this.cellCoord(y);
    const result: Point[] = [];
    for (let dx = -1; dx <= 1; dx++) {
      for (let dy = -1; dy <= 1; dy++) {
        const bucket = this.grid.get(this.key(cx + dx, cy + dy));
        if (bucket) {
          for (let i = 0; i < bucket.length; i++) result.push(bucket[i]);
        }
      }
    }
    return result;
  }

  /** Точки в радиусе r (поиск по охватывающим ячейкам + точная фильтрация). */
  queryRadius(x: number, y: number, r: number): Point[] {
    const cells = Math.max(1, Math.ceil(r / this.cellSize));
    const cx = this.cellCoord(x);
    const cy = this.cellCoord(y);
    const r2 = r * r;
    const result: Point[] = [];
    for (let dx = -cells; dx <= cells; dx++) {
      for (let dy = -cells; dy <= cells; dy++) {
        const bucket = this.grid.get(this.key(cx + dx, cy + dy));
        if (!bucket) continue;
        for (let i = 0; i < bucket.length; i++) {
          const p = bucket[i];
          const ddx = p.x - x;
          const ddy = p.y - y;
          if (ddx * ddx + ddy * ddy <= r2) result.push(p);
        }
      }
    }
    return result;
  }

  /** Ближайшая точка среди точек в 3×3 ячейках (null, если поблизости нет). */
  nearest(x: number, y: number): NearestResult | null {
    const candidates = this.query(x, y);
    let best: Point | null = null;
    let bestDist = Infinity;
    for (let i = 0; i < candidates.length; i++) {
      const p = candidates[i];
      const ddx = p.x - x;
      const ddy = p.y - y;
      const d = Math.sqrt(ddx * ddx + ddy * ddy);
      if (d < bestDist) {
        bestDist = d;
        best = p;
      }
    }
    if (best === null) return null;
    return { point: best, distance: bestDist };
  }

  clear(): void {
    this.grid.clear();
  }
}
