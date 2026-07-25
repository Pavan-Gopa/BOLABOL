/**
 * BlurShader — WebGL2 two-pass Gaussian blur для эффекта blur (узкое место #3).
 *
 * M3 (ROI / session): вместо CPU `ctx.filter = 'blur(Xpx)'` per-step и вместо
 * WebGL re-upload всего холста на каждый штамп — сессия ОДНОГО штриха:
 *   beginStroke — ровно ОДИН раз загружает исходник в texA (+ texOrig для mask);
 *   stamp       — для каждой точки два прохода (H затем V) ТОЛЬКО в bbox кисти
 *                 (gl.scissor); GPU-состояние живёт в texA между штампами;
 *   endStroke   — возвращает union dirty-регионов для коммита в EffectLayer.
 *
 * Структура зеркальна SmudgeShader.ts (ping-pong + blit региона, FLIP_Y).
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

// Horizontal pass: 9-tap Gaussian вдоль оси X. Без маски — чистое размытие.
const FRAG_H_SRC = `#version 300 es
precision highp float;

uniform sampler2D u_source;
uniform vec2 u_resolution;
uniform float u_blurRadius;

out vec4 fragColor;

const float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 texelSize = 1.0 / u_resolution;

  vec4 result = texture(u_source, uv) * weights[0];
  for (int i = 1; i < 5; i++) {
    result += texture(u_source, uv + vec2(float(i) * u_blurRadius, 0.0) * texelSize) * weights[i];
    result += texture(u_source, uv - vec2(float(i) * u_blurRadius, 0.0) * texelSize) * weights[i];
  }

  fragColor = result;
}`;

// Vertical pass: 9-tap Gaussian вдоль оси Y + маска кисти, смешивание с исходником.
const FRAG_V_SRC = `#version 300 es
precision highp float;

uniform sampler2D u_source;     // результат horizontal pass
uniform sampler2D u_original;   // исходный холст (для mask mix)
uniform vec2 u_resolution;
uniform float u_blurRadius;
uniform vec2 u_brushCenter;
uniform float u_brushSize;
uniform float u_opacity;

out vec4 fragColor;

const float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 texelSize = 1.0 / u_resolution;

  vec4 result = texture(u_source, uv) * weights[0];
  for (int i = 1; i < 5; i++) {
    result += texture(u_source, uv + vec2(0.0, float(i) * u_blurRadius) * texelSize) * weights[i];
    result += texture(u_source, uv - vec2(0.0, float(i) * u_blurRadius) * texelSize) * weights[i];
  }

  float dist = distance(gl_FragCoord.xy, u_brushCenter);
  float mask = 1.0 - smoothstep(0.0, u_brushSize, dist);
  mask = pow(mask, 2.0) * u_opacity;

  vec4 original = texture(u_original, uv);
  fragColor = mix(original, result, mask);
}`;

export class BlurShader {
  private gl: WebGL2RenderingContext | null;
  private hProgram: WebGLProgram | null = null;
  private vProgram: WebGLProgram | null = null;
  private quadBuffer: WebGLBuffer | null = null;
  private aPositionLocH = -1;
  private aPositionLocV = -1;

  // Horizontal pass uniforms
  private uHSource: WebGLUniformLocation | null = null;
  private uHResolution: WebGLUniformLocation | null = null;
  private uHBlurRadius: WebGLUniformLocation | null = null;

  // Vertical pass uniforms
  private uVSource: WebGLUniformLocation | null = null;
  private uVOriginal: WebGLUniformLocation | null = null;
  private uVResolution: WebGLUniformLocation | null = null;
  private uVBlurRadius: WebGLUniformLocation | null = null;
  private uVBrushCenter: WebGLUniformLocation | null = null;
  private uVBrushSize: WebGLUniformLocation | null = null;
  private uVOpacity: WebGLUniformLocation | null = null;

  // Ping-pong текстуры + framebuffer'ы + статичный исходник
  private texA: WebGLTexture | null = null;
  private texB: WebGLTexture | null = null;
  private texOrig: WebGLTexture | null = null;
  private fboA: WebGLFramebuffer | null = null;
  private fboB: WebGLFramebuffer | null = null;

  private glCanvas: HTMLCanvasElement;
  private outCanvas: HTMLCanvasElement;
  private width = 0;
  private height = 0;

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

    this.hProgram = this.createProgram(gl, VERT_SRC, FRAG_H_SRC);
    this.vProgram = this.createProgram(gl, VERT_SRC, FRAG_V_SRC);
    if (!this.hProgram || !this.vProgram) {
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
    this.aPositionLocH = gl.getAttribLocation(this.hProgram, 'a_position');
    this.aPositionLocV = gl.getAttribLocation(this.vProgram, 'a_position');

    this.uHSource = gl.getUniformLocation(this.hProgram, 'u_source');
    this.uHResolution = gl.getUniformLocation(this.hProgram, 'u_resolution');
    this.uHBlurRadius = gl.getUniformLocation(this.hProgram, 'u_blurRadius');

    this.uVSource = gl.getUniformLocation(this.vProgram, 'u_source');
    this.uVOriginal = gl.getUniformLocation(this.vProgram, 'u_original');
    this.uVResolution = gl.getUniformLocation(this.vProgram, 'u_resolution');
    this.uVBlurRadius = gl.getUniformLocation(this.vProgram, 'u_blurRadius');
    this.uVBrushCenter = gl.getUniformLocation(this.vProgram, 'u_brushCenter');
    this.uVBrushSize = gl.getUniformLocation(this.vProgram, 'u_brushSize');
    this.uVOpacity = gl.getUniformLocation(this.vProgram, 'u_opacity');
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
      console.error('[BlurShader] link failed:', gl.getProgramInfoLog(prog));
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
      console.error('[BlurShader] compile failed:', gl.getShaderInfoLog(sh));
      return null;
    }
    return sh;
  }

  private ensureTargets(gl: WebGL2RenderingContext, w: number, h: number): void {
    if (this.width === w && this.height === h && this.texA && this.texB && this.texOrig) return;
    this.width = w;
    this.height = h;
    this.glCanvas.width = w;
    this.glCanvas.height = h;
    this.outCanvas.width = w;
    this.outCanvas.height = h;

    this.disposeTargets(gl);

    this.texA = this.createTexture(gl, w, h);
    this.texB = this.createTexture(gl, w, h);
    this.texOrig = this.createTexture(gl, w, h);
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
   * M3: начать сессию штриха. Ровно ОДИН раз загружает исходник в texA и texOrig.
   * @returns false, если WebGL недоступен / холст пуст.
   */
  beginStroke(sourceCanvas: HTMLCanvasElement): boolean {
    const gl = this.gl;
    if (!gl || !this.hProgram || !this.vProgram) return false;

    const w = sourceCanvas.width;
    const h = sourceCanvas.height;
    if (w === 0 || h === 0) return false;

    this.ensureTargets(gl, w, h);
    if (!this.texA || !this.texB || !this.texOrig || !this.fboA || !this.fboB) return false;

    // Исходник загружаем в texA (рабочее состояние) и в статичный texOrig (для mask mix).
    this.uploadSource(gl, sourceCanvas, this.texA);
    this.uploadSource(gl, sourceCanvas, this.texOrig);
    this.accumRect = null;
    return true;
  }

  /**
   * M3: отштамповать сегмент — для каждой точки два прохода (H затем V) вдоль
   * ВСЕХ симметричных путей, ограниченно bbox кисти (gl.scissor).
   * @returns dirty-регион (device-пиксели, y-down) этого штампа.
   */
  stamp(segments: Point[][], brushSize: number, blurRadius: number, opacity: number): DirtyRect | null {
    const gl = this.gl;
    if (!gl || !this.hProgram || !this.vProgram || !this.texA || !this.texB || !this.texOrig || !this.fboA || !this.fboB) return null;

    const w = this.width;
    const h = this.height;

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

    const size = Math.max(0.0001, brushSize);
    const bx = Math.max(0, Math.floor(minX - size));
    const by = Math.max(0, Math.floor(minY - size));
    const bx2 = Math.min(w, Math.ceil(maxX + size));
    const by2 = Math.min(h, Math.ceil(maxY + size));
    const bw = bx2 - bx;
    const bh = by2 - by;
    if (bw <= 0 || bh <= 0) return null;

    const gx = bx;
    const gy = h - by - bh;
    const gw = bw;
    const gh = bh;

    const op = opacity / 100;
    const radius = Math.max(0.0001, blurRadius);

    gl.bindBuffer(gl.ARRAY_BUFFER, this.quadBuffer);
    gl.enableVertexAttribArray(this.aPositionLocH);
    gl.vertexAttribPointer(this.aPositionLocH, 2, gl.FLOAT, false, 0, 0);
    gl.enableVertexAttribArray(this.aPositionLocV);
    gl.vertexAttribPointer(this.aPositionLocV, 2, gl.FLOAT, false, 0, 0);
    gl.viewport(0, 0, w, h);

    for (const path of segments) {
      for (let i = 0; i < path.length; i++) {
        const curr = path[i];
        // В GL origin — bottom-left: переворачиваем Y
        const currX = curr.x;
        const currY = h - curr.y;

        // --- Horizontal pass: texA -> texB ---
        gl.useProgram(this.hProgram);
        gl.bindFramebuffer(gl.FRAMEBUFFER, this.fboB);
        gl.enable(gl.SCISSOR_TEST);
        gl.scissor(gx, gy, gw, gh);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this.texA);
        gl.uniform1i(this.uHSource, 0);
        gl.uniform2f(this.uHResolution, w, h);
        gl.uniform1f(this.uHBlurRadius, radius);
        gl.drawArrays(gl.TRIANGLES, 0, 6);

        // скопировать регион texB -> texA
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, this.fboB);
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, this.fboA);
        gl.blitFramebuffer(gx, gy, gx + gw, gy + gh, gx, gy, gx + gw, gy + gh, gl.COLOR_BUFFER_BIT, gl.NEAREST);

        // --- Vertical pass: texA -> texB, mask-mix с исходником ---
        gl.useProgram(this.vProgram);
        gl.bindFramebuffer(gl.FRAMEBUFFER, this.fboB);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, this.texA);
        gl.uniform1i(this.uVSource, 0);
        gl.activeTexture(gl.TEXTURE1);
        gl.bindTexture(gl.TEXTURE_2D, this.texOrig);
        gl.uniform1i(this.uVOriginal, 1);
        gl.uniform2f(this.uVResolution, w, h);
        gl.uniform1f(this.uVBlurRadius, radius);
        gl.uniform2f(this.uVBrushCenter, currX, currY);
        gl.uniform1f(this.uVBrushSize, size);
        gl.uniform1f(this.uVOpacity, op);
        gl.drawArrays(gl.TRIANGLES, 0, 6);

        // скопировать регион texB -> texA (состояние снова в texA для следующей точки)
        gl.bindFramebuffer(gl.READ_FRAMEBUFFER, this.fboB);
        gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, this.fboA);
        gl.blitFramebuffer(gx, gy, gx + gw, gy + gh, gx, gy, gx + gw, gy + gh, gl.COLOR_BUFFER_BIT, gl.NEAREST);
        gl.bindFramebuffer(gl.FRAMEBUFFER, null);
        gl.disable(gl.SCISSOR_TEST);
      }
    }

    // Скопировать texA → default FB → outCanvas (только dirty ROI).
    gl.disable(gl.SCISSOR_TEST);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, w, h);
    gl.useProgram(this.vProgram);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texA);
    gl.uniform1i(this.uVSource, 0);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, this.texOrig);
    gl.uniform1i(this.uVOriginal, 1);
    gl.uniform2f(this.uVResolution, w, h);
    gl.uniform1f(this.uVBlurRadius, radius);
    gl.uniform2f(this.uVBrushCenter, 0, 0);
    gl.uniform1f(this.uVBrushSize, size);
    gl.uniform1f(this.uVOpacity, 0); // mask=0 → pure copy of texA via mix(original,result,0)? 
    // mix(original, result, 0) = original — НЕПРАВИЛЬНО для copy texA!
    // Используем horizontal program как простой sample copy:
    gl.useProgram(this.hProgram);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.texA);
    gl.uniform1i(this.uHSource, 0);
    gl.uniform2f(this.uHResolution, w, h);
    gl.uniform1f(this.uHBlurRadius, 0); // 9-tap with radius 0 ≈ center weight only-ish; better draw with strength copy
    gl.enable(gl.SCISSOR_TEST);
    gl.scissor(gx, gy, gw, gh);
    gl.drawArrays(gl.TRIANGLES, 0, 6);
    gl.disable(gl.SCISSOR_TEST);

    const outCtx = this.outCanvas.getContext('2d');
    if (outCtx) {
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
    if (this.hProgram) gl.deleteProgram(this.hProgram);
    if (this.vProgram) gl.deleteProgram(this.vProgram);
    this.quadBuffer = null;
    this.hProgram = null;
    this.vProgram = null;
    this.gl = null;
  }

  private disposeTargets(gl: WebGL2RenderingContext): void {
    if (this.texA) gl.deleteTexture(this.texA);
    if (this.texB) gl.deleteTexture(this.texB);
    if (this.texOrig) gl.deleteTexture(this.texOrig);
    if (this.fboA) gl.deleteFramebuffer(this.fboA);
    if (this.fboB) gl.deleteFramebuffer(this.fboB);
    this.texA = null;
    this.texB = null;
    this.texOrig = null;
    this.fboA = null;
    this.fboB = null;
  }
}
