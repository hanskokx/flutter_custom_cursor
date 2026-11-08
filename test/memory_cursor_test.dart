import "dart:io";
import "dart:typed_data";

import "package:custom_cursor/custom_cursor.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Uint8List bytes = File(
    "example/assets/cursors/normal.cur",
  ).readAsBytesSync();

  testWidgets("memory cursors decode their bytes", (tester) async {
    final DecodedCursor? asset = await tester.runAsync(
      () => CustomMouseCursor.memory(bytes).load(),
    );
    expect(asset, isA<StaticCursor>());
    expect(asset!.image.width, greaterThan(0));
  });

  test("memory cursors are equal only for the same byte list", () {
    expect(CustomMouseCursor.memory(bytes), CustomMouseCursor.memory(bytes));
    expect(
      CustomMouseCursor.memory(bytes).hashCode,
      CustomMouseCursor.memory(bytes).hashCode,
    );
    expect(
      CustomMouseCursor.memory(bytes),
      isNot(CustomMouseCursor.memory(Uint8List.fromList(bytes))),
    );
  });

  testWidgets("memory cursors reject unsupported data", (tester) async {
    final Object? error = await tester.runAsync<Object?>(() async {
      try {
        await CustomMouseCursor.memory(Uint8List.fromList([1, 2, 3])).load();
        return null;
      } on FormatException catch (error) {
        return error;
      }
    });
    expect(error, isA<FormatException>());
  });
}
