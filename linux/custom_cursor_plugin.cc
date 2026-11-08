// Copyright (c) 2026 Hans Kokx.
// SPDX-License-Identifier: MIT

#include "include/custom_cursor/custom_cursor_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gdk/gdk.h>
#include <gtk/gtk.h>

#include <cstring>

struct _CustomCursorPlugin
{
  GObject parent_instance;
  FlPluginRegistrar *registrar;
  GdkCursor *active_cursor;
};

G_DEFINE_TYPE(CustomCursorPlugin, custom_cursor_plugin,
              g_object_get_type())

static GdkWindow *get_gdk_window(CustomCursorPlugin *self)
{
  if (self->registrar == nullptr)
    return nullptr;
  FlView *view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr)
    return nullptr;
  GtkWidget *toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  return gtk_widget_get_window(toplevel);
}

static double value_to_double(FlValue *v, double fallback)
{
  if (v == nullptr)
    return fallback;
  switch (fl_value_get_type(v))
  {
  case FL_VALUE_TYPE_INT:
    return static_cast<double>(fl_value_get_int(v));
  case FL_VALUE_TYPE_FLOAT:
    return fl_value_get_float(v);
  default:
    return fallback;
  }
}

static void reset_to_default_cursor(CustomCursorPlugin *self)
{
  GdkWindow *window = get_gdk_window(self);
  if (window != nullptr)
    gdk_window_set_cursor(window, nullptr);
}

static FlMethodResponse *activate_custom_cursor(CustomCursorPlugin *self,
                                                FlValue *args)
{
  FlValue *image_v = fl_value_lookup_string(args, "image");
  if (image_v == nullptr ||
      fl_value_get_type(image_v) != FL_VALUE_TYPE_UINT8_LIST)
  {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("bad_args", "activateCustomCursor", nullptr));
  }
  const uint8_t *bytes = fl_value_get_uint8_list(image_v);
  size_t length = fl_value_get_length(image_v);

  g_autoptr(GError) error = nullptr;
  g_autoptr(GInputStream) stream =
      g_memory_input_stream_new_from_data(bytes, static_cast<gssize>(length), nullptr);
  g_autoptr(GdkPixbuf) raw =
      gdk_pixbuf_new_from_stream(stream, nullptr, &error);
  if (raw == nullptr)
  {
    return FL_METHOD_RESPONSE(
        fl_method_error_response_new("decode", "bad png", nullptr));
  }

  const int original_width = gdk_pixbuf_get_width(raw);
  const int original_height = gdk_pixbuf_get_height(raw);
  // Scale down proportionally to fit the 128px limit.
  const int longest =
      original_width > original_height ? original_width : original_height;
  const double scale = longest > 128 ? 128.0 / longest : 1.0;
  int width = static_cast<int>(original_width * scale + 0.5);
  int height = static_cast<int>(original_height * scale + 0.5);
  if (width < 1)
    width = 1;
  if (height < 1)
    height = 1;

  GdkPixbuf *pixbuf = raw;
  g_autoptr(GdkPixbuf) scaled = nullptr;
  if (width != original_width || height != original_height)
  {
    scaled = gdk_pixbuf_scale_simple(raw, width, height, GDK_INTERP_BILINEAR);
    if (scaled != nullptr)
    {
      pixbuf = scaled;
    }
  }

  double hot_x =
      value_to_double(fl_value_lookup_string(args, "hotspotX"), 0.0) * scale;
  double hot_y =
      value_to_double(fl_value_lookup_string(args, "hotspotY"), 0.0) * scale;
  if (hot_x < 0)
    hot_x = 0;
  else if (hot_x > width - 1)
    hot_x = width - 1;
  if (hot_y < 0)
    hot_y = 0;
  else if (hot_y > height - 1)
    hot_y = height - 1;

  cairo_surface_t *surface =
      gdk_cairo_surface_create_from_pixbuf(pixbuf, 1, nullptr);
  GdkCursor *cursor =
      gdk_cursor_new_from_surface(gdk_display_get_default(), surface, hot_x, hot_y);
  cairo_surface_destroy(surface);

  GdkWindow *window = get_gdk_window(self);
  if (window != nullptr)
  {
    gdk_window_set_cursor(window, cursor);
  }

  GdkCursor *previous = self->active_cursor;
  self->active_cursor = cursor;
  if (previous != nullptr)
  {
    g_object_unref(previous);
  }

  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static void custom_cursor_plugin_handle_method_call(CustomCursorPlugin *self, FlMethodCall *method_call)
{
  const gchar *method = fl_method_call_get_name(method_call);
  FlValue *args = fl_method_call_get_args(method_call);

  if (strcmp(method, "activateCustomCursor") == 0)
  {
    auto *response = activate_custom_cursor(self, args);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(response), nullptr);
    g_object_unref(response);
  }
  else if (strcmp(method, "systemCursorSize") == 0)
  {
    GdkDisplay *display = gdk_display_get_default();
    const guint size =
        display != nullptr ? gdk_display_get_default_cursor_size(display) : 0;
    g_autoptr(FlValue) value = fl_value_new_int(static_cast<int64_t>(size));
    fl_method_call_respond(
        method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(value)),
        nullptr);
  }
  else if (strcmp(method, "clearCursor") == 0)
  {
    // GTK keeps no sticky custom cursor: Flutter's next cursor wins.
    fl_method_call_respond(
        method_call,
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr)), nullptr);
  }
  else if (strcmp(method, "resetCursor") == 0)
  {
    reset_to_default_cursor(self);
    fl_method_call_respond(method_call, FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr)), nullptr);
  }
  else
  {
    fl_method_call_respond(
        method_call, FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()),
        nullptr);
  }
}

static void custom_cursor_plugin_dispose(GObject *object)
{
  CustomCursorPlugin *self = CUSTOM_CURSOR_PLUGIN(object);
  if (self->active_cursor != nullptr)
  {
    g_object_unref(self->active_cursor);
    self->active_cursor = nullptr;
  }
  if (self->registrar != nullptr)
  {
    g_clear_object(&self->registrar);
  }
  G_OBJECT_CLASS(custom_cursor_plugin_parent_class)->dispose(object);
}

static void custom_cursor_plugin_class_init(CustomCursorPluginClass *klass)
{
  G_OBJECT_CLASS(klass)->dispose = custom_cursor_plugin_dispose;
}

static void custom_cursor_plugin_init(CustomCursorPlugin *self)
{
  self->active_cursor = nullptr;
  self->registrar = nullptr;
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *method_call,
                           gpointer user_data)
{
  CustomCursorPlugin *plugin = CUSTOM_CURSOR_PLUGIN(user_data);
  custom_cursor_plugin_handle_method_call(plugin, method_call);
}

void custom_cursor_plugin_register_with_registrar(FlPluginRegistrar *registrar)
{
  CustomCursorPlugin *plugin = CUSTOM_CURSOR_PLUGIN(
      g_object_new(custom_cursor_plugin_get_type(), nullptr));
  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "custom_cursor",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref(plugin));

  g_object_unref(plugin);
}
