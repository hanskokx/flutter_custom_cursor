## 0.1.0

* Initial release.
* Decodes Windows `.cur`/`.ani`, Linux Xcursor, and raster image cursors (PNG,
  GIF/APNG, WebP, JPEG, BMP).
* Displays custom cursors through `CustomMouseCursor` on Android, Linux, macOS,
  Windows, and the web.
* Provides `StaticCursor` and `AnimatedCursor` decoded models plus
  `decodeCursorAsset` for already-loaded bytes.
