// Records what the JavaScript engine (js/*.js) computes on fixed scenarios, so that the Dart
// port (packages/transit_core) can be checked against it: test/golden/js_engine.json.
//
//   node packages/transit_core/tool/make_golden.js          # rewrite the golden file
//   node packages/transit_core/tool/make_golden.js --check  # exit 1 if it is out of date
//
// Trip lists are summarised with an FNV-1a hash over every stop time; vehicles and departure
// boards are recorded in full for a few moments of the day.

"use strict";

// Local-time Date arithmetic below (day-type loop) must not depend on the machine: in a
// zone with daylight saving, 02:30 does not exist on the spring change and shifts the day.
process.env.TZ = "UTC";

const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "../../..");
const U = require(path.join(ROOT, "js/utils.js"));
const METRO = require(path.join(ROOT, "js/data/metro-network.js"));
const FREQ = require(path.join(ROOT, "js/data/metro-frequencies.js"));
const SURFACE = require(path.join(ROOT, "js/data/surface-network.js"));
const TransitScheduler = require(path.join(ROOT, "js/scheduler.js"));
const TransitSimulation = require(path.join(ROOT, "js/simulation-engine.js"));

const OUT = path.join(__dirname, "../test/golden/js_engine.json");

/** FNV-1a, 32 bit, over UTF-16 code units (the Dart test computes the same over codeUnits). */
function fnv1a(text, hash = 0x811c9dc5) {
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 16777619) >>> 0;
  }
  return hash;
}

function tripLine(trip) {
  const times = trip.stopTimes.map((s) => `${s.arrivalTime}/${s.departureTime}`).join(",");
  return `${trip.tripId}|${trip.lineId}|${trip.mode}|${trip.from}|${trip.to}|${trip.stationIds.join(",")}|${times};`;
}

function summarise(trips) {
  let hash = 0x811c9dc5;
  const perLine = {};
  for (const trip of trips) {
    hash = fnv1a(tripLine(trip), hash);
    perLine[trip.lineId] = (perLine[trip.lineId] || 0) + 1;
  }
  return {
    count: trips.length,
    hash,
    perLine,
    first: trips.slice(0, 12).map((t) => [t.tripId, t.from, t.to, t.startTime, t.endTime, t.stationIds.length]),
  };
}

const r6 = (x) => Math.round(x * 1e6) / 1e6;

function vehicles(sim, t) {
  return sim
    .getActiveVehicles(t)
    .map((v) => [v.tripId, v.status, v.lat, v.lon, v.currentStationId, v.nextStationId, v.secondsToNext, v.speed, v.angle, r6(v.progress), r6(v.segmentProgress)]);
}

function departures(sim, stationId, t, trips, perGroup) {
  return sim
    .getStationDepartures(stationId, { t, trips, perGroup })
    .map((d) => [d.lineId, d.tripId, d.destination, d.arrivalTime, d.departureTime, d.waitSeconds, d.atPlatform]);
}

function build() {
  const scheduler = new TransitScheduler(METRO, FREQ);
  const out = { generatedBy: "packages/transit_core/tool/make_golden.js", utils: {}, metro: {}, vehicles: {}, departures: {}, surface: {} };

  // --- utils ------------------------------------------------------------------------------
  const easter = {};
  for (let y = 2000; y <= 2040; y++) {
    const d = U.easterSunday(y);
    easter[y] = `${y}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }
  const dayTypes = (hour, minute) => {
    let s = "";
    for (let d = new Date(2026, 0, 1, hour, minute); d.getFullYear() === 2026; d.setDate(d.getDate() + 1)) s += U.dayTypeFor(d);
    return s;
  };
  const instants = [];
  for (const iso of [
    "2026-03-29T00:59:59Z", "2026-03-29T01:00:00Z", "2026-10-25T00:59:59Z", "2026-10-25T01:00:00Z",
    "2026-12-31T22:59:00Z", "2026-12-31T23:30:00Z", "2027-03-28T00:30:00Z", "2027-03-28T01:30:00Z",
    "2026-06-15T10:00:00Z", "2026-01-15T10:00:00Z", "2030-10-27T00:30:00Z", "2030-10-27T01:30:00Z",
  ]) {
    const c = U.milanClock(new Date(iso));
    const p = (n) => String(n).padStart(2, "0");
    instants.push([iso, `${c.getFullYear()}-${p(c.getMonth() + 1)}-${p(c.getDate())} ${p(c.getHours())}:${p(c.getMinutes())}:${p(c.getSeconds())}`]);
  }
  const stationPairs = [["duomo", "cordusio"], ["sesto_1_maggio", "rho_fiera"], ["loreto", "linate_aeroporto"], ["bignami", "san_siro_stadio"]];
  out.utils = {
    easter,
    dayTypes2026Noon: dayTypes(12, 0),
    dayTypes2026At0230: dayTypes(2, 30),
    milanClock: instants,
    geo: stationPairs.map(([a, b]) => {
      const s1 = METRO.stations[a];
      const s2 = METRO.stations[b];
      return [a, b, U.haversine(s1.lat, s1.lon, s2.lat, s2.lon), U.bearing(s1.lat, s1.lon, s2.lat, s2.lon)];
    }),
    formatClock: [0, 3661, 24.5 * 3600, 26 * 3600 + 59 * 60 + 59, 97199.7].map((s) => [s, U.formatClock(s), U.formatClock(s, false)]),
  };

  // --- metro ------------------------------------------------------------------------------
  const metroTrips = {};
  for (const dayType of ["L", "S", "F"]) {
    metroTrips[dayType] = scheduler.generateMetroSchedule(dayType);
    out.metro[dayType] = summarise(metroTrips[dayType]);
  }

  const fixedClock = () => new Date(2026, 8, 28, 12, 0, 0);
  const moments = [["L", 8.25 * 3600], ["L", 24 * 3600 + 20 * 60], ["F", 6.5 * 3600], ["S", 26 * 3600 + 40 * 60], ["L", 3 * 3600 + 10 * 60]];
  for (const [dayType, t] of moments) {
    const sim = new TransitSimulation(METRO, metroTrips[dayType], { clock: fixedClock });
    out.vehicles[`metro|${dayType}|${t}`] = vehicles(sim, t);
  }
  for (const [dayType, t] of [["L", 8.25 * 3600], ["F", 24 * 3600 + 10 * 60]]) {
    const sim = new TransitSimulation(METRO, metroTrips[dayType], { clock: fixedClock });
    for (const station of ["duomo", "loreto", "cadorna", "pagano", "rho_fiera", "bisceglie", "san_donato"]) {
      out.departures[`metro|${dayType}|${t}|${station}`] = departures(sim, station, t, metroTrips[dayType], 3);
    }
  }

  // --- surface ----------------------------------------------------------------------------
  const lines = ["15", "90", "57", "73", "N25", "1"].filter((id) => SURFACE.lines[id]);
  for (const dayType of ["L", "F"]) {
    for (const lineId of lines) {
      out.surface[`schedule|${dayType}|${lineId}`] = summarise(scheduler.generateSurfaceSchedule(lineId, SURFACE, dayType));
    }
  }
  out.surface.counts = [];
  for (const lineId of Object.keys(SURFACE.lines).slice(0, 30)) {
    for (const t of [7.5 * 3600, 13 * 3600, 23.5 * 3600, 25 * 3600]) {
      out.surface.counts.push([lineId, t, scheduler.countActiveSurfaceVehicles(lineId, SURFACE, "L", t)]);
    }
  }
  for (const [lineId, t] of [["90", 3.5 * 3600], ["15", 8 * 3600]]) {
    const trips = scheduler.generateSurfaceSchedule(lineId, SURFACE, "L");
    const sim = new TransitSimulation(SURFACE, trips, { clock: fixedClock });
    out.vehicles[`surface|L|${lineId}|${t}`] = vehicles(sim, t);
    const stop = trips[0].stationIds[3];
    out.departures[`surface|L|${t}|${lineId}|${stop}`] = departures(sim, stop, t, trips, 2);
  }
  return out;
}

const text = JSON.stringify(build()) + "\n";
if (process.argv.includes("--check")) {
  const current = fs.existsSync(OUT) ? fs.readFileSync(OUT, "utf8") : "";
  if (current !== text) {
    console.error(`${path.relative(ROOT, OUT)} is out of date: run node packages/transit_core/tool/make_golden.js`);
    process.exit(1);
  }
  console.log("golden file up to date");
} else {
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, text);
  console.log(`wrote ${path.relative(ROOT, OUT)} (${text.length.toLocaleString()} bytes)`);
}
