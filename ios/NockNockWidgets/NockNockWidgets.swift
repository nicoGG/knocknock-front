import SwiftUI
import WidgetKit
import AppIntents

struct PendingRow: Identifiable {
  let id: String
  let boardId: String
  let title: String
  let canComplete: Bool
}
struct PendingEntry: TimelineEntry {
  let date: Date
  var owner = "guest"
  var title = "Hoy"
  var total = 0
  var hidden = false
  var initialized = false
  var captureListId = ""
  var listId = ""
  var rows: [PendingRow] = []
  var queued = 0
  var updatedAt: Date?

  func link(_ action: String, row: PendingRow? = nil) -> URL {
    var url = URLComponents()
    url.scheme = "nocknock"
    url.host = "widget"
    url.path = "/\(action)"
    url.queryItems = [URLQueryItem(name: "owner", value: owner),
      URLQueryItem(name: "boardId", value: row?.boardId ?? (action == "capture" ? captureListId : listId)),
      URLQueryItem(name: "noteId", value: row?.id ?? "")]
    return url.url!
  }
}
struct PendingProvider: TimelineProvider {
  func placeholder(in context: Context) -> PendingEntry {
    var entry = PendingEntry(date: Date())
    entry.initialized = true
    entry.total = 3
    entry.rows = [PendingRow(id: "preview", boardId: "", title: "Tus pendientes aquí", canComplete: false)]
    return entry
  }
  func getSnapshot(in context: Context, completion: @escaping (PendingEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : load())
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<PendingEntry>) -> Void) {
    completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(1800))))
  }
  func load() -> PendingEntry {
    let state = HomeWidgetStore.read()
    guard let snapshot = state["snapshot"] as? [String: Any] else { return PendingEntry(date: Date()) }
    var entry = PendingEntry(date: Date())
    entry.initialized = true
    entry.owner = snapshot["owner"] as? String ?? "guest"
    entry.title = snapshot["title"] as? String ?? "Hoy"
    entry.hidden = snapshot["hidden"] as? Bool ?? false
    entry.captureListId = snapshot["captureListId"] as? String ?? ""
    entry.listId = snapshot["listId"] as? String ?? ""
    let queue = state["queue"] as? [[String: Any]] ?? []
    let ids = Set(queue.compactMap { $0["id"] as? String })
    entry.queued = queue.count
    let snapshotRows = snapshot["rows"] as? [[String: Any]] ?? []
    let visibleQueuedCount = snapshotRows.filter { ids.contains($0["id"] as? String ?? "") }.count
    entry.total = max(0, (snapshot["total"] as? Int ?? 0) - visibleQueuedCount)
    if let milliseconds = snapshot["updatedAt"] as? Double { entry.updatedAt = Date(timeIntervalSince1970: milliseconds / 1000) }
    if !entry.hidden {
      entry.rows = snapshotRows.compactMap { row in
        guard let id = row["id"] as? String, !ids.contains(id),
              let boardId = row["boardId"] as? String, let title = row["title"] as? String else { return nil }
        return PendingRow(id: id, boardId: boardId, title: title, canComplete: row["canComplete"] as? Bool ?? false)
      }
    }
    return entry
  }
}

@available(iOS 17.0, *)
struct CompletePendingIntent: AppIntent {
  static var title: LocalizedStringResource = "Completar pendiente"
  static var openAppWhenRun = false
  @Parameter(title: "Nota") var noteId: String
  @Parameter(title: "Cuenta") var owner: String
  init() {}
  init(noteId: String, owner: String) { self.noteId = noteId; self.owner = owner }
  func perform() async throws -> some IntentResult {
    try HomeWidgetStore.complete(id: noteId, owner: owner)
    return .result()
  }
}

struct PendingWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: PendingEntry
  let captureOnly: Bool
  private let ink = Color(red: 0.16, green: 0.15, blue: 0.12)
  private let accent = Color(red: 0.45, green: 0.33, blue: 0.11)
  private var rowLimit: Int { family == .systemLarge ? 5 : family == .systemMedium ? 3 : 1 }
  var body: some View {
    if #available(iOS 17.0, *) {
      content.containerBackground(for: .widget) { Color(red: 1, green: 0.97, blue: 0.92) }
    } else {
      content.padding().background(Color(red: 1, green: 0.97, blue: 0.92))
    }
  }
  private var content: some View {
    VStack(alignment: .leading, spacing: 4) {
      if captureOnly {
        Text("NockNock").font(.caption.bold()).foregroundColor(accent)
        Spacer(minLength: 0)
        Link(destination: entry.link("capture")) {
          Label("Nueva nota", systemImage: "plus.circle.fill")
            .font(.title3.bold()).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.accessibilityLabel("Capturar una nueva nota")
      } else {
        HStack {
          Link(entry.title, destination: entry.link("today")).font(.headline).lineLimit(1)
          Spacer(minLength: 4)
          if !entry.hidden { Text("\(entry.total)").font(.headline).foregroundColor(accent) }
        }
        if entry.rows.isEmpty {
          Text(entry.hidden ? "Contenido oculto" : entry.initialized ? "Sin pendientes para mostrar" : "Abre NockNock para empezar")
            .font(.caption).foregroundColor(ink.opacity(0.65))
        }
        ForEach(Array(entry.rows.prefix(rowLimit))) { row in
          HStack(spacing: 8) {
            if #available(iOS 17.0, *), row.canComplete {
              Button(intent: CompletePendingIntent(noteId: row.id, owner: entry.owner)) {
                Image(systemName: "circle").font(.body).padding(.vertical, 1)
              }.buttonStyle(.plain).accessibilityLabel("Completar \(row.title)")
            } else {
              Link(destination: entry.link("note", row: row)) {
                Image(systemName: row.canComplete ? "circle" : "arrow.clockwise")
              }.accessibilityLabel("Abrir \(row.title)")
            }
            Link(destination: entry.link("note", row: row)) {
              Text(row.title).font(.subheadline).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
        Spacer(minLength: 0)
        if entry.queued > 0 {
          Text("\(entry.queued) por sincronizar · abre NockNock").font(.system(size: 10)).foregroundColor(accent)
        } else if let updated = entry.updatedAt, family != .systemSmall {
          HStack(spacing: 3) { Text("Actualizado"); Text(updated, style: .date); Text(updated, style: .time) }
            .font(.system(size: 10)).foregroundColor(ink.opacity(0.6))
        }
        Link(destination: entry.link("capture")) {
          Label("Nueva nota", systemImage: "plus").font(.caption.bold())
        }.foregroundColor(accent)
      }
    }
    .foregroundColor(ink)
    .widgetURL(entry.link(captureOnly ? "capture" : "today"))
  }
}

struct NockNockPendingWidget: Widget {
  let kind = "NockNockPending"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PendingProvider()) { entry in PendingWidgetView(entry: entry, captureOnly: false) }
      .configurationDisplayName("Mis pendientes")
      .description("Consulta tus tareas y captura una nota. Configura la lista desde NockNock.")
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
struct NockNockCaptureWidget: Widget {
  let kind = "NockNockCapture"
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: PendingProvider()) { entry in PendingWidgetView(entry: entry, captureOnly: true) }
      .configurationDisplayName("Captura rápida")
      .description("Abre directamente el editor para guardar una idea o tarea.")
      .supportedFamilies([.systemSmall, .systemMedium])
  }
}
@main
struct NockNockWidgets: WidgetBundle {
  var body: some Widget { NockNockPendingWidget(); NockNockCaptureWidget() }
}
