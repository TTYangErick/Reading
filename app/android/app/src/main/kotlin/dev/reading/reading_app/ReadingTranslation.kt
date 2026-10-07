package dev.reading.reading_app

import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** One active native operation. No sentence is sent to a cloud translation API. */
class ReadingTranslation : MethodChannel.MethodCallHandler {
    private var active: Int? = null
    private var reply: MethodChannel.Result? = null
    private var client: Translator? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("id")
        if (call.method == "cancel") {
            if (id == active) finish(id, "cancelled")
            result.success(null)
            return
        }
        if (call.method !in listOf("status", "prepare", "translate")) {
            result.notImplemented(); return
        }
        // V1 product supports English to simplified Chinese only.
        if (id == null || call.argument<String>("from") != "en" || call.argument<String>("to") != "zh-Hans") {
            result.error("unsupported", null, null); return
        }
        if (active != null) { result.error("busy", null, null); return }
        val text = call.argument<String>("text")
        if (call.method == "translate" && (text.isNullOrBlank() || text.length > 4000)) {
            result.error("invalidText", null, null); return
        }
        active = id
        reply = result
        RemoteModelManager.getInstance().getDownloadedModels(TranslateRemoteModel::class.java)
            .addOnSuccessListener { models ->
                if (active != id) return@addOnSuccessListener
                // English is implicit in ML Kit's translation models.
                val ready = models.any { it.language == TranslateLanguage.CHINESE }
                if (call.method == "status") {
                    finish(id, value = if (ready) "ready" else "downloadRequired")
                } else if (call.method == "translate" && !ready) {
                    finish(id, "downloadRequired")
                } else {
                    val translator = Translation.getClient(TranslatorOptions.Builder()
                        .setSourceLanguage(TranslateLanguage.ENGLISH)
                        .setTargetLanguage(TranslateLanguage.CHINESE).build())
                    client = translator
                    if (call.method == "prepare") {
                        translator.downloadModelIfNeeded(DownloadConditions.Builder().requireWifi().build())
                            .addOnSuccessListener { finish(id) }
                            .addOnFailureListener { finish(id, "downloadFailed") }
                    } else {
                        translator.translate(text!!)
                            .addOnSuccessListener { translated -> finish(id, value = translated) }
                            .addOnFailureListener { finish(id, "translationFailed") }
                    }
                }
            }
            .addOnFailureListener { finish(id, "unavailable") }
    }

    private fun finish(id: Int?, error: String? = null, value: Any? = null) {
        if (id == null || id != active) return
        val result = reply
        reply = null
        active = null
        client?.close()
        client = null
        if (error == null) result?.success(value) else result?.error(error, null, null)
    }

    fun close() { finish(active, "cancelled") }
}
