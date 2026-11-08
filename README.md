# custom_cursor

Custom cursor decoding and display for Flutter apps.

`custom_cursor` decodes Windows `.cur` and `.ani` resources, Linux Xcursor themes, and native raster images (PNG/GIF/APNG/WebP/JPEG/BMP) into [DecodedCursor] models (`StaticCursor` or `AnimatedCursor`). Use Flutter's `MouseRegion` to display a cursor while the mouse hovers its subtree.

## Platforms

| Platform | Support | Implementation            |
| -------- | ------- | ------------------------- |
| macOS    | ✅       | Swift Package Manager     |
| Windows  | ✅       | C++ (GDI+)                |
| Linux    | ✅       | C++ (GTK3)                |
| Web      | ✅       | CSS `cursor: url(...)`    |
| Android  | ✅       | Kotlin (API 24+)          |
| iOS      | ❌       | Not supported by platform |

### Linux prerequisites

Building on Linux requires GTK3 development headers:

```sh
sudo apt-get install -y libgtk-3-dev
```

## Cursor size limit

Windows and Linux clamp cursor images to **128 px** per dimension, matching the platform limit. macOS and the web use the image's native size; browsers may apply their own limit.

## Android

Android support requires a minimum SDK of **24** (the pointer-icon API is gated behind `Build.VERSION.SDK_INT >= N`; on older devices the system arrow is kept).

## Usage

A `CustomMouseCursor` is a Flutter `MouseCursor` that decodes its own image from a cursor file. Use `MouseRegion` with any `MouseCursor` (custom or system)
to select the cursor while the mouse hovers its child. Cursors decode lazily the first time they are shown, or eagerly via `precache()`.

```dart
import "package:custom_cursor/custom_cursor.dart";

final move = CustomMouseCursor.fromAsset("assets/cursors/move.cur");

// Custom and system cursors work directly with MouseRegion:
MouseRegion(cursor: move, child: child);
MouseRegion(cursor: SystemMouseCursors.click, child: child);
```

To use the bytes of a cursor file you already have in memory (downloaded, read from disk, or dropped onto the window):

```dart
final cursor = CustomMouseCursor.memory(bytes);
```

To use data you have already decoded, wrap the `DecodedCursor`:

```dart
final decoded = await decodeCursorAsset(bytes);
final cursor = CustomMouseCursor.decoded(decoded);
```

To create a cursor directly from a raw `ui.Image` with an optional `hotspot`:

```dart
final cursor = CustomMouseCursor.fromImage(myImage, hotspot: const Offset(8, 8));
```

Equal cursors (same asset path, package, and bundle, the same `Uint8List` instance, or the same decoded `DecodedCursor` instance) share a single native activation. Animated cursors play their frames automatically.

Cursors use the `"custom_cursor"` method channel.
