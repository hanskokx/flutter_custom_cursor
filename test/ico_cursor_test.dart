import "dart:io";
import "dart:typed_data";

import "package:custom_cursor/custom_cursor.dart";
import "package:flutter_test/flutter_test.dart";

/// `normal.cur` rewritten as an `.ico`: type 1, and the hotspot fields
/// holding a typical icon's colour planes (1) and bit count (32).
Uint8List _iconFromCursor(Uint8List cursor) {
  final Uint8List icon = Uint8List.fromList(cursor);
  ByteData.sublistView(icon)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint16(12, 32, Endian.little);
  return icon;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Uint8List cursorBytes = File(
    "example/assets/cursors/normal.cur",
  ).readAsBytesSync();
  final Uint8List iconBytes = _iconFromCursor(cursorBytes);

  test("icons are detected as cursors", () {
    expect(const CurDecoder().detects(iconBytes), isTrue);
    expect(
      const CurDecoder().detects(Uint8List.fromList([0, 0, 3, 0, 1, 0])),
      isFalse,
    );
  });

  testWidgets("icons decode with a top-left hotspot", (tester) async {
    final (DecodedCursor, DecodedCursor)? decoded = await tester.runAsync(
      () async => (
        await decodeCursorAsset(cursorBytes),
        await decodeCursorAsset(iconBytes),
      ),
    );
    final (DecodedCursor cursor, DecodedCursor icon) = decoded!;

    expect(icon, isA<StaticCursor>());
    expect(icon.hotspot, Offset.zero);
    expect(icon.image.width, cursor.image.width);
    expect(icon.image.height, cursor.image.height);

    final (ByteData? iconPixels, ByteData? cursorPixels) = (await tester
        .runAsync(
          () async => (
            await icon.image.toByteData(),
            await cursor.image.toByteData(),
          ),
        ))!;
    expect(
      iconPixels!.buffer.asUint8List(),
      cursorPixels!.buffer.asUint8List(),
    );
  });
}
