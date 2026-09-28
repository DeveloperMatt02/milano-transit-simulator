const test = require("node:test");
const assert = require("node:assert/strict");
const Themes = require("../../js/themes.js");
const U = require("../../js/utils.js");

// WCAG relative luminance and contrast ratio.
function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const c = parseInt(hex.slice(i, i + 2), 16) / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
const contrast = (a, b) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

test("auto follows the system colour scheme; explicit choices win", () => {
  assert.equal(Themes.resolve("auto", false), "noorda-light");
  assert.equal(Themes.resolve("auto", true), "noorda-dark");
  assert.equal(Themes.resolve("fiord", false), "fiord");
  assert.equal(Themes.resolve("noorda-light", true), "noorda-light");
  assert.equal(Themes.resolve("unknown", false), "noorda-light");
});

test("every theme defines an OpenFreeMap style and colours for all lines and modes", () => {
  for (const [id, def] of Object.entries(Themes.THEMES)) {
    assert.match(def.basemap, /^https:\/\/tiles\.openfreemap\.org\/styles\/\w+$/, id);
    for (const line of ["M1", "M2", "M3", "M4", "M5"]) assert.match(def.lineColors[line], /^#[0-9A-F]{6}$/i, `${id} ${line}`);
    for (const mode of ["TRAM", "FILOBUS", "BUS"]) assert.match(def.modeColors[mode], /^#[0-9A-F]{6}$/i, `${id} ${mode}`);
  }
});

test("line badge text meets WCAG AA contrast in every theme", () => {
  for (const [id, def] of Object.entries(Themes.THEMES)) {
    for (const color of [...Object.values(def.lineColors), ...Object.values(def.modeColors)]) {
      const text = U.prefersDarkText(color) ? "#111418" : "#ffffff";
      assert.ok(contrast(color, text) >= 4.5, `${id}: ${text} on ${color} is ${contrast(color, text).toFixed(2)}:1`);
    }
  }
});
