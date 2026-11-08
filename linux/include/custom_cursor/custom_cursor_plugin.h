// Copyright (c) 2026 Hans Kokx.
// SPDX-License-Identifier: MIT

#ifndef CUSTOM_CURSOR_PLUGIN_H
#define CUSTOM_CURSOR_PLUGIN_H

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

G_DECLARE_FINAL_TYPE(CustomCursorPlugin, custom_cursor_plugin, CUSTOM,
                     CURSOR_PLUGIN, GObject)

FLUTTER_PLUGIN_EXPORT void custom_cursor_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // CUSTOM_CURSOR_PLUGIN_H