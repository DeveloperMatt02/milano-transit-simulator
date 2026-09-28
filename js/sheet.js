// Draggable bottom sheet used for the side panels on phones.
//
// The sheet snaps between named heights ("peek", "half", "full"); dragging the handle
// follows the finger and releases to the nearest snap point, taking the gesture's speed
// into account. Dragging a closable sheet well below its lowest snap closes it.
// Outside the mobile breakpoint the sheet is inert and all inline styles are removed.

(function (root) {
  "use strict";

  class BottomSheet {
    /**
     * @param {HTMLElement} el
     * @param {HTMLElement} handle
     * @param {object} opts
     *   media      MediaQueryList enabling the behaviour
     *   snaps      () => ({ peek?, half, full }) heights in px
     *   initial    initial state name
     *   onClose    called when a closable sheet is swiped away
     *   onChange   called with the new state
     */
    constructor(el, handle, opts) {
      this.el = el;
      this.handle = handle;
      this.opts = opts;
      this.state = opts.initial || "half";
      this._drag = null;

      handle.addEventListener("pointerdown", (e) => this._start(e));
      handle.addEventListener("click", () => {
        if (this.enabled() && !this._moved) this.toggle();
      });
      root.addEventListener("pointermove", (e) => this._move(e), { passive: true });
      root.addEventListener("pointerup", (e) => this._end(e));
      root.addEventListener("pointercancel", (e) => this._end(e));
      root.addEventListener("resize", () => this.apply());
      if (opts.media && opts.media.addEventListener) opts.media.addEventListener("change", () => this.apply());
      this.apply();
    }

    enabled() {
      return !this.opts.media || this.opts.media.matches;
    }

    heights() {
      return this.opts.snaps();
    }

    /** Sets a named state and animates to its height. */
    set(state) {
      const heights = this.heights();
      if (!(state in heights)) return;
      this.state = state;
      this.apply();
      if (this.opts.onChange) this.opts.onChange(state);
    }

    toggle() {
      const order = Object.keys(this.heights());
      const next = this.state === order[order.length - 1] ? order[0] : order[order.indexOf(this.state) + 1] || order[0];
      this.set(next);
    }

    apply() {
      if (!this.enabled()) {
        this.el.style.height = "";
        this.el.classList.remove("sheet-dragging");
        delete this.el.dataset.sheet;
        return;
      }
      const heights = this.heights();
      if (!(this.state in heights)) this.state = Object.keys(heights)[0];
      this.el.dataset.sheet = this.state;
      this.el.style.height = `${Math.round(heights[this.state])}px`;
    }

    _start(e) {
      if (!this.enabled() || (e.pointerType === "mouse" && e.button !== 0)) return;
      this._moved = false;
      this._drag = { y0: e.clientY, h0: this.el.getBoundingClientRect().height, t0: performance.now(), lastY: e.clientY, lastT: performance.now(), v: 0 };
      this.el.classList.add("sheet-dragging");
    }

    _move(e) {
      if (!this._drag) return;
      const d = this._drag;
      const dy = e.clientY - d.y0;
      if (Math.abs(dy) > 4) this._moved = true;
      const heights = Object.values(this.heights());
      const max = Math.max(...heights);
      const h = Math.max(40, Math.min(max, d.h0 - dy));
      this.el.style.height = `${h}px`;
      const now = performance.now();
      d.v = (e.clientY - d.lastY) / Math.max(1, now - d.lastT); // px/ms, positive = downwards
      d.lastY = e.clientY;
      d.lastT = now;
    }

    _end() {
      if (!this._drag) return;
      const d = this._drag;
      this._drag = null;
      this.el.classList.remove("sheet-dragging");
      if (!this._moved) return this.apply();

      const current = this.el.getBoundingClientRect().height;
      const entries = Object.entries(this.heights()).sort((a, b) => a[1] - b[1]);
      const lowest = entries[0][1];
      if (this.opts.onClose && (current < lowest * 0.6 || (d.v > 0.8 && current <= lowest + 40))) {
        this.opts.onClose();
        return;
      }
      // Project the release position with the gesture velocity, then snap.
      const projected = current - d.v * 180;
      let best = entries[0];
      for (const entry of entries) if (Math.abs(entry[1] - projected) < Math.abs(best[1] - projected)) best = entry;
      this.set(best[0]);
    }
  }

  root.BottomSheet = BottomSheet;
})(typeof window !== "undefined" ? window : globalThis);
