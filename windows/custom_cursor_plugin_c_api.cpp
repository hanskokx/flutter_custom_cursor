// Copyright (c) 2026 Hans Kokx.
// SPDX-License-Identifier: MIT

#include "include/custom_cursor/custom_cursor_plugin.h"

#include <flutter/plugin_registrar_windows.h>

void CustomCursorPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter::PluginRegistrarWindows* windows_registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  custom_cursor::CustomCursorPlugin::RegisterWithRegistrar(windows_registrar);
}