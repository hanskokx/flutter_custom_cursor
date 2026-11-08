import Cocoa
import FlutterMacOS

public class CustomCursorPlugin: NSObject, FlutterPlugin {
  private var activeCursor: NSCursor?
  private var mouseMonitor: Any?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "custom_cursor",
      binaryMessenger: registrar.messenger
    )
    let instance = CustomCursorPlugin()
    instance.ensureMouseMonitor()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  deinit {
    if let monitor = mouseMonitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  private func ensureMouseMonitor() {
    guard mouseMonitor == nil else { return }
    mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
      if let cursor = self?.activeCursor, CustomCursorPlugin.pointerOverAppWindow() {
        cursor.set()
      }
      return event
    }
  }

  private static func pointerOverAppWindow() -> Bool {
    let location = NSEvent.mouseLocation
    return NSApp.windows.contains { window in
      window.isVisible && NSMouseInRect(location, window.frame, false)
    }
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "activateCustomCursor":
      if let args = call.arguments as? [String: Any],
         let pngData = (args["image"] as? FlutterStandardTypedData)?.data,
         let image = NSImage(data: pngData) {
        let hotspotX = (args["hotspotX"] as? NSNumber)?.doubleValue ?? 0
        let hotspotY = (args["hotspotY"] as? NSNumber)?.doubleValue ?? 0
        activeCursor = NSCursor(image: image, hotSpot: NSPoint(x: hotspotX, y: hotspotY))
        activeCursor?.set()
      }
      result(nil)
    case "clearCursor":
      // Stop re-asserting the custom cursor without changing the visible one,
      // so the cursor Flutter activates next is not overwritten.
      activeCursor = nil
      result(nil)
    case "resetCursor":
      activeCursor = nil
      NSCursor.arrow.set()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
