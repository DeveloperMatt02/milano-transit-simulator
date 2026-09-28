// Integrity checks on the generated network datasets.
const test = require("node:test");
const assert = require("node:assert/strict");

const METRO = require("../../js/data/metro-network.js");
const FREQ = require("../../js/data/metro-frequencies.js");
const SURFACE = require("../../js/data/surface-network.js");

// Generous bounding box around the Milan metropolitan area.
const inMilanArea = (s) => s.lat > 45.3 && s.lat < 45.7 && s.lon > 8.9 && s.lon < 9.5;

test("metro: every station referenced by a path exists and has valid coordinates", () => {
  for (const line of Object.values(METRO.lines)) {
    for (const [pathKey, path] of Object.entries(line.paths)) {
      assert.ok(path.length >= 2, `${line.id}/${pathKey} too short`);
      for (const id of path) {
        const s = METRO.stations[id];
        assert.ok(s, `${line.id}/${pathKey}: missing station ${id}`);
        assert.ok(inMilanArea(s), `${id} outside Milan: ${s.lat},${s.lon}`);
      }
    }
  }
});

test("metro: station.lines matches the lines whose paths include the station", () => {
  for (const [id, station] of Object.entries(METRO.stations)) {
    const serving = Object.values(METRO.lines)
      .filter((l) => Object.values(l.paths).some((p) => p.includes(id)))
      .map((l) => l.id)
      .sort();
    assert.deepEqual([...station.lines].sort(), serving, `lines mismatch for ${id}`);
    assert.equal(station.interchanges.length, station.lines.length - 1, `interchanges mismatch for ${id}`);
  }
});

test("metro: branches share their junction station with the trunk", () => {
  const { M1, M2 } = METRO.lines;
  const last = (a) => a[a.length - 1];
  assert.equal(M1.paths.branch_rho[0], last(M1.paths.trunk));
  assert.equal(M1.paths.branch_bisceglie[0], last(M1.paths.trunk));
  assert.equal(last(M2.paths.branch_gessate), M2.paths.trunk[0]);
  assert.equal(last(M2.paths.branch_cologno), M2.paths.trunk[0]);
  assert.equal(M2.paths.branch_assago[0], last(M2.paths.trunk));
  assert.equal(M2.paths.branch_abbiategrasso[0], last(M2.paths.trunk));
});

test("metro: Lambrate FS sits between Udine and Piola on M2", () => {
  const trunk = METRO.lines.M2.paths.trunk;
  const i = trunk.indexOf("lambrate");
  assert.ok(i > 0, "lambrate missing from M2");
  assert.equal(trunk[i - 1], "udine");
  assert.equal(trunk[i + 1], "piola");
});

test("metro: Portello is served by M5 only", () => {
  assert.deepEqual(METRO.stations.portello.lines, ["M5"]);
});

test("metro: consecutive stations are between 250 m and 4 km apart", () => {
  const { haversine } = require("../../js/utils.js");
  for (const line of Object.values(METRO.lines)) {
    for (const path of Object.values(line.paths)) {
      for (let i = 0; i < path.length - 1; i++) {
        const a = METRO.stations[path[i]];
        const b = METRO.stations[path[i + 1]];
        const d = haversine(a.lat, a.lon, b.lat, b.lon);
        assert.ok(d > 250 && d < 4000, `${line.id}: ${a.name} -> ${b.name} is ${Math.round(d)} m`);
      }
    }
  }
});

test("frequencies: every line has plausible levels for every day type", () => {
  for (const lineId of Object.keys(METRO.lines)) {
    for (const day of ["L", "S", "F"]) {
      const f = FREQ[lineId][day];
      assert.ok(f, `${lineId}/${day} missing`);
      for (const key of ["peak_headway", "mid_headway", "evening_headway"]) {
        assert.ok(f[key] >= 90 && f[key] <= 1200, `${lineId}/${day}.${key} = ${f[key]}`);
      }
      assert.match(f.first_departure, /^0[4-7]:\d{2}$/);
      assert.match(f.last_arrival, /^2[3-6]:\d{2}$/, `${lineId}/${day} last arrival ${f.last_arrival}`);
    }
  }
});

test("surface: routes reference existing stops and have service levels", () => {
  const lines = Object.values(SURFACE.lines);
  assert.ok(lines.length > 100);
  for (const line of lines) {
    assert.ok(["TRAM", "FILOBUS", "BUS"].includes(line.type), `${line.id} type ${line.type}`);
    for (const route of Object.values(line.percorsi)) {
      assert.ok(route.stops.length >= 2);
      route.stops.forEach((id) => assert.ok(SURFACE.stations[id], `${line.id}: missing stop ${id}`));
      const days = Object.keys(route.frequencies);
      assert.ok(days.length > 0, `${line.id}/${route.id} has no service`);
      for (const f of Object.values(route.frequencies)) {
        assert.match(f.service_start, /^\d{2}:\d{2}$/);
        assert.match(f.service_end, /^\d{2}:\d{2}$/);
        assert.ok(f.service_start <= f.service_end, `${line.id}/${route.id}: ${f.service_start} > ${f.service_end}`);
      }
    }
  }
  Object.values(SURFACE.stations).forEach((s) => assert.ok(inMilanArea(s), `stop ${s.id} outside Milan`));
});
