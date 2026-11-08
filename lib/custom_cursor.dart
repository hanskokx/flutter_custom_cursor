/// Custom cursor decoding and display for Flutter.
///
/// Provides decoders for Windows `.cur` and `.ani` resources, Linux Xcursor
/// themes, and native raster images (PNG/GIF/APNG/WebP/JPEG/BMP) into
/// [CustomMouseCursor]s (Flutter `MouseCursor`s that decode themselves).
library;

export "src/cursor.dart";
export "src/cursor_asset.dart";
export "src/cursor_decoder.dart";
export "src/decoders/ani_decoder.dart";
export "src/decoders/cur_decoder.dart";
export "src/decoders/native_image_decoder.dart";
export "src/decoders/xcursor_decoder.dart";
