# ADR 0003 · Keep the JavaScript app as a deprecated "lite" version

**Status:** Accepted (2026-10-10)

## Context

The Flutter app ([ADR 0001](0001-flutter-multiplatform-app.md)) replaces the current vanilla-JS app. The JS version is light (no build, ~1 MB with data), works on old browsers and from `file://`, and is the version that exists today at the public URL.

## Decision

- The JS app is kept as **"Lite"**, in maintenance mode: data refreshes and fixes only, no new features.
- **URL layout on GitHub Pages**
  - until the Flutter app reaches feature parity (end of F5): JS app at `/` as today; Flutter builds are CI artifacts and previews;
  - from the switch-over: Flutter app at `/`, Lite at `/lite/`, both deployed by the same workflow. Existing query parameters (`?simulation`, `?lang=`) work in both.
- From the switch-over the Lite version shows a **deprecation banner**: bilingual (IT/EN), links to the Flutter app keeping the current query parameters, dismissible, the dismissal remembered in `localStorage` (safe wrapper) and shown again when the removal date gets close. The banner is driven by a single configuration object (app URL, removal date) so it can be enabled without touching the markup.
- **Removal:** when the Flutter app has been live and stable for at least three months; the exact date is set by the author and written in the banner beforehand.

## Consequences

- Two apps to deploy for a while; the workflow builds both into one Pages artifact.
- Bug fixes that matter for both (data, time model) are made in the pipeline or in the shared fixtures, so they reach both apps.
