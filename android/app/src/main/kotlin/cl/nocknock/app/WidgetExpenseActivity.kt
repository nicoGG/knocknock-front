package cl.nocknock.app

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.widget.EditText
import android.widget.LinearLayout
import org.json.JSONObject
import java.util.UUID

/** Compact widget entry; persistence uses the same durable queue as checklist actions. */
class WidgetExpenseActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val state = WidgetStore.read(this).optJSONObject("snapshot")
        val owner = intent.getStringExtra("owner") ?: ""
        val board = intent.getStringExtra("boardId") ?: ""
        val lists = state?.optJSONArray("catalog")
        val list = (0 until (lists?.length() ?: 0)).mapNotNull { lists?.optJSONObject(it) }
            .firstOrNull { it.optString("listId") == board && it.optBoolean("expenses") }
        if (state?.optBoolean("hidden") != false || state.optString("owner") != owner || list == null) { finish(); return }
        val form = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 16, 32, 0) }
        val title = EditText(this).apply { hint = "Descripción"; maxLines = 1 }
        val amount = EditText(this).apply { hint = "Monto (${list.optString("currency")})"; inputType = InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_DECIMAL }
        form.addView(title); form.addView(amount)
        val dialog = AlertDialog.Builder(this).setTitle("Agregar gasto · ${list.optString("title")}")
            .setView(form).setPositiveButton("Guardar", null).setNegativeButton("Cancelar") { _, _ -> finish() }
            .setOnCancelListener { finish() }.create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val text = amount.text.toString().trim().replace(',', '.')
                val pattern = if (list.optString("currency") == "CLP") Regex("^[0-9]+$") else Regex("^[0-9]+(?:[.][0-9]{1,2})?$")
                val value = text.toBigDecimalOrNull()
                val max = if (list.optString("currency") == "CLP") java.math.BigDecimal("100000000000000") else java.math.BigDecimal("1000000000000")
                if (title.text.toString().trim().isEmpty() || title.length() > 120) { title.error = "Escribe una descripción de hasta 120 caracteres"; return@setOnClickListener }
                if (!pattern.matches(text) || value == null || value.signum() <= 0 || value > max) { amount.error = "Ingresa un monto válido"; return@setOnClickListener }
                WidgetStore.enqueue(this, JSONObject().put("type", "expense").put("owner", owner).put("boardId", board)
                    .put("id", UUID.randomUUID().toString()).put("title", title.text.toString().trim()).put("amount", text))
                startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    .putExtra("widgetAction", "today").putExtra("owner", owner).putExtra("boardId", board))
                finish()
            }
        }
        dialog.show()
    }
}
