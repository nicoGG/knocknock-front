package cl.nocknock.app

import android.app.Activity
import android.os.Bundle
import android.widget.FrameLayout

/** Native RemoteViews host for instrumentation; excluded from release builds. */
class WidgetPreviewActivity : Activity() {
    lateinit var surface: FrameLayout
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        surface = FrameLayout(this).apply { setBackgroundColor(0xFF101719.toInt()) }
        setContentView(surface)
    }
}
