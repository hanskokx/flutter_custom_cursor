import "dart:async";
import "dart:typed_data";
import "dart:ui";

import "../cursor_asset.dart";
import "../cursor_decoder.dart";
import "cur_decoder.dart";

/// Decodes Windows animated cursor (`.ani`) resources.
///
/// An `.ani` file is a RIFF `ACON` container holding an `anih` header, a
/// `LIST fram` of `icon` subchunks (each a single-frame `.cur`), an optional
/// `seq ` chunk that plays frames out of order, and an optional `rate` chunk
/// giving each play step's duration in 1/60ths of a second.
final class AniDecoder implements CursorDecoder {
  const AniDecoder();

  // Header byte integer constants (Big-Endian representation)
  static const int _kRiff = 0x52494646; // "RIFF"
  static const int _kAcon = 0x41434F4E; // "ACON"
  static const int _kAnih = 0x616E6968; // "anih"
  static const int _kList = 0x4C495354; // "LIST"
  static const int _kFram = 0x6672616D; // "fram"
  static const int _kSeq = 0x73657120; // "seq "
  static const int _kRate = 0x72617465; // "rate"
  static const int _kIcon = 0x69636F6E; // "icon"

  /// An `.ani` is a RIFF chunk whose form type is `ACON`.
  @override
  bool detects(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final ByteData view = ByteData.sublistView(bytes);

    final bool isRiff = view.getUint32(0, Endian.big) == _kRiff;
    final bool isAcon = view.getUint32(8, Endian.big) == _kAcon;

    return isRiff && isAcon;
  }

  @override
  Future<DecodedCursor> decode(Uint8List bytes) async {
    if (!detects(bytes)) {
      throw const FormatException("not an ani file");
    }

    final ByteData view = ByteData.sublistView(bytes);

    // Walk the top-level RIFF chunks.
    int baseDelayMicros = 16 * 1000;
    final List<(Image, Offset)> images = [];
    List<int>? seq;
    List<int>? rates;

    for (int offset = 12; offset + 8 <= bytes.length;) {
      final int id = view.getUint32(offset, Endian.big);
      final int size = view.getUint32(offset + 4, Endian.little);
      final int body = offset + 8;

      // Ensure chunk doesn't overflow file bounds
      if (body + size > bytes.length) {
        throw const FormatException("ani chunk runs past end of file");
      }

      switch (id) {
        case _kAnih:
          if (size < 36) throw const FormatException("bad ani header");

          final int dispRate = view.getUint32(body + 28, Endian.little);
          if (dispRate > 0) {
            // iDispRate is in 1/60ths of a second.
            baseDelayMicros = dispRate * 1000000 ~/ 60;
          }

        case _kList:
          // Ignore non-fram lists (e.g., INFO metadata chunks)
          if (size < 4 || view.getUint32(body, Endian.big) != _kFram) break;
          images.addAll(await _parseFrames(view, body + 4, body + size));

        case _kSeq:
          // The seq chunk defines the playback order indices
          seq = [
            for (int i = 0; i < size ~/ 4; i++)
              view.getUint32(body + i * 4, Endian.little),
          ];

        case _kRate:
          // The rate chunk defines step durations
          rates = [
            for (int i = 0; i < size ~/ 4; i++)
              view.getUint32(body + i * 4, Endian.little),
          ];
      }

      final int padding = size.isOdd ? 1 : 0;
      offset = body + size + padding;
    }

    if (images.isEmpty) {
      throw const FormatException("ani has no frames");
    }

    final List<int> play = seq ?? List<int>.generate(images.length, (i) => i);

    final List<CursorFrame> frames = [];

    for (final int i in play) {
      final int index = play[i];

      if (index < 0 || index >= images.length) continue;

      final (Image image, Offset hotspot) = images[index];

      final int rate = rates != null && i < rates.length ? rates[i] : 0;
      final int micros = rate > 0 ? rate * 1000000 ~/ 60 : baseDelayMicros;

      frames.add(
        CursorFrame(
          image,
          hotspot: hotspot,
          duration: Duration(microseconds: micros),
        ),
      );
    }

    if (frames.isEmpty) {
      throw const FormatException("ani has no playable frames");
    }

    return AnimatedCursor(frames: frames);
  }

  /// Parses consecutive `icon` subchunks starting at [start] (inclusive) up to
  /// [end] (exclusive) within the `LIST fram` body concurrently.
  static Future<List<(Image, Offset)>> _parseFrames(
    ByteData view,
    int start,
    int end,
  ) async {
    final List<Uint8List> sublists = [];

    for (int offset = start; offset + 8 <= end;) {
      final int id = view.getUint32(offset, Endian.big);
      final int size = view.getUint32(offset + 4, Endian.little);
      final int body = offset + 8;

      if ((body + size) > end) {
        throw const FormatException("ani frame overruns list");
      }

      if (id == _kIcon) {
        sublists.add(Uint8List.sublistView(view, body, body + size));
      }

      final int padding = size.isOdd ? 1 : 0;

      offset = body + size + padding;
    }

    // Decode all frames concurrently while maintaining order
    return Future.wait(sublists.map((sub) => CurDecoder.decodeFrame(sub)));
  }
}
