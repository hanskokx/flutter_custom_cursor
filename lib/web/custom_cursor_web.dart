// Copyright (c) 2026 Hans Kokx.
// SPDX-License-Identifier: MIT

// ignore_for_file: public_member_api_docs

import "dart:async";
import "dart:convert";
import "dart:js_interop";

import "package:flutter/services.dart";
import "package:flutter_web_plugins/flutter_web_plugins.dart";
import "package:web/web.dart" as web;

/// Plugin method channel name.
const _kChannel = "custom_cursor";

/// Host element selectors tried in order to find the Flutter view container.
const _kHostSelectors = [
  "flt-glass-pane",
  "flutter-view",
  "flt-scene-host",
  "body",
];

// Host element(s) that carry the cursor style.
final List<web.HTMLElement> _hosts = [];

// Whether the browser accepts `cursor: image-set(...)`. Detected by assigning
// a probe value and checking it round-trips: like any invalid `cursor`
// declaration it reads back as an empty string. Safari (among others) does
// not support image-set in `cursor`, so fall back to the plain URL only.
final bool _imageSetCursorSupported = _probeImageSetCursor();

bool _probeImageSetCursor() {
  final probe = web.HTMLDivElement();
  probe.style.cursor = "image-set(url('x') 1x) 0 0, auto";
  return probe.style.cursor.isNotEmpty;
}

void _initHosts() {
  if (_hosts.isNotEmpty) return;
  for (final selector in _kHostSelectors) {
    final el = web.document.querySelector(selector);
    if (el != null) _hosts.add(el as web.HTMLElement);
  }
  final body = web.document.body;
  if (body != null && !_hosts.contains(body)) _hosts.add(body);
}

/// Web platform implementation of the custom_cursor plugin.
///
/// Each cursor is applied as a CSS `cursor: url(...) x y, auto` value on
/// the Flutter view's host element(s), so the browser draws it natively.
/// A hi-res (2x) variant is baked in via CSS `image-set` when possible,
/// giving crisp cursors on HiDPI displays.
class CustomCursorWeb {
  CustomCursorWeb._();

  static void registerWith(Registrar registrar) {
    // Pass the registrar as the messenger: on the web, plugin registration
    // happens during engine bootstrap, before WidgetsFlutterBinding
    // .ensureInitialized has run, so the default messenger is not yet
    // available.
    final MethodChannel channel = MethodChannel(
      _kChannel,
      const StandardMethodCodec(),
      registrar,
    );
    channel.setMethodCallHandler(_handleMethodCall);
  }

  // ----------------------------------------------------------------------
  // Method call dispatch — matches the native channel contract.
  // ----------------------------------------------------------------------

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case "activateCustomCursor":
        return _handleActivateCustomCursor(call);
      case "clearCursor":
        return _handleClearCursor();
      case "resetCursor":
        return _handleResetCursor();
      default:
        throw Exception("Method ${call.method} not implemented");
    }
  }

  // ----------------------------------------------------------------------
  // activateCustomCursor — apply cursor
  // ----------------------------------------------------------------------

  static Future<void> _handleActivateCustomCursor(MethodCall call) async {
    final args = call.arguments as Map<dynamic, dynamic>;
    final pngBytes = args["image"] as Uint8List;
    final hotX = (args["hotspotX"] as num).toInt();
    final hotY = (args["hotspotY"] as num).toInt();

    final dataUrl = "data:image/png;base64,${base64.encode(pngBytes)}";

    // Try to create a hi‑res (2x) variant for crisp HiDPI rendering.
    String? hiDataUrl;
    try {
      final img = web.HTMLImageElement()
        ..decoding = "sync"
        ..src = dataUrl;
      await img.decode().toDart.catchError((_) => null);
      final w = img.naturalWidth;
      final h = img.naturalHeight;
      if (w > 0 && h > 0) {
        final canvas = web.HTMLCanvasElement()
          ..width = w * 2
          ..height = h * 2;
        final ctx = canvas.getContext("2d") as web.CanvasRenderingContext2D;
        ctx.drawImage(
          img,
          0,
          0,
          w.toDouble(),
          h.toDouble(),
          0,
          0,
          canvas.width.toDouble(),
          canvas.height.toDouble(),
        );
        final hiData = canvas.toDataURL("image/png");
        hiDataUrl = hiData;
      }
    } catch (_) {
      // Image decoding/resizing failed; proceed without hi‑res variant.
    }

    _applyCursorCSS(dataUrl, hotX, hotY, hiDataUrl);
  }

  // ----------------------------------------------------------------------
  // clearCursor / resetCursor — stop applying the custom cursor.
  // ----------------------------------------------------------------------

  static Future<void> _handleClearCursor() async {
    _initHosts();
    for (final host in _hosts) {
      host.style.cursor = "";
    }
  }

  // Clearing the `cursor` style restores the browser's own cursor, so a reset
  // is the same as a clear.
  static Future<void> _handleResetCursor() => _handleClearCursor();

  static void _applyCursorCSS(
    String dataUrl,
    int hotX,
    int hotY,
    String? hiDataUrl,
  ) {
    _initHosts();
    final String rawCursor;
    if (_imageSetCursorSupported && hiDataUrl != null) {
      rawCursor =
          "url($dataUrl) $hotX $hotY, "
          "image-set(url($dataUrl) 1x, url($hiDataUrl) 2x) "
          "$hotX $hotY, auto";
    } else {
      rawCursor = "url($dataUrl) $hotX $hotY, auto";
    }
    for (final host in _hosts) {
      host.style.cursor = rawCursor;
    }
  }
}
