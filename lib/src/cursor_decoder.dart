import "dart:typed_data";

import "cursor_asset.dart";
import "decoders/ani_decoder.dart";
import "decoders/cur_decoder.dart";
import "decoders/native_image_decoder.dart";
import "decoders/xcursor_decoder.dart";

/// Decodes one cursor file format into a [DecodedCursor].
abstract interface class CursorDecoder {
  /// Whether [bytes] starts with this decoder's file signature.
  bool detects(Uint8List bytes);

  /// Decodes [bytes] into a [DecodedCursor].
  ///
  /// Throws a [FormatException] when the data is malformed.
  Future<DecodedCursor> decode(Uint8List bytes);
}

/// The decoders tried, in priority order, when sniffing [bytes].
const List<CursorDecoder> _decoders = [
  AniDecoder(),
  CurDecoder(),
  LinuxXcursorDecoder(),
  NativeImageDecoder(),
];

/// Decodes [bytes] into a [DecodedCursor].
///
/// The first decoder whose signature matches [bytes] handles the data; no
/// other decoder is tried. Throws a [FormatException] when the format is not
/// supported or the data is malformed.
Future<DecodedCursor> decodeCursorAsset(Uint8List bytes) async {
  for (final CursorDecoder decoder in _decoders) {
    if (decoder.detects(bytes)) {
      return decoder.decode(bytes);
    }
  }

  throw const FormatException("unsupported cursor format");
}
