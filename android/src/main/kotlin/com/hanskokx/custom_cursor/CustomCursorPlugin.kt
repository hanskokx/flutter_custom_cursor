// Copyright (c) 2026 Hans Kokx.
// SPDX-License-Identifier: MIT

package com.hanskokx.custom_cursor

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.PointerIcon
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.math.roundToInt

/** CustomCursorPlugin */
class CustomCursorPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {
  private var channel: MethodChannel? = null
  private var activity: Activity? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, CHANNEL)
    channel?.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    onAttachedToActivity(binding)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "activateCustomCursor" -> handleActivateCustomCursor(call, result)
      // Leave the current pointer icon alone; the next cursor Flutter
      // activates will replace it.
      "clearCursor" -> result.success(null)
      "resetCursor" -> handleResetCursor(result)
      else -> result.notImplemented()
    }
  }

  private fun handleResetCursor(result: Result) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      setPointerIcon(null)
    }
    result.success(null)
  }

  private fun handleActivateCustomCursor(call: MethodCall, result: Result) {
    val args = call.arguments as? Map<*, *>
    if (args == null) {
      result.error("bad_args", "activateCustomCursor", null)
      return
    }
    val pngBytes = args["image"] as? ByteArray
    if (pngBytes == null) {
      result.error("bad_args", "missing image", null)
      return
    }
    val hotspotX = (args["hotspotX"] as? Number)?.toFloat() ?: 0f
    val hotspotY = (args["hotspotY"] as? Number)?.toFloat() ?: 0f

    val original = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
    if (original == null) {
      result.error("decode", "bad png", null)
      return
    }
    val density = activity?.resources?.displayMetrics?.density ?: 1.0f
    val bitmap = scaleByDensity(original, density)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
      val x = (hotspotX * density).coerceIn(0f, (bitmap.width - 1).toFloat())
      val y = (hotspotY * density).coerceIn(0f, (bitmap.height - 1).toFloat())
      setPointerIcon(PointerIcon.create(bitmap, x, y))
    }
    result.success(null)
  }

  private fun setPointerIcon(icon: PointerIcon?) {
    val views = mutableListOf<View>()
    val decor = activity?.window?.decorView ?: return
    collectHostViews(decor, views)
    for (view in views) {
      view.pointerIcon = icon
    }
  }

  private fun collectHostViews(view: View, out: MutableList<View>) {
    val name = view.javaClass.name
    if (name == "io.flutter.embedding.android.FlutterView" || name.endsWith("SurfaceView")) {
      out.add(view)
    }
    if (view is ViewGroup) {
      for (i in 0 until view.childCount) {
        collectHostViews(view.getChildAt(i), out)
      }
    }
  }

  private fun scaleByDensity(bitmap: Bitmap, density: Float): Bitmap {
    val width = (bitmap.width * density).roundToInt()
    val height = (bitmap.height * density).roundToInt()
    if (width == bitmap.width && height == bitmap.height) return bitmap
    return Bitmap.createScaledBitmap(bitmap, width, height, true)
  }

  companion object {
    private const val CHANNEL = "custom_cursor"
  }
}
