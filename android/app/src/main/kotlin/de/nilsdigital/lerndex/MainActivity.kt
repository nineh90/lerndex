package de.nilsdigital.lerndex

import android.os.Build
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Spracheingabe nur, wenn Android sie auf dem Gerät erkennt (ohne
        // Google-Server, siehe lib/src/features/stt/stt_provider.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.nilsdigital.lerndex/speech")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isOnDeviceRecognitionAvailable" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            SpeechRecognizer.isOnDeviceRecognitionAvailable(this),
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
