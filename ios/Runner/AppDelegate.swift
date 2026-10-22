import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var widgetChannel: FlutterMethodChannel?
  private var pendingWidgetAction: [String: String]?

  func handleWidgetURL(_ url: URL) -> Bool {
    guard url.scheme == "nocknock", url.host == "widget",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
    var action = ["action": url.lastPathComponent]
    for item in components.queryItems ?? [] where ["owner", "boardId", "noteId"].contains(item.name) {
      action[item.name] = item.value ?? ""
    }
    pendingWidgetAction = action
    widgetChannel?.invokeMethod("actionAvailable", arguments: nil)
    return true
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NockNockHomeWidgets") else { return }
    let channel = FlutterMethodChannel(name: "cl.nocknock/home_widgets", binaryMessenger: registrar.messenger())
    widgetChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      do {
        switch call.method {
        case "publish":
          guard let raw = call.arguments as? String, let data = raw.data(using: .utf8),
                let snapshot = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            result(FlutterError(code: "WIDGET_DATA", message: "Datos inválidos", details: nil)); return
          }
          try HomeWidgetStore.publish(snapshot); result(nil)
        case "readQueue":
          let queue = HomeWidgetStore.read()["queue"] as? [[String: Any]] ?? []
          result(String(data: try JSONSerialization.data(withJSONObject: queue), encoding: .utf8))
        case "acknowledge":
          try HomeWidgetStore.acknowledge(call.arguments as? String ?? ""); result(nil)
        case "takeAction":
          result(self?.pendingWidgetAction); self?.pendingWidgetAction = nil
        case "requestPin": result(false)
        default: result(FlutterMethodNotImplemented)
        }
      } catch { result(FlutterError(code: "WIDGET_STORAGE", message: "No se pudo actualizar el widget", details: nil)) }
    }
  }
}
