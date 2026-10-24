package cl.nocknock.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity() {
    private var widgetChannel: MethodChannel? = null
    private var pendingWidgetAction: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ReceiptScanner.register(this, flutterEngine.dartExecutor.binaryMessenger)
        captureWidgetAction(intent)
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cl.nocknock/home_widgets").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "publish" -> { WidgetStore.publish(this, JSONObject(call.arguments as String)); result.success(null) }
                        "readSnapshot" -> result.success(WidgetStore.read(this).optJSONObject("snapshot")?.toString())
                        "readQueue" -> result.success((WidgetStore.read(this).optJSONArray("queue") ?: org.json.JSONArray()).toString())
                        "acknowledge" -> { WidgetStore.acknowledge(this, call.arguments as String); result.success(null) }
                        "takeAction" -> { result.success(pendingWidgetAction); pendingWidgetAction = null }
                        "requestPin" -> {
                            val manager = AppWidgetManager.getInstance(this)
                            val provider = when (call.argument<String>("kind")) {
                                "summary" -> SummaryWidget::class.java
                                "upcoming" -> UpcomingWidget::class.java
                                "expanded" -> ExpandedListWidget::class.java
                                "capture" -> QuickCaptureWidget::class.java
                                else -> NockNockWidget::class.java
                            }
                            result.success(Build.VERSION.SDK_INT >= 26 && manager.isRequestPinAppWidgetSupported &&
                                manager.requestPinAppWidget(ComponentName(this, provider), null, null))
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) { result.error("WIDGET_STORAGE", "No se pudo actualizar el widget", null) }
            }
        }
    }
    private fun captureWidgetAction(intent: Intent?) {
        val action = intent?.getStringExtra("widgetAction") ?: return
        pendingWidgetAction = mapOf("action" to action, "owner" to (intent.getStringExtra("owner") ?: "guest"),
            "boardId" to (intent.getStringExtra("boardId") ?: ""), "noteId" to (intent.getStringExtra("noteId") ?: ""))
        intent.removeExtra("widgetAction")
        intent.data = null
    }
    override fun onNewIntent(intent: Intent) {
        captureWidgetAction(intent)
        super.onNewIntent(intent)
        widgetChannel?.invokeMethod("actionAvailable", null)
    }
}
