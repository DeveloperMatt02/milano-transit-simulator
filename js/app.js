// Application controller: wires data, scheduler, simulation, map and UI together.
//
// Rendering strategy
//   * Map markers are updated on every animation frame (smooth movement).
//   * DOM panels are refreshed at most 4 times per second, and only when their HTML
//     actually changes, so hover states and clicks are never interrupted.
//   * All list clicks use event delegation on stable containers.

(function () {
  "use strict";

  const U = window.TransitUtils;
  const { t } = window.I18N;
  const esc = U.escapeHtml;

  const UI_REFRESH_MS = 250;
  const METRO_TERMINI = {
    M1: "Sesto 1° Maggio ⇄ Rho Fieramilano / Bisceglie",
    M2: "Gessate / Cologno Nord ⇄ Assago Forum / Abbiategrasso",
    M3: "Comasina ⇄ San Donato",
    M4: "San Cristoforo ⇄ Linate Aeroporto",
    M5: "Bignami ⇄ San Siro Stadio",
  };

  document.addEventListener("DOMContentLoaded", init);

  function init() {
    const params = new URLSearchParams(window.location.search);
    const simulationMode = params.has("simulation") || window.location.hash.includes("simulation");
    window.I18N.init(params.get("lang"));

    indexSurfaceStops();

    // ------------------------------------------------------------------ state
    const state = {
      view: "metro", // "metro" | "surface"
      dayType: U.dayTypeFor(U.milanClock()),
      panel: null, // { type: "line" | "station" | "vehicle", id }
      trackedTripId: null,
      highlightedLineId: null,
      surfaceLineId: null,
      surfaceFilter: "ALL",
      surfaceQuery: "",
      followTracked: false,
      vehicles: [],
      lastUiRefresh: 0,
    };

    const sounds = new UiSounds(U.storage.get("mts.sound", "on") === "on");
    const scheduler = new TransitScheduler(
      METRO_NETWORK,
      typeof METRO_OFFICIAL_FREQUENCIES !== "undefined" ? METRO_OFFICIAL_FREQUENCIES : null
    );
    let metroTrips = scheduler.generateMetroSchedule(state.dayType);
    const sim = new TransitSimulation(METRO_NETWORK, metroTrips);

    const map = new TransitMap("map", METRO_NETWORK, {
      onStationClick: (id) => selectStation(id, { focus: false }),
      onVehicleClick: (tripId) => trackVehicle(tripId),
      onBackgroundClick: () => closePanel(),
    });
    map.labels.vehicleTooltip = (v) => `${t(`mode.${v.mode}`)} ${v.lineId} · ${t("panel.to", { dest: v.to })}`;

    // ------------------------------------------------------------------ DOM
    const $ = (id) => document.getElementById(id);
    const el = {
      clock: $("digital-clock"),
      dayBadge: $("day-of-week"),
      ambient: $("ambient-overlay"),
      accent: $("app-title-accent"),
      realtimeToggle: $("realtime-toggle"),
      realtimeCheckbox: $("realtime-checkbox"),
      realtimeLabel: $("realtime-label"),
      manualControls: $("manual-controls"),
      playPause: $("btn-play-pause"),
      speed: $("select-speed"),
      dayType: $("select-day-type"),
      timeline: $("bottom-timeline-panel"),
      timelineRange: $("timeline-range"),
      sidebar: $("control-sidebar"),
      sidebarToggle: $("sidebar-toggle"),
      linesTitle: $("lines-panel-title"),
      linesDesc: $("lines-panel-desc"),
      surfaceFilters: $("surface-filters"),
      surfaceSearch: $("surface-line-search-input"),
      lines: $("lines-container"),
      statVehicles: $("stat-active-vehicles"),
      statTrips: $("stat-trips"),
      statStations: $("stat-stations"),
      statStationsLabel: $("stat-stations-label"),
      stationSearch: $("station-search-input"),
      autocomplete: $("search-autocomplete-results"),
      vehiclesCount: $("active-vehicles-count"),
      vehiclesList: $("active-vehicles-list"),
      panel: $("right-detail-panel"),
      panelContent: $("right-panel-content"),
      panelClose: $("btn-close-right-panel"),
      btnMetro: $("btn-page-metro"),
      btnSurface: $("btn-page-surface"),
      btnLanguage: $("btn-language"),
      btnSound: $("btn-sound"),
      btnTheme: $("btn-theme-toggle"),
    };

    /** Sets innerHTML only when it changed (avoids DOM churn on periodic refreshes). */
    function setHtml(node, html) {
      if (node && node.__html !== html) {
        node.innerHTML = html;
        node.__html = html;
      }
    }

    // ------------------------------------------------------------------ helpers
    const network = () => (state.view === "metro" ? METRO_NETWORK : SURFACE_NETWORK);
    const lineOf = (lineId) => network().lines[lineId];
    const colorOf = (lineId) => (lineOf(lineId) || {}).color || "#007AFF";
    const modeClass = (lineId) => (state.view === "surface" && lineOf(lineId) ? lineOf(lineId).type : "");
    const badge = (lineId, cls = "mini-circle-badge") =>
      `<span class="${cls} ${modeClass(lineId)}" style="--line-color:${colorOf(lineId)}">${esc(lineId)}</span>`;
    const minutesLabel = (seconds) =>
      seconds < 60 ? t("panel.lessThanMinute") : t("panel.minutes", { n: Math.round(seconds / 60) });
    const vehiclesLabel = (n) => t("vehicles.count", { n });

    function countForLine(lineId) {
      if (state.view === "metro") return state.vehicles.filter((v) => v.lineId === lineId).length;
      return scheduler.countActiveSurfaceVehicles(lineId, SURFACE_NETWORK, state.dayType, sim.simTime);
    }

    function currentHeadwayMinutes(lineId) {
      if (state.view === "metro") {
        const lv = scheduler.getMetroLevels(lineId, state.dayType);
        const first = U.parseHHMM(lv.first_departure);
        const last = U.parseHHMM(lv.last_arrival);
        if (sim.simTime < first || sim.simTime > last) return null;
        return Math.round(scheduler.getHeadway(lineId, sim.simTime, state.dayType) / 60);
      }
      const routes = Object.values(SURFACE_NETWORK.lines[lineId].percorsi);
      const running = routes
        .map((r) => r.frequencies[state.dayType])
        .filter((f) => f && sim.simTime >= U.parseHHMM(f.service_start) && sim.simTime <= U.parseHHMM(f.service_end));
      if (!running.length) return null;
      return Math.round(Math.min(...running.map((f) => scheduler.getSurfaceHeadway(sim.simTime, f))) / 60);
    }

    // ------------------------------------------------------------------ main loop
    function frame() {
      const rolledOver = sim.tick();
      if (sim.isRealTime && (rolledOver || U.dayTypeFor(U.milanClock()) !== state.dayType)) {
        setDayType(U.dayTypeFor(U.milanClock()));
      }
      state.vehicles = sim.getActiveVehicles();
      map.updateVehicles(state.vehicles, state.trackedTripId, (v) => colorOf(v.lineId));

      const now = performance.now();
      if (now - state.lastUiRefresh >= UI_REFRESH_MS) {
        state.lastUiRefresh = now;
        refreshUi();
      }
      requestAnimationFrame(frame);
    }

    function refreshUi() {
      el.clock.textContent = U.formatClock(sim.simTime);
      updateAmbient(sim.simTime);
      if (!sim.isRealTime) el.timelineRange.value = Math.round(sim.simTime);

      el.statVehicles.textContent = state.vehicles.length;
      el.vehiclesCount.textContent = state.vehicles.length;
      refreshLineCounts();
      renderVehicleList();
      refreshPanel();
    }

    function updateAmbient(serviceSeconds) {
      const h = (serviceSeconds % U.DAY) / 3600;
      const cls =
        h >= 5.5 && h < 8.5 ? "ambient-morning" : h >= 8.5 && h < 18.5 ? "ambient-day" : h >= 18.5 && h < 21.5 ? "ambient-evening" : "ambient-night";
      if (el.ambient.className !== cls) el.ambient.className = cls;
    }

    // ------------------------------------------------------------------ schedule / day type
    function setDayType(dayType) {
      state.dayType = dayType;
      el.dayBadge.textContent = t(`day.${dayType}`);
      el.dayType.value = dayType;
      metroTrips = scheduler.generateMetroSchedule(dayType);
      if (state.view === "metro") {
        sim.setTrips(METRO_NETWORK, metroTrips);
      } else if (state.surfaceLineId) {
        sim.setTrips(SURFACE_NETWORK, scheduler.generateSurfaceSchedule(state.surfaceLineId, SURFACE_NETWORK, dayType));
      }
      updateStats();
    }

    function updateStats() {
      if (state.view === "metro") {
        el.statTrips.textContent = metroTrips.length.toLocaleString();
        el.statStations.textContent = Object.keys(METRO_NETWORK.stations).length;
        el.statStationsLabel.dataset.i18n = "stats.stations";
      } else {
        el.statTrips.textContent = state.surfaceLineId ? sim.trips.length.toLocaleString() : "—";
        el.statStations.textContent = state.surfaceLineId
          ? new Set(Object.values(SURFACE_NETWORK.lines[state.surfaceLineId].percorsi).flatMap((r) => r.stops)).size
          : Object.keys(SURFACE_NETWORK.stations).length.toLocaleString();
        el.statStationsLabel.dataset.i18n = "stats.stops";
      }
      el.statStationsLabel.textContent = t(el.statStationsLabel.dataset.i18n);
    }

    // ------------------------------------------------------------------ lines list
    function renderLinesList() {
      if (state.view === "metro") {
        setHtml(
          el.lines,
          Object.values(METRO_NETWORK.lines)
            .map((line) => lineRowHtml(line.id, state.highlightedLineId === line.id, ""))
            .join("")
        );
        return;
      }
      const q = state.surfaceQuery;
      const lines = Object.values(SURFACE_NETWORK.lines)
        .filter((l) => (state.surfaceFilter === "ALL" || l.type === state.surfaceFilter) && (!q || l.id.toLowerCase().includes(q)))
        .sort((a, b) => {
          const na = parseInt(a.id, 10);
          const nb = parseInt(b.id, 10);
          return !isNaN(na) && !isNaN(nb) && na !== nb ? na - nb : a.id.localeCompare(b.id, undefined, { numeric: true });
        });
      setHtml(
        el.lines,
        lines.length
          ? lines.map((l) => lineRowHtml(l.id, state.surfaceLineId === l.id, `<span class="mini-type-badge">${esc(t(`filter.${l.type}`))}</span>`)).join("")
          : `<p class="placeholder-msg compact">${esc(t("lines.none"))}</p>`
      );
      refreshLineCounts();
    }

    function lineRowHtml(lineId, selected, extra) {
      const color = colorOf(lineId);
      return `
        <button type="button" class="line-item-row ${selected ? "selected" : ""}" data-line-id="${esc(lineId)}" style="--line-color:${color};--line-tint:${U.hexToRgba(color, 0.1)}">
          <span class="line-item-left">
            ${badge(lineId, "line-color-badge")}
            <span class="line-name">${esc(t("lines.name", { id: lineId }))} ${extra}</span>
          </span>
          <span class="line-item-right">
            <span class="train-count-badge" data-count-for="${esc(lineId)}"></span>
            <span class="status-badge" data-status-for="${esc(lineId)}"></span>
          </span>
        </button>`;
    }

    function refreshLineCounts() {
      el.lines.querySelectorAll("[data-count-for]").forEach((node) => {
        const lineId = node.dataset.countFor;
        const n = countForLine(lineId);
        const txt = vehiclesLabel(n);
        if (node.textContent !== txt) node.textContent = txt;
        const status = node.parentElement.querySelector("[data-status-for]");
        const statusTxt = n > 0 ? t("lines.inService") : t("lines.notRunning");
        if (status.textContent !== statusTxt) {
          status.textContent = statusTxt;
          status.classList.toggle("regular", n > 0);
          status.classList.toggle("inactive", n === 0);
        }
      });
    }

    el.lines.addEventListener("click", (e) => {
      const row = e.target.closest(".line-item-row");
      if (!row) return;
      sounds.click();
      const lineId = row.dataset.lineId;
      if (state.view === "metro") toggleMetroLine(lineId);
      else selectSurfaceLine(lineId);
    });

    function toggleMetroLine(lineId) {
      if (state.highlightedLineId === lineId) {
        state.highlightedLineId = null;
        map.highlightLine(null);
        closePanel();
      } else {
        state.highlightedLineId = lineId;
        map.highlightLine(lineId);
        openPanel({ type: "line", id: lineId });
      }
      renderLinesList();
    }

    function selectSurfaceLine(lineId) {
      if (state.surfaceLineId === lineId) {
        state.surfaceLineId = null;
        map.clearSurface();
        map.clearVehicles();
        sim.setTrips(SURFACE_NETWORK, []);
        closePanel();
      } else {
        state.surfaceLineId = lineId;
        map.clearVehicles();
        map.drawSurfaceLine(SURFACE_NETWORK.lines[lineId], SURFACE_NETWORK);
        sim.setTrips(SURFACE_NETWORK, scheduler.generateSurfaceSchedule(lineId, SURFACE_NETWORK, state.dayType));
        openPanel({ type: "line", id: lineId });
      }
      updateStats();
      renderLinesList();
    }

    // ------------------------------------------------------------------ right panel
    function openPanel(panel, { silent = false } = {}) {
      if (panel.type === "vehicle" && state.highlightedLineId) {
        state.highlightedLineId = null;
        map.highlightLine(null);
        renderLinesList();
      }
      state.panel = panel;
      state.trackedTripId = panel.type === "vehicle" ? panel.id : null;
      map.setSelectedStation(panel.type === "station" ? panel.id : null);
      el.panel.classList.remove("collapsed");
      document.body.classList.add("detail-open");
      if (window.matchMedia("(max-width: 600px)").matches) setSidebar(false);
      if (!silent) sounds.chime();
      renderPanel();
    }

    function closePanel() {
      if (!state.panel) return;
      if (state.panel.type === "line" && state.view === "metro") {
        state.highlightedLineId = null;
        map.highlightLine(null);
        renderLinesList();
      }
      state.panel = null;
      state.trackedTripId = null;
      map.setSelectedStation(null);
      el.panel.classList.add("collapsed");
      document.body.classList.remove("detail-open");
      sounds.deselect();
    }

    el.panelClose.addEventListener("click", closePanel);

    /** Builds the static skeleton of the panel; live values are filled by refreshPanel(). */
    function renderPanel() {
      const p = state.panel;
      if (!p) return;
      if (p.type === "line") renderLinePanel(p.id);
      else if (p.type === "station") renderStationPanel(p.id);
      else renderVehiclePanel(p.id);
      el.panelContent.__html = null;
      el.panel.scrollTop = 0;
      refreshPanel();
    }

    function renderLinePanel(lineId) {
      const line = lineOf(lineId);
      if (!line) return closePanel();
      const isMetro = state.view === "metro";
      const stops = isMetro
        ? [...new Set(Object.values(line.paths).flat())]
        : [...new Set(Object.values(line.percorsi).flatMap((r) => r.stops))];
      let route = METRO_TERMINI[lineId] || "";
      if (!isMetro) {
        const r = Object.values(line.percorsi)[0];
        const name = (id) => ((SURFACE_NETWORK.stations[id] || {}).name || "").split(",")[0];
        route = r ? `${name(r.stops[0])} ⇄ ${name(r.stops[r.stops.length - 1])}` : "";
      }
      el.panelContent.innerHTML = `
        <div class="panel-header">
          ${badge(lineId, "mini-circle-badge large")}
          <h3>${esc(t("lines.name", { id: lineId }))}${isMetro ? "" : ` <small>${esc(t(`filter.${line.type}`))}</small>`}</h3>
        </div>
        <div class="data-grid">
          <div class="data-box"><span class="data-lbl">${esc(t("panel.running"))}</span><span class="data-val" data-live="line-count"></span></div>
          <div class="data-box"><span class="data-lbl">${esc(t("panel.frequency"))}</span><span class="data-val" data-live="line-frequency"></span></div>
        </div>
        <div class="data-box wide"><span class="data-lbl">${esc(t("panel.termini"))}</span><span class="data-val">${esc(route)}</span></div>
        <h4 class="board-title">${esc(t(isMetro ? "panel.stationsList" : "panel.stopsList"))}</h4>
        <div class="stop-list">
          ${stops
            .map((id) => network().stations[id])
            .filter(Boolean)
            .map(
              (s) => `<button type="button" class="timetable-row station-row-item" data-station-id="${esc(s.id)}">
                  <span class="station-name-text">${esc(s.name)}</span><span class="row-cta">${esc(t("panel.show"))} ❯</span>
                </button>`
            )
            .join("")}
        </div>`;
    }

    function renderStationPanel(stationId) {
      const s = network().stations[stationId];
      if (!s) return closePanel();
      el.panelContent.innerHTML = `
        <div class="panel-header"><h3>${esc(s.name)}</h3></div>
        <div class="station-badge-row">${(s.lines || []).map((l) => badge(l, "mini-line-badge")).join("")}</div>
        <h4 class="board-title">${esc(t("panel.departures"))}</h4>
        <div class="timetable-grid" data-live="departures"></div>`;
    }

    function renderVehiclePanel(tripId) {
      const trip = sim.trips.find((x) => x.tripId === tripId);
      if (!trip) return closePanel();
      el.panelContent.innerHTML = `
        <div class="panel-header">
          ${badge(trip.lineId, "mini-circle-badge large")}
          <h3>${esc(t("panel.vehicleTo", { mode: t(`mode.${trip.mode}`), dest: trip.to }))}</h3>
        </div>
        <div class="data-grid">
          <div class="data-box"><span class="data-lbl">${esc(t("panel.speed"))}</span><span class="data-val" data-live="speed"></span></div>
          <div class="data-box"><span class="data-lbl">${esc(t("panel.terminusArrival"))}</span><span class="data-val">${U.formatClock(trip.endTime, false)}</span></div>
        </div>
        <div data-live="progress"></div>
        <h4 class="board-title spaced">${esc(t("panel.upcoming"))}</h4>
        <div class="timetable-grid" data-live="upcoming"></div>`;
    }

    /** Pixels of map covered by floating panels, so focusing keeps targets visible. */
    function coveredArea() {
      const header = document.getElementById("main-header");
      const pad = { left: 0, right: 0, top: header.offsetTop + header.offsetHeight, bottom: 0 };
      if (!el.sidebar.classList.contains("collapsed") && el.sidebar.offsetWidth < window.innerWidth * 0.6) {
        pad.left = el.sidebar.offsetLeft + el.sidebar.offsetWidth;
      }
      if (state.panel) {
        if (el.panel.offsetWidth < window.innerWidth * 0.6) pad.right = window.innerWidth - el.panel.offsetLeft;
        else pad.bottom = window.innerHeight - el.panel.offsetTop;
      }
      return pad;
    }

    /** Updates the live parts of the panel (called 4×/s). */
    function refreshPanel() {
      const p = state.panel;
      if (!p) return;
      const live = (name) => el.panelContent.querySelector(`[data-live="${name}"]`);

      if (p.type === "line") {
        const n = countForLine(p.id);
        const count = live("line-count");
        if (count) count.textContent = vehiclesLabel(n);
        const freq = live("line-frequency");
        const hw = currentHeadwayMinutes(p.id);
        if (freq) freq.textContent = hw === null ? t("panel.noService") : t("panel.every", { n: Math.max(1, hw) });
      } else if (p.type === "station") {
        renderDepartures(p.id, live("departures"));
      } else {
        const v = state.vehicles.find((x) => x.tripId === p.id);
        if (!v) return closePanel();
        live("speed").textContent = v.status === "STOPPED" ? t("vehicles.stopped") : `${v.speed} km/h`;
        const progress =
          v.status === "MOVING"
            ? `<div class="route-progress">
                 <div class="progress-labels"><span>${esc(v.currentStationName)}</span><span>${esc(v.nextStationName)}</span></div>
                 <div class="progress-track"><div class="progress-fill" style="width:${Math.round(v.segmentProgress * 100)}%;--line-color:${colorOf(v.lineId)}"></div></div>
                 <div class="progress-eta">${esc(t("panel.nextStop", { time: minutesLabel(v.secondsToNext) }))}</div>
               </div>`
            : `<p class="stopped-msg">${esc(t("panel.stoppedAt", { station: v.currentStationName }))}</p>`;
        setHtml(live("progress"), progress);

        const trip = sim.trips.find((x) => x.tripId === p.id);
        const nextIndex = trip ? trip.stationIds.indexOf(v.nextStationId || v.currentStationId) : -1;
        const upcoming = nextIndex >= 0 ? trip.stopTimes.slice(nextIndex, nextIndex + 8) : [];
        setHtml(
          live("upcoming"),
          upcoming
            .map((st) => {
              const s = network().stations[st.stationId];
              return `<div class="timetable-row compact"><span class="station-name-text">${esc(s ? s.name : st.stationId)}</span>
                <span class="eta-clock large">${U.formatClock(st.arrivalTime, false)}</span></div>`;
            })
            .join("")
        );

        const pad = coveredArea();
        if (state.followTracked) {
          map.focusOn(v.lat, v.lon, 14, pad);
          state.followTracked = false;
        } else if (!map.isVisible(v.lat, v.lon, pad)) {
          map.focusOn(v.lat, v.lon, map.map.getZoom(), pad);
        }
      }
    }

    function renderDepartures(stationId, container) {
      if (!container) return;
      let departures;
      if (state.view === "metro") {
        departures = sim.getStationDepartures(stationId, { trips: metroTrips });
      } else {
        const stop = SURFACE_NETWORK.stations[stationId];
        const trips = (stop.lines || []).flatMap((l) => scheduler.generateSurfaceSchedule(l, SURFACE_NETWORK, state.dayType));
        departures = sim.getStationDepartures(stationId, { trips, perGroup: 2 });
      }
      setHtml(
        container,
        departures.length
          ? departures
              .slice(0, 16)
              .map((d) => {
                const status = d.atPlatform ? t("panel.atPlatform") : d.waitSeconds < 60 ? t("panel.arriving") : t("panel.minutes", { n: Math.round(d.waitSeconds / 60) });
                return `<div class="timetable-row">
                    <div class="timetable-left">${badge(d.lineId)}<span class="timetable-dest">${esc(t("panel.to", { dest: d.destination }))}</span></div>
                    <div class="timetable-right"><span class="eta-badge ${d.atPlatform ? "in-banchina" : ""}">${esc(status)}</span>
                    <span class="eta-clock">${esc(t("panel.arrivalAt", { time: U.formatClock(d.arrivalTime, false) }))}</span></div>
                  </div>`;
              })
              .join("")
          : `<p class="placeholder-msg compact">${esc(t("panel.noDepartures"))}</p>`
      );
    }

    el.panelContent.addEventListener("click", (e) => {
      const row = e.target.closest(".station-row-item");
      if (row) selectStation(row.dataset.stationId, { focus: true });
    });

    // ------------------------------------------------------------------ stations & vehicles
    function selectStation(stationId, { focus }) {
      const s = network().stations[stationId];
      if (!s) return;
      openPanel({ type: "station", id: stationId });
      if (focus) map.focusOn(s.lat, s.lon, 15, coveredArea());
    }

    function trackVehicle(tripId) {
      state.followTracked = true;
      openPanel({ type: "vehicle", id: tripId });
    }

    function renderVehicleList() {
      if (state.view === "surface" && !state.surfaceLineId) {
        setHtml(el.vehiclesList, `<p class="placeholder-msg compact">${esc(t("vehicles.selectLine"))}</p>`);
        return;
      }
      if (!state.vehicles.length) {
        setHtml(el.vehiclesList, `<p class="placeholder-msg compact">${esc(t("vehicles.none"))}</p>`);
        return;
      }
      // Only rebuild while the tab is visible; the count in the header is always updated.
      if (!document.getElementById("tab-vehicles").classList.contains("active")) return;
      const sorted = state.vehicles.slice().sort((a, b) => a.lineId.localeCompare(b.lineId, undefined, { numeric: true }) || a.to.localeCompare(b.to));
      setHtml(
        el.vehiclesList,
        sorted
          .map((v) => {
            const eta = v.status === "STOPPED" ? t("vehicles.atStop") : minutesLabel(v.secondsToNext);
            return `<button type="button" class="train-item-row ${v.tripId === state.trackedTripId ? "tracked" : ""}" data-trip-id="${esc(v.tripId)}">
                <span class="train-item-left">${badge(v.lineId)}
                  <span><span class="train-item-dest">${esc(t("panel.to", { dest: v.to }))}</span>
                  <span class="train-item-status">${esc(v.currentStationName)} → ${esc(v.nextStationName || "—")}</span></span>
                </span>
                <span class="train-item-eta">${esc(eta)}</span>
              </button>`;
          })
          .join("")
      );
    }

    el.vehiclesList.addEventListener("click", (e) => {
      const row = e.target.closest(".train-item-row");
      if (row) {
        sounds.click();
        trackVehicle(row.dataset.tripId);
      }
    });

    // ------------------------------------------------------------------ station search
    const normalize = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    let searchResults = [];

    el.stationSearch.addEventListener("input", () => {
      const q = normalize(el.stationSearch.value.trim());
      if (q.length < 2) return hideAutocomplete();
      searchResults = Object.values(network().stations)
        .filter((s) => normalize(s.name).includes(q))
        .sort((a, b) => normalize(a.name).indexOf(q) - normalize(b.name).indexOf(q) || a.name.localeCompare(b.name))
        .slice(0, 8);
      el.autocomplete.innerHTML = searchResults.length
        ? searchResults
            .map(
              (s, i) => `<div class="autocomplete-item" role="option" data-index="${i}">
                <span>${esc(s.name)}</span><span class="autocomplete-lines">${(s.lines || []).slice(0, 6).map((l) => badge(l, "mini-line-badge")).join("")}</span></div>`
            )
            .join("")
        : `<div class="autocomplete-empty">${esc(t("stations.noResults"))}</div>`;
      el.autocomplete.classList.remove("hidden");
      el.stationSearch.setAttribute("aria-expanded", "true");
    });

    el.stationSearch.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && searchResults.length) pickSearchResult(0);
      if (e.key === "Escape") hideAutocomplete();
    });

    el.autocomplete.addEventListener("click", (e) => {
      const item = e.target.closest(".autocomplete-item");
      if (item) pickSearchResult(Number(item.dataset.index));
    });

    function pickSearchResult(index) {
      const s = searchResults[index];
      if (!s) return;
      if (state.view === "surface" && s.lines && s.lines.length && !s.lines.includes(state.surfaceLineId)) {
        selectSurfaceLine(s.lines[0]);
      }
      selectStation(s.id, { focus: true });
      el.stationSearch.value = "";
      hideAutocomplete();
    }

    function hideAutocomplete() {
      el.autocomplete.classList.add("hidden");
      el.stationSearch.setAttribute("aria-expanded", "false");
      searchResults = [];
    }

    document.addEventListener("click", (e) => {
      if (!el.stationSearch.contains(e.target) && !el.autocomplete.contains(e.target)) hideAutocomplete();
    });

    // ------------------------------------------------------------------ view switch
    function switchView(view) {
      if (state.view === view) return;
      closePanel();
      state.view = view;
      state.highlightedLineId = null;
      state.surfaceLineId = null;
      map.highlightLine(null);
      map.clearSurface();
      map.clearVehicles();

      const metro = view === "metro";
      el.btnMetro.classList.toggle("active", metro);
      el.btnSurface.classList.toggle("active", !metro);
      el.btnMetro.setAttribute("aria-selected", String(metro));
      el.btnSurface.setAttribute("aria-selected", String(!metro));
      el.surfaceFilters.classList.toggle("hidden", metro);
      el.surfaceSearch.value = "";
      state.surfaceQuery = "";
      el.linesTitle.dataset.i18n = metro ? "lines.metroTitle" : "lines.surfaceTitle";
      el.linesDesc.dataset.i18n = metro ? "lines.metroDesc" : "lines.surfaceDesc";
      el.accent.dataset.i18n = metro ? "header.accent.metro" : "header.accent.surface";
      el.stationSearch.dataset.i18nPlaceholder = metro ? "stations.searchMetro" : "stations.searchSurface";
      el.stationSearch.dataset.i18nAriaLabel = el.stationSearch.dataset.i18nPlaceholder;
      window.I18N.apply(document.getElementById("main-header"));
      window.I18N.apply(el.sidebar);

      map.showMetro(metro);
      sim.setTrips(metro ? METRO_NETWORK : SURFACE_NETWORK, metro ? metroTrips : []);
      updateStats();
      renderLinesList();
    }

    el.btnMetro.addEventListener("click", () => {
      sounds.click();
      switchView("metro");
    });
    el.btnSurface.addEventListener("click", () => {
      sounds.click();
      switchView("surface");
    });

    document.querySelectorAll(".filter-pill").forEach((btn) =>
      btn.addEventListener("click", () => {
        sounds.click();
        document.querySelectorAll(".filter-pill").forEach((p) => p.classList.toggle("active", p === btn));
        state.surfaceFilter = btn.dataset.filter;
        renderLinesList();
      })
    );
    el.surfaceSearch.addEventListener("input", () => {
      state.surfaceQuery = el.surfaceSearch.value.toLowerCase().trim();
      renderLinesList();
    });

    // ------------------------------------------------------------------ sidebar & tabs
    function setSidebar(open) {
      el.sidebar.classList.toggle("collapsed", !open);
      el.sidebarToggle.setAttribute("aria-expanded", String(open));
    }
    el.sidebarToggle.addEventListener("click", () => setSidebar(el.sidebar.classList.contains("collapsed")));
    if (window.matchMedia("(min-width: 769px)").matches) setTimeout(() => setSidebar(true), 600);

    const tabs = document.querySelectorAll(".tab-trigger");
    tabs.forEach((tab) =>
      tab.addEventListener("click", () => {
        sounds.click();
        tabs.forEach((x) => {
          x.classList.toggle("active", x === tab);
          x.setAttribute("aria-selected", String(x === tab));
        });
        document.querySelectorAll(".tab-panel").forEach((p) => p.classList.toggle("active", p.id === tab.dataset.tab));
        el.vehiclesList.__html = null;
        renderVehicleList();
      })
    );

    // ------------------------------------------------------------------ time controls
    function syncTimeControls() {
      el.realtimeCheckbox.checked = sim.isRealTime;
      el.realtimeLabel.classList.toggle("active", sim.isRealTime);
      el.manualControls.classList.toggle("hidden", sim.isRealTime);
      el.timeline.classList.toggle("hidden", sim.isRealTime);
      document.body.classList.toggle("timeline-open", !sim.isRealTime);
      el.timelineRange.value = Math.round(sim.simTime);
      el.playPause.querySelector(".icon-play").classList.toggle("hidden", sim.isPlaying);
      el.playPause.querySelector(".icon-pause").classList.toggle("hidden", !sim.isPlaying);
    }

    if (simulationMode) el.realtimeToggle.classList.remove("hidden");

    el.realtimeCheckbox.addEventListener("change", () => {
      sounds.click();
      sim.setRealTimeMode(el.realtimeCheckbox.checked);
      if (sim.isRealTime) setDayType(U.dayTypeFor(U.milanClock()));
      syncTimeControls();
    });
    el.playPause.addEventListener("click", () => {
      sounds.click();
      sim.setPlaying(!sim.isPlaying);
      syncTimeControls();
    });
    el.speed.addEventListener("change", () => {
      sounds.click();
      sim.setSpeed(parseFloat(el.speed.value));
    });
    el.dayType.addEventListener("change", () => {
      sounds.click();
      setDayType(el.dayType.value);
      renderPanel();
    });
    el.timelineRange.addEventListener("input", () => {
      sim.setTime(parseInt(el.timelineRange.value, 10));
      syncTimeControls();
    });
    document.querySelectorAll(".preset-btn").forEach((btn) =>
      btn.addEventListener("click", () => {
        sounds.click();
        sim.setTime(parseInt(btn.dataset.time, 10));
        syncTimeControls();
      })
    );

    // ------------------------------------------------------------------ header actions
    function applyTheme(theme) {
      document.body.classList.toggle("light-theme", theme === "light");
      el.btnTheme.textContent = theme === "light" ? "🌙" : "☀️";
      document.querySelector('meta[name="theme-color"]').content = theme === "light" ? "#f0f2f5" : "#07080b";
      map.setTheme(theme);
    }
    el.btnTheme.addEventListener("click", () => {
      sounds.click();
      const theme = document.body.classList.contains("light-theme") ? "dark" : "light";
      U.storage.set("mts.theme", theme);
      applyTheme(theme);
    });

    function syncSoundButton() {
      el.btnSound.textContent = sounds.enabled ? "🔊" : "🔇";
      el.btnSound.setAttribute("aria-pressed", String(sounds.enabled));
      const key = sounds.enabled ? "header.soundOn" : "header.soundOff";
      el.btnSound.title = t(key);
      el.btnSound.setAttribute("aria-label", t(key));
    }
    el.btnSound.addEventListener("click", () => {
      sounds.enabled = !sounds.enabled;
      U.storage.set("mts.sound", sounds.enabled ? "on" : "off");
      syncSoundButton();
      sounds.click();
    });

    function syncLanguageButton() {
      el.btnLanguage.textContent = window.I18N.getLanguage() === "it" ? "EN" : "IT";
    }
    el.btnLanguage.addEventListener("click", () => {
      sounds.click();
      window.I18N.setLanguage(window.I18N.getLanguage() === "it" ? "en" : "it");
    });
    window.I18N.onChange(() => {
      syncLanguageButton();
      syncSoundButton();
      el.dayBadge.textContent = t(`day.${state.dayType}`);
      updateStats();
      el.lines.__html = null;
      renderLinesList();
      el.vehiclesList.__html = null;
      renderPanel();
      refreshUi();
    });

    // ------------------------------------------------------------------ boot
    applyTheme(U.storage.get("mts.theme", "dark"));
    syncLanguageButton();
    syncSoundButton();
    setDayType(state.dayType);
    syncTimeControls();
    renderLinesList();
    refreshUi();
    requestAnimationFrame(frame);

    // Exposed for debugging from the browser console.
    window.mts = { state, sim, scheduler, map };
  }

  /** Adds `lines` (ids of the lines serving it) to every surface stop. */
  function indexSurfaceStops() {
    if (typeof SURFACE_NETWORK === "undefined") return;
    for (const stop of Object.values(SURFACE_NETWORK.stations)) stop.lines = [];
    for (const line of Object.values(SURFACE_NETWORK.lines)) {
      for (const route of Object.values(line.percorsi)) {
        for (const id of route.stops) {
          const stop = SURFACE_NETWORK.stations[id];
          if (stop && !stop.lines.includes(line.id)) stop.lines.push(line.id);
        }
      }
    }
    for (const stop of Object.values(SURFACE_NETWORK.stations)) {
      stop.lines.sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
    }
  }
})();
