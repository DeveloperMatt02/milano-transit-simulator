// Timetable generator.
//
// Official open data only gives *service levels* (trips per time band, first and last
// run), not stop-by-stop timetables. The scheduler turns those levels into a synthetic,
// deterministic timetable: departures from each terminus every `headway` seconds, with
// running times derived from the distance between consecutive stations.

(function (root) {
  "use strict";

  const U =
    typeof module !== "undefined" && module.exports ? require("./utils.js") : root.TransitUtils;

  const METRO = {
    dwellDefault: 25, // seconds at a normal station
    dwellInterchange: 45, // seconds at interchange stations
    cruiseSpeed: 10, // m/s (36 km/h) average commercial speed between stations
    minRun: 50,
    maxRun: 180,
    defaultFirstDeparture: 5.5 * 3600,
    defaultLastArrival: 24.5 * 3600,
  };

  const SURFACE = {
    dwell: 15,
    cruiseSpeed: 4.4, // m/s (~16 km/h) average commercial speed of trams/buses
    minRun: 20,
    maxRun: 200,
  };

  /**
   * Time band used to pick a headway, from the hour of the service day.
   * peak 07:00-09:30, off-peak 09:30-16:30, evening rush 16:30-19:30, evening after 19:30.
   */
  function timeBand(serviceSeconds) {
    const h = serviceSeconds / 3600;
    if (h >= 7 && h < 9.5) return "peak";
    if (h >= 9.5 && h < 16.5) return "mid";
    if (h >= 16.5 && h < 19.5) return "shoulder";
    if (h >= 19.5) return "evening";
    return "mid"; // early morning
  }

  function headwayFromLevels(levels, serviceSeconds) {
    switch (timeBand(serviceSeconds)) {
      case "peak":
        return levels.peak_headway;
      case "shoulder":
        return Math.round((levels.peak_headway + levels.mid_headway) / 2);
      case "evening":
        return levels.evening_headway;
      default:
        return levels.mid_headway;
    }
  }

  class TransitScheduler {
    /**
     * @param {object} metroNetwork   METRO_NETWORK
     * @param {object} [frequencies]  METRO_OFFICIAL_FREQUENCIES (optional, falls back to estimates)
     */
    constructor(metroNetwork, frequencies) {
      this.network = metroNetwork;
      this.frequencies = frequencies || null;
      this._surfaceTripCache = new Map();
      this._surfaceDepartureCache = new Map();
      this._surfaceDurationCache = new Map();
    }

    // ---------------------------------------------------------------------------------
    // Metro
    // ---------------------------------------------------------------------------------

    getTravelTime(stationIdA, stationIdB) {
      const a = this.network.stations[stationIdA];
      const b = this.network.stations[stationIdB];
      if (!a || !b) return 90;
      const t = Math.round(U.haversine(a.lat, a.lon, b.lat, b.lon) / METRO.cruiseSpeed);
      return Math.min(METRO.maxRun, Math.max(METRO.minRun, t));
    }

    getDwellTime(stationId) {
      const s = this.network.stations[stationId];
      return s && s.interchanges && s.interchanges.length > 0 ? METRO.dwellInterchange : METRO.dwellDefault;
    }

    /** Service levels for a line/day type, from open data or a conservative estimate. */
    getMetroLevels(lineId, dayType) {
      const official = this.frequencies && this.frequencies[lineId] && this.frequencies[lineId][dayType];
      if (official) return official;
      const weekend = dayType !== "L";
      return {
        peak_headway: weekend ? 360 : 180,
        mid_headway: weekend ? 360 : 300,
        evening_headway: 540,
        first_departure: weekend && dayType === "F" ? "06:00" : "05:30",
        last_arrival: "24:30",
      };
    }

    /** Headway (seconds) of a metro line at a given service time. */
    getHeadway(lineId, serviceSeconds, dayType) {
      return headwayFromLevels(this.getMetroLevels(lineId, dayType), serviceSeconds);
    }

    /** Stop-by-stop timetable of every metro line for one service day, sorted by start time. */
    generateMetroSchedule(dayType = "L") {
      const trips = [];
      for (const lineId of Object.keys(this.network.lines)) {
        this._generateLineTrips(lineId, dayType, trips);
      }
      trips.sort((a, b) => a.startTime - b.startTime);
      return trips;
    }

    _generateLineTrips(lineId, dayType, out) {
      const line = this.network.lines[lineId];
      if (!line) return;
      const levels = this.getMetroLevels(lineId, dayType);
      const first = U.parseHHMM(levels.first_departure) ?? METRO.defaultFirstDeparture;
      const lastArrival = U.parseHHMM(levels.last_arrival) ?? METRO.defaultLastArrival;
      const name = (id) => this.network.stations[id].name;

      // Each iteration dispatches one train from each end of the line.
      const variants = this._lineVariants(line);
      let t = first;
      let n = 0;
      while (t < lastArrival) {
        const { forward, backward } = variants(n);
        for (const [dir, path] of [["A", forward], ["B", backward]]) {
          const trip = this.createTrip(lineId, `${lineId}-${dir}-${n + 1}`, name(path[0]), name(path[path.length - 1]), path, t);
          if (trip.endTime <= lastArrival) out.push(trip);
        }
        t += this.getHeadway(lineId, t, dayType);
        n++;
      }
    }

    /** Returns a function n -> {forward, backward} station paths, alternating branches. */
    _lineVariants(line) {
      const p = line.paths;
      const join = (...segments) =>
        segments.reduce((acc, seg) => (acc.length ? acc.concat(seg.slice(1)) : seg.slice()), []);
      const rev = (arr) => arr.slice().reverse();

      if (p.branch_rho && p.branch_bisceglie) {
        // M1: Sesto 1° Maggio -> Pagano, then alternately Rho Fieramilano / Bisceglie.
        return (n) => {
          const branch = n % 2 === 0 ? p.branch_bisceglie : p.branch_rho;
          const forward = join(p.trunk, branch);
          return { forward, backward: rev(forward) };
        };
      }
      if (p.branch_gessate && p.branch_cologno && p.branch_assago && p.branch_abbiategrasso) {
        // M2: north branches alternate; one train in three serves Assago in the south.
        return (n) => {
          const north = n % 2 === 0 ? p.branch_cologno : p.branch_gessate;
          const south = n % 3 === 2 ? p.branch_assago : p.branch_abbiategrasso;
          const forward = join(north, p.trunk, south);
          return { forward, backward: rev(forward) };
        };
      }
      return () => ({ forward: p.trunk.slice(), backward: rev(p.trunk) });
    }

    /** Builds a trip with arrival/departure times at every stop. */
    createTrip(lineId, tripId, from, to, stationIds, startTime, opts = {}) {
      const travel = opts.travelTime || ((a, b) => this.getTravelTime(a, b));
      const dwell = opts.dwellTime || ((id) => this.getDwellTime(id));
      const stopTimes = [];
      let clock = startTime;
      for (let i = 0; i < stationIds.length; i++) {
        const last = i === stationIds.length - 1;
        const arrival = clock;
        const departure = last ? arrival : arrival + dwell(stationIds[i]);
        stopTimes.push({ stationId: stationIds[i], arrivalTime: arrival, departureTime: departure });
        if (!last) clock = departure + travel(stationIds[i], stationIds[i + 1]);
      }
      return {
        lineId,
        tripId,
        mode: opts.mode || "METRO",
        from,
        to,
        stationIds,
        startTime,
        endTime: clock,
        stopTimes,
      };
    }

    // ---------------------------------------------------------------------------------
    // Surface (tram, trolleybus, bus)
    // ---------------------------------------------------------------------------------

    getSurfaceTravelTime(stopIdA, stopIdB, surfaceNetwork) {
      const a = surfaceNetwork.stations[stopIdA];
      const b = surfaceNetwork.stations[stopIdB];
      if (!a || !b) return 60;
      const t = Math.round(U.haversine(a.lat, a.lon, b.lat, b.lon) / SURFACE.cruiseSpeed);
      return Math.min(SURFACE.maxRun, Math.max(SURFACE.minRun, t));
    }

    getSurfaceHeadway(serviceSeconds, levels) {
      return headwayFromLevels(levels, serviceSeconds);
    }

    /** Running time of a route from first to last stop (seconds). */
    getSurfaceRouteDuration(route, surfaceNetwork) {
      if (this._surfaceDurationCache.has(route.id)) return this._surfaceDurationCache.get(route.id);
      let duration = 0;
      for (let i = 0; i < route.stops.length - 1; i++) {
        duration += SURFACE.dwell + this.getSurfaceTravelTime(route.stops[i], route.stops[i + 1], surfaceNetwork);
      }
      this._surfaceDurationCache.set(route.id, duration);
      return duration;
    }

    /** Departure times (service seconds) from the first stop of a route; [] if it does not run. */
    getSurfaceDepartures(route, dayType) {
      const key = `${route.id}|${dayType}`;
      if (this._surfaceDepartureCache.has(key)) return this._surfaceDepartureCache.get(key);
      const levels = route.frequencies && route.frequencies[dayType];
      const departures = [];
      if (levels) {
        const start = U.parseHHMM(levels.service_start);
        const end = U.parseHHMM(levels.service_end);
        if (start !== null && end !== null) {
          for (let t = start; t <= end; t += this.getSurfaceHeadway(t, levels)) departures.push(t);
        }
      }
      this._surfaceDepartureCache.set(key, departures);
      return departures;
    }

    /** Full stop-by-stop schedule of one surface line (cached per line and day type). */
    generateSurfaceSchedule(lineId, surfaceNetwork, dayType = "L") {
      const key = `${lineId}|${dayType}`;
      if (this._surfaceTripCache.has(key)) return this._surfaceTripCache.get(key);
      const line = surfaceNetwork.lines[lineId];
      const trips = [];
      if (line) {
        const opts = {
          mode: line.type,
          travelTime: (a, b) => this.getSurfaceTravelTime(a, b, surfaceNetwork),
          dwellTime: () => SURFACE.dwell,
        };
        for (const route of Object.values(line.percorsi)) {
          const stops = route.stops;
          const from = surfaceNetwork.stations[stops[0]];
          const to = surfaceNetwork.stations[stops[stops.length - 1]];
          this.getSurfaceDepartures(route, dayType).forEach((t, i) => {
            trips.push(
              this.createTrip(lineId, `${lineId}-${route.id}-${i + 1}`, from ? from.name : "", to ? to.name : "", stops, t, opts)
            );
          });
        }
      }
      trips.sort((a, b) => a.startTime - b.startTime);
      this._surfaceTripCache.set(key, trips);
      return trips;
    }

    /** Number of vehicles of a surface line on the road at service time t (no full schedule needed). */
    countActiveSurfaceVehicles(lineId, surfaceNetwork, dayType, t) {
      const line = surfaceNetwork.lines[lineId];
      if (!line) return 0;
      let count = 0;
      for (const route of Object.values(line.percorsi)) {
        const duration = this.getSurfaceRouteDuration(route, surfaceNetwork);
        for (const d of this.getSurfaceDepartures(route, dayType)) {
          if (U.isActiveAt(d, d + duration, t)) count++;
        }
      }
      return count;
    }
  }

  TransitScheduler.timeBand = timeBand;

  if (typeof module !== "undefined" && module.exports) {
    module.exports = TransitScheduler;
  } else {
    root.TransitScheduler = TransitScheduler;
  }
})(typeof window !== "undefined" ? window : globalThis);
