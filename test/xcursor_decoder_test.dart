import "dart:typed_data";

import "package:custom_cursor/custom_cursor.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

/// Builds an Xcursor file with one square image chunk per entry of [sizes]
/// (nominal size == pixel size). Repeated sizes become animation frames.
Uint8List _xcursor(List<int> sizes) {
  const int headerSize = 16;
  final int tocEnd = headerSize + sizes.length * 12;
  final List<int> offsets = [];
  int position = tocEnd;
  for (final int size in sizes) {
    offsets.add(position);
    position += 36 + size * size * 4;
  }

  final ByteData view = ByteData(position)
    ..setUint32(0, 0x58637572)
    ..setUint32(4, headerSize, Endian.little)
    ..setUint32(8, 0x10000, Endian.little)
    ..setUint32(12, sizes.length, Endian.little);

  for (int i = 0; i < sizes.length; i++) {
    final int toc = headerSize + i * 12;
    final int at = offsets[i];
    final int size = sizes[i];
    view
      ..setUint32(toc, 0xfffd0002, Endian.little)
      ..setUint32(toc + 4, size, Endian.little)
      ..setUint32(toc + 8, at, Endian.little)
      ..setUint32(at, 36, Endian.little)
      ..setUint32(at + 4, 0xfffd0002, Endian.little)
      ..setUint32(at + 8, size, Endian.little)
      ..setUint32(at + 12, 1, Endian.little)
      ..setUint32(at + 16, size, Endian.little)
      ..setUint32(at + 20, size, Endian.little)
      ..setUint32(at + 32, 50, Endian.little);
  }

  return view.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<int> decodedWidth(
    WidgetTester tester,
    Uint8List bytes, {
    int? size,
  }) async {
    final DecodedCursor? cursor = await tester.runAsync(
      () => LinuxXcursorDecoder(size: size).decode(bytes),
    );
    return cursor!.image.width;
  }

  testWidgets("uses the variant closest to the requested size", (
    tester,
  ) async {
    final Uint8List bytes = _xcursor([24, 32, 48, 64]);
    expect(await decodedWidth(tester, bytes, size: 24), 24);
    expect(await decodedWidth(tester, bytes, size: 30), 32);
    expect(await decodedWidth(tester, bytes, size: 40), 48); // tie: larger
    expect(await decodedWidth(tester, bytes, size: 200), 64);
    expect(await decodedWidth(tester, bytes, size: 8), 24);
  });

  testWidgets("falls back to the default size without a platform answer", (
    tester,
  ) async {
    expect(await decodedWidth(tester, _xcursor([48, 24, 32])), 24);
  });

  testWidgets("asks the platform for its cursor size", (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel("custom_cursor"),
      (call) async => call.method == "systemCursorSize" ? 48 : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel("custom_cursor"),
        null,
      ),
    );
    expect(await decodedWidth(tester, _xcursor([24, 32, 48, 64])), 48);
  });

  testWidgets("animates the frames of the chosen size only", (tester) async {
    final DecodedCursor? cursor = await tester.runAsync(
      () => const LinuxXcursorDecoder(
        size: 32,
      ).decode(_xcursor([24, 24, 24, 32, 32, 48, 48, 48, 48])),
    );
    expect(cursor, isA<AnimatedCursor>());
    final AnimatedCursor animated = cursor! as AnimatedCursor;
    expect(animated.frames, hasLength(2));
    expect(animated.image.width, 32);
    expect(animated.frames.first.duration, const Duration(milliseconds: 50));
  });

  testWidgets("a single image at the chosen size is static", (tester) async {
    final DecodedCursor? cursor = await tester.runAsync(
      () => const LinuxXcursorDecoder(
        size: 24,
      ).decode(_xcursor([24, 48, 48])),
    );
    expect(cursor, isA<StaticCursor>());
  });
}
