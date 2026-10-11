# maplibre 0.3.6 · OnePlus Nord 4 (Android) · release APK without R8

Run by the author on 2026-10-10 23:42, Flutter 3.47.7, arm64 release build from the *Map spike* workflow
(`app_maplibre-no-r8.apk`, Gradle property `shrink=false`). The default release APK (R8 on) and the
Hybrid Composition variant (`app_maplibre-hc.apk`, R8 on) never showed the map: the platform view creation
failed with `java.lang.NullPointerException` (obfuscated stack trace, see below). Without R8 the map works.
Visual impression reported by the author: same as maplibre_gl (smooth at 300, fairly smooth at 3,000,
panning responsive).

Map spike · maplibre 0.3 [tlhc_vd, no-R8] · android · 2026-10-10T23:42:52.026946
(benchmark: 3 s warm-up, 15 s per row)

| vehicles | mode | tick p50 ms | tick p95 ms | ticks > 16.7 ms | update p50 ms | update p95 ms | build p95 ms | raster p95 ms | updates sent | skipped | RSS MB |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 150 | every frame | 11.1 | 11.1 | 0.4 % | 1.2 | 2.1 | 3.2 | 2.1 | 1347 | 0 | 322 |
| 150 | 10 Hz | 11.1 | 11.1 | 4.4 % | 4.3 | 9.2 | 5.6 | 3.3 | 135 | 0 | 308 |
| 300 | every frame | 11.1 | 11.1 | 0.6 % | 2.0 | 2.8 | 3.5 | 1.9 | 1344 | 0 | 331 |
| 300 | 10 Hz | 11.1 | 22.2 | 9.0 % | 7.9 | 12.0 | 9.0 | 3.3 | 135 | 0 | 315 |
| 1000 | every frame | 11.1 | 22.2 | 26.8 % | 5.4 | 7.1 | 7.8 | 1.7 | 1067 | 0 | 395 |
| 1000 | 10 Hz | 11.1 | 22.2 | 10.2 % | 11.8 | 19.2 | 13.2 | 2.8 | 135 | 0 | 380 |
| 3000 | every frame | 22.2 | 33.3 | 100.0 % | 14.1 | 19.4 | 19.7 | 1.7 | 594 | 0 | 493 |
| 3000 | 10 Hz | 11.1 | 44.3 | 14.1 % | 24.5 | 35.5 | 27.3 | 2.5 | 135 | 0 | 450 |

Failure with R8 (Hybrid Composition variant, identical NPE with the default mode):

```
PlatformException(error, null, null, java.lang.NullPointerException
	at il.b(r8-map-id-003d283e…:47)
	at c0.a(r8-map-id-003d283e…:17)
	at g1.a(r8-map-id-003d283e…:7)
	at c0.z(r8-map-id-003d283e…:851)
	at c0.j(r8-map-id-003d283e…:346)
	at g1.o(r8-map-id-003d283e…:28)
	at t6.run(r8-map-id-003d283e…:130)
	at android.os.Handler.handleCallback(Handler.java:1027)
	…
```
