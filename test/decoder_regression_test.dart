import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:custom_cursor/custom_cursor.dart";
import "package:flutter_test/flutter_test.dart";

/// Regression coverage for the curated `broken-cursors` corpus.
///
/// The remaining fixtures are classic monochrome Windows cursors whose shapes
/// were encoded as "screen invert" pixels (an all-set AND mask with the XOR
/// mask carving out the glyph). The decoder used to drop those pixels,
/// producing fully transparent (invisible) cursors; they become visible once
/// the invert pixels are rendered opaque.
void main() {
  Uint8List bytesOf(String path) {
    final file = File(path);
    return file.existsSync()
        ? file.readAsBytesSync()
        : fail("missing fixture $path");
  }

  Future<int> opaqueCount(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    var opaque = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i + 3] != 0) opaque++;
    }
    return opaque;
  }

  testWidgets("reference cursors decode with visible pixels", (tester) async {
    for (final name in ["normal", "move", "resize"]) {
      final bytes = bytesOf("example/assets/cursors/$name.cur");
      final asset = await tester.runAsync(() => decodeCursorAsset(bytes));
      final opaque = await tester.runAsync(() => opaqueCount(asset!.image));
      expect(opaque, greaterThan(0), reason: name);
    }
  });
}
