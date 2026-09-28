// Leaflet map layer: base tiles, metro network, the selected surface line and vehicles.

(function (root) {
  "use strict";

  const TILE_URLS = {
    dark: "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
    light: "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png",
  };
  const ATTRIBUTION =
    '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> ' +
    '&copy; <a href="https://carto.com/attributions" target="_blank" rel="noopener">CARTO</a> · ' +
    'Data: <a href="https://dati.comune.milano.it" target="_blank" rel="noopener">Comune di Milano</a> (CC BY 4.0)';
  const MILAN_CENTER = [45.4642, 9.19];
  const BASE_WEIGHT = 4;

  class TransitMap {
    /**
     * @param {string} containerId
     * @param {object} metroNetwork
     * @param {object} handlers { onStationClick(stationId), onVehicleClick(tripId), onBackgroundClick() }
     */
    constructor(containerId, metroNetwork, handlers = {}) {
      this.metroNetwork = metroNetwork;
      this.handlers = handlers;
      this.metroStationMarkers = {};
      this.surfaceStopMarkers = {};
      this.linePolylines = {};
      this.vehicleMarkers = {};
      this.selectedStationId = null;
      this.labels = { vehicleTooltip: (v) => `${v.lineId} → ${v.to}` };

      this.map = L.map(containerId, {
        center: MILAN_CENTER,
        zoom: 13,
        minZoom: 10,
        maxZoom: 17,
        zoomControl: false,
        attributionControl: false,
      });
      L.control.attribution({ position: "bottomright", prefix: false }).addTo(this.map);
      L.control.zoom({ position: "bottomright" }).addTo(this.map);

      this.tileLayer = L.tileLayer(TILE_URLS.dark, {
        maxZoom: 20,
        subdomains: "abcd",
        attribution: ATTRIBUTION,
      }).addTo(this.map);

      this.metroLayer = L.layerGroup().addTo(this.map);
      this.surfaceLayer = L.layerGroup().addTo(this.map);
      this.vehicleLayer = L.layerGroup().addTo(this.map);

      this.map.on("click", () => this.handlers.onBackgroundClick && this.handlers.onBackgroundClick());
      this._drawMetroNetwork();
    }

    setTheme(theme) {
      this.tileLayer.setUrl(theme === "light" ? TILE_URLS.light : TILE_URLS.dark);
    }

    // --- Metro --------------------------------------------------------------------------

    _drawMetroNetwork() {
      const { stations, lines } = this.metroNetwork;

      for (const lineId of Object.keys(lines)) {
        const line = lines[lineId];
        this.linePolylines[lineId] = Object.values(line.paths).map((path) => {
          const polyline = L.polyline(
            path.map((id) => [stations[id].lat, stations[id].lon]),
            { color: line.color, weight: BASE_WEIGHT, opacity: 0.9, lineCap: "round", lineJoin: "round", interactive: false }
          ).addTo(this.metroLayer);
          this._setGlow(polyline, `drop-shadow(0 0 4px ${line.color})`);
          return polyline;
        });
      }

      for (const station of Object.values(stations)) {
        const interchange = station.lines.length > 1;
        const color = interchange ? "#ffffff" : lines[station.lines[0]].color;
        const size = interchange ? 16 : 12;
        const marker = L.marker([station.lat, station.lon], {
          icon: L.divIcon({
            html: `<div class="station-glow-marker ${interchange ? "interchange-station" : ""}" style="--station-color:${color}"><div class="station-inner-dot"></div></div>`,
            className: "custom-station-icon",
            iconSize: [size, size],
            iconAnchor: [size / 2, size / 2],
          }),
          zIndexOffset: interchange ? 100 : 50,
          keyboard: true,
          title: station.name,
        }).addTo(this.metroLayer);
        marker.bindTooltip(station.name, { direction: "top", offset: [0, -10], className: "station-tooltip" });
        marker.on("click", () => this.handlers.onStationClick && this.handlers.onStationClick(station.id));
        this.metroStationMarkers[station.id] = marker;
      }
    }

    showMetro(visible) {
      if (visible) this.map.addLayer(this.metroLayer);
      else this.map.removeLayer(this.metroLayer);
    }

    /** Emphasises one metro line (or resets all lines when lineId is null). */
    highlightLine(lineId) {
      for (const [id, polylines] of Object.entries(this.linePolylines)) {
        const color = this.metroNetwork.lines[id].color;
        for (const p of polylines) {
          const isTarget = id === lineId;
          p.setStyle({ weight: lineId === null ? BASE_WEIGHT : isTarget ? 7 : 2, opacity: lineId === null || isTarget ? 0.9 : 0.35 });
          this._setGlow(p, lineId === null ? `drop-shadow(0 0 4px ${color})` : isTarget ? `drop-shadow(0 0 8px ${color})` : "none");
        }
      }
    }

    _setGlow(layer, filter) {
      const apply = () => {
        const el = layer.getElement && layer.getElement();
        if (el) el.style.filter = filter;
      };
      apply();
      layer.off("add").on("add", apply);
    }

    // --- Surface ------------------------------------------------------------------------

    /** Draws every route of a surface line and fits the map to it. */
    drawSurfaceLine(line, surfaceNetwork) {
      this.clearSurface();
      const color = line.color || "#007AFF";
      const drawn = new Set();
      const bounds = L.latLngBounds([]);

      for (const route of Object.values(line.percorsi)) {
        const coords = route.stops
          .map((id) => surfaceNetwork.stations[id])
          .filter(Boolean)
          .map((s) => [s.lat, s.lon]);
        if (coords.length < 2) continue;
        const polyline = L.polyline(coords, { color, weight: 5, opacity: 0.85, lineCap: "round", lineJoin: "round", interactive: false }).addTo(this.surfaceLayer);
        this._setGlow(polyline, `drop-shadow(0 0 6px ${color})`);
        bounds.extend(polyline.getBounds());

        for (const stopId of route.stops) {
          const stop = surfaceNetwork.stations[stopId];
          if (!stop || drawn.has(stopId)) continue;
          drawn.add(stopId);
          const marker = L.marker([stop.lat, stop.lon], {
            icon: L.divIcon({
              html: `<div class="station-glow-marker surface-stop" style="--station-color:${color}"><div class="station-inner-dot"></div></div>`,
              className: "custom-station-icon",
              iconSize: [10, 10],
              iconAnchor: [5, 5],
            }),
            zIndexOffset: 60,
            title: stop.name,
          }).addTo(this.surfaceLayer);
          marker.bindTooltip(stop.name, { direction: "top", offset: [0, -6], className: "station-tooltip" });
          marker.on("click", () => this.handlers.onStationClick && this.handlers.onStationClick(stopId));
          this.surfaceStopMarkers[stopId] = marker;
        }
      }
      if (bounds.isValid()) this.map.fitBounds(bounds, { padding: [60, 60], maxZoom: 15 });
      this._refreshSelection();
    }

    clearSurface() {
      this.surfaceLayer.clearLayers();
      this.surfaceStopMarkers = {};
    }

    // --- Vehicles -----------------------------------------------------------------------

    /** Creates, moves or removes vehicle markers. Called every animation frame. */
    updateVehicles(vehicles, trackedTripId, colorFor) {
      const active = new Set();
      for (const v of vehicles) {
        active.add(v.tripId);
        const tracked = v.tripId === trackedTripId;
        const moving = v.status === "MOVING";
        const iconKey = `${v.status}|${tracked}|${v.angle}`;
        let entry = this.vehicleMarkers[v.tripId];

        if (!entry) {
          const marker = L.marker([v.lat, v.lon], { zIndexOffset: 500, keyboard: false });
          marker.bindTooltip(() => this.labels.vehicleTooltip(entry.vehicle), { direction: "right", className: "train-tooltip" });
          marker.on("click", () => this.handlers.onVehicleClick && this.handlers.onVehicleClick(v.tripId));
          marker.addTo(this.vehicleLayer);
          entry = this.vehicleMarkers[v.tripId] = { marker, iconKey: null, vehicle: v };
        } else {
          entry.marker.setLatLng([v.lat, v.lon]);
        }
        entry.vehicle = v;

        if (entry.iconKey !== iconKey) {
          const color = colorFor(v);
          entry.marker.setIcon(
            L.divIcon({
              html: `<div class="train-glow-marker ${moving ? "moving-train" : "stopped-train"} ${tracked ? "tracked-train" : ""}" style="--train-color:${color}">
                  <span class="train-label">${TransitUtils.escapeHtml(v.lineId)}</span>
                  <div class="train-direction-pointer" style="transform: rotate(${v.angle}deg)"><div class="pointer-arrow"></div></div>
                  ${moving ? '<div class="train-pulse-ring"></div>' : ""}
                </div>`,
              className: "custom-train-icon",
              iconSize: [22, 22],
              iconAnchor: [11, 11],
            })
          );
          entry.marker.setZIndexOffset(tracked ? 1000 : 500);
          entry.iconKey = iconKey;
        }
      }

      for (const tripId of Object.keys(this.vehicleMarkers)) {
        if (!active.has(tripId)) {
          this.vehicleLayer.removeLayer(this.vehicleMarkers[tripId].marker);
          delete this.vehicleMarkers[tripId];
        }
      }
    }

    clearVehicles() {
      this.vehicleLayer.clearLayers();
      this.vehicleMarkers = {};
    }

    // --- Selection & camera -------------------------------------------------------------

    _markerFor(stationId) {
      return this.metroStationMarkers[stationId] || this.surfaceStopMarkers[stationId] || null;
    }

    setSelectedStation(stationId) {
      this.selectedStationId = stationId;
      this._refreshSelection();
    }

    _refreshSelection() {
      document.querySelectorAll(".station-glow-marker.focused-station").forEach((el) => el.classList.remove("focused-station"));
      const marker = this.selectedStationId && this._markerFor(this.selectedStationId);
      const el = marker && marker.getElement && marker.getElement();
      const glow = el && el.querySelector(".station-glow-marker");
      if (glow) glow.classList.add("focused-station");
    }

    /**
     * Centres the map on a point inside the area not covered by floating panels.
     * @param {{left:number,right:number,top:number,bottom:number}} pad  covered pixels per side
     */
    focusOn(lat, lon, zoom, pad = { left: 0, right: 0, top: 0, bottom: 0 }) {
      const z = Math.max(zoom || 0, this.map.getZoom());
      const point = this.map.project([lat, lon], z).add([(pad.right - pad.left) / 2, (pad.bottom - pad.top) / 2]);
      this.map.setView(this.map.unproject(point, z), z, { animate: true, duration: 0.8 });
    }

    /** True when the point is inside the visible (uncovered) part of the map. */
    isVisible(lat, lon, pad = { left: 0, right: 0, top: 0, bottom: 0 }) {
      const p = this.map.latLngToContainerPoint([lat, lon]);
      const size = this.map.getSize();
      const m = 30;
      return p.x > pad.left + m && p.x < size.x - pad.right - m && p.y > pad.top + m && p.y < size.y - pad.bottom - m;
    }
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = TransitMap;
  } else {
    root.TransitMap = TransitMap;
  }
})(typeof window !== "undefined" ? window : globalThis);
