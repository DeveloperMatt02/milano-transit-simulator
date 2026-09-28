// Visual themes. CSS holds the interface tokens (css/style.css, [data-theme=…]);
// this file holds what the map needs from JavaScript: basemap style, line colours and weights.
//
//   noorda-light / noorda-dark  inspired by Bob Noorda's 1964 wayfinding for the Milan metro:
//                               solid panels, red band, bold grotesk, thick flat lines.
//   fiord                       control-room look: slate blue, monospaced data, amber accent.

(function (root) {
  "use strict";

  const OPENFREEMAP = "https://tiles.openfreemap.org/styles/";

  const THEMES = {
    "noorda-light": {
      basemap: `${OPENFREEMAP}positron`,
      metaColor: "#ffffff",
      lineWeight: 5,
      lineOpacity: 1,
      glow: null,
      lineColors: { M1: "#E2231A", M2: "#00873F", M3: "#F5C400", M4: "#1165B0", M5: "#8E4799" },
      modeColors: { TRAM: "#E07800", FILOBUS: "#00873F", BUS: "#1165B0" },
    },
    "noorda-dark": {
      basemap: `${OPENFREEMAP}dark`,
      metaColor: "#16181c",
      lineWeight: 5,
      lineOpacity: 1,
      glow: null,
      lineColors: { M1: "#E0261C", M2: "#00843F", M3: "#FFD21F", M4: "#1F74C8", M5: "#9B53B0" },
      modeColors: { TRAM: "#FF9A1F", FILOBUS: "#21C36B", BUS: "#3C8DE0" },
    },
    fiord: {
      basemap: `${OPENFREEMAP}fiord`,
      metaColor: "#142130",
      lineWeight: 3.5,
      lineOpacity: 0.95,
      glow: "drop-shadow(0 0 3px rgba(0, 0, 0, 0.45))",
      lineColors: { M1: "#FF6B61", M2: "#3CCF7A", M3: "#FFD84D", M4: "#4AA3FF", M5: "#C77DFF" },
      modeColors: { TRAM: "#FFB454", FILOBUS: "#3CCF7A", BUS: "#4AA3FF" },
    },
  };

  const PREFERENCES = ["auto", "noorda-light", "noorda-dark", "fiord"];
  const STORAGE_KEY = "mts.theme";

  /** Resolves a stored preference ("auto" included) to a concrete theme id. */
  function resolve(preference, prefersDark) {
    if (preference === "auto" || !THEMES[preference]) return prefersDark ? "noorda-dark" : "noorda-light";
    return preference;
  }

  const ThemeManager = {
    THEMES,
    PREFERENCES,
    resolve,
    _listeners: [],
    _media: null,

    init() {
      let pref = "auto";
      try {
        pref = root.localStorage.getItem(STORAGE_KEY) || "auto";
      } catch (e) {
        /* storage unavailable */
      }
      this.preference = PREFERENCES.includes(pref) ? pref : "auto";
      this._media = root.matchMedia ? root.matchMedia("(prefers-color-scheme: dark)") : null;
      if (this._media) {
        const onChange = () => this.preference === "auto" && this._apply();
        if (this._media.addEventListener) this._media.addEventListener("change", onChange);
        else if (this._media.addListener) this._media.addListener(onChange);
      }
      this._apply();
      return this;
    },

    setPreference(pref) {
      if (!PREFERENCES.includes(pref)) return;
      this.preference = pref;
      try {
        root.localStorage.setItem(STORAGE_KEY, pref);
      } catch (e) {
        /* storage unavailable */
      }
      this._apply();
    },

    get current() {
      return resolve(this.preference, !!(this._media && this._media.matches));
    },

    get def() {
      return THEMES[this.current];
    },

    onChange(fn) {
      this._listeners.push(fn);
    },

    _apply() {
      const id = this.current;
      const doc = root.document;
      if (doc) {
        doc.documentElement.dataset.theme = id;
        const meta = doc.querySelector('meta[name="theme-color"]');
        if (meta) meta.content = THEMES[id].metaColor;
      }
      this._listeners.forEach((fn) => fn(id, THEMES[id]));
    },
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = ThemeManager;
  } else {
    root.ThemeManager = ThemeManager;
  }
})(typeof window !== "undefined" ? window : globalThis);
