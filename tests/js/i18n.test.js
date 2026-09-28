// Guards against missing translations: every key used in the markup or in the scripts
// must exist in both languages, and both dictionaries must have the same keys.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const I18N = require("../../js/i18n.js");
const root = path.join(__dirname, "..", "..");
const { it, en } = I18N.DICTIONARIES;

test("Italian and English dictionaries have the same keys", () => {
  assert.deepEqual(Object.keys(it).sort(), Object.keys(en).sort());
});

test("plural entries define both forms", () => {
  for (const dict of [it, en]) {
    for (const [key, value] of Object.entries(dict)) {
      if (typeof value === "object") assert.ok(value.one && value.other, key);
    }
  }
});

test("every key referenced in index.html and app.js exists", () => {
  const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
  const js = fs.readFileSync(path.join(root, "js", "app.js"), "utf8");
  const used = new Set();
  for (const m of html.matchAll(/data-i18n(?:-[a-z-]+)?="([^"]+)"/g)) used.add(m[1]);
  for (const m of js.matchAll(/\bt\(\s*"([^"]+)"/g)) used.add(m[1]);
  for (const m of js.matchAll(/(?:dataset\.i18n\w*\s*=\s*[^;]*?)"([a-z]+\.[a-zA-Z.]+)"/g)) used.add(m[1]);
  for (const key of used) assert.ok(key in it, `missing translation key: ${key}`);
  // Dynamic keys built from data values.
  for (const mode of ["METRO", "TRAM", "FILOBUS", "BUS"]) assert.ok(`mode.${mode}` in it);
  for (const day of ["L", "S", "F"]) assert.ok(`day.${day}` in it);
});

test("t() interpolates parameters and chooses plural forms", () => {
  I18N.setLanguage("en");
  assert.equal(I18N.t("vehicles.count", { n: 1 }), "1 vehicle");
  assert.equal(I18N.t("vehicles.count", { n: 3 }), "3 vehicles");
  assert.equal(I18N.t("lines.name", { id: "M1" }), "Line M1");
  I18N.setLanguage("it");
  assert.equal(I18N.t("lines.name", { id: "M1" }), "Linea M1");
  assert.equal(I18N.t("unknown.key"), "unknown.key");
});
