import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:custom_cursor/custom_cursor.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("detection", () {
    test("Windows .cur", () {
      final bytes = Uint8List.fromList([0, 0, 2, 0, 1, 0]);
      expect(const CurDecoder().detects(bytes), isTrue);
      expect(const AniDecoder().detects(bytes), isFalse);
    });

    test("Windows .ani", () {
      final bytes = Uint8List(12)
        ..setRange(0, 4, utf8.encode("RIFF"))
        ..setRange(8, 12, utf8.encode("ACON"));
      expect(const AniDecoder().detects(bytes), isTrue);
      expect(const CurDecoder().detects(bytes), isFalse);
    });

    test("Linux Xcursor", () {
      final bytes = Uint8List(16)..setRange(0, 4, utf8.encode("Xcur"));
      expect(const LinuxXcursorDecoder().detects(bytes), isTrue);
      expect(const CurDecoder().detects(bytes), isFalse);
    });

    test("native raster images", () {
      const decoder = NativeImageDecoder();
      expect(
        decoder.detects(
          Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]),
        ),
        isTrue,
      );
      expect(decoder.detects(Uint8List.fromList([0xff, 0xd8, 0xff])), isTrue);
      expect(
        decoder.detects(Uint8List.fromList(utf8.encode("GIF89a"))),
        isTrue,
      );
      expect(
        decoder.detects(
          Uint8List.fromList([
            ...utf8.encode("RIFF"),
            0,
            0,
            0,
            0,
            ...utf8.encode("WEBP"),
          ]),
        ),
        isTrue,
      );
      expect(decoder.detects(Uint8List.fromList(utf8.encode("BM"))), isTrue);
    });
  });

  testWidgets("the first matching decoder handles the data", (tester) async {
    final error = await tester.runAsync(() async {
      try {
        await decodeCursorAsset(Uint8List.fromList([0, 0, 2, 0, 0, 0]));
        return null;
      } on FormatException catch (error) {
        return error;
      }
    });
    expect(error?.message, contains("cursor has no images"));
  });

  testWidgets("reference .cur files decode to static cursors", (tester) async {
    for (final name in ["normal", "move", "resize"]) {
      final bytes = File("example/assets/cursors/$name.cur").readAsBytesSync();
      final asset = await tester.runAsync(() => decodeCursorAsset(bytes));
      expect(asset, isA<StaticCursor>(), reason: name);
      final cursor = asset! as StaticCursor;
      expect(cursor.image.width, greaterThan(0), reason: name);
      expect(cursor.image.height, greaterThan(0), reason: name);
    }
  });
}
