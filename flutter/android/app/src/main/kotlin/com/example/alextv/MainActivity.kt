package com.example.alextv

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.example.alextv/player"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Launch the native full-screen player Activity. Playback runs entirely
        // outside Flutter (no platform view / hybrid composition), which keeps
        // the controls smooth on low-power TV hardware.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrEmpty()) {
                            result.error("no_url", "Missing stream url", null)
                            return@setMethodCallHandler
                        }
                        val intent = Intent(this, PlayerActivity::class.java).apply {
                            putExtra("url", url)
                            putExtra("ext", call.argument<String>("ext") ?: "")
                            putExtra("title", call.argument<String>("title") ?: "")
                            // Web (FebBox) subtitles resolved by Dart: parallel
                            // label/URL lists, attached to the media item natively.
                            putStringArrayListExtra(
                                "subLabels",
                                ArrayList(call.argument<List<String>>("subLabels") ?: emptyList()),
                            )
                            putStringArrayListExtra(
                                "subUrls",
                                ArrayList(call.argument<List<String>>("subUrls") ?: emptyList()),
                            )
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
