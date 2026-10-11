# F2 · Map library spike (archived)

The spike that chose the map library ([ADR 0005](../../adr/0005-map-library-maplibre-gl.md)) was removed from the tree at the end of F3. Its code is in the git history: the last version is commit `fae2cc7` (merged into `main` by pull request #2), folder `spike/`, workflow `.github/workflows/spike.yml`.

Raw results on the author's OnePlus Nord 4:

- [maplibre_gl 0.27](2026-10-10-oneplus-nord4-maplibre_gl.md)
- [maplibre 0.3.6](2026-10-10-oneplus-nord4-maplibre.md) (release APK without R8)

## Lessons for F4

- **Keep the map behind an interface** (`MapBackend` in the spike: `buildMap`, `showLines`, `updateVehicles`). The rest of the app never touches the library.
- **Android release builds need `android.permission.INTERNET`** in the manifest for the base-map tiles (debug builds add it implicitly).
- **One vehicle update in flight**: if the previous `setGeoJsonSource` has not completed, skip the frame's update instead of queueing.
- **Measure in the app**: the spike's HUD (frame interval percentiles, update time, skipped updates, RSS) was enough to decide; a debug overlay with the same numbers is worth keeping behind a flag.
- **maplibre (josxha) 0.3.6** needed the ktlint Gradle plugin declared by the app and fails to start the map in R8 release builds (`NullPointerException` while creating the platform view). Not used.
- `flutter create` on CI generates the platform folders; the app keeps them committed from F4 on, so these fixes live in the repository instead of a script.
