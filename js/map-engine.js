// Leaflet map: open vector base map, metro network, the selected surface line and vehicles.
//
// Base map: OpenFreeMap vector tiles rendered by MapLibre GL inside Leaflet (through the
// maplibre-gl-leaflet adapter). No API key is needed. When WebGL is missing or the style
// cannot be loaded, the map falls back to raster OpenStreetMap tiles.

(function (root) {
  "use strict";

  const DATA_ATTRIBUTION =
    'Data: <a href="https://dati.comune.milano.it" target="_blank" rel="noopener">Comune di Milano</a> (CC BY 4.0)';
  const OSM_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a>';
  const VECTOR_ATTRIBUTION =
    `<a href="https://openfreemap.org" target="_blank" rel="noopener">OpenFreeMap</a> ` +
    `&copy; <a href="https://www.openmaptiles.org/" target="_blank" rel="noopener">OpenMapTiles</a> ${OSM_ATTRIBUTION} · ${DATA_ATTRIBUTION}`;
  const RASTER_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png";
  const RASTER_ATTRIBUTION = `${OSM_ATTRIBUTION} contributors · ${DATA_ATTRIBUTION}`;
  const STYLE_TIMEOUT_MS = 12000;
  const MILAN_CENTER = [45.4642, 9.19];

  function webglAvailable() {
    try {
      const canvas = document.createElement("canvas");
      return !!(canvas.getContext("webgl2") || canvas.getContext("webgl"));
    } catch (e) {
      return false;
    }
  }

  class TransitMap {
    /**
     * @param {string} containerId
     * @param {object} metroNetwork
     * @param {object} handlers  { onStationClick(id), onVehicleClick(tripId), onBackgroundClick() }
     * @param {object} theme     { id, def } from ThemeManager
     */
    constructor(containerId, metroNetwork, handlers, theme) {
      this.metroNetwork = metroNetwork;
      this.handlers = handlers || {};
      this.themeId = theme.id;
      this.theme = theme.def;
      this.metroStationMarkers = {};
      this.surfaceStopMarkers = {};
      this.linePolylines = {};
      this.surfaceLine = null;
      this.surfaceNetwork = null;
      this.vehicleMarkers = {};
      this.selectedStationId = null;
      this.highlightedLineId = null;
      this.labels = { vehicleTooltip: (v) => `${v.lineId} → ${v.to}` };

      this.map = L.map(containerId, {
        center: MILAN_CENTER,
        zoom: 13,
        minZoom: 10,
        maxZoom: 18,
        zoomControl: false,
        attributionControl: false,
        tapTolerance: 20,
      });
      this.attribution = L.control.attribution({ position: "bottomright", prefix: false }).addTo(this.map);
      this.zoomControl = L.control.zoom({ position: "bottomright" }).addTo(this.map);

      this._createBaseLayer();
      this.metroLayer = L.layerGroup().addTo(this.map);
      this.surfaceLayer = L.layerGroup().addTo(this.map);
      this.vehicleLayer = L.layerGroup().addTo(this.map);
      this.map.on("click", () => this.handlers.onBackgroundClick && this.handlers.onBackgroundClick());
      this._drawMetroNetwork();
    }

    // --- Base map -----------------------------------------------------------------------

    _createBaseLayer() {
      const canUseVector = typeof L.maplibreGL === "function" && root.maplibregl && webglAvailable();
      if (canUseVector) {
        try {
          this.baseLayer = L.maplibreGL({
            style: this.theme.basemap,
            attributionControl: false,
            interactive: false,
          }).addTo(this.map);
          this.attribution.addAttribution(VECTOR_ATTRIBUTION);
          this.baseKind = "vector";
          this._currentStyle = this.theme.basemap;
          this._watchStyle();
          return;
        } catch (e) {
          /* fall through to raster */
        }
      }
      this._useRasterFallback();
    }

    /** Switches to raster tiles if the vector style never loads (offline, blocked, service down). */
    _watchStyle() {
      const gl = this.baseLayer.getMaplibreMap && this.baseLayer.getMaplibreMap();
      if (!gl) return;
      let loaded = false;
      gl.on("style.load", () => (loaded = true));
      gl.on("error", (e) => {
        const status = e && e.error && e.error.status;
        if (!loaded && (status || String(e && e.error && e.error.message).includes("style"))) this._useRasterFallback();
      });
      setTimeout(() => !loaded && this.baseKind === "vector" && this._useRasterFallback(), STYLE_TIMEOUT_MS);
    }

    _useRasterFallback() {
      if (this.baseLayer) this.map.removeLayer(this.baseLayer);
      this.attribution.removeAttribution(VECTOR_ATTRIBUTION);
      this.baseLayer = L.tileLayer(RASTER_URL, { maxZoom: 19, attribution: RASTER_ATTRIBUTION }).addTo(this.map);
      this.baseLayer.bringToBack();
      this.baseKind = "raster";
      this._applyRasterFilter();
    }

    /** OSM raster tiles only come in a light style: darken them for the dark themes. */
    _applyRasterFilter() {
      const pane = this.map.getPane("tilePane");
      pane.style.filter =
        this.baseKind === "raster" && this.themeId !== "noorda-light"
          ? "invert(1) hue-rotate(180deg) brightness(0.85) contrast(0.9) saturate(0.6)"
          : "";
    }

    /** Applies a theme: base map style, line colours and weights, markers. */
    setTheme(theme) {
      this.themeId = theme.id;
      this.theme = theme.def;
      if (this.baseKind === "vector" && this.theme.basemap !== this._currentStyle) {
        const gl = this.baseLayer.getMaplibreMap && this.baseLayer.getMaplibreMap();
        if (gl) gl.setStyle(this.theme.basemap);
        this._currentStyle = this.theme.basemap;
      }
      this._applyRasterFilter();
      this.metroLayer.clearLayers();
      this.linePolylines = {};
      this.metroStationMarkers = {};
      this._drawMetroNetwork();
      this.highlightLine(this.highlightedLineId);
      if (this.surfaceLine) this.drawSurfaceLine(this.surfaceLine, this.surfaceNetwork, null);
      for (const entry of Object.values(this.vehicleMarkers)) entry.iconKey = null; // rebuild icons with new colours
      this._refreshSelection();
    }

    /** Colour of a metro line in the current theme. */
    lineColor(lineId) {
      return (this.theme.lineColors && this.theme.lineColors[lineId]) || (this.metroNetwork.lines[lineId] || {}).color || "#888";
    }

    /** Colour of a surface mode (TRAM / FILOBUS / BUS) in the current theme. */
    modeColor(mode, fallback) {
      return (this.theme.modeColors && this.theme.modeColors[mode]) || fallback || "#1165B0";
    }

    setZoomControlVisible(visible) {
      const el = this.zoomControl.getContainer();
      if (el) el.style.display = visible ? "" : "none";
    }

    // --- Metro --------------------------------------------------------------------------

    _drawMetroNetwork() {
      const { stations, lines } = this.metroNetwork;
      for (const lineId of Object.keys(lines)) {
        this.linePolylines[lineId] = Object.values(lines[lineId].paths).map((path) =>
          L.polyline(
            path.map((id) => [stations[id].lat, stations[id].lon]),
            { color: this.lineColor(lineId), weight: this.theme.lineWeight, opacity: this.theme.lineOpacity, lineCap: "round", lineJoin: "round", interactive: false }
          ).addTo(this.metroLayer)
        );
      }

      for (const station of Object.values(stations)) {
        const interchange = station.lines.length > 1;
        const size = interchange ? 16 : 12;
        const marker = L.marker([station.lat, station.lon], {
          icon: L.divIcon({
            html: `<div class="station-marker ${interchange ? "interchange" : ""}" style="--station-color:${this.lineColor(station.lines[0])}"></div>`,
            className: "station-icon",
            iconSize: [size, size],
            iconAnchor: [size / 2, size / 2],
          }),
          zIndexOffset: interchange ? 100 : 50,
          title: station.name,
        }).addTo(this.metroLayer);
        marker.bindTooltip(station.name, { direction: "top", offset: [0, -10], className: "map-tooltip" });
        marker.on("click", () => this.handlers.onStationClick && this.handlers.onStationClick(station.id));
        this.metroStationMarkers[station.id] = marker;
      }
      this.highlightLine(this.highlightedLineId);
    }

    showMetro(visible) {
      if (visible) this.map.addLayer(this.metroLayer);
      else this.map.removeLayer(this.metroLayer);
    }

    /** Emphasises one metro line (or resets all lines when lineId is null). */
    highlightLine(lineId) {
      this.highlightedLineId = lineId;
      const w = this.theme.lineWeight;
      for (const [id, polylines] of Object.entries(this.linePolylines)) {
        const target = id === lineId;
        for (const p of polylines) {
          p.setStyle({
            weight: lineId === null ? w : target ? w + 3 : Math.max(2, w - 2.5),
            opacity: lineId === null || target ? this.theme.lineOpacity : 0.25,
          });
          this._setFilter(p, this.theme.glow && (lineId === null || target) ? this.theme.glow : "none");
          if (target) p.bringToFront();
        }
      }
    }

    _setFilter(layer, filter) {
      const apply = () => {
        const el = layer.getElement && layer.getElement();
        if (el) el.style.filter = filter;
      };
      apply();
      layer.off("add").on("add", apply);
    }

    // --- Surface ------------------------------------------------------------------------

    /** Draws every route of a surface line; fits the map to it unless pad is null. */
    drawSurfaceLine(line, surfaceNetwork, pad = { left: 0, right: 0, top: 0, bottom: 0 }) {
      this.clearSurface();
      this.surfaceLine = line;
      this.surfaceNetwork = surfaceNetwork;
      const color = this.modeColor(line.type, line.color);
      const drawn = new Set();
      const bounds = L.latLngBounds([]);

      for (const route of Object.values(line.percorsi)) {
        const coords = route.stops.map((id) => surfaceNetwork.stations[id]).filter(Boolean).map((s) => [s.lat, s.lon]);
        if (coords.length < 2) continue;
        const polyline = L.polyline(coords, {
          color,
          weight: Math.max(4, this.theme.lineWeight - 0.5),
          opacity: 0.9,
          lineCap: "round",
          lineJoin: "round",
          interactive: false,
        }).addTo(this.surfaceLayer);
        this._setFilter(polyline, this.theme.glow || "none");
        bounds.extend(polyline.getBounds());

        for (const stopId of route.stops) {
          const stop = surfaceNetwork.stations[stopId];
          if (!stop || drawn.has(stopId)) continue;
          drawn.add(stopId);
          const marker = L.marker([stop.lat, stop.lon], {
            icon: L.divIcon({
              html: `<div class="station-marker surface" style="--station-color:${color}"></div>`,
              className: "station-icon",
              iconSize: [10, 10],
              iconAnchor: [5, 5],
            }),
            zIndexOffset: 60,
            title: stop.name,
          }).addTo(this.surfaceLayer);
          marker.bindTooltip(stop.name, { direction: "top", offset: [0, -6], className: "map-tooltip" });
          marker.on("click", () => this.handlers.onStationClick && this.handlers.onStationClick(stopId));
          this.surfaceStopMarkers[stopId] = marker;
        }
      }
      if (pad && bounds.isValid()) {
        this.map.fitBounds(bounds, {
          paddingTopLeft: [pad.left + 30, pad.top + 30],
          paddingBottomRight: [pad.right + 30, pad.bottom + 30],
          maxZoom: 15,
        });
      }
      this._refreshSelection();
    }

    clearSurface() {
      this.surfaceLayer.clearLayers();
      this.surfaceStopMarkers = {};
      this.surfaceLine = null;
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
          marker.bindTooltip(() => this.labels.vehicleTooltip(entry.vehicle), { direction: "right", className: "map-tooltip" });
          marker.on("click", () => this.handlers.onVehicleClick && this.handlers.onVehicleClick(v.tripId));
          marker.addTo(this.vehicleLayer);
          entry = this.vehicleMarkers[v.tripId] = { marker, iconKey: null, vehicle: v };
        } else {
          entry.marker.setLatLng([v.lat, v.lon]);
        }
        entry.vehicle = v;

        if (entry.iconKey !== iconKey) {
          const color = colorFor(v);
          const labelColor = TransitUtils.prefersDarkText(color) ? "#111418" : "#ffffff";
          entry.marker.setIcon(
            L.divIcon({
              html: `<div class="vehicle-marker ${moving ? "moving" : "stopped"} ${tracked ? "tracked" : ""}" style="--vehicle-color:${color}">
                  <span class="vehicle-label" style="color:${labelColor}">${TransitUtils.escapeHtml(v.lineId)}</span>
                  <div class="vehicle-heading" style="transform: rotate(${v.angle}deg)"><div class="vehicle-arrow"></div></div>
                </div>`,
              className: "vehicle-icon",
              iconSize: [24, 24],
              iconAnchor: [12, 12],
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
      document.querySelectorAll(".station-marker.selected").forEach((el) => el.classList.remove("selected"));
      const marker = this.selectedStationId && this._markerFor(this.selectedStationId);
      const el = marker && marker.getElement && marker.getElement();
      const dot = el && el.querySelector(".station-marker");
      if (dot) dot.classList.add("selected");
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
