package app.salu.salu_remote

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val screenChannel = "app.salu.remote/screen"
    private val linkChannel = "app.salu.remote/deep_link"

    // The most recent salu:// link the OS handed to us. `getInitial` reads it
    // so a cold start from a scanned QR is never lost to the Dart/engine race.
    @Volatile
    private var lastLink: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        val on = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, linkChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitial" -> result.success(lastLink)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sendLink(intent?.data)
    }

    // launchMode is singleTop, so a second QR scan while the app is open
    // arrives here rather than in onCreate.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sendLink(intent.data)
    }

    private fun sendLink(data: Uri?) {
        if (data == null) return
        lastLink = data.toString()
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return
        MethodChannel(messenger, linkChannel).invokeMethod("onLink", lastLink)
    }
}
