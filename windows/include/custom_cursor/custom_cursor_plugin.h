// Copyright (c) 2026 Hans Kokx.
// SPDX-License-Identifier: MIT

#ifndef CUSTOM_CURSOR_PLUGIN_H
#define CUSTOM_CURSOR_PLUGIN_H

#include <windows.h>

#include <flutter_plugin_registrar.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void CustomCursorPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#include <memory>

namespace custom_cursor {

class CustomCursorPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  CustomCursorPlugin(flutter::PluginRegistrarWindows* registrar);
  ~CustomCursorPlugin();

  CustomCursorPlugin(const CustomCursorPlugin&) = delete;
  CustomCursorPlugin& operator=(const CustomCursorPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::PluginRegistrarWindows* registrar_;
  HCURSOR cursor_;
  ULONG_PTR gdiplus_token_;
};

}  // namespace custom_cursor

#endif  // CUSTOM_CURSOR_PLUGIN_H
