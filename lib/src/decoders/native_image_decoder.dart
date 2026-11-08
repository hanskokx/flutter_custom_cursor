import "dart:typed_data";
import "dart:ui";

import "../cursor_asset.dart";
import "../cursor_decoder.dart";

/// Decodes raster image formats (PNG, GIF, animated GIF, APNG, WebP, JPEG,
/// BMP) into cursors using [instantiateImageCodec].
///
/// Single-frame images become a [StaticCursor]; multi-frame images become an
/// [AnimatedCursor] whose frame durations come from the codec. Raster images
/// have no intrinsic hotspot, so the top-left corner is used.
final class NativeImageDecoder implements CursorDecoder {
  const NativeImageDecoder();

  @override
  bool detects(Uint8List bytes) {
    return _png(bytes) ||
        _jpg(bytes) ||
        _gif(bytes) ||
        _webp(bytes) ||
        _bmp(bytes);
  }

  @override
  Future<DecodedCursor> decode(Uint8List bytes) async {
    Codec codec;
    try {
      codec = await instantiateImageCodec(bytes);
    } on Exception {
      throw const FormatException("invalid image data");
    }
    try {
      final int frameCount = codec.frameCount;
      final List<(Image, Duration)> frames = [];

      for (int i = 0; i < frameCount; i++) {
        final FrameInfo frame = await codec.getNextFrame();
        frames.add((frame.image, frame.duration));
      }

      if (frames.isEmpty) {
        throw const FormatException("image has no frames");
      }

      if (frames.length == 1) {
        return StaticCursor(frames.single.$1);
      }

      return AnimatedCursor(
        frames: [
          for (final (Image image, Duration duration) in frames)
            CursorFrame(
              image,
              duration: duration > Duration.zero
                  ? duration
                  : const Duration(milliseconds: 16),
            ),
        ],
      );
    } finally {
      codec.dispose();
    }
  }

  static bool _png(Uint8List b) {
    return b.length >= 8 &&
        b[0] == 0x89 && // PNG signature
        b[1] == 0x50 && // 'P'
        b[2] == 0x4e && // 'N'
        b[3] == 0x47; // 'G'
  }

  static bool _jpg(Uint8List b) =>
      b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff;

  static bool _gif(Uint8List b) {
    if (b.length < 6) return false;

    final bool signature =
        b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38;

    final bool isGif87a = b[4] == 0x37 && b[5] == 0x61;
    final bool isGif89a = b[4] == 0x39 && b[5] == 0x61;

    return signature && (isGif87a || isGif89a);
  }

  static bool _webp(Uint8List b) =>
      b.length >= 12 &&
      b[0] == 0x52 && // 'R'
      b[1] == 0x49 && // 'I'
      b[2] == 0x46 && // 'F'
      b[3] == 0x46 && // 'F'
      b[8] == 0x57 && // 'W'
      b[9] == 0x45 && // 'E'
      b[10] == 0x42 && // 'B'
      b[11] == 0x50; // 'P'

  static bool _bmp(Uint8List b) =>
      b.length >= 2 && b[0] == 0x42 && b[1] == 0x4d;
}
