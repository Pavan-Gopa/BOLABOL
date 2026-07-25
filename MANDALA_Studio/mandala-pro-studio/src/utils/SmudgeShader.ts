/**
 * SmudgeShader — WebGL2 fragment shader для эффекта smudge (узкое место #3).
 *
 * M3 (ROI / session): вместо полной загрузки холста и fullscreen-прохода на
 * каждый сегмент (Canvas 2D копия + клип, либо WebGL re-upload всего холста)
 * шейдер живёт сессией ОДНОГО штриха:
 *   beginStroke — ровно ОДИН раз загружает исходник в texA;
 *   stamp       — рисует ТОЛЬКО bbox кисти (gl.scissor), GPU-состояние живёт
 *                 между штампами в texA (ping-pong + blit региона);
 *   endStroke   — возвращает union dirty-регионов для коммита в EffectLayer.
 *
 * Никакого per-stamp upload и никакого fullscreen-прохода на каждый сегмент.
 */

import { Point } from '../types';

export interface DirtyRect {
  x: number;
  y: number;
  w: number;
  h: number;
}

const VERT_SRC = `#version 300 es
in vec2 a_position;
void main() {
  gl_Position = vec4(a_position, 0.0, 1.0);
}`;

const FRAG_SRC = `#version 300 es
precision highp float;

uniform sampler2D u_source;
uniform vec2 u_resolution;
uniform vec2 u_pointPrev;
uniform vec2 u_pointCurr;
uniform float u_brushRadius;
uniform float u_strength;

out vec4 fragColor;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 pos = gl_FragCoord.xy;

  float dist = distance(pos, u_pointCurr);
  if (dist > u_brushRadius) {
    fragColor = texture(u_source, uv);
    return;
  }

  vec2 delta = u_pointCurr - u_pointPrev;
  vec2 dir = vec2(0.0, 0.0);
  if (length(delta) > 0.0001) {
    dir = normalize(delta);
  }
  vec2 sampleOffset = dir * (u_brushRadius * 0.3) * u_strength;
  vec2 sampleUV = uv + sampleOffset / u_resolution;

  float mask = 1.0 - smoothstep(0.0, u_brushRadius, dist);
  mask = pow(mask, 2.0);

  vec4 original = texture(u_source, uv);
  vec4 sampled = texture(u_source, sampleUV);

  fragColor = mix(original, sampled, mask * u_strength);
}`;

export class SmudgeShader {
  private gl: WebGL2RenderingContext | null;
  private program: WebGLProgram | null = null;
  private quadBuffer: WebGLBuffer | null = null;
  private aPositionLoc = -1;

  private uSource: WebGLUniformLocation | null = null;
  private uResolution: WebGLUniformLocation | null = null;
  private uPointPrev: WebGLUniformLocation | null = null;
  private uPointCurr: WebGLUniformLocation | null = null;
  private uBrushRadius: WebGLUniformLocation | null = null;
  private uStrength: WebGLUniformLocation | null = null;

  // Ping-pong текстуры + framebuffer'ы (texA — авторитетное состояние штриха).
  private texA: WebGLTexture | null = null;
  private texB: WebGLTexture | null = null;
  private fboA: WebGLFramebuffer | null = null;
  private fboB: WebGLFramebuffer | null = null;

  private glCanvas: HTMLCanvasElement;
  private outCanvas: HTMLCanvasElement;
  private width = 0;
  private height = 0;

  // Union dirty-регионов за сессию (device-пиксели, y-down).
  private accumRect: DirtyRect | null = null;

  constructor(canvas: HTMLCanvasElement) {
    // WebGL рендерит в собственный offscreen-холст (canvas может иметь только один тип контекста)
    this.glCanvas = document.createElement('canvas');
    this.outCanvas = document.createElement('canvas');
    const gl = this.glCanvas.getContext('webgl2', {
      premultipliedAlpha: false,
      preserveDrawingBuffer: true
    });
    this.gl = gl;
    if (!gl) return;

    this.program = this.createProgram(gl, VERT_SRC, FRAG_SRC);
    if (!this.program) {
      this.gl = null;
      return;
    }

    this.quadBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, this.quadBuffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([
        -1, -1, 1, -1, -1, 1,
        -1, 1, 1, -1, 1, 1
      ]),
      gl.STATIC_DRAW
    );
    this.aPositionLoc = gl.getAttribLocation(this.program, 'a_position');

    this.uSource = gl.getUniformLocation(this.program, 'u_source');
    this.uResolution = gl.getUniformLocation(this.program, 'u_resolution');
    this.uPointPrev = gl.getUniformLocation(this.program, 'u_pointPrev');
    this.uPointCurr = gl.getUniformLocation(this.program, 'u_pointCurr');
    this.uBrushRadius = gl.getUniformLocation(this.program, 'u_brushRadius');
    this.uStrength = gl.getUniformLocation(this.program, 'u_strength');
  }

  private createProgram(gl: WebGL2RenderingContext, vsrc: string, fsrc: string): WebGLProgram | null {
    const vs = this.compileShader(gl, gl.VERTEX_SHADER, vsrc);
    const fs = this.compileShader(gl, gl.FRAGMENT_SHADER, fsrc);
    if (!vs || !fs) return null;
    const prog = gl.createProgram();
    if (!prog) return null;
    gl.attachShader(prog, vs);
    gl.attachShader(prog, fs);
    gl.linkProgram(prog);
    if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      console.error('[SmudgeShader] link failed:', gl.getProgramInfoLog(prog));
      return null;
    }
    return prog;
  }

  private compileShader(gl: WebGL2RenderingContext, type: number, src: string): WebGLShader | null {
    const sh = gl.createShader(type);
    if (!sh) return null;
    gl.shaderSource(sh, src);
    gl.compileShader(sh);
    if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
      console.error('[SmudgeShader] compile failed:', gl.getShaderInfoLog(sh));
      return null;
    }
    return sh;
  }

  private ensureTargets(gl: WebGL2RenderingContext, w: number, h: number): void {
    if (this.width === w && this.height === h && this.texA && this.texB) return;
    this.width = w;
    this.height = h;
    this.glCanvas.width = w;
    this.glCanvas.height = h;
    this.outCanvas.width = w;
    this.outCanvas.height = h;

    this.disposeTargets(gl);

    this.texA = this.createTexture(gl, w, h);
    this.texB = this.createTexture(gl, w, h);
    this.fboA = this.createFramebuffer(gl, this.texA);
    this.fboB = this.createFramebuffer(gl, this.texB);
  }

  private createTexture(gl: WebGL2RenderingContext, w: number, h: number): WebGLTexture | null {
    const tex = gl.createTexture();
    if (!tex) return null;
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
    return tex;
  }

  private createFramebuffer(gl: WebGL2RenderingContext, tex: WebGLTexture | null): WebGLFramebuffer | null {
    if (!tex) return null;
    const fbo = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
    return fbo;
  }

  private uploadSource(gl: WebGL2RenderingContext, src: HTMLCanvasElement, tex: WebGLTexture | null): void {
    if (!tex) return;
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, src);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
  }

  /** Результат сессии (offscreen 2D-холст, device-пиксели) — для блита на main. */
  getOutputCanvas(): HTMLCanvasElement {
    return this.outCanvas;
  }

  /**
   * M3: начать сессию штриха. Ровно ОДИН раз загружает исходник в texA.
   * @returns false, если WebGL недоступен / холст пуст.
   */
  beginStroke(sourceCanvas: HTMLCanvasElement): boolean {
    const gl = this.gl;
    if (!gl || !this.program) return false;

    const w = sourceCanvas.width;
    const h = sourceCanvas.height;
    if (w === 0 || h === 0) return false;

    this.ensureTargets(gl, w, h);
    if (!this.texA || !this.fboA) return false;

    // Исходник загружаем в texA (с переворотом Y под GL-конвенцию uv).
    this.uploadSource(gl, sourceCanvas, this.texA);
    this.accumRect = null;
    return true;
  }

  /**
   * M3: отштамповать один сегмент вдоль ВСЕХ симметричных путей.
   * Только bbox кисти (gl.scissor); GPU-состояние живёт в texA между штампами.
   * @returns dirty-регион (device-пиксели, y-down) этого штампа.
   */
  stamp(segments: Point[][], brushSize: number, opacity: number, smudgeStrength: number): DirtyRect | null {
    const gl = this.gl;
    if (!gl || !this.program || !this.texA || !this.texB || !this.fboA || !this.fboB) return null;

    const w = this.width;
    const h = this.height;

    // Базовый bbox (device px, y-down) по всем точкам + радиус кисти.
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const path of segments) {
      for (const p of path) {
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
      }
    }
    if (!isFinite(minX)) return null;

    const r = Math.max(0.0001, brushSize);
    const bx = Math.max(0, Math.floor(minX - r));
    const by = Math.max(0, Math.floor(minY - r));
    const bx2 = Math.min(w, Math.ceil(maxX + r));
    const by2 = Math.min(h, Math.ceil(maxY + r));
    const bw = bx2 - bx;
    const bh = by2 - by;
    if (bw <= 0 || bh <= 0) return null;

    // GL-координаты scissor (y-up).
    const gx = bx;
    const gy = h - by - bh;
    const gw = bw;
    const gh = bh;

    const strength = smudgeStrength * (opacity / 100);
    const radius = r;

    gl.useProgram(this.program);
    gl.bindBuffer(gl.ARRAY_BUFFER, this.quadBuffer);
    gl.enableVertexAttribArray(this.aPositionLoc);
    gl.vertexAttribPointer(this.aPositionLoc, 2, gl.FLOAT, false, 0, 0);
    gl.uniform1i(this.uSource, 0);
    gl.uniform2f(this.uResolution, w, h);
    gl.uniform1f(this.uBrushRadius, radius);
    gl.uniform1f(this.uStrength, strength);
    gl.activeTexture(gl.TEXTURE0);
    gl.viewport(0, 0, w, h);

    for (const path of segments) {
      for (let i = 1; i < path.length; i++) {
        const prev = path[i - 1];
        const curr = path[i];
        // В GL origin — bottom-left: переворачиваем Y
        const prevX = prev.x;
        const prevY = h - prev.y;
        const currX = curr.x;
        const currY = h - curr.y;

        // read texA -> write texB (scissor = bbox кисти)
        gl.bindFramebuffer(gl.FRAMEBUFFER, this.fboB);
        gl.enable(gl.SCISSOR_TEST);
        gl.scissor(gx, gy, gw, gh);
        gl.bindTexture(gl.TEXTURE_2D, this.texA);
        gl.uniform2f(this.uPointPrev, prevX, prevY);
        gl.uniform2f(this.uPointCurr, currX, currY);
        gl.drawArrays(gl.TRIANGLES, 0, 6);

        // скопировать регион texB -> texA (authoritative state для следующего штампа)
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, this.fboB);
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, this.fboA);
        gl.blitFramebuffer(gx, gy, gx + gw, gy + gh, gx, gy, gx + gw, gy + gh, gl.COLOR_BUFFER_BIT, gl.NEAREST);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        gl.disable(gl.SCISSOR_TEST);
      }
    }

    // Скопировать texA → default framebuffer → outCanvas (только dirty ROI).
    gl.disable(gl.SCISSOR_TEST);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, w, h);
    gl.useProgram(this.program);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texA);
    gl.uniform1f(this.uStrength, 0);
    gl.uniform2f(this.uPointCurr, 0, 0);
    gl.uniform2f(this.uPointPrev, 0, 0);
    // Full draw (strength=0 = copy). Scissor to dirty ROI for speed.
    gl.enable(gl.SCISSOR_TEST);
    gl.scissor(gx, gy, gw, gh);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
    gl.disable(gl.SCISSOR_TEST);

    const outCtx = this.outCanvas.getContext('2d');
    if (outCtx) {
      // Копируем только dirty-прямоугольник — не clearRect всего out (артефакты/мигание).
      outCtx.drawImage(this.glCanvas, bx, by, bw, bh, bx, by, bw, bh);
    }

    const rect: DirtyRect = { x: bx, y: by, w: bw, h: bh };
    if (!this.accumRect) {
      this.accumRect = { ...rect };
    } else {
      const a = this.accumRect;
      const ax2 = a.x + a.w;
      const ay2 = a.y + a.h;
      const rx2 = bx + bw;
      const ry2 = by + bh;
      a.x = Math.min(a.x, bx);
      a.y = Math.min(a.y, by);
      a.w = Math.max(ax2, rx2) - a.x;
      a.h = Math.max(ay2, ry2) - a.y;
    }
    return rect;
  }

  /** M3: завершить сессию, вернуть union dirty-регионов (device px, y-down). */
  endStroke(): DirtyRect | null {
    const r = this.accumRect;
    this.accumRect = null;
    return r;
  }

  dispose(): void {
    const gl = this.gl;
    if (!gl) return;
    this.disposeTargets(gl);
    if (this.quadBuffer) gl.deleteBuffer(this.quadBuffer);
    if (this.program) gl.deleteProgram(this.program);
    this.quadBuffer = null;
    this.program = null;
    this.gl = null;
  }

  private disposeTargets(gl: WebGL2RenderingContext): void {
    if (this.texA) gl.deleteTexture(this.texA);
    if (this.texB) gl.deleteTexture(this.texB);
    if (this.fboA) gl.deleteFramebuffer(this.fboA);
    if (this.fboB) gl.deleteFramebuffer(this.fboB);
    this.texA = null;
    this.texB = null;
    this.fboA = null;
    this.fboB = null;
  }
}
