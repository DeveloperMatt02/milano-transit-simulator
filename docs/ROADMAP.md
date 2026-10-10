# Roadmap

From a synthetic-timetable web app to a multiplatform app (web, Android, iOS) built on the city's real GTFS timetable.

Decisions: [ADR index](adr/README.md) · Starting point: [F0 baseline review](reviews/F0-baseline-review.md)

---

## Phases

| Phase | Goal | Where it runs / is tested | Status |
| --- | --- | --- | --- |
| **F0** Foundations | ADRs, roadmap, baseline review, engine benchmark, dev setup guide | Node + Python (here) | 🔍 In review |
| **F1** GTFS data pipeline | `build_gtfs.py`: patterns + time profiles + calendars + simplified shapes; metro topology derived from the feed (hand-written builder kept as cross-check); size budget test; fixture mini-GTFS tests; scheduled refresh workflow; deploy gated on tests; SRI on CDN resources | Python (here), workflow on GitHub | ⏳ Next |
| **F2** Flutter + MapLibre spike (go/no-go) | Metro network + animated vehicles on web and Android against the criteria in ADR 0001 (300 must pass, 3,000 measured); compare `maplibre_gl` and `maplibre`; ADR 0004 with the numbers | Author's PC + GitHub Actions | — |
| **F3** Dart core | `packages/transit_core`: time model, calendar, synthetic scheduler, GTFS model, simulation with time-bucket and stop indexes; **parity tests** against the JS engine on shared fixtures; engine time budget asserted in CI | `dart test` (PC + CI) | — |
| **F4** Flutter app, feature parity | Map layers, themes, IT/EN, bottom sheets, departure boards, vehicle tracking, time travel, search, settings, accessibility; unit, widget and golden tests | PC + CI | — |
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
| 2026-10-10 | Development on Ubuntu without a Mac: iOS built in CI only; Flutter toolchain to be installed on the author's PC before F2 ([DEV_SETUP](DEV_SETUP.md)) |

## Known constraints

- The Claude workspace used for development cannot reach pub.dev, the Flutter SDK storage or the city's open-data portal. Python and JS work is tested there; Dart/Flutter builds and the real GTFS download run on the author's PC and on GitHub Actions.
- iOS distribution needs an Apple Developer account (not planned yet).
- GTFS releases expire within weeks (the one checked on 2026-10-10 ends on 19 Oct 2026). Until F1 ships, the app keeps using the synthetic timetable, so nothing breaks; after F1 the scheduled workflow and the synthetic fallback cover late releases.
