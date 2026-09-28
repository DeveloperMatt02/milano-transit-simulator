const test = require("node:test");
const assert = require("node:assert/strict");

const METRO = require("../../js/data/metro-network.js");
const FREQ = require("../../js/data/metro-frequencies.js");
const TransitScheduler = require("../../js/scheduler.js");
const TransitSimulation = require("../../js/simulation-engine.js");

const scheduler = new TransitScheduler(METRO, FREQ);
const trips = scheduler.generateMetroSchedule("L");
const at = (h, m = 0) => () => new Date(2026, 8, 28, h, m, 0); // Monday

test("real-time mode follows the wall clock, including after midnight", () => {
  const sim = new TransitSimulation(METRO, trips, { clock: at(0, 20) });
  assert.equal(Math.round(sim.simTime), 24 * 3600 + 20 * 60);
  assert.ok(sim.getActiveVehicles().length > 0, "trains must still run at 00:20");
});

test("no trains between 02:00 and 05:00", () => {
  const sim = new TransitSimulation(METRO, trips, { clock: at(4, 0) });
  assert.equal(sim.getActiveVehicles().length, 0);
});

test("rush hour has more trains than late evening", () => {
  const sim = new TransitSimulation(METRO, trips, { clock: at(8) });
  const rush = sim.getActiveVehicles(8 * 3600).length;
  const late = sim.getActiveVehicles(23.5 * 3600).length;
  assert.ok(rush > late * 1.5, `rush ${rush} vs late ${late}`);
});

test("vehicle positions are interpolated between consecutive stations", () => {
  const sim = new TransitSimulation(METRO, trips, { clock: at(10) });
  const trip = trips.find((t) => t.lineId === "M3" && t.startTime > 10 * 3600);
  const a = trip.stopTimes[3];
  const b = trip.stopTimes[4];
  const mid = (a.departureTime + b.arrivalTime) / 2;
  const v = sim.getVehicleState(trip, mid);
  const s1 = METRO.stations[a.stationId];
  const s2 = METRO.stations[b.stationId];
  assert.equal(v.status, "MOVING");
  assert.ok(Math.abs(v.lat - (s1.lat + s2.lat) / 2) < 1e-9);
  assert.ok(Math.abs(v.lon - (s1.lon + s2.lon) / 2) < 1e-9);
  assert.ok(Math.abs(v.segmentProgress - 0.5) < 1e-9);
  assert.ok(v.speed > 0);

  const dwell = sim.getVehicleState(trip, a.arrivalTime + 1);
  assert.equal(dwell.status, "STOPPED");
  assert.equal(dwell.currentStationId, a.stationId);
});

test("manual clock wraps from 27:00 back to 03:00", () => {
  const sim = new TransitSimulation(METRO, trips, { clock: at(12) });
  sim.setTime(27 * 3600 + 60);
  assert.equal(sim.simTime, 3 * 3600 + 60);
  sim.setTime(2 * 3600);
  assert.equal(sim.simTime, 26 * 3600);
});

test("departure board excludes terminating trains and is time ordered", () => {
  const sim = new TransitSimulation(METRO, trips, { clock: at(9) });
  const deps = sim.getStationDepartures("comasina");
  assert.ok(deps.length > 0);
  assert.ok(deps.every((d) => d.destination !== "Comasina"), "no departures towards the station itself");
  for (let i = 1; i < deps.length; i++) assert.ok(deps[i].arrivalTime >= deps[i - 1].arrivalTime);
});

test("departure board groups at most N trips per line and destination", () => {
  const sim = new TransitSimulation(METRO, trips, { clock: at(9) });
  const deps = sim.getStationDepartures("duomo", { perGroup: 2 });
  const groups = {};
  deps.forEach((d) => (groups[`${d.lineId}|${d.destination}`] = (groups[`${d.lineId}|${d.destination}`] || 0) + 1));
  Object.values(groups).forEach((n) => assert.ok(n <= 2));
  assert.ok(new Set(deps.map((d) => d.lineId)).size === 2, "Duomo is served by M1 and M3");
});
