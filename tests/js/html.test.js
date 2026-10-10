// Static checks on index.html.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const html = fs.readFileSync(path.join(__dirname, "../../index.html"), "utf8");

test("every script and stylesheet from a CDN is pinned with Subresource Integrity", () => {
  const tags = html.match(/<(script|link)\b[^>]*>/g) || [];
  const external = tags.filter((tag) => /\s(src|href)="https:\/\/(unpkg\.com|cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com)\//.test(tag));
  assert.ok(external.length >= 5, `expected the Leaflet and MapLibre resources, found ${external.length}`);
  for (const tag of external) {
    assert.match(tag, /\sintegrity="sha(256|384|512)-[A-Za-z0-9+/=]+"/, `missing integrity: ${tag}`);
    assert.match(tag, /\scrossorigin=/, `missing crossorigin: ${tag}`);
    assert.match(tag, /@\d+\.\d+\.\d+\//, `version not pinned: ${tag}`);
  }
});
