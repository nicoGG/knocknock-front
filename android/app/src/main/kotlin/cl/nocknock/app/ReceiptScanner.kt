package cl.nocknock.app

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Bundled Latin model: receipt images are processed on the device. */
object ReceiptScanner {
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "cl.nocknock/receipt_scanner").setMethodCallHandler { call, result ->
            if (call.method != "recognize") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.arguments as? ByteArray
            if (bytes == null || bytes.isEmpty() || bytes.size > 25 * 1024 * 1024) {
                result.error("RECEIPT_IMAGE", "Imagen inválida", null)
                return@setMethodCallHandler
            }
            var temporary: File? = null
            try {
                val file = File.createTempFile("receipt-", ".img", context.cacheDir)
                temporary = file
                file.writeBytes(bytes)
                val image = InputImage.fromFilePath(context, Uri.fromFile(file))
                val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                recognizer.process(image)
                    .addOnSuccessListener { text ->
                        // Keep reading order across columns by grouping lines at similar heights.
                        val lines = text.textBlocks.flatMap { it.lines }.sortedBy { it.boundingBox?.top ?: 0 }
                        val rows = mutableListOf<MutableList<com.google.mlkit.vision.text.Text.Line>>()
                        for (line in lines) {
                            val bounds = line.boundingBox
                            val row = rows.lastOrNull()
                            val anchor = row?.firstOrNull()?.boundingBox
                            if (row != null && bounds != null && anchor != null && kotlin.math.abs(bounds.centerY() - anchor.centerY()) <= maxOf(bounds.height(), anchor.height()) / 2) {
                                row.add(line)
                            } else rows.add(mutableListOf(line))
                        }
                        result.success(rows.joinToString("\n") { row -> row.sortedBy { it.boundingBox?.left ?: 0 }.joinToString(" ") { it.text } })
                    }
                    .addOnFailureListener { result.error("RECEIPT_OCR", "No se pudo leer la boleta", null) }
                    .addOnCompleteListener { recognizer.close(); file.delete() }
            } catch (_: Exception) {
                temporary?.delete()
                result.error("RECEIPT_OCR", "No se pudo leer la boleta", null)
            }
        }
    }
}
