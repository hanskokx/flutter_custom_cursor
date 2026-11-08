import "dart:convert";
import "dart:ui" as ui;

import "package:custom_cursor/custom_cursor.dart";
import "package:flutter/gestures.dart";
import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";

Future<ui.Image> _image(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(
    recorder,
  ).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 4), ui.Paint()..color = color);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(4, 4);
  } finally {
    picture.dispose();
  }
}

Future<DecodedCursor> _asset(ui.Color color) async =>
    StaticCursor(await _image(color));

Future<AnimatedCursor> _animatedAsset() async {
  const duration = Duration(milliseconds: 10);
  return AnimatedCursor(
    frames: [
      CursorFrame(await _image(const ui.Color(0xFFFFFFFF)), duration: duration),
      CursorFrame(await _image(const ui.Color(0xFF000000)), duration: duration),
    ],
  );
}

void main() {
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel("custom_cursor"), (
          call,
        ) async {
          final args = call.arguments;
          if (args is Map && args["image"] is Uint8List) {
            calls.add(
              "${call.method}:${base64.encode(args["image"] as Uint8List)}",
            );
          } else {
            calls.add(call.method);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel("custom_cursor"), null);
  });

  testWidgets("moving from a custom cursor region back to the default region "
      "switches the cursor back", (tester) async {
    late CustomMouseCursor normal;
    late CustomMouseCursor slider;
    await tester.runAsync(() async {
      normal = CustomMouseCursor.decoded(
        await _asset(const ui.Color(0xFFFFFFFF)),
      );
      slider = CustomMouseCursor.decoded(
        await _asset(const ui.Color(0xFF000000)),
      );
      await normal.precache();
      await slider.precache();
    });
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MouseRegion(
          cursor: normal,
          child: Align(
            alignment: Alignment.topLeft,
            child: MouseRegion(
              cursor: slider,
              child: const SizedBox(width: 50, height: 50),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 200));
    await tester.pump();
    await mouse.moveTo(const Offset(20, 20));
    await tester.pump();
    await mouse.moveTo(const Offset(300, 300));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );

    final activations = calls
        .where((call) => call.startsWith("activateCustomCursor"))
        .toList();
    expect(activations.length, greaterThanOrEqualTo(3), reason: calls.join());
    expect(
      activations.last,
      activations.first,
      reason: "last cursor set should be the default region's",
    );
  });

  testWidgets("animated cursors advance through their frames", (tester) async {
    late CustomMouseCursor cursor;
    await tester.runAsync(() async {
      cursor = CustomMouseCursor.decoded(await _animatedAsset());
      await cursor.precache();
    });
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MouseRegion(
          cursor: cursor,
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(50, 50));
    await tester.pump();
    await tester.pump();
    final first = calls.last;

    await tester.pump(const Duration(milliseconds: 12));
    await tester.pump();
    expect(calls.last, isNot(first));

    await tester.pump(const Duration(milliseconds: 12));
    await tester.pump();
    expect(calls.last, first);
  });
}
