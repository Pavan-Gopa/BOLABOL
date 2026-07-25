import { Point } from '../types';

/**
 * PathBatcher — батчинг GPU-вызовов отрисовки в один Path2D.
 *
 * Устраняет узкое место #2 (CanvasRenderer.tsx, vector brush): вместо
 * отдельного stroke() на каждый сегмент (200+ draw calls на штрих) группирует
 * последовательные точки по уровням толщины (pressure) и рисует один Path2D
 * на каждый уровень — 8 draw calls вместо 200.
 */

export interface BucketedPath {
  path: Path2D;
  width: number;
}

export class PathBatcher {
  /** Создаёт один Path2D из массива точек (непрерывная ломаная). */
  static buildPath(points: Point[]): Path2D {
    const path = new Path2D();
    if (points.length === 0) return path;
    path.moveTo(points[0].x, points[0].y);
    for (let i = 1; i < points.length; i++) {
      path.lineTo(points[i].x, points[i].y);
    }
    return path;
  }

  /**
   * Создаёт несколько Path2D по уровням толщины (pressure-sensitive).
   * 1. width для точки = baseSize * pressure
   * 2. округление до одного из `buckets` уровней
   * 3. группировка последовательных точек с одинаковым уровнем
   * 4. для каждой группы — один Path2D (moveTo/lineTo)
   * Каждая группа рисуется одним stroke(), что сокращает draw calls.
   */
  static buildPressureBatchedPaths(
    points: Point[],
    baseSize: number,
    buckets: number = 8
  ): BucketedPath[] {
    const result: BucketedPath[] = [];
    if (points.length < 2 || buckets < 1) return result;

    const bucketOf = (p: Point): number => {
      const w = baseSize * (p.pressure !== undefined ? p.pressure : 1.0);
      const norm = baseSize > 0 ? Math.max(0, Math.min(1, w / baseSize)) : 0;
      return Math.round(norm * (buckets - 1));
    };

    let runStart = 0;
    let runBucket = bucketOf(points[0]);

    const flushRun = (endExclusive: number) => {
      // Пропускаем вырожденные группы (< 2 точек = нет сегментов)
      if (endExclusive - runStart < 2) return;
      const path = new Path2D();
      path.moveTo(points[runStart].x, points[runStart].y);
      for (let i = runStart + 1; i < endExclusive; i++) {
        path.lineTo(points[i].x, points[i].y);
      }
      const width = (runBucket / (buckets - 1)) * baseSize;
      result.push({ path, width });
    };

    for (let i = 1; i < points.length; i++) {
      const b = bucketOf(points[i]);
      if (b !== runBucket) {
        flushRun(i);
        runStart = i - 1; // граничная точка включается в следующую группу (непрерывность)
        runBucket = b;
      }
    }
    flushRun(points.length);

    return result;
  }

  /** Для sketch brush — множественные офсеты в отдельных Path2D. */
  static buildSketchPath(
    points: Point[],
    offsets: { dx: number; dy: number; w: number }[]
  ): Path2D[] {
    return offsets.map(offset => {
      const path = new Path2D();
      if (points.length === 0) return path;
      const pres0 = points[0].pressure !== undefined ? points[0].pressure : 1.0;
      path.moveTo(points[0].x + offset.dx * pres0, points[0].y + offset.dy * pres0);
      for (let i = 1; i < points.length; i++) {
        const p = points[i];
        const pres = p.pressure !== undefined ? p.pressure : 1.0;
        path.lineTo(p.x + offset.dx * pres, p.y + offset.dy * pres);
      }
      return path;
    });
  }
}
