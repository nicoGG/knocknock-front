package cl.nocknock.app

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.graphics.drawable.Icon
import android.os.Build
import android.widget.RemoteViews
import org.json.JSONObject

/** Theme pairs resolve in the launcher, including when the app is closed. */
internal class WidgetAppearance(private val context: Context, snapshot: JSONObject) {
    private val theme = snapshot.optJSONObject("theme") ?: JSONObject()
    private val mode = theme.optString("mode", "system")
    private val systemDark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    private fun palette(dark: Boolean) = theme.optJSONObject(if (dark) "dark" else "light") ?: JSONObject()
    private fun color(name: String, dark: Boolean): Int = palette(dark).optLong(name, when (name) {
        "ink" -> if (dark) 0xFFEAF2EF else 0xFF222D2B
        "muted" -> if (dark) 0xFFA7BAB4 else 0xFF667370
        "accent" -> if (dark) 0xFF8BD7C5 else 0xFF256C66
        "start" -> if (dark) 0xFF222835 else 0xFFEDF4EF
        else -> if (dark) 0xFF17312E else 0xFFE8E8F6
    }).toInt()
    private fun effective(dark: Boolean) = when (mode) { "dark" -> true; "light" -> false; else -> dark }
    fun text(views: RemoteViews, id: Int, role: String) = applyColor(views, id, "setTextColor", role)
    fun icon(views: RemoteViews, id: Int, role: String = "accent") = applyColor(views, id, "setColorFilter", role)
    private fun applyColor(views: RemoteViews, id: Int, method: String, role: String) {
        if (Build.VERSION.SDK_INT >= 31) views.setColorInt(id, method, color(role, effective(false)), color(role, effective(true)))
        else views.setInt(id, method, color(role, effective(systemDark)))
    }
    fun surface(views: RemoteViews, id: Int, normal: Int, light: Int, dark: Int) {
        views.setInt(id, "setBackgroundResource", when (mode) { "light" -> light; "dark" -> dark; else -> normal })
    }
    fun decorate(views: RemoteViews, captureOnly: Boolean, smallCapture: Boolean = false) {
        surface(views, R.id.widget_root, R.drawable.widget_background, R.drawable.widget_background_light, R.drawable.widget_background_dark)
        if (!smallCapture) surface(views, R.id.widget_capture, R.drawable.widget_button, R.drawable.widget_button_light, R.drawable.widget_button_dark)
        text(views, R.id.widget_brand, "muted")
        text(views, R.id.widget_capture, "accent")
        val light = Icon.createWithBitmap(backdrop(effective(false)))
        val dark = Icon.createWithBitmap(backdrop(effective(true)))
        if (Build.VERSION.SDK_INT >= 31) views.setIcon(R.id.widget_backdrop, "setImageIcon", light, dark)
        else views.setImageViewIcon(R.id.widget_backdrop, if (effective(systemDark)) dark else light)
        if (!captureOnly) {
            surface(views, R.id.widget_configure, R.drawable.widget_configure, R.drawable.widget_configure_light, R.drawable.widget_configure_dark)
            icon(views, R.id.widget_configure)
            text(views, R.id.widget_title, "ink")
            for (id in listOf(R.id.widget_count, R.id.widget_empty, R.id.widget_updated)) text(views, id, "muted")
            text(views, R.id.widget_more, "accent")
        }
    }
    private fun backdrop(dark: Boolean): Bitmap {
        // A small gradient scales smoothly and keeps RemoteViews well below IPC limits.
        val bitmap = Bitmap.createBitmap(192, 256, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, 192f, 256f, color("start", dark), color("end", dark), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, 192f, 256f, paint)
        paint.shader = null
        val accent = color("accent", dark)
        paint.color = Color.argb(if (dark) 15 else 10, Color.red(accent), Color.green(accent), Color.blue(accent))
        canvas.drawCircle(180f, 32f, 108f, paint)
        canvas.drawCircle(-12f, 244f, 96f, paint)
        return bitmap
    }
}
