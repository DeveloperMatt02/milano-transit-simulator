const test = require("node:test");
const assert = require("node:assert/strict");
const U = require("../../js/utils.js");

test("haversine: Duomo to Centrale is about 2.3 km", () => {
  const d = U.haversine(45.4641, 9.1885, 45.4846, 9.2028);
  assert.ok(d > 2400 && d < 2600, `${d}`);
});

test("bearing: north is 0°, east is 90°", () => {
  assert.equal(U.bearing(45, 9, 46, 9), 0);
  assert.equal(U.bearing(45, 9, 45, 10), 90);
});

test("parseHHMM accepts service-day hours above 23", () => {
  assert.equal(U.parseHHMM("05:30"), 5.5 * 3600);
  assert.equal(U.parseHHMM("25:15"), 25 * 3600 + 15 * 60);
  assert.equal(U.parseHHMM("nope"), null);
});

test("toServiceTime maps early-morning clock times after 24:00", () => {
  assert.equal(U.toServiceTime(0), 24 * 3600);
  assert.equal(U.toServiceTime(2.5 * 3600), 26.5 * 3600);
  assert.equal(U.toServiceTime(3 * 3600), 3 * 3600);
  assert.equal(U.toServiceTime(23 * 3600), 23 * 3600);
});

test("formatClock wraps service time back to a wall clock", () => {
  assert.equal(U.formatClock(24.5 * 3600), "00:30:00");
  assert.equal(U.formatClock(7 * 3600 + 5 * 60 + 9), "07:05:09");
  assert.equal(U.formatClock(25 * 3600, false), "01:00");
});

test("isActiveAt handles trips that spill over the end of the service day", () => {
  assert.ok(U.isActiveAt(100, 200, 150));
  assert.ok(!U.isActiveAt(100, 200, 250));
  // A night trip from 26:50 to 27:40 is still running at 03:10 (= 27:10 of the previous service day).
  assert.ok(U.isActiveAt(26 * 3600 + 50 * 60, 27 * 3600 + 40 * 60, 3 * 3600 + 10 * 60));
});

test("easterSunday matches known dates", () => {
  assert.equal(U.easterSunday(2025).toDateString(), new Date(2025, 3, 20).toDateString());
  assert.equal(U.easterSunday(2026).toDateString(), new Date(2026, 3, 5).toDateString());
});

test("dayTypeFor: weekday, Saturday, Sunday, holidays and the 03:00 cut-off", () => {
  assert.equal(U.dayTypeFor(new Date(2026, 8, 28, 12)), "L"); // Monday
  assert.equal(U.dayTypeFor(new Date(2026, 8, 26, 12)), "S"); // Saturday
  assert.equal(U.dayTypeFor(new Date(2026, 8, 27, 12)), "F"); // Sunday
  assert.equal(U.dayTypeFor(new Date(2026, 11, 7, 12)), "F"); // Sant'Ambrogio (Monday)
  assert.equal(U.dayTypeFor(new Date(2026, 3, 6, 12)), "F"); // Easter Monday 2026
  assert.equal(U.dayTypeFor(new Date(2026, 8, 27, 0, 30)), "S"); // Sunday 00:30 -> Saturday service
  assert.equal(U.dayTypeFor(new Date(2026, 8, 28, 2, 59)), "F"); // Monday 02:59 -> Sunday service
});

test("escapeHtml neutralises markup", () => {
  assert.equal(U.escapeHtml(`<a href="x">'&'</a>`), "&lt;a href=&quot;x&quot;&gt;&#39;&amp;&#39;&lt;/a&gt;");
});

test("milanClock converts any instant to Milan wall-clock time", () => {
  // 2026-09-28 10:00 UTC is 12:00 in Milan (CEST, UTC+2).
  const summer = U.milanClock(new Date(Date.UTC(2026, 8, 28, 10, 0, 0)));
  assert.equal(summer.getHours(), 12);
  assert.equal(summer.getDate(), 28);
  // 2026-12-31 23:30 UTC is 00:30 on 1 January in Milan (CET, UTC+1).
  const winter = U.milanClock(new Date(Date.UTC(2026, 11, 31, 23, 30, 0)));
  assert.equal(winter.getFullYear(), 2027);
  assert.equal(winter.getHours(), 0);
  assert.equal(winter.getMinutes(), 30);
});
