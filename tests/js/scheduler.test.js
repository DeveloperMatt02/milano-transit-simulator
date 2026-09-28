const test = require("node:test");
const assert = require("node:assert/strict");

const METRO = require("../../js/data/metro-network.js");
const FREQ = require("../../js/data/metro-frequencies.js");
const SURFACE = require("../../js/data/surface-network.js");
const U = require("../../js/utils.js");
const TransitScheduler = require("../../js/scheduler.js");

const scheduler = new TransitScheduler(METRO, FREQ);
const weekday = scheduler.generateMetroSchedule("L");

test("time bands", () => {
  const band = TransitScheduler.timeBand;
  assert.equal(band(6 * 3600), "mid");
  assert.equal(band(8 * 3600), "peak");
  assert.equal(band(12 * 3600), "mid");
  assert.equal(band(18 * 3600), "shoulder");
  assert.equal(band(21 * 3600), "evening");
  assert.equal(band(24.5 * 3600), "evening");
});

test("metro: headways come from the open-data levels", () => {
  assert.equal(scheduler.getHeadway("M3", 8 * 3600, "L"), FREQ.M3.L.peak_headway);
  assert.equal(scheduler.getHeadway("M3", 12 * 3600, "L"), FREQ.M3.L.mid_headway);
  assert.equal(scheduler.getHeadway("M3", 23 * 3600, "F"), FREQ.M3.F.evening_headway);
});

test("metro: schedule is sorted and every trip has monotonic stop times", () => {
  for (let i = 1; i < weekday.length; i++) assert.ok(weekday[i].startTime >= weekday[i - 1].startTime);
  for (const trip of weekday) {
    assert.equal(trip.stopTimes.length, trip.stationIds.length);
    for (let i = 0; i < trip.stopTimes.length; i++) {
      const st = trip.stopTimes[i];
      assert.ok(st.departureTime >= st.arrivalTime);
      if (i > 0) assert.ok(st.arrivalTime > trip.stopTimes[i - 1].departureTime);
    }
    assert.equal(trip.endTime, trip.stopTimes[trip.stopTimes.length - 1].arrivalTime);
  }
});

test("metro: service window respects first departure and last arrival", () => {
  for (const lineId of Object.keys(METRO.lines)) {
    const trips = weekday.filter((t) => t.lineId === lineId);
    assert.ok(trips.length > 100, `${lineId}: only ${trips.length} trips`);
    const first = Math.min(...trips.map((t) => t.startTime));
    const lastEnd = Math.max(...trips.map((t) => t.endTime));
    assert.equal(first, U.parseHHMM(FREQ[lineId].L.first_departure));
    assert.ok(lastEnd <= U.parseHHMM(FREQ[lineId].L.last_arrival));
    assert.ok(lastEnd > 24 * 3600, `${lineId}: service should run past midnight`);
  }
});

test("metro: M1 alternates the Rho and Bisceglie branches", () => {
  const fromSesto = weekday.filter((t) => t.lineId === "M1" && t.from === "Sesto 1° Maggio").slice(0, 6);
  assert.deepEqual(
    fromSesto.map((t) => t.to),
    ["Bisceglie", "Rho Fieramilano", "Bisceglie", "Rho Fieramilano", "Bisceglie", "Rho Fieramilano"]
  );
  const rho = fromSesto[1].stationIds;
  assert.equal(rho.filter((id) => id === "pagano").length, 1, "junction station must not be duplicated");
});

test("metro: M2 serves all four termini and never duplicates junctions", () => {
  const m2 = weekday.filter((t) => t.lineId === "M2");
  const termini = new Set(m2.flatMap((t) => [t.from, t.to]));
  for (const name of ["Gessate", "Cologno Nord", "Assago Milanofiori Forum", "Abbiategrasso"]) {
    assert.ok(termini.has(name), `missing terminus ${name}`);
  }
  for (const t of m2.slice(0, 20)) assert.equal(new Set(t.stationIds).size, t.stationIds.length);
});

test("metro: fewer trips on Sundays than on weekdays", () => {
  assert.ok(scheduler.generateMetroSchedule("F").length < weekday.length);
});

test("metro: travel times are clamped between 50 s and 180 s", () => {
  for (const line of Object.values(METRO.lines)) {
    for (const path of Object.values(line.paths)) {
      for (let i = 0; i < path.length - 1; i++) {
        const tt = scheduler.getTravelTime(path[i], path[i + 1]);
        assert.ok(tt >= 50 && tt <= 180);
      }
    }
  }
});

test("surface: routes without service on a day type produce no trips", () => {
  const line = Object.values(SURFACE.lines).find((l) =>
    Object.values(l.percorsi).every((r) => !r.frequencies.F)
  );
  assert.ok(line, "expected at least one line that does not run on holidays");
  assert.equal(scheduler.generateSurfaceSchedule(line.id, SURFACE, "F").length, 0);
});

test("surface: 24-hour line 90 runs at 03:30", () => {
  const trips = scheduler.generateSurfaceSchedule("90", SURFACE, "L");
  const t = 3.5 * 3600;
  assert.ok(trips.some((trip) => U.isActiveAt(trip.startTime, trip.endTime, t)));
});

test("surface: quick vehicle count equals the count from full schedules", () => {
  const sample = Object.keys(SURFACE.lines).slice(0, 25);
  for (const lineId of sample) {
    for (const t of [7.5 * 3600, 13 * 3600, 23.5 * 3600]) {
      const full = scheduler
        .generateSurfaceSchedule(lineId, SURFACE, "L")
        .filter((trip) => U.isActiveAt(trip.startTime, trip.endTime, t)).length;
      assert.equal(scheduler.countActiveSurfaceVehicles(lineId, SURFACE, "L", t), full, `line ${lineId} at ${t}`);
    }
  }
});

test("surface: schedules are cached per line and day type", () => {
  const a = scheduler.generateSurfaceSchedule("15", SURFACE, "L");
  assert.equal(scheduler.generateSurfaceSchedule("15", SURFACE, "L"), a);
  assert.notEqual(scheduler.generateSurfaceSchedule("15", SURFACE, "S"), a);
});
