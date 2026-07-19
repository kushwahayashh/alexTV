package com.example.alextv

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

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
                            // Stable backend path the Library keys watch-progress
                            // on. Blank/absent for TMDB playback (untracked).
                            putExtra("mediaPath", call.argument<String>("mediaPath") ?: "")
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
                    "getProgress" -> {
                        // Return saved watch-progress for the given backend paths
                        // as a JSON string: { path: {progress, positionMs, ...} }.
                        val paths = call.argument<List<String>>("paths") ?: emptyList()
                        val payload = PlaybackProgressStore.getProgressPayload(
                            this,
                            JSONArray(paths).toString(),
                        )
                        result.success(payload)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
