# Roadmap

From a synthetic-timetable web app to a multiplatform app (web, Android, iOS) built on the city's real GTFS timetable.

Decisions: [ADR index](adr/README.md) · Starting point: [F0 baseline review](reviews/F0-baseline-review.md)

---

## Phases

| Phase | Goal | Where it runs / is tested | Status |
| --- | --- | --- | --- |
| **F0** Foundations | ADRs, roadmap, baseline review, engine benchmark, dev setup guide | Node + Python (here) | ✅ Done |
| **F1** GTFS data pipeline | `build_gtfs.py`: patterns + time profiles + calendars + simplified shapes; metro stops matched to the JS network stations (the 125 stations are a cross-check in the real-feed test); size budget test; fixture mini-GTFS tests; scheduled refresh workflow; deploy gated on tests; SRI on CDN resources | Python (here), workflow on GitHub | ✅ Done |
| **F2** Flutter + MapLibre spike (go/no-go) | Metro network + animated vehicles on web and Android against the criteria in ADR 0001 (300 must pass, 3,000 measured); compare `maplibre_gl` and `maplibre`; ADR 0005 with the numbers | GitHub Actions builds, author's OnePlus Nord 4 ([spike/](../spike/README.md)) | ✅ Done — `maplibre_gl` ([ADR 0005](adr/0005-map-library-maplibre-gl.md)) |
| **F3** Dart core | `packages/transit_core`: time model, calendar, synthetic scheduler, GTFS model, simulation with time-bucket and stop indexes; **parity tests** against the JS engine on shared fixtures; engine time budget asserted in CI | `dart test` (PC + CI) | — |
| **F4** Flutter app, feature parity | Install [Impeccable](https://impeccable.style/docs/) on the author's PC at the start of F4 for UI audits; map layers, themes, IT/EN, bottom sheets, departure boards, vehicle tracking, time travel, search, settings, accessibility; unit, widget and golden tests | PC + CI | — |
| **F5** Distribution | Web on Pages (Flutter at `/`, Lite at `/lite/` with deprecation banner); Android APK/AAB signed in CI; iOS unsigned build on macOS runner | GitHub Actions | — |
| **F6** New features | Surface routes along streets (GTFS shapes); frequency heat-map per segment and hour; journey planner between two stops (Connection Scan Algorithm); suburban S lines if a Trenord feed is usable; M5 Monza extension when it opens | PC + CI | — |
| **F7** Clean-up | README, ARCHITECTURE and TECHNICAL_DESIGN rewritten for the Flutter app; Lite removal date set | — | — |

Every phase ends with: tests green, an independent code review, docs updated, and the author's approval before the next phase starts. Each phase lives on its own branch (`f1-gtfs-pipeline`, …) and is merged by the author.

## Decisions log

| Date | Decision |
| --- | --- |
| 2026-10-10 | Flutter chosen for web, Android and iOS, gated by the F2 spike ([ADR 0001](adr/0001-flutter-multiplatform-app.md)) |
| 2026-10-10 | GTFS feed of the Comune di Milano verified and adopted as primary source, synthetic timetable as fallback ([ADR 0002](adr/0002-gtfs-primary-data-source.md)) |
| 2026-10-10 | JS app kept as deprecated "Lite" with a banner pointing to the Flutter app, removed later ([ADR 0003](adr/0003-js-lite-deprecation.md)) |
| 2026-10-10 | GTFS fallback per route and day, compact format v1, datasets rebuilt by CI and not committed, refresh twice a week ([ADR 0004](adr/0004-gtfs-dataset-format-and-refresh.md)) |
| 2026-10-11 | Map library `maplibre_gl` 0.27; both candidates passed 300 vehicles at 60 fps, `maplibre` 0.3.6 fails in R8 release builds; viewport culling required for the whole network; Flutter pinned to 3.47.7 ([ADR 0005](adr/0005-map-library-maplibre-gl.md)) |
| 2026-10-10 | Development on Fedora Linux without a Mac: iOS built in CI only. F2 compiled by GitHub Actions and tested on the author's OnePlus Nord 4; Flutter installed locally before F3 ([DEV_SETUP](DEV_SETUP.md)) |

## Open points

| Raised | Point | When to revisit |
| --- | --- | --- |
| 2026-10-10 | Fallback rule per route and day (`coverage_end`) accepted "for now": revisit with the author — partial-day coverage, wording of the "estimated times" notice, whether to hide instead of estimate | After F3, before the Flutter UI shows it |
| 2026-10-10 | Scheduled GTFS refresh stops after 60 days without repository activity (GitHub rule for public repos): decide on a keep-alive or a reminder | Before F5 |
| 2026-10-10 | Install Impeccable (`npx impeccable install`, then `/impeccable init`) for the UI work | Start of F4 (and for the Lite deprecation banner in F5) |

## Known constraints

- The Claude workspace used for development cannot reach pub.dev, the Flutter SDK storage or the city's open-data portal. Python and JS work is tested there; Dart/Flutter builds and the real GTFS download run on the author's PC and on GitHub Actions.
- iOS distribution needs an Apple Developer account (not planned yet).
- GTFS releases expire within weeks (the one checked on 2026-10-10 ends on 19 Oct 2026). Until F1 ships, the app keeps using the synthetic timetable, so nothing breaks; after F1 the scheduled workflow and the synthetic fallback cover late releases.
