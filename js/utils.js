// Shared helpers: geography, service-day time handling, calendar and HTML escaping.
//
// Time convention used across the app: a *service day* runs from 03:00 to 03:00 of the
// next calendar day, and times are expressed in seconds from the midnight that opens it.
// 00:30 after midnight is therefore 24:30 (88200 s). This keeps late-night trips on the
// same timeline as the rest of the day instead of disappearing at midnight.

(function (root) {
  "use strict";

  const DAY = 24 * 3600;
  const SERVICE_DAY_START = 3 * 3600; // 03:00
  const SERVICE_DAY_END = SERVICE_DAY_START + DAY; // 27:00 (03:00 next day)

  /** Great-circle distance in metres between two WGS84 points. */
  function haversine(lat1, lon1, lat2, lon2) {
    const R = 6371e3;
    const toRad = Math.PI / 180;
    const dPhi = (lat2 - lat1) * toRad;
    const dLambda = (lon2 - lon1) * toRad;
    const a =
      Math.sin(dPhi / 2) ** 2 +
      Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) * Math.sin(dLambda / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  /** Compass bearing (degrees, 0 = north, clockwise) from point 1 to point 2, flat-earth approx. */
  function bearing(lat1, lon1, lat2, lon2) {
    const dx = (lon2 - lon1) * Math.cos(((lat1 + lat2) / 2) * (Math.PI / 180));
    const dy = lat2 - lat1;
    return Math.round((Math.atan2(dx, dy) * 180) / Math.PI);
  }

  /** "HH:MM" (hours may exceed 23) -> seconds. Returns null when invalid. */
  function parseHHMM(value) {
    if (typeof value !== "string") return null;
    const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
    if (!match) return null;
    return Number(match[1]) * 3600 + Number(match[2]) * 60;
  }

  /** Clock seconds after midnight (0..86399) -> service-day seconds (03:00..26:59:59). */
  function toServiceTime(clockSeconds) {
    const s = ((clockSeconds % DAY) + DAY) % DAY;
    return s < SERVICE_DAY_START ? s + DAY : s;
  }

  /** Service-day seconds -> "HH:MM:SS" wall-clock string. */
  function formatClock(seconds, withSeconds = true) {
    const s = ((Math.floor(seconds) % DAY) + DAY) % DAY;
    const hh = String(Math.floor(s / 3600)).padStart(2, "0");
    const mm = String(Math.floor((s % 3600) / 60)).padStart(2, "0");
    const ss = String(s % 60).padStart(2, "0");
    return withSeconds ? `${hh}:${mm}:${ss}` : `${hh}:${mm}`;
  }

  /** True when a trip spanning [start, end] (service seconds) is running at service time t. */
  function isActiveAt(start, end, t) {
    return (t >= start && t <= end) || (t + DAY >= start && t + DAY <= end);
  }

  // --- Calendar -------------------------------------------------------------------------

  /** Easter Sunday (Gregorian calendar, anonymous algorithm). */
  function easterSunday(year) {
    const a = year % 19;
    const b = Math.floor(year / 100);
    const c = year % 100;
    const d = Math.floor(b / 4);
    const e = b % 4;
    const f = Math.floor((b + 8) / 25);
    const g = Math.floor((b - f + 1) / 3);
    const h = (19 * a + b - d - g + 15) % 30;
    const i = Math.floor(c / 4);
    const k = c % 4;
    const l = (32 + 2 * e + 2 * i - h - k) % 7;
    const m = Math.floor((a + 11 * h + 22 * l) / 451);
    const month = Math.floor((h + l - 7 * m + 114) / 31);
    const day = ((h + l - 7 * m + 114) % 31) + 1;
    return new Date(year, month - 1, day);
  }

  /** Italian national public holidays plus Milan's patron saint (Sant'Ambrogio, 7 Dec). */
  function isMilanHoliday(date) {
    const md = `${date.getMonth() + 1}-${date.getDate()}`;
    const fixed = ["1-1", "1-6", "4-25", "5-1", "6-2", "8-15", "11-1", "12-7", "12-8", "12-25", "12-26"];
    if (fixed.includes(md)) return true;
    const easterMonday = easterSunday(date.getFullYear());
    easterMonday.setDate(easterMonday.getDate() + 1);
    return (
      date.getFullYear() === easterMonday.getFullYear() &&
      date.getMonth() === easterMonday.getMonth() &&
      date.getDate() === easterMonday.getDate()
    );
  }

  /**
   * Timetable day type for a given moment: "L" weekday, "S" Saturday, "F" Sunday/holiday.
   * Before 03:00 the previous calendar day's timetable is still running.
   */
  function dayTypeFor(date = new Date()) {
    const serviceDate = new Date(date.getTime());
    if (serviceDate.getHours() * 3600 + serviceDate.getMinutes() * 60 < SERVICE_DAY_START) {
      serviceDate.setDate(serviceDate.getDate() - 1);
    }
    if (serviceDate.getDay() === 0 || isMilanHoliday(serviceDate)) return "F";
    if (serviceDate.getDay() === 6) return "S";
    return "L";
  }

  let milanFormatter = null;
  /**
   * Returns a Date whose *local* fields (getHours, getDay…) show the current wall-clock time
   * in Milan, so the simulation matches the city even when the visitor is in another time zone.
   */
  function milanClock(date = new Date()) {
    try {
      milanFormatter =
        milanFormatter ||
        new Intl.DateTimeFormat("en-GB", {
          timeZone: "Europe/Rome",
          hourCycle: "h23",
          year: "numeric",
          month: "2-digit",
          day: "2-digit",
          hour: "2-digit",
          minute: "2-digit",
          second: "2-digit",
        });
      const p = {};
      for (const part of milanFormatter.formatToParts(date)) p[part.type] = Number(part.value);
      return new Date(p.year, p.month - 1, p.day, p.hour, p.minute, p.second, date.getMilliseconds());
    } catch (e) {
      return date;
    }
  }

  // --- Misc -----------------------------------------------------------------------------

  const HTML_ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
  function escapeHtml(value) {
    return String(value ?? "").replace(/[&<>"']/g, (ch) => HTML_ESCAPES[ch]);
  }

  function hexToRgba(hex, alpha) {
    const m = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex || "");
    if (!m) return `rgba(0, 122, 255, ${alpha})`;
    return `rgba(${parseInt(m[1], 16)}, ${parseInt(m[2], 16)}, ${parseInt(m[3], 16)}, ${alpha})`;
  }

  /** Safe localStorage wrapper (storage can be unavailable in private mode or file://). */
  const storage = {
    get(key, fallback = null) {
      try {
        const v = root.localStorage && root.localStorage.getItem(key);
        return v === null || v === undefined ? fallback : v;
      } catch (e) {
        return fallback;
      }
    },
    set(key, value) {
      try {
        if (root.localStorage) root.localStorage.setItem(key, value);
      } catch (e) {
        /* ignore */
      }
    },
  };

  const TransitUtils = {
    DAY,
    SERVICE_DAY_START,
    SERVICE_DAY_END,
    haversine,
    bearing,
    parseHHMM,
    toServiceTime,
    formatClock,
    isActiveAt,
    easterSunday,
    isMilanHoliday,
    dayTypeFor,
    milanClock,
    escapeHtml,
    hexToRgba,
    storage,
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = TransitUtils;
  } else {
    root.TransitUtils = TransitUtils;
  }
})(typeof window !== "undefined" ? window : globalThis);
