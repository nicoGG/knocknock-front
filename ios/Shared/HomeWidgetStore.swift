import Foundation
import WidgetKit
import Darwin

/// A single atomic document and a cross-process lock keep Flutter refreshes and
/// WidgetKit button taps from overwriting each other's durable completion queue.
enum HomeWidgetStore {
  static let group = "group.cl.nocknock.app"
  static func transaction<T>(_ body: (inout [String: Any]) throws -> T) throws -> T {
    guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
      throw NSError(domain: "NockNockWidgets", code: 1)
    }
    let lockURL = directory.appendingPathComponent("home-widget.lock")
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw NSError(domain: "NockNockWidgets", code: 2) }
    defer { flock(descriptor, LOCK_UN); close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw NSError(domain: "NockNockWidgets", code: 3) }
    let url = directory.appendingPathComponent("home-widget.json")
    var state: [String: Any] = [:]
    if let data = try? Data(contentsOf: url),
       let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { state = decoded }
    let result = try body(&state)
    let data = try JSONSerialization.data(withJSONObject: state)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    return result
  }
  static func read() -> [String: Any] { (try? transaction { $0 }) ?? [:] }
  static func publish(_ snapshot: [String: Any]) throws {
    try transaction { state in
      let previous = state["snapshot"] as? [String: Any]
      if previous?["owner"] as? String != snapshot["owner"] as? String { state["queue"] = [[String: Any]]() }
      state["snapshot"] = snapshot
    }
    reload()
  }
  static func acknowledge(_ mutationId: String) throws {
    try transaction { state in
      state["queue"] = (state["queue"] as? [[String: Any]] ?? []).filter { $0["mutationId"] as? String != mutationId }
    }
    reload()
  }
  static func complete(id: String, owner: String) throws {
    try transaction { state in
      guard let snapshot = state["snapshot"] as? [String: Any], snapshot["owner"] as? String == owner,
            snapshot["hidden"] as? Bool != true,
            let row = (snapshot["rows"] as? [[String: Any]])?.first(where: { $0["id"] as? String == id }),
            row["canComplete"] as? Bool == true else { return }
      var queue = state["queue"] as? [[String: Any]] ?? []
      guard !queue.contains(where: { $0["id"] as? String == id }) else { return }
      var action: [String: Any] = ["id": id, "boardId": row["boardId"] ?? "", "revision": row["revision"] ?? 0]
      action["owner"] = owner
      action["mutationId"] = UUID().uuidString
      action["completedAt"] = Int64(Date().timeIntervalSince1970 * 1000)
      queue.append(action)
      state["queue"] = queue
    }
    reload()
  }
  static func reload() {
    WidgetCenter.shared.reloadTimelines(ofKind: "NockNockPending")
    WidgetCenter.shared.reloadTimelines(ofKind: "NockNockCapture")
  }
}
