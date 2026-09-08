package org.evelocalstation.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "eve_local_station/local_storage").setMethodCallHandler { call, result ->
            when (call.method) {
                "documentsPath" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
    }
}
