import "dart:ui" as ui;

import "package:custom_cursor/custom_cursor.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("AnimatedCursor rejects empty frames", () {
    expect(() => AnimatedCursor(frames: []), throwsArgumentError);
  });

  testWidgets("assets expose their first image and hotspot", (tester) async {
    final image = (await tester.runAsync(_image))!;
    const hotspot = ui.Offset(1, 2);

    final staticCursor = StaticCursor(image, hotspot: hotspot);
    expect(staticCursor.image, same(image));
    expect(staticCursor.hotspot, hotspot);

    final frame = CursorFrame(
      image,
      hotspot: const ui.Offset(3, 4),
      duration: const Duration(milliseconds: 10),
    );
    final animated = AnimatedCursor(frames: [frame]);
    expect(animated.image, same(image));
    expect(animated.hotspot, const ui.Offset(3, 4));
    expect(animated.frames.single, same(frame));
  });
}

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 4),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(4, 4);
  } finally {
    picture.dispose();
  }
}
