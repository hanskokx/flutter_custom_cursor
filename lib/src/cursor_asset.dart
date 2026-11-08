import "dart:ui";

/// A decoded cursor: either a single [StaticCursor] or an [AnimatedCursor].
sealed class DecodedCursor {
  const DecodedCursor(this.image, {this.hotspot = Offset.zero});

  /// The image shown first: the only image of a [StaticCursor], or the first
  /// frame of an [AnimatedCursor].
  final Image image;

  /// The hotspot within [image], in pixels.
  final Offset hotspot;
}

/// A cursor that shows a single image.
final class StaticCursor extends DecodedCursor {
  const StaticCursor(super.image, {super.hotspot});
}

/// A cursor that cycles through [frames] while shown.
final class AnimatedCursor extends DecodedCursor {
  factory AnimatedCursor({required List<CursorFrame> frames}) {
    if (frames.isEmpty) {
      throw ArgumentError.value(frames, "frames", "must not be empty");
    }

    final CursorFrame first = frames.first;

    return AnimatedCursor._(
      first.image,
      hotspot: first.hotspot,
      frames: List<CursorFrame>.unmodifiable(frames),
    );
  }

  const AnimatedCursor._(super.image, {required this.frames, super.hotspot});

  /// The animation's frames in playback order; frame 0 is [image] at
  /// [hotspot].
  final List<CursorFrame> frames;
}

/// One frame of an [AnimatedCursor].
final class CursorFrame {
  const CursorFrame(
    this.image, {
    required this.duration,
    this.hotspot = Offset.zero,
  });

  /// The frame's image.
  final Image image;

  /// The hotspot within [image], in pixels.
  final Offset hotspot;

  /// How long the frame is shown before advancing to the next one.
  final Duration duration;
}
