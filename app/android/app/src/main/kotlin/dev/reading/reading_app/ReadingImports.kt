package dev.reading.reading_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.core.content.IntentCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Process-local inbox. Only private bounded copies cross the Flutter bridge. */
class ReadingImports private constructor(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private var instance: ReadingImports? = null
        fun get(context: Context): ReadingImports = instance ?: ReadingImports(context.applicationContext).also { instance = it }
    }
    private class Entry(val id: String = UUID.randomUUID().toString()) {
        var name = "文件"
        var ready = false
        var error: String? = null
        var path: String? = null
        val cancelled = AtomicBoolean(false)
    }
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val entries = linkedMapOf<String, Entry>() // Main-thread ownership.
    private var overflow: Entry? = null
    private var channel: MethodChannel? = null
    private val folder = File(context.cacheDir, "received-books").apply {
        // Constructed once per process; no user library files live here.
        deleteRecursively()
        mkdirs()
    }

    fun attach(value: MethodChannel) {
        channel = value
        value.setMethodCallHandler(this)
    }
    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }
    private fun changed() { channel?.invokeMethod("changed", null) }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pending" -> result.success((entries.values.filter { !it.cancelled.get() } + listOfNotNull(overflow)).map {
                mapOf("id" to it.id, "name" to it.name, "ready" to it.ready, "path" to it.path, "error" to it.error)
            })
            "release" -> {
                val id = call.arguments as? String
                if (overflow?.id == id) overflow = null
                entries[id]?.let {
                    it.cancelled.set(true)
                    if (it.ready) {
                        it.path?.let { path -> File(path).delete() }
                        entries.remove(id)
                    }
                    // An in-flight copy retains its capacity until its worker exits.
                }
                result.success(null)
                changed()
            }
            else -> result.notImplemented()
        }
    }

    fun accept(intent: Intent?) {
        if (intent == null || intent.action !in listOf(Intent.ACTION_VIEW, Intent.ACTION_SEND, Intent.ACTION_SEND_MULTIPLE)) return
        if (entries.size >= 4) {
            if (overflow == null) overflow = Entry().apply { name = "未接收的文件"; ready = true; error = "queueFull" }
            changed()
            return
        }
        val entry = Entry()
        entries[entry.id] = entry
        changed()
        val uri = try {
            when {
                intent.action == Intent.ACTION_SEND_MULTIPLE || (intent.clipData?.itemCount ?: 0) > 1 -> null
                intent.action == Intent.ACTION_VIEW -> intent.data
                else -> IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                    ?: intent.clipData?.takeIf { it.itemCount == 1 }?.getItemAt(0)?.uri
            }
        } catch (_: RuntimeException) { null }
        // An exported receiver must not open arbitrary file:// paths in our sandbox.
        if (uri?.scheme != "content") {
            entry.ready = true
            entry.error = "unsupported"
            changed()
            return
        }
        val suppliedType = intent.type
        worker.execute {
            val target = File(folder, entry.id)
            var name = "文件"
            var error: String? = null
            try {
                val resolver = context.contentResolver
                var declaredSize: Long? = null
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val ni = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (ni >= 0 && !cursor.isNull(ni)) name = cursor.getString(ni)
                        val si = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (si >= 0 && !cursor.isNull(si)) declaredSize = cursor.getLong(si)
                    }
                }
                name = name.substringAfterLast('/').substringAfterLast('\\').replace(Regex("[\\p{Cntrl}]"), "").ifBlank { "文件" }
                if (!name.contains('.')) {
                    name += when (suppliedType ?: resolver.getType(uri)) {
                        "application/epub+zip" -> ".epub"
                        "text/plain" -> ".txt"
                        else -> ""
                    }
                }
                val limit = when (name.substringAfterLast('.', "").lowercase()) {
                    "epub" -> 50L * 1024 * 1024
                    "txt" -> 20L * 1024 * 1024
                    else -> throw ImportFailure("unsupported")
                }
                // Keep the validated suffix when shortening a long display name.
                if (name.length > 160) name = name.take(150) + "." + name.substringAfterLast('.').lowercase()
                if ((declaredSize ?: 0) > limit) throw ImportFailure("tooLarge")
                if (entry.cancelled.get()) throw ImportFailure("cancelled")
                resolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var total = 0L
                        while (true) {
                            if (entry.cancelled.get()) throw ImportFailure("cancelled")
                            val count = input.read(buffer)
                            if (count == -1) break
                            total += count
                            if (total > limit) throw ImportFailure("tooLarge")
                            output.write(buffer, 0, count)
                        }
                    }
                } ?: throw ImportFailure("unreadable")
            } catch (failure: ImportFailure) {
                error = failure.code
            } catch (_: Exception) {
                error = "unreadable"
            }
            if (error != null || entry.cancelled.get()) target.delete()
            val finalName = name
            val finalError = error
            main.post {
                if (entry.cancelled.get()) {
                    target.delete()
                    entries.remove(entry.id)
                } else {
                    entry.name = finalName
                    entry.error = finalError
                    entry.path = if (finalError == null) target.path else null
                    entry.ready = true
                }
                changed()
            }
        }
    }
    private class ImportFailure(val code: String) : Exception()
}
