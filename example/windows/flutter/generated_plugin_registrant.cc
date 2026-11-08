//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <custom_cursor/custom_cursor_plugin.h>
#include <desktop_drop/desktop_drop_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  CustomCursorPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("CustomCursorPlugin"));
  DesktopDropPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DesktopDropPlugin"));
}
