// Simulation clock and vehicle state solver.
//
// The simulation is stateless with respect to vehicles: given the timetable and the
// current service time, the position of every vehicle is computed from scratch by
// interpolating between the two stops it is travelling between. This makes time travel
// (scrubbing the timeline, 60x speed) trivially consistent.

(function (root) {
  "use strict";

  const U =
    typeof module !== "undefined" && module.exports ? require("./utils.js") : root.TransitUtils;

  const nowMs = () =>
    typeof performance !== "undefined" && performance.now ? performance.now() : Date.now();

  class TransitSimulation {
    /**
     * @param {object} network  METRO_NETWORK or SURFACE_NETWORK (stations lookup)
     * @param {Array} trips      output of TransitScheduler
     * @param {object} [opts]    { clock: () => Date } injectable for tests
     */
    constructor(network, trips, opts = {}) {
      this.network = network;
      this.trips = trips || [];
      this.clock = opts.clock || (() => U.milanClock(new Date()));

      this.isRealTime = true;
      this.isPlaying = true;
      this.speed = 1;
      this.simTime = this.getRealServiceTime();
      this._lastTick = nowMs();
    }

    /** Current wall-clock time converted to service-day seconds. */
    getRealServiceTime() {
      const d = this.clock();
      const clockSeconds = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds() + d.getMilliseconds() / 1000;
      return U.toServiceTime(clockSeconds);
    }

    setTrips(network, trips) {
      this.network = network;
      this.trips = trips || [];
    }

    setRealTimeMode(active) {
      this.isRealTime = active;
      if (active) {
        this.speed = 1;
        this.isPlaying = true;
        this.simTime = this.getRealServiceTime();
      }
      this._lastTick = nowMs();
    }

    /** Jump to a service time (switches to manual mode). */
    setTime(serviceSeconds) {
      this.isRealTime = false;
      this.simTime = this._wrap(serviceSeconds);
      this._lastTick = nowMs();
    }

    setPlaying(playing) {
      if (!this.isRealTime) this.isPlaying = playing;
      this._lastTick = nowMs();
    }

    setSpeed(speed) {
      if (!this.isRealTime) this.speed = speed;
      this._lastTick = nowMs();
    }

    /** Keeps service time inside [03:00, 27:00). */
    _wrap(t) {
      const span = U.SERVICE_DAY_END - U.SERVICE_DAY_START;
      return U.SERVICE_DAY_START + ((((t - U.SERVICE_DAY_START) % span) + span) % span);
    }

    /** Advances the clock; returns true when the service day rolled over (03:00). */
    tick() {
      const now = nowMs();
      const dt = (now - this._lastTick) / 1000;
      this._lastTick = now;
      const before = this.simTime;
      if (this.isRealTime) {
        this.simTime = this.getRealServiceTime();
      } else if (this.isPlaying) {
        this.simTime = this._wrap(this.simTime + dt * this.speed);
      }
      return this.simTime < before - 3600; // wrapped past 27:00 -> 03:00
    }

    /** All vehicles running at the current time with position and status. */
    getActiveVehicles(t = this.simTime) {
      const vehicles = [];
      for (const trip of this.trips) {
        if (trip.startTime > t + U.DAY) break; // trips are sorted by start time
        let effective = null;
        if (t >= trip.startTime && t <= trip.endTime) effective = t;
        else if (t + U.DAY >= trip.startTime && t + U.DAY <= trip.endTime) effective = t + U.DAY;
        if (effective === null) continue;
        const state = this.getVehicleState(trip, effective);
        if (state) vehicles.push(state);
      }
      return vehicles;
    }

    /** Position and status of a trip at service time t (null if not running). */
    getVehicleState(trip, t) {
      const stops = trip.stopTimes;
      const station = (id) => this.network.stations[id];
      const base = {
        tripId: trip.tripId,
        lineId: trip.lineId,
        mode: trip.mode,
        from: trip.from,
        to: trip.to,
        terminusArrival: trip.endTime,
      };

      for (let i = 0; i < stops.length; i++) {
        const stop = stops[i];
        const s1 = station(stop.stationId);
        const next = stops[i + 1];
        const s2 = next ? station(next.stationId) : null;

        if (t >= stop.arrivalTime && t <= stop.departureTime) {
          return Object.assign(base, {
            status: "STOPPED",
            currentStationId: stop.stationId,
            currentStationName: s1 ? s1.name : "",
            nextStationId: next ? next.stationId : null,
            nextStationName: s2 ? s2.name : "",
            secondsToNext: next ? next.arrivalTime - t : 0,
            lat: s1 ? s1.lat : 45.4642,
            lon: s1 ? s1.lon : 9.19,
            speed: 0,
            angle: s1 && s2 ? U.bearing(s1.lat, s1.lon, s2.lat, s2.lon) : 0,
            progress: stops.length > 1 ? i / (stops.length - 1) : 1,
            segmentProgress: 0,
          });
        }

        if (next && t > stop.departureTime && t < next.arrivalTime) {
          if (!s1 || !s2) return null;
          const duration = next.arrivalTime - stop.departureTime;
          const f = (t - stop.departureTime) / duration;
          const distance = U.haversine(s1.lat, s1.lon, s2.lat, s2.lon);
          return Object.assign(base, {
            status: "MOVING",
            currentStationId: stop.stationId,
            currentStationName: s1.name,
            nextStationId: next.stationId,
            nextStationName: s2.name,
            secondsToNext: next.arrivalTime - t,
            lat: s1.lat + (s2.lat - s1.lat) * f,
            lon: s1.lon + (s2.lon - s1.lon) * f,
            speed: Math.round((distance / duration) * 3.6),
            angle: U.bearing(s1.lat, s1.lon, s2.lat, s2.lon),
            progress: (i + f) / (stops.length - 1),
            segmentProgress: f,
          });
        }
      }
      return null;
    }

    /**
     * Next departures from a stop, grouped by line and destination.
     * Arrivals at the terminus are excluded (a train ending here does not "depart").
     *
     * @param {string} stationId
     * @param {object} [opts] { trips, perGroup = 3, horizon = 7200, t }
     */
    getStationDepartures(stationId, opts = {}) {
      const trips = opts.trips || this.trips;
      const perGroup = opts.perGroup ?? 3;
      const horizon = opts.horizon ?? 7200;
      const t = opts.t ?? this.simTime;
      const results = [];

      for (const trip of trips) {
        const idx = trip.stationIds.indexOf(stationId);
        if (idx === -1 || idx === trip.stationIds.length - 1) continue;
        const stop = trip.stopTimes[idx];
        for (const offset of [0, U.DAY]) {
          const now = t + offset;
          if (stop.departureTime >= now && stop.arrivalTime <= now + horizon) {
            const wait = stop.arrivalTime - now;
            results.push({
              lineId: trip.lineId,
              mode: trip.mode,
              tripId: trip.tripId,
              destination: trip.to,
              arrivalTime: stop.arrivalTime - offset,
              departureTime: stop.departureTime - offset,
              waitSeconds: Math.max(0, wait),
              atPlatform: wait <= 0,
            });
            break;
          }
        }
      }

      results.sort((a, b) => a.arrivalTime - b.arrivalTime);
      const perKey = new Map();
      return results.filter((dep) => {
        const key = `${dep.lineId}|${dep.destination}`;
        const n = perKey.get(key) || 0;
        perKey.set(key, n + 1);
        return n < perGroup;
      });
    }
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = TransitSimulation;
  } else {
    root.TransitSimulation = TransitSimulation;
  }
})(typeof window !== "undefined" ? window : globalThis);
