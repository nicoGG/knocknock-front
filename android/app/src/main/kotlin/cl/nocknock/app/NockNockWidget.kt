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
        for (type in listOf(NockNockWidget::class.java, QuickCaptureWidget::class.java)) {
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
            val visibleQueuedCount = (0 until rows.length()).count { queuedIds.contains(rows.optJSONObject(it)?.let { row -> row.optString("id") + ":" + row.optString("subtaskId") }) }
            val views = RemoteViews(context.packageName, if (captureOnly) R.layout.widget_capture else R.layout.widget_pending)
            views.setOnClickPendingIntent(R.id.widget_capture, launch(context, "capture", owner, snapshot.optString("captureListId", "").let { if (it == "null") "" else it }))
            if (!captureOnly) {
                val configure = Intent(context, WidgetConfigurationActivity::class.java)
                    .setData(Uri.parse("nocknock://configure/$id"))
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                views.setOnClickPendingIntent(R.id.widget_configure, PendingIntent.getActivity(context, id, configure, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                if (selected?.optBoolean("expenses") == true && !hidden) {
                    val expense = Intent(context, WidgetExpenseActivity::class.java)
                        .setData(Uri.parse("nocknock://expense/$id"))
                        .putExtra("boardId", selected.optString("listId")).putExtra("owner", owner)
                    views.setTextViewText(R.id.widget_capture, "＋ Agregar gasto")
                    views.setOnClickPendingIntent(R.id.widget_capture, PendingIntent.getActivity(context, id, expense, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                }
                views.setTextViewText(R.id.widget_title, snapshot.optString("title", "Hoy"))
                views.setOnClickPendingIntent(R.id.widget_title, launch(context, "today", owner, snapshot.optString("listId", "").let { if (it == "null") "" else it }))
                views.setTextViewText(R.id.widget_count, if (hidden) "Contenido oculto" else "${(snapshot.optInt("total") - visibleQueuedCount).coerceAtLeast(0)} pendientes")
                if (selected?.optBoolean("financial") == true && !hidden) {
                    views.setTextViewText(R.id.widget_count, "Total · " + selected.optString("summary").ifEmpty { "Sin movimientos" })
                }
                views.removeAllViews(R.id.widget_rows)
                var shown = 0
                val height = manager.getAppWidgetOptions(id).getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 310)
                val rowLimit = if (config != null) Int.MAX_VALUE else ((height - 140) / 44).coerceIn(1, 5)
                if (!hidden) for (i in 0 until rows.length()) {
                    val row = rows.optJSONObject(i) ?: continue
                    val noteId = row.optString("id")
                    val subtask = row.optString("subtaskId")
                    val completed = row.optBoolean("completed") || queuedIds.contains("$noteId:$subtask")
                    if (config == null && completed) continue
                    if (shown >= rowLimit) break
                    val item = RemoteViews(context.packageName, R.layout.widget_note_row)
                    item.setTextViewText(R.id.widget_note_title, row.optString("title"))
                    item.setContentDescription(R.id.widget_check, if (row.optBoolean("canComplete")) "Completar ${row.optString("title")}" else "Abrir recordatorio recurrente ${row.optString("title")}")
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
                        item.setTextViewText(R.id.widget_check, "○")
                        item.setOnClickPendingIntent(R.id.widget_check, PendingIntent.getBroadcast(context,
                            complete.data.toString().hashCode(), complete, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                    } else {
                        item.setTextViewText(R.id.widget_check, if (completed) "✓" else "↗")
                        item.setOnClickPendingIntent(R.id.widget_check, open)
                    }
                    views.addView(R.id.widget_rows, item)
                    shown++
                }
                views.setTextViewText(R.id.widget_empty, if (hidden) "Abre NockNock para ver tus notas" else if (snapshot.length() == 0) "Abre NockNock para empezar" else "Sin pendientes para mostrar")
                views.setViewVisibility(R.id.widget_empty, if (shown == 0) android.view.View.VISIBLE else android.view.View.GONE)
                val updated = snapshot.optLong("updatedAt")
                views.setTextViewText(R.id.widget_updated, if (queued.length() > 0) "${queued.length()} por sincronizar · abre NockNock" else if (updated > 0) "Actualizado ${DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(updated))}" else "")
            }
            manager.updateAppWidget(id, views)
        }
    }
}
class QuickCaptureWidget : NockNockWidget()
