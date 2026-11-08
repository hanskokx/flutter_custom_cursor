import "dart:async";
import "dart:typed_data";
import "dart:ui";

import "../cursor_asset.dart";
import "../cursor_decoder.dart";

/// [CursorDecoder] implementation for Windows `.cur` resources.
final class CurDecoder implements CursorDecoder {
  const CurDecoder();

  /// A `.cur` begins with a zero reserved word and a little-endian type of 2.
  @override
  bool detects(Uint8List bytes) {
    if (bytes.length < 6) {
      return false;
    }

    final ByteData view = ByteData.sublistView(bytes);

    final bool startsWithZero = view.getUint16(0, Endian.little) == 0;
    final bool isCursorType = view.getUint16(2, Endian.little) == 2;

    return startsWithZero && isCursorType;
  }

  @override
  Future<DecodedCursor> decode(Uint8List bytes) async {
    if (!detects(bytes)) {
      throw const FormatException("not a cur file");
    }

    final (Image image, Offset hotspot) = await decodeFrame(bytes);
    return StaticCursor(image, hotspot: hotspot);
  }

  /// Decodes the first raw image and hotspot from cursor resource [bytes].
  ///
  /// Throws a [FormatException] on malformed input.
  static Future<(Image, Offset)> decodeFrame(Uint8List bytes) async {
    final ByteData view = ByteData.sublistView(bytes);

    if (bytes.length < 6) {
      throw const FormatException("cursor file too short");
    }

    if (view.getUint16(0, Endian.little) != 0) {
      throw const FormatException("bad cursor reserved field");
    }

    if (view.getUint16(2, Endian.little) != 2) {
      throw const FormatException("not a cursor file");
    }

    final int count = view.getUint16(4, Endian.little);
    if (count == 0) {
      throw const FormatException("cursor has no images");
    }

    const int entry = 6;

    final Offset hotspot = Offset(
      view.getUint16(entry + 4, Endian.little).toDouble(),
      view.getUint16(entry + 6, Endian.little).toDouble(),
    );

    final int size = view.getUint32(entry + 8, Endian.little);
    final int offset = view.getUint32(entry + 12, Endian.little);

    if ((offset + size) > bytes.length) {
      throw const FormatException("cursor bitmap data truncated");
    }

    final Uint8List data = Uint8List.sublistView(bytes, offset, offset + size);

    // Modern cursors may embed a full PNG (or other compressed image) instead
    // of a raw DIB bitmap. Detect it using 32-bit integer magic checks.

    final bool hasPngHeader =
        data.length >= 8 &&
        view.getUint32(offset, Endian.big) == 0x89504E47 && // '\x89PNG'
        view.getUint32(offset + 4, Endian.big) == 0x0D0A1A0A; // '\r\n\x1a\n'

    if (hasPngHeader) {
      final Image image = await _decodeCompressed(data);

      return (
        image,
        Offset(
          hotspot.dx.clamp(0, image.width - 1),
          hotspot.dy.clamp(0, image.height - 1),
        ),
      );
    }

    final ByteData dib = ByteData.sublistView(bytes, offset, offset + size);
    if (dib.lengthInBytes < 40) {
      throw const FormatException("cursor DIB header too small");
    }

    final int dibHeaderSize = dib.getUint32(0, Endian.little);
    if (dibHeaderSize < 40) {
      throw const FormatException("cursor DIB header too small");
    }

    final int width = dib.getInt32(4, Endian.little);
    final int imageHeight = dib.getInt32(8, Endian.little);
    final int planes = dib.getUint16(12, Endian.little);
    final int bpp = dib.getUint16(14, Endian.little);

    // Read the actual number of colors used from the header.
    final int clrUsed = dib.getUint32(32, Endian.little);

    if (planes != 1) {
      throw const FormatException("unsupported cursor planes");
    }

    if (width <= 0 || width > 256) {
      throw const FormatException("bad cursor width");
    }

    if (imageHeight <= 0 || imageHeight > 1024) {
      throw const FormatException("bad cursor height");
    }

    // The DIB height doubles the XOR bitmap with the AND mask underneath.
    final int height = imageHeight ~/ 2;

    // Calculate the palette count from the header, falling back to the bit depth.
    final int paletteCount = bpp <= 8 ? (clrUsed > 0 ? clrUsed : 1 << bpp) : 0;
    final int paletteOffset = dibHeaderSize;
    final int xorOffset = paletteOffset + paletteCount * 4;

    final int xorStride = ((width * bpp + 31) >> 5) << 2;
    final int andStride = ((width + 31) >> 5) << 2;
    final int andOffset = xorOffset + xorStride * height;

    // A final bounds check to ensure masks don't overrun the file bytes.
    if (offset + andOffset + andStride * height > bytes.length) {
      throw const FormatException("cursor pixel data bounds truncated");
    }

    // Classic "invert video" cursors encode their whole shape in the XOR image
    // while the AND mask stays solid: Windows paints each non-empty XOR pixel
    // by inverting the screen underneath.
    bool isInvertVideo = bpp <= 8;

    if (isInvertVideo) {
      outer:
      for (int row = 0; row < height; row++) {
        final srcRow = height - 1 - row;
        final base = offset + andOffset + srcRow * andStride;
        for (int x = 0; x < width; x++) {
          final bit = (bytes[base + (x >> 3)] >> (7 - (x & 7))) & 1;

          // If any pixel in the AND mask is transparent, this is not an
          // invert-video cursor.
          if (bit != 0) continue;

          isInvertVideo = false;
          break outer;
        }
      }
    }

    final Uint8List rgba = Uint8List(width * height * 4);

    // Select the optimal decoding path based on the bit depth and whether this
    // is an invert-video cursor.
    if (isInvertVideo) {
      for (int row = 0; row < height; row++) {
        final int srcRow = height - 1 - row;
        final int xorBase = offset + xorOffset + srcRow * xorStride;
        final int destRowOffset = row * width * 4;

        for (int x = 0; x < width; x++) {
          final int index = switch (bpp) {
            1 => (bytes[xorBase + (x >> 3)] >> (7 - (x & 7))) & 1,
            4 =>
              x.isEven
                  ? (bytes[xorBase + (x >> 1)] >> 4) & 0xF
                  : bytes[xorBase + (x >> 1)] & 0xF,
            _ => bytes[xorBase + x],
          };

          // Skip any pixel whose palette index is out of bounds
          if (index >= paletteCount) continue;
          if (index == 0) continue;

          rgba[destRowOffset + (x * 4) + 3] = 255;
        }
      }
    } else if (bpp <= 8) {
      for (int row = 0; row < height; row++) {
        final int srcRow = height - 1 - row;
        final int xorBase = offset + xorOffset + srcRow * xorStride;
        final int andBase = offset + andOffset + srcRow * andStride;
        final int destRowOffset = row * width * 4;

        for (int x = 0; x < width; x++) {
          final int andByte = bytes[andBase + (x >> 3)];

          // Transparent: skip any pixel whose AND mask bit is set
          if (((andByte >> (7 - (x & 7))) & 1) != 0) continue;

          final int index = switch (bpp) {
            1 => (bytes[xorBase + (x >> 3)] >> (7 - (x & 7))) & 1,
            4 =>
              x.isEven
                  ? (bytes[xorBase + (x >> 1)] >> 4) & 0xF
                  : bytes[xorBase + (x >> 1)] & 0xF,
            _ => bytes[xorBase + x],
          };

          final int dest = destRowOffset + (x * 4);
          final int paletteIndex = index * 4;

          // Skip any pixel whose palette index is out of bounds
          if (paletteIndex + 3 >= paletteCount * 4) {
            rgba[dest + 3] = 255;
            continue;
          }

          final int p = offset + paletteOffset + paletteIndex;
          rgba[dest] = bytes[p + 2]; // R
          rgba[dest + 1] = bytes[p + 1]; // G
          rgba[dest + 2] = bytes[p]; // B
          rgba[dest + 3] = 255; // A
        }
      }
    } else if (bpp == 24) {
      for (int row = 0; row < height; row++) {
        final int srcRow = height - 1 - row;
        final int xorBase = offset + xorOffset + srcRow * xorStride;
        final int andBase = offset + andOffset + srcRow * andStride;
        final int destRowOffset = row * width * 4;

        for (int x = 0; x < width; x++) {
          final int andByte = bytes[andBase + (x >> 3)];

          // Transparent: skip any pixel whose AND mask bit is set
          if (((andByte >> (7 - (x & 7))) & 1) != 0) continue;

          final int p = xorBase + x * 3;
          final int dest = destRowOffset + (x * 4);

          rgba[dest] = bytes[p + 2]; // R
          rgba[dest + 1] = bytes[p + 1]; // G
          rgba[dest + 2] = bytes[p]; // B
          rgba[dest + 3] = 255; // A
        }
      }
    } else if (bpp == 32) {
      for (int row = 0; row < height; row++) {
        final int srcRow = height - 1 - row;
        final int xorBase = offset + xorOffset + srcRow * xorStride;
        final int andBase = offset + andOffset + srcRow * andStride;
        final int destRowOffset = row * width * 4;

        for (int x = 0; x < width; x++) {
          final int andByte = bytes[andBase + (x >> 3)];

          // Transparent: skip any pixel whose AND mask bit is set
          if (((andByte >> (7 - (x & 7))) & 1) != 0) continue;

          final int p = xorBase + x * 4;
          final int dest = destRowOffset + (x * 4);

          rgba[dest] = bytes[p + 2]; // R
          rgba[dest + 1] = bytes[p + 1]; // G
          rgba[dest + 2] = bytes[p]; // B

          final int alpha = bytes[p + 3];

          rgba[dest + 3] = alpha == 0 ? 255 : alpha;
        }
      }
    } else {
      throw FormatException("unsupported bpp: $bpp");
    }

    final Image image = await _rgbaToUiImage(width, height, rgba);
    return (
      image,
      Offset(hotspot.dx.clamp(0, width - 1), hotspot.dy.clamp(0, height - 1)),
    );
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

  static Future<Image> _decodeCompressed(Uint8List bytes) async {
    try {
      final Codec codec = await instantiateImageCodec(bytes);
      try {
        final FrameInfo frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } on Exception {
      throw const FormatException("unsupported compressed cursor data");
    }
  }
}
