// Tiny synthesised UI sounds (Web Audio API) — no audio files required.

(function (root) {
  "use strict";

  class UiSounds {
    constructor(enabled = true) {
      this.enabled = enabled;
      this.ctx = null;
    }

    _context() {
      if (!this.enabled) return null;
      if (!this.ctx) {
        const Ctx = root.AudioContext || root.webkitAudioContext;
        if (!Ctx) return null;
        this.ctx = new Ctx();
      }
      if (this.ctx.state === "suspended") this.ctx.resume();
      return this.ctx;
    }

    _tone(ctx, { type = "sine", from, to = from, start, duration, volume = 0.06 }) {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = type;
      osc.frequency.setValueAtTime(from, start);
      if (to !== from) osc.frequency.exponentialRampToValueAtTime(to, start + duration);
      gain.gain.setValueAtTime(volume, start);
      gain.gain.exponentialRampToValueAtTime(0.001, start + duration);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(start);
      osc.stop(start + duration);
    }

    /** Soft two-note chime, used when something is selected. */
    chime() {
      const ctx = this._context();
      if (!ctx) return;
      const t = ctx.currentTime;
      this._tone(ctx, { from: 523.25, start: t, duration: 0.25 });
      this._tone(ctx, { from: 659.25, start: t + 0.06, duration: 0.3 });
    }

    click() {
      const ctx = this._context();
      if (!ctx) return;
      this._tone(ctx, { type: "triangle", from: 1200, to: 300, start: ctx.currentTime, duration: 0.05 });
    }

    deselect() {
      const ctx = this._context();
      if (!ctx) return;
      this._tone(ctx, { from: 350, to: 70, start: ctx.currentTime, duration: 0.12, volume: 0.08 });
    }
  }

  root.UiSounds = UiSounds;
})(typeof window !== "undefined" ? window : globalThis);
