import "dart:async";
import "dart:io";
import "dart:ui" as ui;

import "package:custom_cursor/custom_cursor.dart";
import "package:desktop_drop/desktop_drop.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart" show rootBundle;

void main() {
  runApp(const CursorExampleApp());
}

/// The example app: loads the bundled `.cur` files, decodes them, and shows a
/// grid of cards previewing each pointer. Hovering a card switches the
/// platform cursor to that pointer. Dropping any supported file (`.cur`,
/// `.ani`, Linux `.cursor`, PNG, GIF, ...) replaces the list; a reset
/// button restores the defaults.
class CursorExampleApp extends StatelessWidget {
  const CursorExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "custom_cursor example",
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const CursorGridScreen(),
    );
  }
}

class CursorGridScreen extends StatefulWidget {
  const CursorGridScreen({super.key});

  @override
  State<CursorGridScreen> createState() => _CursorGridScreenState();
}

class _CursorGridScreenState extends State<CursorGridScreen> {
  static const _defaultAssets = <String>["normal", "move", "resize"];

  Map<String, DecodedCursor> _cursors = {};
  bool _loading = true;
  String? _error;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    await _loadDefaults();
  }

  /// Loads and decodes the bundled `.cur` assets concurrently, populating [_cursors].
  Future<void> _loadDefaults() async {
    try {
      final entries = await Future.wait(
        _defaultAssets.map((stem) async {
          final data = await rootBundle.load("assets/cursors/$stem.cur");
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          final asset = await decodeCursorAsset(bytes);
          return MapEntry(stem, asset);
        }),
      );

      if (!mounted) return;
      setState(() {
        _cursors = Map.fromEntries(entries);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool get _deviated {
    final defaultKeys = _defaultAssets.toSet();
    return _cursors.keys.toSet() != defaultKeys;
  }

  /// Sniffs and decodes every dropped file concurrently, replacing the
  /// whole cursor set.
  Future<void> _onDrop(DropDoneDetails detail) async {
    final loaded = <String, DecodedCursor>{};

    Future<void> loadFile(
      String name,
      Future<Uint8List> Function() read,
    ) async {
      try {
        final bytes = await read();
        final asset = await decodeCursorAsset(bytes);
        final key = name.split(".").first;
        loaded[key] = asset;
      } on FormatException {
        // Skip unsupported or malformed files.
      } on FileSystemException {
        // Skip files that cannot be read.
      }
    }

    Future<void> loadItem(DropItem item) async {
      final bookmark = item.extraAppleBookmark;
      final hasScopedAccess =
          bookmark != null &&
          bookmark.isNotEmpty &&
          await DesktopDrop.instance.startAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
      try {
        final isDirectory =
            item is DropItemDirectory ||
            (!kIsWeb &&
                await FileSystemEntity.type(item.path) ==
                    FileSystemEntityType.directory);

        // Fail-fast guard: if it's a file, load it immediately and return
        if (!isDirectory) {
          await loadFile(item.name, item.readAsBytes);
          return;
        }

        if (item is DropItemDirectory && item.children.isNotEmpty) {
          for (final child in item.children) {
            await loadItem(child);
          }
          return;
        }

        if (!kIsWeb) {
          try {
            await for (final entry in Directory(item.path).list(
              recursive: true,
              followLinks: false,
            )) {
              if (entry is File) {
                final name = entry.uri.pathSegments.last;
                await loadFile(name, entry.readAsBytes);
              }
            }
          } on FileSystemException {
            // Skip directories that cannot be read.
          }
        }
      } finally {
        if (hasScopedAccess) {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        }
      }
    }

    // Process all dropped items concurrently
    await Future.wait(detail.files.map((item) => loadItem(item)));

    if (loaded.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _cursors = loaded;
      _dragging = false;
    });
  }

  Future<void> _reset() async {
    setState(() {
      _cursors = {};
      _loading = true;
    });
    await _loadDefaults();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("custom_cursor example"),
        actions: [
          if (_deviated)
            IconButton(
              tooltip: "Reset to defaults",
              icon: const Icon(Icons.refresh),
              onPressed: () => unawaited(_reset()),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text("Failed to load cursors: $_error"))
          : Column(
              children: [
                _DropRegion(
                  dragging: _dragging,
                  onDragEntered: (_) => setState(() => _dragging = true),
                  onDragExited: (_) => setState(() => _dragging = false),
                  onDragDone: _onDrop,
                ),
                Expanded(
                  child: GridView.count(
                    padding: const EdgeInsets.all(24),
                    crossAxisCount: 3,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    children: [
                      for (final entry in _cursors.entries)
                        CursorCard(name: entry.key, asset: entry.value),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// A tappable drop region that accepts any supported cursor/image file.
class _DropRegion extends StatelessWidget {
  const _DropRegion({
    required this.dragging,
    required this.onDragEntered,
    required this.onDragExited,
    required this.onDragDone,
  });

  final bool dragging;
  final ValueChanged<DropEventDetails> onDragEntered;
  final ValueChanged<DropEventDetails> onDragExited;
  final ValueChanged<DropDoneDetails> onDragDone;

  bool get useDropTarget =>
      kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: DropTarget(
        enable: useDropTarget,
        onDragEntered: onDragEntered,
        onDragExited: onDragExited,
        onDragDone: onDragDone,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dragging
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: dragging
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: dragging ? 2 : 1,
            ),
          ),
          child: Text(
            useDropTarget
                ? dragging
                      ? "Release to load cursors"
                      : "Drop cursor/image files here (cur, ani, Xcursor...)"
                : "Tap to load cursor/image files (cur, ani, Xcursor...)",
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// A card that previews [asset] beneath [name], switching the platform cursor
/// to it while being hovered, with an optional remove affordance.
class CursorCard extends StatefulWidget {
  const CursorCard({required this.name, required this.asset, super.key});

  final String name;
  final DecodedCursor asset;

  @override
  State<CursorCard> createState() => _CursorCardState();
}

class _CursorCardState extends State<CursorCard> {
  bool _hovering = false;

  late CustomMouseCursor _cursor = CustomMouseCursor.decoded(widget.asset);

  @override
  void didUpdateWidget(CursorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.asset, widget.asset)) {
      _cursor = CustomMouseCursor.decoded(widget.asset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: _cursor,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovering
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovering
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: _hovering ? 2 : 1,
          ),
        ),
        child: Column(
          spacing: 12,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: AssetPreview(asset: widget.asset)),
            Text(widget.name, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// Renders a [DecodedCursor], animating an animated cursor's frames.
class AssetPreview extends StatelessWidget {
  const AssetPreview({required this.asset, super.key});

  final DecodedCursor asset;

  @override
  Widget build(BuildContext context) {
    return switch (asset) {
      StaticCursor(:final image) => _CursorPreview(image: image),
      AnimatedCursor(:final frames) => _AnimatedCursorPreview(frames: frames),
    };
  }
}

/// Cycles through [frames], honoring each frame's duration.
class _AnimatedCursorPreview extends StatefulWidget {
  const _AnimatedCursorPreview({required this.frames});

  final List<CursorFrame> frames;

  @override
  State<_AnimatedCursorPreview> createState() => _AnimatedCursorPreviewState();
}

class _AnimatedCursorPreviewState extends State<_AnimatedCursorPreview> {
  late int _index;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _index = 0;
    if (widget.frames.length > 1) {
      _schedule();
    }
  }

  @override
  void didUpdateWidget(_AnimatedCursorPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.frames, widget.frames)) return;
    _timer?.cancel();
    _index = 0;
    if (widget.frames.length > 1) {
      _schedule();
    }
  }

  void _schedule() {
    final duration = widget.frames[_index].duration;
    _timer = Timer(duration > Duration.zero ? duration : _defaultDelay, () {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.frames.length;
      });
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CursorPreview(image: widget.frames[_index].image);
  }
}

const Duration _defaultDelay = Duration(milliseconds: 16);

/// Draws [image] centered in the card without clipping it.
class _CursorPreview extends StatelessWidget {
  const _CursorPreview({required this.image});

  final ui.Image image;

  @override
  Widget build(BuildContext context) {
    final width = image.width.toDouble();
    final height = image.height.toDouble();
    return Center(
      child: RawImage(
        image: image,
        width: width,
        height: height,
      ),
    );
  }
}
