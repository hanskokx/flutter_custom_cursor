// Copyright (c) 2026 Hans Kokx.
// SPDX-License-Identifier: MIT

#include "include/custom_cursor/custom_cursor_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <gdiplus.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

#pragma comment(lib, "gdiplus.lib")

namespace custom_cursor
{

  using flutter::EncodableMap;
  using flutter::EncodableValue;

  namespace
  {

    // Look up [key] in [map] or return null.
    const EncodableValue *ValueOrNull(const EncodableMap &map, const char *key)
    {
      auto it = map.find(EncodableValue(key));
      return it == map.end() ? nullptr : &it->second;
    }

    double GetDouble(const EncodableMap &map, const char *key, double fallback)
    {
      const auto *v = ValueOrNull(map, key);
      if (v == nullptr)
        return fallback;
      if (std::holds_alternative<double>(*v))
        return std::get<double>(*v);
      if (std::holds_alternative<int>(*v))
        return std::get<int>(*v);
      if (std::holds_alternative<int64_t>(*v))
      {
        return static_cast<double>(std::get<int64_t>(*v));
      }
      return fallback;
    }

    // Clamp a dimension to the native cursor max size (128px).
    int ClampSize(int size)
    {
      return size < 1 ? 1 : (size > 128 ? 128 : size);
    }

    // Clear the custom cursor: drop the window-class cursor and show the system
    // default (arrow) immediately. A WM_SETCURSOR is posted afterwards so the
    // window re-evaluates the cursor right away instead of waiting for the next
    // mouse move.
    void ResetToDefaultCursor(flutter::PluginRegistrarWindows *registrar)
    {
      HWND hwnd = registrar->GetView() ? registrar->GetView()->GetNativeWindow()
                                        : nullptr;
      if (hwnd != nullptr)
      {
        SetClassLongPtr(hwnd, GCLP_HCURSOR, 0);
        PostMessage(
            hwnd, WM_SETCURSOR, reinterpret_cast<WPARAM>(hwnd),
            MAKELPARAM(HTCLIENT, WM_MOUSEMOVE));
      }
      SetCursor(LoadCursor(nullptr, IDC_ARROW));
    }

    // Decode PNG [bytes] into an HCURSOR with the given hotspot (device
    // pixels), scaling the image down to fit within 128px on its longest side.
    HCURSOR CursorFromPng(const std::vector<uint8_t> &bytes, int hot_x,
                           int hot_y)
    {
      HGLOBAL global = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
      if (global == nullptr)
        return nullptr;
      void *mem = GlobalLock(global);
      memcpy(mem, bytes.data(), bytes.size());
      GlobalUnlock(global);

      IStream *stream = nullptr;
      if (CreateStreamOnHGlobal(global, TRUE, &stream) != S_OK)
      {
        GlobalFree(global);
        return nullptr;
      }

      HCURSOR cursor = nullptr;
      {
        Gdiplus::Bitmap bitmap(stream);
        if (bitmap.GetLastStatus() == Gdiplus::Ok)
        {
          const int original_width = static_cast<int>(bitmap.GetWidth());
          const int original_height = static_cast<int>(bitmap.GetHeight());
          // Scale down proportionally to fit the 128px limit.
          const int longest = original_width > original_height
                                  ? original_width
                                  : original_height;
          const double scale = longest > 128 ? 128.0 / longest : 1.0;
          const int width = ClampSize(
              static_cast<int>(original_width * scale + 0.5));
          const int height = ClampSize(
              static_cast<int>(original_height * scale + 0.5));

          std::unique_ptr<Gdiplus::Bitmap> scaled;
          Gdiplus::Bitmap *source = &bitmap;
          if (width != original_width || height != original_height)
          {
            scaled = std::make_unique<Gdiplus::Bitmap>(
                width, height, PixelFormat32bppARGB);
            if (scaled->GetLastStatus() == Gdiplus::Ok)
            {
              Gdiplus::Graphics graphics(scaled.get());
              graphics.DrawImage(&bitmap, 0, 0, width, height);
              source = scaled.get();
            }
            else
            {
              scaled.reset();
            }
          }

          HBITMAP hbitmap = nullptr;
          source->GetHBITMAP(Gdiplus::Color(0, 0, 0, 0), &hbitmap);
          if (hbitmap != nullptr)
          {
            // Keep the hotspot on the same pixel of the (possibly scaled)
            // bitmap, and inside the cursor bounds.
            const int scaled_hot_x = original_width > 0
                                         ? hot_x * width / original_width
                                         : 0;
            const int scaled_hot_y = original_height > 0
                                         ? hot_y * height / original_height
                                         : 0;
            const int clamped_hot_x =
                scaled_hot_x < 0 ? 0 : (scaled_hot_x >= width ? width - 1 : scaled_hot_x);
            const int clamped_hot_y =
                scaled_hot_y < 0 ? 0 : (scaled_hot_y >= height ? height - 1 : scaled_hot_y);

            // An all-zero AND mask: visibility comes from the PNG alpha
            // channel, so leave the screen untouched where the cursor is
            // transparent.
            const int mask_stride = ((width + 15) / 16) * 2;
            std::vector<uint8_t> mask_bits(
                static_cast<size_t>(mask_stride) * height, 0);
            HBITMAP mask = CreateBitmap(
                width, height, 1, 1, mask_bits.data());
            ICONINFO info = {};
            info.fIcon = FALSE; // FALSE = cursor (uses hotspot)
            info.xHotspot = static_cast<DWORD>(clamped_hot_x);
            info.yHotspot = static_cast<DWORD>(clamped_hot_y);
            info.hbmMask = mask;
            info.hbmColor = hbitmap;
            cursor = reinterpret_cast<HCURSOR>(CreateIconIndirect(&info));
            DeleteObject(hbitmap);
            DeleteObject(mask);
          }
        }
      }
      stream->Release(); // also frees the HGLOBAL (TRUE above)
      return cursor;
    }

  } // namespace

  // static
  void CustomCursorPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        registrar->messenger(), "custom_cursor",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<CustomCursorPlugin>(registrar);

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  CustomCursorPlugin::CustomCursorPlugin(
      flutter::PluginRegistrarWindows *registrar)
      : registrar_(registrar), cursor_(nullptr)
  {
    Gdiplus::GdiplusStartupInput input;
    Gdiplus::GdiplusStartup(&gdiplus_token_, &input, nullptr);
  }

  CustomCursorPlugin::~CustomCursorPlugin()
  {
    if (cursor_ != nullptr)
      DestroyCursor(cursor_);
    if (gdiplus_token_ != 0)
      Gdiplus::GdiplusShutdown(gdiplus_token_);
  }

  void CustomCursorPlugin::HandleMethodCall(
      const flutter::MethodCall<EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<EncodableValue>> result)
  {
    const auto *args = std::get_if<EncodableMap>(method_call.arguments());
    const std::string &method = method_call.method_name();

    if (method == "activateCustomCursor" && args != nullptr)
    {
      const auto *img_v = ValueOrNull(*args, "image");
      if (img_v != nullptr && std::holds_alternative<std::vector<uint8_t>>(*img_v))
      {
        const auto &bytes = std::get<std::vector<uint8_t>>(*img_v);
        const int hot_x = static_cast<int>(GetDouble(*args, "hotspotX", 0));
        const int hot_y = static_cast<int>(GetDouble(*args, "hotspotY", 0));

        HCURSOR cursor = CursorFromPng(bytes, hot_x, hot_y);
        if (cursor != nullptr)
        {
          if (cursor_ != nullptr)
            DestroyCursor(cursor_);
          cursor_ = cursor;

          SetCursor(cursor);
          HWND hwnd = registrar_->GetView()
                      ? registrar_->GetView()->GetNativeWindow()
                      : nullptr;
          if (hwnd != nullptr)
          {
            SetClassLongPtr(hwnd, GCLP_HCURSOR,
                            reinterpret_cast<LONG_PTR>(cursor));
          }
          result->Success();
        }
        else
        {
          result->Error("decode", "bad png");
        }
      }
      else
      {
        result->Error("bad_args", "activateCustomCursor");
      }
    }
    else if (method == "clearCursor")
    {
      // Stop forcing the custom cursor without changing the visible one, so a
      // cursor Flutter activates right afterwards is not overwritten.
      HWND hwnd = registrar_->GetView()
                      ? registrar_->GetView()->GetNativeWindow()
                      : nullptr;
      if (hwnd != nullptr)
        SetClassLongPtr(hwnd, GCLP_HCURSOR, 0);
      result->Success();
    }
    else if (method == "resetCursor")
    {
      ResetToDefaultCursor(registrar_);
      result->Success();
    }
    else
    {
      result->NotImplemented();
    }
  }

} // namespace custom_cursor
