import "dart:async";
import "dart:ui" as ui;

import "package:flutter/foundation.dart";
import "package:flutter/gestures.dart";
import "package:flutter/services.dart";

import "cursor_asset.dart";
import "cursor_decoder.dart";
import "method_channels.dart";

/// A custom mouse cursor decoded from a cursor file (`.cur`, `.ani`, Xcursor,
/// or PNG/GIF/WebP/BMP) into a Flutter [MouseCursor].
///
/// Create one from an asset path and use it anywhere Flutter accepts a cursor:
///
/// ```dart
/// final move = CustomMouseCursor.fromAsset("assets/cursors/move.cur");
///
/// MouseRegion(cursor: move, child: child);
/// ```
///
/// Cursors decode and register lazily the first time they are shown. Two
/// cursors created from the same source compare equal, so rebuilding a widget
/// with a fresh `CustomMouseCursor.fromAsset(...)` does not re-register
/// anything.
abstract class CustomMouseCursor extends MouseCursor {
  const CustomMouseCursor();

  /// A cursor loaded from an asset bundle (the root bundle by default).
  const factory CustomMouseCursor.fromAsset(
    String assetName, {
    AssetBundle? bundle,
    String? package,
  }) = _AssetCustomMouseCursor;

  /// A cursor decoded from the [bytes] of a cursor file, in any format
  /// [decodeCursorAsset] supports.
  ///
  /// Equality is by the identity of [bytes], so keep the same list around to
  /// avoid re-decoding and re-registering.
  const factory CustomMouseCursor.memory(Uint8List bytes) =
      _MemoryCustomMouseCursor;

  /// A cursor from a raw [ui.Image] with an optional [hotspot].
  const factory CustomMouseCursor.fromImage(
    ui.Image image, {
    ui.Offset hotspot,
  }) = _ImageCustomMouseCursor;

  /// A cursor from an already-decoded [cursor].
  ///
  /// Equality is by the identity of [cursor], so keep the same instance around
  /// to avoid re-registering.
  const factory CustomMouseCursor.decoded(DecodedCursor cursor) =
      _DecodedCustomMouseCursor;

  /// Decodes the cursor source into a [DecodedCursor].
  ///
  /// Prefer [precache] to warm this up explicitly; the cursor session calls it
  /// automatically.
  Future<DecodedCursor> load();

  /// Identifies this cursor's source for equality and cache reuse.
  @protected
  Object get sourceKey;

  /// Decodes and prepares the cursor ahead of time so it is ready immediately.
  Future<void> precache() async {
    await _prepare(this);
  }

  @override
  MouseCursorSession createSession(int device) =>
      _CustomMouseCursorSession(this, device);

  @override
  String get debugDescription =>
      "${objectRuntimeType(this, "CustomMouseCursor")}($sourceKey)";

  @override
  bool operator ==(Object other) {
    return other is CustomMouseCursor &&
        other.runtimeType == runtimeType &&
        other.sourceKey == sourceKey;
  }

  @override
  int get hashCode => Object.hash(runtimeType, sourceKey);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
      StringProperty(
        "source",
        sourceKey.toString(),
        level: DiagnosticLevel.debug,
      ),
    );
  }
}

class _AssetCustomMouseCursor extends CustomMouseCursor {
  const _AssetCustomMouseCursor(this.assetName, {this.bundle, this.package});

  final String assetName;
  final AssetBundle? bundle;
  final String? package;

  String get _path =>
      package == null ? assetName : "packages/$package/$assetName";

  @override
  Object get sourceKey => (assetName, package, bundle);

  @override
  Future<DecodedCursor> load() async {
    final ByteData data = await (bundle ?? rootBundle).load(_path);
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    return decodeCursorAsset(bytes);
  }
}

class _MemoryCustomMouseCursor extends CustomMouseCursor {
  const _MemoryCustomMouseCursor(this.bytes);

  final Uint8List bytes;

  @override
  Object get sourceKey => _Identity(bytes);

  @override
  Future<DecodedCursor> load() => decodeCursorAsset(bytes);
}

class _ImageCustomMouseCursor extends CustomMouseCursor {
  const _ImageCustomMouseCursor(this.image, {this.hotspot = ui.Offset.zero});

  final ui.Image image;
  final ui.Offset hotspot;

  @override
  Object get sourceKey => (_Identity(image), hotspot);

  @override
  Future<DecodedCursor> load() =>
      SynchronousFuture(StaticCursor(image, hotspot: hotspot));
}

class _DecodedCustomMouseCursor extends CustomMouseCursor {
  const _DecodedCustomMouseCursor(this.asset);

  final DecodedCursor asset;

  @override
  Object get sourceKey => _Identity(asset);

  @override
  Future<DecodedCursor> load() => SynchronousFuture(asset);
}

/// Wraps an object so equality is by identity, for decoded assets whose value
/// equality is expensive or undefined.
@immutable
class _Identity {
  const _Identity(this.value);

  final Object value;

  @override
  bool operator ==(Object other) =>
      other is _Identity && identical(other.value, value);

  @override
  int get hashCode => identityHashCode(value);
}

/// Prepared frames, encoded once per distinct [CustomMouseCursor].
final Map<CustomMouseCursor, Future<_PreparedCursor>> _preparedCursors = {};

Future<_PreparedCursor> _prepare(CustomMouseCursor cursor) async {
  final Future<_PreparedCursor>? existing = _preparedCursors[cursor];

  if (existing != null) {
    return existing;
  }

  final Future<_PreparedCursor> future = _load(cursor);
  _preparedCursors[cursor] = future;

  try {
    return await future;
  } on Object {
    _preparedCursors.removeWhere((key, _) => key == cursor);
    rethrow;
  }
}

Future<_PreparedCursor> _load(CustomMouseCursor cursor) async {
  final DecodedCursor asset = await cursor.load();
  return _prepareAsset(asset);
}

Future<_PreparedCursor> _prepareAsset(DecodedCursor asset) async {
  final List<_PreparedFrame> frames = [];

  switch (asset) {
    case StaticCursor(:final image, :final hotspot):
      frames.add(
        _PreparedFrame(png: await _encodePng(image), hotspot: hotspot),
      );
    case AnimatedCursor(frames: final animationFrames):
      for (final CursorFrame frame in animationFrames) {
        frames.add(
          _PreparedFrame(
            png: await _encodePng(frame.image),
            hotspot: frame.hotspot,
            duration: frame.duration,
          ),
        );
      }
  }
  return _PreparedCursor(frames: frames);
}

Future<Uint8List> _encodePng(ui.Image image) async {
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);

  if (data == null) {
    throw StateError("could not encode cursor image as PNG");
  }

  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

@immutable
class _PreparedCursor {
  const _PreparedCursor({required this.frames});

  final List<_PreparedFrame> frames;
}

@immutable
class _PreparedFrame {
  const _PreparedFrame({
    required this.png,
    required this.hotspot,
    this.duration = Duration.zero,
  });

  final Uint8List png;
  final ui.Offset hotspot;
  final Duration duration;
}

class _CustomMouseCursorSession extends MouseCursorSession {
  _CustomMouseCursorSession(CustomMouseCursor super.cursor, super.device);

  static _CustomMouseCursorSession? _current;

  static bool _routeInstalled = false;

  Timer? _timer;
  int _index = 0;

  @override
  CustomMouseCursor get cursor => super.cursor as CustomMouseCursor;

  /// Flutter forgets a device's cursor session without disposing it when the
  /// pointer leaves the view, so reset the cursor then.
  static void _installRemovalRoute() {
    if (_routeInstalled) return;
    _routeInstalled = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      final current = _current;
      if (event is PointerRemovedEvent && current?.device == event.device) {
        _current = null;
        current?._timer?.cancel();
        current?._timer = null;
        unawaited(_reset());
      }
    });
  }

  @override
  Future<void> activate() async {
    _installRemovalRoute();
    _current = this;

    final _PreparedCursor prepared;
    try {
      prepared = await _prepare(cursor);
    } on Object catch (error) {
      debugPrint("custom_cursor: failed to load $cursor: $error");
      return;
    }

    if (!identical(_current, this)) return;

    _timer?.cancel();
    _index = 0;
    await _show(prepared);

    if (prepared.frames.length > 1) {
      _schedule(prepared);
    }
  }

  Future<void> _show(_PreparedCursor prepared) async {
    final frame = prepared.frames[_index];
    try {
      await PackageChannels.mouseCursor.invokeMethod<void>(
        "activateCustomCursor",
        <String, dynamic>{
          "device": device,
          "image": frame.png,
          "hotspotX": frame.hotspot.dx,
          "hotspotY": frame.hotspot.dy,
        },
      );
    } on PlatformException {
      // Best-effort: the platform may not be ready yet.
    }
  }

  void _schedule(_PreparedCursor prepared) {
    _timer?.cancel();
    final Duration delay = prepared.frames[_index].duration;

    _timer = Timer(delay > Duration.zero ? delay : _defaultDelay, () {
      if (!identical(_current, this)) return;
      _index = (_index + 1) % prepared.frames.length;
      unawaited(_show(prepared));
      _schedule(prepared);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (!identical(_current, this)) return;
    _current = null;
    // Stop re-asserting this cursor without changing what is on screen, so
    // whatever Flutter activates next wins.
    unawaited(_clear());
  }

  /// Stops the platform from forcing this cursor, leaving the visible cursor
  /// untouched.
  static Future<void> _clear() async {
    try {
      await PackageChannels.mouseCursor.invokeMethod<void>("clearCursor");
    } on PlatformException {
      // Best-effort.
    }
  }

  /// Restores the system cursor after the pointer leaves the view.
  static Future<void> _reset() async {
    // Yield first so a session activated in the same event turn can claim the
    // cursor; skip the reset if it did.
    await Future<void>.value();
    if (_current != null) return;
    try {
      await PackageChannels.mouseCursor.invokeMethod<void>("resetCursor");
    } on PlatformException {
      // Best-effort.
    }
  }
}

const Duration _defaultDelay = Duration(milliseconds: 16);
