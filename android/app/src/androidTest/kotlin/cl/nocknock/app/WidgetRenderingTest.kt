package cl.nocknock.app

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class WidgetRenderingTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private fun state(mode: String = "system", hidden: Boolean = false): JSONObject {
        val rows = JSONArray()
        for (i in 1..9) rows.put(JSONObject().put("id", "note-$i").put("boardId", "home").put("title", listOf("Recordatorios diarios", "Mandar correo smarfit", "Comprar inyección martes", "Devolver zapatillas", "Retirar sábanas Falabella")[(i - 1) % 5]).put("completed", i in 2..4).put("canComplete", i != 1))
        val list = JSONObject().put("listId", "home").put("title", "Guaguas 👶").put("rows", rows)
        val snapshot = JSONObject().put("owner", "guest").put("title", "Hoy").put("hidden", hidden).put("catalog", JSONArray().put(list)).put("updatedAt", 1792782000000L).put("theme", JSONObject().put("mode", mode))
        return JSONObject().put("snapshot", snapshot).put("configs", JSONObject().put("42", JSONObject().put("owner", "guest").put("board", "home")))
    }
    private fun render(night: Boolean, mode: String = "system", height: Int = 440, capture: Boolean = false, hidden: Boolean = false, width: Int = 320, pendingOnly: Boolean = false): View {
        val config = Configuration(context.resources.configuration).apply { uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or if (night) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO }
        val themed = context.createConfigurationContext(config)
        val options = Bundle().apply { putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, height); putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, width) }
        val views = NockNockWidget.buildViews(themed, 42, capture, state(mode, hidden), options, pendingOnly)
        var root: View? = null
        instrumentation.runOnMainSync {
            root = views.apply(themed, FrameLayout(themed))
            val density = themed.resources.displayMetrics.density
            root!!.measure(View.MeasureSpec.makeMeasureSpec((width * density).toInt(), View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec((height * density).toInt(), View.MeasureSpec.EXACTLY))
            root!!.layout(0, 0, root!!.measuredWidth, root!!.measuredHeight)
        }
        return root!!
    }
    @Test fun layoutsInflateWithNativeCheckboxIconsAndAccurateCounts() {
        for (night in listOf(false, true)) {
            val root = render(night)
            assertTrue(root.findViewById<View>(R.id.widget_check) is ImageButton)
            assertEquals("6 pendientes · 3 completadas", root.findViewById<TextView>(R.id.widget_count).text.toString())
            assertTrue(root.findViewById<TextView>(R.id.widget_note_title).currentTextColor != root.findViewById<TextView>(R.id.widget_updated).currentTextColor)
            assertEquals(View.VISIBLE, root.findViewById<View>(R.id.widget_more).visibility)
            assertTrue(root.findViewById<View>(R.id.widget_check).isClickable)
            assertNotNull(render(night, capture = true).findViewById<View>(R.id.widget_capture))
        }
    }
    @Test fun systemNightAndAppOverridesResolveWhenRemoteViewsAreApplied() {
        val light = render(false).findViewById<TextView>(R.id.widget_title).currentTextColor
        val dark = render(true).findViewById<TextView>(R.id.widget_title).currentTextColor
        assertNotEquals(light, dark)
        assertEquals(dark, render(false, mode = "dark").findViewById<TextView>(R.id.widget_title).currentTextColor)
        assertEquals(light, render(true, mode = "light").findViewById<TextView>(R.id.widget_title).currentTextColor)
    }
    @Test fun compactAndPrivateWidgetsKeepActionsAndPrivacy() {
        val root = render(true, height = 280)
        val capture = root.findViewById<View>(R.id.widget_capture)
        assertTrue(capture.bottom <= root.height)
        val hidden = render(true, hidden = true)
        assertEquals("Contenido oculto", hidden.findViewById<TextView>(R.id.widget_count).text.toString())
        assertNull(hidden.findViewById<View>(R.id.widget_check))
    }
    @Test fun allSizesKeepCaptureVisibleAndUseAppropriateLayouts() {
        val examples = listOf(Triple(110, 110, false), Triple(250, 130, false), Triple(280, 280, false), Triple(320, 440, false), Triple(40, 40, true))
        for (night in listOf(false, true)) for ((width, height, captureOnly) in examples) {
            val root = render(night, height = height, width = width, capture = captureOnly) as android.view.ViewGroup
            val action = root.findViewById<View>(R.id.widget_capture)
            val bounds = android.graphics.Rect(0, 0, action.width, action.height)
            root.offsetDescendantRectToMyCoords(action, bounds)
            assertTrue("$width x $height: capture must fit", bounds.bottom <= root.height && bounds.right <= root.width && bounds.top >= 0)
            assertTrue(action.width > 0 && action.height > 0)
        }
        assertEquals(WidgetSizeLayout.SUMMARY, WidgetSizeLayout.choose(110, 110, false))
        assertEquals(WidgetSizeLayout.WIDE, WidgetSizeLayout.choose(250, 130, false))
        assertEquals(WidgetSizeLayout.COMPACT, WidgetSizeLayout.choose(180, 280, false))
        assertEquals(WidgetSizeLayout.FULL, WidgetSizeLayout.choose(320, 440, false))
    }
    @Test fun launcherOffersFiveWidgetsAndUpcomingSkipsCompletedRows() {
        val installed = AppWidgetManager.getInstance(context).installedProviders.filter { it.provider.packageName == context.packageName }
        assertEquals(5, installed.size)
        val root = render(true, pendingOnly = true)
        val rows = root.findViewById<android.widget.LinearLayout>(R.id.widget_rows)
        for (i in 0 until rows.childCount) {
            val title = rows.getChildAt(i).findViewById<TextView>(R.id.widget_note_title)
            assertEquals(0, title.paintFlags and android.graphics.Paint.STRIKE_THRU_TEXT_FLAG)
        }
        assertTrue(rows.childCount > 0)
    }
    @Test fun saveLightAndDarkNativePreviews() {
        val activity = instrumentation.startActivitySync(Intent(context, WidgetPreviewActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as WidgetPreviewActivity
        try {
            val examples = listOf(Triple(110, 110, false), Triple(250, 130, false), Triple(280, 280, false), Triple(320, 440, false), Triple(40, 40, true))
            for (night in listOf(false, true)) for ((width, height, captureOnly) in examples) {
                val root = render(night, height = height, width = width, capture = captureOnly)
                instrumentation.runOnMainSync {
                    activity.surface.removeAllViews()
                    activity.surface.addView(root, FrameLayout.LayoutParams(root.measuredWidth, root.measuredHeight, Gravity.CENTER))
                }
                instrumentation.waitForIdleSync()
                android.os.SystemClock.sleep(150)
                val screenshot = instrumentation.uiAutomation.takeScreenshot()
                val location = IntArray(2)
                instrumentation.runOnMainSync { root.getLocationOnScreen(location) }
                val bitmap = Bitmap.createBitmap(screenshot, location[0], location[1], root.width, root.height)
                val output = File(context.getExternalFilesDir(null), "widget-previews/widget-${width}x${height}-${if (night) "dark" else "light"}.png")
                output.parentFile!!.mkdirs()
                output.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
                screenshot.recycle()
            }
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }
}
