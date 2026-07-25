/**
 * RenderScheduler — планировщик рендера на requestAnimationFrame.
 *
 * Устраняет множественные рендеры за один кадр (узкое место #6 из ARCHITECTURE_PLAN.md):
 * при быстром движении мыши или одновременном изменении currentPoints / hoverPoint / pan
 * несколько вызовов schedule() за один кадр сводятся к одному RAF и одному набору отрисовок.
 */

type DrawFn = () => void;

const raf: (cb: FrameRequestCallback) => number =
  typeof requestAnimationFrame === 'function'
    ? requestAnimationFrame
    : (cb) => window.setTimeout(() => cb(performance.now()), 16) as unknown as number;

const caf: (id: number) => void =
  typeof cancelAnimationFrame === 'function'
    ? cancelAnimationFrame
    : (id) => window.clearTimeout(id);

export class RenderScheduler {
  private rafId: number | null = null;
  private dirtyLayers: Set<DrawFn> = new Set();

  /**
   * Регистрирует функцию отрисовки и помечает её как "грязную".
   * Если за кадр пришло несколько schedule(), RAF планируется только один раз.
   */
  schedule(drawFn: DrawFn): void {
    this.dirtyLayers.add(drawFn);
    if (this.rafId === null) {
      this.rafId = raf(this.flush);
    }
  }

  /**
   * Запускает все dirty-функции в одном RAF.
   * Снимок множества делается до вызова, чтобы функции могли безопасно
   * перепланировать себя на следующий кадр (рекурсивный schedule внутри flush).
   */
  private flush = (): void => {
    this.rafId = null;
    const layers = Array.from(this.dirtyLayers);
    this.dirtyLayers.clear();

    for (const fn of layers) {
      try {
        fn();
      } catch (err) {
        console.error('[RenderScheduler] draw function failed:', err);
      }
    }
  };

  /**
   * Принудительный синхронный рендер (для экспорта или тестов):
   * отменяет отложенный RAF и выполняет все запланированные функции немедленно.
   */
  flushNow(): void {
    if (this.rafId !== null) {
      caf(this.rafId);
      this.rafId = null;
    }
    const layers = Array.from(this.dirtyLayers);
    this.dirtyLayers.clear();

    for (const fn of layers) {
      try {
        fn();
      } catch (err) {
        console.error('[RenderScheduler] draw function failed:', err);
      }
    }
  }

  /**
   * Отменяет все запланированные рендеры (вызывать при размонтировании компонента).
   */
  cancel(): void {
    if (this.rafId !== null) {
      caf(this.rafId);
      this.rafId = null;
    }
    this.dirtyLayers.clear();
  }
}
