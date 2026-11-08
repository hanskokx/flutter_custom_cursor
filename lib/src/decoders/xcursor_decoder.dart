import "dart:async";
import "dart:typed_data";
import "dart:ui";

import "../cursor_asset.dart";
import "../cursor_decoder.dart";

/// Decodes Linux Xcursor (`.cursor`) themes.
///
/// An Xcursor file starts with the `Xcur` magic and a table of contents whose
/// entries point at image chunks. Each image chunk carries a 36-byte header
/// (size, type, nominal size, width, height, hotspot, delay) followed by raw
/// ARGB32 pixels (or an embedded PNG). Variants are stored per nominal size
/// (24/30/36/48). When more than one image shares a size, the cursor is
/// animated and each frame has its own delay.
final class LinuxXcursorDecoder implements CursorDecoder {
  const LinuxXcursorDecoder();

  // "Xcur" represented as a Big-Endian 32-bit integer constant
  static const int _kXcur = 0x58637572;
  static const int _tocTypeImage = 0xfffd0002;

  @override
  bool detects(Uint8List bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x58 && // 'X'
        bytes[1] == 0x63 && // 'c'
        bytes[2] == 0x75 && // 'u'
        bytes[3] == 0x72; // 'r'
  }

  @override
  Future<DecodedCursor> decode(Uint8List bytes) async {
    if (!detects(bytes)) {
      throw const FormatException("not an xcursor file");
    }

    final List<_XImage> images = _parse(bytes);
    if (images.isEmpty) {
      throw const FormatException("xcursor has no images");
    }

    // Group image chunks by their nominal size (subtype). Multiple entries at
    // the same size indicate an animation.
    final Map<int, List<_XImage>> bySize = {};

    for (final _XImage image in images) {
      bySize.putIfAbsent(image.subtype, () => []).add(image);
    }

    final Iterable<List<_XImage>> animatedGroups = bySize.values.where(
      (group) => group.length > 1,
    );

    // Static: The largest single-frame image is used for non-animated cursors.
    if (animatedGroups.isEmpty) {
      final _XImage largest = bySize.values
          .reduce((a, b) => a.first.subtype >= b.first.subtype ? a : b)
          .first;

      final (Image image, Offset hotspot) = await _decodeImage(largest);
      return StaticCursor(image, hotspot: hotspot);
    }

    // Animated: pick the largest animated size group.
    final List<_XImage> largestGroup = animatedGroups.reduce(
      (a, b) => a.first.subtype >= b.first.subtype ? a : b,
    );

    // Decode all animation frames concurrently
    final List<(Image, Offset)> decodedFrames = await Future.wait(
      largestGroup.map((entry) => _decodeImage(entry)),
    );

    final List<CursorFrame> frames = [
      for (int i = 0; i < largestGroup.length; i++)
        CursorFrame(
          decodedFrames[i].$1,
          hotspot: decodedFrames[i].$2,
          duration: Duration(microseconds: largestGroup[i].delay * 1000),
        ),
    ];

    return AnimatedCursor(frames: frames);
  }

  /// Decodes a single image chunk into an [Image] plus its hotspot.
  Future<(Image, Offset)> _decodeImage(_XImage image) async {
    if (image.bytes.length >= 8 &&
        image.bytes[0] == 0x89 &&
        image.bytes[1] == 0x50) {
      final Codec codec = await instantiateImageCodec(image.bytes);
      try {
        final FrameInfo frame = await codec.getNextFrame();
        return (frame.image, image.hotspot);
      } finally {
        codec.dispose();
      }
    }

    // Raw ARGB32: reorder to RGBA8888 for decodeImageFromPixels.
    final Uint8List rgba = Uint8List(image.width * image.height * 4);
    for (int i = 0; i < image.width * image.height; i++) {
      final int src = i * 4;
      final int dst = i * 4;
      final int a = image.bytes[src];
      rgba[dst] = image.bytes[src + 1]; // R
      rgba[dst + 1] = image.bytes[src + 2]; // G
      rgba[dst + 2] = image.bytes[src + 3]; // B
      rgba[dst + 3] = a; // A
    }

    final Image img = await _rgbaToUiImage(image.width, image.height, rgba);
    return (img, image.hotspot);
  }

  static List<_XImage> _parse(Uint8List bytes) {
    final ByteData view = ByteData.sublistView(bytes);

    if (bytes.length < 16) {
      throw const FormatException("xcursor file too short");
    }

    if (view.getUint32(0, Endian.big) != _kXcur) {
      throw const FormatException("not an xcursor file");
    }

    final int headerSize = view.getUint32(4, Endian.little);
    final int ntoc = view.getUint32(12, Endian.little);
    final List<_XImage> images = [];

    for (int i = 0; i < ntoc; i++) {
      final int tocOffset = headerSize + i * 12;

      if (tocOffset + 12 > bytes.length) {
        // Table of contents entry overruns file
        break;
      }

      final int type = view.getUint32(tocOffset, Endian.little);
      if (type != _tocTypeImage) {
        // Not an image entry; skip
        continue;
      }

      final int subtype = view.getUint32(tocOffset + 4, Endian.little);
      final int position = view.getUint32(tocOffset + 8, Endian.little);
      if (position + 36 > bytes.length) {
        // Image header overruns file
        continue;
      }

      final int imageHeader = view.getUint32(position, Endian.little);
      if (imageHeader != 36) {
        // Image header size is not 36 bytes; skip
        continue;
      }

      final int width = view.getUint32(position + 16, Endian.little);
      final int height = view.getUint32(position + 20, Endian.little);
      final Offset hotspot = Offset(
        view.getUint32(position + 24, Endian.little).toDouble(),
        view.getUint32(position + 28, Endian.little).toDouble(),
      );
      final int delay = view.getUint32(position + 32, Endian.little);

      final int dataStart = position + 36;
      final bool isPng =
          bytes.length >= dataStart + 8 &&
          bytes[dataStart] == 0x89 &&
          bytes[dataStart + 1] == 0x50;

      final int dataSize = isPng
          ? bytes.length - dataStart
          : width * height * 4;

      if (dataStart + dataSize > bytes.length) {
        continue;
      }

      images.add(
        _XImage(
          subtype: subtype,
          width: width,
          height: height,
          hotspot: hotspot,
          delay: delay,
          bytes: Uint8List.sublistView(bytes, dataStart, dataStart + dataSize),
        ),
      );
    }

    return images;
  }

  static Future<Image> _rgbaToUiImage(int width, int height, Uint8List rgba) {
    final Completer<Image> completer = Completer<Image>();

    decodeImageFromPixels(
      rgba,
      width,
      height,
      PixelFormat.rgba8888,
      completer.complete,
    );

    return completer.future;
  }
}

/// One parsed Xcursor image chunk.
class const _XImage({
  required final int subtype,
  required final int width,
  required final int height,
  required final Offset hotspot,
  required final int delay,
  required final Uint8List bytes,
});
