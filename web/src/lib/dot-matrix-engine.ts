const TAU = Math.PI * 2;

const K = {
  baseR: 1.3,
  minR: 1.35,
  fullR: 2.55,
  maxR: 3.1,
  levels: 18,
  floor: 0.07,
  emax: 1.45,
  minAlphaDark: 0.24,
  minAlphaLight: 0.4,
  inkLevels: 12,
  inkFadeStart: 0.18,
  inkBottomLight: 0.2,
  inkBottomDark: 0.26,
  bloomSprite: 64,
  bloomFloor: 0.42,
  bloomMin: 7,
  bloomMax: 15,
  bloomAlphaDark: 0.26,
  bloomAlphaLight: 0.16,
  auroraRows: 4,
  auroraRadius: 90,
  auroraRise: 30,
  auroraAlphaDark: 0.16,
  auroraAlphaLight: 0.07,
  glowHeight: 150,
  glowSwell: 0.6,
  breathK1: 0.011,
  breathK2: 0.027,
  breathK3: 0.0045,
  breathW1: 0.9,
  breathW2: 1.55,
  breathW3: 0.5,
  breathPhase: 1.7,
  breathA1: 0.24,
  breathA2: 0.16,
  breathA3: 0.1,
  breathFloor: 0.2,
  openReach: 0.62,
  openTau: 0.21,
  openDone: 0.9,
  openKick: 9,
  openKickTop: 0.22,
  openGate: 160,
  idleStrength: 1,
  restStrength: 0.4,
  stillStrength: 0.75,
  stillTime: 2.6,
  freeze: 2.4,
  quiet: 3.5,
  period: 0.46,
  damping: 0.24,
  waveSpeed: 7,
  ripplePeriod: 1.8,
  rippleDamping: 0.2,
  rippleSpeed: 20,
  dt: 1 / 120,
  maxSub: 12,
  limit: 2,
  touchKickE: 14,
  touchKickR: 7,
  touchSigma: 1.2,
  dragKickE: 6,
  dragKickR: 3.4,
  dragFull: 18,
  dragSigma: 1.1,
  calmKinetic: 0.5,
  restKinetic: 0.02,
  restDisp: 0.03,
  resumeGap: 0.25,
  replayAfterMs: 2500,
} as const;

type Rgb = readonly [number, number, number];

interface RampStep {
  css: string;
  r: number;
}

const clamp = (x: number, a: number, b: number): number => (x < a ? a : x > b ? b : x);
const lerp = (a: number, b: number, t: number): number => a + (b - a) * t;
const smooth = (x: number): number => {
  const c = clamp(x, 0, 1);
  return c * c * (3 - 2 * c);
};
const get = (a: Float32Array, i: number): number => a[i] ?? 0;
const geti = (a: Int32Array | Int8Array, i: number): number => a[i] ?? 0;
const add = (a: Float32Array, i: number, v: number): void => {
  a[i] = get(a, i) + v;
};

const hsl = (h: number, s: number, l: number): Rgb => {
  const hue = (((h % 360) + 360) % 360) / 360;
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const f = (t0: number): number => {
    const t = (t0 + 1) % 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 0.5) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return [f(hue + 1 / 3) * 255, f(hue) * 255, f(hue - 1 / 3) * 255];
};

const mix = (a: Rgb, b: Rgb, t: number): Rgb => [
  lerp(a[0], b[0], t),
  lerp(a[1], b[1], t),
  lerp(a[2], b[2], t),
];

export interface DotMatrixOptions {
  interactive: boolean;
  isDark: () => boolean;
}

export class DotMatrixEngine {
  private readonly ctx: CanvasRenderingContext2D;
  private readonly reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  private readonly cleanups: Array<() => void> = [];

  private W = 0;
  private H = 0;
  private dpr = 1;
  private S = 12;
  private cols = 0;
  private rows = 0;
  private N = 0;
  private ox = 0;
  private oy = 0;
  private E = new Float32Array(0);
  private V = new Float32Array(0);
  private R = new Float32Array(0);
  private RV = new Float32Array(0);
  private T = new Float32Array(0);
  private level = new Int8Array(0);
  private order = new Int32Array(0);
  private counts = new Int32Array(K.levels);
  private offsets = new Int32Array(K.levels + 1);

  private dark = false;
  private sprite: HTMLCanvasElement | null = null;
  private spriteKey = "";
  private ramp: RampStep[] = [];

  private running = false;
  private raf = 0;
  private last = 0;
  private time = 0;
  private frontPrev = 0;
  private lastKick = 0;
  private kinetic = 0;
  private disp = 0;
  private visible = true;
  private pageVisible = true;
  private offscreenSince = 0;
  private staticTargets = false;
  private pointer = { x: 0, y: 0, has: false };

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly host: HTMLElement,
    private readonly options: DotMatrixOptions,
  ) {
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("2d context unavailable");
    this.ctx = ctx;
    this.buildRamp();
    this.resize();
    if (this.reduce.matches) {
      this.still();
      this.draw();
    } else {
      this.openWave();
    }
    this.bind();
  }

  dispose(): void {
    this.stop();
    this.cleanups.forEach((fn) => fn());
    this.cleanups.length = 0;
  }

  refreshTheme(): void {
    this.buildRamp();
    if (!this.running) this.draw();
  }

  private listen<T extends EventTarget>(
    target: T,
    type: string,
    fn: (ev: Event) => void,
    opts?: AddEventListenerOptions,
  ): void {
    target.addEventListener(type, fn, opts);
    this.cleanups.push(() => target.removeEventListener(type, fn));
  }

  private bind(): void {
    const { host } = this;
    if (this.options.interactive) {
      this.listen(host, "pointerdown", (ev) => this.onDown(ev as PointerEvent), { passive: true });
      this.listen(host, "pointermove", (ev) => this.onMove(ev as PointerEvent), { passive: true });
      this.listen(host, "pointerleave", () => (this.pointer.has = false), { passive: true });
    }

    const ro = new ResizeObserver(() => this.resize());
    ro.observe(host);
    this.cleanups.push(() => ro.disconnect());

    const io = new IntersectionObserver(
      (entries) => {
        const vis = entries[0]?.isIntersecting ?? true;
        if (vis === this.visible) return;
        this.visible = vis;
        if (!vis) {
          this.offscreenSince = performance.now();
          this.stop();
        } else if (!this.reduce.matches) {
          if (performance.now() - this.offscreenSince > K.replayAfterMs && this.time > K.freeze) {
            this.openWave();
          } else if (this.kinetic > 0 || this.disp > K.restDisp) {
            this.start();
          }
        }
      },
      { threshold: 0 },
    );
    io.observe(host);
    this.cleanups.push(() => io.disconnect());

    this.listen(document, "visibilitychange", () => {
      this.pageVisible = !document.hidden;
      if (!this.pageVisible) this.stop();
      else if (this.time <= K.freeze + 0.3 || this.kinetic >= K.restKinetic) this.start();
    });

    this.listen(this.reduce, "change", () => {
      if (this.reduce.matches) {
        this.stop();
        this.resize();
        this.still();
        this.draw();
      } else {
        this.openWave();
      }
    });
  }

  private buildRamp(): void {
    this.dark = this.options.isDark();
    const red: Rgb = [215, 25, 33];
    const hot = hsl(357.3 + 16, 1, this.dark ? 0.6 : 0.5);
    const minA = this.dark ? K.minAlphaDark : K.minAlphaLight;
    this.ramp = [];
    for (let l = 0; l < K.levels; l++) {
      const e = (K.emax * (l + 1)) / K.levels;
      const share = e / K.emax;
      let c: Rgb;
      if (share < 0.5) c = red;
      else if (share < 0.78) c = mix(red, hot, (share - 0.5) / 0.28);
      else c = mix(hot, [255, 255, 255], this.dark ? 0.4 * clamp((share - 0.78) / 0.22, 0, 1) : 0);
      const alpha = lerp(minA, 1, Math.min(1, e));
      const r = e <= 1 ? lerp(K.minR, K.fullR, e) : lerp(K.fullR, K.maxR, (e - 1) / (K.emax - 1));
      this.ramp.push({
        css: `rgba(${Math.round(c[0])},${Math.round(c[1])},${Math.round(c[2])},${alpha.toFixed(3)})`,
        r,
      });
    }
    const key = this.dark ? "d" : "l";
    if (key !== this.spriteKey) {
      this.spriteKey = key;
      const sprite = document.createElement("canvas");
      sprite.width = sprite.height = K.bloomSprite;
      const sc = sprite.getContext("2d");
      if (sc) {
        const h = hsl(357.3 + 10, 1, this.dark ? 0.55 : 0.5);
        const half = K.bloomSprite / 2;
        const g = sc.createRadialGradient(half, half, 0, half, half, half);
        const stops = [0, 0.22, 0.55, 1];
        const prof = [1, 0.55, 0.16, 0];
        stops.forEach((s, i) =>
          g.addColorStop(
            s,
            `rgba(${Math.round(h[0])},${Math.round(h[1])},${Math.round(h[2])},${prof[i] ?? 0})`,
          ),
        );
        sc.fillStyle = g;
        sc.fillRect(0, 0, K.bloomSprite, K.bloomSprite);
      }
      this.sprite = sprite;
    }
  }

  private resize(): void {
    const r = this.host.getBoundingClientRect();
    const w = Math.max(1, Math.round(r.width));
    const h = Math.max(1, Math.round(r.height));
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    if (w === this.W && h === this.H && this.canvas.width === Math.round(w * this.dpr)) return;
    this.W = w;
    this.H = h;
    this.canvas.width = Math.round(w * this.dpr);
    this.canvas.height = Math.round(h * this.dpr);
    this.S = w > 1500 ? 14 : 12;
    this.cols = Math.max(2, Math.floor(w / this.S));
    this.rows = Math.max(2, Math.floor(h / this.S));
    this.N = this.cols * this.rows;
    this.ox = (w - (this.cols - 1) * this.S) / 2;
    this.oy = h - this.S / 2 - (this.rows - 1) * this.S;
    this.E = new Float32Array(this.N);
    this.V = new Float32Array(this.N);
    this.R = new Float32Array(this.N);
    this.RV = new Float32Array(this.N);
    this.T = new Float32Array(this.N);
    this.level = new Int8Array(this.N);
    this.order = new Int32Array(this.N);
    this.settle();
    if (!this.running) this.draw();
  }

  private strengthAt(t: number): number {
    return lerp(K.idleStrength, K.restStrength, smooth(t / K.freeze));
  }

  private computeTargets(tt: number, strength: number, gateOpen: boolean): void {
    const { W, H, S, cols, rows, ox, oy, T } = this;
    const tb = Math.min(tt, K.stillTime);
    const gh = clamp(H * 0.2, K.glowHeight, 200);
    const reachPx = K.openReach * H;
    const s = 1 - Math.exp(-tt / K.openTau);
    const rho = gateOpen ? 9 : s * 1.2;
    const cx = W / 2;
    const colBreath = new Float32Array(cols);
    for (let c = 0; c < cols; c++) {
      const x = ox + c * S;
      const b =
        0.5 +
        K.breathA1 * Math.sin(K.breathK1 * x - K.breathW1 * tb) +
        K.breathA2 * Math.sin(K.breathK2 * x + K.breathW2 * tb + K.breathPhase) +
        K.breathA3 * Math.sin(K.breathK3 * x - K.breathW3 * tb * 1.3);
      colBreath[c] = K.breathFloor + (1 - K.breathFloor) * clamp(b, 0, 1);
    }
    for (let r = 0; r < rows; r++) {
      const y = oy + r * S;
      const dist = H - y;
      for (let c = 0; c < cols; c++) {
        const i = r * cols + c;
        const br = get(colBreath, c);
        const g = gh * (1 + K.glowSwell * (br - 0.5));
        let w = 1 - dist / g;
        if (w <= 0) {
          T[i] = 0;
          continue;
        }
        w = Math.pow(w, 1.6);
        let gate = 1;
        if (!gateOpen) {
          const dx = (ox + c * S - cx) / (W / 2);
          const dy = dist / reachPx;
          gate = smooth(((rho - Math.hypot(dx, dy)) * reachPx) / K.openGate);
        }
        T[i] = strength * br * w * gate;
      }
    }
  }

  private openFront(tt: number): void {
    const { W, H, S, cols, rows, ox, oy, V } = this;
    const reachPx = K.openReach * H;
    const cx = W / 2;
    const rho = (1 - Math.exp(-tt / K.openTau)) * 1.2;
    if (rho <= this.frontPrev) return;
    for (let r = 0; r < rows; r++) {
      const dist = H - (oy + r * S);
      const dy = dist / reachPx;
      if (dy > rho + 0.01) continue;
      const up = clamp(dist / reachPx, 0, 1);
      const kick = K.openKick * lerp(1, K.openKickTop, up);
      for (let c = 0; c < cols; c++) {
        const dx = (ox + c * S - cx) / (W / 2);
        const d = Math.hypot(dx, dy);
        if (d > this.frontPrev && d <= rho) add(V, r * cols + c, kick);
      }
    }
    this.frontPrev = rho;
  }

  private rest(): void {
    for (let i = 0; i < this.N; i++) {
      this.E[i] = get(this.T, i);
      this.V[i] = 0;
      this.R[i] = 0;
      this.RV[i] = 0;
    }
  }

  private settle(): void {
    this.computeTargets(K.freeze + 1, K.restStrength, true);
    this.rest();
    this.frontPrev = 9;
    this.time = K.freeze + 1;
    this.staticTargets = true;
    this.kinetic = 0;
    this.disp = 0;
  }

  private still(): void {
    this.computeTargets(K.stillTime, K.stillStrength, true);
    this.rest();
  }

  private step(dt: number): void {
    const { E, V, R, RV, T, cols: cc, rows: rr, N } = this;
    const wE = TAU / K.period;
    const wR = TAU / K.ripplePeriod;
    const wE2 = wE * wE;
    const dE = 2 * K.damping * wE;
    const wR2 = wR * wR;
    const dR = 2 * K.rippleDamping * wR;
    const cE2 = K.waveSpeed * K.waveSpeed;
    const cR2 = K.rippleSpeed * K.rippleSpeed;
    const lim = K.limit;
    for (let r = 0; r < rr; r++) {
      const row = r * cc;
      for (let c = 0; c < cc; c++) {
        const i = row + c;
        const e = get(E, i);
        const h = get(R, i);
        const eL = c > 0 ? get(E, i - 1) : e;
        const eR = c < cc - 1 ? get(E, i + 1) : e;
        const eU = r > 0 ? get(E, i - cc) : e;
        const eD = r < rr - 1 ? get(E, i + cc) : e;
        const hL = c > 0 ? get(R, i - 1) : h;
        const hR = c < cc - 1 ? get(R, i + 1) : h;
        const hU = r > 0 ? get(R, i - cc) : h;
        const hD = r < rr - 1 ? get(R, i + cc) : h;
        const v = get(V, i);
        const rv = get(RV, i);
        V[i] = v + (-wE2 * (e - get(T, i)) - dE * v + cE2 * (eL + eR + eU + eD - 4 * e)) * dt;
        RV[i] = rv + (-wR2 * h - dR * rv + cR2 * (hL + hR + hU + hD - 4 * h)) * dt;
      }
    }
    let kin = 0;
    let dsp = 0;
    for (let j = 0; j < N; j++) {
      const ne = get(E, j) + get(V, j) * dt;
      const nh = get(R, j) + get(RV, j) * dt;
      E[j] = clamp(ne, -lim, lim);
      R[j] = clamp(nh, -lim, lim);
      kin += get(V, j) ** 2 + get(RV, j) ** 2;
      dsp += Math.abs(get(E, j) - get(T, j)) + Math.abs(get(R, j));
    }
    this.kinetic = kin / N;
    this.disp = dsp / N;
  }

  private draw(): void {
    const { N, ctx, W, H, S, cols, rows, ox, oy, E, R, level, order, counts, offsets } = this;
    if (!N) return;
    const { dark, sprite } = this;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    ctx.globalCompositeOperation = "source-over";
    ctx.globalAlpha = 1;
    const ink = dark ? "255,255,255" : "10,10,10";
    const inkMax = dark ? K.inkBottomDark : K.inkBottomLight;
    const emax = K.emax;

    counts.fill(0);
    for (let i = 0; i < N; i++) {
      const e = get(E, i);
      const en = Math.min(emax, (e > 0 ? e : 0) + Math.abs(get(R, i)));
      if (en < K.floor) {
        level[i] = -1;
        continue;
      }
      const l = Math.min(K.levels - 1, Math.floor((en / emax) * K.levels));
      level[i] = l;
      counts[l] = geti(counts, l) + 1;
    }
    offsets[0] = 0;
    for (let l = 0; l < K.levels; l++) offsets[l + 1] = geti(offsets, l) + geti(counts, l);
    for (let l = 0; l < K.levels; l++) counts[l] = geti(offsets, l);
    for (let i = 0; i < N; i++) {
      const l = geti(level, i);
      if (l >= 0) {
        const slot = geti(counts, l);
        order[slot] = i;
        counts[l] = slot + 1;
      }
    }

    const rowLvl = new Int8Array(rows);
    for (let r = 0; r < rows; r++) {
      const f = clamp(((oy + r * S) / H - K.inkFadeStart) / (1 - K.inkFadeStart), 0, 1);
      rowLvl[r] = Math.round(f * K.inkLevels);
    }
    for (let il = 1; il <= K.inkLevels; il++) {
      ctx.beginPath();
      let any = false;
      for (let r = 0; r < rows; r++) {
        if (geti(rowLvl, r) !== il) continue;
        const y = oy + r * S;
        for (let c = 0; c < cols; c++) {
          if (geti(level, r * cols + c) >= 0) continue;
          const x = ox + c * S;
          ctx.moveTo(x + K.baseR, y);
          ctx.arc(x, y, K.baseR, 0, TAU);
          any = true;
        }
      }
      if (any) {
        ctx.fillStyle = `rgba(${ink},${((inkMax * il) / K.inkLevels).toFixed(3)})`;
        ctx.fill();
      }
    }

    if (sprite) {
      ctx.globalCompositeOperation = dark ? "lighter" : "multiply";
      const bAlpha = dark ? K.bloomAlphaDark : K.bloomAlphaLight;
      for (let l = 0; l < K.levels; l++) {
        const eL = (emax * (l + 1)) / K.levels;
        const from = geti(offsets, l);
        const to = geti(offsets, l + 1);
        if (eL < K.bloomFloor || to === from) continue;
        const rad = lerp(
          K.bloomMin,
          K.bloomMax,
          clamp((eL - K.bloomFloor) / (emax - K.bloomFloor), 0, 1),
        );
        ctx.globalAlpha = bAlpha * Math.min(1, eL);
        for (let k = from; k < to; k++) {
          const i = geti(order, k);
          const r = Math.floor(i / cols);
          const c = i - r * cols;
          ctx.drawImage(sprite, ox + c * S - rad, oy + r * S - rad, rad * 2, rad * 2);
        }
      }
      const aA = dark ? K.auroraAlphaDark : K.auroraAlphaLight;
      for (let c = 0; c < cols; c += 3) {
        let sum = 0;
        let n = 0;
        for (let r = Math.max(0, rows - K.auroraRows); r < rows; r++) {
          const i = r * cols + c;
          sum += Math.min(emax, Math.max(0, get(E, i)) + Math.abs(get(R, i)));
          n++;
        }
        const ea = n ? sum / n : 0;
        if (ea < 0.1) continue;
        ctx.globalAlpha = aA * Math.min(1, ea) * 1.6;
        const ar = K.auroraRadius;
        ctx.drawImage(sprite, ox + c * S - ar, H - K.auroraRise - ar, ar * 2, ar * 2);
      }
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = "source-over";
    }

    for (let l = 0; l < K.levels; l++) {
      const from = geti(offsets, l);
      const to = geti(offsets, l + 1);
      const step = this.ramp[l];
      if (to === from || !step) continue;
      ctx.beginPath();
      for (let m = from; m < to; m++) {
        const i = geti(order, m);
        const r = Math.floor(i / cols);
        const px = ox + (i - r * cols) * S;
        const py = oy + r * S;
        ctx.moveTo(px + step.r, py);
        ctx.arc(px, py, step.r, 0, TAU);
      }
      ctx.fillStyle = step.css;
      ctx.fill();
    }
  }

  private canRun(): boolean {
    return this.visible && this.pageVisible && !this.reduce.matches;
  }

  private start(): void {
    if (this.running || !this.canRun()) return;
    this.running = true;
    this.last = 0;
    this.raf = requestAnimationFrame(this.frame);
  }

  private stop(): void {
    this.running = false;
    if (this.raf) cancelAnimationFrame(this.raf);
    this.raf = 0;
  }

  private readonly frame = (now: number): void => {
    this.raf = 0;
    if (!this.running) return;
    if (!this.last) this.last = now - 16;
    const elapsed = (now - this.last) / 1000;
    const calm = this.kinetic < K.calmKinetic;
    const minGap = (calm ? 1 / 30 : 1 / 60) - 0.003;
    if (elapsed < minGap) {
      this.raf = requestAnimationFrame(this.frame);
      return;
    }
    this.last = now;
    if (elapsed > K.resumeGap) {
      this.settle();
      this.draw();
      this.stop();
      return;
    }
    const dt = Math.min(elapsed, 0.1);
    this.time += dt;
    if (this.time < K.freeze + 0.3) {
      this.computeTargets(this.time, this.strengthAt(this.time), this.time > K.openDone + 0.5);
      this.staticTargets = false;
    } else if (!this.staticTargets) {
      this.computeTargets(K.freeze + 1, K.restStrength, true);
      this.staticTargets = true;
    }
    if (this.time < K.openDone) this.openFront(this.time);
    const steps = Math.min(K.maxSub, Math.max(1, Math.round(dt / K.dt)));
    for (let s = 0; s < steps; s++) this.step(dt / steps);
    this.draw();
    const quiet = (now - this.lastKick) / 1000 > K.quiet && this.time > K.freeze;
    if (quiet && this.kinetic < K.restKinetic && this.disp < K.restDisp) {
      this.settle();
      this.draw();
      this.stop();
      return;
    }
    this.raf = requestAnimationFrame(this.frame);
  };

  private openWave(): void {
    if (this.reduce.matches) {
      this.still();
      this.draw();
      return;
    }
    this.E.fill(0);
    this.V.fill(0);
    this.R.fill(0);
    this.RV.fill(0);
    this.time = 0;
    this.frontPrev = 0;
    this.staticTargets = false;
    this.lastKick = performance.now();
    this.computeTargets(0, this.strengthAt(0), false);
    this.stop();
    this.start();
  }

  private kickAt(px: number, py: number, amtE: number, amtR: number, sigma: number): void {
    const { S, cols, rows, ox, oy, V, RV } = this;
    const cx = (px - ox) / S;
    const cy = (py - oy) / S;
    const reach = Math.ceil(sigma * 3);
    const c0 = Math.max(0, Math.floor(cx) - reach);
    const c1 = Math.min(cols - 1, Math.ceil(cx) + reach);
    const r0 = Math.max(0, Math.floor(cy) - reach);
    const r1 = Math.min(rows - 1, Math.ceil(cy) + reach);
    for (let r = r0; r <= r1; r++) {
      for (let c = c0; c <= c1; c++) {
        const g = Math.exp(-((c - cx) ** 2 + (r - cy) ** 2) / (2 * sigma * sigma));
        if (g < 0.02) continue;
        add(V, r * cols + c, amtE * g);
        add(RV, r * cols + c, amtR * g);
      }
    }
    this.lastKick = performance.now();
    if (!this.running) this.start();
  }

  private local(ev: PointerEvent): { x: number; y: number } {
    const b = this.host.getBoundingClientRect();
    return { x: ev.clientX - b.left, y: ev.clientY - b.top };
  }

  private onDown(ev: PointerEvent): void {
    if (this.reduce.matches || !this.N) return;
    const p = this.local(ev);
    this.pointer = { ...p, has: true };
    this.kickAt(p.x, p.y, K.touchKickE, K.touchKickR, K.touchSigma);
  }

  private onMove(ev: PointerEvent): void {
    if (this.reduce.matches || !this.N) return;
    const p = this.local(ev);
    if (!this.pointer.has) {
      this.pointer = { ...p, has: true };
      return;
    }
    const d = Math.hypot(p.x - this.pointer.x, p.y - this.pointer.y);
    this.pointer = { ...p, has: true };
    if (d < 1) return;
    const k = Math.min(1, d / K.dragFull);
    this.kickAt(p.x, p.y, K.dragKickE * k, K.dragKickR * k, K.dragSigma);
  }
}
