package cl.nocknock.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.DateFormat
import java.util.Date
import java.util.UUID

/** One private device snapshot; actions contain IDs and revisions, never credentials. */
object WidgetStore {
    private fun prefs(context: Context) = context.getSharedPreferences("nocknock_widgets", Context.MODE_PRIVATE)
    @Synchronized fun read(context: Context): JSONObject = try {
        JSONObject(prefs(context).getString("state", "{}") ?: "{}")
    } catch (_: Exception) { JSONObject() }
    @Synchronized private fun write(context: Context, state: JSONObject) {
        check(prefs(context).edit().putString("state", state.toString()).commit())
    }
    @Synchronized fun publish(context: Context, snapshot: JSONObject) {
        val state = read(context)
        if (state.optJSONObject("snapshot")?.optString("owner") != snapshot.optString("owner")) {
            state.put("queue", JSONArray())
        }
        state.put("snapshot", snapshot)
        write(context, state)
        refresh(context)
    }
    @Synchronized fun acknowledge(context: Context, mutationId: String) {
        val state = read(context)
        val queue = state.optJSONArray("queue") ?: JSONArray()
        val remaining = JSONArray()
        for (i in 0 until queue.length()) {
            val item = queue.optJSONObject(i) ?: continue
            if (item.optString("mutationId") != mutationId) remaining.put(item)
        }
        state.put("queue", remaining)
        write(context, state)
        refresh(context)
    }
    @Synchronized fun complete(context: Context, id: String, owner: String) {
        val state = read(context)
        val snapshot = state.optJSONObject("snapshot") ?: return
        if (snapshot.optString("owner") != owner || snapshot.optBoolean("hidden")) return
        val rows = JSONArray()
        val defaultRows = snapshot.optJSONArray("rows") ?: JSONArray()
        for (i in 0 until defaultRows.length()) rows.put(defaultRows.getJSONObject(i))
        val catalog = snapshot.optJSONArray("catalog") ?: JSONArray()
        for (i in 0 until catalog.length()) {
            val items = catalog.optJSONObject(i)?.optJSONArray("rows") ?: continue
            for (j in 0 until items.length()) rows.put(items.getJSONObject(j))
        }
        val queue = state.optJSONArray("queue") ?: JSONArray()
        for (i in 0 until queue.length()) if (queue.optJSONObject(i)?.optString("id") == id && !queue.optJSONObject(i)!!.has("subtaskId")) return
        for (i in 0 until rows.length()) {
            val row = rows.optJSONObject(i) ?: continue
            if (row.optString("id") == id && row.optBoolean("canComplete")) {
                queue.put(JSONObject().put("id", id).put("boardId", row.optString("boardId"))
                    .put("revision", row.optInt("revision")).put("owner", owner)
                    .put("mutationId", UUID.randomUUID().toString())
                    .put("completedAt", System.currentTimeMillis()))
                state.put("queue", queue)
                write(context, state)
                refresh(context)
                return
            }
        }
    }
    @Synchronized fun configure(context: Context, widgetId: Int, board: String, note: String = "") {
        val state = read(context)
        val configs = state.optJSONObject("configs") ?: JSONObject()
        configs.put(widgetId.toString(), JSONObject().put("board", board).put("note", note)
            .put("owner", state.optJSONObject("snapshot")?.optString("owner")))
        state.put("configs", configs)
        write(context, state)
        refresh(context)
    }
    @Synchronized fun enqueue(context: Context, action: JSONObject) {
        val state = read(context)
        val snapshot = state.optJSONObject("snapshot") ?: return
        if (snapshot.optBoolean("hidden") || snapshot.optString("owner") != action.optString("owner")) return
        val queue = state.optJSONArray("queue") ?: JSONArray()
        queue.put(action.put("mutationId", UUID.randomUUID().toString()).put("completedAt", System.currentTimeMillis()))
        state.put("queue", queue)
        write(context, state)
        refresh(context)
    }
    fun refresh(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        for (type in listOf(NockNockWidget::class.java, SummaryWidget::class.java, UpcomingWidget::class.java, ExpandedListWidget::class.java, QuickCaptureWidget::class.java)) {
            for (id in manager.getAppWidgetIds(ComponentName(context, type))) {
                NockNockWidget.render(context, manager, id, type == QuickCaptureWidget::class.java)
            }
        }
    }
}

open class NockNockWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) render(context, manager, id, this is QuickCaptureWidget)
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: android.os.Bundle) {
        render(context, manager, id, this is QuickCaptureWidget)
    }
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == "cl.nocknock.WIDGET_SUBTASK") {
            val row = JSONObject(intent.getStringExtra("row") ?: return)
            WidgetStore.enqueue(context, row)
        }
        if (intent.action == "cl.nocknock.WIDGET_COMPLETE") {
            WidgetStore.complete(context, intent.getStringExtra("noteId") ?: return,
                intent.getStringExtra("owner") ?: return)
        }
    }
    companion object {
        private fun launch(context: Context, action: String, owner: String, board: String = "", note: String = ""): PendingIntent {
            val data = Uri.Builder().scheme("nocknock").authority("widget").appendPath(action)
                .appendQueryParameter("owner", owner).appendQueryParameter("boardId", board)
                .appendQueryParameter("noteId", note).build()
            val intent = Intent(context, MainActivity::class.java).setAction("cl.nocknock.WIDGET_LAUNCH.$data")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra("widgetAction", action).putExtra("owner", owner)
                .putExtra("boardId", board).putExtra("noteId", note)
            return PendingIntent.getActivity(context, data.toString().hashCode(), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        fun render(context: Context, manager: AppWidgetManager, id: Int, captureOnly: Boolean) {
            val state = WidgetStore.read(context)
            val options = manager.getAppWidgetOptions(id)
            val pendingOnly = manager.getAppWidgetInfo(id)?.provider?.className == UpcomingWidget::class.java.name
            fun sized(width: Int, height: Int): RemoteViews {
                val sizeOptions = android.os.Bundle(options).apply {
                    putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, width)
                    putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, height)
                }
                return buildViews(context, id, captureOnly, state, sizeOptions, pendingOnly)
            }
            if (android.os.Build.VERSION.SDK_INT >= 31) {
                @Suppress("DEPRECATION")
                val sizes = options.getParcelableArrayList<android.util.SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                if (!sizes.isNullOrEmpty()) {
                    val layouts = sizes.distinct().take(16).associateWith { sized(it.width.toInt(), it.height.toInt()) }
                    manager.updateAppWidget(id, RemoteViews(layouts))
                    return
                }
            }
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 320)
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 310)
            val maxWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, minWidth)
            val maxHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, minHeight)
            manager.updateAppWidget(id, RemoteViews(sized(maxWidth, minHeight), sized(minWidth, maxHeight)))
        }
        internal fun buildViews(context: Context, id: Int, captureOnly: Boolean, state: JSONObject, options: android.os.Bundle, pendingOnly: Boolean = false): RemoteViews {
            val base = state.optJSONObject("snapshot") ?: JSONObject()
            val config = state.optJSONObject("configs")?.optJSONObject(id.toString())
            val catalog = base.optJSONArray("catalog") ?: JSONArray()
            var selected: JSONObject? = null
            if (config?.optString("owner") == base.optString("owner") && !base.optBoolean("hidden")) {
                for (i in 0 until catalog.length()) {
                    val candidate = catalog.optJSONObject(i) ?: continue
                    if (candidate.optString("listId") == config.optString("board")) selected = candidate
                }
            }
            val snapshot = if (config == null) base else JSONObject(base.toString()).apply {
                put("rows", selected?.optJSONArray("rows") ?: JSONArray())
                put("title", selected?.optString("title") ?: "Lista no disponible")
                put("listId", selected?.optString("listId") ?: "")
                put("captureListId", selected?.optString("listId") ?: "")
            }
            val noteFilter = config?.optString("note") ?: ""
            if (selected != null) {
                val flat = JSONArray()
                val source = selected.optJSONArray("rows") ?: JSONArray()
                for (i in 0 until source.length()) {
                    val row = source.optJSONObject(i) ?: continue
                    if (noteFilter.isNotEmpty() && row.optString("id") != noteFilter) continue
                    flat.put(row)
                    val checklist = row.optJSONArray("checklist") ?: JSONArray()
                    for (j in 0 until checklist.length()) {
                        val sub = checklist.optJSONObject(j) ?: continue
                        flat.put(JSONObject(row.toString()).put("subtaskId", sub.optString("id"))
                            .put("title", "  " + sub.optString("text"))
                            .put("completed", sub.optBoolean("isCompleted")).put("canComplete", !sub.optBoolean("isCompleted")))
                    }
                }
                snapshot.put("rows", flat).put("total", flat.length())
            }
            val owner = snapshot.optString("owner", "guest")
            val hidden = snapshot.optBoolean("hidden", false)
            val queued = state.optJSONArray("queue") ?: JSONArray()
            val queuedIds = (0 until queued.length()).mapNotNull { queued.optJSONObject(it)?.let { row -> row.optString("id") + ":" + row.optString("subtaskId") } }.toSet()
            val rows = snapshot.optJSONArray("rows") ?: JSONArray()
            fun isCompleted(row: JSONObject) = row.optBoolean("completed") || queuedIds.contains(row.optString("id") + ":" + row.optString("subtaskId"))
            val completedCount = (0 until rows.length()).count { rows.optJSONObject(it)?.let(::isCompleted) == true }
            val pendingCount = (if (config == null) snapshot.optInt("total") else rows.length()) - completedCount
            val appearance = WidgetAppearance(context, base)
            val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 310)
            val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 320)
            val sizeLayout = WidgetSizeLayout.choose(width, height, captureOnly)
            val views = RemoteViews(context.packageName, sizeLayout.resource)
            appearance.decorate(views, captureOnly, sizeLayout == WidgetSizeLayout.CAPTURE_SMALL)
            views.setOnClickPendingIntent(R.id.widget_capture, launch(context, "capture", owner, snapshot.optString("captureListId", "").let { if (it == "null") "" else it }))
            if (!captureOnly) {
                val configure = Intent(context, WidgetConfigurationActivity::class.java)
                    .setData(Uri.parse("nocknock://configure/$id"))
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                views.setOnClickPendingIntent(R.id.widget_configure, PendingIntent.getActivity(context, id, configure, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                if (sizeLayout == WidgetSizeLayout.SUMMARY) {
                    views.setTextViewTextSize(R.id.widget_title, android.util.TypedValue.COMPLEX_UNIT_SP, 16f)
                }
                if (sizeLayout == WidgetSizeLayout.COMPACT && width >= 230) {
                    views.setTextViewText(R.id.widget_capture, "＋ Nueva nota")
                    views.setTextViewTextSize(R.id.widget_capture, android.util.TypedValue.COMPLEX_UNIT_SP, 14f)
                }
                if (selected?.optBoolean("expenses") == true && !hidden) {
                    val expense = Intent(context, WidgetExpenseActivity::class.java)
                        .setData(Uri.parse("nocknock://expense/$id"))
                        .putExtra("boardId", selected.optString("listId")).putExtra("owner", owner)
                    views.setTextViewText(R.id.widget_capture, when {
                        sizeLayout == WidgetSizeLayout.FULL -> "Agregar gasto"
                        sizeLayout == WidgetSizeLayout.COMPACT && width >= 230 -> "＋ Agregar gasto"
                        else -> "＋"
                    })
                    views.setContentDescription(R.id.widget_capture, "Agregar gasto")
                    views.setOnClickPendingIntent(R.id.widget_capture, PendingIntent.getActivity(context, id, expense, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                }
                views.setTextViewText(R.id.widget_title, snapshot.optString("title", "Hoy"))
                views.setOnClickPendingIntent(R.id.widget_title, launch(context, "today", owner, snapshot.optString("listId", "").let { if (it == "null") "" else it }))
                views.setTextViewText(R.id.widget_count, if (hidden) "Contenido oculto" else "${pendingCount.coerceAtLeast(0)} ${if (pendingCount == 1) "pendiente" else "pendientes"}" + if (sizeLayout != WidgetSizeLayout.SUMMARY && config != null && completedCount > 0) " · $completedCount completadas" else "")
                if (selected?.optBoolean("financial") == true && !hidden) {
                    views.setTextViewText(R.id.widget_count, "Total · " + selected.optString("summary").ifEmpty { "Sin movimientos" })
                }
                views.removeAllViews(R.id.widget_rows)
                var shown = 0
                // Reserve header/footer space, including a link for truncated lists.
                // Rows use a 44dp touch target plus a 4dp gap; account for font scaling.
                val fontScale = context.resources.configuration.fontScale.coerceAtLeast(1f)
                val rowHeight = (48 * fontScale).toInt()
                if (sizeLayout == WidgetSizeLayout.SUMMARY && fontScale > 1.3f) views.setViewVisibility(R.id.widget_count, android.view.View.GONE)
                val rowLimit = if (sizeLayout == WidgetSizeLayout.SUMMARY) 0 else ((height - sizeLayout.reservedHeight * fontScale) / rowHeight).toInt().coerceIn(0, when {
                    sizeLayout == WidgetSizeLayout.WIDE -> 2
                    sizeLayout == WidgetSizeLayout.COMPACT && width >= 230 -> 3
                    else -> 20
                })
                if (sizeLayout == WidgetSizeLayout.WIDE && rowLimit == 0) views.setViewVisibility(R.id.widget_count, android.view.View.VISIBLE)
                if (!hidden) for (i in 0 until rows.length()) {
                    val row = rows.optJSONObject(i) ?: continue
                    val noteId = row.optString("id")
                    val subtask = row.optString("subtaskId")
                    val completed = row.optBoolean("completed") || queuedIds.contains("$noteId:$subtask")
                    if ((config == null || pendingOnly) && completed) continue
                    if (shown >= rowLimit) break
                    val item = RemoteViews(context.packageName, R.layout.widget_note_row)
                    item.setTextViewText(R.id.widget_note_title, row.optString("title").trim())
                    appearance.surface(item, R.id.widget_row, R.drawable.widget_row, R.drawable.widget_row_light, R.drawable.widget_row_dark)
                    appearance.text(item, R.id.widget_note_title, if (completed) "muted" else "ink")
                    appearance.icon(item, R.id.widget_check, if (completed) "muted" else "accent")
                    item.setInt(R.id.widget_note_title, "setPaintFlags", android.graphics.Paint.ANTI_ALIAS_FLAG or android.graphics.Paint.SUBPIXEL_TEXT_FLAG or (if (completed) android.graphics.Paint.STRIKE_THRU_TEXT_FLAG else 0))
                    item.setContentDescription(R.id.widget_check, if (completed) "Abrir tarea completada: ${row.optString("title")}" else if (row.optBoolean("canComplete")) "Completar ${row.optString("title")}" else "Abrir ${row.optString("title")}")
                    val open = launch(context, "note", owner, row.optString("boardId"), noteId)
                    item.setOnClickPendingIntent(R.id.widget_note_title, open)
                    if (row.optBoolean("canComplete") && !completed) {
                        val complete = Intent(context, NockNockWidget::class.java)
                            .setAction("cl.nocknock.WIDGET_COMPLETE")
                            .setData(Uri.parse("nocknock://complete/${Uri.encode(owner)}/${Uri.encode(noteId)}"))
                            .putExtra("owner", owner).putExtra("noteId", noteId)
                        if (subtask.isNotEmpty()) {
                            complete.setAction("cl.nocknock.WIDGET_SUBTASK")
                                .setData(Uri.parse("nocknock://subtask/${Uri.encode(owner)}/${Uri.encode(noteId)}/${Uri.encode(subtask)}"))
                                .putExtra("row", JSONObject(row.toString()).put("owner", owner).toString())
                        }
                        item.setImageViewResource(R.id.widget_check, R.drawable.widget_checkbox_empty)
                        item.setOnClickPendingIntent(R.id.widget_check, PendingIntent.getBroadcast(context,
                            complete.data.toString().hashCode(), complete, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                    } else {
                        item.setImageViewResource(R.id.widget_check, if (completed) R.drawable.widget_checkbox_checked else R.drawable.widget_open)
                        item.setOnClickPendingIntent(R.id.widget_check, open)
                    }
                    views.addView(R.id.widget_rows, item)
                    shown++
                }
                views.setTextViewText(R.id.widget_empty, if (hidden) "Abre NockNock para ver tus notas" else if (snapshot.length() == 0) "Abre NockNock para empezar" else "Sin pendientes para mostrar")
                views.setViewVisibility(R.id.widget_empty, if (sizeLayout != WidgetSizeLayout.SUMMARY && shown == 0 && (rows.length() == 0 || hidden)) android.view.View.VISIBLE else android.view.View.GONE)
                val available = if (config == null || pendingOnly) rows.length() - completedCount else rows.length()
                val remaining = (available - shown).coerceAtLeast(0)
                views.setTextViewText(R.id.widget_more, "Ver lista completa · $remaining más")
                views.setViewVisibility(R.id.widget_more, if (sizeLayout == WidgetSizeLayout.FULL && !hidden && remaining > 0) android.view.View.VISIBLE else android.view.View.GONE)
                views.setOnClickPendingIntent(R.id.widget_more, launch(context, "today", owner, snapshot.optString("listId", "")))
                val updated = snapshot.optLong("updatedAt")
                views.setTextViewText(R.id.widget_updated, if (queued.length() > 0) "${queued.length()} por sincronizar · abre NockNock" else if (updated > 0) "Actualizado ${DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(updated))}" else "")
            }
            return views
        }
    }
}
class QuickCaptureWidget : NockNockWidget()

class SummaryWidget : NockNockWidget()
class UpcomingWidget : NockNockWidget()
class ExpandedListWidget : NockNockWidget()
