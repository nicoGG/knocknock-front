package cl.nocknock.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.ArrayDeque
import java.util.concurrent.Executors

/** Read the provider's content stream while the temporary OS grant is valid.
 * Never interpret a provider-supplied filename or URI as a filesystem path. */
internal class ReceiptShareReceiver(private val context: Context) {
    private val waiting = ArrayDeque<Pair<Uri?, String>>()
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val folder get() = File(context.cacheDir, "incoming-receipts")
    private var channel: MethodChannel? = null

    @Suppress("DEPRECATION")
    fun intercept(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return
        val type = intent.type.orEmpty()
        // Do not pass untrusted attachment paths to the generic text-share plugin.
        intent.removeExtra(Intent.EXTRA_STREAM)
        if (!type.startsWith("image/") && type != "application/pdf" && type != "application/octet-stream") return
        intent.removeExtra(Intent.EXTRA_TEXT)
        waiting.add((uri.takeIf { it.scheme == "content" }) to type)
        channel?.invokeMethod("available", null)
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "cl.nocknock/incoming_receipts").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "next" -> {
                        val item = waiting.poll()
                        if (item == null) result.success(null)
                        else worker.execute {
                            val value = try { copy(item.first, item.second) }
                                catch (_: Exception) { mapOf("error" to "No se pudo leer la boleta compartida.") }
                            main.post { result.success(value) }
                        }
                    }
                    "release" -> {
                        val name = call.arguments as? String
                        if (name != null && name == File(name).name) File(folder, name).delete()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun copy(uri: Uri?, declaredType: String): Map<String, String> {
        requireNotNull(uri)
        val resolver = context.contentResolver
        val type = resolver.getType(uri)?.takeUnless { it == "application/octet-stream" } ?: declaredType
        val pdf = type == "application/pdf" || type == "application/octet-stream"
        val ext = if (pdf) "pdf" else MimeTypeMap.getSingleton().getExtensionFromMimeType(type)
        require(pdf || (type.startsWith("image/") && ext != null))
        val limit = if (pdf) 5 * 1024 * 1024 else 25 * 1024 * 1024
        folder.mkdirs()
        val target = File.createTempFile("boleta-", ".$ext", folder)
        try {
            resolver.openInputStream(uri)!!.use { input ->
                target.outputStream().use { out ->
                    val buffer = ByteArray(64 * 1024)
                    var total = 0
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > limit) {
                            target.delete()
                            return mapOf("error" to "El archivo supera el límite de ${limit / 1024 / 1024} MB.")
                        }
                        out.write(buffer, 0, count)
                    }
                }
            }
            return mapOf("path" to target.absolutePath, "name" to target.name)
        } catch (e: Exception) {
            target.delete()
            throw e
        }
    }

    fun close() {
        channel?.setMethodCallHandler(null)
        channel = null
        worker.shutdown()
    }
}
