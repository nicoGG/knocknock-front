import Flutter
import UIKit
import Vision

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
    let receiptChannel = FlutterMethodChannel(name: "cl.nocknock/receipt_scanner", binaryMessenger: registrar.messenger())
    receiptChannel.setMethodCallHandler { call, result in
      guard call.method == "recognize" else { result(FlutterMethodNotImplemented); return }
      guard let bytes = call.arguments as? FlutterStandardTypedData,
            !bytes.data.isEmpty, bytes.data.count <= 25 * 1024 * 1024 else {
        result(FlutterError(code: "RECEIPT_IMAGE", message: "Imagen inválida", details: nil)); return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-ES", "en-US"]
        request.usesLanguageCorrection = false
        do {
          try VNImageRequestHandler(data: bytes.data, options: [:]).perform([request])
          let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
          var rows: [[VNRecognizedTextObservation]] = []
          for observation in observations {
            if let anchor = rows.last?.first,
               abs(anchor.boundingBox.midY - observation.boundingBox.midY) <= max(anchor.boundingBox.height, observation.boundingBox.height) / 2 {
              rows[rows.count - 1].append(observation)
            } else { rows.append([observation]) }
          }
          let text = rows.map { row in row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") }.joined(separator: "\n")
          DispatchQueue.main.async { result(text) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "RECEIPT_OCR", message: "No se pudo leer la boleta", details: nil)) }
        }
      }
    }
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
