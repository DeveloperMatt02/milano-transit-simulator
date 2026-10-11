# maplibre_gl 0.27 · OnePlus Nord 4 (Android) · release APK

Run by the author on 2026-10-10 22:29, Flutter 3.47.7, arm64 release build from the *Map spike* workflow.
The display ran at 90 Hz during the test (tick p50 11.1 ms).

Map spike · maplibre_gl 0.27 · android · 2026-10-10T22:29:12.227738
(benchmark: 3 s warm-up, 15 s per row)

| vehicles | mode | tick p50 ms | tick p95 ms | ticks > 16.7 ms | update p50 ms | update p95 ms | build p95 ms | raster p95 ms | updates sent | skipped | RSS MB |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 150 | every frame | 11.1 | 11.1 | 0.4 % | 8.8 | 12.6 | 1.0 | 6.1 | 1314 | 34 | 362 |
| 150 | 10 Hz | 11.1 | 11.1 | 3.0 % | 17.7 | 22.6 | 2.8 | 7.3 | 135 | 0 | 350 |
| 300 | every frame | 11.1 | 11.1 | 0.7 % | 11.5 | 19.4 | 2.0 | 6.0 | 1094 | 251 | 360 |
| 300 | 10 Hz | 11.1 | 11.1 | 5.0 % | 24.6 | 34.6 | 4.7 | 7.1 | 135 | 0 | 348 |
| 1000 | every frame | 11.1 | 22.2 | 37.2 % | 19.5 | 38.1 | 4.8 | 7.1 | 648 | 335 | 379 |
| 1000 | 10 Hz | 11.1 | 22.2 | 18.2 % | 39.7 | 61.2 | 10.8 | 7.6 | 135 | 0 | 367 |
| 3000 | every frame | 22.2 | 55.4 | 51.5 % | 57.8 | 69.4 | 10.8 | 8.1 | 255 | 246 | 433 |
| 3000 | 10 Hz | 11.1 | 44.3 | 19.5 % | 62.8 | 80.0 | 9.8 | 8.2 | 135 | 0 | 443 |
