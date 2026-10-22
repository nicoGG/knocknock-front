package cl.nocknock.app

import android.app.Activity
import android.app.AlertDialog
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import org.json.JSONArray

class WidgetConfigurationActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) { finish(); return }
        val snapshot = WidgetStore.read(this).optJSONObject("snapshot")
        val lists = if (snapshot?.optBoolean("hidden") == false) snapshot.optJSONArray("catalog") ?: JSONArray() else JSONArray()
        if (lists.length() == 0) {
            AlertDialog.Builder(this).setMessage("Abre NockNock para actualizar tus listas y vuelve a agregar el widget.")
                .setPositiveButton("Abrir app") { _, _ -> startActivity(Intent(this, MainActivity::class.java)); finish() }
                .setOnCancelListener { finish() }.show()
            return
        }
        AlertDialog.Builder(this).setTitle("Elige una lista")
            .setItems(Array(lists.length()) { lists.getJSONObject(it).optString("title") }) { _, index ->
                val list = lists.getJSONObject(index)
                val rows = list.optJSONArray("rows") ?: JSONArray()
                val labels = arrayOf("Lista completa") + Array(rows.length()) { rows.getJSONObject(it).optString("title") }
                AlertDialog.Builder(this).setTitle("Mostrar en el widget").setItems(labels) { _, row ->
                    WidgetStore.configure(this, id, list.getString("listId"), if (row == 0) "" else rows.getJSONObject(row - 1).getString("id"))
                    setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
                    finish()
                }.setOnCancelListener { finish() }.show()
            }.setOnCancelListener { finish() }.show()
    }
}
