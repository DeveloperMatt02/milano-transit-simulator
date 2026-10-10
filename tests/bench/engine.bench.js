// Micro-benchmark of the simulation engine hot paths.
//
//   node tests/bench/engine.bench.js            (or: npm run bench)
//
// Measures the engine-side cost of one animation frame (`getActiveVehicles`) and of one
// departure-board refresh (`getStationDepartures`) with today's synthetic metro timetable
// and with larger, *illustrative* trip volumes (the timetable copied 5× and 20× with small
// time offsets). The scaled rows are not a model of the GTFS feed: they only show how the
// cost grows when one simulation holds many more trips, to size the indexing work planned
// in ROADMAP F3. Map rendering is not measured here (that is the F2 spike).
// Not part of `npm test`: timings depend on the machine and are reported, not asserted.

"use strict";

const { performance } = require("node:perf_hooks");
const METRO_NETWORK = require("../../js/data/metro-network.js");
const METRO_FREQ = require("../../js/data/metro-frequencies.js");
const TransitScheduler = require("../../js/scheduler.js");
const TransitSimulation = require("../../js/simulation-engine.js");

const FRAME_BUDGET_MS = 1000 / 60;
const AT = 8.25 * 3600; // 08:15, weekday morning peak
const STATION = "duomo";
const RUNS = 60;

/** min / median / p95 duration (ms) of `fn` over `runs` runs. */
function measure(fn, runs = RUNS) {
  const samples = [];
  for (let i = 0; i < runs; i++) {
    const t0 = performance.now();
    fn();
    samples.push(performance.now() - t0);
  }
  samples.sort((a, b) => a - b);
  const pick = (q) => samples[Math.min(samples.length - 1, Math.floor(q * samples.length))];
  return { min: samples[0], median: pick(0.5), p95: pick(0.95) };
}

/** Copies the timetable `factor` times, each copy shifted by a few seconds (re-sorted by start time). */
function scaleTrips(trips, factor) {
  if (factor === 1) return trips;
  const out = [];
  for (let k = 0; k < factor; k++) {
    const shift = k * 7; // seconds
    for (const trip of trips) {
      out.push({
        ...trip,
        tripId: `${trip.tripId}#${k}`,
        startTime: trip.startTime + shift,
        endTime: trip.endTime + shift,
        stopTimes: trip.stopTimes.map((s) => ({ ...s, arrivalTime: s.arrivalTime + shift, departureTime: s.departureTime + shift })),
      });
    }
  }
  return out.sort((a, b) => a.startTime - b.startTime);
}

const scheduler = new TransitScheduler(METRO_NETWORK, METRO_FREQ);
const gen = measure(() => scheduler.generateMetroSchedule("L"), 10);
const metroTrips = scheduler.generateMetroSchedule("L");

const cases = [1, 5, 20].map((factor) => {
  const trips = scaleTrips(metroTrips, factor);
  const sim = new TransitSimulation(METRO_NETWORK, trips);
  sim.setTime(AT); // manual mode: the clock no longer follows the wall clock
  return { trips, sim };
});

// Warm-up pass over every size before measuring, so the first row is not measured cold.
for (let i = 0; i < 20; i++) {
  for (const { trips, sim } of cases) {
    sim.getActiveVehicles();
    sim.getStationDepartures(STATION, { trips });
  }
}

const fmt = (m) => `${m.median.toFixed(2)} (min ${m.min.toFixed(2)} · p95 ${m.p95.toFixed(2)})`;
const rows = cases.map(({ trips, sim }) => {
  const active = measure(() => sim.getActiveVehicles());
  const board = measure(() => sim.getStationDepartures(STATION, { trips }));
  return {
    "trips in simulation": trips.length,
    "running vehicles": sim.getActiveVehicles().length,
    "getActiveVehicles ms, median (min · p95)": fmt(active),
    "median % of 60 fps frame": `${((active.median / FRAME_BUDGET_MS) * 100).toFixed(0)}%`,
    "getStationDepartures ms, median (min · p95)": fmt(board),
  };
});

console.log(`Node ${process.version} · generateMetroSchedule("L"): ${gen.median.toFixed(1)} ms for ${metroTrips.length} trips`);
console.log(`Engine cost only (no map rendering) · ${RUNS} runs per cell · station board at "${STATION}" (inflated by the copies)\n`);
console.table(rows);
