import "package:flutter/services.dart";

abstract final class PackageChannels {
  static const MethodChannel mouseCursor = OptionalMethodChannel(
    "custom_cursor",
  );
}
