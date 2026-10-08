package dev.reading.reading_app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

class MainActivity : FlutterActivity() {
    private var imports: ReadingImports? = null
    private var immersive = false
    private val translation = ReadingTranslation()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        imports = ReadingImports.get(applicationContext).also {
            it.attach(MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.reading/imports"))
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.reading/translation")
            .setMethodCallHandler(translation)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.reading/system_ui")
            .setMethodCallHandler { call, result ->
                if (call.method == "immersive") {
                    immersive = call.arguments == true
                    applySystemBars()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) imports?.accept(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        imports?.accept(intent)
    }

    private fun applySystemBars() {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (immersive) controller.hide(WindowInsetsCompat.Type.systemBars())
        else controller.show(WindowInsetsCompat.Type.systemBars())
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.reading/translation")
            .setMethodCallHandler(null)
        translation.close()
        imports?.detach()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applySystemBars()
    }
}
