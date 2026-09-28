// Minimal internationalisation layer (Italian / English).
//
// * Static markup uses data attributes:  data-i18n (text), data-i18n-placeholder,
//   data-i18n-title, data-i18n-aria-label.
// * Scripts call I18N.t("key", { param }) — values can be plural objects {one, other}.

(function (root) {
  "use strict";

  const DICTIONARIES = {
    it: {
      "meta.title": "Milano Transit Simulator – Metro e superficie in simulazione",
      "header.accent.metro": "Metro",
      "header.accent.surface": "Superficie",
      "header.view.metro": "METRO",
      "header.view.surface": "SUPERFICIE",
      "header.view.metroTitle": "Rete metropolitana",
      "header.view.surfaceTitle": "Tram, filobus e bus",
      "header.realtime": "Tempo reale",
      "header.playPause": "Riproduci / Pausa",
      "header.speed": "Velocità di simulazione",
      "header.dayType": "Tipo di giorno",
      "header.language": "Switch to English",
      "settings.open": "Apri le opzioni",
      "settings.title": "Opzioni",
      "settings.theme": "Stile grafico",
      "settings.language": "Lingua",
      "settings.sound": "Suoni dell'interfaccia",
      "settings.about":
        "Mappa di base OpenFreeMap (dati OpenStreetMap). Orari simulati a partire dagli Open Data del Comune di Milano. Codice sorgente su GitHub: DeveloperMatt02/milano-transit-simulator.",
      "theme.auto": "Automatico",
      "theme.autoDesc": "Noorda chiaro o scuro come il dispositivo",
      "theme.noordaLight": "Noorda chiaro",
      "theme.noordaLightDesc": "Segnaletica milanese del 1964: fascia rossa e linee piene",
      "theme.noordaDark": "Noorda scuro",
      "theme.noordaDarkDesc": "Lo stesso linguaggio, per la sera",
      "theme.fiord": "Fiord",
      "theme.fiordDesc": "Sala di controllo: blu ardesia e dati in monospazio",
      "header.simulated": "SIMULATO",

      "day.L": "FERIALE",
      "day.S": "SABATO",
      "day.F": "FESTIVO",

      "sidebar.toggle": "Mostra / nascondi pannello",
      "tabs.lines": "LINEE",
      "tabs.stations": "STAZIONI",
      "tabs.vehicles": "MEZZI",
      "tabs.settings": "OPZIONI",
      "tabs.nav": "Sezioni",
      "tabs.linesShort": "Linee",
      "tabs.stationsShort": "Stazioni",
      "tabs.vehiclesShort": "Mezzi",
      "tabs.settingsShort": "Opzioni",

      "lines.metroTitle": "Rete metropolitana",
      "lines.metroDesc": "Seleziona una linea per evidenziarne il percorso e vederne frequenza e stazioni.",
      "lines.surfaceTitle": "Linee di superficie",
      "lines.surfaceDesc": "Seleziona una linea per disegnarne il percorso e simularne i mezzi.",
      "lines.searchPlaceholder": "Cerca linea (es. 90, 15…)",
      "lines.none": "Nessuna linea trovata.",
      "lines.name": "Linea {id}",
      "lines.inService": "IN SERVIZIO",
      "lines.notRunning": "NON ATTIVA",

      "filter.ALL": "Tutti",
      "filter.TRAM": "Tram",
      "filter.FILOBUS": "Filobus",
      "filter.BUS": "Bus",
      "mode.METRO": "Treno",
      "mode.TRAM": "Tram",
      "mode.FILOBUS": "Filobus",
      "mode.BUS": "Bus",

      "stats.title": "Statistiche di rete",
      "stats.running": "Mezzi in viaggio",
      "stats.tripsToday": "Corse programmate",
      "stats.stations": "Stazioni",
      "stats.stops": "Fermate",
      "disclaimer":
        "Simulazione costruita sui livelli di servizio pubblicati negli Open Data del Comune di Milano: posizioni e orari sono stimati, non in tempo reale. Progetto indipendente, non affiliato ad ATM S.p.A.",

      "stations.title": "Stazioni e partenze",
      "stations.searchMetro": "Cerca stazione (es. Duomo, Centrale…)",
      "stations.searchSurface": "Cerca fermata (es. Cadorna, Loreto…)",
      "stations.placeholder": "Cerca una stazione o cliccala sulla mappa: il tabellone delle prossime partenze si apre nel pannello dei dettagli.",
      "stations.noResults": "Nessun risultato",

      "vehicles.title": "Mezzi in circolazione",
      "vehicles.active": "Mezzi attivi",
      "vehicles.none": "Nessun mezzo in servizio in questo momento.",
      "vehicles.selectLine": "Seleziona una linea di superficie per vederne i mezzi.",
      "vehicles.count": { one: "{n} mezzo", other: "{n} mezzi" },
      "vehicles.atStop": "In fermata",
      "vehicles.stopped": "Fermo",

      "panel.close": "Chiudi",
      "panel.running": "MEZZI IN VIAGGIO",
      "panel.frequency": "FREQUENZA ATTUALE",
      "panel.every": "ogni ~{n} min",
      "panel.noService": "nessun servizio",
      "panel.termini": "CAPOLINEA",
      "panel.stationsList": "STAZIONI",
      "panel.stopsList": "FERMATE",
      "panel.show": "Mostra",
      "panel.departures": "PROSSIME PARTENZE (SIMULATE)",
      "panel.noDepartures": "Nessuna partenza nelle prossime 2 ore.",
      "panel.to": "per {dest}",
      "panel.atPlatform": "In banchina",
      "panel.arriving": "In arrivo",
      "panel.minutes": "{n} min",
      "panel.arrivalAt": "arr. {time}",
      "panel.vehicleTo": "{mode} per {dest}",
      "panel.speed": "VELOCITÀ MEDIA TRATTA",
      "panel.terminusArrival": "ARRIVO AL CAPOLINEA",
      "panel.nextStop": "Prossima fermata tra {time}",
      "panel.stoppedAt": "Fermo a {station}",
      "panel.lessThanMinute": "< 1 min",
      "panel.upcoming": "PROSSIME FERMATE",

      "timeline.label": "Timeline della simulazione",
      "timeline.presets": "Scenari:",
      "timeline.morning": "🌅 Punta mattina (07:30)",
      "timeline.afternoon": "☀️ Pomeriggio (14:00)",
      "timeline.evening": "🌇 Punta sera (18:00)",
      "timeline.night": "🌌 Sera (23:00)",
      "timeline.afterMidnight": "🌙 Dopo mezzanotte (00:30)",
    },

    en: {
      "meta.title": "Milano Transit Simulator – Simulated metro and surface network",
      "header.accent.metro": "Metro",
      "header.accent.surface": "Surface",
      "header.view.metro": "METRO",
      "header.view.surface": "SURFACE",
      "header.view.metroTitle": "Metro network",
      "header.view.surfaceTitle": "Trams, trolleybuses and buses",
      "header.realtime": "Real time",
      "header.playPause": "Play / Pause",
      "header.speed": "Simulation speed",
      "header.dayType": "Day type",
      "header.language": "Passa all'italiano",
      "settings.open": "Open settings",
      "settings.title": "Settings",
      "settings.theme": "Visual style",
      "settings.language": "Language",
      "settings.sound": "Interface sounds",
      "settings.about":
        "Base map by OpenFreeMap (OpenStreetMap data). Timetables simulated from the City of Milan open data. Source code on GitHub: DeveloperMatt02/milano-transit-simulator.",
      "theme.auto": "Automatic",
      "theme.autoDesc": "Noorda light or dark, following your device",
      "theme.noordaLight": "Noorda light",
      "theme.noordaLightDesc": "Milan's 1964 metro signage: red band and solid lines",
      "theme.noordaDark": "Noorda dark",
      "theme.noordaDarkDesc": "The same language, for the evening",
      "theme.fiord": "Fiord",
      "theme.fiordDesc": "Control room: slate blue and monospaced data",
      "header.simulated": "SIMULATED",

      "day.L": "WEEKDAY",
      "day.S": "SATURDAY",
      "day.F": "HOLIDAY",

      "sidebar.toggle": "Show / hide panel",
      "tabs.lines": "LINES",
      "tabs.stations": "STATIONS",
      "tabs.vehicles": "VEHICLES",
      "tabs.settings": "SETTINGS",
      "tabs.nav": "Sections",
      "tabs.linesShort": "Lines",
      "tabs.stationsShort": "Stations",
      "tabs.vehiclesShort": "Vehicles",
      "tabs.settingsShort": "Settings",

      "lines.metroTitle": "Metro network",
      "lines.metroDesc": "Select a line to highlight its route and see its frequency and stations.",
      "lines.surfaceTitle": "Surface lines",
      "lines.surfaceDesc": "Select a line to draw its route and simulate its vehicles.",
      "lines.searchPlaceholder": "Search line (e.g. 90, 15…)",
      "lines.none": "No lines found.",
      "lines.name": "Line {id}",
      "lines.inService": "IN SERVICE",
      "lines.notRunning": "NOT RUNNING",

      "filter.ALL": "All",
      "filter.TRAM": "Tram",
      "filter.FILOBUS": "Trolleybus",
      "filter.BUS": "Bus",
      "mode.METRO": "Train",
      "mode.TRAM": "Tram",
      "mode.FILOBUS": "Trolleybus",
      "mode.BUS": "Bus",

      "stats.title": "Network statistics",
      "stats.running": "Vehicles running",
      "stats.tripsToday": "Scheduled trips",
      "stats.stations": "Stations",
      "stats.stops": "Stops",
      "disclaimer":
        "Simulation built on the service levels published in the City of Milan open data: positions and times are estimated, not live. Independent project, not affiliated with ATM S.p.A.",

      "stations.title": "Stations & departures",
      "stations.searchMetro": "Search station (e.g. Duomo, Centrale…)",
      "stations.searchSurface": "Search stop (e.g. Cadorna, Loreto…)",
      "stations.placeholder": "Search for a station or click it on the map: the departure board opens in the details panel.",
      "stations.noResults": "No results",

      "vehicles.title": "Vehicles on the network",
      "vehicles.active": "Active vehicles",
      "vehicles.none": "No vehicles in service right now.",
      "vehicles.selectLine": "Select a surface line to see its vehicles.",
      "vehicles.count": { one: "{n} vehicle", other: "{n} vehicles" },
      "vehicles.atStop": "At stop",
      "vehicles.stopped": "Stopped",

      "panel.close": "Close",
      "panel.running": "VEHICLES RUNNING",
      "panel.frequency": "CURRENT FREQUENCY",
      "panel.every": "every ~{n} min",
      "panel.noService": "no service",
      "panel.termini": "TERMINI",
      "panel.stationsList": "STATIONS",
      "panel.stopsList": "STOPS",
      "panel.show": "Show",
      "panel.departures": "NEXT DEPARTURES (SIMULATED)",
      "panel.noDepartures": "No departures in the next 2 hours.",
      "panel.to": "to {dest}",
      "panel.atPlatform": "At platform",
      "panel.arriving": "Arriving",
      "panel.minutes": "{n} min",
      "panel.arrivalAt": "arr. {time}",
      "panel.vehicleTo": "{mode} to {dest}",
      "panel.speed": "SEGMENT AVG SPEED",
      "panel.terminusArrival": "TERMINUS ARRIVAL",
      "panel.nextStop": "Next stop in {time}",
      "panel.stoppedAt": "Stopped at {station}",
      "panel.lessThanMinute": "< 1 min",
      "panel.upcoming": "UPCOMING STOPS",

      "timeline.label": "Simulation timeline",
      "timeline.presets": "Scenarios:",
      "timeline.morning": "🌅 Morning rush (07:30)",
      "timeline.afternoon": "☀️ Afternoon (14:00)",
      "timeline.evening": "🌇 Evening rush (18:00)",
      "timeline.night": "🌌 Evening (23:00)",
      "timeline.afterMidnight": "🌙 After midnight (00:30)",
    },
  };

  const SUPPORTED = Object.keys(DICTIONARIES);
  const STORAGE_KEY = "mts.lang";
  let current = "it";
  const listeners = [];

  function readStored() {
    try {
      return root.localStorage ? root.localStorage.getItem(STORAGE_KEY) : null;
    } catch (e) {
      return null;
    }
  }

  function detect(explicit) {
    const candidates = [explicit, readStored(), root.navigator && root.navigator.language];
    for (const c of candidates) {
      const lang = (c || "").slice(0, 2).toLowerCase();
      if (SUPPORTED.includes(lang)) return lang;
    }
    return "en";
  }

  function t(key, params = {}) {
    let value = DICTIONARIES[current][key];
    if (value === undefined) value = DICTIONARIES.it[key];
    if (value === undefined) return key;
    if (typeof value === "object") value = params.n === 1 ? value.one : value.other;
    return value.replace(/\{(\w+)\}/g, (_, name) => (params[name] !== undefined ? params[name] : `{${name}}`));
  }

  function apply(scope = root.document) {
    if (!scope) return;
    scope.querySelectorAll("[data-i18n]").forEach((el) => (el.textContent = t(el.dataset.i18n)));
    scope.querySelectorAll("[data-i18n-placeholder]").forEach((el) => (el.placeholder = t(el.dataset.i18nPlaceholder)));
    scope.querySelectorAll("[data-i18n-title]").forEach((el) => (el.title = t(el.dataset.i18nTitle)));
    scope.querySelectorAll("[data-i18n-aria-label]").forEach((el) => el.setAttribute("aria-label", t(el.dataset.i18nAriaLabel)));
    if (root.document) {
      root.document.documentElement.lang = current;
      root.document.title = t("meta.title");
    }
  }

  function setLanguage(lang) {
    if (!SUPPORTED.includes(lang)) return;
    current = lang;
    try {
      if (root.localStorage) root.localStorage.setItem(STORAGE_KEY, lang);
    } catch (e) {
      /* storage unavailable */
    }
    apply();
    listeners.forEach((fn) => fn(lang));
  }

  const I18N = {
    DICTIONARIES,
    SUPPORTED,
    t,
    apply,
    init(explicit) {
      current = detect(explicit);
      apply();
      return current;
    },
    setLanguage,
    getLanguage: () => current,
    onChange: (fn) => listeners.push(fn),
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = I18N;
  } else {
    root.I18N = I18N;
  }
})(typeof window !== "undefined" ? window : globalThis);
